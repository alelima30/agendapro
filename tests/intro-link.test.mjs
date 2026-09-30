/* ===========================================================================
   AgendaPro — a abertura com o logo quando alguém abre o link da cliente

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/intro-link.test.mjs

   (A cortina da tela de ENTRAR do painel é outra coisa, e mora no
   abertura.test.mjs. Esta é a do link que o salão manda para a cliente.)

   O pedido: "Quando clicar no link do cliente, deixar configurável um efeito
   de slide de entrada, uma intro com o logotipo. É possível?"

   Aparência → Abertura: o efeito (sem, aparecer, deslizar, brilho), quanto
   tempo, o fundo (cor do botão ou da página) e o nome embaixo do logo. Nasce
   em "Sem abertura" — o link de sempre, para quem nunca escolheu.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. sem escolha, nenhuma abertura: o link abre como sempre abriu;
     2. no painel: a seção, nascendo em "Sem abertura", as outras réguas
        escondidas até escolher um efeito, o "Ver a abertura" tocando dentro
        do celular da prévia, e o Salvar gravando o objeto no banco;
     3. no link: a abertura cobre a tela com o logo e o nome, no efeito e no
        fundo escolhidos, e sai sozinha no tempo escolhido;
     4. uma vez por visita: recarregar não toca de novo; abrir o link de novo
        (aba nova) toca;
     5. um toque pula;
     6. sem o nome, com o fundo da página, com o logo quadrado;
     7. "reduzir movimento" encurta e para a animação;
     8. lixo no banco não derruba a página: vira "sem abertura".
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
  `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400"><rect width="400" height="400" fill="${a}"/>`
  + `<circle cx="200" cy="200" r="110" fill="${b}"/></svg>`).toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`ab-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Hidratação', duracaoMin:60, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
await dona.atualizar('saloes', SALAO, { logo: arte('#6D28D9', '#F9A8D4') });
const BASE_CFG = { diasLiberados:30, cor:'#B8356B', cores:{ botao:'#B8356B' } };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });
await porCfg({});
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* Lê a abertura no primeiro instante — ela nasce junto com a capa, e o que
   se mede aqui é ela, não a página. */
