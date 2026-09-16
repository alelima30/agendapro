/* ===========================================================================
   AgendaPro — a venda de plano está desligada na tela, e SÓ na tela

     bash tests/bancada/subir.sh
     PLAYWRIGHT=… node tests/oferta-plano.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   Enquanto a comercialização é tratada direto com o comprador do sistema, o
   painel não mostra preço, não recomenda plano e não oferece Assinar. Isso é
   uma chave só no `app.html` — `OFERTA_DE_PLANO` — e chave de uma linha é
   exatamente o tipo de coisa que volta sozinha: alguém mexe na tela do Plano,
   reintroduz um preço, e ninguém percebe até o dono perguntar quanto custa.

   ── A METADE DIFÍCIL É O QUE NÃO PODE SUMIR JUNTO ─────────────────────────
   Tirar a oferta é fácil. O risco é levar embora, no mesmo movimento:

     · a COBRANÇA EM ABERTO, e aí quem tem um Pix por pagar não paga;
     · a ASSINATURA NO CARTÃO e o botão de desligar a renovação, e aí quem
       está pagando todo mês fica preso sem saída visível;
     · os MEDIDORES DE USO, e aí o dono bate no teto sem nenhuma tela que
       explique por quê.

   As três moravam dentro do bloco que saiu. Por isso metade das verificações
   daqui é sobre o que FICOU.

   ⚠ E REPARE NO QUE NÃO É OFERTA: o valor da cobrança em aberto CONTINUA na
   tela, de propósito. Não é preço de venda — é uma conta a pagar, e pedir que
   o dono pague um Pix sem dizer quanto seria pior que mostrar preço. A
   primeira versão deste teste proibia "R$" na aba inteira e reprovou por
   isso; a medida certa é por bloco.
   =========================================================================== */
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';
const sql = q => execFileSync('psql', ['-d','app','-qtAc',q],
  { env:{ ...process.env, PGHOST:'/tmp', PGPORT:'5444', PGUSER:'postgres' },
    encoding:'utf8' }).trim();

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);

