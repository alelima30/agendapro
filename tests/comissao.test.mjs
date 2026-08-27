/* ===========================================================================
   AgendaPro — a escada da comissão: a tela e o banco dizem o mesmo?

     bash tests/bancada/subir.sh
     node tests/comissao.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   A regra da comissão está escrita DUAS VEZES neste projeto, de propósito:

     · `comissao_de()` no 16_comissao.sql — quem DECIDE. O gatilho grava a
       taxa que ela devolver, ignorando o que o navegador mandar.
     · `comissaoDaEscada()` no app.html — quem MOSTRA, no instante em que a
       recepção lança o item, antes de a gravação voltar do servidor.

   Duas cópias da mesma regra é dívida assumida: sem a segunda, o item
   aparece com R$ 0,00 de comissão e pula para R$ 40,00 um segundo depois,
   com a cliente na cadeira. Com a segunda, existe o risco de elas se
   separarem — e quando se separam, a tela mente por alguns segundos e
   ninguém liga uma coisa à outra.

   Este arquivo é o preço da dívida: percorre todos os arranjos da escada
   (par, catálogo, pessoa, zero, fixa, pct+fixa, produto) e exige que os dois
   lados devolvam o MESMO número. Mexer num sem mexer no outro reprova aqui.

   É o mesmo remédio do `relatorios.test.mjs`, que compara `relatorioLocal()`
   com `relatorio()`, e pela mesma razão: as duas contas já se separaram uma
   vez neste projeto.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
const secao = t => console.log('\n' + t);

const cliente = new pg.Client({
  host: process.env.PGHOST || '/tmp', port: +(process.env.PGPORT || 5444),
  user: process.env.PGUSER || 'postgres', database: process.env.PGBANCO || 'app',
});
await cliente.connect();

/* ── A tela, sem navegador ─────────────────────────────────────────────────
   `comissaoDaEscada` e `comissaoDoItem` são funções soltas dentro do
   app.html. Em vez de subir um Chromium só para chamá-las, recorto o bloco
   inteiro do arquivo e avalio aqui — assim o teste lê o MESMO texto que vai
   para o navegador, e não uma cópia que alguém esqueceu de atualizar. */
const html = fs.readFileSync(path.join(RAIZ, 'app.html'), 'utf8');
const de = html.indexOf('function comissaoDaEscada(');
const ate = html.indexOf('const comissaoDaComanda =');
if(de < 0 || ate < 0){
  console.log('✗ não achei o bloco da comissão no app.html — ele foi renomeado?');
  process.exit(1);
}
const fimBloco = html.indexOf(';', html.indexOf('\n', ate)) + 1;
const fonte = html.slice(de, fimBloco);

// O que o bloco usa de fora, de mentirinha.
const bd = { servicos: [], produtos: [], profissionais: [], servicos_profissionais: [] };
const acharServico = id => bd.servicos.find(x => x.id === id);
const acharProf    = id => bd.profissionais.find(x => x.id === id);
const subtotalDaComanda = c => c.itens.reduce((s,i) => s + i.qtd*i.precoUnit, 0);

const tela = new Function('bd', 'acharServico', 'acharProf', 'subtotalDaComanda',
  fonte + '\n return { comissaoDaEscada, comissaoDoItem, comissaoDaComanda };'
)(bd, acharServico, acharProf, subtotalDaComanda);

/* ── O cenário ───────────────────────────────────────────────────────────── */
/* uuid de verdade: só hexadecimal. A primeira versão usava base36 no sufixo
   e o Postgres recusava com «invalid input syntax for type uuid» — base36
   tem letras até o z, e uuid só vai até o f. */
const marca = Date.now().toString(16).slice(-8)
            + Math.floor(Math.random()*0xffff).toString(16).padStart(4,'0');
const uid = n => `f0000000-${n}-0000-0000-${marca.padStart(12,'0').slice(-12)}`;

const SALAO = uid('1111'), ANA = uid('5555'), BIA = uid('5556');
const CLI = uid('7777');

// Duas chamadas, e não duas instruções numa: com parâmetro o `pg` usa
// prepared statement, e prepared statement aceita UM comando só.
await cliente.query(
  `insert into public.saloes (id, slug, nome, tipo)
        values ($1, 'com-${marca}', 'Salão Comissão', 'salao')`, [SALAO]);
await cliente.query(
  `insert into public.assinaturas (salao_id, plano, status)
        values ($1, 'time', 'ativa')`, [SALAO]);

await cliente.query(`
  insert into public.profissionais (id, salao_id, nome, comissao_pct, comissao_fixa)
  values ($2, $1, 'Ana', 40, null), ($3, $1, 'Bia', 30, 7)
`, [SALAO, ANA, BIA]);

