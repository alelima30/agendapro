/* ===========================================================================
   AgendaPro — a cliente que precisa de confirmação

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/confirma-cliente.test.mjs

   O pedido do dono: "deixar na configuração que confirma já quando o
   cliente agendar — mas existe cliente chato que não quero atender, então
   preciso entrar no cadastro dele e colocar que ele precisa confirmar o
   horário. Um tipo de bloqueio para aquele cliente."

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. no banco, com o salão confirmando sozinho: a cliente comum sai
        confirmada; a marcada sai PENDENTE — também se trocar o primeiro nome
        (vale pelo WhatsApp);
     2. a pergunta "esta cliente está marcada?" não é aberta a ninguém;
     3. no painel: a marca na ficha grava no banco, e a lista mostra
        "confirma antes";
     4. no link: a marcada vê "Agendamento enviado" e "Aguardando
        confirmação do salão" — nunca "confirmado"; a comum vê confirmado;
     5. nenhum erro de JavaScript.
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
const n8 = String(Date.now() % 100000000).padStart(8, '0');
const TEL_CHATA = '519' + n8, TEL_BOA = '518' + n8, TEL_NOVA = '517' + n8;
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;

const dona = aba();
await dona.criarConta({ email:`cc-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const sv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:30, intervaloMin:0,
  preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
// O salão CONFIRMA SOZINHO: é o caso do pedido.
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA, confirmaAuto:true } });

const chata = await dona.inserir('clientes', { salaoId: SALAO, nome:'Carla Chata', telefone: TEL_CHATA, exigeConfirmacao: true });
await dona.inserir('clientes', { salaoId: SALAO, nome:'Bruna Boa', telefone: TEL_BOA });

/* Dias de amanhã em diante, com a primeira vaga livre de cada um. */
const anon = aba();
const amanha = d => { const x = new Date(); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); };
async function vaga(diaMais){
  const h = await anon.chamar('horarios_livres', { p_profissional: prof.id, p_data: amanha(diaMais), p_servicos: [sv.id] });
  return (Array.isArray(h) ? h : []).map(x => typeof x === 'string' ? x : Object.values(x)[0])[0];
}
async function marcar(nome, tel, diaMais){
  const r = await anon.chamar('agendar', { p_profissional: prof.id, p_inicio: await vaga(diaMais), p_servicos: [sv.id],
    p_nome: nome, p_telefone: tel });
  const f = Array.isArray(r) ? r[0] : r;
  const l = await anon.meusAgendamentos([f.token]);
  return l[0].status;
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. No banco, com o salão confirmando sozinho');
igual('a cliente comum sai confirmada', await marcar('Bruna Boa', TEL_BOA, 1), 'confirmado');
igual('a cliente marcada sai pendente, esperando o salão', await marcar('Carla Chata', TEL_CHATA, 2), 'pendente');
/* O número com +55 na frente não bate, ao pé da letra, com o da ficha — e
   nasce OUTRA ficha, sem a marca. A regra vale pelo WhatsApp (sem o 55),
   e não só pela ficha encontrada. */
igual('com +55 na frente e outro nome (nasce outra ficha), não escapa: vale pelo WhatsApp',
  await marcar('Carlinha', '+55 ' + TEL_CHATA, 3), 'pendente');
igual('e quem não está marcada continua confirmada', await marcar('Nova Pessoa', TEL_NOVA, 4), 'confirmado');

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Ninguém pergunta quem está marcada');
{
  let anonBarrado = false, logadoBarrado = false;
  try{ await anon.chamar('cliente_exige_confirmacao', { p_salao: SALAO, p_cliente: chata.id, p_tel: TEL_CHATA }); }
  catch(e){ anonBarrado = true; }
  try{ await dona.chamar('cliente_exige_confirmacao', { p_salao: SALAO, p_cliente: chata.id, p_tel: TEL_CHATA }); }
  catch(e){ logadoBarrado = true; }
  igual('nem sem login, nem logado (nem a dona): a função não responde por fora', [anonBarrado, logadoBarrado], [true, true]);
}

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. No painel: a marca na ficha');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => d.dismiss());
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.clientes) && bd.clientes.length >= 2, null, { timeout: 20000 });
  await p.waitForTimeout(800);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); irPara('clientes'); });
  await p.waitForTimeout(500);
  const linhas = await p.evaluate(() => [...document.querySelectorAll('#listaClientes tbody tr')].map(tr => tr.innerText.replace(/\s+/g, ' ')));
  verdade('a lista mostra "confirma antes" na Carla, e não na Bruna',
    linhas.some(l => /Carla Chata confirma antes/.test(l)) && linhas.some(l => /Bruna Boa/.test(l) && !/confirma antes/.test(l)), JSON.stringify(linhas));
  const bruna = await p.evaluate(() => bd.clientes.find(c => c.nome === 'Bruna Boa').id);
  await p.evaluate(id => abrirCliente(id), bruna); await p.waitForTimeout(300);
  igual('a ficha tem a marca, desligada para quem não precisa', await p.evaluate(() => {
    const c = document.getElementById('kExigeConf'); return c ? [c.checked, /precisam da minha confirmação/.test(c.closest('label').innerText)] : null; }),
    [false, true]);
  await p.check('#kExigeConf');
  await p.evaluate(id => salvarCliente(id), bruna); await p.waitForTimeout(2500);
  const noBanco = (await dona.lista('clientes', { salaoId: SALAO })).find(c => c.nome === 'Bruna Boa');
  igual('ligar a marca e salvar grava no banco', noBanco && noBanco.exigeConfirmacao, true);
  igual('e o próximo horário dela pelo link já nasce pendente', await marcar('Bruna Boa', TEL_BOA, 5), 'pendente');
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. No link: a tela de pronto diz a verdade');
async function marcarNoLink(nome, tel){
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(700);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(6).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  await p.fill('#dNome', nome); await p.fill('#dTel', masc(tel));
  await p.fill('#dNasc', '1990-01-01'); await p.fill('#dEmail', `x-${tel}@t.com`);
  await p.click('#btPrincipal'); await p.waitForTimeout(1000);
  const antes = await p.evaluate(() => document.getElementById('cfStatus').innerText.replace(/\s+/g, ' '));
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const r = await p.evaluate(() => ({ tela, titulo: document.querySelector('#p-pronto h2').textContent,
    chip: (document.querySelector('#resumoPronto .cf-chip') || {}).textContent || '' }));
  await ctx.close();
  return Object.assign(r, { antes });
}
{
  const a = await marcarNoLink('Carla Chata', TEL_CHATA);
  igual('a marcada: "Agendamento enviado!" e "Aguardando confirmação do salão" — nunca confirmado',
    [a.tela, a.titulo, /Aguardando confirmação do salão/.test(a.chip)], ['pronto', 'Agendamento enviado!', true]);
  const b = await marcarNoLink('Nova Pessoa', TEL_NOVA);
  igual('a comum: "Agendamento confirmado!"', [b.tela, b.titulo, /Confirmado/.test(b.chip)], ['pronto', 'Agendamento confirmado!', true]);
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
