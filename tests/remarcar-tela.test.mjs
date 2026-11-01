/* ===========================================================================
   AgendaPro — remarcar pelo painel

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/remarcar-tela.test.mjs

   O pedido: "na onde entro para remarcar caso precise?" — e não havia onde.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a janela do atendimento tem "Remarcar"; os horários livres não contam
        o próprio horário como ocupado; remarcar MOVE o mesmo atendimento;
     2. sessão de pacote: fora dos dias do pacote o banco recusa, a janela diz
        por quê e nada muda;
     3. fora da jornada: pergunta, e com o sim fica como encaixe;
     4. atendimento concluído não oferece "Remarcar";
     5. "Cancelar horário", vermelho, ao lado do Arquivar: pergunta antes; com
        o não nada muda, com o sim cancela (e a sessão do pacote volta);
     6. o lembrete da cliente (marcas E texto) aparece no cartão do dia, na
        grade e na lista do que espera confirmação — "para eu saber quem é";
     7. vender o pacote "Já pagou" pergunta antes: com o não, nada é gravado;
     8. a 390px a janela cabe; nenhum erro de JavaScript.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pgLib from './pg.mjs';

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

const banco = new pgLib.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const linha = async (q, v) => (await banco.query(q, v)).rows[0];

const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const dona = aba();
await dona.criarConta({ email:`rm-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Remarca ' + m,
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:60,
  intervaloMin:0, preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA } });
const MARIA = (await linha(`insert into public.clientes (salao_id, nome, telefone) values ($1, 'Maria Souza', $2)
  returning id`, [SALAO, '119' + String(10000000 + Math.floor(Math.random() * 89999999))])).id;

// Daqui a dois dias, no fuso do salão.
const D = (await linha(`select to_char((now() at time zone 'America/Sao_Paulo')::date + 2, 'YYYY-MM-DD') d`)).d;
const D1 = (await linha(`select to_char($1::date + 1, 'YYYY-MM-DD') d`, [D])).d;
const DOW = (await linha(`select extract(dow from $1::date)::int d`, [D])).d;
async function horario(hora, status = 'confirmado'){
  const a = await linha(`insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim,
      status, origem, valor_previsto)
    values ($1, $2, $3, ($4::date + $5::time) at time zone 'America/Sao_Paulo',
            ($4::date + $5::time + interval '60 minutes') at time zone 'America/Sao_Paulo', $6, 'recepcao', 50)
    returning id`, [SALAO, MARIA, prof.id, D, hora, status]);
  await banco.query(`insert into public.agendamento_servicos (agendamento_id, servico_id, ordem, duracao_min, preco, comissao_pct)
    values ($1, $2, 1, 60, 50, 0)`, [a.id, escova.id]);
  return a.id;
}
const onde = async id => (await linha(`select to_char(inicio at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') h,
  encaixe, status, pacote_cliente_id, (select count(*)::int from public.agendamento_servicos where agendamento_id = $1) n
  from public.agendamentos where id = $1`, [id]));

const A = await horario('10:00');
const FEITO = await horario('08:00', 'concluido');
// O pacote que vale só no dia da semana de D, com uma sessão às 13h.
const pacote = await dona.inserir('pacotes', { salaoId: SALAO, nome:'Escova da semana', preco:150,
  sessoes:4, validadeDias:60, dias:[DOW], ativo:true });
await dona.inserir('pacote_servicos', { pacoteId: pacote.id, servicoId: escova.id });
const montado = await dona.chamar('montar_pacote', { p_pacote: pacote.id, p_cliente: MARIA, p_valor: 150,
  p_forma: null, p_profissional: prof.id, p_semanas: [{ inicio: (await linha(
    `select to_char(($1::date + time '13:00') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SSOF') i`, [D])).i,
    servicos: [escova.id] }] });
const SESSAO = (Array.isArray(montado) ? montado[0] : montado).agendamentos[0];

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [], dialogos = [];
let responder = true;
const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
const p = await ctx.newPage();
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => { dialogos.push(d.message()); responder ? d.accept() : d.dismiss(); });
await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
  && bd.planos && bd.planos.length, null, { timeout: 20000 });
await p.waitForTimeout(1200);
await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
const botoes = () => p.evaluate(() => [...document.querySelectorAll('#modalPe .btn')].map(b => b.textContent.trim()));
const aviso = () => p.evaluate(() => (document.getElementById('rmAviso') || {}).innerText || '').then(t => t.replace(/\s+/g, ' ').trim());
const livres = () => p.evaluate(() => [...document.querySelectorAll('#fLivres .hl-op')].map(b => b.textContent.trim()));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Remarcar move o mesmo atendimento');
await p.evaluate(id => abrirDetalhe(id), A);
verdade('a janela do atendimento tem "Remarcar"', (await botoes()).includes('Remarcar'), (await botoes()).join(' | '));
await p.click('#modalPe .btn:has-text("Remarcar")');
await p.waitForSelector('#rmAviso');
igual('abre "Remarcar horário", no dia e com a profissional de agora', await p.evaluate(() =>
  [document.getElementById('modalTitulo').textContent, document.getElementById('fData').value,
   document.getElementById('fProf').value]), ['Remarcar horário', D, prof.id]);
const l1 = await livres();
verdade('o próprio horário (10:00) aparece como livre — ele não ocupa o lugar dele', l1.includes('10:00'), l1.join(' '));
await p.click('#fLivres .hl-op:has-text("15:00")');
verdade('escolhido: mostra das 15:00 às 16:00', /15:00 às 16:00/.test(await aviso()), await aviso());
verdade('a 390px a janela cabe', await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
await p.click('#modalPe .btn-p:has-text("Remarcar")');
await p.waitForFunction(() => !document.getElementById('fundo').classList.contains('on'), null, { timeout: 10000 }).catch(() => {});
const a1 = await onde(A);
igual('no banco: o MESMO atendimento, às 15:00, com o serviço, sem virar encaixe',
  [a1.h, a1.n, a1.encaixe, a1.status], [D + ' 15:00', 1, false, 'confirmado']);
igual('e a janela fechou, com a agenda no dia novo', await p.evaluate(() =>
  [document.getElementById('fundo').classList.contains('on'), diaAtual]), [false, D]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Sessão de pacote: os dias do pacote valem');
await p.evaluate(id => { abrirDetalhe(id); }, SESSAO);
await p.click('#modalPe .btn:has-text("Remarcar")');
await p.waitForSelector('#rmAviso');
verdade('a janela diz que é sessão do pacote', /sessão do pacote/.test(await p.evaluate(() =>
  document.getElementById('modalCorpo').innerText)));
await p.fill('#fData', D1); await p.dispatchEvent('#fData', 'change');
await p.fill('#fInicio', '13:00'); await p.dispatchEvent('#fInicio', 'change');
await p.click('#modalPe .btn-p:has-text("Remarcar")');
await p.waitForFunction(() => /pacote vale só/.test((document.getElementById('rmAviso') || {}).innerText || ''),
  null, { timeout: 10000 }).catch(() => {});
verdade('no dia seguinte, o banco recusa e a janela diz por quê', /O pacote vale só .*Nada mudou/.test(await aviso()), await aviso());
const s1 = await onde(SESSAO);
igual('e a sessão ficou onde estava, no pacote', [s1.h, !!s1.pacote_cliente_id], [D + ' 13:00', true]);
await p.fill('#fData', D); await p.dispatchEvent('#fData', 'change');
await p.fill('#fInicio', '17:00'); await p.dispatchEvent('#fInicio', 'change');
await p.click('#modalPe .btn-p:has-text("Remarcar")');
await p.waitForFunction(() => !document.getElementById('fundo').classList.contains('on'), null, { timeout: 10000 }).catch(() => {});
const s2 = await onde(SESSAO);
igual('no mesmo dia, às 17:00: move, e continua no pacote', [s2.h, !!s2.pacote_cliente_id], [D + ' 17:00', true]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Fora da jornada: pergunta, e fica como encaixe');
await p.evaluate(id => abrirDetalhe(id), A);
await p.click('#modalPe .btn:has-text("Remarcar")');
await p.waitForSelector('#rmAviso');
await p.fill('#fInicio', '19:30'); await p.dispatchEvent('#fInicio', 'change');
verdade('a janela avisa que é fora da jornada, e que vai perguntar', /Fora da jornada.*vai pedir sua confirmação/.test(await aviso()), await aviso());
dialogos.length = 0;
await p.click('#modalPe .btn-p:has-text("Remarcar")');
await p.waitForFunction(() => !document.getElementById('fundo').classList.contains('on'), null, { timeout: 10000 }).catch(() => {});
verdade('perguntou se encaixa', dialogos.some(d => /Confirmar o encaixe\?/.test(d)), dialogos.join(' | '));
const a2 = await onde(A);
igual('com o sim: às 19:30, como encaixe', [a2.h, a2.encaixe], [D + ' 19:30', true]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Atendimento concluído não se remarca');
await p.evaluate(id => abrirDetalhe(id), FEITO);
verdade('sem o botão', !(await botoes()).includes('Remarcar'), (await botoes()).join(' | '));
verdade('nem o de cancelar', !(await botoes()).includes('Cancelar horário'), (await botoes()).join(' | '));
await p.evaluate(() => fecharModal());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Cancelar em um toque, com a pergunta antes');
await p.evaluate(id => abrirDetalhe(id), A);
const b5 = await botoes();
igual('"Cancelar horário" logo depois do Arquivar', b5.slice(0, 2), ['Arquivar', 'Cancelar horário']);
igual('em vermelho: o botão de risco do tema (letra no --erro, como o "Excluir")', await p.evaluate(() => {
  const b = [...document.querySelectorAll('#modalPe .btn')].find(x => x.textContent.trim() === 'Cancelar horário');
  const h = getComputedStyle(document.documentElement).getPropertyValue('--erro').trim();
  const rgb = h.replace(/^#(..)(..)(..)$/, (_, r, g, bb) => `rgb(${parseInt(r, 16)}, ${parseInt(g, 16)}, ${parseInt(bb, 16)})`);
  return [b.classList.contains('btn-perigo'), getComputedStyle(b).color === rgb]; }), [true, true]);
responder = false; dialogos.length = 0;
await p.click('#modalPe .btn:has-text("Cancelar horário")');
await p.waitForTimeout(500);
verdade('pergunta se tem certeza, com o nome e o horário', dialogos.length === 1
  && /^Tem certeza que quer cancelar o horário de Maria Souza\?/.test(dialogos[0]) && /19:30/.test(dialogos[0]), dialogos.join(' | '));
igual('com o não: nada muda, e a janela continua', [(await onde(A)).status,
  await p.evaluate(() => document.getElementById('fundo').classList.contains('on'))], ['confirmado', true]);
responder = true; dialogos.length = 0;
await p.click('#modalPe .btn:has-text("Cancelar horário")');
await p.waitForFunction(() => !document.getElementById('fundo').classList.contains('on'), null, { timeout: 10000 }).catch(() => {});
await p.waitForTimeout(2000);
const c5 = await linha(`select status, cancelado_motivo from public.agendamentos where id = $1`, [A]);
igual('com o sim: cancelado no banco, com o motivo', [c5.status, c5.cancelado_motivo], ['cancelado', 'cancelado pelo salão']);
await p.evaluate(id => abrirDetalhe(id), SESSAO);
dialogos.length = 0;
await p.click('#modalPe .btn:has-text("Cancelar horário")');
await p.waitForTimeout(2500);
verdade('na sessão do pacote, a pergunta diz que a sessão volta para ele',
  dialogos.some(d => /A sessão volta para o pacote dela/.test(d)), dialogos.join(' | '));
const r5 = await linha(`select public.pacote_sessoes_restantes(pacote_cliente_id) n, status from public.agendamentos where id = $1`, [SESSAO]);
igual('e volta: as 4 sessões livres de novo', [r5.status, r5.n], ['cancelado', 4]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. O lembrete da cliente aparece onde ela aparece');
await banco.query(`insert into public.clientes_lembretes (salao_id, cliente_id, marcas, texto)
  values ($1, $2, '{"Atenção no pagamento"}', 'muito chata')`, [SALAO, MARIA]);
const PEND = await horario('09:00', 'pendente');
await banco.query(`update public.agendamentos set origem = 'online' where id = $1`, [PEND]);
await p.evaluate(async () => { const novo = await carregarTudo(); if(novo) bd = novo; });
const l6 = await p.evaluate(([id, d]) => {
  const a = bd.agendamentos.find(x => x.id === id);
  irPara('agenda'); diaAtual = d; pintar(); pintarAConfirmar();
  return { cartao: cartaoDoDia(a),
           fila: (document.getElementById('aConfirmar') || {}).innerText || '' };
}, [PEND, D]);
verdade('no cartão do dia: as marcas e o texto ("muito chata")',
  l6.cartao.includes('class="dc-lembrete">Atenção no pagamento · muito chata<'), l6.cartao);
verdade('na lista do que espera sua confirmação, junto do nome',
  /Maria Souza[\s\S]*Atenção no pagamento · muito chata/.test(l6.fila), l6.fila);
await p.evaluate(() => { trocarVista('dia'); });
await p.waitForTimeout(400);
const g6 = await p.evaluate(() => [...document.querySelectorAll('.ag .ag-lembrete')].map(e => e.textContent.trim()));
verdade('e na grade do dia, no bloco do horário', g6.includes('Atenção no pagamento · muito chata'), JSON.stringify(g6));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. Vender o pacote "Já pagou" pergunta antes');
const JOANA = (await linha(`insert into public.clientes (salao_id, nome, telefone) values ($1, 'Joana Lima', $2)
  returning id`, [SALAO, '119' + String(10000000 + Math.floor(Math.random() * 89999999))])).id;
await p.evaluate(async () => { const novo = await carregarTudo(); if(novo) bd = novo; });
const venderJaPago = async () => {
  await p.evaluate(pid => { fecharModal(); abrirVenderPacote(pid); }, pacote.id);
  await p.waitForSelector('#pkCliente');
  await p.selectOption('#pkCliente', JOANA);
  await p.fill('#pkValor', '150');
  await p.selectOption('#pkForma', 'pix');
  await p.click('#modalPe .btn-p:has-text("Vincular")');
  await p.waitForTimeout(2500);
};
responder = false; dialogos.length = 0;
await venderJaPago();
verdade('pergunta: "Confirma que recebeu R$ 150,00 (Pix) de Joana Lima?"',
  dialogos.some(d => /^Confirma que recebeu R\$\s?150,00 \(Pix\) de Joana Lima\?/.test(d)), dialogos.join(' | '));
igual('com o não, nada é gravado',
  (await linha(`select count(*)::int n from public.pacote_clientes where cliente_id = $1`, [JOANA])).n, 0);
responder = true; dialogos.length = 0;
await venderJaPago();
igual('com o sim, o pacote fica pago no Pix',
  await linha(`select pago_em is not null as pago, forma_pagamento f from public.pacote_clientes where cliente_id = $1`, [JOANA]),
  { pago: true, f: 'pix' });

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
