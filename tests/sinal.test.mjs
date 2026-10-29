/* ===========================================================================
   AgendaPro — o sinal por Pix, do ajuste do dono à confirmação

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/sinal.test.mjs

   "Como fazer para colocar sinal?" — o caminho do Pix com a confirmação do
   salão. O banco tem o tests/sinal.test.sql. Aqui, as telas:

     1. Meu negócio: a seção do sinal aparece com Pix marcado, e grava;
     2. o link avisa o sinal antes de marcar;
     3. marcado, a tela diz "Falta só o sinal!", com o valor do banco, a chave
        com Copiar, quem recebe, o prazo, a regra e o comprovante pelo
        WhatsApp — e o horário fica pendente;
     4. "Meus horários" mostra o que falta e "Como pagar o sinal";
     5. o painel mostra o sinal em "A confirmar", e "Recebi o sinal" confirma
        e marca o sinal como pago;
     6. POR SERVIÇO: o dono põe a porcentagem em cada procedimento; no link,
        a Mecha pede o sinal dela e o Corte, sem porcentagem, confirma direto.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
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
const n7 = String(Date.now() % 10000000).padStart(7, '0');
const TEL = '51' + '9' + n7.slice(0, 8).padEnd(8, '1');
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;

const dona = aba();
await dona.criarConta({ email:`sn-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + Math.floor(Math.random() * 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Studio Sinal ' + m, p_tipo:'salao',
  p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte', duracaoMin:30, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Mecha', duracaoMin:60, intervaloMin:0,
  preco:200, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const servicoId = nome => sql(`select id from public.servicos where salao_id='${SALAO}' and nome='${nome}'`);
await dona.atualizar('saloes', SALAO, { cfg: { diasLiberados:30, cor:'#B8356B', confirmaAuto:true,
  pagamentos: { formas: ['pix'], obs: '', pix: 'pix@studiosinal.com.br' } } });
const cfgPag = () => JSON.parse(sql(`select coalesce(cfg->'pagamentos','null'::jsonb)::text
  from public.saloes where id='${SALAO}'`));
const doBanco = () => {
  const l = sql(`select status || '|' || sinal_exigido || '|' || sinal_pago from public.agendamentos
                  where salao_id='${SALAO}' order by criado_em desc limit 1`);
  const [status, exigido, pago] = l.split('|');
  return { status, exigido: Number(exigido), pago: Number(pago) };
};

// O jsonb guarda as chaves noutra ordem: compara pelo conteúdo.
const emOrdem = o => Object.fromEntries(Object.entries(o || {}).sort());

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrirPainel(){
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => d.accept());
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.profissionais.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  return { ctx, p };
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — MEU NEGÓCIO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. Meu negócio: o sinal, junto da chave Pix');
{
  const { ctx, p } = await abrirPainel();
  await p.evaluate(() => { irPara('salao'); trocarAbaSalao('dados'); });
  await p.waitForTimeout(800);
  verdade('com Pix marcado, a seção do sinal aparece', await p.isVisible('#campoSinal'));
  verdade('começa em "Não cobrar", sem campos',
    await p.evaluate(() => document.querySelector('#reguaSinal button.on').textContent.trim() === 'Não cobrar'
      && getComputedStyle(document.getElementById('sinalCampos')).display === 'none'));
  await p.click('#reguaSinal button:has-text("Porcentagem")');
  await p.fill('#cSinalValor', '10');
  await p.selectOption('#cSinalPrazo', '60');
  await p.fill('#cSinalTitular', 'Ju Barbosa');
  await p.fill('#cSinalRegra', 'Devolvo o sinal se cancelar até 24 horas antes.');
  verdade('e explica o que a cliente vai pagar',
    /R\$\s?10,00/.test(await p.textContent('#explicaSinal')), await p.textContent('#explicaSinal'));
  await p.evaluate(() => salvarCadastroSalao());
  await p.waitForTimeout(2200);
  igual('salvar grava o sinal junto da chave',
    emOrdem((cfgPag() || {}).sinal), emOrdem({ tipo:'pct', valor:10, prazoMin:60, titular:'Ju Barbosa',
                              regra:'Devolvo o sinal se cancelar até 24 horas antes.' }));
  await p.evaluate(() => alternarPagamento('pix'));
  await p.waitForTimeout(200);
  verdade('desmarcar Pix esconde o sinal (sem chave não há para onde mandar)',
    !(await p.isVisible('#campoSinal')));
  await p.evaluate(() => alternarPagamento('pix'));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 a 4 — O LINK
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 e 3. O link: avisa antes, e diz como pagar depois');
{
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(700);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao:has-text("Corte")'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  if(await p.evaluate(() => tela === 'quem')){ await p.click('#quemMim'); await p.waitForTimeout(500); }
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(3).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  if(await p.isVisible('#dNome')) await p.fill('#dNome', 'Bia Lima');
  if(await p.isVisible('#dTel')) await p.fill('#dTel', masc(TEL));
  if(await p.isVisible('#dNasc')) await p.fill('#dNasc', '1990-01-01');
  if(await p.isVisible('#dEmail')) await p.fill('#dEmail', `x-${TEL}@t.com`);
  if(await p.evaluate(() => tela === 'dados')){ await p.click('#btPrincipal'); await p.waitForTimeout(1200); }
  igual('chegou na confirmação', await p.evaluate(() => tela), 'confirmar');
  const antes = (await p.textContent('#cfStatus')).replace(/\s+/g, ' ');
  verdade('antes de marcar, avisa: sinal de R$ 8,00 (10% de R$ 80), por Pix, reservado por 1 hora',
    /Sinal de R\$\s?8,00 para garantir o horário/.test(antes) && /10% do valor/.test(antes)
    && /1 hora/.test(antes), antes);
  if(await p.isVisible('#cfPagamento .cf-pag-op[data-forma="pix"]')){
    await p.click('#cfPagamento .cf-pag-op[data-forma="pix"]'); await p.waitForTimeout(300);
  }
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  igual('marcou', await p.evaluate(() => tela), 'pronto');
  igual('o título diz o que falta', (await p.textContent('#p-pronto h2')).trim(), 'Falta só o sinal!');
  const bolha = await p.evaluate(() => {
    const b = document.getElementById('bolhaConfirmacao');
    const z = b.querySelector('a.sinal-zap');
    return { txt: b.innerText.replace(/\s+/g, ' '), zap: z ? decodeURIComponent(z.href) : '',
             copiar: !!b.querySelector('.folha-copiar') };
  });
  verdade('mostra o valor que o banco calculou', /R\$\s?8,00/.test(bolha.txt), bolha.txt);
  verdade('a chave Pix, com Copiar', bolha.txt.includes('pix@studiosinal.com.br') && bolha.copiar, bolha.txt);
  verdade('em nome de quem', /em nome de Ju Barbosa/.test(bolha.txt), bolha.txt);
  verdade('até quando pagar, e que depois o horário é liberado',
    /Pague até .+ volta a ficar livre/.test(bolha.txt), bolha.txt);
  verdade('a regra de cancelamento', /Cancelamento: Devolvo o sinal/.test(bolha.txt), bolha.txt);
  verdade('e o comprovante vai pelo WhatsApp do salão, com a mensagem pronta',
    /wa\.me\/5511981113251\?text=Olá! Paguei o sinal de R\$\s?8,00 do meu horário de /.test(bolha.zap), bolha.zap);
  const b = doBanco();
  igual('no banco: pendente, sinal de 8, nada pago', b, { status:'pendente', exigido:8, pago:0 });

  secao('4. "Meus horários"');
  await p.evaluate(() => abrirMeus());
  await p.waitForTimeout(2500);
  const meus = (await p.textContent('#conteudoMeus').catch(() => '')) || await p.evaluate(() => document.body.innerText);
  verdade('mostra que o sinal ainda falta, com o prazo', /Aguardando o sinal de R\$\s?8,00 · até/.test(meus), meus.slice(0, 400));
  await p.click('button:has-text("Como pagar o sinal")');
  await p.waitForTimeout(600);
  const folha = await p.evaluate(() => (document.querySelector('#folha .folha') || {}).innerText || '');
  verdade('"Como pagar o sinal" abre a chave e o valor de novo',
    /Pagar o sinal/.test(folha) && folha.includes('pix@studiosinal.com.br') && /R\$\s?8,00/.test(folha), folha);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — O PAINEL CONFIRMA
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. O painel: "Recebi o sinal"');
{
  const { ctx, p } = await abrirPainel();
  await p.evaluate(() => { irPara('agenda'); pintar(); });
  await p.waitForTimeout(800);
  const faixa = (await p.textContent('#aConfirmar')).replace(/\s+/g, ' ');
  verdade('"A confirmar" diz que o sinal está sendo esperado', /Aguardando o sinal de R\$\s?8,00 · até/.test(faixa), faixa);
  verdade('e o botão diz o que confirmar quer dizer', /Recebi o sinal/.test(faixa), faixa);
  await p.click('#aConfirmar button:has-text("Recebi o sinal")');
  await p.waitForTimeout(2500);
  igual('confirmou: no banco, confirmado e o sinal pago', doBanco(), { status:'confirmado', exigido:8, pago:8 });
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   6 — POR SERVIÇO
   ══════════════════════════════════════════════════════════════════════════ */
