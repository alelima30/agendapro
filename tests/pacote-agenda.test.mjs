/* ===========================================================================
   AgendaPro — o pacote com agenda fixa e o pagamento, nas telas (43)

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/pacote-agenda.test.mjs

   "Ela paga mensal e vai toda terça às 14h: na primeira faz mão, na segunda
    mão e pé, na terceira só mão, na quarta mão e pé." O banco tem o
   tests/pacote_agenda.test.sql. Aqui, com a RECEPÇÃO logada:

     1. a aba Pacotes aparece para a recepção (sem criar nem editar pacote);
     2. vincular com agenda fixa: as 4 terças, tocando nos serviços de cada
        uma; o pagamento fica a receber; o recado pelo WhatsApp do salão leva
        as datas, o valor e a chave Pix;
     3. a semana que não cabe fica em vermelho com o porquê, e nada é gravado
        até trocar o horário;
     4. "A receber" no topo, "Recebi", e o horário passa a dizer "já paga";
     5. Renovar abre as próximas 4 terças no mesmo esquema;
     6. quem atende não vê a aba.
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
const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const tel = () => '+5511' + (900000000 + Math.floor(Math.random() * 89999999));
const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const linhas = async (q, v) => (await banco.query(q, v)).rows;

// ── O salão: a dona, a recepção (Rita), a Ju (profissional, com login) ─────
const dDona = novaAba();
await dDona.criarConta({ email:`pa-dona-${marca}@teste.com`, senha:'minhasenhaboa', nome:'Ju Barbosa', telefone: tel() });
const cr = await dDona.chamar('criar_salao', { p_nome_salao:'Salão Agenda Fixa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
await banco.query(`update public.assinaturas set plano='time', status='ativa' where salao_id=$1`, [SALAO]);
await dDona.atualizar('saloes', SALAO, { cfg: { diasLiberados:30, confirmaAuto:true,
  pagamentos: { formas:['pix'], obs:'', pix:'pix@agendafixa.com.br' } } });
const P1 = (await dDona.lista('profissionais', { salaoId: SALAO }))[0];
const JU = await dDona.inserir('profissionais', { salaoId: SALAO, nome:'Ju Unhas', ativo:true,
  aceitaOnline:true, comissaoPct:40, cor:'#7C3AED' });
for(const p of [P1, JU])
  for(let i = 0; i <= 6; i++)
    await dDona.inserir('jornadas', { profissionalId: p.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const MAO = await dDona.inserir('servicos', { salaoId: SALAO, nome:'Mão', duracaoMin:45, intervaloMin:0,
  preco:40, ativo:true, aceitaOnline:true });
const PE = await dDona.inserir('servicos', { salaoId: SALAO, nome:'Pé', duracaoMin:45, intervaloMin:0,
  preco:50, ativo:true, aceitaOnline:true });
const PAC = await dDona.inserir('pacotes', { salaoId: SALAO, nome:'Mão e pé mensal', preco:300,
  sessoes:4, validadeDias:30, dias:[0,1,2,3,4,5,6], soNosDias:false, ativo:true });
for(const s of [MAO, PE]) await dDona.inserir('pacote_servicos', { pacoteId: PAC.id, servicoId: s.id });
const MARIA = await dDona.inserir('clientes', { salaoId: SALAO, nome:'Maria Souza',
  telefone:'11' + (900000000 + Math.floor(Math.random() * 99999999)) });
const JOANA = await dDona.inserir('clientes', { salaoId: SALAO, nome:'Joana Lima',
  telefone:'11' + (900000000 + Math.floor(Math.random() * 99999999)) });

async function convidar(papel, nome, ficha){
  const r = await dDona.chamar('criar_convite', { p_salao: SALAO, p_papel: papel, p_para_quem: nome,
    p_profissional: ficha || null });
  const d = novaAba();
  await d.criarConta({ email:`pa-${papel}-${marca}@teste.com`, senha:'minhasenhaboa', nome, telefone: tel() });
  await d.chamar('aceitar_convite', { p_token: r.token });
  return d;
}
const dRita = await convidar('recepcao', 'Rita Recepção');
const dJu = await convidar('profissional', 'Ju Unhas', JU.id);

// A primeira terça a pelo menos uma semana de hoje.
const terca = (() => { const d = new Date(); d.setUTCHours(12, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() + 7); while(d.getUTCDay() !== 2) d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10); })();
const maisDias = (d, n) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n);
  return x.toISOString().slice(0, 10); };
const ddmm = d => d.slice(8, 10) + '/' + d.slice(5, 7);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrirPainel(dados, rotulo){
  const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(rotulo + ': ' + e.message));
  p.on('dialog', d => { erros.push(rotulo + ' (alerta): ' + d.message()); d.accept(); });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
    window.__abriu = []; window.open = u => { window.__abriu.push(String(u)); return null; }; }, [BASE, dados.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.profissionais.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  return { ctx, p };
}
const abas = p => p.evaluate(() => [...document.querySelectorAll('#abas .aba')].map(b => b.dataset.chave));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A recepção vê a aba Pacotes');
const { ctx: ctxRita, p } = await abrirPainel(dRita, 'rita');
verdade('a aba Pacotes aparece para a recepção', (await abas(p)).includes('pacotes'));
await p.evaluate(() => irPara('pacotes'));
await p.waitForTimeout(400);
igual('sem criar nem editar pacote (isso é da gestão), mas com "+ Vincular cliente"',
  await p.evaluate(() => ({ novo: getComputedStyle(document.getElementById('btNovoPacote')).display !== 'none',
    editar: !![...document.querySelectorAll('#listaPacotes button')].find(b => b.textContent.trim() === 'Editar'),
    vincular: !![...document.querySelectorAll('#listaPacotes button')].find(b => /Vincular cliente/.test(b.textContent)) })),
  { novo:false, editar:false, vincular:true });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Vincular a Maria com as 4 terças');
await p.click('#listaPacotes button:has-text("+ Vincular cliente")');
await p.waitForSelector('#pkCliente');
await p.selectOption('#pkCliente', MARIA.id);
igual('o valor vem do pacote, e o pagamento começa "a receber"',
  [await p.inputValue('#pkValor'), await p.inputValue('#pkForma')], ['300', '']);
await p.check('#pkFixa');
await p.selectOption('#pkProf', JU.id);
await p.fill('#pkData', terca);
await p.fill('#pkHora', '14:00');
await p.selectOption('#pkQtd', '4');
await p.evaluate(() => semanasDaMontagem());
igual('aparecem as 4 terças, uma semana de distância, com os dois serviços marcados',
  await p.evaluate(() => [...document.querySelectorAll('#pkSemanas .pk-semana')].map(s => [
    s.querySelector('input[type=date]').value,
    [...s.querySelectorAll('.pk-servicos button.on')].map(b => b.textContent.trim()).join('+')])),
  [0, 7, 14, 21].map(n => [maisDias(terca, n), 'Mão+Pé']));
for(const n of [1, 3])
  await p.click(`#pkSemanas .pk-semana:nth-child(${n}) .pk-servicos button:has-text("Pé")`);
await p.click('#fundo button:has-text("Agendar e vincular")');
await p.waitForSelector('.pk-lista', { timeout: 15000 });
const montado = await p.evaluate(() => document.querySelector('.modal').innerText.replace(/\s+/g, ' '));
verdade('"Pacote montado" lista as 4 terças com o serviço de cada uma',
  /ter \d\d\/\d\d às 14:00 · Mão ter \d\d\/\d\d às 14:00 · Mão \+ Pé ter \d\d\/\d\d às 14:00 · Mão ter \d\d\/\d\d às 14:00 · Mão \+ Pé/.test(montado),
  montado);
const vMaria = (await linhas(`select id, valor, pago_em from public.pacote_clientes where cliente_id=$1`, [MARIA.id]))[0];
igual('no banco: o vínculo a receber, com as 4 terças às 14h',
  { valor: vMaria.valor, pago: vMaria.pago_em,
    horas: (await linhas(`select to_char(inicio at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') h
      from public.agendamentos where pacote_cliente_id=$1 order by inicio`, [vMaria.id])).map(r => r.h) },
  { valor:'300.00', pago:null, horas:[0, 7, 14, 21].map(n => maisDias(terca, n) + ' 14:00') });
await p.click('#fundo button:has-text("Mandar no WhatsApp")');
const zap = decodeURIComponent(((await p.evaluate(() => window.__abriu)) || [])[0] || '');
verdade('o recado pelo WhatsApp do salão leva as datas, o valor e a chave Pix',
  zap.includes('Seu pacote Mão e pé mensal') && zap.includes(ddmm(terca) + ' às 14:00 — Mão')
  && zap.includes('Valor: R$') && zap.includes('300,00') && zap.includes('Para pagar no Pix: pix@agendafixa.com.br'), zap);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. A semana que não cabe');
await p.click('#listaPacotes button:has-text("+ Vincular cliente")');
await p.waitForSelector('#pkCliente');
await p.selectOption('#pkCliente', JOANA.id);
await p.check('#pkFixa');
await p.selectOption('#pkProf', JU.id);
await p.fill('#pkData', maisDias(terca, 7));
await p.fill('#pkHora', '14:00');
await p.selectOption('#pkQtd', '1');
await p.evaluate(() => semanasDaMontagem());
await p.click('#fundo button:has-text("Agendar e vincular")');
await p.waitForSelector('.pk-motivo', { timeout: 15000 });
const motivo = await p.textContent('.pk-motivo');
verdade('fica em vermelho, dizendo com quem está o horário', /Maria Souza/.test(motivo), motivo);
verdade('e avisa que nada foi marcado ainda', await p.isVisible('#pkErro'));
igual('no banco, nada da Joana', (await linhas(`select count(*)::int n from public.pacote_clientes where cliente_id=$1`, [JOANA.id]))[0].n, 0);
await p.fill('#pkSemanas .pk-semana input[type=time]', '16:00');
await p.dispatchEvent('#pkSemanas .pk-semana input[type=time]', 'change');
await p.click('#fundo button:has-text("Agendar e vincular")');
await p.waitForSelector('.pk-lista', { timeout: 15000 });
igual('trocando para 16h, marca', (await linhas(`select to_char(a.inicio at time zone 'America/Sao_Paulo', 'HH24:MI') h
  from public.agendamentos a join public.pacote_clientes pc on pc.id = a.pacote_cliente_id
  where pc.cliente_id=$1`, [JOANA.id])).map(r => r.h), ['16:00']);
await p.click('#fundo button:has-text("Fechar")');

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. A receber, e "Recebi"');
await p.waitForTimeout(300);
const topo = await p.evaluate(() => (document.querySelector('.pk-receber') || {}).innerText || '');
verdade('"A receber dos pacotes" no topo, com a Maria e a Joana', /A receber dos pacotes/.test(topo)
  && /Maria Souza/.test(topo) && /Joana Lima/.test(topo), topo);
const agMaria = (await linhas(`select id from public.agendamentos where pacote_cliente_id=$1 order by inicio limit 1`, [vMaria.id]))[0].id;
await p.evaluate(id => abrirDetalhe(id), agMaria);
await p.waitForTimeout(300);
verdade('o horário dela diz que o pacote ainda não foi pago',
  /ainda não foi pago: R\$\s?300,00 a receber/.test(await p.evaluate(() => document.querySelector('.modal').innerText)));
await p.evaluate(() => { fecharModal(); irPara('pacotes'); });
await p.waitForTimeout(300);
await p.click('.pk-receber-linha:has-text("Maria Souza") button:has-text("Recebi")');
await p.waitForSelector('#rpForma');
await p.selectOption('#rpForma', 'pix');
await p.click('#fundo button:has-text("Receber")');
await p.waitForTimeout(2500);
const pago = (await linhas(`select pc.pago_em is not null as pago, pc.forma_pagamento, pg.valor
  from public.pacote_clientes pc join public.pagamentos pg on pg.comanda_id = pc.comanda_id where pc.id=$1`, [vMaria.id]))[0] || {};
igual('recebido no Pix: pago, e a comanda do faturamento com R$ 300', [pago.pago, pago.forma_pagamento, pago.valor], [true, 'pix', '300.00']);
const depois = await p.evaluate(() => ({
  topo: (document.querySelector('.pk-receber') || {}).innerText || '',
  lista: document.getElementById('listaPacotes').innerText }));
verdade('a Maria sai do "a receber" (fica só a Joana) e aparece como "pago · Pix"',
  !/Maria Souza/.test(depois.topo) && /Joana Lima/.test(depois.topo) && /pago · Pix/.test(depois.lista),
  JSON.stringify(depois).slice(0, 500));
await p.evaluate(id => abrirDetalhe(id), agMaria);
await p.waitForTimeout(300);
verdade('e o horário passa a dizer que a sessão já foi paga',
  /esta sessão já foi paga/.test(await p.evaluate(() => document.querySelector('.modal').innerText)));
await p.evaluate(() => { fecharModal(); irPara('pacotes'); });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Renovar');
await p.waitForTimeout(300);
await p.click('#listaPacotes tr:has-text("Maria Souza") button:has-text("Renovar")');
await p.waitForSelector('#pkSemanas .pk-semana');
igual('abre as próximas 4 terças, no mesmo horário e com os mesmos serviços de cada uma',
  await p.evaluate(() => [...document.querySelectorAll('#pkSemanas .pk-semana')].map(s => [
    s.querySelector('input[type=date]').value, s.querySelector('input[type=time]').value,
    [...s.querySelectorAll('.pk-servicos button.on')].map(b => b.textContent.trim()).join('+')])),
  [28, 35, 42, 49].map((n, i) => [maisDias(terca, n), '14:00', i % 2 ? 'Mão+Pé' : 'Mão']));
await p.click('#fundo button:has-text("Agendar e vincular")');
await p.waitForSelector('.pk-lista', { timeout: 15000 });
igual('renovado: a Maria fica com 8 terças marcadas, em dois pacotes seguidos',
  (await linhas(`select count(*)::int n, count(distinct a.pacote_cliente_id)::int v from public.agendamentos a
     join public.pacote_clientes pc on pc.id = a.pacote_cliente_id where pc.cliente_id=$1 and a.status='confirmado'`, [MARIA.id]))[0],
  { n:8, v:2 });
await ctxRita.close();

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Quem atende não vê a aba');
{
  const { ctx, p: pj } = await abrirPainel(dJu, 'ju');
  verdade('a Ju (profissional) não vê Pacotes', !(await abas(pj)).includes('pacotes'));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. A comissão da sessão de pacote, no relatório da dona');
{
  // A primeira terça da Maria foi atendida (pela Ju, 40%). O pacote de R$ 300
  // cobre um cheio de R$ 260, então a sessão de mão vale o cheio: R$ 40, e a
  // comissão é R$ 16,00 (44_pacote_comissao.sql).
  await banco.query(`update public.agendamentos set status = 'concluido'
    where id = (select id from public.agendamentos where pacote_cliente_id = $1 order by inicio limit 1)`, [vMaria.id]);
  const { ctx, p: pd } = await abrirPainel(dDona, 'dona');
  await pd.evaluate(() => irPara('relatorios'));
  await pd.waitForFunction(() => /Ju Unhas/.test((document.getElementById('relCorpo') || {}).innerText || ''),
    null, { timeout: 15000 }).catch(() => {});
  const rel = await pd.evaluate(() => (document.getElementById('relCorpo') || {}).innerText || '');
  const linhaJu = await pd.evaluate(() => {
    const tr = [...document.querySelectorAll('#relCorpo tr')].find(t => /Ju Unhas/.test(t.textContent));
    return tr ? [...tr.children].map(td => td.textContent.replace(/\s+/g, ' ').trim()) : null; });
  igual('a Ju aparece no relatório com a terça atendida: vendeu R$ 40, comissão R$ 16',
    linhaJu, ['Ju Unhas', '1', 'R$ 40,00', 'R$ 16,00']);
  verdade('e a venda do pacote não vira linha "sem profissional"', !/sem profissional/.test(rel));
  await ctx.close();
}

verdade('sem erro de JavaScript nem alerta', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
