/* ===========================================================================
   AgendaPro — a tela de Aparência na mão de quem nunca a viu

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/aparencia-uso.test.mjs

   O pedido: "Veja se está funcionando, procure se tem algum bug na
   configuração Aparência do link, se todos os itens estão funcionando, e
   você, como uma pessoa que não conhece o sistema, saberia mexer."

   O que a revisão achou, e este arquivo cobra:
     1. o Salvar morava no fim de uma tela de 9 mil pixels — mexer lá em cima
        e sair sem salvar perdia tudo, sem aviso. Agora uma barra no pé da
        tela diz "Mudanças não salvas", com Salvar e Desfazer;
     2. no celular a prévia ficava DEPOIS de tudo (11 mil pixels abaixo): quem
        mexia numa cor não via nada. Agora o "Ver prévia" a abre por cima, e
        tocar numa parte dela leva à configuração;
     3. dezenove linhas de cor por frase, abertas, afogavam as quatro que
        importam primeiro: agora recolhidas, e abrem sozinhas quando o dono
        já escolheu uma ou toca na frase da prévia;
     4. "Atual" e "Personalizado" desenhavam a mesma página; o "Personalizado"
        dos temas era o botão de LIMPAR as cores; "Temas prontos" se confundia
        com "Modelos prontos"; e havia texto sem acento na tela;
     5. no celular o campo HEX cortava o último caractere ("#AA224"), e nas
        linhas do gradiente ele ficava à esquerda, colado no quadrado.
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
const arte = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="${a}"/>`
  + `<circle cx="320" cy="180" r="120" fill="${b}"/></svg>`).toString('base64');

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`au-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino', duracaoMin:30, intervaloMin:0,
  preco:90, ativo:true, aceitaOnline:true, categoria:'Cabelo', foto: arte('#7C3AED', '#C084FC') });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, {
  endereco:{ logradouro:'Rua Avanhandava', numero:'10', bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  capa: arte('#2E1065', '#7C3AED') });
const porCfg = cfg => dona.atualizar('saloes', SALAO, { cfg: Object.assign({ diasLiberados:30,
  funcionamento: SEMANA, pagamentos:{ formas:['pix'] }, sobre:'Salão de beleza' }, cfg) });
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function painel(largura){
  const cel = largura < 700;
  const ctx = await nav.newContext({ viewport:{ width: largura, height: cel ? 820 : 1000 }, isMobile: cel, hasTouch: cel });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
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
  await p.evaluate(() => irPara('salao'));
  await p.waitForTimeout(400);
  await p.evaluate(() => trocarAbaSalao('aparencia'));
  await p.waitForTimeout(800);
  return { p, fechar: () => ctx.close() };
}
const barra = p => p.evaluate(() => { const b = document.getElementById('apBarra');
  return { suja: b.classList.contains('suja'), aparece: getComputedStyle(b).display !== 'none',
    mostra: [...b.children].filter(x => getComputedStyle(x).display !== 'none').map(x => x.textContent.trim()) }; });

/* ══════════════════════════════════════════════════════════════════════════
   1 — A BARRA DE MUDANÇAS NÃO SALVAS
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. A barra do pé da tela: Salvar sempre à mão');
/* Três salões de verdade, e em nenhum a barra pode acusar mudança ao abrir:
   um recém-criado (cfg quase vazio), um com tudo escolhido e um com o
   "personalizado" gravado de antes. */
