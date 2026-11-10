/* ===========================================================================
   AgendaPro — nenhum texto espremido no celular, em nenhuma tela do painel

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/textos-celular.test.mjs

   ── O RELATO ───────────────────────────────────────────────────────────────
   Print de Aparência → "Pagamentos, Horários e Informações": "Cor da moldura"
   quebrando uma palavra por linha, com o código HEX encostado no nome. E
   depois: "Todos estão assim, precisando de uma correção dos textos pelo
   celular". Estavam: medido a 390px, o nome de TODAS as linhas de cor tinha
   26px de largura ("Fundo da página" em três linhas, a explicação em
   quatorze). Quadrado, nome, código e "automática" não cabem numa fileira.
   Na mesma varredura, os atalhos de período do Relatório ("Este mês",
   "Mês passado"…) quebravam em duas linhas cada um.

   ── O QUE ESTE ARQUIVO MEDE, A 360 E A 390PX ───────────────────────────────
     1. ESPREMIDO: texto de duas palavras ou mais com uma palavra por linha,
        numa caixa com menos de 110px. (Duas palavras em duas linhas com
        espaço sobrando — "Destaques clarinhos" a 360px — é quebra normal.)
     2. ENCAVALADO: duas peças da mesma fileira uma em cima da outra.
     3. FORA DA TELA: algo passando da borda direita.
     4. COM A LETRA AMPLIADA do celular (30% maior), na Aparência: nenhum
        nome de cor espremido e nenhum código HEX cortado.
   Em cada tela do painel e nas três abas de Meu negócio, com todas as cores
   da Aparência escolhidas — para o "automática" aparecer em todas as linhas,
   que é o pior caso.
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
const d = novaAba();
await d.criarConta({ email:`txc-${marca}@teste.com`, senha:'minhasenhaboa', nome:'Rita Alves',
  telefone:'+5511' + (100000000 + Math.floor(Math.random() * 89999999)) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão Megatop ' + marca, p_tipo:'salao',
  p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
const escolhida = '#3A2A2E';
const cores = Object.fromEntries(['papel','card','titulo','texto','discreto','destaque','botao','secundaria',
  'icone','iconeDestaque','borda','moldura','produtos','nomeSalao','rua','lugar','subtitulo','horario',
  'bemVindo','convite','letraAgendar','letraProdutos','legenda','tituloServicos','nomeServico','descServico',
  'precoServico','duracao','verTodosServicos','tituloProdutos','nomeProduto','precoProduto','verTodosProdutos',
  'tituloEquipe','nomeEquipe'].map(k => [k, ['papel','card','secundaria'].includes(k) ? '#FBF4F1' : escolhida]));
await d.atualizar('saloes', SALAO, { cfg:{ cor:'#7C3AED', pagamentos:{ formas:['pix'] }, cores,
  atalhos:{ estilo:'borda', moldura:'#C8A33C', fundo:'#FDF2D0',
            cores:{ pagamentos:escolhida, horarios:escolhida, informacoes:escolhida } } } });

const TELAS = ['hoje','agenda','dashboard','clientes','servicos','produtos','pacotes','equipe','cupons',
  'procedimentos','relatorios','aniversarios','plano','publico','salao:dados','salao:notificacoes','salao:aparencia'];

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
for(const larg of [360, 390]){
  secao(`${larg}px`);
  const ctx = await nav.newContext({ viewport:{ width:larg, height:800 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(`${larg}px: ` + e.message));
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, d.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function' && typeof bd !== 'undefined' && bd
    && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
  for(const tela of TELAS){
    const [k, aba] = tela.split(':');
    await p.evaluate(([k, aba]) => { irPara(k); if(aba) trocarAbaSalao(aba);
      document.querySelectorAll('details').forEach(x => x.open = true); }, [k, aba]);
    await p.waitForTimeout(700);
    const achados = await p.evaluate(k => {
      const raiz = document.getElementById('tela-' + k);
      if(!raiz || !raiz.classList.contains('on')) return ['a tela não abriu'];
      const vis = e => e.offsetParent && e.getBoundingClientRect().width > 0;
      const nome = e => (e.id ? '#' + e.id : '') || String(e.className || e.tagName).split(' ')[0];
      const out = [];
      for(const e of raiz.querySelectorAll('b, span, label, p, button, div, small, h4, a')){
        if(!vis(e)) continue;
        if([...e.childNodes].some(n => n.nodeType === 1 && getComputedStyle(n).display !== 'inline')) continue;
        const pal = e.textContent.replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
        if(pal.length < 2) continue;
        const rg = document.createRange(); rg.selectNodeContents(e);
        const linhas = new Set([...rg.getClientRects()].filter(x => x.width > 0).map(x => Math.round(x.top))).size;
        const w = e.getBoundingClientRect().width;
        if(linhas >= pal.length && w < 110)
          out.push(`espremido: "${pal.join(' ').slice(0, 40)}" em ${Math.round(w)}px, ${linhas} linhas`);
      }
      for(const pai of raiz.querySelectorAll('*')){
        if(!vis(pai) || !/flex|grid/.test(getComputedStyle(pai).display)) continue;
        const f = [...pai.children].filter(c => vis(c) && getComputedStyle(c).position !== 'absolute')
          .map(c => [c, c.getBoundingClientRect()]);
        for(let i = 0; i < f.length; i++) for(let j = i + 1; j < f.length; j++){
          const [a, ra] = f[i], [b, rb] = f[j];
          const x = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left);
          const y = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top);
          if(x > 2 && y > 2) out.push(`encavalado: ${nome(a)} × ${nome(b)} em ${nome(pai)}`);
        }
      }
      for(const e of raiz.querySelectorAll('*')){
        if(!vis(e) || getComputedStyle(e).position === 'fixed') continue;
        if(e.closest('.ap-previa, .fone, .grade, .semana, [style*="overflow"]')) continue;
        const r = e.getBoundingClientRect();
        if(r.right > innerWidth + 1) out.push(`fora da tela: ${nome(e)} até ${Math.round(r.right)}px`);
      }
      return [...new Set(out)];
    }, k);
    achados.length ? nao(`${tela}: texto inteiro, nada encavalado, nada fora da tela`, achados.slice(0, 6).join('\n      '))
                   : ok(`${tela}: texto inteiro, nada encavalado, nada fora da tela`);
  }
  await ctx.close();
}

/* ── COM A LETRA AMPLIADA ──────────────────────────────────────────────────
   O segundo print do dono veio de um celular com "Tamanho da fonte" grande:
   a explicação de "Títulos" em onze linhas, e o código HEX de TODAS as linhas
   cortado ("#F6EFE1" virando "#F6EFE" e meio) — a caixa tinha largura fixa.
   Aqui cada texto da Aparência fica 30% maior, como o celular faz. */
