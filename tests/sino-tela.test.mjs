/* ===========================================================================
   AgendaPro — o sino do painel, na tela (54_sino)

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/sino-tela.test.mjs

   O pedido: "dentro do painel do dono do salão, um ícone de sino para as
   notificações do sistema".

     1. o admin publica um aviso para os salões (e a lista diz que está no ar);
     2. no painel da dona, o sino aparece com o número: o horário a confirmar,
        o pedido da loja e o aviso do AgendaPro;
     3. aberto, cada item diz o que é e leva à tela dele; o aviso se marca
        como lido (e sai do sino, e fica gravado);
     4. resolvido, some: confirmou o horário, o número desce;
     5. no computador, a lista abre embaixo do sino, dentro da tela;
     6. banco sem o 54 (o SQL não foi colado): o sino fica escondido, sem erro.
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

const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const tel = () => String(900000000 + Math.floor(Math.random() * 89999999));
const dona = novaAba();
await dona.criarConta({ email:`sino-${m}@teste.com`, senha:'minhasenhaboa', nome:'Ana Sino', telefone:'+5511' + tel() });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão do Sino ' + m,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:'11222333000181', p_origem:null });
const SALAO = cr[0].salao_id;
const plat = novaAba();
await plat.criarConta({ email:`plat-${m}@teste.com`, senha:'minhasenhaboa', nome:'Plataforma', telefone:'+5511' + tel() });
await banco.query(`update public.perfis set super_admin = true where email = $1`, [`plat-${m}@teste.com`]);

// Um horário marcado pelo link, esperando o "sim"; e um pedido da loja.
const CLI = (await linha(`insert into public.clientes (salao_id, nome, telefone) values ($1, 'Maria Lima', $2) returning id`,
  [SALAO, '11' + tel()])).id;
const PROF = (await linha(`select id from public.profissionais where salao_id = $1 and ativo order by criado_em limit 1`, [SALAO]))?.id
  || (await linha(`insert into public.profissionais (salao_id, nome) values ($1, 'Ana') returning id`, [SALAO])).id;
const AG = (await linha(`insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
  values ($1, $2, $3, now() + interval '2 days', now() + interval '2 days 45 minutes', 'pendente', 'online', 50) returning id`,
  [SALAO, CLI, PROF])).id;
await banco.query(`insert into public.pedidos_loja (salao_id, numero, cliente_id, status) values ($1, 1, $2, 'novo')`, [SALAO, CLI]);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const texto = (p, sel) => p.evaluate(s => (document.querySelector(s) || {}).innerText || '', sel)
  .then(t => t.replace(/\s+/g, ' ').trim());

async function abrir(sessao, url, largura = 390, rotas){
  const ctx = await nav.newContext(largura < 700 ? { viewport:{ width:largura, height:860 }, isMobile:true, hasTouch:true }
    : { viewport:{ width:largura, height:860 } });
  if(rotas) await rotas(ctx);
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(url + ': ' + e.message));
  p.on('dialog', d => d.accept());
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, sessao]);
  await p.goto(BASE + '/' + url);
  return { ctx, p };
}
async function abrirPainel(largura, rotas){
  const r = await abrir(dona.sessao(), 'app.html', largura, rotas);
  await r.p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes) && bd.planos && bd.planos.length,
    null, { timeout: 20000 });
  await r.p.waitForTimeout(1200);
  await r.p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  return r;
}
const numeroDoSino = p => p.evaluate(() => { const n = document.getElementById('sinoNum'); return n && !n.hidden ? n.textContent : ''; });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. O admin publica um aviso para os salões');
{
  const { ctx, p } = await abrir(plat.sessao(), 'admin.html', 1100);
  await p.waitForSelector('#ajusteAvisos', { timeout: 15000 });
  await p.fill('#avTitulo', 'Novidade: o sino ' + m);
  await p.fill('#avTexto', 'Agora os avisos do sistema ficam aqui no sino.');
  await p.click('#btPublicarAviso');
  await p.waitForFunction(t => (document.getElementById('ajusteAvisos') || {}).innerText?.includes(t), 'Novidade: o sino ' + m,
    { timeout: 15000 }).catch(() => {});
  const lista = await texto(p, '#ajusteAvisos');
  verdade('publicado: a lista mostra o aviso, para donos e gerentes, no ar, lido por 0',
    lista.includes('Novidade: o sino ' + m) && /donos e gerentes/.test(lista) && /no ar/.test(lista), lista);
  igual('   e está no banco', (await linha(`select para, arquivado_em is null as vivo from public.avisos_plataforma
    where titulo = $1`, ['Novidade: o sino ' + m])), { para: 'gestao', vivo: true });
  // "Como envio somente para um usuário?": o aviso para um salão só.
  await p.fill('#avTitulo', 'Só para o seu salão ' + m);
  await p.fill('#avTexto', 'Sua cortesia do plano Essencial foi prorrogada por mais 15 dias.');
  await p.selectOption('#avSalao', SALAO);
  await p.click('#btPublicarAviso');
  await p.waitForFunction(t => (document.getElementById('ajusteAvisos') || {}).innerText?.includes(t), 'Só para o seu salão ' + m,
    { timeout: 15000 }).catch(() => {});
  const linhaAv = await p.evaluate(t => { const tr = [...document.querySelectorAll('#ajusteAvisos tr')].find(x => x.innerText.includes(t));
    return tr ? tr.children[1].textContent.trim() : null; }, 'Só para o seu salão ' + m);
  igual('o aviso para um salão só: a lista diz para qual salão, e o banco guarda o salão',
    [linhaAv, (await linha(`select salao_id from public.avisos_plataforma where titulo = $1`, ['Só para o seu salão ' + m])).salao_id],
    ['Salão do Sino ' + m, SALAO]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. O sino da dona, no celular');
const { ctx: ctxC, p: pc } = await abrirPainel(390);
await pc.waitForFunction(() => getComputedStyle(document.getElementById('btSino')).display !== 'none', null, { timeout: 15000 }).catch(() => {});
verdade('o sino aparece no topo, ao lado da Ajuda', await pc.evaluate(() => {
  const s = document.getElementById('btSino').getBoundingClientRect(), a = document.getElementById('btAjuda').getBoundingClientRect();
  return s.width > 0 && s.right <= a.left + 1 && Math.abs((s.top + s.bottom) / 2 - (a.top + a.bottom) / 2) < 6;
}));
// Pode haver avisos de outros testes na mesma bancada: conta os deste salão.
const avisosVivos = Number((await linha(`select count(*) n from public.avisos_plataforma
  where arquivado_em is null and para = 'gestao' and (ate is null or ate >= current_date)
    and (salao_id is null or salao_id = $1)`, [SALAO])).n);
const esperado = 2 + avisosVivos;
igual('o número: 1 horário a confirmar + 1 pedido da loja + os avisos do AgendaPro',
  await numeroDoSino(pc), esperado > 9 ? '9+' : String(esperado));

secao('3. Aberto: o que é cada um, e para onde leva');
await pc.click('#btSino');
await pc.waitForSelector('#sinoPainel:not([hidden]) .sino-item', { timeout: 10000 });
const painel = await texto(pc, '#sinoPainel');
verdade('a lista diz: "1 horário espera sua confirmação", "1 pedido novo da loja" e o aviso, com "Marcar como lido"',
  /1 horário espera sua confirmação/.test(painel) && /1 pedido novo da loja/.test(painel)
  && painel.includes('Novidade: o sino ' + m) && /AVISO DO AGENDAPRO/.test(painel) && /Marcar como lido/.test(painel), painel);
verdade('   e o aviso que foi só para este salão também está lá', painel.includes('Só para o seu salão ' + m), painel);
verdade('   a 390px a lista cabe na tela', await pc.evaluate(() => {
  const r = document.getElementById('sinoPainel').getBoundingClientRect();
  return r.left >= 0 && r.right <= innerWidth + 1 && document.documentElement.scrollWidth <= innerWidth + 1;
}));
const idAviso = (await linha(`select id from public.avisos_plataforma where titulo = $1`, ['Novidade: o sino ' + m])).id;
await pc.click(`#sinoAviso-${idAviso} button:has-text("Marcar como lido")`);
await pc.waitForTimeout(800);
verdade('marcou como lido: sai da lista, o número desce, e fica gravado',
  !(await texto(pc, '#sinoPainel')).includes('Novidade: o sino ' + m)
  && await numeroDoSino(pc) === String(esperado - 1 > 9 ? '9+' : esperado - 1)
  && !!(await linha(`select 1 from public.avisos_lidos al join public.perfis pf on pf.id = al.perfil_id
      where al.aviso_id = $1 and pf.email = $2`, [idAviso, `sino-${m}@teste.com`])));
const idAvisoSalao = (await linha(`select id from public.avisos_plataforma where titulo = $1`, ['Só para o seu salão ' + m])).id;
await pc.click(`#sinoAviso-${idAvisoSalao} button:has-text("Marcar como lido")`);
await pc.waitForTimeout(800);
await pc.click('#sinoPainel .sino-item:has-text("pedido novo da loja")');
await pc.waitForTimeout(600);
igual('o pedido leva à aba Pedidos, e o sino fecha',
  await pc.evaluate(() => [telaAtual, document.getElementById('sinoPainel').hidden]), ['pedidosloja', true]);
await pc.click('#btSino');
await pc.waitForSelector('#sinoPainel:not([hidden]) .sino-item');
await pc.click('#sinoPainel .sino-item:has-text("horário espera")');
await pc.waitForTimeout(600);
igual('o horário leva à agenda, onde está o "espera sua confirmação"',
  await pc.evaluate(() => [telaAtual, !!document.getElementById('aConfirmar')]), ['agenda', true]);
await pc.click('#btSino'); await pc.waitForTimeout(200);
await pc.click('h1#tituloTela'); await pc.waitForTimeout(200);
igual('   tocar fora fecha a lista', await pc.evaluate(() => document.getElementById('sinoPainel').hidden), true);

secao('4. Resolvido, some');
await banco.query(`update public.agendamentos set status = 'confirmado' where id = $1`, [AG]);
await banco.query(`update public.pedidos_loja set status = 'cancelado' where salao_id = $1`, [SALAO]);
await pc.evaluate(() => pedirSino(true));
await pc.waitForTimeout(1500);
const restam = avisosVivos - 2;
igual('confirmou o horário e o pedido saiu: só os outros avisos (se houver) contam',
  await numeroDoSino(pc), restam > 0 ? (restam > 9 ? '9+' : String(restam)) : '');
if(restam === 0){
  await pc.click('#btSino');
  await pc.waitForSelector('#sinoVazio', { timeout: 8000 }).catch(() => {});
  verdade('   e a lista diz "Tudo em dia"', /Tudo em dia/.test(await texto(pc, '#sinoPainel')), await texto(pc, '#sinoPainel'));
}else ok('   (há avisos de outros testes na bancada: o "Tudo em dia" fica para o banco limpo)');
await ctxC.close();

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. No computador');
await banco.query(`update public.agendamentos set status = 'pendente' where id = $1`, [AG]);
{
  const { ctx, p } = await abrirPainel(1280);
  await p.waitForFunction(() => getComputedStyle(document.getElementById('btSino')).display !== 'none', null, { timeout: 15000 }).catch(() => {});
  await p.click('#btSino');
  await p.waitForSelector('#sinoPainel:not([hidden]) .sino-item', { timeout: 10000 });
  verdade('a lista abre embaixo do sino, alinhada à direita, dentro da tela', await p.evaluate(() => {
    const s = document.getElementById('btSino').getBoundingClientRect(), r = document.getElementById('sinoPainel').getBoundingClientRect();
    return r.top >= s.bottom - 1 && r.right <= innerWidth && r.width <= 400 && r.left > innerWidth / 2;
  }));
  await p.keyboard.press('Escape');
  igual('   Esc fecha', await p.evaluate(() => document.getElementById('sinoPainel').hidden), true);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Banco sem o 54 (o SQL não foi colado)');
{
  const { ctx, p } = await abrirPainel(390, async c => c.route('**/rpc/sino_do_painel', r => r.fulfill({ status: 404,
    headers: { 'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'PGRST202', message: 'Could not find the function public.sino_do_painel(p_salao) in the schema cache' }) })));
  await p.waitForTimeout(2500);
  igual('o sino fica escondido, e o painel segue', await p.evaluate(() =>
    [getComputedStyle(document.getElementById('btSino')).display, typeof telaAtual]), ['none', 'string']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. Tela estreita (320px): o topo cabe com o sino');
{
  const { ctx, p } = await abrirPainel(320);
  await p.waitForFunction(() => getComputedStyle(document.getElementById('btSino')).display !== 'none', null, { timeout: 15000 }).catch(() => {});
  verdade('o sino, a Ajuda e o menu no topo, sem passar da tela', await p.evaluate(() => {
    const t = document.querySelector('.palco > .topo').getBoundingClientRect();
    const a = document.getElementById('btAjuda').getBoundingClientRect(), s = document.getElementById('btSino').getBoundingClientRect();
    return s.width > 0 && a.right <= innerWidth + 1 && document.documentElement.scrollWidth <= innerWidth + 1 && t.height < 80;
  }), await p.evaluate(() => JSON.stringify({ w: innerWidth, sw: document.documentElement.scrollWidth,
    a: document.getElementById('btAjuda').getBoundingClientRect().right })));
  await ctx.close();
}

// Os avisos deste teste saem do ar: a bancada é dividida com os outros testes.
await banco.query(`update public.avisos_plataforma set arquivado_em = now()
  where titulo like 'Novidade: o sino %' or titulo like 'Só para o seu salão %'`);

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
