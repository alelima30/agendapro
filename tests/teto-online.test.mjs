/* ===========================================================================
   AgendaPro — o link público não enche a agenda do salão

     bash tests/bancada/subir.sh
     node tests/teto-online.test.mjs

   ── O QUE FOI MEDIDO ANTES DE ESTE ARQUIVO EXISTIR ─────────────────────────
   Numa análise do agendamento, com a bancada de pé e SÓ a chave publicável —
   a mesma que está à vista no config.js, e que está certa ali, porque quem
   protege é o RLS:

       horários que o link oferece para amanhã: 45
         telefone 11910000000: marcou 3 · "Você já tem 3 horários marcados"
         telefone 11910000001: marcou 3 · "Você já tem 3 horários marcados"
         telefone 11910000002: marcou 3 · "Você já tem 3 horários marcados"
         telefone 11910000003: marcou 3 · "Você já tem 3 horários marcados"
       marcados: 12 com 4 telefones · horários restantes: 0 (eram 45)

   Quatro telefones inventados fecharam o dia inteiro de uma profissional em
   menos de um minuto. O freio de "3 horários abertos" existe e funciona — só
   que conta por FICHA, e a ficha nasce do telefone que a pessoa digitou.
   Telefone novo, ficha nova, freio zerado.

   ── O NÚMERO FIXO QUE ESTE TESTE DERRUBOU ──────────────────────────────────
   O primeiro desenho era um teto de 20 marcações por salão por dia. Este
   arquivo reprovou na cara: as 12 marcações acima JÁ ERAM o dia inteiro. Numa
   jornada de 08:00 às 20:00 com serviço de uma hora cabem doze pessoas — um
   teto de vinte nunca chega a valer, e um de dez estraga o dia de um salão
   movimentado. Não existe número fixo certo, porque "o dia" tem tamanho
   diferente em cada salão.

   ── O QUE ESTE ARQUIVO EXIGE ───────────────────────────────────────────────
   Dois limites que ANDAM COM A AGENDA, cada um provado SOZINHO — com o outro
   solto, senão não dá para saber qual dos dois trabalhou:

     reserva do balcão   o link nunca ocupa a agenda inteira de alguém
     freio de rajada     doze marcações num minuto não é gente marcando

   E as três coisas que os tornam úteis em vez de estorvo: a recepção continua
   marcando sem limite nenhum, quem desmarca devolve a cadeira E a cota, e a
   janela da rajada ANDA — freio que não solta é portão trancado.

   ⚠ ISTO NÃO É A SOLUÇÃO, É O CURATIVO. Sem provar que o telefone é de quem
   digitou, dá para encarecer o estrago e não dá para impedi-lo. A solução é o
   código por WhatsApp, que depende da verificação na Meta.
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
const tel = () => '+5511' + (100000000 + Math.floor(Math.random()*89999999));

const dona = novaAba();
await dona.criarConta({ email:`teto-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju do Teto', telefone: tel() });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Teto ' + marca,
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
await dona.atualizar('profissionais', prof.id, { ativo:true, aceitaOnline:true });
for(let d = 0; d <= 6; d++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:d,
                                   inicio:'08:00', fim:'20:00' });
const sv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:60, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });

const AMANHA = maisDias(1);

/* Sem sessão, sem login: exatamente como uma desconhecida com o link na mão.
   `fetch` cru de propósito — passar pelo `Dados` daria a impressão de que o
   caminho exige alguma coisa que ele não exige. */
async function livres(dia = AMANHA){
  const r = await fetch(BASE + '/rest/v1/rpc/horarios_livres', {
    method:'POST', headers:{ apikey:'k', 'Content-Type':'application/json' },
    body: JSON.stringify({ p_profissional: prof.id, p_data: dia,
                           p_servicos:[sv.id] }) });
  if(!r.ok) return [];
  const j = await r.json();
  return (Array.isArray(j) ? j : [j])
    .map(x => (x && typeof x === 'object')
      ? (x.horarios_livres ?? Object.values(x)[0]) : x)
    .filter(Boolean).flat();
}

