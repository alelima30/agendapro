/* ═══════════════════════════════════════════════════════════════════════════
   O FUSO DO SALÃO, NA TELA (58_fuso.sql)

   "Não posso perder nada sobre horários marcados."

   O tests/fuso.test.sql prova a conta no banco. Este prova o caminho de quem
   usa, num navegador de verdade com o relógio de Manaus:

     1. Meu negócio mostra o campo, e avisa que o relógio do aparelho discorda;
     2. cancelar a janela não troca nada;
     3. confirmar troca, e a agenda continua com as MESMAS horas na tela;
     4. o OUTRO aparelho, com a tela aberta desde antes, percebe e se recarrega;
     5. por 90 segundos o banco recusa gravar horário;
     6. "Salvar dados" nunca escreve o fuso;
     7. o link da cliente percebe a troca antes de marcar;
     8. o cadastro grava o fuso do aparelho, só quando é do Brasil.
   ═══════════════════════════════════════════════════════════════════════════ */
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);
const secao = t => console.log('\n' + t);

function aba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(RAIZ + '/dados.js','utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const um = async (sql, args = []) => (await banco.query(sql, args)).rows[0];

const m = Date.now().toString(36);
const dona = aba();
await dona.criarConta({ email:`fuso-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Dona do Fuso', telefone:'+5592' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão de Manaus ' + m,
  p_tipo:'salao', p_telefone:'(92) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'00:00', fim:'23:59' });
const corte = await dona.inserir('servicos', { salaoId:SALAO, nome:'Corte',
  preco:50, duracaoMin:60, intervaloMin:0, ativo:true, aceitaOnline:true });
await dona.inserir('servicos_profissionais', { servicoId: corte.id, profissionalId: prof.id }).catch(() => {});
const cli = await dona.inserir('clientes', { salaoId:SALAO, nome:'Joana',
  telefone: String(92900000000 + (Date.now() % 89000000)) });

// O salão já existe "há um mês": a trava de 90 s só vale para salão antigo.
await banco.query(`update public.saloes set criado_em = now() - interval '30 days' where id = $1`, [SALAO]);
await banco.query(`update public.assinaturas set plano = 'salao', status = 'ativa', trial_ate = null where salao_id = $1`, [SALAO]);

// Dois horários colados, daqui a três dias, às 09:00 e às 10:00 de Brasília.
const DIA = (await um(`select to_char((now() at time zone 'America/Sao_Paulo')::date + 3, 'YYYY-MM-DD') as d`)).d;
for(const [i, f] of [['09:00', '10:00'], ['10:00', '11:00']])
  await banco.query(`insert into public.agendamentos
    (salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
    values ($1, $2, $3, ($4 || ' ' || $5 || ':00 America/Sao_Paulo')::timestamptz,
            ($4 || ' ' || $6 || ':00 America/Sao_Paulo')::timestamptz, 'confirmado', 'recepcao', 50)`,
    [SALAO, cli.id, prof.id, DIA, i, f]);
const instantes = async () => (await banco.query(
  `select inicio from public.agendamentos where salao_id = $1 order by inicio`, [SALAO]))
  .rows.map(r => r.inicio.toISOString());
const antes = await instantes();

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrir(caminho, sessao){
  // O aparelho está em Manaus: uma hora atrás do salão, que nasceu em Brasília.
  const ctx = await nav.newContext({ viewport:{ width:1360, height:900 }, timezoneId:'America/Manaus' });
  const p = await ctx.newPage();
  p.on('pageerror', x => erros.push('pageerror: ' + x.message));
  p._alertas = [];
  p.on('dialog', async d => { p._alertas.push(d.message()); await d.accept(); });
  await p.addInitScript(([base, ses]) => {
    window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
    if(ses) localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
  }, [BASE, sessao || null]);
  await p.goto(BASE + caminho);
  await p.waitForTimeout(3500);
  return p;
}
const horasNaTela = p => p.evaluate(dia => (bd.agendamentos || [])
  .filter(a => a.data === dia).map(a => a.inicio).sort((x, y) => x - y), DIA);

const p = await abrir('/app.html', dona.sessao());
const outro = await abrir('/app.html', dona.sessao());      // o aparelho da recepção
const link = await abrir('/agendar.html?salao=' + SLUG);    // a cliente, com a página aberta

secao('1. Meu negócio mostra o horário da cidade');
e('a agenda abre com os dois horários às 09:00 e 10:00',
  JSON.stringify(await horasNaTela(p)) === '[540,600]', JSON.stringify(await horasNaTela(p)));
await p.click('button:has-text("Meu negócio"), a:has-text("Meu negócio")');
await p.waitForTimeout(1200);
e('o campo existe', await p.isVisible('#cFuso'));
e('e nasce no horário de Brasília', await p.inputValue('#cFuso') === 'America/Sao_Paulo');
const opcoes = await p.evaluate(() => [...document.querySelectorAll('#cFuso option')].map(o => o.textContent.trim()));
e('cada linha diz a hora de lá — ' + JSON.stringify(opcoes[1]),
  opcoes.length >= 9 && opcoes.every(o => /agora \d\d:\d\d$/.test(o)), JSON.stringify(opcoes));
const dica = await p.evaluate(() => (document.getElementById('fusoDica') || {}).innerText || '');
e('e avisa que o relógio do aparelho discorda do do salão — ' + JSON.stringify(dica.slice(0, 60)),
  /relógio deste aparelho marca \d\d:\d\d/.test(dica), dica);

secao('2. Cancelar não troca nada');
await p.selectOption('#cFuso', 'America/Manaus');
await p.waitForTimeout(400);
const janela = await p.evaluate(() => document.getElementById('modalCorpo').innerText);
e('a janela promete que os horários não mudam', /Os horários marcados não mudam/.test(janela), janela);
e('a lista volta para Brasília enquanto ninguém confirmou', await p.inputValue('#cFuso') === 'America/Sao_Paulo');
await p.click('#modalPe button:has-text("Cancelar")');
await p.waitForTimeout(300);
e('cancelando, o banco continua em Brasília',
  (await um(`select fuso from public.saloes where id = $1`, [SALAO])).fuso === 'America/Sao_Paulo');

secao('3. Confirmar troca, e a agenda continua com as mesmas horas');
await p.selectOption('#cFuso', 'America/Manaus');
await p.waitForTimeout(400);
await p.click('#modalPe button:has-text("Trocar o horário")');
await p.waitForTimeout(3500);
const feito = await p.evaluate(() => document.getElementById('modalTitulo').textContent + ' · '
  + document.getElementById('modalCorpo').innerText);
e('a tela diz que trocou e quantos horários ficaram — ' + JSON.stringify(feito.slice(0, 80)),
  /Horário do salão trocado/.test(feito) && /2 horários marcados/.test(feito) && /mesma hora/.test(feito), feito);
e('o banco está em Manaus',
  (await um(`select fuso from public.saloes where id = $1`, [SALAO])).fuso === 'America/Manaus');
const depois = await instantes();
e('os instantes andaram uma hora (a diferença entre as cidades)',
  depois.every((d, i) => Date.parse(d) - Date.parse(antes[i]) === 3600000), JSON.stringify([antes, depois]));
e('e na tela os horários continuam às 09:00 e 10:00',
  JSON.stringify(await horasNaTela(p)) === '[540,600]', JSON.stringify(await horasNaTela(p)));
await p.click('#modalPe button:has-text("Entendi")');
await p.waitForTimeout(4000);
e('depois de recarregar, a mesma coisa',
  JSON.stringify(await horasNaTela(p)) === '[540,600]', JSON.stringify(await horasNaTela(p)));
e('e a tela pensa em Manaus', await p.evaluate(() => fusoDoSalaoAtual()) === 'America/Manaus');
e('nenhum erro apareceu para a dona', p._alertas.length === 0, p._alertas.join(' | '));

secao('4. O outro aparelho, aberto desde antes');
e('ele ainda pensa em Brasília', await outro.evaluate(() => fusoDoSalaoAtual()) === 'America/Sao_Paulo');
await outro.evaluate(() => sincronizarAgenda());
await outro.waitForTimeout(800);
const avisoOutro = await outro.evaluate(() => document.getElementById('modalTitulo').textContent + ' · '
  + document.getElementById('modalCorpo').innerText);
e('ao sincronizar, é avisado — ' + JSON.stringify(avisoOutro.slice(0, 60)),
  /O horário do salão foi ajustado/.test(avisoOutro) && /continuam os\s+mesmos/.test(avisoOutro), avisoOutro);
e('e NÃO pintou a agenda com as horas erradas no meio do caminho',
  JSON.stringify(await horasNaTela(outro)) === '[540,600]', JSON.stringify(await horasNaTela(outro)));
await outro.waitForTimeout(6500);
e('recarrega sozinho e passa a pensar em Manaus',
  await outro.evaluate(() => typeof fusoDoSalaoAtual === 'function' && fusoDoSalaoAtual()) === 'America/Manaus');
e('com os horários às 09:00 e 10:00',
  JSON.stringify(await horasNaTela(outro)) === '[540,600]', JSON.stringify(await horasNaTela(outro)));

secao('5. Noventa segundos sem gravar horário');
let recusa = null;
try{
  await dona.inserir('agendamentos', { salaoId:SALAO, clienteId:cli.id, profissionalId:prof.id,
    inicio: DIA + ' 14:00:00 America/Sao_Paulo', fim: DIA + ' 15:00:00 America/Sao_Paulo',
    status:'confirmado', origem:'recepcao', valorPrevisto:50 });
}catch(x){ recusa = x.message || String(x); }
e('quem tentar gravar com o relógio antigo é recusado — ' + JSON.stringify(recusa),
  /relógio do salão acabou de ser ajustado/.test(recusa || ''), recusa);
await banco.query(`update public.saloes set fuso_mudou_em = now() - interval '2 minutes' where id = $1`, [SALAO]);
let gravou = null;
try{
  gravou = await dona.inserir('agendamentos', { salaoId:SALAO, clienteId:cli.id, profissionalId:prof.id,
    inicio: DIA + ' 14:00:00 America/Manaus', fim: DIA + ' 15:00:00 America/Manaus',
    status:'confirmado', origem:'recepcao', valorPrevisto:50 });
}catch(x){ gravou = 'ERRO ' + x.message; }
e('passado o prazo, grava normalmente', gravou && gravou.id, String(gravou));

secao('6. "Salvar dados" nunca escreve o fuso');
const trocasAntes = Number((await um(`select count(*) n from public.fuso_mudancas where salao_id = $1`, [SALAO])).n);
await p.click('button:has-text("Meu negócio"), a:has-text("Meu negócio")');
await p.waitForTimeout(1200);
e('o campo agora mostra Manaus', await p.inputValue('#cFuso') === 'America/Manaus');
e('e a dica some: o aparelho e o salão marcam a mesma hora',
  !(await p.evaluate(() => !!document.getElementById('fusoDica'))));
await p.fill('#cNome', 'Salão de Manaus Renomeado');
await p.click('#tela-salao button:has-text("Salvar dados")');
await p.waitForTimeout(2500);
const sl = await um(`select nome, fuso from public.saloes where id = $1`, [SALAO]);
e('o nome foi salvo', sl.nome === 'Salão de Manaus Renomeado', sl.nome);
e('e o fuso ficou onde estava, sem troca nova no histórico',
  sl.fuso === 'America/Manaus'
  && Number((await um(`select count(*) n from public.fuso_mudancas where salao_id = $1`, [SALAO])).n) === trocasAntes);

secao('7. O link da cliente, aberto desde antes da troca');
e('a página dela ainda pensa em Brasília', await link.evaluate(() => fusoDoSalao()) === 'America/Sao_Paulo');
e('e percebe que o relógio do salão mudou, antes de marcar',
  await link.evaluate(() => relogioDoSalaoMudou()) === true);
await link.reload();
await link.waitForTimeout(3000);
e('recarregada, pensa em Manaus e não vê mais diferença',
  await link.evaluate(() => fusoDoSalao()) === 'America/Manaus'
  && await link.evaluate(() => relogioDoSalaoMudou()) === false);

secao('8. O cadastro: o fuso do aparelho, só quando é do Brasil');
const fonte = fs.readFileSync(RAIZ + '/criar.html', 'utf8');
e('o cadastro lê o fuso do aparelho e grava no salão novo',
  /resolvedOptions\(\)\.timeZone/.test(fonte) && /Dados\.atualizar\('saloes', criado\.salao_id, \{ fuso: doAparelho \}\)/.test(fonte));
e('a lista do cadastro não tem o horário de Brasília (já é o padrão) nem fuso de fora',
  !/OUTROS = \[[^\]]*Sao_Paulo/.test(fonte) && !/OUTROS = \[[^\]]*(Europe|Etc|UTC)/.test(fonte));
const nova = aba();
await nova.criarConta({ email:`fuso-n-${m}@t.com`, senha:'minhasenhaboa',
  nome:'Dona Nova', telefone:'+5568' + (900000000 + (Date.now() % 89999999)) });
const cn = await nova.chamar('criar_salao', { p_nome_salao:'Salão do Acre ' + m,
  p_tipo:'salao', p_telefone:'(68) 99887-6655', p_documento:null, p_origem:null });
await nova.atualizar('saloes', cn[0].salao_id, { fuso: 'America/Rio_Branco' });
const acre = await um(`select fuso, fuso_mudou_em from public.saloes where id = $1`, [cn[0].salao_id]);
e('o salão recém-criado aceita o fuso do aparelho', acre.fuso === 'America/Rio_Branco', acre.fuso);
e('sem travar o primeiro horário (salão novo não é carimbado)', acre.fuso_mudou_em === null);
let lixo = null;
try{ await nova.atualizar('saloes', cn[0].salao_id, { fuso: 'Qualquer/Coisa' }); }catch(x){ lixo = x.message; }
e('e recusa nome que não é fuso — ' + JSON.stringify(lixo), /Não conheço o fuso horário/.test(lixo || ''), lixo);

e('nenhum erro de JavaScript em nenhuma das telas', erros.length === 0, erros.slice(0, 3).join(' | '));

await banco.query(`delete from public.saloes where id = any($1)`, [[SALAO, cn[0].salao_id]]);
await banco.end();
await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
