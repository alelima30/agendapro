/* ===========================================================================
   AgendaPro — a antecedência mínima que o salão escolhe

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/antecedencia.test.mjs

   ── O QUE ESTE AJUSTE FAZ ─────────────────────────────────────────────────
   Horário que começa em menos de N minutos some da agenda online. Era meia
   hora fixa para todo mundo; virou escolha do salão, porque uma barbearia de
   corte rápido atende quem aparece em 15 minutos e uma clínica precisa de
   horas para separar ficha e sala.

   ── ⚠ E O QUE ELE NÃO FAZ ─────────────────────────────────────────────────
   Não impede o choque com o atendimento combinado no balcão. Se a cliente
   passa de manhã e fica de voltar às 11h, e ninguém lança isso na agenda, o
   app continua oferecendo as 11h — e nenhuma antecedência conserta um
   atendimento que o sistema não conhece. A tela do painel diz isso com todas
   as letras, e a seção 5 daqui cobra que continue dizendo.

   ── POR QUE O TESTE PRECISA DAS DUAS PONTAS ───────────────────────────────
   O valor mora no `cfg` e é lido pela `horarios_livres()`. A `agendar()`
   reconsulta a MESMA função antes de gravar — é isso que faz a regra ser do
   banco e não da tela. Medir só a listagem deixaria passar o dia em que
   alguém "otimizasse" a `agendar()` para confiar no que o navegador mandou.
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
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
const igual = (m, a, b) => a === b ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
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
const d = novaAba();
await d.criarConta({ email:`ant-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona do Salão', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão Antecedência ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const prof = (await d.lista('profissionais', { salaoId: SALAO }))[0];

/* Jornada das 00:00 às 23:59, todos os dias. Não é realismo: é isolar a
   variável. Com jornada estreita, um horário some por causa do expediente e
   o teste creditaria à antecedência — medindo a coisa errada com placar
   verde. */
for(let i = 0; i <= 6; i++){
  await d.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                inicio:'00:00', fim:'23:59' });
}
const sv = await d.inserir('servicos', { salaoId:SALAO, nome:'Corte', preco:50,
  duracaoMin:30, intervaloMin:0, ativo:true, aceitaOnline:true });
ok('salão de teste, com a agenda aberta o dia inteiro');

const hoje = () => new Date().toISOString().slice(0, 10);
// Quantos minutos faltam para o primeiro horário que o motor oferece hoje.
async function primeiroDaqui(){
  const r = await d.chamar('horarios_livres_periodo', {
    p_profissionais:[prof.id], p_de:hoje(), p_ate:hoje(), p_servicos:[sv.id] });
  const todos = (Array.isArray(r) ? r : []).map(x => new Date(x.inicio).getTime())
    .sort((a, b) => a - b);
  return todos.length ? Math.round((todos[0] - Date.now()) / 60000) : null;
}
const usar = async (min) => d.atualizar('saloes', SALAO,
  { cfg: Object.assign({}, { diasLiberados:30 },
      min === undefined ? {} : { antecedenciaMin: min }) });

/* ══════════════════════════════════════════════════════════════════════════
   1 — SEM ESCOLHA NENHUMA, CONTINUA MEIA HORA

   É o caso de todos os salões que já existem. Se a ausência da chave não
   valesse 30, esta funcionalidade mudaria a agenda de quem está usando o
   sistema hoje sem ninguém ter pedido.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Sem escolha nenhuma');

await usar(undefined);
const padrao = await primeiroDaqui();
verdade('o primeiro horário está a 30 min ou mais — ' + padrao + ' min',
  padrao !== null && padrao >= 30,
  'o padrão deixou de ser meia hora, e salão antigo mudou de comportamento');
/* O passo da agenda é de 15 minutos, então o primeiro horário cai entre 30 e
   45 minutos daqui. Sem este teto, `antecedenciaMin` grande passaria também —
   e o teste diria "está certo" para uma agenda fechada demais. */
