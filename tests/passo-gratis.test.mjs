/* ===========================================================================
   AgendaPro — o passo a passo no plano Grátis

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/passo-gratis.test.mjs

   ── O RELATO ───────────────────────────────────────────────────────────────
   Print do passo 6: "NÃO consegui salvar no banco: o seu plano cobre 0
   produtos, e o salão já tem 0". E logo depois: "mas eu não tenho uma
   semana?". O teste grátis é UM por pessoa (39_teste_unico): o mesmo e-mail
   (ou WhatsApp) já tinha usado o dele, e o salão novo nasceu no Grátis. Nada
   dizia isso, e o passo a passo oferecia o que o Grátis não tem.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. A história de verdade: a segunda conta com o mesmo e-mail (com "+2")
        nasce no Grátis — e o passo 1 diz isso, com o porquê e os limites.
     2. Serviços: o teto (5) à vista; no teto, tocar numa sugestão avisa e
        não grava.
     3. Produtos: o passo explica que não estão no plano, sem oferecer nada.
     4. Aparência: avisa que a cor só vale no link depois de assinar.
     5. Mais recursos: pacote e loja "não estão no plano"; sem mensagens.
     6. E quem está no teste não vê nada disso.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
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
const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const um = async (sql, args = []) => (await banco.query(sql, args)).rows[0];
const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const tel = () => '+5511' + (100000000 + Math.floor(Math.random() * 89999999));

async function contaComSalao(email, nome){
  const d = novaAba();
  await d.criarConta({ email, senha:'minhasenhaboa', nome, telefone: tel() });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Barbearia ' + nome + ' ' + marca, p_tipo:'barbearia',
    p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
  return { d, SALAO: cr[0].salao_id };
}

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [], alertas = [];
async function painel(d){
  const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', x => { alertas.push(x.message()); x.accept(); });
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, d.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes) && bd.planos && bd.planos.length,
    null, { timeout: 20000 });
  await p.waitForTimeout(1500);
  return { ctx, p };
}
const passo = async (p, n) => { await p.evaluate(x => abrirPrimeiroDia(x), n); await p.waitForTimeout(250); };
const texto = (p, sel) => p.evaluate(s => ((document.querySelector(s) || {}).innerText || '').replace(/\s+/g, ' '), sel);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A segunda conta com o mesmo e-mail nasce no Grátis, e o passo 1 diz por quê');
const A = await contaComSalao(`gr${marca}@gmail.com`, 'Ana');
const B = await contaComSalao(`g.r${marca}+2@gmail.com`, 'Bia');
igual('no banco: a primeira ganhou o teste; a segunda, com o mesmo e-mail (ponto e "+2"), o Grátis',
  [(await um(`select plano from public.assinaturas where salao_id=$1`, [A.SALAO])).plano,
   (await um(`select plano from public.assinaturas where salao_id=$1`, [B.SALAO])).plano],
  ['trial', 'gratuito']);

const { ctx, p } = await painel(B.d);
await passo(p, 1);
const aviso = await texto(p, '#pdAvisoGratis');
verdade('o passo 1 diz que o salão está no Grátis, e que o teste de 7 dias é um por pessoa',
  /Este salão está no plano Grátis/.test(aviso) && /teste grátis de 7 dias/.test(aviso) && /um por pessoa/.test(aviso), aviso);
verdade('   com os limites do plano: 1 profissional, até 5 serviços, sem produtos',
  /1 profissional/.test(aviso) && /até 5 serviços/.test(aviso) && /sem produtos/.test(aviso), aviso);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Serviços: o teto à vista, e sem passar dele');
for(let i = 0; i < 5; i++)
  await B.d.inserir('servicos', { salaoId: B.SALAO, nome:'Serviço ' + (i + 1), duracaoMin:30, intervaloMin:0,
    preco:30, ativo:true, aceitaOnline:true });
await p.evaluate(async () => { const n = await carregarTudo(); if(n) bd = n; });
await passo(p, 4);
verdade('com 5 serviços: "O seu plano cobre até 5 serviços — o salão tem 5"',
  /cobre até 5 serviços — o salão tem 5/.test(await texto(p, '#pdTetoServicos')), await texto(p, '#pdTetoServicos'));
alertas.length = 0;
await p.evaluate(async () => { await pdVirarServico('barba', 0); });
await p.waitForTimeout(800);
igual('tocar numa sugestão avisa (sem o erro do banco) e não grava nada',
  [alertas.length === 1 && /cobre até 5 serviços/.test(alertas[0]) && !/NÃO consegui salvar/.test(alertas[0]),
   (await um(`select count(*)::int n from public.servicos where salao_id=$1`, [B.SALAO])).n], [true, 5]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Produtos: explica, sem oferecer');
alertas.length = 0;
await passo(p, 6);
const prod = await p.evaluate(() => ({ aviso: ((document.getElementById('pdSemProdutos') || {}).innerText || '').replace(/\s+/g, ' '),
  sugestoes: document.querySelectorAll('#pdCorpo .pd-sug, #pdCorpo input').length }));
verdade('"Produtos não estão no seu plano (Grátis)", sem nenhuma sugestão nem campo',
  /Produtos não estão no seu plano/.test(prod.aviso) && prod.sugestoes === 0, JSON.stringify(prod));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Aparência e 5. Mais recursos');
await passo(p, 9);
verdade('a cor: "no seu plano o link usa a cor padrão… passa a valer quando assinar"',
  /cor\s+padrão/.test(await texto(p, '#pdCorNoPlano')) && /quando assinar/.test(await texto(p, '#pdCorNoPlano')),
  await texto(p, '#pdCorNoPlano'));
await passo(p, 10);
const rec = await p.evaluate(() => Object.fromEntries([...document.querySelectorAll('#pdCorpo .pd-rec')]
  .map(c => [c.dataset.rec, c.innerText.replace(/\s+/g, ' ')])));
verdade('pacote e loja: "Não está no seu plano agora"',
  /Não está no seu plano/.test(rec.pacote || '') && /Não está no seu plano/.test(rec.loja || ''), JSON.stringify(rec));
verdade('mensagens: "Seu plano não tem mensagens no WhatsApp", sem os botões de ligar',
  /Seu plano não tem mensagens no WhatsApp/.test(rec.mensagens || '')
  && await p.evaluate(() => !document.getElementById('pdReguaLembrete')), rec.mensagens);
verdade('e nenhum alerta do banco em nenhum desses passos', alertas.length === 0, alertas.join(' | '));
await ctx.close();

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Quem está no teste não vê nada disso');
{
  const { ctx: c2, p: pa } = await painel(A.d);
  await passo(pa, 1);
  const semAviso = await pa.evaluate(() => !document.getElementById('pdAvisoGratis'));
  await passo(pa, 6);
  const comProdutos = await pa.evaluate(() => !document.getElementById('pdSemProdutos')
    && !!document.getElementById('pdReguaProdutos'));
  await passo(pa, 10);
  const comMensagens = await pa.evaluate(() => !document.getElementById('pdSemMensagens'));
  igual('no teste: sem o aviso do Grátis, com produtos e com mensagens', [semAviso, comProdutos, comMensagens], [true, true, true]);
  await c2.close();
}

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam.`);
process.exit(falhou ? 1 : 0);
