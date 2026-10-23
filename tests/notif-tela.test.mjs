/* ===========================================================================
   AgendaPro — as notificações, do painel até o comportamento do banco

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/notif-tela.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE, SEPARADO DO DE BANCO ─────────────────────
   O `notificacoes.test.mjs` prova que os gatilhos e as cotas funcionam. Ele
   não prova que o dono CONSEGUE mexer neles — e ajuste que só existe no banco
   é ajuste que não existe, porque ninguém vai abrir o SQL Editor do Supabase
   para trocar o lembrete de 2 horas para 24.

   O caminho de um ajuste de notificação tem quatro paradas:

       a tela grava no cfg → o banco lê a chave → o gatilho obedece
       → e recarregar traz de volta o que o dono escolheu

   Esquecer qualquer uma delas falha calado: o dono mexe, vê "Salvo", e nada
   muda. Foi assim que `cartoes` quase foi publicado sem efeito.

   ── E O AVISO QUE NÃO PODE SUMIR ──────────────────────────────────────────
   Enquanto o WhatsApp não estiver conectado, a tela TEM de dizer isso na cara
   de quem está ligando a confirmação. Sem esse aviso, o dono liga, confia, e
   descobre três dias depois que a cliente nunca recebeu nada.
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

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`nt-tela-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju das Notificações',
  telefone:'+5511' + (100000000 + Math.floor(Math.random()*89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Notif ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
await banco.query(
  `update public.assinaturas set plano='salao', status='ativa' where salao_id=$1`,
  [SALAO]);

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let d = 0; d <= 6; d++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:d,
                                   inicio:'08:00', fim:'20:00' });
const sv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:60, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });

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

const abrirNotif = async () => {
  await p.click('#abas .aba[data-chave="salao"]');
  await p.waitForTimeout(1000);
  await p.click('#subAbasSalao button[data-sub="notificacoes"]');
  await p.waitForTimeout(900);
};

/* ══════════════════════════════════════════════════════════════════════════
   1. A TELA EXISTE, E DIZ A VERDADE SOBRE O CANAL
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) A aba de Notificações');

await abrirNotif();

verdade('a aba existe em Meu negócio',
  await p.evaluate(() =>
    !!document.querySelector('.sub-tela[data-sub="notificacoes"].on')),
  'sem a aba, os ajustes só existem no SQL Editor do Supabase');

/* ⚠ O AVISO DIZ O QUE A FILA DIZ. Era fixo — "o WhatsApp ainda não está
   conectado" — e continuou dizendo depois que a conta foi aprovada e as
   mensagens começaram a sair. Salão sem nenhuma mensagem enviada ainda lê
   isso, e o que "pendente" quer dizer; nada de afirmar que está desligado. */
const aviso = await p.textContent('#avisoWhats');
verdade('salão sem mensagem enviada: o aviso diz que nenhuma saiu ainda',
  /Nenhuma mensagem desta agenda saiu/i.test(aviso || ''), aviso);
verdade('dizendo o que pendente quer dizer: ainda não saiu',
  /pendente/i.test(aviso || '') && /não enviada/i.test(aviso || ''), aviso);
verdade('e sem afirmar que o WhatsApp está desligado',
  !/não está conectado/i.test(aviso || ''), aviso);

/* ══════════════════════════════════════════════════════════════════════════
   2. OS PADRÕES DA TELA SÃO OS PADRÕES DO BANCO

   Se divergirem, o dono lê na tela um ajuste que o banco não usa.
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) A tela e o banco começam concordando');

igual('a confirmação vem ligada', await p.isChecked('#nConfirma'), true);
igual('o lembrete vem ligado',    await p.isChecked('#nLembrete'), true);
igual('em 2 horas antes', await p.inputValue('#nLembreteMin'), '120');

/* O resumo é o único que começa desligado, e é decisão: é uma mensagem por
   dia para o dono, todo dia. Ligar isso por conta de uma publicação seria
   mandar mensagem que ninguém pediu e cobrar a cota dele por ela. */
igual('e o resumo do dia vem DESLIGADO', await p.isChecked('#nResumo'), false);

/* "Preciso que apareça lá que é pro cliente": o lembrete da cliente diz de
   quem é, e o do salão é outro, à parte. */
verdade('o lembrete diz que é para o cliente', await p.evaluate(() =>
  /Lembrete para o cliente/.test(document.getElementById('nLembrete').closest('label').innerText)));
igual('o lembrete para o salão existe e vem DESLIGADO',
  await p.isChecked('#nLembEquipe'), false);
