/* ===========================================================================
   AgendaPro — a prévia igual à página, a divisão da foto, e o fundo no
   formato do celular

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/previa-capa.test.mjs

   O pedido, com dois prints: "a prévia não está igual o real. Veja que em
   vez de redondo a divisão da foto e o fundo está reto... quero deixar de
   duas maneiras, reto e também arredondado. Pelo computador o fundo está
   tomando toda a tela roxo... ele não tem que tomar somente o formato do
   celular? E ali seria um fundo diferente?"

   Medido antes de mexer, com o salão do print montado aqui:
     · a prévia cortava a foto reto; a página, num arco;
     · a prévia não lia o modo, a forma da logo, o anel nem a cor dele — a
       logo ficava pequena e solta embaixo da foto;
     · o Horários e o "Bem-vindo!" da prévia usavam a cor do BOTÃO e a do
       PAINEL; a página, a cor escrita da marca;
     · no premium, a página ignorava a espessura e a cor da moldura da logo;
     · num computador, o gradiente pintava a tela inteira.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a divisão da foto: o arco é o padrão, "Reta" chega ao link;
     2. a logo na beira da foto, prévia contra página, em proporção;
     3. as cores da fileira, do status e do Bem-vindo, prévia contra página;
     4. no computador, o fundo escolhido só na coluna, e as margens com o
        papel de fábrica; no celular, a tela de antes.

   ⚠ PRÉVIA E PÁGINA SÃO COMPARADAS EM PROPORÇÃO, e não em pixel: a prévia
   tem 236px e o celular 412. O que se cobra é a mesma forma — a mesma curva
   sobre a mesma largura, a mesma logo montando a mesma fração na foto.
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
const perto = (m, a, b, tol) => Math.abs(a - b) <= tol ? ok(m)
  : nao(m, `página ${b.toFixed(4)}, prévia ${a.toFixed(4)} (tolerância ${tol})`);
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
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="420">`
  + `<rect width="640" height="420" fill="${a}"/>`
  + `<circle cx="320" cy="170" r="90" fill="${b}"/></svg>`).toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`pc-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;

// Aberto a semana inteira, o dia inteiro: o status é ABERTO a qualquer hora
// em que o teste rodar, e as cores comparadas são sempre as do verde.
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
/* O salão do print: marca azul, botão roxo, letras claras sobre um gradiente
   roxo. A marca NÃO é a do botão de propósito — era essa a confusão da
   prévia, que tingia o Horários com a cor do botão. */
const BASE_CFG = { diasLiberados:30, cor:'#1D4ED8', tema:'escuro',
  fundoTipo:'gradiente', gradiente:'#A100FF,#5B0F9E,#1A1030',
  cores:{ botao:'#5B21B6' },
  funcionamento: SEMANA, pagamentos:{ formas:['pix','credito'] }, sobre:'Salão de beleza' };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  logo: arte('#6D28D9', '#C4B5FD'), capa: arte('#111111', '#E8C3A0') });
await porCfg({});
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

