/* ===========================================================================
   AgendaPro — o painel diz por que os produtos não aparecem no link

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/loja-aviso.test.mjs

   A reclamação, com estas palavras: "não estou enxergando os produtos".

   A página da cliente esconde a loja inteira em três casos — loja desligada,
   salão sem WhatsApp, nenhum produto marcado para o link — e o painel não
   dizia nenhum. Pior: a coluna "Na loja" da lista de produtos dizia "à
   venda" enquanto a página não mostrava nada. A tela do dono afirmava o
   contrário do que a cliente via.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a PREMISSA: sem WhatsApp a página esconde mesmo a loja. Sem medir isso
        o aviso poderia estar acusando um defeito que não existe;
     2. o aviso em Produtos, para cada um dos três motivos, e a ausência dele
        quando está tudo certo;
     3. o aviso na aba Dados some ENQUANTO o dono digita o número;
     4. o espelho: `zapDaCasa()` do painel responde igual ao `zapDoSalao()` da
        página, número a número. Os dois divergindo é o aviso dizendo "está
        certo" e a página escondendo — o defeito voltando por outro caminho.
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

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`la-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa da Loja',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prod = await dona.inserir('produtos', { salaoId: SALAO, nome:'Shampoo',
  preco:45, custo:20, ativo:true, vendaOnline:true });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* Um contexto novo a cada pergunta: o painel guarda cópia local das tabelas, e
   reaproveitar a aba mediria o salão de ANTES da mudança feita pela bancada. */
async function painel(tela){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                     isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  /* ⚠ `bd` NASCE NULO e só vira objeto quando os dados chegam. A primeira
     versão desta espera lia `bd.produtos` direto, e o erro que ela mesma
     lançava aparecia como "erro da página" — oito reprovações acusando o
     painel por uma falha do teste. */
  await p.waitForFunction(() => typeof irPara === 'function'
    && typeof bd !== 'undefined' && bd && Array.isArray(bd.produtos), null,
    { timeout: 20000 });
  await p.waitForTimeout(1500);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(t => irPara(t), tela);
  await p.waitForTimeout(700);
  return { p, fechar: () => ctx.close() };
}

async function avisoEmProdutos(){
  const { p, fechar } = await painel('produtos');
  const t = await p.evaluate(() => {
    const e = document.getElementById('avisoLojaLink');
    return e ? e.textContent.replace(/\s+/g, ' ').trim() : '';
  });
  await fechar();
  return t;
}

