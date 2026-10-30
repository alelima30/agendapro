/* ===========================================================================
   AgendaPro — o que a auditoria de segurança achou, nas páginas

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/travas.test.mjs

   O banco tem o tests/travas.test.sql. Aqui, as páginas:

     1. as telas sensíveis (painel, administração, entrar, criar conta, nova
        senha, convite) não abrem dentro de um quadro de outro site — o
        "clickjacking", que o GitHub Pages não deixa barrar por cabeçalho;
     2. o link da cliente abre num quadro, de propósito (o salão pode pôr o
        agendamento no próprio site);
     3. aberto normalmente, o painel aparece como sempre;
     4. o e-mail digitado na tela de entrar volta escapado: código dentro
        dele vira texto, e não roda.
   =========================================================================== */
import { createRequire } from 'node:module';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
const secao = t => console.log('\n' + t);

const nav = await chromium.launch({ executablePath: CHROMIUM });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 e 2. Dentro de um quadro de outro site');
const SENSIVEIS = ['app.html?demo=1', 'admin.html', 'entrar.html', 'criar.html',
                   'nova-senha.html', 'convite.html?t=x'];
for(const pagina of SENSIVEIS.concat(['agendar.html?salao=qualquer'])){
  const ctx = await nav.newContext();
  const p = await ctx.newPage();
  // Uma página "de fora": about:blank tem outra origem que a do AgendaPro.
  await p.setContent(`<iframe id="q" src="${BASE}/${pagina}" width="800" height="600"></iframe>`);
  await p.waitForTimeout(2500);
  const quadro = p.frames().find(f => f !== p.mainFrame());
  // Protegida = o quadro sumiu, OU a página tomou a janela inteira (o
  // navegador às vezes deixa o quadro levar a janela para o endereço certo).
  const tomouAJanela = p.url().startsWith(BASE);
  const escondida = !tomouAJanela && quadro
    ? await quadro.evaluate(() => document.documentElement.style.display === 'none').catch(() => false)
    : false;
  const nome = pagina.split('?')[0];
  if(nome === 'agendar.html'){
    verdade('o link da cliente abre num quadro, de propósito', !tomouAJanela && !escondida);
  } else {
    verdade(`${nome} não aparece dentro do quadro de outro site`, tomouAJanela || escondida,
      `url=${p.url()} escondida=${escondida}`);
  }
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Aberto normalmente');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  await p.goto(BASE + '/app.html?demo=1');
  await p.waitForFunction(() => typeof pintar === 'function', null, { timeout: 15000 });
  verdade('o painel aparece como sempre',
    await p.evaluate(() => document.documentElement.style.display !== 'none'
      && document.body.getBoundingClientRect().height > 100));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. O e-mail na tela de entrar');
{
  const ctx = await nav.newContext();
  const p = await ctx.newPage();
  await p.addInitScript(b => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' }; }, BASE);
  await p.goto(BASE + '/entrar.html');
  await p.waitForFunction(() => typeof esqueci === 'function', null, { timeout: 15000 });
  const r = await p.evaluate(async () => {
    Dados.pedirNovaSenha = async () => true;   // sem mandar e-mail de verdade
    document.getElementById('email').value = '<img src=x onerror="window.__xss=1">@x.com';
    await esqueci();
    await new Promise(res => setTimeout(res, 300));
    const recado = document.getElementById('recado');
    return { rodou: !!window.__xss, img: !!recado.querySelector('img'), texto: recado.innerText };
  });
  verdade('código dentro do e-mail não roda', !r.rodou && !r.img, JSON.stringify(r));
  verdade('e aparece como texto, do jeito que foi digitado', r.texto.includes('<img src=x'), r.texto);
  await ctx.close();
}

await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
