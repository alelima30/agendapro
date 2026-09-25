/* ===========================================================================
   AgendaPro — o estilo dos atalhos: Pagamentos, Horários e Informações

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/atalhos.test.mjs

   O pedido, com dois prints de referência: "transformar SOMENTE a aparência
   desses três itens", à escolha do dono entre

     · SEM MOLDURA — só ícone e texto, sem borda, sem caixa, sem fundo
       próprio, sem efeito de botão;
     · COM ASSOMBREAMENTO — o mesmo desenho, sem borda nenhuma ("NÃO
       significa colocar uma moldura preta"), só a sombra, com intensidade
       (nenhuma/suave/média/forte), desfoque, opacidade, distância e cor.

   E "NÃO remova, substitua ou altere nenhuma funcionalidade existente": o
   cartão com borda de hoje continua sendo o padrão, e quem nunca escolheu
   não vê diferença nenhuma.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. o padrão: nada muda para quem nunca escolheu;
     2. sem moldura: prévia na hora, e o link sem caixa, borda nem sombra;
     3. com assombreamento: só sombra, com os números escolhidos, e a prévia
        com a mesma sombra na escala dela;
     4. a página peneira o que vem do banco;
     5. o resto da capa não mexe, e voltar para "Com borda" devolve tudo;
     6. a cor de cada atalho — "a cor do Horários tem que ser configurável,
        também Informações e Pagamentos" —, nos três estilos.
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

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`at-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
// A marca NÃO é a de fábrica, para "a letra do Horários na cor da marca"
// não passar por acidente.
const BASE_CFG = { diasLiberados:30, cor:'#7C3AED', tema:'claro',
  funcionamento: SEMANA, pagamentos:{ formas:['pix','credito'] }, sobre:'Salão de beleza' };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' } });
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
  await p.waitForFunction(() => document.querySelectorAll('#capaInfo .recurso').length === 3,
    null, { timeout: 15000 });
  await p.waitForTimeout(500);
  return { p, fechar: () => ctx.close() };
}
const salvar = async p => { await p.evaluate(() => salvarAparencia()); await p.waitForTimeout(1800); };
const tocar = async (p, regua, rot) => {
  await p.locator(`#${regua} button`, { hasText: rot }).first().click();
  await p.waitForTimeout(250);
};

/* Qualquer cor em #RRGGBB, com o alfa em dois dígitos quando não for 1. */
const HEX = `c => {
  let m = /rgba?\\(\\s*([\\d.]+)[,\\s]+([\\d.]+)[,\\s]+([\\d.]+)(?:[,\\s/]+([\\d.]+))?/.exec(c || '');
  let v = m ? [m[1], m[2], m[3]].map(Number) : null, a = m && m[4] != null ? Number(m[4]) : 1;
  if(!v){ m = /color\\(srgb\\s+([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)(?:\\s*\\/\\s*([\\d.]+))?/.exec(c || '');
          if(m){ v = [m[1], m[2], m[3]].map(x => Number(x) * 255); a = m[4] != null ? Number(m[4]) : 1; } }
  if(!v) return c || '';
  const h = n => Math.round(n).toString(16).padStart(2, '0');
  return ('#' + v.map(h).join('') + (a < 1 ? h(a * 255) : '')).toUpperCase();
}`;

/* Como cada atalho está desenhado. A sombra é lida em partes: a cor e os
   quatro números — "0px 4px 16px 0px" é deslocamento x, y, desfoque e
   espalhamento. `transparente` vale para alfa zero em qualquer formato. */
