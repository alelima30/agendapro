/* ===========================================================================
   AgendaPro — a escolha dos serviços com o cartão da capa

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/escolha-cartao.test.mjs

   O pedido: "Não quero os serviços aparecendo assim [fileiras retangulares]
   e sim com a moldura da primeira página. Todos os serviços têm que aparecer
   assim." E: "Se está configurado em Aparência do link como moldura Curvada,
   será a curvada; se não, a clássica."

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. em "O que você quer fazer?" os serviços são o cartão da capa — o mesmo
        desenho, com as mesmas peças — e nenhuma fileira antiga;
     2. a moldura segue a de Aparência: Curvada com a onda, Clássica sem;
     3. tocar escolhe (e desescolhe), pode mais de um, e a marca mostra;
     4. o que só a escolha tem continua: preço, COMBO, busca, categorias e a
        soma no fim;
     5. o relógio da Curvada não some ao tocar num serviço.
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
const arte = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480"><rect width="640" height="480" fill="${a}"/>`
  + `<circle cx="320" cy="220" r="120" fill="${b}"/></svg>`).toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`ec-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
/* Os serviços do print dele: dois grupos, alguns com foto, um combo. */
const SV = [['Coloração', 120, 150, 'Cabelo', null], ['Escova', 40, 50, 'Cabelo', null],
  ['Corte feminino', 30, 90, 'Cabelo', arte('#333333', '#999999')], ['Hidratação', 60, 120, 'Cabelo', arte('#5A4A3A', '#BBBBAA')],
  ['Mão e pé', 80, 70, 'Unhas', null], ['Spa dos pés', 60, 80, 'Unhas', null],
  ['Manicure', 50, 40, 'Unhas', arte('#8A5A4A', '#E0C0A0')], ['Pedicure', 40, 50, 'Unhas', arte('#C9A0A0', '#F0D0D0')]];
for(const [nome, duracaoMin, preco, categoria, foto] of SV)
  await dona.inserir('servicos', { salaoId: SALAO, nome, duracaoMin, intervaloMin:0, preco, ativo:true,
    aceitaOnline:true, categoria, foto, descricao: 'Com hora marcada.' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const porMoldura = moldura => dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#4F7356',
  moldura, funcionamento: SEMANA } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function escolher(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:900 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('#capaServicos .sv-cartao'), null, { timeout: 15000 });
  return { p, fechar: () => ctx.close() };
}
/* As peças de um cartão, na ordem: o que faz dele "o cartão da capa". */
const PECAS = `el => [...el.querySelectorAll('*')].map(x => [...x.classList].find(c => c.startsWith('sv-cartao')))
  .filter(Boolean).filter(c => c !== 'sv-cartao-marca' && c !== 'sv-cartao-ir' && c !== 'sv-cartao-preco'
    && c !== 'sv-cartao-apartir')`;

