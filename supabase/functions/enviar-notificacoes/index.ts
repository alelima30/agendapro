/* ===========================================================================
   AgendaPro — o worker das mensagens da agenda
   Supabase Edge Function (Deno). Roda NO SERVIDOR, nunca no navegador.

   ── O QUE ELE MANDA, E O QUE NÃO ──────────────────────────────────────────
   Confirmação, lembrete, resumo do dia e o aviso para quem vai atender. Só
   isso. Campanha tem worker próprio (`enviar-campanha`), e a separação não é
   arrumação: são cadências, cotas e regras de consentimento diferentes.

   ── POR QUE ESTE ARQUIVO NÃO PODE VIRAR JAVASCRIPT DO PAINEL ──────────────
   Ele é um dos dois lugares do projeto que enxergam duas credenciais:

     WHATSAPP_TOKEN            manda mensagem em nome do salão
     SUPABASE_SERVICE_ROLE_KEY passa por cima de TODO o RLS

   Qualquer uma delas no painel é o fim do isolamento entre salões — o painel
   é HTML servido do GitHub Pages, e tudo o que chega nele é público por
   construção. As duas vivem em variáveis de ambiente da função.

   ── A REGRA QUE MANDA ─────────────────────────────────────────────────────
   NADA É MARCADO COMO ENVIADO SEM TER SIDO ENVIADO.

   Este arquivo é o único caminho do sistema que escreve 'enviado', e ele só
   escreve depois de a Graph API responder OK. Sem credencial configurada ele
   não roda: devolve 503 e a fila fica intacta, com tudo pendente — que é a
   verdade e é o que o painel mostra.

   ── QUEM CHAMA ────────────────────────────────────────────────────────────
   O `pg_cron`, de minuto em minuto, pela SQL do README ao lado. Não há laço
   infinito aqui: função de borda que roda para sempre é função que morre no
   meio e leva a fila junto.

   Cada chamada faz duas coisas: põe os resumos do dia na fila (para os
   salões cuja hora chegou) e despacha o que está vencendo.
   =========================================================================== */

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const WA_TOKEN     = Deno.env.get('WHATSAPP_TOKEN');
const WA_PHONE_ID  = Deno.env.get('WHATSAPP_PHONE_ID');
const WA_VERSAO    = Deno.env.get('WHATSAPP_API_VERSAO') ?? 'v21.0';
// O idioma dos modelos cadastrados na Meta. Errar aqui devolve 132001
// ("template does not exist"), que não diz que o problema é o idioma.
const WA_IDIOMA    = Deno.env.get('WHATSAPP_IDIOMA') ?? 'pt_BR';
const SEGREDO      = Deno.env.get('CRON_SEGREDO');

// Teto de tempo por chamada, abaixo do limite da plataforma: parar sozinho
// antes de ser derrubado deixa a fila num estado que a próxima volta entende.
const TETO_MS = 40_000;
const ENTRE_MS = 900;

type Alvo = { id: string; salao_id: string; destino: string;
              corpo: string; tipo: string;
              modelo: string | null; variaveis: string[] | null };

async function rpc(nome: string, corpo: Record<string, unknown>) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(corpo),
  });
  if (!r.ok) throw new Error(`${nome}: ${r.status} ${await r.text()}`);
  const t = await r.text();
  return t ? JSON.parse(t) : null;
}

/* O número em formato internacional. O banco guarda só dígitos; a Meta quer
   com código de país. Número brasileiro sem o 55 é o erro mais comum aqui, e
   ele falha calado do outro lado — a mensagem some sem devolver erro. */
function paraMeta(digitos: string): string {
  const so = digitos.replace(/\D/g, '');
  if (so.length >= 12 && so.startsWith('55')) return so;
  if (so.length === 10 || so.length === 11) return '55' + so;
  return so;
}

/* ⚠ POR QUE MODELO, E NÃO TEXTO LIVRE.

   O WhatsApp só aceita texto livre dentro de 24 horas contadas da última
   mensagem que a PESSOA mandou para o número. Nossas quatro mensagens são
   todas fora dessa janela — a cliente marcou pelo link do site e nunca
   escreveu para o salão. Texto livre aqui volta com o erro 131047, sempre.

   Então o que viaja é o nome do modelo aprovado na Meta e as variáveis na
   ordem. O `corpo`, com emoji e quebra de linha, continua sendo gravado no
   banco: é o que o histórico do painel mostra, e é o registro do que foi dito.

   O texto de cada modelo está em MODELOS.md, ao lado. A ordem das variáveis
   ali e a de `variaveis_agendamento()` no banco são um contrato — modelo
   aprovado praticamente não se edita. */
