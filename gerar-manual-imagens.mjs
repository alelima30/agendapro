/* ===========================================================================
   AgendaPro — tira os prints do manual, com os números em cima dos botões

     python3 -m http.server 8099 --directory .     (noutro terminal)
     node gerar-manual-imagens.mjs
     node gerar-manual-pdf.mjs                     (o PDF leva as imagens novas)

   Os prints saem da DEMONSTRAÇÃO (`?demo=1`), nunca de um salão de verdade:
   nome e telefone de cliente não podem ir parar num manual público.

   O número desenhado em cima de cada botão é o mesmo que a legenda do
   manual.html cita ("1 — o menu"). Se um botão mudar de lugar ou de nome, o
   print novo acompanha sozinho; se ele SUMIR, o script avisa e sai com erro
   — print com o número apontando para o vazio é pior que print nenhum.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const RAIZ = path.dirname(fileURLToPath(import.meta.url));
const BASE = (process.env.BASE || 'http://127.0.0.1:8099/').replace(/\/?$/, '/');
const SAIDA = path.join(RAIZ, 'manual');
fs.mkdirSync(SAIDA, { recursive: true });

const faltou = [];

/* Desenha os números. Cada marca é [seletor, número, posição]; a posição diz
   em que canto do botão o número fica, para não tapar o texto dele. */
async function marcar(p, marcas){
  for(const [sel, n, canto = 'esq'] of marcas){
    const ok = await p.evaluate(([sel, n, canto]) => {
      const el = [...document.querySelectorAll(sel)].find(e => e.offsetParent !== null);
      if(!el) return false;
      // Fora da tela (o pé do menu no celular): rola até ele antes de medir.
      let r = el.getBoundingClientRect();
      if(r.bottom > innerHeight || r.top < 0){
        el.scrollIntoView({ block:'center' }); r = el.getBoundingClientRect();
      }
      if(!document.getElementById('mnEstilo')){
        const st = document.createElement('style'); st.id = 'mnEstilo';
        st.textContent = `.mn-anel{position:fixed;z-index:99998;pointer-events:none;
            border:3px solid #E11D48;border-radius:10px}
          .mn-num{position:fixed;z-index:99999;pointer-events:none;width:30px;height:30px;
            border-radius:50%;background:#E11D48;color:#fff;display:grid;place-items:center;
            font:800 16px/1 system-ui,sans-serif;box-shadow:0 0 0 3px #fff,0 3px 8px rgba(0,0,0,.35)}`;
        document.head.appendChild(st);
      }
      const anel = document.createElement('div'); anel.className = 'mn-anel';
      Object.assign(anel.style, { left:(r.left-4)+'px', top:(r.top-4)+'px',
        width:(r.width+8)+'px', height:(r.height+8)+'px' });
      const num = document.createElement('div'); num.className = 'mn-num'; num.textContent = n;
      const x = canto === 'dir' ? r.right - 8 : r.left - 22;
      const y = r.top - 22;
      Object.assign(num.style, { left:Math.max(2, Math.min(innerWidth-34, x))+'px',
                                 top:Math.max(2, y)+'px' });
      document.body.append(anel, num);
      return true;
    }, [sel, n, canto]);
    if(!ok) faltou.push(`${sel} (número ${n})`);
  }
}
async function limpar(p){
  await p.evaluate(() => document.querySelectorAll('.mn-anel,.mn-num').forEach(e => e.remove()));
}
async function foto(p, nome, marcas = []){
  await p.waitForTimeout(500);
  await marcar(p, marcas);
  await p.screenshot({ path: path.join(SAIDA, nome + '.jpg'), type:'jpeg', quality:82 });
  await limpar(p);
  console.log('  ✓ ' + nome);
}

const nav = await chromium.launch();

/* ── O PAINEL, NO COMPUTADOR ─────────────────────────────────────────────── */
const ctx = await nav.newContext({ viewport:{ width:1280, height:800 }, deviceScaleFactor:1,
                                   colorScheme:'light', locale:'pt-BR' });
const p = await ctx.newPage();
const erros = []; p.on('pageerror', e => erros.push(e.message));
await p.goto(BASE + 'app.html?demo=1&comanda=0');
await p.waitForTimeout(2500);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(600);

const ir = async (k, sub) => {
  await p.evaluate(([k, sub]) => { fecharModal && fecharModal(); irPara(k);
    if(sub) trocarAbaSalao(sub); }, [k, sub]);
  await p.waitForTimeout(700);
};
const fechar = () => p.evaluate(() => fecharModal());

