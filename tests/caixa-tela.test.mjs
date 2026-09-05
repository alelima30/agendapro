/* ===========================================================================
   AgendaPro — o Caixa e o Hoje, num navegador de verdade

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/caixa-tela.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   A gaveta e o painel do dia nasceram com teste de BANCO e nenhum de tela.
   O `caixa.test.sql` prova que os gatilhos barram o que têm de barrar; não
   prova que a recepção consegue abrir o caixa, lançar uma sangria e fechar
   sem levar erro na cara.

   E as três tabelas novas — `caixas`, `caixa_movimentos`, `estornos` —
   entraram na lista que o `Dados.subir()` sincroniza. Esse sincronizador faz
   INSERT, UPDATE **e DELETE**, e duas delas são de propósito só de inserção:
   estorno é registro do que aconteceu, não linha para editar. Se o
   sincronizador tentar um UPDATE ou um DELETE ali, a gravação INTEIRA cai —
   e cai levando junto a comanda que a recepção estava fechando.

   Este arquivo faz o caminho completo pelo navegador, com o `pageerror`
   ligado: abrir o caixa, receber, estornar, lançar sangria, fechar, e olhar
   o painel do dia. É o único jeito de saber.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pg from './pg.mjs';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
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
const tel = () => '+5511' + (100000000 + Math.floor(Math.random()*89999999));

const dona = novaAba();
await dona.criarConta({ email:`cx-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju do Caixa', telefone: tel() });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Caixa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;

/* A profissional que o `criar_salao()` já cria para a dona — e não uma
   nova. O plano de teste cobre UMA, e inserir a segunda esbarra na cota:
   "o salão já tem 1". O teste morria ali, num erro que não tem nada a ver
   com caixa. */
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
await dona.atualizar('profissionais', prof.id, { comissaoPct: 40 });
prof.comissaoPct = 40;
const serv = await dona.inserir('servicos',
  { salaoId: SALAO, nome:'Corte', duracaoMin: 30, preco: 100, comissaoPct: 40 });
const cli = await dona.inserir('clientes',
  { salaoId: SALAO, nome:'Clara', telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });

/* Uma comanda pronta, criada pelo mesmo caminho que a tela usa. Sem
   agendamento de propósito: comanda avulsa é o caso do balcão, e é o que
   deixa o teste independente da agenda. */
const com = await dona.inserir('comandas',
  { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: com.id, tipo:'servico',
  servicoId: serv.id, descricao:'Corte', qtd:1, precoUnit:100,
  profissionalId: prof.id });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
p.on('pageerror', e => erros.push(e.message));
/* `alert` trava o Playwright e some com a mensagem. Aceitar e GUARDAR é o
   que transforma "a tela não fez nada" em "a tela disse isto". */
const avisos = [];
p.on('dialog', async d => { avisos.push(d.message()); await d.accept(); });

await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);

/* ⚠ Lê o ESPERADO, e não o cartão inteiro.

   A primeira versão testava `/R\$\s*200/` contra `textContent` do cartão —
   e passava por engano, casando com o "Aberto com R$ 200,00" que fica ao
   lado. O teste ficava verde com o esperado em branco, que era exatamente o
   defeito procurado. Regex larga em cima de tela é o jeito mais fácil de
   escrever um teste que não testa nada. */
const esperadoNaGaveta = () => p.evaluate(() => {
  const c = document.getElementById('cartaoGaveta');
  if(!c) return null;
  const r = [...c.querySelectorAll('div')].find(d =>
    (d.textContent || '').trim() === 'esperado na gaveta');
  return r && r.previousElementSibling
    ? r.previousElementSibling.textContent.trim() : null;
});

const irPara = async chave => {
  // Fecha o que estiver aberto: modal por cima intercepta o clique na aba, e
  // o Playwright fica trinta segundos tentando antes de desistir com uma
  // mensagem sobre "pointer events" que não diz o que houve.
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} });
  await p.waitForTimeout(200);
  await p.click(`#abas .aba[data-chave="${chave}"]`);
  await p.waitForTimeout(1200);
};

/* Recarrega o `bd` da tela a partir do banco — necessário depois de inserir
   fora dela (o `dona.inserir` fala direto com o PostgREST). Sem isto, a tela
   não conhece o serviço novo e o formulário abre vazio. */
