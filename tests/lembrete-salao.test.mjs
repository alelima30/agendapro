/* ===========================================================================
   AgendaPro — o lembrete para o salão (21_notificacoes.sql, seção 7c)

     bash tests/bancada/subir.sh
     node tests/lembrete-salao.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Precisamos colocar também para o dono do salão que tem um horário marcado
   pra tal pessoa — lembrete. Que seja configurável."

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. DESLIGADO DE FÁBRICA. Mensagem nova custa e gasta a cota: salão que
        não ligou não recebe nada.
     2. QUEM RECEBE é o que o dono escolheu — quem atende, o dono, os dois —
        e o dono que atende o próprio horário recebe UM, não dois.
     3. O TEMPO é o dele, separado do lembrete da cliente.
     4. ACOMPANHA O HORÁRIO: remarcou, trocou de profissional, cancelou,
        confirmou depois — a fila diz a verdade sobre o que vai sair.
     5. AJUSTE MUDADO DEPOIS vale para o que já estava marcado (a varredura).
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';
import { deslocamento } from './dia.mjs';

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
const TEL_DONA = '11988000001';
const TEL_PROF = '11988001001';

/* O salão: a dona (equipe[0], com vínculo de dono) e uma profissional. */
async function montar(nome){
  const d = novaAba();
  await d.criarConta({ email:`ls-${nome}-${marca}@teste.com`, senha:'minhasenhaboa',
    nome:'Dona ' + nome, telefone: tel() });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
  const salao = cr[0].salao_id;
  await banco.query(
    `update public.assinaturas set plano='salao', status='ativa' where salao_id=$1`, [salao]);
  const equipe = await d.lista('profissionais', { salaoId: salao });
  await banco.query(`update public.profissionais set telefone=$2 where id=$1`,
    [equipe[0].id, TEL_DONA]);
  const p = await d.inserir('profissionais',
    { salaoId: salao, nome:'Bia Rocha', ativo:true, aceitaOnline:true });
  await banco.query(`update public.profissionais set telefone=$2 where id=$1`, [p.id, TEL_PROF]);
  equipe.push(p);
  for(const x of equipe)
    for(let dia = 0; dia <= 6; dia++)
      await d.inserir('jornadas', { profissionalId: x.id, diaSemana: dia,
                                    inicio:'00:00', fim:'23:59' });
  const sv = await d.inserir('servicos', { salaoId: salao, nome:'Corte',
    duracaoMin:60, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });
  const dona = (await banco.query(`select nome from public.profissionais where id=$1`,
    [equipe[0].id])).rows[0].nome;
  return { d, salao, equipe, sv, dona };
}

const cfg = (salao, o) => banco.query(
  `update public.saloes set cfg = coalesce(cfg,'{}'::jsonb) || $2::jsonb where id=$1`,
  [salao, JSON.stringify(o)]);

async function marcar(e, prof, inicio, nomeCliente, status = 'confirmado'){
  const c = await e.d.inserir('clientes', { salaoId: e.salao, nome: nomeCliente,
    telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });
  const a = await e.d.inserir('agendamentos', { salaoId: e.salao, clienteId: c.id,
    profissionalId: prof.id, inicio: inicio.toISOString(),
    fim: new Date(inicio.getTime() + 36e5).toISOString(),
    status, origem:'recepcao', valorPrevisto: 80 });
  await e.d.inserir('agendamento_servicos',
    { agendamentoId: a.id, servicoId: e.sv.id, preco: 80, duracaoMin: 60 });
  return a;
}

// Os lembretes do salão de UM agendamento.
const doAg = async (ag, so = null) => (await banco.query(
  `select status, destino, quando, corpo, motivo, modelo, variaveis, profissional_id
     from public.notificacoes
    where agendamento_id=$1 and tipo='lembrete_equipe' ${so ? `and status='${so}'` : ''}
    order by criado_em`, [ag.id])).rows;
