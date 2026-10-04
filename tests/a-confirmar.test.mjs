/* ===========================================================================
   AgendaPro — a agenda mostra o que ainda espera a confirmação do salão

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/a-confirmar.test.mjs

   O pedido do dono, olhando a lista do dia no mês: "sempre tenho que olhar e
   ver o que está confirmado e o que precisa confirmar". A lista mostrava
   nome, hora e valor — nada que separasse uma coisa da outra. A faixa "N
   horários esperam sua confirmação" existia, mas só no topo da agenda.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a lista do dia: "A confirmar" (tarja âmbar e Confirmar ali mesmo) e
        "Confirmado";
     2. Confirmar no cartão confirma sem abrir a ficha; tocar no cartão abre;
     3. o mês: o dia com pendente tem a pastilha âmbar, e a legenda explica;
     4. a grade do dia e a da semana: o bloco pendente diz "a confirmar";
     5. o recado de horário novo diz que espera confirmação e leva até lá;
     6. a 390px nada vaza; nenhum erro de JavaScript.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
const secao = t => console.log('\n' + t);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width: 390, height: 900 }, isMobile: true, hasTouch: true });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => d.dismiss());
await p.goto(BASE + 'app.html?demo=1');
await p.waitForFunction(() => typeof bd !== 'undefined' && bd && typeof pintar === 'function', null, { timeout: 15000 });
await p.waitForTimeout(1200);

/* Um dia de terça com dois horários: um esperando, um confirmado. */
const DIA = await p.evaluate(() => {
  try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true);
  let d = somarDias(hoje(), 1);
  while(new Date(d + 'T12:00').getDay() !== 2) d = somarDias(d, 1);
  const base = agendaDoSalao()[0];
  bd.agendamentos = bd.agendamentos.filter(a => a.data !== d);
  bd.agendamentos.push(Object.assign({}, base, { id:'ag-pend', data:d, inicio:600, fim:660, status:'pendente', arquivadoEm:null }));
  bd.agendamentos.push(Object.assign({}, base, { id:'ag-conf', data:d, inicio:720, fim:780, status:'confirmado', arquivadoEm:null }));
  diaAtual = d; trocarVista('mes');
  return d;
});
await p.waitForTimeout(500);
const cartoes = () => p.evaluate(() => [...document.querySelectorAll('#listaDoDia .dia-cartao')].map(c => ({
  pend: c.classList.contains('st-pendente'), tag: (c.querySelector('.tag') || {}).textContent || '',
  botao: !!c.querySelector('.dc-confirmar'), tarja: getComputedStyle(c).borderLeftColor })));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A lista do dia separa o que espera do que está confirmado');
{
  const c = await cartoes();
  igual('o pendente diz "A confirmar" e tem o Confirmar; o outro diz "Confirmado"',
    c.map(x => [x.pend, x.tag.trim(), x.botao]), [[true, 'A confirmar', true], [false, 'Confirmado', false]]);
  verdade('e a tarja do pendente é de outra cor', c[0].tarja !== c[1].tarja, JSON.stringify(c));
  igual('a 390px, nada vaza para o lado', await p.evaluate(() => document.documentElement.scrollWidth - innerWidth <= 0), true);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. O mês: o dia com pendente aparece');
{
  const r = await p.evaluate(d => {
    const cel = document.querySelector(`.mes-dia[onclick*="${d}"] .mes-qtd`);
    return { pend: cel && cel.classList.contains('pend'),
      legenda: document.querySelector('.mes-legenda').innerText };
  }, DIA);
  verdade('a pastilha do dia fica âmbar, e a legenda diz "A confirmar"', r.pend && /A confirmar/.test(r.legenda), JSON.stringify(r));
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. A grade: o bloco pendente diz que espera');
for(const vista of ['dia', 'semana']){
  await p.evaluate(v => trocarVista(v), vista); await p.waitForTimeout(400);
  const r = await p.evaluate(() => [...document.querySelectorAll('#grade .ag')].map(b => ({
    pend: b.classList.contains('pendente'), etiqueta: (b.querySelector('.ag-pend') || {}).textContent || '' }))
    .filter(x => x.pend || x.etiqueta));
  verdade(`${vista}: o bloco pendente tem a etiqueta "a confirmar"`, r.length >= 1 && r.every(x => x.pend && x.etiqueta === 'a confirmar'), JSON.stringify(r));
}
await p.evaluate(() => trocarVista('mes')); await p.waitForTimeout(400);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. O recado de horário novo');
{
  await p.evaluate(() => avisarNovosHorarios(1)); await p.waitForTimeout(200);
  const t = await p.evaluate(() => document.getElementById('recadoNovos').innerText);
  verdade('diz quantos esperam sua confirmação', /\d+ esperam? sua confirmação/.test(t), t);
  await p.evaluate(() => window.scrollTo(0, document.body.scrollHeight)); await p.waitForTimeout(200);
  await p.click('#recadoNovos'); await p.waitForTimeout(900);
  const topo = await p.evaluate(() => document.getElementById('aConfirmar').getBoundingClientRect().top);
  verdade('tocar leva até a faixa de confirmar', topo > -5 && topo < 300, 'topo ' + topo);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Confirmar no cartão, e o cartão abre a ficha');
{
  await p.click('#listaDoDia .dia-cartao.st-pendente .dc-confirmar'); await p.waitForTimeout(400);
  const r = await p.evaluate(() => ({ st: bd.agendamentos.find(a => a.id === 'ag-pend').status,
    modal: document.getElementById('fundo').classList.contains('on'),
    faixa: document.getElementById('aConfirmar').innerText.trim() }));
  igual('Confirmar confirma, sem abrir a ficha por cima', [r.st, r.modal], ['confirmado', false]);
  const c = await cartoes();
  igual('e o cartão passa a dizer "Confirmado"', c.map(x => x.tag.trim()), ['Confirmado', 'Confirmado']);
  await p.click('#listaDoDia .dia-cartao >> nth=0'); await p.waitForTimeout(400);
  igual('tocar no cartão abre a ficha do atendimento', await p.evaluate(() =>
    document.getElementById('fundo').classList.contains('on')), true);
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