await cliente.query(`
  insert into public.clientes (id, salao_id, nome, telefone)
  values ($2, $1, 'Clara', '55119${Math.floor(Math.random()*90000000+10000000)}')
`, [SALAO, CLI]);

// A tela enxerga o mesmo cadastro.
bd.profissionais = [
  { id: ANA, nome: 'Ana', comissaoPct: 40, comissaoFixa: null },
  { id: BIA, nome: 'Bia', comissaoPct: 30, comissaoFixa: 7 },
];

/* Cada arranjo é um serviço diferente, para um não contaminar o outro — foi
   um par esquecido entre seções que fez o `comissao.test.sql` reprovar por
   sujeira própria enquanto a regra estava certa. */
const ARRANJOS = [
  { nome: 'serviço calado, cai na pessoa',        pct: null, fixa: null, par: null },
  { nome: 'serviço com pct própria',              pct: 55,   fixa: null, par: null },
  { nome: 'serviço com fixa própria',             pct: null, fixa: 9,    par: null },
  { nome: 'serviço com pct E fixa',               pct: 15,   fixa: 4,    par: null },
  { nome: 'serviço dizendo ZERO de propósito',    pct: 0,    fixa: null, par: null },
  { nome: 'o par manda mais que o serviço',       pct: 55,   fixa: null, par: { pct: 70, fixa: null } },
  { nome: 'o par com fixa manda mais',            pct: 55,   fixa: null, par: { pct: null, fixa: 25 } },
  { nome: 'o par dizendo ZERO manda',             pct: 55,   fixa: null, par: { pct: 0, fixa: null } },
];

secao('A escada, arranjo por arranjo — tela contra banco');

let n = 0;
for(const a of ARRANJOS){
  for(const prof of [ANA, BIA]){
    n++;
    const sv = uid(String(6000 + n));
    await cliente.query(`
      insert into public.servicos (id, salao_id, nome, duracao_min, preco,
                                   comissao_pct, comissao_fixa)
      values ($2, $1, $3, 60, 100, $4, $5)
    `, [SALAO, sv, 'S' + n, a.pct, a.fixa]);

    if(a.par){
      await cliente.query(`
        insert into public.servicos_profissionais
          (servico_id, profissional_id, comissao_pct, comissao_fixa)
        values ($1, $2, $3, $4)
      `, [sv, prof, a.par.pct, a.par.fixa]);
    }

    bd.servicos.push({ id: sv, nome: 'S' + n, preco: 100,
                       comissaoPct: a.pct, comissaoFixa: a.fixa });
    if(a.par){
      bd.servicos_profissionais.push({ servicoId: sv, profissionalId: prof,
        comissaoPct: a.par.pct, comissaoFixa: a.par.fixa });
    }

    const r = await cliente.query(
      `select pct, fixa from public.comissao_de('servico', $1, null, $2)`, [sv, prof]);
    const banco = { pct: Number(r.rows[0].pct), fixa: Number(r.rows[0].fixa) };
    const t = tela.comissaoDaEscada('servico', sv, null, prof);

    verdade(`${a.nome} · ${prof === ANA ? 'Ana' : 'Bia'}`,
      banco.pct === t.pct && banco.fixa === t.fixa,
      `banco ${banco.pct}% + ${banco.fixa} · tela ${t.pct}% + ${t.fixa}`);
  }
}

secao('O valor do item — bruto e líquido, tela contra banco');

/* Aqui não basta a taxa bater: o que a recepção lê é o VALOR, e é nele que
   entram o rateio do desconto e a multiplicação da fixa pela quantidade. */
