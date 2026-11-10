/* ===========================================================================
   AgendaPro — o botão de baixo do link: na prévia, e com cor própria

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/botao-de-baixo.test.mjs

   ── O RELATO ───────────────────────────────────────────────────────────────
   "Na prévia não aparece lá no final o Agendar corte que aparece realmente
   no link, e não achei para mudar a cor também." É o botão fixo no pé da
   página (`#btPrincipal`): "Agendar horário" (era "Agendar corte" na
   barbearia, até o "não cortes" do dono), "Continuar" nos passos. Pintava com a Cor dos botões, junto com
   o Agendar do Bem-vindo — sem aparecer na prévia e sem linha própria.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. A prévia mostra o botão de baixo, com o rótulo do tipo de negócio — e
        as mesmas palavras do link nos títulos ("Nossos serviços", "Quem
        atende") e no botão do Bem-vindo.
     2. Sem escolha, nada muda: ele segue a Cor dos botões, na prévia e no link.
     3. "Botão de baixo" muda só ele — o Agendar do Bem-vindo fica como está —
        na prévia na hora, no banco e no link, com a letra que lê melhor.
     4. "Letra do botão de baixo" muda a letra.
     5. Tocar nele na prévia leva às duas cores dele.
     6. Cor torta vinda do banco é ignorada.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

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
const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const dona = novaAba();
await dona.criarConta({ email:`bb-${marca}@teste.com`, senha:'minhasenhaboa', nome:'Rita Alves',
  telefone:'+5511' + (100000000 + Math.floor(Math.random() * 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Navalha Barbearia ' + marca, p_tipo:'barbearia',
  p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte masculino', duracaoMin:30, intervaloMin:0,
  preco:45, ativo:true, aceitaOnline:true });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const BOTAO = '#1F2937';                       // a Cor dos botões, escolhida
const BASE_CFG = { cor:'#7C3AED', tema:'claro', funcionamento: SEMANA, pagamentos:{ formas:['pix'] } };
const porCores = cores => dona.atualizar('saloes', SALAO, { cfg: Object.assign({}, BASE_CFG, { cores }) });
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};

const HEX = c => { const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(c || '');
  return m ? '#' + [m[1], m[2], m[3]].map(n => Number(n).toString(16).padStart(2, '0')).join('').toUpperCase() : c; };

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
  await p.waitForFunction(() => typeof irPara === 'function' && typeof bd !== 'undefined' && bd
    && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(400);
  await p.evaluate(() => { trocarAbaSalao('aparencia'); const d = document.getElementById('apAvancado'); if(d) d.open = true; });
  await p.waitForTimeout(700);
  return { p, fechar: () => ctx.close() };
}
async function link(){
  const ctx = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => { const b = document.getElementById('btPrincipal'); return b && b.offsetParent; },
    null, { timeout: 15000 });
  await p.waitForTimeout(500);
  return { p, fechar: () => ctx.close() };
}
const naPrevia = p => p.evaluate(() => {
  const b = document.querySelector('#previaFone .fone-pe-b'), a = document.querySelector('#previaFone .fone-cta[data-cfg="agendar"]');
  return b ? { rot: b.textContent.trim(), fundo: getComputedStyle(b).backgroundColor, letra: getComputedStyle(b).color,
               agendar: a ? getComputedStyle(a).backgroundColor + '|' + getComputedStyle(a).backgroundImage : '' } : null; });
const noLink = p => p.evaluate(() => {
  const b = document.getElementById('btPrincipal'), a = document.querySelector('.boas .boas-cta:not(.boas-produtos)');
  return { rot: b.textContent.trim(), fundo: getComputedStyle(b).backgroundColor, letra: getComputedStyle(b).color,
           agendar: a ? getComputedStyle(a).backgroundColor + '|' + getComputedStyle(a).backgroundImage + '|' + getComputedStyle(a).color : '',
           classes: ['tem-cor-rodape', 'tem-letra-rodape'].filter(c => document.body.classList.contains(c)) }; });

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1 e 2. Na prévia, e sem escolha nada muda');
await porCores({ botao: BOTAO });
let linkAntes;
{
  const { p, fechar } = await link();
  linkAntes = await noLink(p);
  igual('no link: "Agendar horário", na Cor dos botões, sem classe nova',
    [linkAntes.rot, HEX(linkAntes.fundo), linkAntes.classes], ['Agendar horário', BOTAO, []]);
  linkAntes.palavras = await p.evaluate(() => [
    (document.querySelector('#capaServicos .cat') || {}).textContent,
    (document.getElementById('rotuloEquipe') || {}).textContent,
    (document.querySelector('.boas .boas-cta:not(.boas-produtos)') || {}).textContent].map(x => String(x || '').trim()));
  igual('e a barbearia fala "Nossos serviços", "Quem atende" e "Agendar horário" — nada de "corte"',
    linkAntes.palavras, ['Nossos serviços', 'Quem atende', 'Agendar horário']);
  await fechar();
}
let previaAntes;
{
  const { p, fechar } = await painel();
  previaAntes = await naPrevia(p);
  igual('a prévia mostra o botão de baixo: "Agendar horário", na Cor dos botões, letra branca',
    previaAntes && [previaAntes.rot, HEX(previaAntes.fundo), HEX(previaAntes.letra)], ['Agendar horário', BOTAO, '#FFFFFF']);
  igual('e as mesmas palavras do link nos títulos e no botão do Bem-vindo',
    await p.evaluate(() => ['.fone-rot[data-cfg="tituloServicos"]', '.fone-rot[data-cfg="tituloEquipe"]', '.fone-cta[data-cfg="agendar"]']
      .map(s => String((document.querySelector('#previaFone ' + s) || {}).textContent || '').trim())), linkAntes.palavras);
  const linhas = await p.evaluate(() => ['rodape', 'letraRodape'].map(k => {
    const l = document.querySelector(`#coresBotoes .cor-linha[data-chave="${k}"]`);
    return l ? [l.querySelector('b').textContent, l.querySelector('button').style.display] : null; }));
  igual('Botões e atalhos tem "Botão de baixo" e "Letra do botão de baixo", sem escolha',
    linhas, [['Botão de baixo', 'none'], ['Letra do botão de baixo', 'none']]);

  /* ══════════════════════════════════════════════════════════════════════ */
  secao('3. "Botão de baixo" muda só ele');
  await p.evaluate(() => escolherCorSolta('rodape', '#b45309'));
  await p.waitForTimeout(300);
  const pv = await naPrevia(p);
  igual('na prévia, na hora: o botão de baixo marrom com letra branca, o Agendar do Bem-vindo igual',
    [HEX(pv.fundo), HEX(pv.letra), pv.agendar], ['#B45309', '#FFFFFF', previaAntes.agendar]);

  /* ══════════════════════════════════════════════════════════════════════ */
  secao('5. Tocar nele na prévia leva às duas cores dele');
  await p.evaluate(() => document.querySelector('#previaFone .fone-pe-b').click());
  await p.waitForTimeout(400);
  igual('as linhas "Botão de baixo" e "Letra do botão de baixo" acendem',
    await p.evaluate(() => [...document.querySelectorAll('.cor-linha.ap-alvo')].map(l => l.dataset.chave)),
    ['rodape', 'letraRodape']);
  await p.evaluate(() => salvarAparencia());
  await p.waitForTimeout(1800);
  igual('salvar grava a cor', ((await cfgDe()).cores || {}).rodape, '#b45309');
  await fechar();
}
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('no link: o botão de baixo marrom, letra branca — e o Agendar do Bem-vindo como antes',
    [HEX(d.fundo), HEX(d.letra), d.agendar, d.classes],
    ['#B45309', '#FFFFFF', linkAntes.agendar, ['tem-cor-rodape', 'tem-letra-rodape']]);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. "Letra do botão de baixo"');
await porCores({ botao: BOTAO, rodape:'#FDE68A', letraRodape:'#7C2D12' });
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('fundo e letra escolhidos', [HEX(d.fundo), HEX(d.letra)], ['#FDE68A', '#7C2D12']);
  await fechar();
}
await porCores({ botao: BOTAO, rodape:'#FDE68A' });
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('só o fundo, claro: a letra vira a escura, a que lê melhor nele', HEX(d.letra) !== '#FFFFFF', true);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Cor torta vinda do banco');
await porCores({ botao: BOTAO, rodape:'url(x)', letraRodape:'red' });
{
  const { p, fechar } = await link();
  const d = await noLink(p);
  igual('é ignorada: o botão de sempre, sem classe nova', [HEX(d.fundo), HEX(d.letra), d.classes],
    [HEX(linkAntes.fundo), HEX(linkAntes.letra), []]);
  await fechar();
}

secao('Erros de JavaScript');
igual('nenhum, no painel e no link', erros, []);
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam.`);
process.exit(falhou ? 1 : 0);
