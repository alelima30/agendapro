/* ===========================================================================
   AgendaPro — o dia fecha, e a falta passa a existir

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/fecho-dia.test.mjs

   ── A INTELIGÊNCIA QUE ESTAVA ESCRITA E DESLIGADA ──────────────────────────
   O status 'faltou' existe, e muita coisa depende dele: o aviso de que a
   cliente já faltou N vezes, a sugestão de pedir sinal a partir da terceira,
   a linha de "perdido" no relatório, os contadores do painel do dia.

   E nada no sistema movia um atendimento para lá. Era troca manual, uma a
   uma, na hora em que a recepção está fechando o caixa. O que acontece de
   fato é o previsível: quem veio vira "concluído", quem não veio fica
   "confirmado" para sempre — e o histórico de falta, que é justamente o dado
   que justificaria cobrar sinal, nunca acumula.

   ── O QUE ESTE ARQUIVO EXIGE ───────────────────────────────────────────────
   Que a Agenda pergunte, e que a resposta CHEGUE AO BANCO — porque é do banco
   que o relatório e o painel leem. E, no fim, que o aviso de falta acenda:
   ele é a razão de tudo isto existir, e enquanto não acender o fecho de dia é
   trabalho a mais sem retorno.

   E três coisas que separam um lembrete útil de um aviso para ignorar:
   atendimento de HOJE não entra (o dia ainda não acabou), o que já tem
   desfecho não volta, e a faixa some sozinha quando não há o que responder.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pg from './pg.mjs';
import { maisDias, deslocamento } from './dia.mjs';

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

const dona = novaAba();
await dona.criarConta({ email:`fecho-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju do Fecho',
  telefone:'+5511' + (100000000 + Math.floor(Math.random()*89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Fecho ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
await banco.query(
  `update public.assinaturas set plano='time', status='ativa' where salao_id=$1`,
  [SALAO]);

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let d = 0; d <= 6; d++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:d,
                                   inicio:'08:00', fim:'20:00' });
const sv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:60, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });

const HOJE   = maisDias(0);
const ONTEM  = maisDias(-1);
const ANTES  = maisDias(-2);
const VELHO  = maisDias(-9);   // fora da janela do fecho, de propósito

async function marcar(nome, dia, hora, status){
  const c = await dona.inserir('clientes', { salaoId: SALAO, nome,
    telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });
  const d = deslocamento(dia);
  const a = await dona.inserir('agendamentos', { salaoId: SALAO, clienteId: c.id,
    profissionalId: prof.id,
    inicio: `${dia}T${hora}:00${d}`,
    fim:    `${dia}T${String(Number(hora.slice(0,2)) + 1).padStart(2,'0')}:00${d}`,
    status, origem:'recepcao', valorPrevisto: 80 });
  await dona.inserir('agendamento_servicos',
    { agendamentoId: a.id, servicoId: sv.id, preco: 80, duracaoMin: 60 });
  return { cliente: c, agendamento: a };
}

// Dois de ontem sem desfecho, um de anteontem, e três que NÃO podem aparecer.
const vera   = await marcar('Vera Lima',    ONTEM, '09', 'confirmado');
const bruna  = await marcar('Bruna Alves',  ONTEM, '11', 'pendente');
const carla  = await marcar('Carla Dias',   ANTES, '14', 'confirmado');
await marcar('Já Concluída',  ONTEM, '15', 'concluido');
await marcar('Já Cancelada',  ONTEM, '16', 'cancelado');
await marcar('Muito Antiga',  VELHO, '10', 'confirmado');
await marcar('Ainda Hoje',    HOJE,  '19', 'confirmado');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const p = await (await nav.newContext({ viewport:{ width:1360, height:900 } })).newPage();
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', async d => { await d.accept(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);

const fecho = () => p.evaluate(() => {
  const el = document.getElementById('fechoDoDia');
  return el === null ? null : el.textContent;
});

/* ══════════════════════════════════════════════════════════════════════════
   1. A AGENDA PERGUNTA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) A faixa aparece, com o que precisa de resposta');

verdade('a Agenda TEM onde perguntar', (await fecho()) !== null,
  'não existe #fechoDoDia — a falta continua sem quem a registre');
verdade('e pergunta pelos três atendimentos sem desfecho',
  /3 atendimentos ficaram sem desfecho/.test(await fecho() || ''),
  (await fecho() || '').replace(/\s+/g, ' ').slice(0, 200));

verdade('com o nome de quem era esperada',
  /Vera Lima/.test(await fecho() || '') && /Carla Dias/.test(await fecho() || ''),
  (await fecho() || '').replace(/\s+/g, ' ').slice(0, 300));

/* ⚠ As quatro que NÃO podem estar ali — e cada uma amarrada à faixa ter
   conteúdo. Escritas só como `!/Nome/.test(texto)`, todas passavam com a
   faixa INTEIRA ausente: texto vazio não contém nome nenhum. Quatro verdes
   exatamente no estado que esta suíte existe para reprovar. */
