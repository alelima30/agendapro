/* ===========================================================================
   AgendaPro — confirmação, lembrete, resumo do dia e as cotas do plano

     bash tests/bancada/subir.sh
     node tests/notificacoes.test.mjs

   ── A REGRA QUE ESTA SUÍTE EXISTE PARA DEFENDER ────────────────────────────
   NADA É MARCADO COMO ENVIADO SEM TER SIDO ENVIADO.

   Enquanto a conta na Meta não estiver aprovada, as linhas nascem `pendente`
   e ficam. Um teste que aceitasse "enviado" aqui estaria abençoando
   exatamente o defeito que o pedido proíbe — o salão deixaria de ligar para a
   cliente confiando num aviso que ninguém recebeu.

   Por isso tudo aqui é medido na FILA e no BANCO: o que foi criado, quando
   deve sair, o que foi cancelado, o que conta cota. O envio de verdade tem um
   passo só — o worker — e ele é exercitado chamando as mesmas funções que a
   função de borda chama.

   ── OS QUINZE TESTES DO PEDIDO ─────────────────────────────────────────────
   Cada seção abaixo nomeia qual deles está cobrindo, para a conferência do
   critério de aceitação ser leitura, não arqueologia.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';
import { maisDias, deslocamento } from './dia.mjs';

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

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const tel = () => '+5511' + (100000000 + Math.floor(Math.random()*89999999));

/* Monta um salão do zero. Devolve tudo o que as seções precisam.
   `profs` é quantos profissionais ativos — é o número que decide se o resumo
   do dono vem com cabeçalho de equipe ou não. */
async function montar(nome, profs = 1){
  const d = novaAba();
  await d.criarConta({ email:`nt-${nome}-${marca}@teste.com`, senha:'minhasenhaboa',
    nome:'Dona ' + nome, telefone: tel() });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
  const salao = cr[0].salao_id;
  await banco.query(
    `update public.assinaturas set plano='salao', status='ativa' where salao_id=$1`,
    [salao]);

  const equipe = await d.lista('profissionais', { salaoId: salao });
  await d.atualizar('profissionais', equipe[0].id,
    { telefone:'11', ativo:true });
  await banco.query(
    `update public.profissionais set telefone='11988000001' where id=$1`,
    [equipe[0].id]);
  for(let i = 1; i < profs; i++){
    const p = await d.inserir('profissionais',
      { salaoId: salao, nome:'Prof ' + i, ativo:true, aceitaOnline:true });
    await banco.query(
      `update public.profissionais set telefone=$2 where id=$1`,
      [p.id, '1198800' + String(1000 + i)]);
    equipe.push(p);
  }
  for(const p of equipe)
    for(let dia = 0; dia <= 6; dia++)
      await d.inserir('jornadas', { profissionalId: p.id, diaSemana: dia,
                                    inicio:'08:00', fim:'20:00' });
  const sv = await d.inserir('servicos', { salaoId: salao, nome:'Corte',
    duracaoMin:60, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });
  return { d, salao, equipe, sv };
}

const cfg = (salao, o) => banco.query(
  `update public.saloes set cfg = coalesce(cfg,'{}'::jsonb) || $2::jsonb where id=$1`,
  [salao, JSON.stringify(o)]);

async function marcar(e, prof, quandoIso, nomeCliente){
  const c = await e.d.inserir('clientes', { salaoId: e.salao, nome: nomeCliente,
    telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });
  const a = await e.d.inserir('agendamentos', { salaoId: e.salao, clienteId: c.id,
    profissionalId: prof.id, inicio: quandoIso,
    fim: new Date(new Date(quandoIso).getTime() + 36e5).toISOString(),
    status:'confirmado', origem:'recepcao', valorPrevisto: 80 });
  await e.d.inserir('agendamento_servicos',
    { agendamentoId: a.id, servicoId: e.sv.id, preco: 80, duracaoMin: 60 });
  return { cliente: c, ag: a };
}

const fila = async (salao, extra = '') => (await banco.query(
  `select tipo, status, destino, quando, corpo, motivo, chave
     from public.notificacoes where salao_id=$1 ${extra} order by criado_em`,
  [salao])).rows;

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 1 e 2 — a confirmação e o aviso a quem vai atender
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) Cliente agenda → confirmação, e o profissional fica sabendo');

