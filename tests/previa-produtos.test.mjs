/* ===========================================================================
   AgendaPro — a prévia com produtos, o botão "Ver produtos" e tocar na
   prévia para ir à configuração

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/previa-produtos.test.mjs

   O pedido, com o print do link ao lado do da prévia: "tá diferente da
   prévia, veja que não tem produtos e etc. Preciso mexer também na cor do
   produto, ser a mesma configuração do Agendar horário, mas eu consigo
   escolher a cor que eu quero só pra ele. É possível clicar em cima do
   Agendar horário e ir direto para a configuração? Ou clicar em cima da
   moldura e configurar também?"

   Medido antes de mexer, com um salão igual ao dele:
     · a prévia não tinha o convite do Bem-vindo, nem o "Ver produtos", nem a
       vitrine de produtos;
     · o slide da prévia era 4:3 com "1 de 5"; o do link, 16:8, com o nome e
       as bolinhas;
     · com véu baixo guardado de uma foto antiga, a prévia pintava blocos
       brancos sobre um fundo liso.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a prévia repete o Bem-vindo, os produtos e o slide do link;
     2. o "Ver produtos": discreto (o de sempre) ou igual ao Agendar horário,
        e a cor dos produtos só nos produtos;
     3. tocar num pedaço da prévia leva aos controles dele.
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
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="420"><rect width="640" height="420" fill="${a}"/>`
  + `<circle cx="320" cy="170" r="90" fill="${b}"/></svg>`).toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`pp-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino', duracaoMin:30, intervaloMin:0,
  preco:90, ativo:true, aceitaOnline:true, categoria:'Cabelo', foto: arte('#8a6a4a', '#d9b38c') });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Hidratação', duracaoMin:40, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo', foto: arte('#5a4a6a', '#b8a6d9') });
// Inseridos fora da ordem de nome: a vitrine entrega por nome, e a prévia
// tem que concordar sobre qual produto aparece primeiro.
await dona.inserir('produtos', { salaoId: SALAO, nome:'Shampoo', preco:45, custo:20, estoque:5,
  comissaoPct:10, ativo:true, vendaOnline:true });
await dona.inserir('produtos', { salaoId: SALAO, nome:'Máscara', preco:60, custo:25, estoque:5,
  comissaoPct:10, ativo:true, vendaOnline:true });
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777',
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  logo: arte('#4C1D95', '#A78BFA'), capa: arte('#141414', '#E8C3A0') });
/* O salão do print: letras claras, fundo liso, botão roxo, moldura curvada —
   e um véu baixo guardado de quando ele testou a foto de fundo. */
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const BASE_CFG = { diasLiberados:30, cor:'#1D4ED8', tema:'escuro', fundoTipo:'solida',
  moldura:'elegante', veu:10, cores:{ botao:'#5B21B6' },
  funcionamento: SEMANA, pagamentos:{ formas:['pix'] }, sobre:'Salão de beleza' };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });
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
  await p.waitForTimeout(800);
  return { p, fechar: () => ctx.close() };
}
async function pagina(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:2000 }, isMobile:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('.boas') && document.querySelector('#slidesPista'),
    null, { timeout: 15000 });
  await p.waitForTimeout(600);
  return { p, fechar: () => ctx.close() };
}
const HEX = `c => {
  let m = /rgba?\\(\\s*([\\d.]+)[,\\s]+([\\d.]+)[,\\s]+([\\d.]+)(?:[,\\s/]+([\\d.]+))?/.exec(c || '');
  let v = m ? [m[1], m[2], m[3]].map(Number) : null, a = m && m[4] != null ? Number(m[4]) : 1;
  if(!v){ m = /color\\(srgb\\s+([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)(?:\\s*\\/\\s*([\\d.]+))?/.exec(c || '');
          if(m){ v = [m[1], m[2], m[3]].map(x => Number(x) * 255); a = m[4] != null ? Number(m[4]) : 1; } }
  if(!v) return c || '';
  const h = n => Math.round(n).toString(16).padStart(2, '0');
  return ('#' + v.map(h).join('') + (a < 1 ? h(a * 255) : '')).toUpperCase();
}`;
const limpo = t => String(t || '').replace(/\s+/g, ' ').trim();