for(const moldura of ['elegante', 'reta']){
  const nome = moldura === 'elegante' ? 'Curvada' : 'Clássica';
  await porMoldura(moldura);
  const { p, fechar } = await escolher();

  secao(`1. ${nome}: o cartão da capa na escolha`);
  const capa = await p.evaluate(pc => { const f = eval(pc);
    const c = [...document.querySelectorAll('#capaServicos .sv-cartao')].find(x => /Manicure/.test(x.textContent));
    return c ? f(c) : null; }, PECAS);
  await p.evaluate(() => irPara('servico'));
  await p.waitForTimeout(500);
  const t = await p.evaluate(pc => { const f = eval(pc);
    const cs = [...document.querySelectorAll('#listaServicos .sv-cartao')];
    const man = cs.find(x => /Manicure/.test(x.textContent));
    const foto = man.querySelector('.sv-cartao-foto');
    return { cartoes: cs.length, fileiras: document.querySelectorAll('#listaServicos .opcao').length,
      pecas: f(man), grades: document.querySelectorAll('#listaServicos .sv-grade').length,
      categorias: [...document.querySelectorAll('#listaServicos .cat')].map(c => c.textContent.trim()),
      onda: getComputedStyle(foto).maskImage || getComputedStyle(foto).webkitMaskImage || 'none',
      marca: !!man.querySelector('.sv-cartao-marca'), seta: !!man.querySelector('.sv-cartao-ir'),
      precos: cs.map(c => (c.querySelector('.sv-cartao-preco') || {}).textContent || '').filter(Boolean).length,
      combo: cs.filter(c => c.querySelector('.selo-combo')).map(c => c.querySelector('b').firstChild.textContent.trim()),
      iniciais: document.querySelectorAll('#listaServicos .sv-cartao-inicial').length,
      // Onde a marca fica: embaixo, no lugar da seta, na Curvada; no alto, na Clássica.
      marcaEmbaixo: (() => { const r = man.getBoundingClientRect(), k = man.querySelector('.sv-cartao-marca').getBoundingClientRect();
        return r.bottom - k.bottom < 30; })(),
      moldura: document.documentElement.getAttribute('data-moldura') || 'reta' };
  }, PECAS);
  igual('os oito serviços em cartões, nenhuma fileira antiga', [t.cartoes, t.fileiras], [8, 0]);
  igual('o cartão tem as mesmas peças do da capa', t.pecas, capa);
  igual('uma grade por categoria, com o título dela', [t.grades, t.categorias], [2, ['Cabelo', 'Unhas']]);
  igual(`a moldura é a de Aparência (${nome})`, t.moldura, moldura);
  verdade(moldura === 'elegante' ? 'a foto tem a onda da Curvada' : 'a foto é reta, como na Clássica',
    moldura === 'elegante' ? /url/.test(t.onda) : t.onda === 'none', t.onda);
  igual('no canto, a marca de escolher (e não a seta de ir)', [t.marca, t.seta], [true, false]);
  igual('todos com preço, e o COMBO no combo', [t.precos, t.combo], [8, ['Mão e pé']]);
  igual('quem não tem foto ganha a inicial, como na capa', t.iniciais, 4);
  igual(moldura === 'elegante' ? 'a marca fica embaixo, no lugar da seta' : 'a marca fica no alto, no canto da foto',
    t.marcaEmbaixo, moldura === 'elegante');

  secao(`2. ${nome}: tocar escolhe, e pode mais de um`);
  const marca = nomeSv => p.evaluate(n => { const c = [...document.querySelectorAll('#listaServicos .sv-cartao')]
    .find(x => new RegExp(n).test(x.textContent));
    const k = c.querySelector('.sv-cartao-marca');
    // A cor do botão, resolvida pelo navegador, para comparar com o fundo da marca.
    const i = document.createElement('i');
    i.style.color = getComputedStyle(document.documentElement).getPropertyValue('--acao').trim();
    document.body.appendChild(i);
    const cheia = getComputedStyle(k).backgroundColor === getComputedStyle(i).color;
    i.remove();
    return { sel: c.classList.contains('sel'), aria: c.getAttribute('aria-pressed'), visto: !!k.querySelector('svg'), cheia }; }, nomeSv);
  await p.locator('#listaServicos .sv-cartao', { hasText: 'Coloração' }).click();
  await p.locator('#listaServicos .sv-cartao', { hasText: 'Manicure' }).click();
  await p.waitForTimeout(300);
  igual('os dois tocados ficam marcados: borda, visto e a marca cheia na cor do botão',
    [await marca('Coloração'), await marca('Manicure')],
    [{ sel:true, aria:'true', visto:true, cheia:true }, { sel:true, aria:'true', visto:true, cheia:true }]);
  igual('e os outros não', await marca('Escova'), { sel:false, aria:'false', visto:false, cheia:false });
  const soma = await p.evaluate(() => document.querySelector('#listaServicos .recado').textContent.replace(/\s+/g, ' ').trim());
  verdade('a soma embaixo conta os dois', /2 serviços · 170 min · R\$\s*190,00/.test(soma), soma);
  await p.locator('#listaServicos .sv-cartao', { hasText: 'Coloração' }).click();
  await p.waitForTimeout(200);
  igual('tocar de novo desescolhe', [(await marca('Coloração')).sel, await p.evaluate(() => escolha.servicos.length)], [false, 1]);
  if(moldura === 'elegante'){
    const relogios = await p.evaluate(() => [document.querySelectorAll('#listaServicos .sv-cartao-relogio').length,
      document.querySelectorAll('#listaServicos .sv-cartao-relogio svg').length]);
    igual('o relógio de cada cartão continua depois dos toques', relogios, [8, 8]);
  }
  const alvo = await p.evaluate(() => Math.min(...[...document.querySelectorAll('#listaServicos .sv-cartao')]
    .map(c => c.getBoundingClientRect().height)));
  verdade('e cada cartão é um alvo de dedo', alvo >= 44, String(alvo));

  secao(`3. ${nome}: a busca continua`);
  await p.fill('#buscaServico', 'pe');
  await p.waitForTimeout(300);
  igual('buscar "pe" deixa só os de pé', await p.evaluate(() =>
    [...document.querySelectorAll('#listaServicos .sv-cartao b')].map(b => b.firstChild.textContent.trim()).sort()),
    ['Mão e pé', 'Pedicure', 'Spa dos pés']);
  await fechar();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
