/* ===========================================================================
   AgendaPro — aniversariantes no painel

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/aniversarios.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Como lembrar os parabéns das clientes?" — e, na escolha: "que apareça
   somente no app por enquanto". A data já era guardada e o recado "Dar os
   parabéns" já existia; faltava uma tela dizer QUEM faz aniversário.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. O DIA CERTO. Hoje entra no cartão do Hoje; amanhã e a semana, só no
        Dashboard; daqui a dez dias, em nenhum. E o "hoje" é o do SALÃO.
     2. 29 DE FEVEREIRO. Nos anos que não são bissextos a festa é no dia 28 —
        senão a cliente some do aviso três anos em cada quatro.
     3. O BOTÃO. Abre o WhatsApp do salão com o recado de parabéns, com o
        primeiro nome dela e o nome da casa — e só no dia. Ficha sem telefone
        avisa, em vez de abrir uma conversa com ninguém.
     4. SÓ AVISA. Nada vai para a fila de mensagens da Meta.
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

/* O "hoje" do SALÃO (São Paulo), e não o do relógio da máquina de teste —
   o mesmo cuidado do `hojeNoSalao()` das outras suítes. */
const hojeSP = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
const maisDias = (isoDia, n) => {
  const [a, m, d] = isoDia.split('-').map(Number);
  const dt = new Date(Date.UTC(a, m - 1, d + n));
  return dt.toISOString().slice(0, 10);
};
// Mesmo dia e mês, `anos` anos para trás.
const nasceu = (isoDia, anos) => (Number(isoDia.slice(0, 4)) - anos) + isoDia.slice(4);
const tel = () => '11' + (900000000 + Math.floor(Math.random() * 99999999));