for(const regra of ['bruto', 'liquido']){
  const com = uid(regra === 'bruto' ? 'aaa1' : 'aaa2');

  /* ⚠ A regra se muda no SALÃO, não na comanda.

     A primeira versão deste teste mandava `comissao_sobre` no INSERT da
     comanda e o banco devolvia comissão de bruto mesmo assim — o teste
     acusou 40 contra 36. Não era defeito: `tg_comanda_regra` sobrescreve o
     campo a partir do ajuste do salão e da data de corte, justamente para
     ninguém escolher a regra de comissão no ato de abrir uma comanda.

     Ou seja, o teste tentou forjar a regra e a trava barrou. Corrigir o
     teste é o certo; "corrigir" o gatilho para aceitar o valor de fora
     seria abrir o buraco que este módulo veio fechar. */
  await cliente.query(
    `update public.saloes
        set comissao_sobre = $2, comissao_regra_desde = current_date - 1
      where id = $1`, [SALAO, regra]);

  await cliente.query(`
    insert into public.comandas (id, salao_id, cliente_id, status)
    values ($2, $1, $3, 'aberta')
  `, [SALAO, com, CLI]);

  const congelada = (await cliente.query(
    `select comissao_sobre from public.comandas where id = $1`, [com])).rows[0].comissao_sobre;
  verdade(`a comanda nasceu com a regra '${regra}' congelada`,
    congelada === regra, `veio '${congelada}'`);

  // Dois itens de valores diferentes, para o rateio do desconto não ser
  // simétrico — desconto dividido meio a meio esconde erro de rateio.
  const itens = [
    { sv: bd.servicos[1].id, prof: ANA, qtd: 1, preco: 100 },
    { sv: bd.servicos[5].id, prof: BIA, qtd: 3, preco: 90  },
  ];
  for(const it of itens){
    await cliente.query(`
      insert into public.comanda_itens
        (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
      values ($1, 'servico', $2, 'item', $3, $4, $5)
    `, [com, it.sv, it.qtd, it.preco, it.prof]);
  }
  await cliente.query(`update public.comandas set desconto = 37 where id = $1`, [com]);

  const linhas = (await cliente.query(`
    select i.id, i.servico_id, i.profissional_id, i.qtd, i.preco_unit,
           i.comissao_pct, i.comissao_fixa, k.comissao_valor
      from public.comanda_itens i
      join public.comanda_itens_calculados k on k.id = i.id
     where i.comanda_id = $1 order by i.preco_unit
  `, [com])).rows;

  const cTela = {
    comissaoSobre: regra, desconto: 37, acrescimo: 0,
    itens: linhas.map(l => ({
      tipo: 'servico', servicoId: l.servico_id, produtoId: null,
      profissionalId: l.profissional_id,
      qtd: Number(l.qtd), precoUnit: Number(l.preco_unit),
      comissaoPct: Number(l.comissao_pct), comissaoFixa: Number(l.comissao_fixa),
    })),
  };

  for(let k = 0; k < linhas.length; k++){
    const doBanco = Number(linhas[k].comissao_valor);
    const daTela  = tela.comissaoDoItem(cTela, cTela.itens[k]);
    verdade(`${regra}: item de ${linhas[k].preco_unit} × ${linhas[k].qtd}`,
      Math.abs(doBanco - daTela) < 0.005,
      `banco ${doBanco} · tela ${daTela}`);
  }

  const somaBanco = Number((await cliente.query(
    `select comissao_total from public.comandas_totais where id = $1`, [com])).rows[0].comissao_total);
  verdade(`${regra}: a soma da comanda bate`,
    Math.abs(somaBanco - tela.comissaoDaComanda(cTela)) < 0.005,
    `banco ${somaBanco} · tela ${tela.comissaoDaComanda(cTela)}`);
}

secao('O acréscimo não entra na comissão, nos dois lados');
{
  const com = uid('aaa3');
  await cliente.query(`
    insert into public.comandas (id, salao_id, cliente_id, status, comissao_sobre)
    values ($2, $1, $3, 'aberta', 'liquido')
  `, [SALAO, com, CLI]);
  await cliente.query(`
    insert into public.comanda_itens
      (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
    values ($1, 'servico', $2, 'item', 1, 200, $3)
  `, [com, bd.servicos[1].id, ANA]);

  const antes = Number((await cliente.query(
    `select comissao_total from public.comandas_totais where id=$1`, [com])).rows[0].comissao_total);
  await cliente.query(`update public.comandas set acrescimo = 150 where id = $1`, [com]);
  const depois = Number((await cliente.query(
    `select comissao_total from public.comandas_totais where id=$1`, [com])).rows[0].comissao_total);

  verdade('no banco, o acréscimo não mexeu na comissão',
    antes === depois, `${antes} → ${depois}`);

  const c1 = { comissaoSobre:'liquido', desconto:0, acrescimo:0,
    itens:[{ tipo:'servico', servicoId:bd.servicos[1].id, profissionalId:ANA,
             qtd:1, precoUnit:200, comissaoPct:55, comissaoFixa:0 }] };
  const c2 = { ...c1, acrescimo: 150 };
  verdade('na tela também',
    tela.comissaoDaComanda(c1) === tela.comissaoDaComanda(c2),
    `${tela.comissaoDaComanda(c1)} → ${tela.comissaoDaComanda(c2)}`);
}

await cliente.query(`delete from public.saloes where id = $1`, [SALAO]);
await cliente.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações da escada da comissão.`);
