/* ===========================================================================
   AgendaPro — cada botão da Aparência muda o link de verdade

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/aparencia-link.test.mjs

   O pedido: "configurei a aparência, porém não está obedecendo… cliquei
   curvada e não foi… faz uma varredura então toda a aparência, pq todos os
   botões têm que funcionar."

   Os outros testes da Aparência conferem cada chave pelo NOME: sabem que a
   moldura existe e medem o efeito dela. Este aqui não sabe nome nenhum. Ele
   abre a aba como o dono, acha TODOS os botões, quadrados de cor,
   deslizantes e modelos que existem nela, e para cada um:

       clica no painel → Salvar → abre o link da cliente → algo mudou?

   "Algo mudou" é medido por uma impressão da página inteira: as marcas do
   <html> e do <body>, as variáveis de cor, e o estilo calculado de cada
   elemento (cor, fundo, borda, raio, sombra, letra, proporção, máscara,
   animação). Botão novo que alguém puser na aba entra aqui sozinho — e, se
   não chegar ao link, este arquivo acusa sem ninguém ter escrito o nome dele.

   ⚠ O "Curvada" foi a origem: num salão sem foto nos serviços, ela deixava a
   página praticamente igual à Clássica (a curva mora na foto). A seção 2
   cobre esse caso de propósito.
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
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="${a}"/>`
  + `<circle cx="320" cy="180" r="120" fill="${b}"/></svg>`).toString('base64');

/* ── UM SALÃO COM TUDO ────────────────────────────────────────────────────
   Cada botão só tem onde aparecer se a peça dele existir: a fita precisa de
   produto no carrinho, o slide de galeria, o véu de foto de fundo, o "Ver
   todos os serviços" de mais serviços do que cabem na capa. Salão pobre faria
   botão bom parecer quebrado. */
