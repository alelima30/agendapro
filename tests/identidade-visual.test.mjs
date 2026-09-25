/* ===========================================================================
   AgendaPro — a identidade visual de cada estabelecimento

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/identidade-visual.test.mjs

   ── O PEDIDO, E A PARTE DELE QUE MAIS PESA ─────────────────────────────────
   "Quero permitir que cada estabelecimento tenha identidade visual própria...
    NÃO APAGUE, NÃO SUBSTITUA E NÃO REFAÇA NENHUMA CONFIGURAÇÃO, FUNÇÃO OU
    LAYOUT QUE JÁ EXISTE... Se nenhuma personalização estiver configurada, o
    aplicativo deve continuar mostrando EXATAMENTE o visual atual."

   Metade deste arquivo é sobre a segunda frase, não a primeira.

   ⚠ POR QUE O FALLBACK É O QUE MAIS PRECISA DE TESTE. Uma personalização que
   não funciona aparece na hora: o dono escolhe roxo, a página continua azul,
   ele reclama no mesmo dia. Uma personalização que VAZA não aparece: o salão
   que nunca abriu essa tela acorda com a página diferente, e ninguém liga a
   mudança à funcionalidade nova — porque ele não usou a funcionalidade nova.

   É a mesma armadilha dos destaques da capa e dos cartões do dashboard, pela
   terceira vez: AUSENTE não pode ser lido como "vazio".

   ── O CAMINHO QUE ESTE ARQUIVO MEDE ────────────────────────────────────────
       o painel grava  →  a vitrine() devolve  →  o bdDaVitrine copia  →
       o aplicarAparencia marca o <html>  →  o CSS obedece

   A última parada é a que nenhuma leitura de arquivo alcança: regra escrita
   com o seletor errado passa em toda conferência de texto e não pinta nada.
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

const FOTO = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`vis-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'09:00', fim:'18:00' });
}
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte', duracaoMin:30,
  intervaloMin:0, preco:100, ativo:true, aceitaOnline:true });

/* ⚠ UMA CHAVE DE OUTRA TELA, POSTA ANTES DE TUDO. O pedido em maiúsculas era
   "não apague nada", e o jeito de provar isso não é ler o código: é deixar no
   `cfg` algo que a tela de Aparência não conhece e conferir que continua lá
   depois de ela gravar. `passoHorarios` é da tela de Horários. */
