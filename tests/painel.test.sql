-- ===========================================================================
-- AgendaPro — o painel do dia
--
--   1. Conta o dia do SALÃO, e não o de quem está olhando?
--   2. O faturamento é o das comandas FECHADAS — o mesmo critério do
--      relatório?
--   3. O que está aberto aparece separado, sem somar no faturamento?
--   4. A comparação com ontem é de ontem mesmo?
--   5. A gaveta aparece quando há caixa aberto, e some quando não há?
--   6. Recepção e profissional ficam de fora?
-- ===========================================================================

\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo, fuso) values
  ('e1000000-1111-0000-0000-00000000000a', 'salao-painel', 'Salão Painel',
   'salao', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status) values
  ('e1000000-1111-0000-0000-00000000000a', 'time', 'ativa');

insert into auth.users (id, email) values
  ('e1000000-0000-0000-0000-00000000000d', 'dona-painel@teste.com'),
  ('e1000000-0000-0000-0000-0000000000ce', 'recep-painel@teste.com')
on conflict (id) do nothing;
insert into public.perfis (id, nome, telefone) values
  ('e1000000-0000-0000-0000-00000000000d', 'Dona Painel', '+5511900003001'),
  ('e1000000-0000-0000-0000-0000000000ce', 'Rita Recep',  '+5511900003002')
on conflict (id) do nothing;
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('e1000000-0000-0000-0000-00000000000d',
   'e1000000-1111-0000-0000-00000000000a', 'dono', 'ativo'),
  ('e1000000-0000-0000-0000-0000000000ce',
   'e1000000-1111-0000-0000-00000000000a', 'recepcao', 'ativo');

insert into public.profissionais (id, salao_id, nome, comissao_pct) values
  ('e1000000-5555-0000-0000-00000000000a',
   'e1000000-1111-0000-0000-00000000000a', 'Ana', 40);
insert into public.servicos (id, salao_id, nome, duracao_min, preco, comissao_pct) values
  ('e1000000-6666-0000-0000-00000000000a',
   'e1000000-1111-0000-0000-00000000000a', 'Corte', 60, 100, 40);
insert into public.clientes (id, salao_id, nome, telefone) values
  ('e1000000-7777-0000-0000-00000000000a',
   'e1000000-1111-0000-0000-00000000000a', 'Clara', '5511900003003');

select set_config('request.jwt.claim.sub',
                  'e1000000-0000-0000-0000-00000000000d', false);

/* O dia é fixado com `p_dia` de propósito. Um teste que dependesse de "hoje"
   passaria de manhã e reprovaria à meia-noite — e reprovaria dizendo que o
   faturamento está errado, que é a leitura mais alarmante possível para um
   defeito que é só de fuso horário. */
\set DIA '2026-03-10'

-- Uma comanda FECHADA nesse dia, no fuso do salão: 100 de serviço,
-- 40 de comissão.
insert into public.comandas (id, salao_id, cliente_id, status, fechada_em) values
  ('e1000000-aaaa-0000-0000-00000000000a', 'e1000000-1111-0000-0000-00000000000a',
   'e1000000-7777-0000-0000-00000000000a', 'aberta',
   ('2026-03-10 15:00'::timestamp at time zone 'America/Sao_Paulo'));