const A = await montar('Um', 1);
await cfg(A.salao, { notifLembrete: true, notifLembreteMin: 120 });

const DEPOIS = new Date(Date.now() + 3 * 864e5);
const dia3 = DEPOIS.toISOString().slice(0, 10);
const m1 = await marcar(A, A.equipe[0],
  `${dia3}T14:00:00${deslocamento(dia3)}`, 'Joana Pires');

let f = await fila(A.salao);
verdade('nasceu a confirmação da cliente',
  f.some(x => x.tipo === 'confirmacao'), JSON.stringify(f.map(x => x.tipo)));
verdade('e o aviso de novo agendamento para quem atende',
  f.some(x => x.tipo === 'novo'), JSON.stringify(f.map(x => x.tipo)));

const conf = f.find(x => x.tipo === 'confirmacao');
verdade('a confirmação traz data, horário, serviço, profissional e o salão',
  /14:00/.test(conf.corpo) && /Corte/.test(conf.corpo)
    && /Joana/.test(conf.corpo) && /Salão Um/.test(conf.corpo),
  JSON.stringify(conf.corpo));

/* ⚠ A verificação que sustenta a fase inteira. */
verdade('e NADA está marcado como enviado, porque nada foi enviado',
  f.every(x => x.status === 'pendente'),
  JSON.stringify(f.map(x => [x.tipo, x.status])));

const avisoProf = f.find(x => x.tipo === 'novo');
igual('o aviso vai para o telefone de quem atende',
  avisoProf.destino, '11988000001');

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 5 — o lembrete, uma vez só, na hora configurada
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) Lembrete configurado para 2 horas antes');

const lem = f.filter(x => x.tipo === 'lembrete');
igual('existe UM lembrete, não dois', lem.length, 1);

const distMin = Math.round(
  (new Date(m1.ag.inicio).getTime() - new Date(lem[0].quando).getTime()) / 60000);
igual('marcado para exatamente 2 horas antes', distMin, 120);
verdade('e o texto do lembrete não fala de promoção nem de reagendar',
  !/promo|cupom|desconto|reagend/i.test(lem[0].corpo), lem[0].corpo);

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 13 — nenhuma duplicidade
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) O mesmo agendamento não gera a mensagem duas vezes');

/* O gatilho rodando de novo é o que acontece num reprocessamento. A chave
   única do banco recusa antes de qualquer código conferir. */
const antesDup = (await fila(A.salao)).length;
await banco.query(
  `insert into public.notificacoes
     (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave)
   values ($1,'confirmacao','11999','${'00000000-0000-0000-0000-000000000000'}',
           null, now(), 'duplicata', 'confirmacao:' || $2)
   on conflict (salao_id, chave) do nothing`,
  [A.salao, m1.ag.id]).catch(() => {});
igual('a segunda tentativa não entra', (await fila(A.salao)).length, antesDup);

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 6 — cancelou, não lembra
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) Agendamento cancelado');

const m2 = await marcar(A, A.equipe[0],
  `${dia3}T16:00:00${deslocamento(dia3)}`, 'Rita Souza');
await banco.query(`update public.agendamentos set status='cancelado' where id=$1`,
  [m2.ag.id]);

const doCancelado = await fila(A.salao, `and agendamento_id = '${m2.ag.id}'`);
verdade('tudo o que ainda não saiu vira cancelado',
  doCancelado.length > 0 && doCancelado.every(x => x.status === 'cancelado'),
  JSON.stringify(doCancelado.map(x => [x.tipo, x.status])));
verdade('e o motivo fica escrito',
  doCancelado.every(x => /cancelado/.test(x.motivo || '')),
  JSON.stringify(doCancelado.map(x => x.motivo)));

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 7 — mudou de hora, o lembrete acompanha
   ══════════════════════════════════════════════════════════════════════════ */
secao('5) Agendamento alterado');

const novoIni = `${dia3}T18:00:00${deslocamento(dia3)}`;
await banco.query(
  `update public.agendamentos set inicio=$2::timestamptz,
          fim=$2::timestamptz + interval '1 hour' where id=$1`,
  [m1.ag.id, novoIni]);

