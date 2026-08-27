/* ===========================================================================
   Achar o `pg`, onde quer que ele esteja

   ── O DEFEITO QUE ISTO EXISTE PARA CONSERTAR ───────────────────────────────
   Oito arquivos de teste tinham esta linha, cada um a sua cópia:

       const pg = exigir('./bancada/node_modules/pg');

   Caminho fixo, e certo numa máquina só: a de quem roda `tests/bancada/
   subir.sh` antes, porque é esse script que faz `npm i pg` lá dentro.

   No CI não existe essa pasta. O workflow monta o banco da bancada com psql
   e sobe o `postgrest.mjs` direto — nunca chama o `subir.sh` — e instala as
   dependências na RAIZ, com `npm install --no-save pg playwright`. Então as
   oito suítes morriam em MODULE_NOT_FOUND antes de testar coisa alguma.

   O placar dizia "✗ Reprovaram: cota plataforma auditoria grade semana
   papéis relatórios checkout motor", que se lê como nove defeitos no sistema
   e não era nenhum: era uma pasta no lugar errado.

   O CI deste projeto rodou 29 vezes e reprovou 29. Nunca ficou verde, nunca
   foi consertado, e por isso nunca protegeu nada — três defeitos chegaram ao
   ar nesta semana com o CI vermelho o tempo inteiro, indistinguível do
   vermelho de sempre. Um CI que sempre falha é pior que nenhum: ocupa o
   lugar de um que funcionaria e ensina todo mundo a ignorar o aviso.

   ── POR QUE UM ARQUIVO SÓ ──────────────────────────────────────────────────
   A mesma linha copiada em oito lugares é a mesma suposição errada em oito
   lugares, e o conserto num deles não conserta os outros sete. O `tudo.sh`
   já procurava o Playwright em três lugares antes de desistir; o `pg` não
   tinha nada disso. Agora tem, aqui, uma vez.
   =========================================================================== */
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const exigir = createRequire(import.meta.url);

/* Na ordem em que fazem sentido:

     1. PG_MODULO       para quem quiser apontar à mão
     2. tests/bancada/  onde o subir.sh instala, na máquina de desenvolvimento
     3. raiz do projeto onde o CI instala
     4. o resolvedor do node  global, ou node_modules acima da raiz */
const tentativas = [
  process.env.PG_MODULO,
  path.join(AQUI, 'bancada', 'node_modules', 'pg'),
  path.join(AQUI, '..', 'node_modules', 'pg'),
  'pg',
].filter(Boolean);

let achado = null;
const recusas = [];
for(const onde of tentativas){
  try{ achado = exigir(onde); break; }
  catch(e){ recusas.push(onde + ' → ' + (e.code || e.message)); }
}

if(!achado){
  /* Falhar dizendo o que fazer. A mensagem crua do node é uma pilha de
     `at Module._load` que não menciona `npm` em lugar nenhum, e foi ela que
     ficou 29 execuções no log sem ninguém agir. */
  throw new Error(
    'Não achei o módulo `pg`. Procurei em:\n  ' + recusas.join('\n  ')
    + '\n\nInstale com uma destas:\n'
    + '  bash tests/bancada/subir.sh      (desenvolvimento)\n'
    + '  npm install --no-save pg         (na raiz do projeto)\n'
    + '  PG_MODULO=/caminho/para/pg ...   (apontando à mão)');
}

export default achado;
