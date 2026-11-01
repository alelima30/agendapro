/* ===========================================================================
   AgendaPro — "Continuar com o Google": o link da cliente, o painel e o
   cadastro do dono

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/google-tela.test.mjs

   A bancada não tem Google. O que se mede é o que é NOSSO: o botão leva ao
   endereço certo do Supabase (com a volta certa), e a volta — que chega com
   a sessão no #fragmento, igual à do e-mail — é bem tratada. A conta "do
   Google" aqui é uma conta criada só com nome e e-mail, que é exatamente o
   que o Google entrega.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. no link: o botão na tela de conta leva ao Google pelo Supabase, com a
        volta para o salão;
     2. a volta sem WhatsApp abre "Falta pouco": pede WhatsApp e aniversário,
        confere, grava, e a ficha nasce no salão com os dois;
     3. a ficha do balcão (mesmo WhatsApp e primeiro nome) é LIGADA, sem
        duplicar; o WhatsApp de outra conta é recusado com a frase certa;
     4. "Agora não" volta para a capa;
     5. no painel: o botão em Entrar leva ao Google com a volta para Entrar;
     6. no cadastro do dono, logado pelo Google: some e-mail e senha, o nome
        vem pronto, e o salão nasce com o WhatsApp no perfil;
     7. nenhum erro de JavaScript.
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

const banco = new pgLib.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const linha = async (q, v) => (await banco.query(q, v)).rows[0];

const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const n8 = String(Date.now() % 100000000).padStart(8, '0');
const tel = d => '51' + d + n8.slice(1);
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;

const dona = aba();
await dona.criarConta({ email:`gg-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Google ' + m,
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
// A ficha do balcão da Helena, sem conta.
await banco.query(`insert into public.clientes (salao_id, nome, telefone) values ($1, 'Helena', $2)`, [SALAO, tel('82')]);
// Quem já tem conta com um WhatsApp.
const outra = aba();
await outra.criarConta({ email:`outra-${m}@t.com`, senha:'senhaboa123', nome:'Outra Pessoa', telefone:'+55' + tel('83') });

// "Conta do Google": só nome e e-mail, sem WhatsApp.
async function contaGoogle(nome, email){
  const d = aba();
  await d.criarConta({ email, senha:'x' + Math.random().toString(36).slice(2) + 'Aa1!', nome });
  return d.sessao();
}
const fragmento = s => '#access_token=' + s.token + '&refresh_token=' + (s.refresh || '')
  + '&expires_in=3600&token_type=bearer&provider_token=pt';

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
/* O que o Supabase responde em /auth/v1/settings — é por ele que as telas
   sabem se o Google está ligado. `google`: true (ligado), false (desligado,
   o padrão do Supabase, que é o que a bancada responde) ou 'falha' (o
   endereço dá erro — na dúvida, a tela não mostra o botão). */
