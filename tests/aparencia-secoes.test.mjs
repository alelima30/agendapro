/* ===========================================================================
   AgendaPro — a tela de Aparência do link em seções, e cada cor no seu lugar

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/aparencia-secoes.test.mjs

   O pedido: "BORDAS → quero mudar a borda. TEXTOS → quero mudar as letras.
   ÍCONES → quero mudar os ícones. GRADIENTES → quero configurar o
   gradiente." E: "Se eu alterar a cor da borda para vermelho, não quero que
   os ícones fiquem vermelhos."

   Antes de separar, a página foi pintada uma vez com cada cor e medido o que
   mudou. Quatro vazamentos, e só eles foram separados:
     · Textos mudava o pino do endereço (o ícone herdava a letra ao lado);
     · Destaque e preço mudava os ícones dos atalhos e o fundo do Horários;
     · Ícones passava por cima da cor escolhida para cada atalho;
     · Ícones pintava o calendário de dentro do "Agendar horário".
   O que controla mais de uma coisa DE PROPÓSITO ficou como estava (o texto
   deriva o secundário; o papel fecha o Bem-vindo; o cartão tinge o ABERTO).

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a tela: as seções, cada cor numa só, e HEX em todo quadrado;
     2. o campo HEX: escreve pela mesma função do quadrado, e a prévia muda;
     3. sem escolha nenhuma, a página é a de antes;
     4. cada cor muda só o que é dela, na página;
     5. o que já estava salvo continua salvo e no lugar;
     6. o gradiente continua funcionando, e diz onde está aplicado.
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

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`as-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino', duracaoMin:30, intervaloMin:0,
  preco:90, ativo:true, aceitaOnline:true, categoria:'Cabelo', foto: arte('#7C3AED', '#C084FC') });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
/* A moldura curvada põe o relógio ao lado da duração — é um dos ícones de
   traço soltos na página, e precisa estar na tela para ser medido. */
