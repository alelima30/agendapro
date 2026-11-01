/* ===========================================================================
   AgendaPro — a cliente se cadastra pelo link, sem agendar

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/cadastro-link-tela.test.mjs

   O pedido: "no link tem como o cliente fazer o cadastro sem agendar? Aí ele
   se cadastra e depois eu coloco ele no pacote."

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. o link de cadastro (`&cadastro=1`) abre em "Faça seu cadastro"; criar
        a conta faz a ficha no salão, marcada "pelo link", e mostra "Cadastro
        feito"; daí ela marca um horário se quiser;
     2. quem já tem conta entra pelo mesmo link: a ficha do balcão (mesmo
        WhatsApp e primeiro nome) é ligada, sem ficha nova;
     3. a volta do e-mail de confirmação: `cadastro=1` mostra o cadastro
        feito; `conta=nova` só faz a ficha, calado; o aviso sai do endereço;
     4. criar a conta pela tela de conta de sempre também faz a ficha, e volta
        para onde ela estava;
     5. entrar logada pelo link de sempre NÃO cria ficha (abrir o link de um
        salão não é se cadastrar nele);
     6. o painel: a marca "cadastrou pelo link" em Clientes, e o botão "Link
        de cadastro" com o link, copiar e mandar no WhatsApp;
     7. a 360px cabe; nenhum erro de JavaScript.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import pgLib from './pg.mjs';

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

const banco = new pgLib.Client({ host: process.env.PGHOST || '/tmp',
  port: +(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const fichas = async () => (await banco.query(
  `select nome, telefone, perfil_id, pelo_link from public.clientes where salao_id = $1 order by nome`, [SALAO])).rows;

const m = Date.now().toString(36) + Math.floor(Math.random() * 1000);
const n8 = String(Date.now() % 100000000).padStart(8, '0');
const tel = d => '51' + d + n8.slice(1);     // DDD + 9 dígitos, um por pessoa
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;
const TEL = { maria: tel('91'), lu: tel('92'), carla: tel('93'), dani: tel('94'), eva: tel('95'), fabi: tel('96') };

const dona = aba();
await dona.criarConta({ email:`cl-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:60,
  intervaloMin:0, preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA } });
// A ficha que o balcão já tinha.
await dona.inserir('clientes', { salaoId: SALAO, nome:'Maria Souza', telefone: TEL.maria });

// Uma conta pronta, feita fora do navegador (o "já tenho conta" e a volta do e-mail).
async function conta(nome, t, email){
  const d = aba();
  await d.criarConta({ email, senha:'senhaboa123', nome, telefone:'+55' + t });
  return d.sessao();
}

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function aparelho(sufixo, largura = 390, telaEsperada = null){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.accept());
  await p.goto(BASE + '/agendar.html?salao=' + SLUG + sufixo);
  await p.waitForFunction(t => typeof tela !== 'undefined' && (t ? tela === t : tela !== 'saloes')
    && typeof salao !== 'undefined' && salao, telaEsperada, { timeout: 15000 });
  await p.waitForTimeout(1500);
  return { p, ctx };
}
const estado = p => p.evaluate(() => ({ tela,
  titulo: (document.querySelector('#p-' + tela + ' h2') || {}).textContent || '',
  texto: ((document.getElementById(tela === 'cadastro' ? 'cadastroTexto' : 'contaSub') || {}).textContent || '').replace(/\s+/g, ' ').trim(),
  bp: document.getElementById('btPrincipal').textContent.trim(),
  bs: document.getElementById('btSecundario').offsetParent ? document.getElementById('btSecundario').textContent.trim() : '',
  endereco: location.search }));
const cabe = p => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. O link de cadastro: a conta nova vira ficha no salão');
{
  const { p, ctx } = await aparelho('&cadastro=1', 360, 'conta');
  const e = await estado(p);
  igual('abre direto em "Faça seu cadastro", com o nome do salão', [e.tela, e.titulo, e.bp,
    e.texto.includes('Salão Megatop') && /sem precisar marcar horário/.test(e.texto)],
    ['conta', 'Faça seu cadastro', 'Fazer meu cadastro', true]);
  igual('o aviso sai do endereço (recarregar não repete)', e.endereco, '?salao=' + SLUG);
  verdade('a 360px a tela de cadastro cabe', await cabe(p));
  await p.fill('#cNome', 'Luana Teste');
  await p.fill('#cTel', masc(TEL.lu));
  await p.fill('#cEmail', `lu-${m}@t.com`);
  await p.fill('#cSenha', 'senhaboa123');
  await p.click('#btPrincipal');
  await p.waitForFunction(() => tela === 'cadastro', null, { timeout: 10000 }).catch(() => {});
  const f = await estado(p);
  igual('"Cadastro feito", pelo nome, com o salão', [f.tela, f.titulo,
    f.texto.startsWith('Pronto, Luana!') && f.texto.includes('Salão Megatop'), f.bp, f.bs],
    ['cadastro', 'Cadastro feito', true, 'Marcar um horário', 'Ver o salão']);
  verdade('a 360px o cadastro feito cabe', await cabe(p));
  const lu = (await fichas()).find(x => x.nome === 'Luana Teste');
  igual('no banco: a ficha nasceu, ligada à conta, com o WhatsApp sem o 55 e a marca',
    lu && [lu.telefone, !!lu.perfil_id, lu.pelo_link], [TEL.lu, true, true]);
  await p.click('#btPrincipal'); await p.waitForTimeout(500);
  igual('"Marcar um horário" leva aos serviços, e o voltar vai para a capa', await p.evaluate(() =>
    [tela, (voltar(), tela)]), ['servico', 'capa']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Quem já tem conta entra pelo mesmo link: liga a ficha do balcão');
{
  await conta('Maria', TEL.maria, `maria-${m}@t.com`);
  // A conta acima nasceu fora do link: só ela, sem ficha ligada ainda.
  const { p, ctx } = await aparelho('&cadastro=1', 390, 'conta');
  await p.click('#abaEntrar'); await p.waitForTimeout(200);
  const e = await estado(p);
  igual('na aba Entrar, o título diz para que é', [e.titulo, e.bp], ['Entre para se cadastrar', 'Entrar']);
  await p.fill('#cEmail', `maria-${m}@t.com`); await p.fill('#cSenha', 'senhaboa123');
  await p.click('#btPrincipal');
  await p.waitForFunction(() => tela === 'cadastro', null, { timeout: 10000 }).catch(() => {});
  const f = await estado(p);
  igual('"Você já tinha cadastro"', [f.tela, f.titulo], ['cadastro', 'Você já tinha cadastro']);
  const lista = await fichas();
  const marias = lista.filter(x => x.telefone === TEL.maria);
  igual('a ficha "Maria Souza" do balcão foi ligada, sem ficha nova e sem a marca',
    marias.map(x => [x.nome, !!x.perfil_id, x.pelo_link]), [['Maria Souza', true, false]]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. A volta do e-mail de confirmação');
{
  const s = await conta('Carla Dias', TEL.carla, `carla-${m}@t.com`);
  const { p, ctx } = await aparelho('&cadastro=1#access_token=' + s.token + '&refresh_token=' + (s.refresh || '')
    + '&expires_in=3600&token_type=bearer&type=signup', 390, 'cadastro');
  const e = await estado(p);
  igual('cadastro=1: volta já em "Cadastro feito", e o endereço fica limpo',
    [e.tela, e.titulo, e.endereco, await p.evaluate(() => location.hash)], ['cadastro', 'Cadastro feito', '?salao=' + SLUG, '']);
  const carla = (await fichas()).find(x => x.nome === 'Carla Dias');
  igual('a ficha dela nasceu, marcada', carla && [!!carla.perfil_id, carla.pelo_link], [true, true]);
  await ctx.close();

  const s2 = await conta('Dani Rocha', TEL.dani, `dani-${m}@t.com`);
  const b = await aparelho('&conta=nova#access_token=' + s2.token + '&refresh_token=' + (s2.refresh || '')
    + '&expires_in=3600&token_type=bearer&type=signup', 390, 'capa');
  await b.p.waitForTimeout(1000);
  const e2 = await estado(b.p);
  igual('conta=nova: fica na capa, e o endereço fica limpo', [e2.tela, e2.endereco], ['capa', '?salao=' + SLUG]);
  const dani = (await fichas()).find(x => x.nome === 'Dani Rocha');
  igual('e a ficha nasceu, calada', dani && [!!dani.perfil_id, dani.pelo_link], [true, true]);
  await b.ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Criar a conta pela tela de sempre também faz a ficha');
{
  const pedidos = [];
  const { p, ctx } = await aparelho('', 390, 'capa');
  p.on('request', r => { if(/\/auth\/v1\/signup/.test(r.url())) pedidos.push(r.url()); });
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#btEu'); await p.waitForTimeout(300);
  await p.click('#abaCriar'); await p.waitForTimeout(200);
  const e = await estado(p);
  igual('a tela de conta de sempre não fala em cadastro', [e.titulo, e.bp], ['Criar conta', 'Criar conta']);
  await p.fill('#cNome', 'Eva Lima'); await p.fill('#cTel', masc(TEL.eva));
  await p.fill('#cEmail', `eva-${m}@t.com`); await p.fill('#cSenha', 'senhaboa123');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('volta para onde estava (os serviços)', await p.evaluate(() => tela), 'servico');
  const eva = (await fichas()).find(x => x.nome === 'Eva Lima');
  igual('e a ficha nasceu', eva && [!!eva.perfil_id, eva.pelo_link], [true, true]);
  verdade('a volta do e-mail leva o aviso de conta nova',
    pedidos.length === 1 && decodeURIComponent(pedidos[0]).includes('agendar.html?salao=' + SLUG + '&conta=nova'),
    pedidos.join(' | '));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Abrir o link de sempre, logada, não cadastra');
{
  const s = await conta('Fabi Melo', TEL.fabi, `fabi-${m}@t.com`);
  const { p, ctx } = await aparelho('#access_token=' + s.token + '&refresh_token=' + (s.refresh || '')
    + '&expires_in=3600&token_type=bearer&type=signup', 390, 'capa');
  await p.waitForTimeout(1000);
  igual('fica na capa', await p.evaluate(() => tela), 'capa');
  igual('e nenhuma ficha nasceu para ela', (await fichas()).some(x => x.nome === 'Fabi Melo'), false);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. O painel: a marca em Clientes e o botão do link');
{
  const ctx = await nav.newContext({ viewport:{ width:390, height:860 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => { erros.push('painel (alerta): ' + d.message()); d.accept(); });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
    window.__abriu = []; window.open = u => { window.__abriu.push(String(u)); return null; }; }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.saloes)
    && bd.planos && bd.planos.length, null, { timeout: 20000 });
  await p.waitForTimeout(1200);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  await p.evaluate(() => irPara('clientes'));
  await p.waitForFunction(() => document.querySelectorAll('#listaClientes tbody tr').length >= 3, null, { timeout: 15000 });
  const linhas = await p.evaluate(() => [...document.querySelectorAll('#listaClientes tbody tr')]
    .map(tr => [tr.querySelector('td b').textContent.trim(), /cadastrou pelo link/.test(tr.innerText)]));
  const de = n => (linhas.find(l => l[0] === n) || [n, null])[1];
  igual('quem se cadastrou pelo link tem a marca; a ficha do balcão, não',
    [de('Luana Teste'), de('Carla Dias'), de('Maria Souza')], [true, true, false]);
  await p.click('button:has-text("Link de cadastro")');
  await p.waitForSelector('#linkCadastro');
  const link = await p.inputValue('#linkCadastro');
  verdade('a janela mostra o link do salão com o cadastro', link.endsWith('agendar.html?salao=' + SLUG + '&cadastro=1'), link);
  const botoes = await p.evaluate(() => [...document.querySelectorAll('#modalPe .btn')].map(b => b.textContent.trim()));
  igual('com Fechar, Copiar e Mandar no WhatsApp', botoes, ['Fechar', 'Copiar o link', 'Mandar no WhatsApp']);
  await p.click('#modalPe .btn:has-text("Mandar no WhatsApp")');
  const abriu = await p.evaluate(() => window.__abriu.slice(-1)[0] || '');
  verdade('o WhatsApp abre com o convite e o link', abriu.startsWith('https://wa.me/?text=')
    && decodeURIComponent(abriu).includes('Faça seu cadastro no Salão Megatop')
    && decodeURIComponent(abriu).includes(link), abriu);
  verdade('a 390px a janela cabe', await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1));
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
await banco.end();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
