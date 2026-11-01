/* ===========================================================================
   AgendaPro — "Exigir senha para marcar" e o convite para criar a senha

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/senha-marcar.test.mjs

   O pedido: "e se for obrigatório criar a senha? … não posso perder nada
   sobre horários marcados".

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. desligado (o padrão de todo salão): a senha é opcional, e no fim da
        marcação vem o convite "Criar minha senha", com os dados preenchidos;
        criada, a ficha liga na conta e o convite some;
     2. o dono liga em Meu negócio → "Obrigatória", e o banco guarda;
     3. ligado: sem senha a marcação não segue, e diz por quê; com senha,
        segue já logada;
     4. quem já tinha marcado sem conta NÃO PERDE NADA: a ficha e o horário
        continuam, iguais;
     5. nenhum erro de JavaScript.
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
await dona.criarConta({ email:`sl-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Senha ' + m,
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:60,
  intervaloMin:0, preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA } });

// Quem já marcou pelo link SEM conta, antes de o salão exigir senha.
const ROSA = (await linha(`insert into public.clientes (salao_id, nome, telefone, email, nascimento)
  values ($1, 'Rosa Antiga', $2, 'rosa@t.com', '1970-01-02') returning id`, [SALAO, tel('99')])).id;
const AG_ROSA = (await linha(`insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem)
  values ($1, $2, $3, ((now() at time zone 'America/Sao_Paulo')::date + 5 + time '10:00') at time zone 'America/Sao_Paulo',
          ((now() at time zone 'America/Sao_Paulo')::date + 5 + time '11:00') at time zone 'America/Sao_Paulo',
          'confirmado', 'online') returning id`,
  [SALAO, ROSA, prof.id])).id;
await banco.query(`insert into public.agendamento_servicos (agendamento_id, servico_id, ordem, duracao_min, preco, comissao_pct)
  values ($1, $2, 1, 60, 50, 0)`, [AG_ROSA, escova.id]);
const retrato = async () => linha(`select c.nome, c.telefone, c.email, c.nascimento::text n, c.perfil_id,
    (select count(*)::int from public.agendamentos a where a.cliente_id = c.id and a.status = 'confirmado') ags,
    (select to_char(inicio, 'YYYY-MM-DD HH24:MI') from public.agendamentos where id = $2) h
  from public.clientes c where c.id = $1`, [ROSA, AG_ROSA]);
const ANTES = await retrato();

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function aparelho(){
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.accept());
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(800);
  return { p, ctx };
}
async function ateOsDados(p){
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(2500);
  await p.locator('#listaDias .dia:not(.sem)').nth(1).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.waitForTimeout(300);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
}
async function preencher(p, nome, t, email){
  await p.fill('#dNome', nome); await p.fill('#dTel', masc(t));
  await p.fill('#dNasc', '1991-06-07'); await p.fill('#dEmail', email);
}
const avisoDados = p => p.evaluate(() => document.getElementById('avisoDados').innerText.replace(/\s+/g, ' '));
const rotuloSenha = p => p.evaluate(() => document.querySelector('label[for="dSenha"]').textContent.replace(/\s+/g, ' ').trim());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Desligado (o padrão): senha opcional, e o convite no fim');
{
  const v = await (aba()).chamar('vitrine', { p_slug: SLUG });
  igual('a vitrine diz que o salão não exige senha', (v.salao || v[0]?.salao || {}).exigeSenha, false);
  const { p, ctx } = await aparelho();
  await ateOsDados(p);
  igual('o campo diz "(opcional)"', await rotuloSenha(p), 'Crie uma senha (opcional)');
  await preencher(p, 'Bela Convite', tel('81'), `bela-${m}@t.com`);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  igual('sem senha, segue para a conferência', await p.evaluate(() => tela), 'confirmar');
  await p.click('#btPrincipal'); await p.waitForTimeout(3000);
  const conv = await p.evaluate(() => (document.getElementById('convidarSenha') || {}).innerText || '');
  igual('marcado: a tela de "pronto"', await p.evaluate(() => tela), 'pronto');
  verdade('com o botão "Criar minha senha"', /Crie sua senha/.test(conv) && /Criar minha senha/.test(conv), conv);
  await p.click('#convidarSenha button:has-text("Criar minha senha")'); await p.waitForTimeout(400);
  igual('abre o criar conta com os dados já preenchidos', await p.evaluate(() =>
    [tela, document.getElementById('cNome').value, document.getElementById('cEmail').value,
     document.getElementById('cNasc').value]), ['conta', 'Bela Convite', `bela-${m}@t.com`, '1991-06-07']);
  await p.fill('#cSenha', 'senhadabela1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('criada a senha, volta para o "pronto", e o convite some', await p.evaluate(() =>
    [tela, (document.getElementById('convidarSenha') || {}).innerText.trim()]), ['pronto', '']);
  const bela = await linha(`select perfil_id is not null as conta, (select count(*)::int from public.agendamentos a
    where a.cliente_id = c.id) ags from public.clientes c where c.salao_id = $1 and c.nome = 'Bela Convite'`, [SALAO]);
  igual('a ficha dela fica ligada à conta, com o horário que marcou', bela, { conta: true, ags: 1 });
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. O dono liga em Meu negócio');
{
  const ctx = await nav.newContext({ viewport:{ width:1100, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => { erros.push('painel (alerta): ' + d.message()); d.accept(); });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.planos && bd.planos.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForSelector('#reguaSenha button');
  igual('a régua começa em "Opcional"', await p.evaluate(() =>
    [...document.querySelectorAll('#reguaSenha button')].map(b => b.textContent.trim() + (b.classList.contains('on') ? ' ●' : ''))),
    ['Opcional ●', 'Obrigatória']);
  await p.click('#reguaSenha button:has-text("Obrigatória")');
  verdade('e explica que quem já marcou não perde nada', /não perde nada/.test(await p.textContent('#explicaSenha')));
  await p.click('button:has-text("Salvar dados")'); await p.waitForTimeout(2500);
  const cfg = await linha(`select cfg->>'exigeSenha' e, cfg->>'confirmaAuto' c from public.saloes where id = $1`, [SALAO]);
  igual('o banco guarda (e não mexe no resto do cfg)', [cfg.e, cfg.c], ['true', 'true']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Ligado: sem senha não marca; com senha, marca já logada');
{
  const v = await (aba()).chamar('vitrine', { p_slug: SLUG });
  igual('a vitrine passa a dizer que exige', (v.salao || v[0]?.salao || {}).exigeSenha, true);
  const { p, ctx } = await aparelho();
  await ateOsDados(p);
  igual('o campo deixa de dizer "(opcional)"', await rotuloSenha(p), 'Crie uma senha');
  verdade('e diz por quê, e que quem já tem conta entra', /pede uma senha para marcar/.test(
    await p.evaluate(() => document.getElementById('dSenhaPista').textContent)));
  await preencher(p, 'Carla Exigida', tel('82'), `carla-${m}@t.com`);
  await p.click('#btPrincipal'); await p.waitForTimeout(600);
  igual('sem senha, fica nos dados', await p.evaluate(() => tela), 'dados');
  verdade('e diz que o salão pede conta para marcar', /este salão pede conta para marcar/.test(await avisoDados(p)), await avisoDados(p));
  await p.fill('#dSenha', '123');
  await p.click('#btPrincipal'); await p.waitForTimeout(400);
  verdade('senha curta: não manda "deixar em branco"', !/deixe em branco/.test(await avisoDados(p))
    && /8 caracteres/.test(await avisoDados(p)), await avisoDados(p));
  await p.fill('#dSenha', 'senhadacarla1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('com senha: a conta nasce e segue para a conferência, logada', [await p.evaluate(() => tela),
    await p.evaluate(() => !!(Dados.sessaoAtual && Dados.sessaoAtual()))], ['confirmar', true]);
  await p.click('#btPrincipal'); await p.waitForTimeout(3000);
  igual('marcado, e sem convite (ela já tem senha)', await p.evaluate(() =>
    [tela, (document.getElementById('convidarSenha') || {}).innerText.trim()]), ['pronto', '']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Quem já marcou sem conta não perde nada');
igual('a ficha e o horário da Rosa continuam iguais', await retrato(), ANTES);

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