/* O que o link mostra, e o mesmo lido na prévia. */
const lerPagina = p => p.evaluate(h => { const hex = eval(h);
  const q = s => document.querySelector(s), qa = s => [...document.querySelectorAll(s)];
  const sl = q('#slidesPista').getBoundingClientRect();
  const prod = q('.boas-produtos');
  return {
    convite: q('.boas-sub').textContent.trim(),
    botoes: qa('#capaBoas button').map(b => b.textContent.replace(/\s+/g, ' ').trim()),
    produtos: qa('#capaLoja .pr-txt b').slice(0, 2).map(b => b.textContent.trim()),
    precos: qa('#capaLoja .pr-txt span').slice(0, 2).map(b => b.textContent.trim()),
    todos: (q('.ver-todos-produtos .ver-todos-n') || {}).textContent || null,
    slideForma: Math.round(sl.width / sl.height * 100) / 100,
    legenda: (q('.slide.on figcaption') || {}).textContent || '',
    pontos: qa('#slidePontos button').length,
    prodClasse: prod ? (prod.classList.contains('boas-cta') ? 'metal' : 'discreto') : null,
    prodFundo: prod ? hex(getComputedStyle(prod).backgroundColor) : null,
    prodLetra: prod ? hex(getComputedStyle(prod).color) : null,
    agendarFundo: hex(getComputedStyle(q('#capaBoas .boas-cta:not(.boas-produtos)') || q('#capaBoas .boas-cta')).backgroundColor),
    carrinho: q('.pr-add') ? hex(getComputedStyle(q('.pr-add')).color) : null,
    verTodos: q('.ver-todos-produtos') ? hex(getComputedStyle(q('.ver-todos-produtos')).color) : null,
    preco: q('.pr-txt span') ? hex(getComputedStyle(q('.pr-txt span')).color) : null,
  };
}, HEX);
const lerPrevia = p => p.evaluate(h => { const hex = eval(h);
  const q = s => document.querySelector('#previaFone ' + s), qa = s => [...document.querySelectorAll('#previaFone ' + s)];
  const sl = q('.fone-slide').getBoundingClientRect();
  const prod = q('[data-cfg="produtos"].fone-cta, [data-cfg="produtos"].fone-cta2');
  return {
    convite: (q('.fone-boas-sub') || {}).textContent || '',
    botoes: qa('.fone-boas .fone-cta, .fone-boas .fone-cta2').map(b => b.textContent.replace(/\s+/g, ' ').trim()),
    produtos: qa('.fone-pr .fone-cartao-txt b').map(b => b.textContent.trim()),
    precos: qa('.fone-pr .fone-preco').map(b => b.textContent.trim()),
    todos: (q('.fone-ver-todos span') || {}).textContent || null,
    slideForma: Math.round(sl.width / sl.height * 100) / 100,
    legenda: (q('.fone-slide-leg') || {}).textContent || '',
    pontos: qa('.fone-slide-pontos i').length,
    prodClasse: prod ? (prod.classList.contains('fone-cta') ? 'metal' : 'discreto') : null,
    prodFundo: prod ? getComputedStyle(prod).getPropertyValue('--fone-marca').trim().toUpperCase() : null,
    // Sem foto de fundo, os blocos de serviços e produtos não têm fundo
    // próprio — como na página, onde só a foto engrossa os cartões.
    blocosComFundo: qa('.fone-svs').filter(e => !/rgba\(0, 0, 0, 0\)|transparent/.test(getComputedStyle(e).backgroundColor)).length,
    preco: q('.fone-pr .fone-preco') ? hex(getComputedStyle(q('.fone-pr .fone-preco')).color) : null,
  };
}, HEX);

