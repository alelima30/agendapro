/* ===========================================================================
   AgendaPro — o passo a passo pede o WhatsApp de quem atende e a chave Pix

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/passo-zap-pix.test.mjs

   "No passo a passo está todas as informações para o dono preencher?" Faltavam
   duas, achadas ao percorrer o assistente:

     1. O WhatsApp de quem atende. O passo "Sua equipe" pedia só o nome, e o
        dono entrava sem telefone: num salão recém-criado, o aviso de horário
        novo e o lembrete do salão não saíam para ninguém.
     2. A chave Pix. A cliente escolhia "Pix" no link e não tinha onde ver a
        chave para pagar.

   O que se mede:
     1. a regra (funcionamento.js) guarda a chave só com Pix marcado;
     2. no passo da equipe, o do dono vem com o número do cadastro, cada um
        ganha o seu, número curto segura o passo, e tudo vai para o banco;
     3. no passo do pagamento, a chave aparece com Pix marcado e é gravada;
     4. em Meu negócio, a mesma chave, editável — e some com o Pix.
   (O link mostrando a chave com "Copiar" está no forma-pagamento.test.mjs.)
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

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
const sql = q => execSync('psql -At -v ON_ERROR_STOP=1', { input: q, env: { ...process.env,
  PGHOST: process.env.PGHOST || '/tmp', PGPORT: process.env.PGPORT || '5444',
  PGUSER: process.env.PGUSER || 'postgres', PGDATABASE: process.env.PGBANCO || 'app' } }).toString().trim();

/* ══════════════════════════════════════════════════════════════════════════
   1 — A REGRA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · A regra das formas de pagamento');
const caixa = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(RAIZ, 'funcionamento.js'), 'utf8'), caixa);
const F = caixa.window.Funcionamento;
igual('com Pix marcado, a chave é guardada (sem espaço nas pontas)',
  JSON.parse(JSON.stringify(F.pagamentos({ formas: ['pix'], obs: '', pix: '  pix@studio.com.br ' }))),
  { formas: ['pix'], obs: '', pix: 'pix@studio.com.br' });
igual('sem Pix marcado, a chave não fica',
  JSON.parse(JSON.stringify(F.pagamentos({ formas: ['dinheiro'], obs: '', pix: 'pix@studio.com.br' }))),
  { formas: ['dinheiro'], obs: '' });
igual('sem chave, o formato é o de sempre',
  JSON.parse(JSON.stringify(F.pagamentos({ formas: ['pix', 'credito'], obs: 'até 3x' }))),
  { formas: ['pix', 'credito'], obs: 'até 3x' });
verdade('chave comprida é aparada no teto do Banco Central (77)',
  F.pagamentos({ formas: ['pix'], pix: 'x'.repeat(120) }).pix.length === 77);

/* ══════════════════════════════════════════════════════════════════════════
   A BANCADA
   ══════════════════════════════════════════════════════════════════════════ */
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
const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const fim = String(Date.now() % 10000).padStart(4, '0');
const ZAP_DONA = '1198765' + fim;                       // 11 dígitos, sem o 55
const dona = aba();
await dona.criarConta({ email:`zp-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+55' + ZAP_DONA });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Studio Zap ' + m,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
// Plano com lugar para mais gente: o passo da equipe só oferece "Quem mais
// atende?" quando o plano cabe.
sql(`update public.assinaturas set plano='time', status='ativa', vence_em=current_date+30
      where salao_id='${SALAO}'`);
const digitos = t => String(t || '').replace(/\D/g, '');
const telDe = nome => sql(`select coalesce(telefone,'') from public.profissionais
  where salao_id='${SALAO}' and nome='${nome}'`);
const cfgPag = () => JSON.parse(sql(`select coalesce(cfg->'pagamentos','null'::jsonb)::text
  from public.saloes where id='${SALAO}'`));

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
const p = await ctx.newPage();
const erros = [], dialogos = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => { dialogos.push(d.message()); d.accept(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForFunction(() => typeof irPara === 'function' && typeof bd !== 'undefined'
  && bd && Array.isArray(bd.saloes) && bd.profissionais.length, null, { timeout: 20000 });
await p.waitForTimeout(1500);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A EQUIPE
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · Sua equipe, com o WhatsApp de cada um');
await p.evaluate(() => abrirPrimeiroDia(5));
await p.waitForTimeout(600);
const dono = await p.evaluate(() => {
  const el = document.querySelector('.pd-zap');
  return el ? { valor: el.value, visivel: !!el.offsetParent } : null;
});
verdade('a linha do dono já vem com o WhatsApp do cadastro dele',
  dono && dono.visivel && digitos(dono.valor) === ZAP_DONA, JSON.stringify(dono));
igual('mas ainda não está gravado — só ao seguir', telDe('Rita Alves'), '');

await p.fill('#pdEqNome', 'Lucas Prado');
await p.fill('#pdEqZap', '(11) 91234-5678');
await p.click('button:has-text("Adicionar")');
await p.waitForTimeout(2200);
verdade('quem é adicionado já entra com o WhatsApp dele',
  digitos(telDe('Lucas Prado')) === '11912345678', telDe('Lucas Prado'));

dialogos.length = 0;
await p.fill('.pd-zap[data-prof]', '123');
await p.click('#pdProximo');
await p.waitForTimeout(800);
verdade('número curto segura o passo e diz de quem é',
  dialogos.some(x => /Confira o WhatsApp de Rita Alves/.test(x))
  && await p.evaluate(() => pdPasso) === 5, dialogos.join(' | '));

await p.fill('.pd-zap[data-prof]', '(11) 98765-' + fim);
await p.click('#pdProximo');
await p.waitForTimeout(2200);
verdade('seguindo, o WhatsApp do dono vai para o banco (e o aviso de horário novo passa a chegar)',
  digitos(telDe('Rita Alves')) === ZAP_DONA && await p.evaluate(() => pdPasso) === 6, telDe('Rita Alves'));

/* ══════════════════════════════════════════════════════════════════════════
   3 — O PAGAMENTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · Como a cliente paga, com a chave Pix');
await p.evaluate(() => abrirPrimeiroDia(8));
await p.waitForTimeout(600);
const estaPix = () => p.evaluate(() => {
  const c = document.getElementById('pdCampoPix');
  return !!c && getComputedStyle(c).display !== 'none';
});
const pixLigado = await p.evaluate(() => pdFormasAtuais().includes('pix'));
if(pixLigado){ await p.click('.pd-op[data-forma="pix"]'); await p.waitForTimeout(200); }
verdade('sem Pix marcado, o campo da chave não aparece', !(await estaPix()));
await p.click('.pd-op[data-forma="pix"]');
await p.waitForTimeout(200);
verdade('marcou Pix: o campo da chave aparece, sem redesenhar o passo', await estaPix());
await p.fill('#pdPagPix', 'pix@studiozap.com.br');
await p.click('#pdProximo');
await p.waitForTimeout(2200);
const pag = cfgPag();
verdade('seguindo, a chave vai para o banco, junto das formas',
  pag && pag.pix === 'pix@studiozap.com.br' && pag.formas.includes('pix'), JSON.stringify(pag));

/* ══════════════════════════════════════════════════════════════════════════
   4 — MEU NEGÓCIO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4 · Meu negócio: a mesma chave, editável');
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.evaluate(() => { irPara('salao'); trocarAbaSalao('dados'); });
await p.waitForTimeout(800);
const campo = await p.evaluate(() => ({
  visivel: getComputedStyle(document.getElementById('campoPagPix')).display !== 'none',
  valor: document.getElementById('cPagPix').value }));
igual('com Pix marcado, a chave aparece preenchida', campo, { visivel: true, valor: 'pix@studiozap.com.br' });
await p.fill('#cPagPix', '12.345.678/0001-90');
await p.evaluate(() => salvarCadastroSalao());
await p.waitForTimeout(2000);
igual('trocar e salvar grava a chave nova', cfgPag().pix, '12.345.678/0001-90');
await p.evaluate(() => alternarPagamento('pix'));
await p.waitForTimeout(200);
verdade('desmarcar Pix esconde o campo',
  await p.evaluate(() => getComputedStyle(document.getElementById('campoPagPix')).display === 'none'));
await p.evaluate(() => salvarCadastroSalao());
await p.waitForTimeout(2000);
verdade('e salvar sem Pix tira a chave', !('pix' in (cfgPag() || {})), JSON.stringify(cfgPag()));

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
