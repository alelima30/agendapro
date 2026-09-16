/* ===========================================================================
   AgendaPro — pacotes: quem paga zero, e quem não paga

     bash tests/bancada/subir.sh
     node tests/pacotes.test.mjs

   ── O QUE O PACOTE É ───────────────────────────────────────────────────────
   O salão cria "Pacote Unha em Dia": 4 manutenções, 90 dias de validade, de
   segunda a quarta. Vincula a Maria. A Maria, LOGADA, marca manutenção pelo
   link e o atendimento sai por R$ 0,00 — ela já pagou o pacote.

   ── ⚠ E A LINHA QUE SEPARA DESCONTO DE ROMBO ──────────────────────────────
   O benefício exige LOGIN. Sem conta, a ficha é achada pelo TELEFONE, e o
   `ficha_do_cliente()` diz, no próprio código, que sem SMS não existe prova de
   que o número seja de quem digitou.

   Sem essa exigência, qualquer pessoa que soubesse o telefone da Maria
   marcaria de graça no lugar dela, e o salão só descobriria com a cliente
   sentada na cadeira. É a seção 3 daqui, e é a razão de este arquivo existir.

   ── E O PREÇO É DO BANCO ──────────────────────────────────────────────────
   A tela não manda valor nenhum: o `agendar()` calcula. Um teste que só
   olhasse a tela não distinguiria "o banco deu o desconto" de "o navegador
   disse que era zero" — que é exatamente a diferença que interessa.
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

// ── O salão, com a dona ────────────────────────────────────────────────────
const dona = novaAba();
await dona.criarConta({ email:`pac-dona-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona do Salão', telefone: tel(1) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Pacote ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
/* ⚠ O FREIO DE RAJADA E O TETO DO LINK, AFROUXADOS SÓ AQUI.

   O salão protege a agenda de duas formas: o link não pode tomar mais que uma
   fatia do dia (`tetoOnlinePct`) e não pode marcar muitas vezes seguidas
   (`tetoOnlineRajada`). As duas são certas, e as duas barram este arquivo —
   que marca dezenas de horários em segundos, coisa que cliente nenhuma faz.

   Afrouxar aqui é isolar a variável: sem isto, uma falha do PACOTE apareceria
   como "a marcação está congestionada", e eu passaria a tarde procurando no
   lugar errado. As duas travas têm suíte própria (`teto-online.test.mjs`).

   ⚠ E é `cfg` inteiro de propósito: o salão nasce sem nenhuma dessas chaves, e
   um `Object.assign` aqui esconderia o dia em que o padrão mudasse. */
await dona.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:60, tetoOnlinePct:100, tetoOnlineRajada:100 } });

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'20:00' });
}
const manutencao = await dona.inserir('servicos', { salaoId:SALAO,
  nome:'Manutenção de unha', preco:40, duracaoMin:60, intervaloMin:0,
  ativo:true, aceitaOnline:true });
const escova = await dona.inserir('servicos', { salaoId:SALAO, nome:'Escova',
  preco:50, duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });
ok('salão com dois serviços: manutenção (R$ 40) e escova (R$ 50)');

/* O pacote cobre TODOS os dias nesta montagem. Os dias da semana têm seção
   própria (5) — misturá-los aqui faria uma falha de "cobre o serviço" parecer
   falha de "vale hoje", e vice-versa. */
const pacote = await dona.inserir('pacotes', { salaoId:SALAO,
  nome:'Unha em Dia', preco:140, sessoes:4, validadeDias:90,
  dias:[0,1,2,3,4,5,6], ativo:true });
await dona.inserir('pacote_servicos',
  { pacoteId: pacote.id, servicoId: manutencao.id });
ok('pacote criado: 4 sessões, 90 dias, cobrindo só a manutenção');

