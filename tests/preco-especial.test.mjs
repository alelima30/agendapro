/* ===========================================================================
   AgendaPro — o preço especial por salão (13_cobranca.sql, seção 1b)

     bash tests/bancada/subir.sh
     node tests/preco-especial.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Pode abrir a venda — e o preço deixa 1 real por enquanto neste salão."
   O preço é do PLANO, igual para todos: baixar o Essencial para R$ 1 e abrir
   a venda seria vender a R$ 1 para todo mundo. O preço especial é do salão.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. O salão com preço especial paga o especial — no Pix e no cartão.
     2. Os outros salões pagam o preço do plano.
     3. O especial vale só para o plano marcado.
     4. Ninguém dá desconto a si mesmo: o salão não escreve em `assinaturas`,
        e a função do preço não é chamável do navegador.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
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

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const um = async (sql, args = []) => (await banco.query(sql, args)).rows[0];

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const tel = () => '+5511' + (100000000 + Math.floor(Math.random()*89999999));

async function montar(nome){
  const d = novaAba();
  await d.criarConta({ email:`pe-${nome}-${marca}@teste.com`, senha:'minhasenhaboa',
    nome:'Dona ' + nome, telefone: tel() });
  const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão ' + nome + ' ' + marca,
    p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
  const salao = cr[0].salao_id;
  const dona = (await um(`select perfil_id from public.vinculos where salao_id=$1 and papel='dono'`,
    [salao])).perfil_id;
  return { d, salao, dona };
}

const ESPECIAL = await montar('Teste');
const NORMAL   = await montar('Normal');
await banco.query(`update public.assinaturas set precos_especiais = '{"individual": 1.00}'
                    where salao_id = $1`, [ESPECIAL.salao]);
const precoPlano = Number((await um(`select preco_mes from public.planos where codigo='individual'`)).preco_mes);

secao('1) Quem tem preço especial paga o especial');
igual('preco_do_plano: o especial do salão',
  Number((await um(`select public.preco_do_plano($1,'individual') as v`, [ESPECIAL.salao])).v), 1);
igual('o Pix sai com o especial',
  Number((await um(`select (public.abrir_cobranca($1,'individual','pix',$2)).valor as v`,
    [ESPECIAL.salao, ESPECIAL.dona])).v), 1);
igual('e o cartão também nasce com ele',
  Number((await um(`select (public.preparar_cartao($1,'individual',$2))->>'valor' as v`,
    [ESPECIAL.salao, ESPECIAL.dona])).v), 1);

secao('2) Os outros salões pagam o preço do plano');
igual('preco_do_plano: o do plano',
  Number((await um(`select public.preco_do_plano($1,'individual') as v`, [NORMAL.salao])).v), precoPlano);
igual('o Pix do salão normal sai com o preço do plano',
  Number((await um(`select (public.abrir_cobranca($1,'individual','pix',$2)).valor as v`,
    [NORMAL.salao, NORMAL.dona])).v), precoPlano);

secao('3) O especial vale só para o plano marcado');
const precoDuo = Number((await um(`select preco_mes from public.planos where codigo='duo'`)).preco_mes);
igual('outro plano, no mesmo salão, sai pelo preço normal',
  Number((await um(`select (public.abrir_cobranca($1,'duo','pix',$2)).valor as v`,
    [ESPECIAL.salao, ESPECIAL.dona])).v), precoDuo);
await banco.query(`update public.assinaturas set precos_especiais = '{"individual": "1"}'
                    where salao_id = $1`, [ESPECIAL.salao]);
igual('valor que não é número no mapa é ignorado (vale o normal)',
  Number((await um(`select public.preco_do_plano($1,'individual') as v`, [ESPECIAL.salao])).v), precoPlano);
await banco.query(`update public.assinaturas set precos_especiais = '{"individual": 1.00}'
                    where salao_id = $1`, [ESPECIAL.salao]);

secao('4) Ninguém dá desconto a si mesmo');
// O dono do salão NORMAL tenta escrever o próprio preço pela API, com a sessão dele.
const r = await fetch(`${BASE}/rest/v1/assinaturas?salao_id=eq.${NORMAL.salao}`, {
  method: 'PATCH',
  headers: { apikey:'k', Authorization: 'Bearer ' + NORMAL.d.sessao().token,
             'Content-Type':'application/json', Prefer:'return=representation' },
  body: JSON.stringify({ precos_especiais: { individual: 0.01 } }),
}).catch(e => ({ status: 0, erro: e.message }));
igual('o salão não consegue gravar preço especial para si',
  (await um(`select precos_especiais from public.assinaturas where salao_id=$1`, [NORMAL.salao])).precos_especiais, {});
verdade('(a API recusou ou não mudou nada)', r.status !== 0, JSON.stringify(r.status));
for(const papel of ['anon', 'authenticated'])
  verdade(`${papel} não executa preco_do_plano`,
    (await um(`select has_function_privilege($1, 'public.preco_do_plano(uuid, text)', 'execute') as p`,
      [papel])).p === false);

await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} verificações do preço especial${
  falhou ? `, ${falhou} falharam` : ''}.`);
process.exit(falhou ? 1 : 0);
