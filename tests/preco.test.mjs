/* ===========================================================================
   AgendaPro — preço por vigência, dia da semana e faixa de horário

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/preco.test.mjs

   O pedido: "escova R$ 50 de terça a quinta, R$ 70 sexta e sábado";
   "corte R$ 60 antes das 14h"; "a partir de março a escova passa a R$ 80".

   ── ⚠ ANTES DA FUNCIONALIDADE, TRÊS PREÇOS PARA O MESMO ATENDIMENTO ────────
   Medido na bancada, com o corte a R$ 90 no catálogo e R$ 130 com a
   profissional (`servicos_profissionais.preco`, que já existia):

       o que a cliente VIA na vitrine ......... R$  90
       o que o link COBRAVA no agendar() ...... R$ 130
       o que a recepção COBRAVA no painel ..... R$  90

   Os três liam colunas diferentes, e não havia ninguém para arbitrar. O pior é
   o primeiro par: a cliente confirmava por 90 e a linha nascia 130 — ela só
   descobria no balcão, e a culpa parecia do salão.

   A funcionalidade nova só ficou de pé depois que passou a existir UM lugar
   que responde "quanto custa": `preco_do_servico()` no 33.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a escada do banco, degrau por degrau, e o desempate entre regras;
     2. que os três caminhos cobram o MESMO — vitrine, link e recepção;
     3. que o gatilho corrige a recepção mesmo quando a tela manda errado;
     4. que o preço CONGELA: mudar a regra depois não mexe no que foi marcado;
     5. que o espelho de JavaScript responde igual ao Postgres, caso a caso.
        É o item que mais importa: espelho de dinheiro que anda sozinho faz a
        tela prometer um preço e o banco cobrar outro.
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
const reais = n => Number(n).toFixed(2);

function aba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(path.join(RAIZ,'dados.js'),'utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

/* A próxima terça e o próximo sábado, com folga de uma semana para nunca
   caírem no passado nem fora da janela liberada. Data fixa no teste envelhece;
   data calculada a partir de hoje não. */
