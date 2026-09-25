/* ===========================================================================
   AgendaPro — horários de funcionamento, pagamentos e informações

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/funcionamento.test.mjs

   O pedido: o dono cadastra a semana (dia fechado, dia aberto, dois períodos
   no mesmo dia), e a página da cliente diz sozinha, pelo relógio, se está
   ABERTO ou FECHADO — e quando abre. Abaixo do endereço, três botões:
   Pagamentos, Horários, Informações; tocar abre uma folha que sobe de baixo.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a conta, sem navegador: os exemplos do pedido, o almoço, a virada do
        dia, a semana que só abre segunda, e lixo vindo do banco;
     2. o painel: cadastrar, dois períodos, repetir na semana, fechar um dia,
        recusar horário torto, gravar — e reabrir para editar;
     3. a página, com o relógio PARADO em horas escolhidas: aberto, fechado
        no almoço, fechado à noite, fechado no domingo;
     4. a folha: a semana inteira, hoje destacado, dois períodos, fechar;
     5. as cores do salão chegando no componente — roxo, verde, vermelho;
     6. salão sem nada cadastrado: nada aparece, nada quebra;
     7. celular estreito: nada passa da largura.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
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

/* ══════════════════════════════════════════════════════════════════════════
   1 — A CONTA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · A conta de aberto e fechado');
const caixa = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(RAIZ, 'funcionamento.js'), 'utf8'), caixa);
const F = caixa.window.Funcionamento;

const SEMANA = {
  '1': [['08:00','12:00'], ['13:30','18:00']],
  '2': [['08:00','18:00']], '3': [['08:00','18:00']], '4': [['08:00','18:00']],
  '5': [['08:00','18:00']], '6': [['08:00','14:00']], '0': [],
};
const fs_ = F.normalizar(SEMANA);
const em = (dow, h, m = 0) => F.estado(fs_, { dow, min: h * 60 + m });
igual('segunda 10h: ABERTO, Hoje, até 12:00', em(1, 10),
  { aberto: true, detalhe: 'Hoje, até 12:00' });
igual('segunda 12h30, no almoço: FECHADO, Abre às 13:30', em(1, 12, 30),
  { aberto: false, detalhe: 'Abre às 13:30' });
igual('segunda 13h30 em ponto: ABERTO de novo', em(1, 13, 30),
  { aberto: true, detalhe: 'Hoje, até 18:00' });
/* ⚠ O FIM É ABERTO. Às 18:00 em ponto a porta já fechou — senão 08–12 e
   12–18 diriam coisas diferentes sobre o meio-dia. */
igual('segunda 18h em ponto: FECHADO, Abre amanhã às 08:00', em(1, 18),
  { aberto: false, detalhe: 'Abre amanhã às 08:00' });
igual('segunda 7h: FECHADO, Abre às 08:00', em(1, 7),
  { aberto: false, detalhe: 'Abre às 08:00' });
igual('sábado 15h, com domingo fechado: Abre segunda às 08:00', em(6, 15),
  { aberto: false, detalhe: 'Abre segunda às 08:00' });
igual('domingo 10h: Abre amanhã às 08:00', em(0, 10),
  { aberto: false, detalhe: 'Abre amanhã às 08:00' });
igual('só abre às segundas, segunda 19h: a próxima segunda',
  F.estado(F.normalizar({ 1: [['08:00','18:00']] }), { dow: 1, min: 19 * 60 }),
  { aberto: false, detalhe: 'Abre na próxima segunda às 08:00' });
igual('dois períodos encostados viram um só: 08–12 e 12–18',
  F.estado(F.normalizar({ 2: [['08:00','12:00'], ['12:00','18:00']] }), { dow: 2, min: 11 * 60 + 59 }),
  { aberto: true, detalhe: 'Hoje, até 18:00' });
igual('até meia-noite, e abre de novo à 00:00: diz o fechamento de amanhã',
  F.estado(F.normalizar({ 5: [['18:00','00:00']], 6: [['00:00','02:00']] }), { dow: 5, min: 23 * 60 }),
  { aberto: true, detalhe: 'Até amanhã às 02:00' });

igual('nada cadastrado: não há o que dizer', F.normalizar({}), null);
igual('todos os dias fechados: também não', F.normalizar({ 0: [], 1: [], 6: [] }), null);
igual('lixo do banco não quebra', [F.normalizar('abc'), F.normalizar([1, 2]),
  F.normalizar({ 1: [['aa', 'bb'], ['25:00', '26:00']] }), F.normalizar(null)],
  [null, null, null, null]);
