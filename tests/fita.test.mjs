/* ===========================================================================
   AgendaPro — a fita do carrinho, em metal e configurável

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/fita.test.mjs

   O pedido: "a barra do carrinho metálica, com brilho configurável — ligado
   ou desligado, intensidade, velocidade da animação, cor, arredondamento,
   estática ou animada".

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
   Cinco escolhas, e cada uma atravessa CINCO PARADAS até chegar na tela:

       painel grava → vitrine() devolve → bdDaVitrine() copia →
       aplicarFita() escreve a variável → o CSS obedece

   Esquecer uma parada não dá erro em lugar nenhum. O dono escolhe, o painel
   grava, a prévia obedece — e a página da cliente continua igual. Foi assim
   que o `cartoes` se perdeu uma vez, e é o defeito que este arquivo existe
   para pegar.

   ⚠ E MEDE O QUE NÃO PODE MUDAR, que é onde o erro chega calado:
     · sem escolha nenhuma, a fita é o metal de fábrica — nenhum salão de hoje
       acorda com a página diferente;
     · a cor sai da personalização, e nunca de uma cor escrita no CSS;
     · o interruptor GERAL de brilho continua ganhando do interruptor da fita.
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

function novaAba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(path.join(RAIZ,'dados.js'),'utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`fita-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa da Fita',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'19:00' });
}
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:90, ativo:true, aceitaOnline:true });
const prod = await dona.inserir('produtos', { salaoId: SALAO,
  nome:'Shampoo', preco:45, custo:20, ativo:true, vendaOnline:true });

/* ⚠ A COR NÃO É A PADRÃO DO APP. Com o azul de fábrica, "respeitou a cor do
   salão" passaria por acidente — inclusive num código que a ignorasse. */
const COR = '#B45309';
await dona.atualizar('saloes', SALAO, {
  whatsapp:'(11) 98111-3251',
  cfg:{ diasLiberados:30, cor: COR } });
ok('casa criada, com um produto e a cor dela');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* Abre a página já com o produto no carrinho — é a única condição em que a
   fita existe. O `localStorage` é onde o carrinho mora de verdade, então
   semeá-lo é entrar pela porta, e não empurrar estado pela janela. */
async function comFita(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                     isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  /* ⚠ A CHAVE LEVA O ID DO SALÃO, e não o slug — ver `chaveDoCarrinho()` no
     agendar.html. Escrevi o slug primeiro: o carrinho nascia vazio, a fita
     nunca aparecia, e o teste morria no `waitForFunction` sem dizer por quê. */
  await p.addInitScript(([id, salaoId]) => {
    localStorage.setItem('agendapro.carrinho.' + salaoId, JSON.stringify({ [id]: 2 }));
  }, [prod.id, SALAO]);
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => {
    const f = document.getElementById('carrinhoFita');
    return f && f.style.display !== 'none' && f.innerHTML.trim() !== '';
  }, null, { timeout: 15000 });
  return p;
}

const medir = p => p.evaluate(() => {
  const f = document.getElementById('carrinhoFita');
  const e = getComputedStyle(f);
  const luz = getComputedStyle(f, '::after');
  const raiz = getComputedStyle(document.documentElement);
  return {
    existe: !!f,
    // `background-image` traz o gradiente resolvido; `none` = chapada.
    temMetal: e.backgroundImage !== 'none',
    fundo: e.backgroundColor,
    raio: e.borderTopLeftRadius,
    brilhoAnim: luz.animationName,
    brilhoDur: luz.animationDuration,
    brilhoVisivel: luz.display !== 'none',
    varLuz: raiz.getPropertyValue('--fita-luz').trim(),
    varTempo: raiz.getPropertyValue('--fita-tempo').trim(),
    varCor: raiz.getPropertyValue('--fita-cor').trim(),
    varRaio: raiz.getPropertyValue('--fita-raio').trim(),
    acao: raiz.getPropertyValue('--acao').trim().toUpperCase(),
    // O texto tem que ficar ACIMA da faixa de luz, senão ele pisca.
    textoAcima: getComputedStyle(f.querySelector('.cf-resumo')).zIndex,
  };
});