secao('6. Por serviço: cada procedimento com a sua porcentagem');
const MECHA = servicoId('Mecha');
const REGRA = 'Devolvo o sinal se cancelar até 24 horas antes.';
{
  const { ctx, p } = await abrirPainel();
  await p.evaluate(() => { irPara('salao'); trocarAbaSalao('dados'); });
  await p.waitForTimeout(800);
  await p.click('#reguaSinal button:has-text("Por serviço")');
  const t = await p.evaluate(() => ({
    valor: getComputedStyle(document.getElementById('campoSinalValor')).display,
    nomes: [...document.querySelectorAll('#sinalServicos .sinal-servico-nome')]
      .map(e => e.firstChild.textContent.trim()),
    explica: document.getElementById('explicaSinal').textContent }));
  verdade('"Por serviço" troca o valor único pela lista dos serviços',
    t.valor === 'none' && t.nomes.includes('Corte') && t.nomes.includes('Mecha'), JSON.stringify(t));
  verdade('sem nenhuma porcentagem, pede ao menos uma', /pelo menos um serviço/.test(t.explica), t.explica);
  await p.fill(`#sinalServicos input[data-servico="${MECHA}"]`, '30');
  const explica = await p.textContent('#explicaSinal');
  verdade('com a Mecha em 30%, explica que 1 serviço pede sinal', /1 serviço pede sinal/.test(explica), explica);
  await p.evaluate(() => salvarCadastroSalao());
  await p.waitForTimeout(2200);
  igual('salvar grava só a Mecha, e mantém o prazo, quem recebe e a regra',
    emOrdem((cfgPag() || {}).sinal), emOrdem({ tipo:'servicos', servicos:{ [MECHA]:30 }, prazoMin:60,
                                               titular:'Ju Barbosa', regra:REGRA }));
  await ctx.close();
}
{
  const { ctx, p } = await abrirPainel();
  await p.evaluate(() => { irPara('salao'); trocarAbaSalao('dados'); });
  await p.waitForTimeout(800);
  const volta = await p.evaluate(m => ({
    on: document.querySelector('#reguaSinal button.on').textContent.trim(),
    mecha: document.querySelector(`#sinalServicos input[data-servico="${m}"]`).value,
    corte: [...document.querySelectorAll('#sinalServicos input')].filter(i => i.dataset.servico !== m)
      .map(i => i.value) }), MECHA);
  igual('ao voltar, vem "Por serviço", a Mecha com 30 e o Corte em branco',
    volta, { on:'Por serviço', mecha:'30', corte:[''] });
  await ctx.close();
}
async function marcarNoLink(servico, dia, nome, tel){
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(700);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click(`#listaServicos .sv-cartao:has-text("${servico}")`); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  if(await p.evaluate(() => tela === 'quem')){ await p.click('#quemMim'); await p.waitForTimeout(500); }
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(dia).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  if(await p.isVisible('#dNome')) await p.fill('#dNome', nome);
  if(await p.isVisible('#dTel')) await p.fill('#dTel', masc(tel));
  if(await p.isVisible('#dNasc')) await p.fill('#dNasc', '1991-02-02');
  if(await p.isVisible('#dEmail')) await p.fill('#dEmail', `y-${tel}@t.com`);
  if(await p.evaluate(() => tela === 'dados')){ await p.click('#btPrincipal'); await p.waitForTimeout(1200); }
  const antes = (await p.textContent('#cfStatus').catch(() => '')).replace(/\s+/g, ' ');
  if(await p.isVisible('#cfPagamento .cf-pag-op[data-forma="pix"]')){
    await p.click('#cfPagamento .cf-pag-op[data-forma="pix"]'); await p.waitForTimeout(300);
  }
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const r = { tela: await p.evaluate(() => tela), antes,
              titulo: (await p.textContent('#p-pronto h2').catch(() => '')).trim() };
  await ctx.close();
  return r;
}
const TEL2 = '51' + '8' + n7.slice(0, 8).padEnd(8, '2');
{
  const r = await marcarNoLink('Mecha', 4, 'Carla Mecha', TEL2);
  verdade('Mecha (R$ 200, 30%): antes de marcar, avisa o sinal de R$ 60,00',
    /Sinal de R\$\s?60,00 para garantir o horário/.test(r.antes), r.antes);
  igual('marcou, e a tela diz que falta o sinal', [r.tela, r.titulo], ['pronto', 'Falta só o sinal!']);
  igual('no banco: pendente, sinal de 60', doBanco(), { status:'pendente', exigido:60, pago:0 });
}
{
  const r = await marcarNoLink('Corte', 5, 'Carla Mecha', TEL2);
  verdade('Corte (sem porcentagem): não fala em sinal', !/Sinal de/.test(r.antes), r.antes);
  verdade('e marca sem pedir sinal', r.tela === 'pronto' && r.titulo !== 'Falta só o sinal!', JSON.stringify(r));
  igual('no banco: confirmado direto, sem sinal', doBanco(), { status:'confirmado', exigido:0, pago:0 });
}

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
