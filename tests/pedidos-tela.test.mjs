/* ===========================================================================
   AgendaPro — o modo Pedidos na tela: o link do restaurante e a tela de Pedidos

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/pedidos-tela.test.mjs

   O banco é cobrado no `pedidos.test.mjs`. Aqui é o caminho de gente:

     1. o link do restaurante diz "Faça seu pedido" e "Cardápio", não
        "Agendar horário" — e o do salão continua exatamente como era;
     2. a cliente monta o pedido, escolhe entrega, bairro, pagamento e troco,
        confere a conta (com a taxa do bairro) e confirma;
     3. ela acompanha o andamento, e o aviso da capa a leva de volta;
     4. o restaurante abre o painel direto nos Pedidos, vê o selo, aceita,
        manda sair, entrega, cancela com motivo — e o pedido novo chega
        destacado sem recarregar;
     5. "Entrega e pagamento" e "Recebendo pedidos" gravam o que o banco lê.
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
const limpo = t => String(t || '').replace(/\s+/g, ' ').trim();

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
let tel = 950000000 + (Date.now() % 40000000);
async function casa(nome, tipo){
  const d = aba();
  await d.criarConta({ email:`pt-${tipo}-${m}@teste.com`, senha:'minhasenhaboa', nome:'Dona ' + nome,
    telefone:'+5511' + (tel++) });
  const cr = await d.chamar('criar_salao', { p_nome_salao: nome, p_tipo: tipo,
    p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
  d.salao = cr[0].salao_id; d.slug = cr[0].slug;
  return d;
}
const zé = await casa('Pizzaria do Zé ' + m, 'restaurante');
const salao = await casa('Salão Bela ' + m, 'salao');
const ids = [];
for(const [n, p, cat] of [['Pizza calabresa', 45, 'Pizzas'], ['Pizza marguerita', 42, 'Pizzas'],
                          ['Refrigerante 2L', 12, 'Bebidas']]){
  ids.push((await zé.inserir('produtos', { salaoId: zé.salao, nome:n, preco:p, custo:0, estoque:0,
    ativo:true, vendaOnline:true, categoria:cat })).id);
}
await zé.atualizar('saloes', zé.salao, { cfg:{ pedidos:{ taxas:[{ bairro:'Centro', taxa:5 }, { bairro:'Vila Nova', taxa:8 }],
  minimo: 20, tempo:'40 a 60 min' } } });
// O salão tem serviço e produto: o link dele não pode mudar nada.
await salao.inserir('servicos', { salaoId: salao.salao, nome:'Corte', duracaoMin:30, intervaloMin:0, preco:60,
  ativo:true, aceitaOnline:true });
await salao.inserir('produtos', { salaoId: salao.salao, nome:'Shampoo', preco:30, custo:0, estoque:0,
  ativo:true, vendaOnline:true });
ok('uma pizzaria com cardápio, taxa por bairro e mínimo; e um salão com serviço e produto');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function link(slug){
  const ctx = await nav.newContext({ viewport:{ width:412, height:880 }, isMobile:true, hasTouch:true });
  const c = await ctx.newPage();
  c.on('pageerror', e => erros.push('link: ' + e.message));
  c.on('dialog', d => d.accept());
  await c.goto(BASE + '/agendar.html?salao=' + slug);
  await c.waitForFunction(() => typeof salao !== 'undefined' && salao, null, { timeout: 15000 });
  await c.waitForTimeout(1500);
  return c;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — AS PALAVRAS DO LINK
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. O link do restaurante fala de pedido');
const c = await link(zé.slug);
igual('o botão do pé da capa é "Faça seu pedido"', limpo(await c.textContent('#btPrincipal')), 'Faça seu pedido');
const boas = limpo(await c.textContent('#capaBoas'));
verdade('o Bem-vindo convida a pedir pelo cardápio, e não a agendar nem a mandar pelo WhatsApp',
  /Escolha no cardápio e faça seu pedido/.test(boas) && !/agend/i.test(boas) && !/WhatsApp/.test(boas), boas);
verdade('a capa não oferece serviço nem equipe', await c.evaluate(() =>
  !document.querySelector('#capaServicos .sv-cartao') && getComputedStyle(document.getElementById('rotuloEquipe')).display === 'none'));
verdade('a vitrine da capa é "Do cardápio", com o botão do cardápio completo',
  /Do cardápio/.test(await c.textContent('#capaLoja')) && /Ver o cardápio completo/.test(await c.textContent('#capaLoja')));
{
  const s = await link(salao.slug);
  igual('o salão continua com "Agendar horário" no pé', limpo(await s.textContent('#btPrincipal')), 'Agendar horário');
  verdade('e com "Produtos em destaque" na capa', /Produtos em destaque/.test(await s.textContent('#capaLoja')));
  await s.evaluate(() => irPara('loja'));
  await s.evaluate(() => mudarNoCarrinho(produtosDaLoja()[0].id, 1));
  igual('e a loja dele continua mandando pelo WhatsApp', limpo(await s.textContent('#btPrincipal')), 'Enviar pedido no WhatsApp');
  await s.context().close();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — MONTAR E CONFIRMAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. A cliente monta o pedido e confirma');
await c.click('#btPrincipal');
await c.waitForTimeout(400);
igual('o pé leva ao Cardápio', limpo(await c.textContent('#lojaTitulo')), 'Cardápio');
igual('sem item, o botão diz o que falta', limpo(await c.textContent('#btPrincipal')), 'Escolha pelo menos 1 item');
await c.evaluate(([a, b]) => { mudarNoCarrinho(a, 1); mudarNoCarrinho(a, 1); mudarNoCarrinho(b, 1); }, [ids[0], ids[2]]);
igual('com itens, "Continuar" com o subtotal', limpo(await c.textContent('#btPrincipal')), 'Continuar · R$ 102,00');
await c.click('#btPrincipal');
await c.waitForTimeout(400);
igual('abre a conferência do pedido', await c.evaluate(() => tela), 'pedido');
await c.click('#btPrincipal');
await c.waitForTimeout(300);
verdade('confirmar sem escolher entrega ou retirada: a tela diz o que falta',
  /entre entrega e retirada/.test(await c.textContent('#pedidoCorpo')));
await c.click('.pd-op:has-text("Entrega")');
await c.fill('#pdRua', 'Rua das Flores');
await c.fill('#pdNumero', '120');
await c.selectOption('#pdBairro', 'Vila Nova');
await c.waitForTimeout(200);
verdade('o bairro escolhido põe a taxa dele na conta (8,00 → total 110)',
  /Taxa de entrega ?R\$ 8,00 ?Total ?R\$ 110,00/.test(limpo(await c.textContent('#pedidoConta'))), limpo(await c.textContent('#pedidoConta')));
igual('e o botão acompanha o total', limpo(await c.textContent('#btPrincipal')), 'Confirmar pedido · R$ 110,00');
await c.fill('#pdNome', 'Bruna Costa');
await c.fill('#pdTel', '11965432100');
await c.click('.pd-op:has-text("Dinheiro")');
await c.fill('#pdTroco', '150');
await c.fill('#pdObs', 'sem cebola');
await c.click('#btPrincipal');
await c.waitForFunction(() => tela === 'acompanhar' && document.querySelector('.pd-etapas'), null, { timeout: 10000 });
const acomp = limpo(await c.textContent('#acompanharCorpo'));
verdade('confirmado: a tela de acompanhar mostra o número, "Recebido" e o total do banco',
  /Pedido #1/.test(acomp) && /Esperando o restaurante confirmar/.test(acomp) && /Total ?R\$ 110,00/.test(acomp), acomp);
verdade('com a entrega, o bairro e o troco', /Entrega — Vila Nova · Dinheiro \(troco para R\$ 150,00\)/.test(acomp), acomp);
igual('o carrinho foi esvaziado', await c.evaluate(() => itensNoCarrinho()), 0);
const lista0 = await zé.chamar('pedidos_da_loja', { p_salao: zé.salao });
igual('no banco: um pedido, com a observação e o endereço',
  [lista0.length, lista0[0].observacao, lista0[0].endereco.rua, Number(lista0[0].total)], [1, 'sem cebola', 'Rua das Flores', 110]);

secao('3. Acompanhar');
await zé.chamar('mudar_status_pedido', { p_pedido: lista0[0].id, p_status: 'em_preparo' });
await c.evaluate(() => lerPedidoAcompanhado());
await c.waitForTimeout(600);
const etapa = await c.evaluate(() => document.querySelector('.pd-etapas li.agora').textContent);
verdade('aceito no painel, a tela da cliente passa para "Em preparo", com a previsão',
  /Em preparo/.test(etapa) && /40 a 60 min/.test(etapa), etapa);
verdade('e o "Cancelar este pedido" some (depois do aceite é com o restaurante)',
  !/Cancelar este pedido/.test(await c.textContent('#acompanharCorpo')));
await c.click('#btPrincipal');
await c.waitForTimeout(500);
verdade('de volta à capa, o aviso leva ao pedido em andamento',
  /Seu pedido #1.*Em preparo/.test(limpo(await c.textContent('#capaPedido'))), limpo(await c.textContent('#capaPedido')));
await c.click('#capaPedido .pd-aviso');
await c.waitForTimeout(800);
igual('tocar no aviso abre o acompanhamento', await c.evaluate(() => tela), 'acompanhar');
await c.context().close();

/* ══════════════════════════════════════════════════════════════════════════
   3 — O PAINEL
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. A tela de Pedidos do restaurante');
const cli = aba();
const fazer = o => cli.chamar('fazer_pedido', { p_slug: zé.slug, p_pedido: Object.assign({
  nome:'Carlos Lima', telefone:'11955554444', entrega:'retirada', pagamento:'pix',
  itens:[{ produto: ids[1], quantidade: 1 }] }, o) });
await fazer();
const ctxP = await nav.newContext({ viewport:{ width:1280, height:900 } });
const p = await ctxP.newPage();
p.on('pageerror', e => erros.push('painel: ' + e.message));
p.on('dialog', d => d.type() === 'prompt' ? d.accept('acabou a massa') : d.accept());
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  if(location.pathname.endsWith('app.html')) localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, zé.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForFunction(() => typeof irPara === 'function' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
await p.waitForFunction(() => telaAtual === 'pedidos' && document.querySelectorAll('.pedido-cartao').length >= 2,
  null, { timeout: 15000 }).catch(() => {});
igual('o restaurante abre direto na tela de Pedidos', await p.evaluate(() => telaAtual), 'pedidos');
const abas = await p.evaluate(() => [...document.querySelectorAll('#abas .aba')].map(a => a.dataset.chave));
verdade('com Pedidos no menu, antes da Agenda', abas.indexOf('pedidos') >= 0 && abas.indexOf('pedidos') < abas.indexOf('agenda'), abas.join(','));
igual('e os produtos se chamam Cardápio', await p.evaluate(() =>
  document.querySelector('#abas .aba[data-chave="produtos"] .aba-txt').textContent.trim()), 'Cardápio');
igual('o selo do menu conta o pedido esperando aceite', await p.evaluate(() =>
  (document.querySelector('.selo-pedidos') || {}).textContent), '1');
const grupos = await p.evaluate(() => [...document.querySelectorAll('#listaPedidos h3.secao')].map(h => h.textContent.replace(/\s+/g, ' ').trim()));
igual('os grupos com as contagens', grupos, ['Novos 1', 'Em preparo 1', 'Saiu para entrega / pronto para retirar 0']);
const cartao = id => p.locator(`.pedido-cartao[data-pedido="${id}"]`);
const lista1 = await zé.chamar('pedidos_da_loja', { p_salao: zé.salao });
const carlos = lista1.find(x => x.nome === 'Carlos Lima'), bruna = lista1.find(x => x.nome === 'Bruna Costa');
const txtBruna = limpo(await cartao(bruna.id).textContent());
verdade('o cartão mostra itens, observação, endereço com bairro, troco a levar e total',
  /2× Pizza calabresa/.test(txtBruna) && /sem cebola/.test(txtBruna) && /Rua das Flores, 120 · Vila Nova/.test(txtBruna)
  && /troco para R\$ 150,00 \(levar R\$ 40,00\)/.test(txtBruna) && /Total R\$ 110,00/.test(txtBruna), txtBruna);
await cartao(carlos.id).locator('button', { hasText: 'Aceitar' }).click();
await p.waitForTimeout(1500);
verdade('Aceitar: o pedido de retirada passa para Em preparo, com "Pronto para retirar" como próximo',
  /Em preparo/.test(await cartao(carlos.id).textContent()) && await cartao(carlos.id).locator('button', { hasText: 'Pronto para retirar' }).count() === 1);
await cartao(bruna.id).locator('button', { hasText: 'Saiu para entrega' }).click();
await p.waitForTimeout(1500);
await cartao(bruna.id).locator('button', { hasText: 'Entregue' }).click();
await p.waitForTimeout(1500);
igual('Saiu e Entregue: no banco, o da Bruna está entregue',
  (await zé.chamar('pedidos_da_loja', { p_salao: zé.salao })).find(x => x.id === bruna.id).status, 'entregue');
verdade('e ele vai para os concluídos, com o faturado das 24 horas',
  /1 entregue\(s\), R\$ 110,00/.test(limpo(await p.textContent('.pedido-fim summary'))), limpo(await p.textContent('.pedido-fim summary')));
await cartao(carlos.id).locator('button', { hasText: 'Cancelar' }).click();
await p.waitForTimeout(1500);
const canc = (await zé.chamar('pedidos_da_loja', { p_salao: zé.salao })).find(x => x.id === carlos.id);
igual('Cancelar pede o motivo e grava', [canc.status, canc.motivo], ['cancelado', 'acabou a massa']);

secao('5. O pedido novo chega sozinho');
await fazer({ nome:'Dani Rocha', telefone:'11944443333' });
await p.evaluate(() => carregarPedidos());
await p.waitForTimeout(1200);
igual('na próxima leitura ele aparece destacado como novo', await p.evaluate(() => document.querySelectorAll('.pedido-novo').length), 1);
verdade('e o título da aba do navegador conta', /^\(1\) /.test(await p.title()), await p.title());

secao('6. Entrega e pagamento, e pausar');
await p.click('button:has-text("Entrega e pagamento")');
await p.waitForSelector('#pcTaxa');
await p.fill('#pcTaxa', '6');
await p.fill('#pcMinimo', '30');
await p.fill('#pcTempo', '30 a 45 min');
await p.locator('.pcPag[value="cartao"]').uncheck();
await p.click('#modalPe button:has-text("Salvar")');
await p.waitForTimeout(1500);
const conf = await cli.chamar('pedidos_da_casa', { p_slug: zé.slug });
igual('o que a dona salvou é o que a página lê do banco',
  [Number(conf.taxaPadrao), Number(conf.minimo), conf.tempo, conf.pagamentos, conf.taxas.map(t => t.bairro)],
  [6, 30, '30 a 45 min', ['pix', 'dinheiro'], ['Centro', 'Vila Nova']]);
await p.click('#pdRecebendo');
await p.waitForTimeout(1500);
igual('desligar "Recebendo pedidos": a página fica sabendo que não está aberto',
  (await cli.chamar('pedidos_da_casa', { p_slug: zé.slug })).aberto, false);
verdade('e a tela avisa que está pausado', /pausados/.test(await p.textContent('#listaPedidos')));
await p.click('#pdRecebendo');
await p.waitForTimeout(1200);
igual('ligar de novo: aberto', (await cli.chamar('pedidos_da_casa', { p_slug: zé.slug })).aberto, true);
await p.evaluate(() => { irPara('produtos'); abrirProduto(); });
await p.waitForTimeout(400);
igual('no restaurante, o item novo do cardápio já nasce publicado no link', await p.isChecked('#pOnline'), true);
await ctxP.close();

secao('7. Nada quebrou');
igual('sem erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
