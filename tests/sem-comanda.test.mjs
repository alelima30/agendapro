/* ===========================================================================
   AgendaPro — o salão que trabalha sem comanda e sem caixa

     bash tests/bancada/subir.sh
     node tests/sem-comanda.test.mjs

   ── O QUE ESTÁ SENDO MEDIDO ────────────────────────────────────────────────
   "Não quero comanda nem caixa. Abre, coloca os serviços e já começa a
   trabalhar."

   Atender o pedido só na tela zeraria o mês do salão: TODO o dinheiro deste
   sistema nasce da comanda — o `relatorio()` do 12 soma comanda FECHADA, a
   comissão do 16 mora em `comanda_itens`. Um salão que nunca abrisse comanda
   teria faturamento zero, sem erro nenhum na tela.

   Então o 28 faz o contrário: o atendimento concluído VIRA comanda sozinho,
   fechada, com o pagamento pelo total. A palavra "comanda" some da tela; a
   contabilidade não some. A seção 3 é a que prova isso — sem ela, este
   arquivo estaria medindo que linhas foram criadas, e não que o dono
   consegue ver quanto faturou.

   ── ⚠ E A SEÇÃO 1 É A MAIS IMPORTANTE DE TODAS ─────────────────────────────
   O padrão é LIGADO. Se a ausência da chave valesse "desligado", todo salão
   que existe hoje passaria a gerar comanda automática por cima das comandas
   de verdade que a recepção abre à mão — com desconto, produto e forma de
   pagamento próprios. A seção 1 é o que impede isso de passar despercebido.
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
await d.criarConta({ email:`sc-dona-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona Sem Comanda', telefone: tel(1) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Sem Comanda ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const prof = (await d.lista('profissionais', { salaoId: SALAO }))[0];

/* Comissão no CADASTRO, não no agendamento. É o que a seção 4 mede: o gatilho
   do 16 resolve a taxa pelo cadastro na hora de criar o item, e a comanda
   automática tem que passar por esse mesmo caminho. */
await d.atualizar('profissionais', prof.id, { comissaoPct: 40 });

for(let i = 0; i <= 6; i++)
  await d.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                inicio:'08:00', fim:'20:00' });

const corte = await d.inserir('servicos', { salaoId:SALAO, nome:'Corte',
  preco:50, duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });
/* ⚠ SÓ DÍGITOS. A trava `cli_tel_so_digitos` do 05 recusa o `+` que o
   `criarConta()` aceita — são duas colunas com réguas diferentes, e misturá-las
   derruba a montagem antes de medir qualquer coisa. */
const cliente = await d.inserir('clientes', { salaoId:SALAO, nome:'Joana Teste',
  telefone: String(51900000000 + (Date.now() % 89000000)) });
ok('salão com um serviço de R$ 50 e comissão de 40%');

/* A recepção marcando pelo painel: insert direto, `origem: recepcao`. É este
   o caminho do salão que não usa comanda — ele vive na agenda. */
const FUSO = 'America/Sao_Paulo';
const hojeNoSalao = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO,
  year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date());

/* ⚠ UM DIA DIFERENTE PARA CADA MARCAÇÃO, ÀS 10H DO SALÃO.

   Primeiro eu tinha escrito "daqui a 36 horas, mais 3 a cada chamada" — e na
   quarta marcação o relógio já tinha saído da jornada das 08h às 20h. O erro
   que voltou foi "Fora da jornada de trabalho deste profissional", um defeito
   da MONTAGEM do teste que eu leria como defeito do módulo 28.

   Dias separados resolvem duas coisas de uma vez: nenhuma marcação cai dentro
   da outra (a trava anti-choque do 14 é real), e o horário é sempre o mesmo,
   bem no meio do expediente, a qualquer hora em que o teste rode. */
const maisDias = (data, n) => {
  const x = new Date(data + 'T12:00:00Z');
  x.setUTCDate(x.getUTCDate() + n);
  return x.toISOString().slice(0, 10);
};
let diaDaVez = 2;
const asDezNoSalao = n => maisDias(hojeNoSalao, n) + 'T13:00:00Z';  // 10h em SP

async function marcarNaRecepcao(preco = 50){
  const ini = asDezNoSalao(diaDaVez++);
  const fim = new Date(new Date(ini).getTime() + 60 * 60000).toISOString();
  const a = await d.inserir('agendamentos', { salaoId: SALAO,
    clienteId: cliente.id, profissionalId: prof.id, inicio: ini, fim,
    status:'confirmado', origem:'recepcao', valorPrevisto: preco });
  await d.inserir('agendamento_servicos', { agendamentoId: a.id,
    servicoId: corte.id, ordem:1, duracaoMin:60, preco, comissaoPct:0 });
  return a;
}
const concluir  = id => d.atualizar('agendamentos', id, { status:'concluido' });
const desmarcar = id => d.atualizar('agendamentos', id, { status:'cancelado' });
const comandasDo = async agId => (await d.lista('comandas', { agendamentoId: agId }));

