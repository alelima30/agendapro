/* ===========================================================================
   AgendaPro — a moldura do cartão de serviço, do painel até o pixel

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/moldura.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   A moldura elegante é o SEGUNDO modelo do cartão de serviço. O pedido tinha
   duas metades, e a segunda é a difícil:

     1. o modelo novo existe e é bonito;
     2. o modelo de sempre continua EXATAMENTE como estava.

   A segunda metade não dá sinal quando quebra. Um `.sv-cartao{ }` mexido sem
   escopo, um elemento novo que escapou do `if`, e o salão que nunca pediu
   nada acorda com a página diferente. Ninguém reclama de imediato — a página
   continua funcionando — e quando a reclamação chega, já não se sabe qual
   mudança foi.

   Por isso metade das verificações daqui é sobre o cartão CLÁSSICO.

   ── E OS CINCO PARADAS DA APARÊNCIA ───────────────────────────────────────
   O `sintaxe.test.js` confere de TEXTO que a chave atravessa painel →
   vitrine → tela. Confere que ela está escrita nos três lugares; não confere
   que ela CHEGA. Este arquivo mede a chegada, com um navegador de verdade:

       o banco guarda  →  a vitrine() devolve  →  o bdDaVitrine copia  →
       o aplicarAparencia marca o <html>  →  o CSS obedece

   A última parada é a que nenhum teste de texto alcança: regra escrita com o
   seletor errado passa em toda leitura de arquivo e não pinta nada.
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
const ok = (m) => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => a === b ? ok(m)
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
const COR = '#0C7568';                       // uma das sete da paleta do painel
const d = novaAba();
await d.criarConta({ email:`mold-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const criado = await d.chamar('criar_salao', { p_nome_salao:'Estúdio ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const salaoId = criado[0].salao_id, SLUG = criado[0].slug;
const prof = (await d.lista('profissionais', { salaoId }))[0];
for(let i = 0; i <= 6; i++){
  await d.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                inicio:'09:00', fim:'19:00' });
}

/* Dois serviços de propósito, e diferentes um do outro:

   · COM foto e COM descrição — é o cartão cheio, o que a moldura desenha por
     inteiro: onda, descrição, relógio e seta.
   · COM foto e SEM descrição — porque descrição é campo opcional, e a maior
     parte dos salões não preenche. Se a moldura só ficasse boa com ela, seria
     uma moldura que quase ninguém veria funcionar. */
const FOTO = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
await d.inserir('servicos', { salaoId, nome:'Corte feminino', preco:90,
  descricao:'Lavagem, corte e finalização com escova',
  duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true, foto:FOTO });
await d.inserir('servicos', { salaoId, nome:'Escova', preco:50,
  duracaoMin:40, intervaloMin:0, ativo:true, aceitaOnline:true, foto:FOTO });
ok('salão de teste criado, com dois serviços');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 } });

