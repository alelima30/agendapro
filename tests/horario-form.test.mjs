/* ===========================================================================
   AgendaPro — o horário no "+ Agendamento" (e nos outros campos de hora)

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/horario-form.test.mjs

   O relato, com prints do celular: o campo "Início" era o relógio do
   Android, e o botão de confirmar desse relógio ficava fora da tela. A hora
   não era escolhida, o campo ficava vazio — e vazio era lido como 00:00: o
   aviso dizia "00:00 às 01:00" e "Fora da jornada", e o Agendar oferecia um
   encaixe à meia-noite. E os horários livres não apareciam em lugar nenhum.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. aberto sem hora: o campo vazio NÃO vira 00:00 nem "Fora da jornada";
     2. com o serviço escolhido, os horários livres aparecem em botões — os
        mesmos da agenda — e tocar escolhe;
     3. sem hora, o Agendar não marca; com hora, marca nela;
     4. dia sem vaga mostra os próximos dias com vaga, e tocar leva até lá;
     5. hoje, nenhum horário que já passou;
     6. a hora digitada: "930" → 9:30 → 09:30; "1430" → 14:30; hora que não
        existe não passa;
     7. nenhum campo de hora do painel abre o relógio do celular (bloqueio,
        jornada, regra de preço, passo a passo), e o bloqueio grava com a
        hora digitada;
     8. no celular: alvos de 40px, nada vazando para o lado.
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
const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
const p = await ctx.newPage();
const erros = [];
let alertas = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => { alertas.push(d.message()); d.accept(); });
await p.goto(BASE + 'app.html?demo=1');
await p.waitForTimeout(2200);
await p.evaluate(() => { try{ fecharModal(); }catch(e){} document.getElementById('primeiroDia').hidden = true; });

const ler = () => p.evaluate(() => ({
  inicio: document.getElementById('fInicio').value,
  aviso: document.getElementById('avisoAg').innerText.replace(/\s+/g, ' '),
  livres: [...document.querySelectorAll('#fLivres .hl-op')].map(b => b.textContent.trim()),
  on: [...document.querySelectorAll('#fLivres .hl-op.on')].map(b => b.textContent.trim()),
  nota: (document.querySelector('#fLivres .hl-nota') || {}).textContent || '',
}));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Aberto sem hora');
const DIA = await p.evaluate(() => {
  // Um dia útil daqui a alguns dias, com a primeira profissional trabalhando.
  let d = somarDias(hoje(), 3);
  const pr = profsAtivos()[0];
  while(!jornadaDo(pr, d).length) d = somarDias(d, 1);
  diaAtual = d; abrirNovo();
  return d;
});
await p.waitForTimeout(250);
const r0 = await ler();
igual('o campo de hora começa vazio (ninguém escolheu)', r0.inicio, '');
verdade('e o vazio NÃO vira 00:00 nem "Fora da jornada"',
  !/00:00|Fora da jornada/.test(r0.aviso), r0.aviso);
verdade('sem serviço, pede o serviço — é a duração dele que mostra os livres',
  /Escolha ao menos um serviço/.test(r0.aviso) && /Escolha o serviço para ver os horários livres/.test(r0.nota),
  JSON.stringify(r0));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Os horários livres, em botões');
await p.click('.lista-serv .serv-op'); await p.waitForTimeout(200);
const r1 = await ler();
const conta = await p.evaluate(() => {
  const profId = document.getElementById('fProf').value;
  const data = document.getElementById('fData').value;
  const dur = [...document.querySelectorAll('.serv-op input:checked')]
    .reduce((s, c) => { const sv = acharServico(c.value); return s + sv.duracaoMin + (sv.intervaloMin || 0); }, 0);
  const livres = horariosLivres(profId, data, dur).map(hm);
  const todosCabem = livres.every(t => avaliarHorario(profId, data, minDe(t), minDe(t) + dur, null).cabe);
  return { livres, todosCabem, nome: acharProf(profId).nome };
});
verdade('aparecem os horários livres de quem atende, no dia — ' + r1.livres.length + ' horários',
  r1.livres.length > 0 && JSON.stringify(r1.livres) === JSON.stringify(conta.livres),
  JSON.stringify({ tela: r1.livres.slice(0, 5), conta: conta.livres.slice(0, 5) }));
verdade('todos eles cabem de verdade (sem choque, sem bloqueio, dentro da jornada)', conta.todosCabem);
verdade('com o nome de quem atende, e o pedido para escolher',
  r1.nota.includes(conta.nome) && /Escolha o horário/.test(r1.aviso), JSON.stringify(r1));

await p.click('#fLivres .hl-op:nth-child(3)'); await p.waitForTimeout(150);
const r2 = await ler();
igual('tocar num horário escolhe ele: o campo e o botão marcado',
  [r2.inicio, r2.on], [r1.livres[2], [r1.livres[2]]]);
verdade('e o aviso mostra a faixa certa, sem "Fora da jornada"',
  r2.aviso.startsWith(r1.livres[2] + ' às') && !/Fora da jornada/.test(r2.aviso), r2.aviso);

// Digitou a hora e depois tocou num botão: o primeiro toque tem que valer.
await p.fill('#fInicio', ''); await p.type('#fInicio', '1');
await p.click('#fLivres .hl-op:nth-child(4)'); await p.waitForTimeout(150);
igual('quem digitou e depois toca num horário: o PRIMEIRO toque escolhe',
  await p.inputValue('#fInicio'), r1.livres[3]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Agendar');
await p.fill('#fInicio', ''); await p.waitForTimeout(100);
alertas = [];
const n0 = await p.evaluate(() => bd.agendamentos.length);
await p.evaluate(() => { document.getElementById('fNome').value = 'Rita Hora'; salvarAgendamento(); });
await p.waitForTimeout(300);
igual('sem hora, não marca — e diz o que falta',
  [await p.evaluate(n => bd.agendamentos.length - n, n0), /Escolha o horário/.test(alertas.join(' '))], [0, true]);
await p.click('#fLivres .hl-op:nth-child(2)'); await p.waitForTimeout(100);
await p.evaluate(() => salvarAgendamento()); await p.waitForTimeout(400);
const marcado = await p.evaluate(n => {
  const a = bd.agendamentos[bd.agendamentos.length - 1];
  return { mais: bd.agendamentos.length - n, inicio: hm(a.inicio), data: a.data };
}, n0);
igual('com um horário livre escolhido, marca nele', marcado, { mais: 1, inicio: r1.livres[1], data: DIA });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Dia sem vaga');
const cheio = await p.evaluate(d => {
  const pr = profsAtivos()[0];
  bd.bloqueios.push({ id: 'dia-todo', salaoId: salaoAtual, profissionalId: pr.id, data: d,
                      inicio: 0, fim: 24 * 60, motivo: 'teste' });
  abrirNovo(pr.id);
  document.getElementById('fData').value = d;
  const cx = document.querySelector('.lista-serv .serv-op input');
  cx.checked = true; marcarServico(cx);
  return {
    nota: document.querySelector('#fLivres .hl-nota').textContent.replace(/\s+/g, ' '),
    dias: [...document.querySelectorAll('#fLivres .hl-dia')].map(b => b.textContent.replace(/\s+/g, ' ').trim()),
  };
}, DIA);
verdade('diz que não há horário livre, e mostra os próximos dias com vaga — ' + cheio.dias.join(' | '),
  /Sem horário livre com .+ neste dia/.test(cheio.nota) && cheio.dias.length > 0 && /vaga/.test(cheio.dias[0]),
  JSON.stringify(cheio));
await p.click('#fLivres .hl-dia'); await p.waitForTimeout(150);
const foi = await p.evaluate(d => ({ data: document.getElementById('fData').value,
  livres: document.querySelectorAll('#fLivres .hl-op').length, depois: document.getElementById('fData').value > d }), DIA);
verdade('tocar num deles leva até o dia, já com os horários livres',
  foi.depois && foi.livres > 0, JSON.stringify(foi));
await p.evaluate(() => { bd.bloqueios = bd.bloqueios.filter(b => b.id !== 'dia-todo'); fecharModal(); });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Hoje');
const hojeR = await p.evaluate(() => {
  const pr = profsAtivos()[0];
  // Hoje com a jornada do dia inteiro, para haver horário antes E depois de agora.
  const d = hoje(), dow = diaDaSemana(d);
  const antes = JSON.stringify(pr.jornada);
  pr.jornada = Object.assign({}, pr.jornada, { [dow]: [[0, 24 * 60 - 15]] });
  abrirNovo(pr.id);
  document.getElementById('fData').value = d;
  const cx = document.querySelector('.lista-serv .serv-op input');
  cx.checked = true; marcarServico(cx);
  const sl = acharSalao(salaoAtual);
  const agora = sl && sl.fuso ? instanteParaTela(new Date().toISOString(), sl.fuso)
                              : { min: new Date().getHours() * 60 + new Date().getMinutes() };
  const livres = [...document.querySelectorAll('#fLivres .hl-op')].map(b => minDe(b.textContent.trim()));
  pr.jornada = JSON.parse(antes); fecharModal();
  return { passados: livres.filter(t => t < agora.min).length, total: livres.length };
});
igual('hoje, nenhum horário que já passou aparece', hojeR.passados, 0);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. A hora digitada');
await p.evaluate(() => { const pr = profsAtivos()[0]; abrirNovo(pr.id); });
await p.waitForTimeout(150);
const digita = async txt => { await p.fill('#fInicio', ''); await p.type('#fInicio', txt); return p.inputValue('#fInicio'); };
const casos = {};
for(const t of ['930', '1430', '0915', '99', '1260', '2460', '7']) casos[t] = await digita(t);
/* Digitado número a número, como no celular. "99": não há hora 99 nem
   minuto 9x — fica o 9. "1260": o 6 é recusado (minuto não começa com 6) e o
   0 seguinte entra — 12:0. "2460": não há hora 24, então é 2:46, que existe. */
