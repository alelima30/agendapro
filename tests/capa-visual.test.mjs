/* ===========================================================================
   AgendaPro — o visual da capa da cliente

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/capa-visual.test.mjs

   O pedido foi "deixe a capa mais parecida com esta referência, sem mexer em
   nada que já funciona, e respeitando as configurações de personalização".

   ── O QUE ESTE ARQUIVO MEDE, E POR QUÊ ─────────────────────────────────────
   Teste de aparência é fácil de escrever errado: medir pixel de sombra é
   medir gosto, e trava o próximo ajuste sem proteger nada. Aqui só entram as
   regras que QUEBRAM EM SILÊNCIO — as que não dão erro em lugar nenhum e só
   aparecem quando alguém abre a página no celular e acha estranho.

   Foram três, e as três já morderam durante este trabalho:

     1. o cartão de boas-vindas em duas colunas só quando cabe. Container
        query é dois enganos fáceis de cometer — o elemento não pode consultar
        o próprio container, e a regra precisa vir DEPOIS da que sobrescreve;
     2. os pontinhos do carrossel DENTRO da foto. `position:absolute` sem
        ancestral posicionado os mandou para cima do botão fixo do rodapé;
     3. a cor continua sendo a do salão. Esta é a regra escrita em maiúsculas
        no pedido, e a mais fácil de furar sem querer numa mudança visual.
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

// Uma imagem de verdade, para a capa não sair cinza e as medidas valerem.
const arte = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360">`
  + `<rect width="640" height="360" fill="${a}"/>`
  + `<circle cx="320" cy="180" r="120" fill="${b}"/></svg>`).toString('base64');

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`cv-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'19:00' });
}
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino',
  duracaoMin:30, intervaloMin:0, preco:90, ativo:true, aceitaOnline:true,
  categoria:'Cabelo', foto: arte('#7C3AED', '#C084FC') });

/* ⚠ A COR NÃO É A PADRÃO DO APP. Se o salão ficasse com o azul de fábrica,
   toda verificação de "respeitou a cor escolhida" passaria por acidente —
   inclusive num código que ignorasse a escolha por completo. */
const COR = '#6D28D9';
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10',
             bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  logo: arte('#4C1D95', '#A78BFA'),
  capa: arte('#2E1065', '#7C3AED'),
  cfg: { diasLiberados:30, cor: COR, precoNaCapa:true,
         galeria:[{ url: arte('#4C1D95','#9333EA'), tipo:'imagem', legenda:'' },
                  { url: arte('#7C3AED','#F0ABFC'), tipo:'imagem', legenda:'' }],
         slideDe:'galeria' } });
ok('salão criado, com capa, logo, galeria e a cor dele');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrir(larg, alt){
  const ctx = await nav.newContext({ viewport:{ width:larg, height:alt },
    isMobile: larg < 700, hasTouch: larg < 700 });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(`${larg}px: ${e.message}`));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForTimeout(2600);
  return p;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — NO CELULAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('A capa num celular de 412px');

const cel = await abrir(412, 915);
const m = await cel.evaluate(() => {
  const foto  = document.querySelector('.hero-foto');
  const selo  = document.querySelector('.marca-selo');
  const boas  = document.querySelector('.boas');
  const cta   = document.querySelector('.boas-cta');
  const slides = document.querySelector('.slides');
  const pontos = document.querySelector('.slide-pontos');
  const r = e => e ? e.getBoundingClientRect() : null;
  const est = getComputedStyle(document.documentElement);
  return {
    temFoto: !!foto,
    curva: foto ? getComputedStyle(foto).borderBottomLeftRadius : null,
    // O selo tem que MONTAR na foto: o topo dele acima da base dela.
    seloTopo: r(selo) ? Math.round(r(selo).top) : null,
    fotoBase: r(foto) ? Math.round(r(foto).bottom) : null,
    pinos: document.querySelectorAll('.marca-end .rua .ic-svg').length,
    boasLargura: boas ? Math.round(boas.clientWidth) : null,
    boasDisplay: boas ? getComputedStyle(boas).display : null,
    ctaLargura: cta ? Math.round(cta.clientWidth) : null,
    ctaAltura: cta ? Math.round(cta.getBoundingClientRect().height) : null,
    subtitulo: (document.querySelector('.boas-sub') || {}).textContent || '',
    // Os pontinhos: dentro da caixa do slide, e com alvo de toque de gente.
    pontosDentro: !!(r(pontos) && r(slides)
      && r(pontos).bottom <= r(slides).bottom + 1
      && r(pontos).top >= r(slides).top),
    pontoAlvo: pontos ? Math.round(
      pontos.querySelector('button').getBoundingClientRect().height) : null,
    acao: est.getPropertyValue('--acao').trim().toUpperCase(),
    rolaDeLado: document.documentElement.scrollWidth
              > document.documentElement.clientWidth,
  };
});
console.log('      ' + JSON.stringify(m));

verdade('a foto de capa está lá', m.temFoto);
/* A beira curva. Não meço o número exato — isso seria travar o gosto de quem
   ajustar depois. Meço que EXISTE curva e que ela é elíptica (dois valores),
   que é o que faz o arco atravessar a foto inteira em vez de arredondar só
   os cantos. */
verdade('a beira de baixo da foto é curva, e num arco só',
  /\d/.test(m.curva || '') && (m.curva || '').split(' ').length === 2, m.curva);