function novaAba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(RAIZ + '/dados.js','utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const marca = Date.now().toString(36);
const d = novaAba();
await d.criarConta({ email:`plano-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona do Salão', telefone:'+5551' + (100000000 + (Date.now() % 89999999)) });
const cr = await d.chamar('criar_salao', { p_nome_salao:'Salão Plano ' + marca,
  p_tipo:'salao', p_telefone:'(51) 99887-6655', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;

/* O caso difícil: cartão LIGADO e um Pix em aberto ao mesmo tempo. As duas
   coisas moravam dentro do cartão de oferta que acabou de sair da tela. */
sql(`update public.assinaturas set plano='equipe', status='ativa',
       mp_preapproval='pre-teste-${marca}', cartao_desde=now()
     where salao_id='${SALAO}'`);
sql(`insert into public.cobrancas
       (salao_id, plano, valor, metodo, status, vence_em, mp_id, pix_copia_cola)
     values ('${SALAO}','equipe', 97, 'pix', 'pendente', now() + interval '2 days',
             'mp-${marca}', '00020126580014BR.GOV.BCB.PIX-TESTE-${marca}')`);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push(x.message));
await p.addInitScript(([base, ses]) => {
  window.AGENDAPRO = { url: base, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(ses));
}, [BASE, d.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(3500);
await p.click('a:has-text("Plano"), button:has-text("Plano")');
await p.waitForTimeout(2500);

const tela = await p.evaluate(() => {
  const t = document.getElementById('tela-plano');
  const visivel = el => !!(el && el.offsetParent !== null);
  return {
    texto: t ? t.innerText : '',
    oferta:   visivel(document.getElementById('ofertaPlano')),
    regua:    document.querySelectorAll('#reguaPlanos button').length,
    cartao:   (document.getElementById('cartaoPlano')||{}).innerHTML || '',
    assinar:  document.querySelectorAll('#tela-plano button').length,
    medidores: document.querySelectorAll('#tela-plano .medidor, #painelPlano .medidor').length,
    temCartaoAssin: !!document.getElementById('cartaoAssinatura'),
    temCobranca:    !!document.getElementById('cobrancaPendente'),
  };
});

console.log('\n── O QUE SAIU ──────────────────────────────────────────────');
e('o bloco da oferta não está visível', tela.oferta === false);
e('a régua de "quantos somos" sumiu', tela.regua === 0, tela.regua + ' botões');
e('o cartão de plano recomendado sumiu', tela.cartao.trim() === '');
e('nenhum "PLANO RECOMENDADO" na tela', !/PLANO RECOMENDADO/i.test(tela.texto));
e('nenhum botão de assinar', !/Assinar/i.test(tela.texto), tela.texto.slice(0,200));

/* ⚠ E A MESMA COISA SEM O CARTÃO LIGADO, que é o único caso em que o botão de
   assinar apareceria.

   A linha acima, sozinha, passava pelo motivo errado: com o cartão ativo, o
   `mostrarCartao()` já troca o botão de assinar por um texto — então ela dava
   verde mesmo com a oferta LIGADA. Medido: religando a chave, seis
   verificações reprovavam e essa não.

   Uma verificação que não consegue reprovar é pior que nenhuma: ela ocupa o
   lugar da que mediria. */
sql(`update public.assinaturas set mp_preapproval = null, cartao_desde = null
     where salao_id='${SALAO}'`);
await p.reload();
await p.waitForTimeout(3000);
await p.evaluate(() => irPara('plano'));
await p.waitForTimeout(1500);
const semCartao = await p.evaluate(() =>
  document.getElementById('tela-plano').innerText);
e('e sem cartão ligado — quando o botão APARECERIA — ele também não está lá',
  !/Assinar/i.test(semCartao), semCartao.slice(0, 250));

// Volta ao estado de antes: o resto do arquivo mede o cartão ligado.
sql(`update public.assinaturas set mp_preapproval='pre-teste-${marca}',
       cartao_desde = now() where salao_id='${SALAO}'`);
await p.reload();
await p.waitForTimeout(3000);
await p.evaluate(() => irPara('plano'));
await p.waitForTimeout(1500);
const precos = await p.evaluate(() => {
  const txt = id => (document.getElementById(id)||{}).innerText || '';
  const cobr = txt('cobrancaPendente') + txt('cartaoAssinatura');
  const tudo = document.getElementById('tela-plano').innerText;
  /* O texto da aba MENOS o das duas caixas que podem legitimamente mostrar
     valor. O que sobrar com R$ é preco de oferta, e nao devia estar la. */
  const resto = tudo.split('\n').filter(l => !cobr.includes(l.trim())).join('\n');
  return { resto, naCobranca: (cobr.match(/R\$\s*[\d.,]+/g)||[]) };
});
e('nenhum preço de OFERTA no corpo da aba', !/R\$\s*\d/.test(precos.resto),
  'achei: ' + (precos.resto.match(/R\$\s*[\d.,]+/g)||[]).join(', '));
e('mas o valor da cobrança em aberto CONTINUA — '
  + (precos.naCobranca.join(', ') || 'nenhum'),
  precos.naCobranca.length > 0,
  'pedir que o dono pague um Pix sem dizer quanto é pior que mostrar preço');
e('nem "por mês"', !/por mês/i.test(tela.texto));

console.log('\n── O QUE FICOU ─────────────────────────────────────────────');
e('o nome do plano continua', /Equipe|Grátis|Teste/i.test(tela.texto),
  tela.texto.slice(0, 200));
e('os medidores de uso continuam (' + tela.medidores + ')', tela.medidores > 0);
e('e dizem quantos profissionais cabem', /[Pp]rofissiona/.test(tela.texto));
e('a caixa da assinatura no cartão existe', tela.temCartaoAssin,
  'quem está no cartão ficaria preso, sem botão de desligar a renovação');
e('a caixa da cobrança em aberto existe', tela.temCobranca,
  'quem tem um Pix por pagar não teria como pagar');

await p.waitForTimeout(1500);
const depois = await p.evaluate(() => ({
  texto: document.getElementById('tela-plano').innerText,
  desligar: !!document.querySelector('#cartaoAssinatura button'),
  pix: (document.getElementById('cobrancaPendente')||{}).innerHTML || '',
}));
e('a renovação automática aparece, com o botão de desligar', depois.desligar,
  depois.texto.slice(0, 300));
/* Medido NA LINHA, e nao na aba inteira: a caixa da cobranca ali do lado tem
   valor de propósito, e olhar a aba toda confundia uma coisa com a outra. */
const linhaCartao = depois.texto.match(/Renovação automática[^\n]*/)?.[0] || '';
e('e o plano é nomeado nela, SEM o preço — "' + linhaCartao + '"',
  /Renovação automática/.test(linhaCartao) && !/R\$\s*\d/.test(linhaCartao),
  linhaCartao || '(não achei a linha)');
e('a cobrança em aberto aparece', /pendente|Pix|pagar|copia/i.test(depois.pix)
  || /Pix|pagar/i.test(depois.texto),
  'html da cobrança: ' + depois.pix.slice(0, 200));

console.log('\n── A SAÍDA PARA QUEM BATER NO LIMITE ───────────────────────');
const beco = await p.evaluate(() => {
  const t = document.getElementById('tela-plano').innerText;
  return { assine: /assine um plano/i.test(t),
           troque: /troque de plano/i.test(t),
           fale:   /fale com quem cuida/i.test(t) };
});
e('nenhum aviso manda "assine um plano"', !beco.assine);
e('nem "troque de plano"', !beco.troque);

console.log('\n── ERROS ───────────────────────────────────────────────────');
e('sem erro de JavaScript', erros.length === 0, erros.slice(0,3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
