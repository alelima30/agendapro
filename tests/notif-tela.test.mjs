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

verdade('a aba existe em Meu salão',
  await p.evaluate(() =>
    !!document.querySelector('.sub-tela[data-sub="notificacoes"].on')),
  'sem a aba, os ajustes só existem no SQL Editor do Supabase');

const aviso = await p.textContent('#avisoWhats');
verdade('e avisa, na cara de quem liga, que o WhatsApp não está conectado',
  /não está conectado/i.test(aviso || ''), aviso);
verdade('dizendo o que acontece nesse meio-tempo: fica pendente',
  /pendente/i.test(aviso || ''), aviso);

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
// O rodapé do modal, e não "qualquer botão Salvar": há quatro na página, e
// o primeiro que o seletor larga é o "Salvar dados" de Meu salão, escondido.
await p.click('#modalPe button:has-text("Salvar")');
await p.waitForTimeout(2500);

const noBanco = (await banco.query(
  `select telefone, notif_novo, notif_resumo from public.profissionais where id=$1`,
  [prof.id])).rows[0];
igual('o telefone chega ao banco', noBanco.telefone, '11988776655');
igual('e a vontade de cada um também', noBanco.notif_resumo, false);
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
    && /Mensagens no mês/.test(doPlano || ''), (doPlano || '').slice(0, 200));

/* O número vem do BANCO, não de uma contagem no navegador — e tem de ser o
   MESMO que o gatilho usa para recusar. Dois contadores para a mesma cota é
   como a tela diz "483 de 500" e o cadastro é recusado. */
verdade('e o número de clientes bate com o do banco',
  new RegExp((await banco.query(
    `select count(*)::int as n from public.clientes where salao_id=$1`,
    [SALAO])).rows[0].n + ' de ').test(doPlano || ''),
  (doPlano || '').slice(0, 200));

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
