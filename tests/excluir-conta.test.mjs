/* ===========================================================================
   AgendaPro — Excluir conta: a dona apaga tudo na hora, e só o que é dela

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/excluir-conta.test.mjs

   O pedido: "colocar um botão excluir conta é necessário também" — e, entre
   guardar por um tempo ou apagar, "apaga tudo na hora".

   O perigo de um botão desses não é ele não apagar: é apagar DEMAIS. Um
   salão de outra dona, a ficha que o salão fez da cliente, o histórico de
   quem já saiu da equipe. Por isso metade deste arquivo confere o que FICA.

     1. o banco recusa sem login, sem a palavra EXCLUIR, e com cartão ligado;
     2. a dona única apaga o salão inteiro — com atendimento concluído,
        comanda fechada e pagamento, que têm gatilho que recusa mexer;
     3. o salão que tem outra dona fica, e o que a pessoa fez nele perde só o
        nome; equipe e cliente perdem só o login;
     4. a tela de Sua conta mostra o nome do salão, só acende o botão com a
        palavra, apaga as fotos e volta para o Entrar dizendo que excluiu;
     5. no link, a cliente exclui a dela — e a dona que entra pelo link é
        mandada para o painel em vez de apagar o salão sem ver qual.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pg from './pg.mjs';

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
const recusa = async f => { try{ await f(); return null; }catch(e){ return e.message || String(e); } };

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: Number(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const q = async (sql, args) => (await banco.query(sql, args)).rows;
const um = async (sql, args) => (await q(sql, args))[0];

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
let tel = 900000000 + (Date.now() % 50000000);
async function pessoa(nome){
  const d = aba();
  const email = `ex-${nome.toLowerCase()}-${m}@teste.com`;
  await d.criarConta({ email, senha:'minhasenhaboa', nome, telefone:'+5511' + (tel++) });
  d.email = email;
  d.id = (await um(`select id from auth.users where email = $1`, [email])).id;
  return d;
}
async function salaoDe(d, nome){
  const cr = await d.chamar('criar_salao', { p_nome_salao: nome + ' ' + m,
    p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
  const id = cr[0].salao_id;
  await q(`update public.assinaturas set plano='equipe', status='ativa',
             vence_em = current_date + 30 where salao_id = $1`, [id]);
  return { id, slug: cr[0].slug, nome: nome + ' ' + m };
}
const FOTO = new Blob([Buffer.from('R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==', 'base64')],
  { type:'image/gif' });

/* ══════════════════════════════════════════════════════════════════════════
   O CENÁRIO
     Ana  — dona ÚNICA do Salão Ana (com atendimento concluído, comanda
            fechada, pagamento, produto e foto) e dona JUNTO com a Bruna do
            Salão Bruna;
     Carla — da equipe do Salão Bruna, com ficha de profissional;
     Dani  — cliente do Salão Bruna, com login ligado à ficha.
   ══════════════════════════════════════════════════════════════════════════ */
const ana = await pessoa('Ana'), bruna = await pessoa('Bruna'),
      carla = await pessoa('Carla'), dani = await pessoa('Dani');
const A = await salaoDe(ana, 'Salão Ana');
const B = await salaoDe(bruna, 'Salão Bruna');

await ana.atualizar('saloes', A.id, { cfg:{ usaComanda:false, diasLiberados:30 } });
const profA = (await ana.lista('profissionais', { salaoId: A.id }))[0];
const svA = await ana.inserir('servicos', { salaoId: A.id, nome:'Corte', duracaoMin:60,
  intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });
const cliA = await ana.inserir('clientes', { salaoId: A.id, nome:'Rosa Lima', telefone:'11977770000' });
await ana.inserir('produtos', { salaoId: A.id, nome:'Shampoo', preco:30, custo:10, estoque:5, ativo:true });
const amanha = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
async function marcar(dono, salao, cli, prof, sv, hora){
  const ini = amanha + 'T' + hora + ':00Z', fim = amanha + 'T' + String(Number(hora.slice(0, 2)) + 1).padStart(2, '0') + hora.slice(2) + ':00Z';
  const a = await dono.inserir('agendamentos', { salaoId: salao, clienteId: cli, profissionalId: prof,
    inicio: ini, fim, status:'confirmado', origem:'recepcao', valorPrevisto: 80 });
  await dono.inserir('agendamento_servicos', { agendamentoId: a.id, servicoId: sv, ordem:1,
    duracaoMin:60, preco:80, comissaoPct:0 });
  return a;
}
for(let i = 0; i <= 6; i++) await ana.inserir('jornadas', { profissionalId: profA.id, diaSemana:i, inicio:'00:00', fim:'23:59' });
const ag1 = await marcar(ana, A.id, cliA.id, profA.id, svA.id, '13:00');
await ana.atualizar('agendamentos', ag1.id, { status:'concluido' });
await marcar(ana, A.id, cliA.id, profA.id, svA.id, '15:00');
const urlLogo = await ana.enviarImagem(A.id, 'logo.gif', FOTO);
await ana.atualizar('saloes', A.id, { logo: urlLogo });
await ana.enviarImagem(A.id, 'esquecida.gif', FOTO);      // trocada e esquecida: só a listagem acha
const fechadas = await um(`select count(*)::int n from public.comandas where salao_id = $1 and status = 'fechada'`, [A.id]);
verdade('o Salão Ana tem atendimento concluído com comanda FECHADA (a do gatilho que recusa mexer)',
  fechadas.n >= 1, JSON.stringify(fechadas));

