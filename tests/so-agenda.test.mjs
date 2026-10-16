/* ===========================================================================
   AgendaPro — "só com agenda" e os acertos pedidos depois do teste de ponta a
   ponta

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/so-agenda.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Não vou trabalhar com comanda no momento — esconder por enquanto, só com
   agenda." E, do mesmo teste: "quem mais atende" sai do passo a passo, com o
   aviso de em que plano cabe mais gente; "cheio" vira "encerrado" no dia que
   já acabou; o cadastro da cliente mostra o que é obrigatório; o relatório
   não mostra comissão a pagar para a própria dona; e o horário remarcado
   aparece como remarcado.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. Sem aba Caixa, sem "Abrir comanda", sem a escolha no passo a passo e
        no Meu negócio — e o salão gravado como "Só a agenda" no BANCO, que é o
        que faz o atendimento concluído virar faturamento.
     2. O teste grátis (1 profissional): o passo a passo não oferece "quem
        mais atende", e o "+ Profissional" avisa antes, dizendo os planos.
     3. O relatório: a dona fora da comissão a pagar.
     4. No link: os obrigatórios marcados, "encerrado", e "Remarcado".
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
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
const dona = novaAba();
await dona.criarConta({ email:`sa-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona Rita', telefone:'+5511' + (100000000 + Math.floor(Math.random()*89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Só Agenda ' + marca, p_tipo:'salao',
  p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const SLUG = (await um(`select slug from public.saloes where id=$1`, [SALAO])).slug;

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function painel(sufixo = ''){
  const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => d.accept());
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html' + sufixo); await p.waitForTimeout(3800);
  return { p, fechar: () => ctx.close() };
}
const textoDaJanela = p => p.evaluate(() => {
  const m = [...document.querySelectorAll('.modal, #modal, .pd, [id^="pd"]')].find(e => e.offsetParent !== null);
  return m ? m.innerText : '';
});

/* ══════════════════════════════════════════════════════════════════════════
   1 — O PASSO A PASSO DE UMA DONA NOVA, NO TESTE GRÁTIS
   ══════════════════════════════════════════════════════════════════════════ */
secao('1) O passo a passo: sem "quem mais atende", e sem a escolha da comanda');
{
  const { p, fechar } = await painel();
  const passoDe = () => p.evaluate(() => (document.body.innerText.match(/Passo (\d+) de 10/) || [])[1]);
  verdade('o passo a passo abre sozinho para o salão novo', (await passoDe()) === '1');
  for(let i = 0; i < 4; i++){
    await p.getByRole('button', { name: 'Próximo →' }).filter({ visible: true }).first().click();
    await p.waitForTimeout(900);
  }
  igual('chega no passo 5, "Sua equipe"', await passoDe(), '5');
  const t5 = await p.evaluate(() => document.body.innerText);
  verdade('não oferece "Quem mais atende?" — o teste grátis tem 1 profissional', !/Quem mais atende/.test(t5));
  const aviso = await p.evaluate(() => (document.getElementById('pdEquipeLimite') || {}).innerText || '');
  verdade('e diz em que plano cabe mais gente', /Dupla/.test(aviso) && /Salão/.test(aviso) && /plano maior/.test(aviso), aviso);
  for(let i = 0; i < 2; i++){
    await p.getByRole('button', { name: 'Próximo →' }).filter({ visible: true }).first().click();
    await p.waitForTimeout(900);
  }
  igual('chega no passo 7, "Como você trabalha"', await passoDe(), '7');
  const t7 = await p.evaluate(() => document.body.innerText);
  verdade('sem "O dinheiro do dia" (comanda e caixa escondidos)', !/O dinheiro do dia/.test(t7) && !/Com comanda e caixa/.test(t7));
  verdade('e a pergunta da confirmação continua', /Quem confirma o que vem pelo link/i.test(t7));
  await p.getByRole('button', { name: 'Próximo →' }).filter({ visible: true }).first().click();
  await p.waitForTimeout(1500);
  igual('passar pelo passo 7 grava "Só a agenda"',
    (await um(`select cfg->>'usaComanda' as v from public.saloes where id=$1`, [SALAO])).v, 'false');
  await p.evaluate(() => pdFechar(true)); await p.waitForTimeout(800);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — O PAINEL SÓ COM AGENDA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2) Só com agenda: sem Caixa, sem comanda — e o banco sabe');
