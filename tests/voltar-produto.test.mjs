/* ===========================================================================
   AgendaPro — o Voltar escrito no link, e o produto aberto

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/voltar-produto.test.mjs

   Dois pedidos do dono, olhando o link no celular:
     · "tem senhor e senhora que não sabe aonde volta pra primeira tela, tem
       que ter o botão voltar" — e "nos produtos a mesma coisa". O ‹ do topo é
       pequeno e longe do polegar;
     · "quando clica sobre o produto abre a foto e um lugar explicando sobre
       o produto".

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. em cada passo do agendamento, "Voltar" escrito no pé, ao lado do
        Continuar — e ele volta um passo por vez até a capa;
     2. onde o pé não tinha botão (Para quem), o Voltar aparece sozinho, largo;
     3. na loja, o Voltar ao lado do Enviar pedido;
     4. tocar na foto ou no nome do produto abre a tela dele: foto grande,
        categoria, preço e a descrição inteira (com as quebras de linha);
        Adicionar ali soma no carrinho; o Voltar leva de volta à loja;
     5. o Adicionar do cartão continua só adicionando — não abre o produto;
     6. da capa, o destaque também abre; a 360px nada vaza; nenhum erro.
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
await dona.criarConta({ email:`vp-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:60, intervaloMin:0,
  preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const DESC = 'Condicionador da linha Tododia.\nCabelos mais macios, fortes e brilhantes.\n280 ml.';
const cond = await dona.inserir('produtos', { salaoId: SALAO, nome:'Condicionador', categoria:'Tratamento de cabelo',
  preco:45, custo:10, estoque:5, comissaoPct:0, ativo:true, vendaOnline:true, descricao: DESC, marca:'Natura' });
await dona.inserir('produtos', { salaoId: SALAO, nome:'Perfume ok', categoria:'Perfumes',
  preco:20, custo:5, estoque:5, comissaoPct:0, ativo:true, vendaOnline:true });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777',
  cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA, pularComQuem:false } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function aparelho(largura = 390){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.dismiss());
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(800);
  return { p, ctx };
}
const pe = p => p.evaluate(() => {
  const bs = document.getElementById('btSecundario'), bp = document.getElementById('btPrincipal');
  const vis = e => !!e.offsetParent && getComputedStyle(e).display !== 'none';
  return { tela, voltar: vis(bs) ? bs.textContent.trim() : null, principal: vis(bp) ? bp.textContent.trim() : null,
    lado: vis(bs) && vis(bp) ? Math.abs(bs.getBoundingClientRect().top - bp.getBoundingClientRect().top) < 3 : null,
    largo: vis(bs) ? bs.getBoundingClientRect().width > innerWidth * 0.6 : null };
});
const tocarVoltar = async p => { await p.click('#btSecundario'); await p.waitForTimeout(400); };

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 e 2. O Voltar escrito em cada passo do agendamento');
{
  const { p, ctx } = await aparelho();
  await p.click('.boas-cta'); await p.waitForTimeout(400);
  const a = await pe(p);
  igual('Serviço: "Voltar" ao lado do botão de seguir', [a.tela, a.voltar, a.lado], ['servico', 'Voltar', true]);
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(400);
  const b = await pe(p);
  igual('Para quem (sem Continuar): o Voltar aparece sozinho, largo', [b.tela, b.voltar, b.principal, b.largo],
    ['quem', 'Voltar', null, true]);
  await p.click('#quemMim'); await p.waitForTimeout(800);
  const c = await pe(p);
  igual('Com quem: Voltar ao lado do Continuar', [c.tela, c.voltar, c.lado], ['prof', 'Voltar', true]);
  await p.click('#btPrincipal'); await p.waitForTimeout(2000);
  igual('Quando: o Voltar continua lá', [(await pe(p)).tela, (await pe(p)).voltar], ['quando', 'Voltar']);
  await p.locator('#listaDias .dia:not(.sem)').nth(1).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  igual('Seu cadastro: também', [(await pe(p)).tela, (await pe(p)).voltar], ['dados', 'Voltar']);
  const caminho = [];
  for(let i = 0; i < 6 && (await p.evaluate(() => tela)) !== 'capa'; i++){ await tocarVoltar(p); caminho.push(await p.evaluate(() => tela)); }
  igual('tocando Voltar, volta um passo por vez até a capa', caminho, ['quando', 'prof', 'quem', 'servico', 'capa']);
  igual('e na capa o Voltar some (não há para onde)', (await pe(p)).voltar, null);
  igual('a 390px nada vaza para o lado', await p.evaluate(() => document.documentElement.scrollWidth - innerWidth <= 0), true);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3 a 5. A loja e o produto aberto');
{
  const { p, ctx } = await aparelho(360);
  await p.evaluate(() => irPara('loja')); await p.waitForTimeout(500);
  const l = await pe(p);
  igual('Loja: Voltar ao lado de "Escolha pelo menos 1 produto"', [l.voltar, l.lado, /produto/.test(l.principal || '')], ['Voltar', true, true]);

  // O Adicionar do cartão só adiciona.
  await p.locator('#listaProdutos .loja-add').first().click(); await p.waitForTimeout(300);
  igual('o Adicionar do cartão soma no carrinho e fica na loja', await p.evaluate(() =>
    [tela, Object.values(carrinho).reduce((s, n) => s + n, 0)]), ['loja', 1]);

  // Tocar na foto abre o produto.
  await p.evaluate(() => document.getElementById('listaProdutos').querySelectorAll('.abre-produto').length);
  const alvo = await p.evaluate(id => {
    const c = [...document.querySelectorAll('#listaProdutos .abre-produto')].find(x => /Condicionador/.test(x.textContent));
    return c ? true : false; }, cond.id);
  verdade('o cartão do Condicionador existe na loja', alvo);
  await p.locator('#listaProdutos .abre-produto', { hasText: 'Condicionador' }).first().click({ position: { x: 20, y: 20 } });
  await p.waitForTimeout(500);
  const d = await p.evaluate(() => {
    const f = document.querySelector('#produtoAberto .prod-grande');
    return { tela, nome: (document.querySelector('.prod-nome') || {}).textContent,
      cat: (document.querySelector('.prod-cat') || {}).textContent, marca: (document.querySelector('.prod-marca') || {}).textContent,
      preco: (document.querySelector('.prod-preco') || {}).textContent,
      desc: (document.querySelector('.prod-desc') || {}).innerText,
      fotoAlta: f ? Math.round(f.getBoundingClientRect().height) : 0,
      fita: (document.getElementById('carrinhoFita') || {}).style ? document.getElementById('carrinhoFita').style.display : '',
      sobra: document.documentElement.scrollWidth - innerWidth };
  });
  igual('abre a tela do produto: nome, categoria, marca e preço', [d.tela, d.nome, d.cat, d.marca, /45,00/.test(d.preco)],
    ['produto', 'Condicionador', 'Tratamento de cabelo', 'Natura', true]);
  verdade('a descrição inteira, com as quebras de linha', d.desc && d.desc.split('\n').filter(Boolean).length === 3
    && /280 ml/.test(d.desc), JSON.stringify(d.desc));
  verdade('a foto grande (mais de 200px de altura) e nada vaza a 360px', d.fotoAlta > 200 && d.sobra <= 0, JSON.stringify(d));
  const pp = await pe(p);
  igual('o pé: Voltar e "Ver meu pedido" (já tem 1 no carrinho), sem a fita repetindo',
    [pp.voltar, pp.principal, d.fita], ['Voltar', 'Ver meu pedido', 'none']);
  await p.click('#produtoAberto .loja-qtd button[aria-label="Pôr mais um"]'); await p.waitForTimeout(300);
  igual('o + do produto aberto soma, e a tela continua no produto', await p.evaluate(() =>
    [tela, Object.values(carrinho).reduce((s, n) => s + n, 0)]), ['produto', 2]);
  await tocarVoltar(p);
  igual('o Voltar leva de volta à loja', await p.evaluate(() => tela), 'loja');
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Da capa, o destaque também abre; e o produto sem nada no carrinho');
{
  const { p, ctx } = await aparelho();
  await p.locator('#capaLoja .abre-produto', { hasText: 'Perfume' }).first().click({ position: { x: 20, y: 20 } });
  await p.waitForTimeout(500);
  const a = await pe(p);
  igual('abre o Perfume, com "Adicionar ao pedido"', [a.tela, await p.evaluate(() =>
    document.querySelector('.prod-nome').textContent), a.principal], ['produto', 'Perfume ok', 'Adicionar ao pedido']);
  verdade('sem descrição, diz isso em vez de ficar em branco', /ainda não escreveu/.test(await p.evaluate(() =>
    document.querySelector('.prod-desc').textContent)));
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  igual('Adicionar ao pedido soma 1, e o pé vira "Ver meu pedido"', [await p.evaluate(() =>
    Object.values(carrinho).reduce((s, n) => s + n, 0)), (await pe(p)).principal], [1, 'Ver meu pedido']);
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  igual('e "Ver meu pedido" abre a loja', await p.evaluate(() => tela), 'loja');
  await tocarVoltar(p); await tocarVoltar(p);
  igual('Voltar, Voltar: de novo na capa', await p.evaluate(() => tela), 'capa');
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