igual('desligado, as opções dele nem aparecem', await p.evaluate(() =>
  getComputedStyle(document.getElementById('caixaLembEquipe')).display), 'none');
await p.check('#nLembEquipe');
await p.waitForTimeout(200);
igual('ligando, aparecem: quanto antes e quem recebe', await p.evaluate(() =>
  getComputedStyle(document.getElementById('caixaLembEquipe')).display !== 'none'), true);
igual('com 1 hora antes de padrão', await p.inputValue('#nLembEquipeMin'), '60');
igual('e para quem vai atender', await p.inputValue('#nLembEquipePara'), 'atende');
igual('as três escolhas de quem recebe', JSON.stringify(await p.evaluate(() =>
  [...document.querySelectorAll('#nLembEquipePara option')].map(o => o.value))),
  JSON.stringify(['atende', 'dono', 'ambos']));

igual('o banco concorda sobre o lembrete',
  Number((await banco.query(`select public.lembrete_minutos($1) as m`, [SALAO]))
    .rows[0].m), 120);
igual('e sobre o resumo',
  (await banco.query(`select public.notif_liga($1,'notifResumo',false) as l`,
    [SALAO])).rows[0].l, false);

/* ══════════════════════════════════════════════════════════════════════════
   3. O AJUSTE ATRAVESSA — E MUDA O COMPORTAMENTO, NÃO SÓ O `cfg`
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) Trocar o lembrete muda quando a mensagem sai');

await p.selectOption('#nLembreteMin', '1440');   // 24 horas antes
await p.selectOption('#nLembEquipeMin', '120');
await p.selectOption('#nLembEquipePara', 'ambos');
await p.check('#nResumo');
await p.waitForTimeout(200);
await p.selectOption('#nResumoHora', '7');
await p.selectOption('#nResumoPeriodo', 'manha');
await p.click('button:has-text("Salvar notificações")');
await p.waitForTimeout(2500);

igual('o banco passa a usar 24 horas',
  Number((await banco.query(`select public.lembrete_minutos($1) as m`, [SALAO]))
    .rows[0].m), 1440);
igual('e o resumo passa a estar ligado',
  (await banco.query(`select public.notif_liga($1,'notifResumo',false) as l`,
    [SALAO])).rows[0].l, true);
igual('às 7h', Number((await banco.query(
  `select public.notif_num($1,'notifResumoHora',8) as h`, [SALAO])).rows[0].h), 7);
const lembSalao = (await banco.query(
  `select public.notif_liga($1,'notifLembreteEquipe',false) as l,
          public.notif_num($1,'notifLembreteEquipeMin',60) as m,
          (select cfg->>'notifLembreteEquipePara' from public.saloes where id=$1) as para`,
  [SALAO])).rows[0];
igual('o lembrete para o salão chega ligado ao banco, 2h antes, para os dois',
  JSON.stringify([lembSalao.l, Number(lembSalao.m), lembSalao.para]),
  JSON.stringify([true, 120, 'ambos']));

/* ⚠ E o que importa: um agendamento novo nasce com o lembrete na hora NOVA.
   O `cfg` mudar sem o gatilho obedecer seria o ajuste mais inútil possível. */
const dia4 = maisDias(4);
const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Nara Alves',
  telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });
const ini = `${dia4}T15:00:00${deslocamento(dia4)}`;
const ag = await dona.inserir('agendamentos', { salaoId: SALAO, clienteId: cli.id,
  profissionalId: prof.id, inicio: ini,
  fim: new Date(new Date(ini).getTime() + 36e5).toISOString(),
  status:'confirmado', origem:'recepcao', valorPrevisto: 80 });
await dona.inserir('agendamento_servicos',
  { agendamentoId: ag.id, servicoId: sv.id, preco: 80, duracaoMin: 60 });

const oLembrete = (await banco.query(
  `select quando from public.notificacoes
    where agendamento_id=$1 and tipo='lembrete'`, [ag.id])).rows[0];
const horas = Math.round(
  (new Date(ini).getTime() - new Date(oLembrete.quando).getTime()) / 36e5);
igual('e o gatilho agenda o lembrete 24 horas antes, como o dono pediu',
  horas, 24);