const carregarNaTela = async () => p.evaluate(async () => {
  const novo = await carregarTudo();
  if(novo){ bd = novo; pintar(); }
  return true;
});

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();

/* ═══════════════════════════════════════════════════════════════════════════
   1) ABRIR O CAIXA
   ═══════════════════════════════════════════════════════════════════════════ */
secao('1) A recepção abre o caixa');

await irPara('caixa');

verdade('a tela do caixa oferece abrir a gaveta',
  (await p.textContent('#cartaoGaveta')).includes('não está aberto'),
  await p.textContent('#cartaoGaveta'));

await p.click('#cartaoGaveta button');
await p.waitForTimeout(400);
await p.fill('#gAbertura', '200');
await p.click('.acoes .btn-primario');
await p.waitForTimeout(2000);

const caixas = (await banco.query(
  `select * from public.caixas where salao_id=$1`, [SALAO])).rows;
verdade('o caixa existe no banco', caixas.length === 1,
  JSON.stringify(caixas.map(k => k.id)));
verdade('com os R$ 200 de abertura',
  caixas.length === 1 && Number(caixas[0].valor_abertura) === 200,
  caixas.length ? String(caixas[0].valor_abertura) : '—');

/* ⚠ O número principal da tela, e o mais fácil de esquecer de carregar.
   `conferir_caixa()` é uma chamada ao banco; se ninguém a disparar ao ENTRAR
   na tela, o esperado fica em branco para quem recarregou a página — que é
   todo mundo, todo dia de manhã. */
verdade('e o esperado na gaveta aparece, não fica em branco',
  /200/.test(await esperadoNaGaveta() || ''), await esperadoNaGaveta());

/* ═══════════════════════════════════════════════════════════════════════════
   2) O ESPERADO APARECE DEPOIS DE RECARREGAR A PÁGINA

   É o caso de todo dia: o caixa foi aberto de manhã, e a recepção abre o
   painel de novo depois do almoço.
   ═══════════════════════════════════════════════════════════════════════════ */
secao('2) Depois de recarregar a página');

await p.reload();
await p.waitForTimeout(4000);
await irPara('caixa');

verdade('a gaveta continua mostrando o esperado, e não um traço',
  /200/.test(await esperadoNaGaveta() || ''), await esperadoNaGaveta());

/* ═══════════════════════════════════════════════════════════════════════════
   3) SANGRIA
   ═══════════════════════════════════════════════════════════════════════════ */
secao('3) Uma sangria');

const botaoPor = async rotulo =>
  (await p.$$('#cartaoGaveta button')).find(async b =>
    (await b.textContent()).trim() === rotulo);

await p.click('#cartaoGaveta button:has-text("Sangria")');
await p.waitForTimeout(400);
await p.fill('#mValor', '50');
await p.fill('#mMotivo', 'levei ao banco');
await p.click('.acoes .btn-primario');
await p.waitForTimeout(2000);

const movs = (await banco.query(
  `select * from public.caixa_movimentos where salao_id=$1`, [SALAO])).rows;
verdade('a sangria foi gravada', movs.length === 1, JSON.stringify(movs));
verdade('e o esperado caiu para 150 NA HORA',
  /150/.test(await esperadoNaGaveta() || ''), await esperadoNaGaveta());

/* ═══════════════════════════════════════════════════════════════════════════
   4) RECEBER E ESTORNAR

   O ponto sensível: `estornos` é só-inserção no banco. Se o sincronizador
   tentar UPDATE ou DELETE nela, a gravação inteira cai — e leva junto a
   comanda que a recepção estava fechando.
   ═══════════════════════════════════════════════════════════════════════════ */
secao('4) Receber, e depois estornar');

await p.evaluate(id => abrirComanda(id), com.id);
await p.waitForTimeout(800);
await p.selectOption('#cForma', 'dinheiro');
await p.fill('#cValor', '100');
await p.click('button:has-text("Registrar pagamento")');
await p.waitForTimeout(2000);

let pgs = (await banco.query(
  `select p.* from public.pagamentos p join public.comandas c on c.id=p.comanda_id
    where c.salao_id=$1`, [SALAO])).rows;
