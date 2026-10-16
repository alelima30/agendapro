/* ===========================================================================
   A página dos anúncios (conheca.html)

   Separada da raiz de propósito: a raiz continua levando ao login. Aqui se
   confere o que faz a página vender sem mentir e sem perder o rastro de quem
   chegou:
     · os preços vêm do banco (tabela `planos`) e, sem banco, ficam os de
       reserva — nunca um cartão vazio;
     · todo botão leva ao cadastro com os parâmetros do anúncio, e o cadastro
       já marca "Como você nos conheceu?";
     · a barra fixa do celular só aparece depois que o botão do topo sai da
       tela;
     · sem Pixel/GA configurados, nada de fora é carregado.

   O banco é simulado interceptando a chamada (page.route): o teste não
   depende de rede nem do Supabase de verdade.

       python3 -m http.server 8099 --directory .
       PLAYWRIGHT=.../node_modules/playwright node tests/conheca.test.mjs
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, falhas = 0;
const diz = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });

/* O "banco": a mesma forma que o PostgREST devolve para a tabela `planos`. */
const PLANOS = (essencial) => [
  { codigo:'gratuito',   nome:'Grátis',    preco_mes:0,     max_profissionais:1,  ordem:0, recursos:{ agendamentos_mes:25, lembrete_whatsapp:false } },
  { codigo:'trial',      nome:'Teste grátis', preco_mes:0,  max_profissionais:1,  ordem:1, recursos:{ lembrete_whatsapp:true, mensagens_mes:100, max_clientes:500 } },
  { codigo:'basico',     nome:'Básico',    preco_mes:44.9,  max_profissionais:1,  ordem:2, recursos:{ lembrete_whatsapp:false, mensagens_mes:0, max_clientes:500 } },
  { codigo:'individual', nome:'Essencial', preco_mes:essencial, max_profissionais:1, ordem:2, recursos:{ lembrete_whatsapp:true, mensagens_mes:500, max_clientes:500 } },
  { codigo:'duo',        nome:'Dupla',     preco_mes:157,   max_profissionais:2,  ordem:3, recursos:{ lembrete_whatsapp:true, mensagens_mes:800, max_clientes:1000 } },
  { codigo:'salao',      nome:'Salão',     preco_mes:497,   max_profissionais:12, ordem:6, recursos:{ lembrete_whatsapp:true, mensagens_mes:3600, max_clientes:5000 } },
];

async function abrir({ largura, banco, busca = '' }){
  const ctx = await nav.newContext({ viewport:{ width: largura, height: 800 },
    isMobile: largura < 700, hasTouch: largura < 700 });
  const p = await ctx.newPage();
  const erros = [], deFora = [];
  p.on('pageerror', e => erros.push(e.message));
  p.on('request', r => { if(/facebook|googletagmanager|google-analytics/.test(r.url())) deFora.push(r.url()); });
  await p.route('**/rest/v1/planos**', rota => banco
    ? rota.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(banco) })
    : rota.abort());
  await p.goto(BASE + 'conheca.html' + busca);
  await p.waitForTimeout(900);
  return { ctx, p, erros, deFora };
}
const planosNaTela = p => p.evaluate(() => [...document.querySelectorAll('.lp-plano')].map(x =>
  x.querySelector('h3').textContent.trim() + ' ' + x.querySelector('.lp-preco').firstChild.textContent.trim()));

console.log('\nOs preços');
{
  const { ctx, p, erros } = await abrir({ largura: 1280, banco: PLANOS(99) });
  const planos = await planosNaTela(p);
  diz(planos.join() === 'Essencial R$ 99,Dupla R$ 157,Salão R$ 497',
      'vêm do banco: mudar o preço no Supabase muda a página (e o Básico/Grátis não viram cartão)', planos.join(' | '));
  const menores = await p.evaluate(() => document.getElementById('planosMenores').textContent.replace(/\s+/g, ' '));
  diz(/R\$ 44,90/.test(menores) && /até 25 agendamentos/.test(menores),
      'o Básico e o Grátis saem do banco também', menores.trim());
  diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));
  await ctx.close();
}
{
  const { ctx, p } = await abrir({ largura: 1280, banco: null });
  const planos = await planosNaTela(p);
  diz(planos.length === 5 && planos[0] === 'Essencial R$ 97' && planos[4] === 'Salão R$ 497',
      'sem banco, ficam os de reserva — a seção de preços nunca sai vazia', planos.join(' | '));
  await ctx.close();
}

