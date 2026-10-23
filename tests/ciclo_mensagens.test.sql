-- ===========================================================================
-- AgendaPro — o mês da franquia conta do dia da assinatura (22_cotas.sql)
--
-- "Conta a partir do dia da assinatura." O contador de mensagens zerava todo
-- dia 1º: quem assinava no dia 20 tinha as 500 por dez dias, e outras 500 no
-- dia 1º. Agora o mês vai do dia da assinatura (o dia do `vence_em`) ao mesmo
-- dia do mês seguinte.
--
--   1. assinatura em dia: do dia do vencimento, mês a mês;
--   2. paga adiantado: o dia não muda, e nada zera antes da hora;
--   3. dia 31 em mês curto: o último dia do mês, sem buraco entre ciclos;
--   4. teste grátis: o teste inteiro num ciclo só, com o último dia dentro;
--   5. sem vencimento: o mês do calendário, como antes;
--   6. o contador usa o ciclo, e o painel recebe o dia em que renova;
--   7. a função é interna.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo, status) values
  ('c1100000-0000-0000-0000-000000000001', 'ciclo-dia-20', 'Ciclo 20', 'salao', 'ativo'),
  ('c1100000-0000-0000-0000-000000000002', 'ciclo-dia-31', 'Ciclo 31', 'salao', 'ativo'),
  ('c1100000-0000-0000-0000-000000000003', 'ciclo-teste',  'Ciclo Teste', 'salao', 'ativo'),
  ('c1100000-0000-0000-0000-000000000004', 'ciclo-sem',    'Ciclo Sem', 'salao', 'ativo'),
  ('c1100000-0000-0000-0000-000000000005', 'ciclo-hoje',   'Ciclo Hoje', 'salao', 'ativo');
insert into public.assinaturas (salao_id, plano, status, vence_em, trial_ate) values
  ('c1100000-0000-0000-0000-000000000001', 'individual', 'ativa', '2027-03-20', null),
  ('c1100000-0000-0000-0000-000000000002', 'individual', 'ativa', '2027-03-31', null),
  ('c1100000-0000-0000-0000-000000000003', 'trial',      'trial', null, '2027-05-07'),
  ('c1100000-0000-0000-0000-000000000004', 'individual', 'ativa', null, null),
  ('c1100000-0000-0000-0000-000000000005', 'individual', 'ativa',
     (now() at time zone 'America/Sao_Paulo')::date, null);