async function marcar(inicio, nome, telefone){
  const r = await fetch(BASE + '/rest/v1/rpc/agendar', {
    method:'POST', headers:{ apikey:'k', 'Content-Type':'application/json' },
    body: JSON.stringify({ p_profissional: prof.id, p_inicio: inicio,
      p_servicos:[sv.id], p_nome: nome, p_telefone: telefone }) });
  if(r.ok) return { ok:true };
  const t = await r.text();
  let msg = t;
  try{ msg = JSON.parse(t).message || t; }catch(e){}
  return { ok:false, erro: msg };
}

/* Enche até o link parar de aceitar, trocando de telefone a cada recusa por
   ficha. Devolve quantas marcações entraram e por que parou. */
async function encher(teto = 40){
  let feitos = 0, ultimo = null;
  for(let t = 0; t < teto; t++){
    const telefone = '119' + String(20000000 + t + Math.floor(Math.random()*1000))
      .padStart(8, '0');
    for(;;){
      const l = await livres();
      if(!l.length){ ultimo = 'acabaram os horários oferecidos'; break; }
      const r = await marcar(l[0], 'Fulano ' + t, telefone);
      if(!r.ok){ ultimo = r.erro; break; }
      feitos++;
    }
    if(!(await livres()).length) break;
  }
  return { feitos, ultimo };
}

/* O deslocamento do fuso do salão, para montar um instante sem depender do
   que o link está oferecendo — que é justamente o que os limites mexem. */
const desl = deslocamento(AMANHA);
const instante = (dia, hora) => `${dia}T${hora}:00${desl}`;

// A agenda de verdade, do ponto de vista do SALÃO: quanto do dia está livre.
const livreNaCasa = async (dia = AMANHA) => {
  const r = await banco.query(
    `select public.minutos_de_jornada($1,$2::date)
            - coalesce((select sum(extract(epoch from (a.fim - a.inicio))/60)
                          from public.agendamentos a
                         where a.profissional_id = $1
                           and a.arquivado_em is null
                           and a.status in ('pendente','confirmado','em_atendimento','concluido')
                           and (a.inicio at time zone 'America/Sao_Paulo')::date = $2::date), 0)
            as m`, [prof.id, dia]);
  return Number(r.rows[0].m);
};

const cfgAtual = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
const ajustar = async o => dona.atualizar('saloes', SALAO,
  { cfg: Object.assign({}, await cfgAtual(), o) });

// A frase que o link dá quando recusa — pedida direto, sem depender da oferta.
const porqueNao = async (dia = AMANHA) => (await banco.query(
  `select public.porque_nao_agenda($1, $2::date, array[$3]::uuid[]) as m`,
  [prof.id, dia, sv.id])).rows[0].m;

/* ══════════════════════════════════════════════════════════════════════════
   1. COM TUDO NO PADRÃO, O DIA NÃO ENCHE MAIS

   O ataque medido: telefone descartável a cada três marcações, até o link
   parar. Antes ele parava no fim da agenda — 45 horários viravam 0.
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) Telefones descartáveis contra o dia de uma profissional');

const oferecidos = (await livres()).length;
verdade(`o link oferece ${oferecidos} horários para amanhã`, oferecidos >= 10,
  String(oferecidos));

/* A jornada é 08:00–20:00 e o serviço tem uma hora: cabem DOZE atendimentos.
   Este número está escrito aqui porque foi ele que reprovou o primeiro
   desenho deste teto — um limite fixo de 20 nunca chegaria a valer num dia
   que só tem doze cadeiras. */
const jornadaMin = Number((await banco.query(
  `select public.minutos_de_jornada($1, $2::date) as m`,
  [prof.id, AMANHA])).rows[0].m);
igual('a jornada de amanhã tem 12 horas', jornadaMin, 720);

const cheia = await encher();
console.log(`      (entraram ${cheia.feitos}; parou em: ${cheia.ultimo})`);

verdade('o link NÃO leva o dia inteiro', cheia.feitos < 12,
  `entraram ${cheia.feitos} de 12 cadeiras`);