async function painel(){
  const ctx = await nav.newContext({ viewport:{ width:1280, height:1000 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function'
    && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => irPara('salao'));
  await p.waitForTimeout(400);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(700);
  return { p, fechar: () => ctx.close() };
}
async function pagina(larg = 412, alt = 915){
  const ctx = await nav.newContext({ viewport:{ width:larg, height:alt },
    isMobile: larg < 700, hasTouch: larg < 700 });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(`página ${larg}px: ` + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('.marca-selo')
    && document.querySelector('#capaInfo .recurso'), null, { timeout: 15000 });
  await p.waitForTimeout(500);
  return { p, fechar: () => ctx.close() };
}

/* Qualquer cor que o navegador devolva — rgb(), rgba() ou o color(srgb …)
   de um color-mix — em #RRGGBB. É o que deixa comparar a conta da prévia
   com a da página sem depender de como cada uma foi escrita. */
const HEX = `c => {
  let m = /rgba?\\(\\s*([\\d.]+)[,\\s]+([\\d.]+)[,\\s]+([\\d.]+)(?:[,\\s/]+([\\d.]+))?/.exec(c || '');
  let v = m ? [m[1], m[2], m[3]].map(Number) : null, a = m && m[4] != null ? Number(m[4]) : 1;
  if(!v){ m = /color\\(srgb\\s+([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)(?:\\s*\\/\\s*([\\d.]+))?/.exec(c || '');
          if(m){ v = [m[1], m[2], m[3]].map(x => Number(x) * 255); a = m[4] != null ? Number(m[4]) : 1; } }
  if(!v) return c || '';
  const h = n => Math.round(n).toString(16).padStart(2, '0');
  return ('#' + v.map(h).join('') + (a < 1 ? h(a * 255) : '')).toUpperCase();
}`;

/* A forma da capa, nos dois lados, em proporção da largura da foto. */
const MEDIR = `(foto, selo) => {
  const hex = (${HEX});
  const rf = foto.getBoundingClientRect(), rs = selo.getBoundingClientRect();
  const cf = getComputedStyle(foto), cs = getComputedStyle(selo);
  const raio = cf.borderBottomLeftRadius.split(' ');
  const anel = /^(rgba?\\([^)]*\\)|color\\([^)]*\\))\\s+0px\\s+0px\\s+0px\\s+([\\d.]+)px/.exec(cs.boxShadow) || [];
  return {
    arco: parseFloat(raio[1] || raio[0]) / rf.width,
    alto: rf.height / rf.width,
    logo: rs.width / rf.width,
    monta: (rf.bottom - rs.top) / rs.height,
    // "21%" na prévia, "22px" na página: os dois viram fração da largura.
    canto: /%$/.test(cs.borderTopLeftRadius) ? parseFloat(cs.borderTopLeftRadius) / 100
         : parseFloat(cs.borderTopLeftRadius) / rs.width,
    anel: anel[2] ? Number(anel[2]) / rf.width : 0,
    anelCor: anel[1] ? hex(anel[1]) : '',
  };
}`;
const medirPagina = p => p.evaluate(f => eval(f)(
  document.querySelector('.hero-foto'), document.querySelector('.marca-selo')), MEDIR);
const medirPrevia = p => p.evaluate(f => eval(f)(
  document.querySelector('#previaFone .fone-capa'),
  document.querySelector('#previaFone .fone-topo img, #previaFone .fone-selo')), MEDIR);

/* ══════════════════════════════════════════════════════════════════════════
   1 — A DIVISÃO DA FOTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. A divisão da foto: arredondada por padrão, reta quando escolhida');
{
  const { p, fechar } = await pagina();
  const r = await p.evaluate(() => ({
    attr: document.documentElement.getAttribute('data-capa'),
    raio: getComputedStyle(document.querySelector('.hero-foto')).borderBottomLeftRadius,
  }));
  igual('quem nunca escolheu não ganha atributo nenhum', r.attr, null);
  verdade('e a foto continua terminando no arco de sempre', /18px/.test(r.raio), r.raio);
  await fechar();
}
{
  const { p, fechar } = await painel();
  const regua = await p.evaluate(() => [...document.querySelectorAll('#reguaCapaForma button')]
    .map(b => b.textContent.trim() + (b.classList.contains('on') ? '*' : '')));
  igual('o painel oferece as duas, com a arredondada marcada', regua, ['Arredondada*', 'Reta']);
  const antes = await medirPrevia(p);
  verdade('a prévia também começa no arco', antes.arco > 0.03, JSON.stringify(antes));

  await p.locator('#reguaCapaForma button', { hasText: 'Reta' }).click();
  await p.waitForTimeout(300);
  const reta = await medirPrevia(p);
  igual('tocar em Reta endireita a prévia na hora, antes de salvar', reta.arco, 0);
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  igual('salvar grava capaForma = reta', (await cfgDe()).capaForma, 'reta');
  await fechar();
}
{
  const { p, fechar } = await pagina();
  const r = await p.evaluate(() => ({
    attr: document.documentElement.getAttribute('data-capa'),
    raio: getComputedStyle(document.querySelector('.hero-foto')).borderBottomLeftRadius,
  }));
  igual('o link recebe a escolha (a vitrine entrega a chave)', r.attr, 'reta');
  igual('e a foto termina reta no link', r.raio, '0px');
  await fechar();
}
{
  const { p, fechar } = await painel();
  const regua = await p.evaluate(() => [...document.querySelectorAll('#reguaCapaForma button')]
    .map(b => b.textContent.trim() + (b.classList.contains('on') ? '*' : '')));
  igual('reabrindo o painel, a Reta continua marcada', regua, ['Arredondada', 'Reta*']);
  await p.locator('#reguaCapaForma button', { hasText: 'Arredondada' }).click();
  await p.waitForTimeout(300);
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  await fechar();
  const pg = await pagina();
  const r = await pg.p.evaluate(() => ({
    attr: document.documentElement.getAttribute('data-capa'),
    raio: getComputedStyle(document.querySelector('.hero-foto')).borderBottomLeftRadius,
  }));
  verdade('voltar para Arredondada devolve o arco ao link',
    r.attr === null && /18px/.test(r.raio), JSON.stringify(r));
  await pg.fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — A LOGO NA BEIRA DA FOTO, PRÉVIA CONTRA PÁGINA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. A capa da prévia tem a forma da capa da página');
const CASOS = [
  ['modo atual, moldura média, logo de fábrica', {}],
  ['modo atual, divisão reta', { capaForma:'reta' }],
  ['modo atual, moldura grossa na cor que ele escolheu, logo arredondada',
    { logoBorda:'grossa', logoForma:'arredondado', cores:{ botao:'#5B21B6', moldura:'#A8B83A' } }],
  ['premium, moldura de fábrica', { modo:'premium' }],
  ['premium, moldura grossa na cor dele, logo quadrada',
    { modo:'premium', logoBorda:'grossa', logoForma:'quadrado', cores:{ botao:'#5B21B6', moldura:'#A8B83A' } }],
  ['premium, sem moldura', { modo:'premium', logoBorda:'sem' }],
];
for(const [nome, extra] of CASOS){
  await porCfg(extra);
  const pg = await pagina();
  const real = await medirPagina(pg.p);
  await pg.fechar();
  const pn = await painel();
  const prev = await medirPrevia(pn.p);
  await pn.fechar();
  console.log(`   ${nome}`);
  perto('  a curva na mesma proporção', prev.arco, real.arco, 0.006);
  perto('  a foto com a mesma altura', prev.alto, real.alto, 0.02);
  perto('  a logo do mesmo tamanho', prev.logo, real.logo, 0.012);
  perto('  montando a mesma fração na foto', prev.monta, real.monta, 0.05);
  perto('  com o mesmo canto', prev.canto, real.canto, 0.03);
  perto('  e o anel da mesma espessura', prev.anel, real.anel, 0.0025);
  if(real.anel > 0) igual('  e da mesma cor', prev.anelCor, real.anelCor);
}

/* O premium deixava de lado a moldura escolhida: medido na página, sem a
   prévia no meio — é defeito do link, e não só da comparação. */
await porCfg({ modo:'premium', logoBorda:'grossa', cores:{ botao:'#5B21B6', moldura:'#A8B83A' } });
{
  const { p, fechar } = await pagina();
  const r = await p.evaluate(h => { const hex = eval(h);
    const bs = getComputedStyle(document.querySelector('.marca-selo')).boxShadow;
    const m = /^(rgba?\([^)]*\))\s+0px\s+0px\s+0px\s+([\d.]+)px/.exec(bs) || [];
    return { cor: hex(m[1]), px: Number(m[2]) }; }, HEX);
  igual('no premium, a moldura grossa chega ao link (9px)', r.px, 9);
  igual('e na cor escolhida', r.cor, '#A8B83A');
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — AS CORES DA FILEIRA, DO STATUS E DO BEM-VINDO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. A fileira, o ABERTO e o Bem-vindo pintados como na página');
const CORES = [
  ['letras claras sobre o gradiente do print', {}],
  ['letras escuras, sem fundo escolhido', { tema:'claro', fundoTipo:'cor', gradiente:null }],
  ['letras claras, Destaque e Secundária escolhidos',
    { cores:{ botao:'#5B21B6', destaque:'#F59E0B', secundaria:'#10B981' } }],
  /* Sem fundo escolhido o Bem-vindo é o tom SUAVE, e é aí que a Secundária
     aparece: com fundo escolhido ele é o cartão opaco e o suave não entra. */
  ['letras escuras, sem fundo, Secundária escolhida',
    { tema:'claro', fundoTipo:'cor', gradiente:null, cores:{ botao:'#5B21B6', secundaria:'#10B981' } }],
];
const PARES = [
  ['o cartão Pagamentos',         '.recurso:not(.destaque)', '.fone-recurso:not(.destaque)', 'backgroundColor'],
  ['a borda dele',                '.recurso:not(.destaque)', '.fone-recurso:not(.destaque)', 'borderTopColor'],
  ['o ícone',                     '.recurso:not(.destaque) .recurso-ic',
                                  '.fone-recurso:not(.destaque) :is(svg, [data-ico])', 'color'],
  ['o botão Horários',            '.recurso.destaque',       '.fone-recurso.destaque',       'backgroundColor'],
  ['a letra do Horários',         '.recurso.destaque',       '.fone-recurso.destaque',       'color'],
  ['o cartão ABERTO',             '.status-casa',            '.fone-status',                 'backgroundColor'],
  ['a palavra ABERTO',            '.status-rot',             '.fone-status b',               'color'],
  ['o cartão Bem-vindo',          '.boas',                   '.fone-boas',                   'backgroundColor'],
  ['a borda dele',                '.boas',                   '.fone-boas',                   'borderTopColor'],
  ['o "Bem-vindo!"',              '.boas-oi',                '.fone-boas-t',                 'color'],
];
const ler = (p, raiz) => p.evaluate(([h, pares, raiz]) => {
  const hex = eval(h);
  return pares.map(([, pag, prev, prop]) => {
    const el = document.querySelector(raiz ? '#previaFone ' + prev : pag);
    return el ? hex(getComputedStyle(el)[prop]) : '(não achou)';
  });
}, [HEX, PARES, raiz]);
for(const [nome, extra] of CORES){
  await porCfg(extra);
  const pg = await pagina();
  const real = await ler(pg.p, false);
  await pg.fechar();
  const pn = await painel();
  const prev = await ler(pn.p, true);
  await pn.fechar();
  console.log(`   ${nome}`);
  PARES.forEach(([rot], i) => igual('  ' + rot, prev[i], real[i]));
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — NO COMPUTADOR, O FUNDO NO FORMATO DO CELULAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. No computador o fundo fica na coluna; no celular, a tela de antes');
/* O que o olho vê num ponto: sobe do elemento mais de cima até o primeiro
   que pinta alguma coisa. O <body> certo e escondido já enganou um teste
   deste projeto — aqui só vale o que aparece. */
const VISTO = `(x, y) => {
  const hex = (${HEX});
  for(const e of document.elementsFromPoint(x, y)){
    const cs = getComputedStyle(e);
    if(cs.backgroundImage !== 'none')
      return { quem: e.className || e.tagName, imagem: cs.backgroundImage.slice(0, 40) };
    const a = /rgba\\([^)]*,\\s*([\\d.]+)\\)/.exec(cs.backgroundColor);
    if(cs.backgroundColor !== 'transparent' && !(a && Number(a[1]) === 0))
      return { quem: e.className || e.tagName, cor: hex(cs.backgroundColor) };
  }
  return {};
}`;
const olhar = (p, x, y) => p.evaluate(([f, x, y]) => eval(f)(x, y), [VISTO, x, y]);
const atrasDoNome = p => p.evaluate(f => {
  const r = document.querySelector('.marca-salao h2').getBoundingClientRect();
  return eval(f)(r.left + 2, r.top + r.height / 2);
}, VISTO);

await porCfg({});
{
  const { p, fechar } = await pagina(1280, 800);
  const dentro = await atrasDoNome(p);
  const fora = await olhar(p, 120, 500);
  verdade('gradiente: atrás do nome, a coluna pinta o gradiente',
    /app/.test(dentro.quem || '') && /gradient/.test(dentro.imagem || ''), JSON.stringify(dentro));
  verdade('e a margem do computador fica lisa, no papel de fábrica do escuro',
    !fora.imagem && fora.cor === '#0B1220', JSON.stringify(fora));
  await fechar();
}
{
  const { p, fechar } = await pagina(412, 915);
  const dentro = await atrasDoNome(p);
  verdade('no celular, o gradiente continua atrás de tudo, como antes',
    /gradient/.test(dentro.imagem || ''), JSON.stringify(dentro));
  await fechar();
}
await porCfg({ tema:'claro', fundoTipo:'solida', gradiente:null,
  cores:{ botao:'#5B21B6', papel:'#F9D5E5' } });
{
  const { p, fechar } = await pagina(1280, 800);
  const dentro = await atrasDoNome(p);
  const fora = await olhar(p, 120, 500);
  igual('cor sólida: a coluna na cor escolhida', dentro.cor, '#F9D5E5');
  igual('e a margem no papel de fábrica do claro', fora.cor, '#F6F2E8');
  await fechar();
}
// A foto de fundo mora em cfg.fundo.
await porCfg({ tema:'claro', fundoTipo:'imagem', gradiente:null, veu:40,
  fundo: arte('#7a4a2a', '#d9a066') });
{
  const { p, fechar } = await pagina(1280, 800);
  const r = await p.evaluate(() => {
    const e = document.getElementById('fundoImagem');
    const b = e && e.getBoundingClientRect();
    return b ? { esq: Math.round(b.left), larg: Math.round(b.width) } : null;
  });
  igual('imagem: a foto de fundo ocupa só a coluna (400 a 880)', r, { esq: 400, larg: 480 });
  const fora = await olhar(p, 120, 500);
  igual('e a margem fica no papel de fábrica', fora.cor, '#F6F2E8');
  await fechar();
}
/* Foto de fundo E papel escolhido: as duas classes no <body>. A coluna tem
   que continuar transparente — pintada de papel, ela esconderia a foto. */
await porCfg({ tema:'claro', fundoTipo:'imagem', gradiente:null, veu:40,
  fundo: arte('#7a4a2a', '#d9a066'), cores:{ botao:'#5B21B6', papel:'#F9D5E5' } });
{
  const { p, fechar } = await pagina(1280, 800);
  const r = await p.evaluate(() => {
    const cs = getComputedStyle(document.querySelector('.app'));
    return { cor: cs.backgroundColor, imagem: cs.backgroundImage,
             classes: ['tem-fundo', 'tem-papel'].filter(c => document.body.classList.contains(c)) };
  });
  verdade('imagem com papel escolhido: a coluna não cobre a foto',
    r.classes.length === 2 && r.imagem === 'none' && /rgba\(0, 0, 0, 0\)|transparent/.test(r.cor),
    JSON.stringify(r));
  await fechar();
}
{
  const { p, fechar } = await pagina(412, 915);
  const r = await p.evaluate(() => {
    const b = document.getElementById('fundoImagem').getBoundingClientRect();
    return { esq: Math.round(b.left), larg: Math.round(b.width) };
  });
  igual('no celular, a foto de fundo continua na tela inteira', r, { esq: 0, larg: 412 });
  await fechar();
}
await porCfg({ tema:'claro', fundoTipo:null, gradiente:null, cores:{} });
{
  const { p, fechar } = await pagina(1280, 800);
  const dentro = await atrasDoNome(p);
  const fora = await olhar(p, 120, 500);
  verdade('sem fundo escolhido, o computador é o de sempre: coluna branca…',
    /app/.test(dentro.quem || '') && dentro.cor === '#FFFFFF', JSON.stringify(dentro));
  igual('…sobre o creme', fora.cor, '#F6F2E8');
  await fechar();
}

secao('Erros de JavaScript');
igual('nenhum, no painel e na página', erros, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