verdade('o pagamento entrou', pgs.length === 1, JSON.stringify(pgs.length));
verdade('e o banco carimbou o caixa nele',
  pgs.length === 1 && pgs[0].caixa_id === caixas[0].id,
  pgs.length ? String(pgs[0].caixa_id) : '—');

await p.evaluate(id => abrirComanda(id), com.id);
await p.waitForTimeout(600);
verdade('a comanda oferece estornar o pagamento',
  await p.isVisible('button:has-text("Estornar")'));

await p.click('button:has-text("Estornar")');
await p.waitForTimeout(400);
await p.fill('#eValor', '40');
await p.fill('#eMotivo', 'digitei a mais');
await p.click('.acoes .btn-primario');
await p.waitForTimeout(2500);

const est = (await banco.query(
  `select * from public.estornos where salao_id=$1`, [SALAO])).rows;
verdade('o estorno foi gravado', est.length === 1, JSON.stringify(est.length));
verdade('e no valor certo',
  est.length === 1 && Number(est[0].valor) === 40,
  est.length ? String(est[0].valor) : '—');

/* ⚠ A pergunta que motivou este arquivo. */
verdade('gravar depois do estorno NÃO derruba a sincronização',
  !avisos.some(a => /apagar|permission denied|não consegui/i.test(a)),
  JSON.stringify(avisos));

// E salvar DE NOVO, que é quando um DELETE indevido apareceria: agora o
// estorno está no retrato anterior e no atual.
await p.evaluate(() => salvar());
await p.waitForTimeout(2000);
verdade('e gravar uma segunda vez também não',
  !avisos.some(a => /apagar|permission denied/i.test(a)),
  JSON.stringify(avisos));

const est2 = (await banco.query(
  `select count(*)::int as n from public.estornos where salao_id=$1`, [SALAO])).rows[0].n;
verdade('o estorno continua lá depois da segunda gravação', est2 === 1, String(est2));

/* ═══════════════════════════════════════════════════════════════════════════
   4b) DEPOIS DE DEVOLVER, A COMANDA VOLTA A DEVER

   O banco sempre soube: `comandas_totais.pago` é LÍQUIDO de estorno, e o
   `tg_fechar_comanda` recusa fechar com `falta > 0`.

   A tela não sabia. `pagoNaComanda()` somava `pagamentos.valor` cru, sem
   descontar o que foi devolvido — então, depois de estornar R$ 40 de uma
   comanda de R$ 100, a tela continuava dizendo "Recebido R$ 100,00" em
   verde, sem linha de "Falta receber", com o campo de valor do próximo
   pagamento em R$ 0,00.

   O caminho todo é o normal: recebeu errado → reabre → estorna → cobra o
   certo. É no meio dele que a recepção olhava uma comanda quitada e, ao
   apertar "Fechar comanda", levava um erro do banco dizendo que faltavam
   R$ 40. A tela e o banco discordando sobre quanto a cliente deve — na
   frente da cliente.
   ═══════════════════════════════════════════════════════════════════════════ */
secao('4b) A comanda depois do estorno');

await p.evaluate(id => abrirComanda(id), com.id);
await p.waitForTimeout(700);

const corpoComanda = await p.textContent('#modalCorpo');
verdade('a comanda mostra que voltou a faltar R$ 40',
  /Falta receber/.test(corpoComanda) && /40,00/.test(corpoComanda),
  corpoComanda.replace(/\s+/g, ' ').slice(0, 320));

verdade('e o "Recebido" conta os R$ 60 que sobraram, não os R$ 100 brutos',
  await p.evaluate(id => {
    const c = bd.comandas.find(x => x.id === id);
    return Math.abs(pagoNaComanda(c) - 60) < 0.005;
  }, com.id),
  'pagoNaComanda veio ' + await p.evaluate(id =>
    pagoNaComanda(bd.comandas.find(x => x.id === id)), com.id));

/* O par de sempre: a tela concordando com o banco, e não só consigo mesma. */
const totaisDoBanco = (await banco.query(
  `select pago, falta, situacao from public.comandas_totais where id=$1`,
  [com.id])).rows[0];
verdade('e o banco diz a mesma coisa: falta 40, situação parcial',
  Math.abs(Number(totaisDoBanco.falta) - 40) < 0.005
    && totaisDoBanco.situacao === 'parcial',
  JSON.stringify(totaisDoBanco));

