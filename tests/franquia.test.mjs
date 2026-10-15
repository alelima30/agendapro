/* ===========================================================================
   AgendaPro — a franquia de mensagens e a reserva da cliente (22_cotas.sql)

     bash tests/bancada/subir.sh
     node tests/franquia.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   A franquia de cada plano cobre o que a cliente gasta (confirmação e
   lembrete), o teste grátis tem um teto pequeno, e quando a franquia está no
   fim as mensagens do salão param antes e as da cliente seguem.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. OS NÚMEROS de cada plano — e o teste grátis com 100, separado do
        Essencial (eram a mesma linha).
     2. A RESERVA: a 90% da franquia, aviso, lembrete para o salão e resumo
        param; confirmação e lembrete da cliente seguem até o teto. No teto,
        para tudo.
     3. O PRAZO: mensagem de um horário que já começou não sai, nem que a
        franquia volte. O resumo, que não é de um horário, não cai nisso.
     4. A TELA lê o mesmo número do servidor (`uso_do_plano().tetoSalao`).
     5. As funções novas são só do worker.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

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

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const tel = () => '+5511' + (100000000 + Math.floor(Math.random()*89999999));
const um = async (sql, args = []) => (await banco.query(sql, args)).rows[0];

async function montar(nome, plano){
  const d = novaAba();
  await d.criarConta({ email:`fr-${nome}-${marca}@teste.com`, senha:'minhasenhaboa',
    nome:'Dona ' + nome, telefone: tel() });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
  const salao = cr[0].salao_id;
  if(plano) await banco.query(
    `update public.assinaturas set plano=$2, status='ativa' where salao_id=$1`, [salao, plano]);
  return { d, salao };
}

/* Gasta a franquia escrevendo envios do mês, como se tivessem saído. */
const gastar = (salao, n, de = 0) => banco.query(
  `insert into public.notificacoes
     (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
   select $1, 'lembrete', '11999', now(), 'x', 'gasto:' || g, 'enviado', now()
     from generate_series($2::int + 1, $2::int + $3::int) g`, [salao, de, n]);

/* Uma de cada tipo na fila, pronta para sair. Sem agendamento: aqui a regra
   em jogo é a da franquia, não a do prazo. `quando` quase seis horas atrás
   põe as daqui na frente da fila da bancada inteira. */
const TIPOS = ['confirmacao', 'lembrete', 'novo', 'lembrete_equipe', 'resumo'];
async function enfileirar(salao, rodada){
  for(const t of TIPOS) await banco.query(
    `insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status)
     values ($1, $2, '11988', now() - interval '5 hours 50 minutes', 'x', $3, 'pendente')`,
    [salao, t, `fila:${rodada}:${t}`]);
}
async function servidos(salao, rodada){
  const r = await banco.query(`select * from public.notificacao_proxima(500)`);
  const meus = r.rows.filter(x => x.salao_id === salao).map(x => x.tipo).sort();
  // O que ficou na fila desta rodada volta a não incomodar as outras.
  await banco.query(
    `update public.notificacoes set status='cancelado', motivo='fim do teste'
      where salao_id=$1 and chave like $2 and status in ('pendente','enviando')`,
    [salao, `fila:${rodada}:%`]);
  return meus;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — OS NÚMEROS
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) A franquia de cada plano');

const franquias = Object.fromEntries((await banco.query(
  `select codigo, (recursos->>'mensagens_mes')::int as m from public.planos`)).rows
  .map(r => [r.codigo, r.m]));
igual('Grátis não tem mensagem automática', franquias.gratuito, 0);
igual('o teste grátis tem 100', franquias.trial, 100);
igual('o Essencial tem 500', franquias.individual, 500);
igual('a Dupla tem 800', franquias.duo, 800);
igual('o Time tem 1.100', franquias.time, 1100);
igual('o Equipe tem 2.000', franquias.equipe, 2000);
igual('o Salão tem 3.600', franquias.salao, 3600);

const TESTE = await montar('Teste', null);
igual('um salão novo, em teste, tem 100 no mês',
  Number((await um(`select public.teto_mensagens($1) as t`, [TESTE.salao])).t), 100);
igual('e as do salão vão até 90',
  Number((await um(`select public.teto_mensagens_salao($1) as t`, [TESTE.salao])).t), 90);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A RESERVA DA CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) Perto do fim, as do salão param antes');

const E = await montar('Ess', 'individual');
igual('Essencial: as do salão vão até 450 de 500',
  Number((await um(`select public.teto_mensagens_salao($1) as t`, [E.salao])).t), 450);

await enfileirar(E.salao, 'livre');
igual('com a franquia folgada, sai de tudo',
  await servidos(E.salao, 'livre'), [...TIPOS].sort());

await gastar(E.salao, 449);
await enfileirar(E.salao, 'q449');
igual('com 449 gastas, ainda sai de tudo (o corte é em 450)',
  await servidos(E.salao, 'q449'), [...TIPOS].sort());

await gastar(E.salao, 1, 449);
await enfileirar(E.salao, 'q450');
igual('com 450, só confirmação e lembrete da cliente saem',
  await servidos(E.salao, 'q450'), ['confirmacao', 'lembrete']);

const pode = async (t) => (await um(
  `select public.pode_enviar_tipo($1, $2) as p`, [E.salao, t])).p;
