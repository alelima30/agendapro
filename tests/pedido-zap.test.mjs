/* ===========================================================================
   AgendaPro — a barra do pedido, com o logo do WhatsApp, no celular

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/pedido-zap.test.mjs

   O pedido: "Não aparece o logo do WhatsApp ao lado do Enviar pedido no
   celular."

   Medido antes de mexer, com dois produtos no carrinho:
     · a 320 e a 360px (a largura mais comum dos Android) o logo SUMIA e
       ficava o texto. A regra queria o contrário — esconder o texto e deixar
       o logo — mas escrita como `span:not(.ic-svg)`, casava justo com o span
       que embrulha o SVG;
     · a 375, 390 e 412px o total ("R$ 120,00") saía cortado embaixo do
       botão — agora ele tem a linha de cima só para ele;
     · no tema de letras claras o botão era o painel escuro com a letra na
       cor do botão: roxo sobre azul-marinho;
     · e a prévia do painel mostrava "Enviar" sem logo.
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
const lum = h => { const [r, g, b] = [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
  .map(c => c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const contraste = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`pz-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino', duracaoMin:30, intervaloMin:0,
  preco:90, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
await dona.inserir('produtos', { salaoId: SALAO, nome:'Máscara', preco:102.875, custo:20, estoque:50,
  comissaoPct:10, ativo:true, vendaOnline:true });
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const porCfg = cfg => dona.atualizar('saloes', SALAO, { cfg: Object.assign({ diasLiberados:30,
  funcionamento: SEMANA, pagamentos:{ formas:['pix'] } }, cfg) });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const HEX = `c => { const m = /rgba?\\(\\s*([\\d.]+)[,\\s]+([\\d.]+)[,\\s]+([\\d.]+)/.exec(c || '');
  return m ? '#' + [m[1], m[2], m[3]].map(n => Math.round(Number(n)).toString(16).padStart(2, '0')).join('').toUpperCase() : c; }`;
async function fita(largura, quantos){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:780 }, isMobile:true, hasTouch:true });
  const c = await ctx.newPage();
  c.on('pageerror', e => erros.push('página: ' + e.message));
  await c.goto(BASE + '/agendar.html?salao=' + SLUG);
  await c.waitForFunction(() => typeof produtosDaLoja === 'function' && produtosDaLoja().length, null, { timeout: 15000 });
  const r = await c.evaluate(([h, n]) => { const hex = eval(h);
    const pr = produtosDaLoja()[0];
    for(let i = 0; i < n; i++) mudarNoCarrinho(pr.id, 1);
    const f = document.getElementById('carrinhoFita'), z = f.querySelector('.cf-zap'), svg = z.querySelector('svg');
    const b = f.querySelector('.cf-txt b'), rz = z.getBoundingClientRect(), rs = svg && svg.getBoundingClientRect();
    const base = getComputedStyle(f).backgroundColor;
    const txt = z.querySelector('.cf-zap-txt');
    return { logo: !!rs && rs.width >= 14 && rs.right <= innerWidth,
      texto: txt && getComputedStyle(txt).display !== 'none' ? txt.textContent.trim() : '',
      total: b.textContent.trim(), totalInteiro: b.scrollWidth <= b.clientWidth,
      totalCor: hex(getComputedStyle(b).color),
      dentro: rz.left >= 0 && rz.right <= innerWidth, alvo: Math.round(rz.height),
      rotulo: z.getAttribute('aria-label'),
      fundoZap: hex(getComputedStyle(z).backgroundColor), letraZap: hex(getComputedStyle(z).color),
      iconeZap: hex(getComputedStyle(svg).color), fundoFita: hex(base), letraFita: hex(getComputedStyle(f).color) };
  }, [HEX, quantos]);
  await ctx.close();
  return r;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — O LOGO E O TOTAL, EM CADA LARGURA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. O logo do WhatsApp e o total, em cada celular');
await porCfg({ cor:'#5B21B6' });
for(const larg of [320, 360, 375, 390, 412]){
  for(const n of [2, 12]){
    const r = await fita(larg, n);
    verdade(`${larg}px, ${n} produtos: logo à vista, total inteiro (${r.total}) e o botão na tela`,
      r.logo && r.totalInteiro && r.dentro && r.alvo >= 44, JSON.stringify(r));
    /* Até 360px, só o logo; dali para cima, o logo e "Enviar pedido". */
    igual(`${larg}px, ${n} produtos: o botão diz`, r.texto, larg <= 360 ? '' : 'Enviar pedido');
  }
}
const cheio = await fita(412, 12);
igual('o botão diz o que faz para quem não enxerga o logo', cheio.rotulo, 'Enviar pedido no WhatsApp');
verdade('e o total grande aparece inteiro, com milhar e centavos', /R\$\s*1\.234,\d\d$/.test(cheio.total), cheio.total);