verdade('a situação na tela também é parcial, e não "pago"',
  await p.evaluate(id =>
    situacaoDaComanda(bd.comandas.find(x => x.id === id)), com.id) === 'parcial',
  await p.evaluate(id =>
    situacaoDaComanda(bd.comandas.find(x => x.id === id)), com.id));

/* ⚠ E ESTE É O SINTOMA MAIS CARO DOS TRÊS.

   O campo do próximo pagamento vem preenchido com `total − pago`. Com o
   `pago` sem descontar o estorno, ele vinha R$ 0,00 — e o `receber()` recusa
   qualquer valor acima do que falta. Quer dizer: dava para DEVOLVER e não
   dava para COBRAR de novo. O caminho "recebeu errado → reabre → estorna →
   cobra o certo" morria no último passo, com a tela dizendo
   "Faltam R$ 0,00 nesta comanda, e você digitou R$ 40,00". */
verdade('e o campo do próximo pagamento já vem com os R$ 40 que faltam',
  Math.abs(Number(await p.inputValue('#cValor')) - 40) < 0.005,
  'veio ' + JSON.stringify(await p.inputValue('#cValor')));

/* ⚠ E QUEM RECUSA PRIMEIRO TEM QUE SER A TELA.

   O banco recusa de qualquer jeito — o `tg_fechar_comanda` está lá. Mas
   recusar só no banco significa uma ida ao servidor para devolver um erro
   que a tela já tinha como saber, e o aviso que a recepção lê vira o de
   gravação recusada, com "entre de novo" no fim. */
avisos.length = 0;
await p.evaluate(id => fecharComanda(id), com.id);
await p.waitForTimeout(2000);
/* O texto procurado é o da TELA, não o do banco.

   As duas recusas começam com "Ainda faltam R$ 40,00" — a do gatilho e a
   daqui. Procurar só por isso deixaria esta verificação passar exatamente no
   estado que ela existe para reprovar: a tela mandando, o banco recusando.
   "Registre o pagamento que falta" só existe no aviso da tela. */
verdade('e "Fechar comanda" é barrado pela própria tela, com a conta certa',
  avisos.some(a => /40,00/.test(a) && /Registre o pagamento que falta/.test(a)),
  JSON.stringify(avisos));
verdade('sem virar recusa de gravação do banco',
  !avisos.some(a => /NÃO consegui salvar/i.test(a)), JSON.stringify(avisos));

const aindaAberta = (await banco.query(
  `select status from public.comandas where id=$1`, [com.id])).rows[0].status;
verdade('e a comanda continua aberta no banco', aindaAberta === 'aberta',
  aindaAberta);

/* De propósito NÃO cobramos os R$ 40 aqui: a seção 5 confere a gaveta em
   210 (200 de abertura + 100 recebidos − 40 devolvidos − 50 de sangria), e
   um pagamento a mais nesta seção mudaria aquele número — deixando a
   reprova de lá parecendo defeito do caixa em vez de mexida daqui. */
await p.evaluate(() => { try{ fecharModal(); }catch(e){} });

/* ═══════════════════════════════════════════════════════════════════════════
   5) FECHAR O CAIXA
   ═══════════════════════════════════════════════════════════════════════════ */
secao('5) Fechar a gaveta');

await irPara('caixa');
// 200 abertura + 100 recebido − 40 devolvido − 50 sangria = 210
verdade('o esperado agora é 210',
  /210/.test(await esperadoNaGaveta() || ''), await esperadoNaGaveta());

await p.click('#cartaoGaveta button:has-text("Fechar caixa")');
await p.waitForTimeout(400);
await p.fill('#gContado', '200');
await p.click('.acoes .btn-primario');
await p.waitForTimeout(2500);

verdade('a tela diz quanto faltou na gaveta',
  avisos.some(a => /[Ff]altaram/.test(a)), JSON.stringify(avisos.slice(-3)));

const fechado = (await banco.query(
  `select fechado_em, valor_contado from public.caixas where salao_id=$1`, [SALAO])).rows[0];
verdade('e o banco guardou o fechamento',
  !!fechado.fechado_em && Number(fechado.valor_contado) === 200,
  JSON.stringify(fechado));