verdade('aviso de horário novo espera', (await pode('novo')) === false);
verdade('lembrete para o salão espera', (await pode('lembrete_equipe')) === false);
verdade('resumo do dia espera', (await pode('resumo')) === false);
verdade('confirmação segue', (await pode('confirmacao')) === true);
verdade('lembrete da cliente segue', (await pode('lembrete')) === true);

await gastar(E.salao, 49, 450);
await enfileirar(E.salao, 'q499');
igual('com 499, as da cliente ainda saem',
  await servidos(E.salao, 'q499'), ['confirmacao', 'lembrete']);

await gastar(E.salao, 1, 499);
await enfileirar(E.salao, 'q500');
igual('no teto, não sai nada — nem da cliente',
  await servidos(E.salao, 'q500'), []);

/* Quem já usava `pode_enviar()` continua com a resposta de antes. */
verdade('pode_enviar() segue dizendo "não" no teto',
  (await um(`select public.pode_enviar($1) as p`, [E.salao])).p === false);

const G = await montar('Gratis', 'gratuito');
await enfileirar(G.salao, 'g');
igual('no Grátis não sai nada, de tipo nenhum', await servidos(G.salao, 'g'), []);

/* ══════════════════════════════════════════════════════════════════════════
   3 — O PRAZO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) Mensagem de horário que já começou não sai');

const P = await montar('Prazo', 'salao');
const prof = (await banco.query(
  `select id from public.profissionais where salao_id=$1 limit 1`, [P.salao])).rows[0].id;
const cli = (await um(
  `insert into public.clientes (salao_id, nome, telefone) values ($1, 'Lia Prazo', '11977776666')
   returning id`, [P.salao])).id;

/* O agendamento entra direto, sem os gatilhos: o que está em teste é a
   fila, e não a agenda — que recusaria um horário no passado. */
async function agendamento(inicio){
  await banco.query(`set session_replication_role = replica`);
  try{
    return (await um(
      `insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem)
       values ($1, $2, $3, $4::timestamptz, $4::timestamptz + interval '1 hour', 'confirmado', 'recepcao')
       returning id`, [P.salao, cli, prof, inicio])).id;
  } finally {
    await banco.query(`set session_replication_role = origin`);
  }
}
const passou1h = await agendamento(new Date(Date.now() - 36e5).toISOString());
const daqui3h  = await agendamento(new Date(Date.now() + 3 * 36e5).toISOString());

for(const [ag, t] of [[passou1h, 'lembrete'], [passou1h, 'confirmacao'], [passou1h, 'novo'],
                      [passou1h, 'lembrete_equipe'], [daqui3h, 'lembrete']])
  await banco.query(
    `insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, agendamento_id)
     values ($1, $2, '11977776666', now() + interval '1 day', 'x', $3, 'pendente', $4)`,
    [P.salao, t, `prazo:${ag}:${t}`, ag]);
// O resumo fala do dia, não de um horário — e por isso não tem agendamento.
await banco.query(
  `insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status)
   values ($1, 'resumo', '11977776666', now() + interval '1 day', 'x', $2, 'pendente')`,
  [P.salao, `prazo:resumo:${marca}`]);

await banco.query(`select * from public.notificacao_proxima(1)`);

const estado = async (filtro, args) => (await banco.query(
  `select tipo, status, motivo from public.notificacoes where salao_id=$1 and ${filtro}
    order by tipo`, [P.salao, ...args])).rows;
const doPassado = await estado(`agendamento_id=$2`, [passou1h]);
igual('as quatro de um horário que já começou saíram da fila',
  doPassado.map(r => r.status), ['cancelado', 'cancelado', 'cancelado', 'cancelado']);
verdade('com o motivo dito',
  doPassado.every(r => r.motivo === 'o horário já passou'),
  JSON.stringify(doPassado.map(r => r.motivo)));
igual('a de um horário que ainda vem continua esperando',
  (await estado(`agendamento_id=$2`, [daqui3h])).map(r => r.status), ['pendente']);
igual('e o resumo do dia, que não é de um horário, também',
  (await estado(`tipo='resumo'`, [])).map(r => r.status), ['pendente']);

/* ══════════════════════════════════════════════════════════════════════════
   4 — A TELA LÊ O MESMO NÚMERO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) O uso do plano traz até onde vão as do salão');

const u = await E.d.chamar('uso_do_plano', { p_salao: E.salao });
igual('500 usadas de 500, e as do salão até 450',
  [u.mensagens.usado, u.mensagens.teto, u.mensagens.tetoSalao], [500, 500, 450]);
const ug = await G.d.chamar('uso_do_plano', { p_salao: G.salao });
igual('no Grátis, zero e zero', [ug.mensagens.teto, ug.mensagens.tetoSalao], [0, 0]);

/* ══════════════════════════════════════════════════════════════════════════
   5 — SÓ DO WORKER
   ══════════════════════════════════════════════════════════════════════════ */
secao('5) As funções novas são só do worker');

for(const papel of ['anon', 'authenticated'])
  for(const f of ['public.pode_enviar_tipo(uuid, text)', 'public.teto_mensagens_salao(uuid)'])
    verdade(`${papel} não executa ${f.replace('public.', '')}`,
      (await um(`select has_function_privilege($1, $2, 'execute') as p`, [papel, f])).p === false);

await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} verificações da franquia${
  falhou ? `, ${falhou} falharam` : ''}.`);
process.exit(falhou ? 1 : 0);
