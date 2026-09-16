/* ===========================================================================
   AgendaPro — o carrinho e a loja que muda por baixo dele

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/carrinho.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   O carrinho mora no `localStorage` da cliente e guarda IDS de produto. A loja
   não fica parada: a dona desmarca "vender online" quando acaba o estoque,
   desativa um produto, ou apaga. O carrinho da cliente não fica sabendo.

   O `loja.test.sql` cobre a `vitrine()`: quem aparece e quem não aparece. Não
   cobre — não tem como — o que a TELA faz com um id que ela guardou ontem e
   que hoje não existe mais na lista.

   ── O DEFEITO QUE ISTO PEGOU ──────────────────────────────────────────────
   O `itensNoCarrinho()` contava `Object.values(carrinho)`, tudo, enquanto o
   `totalDoCarrinho()` e o `textoDoPedido()` percorriam a LOJA. As três
   discordavam. Medido, com os dois produtos despublicados:

       itensNoCarrinho() = 3      totalDoCarrinho() = 0

   O botão "Enviar pedido no WhatsApp" ficava LIGADO, e a cliente mandava:

       "Olá! Vim pela página do Salão X e quero estes produtos:
        (nada)
        Total estimado: R$ 0,00"

   Sem erro nenhum no console. A dona recebia uma mensagem sem produto e a
   cliente saía achando que tinha pedido. O pior tipo: silencioso, e com
   consequência para duas pessoas de verdade.
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
const igual = (m, a, b) => a === b ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
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
const d = novaAba();
await d.criarConta({ email:`carr-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona do Balcão', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão Carrinho ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;

const SHAMPOO = crypto.randomUUID(), COND = crypto.randomUUID();
const base = await d.baixar(SALAO);
const com = JSON.parse(JSON.stringify(base));
com.produtos = [
  { id:SHAMPOO, salaoId:SALAO, nome:'Shampoo', marca:'X', descricao:'', preco:45,
    custo:18, estoque:10, comissaoPct:0, comissaoFixa:null, ativo:true,
    vendaOnline:true, foto:null },
  { id:COND, salaoId:SALAO, nome:'Condicionador', marca:'X', descricao:'', preco:38,
    custo:15, estoque:10, comissaoPct:0, comissaoFixa:null, ativo:true,
    vendaOnline:true, foto:null },
];
await d.subir(base, com);
ok('salão com dois produtos na loja');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:412, height:915 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push(x.message));

async function abrir(){
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForTimeout(2400);
}
/* As três contas, do mesmo instante. Medi-las juntas é o ponto do arquivo: o
   defeito não estava em nenhuma delas isolada, estava na DISCORDÂNCIA. */
const contas = () => p.evaluate(() => {
  let texto = '';
  try{ texto = textoDoPedido(); }catch(e){ texto = 'ERRO: ' + e.message; }
  const bp = document.getElementById('btPrincipal') || {};
  return { itens: itensNoCarrinho(), total: totalDoCarrinho(), texto,
           naLoja: (bd.produtos || []).length,
           botao: (bp.textContent || '').trim(), ligado: !bp.disabled };
});
// Quantas linhas de "• produto" a mensagem tem.
const linhas = t => (String(t).match(/^•/gm) || []).length;

/* ══════════════════════════════════════════════════════════════════════════
   1 — COM OS DOIS À VENDA, TUDO CONFERE
   ══════════════════════════════════════════════════════════════════════════ */
secao('Com os dois produtos na loja');

await abrir();
await p.evaluate(([a, b]) => { mudarNoCarrinho(a, 2); mudarNoCarrinho(b, 1); },
  [SHAMPOO, COND]);
await p.waitForTimeout(400);

const cheio = await contas();
igual('o carrinho conta 3 unidades', cheio.itens, 3);
igual('o total é 2×45 + 1×38', cheio.total, 128);
igual('e a mensagem lista os dois', linhas(cheio.texto), 2);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A DONA DESPUBLICA UM. O CARRINHO TEM QUE ACOMPANHAR.

   É o caso comum: acabou o estoque do shampoo, ela desmarca. O condicionador
   continua à venda, e o pedido tem que sair com ele e só com ele.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A dona tira o shampoo da loja (2 × R$ 45)');

