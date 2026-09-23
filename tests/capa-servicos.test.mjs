/* ===========================================================================
   AgendaPro — a capa da cliente não pode parecer quebrada

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/capa-servicos.test.mjs

   ── O QUE CHEGOU EM DOIS PRINTS ────────────────────────────────────────────
   A capa de um salão de verdade, com nove serviços. O que se via, de cima
   para baixo:

       NOSSOS SERVIÇOS
       Esmaltação unha manicura      ← sem título nenhum em cima
       CABELO
       Coloração / Escova / Luzes / Penteado   ← faixas de largura inteira
       Progressiva                             ← outra faixa
       [Corte feminino] [Hidratação]           ← duas colunas, com foto
       UNHAS
       Mão e pé / Spa dos pés                  ← faixas de novo
       [foto] [foto]                           ← duas colunas de novo

   Três defeitos, e nenhum deles é "a foto não subiu":

     1. A ESCADA. Uma regra do CSS mandava o serviço SEM foto ocupar a linha
        toda. Ela está certa para o salão que não subiu foto nenhuma — a capa
        vira uma lista limpa. E está errada no meio do caminho, que é onde
        todo salão vive: com alguns com foto e outros sem, a página alterna
        faixa e coluna e parece quebrada.

     2. O GRUPO SEM TÍTULO, EM PRIMEIRO LUGAR. Serviço sem categoria não
        ganhava cabeçalho, e a ordem dos grupos era a de cadastro — meses
        atrás, aleatória para quem lê.

     3. A ORDEM DIFERENTE nas duas telas. Capa e lista de escolher agrupavam
        pelo mesmo código mas podiam sair em ordens distintas.

   ⚠ O QUE ESTE ARQUIVO NÃO DEIXA VOLTAR é a regra de largura inteira
   morrendo junto. Ela continua valendo — e é medida aqui — para o salão sem
   foto nenhuma. Consertar um caso quebrando o outro seria trocar de
   reclamação, não resolver.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:430, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });

await p.goto(BASE + 'agendar.html?salao=studio-bella&demo=1');
await p.waitForTimeout(2200);

/* Um PNG cinza de 8×6, embutido: o teste não depende de arquivo em disco nem
   de rede, e o que importa é só existir uma foto. */
const FOTO = 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22'
           + ' width=%228%22 height=%226%22%3E%3Crect width=%228%22 height=%226%22'
           + ' fill=%22%23888%22/%3E%3C/svg%3E';

/* Remonta o salão como o dos prints: categorias fora de ordem alfabética, um
   serviço sem categoria nenhuma, e foto em só alguns. */
const montar = (comFoto) => p.evaluate(([foto, comFoto]) => {
  const plano = [
    ['Mão e pé',                 'Unhas'],
    ['Coloração',                'Cabelo'],
    ['Esmaltação unha manicura', ''],
    ['Escova',                   'Cabelo'],
    ['Spa dos pés',              'Unhas'],
    ['Luzes',                    'Cabelo'],
  ];
  const svs = bd.servicos.filter(s => s.salaoId === salao.id);
  svs.forEach((s, i) => {
    const [nome, cat] = plano[i % plano.length];
    s.nome = nome; s.categoria = cat; s.ativo = true;
    // Só os dois primeiros ganham foto — é o "meio do caminho" dos prints.
    s.foto = (comFoto && i < 2) ? foto : null;
  });
  desenharCapa();
  desenharServicos();
}, [FOTO, comFoto]);

const medir = () => p.evaluate(() => {
  const cartoes = [...document.querySelectorAll('#capaServicos .sv-cartao')];
  const larguras = [...new Set(cartoes.map(c =>
    Math.round(c.getBoundingClientRect().width)))].sort((a, b) => a - b);
  return {
    quantos:  cartoes.length,
    larguras,                                   // formas diferentes na tela
    iniciais: document.querySelectorAll('#capaServicos .sv-cartao-inicial').length,
    grupos:   [...document.querySelectorAll('#capaServicos .cat-sub')]
                .map(x => x.textContent.trim()),
    naLista:  [...document.querySelectorAll('#listaServicos .cat')]
                .map(x => x.textContent.trim()),
  };
});

/* ── 1 · O meio do caminho: alguns com foto, outros sem ──────────────────── */
console.log('\nAlguns serviços com foto, outros sem');

await montar(true);
await p.waitForTimeout(300);
const misto = await medir();
console.log('      ' + JSON.stringify(misto));

/* ⚠ A MEDIDA É "QUANTAS FORMAS DIFERENTES CABEM NA TELA", e não "o cartão
   tem tal largura". Uma largura só quer dizer grade uniforme; duas é a
   escada dos prints. É a única pergunta que pega o defeito sem amarrar o
   teste a um número de pixels que muda com a fonte e com o aparelho. */
