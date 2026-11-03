-- ===========================================================================
-- AgendaPro — a loja e os pacotes no Relatórios (55)
--
-- Na Loja da Ana, nos últimos dez dias: a Maria mandou três pedidos pelo
-- link — um vendido no Pix (2 batons), um cancelado, um ainda esperando. E
-- dois pacotes vendidos (um pago, um a receber), mais um antigo a receber;
-- uma sessão de pacote feita e uma falta.
--
--   1. quem vê: só a gestão; a recepção e o anon, não; datas conferidas;
--   2. a loja: chegaram, vendidos, cancelados, esperando, o valor e o que saiu;
--   3. os pacotes: vendidos e por quanto, recebido, a receber, sessões e faltas.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5500000-0000-0000-0000-00000000000a'),  -- Ana   — dona
  ('b5500000-0000-0000-0000-00000000000b'),  -- Rita  — recepção
  ('c5500000-0000-0000-0000-00000000000c');  -- Maria — cliente
insert into public.perfis (id, nome, telefone) values
  ('a5500000-0000-0000-0000-00000000000a', 'Ana',         '+5511955000001'),
  ('b5500000-0000-0000-0000-00000000000b', 'Rita',        '+5511955000002'),
  ('c5500000-0000-0000-0000-00000000000c', 'Maria Souza', '+5511955000003')
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone;
insert into public.saloes (id, slug, nome, tipo, status, fuso) values
  ('55500000-0000-0000-0000-00000000000a', 'rel-ana', 'Loja da Ana', 'salao', 'ativo', 'America/Sao_Paulo');
-- O dia do salão (o servidor está em UTC: à noite, o dia dele já é amanhã).
select public.hoje_no_salao('55500000-0000-0000-0000-00000000000a') as hoje \gset
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('55500000-0000-0000-0000-00000000000a', 'individual', 'ativa', :'hoje'::date + 20);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a5500000-0000-0000-0000-00000000000a', '55500000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('b5500000-0000-0000-0000-00000000000b', '55500000-0000-0000-0000-00000000000a', 'recepcao', 'ativo');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct) values
  ('95500000-0000-0000-0000-00000000000a', '55500000-0000-0000-0000-00000000000a',
   'a5500000-0000-0000-0000-00000000000a', 'Ana', 0);
insert into public.produtos (id, salao_id, nome, preco, estoque, ativo, venda_online) values
  ('55510000-0000-0000-0000-0000000000b1', '55500000-0000-0000-0000-00000000000a', 'Batom vermelho', 40, 10, true, true),
  ('55510000-0000-0000-0000-0000000000b2', '55500000-0000-0000-0000-00000000000a', 'Creme de mãos', 25, 5, true, true);
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
create or replace function t_pedir(p_itens text) returns jsonb language sql as $$
  select t_como('c5500000-0000-0000-0000-00000000000c', format(
    'select public.fazer_pedido_loja(%L, %L::jsonb)', '55500000-0000-0000-0000-00000000000a', p_itens))
$$;

-- A loja: um vendido (2 batons, no Pix), um cancelado, um esperando.
select t_pedir('[{"id":"55510000-0000-0000-0000-0000000000b1","qtd":2}]') as p1 \gset
select t_pedir('[{"id":"55510000-0000-0000-0000-0000000000b2","qtd":1}]') as p2 \gset
select t_pedir('[{"id":"55510000-0000-0000-0000-0000000000b2","qtd":1}]') as p3 \gset
select t_como('a5500000-0000-0000-0000-00000000000a', format(
  'select public.vender_pedido_loja(%L, %L::jsonb, %L)', :'p1'::jsonb->>'pedido',
  '[{"id":"55510000-0000-0000-0000-0000000000b1","qtd":2}]', 'pix'));
select t_como('a5500000-0000-0000-0000-00000000000a', format(
  'select public.cancelar_pedido_loja(%L)', :'p2'::jsonb->>'pedido'));

-- Os pacotes: dois vendidos agora (um pago, um a receber) e um antigo a receber.
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c5510000-0000-0000-0000-000000000002', '55500000-0000-0000-0000-00000000000a', 'Carla Dias', '11955000006');
insert into public.pacotes (id, salao_id, nome, sessoes, validade_dias, preco)
  values ('55530000-0000-0000-0000-000000000001', '55500000-0000-0000-0000-00000000000a', 'Escova do mês', 4, 60, 200);
insert into public.pacote_clientes (id, pacote_id, cliente_id, sessoes, vence_em, valor, pago_em, criado_em) values
  ('55540000-0000-0000-0000-000000000001', '55530000-0000-0000-0000-000000000001', 'c5510000-0000-0000-0000-000000000002',
   4, :'hoje'::date + 60, 200, now(), now()),
  ('55540000-0000-0000-0000-000000000002', '55530000-0000-0000-0000-000000000001', 'c5510000-0000-0000-0000-000000000002',
   4, :'hoje'::date + 60, 150, null, now()),
  ('55540000-0000-0000-0000-000000000003', '55530000-0000-0000-0000-000000000001', 'c5510000-0000-0000-0000-000000000002',
   4, :'hoje'::date + 20, 200, null, now() - interval '40 days');
