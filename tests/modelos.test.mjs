/* ===========================================================================
   AgendaPro — os modelos prontos da Aparência

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/modelos.test.mjs

   O pedido: "É possível criar modelos prontos? Para a pessoa chegar e clicar
   e, se gostar, usar? Não colocar o nome por profissão, mas cria do seu
   jeito. E fotos, produtos e serviços a pessoa acrescentar como quiser."

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a seção: primeira da tela, dez modelos ou mais, nomes de estilo;
     2. experimentar muda a prévia e NÃO grava nada;
     3. "Voltar ao que eu tinha" devolve a aparência exata, mesmo depois de
        passar por dois modelos e mexer numa cor;
     4. todo modelo se lê: o aviso de legibilidade fica calado em cada um;
     5. "Usar este modelo" grava o modelo inteiro e deixa em paz fotos,
        serviços, produtos e o resto do cfg;
     6. na página da cliente, cada modelo chega com as cores dele, e a letra
        do botão se lê.
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
// jsonb não guarda a ordem das chaves: compara com as chaves em ordem.
const ordenado = o => o && typeof o === 'object' && !Array.isArray(o)
  ? Object.fromEntries(Object.keys(o).sort().map(k => [k, ordenado(o[k])])) : o;

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

/* Os modelos, lidos do próprio painel: o teste não guarda uma cópia que
   possa ficar para trás. */
const fonte = fs.readFileSync(path.join(RAIZ, 'app.html'), 'utf8');
const ini = fonte.indexOf('const MODELOS_PRONTOS = [');
const MODELOS = eval(fonte.slice(ini + 'const MODELOS_PRONTOS = '.length, fonte.indexOf('\n];', ini) + 3));

