/* ===========================================================================
   AgendaPro — aparência fácil: as cores da logo e o "Arrumar para mim"

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/aparencia-facil.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Tem que estar bem fácil para qualquer um conseguir fazer uma aparência
   bonita no link." Escolhidas pelo dono:
     · COMBINAR COM A LOGO — um toque lê as cores da logo e monta as da
       página, sempre legíveis; só na prévia até "Usar estas cores".
     · ARRUMAR A LEITURA — quando uma cor deixa texto difícil de ler, um toque
       troca só as cores ruins pelas mais parecidas que se leem.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. Sem logo, o botão fica desligado e diz o que fazer.
     2. Cada tipo de logo dá a página certa (clara/escura, cor da casa) e
        NENHUM aviso de leitura — logo de fundo cheio e logo recortada.
     3. Só na prévia: "Voltar ao que eu tinha" devolve tudo; "Usar estas
        cores" grava. Modo, letra e moldura não mudam.
     4. Logo que não carrega: avisa e não mexe em nada.
     5. "Arrumar para mim" (no topo e na seção): some o aviso, só as cores
        ruins mudam, fundos e botões ficam, e "Desfazer" devolve.
     6. O QUE A CAÇA-BUG ACHOU: "Cartões" em preto numa página clara deixava
        o link inteiro preto com letra escura (nome de serviço a 1,3:1) e o
        aviso calado; e letra clara escolhida sobre cartão escuro era acusada
        de ilegível, medida contra um papel que nem aparece. Agora o aviso
        pega o cartão escolhido, a cor de dentro dos serviços, dos produtos e
        dos atalhos — e o conserto é conferido NO LINK de verdade.
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
await dona.criarConta({ email:`af-${marca}@teste.com`, senha:'minhasenhaboa', nome:'Rita Alves',
  telefone:'+5511' + (100000000 + Math.floor(Math.random() * 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Barbearia Lima ' + marca, p_tipo:'barbearia',
  p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte navalhado', duracaoMin:40, intervaloMin:0,
  preco:45, ativo:true, aceitaOnline:true });
await dona.atualizar('saloes', SALAO, { cfg:{ cor:'#7C3AED', tema:'claro', modo:'premium', letra:'elegante',
  moldura:'elegante', pagamentos:{ formas:['pix'] } } });
const cfgDe = async () => (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [], alertas = [];
const ctx = await nav.newContext({ viewport:{ width:1280, height:1000 } });
const p = await ctx.newPage();
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', x => { alertas.push(x.message()); x.accept(); });
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
await p.evaluate(() => trocarAbaSalao('aparencia'));
await p.waitForTimeout(800);

/* Uma logo desenhada na hora: um círculo e uma faixa na tinta, sobre o fundo
   (ou recortada, sem fundo). */
const desenhar = (fundo, tinta) => p.evaluate(([fundo, tinta]) => {
  const c = document.createElement('canvas'); c.width = 200; c.height = 200;
  const x = c.getContext('2d');
  if(fundo){ x.fillStyle = fundo; x.fillRect(0, 0, 200, 200); }
  x.fillStyle = tinta; x.beginPath(); x.arc(100, 80, 45, 0, 7); x.fill(); x.fillRect(30, 140, 140, 26);
  return c.toDataURL('image/png');
}, [fundo, tinta]);
const comLogo = async url => { await p.evaluate(u => { acharSalao(salaoAtual).logo = u; pintarAparencia(); }, url);
  await p.waitForTimeout(200); };
const matiz = hex => { const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.substr(i, 2), 16) / 255);
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  if(!d) return -1;
  const h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return Math.round(h * 60); };
