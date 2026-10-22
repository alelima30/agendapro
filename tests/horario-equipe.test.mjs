/* ===========================================================================
   AgendaPro — o horário que abre vaga no link

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/horario-equipe.test.mjs

   Relatado: "alterei o horário para hoje até meia-noite, mas quando acesso o
   link não aparece esse horário" e "mudei o horário de quinta para as 7h e
   não apareceu através do link". Dois defeitos:

     1. O link marca pelo horário de cada PROFISSIONAL (`horarios_livres()`),
        e mudar o horário de funcionamento em Meu negócio não chegava nele.
        Agora quem seguia o horário da casa acompanha sozinho, e quem tem
        horário próprio só muda se o dono confirmar.
     2. Na ficha do profissional, "09:00 às 00:00" terminava antes de começar:
        a faixa era DESCARTADA calada, e o dia virava folga. 00:00 no fim é
        meia-noite, e o banco guarda '24:00:00'.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
const secao = t => console.log('\n' + t);
const sql = q => execSync('psql -At -v ON_ERROR_STOP=1', { input: q, env: { ...process.env,
  PGHOST: process.env.PGHOST || '/tmp', PGPORT: process.env.PGPORT || '5444',
  PGUSER: process.env.PGUSER || 'postgres', PGDATABASE: process.env.PGBANCO || 'app' } }).toString().trim();

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

/* ── O salão: a Rita segue o horário da casa, o Lucas tem o dele ─────────── */
const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const dona = aba();
await dona.criarConta({ email:`he-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salao Megatop ' + m,
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
sql(`update public.assinaturas set plano='salao', status='ativa', vence_em=current_date+30
      where salao_id='${SALAO}'`);
const SEMANA = { 1:[['09:00','18:00']], 2:[['09:00','18:00']], 3:[['09:00','18:00']],
                 4:[['09:00','18:00']], 5:[['09:00','18:00']], 6:[['09:00','18:00']], 0:[] };
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, antecedenciaMin:0, funcionamento:SEMANA } });
const rita = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
const lucas = await dona.inserir('profissionais', { salaoId: SALAO, nome:'Lucas', ativo:true, cor:'#0ea5e9' });
for(let d = 1; d <= 6; d++){
  await dona.inserir('jornadas', { profissionalId: rita.id, diaSemana:d, inicio:'09:00', fim:'18:00' });
  // O Lucas sai mais cedo às quintas: horário próprio.
  await dona.inserir('jornadas', { profissionalId: lucas.id, diaSemana:d, inicio:'10:00',
                                   fim: d === 4 ? '15:00' : '19:00' });
}
const SV = (await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte', duracaoMin:30,
  intervaloMin:0, preco:50, ativo:true, aceitaOnline:true })).id;

// A próxima quinta-feira, daqui a pelo menos um dia (o horário de hoje
// depende de que horas o teste roda).
const quinta = sql(`select (current_date + 1 + ((4 - extract(dow from current_date + 1)::int + 7) % 7))::text`);
const vagas = prof => sql(`select coalesce(string_agg(to_char(h at time zone 'America/Sao_Paulo', 'HH24:MI'), ' '
  order by h), '') from public.horarios_livres('${prof}', '${quinta}', array['${SV}'::uuid]) h`).split(' ');
const jornadaDe = (prof, d) => sql(`select string_agg(inicio::text || '-' || fim::text, ',' order by inicio)
  from public.jornadas where profissional_id='${prof}' and dia_semana=${d}`);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
const p = await ctx.newPage();
const erros = [], dialogos = [];
let responder = true;
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', d => { dialogos.push(d.message()); responder ? d.accept() : d.dismiss(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForFunction(() => typeof irPara === 'function'
  && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes) && bd.profissionais.length, null, { timeout: 20000 });
await p.waitForTimeout(1200);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });

/* ══════════════════════════════════════════════════════════════════════════
   1 — QUINTA ÀS 7H NO FUNCIONAMENTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · Mudar o funcionamento de quinta para as 7h');
verdade('antes: a primeira vaga da Rita na quinta é 09:00', vagas(rita.id)[0] === '09:00', vagas(rita.id).join(' '));

await p.evaluate(() => { irPara('salao'); trocarAbaSalao('dados'); });
await p.waitForTimeout(600);
responder = false;   // "Usar também na agenda do Lucas?" → Cancelar
await p.evaluate(() => { funcEscolhido[4] = [['07:00', '18:00']]; salvarCadastroSalao(); });
await p.waitForTimeout(2000);

verdade('a Rita, que seguia o horário da casa, passa a começar às 07:00 na quinta',
  jornadaDe(rita.id, 4) === '07:00:00-18:00:00', jornadaDe(rita.id, 4));
verdade('e o link já oferece 07:00 na quinta (antes: só a partir das 09:00)',
  vagas(rita.id)[0] === '07:00', vagas(rita.id).slice(0, 4).join(' '));
verdade('os outros dias dela não mudam', jornadaDe(rita.id, 3) === '09:00:00-18:00:00', jornadaDe(rita.id, 3));
verdade('o Lucas, que tem horário próprio, foi PERGUNTADO',
  dialogos.some(x => /Usar este horário também na agenda de Lucas/.test(x)), dialogos.join(' | '));
verdade('e, com Cancelar, o horário dele fica como estava',
  jornadaDe(lucas.id, 4) === '10:00:00-15:00:00', jornadaDe(lucas.id, 4));

/* ══════════════════════════════════════════════════════════════════════════
   2 — ATÉ MEIA-NOITE NA FICHA DO PROFISSIONAL
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · A Rita atende até meia-noite na quinta');
await p.evaluate(id => abrirProf(id), rita.id);
await p.waitForTimeout(400);
await p.fill('#j4b', '00:00');
await p.evaluate(id => salvarProf(id), rita.id);
await p.waitForTimeout(2000);
verdade('a quinta continua na jornada, até 24:00 no banco (antes: a faixa sumia e virava folga)',
  jornadaDe(rita.id, 4) === '07:00:00-24:00:00', String(jornadaDe(rita.id, 4)));
const ultimas = vagas(rita.id);
verdade('o link oferece até 23:30 na quinta (serviço de 30 minutos)',
  ultimas[ultimas.length - 1] === '23:30', ultimas.slice(-3).join(' '));

await p.evaluate(id => abrirProf(id), rita.id);
await p.waitForTimeout(400);
verdade('reabrindo a ficha, a saída aparece como 00:00, e não "24:00"',
  await p.inputValue('#j4b') === '00:00', await p.inputValue('#j4b'));
await p.evaluate(() => fecharModal());

/* ══════════════════════════════════════════════════════════════════════════
   3 — MUDAR A QUARTA E SALVAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · "Mudei a quarta da Ju, salvei, e ficou sem horário"');
const quartaAntes = jornadaDe(lucas.id, 3);
await p.evaluate(id => abrirProf(id), lucas.id);
await p.waitForTimeout(400);
await p.fill('#j3a', '08:00');
await p.fill('#j3b', '17:00');
await p.evaluate(id => salvarProf(id), lucas.id);
await p.waitForTimeout(2000);
verdade('a quarta nova vai para o banco: 08:00 às 17:00',
  jornadaDe(lucas.id, 3) === '08:00:00-17:00:00', `antes ${quartaAntes}, agora ${jornadaDe(lucas.id, 3)}`);
verdade('e os outros dias dele não mudam', jornadaDe(lucas.id, 4) === '10:00:00-15:00:00', jornadaDe(lucas.id, 4));

responder = true;
dialogos.length = 0;
await p.evaluate(id => abrirProf(id), lucas.id);
await p.waitForTimeout(400);
await p.fill('#j3a', '19:00');
await p.fill('#j3b', '07:00');
await p.evaluate(id => salvarProf(id), lucas.id);
await p.waitForTimeout(1200);
verdade('saída antes da entrada: o salvar para e diz o dia (antes: a quarta sumia calada)',
  dialogos.some(x => /Quarta: a saída \(07:00\) tem de ser depois da entrada \(19:00\)/.test(x)),
  dialogos.join(' | '));
verdade('e nada é gravado — a quarta continua 08:00 às 17:00',
  jornadaDe(lucas.id, 3) === '08:00:00-17:00:00', jornadaDe(lucas.id, 3));
verdade('com a ficha ainda aberta para acertar', await p.isVisible('#j3a'));

dialogos.length = 0;
await p.fill('#j3a', '08:00');
await p.fill('#j3b', '');
await p.evaluate(id => salvarProf(id), lucas.id);
await p.waitForTimeout(1200);
verdade('só a entrada preenchida: diz que falta a saída',
  dialogos.some(x => /Quarta: falta o horário de saída/.test(x)), dialogos.join(' | '));
await p.evaluate(() => fecharModal());

verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
