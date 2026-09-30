/* ===========================================================================
   AgendaPro — a tela de produtos na moldura curvada, e na cor do tema

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/loja-curvada.test.mjs

   O pedido: "Aplicar moldura curvada, quando tiver configurável, também em
   produtos. Pintar o Adicionar na cor do tema que está ativo. 'Escolha pelo
   menos 1 produto' também pintar na cor do tema."

   A lista da loja era uma fileira de blocos retos, com um "Adicionar" branco,
   qualquer que fosse a moldura escolhida em Aparência. Agora:
     · Curvada: os produtos em cartões iguais aos "Produtos em destaque" da
       capa (a foto com a onda), dois por linha, com o Adicionar embaixo;
     · Clássica: as fileiras de sempre;
     · nas duas, o Adicionar na cor do botão do salão (ou na cor dos
       produtos, quando o dono escolheu uma), e o "Escolha pelo menos 1
       produto" num tom da mesma cor, em vez do cinza.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. Curvada: cartões com a onda, dois por linha, nome, marca, descrição e
        preço, e o Adicionar;
     2. o Adicionar na cor do botão, com a letra calculada para ela;
     3. o botão de baixo, desligado, num tom da cor do tema, dizendo o que falta;
     4. tocar em Adicionar vira − 1 +, e o botão de baixo liga;
     5. Clássica: as fileiras de sempre, com o Adicionar também na cor;
     6. com "Cor dos produtos" escolhida, o Adicionar segue ela;
     7. a 360px, nada vaza para o lado e os botões são alvo de dedo.
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
const arte = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="300" height="420"><rect width="300" height="420" fill="${a}"/>`
  + `<rect x="100" y="80" width="100" height="260" rx="30" fill="${b}"/></svg>`).toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`lc-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Hidratação', duracaoMin:60, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const PRODUTOS = [
  ['Condicionador', 45, 'Tododia', 'Para cabelos mais macios'],
  ['Máscara de hidratação', 60, null, null],
  ['Perfume ok', 20, null, null],
  ['Shampoo', 45, null, null],
];
for(const [nome, preco, marca, descricao] of PRODUTOS)
  await dona.inserir('produtos', { salaoId: SALAO, nome, preco, marca, descricao, custo:10, estoque:5,
    comissaoPct:0, ativo:true, vendaOnline:true, foto: arte('#F3D9E4', '#D6336C') });
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777' });
const BASE_CFG = { diasLiberados:30, cor:'#B8356B', cores:{ botao:'#B8356B' } };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function loja(largura = 390){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:844 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.evaluate(() => irPara('loja'));
  await p.waitForTimeout(500);
  return { p, fechar: () => ctx.close() };
}
const cor = hex => {
  const n = parseInt(hex.slice(1), 16);
  return `rgb(${n >> 16}, ${(n >> 8) & 255}, ${n & 255})`;
};
const lerLoja = p => p.evaluate(() => {
  const add = document.querySelector('#listaProdutos .loja-add');
  const bp = document.getElementById('btPrincipal');
  const cs = x => x ? getComputedStyle(x) : null;
  const ac600 = getComputedStyle(document.documentElement).getPropertyValue('--ac-600').trim();
  const sonda = document.createElement('span'); sonda.style.color = ac600; document.body.appendChild(sonda);
  const ac600rgb = getComputedStyle(sonda).color; sonda.remove();
  return {
    grade: !!document.querySelector('#listaProdutos .pr-grade'),
    cartoes: document.querySelectorAll('#listaProdutos .pr-cartao').length,
    fileiras: document.querySelectorAll('#listaProdutos .bloco').length,
    colunas: (() => { const g = document.querySelector('#listaProdutos .pr-grade');
      return g ? getComputedStyle(g).gridTemplateColumns.split(' ').length : 0; })(),
    onda: (() => { const f = document.querySelector('#listaProdutos .pr-foto');
      if(!f) return null; const c = getComputedStyle(f);
      return (c.maskImage || c.webkitMaskImage || 'none') !== 'none'; })(),
    primeiro: (() => { const c = document.querySelector('#listaProdutos .pr-cartao');
      return c ? c.innerText.replace(/\s+/g, ' ').trim() : null; })(),
    addFundo: add ? cs(add).backgroundColor : null,
    addLetra: add ? cs(add).color : null,
    addTexto: add ? add.textContent.trim() : null,
    addAltura: add ? Math.round(add.getBoundingClientRect().height) : 0,
    bp: [bp.disabled, bp.textContent.trim(), cs(bp).backgroundColor, cs(bp).color],
    ac600rgb,
    sobra: document.documentElement.scrollWidth - innerWidth,
  };
});

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Moldura Curvada: os produtos em cartões com a onda');
await porCfg({ moldura:'elegante' });
{
  const { p, fechar } = await loja();
  const t = await lerLoja(p);
  igual('cartões, um por produto, e nenhuma fileira', [t.grade, t.cartoes, t.fileiras], [true, 4, 0]);
  igual('dois por linha, com a foto na onda', [t.colunas, t.onda], [2, true]);
  igual('o cartão traz nome, marca, descrição, preço e o Adicionar', t.primeiro,
    'Condicionador Tododia Para cabelos mais macios R$ 45,00 Adicionar');

  secao('2. O Adicionar na cor do tema');
  igual('fundo na cor do botão do salão, e não branco', t.addFundo, cor('#B8356B'));
  igual('com a letra calculada para ela (branca sobre o rosa)', t.addLetra, 'rgb(255, 255, 255)');

  secao('3. "Escolha pelo menos 1 produto" num tom da cor do tema');
  igual('desligado, dizendo o que falta', t.bp.slice(0, 2), [true, 'Escolha pelo menos 1 produto']);
  verdade('a letra na cor do tema (a escrita da marca), e não o cinza', t.bp[3] === t.ac600rgb,
    `letra ${t.bp[3]}, marca ${t.ac600rgb}`);
  // O color-mix chega como "color(srgb 0.97 0.9 0.93)", e não como rgb().
  verdade('e o fundo num tom rosado, e não o cinza de antes', (() => {
    const srgb = /color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)/.exec(t.bp[2]);
    const [r, g, b] = srgb ? srgb.slice(1).map(x => Number(x) * 255) : t.bp[2].match(/\d+/g).map(Number);
    return r > g + 8 && r > b;
  })(), t.bp[2]);

  secao('4. Tocar em Adicionar');
  await p.click('#listaProdutos .loja-add');
  await p.waitForTimeout(300);
  const q = await p.evaluate(() => {
    const c = document.querySelector('#listaProdutos .pr-cartao');
    const s = c.querySelector('.loja-qtd');
    return { passo: s ? s.innerText.replace(/\s+/g, ' ').trim() : null, noCarrinho: itensNoCarrinho(),
      bp: [document.getElementById('btPrincipal').disabled, document.getElementById('btPrincipal').textContent.trim()] };
  });
  igual('vira − 1 +, no mesmo cartão', q.passo, '− 1 +');
  igual('e o botão de baixo liga para enviar o pedido', [q.noCarrinho, q.bp], [1, [false, 'Enviar pedido no WhatsApp']]);
  await p.click('#listaProdutos .pr-cartao .loja-qtd button:last-child');
  await p.waitForTimeout(200);
  igual('o + soma', await p.evaluate(() => itensNoCarrinho()), 2);
  await p.click('#listaProdutos .pr-cartao .loja-qtd button:first-child');
  await p.click('#listaProdutos .pr-cartao .loja-qtd button:first-child');
  await p.waitForTimeout(200);
  igual('e o − tira, até voltar ao Adicionar', await p.evaluate(() =>
    [itensNoCarrinho(), !!document.querySelector('#listaProdutos .pr-cartao .loja-add')]), [0, true]);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Moldura Clássica: as fileiras de sempre');
await porCfg({ moldura:'reta' });
{
  const { p, fechar } = await loja();
  const t = await lerLoja(p);
  igual('fileiras, sem cartões de onda', [t.fileiras, t.cartoes, t.grade], [4, 0, false]);
  igual('e o Adicionar também na cor do tema', [t.addFundo, t.addTexto], [cor('#B8356B'), 'Adicionar']);
  igual('o botão de baixo também', t.bp[3], t.ac600rgb);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Com "Cor dos produtos" escolhida');
await porCfg({ moldura:'elegante', cores:{ botao:'#B8356B', produtos:'#1D4ED8' } });
{
  const { p, fechar } = await loja();
  const t = await lerLoja(p);
  igual('o Adicionar segue a cor dos produtos', [t.addFundo, t.addLetra], [cor('#1D4ED8'), 'rgb(255, 255, 255)']);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. A 360px');
{
  const { p, fechar } = await loja(360);
  const t = await lerLoja(p);
  igual('nada vaza para o lado, e o Adicionar é alvo de dedo', [t.sobra <= 0, t.addAltura >= 40], [true, true]);
  await p.click('#listaProdutos .loja-add');
  await p.waitForTimeout(250);
  const passo = await p.evaluate(() => [...document.querySelectorAll('#listaProdutos .loja-qtd button')]
    .slice(0, 2).map(b => Math.round(Math.min(b.getBoundingClientRect().width, b.getBoundingClientRect().height))));
  verdade('o − e o + também (≥ 40px)', passo.length === 2 && passo.every(x => x >= 40), JSON.stringify(passo));
  igual('e continua sem vazar com o − 1 +', await p.evaluate(() => document.documentElement.scrollWidth - innerWidth <= 0), true);
  await fechar();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
