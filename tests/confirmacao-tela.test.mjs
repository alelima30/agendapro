/* ===========================================================================
   AgendaPro — a confirmação, nas duas telas

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/confirmacao-tela.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   O `confirmacao.test.mjs` mede o banco: que status nasce, que mensagem sai e
   quando. Nada disso diz o que a CLIENTE lê depois de marcar — e é a frase
   dela que faz a diferença entre uma pessoa tranquila e uma pessoa ligando
   para o salão.

   Duas telas, dois riscos diferentes:

     · a da cliente promete demais — "Agendado!" e uma bolha de WhatsApp com
       "Seu horário está confirmado" de um horário que o dono não olhou;
     · a do dono não mostra nada — o pendente fica escondido numa etiqueta
       cinza dentro da ficha, e ele passa o dia sem saber que tem gente
       esperando.
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
await dona.criarConta({ email:`cft-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Dona', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Confirma Tela ' + m,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.atualizar('saloes', SALAO,
  { cfg:{ diasLiberados:60, tetoOnlinePct:100, tetoOnlineRajada:100 } });
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'20:00' });
await dona.inserir('servicos', { salaoId:SALAO, nome:'Corte', preco:50,
  duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });

/* ══════════════════════════════════════════════════════════════════════════
   1 — A RÉGUA NO PAINEL
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O PAINEL ─────────────────────────────────────────────────');
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

await p.click('button:has-text("Meu salão"), a:has-text("Meu salão")');
await p.waitForTimeout(1200);
e('a régua da confirmação existe', await p.isVisible('#reguaConfirma'));

const escolhido = () => p.evaluate(() =>
  (document.querySelector('#reguaConfirma button.on') || {}).textContent || '');
e('e nasce em "Já entra confirmado" — ' + JSON.stringify(await escolhido()),
  /entra confirmado/i.test(await escolhido()),
  'se nascesse no outro lado, todo salão que já usa o link acordaria com '
  + 'pendências que ninguém pediu');

await p.click('#reguaConfirma button:has-text("Eu confirmo")');
await p.waitForTimeout(400);
const explica = await p.evaluate(() =>
  (document.getElementById('explicaConfirma') || {}).innerText || '');
console.log('      explicação: ' + JSON.stringify(explica.slice(0, 110)));
/* As duas coisas que o dono precisa saber antes de clicar: a cadeira fica
   guardada, e a mensagem espera por ele. */
e('a tela diz que o horário fica guardado para a cliente',
  /guardada|guardado/i.test(explica), explica);
e('e que a mensagem só sai quando ele confirmar',
  /confirmar/i.test(explica) && /whatsapp/i.test(explica), explica);

await p.click('#tela-salao button:has-text("Salvar")');
await p.waitForTimeout(2500);
const noBanco = await dona.chamar('confirma_automatico', { p_salao: SALAO });
e('e o banco concorda — ' + JSON.stringify(noBanco), noBanco === false,
  'a tela mostrou uma coisa e o banco guardou outra');

/* ══════════════════════════════════════════════════════════════════════════
   2 — ⚠ A TELA DA CLIENTE NÃO PODE PROMETER O QUE O DONO NÃO DISSE
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── O LINK DA CLIENTE ────────────────────────────────────────');
const c = await ctx.newPage();
const errosC = [];
c.on('pageerror', x => errosC.push('pageerror: ' + x.message));
c.on('console', x => { if(x.type() === 'error') errosC.push('console: ' + x.text()); });
c.on('dialog', async d => { errosC.push('ALERT: ' + d.message()); await d.dismiss(); });

const maria = aba();
const TEL = '+5551' + (200000000 + (Date.now() % 79999999));
await maria.criarConta({ email:`cft-maria-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Maria Cliente', telefone: TEL });
await c.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, maria.sessao()]);
await c.goto(BASE + '/agendar.html?salao=' + SLUG);
await c.waitForTimeout(3500);

const politica = await c.evaluate(() =>
  typeof salaoConfirmaSozinho !== 'undefined' ? salaoConfirmaSozinho : 'não existe');
e('a página recebeu a política do banco — ' + JSON.stringify(politica),
  politica === false,
  'se vier true, a tela vai prometer confirmação de um horário pendente');

// Caminho de verdade, clicado: capa → serviço → profissional → dia → hora.
await c.click('.boas-cta');
await c.waitForTimeout(1000);
await c.click('#listaServicos .opcao');
await c.waitForTimeout(700);
await c.click('#btPrincipal');
await c.waitForTimeout(1000);
await c.click('#listaProfs .opcao');
await c.waitForTimeout(700);
await c.click('#btPrincipal');
await c.waitForTimeout(3000);
await c.click('#listaHoras .hora');
await c.waitForTimeout(700);
await c.click('#btPrincipal');            // quando → dados
await c.waitForTimeout(1500);

/* ⚠ OS CAMPOS SÃO PREENCHIDOS À MÃO, e não deixados para o preenchimento
   automático da sessão.

   Sem isto o teste parava em `dados` para sempre: o `salvarDados()` recusa
   nome curto ou telefone sem DDD e só reescreve o aviso — não avança, não
   alerta, não erra. Dali em diante todas as medidas reprovavam apontando para
   a tela de "pronto", que nunca tinha sido alcançada. */