const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`al-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Varredura',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'00:00', fim:'23:59' });
}
const NOMES = ['Corte feminino', 'Escova', 'Hidratação', 'Manicure', 'Pedicure', 'Sobrancelha', 'Coloração', 'Luzes'];
for(const [i, nome] of NOMES.entries()){
  await dona.inserir('servicos', { salaoId: SALAO, nome, duracaoMin:30 + i * 5, intervaloMin:0,
    preco:50 + i * 10, ativo:true, aceitaOnline:true, categoria: i < 4 ? 'Cabelo' : 'Unhas',
    descricao:'Feito com cuidado e produto de qualidade',
    foto: arte('#7C3AED', ['#C084FC', '#F0ABFC', '#A78BFA', '#DDD6FE'][i % 4]) });
}
for(const [i, nome] of ['Shampoo', 'Máscara', 'Óleo'].entries()){
  await dona.inserir('produtos', { salaoId: SALAO, nome, preco:30 + i * 5, custo:10, estoque:9,
    ativo:true, vendaOnline:true, foto: arte('#0E7490', '#67E8F9') });
}
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const ENDERECO = { logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' };
await dona.atualizar('saloes', SALAO, {
  endereco: ENDERECO, whatsapp:'11988887777',
  logo: arte('#4C1D95', '#A78BFA'), capa: arte('#2E1065', '#7C3AED'),
  cfg: { diasLiberados:30, cor:'#6D28D9', funcionamento: SEMANA, pagamentos:{ formas:['pix'] },
         sobre:'Salão de beleza', fundo: arte('#7a4a2a', '#d9a066'),
         galeria:[{ url: arte('#4C1D95','#9333EA'), tipo:'imagem', legenda:'Antes e depois' },
                  { url: arte('#7C3AED','#F0ABFC'), tipo:'imagem', legenda:'Nosso espaço' }] } });
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
ok('salão criado: logo, capa, fundo, galeria, 8 serviços com foto, 3 produtos');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* ── O LINK, E A IMPRESSÃO DELE ───────────────────────────────────────────
   A abertura (intro) dura um ou dois segundos e some: em vez de correr atrás
   dela, um observador guarda como ela nasceu. As animações são paradas no
   zero antes de medir — uma fita brilhando no meio do caminho daria uma
   "mudança" que nenhum botão causou. */
const ctxLink = await nav.newContext({ viewport:{ width:412, height:915 }, isMobile:true, hasTouch:true });
await ctxLink.addInitScript(() => {
  new MutationObserver(() => {
    const el = document.getElementById('intro');
    if(el && !window.__intro) window.__intro = el.className + '|' + el.style.getPropertyValue('--intro-ms')
      + '|' + !!el.querySelector('.intro-nome') + '|' + getComputedStyle(el).backgroundColor
      + '|' + getComputedStyle(el).backgroundImage;
  // `document`, e não o <html>: o script entra antes de o <html> existir.
  }).observe(document, { childList:true, subtree:true });
});
async function impressao(){
  const c = await ctxLink.newPage();
  c.on('pageerror', e => erros.push('link: ' + e.message));
  await c.goto(BASE + '/agendar.html?salao=' + SLUG);
  await c.waitForFunction(() => document.querySelector('#capaServicos .sv-cartao')
    && document.querySelector('.marca-salao'), null, { timeout: 15000 });
  await c.waitForTimeout(500);
  const r = await c.evaluate(() => {
    document.getAnimations().forEach(a => { try{ a.pause(); a.currentTime = 0; }catch(e){} });
    const P = ['color','backgroundColor','backgroundImage','borderTopColor','borderTopWidth',
      'borderTopLeftRadius','borderBottomLeftRadius','boxShadow','fontFamily','fontWeight',
      'textTransform','letterSpacing','aspectRatio','maskImage','webkitMaskImage','clipPath',
      'animationDuration','animationName','backdropFilter','gridTemplateColumns','display',
      'backgroundPosition','objectPosition'];
    const fora = ['html ' + [...document.documentElement.attributes].map(a => a.name + '=' + a.value).sort().join(' '),
      'body ' + document.body.className + ' ' + (document.body.getAttribute('style') || ''),
      'intro ' + (window.__intro || '')];
    let n = 0;
    for(const e of document.body.querySelectorAll('*')){
      if(++n > 2500) break;
      if(/^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(e.tagName) || e.id === 'intro' || e.closest('#intro')) continue;
      const cs = getComputedStyle(e);
      if(cs.display === 'none') continue;
      let s = e.tagName + '#' + e.id + '.' + (typeof e.className === 'string' ? e.className : '');
      for(const p of P) s += '|' + cs[p];
      for(const pe of ['::before', '::after']){
        const c2 = getComputedStyle(e, pe);
        if(c2.content && c2.content !== 'none' && c2.content !== 'normal')
          s += pe + c2.backgroundImage + c2.backgroundColor + c2.animationName + c2.animationDuration + c2.opacity;
      }
      fora.push(s);
    }
    return fora;
  });
  await c.close();
  return r;
}
const diferencas = (a, b) => {
  let d = 0;
  for(let i = 0; i < Math.max(a.length, b.length); i++) if(a[i] !== b[i]) d++;
  return d;
};

/* ── O PAINEL ─────────────────────────────────────────────────────────── */
const ctx = await nav.newContext({ viewport:{ width:1280, height:1000 } });
const p = await ctx.newPage();
p.on('pageerror', e => erros.push('painel: ' + e.message));
p.on('dialog', d => d.accept());
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
const RAIZ_AP = '#painelSalao .sub-tela[data-sub="aparencia"]';
const abrirDobras = () => p.evaluate(r => document.querySelector(r)
  .querySelectorAll('details').forEach(d => { d.open = true; }), RAIZ_AP);

/* Salvar e esperar o banco. Se o cfg não mudar, o botão nem chegou a gravar
   — e isso já é a falha, antes de olhar o link.
   O "Usar este modelo" salva sozinho: aí a barra já volta limpa, e o que vale
   é o banco ter mudado. */
async function salvarEsperando(antes){
  const suja = await p.evaluate(() => document.getElementById('apBarra').classList.contains('suja'));
  if(suja) await p.locator('#apBarra .btn-p').click();
  for(let i = 0; i < 40; i++){
    await p.waitForTimeout(150);
    const agora = JSON.stringify(await cfgDe());
    if(agora !== antes) return { gravou: true, cfg: agora };
  }
  return { gravou: false, motivo: suja ? 'salvou, mas o banco continuou igual'
    : 'a barra não acusou mudança para salvar (o Salvar nem apareceu)' };
}

let cfgAtual = JSON.stringify(await cfgDe());
let fotoAtual = await impressao();
const semEfeito = [];
async function conferir(nome, agir){
  await agir();
  await p.waitForTimeout(150);
  const s = await salvarEsperando(cfgAtual);
  if(!s.gravou){ nao(nome + ': ' + s.motivo); semEfeito.push(nome); return; }
  cfgAtual = s.cfg;
  const nova = await impressao();
  const d = diferencas(fotoAtual, nova);
  fotoAtual = nova;
  if(d > 0) ok(`${nome} — o link mudou (${d} ${d === 1 ? 'peça' : 'peças'})`);
  /* Vidro e Automático são o MESMO desenho enquanto há bastante branco por
     cima da foto — o Automático só fecha com o véu abaixo de 35. Aí o clique
     não muda nada de verdade, e o que se cobra é a tela dizer isso. */
  else if(/^reguaCartoes:(Vidro|Automático)$/.test(nome)
       && / igual ao (Vidro|Automático)\./.test(await p.evaluate(() => document.getElementById('explicaCartoes').textContent)))
    ok(`${nome} — igual ao vizinho com este fundo, e a tela avisa`);
  else { nao(`${nome}: gravou, mas o link ficou idêntico`); semEfeito.push(nome); }
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — TODOS OS BOTÕES DE ESCOLHA (as réguas)
   Achados na tela, não numa lista escrita aqui. A régua escondida (Cartões só
   com foto de fundo, as da abertura só com abertura ligada) entra quando o
   botão que a revela é clicado — por isso o laço volta a procurar até não
   sobrar botão novo.
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. Cada botão de cada régua');
const feitos = new Set();
for(let volta = 0; volta < 200; volta++){
  await abrirDobras();
  const prox = await p.evaluate(([r, f]) => {
    const feito = new Set(f);
    for(const g of document.querySelector(r).querySelectorAll('.regua[id], #paletaCores')){
      if(!g.offsetParent) continue;
      for(const [i, b] of [...g.querySelectorAll('button')].entries()){
        const chave = g.id + ':' + b.textContent.trim();
        if(feito.has(chave) || b.classList.contains('on') || b.disabled || !b.offsetParent) continue;
        return { id: g.id, i, chave };
      }
    }
    return null;
  }, [RAIZ_AP, [...feitos]]);
  if(!prox) break;
  feitos.add(prox.chave);
  await conferir(prox.chave, () => p.locator(`#${prox.id} button`).nth(prox.i).click());
}
const todas = await p.evaluate(r => [...document.querySelector(r).querySelectorAll('.regua[id]')]
  .flatMap(g => [...g.querySelectorAll('button')].map(b => g.id + ':' + b.textContent.trim())), RAIZ_AP);