const HOJE = hojeSP();
const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`niver-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa Niver ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const NOME_SALAO = 'Casa Niver ' + marca;

const fichas = {
  bia:   { nome:'Bia Souza',   telefone: tel(), nascimento: nasceu(HOJE, 30) },
  gabi:  { nome:'Gabi Lima',   telefone: null,  nascimento: nasceu(maisDias(HOJE, 0), 25) },
  carla: { nome:'Carla Dias',  telefone: tel(), nascimento: nasceu(maisDias(HOJE, 1), 41) },
  dani:  { nome:'Dani Rocha',  telefone: tel(), nascimento: nasceu(maisDias(HOJE, 5), 19) },
  eva:   { nome:'Eva Prado',   telefone: tel(), nascimento: nasceu(maisDias(HOJE, 10), 33) },
  fe:    { nome:'Fê Sem Data', telefone: tel(), nascimento: null },
};
for(const f of Object.values(fichas)){
  const c = await dona.inserir('clientes', { salaoId: SALAO, ...f });
  f.id = c.id;
}
ok('salão com seis fichas: hoje (duas), amanhã, daqui a 5 e a 10 dias, e sem data');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 } });
const p = await ctx.newPage();
const erros = [];
const dialogos = [];
p.on('pageerror', e => erros.push(e.message));
p.on('console', c => { if(c.type()==='error') erros.push('console: ' + c.text()); });
p.on('dialog', async d => { dialogos.push(d.message()); await d.accept(); });

await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  // O botão abre o WhatsApp numa aba nova. Aqui ele só anota para onde iria.
  window.__abertos = [];
  window.open = (u) => { window.__abertos.push(String(u)); return null; };
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1200);

const abrirAba = async (chave, corpo) => {
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} });
  const gaveta = await p.$('.menu-botao');
  if(gaveta && await gaveta.isVisible()){ await gaveta.click(); await p.waitForTimeout(350); }
  await p.click(`#abas .aba[data-chave="${chave}"]`);
  await p.waitForFunction(id => {
    const a = document.getElementById(id);
    return a && a.innerText && !/Somando/.test(a.innerText);
  }, corpo, { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(400);
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — A CONTA
   ══════════════════════════════════════════════════════════════════════════ */
secao('Quem faz aniversário, e quando');

const semana = await p.evaluate(() => aniversariantes(7)
  .map(x => [x.chamada, x.faltam, x.idade]));
console.log('      ' + JSON.stringify(semana));
igual('hoje, amanhã e daqui a 5 dias, nessa ordem; os de hoje por nome',
  semana.map(x => x[0]), ['Bia Souza', 'Gabi Lima', 'Carla Dias', 'Dani Rocha']);
igual('com quantos dias faltam', semana.map(x => x[1]), [0, 0, 1, 5]);
igual('e quantos anos fazem', semana.map(x => x[2]), [30, 25, 41, 19]);
verdade('daqui a 10 dias fica de fora da semana',
  !semana.some(x => x[0] === 'Eva Prado'));
verdade('e ficha sem data não entra em lugar nenhum',
  !(await p.evaluate(() => aniversariantes(366).some(x => x.chamada === 'Fê Sem Data'))));
igual('com 10 dias de janela, ela aparece', await p.evaluate(() =>
  aniversariantes(10).filter(x => x.chamada === 'Eva Prado').map(x => x.faltam)), [10]);

/* ⚠ 29 DE FEVEREIRO. O `hoje()` é trocado por um instante para cair nas datas
   que interessam, e devolvido logo depois. */
const bissexto = await p.evaluate(() => {
  const original = window.hoje;
  const c = { id:'x29', salaoId: salaoAtual, nome:'Lia Bissexta',
              telefone:'11988887777', nascimento:'2000-02-29' };
  bd.clientes.push(c);
  const em = d => { window.hoje = () => d;
    return aniversariantes(0).some(x => x.chamada === 'Lia Bissexta'); };
  const r = { a2027_28: em('2027-02-28'), a2027_0301: em('2027-03-01'),
              a2028_28: em('2028-02-28'), a2028_29: em('2028-02-29') };
  window.hoje = original;
  bd.clientes.splice(bd.clientes.indexOf(c), 1);
  return r;
});
igual('nascida em 29/02: num ano comum, a festa é no dia 28', bissexto.a2027_28, true);
igual('e não no 1º de março', bissexto.a2027_0301, false);
igual('no ano bissexto, é no 29 — e não no 28',
  [bissexto.a2028_28, bissexto.a2028_29], [false, true]);

const virada = await p.evaluate(() => {
  const original = window.hoje;
  const c = { id:'xano', salaoId: salaoAtual, nome:'Nina Virada',
              telefone:'11988886666', nascimento:'1990-01-02' };
  bd.clientes.push(c);
  window.hoje = () => '2026-12-30';
  const r = aniversariantes(7).filter(x => x.chamada === 'Nina Virada')
    .map(x => [x.dia, x.faltam, x.idade]);
  window.hoje = original;
  bd.clientes.splice(bd.clientes.indexOf(c), 1);
  return r;
});
igual('na virada do ano, 30/12 já enxerga o 2 de janeiro, com a idade do ano novo',
  virada, [['2027-01-02', 3, 37]]);

/* Ficha antiga com ano 1900 é data dada só com dia e mês: o aniversário vale,
   a idade não — "faz 126 anos" seria piada na tela do dono. */
const semAno = await p.evaluate(() => {
  const original = window.hoje;
  const c = { id:'xsa', salaoId: salaoAtual, nome:'Iris Sem Ano',
              telefone:'11988885555', nascimento:'1900-06-10' };
  bd.clientes.push(c);
  window.hoje = () => '2026-06-10';
  const r = aniversariantes(0).filter(x => x.chamada === 'Iris Sem Ano')
    .map(x => [x.idade, linhaNiver(x).includes('anos')]);
  window.hoje = original;
  bd.clientes.splice(bd.clientes.indexOf(c), 1);
  return r;
});
igual('ano 1900: entra no aviso, mas sem idade inventada', semAno, [[null, false]]);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A TELA HOJE
   ══════════════════════════════════════════════════════════════════════════ */
secao('O cartão na tela Hoje');

await abrirAba('hoje', 'hojeCorpo');
if(process.env.PRINT){
  await p.evaluate(() => document.getElementById('niverHoje').scrollIntoView({block:'center'}));
  await p.screenshot({ path: process.env.PRINT + '/niver-hoje.png' });
}
const naHoje = await p.evaluate(() => {
  const c = document.getElementById('niverHoje');
  return c ? { titulo: c.querySelector('h3').innerText.trim(),
               linhas: [...c.querySelectorAll('.niver-linha')].map(l => l.innerText.replace(/\s+/g, ' ').trim()),
               botoes: c.querySelectorAll('.niver-linha .btn').length,
               icone: !!c.querySelector('h3 svg, h3 [data-ico]') } : null;
});
console.log('      ' + JSON.stringify(naHoje));
verdade('aparece o cartão de aniversário', !!naHoje, 'o cartão não apareceu na tela Hoje');
if(naHoje){
  igual('no plural, porque são duas', naHoje.titulo, 'Aniversários hoje');
  igual('com as duas de hoje e só elas', naHoje.linhas.length, 2);
  verdade('com o nome e a idade',
    /Bia Souza/.test(naHoje.linhas[0]) && /faz 30 anos/.test(naHoje.linhas[0]), naHoje.linhas[0]);
  igual('e um botão de parabéns em cada uma', naHoje.botoes, 2);
  verdade('quem faz amanhã não entra no Hoje',
    !naHoje.linhas.some(l => /Carla/.test(l)));
}

// O botão abre o WhatsApp do salão com o recado de parabéns.
await p.evaluate(() => { window.__abertos.length = 0; });
await p.click('#niverHoje .niver-linha:first-of-type .btn');
await p.waitForTimeout(300);
const aberto = await p.evaluate(() => window.__abertos.slice());
console.log('      ' + (aberto[0] || '(nada)').slice(0, 140));
verdade('o botão abre o WhatsApp',
  aberto.length === 1 && aberto[0].startsWith('https://wa.me/55' + fichas.bia.telefone + '?text='),
  JSON.stringify(aberto));
const texto = aberto[0] ? decodeURIComponent(aberto[0].split('?text=')[1] || '') : '';
verdade('com o primeiro nome dela, o parabéns e o nome do salão',
  /Bia\b/.test(texto) && !/Souza/.test(texto) && /feliz aniversário/i.test(texto)
    && texto.includes(NOME_SALAO), texto);
verdade('sem a sobra do ${horario}', !/\$\{|\bde\s*[.!?]?$/.test(texto), texto);
verdade('e sem passar pela janela de escolher recado',
  !(await p.evaluate(() => document.getElementById('fundo').classList.contains('on'))));

// Ficha sem telefone: avisa, e não abre conversa nenhuma.
dialogos.length = 0;
await p.evaluate(() => { window.__abertos.length = 0; });
await p.click('#niverHoje .niver-linha:nth-of-type(2) .btn');
await p.waitForTimeout(300);
verdade('ficha sem telefone avisa o que fazer',
  dialogos.some(m => /não tem telefone/.test(m)), JSON.stringify(dialogos));
igual('e não abre WhatsApp nenhum', await p.evaluate(() => window.__abertos.length), 0);

// Dia sem aniversariante: o cartão nem aparece.
igual('dia sem ninguém: o Hoje não ganha cartão vazio', await p.evaluate(() => {
  const original = window.hoje;
  window.hoje = () => '2026-01-01';
  const r = blocoNiverHoje();
  window.hoje = original;
  return r;
}), '');

/* ══════════════════════════════════════════════════════════════════════════
   3 — O DASHBOARD
   ══════════════════════════════════════════════════════════════════════════ */
secao('O cartão no Dashboard');

igual('o cartão está no catálogo, desligado de fábrica',
  await p.evaluate(() => [CARTOES_DASH.some(c => c[0] === 'aniversarios'),
                          PADRAO_DASHBOARD.includes('aniversarios')]), [true, false]);

await abrirAba('dashboard', 'dashCorpo');
await p.evaluate(() => {
  acharSalao(salaoAtual).cfg = { ...(acharSalao(salaoAtual).cfg || {}), dashboard: ['aniversarios'] };
  desenharDash();
});
if(process.env.PRINT){
  await p.evaluate(() => document.querySelector('#dashCorpo .dash-card').scrollIntoView({block:'center'}));
  await p.screenshot({ path: process.env.PRINT + '/niver-dash.png' });
}
const noDash = await p.evaluate(() => {
  const c = document.querySelector('#dashCorpo .dash-card[data-cartao="aniversarios"]');
  return c ? { titulo: c.querySelector('h3').innerText.trim(),
               linhas: [...c.querySelectorAll('.niver-linha')].map(l => l.innerText.replace(/\s+/g, ' ').trim()),
               botoes: c.querySelectorAll('.niver-linha .btn').length,
               sub: (c.querySelector('.niver-sub') || {}).innerText || '' } : null;
});
console.log('      ' + JSON.stringify(noDash));
verdade('ligado, o cartão aparece', !!noDash);
if(noDash){
  igual('com o título', noDash.titulo, 'Aniversariantes');
  igual('as quatro da semana, e não a de daqui a 10 dias', noDash.linhas.length, 4);
  verdade('amanhã escrito como "amanhã"', noDash.linhas.some(l => /Carla Dias amanhã/.test(l)),
    JSON.stringify(noDash.linhas));
  verdade('e daqui a 5 dias com o dia da semana e a data',
    noDash.linhas.some(l => /Dani Rocha \w{3}, \d{2}\/\d{2}/.test(l)), JSON.stringify(noDash.linhas));
  igual('botão só para as de hoje — parabéns adiantado não', noDash.botoes, 2);
  igual('com a separação dos próximos dias', noDash.sub, 'Próximos dias');
}

igual('semana sem ninguém: o cartão diz, em vez de sumir', await p.evaluate(() => {
  const original = window.hoje;
  window.hoje = () => '2026-01-01';
  const r = /Ninguém faz aniversário/.test(dashAniversarios());
  window.hoje = original;
  return r;
}), true);

/* ══════════════════════════════════════════════════════════════════════════
   4 — ⚠ SÓ AVISA
   ══════════════════════════════════════════════════════════════════════════ */
secao('Nada vai para a fila da Meta');

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: Number(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
igual('nenhuma notificação nasceu para o salão',
  Number((await banco.query(`select count(*) from public.notificacoes where salao_id=$1`,
    [SALAO])).rows[0].count), 0);
await banco.end();

igual('sem erro de JavaScript na página', erros, []);

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} verificações dos aniversariantes`
  + (falhou ? `, ${falhou} falharam.` : '.'));
process.exit(falhou ? 1 : 0);
