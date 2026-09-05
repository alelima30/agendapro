/* ===========================================================================
   AgendaPro — o aviso de pagamento do Mercado Pago
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── ESTE É O ENDEREÇO MAIS EXPOSTO DO SISTEMA ──────────────────────────────
   Ele é público por obrigação: o Mercado Pago precisa alcançá-lo sem login.
   Ou seja, QUALQUER PESSOA NA INTERNET pode fazer POST aqui dizendo "a
   cobrança tal foi paga". Se este arquivo acreditar no que recebe, o produto
   é de graça para quem souber escrever um curl.

   Por isso são DUAS conferências, e nenhuma delas confia no corpo do aviso:

     1. ASSINATURA. O Mercado Pago manda `x-signature` com um HMAC-SHA256 do
        aviso, feito com um segredo que só nós e ele temos. Sem bater, é 401.

     2. A FONTE. Mesmo com a assinatura boa, o corpo do aviso não é usado como
        verdade: ele diz só o ID do pagamento. Status e valor são LIDOS DA API
        do Mercado Pago, com o nosso token. Assim, mesmo que a assinatura
        vazasse um dia, ainda seria preciso que o pagamento existisse e
        estivesse aprovado lá.

   E a terceira trava não está aqui — está no banco. `registrar_pagamento()`
   é idempotente: o Mercado Pago reenvia o mesmo aviso até receber 200, e
   reenvia de novo a cada mudança do pagamento. Cada chegada somando um mês
   daria meio ano de assinatura a quem pagou uma vez.

   ── POR QUE QUASE TUDO RESPONDE 200 ────────────────────────────────────────
   Aviso que não é nosso, pagamento que não está aprovado, cobrança que não
   existe: tudo isso é 200. Responder erro faz o Mercado Pago reenviar em
   escala crescente por dias. O 401 é reservado para o que interessa — aviso
   com assinatura errada, que é tentativa de fraude e tem que constar no log.

   ── OS TRÊS AVISOS QUE ESTE ARQUIVO ATENDE ─────────────────────────────────
     payment                          o Pix avulso caiu
     subscription_preapproval         o cartão foi autorizado — ou cancelado
     subscription_authorized_payment  a cobrança mensal do cartão

   Os dois últimos são a assinatura recorrente, e a regra de cima vale igual
   para eles: o corpo do aviso diz só um id, e tudo o mais é RELIDO da API do
   Mercado Pago com o nosso token. O `external_reference` que decide de qual
   salão é a assinatura vem de lá, nunca do POST — e ele só pode estar lá
   porque fomos nós que o gravamos ao criar a pré-aprovação.
   =========================================================================== */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MP_TOKEN     = Deno.env.get('MP_ACCESS_TOKEN')!;
// Segredo do webhook, copiado do painel do Mercado Pago ao cadastrar a URL.
const MP_SEGREDO   = Deno.env.get('MP_WEBHOOK_SECRET') ?? '';

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

/* Lê a pré-aprovação NA API do Mercado Pago. É a fonte: o corpo do aviso diz
   só um id, e é daqui que sai o `external_reference` que decide de qual salão
   é a assinatura. Devolve null quando não deu para ler — e aí quem chama
   responde 500, para o Mercado Pago tentar de novo. */
async function lerPreapproval(id: string) {
  const r = await fetch(`https://api.mercadopago.com/preapproval/${id}`, {
    headers: { Authorization: `Bearer ${MP_TOKEN}` } });
  if(!r.ok){
    console.error('webhook-mp: não li a pré-aprovação', id, r.status);
    return null;
  }
  return await r.json();
}

/* Liga o cartão do salão que a pré-aprovação aponta. Devolve se ligou. */
async function ligarDaPreapproval(pre: Record<string, unknown>) {
  const salao = String(pre?.external_reference ?? '');
  /* Sem uuid não há salão para ligar. Acontece se a pré-aprovação foi criada
     fora daqui, na mão, dentro do painel do Mercado Pago. */
  if(!/^[0-9a-f-]{36}$/i.test(salao)){
    console.error('webhook-mp: pré-aprovação sem salão', String(pre?.id ?? ''));
    return false;
  }
  const feito = await rpc('ligar_cartao',
    { p_salao: salao, p_preapproval: String(pre.id) });
  console.log('webhook-mp preapproval', JSON.stringify(feito));
  return feito?.ok === true;
}

