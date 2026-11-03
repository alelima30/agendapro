-- ===========================================================================
-- AgendaPro — o sino do painel (54)
--
-- O Salão da Ana: a Ana (dona), a Rita (recepção), a Ju e a Bia (atendem).
--
--   1. quem chama: só a equipe do salão (a cliente e o anon, não);
--   2. sem nada pendente, o sino vem vazio (e a assinatura em dia não avisa);
--   3. os horários a confirmar: o balcão vê todos, quem atende só os dela; o
--      sinal tem item próprio; o pacote a receber não conta;
--   4. pedidos da loja e do restaurante, parcelas vencidas: o balcão vê,
--      quem atende não;
--   5. mensagens que falharam, a franquia e a assinatura: só a gestão;
--   6. resolvido, some: confirmar, vender, receber a parcela;
--   7. os avisos do AgendaPro: só a plataforma publica; a gestão ou a equipe
--      vê, conforme o público; lido, some só para quem leu; arquivado ou
--      vencido, some para todos.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5400000-0000-0000-0000-00000000000a'),  -- Ana   — dona
  ('b5400000-0000-0000-0000-00000000000b'),  -- Rita  — recepção
  ('d5400000-0000-0000-0000-00000000000d'),  -- Ju    — profissional
  ('e5400000-0000-0000-0000-00000000000e'),  -- Bia   — profissional
  ('c5400000-0000-0000-0000-00000000000c'),  -- Maria — cliente
  ('f5400000-0000-0000-0000-00000000000f');  -- Zé    — a plataforma
insert into public.perfis (id, nome, telefone, super_admin) values
  ('a5400000-0000-0000-0000-00000000000a', 'Ana',         '+5511954000001', false),
  ('b5400000-0000-0000-0000-00000000000b', 'Rita',        '+5511954000002', false),
  ('d5400000-0000-0000-0000-00000000000d', 'Ju',          '+5511954000004', false),
  ('e5400000-0000-0000-0000-00000000000e', 'Bia',         '+5511954000005', false),
  ('c5400000-0000-0000-0000-00000000000c', 'Maria Souza', '+5511954000003', false),
  ('f5400000-0000-0000-0000-00000000000f', 'Zé',          '+5511954000009', true)
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone, super_admin = excluded.super_admin;
insert into public.saloes (id, slug, nome, tipo, status, fuso) values
  ('55400000-0000-0000-0000-00000000000a', 'sino-ana', 'Salão da Ana', 'salao', 'ativo', 'America/Sao_Paulo');
-- O dia do salão (o servidor está em UTC: à noite, current_date já é amanhã).
select public.hoje_no_salao('55400000-0000-0000-0000-00000000000a') as hoje \gset
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('55400000-0000-0000-0000-00000000000a', 'time', 'ativa', :'hoje'::date + 20);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a5400000-0000-0000-0000-00000000000a', '55400000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('b5400000-0000-0000-0000-00000000000b', '55400000-0000-0000-0000-00000000000a', 'recepcao', 'ativo'),
  ('d5400000-0000-0000-0000-00000000000d', '55400000-0000-0000-0000-00000000000a', 'profissional', 'ativo'),
  ('e5400000-0000-0000-0000-00000000000e', '55400000-0000-0000-0000-00000000000a', 'profissional', 'ativo');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct) values
  ('95400000-0000-0000-0000-00000000000d', '55400000-0000-0000-0000-00000000000a', 'd5400000-0000-0000-0000-00000000000d', 'Ju', 10),
  ('95400000-0000-0000-0000-00000000000e', '55400000-0000-0000-0000-00000000000a', 'e5400000-0000-0000-0000-00000000000e', 'Bia', 10);
insert into public.clientes (id, salao_id, nome, telefone, perfil_id) values
  ('c5410000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 'Maria Souza', '11954000003',
   'c5400000-0000-0000-0000-00000000000c'),
  ('c5410000-0000-0000-0000-000000000002', '55400000-0000-0000-0000-00000000000a', 'Carla Dias', '11954000006', null);
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
-- O sino de alguém, resumido: "tipo:qtd" em ordem, e quantos avisos.
create or replace function t_sino(p_quem uuid) returns text language sql as $$
  select coalesce((select string_agg((i->>'tipo') || ':' || (i->>'qtd'), ' ' order by i->>'tipo')
                     from jsonb_array_elements(s->'itens') i), '-')
         || ' | avisos ' || jsonb_array_length(s->'avisos')
    from (select t_como(p_quem, 'select public.sino_do_painel(''55400000-0000-0000-0000-00000000000a'')') s) x
