/* ===========================================================================
   AgendaPro — o aviso de status da Meta
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── O QUE ELE FAZ ─────────────────────────────────────────────────────────
   É a outra metade do `enviar-notificacoes`. Aquele manda e escreve
   'enviado'; este recebe o que a Meta conta depois e move a linha para
   `entregue`, `lido` ou `falhou`.

   Sem ele, esses três estados não existem — e o painel diz isso em vez de
   estimar. A regra da fase não é só "não marcar como enviado sem ter
   enviado": é não inventar estado nenhum.

   ── E O `falhou` É O QUE MAIS IMPORTA ─────────────────────────────────────
   `delivered` e `read` são informação. `failed` é correção: a Meta aceitou a
   mensagem, devolveu um wam_id, a linha virou 'enviado' e já custou cota — e
   só depois ela descobre que não dá para entregar. Sem este arquivo, essa
   linha diz "enviado" para sempre, e o salão acha que avisou.

   ── ESTE ENDEREÇO É PÚBLICO POR OBRIGAÇÃO ─────────────────────────────────
   A Meta precisa alcançá-lo sem login, então qualquer pessoa na internet pode
   fazer POST aqui. Duas travas:

     1. ASSINATURA. `X-Hub-Signature-256` é um HMAC-SHA256 do corpo cru feito
        com o App Secret. Sem bater, é 401. Sem `META_APP_SECRET` configurado,
        NADA passa — nem um aviso perfeito.

     2. O `wam_id`. Mesmo com assinatura boa, o corpo não escolhe qual linha
        muda: ele diz um id que a Meta gerou no envio, e só casa com uma linha
        que ESTE sistema mandou. Não há como apontar para uma mensagem alheia
        sem ter visto o id dela.

   E a terceira trava está no banco: `notificacao_status()` nunca anda para
   trás e nunca ressuscita uma linha cancelada.

   ── POR QUE QUASE TUDO RESPONDE 200 ───────────────────────────────────────
   Aviso de mensagem que não é nossa, status que não tratamos, corpo
   estranho: tudo 200. A Meta reenvia o que não devolve 2xx, em escala
   crescente, e DESATIVA o webhook depois de insistir bastante. O 401 é
   reservado para assinatura errada, que é tentativa de fraude e tem que
   constar no log.
   =========================================================================== */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
// O App Secret do app da Meta (Configurações → Básico), não o token de envio.
const APP_SECRET   = Deno.env.get('META_APP_SECRET') ?? '';
// Uma frase sua, digitada no painel da Meta ao cadastrar a URL do webhook.
const VERIFY_TOKEN = Deno.env.get('WHATSAPP_VERIFY_TOKEN') ?? '';

/* A conferência mora em `assinatura.js`, ao lado, e não aqui dentro — porque
   precisa rodar também no Node, no tests/status-whatsapp.test.js. */
import { assinaturaConfere, desafioConfere, statusesDoAviso }
  from './assinatura.js';

async function rpc(nome: string, args: Record<string, unknown>) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${await r.text()}`);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  /* ── O APERTO DE MÃO ──────────────────────────────────────────────────────
     Acontece uma vez, quando você cadastra a URL no painel da Meta. Ela chama
     de GET e espera o `hub.challenge` de volta em TEXTO PURO — devolver JSON
     aqui faz o cadastro falhar com uma mensagem que não explica nada. */
  if (req.method === 'GET') {
    const ok = desafioConfere({
      modo:  url.searchParams.get('hub.mode'),
      token: url.searchParams.get('hub.verify_token'),
      esperado: VERIFY_TOKEN,
    });
    if (!ok) {
      if (!VERIFY_TOKEN) console.error('WHATSAPP_VERIFY_TOKEN não configurado.');
      return new Response('não autorizado', { status: 403 });
    }
    return new Response(url.searchParams.get('hub.challenge') ?? '', {
      status: 200, headers: { 'Content-Type': 'text/plain' } });
  }

  if (req.method !== 'POST') return new Response('ok', { status: 200 });

  try {
    /* ⚠ UMA leitura só, e é ela que vale para as duas coisas. O HMAC é do
       corpo cru; reserializar o JSON muda espaço, ordem e escape de acento, e
       aí NENHUM aviso legítimo passa. */
    const corpoBruto = await req.text();

    const confere = await assinaturaConfere({
      segredo: APP_SECRET,
      cabecalho: req.headers.get('x-hub-signature-256') ?? '',
      corpoBruto,
    });
    if (!confere) {
      if (!APP_SECRET) console.error('META_APP_SECRET não configurado.');
      console.error('status-whatsapp: assinatura inválida');
      return new Response('assinatura inválida', { status: 401 });
    }

    let corpo: unknown = {};
    try { corpo = JSON.parse(corpoBruto); } catch { corpo = {}; }

    const statuses = statusesDoAviso(corpo);
    let aplicados = 0;
    for (const s of statuses) {
      await rpc('notificacao_status', {
        p_wam_id: s.wamId,
        p_status: s.status,
        p_codigo: s.codigo,
        p_msg: s.msg,
      });
      aplicados++;
    }

    /* O log guarda a contagem e os estados, nunca o aviso inteiro: ele traz o
       telefone de quem recebeu. */
    if (aplicados) {
      console.log('status-whatsapp',
        JSON.stringify(statuses.map((s) => s.status)));
    }
    return new Response('ok', { status: 200 });

  } catch (e) {
    console.error('status-whatsapp falhou:', String(e).slice(0, 300));
    // 500 para a Meta tentar de novo: pode ter sido o banco, não o aviso.
    return new Response('erro', { status: 500 });
  }
});
