/* ===========================================================================
   AgendaPro — o dashboard, do banco até o desenho

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/dashboard.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Criar um dashboard, veja as configurações" — com dois prints: faturamento
   anual em linha, faturamento semanal em barras, e uma janela para ativar,
   desativar e reordenar os cartões.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
   Três coisas, e as três falham CALADAS:

     1. O NÚMERO. Um dashboard que soma diferente do Caixa e dos Relatórios é
        pior que dashboard nenhum: o dono vê dois faturamentos para o mesmo
        mês e para de confiar no sistema inteiro. Por isso aqui o valor não é
        só "algum número" — é conferido contra o que foi vendido.

     2. A ESCOLHA VAZIA. Salão que nunca mexeu na configuração tem a lista
        vazia. Lido como "não quero nenhum", o dashboard nasceria em branco
        para todo mundo no dia da atualização. É a mesma armadilha dos
        destaques da capa.

     3. A DIVISÃO POR ZERO. Salão sem faturamento nenhum: todo valor é 0, o
        máximo é 0, e a proporção vira NaN. O caminho do SVG sai com "NaN" no
        meio e o gráfico não desenha — sem erro no console, sem nada na tela.
        É o estado de TODO salão no primeiro dia.
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
await dona.criarConta({ email:`dash-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
const serv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:100, ativo:true, aceitaOnline:true });
const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Clara',
  telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });
ok('salão de teste criado, ainda sem faturamento nenhum');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', e => erros.push(e.message));
p.on('console', c => { if(c.type()==='error') erros.push('console: ' + c.text()); });
p.on('dialog', async d => { await d.accept(); });

await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1500);

/* Em 412px a lateral é GAVETA: a aba existe, mas fica fora da tela até
   alguém abrir o menu. Clicar direto dá trinta segundos de espera e uma
   mensagem sobre "outside of the viewport" que não diz o que houve. */
const abrirDash = async (forcar) => {
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} });
  const gaveta = await p.$('.menu-botao');
  if(gaveta && await gaveta.isVisible()){
    await gaveta.click();
    await p.waitForTimeout(350);
  }
  await p.click('#abas .aba[data-chave="dashboard"]');
  if(forcar) await p.evaluate(() => carregarDash(true));

  /* ⚠ ESPERAR A CONDIÇÃO, E NÃO O RELÓGIO.

     Aqui havia `waitForTimeout(1600)`, e 1600ms é um palpite correndo contra
     uma ida ao banco. Rodando a suíte sozinha ele ganhava sempre; dentro do
     `tudo.sh`, com a máquina ocupada, perdeu — e as cinco verificações do
     primeiro bloco reprovaram todas juntas, dizendo "abriu sem cartão
     nenhum". Parecia o defeito que elas existem para pegar (lista vazia lida
     como "não quero nada"); era o teste olhando cedo demais.

     O `carregarDash()` escreve "Somando…" enquanto espera o banco, então dá
     para esperar o fim de verdade. Os dois estados de chegada — com cartão e
     o "Nenhum cartão escolhido" — passam por aqui, e um erro de banco
     também: nenhum deles diz Somando. */
  await p.waitForFunction(() => {
    const a = document.getElementById('dashCorpo');
    return a && a.innerText && !/Somando/.test(a.innerText);
  }, null, { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(400);
};
const naTela = () => p.evaluate(() => ({
  cartoes: [...document.querySelectorAll('#dashCorpo .dash-card')]
             .map(c => c.getAttribute('data-cartao')),
  titulos: [...document.querySelectorAll('#dashCorpo .dash-card h3')]
             .map(h => h.textContent.trim()),
  texto: (document.getElementById('dashCorpo') || {}).innerText || '',
}));

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ O SALÃO DO PRIMEIRO DIA

   Vem PRIMEIRO de propósito: é o estado de todo salão recém-criado, e é o
   único momento em que dá para medi-lo. Daqui para baixo o teste fatura.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O salão que ainda não faturou nada');

verdade('a aba Dashboard existe para a dona',
  await p.evaluate(() => !!document.querySelector('#abas .aba[data-chave="dashboard"]')));

await abrirDash();
const zerado = await naTela();
console.log('      ' + JSON.stringify(zerado.cartoes));

/* ⚠ SEM ESCOLHA NENHUMA, O DASHBOARD NÃO PODE ABRIR VAZIO. É o que
   aconteceria se a lista vazia do `cfg` fosse lida como "não quero nada". */
verdade('sem ter escolhido nada, ele mostra o padrão e não fica em branco',
  zerado.cartoes.length > 0,
  'abriu sem cartão nenhum — é a lista vazia lida como "nenhum"');
igual('que são os três do padrão, nesta ordem',
  zerado.cartoes, ['pendentes', 'fatAno', 'fatSemana']);

/* ⚠ A DIVISÃO POR ZERO. Com tudo zerado o máximo é zero, e a proporção vira
   NaN. O `d` do SVG sai com "NaN" no meio, o navegador descarta o caminho
   inteiro e o cartão fica em branco — sem erro nenhum no console. */
const svgZerado = await p.evaluate(() => {
  const l = document.querySelector('#dashCorpo .graf-linha');
  const a = document.querySelector('#dashCorpo .graf-area');
  return { linha: l ? l.getAttribute('d') : null,
           area:  a ? a.getAttribute('d') : null,
           barras: document.querySelectorAll('#dashCorpo .barra').length,
           tocos: [...document.querySelectorAll('#dashCorpo .barra')]
                    .filter(b => (b.style.height || '') !== '' && b.offsetHeight > 0).length };
});
console.log('      ' + JSON.stringify(svgZerado).slice(0, 180));
verdade('o gráfico do ano desenha mesmo com tudo zerado',
  !!svgZerado.linha && !/NaN|Infinity/.test(svgZerado.linha + svgZerado.area),
  'o caminho saiu com NaN — o navegador descarta e o cartão fica em branco');
igual('e a semana desenha os sete dias', svgZerado.barras, 7);
igual('todos com um toco visível, para nenhum dia sumir',
  svgZerado.tocos, 7);
verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));