verdade('e a agenda continua com espaço de sobra', (await livreNaCasa()) >= 60,
  `sobraram ${await livreNaCasa()} minutos de ${jornadaMin}`);

/* ══════════════════════════════════════════════════════════════════════════
   2. A RESERVA DO BALCÃO, SOZINHA

   Com o freio de rajada solto, quem para o link é só a reserva — e é essa
   separação que prova qual dos dois limites está fazendo o trabalho.
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) A reserva do balcão, medida em minutos');

igual('a reserva padrão deixa o link com 70% do dia',
  Number((await banco.query(`select public.teto_online_pct($1) as p`, [SALAO]))
    .rows[0].p), 70);

await ajustar({ tetoOnlineRajada: 90 });
const soReserva = await encher();
console.log(`      (entraram mais ${soReserva.feitos}; parou em: ${soReserva.ultimo})`);

const ocupado = Number((await banco.query(
  `select public.minutos_online_no_dia($1, $2::date) as m`,
  [prof.id, AMANHA])).rows[0].m);
verdade('o link enche até a reserva e para',
  ocupado > 0 && ocupado <= jornadaMin * 0.70,
  `o link ocupou ${ocupado} min de ${jornadaMin} (limite ${jornadaMin * 0.7})`);
verdade('e não para cedo demais: usou mais da metade do que podia',
  ocupado >= jornadaMin * 0.35,
  `${ocupado} min — reserva frouxa demais seria um limite que não limita`);

verdade('a recusa manda a pessoa para onde tem gente',
  /WhatsApp/i.test(await porqueNao() || ''), JSON.stringify(await porqueNao()));
verdade('e não conta o mecanismo para quem está do outro lado',
  !/(teto|limite|cota|reserva|%)/i.test(await porqueNao() || ''),
  JSON.stringify(await porqueNao()));

/* ══════════════════════════════════════════════════════════════════════════
   3. O BALCÃO NÃO TEM RESERVA — A RESERVA É CONTRA O LINK
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) A recepção marca na parte guardada');

/* Se a reserva pegasse no painel, um dia cheio de marcação pela internet
   deixaria a recepção sem poder anotar quem ligou — exatamente o contrário
   do que ela existe para fazer. O horário abaixo é montado por fuso, e não
   tirado da oferta do link: a oferta é o que os limites mexem. */
const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Dona Marta',
  telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });

let doBalcao = null;
for(const h of ['19','18','17','16','15']){
  try{
    doBalcao = await dona.inserir('agendamentos', { salaoId: SALAO,
      clienteId: cli.id, profissionalId: prof.id,
      inicio: instante(AMANHA, h), fim: instante(AMANHA, String(+h + 1)),
      status:'confirmado', origem:'recepcao', valorPrevisto: 80 });
    break;
  }catch(e){ doBalcao = { erro: e.message }; }
}
verdade('a recepção marca no que o link não alcança',
  !!(doBalcao && doBalcao.id), JSON.stringify(doBalcao));

/* E o que o balcão marcou não come a cota do link: a reserva conta só o que
   veio pela internet. Contar tudo faria um dia cheio de telefonema fechar o
   link — punindo o salão pelo próprio movimento. */
igual('e o que a recepção marcou não entra na conta do link',
  Number((await banco.query(
    `select public.minutos_online_no_dia($1, $2::date) as m`,
    [prof.id, AMANHA])).rows[0].m), ocupado);

/* ══════════════════════════════════════════════════════════════════════════
   4. O FREIO DE RAJADA, SOZINHO

   Agora ao contrário: reserva desligada (100%), rajada no padrão. Um dia
   inteiramente livre pela frente e o link mesmo assim segura.
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) Doze marcações num minuto não é gente marcando');

/* Reserva desligada (100%) para o dia não ser quem para: aqui só o freio de
   rajada pode falar. E a rajada é montada AQUI, com telefones novos num dia
   lá na frente — depender de sobra das seções acima faria esta seção passar
   ou reprovar pelo que as outras deixaram, que não é medir nada. */
