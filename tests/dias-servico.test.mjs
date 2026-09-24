/* ===========================================================================
   AgendaPro — o serviço que só é feito em certos dias

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/dias-servico.test.mjs

   "Escova só de quinta a sábado." Pedido de quem tem serviço longo que só cabe
   em dia de movimento fraco.

   ── AS TRÊS COISAS QUE ESTE ARQUIVO PRECISA PROVAR ─────────────────────────

     1. QUEM NÃO CONFIGUROU NÃO MUDA. `dias` nulo é o estado de todo serviço
        que já existe. Se ausente não valesse "todos os dias", esta
        funcionalidade apagaria a agenda de quem nunca pediu nada.

     2. QUEM RECUSA É O BANCO. A peneira não pode viver só na tela: o
        `agendar()` tem que recusar a segunda-feira mesmo que a chamada venha
        direto, sem passar pela página.

     3. A RECEPÇÃO CONTINUA LIVRE. O painel grava na tabela direto, e a dona
        marca a escova na segunda se ela quiser. A peneira é do LINK.

   ⚠ E UMA QUARTA, QUE É DE TEXTO E NÃO DE REGRA: o dia bloqueado não pode
   aparecer como "cheio". "Cheio" manda a cliente esperar uma vaga que nunca
   vai abrir; o salão está vazio, o serviço é que não é feito ali.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
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
await dona.criarConta({ email:`ds-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'18:00' });
}

/* Dois serviços de propósito. O corte não é tocado NUNCA neste arquivo: ele é
   a testemunha de que a funcionalidade não vaza para quem não a usa. */
const corte = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova',
  duracaoMin:60, intervaloMin:0, preco:120, ativo:true, aceitaOnline:true });
ok('salão criado, com um Corte e uma Escova — nenhum com dia marcado');

/* ⚠ AS DATAS SAEM DO FUSO DO SALÃO, e não do relógio desta máquina. Já custou
   caro neste projeto: teste que monta data com `new Date()` local reprova uma
   hora por dia e passa nas outras vinte e três. */
const hojeNoSalao = (await dona.chamar('hoje_no_salao', { p_salao: SALAO }));
const HOJE = String(Array.isArray(hojeNoSalao) ? hojeNoSalao[0] : hojeNoSalao).slice(0,10);
const somarDias = (iso, n) => {
  const [a,m,d] = iso.split('-').map(Number);
  const t = new Date(Date.UTC(a, m-1, d + n));
  return t.toISOString().slice(0,10);
};
const dowDe = iso => {
  const [a,m,d] = iso.split('-').map(Number);
  return new Date(Date.UTC(a, m-1, d)).getUTCDay();
};
// Uma quinta e uma segunda, ambas no futuro e dentro da janela liberada.
let QUINTA = HOJE, SEGUNDA = HOJE;
for(let i = 1; i <= 14; i++){
  const d = somarDias(HOJE, i);
  if(dowDe(d) === 4 && QUINTA === HOJE) QUINTA = d;
  if(dowDe(d) === 1 && SEGUNDA === HOJE) SEGUNDA = d;
}
console.log(`      hoje ${HOJE} · quinta ${QUINTA} · segunda ${SEGUNDA}`);

const porque = (dia, servicos) => dona.chamar('porque_nao_agenda',
  { p_profissional: prof.id, p_data: dia, p_servicos: servicos });
const vagas = async (dia, servicos) =>
  (await dona.chamar('horarios_livres',
    { p_profissional: prof.id, p_data: dia, p_servicos: servicos }) || []).length;

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ SEM DIA MARCADO, NADA MUDA
   ══════════════════════════════════════════════════════════════════════════ */
secao('O serviço que ninguém configurou');

igual('a segunda continua aberta para a escova', await porque(SEGUNDA, [escova.id]), null);
igual('e para o corte também', await porque(SEGUNDA, [corte.id]), null);
verdade('e a agenda oferece horário na segunda',
  await vagas(SEGUNDA, [escova.id]) > 0);

const v0 = await dona.chamar('vitrine', { p_slug: SLUG });
const svs0 = (Array.isArray(v0) ? v0[0] : v0).servicos;
verdade('a vitrine() manda `dias` nulo para os dois',
  svs0.every(s => s.dias === null), JSON.stringify(svs0.map(s => [s.nome, s.dias])));

/* ══════════════════════════════════════════════════════════════════════════
   2 — A ESCOVA PASSA A SER SÓ DE QUINTA A SÁBADO
   ══════════════════════════════════════════════════════════════════════════ */
secao('Escova só de quinta a sábado');

await dona.atualizar('servicos', escova.id, { dias: [4, 5, 6] });

igual('na quinta ela continua aberta', await porque(QUINTA, [escova.id]), null);
const naSegunda = await porque(SEGUNDA, [escova.id]);
verdade('na segunda o banco recusa', typeof naSegunda === 'string' && naSegunda.length > 0,
  JSON.stringify(naSegunda));