async function abrir(){
  const p = await ctx.newPage();
  p.erros = [];
  p.on('pageerror', e => p.erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForTimeout(2400);
  return p;
}
const cfg = (extra) => d.atualizar('saloes', salaoId,
  { cfg: Object.assign({ diasLiberados:30, cor:COR, precoNaCapa:true }, extra) });

/* ══════════════════════════════════════════════════════════════════════════
   1 — O SALÃO QUE NUNCA ESCOLHEU NADA

   É o caso de TODOS os salões que já existem. Se a ausência da chave não
   valesse `reta`, esta funcionalidade seria uma mudança de aparência aplicada
   à revelia em cima de gente que está usando o sistema hoje.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Sem escolha nenhuma, nada muda');

await cfg();                                  // sem `moldura` no cfg
const v0 = await d.chamar('vitrine', { p_slug: SLUG });
igual('a vitrine() devolve `reta` quando o cfg não tem a chave',
  (Array.isArray(v0) ? v0[0] : v0).salao.moldura, 'reta');

const a = await abrir();
igual('e o <html> não ganha marca nenhuma',
  await a.getAttribute('html', 'data-moldura'), null);

/* ── O CARTÃO CLÁSSICO, ELEMENTO POR ELEMENTO ─────────────────────────────
   Os três elementos novos não podem NASCER e ser escondidos por CSS: o pedido
   foi não mexer no modelo atual, e HTML a mais é mexer nele. Leitor de tela e
   busca da página leem o que existe, não o que está visível. */
const classico = async (p) => p.evaluate(() => ({
  cartoes:  document.querySelectorAll('.sv-cartao').length,
  desc:     document.querySelectorAll('.sv-cartao-desc').length,
  relogio:  document.querySelectorAll('.sv-cartao-relogio').length,
  seta:     document.querySelectorAll('.sv-cartao-ir').length,
  raio:     getComputedStyle(document.querySelector('.sv-cartao')).borderRadius,
  mascara:  getComputedStyle(document.querySelector('.sv-cartao-foto')).maskImage,
  proporcao:getComputedStyle(document.querySelector('.sv-cartao-foto')).aspectRatio,
}));
const c0 = await classico(a);
igual('os dois serviços viram dois cartões', c0.cartoes, 2);
igual('nenhuma descrição é escrita', c0.desc, 0);
igual('nenhum relógio', c0.relogio, 0);
igual('nenhum botão de seta', c0.seta, 0);
igual('a foto continua 4/3, como sempre foi', c0.proporcao, '4 / 3');
igual('e sem máscara nenhuma recortando a foto', c0.mascara, 'none');
igual('o raio do cartão é o de sempre (--r)', c0.raio, '12px');
igual('sem erro de JavaScript', a.erros.length ? a.erros.join(' | ') : 0, 0);

/* ══════════════════════════════════════════════════════════════════════════
   2 — O DONO ESCOLHE A ELEGANTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('Escolhida a elegante, a chave atravessa até o <html>');

await cfg({ moldura:'elegante' });
const v1 = await d.chamar('vitrine', { p_slug: SLUG });
const daVitrine = Array.isArray(v1) ? v1[0] : v1;
igual('a vitrine() devolve `elegante`', daVitrine.salao.moldura, 'elegante');
verdade('e continua sem devolver o cfg inteiro',
  daVitrine.salao.cfg === undefined,
  'o cfg cru veio junto — chave nova cairia na vitrine sem ninguém decidir');

await a.close();
const b = await abrir();
igual('o <html> é marcado', await b.getAttribute('html', 'data-moldura'), 'elegante');

secao('E o desenho aparece');

const e1 = await b.evaluate(() => {
  const c = document.querySelector('.sv-cartao');
  const est = getComputedStyle(c);
  const foto = getComputedStyle(c.querySelector('.sv-cartao-foto'));
  const seta = c.querySelector('.sv-cartao-ir');
  const rel  = c.querySelector('.sv-cartao-relogio');
  return {
    cartoes:  document.querySelectorAll('.sv-cartao').length,
    desc:     document.querySelectorAll('.sv-cartao-desc').length,
    relogio:  document.querySelectorAll('.sv-cartao-relogio').length,
    seta:     document.querySelectorAll('.sv-cartao-ir').length,
    raio:     est.borderRadius,
    mascara:  foto.maskImage,
    proporcao:foto.aspectRatio,
    margem:   foto.marginBottom,
    fundoSeta:seta ? getComputedStyle(seta).backgroundColor : null,
    letraSeta:seta ? getComputedStyle(seta).color : null,
    svgSeta:  seta ? seta.querySelectorAll('svg').length : -1,
    svgRel:   rel  ? rel.querySelectorAll('svg').length  : -1,
    larguraSeta: seta ? Math.round(seta.getBoundingClientRect().width) : 0,
    divisoria: getComputedStyle(c.querySelector('.sv-cartao-linha')).borderTopWidth,
  };
});
igual('continuam sendo dois cartões — a moldura não inventa serviço',
  e1.cartoes, 2);
igual('a seta aparece nos dois', e1.seta, 2);
igual('o relógio também', e1.relogio, 2);
/* UM, e não dois: o segundo serviço não tem descrição cadastrada. Se saíssem
   dois, seria um <span> vazio abrindo buraco no cartão de quem não preencheu
   o campo — que é a maioria dos salões. */
igual('mas a descrição sai só no serviço que tem uma', e1.desc, 1);
igual('o cartão ganha o raio grande (--r-lg)', e1.raio, '16px');
igual('a foto vira quadrada', e1.proporcao, '1 / 1');
igual('a linha de baixo ganha a divisória', e1.divisoria, '1px');

/* ── A ONDA ───────────────────────────────────────────────────────────────
   A parada que nenhum teste de texto alcança. `maskImage` diferente de `none`
   quer dizer que o navegador ACEITOU a regra: SVG malformado, aspas erradas
   no data URI ou `#` sem escapar caem todos em `none`, calados. */
verdade('a foto é recortada por uma máscara — ' + e1.mascara.slice(0, 40) + '…',
  e1.mascara !== 'none' && /svg/.test(e1.mascara),
  'veio ' + JSON.stringify(e1.mascara) + ' — data URI malformado cai em `none` '
  + 'sem erro nenhum, e o cartão fica reto de novo');
verdade('e o texto sobe para encostar na curva — ' + e1.margem,
  parseFloat(e1.margem) < 0,
  'sem margem negativa sobra uma faixa vazia do tamanho do recorte');

/* ── OS ÍCONES VIRARAM DESENHO ────────────────────────────────────────────
   O `data-ico` é um <span> vazio até o `aplicarIcones()` trocar. */
igual('o relógio virou SVG mesmo — não ficou um span vazio', e1.svgRel, 1);
igual('a seta também', e1.svgSeta, 1);
verdade('e a seta tem tamanho de botão — ' + e1.larguraSeta + 'px',
  e1.larguraSeta >= 20 && e1.larguraSeta <= 40, 'veio ' + e1.larguraSeta + 'px');

/* ── E CONTINUAM DESENHO DEPOIS DE UM REDESENHO ───────────────────────────
   Na abertura, quem pinta é o `irPara('capa')` com que o `entrarNoSalao()`
   termina — então as duas linhas acima passariam mesmo sem a chamada que
   existe no fim do `desenharCapa()`. Foi o que aconteceu: mutei a chamada
   para fora e o teste continuou verde.

   O que ela protege é o outro caso: um `desenhar()` com a capa JÁ na tela.
   Ele reescreve o `#capaServicos` com `data-ico` novo, e ninguém pinta
   depois. Medido sem a chamada, os seis SVGs viram ZERO.

   Hoje nenhuma tela dispara esse caminho — todo `desenhar()` solto pertence a
   outro passo. A linha é prevenção, e é por isso que esta verificação força o
   redesenho à mão: prevenção sem teste é uma linha que ninguém sabe se ainda
   funciona, e a primeira pessoa a "limpar" o código a leva embora. */
const antesDoRedesenho = await b.evaluate(() =>
  document.querySelectorAll('.sv-cartao-ir svg, .sv-cartao-relogio svg').length);
await b.evaluate(() => desenhar());
await b.waitForTimeout(150);
const depoisDoRedesenho = await b.evaluate(() =>
  document.querySelectorAll('.sv-cartao-ir svg, .sv-cartao-relogio svg').length);
igual('redesenhando a capa, os ícones continuam desenhados',
  depoisDoRedesenho, antesDoRedesenho);
verdade('(e havia ícones para perder: ' + antesDoRedesenho + ')',
  antesDoRedesenho > 0);

/* ── A COR É A DO SALÃO ───────────────────────────────────────────────────
   A imagem de referência era roxa. Roxo escrito à mão no CSS deixaria a
   barbearia de dourado e grafite com um botão roxo no cartão — e o dono não
   teria onde mexer. */
igual('o botão usa a cor de marca escolhida, e não uma cor fixa',
  e1.fundoSeta, 'rgb(12, 117, 104)');
verdade('com letra que contrasta com ela',
  e1.letraSeta === 'rgb(255, 255, 255)' || e1.letraSeta === 'rgb(16, 16, 20)',
  'veio ' + e1.letraSeta);

/* ── A DESCRIÇÃO TEM TETO ─────────────────────────────────────────────────
   Dois cartões lado a lado numa grade: se um esticasse com um parágrafo, o
   vizinho ficaria com um buraco branco embaixo. */
const linhas = await b.evaluate(() => {
  const el = document.querySelector('.sv-cartao-desc');
  if(!el) return null;
  const est = getComputedStyle(el);
  return { clamp: est.webkitLineClamp, corte: est.overflow };
});
igual('a descrição é cortada em duas linhas', linhas && linhas.clamp, '2');
igual('e o que passa disso fica escondido', linhas && linhas.corte, 'hidden');

igual('sem erro de JavaScript na elegante',
  b.erros.length ? b.erros.join(' | ') : 0, 0);

/* ══════════════════════════════════════════════════════════════════════════
   3 — AS DUAS METADES NÃO SE MISTURAM

   `cartoes` decide o quanto o cartão fecha sobre a foto de capa; `moldura`
   decide a forma. São eixos diferentes, e foi por isso que a moldura não
   virou mais um valor de `cartoes`. Este bloco é o que cobra essa decisão:
   pedir vidro E elegante tem que dar os dois.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Moldura e fundo dos cartões são escolhas separadas');

/* ⚠ `cartoes` NÃO vira atributo no <html>, como a `moldura`. Ele vira a
   classe `fundo-forte` no <body>, e só quando existe imagem de fundo — sem
   foto por baixo não há nada para o cartão fechar por cima.

   A primeira versão deste bloco procurava um `data-cartoes` que nunca
   existiu, e o teste reprovou dizendo que a página não aplicava. Quem estava
   errado era o teste. Por isso as duas escolhas são medidas no EFEITO que
   cada uma tem de verdade, e não no jeito como cada uma é marcada. */
const COM_FUNDO = { fundo:FOTO, veu:10 };    // véu baixo: o limiar quer fechar

await cfg(Object.assign({ moldura:'elegante', cartoes:'vidro' }, COM_FUNDO));
const v2 = await d.chamar('vitrine', { p_slug: SLUG });
const s2 = (Array.isArray(v2) ? v2[0] : v2).salao;
igual('a vitrine devolve as duas', s2.moldura + '/' + s2.cartoes, 'elegante/vidro');

await b.close();
let c = await abrir();
igual('pedindo vidro, a moldura continua elegante',
  await c.getAttribute('html', 'data-moldura'), 'elegante');
verdade('e o cartão fica de vidro — o véu baixo não o fecha',
  !(await c.evaluate(() => document.body.classList.contains('fundo-forte'))),
  '`vidro` é justamente o que manda ignorar o limiar do véu');

/* O outro extremo do mesmo eixo, com a MESMA moldura. Se os dois tivessem
   virado um só ajuste, este par seria impossível de pedir. */
await cfg(Object.assign({ moldura:'elegante', cartoes:'fechado' }, COM_FUNDO));
await c.close();
c = await abrir();
igual('pedindo fechado, a moldura AINDA é elegante',
  await c.getAttribute('html', 'data-moldura'), 'elegante');
verdade('e agora o cartão fecha sobre a foto',
  await c.evaluate(() => document.body.classList.contains('fundo-forte')),
  'os dois eixos se misturaram: a moldura passou a mandar no fundo');
verdade('com a onda continuando no lugar nos dois casos',
  await c.evaluate(() => getComputedStyle(
    document.querySelector('.sv-cartao-foto')).maskImage !== 'none'));

/* ══════════════════════════════════════════════════════════════════════════
   4 — E DÁ PARA VOLTAR

   Escolha de aparência que não tem volta não é escolha: é armadilha. O dono
   experimenta, não gosta, e precisa achar o caminho de casa.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Escolhendo a clássica de novo, tudo volta ao que era');

await cfg({ moldura:'reta' });
await c.close();
const f = await abrir();
igual('a marca sai do <html>', await f.getAttribute('html', 'data-moldura'), null);

const cF = await classico(f);
igual('sem descrição de novo', cF.desc, 0);
igual('sem relógio', cF.relogio, 0);
igual('sem seta', cF.seta, 0);
igual('a foto volta a 4/3', cF.proporcao, '4 / 3');
igual('a máscara some', cF.mascara, 'none');
igual('e o raio volta ao de sempre', cF.raio, '12px');
igual('sem erro de JavaScript na volta',
  f.erros.length ? f.erros.join(' | ') : 0, 0);
await f.close();

/* ══════════════════════════════════════════════════════════════════════════
   5 — SERVIÇO SEM FOTO NÃO VIRA CARTÃO QUEBRADO

   ── ⚠ ESTA SEÇÃO MEDIA UM CASO SÓ, E AGORA SÃO DOIS ───────────────────────
   Ela dizia, de uma vez: serviço sem foto não tem foto para recortar, logo o
   `padding-top:2px` do texto — que só serve para encostar numa foto — tem que
   sumir. Estava certo enquanto "sem foto" queria dizer uma coisa só.

   Não quer mais. A capa passou a decidir a forma PELO CONJUNTO, e não por
   cartão, porque o meio do caminho (alguns serviços com foto, outros sem)
   produzia uma escada — faixa inteira, duas colunas, faixa inteira — e a
   primeira tela da cliente parecia quebrada. Então:

     · salão com foto em ALGUNS: quem não tem ganha uma capa com a inicial do
       serviço, que é um `.sv-cartao-foto` de verdade. Aí o texto ENCOSTA
       nela, e os 2px são o certo — tirá-los abriria um vão branco no meio do
       cartão;

     · salão SEM FOTO NENHUMA: não há capa com que encostar, e aí vale a
       regra antiga inteira — nenhum `.sv-cartao-foto`, e o nome longe do topo.

   As duas cenas estão aqui porque consertar uma quebrando a outra é trocar de
   reclamação, não resolver — e foi exatamente isso que aconteceu da primeira
   vez: a cena nova entrou e esta seção continuou cobrando a regra velha.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Serviço sem foto, na moldura elegante');

const semFotoAqui = await d.inserir('servicos', { salaoId, nome:'Hidratação',
  preco:70, duracaoMin:45, intervaloMin:0, ativo:true, aceitaOnline:true });
await cfg({ moldura:'elegante' });

const medirSemFoto = (p) => p.evaluate(() => {
  const c = document.querySelector('.sv-cartao.sem-foto');
  if(!c) return null;
  const txt = getComputedStyle(c.querySelector('.sv-cartao-txt'));
  return { topo: parseFloat(txt.paddingTop),
           fotos: c.querySelectorAll('.sv-cartao-foto').length,
           iniciais: c.querySelectorAll('.sv-cartao-inicial').length,
           seta: c.querySelectorAll('.sv-cartao-ir').length };
});

// ── 5a · o meio do caminho: os outros dois têm foto, este não ──────────────
const g = await abrir();
const misturado = await medirSemFoto(g);
verdade('o cartão sem foto existe', misturado !== null,
  'o serviço sem foto não virou cartão — mudou a regra do `sem-foto`');
igual('num salão que TEM fotos, ele ganha a capa com a inicial',
  misturado && misturado.iniciais, 1);
verdade('e o nome encosta nela, sem vão branco — '
        + (misturado && misturado.topo) + 'px',
  misturado && misturado.topo <= 4,
  'a capa da inicial é foto para todos os efeitos: o texto encosta como '
  + 'encosta numa foto de verdade');
igual('e ele ganha a seta como os outros', misturado && misturado.seta, 1);
igual('sem erro de JavaScript', g.erros.length ? g.erros.join(' | ') : 0, 0);
await g.close();

// ── 5b · o salão que ainda não subiu foto nenhuma ─────────────────────────
// É a regra antiga, e ela continua valendo inteira.
for(const s of await d.lista('servicos', { salaoId })){
  if(s.foto) await d.atualizar('servicos', s.id, { foto: null });
}
const h = await abrir();
const nenhuma = await medirSemFoto(h);
verdade('sem foto nenhuma no salão, o cartão continua existindo',
  nenhuma !== null);
igual('e aí não há foto nenhuma para recortar', nenhuma && nenhuma.fotos, 0);
verdade('o nome não fica colado no topo — ' + (nenhuma && nenhuma.topo) + 'px',
  nenhuma && nenhuma.topo >= 10,
  'ficou ' + (nenhuma && nenhuma.topo) + 'px: o padding de 2px, que só serve '
  + 'para encostar numa foto, sobrou num cartão que não tem foto');
igual('e a seta continua lá', nenhuma && nenhuma.seta, 1);
igual('sem erro de JavaScript', h.erros.length ? h.erros.join(' | ') : 0, 0);
await h.close();

// As fotos voltam: as seções de baixo medem a prévia do painel, e um salão
// sem foto nenhuma mudaria a forma do cartão lá também.
for(const s of await d.lista('servicos', { salaoId })){
  if(s.id !== semFotoAqui.id) await d.atualizar('servicos', s.id, { foto: FOTO });
}

/* ══════════════════════════════════════════════════════════════════════════
   6 — A PRÉVIA DO PAINEL OBEDECE

   É onde a escolha acontece. O dono clica na régua olhando para o telefone
   desenhado ao lado; se ele não mudar, a conclusão razoável é que o botão não
   funciona — e o dono desiste da funcionalidade inteira sem nunca ter visto o
   que ela faz.

   Esta é a parada que mais fácil se esquece, porque a prévia do painel é um
   desenho À PARTE da página da cliente: fazer a página obedecer não faz a
   prévia obedecer, e nada avisa.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A prévia do painel muda quando o dono escolhe');

const painel = await ctx.newPage();
const errosP = [];
painel.on('pageerror', e => errosP.push(e.message));
await painel.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, d.sessao()]);
await painel.setViewportSize({ width: 1360, height: 900 });
await painel.goto(BASE + '/app.html');
await painel.waitForTimeout(3200);
await painel.click('a:has-text("Meu salão"), button:has-text("Meu salão")');
await painel.waitForTimeout(1500);
/* "Meu salão" tem sub-abas, e a Aparência não é a que abre por padrão. Sem
   este clique a régua EXISTE no HTML e não é clicável — que foi como este
   teste reprovou da primeira vez, com "element is not visible". */
await painel.click('[data-sub="aparencia"]');
await painel.waitForTimeout(1200);

const regua = await painel.evaluate(() =>
  [...document.querySelectorAll('#reguaMoldura button')].map(b => b.textContent.trim()));
igual('a régua da moldura existe, com as duas opções',
  JSON.stringify(regua), JSON.stringify(['Clássica', 'Curvada']));
/* Dois rótulos iguais na mesma aba fariam o dono escolher um e ver o outro
   mudar de lugar. O `LETRAS` já tem um "Elegante" — a letra serifada, em uso
   nos salões — e por isso o rótulo aqui é outro, embora o valor guardado
   continue sendo `elegante`. */
const rotulos = await painel.evaluate(() =>
  [...document.querySelectorAll('#reguaMoldura button, #reguaLetra button')]
    .map(b => b.textContent.trim()));
igual('e nenhum rótulo se repete entre as réguas da aba',
  new Set(rotulos).size, rotulos.length);

const naPrevia = () => painel.evaluate(() => ({
  fileiras: document.querySelectorAll('#previaFone .fone-sv-foto').length,
  cartoes:  document.querySelectorAll('#previaFone .fone-cartao').length,
  onda: (() => {
    const f = document.querySelector('#previaFone .fone-cartao-foto');
    return f ? getComputedStyle(f).maskImage : 'sem cartão';
  })(),
}));

await painel.click('#reguaMoldura button:has-text("Clássica")');
await painel.waitForTimeout(400);
const pClass = await naPrevia();
verdade('na clássica, a prévia é a fileira de sempre — ' + pClass.fileiras,
  pClass.fileiras > 0 && pClass.cartoes === 0,
  JSON.stringify(pClass));

await painel.click('#reguaMoldura button:has-text("Curvada")');
await painel.waitForTimeout(400);
const pCurv = await naPrevia();
verdade('escolhendo Curvada, a prévia vira a grade de cartões — ' + pCurv.cartoes,
  pCurv.cartoes > 0 && pCurv.fileiras === 0,
  JSON.stringify(pCurv) + ' — a prévia não acompanhou a escolha, e o dono vê '
  + 'o mesmo de antes ao clicar');
verdade('com a curva desenhada nela também',
  pCurv.onda !== 'none' && /svg/.test(String(pCurv.onda)),
  'veio ' + JSON.stringify(pCurv.onda));

/* ── E A CURVA DA PRÉVIA É A MESMA DA PÁGINA ──────────────────────────────
   São duas cópias do mesmo SVG, em dois lugares da folha de estilo, porque a
   prévia vive no painel e não pode usar as variáveis do salão. Duas cópias
   divergem — é o que cópias fazem. Quando divergirem, a prévia passa a
   prometer uma curva e a página a entregar outra, e ninguém descobre: as duas
   continuam bonitas, cada uma sozinha. */
const curvaDaPagina = (fs.readFileSync(path.join(RAIZ, 'estilo.css'), 'utf8')
  .match(/--onda:url\("[^"]+"\)/g) || []);
igual('a onda está escrita duas vezes na folha — página e prévia',
  curvaDaPagina.length, 2);
verdade('e as duas são a MESMA curva, caractere por caractere',
  curvaDaPagina.length === 2 && curvaDaPagina[0] === curvaDaPagina[1],
  'divergiram:\n      ' + curvaDaPagina.join('\n      '));

igual('sem erro de JavaScript no painel',
  errosP.length ? errosP.join(' | ') : 0, 0);
await painel.close();

await ctx.close();
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