const proximo = dow => {
  const d = new Date();
  d.setUTCHours(12, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() + ((dow - d.getUTCDay() + 7) % 7 || 7));
  return d.toISOString().slice(0, 10);
};
const TERCA  = proximo(2);
const SABADO = proximo(6);
// Em America/Sao_Paulo (UTC-3), 10h locais são 13h UTC.
const emUtc = (dia, horaLocal) =>
  new Date(dia + 'T' + String(horaLocal + 3).padStart(2,'0') + ':00:00.000Z')
    .toISOString();

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`pr-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa do Preço',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'19:00' });
}
const sv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:60, intervaloMin:0, preco:90, ativo:true, aceitaOnline:true });
// O par que já existia e que ninguém respeitava por igual.
await dona.inserir('servicos_profissionais',
  { servicoId: sv.id, profissionalId: prof.id, preco:130 });
ok('salão criado: corte a R$ 90 no catálogo, R$ 130 com a profissional');

const vitrine = async () => {
  const v = await dona.chamar('vitrine', { p_slug: SLUG });
  return Array.isArray(v) ? v[0] : v;
};
/* ⚠ PERGUNTAR O PREÇO NÃO É MARCAR, e a diferença importa para o teste.
   A primeira versão media a escada MARCANDO, e cada marcação ocupa o horário
   de verdade: na sétima o banco respondeu "esse horário não está mais livre" e
   o arquivo morreu no meio de uma verificação de dinheiro, por um motivo que
   não tinha nada a ver com preço.

   Aqui a escada é perguntada direto à função que o `agendar()` chama. As
   marcações continuam existindo mais abaixo, onde marcar É o assunto. */
const precoNoBanco = async (quando) => {
  const r = await dona.chamar('preco_dos_servicos', {
    p_profissional: prof.id, p_servicos: [sv.id], p_quando: quando });
  return reais(Array.isArray(r) ? r[0] : r);
};

const marcarPeloLink = async (quando) => {
  const cli = aba();
  const r = await cli.chamar('agendar', { p_profissional: prof.id,
    p_inicio: quando, p_servicos:[sv.id], p_nome:'Ana Teste',
    p_telefone:'119' + String(70000000 + Math.floor(Math.random()*9999999)) });
  return Array.isArray(r) ? r[0] : r;
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — A ESCADA, DEGRAU POR DEGRAU
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · A escada do banco');

igual('sem regra nenhuma, vale o preço do par',
  await precoNoBanco(emUtc(TERCA, 10)), '130.00');

const r1 = await dona.inserir('precos_regras',
  { salaoId: SALAO, servicoId: sv.id, preco:50, dias:[2,3,4] });
/* ⚠ A REGRA GANHA DO PAR, e não o contrário. Uma promoção de terça é do
   salão: ela vale para quem atender, inclusive para quem cobra mais caro. Quem
   quiser a profissional de fora põe o nome dela numa regra própria — e aí essa
   ganha, porque tem mais recortes. */
igual('a regra de terça ganha do preço do par',
  await precoNoBanco(emUtc(TERCA, 11)), '50.00');
igual('no sábado, que não é dia da regra, volta o par',
  await precoNoBanco(emUtc(SABADO, 11)), '130.00');

const r2 = await dona.inserir('precos_regras',
  { salaoId: SALAO, servicoId: sv.id, preco:40, dias:[2,3,4],
    horaIni:480, horaFim:720 });
igual('dias + horário ganha de dias sozinho',
  await precoNoBanco(emUtc(TERCA, 9)), '40.00');
igual('fora da faixa, volta a regra de dias',
  await precoNoBanco(emUtc(TERCA, 15)), '50.00');
/* ⚠ A FAIXA É FECHADA NO COMEÇO E ABERTA NO FIM. Meio-dia pertence à tarde, e
   não às duas. Sem essa escolha, das 8h às 12h e das 12h às 18h se cruzariam
   exatamente no meio-dia, e qual ganharia dependeria da ordem de cadastro. */
igual('meio-dia cai FORA da faixa que termina ao meio-dia',
  await precoNoBanco(emUtc(TERCA, 12)), '50.00');

const r3 = await dona.inserir('precos_regras',
  { salaoId: SALAO, servicoId: sv.id, profissionalId: prof.id, preco:95,
    dias:[2,3,4] });
igual('a regra com profissional ganha de todas',
  await precoNoBanco(emUtc(TERCA, 15)), '95.00');

/* ⚠ E PRECISA GANHAR DE UMA REGRA CADASTRADA DEPOIS DELA, senão o teste está
   medindo a ordem de cadastro e chamando isso de especificidade.

   Empate de peso é desempatado pela mais nova. Como a r3 era a última regra do
   arquivo, ela ganhava de todo jeito — com peso de profissional ou sem. A
   mutação que zerava esse peso sobreviveu por isso: o número não mudava.

   A r5 é do salão (sem profissional), tem os mesmos recortes que a r1 e nasce
   DEPOIS da r3. Agora o peso da profissional é a única coisa que decide entre
   95 e 70. */
const r5 = await dona.inserir('precos_regras',
  { salaoId: SALAO, servicoId: sv.id, preco:70, dias:[2,3,4] });
igual('e ganha até de uma regra do salão cadastrada depois dela',
  await precoNoBanco(emUtc(TERCA, 15)), '95.00');

/* ⚠ A REGRA FUTURA PRECISA SER A MAIS ESPECÍFICA DE TODAS, senão ela não
   prova nada. A primeira versão pôs uma regra larga (só vigência, peso 1) e a
   regra da profissional (peso 12) ganhava de qualquer jeito — com ou sem a
   conferência de data. A mutação que apagava o `and q.dia >= r.de` sobreviveu
   por isso: a resposta não mudava.

   Com profissional + dias + horário + vigência ela passa a ser a de MAIOR
   peso. Se a data deixar de ser olhada, é ela que responde — e o número
   muda. */
const depois = new Date(Date.now() + 200*864e5).toISOString().slice(0,10);
const r4 = await dona.inserir('precos_regras',
  { salaoId: SALAO, servicoId: sv.id, profissionalId: prof.id, preco:20,
    dias:[2,3,4], horaIni:780, horaFim:1020, de: depois });
igual('regra que só começa daqui a meses não mexe no preço de hoje',
  await precoNoBanco(emUtc(TERCA, 15)), '95.00');
await dona.apagar('precos_regras', r4.id);

// E uma desligada também não.
await dona.atualizar('precos_regras', r3.id, { ativo:false });
igual('regra desligada sai da disputa',
  await precoNoBanco(emUtc(TERCA, 15)), '70.00');
await dona.atualizar('precos_regras', r3.id, { ativo:true });

/* ══════════════════════════════════════════════════════════════════════════
   2 — OS TRÊS CAMINHOS COBRAM O MESMO
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · Vitrine, link e recepção dizem o mesmo número');

const vit = await vitrine();
const svVit = vit.servicos[0];
console.log('      ' + JSON.stringify({ preco: svVit.preco,
  precoMin: svVit.precoMin, porProf: svVit.precoPorProf,
  regras: (svVit.regras || []).length }));

igual('a vitrine leva o menor preço possível para o "a partir de"',
  reais(svVit.precoMin), '40.00');
verdade('e leva o preço por profissional, que ela escondia',
  svVit.precoPorProf && Number(svVit.precoPorProf[prof.id]) === 130,
  JSON.stringify(svVit.precoPorProf));
/* ⚠ AS REGRAS VÊM NA ORDEM EM QUE GANHAM. É o que permite à tela pegar a
   primeira que casar, sem repetir em JavaScript a conta de especificidade do
   33 — que é onde um espelho desses diverge do original com o tempo. */
igual('e as regras vêm ordenadas por quem ganha',
  (svVit.regras || []).map(x => Number(x.preco)), [95, 40, 70, 50]);

// A recepção: grava o preço do catálogo, como a tela faz, e o banco corrige.
const cli2 = await dona.inserir('clientes',
  { salaoId: SALAO, nome:'Bia Balcao', telefone:'11966665555' });
const ag = await dona.inserir('agendamentos', { salaoId: SALAO,
  clienteId: cli2.id, profissionalId: prof.id,
  inicio: emUtc(TERCA, 16), fim: emUtc(TERCA, 17),
  status:'confirmado', origem:'recepcao' });
/* ⚠ O CONTRATO É "QUEM NÃO DISSE, O BANCO DIZ" — e ele tem três lados.

   A primeira versão do gatilho reescrevia SEMPRE, e isso consertava o defeito
   antigo ao custo de quebrar outro caso: a recepção lançando uma CORTESIA por
   R$ 0,00. O `sem-comanda.test.mjs` pegou na hora, e o arquivo dele já dizia
   por escrito que não é caso raro.

   Os dois são dinheiro, e desfazer o que a pessoa acabou de combinar na frente
   da cliente é pior do que o preço vir do catálogo. Então: sem preço, o banco
   preenche; com preço, ele respeita. E quem impede a recepção de mandar o
   número errado é o `precoDaEscada()` do painel — que responde a mesma escada
   e é conferido contra o Postgres na seção 4 deste arquivo. */
await dona.inserir('agendamento_servicos', { agendamentoId: ag.id,
  servicoId: sv.id, ordem:1, duracaoMin:60, comissaoPct:0 });
let linhas = await dona.lista('agendamento_servicos', { agendamentoId: ag.id });
igual('sem preço na linha, o banco preenche com a escada',
  reais(linhas[0].preco), '95.00');

const agB = await dona.inserir('agendamentos', { salaoId: SALAO,
  clienteId: cli2.id, profissionalId: prof.id,
  inicio: emUtc(TERCA, 8), fim: emUtc(TERCA, 9),
  status:'confirmado', origem:'recepcao' });
await dona.inserir('agendamento_servicos', { agendamentoId: agB.id,
  servicoId: sv.id, ordem:1, duracaoMin:60, preco:0, comissaoPct:0 });
/* ⚠ ZERO É UM PREÇO, e não "faltou preencher". Cortesia, manutenção coberta,
   um acerto qualquer — se o banco reescrever isso, o sistema desfaz em
   silêncio o que a recepção combinou. */
igual('a cortesia de R$ 0,00 da recepção é respeitada',
  reais((await dona.lista('agendamento_servicos',
    { agendamentoId: agB.id }))[0].preco), '0.00');

const agC = await dona.inserir('agendamentos', { salaoId: SALAO,
  clienteId: cli2.id, profissionalId: prof.id,
  /* 13h, e não 7h: a jornada do teste é das 8h às 19h, e o banco recusa
     marcação fora dela com `check_violation`. O arquivo morria aqui por um
     motivo que não tem nada a ver com preço. */
  inicio: emUtc(TERCA, 13), fim: emUtc(TERCA, 14),
  status:'confirmado', origem:'recepcao' });
await dona.inserir('agendamento_servicos', { agendamentoId: agC.id,
  servicoId: sv.id, ordem:1, duracaoMin:60, preco:123, comissaoPct:0 });
igual('e um valor combinado à mão também',
  reais((await dona.lista('agendamento_servicos',
    { agendamentoId: agC.id }))[0].preco), '123.00');

/* ══════════════════════════════════════════════════════════════════════════
   3 — O PREÇO CONGELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · Mudar a regra depois não mexe no que já foi marcado');

const antes = await marcarPeloLink(emUtc(TERCA, 17));
igual('marcado por', reais(antes.valor), '95.00');
await dona.atualizar('precos_regras', r3.id, { preco: 300 });
const conferindo = await dona.lista('agendamento_servicos',
  { agendamentoId: antes.id });
/* É o que impede o pior defeito possível numa agenda: a cliente ver R$ 95 na
   terça, o dono subir a regra na quarta, e ela pagar R$ 300 no balcão. */
igual('e continua valendo o combinado, mesmo com a regra em R$ 300',
  reais(conferindo[0].preco), '95.00');
igual('a regra nova só vale para quem marcar de agora em diante',
  reais((await marcarPeloLink(emUtc(TERCA, 18))).valor), '300.00');
await dona.atualizar('precos_regras', r3.id, { preco: 95 });

/* ⚠ E O CONSERTO À MÃO CONTINUA VALENDO. "Combinei R$ 100 com ela" é a
   recepção fazendo o trabalho dela, e o gatilho é só no insert justamente para
   não desfazer isso na frente da cliente. */
await dona.atualizar('agendamento_servicos', linhas[0].id, { preco: 100 });
const corrigido = await dona.lista('agendamento_servicos', { agendamentoId: ag.id });
igual('a recepção corrige na mão e o banco respeita', reais(corrigido[0].preco),
  '100.00');

/* ══════════════════════════════════════════════════════════════════════════
   4 — O ESPELHO DA TELA CONTRA O POSTGRES
   ══════════════════════════════════════════════════════════════════════════ */
secao('4 · A tela responde o mesmo que o banco, caso a caso');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                   isMobile:true, hasTouch:true });
const pg = await ctx.newPage();
const erros = [];
pg.on('pageerror', e => erros.push(e.message));
await pg.goto(BASE + '/agendar.html?salao=' + SLUG);
await pg.waitForFunction(() => {
  const m = document.getElementById('capaMarca');
  return m && m.textContent.trim().length > 0;
}, null, { timeout: 15000 });

/* ⚠ A MATRIZ EXISTE PORQUE UM CASO SÓ NÃO PROVA NADA. Espelho de dinheiro
   erra nas beiras: o meio-dia da faixa, o dia que não é da regra, o
   profissional que tem regra própria. Cada linha abaixo é uma beira. */
/* ⚠ E A REGRA DA PROFISSIONAL SAI DE CENA PARA A MATRIZ RODAR.

   Ela tem o maior peso e ganha em TODA terça, a qualquer hora. Com ela ligada,
   os cinco casos abaixo davam a mesma resposta e a faixa de horário nunca era
   exercitada — a mutação que apagava a conferência de hora do espelho
   sobreviveu exatamente por isso. O teste comparava tela e banco, os dois
   respondiam 95, e nenhum dos dois estava olhando o relógio.

   Desligada, quem decide são as regras de dia e de hora, que é o que esta
   seção existe para medir. */
await dona.atualizar('precos_regras', r3.id, { ativo:false });

/* ⚠ E A PÁGINA PRECISA SER RECARREGADA DEPOIS DE MEXER NAS REGRAS.

   A `vitrine()` é lida uma vez, na abertura. Desligar a regra no banco e
   perguntar à página que já estava aberta compara o banco de AGORA com a tela
   de ANTES — e a reprovação que sai ("a tela diz 95, o banco diz 50") acusa um
   espelho quebrado que está inteiro.

   É o mesmo erro de leitura do outro lado: medir duas coisas em momentos
   diferentes e chamar a diferença de defeito. */
await pg.reload();
await pg.waitForFunction(() => {
  const m = document.getElementById('capaMarca');
  return m && m.textContent.trim().length > 0;
}, null, { timeout: 15000 });

const CASOS = [
  [TERCA,  9, 'terça 9h — dentro da faixa 8h-12h, vale 40'],
  [TERCA, 12, 'terça 12h — a beira: fora da faixa, volta 70'],
  [TERCA, 15, 'terça 15h — fora da faixa, vale a regra de dias'],
  [SABADO, 9, 'sábado 9h — nenhuma regra, vale o par'],
  [SABADO,16, 'sábado 16h — idem'],
];
for(const [dia, hora, rotulo] of CASOS){
  const noBanco = await precoNoBanco(emUtc(dia, hora));
  const naTela = await pg.evaluate(([id, pid, d, min]) => {
    const s = bd.servicos.find(x => x.id === id);
    return precoDoServico(s, pid, d, min);
  }, [sv.id, prof.id, dia, hora * 60]);
  igual(rotulo, reais(naTela), noBanco);
}
igual('nenhum erro na página da cliente', erros, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