const cfgInicial = (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
await dona.atualizar('saloes', SALAO,
  { cfg: Object.assign({}, cfgInicial, { passoHorarios:'30' }) });
ok('salão de teste criado, sem personalização visual nenhuma');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctxCli = await nav.newContext({ viewport:{ width:412, height:915 } });
const erros = [];

async function olharCapa(){
  const c = await ctxCli.newPage();
  c.on('pageerror', e => erros.push('cliente: ' + e.message));
  await c.goto(BASE + '/agendar.html?salao=' + SLUG);
  await c.waitForTimeout(2400);
  const r = await c.evaluate(() => {
    const raiz = document.documentElement;
    const est = getComputedStyle(raiz);
    const selo = document.querySelector('.marca-selo');
    return {
      modo: raiz.getAttribute('data-modo'),
      logo: raiz.getAttribute('data-logo'),
      // As variáveis em que o `aplicarCoresSoltas()` encosta.
      acao:   est.getPropertyValue('--acao').trim(),
      txt:    est.getPropertyValue('--txt').trim(),
      painel: est.getPropertyValue('--painel').trim(),
      borda:  est.getPropertyValue('--borda').trim(),
      ico:    est.getPropertyValue('--ico').trim(),
      ac600:  est.getPropertyValue('--ac-600').trim(),
      bg:     est.getPropertyValue('--bg').trim(),
      txt3:   est.getPropertyValue('--txt3').trim(),
      painel2: est.getPropertyValue('--painel2').trim(),
      temaCor: (document.querySelector('meta[name="theme-color"]') || {})
                 .getAttribute ? document.querySelector('meta[name="theme-color"]')
                 .getAttribute('content') : null,
      grad:   est.getPropertyValue('--bg-grad').trim(),
      temGradiente: document.body.classList.contains('tem-gradiente'),
      temFundo: document.body.classList.contains('tem-fundo'),
      seloRaio: selo ? getComputedStyle(selo).borderRadius : null,
      // A prova de que a página continua sendo a mesma página.
      botao: (document.getElementById('btPrincipal') || {}).textContent || '',
      servicos: document.querySelectorAll('#capaServicos .sv-cartao').length,
    };
  });
  await c.close();
  return r;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ O SALÃO QUE NÃO ESCOLHEU NADA

   Vem primeiro, e é o mais importante do arquivo: é o estado de TODO salão
   que já existe no dia em que isto entra no ar.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Sem personalização nenhuma, nada pode mudar');

const zero = await olharCapa();
console.log('      ' + JSON.stringify(zero).slice(0, 240));

igual('o <html> não ganha marca de modo', zero.modo, null);
igual('nem marca de formato de logo', zero.logo, null);
/* ⚠ A VARIÁVEL NÃO PODE NEM EXISTIR. Definida com um valor "neutro" ela ainda
   ganharia de regras que hoje vencem por especificidade — e o estrago
   apareceria numa tela qualquer, longe daqui. Ausente é ausente. */
igual('e a cor dos ícones não é definida', zero.ico, '');
igual('nem o gradiente', zero.grad, '');
verdade('o corpo não tem classe de gradiente', !zero.temGradiente);
verdade('a capa desenha o serviço, como sempre', zero.servicos > 0,
  JSON.stringify(zero));
verdade('e o botão de marcar continua lá', zero.botao.length > 0, zero.botao);

/* ══════════════════════════════════════════════════════════════════════════
   2 — O PAINEL: o dono escolhe
   ══════════════════════════════════════════════════════════════════════════ */
secao('O dono escolhe, no painel');

const ctxDono = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctxDono.newPage();
p.on('pageerror', e => erros.push('painel: ' + e.message));
p.on('dialog', async d => { await d.accept(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1500);
await p.click('#abas .aba[data-chave="salao"]');
await p.waitForTimeout(900);
await p.evaluate(() => trocarAbaSalao('aparencia'));
await p.waitForTimeout(600);

const daTela = await p.evaluate(() => ({
  temModo: !!document.getElementById('reguaModo'),
  temTemas: document.querySelectorAll('#temasProntos button').length,
  /* ⚠ AS ONZE, NOS DOIS LUGARES ONDE ELAS PODEM SER DESENHADAS — e não
     "todas dentro de #coresSoltas". A regra é que as onze sejam escolhíveis;
     o container era circunstância, e cravá-lo reprovou a tela por ter movido
     a linha do papel para junto das perguntas sobre fundo, que foi o conserto.

     ⚠ E TAMBÉM NÃO É `.cor-linha` SOLTO NA PÁGINA. Tentei, e deu 12: a cor da
     fita do carrinho usa a mesma classe, lá embaixo, e não é uma das onze.
     Contar por classe media "quantos seletores de cor existem", que é outra
     pergunta. */
  /* E hoje nem "dois lugares": desde que a tela virou seções (Fundo,
     Textos, Ícones, Bordas…), cada cor mora na seção dela. Conta-se a linha
     pela chave, onde quer que esteja. */
  temCores: document.querySelectorAll('.ap-controles .cor-linha[data-chave]').length,
  chavesUnicas: new Set([...document.querySelectorAll('.ap-controles .cor-linha[data-chave]')]
    .map(e => e.dataset.chave)).size,
  /* E o papel tem que estar no bloco do FUNDO. "O fundo só tem claro e
     escuro" foi dito sobre uma tela em que a cor do papel morava no meio de
     uma lista de onze, três blocos abaixo da pergunta sobre fundo. */
  papelJuntoDoFundo: !!document.querySelector('#apFundo #corDoPapel .cor-linha[data-chave="papel"]'),
  papelForaDaLista: document.querySelectorAll('.cor-linha[data-chave="papel"]').length === 1,
  temFundoTipo: !!document.getElementById('reguaFundoTipo'),
  temLogoForma: !!document.getElementById('reguaLogoForma'),
  gradEscondido: getComputedStyle(
    document.getElementById('gradienteCampos')).display,
}));
console.log('      ' + JSON.stringify(daTela));
verdade('a tela de Aparência ganhou o seletor de modo', daTela.temModo);
// Treze: as onze de antes, os "Ícones de destaque" (que separaram os ícones
// dos atalhos da cor do texto de destaque) e a "Cor dos produtos" (o botão
// Ver produtos e o carrinho). Cada uma uma vez só.
igual('as treze cores aparecem uma a uma', daTela.temCores, 13);
igual('nenhuma repetida', daTela.chavesUnicas, 13);
verdade('e a cor do papel fica junto das outras perguntas sobre fundo',
  daTela.papelJuntoDoFundo && daTela.papelForaDaLista,
  'ela ficou na lista das onze, longe de onde se pergunta pelo fundo');
/* Dez temas mais o "Personalizado", que não é tema: é o botão que limpa as
   cores soltas e devolve tudo ao cálculo automático. */
igual('e os onze botões de tema', daTela.temTemas, 11);
verdade('o tipo de fundo está lá', daTela.temFundoTipo);
verdade('e o formato do logo também', daTela.temLogoForma);
igual('os campos do gradiente ficam escondidos até ele pedir gradiente',
  daTela.gradEscondido, 'none');

/* ⚠ O TEMA PRONTO SÓ PREENCHE. Ele não é um estado guardado: aplicar e depois
   mexer numa cor não pode deixar nada dizendo "este salão é Dourado", senão
   passam a existir duas verdades sobre a mesma tela — a do tema e a das
   cores — e elas discordam no primeiro ajuste. */
const aposTema = await p.evaluate(() => {
  aplicarTemaPronto('Dourado');
  return { cor: aparencia.cor, tema: aparencia.tema,
           cores: Object.keys(aparencia.cores).sort(),
           semNome: !('temaPronto' in aparencia) };
});
console.log('      ' + JSON.stringify(aposTema));
igual('aplicar um tema pronto preenche a cor da marca', aposTema.cor, '#B45309');
igual('e o fundo que combina com ele', aposTema.tema, 'escuro');
igual('e as cores soltas dele', aposTema.cores, ['destaque','secundaria']);
verdade('sem guardar o NOME do tema em lugar nenhum', aposTema.semNome,
  'guardar o nome cria duas verdades sobre a mesma tela');

// O dono ajusta à mão por cima, escolhe o modo, o fundo e a forma do logo.
await p.evaluate(() => {
  escolherCorSolta('card', '#1B1B1F');
  escolherCorSolta('texto', '#E8E4DA');
  escolherCorSolta('icone', '#F5C34B');
  escolherAparencia('modo', 'premium');
  escolherAparencia('logoForma', 'quadrado');
  escolherAparencia('fundoTipo', 'gradiente');
  document.getElementById('gradA').value = '#1B1B1F';
  document.getElementById('gradB').value = '#3A2E12';
  escolherGradiente();
  salvarAparencia();
});
await p.waitForTimeout(1800);

const noBanco = (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
console.log('      ' + JSON.stringify(noBanco).slice(0, 280));
igual('a escolha chega ao banco: modo', noBanco.modo, 'premium');
igual('formato do logo', noBanco.logoForma, 'quadrado');
igual('tipo de fundo', noBanco.fundoTipo, 'gradiente');
/* Minúsculas de propósito: o `<input type="color">` normaliza o valor para
   minúsculo, então é assim que ele chega ao banco — e o CSS não se importa. */
igual('gradiente', String(noBanco.gradiente).toUpperCase(), '#1B1B1F,#3A2E12');
verdade('e as cores que ele trocou', noBanco.cores
  && noBanco.cores.card === '#1B1B1F' && noBanco.cores.icone === '#F5C34B',
  JSON.stringify(noBanco.cores));

/* ⚠ E SÓ AS QUE ELE TROCOU. Gravar as nove sempre congelaria dentro do salão
   as contas de hoje — e melhorar o cálculo depois não chegaria em ninguém.
   Mesma lição dos recados do WhatsApp. */
verdade('e SÓ elas — as herdadas não viram valor fixo',
  !('borda' in (noBanco.cores || {})) && !('titulo' in (noBanco.cores || {}))
  && !('botao' in (noBanco.cores || {}))
  && !('papel' in (noBanco.cores || {})), JSON.stringify(noBanco.cores));

/* ⚠ E A CHAVE DA OUTRA TELA CONTINUA LÁ. "Não apague nada", medido. */
igual('e o que outra tela tinha gravado no cfg continua intacto',
  noBanco.passoHorarios, '30');

/* ══════════════════════════════════════════════════════════════════════════
   3 — A ESCOLHA CHEGA À CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('A página da cliente obedece');

const daVitrine = await dona.chamar('vitrine', { p_slug: SLUG });
const v = Array.isArray(daVitrine) ? daVitrine[0] : daVitrine;
igual('a vitrine() leva o modo', v.salao.modo, 'premium');
igual('o formato do logo', v.salao.logoForma, 'quadrado');
igual('o tipo de fundo', v.salao.fundoTipo, 'gradiente');
igual('o gradiente', String(v.salao.gradiente).toUpperCase(), '#1B1B1F,#3A2E12');
verdade('e as cores', v.salao.cores && v.salao.cores.card === '#1B1B1F',
  JSON.stringify(v.salao.cores));
/* A regra de ouro desta função desde sempre: nunca o `cfg` cru. Chave nova
   só chega à cliente se for escrita lá de propósito. */
verdade('sem devolver o cfg inteiro', v.salao.cfg === undefined,
  'o cfg cru veio junto — chave nova cairia na vitrine sem ninguém decidir');

const vestido = await olharCapa();
console.log('      ' + JSON.stringify(vestido).slice(0, 280));
igual('o <html> é marcado com o modo', vestido.modo, 'premium');
igual('e com o formato do logo', vestido.logo, 'quadrado');
verdade('o gradiente entra', vestido.temGradiente
  && /linear-gradient/.test(vestido.grad) && /1B1B1F/i.test(vestido.grad),
  vestido.grad);
igual('a cor de card escolhida vale', vestido.painel.toUpperCase(), '#1B1B1F');
igual('a cor de ícone escolhida vale', vestido.ico.toUpperCase(), '#F5C34B');
/* ⚠ E A ESCOLHA GANHA DO CÁLCULO. `--ac-600` é deduzido da cor da marca lá em
   cima do `aplicarAparencia()`; o destaque escolhido vem DEPOIS e passa por
   cima. Invertida a ordem, tudo isto aqui continuaria verde menos esta linha:
   as cores que o sistema não calcula (`--ico`, `--painel`) sobreviveriam à
   troca, e só as calculadas apagariam a escolha do dono — em silêncio. */
igual('e a cor de destaque escolhida ganha do cálculo',
  vestido.ac600.toUpperCase(), '#F59E0B');
igual('o logo fica quadrado', vestido.seloRaio, '4px');

/* ⚠ E A PÁGINA CONTINUA SENDO A MESMA. É o pedido inteiro em duas linhas: a
   camada nova é visual, e nada do agendamento pode ter mudado. */
verdade('o serviço continua na capa', vestido.servicos > 0, JSON.stringify(vestido));
verdade('e o botão de marcar continua lá', vestido.botao.length > 0, vestido.botao);

/* ══════════════════════════════════════════════════════════════════════════
   4 — ⚠ O QUE ELE NÃO ESCOLHEU CONTINUA SENDO CALCULADO

   É o que separa "nove cores" de "nove cores que o dono é obrigado a
   preencher". Ele mexeu em três; as outras têm que continuar acompanhando a
   cor da marca, como sempre acompanharam.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O que ele não escolheu continua acompanhando a marca');

await p.evaluate(() => { escolherCor('#1D4ED8'); salvarAparencia(); });
await p.waitForTimeout(1800);
const depois = await olharCapa();
igual('trocando a cor da marca, o botão — que ele NÃO escolheu — acompanha',
  depois.acao.toUpperCase(), '#1D4ED8');
igual('e o card, que ele escolheu, não se mexe',
  depois.painel.toUpperCase(), '#1B1B1F');
verdade('a borda, não escolhida, continua a do tema',
  !!depois.borda && depois.borda === vestido.borda,
  vestido.borda + ' → ' + depois.borda);

/* O botão "herdar" de cada linha: o dono tem que conseguir DESFAZER uma cor
   sem apagar as outras. Sem isto, escolher seria caminho de mão única. */
await p.evaluate(() => { herdarCorSolta('card'); salvarAparencia(); });
await p.waitForTimeout(1800);
const herdado = await olharCapa();
const banco2 = (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
verdade('herdando o card, a chave sai do banco', !('card' in (banco2.cores || {})),
  JSON.stringify(banco2.cores));
verdade('e a tela volta ao card do tema',
  !!herdado.painel && herdado.painel.toUpperCase() !== '#1B1B1F', herdado.painel);
igual('sem mexer nas outras que ele escolheu',
  herdado.ico.toUpperCase(), '#F5C34B');

/* ══════════════════════════════════════════════════════════════════════════
   4b — ⚠ O PAPEL DA PÁGINA, QUE ERA O QUE FALTAVA

   "O fundo só tem preto e bege claro." Era verdade: o interruptor
   Claro/Escuro decidia a maior superfície da tela, e não havia como pedir
   outra cor. Agora há — e ela precisa levar a página inteira junto, não só
   uma faixa.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O fundo na cor que o dono quiser');

await p.evaluate(() => { escolherCorSolta('papel', '#2E1065'); salvarAparencia(); });
await p.waitForTimeout(1800);
const comPapel = await olharCapa();
console.log('      ' + JSON.stringify(comPapel).slice(0, 240));

igual('o papel escolhido vale', comPapel.bg.toUpperCase(), '#2E1065');
/* ⚠ E O `--painel2` VAI JUNTO. Ele é o fundo dos blocos rasos e da barra do
   topo. Ficando na cor antiga, a tela sai com duas famílias de fundo
   brigando — um papel roxo com uma faixa bege em cima dele lê como defeito,
   não como escolha. */
verdade('e o fundo dos blocos rasos acompanha, em vez de ficar na cor velha',
  comPapel.painel2 && comPapel.painel2.toUpperCase() !== '#FBF8F1',
  comPapel.painel2);
// A barra do navegador no celular também: senão a tela começa com uma faixa
// de outra cor acima da página.
igual('a barra do navegador acompanha o papel',
  String(comPapel.temaCor).toUpperCase(), '#2E1065');

/* ⚠ E O CARD ESCOLHIDO NÃO SE MEXE. O papel é outra superfície: quem pediu
   card escuro e papel roxo quer os dois, e não um só. */
verdade('e o card escolhido continua o que era',
  comPapel.painel.toUpperCase() !== '#2E1065', comPapel.painel);

// Herdando de volta, o papel volta ao do tema.
await p.evaluate(() => { herdarCorSolta('papel'); salvarAparencia(); });
await p.waitForTimeout(1800);
const semPapel = await olharCapa();
verdade('herdando, o papel volta ao da base clara/escura',
  semPapel.bg.toUpperCase() !== '#2E1065', semPapel.bg);

/* ══════════════════════════════════════════════════════════════════════════
   4c — ⚠ O CINZA DOS DETALHES

   O bairro embaixo do endereço, o "NOSSOS SERVIÇOS" e o "30 min" do cartão.
   Ele era DEDUZIDO do texto escolhido, e a dedução tem que continuar valendo
   para quem não escolher — o que se ganha é a escolha explícita por cima.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O cinza dos detalhes');

const antesDoCinza = (await olharCapa()).txt3;
await p.evaluate(() => { escolherCorSolta('discreto', '#B08D57'); salvarAparencia(); });
await p.waitForTimeout(1800);
const comCinza = await olharCapa();
igual('a cor escolhida para os textos discretos vale',
  comCinza.txt3.toUpperCase(), '#B08D57');
/* ⚠ E ELA GANHA DA DEDUÇÃO. O `texto` escolhido (lá em cima, #E8E4DA) já
   deduz um `--txt3` puxado dele. Se a dedução viesse depois, ela apagaria a
   escolha — e a linha acima passaria mesmo assim numa ordem errada, porque o
   valor deduzido também é uma cor válida. Por isso a comparação é com o que
   havia ANTES: o número tem que ter mudado, e mudado para o escolhido. */
verdade('e ela é diferente do cinza que era deduzido do texto',
  antesDoCinza.toUpperCase() !== '#B08D57', antesDoCinza);

await p.evaluate(() => { herdarCorSolta('discreto'); salvarAparencia(); });
await p.waitForTimeout(1800);
igual('herdando, o cinza volta a ser deduzido do texto',
  (await olharCapa()).txt3.toUpperCase(), antesDoCinza.toUpperCase());

/* ══════════════════════════════════════════════════════════════════════════
   5 — ⚠ A FOTO DE FUNDO QUE JÁ ESTAVA LÁ

   O caso que só aparece depois de publicado: o salão anexou uma foto de fundo
   meses atrás e nunca vai ver o seletor novo. Se `fundoTipo` ausente
   desligasse a foto, a funcionalidade nova apagaria a decisão dele.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Foto de fundo antiga, sem seletor nenhum');

const base = (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
const porCfg = extra => dona.atualizar('saloes', SALAO,
  { cfg: Object.assign({}, base, { fundo: FOTO }, extra) });

await porCfg({ fundoTipo: null, gradiente: null });
const antiga = await olharCapa();
verdade('sem escolher tipo de fundo, a foto que ele anexou continua valendo',
  antiga.temFundo, JSON.stringify(antiga));
verdade('e o gradiente fica fora', !antiga.temGradiente);

/* ⚠ E PEDIR GRADIENTE TIRA A FOTO. As duas camadas somadas dariam uma tela
   que não é nenhuma das duas — e o dono acharia que o gradiente não pegou. */
await porCfg({ fundoTipo:'gradiente', gradiente:'#1B1B1F,#3A2E12' });
const trocado = await olharCapa();
verdade('pedindo gradiente, ele entra', trocado.temGradiente, trocado.grad);
verdade('e a foto sai da frente', !trocado.temFundo, JSON.stringify(trocado));

// Valor torto não pode derrubar a página: gradiente pela metade é ignorado.
await porCfg({ fundoTipo:'gradiente', gradiente:'só isso aqui' });
const torto = await olharCapa();
verdade('gradiente escrito errado é ignorado, e a página abre',
  !torto.temGradiente && torto.servicos > 0, JSON.stringify(torto));

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

/* ══════════════════════════════════════════════════════════════════════════
   ⚠ A PRÉVIA TEM QUE MOSTRAR O QUE A PÁGINA VAI MOSTRAR

   Este bloco nasceu de uma reclamação que parecia três: "não consigo mudar a
   cor das letras", "o fundo só tem claro e escuro", "as configurações do link
   não aparecem exatamente como mexemos".

   Era uma coisa só. A prévia herdava o tema do PAINEL e ignorava as onze
   cores. Medido, com as onze escolhidas, seis elementos de seis divergiam:

       fundo #102030 na página, #fbf8f1 na prévia
       nome  #203040 na página, #172033 na prévia   … e assim por diante

   O estrago não é a divergência: é que o dono escolhe a cor, a prévia não
   mexe, e ele conclui que a funcionalidade NÃO EXISTE. Ele estava certo sobre
   o que via, e a página sabia pintar tudo aquilo o tempo todo.

   ⚠ E A MEDIDA É LADO A LADO, elemento por elemento. Conferir só que a prévia
   "tem uma cor diferente do padrão" passaria com ela pintando qualquer coisa.
   O que importa é ser A MESMA.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A prévia do painel contra a página de verdade');

const CORES_PROVA = { papel:'#102030', texto:'#405060', discreto:'#708090',
                      titulo:'#203040', card:'#c0d0e0', botao:'#804020' };
/* ⚠ O ENDEREÇO PRECISA EXISTIR para a linha dele existir na tela. Sem ele o
   `.marca-end .rua` não é desenhado, a leitura vem "nao achei", e a
   comparação passa a medir a ausência do elemento em vez da cor dele. */
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova',
             cidade:'Itu', uf:'SP' } });
await porCfg({ cores: CORES_PROVA, moldura:'elegante' });

const hexDe = c => {
  const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(c || '');
  return m ? '#' + [1,2,3].map(i => Number(m[i]).toString(16).padStart(2,'0')).join('')
           : (c || '-');
};
const LADOS = [
  ['fundo da página', 'body',              '#previaFone .fone',         'backgroundColor'],
  ['nome do salão',   '.marca-salao h2',   '#previaFone .fone-topo b',  'color'],
  ['endereço',        '.marca-end .rua',   '#previaFone .fone-topo span','color'],
  ['título de seção', '.cat',              '#previaFone .fone-rot',     'color'],
  ['fundo do cartão', '.sv-cartao',        '#previaFone .fone-cartao',  'backgroundColor'],
  ['botão',           '.boas-cta',         '#previaFone .fone-cta',     'backgroundColor'],
];

const cPrev = await ctxCli.newPage();
cPrev.on('pageerror', e => erros.push('cliente: ' + e.message));
await cPrev.goto(BASE + '/agendar.html?salao=' + SLUG);
await cPrev.waitForTimeout(2400);
const naPagina = await cPrev.evaluate(l => l.map(([, sel, , prop]) => {
  const e = document.querySelector(sel);
  return e ? getComputedStyle(e)[prop] : 'nao achei';
}), LADOS);
await cPrev.close();

await p.reload();
await p.waitForTimeout(3500);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(900);
await p.evaluate(() => irPara('salao'));
await p.waitForTimeout(500);
await p.evaluate(() => trocarAbaSalao('aparencia'));
await p.waitForTimeout(1200);
const naPrevia = await p.evaluate(l => l.map(([, , sel, prop]) => {
  const e = document.querySelector(sel);
  return e ? getComputedStyle(e)[prop] : 'nao achei';
}), LADOS);

LADOS.forEach(([rotulo], i) => {
  igual('a prévia e a página pintam igual: ' + rotulo,
        hexDe(naPrevia[i]), hexDe(naPagina[i]));
});

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
