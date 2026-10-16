/* ===========================================================================
   A aba Aniversariantes

   Pedido do dono: "que o aniversário tenha um tópico separado do dashboard,
   pra eu clicar e ver os aniversariantes". A conta é a mesma do cartão do
   Dashboard (`aniversariantes()`); aqui ela ganha aba no menu, período à
   escolha (hoje, 7 dias, o mês, qualquer mês) e o atalho para a ficha.

   Na demonstração (sem banco). Precisa do servidor estático:
       python3 -m http.server 8099 --directory .
       PLAYWRIGHT=.../node_modules/playwright node tests/aniversarios-tela.test.mjs
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, falhas = 0;
const diz = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
const ctx = await nav.newContext({ viewport:{ width:375, height:800 }, isMobile:true, hasTouch:true });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => d.dismiss());
await p.goto(BASE + 'app.html?demo=1');
await p.waitForTimeout(1200);

/* As datas saem do `hoje()` do próprio painel (fuso do salão), e são
   montadas de modo que caiam no MESMO mês de hoje — quem já fez, quem faz
   hoje e quem vai fazer. Mais duas fichas: uma de outro mês, uma sem data. */
const cena = await p.evaluate(() => {
  if(typeof pdFechar === 'function') try{ pdFechar(true); }catch(e){}
  const hj = hoje(), mes = hj.slice(5, 7), ano = Number(hj.slice(0, 4));
  const dia = Number(hj.slice(8, 10));
  const noMes = d => `1990-${mes}-${String(d).padStart(2, '0')}`;
  const ultimo = new Date(Date.UTC(ano, Number(mes), 0)).getUTCDate();
  const antes = dia > 1 ? dia - 1 : null, depois = dia < ultimo ? dia + 1 : null;
  const outroMes = String(Number(mes) % 12 + 1).padStart(2, '0');
  const base = clientesDo()[0];
  const fichas = [
    ['Hoje Silva',   noMes(dia)],
    ['Ontem Souza',  antes ? noMes(antes) : null],
    ['Amanhã Lima',  depois ? noMes(depois) : null],
    ['Outro Mês',    `1985-${outroMes}-10`],
    ['Sem Data',     null],
  ];
  for(const [nome, nasc] of fichas){
    bd.clientes.push(Object.assign({}, base, { id: 'tn-' + nome.replace(/\W/g, ''), nome,
      nascimento: nasc, telefone: '11999990000' }));
  }
  // As fichas da demonstração não entram na conta deste teste.
  for(const c of bd.clientes) if(!String(c.id).startsWith('tn-')) c.nascimento = null;
  irPara('agenda');
  return { mes: Number(mes), outroMes: Number(outroMes), temAntes: !!antes, temDepois: !!depois };
});

console.log('\nNo menu');
const aba = await p.evaluate(() => {
  const b = document.querySelector('.aba[data-chave="aniversarios"]');
  return b ? { txt: b.querySelector('.aba-txt').textContent.trim(),
               selo: (b.querySelector('.selo-niver') || {}).textContent || '' } : null;
});
diz(aba && aba.txt === 'Aniversariantes', 'a aba "Aniversariantes" existe no menu, separada do Dashboard');
diz(aba && aba.selo === '1', 'e o selo diz quantos fazem aniversário hoje', JSON.stringify(aba));

await p.locator('.menu-botao').click(); await p.waitForTimeout(300);
await p.locator('.aba[data-chave="aniversarios"]').click(); await p.waitForTimeout(400);
diz(await p.evaluate(() => telaAtual === 'aniversarios' && document.getElementById('tituloTela').textContent.trim() === 'Aniversariantes'),
    'tocar na aba abre a tela, com o título no topo');

console.log('\nO mês corrente (o padrão)');
const mesLista = await p.evaluate(() => [...document.querySelectorAll('#listaNiver .niver-linha')].map(l => ({
  quem: l.querySelector('b').textContent.trim(),
  quando: l.querySelector('.niver-quando').textContent.trim(),
  parabens: !!l.querySelector('button[onclick^="darParabens"]'),
  ficha: !!l.querySelector('button[onclick^="abrirCliente"]'),
  passou: l.classList.contains('niver-passou'), hoje: l.classList.contains('niver-hoje'),
})));
const esperados = ['Ontem Souza', 'Hoje Silva', 'Amanhã Lima'].filter(n =>
  n !== 'Ontem Souza' || cena.temAntes).filter(n => n !== 'Amanhã Lima' || cena.temDepois);
diz(JSON.stringify(mesLista.map(x => x.quem)) === JSON.stringify(esperados),
    'lista quem faz aniversário no mês, em ordem de dia — inclusive quem já fez',
    mesLista.map(x => x.quem).join(', '));