/* ══════════════════════════════════════════════════════════════════════════
   2 — O NÚMERO TEM QUE SER O NÚMERO

   ⚠ Não basta "apareceu um valor". Um dashboard que soma diferente do Caixa
   é pior que nenhum: o dono vê dois faturamentos para o mesmo dia e para de
   confiar no sistema todo.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Duas vendas fechadas, e o dashboard tem que bater com elas');

// Duas comandas de R$ 100, fechadas hoje. O item entra ANTES do fechamento:
// comanda fechada é imutável, e é o gatilho `tg_comanda_travada` que garante.
for(let i = 0; i < 2; i++){
  const com = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
  await dona.inserir('comanda_itens', { comandaId: com.id, tipo:'servico',
    servicoId: serv.id, descricao:'Corte', qtd:1, precoUnit:100,
    profissionalId: prof.id });
  await dona.inserir('pagamentos', { comandaId: com.id, forma:'dinheiro', valor:100 });
  await dona.atualizar('comandas', com.id, { status:'fechada' });
}

/* ── ⚠ DUAS COMANDAS QUE NÃO PODEM CONTAR ────────────────────────────────
   R$ 999 e R$ 888 de propósito: valores que não se confundem com nada, para
   a falha ser legível se aparecerem.

   A primeira fica ABERTA. A segunda é fechada e depois CANCELADA — e é ela
   que importa, porque é o caso que quase escapou.

   Mutei a consulta tirando o `status = 'fechada'` e o teste continuou verde.
   Fui ver por quê: comanda aberta tem `fechada_em` nulo, então o filtro de
   DATA já a excluía sozinho, e o filtro de status parecia decorativo.

   Não é. O banco deixa cancelar uma comanda já fechada — medi —, e nesse
   caso o `fechada_em` CONTINUA preenchido. Quer dizer: sem o filtro de
   status, uma venda cancelada entraria no faturamento do dashboard e não no
   do Caixa. Dois números para o mesmo dia, e a diferença aparecendo só nos
   dias em que alguém cancelou algo. */
const aberta = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: aberta.id, tipo:'servico',
  servicoId: serv.id, descricao:'Corte', qtd:1, precoUnit:999,
  profissionalId: prof.id });

const cancelada = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: cancelada.id, tipo:'servico',
  servicoId: serv.id, descricao:'Corte', qtd:1, precoUnit:888,
  profissionalId: prof.id });
await dona.inserir('pagamentos', { comandaId: cancelada.id, forma:'dinheiro', valor:888 });
await dona.atualizar('comandas', cancelada.id, { status:'fechada' });
await dona.atualizar('comandas', cancelada.id, { status:'cancelada' });

const doBanco = await dona.chamar('painel_grafico', { p_salao: SALAO });
const d = Array.isArray(doBanco) ? doBanco[0] : doBanco;
const hojeNaSerie = (d.semana || [])[(d.semana || []).length - 1];
igual('o banco soma R$ 200 no dia de hoje — só as duas FECHADAS',
  Number(hojeNaSerie.valor), 200);
igual('e o último mês da série também', Number((d.ano || []).slice(-1)[0].valor), 200);
/* ⚠ Cobrado como "nada acima de 200", e não como "não aparece 999". Assim
   pega os dois casos de uma vez — a aberta e a cancelada — e pegaria também
   qualquer terceira coisa que passasse a contar sem ninguém decidir. */
verdade('a comanda aberta e a CANCELADA ficam de fora, nas duas séries',
  !(d.semana || []).some(x => Number(x.valor) > 200)
  && !(d.ano || []).some(x => Number(x.valor) > 200),
  JSON.stringify({ semana: d.semana, ano: (d.ano||[]).slice(-2) }));
igual('a série do ano tem doze meses, com os vazios em zero',
  (d.ano || []).length, 12);
igual('a da semana tem sete dias', (d.semana || []).length, 7);

await abrirDash(true);
const comVenda = await naTela();
verdade('e a tela mostra esse mesmo R$ 200,00',
  /R\$\s*200,00/.test(comVenda.texto), comVenda.texto.slice(0, 220));

