/* ===========================================================================
   AgendaPro — toda tela do painel abre, e abre limpa

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/telas.test.mjs

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   As outras suítes entram FUNDO numa tela de cada vez: a agenda, o caixa, os
   pacotes, a aparência. Nenhuma passava por TODAS as abas só para ver se elas
   abrem.

   E uma não abria. A aba Pacotes estourava em demonstração — `pacotesDoSalao()`
   faz `doSalao(bd.pacotes)`, a semente não criava `bd.pacotes`, e
   `undefined.filter` derrubava a tela com um TypeError no console. Quem está
   conhecendo o sistema clicava em Pacotes e via uma tela em branco.

   A causa era mais larga que a aba: na nuvem o `baixar()` monta uma chave por
   tabela, sempre, nem que seja lista vazia; a semente montava só o que ela
   tinha para contar. Os dois modos discordavam sobre o que é o `bd`.

   ⚠ E POR ISSO ESTE TESTE RODA EM DEMONSTRAÇÃO, e não na bancada. É o modo em
   que o `bd` vem da semente, e é o que uma pessoa abre para conhecer o
   sistema antes de criar conta. Defeito aqui é defeito na vitrine do produto.

   O que ele mede, por tela: nenhum erro de JavaScript, a tela tem conteúdo de
   verdade (não ficou em branco), e a página não rola para o lado.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const BASE = 'http://127.0.0.1:8099/';

const nav = await chromium.launch({ executablePath:'/opt/pw-browsers/chromium' });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
let erros = [];
p.on('pageerror', e => erros.push('pageerror: ' + e.message));
p.on('console', m => { if(m.type()==='error') erros.push('console: ' + m.text()); });

await p.goto(BASE + 'app.html?demo=1');
await p.waitForTimeout(2500);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(900);

const telas = await p.evaluate(() => TELAS.map(t => [t[0], t[1]]));
console.log('telas no quadro: ' + telas.length + '\n');

let ruins = 0;
for(const [chave, rotulo] of telas){
  erros = [];
  /* ⚠ O `irPara()` PODE LEVANTAR, e foi assim que o defeito apareceu: o
     `pintarPacotes()` estourava dentro dele. Sem este `catch`, o arquivo
     morre com uma pilha e não diz QUAL tela quebrou — que é a única coisa
     que este teste existe para dizer. */
  let estourou = null;
  try{ await p.evaluate(k => irPara(k), chave); }
  catch(err){ estourou = String(err.message || err).split('\n')[0]; }
  if(estourou) erros.push('ao abrir: ' + estourou);
  await p.waitForTimeout(700);
  const r = estourou ? { id:null, vazia:0, titulo:'', rolaLado:false }
                     : await p.evaluate(() => {
    const t = document.querySelector('.tela.on');
    return {
      id: t ? t.id : null,
      vazia: t ? t.innerText.replace(/\s+/g,' ').trim().length : 0,
      titulo: (document.getElementById('tituloTela')||{}).textContent || '',
      rolaLado: document.documentElement.scrollWidth
              > document.documentElement.clientWidth,
    };
  });
  const mau = erros.length > 0 || r.vazia < 15 || r.rolaLado;
  if(mau) ruins++;
  console.log((mau ? '  ✗ ' : '  ✓ ') + rotulo.padEnd(18)
    + ' ' + String(r.vazia).padStart(5) + ' letras'
    + (r.rolaLado ? '  ROLA DE LADO' : '')
    + (erros.length ? '\n        ' + erros.slice(0,2).join('\n        ') : ''));
}

// e as sub-abas de Meu salão
console.log('\nas sub-abas de Meu salão');
await p.evaluate(() => irPara('salao'));
await p.waitForTimeout(700);
for(const sub of ['dados','aparencia','notificacoes']){
  erros = [];
  await p.evaluate(s => trocarAbaSalao(s), sub);
  await p.waitForTimeout(700);
  const r = await p.evaluate(() => {
    const t = document.querySelector('#painelSalao .sub-tela:not([hidden])')
           || document.querySelector('#painelSalao .sub-tela');
    return { letras: t ? t.innerText.replace(/\s+/g,' ').trim().length : 0,
             rolaLado: document.documentElement.scrollWidth
                     > document.documentElement.clientWidth };
  });
  const mau = erros.length > 0 || r.letras < 50 || r.rolaLado;
  if(mau) ruins++;
  console.log((mau ? '  ✗ ' : '  ✓ ') + sub.padEnd(14) + String(r.letras).padStart(5)
    + ' letras' + (r.rolaLado ? '  ROLA DE LADO' : '')
    + (erros.length ? '\n        ' + erros.slice(0,2).join('\n        ') : ''));
}

console.log('\n' + (ruins ? ruins + ' tela(s) com problema'
                          : (telas.length + 3) + ' telas abriram limpas'));
await nav.close();
process.exit(ruins ? 1 : 0);