verdade('e não mais que 45, que é o passo seguinte — ' + padrao + ' min',
  padrao !== null && padrao <= 45, 'veio ' + padrao);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A ESCOLHA MANDA, PARA MAIS E PARA MENOS
   ══════════════════════════════════════════════════════════════════════════ */
secao('Cada valor da régua muda o primeiro horário');

const medidas = [];
for(const min of [0, 15, 30, 60, 120, 240]){
  await usar(min);
  const daqui = await primeiroDaqui();
  medidas.push({ min, daqui });
  verdade(`com ${min} min, o primeiro horário está a ${daqui} min`,
    daqui !== null && daqui >= min && daqui <= min + 15,
    'esperava entre ' + min + ' e ' + (min + 15) + ', veio ' + daqui);
}
/* ⚠ ESTRITAMENTE MAIOR, e não `>=`.

   Escrevi `>=` primeiro, e a verificação passou com `0→43, 15→43, 30→43,
   60→43, 120→43, 240→43` — exatamente o caso em que o ajuste era IGNORADO e
   o motor devolvia sempre o padrão. Uma asserção que aceita "tudo igual" não
   consegue distinguir "obedece" de "não obedece", que é a única coisa que ela
   existe para distinguir.

   A comparação é entre valores distantes (0 vs 240), e não entre vizinhos: o
   passo da agenda é de 15 minutos, então 0 e 15 podem legitimamente cair no
   mesmo horário. O que não pode é o primeiro e o último empatarem. */
const primeiro = medidas[0], ultimo = medidas[medidas.length - 1];
verdade('e o primeiro horário se afasta de verdade quando o ajuste cresce — '
  + medidas.map(m => m.min + '→' + m.daqui).join(', '),
  ultimo.daqui > primeiro.daqui + 200,
  'com ' + primeiro.min + ' min deu ' + primeiro.daqui + ' e com '
  + ultimo.min + ' min deu ' + ultimo.daqui + ': o ajuste não está sendo lido');
const sobe = medidas.every((m, i) => i === 0 || m.daqui >= medidas[i-1].daqui);
verdade('e nenhum valor maior aproxima o horário', sobe);

/* ══════════════════════════════════════════════════════════════════════════
   3 — A REGRA É DO BANCO, NÃO DA TELA

   O `agendar()` reconsulta a mesma `horarios_livres()`. Se um dia ele parar
   de reconsultar, uma página velha aberta no celular de alguém continuaria
   marcando horários que a regra nova já não oferece.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Tentar marcar por fora, ignorando a tela');

await usar(120);
// Um horário daqui a 30 minutos, no passo de 15. A tela NÃO o ofereceria.
const emBreve = new Date(Math.ceil((Date.now() + 30 * 60000) / 9e5) * 9e5);
let recusa = null;
try{
  await d.chamar('agendar', { p_profissional: prof.id, p_inicio: emBreve.toISOString(),
    p_servicos:[sv.id], p_nome:'Cliente Afobada', p_telefone:'+5511977776666' });
}catch(e){ recusa = e.message || String(e); }
verdade('o banco recusa um horário dentro da antecedência',
  recusa !== null, 'ACEITOU — a antecedência virou enfeite de tela');
verdade('e explica o motivo em português — ' + JSON.stringify(String(recusa).slice(0, 60)),
  /livre|antecedência|horário/i.test(String(recusa)), recusa);

// E o mesmo caminho aceita quando o horário está fora da antecedência.
const maisTarde = new Date(Math.ceil((Date.now() + 200 * 60000) / 9e5) * 9e5);
let aceitou = true, porque = null;
try{
  await d.chamar('agendar', { p_profissional: prof.id, p_inicio: maisTarde.toISOString(),
    p_servicos:[sv.id], p_nome:'Cliente Tranquila', p_telefone:'+5511977775555' });
}catch(e){ aceitou = false; porque = e.message || String(e); }
verdade('mas aceita normalmente o que está fora dela', aceitou,
  'recusou também o horário distante: ' + porque);

/* ══════════════════════════════════════════════════════════════════════════
   4 — LIXO NO CAMPO NÃO PODE DERRUBAR A AGENDA

   `cfg` é jsonb e guarda o que puserem nele. No Postgres, `'abc'::int`
   LEVANTA — não devolve nulo. Um cast desprotegido aqui não daria o padrão:
   daria erro na agenda da cliente.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Valor inválido no cfg');

await d.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:30, antecedenciaMin:'abacaxi' } });
let quebrou = null, comLixo = null;
try{ comLixo = await primeiroDaqui(); }catch(e){ quebrou = e.message; }
verdade('a agenda continua respondendo', quebrou === null, quebrou);
verdade('e cai no padrão de 30 min — ' + comLixo + ' min',
  comLixo !== null && comLixo >= 30 && comLixo <= 45, 'veio ' + comLixo);

/* Número absurdo passa pela peneira do texto e ainda assim fecharia a agenda
   para sempre. O teto de 7 dias é o que impede o dono de se trancar fora. */
