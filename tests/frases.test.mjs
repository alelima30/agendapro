/* ===========================================================================
   AgendaPro — cada frase do topo da página com a sua cor

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/frases.test.mjs

   O pedido: "Quero que cada frase tenha configuração para mudar a cor: Salão
   Megatop uma cor, endereço rua outra cor, bairro com cidade outra cor.
   Bem-vindo outra cor, a frase 'Escolha o serviço...' até a palavra
   produtos de outra cor."

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a tela: as cinco linhas em Textos, com HEX, dizendo de quem herdam;
     2. sem escolha, cada frase continua na cor que sempre teve;
     3. escolhida, cada cor muda só a frase dela — nem as outras quatro, nem o
        que dividia a cor com ela (nome dos serviços, duração, preço);
     4. a prévia mostra a mesma cor, e tocar na frase leva à linha dela;
     5. "herdar" devolve a frase à cor de cima;
     6. o aviso de leitura mede cada frase onde ela mora;
     7. salvar grava, e a página da cliente lê;
     8. a letra (e o ícone) do Agendar horário e do Ver produtos;
     e as frases de baixo — slide, serviços, produtos, quem atende — nos
     mesmos passos 1 a 7. "Fez também de todas as frases abaixo?"
   "Fez também cor para o Até amanhã às 00:00? Para o Agendar horário junto
   com o logo? Para o Ver produtos?"
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
const dona = aba();
await dona.criarConta({ email:`fr-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const arte = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="${a}"/>`
  + `<circle cx="320" cy="180" r="120" fill="${b}"/></svg>`).toString('base64');
/* Sete serviços: a capa mostra seis, e o sétimo traz o "Ver todos os
   serviços". O primeiro tem foto (o slide). Todos têm descrição: a prévia
   mostra os dois primeiros que o banco devolve, e a ordem não é garantida. */
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino', duracaoMin:30, intervaloMin:0,
  preco:90, ativo:true, aceitaOnline:true, categoria:'Cabelo', descricao:'Lavar, cortar e finalizar.',
  foto: arte('#7C3AED', '#C084FC') });
for(const [i, nome] of ['Escova', 'Hidratação', 'Manicure', 'Pedicure', 'Sobrancelha', 'Maquiagem'].entries())
  await dona.inserir('servicos', { salaoId: SALAO, nome, duracaoMin:30 + i * 5, intervaloMin:0,
    preco:40 + i * 10, ativo:true, aceitaOnline:true, categoria:'Beleza', descricao:'Com hora marcada.' });
// Com produto e WhatsApp, o Bem-vindo tem os dois botões.
await dona.inserir('produtos', { salaoId: SALAO, nome:'Shampoo', preco:45, custo:20, estoque:5,
  comissaoPct:10, ativo:true, vendaOnline:true });