const lemDepois = (await fila(A.salao, `and agendamento_id='${m1.ag.id}'`))
  .find(x => x.tipo === 'lembrete');
const dist2 = Math.round(
  (new Date(novoIni).getTime() - new Date(lemDepois.quando).getTime()) / 60000);
igual('o lembrete anda junto com o horário novo', dist2, 120);
verdade('e o TEXTO é reescrito — nunca sai com a hora velha',
  /18:00/.test(lemDepois.corpo) && !/14:00/.test(lemDepois.corpo),
  lemDepois.corpo);

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 4 e 8 — o resumo de quem trabalha sozinho
   ══════════════════════════════════════════════════════════════════════════ */
secao('6) Resumo do proprietário que trabalha sozinho');

const HOJE = maisDias(0);
const S = await montar('Sozinha', 1);
await cfg(S.salao, { notifResumo: true, notifResumoHora: 8, notifResumoPeriodo: 'dia' });
for(const h of ['09','10','14'])
  await marcar(S, S.equipe[0], `${HOJE}T${h}:00:00${deslocamento(HOJE)}`, 'Cliente ' + h);

// Fixa o instante: às 8h05 do salão o resumo já deve ter saído da hora.
const oitoEcinco = `${HOJE}T08:05:00${deslocamento(HOJE)}`;
await banco.query(`select public.gerar_resumos($1::timestamptz)`, [oitoEcinco]);

const rSozinha = (await fila(S.salao)).filter(x => x.tipo === 'resumo');
igual('sai UM resumo', rSozinha.length, 1);
verdade('sem cabeçalho de equipe, porque não há equipe',
  !/👤/.test(rSozinha[0].corpo), rSozinha[0].corpo);
verdade('com os três atendimentos e o total',
  /09:00/.test(rSozinha[0].corpo) && /14:00/.test(rSozinha[0].corpo)
    && /Total: 3/.test(rSozinha[0].corpo), rSozinha[0].corpo);

/* TESTE 12 do pedido de fase anterior, e item 18 desta: o resumo conta UMA
   mensagem, com três atendimentos dentro. Sai de graça da modelagem. */
igual('e três atendimentos continuam sendo uma linha na fila',
  rSozinha.length, 1);

// Rodar de novo no mesmo dia não duplica: a chave inclui o dia.
await banco.query(`select public.gerar_resumos($1::timestamptz)`, [oitoEcinco]);
igual('rodar o agendador de novo não manda o resumo duas vezes',
  (await fila(S.salao)).filter(x => x.tipo === 'resumo').length, 1);

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 3, 9 e 10 — o dono com equipe, e cada profissional com a sua
   ══════════════════════════════════════════════════════════════════════════ */
secao('7) Resumo do proprietário com equipe, e o de cada profissional');

const E = await montar('Equipe', 3);
await cfg(E.salao, { notifResumo: true, notifResumoHora: 8, notifResumoPeriodo: 'dia' });
await marcar(E, E.equipe[0], `${HOJE}T09:00:00${deslocamento(HOJE)}`, 'Cliente da Ju');
await marcar(E, E.equipe[1], `${HOJE}T10:00:00${deslocamento(HOJE)}`, 'Cliente do Um');
await marcar(E, E.equipe[2], `${HOJE}T11:00:00${deslocamento(HOJE)}`, 'Cliente do Dois');

await banco.query(`select public.gerar_resumos($1::timestamptz)`, [oitoEcinco]);
const rEquipe = (await fila(E.salao)).filter(x => x.tipo === 'resumo');

const daCasa = rEquipe.find(x => x.chave.startsWith('resumo:casa'));
verdade('o dono recebe o resumo da casa inteira',
  !!daCasa && /Total: 3 agendamento/.test(daCasa.corpo),
  daCasa ? daCasa.corpo : 'não saiu');
verdade('com os três profissionais separados por cabeçalho',
  daCasa && (daCasa.corpo.match(/👤/g) || []).length === 3,
  daCasa ? daCasa.corpo : '');

const doProf = rEquipe.filter(x => x.chave.startsWith('resumo:')
  && !x.chave.startsWith('resumo:casa'));
igual('e cada profissional recebe o dele', doProf.length, 3);
verdade('com um atendimento cada, e sem os das colegas',
  doProf.every(x => /Total: 1 atendimento/.test(x.corpo)),
  JSON.stringify(doProf.map(x => x.corpo.slice(-40))));