const lum = h => { const [r, g, b] = [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255)
  .map(c => c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const contraste = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`mo-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino', duracaoMin:30, intervaloMin:0,
  preco:90, ativo:true, aceitaOnline:true, categoria:'Cabelo', foto: arte('#7C3AED', '#C084FC') });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Hidratação', duracaoMin:40, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const LOGO = arte('#4C1D95', '#A78BFA'), CAPA = arte('#2E1065', '#7C3AED'), FUNDO = arte('#111111', '#333333');
/* O que é do salão, e não do estilo: nenhum modelo pode tocar. */
const DO_SALAO = { diasLiberados:30, precoNaCapa:true, slideDe:'galeria', capaFoco:30, veu:60,
  cartoes:'vidro', slideForma:'quadrado', funcionamento: SEMANA, pagamentos:{ formas:['pix'] },
  sobre:'Salão de beleza', fundo: FUNDO };
const ANTES = Object.assign({}, DO_SALAO, { cor:'#1D4ED8', tema:'claro', modo:'atual', moldura:'reta',
  letra:'moderno', fundoTipo:'imagem', gradiente:'#111111,#222222', fitaCor:'#FF0000',
  // `produtos` fica de fora de quase todo modelo: o de antes não pode sobrar.
  cores:{ botao:'#5B21B6', texto:'#222222', produtos:'#0000FF' },
  atalhos:{ estilo:'borda', cores:{ horarios:'#0E7490' } }, logoBorda:'grossa' });
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  logo: LOGO, capa: CAPA, cfg: ANTES });
const salao = async () => (await dona.lista('saloes', { id: SALAO }))[0];

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
const experimentar = async (p, id) => {
  await p.locator(`.modelo[data-modelo="${id}"]`).click();
  await p.waitForTimeout(250);
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — A SEÇÃO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. A seção dos modelos');
const { p, fechar } = await painel();
{
  const t = await p.evaluate(() => ({
    primeira: document.querySelector('.ap-controles .ap-sec').id,
    cartoes: [...document.querySelectorAll('#listaModelos .modelo')].map(b => ({
      id: b.dataset.modelo, nome: b.querySelector('b').textContent.trim(),
      frase: b.querySelector('small').textContent.trim(),
      mini: !!b.querySelector('.modelo-tela .modelo-botao') })),
    barra: getComputedStyle(document.getElementById('modeloBarra')).display,
    indice: document.querySelector('.ap-indice button').textContent.trim(),
  }));
  igual('é a primeira seção da tela', t.primeira, 'apModelos');
  verdade('e a primeira do índice do topo', /Modelos prontos/.test(t.indice), t.indice);
  verdade('dez modelos ou mais — ' + t.cartoes.length, t.cartoes.length >= 10);
  igual('um cartão para cada modelo, na ordem', t.cartoes.map(c => c.id), MODELOS.map(x => x.id));
  igual('nenhum nome repetido', new Set(t.cartoes.map(c => c.nome)).size, t.cartoes.length);
  verdade('cada cartão tem a miniatura e uma frase',
    t.cartoes.every(c => c.mini && c.frase.length > 10), JSON.stringify(t.cartoes.filter(c => !c.mini || c.frase.length <= 10)));
  /* "Não colocar o nome por profissão." */
  const PROFISSAO = /sal[aã]o|manicure|pedicure|unha|\bgel\b|veterin|\bpets?\b|m[eé]dic|cl[ií]nic|psic[oó]|terap|barbe|est[eé]tic|consult[oó]rio|cabel/i;
  const comProfissao = t.cartoes.filter(c => PROFISSAO.test(c.nome + ' ' + c.frase));
  igual('nenhum nome ou frase fala de profissão', comProfissao.map(c => c.nome), []);
  igual('sem modelo na prévia, a barra não aparece', t.barra, 'none');
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — EXPERIMENTAR NÃO GRAVA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. Experimentar muda a prévia, e só ela');
const cfgAntes = ordenado((await salao()).cfg);
const apAntes = await p.evaluate(() => JSON.stringify(aparencia));
{
  const mo = MODELOS.find(x => x.id === 'dourada');
  await experimentar(p, 'dourada');
  const t = await p.evaluate(() => {
    const f = document.querySelector('#previaFone .fone');
    return {
      on: [...document.querySelectorAll('.modelo.on')].map(b => b.dataset.modelo),
      barra: document.getElementById('modeloBarra').textContent.replace(/\s+/g, ' ').trim(),
      escuro: f.classList.contains('fone-escuro'),
      modo: f.dataset.modo, logo: f.dataset.logo, atalhos: f.dataset.atalhos,
      estilo: f.getAttribute('style'),
      capaReta: !!document.querySelector('#previaFone .fone-capa.reta'),
      letra: document.querySelector('#previaFone .fone-topo').dataset.letra,
      fita: document.querySelector('#previaFone .fone-fita').dataset.metal,
      aviso: document.getElementById('avisoLegibilidade').textContent.trim(),
      icones: [document.querySelectorAll('#previaFone [data-ico]').length,
               document.querySelectorAll('#previaFone .fone-recurso svg').length],
      convite: getComputedStyle(document.querySelector('#previaFone .fone-boas-sub')).color,
    };
  });
  igual('o cartão tocado fica marcado', t.on, ['dourada']);
  verdade('a barra diz qual está na prévia e que nada foi salvo',
    t.barra.includes(mo.nome) && /Nada foi salvo/.test(t.barra) && /Usar este modelo/.test(t.barra)
    && /Voltar ao que eu tinha/.test(t.barra), t.barra);
  verdade('a prévia fica escura, no modo, na logo e nos atalhos do modelo',
    t.escuro && t.modo === mo.modo && t.logo === mo.logoForma && t.atalhos === mo.atalhos.estilo, JSON.stringify(t));
  verdade('com as cores dele (botão, títulos, cartão, papel)',
    ['botao', 'titulo', 'card', 'papel'].every(k => t.estilo.includes(`--fone-${k}:${mo.cores[k]}`)), t.estilo);
  verdade('a divisão da foto, a letra e a fita dele',
    t.capaReta === (mo.capaForma === 'reta') && t.letra === mo.letra && t.fita === mo.fita.metal, JSON.stringify(t));
  igual('e o banco continua como estava', ordenado((await salao()).cfg), cfgAntes);
  /* Dois defeitos da prévia que os modelos puseram à vista: os ícones sumiam
     a cada mudança, e o convite do Bem-vindo ficava no cinza do painel. */
  igual('os ícones da prévia continuam desenhados depois da troca', t.icones, [0, 3]);
  const rgb = h => 'rgb(' + [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16)).join(', ') + ')';
  igual('e o convite do Bem-vindo na cor de texto do modelo', t.convite, rgb(mo.cores.texto));
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — VOLTAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. "Voltar ao que eu tinha" devolve tudo');
{
  await experimentar(p, 'neon');
  // Mexer numa cor com o modelo na prévia: o Voltar desfaz isto também.
  await p.evaluate(() => escolherCorSolta('titulo', '#123456'));
  await p.getByText('Voltar ao que eu tinha').click();
  await p.waitForTimeout(250);
  const t = await p.evaluate(() => ({ ap: JSON.stringify(aparencia),
    on: document.querySelectorAll('.modelo.on').length,
    barra: getComputedStyle(document.getElementById('modeloBarra')).display }));
  igual('passando por dois modelos e mexendo numa cor, a aparência volta exata', JSON.parse(t.ap), JSON.parse(apAntes));
  igual('nenhum cartão marcado, e a barra some', [t.on, t.barra], [0, 'none']);
  igual('nada foi gravado', ordenado((await salao()).cfg), cfgAntes);
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — TODO MODELO SE LÊ
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. Cada modelo, conferido pela própria tela');
{
  const avisos = [];
  for(const mo of MODELOS){
    await experimentar(p, mo.id);
    const t = await p.evaluate(() => ({
      aviso: document.getElementById('avisoLegibilidade').textContent.trim(),
      intensidade: aparencia.atalhos.sombra.intensidade,
      cores: aparencia.atalhos.cores,
    }));
    if(t.aviso) avisos.push(mo.nome + ': ' + t.aviso);
    if(mo.atalhos.sombra){
      const s = mo.atalhos.sombra;
      const pronta = { suave:[16, 10, 4], media:[24, 16, 8], forte:[34, 26, 12] };
      const bate = Object.keys(pronta).find(k => pronta[k].join() === [s.desfoque, s.opacidade, s.distancia].join());
      if(t.intensidade !== (bate || 'personalizada'))
        avisos.push(mo.nome + ': intensidade ' + t.intensidade + ', esperava ' + (bate || 'personalizada'));
    }
    if(Object.keys(t.cores).length) avisos.push(mo.nome + ': cor de atalho do antes ficou: ' + JSON.stringify(t.cores));
  }
  igual('nenhum dos ' + MODELOS.length + ' acende o "Difícil de ler", e a sombra marca a intensidade certa', avisos, []);
  const ruins = [];
  for(const mo of MODELOS){
    const c = mo.cores;
    const fundos = mo.fundoTipo === 'gradiente' ? mo.gradiente.split(',') : [c.papel];
    const letra = contraste(c.botao, '#FFFFFF') >= contraste(c.botao, '#000000') ? '#FFFFFF' : '#000000';
    const pior = (cor, alvos) => Math.min(...alvos.map(f => contraste(cor, f)));
    if(pior(c.titulo, [...fundos, c.card]) < 4.5) ruins.push(mo.nome + ' título');
    if(pior(c.texto, [...fundos, c.card]) < 4.5) ruins.push(mo.nome + ' texto');
    if(pior(c.destaque, [c.card]) < 4.5) ruins.push(mo.nome + ' preço');
    if(contraste(c.botao, letra) < 4.5) ruins.push(mo.nome + ' letra do botão');
  }
  igual('e pela régua mais dura: títulos, texto, preço e botão a 4,5:1', ruins, []);
  await p.getByText('Voltar ao que eu tinha').click();
  await p.waitForTimeout(200);
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — USAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. "Usar este modelo" grava o modelo, e só o modelo');
const esperadoNoBanco = mo => ordenado({
  cor: mo.cor, tema: mo.tema, fundoTipo: mo.fundoTipo === 'cor' ? 'solida' : mo.fundoTipo,
  cores: mo.cores, modo: mo.modo, logoForma: mo.logoForma, logoBorda: mo.logoBorda,
  moldura: mo.moldura, letra: mo.letra, capaForma: mo.capaForma, brilho: mo.brilho,
  atalhos: { estilo: mo.atalhos.estilo, cores: {} }, botaoProdutos: mo.botaoProdutos,
  // Modelo de cor lisa guarda o gradiente que ele já tinha montado.
  gradiente: mo.gradiente || ANTES.gradiente,
  fitaMetal: mo.fita.metal, fitaBorda: mo.fita.borda, fitaBrilho: mo.fita.brilho,
  fitaTempo: mo.fita.tempo, fitaCor: null,
});
const doBanco = cfg => ordenado(Object.assign({}, Object.fromEntries(Object.keys(esperadoNoBanco(MODELOS[0]))
  .map(k => [k, cfg[k]])), { atalhos: { estilo: cfg.atalhos.estilo, cores: cfg.atalhos.cores } }));
{
  const mo = MODELOS.find(x => x.id === 'rose');
  await experimentar(p, 'rose');
  await p.getByText('Usar este modelo').click();
  await p.waitForTimeout(1800);
  const s = await salao();
  igual('o banco tem o modelo inteiro', doBanco(s.cfg), esperadoNoBanco(mo));
  igual('com a sombra dos atalhos dele',
    [s.cfg.atalhos.sombra.desfoque, s.cfg.atalhos.sombra.opacidade, s.cfg.atalhos.sombra.distancia, s.cfg.atalhos.sombra.cor],
    [mo.atalhos.sombra.desfoque, mo.atalhos.sombra.opacidade, mo.atalhos.sombra.distancia, mo.atalhos.sombra.cor]);
  igual('o que é do salão ficou igual (funcionamento, pagamentos, sobre, foto de fundo, slide, véu, preço na capa)',
    ordenado(Object.fromEntries(Object.keys(DO_SALAO).map(k => [k, s.cfg[k]]))), ordenado(DO_SALAO));
  igual('a logo e a capa são as mesmas', [s.logo === LOGO, s.capa === CAPA], [true, true]);
  const svs = await dona.lista('servicos', { salaoId: SALAO });
  igual('e os serviços também', svs.map(x => x.nome).sort(), ['Corte feminino', 'Hidratação']);
  const t = await p.evaluate(() => document.getElementById('modeloBarra').textContent.replace(/\s+/g, ' ').trim());
  verdade('a barra confirma que foi salvo', /Pronto/.test(t) && t.includes('Rosé Champagne') && !/Nada foi salvo/.test(t), t);
  await p.waitForTimeout(3800);
  const depois = await p.evaluate(() => ({ barra: getComputedStyle(document.getElementById('modeloBarra')).display,
    on: document.querySelectorAll('.modelo.on').length }));
  igual('e depois sai sozinha, sem modelo marcado', [depois.barra, depois.on], ['none', 0]);
  /* Salvo, o Voltar não tem mais para onde voltar: experimentar outro e
     voltar dá no modelo salvo, e não no de antes dele. */
  const salvo = await p.evaluate(() => JSON.stringify(aparencia));
  await experimentar(p, 'oceano');
  await p.getByText('Voltar ao que eu tinha').click();
  await p.waitForTimeout(200);
  igual('depois de usar, o "Voltar" volta ao que foi salvo',
    JSON.parse(await p.evaluate(() => JSON.stringify(aparencia))), JSON.parse(salvo));

  /* O "Salvar aparência" do pé da tela também aceita o modelo. */
  await experimentar(p, 'algodao');
  await p.getByText('Salvar aparência').click();
  await p.waitForTimeout(1800);
  const b = await p.evaluate(() => ({ barra: getComputedStyle(document.getElementById('modeloBarra')).display,
    on: document.querySelectorAll('.modelo.on').length }));
  igual('o Salvar do pé grava o modelo da prévia', doBanco((await salao()).cfg),
    esperadoNoBanco(MODELOS.find(x => x.id === 'algodao')));
  igual('e a barra do "nada foi salvo" sai na hora', [b.barra, b.on], ['none', 0]);

  /* Trocar de estabelecimento relê a aparência: o modelo da prévia e o
     "Voltar" de um salão não podem passar para o outro. */
  await experimentar(p, 'lavanda');
  const r = await p.evaluate(() => { aparencia = null; pintarAparencia();
    return { antes: modeloAntes, atual: modeloAtual,
      barra: getComputedStyle(document.getElementById('modeloBarra')).display }; });
  igual('reler a aparência esquece o modelo experimentado', r, { antes: null, atual: null, barra: 'none' });
}
await fechar();

/* ══════════════════════════════════════════════════════════════════════════
   6 — NA PÁGINA DA CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('6. Cada modelo chega na página da cliente');
{
  const { p: q, fechar: fecharPainel } = await painel();
  for(const mo of MODELOS){
    await experimentar(q, mo.id);
    await q.getByText('Usar este modelo').click();
    await q.waitForTimeout(1200);
    const ctx = await nav.newContext({ viewport:{ width:412, height:1800 }, isMobile:true });
    const c = await ctx.newPage();
    c.on('pageerror', e => erros.push('página: ' + e.message));
    await c.goto(BASE + '/agendar.html?salao=' + SLUG);
    await c.waitForFunction(() => document.querySelector('.boas-cta'), null, { timeout: 15000 });
    await c.waitForTimeout(500);
    const r = await c.evaluate(() => {
      const raiz = document.documentElement, est = getComputedStyle(raiz);
      const v = n => est.getPropertyValue(n).trim().toUpperCase();
      const hex = x => { const m = /rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)/.exec(x);
        return m ? '#' + [m[1], m[2], m[3]].map(n => Number(n).toString(16).padStart(2, '0')).join('').toUpperCase() : x; };
      return {
        // Sem o atributo é o padrão: a página só marca o que foge dele.
        modo: raiz.getAttribute('data-modo'), logo: raiz.getAttribute('data-logo') || 'circular',
        capa: raiz.getAttribute('data-capa') || 'curva', atalhos: raiz.getAttribute('data-atalhos') || 'borda',
        moldura: raiz.getAttribute('data-moldura') || 'reta',
        acao: v('--acao'), txt: v('--txt'), txt3: v('--txt3'), ico: v('--ico'),
        icoDestaque: v('--ico-destaque'), selo: v('--selo-cor'), bg: v('--bg'),
        prod: v('--prod-cor'),
        gradiente: document.body.classList.contains('tem-gradiente'),
        titulo: hex(getComputedStyle(document.querySelector('.marca-salao h2')).color),
        letraBotao: hex(getComputedStyle(document.querySelector('.boas-cta')).color),
      };
    });
    await ctx.close();
    const k = mo.cores;
    const falta = [];
    const conf = (rot, a, b) => { if(String(a).toUpperCase() !== String(b).toUpperCase()) falta.push(`${rot} ${a}≠${b}`); };
    conf('modo', r.modo, mo.modo); conf('logo', r.logo, mo.logoForma); conf('capa', r.capa, mo.capaForma);
    conf('atalhos', r.atalhos, mo.atalhos.estilo); conf('moldura', r.moldura, mo.moldura);
    conf('botão', r.acao, k.botao); conf('títulos', r.txt, k.titulo); conf('discreto', r.txt3, k.discreto);
    conf('ícones', r.ico, k.icone); conf('ícone de destaque', r.icoDestaque, k.iconeDestaque);
    conf('moldura do logo', r.selo, k.moldura); conf('cor do nome', r.titulo, k.titulo);
    if(k.produtos) conf('produtos', r.prod, k.produtos);
    if(mo.fundoTipo === 'gradiente') { if(!r.gradiente) falta.push('sem gradiente'); }
    else conf('papel', r.bg, k.papel);
    const letra = contraste(r.acao, r.letraBotao);
    if(letra < 4.5) falta.push('letra do botão ' + letra.toFixed(2) + ':1');
    igual(`${mo.nome}: tudo o que o modelo escolheu, na página (letra do botão ${letra.toFixed(1)}:1)`, falta, []);
  }
  await fecharPainel();
}

igual('\nnenhum erro de JavaScript no painel nem na página', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
