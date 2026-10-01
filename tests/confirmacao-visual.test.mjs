/* ===========================================================================
   AgendaPro — "Confira seu agendamento" e "Agendamento enviado!"

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/confirmacao-visual.test.mjs

   O pedido: redesenhar a confirmação e a tela de depois, seguindo a
   referência só na estrutura — as cores vêm EXCLUSIVAMENTE do tema de
   Aparência, o escuro vale sozinho, e a lógica de agendamento não muda.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a confirmação: título, dia/hora/profissional no alto, o cartão com
        salão, serviço, profissional, quando, duração e total (o total
        maior), o status, a observação fechada, e os dois botões;
     2. o status segue o dono: "Aguardando confirmação" para quem confirma
        depois; "Confirmado na hora" para quem confirma sozinho;
     3. as cores são do tema: o botão, o total e os ícones mudam com a cor
        escolhida, e o bloco .cf-* do estilo.css não tem cor escrita;
     4. o escuro: cartão escuro, letra clara, contraste de leitura;
     5. "Alterar horário" volta aos horários com a escolha intacta;
     6. marcando de verdade (salão que confirma depois): a observação chega
        ao banco, e a tela de depois mostra "Agendamento enviado!", o resumo
        compacto, "Aguardando confirmação do salão", e os dois botões;
     7. salão que confirma sozinho: "Agendamento confirmado!" e "Confirmado";
     8. celular, tablet e computador: nada vaza, e os botões se arrumam.
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

/* ── 3b: o bloco .cf-* do estilo.css não escreve cor nenhuma ─────────────── */
secao('0. O estilo das duas telas não tem cor escrita');
{
  const css = fs.readFileSync(path.join(RAIZ, 'estilo.css'), 'utf8');
  const ini = css.indexOf('CONFIRA SEU AGENDAMENTO e AGENDAMENTO ENVIADO');
  const bloco = css.slice(ini, css.indexOf('#convitePwa .btn-p', ini));
  const regras = bloco.replace(/\/\*[\s\S]*?\*\//g, '');
  verdade('achei o bloco das telas no estilo.css', ini > 0 && regras.length > 1000);
  const escritas = regras.match(/#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|\b(pink|purple|magenta|violet|red|blue|green)\b/g) || [];
  igual('nenhuma cor escrita nas regras: só as variáveis do tema', escritas, []);
  verdade('e elas usam as variáveis da Aparência', ['--acao', '--acao-txt', '--ac-600', '--ac-soft', '--painel', '--txt']
    .every(v => regras.includes('var(' + v + ')')));
}

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = aba();
await dona.criarConta({ email:`cv-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const sv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Coloração', duracaoMin:120, intervaloMin:0,
  preco:150, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
const porCfg = extra => dona.atualizar('saloes', SALAO, { cfg: Object.assign(
  { diasLiberados:30, funcionamento: SEMANA, confirmaAuto:false }, extra) });
await porCfg({ cor:'#B8356B', cores:{ botao:'#8E2457' } });

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
const cor = hex => { const n = parseInt(hex.slice(1), 16); return `rgb(${n >> 16}, ${(n >> 8) & 255}, ${n & 255})`; };

/* Leva a página direto à confirmação com uma escolha montada — a tela só lê
   a escolha; o caminho clicado inteiro é medido no item 6. */
async function naConfirmacao(largura = 390, pendente = true, servicos = null){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:900 }, isMobile: largura < 700, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(600);
  await p.evaluate(([sid, pid, pend]) => {
    salaoConfirmaSozinho = !pend;
    escolha = { servicos: Array.isArray(sid) ? sid : [sid], profissionalId:pid, data:'2026-10-01', inicio:630,
                para:'mim', filhoNome:'', quem:'mim', relacao:null, junto:false };
    historico = ['capa', 'servico', 'quem', 'prof', 'quando', 'dados'];
    irPara('confirmar', true);
  }, [servicos || sv.id, prof.id, pendente]);
  await p.waitForTimeout(300);
  return { p, fechar: () => ctx.close() };
}
const lerConfirmacao = p => p.evaluate(() => {
  const q = s => document.querySelector(s), cs = s => q(s) ? getComputedStyle(q(s)) : null;
  const bp = q('#btPrincipal'), bs = q('#btSecundario');
  return {
    titulo: q('#p-confirmar h2').textContent.trim(),
    quando: q('#cfQuando').innerText.replace(/\s+/g, ' ').trim(),
    salao: [q('#resumoFinal .cf-salao-logo').innerText.trim(),
            q('#resumoFinal .cf-salao-txt').innerText.replace(/\s+/g, ' ').trim()],
    rotulos: [...document.querySelectorAll('#resumoFinal .cf-linha small')].map(x => x.textContent.trim()),
    valores: [...document.querySelectorAll('#resumoFinal .cf-linha b')].map(x => x.innerText.replace(/\s+/g, ' ').trim()),
    icones: [...document.querySelectorAll('#resumoFinal .cf-linha .cf-ic')].map(x => !!x.querySelector('svg') || x.textContent.trim()),
    totalFonte: parseFloat(cs('#resumoFinal .cf-total b').fontSize),
    outraFonte: parseFloat(cs('#resumoFinal .cf-linha b').fontSize),
    totalCor: cs('#resumoFinal .cf-total b').color,
    ac600: (() => { const s = document.createElement('i'); s.style.color = getComputedStyle(document.documentElement).getPropertyValue('--ac-600');
      document.body.appendChild(s); const c = getComputedStyle(s).color; s.remove(); return c; })(),
    status: q('#cfStatus').innerText.replace(/\s+/g, ' ').trim(),
    statusClasse: q('#cfStatus > div').className,
    obs: { aberta: q('#cfObs').open, resumo: q('#cfObs summary').innerText.replace(/\s+/g, ' ').trim() },
    botoes: [[bp.textContent.trim(), !!bp.offsetParent], [bs.textContent.trim(), !!bs.offsetParent]],
    bpFundo: getComputedStyle(bp).backgroundColor,
    bsCor: getComputedStyle(bs).color, bsFundo: getComputedStyle(bs).backgroundColor,
    icCor: cs('#resumoFinal .cf-linha .cf-ic').color,
    card: cs('#resumoFinal').backgroundColor, cardTxt: cs('#resumoFinal .cf-linha b').color,
    stFundo: cs('#cfStatus > div').backgroundColor, stTit: cs('#cfStatus b').color,
    sobra: document.documentElement.scrollWidth - innerWidth,
    pe: (() => { const a = bp.getBoundingClientRect(), b = bs.getBoundingClientRect();
      return { lado: Math.abs(a.top - b.top) < 4, primeiroEmCima: a.top < b.top - 4 }; })(),
  };
});

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A confirmação');
{
  const { p, fechar } = await naConfirmacao();
  const t = await lerConfirmacao(p);
  igual('o título', t.titulo, 'Confira seu agendamento');
  igual('no alto: o dia, a hora e com quem', t.quando, 'Quinta-feira, 01/10 às 10:30 com Ju Barbosa');
  igual('o cartão abre com o salão (sem logo, a inicial no lugar dela)', t.salao, ['S', 'Salão Megatop Salão de beleza']);
  igual('e segue com cada informação, na ordem', t.rotulos, ['Serviço', 'Profissional', 'Quando', 'Duração', 'Total']);
  igual('com os valores', t.valores,
    ['Coloração', 'Ju Barbosa', 'Quinta-feira, 01/10 10:30 às 12:30', '120 min', 'R$ 150,00']);
  igual('cada uma com o seu ícone (e o R$ no total)', t.icones, [true, true, true, true, 'R$']);
  verdade('o total é o maior valor do cartão, na cor da marca', t.totalFonte >= t.outraFonte * 1.3 && t.totalCor === t.ac600,
    `${t.totalFonte}px x ${t.outraFonte}px, ${t.totalCor} x ${t.ac600}`);
  igual('a observação começa fechada, e diz que é opcional', [t.obs.aberta, t.obs.resumo],
    [false, 'Deseja adicionar alguma observação? (opcional)']);
  await p.click('#cfObs summary');
  igual('tocada, abre o campo', await p.evaluate(() => !!document.getElementById('fRecado').offsetParent), true);
  igual('embaixo: Confirmar agendamento e Alterar horário', t.botoes,
    [['Confirmar agendamento', true], ['Alterar horário', true]]);

  secao('2. O status segue o que o dono escolheu');
  igual('quem confirma depois: "Aguardando confirmação", com as duas frases', t.status,
    'Aguardando confirmação Você receberá uma mensagem pelo WhatsApp assim que o salão confirmar seu horário. '
    + 'Enquanto isso, este horário fica reservado para você e não pode ser agendado por outra pessoa.');
  verdade('com cara de informação, no tom da marca — e não de erro', !/erro|alerta/.test(t.statusClasse)
    && t.stTit === t.ac600, `${t.statusClasse} / ${t.stTit}`);

  secao('3. As cores são do tema');
  igual('o Confirmar na cor do botão escolhida', t.bpFundo, cor('#8E2457'));
  verdade('o Alterar horário na mesma identidade, com menos peso (papel, letra da marca)',
    t.bsCor === t.ac600 && t.bsFundo === t.card, `${t.bsCor} / ${t.bsFundo}`);
  verdade('os ícones na cor da marca', t.icCor === t.ac600, t.icCor);

  secao('5. "Alterar horário"');
  await p.click('#btSecundario');
  await p.waitForTimeout(400);
  igual('volta aos horários, com o serviço e a profissional ainda escolhidos', await p.evaluate(() =>
    [tela, escolha.servicos.length, !!escolha.profissionalId]), ['quando', 1, true]);
  await fechar();
}
{
  const { p, fechar } = await naConfirmacao(390, false);
  const t = await lerConfirmacao(p);
  verdade('quem confirma sozinho: "Confirmado na hora", sem prometer espera',
    /^Confirmado na hora/.test(t.status) && !/Aguardando/.test(t.status), t.status);
  await fechar();
}

secao('3b. Outra cor em Aparência, outra tela');
await porCfg({ cor:'#1D4ED8' });
{
  const { p, fechar } = await naConfirmacao();
  const t = await lerConfirmacao(p);
  igual('o Confirmar fica azul', t.bpFundo, cor('#1D4ED8'));
  verdade('e o total, os ícones e o status acompanham', t.totalCor === t.ac600 && t.icCor === t.ac600
    && t.stTit === t.ac600 && /^rgb\(\d+, \d+, (\d+)\)$/.test(t.ac600)
    && Number(t.ac600.match(/\d+/g)[2]) > Number(t.ac600.match(/\d+/g)[0]), t.ac600);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. No tema escuro');
await porCfg({ cor:'#10B981', tema:'escuro' });
{
  const { p, fechar } = await naConfirmacao();
  const t = await lerConfirmacao(p);
  const lum = c => { const [r, g, b] = c.match(/\d+(\.\d+)?/g).slice(0, 3).map(Number).map(v => {
    v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; });
    return .2126 * r + .7152 * g + .0722 * b; };
  const contraste = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((i, j) => j - i); return (x + .05) / (y + .05); };
  verdade('o cartão é escuro', lum(t.card) < .06, t.card);
  verdade('e a letra dele se lê (contraste ≥ 7)', contraste(t.cardTxt, t.card) >= 7,
    contraste(t.cardTxt, t.card).toFixed(1));
  verdade('o total, na cor da marca, também (≥ 4,5)', contraste(t.totalCor, t.card) >= 4.5,
    contraste(t.totalCor, t.card).toFixed(1));
  verdade('e o título do status sobre o fundo da página (≥ 4,5)', await p.evaluate(() => {
    const b = getComputedStyle(document.body).backgroundColor;
    return b; }).then(bg => contraste(t.stTit, bg) >= 4.5), t.stTit);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. Marcando de verdade — salão que confirma depois');
await porCfg({ cor:'#B8356B', cores:{ botao:'#8E2457' } });
async function marcar(){
  const cliente = aba();
  const TEL = '+5551' + (200000000 + (Date.now() % 79999999));
  await cliente.criarConta({ email:`cvc-${Date.now()}@t.com`, senha:'minhasenhaboa', nome:'Maria Cliente', telefone: TEL });
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, cliente.sessao()]);
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => document.querySelector('.boas-cta'), null, { timeout: 15000 });
  await p.waitForTimeout(1500);
  await p.click('.boas-cta'); await p.waitForTimeout(500);
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(400);
  await p.click('#quemMim'); await p.waitForTimeout(600);
  if(await p.evaluate(() => tela === 'prof')){ await p.click('#btPrincipal'); }
  await p.waitForTimeout(2500);
  await p.click('#listaHoras .hora'); await p.waitForTimeout(400);
  await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  if(await p.evaluate(() => tela === 'dados')){
    await p.fill('#dNome', 'Maria Cliente'); await p.fill('#dTel', '51988887777');
    await p.fill('#dNasc', '1989-10-04'); await p.fill('#dEmail', 'maria@exemplo.com').catch(() => {});
    await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  }
  return { p, fechar: () => ctx.close() };
}
{
  const { p, fechar } = await marcar();
  igual('chega à confirmação', await p.evaluate(() => tela), 'confirmar');
  await p.click('#cfObs summary');
  await p.fill('#fRecado', 'tenho alergia a amônia');
  await p.click('#btPrincipal');
  await p.waitForTimeout(4000);
  const t = await p.evaluate(() => ({
    tela, titulo: document.querySelector('#p-pronto h2').textContent,
    sub: document.getElementById('prontoTexto').textContent.trim(),
    // Sem o logo (aqui é a inicial, "S"): o que se lê é o texto.
    resumo: [document.querySelector('#resumoPronto .cf-salao-txt').innerText,
      ...[...document.getElementById('resumoPronto').children].slice(1).map(e => e.innerText)]
      .join(' ').replace(/\s+/g, ' ').trim(),
    icones: document.querySelectorAll('#resumoPronto .cf-mini svg').length,
    chip: (document.querySelector('#resumoPronto .cf-chip') || {}).className,
    nota: document.getElementById('bolhaConfirmacao').innerText.replace(/\s+/g, ' ').trim(),
    bolhaZap: !!document.querySelector('#p-pronto .zap'),
    botoes: [document.getElementById('btPrincipal').textContent.trim(), document.getElementById('btSecundario').textContent.trim()],
    pe: (() => { const a = document.getElementById('btPrincipal').getBoundingClientRect(),
      b = document.getElementById('btSecundario').getBoundingClientRect(); return a.top < b.top; })(),
  }));
  igual('"Agendamento enviado!", e para onde ele foi', [t.tela, t.titulo, t.sub],
    ['pronto', 'Agendamento enviado!', 'Seu horário foi encaminhado para o salão.']);
  verdade('o resumo compacto: salão, serviço, profissional, dia e hora, duração',
    /^Salão Megatop Salão de beleza Coloração Ju Barbosa \S+-feira, \d\d\/\d\d · \d\d:\d\d às \d\d:\d\d 120 min Aguardando confirmação do salão$/.test(t.resumo)
    || /^Salão Megatop Salão de beleza Coloração Ju Barbosa (Sábado|Domingo), \d\d\/\d\d · \d\d:\d\d às \d\d:\d\d 120 min Aguardando confirmação do salão$/.test(t.resumo),
    t.resumo);
  igual('cada linha com o seu ícone, e o selo de espera', [t.icones, t.chip], [4, 'cf-chip cf-chip-espera']);
  verdade('a nota diz que a mensagem vem quando o salão confirmar', /assim que o salão confirmar/.test(t.nota), t.nota);
  igual('sem bolha de WhatsApp desenhada', t.bolhaZap, false);
  igual('os botões: Ver meus horários, e Voltar para a home embaixo', [t.botoes, t.pe],
    [['Ver meus horários', 'Voltar para a home'], true]);
  const ags = await dona.lista('agendamentos', { salaoId: SALAO });
  const novo = ags[ags.length - 1];
  igual('no banco: pendente, e com a observação', [novo && novo.status, novo && novo.obs],
    ['pendente', 'tenho alergia a amônia']);
  await p.click('#btSecundario');
  await p.waitForTimeout(500);
  igual('"Voltar para a home" leva à capa, com a escolha zerada', await p.evaluate(() =>
    [tela, escolha.servicos.length, escolha.inicio]), ['capa', 0, null]);
  await fechar();
}

secao('7. Salão que confirma sozinho');
await porCfg({ cor:'#B8356B', confirmaAuto:true });
{
  const { p, fechar } = await marcar();
  await p.click('#btPrincipal');
  await p.waitForTimeout(4000);
  const t = await p.evaluate(() => ({ titulo: document.querySelector('#p-pronto h2').textContent,
    resumo: document.getElementById('resumoPronto').innerText,
    chip: (document.querySelector('#resumoPronto .cf-chip') || {}).className }));
  igual('"Agendamento confirmado!", com o selo de confirmado', [t.titulo, t.chip],
    ['Agendamento confirmado!', 'cf-chip cf-chip-ok']);
  verdade('e sem "Aguardando"', !/Aguardando/.test(t.resumo), t.resumo);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('8. Celular, tablet e computador');
for(const [largura, nome, lado] of [[360, 'celular pequeno', false], [390, 'celular', false],
                                    [768, 'tablet', true], [1280, 'computador', true]]){
  const { p, fechar } = await naConfirmacao(largura);
  const t = await lerConfirmacao(p);
  verdade(`${nome} (${largura}px): nada vaza para o lado`, t.sobra <= 0, `sobra ${t.sobra}px`);
  igual(`${nome}: os dois botões ${lado ? 'lado a lado' : 'um sobre o outro, o Confirmar em cima'}`,
    lado ? t.pe.lado : t.pe.primeiroEmCima, true);
  await fechar();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('9. Nome de serviço comprido');
/* O defeito da foto do dono: "Esmaltação unha manicure + Manicure" passava da
   borda do cartão. A página não rolava para o lado (o item 8 não via), porque
   o texto vazava por cima, sem esticar nada. A medida aqui segue o TEXTO,
   com um Range, e não a caixa onde ele deveria caber. */
{
  const longo1 = await dona.inserir('servicos', { salaoId: SALAO, nome:'Esmaltação unha manicure', duracaoMin:40,
    intervaloMin:0, preco:35, ativo:true, aceitaOnline:true, categoria:'Unhas' });
  const longo2 = await dona.inserir('servicos', { salaoId: SALAO, nome:'Manicure tradicional completa com cutilagem',
    duracaoMin:40, intervaloMin:0, preco:40, ativo:true, aceitaOnline:true, categoria:'Unhas' });
  for(const largura of [320, 360, 390]){
    const { p, fechar } = await naConfirmacao(largura, true, [longo1.id, longo2.id]);
    const r = await p.evaluate(() => {
      const card = document.getElementById('resumoFinal').getBoundingClientRect();
      const fora = [...document.querySelectorAll('#resumoFinal .cf-linha b')].map(b => {
        const rg = document.createRange(); rg.selectNodeContents(b);
        return Math.round(rg.getBoundingClientRect().right - card.right);
      });
      const nome = document.querySelector('#resumoFinal .cf-linha b');
      const fx = getComputedStyle(document.querySelector('#resumoFinal .cf-faixa'));
      return { fora, texto: nome.innerText.replace(/\s+/g, ' ').trim(),
        linhas: Math.round(nome.getBoundingClientRect().height / parseFloat(getComputedStyle(nome).fontSize)),
        faixa: [parseFloat(fx.fontSize), fx.opacity] };
    });
    verdade(`${largura}px: nenhum texto passa da borda do cartão`, r.fora.every(x => x <= 0), JSON.stringify(r.fora));
    verdade(`${largura}px: o nome inteiro, descendo para a linha de baixo`,
      r.texto === 'Esmaltação unha manicure + Manicure tradicional completa com cutilagem' && r.linhas >= 2, JSON.stringify(r));
    verdade(`${largura}px: o horário ("10:30 às …") se lê — nem miúdo, nem apagado`,
      r.faixa[0] >= 13 && r.faixa[1] === '1', JSON.stringify(r.faixa));
    await fechar();
  }
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
