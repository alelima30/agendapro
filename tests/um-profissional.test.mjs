/* ===========================================================================
   AgendaPro — "Com quem?" quando só uma pessoa faz o serviço

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/um-profissional.test.mjs

   O pedido: "Aqui só tem um atendente, então como fazer: só aparecer essa
   opção 'tanto faz' quando tiver dois atendentes, e quando tiver só um
   aparecer selecionado só a Ju."

   A conta é de quem faz AQUELE serviço, não do tamanho da equipe: num salão
   de duas, se só a Bia faz barba, para barba é só a Bia.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. uma pessoa só: sem "Tanto faz", ela marcada, o Continuar ligado, e os
        horários dela na tela seguinte;
     2. o voltar do horário não solta o horário já escolhido;
     3. duas pessoas: o "Tanto faz" volta, e nada vem marcado;
     4. duas na equipe, uma só que faz o serviço: só ela, marcada;
     5. trocar para um serviço que as duas fazem devolve a escolha;
     6. o "Livre quarta às 13:45" já na primeira passagem — ele saía do cache
        dos horários, que só era pedido na tela seguinte, e cada pessoa
        aparecia "sem horário" com a agenda livre. Com uma pessoa só, a
        pergunta ao banco é uma, não uma por tela.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
/* Conexão direta ao banco só para subir o plano: o teste grátis trava em uma
   profissional, e `assinaturas` só a plataforma escreve (como em auditoria). */