const CFGS = {
  'recém-criado': {},
  'com tudo escolhido': { cor:'#B76E79', tema:'escuro', modo:'premium', moldura:'elegante', letra:'elegante',
    fundoTipo:'gradiente', gradiente:'#241E16,#0E0C0A', capaFoco:30, veu:60, cartoes:'vidro', capaForma:'reta',
    logoForma:'quadrado', logoBorda:'grossa', slideForma:'quadrado', fitaMetal:'forte', fitaBrilho:false,
    fitaTempo:'rapida', fitaCor:'#123456', fitaBorda:'suave', botaoProdutos:'metal', precoNaCapa:true,
    atalhos:{ estilo:'sombra', cores:{ horarios:'#0E7490' }, sombra:{ intensidade:'personalizada',
      desfoque:18, opacidade:14, distancia:5, cor:'#B76E79' } },
    /* "Fundos suaves" e "Cartões" vêm antes de "Texto" na tela, e o jsonb
       devolve as chaves curtas primeiro: a mesma escolha, em ordem diferente,
       não pode parecer mudança. */
    cores:{ secundaria:'#3A301F', papel:'#121010', card:'#1E1A15', titulo:'#F6EFE1', texto:'#D4C9B5',
      nomeSalao:'#E2C274', precoProduto:'#A5D6A7', letraAgendar:'#000000' } },
  'personalizado de antes': { cor:'#1D4ED8', modo:'personalizado' },
};
for(const [nome, cfg] of Object.entries(CFGS)){
  await porCfg(cfg);
  const { p, fechar } = await painel(1280);
  const b = await barra(p);
  igual(`${nome}: ao abrir, nada a salvar e a barra fica escondida no computador`, [b.suja, b.aparece], [false, false]);
  await fechar();
}
await porCfg({ cor:'#1D4ED8' });
{
  const { p, fechar } = await painel(1280);
  await p.evaluate(() => escolherCorSolta('titulo', '#aa2244'));
  igual('mudou uma cor: a barra aparece, com o aviso, Desfazer e Salvar', (await barra(p)).mostra,
    ['Mudanças não salvas', 'Desfazer', 'Salvar']);
  await p.locator('#apBarra .btn-p').click();
  await p.waitForTimeout(1500);
  igual('Salvar pela barra grava', (await cfgDe()).cores, { titulo:'#aa2244' });
  igual('e a barra some', (await barra(p)).aparece, false);
  await p.evaluate(() => { escolherCorSolta('titulo', '#112233'); escolherAparencia('letra', 'marcante'); });
  await p.locator('#apBarra button', { hasText: 'Desfazer' }).click();
  await p.waitForTimeout(300);
  igual('Desfazer volta ao que está salvo', await p.evaluate(() => [aparencia.cores.titulo, aparencia.letra]),
    ['#aa2244', (await cfgDe()).letra || 'moderno']);
  igual('e a barra some de novo', (await barra(p)).suja, false);
  await p.locator('.modelo[data-modelo="rose"]').click();
  await p.waitForTimeout(250);
  igual('experimentar um modelo também é mudança não salva', (await barra(p)).suja, true);
  await p.getByText('Usar este modelo').click();
  await p.waitForTimeout(1500);
  igual('e usar o modelo salva: a barra some', (await barra(p)).suja, false);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   2 — A PRÉVIA NO CELULAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. No celular, a prévia a um toque');
await porCfg({ cor:'#1D4ED8' });
{
  const { p, fechar } = await painel(412);
  const b = await barra(p);
  igual('a barra fica sempre no celular, com o Ver prévia', [b.aparece, b.mostra], [true, ['👁 Ver prévia']]);
  const onde = await p.evaluate(() => Math.round(document.querySelector('.ap-previa').getBoundingClientRect().top));
  verdade('(e a prévia continua lá no fim da tela, fora de vista — por isso o botão)', onde > 3000, 'topo em ' + onde);
  await p.locator('.ap-ver-previa').click();
  await p.waitForTimeout(300);
  const aberta = await p.evaluate(() => { const r = document.getElementById('previaFone').getBoundingClientRect();
    return { classe: document.body.classList.contains('ap-previa-aberta'), naTela: r.top >= 0 && r.top < innerHeight,
      fechar: !!document.querySelector('.ap-previa-topo button').offsetParent }; });
  igual('Ver prévia abre o celular por cima, com Fechar', aberta, { classe:true, naTela:true, fechar:true });
  await p.locator('#previaFone [data-cfg="bemVindo"]').click();
  await p.waitForTimeout(1000);
  const toque = await p.evaluate(() => { const l = document.querySelector('.cor-linha[data-chave="bemVindo"]');
    const r = l.getBoundingClientRect();
    return { fechou: !document.body.classList.contains('ap-previa-aberta'), dobra: document.getElementById('frasesDetalhe').open,
      acesa: l.classList.contains('ap-alvo'), naTela: r.top >= 0 && r.bottom <= innerHeight }; });
  igual('tocar numa frase fecha a prévia, abre as frases e leva à cor dela', toque,
    { fechou:true, dobra:true, acesa:true, naTela:true });
  await p.locator('.ap-ver-previa').click();
  await p.waitForTimeout(200);
  await p.locator('.ap-previa-topo button').click();
  igual('e o Fechar fecha', await p.evaluate(() => document.body.classList.contains('ap-previa-aberta')), false);
  await p.evaluate(() => escolherCorSolta('titulo', '#aa2244'));
  igual('com mudança, o Salvar aparece do lado do Ver prévia', (await barra(p)).mostra, ['👁 Ver prévia', 'Desfazer', 'Salvar']);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   3 — AS FRASES RECOLHIDAS
   ══════════════════════════════════════════════════════════════════════════ */
secao('3. As cores de cada frase, recolhidas');
await porCfg({ cor:'#1D4ED8' });
{
  const { p, fechar } = await painel(1280);
  const t = await p.evaluate(() => { const d = document.getElementById('frasesDetalhe');
    return { aberta: d.open, resumo: d.querySelector('summary').textContent.trim(),
      dentro: d.querySelectorAll('.cor-linha').length, noTextos: d.closest('.ap-sec').id }; });
  igual('sem frase escolhida, fechadas, com um título que diz o que tem dentro', t,
    { aberta:false, resumo:'Mudar a cor de cada frase, uma por uma', dentro:19, noTextos:'apTextos' });
  await fechar();
}
await porCfg({ cor:'#1D4ED8', cores:{ duracao:'#4E342E' } });
{
  const { p, fechar } = await painel(1280);
  igual('quem já deu cor a uma frase acha as frases abertas',
    await p.evaluate(() => document.getElementById('frasesDetalhe').open), true);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   4 — OS NOMES
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. Nomes que quem chega entende');
await porCfg({ cor:'#1D4ED8', modo:'personalizado', cores:{ titulo:'#aa2244' } });
{
  const { p, fechar } = await painel(1280);
  const t = await p.evaluate(() => ({
    modos: [...document.querySelectorAll('#reguaModo button')].map(b => [b.textContent.trim(), b.classList.contains('on')]),
    rotulos: [...document.querySelectorAll('#apMarca .rot')].map(r => r.textContent.trim()),
    ultimoTema: [...document.querySelectorAll('#temasProntos button')].pop().textContent.trim(),
    texto: document.querySelector('.sub-tela[data-sub="aparencia"]').innerText,
  }));
  igual('modo de exibição: dois, e o personalizado de antes aparece como Simples', t.modos,
    [['Simples', true], ['Premium', false]]);
  await p.locator('#reguaModo button', { hasText: 'Simples' }).click();
  igual('tocar no Simples já aceso não vira mudança', [await p.evaluate(() => aparencia.modo), (await barra(p)).suja],
    ['personalizado', false]);
  igual('com acento, e "Só as cores prontas" no lugar de "Temas prontos"', t.rotulos,
    ['Modo de exibição', 'Cor da marca', 'Só as cores prontas']);
  igual('o botão que limpa as cores diz que limpa', t.ultimoTema, 'Limpar cores');
  const semAcento = (t.texto.match(/\b(e'|so'|voce|exibicao|voc[eê]'|nao)\b/gi) || []);
  igual('nenhum texto sem acento na tela', semAcento, []);
  await p.locator('#temasProntos button', { hasText: 'Limpar cores' }).click();
  igual('e Limpar cores limpa', await p.evaluate(() => aparencia.cores), {});
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════
   5 — O CAMPO HEX
   ══════════════════════════════════════════════════════════════════════════ */
secao('5. O código da cor inteiro, e sempre do mesmo lado');
await porCfg({ cor:'#1D4ED8', fundoTipo:'gradiente', gradiente:'#A100FF,#5B0F9E,#1A1030' });
for(const largura of [412, 360]){
  const { p, fechar } = await painel(largura);
  const r = await p.evaluate(() => { document.getElementById('frasesDetalhe').open = true;
    const hs = [...document.querySelectorAll('.ap-controles .cor-hex')].filter(h => h.offsetParent);
    return { total: hs.length, cortados: hs.filter(h => h.scrollWidth > h.clientWidth).map(h => h.value) }; });
  verdade(`a ${largura}px, nenhum dos ${r.total} códigos cortado`, r.total > 30 && !r.cortados.length, JSON.stringify(r.cortados));
  await fechar();
}
{
  const { p, fechar } = await painel(1280);
  const lado = await p.evaluate(() => ['gradA', 'gradM', 'gradB'].map(id => {
    const q = document.getElementById(id), h = q._hex, t = q.closest('.cor-linha').querySelector('.cor-linha-txt');
    return h.getBoundingClientRect().left > t.getBoundingClientRect().left;
  }));
  igual('no gradiente, o código fica à direita do nome, como nas outras linhas', lado, [true, true, true]);
  await fechar();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