const LER = `(els) => {
  const hex = (${HEX});
  const alfa0 = c => /rgba\\([^)]*,\\s*0\\)|transparent|\\/\\s*0\\)/.test(c);
  return els.map(e => {
    const cs = getComputedStyle(e), r = e.getBoundingClientRect();
    const sh = /^(rgba?\\([^)]*\\)|color\\([^)]*\\))\\s+(-?[\\d.]+)px\\s+(-?[\\d.]+)px\\s+([\\d.]+)px/.exec(cs.boxShadow) || [];
    return {
      fundo: alfa0(cs.backgroundColor) ? 'transparente' : hex(cs.backgroundColor),
      borda: alfa0(cs.borderTopColor) ? 'transparente' : hex(cs.borderTopColor),
      bordaPx: cs.borderTopWidth,
      sombra: cs.boxShadow === 'none' ? 'nenhuma'
        : { cor: hex(sh[1]), y: Number(sh[3]), desfoque: Number(sh[4]) },
      letra: hex(cs.color),
      larg: Math.round(r.width * 10) / 10, alt: Math.round(r.height * 10) / 10,
      transform: cs.transform,
    };
  });
}`;
const naPagina = p => p.evaluate(f => eval(f)([...document.querySelectorAll('#capaInfo .recurso')]), LER);
const naPrevia = p => p.evaluate(f => eval(f)([...document.querySelectorAll('#previaFone .fone-recurso')]), LER);
const controles = p => p.evaluate(() => ({
  estilo: [...document.querySelectorAll('#reguaAtalhos button')]
    .map(b => b.textContent.trim() + (b.classList.contains('on') ? '*' : '')),
  intensidade: [...document.querySelectorAll('#reguaSombra button')]
    .map(b => b.textContent.trim() + (b.classList.contains('on') ? '*' : '')),
  desligados: ['atDesfoque', 'atOpacidade', 'atDistancia', 'atCor']
    .map(id => document.getElementById(id).disabled),
  valores: ['atDesfoque', 'atOpacidade', 'atDistancia'].map(id => Number(document.getElementById(id).value)),
  rotulos: ['atDesfoqueV', 'atOpacidadeV', 'atDistanciaV']
    .map(id => document.getElementById(id).textContent),
  cor: document.getElementById('atCor').value,
  explica: document.getElementById('explicaSombra').textContent,
}));
// O resto da capa, para conferir que nada além dos atalhos mudou.
const resto = p => p.evaluate(h => { const hex = eval(h);
  const q = s => getComputedStyle(document.querySelector(s));
  return { status: hex(q('.status-casa').backgroundColor), boas: hex(q('.boas').backgroundColor),
           nome: hex(q('.marca-salao h2').color),
           recursosAlt: Math.round(document.querySelector('.recursos').getBoundingClientRect().height) };
}, HEX);

