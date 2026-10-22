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
-- O que isto faz: a cada 15 segundos, o banco chama a função
-- `enviar-notificacoes`, que manda o que está na fila (confirmação, lembrete,
-- resumo do dia, aviso à equipe). Sem fila, a chamada volta na hora e não
-- custa nada na Meta. Colar duas vezes não duplica: o agendamento antigo com
-- o mesmo nome é trocado.
--
-- Era de minuto em minuto, e a confirmação esperava até 60 segundos na fila
-- antes de sair — somado ao tempo da Meta e do celular, a cliente via a
-- mensagem minutos depois de marcar. São 5.760 chamadas por dia, dentro da
-- franquia de funções do Supabase.
--
-- JÁ TEM O DESPERTADOR DE MINUTO EM MINUTO? Não precisa colar tudo de novo
-- (nem achar a frase do segredo). Basta esta linha:
--
--   select cron.alter_job((select jobid from cron.job
--                           where jobname = 'agendapro-notificacoes'),
--                         schedule := '15 seconds');
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
  '15 seconds',
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
