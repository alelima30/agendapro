-- ===========================================================================
-- AgendaPro — o modo suporte (38_suporte.sql)
--
-- A conta da plataforma abre o painel de um salão cliente. O que se confere:
--   1. sem sessão de suporte, ela não grava nada no salão de outra pessoa;
--   2. com a sessão aberta mas a edição fechada, também não;
--   3. com "Liberar edição", grava — e o que mudou fica registrado;
--   4. a liberação vale duas horas, e "Sair" fecha a porta;
--   5. a jornada (que não tem salao_id) passa pela mesma trava;
--   6. o dono, a equipe e a plataforma no salão DELA gravam como sempre;
--   7. suspender e estender teste continuam funcionando sem sessão;
--   8. só a plataforma abre sessão; o dono do salão vê os acessos da casa
--      dele, e o dono de outra casa não.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('5e000000-0000-0000-0000-0000000000ad'),   -- Ale — a plataforma
  ('5e000000-0000-0000-0000-0000000000d0'),   -- Ju  — dona do salão
  ('5e000000-0000-0000-0000-0000000000e0');   -- Zé  — dono de outra casa
insert into public.perfis (id, nome, telefone, super_admin) values
  ('5e000000-0000-0000-0000-0000000000ad', 'Ale (plataforma)', '+5511900009001', true),
  ('5e000000-0000-0000-0000-0000000000d0', 'Ju', '+5511900009002', false),
  ('5e000000-0000-0000-0000-0000000000e0', 'Zé', '+5511900009003', false)
on conflict (id) do update set super_admin = excluded.super_admin;

