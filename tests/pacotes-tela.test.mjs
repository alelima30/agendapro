/* ===========================================================================
   AgendaPro — as TELAS do pacote, abertas num navegador

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/pacotes-tela.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   O `pacotes.test.mjs` cobre a regra: quem paga zero, quem não paga, sessões,
   validade, dias. Ele passou 24 de 24 — e as duas telas estavam QUEBRADAS.

   Ele insere direto no banco. A tela faz outra coisa: monta objetos, chama o
   `salvar()`, espera o `dados.js` traduzir, e redesenha com o que voltou. É
   nesse caminho que estavam os quatro defeitos, e nenhum deles daria erro
   visível:

     · `pacote_servicos` sem coluna `id` — o `dados.js` recusa a gravação
       INTEIRA, e o pacote nascia sem serviço nenhum, dizendo na própria tela
       que "não vale para nada ainda";
     · o painel criando a linha sem `id` — a coluna no banco não bastava,
       porque o `dados.js` confere ANTES de mandar;
     · `await carregarTudo();` sem o `bd =` — o vínculo ia para o banco e a
       lista continuava dizendo "Ninguém ainda". O projeto já tinha caído nisto
       com o caixa, e o aviso estava escrito no arquivo;
     · `p.venceEm` em vez de `p.vence_em` — `Dados.chamar()` devolve o JSON cru
       do Postgres, e `undefined >= '2026-09-16'` é falso. Nenhum pacote cobria
       nada, e a cliente com pacote via o preço cheio, sem um erro sequer.

   Quatro defeitos mudos, num caminho que só existe quando alguém CLICA.
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
await dona.criarConta({ email:`tp-dona-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Dona', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Telas Pacote ' + m,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:60, tetoOnlinePct:100, tetoOnlineRajada:100 } });
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'20:00' });
await dona.inserir('servicos', { salaoId:SALAO, nome:'Manutenção de unha',
  preco:40, duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });

/* ══════════════════════════════════════════════════════════════════════════
   1 — A ABA PACOTES, CLICADA
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O PAINEL ─────────────────────────────────────────────────');
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });
/* ⚠ O Playwright DESCARTA alert() sozinho. Sem este ouvinte, um "Não consegui
   vincular" apareceria e sumiria sem deixar rastro — e eu ficaria procurando
   o defeito na tela quando a tela estava me dizendo qual era. */
p.on('dialog', async d => { erros.push('ALERT: ' + d.message()); await d.dismiss(); });
await p.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(3500);

e('a aba Pacotes aparece no menu',
  await p.isVisible('a:has-text("Pacotes"), button:has-text("Pacotes")'));
await p.click('a:has-text("Pacotes"), button:has-text("Pacotes")');
await p.waitForTimeout(1200);
const vazio = await p.evaluate(() =>
  (document.getElementById('listaPacotes') || {}).innerText || '');
e('a tela vazia explica o que é um pacote — ' + JSON.stringify(vazio.slice(0, 40)),
  /Nenhum pacote/i.test(vazio), vazio.slice(0, 200));

await p.click('#btNovoPacote');
await p.waitForTimeout(700);
e('o formulário de novo pacote abre', await p.isVisible('#pkNome'));

await p.fill('#pkNome', 'Unha em Dia');
await p.fill('#pkPreco', '140');
await p.fill('#pkSessoes', '4');
await p.fill('#pkValidade', '90');
// Deixa só segunda, terça e quarta ligados.
await p.evaluate(() => {
  document.querySelectorAll('#pkDias button').forEach((b, i) => {
    const querido = [1,2,3].includes(i);
    if(b.classList.contains('on') !== querido) b.click();
  });
  document.querySelector('#pkServicos input').checked = true;
});
await p.waitForTimeout(300);
await p.click("#fundo button:has-text(\"Salvar\")");
await p.waitForTimeout(1800);

const depois = await p.evaluate(() =>
  (document.getElementById('listaPacotes') || {}).innerText || '');
e('o pacote aparece na lista', /Unha em Dia/.test(depois), depois.slice(0, 250));
e('com as sessões e os dias escritos — '
  + JSON.stringify((depois.match(/4 sess[^\n]*/) || [''])[0]),
  /4 sess/.test(depois) && /seg/.test(depois), depois.slice(0, 250));
e('e diz que ninguém está vinculado ainda', /Ningu[ée]m ainda/i.test(depois),
  depois.slice(0, 300));

