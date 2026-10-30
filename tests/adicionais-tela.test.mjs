/* ===========================================================================
   AgendaPro — os módulos adicionais na tela (46_adicionais): o Crediário em
   Meu plano

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/adicionais-tela.test.mjs

   A borda `adicional` é interceptada, como a do checkout (cobranca.test.mjs):
   guarda o que o painel MANDOU e faz no banco o que a borda faz — a conta
   (`preparar_adicional`) e o gravar (`aplicar_adicional`). O valor do cartão
   no Mercado Pago não roda aqui; o que o banco faz com ele está no
   adicionais.test.sql.

     1. o Essencial vê o Crediário, com o preço, e "Contratar";
     2. contratar mostra a conta ANTES ("de R$ 97,00 para R$ 146,90"), e o
        painel não manda preço nenhum; depois, "Ativo" e a soma da mensalidade;
     3. o Pix do mês diz o que cobra: "Essencial + Crediário";
     4. cancelar diz até quando vale e o que acontece com o fiado;
     5. no Básico: "Mudar para o Essencial + Crediário" pede o módulo e abre o
        pagamento do plano.
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
async function salaoNoPlano(nome, plano){
  const d = novaAba();
  await d.criarConta({ email:`adic-${plano}-${marca}@teste.com`, senha:'minhasenhaboa', nome,
    telefone:'+5511' + (100000000 + Math.floor(Math.random() * 89999999)) });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:'11222333000181', p_origem:null });
  const salao = cr[0].salao_id;
  await banco.query(`update public.assinaturas set plano = $2, status = 'ativa', trial_ate = null,
    vence_em = current_date + 20 where salao_id = $1`, [salao, plano]);
  return { d, salao };
}
const ana = await salaoNoPlano('Ana Lingerie', 'individual');
const bia = await salaoNoPlano('Bia Basico', 'basico');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrirPainel(dados, rotulo){
  const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(rotulo + ': ' + e.message));
  p.on('dialog', d => { erros.push(rotulo + ' (alerta): ' + d.message()); d.accept(); });
  p.pedidos = [];
  /* A borda `adicional`, interceptada: guarda o pedido e faz o que ela faz. */
  await p.route('**/functions/v1/adicional', async rota => {
    const req = rota.request();
    const b = JSON.parse(req.postData() || '{}');
    p.pedidos.push({ corpo: b, auth: req.headers()['authorization'] || '' });
    try{
      const c = (await banco.query(`select public.preparar_adicional($1,$2,$3,$4,$5) as c`,
        [b.salaoId, b.adicional, b.acao, dados.sessao().usuarioId, b.preco ?? null])).rows[0].c;
      if(!c.mudou) return rota.fulfill({ json: { ok: true, efeito: c.efeito } });
      const r = (await banco.query(`select public.aplicar_adicional($1,$2,$3,$4,$5,$6) as r`,
        [b.salaoId, b.adicional, b.acao, dados.sessao().usuarioId, b.preco ?? null, c.depois])).rows[0].r;
      return rota.fulfill({ json: { ...r, cartao: !!c.preapproval } });
    }catch(e){
      return rota.fulfill({ status: 403, json: { erro: String(e.message) } });
    }
  });
  /* O checkout, interceptado como no cobranca.test.mjs: a cobrança de verdade. */
  await p.route('**/functions/v1/criar-cobranca', async rota => {
    const b = JSON.parse(rota.request().postData() || '{}');
    const c = (await banco.query(`select * from public.abrir_cobranca($1, $2, $3, $4)`,
      [b.salaoId, b.plano, b.metodo, dados.sessao().usuarioId])).rows[0];
    return rota.fulfill({ json: { ok: true, cobranca: { id: c.id, plano: c.plano, valor: c.valor,
      metodo: c.metodo, venceEm: c.vence_em, itens: c.itens,
      pixCopiaCola: '00020126580014BR.GOV.BCB.PIX0136teste', pixQrBase64: null } } });
  });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dados.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.planos && bd.planos.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => irPara('plano'));
  await p.waitForSelector('#adicional-crediario', { timeout: 15000 });
  return { ctx, p };
}
const texto = (p, sel) => p.evaluate(s => (document.querySelector(s) || {}).innerText || '', sel)
  .then(t => t.replace(/\s+/g, ' ').trim());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. O Essencial vê o Crediário');
const { ctx: ctxAna, p } = await abrirPainel(ana.d, 'ana');
const cartao = await texto(p, '#adicional-crediario');
verdade('o cartão do Crediário, com o preço e o botão de contratar',
  /Crediário/.test(cartao) && /R\$\s?49,90/.test(cartao) && /por mês/.test(cartao)
  && /Contratar/.test(cartao), cartao);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Contratar: a conta antes, e o painel não manda preço');
await p.click('#adicional-crediario button:has-text("Contratar")');
await p.waitForSelector('#contaAdicional');
const conta = await texto(p, '#contaAdicional');
verdade('o dono vê antes: de R$ 97,00 para R$ 146,90, liberado agora',
  /R\$\s?97,00/.test(conta) && /R\$\s?146,90/.test(conta) && /liberado agora/.test(conta), conta);