const lerIntro = p => p.evaluate(() => {
  const el = document.getElementById('intro');
  if(!el) return null;
  const cs = getComputedStyle(el), logo = el.querySelector('.intro-logo');
  const r = el.getBoundingClientRect();
  return {
    classe: el.className,
    cobre: cs.position === 'fixed' && r.width >= innerWidth && r.height >= innerHeight,
    img: !!(logo && logo.querySelector('img') && logo.querySelector('img').src.startsWith('data:image/svg')),
    nome: (el.querySelector('.intro-nome') || {}).textContent || null,
    ms: el.style.getPropertyValue('--intro-ms'),
    raio: logo ? getComputedStyle(logo).borderTopLeftRadius : null,
    fundo: cs.backgroundColor + ' ' + cs.backgroundImage.slice(0, 40),
    papel: getComputedStyle(document.body).backgroundColor,
    rotulo: el.getAttribute('aria-label'),
    anima: logo ? getComputedStyle(logo).animationName : null,
  };
});
async function abrir(ctx){
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  return p;
}
const celular = (extra = {}) => nav.newContext(Object.assign(
  { viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true }, extra));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Sem escolha, nenhuma abertura');
{
  const ctx = await celular();
  const p = await abrir(ctx);
  igual('o link abre direto na capa, sem abertura', await lerIntro(p), null);
  await p.waitForTimeout(700);
  igual('nem depois de um instante', await p.evaluate(() => !!document.querySelector('.intro')), false);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. No painel: Aparência → Abertura');
{
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

  const regua = () => p.evaluate(() => {
    const on = id => [...document.querySelectorAll('#' + id + ' button')]
      .map(b => b.textContent.trim() + (b.classList.contains('on') ? ' ●' : ''));
    return { titulo: document.querySelector('#apAbertura .ap-sec-t').textContent.trim(),
      efeito: on('reguaIntroEfeito'), tempo: on('reguaIntroTempo'), fundo: on('reguaIntroFundo'),
      nome: on('reguaIntroNome'), opcoes: !!document.getElementById('introOpcoes').offsetParent,
      explica: document.getElementById('explicaIntroEfeito').textContent };
  });
  const r = await regua();
  igual('a seção, com os quatro efeitos, nascendo em "Sem abertura"', [r.titulo, r.efeito],
    ['🎬Abertura', ['Sem abertura ●', 'Aparecer', 'Deslizar', 'Brilho']]);
  igual('sem efeito, tempo, fundo e nome ficam escondidos', r.opcoes, false);

  await p.click('#reguaIntroEfeito button:has-text("Deslizar")');
  await p.waitForTimeout(150);
  const tocando = await p.evaluate(() => {
    const el = document.querySelector('#previaFone .fone .intro');
    return el ? { classe: el.className, nome: (el.querySelector('.intro-nome') || {}).textContent,
      fundo: el.style.getPropertyValue('--i-fundo').trim().toUpperCase(),
      dentro: el.parentElement.classList.contains('fone') } : null;
  });
  igual('escolher o efeito já toca a abertura dentro do celular da prévia',
    tocando && [tocando.classe, tocando.nome, tocando.dentro], ['intro intro-deslizar', 'Salão Megatop', true]);
  igual('na cor do botão do salão, e não na do painel', tocando && tocando.fundo, '#B8356B');
  const r2 = await regua();
  igual('aparecem as outras réguas, cada uma no padrão', [r2.opcoes, r2.tempo, r2.fundo, r2.nome],
    [true, ['Rápida · 1s', 'Normal · 2s ●', 'Longa · 3s'], ['Cor do botão ●', 'Fundo da página'],
     ['Com o nome ●', 'Só o logo']]);
  verdade('e a explicação diz o que o efeito faz', /cortina/.test(r2.explica), r2.explica);
  await p.waitForTimeout(2600);
  igual('a abertura da prévia sai sozinha', await p.evaluate(() => !!document.querySelector('#previaFone .intro')), false);

  await p.click('#reguaIntroTempo button:has-text("Rápida")');
  await p.click('#btVerIntro');
  await p.waitForTimeout(100);
  igual('"Ver a abertura" toca de novo, no tempo novo', await p.evaluate(() => {
    const el = document.querySelector('#previaFone .intro');
    return el ? el.style.getPropertyValue('--intro-ms') : null; }), '1200ms');
  await p.click('#previaFone .intro');
  await p.waitForTimeout(600);
  igual('e um toque na prévia pula', await p.evaluate(() => !!document.querySelector('#previaFone .intro')), false);
  verdade('com mudança sem salvar, a barra avisa', await p.evaluate(() =>
    document.getElementById('apBarra').classList.contains('suja')));

  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(2500);
  const c = await cfgDe();
  // O jsonb do banco guarda as chaves na ordem dele: compara-se sem ordem.
  const emOrdem = o => o && typeof o === 'object' ? Object.fromEntries(Object.entries(o).sort()) : o;
  igual('salvo: o banco guarda o objeto da abertura', emOrdem(c.intro),
    emOrdem({ efeito:'deslizar', tempo:'rapida', fundo:'marca', nome:true }));
  igual('e o resto da aparência continua lá', c.cores && c.cores.botao, '#B8356B');
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. No link: a abertura, e ela sai sozinha');
{
  const ctx = await celular();
  const p = await abrir(ctx);
  const i = await lerIntro(p);
  verdade('ao abrir, a abertura cobre a tela inteira', i && i.cobre, JSON.stringify(i));
  igual('com o logo do salão e o nome embaixo', i && [i.img, i.nome], [true, 'Salão Megatop']);
  igual('no efeito e no tempo escolhidos', i && [i.classe, i.ms], ['intro intro-deslizar', '1200ms']);
  igual('e diz para leitor de tela que dá para pular', i && i.rotulo, 'Pular a abertura');
  verdade('no fundo da cor do botão, em degradê', i && /radial-gradient/.test(i.fundo), i && i.fundo);
  await p.waitForTimeout(1900);
  igual('depois do tempo, ela sai e a capa fica', [await p.evaluate(() => !!document.getElementById('intro')),
    await p.evaluate(() => tela)], [false, 'capa']);

  secao('4. Uma vez por visita');
  await p.reload();
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  igual('recarregar a página não toca de novo', await lerIntro(p), null);
  const ctx2 = await celular();
  const p2 = await abrir(ctx2);
  verdade('abrir o link de novo, noutra visita, toca', !!(await lerIntro(p2)));

  secao('5. Um toque pula');
  await p2.click('#intro');
  await p2.waitForTimeout(550);
  igual('tocar na abertura tira ela da frente na hora', await p2.evaluate(() => !!document.getElementById('intro')), false);
  await ctx.close();
  await ctx2.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Sem o nome, no fundo da página, com o logo quadrado');
await porCfg({ logoForma:'quadrado', intro:{ efeito:'brilho', tempo:'longa', fundo:'pagina', nome:false } });
{
  const ctx = await celular();
  const p = await abrir(ctx);
  const i = await lerIntro(p);
  igual('efeito "brilho", 3 segundos, fundo da página', i && [i.classe, i.ms],
    ['intro intro-brilho intro-pagina', '3000ms']);
  igual('só o logo, sem o nome', i && [i.img, i.nome], [true, null]);
  verdade('no papel da página, sem degradê', i && i.fundo.startsWith(i.papel) && /none/.test(i.fundo),
    i && (i.fundo + ' / ' + i.papel));
  igual('o logo com o canto do "quadrado"', i && i.raio, '6px');
  const faixa = await p.evaluate(() =>
    getComputedStyle(document.querySelector('#intro .intro-logo'), '::after').animationName);
  igual('e a faixa de luz passando', faixa, 'intro-luz');
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. "Reduzir movimento" no celular');
{
  const ctx = await celular({ reducedMotion:'reduce' });
  const p = await abrir(ctx);
  const i = await lerIntro(p);
  igual('a abertura aparece curta e parada', i && [i.ms, i.anima], ['700ms', 'none']);
  await p.waitForTimeout(1300);
  igual('e sai logo', await p.evaluate(() => !!document.getElementById('intro')), false);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('8. Lixo no banco não derruba a página');
for(const lixo of [{ efeito:'abacaxi' }, 'deslizar', 42]){
  await porCfg({ intro: lixo });
  const ctx = await celular();
  const p = await abrir(ctx);
  igual(`intro = ${JSON.stringify(lixo)}: a página abre, sem abertura`,
    [await p.evaluate(() => tela), await lerIntro(p)], ['capa', null]);
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