/* ── A cliente precisa existir para ser vinculada ────────────────────────── */
const maria = aba();
const TEL = '+5551' + (200000000 + (Date.now() % 79999999));
await maria.criarConta({ email:`tp-maria-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Maria Telas', telefone: TEL });
const svs = await dona.lista('servicos', { salaoId: SALAO });
const quando = (() => { const d = new Date(Date.now() + 3*864e5);
  d.setUTCHours(13,0,0,0); return d.toISOString(); })();
await maria.chamar('agendar', { p_profissional: prof.id, p_inicio: quando,
  p_servicos:[svs[0].id], p_nome:'Maria Telas', p_telefone: TEL });

await p.reload();
await p.waitForTimeout(3500);
await p.click('a:has-text("Pacotes"), button:has-text("Pacotes")');
await p.waitForTimeout(1200);
await p.click('button:has-text("+ Vincular cliente")');
await p.waitForTimeout(800);
e('a janela de vincular abre com a lista de clientes',
  await p.isVisible('#pkCliente'));
e('e avisa que a cliente precisa de conta',
  /conta/i.test(await p.evaluate(() =>
    (document.querySelector('.modal, dialog, .janela') || document.body).innerText)),
  'sem esse aviso a dona vincula e não entende por que não funciona');

const antesDeVincular = await p.evaluate(() => ({
  temSelect: !!document.getElementById('pkCliente'),
  clientes: (bd.clientes || []).length,
  opcoes: document.querySelectorAll('#pkCliente option').length,
  vinculos: (bd.pacote_clientes || []).length,
}));
console.log('      antes de vincular: ' + JSON.stringify(antesDeVincular));
await p.click("#fundo button:has-text(\"Vincular\")");
await p.waitForTimeout(3000);
const depoisDeVincular = await p.evaluate(() => ({
  modalAberto: !!document.querySelector('#fundo.on'),
  vinculos: (bd.pacote_clientes || []).length,
}));
console.log('      depois: ' + JSON.stringify(depoisDeVincular));
const comCliente = await p.evaluate(() =>
  (document.getElementById('listaPacotes') || {}).innerText || '');
e('a Maria aparece dentro do pacote', /Maria Telas/.test(comCliente),
  comCliente.slice(0, 400));
e('com a data de vencimento', /vence/i.test(comCliente), comCliente.slice(0, 400));
e('sem erro de JavaScript no painel',
  erros.length === 0, erros.slice(0, 3).join(' | '));

/* ══════════════════════════════════════════════════════════════════════════
   2 — A PÁGINA DA CLIENTE, LOGADA
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O LINK DA CLIENTE ────────────────────────────────────────');
const c = await ctx.newPage();
const errosC = [];
c.on('pageerror', x => errosC.push('pageerror: ' + x.message));
c.on('console', x => { if(x.type() === 'error') errosC.push('console: ' + x.text()); });
await c.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, maria.sessao()]);
await c.goto(BASE + '/agendar.html?salao=' + SLUG);
await c.waitForTimeout(3000);

const carregou = await c.evaluate(() => ({
  quantos: (typeof meusPacotes !== 'undefined' ? meusPacotes : []).length,
  nome: (typeof meusPacotes !== 'undefined' && meusPacotes[0]) ? meusPacotes[0].nome : null,
}));
e('a página carregou o pacote da Maria — ' + JSON.stringify(carregou),
  carregou.quantos === 1 && carregou.nome === 'Unha em Dia',
  'se ficou zero, a cadeia painel → banco → link está quebrada');

await c.click('.boas-cta');
await c.waitForTimeout(1200);
const naLista = await c.evaluate(() =>
  [...document.querySelectorAll('#listaServicos .vv')].map(v => v.textContent.trim()));
console.log('      o que aparece no lugar do preço: ' + JSON.stringify(naLista));
/* ⚠ Pode legitimamente mostrar R$ 40 se HOJE não for um dos dias do pacote —
   o pacote foi criado de segunda a quarta. Então a asserção aceita os dois, e
   o que ela cobra é que o texto seja UM DOS DOIS, nunca vazio nem quebrado. */
e('o preço ou o aviso do pacote aparecem',
  naLista.length > 0 && naLista.every(v => /R\$|pacote/i.test(v)),
  JSON.stringify(naLista));

const hojeVale = await c.evaluate(() => {
  const p = (typeof meusPacotes !== 'undefined' ? meusPacotes : [])[0];
  return p ? (p.dias || []).includes(new Date().getDay()) : false;
});
console.log('      hoje é dia de pacote? ' + (hojeVale ? 'sim' : 'não'));
if(hojeVale){
  e('e como hoje vale, diz "no seu pacote"',
    naLista.some(v => /pacote/i.test(v)), JSON.stringify(naLista));
} else {
  e('e como hoje NÃO vale, mostra o preço normal',
    naLista.every(v => /R\$/.test(v)), JSON.stringify(naLista));
}
e('sem erro de JavaScript no link',
  errosC.length === 0, errosC.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
