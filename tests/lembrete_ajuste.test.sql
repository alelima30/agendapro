-- ===========================================================================
-- AgendaPro — o lembrete da cliente acompanha o ajuste (21_notificacoes.sql)
--
-- "Parece que o lembrete não está funcionando, chega uma hora antes." O
-- lembrete era calculado UMA vez, ao marcar: trocar o tempo em Notificações
-- não mexia nos horários já marcados. O que se confere:
--   1. marcado com "1 hora antes", o lembrete nasce 1 hora antes;
--   2. trocou para "3 horas antes": o da fila vai para 3 horas antes;
--   3. trocou para "24 horas antes" com o horário daqui a 10 horas: a hora
--      nova já passou, então o lembrete de antes FICA (não some, não nasce
--      um "para agora");
--   4. desligou: o pendente sai da fila, dizendo por quê;
--   5. ligou de novo: o lembrete volta, na hora do ajuste;
--   6. o que já saiu não se mexe;
--   7. horário de quem não tem WhatsApp na ficha: nada nasce.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo, status, cfg) values
  ('1a100000-0000-0000-0000-000000000001', 'studio-lembra', 'Studio Lembra', 'salao', 'ativo',
   '{"notifLembrete": true, "notifLembreteMin": 60}');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('1a100000-0000-0000-0000-000000000001', 'time', 'ativa', current_date + 30);
insert into public.profissionais (id, salao_id, nome, ativo) values
  ('1a200000-0000-0000-0000-000000000001', '1a100000-0000-0000-0000-000000000001', 'Bia Souza', true);
insert into public.servicos (id, salao_id, nome, duracao_min, preco) values
  ('1a300000-0000-0000-0000-000000000001', '1a100000-0000-0000-0000-000000000001', 'Corte', 30, 60);
insert into public.clientes (id, salao_id, nome, telefone) values
  ('1a400000-0000-0000-0000-000000000001', '1a100000-0000-0000-0000-000000000001', 'Maria Lima', '11977776666'),
  ('1a400000-0000-0000-0000-000000000002', '1a100000-0000-0000-0000-000000000001', 'Sem Zap', null);

-- Sem jornada: a regra de jornada não vale para quem não configurou nenhuma.
create or replace function marcar(p_id uuid, p_cli uuid, p_horas int) returns void
language plpgsql as $f$
declare v_ini timestamptz := date_trunc('minute', now()) + make_interval(hours => p_horas);
begin
  insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, valor_previsto)
  values (p_id, '1a100000-0000-0000-0000-000000000001', p_cli,
          '1a200000-0000-0000-0000-000000000001', v_ini, v_ini + interval '30 minutes', 'confirmado', 60);
  insert into public.agendamento_servicos (agendamento_id, servico_id, duracao_min, preco)
  values (p_id, '1a300000-0000-0000-0000-000000000001', 30, 60);
end $f$;

create or replace function lembrete(p_ag uuid) returns public.notificacoes
language sql as $f$
  select * from public.notificacoes where agendamento_id = p_ag and tipo = 'lembrete'
$f$;
create or replace function antes(p_ag uuid) returns int
language sql as $f$
  select round(extract(epoch from (a.inicio - n.quando)) / 60)::int
    from public.agendamentos a join public.notificacoes n on n.agendamento_id = a.id and n.tipo = 'lembrete'
   where a.id = p_ag
$f$;
create or replace function ajuste(p jsonb) returns void
language sql as $f$
  update public.saloes set cfg = cfg || p where id = '1a100000-0000-0000-0000-000000000001'
$f$;

-- Um horário daqui a 10 horas, outro daqui a 20.
select marcar('1a500000-0000-0000-0000-000000000001', '1a400000-0000-0000-0000-000000000001', 10);
select marcar('1a500000-0000-0000-0000-000000000002', '1a400000-0000-0000-0000-000000000001', 20);

\echo ''
\echo 'Marcado com "1 hora antes"'
select t_igual('1. o lembrete nasce 1 hora antes do horário (60 min)',
  antes('1a500000-0000-0000-0000-000000000001'), 60);

\echo ''
\echo 'Trocou para "3 horas antes"'
select ajuste('{"notifLembreteMin": 180}');
select t_verdade('   (sem a varredura, ele continuava 1 hora antes — era o defeito)',
  antes('1a500000-0000-0000-0000-000000000001') = 60);
select public.gerar_lembretes_cliente();
select t_igual('2. o da fila vai para 3 horas antes (180 min)',
  antes('1a500000-0000-0000-0000-000000000001'), 180);
select t_igual('   e o do outro horário também',
  antes('1a500000-0000-0000-0000-000000000002'), 180);
select t_verdade('   continua pendente, com o texto refeito',
  (lembrete('1a500000-0000-0000-0000-000000000001')).status = 'pendente'
  and (lembrete('1a500000-0000-0000-0000-000000000001')).corpo like '%Corte%');
select t_igual('   rodar de novo não refaz nada', public.gerar_lembretes_cliente(), 0);

\echo ''
\echo 'Trocou para "24 horas antes" (o de daqui a 10 horas já passou da hora)'
select ajuste('{"notifLembreteMin": 1440}');
select public.gerar_lembretes_cliente();
select t_igual('3. o de daqui a 10 horas FICA como estava (3 horas antes), sem sumir',
  antes('1a500000-0000-0000-0000-000000000001'), 180);
select t_verdade('   e sem nascer um "para agora"',
  (lembrete('1a500000-0000-0000-0000-000000000001')).quando > now());
select t_igual('   o de daqui a 20 horas também fica (24 horas antes já passou)',
  antes('1a500000-0000-0000-0000-000000000002'), 180);

\echo ''
\echo 'Desligou o lembrete'
select ajuste('{"notifLembrete": false}');
select public.gerar_lembretes_cliente();
select t_verdade('4. o pendente sai da fila, dizendo por quê',
  (lembrete('1a500000-0000-0000-0000-000000000001')).status = 'cancelado'
  and (lembrete('1a500000-0000-0000-0000-000000000001')).motivo = 'o lembrete foi desligado no salão');

\echo ''
\echo 'Ligou de novo, "2 horas antes"'
select ajuste('{"notifLembrete": true, "notifLembreteMin": 120}');
select public.gerar_lembretes_cliente();
select t_verdade('5. o lembrete volta para a fila, 2 horas antes',
  (lembrete('1a500000-0000-0000-0000-000000000001')).status = 'pendente'
  and antes('1a500000-0000-0000-0000-000000000001') = 120
  and (lembrete('1a500000-0000-0000-0000-000000000001')).motivo is null);

\echo ''
\echo 'O que já saiu'
update public.notificacoes set status = 'enviado', enviado_em = now()
 where agendamento_id = '1a500000-0000-0000-0000-000000000002' and tipo = 'lembrete';
select ajuste('{"notifLembreteMin": 30}');
select public.gerar_lembretes_cliente();
select t_verdade('6. o lembrete já enviado não se mexe nem volta para a fila',
  (lembrete('1a500000-0000-0000-0000-000000000002')).status = 'enviado'
  and antes('1a500000-0000-0000-0000-000000000002') = 120);
select t_igual('   e o pendente segue o ajuste novo (30 min)',
  antes('1a500000-0000-0000-0000-000000000001'), 30);

\echo ''
\echo 'Cliente sem WhatsApp na ficha'
select marcar('1a500000-0000-0000-0000-000000000003', '1a400000-0000-0000-0000-000000000002', 8);
select public.gerar_lembretes_cliente();
select t_verdade('7. nada nasce para quem não tem número',
  (lembrete('1a500000-0000-0000-0000-000000000003')).id is null);