import pg from './pg.mjs';

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
await dona.criarConta({ email:`up-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const ju = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
const jornada = async p => { for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: p.id, diaSemana:i, inicio:'08:00', fim:'19:00' }); };
await jornada(ju);
const hidratacao = await dona.inserir('servicos', { salaoId: SALAO, nome:'Hidratação', duracaoMin:60,
  intervaloMin:0, preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const barba = await dona.inserir('servicos', { salaoId: SALAO, nome:'Barba', duracaoMin:30,
  intervaloMin:0, preco:40, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function ateComQuem(servico){
  const ctx = await nav.newContext({ viewport:{ width:412, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => { erros.push('ALERT: ' + d.message()); d.dismiss(); });
  p.perguntas = 0;
  p.on('request', r => { if(r.url().includes('/rpc/horarios_livres_periodo')) p.perguntas++; });
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('.boas-cta'), null, { timeout: 15000 });
  await p.click('.boas-cta');
  await p.waitForTimeout(500);
  await p.locator('#listaServicos .sv-cartao', { hasText: servico }).click();
  await p.click('#btPrincipal');
  await p.waitForTimeout(300);
  await p.click('#quemMim');
  await p.waitForTimeout(1500);
  return { p, fechar: () => ctx.close() };
}
const comQuem = p => p.evaluate(() => {
  const b = document.getElementById('btPrincipal');
  return {
    tela,
    opcoes: [...document.querySelectorAll('#listaProfs .opcao')].map(o =>
      o.querySelector('.tt').textContent.trim() + (o.classList.contains('sel') ? ' ✓' : '')),
    livre: [...document.querySelectorAll('#listaProfs .opcao')].slice(-2).map(o => o.querySelector('.dd').textContent.trim()),
    botao: [b.disabled, b.textContent.trim()],
  };
});

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Uma pessoa só: ela, já marcada');
{
  const { p, fechar } = await ateComQuem('Hidratação');
  const t = await comQuem(p);
  igual('sem "Tanto faz": só a Ju, marcada', [t.tela, t.opcoes], ['prof', ['Ju Barbosa ✓']]);
  igual('o Continuar já liga', t.botao, [false, 'Continuar']);
  igual('e a escolha é dela, não "qualquer um"', await p.evaluate(() => escolha.profissionalId), ju.id);
  igual('já na primeira passagem, o primeiro horário livre dela (e não "sem horário")',
    t.livre.map(x => /^Livre .+ às \d\d:\d\d$/.test(x)), [true]);
  await p.click('#btPrincipal');
  await p.waitForTimeout(2500);
  igual('os horários dela aparecem', [await p.evaluate(() => tela),
    await p.evaluate(() => document.querySelectorAll('#listaHoras .hora').length > 0)], ['quando', true]);
  igual('e o banco foi perguntado uma vez só, não uma por tela', p.perguntas, 1);

  secao('2. O voltar não solta o horário');
  await p.click('#listaHoras .hora');
  await p.waitForTimeout(300);
  const antes = await p.evaluate(() => [escolha.data, escolha.inicio]);
  await p.click('#btVoltar');
  await p.waitForTimeout(400);
  igual('de volta ao "Com quem?", o horário continua escolhido',
    [await p.evaluate(() => tela), await p.evaluate(() => [escolha.data, escolha.inicio])], ['prof', antes]);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Duas pessoas: o "Tanto faz" volta');
const bd = new pg.Client({
  host: process.env.PGHOST || '/tmp', port: +(process.env.PGPORT || 5444),
  user: process.env.PGUSER || 'postgres', database: process.env.PGBANCO || 'app' });
await bd.connect();
await bd.query(`delete from public.assinaturas where salao_id = $1`, [SALAO]);
await bd.query(`insert into public.assinaturas (salao_id, plano, status) values ($1, 'salao', 'ativa')`, [SALAO]);
await bd.end();
const bia = await dona.inserir('profissionais', { salaoId: SALAO, nome:'Bia Souza',
  cor:'#7C3AED', ativo:true, aceitaOnline:true, comissaoPct:0 });
await jornada(bia);
{
  const { p, fechar } = await ateComQuem('Hidratação');
  const t = await comQuem(p);
  igual('"Tanto faz" e as duas, nenhuma marcada', t.opcoes, ['Tanto faz', 'Ju Barbosa', 'Bia Souza']);
  igual('cada uma com o primeiro horário livre dela',
    t.livre.map(x => /^Livre .+ às \d\d:\d\d$/.test(x)), [true, true]);
  igual('o Continuar espera a escolha', t.botao, [true, 'Escolha com quem']);
  await p.locator('#listaProfs .opcao', { hasText: 'Tanto faz' }).click();
  await p.click('#btPrincipal');
  await p.waitForTimeout(2500);
  igual('"Tanto faz" usa a mesma resposta: os horários, e uma pergunta só',
    [await p.evaluate(() => document.querySelectorAll('#listaHoras .hora').length > 0), p.perguntas], [true, 1]);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Duas na equipe, uma só que faz o serviço');
// A Ju passa a fazer só hidratação; a Bia, sem lista, continua fazendo tudo.
await dona.inserir('servicos_profissionais', { servicoId: hidratacao.id, profissionalId: ju.id });
{
  const { p, fechar } = await ateComQuem('Barba');
  const t = await comQuem(p);
  igual('barba: só a Bia, marcada, sem "Tanto faz"', t.opcoes, ['Bia Souza ✓']);
  igual('e o Continuar ligado', t.botao, [false, 'Continuar']);

  secao('5. Trocar para um serviço que as duas fazem');
  await p.click('#btVoltar'); await p.waitForTimeout(300);
  await p.click('#btVoltar'); await p.waitForTimeout(300);
  await p.locator('#listaServicos .sv-cartao', { hasText: 'Barba' }).click();
  await p.locator('#listaServicos .sv-cartao', { hasText: 'Hidratação' }).click();
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  const t2 = await comQuem(p);
  igual('hidratação: a escolha volta, sem nada marcado', t2.opcoes, ['Tanto faz', 'Ju Barbosa', 'Bia Souza']);
  igual('e o Continuar espera de novo', t2.botao, [true, 'Escolha com quem']);
  await fechar();
}

igual('\nnenhum erro de JavaScript nem alerta', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