// Salão Bruna: a Ana é dona junto; a Carla é da equipe; a Dani é cliente com login.
await q(`insert into public.vinculos (perfil_id, salao_id, papel, status) values ($1, $2, 'dono', 'ativo')`, [ana.id, B.id]);
await q(`insert into public.vinculos (perfil_id, salao_id, papel, status) values ($1, $2, 'profissional', 'ativo')`, [carla.id, B.id]);
await q(`insert into public.vinculos (perfil_id, salao_id, papel, status) values ($1, $2, 'cliente', 'ativo')`, [dani.id, B.id]);
const profCarla = (await q(`insert into public.profissionais (salao_id, nome, perfil_id, ativo)
  values ($1, 'Carla Dias', $2, true) returning id`, [B.id, carla.id]))[0];
const fichaDani = (await q(`insert into public.clientes (salao_id, nome, telefone, perfil_id)
  values ($1, 'Dani Rocha', '11966660000', $2) returning id`, [B.id, dani.id]))[0];
const profB = (await bruna.lista('profissionais', { salaoId: B.id }))[0];
for(let i = 0; i <= 6; i++) await bruna.inserir('jornadas', { profissionalId: profB.id, diaSemana:i, inicio:'00:00', fim:'23:59' });
const svB = await bruna.inserir('servicos', { salaoId: B.id, nome:'Escova', duracaoMin:60,
  intervaloMin:0, preco:80, ativo:true, aceitaOnline:true });
const agB = await marcar(bruna, B.id, fichaDani.id, profB.id, svB.id, '13:00');
await q(`update public.agendamentos set criado_por = $1 where id = $2`, [ana.id, agB.id]);
ok('cenário montado: Ana (dona única de um, dona junto de outro), Bruna, Carla da equipe, Dani cliente');

