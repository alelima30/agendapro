/* ===========================================================================
   AgendaPro — desligar a renovação automática no cartão
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── ⚠ POR QUE ISTO NÃO É UM UPDATE NO BANCO ────────────────────────────────
   Quem debita o cartão todo mês é o Mercado Pago, e ele não lê a nossa tabela.
   Apagar o `mp_preapproval` sozinho produziria o pior desfecho que este
   projeto pode entregar: o painel dizendo "renovação desligada" e a fatura do
   dono continuando a chegar, mês após mês, sem nada no sistema explicando por
   quê. Ele cancelaria no cartão dele, contestaria, e teria razão.

   Por isso a ordem aqui é fixa:

     1. LER o identificador da pré-aprovação (com permissão conferida no banco)
     2. CANCELAR na fonte, na API do Mercado Pago
     3. só então limpar do nosso lado

   Efeito externo primeiro, estado local depois. Se o passo 2 falhar, nada
   mudou deste lado: o cartão continua ligado, o painel continua dizendo a
   verdade, e o dono pode tentar de novo. Não há o que desfazer.

   ── O QUE O CANCELAMENTO NÃO FAZ ───────────────────────────────────────────
   Não derruba o plano. O dono pagou este mês, e o mês é dele: `vence_em`
   continua valendo até o fim, e só então a assinatura vence como qualquer
   outra. Cortar o acesso na hora seria cobrar por trinta dias e entregar dez.

   ── A CREDENCIAL QUE SÓ EXISTE AQUI ────────────────────────────────────────
     MP_ACCESS_TOKEN            cancela assinatura na conta que recebe
     SUPABASE_SERVICE_ROLE_KEY  passa por cima de TODO o RLS
   =========================================================================== */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY     = Deno.env.get('SUPABASE_ANON_KEY')!;
const MP_TOKEN     = Deno.env.get('MP_ACCESS_TOKEN')!;

const CORS = {
  'Access-Control-Allow-Origin': Deno.env.get('PAINEL_ORIGEM') ?? '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const responder = (dados: unknown, status = 200) =>
  new Response(JSON.stringify(dados), {
    status, headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' },
  });

const rpc = async (nome: string, args: unknown) => {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  if(!r.ok) throw new Error(`${nome}: ${r.status} ${await r.text()}`);
  return r.json();
};

/* Quem está pedindo. Devolve o uuid do perfil, ou null. Não decodifica o JWT:
   quem diz se ele é válido é o servidor que o assinou. */
async function quemPediu(auth: string | null): Promise<string | null> {
  if(!auth || !auth.startsWith('Bearer ')) return null;
  const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: auth },
  });
  if(!r.ok) return null;
  const u = await r.json();
  return u?.id ?? null;
}

Deno.serve(async (req) => {
  if(req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if(req.method !== 'POST') return responder({ erro: 'method' }, 405);

  try{
    const quem = await quemPediu(req.headers.get('Authorization'));
    if(!quem) return responder({ erro: 'Faça login de novo.' }, 401);

    const pedidoTela = await req.json().catch(() => ({}));
    const salaoId = String(pedidoTela.salaoId ?? '');
    if(!salaoId) return responder({ erro: 'Faltou o salão.' }, 400);

    // 1) Quem é a pré-aprovação deste salão — e esta pessoa pode mexer nela?
    let atual;
    try{
      atual = await rpc('cartao_do_salao', { p_salao: salaoId, p_quem: quem });
    }catch(e){
      console.error('cartao_do_salao recusou', String(e).slice(0, 200));
      return responder({ erro: 'Não consegui ler a assinatura.' }, 403);
    }

    /* Já estava desligado. Responde ok em vez de erro: o dono clicou duas
       vezes, ou voltou numa aba velha, e o resultado que ele queria já é o
       estado atual. Erro aqui só faria ele achar que ficou pela metade. */
    if(!atual?.ligado){
      return responder({ ok: true, motivo: 'ja_desligado' });
    }

    /* 2) NA FONTE. `PUT /preapproval/{id}` com status `cancelled` é o que
       realmente para o débito. Tudo abaixo depende deste passo dar certo. */
    const id = String(atual.preapproval);
    const r = await fetch(`https://api.mercadopago.com/preapproval/${id}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${MP_TOKEN}`,
      },
      body: JSON.stringify({ status: 'cancelled' }),
    });

    if(!r.ok){
      const mp = await r.text();
      /* 404 é a pré-aprovação não existir mais lá — cancelada pelo dono na
         conta dele, ou por eles depois de tentativas demais. O débito já
         parou, que é o que importa; seguir e limpar deste lado deixa os dois
         contando a mesma história. Qualquer outro erro para aqui. */
      if(r.status !== 404){
        console.error('MP recusou o cancelamento', r.status, mp.slice(0, 300));
        return responder({ erro: 'O Mercado Pago não conseguiu cancelar a '
          + 'assinatura agora. O cartão CONTINUA ligado — tente de novo em '
          + 'alguns minutos.' }, 502);
      }
      console.error('MP: pré-aprovação já não existe', r.status);
    }

    // 3) E só agora o nosso lado.
    await rpc('cancelar_cartao', { p_salao: salaoId, p_quem: quem });

    console.log('cancelar-cartao', JSON.stringify({ ok: true }));
    return responder({ ok: true });

  }catch(e){
    console.error('cancelar-cartao falhou:', String(e).slice(0, 300));
    return responder({ erro: 'Não consegui cancelar agora.' }, 500);
  }
});