await d.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:30, antecedenciaMin:999999 } });
const r8 = await d.chamar('horarios_livres_periodo', {
  p_profissionais:[prof.id], p_de:hoje(), p_ate:hoje(), p_servicos:[sv.id] });
igual('999999 minutos não oferece nada hoje', (r8 || []).length, 0);
const daqui8 = new Date(Date.now() + 8 * 864e5).toISOString().slice(0, 10);
const r9 = await d.chamar('horarios_livres_periodo', {
  p_profissionais:[prof.id], p_de:daqui8, p_ate:daqui8, p_servicos:[sv.id] });
verdade('mas depois de 8 dias volta a oferecer — o teto de 7 dias segurou',
  (r9 || []).length > 0,
  'nenhum horário daqui a 8 dias: o teto não está sendo aplicado, e o dono '
  + 'consegue se trancar fora da própria agenda');

/* ══════════════════════════════════════════════════════════════════════════
   5 — O PAINEL: A RÉGUA, E O AVISO QUE NÃO PODE SUMIR
   ══════════════════════════════════════════════════════════════════════════ */
secao('A régua no painel');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push(x.message));
await p.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, d.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(3500);
await p.click('a:has-text("Meu salão"), button:has-text("Meu salão")');
await p.waitForTimeout(1200);
await p.click('[data-sub="dados"]');
await p.waitForTimeout(1000);

const regua = await p.evaluate(() =>
  [...document.querySelectorAll('#reguaAntecedencia button')]
    .map(b => b.textContent.trim()));
verdade('a régua existe, com as opções (' + regua.length + ')', regua.length >= 5,
  JSON.stringify(regua));
verdade('e oferece o "Sem limite" — zero é escolha legítima',
  regua.some(r => /sem limite/i.test(r)), JSON.stringify(regua));

/* ⚠ O AVISO SOBRE O ATENDIMENTO DE BALCÃO. É a única coisa na tela que
   explica o que esta régua NÃO faz. Sem ele, o dono escolhe 4 horas achando
   que resolveu o encaixe presencial, leva um choque de agenda, e conclui que
   o ajuste não funciona — quando ele funcionou exatamente como devia. */
const texto = await p.evaluate(() =>
  document.getElementById('tela-salao').innerText);
verdade('a tela avisa que isto não cobre o atendimento combinado no balcão',
  /balcão|balcao/i.test(texto) && /lance o atendimento|sua agenda/i.test(texto),
  'o aviso sumiu — o dono vai achar que a régua resolve o encaixe presencial');

await p.click('#reguaAntecedencia button:has-text("1 hora")');
await p.waitForTimeout(400);
const explica = await p.evaluate(() =>
  (document.getElementById('explicaAntecedencia') || {}).textContent || '');
verdade('clicar numa opção explica o que ela significa — '
  + JSON.stringify(explica.slice(0, 50)), /1 hora/.test(explica), explica);

igual('sem erro de JavaScript no painel',
  erros.length ? erros.slice(0, 3).join(' | ') : 0, 0);

await ctx.close();
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