/* ══════════════════════════════════════════════════════════════════════════
   2 — O BOTÃO SE LÊ, EM QUALQUER COR
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. O Enviar se lê em qualquer tema e cor');
const CASOS = {
  'claro, botão roxo':                { cor:'#5B21B6' },
  'letras claras (painel escuro)':    { cor:'#5B21B6', tema:'escuro' },
  'botão dourado (letra preta)':      { cor:'#C9A24B', cores:{ botao:'#C9A24B' } },
  'fita clara escolhida à mão':       { cor:'#5B21B6', fitaCor:'#F5D76E' },
  'fita escura com botão claro':      { cor:'#C9A24B', cores:{ botao:'#C9A24B' }, fitaCor:'#123456' },
};
for(const [nome, cfg] of Object.entries(CASOS)){
  await porCfg(cfg);
  const r = await fita(390, 2);
  const zap = contraste(r.letraZap, r.fundoZap), icone = contraste(r.iconeZap, r.fundoZap);
  const fitaTxt = contraste(r.letraFita, cfg.fitaCor || (cfg.cores || {}).botao || cfg.cor);
  verdade(`${nome}: Enviar ${zap.toFixed(1)}:1, logo ${icone.toFixed(1)}:1, letra da fita ${fitaTxt.toFixed(1)}:1`,
    zap >= 4.5 && icone >= 4.5 && fitaTxt >= 4.5, JSON.stringify(r));
  /* ⚠ O TOTAL É LETRA DA FITA, não do tema. O cartão de "Confira seu
     agendamento" tem uma classe com o mesmo nome (.cf-txt) e chegou a pintar
     este valor com a letra escura do tema — sobre a fita roxa. */
  igual(`${nome}: o total tem a letra da fita`, r.totalCor, r.letraFita);
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — A PRÉVIA DO PAINEL
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. A prévia mostra o mesmo botão');
await porCfg({ cor:'#5B21B6', fitaCor:'#F5D76E' });
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:1000 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function' && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes),
    null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(400);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(800);
  const r = await p.evaluate(h => { const hex = eval(h);
    const z = document.querySelector('#previaFone .fone-fita-zap'), f = z.closest('.fone-fita');
    return { logo: !!z.querySelector('svg'), texto: z.textContent.trim(),
      fundoZap: hex(getComputedStyle(z).backgroundColor), letraFita: hex(getComputedStyle(f).color),
      total: f.querySelector('.fone-fita-txt b').textContent.trim() };
  }, HEX);
  igual('o Enviar da prévia tem o logo do WhatsApp', [r.logo, r.texto], [true, 'Enviar']);
  igual('o fundo do Enviar é a letra da fita, como na página', r.fundoZap, r.letraFita);
  verdade('e a letra da fita clara é escura', contraste(r.letraFita, '#F5D76E') >= 4.5, r.letraFita);
  verdade('e o total fica na linha de cima, como na página', /^R\$/.test(r.total), r.total);
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
