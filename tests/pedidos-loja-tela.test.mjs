/* ===========================================================================
   AgendaPro — o pedido da loja, do link ao painel (53_pedidos_loja)

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/pedidos-loja-tela.test.mjs

   O pedido: "a pessoa tem que fazer seu cadastro e depois enviar no WhatsApp
   do jeito que está, e quando clicar enviar vai aparecer no painel, no
   módulo pedidos, que aí eu tenho que confirmar a lista e como será o
   pagamento — e o crediário, se tiver o módulo".

     1. no link: sem conta, Enviar pede o cadastro; feito, volta à loja;
        enviar grava o pedido (nº 1) e abre o WhatsApp com o número;
        corrigir e mandar de novo atualiza o mesmo pedido;
     2. no painel: a aba Pedidos lista; Vender confere os itens e fecha no
        Pix — a comanda fecha e o estoque baixa;
     3. o segundo pedido no Crediário: a venda a prazo abre com a cliente e os
        itens, e o pedido sai vendido;
     4. o terceiro é cancelado.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pgLib from './pg.mjs';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
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

const banco = new pgLib.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const linha = async (q, v) => (await banco.query(q, v)).rows[0];
await banco.query(`update public.adicionais set ativo = true where codigo = 'crediario'`);

const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const tel = () => String(900000000 + Math.floor(Math.random() * 89999999));
const dona = novaAba();
await dona.criarConta({ email:`pl-${m}@teste.com`, senha:'minhasenhaboa', nome:'Ana Loja', telefone:'+5511' + tel() });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Loja da Ana ' + m,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:'11222333000181', p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await banco.query(`update public.assinaturas set plano = 'individual', status = 'ativa', trial_ate = null,
  vence_em = current_date + 20 where salao_id = $1`, [SALAO]);
await banco.query(`insert into public.salao_adicionais (salao_id, adicional, status, ativo_desde)
  values ($1, 'crediario', 'ativo', now())`, [SALAO]);
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, funcionamento: SEMANA, pagamentos:{ formas:['pix'] } } });
const BATOM = await dona.inserir('produtos', { salaoId: SALAO, nome:'Batom vermelho', preco:40, estoque:10,
  ativo:true, vendaOnline:true });
const CREME = await dona.inserir('produtos', { salaoId: SALAO, nome:'Creme de mãos', preco:25, estoque:5,
  ativo:true, vendaOnline:true });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const texto = (p, sel) => p.evaluate(s => (document.querySelector(s) || {}).innerText || '', sel)
  .then(t => t.replace(/\s+/g, ' ').trim());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. No link: o cadastro antes, e o pedido gravado');
const ctxL = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
const pl = await ctxL.newPage();
pl.on('pageerror', e => erros.push('link: ' + e.message));
await pl.addInitScript(() => {
  window.__zap = [];
  window.open = u => { const w = { opener: 1, close(){ w.fechada = true; },
    location: { set href(v){ window.__zap.push(v); } } }; if(u) window.__zap.push(u); return w; };
});
await pl.goto(BASE + '/agendar.html?salao=' + SLUG);
await pl.waitForFunction(() => typeof produtosDaLoja === 'function' && produtosDaLoja().length === 2, null, { timeout: 15000 });
await pl.evaluate(([b, c]) => { mudarNoCarrinho(b, 1); mudarNoCarrinho(b, 1); mudarNoCarrinho(c, 1); irPara('loja'); }, [BATOM.id, CREME.id]);
await pl.waitForTimeout(400);
await pl.evaluate(() => enviarPedido());
await pl.waitForTimeout(500);
igual('sem conta, Enviar abre o cadastro, dizendo por quê, e não abre o WhatsApp',
  await pl.evaluate(() => [tela, contaModo, /Para enviar o pedido, faça seu cadastro/.test(document.getElementById('avisoConta').innerText),
    window.__zap.length]), ['conta', 'criar', true, 0]);
await pl.fill('#cNome', 'Gal Prado'); await pl.fill('#cTel', '(11) ' + tel().replace(/(\d{5})(\d{4})/, '$1-$2'));
await pl.fill('#cNasc', '1990-05-04');
await pl.fill('#cEmail', `gal-${m}@t.com`); await pl.fill('#cSenha', 'senhadagal1');
await pl.click('#btPrincipal');
await pl.waitForFunction(() => tela === 'loja', null, { timeout: 15000 }).catch(() => {});
await pl.waitForTimeout(600);
igual('criou a conta e voltou para a loja, com o carrinho, e a loja diz para enviar',
  await pl.evaluate(() => [tela, logada(), itensNoCarrinho(), !!document.getElementById('pedidoLojaPronto')]),
  ['loja', true, 3, true]);
await pl.evaluate(() => enviarPedido());
await pl.waitForFunction(() => !!document.getElementById('pedidoLojaFeito'), null, { timeout: 15000 }).catch(() => {});
const ped1 = await linha(`select p.id, p.numero, p.status, c.nome, p.total_estimado::text total,
    (select string_agg(i.descricao || ' ' || i.qtd::int, ', ' order by i.descricao) from public.pedido_loja_itens i where i.pedido_id = p.id) itens
  from public.pedidos_loja p join public.clientes c on c.id = p.cliente_id where p.salao_id = $1 order by p.numero limit 1`, [SALAO]);
igual('o pedido nº 1 está no banco, na ficha dela, com o preço do cadastro',
  ped1 && [ped1.numero, ped1.status, ped1.nome, ped1.total, ped1.itens],
  [1, 'novo', 'Gal Prado', '105.00', 'Batom vermelho 2, Creme de mãos 1']);
const zap1 = await pl.evaluate(() => decodeURIComponent((window.__zap.slice(-1)[0] || '').split('?text=')[1] || ''));
verdade('e o WhatsApp abriu com o texto de sempre e o número do pedido',
  /quero estes produtos \(pedido nº 1\):/.test(zap1) && /Batom vermelho — 2x/.test(zap1), zap1);
verdade('   a loja diz o número, e que dá para corrigir e mandar de novo',
  /Pedido nº 1 enviado/.test(await texto(pl, '#pedidoLojaFeito')) && /é atualizado/.test(await texto(pl, '#pedidoLojaFeito')),
  await texto(pl, '#pedidoLojaFeito'));
// Corrigiu: tirou um batom e mandou de novo.
const abertos = await pl.evaluate(() => window.__zap.length);
await pl.evaluate(b => { mudarNoCarrinho(b, -1); enviarPedido(); }, BATOM.id);
await pl.waitForTimeout(1500);
igual('mandou de novo, corrigido: o MESMO nº 1, com os itens novos (e uma janela só)',
  [ (await linha(`select count(*)::int n from public.pedidos_loja where salao_id = $1`, [SALAO])).n,
    (await linha(`select string_agg(descricao || ' ' || qtd::int, ', ' order by descricao) i from public.pedido_loja_itens
       where pedido_id = $1`, [ped1.id])).i,
    await pl.evaluate(() => window.__zap.length) - abertos ],
  [1, 'Batom vermelho 1, Creme de mãos 1', 1]);
await ctxL.close();

// O segundo e o terceiro pedidos, da Gal, pelo banco (o caminho do link já foi medido).
const gal = novaAba();
await gal.entrar({ email:`gal-${m}@t.com`, senha:'senhadagal1' });
const um = r => Array.isArray(r) ? r[0] : r;
const ped2 = um(await gal.chamar('fazer_pedido_loja', { p_salao: SALAO, p_itens: [{ id: CREME.id, qtd: 2 }], p_cupom: null, p_pedido: null }));
const ped3 = um(await gal.chamar('fazer_pedido_loja', { p_salao: SALAO, p_itens: [{ id: BATOM.id, qtd: 1 }], p_cupom: null, p_pedido: null }));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. No painel: a aba Pedidos, e vender no Pix');
const ctxP = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
const pp = await ctxP.newPage();
pp.on('pageerror', e => erros.push('painel: ' + e.message));
pp.on('dialog', d => d.accept());
await pp.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
await pp.goto(BASE + '/app.html');
await pp.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes) && bd.planos && bd.planos.length,
  null, { timeout: 20000 });
await pp.waitForTimeout(1200);
await pp.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
verdade('a aba Pedidos aparece (salão com produto na loja)',
  await pp.evaluate(() => minhasTelas().some(t => t[0] === 'pedidosloja')));
await pp.evaluate(() => irPara('pedidosloja'));
await pp.waitForSelector('.pl-pedido', { timeout: 15000 });
const cartoes = await pp.evaluate(() => [...document.querySelectorAll('.pl-pedido h3')].map(h => h.textContent.trim()));
igual('os três pedidos esperando, o mais novo primeiro', cartoes,
  ['Pedido nº 3 · Gal Prado', 'Pedido nº 2 · Gal Prado', 'Pedido nº 1 · Gal Prado']);
await pp.click(`#pl-${ped1.id} button:has-text("Vender")`);
await pp.waitForSelector('#plItens .pl-item');
igual('Vender abre a lista para conferir, com o preço do cadastro', await pp.evaluate(() =>
  [document.getElementById('modalTitulo').textContent, [...document.querySelectorAll('#plItens .pl-qtd')].map(b => b.textContent),
   /R\$\s?65,00/.test(document.getElementById('plTotal').innerText),
   [...document.querySelectorAll('#plForma option')].map(o => o.value)]),
  ['Vender o pedido nº 1', ['1', '1'], true, ['pix', 'dinheiro', 'credito', 'debito', 'transferencia', 'crediario']]);
// Não tinha creme: tira, e vende só o batom no Pix.
await pp.click('#plItens .pl-item:nth-child(2) button[aria-label="Menos um"]');
verdade('   tirou o creme: o total passa a R$ 40,00', /R\$\s?40,00/.test(await texto(pp, '#plTotal')), await texto(pp, '#plTotal'));
await pp.click('#modalPe .btn-p:has-text("Vender")');
await pp.waitForFunction(() => !document.getElementById('fundo').classList.contains('on'), null, { timeout: 15000 }).catch(() => {});
await pp.waitForTimeout(1200);
const venda1 = await linha(`select p.status, c.status cstatus, t.total::text total,
    (select string_agg(forma || ' ' || valor, ',') from public.pagamentos where comanda_id = c.id) pg,
    (select estoque::int from public.produtos where id = $2) batom, (select estoque::int from public.produtos where id = $3) creme
  from public.pedidos_loja p join public.comandas c on c.id = p.comanda_id join public.comandas_totais t on t.id = c.id
  where p.id = $1`, [ped1.id, BATOM.id, CREME.id]);
igual('vendido: a comanda fechou com R$ 40 no Pix, o batom saiu do estoque e o creme não',
  venda1 && [venda1.status, venda1.cstatus, venda1.total, venda1.pg, venda1.batom, venda1.creme],
  ['vendido', 'fechada', '40.00', 'pix 40.00', 9, 5]);
verdade('   e o pedido nº 1 sai da lista de esperando, para o histórico',
  !(await pp.evaluate(() => !!document.querySelector('.pl-pedido h3') && [...document.querySelectorAll('.pl-pedido h3')]
    .some(h => /nº 1 /.test(h.textContent + ' '))))
  && /Vendido/.test(await texto(pp, '#plHistorico')), await texto(pp, '#plCorpo'));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. O segundo no Crediário');
await pp.click(`#pl-${ped2.pedido} button:has-text("Vender")`);
await pp.waitForSelector('#plForma');
await pp.selectOption('#plForma', 'crediario');
verdade('escolheu Crediário: avisa que a próxima tela é das parcelas', /parcelas/.test(await texto(pp, '#plTotal')));
await pp.click('#modalPe .btn-p:has-text("Vender")');
await pp.waitForSelector('#vnCliente', { timeout: 10000 });
await pp.waitForTimeout(400);
igual('abre a venda no crediário com a cliente e os itens do pedido', await pp.evaluate(() =>
  [document.getElementById('modalTitulo').textContent, acharCliente(document.getElementById('vnCliente').value).nome,
   vendaNova.itens.map(i => i.qtd), !!document.getElementById('vcCpf')]),
  ['Pedido nº 2 no crediário', 'Gal Prado', [2], true]);
await pp.fill('#vcCpf', '529.982.247-25');
await pp.selectOption('#vnN', '2');
await pp.click('#modalPe .btn-p:has-text("Vender no crediário")');
await pp.waitForFunction(() => /Vendido no crediário/.test(document.getElementById('modalTitulo').textContent), null, { timeout: 15000 }).catch(() => {});
const venda2 = await linha(`select p.status, cr.valor::text valor, cr.parcelas from public.pedidos_loja p
  join public.crediarios cr on cr.id = p.crediario_id where p.id = $1`, [ped2.pedido]);
igual('vendido no crediário: R$ 50 em 2x, e o pedido nº 2 ligado a ele',
  venda2 && [venda2.status, venda2.valor, venda2.parcelas], ['vendido', '50.00', 2]);
await pp.evaluate(() => { fecharModal(); irPara('pedidosloja'); });
await pp.waitForTimeout(1200);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. O terceiro, cancelado');
await pp.waitForSelector(`#pl-${ped3.pedido}`, { timeout: 10000 });
await pp.click(`#pl-${ped3.pedido} button:has-text("Cancelar")`);
await pp.waitForTimeout(1500);
igual('cancelado no banco, e a lista fica sem nenhum esperando',
  [(await linha(`select status from public.pedidos_loja where id = $1`, [ped3.pedido])).status,
   await pp.evaluate(() => !!document.getElementById('plVazio'))], ['cancelado', true]);
verdade('a 390px a tela cabe', await pp.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
await ctxP.close();

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
