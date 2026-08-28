/* ===========================================================================
   AgendaPro — os cartões sobre a foto de fundo são escolha do dono

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/cartoes.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   Quando o véu passou a poder chegar a zero, os cartões passaram a engrossar
   sozinhos abaixo de 35% — um limiar fixo, escrito por mim, decidindo a
   aparência do salão dos outros.

   Foto de fundo varia demais para um número servir a todas: parede de tijolo
   escura pede cartão fechado mesmo com véu alto; mármore claro aguenta vidro
   com véu zero. Quem sabe qual é a foto é o dono, e ele está olhando para
   ela. Virou escolha — 'auto', 'vidro' ou 'fechado' — com 'auto' de padrão.

   ── O QUE ESTE ARQUIVO PRECISA PROVAR ──────────────────────────────────────
   Que a escolha ATRAVESSA. Um ajuste de aparência passa por quatro lugares
   antes de virar pixel na tela da cliente:

       painel grava no cfg → vitrine() devolve a chave → agendar.html lê
       → o CSS obedece

   Basta um deles esquecer e o sintoma é o mais desanimador que existe: o
   dono escolhe, o painel grava, a PRÉVIA obedece — e a página da cliente
   continua igual. Sem erro nenhum para investigar.

   Foi exatamente o que quase aconteceu: `vitrine()` mora nos arquivos de
   base, que não entram no arquivo de colagem, e a chave nova ficaria presa
   no painel.
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
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
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
await dona.criarConta({ email:`ct-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju dos Cartões',
  telefone:'+5511' + (100000000 + Math.floor(Math.random()*89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Cartões ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const SLUG = cr[0].slug;

// Um serviço, senão a vitrine não tem o que mostrar.
await dona.inserir('servicos',
  { salaoId: SALAO, nome:'Corte', duracaoMin: 30, preco: 100 });

/* Uma foto de fundo de mentirinha, mas de verdade o bastante: o `fundo-forte`
   só entra quando existe fundo, e sem imagem nada disto seria exercitado. */
const FOTO = 'data:image/svg+xml,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="60">'
  + '<rect width="40" height="60" fill="#7a4f22"/></svg>');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* Grava o ajuste, abre a página da cliente e devolve o que o CSS FEZ — não o
   que o `cfg` diz. É a diferença entre "a chave chegou" e "a tela obedeceu",
   e só a segunda importa para quem está olhando. */
async function comAjuste(cfg){
  await dona.atualizar('saloes', SALAO,
    { cfg: Object.assign({ fundo: FOTO }, cfg) });
  const p = await (await nav.newContext({ viewport:{ width:420, height:820 } })).newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForTimeout(2200);
  const r = await p.evaluate(() => {
    const c = document.querySelector('.cartao, .opcao, .boas');
    return {
      temFundo: document.body.classList.contains('tem-fundo'),
      forte:    document.body.classList.contains('fundo-forte'),
      veu:      getComputedStyle(document.documentElement).getPropertyValue('--veu').trim(),
      cartao:   c ? getComputedStyle(c).backgroundColor : null,
    };
  });
  await p.context().close();
  return r;
}

secao('1) A foto de fundo chega, e o véu também');
{
  const r = await comAjuste({ veu: 0 });
  verdade('a página sabe que há foto de fundo', r.temFundo, JSON.stringify(r));
  verdade('e o véu zero atravessou até o CSS', r.veu === '0',
    'veio ' + JSON.stringify(r.veu));
}

secao('2) Automático: fecha com pouco véu, não fecha com muito');
{
  const pouco = await comAjuste({ veu: 0,  cartoes: 'auto' });
  verdade('véu 0 no automático fecha os cartões', pouco.forte, JSON.stringify(pouco));

  const muito = await comAjuste({ veu: 84, cartoes: 'auto' });
  verdade('véu 84 no automático deixa o vidro', !muito.forte, JSON.stringify(muito));
}

secao('3) Vidro: nunca fecha, nem com a foto em cheio');
{
  const r = await comAjuste({ veu: 0, cartoes: 'vidro' });
  verdade('o dono pediu vidro e continua vidro com véu 0',
    !r.forte, JSON.stringify(r));
}

secao('4) Fechado: sempre fecha, mesmo com muito branco');
{
  const r = await comAjuste({ veu: 90, cartoes: 'fechado' });
  verdade('o dono pediu fechado e fecha mesmo com véu 90',
    r.forte, JSON.stringify(r));
}

secao('5) Salão que nunca escolheu não vê diferença');
{
  /* A migração silenciosa: todo salão criado antes disto tem `cfg` sem a
     chave. Se o ausente não caísse em 'auto', a aparência de quem já usa
     mudaria sozinha numa publicação — a pior forma de estrear um ajuste. */
  const r = await comAjuste({ veu: 0 });
  verdade('sem a chave, vale o automático (fecha com véu 0)',
    r.forte, JSON.stringify(r));
}

secao('6) O console');
verdade('nenhum erro de JavaScript', erros.length === 0, erros.join(' · '));

await nav.close();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações dos cartões sobre a foto.`);
