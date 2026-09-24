/* ===========================================================================
   AgendaPro — o que faltava no cadastro de produto

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/produto-cadastro.test.mjs

   Três coisas, vindas da comparação com os prints do concorrente:

     1. o PREÇO pode ficar escondido sem o produto sumir da loja;
     2. cada PROFISSIONAL pode ter comissão própria naquele produto;
     3. o estoque passa a ter HISTÓRICO.

   ── ⚠ A DO MEIO É A QUE PRECISA DE MAIS CUIDADO ────────────────────────────
   Ela mexe na `comissao_de()`, e o que essa função devolve é CONGELADO dentro
   da comanda pelo gatilho. Quer dizer: um erro ali não aparece na tela. Ele
   aparece no acerto do mês, semanas depois, quando a profissional conferir o
   que recebeu — e aí já foram dezenas de comandas.

   Por isso metade deste arquivo é sobre a ESCADA: que o degrau novo funciona,
   e principalmente que ele não mexeu nos degraus que já existiam.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
const secao = t => console.log('\n' + t);

function novaAba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(path.join(RAIZ,'dados.js'),'utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`pc-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];

/* Dois produtos, os dois na loja. O shampoo é o que vai esconder o preço; a
   máscara é a testemunha de que nada vaza para quem não mexeu. */
const shampoo = await dona.inserir('produtos', { salaoId: SALAO, nome:'Shampoo',
  preco:45, custo:20, estoque:10, comissaoPct:10, ativo:true, vendaOnline:true });
const mascara = await dona.inserir('produtos', { salaoId: SALAO, nome:'Mascara',
  preco:60, custo:30, estoque:5, comissaoPct:10, ativo:true, vendaOnline:true });
ok('salão criado, com dois produtos na loja');

const daLoja = async () => {
  const v = await dona.chamar('vitrine', { p_slug: SLUG });
  return (Array.isArray(v) ? v[0] : v).produtos;
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ O PREÇO ESCONDIDO

   E, antes dele, o estado de todo produto que já existe: preço à mostra.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O preço na loja');

const antes = await daLoja();
verdade('sem ninguém mexer, os dois produtos mostram o preço',
  antes.every(p => p.preco != null), JSON.stringify(antes.map(p => [p.nome, p.preco])));

await dona.atualizar('produtos', shampoo.id, { precoVisivel: false });
const depois = await daLoja();
const sh = depois.find(p => p.nome === 'Shampoo');
const ms = depois.find(p => p.nome === 'Mascara');

/* ⚠ O PREÇO NÃO PODE SAIR DO BANCO. Mandar o valor e pedir para a tela não
   mostrar é publicá-lo assim mesmo: ele viaja pela rede e aparece para quem
   abrir o inspetor. Esconder tem que ser esconder. */
igual('escondendo o preço do shampoo, ele vem NULO da vitrine', sh.preco, null);
verdade('e o produto continua na loja, com nome e foto',
  sh.nome === 'Shampoo' && 'descricao' in sh, JSON.stringify(sh));
igual('a máscara, que ninguém tocou, continua com o preço', Number(ms.preco), 60);

/* ══════════════════════════════════════════════════════════════════════════
   2 — ⚠ A ESCADA DA COMISSÃO

   Quatro degraus, e o novo é o primeiro. O que mais importa aqui não é que o
   degrau novo funcione — é que os antigos continuem respondendo igual.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A comissão do produto, degrau por degrau');

/* ⚠ PELO CAMINHO DE VERDADE, e não chamando a `comissao_de()` direto.

   Ela é fechada para todo mundo, de propósito: quem a chama é o gatilho que
   congela a taxa dentro do item, e ele é `security definer`. A primeira
   versão deste teste a chamava pelo PostgREST e levou "permission denied" —
   o que é a função funcionando, não falhando.

   E medir pelo item é melhor mesmo: é exatamente o número que vai para o
   acerto do mês. Testar a função por fora provaria que a escada está certa e
   não provaria que ela CHEGA na comanda. */
const comandaDeTeste = { id: null };
const leitura = async (produto, profissional) => {
  if(!comandaDeTeste.id){
    const c = await dona.inserir('clientes', { salaoId: SALAO,
      nome:'Teste Comissao', telefone:'11977776666' });
    comandaDeTeste.id = (await dona.inserir('comandas',
      { salaoId: SALAO, clienteId: c.id })).id;
  }
  const it = await dona.inserir('comanda_itens', {
    comandaId: comandaDeTeste.id, tipo:'produto', produtoId: produto,
    profissionalId: profissional, descricao:'medida', qtd:1, precoUnit:100 });
  await dona.apagar('comanda_itens', it.id);
  return [Number(it.comissaoPct || 0), Number(it.comissaoFixa || 0)];
};

igual('sem exceção nenhuma, vale a comissão do produto (o catálogo)',
  await leitura(shampoo.id, prof.id), [10, 0]);

await dona.inserir('produtos_profissionais', { produtoId: shampoo.id,
  profissionalId: prof.id, comissaoPct: 30, comissaoFixa: null });
igual('com exceção, o par ganha do catálogo',
  await leitura(shampoo.id, prof.id), [30, 0]);

/* ⚠ E SÓ PARA AQUELE PRODUTO. Exceção que vazasse para os outros faria o
   dono pagar 30% em tudo por ter escrito 30% num lugar. */
igual('a máscara, sem exceção, continua no catálogo',
  await leitura(mascara.id, prof.id), [10, 0]);

/* ⚠ LINHA QUE NÃO DIZ NADA NÃO É DEGRAU. Se uma linha com os dois campos
   nulos parasse a escada, ela devolveria nulo — zero por outro caminho — e a
   pessoa perderia a comissão do produto sem ninguém saber por quê. */
await dona.inserir('produtos_profissionais', { produtoId: mascara.id,
  profissionalId: prof.id, comissaoPct: null, comissaoFixa: null });
igual('linha vazia no par é ignorada, e o catálogo responde',
  await leitura(mascara.id, prof.id), [10, 0]);

// E o valor fixo, que soma com a porcentagem.
await dona.atualizar('produtos_profissionais',
  (await dona.lista('produtos_profissionais', {}))
    .find(x => x.produtoId === shampoo.id).id,
  { comissaoPct: 0, comissaoFixa: 5 });
igual('o par também sabe dizer valor fixo',
  await leitura(shampoo.id, prof.id), [0, 5]);

/* ⚠ E A ESCADA DO SERVIÇO NÃO PODE TER MUDADO. A `comissao_de()` foi
   reescrita inteira para ganhar o degrau novo — e reescrever inteira é
   exatamente onde se perde uma linha sem ninguém notar. */
const serv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true,
  comissaoPct: 40, comissaoFixa: null });
