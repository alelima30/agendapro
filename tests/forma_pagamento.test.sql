-- ===========================================================================
-- AgendaPro — como a cliente vai pagar (09_cliente.sql, 1d)
--
--   1. O que ela escolhe no link é gravado no agendamento.
--   2. Forma estranha, ou que o salão não aceita, vira nula — e a marcação
--      não cai por isso.
--   3. Atendimento que sai por R$ 0 (pacote) não guarda forma.
--   4. "Meus horários" devolve a forma.
--   5. A trava das quatro formas vale para o painel também.
-- ===========================================================================

\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo, status, fuso, cfg) values
  ('fb000000-1111-0000-0000-000000000001', 'salao-pagamento', 'Salão Pagamento', 'salao',
   'ativo', 'America/Sao_Paulo', '{"diasLiberados": 30}'),
  -- Este salão marcou o que aceita: só Pix e crédito.
  ('fb000000-1111-0000-0000-000000000002', 'salao-pix-credito', 'Salão Pix', 'salao',
   'ativo', 'America/Sao_Paulo', '{"diasLiberados": 30, "pagamentos": {"formas": ["pix", "credito"]}}');
insert into public.assinaturas (salao_id, plano, status) values
  ('fb000000-1111-0000-0000-000000000001', 'time', 'ativa'),
  ('fb000000-1111-0000-0000-000000000002', 'time', 'ativa');

insert into auth.users (id, email) values
  ('fb000000-0000-0000-0000-00000000000d', 'dona@pagamento.com'),
  ('fb000000-0000-0000-0000-00000000000c', 'rita@pagamento.com');
insert into public.perfis (id, nome, telefone) values
  ('fb000000-0000-0000-0000-00000000000d', 'Dona', '+5511900004001'),
  ('fb000000-0000-0000-0000-00000000000c', 'Rita', '+5551944445555')
on conflict (id) do nothing;
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('fb000000-0000-0000-0000-00000000000d', 'fb000000-1111-0000-0000-000000000001', 'dono', 'ativo');