await p.waitForTimeout(500);
verdade('a tela volta a oferecer abrir o caixa',
  (await p.textContent('#cartaoGaveta')).includes('não está aberto'),
  await p.textContent('#cartaoGaveta'));

/* ═══════════════════════════════════════════════════════════════════════════
   6) O PAINEL DO DIA
   ═══════════════════════════════════════════════════════════════════════════ */
secao('6) A aba Hoje');

await irPara('hoje');
const hoje = await p.textContent('#hojeCorpo');

verdade('o painel abre sem erro', !/Não consegui montar/.test(hoje),
  hoje.slice(0, 180));
verdade('mostra o faturamento do dia', /faturamento de hoje/.test(hoje));
verdade('e diz que o caixa foi fechado', /não está aberto/.test(hoje),
  hoje.slice(0, 200));

/* ═══════════════════════════════════════════════════════════════════════════
   7) AS REGRAS NOVAS DE COMISSÃO TÊM ONDE SER CADASTRADAS

   Elas nasceram no banco, com teste de banco, e SEM campo em tela nenhuma:
   comissão fixa, comissão por par e bruto/líquido existiam e eram
   inalcançáveis pelo dono. Do ponto de vista dele, não existiam.

   E `saloes` não tinha mapa de colunas — todo campo dele era palavra única.
   `comissaoSobre` iria cru para o PostgREST, que não tem essa coluna, e a
   gravação inteira do cadastro do salão cairia: nome, telefone, endereço,
   tudo junto.
   ═══════════════════════════════════════════════════════════════════════════ */
secao('7) Cadastrar as regras novas de comissão');

await irPara('servicos');
await p.click(`button[onclick*="${serv.id}"]`).catch(() => {});
await p.waitForTimeout(600);
verdade('o serviço tem campo de comissão fixa',
  await p.isVisible('#sComFixa'));
await p.evaluate(() => { try{ fecharModal(); }catch(e){} });

await irPara('salao');
verdade('Meu salão deixa escolher bruto ou líquido',
  await p.isVisible('#cComSobre'));
verdade('e a data de corte',
  await p.isVisible('#cComDesde'));

await p.selectOption('#cComSobre', 'liquido');
await p.fill('#cComDesde', '2026-01-01');
await p.click('button:has-text("Salvar")');
await p.waitForTimeout(2500);

const sl = (await banco.query(
  `select comissao_sobre, comissao_regra_desde from public.saloes where id=$1`,
  [SALAO])).rows[0];
verdade('a regra chegou ao banco',
  sl.comissao_sobre === 'liquido', JSON.stringify(sl));
verdade('e a data de corte também',
  !!sl.comissao_regra_desde, JSON.stringify(sl));
verdade('e o cadastro do salão não caiu junto',
  !avisos.some(a => /NÃO consegui salvar/.test(a)),
  JSON.stringify(avisos.slice(-2)));

/* ═══════════════════════════════════════════════════════════════════════════
   8) A EXCEÇÃO POR PAR SERVIÇO+PROFISSIONAL

   `servicos_profissionais` existe desde o primeiro dia e nunca teve tela.
   Guarda três exceções por dupla — preço, duração e comissão — e as três
   eram inalcançáveis pelo dono.

   E ela não tinha coluna `id`: medido antes de a tela existir, gravar dois
   pares gravava UM, sem erro. Por isso este bloco cadastra DOIS, e não um.
   ═══════════════════════════════════════════════════════════════════════════ */
secao('8) Preço e comissão por profissional');

// Um segundo serviço, para haver dois pares para gravar de uma vez.
const serv2 = await dona.inserir('servicos',
  { salaoId: SALAO, nome:'Escova', duracaoMin: 45, preco: 200 });
const novo = await carregarNaTela();
void novo;

await irPara('servicos');
await p.waitForTimeout(800);

await p.evaluate(sid => abrirServico(sid), serv.id);
await p.waitForTimeout(600);
verdade('o formulário do serviço mostra a tabela por profissional',
  await p.isVisible('.par-in'));

await p.evaluate(pid => {
  const preco = document.querySelector(`.par-in[data-prof="${pid}"][data-campo="preco"]`);
  const pct   = document.querySelector(`.par-in[data-prof="${pid}"][data-campo="comissaoPct"]`);
  preco.value = '150'; pct.value = '70';
}, prof.id);
await p.click('#modalPe .btn-p');
await p.waitForTimeout(2500);