/* ── A CONFERÊNCIA DA ASSINATURA ────────────────────────────────────────────
   Mora em `assinatura.js`, ao lado, e não aqui dentro — porque precisa rodar
   também no Node, no tests/webhook-assinatura.test.js. É a função que separa
   "o Mercado Pago avisou que pagaram" de "alguém escreveu que pagaram", num
   endereço que é público por obrigação: deixá-la presa dentro de um arquivo
   que só o Deno executa seria a parte mais crítica do sistema sendo a única
   sem teste. */
import { assinaturaConfere } from './assinatura.js';

Deno.serve(async (req) => {
  if(req.method !== 'POST') return new Response('ok', { status: 200 });

  try{
    const url = new URL(req.url);
    const corpo = await req.json().catch(() => ({}));

    // O id do pagamento pode vir na querystring ou no corpo, dependendo do
    // tipo de aviso. O da querystring é o que entra no manifesto assinado.
    const dataId = String(
      url.searchParams.get('data.id') ?? corpo?.data?.id ?? '');
    /* `topic` e não só `type`: os avisos de assinatura chegam no formato
       antigo em algumas configurações, e lá o campo tem o outro nome. Ler só
       `type` deixava `subscription_authorized_payment` cair no `if` de baixo
       como se fosse aviso alheio — e a renovação mensal era descartada com um
       200 silencioso, que é a forma mais difícil de defeito de enxergar. */
    const tipo = String(url.searchParams.get('type')
                     ?? url.searchParams.get('topic')
                     ?? corpo?.type ?? corpo?.topic ?? '');

    if(!dataId) return new Response('sem id', { status: 200 });

    const confere = await assinaturaConfere({
      segredo: MP_SEGREDO,
      xSignature: req.headers.get('x-signature'),
      xRequestId: req.headers.get('x-request-id'),
      dataId,
    });
    if(!confere){
      if(!MP_SEGREDO) console.error('MP_WEBHOOK_SECRET não configurado.');
      console.error('webhook-mp: assinatura inválida', { tipo, dataId });
      return new Response('assinatura inválida', { status: 401 });
    }

    /* ── O CARTÃO FOI AUTORIZADO, OU DEIXOU DE SER ───────────────────────────
       Este é o único lugar do sistema que liga o cartão de um salão. A borda
       `assinar-cartao` não liga: chegar lá é ter clicado num botão, não é ter
       autorizado nada. Aqui o dado vem da API do Mercado Pago. */
    if(tipo === 'subscription_preapproval'){
      const pre = await lerPreapproval(dataId);
      if(!pre) return new Response('erro ao ler', { status: 500 });
      const situacao = String(pre?.status ?? '');

      if(situacao === 'authorized'){
        await ligarDaPreapproval(pre);
        return new Response('ok', { status: 200 });
      }

      /* Cancelada ou pausada: pode ter sido o dono, dentro da conta dele, ou o
         próprio Mercado Pago depois de tentativas demais num cartão que não
         passa. Nos dois casos o débito parou.

         Desligar do nosso lado é o que devolve o salão para a lista de
         renovação por Pix. Sem isto ele continuaria marcado como "renova
         sozinho" e venceria em silêncio, sem cobrança e sem lembrete. */
      if(situacao === 'cancelled' || situacao === 'paused'){
        const feito = await rpc('desligar_cartao', { p_preapproval: dataId });
        console.log('webhook-mp preapproval', situacao, JSON.stringify(feito));
      }
      return new Response('ok', { status: 200 });
    }

    /* ── A COBRANÇA MENSAL DO CARTÃO ─────────────────────────────────────────
       ⚠ É este aviso, e não o `payment`, que renova a assinatura no cartão.

       O pagamento recorrente também chega como `payment`, mas lá ele não tem
       cobrança nossa esperando — ninguém clica em "assinar" no mês 2 — e o
       `registrar_pagamento()` responde `cobranca_desconhecida`. É aqui que a
       linha do mês nasce, porque só aqui existe o `preapproval_id` que diz de
       qual salão ela é.

       Os dois avisos chegam em ordem imprevisível, e tanto faz: o `mp_id` é
       único, e quem chegar depois cai no `ja_registrada`. */
    if(tipo === 'subscription_authorized_payment'){
      const r = await fetch(
        `https://api.mercadopago.com/authorized_payments/${dataId}`, {
          headers: { Authorization: `Bearer ${MP_TOKEN}` } });
      if(!r.ok){
        console.error('webhook-mp: não li a cobrança recorrente', dataId, r.status);
        return new Response('erro ao ler', { status: 500 });
      }
      const ap = await r.json();
      const pagamento = ap?.payment ?? {};

      /* Sem pagamento ainda é agendamento, não cobrança: o Mercado Pago avisa
         a tentativa antes de fazê-la. Nada a registrar. */
      if(!pagamento?.id){
        console.log('webhook-mp recorrente sem pagamento', dataId);
        return new Response('ok', { status: 200 });
      }

      const pedidoRpc = {
        p_preapproval: String(ap.preapproval_id ?? ''),
        p_mp_id: String(pagamento.id),
        p_valor: Number(ap.transaction_amount ?? pagamento.transaction_amount),
        p_status: String(pagamento.status ?? ''),
      };
      let feito = await rpc('registrar_recorrencia', pedidoRpc);

      /* ⚠ A ORDEM DOS DOIS AVISOS NÃO É GARANTIDA, E O MÊS 1 DEPENDE DELA.

         O Mercado Pago cobra assim que a pré-aprovação é autorizada, e manda
         os dois avisos quase juntos. Se a COBRANÇA chegar primeiro, o banco
         ainda não sabe de qual salão é a pré-aprovação, e responde
         `preapproval_desconhecida` — o primeiro mês, que já foi debitado, se
         perderia. O dono pagou e o painel diria que o plano não está ativo.

         Esperar o reenvio do Mercado Pago resolveria na maioria das vezes, e
         é justamente a parte que não dá para prometer. Aqui a função vai
         buscar a pré-aprovação na API, liga o cartão e registra de novo — uma
         requisição a mais, num caminho que só roda quando a ordem inverteu. */
      if(feito?.motivo === 'preapproval_desconhecida' && ap.preapproval_id){
        const pre = await lerPreapproval(String(ap.preapproval_id));
        if(pre && String(pre.status ?? '') === 'authorized'
           && await ligarDaPreapproval(pre)){
          feito = await rpc('registrar_recorrencia', pedidoRpc);
        }
      }

      console.log('webhook-mp recorrente', dataId, JSON.stringify(feito));
      return new Response('ok', { status: 200 });
    }

    // Só interessa aviso de pagamento. `merchant_order` e o resto chegam
    // junto e não movem assinatura nenhuma.
    if(tipo && tipo !== 'payment') return new Response('ok', { status: 200 });

    /* ── A FONTE ────────────────────────────────────────────────────────────
       Aqui o corpo do aviso deixa de importar. Status e valor vêm da API. */
    const r = await fetch(`https://api.mercadopago.com/v1/payments/${dataId}`, {
      headers: { Authorization: `Bearer ${MP_TOKEN}` } });
    if(!r.ok){
      console.error('webhook-mp: não consegui ler o pagamento', dataId, r.status);
      // 500 para o Mercado Pago tentar de novo: pode ter sido rede.
      return new Response('erro ao ler', { status: 500 });
    }
    const pg = await r.json();

    const resultado = await rpc('registrar_pagamento', {
      p_mp_id: String(pg.id),
      p_valor: Number(pg.transaction_amount),
      p_status: String(pg.status ?? ''),
    });

    // O log guarda o resultado, nunca o pagamento inteiro: ele traz nome,
    // e-mail e documento de quem pagou.
    console.log('webhook-mp', dataId, JSON.stringify(resultado));
    return new Response('ok', { status: 200 });

  }catch(e){
    console.error('webhook-mp falhou:', String(e).slice(0, 300));
    return new Response('erro', { status: 500 });
  }
});