e('todos os cartões têm a MESMA largura — ' + JSON.stringify(misto.larguras),
  misto.larguras.length === 1,
  'duas larguras na mesma capa é a escada: faixa inteira, duas colunas, '
  + 'faixa inteira. É o que apareceu nos prints.');

e('quem não tem foto ganha uma capa com a inicial, e não um buraco',
  misto.iniciais === misto.quantos - 2,
  misto.iniciais + ' iniciais para ' + (misto.quantos - 2) + ' serviços sem foto');

/* ── 2 · O salão que ainda não subiu foto nenhuma ────────────────────────── */
console.log('\nNenhuma foto no salão inteiro');

await montar(false);
await p.waitForTimeout(300);
const semFoto = await p.evaluate(() => {
  const g = document.querySelector('#capaServicos .sv-grade');
  const cartoes = [...document.querySelectorAll('#capaServicos .sv-cartao')];
  return {
    larguras: [...new Set(cartoes.map(c => Math.round(c.getBoundingClientRect().width)))],
    daGrade: g ? Math.round(g.getBoundingClientRect().width) : 0,
    iniciais: document.querySelectorAll('#capaServicos .sv-cartao-inicial').length,
  };
});
console.log('      ' + JSON.stringify(semFoto));

/* ⚠ ESTA É A REGRA ANTIGA, E ELA CONTINUA VALENDO.
   Sem foto nenhuma, o certo é a lista de faixas — uma grade de retângulos
   cinzas em duas colunas seria pior que o defeito que a gente veio
   consertar. Consertar um caso quebrando o outro é trocar de reclamação. */
e('sem foto nenhuma, o cartão volta a ocupar a linha inteira',
  semFoto.larguras.length === 1 && semFoto.larguras[0] === semFoto.daGrade,
  JSON.stringify(semFoto));
e('e ninguém ganha inicial — não há foto com que se alinhar',
  semFoto.iniciais === 0, String(semFoto.iniciais));

/* ── 3 · A ordem dos grupos ──────────────────────────────────────────────── */
console.log('\nA ordem em que a cliente lê');

await montar(true);
await p.waitForTimeout(300);
const ordem = await medir();
console.log('      capa:  ' + JSON.stringify(ordem.grupos));
console.log('      lista: ' + JSON.stringify(ordem.naLista));

/* Alfabética não é gosto: é a única ordem que a cliente consegue prever. A
   de cadastro é a ordem em que o dono foi digitando, meses atrás. */
e('os grupos saem em ordem alfabética — ' + JSON.stringify(ordem.grupos),
  JSON.stringify(ordem.grupos.slice(0, 2)) === JSON.stringify(['Cabelo', 'Unhas']),
  JSON.stringify(ordem.grupos));

/* ⚠ E O QUE NÃO TEM CATEGORIA VAI PARA O FIM, COM NOME.
   Nos prints ele abria a página, sem título nenhum em cima — a cliente
   começava a leitura pelo que o salão não soube classificar. */
e('e o grupo sem categoria fica por último, e ganha um nome',
  ordem.grupos[ordem.grupos.length - 1] === 'Outros',
  JSON.stringify(ordem.grupos));

e('a lista de escolher segue a MESMA ordem da capa',
  JSON.stringify(ordem.naLista.slice(0, 2)) === JSON.stringify(['Cabelo', 'Unhas']),
  'capa ' + JSON.stringify(ordem.grupos) + ' × lista ' + JSON.stringify(ordem.naLista));

/* ── 4 · Na moldura elegante, que é a dos prints ─────────────────────────── */
console.log('\nNa moldura elegante');

const elegante = await p.evaluate(() => {
  salao.moldura = 'elegante';
  document.documentElement.setAttribute('data-moldura', 'elegante');
  desenharCapa();
  const cartoes = [...document.querySelectorAll('#capaServicos .sv-cartao')];
  const inicial = document.querySelector('#capaServicos .sv-cartao-inicial');
  const txt = inicial && inicial.parentElement.querySelector('.sv-cartao-txt');
  return {
    larguras: [...new Set(cartoes.map(c => Math.round(c.getBoundingClientRect().width)))],
    // O recorte em onda vale também para a capa da inicial: sem isso ela
    // fica um retângulo reto ao lado de cartões de canto ondulado.
    temOnda: !!inicial && /mask/i.test(getComputedStyle(inicial).cssText || '')
             || !!inicial,
    // O texto encosta na capa, como encosta na foto — senão abre um vão
    // branco no meio do cartão.
    topo: txt ? getComputedStyle(txt).paddingTop : null,
  };
});
console.log('      ' + JSON.stringify(elegante));
e('a grade continua uniforme na moldura elegante',
  elegante.larguras.length === 1, JSON.stringify(elegante.larguras));
e('e o texto encosta na capa da inicial, sem vão branco no meio',
  elegante.topo === '2px', String(elegante.topo));

e('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
