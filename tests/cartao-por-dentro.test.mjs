/* ===========================================================================
   AgendaPro — a cor de dentro dos cartões de serviço e de produto

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/cartao-por-dentro.test.mjs

   ── O RELATO ───────────────────────────────────────────────────────────────
   "Não estou achando a cor da moldura curvada para mudar a cor de dentro da
   moldura curvada." O fundo do cartão de serviço era a cor dos Cartões, lá
   no bloco de cores — que muda também os atalhos e outras caixas da página.
   Agora há "Cor de dentro dos serviços" e "dos produtos" logo abaixo de
   "Moldura dos serviços"; sem escolha, continua a dos Cartões.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. As duas linhas moram logo abaixo da moldura, herdando os Cartões.
     2. Sem escolha, nada muda no link nem na prévia.
     3. A cor escolhida pinta o cartão de serviço na prévia (na hora) e no
        link — na Curvada e na Clássica —, e só ele: atalhos, Bem-vindo e
        "Entrar na minha conta" continuam na cor dos Cartões.
     4. A dos produtos pinta os cartões de produto, e só eles.
     5. Tocar num serviço da prévia acende a cor de dentro.
     6. Cor torta vinda do banco é ignorada.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

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
const secao = t => console.log('\n' + t);

function novaAba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(path.join(RAIZ,'dados.js'),'utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}
const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const dona = novaAba();
await dona.criarConta({ email:`cd-${marca}@teste.com`, senha:'minhasenhaboa', nome:'Rita Alves',
  telefone:'+5511' + (100000000 + Math.floor(Math.random() * 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Navalha Barbearia ' + marca, p_tipo:'barbearia',
  p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
for(const [nome, descricao] of [['Corte masculino', 'Tesoura e máquina.'], ['Barba', 'Toalha quente e navalha.']])
  await dona.inserir('servicos', { salaoId: SALAO, nome, descricao, duracaoMin:30, intervaloMin:0,
    preco:45, ativo:true, aceitaOnline:true });
await dona.inserir('produtos', { salaoId: SALAO, nome:'Pomada modeladora', preco:39.9, ativo:true,
  vendaOnline:true, precoVisivel:true, estoque:10 });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const BASE_CFG = { cor:'#1F2937', tema:'claro', funcionamento: SEMANA, pagamentos:{ formas:['pix'] } };
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, extra) });
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
const HEX = c => { const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(c || '');
  return m ? '#' + [m[1], m[2], m[3]].map(n => Number(n).toString(16).padStart(2, '0')).join('').toUpperCase() : c; };
const DENTRO = '#FDF2D0', DENTRO_PR = '#E0F2FE';

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
  await p.waitForFunction(() => typeof irPara === 'function' && typeof bd !== 'undefined' && bd
    && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(400);
  await p.evaluate(() => { trocarAbaSalao('aparencia'); const d = document.getElementById('apAvancado'); if(d) d.open = true; });
  await p.waitForTimeout(700);
  return { p, fechar: () => ctx.close() };
}
async function link(){
  const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelectorAll('.sv-cartao').length >= 2, null, { timeout: 15000 });
  await p.waitForTimeout(600);
  return { p, fechar: () => ctx.close() };
}
const noLink = p => p.evaluate(() => {
  const bg = s => [...document.querySelectorAll(s)].map(e => getComputedStyle(e).backgroundColor);
  return { servicos: bg('.sv-cartao'), produtos: bg('.pr-cartao'), atalhos: bg('#capaInfo .recurso'),
           conta: bg('.cartao, .opcao').slice(0, 1) }; });
const naPrevia = p => p.evaluate(() => {
  const bg = s => [...document.querySelectorAll(s)].map(e => getComputedStyle(e).backgroundColor);
  return { servicos: bg('#previaFone .fone-svs[data-cfg="servicos"] .fone-cartao:not(.fone-pr)'),
           classica: bg('#previaFone .fone-svs:has(> [data-cfg="tituloServicos"]) .fone-sv'),
           produtos: bg('#previaFone .fone-pr'), atalhos: bg('#previaFone .fone-recurso') }; });
const todos = (lista, cor) => lista.length > 0 && lista.every(c => HEX(c) === cor);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 e 2. As linhas, logo abaixo da moldura; sem escolha nada muda');
await porCfg({ moldura:'elegante' });
let antes;
{
  const { p, fechar } = await link();
  antes = await noLink(p);
  igual('no link, os cartões de serviço e de produto na cor dos Cartões (branco)',
    [todos(antes.servicos, '#FFFFFF'), todos(antes.produtos, '#FFFFFF')], [true, true]);
  await fechar();
}
{
  const { p, fechar } = await painel();
  const l = await p.evaluate(() => {
    const g = document.getElementById('coresMolduraCartoes');
    const anterior = g && g.previousElementSibling;
    return { logoAbaixo: !!anterior && anterior.id === 'explicaMoldura',
      linhas: g ? [...g.querySelectorAll('.cor-linha')].map(x => [x.dataset.chave,
        x.querySelector('.cor-linha-ajuda').textContent, x.querySelector('button').style.display]) : [] }; });
  igual('"Cor de dentro dos serviços" e "dos produtos" logo abaixo da moldura, acompanhando "Cartões"', l,
    { logoAbaixo: true, linhas: [['fundoServico', 'acompanha "Cartões"', 'none'], ['fundoProduto', 'acompanha "Cartões"', 'none']] });
  const pv0 = await naPrevia(p);

  /* ════════════════════════════════════════════════════════════════════ */
  secao('3. A cor de dentro dos serviços');
  await p.evaluate(v => escolherCorSolta('fundoServico', v.toLowerCase()), DENTRO);
  await p.waitForTimeout(300);
  const pv = await naPrevia(p);
  igual('na prévia, na hora: os cartões de serviço creme; produtos e atalhos como antes',
    [todos(pv.servicos, DENTRO), pv.produtos, pv.atalhos], [true, pv0.produtos, pv0.atalhos]);

  secao('5. Tocar num serviço da prévia acende a cor de dentro');
  await p.evaluate(() => document.querySelector('#previaFone .fone-cartao:not(.fone-pr) .fone-cartao-foto').click());
  await p.waitForTimeout(400);
  igual('a linha "Cor de dentro dos serviços" acende',
    await p.evaluate(() => !!document.querySelector('.cor-linha.ap-alvo[data-chave="fundoServico"]')), true);
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  igual('salvar grava a cor', ((await cfgDe()).cores || {}).fundoServico, DENTRO.toLowerCase());
  await fechar();
}
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('no link (Curvada): os serviços creme; produtos, atalhos e o resto como antes',
    [todos(d.servicos, DENTRO), d.produtos, d.atalhos, d.conta], [true, antes.produtos, antes.atalhos, antes.conta]);
  await fechar();
}
await porCfg({ moldura:'reta', cores:{ fundoServico: DENTRO } });
{
  const { p, fechar } = await link();
  igual('na Clássica também', todos((await noLink(p)).servicos, DENTRO), true);
  await fechar();
  const pn = await painel();
  igual('e a prévia da Clássica mostra a cor nas linhas dos serviços', todos((await naPrevia(pn.p)).classica, DENTRO), true);
  await pn.fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. A cor de dentro dos produtos');
await porCfg({ moldura:'elegante', cores:{ fundoProduto: DENTRO_PR } });
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('no link: os produtos azul-claro, os serviços como antes',
    [todos(d.produtos, DENTRO_PR), d.servicos], [true, antes.servicos]);
  await fechar();
  const pn = await painel();
  const pv = await naPrevia(pn.p);
  igual('e na prévia', [todos(pv.produtos, DENTRO_PR), todos(pv.servicos, '#FFFFFF')], [true, true]);
  await pn.fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Cor torta vinda do banco');
await porCfg({ moldura:'elegante', cores:{ fundoServico:'url(x)', fundoProduto:'red' } });
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('é ignorada: os cartões de sempre, sem classe nova',
    [d.servicos, d.produtos, await p.evaluate(() => ['tem-fundo-servico', 'tem-fundo-produto'].filter(c => document.body.classList.contains(c)))],
    [antes.servicos, antes.produtos, []]);
  await fechar();
}

secao('Erros de JavaScript');
igual('nenhum, no painel e no link', erros, []);
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam.`);
process.exit(falhou ? 1 : 0);
