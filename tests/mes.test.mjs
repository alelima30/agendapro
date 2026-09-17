/* ===========================================================================
   AgendaPro — a agenda do mês

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/mes.test.mjs

   ── O QUE ESTA TELA RESPONDE ───────────────────────────────────────────────
   A pergunta da visão de mês não é "quem vem às 14h" — é "como está o mês".
   Onde tem dia cheio, onde tem dia vazio, e para onde dá para empurrar quem
   liga pedindo "qualquer dia dessas duas semanas".

   ── ⚠ E A MEDIDA MAIS IMPORTANTE É A DO ALINHAMENTO ────────────────────────
   Um calendário cujas colunas não batem com os dias da semana é pior que
   calendário nenhum: ele PARECE certo, e a pessoa marca no dia errado.

   E não é hipótese. A primeira versão desta tela nasceu desalinhada: eu tinha
   dado aos dias do mês vizinho a classe `fora`, e o painel já tem um `.fora`
   global — a faixa listrada de "fora da jornada" na grade de horas, que é
   `position:absolute`. Os dias de agosto saíram da grade e foram empilhados
   por cima dos de setembro. O DOM estava perfeito; só a TELA estava errada.

   Por isso a seção 2 compara posições medidas no navegador, e não a ordem dos
   elementos: é a única forma de perguntar "isto está no lugar certo?".
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });
p.on('dialog', async d => { erros.push('ALERT: ' + d.message()); await d.dismiss(); });

await p.goto(BASE + 'app.html?demo=1');
await p.waitForTimeout(1800);

/* ══════════════════════════════════════════════════════════════════════════
   1 — A VISÃO EXISTE E TROCA
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── TROCANDO PARA O MÊS ──────────────────────────────────────');
e('o seletor oferece Mês', await p.isVisible('#vistas button:has-text("Mês")'));
await p.click('#vistas button:has-text("Mês")');
await p.waitForTimeout(900);

const rotulo = await p.evaluate(() =>
  document.getElementById('rotuloDia').textContent.trim());
console.log('      rótulo: ' + JSON.stringify(rotulo));
e('o rótulo passa a ser o mês e o ano — ' + JSON.stringify(rotulo),
  /^[a-zç]+\s+de\s+\d{4}$/i.test(rotulo), rotulo);

e('o calendário aparece', await p.isVisible('.mes-cal'));
/* A grade de HORAS some: ela é outra pergunta, e deixá-la embaixo do
   calendário faria a tela pedir duas leituras para dizer uma coisa. */
e('e a grade de horários sai da tela', await p.evaluate(() =>
  getComputedStyle(document.querySelector('#tela-agenda .grade-wrap')).display) === 'none');

/* ══════════════════════════════════════════════════════════════════════════
   2 — ⚠ AS COLUNAS BATEM COM OS DIAS DA SEMANA

   Medido por POSIÇÃO na tela, não por ordem no DOM. Foi assim que o `.fora`
   global apareceu: o DOM estava certo e o desenho estava errado.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O ALINHAMENTO ────────────────────────────────────────────');
const alinhamento = await p.evaluate(() => {
  const cabecas = [...document.querySelectorAll('.mes-semana span')]
    .map(s => ({ txt: s.textContent.trim(),
                 meio: Math.round(s.getBoundingClientRect().left
                                + s.getBoundingClientRect().width / 2) }));
  const dias = [...document.querySelectorAll('.mes-dia')].map(b => {
    const r = b.getBoundingClientRect();
    return { rot: b.getAttribute('aria-label') || '',
             meio: Math.round(r.left + r.width / 2),
             topo: Math.round(r.top), alt: Math.round(r.height) };
  });
  return { cabecas, dias };
});

e('sete cabeçalhos de dia da semana', alinhamento.cabecas.length === 7,
  JSON.stringify(alinhamento.cabecas.map(c => c.txt)));

/* Cada célula tem que estar embaixo do cabeçalho do dia da semana que ela é.
   O `aria-label` traz o nome do dia por extenso, escrito pelo próprio
   `porExtenso()` — então a conferência é contra o que a tela diz, não contra
   uma tabela que eu escreveria aqui e manteria igual por conta própria. */
const CURTO = { 'domingo':'dom', 'segunda':'seg', 'terça':'ter', 'quarta':'qua',
                'quinta':'qui', 'sexta':'sex', 'sábado':'sáb' };
