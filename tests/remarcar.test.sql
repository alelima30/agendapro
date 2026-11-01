-- ===========================================================================
-- AgendaPro — o salão remarca um horário (49_remarcar.sql)
--
-- "Na onde entro para remarcar caso precise?"
--
--   1. quem chama: o anon nem chama;
--   2. a recepção move a sessão do pacote: o MESMO horário, ainda no pacote,
--      com os mesmos serviços e a mesma duração; o lembrete vai junto;
--   3. as regras do pacote: os dias dele e a validade;
--   4. choque: diz com quem, e não deixa encaixar;
--   5. fora da jornada: só com a confirmação, e fica como encaixe com nome;
--   6. outra profissional: a comissão passa a ser a dela;
--   7. quem atende remarca o próprio horário, para si — e só;
--   8. o que não se remarca: horário que já passou, cancelado, e a cliente.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4900000-0000-0000-0000-00000000000a'),  -- Ana   — dona
  ('b4900000-0000-0000-0000-00000000000b'),  -- Rita  — recepção
  ('d4900000-0000-0000-0000-00000000000d'),  -- Ju    — profissional
  ('d4900000-0000-0000-0000-00000000000e'),  -- Bia   — profissional
  ('c4900000-0000-0000-0000-00000000000c');  -- Maria — cliente com conta
insert into public.perfis (id, nome, telefone) values
  ('a4900000-0000-0000-0000-00000000000a', 'Ana',   '+5511949000001'),
  ('b4900000-0000-0000-0000-00000000000b', 'Rita',  '+5511949000002'),
  ('d4900000-0000-0000-0000-00000000000d', 'Ju',    '+5511949000004'),
  ('d4900000-0000-0000-0000-00000000000e', 'Bia',   '+5511949000005'),
  ('c4900000-0000-0000-0000-00000000000c', 'Maria', '+5511949000003')
on conflict (id) do update set nome = excluded.nome;

insert into public.saloes (id, slug, nome, status, fuso) values
  ('54900000-0000-0000-0000-00000000000a', 'remarcar', 'Salão Remarca', 'ativo', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status) values
  ('54900000-0000-0000-0000-00000000000a', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a4900000-0000-0000-0000-00000000000a', '54900000-0000-0000-0000-00000000000a', 'dono'),
  ('b4900000-0000-0000-0000-00000000000b', '54900000-0000-0000-0000-00000000000a', 'recepcao'),
  ('d4900000-0000-0000-0000-00000000000d', '54900000-0000-0000-0000-00000000000a', 'profissional'),
  ('d4900000-0000-0000-0000-00000000000e', '54900000-0000-0000-0000-00000000000a', 'profissional'),
  ('c4900000-0000-0000-0000-00000000000c', '54900000-0000-0000-0000-00000000000a', 'cliente');
insert into public.profissionais (id, salao_id, perfil_id, nome, telefone, ativo, comissao_pct) values
  ('94900000-0000-0000-0000-00000000000d', '54900000-0000-0000-0000-00000000000a',
   'd4900000-0000-0000-0000-00000000000d', 'Ju', '11949000004', true, 40),
  ('94900000-0000-0000-0000-00000000000e', '54900000-0000-0000-0000-00000000000a',
   'd4900000-0000-0000-0000-00000000000e', 'Bia', '11949000005', true, 50);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select p, d, '08:00', '20:00' from generate_series(0, 6) d,
    unnest(array['94900000-0000-0000-0000-00000000000d','94900000-0000-0000-0000-00000000000e']::uuid[]) p;
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco) values
  ('54910000-0000-0000-0000-0000000000a1', '54900000-0000-0000-0000-00000000000a', 'Mão', 45, 0, 40),
  ('54910000-0000-0000-0000-0000000000a2', '54900000-0000-0000-0000-00000000000a', 'Pé',  45, 0, 50);
insert into public.servicos_profissionais (servico_id, profissional_id)
  select s, p from unnest(array['54910000-0000-0000-0000-0000000000a1','54910000-0000-0000-0000-0000000000a2']::uuid[]) s,
    unnest(array['94900000-0000-0000-0000-00000000000d','94900000-0000-0000-0000-00000000000e']::uuid[]) p;
-- O pacote só das terças, 30 dias.
insert into public.pacotes (id, salao_id, nome, preco, sessoes, validade_dias, dias) values
  ('54920000-0000-0000-0000-0000000000b1', '54900000-0000-0000-0000-00000000000a',
   'Mão e pé das terças', 300, 4, 30, '{2}');
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('54920000-0000-0000-0000-0000000000b1', '54910000-0000-0000-0000-0000000000a1'),
  ('54920000-0000-0000-0000-0000000000b1', '54910000-0000-0000-0000-0000000000a2');
insert into public.clientes (id, salao_id, perfil_id, nome, telefone) values
  ('c4910000-0000-0000-0000-00000000000a', '54900000-0000-0000-0000-00000000000a',
   'c4900000-0000-0000-0000-00000000000c', 'Maria Souza', '11949000003'),
  ('c4910000-0000-0000-0000-00000000000b', '54900000-0000-0000-0000-00000000000a', null,
   'Joana Lima', '11949000099');