/* ══════════════════════════════════════════════════════════════════════════
   1 — O BANCO RECUSA O QUE NÃO PODE
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. As recusas');
const anonimo = aba();
verdade('sem login, a função nem responde', !!(await recusa(() =>
  anonimo.chamar('excluir_minha_conta', { p_confirmacao:'EXCLUIR' }))));

const previa = await ana.chamar('o_que_excluir_apaga');
igual('a Ana vê o que vai acontecer: o Salão Ana sai inteiro, o da Bruna fica',
  (previa || []).map(x => [x.nome, x.apaga]).sort(), [[A.nome, true], [B.nome, false]].sort());
const daDani = await dani.chamar('o_que_excluir_apaga');
igual('o vínculo de CLIENTE não conta como estabelecimento da Dani', daDani, []);

const semPalavra = await recusa(() => ana.chamar('excluir_minha_conta', { p_confirmacao:'sim' }));
verdade('sem a palavra EXCLUIR, recusa e diz qual é', /digite EXCLUIR/.test(semPalavra || ''), semPalavra);

await q(`update public.assinaturas set mp_preapproval = 'pre_teste' where salao_id = $1`, [A.id]);
const comCartao = await recusa(() => ana.chamar('excluir_minha_conta', { p_confirmacao:'EXCLUIR' }));
verdade('com a renovação no cartão ligada, recusa — o cartão seguiria sendo cobrado',
  /renovação automática/.test(comCartao || ''), comCartao);
await q(`update public.assinaturas set mp_preapproval = null where salao_id = $1`, [A.id]);
igual('e nada foi apagado nas recusas', Number((await um(`select count(*) n from public.saloes where id = $1`, [A.id])).n), 1);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A DONA ÚNICA APAGA O SALÃO INTEIRO
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. Ana exclui a conta');
let r;
const erro = await recusa(async () => { r = await ana.chamar('excluir_minha_conta', { p_confirmacao:' excluir ' }); });
igual('aceita "excluir" minúsculo e com espaço, e apaga um salão', erro || (r && r.saloes_apagados), 1);
igual('o Salão Ana não existe mais', Number((await um(`select count(*) n from public.saloes where id = $1`, [A.id])).n), 0);
const tabelas = await q(`select table_name from information_schema.columns
  where table_schema = 'public' and column_name = 'salao_id'
    and table_name in (select table_name from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE')`);
const sobras = [];
for(const { table_name } of tabelas){
  const n = Number((await um(`select count(*) n from public.${table_name} where salao_id = $1`, [A.id])).n);
  if(n) sobras.push(table_name + ':' + n);
}
igual(`nenhuma linha do Salão Ana sobrou em nenhuma das ${tabelas.length} tabelas`, sobras, []);
igual('o login da Ana sumiu (auth.users e perfis)',
  [Number((await um(`select count(*) n from auth.users where id = $1`, [ana.id])).n),
   Number((await um(`select count(*) n from public.perfis where id = $1`, [ana.id])).n)], [0, 0]);
verdade('e entrar com o e-mail e a senha dela não funciona mais',
  !!(await recusa(() => aba().entrar({ email: ana.email, senha:'minhasenhaboa' }))));

/* ══════════════════════════════════════════════════════════════════════════
   3 — O QUE FICA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. O que não era só dela continua');
igual('o Salão Bruna continua', Number((await um(`select count(*) n from public.saloes where id = $1`, [B.id])).n), 1);
igual('com a Bruna dona, e sem a Ana', (await q(`select perfil_id from public.vinculos where salao_id = $1 and papel = 'dono'`, [B.id]))
  .map(x => x.perfil_id), [bruna.id]);
const agBdepois = await um(`select id, criado_por from public.agendamentos where id = $1`, [agB.id]);
igual('o horário que a Ana marcou lá continua, só sem o nome de quem marcou', [!!agBdepois, agBdepois && agBdepois.criado_por], [true, null]);

const rc = await carla.chamar('excluir_minha_conta', { p_confirmacao:'EXCLUIR' });
igual('Carla, da equipe, exclui a dela sem apagar salão nenhum', rc && rc.saloes_apagados, 0);
const fichaC = await um(`select id, perfil_id from public.profissionais where id = $1`, [profCarla.id]);
igual('a ficha de profissional dela fica no salão (é histórico), desligada da conta', [!!fichaC, fichaC && fichaC.perfil_id], [true, null]);
igual('e o Salão Bruna segue inteiro', Number((await um(`select count(*) n from public.saloes where id = $1`, [B.id])).n), 1);

const rd = await dani.chamar('excluir_minha_conta', { p_confirmacao:'EXCLUIR' });
igual('Dani, cliente, exclui a dela', rd && rd.saloes_apagados, 0);
const fichaD = await um(`select id, perfil_id from public.clientes where id = $1`, [fichaDani.id]);
igual('a ficha que o salão fez dela fica, desligada da conta', [!!fichaD, fichaD && fichaD.perfil_id], [true, null]);

/* ══════════════════════════════════════════════════════════════════════════
   4 — A TELA DE SUA CONTA
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. No painel: Meu negócio → Dados → Sua conta');
const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const eva = await pessoa('Eva');
const E = await salaoDe(eva, 'Studio Eva');
const urlE = await eva.enviarImagem(E.id, 'logo.gif', FOTO);
await eva.atualizar('saloes', E.id, { logo: urlE });
await eva.enviarImagem(E.id, 'galeria-1.gif', FOTO);
{
  const p = await (await nav.newContext({ viewport:{ width:1280, height:900 } })).newPage();
  p.on('pageerror', e => erros.push(e.message));
  // A sessão entra só no painel: o script roda em TODA página aberta, e no
  // Entrar ele poria de volta a sessão que a exclusão acabou de limpar.
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    if(location.pathname.endsWith('app.html')) localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, eva.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1000);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(400);
  await p.evaluate(() => trocarAbaSalao('dados'));
  await p.waitForSelector('#btExcluirConta', { timeout: 10000 });
  verdade('o botão "Excluir minha conta" está em Sua conta', await p.isVisible('#btExcluirConta'));
  await p.click('#btExcluirConta');
  await p.waitForSelector('#palavraExcluir', { timeout: 10000 });
  const janela = await p.evaluate(() => document.getElementById('modalCorpo').textContent.replace(/\s+/g, ' '));
  verdade('a janela diz o nome do salão que será apagado', janela.includes('Studio Eva'), janela);
  verdade('e diz que não tem volta', /não tem volta/.test(janela), janela);
  const botao = () => p.evaluate(() => { const b = [...document.querySelectorAll('#modalPe button')]
    .find(x => /Excluir para sempre/.test(x.textContent)); return b ? b.disabled : null; });
  igual('o "Excluir para sempre" nasce apagado', await botao(), true);
  await p.fill('#palavraExcluir', 'exclu');
  igual('com a palavra pela metade, continua apagado', await botao(), true);
  await p.fill('#palavraExcluir', 'excluir');
  igual('com EXCLUIR (minúsculo serve), acende', await botao(), false);
  await Promise.all([
    p.waitForURL(/entrar\.html/, { timeout: 20000 }),
    p.locator('#modalPe button', { hasText: 'Excluir para sempre' }).click(),
  ]);
  await p.waitForTimeout(800);
  const recado = await p.evaluate(() => (document.getElementById('recado') || {}).textContent || '');
  verdade('volta para o Entrar dizendo que a conta foi excluída', /Sua conta foi excluída/.test(recado), recado);
  igual('o Studio Eva não existe mais', Number((await um(`select count(*) n from public.saloes where id = $1`, [E.id])).n), 0);
  const fotos = await (await fetch(BASE + '/storage/v1/object/list/salao', { method:'POST',
    headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ prefix: E.id }) })).json();
  igual('e a pasta de fotos dele ficou vazia — até a foto que nenhum cadastro apontava', fotos, []);
  igual('a sessão deste navegador foi limpa', await p.evaluate(() => localStorage.getItem('agendapro.sessao')), null);
  await p.context().close();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — NO LINK
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. No link: Meus horários');
async function noLink(d){
  const p = await (await nav.newContext({ viewport:{ width:412, height:900 }, isMobile:true, hasTouch:true })).newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.dialogos = [];
  p.on('dialog', async dg => { p.dialogos.push(dg.message());
    if(dg.type() === 'prompt') await dg.accept(p.resposta || ''); else await dg.accept(); });
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, d.sessao()]);
  await p.goto(BASE + '/agendar.html?salao=' + B.slug);
  await p.waitForFunction(() => typeof irPara === 'function' && typeof salao !== 'undefined' && salao, null, { timeout: 15000 });
  await p.waitForTimeout(800);
  await p.evaluate(() => { irPara('meus'); });
  await p.waitForTimeout(800);
  return p;
}
{
  const fabi = await pessoa('Fabi');
  const fichaF = (await q(`insert into public.clientes (salao_id, nome, telefone, perfil_id)
    values ($1, 'Fabi Melo', '11955550000', $2) returning id`, [B.id, fabi.id]))[0];
  const p = await noLink(fabi);
  verdade('logada, "Excluir minha conta" aparece embaixo do Sair', await p.isVisible('#btExcluirMinhaConta'));
  p.resposta = 'talvez';
  await p.click('#btExcluirMinhaConta');
  await p.waitForTimeout(1200);
  igual('palavra errada: não exclui', Number((await um(`select count(*) n from auth.users where id = $1`, [fabi.id])).n), 1);
  p.resposta = 'EXCLUIR';
  await p.click('#btExcluirMinhaConta');
  await p.waitForTimeout(1800);
  verdade('com EXCLUIR, a conta sai e a tela confirma',
    p.dialogos.some(t => /Sua conta foi excluída/.test(t)), JSON.stringify(p.dialogos));
  igual('o login da Fabi não existe mais', Number((await um(`select count(*) n from auth.users where id = $1`, [fabi.id])).n), 0);
  const ff = await um(`select perfil_id from public.clientes where id = $1`, [fichaF.id]);
  igual('a ficha dela no salão continua, desligada da conta', ff && ff.perfil_id, null);
  igual('e o salão continua', Number((await um(`select count(*) n from public.saloes where id = $1`, [B.id])).n), 1);
  await p.context().close();
}
{
  const p = await noLink(bruna);
  p.resposta = 'EXCLUIR';
  await p.click('#btExcluirMinhaConta');
  await p.waitForTimeout(1200);
  verdade('a DONA que entra pelo link é mandada para o painel, sem apagar nada',
    p.dialogos.some(t => /administrar um estabelecimento.*painel/s.test(t)), JSON.stringify(p.dialogos));
  igual('o salão dela continua', Number((await um(`select count(*) n from public.saloes where id = $1`, [B.id])).n), 1);
  igual('e o login também', Number((await um(`select count(*) n from auth.users where id = $1`, [bruna.id])).n), 1);
  await p.context().close();
}

secao('6. Nada quebrou');
igual('sem erro de JavaScript', erros, []);

await nav.close();
await banco.end();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
