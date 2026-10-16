/* ===========================================================================
   Celular: o que quebra numa tela de 390px

   Três defeitos que só aparecem no telefone e que ninguém vê testando no
   monitor. Estão aqui porque os três já aconteceram neste projeto:

   1. ROLAGEM LATERAL. Uma tabela de 610px empurrava a página inteira, e o
      cabeçalho ia junto. A causa era `min-width:auto` implícito em item flex.
   2. ALVO DE TOQUE pequeno demais. O dedo tem uns 9mm; botão de 30px erra.
   3. TEXTO MIÚDO. 10px é legível na mesa e não é no braço esticado.

   Precisa do servidor de pé:
       python3 -m http.server 8099 --directory .
       PLAYWRIGHT=.../node_modules/playwright node tests/celular.test.mjs
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, falhas = 0;
const diz = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

const nav = await chromium.launch({ executablePath: CHROMIUM });
// iPhone SE é o piso realista: quem tem telefone pequeno é quem mais precisa.
const ctx = await nav.newContext({ viewport:{width:375,height:667},
                                   isMobile:true, hasTouch:true });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', e => erros.push(e.message));
p.on('console', m => { if(m.type()==='error') erros.push(m.text()); });

const medir = () => p.evaluate(() => ({
  vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
  alvos: [...document.querySelectorAll('button,select,a[href],input:not([type=hidden])')]
    // A caixinha dentro de um <label> é tocada pela frase inteira: o alvo
    // é o label, não o quadradinho de 18px.
    .filter(e => { const r = (e.matches('[type=checkbox],[type=radio]') && e.closest('label')
                              || e).getBoundingClientRect();
      return r.width > 0 && r.height > 0 && (r.height < 40 || r.width < 40); })
    .map(e => e.tagName.toLowerCase() + '.' + (e.className||'').toString().split(' ')[0]),
  miudo: [...document.querySelectorAll('body *')]
    .filter(e => e.children.length === 0 && e.textContent.trim()
              && e.offsetParent !== null
              && parseFloat(getComputedStyle(e).fontSize) < 11)
    .map(e => e.tagName.toLowerCase() + ' @' + getComputedStyle(e).fontSize),
}));

/* ── NADA PODE COBRIR O BOTÃO DO MENU ─────────────────────────────────────
   No celular a lateral é gaveta, e a gaveta abre por um botão só. Coberto,
   não há segunda porta: a pessoa fica presa na aba em que estiver.

   Aconteceu de verdade, e por um caminho que ninguém procuraria: o cartão de
   foto montava a classe com o NOME DO CAMPO (`class="foto-previa fundo"`), e
   já existia um `.fundo` global nesta página — o véu do modal,
   `position:fixed; inset:0`. A prévia do campo novo virou uma camada fixa
   cobrindo o canto de cima da tela.

   A suíte pegou, mas só porque o clique seguinte falhou por timeout — trinta
   segundos para dizer "algo está por cima". Esta pergunta responde na hora, e
   diz o nome de quem está ali. */
console.log('\nO app do salão, em 375px');
// A comanda e o caixa estão desligados na plataforma; aqui a aba Caixa é medida.
await p.goto(BASE + 'app.html?demo=1&comanda=1');
await p.waitForTimeout(900);

const abas = ['Agenda','Caixa','Relatórios','Clientes','Serviços','Equipe',
              'Meu negócio','Plano'];
for(const aba of abas){
  if(aba !== 'Agenda'){
    await p.locator('.menu-botao').click();
    await p.waitForTimeout(300);
    await p.locator('.aba', { hasText: aba }).click();
    await p.waitForTimeout(450);
  }
  // Antes de medir a aba: o botão que leva à PRÓXIMA continua alcançável?
  const cobrindo = await p.evaluate(() => {
    const b = document.querySelector('.menu-botao');
    if(!b) return null;
    const c = b.getBoundingClientRect();
    const emCima = document.elementFromPoint(c.x + c.width/2, c.y + c.height/2);
    return (emCima && (emCima === b || b.contains(emCima))) ? null
         : (emCima ? (emCima.tagName + '.' + String(emCima.className)) : 'nada');
  });
  diz(cobrindo === null,
    `${aba}: o botão do menu não está coberto por nada`, 'quem está ali: ' + cobrindo);

  const r = await medir();
  diz(r.vaza === 0, `${aba}: a página não rola para o lado`,
      `sobram ${r.vaza}px — quase sempre é min-width:auto em item flex`);
  diz(r.alvos.length === 0, `${aba}: nenhum alvo de toque abaixo de 40px`,
      r.alvos.join(', '));
  diz(r.miudo.length === 0, `${aba}: nenhum texto abaixo de 11px`,
      [...new Set(r.miudo)].join(', '));
}

