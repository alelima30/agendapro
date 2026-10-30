-- ===========================================================================
-- AgendaPro — o que a auditoria de segurança achou (42_travas.sql e 14_motor)
--
--   1. a dona de salão suspenso NÃO se reativa pela API; a plataforma e o SQL
--      Editor mudam o status como sempre; a data de criação não muda;
--   2. virar "cliente" de um salão (o insert livre do link) não dá a linha do
--      salão — o `cfg` inteiro — a quem não é da equipe;
--   3. `porque_nao_cabe()` e `avaliar_horario()` não dizem nome de cliente nem
--      motivo de bloqueio a quem não é da equipe; a equipe continua lendo.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4200000-0000-0000-0000-00000000000a'),  -- Ana   — dona do salão
  ('b4200000-0000-0000-0000-00000000000b'),  -- Bia   — profissional
  ('c4200000-0000-0000-0000-00000000000c'),  -- Carla — só cliente (conta do link)
  ('f4200000-0000-0000-0000-00000000000f');  -- Super — a plataforma

insert into public.perfis (id, nome, telefone, super_admin) values
  ('a4200000-0000-0000-0000-00000000000a', 'Ana',   '+5511942000001', false),
  ('b4200000-0000-0000-0000-00000000000b', 'Bia',   '+5511942000002', false),
  ('c4200000-0000-0000-0000-00000000000c', 'Carla', '+5511942000003', false),
  ('f4200000-0000-0000-0000-00000000000f', 'Plataforma', '+5511942000009', true)
on conflict (id) do update set nome = excluded.nome, super_admin = excluded.super_admin;

insert into public.saloes (id, slug, nome, status, cfg) values
  ('54200000-1111-0000-0000-00000000000a', 'travas-a', 'Salão Travas', 'suspenso',
   '{"notifLembreteEquipePara": "segredo-interno", "diasLiberados": 30}');
insert into public.assinaturas (salao_id, plano, status) values
  ('54200000-1111-0000-0000-00000000000a', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a4200000-0000-0000-0000-00000000000a', '54200000-1111-0000-0000-00000000000a', 'dono'),
  ('b4200000-0000-0000-0000-00000000000b', '54200000-1111-0000-0000-00000000000a', 'profissional');
insert into public.profissionais (id, salao_id, perfil_id, nome) values
  ('94200000-0000-0000-0000-00000000000b', '54200000-1111-0000-0000-00000000000a',
   'b4200000-0000-0000-0000-00000000000b', 'Bia');
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '94200000-0000-0000-0000-00000000000b', d, '00:00', '23:59' from generate_series(0, 6) d;
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c4210000-0000-0000-0000-00000000000a', '54200000-1111-0000-0000-00000000000a',
   'Maria Sigilosa', '5511942000077');
insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status) values
  ('54200000-1111-0000-0000-00000000000a', 'c4210000-0000-0000-0000-00000000000a',
   '94200000-0000-0000-0000-00000000000b', '2030-01-10 10:00-03', '2030-01-10 11:00-03', 'confirmado');
insert into public.bloqueios (salao_id, profissional_id, inicio, fim, motivo) values
  ('54200000-1111-0000-0000-00000000000a', '94200000-0000-0000-0000-00000000000b',
   '2030-01-10 14:00-03', '2030-01-10 15:00-03', 'consulta médica');

grant usage on schema auth to anon, authenticated;

\echo ''
\echo '1. O status do salão é da plataforma'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4200000-0000-0000-0000-00000000000a';
  do $$ begin
    perform t_texto('a dona do salão suspenso não se reativa pela API',
      erro_de($q$update public.saloes set status = 'ativo'
                 where id = '54200000-1111-0000-0000-00000000000a'$q$),
      'Só a plataforma muda a situação do salão (ativo, suspenso ou cancelado).');
    perform t_texto('nem muda a data de criação',
      erro_de($q$update public.saloes set criado_em = now() - interval '5 years'
                 where id = '54200000-1111-0000-0000-00000000000a'$q$),
      'A data de criação do salão não muda.');
    update public.saloes set nome = 'Salão Travas Novo' where id = '54200000-1111-0000-0000-00000000000a';
    perform t_texto('mas o resto do cadastro ela edita como sempre',
      (select nome from public.saloes where id = '54200000-1111-0000-0000-00000000000a'),
      'Salão Travas Novo');
  end $$;