console.log('\nOs botões levam o anúncio até o cadastro');
{
  const { ctx, p, deFora } = await abrir({ largura: 375, banco: PLANOS(97),
    busca: '?utm_source=instagram&utm_campaign=lancamento&fbclid=abc123&lixo=<x>' });
  const links = await p.evaluate(() => [...document.querySelectorAll('[data-cta], .lp-plano a')].map(a => a.getAttribute('href')));
  const alvo = new URL(links[0], BASE);
  diz(links.length >= 6 && links.every(h => h === links[0]),
      `todos os botões de teste (${links.length}) vão para o mesmo endereço`);
  diz(alvo.pathname.endsWith('/criar.html') && alvo.searchParams.get('utm_source') === 'instagram'
      && alvo.searchParams.get('utm_campaign') === 'lancamento' && alvo.searchParams.get('fbclid') === 'abc123'
      && alvo.searchParams.get('origem') === 'pagina' && !alvo.searchParams.has('lixo'),
      'o cadastro recebe utm_*, fbclid e a origem — e só eles', links[0]);
  diz(deFora.length === 0, 'sem Pixel/GA configurados, nada de fora é carregado', deFora.join(' | '));

  await p.goto(new URL(links[0], BASE).href); await p.waitForTimeout(800);
  const origem = await p.evaluate(() => document.getElementById('fOrigem').value);
  diz(origem === 'Instagram', 'e o cadastro já marca "Como você nos conheceu?" = Instagram', origem);
  await ctx.close();
}
{
  const ctx = await nav.newContext({ viewport:{ width: 375, height: 800 } });
  const p = await ctx.newPage();
  await p.goto(BASE + 'criar.html?utm_source=tiktok'); await p.waitForTimeout(600);
  const o1 = await p.evaluate(() => document.getElementById('fOrigem').value);
  await p.goto(BASE + 'criar.html'); await p.waitForTimeout(600);
  const o2 = await p.evaluate(() => document.getElementById('fOrigem').value);
  diz(o1 === 'Anúncio: tiktok' && o2 === '',
      'origem desconhecida vira "Anúncio: …"; sem parâmetro, o cadastro fica como sempre foi', `${o1} / "${o2}"`);
  await ctx.close();
}

console.log('\nNo celular');
{
  const { ctx, p, erros } = await abrir({ largura: 375, banco: PLANOS(97) });
  const topo = await p.evaluate(() => ({
    vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    barra: document.getElementById('barra').classList.contains('on'),
    h1: document.querySelector('h1').textContent.trim(),
  }));
  diz(topo.vaza === 0, 'a página não rola para o lado', `sobram ${topo.vaza}px`);
  diz(/agenda cheia/i.test(topo.h1) && /WhatsApp/.test(topo.h1), 'a promessa está no título', topo.h1);
  diz(!topo.barra, 'no topo, a barra fixa fica escondida (o botão do herói está à vista)');

  // Rola a página inteira devagar: as imagens com loading=lazy precisam carregar.
  await p.evaluate(async () => { for(let y = 0; y < document.body.scrollHeight; y += 500){ window.scrollTo(0, y); await new Promise(r => setTimeout(r, 60)); } });
  await p.waitForTimeout(600);
  const fundo = await p.evaluate(() => ({
    barra: document.getElementById('barra').classList.contains('on'),
    imgs: [...document.images].filter(i => i.offsetParent !== null).map(i => [i.getAttribute('src'), i.naturalWidth > 0, !!i.alt]),
  }));
  diz(fundo.barra, 'depois de passar pelo topo, a barra "Testar 7 dias grátis" aparece');
  diz(fundo.imgs.length >= 3 && fundo.imgs.every(([, carregou]) => carregou),
      'todas as imagens visíveis carregam (também as que esperam a rolagem)', JSON.stringify(fundo.imgs.filter(x => !x[1])));
  diz(fundo.imgs.every(([, , alt]) => alt), 'e toda imagem tem texto alternativo');

  const faixa = await p.evaluate(() => { const l = document.getElementById('listaPlanos');
    return { rola: l.scrollWidth > l.clientWidth, estilo: getComputedStyle(l).overflowX }; });
  diz(faixa.rola && faixa.estilo === 'auto', 'os planos ficam numa faixa que se arrasta de lado', JSON.stringify(faixa));

  await p.fill('#contaValor', '100'); await p.fill('#contaFaltas', '3'); await p.waitForTimeout(100);
  const conta = await p.evaluate(() => document.getElementById('contaRes').textContent.replace(/\s+/g, ' '));
  diz(/R\$ 300 por mês/.test(conta) && /Essencial custa R\$ 97/.test(conta),
      'a conta das faltas faz a conta com os números da pessoa', conta.trim());

  const demos = await p.evaluate(() => [...document.querySelectorAll('a[target="_blank"]')].map(a => a.getAttribute('href')));
  diz(demos.includes('agendar.html?salao=studio-bella&demo=1') && demos.includes('app.html?demo=1'),
      'as demonstrações abrem em outra aba (link da cliente e painel)', demos.join(' | '));
  const texto = await p.evaluate(() => document.body.innerText);
  diz(!/undefined|NaN|\$\{/.test(texto), 'nenhum "undefined", "NaN" ou ${…} escapou para o texto');
  diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));
  await ctx.close();
}

console.log('\nNo computador');
{
  const { ctx, p } = await abrir({ largura: 1366, banco: PLANOS(97) });
  await p.evaluate(() => window.scrollTo(0, 3000)); await p.waitForTimeout(300);
  const pc = await p.evaluate(() => ({
    barra: getComputedStyle(document.getElementById('barra')).display,
    botoes: [...document.querySelectorAll('.lp-plano .lp-bt')].map(b => Math.round(b.getBoundingClientRect().height)),
  }));
  diz(pc.barra === 'none', 'a barra fixa é só do celular');
  diz(pc.botoes.every(h => h <= 56), 'o botão de cada plano cabe numa linha', pc.botoes.join(', '));
  await ctx.close();
}

console.log('\nA raiz do site continua levando ao login');
{
  const raiz = fs.readFileSync(path.join(RAIZ, 'index.html'), 'utf8');
  diz(/http-equiv="refresh" content="0; url=entrar\.html"/.test(raiz) && !/conheca/.test(raiz),
      'index.html segue indo para entrar.html — a página de anúncio é à parte');
}

await nav.close();
console.log(falhas ? `\n✗ ${falhas} de ${ok + falhas} falharam.` : `\n✓ ${ok} passaram, 0 falharam`);
process.exit(falhas ? 1 : 0);