insert into public.profissionais (id, salao_id, nome, ativo, aceita_online) values
  ('fb000000-2222-0000-0000-000000000001', 'fb000000-1111-0000-0000-000000000001', 'Ana', true, true),
  ('fb000000-2222-0000-0000-000000000002', 'fb000000-1111-0000-0000-000000000002', 'Lu', true, true);
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco, ativo, aceita_online) values
  ('fb000000-3333-0000-0000-000000000001', 'fb000000-1111-0000-0000-000000000001', 'Escova', 30, 0, 50, true, true),
  ('fb000000-3333-0000-0000-000000000002', 'fb000000-1111-0000-0000-000000000002', 'Escova', 30, 0, 50, true, true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
select p, d, '08:00', '20:00'
  from unnest(array['fb000000-2222-0000-0000-000000000001'::uuid,
                    'fb000000-2222-0000-0000-000000000002'::uuid]) p,
       generate_series(0, 6) d;

-- A n-ésima vaga livre de um dia, para cada marcação cair num horário seu.
create or replace function vaga_fp(p_prof uuid, p_serv uuid, p_n int) returns timestamptz
language sql stable as $f$
  select h from public.horarios_livres(p_prof, (now() at time zone 'America/Sao_Paulo')::date + 3,
                                       array[p_serv]) h
   order by h offset p_n - 1 limit 1
$f$;
create or replace function forma_de(p_id uuid) returns text language sql stable as $f$
  select coalesce(forma_pagamento, '(nula)') from public.agendamentos where id = p_id
$f$;

\echo ''
\echo '1) O que ela escolhe é gravado'

create temporary table m1 as
select * from public.agendar('fb000000-2222-0000-0000-000000000001'::uuid,
  vaga_fp('fb000000-2222-0000-0000-000000000001', 'fb000000-3333-0000-0000-000000000001', 1),
  array['fb000000-3333-0000-0000-000000000001'::uuid], 'Bia Lima', '51911110001',
  p_forma_pagamento => 'pix');
select t_texto('marcou dizendo "Pix": o agendamento guarda pix', forma_de((select id from m1)), 'pix');

create temporary table m2 as
select * from public.agendar('fb000000-2222-0000-0000-000000000001'::uuid,
  vaga_fp('fb000000-2222-0000-0000-000000000001', 'fb000000-3333-0000-0000-000000000001', 3),
  array['fb000000-3333-0000-0000-000000000001'::uuid], 'Caio Reis', '51911110002');
select t_texto('sem escolher (salão que não marcou formas): fica sem forma, e marca igual',
  forma_de((select id from m2)), '(nula)');

\echo ''
\echo '2) Forma estranha, ou que o salão não aceita'

create temporary table m3 as
select * from public.agendar('fb000000-2222-0000-0000-000000000001'::uuid,
  vaga_fp('fb000000-2222-0000-0000-000000000001', 'fb000000-3333-0000-0000-000000000001', 5),
  array['fb000000-3333-0000-0000-000000000001'::uuid], 'Duda Melo', '51911110003',
  p_forma_pagamento => 'ouro');
select t_texto('"ouro" não é forma: a marcação acontece, e a forma fica nula',
  forma_de((select id from m3)), '(nula)');

create temporary table m4 as
select * from public.agendar('fb000000-2222-0000-0000-000000000002'::uuid,
  vaga_fp('fb000000-2222-0000-0000-000000000002', 'fb000000-3333-0000-0000-000000000002', 1),
  array['fb000000-3333-0000-0000-000000000002'::uuid], 'Eva Dias', '51911110004',
  p_forma_pagamento => 'dinheiro');
select t_texto('o salão aceita só Pix e crédito: "dinheiro" não é gravado',
  forma_de((select id from m4)), '(nula)');

create temporary table m5 as
select * from public.agendar('fb000000-2222-0000-0000-000000000002'::uuid,
  vaga_fp('fb000000-2222-0000-0000-000000000002', 'fb000000-3333-0000-0000-000000000002', 3),
  array['fb000000-3333-0000-0000-000000000002'::uuid], 'Fê Souza', '51911110005',
  p_forma_pagamento => ' Credito ');
select t_texto('e "crédito" (com espaço e maiúscula) é', forma_de((select id from m5)), 'credito');

\echo ''
\echo '3) O que sai por R$ 0 não guarda forma'

insert into public.clientes (id, salao_id, perfil_id, nome, telefone) values
  ('fb000000-7777-0000-0000-000000000001', 'fb000000-1111-0000-0000-000000000001',
   'fb000000-0000-0000-0000-00000000000c', 'Rita', '51944445555');
insert into public.pacotes (id, salao_id, nome, sessoes, preco, validade_dias, ativo) values
  ('fb000000-8888-0000-0000-000000000001', 'fb000000-1111-0000-0000-000000000001', '4 escovas', 4, 160, 90, true);
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('fb000000-8888-0000-0000-000000000001', 'fb000000-3333-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-00000000000d', false);
select public.vender_pacote('fb000000-8888-0000-0000-000000000001', 'fb000000-7777-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-00000000000c', false);
create temporary table m6 as
select * from public.agendar('fb000000-2222-0000-0000-000000000001'::uuid,
  vaga_fp('fb000000-2222-0000-0000-000000000001', 'fb000000-3333-0000-0000-000000000001', 7),
  array['fb000000-3333-0000-0000-000000000001'::uuid], 'Rita', '51944445555',
  p_forma_pagamento => 'pix');
select set_config('request.jwt.claim.sub', '', false);
select t_verdade('a sessão do pacote sai por R$ 0 e sem forma de pagamento',
  (select valor from m6) = 0 and forma_de((select id from m6)) = '(nula)');

\echo ''
\echo '4) "Meus horários" devolve a forma'

select t_texto('meus_agendamentos traz "forma_pagamento"',
  public.meus_agendamentos(array[(select token from m1)])->0->>'forma_pagamento', 'pix');

\echo ''
\echo '5) A trava vale para o painel também'

-- O id numa variável do psql: a tabela temporária é do superusuário, e o
-- papel `authenticated` não a enxerga.
select id as m2_id from m2 \gset
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'fb000000-0000-0000-0000-00000000000d';
  do $$ begin perform t_verdade('a dona não grava uma forma inventada',
    recusado($q$ update public.agendamentos set forma_pagamento = 'ouro'
                 where salao_id = 'fb000000-1111-0000-0000-000000000001' $q$)); end $$;
  update public.agendamentos set forma_pagamento = 'debito' where id = :'m2_id';
commit;
select t_texto('e anota "débito" num horário marcado por telefone', forma_de((select id from m2)), 'debito');