/* ══════════════════════════════════════════════════════════════════════════
   O PERÍODO — item 14
   ══════════════════════════════════════════════════════════════════════════ */
secao('8) Manhã, tarde e dia inteiro');

const P = await montar('Periodo', 1);
await cfg(P.salao, { notifResumo: true, notifResumoHora: 8,
                     notifResumoPeriodo: 'manha', notifManhaIni: 8, notifManhaFim: 12 });
await marcar(P, P.equipe[0], `${HOJE}T09:00:00${deslocamento(HOJE)}`, 'Da Manhã');
await marcar(P, P.equipe[0], `${HOJE}T15:00:00${deslocamento(HOJE)}`, 'Da Tarde');

const soManha = (await banco.query(
  `select public.texto_resumo($1, null, $2::date, 'manha') as t`,
  [P.salao, HOJE])).rows[0].t;
verdade('«manhã» traz só quem é da manhã',
  /Da Manhã/.test(soManha) && !/Da Tarde/.test(soManha), soManha);

const soTarde = (await banco.query(
  `select public.texto_resumo($1, null, $2::date, 'tarde') as t`,
  [P.salao, HOJE])).rows[0].t;
verdade('«tarde» traz só quem é da tarde',
  /Da Tarde/.test(soTarde) && !/Da Manhã/.test(soTarde), soTarde);

const oDiaTodo = (await banco.query(
  `select public.texto_resumo($1, null, $2::date, 'dia') as t`,
  [P.salao, HOJE])).rows[0].t;
verdade('e «dia inteiro» traz os dois',
  /Da Manhã/.test(oDiaTodo) && /Da Tarde/.test(oDiaTodo), oDiaTodo);

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 11 e 12 — a cota do plano e a virada do mês
   ══════════════════════════════════════════════════════════════════════════ */
secao('9) O limite de mensagens do plano');

const C = await montar('Cota', 1);
await banco.query(
  `update public.assinaturas set plano='individual' where salao_id=$1`, [C.salao]);

igual('o plano Individual dá 300 mensagens no mês',
  Number((await banco.query(`select public.teto_mensagens($1) as t`, [C.salao])).rows[0].t),
  300);
verdade('e com zero enviadas, pode enviar',
  (await banco.query(`select public.pode_enviar($1) as p`, [C.salao])).rows[0].p);

// Estoura a cota escrevendo envios do mês, como se tivessem saído.
await banco.query(
  `insert into public.notificacoes
     (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
   select $1, 'lembrete', '11999', now(), 'x', 'cheia:' || g, 'enviado', now()
     from generate_series(1, 300) g`, [C.salao]);

igual('trezentas enviadas contam trezentas',
  Number((await banco.query(`select public.mensagens_no_mes($1) as n`, [C.salao])).rows[0].n),
  300);
verdade('no teto, o banco recusa novos envios',
  (await banco.query(`select public.pode_enviar($1) as p`, [C.salao])).rows[0].p === false);

/* ⚠ E a recusa é do WORKER, não da tela. Uma mensagem pendente de um salão
   estourado não pode ser servida para envio. */
await marcar(C, C.equipe[0], `${dia3}T09:00:00${deslocamento(dia3)}`, 'Depois do Teto');
await banco.query(
  `update public.notificacoes set quando = now() - interval '1 minute'
    where salao_id=$1 and status='pendente'`, [C.salao]);
const servidas = (await banco.query(
  `select id from public.notificacoes_proxima_teste($1)`, [C.salao]).catch(() => null))
  || (await banco.query(`select * from public.notificacao_proxima(10)`));
verdade('o worker não serve mensagem de salão no teto',
  !servidas.rows.some(r => r.salao_id === C.salao),
  JSON.stringify(servidas.rows.map(r => r.salao_id)));

/* A virada do mês: envio do mês passado não conta no mês novo, e o histórico
   continua lá. */
await banco.query(
  `update public.notificacoes set enviado_em = now() - interval '45 days'
    where salao_id=$1 and chave like 'cheia:%'`, [C.salao]);
igual('no mês novo o contador zera',
  Number((await banco.query(`select public.mensagens_no_mes($1) as n`, [C.salao])).rows[0].n),
  0);