commit;

do $$ begin
  perform t_texto('no banco, o salão continua suspenso',
    (select status from public.saloes where id = '54200000-1111-0000-0000-00000000000a'), 'suspenso');
end $$;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'f4200000-0000-0000-0000-00000000000f';
  select public.definir_status_salao('54200000-1111-0000-0000-00000000000a', 'ativo');
  do $$ begin
    perform t_texto('a plataforma reativa pela função dela',
      (select status from public.saloes where id = '54200000-1111-0000-0000-00000000000a'), 'ativo');
  end $$;
commit;

do $$ begin
  update public.saloes set status = 'suspenso' where id = '54200000-1111-0000-0000-00000000000a';
  perform t_texto('e o SQL Editor também muda (não é chamada da internet)',
    (select status from public.saloes where id = '54200000-1111-0000-0000-00000000000a'), 'suspenso');
  update public.saloes set status = 'ativo' where id = '54200000-1111-0000-0000-00000000000a';
end $$;

\echo ''
\echo '2. Virar cliente não dá a linha do salão'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'c4200000-0000-0000-0000-00000000000c';
  insert into public.vinculos (perfil_id, salao_id, papel, status)
    values ('c4200000-0000-0000-0000-00000000000c', '54200000-1111-0000-0000-00000000000a', 'cliente', 'ativo');
  do $$ begin
    perform t_igual('a conta que só virou cliente não lê a tabela do salão',
      (select count(*) from public.saloes where id = '54200000-1111-0000-0000-00000000000a'), 0);
    perform t_verdade('mas o link continua lendo o salão pela vitrine',
      public.vitrine('travas-a') is not null
      and public.vitrine('travas-a')::text not like '%segredo-interno%');
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4200000-0000-0000-0000-00000000000b';
  do $$ begin
    perform t_igual('a profissional da casa lê a linha do salão',
      (select count(*) from public.saloes where id = '54200000-1111-0000-0000-00000000000a'), 1);
  end $$;
commit;

\echo ''
\echo '3. O porquê de não caber é da equipe'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'c4200000-0000-0000-0000-00000000000c';
  do $$ begin
    perform t_texto('quem não é da equipe não lê o nome da cliente na agenda',
      erro_de($q$select public.porque_nao_cabe('94200000-0000-0000-0000-00000000000b',
                 '2030-01-10 10:15-03', '2030-01-10 10:45-03')$q$),
      'Só a equipe do salão consulta a agenda.');
    perform t_texto('nem pelo avaliar_horario',
      erro_de($q$select public.avaliar_horario('94200000-0000-0000-0000-00000000000b',
                 '2030-01-10 14:15-03', '2030-01-10 14:45-03')$q$),
      'Só a equipe do salão consulta a agenda.');
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4200000-0000-0000-0000-00000000000b';
  do $$ begin
    perform t_verdade('a profissional da casa continua vendo com quem está o horário',
      public.porque_nao_cabe('94200000-0000-0000-0000-00000000000b',
        '2030-01-10 10:15-03', '2030-01-10 10:45-03') like '%Maria Sigilosa%');
    perform t_verdade('e o motivo do bloqueio',
      (public.avaliar_horario('94200000-0000-0000-0000-00000000000b',
        '2030-01-10 14:15-03', '2030-01-10 14:45-03'))->>'motivo' like '%consulta médica%');
  end $$;
commit;

do $$ begin
  perform t_verdade('e o SQL Editor também (os testes do motor seguem valendo)',
    public.porque_nao_cabe('94200000-0000-0000-0000-00000000000b',
      '2030-01-10 10:15-03', '2030-01-10 10:45-03') like '%Maria Sigilosa%');
end $$;
