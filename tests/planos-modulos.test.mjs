/* ===========================================================================
   AgendaPro — Grátis bem limitado, Básico sem mensagens (22_cotas, 01)

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/planos-modulos.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "O plano grátis tem que ser bem limitado, mas bem limitado mesmo" — e um
   plano de R$ 49,90 com o sistema inteiro, sem as mensagens.

     Grátis     agenda, clientes e o link simples (com selo); 20 horários,
                30 clientes, 5 serviços, sem produtos; sem caixa/comanda,
                relatórios, pacotes, cupons, aparência e mensagens
     Básico     o sistema inteiro, sem mensagens automáticas
     Essencial  o Básico + 500 mensagens

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. O BANCO recusa cada módulo no Grátis — pelo caminho que o console
        usaria, não pelo botão.
     2. O Básico usa todos, e não manda mensagem automática.
     3. O link do Grátis sai simples (sem a aparência guardada) e com o selo,
        e sem loja; a personalização continua guardada para quando assinar.
     4. A tela: cadeado nas abas, aviso no lugar do módulo, Básico ao lado do
        Essencial na tela do Plano.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
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
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
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

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const um = async (sql, args = []) => (await banco.query(sql, args)).rows[0];
const recusa = async (sql, args = []) => {
  try{ await banco.query(sql, args); return null; }
  catch(e){ return e.message; }
};

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const tel = () => '+5511' + (100000000 + Math.floor(Math.random()*89999999));

async function montar(nome, plano){
  const d = novaAba();
  await d.criarConta({ email:`pm-${nome}-${marca}@teste.com`, senha:'minhasenhaboa',
    nome:'Dona ' + nome, telefone: tel() });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
  const salao = cr[0].salao_id;
  const slug = (await um(`select slug from public.saloes where id=$1`, [salao])).slug;
  const cli = (await um(`insert into public.clientes (salao_id, nome, telefone)
                          values ($1, 'Cliente ' || $2, '1197777' || lpad((random()*9999)::int::text, 4, '0'))
                          returning id`, [salao, nome])).id;
  return { d, salao, slug, cli, plano: async (p) => banco.query(
    `update public.assinaturas set plano=$2, status='ativa', vence_em = current_date + 30
      where salao_id=$1`, [salao, p]) };
}

/* ══════════════════════════════════════════════════════════════════════════
   0 — OS NÚMEROS
   ══════════════════════════════════════════════════════════════════════════ */
secao('0) Os planos');
const pl = Object.fromEntries((await banco.query(
  `select codigo, preco_mes, recursos from public.planos`)).rows.map(r => [r.codigo, r]));
igual('o Básico existe, a R$ 49,90', Number(pl.basico?.preco_mes), 49.9);
igual('o Básico não tem mensagem automática', Number(pl.basico?.recursos?.mensagens_mes), 0);
const g = pl.gratuito.recursos;
igual('Grátis: 20 horários, 30 clientes, 5 serviços, 0 produto, 0 mensagem',
  [g.agendamentos_mes, g.max_clientes, g.max_servicos, g.max_produtos, g.mensagens_mes], [20, 30, 5, 0, 0]);
igual('Grátis: sem caixa, relatórios, loja, pacotes, cupons, aparência',
  ['caixa','relatorios','loja','pacotes','cupons','aparencia'].map(k => g[k]), [false,false,false,false,false,false]);
igual('Básico: com todos os módulos',
  ['caixa','relatorios','loja','pacotes','cupons','aparencia'].map(k => pl.basico.recursos[k]), [true,true,true,true,true,true]);