/* ══════════════════════════════════════════════════════════════════════════
   4. RECARREGAR TRAZ O QUE O DONO ESCOLHEU
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) O que foi salvo volta');

await p.reload();
await p.waitForTimeout(4000);
await abrirNotif();

igual('o lembrete volta em 24 horas', await p.inputValue('#nLembreteMin'), '1440');
igual('o resumo volta ligado', await p.isChecked('#nResumo'), true);
igual('na hora escolhida', await p.inputValue('#nResumoHora'), '7');
igual('e no período escolhido', await p.inputValue('#nResumoPeriodo'), 'manha');
igual('o lembrete para o salão volta ligado, 2h, para os dois',
  JSON.stringify([await p.isChecked('#nLembEquipe'), await p.inputValue('#nLembEquipeMin'),
   await p.inputValue('#nLembEquipePara')]), JSON.stringify([true, '120', 'ambos']));

/* Ajuste que não vale não fica na tela pedindo atenção: com o período em
   "dia inteiro", os horários de manhã e tarde somem. */
await p.selectOption('#nResumoPeriodo', 'dia');
await p.waitForTimeout(200);
igual('com "dia inteiro", os horários de manhã e tarde somem da tela',
  await p.evaluate(() =>
    getComputedStyle(document.getElementById('caixaPeriodo')).display), 'none');

/* ══════════════════════════════════════════════════════════════════════════
   5. O HISTÓRICO, E O ESTADO QUE ELE MOSTRA
   ══════════════════════════════════════════════════════════════════════════ */
secao('5) O histórico diz pendente, porque pendente é a verdade');

const hist = await p.textContent('#historicoNotif');
verdade('a mensagem preparada aparece no histórico',
  /Nara Alves/.test(hist || ''), (hist || '').slice(0, 200));
verdade('com o estado pendente, e não "enviado"',
  /pendente/.test(hist || '') && !/enviado/.test(hist || ''),
  (hist || '').slice(0, 300));
verdade('e o tipo diz de quem é o lembrete',
  /Lembrete para o cliente/.test(hist || ''), (hist || '').slice(0, 300));
/* "No meu negócio o lembrete para o cliente está dizendo pendente": era o
   lembrete de um horário de amanhã, esperando a hora dele. Sem o porquê, o
   dono lia "travou". */
verdade('o lembrete de amanhã diz que espera a hora marcada, não só "pendente"',
  /espera a hora marcada/.test(hist || ''), (hist || '').slice(0, 300));

/* Saiu uma mensagem deste salão: o aviso de cima passa a dizer que está
   ligado. (A linha é marcada à mão aqui; quem marca de verdade é o worker.) */
await banco.query(
  `update public.notificacoes set status='enviado', enviado_em=now()
    where id = (select id from public.notificacoes where salao_id=$1
                 and tipo='confirmacao' limit 1)`, [SALAO]);
await abrirNotif();
await p.waitForTimeout(1500);
verdade('com mensagem enviada, o aviso diz que o WhatsApp está ligado',
  /WhatsApp está ligado/.test(await p.textContent('#avisoWhats') || ''),
  await p.textContent('#avisoWhats'));

/* ══════════════════════════════════════════════════════════════════════════
   6. O TELEFONE DE QUEM ATENDE
   ══════════════════════════════════════════════════════════════════════════ */
secao('6) A ficha do profissional');

await p.click('#abas .aba[data-chave="equipe"]');
await p.waitForTimeout(1000);
await p.click('#listaEquipe button:has-text("Editar")');
await p.waitForTimeout(700);

verdade('a ficha tem onde pôr o WhatsApp de quem atende',
  await p.evaluate(() => !!document.getElementById('qTel')),
  'sem isso o aviso de novo agendamento não tem para onde ir');
await p.fill('#qTel', '11988776655');
await p.uncheck('#qNotifResumo');
verdade('a ficha tem a escolha do lembrete antes de cada atendimento, marcada',
  await p.isChecked('#qNotifLembrete'));
await p.uncheck('#qNotifLembrete');
// O rodapé do modal, e não "qualquer botão Salvar": há quatro na página, e
// o primeiro que o seletor larga é o "Salvar dados" de Meu negócio, escondido.
await p.click('#modalPe button:has-text("Salvar")');
await p.waitForTimeout(2500);

const noBanco = (await banco.query(
  `select telefone, notif_novo, notif_resumo, notif_lembrete
     from public.profissionais where id=$1`,
  [prof.id])).rows[0];
igual('o telefone chega ao banco', noBanco.telefone, '11988776655');
igual('e a vontade de cada um também', noBanco.notif_resumo, false);
igual('inclusive a do lembrete antes do atendimento', noBanco.notif_lembrete, false);
igual('sem mexer na outra', noBanco.notif_novo, true);