insert into public.saloes (id, slug, nome, tipo, status) values
  ('5e100000-0000-0000-0000-000000000001', 'salao-suporte', 'Salão Suporte', 'salao', 'ativo'),
  ('5e100000-0000-0000-0000-000000000002', 'casa-do-ze', 'Casa do Zé', 'barbearia', 'ativo'),
  ('5e100000-0000-0000-0000-000000000003', 'salao-da-plataforma', 'Salão da Plataforma', 'salao', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values
  ('5e100000-0000-0000-0000-000000000001', 'time', 'ativa'),
  ('5e100000-0000-0000-0000-000000000002', 'time', 'ativa'),
  ('5e100000-0000-0000-0000-000000000003', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('5e000000-0000-0000-0000-0000000000d0', '5e100000-0000-0000-0000-000000000001', 'dono', 'ativo'),
  ('5e000000-0000-0000-0000-0000000000e0', '5e100000-0000-0000-0000-000000000002', 'dono', 'ativo'),
  ('5e000000-0000-0000-0000-0000000000ad', '5e100000-0000-0000-0000-000000000003', 'dono', 'ativo');
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco, ativo, aceita_online) values
  ('5e200000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-000000000001', 'Corte', 30, 0, 80, true, true),
  ('5e200000-0000-0000-0000-000000000003', '5e100000-0000-0000-0000-000000000003', 'Corte', 30, 0, 50, true, true);
insert into public.profissionais (id, salao_id, nome, ativo, aceita_online) values
  ('5e300000-0000-0000-0000-000000000001', '5e100000-0000-0000-0000-000000000001', 'Ju', true, true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim) values
  ('5e300000-0000-0000-0000-000000000001', 1, '09:00', '18:00');

create or replace function preco_corte() returns numeric language sql stable as $f$
  select preco from public.servicos where id = '5e200000-0000-0000-0000-000000000001'
$f$;

\echo ''
\echo 'A plataforma no salão de outra pessoa'
select set_config('request.jwt.claim.sub', '5e000000-0000-0000-0000-0000000000ad', false);
select t_verdade('1. sem sessão de suporte, ela não muda o preço de um serviço do cliente',
  recusado($$update public.servicos set preco = 1 where id = '5e200000-0000-0000-0000-000000000001'$$));
select t_verdade('   e não cria cliente na ficha dele',
  recusado($$insert into public.clientes (salao_id, nome, telefone) values ('5e100000-0000-0000-0000-000000000001', 'Teste', '11999990000')$$));

select (public.iniciar_suporte('5e100000-0000-0000-0000-000000000001')->>'acesso')::uuid as acesso \gset
select t_verdade('2. com a sessão aberta e a edição fechada, continua só leitura',
  recusado($$update public.servicos set preco = 1 where id = '5e200000-0000-0000-0000-000000000001'$$));
select t_verdade('   e a mensagem é a que a tela mostra',
  (select coalesce((select 'x' from pg_proc where proname = 'tg_suporte' and prosrc like '%Liberar edição%'), '') = 'x'));
select t_igual('   o preço não mudou', preco_corte()::bigint, 80);

select public.liberar_edicao_suporte(:'acesso');
update public.servicos set preco = 85 where id = '5e200000-0000-0000-0000-000000000001';
select t_igual('3. com "Liberar edição", ela muda', preco_corte()::bigint, 85);
select t_verdade('   e fica registrado o antes e o depois, na sessão dela',
  (select count(*) = 1 and bool_and(tabela = 'servicos' and operacao = 'UPDATE'
          and (antes->>'preco')::numeric = 80 and (depois->>'preco')::numeric = 85)
     from public.suporte_alteracoes where acesso_id = :'acesso'));

update public.jornadas set fim = '19:00' where profissional_id = '5e300000-0000-0000-0000-000000000001';
select t_verdade('5. a jornada (sem salao_id) também passa pela trava e é registrada',
  exists (select 1 from public.suporte_alteracoes where acesso_id = :'acesso' and tabela = 'jornadas'));

-- A liberação vale duas horas.
update public.suporte_acessos set edicao_desde = now() - interval '3 hours' where id = :'acesso';
select t_verdade('4. passadas duas horas da liberação, volta a ser só leitura',
  recusado($$update public.servicos set preco = 90 where id = '5e200000-0000-0000-0000-000000000001'$$));
select public.liberar_edicao_suporte(:'acesso');
select public.encerrar_suporte(:'acesso');
select t_verdade('   e "Sair" fecha a porta, mesmo com a edição liberada há pouco',
  recusado($$update public.servicos set preco = 90 where id = '5e200000-0000-0000-0000-000000000001'$$));
select t_verdade('   sessão encerrada não se libera de novo',
  recusado(format('select public.liberar_edicao_suporte(%L)', :'acesso')));

\echo ''
\echo 'O que não muda'
select set_config('request.jwt.claim.sub', '5e000000-0000-0000-0000-0000000000d0', false);
update public.servicos set preco = 95 where id = '5e200000-0000-0000-0000-000000000001';
select t_igual('6. a dona muda o preço do próprio serviço, sem sessão nenhuma', preco_corte()::bigint, 95);
select t_igual('   e nada disso vai para o registro do suporte',
  (select count(*) from public.suporte_alteracoes where (depois->>'preco')::numeric = 95), 0);

select set_config('request.jwt.claim.sub', '5e000000-0000-0000-0000-0000000000ad', false);
update public.servicos set preco = 55 where id = '5e200000-0000-0000-0000-000000000003';
select t_verdade('   a plataforma, no salão em que ELA é dona, grava como qualquer dono',
  (select preco = 55 from public.servicos where id = '5e200000-0000-0000-0000-000000000003'));

select public.definir_status_salao('5e100000-0000-0000-0000-000000000001', 'suspenso');
select t_verdade('7. suspender continua funcionando sem sessão de suporte',
  (select status = 'suspenso' from public.saloes where id = '5e100000-0000-0000-0000-000000000001'));
select public.definir_status_salao('5e100000-0000-0000-0000-000000000001', 'ativo');
select public.estender_teste('5e100000-0000-0000-0000-000000000001', current_date + 10);
select t_verdade('   e estender o teste também: o salão volta a ser teste até a data',
  public.plano_efetivo('5e100000-0000-0000-0000-000000000001') = 'trial'
  and (select trial_ate = current_date + 10 from public.assinaturas where salao_id = '5e100000-0000-0000-0000-000000000001'));
select t_verdade('   (teste com data no passado é recusado)',
  recusado($$select public.estender_teste('5e100000-0000-0000-0000-000000000001', current_date - 1)$$));

\echo ''
\echo 'Quem abre sessão, e quem vê os acessos'
select set_config('request.jwt.claim.sub', '5e000000-0000-0000-0000-0000000000e0', false);
select t_verdade('8. o dono de outra casa não abre sessão de suporte no salão da Ju',
  recusado($$select public.iniciar_suporte('5e100000-0000-0000-0000-000000000001')$$));
select t_verdade('   nem estende teste',
  recusado($$select public.estender_teste('5e100000-0000-0000-0000-000000000002', current_date + 30)$$));
select set_config('request.jwt.claim.sub', '', false);

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '5e000000-0000-0000-0000-0000000000d0';
  do $$ begin perform t_verdade('   a Ju vê que o suporte entrou na casa dela, e o que mudou',
    (select count(*) from public.suporte_acessos) = 1 and (select count(*) from public.suporte_alteracoes) >= 2); end $$;
  do $$ begin perform t_verdade('   e não consegue apagar o registro',
    recusado('delete from public.suporte_alteracoes')
    or (select count(*) from public.suporte_alteracoes) >= 2); end $$;
rollback;
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '5e000000-0000-0000-0000-0000000000e0';
  do $$ begin perform t_igual('   o Zé não vê os acessos da casa da Ju',
    (select count(*) from public.suporte_acessos), 0); end $$;
rollback;
