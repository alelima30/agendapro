/* ===========================================================================
   AgendaPro — quem tem dois salões não apaga um mexendo no outro

     bash tests/bancada/subir.sh
     PLAYWRIGHT=.../node_modules/playwright node tests/sincronia-saloes.test.mjs

   As tabelas sem `salao_id` (a jornada, o item da comanda, o pagamento, o
   serviço do agendamento…) desciam sem filtro: para a dona de dois salões,
   vinham as linhas dos DOIS. A tela reconstrói essas filhas a partir das
   mães — que são de um salão só — e o `subir()` lia as do outro salão como
   "sumiram" e mandava apagar. Medido: abriu o painel na Casa A, e as cinco
   faixas de jornada da profissional da Casa B foram apagadas, sem erro.

   Aqui: a dona abre e salva na Casa A, e a Casa B continua inteira — jornada,
   comanda com item e pagamento, agendamento com o serviço. E o que ela muda
   na Casa A continua indo para o banco.
   =========================================================================== */
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BANCADA = process.env.BANCADA || 'http://127.0.0.1:8123';
const RAIZ = path.dirname(new URL(import.meta.url).pathname);

let ok = 0, mau = 0;
const diz = (bom, msg, extra) => bom
  ? (ok++, console.log('  ✓ ' + msg))
  : (mau++, console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')));

const sql = q => execSync('psql -At -v ON_ERROR_STOP=1', { input: q, env: { ...process.env,
  PGHOST: process.env.PGHOST || '/tmp', PGPORT: process.env.PGPORT || '5444',
  PGUSER: process.env.PGUSER || 'postgres', PGDATABASE: process.env.PGBANCO || 'app' } }).toString().trim();

console.log('\nToda tabela sem salao_id desce pela mãe');
{
  const g = {};
  const j = { AGENDAPRO: { url: BANCADA, chave: 'k', ambiente: 'bancada' },
    localStorage: { getItem: k => (k in g ? g[k] : null), setItem: (k, v) => { g[k] = String(v); }, removeItem: k => { delete g[k]; } } };
  new Function('window', 'console', 'fetch', 'localStorage',
    fs.readFileSync(path.join(RAIZ, '..', 'dados.js'), 'utf8'))(j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  const D = j.Dados;
  const semSalao = D.TABELAS_SINCRONIZADAS.filter(t => t !== 'saloes' && !(D.COLUNAS[t] && D.COLUNAS[t].salaoId));
  const faltam = semSalao.filter(t => !D.FILHAS[t]);
  diz(faltam.length === 0, 'cada tabela sincronizada sem salao_id tem a mãe dela no FILHAS', faltam.join(', '));
  const maesRuins = Object.entries(D.FILHAS).filter(([, [, mae]]) => !(D.COLUNAS[mae] && D.COLUNAS[mae].salaoId));
  diz(maesRuins.length === 0, 'e toda mãe é filtrada por salão', maesRuins.map(x => x[0]).join(', '));
  const colunas = Object.entries(D.FILHAS).filter(([t, [col]]) => !(D.COLUNAS[t] && D.COLUNAS[t][col]));
  diz(colunas.length === 0, 'e a coluna que aponta para a mãe existe no mapa', colunas.map(x => x[0]).join(', '));
}

console.log('\nA dona de duas casas abre e salva na Casa A');
const email = 'duas-casas-' + Date.now() + '@teste.com';
const conta = await fetch(BANCADA + '/auth/v1/signup', { method: 'POST',
  headers: { apikey: 'k', 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password: 'senha-de-teste',
    data: { nome: 'Dona de Duas', telefone: '+5511' + Math.floor(1e8 + Math.random() * 8e8) } }) }).then(r => r.json());
const sessao = { token: conta.access_token, usuarioId: conta.user.id };
const rpc = (f, a) => fetch(BANCADA + '/rest/v1/rpc/' + f, { method: 'POST',
  headers: { apikey: 'k', Authorization: 'Bearer ' + sessao.token, 'Content-Type': 'application/json' },
  body: JSON.stringify(a) }).then(r => r.json());
const sufixo = Date.now().toString(36);
const hx = Date.now().toString(16).padStart(12, '0').slice(-12);   // pedaço de uuid
const criar = async nome => {
  const r = await rpc('criar_salao', { p_nome_salao: nome, p_tipo: 'salao', p_slug: nome.toLowerCase().replace(/\W+/g, '-') + '-' + sufixo,
    p_telefone: '11999990000', p_documento: null, p_origem: null });
  return (Array.isArray(r) ? r[0] : r).salao_id;
};
const casaA = await criar('Casa A');
const casaB = await criar('Casa B');

// A Casa B com um pouco de tudo que mora em tabela sem salao_id. O horário
// é a segunda-feira que vem, 10h em Brasília: dentro da jornada de 9h às 18h.
sql(`
  insert into jornadas (profissional_id, dia_semana, inicio, fim)
    select p.id, d, '09:00', '18:00' from profissionais p, generate_series(1,5) d where p.salao_id = '${casaB}';
  insert into servicos (id, salao_id, nome, duracao_min, preco) values ('5a000000-0000-0000-0000-${hx}', '${casaB}', 'Escova B', 40, 70);
  insert into clientes (id, salao_id, nome, telefone) values ('5b000000-0000-0000-0000-${hx}', '${casaB}', 'Cliente B', '11988887777');
  insert into agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim)
    select '5c000000-0000-0000-0000-${hx}', '${casaB}', '5b000000-0000-0000-0000-${hx}', p.id,
           date_trunc('week', now() + interval '7 days') + interval '13 hours',
           date_trunc('week', now() + interval '7 days') + interval '13 hours 40 minutes' from profissionais p where p.salao_id = '${casaB}' limit 1;
  insert into agendamento_servicos (agendamento_id, servico_id, duracao_min, preco)
    values ('5c000000-0000-0000-0000-${hx}', '5a000000-0000-0000-0000-${hx}', 40, 70);
  insert into comandas (id, salao_id, cliente_id, numero)
    values ('5d000000-0000-0000-0000-${hx}', '${casaB}', '5b000000-0000-0000-0000-${hx}', 1);
  insert into comanda_itens (comanda_id, tipo, descricao, qtd, preco_unit)
    values ('5d000000-0000-0000-0000-${hx}', 'servico', 'Escova B', 1, 70);
  insert into pagamentos (comanda_id, forma, valor) values ('5d000000-0000-0000-0000-${hx}', 'pix', 70);
`);
const daCasaB = () => Number(sql(`select
    (select count(*) from jornadas j join profissionais p on p.id = j.profissional_id where p.salao_id = '${casaB}')
  + (select count(*) from agendamento_servicos s join agendamentos a on a.id = s.agendamento_id where a.salao_id = '${casaB}')
  + (select count(*) from comanda_itens i join comandas c on c.id = i.comanda_id where c.salao_id = '${casaB}')
  + (select count(*) from pagamentos g join comandas c on c.id = g.comanda_id where c.salao_id = '${casaB}')`));
const antes = daCasaB();
diz(antes === 8, 'a Casa B tem 5 faixas de jornada, 1 serviço agendado, 1 item e 1 pagamento', 'tem ' + antes);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport: { width: 1280, height: 900 } });
await ctx.addInitScript(([base, s]) => {
  window.AGENDAPRO = { url: base, chave: 'k', ambiente: 'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BANCADA, sessao]);
const p = await ctx.newPage();
const erros = [], dialogos = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => { dialogos.push(d.message()); d.dismiss(); });
await p.goto(BANCADA + '/app.html');
await p.waitForFunction(() => typeof bd !== 'undefined' && bd && bd.saloes && salaoAtual, null, { timeout: 15000 });
await p.waitForTimeout(800);

// Qual das duas abre primeiro depende da ordem em que o banco devolve os
// salões — não é escolha da tela. O teste vai para a Casa B pelo seletor
// (como a dona faria), confere que ela chega COM os dados dela, e volta à A.
const onde = await p.evaluate(() => ({ nome: (acharSalao(salaoAtual) || {}).nome, saloes: bd.saloes.length }));
diz(onde.saloes === 2, 'o painel abriu com as duas casas no seletor', JSON.stringify(onde));
diz(daCasaB() === antes, 'só abrir o painel não tirou nada da Casa B', 'ficou ' + daCasaB());

const naCasa = async id => {
  await p.selectOption('#selSalao', id);
  await p.waitForFunction(id => salaoAtual === id
    && bd.profissionais.length && bd.profissionais.every(x => x.salaoId === id), id, { timeout: 10000 }).catch(() => {});
  await p.waitForTimeout(400);
  return p.evaluate(() => ({ nome: (acharSalao(salaoAtual) || {}).nome,
    profs: bd.profissionais.filter(x => x.salaoId === salaoAtual).length,
    jornadaDaPrimeira: Object.keys((bd.profissionais[0] || {}).jornada || {}).length,
    comandas: (bd.comandas || []).length }));
};
const emB = await naCasa(casaB);
diz(emB.nome === 'Casa B' && emB.profs === 1 && emB.jornadaDaPrimeira === 5 && emB.comandas === 1,
    'trocar para a Casa B no seletor traz a equipe, a jornada e a comanda DELA (antes: vazia)', JSON.stringify(emB));
const emA = await naCasa(casaA);
diz(emA.nome === 'Casa A' && emA.profs === 1 && emA.comandas === 0,
    'e voltar para a Casa A traz a dela, sem a comanda da B', JSON.stringify(emA));
diz(daCasaB() === antes, 'ir e voltar não tirou nada da Casa B', 'ficou ' + daCasaB());

const doRetrato = await p.evaluate(() => {
  const casa = salaoAtual;
  const profs = new Set(bd.profissionais.map(x => x.id));
  return { jornadasDeFora: (_baixado.jornadas || []).filter(j => !profs.has(j.profissionalId)).length,
           itensDeFora: (_baixado.comanda_itens || []).length, casa };
});
diz(doRetrato.jornadasDeFora === 0 && doRetrato.itensDeFora === 0,
    'o retrato da Casa A não carrega jornada nem item de comanda da Casa B', JSON.stringify(doRetrato));

/* A rede cai bem na hora de trocar de casa. Antes o painel seguia para a Casa
   B com os dados de nenhuma — a B aparecia vazia, como se não tivesse nada. */
await p.route('**/rest/v1/**', r => r.abort());
await p.selectOption('#selSalao', casaB);
await p.waitForTimeout(1500);
const caiu = await p.evaluate(() => ({ casa: (acharSalao(salaoAtual) || {}).nome,
  seletor: (acharSalao(document.getElementById('selSalao').value) || {}).nome,
  topo: document.getElementById('tbSalao').textContent,
  profs: bd.profissionais.filter(x => x.salaoId === salaoAtual).length }));
await p.unroute('**/rest/v1/**');
diz(caiu.casa === 'Casa A' && caiu.seletor === 'Casa A' && caiu.topo === 'Casa A' && caiu.profs === 1,
    'sem rede na troca, o painel fica na Casa A com os dados dela (antes: Casa B vazia)', JSON.stringify(caiu));
const avisos = dialogos.splice(0);
diz(avisos.some(m => /conex/i.test(m)) && !avisos.some(m => /config\.js/.test(m)),
    'e avisa que é falta de conexão, não "confira o config.js"', avisos.join(' | '));

// Ela marca o horário da profissional da Casa A e salva.
await p.evaluate(async () => {
  const prof = bd.profissionais[0];
  prof.jornada = { 2: [[600, 1080]] };
  await salvar();
});
await p.waitForTimeout(800);
diz(daCasaB() === antes, 'salvar na Casa A não apaga nada da Casa B — jornada, serviço agendado, item e pagamento', 'ficou ' + daCasaB());
const daCasaA = Number(sql(`select count(*) from jornadas j join profissionais p on p.id = j.profissional_id
  where p.salao_id = '${casaA}' and j.dia_semana = 2 and j.inicio = '10:00' and j.fim = '18:00'`));
diz(daCasaA === 1, 'e o horário que ela marcou na Casa A foi para o banco', 'achei ' + daCasaA);
diz(!dialogos.length, 'sem aviso de gravação recusada', dialogos.join(' | '));
diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));

