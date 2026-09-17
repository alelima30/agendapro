/* ===========================================================================
   AgendaPro — o QR no painel

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/qr-tela.test.mjs

   O `qr.test.js` prova que o desenho está certo — a matemática, a estrutura, a
   volta. Isto aqui prova a outra metade: que ele APARECE, no lugar onde o
   texto do painel promete que ele está.

   O cartão do link diz "imprime como QR no espelho" desde sempre. A frase
   estava lá e o quadradinho não — o dono lia, procurava e não achava. Uma
   promessa escrita sem nada por trás é pior que promessa nenhuma, porque a
   pessoa conclui que ela é quem não está entendendo.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });

await p.goto(BASE + 'app.html?demo=1');
await p.waitForTimeout(2200);
await p.click('.aba[data-chave="publico"]');
await p.waitForTimeout(1200);

const cartao = await p.evaluate(() => {
  const c = document.getElementById('qrDoLink');
  const svg = c && c.querySelector('svg');
  return {
    temSvg:  !!svg,
    caixa:   svg ? svg.getAttribute('viewBox') : null,
    rotulo:  svg ? svg.getAttribute('aria-label') : null,
    largura: c ? Math.round(c.getBoundingClientRect().width) : 0,
    link:    (document.getElementById('linkPublico') || {}).value || '',
    texto:   (c && c.closest('.aviso') ? c.closest('.aviso').innerText : ''),
  };
});
console.log('      ' + JSON.stringify({ caixa: cartao.caixa, largura: cartao.largura }));

e('o QR é desenhado no cartão do link', cartao.temSvg,
  'a frase "imprime como QR" continua prometendo o que não existe');
e('com a zona de silêncio de quatro módulos dos dois lados — ' + cartao.caixa,
  /^0 0 (\d+) \1$/.test(cartao.caixa || '')
  && Number((cartao.caixa || '').split(' ')[2]) >= 29,
  cartao.caixa);
e('e com rótulo para quem usa leitor de tela',
  /QR/i.test(cartao.rotulo || ''), cartao.rotulo);
e('ocupa um canto do cartão, não meia tela',
  cartao.largura > 80 && cartao.largura < 200, String(cartao.largura));
e('o botão de baixar para imprimir está lá',
  /Baixar para imprimir/i.test(cartao.texto), cartao.texto.slice(0, 200));

/* ⚠ O QR TEM QUE SER DO LINK QUE ESTÁ NA CAIXA AO LADO, e não de um endereço
   parecido. Um QR que leva ao salão errado é o defeito mais caro possível
   aqui: ele é impresso, colado na parede, e manda cliente para outro lugar
   durante meses. Refeito pelo próprio gerador e comparado módulo a módulo. */
const confere = await p.evaluate(() => {
  const desenhado = document.getElementById('qrDoLink').querySelector('svg')
    .querySelector('path').getAttribute('d');
  const refeito = new DOMParser()
    .parseFromString(QR.svg(document.getElementById('linkPublico').value), 'image/svg+xml')
    .querySelector('path').getAttribute('d');
  return { iguais: desenhado === refeito, modulos: (desenhado.match(/M/g) || []).length };
});
e('e o desenho é exatamente o do link que está na caixa — '
  + confere.modulos + ' módulos', confere.iguais,
  'o QR na parede levaria a um endereço diferente do que o dono copiou');

/* Trocando de salão, o QR troca junto: um desenho que ficasse do salão
   anterior mandaria a cliente de um para a agenda do outro. */
const trocou = await p.evaluate(() => {
  const antes = document.getElementById('qrDoLink').innerHTML;
  const outro = (bd.saloes || []).find(s => s.id !== salaoAtual);
  if(!outro) return { pulou: true };
  salaoAtual = outro.id; pintar(); irPara('publico');
  return { pulou: false, mudou: document.getElementById('qrDoLink').innerHTML !== antes };
});
if(trocou.pulou) console.log('      (só há um salão na demonstração — pulado)');
else e('trocando de salão, o QR é refeito', trocou.mudou,
       'o QR ficou o do salão anterior');

/* ── No celular ─────────────────────────────────────────────────────────── */
const cel = await ctx.newPage();
await cel.setViewportSize({ width:375, height:667 });
await cel.goto(BASE + 'app.html?demo=1');
await cel.waitForTimeout(2200);
await cel.evaluate(() => irPara('publico'));
await cel.waitForTimeout(900);
const noCelular = await cel.evaluate(() => ({
  vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  largura: Math.round(document.getElementById('qrDoLink').getBoundingClientRect().width),
}));
console.log('      375px: ' + JSON.stringify(noCelular));
e('em 375px a página não rola para o lado', noCelular.vaza === 0,
  'sobram ' + noCelular.vaza + 'px');
e('e o QR continua legível — ' + noCelular.largura + 'px',
  noCelular.largura >= 100, String(noCelular.largura));

e('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