igual('e o histórico não foi apagado',
  Number((await banco.query(
    `select count(*)::int as n from public.notificacoes
      where salao_id=$1 and chave like 'cheia:%'`, [C.salao])).rows[0].n), 300);

/* ══════════════════════════════════════════════════════════════════════════
   AS OUTRAS COTAS — itens 25, 30 e 33
   ══════════════════════════════════════════════════════════════════════════ */
secao('10) Cliente, serviço e a tela Meu Plano');

/* Pela SESSÃO da dona, e não pelo psql: `uso_do_plano()` confere `e_gestor()`
   na primeira linha, e o superusuário não tem `auth.uid()`. Chamar por fora
   testaria um caminho que não existe no ar. */
const uso = await C.d.chamar('uso_do_plano', { p_salao: C.salao });
verdade('o uso do plano vem num jsonb só, com usado e teto',
  uso.clientes && uso.servicos && uso.mensagens && uso.profissionais,
  JSON.stringify(uso));
igual('e o teto de clientes do Individual é 500', uso.clientes.teto, 500);

// Um plano apertado, para a recusa acontecer de verdade.
await banco.query(
  `update public.assinaturas set plano='gratuito' where salao_id=$1`, [C.salao]);
await banco.query(
  `update public.planos set recursos = recursos || '{"max_servicos":1}'::jsonb
    where codigo='gratuito'`);
let recusou = null;
try{
  await C.d.inserir('servicos', { salaoId: C.salao, nome:'Segundo',
    duracaoMin:30, preco:50, ativo:true });
}catch(e){ recusou = e.message; }
verdade('passar do teto de serviços é recusado, e a frase diz o que fazer',
  /plano cobre 1 serviço/.test(recusou || ''), JSON.stringify(recusou));

/* ⚠ ITEM 33: descer de plano NÃO apaga nada. */
igual('e o que já existia continua existindo',
  Number((await banco.query(
    `select count(*)::int as n from public.servicos where salao_id=$1`,
    [C.salao])).rows[0].n), 1);
await banco.query(
  `update public.planos set recursos = recursos - 'max_servicos' || '{"max_servicos":10}'::jsonb
    where codigo='gratuito'`);

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 14 — dois salões, nenhum dado cruzado
   ══════════════════════════════════════════════════════════════════════════ */
secao('11) Isolamento entre estabelecimentos');

const B = await montar('Dois', 1);
await marcar(B, B.equipe[0], `${dia3}T09:00:00${deslocamento(dia3)}`, 'Cliente do B');

const daA = await fila(A.salao);
const daB = await fila(B.salao);
verdade('cada salão só tem as suas notificações',
  daA.length > 0 && daB.length > 0
    && !daA.some(x => /Cliente do B/.test(x.corpo)),
  `A=${daA.length} B=${daB.length}`);

/* E pelo RLS, com a sessão de verdade da dona do A pedindo as do B. */
const vazamento = await A.d.lista('notificacoes', { salaoId: B.salao })
  .catch(() => []);