grant usage on schema auth to anon, authenticated;

-- A primeira terça a pelo menos uma semana de hoje.
select (current_date + ((2 - extract(dow from current_date)::int + 7) % 7) + 7) as terca \gset
create or replace function t_em(p_dia date, p_hora text) returns timestamptz language sql as $$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$$;
create or replace function t_hora(p timestamptz) returns text language sql as $$
  select to_char(p at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI')
$$;

-- A recepção monta o pacote: duas terças às 14h, mão e pé (90 minutos).
select set_config('request.jwt.claim.sub', 'b4900000-0000-0000-0000-00000000000b', false);
set role authenticated;
select public.montar_pacote('54920000-0000-0000-0000-0000000000b1', 'c4910000-0000-0000-0000-00000000000a',
  300, 'pix', '94900000-0000-0000-0000-00000000000d',
  jsonb_build_array(
    jsonb_build_object('inicio', t_em(:'terca'::date, '14:00'),
                       'servicos', '["54910000-0000-0000-0000-0000000000a1","54910000-0000-0000-0000-0000000000a2"]'::jsonb),
    jsonb_build_object('inicio', t_em(:'terca'::date + 7, '14:00'),
                       'servicos', '["54910000-0000-0000-0000-0000000000a1","54910000-0000-0000-0000-0000000000a2"]'::jsonb)))
  ->>'pacoteCliente' as pc \gset
reset role;
select a.id as s1 from public.agendamentos a
 where a.pacote_cliente_id = :'pc' order by a.inicio limit 1 \gset
-- A Joana, com a Ju, na mesma terça às 10h (atendimento comum).
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
  values ('a4910000-0000-0000-0000-0000000000f1', '54900000-0000-0000-0000-00000000000a',
          'c4910000-0000-0000-0000-00000000000b', '94900000-0000-0000-0000-00000000000d',
          t_em(:'terca'::date, '10:00'), t_em(:'terca'::date, '10:45'), 'confirmado', 'recepcao', 40)
  ;

-- Chama como a pessoa, e volta.
create or replace function t_remarcar(p_quem uuid, p_ag uuid, p_ini timestamptz,
  p_prof uuid default null, p_encaixe boolean default false) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_quem::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.remarcar_pelo_salao(p_ag, p_ini, p_prof, p_encaixe);
  perform set_config('role', 'postgres', true);
  return r;
end $$;

\echo ''
\echo '1. Quem chama'
select t_verdade('o anon não executa',
  not has_function_privilege('anon', 'public.remarcar_pelo_salao(uuid,timestamptz,uuid,boolean)', 'execute'));
select t_verdade('quem está logado executa (e o banco decide o resto)',
  has_function_privilege('authenticated', 'public.remarcar_pelo_salao(uuid,timestamptz,uuid,boolean)', 'execute'));

\echo ''
\echo '2. A recepção move a sessão do pacote'
select (select count(*) from public.notificacoes where agendamento_id = :'s1' and tipo = 'lembrete'
          and status = 'pendente') as lembretes_antes \gset
begin;
select t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date, '16:00')) as r2 \gset
commit;
select t_verdade('remarcou', (:'r2'::jsonb->>'ok')::boolean);
select t_texto('e diz para quando', (:'r2'::jsonb->>'data') || ' ' || (:'r2'::jsonb->>'hora'),
  to_char(:'terca'::date, 'DD/MM/YYYY') || ' 16:00');
select t_texto('o MESMO horário, das 16:00 às 17:30 (a duração vai junto)',
  (select t_hora(inicio) || ' – ' || to_char(fim at time zone 'America/Sao_Paulo', 'HH24:MI')
     from public.agendamentos where id = :'s1'),
  to_char(:'terca'::date, 'YYYY-MM-DD') || ' 16:00 – 17:30');
select t_verdade('ainda no pacote, confirmado, sem virar encaixe',
  (select pacote_cliente_id = :'pc' and status = 'confirmado' and not encaixe
     from public.agendamentos where id = :'s1'));
select t_igual('com os mesmos dois serviços',
  (select count(*) from public.agendamento_servicos where agendamento_id = :'s1'), 2);
select t_igual('nenhum horário novo: as duas terças do pacote continuam duas',
  (select count(*) from public.agendamentos where pacote_cliente_id = :'pc' and status <> 'cancelado'), 2);
select t_verdade('o lembrete da cliente vai junto, com a hora nova',
  :lembretes_antes = 1 and exists (select 1 from public.notificacoes n
    where n.agendamento_id = :'s1' and n.tipo = 'lembrete' and n.status = 'pendente'
      and n.quando = t_em(:'terca'::date, '16:00') - interval '120 minutes'
      and n.corpo like '%16:00%'));

\echo ''
\echo '3. As regras do pacote'
select t_texto('na quarta, não: o pacote vale só às terças',
  t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date + 1, '14:00'))->>'motivo',
  'O pacote vale só ' || public.dias_por_extenso('{2}') || '.');
