/* ===========================================================================
   AgendaPro — a Etapa 2 do agendamento: para quem é o atendimento

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/etapa2.test.mjs

   O pedido: a Etapa 2 começa com duas portas só — "Para mim" e "Para outra
   pessoa". Para mim usa quem marca e segue direto, sem pedir nome nem
   parentesco. Para outra pessoa abre a relação (Filha, Filho, Mãe, Pai, Avó,
   Avô, Cônjuge, Outra pessoa, em grade de dois) e o nome; o Continuar só
   liga com os dois.

   Antes, o "para quem" era um segmento em cima dos serviços (Para mim / Meu
   filho / Eu e meu filho). O "Eu e meu filho" — dois horários seguidos —
   continua existindo, como "Eu também quero ser atendido(a)" na segunda tela.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a tela de serviços não pergunta mais "para quem";
     2. a Etapa 2: rótulo, título, os dois cartões, a trilha em 2 de 5;
     3. Para mim segue direto, sem nome;
     4. Para outra pessoa: as oito relações em grade de dois, o nome, e o
        Continuar que diz o que falta até ter os dois;
     5. o Voltar devolve a Etapa 2 como ela estava;
     6. o "eu também" dobra a duração, e trocar para "para mim" solta o
        horário escolhido;
     7. marcando de verdade, o banco guarda "Ana (filha)" — e nada, para mim;
     8. no celular de 360px cabe tudo, sem rolagem de lado.
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

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`e2-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Manicure', duracaoMin:40, intervaloMin:0,
  preco:40, ativo:true, aceitaOnline:true, categoria:'Unhas' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#4F7356', funcionamento: SEMANA } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function pagina(largura = 412){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => { erros.push('ALERT: ' + d.message()); d.dismiss(); });
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('.boas-cta'), null, { timeout: 15000 });
  return { p, fechar: () => ctx.close() };
}
const tela = p => p.evaluate(() => tela);
const botao = p => p.evaluate(() => { const b = document.getElementById('btPrincipal');
  return { visivel: !!b.offsetParent, desligado: b.disabled, texto: b.textContent.trim() }; });
const ateEtapa2 = async p => {
  await p.click('.boas-cta');
  await p.waitForTimeout(500);
  await p.click('#listaServicos .sv-cartao');
  await p.click('#btPrincipal');
  await p.waitForTimeout(400);
};

/* ══════════════════════════════════════════════════════════════════════════
   1, 2 e 3 — A ETAPA 2 E O "PARA MIM"
   ══════════════════════════════════════════════════════════════════════════ */
{
  const { p, fechar } = await pagina();
  secao('1. A tela de serviços não pergunta mais "para quem"');
  await p.click('.boas-cta');
  await p.waitForTimeout(500);
  igual('nem o segmento, nem o campo do filho', await p.evaluate(() =>
    [!!document.getElementById('blocoParaQuem'), !!document.getElementById('pq-mim'),
     !!document.getElementById('fFilho'), /Para quem/.test(document.getElementById('p-servico').innerText)]),
    [false, false, false, false]);

  secao('2. A Etapa 2');
  await p.click('#listaServicos .sv-cartao');
  await p.click('#btPrincipal');
  await p.waitForTimeout(400);
  const t = await p.evaluate(() => ({
    tela, rotulo: document.querySelector('#p-quem .etapa-rot').textContent.trim(),
    titulo: document.querySelector('#p-quem h2').textContent.trim(),
    sub: document.querySelector('#p-quem .sub').textContent.trim(),
    cartoes: [...document.querySelectorAll('#p-quem .quem-card')].map(c => [
      c.querySelector('b').textContent.trim(), c.querySelector('.quem-txt span').textContent.trim(),
      !!c.querySelector('.quem-ic svg'), !!c.querySelector('.quem-seta svg')]),
    trilha: [...document.querySelectorAll('#trilha i')].map(i => i.classList.contains('on') ? 1 : 0).join(''),
    voltar: !!document.getElementById('btVoltar').offsetParent,
  }));
  igual('depois do serviço, a Etapa 2', t.tela, 'quem');
  igual('com o rótulo, o título e a frase do pedido', [t.rotulo, t.titulo, t.sub],
    ['Etapa 2', 'Para quem é o atendimento?', 'Escolha quem receberá o atendimento.']);
  igual('duas portas só, com ícone e seta', t.cartoes, [
    ['Para mim', 'O atendimento será realizado em meu nome.', true, true],
    ['Para outra pessoa', 'Vou agendar para um familiar ou outra pessoa.', true, true]]);
  igual('a trilha em 2 de 5, e o voltar à mão', [t.trilha, t.voltar], ['11000', true]);
  igual('e sem o botão de baixo: o cartão já avança', (await botao(p)).visivel, false);

  secao('3. Para mim segue direto');
  await p.click('#quemMim');
  await p.waitForTimeout(400);
  igual('vai para a escolha do profissional, sem pedir nome', [await tela(p),
    await p.evaluate(() => [escolha.para, nomeDoAtendido()])], ['prof', ['mim', '']]);
  igual('a trilha anda para 3 de 5', await p.evaluate(() =>
    [...document.querySelectorAll('#trilha i')].map(i => i.classList.contains('on') ? 1 : 0).join('')), '11100');
  await p.click('#btVoltar');
  await p.waitForTimeout(300);
  igual('o voltar devolve a Etapa 2 com o "Para mim" marcado', [await tela(p),
    await p.evaluate(() => document.getElementById('quemMim').classList.contains('sel'))], ['quem', true]);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   4, 5 e 6 — PARA OUTRA PESSOA
   ══════════════════════════════════════════════════════════════════════════ */
{
  const { p, fechar } = await pagina();
  await ateEtapa2(p);
  secao('4. Para outra pessoa: a relação e o nome');
  await p.click('#quemOutra');
  await p.waitForTimeout(400);
  const t = await p.evaluate(() => ({
    tela, rotulo: document.querySelector('#p-quemOutra .etapa-rot').textContent.trim(),
    titulo: document.querySelector('#p-quemOutra h2').textContent.trim(),
    sub: document.querySelector('#p-quemOutra .sub').textContent.trim(),
    relacoes: [...document.querySelectorAll('#gradeRelacao .rel-card')].map(c =>
      [c.querySelector('.rel-emoji').textContent, c.querySelector('.rel-rot').textContent]),
    colunas: getComputedStyle(document.getElementById('gradeRelacao')).gridTemplateColumns.split(' ').length,
    campo: [document.querySelector('label[for="fAtendido"]').textContent.trim(), document.getElementById('fAtendido').placeholder],
    trilha: [...document.querySelectorAll('#trilha i')].map(i => i.classList.contains('on') ? 1 : 0).join(''),
  }));
  igual('abre a segunda tela da Etapa 2, sem avançar', [t.tela, t.rotulo, t.trilha], ['quemOutra', 'Etapa 2', '11000']);
  igual('com o título e a frase do pedido', [t.titulo, t.sub],
    ['Quem receberá o atendimento?', 'Selecione a relação com você e informe o nome da pessoa.']);
  igual('as oito relações, na ordem, com o desenho', t.relacoes, [['👧', 'Filha'], ['👦', 'Filho'], ['👩', 'Mãe'],
    ['👨', 'Pai'], ['👵', 'Avó'], ['👴', 'Avô'], ['🧑‍🤝‍🧑', 'Cônjuge'], ['👤', 'Outra pessoa']]);
  igual('em grade de dois', t.colunas, 2);
  igual('e o campo do nome', t.campo, ['Nome da pessoa', 'Digite o nome']);
  igual('sem nada: o Continuar desligado, dizendo o que falta', await botao(p),
    { visivel:true, desligado:true, texto:'Escolha a relação com você' });
  await p.fill('#fAtendido', 'Ana');
  igual('só o nome não basta', (await botao(p)).desligado, true);
  await p.fill('#fAtendido', '');
  await p.locator('.rel-card', { hasText: 'Filha' }).click();
  igual('só a relação também não', await botao(p), { visivel:true, desligado:true, texto:'Digite o nome da pessoa' });
  igual('a relação tocada fica marcada, só ela', await p.evaluate(() =>
    [...document.querySelectorAll('.rel-card')].filter(c => c.classList.contains('sel') || c.getAttribute('aria-pressed') === 'true')
      .map(c => [c.querySelector('.rel-rot').textContent, c.getAttribute('aria-pressed')])), [['Filha', 'true']]);
  await p.fill('#fAtendido', '   ');
  igual('nome em branco não conta', (await botao(p)).desligado, true);
  await p.fill('#fAtendido', 'Ana');
  igual('com os dois, o Continuar liga', await botao(p), { visivel:true, desligado:false, texto:'Continuar' });
  await p.click('#btPrincipal');
  await p.waitForTimeout(400);
  igual('e segue, guardando a pessoa: "Ana (filha)"', [await tela(p),
    await p.evaluate(() => [escolha.para, nomeDoAtendido()])], ['prof', ['filho', 'Ana (filha)']]);

  secao('5. O voltar devolve a Etapa 2 como estava');
  await p.click('#btVoltar');
  await p.waitForTimeout(300);
  igual('a relação e o nome continuam lá', [await tela(p), await p.evaluate(() =>
    [document.querySelector('.rel-card.sel .rel-rot').textContent, document.getElementById('fAtendido').value])],
    ['quemOutra', ['Filha', 'Ana']]);
  await p.locator('.rel-card', { hasText: 'Outra pessoa' }).click();
  igual('"Outra pessoa" guarda só o nome', await p.evaluate(() => nomeDoAtendido()), 'Ana');
  await p.locator('.rel-card', { hasText: 'Avó' }).click();
  igual('e cada relação vai junto, em minúscula', await p.evaluate(() => nomeDoAtendido()), 'Ana (avó)');
  await p.click('#btVoltar');
  await p.waitForTimeout(300);
  igual('mais um voltar: a primeira tela, com "Para outra pessoa" marcado', [await tela(p),
    await p.evaluate(() => document.getElementById('quemOutra').classList.contains('sel'))], ['quem', true]);

  secao('6. O "eu também": dois horários seguidos');
  await p.click('#quemOutra');
  await p.waitForTimeout(300);
  await p.check('#fJunto');
  await p.click('#btPrincipal');
  await p.waitForTimeout(400);
  const dois = await p.evaluate(() => ({ para: escolha.para, sub: document.getElementById('subProf').textContent }));
  igual('vira "ambos", e o profissional sabe que são dois', [dois.para, /80 min \(dois atendimentos\)/.test(dois.sub)],
    ['ambos', true]);
  await p.evaluate(() => { escolha.data = '2099-01-01'; escolha.inicio = 600; });
  await p.click('#btVoltar'); await p.waitForTimeout(200);
  await p.click('#btVoltar'); await p.waitForTimeout(200);
  await p.click('#quemMim');
  await p.waitForTimeout(300);
  igual('trocar para "para mim" solta o horário (a duração mudou)', await p.evaluate(() =>
    [escolha.para, escolha.data, escolha.inicio]), ['mim', null, null]);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   7 — MARCANDO DE VERDADE
   ══════════════════════════════════════════════════════════════════════════ */
secao('7. O banco guarda para quem é');
async function marcar(quem){
  const cliente = aba();
  const TEL = '+5551' + (200000000 + (Date.now() % 79999999));
  await cliente.criarConta({ email:`e2c-${quem}-${m}@t.com`, senha:'minhasenhaboa', nome:'Maria Cliente', telefone: TEL });
  const ctx = await nav.newContext({ viewport:{ width:412, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, cliente.sessao()]);
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('.boas-cta'), null, { timeout: 15000 });
  await ateEtapa2(p);
  if(quem === 'mim') await p.click('#quemMim');
  else {
    await p.click('#quemOutra'); await p.waitForTimeout(300);
    await p.locator('.rel-card', { hasText: 'Filha' }).click();
    await p.fill('#fAtendido', 'Ana');
    await p.click('#btPrincipal');
  }
  await p.waitForTimeout(600);
  if(await p.evaluate(() => tela === 'prof')){ await p.click('#listaProfs .opcao'); await p.click('#btPrincipal'); }
  await p.waitForTimeout(3000);
  await p.click('#listaHoras .hora');
  await p.waitForTimeout(500);
  await p.click('#btPrincipal');
  await p.waitForTimeout(1500);
  const pedeNome = await p.evaluate(() => /nome da pessoa/i.test(document.body.innerText));
  if(await p.evaluate(() => tela === 'dados')){
    if(await p.isVisible('#dNome')) await p.fill('#dNome', 'Maria Cliente');
    if(await p.isVisible('#dTel')) await p.fill('#dTel', '51988887777');
    if(await p.isVisible('#dNasc')) await p.fill('#dNasc', '1989-10-04');
    if(await p.isVisible('#dEmail')) await p.fill('#dEmail', 'maria@exemplo.com');
    await p.click('#btPrincipal');
    await p.waitForTimeout(1500);
  }
  const resumo = await p.evaluate(() => (document.getElementById('p-confirmar') || document.body).innerText);
  await p.click('#btPrincipal');
  await p.waitForTimeout(4000);
  const pronto = await p.evaluate(() => ({ tela, texto: document.getElementById('p-pronto').innerText }));
  await ctx.close();
  const ags = await dona.lista('agendamentos', { salaoId: SALAO });
  return { pronto, pedeNome, resumo, atendido: ags[ags.length - 1] && ags[ags.length - 1].atendidoNome };
}
const outra = await marcar('outra');
igual('para outra pessoa: chega ao fim', outra.pronto.tela, 'pronto');
igual('e o banco guarda "Ana (filha)"', outra.atendido, 'Ana (filha)');
verdade('a tela final diz para quem é', /Para Ana \(filha\)/.test(outra.pronto.texto), outra.pronto.texto.slice(0, 200));
const mim = await marcar('mim');
igual('para mim: chega ao fim, sem pedir nome de ninguém', [mim.pronto.tela, mim.pedeNome], ['pronto', false]);
igual('e o banco não guarda outra pessoa', mim.atendido || null, null);

/* ══════════════════════════════════════════════════════════════════════════
   8 — NO CELULAR PEQUENO
   ══════════════════════════════════════════════════════════════════════════ */
secao('8. A 360px, tudo cabe');
{
  const { p, fechar } = await pagina(360);
  await ateEtapa2(p);
  const um = await p.evaluate(() => ({ sobra: document.documentElement.scrollWidth - innerWidth,
    alvo: Math.min(...[...document.querySelectorAll('.quem-card')].map(c => c.getBoundingClientRect().height)) }));
  igual('primeira tela sem rolagem de lado, cartões grandes', [um.sobra <= 0, um.alvo >= 80], [true, true]);
  await p.click('#quemOutra');
  await p.waitForTimeout(300);
  const dois = await p.evaluate(() => ({ sobra: document.documentElement.scrollWidth - innerWidth,
    alvo: Math.min(...[...document.querySelectorAll('.rel-card')].map(c => c.getBoundingClientRect().height)),
    colunas: getComputedStyle(document.getElementById('gradeRelacao')).gridTemplateColumns.split(' ').length }));
  igual('segunda tela sem rolagem de lado, dois por linha, alvo de dedo', [dois.sobra <= 0, dois.colunas, dois.alvo >= 44],
    [true, 2, true]);
  await fechar();
}

igual('\nnenhum erro de JavaScript nem alerta', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