/* Abrir o painel sem internet. Antes: "Nenhum salão nesta conta — crie o seu
   em dois minutos", para a dona de duas casas. */
{
  const c2 = await nav.newContext({ viewport: { width: 390, height: 844 } });
  await c2.addInitScript(([base, s]) => {
    window.AGENDAPRO = { url: base, chave: 'k', ambiente: 'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BANCADA, sessao]);
  const q = await c2.newPage();
  const errosQ = [];
  q.on('pageerror', e => errosQ.push(e.message));
  q.on('dialog', d => d.dismiss());
  await q.route('**/rest/v1/**', r => r.abort());
  await q.goto(BANCADA + '/app.html');
  await q.waitForTimeout(2500);
  const txt = (await q.textContent('.corpo').catch(() => '')) || '';
  diz(/falar com o servidor/i.test(txt) && !/Nenhum salão/i.test(txt),
      'abrir sem internet diz que não falou com o servidor — não "Nenhum salão nesta conta"',
      txt.replace(/\s+/g, ' ').slice(0, 140));
  diz(await q.isVisible('button:has-text("Tentar de novo")'), 'com o botão "Tentar de novo"');
  const guardada = await q.evaluate(() => { try{ return !!JSON.parse(localStorage.getItem('agendapro.sessao')).token; }catch(e){ return false; } });
  diz(guardada, 'e o login continua guardado no aparelho');
  diz(errosQ.length === 0, 'sem erro de JavaScript', errosQ.join(' | '));
  await c2.close();
}

await nav.close();
console.log(`\n${ok} ok, ${mau} falha(s)`);
process.exit(mau ? 1 : 0);