const minutosAntes = (inicio, quando) =>
  Math.round((inicio.getTime() - new Date(quando).getTime()) / 6e4);
/* A varredura pelo MESMO caminho do agendador: o worker chama o
   `gerar_resumos()` de minuto em minuto, e é ele que puxa a do lembrete.
   Chamar a função de dentro direto deixaria passar o dia em que alguém a
   tirasse do agendador. */
const varrer = () => banco.query(`select public.gerar_resumos()`);

/* ⚠ OS HORÁRIOS VÊM DE UMA ÂNCORA, EM HORA SEGURA DE SÃO PAULO.

   "Daqui a 5 horas" rodando às 20h cai em 01h, e um atendimento de uma hora
   às 23h termina depois do fim da jornada (23:59) — o banco recusa com "Fora
   da jornada", e a suíte quebrava conforme o relógio. A âncora é a primeira
   hora cheia, a pelo menos 4h daqui (o teste do lembrete de 3h precisa de
   folga), entre 01h e 15h em São Paulo; os horários do teste ficam de
   âncora+0 a âncora+5, sempre dentro do dia e a menos de 25h — a janela que
   a varredura olha. */
const horaSP = t => Number(new Intl.DateTimeFormat('en-GB', { hour:'numeric',
  hourCycle:'h23', timeZone:'America/Sao_Paulo' }).format(t));
const ANCORA = (() => {
  const t = new Date(Date.now() + 5 * 36e5);
  t.setUTCMinutes(0, 0, 0);
  while(!(horaSP(t) >= 1 && horaSP(t) <= 15)) t.setTime(t.getTime() + 36e5);
  return t;
})();
const daqui = h => new Date(ANCORA.getTime() + h * 36e5);

const L = await montar('Lemb');
const DESL = await montar('Desl');

/* ══════════════════════════════════════════════════════════════════════════
   1 — DESLIGADO DE FÁBRICA
   ══════════════════════════════════════════════════════════════════════════ */
secao('Desligado de fábrica');

const a0 = await marcar(DESL, DESL.equipe[1], daqui(0), 'Ana Lima');
igual('salão que não ligou não ganha lembrete para o salão', (await doAg(a0)).length, 0);
verdade('mas o lembrete da CLIENTE continua nascendo, como sempre',
  (await banco.query(`select 1 from public.notificacoes where agendamento_id=$1 and tipo='lembrete'`,
    [a0.id])).rows.length === 1);