const ligar    = () => d.atualizar('saloes', SALAO, { cfg:{ usaComanda: true } });
const desligar = () => d.atualizar('saloes', SALAO, { cfg:{ usaComanda: false } });

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ O PADRÃO É LIGADO, E NADA MUDA PARA QUEM JÁ USA
   ══════════════════════════════════════════════════════════════════════════ */
secao('Salão novo, sem a chave no cfg');

const semChave = await d.chamar('usa_comanda', { p_salao: SALAO });
verdade('o salão nasce USANDO comanda — ' + JSON.stringify(semChave),
  semChave === true,
  'se nascesse desligado, todo salão de hoje passaria a gerar comanda '
  + 'automática por cima das que a recepção abre à mão');

const a1 = await marcarNaRecepcao();
await concluir(a1.id);
igual('concluir NÃO cria comanda nenhuma — é o de sempre',
  (await comandasDo(a1.id)).length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   2 — DESLIGADO: CONCLUIR VIRA DINHEIRO
   ══════════════════════════════════════════════════════════════════════════ */
secao('Interruptor desligado');

await desligar();
igual('o banco passa a responder que não usa comanda',
  await d.chamar('usa_comanda', { p_salao: SALAO }), false);

const a2 = await marcarNaRecepcao();
igual('antes de concluir, nenhuma comanda', (await comandasDo(a2.id)).length, 0);
await concluir(a2.id);

const c2 = await comandasDo(a2.id);
igual('concluir criou UMA comanda', c2.length, 1);
igual('já nasce fechada — comanda aberta não é faturamento', c2[0].status, 'fechada');
verdade('marcada como automática', c2[0].automatica === true,
  'sem essa marca não há como desfazer sem apagar a comanda da recepção junto');
verdade('e sem dono: não foi ninguém, foi o sistema',
  c2[0].abertaPor == null, JSON.stringify(c2[0].abertaPor));

const itens = await d.lista('comanda_itens', { comandaId: c2[0].id });
igual('com o serviço do atendimento dentro', itens.length, 1);
igual('pelo preço combinado na marcação', Number(itens[0].precoUnit), 50);
igual('e apontando para o cadastro do serviço', itens[0].servicoId, corte.id);

const pgs = await d.lista('pagamentos', { comandaId: c2[0].id });
igual('com o pagamento pelo total', pgs.length, 1);
igual('de R$ 50', Number(pgs[0].valor), 50);
/* ⚠ `nao_informado`, e não `dinheiro`. Pôr dinheiro seria mentira com
   consequência: no dia em que esse salão abrisse o caixa, a gaveta passaria a
   esperar um dinheiro que nunca entrou nela. */
igual('na forma "não informado" — a verdade sobre este salão',
  pgs[0].forma, 'nao_informado');
verdade('e fora de qualquer gaveta, porque não há caixa aberto',
  pgs[0].caixaId == null, JSON.stringify(pgs[0].caixaId));

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ E O DONO CONSEGUE VER QUANTO FATUROU

   A seção que justifica o desenho inteiro. Sem ela, este arquivo mediria que
   linhas nasceram — e linha nascendo não é a mesma coisa que o relatório do
   mês respondendo certo, que é o que o dono abre.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O relatório do mês');

const rel = await d.chamar('relatorio',
  { p_salao: SALAO, p_de: hojeNoSalao, p_ate: hojeNoSalao });
const R = Array.isArray(rel) ? rel[0] : rel;
verdade('o relatório respondeu', !!R, JSON.stringify(rel).slice(0, 200));
igual('e o faturamento do dia é os R$ 50 do atendimento concluído',
  Number(R.faturamento), 50);

/* ══════════════════════════════════════════════════════════════════════════
   4 — A COMISSÃO SAI DO CADASTRO, NÃO DO AGENDAMENTO

   O item do agendamento foi gravado com `comissaoPct: 0`. Se a comanda
   automática copiasse esse número, a comissão de todo mundo seria zero num
   salão que não usa comanda — em silêncio, e só descoberto no fim do mês.
   Quem decide é o gatilho do 16, pelo cadastro do profissional: 40%.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A comissão');

igual('o item saiu com os 40% do cadastro, não com o zero da marcação',
  Number(itens[0].comissaoPct), 40);

/* ⚠ O VALOR DA COMISSÃO NÃO MORA NA TABELA — e eu escrevi
   `itens[0].comissaoValor` primeiro, que voltou nulo.

   `comanda_itens` guarda a TAXA; quem faz a conta é a vista
   `comanda_itens_calculados`, porque a comissão pode ser sobre o bruto ou
   sobre o líquido, com data de corte (16_comissao.sql). Guardar o valor
   congelaria uma conta que depende de uma regra que o dono muda.

   E a conferência é pelo RELATÓRIO, não pela vista: é o número que o dono
   abre no fim do mês, e é ele que precisa estar certo. */
const linhaProf = (R.comissoes || []).find(x => x.profissionalId === prof.id);
verdade('o relatório traz a comissão do profissional — '
  + JSON.stringify(linhaProf && { vendido: linhaProf.vendido, comissao: linhaProf.comissao }),
  !!linhaProf, JSON.stringify(R.comissoes));
igual('R$ 50 vendidos', Number((linhaProf || {}).vendido), 50);
igual('e R$ 20 de comissão', Number((linhaProf || {}).comissao), 20);

/* ══════════════════════════════════════════════════════════════════════════
   5 — DESMARCAR DESFAZ
   ══════════════════════════════════════════════════════════════════════════ */
secao('Concluir por engano');

const a3 = await marcarNaRecepcao();
await concluir(a3.id);
igual('concluído: a comanda existe', (await comandasDo(a3.id)).length, 1);
await desmarcar(a3.id);
igual('desmarcado: a comanda automática some',
  (await comandasDo(a3.id)).length, 0);
/* Senão o dinheiro de um atendimento que não houve ficaria no relatório do
   mês, e o dono só descobriria conferindo à mão. */
const relDepois = await d.chamar('relatorio',
  { p_salao: SALAO, p_de: hojeNoSalao, p_ate: hojeNoSalao });
igual('e o faturamento volta a ser só o do atendimento que houve',
  Number((Array.isArray(relDepois) ? relDepois[0] : relDepois).faturamento), 50);

/* ══════════════════════════════════════════════════════════════════════════
   6 — ⚠ A COMANDA DA RECEPÇÃO É INTOCÁVEL

   Se a recepção abriu comanda à mão — com desconto, com produto — o gatilho
   não pode criar uma segunda nem apagar a dela ao desmarcar. Uma segunda
   cobraria o atendimento duas vezes, e o índice único do 15 derrubaria a
   conclusão inteira com um erro que não tem nada a ver com o que a pessoa fez.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Comanda aberta à mão');

const a4 = await marcarNaRecepcao();
const naMao = await d.inserir('comandas', { salaoId: SALAO,
  agendamentoId: a4.id, clienteId: cliente.id, desconto: 0 });
await d.inserir('comanda_itens', { comandaId: naMao.id, tipo:'servico',
  servicoId: corte.id, descricao:'Corte', qtd:1, precoUnit:50 });

let quebrou = null;
try{ await concluir(a4.id); }catch(e){ quebrou = e.message || String(e); }
verdade('concluir não derruba quando já existe comanda', quebrou === null, quebrou);
const c4 = await comandasDo(a4.id);
igual('e continua existindo UMA só', c4.length, 1);
verdade('a da recepção, não uma automática', c4[0].automatica === false,
  'o gatilho criou por cima da comanda que alguém montou à mão');

await desmarcar(a4.id);
igual('desmarcar NÃO apaga a comanda da recepção',
  (await comandasDo(a4.id)).length, 1);

/* ══════════════════════════════════════════════════════════════════════════
   7 — ⚠ O ATENDIMENTO DE R$ 0,00 — QUE É O PACOTE

   Não é caso raro: uma manutenção coberta pelo pacote vale zero. E
   `tg_fechar_comanda` recusa comanda sem itens com "Comanda sem itens não
   pode ser fechada" — se o 28 tentasse criar mesmo assim, CONCLUIR O
   ATENDIMENTO FALHARIA, com uma frase que não tem nada a ver com o que a
   recepção fez.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Atendimento que não custou nada');

const aZ = await marcarNaRecepcao(0);

let caiu = null;
try{ await concluir(aZ.id); }catch(e){ caiu = e.message || String(e); }
verdade('concluir um atendimento de R$ 0,00 não derruba', caiu === null, caiu);
igual('e não nasce comanda — não houve dinheiro nenhum a contar',
  (await comandasDo(aZ.id)).length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   8 — LIXO NO CFG NÃO DESLIGA NADA

   `cfg` é jsonb e guarda o que puserem nele. `'abacaxi'::boolean` LEVANTA no
   Postgres — e um cast desprotegido aqui derrubaria a conclusão de TODO
   atendimento do salão. A peneira é de texto, e o lado seguro é o ligado: um
   erro de digitação nunca pode apagar a comanda de ninguém.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Valor inválido no cfg');

await d.atualizar('saloes', SALAO, { cfg:{ usaComanda:'abacaxi' } });
let explodiu = null, resposta = null;
try{ resposta = await d.chamar('usa_comanda', { p_salao: SALAO }); }
catch(e){ explodiu = e.message || String(e); }
verdade('a função continua respondendo', explodiu === null, explodiu);
igual('e cai no lado seguro: LIGADO', resposta, true);

const aL = await marcarNaRecepcao();
let caiuL = null;
try{ await concluir(aL.id); }catch(e){ caiuL = e.message || String(e); }
verdade('concluir continua funcionando com lixo no cfg', caiuL === null, caiuL);
igual('e nenhuma comanda automática nasce', (await comandasDo(aL.id)).length, 0);

/* ══════════════════════════════════════════════════════════════════════════
   9 — LIGAR DE VOLTA
   ══════════════════════════════════════════════════════════════════════════ */
secao('Religando o interruptor');

await ligar();
const a5 = await marcarNaRecepcao();
await concluir(a5.id);
igual('volta a não criar comanda sozinho',
  (await comandasDo(a5.id)).length, 0);

console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
