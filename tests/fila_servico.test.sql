-- ===========================================================================
-- AgendaPro — a fila espera o serviço chegar (22_cotas.sql)
--
-- O painel grava o agendamento e os serviços dele em duas chamadas, uma logo
-- depois da outra. Com a fila passando a cada 15 segundos ("a mensagem está
-- demorando 2 a 3 minutos"), tomar a confirmação entre as duas deixou de ser
-- raro — e ela sairia com "Serviço: atendimento" e o valor sem os itens.
--
--   1. sem serviço ainda, a confirmação recém-criada NÃO é tomada;
--   2. o serviço chegou: é tomada, e o texto já diz o serviço;
--   3. agendamento que nunca terá serviço sai depois de um minuto;
--   4. mensagem sem agendamento (o resumo do dia) não espera nada.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo, status) values
  ('f5100000-0000-0000-0000-000000000001', 'studio-fila', 'Studio Fila', 'salao', 'ativo');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('f5100000-0000-0000-0000-000000000001', 'time', 'ativa', current_date + 30);
insert into public.profissionais (id, salao_id, nome, ativo) values
  ('f5200000-0000-0000-0000-000000000001', 'f5100000-0000-0000-0000-000000000001', 'Bia Souza', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select 'f5200000-0000-0000-0000-000000000001', d, '07:00', '22:00' from generate_series(0, 6) d;
insert into public.servicos (id, salao_id, nome, duracao_min, preco) values
  ('f5300000-0000-0000-0000-000000000001', 'f5100000-0000-0000-0000-000000000001', 'Corte', 30, 60);
insert into public.clientes (id, salao_id, nome, telefone) values
  ('f5400000-0000-0000-0000-000000000001', 'f5100000-0000-0000-0000-000000000001', 'Maria Lima', '11977776666');

-- Só o agendamento, como na primeira das duas chamadas do painel.
create or replace function so_agendamento(p_id uuid, p_dia int) returns void
language plpgsql as $f$
declare v_ini timestamptz := (date_trunc('day', now() at time zone 'America/Sao_Paulo')
                              + make_interval(days => p_dia, hours => 10)) at time zone 'America/Sao_Paulo';
begin
  insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, valor_previsto)
  values (p_id, 'f5100000-0000-0000-0000-000000000001', 'f5400000-0000-0000-0000-000000000001',
          'f5200000-0000-0000-0000-000000000001', v_ini, v_ini + interval '30 minutes', 'confirmado', 60);
end $f$;

create or replace function confirmacao_de(p_ag uuid) returns public.notificacoes
language sql as $f$
  select * from public.notificacoes where agendamento_id = p_ag and tipo = 'confirmacao'
$f$;

-- O lembrete fica para depois: aqui só a confirmação, que sai na hora.
select so_agendamento('f5500000-0000-0000-0000-000000000001', 2);
update public.notificacoes set quando = now() + interval '1 day'
 where tipo <> 'confirmacao' and status = 'pendente';

\echo ''
\echo 'A segunda chamada do painel ainda não chegou'
select count(*) as tomadas from public.notificacao_proxima(1) \gset
select t_verdade('1. a confirmação sem serviço NÃO é tomada (sairia "Serviço: atendimento")',
  :tomadas = 0 and (confirmacao_de('f5500000-0000-0000-0000-000000000001')).status = 'pendente');

\echo ''
\echo 'O serviço chegou'
insert into public.agendamento_servicos (agendamento_id, servico_id, duracao_min, preco)
values ('f5500000-0000-0000-0000-000000000001', 'f5300000-0000-0000-0000-000000000001', 30, 60);
create temporary table tomada as select * from public.notificacao_proxima(1);
select t_verdade('2. agora é tomada',
  (select count(*) from tomada where id = (confirmacao_de('f5500000-0000-0000-0000-000000000001')).id) = 1);
select t_verdade('   e o texto que sai já diz o serviço',
  (select corpo from tomada) like '%Corte%' and (select corpo from tomada) not like '%atendimento%');

\echo ''
\echo 'Agendamento que nunca terá serviço'
select so_agendamento('f5500000-0000-0000-0000-000000000002', 3);
update public.notificacoes set quando = now() + interval '1 day'
 where tipo <> 'confirmacao' and status = 'pendente';
update public.notificacoes set quando = now() - interval '2 minutes'
 where agendamento_id = 'f5500000-0000-0000-0000-000000000002' and tipo = 'confirmacao';
select count(*) as tomadas from public.notificacao_proxima(1) \gset
select t_verdade('3. passado um minuto, sai mesmo sem serviço — não fica presa',
  :tomadas = 1 and (confirmacao_de('f5500000-0000-0000-0000-000000000002')).status = 'enviando');

\echo ''
\echo 'Mensagem sem agendamento'
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave) values
  ('f5100000-0000-0000-0000-000000000001', 'resumo', '5511900003001', now(), 'resumo do dia', 'fila-resumo-1');
select count(*) as tomadas from public.notificacao_proxima(1) \gset
select t_verdade('4. o resumo do dia sai na hora, sem esperar serviço nenhum',
  :tomadas = 1 and (select status from public.notificacoes where chave = 'fila-resumo-1') = 'enviando');