const doServico = async () => {
  const it = await dona.inserir('comanda_itens', {
    comandaId: comandaDeTeste.id, tipo:'servico', servicoId: serv.id,
    profissionalId: prof.id, descricao:'medida', qtd:1, precoUnit:100 });
  await dona.apagar('comanda_itens', it.id);
  return [Number(it.comissaoPct || 0), Number(it.comissaoFixa || 0)];
};
igual('serviço sem exceção continua no catálogo dele', await doServico(), [40, 0]);
await dona.inserir('servicos_profissionais', { servicoId: serv.id,
  profissionalId: prof.id, comissaoPct: 55, comissaoFixa: null });
igual('e a exceção do serviço continua ganhando', await doServico(), [55, 0]);

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ O HISTÓRICO DO ESTOQUE

   O ponto delicado: a baixa da comanda e o ajuste à mão mexem na MESMA
   coluna. Registrar nos dois lugares contaria a venda duas vezes.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O histórico do estoque');

const hist = async pid => await dona.chamar('estoque_historico',
  { p_produto: pid, p_limite: 50 });

igual('produto recém-cadastrado não tem movimento nenhum',
  (await hist(mascara.id)).length, 0);

// Ajuste à mão: o dono contou a prateleira e digitou outro número.
await dona.atualizar('produtos', mascara.id, { estoque: 8 });
const h1 = await hist(mascara.id);
igual('o ajuste à mão vira uma linha', h1.length, 1);
igual('com o de e o para', [Number(h1[0].de), Number(h1[0].para)], [5, 8]);
igual('e o motivo certo', h1[0].motivo, 'ajuste');
verdade('e o nome de quem mexeu, não o uuid',
  h1[0].quem === 'Rita Alves', JSON.stringify(h1[0].quem));

/* ⚠ GRAVAR O MESMO NÚMERO POR CIMA NÃO É MOVIMENTO. O painel salva o produto
   inteiro a cada edição, então isto acontece o tempo todo — e sem esta guarda
   o histórico encheria de linhas de "8 → 8". */
await dona.atualizar('produtos', mascara.id, { estoque: 8, marca: 'Alguma' });
igual('salvar de novo sem mudar o estoque não cria linha',
  (await hist(mascara.id)).length, 1);

// A venda: uma comanda com o produto, fechada.
const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Maria Souza',
  telefone:'11988887777' });
const com = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: com.id, tipo:'produto',
  produtoId: mascara.id, descricao:'Mascara', qtd:2, precoUnit:60 });
await dona.inserir('pagamentos', { comandaId: com.id, forma:'dinheiro',
  valor:120 });
await dona.atualizar('comandas', com.id, { status:'fechada' });

const h2 = await hist(mascara.id);
console.log('      ' + JSON.stringify(h2.slice(0, 3)));
/* ⚠ UMA LINHA, E NÃO DUAS. É o defeito que o desenho evita: quem escreve o
   histórico é um gatilho só, na própria `produtos`. Se o 26_estoque também
   escrevesse, toda venda apareceria duplicada. */
igual('a venda vira UMA linha, e não duas', h2.length, 2);
igual('de 8 para 6', [Number(h2[0].de), Number(h2[0].para)], [8, 6]);
igual('e o motivo diz que foi venda', h2[0].motivo, 'venda');
verdade('e aponta a comanda', !!h2[0].comanda_id || h2[0].motivo === 'venda',
  JSON.stringify(h2[0]));

