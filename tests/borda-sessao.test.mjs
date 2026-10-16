/* ===========================================================================
   A borda (Mercado Pago) com a sessão vencida

   Relatado: "Assinar com Pix" dava erro no primeiro clique e mostrava o QR
   no segundo. O token da sessão vale uma hora; o `Dados.borda()` era a única
   porta que o mandava do jeito que estava, sem renovar. Com o painel aberto
   há mais de uma hora, a borda respondia 401 ("Faça login de novo.") — e
   qualquer leitura do painel renovava a sessão logo depois, por isso o
   segundo clique funcionava.

   Aqui o `dados.js` roda com um `fetch` de mentira que faz o papel do
   Supabase: recusa o token velho na borda, troca o refresh por um token
   novo, e aceita o novo. Nenhum servidor no ar, nenhum Mercado Pago.

       node tests/borda-sessao.test.mjs
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

/* Um "Supabase" de mentira. `vivos` são os tokens que a borda aceita. */
function montar({ vivos, refreshVale = true, bordaResponde }){
  const pedidos = [];
  const guardado = {};
  const janela = {
    AGENDAPRO: { url: 'https://projeto.supabase.co', chave: 'publica' },
    localStorage: {
      getItem: k => (k in guardado ? guardado[k] : null),
      setItem: (k, v) => { guardado[k] = String(v); },
      removeItem: k => { delete guardado[k]; },
    },
  };
  const responder = (status, corpo) => ({
    ok: status >= 200 && status < 300, status,
    json: async () => corpo, text: async () => JSON.stringify(corpo),
    headers: { get: () => null },
  });
  const fetchFalso = async (url, op = {}) => {
    const auth = ((op.headers || {}).Authorization || '').replace('Bearer ', '');
    pedidos.push({ url: String(url), auth });
    if(/\/auth\/v1\/token\?grant_type=refresh_token/.test(url)){
      if(!refreshVale) return responder(400, { error: 'invalid_grant', error_description: 'Refresh Token Not Found' });
      vivos.add('novo');
      return responder(200, { access_token: 'novo', refresh_token: 'r2', expires_in: 3600, user: { id: 'u1' } });
    }
    if(/\/functions\/v1\//.test(url)){
      if(bordaResponde) return bordaResponde(auth, pedidos);
      if(!vivos.has(auth)) return responder(401, { erro: 'Faça login de novo.' });
      return responder(200, { ok: true, cobranca: { id: 'c1', metodo: 'pix', pixQrBase64: 'QR' } });
    }
    return responder(404, {});
  };
  new Function('window', 'console', 'fetch', 'localStorage',
    fs.readFileSync(path.join(RAIZ, 'dados.js'), 'utf8'))(
      janela, { info(){}, error(){}, log(){}, warn(){} }, fetchFalso, janela.localStorage);
  return { Dados: janela.Dados, pedidos };
}

console.log('\nToken vencido no meio do trabalho (a borda recusa com 401)');
{
  const { Dados, pedidos } = montar({ vivos: new Set() });
  Dados.entrarComToken({ token: 'velho', refresh: 'r1', usuarioId: 'u1' });
  let r = null, erro = null;
  try{ r = await Dados.borda('criar-cobranca', { salaoId: 's1', plano: 'individual', metodo: 'pix' }); }
  catch(e){ erro = e; }
  diz(!erro && r && r.cobranca && r.cobranca.pixQrBase64 === 'QR',
      'o PRIMEIRO pedido do Pix já devolve a cobrança com o QR', erro ? erro.message : '');
  const bordas = pedidos.filter(p => /functions/.test(p.url));
  diz(bordas.length === 2 && bordas[0].auth === 'velho' && bordas[1].auth === 'novo',
      'tentou com o token velho, renovou, e repetiu UMA vez com o novo',
      bordas.map(b => b.auth).join(' → '));
  diz(Dados.sessao().token === 'novo', 'e a sessão guardada passa a ser a nova');
}

console.log('\nToken no fim da validade: renova ANTES de pedir');
{
  const { Dados, pedidos } = montar({ vivos: new Set(['velho']) });
  Dados.entrarComToken({ token: 'velho', refresh: 'r1', usuarioId: 'u1' });
  // Vence daqui a 10 segundos — dentro do minuto de folga.
  const s = Dados.sessao(); s.expiraEm = Date.now() + 10000;
  await Dados.borda('criar-cobranca', { salaoId: 's1', plano: 'individual' });
  const bordas = pedidos.filter(p => /functions/.test(p.url));
  diz(bordas.length === 1 && bordas[0].auth === 'novo',
      'um pedido só, já com o token renovado', bordas.map(b => b.auth).join(' → '));
}

console.log('\nSessão que acabou de verdade (refresh recusado)');
{
  const { Dados, pedidos } = montar({ vivos: new Set(), refreshVale: false });
  Dados.entrarComToken({ token: 'velho', refresh: 'r1', usuarioId: 'u1' });
  let erro = null;
  try{ await Dados.borda('criar-cobranca', { salaoId: 's1', plano: 'individual' }); }
  catch(e){ erro = e; }
  diz(erro && /login/i.test(erro.message) && erro.status === 401,
      'diz "Faça login de novo", com o status 401 junto', erro ? erro.message + ' / ' + erro.status : 'não deu erro');
  diz(pedidos.filter(p => /functions/.test(p.url)).length === 1,
      'e não fica repetindo: um pedido à borda, sem laço');
}

console.log('\nRecusa que não é de sessão volta como está');
{
  const { Dados } = montar({ vivos: new Set(['velho']), bordaResponde: () => ({
    ok: false, status: 502, json: async () => ({ erro: 'O Mercado Pago não aceitou a cobrança agora.' }),
    text: async () => '', headers: { get: () => null } }) });
  Dados.entrarComToken({ token: 'velho', refresh: 'r1', usuarioId: 'u1' });
  let erro = null;
  try{ await Dados.borda('criar-cobranca', {}); }catch(e){ erro = e; }
  diz(erro && /Mercado Pago/.test(erro.message) && erro.status === 502,
      'a frase da borda chega na tela, com o status (a tela repete sozinha só em 5xx)',
      erro ? erro.message + ' / ' + erro.status : '');
}

console.log(falhas ? `\n✗ ${falhas} de ${ok + falhas} falharam.` : `\n✓ ${ok} passaram, 0 falharam`);
process.exit(falhas ? 1 : 0);