igual('e estado de nada é nada', F.estado(null, { dow: 1, min: 600 }), null);

const q = F.validar({ 1: [['08:00', '']], 2: [['18:00', '08:00']],
                      3: [['08:00', '12:00'], ['11:00', '14:00']], 4: [['08:00', '18:00']] });
igual('o editor recusa três erros, um por dia, e deixa o certo passar', q.length, 3);
verdade('dizendo o dia e o que falta', /Segunda-feira: preencha/.test(q[0]) &&
  /Terça-feira: o fechamento precisa ser depois/.test(q[1]) &&
  /Quarta-feira: dois horários se cruzam/.test(q[2]), q.join(' | '));

igual('pagamentos: só as formas conhecidas, sem repetir',
  F.pagamentos({ formas: ['pix', 'ouro', 'pix', 'credito'], obs: ' até 3x ' }),
  { formas: ['pix', 'credito'], obs: 'até 3x' });
igual('sem forma nem observação: nada', F.pagamentos({ formas: [] }), null);

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
const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`fn-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salao Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.atualizar('saloes', SALAO, { whatsapp:'(11) 98111-3251',
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova',
             cidade:'Itu', uf:'SP' },
  cfg:{ diasLiberados:30, cor:'#6D28D9' } });
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

async function painel(quando){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                     isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  // Antes de abrir: a prévia é desenhada na carga, com a hora daquele instante.
  if(quando) await p.clock.setFixedTime(quando);
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => d.accept());
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function'
    && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => { irPara('salao'); trocarAbaSalao('dados'); });
  await p.waitForTimeout(600);
  return { p, fechar: () => ctx.close() };
}
const salvarDados = async p => {
  await p.evaluate(() => salvarCadastroSalao());
  await p.waitForTimeout(1800);
};

/* A página com o relógio PARADO numa hora do salão. `setFixedTime` para o
   Date inteiro da página — o mesmo relógio que a cliente teria na mão. */
const SP = h => new Date(h + '-03:00');
async function pagina(quando, largura = 412){
  const ctx = await nav.newContext({ viewport:{ width:largura, height:915 }, isMobile:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  if(quando) await p.clock.setFixedTime(quando);
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => {
    const e = document.getElementById('capaMarca');
    return e && e.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  await p.waitForTimeout(400);
  return { p, fechar: () => ctx.close() };
}
const lerCapa = p => p.evaluate(() => {
  const st = document.querySelector('.status-casa');
  return {
    botoes: [...document.querySelectorAll('.recurso')].map(b => b.innerText.trim()),
    status: st ? st.querySelector('.status-rot').textContent.trim() : null,
    detalhe: st ? st.querySelector('.status-txt').textContent.trim() : null,
    abaixoDoEndereco: (() => {
      const end = document.querySelector('.marca-end');
      const r = document.querySelector('.recursos');
      return !!(end && r && (end.compareDocumentPosition(r) & Node.DOCUMENT_POSITION_FOLLOWING));
    })(),
  };
});

/* ══════════════════════════════════════════════════════════════════════════
   6 (antes de tudo) — SALÃO SEM NADA CADASTRADO
   ══════════════════════════════════════════════════════════════════════════ */
secao('6 · Salão sem horário cadastrado: nada aparece, nada quebra');
{
  const { p, fechar } = await pagina();
  const c = await lerCapa(p);
  igual('sem horário, sem pagamento, sem apresentação: nenhuma fileira', c.botoes, []);
  igual('e nenhum cartão de status — nada de horário inventado', c.status, null);
  await fechar();

  await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#6D28D9',
    funcionamento:'isto não é uma semana', pagamentos:[1, 2] } });
  const { p: p2, fechar: f2 } = await pagina();
  igual('lixo no banco também não mostra nada', (await lerCapa(p2)).status, null);
  await f2();
  await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#6D28D9' } });
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — O PAINEL
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · O painel: cadastrar, editar, fechar um dia');
{
  const { p, fechar } = await painel();
  const dias = await p.evaluate(() =>
    [...document.querySelectorAll('#editorFuncionamento .func-dia b')].map(b => b.textContent));
  igual('os sete dias, de segunda a domingo', dias,
    ['Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado','Domingo']);
  verdade('nascem todos fechados — nenhum horário inventado',
    await p.evaluate(() => document.querySelectorAll('#editorFuncionamento .func-hora').length === 0));

  // Segunda: abre, preenche, e ganha o segundo período.
  await p.evaluate(() => funcAbrir(1));
  const seg = '#editorFuncionamento .func-dia[data-dia="1"]';
  await p.locator(seg + ' .func-hora').nth(0).selectOption('08:00');
  await p.locator(seg + ' .func-hora').nth(1).selectOption('12:00');
  await p.click(seg + ' .func-mais');
  const inputs = seg + ' .func-hora';
  const n = await p.evaluate(s => document.querySelectorAll(s).length, inputs);
  igual('"+ Adicionar horário" abre o segundo período', n, 4);
  await p.locator(inputs).nth(2).selectOption('13:30');
  await p.locator(inputs).nth(3).selectOption('18:00');

  // Terça a sexta, pelo atalho; sábado, abrindo — copia a sexta — e trocando.
  await p.evaluate(() => { funcRepetirSegunda(); funcAbrir(6); });
  const sab = '#editorFuncionamento .func-dia[data-dia="6"] .func-hora';
  igual('abrir o sábado copia o dia aberto anterior, e não inventa',
    await p.evaluate(s => [...document.querySelectorAll(s)].map(i => i.value), sab),
    ['08:00', '12:00', '13:30', '18:00']);
  await p.evaluate(() => { funcTirar(6, 1); });
  await p.locator(sab).nth(1).selectOption('14:00');

  // Um horário torto segura o salvar e diz o motivo.
  await p.evaluate(() => { funcAbrir(0); });
  await p.locator('#editorFuncionamento .func-dia[data-dia="0"] .func-hora').nth(0).selectOption('18:00');
  await p.locator('#editorFuncionamento .func-dia[data-dia="0"] .func-hora').nth(1).selectOption('08:00');
  await salvarDados(p);
  verdade('horário torto: o banco não recebe nada', !(await cfgDe()).funcionamento);
  verdade('e a tela diz qual dia e por quê',
    /Domingo: o fechamento precisa ser depois/.test(
      await p.evaluate(() => document.getElementById('avisoFuncionamento').textContent)));

  // Domingo fechado, e agora salva.
  await p.evaluate(() => funcFechar(0));
  await p.evaluate(() => { alternarPagamento('pix'); alternarPagamento('credito'); });
  await p.fill('#cPagObs', 'Parcelamos em até 3x no cartão');
  await p.fill('#cSobre', 'Salão de beleza com 10 anos de casa.');
  await p.fill('#cInsta', 'https://instagram.com/salaomegatop/');
  await salvarDados(p);
  await fechar();

  const c = await cfgDe();
  igual('gravado: segunda com dois períodos', c.funcionamento && c.funcionamento['1'],
    [['08:00','12:00'], ['13:30','18:00']]);
  igual('terça a sexta iguais à segunda', [2,3,4,5].map(d => c.funcionamento[String(d)]),
    Array(4).fill([['08:00','12:00'], ['13:30','18:00']]));
  igual('sábado até 14:00', c.funcionamento['6'], [['08:00','14:00']]);
  igual('domingo fechado', c.funcionamento['0'], []);
  // O jsonb do banco reordena as chaves: compara campo a campo.
  igual('as formas de pagamento', [c.pagamentos && c.pagamentos.formas, c.pagamentos && c.pagamentos.obs],
    [['pix', 'credito'], 'Parcelamos em até 3x no cartão']);
  igual('a apresentação', c.sobre, 'Salão de beleza com 10 anos de casa.');
  igual('o Instagram limpo, sem o endereço em volta', c.instagram, 'salaomegatop');

  // Reabrir e EDITAR: o painel traz o que foi gravado, e a troca grava.
  const { p: p2, fechar: f2 } = await painel();
  igual('ao reabrir, o sábado vem como foi salvo',
    await p2.evaluate(() => [...document.querySelectorAll(
      '#editorFuncionamento .func-dia[data-dia="6"] .func-hora')].map(i => i.value)),
    ['08:00', '14:00']);
  await p2.locator('#editorFuncionamento .func-dia[data-dia="6"] .func-hora').nth(1).selectOption('13:00');
  await salvarDados(p2);
  await f2();
  igual('editado: sábado agora até 13:00', (await cfgDe()).funcionamento['6'],
    [['08:00','13:00']]);
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — A PÁGINA, COM O RELÓGIO PARADO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · A página diz ABERTO ou FECHADO pelo relógio');
/* Datas escolhidas pelo dia da semana: 2026-10-05 é segunda. */
const CASOS = [
  ['2026-10-05T10:00', 'segunda 10:00', 'ABERTO',  'Hoje, até 12:00'],
  ['2026-10-05T12:30', 'segunda 12:30', 'FECHADO', 'Abre às 13:30'],
  ['2026-10-05T19:00', 'segunda 19:00', 'FECHADO', 'Abre amanhã às 08:00'],
  ['2026-10-10T15:00', 'sábado 15:00',  'FECHADO', 'Abre segunda às 08:00'],
  ['2026-10-11T10:00', 'domingo 10:00', 'FECHADO', 'Abre amanhã às 08:00'],
];
for(const [quando, rot, st, det] of CASOS){
  const { p, fechar } = await pagina(SP(quando));
  const c = await lerCapa(p);
  igual(rot + ': ' + st + ' — ' + det, [c.status, c.detalhe], [st, det]);
  await fechar();
}
{
  const { p, fechar } = await pagina(SP('2026-10-05T10:00'));
  const c = await lerCapa(p);
  igual('os três botões, na ordem do pedido', c.botoes, ['Pagamentos', 'Horários', 'Informações']);
  verdade('logo abaixo do endereço', c.abaixoDoEndereco);

  await fechar();
}
{
  /* O cartão se corrige sozinho: o relógio ANDA até o almoço e o status vira
     sem recarregar. Com o relógio instalado, e não chamando a função à mão —
     senão o teste provaria a função e não o relógio que a chama. */
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 }, isMobile:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  await p.clock.install({ time: SP('2026-10-05T11:59:20') });
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.clock.runFor(4000);
  await p.waitForFunction(() => !!document.querySelector('.status-casa'), null, { timeout: 15000 });
  const antes = (await lerCapa(p)).status;
  await p.clock.runFor(60000);
  igual('às 11:59 ABERTO; um minuto depois, FECHADO — sem recarregar',
    [antes, (await lerCapa(p)).status], ['ABERTO', 'FECHADO']);
  await ctx.close();
}

{
  /* A prévia do painel diz o mesmo que a página, na mesma hora. As duas usam
     o funcionamento.js — este teste existe para o dia em que alguém escrever
     uma segunda conta "só para a prévia". */
  const { p, fechar } = await painel(SP('2026-10-05T12:30'));
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(500);
  const r = await p.evaluate(() => ({
    status: (document.querySelector('#previaFone .fone-status') || {}).innerText || '',
    botoes: [...document.querySelectorAll('#previaFone .fone-recurso')].map(b => b.innerText.trim()),
    icones: document.querySelectorAll('#previaFone .fone-recurso svg').length,
  }));
  verdade('a prévia do painel mostra o mesmo FECHADO — Abre às 13:30',
    /FECHADO/.test(r.status) && /Abre às 13:30/.test(r.status), JSON.stringify(r));
  igual('com os mesmos três botões', r.botoes, ['Pagamentos', 'Horários', 'Informações']);
  igual('e os três ícones desenhados', r.icones, 3);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — A FOLHA
   ══════════════════════════════════════════════════════════════════════════ */
secao('4 · A folha de horários');
{
  const { p, fechar } = await pagina(SP('2026-10-05T10:00'));
  await p.click('.status-casa');
  await p.waitForTimeout(450);
  const f = await p.evaluate(() => {
    const fo = document.querySelector('#folha .folha');
    const r = fo.getBoundingClientRect();
    return {
      aberta: document.getElementById('folha').classList.contains('on'),
      titulo: fo.querySelector('h3').textContent.trim(),
      sub: fo.querySelector('.folha-cabeca p').textContent.trim(),
      dias: [...fo.querySelectorAll('.semana-dia')].map(d =>
        d.querySelector('.semana-nome').firstChild.textContent.trim() + ' = '
        + d.querySelector('.semana-horas').innerText.replace(/\n/g, ' / ')),
      hoje: [...fo.querySelectorAll('.semana-dia.hoje .semana-nome')].map(e => e.firstChild.textContent.trim()),
      noPe: Math.round(innerHeight - r.bottom),
      altura: Math.round(r.height), janela: innerHeight,
      dialogo: fo.getAttribute('role') === 'dialog',
    };
  });
  verdade('tocar no cartão abre a folha', f.aberta);
  igual('com o título e o subtítulo do pedido', [f.titulo, f.sub],
    ['Horário de Funcionamento', 'Confira nossos horários de atendimento']);
  igual('a semana inteira, de segunda a domingo', f.dias, [
    'Segunda-feira = 08:00 – 12:00 / 13:30 – 18:00',
    'Terça-feira = 08:00 – 12:00 / 13:30 – 18:00',
    'Quarta-feira = 08:00 – 12:00 / 13:30 – 18:00',
    'Quinta-feira = 08:00 – 12:00 / 13:30 – 18:00',
    'Sexta-feira = 08:00 – 12:00 / 13:30 – 18:00',
    'Sábado = 08:00 – 13:00',
    'Domingo = Fechado']);
  igual('e só hoje destacado — segunda', f.hoje, ['Segunda-feira']);
  verdade('ela sobe de baixo, colada no pé da tela', f.noPe === 0, JSON.stringify(f));
  verdade('sem tomar a tela inteira', f.altura < f.janela * 0.9, JSON.stringify(f));
  verdade('e é um diálogo para quem usa leitor de tela', f.dialogo);

  await p.click('.folha-fechar');
  await p.waitForTimeout(400);
  verdade('o X fecha', !(await p.evaluate(() => !!document.getElementById('folha'))));

  await p.click('.recurso[data-recurso="horarios"]');
  await p.waitForTimeout(400);
  await p.mouse.click(200, 40);          // fora da folha, no véu escuro
  await p.waitForTimeout(400);
  verdade('o botão Horários abre a mesma folha, e tocar fora fecha',
    !(await p.evaluate(() => !!document.getElementById('folha'))));

  await p.click('.recurso[data-recurso="pagamentos"]');
  await p.waitForTimeout(400);
  const pg = await p.evaluate(() => document.querySelector('#folha .folha').innerText);
  verdade('Pagamentos mostra o que foi marcado, e nada mais',
    /Pix/.test(pg) && /Cartão de crédito/.test(pg) && !/Dinheiro/.test(pg)
    && /Parcelamos em até 3x/.test(pg), pg);
  await p.keyboard.press('Escape');
  await p.waitForTimeout(400);
  verdade('o Esc fecha', !(await p.evaluate(() => !!document.getElementById('folha'))));

  /* Trocar de tela com a folha aberta: ela não pode ficar flutuando sobre a
     loja. */
  await p.click('.recurso[data-recurso="horarios"]');
  await p.waitForTimeout(400);
  await p.evaluate(() => irPara('loja'));
  await p.waitForTimeout(300);
  verdade('ir para outra tela fecha a folha',
    !(await p.evaluate(() => !!document.getElementById('folha'))));
  await p.evaluate(() => irPara('capa'));
  await p.waitForTimeout(300);

  await p.click('.recurso[data-recurso="informacoes"]');
  await p.waitForTimeout(400);
  const info = await p.evaluate(() => ({
    txt: document.querySelector('#folha .folha').innerText,
    mapa: !!document.querySelector('#folha a[href*="google.com/maps"]'),
    insta: (document.querySelector('#folha a[href*="instagram.com"]') || {}).href || '',
  }));
  verdade('Informações traz a apresentação e o endereço',
    /10 anos de casa/.test(info.txt) && /Rua Avanhandava, 10/.test(info.txt), info.txt);
  verdade('com o mapa e o Instagram', info.mapa && /instagram\.com\/salaomegatop$/.test(info.insta),
    JSON.stringify(info));
  await fechar();
}

{
  /* O destaque segue o DIA, e não a segunda-feira. Um teste só na segunda
     não distingue "destaca hoje" de "destaca a primeira linha". */
  const { p, fechar } = await pagina(SP('2026-10-10T09:00'));
  await p.click('.status-casa');
  await p.waitForTimeout(400);
  igual('num sábado, o sábado é que fica destacado',
    await p.evaluate(() => [...document.querySelectorAll('.semana-dia.hoje .semana-nome')]
      .map(e => e.firstChild.textContent.trim())), ['Sábado']);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — AS CORES DO SALÃO
   ══════════════════════════════════════════════════════════════════════════ */
secao('5 · O componente acompanha a cor do salão');
/* A cor como o NAVEGADOR a pinta, em RGB, venha a regra em que formato vier
   (color-mix devolve "color(srgb …)"): um pixel de canvas lê qualquer um. */
const PIXEL = `css => { const c = document.createElement('canvas'); c.width = c.height = 1;
  const x = c.getContext('2d'); x.fillStyle = '#000'; x.fillStyle = css;
  x.fillRect(0, 0, 1, 1); return [...x.getImageData(0, 0, 1, 1).data]; }`;
const matiz = ([r, g, b]) => {
  [r, g, b] = [r, g, b].map(v => v / 255);
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  if(!d) return null;
  const h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return (h * 60 + 360) % 360;
};
const pertoDe = (a, b) => a !== null && Math.min(Math.abs(a - b), 360 - Math.abs(a - b)) <= 20;
const lum = rgb => rgb.slice(0, 3).map(v => v / 255)
  .map(c => c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
  .reduce((s, v, i) => s + [0.2126, 0.7152, 0.0722][i] * v, 0);
const contraste = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05); };
const hexRgb = h => [1, 3, 5].map(i => parseInt(h.substr(i, 2), 16));

for(const [nome, cor] of [['roxo', '#6D28D9'], ['verde', '#15803D'], ['vermelho', '#B91C1C']]){
  const c0 = await cfgDe();
  await dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, c0, { cor }) });
  const { p, fechar } = await pagina(SP('2026-10-05T10:00'));
  await p.click('.status-casa');
  await p.waitForTimeout(400);
  const r = await p.evaluate(px => {
    const pixel = eval(px);
    return {
      botao: pixel(getComputedStyle(document.querySelector('.recurso.destaque')).backgroundColor),
      hoje: pixel(getComputedStyle(document.querySelector('.semana-dia.hoje')).backgroundColor),
    };
  }, PIXEL);
  const h = matiz(hexRgb(cor));
  verdade(nome + ': o botão Horários tem o matiz da cor do salão', pertoDe(matiz(r.botao), h),
    JSON.stringify(r));
  verdade(nome + ': e o dia de hoje na folha também', pertoDe(matiz(r.hoje), h), JSON.stringify(r));
  await fechar();
}

{
  /* ⚠ O PRINT DELE: gradiente roxo forte, letras claras. O botão Horários era
     roxo-transparente com letra roxa, sobre roxo — sumia, e ficava um vão
     entre Pagamentos e Informações. O ABERTO verde quase não se lia. Medido
     aqui como regra: opaco, e a letra se lendo sobre o próprio fundo. */
  const c0 = await cfgDe();
  await dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, c0, {
    cor: '#6D28D9', tema: 'escuro', fundoTipo: 'gradiente', gradiente: '#A000FF,#1A1330' }) });
  const { p, fechar } = await pagina(SP('2026-10-05T10:00'));
  const r = await p.evaluate(px => {
    const pixel = eval(px);
    const cor = (sel, prop) => pixel(getComputedStyle(document.querySelector(sel))[prop]);
    return {
      botaoFundo: cor('.recurso.destaque', 'backgroundColor'),
      botaoLetra: cor('.recurso.destaque .recurso-rot', 'color'),
      statusFundo: cor('.status-casa', 'backgroundColor'),
      statusLetra: cor('.status-casa .status-rot', 'color'),
      boasFundo: cor('.boas', 'backgroundColor'),
      boasLetra: cor('.boas-oi', 'color'),
    };
  }, PIXEL);
  verdade('sobre o gradiente roxo, o botão Horários é opaco — não some no fundo',
    r.botaoFundo[3] === 255, JSON.stringify(r));
  verdade('e a palavra "Horários" se lê sobre ele (3:1 ou mais)',
    contraste(r.botaoLetra, r.botaoFundo) >= 3,
    contraste(r.botaoLetra, r.botaoFundo).toFixed(2) + ':1 ' + JSON.stringify(r));
  verdade('o cartão ABERTO também é opaco', r.statusFundo[3] === 255, JSON.stringify(r));
  verdade('e o "ABERTO" se lê sobre ele',
    contraste(r.statusLetra, r.statusFundo) >= 3,
    contraste(r.statusLetra, r.statusFundo).toFixed(2) + ':1');
  /* O cartão Bem-vindo tinha o mesmo defeito: tom transparente da marca, e o
     "Bem-vindo!" roxo sumindo sobre o fundo roxo. */
  verdade('o cartão Bem-vindo também é opaco', r.boasFundo[3] === 255, JSON.stringify(r));
  verdade('e o "Bem-vindo!" se lê sobre ele',
    contraste(r.boasLetra, r.boasFundo) >= 3,
    contraste(r.boasLetra, r.boasFundo).toFixed(2) + ':1');
  await fechar();
  await dona.atualizar('saloes', SALAO, { cfg: c0 });
}

/* ══════════════════════════════════════════════════════════════════════════
   7 — CELULAR ESTREITO
   ══════════════════════════════════════════════════════════════════════════ */
secao('7 · Celular estreito');
for(const larg of [360, 412]){
  const { p, fechar } = await pagina(SP('2026-10-05T10:00'), larg);
  await p.click('.status-casa');
  await p.waitForTimeout(400);
  const r = await p.evaluate(() => ({
    lado: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    folha: Math.round(document.querySelector('#folha .folha').getBoundingClientRect().right),
    janela: innerWidth,
  }));
  verdade(larg + 'px: nada rola de lado, e a folha cabe', r.lado <= 0 && r.folha <= r.janela,
    JSON.stringify(r));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   8 — O ENDEREÇO NÃO VIRA CÓDIGO

   Achado ao montar a folha de Informações: a capa punha o endereço na página
   sem escapar. Qualquer pessoa cria um salão, e um HTML no campo Rua rodava
   no celular de quem abrisse o link — medido, com um `onerror` que marcava
   a janela. A folha nova mostra o endereço de novo, então a prova vale para
   os dois lugares.
   ══════════════════════════════════════════════════════════════════════════ */
secao('8 · O endereço digitado pelo dono não vira código na página');
{
  const c0 = await cfgDe();
  await dona.atualizar('saloes', SALAO, { cfg: c0, endereco: {
    logradouro: '<img src=x onerror="window.__invadiu=1">Rua Avanhandava',
    numero: '10', bairro: '<b onmouseover="window.__invadiu=2">Cidade Nova</b>',
    cidade: 'Itu', uf: 'SP' } });
  const { p, fechar } = await pagina(SP('2026-10-05T10:00'));
  await p.click('.recurso[data-recurso="informacoes"]');
  await p.waitForTimeout(400);
  const r = await p.evaluate(() => ({
    rodou: window.__invadiu || 0,
    tags: document.querySelectorAll('.marca-end img, .marca-end b, #folha img, #folha .folha-item b img').length,
    capa: document.querySelector('.marca-end').innerText,
    folha: document.querySelector('#folha').innerText,
  }));
  igual('nenhum código do endereço rodou', r.rodou, 0);
  igual('nenhuma tag do endereço virou elemento', r.tags, 0);
  verdade('o texto aparece como foi digitado, na capa e na folha',
    /<img src=x/.test(r.capa) && /<img src=x/.test(r.folha), JSON.stringify(r));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   9 — FECHAR TODOS OS DIAS TIRA O HORÁRIO DA PÁGINA

   É o jeito de o dono "desligar" o horário: todos fechados grava nulo, e a
   página volta ao estado de quem nunca cadastrou. Gravar sete dias vazios
   deixaria um FECHADO permanente na primeira dobra da página dele.
   ══════════════════════════════════════════════════════════════════════════ */
secao('9 · Todos os dias fechados: o horário sai da página');
{
  const { p, fechar } = await painel();
  await p.evaluate(() => { for(let d = 0; d <= 6; d++) funcFechar(d); });
  await salvarDados(p);
  await fechar();
  igual('no banco, "não informado"', (await cfgDe()).funcionamento, null);
  const { p: p2, fechar: f2 } = await pagina(SP('2026-10-05T10:00'));
  const c = await lerCapa(p2);
  igual('na página: sem cartão de status', c.status, null);
  verdade('e sem o botão Horários — os outros dois continuam',
    !c.botoes.includes('Horários') && c.botoes.includes('Pagamentos'), JSON.stringify(c.botoes));
  await f2();
}

igual('nenhum erro nas telas', erros, []);
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