// Reabrir devolve, e o histórico conta isso.
await dona.atualizar('comandas', com.id, { status:'aberta' });
const h3 = await hist(mascara.id);
igual('reabrir a comanda vira outra linha', h3.length, 3);
igual('de volta de 6 para 8', [Number(h3[0].de), Number(h3[0].para)], [6, 8]);
igual('com o motivo da devolução', h3[0].motivo, 'devolucao');

/* ⚠ E O RÓTULO DE "VENDA" NÃO PODE GRUDAR NA CONEXÃO. O aviso que o
   26_estoque manda ao gatilho é local à transação. Sem isso, o próximo ajuste
   à mão — de qualquer salão, na mesma conexão — sairia rotulado como venda
   daquela comanda. */
await dona.atualizar('produtos', mascara.id, { estoque: 20 });
const h4 = await hist(mascara.id);
igual('o ajuste seguinte volta a ser "ajuste", e não "venda"',
  h4[0].motivo, 'ajuste');
igual('e sem comanda pendurada', h4[0].comanda_id ?? null, null);

/* ⚠ E QUEM NÃO É GESTÃO NÃO LÊ. O histórico mostra quanto o salão comprou e
   vendeu de cada coisa. */
const fora = novaAba();
await fora.criarConta({ email:`pcx-${marca}@teste.com`, senha:'outrasenhaboa',
  nome:'De Fora', telefone:'+5521' + (900000000 + (Date.now() % 89999999)) });
let barrou = false, recado = '';
try{
  await fora.chamar('estoque_historico', { p_produto: mascara.id, p_limite: 5 });
}catch(e){ barrou = true; recado = e.message; }
verdade('uma conta de fora leva recusa do banco', barrou, recado);

/* ══════════════════════════════════════════════════════════════════════════
   4 — A TELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('O cadastro, no painel');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                   hasTouch:true, isMobile:true });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', async d => { await d.accept(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1500);
const g = await p.$('.menu-botao');
if(g && await g.isVisible()){ await g.click(); await p.waitForTimeout(400); }
await p.click('#abas .aba[data-chave="produtos"]');
await p.waitForTimeout(1200);

await p.evaluate(id => abrirProduto(id), shampoo.id);
await p.waitForTimeout(700);

const naTela = await p.evaluate(() => ({
  temPrecoVisivel: !!document.getElementById('pPrecoVisivel'),
  marcado: (document.getElementById('pPrecoVisivel') || {}).checked,
  linhasPar: document.querySelectorAll('.ppar-in').length,
  temHistorico: !!document.querySelector('button[onclick^="verHistoricoEstoque"]'),
}));
console.log('      ' + JSON.stringify(naTela));
verdade('o interruptor do preço está no formulário', naTela.temPrecoVisivel);
verdade('e vem DESMARCADO, porque este produto está com o preço escondido',
  naTela.marcado === false, JSON.stringify(naTela.marcado));
verdade('a tabelinha de comissão por pessoa aparece', naTela.linhasPar >= 2,
  JSON.stringify(naTela.linhasPar));
verdade('e o botão do histórico também', naTela.temHistorico);

/* ⚠ E O PRODUTO NOVO NASCE COM O PREÇO À MOSTRA. Faltava esta linha, e a
   mutação mostrou: eu só abria o cadastro de um produto que JÁ EXISTE, então
   trocar o padrão do campo não reprovava nada.

   O defeito seria calado e caro: todo produto novo nasceria com o preço
   escondido, a loja mostraria "sob consulta" em tudo, e o dono não teria como
   ligar isso a uma caixinha que ele nunca desmarcou. */
await p.evaluate(() => { fecharModal(); abrirProduto(null); });
await p.waitForTimeout(600);
const novo = await p.evaluate(() => ({
  marcado: (document.getElementById('pPrecoVisivel') || {}).checked,
  // Sem produto ainda não há id: a tabelinha e o histórico explicam em vez de
  // aparecerem vazios.
  semPares: document.querySelectorAll('.ppar-in').length === 0,
  semHistorico: !document.querySelector('button[onclick^="verHistoricoEstoque"]'),
}));
console.log('      produto novo: ' + JSON.stringify(novo));
verdade('produto NOVO nasce com o preço à mostra', novo.marcado === true,
  JSON.stringify(novo));
verdade('e ainda sem tabelinha de comissão, porque não tem id', novo.semPares);
verdade('nem botão de histórico', novo.semHistorico);
await p.evaluate(() => fecharModal());
await p.waitForTimeout(300);

// O histórico abre e mostra o que o banco tem.
await p.evaluate(id => abrirProduto(id), mascara.id);
await p.waitForTimeout(600);
await p.click('button[onclick^="verHistoricoEstoque"]');
await p.waitForTimeout(2000);
const txtHist = await p.evaluate(() =>
  (document.getElementById('histEstoque') || {}).innerText || '');
verdade('o histórico abre com as movimentações',
  /ajuste|venda/.test(txtHist), txtHist.slice(0, 200));
verdade('e diz quem mexeu', /Rita/.test(txtHist), txtHist.slice(0, 200));

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