create or replace function ciclo(p_salao uuid, p_hoje date) returns text
language sql as $f$
  select to_char(c.ini at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI') || ' até '
      || to_char(c.fim at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI')
    from public.ciclo_mensagens(p_salao, p_hoje) c
$f$;

\echo ''
\echo '1. Assinatura em dia (vence dia 20)'
select t_texto('no dia 5, o ciclo é do dia 20 passado ao dia 20 (e não do dia 1º)',
  ciclo('c1100000-0000-0000-0000-000000000001', '2027-03-05'),
  '2027-02-20 00:00 até 2027-03-20 00:00');
select t_texto('no dia 1º não zera nada',
  ciclo('c1100000-0000-0000-0000-000000000001', '2027-03-01'),
  '2027-02-20 00:00 até 2027-03-20 00:00');
select t_texto('no dia do vencimento começa o ciclo novo',
  ciclo('c1100000-0000-0000-0000-000000000001', '2027-03-20'),
  '2027-03-20 00:00 até 2027-04-20 00:00');

\echo ''
\echo '2. Paga adiantado: o vencimento andou um mês, o dia ficou'
select t_texto('dois meses antes do vencimento, o ciclo é o do mês de agora',
  ciclo('c1100000-0000-0000-0000-000000000001', '2027-01-25'),
  '2027-01-20 00:00 até 2027-02-20 00:00');
select t_texto('e na véspera do dia 20 ainda é o mesmo',
  ciclo('c1100000-0000-0000-0000-000000000001', '2027-02-19'),
  '2027-01-20 00:00 até 2027-02-20 00:00');

\echo ''
\echo '3. Dia 31 em mês curto'
select t_texto('em fevereiro, o dia 31 vira o 28',
  ciclo('c1100000-0000-0000-0000-000000000002', '2027-02-15'),
  '2027-01-31 00:00 até 2027-02-28 00:00');
select t_texto('e o ciclo seguinte começa onde o outro termina',
  ciclo('c1100000-0000-0000-0000-000000000002', '2027-02-28'),
  '2027-02-28 00:00 até 2027-03-31 00:00');
select t_texto('em abril, o 30',
  ciclo('c1100000-0000-0000-0000-000000000002', '2027-04-29'),
  '2027-03-31 00:00 até 2027-04-30 00:00');

\echo ''
\echo '4. Teste grátis (termina dia 7)'
select t_texto('o teste inteiro num ciclo só',
  ciclo('c1100000-0000-0000-0000-000000000003', '2027-05-01'),
  '2027-04-08 00:00 até 2027-05-08 00:00');
select t_texto('o último dia do teste não ganha outras 100',
  ciclo('c1100000-0000-0000-0000-000000000003', '2027-05-07'),
  '2027-04-08 00:00 até 2027-05-08 00:00');

\echo ''
\echo '5. Sem vencimento: o mês do calendário'
select t_texto('do dia 1º ao dia 1º',
  ciclo('c1100000-0000-0000-0000-000000000004', '2027-06-15'),
  '2027-06-01 00:00 até 2027-07-01 00:00');

\echo ''
\echo '6. O contador e o painel'
-- Vence hoje: o ciclo começou à meia-noite. Uma enviada uma hora antes é do
-- ciclo passado (e no mês do calendário ela contava); uma de agora conta.
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
select 'c1100000-0000-0000-0000-000000000005', 'lembrete', '11999', now(), 'x', 'ciclo:antes',
       'enviado', c.ini - interval '1 hour'
  from public.ciclo_mensagens('c1100000-0000-0000-0000-000000000005') c;
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
values ('c1100000-0000-0000-0000-000000000005', 'lembrete', '11999', now(), 'x', 'ciclo:agora',
        'enviado', now());
select t_igual('só a mensagem do ciclo de agora conta',
  public.mensagens_no_mes('c1100000-0000-0000-0000-000000000005')::bigint, 1);

insert into auth.users (id) values ('c1900000-0000-0000-0000-000000000001') on conflict do nothing;
insert into public.perfis (id, nome, email) values
  ('c1900000-0000-0000-0000-000000000001', 'Dona Ciclo', 'ciclo@teste.com')
  on conflict (id) do nothing;
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('c1900000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000005', 'dono', 'ativo'),
  ('c1900000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000003', 'dono', 'ativo');
select set_config('request.jwt.claim.sub', 'c1900000-0000-0000-0000-000000000001', false);
select t_texto('o painel recebe o dia em que renova: daqui a um mês',
  public.uso_do_plano('c1100000-0000-0000-0000-000000000005')->'mensagens'->>'renovaEm',
  to_char((now() at time zone 'America/Sao_Paulo')::date + interval '1 month', 'YYYY-MM-DD'));
select t_igual('e o mesmo número que o contador',
  ((public.uso_do_plano('c1100000-0000-0000-0000-000000000005')->'mensagens'->>'usado')::int)::bigint, 1);
select t_verdade('no teste grátis não há "renova em" (ele não renova)',
  public.uso_do_plano('c1100000-0000-0000-0000-000000000003')->'mensagens'->>'renovaEm' is null);
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '7. Interna'
select t_falso('anon não executa ciclo_mensagens',
  has_function_privilege('anon', 'public.ciclo_mensagens(uuid, date)', 'execute'));
select t_falso('nem quem está logado',
  has_function_privilege('authenticated', 'public.ciclo_mensagens(uuid, date)', 'execute'));
