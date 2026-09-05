/* ===========================================================================
   AgendaPro — ligar a assinatura no cartão
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── AS DUAS CREDENCIAIS QUE SÓ EXISTEM AQUI ────────────────────────────────
     MP_ACCESS_TOKEN            cria a assinatura recorrente na conta que recebe
     SUPABASE_SERVICE_ROLE_KEY  passa por cima de TODO o RLS

   Nenhuma das duas pode encostar no painel. O painel é HTML servido do GitHub
   Pages: tudo o que chega nele é público por construção.

   ── ⚠ NENHUM DADO DE CARTÃO PASSA POR AQUI ─────────────────────────────────
   Esta função NÃO recebe número de cartão, CVV nem validade — e é de
   propósito. Ela cria uma PRÉ-APROVAÇÃO no Mercado Pago e devolve o endereço
   da página deles, onde o dono digita o cartão. O que volta para nós é um
   identificador.

   A diferença é de responsabilidade, não de conforto: não há formulário de
   cartão no nosso HTML, não há número passando pelo nosso servidor, e não há
   nós respondendo se algo vazar. Quem lida com cartão vencido, cartão trocado
   e nova tentativa também é eles — essa lista inteira é código que não existe
   neste projeto.

   ── O QUE ELA FAZ, E EM QUE ORDEM ──────────────────────────────────────────
     1. confere QUEM está pedindo, pelo token de sessão do painel
     2. pergunta ao BANCO se essa pessoa pode, quanto custa e para qual e-mail
     3. cria a pré-aprovação no Mercado Pago
     4. devolve o endereço da autorização — e mais nada

   ── ⚠ O QUE ELA NÃO FAZ: LIGAR O CARTÃO ────────────────────────────────────
   Ela não chama `ligar_cartao()`. Chegar até aqui é ter clicado num botão; não
   é ter autorizado nada. Quem liga é o `webhook-mp`, quando o Mercado Pago
   avisa que a pré-aprovação foi autorizada — e mesmo lá o dado é relido da API
   deles, não acreditado do corpo do aviso.

   Se esta função marcasse o cartão como ligado, bastaria clicar em "Assinar"
   e fechar a aba para o salão constar como pagante sem nunca ter pago.

   ── ⚠ E O VALOR NUNCA VEM DO CORPO DA REQUISIÇÃO ───────────────────────────
   O navegador manda `salaoId` e `plano`. O preço é lido de `planos` dentro do
   `preparar_cartao()`, no banco. Aqui isso pesa mais do que no Pix avulso: o
   `transaction_amount` da pré-aprovação é o valor debitado TODO MÊS, para
   sempre. Aceitá-lo da tela seria uma mensalidade escolhida pelo cliente.
   =========================================================================== */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY     = Deno.env.get('SUPABASE_ANON_KEY')!;
const MP_TOKEN     = Deno.env.get('MP_ACCESS_TOKEN')!;
/* Para onde o Mercado Pago devolve o dono depois de ele autorizar. É
   obrigatório na pré-aprovação — sem `back_url` a API recusa o pedido. Cai no
   PAINEL_ORIGEM quando ninguém configurou um endereço mais preciso. */
const PAINEL_URL   = Deno.env.get('PAINEL_URL')
                  ?? Deno.env.get('PAINEL_ORIGEM') ?? '';

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