select t_verdade('depois da validade, não',
  t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date + 35, '14:00'))->>'motivo'
    like 'Passa da validade do pacote (vence em %');

\echo ''
\echo '4. Choque'
select t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date, '10:00'), null, true) as r4 \gset
select t_verdade('em cima da Joana, não — nem pedindo encaixe — e diz com quem',
  not (:'r4'::jsonb->>'ok')::boolean and not (:'r4'::jsonb->>'encaixavel')::boolean
  and (:'r4'::jsonb->>'motivo') like 'Ju já tem Joana Lima das 10:00%');
select t_texto('e o horário ficou onde estava',
  (select t_hora(inicio) from public.agendamentos where id = :'s1'), to_char(:'terca'::date, 'YYYY-MM-DD') || ' 16:00');

\echo ''
\echo '5. Fora da jornada: só com a confirmação'
select t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date, '20:30')) as r5 \gset
select t_verdade('sem confirmar: não move, e diz que dá para encaixar',
  not (:'r5'::jsonb->>'ok')::boolean and (:'r5'::jsonb->>'encaixavel')::boolean
  and (:'r5'::jsonb->>'motivo') like 'Fora da jornada de Ju%');
begin;
select t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date, '20:30'), null, true) as r5b \gset
commit;
select t_verdade('confirmando: move, e fica como encaixe com o nome de quem remarcou',
  (:'r5b'::jsonb->>'ok')::boolean and (:'r5b'::jsonb->>'encaixe')::boolean
  and (select encaixe and encaixe_por = 'b4900000-0000-0000-0000-00000000000b'
         from public.agendamentos where id = :'s1'));
begin;
select t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date, '15:00')) as r5c \gset
commit;
select t_verdade('de volta para dentro da jornada, deixa de ser encaixe',
  (:'r5c'::jsonb->>'ok')::boolean
  and (select not encaixe and encaixe_por is null from public.agendamentos where id = :'s1'));

\echo ''
\echo '6. Outra profissional: a comissão passa a ser a dela'
begin;
select t_remarcar('b4900000-0000-0000-0000-00000000000b', :'s1', t_em(:'terca'::date, '15:00'),
  '94900000-0000-0000-0000-00000000000e') as r6 \gset
commit;
select t_verdade('agora é da Bia, no mesmo horário',
  (:'r6'::jsonb->>'ok')::boolean
  and (select profissional_id = '94900000-0000-0000-0000-00000000000e' from public.agendamentos where id = :'s1'));
select t_texto('com a comissão da Bia (50%) nos dois serviços',
  (select string_agg(distinct comissao_pct::int::text, ',') from public.agendamento_servicos
    where agendamento_id = :'s1'), '50');

\echo ''
\echo '7. Quem atende remarca o próprio horário, para si'
begin;
select t_remarcar('d4900000-0000-0000-0000-00000000000d', 'a4910000-0000-0000-0000-0000000000f1',
  t_em(:'terca'::date, '11:00')) as r7 \gset
commit;
select t_verdade('a Ju move o horário da Joana, que é dela',
  (:'r7'::jsonb->>'ok')::boolean
  and (select t_hora(inicio) from public.agendamentos where id = 'a4910000-0000-0000-0000-0000000000f1')
      = to_char(:'terca'::date, 'YYYY-MM-DD') || ' 11:00');
select t_texto('mas não passa para a Bia',
  erro_de($$select t_remarcar('d4900000-0000-0000-0000-00000000000d', 'a4910000-0000-0000-0000-0000000000f1',
    now() + interval '9 days', '94900000-0000-0000-0000-00000000000e')$$),
  'Só o balcão e a gestão remarcam o horário de outra pessoa.');
select t_texto('nem mexe no horário da Bia',
  erro_de(format($$select t_remarcar('d4900000-0000-0000-0000-00000000000d', %L, now() + interval '9 days')$$, :'s1')),
  'Só o balcão e a gestão remarcam o horário de outra pessoa.');

\echo ''
\echo '8. O que não se remarca'
select t_texto('para um horário que já passou, não',
  erro_de($$select t_remarcar('b4900000-0000-0000-0000-00000000000b', 'a4910000-0000-0000-0000-0000000000f1',
    now() - interval '1 hour')$$), 'Escolha um horário que ainda vai acontecer.');
update public.agendamentos set status = 'cancelado' where id = 'a4910000-0000-0000-0000-0000000000f1';
select t_texto('o cancelado, não',
  erro_de($$select t_remarcar('b4900000-0000-0000-0000-00000000000b', 'a4910000-0000-0000-0000-0000000000f1',
    now() + interval '9 days')$$), 'Só dá para remarcar um horário pendente ou confirmado.');
select t_texto('a cliente não remarca por aqui (pelo link, sim)',
  erro_de(format($$select t_remarcar('c4900000-0000-0000-0000-00000000000c', %L, now() + interval '9 days')$$, :'s1')),
  'Só o balcão e a gestão remarcam o horário de outra pessoa.');
select set_config('request.jwt.claim.sub', '', false);