const foraDoLugar = alinhamento.dias.filter(d => {
  const nome = (d.rot.split(',')[0] || '').trim();
  const col = alinhamento.cabecas.find(c => c.txt === CURTO[nome]);
  return !col || Math.abs(col.meio - d.meio) > 2;
});
e('cada dia está embaixo do cabeçalho do dia da semana dele',
  foraDoLugar.length === 0,
  foraDoLugar.length + ' fora do lugar: '
  + JSON.stringify(foraDoLugar.slice(0, 4).map(d => d.rot)));

/* E nenhuma célula empilhada sobre outra: com o `position:absolute` herdado,
   duas células dividiam o mesmo ponto da tela. */
const posicoes = alinhamento.dias.map(d => d.meio + '@' + d.topo);
e('e nenhuma célula ocupa o mesmo lugar que outra',
  new Set(posicoes).size === posicoes.length,
  (posicoes.length - new Set(posicoes).size) + ' célula(s) empilhada(s)');

e('todas com altura de verdade — nenhuma achatada',
  alinhamento.dias.every(d => d.alt >= 40),
  JSON.stringify(alinhamento.dias.filter(d => d.alt < 40).slice(0, 3)));

/* ══════════════════════════════════════════════════════════════════════════
   3 — O NÚMERO DENTRO DO DIA
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── A CONTAGEM ───────────────────────────────────────────────');
const contagem = await p.evaluate(() => {
  const ATIVOS_ = ['pendente','confirmado','em_atendimento','concluido'];
  const fora = [];
  for(const b of document.querySelectorAll('.mes-dia')){
    const m = (b.getAttribute('onclick') || '').match(/'(\d{4}-\d{2}-\d{2})'/);
    if(!m) continue;
    const real = bd.agendamentos.filter(a => a.salaoId === salaoAtual
      && a.data === m[1] && !a.arquivadoEm && ATIVOS_.includes(a.status)).length;
    const naTela = Number((b.querySelector('.mes-qtd:not(.bloq)') || {}).textContent || 0);
    if(real !== naTela) fora.push({ dia:m[1], real, naTela });
  }
  return fora;
});
e('a pastilha de cada dia bate com os atendimentos daquele dia',
  contagem.length === 0, JSON.stringify(contagem.slice(0, 4)));

const semZero = await p.evaluate(() =>
  [...document.querySelectorAll('.mes-qtd')].filter(x => x.textContent.trim() === '0').length);
e('e dia sem atendimento não ganha pastilha com zero', semZero === 0,
  semZero + ' pastilha(s) de zero — o vazio já diz o que o zero diria');

/* ══════════════════════════════════════════════════════════════════════════
   4 — ESCOLHER UM DIA NÃO TROCA DE VISÃO

   Quem está no mês está comparando dias. Mandá-lo para a grade de horas a
   cada clique tira dele justamente a comparação que ele veio fazer.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── ESCOLHENDO UM DIA ────────────────────────────────────────');
const outro = await p.evaluate(() => {
  const sel = document.querySelector('.mes-dia.sel');
  const todos = [...document.querySelectorAll('.mes-dia')]
    .filter(b => b !== sel && b.querySelector('.mes-qtd:not(.bloq)'));
  const b = todos[0];
  return b ? (b.getAttribute('onclick').match(/'(\d{4}-\d{2}-\d{2})'/) || [])[1] : null;
});
e('achei outro dia com movimento para clicar — ' + JSON.stringify(outro), !!outro);

await p.click(`.mes-dia[onclick*="${outro}"]`);
await p.waitForTimeout(800);

const depois = await p.evaluate(() => ({
  vista: typeof vistaAgenda !== 'undefined' ? vistaAgenda : '?',
  sel: (document.querySelector('.mes-dia.sel') || {}).getAttribute
       ? document.querySelector('.mes-dia.sel').getAttribute('onclick') : '',
  kpis: (document.getElementById('kpisDia') || {}).innerText || '',
  lista: (document.getElementById('listaDoDia') || {}).innerText || '',
}));
e('continua no mês — não pula para a grade de horas', depois.vista === 'mes',
  depois.vista);
e('o dia clicado passa a ser o escolhido', depois.sel.includes(outro), depois.sel);
e('o resumo em cima mostra os números do dia',
  /atendimentos/i.test(depois.kpis) && /previsto no dia/i.test(depois.kpis),
  depois.kpis.slice(0, 120));
e('e a lista embaixo traz os atendimentos daquele dia',
  depois.lista.length > 20, depois.lista.slice(0, 150));

/* ══════════════════════════════════════════════════════════════════════════
   5 — ⚠ O BOTÃO ‹ › ANDA UM MÊS, E NÃO ESCORREGA NO DIA 31

   `new Date(2026, 1, 31)` no JavaScript vira 3 de março sozinho — e o botão
   pularia fevereiro inteiro, uma vez por ano, para quem estivesse no fim do
   mês.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── ANDANDO DE MÊS ───────────────────────────────────────────');
await p.evaluate(() => { diaAtual = '2026-01-31'; pintar(); });
await p.waitForTimeout(600);
const jan = await p.evaluate(() => document.getElementById('rotuloDia').textContent.trim());
await p.click('#tela-agenda .barra button:has-text("›")');
await p.waitForTimeout(700);
const dep = await p.evaluate(() => ({
  rot: document.getElementById('rotuloDia').textContent.trim(),
  dia: diaAtual,
}));
console.log('      ' + JSON.stringify(jan) + ' → ' + JSON.stringify(dep));
e('31 de janeiro + um mês cai em fevereiro, não em março',
  /fevereiro/i.test(dep.rot) && dep.dia.startsWith('2026-02'),
  JSON.stringify(dep));
e('e no último dia que fevereiro tem', dep.dia === '2026-02-28', dep.dia);

/* ══════════════════════════════════════════════════════════════════════════
   6 — ⚠ VOLTAR PARA O DIA TRAZ A GRADE DE VOLTA

   Esconder é fácil de escrever e fácil de esquecer de desfazer: sem a linha
   que devolve o `display`, trocar para Mês e voltar deixava a agenda em
   branco, sem nada na tela dizendo por quê.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── VOLTANDO ─────────────────────────────────────────────────');
await p.click('#vistas button:has-text("Dia")');
await p.waitForTimeout(900);
const voltou = await p.evaluate(() => ({
  grade: getComputedStyle(document.querySelector('#tela-agenda .grade-wrap')).display,
  cal: (document.getElementById('mesCalendario') || {}).innerHTML.length,
  lista: (document.getElementById('listaDoDia') || {}).innerHTML.length,
  colunas: document.querySelectorAll('#grade .col-h').length,
}));
console.log('      ' + JSON.stringify(voltou));
e('a grade de horários volta a aparecer', voltou.grade !== 'none', voltou.grade);
e('com as colunas desenhadas', voltou.colunas > 0, JSON.stringify(voltou));
e('e o calendário do mês é limpo', voltou.cal === 0, 'sobrou ' + voltou.cal);
e('e a lista do mês também', voltou.lista === 0, 'sobrou ' + voltou.lista);

/* ══════════════════════════════════════════════════════════════════════════
   7 — NO CELULAR

   A suíte do celular percorre as abas, mas nunca troca a visão da agenda —
   então esta tela só é medida aqui.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── EM 375px ─────────────────────────────────────────────────');
const cel = await ctx.newPage();
await cel.setViewportSize({ width:375, height:667 });
await cel.goto(BASE + 'app.html?demo=1');
await cel.waitForTimeout(1800);
await cel.click('#vistas button:has-text("Mês")');
await cel.waitForTimeout(900);

const noCelular = await cel.evaluate(() => ({
  vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  pequenos: [...document.querySelectorAll('.mes-dia')]
    .filter(b => { const r = b.getBoundingClientRect();
                   return r.height < 40 || r.width < 40; }).length,
  miudo: [...document.querySelectorAll('.mes-cal *')]
    .filter(x => x.children.length === 0 && x.textContent.trim()
              && parseFloat(getComputedStyle(x).fontSize) < 11).length,
}));
console.log('      ' + JSON.stringify(noCelular));
e('a página não rola para o lado', noCelular.vaza === 0,
  'sobram ' + noCelular.vaza + 'px');
e('nenhum dia menor que 40px — é o dedo que vai clicar',
  noCelular.pequenos === 0, noCelular.pequenos + ' dia(s) pequeno(s)');
e('e nenhum texto abaixo de 11px', noCelular.miudo === 0,
  noCelular.miudo + ' pedaço(s) de texto miúdo');

e('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
