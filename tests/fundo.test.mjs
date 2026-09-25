/* ===========================================================================
   AgendaPro — o fundo da página: qualquer cor, gradiente ou imagem

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/fundo.test.mjs

   O pedido, com print da tela: "A base clara ou escura, eu quero colocar cor
   que eu quiser gradiente, cor sólida ou imagem."

   Era a terceira vez da mesma queixa. O print mostrava por quê: a primeira
   pergunta do bloco do fundo era "Base clara ou escura", o "Cor sólida" dizia
   "o papel limpo do tema", e o quadrado do Fundo da página aparecia AZUL — a
   cor da marca — com a frase "acompanha a cor da marca", sobre uma página
   bege. Três coisas dizendo que o fundo não se escolhia.

   E mais três que só apareceram medindo:
     · a prévia não desenhava gradiente nenhum;
     · escolher "Gradiente" sem mexer nos seletores gravava nulo;
     · "Cor sólida" escolhida à mão deixava a foto antiga no link.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. o bloco: o tipo vem primeiro, cada tipo mostra os seus controles, e o
        quadrado mostra a cor que está na página;
     2. as letras: escolhidas sozinhas pelo fundo, por contraste;
     3. gravar: o que foi escolhido chega na página da cliente;
     4. a foto: quem nunca escolheu continua com ela, quem escolheu cor não;
     5. a prévia pinta o mesmo fundo que a página;
     6. as cores de fábrica do painel batem com as da página.
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

const FOTO = 'data:image/svg+xml;base64,' + Buffer.from(
  '<svg xmlns="http://www.w3.org/2000/svg" width="90" height="160">'
  + '<rect width="90" height="160" fill="#7a4a2a"/></svg>').toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`fu-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salao Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const MARCA = '#1D4ED8';
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
const porCfg = async extra => dona.atualizar('saloes', SALAO,
  { cfg: Object.assign({ diasLiberados:30, cor: MARCA }, extra) });
await porCfg({});

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

async function painel(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                     isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function'
    && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes), null,
    { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => irPara('salao'));
  await p.waitForTimeout(400);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(700);
  return { p, fechar: () => ctx.close() };
}

const salvar = async p => {
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
};

const HEX = `c => { const m = /rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/.exec(c || '');
  return m ? '#' + [1,2,3].map(i => Number(m[i]).toString(16).padStart(2,'0'))
    .join('').toUpperCase() : (c || ''); }`;

async function pagina(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 }, isMobile:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => {
    const e = document.getElementById('capaMarca');
    return e && e.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  await p.waitForTimeout(500);
  const r = await p.evaluate(h => {
    const hex = eval(h);
    const raiz = getComputedStyle(document.documentElement);
    const nome = document.querySelector('.marca-salao h2');
    return {
      fundo: hex(getComputedStyle(document.body).backgroundColor),
      grad: raiz.getPropertyValue('--bg-grad').trim(),
      comGrad: document.body.classList.contains('tem-gradiente'),
      escuro: document.documentElement.getAttribute('data-tema') === 'escuro',
      nome: nome ? hex(getComputedStyle(nome).color) : '',
      foto: !!document.getElementById('fundoImagem'),
      padroes: Object.fromEntries(['--bg','--painel','--txt','--txt2','--txt3','--borda']
        .map(k => [k, hex(raiz.getPropertyValue(k).trim()).toUpperCase()])),
    };
  }, HEX);
  await ctx.close();
  return r;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — O BLOCO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · O bloco do fundo, no celular');
{
  const { p, fechar } = await painel();
  const r = await p.evaluate(() => {
    const aba = document.querySelector('#painelSalao [data-sub="aparencia"]');
    const tipo = document.getElementById('reguaFundoTipo');
    const letras = document.getElementById('reguaTema');
    return {
      antes: !!(tipo.compareDocumentPosition(letras) & Node.DOCUMENT_POSITION_FOLLOWING),
      semBase: !/Base clara ou escura/i.test(aba.innerText),
      quadrado: document.querySelector('#corDoPapel input').value.toUpperCase(),
      frase: document.querySelector('#corDoPapel .cor-linha-txt span').textContent,
    };
  });
  verdade('a primeira pergunta do fundo é o tipo, e as letras vêm depois', r.antes);
  verdade('"Base clara ou escura" não existe mais na tela', r.semBase);
  /* ⚠ ERA AZUL NO PRINT. O quadrado mostrava a cor da marca para uma página
     bege — a única cor que ele estava tentando escolher, errada. */
  igual('o quadrado do fundo mostra o bege que está na página, e não a marca',
    r.quadrado, '#F6F2E8');
  verdade('e diz que é automático, não que "acompanha a marca"',
    /automático/.test(r.frase) && !/marca/.test(r.frase), r.frase);

  const visiveis = async tipo => p.evaluate(t => {
    escolherFundoTipo(t);
    const v = id => getComputedStyle(document.getElementById(id)).display !== 'none';
    return { cor: v('fundoSolido'), grad: v('gradienteCampos'), img: v('imagemCampos') };
  }, tipo);
  igual('Cor sólida mostra só a cor', await visiveis('cor'),
    { cor:true, grad:false, img:false });
  igual('Gradiente mostra só as duas cores', await visiveis('gradiente'),
    { cor:false, grad:true, img:false });
  igual('Imagem mostra só a imagem', await visiveis('imagem'),
    { cor:false, grad:false, img:true });
  verdade('e a imagem se anexa ali mesmo, com a régua do véu junto',
    await p.evaluate(() => !!document.querySelector('#imagemCampos input[type=file]')
      && !!document.querySelector('#imagemCampos #fxVeu')));

  const semRolar = await p.evaluate(() =>
    document.documentElement.scrollWidth <= document.documentElement.clientWidth);
  verdade('nada passa da largura do celular', semRolar);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — AS LETRAS ACOMPANHAM O FUNDO
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · As letras se ajustam sozinhas ao fundo');
{
  const { p, fechar } = await painel();
  const tema = acao => p.evaluate(a => { eval(a); return aparencia.tema; }, acao);
  igual('fundo "Noite" pede letras claras',
    await tema("escolherPapelPronto('#0B1220')"), 'escuro');
  igual('um rosa claro escolhido à mão pede letras escuras',
    await tema("escolherCorSolta('papel', '#FBE7EF')"), 'claro');
  igual('gradiente escuro, letras claras',
    await tema("escolherGradientePronto('#1F2430', '#07090F')"), 'escuro');
  igual('gradiente claro, letras escuras',
    await tema("escolherGradientePronto('#FFFFFF', '#EFE9DF')"), 'claro');
  /* ⚠ NO GRADIENTE MANDA A PIOR PONTA. Não existe letra que se leia bem nas
     duas pontas de um gradiente claro-escuro, então a escolha é a que se lê
     MELHOR no pior ponto. Os dois pares são escolhidos para discordar de quem
     olhasse uma ponta só: o primeiro reprova quem olha só a de baixo, o
     segundo quem olha só a de cima. Medido antes de escrever. */
  igual('branco até cinza-escuro: letras escuras',
    await tema("escolherGradientePronto('#FFFFFF', '#3A3A3A')"), 'claro');
  igual('grafite até quase branco: letras escuras também',
    await tema("escolherGradientePronto('#1F2430', '#F0F0F0')"), 'claro');

  // Ele pode trocar à mão, e a tela avisa que não é o que se lê melhor.
  const avisa = await p.evaluate(() => {
    escolherPapelPronto('#FFFFFF');
    escolherTema('escuro');
    return document.getElementById('explicaTema').textContent;
  });
  verdade('trocar as letras à mão é permitido, com aviso', /o outro/.test(avisa), avisa);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — GRAVAR, E A PÁGINA OBEDECE
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · O que ele escolhe chega na página da cliente');
{
  let { p, fechar } = await painel();
  await p.evaluate(() => escolherPapelPronto('#0B1220'));
  await salvar(p);
  await fechar();
  const c1 = await cfgDe();
  igual('no banco: cor sólida', c1.fundoTipo, 'solida');
  igual('a cor', String((c1.cores || {}).papel).toUpperCase(), '#0B1220');
  igual('e as letras claras', c1.tema, 'escuro');
  const pg1 = await pagina();
  igual('a página pinta o fundo escolhido', pg1.fundo, '#0B1220');
  verdade('com as letras claras', pg1.escuro, JSON.stringify(pg1));
  verdade('e o nome do salão se lê sobre ele',
    pg1.nome && pg1.nome !== '#172033', pg1.nome);

  /* ⚠ GRADIENTE SEM MEXER NOS SELETORES. Os dois apareciam preenchidos, e
     salvar gravava nulo: a página continuava lisa. */
  ({ p, fechar } = await painel());
  await p.evaluate(() => { aparencia.gradiente = null; escolherFundoTipo('gradiente'); });
  const naTela = await p.evaluate(() =>
    document.getElementById('gradA').value + ',' + document.getElementById('gradB').value);
  await salvar(p);
  await fechar();
  const c2 = await cfgDe();
  igual('escolher Gradiente e salvar sem mexer grava o gradiente que estava na tela',
    String(c2.gradiente || '').toLowerCase(), naTela.toLowerCase());
  const pg2 = await pagina();
  verdade('e a página mostra o gradiente', pg2.comGrad && /linear-gradient/.test(pg2.grad),
    JSON.stringify(pg2));

  ({ p, fechar } = await painel());
  await p.evaluate(() => escolherGradientePronto('#FDF2F6', '#F4CFDD'));
  await salvar(p);
  await fechar();
  const pg3 = await pagina();
  verdade('um gradiente pronto também chega inteiro',
    /#fdf2f6/i.test(pg3.grad) && /#f4cfdd/i.test(pg3.grad), pg3.grad);
  verdade('com letras escuras, porque é claro', !pg3.escuro);
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — A FOTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4 · A foto: quem nunca escolheu fica com ela, quem escolheu cor não');
{
  await porCfg({ fundo: FOTO });                       // sem fundoTipo
  verdade('foto antiga, sem escolha nenhuma: continua no link', (await pagina()).foto);
  let { p, fechar } = await painel();
  igual('e o painel mostra "Imagem" aceso — o que a página faz',
    await p.evaluate(() => document.querySelector('#reguaFundoTipo .on').textContent.trim()),
    'Imagem');
  await fechar();

  /* Quem salvou com o painel anterior tem `cor` gravado junto com a foto: o
     painel antigo sempre gravava `cor`. Para a página esse salão é igual ao
     que nunca escolheu — a foto que ele vê hoje não pode sumir. */
  await porCfg({ fundo: FOTO, fundoTipo: 'cor' });
  verdade('foto com "cor" gravado pelo painel antigo: continua', (await pagina()).foto);

  ({ p, fechar } = await painel());
  await p.evaluate(() => { escolherFundoTipo('cor'); escolherPapelPronto('#FBE7EF'); });
  await salvar(p);
  await fechar();
  igual('escolhendo Cor sólida, o banco guarda "solida"', (await cfgDe()).fundoTipo, 'solida');
  const semFoto = await pagina();
  verdade('e a foto sai do link', !semFoto.foto, JSON.stringify(semFoto));
  igual('ficando a cor que ele escolheu', semFoto.fundo, '#FBE7EF');

  ({ p, fechar } = await painel());
  await p.evaluate(() => escolherFundoTipo('imagem'));
  await salvar(p);
  await fechar();
  verdade('voltando para Imagem, a foto volta', (await pagina()).foto);
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — A PRÉVIA PINTA O MESMO FUNDO
   ══════════════════════════════════════════════════════════════════════════ */
secao('5 · A prévia do painel pinta o mesmo fundo que a página');
{
  await porCfg({});
  const { p, fechar } = await painel();
  const previa = acao => p.evaluate(([a, h]) => {
    eval(a);
    const hex = eval(h);
    const f = document.querySelector('#previaFone .fone');
    return { cor: hex(getComputedStyle(f).backgroundColor),
             img: getComputedStyle(f).backgroundImage };
  }, [acao, HEX]);

  /* ⚠ SEM NADA ESCOLHIDO, NO ESCURO. A prévia caía no cinza do painel
     (#141416) em vez do azul-noite da página (#0B1220). */
  igual('sem escolha, no escuro: o mesmo fundo de fábrica da página',
    (await previa("escolherFundoTipo('cor'); escolherTema('escuro')")).cor, '#0B1220');
  igual('cor escolhida', (await previa("escolherPapelPronto('#F2E4DA')")).cor, '#F2E4DA');
  const g = await previa("escolherGradientePronto('#FBF6EC', '#E9D6B0')");
  verdade('gradiente: a prévia desenha as duas cores',
    /251, 246, 236/.test(g.img) && /233, 214, 176/.test(g.img), g.img);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   6 — AS CORES DE FÁBRICA
   ══════════════════════════════════════════════════════════════════════════ */
secao('6 · As cores de fábrica do painel são as da página');
/* O quadrado de cada cor mostra o PADRAO_TEMA do painel enquanto o dono não
   escolhe. Se a página mudar o padrão dela e o painel não, o quadrado volta a
   mentir — exatamente o defeito do print. */
{
  const { p, fechar } = await painel();
  const noPainel = await p.evaluate(() => PADRAO_TEMA);
  await fechar();
  const MAPA = { '--bg':'papel', '--painel':'card', '--txt':'titulo',
                 '--txt2':'texto', '--txt3':'discreto', '--borda':'borda' };
  for(const tema of ['claro', 'escuro']){
    await porCfg({ tema });
    const pg = await pagina();
    const naPagina = Object.fromEntries(Object.entries(MAPA)
      .map(([v, k]) => [k, pg.padroes[v]]));
    igual('tema ' + tema + ': as seis cores batem', naPagina,
      Object.fromEntries(Object.values(MAPA).map(k => [k, noPainel[tema][k].toUpperCase()])));
  }
}

igual('nenhum erro nas telas', erros, []);
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