await p.evaluate(sid => abrirServico(sid), serv2.id);
await p.waitForTimeout(600);
await p.evaluate(pid => {
  document.querySelector(`.par-in[data-prof="${pid}"][data-campo="comissaoFixa"]`).value = '25';
}, prof.id);
await p.click('#modalPe .btn-p');
await p.waitForTimeout(2500);

const pares = (await banco.query(
  `select sp.*, s.nome from public.servicos_profissionais sp
     join public.servicos s on s.id = sp.servico_id
    where s.salao_id = $1 order by s.nome`, [SALAO])).rows;

verdade('os DOIS pares foram gravados — não um', pares.length === 2,
  JSON.stringify(pares.map(x => x.nome)));
verdade('o preço da Ana no Corte é 150',
  pares.some(x => Number(x.preco) === 150 && Number(x.comissao_pct) === 70),
  JSON.stringify(pares));
verdade('e a comissão fixa dela na Escova é 25',
  pares.some(x => Number(x.comissao_fixa) === 25),
  JSON.stringify(pares));

/* E a prova de que serve para alguma coisa: a escada do banco tem que
   passar a devolver a taxa do par, e não a do serviço nem a da pessoa. */
const daEscada = (await banco.query(
  `select pct, fixa from public.comissao_de('servico', $1, null, $2)`,
  [serv.id, prof.id])).rows[0];
verdade('a escada do banco passa a usar a taxa do par (70%)',
  Number(daEscada.pct) === 70, JSON.stringify(daEscada));

verdade('e nada disso derrubou a gravação',
  !avisos.some(a => /NÃO consegui salvar/.test(a)),
  JSON.stringify(avisos.slice(-2)));

/* ═══════════════════════════════════════════════════════════════════════════
   8b) O ACRÉSCIMO CONTA NO FATURAMENTO DO CAIXA

   O aviso em cima do `pintarCaixa()` diz, com todas as letras, que o Caixa
   tem que contar a MESMA coisa que o relatório — "dois faturamentos
   diferentes na mesma tela é o tipo de coisa que faz o dono parar de confiar
   no sistema inteiro".

   E o KPI somava `qtd × preço` dos itens e subtraía o desconto. Só isso. O
   acréscimo — taxa de domingo, urgência, deslocamento — nasceu na Fase 2A,
   entrou no `totalDaComanda()`, entrou na vista `comandas_totais`, e ficou
   de fora daqui. Segunda vez que este campo escapa de um lugar: a primeira
   foi a lista `NUMERICAS` do dados.js, e o sintoma apareceu três arquivos
   adiante.

   A conferência é contra o BANCO, não contra um número escrito à mão: a
   pergunta não é "dá 230?", é "dá o mesmo que o relatório vai dar?".
   ═══════════════════════════════════════════════════════════════════════════ */
secao('8b) O acréscimo no faturamento do Caixa');

const com2 = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: com2.id, tipo:'servico',
  servicoId: serv.id, descricao:'Corte', qtd:1, precoUnit:200,
  profissionalId: prof.id });
// O acréscimo ANTES do pagamento: o `tg_comanda_valor_travado` não deixa
// mexer no valor de uma comanda que já recebeu dinheiro, e com razão.
await dona.atualizar('comandas', com2.id, { acrescimo: 30 });
await dona.inserir('pagamentos',
  { comandaId: com2.id, forma:'pix', valor: 230 });
await dona.atualizar('comandas', com2.id, { status:'fechada' });

const t2 = (await banco.query(
  `select total from public.comandas_totais where id=$1`, [com2.id])).rows[0];
verdade('o banco põe o acréscimo no total da comanda',
  Math.abs(Number(t2.total) - 230) < 0.005, JSON.stringify(t2));

await carregarNaTela();
await irPara('caixa');

/* Lê o KPI pelo RÓTULO, e devolve o número — comparar textos formatados
   faria esta verificação reprovar no dia em que alguém trocar o separador de
   milhar, por um motivo que não é o desta seção. */