-- Uma sessão feita e uma falta (a falta gasta a sessão).
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto, pacote_cliente_id)
values
  ('a5520000-0000-0000-0000-000000000001', '55500000-0000-0000-0000-00000000000a', 'c5510000-0000-0000-0000-000000000002',
   '95500000-0000-0000-0000-00000000000a', now() - interval '3 days', now() - interval '3 days' + interval '45 minutes',
   'concluido', 'recepcao', 0, '55540000-0000-0000-0000-000000000001'),
  ('a5520000-0000-0000-0000-000000000002', '55500000-0000-0000-0000-00000000000a', 'c5510000-0000-0000-0000-000000000002',
   '95500000-0000-0000-0000-00000000000a', now() - interval '2 days', now() - interval '2 days' + interval '45 minutes',
   'faltou', 'recepcao', 0, '55540000-0000-0000-0000-000000000001');

create or replace function t_rel(p_quem uuid, p_de date, p_ate date) returns jsonb language sql as $$
  select t_como(p_quem, format('select public.relatorio_vendas(%L, %L, %L)',
    '55500000-0000-0000-0000-00000000000a', p_de, p_ate))
$$;

\echo ''
\echo '1. Quem vê'
select t_verdade('o anon nem chama',
  not has_function_privilege('anon', 'public.relatorio_vendas(uuid,date,date)', 'execute'));
select t_texto('a recepção não vê (é o dinheiro da casa, como o relatório de sempre)',
  erro_de(format($$select t_rel('b5500000-0000-0000-0000-00000000000b', %L, %L)$$, :'hoje'::date - 10, :'hoje'::date)),
  'Sem permissão neste salão.');
select t_texto('período ao contrário é recusado',
  erro_de(format($$select t_rel('a5500000-0000-0000-0000-00000000000a', %L, %L)$$, :'hoje'::date, :'hoje'::date - 10)),
  'Confira as datas do período.');

select t_rel('a5500000-0000-0000-0000-00000000000a', :'hoje'::date - 10, :'hoje'::date) as r \gset

\echo ''
\echo '2. A loja pelo link'
select t_texto('chegaram 3, vendido 1 (nenhum no crediário), cancelado 1, esperando 1',
  (:'r'::jsonb->'loja'->>'recebidos') || ' ' || (:'r'::jsonb->'loja'->>'vendidos') || ' '
  || (:'r'::jsonb->'loja'->>'noCrediario') || ' ' || (:'r'::jsonb->'loja'->>'cancelados') || ' '
  || (:'r'::jsonb->'loja'->>'esperando'), '3 1 0 1 1');
select t_texto('   rendeu R$ 80 (os 2 batons), e é o que saiu pela loja',
  (:'r'::jsonb->'loja'->>'valor') || ' | ' || (select string_agg((x->>'nome') || ' ' || (x->>'qtd')::numeric::int || ' ' || (x->>'valor'), ', ')
     from jsonb_array_elements(:'r'::jsonb->'loja'->'produtos') x), '80.00 | Batom vermelho 2 80.00');
select t_texto('   fora do período (o mês passado), não conta',
  (select (x->'loja'->>'vendidos') || ' ' || (x->'loja'->>'valor')
     from (select t_rel('a5500000-0000-0000-0000-00000000000a', :'hoje'::date - 60, :'hoje'::date - 30) x) y), '0 0');

\echo ''
\echo '3. Os pacotes'
select t_texto('vendidos 2 no período (o antigo não), por R$ 350; recebido R$ 200',
  (:'r'::jsonb->'pacotes'->>'vendidos') || ' | ' || (:'r'::jsonb->'pacotes'->>'valorVendido') || ' | '
  || (:'r'::jsonb->'pacotes'->>'recebido'), '2 | 350.00 | 200.00');
select t_texto('   a receber hoje: R$ 350 (o de agora e o antigo)', :'r'::jsonb->'pacotes'->>'aReceber', '350.00');
select t_texto('   1 sessão feita e 1 falta', (:'r'::jsonb->'pacotes'->>'sessoesFeitas') || ' ' || (:'r'::jsonb->'pacotes'->>'faltas'), '1 1');
select t_texto('   por pacote: Escova do mês, 2, R$ 350',
  (select string_agg((x->>'nome') || ' ' || (x->>'vendidos') || ' ' || (x->>'valor'), ', ')
     from jsonb_array_elements(:'r'::jsonb->'pacotes'->'porPacote') x), 'Escova do mês 2 350.00');
select set_config('request.jwt.claim.sub', '', false);