const lerLogo = async () => {
  await p.evaluate(() => experimentarCoresDaLogo());
  await p.waitForFunction(() => !lendoLogo, null, { timeout: 8000 });
  await p.waitForTimeout(300);
  return p.evaluate(() => ({ tema: aparencia.tema, cor: aparencia.cor, cores: aparencia.cores, modo: aparencia.modo,
    letra: aparencia.letra, moldura: aparencia.moldura, modelo: modeloAtual,
    aviso: document.getElementById('avisoLegibilidade').textContent.trim(),
    topo: document.getElementById('avisoLeituraTopo').textContent.trim(),
    barra: document.getElementById('modeloBarra').textContent.replace(/\s+/g, ' ').trim() }));
};

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Sem logo, o botão diz o que fazer');
await comLogo(null);
igual('desligado, pedindo a logo no passo 1', await p.evaluate(() => [document.getElementById('btCorDaLogo').disabled,
  /Ponha a logo no passo 1/.test(document.getElementById('corDaLogo').textContent)]), [true, true]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. Cada logo dá a sua página — e nenhuma fica difícil de ler');
const antesDeTudo = await p.evaluate(() => JSON.stringify(aparencia));
const CASOS = [
  ['dourado no preto (selo de barbearia)', '#111111', '#C9A24B', 'escuro', [30, 55]],
  ['vermelho no branco',                   '#FFFFFF', '#D32F2F', 'claro',  [0, 10, 350, 360]],
  ['rosa no branco',                       '#FFFFFF', '#E91E63', 'claro',  [330, 350]],
  ['tinta preta recortada',                null,      '#111111', 'claro',  null],
  ['tinta branca recortada',               null,      '#FFFFFF', 'escuro', null],
];
for(const [nome, fundo, tinta, tema, faixa] of CASOS){
  await comLogo(await desenhar(fundo, tinta));
  const r = await lerLogo();
  const h = matiz(r.cor);
  const naFaixa = !faixa ? h === -1 || r.cores.botao
    : (h >= faixa[0] && h <= faixa[1]) || (faixa.length > 2 && h >= faixa[2] && h <= faixa[3]);
  verdade(`${nome}: página ${tema}, ${faixa ? 'na cor da logo' : 'neutra'}, sem nenhum aviso de leitura`,
    r.tema === tema && naFaixa && !r.aviso && !r.topo && r.modelo === 'logo',
    JSON.stringify({ tema: r.tema, cor: r.cor, matiz: h, aviso: r.aviso, topo: r.topo }));
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. Só na prévia até usar; modo, letra e moldura ficam');
const ult = await lerLogo();
verdade('a barra diz que é a prévia e oferece "Usar estas cores"',
  /Você está vendo Cores da logo na prévia/.test(ult.barra) && /Usar estas cores/.test(ult.barra), ult.barra);
igual('modo, letra e moldura não mudam', [ult.modo, ult.letra, ult.moldura], ['premium', 'elegante', 'elegante']);
await p.evaluate(() => voltarDoModelo());
await p.waitForTimeout(200);
igual('"Voltar ao que eu tinha" devolve a aparência inteira', await p.evaluate(() => JSON.stringify(aparencia)), antesDeTudo);
await comLogo(await desenhar('#111111', '#C9A24B'));
const dourada = await lerLogo();
await p.evaluate(() => usarModelo());
await p.waitForTimeout(1800);
const cfg = await cfgDe();
igual('"Usar estas cores" grava: tema, cor da casa e as cores',
  [cfg.tema, cfg.cor, (cfg.cores || {}).botao, (cfg.cores || {}).papel],
  [dourada.tema, dourada.cor, dourada.cores.botao, dourada.cores.papel]);
verdade('e diz que ficou pronto', /Pronto: Cores da logo/.test(await p.evaluate(() => document.getElementById('modeloBarra').textContent)));

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. Logo que não carrega');
alertas.length = 0;
const antesFalha = await p.evaluate(() => JSON.stringify(aparencia));
await comLogo(BASE + '/nao-existe-' + marca + '.png');
await p.evaluate(() => experimentarCoresDaLogo());
await p.waitForFunction(() => !lendoLogo, null, { timeout: 8000 });
await p.waitForTimeout(300);
igual('avisa, e não mexe em nada', [alertas.length === 1 && /Não consegui ler as cores da sua logo/.test(alertas[0]),
  await p.evaluate(() => JSON.stringify(aparencia)) === antesFalha], [true, true]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. "Arrumar para mim"');
await p.evaluate(() => { aparencia.tema = 'claro'; aparencia.fundoTipo = 'cor';
  aparencia.cores = { card:'#FFFFFF', papel:'#FFFFFF', botao:'#2563EB', texto:'#EEEEEE', titulo:'#F5F5F5', letraAgendar:'#2A5FD8' };
  pintarAparencia(); });
await p.waitForTimeout(200);
const ruim = await p.evaluate(() => ({ topo: document.getElementById('avisoLeituraTopo').textContent.replace(/\s+/g, ' ').trim(),
  sec: document.getElementById('avisoLegibilidade').textContent }));
// Quatro: texto, títulos, a letra do botão — e o discreto, que acompanha o texto escolhido.
verdade('o topo da Aparência avisa, com "Arrumar para mim"', /4 partes da sua página estão difíceis de ler/.test(ruim.topo)
  && /Arrumar para mim/.test(ruim.topo), ruim.topo);
verdade('e a seção Cores das letras também tem o botão', /Arrumar para mim/.test(ruim.sec), ruim.sec);
const antesArrumar = await p.evaluate(() => Object.assign({}, aparencia.cores));
await p.click('#avisoLeituraTopo .btn');
await p.waitForTimeout(300);
const arrumado = await p.evaluate(() => ({ cores: Object.assign({}, aparencia.cores),
  aviso: document.getElementById('avisoLegibilidade').textContent.trim(),
  topo: document.getElementById('avisoLeituraTopo').textContent.replace(/\s+/g, ' ').trim(),
  contraste: [contrasteEntre(aparencia.cores.texto, '#FFFFFF'), contrasteEntre(aparencia.cores.titulo, '#FFFFFF'),
              contrasteEntre(aparencia.cores.letraAgendar, '#2563EB')].map(x => Math.round(x * 10) / 10) }));
verdade('o aviso some, e o topo diz o que fez ("Arrumei a leitura de 4 cores")',
  !arrumado.aviso && /Arrumei a leitura de 4 cores/.test(arrumado.topo), JSON.stringify(arrumado));
verdade('texto, títulos e a letra do botão passam de 4,5:1', arrumado.contraste.every(x => x >= 4.5),
  JSON.stringify(arrumado.contraste));
igual('fundos e botão não mudam', [arrumado.cores.card, arrumado.cores.papel, arrumado.cores.botao],
  [antesArrumar.card, antesArrumar.papel, antesArrumar.botao]);
await p.click('#avisoLeituraTopo .btn');           // Desfazer
await p.waitForTimeout(300);
igual('"Desfazer" devolve as cores de antes', await p.evaluate(() => aparencia.cores), antesArrumar);
await p.evaluate(() => document.querySelector('#avisoLegibilidade .btn').click());
await p.waitForTimeout(300);
igual('o botão da seção arruma igual', await p.evaluate(() => [document.getElementById('avisoLegibilidade').textContent.trim(),
  /Arrumei/.test(document.getElementById('leituraArrumadaSec').textContent)]), ['', true]);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. O aviso pega o cartão escuro e as cores de dentro — e não acusa página certa');
// A cor da marca fixa (roxo): o preço herdado sai dela, e o teste não pode depender da logo de cima.
const por = async (cores, atalhos) => { await p.evaluate(([c, a]) => { aparencia.cor = '#7C3AED'; aparencia.tema = 'claro'; aparencia.fundoTipo = 'cor';
    aparencia.cores = c; Object.assign(aparencia.atalhos, { estilo:'borda', fundo:'', cores:{} }, a || {});
    leituraArrumada = null; pintarAparencia(); }, [cores, atalhos || null]); await p.waitForTimeout(200); };
const avisoTopo = () => p.evaluate(() => document.getElementById('avisoLeituraTopo').textContent.replace(/\s+/g, ' ').trim());
const avisoSec  = () => p.evaluate(() => document.getElementById('avisoLegibilidade').textContent.replace(/\s+/g, ' ').trim());
const arrumar   = async () => { await p.click('#avisoLeituraTopo .btn'); await p.waitForTimeout(300); };

// a) "Cartões" em preto numa página clara: o link inteiro fica preto.
await por({ card:'#000000' });
const a1 = await avisoSec();
verdade('"Cartões" em preto numa página clara: o aviso acusa os títulos, o texto e o preço',
  /os títulos \(1\.3:1 sobre os cards\)/.test(a1) && /o texto \(/.test(a1) && /o preço \(/.test(a1), a1);
await arrumar();
const d1 = await p.evaluate(() => ({ aviso: document.getElementById('avisoLegibilidade').textContent.trim(), card: aparencia.cores.card,
  c: ['titulo', 'texto', 'destaque'].map(k => Math.round(contrasteEntre(aparencia.cores[k], '#000000') * 10) / 10) }));
verdade('"Arrumar para mim" clareia títulos, texto e preço (4,5:1 ou mais no cartão) e não toca no cartão',
  !d1.aviso && d1.card === '#000000' && d1.c.every(x => x >= 4.5), JSON.stringify(d1));
await p.evaluate(() => salvarAparencia());
await p.waitForTimeout(1800);
{
  // No LINK de verdade: o nome do serviço e o "Entrar na minha conta" se leem sobre o cartão preto.
  const c2 = await nav.newContext({ viewport:{ width:390, height:844 }, isMobile:true, hasTouch:true });
  const q = await c2.newPage();
  q.on('pageerror', e => erros.push('link: ' + e.message));
  await q.goto(BASE + '/agendar.html?salao=' + cr[0].slug);
  await q.waitForFunction(() => document.querySelectorAll('.sv-cartao').length >= 1, null, { timeout: 15000 });
  await q.waitForTimeout(600);
  const r = await q.evaluate(() => { const lum = c => { const v = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(c).slice(1, 4).map(Number).map(x => { x /= 255;
        return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }); return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]; };
    const ct = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return Math.round((x + 0.05) / (y + 0.05) * 10) / 10; };
    const card = document.querySelector('.sv-cartao'), nome = card.querySelector('.sv-cartao-txt b');
    const conta = document.querySelector('.cartao, .opcao');
    return { fundo: getComputedStyle(card).backgroundColor, nome: ct(getComputedStyle(nome).color, getComputedStyle(card).backgroundColor),
      conta: conta ? ct(getComputedStyle(conta.querySelector('b') || conta).color, getComputedStyle(conta).backgroundColor) : 99 }; });
  verdade('no link: cartão preto, e o nome do serviço e o "Entrar na minha conta" com 4,5:1 ou mais',
    r.fundo === 'rgb(0, 0, 0)' && r.nome >= 4.5 && r.conta >= 4.5, JSON.stringify(r));
  await c2.close();
}

// b) Página certa não é acusada: sem fundo escolhido, a coluna tem a cor dos cartões.
await por({ card:'#000000', texto:'#FFFFFF', titulo:'#FFFFFF', destaque:'#FFD54F', icone:'#FFFFFF', discreto:'#CCCCCC' });
igual('cartão preto com letras claras escolhidas: nenhum aviso (o papel de fábrica não aparece)',
  [await avisoTopo(), await avisoSec()], ['', '']);

// c) A cor de dentro dos serviços, que é outra superfície.
await por({ fundoServico:'#000000' });
const a3 = await avisoSec();
verdade('"Cor de dentro dos serviços" preta: acusa o nome e o preço DO SERVIÇO, e não os títulos da página',
  /o nome do serviço \(1\.3:1 sobre o quadro\)/.test(a3) && /o preço do serviço \(/.test(a3) && !/os títulos/.test(a3), a3);
await arrumar();
igual('e o conserto mexe só nas frases do cartão de serviço',
  [await avisoSec(), await p.evaluate(() => Object.keys(aparencia.cores).sort())], ['', ['fundoServico', 'nomeServico', 'precoServico']]);

// d) A dos produtos.
await por({ fundoProduto:'#000000' });
verdade('"Cor de dentro dos produtos" preta: acusa o nome do produto', /o nome do produto \(1\.3:1 sobre o quadro\)/.test(await avisoSec()), await avisoSec());

// e) A cor de dentro dos três atalhos: o conserto mora em atalhos.cores.
await por({}, { fundo:'#1A1A1A' });
const a5 = await avisoSec();
verdade('"Cor de dentro" dos atalhos escura: acusa o nome dos três',
  ['Pagamentos', 'Horários', 'Informações'].every(n => new RegExp('o nome de ' + n + ' \\(.*sobre a cor de dentro\\)').test(a5)), a5);
await arrumar();
const d5 = await p.evaluate(() => ({ aviso: document.getElementById('avisoLegibilidade').textContent.trim(),
  c: ['pagamentos', 'horarios', 'informacoes'].map(k => Math.round(contrasteEntre(aparencia.atalhos.cores[k] || '#000000', '#1A1A1A') * 10) / 10),
  soltas: Object.keys(aparencia.cores).length }));
verdade('"Arrumar para mim" dá cor legível aos três nomes, sem mexer nas cores soltas',
  !d5.aviso && d5.c.every(x => x >= 4.5) && d5.soltas === 0, JSON.stringify(d5));
await p.click('#avisoLeituraTopo .btn');           // Desfazer
await p.waitForTimeout(300);
igual('"Desfazer" devolve os atalhos como estavam', await p.evaluate(() => aparencia.atalhos.cores), {});
await por({}, { fundo:'#1A1A1A', estilo:'limpo' });
igual('no "Sem contorno" não há cartão: nenhum aviso', await avisoSec(), '');

secao('Erros de JavaScript');
igual('nenhum', erros, []);
await nav.close();
console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam.`);
process.exit(falhou ? 1 : 0);