/* ══════════════════════════════════════════════════════════════════════════
   7. OS MEDIDORES DO PLANO
   ══════════════════════════════════════════════════════════════════════════ */
secao('7) Meu Plano mostra cliente, serviço e mensagem');

await p.click('#abas .aba[data-chave="plano"]');
await p.waitForTimeout(2500);
const doPlano = await p.textContent('#medidoresDoPlano');
verdade('as três barras novas aparecem',
  /Clientes na ficha/.test(doPlano || '')
    && /Serviços no cardápio/.test(doPlano || '')
    && /Mensagens usadas no mês/.test(doPlano || ''), (doPlano || '').slice(0, 200));

/* O número vem do BANCO, não de uma contagem no navegador — e tem de ser o
   MESMO que o gatilho usa para recusar. Dois contadores para a mesma cota é
   como a tela diz "483 de 500" e o cadastro é recusado. */
verdade('e o número de clientes bate com o do banco',
  new RegExp((await banco.query(
    `select count(*)::int as n from public.clientes where salao_id=$1`,
    [SALAO])).rows[0].n + ' de ').test(doPlano || ''),
  (doPlano || '').slice(0, 200));

/* ══════════════════════════════════════════════════════════════════════════
   7b. O MESMO CONTADOR ONDE SE LIGAM AS MENSAGENS

   É em Mensagens da agenda que o dono decide ligar o lembrete para o salão
   ou o resumo — e é ali que ele precisa ver quanto já gastou, e o que para
   primeiro quando a franquia está no fim (22_cotas, 2b).
   ══════════════════════════════════════════════════════════════════════════ */
secao('7b) O contador em Mensagens da agenda');

const consumo = async () => {
  await abrirNotif();
  await p.waitForTimeout(1500);
  return (await p.textContent('#consumoMensagens')) || '';
};
const gastarTela = (n, de) => banco.query(
  `insert into public.notificacoes
     (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
   select $1, 'lembrete', '11999', now(), 'x', 'tela-gasto:' || g, 'enviado', now()
     from generate_series($2::int + 1, $2::int + $3::int) g`, [SALAO, de, n]);

/* O mês das mensagens conta do dia da assinatura (22, `ciclo_mensagens`):
   vencendo daqui a 10 dias, a franquia renova nesse dia — e é ele que a tela
   tem de dizer, e não "quando virar o mês". */
const RENOVA = (await banco.query(
  `update public.assinaturas
      set vence_em = (now() at time zone 'America/Sao_Paulo')::date + 10
    where salao_id=$1
   returning to_char(vence_em, 'DD/MM') as d`, [SALAO])).rows[0].d;
let c = await consumo();
verdade('diz o dia em que a franquia renova: o do vencimento da assinatura',
  new RegExp('renova em\\s+' + RENOVA).test(c), c.slice(0, 300));
verdade('mostra o que já saiu no mês, com o número do banco (1 de 3600)',
  /Mensagens deste mês/.test(c) && /1 de 3600/.test(c), c.slice(0, 200));
verdade('e explica que as últimas ficam para o cliente',
  /usam até 3240/.test(c) && /360\s+ficam guardadas para o cliente/.test(c), c.slice(0, 300));
verdade('folgado, sem aviso de limite', !/pararam|acabaram|próximo do limite/.test(c), c);

await gastarTela(3239, 0);                       // 1 + 3239 = 3240, a marca dos 90%
c = await consumo();
verdade('aos 90%, diz que as do salão pararam',
  /As mensagens para o salão pararam/.test(c), c.slice(0, 300));
verdade('e quantas sobram para o cliente', /360 que faltam/.test(c), c.slice(0, 300));
verdade('e que voltam no dia da renovação, não "quando virar o mês"',
  new RegExp('voltam em ' + RENOVA).test(c) && !/virar o mês/.test(c), c.slice(0, 400));

await gastarTela(360, 3239);                     // 3600, o teto
c = await consumo();
verdade('no teto, diz que acabaram — inclusive para o cliente',
  /acabaram/.test(c) && /nem para o cliente/.test(c), c.slice(0, 300));
verdade('até o dia da renovação',
  new RegExp('até ' + RENOVA + ', quando a franquia renova').test(c), c.slice(0, 400));

await p.click('#abas .aba[data-chave="plano"]');
await p.waitForTimeout(2500);
verdade('e Meu Plano diz o mesmo',
  /acabaram/.test((await p.textContent('#medidoresDoPlano')) || ''));

secao('8) O console');
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
console.log(`✓ ${passou} verificações das notificações na tela.`);
