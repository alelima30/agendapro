/* ===========================================================================
   AgendaPro — contratar, cancelar (e a plataforma dar cortesia ou preço) um
   módulo adicional, como o Crediário
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── ⚠ POR QUE ISTO NÃO É SÓ UM UPDATE NO BANCO ─────────────────────────────
   Quem paga no cartão tem o valor da mensalidade guardado NO MERCADO PAGO
   (a pré-aprovação). Contratar o Crediário sem mudar o valor lá daria o
   módulo de graça todo mês; cancelar sem mudar lá continuaria cobrando um
   módulo que o dono desligou — e ele descobriria na fatura.

   Por isso a ordem é a do `cancelar-cartao`:

     1. a CONTA, no banco (`preparar_adicional`): pode? quanto passa a ser?
        Não grava nada.
     2. o VALOR NO CARTÃO, na API do Mercado Pago — só se o salão está no
        cartão e o valor muda.
     3. só então GRAVAR (`aplicar_adicional`), conferindo que a conta não
        mudou no meio. Se o banco recusar, o valor do cartão volta ao de antes.

   Quem paga no Pix não tem nada lá fora: o passo 2 não acontece, e o próximo
   Pix já nasce com o valor novo (13, `abrir_cobranca`).

   ── O VALOR NUNCA VEM DA TELA ──────────────────────────────────────────────
   A tela manda o salão, o módulo e a ação. O preço é lido do banco — a mesma
   regra do checkout (criar-cobranca) e do cartão (assinar-cartao).

   ── A CREDENCIAL QUE SÓ EXISTE AQUI ────────────────────────────────────────
     MP_ACCESS_TOKEN            muda o valor da assinatura na conta que recebe
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

/* O erro do banco vem como texto do PostgREST. A mensagem (`message`) é
   escrita para o dono ("Regularize a mensalidade primeiro…") e pode ir para
   a tela; o resto do corpo, não. */
class ErroDoBanco extends Error {
  constructor(public status: number, public mensagem: string){ super(mensagem); }
}
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
  if(!r.ok){
    const corpo = await r.json().catch(() => ({}));
    throw new ErroDoBanco(r.status, String(corpo?.message ?? `${nome}: ${r.status}`));
  }
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

/* Muda o valor mensal da pré-aprovação. 404 é ela não existir mais lá
   (cancelada na conta do dono, ou pelo Mercado Pago): não há o que mudar, e
   o webhook vai desligar o cartão do nosso lado. */
async function valorNoCartao(preapproval: string, valor: number): Promise<'ok' | 'sumiu' | 'erro'> {
  const r = await fetch(`https://api.mercadopago.com/preapproval/${preapproval}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${MP_TOKEN}` },
    body: JSON.stringify({ auto_recurring: { transaction_amount: valor, currency_id: 'BRL' } }),
  });
  if(r.ok) return 'ok';
  const mp = await r.text();
  if(r.status === 404){
    console.error('adicional: a pré-aprovação já não existe no MP');
    return 'sumiu';
  }
  // ⚠ Só o começo, e sem o pedido: a resposta do MP às vezes ecoa o e-mail do pagador.
  console.error('adicional: MP recusou mudar o valor', r.status, mp.slice(0, 200));
  return 'erro';
}

const ACOES = ['contratar', 'cancelar', 'cortesia', 'sem_cortesia', 'preco'];

Deno.serve(async (req) => {
  if(req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if(req.method !== 'POST') return responder({ erro: 'method' }, 405);

  try{
    const quem = await quemPediu(req.headers.get('Authorization'));
    if(!quem) return responder({ erro: 'Faça login de novo.' }, 401);

    const pedido = await req.json().catch(() => ({}));
    const salaoId   = String(pedido.salaoId ?? '');
    const adicional = String(pedido.adicional ?? '');
    const acao      = String(pedido.acao ?? '');
    // Só a plataforma manda preço (a função do banco confere quem é).
    const preco = pedido.preco === null || pedido.preco === undefined || pedido.preco === ''
      ? null : Number(pedido.preco);
    if(!/^[0-9a-f-]{36}$/i.test(salaoId) || !adicional || !ACOES.includes(acao)){
      return responder({ erro: 'Pedido incompleto.' }, 400);
    }
    if(preco !== null && !(preco >= 0)) return responder({ erro: 'Preço inválido.' }, 400);
    const args = { p_salao: salaoId, p_adicional: adicional, p_acao: acao, p_quem: quem, p_preco: preco };

    // 1) A conta: pode? quanto passa a ser?
    let conta;
    try{
      conta = await rpc('preparar_adicional', args);
    }catch(e){
      if(e instanceof ErroDoBanco && e.status < 500) return responder({ erro: e.mensagem }, 403);
      throw e;
    }
    if(!conta?.mudou){
      return responder({ ok: true, efeito: conta?.efeito, mensalidade: Number(conta?.antes) });
    }

    // 2) O valor no cartão, se o salão está no cartão e o valor muda.
    const antes = Number(conta.antes), depois = Number(conta.depois);
    const pre = conta.preapproval ? String(conta.preapproval) : '';
    let mudouCartao = false;
    if(pre && antes !== depois && depois > 0){
      const feito = await valorNoCartao(pre, depois);
      if(feito === 'erro'){
        return responder({ erro: 'O Mercado Pago não aceitou mudar o valor da sua assinatura '
          + 'agora. Nada mudou — tente de novo em alguns minutos.' }, 502);
      }
      mudouCartao = feito === 'ok';
    }

    // 3) Gravar, conferindo que a conta é a mesma.
    try{
      const feito = await rpc('aplicar_adicional', { ...args, p_esperado: depois });
      console.log('adicional', JSON.stringify({ acao, adicional, efeito: feito?.efeito, cartao: mudouCartao }));
      return responder({ ...feito, cartao: !!pre });
    }catch(e){
      /* O banco recusou depois de o cartão mudar: o cartão volta ao valor de
         antes. Se nem isso der, fica no log — e o `registrar_recorrencia`
         aceita o mês com qualquer das composições conhecidas (46,
         `itens_que_batem`), para o plano não vencer por isso. */
      if(mudouCartao && await valorNoCartao(pre, antes) !== 'ok'){
        console.error('adicional: NÃO consegui desfazer o valor do cartão', JSON.stringify({ antes, depois }));
      }
      if(e instanceof ErroDoBanco && e.status < 500) return responder({ erro: e.mensagem }, 409);
      throw e;
    }

  }catch(e){
    // Nunca `console.error(req)` nem o corpo: leva token de sessão para o log.
    console.error('adicional falhou:', String(e).slice(0, 300));
    return responder({ erro: 'Não consegui mudar o módulo agora. Tente de novo em alguns minutos.' }, 500);
  }
});