await varrer();
igual('e a varredura também não inventa', (await doAg(a0)).length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   2 — QUEM VAI ATENDER
   ══════════════════════════════════════════════════════════════════════════ */
secao('Ligado, para quem vai atender');

await cfg(L.salao, { notifLembreteEquipe: true, notifLembreteEquipeMin: 60,
                     notifLembreteEquipePara: 'atende',
                     notifLembrete: true, notifLembreteMin: 120 });
const ini1 = daqui(0);
const a1 = await marcar(L, L.equipe[1], ini1, 'Carla Dias');
let r = await doAg(a1);
igual('um lembrete', r.length, 1);
igual('para a Bia, que vai atender', r[0] && r[0].destino, TEL_PROF);
igual('1 hora antes — o tempo DELE, e não as 2h da cliente',
  r[0] && minutosAntes(ini1, r[0].quando), 60);
igual('pelo modelo de utilidade do lembrete do salão', r[0] && r[0].modelo,
  'agendapro_lembrete_equipe');
const v1 = (r[0] && r[0].variaveis) || [];
igual('com sete variáveis', v1.length, 7);
igual('a 1ª é o primeiro nome de quem RECEBE', v1[0], 'Bia');
igual('a 2ª é a cliente, nome inteiro', v1[1], 'Carla Dias');
igual('a 4ª é quem atende', v1[3], 'Bia Rocha');
igual('a 7ª é o salão', v1[6], 'Salão Lemb ' + marca);
verdade('o serviço já entra certo (e não "atendimento")', v1[2] === 'Corte', JSON.stringify(v1));
verdade('e o histórico diz o mesmo',
  /Lembrete de um horário agendado/.test(r[0].corpo) && /Cliente: Carla Dias/.test(r[0].corpo)
    && /Profissional: Bia Rocha/.test(r[0].corpo), r[0] && r[0].corpo);
const lembCli = (await banco.query(
  `select quando from public.notificacoes where agendamento_id=$1 and tipo='lembrete'`,
  [a1.id])).rows[0];
igual('o da cliente segue nas 2 horas dela', lembCli && minutosAntes(ini1, lembCli.quando), 120);

await varrer();
igual('varrer de novo não duplica', (await doAg(a1)).length, 1);

/* ══════════════════════════════════════════════════════════════════════════
   3 — O TEMPO É CONFIGURÁVEL
   ══════════════════════════════════════════════════════════════════════════ */
secao('O tempo, mudado depois');

await cfg(L.salao, { notifLembreteEquipeMin: 180 });
await varrer();
r = await doAg(a1);
igual('o pendente de 1h vira cancelado', r.filter(x => x.status === 'cancelado').length, 1);
const vivo = r.filter(x => x.status === 'pendente');
igual('e nasce um de 3 horas antes',
  vivo.length === 1 ? minutosAntes(ini1, vivo[0].quando) : vivo, 180);
await cfg(L.salao, { notifLembreteEquipeMin: 60 });
await varrer();

/* ══════════════════════════════════════════════════════════════════════════
   4 — QUEM RECEBE É CONFIGURÁVEL
   ══════════════════════════════════════════════════════════════════════════ */
secao('Quem recebe: o dono, e os dois');

await cfg(L.salao, { notifLembreteEquipePara: 'dono' });
await varrer();
r = await doAg(a1, 'pendente');
igual('"o dono": vai só para a dona', r.map(x => x.destino), [TEL_DONA]);
igual('chamada pelo nome dela', r[0] && r[0].variaveis[0], L.dona.split(' ')[0]);
igual('e lendo quem atende: a Bia', r[0] && r[0].variaveis[3], 'Bia Rocha');

await cfg(L.salao, { notifLembreteEquipePara: 'ambos' });
await varrer();
r = await doAg(a1, 'pendente');
igual('"os dois": a Bia e a dona', r.map(x => x.destino).sort(), [TEL_DONA, TEL_PROF].sort());

const iniD = daqui(1);
const aD = await marcar(L, L.equipe[0], iniD, 'Duda Reis');
igual('a dona que atende o próprio horário recebe UM, não dois',
  (await doAg(aD, 'pendente')).map(x => x.destino), [TEL_DONA]);

/* ══════════════════════════════════════════════════════════════════════════
   5 — ACOMPANHA O HORÁRIO
   ══════════════════════════════════════════════════════════════════════════ */
secao('Remarcou, trocou de profissional, cancelou');

await cfg(L.salao, { notifLembreteEquipePara: 'atende' });
await varrer();
const ini1b = daqui(2);
await banco.query(`update public.agendamentos set inicio=$2, fim=$3 where id=$1`,
  [a1.id, ini1b.toISOString(), new Date(ini1b.getTime() + 36e5).toISOString()]);
r = await doAg(a1, 'pendente');
igual('remarcou: um só pendente, 1h antes da hora NOVA',
  r.length === 1 && minutosAntes(ini1b, r[0].quando), 60);
const horaNova = new Intl.DateTimeFormat('pt-BR', { hour:'2-digit', minute:'2-digit',
  timeZone:'America/Sao_Paulo' }).format(ini1b);
igual('e com a hora nova escrita dentro', r[0] && r[0].variaveis[5], horaNova);

await banco.query(`update public.agendamentos set profissional_id=$2 where id=$1`,
  [a1.id, L.equipe[0].id]);
r = await doAg(a1, 'pendente');
igual('trocou de profissional: o lembrete vai para a nova (a dona)', r.map(x => x.destino), [TEL_DONA]);
igual('e a Bia não é mais avisada de um horário que não é dela',
  (await doAg(a1)).filter(x => x.destino === TEL_PROF && x.status === 'pendente').length, 0);

await banco.query(`update public.agendamentos set status='cancelado' where id=$1`, [a1.id]);
igual('cancelou: nada pendente', (await doAg(a1, 'pendente')).length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   6 — AS BORDAS
   ══════════════════════════════════════════════════════════════════════════ */
secao('Pendente, em cima da hora, e quem desligou o seu');

const aP = await marcar(L, L.equipe[1], daqui(3), 'Eva Prado', 'pendente');
igual('horário ainda pendente não ganha lembrete', (await doAg(aP)).length, 0);
await banco.query(`update public.agendamentos set status='confirmado' where id=$1`, [aP.id]);
igual('o dono confirmou: aí sim', (await doAg(aP, 'pendente')).length, 1);

/* "Em cima da hora" sem depender do relógio: lembrete de 24h para um
   horário de daqui a poucas horas — a hora do lembrete já passou. */
await cfg(L.salao, { notifLembreteEquipeMin: 1440 });
const aPerto = await marcar(L, L.equipe[1], daqui(5), 'Fê Lopes');
igual('lembrete de 24h para um horário de daqui a poucas horas: a hora já passou',
  (await doAg(aPerto)).length, 0);
await cfg(L.salao, { notifLembreteEquipeMin: 60 });

await banco.query(`update public.profissionais set notif_lembrete=false where id=$1`, [L.equipe[1].id]);
const aOpt = await marcar(L, L.equipe[1], daqui(4), 'Gi Melo');
igual('quem desligou o seu em Equipe não recebe', (await doAg(aOpt)).length, 0);
await banco.query(`update public.profissionais set notif_lembrete=true where id=$1`, [L.equipe[1].id]);

/* ══════════════════════════════════════════════════════════════════════════
   7 — LIGOU DEPOIS, DESLIGOU DEPOIS
   ══════════════════════════════════════════════════════════════════════════ */
secao('O ajuste mudado vale para o que já estava marcado');

await cfg(DESL.salao, { notifLembreteEquipe: true });
await varrer();
r = await doAg(a0, 'pendente');
igual('ligou hoje: o horário marcado antes ganha lembrete (padrão: quem atende, 1h)',
  r.length === 1 && r[0].destino === TEL_PROF ? minutosAntes(new Date(a0.inicio), r[0].quando) : r, 60);

await cfg(DESL.salao, { notifLembreteEquipe: false });
await varrer();
igual('desligou: o que estava na fila sai dela', (await doAg(a0, 'pendente')).length, 0);
verdade('dizendo por quê', (await doAg(a0)).every(x => x.status !== 'pendente'
  && /mudou/.test(x.motivo || '')), JSON.stringify((await doAg(a0)).map(x => x.motivo)));

/* ══════════════════════════════════════════════════════════════════════════
   8 — NINGUÉM DE FORA CHAMA ISTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('As funções são internas');
for(const f of ['public.refazer_lembrete_equipe(uuid)', 'public.gerar_lembretes_equipe()',
                'public.variaveis_lembrete_equipe(uuid,uuid)', 'public.texto_lembrete_equipe(uuid,uuid)']){
  const x = (await banco.query(
    `select has_function_privilege('anon', $1, 'execute') as a,
            has_function_privilege('authenticated', $1, 'execute') as b`, [f])).rows[0];
  igual(`nem anon nem logado executam ${f.split('(')[0]}`, [x.a, x.b], [false, false]);
}

await banco.query(`delete from public.agendamentos where salao_id = any($1)`, [[L.salao, DESL.salao]]);
await banco.query(`delete from public.saloes where id = any($1)`, [[L.salao, DESL.salao]]);
await banco.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações do lembrete para o salão.`);