const temFaixa = async () => /sem desfecho/.test(await fecho() || '');
const foraDaFaixa = async (rotulo, quem) =>
  verdade(rotulo, (await temFaixa()) && !new RegExp(quem).test(await fecho() || ''),
    (await fecho() || '').replace(/\s+/g, ' ').slice(0, 200));

await foraDaFaixa('quem já foi concluída não volta a ser perguntada', 'Já Concluída');
await foraDaFaixa('nem quem foi cancelada — cancelar já é um desfecho', 'Já Cancelada');
await foraDaFaixa('o atendimento de HOJE fica fora: o dia ainda não acabou', 'Ainda Hoje');
await foraDaFaixa('e o de nove dias atrás também: lista velha ninguém encara', 'Muito Antiga');

/* ══════════════════════════════════════════════════════════════════════════
   2. A RESPOSTA CHEGA AO BANCO

   É do banco que o relatório e o painel do dia leem. Faixa que muda a tela e
   não grava seria pior que faixa nenhuma: a recepção responderia todo dia e
   os números continuariam iguais.
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) "Veio" e "Não veio" chegam ao banco');

await p.evaluate(id => desfecho(id, 'concluido'), vera.agendamento.id);
await p.waitForTimeout(2200);
await p.evaluate(id => desfecho(id, 'faltou'), bruna.agendamento.id);
await p.waitForTimeout(2200);

const noBanco = async id => (await banco.query(
  `select status from public.agendamentos where id=$1`, [id])).rows[0].status;

igual('quem veio virou concluído no banco',
  await noBanco(vera.agendamento.id), 'concluido');
igual('e quem não veio virou falta',
  await noBanco(bruna.agendamento.id), 'faltou');

verdade('a faixa passa a perguntar só pelo que sobrou',
  /1 atendimento ficou sem desfecho/.test(await fecho() || ''),
  (await fecho() || '').replace(/\s+/g, ' ').slice(0, 200));

/* ══════════════════════════════════════════════════════════════════════════
   3. E A FAIXA SOME QUANDO NÃO HÁ O QUE RESPONDER

   Cartão fixo dizendo "nada pendente" é ruído na tela mais usada do sistema,
   todo dia, para informar que não há nada a fazer.
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) Dia fechado, faixa some');

await p.evaluate(id => desfecho(id, 'concluido'), carla.agendamento.id);
await p.waitForTimeout(2200);
igual('sem pendência, a faixa não ocupa espaço',
  ((await fecho()) || '').trim(), '');

/* ══════════════════════════════════════════════════════════════════════════
   4. E AGORA O AVISO DE FALTA ACENDE

   Este é o ponto do arquivo inteiro. `avisoDeFaltas()` estava escrito desde
   sempre e nunca aparecia, porque ninguém marcava falta. Com o fecho de dia,
   a segunda falta da mesma cliente passa a avisar quem for marcar a próxima.
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) A falta passa a existir para o sistema');

igual('uma falta já conta na ficha da cliente',
  await p.evaluate(cid => faltasDoCliente(cid), bruna.cliente.id), 1);

/* A segunda falta é o limiar do aviso — abaixo dele o sistema não incomoda
   ninguém por um imprevisto. */
const outra = await marcar('Bruna de novo', ANTES, '17', 'confirmado');
await banco.query(`update public.clientes set id=id where id=$1`, [bruna.cliente.id]);
await banco.query(
  `update public.agendamentos set cliente_id=$1 where id=$2`,
  [bruna.cliente.id, outra.agendamento.id]);
await p.evaluate(async () => { const n = await carregarTudo(); if(n){ bd = n; pintar(); } });
await p.waitForTimeout(1500);
await p.evaluate(id => desfecho(id, 'faltou'), outra.agendamento.id);
await p.waitForTimeout(2200);

igual('duas faltas contam duas',
  await p.evaluate(cid => faltasDoCliente(cid), bruna.cliente.id), 2);
verdade('e o aviso que nunca acendia passa a acender',
  /faltou/i.test(await p.evaluate(cid => avisoDeFaltas(cid), bruna.cliente.id)),
  await p.evaluate(cid => avisoDeFaltas(cid), bruna.cliente.id));

secao('5) O console');
igual('nenhum erro de JavaScript', erros.length, 0, erros.join(' | '));

await nav.close();
await banco.query(`delete from public.agendamentos where salao_id=$1`, [SALAO]);
await banco.query(`delete from public.saloes where id=$1`, [SALAO]);
await banco.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações do fecho de dia.`);