const nunca = todas.filter(k => !feitos.has(k));
/* O que sobra é o botão que estava aceso desde o começo e nunca se apagou —
   não dá para "clicar e ver mudar" o que já está escolhido. Cada um desses
   tem que ter sido apagado por um vizinho e clicado de volta. */
igual('nenhum botão de régua ficou sem ser clicado', nunca, []);
verdade('e foram dezenas deles, não meia dúzia', feitos.size >= 60, String(feitos.size));

/* ══════════════════════════════════════════════════════════════════════════
   2 — A CURVADA NUM SALÃO SEM FOTO NOS SERVIÇOS
   O caso da reclamação. A curva mora na foto: sem foto, a Curvada ganha a
   capa com a inicial, e a Clássica continua a lista de linhas de sempre.
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. Curvada sem foto nos serviços');
{
  const fotos = await dona.lista('servicos', { salaoId: SALAO });
  for(const s of fotos) await dona.atualizar('servicos', s.id, { foto: null });
  const forma = async mold => {
    const c = Object.assign(await cfgDe(), { moldura: mold });
    await dona.atualizar('saloes', SALAO, { cfg: c });
    const pg = await ctxLink.newPage();
    pg.on('pageerror', e => erros.push('link: ' + e.message));
    await pg.goto(BASE + '/agendar.html?salao=' + SLUG);
    await pg.waitForFunction(() => document.querySelector('#capaServicos .sv-cartao'), null, { timeout: 15000 });
    await pg.waitForTimeout(400);
    const r = await pg.evaluate(() => {
      const c = document.querySelector('#capaServicos .sv-cartao');
      const f = c.querySelector('.sv-cartao-foto');
      return { grade: document.querySelector('#capaServicos .sv-grade').classList.contains('com-foto'),
        capa: !!f, inicial: f ? f.textContent.trim() : '', mascara: f ? getComputedStyle(f).maskImage !== 'none' : false,
        lado: [...document.querySelectorAll('#capaServicos .sv-cartao')].slice(0, 2)
          .map(e => Math.round(e.getBoundingClientRect().top)) };
    });
    await pg.close();
    return r;
  };
  const curva = await forma('elegante');
  verdade('Curvada: cada serviço ganha a capa com a inicial', curva.capa && /^[A-ZÀ-Ú]$/.test(curva.inicial), JSON.stringify(curva));
  verdade('e a capa termina na curva (a máscara da onda)', curva.mascara, JSON.stringify(curva));
  verdade('em grade de dois em dois, como a prévia mostra', curva.grade && curva.lado[0] === curva.lado[1], JSON.stringify(curva));
  const reta = await forma('reta');
  igual('Clássica sem foto: continua a lista de linhas, sem capa nenhuma',
    { grade: reta.grade, capa: reta.capa }, { grade: false, capa: false });
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — CADA QUADRADO DE COR E CADA DESLIZANTE
   Pelo evento de verdade (`input`), que é o que o dedo dispara — chamar a
   função direto pularia justamente o fio que pode estar solto.
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. Cada quadrado de cor e cada deslizante');
{
  // Os serviços voltam a ter foto: a descrição e a duração só aparecem nos
  // cartões, e o slide de serviços precisa delas.
  const svs = await dona.lista('servicos', { salaoId: SALAO });
  for(const [i, s] of svs.entries()) await dona.atualizar('servicos', s.id, { foto: arte('#7C3AED', ['#C084FC', '#F0ABFC'][i % 2]) });
  // Parte do painel com a cor nova dos serviços (a foto mudou fora dele).
  await p.reload();
  await p.waitForFunction(() => typeof irPara === 'function' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1000);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(300);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(600);
  // Fundo de imagem (o véu precisa dele), atalhos com sombra (os três
  // deslizantes dela) e o slide das minhas fotos (a legenda).
  await p.evaluate(() => { aparencia.fundoTipo = 'imagem'; aparencia.slideDe = 'galeria';
    aparencia.atalhos.estilo = 'sombra'; aparencia.moldura = 'elegante'; pintarAparencia(); });
  await salvarEsperando(cfgAtual).then(s => { if(s.gravou) cfgAtual = s.cfg; });
  fotoAtual = await impressao();
  await abrirDobras();
  const PALETA = ['#C2185B', '#1565C0', '#2E7D32', '#EF6C00', '#6A1B9A', '#00838F', '#AD1457', '#4E342E'];
  const campos = await p.evaluate(r => [...document.querySelector(r)
    .querySelectorAll('input[type="color"], input[type="range"]')]
    .filter(i => i.offsetParent && i.id !== 'corLivre' && !i.closest('#gradienteCampos'))
    .map((i, n) => { if(!i.dataset.varredura) i.dataset.varredura = 'c' + n;
      return { sel: i.dataset.varredura, tipo: i.type, valor: i.value, min: i.min, max: i.max,
        nome: (i.closest('.cor-linha') || {}).dataset ? ((i.closest('.cor-linha').dataset.chave) || i.id || i.getAttribute('aria-label'))
            : (i.id || i.getAttribute('aria-label')) }; }), RAIZ_AP);
  verdade('achou os quadrados de cor e os deslizantes', campos.length >= 40, String(campos.length));
  for(const [n, c] of campos.entries()){
    let novo;
    if(c.tipo === 'color'){
      novo = PALETA[n % PALETA.length];
      if(novo.toLowerCase() === c.valor.toLowerCase()) novo = PALETA[(n + 1) % PALETA.length];
    } else {
      const lo = Number(c.min || 0), hi = Number(c.max || 100), v = Number(c.valor);
      novo = String(Math.abs(v - hi) > Math.abs(v - lo) ? hi : lo);
    }
    await conferir(`${c.tipo === 'color' ? 'cor' : 'deslizante'} ${c.nome || c.sel}`, () => p.evaluate(([s, v]) => {
      const el = document.querySelector(`[data-varredura="${s}"]`);
      el.value = v;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }, [c.sel, novo]));
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — O "AGENDE SEU HORÁRIO" TEM COR
   Era a única frase do topo sem escolha. Ela só aparece quando o endereço não
   está preenchido — o salão de teste perde o endereço para ela existir.
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. A cor do "Agende seu horário"');
{
  await dona.atualizar('saloes', SALAO, { endereco: {} });
  const lerSub = async () => {
    const pg = await ctxLink.newPage();
    await pg.goto(BASE + '/agendar.html?salao=' + SLUG);
    await pg.waitForFunction(() => document.querySelector('.marca-salao'), null, { timeout: 15000 });
    await pg.waitForTimeout(400);
    const r = await pg.evaluate(() => { const e = document.querySelector('.marca-salao .sub');
      return e ? { txt: e.textContent.trim(), cor: getComputedStyle(e).color } : null; });
    await pg.close();
    return r;
  };
  const c0 = Object.assign(await cfgDe(), {});
  c0.cores = Object.assign({}, c0.cores); delete c0.cores.subtitulo; delete c0.cores.texto;
  await dona.atualizar('saloes', SALAO, { cfg: c0 });
  const antes = await lerSub();
  igual('sem endereço, a frase aparece embaixo do nome', antes && antes.txt, 'Agende seu horário');
  await dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, c0, { cores: Object.assign({}, c0.cores, { subtitulo:'#C2185B' }) }) });
  const depois = await lerSub();
  igual('com cor escolhida, ela muda de cor', depois && depois.cor, 'rgb(194, 24, 91)');
  verdade('e antes estava em outra cor (a do texto)', antes && antes.cor !== 'rgb(194, 24, 91)', JSON.stringify(antes));

  await p.reload();
  await p.waitForFunction(() => typeof irPara === 'function' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1000);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(300);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(600);
  const tela = await p.evaluate(() => {
    const l = document.querySelector('#coresFrases .cor-linha[data-chave="subtitulo"]');
    const pv = document.querySelector('#previaFone [data-cfg="subtitulo"]');
    return { rot: l && l.querySelector('b').textContent.trim(),
      ajuda: l && l.querySelector('.cor-linha-ajuda').textContent,
      quadrado: l && l.querySelector('input[type="color"]').value.toUpperCase(),
      previa: pv && getComputedStyle(pv).color };
  });
  igual('no painel, a linha "Agende seu horário" junto das frases do topo', tela.rot, 'Agende seu horário');
  verdade('dizendo quando ela aparece', /endereço não está preenchido/.test(tela.ajuda || ''), tela.ajuda);
  igual('o quadrado mostra a cor escolhida', tela.quadrado, '#C2185B');
  igual('e a prévia pinta a frase na mesma cor', tela.previa, 'rgb(194, 24, 91)');
  await dona.atualizar('saloes', SALAO, { endereco: ENDERECO });
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — OS MODELOS PRONTOS
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. Cada modelo pronto, usado e salvo');
{
  await p.reload();
  await p.waitForFunction(() => typeof irPara === 'function' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1000);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(300);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(600);
  cfgAtual = JSON.stringify(await cfgDe());
  fotoAtual = await impressao();
  const modelos = await p.evaluate(() => [...document.querySelectorAll('[data-modelo]')].map(e => e.dataset.modelo));
  verdade('há modelos prontos na tela', modelos.length >= 5, String(modelos.length));
  for(const id of modelos){
    await conferir(`modelo ${id}`, async () => {
      await p.locator(`[data-modelo="${id}"]`).first().click();
      await p.waitForTimeout(200);
      const usar = p.locator('button', { hasText: 'Usar este modelo' });
      if(await usar.count()) await usar.first().click();
    });
  }
}

secao('6. Nada quebrou no caminho');
igual('sem erro de JavaScript no painel nem no link', erros.slice(0, 5), []);
if(semEfeito.length) console.log('\n  Sem efeito no link: ' + semEfeito.join(', '));

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