/* ══════════════════════════════════════════════════════════════════════════
   3 — O DONO ESCOLHE O QUE VER
   ══════════════════════════════════════════════════════════════════════════ */
secao('Ligar, desligar e ordenar');

await p.evaluate(() => abrirConfigDash());
await p.waitForTimeout(500);

const naJanela = await p.evaluate(() => ({
  linhas: document.querySelectorAll('#dashConfig .dash-cfg').length,
  ligados: document.querySelectorAll('#dashConfig .dash-cfg.on').length,
  marcados: document.querySelectorAll('#dashConfig input:checked').length,
}));
console.log('      ' + JSON.stringify(naJanela));
igual('a janela lista TODOS os cartões, ligados e desligados',
  naJanela.linhas, 7);
/* ⚠ O DESLIGADO APARECE APAGADO, E NÃO SOME. Lista que só mostra o que já
   está ligado não ensina o que mais existe — a pessoa precisa ver para
   poder querer. */
igual('e só três estão marcados', naJanela.marcados, 3);
igual('os mesmos três que estão na tela', naJanela.ligados, 3);

// Liga "o que mais vende" e desliga o faturamento semanal.
await p.evaluate(() => { virarCartaoDash('topServicos'); virarCartaoDash('fatSemana'); });
await p.waitForTimeout(300);
// E sobe o novo até o topo, com as setas.
await p.evaluate(() => { moverCartaoDash('topServicos', -1); moverCartaoDash('topServicos', -1); });
await p.waitForTimeout(300);
await p.evaluate(() => gravarConfigDash());
await p.waitForTimeout(1800);

const noBanco = (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
igual('a escolha chega ao banco, na ordem em que ficou',
  noBanco.dashboard, ['topServicos', 'pendentes', 'fatAno']);

/* ⚠ E O RESTO DO `cfg` CONTINUA LÁ. Gravar `{dashboard}` por cima em vez de
   somar apagaria cor, tema e janela da agenda de uma vez — e o estrago só
   apareceria dias depois, sem ninguém ligar uma coisa à outra. */
verdade('e o resto do cfg não foi apagado',
  noBanco.diasLiberados != null || Object.keys(noBanco).length > 1,
  JSON.stringify(noBanco));

const depois = await naTela();
igual('a tela obedece: três cartões, na ordem escolhida',
  depois.cartoes, ['topServicos', 'pendentes', 'fatAno']);
verdade('o ranque traz o serviço vendido', /Corte/.test(depois.texto),
  depois.texto.slice(0, 200));

/* ── ⚠ DESMARCAR TUDO É UMA ESCOLHA, E TEM QUE SER OBEDECIDA ─────────────
   A primeira versão de `dashEscolhidos()` lia lista vazia como "nunca
   escolhi" e trazia o padrão de volta — desfazendo em silêncio o que o dono
   acabou de fazer. Só a mutação mostrou, porque o caso nunca era exercido.

   Ausente e vazio são estados diferentes: um é "não mexi", o outro é "não
   quero nenhum". */
await p.evaluate(() => abrirConfigDash());
await p.waitForTimeout(400);
await p.evaluate(() => {
  for(const id of dashRascunho.slice()) virarCartaoDash(id);
});
await p.waitForTimeout(300);
await p.evaluate(() => gravarConfigDash());
await p.waitForTimeout(1500);

igual('desmarcando tudo, o banco guarda a lista vazia',
  ((await dona.lista('saloes', { id: SALAO }))[0].cfg || {}).dashboard, []);
const semNada = await naTela();
igual('e a tela não traz o padrão de volta', semNada.cartoes, []);
verdade('ela explica o que aconteceu e onde desfazer',
  /Nenhum cartão escolhido/i.test(semNada.texto), semNada.texto.slice(0, 160));

/* E a janela continua listando os sete, senão não haveria como voltar
   atrás: uma tela vazia sem caminho de volta é uma armadilha. */
await p.evaluate(() => abrirConfigDash());
await p.waitForTimeout(400);
igual('e a configuração ainda lista os sete, para dar meia-volta',
  await p.evaluate(() => document.querySelectorAll('#dashConfig .dash-cfg').length), 7);
await p.evaluate(() => fecharModal());
await p.waitForTimeout(300);

/* ══════════════════════════════════════════════════════════════════════════
   4 — ⚠ O DINHEIRO DA CASA NÃO É DE QUEM ATENDE

   A mesma linha do `relatorio()`. Sem ela, bastaria trocar o uuid na chamada
   para o dono de um salão ler o faturamento do vizinho.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Quem não é gestão não lê o faturamento');

const dOutra = novaAba();
await dOutra.criarConta({ email:`outra-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Estranha', telefone:'+5521' + (900000000 + ((Date.now()+7) % 89999999)) });
let recusou = false, resposta = null;
try{
  resposta = await dOutra.chamar('painel_grafico', { p_salao: SALAO });
}catch(e){ recusou = /permiss/i.test(e.message || ''); }
verdade('uma conta de fora leva recusa do banco', recusou,
  'veio ' + JSON.stringify(resposta));

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