/* ══════════════════════════════════════════════════════════════════════════
   1 — O GRÁTIS, RECUSADO PELO BANCO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) No Grátis, o banco recusa cada módulo');
const G = await montar('Gratis');
// Enquanto ainda está no teste (tudo liberado), monta o que vai ficar guardado.
await banco.query(`update public.saloes set cfg = coalesce(cfg,'{}'::jsonb)
  || '{"cor":"#123456","tema":"escuro","fundo":"x","loja":"true"}'::jsonb where id=$1`, [G.salao]);
const pacoteG = (await um(`insert into public.pacotes (salao_id, nome, preco, sessoes)
                            values ($1, 'Pacote antigo', 100, 4) returning id`, [G.salao])).id;
await banco.query(`insert into public.cupons (salao_id, codigo, valor) values ($1, 'ANTIGO10', 10)`, [G.salao]);
await banco.query(`insert into public.produtos (salao_id, nome, preco, ativo) values ($1, 'Shampoo antigo', 30, true)`, [G.salao]);
await G.plano('gratuito');

const BASICO = /a partir do plano Básico/;
let r;
r = await recusa(`insert into public.caixas (salao_id) values ($1)`, [G.salao]);
verdade('abrir caixa: recusado', r && BASICO.test(r), String(r));
r = await G.d.chamar('relatorio', { p_salao: G.salao, p_de: '2026-01-01', p_ate: '2026-12-31' })
  .then(() => null).catch(e => e.message);
verdade('relatório, pela sessão do dono: recusado', r && BASICO.test(r), String(r));
r = await recusa(`insert into public.pacotes (salao_id, nome, preco, sessoes) values ($1, 'Novo', 100, 4)`, [G.salao]);
verdade('criar pacote: recusado', r && BASICO.test(r), String(r));
r = await G.d.chamar('vender_pacote', { p_pacote: pacoteG, p_cliente: G.cli })
  .then(() => null).catch(e => e.message);
verdade('vender o pacote que já existia: recusado', r && BASICO.test(r), String(r));
r = await recusa(`insert into public.cupons (salao_id, codigo, valor) values ($1, 'NOVO10', 10)`, [G.salao]);
verdade('criar cupom: recusado', r && BASICO.test(r), String(r));
// Todos os argumentos: uma chamada que errasse por assinatura passaria
// "recusada" pelo motivo errado (foi o que a mutação 6 pegou).
const calcular = async (salao) => (await um(
  `select public.cupom_calcular($1, 'ANTIGO10', 'agendamento', null, null,
     now() + interval '2 days', null, null, null) as c`, [salao])).c;
const calc = await calcular(G.salao);
verdade('usar o cupom que já existia: não vale, e diz por quê',
  calc && /não está aceitando cupons/.test(calc.motivo || ''), JSON.stringify(calc));
const temCupom = (await um(`select public.salao_tem_cupom($1) as t`, [G.salao])).t;
igual('o link nem mostra campo de cupom', [temCupom.agendamento, temCupom.produtos], [false, false]);
r = await recusa(`insert into public.produtos (salao_id, nome, preco, ativo) values ($1, 'Novo produto', 30, true)`, [G.salao]);
verdade('cadastrar produto: recusado (o Grátis não tem produto)', !!r, String(r));
verdade('comanda e caixa desligados, mesmo com o interruptor ligado',
  (await um(`select public.usa_comanda($1) as u`, [G.salao])).u === false);

for(let i = 0; i < 29; i++)
  await banco.query(`insert into public.clientes (salao_id, nome) values ($1, 'Extra ' || $2)`, [G.salao, i]);
r = await recusa(`insert into public.clientes (salao_id, nome) values ($1, 'A trigésima primeira')`, [G.salao]);
verdade('a 31ª cliente: recusada', !!r, String(r));
const servicosJa = Number((await um(`select count(*) as n from public.servicos where salao_id=$1`, [G.salao])).n);
for(let i = servicosJa; i < 5; i++)
  await banco.query(`insert into public.servicos (salao_id, nome, duracao_min, preco) values ($1, 'Serviço ' || $2, 30, 50)`, [G.salao, i]);
r = await recusa(`insert into public.servicos (salao_id, nome, duracao_min, preco) values ($1, 'O sexto', 30, 50)`, [G.salao]);
verdade('o 6º serviço: recusado', !!r, String(r));
igual('e nenhuma mensagem automática', (await um(`select public.pode_enviar($1) as p`, [G.salao])).p, false);

secao('2) O link do Grátis é o simples');
const vg = (await um(`select public.vitrine($1) as v`, [G.slug])).v;
igual('sem a cor e o tema guardados', [vg.salao.cor, vg.salao.tema], [null, null]);
igual('com o selo "Feito com AgendaPro"', vg.salao.selo, true);
igual('sem loja, e sem os produtos', [vg.salao.loja, (vg.produtos || []).length], [false, 0]);
const cfgG = (await um(`select cfg from public.saloes where id=$1`, [G.salao])).cfg;
igual('mas a aparência continua guardada no salão', [cfgG.cor, cfgG.tema], ['#123456', 'escuro']);

/* ══════════════════════════════════════════════════════════════════════════
   3 — O BÁSICO USA TUDO, MENOS MENSAGEM
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) O Básico usa todos os módulos, sem mensagem automática');
await G.plano('basico');
r = await recusa(`insert into public.caixas (salao_id) values ($1)`, [G.salao]);
igual('abrir caixa: aceito', r, null);
r = await G.d.chamar('relatorio', { p_salao: G.salao, p_de: '2026-01-01', p_ate: '2026-12-31' })
  .then(() => null).catch(e => e.message);
igual('relatório: aceito', r, null);
igual('criar pacote: aceito',
  await recusa(`insert into public.pacotes (salao_id, nome, preco, sessoes) values ($1, 'Novo B', 100, 4)`, [G.salao]), null);
igual('criar cupom: aceito',
  await recusa(`insert into public.cupons (salao_id, codigo, valor) values ($1, 'BASICO10', 10)`, [G.salao]), null);
const calcB = await calcular(G.salao);
verdade('e o cupom antigo volta a ser conferido (sem a recusa do plano)',
  calcB && !/não está aceitando cupons/.test(calcB.motivo || ''), JSON.stringify(calcB));
verdade('comanda e caixa ligados', (await um(`select public.usa_comanda($1) as u`, [G.salao])).u === true);
const vb = (await um(`select public.vitrine($1) as v`, [G.slug])).v;
igual('o link volta com a aparência guardada, sem selo', [vb.salao.cor, vb.salao.selo], ['#123456', false]);
igual('a loja volta', vb.salao.loja, true);
igual('mensagem automática: nenhuma (franquia 0)',
  [Number((await um(`select public.teto_mensagens($1) as t`, [G.salao])).t),
   (await um(`select public.pode_enviar($1) as p`, [G.salao])).p], [0, false]);

/* A assinatura só o gestor lê; a recepção e a profissional perguntam o plano
   por `plano_do_salao` — só o código, e só do salão onde trabalham. Sem isto
   a tela delas achava que era o Grátis e trancava o caixa de quem paga. */