await dona.atualizar('saloes', SALAO, { whatsapp:'11988887777' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
/* As quatro cores de cima escolhidas: cada frase tem um pai com cor
   conhecida, e dá para ver se ela o segue ou se separou dele. */
const PAIS = { titulo:'#3A2A2E', texto:'#5E4A4F', discreto:'#8A7278', destaque:'#9B4F5D' };
const BASE_CFG = { diasLiberados:30, cor:'#B76E79', precoNaCapa:true, moldura:'elegante', funcionamento: SEMANA,
  pagamentos:{ formas:['pix'] }, sobre:'Salão de beleza' };
const porCores = (cores, extra) => dona.atualizar('saloes', SALAO,
  { cfg: Object.assign({}, BASE_CFG, extra || {}, { cores: Object.assign({}, PAIS, cores) }) });
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' } });
await porCores({});

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

async function painel(){
  const ctx = await nav.newContext({ viewport:{ width:1280, height:1000 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function'
    && typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => irPara('salao'));
  await p.waitForTimeout(400);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(800);
  return { p, fechar: () => ctx.close() };
}

const HEX = `c => {
  const m = /rgba?\\(\\s*([\\d.]+)[,\\s]+([\\d.]+)[,\\s]+([\\d.]+)/.exec(c || '');
  return m ? '#' + [m[1], m[2], m[3]].map(n => Math.round(Number(n)).toString(16).padStart(2, '0')).join('').toUpperCase() : c;
}`;
/* Cada frase, onde ela está na página. */
const NA_PAGINA = {
  nomeSalao: '.marca-salao h2', rua: '.marca-end .rua', lugar: '.marca-end .lugar',
  horario: '.status-txt', bemVindo: '.boas-oi', convite: '.boas-sub',
  legenda: '.slide figcaption', tituloServicos: '#capaServicos > .cat', nomeServico: '.sv-cartao-txt b',
  descServico: '.sv-cartao-desc', precoServico: '.sv-cartao-preco', duracao: '.sv-cartao-dur',
  verTodosServicos: '#capaServicos .ver-todos', tituloProdutos: '#capaLoja > .cat', nomeProduto: '.pr-txt b',
  precoProduto: '.pr-txt span', verTodosProdutos: '.ver-todos-produtos', tituloEquipe: '#rotuloEquipe',
  nomeEquipe: '#capaEquipe .tt',
};
async function lerPagina(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:1400 }, isMobile:true });
  const c = await ctx.newPage();
  c.on('pageerror', e => erros.push('página: ' + e.message));
  await c.goto(BASE + '/agendar.html?salao=' + SLUG);
  await c.waitForFunction(() => document.querySelector('.boas-sub') && document.querySelector('.sv-cartao-dur')
    && document.querySelector('.status-txt') && document.querySelector('.boas-produtos svg')
    && document.querySelector('.slide figcaption') && document.querySelector('#capaEquipe .tt')
    && document.querySelector('.pr-txt b') && document.querySelector('#capaServicos .ver-todos'),
    null, { timeout: 15000 });
  await c.waitForTimeout(300);
  const r = await c.evaluate(([h, S]) => { const hex = eval(h);
    return Object.fromEntries(Object.entries(S).map(([k, sel]) => {
      const e = document.querySelector(sel);
      return [k, e ? hex(getComputedStyle(e).color) : '(sem ' + sel + ')'];
    }));
  }, [HEX, NA_PAGINA]);
  await ctx.close();
  return r;
}
const DO_TOPO = ['nomeSalao', 'rua', 'lugar', 'horario', 'bemVindo', 'convite'];
const DE_BAIXO = ['legenda', 'tituloServicos', 'nomeServico', 'descServico', 'precoServico', 'duracao',
  'verTodosServicos', 'tituloProdutos', 'nomeProduto', 'precoProduto', 'verTodosProdutos', 'tituloEquipe', 'nomeEquipe'];
const FRASES = [...DO_TOPO, ...DE_BAIXO];
const PAI = { nomeSalao:'titulo', rua:'texto', lugar:'discreto', horario:'texto', bemVindo:'destaque', convite:'texto',
  tituloServicos:'discreto', nomeServico:'titulo', descServico:'discreto', precoServico:'destaque', duracao:'discreto',
  verTodosServicos:'destaque', tituloProdutos:'discreto', nomeProduto:'titulo', precoProduto:'destaque',
  verTodosProdutos:'destaque', tituloEquipe:'discreto', nomeEquipe:'titulo' };
// Sem escolha: a cor do pai; a legenda do slide é branca.
const DE_ANTES = Object.fromEntries(FRASES.map(k => [k, k === 'legenda' ? '#FFFFFF' : PAIS[PAI[k]]]));

/* ══════════════════════════════════════════════════════════════════════════
   1 — A TELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. As seis frases em Textos');
{
  const { p, fechar } = await painel();
  const t = await p.evaluate(() => ({
    linhas: [...document.querySelectorAll('#apTextos #coresFrases .cor-linha')].map(l => ({
      chave: l.dataset.chave, rot: l.querySelector('b').textContent.trim(),
      ajuda: l.querySelector('.cor-linha-ajuda').textContent.trim(),
      valor: l.querySelector('input[type="color"]').value.toUpperCase(),
      hex: (l.querySelector('input[type="color"]')._hex || {}).value || '',
      herdar: getComputedStyle(l.querySelector('button')).display !== 'none' })),
    titulo: (document.querySelector('#coresFrases').previousElementSibling || {}).textContent,
  }));
  igual('as seis, na ordem da página', t.linhas.map(l => l.chave), DO_TOPO);
  igual('com os nomes que o dono usa', t.linhas.map(l => l.rot),
    ['Nome do estabelecimento', 'Endereço (rua)', 'Bairro e cidade', 'Horário de hoje', 'Bem-vindo!', 'Frase do Bem-vindo']);
  verdade('debaixo de um título que diz o que é', /Cada frase do topo/i.test(t.titulo || ''), t.titulo);
  verdade('sem escolha, cada uma diz de quem herda, e sem botão "herdar"',
    t.linhas.every(l => /acompanha "/.test(l.ajuda) && !l.herdar), JSON.stringify(t.linhas.map(l => l.ajuda)));
  igual('e o quadrado mostra a cor que está na frase: a do pai',
    t.linhas.map(l => l.valor), DO_TOPO.map(k => PAIS[PAI[k]]));
  verdade('cada uma com o campo HEX do mesmo valor', t.linhas.every(l => l.hex === l.valor), JSON.stringify(t.linhas));
  /* E as de baixo, em três grupos com título, na ordem da página. */
  const baixo = await p.evaluate(() => ['coresFrasesServicos', 'coresFrasesProdutos', 'coresFrasesEquipe'].map(id => {
    const g = document.getElementById(id);
    return { onde: g.closest('.ap-sec').id, titulo: g.previousElementSibling.textContent.trim(),
      linhas: [...g.querySelectorAll('.cor-linha')].map(l => ({ chave: l.dataset.chave,
        valor: l.querySelector('input').value.toUpperCase(), ajuda: l.querySelector('.cor-linha-ajuda').textContent,
        hex: !!l.querySelector('input')._hex })) };
  }));
  igual('as de baixo em Textos, em três grupos: slide e serviços, produtos, quem atende',
    baixo.map(g => [g.onde, g.titulo]), [['apTextos', 'Slide e serviços'], ['apTextos', 'Produtos'], ['apTextos', 'Quem atende']]);
  igual('todas as frases de baixo, na ordem da página', baixo.flatMap(g => g.linhas.map(l => l.chave)), DE_BAIXO);
  igual('cada quadrado mostra a cor que está na frase', baixo.flatMap(g => g.linhas.map(l => l.valor)),
    DE_BAIXO.map(k => DE_ANTES[k]));
  verdade('e cada uma com HEX e dizendo de onde vem a cor', baixo.every(g => g.linhas.every(l => l.hex
    && /acompanha|automático/.test(l.ajuda))), JSON.stringify(baixo));
  /* Mudar o pai muda o quadrado da frase que ainda herda. */
  await p.evaluate(() => escolherCorSolta('texto', '#224466'));
  const segue = await p.evaluate(() => ['rua', 'horario', 'convite'].map(k =>
    document.querySelector(`.cor-linha[data-chave="${k}"] input`).value.toUpperCase()));
  igual('trocando "Texto principal", a rua, o horário e a frase herdados acompanham', segue,
    ['#224466', '#224466', '#224466']);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 e 3 — NA PÁGINA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. Sem escolha, a página é a de antes');
igual('cada frase na cor que sempre teve, e o resto também', await lerPagina(), DE_ANTES);

secao('3. Cada cor muda só a sua frase');
const NOVAS = { nomeSalao:'#C2185B', rua:'#1565C0', lugar:'#2E7D32', horario:'#00838F',
  bemVindo:'#EF6C00', convite:'#6A1B9A', legenda:'#FFEB3B', tituloServicos:'#AD1457', nomeServico:'#283593',
  descServico:'#00695C', precoServico:'#E65100', duracao:'#4E342E', verTodosServicos:'#6A1B9A',
  tituloProdutos:'#1B5E20', nomeProduto:'#0D47A1', precoProduto:'#BF360C', verTodosProdutos:'#4A148C',
  tituloEquipe:'#880E4F', nomeEquipe:'#1A237E' };
for(const k of FRASES){
  await porCores({ [k]: NOVAS[k] });
  const r = await lerPagina();
  igual(`só ${k} mudou`, r, Object.assign({}, DE_ANTES, { [k]: NOVAS[k] }));
}
await porCores(NOVAS);
igual('todas juntas, cada uma na sua', await lerPagina(), Object.assign({}, DE_ANTES, NOVAS));

/* ══════════════════════════════════════════════════════════════════════════
   4, 5 e 6 — A PRÉVIA, O HERDAR E O AVISO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. A prévia mostra a mesma cor, e o toque leva à linha');
await porCores({});
{
  const { p, fechar } = await painel();
  const NA_PREVIA = { nomeSalao:'.fone-topo > b', rua:'.fone-topo [data-cfg="rua"]', lugar:'.fone-topo i',
    horario:'.fone-status-txt', bemVindo:'.fone-boas-t', convite:'.fone-boas-sub' };
  // As de baixo que a prévia desenha (o Ver todos os serviços não cabe nela).
  const DE_BAIXO_NA_PREVIA = DE_BAIXO.filter(k => k !== 'verTodosServicos');
  for(const k of DE_BAIXO_NA_PREVIA) NA_PREVIA[k] = k === 'legenda' ? '.fone-slide-leg' : `[data-cfg="${k}"]`;
  const soDoTopo = o => Object.fromEntries(Object.entries(o).filter(([k]) => DO_TOPO.includes(k)));
  const lerPrevia = () => p.evaluate(([h, S]) => { const hex = eval(h);
    return Object.fromEntries(Object.entries(S).map(([k, sel]) => {
      const e = document.querySelector('#previaFone ' + sel);
      return [k, e ? hex(getComputedStyle(e).color) : '(sem ' + sel + ')'];
    }));
  }, [HEX, NA_PREVIA]);
  const antes = await lerPrevia();
  // Títulos, nomes e preços de baixo: a prévia já os pintava na cor do pai.
  const HERDA_NA_PREVIA = ['tituloServicos', 'nomeServico', 'precoServico', 'tituloProdutos', 'nomeProduto',
    'precoProduto', 'verTodosProdutos', 'tituloEquipe', 'nomeEquipe', 'legenda'];
  igual('sem escolha, as de baixo da prévia na cor do pai',
    Object.fromEntries(HERDA_NA_PREVIA.map(k => [k, antes[k]])), Object.fromEntries(HERDA_NA_PREVIA.map(k => [k, DE_ANTES[k]])));
  igual('sem escolha, cada frase do topo da prévia na cor do pai', soDoTopo(antes),
    { nomeSalao: PAIS.titulo, rua: PAIS.texto, lugar: PAIS.discreto, horario: PAIS.texto,
      bemVindo: PAIS.destaque, convite: PAIS.texto });
  await p.evaluate(N => { for(const [k, v] of Object.entries(N)) escolherCorSolta(k, v); }, NOVAS);
  const depois = await lerPrevia();
  igual('escolhidas, a prévia mostra as do topo', soDoTopo(depois), soDoTopo(NOVAS));
  igual('e as de baixo', Object.fromEntries(DE_BAIXO_NA_PREVIA.map(k => [k, depois[k]])),
    Object.fromEntries(DE_BAIXO_NA_PREVIA.map(k => [k, NOVAS[k]])));
  const opacos = await p.evaluate(() => ['descServico', 'duracao'].map(k =>
    getComputedStyle(document.querySelector(`#previaFone [data-cfg="${k}"]`)).opacity));
  igual('a descrição e a duração escolhidas aparecem na cor cheia', opacos, ['1', '1']);
  const op = await p.evaluate(() => getComputedStyle(document.querySelector('#previaFone .fone-topo [data-cfg="rua"]')).opacity);
  igual('a rua da prévia na cor cheia, como na página', op, '1');

  const TOQUES = Object.assign({ nome:'nomeSalao', rua:'rua', lugar:'lugar', horario:'horario',
      bemVindo:'bemVindo', convite:'convite', agendar:'letraAgendar' },
    Object.fromEntries(DE_BAIXO_NA_PREVIA.map(k => [k, k])));
  for(const [k, sel] of Object.entries(TOQUES)){
    await p.evaluate(() => { document.querySelectorAll('.ap-alvo').forEach(e => e.classList.remove('ap-alvo')); window.scrollTo(0, 0); });
    await p.locator(`#previaFone [data-cfg="${k}"]`).first().click({ force: true });
    await p.waitForTimeout(800);
    const r = await p.evaluate(c => { const l = document.querySelector(`.ap-controles .cor-linha[data-chave="${c}"]`);
      const b = l.getBoundingClientRect();
      return { aceso: l.classList.contains('ap-alvo'), naTela: b.top >= 0 && b.bottom <= innerHeight }; }, sel);
    verdade(`tocar em ${k} acende a linha ${sel}`, r.aceso && r.naTela, JSON.stringify(r));
  }

  secao('5. "herdar" devolve a frase à cor de cima');
  await p.evaluate(() => herdarCorSolta('rua'));
  const h = await p.evaluate(() => ({ tem: 'rua' in aparencia.cores,
    ajuda: document.querySelector('.cor-linha[data-chave="rua"] .cor-linha-ajuda').textContent }));
  verdade('a chave sai e a linha volta a dizer de quem herda', !h.tem && /Texto principal/.test(h.ajuda), JSON.stringify(h));
  igual('e a rua da prévia volta à cor do texto', (await lerPrevia()).rua, PAIS.texto);

  secao('6. O aviso de leitura mede cada frase onde ela mora');
  const aviso = () => p.evaluate(() => document.getElementById('avisoLegibilidade').textContent);
  await p.evaluate(() => { escolherCorSolta('rua', '#F4ECEE'); escolherCorSolta('bemVindo', '#F9F4F5'); });
  const a1 = await aviso();
  verdade('rua clara no fundo claro: acusa a rua', /a rua \(/.test(a1), a1);
  verdade('Bem-vindo claro no quadro claro: acusa, e diz "sobre o quadro"',
    /o Bem-vindo \([\d.]+:1 sobre o quadro\)/.test(a1), a1);
  /* Quadro escuro com fundo roxo: o laranja se lê no quadro, onde ele está. */
  await p.evaluate(() => { aparencia.tema = 'escuro'; aparencia.fundoTipo = 'gradiente';
    aparencia.gradiente = '#8E24AA,#4A148C'; aparencia.cores = { card:'#1B2233', bemVindo:'#FFA040' };
    pintarAparencia(); });
  const a2 = await aviso();
  verdade('laranja no quadro escuro sobre fundo roxo: não acusa o Bem-vindo', !/Bem-vindo/.test(a2), a2);
  await p.evaluate(() => { aparencia.cores.nomeSalao = '#7B1FA2'; pintarAparencia(); });
  const a3 = await aviso();
  verdade('mas o nome roxo sobre o fundo roxo, acusa', /o nome do estabelecimento \([\d.]+:1 sobre o fundo\)/.test(a3), a3);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   7 — SALVAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('7. Salvar grava, e a página lê');
await porCores({});
{
  const { p, fechar } = await painel();
  await p.evaluate(N => { for(const [k, v] of Object.entries(N)) escolherCorSolta(k, v); salvarAparencia(); }, NOVAS);
  await p.waitForTimeout(1800);
  const cores = (await dona.lista('saloes', { id: SALAO }))[0].cfg.cores || {};
  igual('todas no banco', Object.fromEntries(FRASES.map(k => [k, cores[k]])), NOVAS);
  igual('as de cima continuam as dele', Object.fromEntries(Object.keys(PAIS).map(k => [k, cores[k]])), PAIS);
  igual('e a página da cliente mostra', await lerPagina(), Object.assign({}, DE_ANTES, NOVAS));
  /* Um modelo pronto decide o conjunto: as cores das frases saem com ele. */
  await p.locator('.modelo[data-modelo="azul"]').click();
  await p.waitForTimeout(300);
  const mo = await p.evaluate(() => FRASE_HERDA_DE && Object.keys(FRASE_HERDA_DE).filter(k => k in aparencia.cores));
  igual('experimentar um modelo tira as cores das frases', mo, []);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   8 — A LETRA DOS BOTÕES, COM O ÍCONE
   ══════════════════════════════════════════════════════════════════════════ */
secao('8. A letra do Agendar horário e do Ver produtos, com o ícone');
async function lerBotoes(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:1000 }, isMobile:true });
  const c = await ctx.newPage();
  c.on('pageerror', e => erros.push('página: ' + e.message));
  await c.goto(BASE + '/agendar.html?salao=' + SLUG);
  await c.waitForFunction(() => document.querySelector('.boas-produtos svg') && document.querySelector('.boas-cta svg'),
    null, { timeout: 15000 });
  const r = await c.evaluate(h => { const hex = eval(h);
    const cor = sel => { const e = document.querySelector(sel); return e ? hex(getComputedStyle(e).color) : '(sem)'; };
    return { agendar: cor('.boas .boas-cta:not(.boas-produtos)'), agendarIcone: cor('.boas .boas-cta:not(.boas-produtos) svg'),
      produtos: cor('.boas .boas-produtos'), produtosIcone: cor('.boas .boas-produtos svg'),
      letraDoBotao: getComputedStyle(document.documentElement).getPropertyValue('--acao-txt').trim().toUpperCase() };
  }, HEX);
  await ctx.close();
  return r;
}
await porCores({});
const padrao = await lerBotoes();
verdade('sem escolha, a letra do Agendar é a que o botão calcula, e o ícone vai junto',
  padrao.agendar === padrao.letraDoBotao && padrao.agendarIcone === padrao.agendar, JSON.stringify(padrao));
