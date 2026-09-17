/* ===========================================================================
   AgendaPro — o salão confirma, ou o link confirma sozinho

     bash tests/bancada/subir.sh
     node tests/confirmacao.test.mjs

   ── O QUE ESTÁ SENDO MEDIDO ────────────────────────────────────────────────
   O `agendar()` gravava `'confirmado'` escrito à mão, e o `'pendente'` era uma
   porta que o schema tinha desde o começo e ninguém abria.

   ⚠ E A PARTE CARA NÃO É O STATUS — É A MENSAGEM.

   Trocar a palavra no `agendar()` faria o banco enfileirar, no mesmo instante,
   um WhatsApp dizendo "Seu horário está confirmado" de um horário que o dono
   ainda não olhou. O `tg_notificar_agendamento()` do 21 dispara no INSERT e
   aceitava os dois status.

   A seção 2 é a que mede isso, e é a razão deste arquivo existir. Sem ela, o
   resto passaria com o sistema prometendo em nome do salão.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
const tel = n => '+5551' + String(900000000 + n + (Date.now() % 89000000)).slice(0, 9);

// ── O salão ────────────────────────────────────────────────────────────────
const d = novaAba();
await d.criarConta({ email:`cf-dona-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona Confirma', telefone: tel(1) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Confirma ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
/* Rajada e teto afrouxados, como nas outras suítes: as duas travas são certas
   e barram um arquivo que marca dezenas de horários em segundos. Sem isto,
   uma falha da CONFIRMAÇÃO apareceria como "a marcação está congestionada". */
await d.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:60, tetoOnlinePct:100, tetoOnlineRajada:100 } });

const prof = (await d.lista('profissionais', { salaoId: SALAO }))[0];
/* ⚠ O PROFISSIONAL PRECISA DE TELEFONE, e eu escrevi o comentário antes de
   escrever a linha — a seção 2 reprovou por isso.

   O aviso `novo` só é enfileirado quando `profissionais.telefone` existe e
   `notif_novo` está ligado. Sem o telefone não havia para onde mandar, e a
   medida acusava "o dono não fica sabendo" quando o gatilho nem tinha tentado:
   um defeito de montagem apontando para o lugar errado. */
await d.atualizar('profissionais', prof.id,
  { telefone: String(51911000000 + (Date.now() % 88000000)), notifNovo: true });

for(let i = 0; i <= 6; i++)
  await d.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                inicio:'08:00', fim:'20:00' });
const corte = await d.inserir('servicos', { salaoId:SALAO, nome:'Corte',
  preco:50, duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });
ok('salão com um serviço e jornada todos os dias');

const FUSO = 'America/Sao_Paulo';
const hojeNoSalao = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO,
  year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date());
const maisDias = (data, n) => {
  const x = new Date(data + 'T12:00:00Z');
  x.setUTCDate(x.getUTCDate() + n);
  return x.toISOString().slice(0, 10);
};
let diaDaVez = 2;
const asDez = () => maisDias(hojeNoSalao, diaDaVez++) + 'T13:00:00Z';

const TEL_CLI = tel(2);
const cliente = novaAba();
await cliente.criarConta({ email:`cf-cli-${marca}@teste.com`,
  senha:'minhasenhaboa', nome:'Joana Cliente', telefone: TEL_CLI });

const marcar = () => cliente.chamar('agendar', { p_profissional: prof.id,
  p_inicio: asDez(), p_servicos:[corte.id],
  p_nome:'Joana Cliente', p_telefone: TEL_CLI });

const doAgendamento = async agId =>
  (await d.lista('agendamentos', { id: agId }))[0];
const notificacoesDe = async agId =>
  (await d.lista('notificacoes', { agendamentoId: agId }));

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ O PADRÃO É AUTOMÁTICO, E NADA MUDA PARA QUEM JÁ USA O LINK

   Se a ausência da chave valesse "o dono confirma", todo salão que já usa a
   agenda online acordaria amanhã com pendências que ninguém pediu — e
   clientes esperando uma resposta que o dono não sabe que deve dar.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Salão novo, sem a chave no cfg');

igual('o salão nasce confirmando sozinho',
  await d.chamar('confirma_automatico', { p_salao: SALAO }), true);

const r1 = await marcar();
const a1 = await doAgendamento(r1[0].id);
igual('o horário entra já confirmado', a1.status, 'confirmado');

const n1 = await notificacoesDe(a1.id);
verdade('e a confirmação é enfileirada na hora — '
  + JSON.stringify(n1.map(x => x.tipo)),
  n1.some(x => x.tipo === 'confirmacao'),
  'a cliente marcou e não recebe confirmação nenhuma');

/* ══════════════════════════════════════════════════════════════════════════
   2 — ⚠ DESLIGADO: PENDENTE, E NENHUMA PROMESSA NO WHATSAPP

   A seção que este arquivo existe para provar.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O salão passa a confirmar à mão');

await d.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:60, tetoOnlinePct:100, tetoOnlineRajada:100,
          confirmaAuto: false } });
igual('o banco passa a responder que não confirma sozinho',
  await d.chamar('confirma_automatico', { p_salao: SALAO }), false);

const r2 = await marcar();
const a2 = await doAgendamento(r2[0].id);
igual('o horário entra PENDENTE', a2.status, 'pendente');

const n2 = await notificacoesDe(a2.id);
console.log('      notificações: ' + JSON.stringify(n2.map(x => x.tipo)));
verdade('NENHUMA confirmação sai antes de o dono olhar',
  !n2.some(x => x.tipo === 'confirmacao'),
  'o sistema prometeu em nome do salão um horário que ele não aceitou');
/* O lembrete também espera: "seu horário é amanhã às 15h" lê-se como
   confirmação, e ninguém lê aquilo como "talvez". */