/* ══════════════════════════════════════════════════════════════════════════
   1 — A PRÉVIA REPETE O LINK
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. O Bem-vindo, os produtos e o slide, na prévia como no link');
let real;
{
  const pg = await pagina();
  real = await lerPagina(pg.p);
  await pg.fechar();
  const { p, fechar } = await painel();
  const prev = await lerPrevia(p);
  igual('o convite do Bem-vindo é o mesmo', prev.convite, real.convite);
  igual('os dois botões, na mesma ordem', prev.botoes, real.botoes);
  igual('os produtos em destaque, na ordem do link', prev.produtos, real.produtos);
  igual('com os mesmos preços', prev.precos, real.precos);
  igual('e o "Ver todos os produtos" com a mesma contagem', prev.todos, real.todos);
  verdade('o slide tem a forma do link (16:8)', Math.abs(prev.slideForma - real.slideForma) < 0.06,
    `prévia ${prev.slideForma}, link ${real.slideForma}`);
  igual('o nome no slide e as bolinhas', [prev.legenda, prev.pontos], [real.legenda, real.pontos]);
  igual('o véu baixo guardado não pinta blocos sobre fundo liso', prev.blocosComFundo, 0);
  igual('e o preço do produto na mesma cor do link', prev.preco, real.preco);
  await fechar();
}
await porCfg({ slideForma:'quadrado' });
{
  const pg = await pagina();
  const r = await lerPagina(pg.p);
  await pg.fechar();
  const { p, fechar } = await painel();
  const prev = await lerPrevia(p);
  verdade('slide quadrado: a prévia acompanha', Math.abs(prev.slideForma - r.slideForma) < 0.06,
    `prévia ${prev.slideForma}, link ${r.slideForma}`);
  await fechar();
}
await porCfg({});

/* ══════════════════════════════════════════════════════════════════════════
   2 — O BOTÃO VER PRODUTOS
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. O "Ver produtos": discreto, ou igual ao Agendar horário na cor dele');
igual('quem nunca escolheu: discreto no link', real.prodClasse, 'discreto');
{
  const { p, fechar } = await painel();
  const r0 = await p.evaluate(() => ({
    regua: [...document.querySelectorAll('#reguaBotaoProdutos button')]
      .map(b => b.textContent.trim() + (b.classList.contains('on') ? '*' : '')),
    secao: document.getElementById('reguaBotaoProdutos').closest('.ap-sec').id,
    corNaSecao: !!document.querySelector('#apBotoes .cor-linha[data-chave="produtos"]'),
  }));
  igual('a escolha mora em Botões e atalhos, com a cor dos produtos logo abaixo',
    [r0.regua, r0.secao, r0.corNaSecao], [['Discreto*', 'Igual ao Agendar horário'], 'apBotoes', true]);
  igual('a prévia também começa discreta', (await lerPrevia(p)).prodClasse, 'discreto');
  // A fita do carrinho herda a cor do BOTÃO: o quadrado dela mostrava a da
  // marca (azul) com um botão roxo escolhido — visto na foto desta rodada.
  igual('o quadrado da fita mostra a cor que ela herda, a dos botões',
    await p.evaluate(() => document.getElementById('fitaCor').value), '#5b21b6');
  await p.locator('#reguaBotaoProdutos button', { hasText: 'Igual ao Agendar' }).click();
  await p.waitForTimeout(250);
  let prev = await lerPrevia(p);
  igual('"Igual ao Agendar horário" muda a prévia na hora, na cor dos botões',
    [prev.prodClasse, prev.prodFundo], ['metal', '#5B21B6']);
  const hex = await p.evaluateHandle(() => document.querySelector('.cor-linha[data-chave="produtos"] input[type="color"]')._hex);
  await hex.asElement().fill(''); await hex.asElement().type('#db2777');
  await p.waitForTimeout(250);
  prev = await lerPrevia(p);
  igual('e a cor dos produtos, escolhida só para ele, entra na hora', prev.prodFundo, '#DB2777');
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  const g = await cfgDe();
  igual('salvar grava o estilo e a cor', [g.botaoProdutos, g.cores.produtos], ['metal', '#db2777']);
  await fechar();
}
{
  const pg = await pagina();
  const r = await lerPagina(pg.p);
  await pg.fechar();
  igual('no link, o botão cheio, de metal', r.prodClasse, 'metal');
  verdade('na cor dos produtos (o metal é um degradê dela)', r.prodFundo.startsWith('#DB2777'), r.prodFundo);
  igual('o carrinho de cada produto e o "Ver todos" também', [r.carrinho, r.verTodos], ['#DB2777', '#DB2777']);
  igual('e o Agendar horário continua na cor dele', r.agendarFundo, real.agendarFundo);
  igual('o preço continua sendo o "Texto de destaque e preço"', r.preco, real.preco);
}
await porCfg({ cores:{ botao:'#5B21B6', produtos:'#DB2777' } });
{
  const pg = await pagina();
  const r = await lerPagina(pg.p);
  await pg.fechar();
  igual('discreto com cor: letra na cor dos produtos, sem fundo cheio', [r.prodClasse, r.prodLetra], ['discreto', '#DB2777']);
}
await porCfg({ botaoProdutos:'metal' });
{
  const pg = await pagina();
  const r = await lerPagina(pg.p);
  await pg.fechar();
  igual('igual ao Agendar sem cor própria: a cor dos botões', [r.prodClasse, r.prodFundo], ['metal', real.agendarFundo]);
}
await porCfg({ botaoProdutos:'qualquer-coisa' });
{
  const pg = await pagina();
  igual('valor torto no banco é o discreto de sempre', (await lerPagina(pg.p)).prodClasse, 'discreto');
  await pg.fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — TOCAR NA PRÉVIA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. Tocar num pedaço da prévia leva aos controles dele');
await porCfg({});
{
  const { p, fechar } = await painel();
  const semAlvo = await p.evaluate(() => {
    const usados = [...new Set([...document.querySelectorAll('#previaFone [data-cfg]')].map(e => e.dataset.cfg))];
    return { usados, faltam: usados.filter(k => !(CONFIG_DA_PREVIA[k] || []).some(sel =>
      document.querySelector('.ap-controles ' + sel))) };
  });
  verdade('todo pedaço tocável da prévia tem controle para onde ir',
    semAlvo.usados.length >= 14 && semAlvo.faltam.length === 0, JSON.stringify(semAlvo));
  const tocar = async (sel, esperado) => {
    await p.evaluate(() => { document.querySelectorAll('.ap-alvo').forEach(e => e.classList.remove('ap-alvo'));
      window.scrollTo(0, 0); });
    await p.locator('#previaFone ' + sel).first().click();
    await p.waitForTimeout(900);
    return p.evaluate(sel => { const el = document.querySelector('.ap-controles ' + sel);
      const alvo = el && (el.closest('.cor-linha') || el);
      const r = alvo && alvo.getBoundingClientRect();
      return { aceso: !!alvo && alvo.classList.contains('ap-alvo'),
               naTela: !!r && r.top >= 0 && r.bottom <= innerHeight }; }, esperado);
  };
  const CASOS = [
    ['o Agendar horário → Cor dos botões', '[data-cfg="agendar"]', '.cor-linha[data-chave="botao"]'],
    ['o Ver produtos → o botão Ver produtos', '[data-cfg="produtos"].fone-cta2', '#reguaBotaoProdutos'],
    ['a logo (a moldura) → Moldura do logo', '[data-cfg="logo"]', '.cor-linha[data-chave="moldura"]'],
    ['o nome → Títulos', '[data-cfg="nome"]', '.cor-linha[data-chave="titulo"]'],
    ['um serviço → Moldura dos serviços', '.fone-cartao:not(.fone-pr)', '#reguaMoldura'],
    ['o slide → Slide da capa', '[data-cfg="slide"]', '#reguaSlide'],
    ['a foto de capa → Enquadramento', '[data-cfg="capa"]', '#fxFoco'],
    ['os atalhos → Estilo dos atalhos', '.fone-recurso', '#reguaAtalhos'],
    ['o pino → Cor dos ícones', '[data-cfg="pino"]', '.cor-linha[data-chave="icone"]'],
    ['a fita → Fita do carrinho', '[data-cfg="fita"]', '#reguaFitaMetal'],
    ['o ABERTO → Cartões, que o tingem', '[data-cfg="status"]', '.cor-linha[data-chave="card"]'],
    ['o preço → Texto de destaque e preço', '[data-cfg="preco"]', '.cor-linha[data-chave="destaque"]'],
  ];
  for(const [rot, sel, esperado] of CASOS){
    const r = await tocar(sel, esperado);
    verdade(rot + ': acende e aparece na tela', r.aceso && r.naTela, JSON.stringify(r));
  }
  const nada = await p.evaluate(() => {
    const antes = aparencia && JSON.stringify(aparencia);
    document.querySelector('#previaFone [data-cfg="agendar"]').click();
    return antes === JSON.stringify(aparencia);
  });
  verdade('tocar só leva: não muda nenhuma escolha', nada);
  await fechar();
}
{
  // Na página da cliente o botão continua sendo o botão: nada de configuração.
  const pg = await pagina();
  const r = await pg.p.evaluate(() => ({ cfg: document.querySelectorAll('[data-cfg]').length,
    alvo: typeof irParaConfig }));
  igual('no link da cliente não existe nada disso', r, { cfg: 0, alvo: 'undefined' });
  await pg.fechar();
}

secao('Erros de JavaScript');
igual('nenhum, no painel e na página', erros, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
