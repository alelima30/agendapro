/* ===========================================================================
   AgendaPro — o que o caça-bug achou na TELA, e que não volta

     bash tests/bancada/subir.sh                       (noutro terminal)
     python3 -m http.server 8099 --directory .         (a parte da demonstração)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/caca-bug.test.mjs

   Os defeitos de banco moram no tests/caca_bug.test.sql. Aqui, os de tela:

   ── O LINK DA CLIENTE ─────────────────────────────────────────────────────
     1. a "capa" do salão não roda código no navegador de quem abre o link;
     2. salão que não existe não mostra o texto da demonstração;
     3. "+55 51 99999-8888" vira (51) 99999-8888, e não um número errado;
     4. a faixa de dias tem os mesmos dias que o aviso promete; dia fechado é
        "fechado", e não "cheio" com lista de espera;
     5. "eu e mais alguém" mostra o preço dos dois;
     6. remarcar e desistir NÃO cancela outro horário;
     7. remarcar leva o cupom junto, e a tela diz isso;
     8. sair da conta limpa o cadastro da tela;
     9. a loja acha sem acento, e reenviar o pedido corrigido não gasta outro
        uso do cupom; cupom na loja só dentro da conta;
    9b. "eu e mais alguém" com pacote: o horário dela sai pelo pacote, o da
        acompanhante é cobrado à parte — na tela e no banco.
   ── O PAINEL ──────────────────────────────────────────────────────────────
    10. a tela Hoje usa o cartão do mês (nome, status, serviço, valor);
    11. tirar um item da comanda com a rede lenta tira do banco também;
    12. o Dashboard não mostra os números de outro salão;
    13. (demonstração) regra de preço nova grava; exceções de quem está
        inativo ficam; cupom com serviço desativado não vira "todos"; pacote
        conta pelo dia de hoje; busca de cliente sem acento e por telefone;
        bloqueio se remove; a profissional marca só para si; a recepção não
        vê a comissão das colegas; a comanda entra no dia em que fechou; o
        link da demonstração continua na demonstração; o passo a passo
        preenche o horário de funcionamento; sessão de pacote sai por zero.
    14. nenhum erro de JavaScript.
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
const ESTATICO = process.env.BASE || 'http://127.0.0.1:8099/';

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
const um = r => Array.isArray(r) ? r[0] : r;
const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const n7 = String(Date.now() % 10000000).padStart(7, '0');
const tel = k => '51' + k + n7;
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;
const diaMais = d => { const x = new Date(); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); };
const espaco = t => String(t || '').replace(/\s/g, ' ');

// ── O salão: segunda a sábado, domingo FECHADO ─────────────────────────────
const dona = aba();
await dona.criarConta({ email:`cb-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Caça', p_tipo:'salao',
  p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 1; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const corte = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte', duracaoMin:30, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:30, intervaloMin:0,
  preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const mascara = await dona.inserir('produtos', { salaoId: SALAO, nome:"Máscara d'Ouro", preco:40, ativo:true,
  vendaOnline:true, precoVisivel:true, estoque:20 });
const oleo = await dona.inserir('produtos', { salaoId: SALAO, nome:'Óleo Argan', preco:30, ativo:true,
  vendaOnline:true, precoVisivel:true, estoque:20 });
const FUNC = { 0: [], 1: [['08:00','19:00']], 2: [['08:00','19:00']], 3: [['08:00','19:00']],
               4: [['08:00','19:00']], 5: [['08:00','19:00']], 6: [['08:00','19:00']] };
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: FUNC, confirmaAuto:true } });
await dona.inserir('cupons', { salaoId: SALAO, codigo:'BEM10', tipo:'pct', valor:10, valeAgendamento:true,
  valeProdutos:false, umPorCliente:true, ativo:true });
await dona.inserir('cupons', { salaoId: SALAO, codigo:'LOJA10', tipo:'pct', valor:10, valeAgendamento:false,
  valeProdutos:true, umPorCliente:false, ativo:true });
const agendamentos = () => dona.lista('agendamentos', { salaoId: SALAO });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

async function abrirLink(slug){
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + (slug || SLUG));
  await p.waitForFunction(() => typeof tela !== 'undefined' && (tela === 'capa' || tela === 'saloes'), null, { timeout: 15000 });
  await p.waitForTimeout(700);
  return { ctx, p };
}
// Da capa (ou de Meus horários) até a tela de confirmar, num dia útil.
async function ateConfirmar(p, nome, telefone, servico, nDia){
  if(await p.evaluate(() => tela === 'capa')){ await p.click('.boas-cta'); await p.waitForTimeout(300); }
  await p.click(`#listaServicos .sv-cartao:has-text("${servico || 'Corte'}")`); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  if(await p.evaluate(() => tela === 'quem')){ await p.click('#quemMim'); await p.waitForTimeout(500); }
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(nDia || 3).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  if(await p.isVisible('#dNome')) await p.fill('#dNome', nome);
  if(await p.isVisible('#dTel')) await p.fill('#dTel', masc(telefone));
  if(await p.isVisible('#dNasc')) await p.fill('#dNasc', '1990-01-01');
  if(await p.isVisible('#dEmail')) await p.fill('#dEmail', `x-${telefone}@t.com`);
  if(await p.evaluate(() => tela === 'dados')){ await p.click('#btPrincipal'); await p.waitForTimeout(1200); }
}
const totalNaTela = p => p.evaluate(() => ((document.querySelector('#resumoFinal .cf-total b') || {}).textContent || '').replace(/\s/g, ' '));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A capa não vira código');
{
  await dona.atualizar('saloes', SALAO, { capa: `https://x.y/c.jpg');"><img src=x onerror="window.__xss=document.domain">` });
  const { ctx, p } = await abrirLink();
  await p.waitForTimeout(800);
  const r = await p.evaluate(() => ({ xss: window.__xss || null,
    img: !!document.querySelector('#capaMarca img[src="x"]'),
    fundo: (document.querySelector('.hero-foto') || {}).style ? document.querySelector('.hero-foto').style.backgroundImage : '' }));
  igual('a "capa" gravada pela API com HTML dentro não roda nada', [r.xss, r.img], [null, false]);
  verdade('as aspas viram %27 dentro do url()', /%27/.test(r.fundo), r.fundo);
  await dona.atualizar('saloes', SALAO, { capa: null });
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Salão que não existe');
{
  const { ctx, p } = await abrirLink('salao-que-nao-existe-' + m);
  const r = await p.evaluate(() => ({ tela,
    titulo: getComputedStyle(document.querySelector('#p-saloes > h2')).display,
    sub: getComputedStyle(document.querySelector('#p-saloes > .sub')).display,
    recado: document.getElementById('listaSaloes').innerText.trim().length > 0 }));
  igual('mostra só o recado, sem o "Qual salão? … demonstração"', [r.tela, r.titulo, r.sub, r.recado], ['saloes', 'none', 'none', true]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3 a 5. Telefone, dias e "eu e mais alguém"');
const TEL_A = tel('81');
{
  const { ctx, p } = await abrirLink();
  igual('"+55 51 99999-8888" vira (51) 99999-8888', await p.evaluate(() => {
    const el = document.createElement('input'); el.value = '+55 51 99999-8888'; mascaraTelefone(el); return el.value; }),
    '(51) 99999-8888');
  await ateConfirmar(p, 'Ana Lima', TEL_A);
  igual('a faixa tem os 30 dias liberados (31 botões), o mesmo do aviso',
    await p.evaluate(() => [diasNaTela(), ultimoDiaLiberado() === somarDias(hoje(), 30)]), [30, true]);
  const total1 = await totalNaTela(p);
  const ambos = await p.evaluate(() => { escolha.para = 'ambos'; desenharConfirmar();
    const t = ((document.querySelector('#resumoFinal .cf-total b') || {}).textContent || '').replace(/\s/g, ' ');
    escolha.para = 'mim'; desenharConfirmar(); return t; });
  igual('"eu e mais alguém" soma os dois atendimentos (R$ 80 → R$ 160)', [total1, ambos], ['R$ 80,00', 'R$ 160,00']);
  // Volta aos horários para conferir o domingo.
  await p.evaluate(() => irPara('quando')); await p.waitForTimeout(600);
  const dom = await p.evaluate(() => [...document.querySelectorAll('#listaDias .dia')]
    .filter(b => /^dom$/i.test(b.querySelector('small').textContent)).map(b => b.querySelector('i').textContent));
  verdade('domingo, que o salão não abre, aparece como "fechado"', dom.length && dom.every(t => t === 'fechado'), JSON.stringify(dom));
  await p.evaluate(() => { const b = [...document.querySelectorAll('#listaDias .dia')].find(x => /^dom$/i.test(x.querySelector('small').textContent)); b.click(); });
  await p.waitForTimeout(500);
  igual('e tocando nele: "Fechado neste dia", sem lista de espera',
    await p.evaluate(() => [(document.querySelector('#listaHoras .nada b') || {}).textContent || '',
                            !!document.querySelector('#areaEspera .espera')]), ['Fechado neste dia', false]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Remarcar e desistir não cancela outro horário');
const TEL_B = tel('82');
{
  const { ctx, p } = await abrirLink();
  await ateConfirmar(p, 'Bia Souza', TEL_B, 'Corte', 2);
  await p.click('#btPrincipal'); await p.waitForTimeout(3000);
  igual('marcou o Corte', await p.evaluate(() => tela), 'pronto');
  const primeiro = await p.evaluate(() => lerTokens().agendamentos[0]);
  await p.evaluate(() => abrirMeus());
  await p.waitForFunction(() => meusDaNuvem && meusDaNuvem.ags && meusDaNuvem.ags.length, null, { timeout: 10000 });
  await p.evaluate(t => remarcarNaNuvem(t), primeiro); await p.waitForTimeout(500);
  verdade('Remarcar leva aos horários com a marca da remarcação', await p.evaluate(() => tela === 'quando' && !!escolha.remarcar));
  // Desiste: volta à capa e começa uma marcação nova pelo botão de lá — o
  // caminho que NÃO zera a escolha (o de "Meus horários" zera por conta própria).
  await p.evaluate(() => irPara('capa')); await p.waitForTimeout(500);
  await p.click('.boas-cta'); await p.waitForTimeout(500);
  verdade('a marcação nova começa sem a marca', await p.evaluate(() => tela === 'servico' && !escolha.remarcar));
  await ateConfirmar(p, 'Bia Souza', TEL_B, 'Escova', 4);
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const st = (await agendamentos()).filter(a => a.status !== 'cancelado').length;
  igual('os DOIS horários continuam marcados (o Corte não foi cancelado)', [await p.evaluate(() => tela), st >= 2], ['pronto', true]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7 e 8. Remarcar leva o cupom; sair limpa o cadastro');
const TEL_C = tel('83');
{
  const { ctx, p } = await abrirLink();
  await ateConfirmar(p, 'Cau Reis', TEL_C, 'Corte', 2);
  await p.click('#cfCupomCaixa summary'); await p.fill('#cupomAgendaTxt', 'bem10');
  await p.click('#cfCupomCaixa .cupom-aplicar'); await p.waitForTimeout(1200);
  igual('com o BEM10 o Corte fica R$ 72', await totalNaTela(p), 'R$ 72,00');
  await p.click('#btPrincipal'); await p.waitForTimeout(3000);
  const antigo = await p.evaluate(() => lerTokens().agendamentos.slice(-1)[0]);
  await p.evaluate(() => abrirMeus());
  await p.waitForFunction(() => meusDaNuvem && meusDaNuvem.ags && meusDaNuvem.ags.length, null, { timeout: 10000 });
  await p.evaluate(t => remarcarNaNuvem(t), antigo); await p.waitForTimeout(1500);
  await p.locator('#listaDias .dia:not(.sem)').nth(5).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  if(await p.evaluate(() => tela === 'dados')){ await p.click('#btPrincipal'); await p.waitForTimeout(1200); }
  const conf = await p.evaluate(() => ({ tela, campo: !!document.getElementById('cfCupomCaixa'),
    linha: [...document.querySelectorAll('#resumoFinal .cf-linha small')].map(s => s.textContent) }));
  verdade('a confirmação diz que o cupom do horário antigo vai junto, e não pede cupom de novo',
    conf.tela === 'confirmar' && !conf.campo && conf.linha.includes('Cupom do horário antigo (vai junto)'), JSON.stringify(conf));
  igual('e o total já sai com o desconto (R$ 72,00)', await totalNaTela(p), 'R$ 72,00');
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const lista = await agendamentos();
  const velho = lista.find(a => a.cancelado_motivo === 'remarcado pelo cliente' || a.canceladoMotivo === 'remarcado pelo cliente');
  const novo = lista.find(a => a.status !== 'cancelado' && Number(a.desconto) === 8);
  verdade('no banco: o antigo saiu como "remarcado pelo cliente" e o novo tem os R$ 8 de desconto',
    !!velho && !!novo && Number(novo.valorPrevisto) === 72, JSON.stringify(lista.map(a => [a.status, a.desconto, a.valorPrevisto, a.canceladoMotivo])));

  // Sair limpa o que ficou digitado.
  const limpo = await p.evaluate(async () => {
    document.getElementById('dNome').value = 'Cau Reis'; document.getElementById('dTel').value = '(51) 98888-7777';
    window.confirm = () => true; await sair();
    return ['dNome', 'dTel', 'dEmail'].map(id => (document.getElementById(id) || {}).value || '');
  });
  igual('"Sair" deixa o cadastro em branco para a próxima pessoa', limpo, ['', '', '']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('9. A loja: sem acento, e o pedido corrigido não gasta outro uso');
{
  const { ctx, p } = await abrirLink();
  const busca = async t => p.evaluate(q => { document.getElementById('buscaProduto').value = q; desenharLoja();
    return document.getElementById('listaProdutos').innerText; }, t);
  await p.evaluate(() => irPara('loja')); await p.waitForTimeout(400);
  verdade('"mascara" acha a Máscara, "oleo" acha o Óleo',
    /Máscara/.test(await busca('mascara')) && /Óleo/.test(await busca('oleo')));
  await busca('');
  await p.evaluate(id => { window.__abertos = []; window.open = u => { window.__abertos.push(u); return null; };
    mudarNoCarrinho(id, 1); }, mascara.id);
  await p.waitForTimeout(400);
  // Cupom na loja só dentro da conta: cria a conta pela própria caixa do cupom.
  await p.click('#lojaCupomCaixa summary');
  await p.click('#lojaCupomCaixa button:has-text("Criar conta")'); await p.waitForTimeout(300);
  await p.fill('#cNome', 'Dri Loja'); await p.fill('#cTel', masc(tel('85')));
  await p.fill('#cEmail', `dri-${m}@t.com`); await p.fill('#cSenha', 'senhadadri1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  if(!(await p.isVisible('#cupomLojaTxt'))) await p.click('#lojaCupomCaixa summary');
  await p.fill('#cupomLojaTxt', 'loja10');
  await p.click('#lojaCupomCaixa .cupom-aplicar'); await p.waitForTimeout(1200);
  await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  const usos = async () => (um(await dona.chamar('usos_dos_cupons', { p_salao: SALAO })) || {});
  const cupons = await dona.lista('cupons', { salaoId: SALAO });
  const LOJA10 = cupons.find(c => c.codigo === 'LOJA10');
  igual('enviou: 1 uso registrado', (await usos())[LOJA10.id], 1);
  await p.evaluate(id => mudarNoCarrinho(id, 1), oleo.id); await p.waitForTimeout(1200);
  await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  const msg = decodeURIComponent((await p.evaluate(() => window.__abertos.slice(-1)[0] || '')).split('?text=')[1] || '');
  igual('corrigiu o pedido e mandou de novo: continua 1 uso', (await usos())[LOJA10.id], 1);
  verdade('e a mensagem nova ainda leva o cupom', /Cupom LOJA10/.test(msg), msg);
  await ctx.close();

  // Por fora do link, direto no banco: sem conta não gasta; com conta, chamar
  // em repetição no mesmo dia gasta UM uso só.
  const itens = [{ id: oleo.id, qtd: 1 }];
  const semConta = um(await aba().chamar('usar_cupom_no_pedido', { p_salao: SALAO, p_codigo: 'LOJA10', p_itens: itens }));
  igual('sem conta, o pedido da loja não usa o cupom', [semConta.ok, semConta.entrar, (await usos())[LOJA10.id]], [false, true, 1]);
  const insistente = aba();
  await insistente.criarConta({ email:`ins-${m}@t.com`, senha:'senhainsistente1', nome:'Ivo Insiste',
    telefone:'+55' + tel('87') });
  for(let i = 0; i < 4; i++)
    await insistente.chamar('usar_cupom_no_pedido', { p_salao: SALAO, p_codigo: 'LOJA10', p_itens: itens });
  igual('a mesma conta chamando 4 vezes gasta 1 uso (não esgota o cupom)', (await usos())[LOJA10.id], 2);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('9b. "Eu e mais alguém" com pacote: a acompanhante paga à parte');
{
  const TEL_L = tel('86');
  const lia = aba();
  await lia.criarConta({ email:`lia-${m}@t.com`, senha:'senhadalia1', nome:'Lia Pacote', telefone:'+55' + TEL_L });
  const anon2 = aba();
  const livres = async d => {
    const h = await anon2.chamar('horarios_livres', { p_profissional: prof.id, p_data: diaMais(d), p_servicos: [corte.id] });
    return (Array.isArray(h) ? h : []).map(x => typeof x === 'string' ? x : Object.values(x)[0]);
  };
  let d0 = 9; while(!(await livres(d0)).length) d0++;
  // A ficha nasce da primeira marcação (com a conta), como na vida real.
  const primeira = um(await lia.chamar('agendar', { p_profissional: prof.id, p_inicio: (await livres(d0))[0],
    p_servicos: [corte.id], p_nome: 'Lia Pacote', p_telefone: TEL_L }));
  await dona.atualizar('agendamentos', primeira.id, { status: 'cancelado' });
  const ficha = (await dona.lista('clientes', { salaoId: SALAO })).find(c => c.telefone === TEL_L);
  const pac = await dona.inserir('pacotes', { salaoId: SALAO, nome:'4 Cortes', preco:240, sessoes:4,
    validadeDias:90, dias:[0,1,2,3,4,5,6], ativo:true });
  await dona.inserir('pacote_servicos', { pacoteId: pac.id, servicoId: corte.id });
  await dona.chamar('vender_pacote', { p_pacote: pac.id, p_cliente: ficha.id });

  const { ctx, p } = await abrirLink();
  await p.evaluate(() => abrirConta('entrar')); await p.waitForTimeout(300);
  await p.fill('#cEmail', `lia-${m}@t.com`); await p.fill('#cSenha', 'senhadalia1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  verdade('entrou na conta, e o pacote apareceu', await p.evaluate(() => logada() && meusPacotes.length === 1));
  if(await p.evaluate(() => tela !== 'capa')) await p.evaluate(() => irPara('capa'));
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao:has-text("Corte")'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemOutra'); await p.waitForTimeout(300);
  await p.evaluate(() => escolherRelacao('outra'));
  await p.fill('#fAtendido', 'Bia Amiga'); await p.check('#fJunto');
  await p.click('#btPrincipal'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(4).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(900);
  if(await p.evaluate(() => tela === 'dados')){
    if(await p.isVisible('#dNasc') && !(await p.inputValue('#dNasc'))) await p.fill('#dNasc', '1990-01-01');
    if(await p.isVisible('#dEmail') && !(await p.inputValue('#dEmail'))) await p.fill('#dEmail', `lia-${m}@t.com`);
    await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  }
  const conf = await p.evaluate(() => ({ tela, para: escolha.para,
    total: ((document.querySelector('#resumoFinal .cf-total b') || {}).textContent || '').replace(/\s/g, ' '),
    aviso: ((document.querySelector('#resumoFinal .recado.ok') || {}).textContent || '').replace(/\s+/g, ' ') }));
  igual('o total é o da acompanhante (R$ 80,00), e não R$ 0,00 para as duas', [conf.tela, conf.para, conf.total],
    ['confirmar', 'ambos', 'R$ 80,00']);
  verdade('e a tela diz: o seu no pacote, o da Bia cobrado à parte',
    /O seu horário está no seu pacote/.test(conf.aviso) && /Bia Amiga é cobrado à parte/.test(conf.aviso), conf.aviso);
  await p.click('#btPrincipal'); await p.waitForTimeout(4000);
  const dela = (await dona.lista('agendamentos', { salaoId: SALAO }))
    .filter(a => a.clienteId === ficha.id && a.status !== 'cancelado')
    .sort((a, b) => String(a.inicio).localeCompare(String(b.inicio)));
  igual('no banco: o dela por R$ 0 no pacote, o da Bia por R$ 80 fora dele',
    [await p.evaluate(() => tela), dela.map(a => [Number(a.valorPrevisto), !!a.pacoteClienteId, a.atendidoNome || null])],
    ['pronto', [[0, true, null], [80, false, 'Bia Amiga']]]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('10 a 12. O painel na nuvem');
{
  // Um horário de HOJE, mais tarde (se ainda houver vaga hoje).
  const anon = aba();
  const hojeSalao = new Intl.DateTimeFormat('en-CA', { timeZone:'America/Sao_Paulo' }).format(new Date());
  const h = await anon.chamar('horarios_livres', { p_profissional: prof.id, p_data: hojeSalao, p_servicos: [corte.id] }).catch(() => []);
  const vagaHoje = (Array.isArray(h) ? h : []).map(x => typeof x === 'string' ? x : Object.values(x)[0])[0];
  if(vagaHoje) await anon.chamar('agendar', { p_profissional: prof.id, p_inicio: vagaHoje, p_servicos: [corte.id],
    p_nome: 'Hoje Ainda Vem', p_telefone: tel('84') });

  const ctx = await nav.newContext({ viewport:{ width:390, height:880 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => d.dismiss());
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.agendamentos), null, { timeout: 20000 });
  await p.waitForTimeout(900);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });

  if(vagaHoje){
    await p.evaluate(() => irPara('hoje')); await p.waitForTimeout(2500);
    const hoje = await p.evaluate(() => [...document.querySelectorAll('#hojeCorpo .dia-cartao')].map(x => x.innerText.replace(/\s+/g, ' ')));
    verdade('Hoje → "Quem ainda vem" com o cartão do mês: nome, status, serviço e valor',
      hoje.some(t => /Hoje Ainda Vem/.test(t) && /Corte/.test(t) && /R\$\s?80,00/.test(t) && /Confirmado|A confirmar/.test(t)), JSON.stringify(hoje));
  } else ok('sem vaga hoje a esta hora — a tela Hoje fica para a suíte de amanhã');

  // Dashboard: trocar de salão pede os números de novo.
  const pedidos = await p.evaluate(async () => {
    const orig = Dados.chamar; let n = 0;
    Dados.chamar = (f, a) => { if(f === 'painel_grafico') n++; return orig(f, a); };
    irPara('dashboard'); await new Promise(r => setTimeout(r, 1500));
    const aberto = n; await carregarDash(); const mesmo = n - aberto;
    const antes = salaoAtual; salaoAtual = '00000000-0000-4000-8000-000000000000';
    await carregarDash().catch(() => {}); const outro = n - aberto;
    salaoAtual = antes; Dados.chamar = orig;
    return [mesmo, outro];
  });
  igual('Dashboard: o mesmo salão não pergunta de novo, outro salão pergunta', pedidos, [0, 1]);

  // Comanda com a rede lenta: somar, tirar, somar.
  const ag = (await agendamentos())[0];
  await p.evaluate(async id => { await comandaDoAgendamento(id); }, ag.id); await p.waitForTimeout(2500);
  await p.route('**/rest/v1/**', async r => { if(r.request().method() !== 'GET') await new Promise(x => setTimeout(x, 400)); r.continue(); });
  await p.selectOption('#cItem', 'p:' + mascara.id); await p.click('button:has-text("+ Somar à comanda")');
  await p.waitForTimeout(150);
  await p.click('#modalCorpo tbody tr:nth-child(2) button[aria-label="Remover"]');
  await p.waitForTimeout(150);
  await p.selectOption('#cItem', 's:' + escova.id); await p.click('button:has-text("+ Somar à comanda")');
  await p.waitForTimeout(4000);
  await p.waitForFunction(() => !_gravando, null, { timeout: 15000 }).catch(() => {});
  await p.unroute('**/rest/v1/**');
  const tela = await p.evaluate(id => (bd.comandas.find(c => c.agendamentoId === id) || { itens: [] }).itens.map(i => i.descricao).sort(), ag.id);
  const cmd = (await dona.lista('comandas', { salaoId: SALAO })).find(c => c.agendamentoId === ag.id);
  const noBanco = cmd ? (await dona.lista('comanda_itens', { comandaId: cmd.id })).map(i => i.descricao).sort() : [];
  igual('rede lenta: o banco fica com exatamente o que a tela mostra', noBanco, tela);
  verdade('e a Máscara tirada não ficou no banco', !noBanco.includes("Máscara d'Ouro"), JSON.stringify(noBanco));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('13. O painel na demonstração');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('demo: ' + e.message));
  p.on('dialog', d => d.type() === 'confirm' ? d.accept() : d.dismiss());
  await p.goto(ESTATICO + 'app.html?demo=1');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.agendamentos), null, { timeout: 15000 });
  await p.waitForTimeout(600);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} });

  const regra = await p.evaluate(() => {
    const sv = servsAtivos()[0]; const antes = (bd.precos_regras || []).length;
    abrirServico(sv.id); abrirRegraDePreco(sv.id, null);
    document.getElementById('rgPreco').value = '99';
    salvarRegraDePreco(sv.id, null);
    const titulo = document.getElementById('modalTitulo').textContent; fecharModal();
    return [(bd.precos_regras || []).length - antes, titulo];
  });
  igual('"+ Nova regra de preço" grava, e volta ao serviço que estava aberto', regra, [1, 'Editar serviço']);

  const pares = await p.evaluate(() => {
    const sv = servsAtivos()[0]; const inativa = doSalao(bd.profissionais)[0];
    inativa.ativo = false;
    bd.servicos_profissionais = (bd.servicos_profissionais || []).filter(x => !(x.servicoId === sv.id && x.profissionalId === inativa.id));
    bd.servicos_profissionais.push({ id: id(), servicoId: sv.id, profissionalId: inativa.id, preco: 150, duracaoMin: null, comissaoPct: 60, comissaoFixa: null });
    abrirServico(sv.id); guardarParesDoServico(sv.id); fecharModal();
    const fica = bd.servicos_profissionais.some(x => x.servicoId === sv.id && x.profissionalId === inativa.id && x.preco === 150);
    inativa.ativo = true; return fica;
  });
  verdade('editar o serviço não apaga o preço especial de quem está inativa', pares);

  const cupom = await p.evaluate(() => {
    const sv = servsAtivos()[0];
    const c = { id: id(), salaoId: salaoAtual, codigo: 'SO' + Date.now() % 10000, tipo: 'valor', valor: 15,
                valeAgendamento: true, valeProdutos: false, servicos: [sv.id], inicio: null, fim: null,
                limiteTotal: null, umPorCliente: true, ativo: true };
    bd.cupons.push(c); sv.ativo = false;
    abrirCupom(c.id);
    const marcado = !!document.querySelector(`#cpServicos input[value="${sv.id}"]:checked`);
    salvarCupom(c.id); sv.ativo = true;
    return [marcado, JSON.stringify(bd.cupons.find(x => x.id === c.id).servicos) === JSON.stringify([sv.id])];
  });
  igual('cupom de um serviço desativado: o serviço continua marcado, e salvar não vira "todos"', cupom, [true, true]);

  const pacote = await p.evaluate(() => { diaAtual = somarDias(hoje(), 120); irPara('pacotes');
    const t = document.getElementById('listaPacotes').innerText; diaAtual = hoje(); return t; });
  verdade('o pacote conta as clientes pelo dia de hoje, não pelo dia aberto na agenda', /Clientes no pacote \(1\)/.test(pacote), pacote.slice(0, 200));

  const busca = await p.evaluate(() => {
    bd.clientes.push({ id: id(), salaoId: salaoAtual, nome: 'José Antônio', telefone: '11987654321' });
    irPara('clientes');
    const r = q => { document.getElementById('buscaCliente').value = q; pintarClientes();
      return /José Antônio/.test(document.getElementById('listaClientes').innerText); };
    return [r('jose'), r('(11) 98765-4321'), r('98765-4321')];
  });
  igual('busca de cliente sem acento e pelo telefone formatado', busca, [true, true, true]);

  const bloq = await p.evaluate(() => {
    const pr = doSalao(bd.profissionais)[0];
    const b = { id: id(), salaoId: salaoAtual, profissionalId: pr.id, data: hoje(), inicio: 9 * 60, fim: 17 * 60, motivo: 'digitado errado' };
    bd.bloqueios.push(b);
    abrirDetalheBloqueio(b.id);
    const tem = [...document.querySelectorAll('#modalPe button')].some(x => /Remover bloqueio/.test(x.textContent));
    window.confirm = () => true; removerBloqueio(b.id);
    return [tem, bd.bloqueios.some(x => x.id === b.id)];
  });
  igual('bloqueio abre com "Remover bloqueio", e remove', bloq, [true, false]);

  const papel = await p.evaluate(() => {
    const original = meuPapel, ficha = minhaFichaDeProf;
    const eu = doSalao(bd.profissionais).filter(x => x.ativo)[0];
    meuPapel = () => 'profissional'; minhaFichaDeProf = () => eu;
    abrirNovo(eu.id, 600);
    const opcoes = document.querySelectorAll('#fProf option').length; fecharModal();
    meuPapel = () => 'recepcao'; minhaFichaDeProf = () => null;
    irPara('caixa'); pintarCaixa();
    const titulo = getComputedStyle(document.getElementById('tituloComissao')).display;
    const lista = document.getElementById('listaComissao').innerHTML.trim();
    meuPapel = original; minhaFichaDeProf = ficha; irPara('agenda');
    return [opcoes, titulo, lista];
  });
  igual('a profissional vê só ela no "+ Agendamento"; a recepção não vê a comissão das colegas', papel, [1, 'none', '']);

  const caixa = await p.evaluate(() => {
    const c = { id: id(), salaoId: salaoAtual, numero: 999, data: somarDias(hoje(), -1), status: 'fechada',
                fechadaEm: new Date().toISOString(), itens: [], pagamentos: [] };
    return diaDaComanda(c) === hoje();
  });
  verdade('a comanda aberta ontem e paga hoje entra no Caixa de HOJE', caixa);

  const link = await p.evaluate(() => { irPara('publico'); return document.getElementById('abrirComoCliente').getAttribute('href'); });
  verdade('na demonstração, "Abrir o app do cliente" continua na demonstração', /demo=1/.test(link), link);

  const func = await p.evaluate(() => {
    const sl = acharSalao(salaoAtual); sl.cfg = Object.assign({}, sl.cfg, { funcionamento: null });
    pdHorario = { 1: [[540, 1080]], 2: [[540, 1080]], 3: [[540, 1080]], 4: [[540, 1080]], 5: [[540, 1080]], 6: [[540, 780]], 0: null };
    pdAplicarHorario();
    return [JSON.stringify((sl.cfg.funcionamento || {})[1]), JSON.stringify((sl.cfg.funcionamento || {})[0])];
  });
  igual('o passo a passo preenche o horário de funcionamento (segunda 09:00–18:00, domingo fechado)', func, ['[["09:00","18:00"]]', '[]']);

  igual('sessão de pacote sai por zero na agenda', await p.evaluate(() =>
    totalDe({ pacoteClienteId: 'x', servicos: [{ preco: 80 }], desconto: 0 })), 0);
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
