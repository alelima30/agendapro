-- ===========================================================================
-- AgendaPro — a cliente excluiu a conta: o salão fica sabendo (56)
--
-- No Salão da Ana: a Maria (com conta, horário marcado e pacote) exclui a
-- conta; a Bia tem a ficha desligada por outro motivo (o perfil continua).
--
--   1. a conta some: a ficha fica, desligada, com o dia em que a conta sumiu;
--      desligar a ficha com o perfil ainda existindo não marca nada;
--   2. o sino do balcão avisa (com quem tem horário e pacote); quem atende, não;
--   3. visto, sai do sino, e a marca na ficha fica;
--   4. ela volta e cria conta de novo: a ficha é religada e a marca sai.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5600000-0000-0000-0000-00000000000a'),  -- Ana   — dona
  ('b5600000-0000-0000-0000-00000000000b'),  -- Rita  — recepção
  ('d5600000-0000-0000-0000-00000000000d'),  -- Ju    — profissional
  ('c5600000-0000-0000-0000-00000000000c'),  -- Maria — cliente
  ('e5600000-0000-0000-0000-00000000000e');  -- Bia   — cliente
insert into public.perfis (id, nome, telefone) values
  ('a5600000-0000-0000-0000-00000000000a', 'Ana',         '+5511956000001'),
  ('b5600000-0000-0000-0000-00000000000b', 'Rita',        '+5511956000002'),
  ('d5600000-0000-0000-0000-00000000000d', 'Ju',          '+5511956000004'),
  ('c5600000-0000-0000-0000-00000000000c', 'Maria Souza', '+5511956000003'),
  ('e5600000-0000-0000-0000-00000000000e', 'Bia Lima',    '+5511956000005')
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone;
insert into public.saloes (id, slug, nome, tipo, status, fuso) values
  ('55600000-0000-0000-0000-00000000000a', 'conta-ana', 'Salão da Ana', 'salao', 'ativo', 'America/Sao_Paulo');
select public.hoje_no_salao('55600000-0000-0000-0000-00000000000a') as hoje \gset
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('55600000-0000-0000-0000-00000000000a', 'time', 'ativa', :'hoje'::date + 20);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a5600000-0000-0000-0000-00000000000a', '55600000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('b5600000-0000-0000-0000-00000000000b', '55600000-0000-0000-0000-00000000000a', 'recepcao', 'ativo'),
  ('d5600000-0000-0000-0000-00000000000d', '55600000-0000-0000-0000-00000000000a', 'profissional', 'ativo');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct) values
  ('95600000-0000-0000-0000-00000000000d', '55600000-0000-0000-0000-00000000000a', 'd5600000-0000-0000-0000-00000000000d', 'Ju', 10);
insert into public.clientes (id, salao_id, nome, telefone, perfil_id) values
  ('c5610000-0000-0000-0000-000000000001', '55600000-0000-0000-0000-00000000000a', 'Maria Souza', '11956000003',
   'c5600000-0000-0000-0000-00000000000c'),
  ('c5610000-0000-0000-0000-000000000002', '55600000-0000-0000-0000-00000000000a', 'Bia Lima', '11956000005',
   'e5600000-0000-0000-0000-00000000000e');
-- A Maria tem horário marcado e um pacote ativo.
insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
  values ('55600000-0000-0000-0000-00000000000a', 'c5610000-0000-0000-0000-000000000001', '95600000-0000-0000-0000-00000000000d',
          now() + interval '3 days', now() + interval '3 days 45 minutes', 'confirmado', 'online', 40);
insert into public.pacotes (id, salao_id, nome, sessoes, validade_dias, preco)
  values ('55630000-0000-0000-0000-000000000001', '55600000-0000-0000-0000-00000000000a', 'Escova do mês', 4, 60, 200);
insert into public.pacote_clientes (pacote_id, cliente_id, sessoes, vence_em)
  values ('55630000-0000-0000-0000-000000000001', 'c5610000-0000-0000-0000-000000000001', 4, :'hoje'::date + 30);
