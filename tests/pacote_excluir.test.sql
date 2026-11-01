-- ===========================================================================
-- AgendaPro — excluir pacote (50_pacote_excluir.sql)
--
-- "Só excluir quando não tiver pessoas nesse pacote."
--
--   1. quem chama: o anon nem chama; a recepção não exclui;
--   2. nunca vendido: apaga, com os serviços dele;
--   3. com cliente dentro: não exclui, e diz quem — nem pela função, nem
--      apagando direto;
--   4. tirada a cliente: sai da lista (arquivado) e o histórico fica;
--   5. vendido e vencido: o mesmo — arquiva, não apaga;
--   6. excluir o salão (a conta) ainda leva tudo junto, em cascata.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5000000-0000-0000-0000-00000000000a'),
  ('b5000000-0000-0000-0000-00000000000b');
insert into public.perfis (id, nome, telefone) values
  ('a5000000-0000-0000-0000-00000000000a', 'Ana',  '+5511950000001'),
  ('b5000000-0000-0000-0000-00000000000b', 'Rita', '+5511950000002')
on conflict (id) do update set nome = excluded.nome;
insert into public.saloes (id, slug, nome, status, fuso) values
  ('55000000-0000-0000-0000-00000000000a', 'pacote-excluir', 'Salão Exclui', 'ativo', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status) values
  ('55000000-0000-0000-0000-00000000000a', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a5000000-0000-0000-0000-00000000000a', '55000000-0000-0000-0000-00000000000a', 'dono'),
  ('b5000000-0000-0000-0000-00000000000b', '55000000-0000-0000-0000-00000000000a', 'recepcao');
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco) values
  ('55100000-0000-0000-0000-0000000000a1', '55000000-0000-0000-0000-00000000000a', 'Mão', 45, 0, 40);
insert into public.pacotes (id, salao_id, nome, preco, sessoes, validade_dias) values
  ('55200000-0000-0000-0000-0000000000b1', '55000000-0000-0000-0000-00000000000a', 'Nunca vendido', 100, 4, 30),
  ('55200000-0000-0000-0000-0000000000b2', '55000000-0000-0000-0000-00000000000a', 'Com cliente',   200, 4, 30),
  ('55200000-0000-0000-0000-0000000000b3', '55000000-0000-0000-0000-00000000000a', 'Vencido',       150, 4, 30);
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('55200000-0000-0000-0000-0000000000b1', '55100000-0000-0000-0000-0000000000a1'),
  ('55200000-0000-0000-0000-0000000000b2', '55100000-0000-0000-0000-0000000000a1'),
  ('55200000-0000-0000-0000-0000000000b3', '55100000-0000-0000-0000-0000000000a1');
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c5100000-0000-0000-0000-00000000000a', '55000000-0000-0000-0000-00000000000a', 'Maria Souza', '11950000003'),
  ('c5100000-0000-0000-0000-00000000000b', '55000000-0000-0000-0000-00000000000a', 'Joana Lima',  '11950000004');
insert into public.pacote_clientes (id, pacote_id, cliente_id, sessoes, vence_em) values
  ('55300000-0000-0000-0000-0000000000c2', '55200000-0000-0000-0000-0000000000b2',
   'c5100000-0000-0000-0000-00000000000a', 4, current_date + 20),
  ('55300000-0000-0000-0000-0000000000c3', '55200000-0000-0000-0000-0000000000b3',
   'c5100000-0000-0000-0000-00000000000b', 4, current_date - 5);
grant usage on schema auth to anon, authenticated;

create or replace function t_excluir(p_quem uuid, p_pac uuid) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_quem::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.excluir_pacote(p_pac);
  perform set_config('role', 'postgres', true);
  return r;
end $$;

\echo ''
\echo '1. Quem chama'
select t_verdade('o anon não executa',
  not has_function_privilege('anon', 'public.excluir_pacote(uuid)', 'execute'));
select t_texto('a recepção não exclui',
  erro_de($$select t_excluir('b5000000-0000-0000-0000-00000000000b', '55200000-0000-0000-0000-0000000000b1')$$),
  'Só o proprietário ou um administrador exclui pacote.');

\echo ''
\echo '2. Nunca vendido: apaga'
select t_texto('apagado', t_excluir('a5000000-0000-0000-0000-00000000000a',
  '55200000-0000-0000-0000-0000000000b1')->>'acao', 'apagado');
select t_verdade('sumiu, com os serviços dele',
  not exists (select 1 from public.pacotes where id = '55200000-0000-0000-0000-0000000000b1')
  and not exists (select 1 from public.pacote_servicos where pacote_id = '55200000-0000-0000-0000-0000000000b1'));

\echo ''
\echo '3. Com cliente dentro: não exclui, e diz quem'
select t_texto('pela função',
  erro_de($$select t_excluir('a5000000-0000-0000-0000-00000000000a', '55200000-0000-0000-0000-0000000000b2')$$),
  'Ainda tem cliente neste pacote (Maria Souza). Tire do pacote primeiro, ou espere vencer.');
select t_texto('nem apagando direto',
  erro_de($$delete from public.pacotes where id = '55200000-0000-0000-0000-0000000000b2'$$),
  'Ainda tem cliente neste pacote (Maria Souza). Tire do pacote primeiro, ou espere vencer.');
select t_verdade('e o pacote continua, ativo, com a cliente',
  (select ativo and arquivado_em is null from public.pacotes where id = '55200000-0000-0000-0000-0000000000b2'));

\echo ''
\echo '4. Tirada a cliente: arquiva, e o histórico fica'
update public.pacote_clientes set cancelado_em = now() where id = '55300000-0000-0000-0000-0000000000c2';
select t_texto('arquivado', t_excluir('a5000000-0000-0000-0000-00000000000a',
  '55200000-0000-0000-0000-0000000000b2')->>'acao', 'arquivado');
select t_verdade('sai da lista (arquivado e desativado), e o vínculo antigo continua',
  (select arquivado_em is not null and not ativo from public.pacotes where id = '55200000-0000-0000-0000-0000000000b2')
  and exists (select 1 from public.pacote_clientes where id = '55300000-0000-0000-0000-0000000000c2'));
select t_verdade('apagar direto o que tem histórico também é recusado',
  erro_de($$delete from public.pacotes where id = '55200000-0000-0000-0000-0000000000b2'$$)
    like 'Este pacote já foi vendido%');

\echo ''
\echo '5. Vendido e vencido: arquiva, não apaga'
select t_texto('arquivado', t_excluir('a5000000-0000-0000-0000-00000000000a',
  '55200000-0000-0000-0000-0000000000b3')->>'acao', 'arquivado');
select t_verdade('e o vínculo vencido continua no histórico',
  exists (select 1 from public.pacote_clientes where id = '55300000-0000-0000-0000-0000000000c3'));

\echo ''
\echo '6. Excluir o salão ainda leva tudo junto'
delete from public.saloes where id = '55000000-0000-0000-0000-00000000000a';
select t_verdade('o salão e os pacotes (com histórico) saíram em cascata',
  not exists (select 1 from public.pacotes where salao_id = '55000000-0000-0000-0000-00000000000a'));
select set_config('request.jwt.claim.sub', '', false);