const hojeL = mesLista.find(x => x.quem === 'Hoje Silva');
diz(hojeL && hojeL.hoje && /^hoje · faz 36 anos$/.test(hojeL.quando) || (hojeL && hojeL.hoje && /^hoje/.test(hojeL.quando)),
    'quem faz hoje vem em destaque, com a idade', hojeL && hojeL.quando);
diz(mesLista.every(x => x.ficha), 'toda linha tem "Ver ficha"');
diz(mesLista.filter(x => x.parabens).map(x => x.quem).join() === 'Hoje Silva',
    '"Dar os parabéns" só no dia (a regra do cartão do Dashboard)');
if(cena.temAntes){
  const o = mesLista.find(x => x.quem === 'Ontem Souza');
  diz(o && o.passou && /^foi /.test(o.quando) && /fez \d+ anos/.test(o.quando),
      'quem já fez aparece esmaecido, como "foi…" e "fez N anos"', o && o.quando);
}
const resumo = await p.evaluate(() => document.getElementById('niverResumo').textContent.replace(/\s+/g, ' ').trim());
diz(/sem data de nascimento/.test(resumo), 'avisa quantas fichas estão sem a data', resumo);

console.log('\nOs outros períodos');
await p.click('#niverVistas button:has-text("Hoje")'); await p.waitForTimeout(250);
const soHoje = await p.evaluate(() => [...document.querySelectorAll('#listaNiver .niver-linha b')].map(b => b.textContent.trim()));
diz(soHoje.join() === 'Hoje Silva', '"Hoje" mostra só quem faz hoje', soHoje.join(', '));

await p.click('#niverVistas button:has-text("7 dias")'); await p.waitForTimeout(250);
const semana = await p.evaluate(() => [...document.querySelectorAll('#listaNiver .niver-linha b')].map(b => b.textContent.trim()));
diz(semana[0] === 'Hoje Silva' && !semana.includes('Ontem Souza') && !semana.includes('Outro Mês'),
    '"7 dias" começa em hoje e não traz quem já fez', semana.join(', '));

await p.selectOption('#niverMes', String(cena.outroMes)); await p.waitForTimeout(250);
const outro = await p.evaluate(() => ({
  nomes: [...document.querySelectorAll('#listaNiver .niver-linha b')].map(b => b.textContent.trim()),
  on: [...document.querySelectorAll('#niverVistas button.on')].map(b => b.textContent.trim()),
}));
diz(outro.nomes.join() === 'Outro Mês', 'escolher outro mês na lista mostra os daquele mês', outro.nomes.join(', '));
diz(outro.on.length === 0, 'e nenhum botão de período fica aceso (não é "Este mês")', outro.on.join());

await p.click('#niverVistas button:has-text("Este mês")'); await p.waitForTimeout(250);
diz(await p.evaluate(m => Number(document.getElementById('niverMes').value) === m, cena.mes),
    '"Este mês" volta a lista para o mês de hoje');

console.log('\nO 29 de fevereiro');
const fev = await p.evaluate(() => {
  const ano = Number(hoje().slice(0, 4));
  const bissexto = ano % 4 === 0 && (ano % 100 !== 0 || ano % 400 === 0);
  const base = clientesDo()[0];
  bd.clientes.push(Object.assign({}, base, { id: 'tn-Bissexta', nome: 'Bissexta', nascimento: '1996-02-29' }));
  const l = aniversariantesNoMes(2).find(x => x.chamada === 'Bissexta');
  return { bissexto, dia: l && l.dia.slice(5) };
});
diz(fev.dia === (fev.bissexto ? '02-29' : '02-28'),
    'quem nasceu em 29/02 aparece no dia 28 quando o ano não é bissexto', JSON.stringify(fev));

console.log('\nNo celular');
const medida = await p.evaluate(() => ({
  vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  nomeLargo: (() => { const q = document.querySelector('#listaNiver .niver-quem');
    return q ? Math.round(q.getBoundingClientRect().width) : 0; })(),
}));
diz(medida.vaza === 0, 'a tela não rola para o lado', `sobram ${medida.vaza}px`);
diz(medida.nomeLargo > 250, 'o nome ocupa a linha inteira (os botões vão para baixo)', medida.nomeLargo + 'px');

await p.click('#listaNiver button[onclick^="abrirCliente"]'); await p.waitForTimeout(300);
diz(await p.evaluate(() => document.getElementById('fundo').classList.contains('on')
      && /cliente/i.test(document.getElementById('modalTitulo').textContent)),
    '"Ver ficha" abre a ficha da cliente');
await p.evaluate(() => fecharModal());

diz(erros.length === 0, 'nada disso deu erro de JavaScript', erros.join(' | '));
await nav.close();
console.log(falhas ? `\n✗ ${falhas} de ${ok + falhas} falharam.` : `\n✓ ${ok} passaram, 0 falharam`);
process.exit(falhas ? 1 : 0);
