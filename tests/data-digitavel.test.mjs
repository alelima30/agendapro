/* ===========================================================================
   AgendaPro — o aniversário que se digita (dd/mm/aaaa), com o calendário ao lado

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/data-digitavel.test.mjs

   O dono, no cadastro do link: "quando vou cadastrar aniversário não consigo
   digitar — tenho que conseguir digitar dia, mês e ano, ou colocar através
   da agenda ao lado". `<input type="date">` no Android só abre o seletor.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. no cadastro do link: digitar "04101990" vira "04/10/1990", e o campo
        de data guarda "1990-10-04" (o que o salvar lê);
     2. data que não existe (31/02) ou pela metade: o Continuar diz "Confira
        a data", e não "falta";
     3. escolher pelo calendário escreve no texto; o ícone é o campo de data
        (tocar nele abre o seletor); o que o aparelho lembra aparece escrito;
     4. no painel, a ficha da cliente: digitar e salvar grava a data certa;
        data torta não salva calada;
     5. a 360px nada vaza; nenhum erro de JavaScript.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';
const ESTATICO = process.env.BASE || 'http://127.0.0.1:8099/';

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

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`dd-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:60, intervaloMin:0,
  preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const estado = p => p.evaluate(() => ({ txt: document.getElementById('dNascTxt').value, iso: document.getElementById('dNasc').value }));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 a 3. No cadastro do link');
{
  const ctx = await nav.newContext({ viewport:{ width:360, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(600);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(2000);
  await p.locator('#listaDias .dia:not(.sem)').nth(1).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  igual('chegou ao cadastro', await p.evaluate(() => tela), 'dados');

  const campo = await p.evaluate(() => {
    const t = document.getElementById('dNascTxt');
    return t ? { tipo: t.type, teclado: t.inputMode, dica: t.placeholder, rotulo: t.getAttribute('aria-label') } : null;
  });
  igual('o aniversário é um campo de texto, com teclado de números e a dica dd/mm/aaaa',
    campo, { tipo:'text', teclado:'numeric', dica:'dd/mm/aaaa', rotulo:'Aniversário' });

  await p.click('#dNascTxt'); await p.keyboard.type('04101990'); await p.waitForTimeout(100);
  igual('digitar 04101990: as barras entram sozinhas, e a data fica guardada', await estado(p),
    { txt:'04/10/1990', iso:'1990-10-04' });

  await p.fill('#dNascTxt', ''); await p.click('#dNascTxt'); await p.keyboard.type('31021990');
  igual('31/02 não existe: o texto fica, a data não', await estado(p), { txt:'31/02/1990', iso:'' });
  igual('a conversão sozinha também recusa o que não existe, e aceita o 29/02 de ano bissexto',
    await p.evaluate(() => [Documento.dataDeBr('31/02/1990'), Documento.dataDeBr('29/02/2023'),
      Documento.dataDeBr('29/02/2024'), Documento.dataDeBr('4/10/1990')]), ['', '', '2024-02-29', '']);
  await p.fill('#dNome', 'Maria Teste'); await p.fill('#dTel', '(51) 98888-7777');
  await p.fill('#dEmail', `maria-${m}@t.com`);
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  verdade('Continuar com data torta: "Confira a data", e não "falta"', /Confira a data do aniversário/.test(
    await p.evaluate(() => document.getElementById('avisoDados').innerText)));

  // O calendário: o ícone é o próprio campo de data, por cima.
  const toque = await p.evaluate(() => {
    const ic = document.querySelector('#p-dados .data-ic').getBoundingClientRect();
    const el = document.elementFromPoint(ic.left + ic.width / 2, ic.top + ic.height / 2);
    return el && el.id;
  });
  igual('tocar no ícone do calendário é tocar no campo de data (abre o seletor)', toque, 'dNasc');
  await p.fill('#dNasc', '1985-12-25'); await p.waitForTimeout(100);
  igual('escolher no calendário escreve no texto', await estado(p), { txt:'25/12/1985', iso:'1985-12-25' });
  await p.evaluate(() => { document.getElementById('dNasc').value = '1977-03-09'; });
  igual('e a memória do aparelho (escrita por código) também aparece escrita', (await estado(p)).txt, '09/03/1977');

  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  igual('com a data certa, segue para a conferência', await p.evaluate(() => tela), 'confirmar');
  igual('a 360px nada vaza para o lado', await p.evaluate(() => document.documentElement.scrollWidth - innerWidth <= 0), true);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Na ficha da cliente, no painel');
{
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  const alertas = [];
  p.on('dialog', d => { alertas.push(d.message()); d.dismiss(); });
  await p.goto(ESTATICO + 'app.html?demo=1');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && typeof abrirCliente === 'function', null, { timeout: 15000 });
  await p.waitForTimeout(1000);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); abrirCliente(null); });
  await p.waitForTimeout(300);
  await p.fill('#kNome', 'Dona Cida');
  await p.fill('#kTel', '11977775555');
  await p.click('#kNascTxt'); await p.keyboard.type('1503195');
  await p.evaluate(() => salvarCliente(null)); await p.waitForTimeout(300);
  verdade('ano pela metade: avisa e não salva calado', alertas.some(a => /Confira a data de nascimento/.test(a))
    && await p.evaluate(() => !bd.clientes.some(c => c.nome === 'Dona Cida')), JSON.stringify(alertas));
  await p.click('#kNascTxt'); await p.keyboard.type('8');
  await p.evaluate(() => salvarCliente(null)); await p.waitForTimeout(400);
  igual('15/03/1958 digitado: a ficha grava 1958-03-15', await p.evaluate(() =>
    (bd.clientes.find(c => c.nome === 'Dona Cida') || {}).nascimento), '1958-03-15');
  await p.evaluate(() => abrirCliente(bd.clientes.find(c => c.nome === 'Dona Cida').id)); await p.waitForTimeout(300);
  igual('reabrindo a ficha, a data aparece escrita', await p.evaluate(() => document.getElementById('kNascTxt').value), '15/03/1958');
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