verdade('a logo monta na foto, e não fica abaixo dela',
  m.seloTopo != null && m.seloTopo < m.fotoBase, `${m.seloTopo} vs ${m.fotoBase}`);
igual('o endereço tem o pino do mapa, uma vez só', m.pinos, 1);

/* ⚠ NO CELULAR O CARTÃO FICA EMPILHADO, com o botão inteiro. Duas colunas em
   374px deixariam o botão com menos de 200px e "Agendar horário" quebraria em
   duas linhas dentro dele. O alvo de toque confortável vale mais que a
   simetria. */
igual('o cartão de boas-vindas fica empilhado', m.boasDisplay, 'block');
verdade('e o botão ocupa a largura toda',
  m.ctaLargura > m.boasLargura - 40, `${m.ctaLargura} de ${m.boasLargura}`);
verdade('com altura de alvo de toque', m.ctaAltura >= 48, String(m.ctaAltura));
verdade('e o cartão explica o que dá para fazer aqui',
  /Escolha o serviço/.test(m.subtitulo), m.subtitulo);

/* ⚠ OS PONTINHOS DENTRO DA FOTO. Sem ancestral posicionado eles foram parar
   em cima do botão fixo do rodapé — visíveis, no lugar errado, sem erro
   nenhum em lugar nenhum. */
verdade('os pontinhos do carrossel ficam dentro da foto', m.pontosDentro);
verdade('e o alvo de toque deles continua com 40px', m.pontoAlvo >= 40,
  String(m.pontoAlvo));

/* ⚠ A REGRA ESCRITA EM MAIÚSCULAS NO PEDIDO: o visual novo obedece à
   personalização. Cor cravada no CSS passaria em tudo acima e furaria isto. */
igual('a cor da página é a que o salão escolheu', m.acao, COR);
verdade('e a página não rola de lado', !m.rolaDeLado);
await cel.close();

/* ══════════════════════════════════════════════════════════════════════════
   2 — ⚠ NO DESKTOP, O CARTÃO VIRA DUAS COLUNAS

   Duas armadilhas de container query moram aqui, e as duas passam caladas:
   o elemento não pode consultar o container que ele mesmo declara, e a regra
   precisa vir DEPOIS da que ela sobrescreve. A segunda foi pior que a
   primeira: o cartão virou flex, o botão manteve `width:100%`, e o texto foi
   espremido numa coluna de 30px com uma palavra por linha.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A mesma capa numa tela larga');

const desk = await abrir(1100, 1000);
const d = await desk.evaluate(() => {
  const boas = document.querySelector('.boas');
  const cta  = document.querySelector('.boas-cta');
  const txt  = document.querySelector('.boas-txt');
  return {
    display: boas ? getComputedStyle(boas).display : null,
    boasLargura: boas ? Math.round(boas.clientWidth) : null,
    ctaLargura: cta ? Math.round(cta.clientWidth) : null,
    txtLargura: txt ? Math.round(txt.clientWidth) : null,
    // Lado a lado de verdade: o texto termina antes de o botão começar.
    ladoALado: !!(txt && cta
      && txt.getBoundingClientRect().right <= cta.getBoundingClientRect().left + 1),
  };
});
console.log('      ' + JSON.stringify(d));
igual('o cartão vira duas colunas', d.display, 'flex');
verdade('o texto e o botão ficam lado a lado, sem se sobrepor', d.ladoALado,
  JSON.stringify(d));
/* ⚠ E O BOTÃO PARA DE OCUPAR A LARGURA TODA. É exatamente o que falhou: com o
   `width:100%` sobrevivendo, o cartão era flex e parecia certo no código. */
verdade('o botão encolhe para caber ao lado',
  d.ctaLargura < d.boasLargura * 0.7, `${d.ctaLargura} de ${d.boasLargura}`);
verdade('e sobra largura de verdade para o texto', d.txtLargura > 120,
  String(d.txtLargura));
await desk.close();

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ O SALÃO SEM FOTO NENHUMA

   Metade dos salões não sobe capa. A beira curva não pode virar um arco
   recortado no papel da página quando não há imagem para recortar.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O salão que não subiu capa');

await dona.atualizar('saloes', SALAO, { capa: null });
const sem = await abrir(412, 915);
const s2 = await sem.evaluate(() => ({
  temFoto: !!document.querySelector('.hero-foto'),
  temSelo: !!document.querySelector('.marca-selo'),
  temBotao: !!document.getElementById('btPrincipal'),
  temServico: document.querySelectorAll('#capaServicos .sv-cartao').length,
}));
console.log('      ' + JSON.stringify(s2));
verdade('sem capa, a faixa de foto não é desenhada', !s2.temFoto);
verdade('a logo continua lá', s2.temSelo);
verdade('o serviço continua na capa', s2.temServico > 0);
verdade('e o botão de marcar continua lá', s2.temBotao);

/* ⚠ E O TEXTO DO CARTÃO NÃO PROMETE O QUE O SALÃO NÃO TEM. Este salão não
   vende produto; mandar a cliente "conferir nossos produtos" é mandá-la
   procurar uma seção que não existe — e ela conclui que a página quebrou. */
const semLoja = await sem.evaluate(() =>
  (document.querySelector('.boas-sub') || {}).textContent || '');
verdade('e o convite não fala em produtos, porque não há loja',
  !/produtos/.test(semLoja), semLoja);
await sem.close();

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
