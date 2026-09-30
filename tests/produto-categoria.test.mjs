/* ===========================================================================
   AgendaPro — categoria de produto: a etiqueta no painel, o filtro no link

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/produto-categoria.test.mjs

   O pedido: "Em produtos, colocar categorias — tipo 'tratamento de cabelo' —
   e ter essa etiqueta. E pro cliente, ele consegue filtrar clicando em cima
   da categoria, que vai filtrar todos que estão vinculados. Para o cliente,
   em produtos, embaixo de buscar produto, aparecer as categorias."

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. o painel: a etiqueta embaixo do nome de cada produto com categoria;
     2. o cadastro: o campo Categoria, com as que já existem sugeridas, e a
        gravação (e o apagar, que volta a "sem categoria");
     3. o link: as categorias logo abaixo de "Buscar produto…", com "Todos";
     4. tocar numa filtra; tocar de novo, ou em "Todos", volta tudo;
     5. "Tratamento de cabelo" e " tratamento de CABELO " são a mesma;
     6. a busca e a categoria valem juntas;
     7. sem categoria nenhuma, a fileira não aparece;
     8. a categoria escolhida na cor do tema; a 360px a fileira rola por
        dentro, sem a página rolar de lado; o nome é escapado.
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
await dona.criarConta({ email:`pc-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Hidratação', duracaoMin:60, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const novo = (nome, categoria) => dona.inserir('produtos', { salaoId: SALAO, nome, categoria, preco:45,
  custo:10, estoque:5, comissaoPct:0, ativo:true, vendaOnline:true });
const cond = await novo('Condicionador', 'Tratamento de cabelo');
await novo('Máscara de hidratação', 'Tratamento de cabelo');
await novo('Óleo reparador', ' tratamento de  CABELO ');
await novo('Perfume ok', 'Perfumaria');
const shampoo = await novo('Shampoo', null);
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777',
  cfg:{ diasLiberados:30, cor:'#B8356B', cores:{ botao:'#8E2457' } } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 e 2. No painel: a etiqueta e o cadastro');
{
  const ctx = await nav.newContext({ viewport:{ width:390, height:900 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => { erros.push('ALERT: ' + d.message()); d.dismiss(); });
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function'
    && typeof bd !== 'undefined' && bd && Array.isArray(bd.produtos) && bd.produtos.length >= 5, null, { timeout: 20000 });
  await p.waitForTimeout(800);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => irPara('produtos'));
  await p.waitForTimeout(700);
  const etiquetas = () => p.evaluate(() => Object.fromEntries([...document.querySelectorAll('#listaProdutos tbody tr')]
    .map(tr => [tr.querySelector('b').textContent.trim(),
      (tr.querySelector('.tag-cat') || {}).textContent ? tr.querySelector('.tag-cat').textContent.trim() : null])));
  const e1 = await etiquetas();
  igual('cada produto com a etiqueta da sua categoria, embaixo do nome', e1, {
    'Condicionador':'Tratamento de cabelo', 'Máscara de hidratação':'Tratamento de cabelo',
    'Óleo reparador':'tratamento de CABELO', 'Perfume ok':'Perfumaria', 'Shampoo':null });
  verdade('com o ícone de etiqueta', await p.evaluate(() =>
    !!document.querySelector('#listaProdutos .tag-cat svg')));

  await p.evaluate(id => abrirProduto(id), shampoo.id);
  await p.waitForTimeout(400);
  const f = await p.evaluate(() => ({
    rotulo: document.querySelector('label[for="pCat"]') ? document.querySelector('label[for="pCat"]').textContent.trim() : null,
    valor: document.getElementById('pCat').value,
    sugestoes: [...document.querySelectorAll('#pCatLista option')].map(o => o.value),
  }));
  igual('o cadastro tem o campo Categoria, vazio para quem não tem', [f.rotulo, f.valor], ['Categoria', '']);
  igual('com as categorias que já existem sugeridas — uma vez cada', f.sugestoes, ['Perfumaria', 'Tratamento de cabelo']);
  await p.fill('#pCat', '  Cabelo   liso ');
  await p.evaluate(id => salvarProduto(id), shampoo.id);
  await p.waitForTimeout(2500);
  const noBanco = async id => ((await dona.lista('produtos', { salaoId: SALAO })).find(x => x.id === id) || {}).categoria;
  igual('salvo: a categoria vai para o banco, sem os espaços sobrando', await noBanco(shampoo.id), 'Cabelo liso');
  await p.evaluate(id => abrirProduto(id), shampoo.id);
  await p.waitForTimeout(400);
  await p.fill('#pCat', '');
  await p.evaluate(id => salvarProduto(id), shampoo.id);
  await p.waitForTimeout(2500);
  igual('apagar o campo volta a "sem categoria"', await noBanco(shampoo.id) ?? null, null);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
async function loja(largura = 390){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:900 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.evaluate(() => irPara('loja'));
  await p.waitForTimeout(500);
  return { p, fechar: () => ctx.close() };
}
const lerLoja = p => p.evaluate(() => {
  const fileira = document.getElementById('lojaCats');
  return {
    visivel: !!(fileira && fileira.offsetParent),
    logoAbaixoDaBusca: !!fileira && document.getElementById('buscaProduto').nextElementSibling === fileira,
    chips: fileira ? [...fileira.querySelectorAll('button')].map(b => b.textContent.trim()
      + (b.getAttribute('aria-pressed') === 'true' ? ' ●' : '')) : [],
    produtos: [...document.querySelectorAll('#listaProdutos .pr-cartao .loja-nome, #listaProdutos .bloco .rot')]
      .map(x => x.textContent.trim()),
  };
});

secao('3. No link: as categorias embaixo de "Buscar produto…"');
{
  const { p, fechar } = await loja();
  const t = await lerLoja(p);
  igual('a fileira aparece, logo abaixo da busca', [t.visivel, t.logoAbaixoDaBusca], [true, true]);
  igual('"Todos" marcado, e cada categoria uma vez, em ordem', t.chips,
    ['Todos ●', 'Perfumaria', 'Tratamento de cabelo']);
  igual('com todos os produtos', t.produtos.length, 5);

  secao('4 e 5. Tocar filtra — e maiúscula e espaço não separam');
  await p.click('#lojaCats button:has-text("Tratamento de cabelo")');
  await p.waitForTimeout(250);
  const t2 = await lerLoja(p);
  igual('só os de tratamento, inclusive o escrito de outro jeito', [t2.produtos.sort(), t2.chips[2]],
    [['Condicionador', 'Máscara de hidratação', 'Óleo reparador'], 'Tratamento de cabelo ●']);
  await p.click('#lojaCats button:has-text("Tratamento de cabelo")');
  await p.waitForTimeout(250);
  igual('tocar de novo desmarca, e volta tudo', [(await lerLoja(p)).produtos.length, (await lerLoja(p)).chips[0]], [5, 'Todos ●']);
  await p.click('#lojaCats button:has-text("Perfumaria")');
  await p.click('#lojaCats button:has-text("Todos")');
  await p.waitForTimeout(250);
  igual('e "Todos" também', (await lerLoja(p)).produtos.length, 5);

  secao('6. A busca e a categoria juntas');
  await p.click('#lojaCats button:has-text("Tratamento de cabelo")');
  await p.fill('#buscaProduto', 'másc');
  await p.waitForTimeout(250);
  igual('tratamento + "másc": só a máscara, e a categoria continua marcada', [(await lerLoja(p)).produtos,
    (await lerLoja(p)).chips[2]], [['Máscara de hidratação'], 'Tratamento de cabelo ●']);
  await p.fill('#buscaProduto', 'perfume');
  await p.waitForTimeout(250);
  verdade('sem nada nas duas, diz que não achou naquela categoria', await p.evaluate(() =>
    /Nenhum produto/.test(document.getElementById('listaProdutos').innerText)));

  secao('8. Na cor do tema, e sem vazar');
  await p.fill('#buscaProduto', '');
  await p.waitForTimeout(200);
  const cores = await p.evaluate(() => {
    const on = document.querySelector('#lojaCats button[aria-pressed="true"]');
    return [getComputedStyle(on).backgroundColor, getComputedStyle(on).color];
  });
  igual('a categoria escolhida na cor do botão do salão', cores, ['rgb(142, 36, 87)', 'rgb(255, 255, 255)']);
  await fechar();
}
{
  // Muitas categorias numa tela estreita: a fileira rola por dentro.
  for(const c of ['Maquiagem', 'Unhas e esmaltes', 'Corpo e banho', 'Barba'])
    await novo('Item de ' + c, c);
  const { p, fechar } = await loja(360);
  const r = await p.evaluate(() => {
    const f = document.getElementById('lojaCats');
    // Rola de verdade: com a fileira sem rolagem, o que não cabe só fica
    // cortado — o tamanho passa do limite do mesmo jeito, mas não anda.
    f.scrollLeft = 200;
    return { pagina: document.documentElement.scrollWidth - innerWidth, rola: f.scrollLeft > 0,
      alvo: Math.min(...[...f.querySelectorAll('button')].map(b => b.getBoundingClientRect().height)) };
  });
  igual('a 360px: a página não vaza, a fileira rola por dentro, e cada uma é alvo de dedo',
    [r.pagina <= 0, r.rola, r.alvo >= 40], [true, true, true]);
  await fechar();
}
{
  await dona.atualizar('produtos', cond.id, { categoria:'<b>Promo</b>' });
  const { p, fechar } = await loja();
  verdade('o nome da categoria é escapado: aparece como texto', await p.evaluate(() =>
    [...document.querySelectorAll('#lojaCats button')].some(b => b.textContent === '<b>Promo</b>')
    && !document.querySelector('#lojaCats b')));
  await fechar();
}

secao('7. Sem categoria nenhuma, a fileira não aparece');
for(const x of await dona.lista('produtos', { salaoId: SALAO }))
  await dona.atualizar('produtos', x.id, { categoria: null });
{
  const { p, fechar } = await loja();
  const t = await lerLoja(p);
  igual('só a busca e os produtos, como antes', [t.visivel, t.produtos.length > 0], [false, true]);
  await fechar();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