await c.fill('#dNome', 'Maria Cliente');
await c.fill('#dTel', '51988887777');
await c.waitForTimeout(300);
await c.click('#btPrincipal');            // dados → confirmar
await c.waitForTimeout(1500);
console.log('      passo antes de confirmar: '
  + await c.evaluate(() => document.body.getAttribute('data-passo')));
await c.click('#btPrincipal');            // confirmar de verdade
await c.waitForTimeout(4000);

const tela = await c.evaluate(() => ({
  passo:  document.body.getAttribute('data-passo'),
  titulo: (document.querySelector('#p-pronto h2') || {}).textContent || '',
  texto:  (document.getElementById('p-pronto') || document.body).innerText || '',
}));
console.log('      passo: ' + tela.passo + ' · título: ' + JSON.stringify(tela.titulo));
e('a marcação chegou ao fim', tela.passo === 'pronto', JSON.stringify(tela));
e('o título não afirma que está agendado — ' + JSON.stringify(tela.titulo),
  !/^Agendado/i.test(tela.titulo), tela.titulo);
e('a tela diz que ela receberá uma mensagem de confirmação',
  /mensagem de confirma/i.test(tela.texto), tela.texto.slice(0, 300));
e('e que o horário fica guardado para ela',
  /guardado para você/i.test(tela.texto), tela.texto.slice(0, 300));
/* ⚠ A BOLHA DO WHATSAPP NÃO PODE APARECER AQUI. Ela mostra a confirmação que
   o banco acabou de enfileirar; neste caminho a mensagem só nasce quando o
   dono confirmar, e desenhá-la seria simular um envio que não houve. */
e('e NÃO mostra uma confirmação de WhatsApp que ainda não existe',
  !/est[áa] confirmado/i.test(tela.texto), tela.texto.slice(0, 400));

const ags = await dona.lista('agendamentos', { salaoId: SALAO });
const novo = ags[ags.length - 1];
e('e no banco o horário está pendente — ' + JSON.stringify(novo && novo.status),
  !!novo && novo.status === 'pendente', JSON.stringify(novo && novo.status));

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ O DONO PRECISA VER QUE TEM GENTE ESPERANDO
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\n── A FAIXA NA AGENDA ────────────────────────────────────────');
await p.reload();
await p.waitForTimeout(3500);
await p.click('button:has-text("Agenda"), a:has-text("Agenda")');
await p.waitForTimeout(1800);

const faixa = await p.evaluate(() =>
  (document.getElementById('aConfirmar') || {}).innerText || '');
console.log('      faixa: ' + JSON.stringify(faixa.slice(0, 90)));
e('a faixa aparece no topo da agenda', /confirma/i.test(faixa), faixa.slice(0, 200));
e('com o nome de quem está esperando', /Maria Cliente/.test(faixa),
  faixa.slice(0, 300));

await p.click('#aConfirmar button:has-text("Confirmar")');
await p.waitForTimeout(2500);
const depois = await p.evaluate(() =>
  (document.getElementById('aConfirmar') || {}).innerText || '');
e('confirmando, a faixa esvazia', depois.trim() === '', depois.slice(0, 200));

const agora = (await dona.lista('agendamentos', { id: novo.id }))[0];
e('e o horário ficou confirmado no banco — ' + JSON.stringify(agora.status),
  agora.status === 'confirmado');

const notifs = await dona.lista('notificacoes', { agendamentoId: novo.id });
console.log('      notificações: ' + JSON.stringify(notifs.map(x => x.tipo)));
e('e a confirmação foi enfileirada só agora',
  notifs.some(x => x.tipo === 'confirmacao'),
  'o dono confirmou pela tela e a cliente não vai saber');

e('nada disso deu erro de JavaScript no painel', erros.length === 0,
  erros.slice(0, 3).join(' | '));
e('nem no link da cliente', errosC.length === 0, errosC.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