// Um salão gravado "com comanda" (como os de antes): o painel passa a "Só a agenda".
await banco.query(`update public.saloes set cfg = coalesce(cfg,'{}') || '{"usaComanda":true}' where id=$1`, [SALAO]);
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
// O dia inteiro, todos os dias: o atendimento de teste cabe a qualquer hora.
await banco.query(`delete from public.jornadas where profissional_id=$1`, [prof.id]);
for(let d = 0; d <= 6; d++)
  await banco.query(`insert into public.jornadas (profissional_id, dia_semana, inicio, fim) values ($1, $2, '00:00', '23:59')`, [prof.id, d]);
const corte = await dona.inserir('servicos', { salaoId:SALAO, nome:'Corte', preco:80, duracaoMin:60,
  intervaloMin:0, ativo:true, aceitaOnline:true });
const cliente = await dona.inserir('clientes', { salaoId:SALAO, nome:'Joana',
  telefone: String(11900000000 + (Date.now() % 89000000)) });
const FUSO = 'America/Sao_Paulo';
const hojeLa = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO, year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date());
const ini = hojeLa + 'T16:00:00Z';   // 13:00 em São Paulo
const ag = await dona.inserir('agendamentos', { salaoId: SALAO, clienteId: cliente.id, profissionalId: prof.id,
  inicio: ini, fim: new Date(new Date(ini).getTime() + 60 * 60000).toISOString(),
  status:'confirmado', origem:'recepcao', valorPrevisto: 80 });
await dona.inserir('agendamento_servicos', { agendamentoId: ag.id, servicoId: corte.id, ordem:1,
  duracaoMin:60, preco:80, comissaoPct:0 });
{
  const { p, fechar } = await painel();
  const abas = await p.evaluate(() => [...document.querySelectorAll('#abas .aba')].map(b => b.dataset.chave));
  verdade('a aba Caixa não aparece', !abas.includes('caixa'), JSON.stringify(abas));
  const faixa = await p.evaluate(() => { const f = document.getElementById('faixaTeste');
    return f && f.offsetParent !== null ? f.innerText : ''; });
  verdade('no alto do painel, a faixa do teste grátis diz quantos dias faltam e até quando',
    /Teste grátis/.test(faixa) && /faltam? \d+ dias?|termina hoje/.test(faixa) && /até/.test(faixa), faixa);
  await p.waitForTimeout(1500);
  const g = await um(`select cfg->>'usaComanda' as v, public.usa_comanda($1) as u from public.saloes where id=$1`, [SALAO]);
  igual('o salão que estava "com comanda" é gravado "Só a agenda" ao abrir o painel', g.v, 'false');
  igual('e o banco trabalha sem comanda (usa_comanda)', g.u, false);
  await p.evaluate(([dia, id]) => { diaAtual = dia; irPara('agenda'); abrirDetalhe(id); }, [hojeLa, ag.id]);
  await p.waitForTimeout(900);
  const jan = await textoDaJanela(p);
  verdade('a janela do atendimento não oferece "Abrir comanda"', !/Abrir comanda/i.test(jan), jan.slice(0, 300));
  verdade('e continua deixando mudar o status', /Concluído/.test(jan), jan.slice(0, 300));
  await p.evaluate(() => fecharModal());
  // Meu negócio: a escolha some, e salvar não religa a comanda por baixo.
  await p.evaluate(() => irPara('salao')); await p.waitForTimeout(900);
  const bloco = await p.evaluate(() => { const b = document.getElementById('blocoComanda'); return b ? b.offsetParent !== null : null; });
  igual('em Meu negócio, "Como você trabalha" (comanda) não aparece', bloco, false);
  await p.evaluate(() => salvarCadastroSalao()); await p.waitForTimeout(1500);
  igual('e salvar o Meu negócio não religa a comanda',
    (await um(`select cfg->>'usaComanda' as v from public.saloes where id=$1`, [SALAO])).v, 'false');
  // + Profissional no limite: o aviso, antes da ficha.
  await p.evaluate(() => irPara('equipe')); await p.waitForTimeout(900);
  await p.getByRole('button', { name: '+ Profissional' }).click(); await p.waitForTimeout(700);
  const m = await p.evaluate(() => ({ titulo: (document.getElementById('modalTitulo') || {}).textContent,
    corpo: (document.getElementById('modalCorpo') || {}).innerText || '', ficha: !!document.getElementById('qNome') }));
  verdade('"+ Profissional" no limite avisa antes, sem abrir a ficha',
    m.titulo === 'Mais gente na equipe' && !m.ficha && /Dupla/.test(m.corpo), JSON.stringify(m));
  await p.evaluate(() => fecharModal());
  await fechar();
}
// Concluir: o banco transforma o atendimento em faturamento sozinho.
await dona.atualizar('agendamentos', ag.id, { status:'concluido' });
const auto = await um(`select count(*)::int as n, coalesce(sum(i.qtd * i.preco_unit),0)::numeric as v
  from public.comandas c join public.comanda_itens i on i.comanda_id = c.id
  where c.agendamento_id = $1 and c.status = 'fechada'`, [ag.id]);