console.log('\nA tabela vira cartão, e o cartão traz os rótulos');
await p.locator('.menu-botao').click(); await p.waitForTimeout(300);
await p.locator('.aba', { hasText: 'Serviços' }).click(); await p.waitForTimeout(450);
const cartao = await p.evaluate(() => {
  const tr = document.querySelector('.tabela tbody tr');
  if(!tr) return null;
  const td = [...tr.children];
  return {
    empilhado: getComputedStyle(tr).display === 'block',
    cabecaOculta: getComputedStyle(document.querySelector('.tabela thead')).display === 'none',
    // toda célula menos a primeira (o título) e a de ações precisa de rótulo
    semRotulo: td.slice(1, -1).filter(e => !e.getAttribute('data-r')).length,
    rotulos: td.slice(1, -1).map(e => e.getAttribute('data-r')),
  };
});
diz(cartao && cartao.empilhado, 'a linha da tabela empilha como cartão');
diz(cartao && cartao.cabecaOculta, 'o cabeçalho da tabela some — o rótulo foi para a célula');
diz(cartao && cartao.semRotulo === 0,
    `toda célula tem o nome da coluna (${(cartao?.rotulos||[]).join(', ')})`,
    `${cartao?.semRotulo} sem rótulo`);

/* ── A TABELINHA DENTRO DA JANELA TAMBÉM ──────────────────────────────────
   O rótulo das colunas só era posto nas tabelas das telas. A de "quando é
   diferente com alguém" (no serviço e no produto) e a jornada do
   profissional moram numa janela — no celular viravam caixas soltas, "0" e
   "—" sem dizer de quê, e a última coluna esticada na largura toda. */
console.log('\nA tabelinha de preencher, dentro da janela');
for(const [nome, abrir] of [
  ['serviço (preço e comissão por pessoa)', () => abrirServico(doSalao(bd.servicos)[0].id)],
  ['profissional (jornada)',                () => abrirProf(doSalao(bd.profissionais).filter(x => x.ativo)[0].id)],
]){
  await p.evaluate(`(${abrir})()`);
  await p.waitForTimeout(400);
  const j = await p.evaluate(() => {
    const t = [...document.querySelectorAll('#modalCorpo table.tabela')]
      .find(x => x.querySelector('thead th') && x.querySelector('tbody input'));
    if(!t) return null;
    const tr = t.querySelector('tbody tr');
    const campos = [...tr.querySelectorAll('td')].filter(td => td.querySelector('input'));
    const larg = campos.map(td => Math.round(td.querySelector('input').getBoundingClientRect().width));
    return {
      semRotulo: campos.filter(td => !td.getAttribute('data-r')
        || getComputedStyle(td, '::before').content === 'none').length,
      rotulos: campos.map(td => td.getAttribute('data-r')),
      larg,
      mesma: Math.max(...larg) - Math.min(...larg) <= 1,
      vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    };
  });
  diz(j && j.semRotulo === 0, `${nome}: cada caixa diz de que é (${(j?.rotulos||[]).join(', ')})`,
      `${j?.semRotulo} caixa(s) sem rótulo`);
  diz(j && j.mesma, `${nome}: todas as caixas da mesma largura — a última não estica`,
      'larguras: ' + (j?.larg||[]).join(', '));
  diz(j && j.vaza === 0, `${nome}: a página não rola para o lado`);
  await p.evaluate(() => fecharModal());
  await p.waitForTimeout(200);
}