/* ⚠ A FRASE PRECISA DIZER O QUÊ, QUANDO E O QUE FAZER. Recusa sem motivo
   escrito é igual a horário que some: a cliente conclui que o salão fechou. */
verdade('e a frase diz o serviço', /Escova/.test(naSegunda || ''), naSegunda);
/* ⚠ SEM CONCORDÂNCIA DE GÊNERO. A frase dizia "Escova é feito só quinta" — o
   nome do serviço é texto livre do dono, e metade é feminino. Não dá para
   adivinhar; dois-pontos resolvem sem adivinhar nada. */
verdade('e sem errar a concordância — nada de "é feito" num nome feminino',
  !/é feit[oa]/.test(naSegunda || ''), naSegunda);
verdade('e diz quais são os dias',
  /quinta/.test(naSegunda || '') && /sábado/.test(naSegunda || ''), naSegunda);
verdade('e oferece uma saída', /WhatsApp|Escolha/.test(naSegunda || ''), naSegunda);

igual('a agenda não oferece horário nenhum na segunda',
  await vagas(SEGUNDA, [escova.id]), 0);
verdade('mas oferece na quinta', await vagas(QUINTA, [escova.id]) > 0);

/* ⚠ O CORTE, QUE NINGUÉM TOCOU, CONTINUA ABERTO NA SEGUNDA. É a prova de que
   a regra é do serviço e não do dia: um serviço com dia marcado não pode
   fechar a segunda-feira do salão inteiro. */
igual('o corte continua aberto na segunda', await porque(SEGUNDA, [corte.id]), null);
verdade('e com horário para marcar', await vagas(SEGUNDA, [corte.id]) > 0);

/* ⚠ E BASTA UM DO PEDIDO ESTAR FORA. Ela marcou corte + escova juntos; se a
   escova não é feita na segunda, o par não cabe na segunda. Barrar só quando
   TODOS estão fora deixaria passar um combinado que o salão não cumpre — e o
   problema apareceria com a cliente sentada na cadeira. */
verdade('corte + escova na segunda é recusado por causa da escova',
  /Escova/.test(await porque(SEGUNDA, [corte.id, escova.id]) || ''),
  JSON.stringify(await porque(SEGUNDA, [corte.id, escova.id])));

/* ══════════════════════════════════════════════════════════════════════════
   2b — ⚠ A LISTA DE ESPERA PEDE UMA JANELA, NÃO UM DIA

   Achado caçando bug, e é o pior tipo de falha que este projeto conhece: o
   mesmo link RECUSAVA marcar escova na segunda, com a frase certa, e ACEITAVA
   a cliente na fila de domingo a quarta — uma janela em que a escova não é
   feita em dia nenhum.

   Nada dava erro. Ela recebia "pronto, a gente te avisa" e ficava esperando um
   telefonema que não podia acontecer. Do lado do salão também não aparecia
   nada: um pedido impossível no meio dos possíveis.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A fila de espera e os dias do serviço');

const naFila = async (de, ate, servicos) => {
  try{
    await dona.chamar('entrar_na_fila', { p_salao: SALAO, p_servicos: servicos,
      p_nome:'Ana Teste', p_telefone:'1197770' + String(Date.now()).slice(-4),
      p_de: de, p_ate: ate, p_profissional: null, p_turno:'qualquer', p_obs: null });
    return null;                       // entrou
  }catch(e){ return e.message; }       // recusou, e a frase é esta
};

// Uma janela de domingo a quarta: nenhum dia em que a escova é feita.
let DOMINGO = HOJE;
for(let i = 1; i <= 14; i++){
  const d = somarDias(HOJE, i);
  if(dowDe(d) === 0){ DOMINGO = d; break; }
}
const QUARTA = somarDias(DOMINGO, 3);
const naoNaFila = await naFila(DOMINGO, QUARTA, [escova.id]);
verdade('janela sem nenhum dia possível é recusada',
  typeof naoNaFila === 'string' && /Escova/.test(naoNaFila), JSON.stringify(naoNaFila));
/* ⚠ E A FRASE É A MESMA DA RECUSA DE MARCAR. Dois textos para o mesmo motivo
   fazem a cliente achar que são dois problemas diferentes. */
verdade('e com a MESMA frase da recusa de marcar',
  naoNaFila === await porque(SEGUNDA, [escova.id]),
  JSON.stringify(naoNaFila) + '\n      vs '
    + JSON.stringify(await porque(SEGUNDA, [escova.id])));

/* ⚠ E BASTA UM DIA PARA ACEITAR. Recusar a janela por ela conter dias ruins
   seria recusar quase todas — quase toda semana tem pelo menos um dia de
   fora. Se pega uma quinta, o salão vai oferecer a quinta. */
igual('janela que pega uma quinta é aceita',
  await naFila(DOMINGO, somarDias(DOMINGO, 6), [escova.id]), null);
