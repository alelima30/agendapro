/* ===========================================================================
   AgendaPro — o teste grátis é um por pessoa, na tela do cadastro

     bash tests/bancada/subir.sh
     PLAYWRIGHT=.../node_modules/playwright node tests/teste-unico.test.mjs

   O 39_teste_unico.sql decide no banco quem ganha os 7 dias. Aqui se confere
   o que a pessoa LÊ no fim do cadastro — a tela prometia "7 dias com tudo
   liberado" sem perguntar nada a ninguém:

     · primeira vez: o quadro do Teste grátis, com a data que o banco gravou;
     · outra conta com o mesmo WhatsApp (sem excluir a primeira): plano Grátis,
       dito com todas as letras, e nenhuma promessa de 7 dias;
     · excluiu a conta e voltou com o mesmo e-mail: Grátis também;
     · e o "Excluir conta" avisa, antes, que o teste não volta.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok = (m) => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + '\n      ' + d); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const digitar = (p, sel, txt) => p.click(sel).then(() => p.type(sel, txt, { delay: 2 }));

// Cada rodada com e-mail e WhatsApp que ninguém usou: a bancada não é zerada
// entre execuções, e a marca de "já usou" fica — é justamente o ponto.
const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const ZAP = '119' + String(Date.now() % 100000000).padStart(8, '0');
const EMAIL = 'teste-unico-' + marca + '@gmail.com';

async function cadastrar({ nome, email, salao, zap }){
  const ctx = await nav.newContext({ viewport: { width: 430, height: 820 } });
  const p = await ctx.newPage();
  p.erros = [];
  p.on('pageerror', e => p.erros.push(e.message));
  await p.goto(BASE + '/criar.html');
  await p.waitForTimeout(400);
  await digitar(p, '#fNome', nome);
  await digitar(p, '#fEmail', email);
  await digitar(p, '#fSenha', 'minhasenhaboa');
  await p.click('button.grande:has-text("Continuar")');
  await p.waitForTimeout(300);
  await digitar(p, '#fSalao', salao);
  await p.selectOption('#fTipo', { index: 1 });
  await digitar(p, '#fZap', zap);
  await p.click('#btCriar');
  await p.waitForFunction(() => document.getElementById('textoPronto')
    && document.getElementById('textoPronto').textContent.trim().length > 0, null, { timeout: 15000 });
  const quadro = (await p.textContent('#quadroTeste').catch(() => '')) || '';
  const sessao = await p.evaluate(() => Dados.sessaoAtual());
  return { p, ctx, quadro, sessao };
}

console.log('\nA primeira vez');
const a = await cadastrar({ nome: 'Rita Moraes', email: EMAIL, salao: 'Studio Rita ' + marca, zap: ZAP });
verdade('o quadro diz Teste grátis, 7 dias, até quando — e sem cobrança',
  /Teste grátis/.test(a.quadro) && /7 dias/.test(a.quadro) && /\d{2}\/\d{2}\/\d{4}/.test(a.quadro) && /sem cobrança/i.test(a.quadro),
  a.quadro);
/* No dia do SALÃO, como o criar_salao() grava (03_onboarding). Com o dia do
   servidor (UTC), o teste reprovava das 21h à meia-noite de Brasília: o
   banco dizia 28/10 — certo para quem está no Brasil — e o teste esperava 29. */
const esperado = new Date(Date.now() + 7 * 864e5)
  .toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
verdade('com a data que o banco gravou (hoje + 7)', a.quadro.includes(esperado), a.quadro);
verdade('sem erro de JavaScript', a.p.erros.length === 0, a.p.erros.join(' | '));
await a.ctx.close();

console.log('\nOutra conta, o mesmo WhatsApp (sem excluir a primeira)');
const b = await cadastrar({ nome: 'Rita M', email: 'outra-' + marca + '@exemplo.com', salao: 'Rita Beleza ' + marca, zap: ZAP });
verdade('o quadro diz que é o plano Grátis', /plano Grátis/.test(b.quadro), b.quadro);
verdade('e por quê: o teste é um por pessoa, e este WhatsApp ou e-mail já o usou',
  /um por pessoa/.test(b.quadro) && /já o usou/.test(b.quadro), b.quadro);
verdade('sem prometer "7 dias com tudo liberado" nem data de teste',
  !/tudo liberado/.test(b.quadro) && !/\d{2}\/\d{2}\/\d{4}/.test(b.quadro), b.quadro);
verdade('e aponta por onde seguir (Meu plano)', /Meu plano/.test(b.quadro), b.quadro);
verdade('sem erro de JavaScript', b.p.erros.length === 0, b.p.erros.join(' | '));
await b.ctx.close();

console.log('\nExcluir a conta e voltar com o mesmo e-mail');
{
  // O aviso, antes de excluir: no painel da primeira conta.
  const ctx = await nav.newContext({ viewport: { width: 1280, height: 900 } });
  await ctx.addInitScript(([base, s]) => {
    window.AGENDAPRO = { url: base, chave: 'k', ambiente: 'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, a.sessao]);
  const p = await ctx.newPage();
  const erros = [];
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && bd.saloes && salaoAtual, null, { timeout: 15000 });
  await p.evaluate(() => { if(typeof pdFechar === 'function') try{ pdFechar(true); }catch(e){} });
  await p.evaluate(() => abrirExcluirConta());
  await p.waitForTimeout(500);
  const aviso = await p.evaluate(() => (document.getElementById('fundo') || document.body).textContent);
  verdade('o "Excluir conta" avisa que o teste grátis não volta com o mesmo WhatsApp e e-mail',
    /já\s+usaram o teste grátis/.test(aviso.replace(/\s+/g, ' ')) && /plano Grátis/.test(aviso), aviso.slice(0, 400));
  verdade('sem erro de JavaScript no painel', erros.length === 0, erros.join(' | '));
  await ctx.close();
}
const r = await fetch(BASE + '/rest/v1/rpc/excluir_minha_conta', { method: 'POST',
  headers: { apikey: 'k', Authorization: 'Bearer ' + a.sessao.token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ p_confirmacao: 'EXCLUIR' }) });
verdade('a primeira conta foi excluída', r.ok, r.status + ' ' + await r.text());

// O mesmo e-mail, com pontos e etiqueta (o Gmail entrega na mesma caixa), e
// um WhatsApp que ninguém usou.
const zapNovo = '118' + String((Date.now() + 7) % 100000000).padStart(8, '0');
const emailVariado = EMAIL.replace('teste-unico-', 'teste.unico-').replace('@', '+volta@');
const c = await cadastrar({ nome: 'Rita Moraes', email: emailVariado, salao: 'Studio Rita de Novo ' + marca, zap: zapNovo });
verdade('voltou com o mesmo Gmail escrito de outro jeito: plano Grátis', /plano Grátis/.test(c.quadro), c.quadro);
verdade('sem erro de JavaScript', c.p.erros.length === 0, c.p.erros.join(' | '));
await c.ctx.close();

await nav.close();
console.log(`\n${passou} ok, ${falhou} falha(s)`);
process.exit(falhou ? 1 : 0);