await ir('agenda');
await foto(p, 'agenda', [
  ['#abas', 1, 'dir'], ['#vistas', 2], ['button[onclick="abrirNovo()"]', 3, 'dir'],
  ['#btAjuda', 4], ['.grade .ag', 5, 'dir'],
]);

await p.click('#btAjuda');
await foto(p, 'ajuda', [['#ajudaManual', 1], ['#ajudaWhats', 2]]);
await p.evaluate(() => fecharMenuAjuda());

await p.evaluate(() => abrirNovo());
await foto(p, 'novo-agendamento', [['#modalPe .btn-p', 1, 'dir']]);
await fechar();

await p.evaluate(() => {
  // Um PENDENTE: é nele que aparece o "Confirmar horário" que o manual cita.
  const meus = (bd.agendamentos || []).filter(x => x.salaoId === salaoAtual);
  const a = meus.find(x => x.status === 'pendente') || meus.find(x => x.status !== 'cancelado');
  abrirDetalhe(a.id);
});
await foto(p, 'detalhe', [
  ['#modalPe button[onclick^="confirmarHorario"]', 1],
  ['#modalPe button[onclick^="falarNoWhatsapp"]', 2],
  ['#modalPe button[onclick^="salvarStatus"]', 3, 'dir'],
]);
await fechar();

await ir('servicos');
await foto(p, 'servicos', [['#btNovoServico', 1, 'dir']]);
await p.evaluate(() => abrirServico(servsAtivos()[0].id));
await foto(p, 'servico-form', [['#sAtivo', 1]]);
await fechar();

await ir('equipe');
await foto(p, 'equipe', [
  ['button[onclick="abrirProf()"]', 1, 'dir'],
  ['#listaEquipe button[onclick^="abrirBloqueio"]', 2], ['#cartaoAcessos', 3],
]);

await ir('salao', 'dados');
await foto(p, 'negocio-dados', [['#subAbasSalao', 1]]);
await ir('salao', 'aparencia');
await foto(p, 'negocio-aparencia');
await ir('salao', 'notificacoes');
await foto(p, 'negocio-notificacoes');

await ir('publico');
// O print mostra o endereço do SITE, não o do computador que tirou o print.
await p.evaluate(() => {
  document.getElementById('linkPublico').value = 'https://www.agendaprogestao.com.br/agendar.html?salao=studio-bella';
});
await foto(p, 'link', [
  ['#linkPublico', 1], ['button[onclick^="copiarLink"]', 2, 'dir'],
  ['#qrDoLink', 3], ['#abrirComoCliente', 4, 'dir'],
]);

await ir('clientes');
await foto(p, 'clientes', [['#buscaCliente', 1], ['button[onclick="abrirCliente()"]', 2, 'dir']]);
await ir('aniversarios');
await foto(p, 'aniversariantes');
await ir('hoje');
await foto(p, 'hoje');
await ir('dashboard');
await foto(p, 'dashboard');
await ir('relatorios');
await foto(p, 'relatorios', [['#relAtalhos', 1], ['#relDe', 2]]);
await ir('plano');
await foto(p, 'plano');

/* ── NO CELULAR ──────────────────────────────────────────────────────────── */
const cel = await nav.newContext({ viewport:{ width:390, height:780 }, deviceScaleFactor:2,
                                   isMobile:true, hasTouch:true, locale:'pt-BR' });
const c = await cel.newPage();
c.on('pageerror', e => erros.push(e.message));
await c.goto(BASE + 'app.html?demo=1&comanda=0');
await c.waitForTimeout(2500);
await c.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await foto(c, 'celular-agenda', [['.menu-botao', 1, 'dir'], ['#btAjuda', 2]]);
await c.evaluate(() => alternarLateral());
await foto(c, 'celular-menu', [['#latManual', 1], ['#btInstalar', 2]]);

/* O link da cliente: o que ela vê ao abrir no WhatsApp. */
await c.goto(BASE + 'agendar.html?salao=studio-bella&demo=1');
await c.waitForTimeout(2500);
await foto(c, 'cliente-link');

await nav.close();

if(erros.length) console.log('\n⚠ erros de JavaScript nas telas:\n  ' + erros.slice(0, 5).join('\n  '));
if(faltou.length){
  console.log('\n✗ botões que sumiram (o número não foi desenhado):\n  ' + faltou.join('\n  '));
  process.exit(1);
}
console.log(`\n✓ prints em manual/ — agora rode: node gerar-manual-pdf.mjs`);