igual('e o corte, que não tem dia marcado, entra em qualquer janela',
  await naFila(DOMINGO, QUARTA, [corte.id]), null);

/* ⚠ DATA INVERTIDA CONTINUA RESPONDENDO SOBRE A DATA. Falar dos dias da
   semana de uma janela que começa depois de terminar seria responder outra
   pergunta. */
verdade('janela invertida reclama da data, e não dos dias',
  /datas/.test(await naFila(QUARTA, DOMINGO, [escova.id]) || ''),
  JSON.stringify(await naFila(QUARTA, DOMINGO, [escova.id])));

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ A RECEPÇÃO NÃO É PENEIRADA

   O painel grava na tabela direto, sem passar pelo `agendar()`. Se a dona
   quiser fazer escova na segunda, ela faz — a peneira é do link.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A recepção continua dona da agenda');

const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Maria Souza',
  telefone:'11988887777' });
let marcouNaSegunda = true, recusa = '';
try{
  await dona.inserir('agendamentos', { salaoId: SALAO, clienteId: cli.id,
    profissionalId: prof.id, inicio: SEGUNDA + 'T13:00:00-03:00',
    fim: SEGUNDA + 'T14:00:00-03:00', status:'confirmado', origem:'recepcao' });
}catch(e){ marcouNaSegunda = false; recusa = e.message; }
verdade('a dona marca a escova na segunda pelo painel, e o banco aceita',
  marcouNaSegunda, recusa);

/* ══════════════════════════════════════════════════════════════════════════
   4 — ⚠ A PÁGINA DA CLIENTE DIZ "NÃO ATENDE", E NÃO "CHEIO"
   ══════════════════════════════════════════════════════════════════════════ */
secao('O que a cliente lê no dia bloqueado');

const v1 = await dona.chamar('vitrine', { p_slug: SLUG });
const svs1 = (Array.isArray(v1) ? v1[0] : v1).servicos;
const daEscova = svs1.find(s => s.nome === 'Escova');
const doCorte  = svs1.find(s => s.nome === 'Corte');
igual('a vitrine() leva os dias da escova', daEscova.dias, [4,5,6]);
igual('e continua mandando nulo para o corte', doCorte.dias, null);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 } });
const c = await ctx.newPage();
const erros = [];
c.on('pageerror', e => erros.push(e.message));
await c.goto(BASE + '/agendar.html?salao=' + SLUG);
await c.waitForTimeout(2600);

/* ⚠ PELOS BOTÕES, e não empurrando `escolha` por dentro. Mexer no estado e
   chamar `irPara()` pula o que cada passo faz ao sair — foi o que a primeira
   versão deste teste fez, e a faixa de dias veio vazia: parecia defeito da
   funcionalidade e era o teste entrando pela janela. O caminho é o mesmo do
   `cliente-nuvem.test.mjs`, que já o percorre há muito tempo. */
const escolherServico = async nome => {
  await c.click('#listaServicos button.opcao:has-text("' + nome + '")');
  await c.waitForTimeout(250);
  await c.click('#btPrincipal'); await c.waitForTimeout(400);
  await c.click('#listaProfs button.opcao'); await c.waitForTimeout(250);
  await c.click('#btPrincipal'); await c.waitForTimeout(3000);
};
await c.click('#btPrincipal'); await c.waitForTimeout(400);
await escolherServico('Escova');

const faixa = await c.evaluate(() =>
  [...document.querySelectorAll('#listaDias .dia')].map(b => ({
    txt: (b.querySelector('i') || {}).textContent || '',
    dia: (b.querySelector('small') || {}).textContent || '',
  })));
console.log('      ' + JSON.stringify(faixa.slice(0, 8)));

const segundas = faixa.filter(d => /seg/i.test(d.dia));
const quintas  = faixa.filter(d => /qui/i.test(d.dia));
verdade('a faixa de dias foi desenhada', faixa.length > 0);
verdade('a segunda diz "não atende", e nunca "cheio"',
  segundas.length > 0 && segundas.every(d => /não atende/.test(d.txt)),
  JSON.stringify(segundas));
verdade('e a quinta oferece vagas',
  quintas.length > 0 && quintas.some(d => /vaga/.test(d.txt)),
  JSON.stringify(quintas));

// E com o corte escolhido, nenhum dia é "não atende".
await c.goto(BASE + '/agendar.html?salao=' + SLUG);
await c.waitForTimeout(2600);
await c.click('#btPrincipal'); await c.waitForTimeout(400);
await escolherServico('Corte');
const faixaCorte = await c.evaluate(() =>
  [...document.querySelectorAll('#listaDias .dia i')].map(i => i.textContent));
verdade('escolhendo o corte, nenhum dia diz "não atende"',
  faixaCorte.length > 0 && !faixaCorte.some(t => /não atende/.test(t)),
  JSON.stringify(faixaCorte.slice(0, 8)));

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