igual('a máscara: 930 → 9:30, 1430 → 14:30, 0915 → 09:15, e hora que não existe não passa',
  casos, { '930': '9:30', '1430': '14:30', '0915': '09:15', '99': '9', '1260': '12:0', '2460': '2:46', '7': '7' });
await digita('930'); await p.locator('#fInicio').blur(); await p.waitForTimeout(100);
const completou = await p.inputValue('#fInicio');
await digita('7'); await p.locator('#fInicio').blur(); await p.waitForTimeout(100);
igual('ao sair do campo, a hora se completa: 9:30 → 09:30, 7 → 07:00',
  [completou, await p.inputValue('#fInicio')], ['09:30', '07:00']);
await p.evaluate(() => fecharModal());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. Nenhum campo de hora abre o relógio do celular');
const relogios = await p.evaluate(() => {
  const conta = () => document.querySelectorAll('input[type="time"]').length;
  const pr = profsAtivos()[0], sv = servsAtivos()[0];
  const r = {};
  abrirNovo(pr.id); r.agendamento = conta(); fecharModal();
  abrirBloqueio(pr.id); r.bloqueio = conta(); fecharModal();
  abrirProf(pr.id); r.jornada = conta(); fecharModal();
  abrirRegraDePreco(sv.id, null); r.regraDePreco = conta(); fecharModal();
  abrirPrimeiroDia(2); r.passoAPasso = conta(); document.getElementById('primeiroDia').hidden = true;
  return r;
});
igual('"+ Agendamento", bloqueio, jornada, regra de preço e passo a passo: zero relógios',
  relogios, { agendamento: 0, bloqueio: 0, jornada: 0, regraDePreco: 0, passoAPasso: 0 });