insert into public.comanda_itens
  (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('e1000000-aaaa-0000-0000-00000000000a', 'servico',
        'e1000000-6666-0000-0000-00000000000a', 'Corte', 1, 100,
        'e1000000-5555-0000-0000-00000000000a');
insert into public.pagamentos (comanda_id, forma, valor) values
  ('e1000000-aaaa-0000-0000-00000000000a', 'dinheiro', 100);
update public.comandas set status = 'fechada'
 where id = 'e1000000-aaaa-0000-0000-00000000000a';

-- Uma comanda ABERTA, com 60 lançados e nada pago.
insert into public.comandas (id, salao_id, cliente_id, status) values
  ('e1000000-aaaa-0000-0000-00000000000b', 'e1000000-1111-0000-0000-00000000000a',
   'e1000000-7777-0000-0000-00000000000a', 'aberta');
insert into public.comanda_itens
  (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('e1000000-aaaa-0000-0000-00000000000b', 'servico',
        'e1000000-6666-0000-0000-00000000000a', 'Corte', 1, 60,
        'e1000000-5555-0000-0000-00000000000a');

-- E uma fechada ONTEM, de 250.
insert into public.comandas (id, salao_id, cliente_id, status, fechada_em) values
  ('e1000000-aaaa-0000-0000-00000000000c', 'e1000000-1111-0000-0000-00000000000a',
   'e1000000-7777-0000-0000-00000000000a', 'aberta',
   ('2026-03-09 18:00'::timestamp at time zone 'America/Sao_Paulo'));
insert into public.comanda_itens
  (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('e1000000-aaaa-0000-0000-00000000000c', 'servico',
        'e1000000-6666-0000-0000-00000000000a', 'Corte', 1, 250,
        'e1000000-5555-0000-0000-00000000000a');
insert into public.pagamentos (comanda_id, forma, valor) values
  ('e1000000-aaaa-0000-0000-00000000000c', 'dinheiro', 250);
update public.comandas set status = 'fechada'
 where id = 'e1000000-aaaa-0000-0000-00000000000c';

-- A agenda do dia: um concluído, um que faltou, um ainda por vir.
insert into public.agendamentos
  (salao_id, cliente_id, profissional_id, inicio, fim, status)
values
  ('e1000000-1111-0000-0000-00000000000a', 'e1000000-7777-0000-0000-00000000000a',
   'e1000000-5555-0000-0000-00000000000a',
   ('2026-03-10 09:00'::timestamp at time zone 'America/Sao_Paulo'),
   ('2026-03-10 10:00'::timestamp at time zone 'America/Sao_Paulo'), 'concluido'),
  ('e1000000-1111-0000-0000-00000000000a', 'e1000000-7777-0000-0000-00000000000a',
   'e1000000-5555-0000-0000-00000000000a',
   ('2026-03-10 11:00'::timestamp at time zone 'America/Sao_Paulo'),
   ('2026-03-10 12:00'::timestamp at time zone 'America/Sao_Paulo'), 'faltou'),
  ('e1000000-1111-0000-0000-00000000000a', 'e1000000-7777-0000-0000-00000000000a',
   'e1000000-5555-0000-0000-00000000000a',
   ('2026-03-10 16:00'::timestamp at time zone 'America/Sao_Paulo'),
   ('2026-03-10 17:00'::timestamp at time zone 'America/Sao_Paulo'), 'confirmado');

\echo ''
\echo '1) A agenda do dia'

select t_igual('conta os três atendimentos do dia',
  ((public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                       :'DIA'::date)->'agenda'->>'total')::bigint), 3::bigint);

select t_igual('um concluído',
  ((public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                       :'DIA'::date)->'agenda'->>'concluidos')::bigint), 1::bigint);

select t_igual('uma falta',
  ((public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                       :'DIA'::date)->'agenda'->>'faltas')::bigint), 1::bigint);

\echo ''
\echo '2) O dinheiro: fechadas contam, abertas não'

select t_verdade('faturamento do dia = 100, só a fechada',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      :'DIA'::date)->'dinheiro'->>'faturamento')::numeric = 100.00);

select t_verdade('a comissão do dia = 40',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      :'DIA'::date)->'dinheiro'->>'comissoes')::numeric = 40.00);

-- Se a aberta entrasse no faturamento, o dono acharia que fez 160 num dia em
-- que entraram 100 — e fecharia o mês com um número que não existe.
select t_verdade('o que está lançado e não pago aparece à parte (60)',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      :'DIA'::date)->>'aReceber')::numeric = 60.00);

\echo ''
\echo '3) Ontem é ontem'

select t_verdade('ontem = 250',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      :'DIA'::date)->'ontem'->>'faturamento')::numeric = 250.00);

-- E pedindo o painel DE ontem, os papéis se invertem: é a prova de que a
-- janela desliza, e não de que existem duas contas escritas de jeitos
-- diferentes que por acaso deram certo hoje.
select t_verdade('pedindo ontem, o faturamento vira 250',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      '2026-03-09'::date)->'dinheiro'->>'faturamento')::numeric = 250.00);

\echo ''
\echo '4) A gaveta'

select t_verdade('sem caixa aberto, a gaveta vem nula',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      :'DIA'::date)->'caixa') = 'null'::jsonb);

insert into public.caixas (id, salao_id, valor_abertura) values
  ('e1000000-cccc-0000-0000-00000000000a',
   'e1000000-1111-0000-0000-00000000000a', 150);

select t_verdade('com caixa aberto, a gaveta aparece',
  (public.painel_hoje('e1000000-1111-0000-0000-00000000000a',
                      :'DIA'::date)->'caixa'->>'valorAbertura')::numeric = 150.00);

\echo ''
\echo '5) Quem vê o painel'

select set_config('request.jwt.claim.sub',
                  'e1000000-0000-0000-0000-0000000000ce', false);

select t_texto('a recepção não abre o painel do dono',
  erro_de($q$ select public.painel_hoje('e1000000-1111-0000-0000-00000000000a') $q$),
  'Sem permissão neste salão.');

select set_config('request.jwt.claim.sub', '', false);

select t_verdade('e anon muito menos',
  recusado($q$ select public.painel_hoje('e1000000-1111-0000-0000-00000000000a') $q$));
