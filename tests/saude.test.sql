-- ===========================================================================
-- AgendaPro — o check-up do sistema (40_saude.sql)
--
-- "Preciso criar algo que fique monitorando o AgendaPro." O banco dos testes
-- não tem pg_cron nem pg_net: o despertador e as respostas da função de envio
-- são montados aqui, com as mesmas colunas, para cada caso ser provado.
--
--   1. sem pg_cron: problema, dizendo o que rodar;
--   2. despertador rodando: ok; parado ou falhando: problema;
--   3. a função de envio: 401 é o segredo, 404 não publicada, 503 sem token;
--   4. a fila: mensagem atrasada é problema; parada pela franquia, não;
--   5. as falhas: token vencido é problema, cliente sem WhatsApp é atenção;
--   6. o negócio: franquia acabando e assinatura vencendo, sem derrubar o nível;
--   7. a porta pública não leva nome de salão; as portas são as certas.
-- ===========================================================================
\set ON_ERROR_STOP on

create or replace function item(p_chave text) returns jsonb language sql as $f$
  select i from jsonb_array_elements(public.saude_verificar()->'itens') i
   where i->>'chave' = p_chave
$f$;
create or replace function negocio(p_chave text) returns jsonb language sql as $f$
  select i from jsonb_array_elements(public.saude_verificar()->'negocio') i
   where i->>'chave' = p_chave
$f$;

\echo ''
\echo '1. Banco novo, sem nada'
select t_texto('o banco responde', item('banco')->>'nivel', 'ok');
select t_texto('sem pg_cron, o despertador é problema', item('despertador')->>'nivel', 'problema');
select t_verdade('e diz o que rodar', item('despertador')->>'acao' like '%LIGAR-WHATSAPP.sql%');
select t_texto('fila vazia: ok', item('fila')->>'nivel', 'ok');
select t_texto('sem falha: ok', item('falhas')->>'nivel', 'ok');
select t_texto('o nível geral é o pior deles', public.saude_verificar()->>'nivel', 'problema');

\echo ''
\echo '2. O despertador'
create schema if not exists cron;
create table cron.job (jobid bigserial primary key, jobname text, schedule text, active boolean);
create table cron.job_run_details (runid bigserial primary key, jobid bigint, start_time timestamptz,
                                   status text, return_message text);
select t_verdade('sem o agendapro-notificacoes: problema',
  item('despertador')->>'nivel' = 'problema' and item('despertador')->>'detalhe' like '%não existe%');
insert into cron.job (jobname, schedule, active) values ('agendapro-notificacoes', '15 seconds', false);
select t_verdade('pausado: problema',
  item('despertador')->>'nivel' = 'problema' and item('despertador')->>'detalhe' like '%pausado%');
update cron.job set active = true;
select t_verdade('ligado e nunca rodou: problema',
  item('despertador')->>'nivel' = 'problema' and item('despertador')->>'detalhe' like '%nunca rodou%');
insert into cron.job_run_details (jobid, start_time, status, return_message)
  select 1, now() - make_interval(secs => 15 * g), 'succeeded', '1 row' from generate_series(60, 1, -1) g;
select t_verdade('rodando a cada 15 segundos: ok',
  item('despertador')->>'nivel' = 'ok' and item('despertador')->>'detalhe' like '%15 seconds%');
insert into cron.job_run_details (jobid, start_time, status, return_message)
  values (1, now(), 'failed', 'schema "net" does not exist');
select t_verdade('falhou agora: problema, com a mensagem do pg_cron',
  item('despertador')->>'nivel' = 'problema' and item('despertador')->>'detalhe' like '%net%');
delete from cron.job_run_details where status = 'failed';
update cron.job_run_details set start_time = start_time - interval '1 hour';
select t_verdade('parado há uma hora: problema, dizendo desde quando',
  item('despertador')->>'nivel' = 'problema' and item('despertador')->>'detalhe' like '%não roda desde%');
update cron.job_run_details set start_time = start_time + interval '1 hour';

