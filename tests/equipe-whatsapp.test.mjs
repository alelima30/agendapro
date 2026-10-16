/* ===========================================================================
   AgendaPro — as mensagens da equipe dizem que precisam do WhatsApp de cada um

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/equipe-whatsapp.test.mjs

   O pedido: "precisa informar em algum lugar que, para funcionar as
   mensagens, precisa cadastrar o telefone no profissional."

   O aviso de horário novo, o lembrete e o resumo do dia vão para o WhatsApp
   de CADA profissional. Sem número o banco pula a pessoa sem erro nenhum — e
   o dono, que ligou a caixa em Mensagens da agenda, achava que funcionava.

   Três lugares avisam, e este arquivo cobra os três:
     1. Mensagens da agenda: com alguma mensagem da equipe ligada, o nome de
        quem está sem número e o caminho para Equipe;
     2. o cartão de cada um em Equipe;
     3. a ficha do profissional, embaixo do campo do WhatsApp.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
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
await dona.criarConta({ email:`ew-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Lia Prado', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Zap ' + m,
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
// Plano com equipe: o teste grátis aceita um profissional só.
const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: Number(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
await banco.query(`update public.assinaturas set plano='equipe', status='ativa',
  vence_em = current_date + 30 where salao_id=$1`, [SALAO]);
await banco.end();
/* A dona (criada sem número na ficha de profissional), a Bia com número, o
   Caio sem, e a Duda sem número mas inativa — inativa não atende, e não
   recebe nada mesmo. */
const lia = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
await dona.inserir('profissionais', { salaoId: SALAO, nome:'Bia Souza', ativo:true,
  telefone:'(11) 97777-6666', comissaoPct:40, cor:'#2563EB' });
await dona.inserir('profissionais', { salaoId: SALAO, nome:'Caio Lima', ativo:true,
  comissaoPct:40, cor:'#16A34A' });
await dona.inserir('profissionais', { salaoId: SALAO, nome:'Duda Reis', ativo:false,
  comissaoPct:40, cor:'#DC2626' });
ok('salão com a dona e três profissionais (um com WhatsApp, um sem, um inativo sem)');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const p = await (await nav.newContext({ viewport:{ width:1360, height:900 } })).newPage();
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => d.accept());
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForFunction(() => typeof irPara === 'function'
  && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
await p.waitForTimeout(1200);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });

/* ══════════════════════════════════════════════════════════════════════════
   1 — MENSAGENS DA AGENDA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. Mensagens da agenda');
await p.evaluate(() => irPara('salao'));
await p.waitForTimeout(500);
await p.evaluate(() => trocarAbaSalao('notificacoes'));
await p.waitForTimeout(700);
const aviso = () => p.evaluate(() => {
  const a = document.querySelector('#avisoTelEquipe .aviso');
  return a ? a.textContent.replace(/\s+/g, ' ').trim() : '';
});
const marcar = (id, v) => p.evaluate(([i, val]) => {
  const e = document.getElementById(i);
  if(e.checked !== val){ e.checked = val; e.dispatchEvent(new Event('change', { bubbles: true })); }
}, [id, v]);

igual('o aviso de horário novo vem ligado de fábrica', await p.isChecked('#nProfNovo'), true);
const a1 = await aviso();
verdade('e por isso o aviso aparece, dizendo o que falta', /Falta o WhatsApp de quem atende/.test(a1), a1);
verdade('explica para que serve o número', /aviso de horário novo, o lembrete e o resumo do dia/.test(a1), a1);
verdade('cita quem está sem: a dona e o Caio', a1.includes('Lia Prado') && a1.includes('Caio Lima'), a1);
verdade('não cita a Bia, que tem número', !a1.includes('Bia Souza'), a1);
verdade('nem a Duda, que está inativa', !a1.includes('Duda Reis'), a1);

await marcar('nProfNovo', false);
igual('com as mensagens da equipe desligadas, o aviso some', await aviso(), '');
await marcar('nLembEquipe', true);
await p.selectOption('#nLembEquipePara', 'dono');
await p.evaluate(() => pintarNotificacoes(true));
igual('o lembrete só para o dono do salão não pede o número da equipe', await aviso(), '');
await p.selectOption('#nLembEquipePara', 'atende');
await p.evaluate(() => pintarNotificacoes(true));
verdade('para quem vai atender, pede', /Falta o WhatsApp/.test(await aviso()));
await marcar('nLembEquipe', false);
await marcar('nResumo', true);
verdade('o resumo do dia também pede', /Falta o WhatsApp/.test(await aviso()));

await p.locator('#avisoTelEquipe button', { hasText: 'Cadastrar em Equipe' }).click();
await p.waitForTimeout(800);
verdade('o botão leva para Equipe', await p.evaluate(() =>
  !!document.querySelector('#listaEquipe .card')));

/* ══════════════════════════════════════════════════════════════════════════
   2 — O CARTÃO DE CADA UM EM EQUIPE
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. Equipe');
const cartoes = await p.evaluate(() => [...document.querySelectorAll('#listaEquipe .card')].map(c => ({
  nome: c.querySelector('h3').textContent.replace(/\s+/g, ' ').trim(),
  semTel: !!c.querySelector('.eq-sem-tel') })));
const de = n => (cartoes.find(c => c.nome.includes(n)) || {}).semTel;
igual('a dona e o Caio mostram "Sem WhatsApp cadastrado"', [de('Lia Prado'), de('Caio Lima')], [true, true]);
igual('a Bia não', de('Bia Souza'), false);
igual('a inativa também não (não atende, não recebe)', de('Duda Reis'), false);

/* ══════════════════════════════════════════════════════════════════════════
   3 — A FICHA, E O AVISO SUMINDO QUANDO O NÚMERO ENTRA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. A ficha do profissional');
await p.evaluate(id => abrirProf(id), lia.id);
await p.waitForTimeout(500);
const ajuda = await p.evaluate(() => (document.getElementById('qTelAjuda') || {}).textContent || '');
verdade('embaixo do WhatsApp, diz para que serve o número', /aviso de horário novo, o lembrete e o resumo do dia/.test(ajuda)
  && /Sem número/.test(ajuda), ajuda);
await p.fill('#qTel', '(11) 96666-5555');
await p.locator('.modal button', { hasText: 'Salvar' }).last().click();
await p.waitForTimeout(1500);
const depois = await p.evaluate(() => [...document.querySelectorAll('#listaEquipe .card')]
  .filter(c => c.querySelector('h3').textContent.includes('Lia Prado'))
  .map(c => !!c.querySelector('.eq-sem-tel'))[0]);
igual('com o número salvo, o cartão da dona para de avisar', depois, false);
await p.evaluate(() => irPara('salao'));
await p.waitForTimeout(400);
await p.evaluate(() => trocarAbaSalao('notificacoes'));
await p.waitForTimeout(600);
await marcar('nProfNovo', true);
const a2 = await aviso();
verdade('e Mensagens da agenda passa a citar só o Caio', a2.includes('Caio Lima') && !a2.includes('Lia Prado'), a2);

secao('4. Nada quebrou');
igual('sem erro de JavaScript', erros, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
