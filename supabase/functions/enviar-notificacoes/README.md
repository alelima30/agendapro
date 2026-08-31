# Ligar as mensagens da agenda

Confirmação, lembrete e resumo do dia já são **preparados** pelo banco assim
que você cola o `98_modulos.sql`. Eles ficam na fila, com o horário certo, em
estado `pendente` — e é isso que a aba **Meu salão → Notificações** mostra.

Para que passem a **sair**, faltam três coisas. Nenhuma delas é código, e a
primeira não depende de você.

---

## 1. A conta na Meta

Sem a verificação do WhatsApp Business aprovada, nada sai. Não há atalho, e
não há como fingir: este worker devolve `503` e não toca na fila quando o
token não existe, de propósito.

Enquanto isso, tudo continua sendo preparado. No dia em que a conta for
aprovada, as mensagens começam a andar sem mexer em nada — as que já
venceram há mais de seis horas são aposentadas sozinhas, para ninguém receber
"seu horário é daqui a duas horas" três dias depois.

---

## 2. Os segredos da função

No painel do Supabase, em **Edge Functions → Secrets**:

```
WHATSAPP_TOKEN        o token permanente do app da Meta
WHATSAPP_PHONE_ID     o id do número (Phone Number ID), não o telefone
WHATSAPP_API_VERSAO   opcional; o padrão é v21.0
CRON_SEGREDO          uma frase qualquer, sua, para o cron provar quem é
```

> ⚠ **Nenhum destes valores pode entrar no `config.js` nem em qualquer arquivo
> do painel.** O painel é HTML servido pelo GitHub Pages: tudo o que chega
> nele é público por construção. O `SUPABASE_SERVICE_ROLE_KEY` já é injetado
> pela plataforma e passa por cima de todo o RLS — se ele vazar, acabou o
> isolamento entre salões.

Publicar:

```bash
supabase functions deploy enviar-notificacoes
```

---

## 3. O agendador

O worker não tem laço infinito: alguém precisa acordá-lo de minuto em minuto.
É o `pg_cron`, que vem com o Supabase e precisa ser **ligado uma vez**:

**Database → Extensions → `pg_cron`** (e `pg_net`, para a chamada HTTP).

Depois, no SQL Editor, uma vez:

```sql
select cron.schedule(
  'agendapro-notificacoes',
  '* * * * *',
  $$
  select net.http_post(
    url     := 'https://SEU-PROJETO.supabase.co/functions/v1/enviar-notificacoes',
    headers := jsonb_build_object(
                 'Content-Type',   'application/json',
                 'x-cron-segredo', 'A FRASE QUE VOCÊ PÔS EM CRON_SEGREDO'),
    body    := '{}'::jsonb);
  $$);
```

Trocar `SEU-PROJETO` e a frase do segredo. Para conferir depois:

```sql
select jobname, schedule, active from cron.job;
```

Para desligar:

```sql
select cron.unschedule('agendapro-notificacoes');
```

---

## O que acontece a cada volta

1. `gerar_resumos()` põe o resumo do dia na fila dos salões cuja hora chegou.
   Idempotente por dia: rodar sessenta vezes numa hora cria uma linha só.
2. Pega uma mensagem por vez com `notificacao_proxima()`, que marca
   `enviando` na mesma transação em que lê — dois workers ao mesmo tempo nunca
   mandam a mesma duas vezes.
3. Manda pela Graph API.
4. `notificacao_resultado()` carimba. **Só o sucesso escreve `enviado_em`**, e
   é dele que sai o consumo do mês: falha não custa cota.
5. Espera quase um segundo e repete, até 40 segundos por chamada.

Falha temporária volta para `pendente` com espera crescente, até três
tentativas. Depois disso a mensagem é dada por perdida — retentar para sempre
é como uma fila entope.

---

## O que ainda não existe

**`entregue` e `lido`.** Os dois estados só chegam pelo webhook de status da
Meta. O `wam_id` que ela devolve já está sendo guardado em cada linha, e a
função `notificacao_status()` já sabe casar — falta só o webhook, que entra
junto com a conta aprovada.

Enquanto ele não existir, esses dois estados **não aparecem no painel**. Não
são estimados.
