/* ===========================================================================
   AgendaPro — o interruptor de comanda e caixa, clicado num navegador

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/sem-comanda-tela.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   O `sem-comanda.test.mjs` cobre a regra: o que o banco faz quando o
   atendimento é concluído. Ele insere direto, e passou 36 de 36 — o que não
   diz nada sobre o caminho que existe só quando alguém CLICA:

     painel → dados.js → cfg no banco → menu redesenhado.

   Foi exatamente aí que os pacotes esconderam quatro defeitos mudos, e um
   deles — `await carregarTudo()` sem o `bd =` — o projeto já tinha cometido
   antes, com o caixa.

   E aqui há um lugar a mais para errar: a peneira do `cfg`. O banco só
   desliga quando o valor é literalmente falso; a tela, se usasse
   `!!cfg.usaComanda`, leria a string `'false'` como VERDADEIRA. Aba Caixa na
   tela, comanda automática no banco, e o dono sem entender. A seção 4 mede
   isso com o valor que causaria o estrago.
   =========================================================================== */
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);

function aba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(RAIZ + '/dados.js','utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const m = Date.now().toString(36);
const dona = aba();
await dona.criarConta({ email:`sct-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Dona', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Sem Comanda Tela ' + m,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'20:00' });
const corte = await dona.inserir('servicos', { salaoId:SALAO, nome:'Corte',
  preco:50, duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });
const cliente = await dona.inserir('clientes', { salaoId:SALAO, nome:'Joana',
  telefone: String(51900000000 + (Date.now() % 89000000)) });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });
p.on('dialog', async d => { erros.push('ALERT: ' + d.message()); await d.dismiss(); });
await p.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(3500);

const abas = () => p.evaluate(() =>
  [...document.querySelectorAll('#abas .aba')].map(b => b.dataset.chave));

/* ══════════════════════════════════════════════════════════════════════════
   1 — LIGADO É O PADRÃO, E A ABA CAIXA ESTÁ LÁ
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O PADRÃO ─────────────────────────────────────────────────');
const antes = await abas();
console.log('      abas: ' + JSON.stringify(antes));
e('a aba Caixa aparece num salão novo', antes.includes('caixa'),
  'se sumir por padrão, todo salão de hoje perde a gaveta sem pedir');

/* ══════════════════════════════════════════════════════════════════════════
   2 — DESLIGANDO PELA TELA
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── DESLIGANDO ───────────────────────────────────────────────');
await p.click('button:has-text("Meu salão"), a:has-text("Meu salão")');
await p.waitForTimeout(1200);
e('a régua existe na tela do salão', await p.isVisible('#reguaComanda'));
const escolhido = () => p.evaluate(() =>
  (document.querySelector('#reguaComanda button.on') || {}).textContent || '');
e('e nasce em "Com comanda e caixa" — ' + JSON.stringify(await escolhido()),
  /Com comanda/i.test(await escolhido()));

const explicaLigado = await p.evaluate(() =>
  (document.getElementById('explicaComanda') || {}).innerText || '');
e('com a explicação de quem usa — ' + JSON.stringify(explicaLigado.slice(0, 50)),
  /comanda/i.test(explicaLigado), explicaLigado);

await p.click('#reguaComanda button:has-text("Só a agenda")');
await p.waitForTimeout(400);
e('a régua passa para "Só a agenda" — ' + JSON.stringify(await escolhido()),
  /S[óo] a agenda/i.test(await escolhido()));
const explicaDesligado = await p.evaluate(() =>
  (document.getElementById('explicaComanda') || {}).innerText || '');
console.log('      ao desmarcar: ' + JSON.stringify(explicaDesligado.slice(0, 90)));
/* A frase que decide se o dono clica ou não: ele precisa saber que o
   relatório continua funcionando e que nada do que já fechou se perde. */
e('desmarcando, a tela promete que o relatório continua',
  /relat[óo]rio/i.test(explicaDesligado) && /perde/i.test(explicaDesligado),
  explicaDesligado);

await p.click('#tela-salao button:has-text("Salvar")');
await p.waitForTimeout(2500);

const depois = await abas();
console.log('      abas: ' + JSON.stringify(depois));
e('a aba Caixa some do menu na hora', !depois.includes('caixa'), JSON.stringify(depois));
e('e o resto do menu continua inteiro',
  depois.includes('agenda') && depois.includes('hoje') && depois.includes('salao'),
  JSON.stringify(depois));

/* ⚠ RECARREGA: até aqui eu poderia estar olhando o que a própria tela montou
   na memória, que é verdade mesmo quando nada foi gravado. */
await p.reload();
await p.waitForTimeout(3500);
const apesDeRecarregar = await abas();
e('recarregando, a aba continua fora — foi ao banco',
  !apesDeRecarregar.includes('caixa'), JSON.stringify(apesDeRecarregar));
const noBanco = await dona.chamar('usa_comanda', { p_salao: SALAO });
e('e o banco concorda com a tela — ' + JSON.stringify(noBanco), noBanco === false,
  'a tela escondeu a aba e o banco continua achando que usa comanda');

/* ══════════════════════════════════════════════════════════════════════════
   3 — O CARTÃO DA GAVETA NO "HOJE"

   A aba some, mas o cartão do Hoje dizia "Abra em Caixa para ter o que
   conferir no fim do dia" — apontando para uma aba que não existe mais. Na
   primeira tela que o dono abre, todo santo dia.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── A TELA HOJE ──────────────────────────────────────────────');
await p.click('button:has-text("Hoje"), a:has-text("Hoje")');
await p.waitForTimeout(2500);
const hoje = await p.evaluate(() =>
  (document.getElementById('tela-hoje') || document.body).innerText || '');
e('o Hoje não manda abrir uma aba que sumiu',
  !/Abra em Caixa/i.test(hoje), hoje.slice(0, 300));
e('e continua mostrando o faturamento', /faturamento/i.test(hoje),
  hoje.slice(0, 300));

/* ══════════════════════════════════════════════════════════════════════════
   4 — ⚠ A PENEIRA: A STRING 'false'

   `!!'false'` é VERDADEIRO em JavaScript. Se a tela usasse isso, um `cfg`
   gravado como texto — por uma importação, por uma correção à mão no
   Supabase — deixaria a aba Caixa na tela com o banco já desligado.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O CFG COMO TEXTO ─────────────────────────────────────────');
await dona.atualizar('saloes', SALAO, { cfg:{ usaComanda:'false' } });
await p.reload();
await p.waitForTimeout(3500);
const comTexto = await abas();
const bancoTexto = await dona.chamar('usa_comanda', { p_salao: SALAO });
console.log('      banco: ' + JSON.stringify(bancoTexto)
          + ' · abas: ' + JSON.stringify(comTexto));
e('com a string "false", tela e banco continuam concordando',
  bancoTexto === false && !comTexto.includes('caixa'),
  'tela e banco discordando sobre dinheiro é o defeito mais caro deste projeto');

/* E o contrário: lixo no cfg cai no lado seguro, LIGADO, nos dois. */
await dona.atualizar('saloes', SALAO, { cfg:{ usaComanda:'abacaxi' } });
await p.reload();
await p.waitForTimeout(3500);
const comLixo = await abas();
const bancoLixo = await dona.chamar('usa_comanda', { p_salao: SALAO });
console.log('      banco: ' + JSON.stringify(bancoLixo)
          + ' · abas: ' + JSON.stringify(comLixo));
e('com lixo no cfg, os dois caem em LIGADO',
  bancoLixo === true && comLixo.includes('caixa'),
  'um erro de digitação não pode apagar a comanda de ninguém');

/* ══════════════════════════════════════════════════════════════════════════
   5 — O BOTÃO "ABRIR COMANDA" NA AGENDA
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O BOTÃO NA FICHA DO ATENDIMENTO ──────────────────────────');
const FUSO = 'America/Sao_Paulo';
const hojeLa = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO,
  year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date());
const ini = hojeLa + 'T13:00:00Z';
const ag = await dona.inserir('agendamentos', { salaoId: SALAO,
  clienteId: cliente.id, profissionalId: prof.id, inicio: ini,
  fim: new Date(new Date(ini).getTime() + 60 * 60000).toISOString(),
  status:'confirmado', origem:'recepcao', valorPrevisto: 50 });
await dona.inserir('agendamento_servicos', { agendamentoId: ag.id,
  servicoId: corte.id, ordem:1, duracaoMin:60, preco:50, comissaoPct:0 });

const temBotaoComanda = async () => {
  await p.reload();
  await p.waitForTimeout(3500);
  await p.evaluate(([dia, id]) => { diaAtual = dia; irPara('agenda'); abrirDetalhe(id); },
                   [hojeLa, ag.id]);
  await p.waitForTimeout(900);
  const txt = await p.evaluate(() =>
    (document.getElementById('fundo') || document.body).innerText || '');
  await p.evaluate(() => fecharModal());
  return /Abrir comanda/i.test(txt);
};

/* Com o interruptor LIGADO (o cfg está com lixo, que cai em ligado). */
e('com comanda ligada, a ficha oferece "Abrir comanda"', await temBotaoComanda());

await dona.atualizar('saloes', SALAO, { cfg:{ usaComanda:false } });
e('desligada, o botão some — senão seria uma segunda contagem do mesmo '
  + 'atendimento', !(await temBotaoComanda()));

e('e nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