$$;
create or replace function t_item(p_quem uuid, p_tipo text) returns jsonb language sql as $$
  select (select i from jsonb_array_elements(s->'itens') i where i->>'tipo' = p_tipo)
    from (select t_como(p_quem, 'select public.sino_do_painel(''55400000-0000-0000-0000-00000000000a'')') s) x
$$;
\set ana  '''a5400000-0000-0000-0000-00000000000a'''
\set rita '''b5400000-0000-0000-0000-00000000000b'''
\set ju   '''d5400000-0000-0000-0000-00000000000d'''
\set bia  '''e5400000-0000-0000-0000-00000000000e'''
\set plat   '''f5400000-0000-0000-0000-00000000000f'''

\echo ''
\echo '1. Quem chama'
select t_verdade('o anon nem chama',
  not has_function_privilege('anon', 'public.sino_do_painel(uuid)', 'execute'));
select t_texto('a cliente do salão não vê o sino dele',
  erro_de($$select t_como('c5400000-0000-0000-0000-00000000000c', 'select public.sino_do_painel(''55400000-0000-0000-0000-00000000000a'')')$$),
  'Só a equipe do salão vê os avisos.');
select t_verdade('as tabelas dos avisos não abrem direto para ninguém',
  not has_table_privilege('authenticated', 'public.avisos_plataforma', 'select')
  and not has_table_privilege('authenticated', 'public.avisos_lidos', 'insert'));

\echo ''
\echo '2. Nada pendente'
select t_texto('o sino da Ana vem vazio (a assinatura vence daqui a 20 dias: não é aviso)',
  t_sino(:ana::uuid), '- | avisos 0');

\echo ''
\echo '3. Horários a confirmar'
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto,
                                 sinal_exigido, sinal_pago, sinal_ate) values
  -- dois da Ju e um da Bia, esperando o "sim"
  ('a5420000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000001',
   '95400000-0000-0000-0000-00000000000d', now() + interval '2 days', now() + interval '2 days 45 minutes', 'pendente', 'online', 40, 0, 0, null),
  ('a5420000-0000-0000-0000-000000000002', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000002',
   '95400000-0000-0000-0000-00000000000d', now() + interval '3 days', now() + interval '3 days 45 minutes', 'pendente', 'online', 40, 0, 0, null),
  ('a5420000-0000-0000-0000-000000000003', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000002',
   '95400000-0000-0000-0000-00000000000e', now() + interval '2 days', now() + interval '2 days 45 minutes', 'pendente', 'online', 40, 0, 0, null),
  -- um da Bia esperando o Pix do sinal
  ('a5420000-0000-0000-0000-000000000004', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000001',
   '95400000-0000-0000-0000-00000000000e', now() + interval '4 days', now() + interval '4 days 45 minutes', 'pendente', 'online', 80,
   20, 0, now() + interval '2 hours'),
  -- um da Ju de ontem (passou: não é mais "a confirmar") e um confirmado
  ('a5420000-0000-0000-0000-000000000005', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000001',
   '95400000-0000-0000-0000-00000000000d', now() - interval '2 days', now() - interval '2 days' + interval '45 minutes', 'pendente', 'online', 40, 0, 0, null),
  ('a5420000-0000-0000-0000-000000000006', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000001',
   '95400000-0000-0000-0000-00000000000d', now() + interval '5 days', now() + interval '5 days 45 minutes', 'confirmado', 'online', 40, 0, 0, null);
-- Uma sessão de pacote a receber (espera o pagamento, não um "sim").
insert into public.pacotes (id, salao_id, nome, sessoes, validade_dias, preco)
  values ('55430000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 'Escova do mês', 4, 60, 200);
insert into public.pacote_clientes (id, pacote_id, cliente_id, sessoes, vence_em, valor)
  values ('55440000-0000-0000-0000-000000000001', '55430000-0000-0000-0000-000000000001',
          'c5410000-0000-0000-0000-000000000002', 4, :'hoje'::date + 60, 200);
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto, pacote_cliente_id)
  values ('a5420000-0000-0000-0000-000000000007', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000002',
          '95400000-0000-0000-0000-00000000000e', now() + interval '6 days', now() + interval '6 days 45 minutes', 'pendente', 'recepcao', 0,
          '55440000-0000-0000-0000-000000000001');
select t_texto('o balcão (Rita): 3 a confirmar e 1 sinal; o de ontem, o confirmado e o pacote a receber não contam',
  t_sino(:rita::uuid), 'a_confirmar:3 sinal:1 | avisos 0');