igual('e o Ver produtos discreto fica na cor dos títulos, ícone junto',
  [padrao.produtos, padrao.produtosIcone], [PAIS.titulo, PAIS.titulo]);
await porCores({ letraAgendar:'#FFD54F' });
const soAgendar = await lerBotoes();
igual('escolhida a do Agendar: a letra e o ícone mudam, o Ver produtos não',
  [soAgendar.agendar, soAgendar.agendarIcone, soAgendar.produtos], ['#FFD54F', '#FFD54F', PAIS.titulo]);
await porCores({ letraProdutos:'#00695C', produtos:'#B45309' });
const soProdutos = await lerBotoes();
igual('escolhida a do Ver produtos: ganha até da cor dos produtos, e o Agendar fica',
  [soProdutos.produtos, soProdutos.produtosIcone, soProdutos.agendar], ['#00695C', '#00695C', padrao.agendar]);
await porCores({ letraProdutos:'#FFFFFF' }, { botaoProdutos:'metal' });
const metal = await lerBotoes();
igual('no Ver produtos de metal também', [metal.produtos, metal.produtosIcone], ['#FFFFFF', '#FFFFFF']);
/* O Ver produtos de metal também é um .boas-cta: a letra do Agendar não
   pode passar para ele. */
await porCores({}, { botaoProdutos:'metal' });
const metalPadrao = await lerBotoes();
await porCores({ letraAgendar:'#FFD54F' }, { botaoProdutos:'metal' });
const metalAgendar = await lerBotoes();
igual('com o Ver produtos de metal, a letra do Agendar fica só no Agendar',
  [metalAgendar.agendar, metalAgendar.produtos], ['#FFD54F', metalPadrao.produtos]);
