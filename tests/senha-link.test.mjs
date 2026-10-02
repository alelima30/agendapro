/* ===========================================================================
   AgendaPro — a tela de senha nova quando o link NÃO serve

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/senha-link.test.mjs

   A foto do dono: "Este link já venceu", com o título, a frase e o link em
   três colunas espremidas — e nenhum jeito de sair dali que não fosse a tela
   de entrar do PAINEL, mesmo para a cliente que pediu pelo link do salão.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. o aviso se lê de cima para baixo, a 360 e a 390px;
     2. o texto que vem na barra de endereço não vira HTML;
     3. a cliente vê textos dela e volta para o salão; `volta` de fora é
        recusado;
     4. pedir outro link na própria tela, com a volta para o salão junto, e
        o limite de envio dito como "espere";
     5. o link com código (modelo de e-mail com {{ .TokenHash }}): abrir não
        gasta — só o Salvar; o segundo Salvar com o mesmo link é recusado; e
        o link mais velho deixa de valer quando ela pede outro;
     6. nenhum erro de JavaScript.
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
await dona.criarConta({ email:`sl-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SLUG = cr[0].slug;
const EMAIL = `cliente-${m}@t.com`, VELHA = 'senhavelha12', NOVA = 'senhanova123';
await aba().criarConta({ email: EMAIL, senha: VELHA, nome:'Maria',
  telefone:'+5551' + (900000000 + (Date.now() % 89999999)) });
const VOLTA = 'agendar.html?salao=' + SLUG;
const COM_VOLTA = BASE + '/nova-senha.html?volta=' + encodeURIComponent(VOLTA);
const pescar = () => fetch(BASE + '/_recuperacao?email=' + encodeURIComponent(EMAIL)).then(r => r.json());

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function abrir(url, largura = 390){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:860 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  const verifica = [];
  p.on('request', r => { if(/\/auth\/v1\/verify/.test(r.url())) verifica.push(r.url()); });
  await p.goto(url);
  await p.waitForTimeout(600);
  return { p, ctx, verifica };
}
const aviso = p => p.evaluate(() => document.getElementById('aviso').innerText.replace(/\s+/g, ' ').trim());
const visivel = (p, id) => p.evaluate(i => !!document.getElementById(i).offsetParent, id);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. O aviso se lê de cima para baixo');
const VENCIDO = '#error=access_denied&error_code=otp_expired'
  + '&error_description=Email+link+is+invalid+or+has+expired';
for(const largura of [360, 390]){
  const { p, ctx } = await abrir(BASE + '/nova-senha.html' + VENCIDO, largura);
  const r = await p.evaluate(() => {
    const av = document.querySelector('#aviso .aviso'), b = av.querySelector('b');
    const txt = b.nextSibling, rg = document.createRange(); rg.selectNodeContents(txt);
    const rb = b.getBoundingClientRect(), rt = rg.getClientRects()[0], ra = av.getBoundingClientRect();
    return { display: getComputedStyle(av).display,
      fraseEmbaixo: rt.top >= rb.bottom - 1, mesmaMargem: Math.abs(rt.left - rb.left) < 2,
      tituloLargo: rb.width > ra.width * 0.7, sobra: document.documentElement.scrollWidth - innerWidth };
  });
  verdade(`${largura}px: o título em cima, a frase embaixo, na mesma margem — e não em colunas`,
    r.display === 'block' && r.fraseEmbaixo && r.mesmaMargem && r.tituloLargo && r.sobra <= 0, JSON.stringify(r));
  if(largura === 390){
    const t = await aviso(p);
    verdade('diz as três causas: uma vez só, uma hora, só o último vale',
      /não vale mais/.test(t) && /uma vez só/.test(t) && /uma hora/.test(t) && /só o último vale/.test(t), t);
    igual('o formulário de senha some, e o de pedir outro aparece', [await visivel(p, 'form'), await visivel(p, 'repedir')], [false, true]);
  }
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. O texto da barra de endereço não vira HTML');
{
  const { p, ctx } = await abrir(BASE + '/nova-senha.html#error=server_error&error_description='
    + encodeURIComponent('<img src=x onerror="window.INVADIDO=1">quebrou'));
  igual('nada roda, e nenhuma imagem nasce no aviso', await p.evaluate(() =>
    [window.INVADIDO || 0, document.querySelectorAll('#aviso img').length]), [0, 0]);
  verdade('e o texto aparece como texto', /<img src=x/.test(await aviso(p)), await aviso(p));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. A cliente do link do salão');
{
  const { p, ctx } = await abrir(COM_VOLTA);
  const t = await p.evaluate(() => ({ sub: document.getElementById('sub').textContent,
    volta: document.getElementById('voltarLink').getAttribute('href'),
    rotulo: document.getElementById('voltarLink').textContent }));
  igual('textos dela, e o caminho de volta é o salão', [/link do salão/.test(t.sub), t.volta, t.rotulo],
    [true, VOLTA, 'Voltar para o salão']);
  verdade('sem o link do e-mail: "Falta o link", e o pedido ali mesmo', /Falta o link do e-mail/.test(await aviso(p))
    && await visivel(p, 'repedir'));
  await ctx.close();

  const fora = await abrir(BASE + '/nova-senha.html?volta=' + encodeURIComponent('https://golpe.example/agendar.html?salao=x'));
  igual('`volta` para fora do site é ignorado: textos e volta do painel', await fora.p.evaluate(() =>
    [document.getElementById('voltarLink').getAttribute('href'), /painel/.test(document.getElementById('sub').textContent)]),
    ['entrar.html', true]);
  await fora.ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Pedir outro link na própria tela');
{
  const { p, ctx } = await abrir(COM_VOLTA + VENCIDO);
  const pedidos = [];
  p.on('request', r => { if(/\/auth\/v1\/recover/.test(r.url())) pedidos.push(decodeURIComponent(r.url())); });
  await p.fill('#emailNovo', 'maria@');
  await p.click('#btRepedir'); await p.waitForTimeout(300);
  verdade('e-mail incompleto: avisa, e não pede nada', /Confira o e-mail/.test(await aviso(p)) && !pedidos.length);
  await p.fill('#emailNovo', EMAIL);
  await p.click('#btRepedir'); await p.waitForTimeout(900);
  verdade('o link novo também volta para o salão', pedidos.length === 1
    && pedidos[0].includes('nova-senha.html?volta=' + encodeURIComponent(VOLTA)), pedidos.join(' | '));
  const t = await aviso(p);
  verdade('e a resposta não diz se o e-mail existe, e manda usar o mais recente',
    /Se houver conta com/.test(t) && /mais recente/.test(t), t);
  await ctx.close();

  const lim = await abrir(COM_VOLTA + VENCIDO);
  await lim.p.route('**/auth/v1/recover**', r => r.fulfill({ status: 429, contentType: 'application/json',
    body: JSON.stringify({ code: 429, error_code: 'over_email_send_rate_limit',
      msg: 'For security purposes, you can only request this after 35 seconds.' }) }));
  await lim.p.fill('#emailNovo', EMAIL);
  await lim.p.click('#btRepedir'); await lim.p.waitForTimeout(600);
  const dito = await aviso(lim.p);
  verdade('no limite de envio: "espere 35 segundos", e não "confira a conexão"',
    /Espere 35 segundos/.test(dito) && !/conex/.test(dito), dito);
  await lim.ctx.close();

  /* O limite do e-mail padrão do Supabase (2 por hora) vem sem segundos e
     com outra frase — é o que acontece de verdade sem SMTP próprio. */
  const hora = await abrir(COM_VOLTA + VENCIDO);
  await hora.p.route('**/auth/v1/recover**', r => r.fulfill({ status: 429, contentType: 'application/json',
    body: JSON.stringify({ code: 429, error_code: 'over_email_send_rate_limit', msg: 'Too many emails' }) }));
  await hora.p.fill('#emailNovo', EMAIL);
  await hora.p.click('#btRepedir'); await hora.p.waitForTimeout(600);
  const dito2 = await aviso(hora.p);
  verdade('no limite por hora: "espere alguns minutos", pelo código, sem depender da frase',
    /Espere alguns minutos/.test(dito2) && !/conex/.test(dito2), dito2);
  await hora.ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. O link com código: abrir não gasta');
{
  await fetch(BASE + '/auth/v1/recover?redirect_to=' + encodeURIComponent(COM_VOLTA), { method:'POST',
    headers:{ 'Content-Type':'application/json', apikey:'k' }, body: JSON.stringify({ email: EMAIL }) });
  const velho = (await pescar()).token_hash;
  await fetch(BASE + '/auth/v1/recover?redirect_to=' + encodeURIComponent(COM_VOLTA), { method:'POST',
    headers:{ 'Content-Type':'application/json', apikey:'k' }, body: JSON.stringify({ email: EMAIL }) });
  const hash = (await pescar()).token_hash;
  verdade('a bancada deu dois códigos diferentes', !!velho && !!hash && velho !== hash);
  const LINK = COM_VOLTA + '#token_hash=' + hash + '&type=recovery';

  const A = await abrir(LINK);
  igual('abrir: o formulário aparece, o código sai da barra, e NADA é gasto',
    [await visivel(A.p, 'form'), await A.p.evaluate(() => location.hash), A.verifica.length], [true, '', 0]);
  const B = await abrir(LINK);            // o antivírus, ou ela abrindo duas vezes
  igual('abrir de novo (antivírus, ou ela mesma): continua valendo', [await visivel(B.p, 'form'), B.verifica.length], [true, 0]);

  await A.p.fill('#senha', NOVA); await A.p.fill('#senha2', NOVA);
  await A.p.click('#btSalvar');
  await A.p.waitForURL(u => /agendar\.html\?salao=/.test(String(u)), { timeout: 8000 }).catch(() => {});
  await A.p.waitForTimeout(1500);
  igual('salvar gasta o código, troca a senha e volta para o salão, já dentro',
    [A.verifica.length, new URL(A.p.url()).pathname + new URL(A.p.url()).search,
     await A.p.evaluate(() => !!(window.Dados && Dados.sessaoAtual && Dados.sessaoAtual()))],
    [1, '/' + VOLTA, true]);
  let velhaEntra = true, novaEntra = false;
  try{ await aba().entrar({ email: EMAIL, senha: VELHA }); }catch(e){ velhaEntra = false; }
  try{ await aba().entrar({ email: EMAIL, senha: NOVA }); novaEntra = true; }catch(e){}
  igual('a senha nova entra, a velha não', [novaEntra, velhaEntra], [true, false]);

  await B.p.fill('#senha', 'outrasenha99'); await B.p.fill('#senha2', 'outrasenha99');
  await B.p.click('#btSalvar'); await B.p.waitForTimeout(1200);
  verdade('o mesmo link, salvo de novo noutra aba: "não vale mais", com o pedido ali',
    /não vale mais/.test(await aviso(B.p)) && await visivel(B.p, 'repedir') && !(await visivel(B.p, 'form')), await aviso(B.p));
  await A.ctx.close(); await B.ctx.close();

  const V = await abrir(COM_VOLTA + '#token_hash=' + velho + '&type=recovery');
  await V.p.fill('#senha', 'outrasenha99'); await V.p.fill('#senha2', 'outrasenha99');
  await V.p.click('#btSalvar'); await V.p.waitForTimeout(1200);
  verdade('o link do e-mail mais velho deixou de valer quando ela pediu outro',
    /só o último vale/.test(await aviso(V.p)), await aviso(V.p));
  await V.ctx.close();

  const R = await abrir(BASE + '/index.html#token_hash=' + hash + '&type=recovery');
  await R.p.waitForTimeout(800);
  igual('caindo na raiz do site, o link com código ainda chega à tela de senha', new URL(R.p.url()).pathname, '/nova-senha.html');
  await R.ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