\echo ''
\echo '3. A função de envio'
create schema if not exists net;
create table net._http_response (id bigserial primary key, status_code int, content_type text,
  headers jsonb, content text, timed_out boolean, error_msg text, created timestamptz default now());
select t_texto('sem resposta ainda: atenção', item('funcao_envio')->>'nivel', 'atencao');
insert into net._http_response (status_code, content, timed_out) values (200, '{"enviadas":0}', false);
select t_texto('respondeu 200: ok', item('funcao_envio')->>'nivel', 'ok');
insert into net._http_response (status_code, content, timed_out) values (401, '{"erro":"x"}', false);
select t_verdade('401: problema, apontando o CRON_SEGREDO',
  item('funcao_envio')->>'nivel' = 'problema' and item('funcao_envio')->>'detalhe' like '%CRON_SEGREDO%');
insert into net._http_response (status_code, content, timed_out) values (404, '', false);
select t_verdade('404: a função não está publicada',
  item('funcao_envio')->>'detalhe' like '%não está publicada%' and item('funcao_envio')->>'acao' like '%Run workflow%');
insert into net._http_response (status_code, content, timed_out) values (503, '', false);
select t_verdade('503: faltam os segredos do WhatsApp',
  item('funcao_envio')->>'detalhe' like '%WHATSAPP_TOKEN%');
insert into net._http_response (status_code, content, timed_out) values (null, null, true);
select t_verdade('não respondeu a tempo: problema',
  item('funcao_envio')->>'nivel' = 'problema' and item('funcao_envio')->>'detalhe' like '%não respondeu%');
insert into net._http_response (status_code, content, timed_out) values (200, '{"enviadas":1}', false);
select t_texto('voltou a responder: ok', item('funcao_envio')->>'nivel', 'ok');
select t_texto('com tudo certo, o nível geral é ok', public.saude_verificar()->>'nivel', 'ok');

\echo ''
\echo '4. A fila'
insert into public.saloes (id, slug, nome, tipo, status) values
  ('5a100000-0000-0000-0000-000000000001', 'saude-um',   'Studio Saúde',  'salao', 'ativo'),
  ('5a100000-0000-0000-0000-000000000002', 'saude-dois', 'Barbearia Fim', 'salao', 'ativo');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('5a100000-0000-0000-0000-000000000001', 'time',       'ativa', current_date + 20),
  ('5a100000-0000-0000-0000-000000000002', 'individual', 'ativa', current_date + 2);
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status)
values ('5a100000-0000-0000-0000-000000000001', 'resumo', '11999', now() - interval '20 minutes',
        'x', 'saude:atrasada', 'pendente');
select t_verdade('mensagem que devia ter saído há 20 minutos: problema',
  item('fila')->>'nivel' = 'problema' and item('fila')->>'detalhe' like '%1 mensagem(ns) atrasada(s)%');
select t_verdade('e a porta pública aponta a fila',
  public.saude_publica()->'problemas' ? 'fila');
update public.notificacoes set quando = now() + interval '1 hour' where chave = 'saude:atrasada';
select t_verdade('marcada para daqui a uma hora: ok, contada como "para mais tarde"',
  item('fila')->>'nivel' = 'ok' and item('fila')->>'detalhe' like '%1 na fila%');

-- A Barbearia Fim no Essencial (500): 500 enviadas, a franquia acabou.
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
  select '5a100000-0000-0000-0000-000000000002', 'lembrete', '11999', now(), 'x',
         'saude:gasto:' || g, 'enviado', now()
    from generate_series(1, 500) g;
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status)
values ('5a100000-0000-0000-0000-000000000002', 'confirmacao', '11999', now() - interval '20 minutes',
        'x', 'saude:parada', 'pendente');
select t_texto('parada pela franquia do salão não é atraso do sistema', item('fila')->>'nivel', 'ok');
select t_verdade('mas aparece no negócio',
  negocio('franquia_parada')->>'detalhe' like '1 mensagem(ns) esperando%');