/* ══════════════════════════════════════════════════════════════════════════
   1 — O PADRÃO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. Quem nunca escolheu fica com o cartão com borda de sempre');
let antes, restoAntes;
{
  const { p, fechar } = await pagina();
  antes = await naPagina(p);
  restoAntes = await resto(p);
  igual('a página não ganha atributo', await p.evaluate(() =>
    document.documentElement.getAttribute('data-atalhos')), null);
  verdade('os três com borda visível; Pagamentos e Informações com fundo de cartão',
    antes.every(x => x.borda !== 'transparente')
      && antes[0].fundo === '#FFFFFF' && antes[2].fundo === '#FFFFFF', JSON.stringify(antes));
  verdade('e o Horários tingido na cor da marca, como antes',
    antes[1].fundo !== '#FFFFFF', JSON.stringify(antes[1]));
  await fechar();
}
{
  const { p, fechar } = await painel();
  const c = await controles(p);
  igual('o painel oferece os três estilos, com a borda marcada',
    c.estilo, ['Com borda*', 'Sem moldura', 'Com assombreamento']);
  igual('e os controles da sombra ficam desligados', c.desligados, [true, true, true, true]);
  verdade('dizendo como ligar', /Com assombreamento/.test(c.explica), c.explica);
  const prev = await naPrevia(p);
  verdade('a prévia mostra a borda também', prev.every(x => x.borda !== 'transparente'),
    JSON.stringify(prev));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — SEM MOLDURA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. Sem moldura: só ícone e texto');
{
  const { p, fechar } = await painel();
  await tocar(p, 'reguaAtalhos', 'Sem moldura');
  const prev = await naPrevia(p);
  verdade('a prévia muda na hora, antes de salvar: sem fundo, sem borda, sem sombra',
    prev.every(x => x.fundo === 'transparente' && x.borda === 'transparente' && x.sombra === 'nenhuma'),
    JSON.stringify(prev));
  igual('e a sombra continua desligada', (await controles(p)).desligados, [true, true, true, true]);
  await salvar(p);
  igual('salvar grava o estilo', (await cfgDe()).atalhos?.estilo, 'limpo');
  await fechar();
}
{
  const { p, fechar } = await pagina();
  const d = await naPagina(p);
  verdade('no link, os três sem fundo, sem borda e sem sombra — o Horários também',
    d.every(x => x.fundo === 'transparente' && x.borda === 'transparente' && x.sombra === 'nenhuma'),
    JSON.stringify(d));
  verdade('os três do mesmo tamanho',
    d.every(x => x.larg === d[0].larg && x.alt === d[0].alt), JSON.stringify(d.map(x => [x.larg, x.alt])));
  igual('e do mesmo tamanho de antes (a borda ficou transparente, não sumiu)',
    d.map(x => [x.larg, x.alt]), antes.map(x => [x.larg, x.alt]));
  verdade('a letra do Horários continua na cor da marca',
    d[1].letra === antes[1].letra && d[1].letra !== d[0].letra, JSON.stringify(d.map(x => x.letra)));
  await p.locator('#capaInfo .recurso').nth(0).hover();
  await p.waitForTimeout(300);
  const h = (await naPagina(p))[0];
  verdade('sem efeito de botão: passar o mouse não levanta nem sombreia',
    h.sombra === 'nenhuma' && (h.transform === 'none' || /matrix\(1, 0, 0, 1, 0, 0\)/.test(h.transform)),
    JSON.stringify(h));
  igual('o resto da capa não mexe', await resto(p), restoAntes);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — COM ASSOMBREAMENTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. Com assombreamento: sem borda, só a sombra');
const K = 234 / 412;
{
  const { p, fechar } = await painel();
  await tocar(p, 'reguaAtalhos', 'Com assombreamento');
  let c = await controles(p);
  igual('os controles da sombra ligam', c.desligados, [false, false, false, false]);
  igual('começando na intensidade Suave', c.intensidade, ['Nenhuma', 'Suave*', 'Média', 'Forte']);
  igual('com os números dela', c.valores, [16, 10, 4]);
  let prev = await naPrevia(p);
  verdade('a prévia: fundo de cartão, borda transparente e a sombra',
    prev.every(x => x.fundo === '#FFFFFF' && x.borda === 'transparente' && x.sombra !== 'nenhuma'),
    JSON.stringify(prev));

  await tocar(p, 'reguaSombra', 'Forte');
  c = await controles(p);
  igual('Forte preenche os três números', c.valores, [34, 26, 12]);
  igual('e os rótulos acompanham', c.rotulos, ['34 px', '26 %', '12 px']);
  prev = await naPrevia(p);
  verdade('e a prévia engrossa a sombra na hora (na escala dela)',
    Math.abs(prev[0].sombra.desfoque - 34 * K) < 0.6 && Math.abs(prev[0].sombra.y - 12 * K) < 0.6,
    JSON.stringify(prev[0].sombra));

  /* Arrastar o deslizante à mão. O elemento tem que ser o MESMO depois do
     movimento — refeito no meio do arrasto, ele solta o dedo do dono. */
  const mesmo = await p.evaluate(() => {
    const el = document.getElementById('atDesfoque');
    el.value = 20; el.dispatchEvent(new Event('input', { bubbles: true }));
    return el.isConnected && document.getElementById('atDesfoque') === el;
  });
  verdade('arrastar o desfoque não refaz o deslizante', mesmo);
  c = await controles(p);
  verdade('mexer à mão vira intensidade personalizada',
    !c.intensidade.some(x => x.endsWith('*')) && /personalizada/i.test(c.explica),
    JSON.stringify(c));
  const corMesma = await p.evaluate(() => {
    const el = document.getElementById('atCor');
    el.value = '#7c3aed'; el.dispatchEvent(new Event('input', { bubbles: true }));
    return el.isConnected && document.getElementById('atCor') === el;
  });
  verdade('escolher a cor da sombra não refaz o quadrado', corMesma);
  prev = await naPrevia(p);
  igual('a prévia pinta a sombra na cor escolhida, com a opacidade da Forte',
    prev[0].sombra.cor, '#7C3AED42');
  await salvar(p);
  const g = (await cfgDe()).atalhos;
  igual('salvar grava estilo, números e cor',
    [g.estilo, g.sombra.desfoque, g.sombra.opacidade, g.sombra.distancia, g.sombra.cor, g.sombra.intensidade],
    ['sombra', 20, 26, 12, '#7c3aed', 'personalizada']);
  await fechar();
}
{
  const { p, fechar } = await pagina();
  const d = await naPagina(p);
  verdade('no link: fundo de cartão e borda transparente nos três — sem moldura preta',
    d.every(x => x.fundo === '#FFFFFF' && x.borda === 'transparente'), JSON.stringify(d));
  igual('e a sombra com os números escolhidos',
    d.map(x => x.sombra), d.map(() => ({ cor:'#7C3AED42', y:12, desfoque:20 })));
  igual('do mesmo tamanho de antes', d.map(x => [x.larg, x.alt]), antes.map(x => [x.larg, x.alt]));
  await p.locator('#capaInfo .recurso').nth(2).hover();
  await p.waitForTimeout(300);
  igual('passar o mouse não troca a sombra', (await naPagina(p))[2].sombra,
    { cor:'#7C3AED42', y:12, desfoque:20 });
  igual('o resto da capa não mexe', await resto(p), restoAntes);
  await fechar();
  const pn = await painel();
  const prev = await naPrevia(pn.p);
  verdade('prévia e link: a mesma cor, e o desfoque e a distância na proporção da prévia',
    prev.every(x => x.sombra.cor === d[0].sombra.cor
      && Math.abs(x.sombra.desfoque / d[0].sombra.desfoque - K) < 0.03
      && Math.abs(x.sombra.y / d[0].sombra.y - K) < 0.03), JSON.stringify(prev.map(x => x.sombra)));
  const c = await controles(pn.p);
  igual('reabrindo o painel, tudo como foi salvo',
    [c.estilo[2], c.valores, c.cor, c.intensidade.some(x => x.endsWith('*'))],
    ['Com assombreamento*', [20, 26, 12], '#7c3aed', false]);
  await tocar(pn.p, 'reguaSombra', 'Nenhuma');
  await salvar(pn.p);
  await pn.fechar();
}
{
  const { p, fechar } = await pagina();
  const d = await naPagina(p);
  verdade('intensidade Nenhuma: nem sombra nem borda — o cartão limpo',
    d.every(x => x.borda === 'transparente' && x.fundo === '#FFFFFF'
      && (x.sombra === 'nenhuma' || /00$/.test(x.sombra.cor))), JSON.stringify(d));
  await fechar();
}
{
  const { p, fechar } = await pagina(1280, 800);
  const d = await naPagina(p);
  verdade('no computador, o mesmo estilo e os três do mesmo tamanho',
    d.every(x => x.borda === 'transparente' && x.larg === d[0].larg && x.alt === d[0].alt),
    JSON.stringify(d.map(x => [x.borda, x.larg, x.alt])));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — A PÁGINA PENEIRA O QUE VEM DO BANCO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. A página não confia no número que veio de fora');
/* A cor torta é "red": o CSS aceitaria, e é justamente por isso que a
   página precisa recusar. E com opacidade de verdade — com zero, a cor da
   sombra não aparece e o teste não veria nada. */
await porCfg({ atalhos:{ estilo:'sombra',
  sombra:{ desfoque:999, opacidade:20, distancia:'muito', cor:'red' } } });
{
  const { p, fechar } = await pagina();
  const d = (await naPagina(p))[0];
  igual('desfoque acima do teto vira 40, distância torta vira a da suave (4), cor torta vira preto',
    [d.sombra.desfoque, d.sombra.y, d.sombra.cor], [40, 4, '#00000033']);
  await fechar();
}
await porCfg({ atalhos:{ estilo:'sombra', sombra:{ desfoque:16, opacidade:-5, distancia:4 } } });
{
  const { p, fechar } = await pagina();
  const d = (await naPagina(p))[0];
  verdade('opacidade negativa vira zero', d.sombra === 'nenhuma' || /00$/.test(d.sombra.cor),
    JSON.stringify(d.sombra));
  await fechar();
}
await porCfg({ atalhos:{ estilo:'moldura-preta' } });
{
  const { p, fechar } = await pagina();
  const d = await naPagina(p);
  igual('estilo desconhecido é o cartão com borda de sempre',
    d.map(x => [x.fundo, x.borda]), antes.map(x => [x.fundo, x.borda]));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — VOLTAR PARA "COM BORDA"
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. Voltar para "Com borda" devolve o desenho de antes');
await porCfg({ atalhos:{ estilo:'limpo' } });
{
  const { p, fechar } = await painel();
  await tocar(p, 'reguaAtalhos', 'Com borda');
  await salvar(p);
  await fechar();
  const pg = await pagina();
  igual('o link volta exatamente ao que era', await naPagina(pg.p), antes);
  await pg.fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   6 — A COR DE CADA ATALHO
   ══════════════════════════════════════════════════════════════════════════ */
secao('6. A cor de Pagamentos, Horários e Informações');
const CORES = { pagamentos:'#0EA5E9', horarios:'#DC2626', informacoes:'#16A34A' };
// Ícone e nome de cada atalho, na página e na prévia.
const tintas = (p, raiz) => p.evaluate(([h, raiz]) => { const hex = eval(h);
  return [...document.querySelectorAll(raiz ? '#previaFone .fone-recurso' : '#capaInfo .recurso')]
    .map(e => ({ qual: e.dataset.recurso,
                 nome: hex(getComputedStyle(e).color),
                 icone: hex(getComputedStyle(e.querySelector(raiz ? 'svg, [data-ico]' : '.recurso-ic')).color),
                 fundo: hex(getComputedStyle(e).backgroundColor) }));
}, [HEX, raiz]);
await porCfg({});
{
  const { p, fechar } = await painel();
  const aj = await p.evaluate(() => ['Pagamentos', 'Horarios', 'Informacoes'].map(k => ({
    ajuda: document.getElementById('atCor' + k + 'Ajuda').textContent,
    herdar: document.getElementById('atCor' + k + 'Herdar').style.display })));
  igual('sem escolha, cada quadrado diz de onde vem a cor, e não oferece "herdar"',
    aj, [{ ajuda:'ícone na cor da marca, nome em cinza', herdar:'none' },
         { ajuda:'acompanha a cor da marca', herdar:'none' },
         { ajuda:'ícone na cor da marca, nome em cinza', herdar:'none' }]);
  const mesmos = await p.evaluate(cs => Object.entries(cs).every(([k, v]) => {
    const el = document.getElementById('atCor' + k[0].toUpperCase() + k.slice(1));
    el.value = v.toLowerCase(); el.dispatchEvent(new Event('input', { bubbles: true }));
    return el.isConnected && document.getElementById(el.id) === el;
  }), CORES);
  verdade('escolher as três cores não refaz os quadrados', mesmos);
  const prev = await tintas(p, true);
  igual('a prévia pinta ícone e nome de cada um na cor dele, na hora',
    prev.map(x => [x.qual, x.nome, x.icone]),
    [['pagamentos', CORES.pagamentos, CORES.pagamentos], ['horarios', CORES.horarios, CORES.horarios],
     ['informacoes', CORES.informacoes, CORES.informacoes]]);
  await salvar(p);
  // Em ordem de nome: o jsonb do Postgres guarda as chaves na ordem dele.
  igual('salvar grava as três', Object.entries((await cfgDe()).atalhos?.cores || {}).sort(),
    [['horarios', '#dc2626'], ['informacoes', '#16a34a'], ['pagamentos', '#0ea5e9']]);
  await fechar();
}
let comCor;
{
  const { p, fechar } = await pagina();
  comCor = await tintas(p, false);
  igual('no link, cada um na cor escolhida — ícone e nome',
    comCor.map(x => [x.qual, x.nome, x.icone]),
    [['pagamentos', CORES.pagamentos, CORES.pagamentos], ['horarios', CORES.horarios, CORES.horarios],
     ['informacoes', CORES.informacoes, CORES.informacoes]]);
  verdade('e o tingido do Horários, no cartão com borda, acompanha a cor dele',
    comCor[1].fundo !== antes[1].fundo && comCor[1].fundo !== '#FFFFFF', JSON.stringify([comCor[1], antes[1]]));
  igual('o resto da capa não mexe', await resto(p), restoAntes);
  await fechar();
}
for(const estilo of ['limpo', 'sombra']){
  await porCfg({ atalhos:{ estilo, cores: CORES } });
  const { p, fechar } = await pagina();
  const d = await tintas(p, false);
  igual(`as cores valem também no estilo ${estilo === 'limpo' ? 'Sem moldura' : 'Com assombreamento'}`,
    d.map(x => [x.nome, x.icone]), Object.values(CORES).map(c => [c, c]));
  await fechar();
}
await porCfg({ atalhos:{ estilo:'borda', cores: CORES } });
{
  const { p, fechar } = await painel();
  const pv = await tintas(p, true);
  igual('prévia e link com as mesmas cores, fundo do Horários inclusive',
    pv.map(x => [x.nome, x.icone, x.fundo]), comCor.map(x => [x.nome, x.icone, x.fundo]));
  await p.locator('#atCorHorariosHerdar').click();
  await p.waitForTimeout(250);
  const aj = await p.evaluate(() => document.getElementById('atCorHorariosAjuda').textContent);
  igual('"herdar" devolve o Horários à marca', aj, 'acompanha a cor da marca');
  await salvar(p);
  igual('e a chave sai do que é gravado', Object.keys((await cfgDe()).atalhos.cores).sort(),
    ['informacoes', 'pagamentos']);
  await fechar();
  const pg = await pagina();
  const d = await tintas(pg.p, false);
  igual('no link o Horários volta a ser exatamente o de antes',
    [d[1].nome, d[1].icone, d[1].fundo], [antes[1].letra, antes[1].letra, antes[1].fundo]);
  await pg.fechar();
}
await porCfg({ tema:'escuro', atalhos:{ estilo:'limpo', cores:{ horarios:'#1A1A1A' } } });
{
  const { p, fechar } = await painel();
  const aj = await p.evaluate(() => document.getElementById('atCorHorariosAjuda').textContent);
  verdade('cor que some no fundo ganha o aviso de contraste', /pouco contraste/.test(aj), aj);
  await fechar();
}
await porCfg({ atalhos:{ estilo:'borda', cores:{ horarios:'red', pagamentos:'#12345', informacoes:'url(x)' } } });
{
  const { p, fechar } = await pagina();
  const d = await naPagina(p);
  igual('a página ignora cor torta: fica o de antes',
    d.map(x => [x.letra, x.fundo]), antes.map(x => [x.letra, x.fundo]));
  await fechar();
}

secao('Erros de JavaScript');
igual('nenhum, no painel e na página', erros, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
