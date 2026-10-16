/* ===========================================================================
   AgendaPro — "Precisa de ajuda?" pelo WhatsApp do suporte

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/ajuda.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   Quem trava e não tem a quem perguntar, desiste. Um botão que abre o
   WhatsApp do suporte do AgendaPro — (11) 96365-9620.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. O botão está no topo, à vista no celular, e com tamanho de dedo.
     2. Abre o número certo, já dizendo o salão e a tela em que a pessoa está
        — e a tela é a de AGORA, não a de quando o painel abriu.
     3. Também está no menu, e não cobre nada da agenda.
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
const NUMERO = '5511963659620';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
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

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const d = novaAba();
await d.criarConta({ email:`ajuda-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona Ajuda', telefone:'+5511' + (100000000 + Math.floor(Math.random()*89999999)) });
const NOME = 'Studio Ajuda ' + marca;
await d.chamar('criar_salao', { p_nome_salao: NOME, p_tipo:'salao',
  p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
// O wa.me de verdade não é chamado: o que se mede é o endereço que o botão abre.
await ctx.route('https://wa.me/**', r => r.fulfill({ status:200, contentType:'text/html', body:'ok' }));
const p = await ctx.newPage();
const erros = []; p.on('pageerror', e => erros.push(e.message));
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, d.sessao()]);
await p.goto(BASE + '/app.html'); await p.waitForTimeout(3500);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1200);

const abrir = async (sel) => {
  const [aba] = await Promise.all([ctx.waitForEvent('page'), p.click(sel)]);
  await aba.waitForLoadState().catch(() => {});
  const u = aba.url(); await aba.close();
  return u;
};
const texto = u => { try{ return new URL(u).searchParams.get('text') || ''; }catch(e){ return ''; } };

secao('1) No topo, à vista no celular');
const bt = await p.evaluate(() => {
  const a = document.getElementById('btAjuda');
  if(!a) return null;
  const r = a.getBoundingClientRect();
  return { visivel: a.offsetParent !== null, alto: r.height, topo: r.top,
           noTopo: !!a.closest('.topo'), txt: a.textContent.trim() };
});
verdade('o botão "Ajuda" existe e aparece', bt && bt.visivel && /Ajuda/.test(bt.txt), JSON.stringify(bt));
verdade('mora no topo da tela (não flutua por cima da agenda)', bt && bt.noTopo && bt.topo < 80, JSON.stringify(bt));
verdade('com tamanho de dedo (44px)', bt && bt.alto >= 44, JSON.stringify(bt));

secao('2) Abre o WhatsApp do suporte, dizendo o salão e a tela');
let u = await abrir('#btAjuda');
verdade('abre o número do suporte', u.startsWith('https://wa.me/' + NUMERO), u);
verdade('a conversa já diz o salão', texto(u).includes(NOME), texto(u));
verdade('e a tela em que a pessoa está', /Tela: Agenda/.test(texto(u)), texto(u));
await p.evaluate(() => irPara('clientes')); await p.waitForTimeout(900);
u = await abrir('#btAjuda');
verdade('trocou de tela, a conversa acompanha (Clientes)', /Tela: Clientes/.test(texto(u)), texto(u));

secao('3) Também no menu');
await p.evaluate(() => alternarLateral()); await p.waitForTimeout(600);
const lat = await p.evaluate(() => {
  const a = document.getElementById('latAjuda');
  return a && { visivel: a.offsetParent !== null, txt: a.textContent.trim() };
});
verdade('"Precisa de ajuda? Fale no WhatsApp" no menu', lat && lat.visivel && /ajuda/i.test(lat.txt), JSON.stringify(lat));
u = await abrir('#latAjuda');
verdade('e abre o mesmo número, com o salão', u.startsWith('https://wa.me/' + NUMERO) && texto(u).includes(NOME), u);

verdade('sem erro de JavaScript', erros.length === 0, erros.slice(0, 3).join(' | '));
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} verificações do botão de ajuda${falhou ? `, ${falhou} falharam.` : '.'}`);
process.exit(falhou ? 1 : 0);
