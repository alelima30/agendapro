/* ===========================================================================
   AgendaPro — o que só a equipe sabe, nas telas (41_ficha_equipe.sql)

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/ficha-equipe.test.mjs

   Os pedidos: "um lugar que o profissional consiga fazer o procedimento —
   coloração loiro perolado, quais as tintas e como lavar o cabelo" e "no
   cadastro da cliente Maria, marcar algo que lembre dela: não gosta de
   conversar, dá problema na hora do pagamento". O banco tem o
   tests/ficha_equipe.test.sql. Aqui, as telas:

     1. a dona escreve o como fazer no serviço e marca a Maria — e a
        cliente nova já nasce com o lembrete, numa gravação só;
     2. a profissional (outro login) abre o horário da Maria e vê o
        lembrete e o como fazer; o cartão do dia mostra as marcas;
     3. desmarcar tudo apaga o lembrete;
     4. o link da cliente não recebe nem o lembrete nem o como fazer;
     5. PROCEDIMENTOS, o tópico próprio: a dona cria Morena iluminada e Loiro
        perolado na Coloração; a Bia vê a aba (sem criar nem editar), o passo
        a passo numerado, e os dois no horário da Maria; o link não recebe.
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
const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const tel = () => '+5511' + (900000000 + Math.floor(Math.random() * 89999999));

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const um = async (q, v) => (await banco.query(q, v)).rows[0] || null;

// ── O salão, com a dona e a Bia (outro login, convidada) ───────────────────
const dDona = novaAba();
await dDona.criarConta({ email:`fe-dona-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone: tel() });
const cr = await dDona.chamar('criar_salao', { p_nome_salao:'Salão Ficha ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3333-4444', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await banco.query(`update public.assinaturas set plano='time', status='ativa' where salao_id=$1`, [SALAO]);

const P1 = (await dDona.lista('profissionais', { salaoId: SALAO }))[0];
const P2 = await dDona.inserir('profissionais', { salaoId: SALAO, nome:'Bia',
  ativo:true, aceitaOnline:true, comissaoPct:40, cor:'#7C3AED' });
for(const p of [P1, P2])
  for(let i = 0; i <= 6; i++)
    await dDona.inserir('jornadas', { profissionalId: p.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const SV = await dDona.inserir('servicos', { salaoId: SALAO, nome:'Coloração loiro perolado',
  duracaoMin:120, intervaloMin:0, preco:350, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
await dDona.inserir('servicos_profissionais', { servicoId: SV.id, profissionalId: P2.id });

const convite = await dDona.chamar('criar_convite', { p_salao: SALAO, p_papel: 'profissional',
  p_para_quem: 'Bia', p_profissional: P2.id });
const dBia = novaAba();
await dBia.criarConta({ email:`fe-bia-${marca}@teste.com`, senha:'minhasenhaboa', nome:'Bia', telefone: tel() });
await dBia.chamar('aceitar_convite', { p_token: convite.token });

const CLI = await dDona.inserir('clientes', { salaoId: SALAO, nome:'Maria Lima',
  telefone:'11' + (900000000 + Math.floor(Math.random() * 99999999)) });
const AMANHA = new Date(Date.now() + 864e5).toISOString().slice(0, 10);
const desl = new Intl.DateTimeFormat('en-US', { timeZone:'America/Sao_Paulo',
  timeZoneName:'longOffset' }).formatToParts(new Date(AMANHA + 'T12:00:00Z'))
  .find(x => x.type === 'timeZoneName').value.replace('GMT', '');
const AG = await dDona.inserir('agendamentos', { salaoId: SALAO, clienteId: CLI.id,
  profissionalId: P2.id, inicio:`${AMANHA}T10:00:00${desl}`, fim:`${AMANHA}T12:00:00${desl}`,
  status:'confirmado', origem:'recepcao', valorPrevisto: 350 });
await dDona.inserir('agendamento_servicos', { agendamentoId: AG.id, servicoId: SV.id,
  ordem:1, duracaoMin:120, preco:350, comissaoPct:40 });

const COMO = 'Tinta 9.1 + 0.11 com ox 20 volumes, 35 minutos.\nLavar com shampoo sem sulfato e finalizar com máscara matizadora.';
const LEMBRETE = 'Prefere pagar no Pix e pede para dividir.';

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrirPainel(dados, rotulo){
  const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(rotulo + ': ' + e.message));
  p.on('dialog', d => { erros.push(rotulo + ' (alerta): ' + d.message()); d.accept(); });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dados.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.profissionais.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  return { ctx, p };
}
const lembreteNoBanco = id => um(`select marcas, texto from public.clientes_lembretes where cliente_id=$1`, [id]);

/* ══════════════════════════════════════════════════════════════════════════
   1 — A DONA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. A dona: o como fazer do serviço e os lembretes da Maria');
{
  const { ctx, p } = await abrirPainel(dDona, 'dona');
  await p.evaluate(id => { irPara('servicos'); abrirServico(id); }, SV.id);
  await p.waitForSelector('#sProc');
  verdade('o serviço tem o campo "Como fazer", dizendo que só a equipe vê',
    /Como fazer\s*·\s*só a equipe vê/.test(await p.evaluate(() =>
      document.querySelector('label[for="sProc"]').textContent.replace(/\s+/g, ' '))));
  await p.fill('#sProc', COMO);
  await p.evaluate(id => salvarServico(id), SV.id);
  await p.waitForTimeout(1800);
  igual('salvar grava o como fazer no serviço',
    (await um(`select procedimento from public.servicos where id=$1`, [SV.id])).procedimento, COMO);

  await p.evaluate(id => { irPara('clientes'); abrirCliente(id); }, CLI.id);
  await p.waitForSelector('#kMarcas');
  const opcoes = await p.evaluate(() => [...document.querySelectorAll('#kMarcas button')]
    .map(b => [b.textContent.trim(), b.getAttribute('aria-pressed')]));
  igual('o cadastro oferece as marcas prontas, nenhuma marcada',
    opcoes, [['Prefere não conversar','false'], ['Gosta de conversar','false'],
             ['Atenção no pagamento','false'], ['Costuma atrasar','false'],
             ['Exigente com o resultado','false']]);
  verdade('e diz que a cliente não vê',
    /Lembretes da equipe\s*·\s*a cliente não vê/.test(await p.evaluate(() =>
      document.getElementById('kMarcas').closest('.campo').querySelector('label').textContent.replace(/\s+/g, ' '))));
  await p.click('#kMarcas button:has-text("Prefere não conversar")');
  await p.click('#kMarcas button:has-text("Atenção no pagamento")');
  await p.fill('#kLembrete', LEMBRETE);
  await p.evaluate(id => salvarCliente(id), CLI.id);
  await p.waitForTimeout(1800);
  igual('salvar grava o lembrete, à parte da ficha',
    await lembreteNoBanco(CLI.id), { marcas:['Prefere não conversar', 'Atenção no pagamento'], texto: LEMBRETE });
  const obs = (await um(`select obs from public.clientes where id=$1`, [CLI.id])).obs || '';
  verdade('e nada dele vai para a ficha que a cliente lê (o obs)',
    !obs.includes('Pix') && !obs.includes('pagamento'), obs);
  const lista = await p.evaluate(() => document.body.innerText);
  verdade('a lista de clientes mostra as marcas da Maria',
    lista.includes('Prefere não conversar · Atenção no pagamento'));

  // Cliente nova, já com marca: a ficha e o lembrete sobem juntos.
  await p.evaluate(() => abrirCliente(null));
  await p.waitForSelector('#kMarcas');
  await p.fill('#kNome', 'Joana Nova');
  await p.click('#kMarcas button:has-text("Costuma atrasar")');
  await p.evaluate(() => salvarCliente(null));
  await p.waitForTimeout(1800);
  const joana = await um(`select c.id, l.marcas from public.clientes c
    left join public.clientes_lembretes l on l.cliente_id = c.id
    where c.salao_id=$1 and c.nome='Joana Nova'`, [SALAO]);
  igual('cliente nova nasce com o lembrete, na mesma gravação',
    joana && joana.marcas, ['Costuma atrasar']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — A PROFISSIONAL
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. A Bia (profissional, outro login) abre o horário da Maria');
{
  const { ctx, p } = await abrirPainel(dBia, 'bia');
  igual('o lembrete desceu para ela', await p.evaluate(() => (bd.clientes_lembretes || []).length >= 1), true);
  await p.evaluate(id => abrirDetalhe(id), AG.id);
  await p.waitForTimeout(500);
  const det = await p.evaluate(() => {
    const m = document.querySelector('.modal');
    const d = m.querySelector('details.como-fazer');
    return { txt: m.innerText.replace(/\s+/g, ' '),
             aviso: (m.querySelector('.lembrete-aviso') || {}).innerText || '',
             aberto: !!(d && d.open), resumo: d ? d.querySelector('summary').textContent.trim() : '',
             como: d ? d.querySelector('.como-fazer-txt').innerText : '' };
  });
  verdade('vê o lembrete sobre a Maria, dizendo que só a equipe vê',
    /Lembrete sobre Maria Lima/.test(det.aviso) && /só a equipe vê/.test(det.aviso), det.aviso);
  verdade('com as duas marcas e o texto',
    det.aviso.includes('Prefere não conversar') && det.aviso.includes('Atenção no pagamento')
    && det.aviso.includes(LEMBRETE), det.aviso);
  verdade('e o como fazer do serviço, já aberto', det.aberto
    && det.resumo === 'Como fazer · Coloração loiro perolado', JSON.stringify(det.resumo));
  igual('com o texto inteiro, com a quebra de linha', det.como, COMO);
  const cartao = await p.evaluate(id => cartaoDoDia(bd.agendamentos.find(a => a.id === id)), AG.id);
  verdade('o cartão do dia mostra as marcas da cliente',
    /class="dc-lembrete">Prefere não conversar · Atenção no pagamento</.test(cartao), cartao);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — DESMARCAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. Desmarcar tudo apaga o lembrete');
{
  const { ctx, p } = await abrirPainel(dDona, 'dona');
  await p.evaluate(id => { irPara('clientes'); abrirCliente(id); }, CLI.id);
  await p.waitForSelector('#kMarcas');
  igual('ao voltar, as marcas vêm marcadas e o texto preenchido',
    await p.evaluate(() => ({ on: [...document.querySelectorAll('#kMarcas button.on')].map(b => b.textContent.trim()),
                              txt: document.getElementById('kLembrete').value })),
    { on: ['Prefere não conversar', 'Atenção no pagamento'], txt: LEMBRETE });
  await p.click('#kMarcas button:has-text("Prefere não conversar")');
  await p.click('#kMarcas button:has-text("Atenção no pagamento")');
  await p.fill('#kLembrete', '');
  await p.evaluate(id => salvarCliente(id), CLI.id);
  await p.waitForTimeout(1800);
  igual('sem marca e sem texto, a linha sai do banco', await lembreteNoBanco(CLI.id), null);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — O LINK DA CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. O link da cliente não recebe nada disso');
{
  await banco.query(`insert into public.clientes_lembretes (salao_id, cliente_id, marcas, texto)
                     values ($1, $2, array['Atenção no pagamento'], 'segredo da equipe')`, [SALAO, CLI.id]);
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  const respostas = [];
  p.on('response', async r => { if(/\/rest\/v1\//.test(r.url())) respostas.push(await r.text().catch(() => '')); });
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(1500);
  const tudo = respostas.join('\n') + (await p.content());
  verdade('o link mostra o serviço', tudo.includes('Coloração loiro perolado'));
  verdade('mas o como fazer não chega nem na resposta do servidor',
    !tudo.includes('ox 20 volumes') && !tudo.includes('procedimento'));
  verdade('nem o lembrete', !tudo.includes('segredo da equipe') && !tudo.includes('Atenção no pagamento'));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — PROCEDIMENTOS
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. Procedimentos: o tópico próprio');
const PASSOS = '1. Separar o cabelo em mechas finas\n2. Aplicar o descolorante\n\n- Enxaguar e tonalizar';
{
  const { ctx, p } = await abrirPainel(dDona, 'dona');
  igual('a dona vê a aba Procedimentos, logo depois de Serviços',
    await p.evaluate(() => { const k = [...document.querySelectorAll('#abas .aba')].map(b => b.dataset.chave);
      return k[k.indexOf('servicos') + 1]; }), 'procedimentos');
  await p.evaluate(() => irPara('procedimentos'));
  await p.waitForTimeout(300);
  verdade('vazia, explica para que serve', /Nenhum procedimento ainda/.test(await p.textContent('#listaProcedimentos')));
  for(const [nome, prod, passos] of [['Morena iluminada', 'Pó descolorante; ox 20 volumes', PASSOS],
                                     ['Loiro perolado', 'Tonalizante perolado', 'Lavar\nTonalizar']]){
    await p.click('#btNovoProc');
    await p.waitForSelector('#prNome');
    await p.fill('#prNome', nome);
    await p.selectOption('#prServico', SV.id);
    await p.fill('#prProdutos', prod);
    await p.fill('#prPassos', passos);
    await p.evaluate(() => salvarProcedimento(null));
    await p.waitForTimeout(1500);
  }
  const noBanco = (await banco.query(`select nome, servico_id, produtos, passos from public.procedimentos
    where salao_id=$1 order by nome`, [SALAO])).rows;
  igual('os dois foram para o banco, ligados à Coloração',
    noBanco.map(r => [r.nome, r.servico_id]), [['Loiro perolado', SV.id], ['Morena iluminada', SV.id]]);
  igual('com o passo a passo como foi digitado', noBanco[1].passos, PASSOS);
  igual('a lista mostra os dois cartões, em ordem de nome',
    await p.evaluate(() => [...document.querySelectorAll('.proc-cartao .proc-nome')].map(b => b.textContent)),
    ['Loiro perolado', 'Morena iluminada']);
  await p.fill('#buscaProc', 'descolor');
  igual('a busca acha também pelo produto',
    await p.evaluate(() => [...document.querySelectorAll('.proc-cartao .proc-nome')].map(b => b.textContent)),
    ['Morena iluminada']);
  await p.fill('#buscaProc', '');
  await p.evaluate(id => { irPara('servicos'); abrirServico(id); }, SV.id);
  await p.waitForSelector('#sProc');
  verdade('o cadastro do serviço diz quais procedimentos estão nele',
    /Procedimentos deste serviço:\s*Loiro perolado, Morena iluminada/.test(
      await p.evaluate(() => document.querySelector('.modal').innerText)));
  await ctx.close();
}
{
  const { ctx, p } = await abrirPainel(dBia, 'bia');
  await p.evaluate(() => irPara('procedimentos'));
  await p.waitForTimeout(300);
  igual('a Bia vê a aba e os dois procedimentos',
    await p.evaluate(() => [telaAtual, document.querySelectorAll('.proc-cartao').length]), ['procedimentos', 2]);
  verdade('mas sem o botão de criar', !(await p.isVisible('#btNovoProc')));
  await p.click('.proc-cartao:has-text("Morena iluminada")');
  await p.waitForTimeout(300);
  const ver = await p.evaluate(() => ({
    passos: [...document.querySelectorAll('.modal .proc-passos li')].map(l => l.textContent),
    botoes: [...document.querySelectorAll('.modal button')].map(b => b.textContent.trim()) }));
  igual('o passo a passo vem numerado, sem o número e o traço digitados',
    ver.passos, ['Separar o cabelo em mechas finas', 'Aplicar o descolorante', 'Enxaguar e tonalizar']);
  verdade('e sem o botão Editar para ela', !ver.botoes.includes('Editar'), JSON.stringify(ver.botoes));
  await p.evaluate(id => { fecharModal(); abrirDetalhe(id); }, AG.id);
  await p.waitForTimeout(400);
  const det = await p.evaluate(() => [...document.querySelectorAll('.modal details.proc-detalhe')]
    .map(d => [d.querySelector('summary').textContent.trim(), d.open]));
  igual('no horário da Maria (Coloração), os dois procedimentos, fechados para ela escolher',
    det, [['Procedimento · Loiro perolado', false], ['Procedimento · Morena iluminada', false]]);
  verdade('e o como fazer do serviço continua lá',
    await p.evaluate(() => !!document.querySelector('.modal details.como-fazer:not(.proc-detalhe)')));
  await ctx.close();
}
{
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  const respostas = [];
  p.on('response', async r => { if(/\/rest\/v1\//.test(r.url())) respostas.push(await r.text().catch(() => '')); });
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(1500);
  const tudo = respostas.join('\n') + (await p.content());
  verdade('o link não recebe os procedimentos',
    !tudo.includes('Morena iluminada') && !tudo.includes('Tonalizante perolado'));
  await ctx.close();
}

verdade('sem erro de JavaScript nem alerta', erros.length === 0, erros.join(' | '));
await nav.close();
await banco.end();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam`);
process.exit(falhou ? 1 : 0);