// ── A Maria, com conta ─────────────────────────────────────────────────────
const maria = novaAba();
const TEL_MARIA = tel(2);
await maria.criarConta({ email:`pac-maria-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Maria Pacote', telefone: TEL_MARIA });

/* A ficha nasce da primeira marcação — é assim que o sistema funciona, e
   montar a ficha por fora criaria um estado que a vida real não produz. */
const soDigitos = t => String(t).replace(/\D/g, '');
const daquiA = (dias, hora) => {
  const d = new Date(Date.now() + dias * 864e5);
  d.setUTCHours(hora, 0, 0, 0);
  return d.toISOString();
};
const marcar = (quem, servicos, quando, nome, telefone) => quem.chamar('agendar', {
  p_profissional: prof.id, p_inicio: quando, p_servicos: servicos,
  p_nome: nome, p_telefone: telefone });

/* ⚠ A TRAVA DOS 3 HORÁRIOS ABERTOS É REAL, e este arquivo esbarrou nela.

   O `agendar()` recusa a quarta marcação em aberto da mesma cliente. Faz
   sentido no salão — evita quem marca cinco horários "para decidir depois" —
   e obriga o teste a limpar atrás de si.

   São dois jeitos de limpar, e a diferença IMPORTA para o que está sendo
   medido:

   · `atender()` marca como concluído: libera a vaga na trava dos 3 E MANTÉM a
     sessão do pacote gasta, porque `concluido` conta como sessão usada. É o
     que acontece de verdade quando a cliente vem.
   · `desmarcar()` cancela: libera a vaga E DEVOLVE a sessão.

   Usar cancelar onde deveria ser concluir faria as sessões nunca acabarem, e
   a seção 4 mediria o oposto do que diz medir. */
const atender   = id => dona.atualizar('agendamentos', id, { status:'concluido' });
const desmarcar = id => dona.atualizar('agendamentos', id, { status:'cancelado' });

const primeira = await marcar(maria, [manutencao.id], daquiA(3, 13),
  'Maria Pacote', TEL_MARIA);
igual('sem pacote ainda, a manutenção custa os R$ 40',
  Number(primeira[0].valor), 40);
await desmarcar(primeira[0].id);

const fichaMaria = (await dona.lista('clientes', { salaoId: SALAO }))
  .find(c => soDigitos(c.telefone) === soDigitos(TEL_MARIA));
verdade('a ficha da Maria existe', !!fichaMaria,
  'sem ficha não há a quem vincular o pacote');

/* ══════════════════════════════════════════════════════════════════════════
   1 — VINCULADA, ELA PAGA ZERO
   ══════════════════════════════════════════════════════════════════════════ */
secao('A dona vincula a Maria ao pacote');

const venda = await dona.chamar('vender_pacote',
  { p_pacote: pacote.id, p_cliente: fichaMaria.id });
const VENDA = Array.isArray(venda) ? venda[0] : venda;
verdade('a venda devolve o vínculo', !!VENDA, JSON.stringify(venda));

const segunda = await marcar(maria, [manutencao.id], daquiA(4, 13),
  'Maria Pacote', TEL_MARIA);
igual('agora a manutenção sai por R$ 0,00', Number(segunda[0].valor), 0);
await atender(segunda[0].id);          // veio, foi atendida: a sessão foi

const meus = await maria.chamar('meus_pacotes', { p_salao: SALAO });
const MEU = (Array.isArray(meus) ? meus : [])[0] || {};
igual('e ela vê o próprio pacote no link', MEU.nome, 'Unha em Dia');
/* 4 sessões, uma usada pela marcação de agora. A primeira marcação foi ANTES
   do vínculo e não pode contar — se contasse, vender um pacote descontaria
   sessões de atendimentos já pagos. */
igual('com 3 sessões restantes — a marcação de antes do vínculo não conta',
  Number(MEU.restantes), 3);

/* ══════════════════════════════════════════════════════════════════════════
   2 — O PACOTE COBRE O QUE COBRE, E SÓ
   ══════════════════════════════════════════════════════════════════════════ */
secao('Serviço de fora do pacote');

const comEscova = await marcar(maria, [escova.id], daquiA(5, 13),
  'Maria Pacote', TEL_MARIA);
igual('a escova, que não está no pacote, custa os R$ 50',
  Number(comEscova[0].valor), 50);
await desmarcar(comEscova[0].id);

/* ⚠ E OS DOIS JUNTOS NÃO PODEM SAIR DE GRAÇA. O pacote cobre a manutenção;
   dar o combo inteiro porque metade está coberta seria um desconto que
   ninguém decidiu — e o mais caro dos dois. */
const combo = await marcar(maria, [manutencao.id, escova.id], daquiA(6, 13),
  'Maria Pacote', TEL_MARIA);
igual('manutenção + escova juntas custam os R$ 90, não zero',
  Number(combo[0].valor), 90);
await desmarcar(combo[0].id);

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ QUEM SABE O TELEFONE DELA NÃO GANHA O PACOTE

   O caso que este arquivo existe para provar. Uma vizinha que conhece o
   número da Maria digita o mesmo telefone, SEM conta. A ficha encontrada é a
   da Maria — é assim que o sistema funciona, e sem SMS não há como impedir.
   O que NÃO pode acontecer é o atendimento sair de graça.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Sem login, com o telefone da Maria');

const vizinha = novaAba();          // aba nova, sem conta nenhuma
const espiao = await marcar(vizinha, [manutencao.id], daquiA(7, 13),
  'Maria Pacote', TEL_MARIA);
igual('paga os R$ 40 — o pacote não acompanha o telefone',
  Number(espiao[0].valor), 40);
await desmarcar(espiao[0].id);

const depoisDoEspiao = await maria.chamar('meus_pacotes', { p_salao: SALAO });
igual('e nenhuma sessão da Maria foi gasta por ela',
  Number(((Array.isArray(depoisDoEspiao) ? depoisDoEspiao : [])[0] || {}).restantes), 3);

/* E a função dos pacotes não responde para quem não está logado. */
const anon = novaAba();
let vazio = null;
try{ vazio = await anon.chamar('meus_pacotes', { p_salao: SALAO }); }catch(e){ vazio = e.message; }
verdade('sem login, meus_pacotes() não devolve nada — ' + JSON.stringify(vazio),
  Array.isArray(vazio) ? vazio.length === 0 : true,
  'devolveu pacote para quem não provou quem é');

/* ══════════════════════════════════════════════════════════════════════════
   4 — AS SESSÕES ACABAM, E CANCELAR DEVOLVE
   ══════════════════════════════════════════════════════════════════════════ */
secao('Gastando as sessões');

const usadas = [];
for(let i = 0; i < 3; i++){
  const r = await marcar(maria, [manutencao.id], daquiA(8 + i, 13),
    'Maria Pacote', TEL_MARIA);
  usadas.push(r[0]);
  igual('sessão ' + (i + 2) + ' de 4 sai por R$ 0,00', Number(r[0].valor), 0);
  await atender(r[0].id);
}

const acabou = await marcar(maria, [manutencao.id], daquiA(12, 13),
  'Maria Pacote', TEL_MARIA);
igual('a quinta volta a custar R$ 40 — o pacote acabou',
  Number(acabou[0].valor), 40);
await desmarcar(acabou[0].id);

/* ⚠ CANCELAR DEVOLVE A SESSÃO, e sem ninguém ter escrito código para isso.
   As sessões gastas são CONTADAS a partir dos agendamentos vivos, não
   guardadas num contador — cancelar muda o status e a conta muda junto. É o
   que evita a classe de defeito que o estoque do 26 precisou travar à mão. */
await dona.atualizar('agendamentos', usadas[0].id, { status:'cancelado' });
const depoisDoCancel = await marcar(maria, [manutencao.id], daquiA(13, 13),
  'Maria Pacote', TEL_MARIA);
igual('cancelando uma, a sessão volta e a próxima sai de graça de novo',
  Number(depoisDoCancel[0].valor), 0);
await desmarcar(depoisDoCancel[0].id);

/* ══════════════════════════════════════════════════════════════════════════
   5 — OS DIAS DA SEMANA
   ══════════════════════════════════════════════════════════════════════════ */
secao('Pacote que só vale em alguns dias');

const so2a = await dona.inserir('pacotes', { salaoId:SALAO,
  nome:'Só na segunda', preco:60, sessoes:10, validadeDias:90,
  dias:[1], ativo:true });                       // 1 = segunda-feira
await dona.inserir('pacote_servicos',
  { pacoteId: so2a.id, servicoId: escova.id });

const ana = novaAba();
const TEL_ANA = tel(3);
await ana.criarConta({ email:`pac-ana-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ana Segunda', telefone: TEL_ANA });
const anaPrimeira = await marcar(ana, [escova.id], daquiA(3, 15),
  'Ana Segunda', TEL_ANA);
await desmarcar(anaPrimeira[0].id);
const fichaAna = (await dona.lista('clientes', { salaoId: SALAO }))
  .find(c => soDigitos(c.telefone) === soDigitos(TEL_ANA));
await dona.chamar('vender_pacote', { p_pacote: so2a.id, p_cliente: fichaAna.id });

/* Acha a próxima segunda e a próxima quarta, no fuso do salão. Fixar "daqui a
   N dias" daria um dia da semana diferente a cada dia em que o teste rodasse —
   é a armadilha que fez a `corrida.test.mjs` reprovar uma hora por dia. */
const proximo = (dow) => {
  for(let i = 2; i < 16; i++){
    const d = new Date(Date.now() + i * 864e5);
    d.setUTCHours(15, 0, 0, 0);
    if(new Date(d.toLocaleString('en-US', { timeZone:'America/Sao_Paulo' }))
         .getDay() === dow) return d.toISOString();
  }
  return null;
};
const naSegunda = proximo(1), naQuarta = proximo(3);
verdade('achei uma segunda e uma quarta para medir', !!naSegunda && !!naQuarta);

const rSeg = await marcar(ana, [escova.id], naSegunda, 'Ana Segunda', TEL_ANA);
igual('na segunda, a escova sai por R$ 0,00', Number(rSeg[0].valor), 0);
await atender(rSeg[0].id);

const rQua = await marcar(ana, [escova.id], naQuarta, 'Ana Segunda', TEL_ANA);
/* ⚠ E NA QUARTA ELA CONTINUA CONSEGUINDO MARCAR — pagando. O pacote restringe
   o BENEFÍCIO, não o acesso: bloquear seria tirar da cliente uma coisa que
   ela já tem hoje, e transformar um desconto num castigo. */
igual('na quarta ela marca do mesmo jeito, pagando os R$ 50',
  Number(rQua[0].valor), 50);
await desmarcar(rQua[0].id);

/* ══════════════════════════════════════════════════════════════════════════
   6 — VALIDADE
   ══════════════════════════════════════════════════════════════════════════ */
secao('Pacote vencido');

await dona.atualizar('pacote_clientes', VENDA,
  { venceEm: new Date(Date.now() - 864e5).toISOString().slice(0, 10) });
const vencido = await marcar(maria, [manutencao.id], daquiA(14, 13),
  'Maria Pacote', TEL_MARIA);
igual('vencido, volta a custar R$ 40', Number(vencido[0].valor), 40);
const nada = await maria.chamar('meus_pacotes', { p_salao: SALAO });
igual('e some da lista dela', (Array.isArray(nada) ? nada : []).length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   7 — QUEM PODE VENDER
   ══════════════════════════════════════════════════════════════════════════ */
secao('Só gestor vende pacote');

let recusou = null;
try{
  await maria.chamar('vender_pacote', { p_pacote: pacote.id, p_cliente: fichaMaria.id });
}catch(e){ recusou = e.message || String(e); }
verdade('a própria cliente não consegue se dar um pacote',
  recusou !== null, 'ACEITOU — qualquer pessoa logada se daria pacote de graça');

console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