await p.click('#fundo button:has-text("Confirmar")');
await p.waitForFunction(() => /Ativo\. Entra na sua mensalidade/.test(
  (document.getElementById('adicional-crediario') || {}).innerText || ''), null, { timeout: 15000 }).catch(() => {});
igual('o painel mandou só o salão, o módulo e a ação (nada de preço)',
  Object.keys((p.pedidos[0] || {}).corpo || {}).sort(), ['acao', 'adicional', 'salaoId']);
verdade('   com a sessão de quem pediu', /^Bearer .+/.test((p.pedidos[0] || {}).auth || ''));
verdade('depois: "Ativo. Entra na sua mensalidade."',
  /Ativo\. Entra na sua mensalidade/.test(await texto(p, '#adicional-crediario')), await texto(p, '#adicional-crediario'));
verdade('e a soma da mensalidade: Essencial + Crediário = R$ 146,90',
  /Essencial R\$\s?97,00 \+ Crediário R\$\s?49,90 = R\$\s?146,90/.test(await texto(p, '#somaMensalidade')),
  await texto(p, '#somaMensalidade'));
igual('no banco, o Crediário vale', (await linha(
  `select public.recurso_bool($1, 'crediario') as v`, [ana.salao])).v, true);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. O Pix do mês diz o que cobra');
await p.evaluate(() => assinar('individual', 'pix'));
await p.waitForFunction(() => /por mês/.test((document.getElementById('pgtoCorpo') || {}).innerText || ''),
  null, { timeout: 15000 }).catch(() => {});
verdade('"Essencial + Crediário · R$ 146,90 por mês"',
  /Essencial \+ Crediário · R\$\s?146,90 por mês/.test(await texto(p, '#pgtoCorpo')), await texto(p, '#pgtoCorpo'));
await p.evaluate(() => fecharModal());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Cancelar');
await p.evaluate(() => irPara('plano'));
await p.waitForSelector('#adicional-crediario button:has-text("Cancelar o módulo")');
await p.click('#adicional-crediario button:has-text("Cancelar o módulo")');
await p.waitForSelector('#contaAdicional');
const vence = (await linha(`select to_char(vence_em, 'DD/MM/YYYY') as v from public.assinaturas where salao_id = $1`,
  [ana.salao])).v;
const aviso = await texto(p, '#contaAdicional');
verdade('diz até quando vale, e que o fiado aberto continua (só não vende novo)',
  aviso.includes('continua valendo até ' + vence) && /só não dá para vender fiado novo/.test(aviso)
  && /R\$\s?97,00/.test(aviso), aviso);
await p.click('#fundo button:has-text("Cancelar o módulo")');
await p.waitForFunction(() => /Cancelado/.test((document.getElementById('adicional-crediario') || {}).innerText || ''),
  null, { timeout: 15000 }).catch(() => {});
verdade('o cartão passa a dizer "Cancelado — continua valendo até…", com "Voltar a contratar"',
  (await texto(p, '#adicional-crediario')).includes('Cancelado — continua valendo até ' + vence)
  && /Voltar a contratar/.test(await texto(p, '#adicional-crediario')), await texto(p, '#adicional-crediario'));
await ctxAna.close();

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. No Básico');
{
  const { ctx, p: pb } = await abrirPainel(bia.d, 'bia');
  const c = await texto(pb, '#adicional-crediario');
  verdade('"Disponível a partir do Essencial", com "Mudar para o Essencial + Crediário"',
    /Disponível a partir do Essencial/.test(c) && /Mudar para o Essencial \+ Crediário/.test(c), c);
  await pb.click('#adicional-crediario button:has-text("Mudar para o Essencial")');
  await pb.waitForSelector('#contaAdicional');
  await pb.click('#fundo button:has-text("Confirmar")');
  await pb.waitForFunction(() => /Como você quer pagar/.test((document.querySelector('#fundo .modal') || {}).innerText || ''),
    null, { timeout: 15000 }).catch(() => {});
  const modal = await texto(pb, '#fundo .modal');
  verdade('o módulo fica pedido e abre o pagamento do Essencial (Pix ou cartão)',
    /Assinar o Essencial/.test(modal) && /Pix/.test(modal) && /Cartão/.test(modal), modal);
  igual('no banco: aguardando, sem valer ainda', await linha(
    `select status, public.recurso_bool($1, 'crediario') as vale from public.salao_adicionais
      where salao_id = $1 and adicional = 'crediario'`, [bia.salao]), { status:'aguardando', vale:false });
  await pb.click('#fundo button:has-text("Pix")');
  await pb.waitForFunction(() => /por mês/.test((document.getElementById('pgtoCorpo') || {}).innerText || ''),
    null, { timeout: 15000 }).catch(() => {});
  verdade('o Pix do Essencial já vem com o Crediário: R$ 146,90',
    /Essencial \+ Crediário · R\$\s?146,90 por mês/.test(await texto(pb, '#pgtoCorpo')), await texto(pb, '#pgtoCorpo'));
  await ctx.close();
}

verdade('sem erro de JavaScript nem alerta', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
