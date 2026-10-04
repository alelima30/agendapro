/* ===========================================================================
   AgendaPro — os serviços no "Novo agendamento", com foto e busca

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/servicos-form.test.mjs

   A foto do dono: uma lista de caixinhas em que, no celular, a caixinha
   ficava numa linha e o nome noutra (o `.campo label` do formulário pesava
   mais que a regra da lista). O pedido: as molduras com as fotos, como no
   link da cliente, e um Buscar para quem tem 50 serviços.

   A caixinha continua dentro de cada cartão, escondida: é ela que o resto do
   formulário lê, e por isso salvar não muda.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
const secao = t => console.log('\n' + t);

const FOTO = 'data:image/svg+xml;utf8,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="30"><rect width="40" height="30" fill="#c06"/></svg>');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function formulario(largura, extras){
  const ctx = await nav.newContext({ viewport:{ width: largura, height: 900 }, isMobile: largura < 700, hasTouch: largura < 700 });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.dismiss());
  await p.goto(BASE + 'app.html?demo=1');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && typeof abrirNovo === 'function', null, { timeout: 15000 });
  await p.waitForTimeout(1200);
  await p.evaluate(([n, foto]) => {
    try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true);
    // Zero extras = o salão pequeno: três serviços só.
    if(!n) servsAtivos().slice(3).forEach(s => { s.ativo = false; });
    const base = servsAtivos()[0];
    base.foto = foto;                                   // o primeiro com foto
    const nomes = ['Coloração', 'Hidratação profunda', 'Escova progressiva', 'Luzes', 'Manicure',
                   'Pedicure', 'Sobrancelha', 'Design de barba', 'Cauterização', 'Botox capilar'];
    for(let i = 0; i < n; i++)
      bd.servicos.push(Object.assign({}, base, { id: 'sv-extra-' + i, nome: nomes[i % nomes.length],
        foto: null, duracaoMin: 30 + i * 5, preco: 40 + i, categoria: i % 2 ? 'Unhas' : 'Cabelo' }));
    abrirNovo();
  }, [extras, FOTO]);
  await p.waitForTimeout(400);
  return { p, ctx };
}
const cartoes = p => p.evaluate(() => [...document.querySelectorAll('.lista-serv .serv-op')]
  .filter(el => el.style.display !== 'none').map(el => el.querySelector('.n').textContent.trim()));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Cartões com a foto, no celular');
{
  const { p, ctx } = await formulario(390, 10);
  const r = await p.evaluate(() => {
    const cs = [...document.querySelectorAll('.lista-serv .serv-op')];
    const a = cs[0].getBoundingClientRect(), b = cs[1].getBoundingClientRect();
    const nome = cs[0].querySelector('.n').getBoundingClientRect();
    const cx = cs[0].querySelector('input').getBoundingClientRect();
    return { lado: Math.abs(a.top - b.top) < 2 && b.left > a.right - 1,
      nomeDentro: nome.left >= a.left && nome.right <= a.right + 1 && nome.top >= a.top,
      caixinhaEscondida: cx.width <= 2 && getComputedStyle(cs[0].querySelector('input')).opacity === '0',
      foto: !!cs[0].querySelector('.serv-foto img'), inicial: (cs[1].querySelector('.serv-ini') || {}).textContent || '',
      sobra: document.documentElement.scrollWidth - innerWidth };
  });
  verdade('dois cartões lado a lado, o nome dentro do cartão, a caixinha escondida',
    r.lado && r.nomeDentro && r.caixinhaEscondida && r.sobra <= 0, JSON.stringify(r));
  igual('com foto, a foto; sem foto, a inicial do nome', [r.foto, r.inicial.length === 1], [true, true]);

  secao('2. Tocar marca, e o resto do formulário entende');
  await p.locator('.lista-serv .serv-op').nth(1).click(); await p.waitForTimeout(200);
  const m = await p.evaluate(() => {
    const c = document.querySelectorAll('.lista-serv .serv-op')[1];
    return { on: c.classList.contains('on'), marcado: c.querySelector('input').checked,
      marca: getComputedStyle(c.querySelector('.serv-marca')).backgroundColor,
      aviso: document.getElementById('avisoAg').innerText };
  });
  verdade('o cartão ganha moldura e visto, e a caixinha marca', m.on && m.marcado && m.marca !== 'rgba(255, 255, 255, 0.92)', JSON.stringify(m));
  verdade('e o aviso já diz até que horas e quanto custa', /min · R\$/.test(m.aviso), m.aviso);
  await p.locator('.lista-serv .serv-op').nth(1).click(); await p.waitForTimeout(200);
  igual('tocar de novo desmarca', await p.evaluate(() =>
    document.querySelectorAll('.lista-serv .serv-op')[1].classList.contains('on')), false);

  secao('3. Buscar, para quem tem muitos serviços');
  verdade('com mais de 6 serviços, aparece o Buscar', await p.isVisible('#fBuscaServ'));
  await p.locator('.lista-serv .serv-op', { hasText: 'Manicure' }).first().click();
  await p.fill('#fBuscaServ', 'hidra'); await p.waitForTimeout(150);
  const v = await cartoes(p);
  verdade('"hidra": só a hidratação — e a Manicure já marcada não some',
    v.every(n => /Hidrata|Manicure/.test(n)) && v.some(n => /Hidrata/.test(n)) && v.includes('Manicure'), JSON.stringify(v));
  await p.fill('#fBuscaServ', 'coloracao'); await p.waitForTimeout(150);
  verdade('sem acento acha com acento ("coloracao" → Coloração)', (await cartoes(p)).includes('Coloração'));
  await p.fill('#fBuscaServ', 'unhas'); await p.waitForTimeout(150);
  verdade('acha pela categoria também', (await cartoes(p)).length >= 2);
  await p.fill('#fBuscaServ', 'xyzabc'); await p.waitForTimeout(150);
  verdade('nada achado: diz, em vez de ficar em branco', await p.isVisible('#servNada')
    && (await cartoes(p)).join() === 'Manicure');
  await p.fill('#fBuscaServ', ''); await p.waitForTimeout(150);
  igual('apagou a busca: todos de volta', (await cartoes(p)).length, await p.evaluate(() => servsAtivos().length));

  secao('4. Salvar continua igual');
  await p.fill('#fNome', 'Cliente Cartões'); await p.fill('#fTel', '11977776666');
  // Uma terça às 15h: o salão da demonstração não abre no domingo, e o
  // encaixe pediria confirmação.
  await p.evaluate(() => { let d = hoje(); while(new Date(d + 'T12:00').getDay() !== 2) d = somarDias(d, 1);
    document.getElementById('fData').value = d; });
  await p.fill('#fInicio', '15:00');
  const antes = await p.evaluate(() => bd.agendamentos.length);
  await p.evaluate(() => salvarAgendamento()); await p.waitForTimeout(600);
  igual('o agendamento é gravado com o serviço do cartão', await p.evaluate(n => {
    const a = bd.agendamentos[bd.agendamentos.length - 1];
    return [bd.agendamentos.length === n + 1, (a.servicos || []).some(x => (x.servicoId || x) && acharServico(x.servicoId || x).nome === 'Manicure')];
  }, antes), [true, true]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Poucos serviços: sem Buscar');
{
  const { p, ctx } = await formulario(1280, 0);
  igual('com poucos serviços, a busca não aparece', await p.evaluate(() =>
    [servsAtivos().length <= 6, !document.getElementById('fBuscaServ')]), [true, true]);
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
