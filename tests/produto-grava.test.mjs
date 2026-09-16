/* ===========================================================================
   AgendaPro — o produto chega mesmo ao banco

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/produto-grava.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   O `produtos.test.sql` cobria o módulo e passava: colunas, teto do plano,
   RLS, gatilho. Todas as inserções dele são feitas como superusuário, com os
   valores escritos à mão.

   O caminho de VERDADE é outro: a tela monta um objeto, o `dados.js` traduz
   para colunas, o PostgREST insere. E foi aí que quebrou — `comissaoPct`
   saindo `null` para uma coluna `not null`, porque a tela do produto foi
   escrita copiando a do serviço, onde nulo quer dizer "herda".

   O efeito não era perder o campo: era a gravação INTEIRA do painel ser
   recusada, e o produto sumir. O dono cadastrava, via o aviso de erro, e o
   banco continuava vazio.

   Nenhum teste de SQL pegaria isso, porque nenhum deles passa pela tradução.
   Este passa, com o mesmo `dados.js` que o painel carrega.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
await d.criarConta({ email:`prod-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona do Balcão', telefone:'+5511' + (100000000 + (Date.now() % 89999999)) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão Produto ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444',
  p_documento:'11222333000181', p_origem:null });
const SALAO = cr[0].salao_id;

/* O objeto EXATAMENTE como `salvarProduto()` do app.html o monta. Se aquela
   função mudar de forma, este teste tem que mudar junto — e é de propósito:
   é o contrato entre a tela e o banco que está sendo medido. */
const comoATelaMonta = (extra) => Object.assign({
  id: crypto.randomUUID(), salaoId: SALAO,
  nome: 'Shampoo sem sal', marca: 'MarcaX',
  descricao: 'Para cabelo com química',
  preco: 45, custo: 18, estoque: 10,
  comissaoPct: 0,          // em branco na tela vale ZERO, não null
  comissaoFixa: null,      // esta sim é anulável: "não usa valor fixo"
  ativo: true, vendaOnline: false, foto: null,
}, extra || {});

secao('O produto cadastrado na tela chega ao banco');

const antes = await d.baixar(SALAO);
igual('o salão começa sem produto nenhum', (antes.produtos || []).length, 0);

const agora = JSON.parse(JSON.stringify(antes));
const novo = comoATelaMonta();
agora.produtos = [novo];

let recusa = null;
try{ await d.subir(antes, agora); }catch(e){ recusa = e.message; }
verdade('o subir() não é recusado pelo banco', recusa === null, recusa);

const depois = await d.baixar(SALAO);
const gravado = (depois.produtos || []).find(p => p.id === novo.id);
verdade('e o produto está lá depois de recarregar', !!gravado,
  'o banco ficou com ' + (depois.produtos || []).length + ' produto(s)');

if(gravado){
  secao('E chegou inteiro, campo por campo');
  igual('nome',        gravado.nome, novo.nome);
  igual('marca',       gravado.marca, novo.marca);
  igual('descrição',   gravado.descricao, novo.descricao);
  igual('preço',       Number(gravado.preco), 45);
  igual('custo',       Number(gravado.custo), 18);
  igual('estoque',     Number(gravado.estoque), 10);
  /* ⚠ O CAMPO QUE QUEBROU. `produtos.comissao_pct` é `not null default 0`, ao
     contrário de `servicos.comissao_pct`. Mandar null daqui fazia o banco
     recusar a gravação INTEIRA — não só este campo. */
  igual('comissão em branco virou zero, e não null',
    Number(gravado.comissaoPct), 0);
  /* E a diferença entre as duas: esta continua podendo ser nula. Sem esta
     verificação, "consertar" a de cima mandando zero nas duas passaria — e
     zero em `comissao_fixa` quer dizer "usa valor fixo, de R$ 0,00", que é
     outra coisa. */
  verdade('mas a comissão FIXA continua podendo ser nula',
    gravado.comissaoFixa === null || gravado.comissaoFixa === undefined,
    JSON.stringify(gravado.comissaoFixa));
  verdade('e nasce fora da loja', gravado.vendaOnline === false,
    JSON.stringify(gravado.vendaOnline));
}

secao('E editar o que já existe também sobe');

if(gravado){
  const antes2 = await d.baixar(SALAO);
  const agora2 = JSON.parse(JSON.stringify(antes2));
  agora2.produtos[0].preco = 52.5;
  agora2.produtos[0].vendaOnline = true;
  let recusa2 = null;
  try{ await d.subir(antes2, agora2); }catch(e){ recusa2 = e.message; }
  verdade('a edição não é recusada', recusa2 === null, recusa2);

  const depois2 = await d.baixar(SALAO);
  const p2 = (depois2.produtos || []).find(p => p.id === novo.id) || {};
  igual('o preço novo ficou', Number(p2.preco), 52.5);
  verdade('e o produto foi para a loja', p2.vendaOnline === true,
    JSON.stringify(p2.vendaOnline));
}

console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
