/* ===========================================================================
   AgendaPro — bloqueio e atendimento não passam juntos

     bash tests/bancada/subir.sh
     node tests/corrida.test.mjs

   ── O QUE FOI MEDIDO ANTES DE ESTE ARQUIVO EXISTIR ─────────────────────────
   Duas conexões, caminho normal, sem encaixe, jornada aberta:

       A inseriu o atendimento (sem comitar)
       B inseriu o bloqueio    (sem comitar)
       A comitou
       B comitou
       depois das duas: {"atendimentos":"1","bloqueios":"1"}

   O almoço e o atendimento ficaram no mesmo horário. Depois disso nada
   detecta o estado: a grade desenha um bloco em cima do outro, e a
   profissional descobre quando a cliente chega.

   ── POR QUE UM TESTE DE UMA CONEXÃO SÓ NÃO ACHARIA ─────────────────────────
   Atendimento contra atendimento é uma CONSTRAINT (`agenda_sem_choque`), e
   constraint não tem corrida. Atendimento contra BLOQUEIO são duas tabelas, e
   EXCLUDE não atravessa duas tabelas — a regra é um par de gatilhos, e
   gatilho enxerga só o que já foi comitado.

   Rodando as duas escritas em sequência, os gatilhos funcionam perfeitamente
   e o teste fica verde. O furo só aparece com as duas transações ABERTAS ao
   mesmo tempo, que é por isso que este arquivo abre duas conexões de verdade
   em vez de chamar duas funções.

   ── O QUE ESTE ARQUIVO EXIGE ───────────────────────────────────────────────
   Que a segunda transação ESPERE a primeira e então enxergue o que ela
   gravou — nos dois sentidos, porque inverter a ordem seria outro caminho e
   dava para furar por ele.

   E que a trava seja só do salão: dois salões diferentes escrevendo ao mesmo
   tempo não podem se esperar, senão o conserto vira gargalo.
   =========================================================================== */
import pg from './pg.mjs';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
const secao = t => console.log('\n' + t);