/* Quem está pedindo. Devolve o uuid do perfil, ou null.

   ⚠ Não decodifica o JWT aqui. Um JWT é base64 legível: qualquer pessoa monta
   um com o `sub` que quiser. Quem diz se ele é válido é o servidor que o
   assinou. */
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
    const plano   = String(pedidoTela.plano ?? '');
    if(!salaoId || !plano) return responder({ erro: 'Faltou o salão ou o plano.' }, 400);

    if(!PAINEL_URL){
      /* No log, e não só na resposta: quem vai olhar aqui é alguém tentando
         entender por que o botão não abre nada, e a resposta HTTP some da
         tela assim que ela é repintada. */
      console.error('assinar-cartao: falta PAINEL_URL (ou PAINEL_ORIGEM). '
                  + 'A pré-aprovação exige back_url.');
      return responder({ erro: 'A assinatura no cartão ainda não está '
        + 'configurada. Pague no Pix, ou fale com o suporte.' }, 503);
    }

    /* Permissão, preço e pagador vêm do banco de uma vez só. Se esta pessoa
       não for gestão deste salão, `preparar_cartao` recusa e a gente para
       aqui — a autorização é do banco, não deste arquivo. */
    let base;
    try{
      base = await rpc('preparar_cartao', {
        p_salao: salaoId, p_plano: plano, p_quem: quem });
    }catch(e){
      console.error('preparar_cartao recusou', String(e).slice(0, 200));
      return responder({ erro: 'Não consegui preparar a assinatura.' }, 403);
    }

    /* ⚠ DUAS PRÉ-APROVAÇÕES ATIVAS NO MESMO SALÃO É COBRANÇA DOBRADA.
       O Mercado Pago não sabe que as duas são nossas, e debita as duas todo
       mês. O dono descobre na fatura seguinte, e a conversa começa com ele já
       tendo pago duas vezes.

       Trocar de plano no cartão é cancelar e assinar de novo. São dois
       cliques, e é a versão desta tela que não cobra em duplicidade. */
    if(base?.jaLigado){
      return responder({ erro: 'Este salão já está no cartão. Para trocar de '
        + 'plano, cancele a renovação automática e assine de novo.' }, 409);
    }

    const email = String(base?.email ?? '').trim();
    if(!email){
      return responder({ erro: 'Preciso do e-mail do responsável no cadastro '
        + 'para criar a assinatura no cartão.' }, 400);
    }

    /* ── O pedido ao Mercado Pago ────────────────────────────────────────────
       `external_reference` é o id do SALÃO, e não o de uma cobrança — porque
       aqui o vínculo é permanente: uma pré-aprovação vale enquanto o cartão
       durar, e as cobranças mensais nascem dela.

       `status: 'pending'` é o que faz a API devolver `init_point`: a
       pré-aprovação fica esperando o dono autorizar na página deles. Com
       `authorized` ela exigiria um token de cartão — que é exatamente o dado
       que este projeto não quer ver. */
    const pedidoMp: Record<string, unknown> = {
      reason: `AgendaPro — plano ${base?.nomePlano ?? plano}`,
      external_reference: salaoId,
      payer_email: email,
      back_url: PAINEL_URL,
      status: 'pending',
      auto_recurring: {
        frequency: 1,
        frequency_type: 'months',
        transaction_amount: Number(base?.valor),
        currency_id: 'BRL',
      },
    };

    /* ⚠ E REPARE NO QUE NÃO VAI NO PEDIDO: `notification_url`.

       Os avisos desta assinatura chegam pelo webhook cadastrado no PAINEL do
       Mercado Pago — é ele que vem com o `x-signature`, e é essa assinatura
       que separa "o Mercado Pago avisou" de "alguém escreveu que avisou" num
       endereço que é público por obrigação.

       Mandar `notification_url` aqui liga uma SEGUNDA via de entrega, no
       formato antigo. O `webhook-mp` recusaria essas cópias com 401 e um
       "assinatura inválida" no log — que é exatamente o alarme reservado para
       tentativa de fraude. Encher esse log de ruído previsível é ensinar quem
       lê a ignorá-lo, e aí o alarme de verdade passa junto.

       Uma via só, sempre assinada. Marcar os dois eventos no painel é passo
       obrigatório do README ao lado, e sem eles nada chega. */

    const r = await fetch('https://api.mercadopago.com/preapproval', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${MP_TOKEN}`,
      },
      body: JSON.stringify(pedidoMp),
    });
    const mp = await r.json().catch(() => ({}));

    if(!r.ok){
      /* ⚠ O ERRO DO MERCADO PAGO NÃO VAI INTEIRO PARA A TELA: ele às vezes
         ecoa parte do pedido, e o pedido carrega o e-mail do pagador. */
      console.error('MP recusou a pré-aprovação', r.status,
        JSON.stringify(mp).slice(0, 400));

      /* Este erro merece nome próprio. O Mercado Pago recusa quando o e-mail
         do pagador é o da PRÓPRIA CONTA que recebe — ninguém assina de si
         mesmo. É o primeiro tropeço de quem testa com a própria conta, e a
         mensagem crua ("Invalid users involved") não diz nada disso. */
      const cru = JSON.stringify(mp);
      if(/Invalid users involved|cannot.*same user/i.test(cru)){
        return responder({ erro: 'O e-mail do responsável é o mesmo da conta '
          + 'que recebe os pagamentos. O Mercado Pago não deixa alguém assinar '
          + 'de si mesmo — use outro e-mail no cadastro do salão.' }, 400);
      }
      return responder({ erro: 'O Mercado Pago não aceitou a assinatura '
        + 'agora. Tente de novo em alguns minutos.' }, 502);
    }

    const endereco = mp?.init_point ?? mp?.sandbox_init_point ?? null;
    if(!endereco){
      console.error('MP não devolveu init_point', JSON.stringify(mp).slice(0, 300));
      return responder({ erro: 'O Mercado Pago não devolveu o endereço da '
        + 'autorização. Tente de novo em alguns minutos.' }, 502);
    }

    /* O `id` da pré-aprovação NÃO volta para a tela, e não é gravado aqui.
       Ele chega pelo webhook, depois de autorizado — que é o único momento em
       que ele significa alguma coisa. Guardá-lo agora daria um salão com
       cartão "ligado" que nunca foi autorizado. */
    console.log('assinar-cartao', JSON.stringify({ plano, criada: true }));
    return responder({ ok: true, url: endereco });

  }catch(e){
    // Nunca `console.error(req)` nem o corpo: leva token de sessão para o log.
    console.error('assinar-cartao falhou:', String(e).slice(0, 300));
    return responder({ erro: 'Não consegui abrir a assinatura agora.' }, 500);
  }
});