await ajustar({ tetoOnlinePct: 100, tetoOnlineRajada: 10 });
igual('o freio padrão são 10 pessoas novas em 10 minutos',
  Number((await banco.query(`select public.teto_online_rajada($1) as r`, [SALAO]))
    .rows[0].r), 10);

const longe = maisDias(5);
verdade('o dia lá na frente está vazio', (await livreNaCasa(longe)) === 720,
  String(await livreNaCasa(longe)));

let entraram = 0, recusa = null;
for(let i = 0; i < 25; i++){
  const l = await livres(longe);
  if(!l.length){ recusa = 'acabaram os horários'; break; }
  const r = await marcar(l[0], 'Desconhecida ' + i,
    '119' + String(70000000 + i).padStart(8, '0'));
  if(!r.ok){ recusa = r.erro; break; }
  entraram++;
}
console.log(`      (entraram ${entraram} desconhecidas; parou em: ${recusa})`);

/* O contador da janela é do SALÃO, e as seções acima já marcaram nele. O que
   importa não é quantas entraram AQUI, e sim que o freio tenha disparado com
   dia livre pela frente — medido pelo contador e pela frase, não por uma
   contagem local que dependeria do que sobrou lá de cima. */
verdade('o contador da janela chegou ao teto',
  Number((await banco.query(`select public.rajada_online($1) as n`, [SALAO]))
    .rows[0].n) >= 10,
  'entraram ' + entraram + ' nesta seção; parou em: ' + recusa);
verdade('e o link recusa com dia livre pela frente',
  /congestionada/i.test(await porqueNao(longe) || ''),
  JSON.stringify(await porqueNao(longe)));
verdade('sem ter enchido a agenda: sobra dia de sobra',
  (await livreNaCasa(longe)) >= 600,
  `sobraram ${await livreNaCasa(longe)} minutos de 720`);

/* ⚠ O CONTADOR SÓ ENXERGA QUEM O SALÃO NUNCA ATENDEU.

   A primeira versão contava toda marcação online da janela, com teto de
   cinco — e reprovou a suíte de auditoria inteira com "congestionada". A
   reprova não era do teste: era o retrato do dia bom do salão. O dono publica
   um story, oito clientes remarcam em dez minutos, e o freio manda todas
   embora.

   Contando só ficha NOVA, uma correria de gente conhecida não enche o
   contador e nunca aciona o freio.

   O que isto NÃO quer dizer — e o teste diz de propósito, para ninguém se
   iludir lendo depois: quando o freio DISPARA, ele segura o link para todo
   mundo por até dez minutos, conhecida inclusive. `porque_nao_agenda()`
   responde sobre o dia e o profissional, e não sabe quem está do outro lado. */
await banco.query(
  `update public.agendamentos set criado_em = now() - interval '2 hours'
    where salao_id = $1 and origem = 'online'`, [SALAO]);
igual('zerando a janela para medir a outra metade sozinha',
  Number((await banco.query(`select public.rajada_online($1) as n`, [SALAO]))
    .rows[0].n), 0);

// Uma turma de clientes CONHECIDAS marcando em rajada.
const conhecidas = [];
for(let i = 0; i < 12; i++){
  const t = '1195544' + String(3300 + i);
  const c = await dona.inserir('clientes', { salaoId: SALAO,
    nome:'Cliente de Sempre ' + i, telefone: t });
  await banco.query(
    `update public.clientes set criado_em = now() - interval '200 days' where id=$1`,
    [c.id]);
  conhecidas.push(t);
}
let entraramConhecidas = 0, recusaConhecida = null;
for(const t of conhecidas){
  const l = await livres(longe);
  if(!l.length){ recusaConhecida = 'o link parou de oferecer'; break; }
  const r = await marcar(l[0], 'Cliente de Sempre', t);
  if(!r.ok){ recusaConhecida = r.erro; break; }
  entraramConhecidas++;
}
console.log(`      (entraram ${entraramConhecidas} conhecidas; parou em: ${recusaConhecida})`);

