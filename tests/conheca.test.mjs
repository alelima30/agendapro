/* ===========================================================================
   A página dos anúncios (conheca.html) — o desenho do dono do AgendaPro

   Veio da ferramenta de design como um pacote de 14 MB que se montava no
   navegador; no site ela é estática (HTML montado, WebP, fontes em arquivo e
   um script pequeno). Aqui se confere o que faz a página vender sem mentir,
   abrir rápido e não perder o rastro de quem chegou:

     · título, descrição, canônico e imagem de compartilhamento;
     · todo "Criar conta grátis" leva utm_*, fbclid e gclid ao cadastro, e o
       cadastro já marca "Como você nos conheceu?";
     · nada de fora é carregado (sem Google Fonts, sem unpkg, sem React), e a
       página inteira pesa pouco;
     · os carrosséis e as perguntas funcionam sem o código da ferramenta;
     · o que o sistema não faz não está escrito (exportar dados);
     · quem pede "reduzir movimento" vê tudo parado;
     · a raiz do site continua levando ao login.

       python3 -m http.server 8099 --directory .
       PLAYWRIGHT=.../node_modules/playwright node tests/conheca.test.mjs
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, falhas = 0;
const diz = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });

async function abrir({ largura, busca = '', movimento = 'no-preference' }){
  const ctx = await nav.newContext({ viewport: { width: largura, height: 800 },
    isMobile: largura < 700, hasTouch: largura < 700, reducedMotion: movimento });
  const p = await ctx.newPage();
  const erros = [], deFora = [], bytes = { total: 0 };
  p.on('pageerror', e => erros.push(e.message));
  p.on('console', m => { if(m.type() === 'error') erros.push(m.text()); });
  p.on('request', r => { const u = r.url(); if(!u.startsWith(BASE.replace(/\/$/, '')) && !u.startsWith('data:')) deFora.push(u); });
  p.on('response', async r => { try{ bytes.total += (await r.body()).length; }catch(e){} });
  await p.goto(BASE + 'conheca.html' + busca);
  await p.waitForTimeout(900);
  return { ctx, p, erros, deFora, bytes };
}

console.log('\nAbrindo');
{
  const { ctx, p, erros, deFora } = await abrir({ largura: 1366 });
  const cab = await p.evaluate(() => ({
    titulo: document.title,
    desc: (document.querySelector('meta[name=description]') || {}).content || '',
    canonico: (document.querySelector('link[rel=canonical]') || {}).href || '',
    og: (document.querySelector('meta[property="og:image"]') || {}).content || '',
    h1: [...document.querySelectorAll('h1')].map(h => h.textContent.replace(/\s+/g, ' ').trim()),
    lang: document.documentElement.lang,
  }));
  diz(/AgendaPro/.test(cab.titulo) && cab.desc.length > 60, 'tem título e descrição para o Google', cab.titulo);
  diz(/conheca\.html$/.test(cab.canonico) && /lp\/og\.jpg$/.test(cab.og), 'link canônico e imagem de compartilhamento (WhatsApp, Instagram)');
  diz(fs.existsSync(path.join(RAIZ, 'lp/og.jpg')), 'e a imagem de compartilhamento existe no site');
  diz(cab.h1.length === 1 && /agenda online/i.test(cab.h1[0]) && /pronta hoje/.test(cab.h1[0]), 'um título só (h1), com a promessa', cab.h1.join(' | '));
  diz(cab.lang === 'pt-BR', 'a página se declara em português');
  diz(deFora.length === 0, 'nada vem de fora: sem Google Fonts, sem unpkg, sem React', deFora.slice(0, 3).join(' | '));
  diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));
  const fontes = await p.evaluate(async () => { await document.fonts.ready; return [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replace(/"/g, '')); });
  diz(fontes.includes('Montserrat') && fontes.includes('Plus Jakarta Sans'), 'as fontes do desenho carregam do próprio site', [...new Set(fontes)].join(', '));
  const orfaos = await p.evaluate(() => [...document.querySelectorAll('a[href^="#"]')].map(a => a.getAttribute('href'))
    .filter(h => h.length > 1 && !document.getElementById(h.slice(1))));
  diz(orfaos.length === 0, 'todo link do menu (#…) leva a uma seção que existe', orfaos.join(', '));
  diz(!/\{\{|sc-placeholder|__bundler|dc-runtime|blob:/.test(await p.content()), 'não sobrou nada do código da ferramenta ({{ }}, blob:, carregador)');
  await ctx.close();
}

console.log('\nOs botões levam o anúncio até o cadastro');
{
  const { ctx, p } = await abrir({ largura: 375, busca: '?utm_source=instagram&utm_campaign=lancamento&fbclid=abc123&lixo=<x>' });
  const links = await p.evaluate(() => [...document.querySelectorAll('a')].filter(a => /Criar conta/i.test(a.textContent)).map(a => a.getAttribute('href')));
  const alvo = new URL(links[0], BASE);
  diz(links.length >= 3 && links.every(h => h === links[0]), `todos os "Criar conta grátis" (${links.length}) vão para o mesmo endereço`);
  diz(alvo.pathname.endsWith('/criar.html') && alvo.searchParams.get('utm_source') === 'instagram'
      && alvo.searchParams.get('utm_campaign') === 'lancamento' && alvo.searchParams.get('fbclid') === 'abc123'
      && alvo.searchParams.get('origem') === 'pagina' && !alvo.searchParams.has('lixo'),
      'o cadastro recebe utm_*, fbclid e a origem — e só eles', links[0]);
  const entrar = await p.evaluate(() => [...document.querySelectorAll('a')].filter(a => /Entrar/.test(a.textContent)).map(a => a.getAttribute('href')));
  diz(entrar.length >= 2 && entrar.every(h => h === 'entrar.html'), '"Entrar" e "Entrar no painel" levam ao login do próprio site', entrar.join(' | '));
  const zap = await p.evaluate(() => { const a = document.getElementById('zapDuvida'); return a ? a.href : ''; });
  diz(/^https:\/\/wa\.me\/55\d{10,11}\?text=/.test(zap), '"Fale com a gente no WhatsApp" tem número e mensagem (antes era wa.me/ vazio)', zap);
  await p.goto(alvo.href); await p.waitForTimeout(800);
  diz(await p.evaluate(() => document.getElementById('fOrigem').value) === 'Instagram', 'e o cadastro já marca "Como você nos conheceu?" = Instagram');
  await ctx.close();
}

console.log('\nNo celular');
{
  const { ctx, p, erros, bytes } = await abrir({ largura: 375 });
  diz(await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth) === 0, 'a página não rola para o lado');
  await p.evaluate(async () => { for(let y = 0; y < document.body.scrollHeight; y += 400){ window.scrollTo(0, y); await new Promise(r => setTimeout(r, 60)); } });
  await p.waitForTimeout(800);
  const imgs = await p.evaluate(() => [...document.images].filter(i => i.offsetParent !== null || i.closest('[style*="preserve-3d"]'))
    .map(i => ({ src: i.getAttribute('src'), ok: i.complete && i.naturalWidth > 0, alt: !!i.alt, medida: !!(i.getAttribute('width') && i.getAttribute('height')) })));
  diz(imgs.length >= 8 && imgs.every(i => i.ok), 'todas as imagens carregam', JSON.stringify(imgs.filter(i => !i.ok)));
  diz(imgs.every(i => i.alt) && imgs.every(i => i.medida), 'e toda imagem tem texto alternativo e medida (a página não pula)');
  diz(imgs.every(i => /\.webp$/.test(i.src)), 'as imagens são WebP, no tamanho em que aparecem', imgs.map(i => i.src).filter(s => !/\.webp$/.test(s)).join(', '));
  const kb = Math.round(bytes.total / 1024);
  diz(kb < 1500, `a página inteira pesa ${kb} KB (era 14 MB)`, kb + ' KB');
  const texto = await p.evaluate(() => document.body.innerText);
  diz(!/undefined|NaN|\$\{|\{\{/.test(texto), 'nenhum "undefined", "NaN" ou {{…}} escapou para o texto');
  diz(!/exportar/i.test(texto), 'não promete "exportar tudo" — o sistema não tem exportação');
  diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));
  await ctx.close();
}

console.log('\nOs carrosséis e as perguntas, sem o código da ferramenta');
{
  const { ctx, p, erros } = await abrir({ largura: 1366 });
  const heroi = () => p.evaluate(() => ({ rotulo: document.querySelector('#heroiRotulo .sc-interp').textContent,
    frente: document.getElementById('heroiFrente').getAttribute('src'), verso: document.getElementById('heroiVerso').getAttribute('src'),
    giro: document.getElementById('heroiGiro').style.transform, cliente: document.querySelector('[data-dc-tpl="67"] .sc-interp').textContent }));
  const h0 = await heroi();
  await p.click('#heroiPontos button:nth-child(3)'); await p.waitForTimeout(200);
  const h1 = await heroi();
  diz(h0.rotulo === 'Salão de beleza' && h1.rotulo === 'Estética' && h1.cliente === 'Camila' && /rotateY\(-360deg\)/.test(h1.giro),
      'tocar no 3º pontinho do celular vira para "Estética", com a mensagem da Camila', JSON.stringify([h0.rotulo, h1]));
  diz(/nicho-estetica\.webp$/.test(h1.frente) || /nicho-estetica\.webp$/.test(h1.verso), 'e a tela da estética está no lado que aparece');
  const anel = () => p.evaluate(() => ({ titulo: document.querySelector('#anelTitulo .sc-interp').textContent, giro: document.getElementById('anel').style.transform }));
  await p.click('#anelPontos button:nth-child(4)'); await p.waitForTimeout(200);
  const a1 = await anel();
  diz(a1.titulo === 'Com a sua marca' && /rotateY\(-216deg\)/.test(a1.giro), 'tocar no 4º pontinho da roda gira para "Com a sua marca"', JSON.stringify(a1));
  const faq = () => p.evaluate(() => [...document.querySelectorAll('[data-faq]')].map(b => ({ aberta: b.getAttribute('aria-expanded') === 'true',
    resposta: !document.getElementById('faqR' + b.dataset.faq).hidden })));
  const f0 = await faq();
  diz(f0.length === 10 && f0[0].aberta && f0[0].resposta && f0.slice(1).every(x => !x.aberta && !x.resposta), 'dez perguntas, a primeira aberta, como no desenho');
  diz(await p.evaluate(() => [...document.querySelectorAll('[id^="faqR"]')].every(r => r.textContent.trim().length > 20)),
      'e todas as respostas estão no HTML (o Google lê, mesmo fechadas)');
  await p.click('[data-faq="2"]'); await p.click('[data-faq="0"]'); await p.waitForTimeout(100);
  const f1 = await faq();
  diz(f1[2].aberta && f1[2].resposta && !f1[0].aberta && !f1[0].resposta, 'tocar abre e fecha cada pergunta (aria-expanded junto)');
  await p.mouse.move(5, 5);
  await p.waitForTimeout(3600);
  diz((await anel()).titulo !== 'Com a sua marca', 'e a roda segue girando sozinha');
  diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));
  await ctx.close();
}

console.log('\nQuem pede menos movimento');
{
  const { ctx, p } = await abrir({ largura: 375, movimento: 'reduce' });
  const antes = await p.evaluate(() => document.getElementById('anel').style.transform + '|' + document.getElementById('heroiGiro').style.transform);
  await p.waitForTimeout(4500);
  const depois = await p.evaluate(() => document.getElementById('anel').style.transform + '|' + document.getElementById('heroiGiro').style.transform);
  diz(antes === depois, 'com "reduzir movimento", nada gira sozinho', antes + ' → ' + depois);
  await ctx.close();
}

console.log('\nA raiz do site continua levando ao login');
{
  const raiz = fs.readFileSync(path.join(RAIZ, 'index.html'), 'utf8');
  diz(/http-equiv="refresh" content="0; url=entrar\.html"/.test(raiz) && !/conheca/.test(raiz),
      'index.html segue indo para entrar.html — a página de anúncio é à parte');
}

await nav.close();
console.log(falhas ? `\n✗ ${falhas} de ${ok + falhas} falharam.` : `\n✓ ${ok} passaram, 0 falharam`);
process.exit(falhas ? 1 : 0);
