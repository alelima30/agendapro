/* ===========================================================================
   AgendaPro — a conferência do aviso de status da Meta

   ── POR QUE ESTE ARQUIVO É .js E NÃO .ts ───────────────────────────────────
   Pelo mesmo motivo do `webhook-mp/assinatura.js`: o Deno importa daqui, e o
   teste (tests/status-whatsapp.test.js) importa EXATAMENTE este arquivo, no
   Node. Sem build, sem transpilar, sem duas cópias que divergem em silêncio.

   ── O QUE ESTE ENDEREÇO ACEITA DA INTERNET ────────────────────────────────
   O endereço do webhook é público por obrigação: a Meta precisa alcançá-lo
   sem login. Quem escrever um curl para cá está dizendo ao sistema "esta
   mensagem foi lida" ou "esta mensagem falhou".

   O estrago não é o de um webhook de pagamento, mas não é nenhum:

     • marcar como `lido` uma mensagem que ninguém abriu faz o salão parar de
       ligar para a cliente;
     • marcar como `falhou` DEVOLVE COTA — e cota devolvida sem limite é
       mensagem de graça para sempre.

   Por isso a assinatura é conferida sempre, e sem `META_APP_SECRET`
   configurado nada passa.

   Usa só WebCrypto, que Deno e Node 20+ têm nativamente.
   =========================================================================== */

/* ⚠ Comparar com `===` vaza, pelo tempo, o tamanho do prefixo que bateu. É
   pouco por tentativa, e é explorável em cima de um endereço que aceita
   tentativas ilimitadas. Comparação de tamanho fixo custa nada. */
export function iguaisEmTempoConstante(a, b){
  if(typeof a !== 'string' || typeof b !== 'string') return false;
  if(a.length !== b.length) return false;
  let dif = 0;
  for(let i = 0; i < a.length; i++) dif |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return dif === 0;
}

export async function hmacHex(segredo, texto){
  const chave = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(segredo),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bruto = await crypto.subtle.sign(
    'HMAC', chave, new TextEncoder().encode(texto));
  return [...new Uint8Array(bruto)]
    .map(b => b.toString(16).padStart(2, '0')).join('');
}

/* A Meta assina o CORPO CRU, byte a byte, com o App Secret, e manda o
   resultado em `X-Hub-Signature-256: sha256=<hex>`.

   ⚠ "Corpo cru" é literal. Ler o corpo como JSON e serializar de volta para
   conferir NÃO funciona: espaço, ordem de chave e escape de acento mudam, o
   HMAC muda junto, e todo aviso legítimo passa a ser recusado. O index.ts lê
   com `req.text()` uma vez só e usa esse mesmo texto para as duas coisas. */
export async function assinaturaConfere({ segredo, cabecalho, corpoBruto }){
  /* Sem segredo configurado não há o que conferir. Recusar é o certo: aceitar
     deixaria o endereço aberto justamente enquanto ninguém terminou de
     configurar — que é quando ninguém está olhando. */
  if(!segredo) return false;
  if(typeof cabecalho !== 'string' || typeof corpoBruto !== 'string') return false;

  const p = cabecalho.trim();
  if(!p.toLowerCase().startsWith('sha256=')) return false;
  const veio = p.slice(7).trim().toLowerCase();
  // Antes de gastar um HMAC: 64 dígitos hexadecimais ou não é assinatura.
  if(!/^[0-9a-f]{64}$/.test(veio)) return false;

  return iguaisEmTempoConstante(await hmacHex(segredo, corpoBruto), veio);
}

/* O aperto de mão do cadastro da URL no painel da Meta. Ela chama uma vez, de
   GET, com um token que só nós e ela conhecemos, e espera o `hub.challenge`
   de volta em texto puro. Errar isto trava o cadastro do webhook. */
export function desafioConfere({ modo, token, esperado }){
  if(!esperado) return false;
  if(modo !== 'subscribe') return false;
  return iguaisEmTempoConstante(String(token ?? ''), String(esperado));
}

/* De como a Meta chama para como o banco chama.

   `sent` fica de fora de propósito: o worker já escreveu 'enviado' quando a
   Graph API respondeu OK, com a hora certa. Reprocessar isso não acrescenta
   nada e só arrisca mexer numa linha já resolvida. */
const DE_META = { delivered: 'entregue', read: 'lido', failed: 'falhou' };

/* Desembrulha o aviso da Meta e devolve só o que interessa.

   O envelope é fundo — entry[] → changes[] → value.statuses[] — e cada nível
   pode vir ausente, vazio ou de outro formato. Nada aqui confia na forma: o
   que não for do jeito esperado é ignorado, não quebra a chamada. Um webhook
   que estoura com um payload estranho é um webhook que a Meta desativa
   depois de algumas tentativas.

   ⚠ `value.messages` é IGNORADO. É por ali que chega mensagem de cliente
   escrevendo para o salão, e responder a isso é chatbot — que está fora
   desta fase de propósito. O que este arquivo faz é ler status, só. */
export function statusesDoAviso(corpo){
  const fora = [];
  const entradas = Array.isArray(corpo?.entry) ? corpo.entry : [];
  for(const e of entradas){
    const mudancas = Array.isArray(e?.changes) ? e.changes : [];
    for(const c of mudancas){
      const lista = Array.isArray(c?.value?.statuses) ? c.value.statuses : [];
      for(const s of lista){
        const nosso = DE_META[String(s?.status ?? '')];
        if(!nosso) continue;
        const wamId = String(s?.id ?? '').trim();
        if(!wamId) continue;

        // O motivo da falha vem numa lista; a primeira basta para o histórico.
        const erro = Array.isArray(s?.errors) ? s.errors[0] : null;
        fora.push({
          wamId,
          status: nosso,
          codigo: erro ? String(erro.code ?? '').slice(0, 40) || null : null,
          msg: erro
            ? String(erro.title ?? erro.message ?? '').slice(0, 300) || null
            : null,
        });
      }
    }
  }
  return fora;
}