/* O que prova a regra não é QUANTAS entraram — o dia acaba, e acabar é
   diferente de ser freado. É que nenhuma delas tenha levado "congestionada",
   com o contador parado em zero o tempo todo. */
verdade('nenhuma conhecida foi freada, por mais rápido que marcassem',
  !/congestionada/i.test(recusaConhecida || '') && entraramConhecidas >= 8,
  `entraram ${entraramConhecidas}; parou em: ${recusaConhecida}`);
igual('porque nenhuma delas entra na conta',
  Number((await banco.query(`select public.rajada_online($1) as n`, [SALAO]))
    .rows[0].n), 0);

/* A rajada é uma janela que ANDA. Empurrando o que este teste marcou para
   fora dos dez minutos, o link volta a atender — senão isto não seria um
   freio, seria um portão trancado. */
await banco.query(
  `update public.agendamentos set criado_em = now() - interval '2 hours'
    where salao_id = $1 and origem = 'online'`, [SALAO]);
igual('passados os dez minutos, a janela esvazia',
  Number((await banco.query(`select public.rajada_online($1) as n`, [SALAO]))
    .rows[0].n), 0);
/* Num dia que ninguém tocou: o `longe` acabou de encher, e perguntar por ele
   traria a reserva de volta — outra recusa, por outro motivo, que não é o que
   esta linha mede. */
igual('e o link volta a aceitar', await porqueNao(maisDias(6)), null);

/* ══════════════════════════════════════════════════════════════════════════
   5. O DONO MANDA NOS DOIS NÚMEROS
   ══════════════════════════════════════════════════════════════════════════ */
secao('5) Os limites são ajuste do salão, não número meu');

igual('quem só trabalha com link põe 100 e desliga a reserva',
  Number((await banco.query(`select public.teto_online_pct($1) as p`, [SALAO]))
    .rows[0].p), 100);

/* Número fora da escala não vira limite fora da escala: o mesmo cuidado que
   o `dias_liberados()` tem com o 365. */
await ajustar({ tetoOnlinePct: 0, tetoOnlineRajada: 99999 });
igual('reserva abaixo do mínimo é aparada em 10%',
  Number((await banco.query(`select public.teto_online_pct($1) as p`, [SALAO]))
    .rows[0].p), 10);
igual('e rajada absurda é aparada em 100',
  Number((await banco.query(`select public.teto_online_rajada($1) as r`, [SALAO]))
    .rows[0].r), 100);

/* ══════════════════════════════════════════════════════════════════════════
   6. CANCELAR DEVOLVE A CADEIRA E A COTA
   ══════════════════════════════════════════════════════════════════════════ */
secao('6) Quem desmarca não fica devendo');

/* A reserva mede OCUPAÇÃO. Se contasse chamadas, uma cliente que desmarcou e
   remarcou no mesmo dia gastaria duas vezes a cota do salão — e a casa
   perderia agenda por causa de quem se organizou. */
const antesDoCancel = Number((await banco.query(
  `select public.minutos_online_no_dia($1, $2::date) as m`,
  [prof.id, AMANHA])).rows[0].m);
/* Do dia MEDIDO, e não qualquer uma: as seções acima marcaram noutros dias,
   e cancelar uma delas não mexeria no número que esta seção confere — a
   verificação passaria a comparar 480 com 480 e reprovaria falando de
   estorno de cota, que não seria o que houve. */
await banco.query(
  `update public.agendamentos set status='cancelado'
    where id in (select a.id from public.agendamentos a
                  join public.saloes s on s.id = a.salao_id
                 where a.salao_id=$1 and a.origem='online'
                   and a.status in ('pendente','confirmado')
                   and (a.inicio at time zone coalesce(s.fuso,'America/Sao_Paulo'))::date
                       = $2::date
                 limit 1)`, [SALAO, AMANHA]);
const depoisDoCancel = Number((await banco.query(
  `select public.minutos_online_no_dia($1, $2::date) as m`,
  [prof.id, AMANHA])).rows[0].m);