await porCores({});
{
  const { p, fechar } = await painel();
  const t = await p.evaluate(() => ({
    botoes: [...document.querySelectorAll('#coresBotoes .cor-linha')].map(l => l.dataset.chave),
    produtos: [...document.querySelectorAll('#coresProdutos .cor-linha')].map(l => l.dataset.chave),
    ajuda: document.querySelector('.cor-linha[data-chave="letraAgendar"] .cor-linha-ajuda').textContent,
    icones: [...document.querySelectorAll('#previaFone .fone-cta, #previaFone .fone-cta2')].map(b => !!b.querySelector('svg')),
  }));
  igual('as duas linhas moram junto da cor de cada botão', [t.botoes, t.produtos],
    [['botao', 'letraAgendar'], ['produtos', 'letraProdutos']]);
  verdade('sem escolha, a linha diz que é automática', /automático/.test(t.ajuda), t.ajuda);
  igual('os botões da prévia têm o ícone, como na página', t.icones, [true, true]);
  await p.evaluate(() => { escolherCorSolta('letraAgendar', '#FFD54F'); escolherCorSolta('letraProdutos', '#00695C'); });
  const pv = await p.evaluate(h => { const hex = eval(h);
    const cor = sel => hex(getComputedStyle(document.querySelector('#previaFone ' + sel)).color);
    return [cor('.fone-cta[data-cfg="agendar"]'), cor('.fone-cta[data-cfg="agendar"] svg'), cor('.fone-cta2'), cor('.fone-cta2 svg')];
  }, HEX);
  igual('a prévia mostra as duas letras, com os ícones', pv, ['#FFD54F', '#FFD54F', '#00695C', '#00695C']);
  await p.evaluate(() => { escolherCorSolta('letraAgendar', corDoBotaoNaPrevia()); });
  const av = await p.evaluate(() => document.getElementById('avisoLegibilidade').textContent);
  verdade('letra da cor do próprio botão: o aviso acusa', /a letra do Agendar horário \(1\.0:1 sobre o botão\)/.test(av), av);
  await fechar();
}

igual('\nnenhum erro de JavaScript no painel nem na página', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