secao('410px com a letra 30% maior (Aparência)');
{
  const ctx = await nav.newContext({ viewport:{ width:410, height:820 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('letra grande: ' + e.message));
  await p.addInitScript(([b, s]) => {
    window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BASE, d.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof irPara === 'function' && typeof bd !== 'undefined' && bd
    && Array.isArray(bd.saloes), null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); irPara('salao'); });
  await p.waitForTimeout(400);
  await p.evaluate(() => { trocarAbaSalao('aparencia'); document.querySelectorAll('details').forEach(x => x.open = true); });
  await p.waitForTimeout(900);
  await p.evaluate(() => { const els = [...document.querySelectorAll('#tela-salao *')];
    const tam = els.map(e => parseFloat(getComputedStyle(e).fontSize));
    els.forEach((e, i) => e.style.fontSize = (tam[i] * 1.3) + 'px'); });
  await p.waitForTimeout(400);
  const r = await p.evaluate(() => {
    const linhas = [...document.querySelectorAll('#tela-salao .cor-linha')].filter(l => l.offsetParent);
    const apertadas = linhas.filter(l => {
      const t = l.querySelector('.cor-linha-txt');
      return t && t.getBoundingClientRect().width < 110; }).map(l => l.dataset.chave || l.querySelector('input').id);
    const hex = [...document.querySelectorAll('#tela-salao .cor-hex')].filter(h => h.offsetParent);
    const cortados = hex.filter(h => h.scrollWidth > h.clientWidth + 1).map(h => h.value);
    return { linhas: linhas.length, apertadas, hex: hex.length, cortados };
  });
  r.linhas > 30 && !r.apertadas.length ? ok(`as ${r.linhas} linhas de cor com o nome inteiro (110px ou mais)`)
    : nao('as linhas de cor com o nome inteiro', JSON.stringify(r.apertadas));
  r.hex > 30 && !r.cortados.length ? ok(`os ${r.hex} códigos HEX inteiros, sem corte`)
    : nao('os códigos HEX inteiros, sem corte', JSON.stringify(r.cortados.slice(0, 6)));
  await ctx.close();
}

secao('Erros de JavaScript');
erros.length ? nao('nenhum', erros.join(' | ')) : ok('nenhum');
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam.`);
process.exit(falhou ? 1 : 0);
