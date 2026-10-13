-- ===========================================================================
-- AgendaPro — ligar o "despertador" das mensagens do WhatsApp
--
-- Cole no Supabase → SQL Editor → Run, DEPOIS de:
--   1. guardar os segredos em Edge Functions → Secrets (WHATSAPP_TOKEN,
--      WHATSAPP_PHONE_ID, META_APP_SECRET, WHATSAPP_VERIFY_TOKEN, CRON_SEGREDO);
--   2. publicar as funções (GitHub → Actions → "Publicar as funções do
--      WhatsApp" → Run workflow).
--
-- ⚠ TROQUE UMA COISA SÓ: a frase 'TROQUE-PELA-FRASE-DO-CRON_SEGREDO' lá
-- embaixo, pela MESMA frase que você guardou no segredo CRON_SEGREDO. As
-- duas têm de ser iguais, letra por letra — é assim que a função sabe que
-- quem a acordou foi o seu banco, e não um estranho.
--
-- O que isto faz: de minuto em minuto, o banco chama a função
-- `enviar-notificacoes`, que manda o que está na fila (confirmação, lembrete,
-- resumo do dia, aviso à equipe). Sem fila, a chamada volta na hora e não
-- custa nada na Meta. Colar duas vezes não duplica: o agendamento antigo com
-- o mesmo nome é trocado.
-- ===========================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  perform cron.unschedule('agendapro-notificacoes')
    where exists (select 1 from cron.job where jobname = 'agendapro-notificacoes');
end $$;

select cron.schedule(
  'agendapro-notificacoes',
  '* * * * *',
  $cron$
  select net.http_post(
    url     := 'https://ialjrnighxntuirzmppt.supabase.co/functions/v1/enviar-notificacoes',
    headers := jsonb_build_object(
                 'Content-Type',   'application/json',
                 'x-cron-segredo', 'TROQUE-PELA-FRASE-DO-CRON_SEGREDO'),
    body    := '{}'::jsonb);
  $cron$);

-- Conferir: deve aparecer uma linha, ativa.
select jobname, schedule, active from cron.job where jobname = 'agendapro-notificacoes';