grant usage on schema auth to anon, authenticated;

create or replace function t_como(p_quem uuid, p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_quem::text, ''), true);
  set local role authenticated;
  execute p_sql into r;
  reset role;
  return r;
end $$;
create or replace function t_item(p_quem uuid) returns jsonb language sql as $$
  select (select i from jsonb_array_elements(s->'itens') i where i->>'tipo' = 'conta_excluida')
    from (select t_como(p_quem, 'select public.sino_do_painel(''55600000-0000-0000-0000-00000000000a'')') s) x
$$;

\echo ''
\echo '1. A conta some, a ficha fica'
delete from auth.users where id = 'c5600000-0000-0000-0000-00000000000c';
select t_texto('a ficha da Maria continua, desligada da conta, com o dia em que a conta sumiu',
  (select (perfil_id is null) || ' | ' || (conta_excluida_em is not null) || ' | ' || nome
     from public.clientes where id = 'c5610000-0000-0000-0000-000000000001'), 'true | true | Maria Souza');
select t_igual('   e o horário dela continua na agenda',
  (select count(*) from public.agendamentos where cliente_id = 'c5610000-0000-0000-0000-000000000001'
     and status = 'confirmado'), 1);
update public.clientes set perfil_id = null where id = 'c5610000-0000-0000-0000-000000000002';
select t_verdade('desligar a ficha com o perfil ainda existindo (a Bia) não marca nada',
  (select conta_excluida_em is null from public.clientes where id = 'c5610000-0000-0000-0000-000000000002'));

\echo ''
\echo '2. O sino'
select t_texto('o balcão (Rita) vê: Maria Souza, 1 com horário marcado, 1 com pacote',
  (select (i->>'qtd') || ' | ' || (i->'nomes'->>0) || ' | ' || (i->>'comHorario') || ' | ' || (i->>'comPacote')
     from (select t_item('b5600000-0000-0000-0000-00000000000b') i) x), '1 | Maria Souza | 1 | 1');
select t_verdade('   a dona também', t_item('a5600000-0000-0000-0000-00000000000a') is not null);
select t_verdade('quem atende (Ju) não vê', t_item('d5600000-0000-0000-0000-00000000000d') is null);

\echo ''
\echo '3. Visto'
select t_texto('quem atende não marca como visto',
  erro_de($$select t_como('d5600000-0000-0000-0000-00000000000d', 'select public.ver_contas_excluidas(''55600000-0000-0000-0000-00000000000a'')')$$),
  'Só o balcão e a gestão veem este aviso.');
select t_texto('a Rita vê o aviso: sai do sino',
  (t_como('b5600000-0000-0000-0000-00000000000b', 'select public.ver_contas_excluidas(''55600000-0000-0000-0000-00000000000a'')')->>'vistas')
  || ' | ' || coalesce(t_item('b5600000-0000-0000-0000-00000000000b')::text, 'sem aviso'), '1 | sem aviso');
select t_verdade('   e a marca na ficha fica',
  (select conta_excluida_em is not null from public.clientes where id = 'c5610000-0000-0000-0000-000000000001'));

\echo ''
\echo '4. Ela volta'
insert into auth.users (id) values ('c5600000-0000-0000-0000-0000000000c2');
insert into public.perfis (id, nome, telefone) values ('c5600000-0000-0000-0000-0000000000c2', 'Maria Souza', '+5511956000003')
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone;
update public.clientes set perfil_id = 'c5600000-0000-0000-0000-0000000000c2' where id = 'c5610000-0000-0000-0000-000000000001';
select t_verdade('criou conta de novo e a ficha foi religada: a marca sai',
  (select conta_excluida_em is null and conta_excluida_vista_em is null from public.clientes
    where id = 'c5610000-0000-0000-0000-000000000001'));
select set_config('request.jwt.claim.sub', '', false);