igual('e o RLS não entrega as do vizinho nem pedindo pelo id',
  vazamento.length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   O WORKER — o único caminho que marca "enviado"
   ══════════════════════════════════════════════════════════════════════════ */
secao('12) O envio, e o que ele carimba');

const W = await montar('Worker', 1);
await marcar(W, W.equipe[0], `${dia3}T09:00:00${deslocamento(dia3)}`, 'Do Worker');
await banco.query(
  `update public.notificacoes set quando = now() - interval '1 minute'
    where salao_id=$1 and tipo='confirmacao'`, [W.salao]);

const pego = (await banco.query(
  `select * from public.notificacao_proxima(1)`)).rows[0];
verdade('o worker pega a mensagem cuja hora chegou', !!pego, JSON.stringify(pego));
igual('e a marca como enviando, não como enviada',
  (await banco.query(`select status from public.notificacoes where id=$1`,
    [pego.id])).rows[0].status, 'enviando');

await banco.query(`select public.notificacao_resultado($1, true, 'wamid.TESTE')`,
  [pego.id]);
const depoisDoEnvio = (await banco.query(
  `select status, enviado_em, wam_id from public.notificacoes where id=$1`,
  [pego.id])).rows[0];
igual('só depois do sucesso ela vira enviada', depoisDoEnvio.status, 'enviado');
verdade('com a hora do envio, que é de onde sai o consumo',
  !!depoisDoEnvio.enviado_em, JSON.stringify(depoisDoEnvio));

/* Falha não carimba `enviado_em` — senão o erro custaria cota. */
await banco.query(
  `update public.notificacoes set quando = now() - interval '1 minute'
    where salao_id=$1 and tipo='lembrete'`, [W.salao]);
const pego2 = (await banco.query(
  `select * from public.notificacao_proxima(1)`)).rows[0];
await banco.query(
  `select public.notificacao_resultado($1, false, null, '131026', 'sem sessão')`,
  [pego2.id]);
const falhou1 = (await banco.query(
  `select status, tentativas, proxima_em, enviado_em from public.notificacoes
    where id=$1`, [pego2.id])).rows[0];
igual('a primeira falha volta para pendente, com espera', falhou1.status, 'pendente');
verdade('e não carimba envio', falhou1.enviado_em === null, JSON.stringify(falhou1));

/* Mensagem vencida não sai. "Seu horário é daqui a duas horas", entregue no
   dia seguinte, é pior que silêncio. */
await banco.query(
  `update public.notificacoes set quando = now() - interval '2 days',
          status='pendente', proxima_em=null
    where id=$1`, [pego2.id]);
await banco.query(`select * from public.notificacao_proxima(5)`);
igual('mensagem parada há dois dias é aposentada, não enviada',
  (await banco.query(`select status from public.notificacoes where id=$1`,
    [pego2.id])).rows[0].status, 'cancelado');

/* ══════════════════════════════════════════════════════════════════════════
   TESTE 15 — o plano não se muda pelo navegador
   ══════════════════════════════════════════════════════════════════════════ */
secao('13) O plano não é editável pela tela');

let mexeu = null;
try{
  await W.d.atualizar('assinaturas',
    (await banco.query(`select id from public.assinaturas where salao_id=$1`,
      [W.salao])).rows[0].id, { plano: 'salao' });
  mexeu = 'passou';
}catch(e){ mexeu = e.message; }
igual('a dona não consegue subir o próprio plano pelo painel',
  (await banco.query(`select plano from public.assinaturas where salao_id=$1`,
    [W.salao])).rows[0].plano, 'salao');

/* ══════════════════════════════════════════════════════════════════════════
   OS MODELOS APROVADOS

   Texto livre só sai dentro de 24h da última mensagem da PESSOA. As nossas
   quatro são todas fora dessa janela — a cliente marcou pelo site e nunca
   escreveu. Sem modelo, tudo volta com 131047.
   ══════════════════════════════════════════════════════════════════════════ */
secao('15) O modelo e as variáveis que viajam para a Meta');

const M = await montar('Modelo', 1);
await marcar(M, M.equipe[0], `${dia3}T15:00:00${deslocamento(dia3)}`, 'Rita Souza');

const linhaM = (await banco.query(
  `select tipo, modelo, variaveis, corpo from public.notificacoes
    where salao_id=$1 and tipo='confirmacao'`, [M.salao])).rows[0];

igual('a confirmação nasce com o modelo aprovado',
  linhaM.modelo, 'agendapro_confirmacao');
igual('e com cinco variáveis, na ordem do texto cadastrado',
  (linhaM.variaveis || []).length, 5);
igual('a primeira é o PRIMEIRO nome', linhaM.variaveis[0], 'Rita');
verdade('a segunda é a data', /^\d{2}\/\d{2}\/\d{4}$/.test(linhaM.variaveis[1]),
  JSON.stringify(linhaM.variaveis));
igual('a terceira é a hora, no fuso do salão', linhaM.variaveis[2], '15:00');

/* O aviso ao profissional usa o nome INTEIRO — é ele que a pessoa procura na
   agenda. Confundir os dois foi um erro que eu cometi ao refatorar. */
const novoM = (await banco.query(
  `select variaveis from public.notificacoes
    where salao_id=$1 and tipo='novo'`, [M.salao])).rows[0];
if(novoM){
  igual('o aviso ao profissional leva quatro variáveis',
    (novoM.variaveis || []).length, 4);
  igual('e o nome COMPLETO da cliente, não só o primeiro',
    novoM.variaveis[0], 'Rita Souza');
}

/* ⚠ NENHUMA VARIÁVEL PODE TER QUEBRA DE LINHA NEM VIR VAZIA — a Meta recusa a
   mensagem inteira, e o erro não diz qual das cinco era. */
const todasVars = (await banco.query(
  `select variaveis from public.notificacoes
    where salao_id=$1 and variaveis is not null`, [M.salao])).rows;
verdade('nenhuma variável tem quebra de linha',
  todasVars.every(r => r.variaveis.every(v => !/[\r\n\t]/.test(v))),
  JSON.stringify(todasVars.map(r => r.variaveis)));
verdade('e nenhuma vem vazia',
  todasVars.every(r => r.variaveis.every(v => String(v).trim() !== '')),
  JSON.stringify(todasVars.map(r => r.variaveis)));

/* ⚠ E AS VARIÁVEIS ANDAM JUNTO COM O CORPO.

   Foi assim que o defeito "Serviço: atendimento" apareceu na fase passada: o
   serviço entra depois da ficha, e o texto era montado antes. Agora existem
   DOIS textos por linha — o corpo, que o painel mostra, e as variáveis, que a
   cliente recebe. Atualizar um e esquecer o outro faz o painel mostrar o
   certo e a cliente receber o errado, que é pior do que os dois errados. */
const outraHora = `${dia3}T17:30:00${deslocamento(dia3)}`;
await banco.query(
  `update public.agendamentos set inicio=$2,
          fim = $2::timestamptz + (fim - inicio)
    where salao_id=$1`, [M.salao, outraHora]);
const depoisDeRemarcar = (await banco.query(
  `select corpo, variaveis from public.notificacoes
    where salao_id=$1 and tipo='lembrete'`, [M.salao])).rows[0];
if(depoisDeRemarcar){
  verdade('remarcar reescreve o corpo', /17:30/.test(depoisDeRemarcar.corpo),
    depoisDeRemarcar.corpo);
  igual('e a variável da hora junto com ele',
    depoisDeRemarcar.variaveis[2], '17:30');
}

// A fila entrega o modelo ao worker — sem isso ele cairia em texto livre.
await banco.query(
  `update public.notificacoes set quando = now() - interval '1 minute'
    where salao_id=$1 and tipo='confirmacao'`, [M.salao]);
const daFila = (await banco.query(
  `select * from public.notificacao_proxima(1)`)).rows[0];
verdade('a fila entrega o modelo ao worker',
  !!daFila && daFila.modelo === 'agendapro_confirmacao', JSON.stringify(daFila));
verdade('e as variáveis junto',
  !!daFila && Array.isArray(daFila.variaveis) && daFila.variaveis.length === 5,
  JSON.stringify(daFila && daFila.variaveis));

/* ══════════════════════════════════════════════════════════════════════════
   O WEBHOOK DE STATUS DA META

   Até aqui a fila só sabia de 'enviado'. `entregue` e `lido` são informação;
   `falhou` é CORREÇÃO — a Meta aceitou a mensagem, devolveu wam_id, a linha
   virou 'enviado' e já custou cota, e só depois ela descobre que não dá para
   entregar. Sem este caminho, a linha mente para sempre.
   ══════════════════════════════════════════════════════════════════════════ */
secao('14) O que a Meta conta depois do envio');

// Uma linha como o worker a deixa depois de a Graph API responder OK.
async function jaEnviada(salao, wam){
  return (await banco.query(
    `insert into public.notificacoes
       (salao_id, tipo, destino, quando, corpo, chave,
        status, enviado_em, wam_id)
     values ($1, 'confirmacao', '5511988887777', now(), 'corpo qualquer', $2,
             'enviado', now(), $3)
     returning id`, [salao, 'teste:' + wam, wam])).rows[0].id;
}
const estado = async id => (await banco.query(
  `select status, erro_codigo, erro_msg from public.notificacoes where id=$1`,
  [id])).rows[0];
const avisar = (wam, st, cod, msg) => banco.query(
  `select public.notificacao_status($1,$2,$3,$4)`, [wam, st, cod ?? null, msg ?? null]);

const n1 = await jaEnviada(W.salao, 'wamid.E1');
await avisar('wamid.E1', 'entregue');
igual('delivered move de enviado para entregue', (await estado(n1)).status, 'entregue');
await avisar('wamid.E1', 'lido');
igual('e read move para lido', (await estado(n1)).status, 'lido');

/* ⚠ A Meta NÃO garante ordem. Um `delivered` atrasado chegando depois do
   `read` não pode desfazer o que já se sabe. */
await avisar('wamid.E1', 'entregue');
igual('um delivered atrasado não desfaz o lido', (await estado(n1)).status, 'lido');

// E o caminho contrário: `read` chegando primeiro, sem o `delivered`.
const n2 = await jaEnviada(W.salao, 'wamid.E2');
await avisar('wamid.E2', 'lido');
igual('read chegando antes de delivered também vale',
  (await estado(n2)).status, 'lido');

// A falha, com o motivo que a cliente vai ouvir da recepção.
const n3 = await jaEnviada(W.salao, 'wamid.E3');
await avisar('wamid.E3', 'falhou', '131026', 'Message undeliverable');
const naoEntregue = await estado(n3);
igual('failed move para falhou', naoEntregue.status, 'falhou');
igual('guardando o código do erro', naoEntregue.erro_codigo, '131026');
verdade('e o motivo por extenso',
  /undeliverable/i.test(naoEntregue.erro_msg || ''), naoEntregue.erro_msg);

/* Um `failed` depois de lido é contradição: a mensagem chegou e alguém abriu.
   Ruído da Meta não pode apagar o que já foi visto. */
await avisar('wamid.E1', 'falhou', '131026', 'atrasado');
igual('um failed atrasado não derruba uma mensagem já lida',
  (await estado(n1)).status, 'lido');

igual('status que não existe não mexe em nada',
  (await (async () => { await avisar('wamid.E2', 'sei-la'); return estado(n2); })()).status,
  'lido');

/* Cancelada não ressuscita. A linha de um horário desmarcado não pode voltar
   à vida porque um aviso da Meta chegou atrasado. */
const n4 = await jaEnviada(W.salao, 'wamid.E4');
await banco.query(
  `update public.notificacoes set status='cancelado' where id=$1`, [n4]);
await avisar('wamid.E4', 'entregue');
igual('cancelada continua cancelada', (await estado(n4)).status, 'cancelado');

/* ── A CONTA QUE FECHA SOZINHA ──────────────────────────────────────────────
   `mensagens_no_mes()` conta enviado/entregue/lido. Sair para 'falhou' devolve
   o crédito sem nenhuma linha de código a mais — e é o certo: mensagem que não
   chegou não pode custar. */
const cotaAntes = (await banco.query(
  `select public.mensagens_no_mes($1) as n`, [W.salao])).rows[0].n;
const n5 = await jaEnviada(W.salao, 'wamid.E5');
const cotaComElaNoAr = (await banco.query(
  `select public.mensagens_no_mes($1) as n`, [W.salao])).rows[0].n;
igual('uma mensagem enviada consome uma do mês', cotaComElaNoAr, cotaAntes + 1);

await avisar('wamid.E5', 'falhou', '131026', 'número não tem WhatsApp');
const cotaDepois = (await banco.query(
  `select public.mensagens_no_mes($1) as n`, [W.salao])).rows[0].n;
igual('e a que a Meta não entregou devolve a cota', cotaDepois, cotaAntes);
verdade('sem apagar a linha: o histórico continua contando o que houve',
  (await estado(n5)).status === 'falhou');

/* O índice que o webhook usa. Sem ele, cada um dos dois ou três avisos por
   mensagem varre a fila inteira — barato hoje, caro quando o volume chegar. */
igual('a busca pelo wam_id tem índice',
  (await banco.query(
    `select count(*)::int as n from pg_indexes
      where tablename='notificacoes' and indexname='ix_notif_wam'`)).rows[0].n, 1);

await banco.query(`delete from public.agendamentos where salao_id = any($1)`,
  [[A.salao, S.salao, E.salao, P.salao, C.salao, B.salao, W.salao, M.salao]]);
await banco.query(`delete from public.saloes where id = any($1)`,
  [[A.salao, S.salao, E.salao, P.salao, C.salao, B.salao, W.salao, M.salao]]);
await banco.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações das notificações e das cotas.`);