verdade('concluir o atendimento lança o faturamento (comanda automática, fechada)',
  auto.n >= 1 && Number(auto.v) === 80, JSON.stringify(auto));

secao('3) O relatório: sem comissão a pagar para a própria dona');
{
  const { p, fechar } = await painel();
  await p.evaluate(dd => { irPara('relatorios'); relDe = dd; relAte = dd; prepararRelatorios(); }, hojeLa);
  await p.waitForTimeout(2500);
  const t = await p.evaluate(() => (document.getElementById('relCorpo') || {}).textContent.replace(/\s+/g, ' '));
  verdade('o faturamento do atendimento concluído aparece', /R\$\s*80,00/.test(t), t.slice(0, 300));
  verdade('contado como atendimento, e não como comanda', /atendimentos concluídos/.test(t) && !/comandas fechadas/.test(t), t.slice(0, 300));
  verdade('a linha da dona diz "é a dona"', /— é a dona/.test(t), t.slice(0, 500));
  verdade('e sem "comissões a pagar" nem "Total a pagar" (só ela atende)',
    !/comissões a pagar/.test(t) && !/Total a pagar/.test(t), t.slice(0, 500));
  await fechar();
}

secao('3b) A tela do Plano: o que inclui, quanto resta, e a saída a 90%');
{
  const { p, fechar } = await painel();
  await p.evaluate(() => irPara('plano')); await p.waitForTimeout(2800);
  const t = await p.evaluate(() => (document.getElementById('painelPlano') || {}).innerText || '');
  verdade('"O que o seu plano inclui", com a agenda e os relatórios (teste: tudo liberado)',
    /O que o seu plano inclui/.test(t) && /Agenda e link de agendamento/.test(t) && /Relatórios/.test(t), t.slice(0, 600));
  verdade('sem "Comanda e caixa" na lista (desligados na plataforma)', !/Comanda e caixa/.test(t), t.slice(0, 600));
  verdade('as mensagens dizem quantas restam no mês', /Restam\s*\d+\s*mensagens neste mês/.test(t), t.slice(0, 600));
  verdade('a equipe cheia no plano de 1 não assusta: diz em que plano cabe mais gente',
    !/chegou ao limite/.test(t) && /plano maior/.test(t) && /Dupla/.test(t), t.slice(0, 700));
  const a90 = await p.evaluate(() => avisoDeMensagens({ usado: 91, teto: 100, tetoSalao: null }));
  verdade('a 90% das mensagens, o aviso oferece comprar mais (pelo WhatsApp do suporte)',
    /91%/.test(a90) && /Comprar mais mensagens/.test(a90) && /wa\.me\/5511963659620/.test(a90), a90.slice(0, 400));
  const a80 = await p.evaluate(() => avisoDeMensagens({ usado: 85, teto: 100, tetoSalao: null }));
  verdade('a 85% ainda não oferece compra', !/Comprar mais mensagens/.test(a80), a80.slice(0, 300));
  await fechar();
}