const escolher = async (extra) => {
  const sl = (await dona.lista('saloes', { id: SALAO }))[0];
  await dona.atualizar('saloes', SALAO,
    { cfg: Object.assign({}, sl.cfg, extra) });
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — DE FÁBRICA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · Sem escolha nenhuma, a fita é o metal de fábrica');

let p = await comFita();
let m = await medir(p);
console.log('      ' + JSON.stringify(m));
verdade('a fita está na tela', m.existe);
verdade('e ela é metálica, não chapada', m.temMetal);
igual('o metal é o médio, que é o do botão de agendar', m.varLuz, '30%');
igual('o brilho está animado', m.brilhoAnim, 'brilho-metal');
igual('no ritmo de sempre, 5.2s', m.brilhoDur, '5.2s');
/* ⚠ PADRÃO NÃO ESCREVE VARIÁVEL. Escrever o mesmo número criaria um estado
   "escolhido" onde não houve escolha, e quem mexer no padrão amanhã mexeria
   num lugar e não em dois. */
igual('a velocidade padrão NÃO escreve variável', m.varTempo, '');
igual('nem a cor', m.varCor, '');
igual('nem o canto', m.varRaio, '');
igual('o canto continua reto', m.raio, '0px');
verdade('e o texto fica acima da faixa de luz, para não piscar',
  m.textoAcima === '1', m.textoAcima);
await p.context().close();

/* ══════════════════════════════════════════════════════════════════════════
   2 — AS CINCO ESCOLHAS ATRAVESSAM
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · O dono escolhe, e a escolha chega na tela da cliente');

await escolher({ fitaMetal:'forte' });
p = await comFita(); m = await medir(p);
igual('metal forte chega como 46%', m.varLuz, '46%');
verdade('e a fita continua metálica', m.temMetal);
await p.context().close();

await escolher({ fitaMetal:'chapado' });
p = await comFita(); m = await medir(p);
/* ⚠ CHAPADO É A AUSÊNCIA DA VARIÁVEL, e não um valor dela. Sem `--fita-luz`
   o `color-mix` fica com argumento vazio e o navegador DESCARTA o gradiente
   inteiro — sobra a cor lisa. É o mesmo mecanismo que protege o navegador
   antigo, usado de propósito. */
igual('chapado não escreve luz nenhuma', m.varLuz, '');
verdade('e a fita fica lisa', !m.temMetal, m.fundo);
await p.context().close();

await escolher({ fitaMetal:'media', fitaTempo:'rapida' });
p = await comFita(); m = await medir(p);
igual('a velocidade rápida chega', m.brilhoDur, '2.8s');
await p.context().close();

await escolher({ fitaTempo:'lenta' });
p = await comFita(); m = await medir(p);
igual('e a devagar também', m.brilhoDur, '8.5s');
await p.context().close();

await escolher({ fitaTempo:'media', fitaBorda:'redonda' });
p = await comFita(); m = await medir(p);
igual('o canto bem redondo chega', m.raio, '18px');
await p.context().close();

await escolher({ fitaBorda:'reta', fitaCor:'#1F6F4A' });
p = await comFita(); m = await medir(p);
verdade('a cor própria da fita chega',
  m.varCor.toUpperCase() === '#1F6F4A', m.varCor);
/* ⚠ E CHEGA NO PIXEL, não só na variável. Ler `--fita-cor` prova que o
   JavaScript escreveu; prova nenhuma de que o CSS usou. Trocar o
   `var(--fita-cor, var(--acao))` do `.carrinho-fita` por um `var(--acao)`
   seco deixa a variável escrita e a barra na cor errada — e a verificação de
   cima passa inteira. `backgroundColor` é a cor chapada de reserva, que é
   exatamente a que o gradiente usa como base. */
igual('e ela é a cor que a barra realmente pinta', m.fundo, 'rgb(31, 111, 74)');
/* ⚠ E NÃO ARRASTA A COR DO BOTÃO JUNTO. São duas escolhas separadas; se a
   fita mexesse em `--acao`, escolher a cor dela repintaria a página inteira.

   Não há mutação para esta linha no `mutacoes-fita.sh`, e o motivo é bom: o
   `aplicarModo()` — que chama o `aplicarFita()` — roda ANTES do
   `p('--acao', cor)` do `aplicarAparencia()`, e os dois escrevem no MESMO
   bloco de estilo embutido. Ali o `!important` não protege: um `setProperty`
   posterior sem prioridade simplesmente substitui o valor. Qualquer
   vazamento escrito dentro do `aplicarFita()` é apagado três linhas depois.

   A verificação fica porque a regra é real e vale um centavo; o que não
   existe é jeito de quebrá-la de dentro da função. */
igual('e a cor do botão continua a do salão', m.acao, COR.toUpperCase());
await p.context().close();

/* ══════════════════════════════════════════════════════════════════════════
   3 — ESTÁTICA OU ANIMADA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · Parada, e o interruptor geral por cima');

await escolher({ fitaCor:null, fitaBrilho:false });
p = await comFita(); m = await medir(p);
/* ⚠ `display:none` E NÃO `opacity:0`. Com opacidade zero a animação continua
   rodando — trabalho de desenho a cada quadro, no celular de alguém, para não
   mostrar nada. */
verdade('com o brilho parado, a faixa de luz some de vez', !m.brilhoVisivel);
verdade('mas a fita continua em metal', m.temMetal);
await p.context().close();

/* ⚠ O INTERRUPTOR GERAL GANHA. São duas perguntas — "quero brilho nesta
   barra?" e "quero brilho em lugar nenhum?" — e se a segunda perdesse, o
   interruptor geral viraria mentira na tela de quem o desligou. */
await escolher({ fitaBrilho:true, brilho:false });
p = await comFita(); m = await medir(p);
igual('com o brilho GERAL desligado, a fita não anima',
  m.brilhoAnim, 'none');
await p.context().close();

await escolher({ brilho:true });

/* ⚠ LIXO NO cfg NÃO PODE DERRUBAR A VITRINE, e esta chave é a mais exposta
   das cinco: é a única booleana, e booleana é a que alguém grava como texto
   sem perceber. `'talvez'::boolean` LEVANTA no Postgres — não devolve nulo — e
   quem cai é a `vitrine()`, que é a única porta da página da cliente.

   Faltava esta verificação: a mutação que devolvia o `::boolean` sobreviveu,
   porque nenhum teste punha um valor estranho aqui. */
await escolher({ fitaBrilho:'talvez' });
let vi = null;
try{ vi = await dona.chamar('vitrine', { p_slug: SLUG }); }
catch(e){ nao('com lixo no fitaBrilho, a vitrine ainda responde',
              'a vitrine LEVANTOU: ' + e.message); }
if(vi){
  const sal = (Array.isArray(vi) ? vi[0] : vi).salao;
  ok('com lixo no fitaBrilho, a vitrine ainda responde');
  igual('e o lixo deixa o brilho LIGADO, que é o lado seguro',
        sal.fitaBrilho, true);
}
await escolher({ fitaBrilho:' NÃO ' });
vi = await dona.chamar('vitrine', { p_slug: SLUG });
igual('mas " NÃO " com espaço e acento desliga mesmo',
  (Array.isArray(vi) ? vi[0] : vi).salao.fitaBrilho, false);
await escolher({ fitaBrilho:true });

igual('nenhum erro de página em nenhuma combinação', erros, []);

/* ══════════════════════════════════════════════════════════════════════════
   4 — O PAINEL: RÉGUAS, PRÉVIA E GRAVAÇÃO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4 · O painel escolhe, mostra na prévia, e grava');

const ctxP = await nav.newContext({ viewport:{ width:1360, height:900 } });
const pa = await ctxP.newPage();
const errosP = [];
pa.on('pageerror', e => errosP.push(e.message));
pa.on('dialog', async d => { await d.accept(); });
await pa.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await pa.goto(BASE + '/app.html');
await pa.waitForTimeout(4000);
await pa.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await pa.waitForTimeout(1200);
await pa.click('#abas .aba[data-chave="salao"]');
await pa.waitForTimeout(600);
await pa.evaluate(() => trocarAbaSalao('aparencia'));
await pa.waitForTimeout(900);

const reguas = await pa.evaluate(() => ({
  metal: document.querySelectorAll('#reguaFitaMetal button').length,
  borda: document.querySelectorAll('#reguaFitaBorda button').length,
  brilho: document.querySelectorAll('#reguaFitaBrilho button').length,
  tempo: document.querySelectorAll('#reguaFitaTempo button').length,
  cor: !!document.getElementById('fitaCor'),
  metalOn: (document.querySelector('#reguaFitaMetal button.on') || {}).textContent,
  previa: !!document.querySelector('#previaFone .fone-fita'),
}));
console.log('      ' + JSON.stringify(reguas));
igual('as quatro opções de metal', reguas.metal, 4);
igual('as três de canto', reguas.borda, 3);
igual('animado ou parado', reguas.brilho, 2);
igual('e três velocidades', reguas.tempo, 3);
verdade('o seletor de cor está lá', reguas.cor);
igual('de fábrica, o metal marcado é o Média', reguas.metalOn, 'Média');
/* ⚠ A PRÉVIA É O PONTO. Escolher metal e brilho sem ver onde cai é escolher
   no escuro: o dono só descobriria abrindo o próprio link no celular, com um
   produto no carrinho — três passos para conferir uma escolha de dois
   segundos. */
verdade('e a fita aparece na prévia do celular', reguas.previa);

/* ⚠ A VELOCIDADE FICA CINZA COM O BRILHO PARADO. Régua viva que não muda nada
   é a forma mais rápida de fazer alguém achar que a tela está quebrada. */
await pa.evaluate(() => {
  Array.from(document.querySelectorAll('#reguaFitaBrilho button'))
    .find(b => b.textContent.trim() === 'Parado').click();
});
await pa.waitForTimeout(300);
const paradoNaTela = await pa.evaluate(() => ({
  tempoCinza: Array.from(document.querySelectorAll('#reguaFitaTempo button'))
    .every(b => b.disabled),
  previaBrilho: document.querySelector('#previaFone .fone-fita')
    .classList.contains('com-brilho'),
  frase: (document.getElementById('explicaFitaBrilho') || {}).textContent || '',
}));
console.log('      ' + JSON.stringify(paradoNaTela));
verdade('com o brilho parado, a velocidade fica cinza', paradoNaTela.tempoCinza);
verdade('a prévia para junto', !paradoNaTela.previaBrilho);
verdade('e a frase explica por que a velocidade não vale',
  /só volta a valer/i.test(paradoNaTela.frase), paradoNaTela.frase);

// E agora escolhe de verdade e salva.
await pa.evaluate(() => {
  Array.from(document.querySelectorAll('#reguaFitaBrilho button'))
    .find(b => b.textContent.trim() === 'Animado').click();
  Array.from(document.querySelectorAll('#reguaFitaMetal button'))
    .find(b => b.textContent.trim() === 'Forte').click();
  Array.from(document.querySelectorAll('#reguaFitaBorda button'))
    .find(b => b.textContent.trim() === 'Bem redondo').click();
  escolherFitaCor('#1f6f4a');
});
await pa.waitForTimeout(300);
const previaDepois = await pa.evaluate(() => {
  const f = document.querySelector('#previaFone .fone-fita');
  return { metal: f.getAttribute('data-metal'), borda: f.getAttribute('data-borda'),
           cor: (f.getAttribute('style') || '') };
});
igual('a prévia acompanha o metal forte', previaDepois.metal, 'forte');
igual('e o canto redondo', previaDepois.borda, 'redonda');
verdade('e a cor própria', /1f6f4a/i.test(previaDepois.cor), previaDepois.cor);

await pa.evaluate(() => salvarAparencia());
await pa.waitForTimeout(2000);
const g = ((await dona.lista('saloes', { id: SALAO }))[0].cfg || {});
igual('o metal chega ao banco', g.fitaMetal, 'forte');
igual('o canto também', g.fitaBorda, 'redonda');
igual('a cor também', g.fitaCor, '#1f6f4a');
igual('e o brilho animado', g.fitaBrilho, true);
/* ⚠ E O RESTO DA APARÊNCIA NÃO FOI JUNTO. `sl.cfg = Object.assign({}, sl.cfg,
   {...})` é o que impede isso, e é fácil de quebrar numa limpeza. */
igual('a cor da marca continua intacta', g.cor, COR);

// E a escolha sobrevive ao recarregar.
await pa.reload();
await pa.waitForTimeout(4000);
await pa.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await pa.waitForTimeout(900);
await pa.click('#abas .aba[data-chave="salao"]');
await pa.waitForTimeout(500);
await pa.evaluate(() => trocarAbaSalao('aparencia'));
await pa.waitForTimeout(800);
const depois = await pa.evaluate(() => ({
  metal: (document.querySelector('#reguaFitaMetal button.on') || {}).textContent,
  cor: (document.getElementById('fitaCor') || {}).value,
  ajuda: (document.getElementById('fitaCorAjuda') || {}).textContent,
}));
igual('ao reabrir, o metal forte continua marcado', depois.metal, 'Forte');
/* O `<input type="color">` devolve tudo em minúscula — o navegador normaliza,
   e comparar com maiúscula reprova um código certo. */
igual('a cor continua no seletor', (depois.cor || '').toLowerCase(), '#1f6f4a');
verdade('e a tela diz que a cor é própria, não herdada',
  /própria/i.test(depois.ajuda), depois.ajuda);

/* ══════════════════════════════════════════════════════════════════════════
   5 — A PRÉVIA NÃO PODE MENTIR
   ══════════════════════════════════════════════════════════════════════════ */
secao('5 · Os números da prévia batem com os da página');

/* ⚠ PRÉVIA QUE MENTE É PIOR QUE PRÉVIA NENHUMA.

   São duas folhas de regras diferentes — a página lê variáveis escritas pelo
   JavaScript dela, a prévia lê `data-` escritos pelo painel — e nada obriga
   os números a serem os mesmos. Se a prévia mostrar menos metal do que a
   página vai dar, o dono escolhe "forte", acha pouco, escolhe de novo, e o
   link dele sai com o dobro do que ele queria.

   Comparar os dois lados de verdade é a única forma de saber. Medir só o
   `data-metal` do elemento — que foi o que eu fiz primeiro — prova que o
   atributo chegou, e não que ele vale a mesma coisa dos dois lados: a
   mutação que trocou o número da prévia sobreviveu a isso. */
for(const [escolha, esperado] of [['suave','18%'], ['media','30%'], ['forte','46%']]){
  await pa.evaluate((e) => { aparencia.fitaMetal = e; pintarAparencia(); }, escolha);
  await pa.waitForTimeout(200);
  const naPrevia = await pa.evaluate(() => getComputedStyle(
    document.querySelector('#previaFone .fone-fita')).getPropertyValue('--ff-luz').trim());
  igual(`a prévia do metal "${escolha}" usa o mesmo número da página`,
        naPrevia, esperado);
}
for(const [escolha, esperado] of [['lenta','8.5s'], ['rapida','2.8s']]){
  await pa.evaluate((e) => { aparencia.fitaTempo = e; pintarAparencia(); }, escolha);
  await pa.waitForTimeout(200);
  const naPrevia = await pa.evaluate(() => getComputedStyle(
    document.querySelector('#previaFone .fone-fita')).getPropertyValue('--ff-tempo').trim());
  igual(`a prévia da velocidade "${escolha}" usa o mesmo tempo da página`,
        naPrevia, esperado);
}
const RAIO_PREVIA = { suave:'10px', redonda:'18px', reta:'0px' };
for(const escolha of ['suave', 'redonda', 'reta']){
  await pa.evaluate((e) => { aparencia.fitaBorda = e; pintarAparencia(); }, escolha);
  await pa.waitForTimeout(200);
  const naPrevia = await pa.evaluate(() => getComputedStyle(
    document.querySelector('#previaFone .fone-fita')).borderTopLeftRadius);
  igual(`a prévia do canto "${escolha}" usa o mesmo raio da página`,
        naPrevia, RAIO_PREVIA[escolha]);
}

igual('nenhum erro no painel', errosP, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