verdade('e nenhum lembrete é marcado ainda',
  !n2.some(x => x.tipo === 'lembrete'),
  'lembrar de um horário não aceito é confirmá-lo por tabela');
/* Mas o salão PRECISA saber que tem coisa esperando. */
verdade('o aviso para quem atende sai na hora — é como o dono descobre',
  n2.some(x => x.tipo === 'novo'),
  'sem este aviso o dono não sabe que existe algo para confirmar');

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ O HORÁRIO FICA GUARDADO ENQUANTO ESPERA

   Se `pendente` não segurasse a cadeira, duas pessoas marcariam o mesmo
   horário durante a espera — e uma delas ouviria "não" depois de já ter
   combinado o dia.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A cadeira durante a espera');

const outra = novaAba();
const TEL_OUTRA = tel(3);
await outra.criarConta({ email:`cf-out-${marca}@teste.com`,
  senha:'minhasenhaboa', nome:'Bia Outra', telefone: TEL_OUTRA });

let barrou = null;
try{
  await outra.chamar('agendar', { p_profissional: prof.id,
    p_inicio: a2.inicio, p_servicos:[corte.id],
    p_nome:'Bia Outra', p_telefone: TEL_OUTRA });
}catch(e){ barrou = e.message || String(e); }
verdade('outra pessoa não consegue pegar o mesmo horário — '
  + JSON.stringify(String(barrou).slice(0, 50)),
  barrou !== null, 'o horário pendente não está segurando a cadeira');

/* ══════════════════════════════════════════════════════════════════════════
   4 — ⚠ CONFIRMANDO, A MENSAGEM SAI

   Sem o gatilho do 29, o dono confirmaria e a cliente nunca saberia.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O dono confirma');

await d.atualizar('agendamentos', a2.id, { status:'confirmado' });
const n3 = await notificacoesDe(a2.id);
console.log('      notificações: ' + JSON.stringify(n3.map(x => x.tipo)));
verdade('agora a confirmação é enfileirada',
  n3.some(x => x.tipo === 'confirmacao'),
  'o dono confirmou e a cliente não vai saber');
verdade('e o lembrete também',
  n3.some(x => x.tipo === 'lembrete'),
  'o lembrete ficou preso no status antigo');

/* ⚠ E CONFIRMAR DUAS VEZES NÃO MANDA DUAS MENSAGENS. Os `insert` do 21
   terminam em `on conflict (salao_id, chave) do nothing`, e é isso que deixa
   o gatilho do 29 reaproveitar a mesma função sem risco. */
await d.atualizar('agendamentos', a2.id, { status:'em_atendimento' });
await d.atualizar('agendamentos', a2.id, { status:'confirmado' });
const n4 = await notificacoesDe(a2.id);
igual('confirmar de novo não duplica a mensagem',
  n4.filter(x => x.tipo === 'confirmacao').length, 1);

/* ══════════════════════════════════════════════════════════════════════════
   5 — RECUSAR CANCELA O QUE ESTIVER NA FILA
   ══════════════════════════════════════════════════════════════════════════ */
secao('O dono recusa');

const r5 = await marcar();
const a5 = await doAgendamento(r5[0].id);
igual('nasce pendente', a5.status, 'pendente');
await d.atualizar('agendamentos', a5.id,
  { status:'cancelado', canceladoMotivo:'não confirmado pelo salão' });
const n5 = await notificacoesDe(a5.id);
const vivas = n5.filter(x => x.status === 'pendente');
igual('nada fica na fila para ser enviado depois — '
  + JSON.stringify(n5.map(x => x.tipo + ':' + x.status)), vivas.length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   6 — LIXO NO CFG CAI NO LADO SEGURO

   `'abacaxi'::boolean` LEVANTA no Postgres, e um cast desprotegido aqui
   derrubaria TODA marcação do salão.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Valor inválido no cfg');

await d.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:60, tetoOnlinePct:100, tetoOnlineRajada:100,
          confirmaAuto:'abacaxi' } });
let explodiu = null, resposta = null;
try{ resposta = await d.chamar('confirma_automatico', { p_salao: SALAO }); }
catch(e){ explodiu = e.message || String(e); }
verdade('a função continua respondendo', explodiu === null, explodiu);
igual('e cai no automático, que é o lado seguro', resposta, true);

let caiu = null, r6 = null;
try{ r6 = await marcar(); }catch(e){ caiu = e.message || String(e); }
verdade('marcar continua funcionando com lixo no cfg', caiu === null, caiu);
if(r6) igual('e o horário entra confirmado',
  (await doAgendamento(r6[0].id)).status, 'confirmado');

/* ══════════════════════════════════════════════════════════════════════════
   7 — ⚠ E A CLIENTE PRECISA PODER PERGUNTAR

   A página dela decide entre "Pronto, está confirmado" e "Você receberá uma
   mensagem de confirmação" com esta resposta. Quem abre o link não tem conta.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Sem login');

const anon = novaAba();
let semConta = null, erroAnon = null;
try{ semConta = await anon.chamar('confirma_automatico', { p_salao: SALAO }); }
catch(e){ erroAnon = e.message || String(e); }
verdade('quem não tem conta consegue perguntar — ' + JSON.stringify(semConta),
  erroAnon === null,
  'a página da cliente não conseguiria saber o que prometer: ' + erroAnon);

console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
