/* ===========================================================================
   Sem internet não é "sem salão", nem "saia da conta"

   Achado no caça-bug: com o celular sem sinal (ou o wi-fi do salão caindo),
   toda leitura do `baixar()` falhava no `fetch` — e o erro era engolido como
   se fosse falta de permissão, devolvendo lista vazia. O painel abria dizendo
   "Nenhum salão nesta conta — crie o seu em dois minutos" para quem tem
   salão, agenda e caixa lá dentro.

   E pior, depois de uma hora parado: a renovação da sessão também falhava no
   `fetch`, e o `dados.js` lia isso como "refresh recusado" — apagava a sessão.
   Quem só estava sem sinal era deslogado, e sem sinal nem entrava de novo.

   Aqui o `dados.js` roda com um `fetch` de mentira. Nenhum servidor no ar.

       node tests/sem-rede.test.mjs
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
let ok = 0, falhas = 0;
const diz = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

/* `responde(url)` devolve a resposta, ou lança — que é o que o `fetch` faz
   quando não há rede ("Failed to fetch" no Chrome, "Load failed" no Safari). */
function montar(responde){
  const guardado = {};
  const janela = {
    AGENDAPRO: { url: 'https://projeto.supabase.co', chave: 'publica' },
    localStorage: {
      getItem: k => (k in guardado ? guardado[k] : null),
      setItem: (k, v) => { guardado[k] = String(v); },
      removeItem: k => { delete guardado[k]; },
    },
  };
  const fetchFalso = async (url) => responde(String(url));
  new Function('window', 'console', 'fetch', 'localStorage',
    fs.readFileSync(path.join(RAIZ, 'dados.js'), 'utf8'))(
      janela, { info(){}, error(){}, log(){}, warn(){} }, fetchFalso, janela.localStorage);
  return janela.Dados;
}
const responder = (status, corpo) => ({
  ok: status >= 200 && status < 300, status, statusText: '',
  json: async () => corpo, text: async () => JSON.stringify(corpo),
  headers: { get: () => null },
});
const semRede = () => { throw new TypeError('Failed to fetch'); };

console.log('\nSem internet ao abrir o painel');
{
  const Dados = montar(semRede);
  Dados.entrarComToken({ token: 'tk', refresh: 'r1', usuarioId: 'u1' });
  let erro = null, bd = null;
  try{ bd = await Dados.baixar(); }catch(e){ erro = e; }
  diz(erro && erro.semRede === true,
      'o baixar() FALHA dizendo que é rede, em vez de devolver tudo vazio',
      erro ? erro.message : 'devolveu ' + JSON.stringify(bd && { saloes: bd.saloes }));
  diz(erro && /conex/i.test(erro.message) && !/config\.js/.test(erro.message),
      'com uma frase de gente ("sem conexão"), não de configuração', erro && erro.message);
  diz(Dados.sessao() && Dados.sessao().token === 'tk', 'e a sessão continua guardada');
}

console.log('\nSem internet depois de uma hora parado (token no fim da validade)');
{
  const Dados = montar(semRede);
  Dados.entrarComToken({ token: 'velho', refresh: 'r1', usuarioId: 'u1' });
  Dados.sessao().expiraEm = Date.now() + 10000;   // dentro do minuto de folga
  try{ await Dados.baixar(); }catch(e){ /* esperado */ }
  const s = Dados.sessao();
  diz(s && s.token === 'velho' && s.refresh === 'r1',
      'a renovação que não alcançou o servidor NÃO apaga a sessão (antes: deslogava)',
      JSON.stringify(s));
}

console.log('\nO servidor fora do ar (5xx) também é "agora não"');
{
  const Dados = montar(() => responder(503, { message: 'Service Unavailable' }));
  Dados.entrarComToken({ token: 'tk', refresh: 'r1', usuarioId: 'u1' });
  let erro = null;
  try{ await Dados.baixar(); }catch(e){ erro = e; }
  diz(erro && erro.semRede === true, 'o baixar() falha como rede, sem tela vazia', erro ? erro.message : 'não falhou');
}

console.log('\nO que já funcionava continua');
{
  // Refresh recusado de verdade (400): a sessão acabou, e sai.
  const Dados = montar(url => /grant_type=refresh_token/.test(url)
    ? responder(400, { error: 'invalid_grant', error_description: 'Refresh Token Not Found' })
    : responder(401, { message: 'JWT expired' }));
  Dados.entrarComToken({ token: 'velho', refresh: 'r1', usuarioId: 'u1' });
  const bd = await Dados.baixar();
  diz(!Dados.sessao(), 'refresh RECUSADO pelo servidor ainda encerra a sessão');
  diz(bd && bd.sessaoExpirou === true, 'e o painel recebe "sua sessão expirou", como antes');
}
{
  // Tabela que o banco ainda não tem (404): lista vazia, sem derrubar o painel.
  const Dados = montar(url => /\/rest\/v1\/pedidos\?/.test(url)
    ? responder(404, { code: 'PGRST205', message: "Could not find the table 'public.pedidos' in the schema cache" })
    : responder(200, []));
  Dados.entrarComToken({ token: 'tk', refresh: 'r1', usuarioId: 'u1' });
  let erro = null, bd = null;
  try{ bd = await Dados.baixar(); }catch(e){ erro = e; }
  diz(!erro && bd && Array.isArray(bd.saloes),
      'tabela que o banco ainda não tem continua vindo vazia, sem derrubar a abertura',
      erro && erro.message);
}

console.log(falhas ? `\n✗ ${falhas} de ${ok + falhas} falharam.` : `\n✓ ${ok} passaram, 0 falharam`);
process.exit(falhas ? 1 : 0);
