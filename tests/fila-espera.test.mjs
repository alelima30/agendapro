/* ===========================================================================
   AgendaPro — a fila de espera aparece para quem trabalha no salão

     bash tests/bancada/subir.sh
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/fila-espera.test.mjs

   ── A PROMESSA QUE O PRODUTO FAZIA E NÃO CUMPRIA ───────────────────────────
   A cliente que não acha horário entra na fila pelo link e lê, com estas
   palavras:

       "Pronto! Você está na lista. Assim que alguém cancelar nesse período,
        o salão te chama no WhatsApp."

   E o painel não tinha essa tela. A palavra `lista_espera` aparecia ZERO
   vezes no app.html: a fila era baixada do banco a cada carregamento, entrava
   no `bd`, era sincronizada de volta pelo `Dados.subir()` — e não era
   desenhada em lugar nenhum.

   Não era um defeito que atrapalhava o trabalho. Era uma promessa quebrada
   para uma cliente que já tinha decidido comprar, que é pior — e do tipo que
   nunca vira reclamação, porque quem esperou o telefonema não escreve para
   dizer que ele não veio.

   ── O QUE ESTE ARQUIVO EXIGE ───────────────────────────────────────────────
   O caminho inteiro, das duas pontas: a cliente entra pelo link público, sem
   login, e a recepção ABRE A AGENDA e vê a pessoa lá — com nome, serviço,
   faixa de dias e um botão que abre a conversa.

   E as três coisas que separam uma lista útil de uma lista que atrapalha:
   quem já foi chamada aparece marcada, quem saiu some da lista sem sumir do
   banco, e faixa de dias que já passou não fica ocupando a tela da recepção.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pg from './pg.mjs';
import { maisDias } from './dia.mjs';

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

const dona = novaAba();
await dona.criarConta({ email:`fila-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju da Fila',
  telefone:'+5511' + (100000000 + Math.floor(Math.random()*89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Fila ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
await banco.query(
  `update public.assinaturas set plano='time', status='ativa' where salao_id=$1`,
  [SALAO]);

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
await dona.atualizar('profissionais', prof.id, { ativo:true, aceitaOnline:true });
const corte = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:60, ativo:true, aceitaOnline:true });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova',
  duracaoMin:60, intervaloMin:0, preco:90, ativo:true, aceitaOnline:true });

/* ══════════════════════════════════════════════════════════════════════════
   1. A CLIENTE ENTRA NA FILA PELO LINK, SEM LOGIN
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) A cliente entra na fila');

const DE  = maisDias(2);
const ATE = maisDias(9);

async function entrar(nome, telefone, servicos, de, ate, turno, prof_ = null){
  const r = await fetch(BASE + '/rest/v1/rpc/entrar_na_fila', {
    method:'POST', headers:{ apikey:'k', 'Content-Type':'application/json' },
    body: JSON.stringify({ p_salao: SALAO, p_servicos: servicos, p_nome: nome,
      p_telefone: telefone, p_de: de, p_ate: ate, p_profissional: prof_,
      p_turno: turno, p_obs: null }) });
  const t = await r.text();
  if(!r.ok){ let m = t; try{ m = JSON.parse(t).message || t; }catch(e){} throw new Error(m); }
  return JSON.parse(t);
}

await entrar('Marta Ribeiro', '11988776655', [corte.id, escova.id],
             DE, ATE, 'tarde');
await entrar('Cleide Souza', '11977665544', [corte.id], DE, ATE, 'manha');

/* Uma que pediu vaga para uma faixa que JÁ PASSOU. Não dá para criá-la pelo
   link — o `entrar_na_fila()` recusa data velha, e faz bem. Ela nasce do
   tempo: a pessoa entrou na fila em julho pedindo vaga para julho, e hoje é
   agosto. Por isso vai direto no banco, que é o estado em que ela de fato
   aparece num salão de verdade. */
const cliVelha = await dona.inserir('clientes', { salaoId: SALAO,
  nome:'Fantasma Antiga', telefone:'11966554433' });
await banco.query(
  `insert into public.lista_espera
     (salao_id, cliente_id, servicos, duracao_min, de, ate, turno, status)
   values ($1, $2, to_jsonb($3::uuid[]), 30, $4::date, $5::date,
           'qualquer', 'aguardando')`,
  [SALAO, cliVelha.id, [corte.id], maisDias(-20), maisDias(-10)]);

const noBanco = (await banco.query(
  `select count(*)::int as n from public.lista_espera where salao_id=$1`,
  [SALAO])).rows[0].n;
igual('as três entradas estão no banco', noBanco, 3);

const comToken = (await banco.query(
  `select count(*)::int as n from public.lista_espera
    where salao_id=$1 and gerenciar_token is not null`, [SALAO])).rows[0].n;
igual('e cada uma tem o segredo de acompanhar', comToken, 3);

/* ══════════════════════════════════════════════════════════════════════════
   2. E O SALÃO VÊ — QUE É O PONTO DESTE ARQUIVO
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) A recepção abre a Agenda e a fila está lá');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const p = await (await nav.newContext({ viewport:{ width:1360, height:900 } })).newPage();
p.on('pageerror', e => erros.push(e.message));
const avisos = [];
p.on('dialog', async d => { avisos.push(d.message()); await d.accept(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);

/* Pelo `evaluate`, e não pelo `p.textContent()`: sem o elemento, o
   `textContent` fica trinta segundos esperando e a suíte morre com
   "Timeout exceeded", que é a pior forma de contar que a tela não existe —
   parece lentidão. Assim a reprova diz a verdade na primeira linha. */
