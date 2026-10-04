/* ===========================================================================
   AgendaPro — a agenda acorda no dia de hoje, e os números vêm depois

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/agenda-hoje.test.mjs

   A foto do dono, num domingo 04/10: o painel abriu em setembro, no último
   dia que ele tinha olhado, "como se já tivesse passado". O celular não fecha
   o painel — dorme com a aba e acorda dias depois onde estava — e o dia da
   agenda só era calculado uma vez, ao entrar.

   O relógio da página é controlado aqui (page.clock): abre num dia, o tempo
   pula para outro, e a agenda tem que perceber sozinha.

   E a ordem pedida: o calendário e quem vem no dia primeiro; os cartões de
   números (atendimentos, faturamento, ocupação, faltas) embaixo. Medido pela
   POSIÇÃO na tela, não pela ordem no HTML.
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
const erros = [];
async function painel(quando, largura = 390){
  const ctx = await nav.newContext({ viewport:{ width: largura, height: 900 },
    timezoneId: 'America/Sao_Paulo', isMobile: largura < 700 });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.dismiss());
  await p.clock.install({ time: new Date(quando) });
  await p.goto(BASE + 'app.html?demo=1');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && typeof diaAtual === 'string', null, { timeout: 15000 });
  await p.waitForTimeout(1500);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  return { p, ctx };
}
const estado = p => p.evaluate(() => ({ dia: diaAtual,
  hoje: (document.querySelector('.mes-dia.hoje .mes-num') || {}).textContent || null,
  rotulo: document.getElementById('rotuloDia').textContent.trim() }));
const acordar = (p, como) => p.evaluate(c => c === 'foco' ? window.dispatchEvent(new Event('focus'))
  : document.dispatchEvent(new Event('visibilitychange')), como);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. O painel dorme no dia 30 e acorda no dia 4');
{
  const { p, ctx } = await painel('2026-09-30T18:00:00-03:00');
  igual('abre no dia de hoje do aparelho', (await estado(p)).dia, '2026-09-30');
  await p.click('#vistas button:has-text("Mês")'); await p.waitForTimeout(500);

  await p.clock.setSystemTime(new Date('2026-10-04T15:30:00-03:00'));
  await acordar(p, 'visivel'); await p.waitForTimeout(400);
  const e = await estado(p);
  igual('ao voltar para o app: vai para hoje, em outubro, com o dia 4 marcado como hoje',
    [e.dia, /outubro/i.test(e.rotulo), e.hoje], ['2026-10-04', true, '4']);

  /* Andar para outro dia e sair por um minuto não pode jogar o dono de volta
     para hoje: só a VIRADA do dia faz isso. */
  await p.evaluate(() => escolherDiaDoMes('2026-10-15')); await p.waitForTimeout(200);
  await p.clock.setSystemTime(new Date('2026-10-04T15:45:00-03:00'));
  await acordar(p, 'foco'); await p.waitForTimeout(300);
  igual('no mesmo dia, o dia que ele escolheu fica', (await estado(p)).dia, '2026-10-15');

  // E o painel aberto atravessando a meia-noite: o relógio de um minuto vê.
  await p.clock.setSystemTime(new Date('2026-10-05T00:00:30-03:00'));
  await p.clock.runFor(61000); await p.waitForTimeout(300);
  igual('aberto na tela, passou da meia-noite: vai para o dia novo sozinho', (await estado(p)).dia, '2026-10-05');
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. A agenda primeiro, os números embaixo');
for(const largura of [390, 1280]){
  const { p, ctx } = await painel('2026-10-04T15:30:00-03:00', largura);
  const dia = await p.evaluate(() => {
    const t = id => document.getElementById(id).getBoundingClientRect();
    const g = document.querySelector('#tela-agenda .grade-wrap').getBoundingClientRect();
    return { grade: g.top, kpis: t('kpisDia').top, kpisAltura: t('kpisDia').height };
  });
  verdade(`${largura}px, dia: a grade de horários vem antes dos cartões`,
    dia.kpis > dia.grade && dia.kpisAltura > 0, JSON.stringify(dia));
  await p.click('#vistas button:has-text("Mês")'); await p.waitForTimeout(500);
  const mes = await p.evaluate(() => {
    const t = id => document.getElementById(id).getBoundingClientRect();
    return { cal: t('mesCalendario').top, lista: t('listaDoDia').top, kpis: t('kpisDia').top,
      kpisTexto: document.getElementById('kpisDia').innerText };
  });
  verdade(`${largura}px, mês: calendário, depois quem vem no dia, depois os números`,
    mes.cal < mes.lista && mes.lista < mes.kpis && /agendamentos no dia/.test(mes.kpisTexto), JSON.stringify(mes));
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