const BASE_CFG = { diasLiberados:30, cor:'#1D4ED8', precoNaCapa:true, moldura:'elegante',
  funcionamento: SEMANA, pagamentos:{ formas:['pix'] }, sobre:'Salão de beleza' };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  logo: arte('#4C1D95', '#A78BFA'), capa: arte('#2E1065', '#7C3AED') });
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
  const ctx = await nav.newContext({ viewport:{ width:412, height:2200 }, isMobile:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('#capaInfo .recurso svg')
    && document.querySelector('.sv-cartao-relogio svg') && document.querySelector('.boas-cta svg'),
    null, { timeout: 15000 });
  await p.waitForTimeout(400);
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

/* O que cada categoria pinta na capa. Ícones são medidos no <svg>, que é o
   que o olho vê — não no <span> que o embrulha. */
const SONDAS = {
  pino:          ['.marca-end .rua svg', 'color'],
  relogio:       ['.sv-cartao-relogio svg', 'color'],
  iconeAtalho:   ['#capaInfo .recurso:not(.destaque) svg', 'color'],
  iconeHorarios: ['#capaInfo .recurso.destaque svg', 'color'],
  iconeBotao:    ['.boas-cta svg', 'color'],
  setaStatus:    ['.status-seta svg', 'color'],
  letraRua:      ['.marca-end .rua', 'color'],
  letraHorarios: ['#capaInfo .recurso.destaque .recurso-rot', 'color'],
  fundoHorarios: ['#capaInfo .recurso.destaque', 'backgroundColor'],
  bordaHorarios: ['#capaInfo .recurso.destaque', 'borderTopColor'],
  titulo:        ['.marca-salao h2', 'color'],
  preco:         ['.sv-cartao-preco', 'color'],
  bemVindo:      ['.boas-oi', 'color'],
  duracao:       ['.sv-cartao-dur', 'color'],
  // A escolha de quem atende: com a moldura curvada o cartão de serviço
  // não tem borda, e medir ali seria medir nada.
  bordaCartao:   ['#capaEquipe .opcao', 'borderTopColor'],
  bordaAtalho:   ['#capaInfo .recurso:not(.destaque)', 'borderTopColor'],
  letraBotao:    ['.boas-cta', 'color'],
};
const medir = p => p.evaluate(([h, S]) => { const hex = eval(h);
  return Object.fromEntries(Object.entries(S).map(([k, [sel, prop]]) => {
    const e = document.querySelector(sel);
    return [k, e ? hex(getComputedStyle(e)[prop]) : '(não achou ' + sel + ')'];
  }));
}, [HEX, SONDAS]);

/* ══════════════════════════════════════════════════════════════════════════
   1 — A TELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. A tela em seções, cada cor numa só');
const ESPERADO = { apFundo:['papel', 'card', 'secundaria'], apTextos:['titulo', 'texto', 'discreto', 'destaque'],
  apIcones:['icone', 'iconeDestaque'], apBordas:['borda', 'moldura'], apBotoes:['botao', 'produtos'] };
{
  const { p, fechar } = await painel();
  const t = await p.evaluate(() => ({
    secoes: [...document.querySelectorAll('.ap-controles .ap-sec')].map(s => s.id),
    // Sem o emoji da frente: tudo o que não é letra, até a primeira letra.
    titulos: [...document.querySelectorAll('.ap-sec-t')].map(h => h.textContent.trim().replace(/^[^\p{L}]+/u, '')),
    indice: [...document.querySelectorAll('.ap-indice button')].map(b => b.textContent.trim().replace(/^[^\p{L}]+/u, '')),
    chaves: Object.fromEntries([...document.querySelectorAll('.ap-sec')].map(s =>
      [s.id, [...s.querySelectorAll('.cor-linha[data-chave]')].map(x => x.dataset.chave)])),
    quadrados: document.querySelectorAll('.ap-controles input[type="color"]').length,
    comHex: [...document.querySelectorAll('.ap-controles input[type="color"]')].filter(c => c._hex && c._hex.isConnected).length,
    hexIgual: [...document.querySelectorAll('.ap-controles input[type="color"]')]
      .every(c => c._hex.value === c.value.toUpperCase()),
    // Os controles que já existiam, cada um na seção certa.
    onde: Object.fromEntries(['reguaModo', 'paletaCores', 'temasProntos', 'reguaFundoTipo', 'fxVeu',
      'reguaTema', 'reguaLetra', 'reguaLogoBorda', 'reguaMoldura', 'gradA', 'gradB', 'reguaBrilho',
      'reguaFitaMetal', 'fitaCor', 'reguaAtalhos', 'atCor', 'fxFoco', 'reguaCapaForma', 'reguaLogoForma',
      'reguaSlideForma', 'reguaSlide', 'reguaPreco']
      .map(id => [id, (document.getElementById(id) || {}).closest?.('.ap-sec')?.id || '(sumiu)'])),
  }));
  igual('as oito seções, na ordem', t.secoes,
    ['apMarca', 'apFundo', 'apTextos', 'apIcones', 'apBordas', 'apGradientes', 'apBotoes', 'apCapa']);
  igual('com os nomes do pedido', t.titulos,
    ['Marca', 'Fundo', 'Textos', 'Ícones', 'Bordas', 'Gradientes', 'Botões e atalhos', 'Capa e fotos']);
  igual('e o índice do topo leva a cada uma', t.indice, t.titulos);
  for(const [sec, chaves] of Object.entries(ESPERADO))
    igual(`${sec}: só as cores dela`, t.chaves[sec], chaves);
  igual('Marca, Gradientes e Capa não têm cor solta misturada', [t.chaves.apMarca, t.chaves.apGradientes, t.chaves.apCapa], [[], [], []]);
  verdade('todo quadrado de cor da tela tem o campo HEX, com o código dele',
    t.quadrados >= 20 && t.comHex === t.quadrados && t.hexIgual, JSON.stringify([t.quadrados, t.comHex, t.hexIgual]));
  igual('nada sumiu: cada controle de antes, na seção dele', t.onde, {
    reguaModo:'apMarca', paletaCores:'apMarca', temasProntos:'apMarca', reguaFundoTipo:'apFundo', fxVeu:'apFundo',
    reguaTema:'apTextos', reguaLetra:'apTextos', reguaLogoBorda:'apBordas', reguaMoldura:'apBordas',
    gradA:'apGradientes', gradB:'apGradientes', reguaBrilho:'apGradientes', reguaFitaMetal:'apGradientes',
    fitaCor:'apGradientes', reguaAtalhos:'apBotoes', atCor:'apBotoes', fxFoco:'apCapa', reguaCapaForma:'apCapa',
    reguaLogoForma:'apCapa', reguaSlideForma:'apCapa', reguaSlide:'apCapa', reguaPreco:'apCapa' });
  await p.locator('.ap-indice button', { hasText: 'Bordas' }).click();
  await p.waitForTimeout(900);
  const topo = await p.evaluate(() => Math.round(document.getElementById('apBordas').getBoundingClientRect().top));
  verdade('tocar em "Bordas" no índice leva à seção', topo >= 0 && topo < 160, 'topo em ' + topo);

  /* ══════════════════════════════════════════════════════════════════════
     2 — O CAMPO HEX
     ══════════════════════════════════════════════════════════════════════ */
  secao('2. O campo HEX: mesma função do quadrado, prévia na hora');
  const digitar = async (sel, txt) => {
    const hex = await p.evaluateHandle(s => document.querySelector(s)._hex, sel);
    await hex.asElement().fill('');
    await hex.asElement().type(txt);
    await p.waitForTimeout(200);
  };
  // O campo guarda o que foi digitado enquanto tem o foco (minúsculas
  // inclusive); ao sair, ele passa ao código do quadrado, em maiúsculas.
  const lerQ = s => p.evaluate(s => {
    const c = document.querySelector(s); return { quadrado: c.value.toUpperCase(), hex: c._hex.value.toUpperCase(), torto: c._hex.classList.contains('torto') };
  }, s);
  const prev = () => p.evaluate(h => { const hex = eval(h), q = s => document.querySelector('#previaFone ' + s);
    return { borda: hex(getComputedStyle(q('.fone-recurso:not(.destaque)')).borderTopColor),
             titulo: hex(getComputedStyle(q('.fone-topo b')).color),
             pino: hex(getComputedStyle(q('.fone-pino svg, .fone-pino')).color),
             iconeAtalho: hex(getComputedStyle(q('.fone-recurso:not(.destaque) svg, .fone-recurso:not(.destaque) [data-ico]')).color),
             bemVindo: hex(getComputedStyle(q('.fone-boas-t')).color) }; }, HEX);
  const L = k => `.cor-linha[data-chave="${k}"] input[type="color"]`;
  await digitar(L('borda'), '#e11d48');
  igual('HEX na borda: o quadrado acompanha', await lerQ(L('borda')), { quadrado:'#E11D48', hex:'#E11D48', torto:false });
  igual('e a cor vira escolha, pelo mesmo caminho do quadrado',
    await p.evaluate(() => aparencia.cores.borda), '#e11d48');
  let pv = await prev();
  igual('a prévia pinta a borda na hora, antes de salvar', pv.borda, '#E11D48');
  await digitar(L('titulo'), 'f0a');
  igual('código curto e sem # também vale (f0a → #FF00AA)', (await lerQ(L('titulo'))).quadrado, '#FF00AA');
  igual('e a prévia mostra o título nele', (await prev()).titulo, '#FF00AA');
  await digitar(L('icone'), '#0ea5e9');
  await digitar(L('iconeDestaque'), '#16a34a');
  await digitar(L('destaque'), '#b45309');
  pv = await prev();
  igual('ícones, ícones de destaque e texto de destaque, cada um no seu lugar da prévia',
    [pv.pino, pv.iconeAtalho, pv.bemVindo], ['#0EA5E9', '#16A34A', '#B45309']);
  igual('e a borda da prévia não foi junto com nenhum deles', pv.borda, '#E11D48');
  await digitar(L('texto'), '#12zz');
  const torto = await lerQ(L('texto'));
  verdade('código torto fica vermelho e não muda a cor', torto.torto && torto.quadrado !== '#12ZZ', JSON.stringify(torto));
  await p.evaluate(s => document.querySelector(s)._hex.blur(), L('texto'));
  await p.waitForTimeout(150);
  const volta = await lerQ(L('texto'));
  igual('ao sair do campo, ele volta ao código do quadrado', [volta.hex === volta.quadrado, volta.torto], [true, false]);
  const mesmo = await p.evaluate(s => { const c = document.querySelector(s); const h = c._hex;
    h.value = '#123456'; h.dispatchEvent(new Event('input', { bubbles:true }));
    return c.isConnected && h.isConnected && document.querySelector(s) === c && c._hex === h; }, L('card'));
  verdade('digitar não refaz a linha: quadrado e campo são os mesmos', mesmo);
  await digitar('#corLivre', '#be185d');
  igual('HEX na cor da marca', await p.evaluate(() => aparencia.cor.toLowerCase()), '#be185d');
  await p.evaluate(() => { const b = [...document.querySelectorAll('#coresBordas .cor-linha[data-chave="borda"] button')][0]; b.click(); });
  await p.waitForTimeout(200);
  const herdou = await lerQ(L('borda'));
  verdade('"herdar" devolve a borda ao automático, e o HEX mostra a cor de volta',
    await p.evaluate(() => !('borda' in aparencia.cores)) && herdou.hex === herdou.quadrado && herdou.hex !== '#E11D48',
    JSON.stringify(herdou));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — SEM ESCOLHA, A PÁGINA DE ANTES
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. Quem nunca escolheu vê a página de antes');
await porCfg({});
let antes;
{
  const { p, fechar } = await pagina();
  antes = await medir(p);
  const v = await p.evaluate(() => { const r = getComputedStyle(document.documentElement);
    return [r.getPropertyValue('--ac-marca').trim().toUpperCase(), r.getPropertyValue('--ac-600').trim().toUpperCase()]; });
  igual('sem destaque escolhido, a cor da marca dos ícones é a mesma do --ac-600', v[0], v[1]);
  /* O que era herança continua dando a mesma cor: o pino era a letra da rua,
     o relógio a da duração, o ícone do atalho a do Horários. */
  igual('o pino na cor da rua, como antes', antes.pino, antes.letraRua);
  igual('o relógio na cor da duração, como antes', antes.relogio, antes.duracao);
  igual('o ícone do atalho na cor da marca, como o nome do Horários', antes.iconeAtalho, antes.letraHorarios);
  igual('o calendário do botão na letra do botão', antes.iconeBotao, antes.letraBotao);
  await fechar();
}
/* O quadrado de quem não escolheu mostra a cor que ESTÁ na página. Ele
   mostrava a cor da marca na moldura do logo (a página usa a do cartão) e
   no texto de destaque (a página usa a marca puxada para ler bem). */
{
  const pg = await pagina();
  const naPagina = await pg.p.evaluate(h => { const hex = eval(h);
    const anel = /^(rgba?\([^)]*\))/.exec(getComputedStyle(document.querySelector('.marca-selo')).boxShadow) || [];
    return { anel: hex(anel[1]) }; }, HEX);
  await pg.fechar();
  const { p, fechar } = await painel();
  const q = await p.evaluate(() => Object.fromEntries(['icone', 'iconeDestaque', 'destaque', 'moldura', 'texto', 'borda']
    .map(k => [k, document.querySelector(`.cor-linha[data-chave="${k}"] input[type="color"]`).value.toUpperCase()])));
  igual('sem escolha, cada quadrado mostra a cor que está na página',
    q, { icone: antes.pino, iconeDestaque: antes.iconeAtalho, destaque: antes.preco,
         moldura: naPagina.anel, texto: antes.letraRua, borda: antes.bordaAtalho });
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — CADA COR MUDA SÓ O QUE É DELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. Cada cor muda só o que é dela');
const COR = '#FF00AA', COR_H = '#FF00AA';
/* [o que vai para a cor escolhida, o que muda junto DE PROPÓSITO]. O texto
   principal deriva o secundário quando ninguém escolheu o secundário — é da
   mesma família (textos), está documentado no aplicarCoresSoltas, e foi
   mantido: "se alguma configuração foi criada para controlar mais de um
   elemento, analise antes de separar". O relógio (ícone) não vai junto. */
const CASOS = {
  texto:         [['letraRua'], ['duracao']],
  discreto:      [['duracao'], []],
  titulo:        [['titulo'], []],
  destaque:      [['preco', 'bemVindo'], []],
  icone:         [['pino', 'relogio'], []],
  iconeDestaque: [['iconeAtalho', 'iconeHorarios'], []],
  borda:         [['bordaCartao', 'bordaAtalho'], []],
};
for(const [chave, [deve, junto]] of Object.entries(CASOS)){
  await porCfg({ cores:{ [chave]: COR } });
  const { p, fechar } = await pagina();
  const d = await medir(p);
  await fechar();
  const mudou = Object.keys(SONDAS).filter(k => d[k] !== antes[k]);
  igual(`${chave}: muda ${deve.join(' e ')}${junto.length ? ' (e ' + junto.join(', ') + ', de propósito)' : ''} — e mais nada da lista`,
    mudou.sort(), [...deve, ...junto].sort());
  verdade(`${chave}: e muda para a cor escolhida`, deve.every(k => d[k].startsWith(COR_H)),
    JSON.stringify(Object.fromEntries(deve.map(k => [k, d[k]]))));
}
/* A cor própria de cada atalho ganha dos ícones gerais, e os ícones de
   dentro dos botões e do status seguem os donos deles. */
await porCfg({ cores:{ icone:'#0EA5E9', iconeDestaque:'#16A34A' },
  atalhos:{ estilo:'borda', cores:{ pagamentos:'#DC2626' } } });
{
  const { p, fechar } = await pagina();
  const d = await medir(p);
  igual('a cor própria do atalho ganha de "Cor dos ícones" e de "Ícones de destaque"', d.iconeAtalho, '#DC2626');
  igual('o Horários, sem cor própria, fica nos ícones de destaque', d.iconeHorarios, '#16A34A');
  igual('o calendário do "Agendar horário" continua na letra do botão', d.iconeBotao, antes.iconeBotao);
  igual('e a seta do ABERTO continua verde', d.setaStatus, antes.setaStatus);
  /* A janela do Horários: os ícones dela também são de destaque. */
  await p.locator('#capaInfo .recurso.destaque').click();
  await p.waitForSelector('.folha-ic svg', { timeout: 5000 });
  await p.waitForTimeout(400);
  const f = await p.evaluate(h => eval(h)(getComputedStyle(document.querySelector('.folha-ic svg')).color), HEX);
  igual('e o ícone da janela que o Horários abre também', f, '#16A34A');
  await fechar();
}
await porCfg({ cores:{ destaque:'#B45309' } });
{
  const { p, fechar } = await pagina();
  await p.locator('#capaInfo .recurso.destaque').click();
  await p.waitForSelector('.folha-ic svg', { timeout: 5000 });
  await p.waitForTimeout(400);
  const f = await p.evaluate(h => eval(h)(getComputedStyle(document.querySelector('.folha-ic svg')).color), HEX);
  verdade('o texto de destaque não pinta o ícone da janela', f !== '#B45309', f);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — O QUE JÁ ESTAVA SALVO
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. O que já estava salvo continua salvo, e no lugar certo');
const VELHAS = { papel:'#FDF2F8', secundaria:'#FCE7F3', botao:'#9D174D', texto:'#4A044E', discreto:'#86198F',
  titulo:'#500724', card:'#FFFFFF', icone:'#BE185D', destaque:'#A21CAF', borda:'#F5D0FE', moldura:'#F0ABFC' };
await porCfg({ tema:'claro', fundoTipo:'solida', cores: VELHAS, gradiente:'#111111,#222222' });
{
  const { p, fechar } = await painel();
  const nosQuadrados = await p.evaluate(ks => Object.fromEntries(ks.map(k =>
    [k, document.querySelector(`.cor-linha[data-chave="${k}"] input[type="color"]`).value.toUpperCase()])), Object.keys(VELHAS));
  igual('cada cor salva antes aparece no quadrado dela', nosQuadrados, VELHAS);
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  const cfg = await cfgDe();
  igual('salvar sem mexer não perde nem inventa cor', Object.entries(cfg.cores).map(([k, v]) => [k, v.toUpperCase()]).sort(),
    Object.entries(VELHAS).sort());
  igual('e o gradiente guardado continua guardado', cfg.gradiente, '#111111,#222222');
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   6 — O GRADIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('6. O gradiente continua funcionando, e diz onde está aplicado');
await porCfg({ tema:'claro', fundoTipo:'solida' });
{
  const { p, fechar } = await painel();
  let g = await p.evaluate(() => ({ txt: document.getElementById('gradAplicado').textContent,
    usar: getComputedStyle(document.getElementById('gradUsar')).display }));
  verdade('com cor sólida, Gradientes diz que não está em uso e oferece usar',
    /Não está em uso/.test(g.txt) && g.usar !== 'none', JSON.stringify(g));
  await p.locator('#gradUsar').click();
  await p.waitForTimeout(300);
  g = await p.evaluate(() => ({ txt: document.getElementById('gradAplicado').textContent,
    usar: getComputedStyle(document.getElementById('gradUsar')).display, tipo: aparencia.fundoTipo,
    campos: getComputedStyle(document.getElementById('gradienteCampos')).display,
    fundoRegua: [...document.querySelectorAll('#reguaFundoTipo button.on')].map(b => b.textContent.trim()) }));
  verdade('"Usar" liga o gradiente no fundo — a mesma escolha da régua do Fundo, e não uma segunda',
    g.tipo === 'gradiente' && /fundo da página/.test(g.txt) && g.usar === 'none' && g.campos !== 'none'
      && g.fundoRegua[0] === 'Gradiente', JSON.stringify(g));
  const a = await p.evaluateHandle(() => document.getElementById('gradA')._hex);
  await a.asElement().fill(''); await a.asElement().type('#0f172a');
  const b = await p.evaluateHandle(() => document.getElementById('gradB')._hex);
  await b.asElement().fill(''); await b.asElement().type('#7c3aed');
  await p.waitForTimeout(300);
  const fone = await p.evaluate(() => getComputedStyle(document.querySelector('#previaFone .fone')).backgroundImage);
  verdade('as cores inicial e final pelo HEX chegam na prévia', /15, 23, 42/.test(fone) && /124, 58, 237/.test(fone), fone);
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  igual('e são gravadas', [(await cfgDe()).fundoTipo, (await cfgDe()).gradiente], ['gradiente', '#0f172a,#7c3aed']);
  await fechar();
}

secao('Erros de JavaScript');
igual('nenhum, no painel e na página', erros, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