async function lojaNaPagina(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                     isMobile:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('página: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => {
    const e = document.getElementById('capaMarca');
    return e && e.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  await p.waitForTimeout(600);
  const n = await p.evaluate(() =>
    document.querySelectorAll('#capaLoja .pr-cartao').length);
  await ctx.close();
  return n;
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — A PREMISSA, E O CASO BOM
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · Com WhatsApp, a loja aparece e o painel não reclama');
verdade('a página mostra o produto', await lojaNaPagina() === 1);
igual('e Produtos não tem aviso nenhum', await avisoEmProdutos(), '');

secao('2 · Sem WhatsApp');
await dona.atualizar('saloes', SALAO, { telefone: null, whatsapp: null });
igual('a página esconde a loja — a premissa do aviso', await lojaNaPagina(), 0);
const semZap = await avisoEmProdutos();
verdade('e Produtos diz que falta o WhatsApp', /sem WhatsApp/.test(semZap), semZap);
verdade('dizendo onde se preenche', /Meu salão → Dados → WhatsApp/.test(semZap), semZap);

/* ⚠ UM NÚMERO QUE NÃO ABRE CONVERSA É O MESMO QUE NENHUM. Nove dígitos, sem
   DDD: o campo não está vazio, e é exatamente o caso em que um aviso que
   olhasse só "tem alguma coisa escrita?" diria que está tudo certo. */
await dona.atualizar('saloes', SALAO, { whatsapp: '98111-3251' });
igual('número sem DDD: a página também esconde', await lojaNaPagina(), 0);
verdade('e o painel também avisa',
  /sem WhatsApp/.test(await avisoEmProdutos()));

await dona.atualizar('saloes', SALAO, { whatsapp: '(11) 98111-3251' });
igual('com o número de volta, o aviso some', await avisoEmProdutos(), '');

secao('3 · Loja desligada');
const s0 = (await dona.lista('saloes', { id: SALAO }))[0];
await dona.atualizar('saloes', SALAO, { cfg: { ...(s0.cfg || {}), loja: false } });
igual('a página esconde', await lojaNaPagina(), 0);
const deslig = await avisoEmProdutos();
verdade('e Produtos diz que a loja está desligada', /desligada/.test(deslig), deslig);
await dona.atualizar('saloes', SALAO, { cfg: { ...(s0.cfg || {}), loja: true } });

secao('4 · Nenhum produto marcado para o link');
await dona.atualizar('produtos', prod.id, { vendaOnline: false });
igual('a página esconde', await lojaNaPagina(), 0);
const nenhum = await avisoEmProdutos();
verdade('e Produtos diz o que marcar',
  /Vender na página do salão/.test(nenhum), nenhum);
await dona.atualizar('produtos', prod.id, { vendaOnline: true });

/* ══════════════════════════════════════════════════════════════════════════
   5 — NA ABA DADOS, O AVISO RESPONDE AO QUE ESTÁ DIGITADO
   ══════════════════════════════════════════════════════════════════════════ */
secao('5 · Aba Dados: o aviso some enquanto o dono digita');
await dona.atualizar('saloes', SALAO, { telefone: null, whatsapp: null });
{
  const { p, fechar } = await painel('salao');
  await p.evaluate(() => trocarAbaSalao('dados'));
  await p.waitForTimeout(500);
  const tem = () => p.evaluate(() => !!document.getElementById('avisoLojaModulos'));
  verdade('sem número, o aviso aparece ao lado dos interruptores', await tem());
  await p.fill('#cZap', '(11) 98111-3251');
  verdade('digitado o número, ele some — antes de salvar', !(await tem()));
  await p.fill('#cZap', '');
  verdade('apagado, ele volta', await tem());
  await p.fill('#cTel', '(11) 3333-4444');
  verdade('o telefone fixo também serve, como na página', !(await tem()));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   6 — O ESPELHO
   ══════════════════════════════════════════════════════════════════════════ */
secao('6 · O painel e a página respondem igual, número a número');
/* O quinto é o que separa as duas réguas do painel: 13 dígitos sem o 55. O
   `numeroWhatsapp()` aceita; a página recusa. Um aviso escrito com a régua
   errada diria "está certo" e a loja continuaria sumida. */
const NUMEROS = ['', '12345', '98111-3251', '(11) 3333-4444', '(11) 98111-3251',
                 '4412345678901', '+55 11 98111-3251', '5511981113251'];
{
  const { p: pa, fechar } = await painel('produtos');
  const ctx = await nav.newContext();
  const pg = await ctx.newPage();
  await pg.goto(BASE + '/agendar.html?salao=' + SLUG);
  await pg.waitForFunction(() => typeof zapDoSalao === 'function'
    && typeof salao !== 'undefined' && salao, null, { timeout: 15000 });
  for(const n of NUMEROS){
    const naPagina = await pg.evaluate(x => {
      salao = Object.assign({}, salao, { whatsapp: x, telefone: null });
      return zapDoSalao();
    }, n);
    const noPainel = await pa.evaluate(x => zapDaCasa({}, x), n);
    igual(JSON.stringify(n) + ' → ' + (naPagina || 'nenhum'), noPainel, naPagina);
  }
  await ctx.close();
  await fechar();
}

igual('nenhum erro nas telas', erros, []);
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