delete from public.notificacoes where chave = 'saude:parada';

\echo ''
\echo '5. As falhas'
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, erro_codigo)
values ('5a100000-0000-0000-0000-000000000001', 'confirmacao', '11988', now() - interval '2 hours',
        'x', 'saude:sem-zap', 'falhou', '131026');
select t_verdade('cliente sem WhatsApp: atenção, explicado',
  item('falhas')->>'nivel' = 'atencao' and item('falhas')->>'detalhe' like '%não tem WhatsApp%');
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, erro_codigo, proxima_em)
values ('5a100000-0000-0000-0000-000000000001', 'lembrete', '11977', now() - interval '3 minutes',
        'x', 'saude:token', 'pendente', '190', now() + interval '5 minutes');
select t_verdade('token vencido: problema, dizendo o segredo a trocar',
  item('falhas')->>'nivel' = 'problema' and item('falhas')->>'detalhe' like '%WHATSAPP_TOKEN%');
select t_verdade('a tentando de novo não conta como atrasada', item('fila')->>'nivel' = 'ok');
select t_verdade('e a porta pública aponta as falhas', public.saude_publica()->'problemas' ? 'falhas');
delete from public.notificacoes where chave in ('saude:token', 'saude:sem-zap');
select t_texto('resolvido, volta a ok', item('falhas')->>'nivel', 'ok');

\echo ''
\echo '6. O negócio'
select t_verdade('a franquia acabando lista o salão',
  negocio('franquia')->>'detalhe' like '%Barbearia Fim: 500 de 500%');
select t_verdade('a assinatura vencendo também',
  negocio('vencimentos')->>'detalhe' like '%Barbearia Fim vence em%');
select t_texto('e o negócio não derruba o nível do sistema', public.saude_verificar()->>'nivel', 'ok');

\echo ''
\echo '7. As portas'
select t_falso('a porta pública não leva nome de salão',
  public.saude_publica()::text like '%Barbearia%' or public.saude_publica()::text like '%Studio%');
select t_verdade('só nível, horário e chaves',
  (select array_agg(k order by k) from jsonb_object_keys(public.saude_publica()) k)
    = array['atencao', 'nivel', 'problemas', 'verificadoEm']);
select t_falso('anon não executa nenhuma',
  has_function_privilege('anon', 'public.saude_verificar()', 'execute')
  or has_function_privilege('anon', 'public.saude_publica()', 'execute')
  or has_function_privilege('anon', 'public.saude_plataforma()', 'execute'));
select t_falso('logado não executa a conta nem a porta pública',
  has_function_privilege('authenticated', 'public.saude_verificar()', 'execute')
  or has_function_privilege('authenticated', 'public.saude_publica()', 'execute'));
select t_verdade('a função de borda (service_role) executa a porta pública',
  has_function_privilege('service_role', 'public.saude_publica()', 'execute'));

insert into auth.users (id) values ('5a900000-0000-0000-0000-000000000001'),
                                   ('5a900000-0000-0000-0000-000000000002') on conflict do nothing;
insert into public.perfis (id, nome, email, super_admin) values
  ('5a900000-0000-0000-0000-000000000001', 'Dona Comum', 'comum@saude.com', false),
  ('5a900000-0000-0000-0000-000000000002', 'Plataforma', 'plataforma@saude.com', true)
  on conflict (id) do update set super_admin = excluded.super_admin;
select set_config('request.jwt.claim.sub', '5a900000-0000-0000-0000-000000000001', false);
select t_verdade('a dona de salão comum é recusada no admin',
  recusado('select public.saude_plataforma()'));
select set_config('request.jwt.claim.sub', '5a900000-0000-0000-0000-000000000002', false);
select t_verdade('a conta da plataforma vê tudo, com o negócio',
  public.saude_plataforma() ? 'negocio' and public.saude_plataforma()->>'nivel' = 'ok');
select set_config('request.jwt.claim.sub', '', false);
