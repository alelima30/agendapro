/* ===========================================================================
   AgendaPro — o check-up do sistema, para quem vigia de fora
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── O QUE ELE FAZ ─────────────────────────────────────────────────────────
   O UptimeRobot (ou qualquer monitor) visita este endereço a cada 5 minutos.
   Ele pergunta ao banco `saude_publica()` (40_saude.sql) e responde:

     · 200 — tudo certo, ou só "atenção" (uma cliente sem WhatsApp, uma
             mensagem tentando de novo): nada que mereça acordar alguém;
     · 503 — problema: o despertador parou, a função de envio recusa, há
             mensagem atrasada, o token da Meta venceu… O monitor avisa.

   O detalhe — o que está errado e o que fazer — fica no admin.html, cartão
   "Saúde do sistema". Aqui só sai o nível e as CHAVES ("despertador",
   "falhas"), porque o endereço é público: nenhum nome de salão, telefone ou
   texto de mensagem passa por este arquivo.

   ── POR QUE O ALERTA NÃO É PELO WHATSAPP ──────────────────────────────────
   Se o que quebrou foi o WhatsApp, o aviso também não chegaria. O monitor de
   fora avisa por e-mail, pelo app dele ou pelo Telegram.

   ── PÚBLICO DE PROPÓSITO ──────────────────────────────────────────────────
   Publicado SEM verificação de JWT: o monitor não tem token do Supabase. Não
   há o que proteger — a resposta não tem dado de ninguém — e o banco só deixa
   o `service_role` executar `saude_publica()`.
   =========================================================================== */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const CABECALHOS = {
  'Content-Type': 'application/json; charset=utf-8',
  // Um monitor olhando uma resposta guardada diria "ok" com o sistema parado.
  'Cache-Control': 'no-store',
};

function responder(corpo: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(corpo), { status, headers: CABECALHOS });
}

Deno.serve(async (req) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return responder({ erro: 'use GET' }, 405);
  }
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/saude_publica`, {
      method: 'POST',
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    /* O banco não respondeu: isso JÁ é o problema. 503, e não 500 — para o
       monitor é a mesma coisa (avisa), e 503 diz "fora do ar", que é o caso. */
    if (!r.ok) {
      console.error('saude: o banco respondeu', r.status);
      return responder({ nivel: 'problema', problemas: ['banco'] }, 503);
    }
    const s = await r.json();
    return responder(s, s && s.nivel === 'problema' ? 503 : 200);
  } catch (e) {
    console.error('saude: sem resposta do banco:', String((e as Error).message).slice(0, 200));
    return responder({ nivel: 'problema', problemas: ['banco'] }, 503);
  }
});