const fatCaixa = await p.evaluate(() => {
  const r = [...document.querySelectorAll('#kpisCaixa .kpi')].find(k =>
    /faturamento/.test(k.textContent));
  if(!r) return null;
  const t = ((r.querySelector('.v') || {}).textContent || '')
    .replace(/[^\d,.-]/g, '').replace(/\./g, '').replace(',', '.');
  return t === '' ? null : Number(t);
});
verdade('e o Caixa mostra o MESMO faturamento que o banco calculou',
  fatCaixa !== null && Math.abs(fatCaixa - Number(t2.total)) < 0.005,
  'a tela somou ' + fatCaixa + ', o banco calculou ' + t2.total);

/* ═══════════════════════════════════════════════════════════════════════════
   8c) "HOJE" É O DIA DO SALÃO

   O `hoje()` da tela devolvia a data do APARELHO, enquanto `a.data` e
   `c.data` saem do fuso do SALÃO. Enquanto os dois coincidem — celular
   brasileiro, salão brasileiro — não se vê nada. Quando não coincidem, a
   agenda abre num dia vazio e o Caixa filtra `c.data === diaAtual` sem achar
   comanda nenhuma. Sem erro nenhum para investigar.

   Foi assim que a seção 8b acima apareceu: a bancada roda em UTC, o salão é
   America/Sao_Paulo, e o Caixa mostrou R$ 0,00 com R$ 230 fechados no banco.

   O fuso escolhido aqui é o que GARANTE data diferente da do aparelho a
   qualquer hora do dia. Sem esse cuidado o teste passaria por sorte de
   horário — que é o mesmo que não testar.
   ═══════════════════════════════════════════════════════════════════════════ */
secao('8c) O dia é o do salão, não o do aparelho');

/* ⚠ A FRONTEIRA É 11, NÃO 12 — E ERRAR ISSO ABRIA UMA HORA DE FALHA POR DIA.

   Niue é UTC−11: ele só cai no dia ANTERIOR enquanto a hora UTC for menor que
   11. Às 11h UTC em ponto, lá é 00h do MESMO dia — e a própria verificação
   logo abaixo, que existe para garantir que os dois dias diferem, reprovava.

   Uma hora por dia, todo dia, com uma mensagem que fala de fuso horário e não
   de caixa. A suíte inteira parava por causa do relógio da máquina, e quem
   rodasse às 08h de Brasília ia procurar o defeito no lugar errado.

   Com 11, as duas metades cobrem o dia inteiro sem buraco: de 0h a 10h Niue
   está ontem; de 11h a 23h, Kiritimati (UTC+14) já está amanhã. */
const agora = new Date();
const FUSO_LONGE = agora.getUTCHours() >= 11
  ? 'Pacific/Kiritimati'   // UTC+14: já é amanhã lá
  : 'Pacific/Niue';        // UTC−11: ainda é ontem lá
const emFuso = f => new Intl.DateTimeFormat('en-CA',
  Object.assign({ year:'numeric', month:'2-digit', day:'2-digit' },
                f ? { timeZone: f } : {})).format(agora);

await dona.atualizar('saloes', SALAO, { fuso: FUSO_LONGE });
await carregarNaTela();
const diaDaTela = await p.evaluate(() => ({ hoje: hoje(), diaAtual }));

verdade('o fuso escolhido de fato cai noutro dia que o do aparelho',
  emFuso(FUSO_LONGE) !== emFuso(null),
  FUSO_LONGE + ' → ' + emFuso(FUSO_LONGE) + ' · aparelho → ' + emFuso(null));
verdade('e o hoje() da tela segue o salão',
  diaDaTela.hoje === emFuso(FUSO_LONGE),
  'a tela disse ' + diaDaTela.hoje + ', no salão é ' + emFuso(FUSO_LONGE));

await dona.atualizar('saloes', SALAO, { fuso: 'America/Sao_Paulo' });
await carregarNaTela();

/* ═══════════════════════════════════════════════════════════════════════════
   9) NENHUM ERRO DE JAVASCRIPT NO CAMINHO INTEIRO
   ═══════════════════════════════════════════════════════════════════════════ */
secao('9) O console');
verdade('nenhum erro de JavaScript', erros.length === 0, erros.join(' · '));

await banco.query(`delete from public.saloes where id=$1`, [SALAO]);
await banco.end();
await nav.close();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações do caixa e do painel na tela.`);