select t_texto('   a Ana, igual', t_sino(:ana::uuid), 'a_confirmar:3 sinal:1 | avisos 0');
select t_texto('a Ju vê só os dois dela', t_sino(:ju::uuid), 'a_confirmar:2 | avisos 0');
select t_texto('a Bia, o dela e o do sinal, juntos em "a confirmar" (o sinal é do balcão)',
  t_sino(:bia::uuid), 'a_confirmar:2 | avisos 0');

\echo ''
\echo '4. Pedidos e parcelas'
insert into public.pedidos_loja (salao_id, numero, cliente_id, perfil_id, status) values
  ('55400000-0000-0000-0000-00000000000a', 1, 'c5410000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-00000000000c', 'novo'),
  ('55400000-0000-0000-0000-00000000000a', 2, 'c5410000-0000-0000-0000-000000000001', 'c5400000-0000-0000-0000-00000000000c', 'vendido');
insert into public.comandas (id, salao_id, cliente_id) values
  ('c5450000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000002');
insert into public.crediarios (id, salao_id, cliente_id, comanda_id, valor, parcelas) values
  ('c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 'c5410000-0000-0000-0000-000000000002',
   'c5450000-0000-0000-0000-000000000001', 300, 3);
insert into public.crediario_parcelas (id, crediario_id, salao_id, numero, valor, vence_em) values
  ('c5470000-0000-0000-0000-000000000001', 'c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 1, 100, :'hoje'::date - 40),
  ('c5470000-0000-0000-0000-000000000002', 'c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 2, 100, :'hoje'::date - 10),
  ('c5470000-0000-0000-0000-000000000003', 'c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 3, 100, :'hoje'::date + 20);
-- A primeira já foi paga; a segunda, só em parte (R$ 30).
insert into public.crediario_recebimentos (parcela_id, crediario_id, salao_id, valor, forma) values
  ('c5470000-0000-0000-0000-000000000001', 'c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 100, 'pix'),
  ('c5470000-0000-0000-0000-000000000002', 'c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 30, 'pix');
select t_texto('o balcão: 1 pedido da loja (o vendido não), 1 parcela vencida (a paga e a que vem, não)',
  t_sino(:rita::uuid), 'a_confirmar:3 parcelas:1 pedidos_loja:1 sinal:1 | avisos 0');
select t_texto('   com o que falta receber dela: R$ 70', t_item(:rita::uuid, 'parcelas')->>'valor', '70.00');
select t_texto('quem atende não vê pedido nem parcela', t_sino(:ju::uuid), 'a_confirmar:2 | avisos 0');
-- "Pedidos só se o comércio tiver colocado vendas no Meu negócio."
update public.saloes set cfg = coalesce(cfg, '{}'::jsonb) || '{"loja": false}' where id = '55400000-0000-0000-0000-00000000000a';
select t_texto('com Produtos à venda: Não (Meu negócio), o pedido da loja sai do sino',
  t_sino(:rita::uuid), 'a_confirmar:3 parcelas:1 sinal:1 | avisos 0');
update public.saloes set cfg = cfg - 'loja' where id = '55400000-0000-0000-0000-00000000000a';

\echo ''
\echo '5. Mensagens, franquia e assinatura: só a gestão'
-- A franquia de teste: 5 mensagens no mês, 4 já saíram (80%).
update public.planos set recursos = jsonb_set(recursos, '{mensagens_mes}', '5') where codigo = 'time';
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em, criado_em) values
  ('55400000-0000-0000-0000-00000000000a', 'resumo', '5511954000001', now(), 'r1', 'sino-e1', 'enviado', now(), now()),
  ('55400000-0000-0000-0000-00000000000a', 'resumo', '5511954000001', now(), 'r2', 'sino-e2', 'enviado', now(), now()),
  ('55400000-0000-0000-0000-00000000000a', 'resumo', '5511954000001', now(), 'r3', 'sino-e3', 'enviado', now(), now()),
  ('55400000-0000-0000-0000-00000000000a', 'resumo', '5511954000001', now(), 'r4', 'sino-e4', 'enviado', now(), now()),
  -- uma falhou ontem; a outra, há 10 dias (passou da semana: não conta)
  ('55400000-0000-0000-0000-00000000000a', 'resumo', '5511954000001', now(), 'f1', 'sino-f1', 'falhou', null, now() - interval '1 day'),
  ('55400000-0000-0000-0000-00000000000a', 'resumo', '5511954000001', now(), 'f2', 'sino-f2', 'falhou', null, now() - interval '10 days');
select t_texto('a Ana: 1 mensagem que falhou na semana e a franquia em 80%',
  t_sino(:ana::uuid), 'a_confirmar:3 franquia:1 mensagens:1 parcelas:1 pedidos_loja:1 sinal:1 | avisos 0');
select t_texto('   a franquia diz o uso: 4 de 5, 80%',
  (select i->>'usado' || ' de ' || (i->>'teto') || ', ' || (i->>'pct') || '%' from (select t_item(:ana::uuid, 'franquia') i) x), '4 de 5, 80%');
select t_texto('a Rita (recepção) não vê mensagens nem franquia',
  t_sino(:rita::uuid), 'a_confirmar:3 parcelas:1 pedidos_loja:1 sinal:1 | avisos 0');
-- A assinatura em cada situação.
update public.assinaturas set vence_em = :'hoje'::date + 3 where salao_id = '55400000-0000-0000-0000-00000000000a';
select t_texto('ativa no Pix, vence em 3 dias: avisa a gestão',
  (select i->>'situacao' || ' ' || (i->>'dias') from (select t_item(:ana::uuid, 'assinatura') i) x), 'vence 3');
select t_verdade('   e a recepção não vê', t_item(:rita::uuid, 'assinatura') is null);
update public.assinaturas set mp_preapproval = 'pre-teste-sino' where salao_id = '55400000-0000-0000-0000-00000000000a';
select t_verdade('no cartão (renova sozinho), vencer em 3 dias não é aviso', t_item(:ana::uuid, 'assinatura') is null);
update public.assinaturas set status = 'inadimplente' where salao_id = '55400000-0000-0000-0000-00000000000a';
select t_texto('pagamento pendente: avisa', t_item(:ana::uuid, 'assinatura')->>'situacao', 'inadimplente');
update public.assinaturas set status = 'trial', trial_ate = :'hoje'::date + 2, mp_preapproval = null
 where salao_id = '55400000-0000-0000-0000-00000000000a';
select t_texto('teste grátis no fim (2 dias): avisa',
  (select i->>'situacao' || ' ' || (i->>'dias') from (select t_item(:ana::uuid, 'assinatura') i) x), 'teste 2');
update public.assinaturas set status = 'ativa', trial_ate = null, vence_em = :'hoje'::date - 4
 where salao_id = '55400000-0000-0000-0000-00000000000a';
select t_texto('venceu há 4 dias: avisa',
  (select i->>'situacao' || ' ' || (i->>'dias') from (select t_item(:ana::uuid, 'assinatura') i) x), 'venceu 4');
update public.assinaturas set vence_em = :'hoje'::date + 20 where salao_id = '55400000-0000-0000-0000-00000000000a';
update public.planos set recursos = jsonb_set(recursos, '{mensagens_mes}', '1100') where codigo = 'time';
update public.notificacoes set status = 'enviado', enviado_em = now() where chave = 'sino-f1';

\echo ''
\echo '6. Resolvido, some'
update public.agendamentos set status = 'confirmado' where id in ('a5420000-0000-0000-0000-000000000001', 'a5420000-0000-0000-0000-000000000004');
update public.pedidos_loja set status = 'vendido' where salao_id = '55400000-0000-0000-0000-00000000000a' and numero = 1;
insert into public.crediario_recebimentos (parcela_id, crediario_id, salao_id, valor, forma) values
  ('c5470000-0000-0000-0000-000000000002', 'c5460000-0000-0000-0000-000000000001', '55400000-0000-0000-0000-00000000000a', 70, 'dinheiro');
select t_texto('confirmou dois, vendeu o pedido, recebeu a parcela, a franquia voltou, a mensagem saiu: sobram 2 a confirmar',
  t_sino(:ana::uuid), 'a_confirmar:2 | avisos 0');

\echo ''
\echo '7. Os avisos do AgendaPro'
select t_texto('só a plataforma publica',
  erro_de($$select t_como('a5400000-0000-0000-0000-00000000000a', 'select public.publicar_aviso_plataforma(''Oi'', ''Texto do aviso'')')$$),
  'Só a plataforma publica avisos para os salões.');
select t_texto('   título curto demais é recusado',
  erro_de($$select t_como('f5400000-0000-0000-0000-00000000000f', 'select public.publicar_aviso_plataforma(''Oi'', ''Texto do aviso'')')$$),
  'O título precisa ter de 3 a 120 letras.');
select t_como(:plat::uuid, $$select public.publicar_aviso_plataforma('Novidade: o sino', 'Agora os avisos ficam aqui.', 'gestao')$$) as av1 \gset
select t_como(:plat::uuid, $$select public.publicar_aviso_plataforma('Manutenção domingo', 'O sistema para das 2h às 3h.', 'equipe')$$) as av2 \gset
select t_texto('a Ana (gestão) vê os dois, o mais novo primeiro',
  (select string_agg(a->>'titulo', ' / ') from jsonb_array_elements(
    t_como(:ana::uuid, 'select public.sino_do_painel(''55400000-0000-0000-0000-00000000000a'')')->'avisos') a),
  'Manutenção domingo / Novidade: o sino');
select t_texto('a Ju (equipe) vê só o da equipe', t_sino(:ju::uuid), 'a_confirmar:1 | avisos 1');
select t_texto('a Ana marca o da manutenção como lido: sai do sino dela',
  (select t_como(:ana::uuid, format('select public.marcar_aviso_lido(%L)', :'av2'::jsonb->>'id'))->>'ok')
  || ' | ' || t_sino(:ana::uuid), 'true | a_confirmar:2 | avisos 1');
select t_texto('   e continua no da Ju', t_sino(:ju::uuid), 'a_confirmar:1 | avisos 1');
select t_texto('   marcar de novo não quebra',
  t_como(:ana::uuid, format('select public.marcar_aviso_lido(%L)', :'av2'::jsonb->>'id'))->>'ok', 'true');
select t_texto('o admin vê quantos leram', (select a->>'lidos' from jsonb_array_elements(
  t_como(:plat::uuid, 'select public.avisos_plataforma_admin()')) a where a->>'id' = :'av2'::jsonb->>'id'), '1');
select t_texto('   e a dona não lista os avisos do admin',
  erro_de($$select t_como('a5400000-0000-0000-0000-00000000000a', 'select public.avisos_plataforma_admin()')$$),
  'Só a plataforma vê os avisos publicados.');
select t_texto('arquivado: some para todos',
  (select t_como(:plat::uuid, format('select public.arquivar_aviso_plataforma(%L)', :'av1'::jsonb->>'id'))->>'ok')
  || ' | ' || t_sino(:ana::uuid), 'true | a_confirmar:2 | avisos 0');
update public.avisos_plataforma set ate = :'hoje'::date - 1 where id = (:'av2'::jsonb->>'id')::uuid;
select t_texto('passou do dia de saída: some também', t_sino(:ju::uuid), 'a_confirmar:1 | avisos 0');
select t_verdade('   e o admin mostra os dois fora do ar',
  (select bool_and(not (a->>'noAr')::boolean) from jsonb_array_elements(t_como(:plat::uuid, 'select public.avisos_plataforma_admin()')) a));

\echo ''
\echo '8. O aviso para um salão só'
-- "Como envio somente para um usuário?" — a prorrogação da cortesia de um dono.
insert into public.saloes (id, slug, nome, tipo, status, fuso) values
  ('55400000-0000-0000-0000-00000000000b', 'sino-outro', 'Outro Salão', 'salao', 'ativo', 'America/Sao_Paulo');
select t_como(:plat::uuid, $$select public.publicar_aviso_plataforma('Sua cortesia foi prorrogada',
  'Mais 15 dias de plano Essencial.', 'gestao', null, '55400000-0000-0000-0000-00000000000a')$$) as av3 \gset
select t_como(:plat::uuid, $$select public.publicar_aviso_plataforma('Recado do outro salão',
  'Só para o Outro Salão.', 'equipe', null, '55400000-0000-0000-0000-00000000000b')$$) as av4 \gset
select t_texto('a Ana vê o aviso dela (e não o do outro salão)',
  (select string_agg(a->>'titulo', ' / ') from jsonb_array_elements(
    t_como(:ana::uuid, 'select public.sino_do_painel(''55400000-0000-0000-0000-00000000000a'')')->'avisos') a),
  'Sua cortesia foi prorrogada');
select t_texto('   a Ju (equipe) não vê nenhum dos dois: um é da gestão, o outro é de outro salão',
  t_sino(:ju::uuid), 'a_confirmar:1 | avisos 0');
select t_texto('   o admin mostra para qual salão foi',
  (select a->>'salao' from jsonb_array_elements(t_como(:plat::uuid, 'select public.avisos_plataforma_admin()')) a
    where a->>'id' = :'av3'::jsonb->>'id'), 'Salão da Ana');
select t_texto('salão que não existe é recusado',
  erro_de($$select t_como('f5400000-0000-0000-0000-00000000000f', 'select public.publicar_aviso_plataforma(''Aviso teste'', ''Texto do aviso'', ''gestao'', null, ''00000000-0000-0000-0000-000000000000'')')$$),
  'Não achei esse salão.');