async function pagina(url, largura = 390, google = true){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:880 }, isMobile:true, hasTouch:true,
    serviceWorkers: 'block' });
  if(google === 'falha'){
    await ctx.route('**/auth/v1/settings', r => r.fulfill({ status: 503,
      headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' }, body: 'fora do ar' }));
  }else if(google === true){
    await ctx.route('**/auth/v1/settings', r => r.fulfill({ status: 200,
      headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*' },
      json: { external: { email: true, google: true }, disable_signup: false } }));
  }
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.accept());
  const pedidos = [];
  p.on('request', r => { if(/\/auth\/v1\/authorize/.test(r.url())) pedidos.push(decodeURIComponent(r.url())); });
  await p.goto(BASE + '/' + url);
  return { p, ctx, pedidos };
}
const esperarTela = (p, t) => p.waitForFunction(x => typeof tela !== 'undefined' && tela === x, t, { timeout: 15000 });
const aviso = p => p.evaluate(() => (document.getElementById('avisoCompletar') || {}).innerText || '');

/* ══════════════════════════════════════════════════════════════════════════ */
secao('0. Com o Google DESLIGADO no Supabase, o botão não aparece (nada quebra)');
for(const [rotulo, google] of [['desligado (o padrão do Supabase)', false], ['Supabase com erro', 'falha']]){
  const a = await pagina('agendar.html?salao=' + SLUG, 390, google);
  await esperarTela(a.p, 'capa'); await a.p.waitForTimeout(300);
  await a.p.evaluate(() => abrirConta('criar')); await a.p.waitForTimeout(600);
  const noLink = await a.p.isVisible('#btGoogle');
  const naoPede = await a.p.isVisible('#cNome');
  await a.ctx.close();
  const e = await pagina('entrar.html', 1100, google);
  await e.p.waitForSelector('#fEmail, input[type=email]', { timeout: 15000 }); await e.p.waitForTimeout(800);
  const noPainel = await e.p.isVisible('#btGoogle');
  await e.ctx.close();
  const c = await pagina('criar.html', 1100, google);
  await c.p.waitForSelector('#fEmail', { state: 'visible', timeout: 15000 }); await c.p.waitForTimeout(800);
  const noCriar = await c.p.isVisible('#btGoogle');
  await c.ctx.close();
  igual(rotulo + ': sem botão no link, no Entrar e no Criar conta; e-mail e senha continuam',
    [noLink, noPainel, noCriar, naoPede], [false, false, false, true]);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. No link: o botão leva ao Google, com a volta para o salão');
{
  const { p, ctx, pedidos } = await pagina('agendar.html?salao=' + SLUG);
  await esperarTela(p, 'capa'); await p.waitForTimeout(500);
  await p.evaluate(() => abrirConta('criar'));
  await p.waitForSelector('#btGoogle', { state: 'visible', timeout: 5000 }).catch(() => {});
  verdade('com o Google ligado, o botão "Continuar com o Google" aparece na tela de conta', await p.isVisible('#btGoogle'));
  igual('com "ou com e-mail e senha" logo abaixo', await p.textContent('#caixaGoogle .ou-linha'), 'ou com e-mail e senha');
  await p.click('#btGoogle'); await p.waitForTimeout(800);
  verdade('vai ao Supabase com provider=google e a volta para ESTE salão',
    pedidos.length >= 1 && /\/auth\/v1\/authorize\?provider=google&redirect_to=.*agendar\.html\?salao=/.test(pedidos[0])
    && pedidos[0].includes('salao=' + SLUG + '&conta=google'), pedidos.join(' | '));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. A volta sem WhatsApp: "Falta pouco", e a ficha nasce com os dois');
{
  const s = await contaGoogle('Gabriela Prado', `gabi-${m}@gmail.com`);
  const { p, ctx } = await pagina('agendar.html?salao=' + SLUG + '&conta=google' + fragmento(s));
  await esperarTela(p, 'completar');
  igual('abre "Falta pouco", com Continuar e Agora não', await p.evaluate(() =>
    [document.querySelector('#p-completar h2').textContent, document.getElementById('btPrincipal').textContent.trim(),
     document.getElementById('btSecundario').textContent.trim(), location.hash, location.search]),
    ['Falta pouco', 'Continuar', 'Agora não', '', '?salao=' + SLUG]);
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  verdade('sem WhatsApp, diz o que falta', /Falta o WhatsApp com DDD/.test(await aviso(p)), await aviso(p));
  await p.fill('#cpTel', masc(tel('81')));
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  verdade('sem aniversário, diz o que falta', /Falta o seu aniversário/.test(await aviso(p)), await aviso(p));
  await p.fill('#cpNasc', '1993-08-15');
  await p.click('#btPrincipal');
  await esperarTela(p, 'capa').catch(() => {});
  await p.waitForTimeout(800);
  igual('salvo: volta para a capa', await p.evaluate(() => tela), 'capa');
  const f = await linha(`select c.nome, c.telefone, c.nascimento::text n, c.pelo_link, c.perfil_id is not null as conta,
      (select telefone from public.perfis where id = c.perfil_id) pt
    from public.clientes c where c.salao_id = $1 and c.nome = 'Gabriela Prado'`, [SALAO]);
  igual('a ficha nasce com o nome do Google, o WhatsApp e o aniversário, ligada à conta',
    f && [f.telefone, f.n, f.pelo_link, f.conta, f.pt], [tel('81'), '1993-08-15', true, true, '+55' + tel('81')]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. A ficha do balcão é ligada, sem duplicar; o WhatsApp de outra conta, não');
{
  const s = await contaGoogle('Helena Costa', `helena-${m}@gmail.com`);
  const { p, ctx } = await pagina('agendar.html?salao=' + SLUG + '&conta=google' + fragmento(s));
  await esperarTela(p, 'completar');
  await p.fill('#cpTel', masc(tel('83'))); await p.fill('#cpNasc', '1980-02-03');
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  verdade('o WhatsApp de outra conta: recusa, e diz para entrar com ela',
    /Este WhatsApp já está em outra conta/.test(await aviso(p)) && await p.evaluate(() => tela === 'completar'), await aviso(p));
  await p.fill('#cpTel', masc(tel('82')));
  await p.click('#btPrincipal');
  await esperarTela(p, 'capa').catch(() => {});
  await p.waitForTimeout(800);
  const hs = (await banco.query(`select nome, perfil_id is not null as conta, nascimento::text n from public.clientes
    where salao_id = $1 and telefone = $2`, [SALAO, tel('82')])).rows;
  igual('a ficha "Helena" do balcão foi ligada (uma só), e ganhou o aniversário',
    hs.map(x => [x.nome, x.conta, x.n]), [['Helena', true, '1980-02-03']]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. "Agora não" volta para a capa');
{
  const s = await contaGoogle('Iara Lopes', `iara-${m}@gmail.com`);
  const { p, ctx } = await pagina('agendar.html?salao=' + SLUG + '&conta=google' + fragmento(s));
  await esperarTela(p, 'completar');
  await p.click('#btSecundario'); await p.waitForTimeout(400);
  igual('na capa, ainda logada', await p.evaluate(() => [tela, !!(Dados.sessaoAtual && Dados.sessaoAtual())]), ['capa', true]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. No painel: o botão em Entrar');
{
  const { p, ctx, pedidos } = await pagina('entrar.html', 1100);
  await p.waitForSelector('#btGoogle', { state: 'visible', timeout: 15000 });
  igual('"Continuar com o Google", e "ou com e-mail e senha"', [(await p.textContent('#btGoogle')).trim(), (await p.textContent('#caixaGoogle .ou')).trim()],
    ['GContinuar com o Google', 'ou com e-mail e senha']);
  await p.click('#btGoogle'); await p.waitForTimeout(800);
  verdade('vai ao Supabase com provider=google e a volta para Entrar',
    pedidos.length >= 1 && /provider=google&redirect_to=.*\/entrar\.html$/.test(pedidos[0]), pedidos.join(' | '));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. O dono que entra com o Google cria o salão sem e-mail e senha');
{
  const s = await contaGoogle('Karla Dona', `karla-${m}@gmail.com`);
  const { p, ctx } = await pagina('criar.html' + fragmento(s), 1100);
  await p.waitForSelector('#avisoGeral .aviso', { timeout: 15000 });
  igual('diz com que conta entrou; e-mail e senha somem; o nome vem pronto', await p.evaluate(() => [
    /Você entrou como karla-/.test(document.getElementById('avisoGeral').innerText),
    !!document.getElementById('fEmail').offsetParent, !!document.getElementById('fSenha').offsetParent,
    document.getElementById('fNome').value, location.hash]), [true, false, false, 'Karla Dona', '']);
  await p.click('button.grande:has-text("Continuar")'); await p.waitForTimeout(500);
  await p.fill('#fSalao', 'Studio Karla ' + m); await p.dispatchEvent('#fSalao', 'input');
  await p.selectOption('#fTipo', { index: 1 });
  await p.fill('#fZap', masc(tel('84'))); await p.dispatchEvent('#fZap', 'input');
  await p.click('#btCriar');
  await p.waitForFunction(() => /link/i.test((document.getElementById('linkFinal') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(800);
  const r = await linha(`select s.nome, v.papel, pf.telefone from public.vinculos v
      join public.saloes s on s.id = v.salao_id join public.perfis pf on pf.id = v.perfil_id
     where pf.email = $1`, [`karla-${m}@gmail.com`]);
  igual('o salão nasceu com ela de dona, e o WhatsApp foi para o perfil',
    r && [r.nome, r.papel, r.telefone], ['Studio Karla ' + m, 'dono', '+55' + tel('84')]);
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
