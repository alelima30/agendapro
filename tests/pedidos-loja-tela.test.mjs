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
     4. o terceiro é cancelado;
     5. a conta sem WhatsApp (criada com o número de outra conta, ou pelo
        Google): o Enviar leva ao "Falta pouco", Meus horários tem o atalho,
        e completar volta para a loja.
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

/* ══════════════════════════════════════════════════════════════════════════
   5. A conta SEM WhatsApp. O caso de produção: a conta foi criada com um
   WhatsApp que JÁ ERA de outra conta (a da dona, por exemplo) — o banco não
   deixa duas contas com o mesmo número, e esta nasceu sem ele. A loja só
   dizia "Falta o seu WhatsApp no cadastro" e parava, sem caminho nenhum.
   Agora: o Enviar leva ao "Falta pouco", Meus horários tem o atalho, o
   número de outra conta é recusado com o botão para entrar com ela, e
   completar volta para a loja com o carrinho. */
secao('5. Conta sem WhatsApp: o caminho para completar, e de volta à loja');
{
  const lia = novaAba();
  const telLia = tel();
  await lia.criarConta({ email:`lia-${m}@t.com`, senha:'senhadalia1', nome:'Lia Sem Zap', telefone:'+5511' + tel() });
  // Sem WhatsApp, e com o aniversário que já tinha: o Falta pouco não pede de novo.
  await banco.query(`update public.perfis set telefone = null, nascimento = '1995-03-12' where email = $1`, [`lia-${m}@t.com`]);
  const telDaDona = (await linha(`select public.telefone_nacional(telefone) t from public.perfis where email = $1`, [`pl-${m}@teste.com`])).t;
  const masc = t => '(' + t.slice(0, 2) + ') ' + t.slice(2, 7) + '-' + t.slice(7);
  const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link sem zap: ' + e.message));
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
    window.__zap = []; window.__fechadas = 0;
    window.open = u => { const w = { opener: 1, close(){ window.__fechadas++; },
      location: { set href(v){ window.__zap.push(v); } } }; if(u) window.__zap.push(u); return w; };
  }, [BASE, lia.sessao()]);
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'completar', null, { timeout: 15000 }).catch(() => {});
  igual('ao abrir, logada e sem WhatsApp, o link pede para completar (só o WhatsApp: o aniversário ela já tem)',
    await p.evaluate(() => [tela, getComputedStyle(document.getElementById('campoCpNasc')).display === 'none',
      /aniversário/.test(document.getElementById('subCompletar').textContent)]), ['completar', true, false]);
  await p.click('#btSecundario'); await p.waitForTimeout(400);

  // Meus horários: o atalho para completar, a qualquer hora.
  await p.evaluate(() => irPara('meus')); await p.waitForTimeout(600);
  verdade('"Agora não" e depois Meus horários: o aviso de que falta o WhatsApp, com "Completar meus dados"',
    await p.evaluate(() => !!document.getElementById('meusFaltaZap') && !!document.getElementById('btCompletarDados')));
  await p.click('#btCompletarDados'); await p.waitForTimeout(400);
  igual('   o botão abre o Falta pouco; "Agora não" volta para Meus horários',
    [await p.evaluate(() => tela), await p.click('#btSecundario').then(() => p.waitForTimeout(400)).then(() => p.evaluate(() => tela))],
    ['completar', 'meus']);

  await p.waitForFunction(() => produtosDaLoja().length === 2, null, { timeout: 15000 });
  await p.evaluate(b => { mudarNoCarrinho(b, 1); irPara('loja'); }, BATOM.id);
  await p.waitForTimeout(300);
  await p.evaluate(() => enviarPedido());
  await p.waitForTimeout(600);
  igual('na loja, Enviar: vai ao "Falta pouco", dizendo que é para o pedido, sem abrir o WhatsApp',
    await p.evaluate(() => [tela, /Para enviar o pedido, falta o seu WhatsApp/.test(document.getElementById('avisoCompletar').innerText),
      window.__zap.length]), ['completar', true, 0]);
  await p.evaluate(() => voltar()); await p.waitForTimeout(400);
  igual('voltou sem completar: a loja, com o carrinho, dizendo que o pedido não saiu (e não "Cadastro feito")',
    await p.evaluate(() => [tela, itensNoCarrinho(), !!document.getElementById('pedidoLojaFaltaZap'),
      !!document.getElementById('pedidoLojaPronto')]), ['loja', 1, true, false]);
  // O banco é quem confere: mesmo sem a loja saber de antemão, a recusa leva ao mesmo lugar.
  await p.evaluate(() => { contaSemZap = false; enviarPedido(); });
  await p.waitForFunction(() => tela === 'completar', null, { timeout: 15000 }).catch(() => {});
  igual('   e se só o banco souber: a janela em branco fecha e vai ao "Falta pouco"',
    await p.evaluate(() => [tela, window.__fechadas, window.__zap.length]), ['completar', 1, 0]);

  // O WhatsApp que já é de outra conta (o da dona): recusa, e o caminho é entrar com ela.
  await p.fill('#cpTel', masc(telDaDona));
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  verdade('o WhatsApp de outra conta: diz isso, com o botão "Entrar com a outra conta"',
    /já está em outra conta/.test(await texto(p, '#avisoCompletar')) && await p.evaluate(() => !!document.getElementById('btOutraConta')),
    await texto(p, '#avisoCompletar'));
  await p.click('#btOutraConta'); await p.waitForTimeout(400);
  igual('   que abre o Entrar, aqui mesmo; e o voltar leva à loja, não ao Falta pouco',
    [await p.evaluate(() => [tela, contaModo, /conta que tem este WhatsApp/.test(document.getElementById('avisoConta').innerText)]),
     await p.evaluate(() => { voltarDaConta(); return tela; })],
    [['conta', 'entrar', true], 'loja']);

  // Completa com o número dela.
  await p.evaluate(() => enviarPedido());
  await p.waitForFunction(() => tela === 'completar', null, { timeout: 15000 }).catch(() => {});
  await p.fill('#cpTel', masc('11' + telLia));
  await p.click('#btPrincipal');
  await p.waitForFunction(() => tela === 'loja', null, { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(500);
  igual('completou: volta para a loja, com o carrinho, e a loja diz para enviar',
    await p.evaluate(() => [tela, itensNoCarrinho(), !!document.getElementById('pedidoLojaPronto'),
      !!document.getElementById('pedidoLojaFaltaZap')]), ['loja', 1, true, false]);
  await p.evaluate(() => enviarPedido());
  await p.waitForFunction(() => !!document.getElementById('pedidoLojaFeito'), null, { timeout: 15000 }).catch(() => {});
  const pl4 = await linha(`select p.numero, c.telefone, c.nascimento::text n from public.pedidos_loja p
    join public.clientes c on c.id = p.cliente_id where p.salao_id = $1 and c.nome = 'Lia Sem Zap'`, [SALAO]);
  igual('enviou: o pedido nº 4 está no banco, na ficha nova dela, com o WhatsApp que ela deu e o aniversário da conta',
    pl4 && [pl4.numero, pl4.telefone, pl4.n], [4, '11' + telLia, '1995-03-12']);
  verdade('   e o WhatsApp abriu com o número do pedido',
    /\(pedido nº 4\)/.test(await p.evaluate(() => decodeURIComponent((window.__zap.slice(-1)[0] || '').split('?text=')[1] || ''))));
  await p.evaluate(() => irPara('meus')); await p.waitForTimeout(600);
  verdade('   e Meus horários não diz mais que falta', await p.evaluate(() => !document.getElementById('meusFaltaZap')));
  await ctx.close();
}

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