secao('4) ?comanda=1 religa só naquela aba');
{
  const { p, fechar } = await painel('?comanda=1');
  const abas = await p.evaluate(() => [...document.querySelectorAll('#abas .aba')].map(b => b.dataset.chave));
  // O salão está "Só a agenda" no cfg: a aba não volta sozinha — mas a escolha volta a aparecer.
  await p.evaluate(() => irPara('salao')); await p.waitForTimeout(900);
  const bloco = await p.evaluate(() => { const b = document.getElementById('blocoComanda'); return b ? b.offsetParent !== null : null; });
  igual('com ?comanda=1, a escolha "Como você trabalha" volta', bloco, true);
  verdade('e a aba Caixa segue a escolha gravada (Só a agenda: sem Caixa)', !abas.includes('caixa'), JSON.stringify(abas));
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — O LINK DA CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('5) No link: obrigatórios marcados, "encerrado" e "Remarcado"');
async function link(){
  const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
  const q = await ctx.newPage();
  q.on('pageerror', e => erros.push('link: ' + e.message));
  q.on('dialog', d => d.accept());
  await q.addInitScript(b => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' }; }, BASE);
  await q.goto(BASE + '/agendar.html?salao=' + SLUG); await q.waitForTimeout(3200);
  return { q, fechar: () => ctx.close() };
}
{
  const { q, fechar } = await link();
  const ob = await q.evaluate(() => {
    const rot = id => { const c = document.getElementById(id); const l = c && c.querySelector('label'); return l ? !!l.querySelector('.obrig') : null; };
    return { nome: rot('campoNome'), tel: rot('campoTel'), nasc: rot('campoNasc'), email: rot('campoEmail'),
             cpf: rot('campoCpf'), legenda: !!document.getElementById('legendaObrig') };
  });
  igual('nome, WhatsApp, aniversário e e-mail com asterisco; CPF sem; e a legenda',
    ob, { nome:true, tel:true, nasc:true, email:true, cpf:false, legenda:true });
  await fechar();
}
// "Encerrado": hoje, o horário do salão e a jornada acabam à 00:01 — já passou.
{
  const dow = new Date(hojeLa + 'T12:00:00Z').getUTCDay();
  await banco.query(`update public.saloes set cfg = coalesce(cfg,'{}') || jsonb_build_object('funcionamento',
    jsonb_build_object($2::text, jsonb_build_array(jsonb_build_array('00:00','00:01')))) where id=$1`, [SALAO, String(dow)]);
  await banco.query(`delete from public.jornadas where profissional_id=$1 and dia_semana=$2`, [prof.id, dow]);
  await banco.query(`insert into public.jornadas (profissional_id, dia_semana, inicio, fim) values ($1, $2, '00:00', '00:01')`, [prof.id, dow]);
  const { q, fechar } = await link();
  await q.getByRole('button', { name: 'Agendar horário' }).filter({ visible: true }).first().click(); await q.waitForTimeout(1200);
  await q.getByText('Corte', { exact: true }).filter({ visible: true }).first().click(); await q.waitForTimeout(400);
  await q.getByRole('button', { name: 'Continuar' }).filter({ visible: true }).first().click(); await q.waitForTimeout(1200);
  const paraMim = q.getByText('Para mim', { exact: true }).filter({ visible: true }).first();
  if(await paraMim.count()){ await paraMim.click(); await q.waitForTimeout(1200); }
  const comQuem = q.getByRole('button', { name: 'Continuar' }).filter({ visible: true }).first();
  if(/Com quem/.test(await q.evaluate(() => document.body.innerText)) && await comQuem.count()){ await comQuem.click(); await q.waitForTimeout(1500); }
  const dias = await q.evaluate(() => [...document.querySelectorAll('#listaDias button.dia')].slice(0, 2).map(b => b.innerText.replace(/\s+/g, ' ')));
  verdade('o dia de hoje, depois do expediente, aparece "encerrado" — e não "cheio"',
    /encerrado/.test(dias[0] || '') && !/cheio/.test(dias[0] || ''), JSON.stringify(dias));
  await fechar();
  await banco.query(`update public.saloes set cfg = cfg - 'funcionamento' where id=$1`, [SALAO]);
  await banco.query(`delete from public.jornadas where profissional_id=$1 and dia_semana=$2`, [prof.id, dow]);
}
// "Remarcado": o horário trocado por outro, na lista da cliente.
{
  const amanha = new Date(new Date(hojeLa + 'T12:00:00Z').getTime() + 864e5).toISOString().slice(0, 10);
  const ini2 = amanha + 'T13:00:00Z';
  const ag2 = await dona.inserir('agendamentos', { salaoId: SALAO, clienteId: cliente.id, profissionalId: prof.id,
    inicio: ini2, fim: new Date(new Date(ini2).getTime() + 60 * 60000).toISOString(),
    status:'confirmado', origem:'recepcao', valorPrevisto: 80 });
  await dona.inserir('agendamento_servicos', { agendamentoId: ag2.id, servicoId: corte.id, ordem:1,
    duracaoMin:60, preco:80, comissaoPct:0 });
  const lista = async () => ((await um(`select public.meus_agendamentos(array[a.gerenciar_token]) as l
    from public.agendamentos a where a.id = $1`, [ag2.id])).l || [])[0] || {};
  await banco.query(`update public.agendamentos set status='cancelado', cancelado_motivo='cancelado pelo cliente' where id=$1`, [ag2.id]);
  igual('cancelado de verdade não sai como remarcado', (await lista()).remarcado, false);
  await banco.query(`update public.agendamentos set cancelado_motivo='remarcado pelo cliente' where id=$1`, [ag2.id]);
  igual('o que a cliente trocou por outro sai com remarcado = true', (await lista()).remarcado, true);
}

secao('Erros de JavaScript');
igual('nenhum, no painel e no link', erros, []);
await banco.end();
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} verificações do "só com agenda"${falhou ? `, ${falhou} falharam.` : '.'}`);
process.exit(falhou ? 1 : 0);
