/* ===========================================================================
   AgendaPro — o Crediário na tela (47_crediario)

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/crediario-tela.test.mjs

   A Maria leva 2 conjuntos de R$ 150: R$ 100 de entrada no Pix e o resto em
   2x. A comanda está desligada na plataforma (o jeito de hoje), então a
   venda é feita na própria aba Crediário.

     1. a aba aparece com o módulo; a venda: cliente, itens, entrada, parcelas
        e a conta antes; o CPF que faltava vai para a ficha;
     2. o combinado pelo WhatsApp do salão;
     3. a aba: a receber, a parcela, "Recebi" com parte do valor, "Cobrar";
     4. a ficha da cliente diz quanto ela deve;
     5. o relatório mostra o crediário;
     6. sem o módulo, a aba explica e leva a contratar.
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
// O Crediário nasce fora da venda (46): na bancada, à venda, como ficará.
await banco.query(`update public.adicionais set ativo = true where codigo = 'crediario'`);

const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
async function salaoEssencial(nome){
  const d = novaAba();
  await d.criarConta({ email:`cred-${nome.split(' ')[0].toLowerCase()}-${marca}@teste.com`, senha:'minhasenhaboa', nome,
    telefone:'+5511' + (100000000 + Math.floor(Math.random() * 89999999)) });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Loja ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:'11222333000181', p_origem:null });
  const salao = cr[0].salao_id;
  await banco.query(`update public.assinaturas set plano = 'individual', status = 'ativa', trial_ate = null,
    vence_em = current_date + 20 where salao_id = $1`, [salao]);
  return { d, salao };
}
const ana = await salaoEssencial('Ana Lingerie');
await banco.query(`insert into public.salao_adicionais (salao_id, adicional, status, ativo_desde)
  values ($1, 'crediario', 'ativo', now())`, [ana.salao]);
await banco.query(`update public.saloes set cfg = coalesce(cfg, '{}'::jsonb)
  || '{"pagamentos":{"formas":["pix"],"pix":"pix@ana.com"}}'::jsonb where id = $1`, [ana.salao]);
const PROD = (await linha(`insert into public.produtos (salao_id, nome, preco) values ($1, 'Conjunto renda', 150)
  returning id`, [ana.salao])).id;
const MARIA = (await linha(`insert into public.clientes (salao_id, nome, telefone) values ($1, 'Maria Souza', $2)
  returning id`, [ana.salao, '119' + String(10000000 + Math.floor(Math.random() * 89999999))])).id;
const bia = await salaoEssencial('Bia Sem Modulo');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrirPainel(dados, rotulo){
  const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(rotulo + ': ' + e.message));
  p.on('dialog', d => { erros.push(rotulo + ' (alerta): ' + d.message()); d.accept(); });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
    window.__abriu = []; window.open = u => { window.__abriu.push(String(u)); return null; }; }, [BASE, dados.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.planos && bd.planos.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  return { ctx, p };
}
const texto = (p, sel) => p.evaluate(s => (document.querySelector(s) || {}).innerText || '', sel)
  .then(t => t.replace(/\s+/g, ' ').trim());
const abas = p => p.evaluate(() => [...document.querySelectorAll('#abas .aba')].map(b => b.dataset.chave));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A venda no crediário, na própria aba');
const { ctx, p } = await abrirPainel(ana.d, 'ana');
await p.waitForFunction(() => [...document.querySelectorAll('#abas .aba')].some(b => b.dataset.chave === 'crediario'),
  null, { timeout: 15000 }).catch(() => {});
verdade('com o módulo, a aba Crediário aparece (com a comanda desligada)', (await abas(p)).includes('crediario'));
await p.evaluate(() => irPara('crediario'));
await p.waitForSelector('#crResumo', { timeout: 15000 });
await p.click('button:has-text("+ Nova venda no crediário")');
await p.waitForSelector('#vnCliente');
await p.selectOption('#vnCliente', MARIA);
await p.waitForSelector('#vcCpf');
await p.fill('#vcCpf', '529.982.247-25');
await p.selectOption('#vnItem', 'produto:' + PROD);
await p.fill('#vnQtd', '2');
await p.click('button:has-text("+ Somar à venda")');
await p.fill('#vnEntrada', '100');
await p.selectOption('#vnN', '2');
await p.evaluate(() => pintarVendaNova());
verdade('a conta antes: total R$ 300, entrada R$ 100, no crediário R$ 200',
  /Total R\$\s?300,00 · entrada R\$\s?100,00 · no crediário: R\$\s?200,00/.test(await texto(p, '#vnConta')),
  await texto(p, '#vnConta'));
verdade('e as duas parcelas de R$ 100, um mês depois da outra',
  /1ª · \d\d\/\d\d · R\$\s?100,00 2ª · \d\d\/\d\d · R\$\s?100,00/.test(await texto(p, '#vnPrevia')),
  await texto(p, '#vnPrevia'));
await p.click('#fundo button:has-text("Vender no crediário")');
await p.waitForSelector('#vcParcelas', { timeout: 15000 }).catch(() => {});
verdade('"Vendido no crediário", com as duas parcelas', /1ª · .* R\$\s?100,00 2ª · .* R\$\s?100,00/.test(await texto(p, '#vcParcelas')),
  await texto(p, '#vcParcelas'));
const venda = await linha(`select t.total, c.status, cl.cpf from public.crediarios cr
  join public.comandas c on c.id = cr.comanda_id join public.comandas_totais t on t.id = c.id
  join public.clientes cl on cl.id = cr.cliente_id where cr.cliente_id = $1`, [MARIA]);
igual('no banco: a venda de R$ 300 fechada, e o CPF que faltava foi para a ficha',
  venda, { total:'300.00', status:'fechada', cpf:'52998224725' });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. O combinado pelo WhatsApp do salão');
await p.click('#fundo button:has-text("Mandar o combinado no WhatsApp")');
const zap = decodeURIComponent(((await p.evaluate(() => window.__abriu)) || []).slice(-1)[0] || '');
verdade('leva o valor, as parcelas e o Pix', zap.includes('wa.me/') && /R\$\s?200,00 em 2x/.test(zap)
  && zap.includes('Pix: pix@ana.com'), zap);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. A aba: receber e cobrar');
await p.evaluate(() => { fecharModal(); irPara('crediario'); });
await p.waitForFunction(() => /Maria Souza/.test((document.getElementById('crCorpo') || {}).innerText || ''),
  null, { timeout: 15000 }).catch(() => {});
verdade('a receber: R$ 200', /R\$\s?200,00 a receber/.test(await texto(p, '#crResumo')), await texto(p, '#crResumo'));
await p.click('.cr-venda .cr-parcela >> nth=0 >> button:has-text("Recebi")');
await p.waitForSelector('#crValor');
await p.fill('#crValor', '60');
await p.selectOption('#crForma', 'dinheiro');
await p.click('#fundo button:has-text("Receber")');
await p.waitForFunction(() => /Recebido R\$\s?60,00/.test((document.getElementById('crCorpo') || {}).innerText || ''),
  null, { timeout: 15000 }).catch(() => {});
const cartao = await texto(p, '.cr-venda');
verdade('pagou R$ 60 da primeira: falta R$ 40, e o recebimento aparece',
  /falta R\$\s?40,00/.test(cartao) && /Recebido R\$\s?60,00 · Dinheiro/.test(cartao), cartao);
await p.click('.cr-venda .cr-parcela >> nth=0 >> button:has-text("Cobrar")');
const cobra = decodeURIComponent(((await p.evaluate(() => window.__abriu)) || []).slice(-1)[0] || '');
verdade('"Cobrar" abre o WhatsApp com a parcela e o que falta', /Lembrete da parcela 1 de 2/.test(cobra)
  && /R\$\s?40,00/.test(cobra), cobra);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Na ficha da cliente');
await p.evaluate(id => abrirCliente(id), MARIA);
await p.waitForFunction(() => /deve/.test((document.getElementById('kCrediario') || {}).innerText || ''),
  null, { timeout: 15000 }).catch(() => {});
verdade('"Crediário: deve R$ 140,00 em 2 parcela(s)"', /deve R\$\s?140,00 em 2 parcela/.test(await texto(p, '#kCrediario')),
  await texto(p, '#kCrediario'));
await p.evaluate(() => fecharModal());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. No relatório');
await p.evaluate(() => irPara('relatorios'));
await p.waitForSelector('#relCrediario', { timeout: 15000 }).catch(() => {});
const rel = await texto(p, '#relCrediario');
verdade('vendido R$ 200 no crediário, recebido R$ 60, a receber R$ 140',
  /R\$\s?200,00 vendido no crediário/.test(rel) && /R\$\s?60,00 recebido das parcelas/.test(rel)
  && /R\$\s?140,00 a receber/.test(rel), rel);
await ctx.close();

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Sem o módulo');
{
  const { ctx: c2, p: pb } = await abrirPainel(bia.d, 'bia');
  await pb.waitForFunction(() => [...document.querySelectorAll('#abas .aba')].some(b => b.dataset.chave === 'crediario'),
    null, { timeout: 15000 }).catch(() => {});
  await pb.evaluate(() => irPara('crediario'));
  await pb.waitForTimeout(800);
  const t = await texto(pb, '#crCorpo');
  verdade('a aba explica o módulo, com o preço e o caminho para contratar',
    /módulo adicional/.test(t) && /R\$\s?49,90 por mês/.test(t) && /Contratar em Meu plano/.test(t), t);
  await c2.close();
}

verdade('sem erro de JavaScript nem alerta', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