verdade('a marcação cancelada sai da conta da reserva',
  depoisDoCancel < antesDoCancel,
  `antes ${antesDoCancel} min, depois ${depoisDoCancel} min`);


/* ══════════════════════════════════════════════════════════════════════════
   7. E O DONO ALCANÇA OS DOIS NÚMEROS

   Ajuste que só existe no banco é ajuste que não existe: ninguém vai abrir o
   SQL Editor do Supabase para guardar 30% da própria agenda. E ajuste que a
   tela grava mas o banco ignora é pior ainda — a pessoa mexe, vê "Salvo", e
   nada muda.

   Então o caminho inteiro, num navegador de verdade: a tela mostra o padrão,
   o dono troca, o BANCO passa a usar o número novo, e recarregar traz de
   volta o que ele escolheu — não o padrão outra vez.
   ══════════════════════════════════════════════════════════════════════════ */
secao('7) Os dois números, do painel até o banco');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const errosJs = [];
const pg2 = await (await nav.newContext({ viewport:{ width:1360, height:900 } })).newPage();
pg2.on('pageerror', e => errosJs.push(e.message));
pg2.on('dialog', d => d.accept());
await pg2.addInitScript(([b, ss]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ss));
}, [BASE, dona.sessao()]);
await pg2.goto(BASE + '/app.html');
await pg2.waitForTimeout(4000);
await pg2.click('#abas .aba[data-chave="salao"]');
await pg2.waitForTimeout(1200);

/* Este salão já teve os dois mexidos lá em cima (10 e 100, os aparados).
   A tela tem que mostrar O QUE O SALÃO TEM, e não o primeiro item da lista —
   senão o Salvar seguinte trocaria o ajuste do dono sem ninguém pedir. */
igual('a tela abre com a reserva que o salão realmente tem',
  await pg2.inputValue('#cTetoPct'), '10');
igual('e com a rajada que ele realmente tem',
  await pg2.inputValue('#cTetoRajada'), '100');

await pg2.selectOption('#cTetoPct', '85');
await pg2.selectOption('#cTetoRajada', '10');
await pg2.waitForTimeout(200);
verdade('a explicação fala em cadeiras, não em porcentagem',
  /8 e 2 ficam/.test(await pg2.textContent('#explicaTeto')),
  await pg2.textContent('#explicaTeto'));

await pg2.click('button:has-text("Salvar dados")');
await pg2.waitForTimeout(2500);

const depoisDeSalvar = (await banco.query(
  `select public.teto_online_pct($1) as pct, public.teto_online_rajada($1) as raj,
          cfg->>'diasLiberados' as dias from public.saloes where id = $1`,
  [SALAO])).rows[0];
igual('o banco passa a usar a reserva escolhida', Number(depoisDeSalvar.pct), 85);
igual('e a rajada escolhida', Number(depoisDeSalvar.raj), 10);
/* `cfg` é jsonb compartilhado: gravar dois campos não pode apagar os
   vizinhos. Foi assim que a janela da agenda quase sumiu. */
igual('sem levar junto a janela da agenda', depoisDeSalvar.dias, '30');

await pg2.reload();
await pg2.waitForTimeout(4000);
await pg2.click('#abas .aba[data-chave="salao"]');
await pg2.waitForTimeout(1200);
igual('e recarregar traz o que o dono escolheu, não o padrão',
  await pg2.inputValue('#cTetoPct'), '85');

igual('nenhum erro de JavaScript no caminho', errosJs.length, 0,
  errosJs.join(' | '));
await nav.close();

/* Os agendamentos primeiro. `agendamento_servicos.servico_id` é `on delete
   restrict` de propósito — serviço com horário marcado não some do catálogo —
   e isso faz o cascade do salão esbarrar em si mesmo se a ordem for a de
   sempre. */
await banco.query(`delete from public.agendamentos where salao_id=$1`, [SALAO]);
await banco.query(`delete from public.saloes where id=$1`, [SALAO]);
await banco.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações do teto do link público.`);