const a2 = await d.baixar(SALAO);
const b2 = JSON.parse(JSON.stringify(a2));
b2.produtos.find(x => x.id === SHAMPOO).vendaOnline = false;
await d.subir(a2, b2);

await abrir();
const meio = await contas();
igual('a loja passa a ter 1 produto', meio.naLoja, 1);
/* ⚠ A ASSERÇÃO QUE PEGOU O DEFEITO. Aqui saía 3: o shampoo despublicado
   continuava contando, e a capa dizia "Ver o carrinho (3)" com R$ 38 dentro. */
igual('o carrinho conta só 1 unidade — a que ainda está à venda', meio.itens, 1);
igual('o total é só o condicionador', meio.total, 38);
igual('e a mensagem lista só ele', linhas(meio.texto), 1);
verdade('com o nome certo', /Condicionador/.test(meio.texto) && !/Shampoo/.test(meio.texto),
  meio.texto);

/* ⚠ AS TRÊS TÊM QUE CONCORDAR, e não só estar cada uma certa por conta.
   Era exatamente a discordância que produzia o pedido vazio. */
const somaDaMensagem = (meio.texto.match(/— (\d+)x/g) || [])
  .reduce((s, m) => s + Number(m.match(/\d+/)[0]), 0);
igual('a contagem e a mensagem falam o mesmo número', meio.itens, somaDaMensagem);

/* ══════════════════════════════════════════════════════════════════════════
   3 — E SE TODOS SAÍREM, O BOTÃO NÃO PODE MANDAR PEDIDO VAZIO
   ══════════════════════════════════════════════════════════════════════════ */
secao('A dona tira o resto da loja');

const a3 = await d.baixar(SALAO);
const b3 = JSON.parse(JSON.stringify(a3));
b3.produtos.forEach(x => { x.vendaOnline = false; });
await d.subir(a3, b3);

await abrir();
const vazio = await contas();
igual('a loja fica sem produto', vazio.naLoja, 0);
igual('e o carrinho deixa de contar', vazio.itens, 0);
igual('o total zera', vazio.total, 0);

await p.evaluate(() => irPara('loja'));
await p.waitForTimeout(700);
const naLoja = await contas();
/* O botão DESLIGADO é a trava de verdade: o `enviarPedido()` sai cedo quando
   `itensNoCarrinho()` é zero. Ligado, ele abria o WhatsApp com uma mensagem
   sem produto nenhum — e nem a dona nem a cliente entenderiam o que houve. */
verdade('o botão de enviar fica DESLIGADO', !naLoja.ligado,
  'botão "' + naLoja.botao + '" ligado — mandaria um pedido vazio');
verdade('e diz o que falta, em vez de ficar cinza mudo',
  /produto/i.test(naLoja.botao), JSON.stringify(naLoja.botao));

/* ══════════════════════════════════════════════════════════════════════════
   4 — E O QUE FICOU GUARDADO VOLTA QUANDO O PRODUTO VOLTA

   Não apagamos o carrinho de propósito. Produto despublicado por dois dias
   volta com as unidades que a cliente já tinha escolhido, e produto que não
   volta simplesmente nunca mais é contado.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O produto volta para a loja');

const a4 = await d.baixar(SALAO);
const b4 = JSON.parse(JSON.stringify(a4));
b4.produtos.find(x => x.id === SHAMPOO).vendaOnline = true;
await d.subir(a4, b4);

await abrir();
const devolta = await contas();
igual('o shampoo volta a contar, com as 2 unidades de antes', devolta.itens, 2);
igual('e o total volta com ele', devolta.total, 90);
verdade('a mensagem o nomeia de novo', /Shampoo/.test(devolta.texto), devolta.texto);

igual('nenhum erro de JavaScript no percurso',
  erros.length ? erros.slice(0, 3).join(' | ') : 0, 0);

await ctx.close();
await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
