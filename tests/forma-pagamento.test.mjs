/* ===========================================================================
   AgendaPro — "Como você vai pagar?": a escolha da cliente, do link à agenda

     bash tests/bancada/subir.sh                       (noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/forma-pagamento.test.mjs

   O banco tem o tests/forma_pagamento.test.sql. Aqui, a tela:

   ── O LINK ────────────────────────────────────────────────────────────────
     1. com as formas marcadas pelo salão (Pix e crédito), a confirmação
        pergunta "Como você vai pagar?" só com elas, e com a observação dele;
     2. sem escolher, não marca — e diz o que falta;
     3. escolhida, o resumo mostra, a tela de pronto também, o banco grava, e
        "Meus horários" mostra;
     4. salão que não marcou formas: as quatro, e escolher é opcional;
     5. tudo no pacote (R$ 0): não pergunta.
   ── O PAINEL ──────────────────────────────────────────────────────────────
     6. o cartão do dia mostra "Pix"; o detalhe mostra e deixa trocar; a
        comanda abre com a forma escolhida; o novo agendamento tem o campo.
     7. cores só do tema; nenhum erro de JavaScript.
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
const um = r => Array.isArray(r) ? r[0] : r;
const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const n7 = String(Date.now() % 10000000).padStart(7, '0');
const tel = k => '51' + k + n7;
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;
const diaMais = d => { const x = new Date(); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); };

// ── Dois salões: um que marcou Pix e crédito, outro que não marcou nada ────
async function montarSalao(nome, cfgExtra){
  const dona = aba();
  await dona.criarConta({ email:`fp-${nome}-${m}@teste.com`, senha:'minhasenhaboa',
    nome:'Ju Barbosa', telefone:'+5511' + (900000000 + Math.floor(Math.random() * 89999999)) });
  const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão ' + nome, p_tipo:'salao',
    p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
  const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
  const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
  for(let i = 0; i <= 6; i++)
    await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
  const corte = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte', duracaoMin:30, intervaloMin:0,
    preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
  await dona.atualizar('saloes', SALAO, { cfg: Object.assign({ diasLiberados:30, cor:'#B8356B',
    confirmaAuto:true, usaComanda:true }, cfgExtra) });
  return { dona, SALAO, SLUG, prof, corte };
}
const A = await montarSalao('pix', { pagamentos: { formas: ['pix', 'credito'], obs: 'Parcelamos em até 3x' } });
const B = await montarSalao('livre', {});

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrirLink(slug){
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + slug);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(700);
  return { ctx, p };
}
async function ateConfirmar(p, nome, telefone, nDia){
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao:has-text("Corte")'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  if(await p.evaluate(() => tela === 'quem')){ await p.click('#quemMim'); await p.waitForTimeout(500); }
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(nDia || 3).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  if(await p.isVisible('#dNome')) await p.fill('#dNome', nome);
  if(await p.isVisible('#dTel')) await p.fill('#dTel', masc(telefone));
  if(await p.isVisible('#dNasc')) await p.fill('#dNasc', '1990-01-01');
  if(await p.isVisible('#dEmail')) await p.fill('#dEmail', `x-${telefone}@t.com`);
  if(await p.evaluate(() => tela === 'dados')){ await p.click('#btPrincipal'); await p.waitForTimeout(1200); }
}
const caixa = p => p.evaluate(() => {
  const c = document.querySelector('#cfPagamento .cf-pag');
  return c ? { titulo: c.querySelector('#cfPagTit').textContent, sub: c.querySelector('.cf-pag-txt small').textContent,
               formas: [...c.querySelectorAll('.cf-pag-op')].map(b => b.textContent.trim()),
               obs: (c.querySelector('.cf-pag-obs') || {}).textContent || '' } : null;
});

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 a 3. O salão que aceita Pix e crédito');
const TEL_ANA = tel('71');
let AG_ANA = null;
{
  const { ctx, p } = await abrirLink(A.SLUG);
  await ateConfirmar(p, 'Ana Lima', TEL_ANA, 3);
  igual('a confirmação pergunta "Como você vai pagar?" só com as formas do salão, e a observação dele',
    await caixa(p), { titulo: 'Como você vai pagar?', sub: 'O pagamento é feito no salão, no dia.',
      formas: ['Pix', 'Cartão de crédito'], obs: 'Parcelamos em até 3x' });

  const antes = (await A.dona.lista('agendamentos', { salaoId: A.SALAO })).length;
  await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  const r = await p.evaluate(() => ({ tela, aviso: document.getElementById('avisoConfirmar').innerText.replace(/\s+/g, ' ') }));
  verdade('sem escolher, não marca: fica na confirmação e diz o que falta',
    r.tela === 'confirmar' && /Escolha como você vai pagar/.test(r.aviso), JSON.stringify(r));
  igual('e nada foi para o banco', (await A.dona.lista('agendamentos', { salaoId: A.SALAO })).length, antes);

  await p.click('#cfPagamento .cf-pag-op[data-forma="pix"]'); await p.waitForTimeout(300);
  const escolhida = await p.evaluate(() => ({
    on: [...document.querySelectorAll('#cfPagamento .cf-pag-op.on')].map(b => b.dataset.forma),
    aviso: document.getElementById('avisoConfirmar').innerText.trim(),
    linha: [...document.querySelectorAll('#resumoFinal .cf-linha')].map(l => l.innerText.replace(/\s+/g, ' '))
      .find(t => /Pagamento/.test(t)) || '' }));
  igual('tocou em Pix: marcado, o aviso some, e o resumo ganha "Pagamento (no salão) Pix"',
    escolhida, { on: ['pix'], aviso: '', linha: 'Pagamento (no salão) Pix' });

  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const pronto = await p.evaluate(() => ({ tela, mini: (document.getElementById('resumoPronto') || {}).innerText || '' }));
  verdade('marcou, e a tela de pronto repete: "Pagamento no salão: Pix"',
    pronto.tela === 'pronto' && /Pagamento no salão: Pix/.test(pronto.mini), JSON.stringify(pronto));
  const ag = (await A.dona.lista('agendamentos', { salaoId: A.SALAO })).find(a => a.status !== 'cancelado');
  AG_ANA = ag && ag.id;
  igual('no banco: forma_pagamento = pix', ag && ag.formaPagamento, 'pix');

  await p.evaluate(() => abrirMeus());
  await p.waitForFunction(() => meusDaNuvem && meusDaNuvem.ags && meusDaNuvem.ags.length, null, { timeout: 10000 });
  await p.waitForTimeout(500);
  verdade('"Meus horários" mostra "· Pix" no horário', /R\$\s?80,00 · Pix/.test(await p.evaluate(() =>
    document.getElementById('p-meus').innerText)));
  await ctx.close();

  // Por fora da tela: forma que o salão não aceita não é gravada.
  const anon = aba();
  const h = await anon.chamar('horarios_livres', { p_profissional: A.prof.id, p_data: diaMais(12), p_servicos: [A.corte.id] });
  const vaga = (Array.isArray(h) ? h : []).map(x => typeof x === 'string' ? x : Object.values(x)[0])[0];
  const fora = um(await anon.chamar('agendar', { p_profissional: A.prof.id, p_inicio: vaga, p_servicos: [A.corte.id],
    p_nome: 'Duda Melo', p_telefone: tel('74'), p_forma_pagamento: 'dinheiro' }));
  const gravado = (await A.dona.lista('agendamentos', { salaoId: A.SALAO })).find(a => a.id === fora.id);
  igual('pela API, "dinheiro" num salão que só aceita Pix e crédito: marca, mas sem forma',
    gravado && (gravado.formaPagamento || null), null);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. O salão que não marcou formas');
{
  const { ctx, p } = await abrirLink(B.SLUG);
  await ateConfirmar(p, 'Bia Souza', tel('72'), 3);
  const c = await caixa(p);
  igual('aparecem as quatro, e escolher é opcional', c && [c.formas, c.sub],
    [['Pix', 'Dinheiro', 'Cartão de débito', 'Cartão de crédito'], '(opcional) O pagamento é feito no salão, no dia.']);
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const ag = (await B.dona.lista('agendamentos', { salaoId: B.SALAO }))[0];
  igual('sem escolher, marca normalmente, sem forma', [await p.evaluate(() => tela), ag && (ag.formaPagamento || null)], ['pronto', null]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Tudo no pacote: não pergunta');
{
  const { ctx, p } = await abrirLink(A.SLUG);
  await ateConfirmar(p, 'Cau Reis', tel('73'), 4);
  const r = await p.evaluate(() => {
    meusPacotes = [{ nome: 'x', servicos: escolha.servicos.slice(), dias: [0,1,2,3,4,5,6],
                     restantes: 3, vence_em: '2999-01-01' }];
    desenharConfirmar();
    const sem = !document.querySelector('#cfPagamento .cf-pag');
    escolha.para = 'ambos'; desenharConfirmar();
    const comAmiga = !!document.querySelector('#cfPagamento .cf-pag');
    escolha.para = 'mim'; meusPacotes = []; desenharConfirmar();
    return [sem, comAmiga];
  });
  igual('R$ 0 no pacote: sem a pergunta; com a acompanhante (que paga): pergunta', r, [true, true]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. O painel');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => d.dismiss());
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, A.dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.agendamentos)
    && bd.agendamentos.length > 0, null, { timeout: 20000 });
  await p.waitForTimeout(900);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });

  const cartao = await p.evaluate(id => {
    const a = bd.agendamentos.find(x => x.id === id);
    irPara('agenda'); vistaAgenda = 'mes'; diaAtual = a.data; pintar();
    return [...document.querySelectorAll('#listaDoDia .dia-cartao')].map(c => c.innerText.replace(/\s+/g, ' ')).join(' | ');
  }, AG_ANA);
  verdade('o cartão do dia mostra "Pix" embaixo do valor', /Ana Lima.*R\$\s?80,00 Pix/.test(cartao), cartao);

  const det = await p.evaluate(id => {
    abrirDetalhe(id);
    const linha = [...document.querySelectorAll('#modalCorpo tr')].map(t => t.innerText.replace(/\s+/g, ' '))
      .find(t => /^Pagamento/.test(t)) || '';
    const sel = document.getElementById('fFormaPag');
    return { linha, valor: sel && sel.value, opcoes: sel ? sel.options.length : 0 };
  }, AG_ANA);
  igual('o detalhe mostra a linha e o seletor com a escolha dela',
    det, { linha: 'Pagamento Pix como a cliente disse que vai pagar', valor: 'pix', opcoes: 5 });

  await p.selectOption('#fFormaPag', 'credito');
  await p.evaluate(id => salvarStatus(id), AG_ANA);
  await p.waitForTimeout(2500);
  const doBanco = (await A.dona.lista('agendamentos', { salaoId: A.SALAO })).find(a => a.id === AG_ANA);
  igual('a recepção troca para crédito, e o banco grava', doBanco && doBanco.formaPagamento, 'credito');

  await p.evaluate(async id => { await comandaDoAgendamento(id); }, AG_ANA);
  await p.waitForTimeout(2500);
  igual('a comanda abre com "Crédito" já escolhido na forma de pagamento',
    await p.evaluate(() => (document.getElementById('cForma') || {}).value), 'credito');
  await p.evaluate(() => fecharModal());

  const novo = await p.evaluate(profId => {
    abrirNovo(profId, 600);
    const sel = document.getElementById('fFormaPag');
    const r = sel ? [...sel.options].map(o => o.textContent) : null;
    fecharModal(); return r;
  }, A.prof.id);
  igual('o "+ Agendamento" tem o campo, com "Não informado" e as quatro formas', novo,
    ['Não informado', 'Pix', 'Dinheiro', 'Cartão de débito', 'Cartão de crédito']);

  // Marcado pela recepção, por telefone, já dizendo como ela vai pagar.
  const dia = diaMais(15);
  await p.evaluate(([profId, servId, d]) => {
    abrirNovo(profId, 600);
    document.getElementById('fNome').value = 'Gil Telefone';
    document.getElementById('fTel').value = '(51) 98877-6655';
    const cx = document.querySelector(`.lista-serv input[value="${servId}"]`); cx.checked = true; marcarServico(cx);
    document.getElementById('fData').value = d; document.getElementById('fInicio').value = '14:00';
    document.getElementById('fFormaPag').value = 'dinheiro';
    recalcularFim(); salvarAgendamento();
  }, [A.prof.id, A.corte.id, dia]);
  await p.waitForTimeout(3000);
  const doTel = (await A.dona.lista('agendamentos', { salaoId: A.SALAO }))
    .filter(a => a.origem !== 'online' && a.status !== 'cancelado');
  igual('marcado pelo painel com "Dinheiro": o banco grava', doTel.map(a => a.formaPagamento), ['dinheiro']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. Cores do tema, e nenhum erro');
{
  const css = fs.readFileSync(path.join(RAIZ, 'estilo.css'), 'utf8');
  const bloco = css.slice(css.indexOf('.cf-pag{'), css.indexOf('.cf-pag-obs{') + 80);
  verdade('o CSS da escolha não tem cor escrita (só variáveis do tema)', bloco.length > 300
    && !/#[0-9a-f]{3,8}\b|rgba?\(|hsl\(/i.test(bloco), bloco.match(/#[0-9a-f]{3,8}\b|rgba?\(|hsl\(/i));
  const linhaPainel = css.slice(css.indexOf('.dia-cartao .dc-pag{'), css.indexOf('.dia-cartao .dc-pag{') + 140);
  verdade('nem a etiqueta do cartão do painel', /var\(--txt2\)/.test(linhaPainel) && !/#[0-9a-f]{3,8}\b/i.test(linhaPainel), linhaPainel);
}
igual('nenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
