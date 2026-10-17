/* ===========================================================================
   AgendaPro — o que a SEGUNDA varredura do caça-bug achou na tela

   Desta vez com robôs: um que abre cada tela do painel e clica em cada
   botão (e em cada botão das janelas que abrem), e outro que faz caminhos
   ao acaso — preenche, salva, aceita ou recusa as confirmações — no painel,
   no link da cliente e na bancada. O que eles acharam, e que não volta:

     1. "Copiar" o link do salão copiava, mas no site de verdade (https) o
        botão nunca dizia "Copiado": ele procurava o botão no `event` global,
        que já não existe quando o navigator.clipboard responde.
     2. O "Tirar" de uma cliente do pacote levava o NOME dela escrito dentro
        do onclick. O escapar() não protege ali (o parser de HTML desfaz o
        &#39; antes de o JS ler): "Joana D'Arc" quebrava o botão, e um nome
        montado no link de agendamento rodava código no painel do dono.
     3. Na página da plataforma (admin.html), o "Suspender"/"Religar" levava
        o nome do salão por JSON.stringify — aspas duplas dentro de um
        atributo de aspas duplas. O botão terminava no meio e não fazia nada.

   Na demonstração (sem banco). Precisa do servidor estático:
       python3 -m http.server 8099 --directory .
       PLAYWRIGHT=.../node_modules/playwright node tests/caca-bug-2.test.mjs
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, falhas = 0;
const diz = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });

console.log('\n1. "Copiar" o link diz "Copiado" — também quando a cópia responde depois');
{
  // 127.0.0.1 é contexto seguro, como o https do site: a cópia passa pelo
  // navigator.clipboard, que responde DEPOIS do clique — o caso que quebrava.
  const ctx = await nav.newContext({ viewport: { width: 1280, height: 860 } });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: BASE.replace(/\/$/, '') });
  const p = await ctx.newPage();
  const erros = [];
  p.on('pageerror', e => erros.push(e.message));
  p.on('console', m => { if(m.type() === 'error') erros.push(m.text()); });
  await p.goto(BASE + 'app.html?demo=1'); await p.waitForTimeout(1200);
  await p.evaluate(() => { if(typeof pdFechar === 'function') try{ pdFechar(true); }catch(e){} irPara('publico'); });
  await p.waitForTimeout(500);
  const seguro = await p.evaluate(() => window.isSecureContext && !!navigator.clipboard);
  await p.click('#tela-publico button:has-text("Copiar")');
  await p.waitForTimeout(300);
  const depois = await p.evaluate(async () => ({
    texto: [...document.querySelectorAll('#tela-publico button')].map(b => b.textContent.trim()).find(t => /Copia/.test(t)),
    copiado: await navigator.clipboard.readText(),
    link: document.getElementById('linkPublico').value,
  }));
  const naArea = depois.copiado;
  diz(seguro, 'o teste roda em contexto seguro, onde a cópia é assíncrona (como no site)');
  diz(depois.texto === 'Copiado', 'o botão diz "Copiado"', 'veio ' + JSON.stringify(depois.texto));
  diz(naArea === depois.link && /agendar\.html/.test(naArea), 'e o link foi mesmo para a área de transferência', naArea);
  diz(!erros.some(e => /Falha ao copiar|event|target/.test(e)), 'sem "Falha ao copiar" no console', erros.join(' | '));
  await ctx.close();
}

console.log('\n2. "Tirar do pacote" com nome que tem apóstrofo — e com nome montado');
{
  const ctx = await nav.newContext({ viewport: { width: 1280, height: 860 } });
  const p = await ctx.newPage();
  const erros = [], dialogos = [];
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => { dialogos.push(d.message()); d.dismiss(); });
  await p.goto(BASE + 'app.html?demo=1'); await p.waitForTimeout(1200);
  for(const nome of ["Joana D'Arc", "x');window.__invadido=1;('", 'Ana "Nina" <b>Souza</b>']){
    dialogos.length = 0;
    await p.evaluate(nome => {
      if(typeof pdFechar === 'function') try{ pdFechar(true); }catch(e){}
      const venda = (bd.pacote_clientes || [])[0];
      const c = bd.clientes.find(x => x.id === venda.clienteId);
      c.nome = nome;
      irPara('pacotes');
    }, nome);
    await p.waitForTimeout(400);
    const bt = p.locator('#tela-pacotes button:has-text("Tirar")').first();
    const tem = await bt.count();
    if(tem) await bt.click();
    await p.waitForTimeout(250);
    diz(tem && dialogos.length === 1 && dialogos[0].startsWith('Tirar ' + nome + ' do pacote?'),
        `o botão funciona e a pergunta traz o nome exato — ${JSON.stringify(nome)}`, JSON.stringify(dialogos));
  }
  diz(await p.evaluate(() => window.__invadido === undefined), 'o nome montado não roda como código');
  diz(erros.length === 0, 'sem erro de JavaScript', erros.join(' | '));
  await ctx.close();
}

console.log('\n3. A plataforma: "Suspender" e "Religar" chamam com o nome certo');
{
  const ctx = await nav.newContext({ viewport: { width: 1280, height: 860 } });
  const p = await ctx.newPage();
  const erros = [];
  p.on('pageerror', e => erros.push(e.message));
  await p.route(/^https?:\/\/(?!127\.0\.0\.1)/, r => r.abort());
  await p.goto(BASE + 'admin.html'); await p.waitForTimeout(800);
  for(const [nome, status] of [['Studio Bella', 'ativo'], [`Salão "Top" D'Ávila & Cia`, 'suspenso']]){
    const r = await p.evaluate(([nome, status]) => {
      window.__chamado = null;
      window.mudarStatus = (...a) => { window.__chamado = a; };
      painel = { planos: [] };
      const t = document.createElement('table'); document.body.appendChild(t);
      t.innerHTML = '<tbody>' + linhaSalao({ id: '11111111-2222-3333-4444-555555555555', nome, slug: 'studio',
        status, plano: 'individual', assinatura: 'ativa', preco: 97, profissionais: 1, limite: 1,
        agendamentosMes: 3, ultimoAgendamento: null, origem: null }) + '</tbody>';
      t.querySelector('button.acao[onclick*="mudarStatus"]').click();
      t.remove();
      return window.__chamado;
    }, [nome, status]);
    diz(r && r[0] === '11111111-2222-3333-4444-555555555555' && r[1] === (status === 'ativo' ? 'suspenso' : 'ativo') && r[2] === nome,
        `${status === 'ativo' ? '"Suspender"' : '"Religar"'} de ${JSON.stringify(nome)} chama mudarStatus com o nome exato`, JSON.stringify(r));
  }
  diz(erros.length === 0, 'sem erro de JavaScript (antes: "Unexpected end of input" no clique)', erros.join(' | '));
  await ctx.close();
}

await nav.close();
console.log(falhas ? `\n✗ ${falhas} de ${ok + falhas} falharam.` : `\n✓ ${ok} passaram, 0 falharam`);
process.exit(falhas ? 1 : 0);