const conf = { host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' };

const admin = new pg.Client(conf); await admin.connect();

async function montarSalao(nome){
  const s = (await admin.query(
    `insert into public.saloes (slug, nome, tipo, fuso)
     values ($1, $2, 'salao', 'America/Sao_Paulo') returning id`,
    // O slug tem regra própria no schema: minúsculas, sem espaço.
    [nome.toLowerCase().replace(/[^a-z0-9]+/g, '-')
       + '-' + Date.now().toString(36) + Math.floor(Math.random()*1000), nome]
  )).rows[0].id;
  const p = (await admin.query(
    `insert into public.profissionais (salao_id, nome, ativo)
     values ($1, 'Ana', true) returning id`, [s])).rows[0].id;
  const c = (await admin.query(
    `insert into public.clientes (salao_id, nome) values ($1, 'Cliente') returning id`,
    [s])).rows[0].id;
  // Jornada aberta todo dia: assim o agendamento passa pelo caminho NORMAL,
  // sem encaixe, e a corrida medida é a de verdade.
  for(let d = 0; d <= 6; d++)
    await admin.query(
      `insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
       values ($1, $2, '00:00', '23:59')`, [p, d]);
  return { salao: s, prof: p, cliente: c };
}

const INI = "date_trunc('hour', now() + interval '3 days')";
const FIM = "date_trunc('hour', now() + interval '3 days') + interval '1 hour'";

const marcar = (cx, e) => cx.query(
  `insert into public.agendamentos (salao_id, cliente_id, profissional_id,
     inicio, fim, status, origem, encaixe)
   values ($1,$2,$3, ${INI}, ${FIM}, 'confirmado', 'recepcao', false)`,
  [e.salao, e.cliente, e.prof]);

const bloquear = (cx, e) => cx.query(
  `insert into public.bloqueios (salao_id, profissional_id, inicio, fim, motivo)
   values ($1,$2, ${INI}, ${FIM}, 'almoço')`, [e.salao, e.prof]);

async function contar(salao){
  const r = await admin.query(
    `select (select count(*)::int from public.agendamentos
              where salao_id=$1
                and status in ('pendente','confirmado','em_atendimento','concluido')
                and arquivado_em is null) as atendimentos,
            (select count(*)::int from public.bloqueios where salao_id=$1) as bloqueios`,
    [salao]);
  return r.rows[0];
}

/* ⚠ ESTE ARRANJO É O TESTE INTEIRO, E A PRIMEIRA VERSÃO DELE NÃO TESTAVA NADA.

   Estava assim: `a` escreve, `b` começa a escrever sem ser aguardado, e `a`
   comita em seguida. Parece a corrida — e não é. As duas conexões falam com o
   servidor de forma independente, então o `commit` de `a` chegava ANTES de o
   insert de `b` sair daqui. `b` então enxergava tudo comitado e recusava
   direitinho.

   Resultado: o teste ficou VERDE com a trava removida do banco. Passava pelo
   motivo errado, que é a única coisa pior do que reprovar.

   O que faz a corrida existir é o insert de `b` ter RODADO — gatilho e tudo —
   com `a` ainda aberta. Então aqui se espera `b` chegar a um dos dois
   estados possíveis antes de comitar `a`:

     · travado esperando (`wait_event_type = 'Lock'`) → a trava está de pé
     · terminado                                      → não há trava nenhuma,
                                                        e é o furo

   Sem relógio fixo: pergunta ao `pg_stat_activity` até um dos dois valer. Um
   `sleep` de 300ms passaria a maior parte das vezes e falharia numa máquina
   carregada, que é o tipo de teste que ninguém confia depois. */
async function corrida(e, primeiro, segundo){
  const a = new pg.Client(conf); await a.connect();
  const b = new pg.Client(conf); await b.connect();
  let erroDoSegundo = null;
  try{
    await a.query('begin');
    await b.query('begin');
    const pidB = (await b.query('select pg_backend_pid() as p')).rows[0].p;

    await primeiro(a, e);

    let terminou = false;
    const oSegundo = segundo(b, e).then(
      () => { terminou = true; },
      err => { terminou = true; erroDoSegundo = err.message; });

    const ateQuando = Date.now() + 8000;
    for(;;){
      if(terminou) break;
      const r = await admin.query(
        `select wait_event_type as w from pg_stat_activity where pid = $1`, [pidB]);
      if(r.rows[0] && r.rows[0].w === 'Lock') break;
      if(Date.now() > ateQuando){
        throw new Error('o segundo lado não travou nem terminou em 8s');
      }
      await new Promise(r2 => setTimeout(r2, 25));
    }

    await a.query('commit');
    await oSegundo;
    if(erroDoSegundo) await b.query('rollback');
    else await b.query('commit');
  } finally {
    await a.end(); await b.end();
  }
  return erroDoSegundo;
}

/* ══════════════════════════════════════════════════════════════════════════
   1. MARCA E BLOQUEIA AO MESMO TEMPO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) A recepção bloqueia o almoço enquanto a cliente confirma');

{
  const e = await montarSalao('Corrida A');
  const erro = await corrida(e, marcar, bloquear);
  const n = await contar(e.salao);

  verdade('o bloqueio é recusado, e diz por quê',
    /atendimento marcado nesse período/i.test(erro || ''), JSON.stringify(erro));
  verdade('o atendimento fica de pé', n.atendimentos === 1, JSON.stringify(n));
  verdade('e o bloqueio NÃO entra por cima dele', n.bloqueios === 0,
    JSON.stringify(n) + ' — almoço e atendimento no mesmo horário');
}

/* ══════════════════════════════════════════════════════════════════════════
   2. E NA ORDEM INVERSA

   Sem esta metade dava para furar simplesmente invertendo quem chega antes —
   que é o que aconteceria metade das vezes, por acaso.
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) E ao contrário: bloqueia primeiro, marca depois');

{
  const e = await montarSalao('Corrida B');
  const erro = await corrida(e, bloquear, marcar);
  const n = await contar(e.salao);

  verdade('a marcação é recusada, sem contar o motivo do bloqueio',
    /indispon|bloquead/i.test(erro || '')
      && !/almoço/i.test(erro || ''), JSON.stringify(erro));
  verdade('o bloqueio fica de pé', n.bloqueios === 1, JSON.stringify(n));
  verdade('e o atendimento NÃO entra por cima dele', n.atendimentos === 0,
    JSON.stringify(n));
}

/* ══════════════════════════════════════════════════════════════════════════
   3. HORÁRIOS QUE NÃO SE TOCAM CONTINUAM PASSANDO OS DOIS

   Uma trava que serializa é fácil de confundir com uma trava que RECUSA. Se
   o conserto tivesse virado "só um por vez, e o segundo perde", bloquear a
   tarde enquanto alguém marca de manhã passaria a falhar — e ninguém ligaria
   uma coisa à outra.
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) Serializar não é recusar');

{
  const e = await montarSalao('Corrida C');
  const bloquearOutraHora = (cx, x) => cx.query(
    `insert into public.bloqueios (salao_id, profissional_id, inicio, fim, motivo)
     values ($1,$2, ${INI} + interval '5 hours', ${FIM} + interval '5 hours', 'médico')`,
    [x.salao, x.prof]);

  const erro = await corrida(e, marcar, bloquearOutraHora);
  const n = await contar(e.salao);
  verdade('bloquear outra hora não é recusado', erro === null, JSON.stringify(erro));
  verdade('e os dois convivem, porque não se cruzam',
    n.atendimentos === 1 && n.bloqueios === 1, JSON.stringify(n));
}

/* ══════════════════════════════════════════════════════════════════════════
   4. SALÕES DIFERENTES NÃO SE ESPERAM

   A trava é chaveada pelo salão. Se fosse global, o conserto de um defeito
   raro viraria uma fila para o sistema inteiro — e o remédio seria pior.
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) Um salão não segura o outro');

{
  const e1 = await montarSalao('Corrida D1');
  const e2 = await montarSalao('Corrida D2');

  const a = new pg.Client(conf); await a.connect();
  const b = new pg.Client(conf); await b.connect();
  await a.query('begin');
  await b.query('begin');
  await marcar(a, e1);

  /* `b` escreve no OUTRO salão com `a` ainda aberta. Se as duas dividissem
     trava, esta linha ficaria pendurada até o commit de `a` — e o teste
     morreria no tempo limite em vez de reprovar. Daí o relógio. */
  const relogio = new Promise((_, x) =>
    setTimeout(() => x(new Error('o outro salão ficou esperando')), 5000));
  let livre = true;
  try{ await Promise.race([marcar(b, e2), relogio]); }
  catch(err){ livre = false; }

  await a.query('commit');
  await b.query('commit').catch(() => {});
  await a.end(); await b.end();

  verdade('o segundo salão escreve sem esperar o primeiro', livre,
    'a trava não pode ser global');
  const n2 = await contar(e2.salao);
  verdade('e a marcação dele entrou', n2.atendimentos === 1, JSON.stringify(n2));
}

await admin.query(
  `delete from public.saloes where nome like 'Corrida %'`);
await admin.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações da corrida entre bloqueio e atendimento.`);