alertas = [];
const bloq = await p.evaluate(() => {
  const pr = profsAtivos()[0];
  abrirBloqueio(pr.id);
  const ini = document.getElementById('bIni'), fim = document.getElementById('bFim');
  ini.value = '12'; ini.dispatchEvent(new Event('change'));
  fim.value = '13:3'; fim.dispatchEvent(new Event('change'));
  const n = bd.bloqueios.length;
  salvarBloqueio(pr.id);
  const b = bd.bloqueios[bd.bloqueios.length - 1];
  const r = { mais: bd.bloqueios.length - n, ini: hm(b.inicio), fim: hm(b.fim), campos: [ini.value, fim.value] };
  bd.bloqueios.pop();
  return r;
});
igual('o bloqueio grava com a hora digitada ("12" e "13:3" viram 12:00 e 13:30)',
  bloq, { mais: 1, ini: '12:00', fim: '13:30', campos: ['12:00', '13:30'] });
const bloqRuim = await p.evaluate(() => {
  const pr = profsAtivos()[0];
  abrirBloqueio(pr.id);
  document.getElementById('bIni').value = '';
  const n = bd.bloqueios.length;
  salvarBloqueio(pr.id);
  const r = bd.bloqueios.length - n; fecharModal(); return r;
});
igual('e hora em branco não vira um bloqueio à meia-noite', [bloqRuim, /Confira as horas/.test(alertas.join(' '))], [0, true]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('8. No celular');
const cel = await p.evaluate(d => {
  const pr = profsAtivos()[0];
  abrirNovo(pr.id);
  document.getElementById('fData').value = d;
  const cx = document.querySelector('.lista-serv .serv-op input');
  cx.checked = true; marcarServico(cx);
  const pequenos = [...document.querySelectorAll('#fLivres button, #fInicio')]
    .filter(el => { const r = el.getBoundingClientRect(); return r.height > 0 && r.height < 40; }).length;
  const vaza = document.documentElement.scrollWidth - document.documentElement.clientWidth;
  fecharModal();
  return { pequenos, vaza };
}, DIA);
igual('em 390px: todo horário e o campo têm os 40px de toque, e nada vaza para o lado', cel, { pequenos: 0, vaza: 0 });

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