secao('3b) A equipe sabe o plano, e só o do próprio salão');
igual('quem é do salão: recebe o código do plano',
  await G.d.chamar('plano_do_salao', { p_salao: G.salao }), 'basico');
const F = await montar('Fora');
igual('quem é de outro salão: não recebe nada',
  await F.d.chamar('plano_do_salao', { p_salao: G.salao }), null);
r = await novaAba().chamar('plano_do_salao', { p_salao: G.salao })
  .then(v => 'respondeu ' + JSON.stringify(v)).catch(() => null);
igual('sem login: nem chega a perguntar', r, null);

/* ══════════════════════════════════════════════════════════════════════════
   4 — A TELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) A tela: cadeado, aviso, e o Básico ao lado do Essencial');
const T = await montar('Tela');
await T.plano('gratuito');
const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const abrir = async (sessao, sufixo = '') => {
  const p = await (await nav.newContext({ viewport:{ width:1360, height:900 } })).newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.accept());
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, sessao]);
  await p.goto(BASE + '/app.html' + sufixo);
  await p.waitForTimeout(3500);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  await p.waitForTimeout(600);
  return p;
};
const pg1 = await abrir(T.d.sessao(), '?oferta=1');
const cadeados = await pg1.evaluate(() =>
  [...document.querySelectorAll('#abas .aba.aba-travada')].map(b => b.dataset.chave).sort());
igual('Grátis: cadeado em Cupons, Pacotes, Produtos e Relatórios', cadeados,
  ['cupons', 'pacotes', 'produtos', 'relatorios']);
const telaTravada = async (p, k) => {
  await p.evaluate(k => irPara(k), k);
  await p.waitForTimeout(700);
  return p.evaluate(k => {
    const t = document.getElementById('tela-' + k);
    const av = t.querySelector(':scope > .trava-plano');
    return { travada: t.classList.contains('travada'), texto: av ? av.innerText : '' };
  }, k);
};
for(const k of ['relatorios', 'produtos', 'pacotes', 'cupons']){
  const t = await telaTravada(pg1, k);
  verdade(`${k}: abre no aviso "a partir do plano Básico"`, t.travada && /plano Básico/.test(t.texto), JSON.stringify(t));
}
await pg1.evaluate(() => { irPara('salao'); });
await pg1.waitForTimeout(800);
await pg1.evaluate(() => trocarAbaSalao('aparencia'));
await pg1.waitForTimeout(500);
const apar = await pg1.evaluate(() => {
  const t = document.querySelector('#painelSalao .sub-tela[data-sub="aparencia"]');
  return { travada: t && t.classList.contains('travada'),
           texto: (t && t.querySelector('.trava-plano') || {}).innerText || '' };
});
verdade('Aparência do link: travada, com o aviso', apar.travada && /Aparência do link/.test(apar.texto), JSON.stringify(apar));
verdade('a aba Caixa não aparece (sem comanda no Grátis)',
  !(await pg1.evaluate(() => !!document.querySelector('#abas .aba[data-chave="caixa"]'))));

await pg1.evaluate(() => irPara('plano'));
await pg1.waitForTimeout(1500);
const planoTxt = await pg1.evaluate(() => (document.getElementById('cartaoPlano') || {}).innerText || '');
verdade('tela do Plano, 1 profissional: Essencial recomendado', /PLANO RECOMENDADO[\s\S]*Essencial/.test(planoTxt), planoTxt.slice(0, 300));
verdade('e o Básico a R$ 49,90, sem mensagens', /Básico/.test(planoTxt) && /49,90/.test(planoTxt)
  && /SEM MENSAGENS/i.test(planoTxt), planoTxt.slice(0, 500));

await T.plano('basico');
const pg2 = await abrir(T.d.sessao());
igual('Básico: nenhum cadeado', await pg2.evaluate(() =>
  document.querySelectorAll('#abas .aba.aba-travada').length), 0);
const tb = await telaTravada(pg2, 'relatorios');
verdade('Básico: Relatórios abre normal', !tb.travada, JSON.stringify(tb));

igual('nenhum erro de JavaScript', erros, []);
await nav.close();

await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} verificações dos planos${
  falhou ? `, ${falhou} falharam` : ''}.`);
process.exit(falhou ? 1 : 0);