/* ── O QUE A VARREDURA DE LAYOUT ACHOU ────────────────────────────────────
   Cada item foi visto num print de celular, um por um, e cada um já
   aconteceu: estão aqui para não voltar. */
console.log('\nA varredura de layout: caixinhas, cores, campos e cartões');
await p.evaluate(() => abrirProf(doSalao(bd.profissionais).filter(x => x.ativo)[0].id));
await p.waitForTimeout(400);
const prof = await p.evaluate(() => {
  const caixas = [...document.querySelectorAll('#modalCorpo label.check input[type=checkbox]')]
    .map(e => { const r = e.getBoundingClientRect(); return [Math.round(r.width), Math.round(r.height)]; });
  const cor = document.getElementById('qCor');
  const p = doSalao(bd.profissionais).filter(x => x.ativo)[0];
  const ajuda = document.getElementById('qTelAjuda');
  const fotos = [...document.querySelectorAll('#modalCorpo .foto-acoes .btn')].map(b => {
    const r = b.getBoundingClientRect(), rg = document.createRange(); rg.selectNodeContents(b);
    const t = [...rg.getClientRects()].filter(x => x.width > 2)[0] || r;
    return Math.round((t.top + t.height / 2) - (r.top + r.height / 2)); });
  return {
    caixas,
    valores: [...cor.options].map(o => o.value),
    marcada: cor.value.toLowerCase(), atual: corDoProf(p).toLowerCase(),
    ajuda: ajuda ? parseFloat(getComputedStyle(ajuda).fontSize) : null,
    fotos,
  };
});
diz(prof.caixas.length >= 3 && prof.caixas.every(([w, h]) => w <= 24 && h <= 24),
    'Editar profissional: as caixinhas "Avisar quando…" têm tamanho de caixinha',
    'largura × altura: ' + prof.caixas.map(x => x.join('×')).join(', '));