async function mandar(alvo: Alvo) {
  const destino = alvo.destino;

  /* Sem modelo é linha antiga, criada antes desta mudança. Vai como texto
     livre: se estiver fora da janela a Meta recusa com 131047, o erro fica
     gravado na linha, e isso é melhor do que inventar um modelo que não
     existe — que falha igual, sem dizer por quê. */
  const pedido = alvo.modelo
    ? {
        messaging_product: 'whatsapp',
        to: paraMeta(destino),
        type: 'template',
        template: {
          name: alvo.modelo,
          language: { code: WA_IDIOMA },
          components: (alvo.variaveis ?? []).length
            ? [{ type: 'body',
                 parameters: (alvo.variaveis ?? []).map((v) => ({
                   type: 'text', text: String(v) })) }]
            : [],
        },
      }
    : {
        messaging_product: 'whatsapp',
        to: paraMeta(destino),
        type: 'text',
        text: { preview_url: false, body: alvo.corpo },
      };

  const r = await fetch(
    `https://graph.facebook.com/${WA_VERSAO}/${WA_PHONE_ID}/messages`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${WA_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(pedido),
    });

  const resposta = await r.json().catch(() => ({}));
  if (r.ok) {
    return { ok: true as const, wamId: resposta?.messages?.[0]?.id ?? null };
  }
  const erro = resposta?.error ?? {};
  return {
    ok: false as const,
    codigo: String(erro.code ?? r.status),
    msg: String(erro.message ?? 'falha ao enviar').slice(0, 300),
  };
}

Deno.serve(async (req) => {
  // Um segredo compartilhado com o `pg_cron`. Sem isto, a URL da função é
  // um botão de disparo aberto na internet.
  if (SEGREDO) {
    const veio = req.headers.get('x-cron-segredo');
    if (veio !== SEGREDO) {
      return new Response(JSON.stringify({ erro: 'não autorizado' }), {
        status: 401, headers: { 'Content-Type': 'application/json; charset=utf-8' } });
    }
  }

  /* ⚠ SEM CREDENCIAL, NÃO SE INVENTA ENVIO.

     A tentação aqui seria "marcar como enviado para o painel ficar bonito".
     O resultado disso é o salão parar de ligar para a cliente confiando num
     aviso que ninguém recebeu. Devolve 503, a fila fica intacta, e o painel
     continua dizendo pendente — que é a verdade. */
  if (!WA_TOKEN || !WA_PHONE_ID) {
    /* No LOG, e não só na resposta. Quem vai olhar aqui é alguém tentando
       entender por que a fila não anda — e a resposta HTTP some: o `pg_cron`
       chama, recebe e descarta o corpo. Sem esta linha, o log da função mostra
       uma parede de 503 sem dizer o que falta. */
    console.error('enviar-notificacoes: faltam WHATSAPP_TOKEN e/ou '
                + 'WHATSAPP_PHONE_ID. A fila fica intacta, com tudo pendente.');
    return new Response(JSON.stringify({
      erro: 'WhatsApp não configurado',
      detalhe: 'Faltam WHATSAPP_TOKEN e/ou WHATSAPP_PHONE_ID. '
             + 'A fila continua intacta, com tudo pendente.',
    }), { status: 503, headers: { 'Content-Type': 'application/json; charset=utf-8' } });
  }

  const ate = Date.now() + TETO_MS;
  let enviadas = 0, falhas = 0, resumos = 0;

  try {
    // Primeiro os resumos do dia entram na fila. Idempotente por dia: chamar
    // isto de minuto em minuto cria uma linha só.
    resumos = (await rpc('gerar_resumos', {})) ?? 0;

    while (Date.now() < ate) {
      const lote = await rpc('notificacao_proxima', { p_lote: 1 }) as Alvo[];
      if (!lote || lote.length === 0) break;
      const alvo = lote[0];

      let r;
      try {
        r = await mandar(alvo);
      } catch (e) {
        r = { ok: false as const, codigo: 'rede',
              msg: String((e as Error).message).slice(0, 300) };
      }

      await rpc('notificacao_resultado', {
        p_id: alvo.id,
        p_ok: r.ok,
        p_wam_id: r.ok ? r.wamId : null,
        p_codigo: r.ok ? null : r.codigo,
        p_msg: r.ok ? null : r.msg,
      });

      if (r.ok) { enviadas++; }
      else {
        falhas++;
        /* O código do erro, nunca o destino nem o corpo: o log de função é
           lido por gente de suporte, e o corpo tem nome e horário de cliente.
           O motivo por extenso fica na linha da fila, que o painel mostra. */
        console.error('enviar-notificacoes: falhou', alvo.tipo, r.codigo);
      }

      // Cadência. Sem ela, um lote grande de lembretes sai como rajada — e
      // rajada é o padrão que a Meta lê como robô.
      await new Promise((s) => setTimeout(s, ENTRE_MS));
    }

    /* A volta que não fez nada não vira linha: são 1.440 chamadas por dia, e
       a esmagadora maioria não tem o que despachar. Log que enche sozinho é
       log que ninguém abre. */
    if (resumos || enviadas || falhas) {
      console.log('enviar-notificacoes',
        JSON.stringify({ resumos, enviadas, falhas }));
    }
    return new Response(JSON.stringify({ resumos, enviadas, falhas }), {
      headers: { 'Content-Type': 'application/json; charset=utf-8' } });
  } catch (e) {
    console.error('enviar-notificacoes falhou:',
      String((e as Error).message).slice(0, 300));
    return new Response(JSON.stringify({ erro: String((e as Error).message) }), {
      status: 500, headers: { 'Content-Type': 'application/json; charset=utf-8' } });
  }
});