const fila = () => p.evaluate(() => {
  const el = document.getElementById('filaEspera');
  return el === null ? null : el.textContent;
});

verdade('a Agenda TEM onde desenhar a fila',
  (await fila()) !== null,
  'não existe #filaEspera na Agenda — a fila continua invisível para o salão');
verdade('a Agenda mostra o cartão da fila',
  /esperando vaga/.test(await fila() || ''), (await fila() || '').slice(0, 160));
verdade('com as duas que ainda esperam, e não a terceira',
  /2 pessoas esperando/.test(await fila() || ''), (await fila() || '').slice(0, 120));
/* ⚠ Amarrada ao cartão EXISTIR. Escrita como `!/Fantasma/.test(texto)` ela
   passava com a tela inteira ausente — texto vazio não contém Fantasma — e
   ficava verde justamente no estado que esta suíte existe para reprovar. */
verdade('a faixa que já passou não ocupa a tela da recepção',
  /esperando vaga/.test(await fila() || '') && !/Fantasma/.test(await fila() || ''),
  (await fila() || '').replace(/\s+/g, ' ').slice(0, 200));

verdade('o nome de quem espera aparece',
  /Marta Ribeiro/.test(await fila() || '') && /Cleide Souza/.test(await fila() || ''),
  (await fila() || '').replace(/\s+/g, ' ').slice(0, 260));
verdade('e o que ela queria fazer',
  /Corte \+ Escova/.test(await fila() || ''),
  (await fila() || '').replace(/\s+/g, ' ').slice(0, 260));
verdade('e a faixa de dias em que ela pode',
  new RegExp(String(DE).slice(8, 10)).test(await fila() || ''),
  (await fila() || '').replace(/\s+/g, ' ').slice(0, 260));
verdade('e o turno que ela pediu',
  /à tarde/.test(await fila() || '') && /de manhã/.test(await fila() || ''),
  (await fila() || '').replace(/\s+/g, ' ').slice(0, 260));

/* ══════════════════════════════════════════════════════════════════════════
   3. CHAMAR NO WHATSAPP MARCA QUE JÁ FOI CHAMADA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3) Chamar, e não chamar duas vezes');

/* Sem esta marca a recepção liga para a mesma pessoa três vezes numa manhã
   cheia — e é assim que uma fila que era venda vira incômodo. */
await p.evaluate(() => window.open = () => null);   // não abre aba de verdade
await p.click('#filaEspera button:has-text("Chamar")');
await p.waitForTimeout(2500);

verdade('quem foi chamada fica marcada na tela',
  /já avisada/.test(await fila() || ''), (await fila() || '').replace(/\s+/g, ' ').slice(0, 260));

const avisada = (await banco.query(
  `select status, avisado_em from public.lista_espera
    where salao_id=$1 and status='avisado'`, [SALAO])).rows;
igual('e o banco guardou que ela foi avisada', avisada.length, 1);
verdade('com a hora do aviso', !!(avisada[0] && avisada[0].avisado_em),
  JSON.stringify(avisada[0]));

verdade('e ela continua na fila até alguém dizer o que houve',
  /2 pessoas esperando/.test(await fila() || ''), (await fila() || '').slice(0, 120));

/* ══════════════════════════════════════════════════════════════════════════
   4. SAIR DA FILA NÃO É APAGAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('4) Marcou, ou desistiu');

await p.click('#filaEspera button:has-text("Marcou")');
await p.waitForTimeout(2500);

verdade('quem marcou sai da lista da recepção',
  /1 pessoa esperando/.test(await fila() || ''), (await fila() || '').slice(0, 120));

/* A linha fica: é dela que sai, no fim do mês, quanta gente pediu vaga e
   quanta foi atendida — o número que diz se vale abrir mais um horário. */
igual('mas a linha continua no banco, com o desfecho',
  (await banco.query(
    `select count(*)::int as n from public.lista_espera
      where salao_id=$1 and status='atendido'`, [SALAO])).rows[0].n, 1);
igual('e nenhuma linha foi apagada',
  (await banco.query(
    `select count(*)::int as n from public.lista_espera where salao_id=$1`,
    [SALAO])).rows[0].n, 3);

/* ══════════════════════════════════════════════════════════════════════════
   5. FILA VAZIA NÃO OCUPA ESPAÇO
   ══════════════════════════════════════════════════════════════════════════ */
secao('5) Sem ninguém esperando, o cartão não existe');

/* Cartão que fica na tela dizendo "nenhuma pessoa esperando" é ruído na tela
   mais usada do sistema, todo dia, para dizer que não há nada a fazer. */
await p.click('#filaEspera button:has-text("Saiu")');
await p.waitForTimeout(2500);
igual('o cartão some quando a fila esvazia',
  ((await fila()) || '').trim(), '');

secao('6) O console');
igual('nenhum erro de JavaScript', erros.length, 0, erros.join(' | '));

await nav.close();
await banco.query(`delete from public.saloes where id=$1`, [SALAO]);
await banco.end();

console.log('');
if(falhou){
  console.log(`✗ ${falhou} de ${passou + falhou} verificações falharam.`);
  process.exit(1);
}
console.log(`✓ ${passou} verificações da fila de espera.`);