diz(prof.valores.length > 0 && prof.valores.every(v => /^#[0-9a-f]{6}$/i.test(v)),
    'a lista "Cor na agenda" grava uma cor de verdade (era "#C8A33C,Dourado")',
    prof.valores.join(' | '));
diz(prof.marcada === prof.atual,
    'e vem marcada na cor que a coluna mostra hoje: salvar sem mexer não troca a cor',
    `marcada ${prof.marcada}, coluna ${prof.atual}`);
diz(prof.ajuda !== null && prof.ajuda <= 13.5, 'o texto de ajuda é miúdo, não do tamanho do texto normal',
    'font-size: ' + prof.ajuda);
diz(prof.fotos.length === 2 && prof.fotos.every(d => Math.abs(d) <= 2),
    '"Escolher" e "Remover" com o texto no meio do botão, os dois na mesma altura',
    'desvio do centro: ' + prof.fotos.join(', '));
await p.evaluate(() => fecharModal());

await p.evaluate(() => abrirCliente(null));
await p.waitForTimeout(300);
const larguras = await p.evaluate(() => [...document.querySelectorAll('#modalCorpo .campo > input:not([type=checkbox]), #modalCorpo .campo > .data-caixa')]
  .map(e => Math.round(e.getBoundingClientRect().width)));
diz(larguras.length >= 4 && Math.max(...larguras) - Math.min(...larguras) <= 1,
    'Novo cliente: os campos empilhados têm todos a mesma largura', larguras.join(', '));
const vaos = await p.evaluate(() => {
  const cs = [...document.querySelectorAll('#modalCorpo .campo')].filter(c => c.querySelector(':scope > input, :scope > .data-caixa'));
  const v = [];
  for(let i = 1; i < cs.length; i++) v.push(Math.round(cs[i].getBoundingClientRect().top - cs[i - 1].getBoundingClientRect().bottom));
  return v;
});
diz(vaos.length >= 3 && Math.max(...vaos) - Math.min(...vaos) <= 2,
    'e o espaço entre eles é sempre o mesmo (a dupla somava o gap e a margem)', vaos.join(', '));
await p.evaluate(() => fecharModal());

await p.evaluate(() => { const a = agendaDoSalao()[0]; if(a) abrirDetalhe(a.id); });
await p.waitForTimeout(300);
const pares = await p.evaluate(() => {
  const t = document.querySelector('#modalCorpo table.tabela[data-pares]');
  return t ? { disp: getComputedStyle(t).display, linhas: t.querySelectorAll('tbody tr').length,
               td: getComputedStyle(t.querySelector('tbody td')).display } : null;
});
diz(pares && pares.disp === 'table' && pares.td === 'table-cell',
    'o detalhe do atendimento é uma tabela "rótulo | valor" num cartão só — não um cartão por linha',
    JSON.stringify(pares));
await p.evaluate(() => fecharModal());

await p.evaluate(() => abrirGaveta());
await p.waitForTimeout(300);
const gaveta = await p.evaluate(() => ({
  pe: [...document.querySelectorAll('#modalPe .btn')].map(b => b.textContent.trim() + (b.classList.contains('btn-p') ? '*' : '')),
  noCorpo: document.querySelectorAll('#modalCorpo button').length,
  campo: !!document.querySelector('#modalCorpo .campo #gAbertura'),
}));
diz(gaveta.pe.join(',') === 'Cancelar,Abrir*' && gaveta.noCorpo === 0 && gaveta.campo,
    'Abrir o caixa: o campo no padrão, e os botões no rodapé da janela (o "Abrir" é o principal)',
    JSON.stringify(gaveta));
await p.evaluate(() => fecharModal());

await p.locator('.menu-botao').click(); await p.waitForTimeout(300);
await p.locator('.aba', { hasText: 'Clientes' }).click(); await p.waitForTimeout(450);
const lista = await p.evaluate(() => {
  const barra = document.querySelector('#tela-clientes .barra'), busca = document.getElementById('buscaCliente');
  const trs = [...document.querySelectorAll('#tela-clientes .tabela tbody tr')];
  const ultimo = trs[trs.length - 1];
  return {
    recuo: Math.round(busca.getBoundingClientRect().left - barra.getBoundingClientRect().left),
    riscos: ultimo ? [...ultimo.children].slice(1, -1).map(td => getComputedStyle(td).borderBottomWidth) : [],
  };
});
diz(lista.recuo === 0, 'Clientes: a busca começa no canto, sem meia tela vazia à esquerda',
    `recuo de ${lista.recuo}px`);
diz(lista.riscos.length > 0 && lista.riscos.every(w => parseFloat(w) >= 1),
    'o último cartão da lista tem as linhas entre os campos, como os outros', lista.riscos.join(', '));

console.log('\nA agenda rola dentro dela mesma');
await p.locator('.menu-botao').click(); await p.waitForTimeout(300);
await p.locator('.aba', { hasText: 'Agenda' }).click(); await p.waitForTimeout(450);
const grade = await p.evaluate(() => {
  const w = document.querySelector('.grade-wrap');
  return { rola: w.scrollWidth > w.clientWidth + 1,
           overflow: getComputedStyle(w).overflowX,
           pagina: document.documentElement.scrollWidth
                 - document.documentElement.clientWidth };
});
diz(grade.rola, 'a grade tem mais coluna do que cabe — é o caso que interessa');
diz(grade.overflow === 'auto' || grade.overflow === 'scroll',
    'e ela mesma rola', 'overflow-x: ' + grade.overflow);
diz(grade.pagina === 0, 'sem arrastar a página junto');

console.log('\nO app do cliente e o cadastro');
// `demo=1` em todas: estas medidas são de LAYOUT, e layout não deve depender
// de o banco estar no ar. Sem isso, a suíte de celular passaria a exigir
// internet e rede boa para dizer se um botão tem 44px.
for(const [url, nome] of [['agendar.html?salao=studio-bella&demo=1','vitrine do cliente'],
                          ['criar.html?demo=1','cadastro do dono']]){
  await p.goto(BASE + url); await p.waitForTimeout(900);
  const r = await medir();
  diz(r.vaza === 0, `${nome}: não rola para o lado`, `sobram ${r.vaza}px`);
  diz(r.alvos.length === 0, `${nome}: nenhum alvo abaixo de 40px`, r.alvos.join(', '));
}

/* A loja do link: a lupa da busca (o `background:… !important` do estilo
   geral a apagava, e sobrava o recuo vazio) e o "Adicionar" com margem
   interna (encostava nas bordas). */
await p.goto(BASE + 'agendar.html?salao=studio-bella&demo=1'); await p.waitForTimeout(900);
await p.evaluate(() => irPara('loja')); await p.waitForTimeout(600);
const loja = await p.evaluate(() => {
  const b = document.getElementById('buscaProduto'), a = document.querySelector('#listaProdutos .loja-add');
  return { lupa: b ? getComputedStyle(b).backgroundImage : '',
           add: a ? { pad: parseFloat(getComputedStyle(a).paddingRight), sobra: a.scrollWidth - a.clientWidth } : null };
});
diz(/svg/.test(loja.lupa), 'loja do link: a busca tem a lupa dentro', loja.lupa.slice(0, 60));

/* ⚠ FOTO EM PÉ NUMA CAIXA QUADRADA. Relatado com print: o logo (uma selfie)
   aparecia no link só com o alto da foto — a caixa é uma grade, e numa grade
   o `height:100%` da imagem não segura: ela ficava 104×208 num selo de 104.
   Na prévia do painel aparecia certo, e era essa a diferença que a dona via.
   A mesma coisa nas miniaturas do painel (logo, profissional, serviço). */
const FOTO_EM_PE = `(() => { const c = document.createElement('canvas'); c.width = 120; c.height = 240;
  const g = c.getContext('2d'); g.fillStyle = '#c33'; g.fillRect(0, 0, 120, 240); return c.toDataURL(); })()`;
const caixaCheia = sel => p.evaluate(sel => [...document.querySelectorAll(sel)].map(b => {
  const im = b.querySelector(':scope > img'); if(!im) return null;
  const rb = b.getBoundingClientRect(), ri = im.getBoundingClientRect();
  return Math.round(ri.height) <= Math.round(rb.height) + 1 ? 'ok' : `${Math.round(rb.width)}x${Math.round(rb.height)} com foto de ${Math.round(ri.width)}x${Math.round(ri.height)}`;
}).filter(Boolean), sel);
await p.evaluate(`(() => { salao.logo = ${FOTO_EM_PE}; irPara('capa'); })()`); await p.waitForTimeout(600);
const selo = await caixaCheia('.marca-selo');
diz(selo.length === 1 && selo[0] === 'ok', 'link: logo em foto em pé cabe no selo (o cover centraliza, não mostra só o alto)', selo.join(', '));
diz(!loja.add || (loja.add.pad >= 10 && loja.add.sobra <= 0),
    'e o "Adicionar" tem folga dos dois lados, sem a última letra colada na borda', JSON.stringify(loja.add));

await p.goto(BASE + 'app.html?demo=1&comanda=1'); await p.waitForTimeout(900);
await p.evaluate(`(() => { const f = ${FOTO_EM_PE}; acharSalao(salaoAtual).logo = f;
  doSalao(bd.servicos).forEach(s => s.foto = f); doSalao(bd.profissionais).forEach(x => x.foto = f); })()`);
const miniaturas = [];
await p.evaluate(() => irPara('servicos')); await p.waitForTimeout(400);
miniaturas.push(...await caixaCheia('.sv-mini'));
await p.evaluate(() => irPara('equipe')); await p.waitForTimeout(400);
miniaturas.push(...await caixaCheia('.eq-rosto'));
await p.evaluate(() => abrirProf(doSalao(bd.profissionais)[0].id)); await p.waitForTimeout(400);
miniaturas.push(...await caixaCheia('.foto-previa'));
await p.evaluate(() => fecharModal());
diz(miniaturas.length >= 3 && miniaturas.every(x => x === 'ok'),
    'painel: as miniaturas com foto em pé (serviço, equipe, profissional) cabem na caixa',
    miniaturas.filter(x => x !== 'ok').join(', '));

diz(erros.length === 0, 'nenhum erro de JavaScript em nenhuma tela', erros.join(' | '));

await nav.close();
console.log(falhas
  ? `\n✗ ${falhas} falha(s) em ${ok + falhas} verificações.`
  : `\n✓ ${ok} verificações de celular.`);
process.exit(falhas ? 1 : 0);
