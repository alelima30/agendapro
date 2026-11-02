-- ===========================================================================
-- AgendaPro — o pedido da loja, gravado, e a venda no painel (53)
--
-- A Maria pede dois batons e um creme pelo link da Ana.
--
--   1. sem conta, não pede; com conta e sem ficha, a ficha nasce;
--   2. o pedido: número, itens com o preço do CADASTRO (o que a tela mandou
--      de preço não conta), só o que a loja mostra, duplicado vira um;
--   3. no painel: o balcão vê, quem atende não, a cliente vê os dela;
--   4. vender no Pix: a comanda fecha com a lista conferida, o estoque baixa,
--      o pedido fica vendido — e não se vende duas vezes;
--   5. vender no crediário: as parcelas do 47 e o pedido vendido, juntos;
--      sem CPF na ficha, nem um nem outro;
--   6. cancelar; e o teto de 5 pedidos esperando.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5300000-0000-0000-0000-00000000000a'),  -- Ana   — dona
  ('b5300000-0000-0000-0000-00000000000b'),  -- Rita  — recepção
  ('d5300000-0000-0000-0000-00000000000d'),  -- Ju    — profissional
  ('c5300000-0000-0000-0000-00000000000c');  -- Maria — cliente
insert into public.perfis (id, nome, telefone) values
  ('a5300000-0000-0000-0000-00000000000a', 'Ana',          '+5511953000001'),
  ('b5300000-0000-0000-0000-00000000000b', 'Rita',         '+5511953000002'),
  ('d5300000-0000-0000-0000-00000000000d', 'Ju',           '+5511953000004'),
  ('c5300000-0000-0000-0000-00000000000c', 'Maria Souza',  '+5511953000003')
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone;
insert into public.saloes (id, slug, nome, tipo, status, fuso) values
  ('55300000-0000-0000-0000-00000000000a', 'loja-ana', 'Loja da Ana', 'salao', 'ativo', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('55300000-0000-0000-0000-00000000000a', 'individual', 'ativa', current_date + 20);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a5300000-0000-0000-0000-00000000000a', '55300000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('b5300000-0000-0000-0000-00000000000b', '55300000-0000-0000-0000-00000000000a', 'recepcao', 'ativo'),
  ('d5300000-0000-0000-0000-00000000000d', '55300000-0000-0000-0000-00000000000a', 'profissional', 'ativo');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct) values
  ('95300000-0000-0000-0000-00000000000d', '55300000-0000-0000-0000-00000000000a',
   'd5300000-0000-0000-0000-00000000000d', 'Ju', 10);
insert into public.produtos (id, salao_id, nome, preco, estoque, ativo, venda_online) values
  ('55310000-0000-0000-0000-0000000000b1', '55300000-0000-0000-0000-00000000000a', 'Batom vermelho', 40, 10, true, true),
  ('55310000-0000-0000-0000-0000000000b2', '55300000-0000-0000-0000-00000000000a', 'Creme de mãos', 25, 5, true, true),
  ('55310000-0000-0000-0000-0000000000b3', '55300000-0000-0000-0000-00000000000a', 'Só no balcão', 99, 3, true, false);
update public.adicionais set ativo = true where codigo = 'crediario';
insert into public.salao_adicionais (salao_id, adicional, status, ativo_desde)
  values ('55300000-0000-0000-0000-00000000000a', 'crediario', 'ativo', now());
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
  select t_como('c5300000-0000-0000-0000-00000000000c', format(
    'select public.fazer_pedido_loja(%L, %L::jsonb, %L)', '55300000-0000-0000-0000-00000000000a', p_itens, 'BEMVINDA'))
$$;

\echo ''
\echo '1. Quem pede'
select t_verdade('o anon nem chama',
  not has_function_privilege('anon', 'public.fazer_pedido_loja(uuid,jsonb,text,uuid)', 'execute'));
select t_texto('sem login, pede o cadastro',
  erro_de($$select t_como(null, 'select public.fazer_pedido_loja(''55300000-0000-0000-0000-00000000000a'', ''[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]'')')$$),
  'Faça seu cadastro (ou entre) para enviar o pedido.');
select t_igual('a Maria ainda não tem ficha na Loja da Ana',
  (select count(*) from public.clientes where salao_id = '55300000-0000-0000-0000-00000000000a'), 0);

\echo ''
\echo '2. O pedido'
-- Dois batons (em duas linhas), um creme, o produto só do balcão, e um preço
-- de R$ 0,01 que a tela "mandou".
select t_pedir('[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1,"preco":0.01},
                 {"id":"55310000-0000-0000-0000-0000000000b1","qtd":1},
                 {"id":"55310000-0000-0000-0000-0000000000b2","qtd":1},
                 {"id":"55310000-0000-0000-0000-0000000000b3","qtd":1}]') as p1 \gset
select t_texto('o pedido nº 1, com o total do cadastro: 2 × R$ 40 + R$ 25',
  (:'p1'::jsonb->>'numero') || ' | ' || (:'p1'::jsonb->>'total'), '1 | 105.00');
select t_texto('   os itens: o batom numa linha só (2), o creme; o do balcão não entra',
  (select string_agg(descricao || ' ' || qtd::int || ' × ' || preco_unit, ', ' order by descricao)
     from public.pedido_loja_itens where pedido_id = (:'p1'::jsonb->>'pedido')::uuid),
  'Batom vermelho 2 × 40.00, Creme de mãos 1 × 25.00');
select t_texto('   a ficha nasceu, ligada à conta, e o pedido é dela (com o cupom anotado)',
  (select c.nome || ' | ' || (c.perfil_id = 'c5300000-0000-0000-0000-00000000000c') || ' | ' || p.cupom || ' | ' || p.status
     from public.pedidos_loja p join public.clientes c on c.id = p.cliente_id
    where p.id = (:'p1'::jsonb->>'pedido')::uuid), 'Maria Souza | true | BEMVINDA | novo');
select t_pedir('[{"id":"55310000-0000-0000-0000-0000000000b2","qtd":2}]') as p2 \gset
select t_texto('o seguinte é o nº 2, na mesma ficha',
  (:'p2'::jsonb->>'numero') || ' | ' || (select count(distinct cliente_id) from public.pedidos_loja
    where salao_id = '55300000-0000-0000-0000-00000000000a'), '2 | 1');
-- Corrigiu e mandou de novo, com o pedido 2: o MESMO pedido, com os itens novos.
select t_como('c5300000-0000-0000-0000-00000000000c', format(
  'select public.fazer_pedido_loja(%L, %L::jsonb, null, %L)', '55300000-0000-0000-0000-00000000000a',
  '[{"id":"55310000-0000-0000-0000-0000000000b2","qtd":2},{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]',
  :'p2'::jsonb->>'pedido')) as p2b \gset
select t_texto('mandou de novo, corrigido: o mesmo nº 2, atualizado, sem pedido novo',
  (:'p2b'::jsonb->>'numero') || ' | ' || (:'p2b'::jsonb->>'atualizado') || ' | ' || (:'p2b'::jsonb->>'total')
    || ' | ' || (select count(*) from public.pedidos_loja where salao_id = '55300000-0000-0000-0000-00000000000a'),
  '2 | true | 90.00 | 2');
-- E volta ao que era (só os 2 cremes), para o resto do teste.
select t_como('c5300000-0000-0000-0000-00000000000c', format(
  'select public.fazer_pedido_loja(%L, %L::jsonb, null, %L)', '55300000-0000-0000-0000-00000000000a',
  '[{"id":"55310000-0000-0000-0000-0000000000b2","qtd":2}]', :'p2'::jsonb->>'pedido'));
select t_texto('só produto que a loja não mostra: recusa',
  erro_de($$select t_pedir('[{"id":"55310000-0000-0000-0000-0000000000b3","qtd":1}]')$$),
  'Estes produtos não estão mais na loja. Atualize a página.');

\echo ''
\echo '3. Quem vê'
select t_igual('o balcão vê os dois pedidos',
  jsonb_array_length(t_como('b5300000-0000-0000-0000-00000000000b',
    $$select public.pedidos_loja_painel('55300000-0000-0000-0000-00000000000a')$$)), 2);
select t_verdade('quem atende não vê a lista',
  recusado($$select t_como('d5300000-0000-0000-0000-00000000000d', 'select public.pedidos_loja_painel(''55300000-0000-0000-0000-00000000000a'')')$$));
select t_igual('a cliente lê os pedidos dela pela tabela',
  (t_como('c5300000-0000-0000-0000-00000000000c',
    $$select to_jsonb(count(*)) from public.pedidos_loja$$))::int, 2);
select t_verdade('ninguém escreve direto na tabela',
  recusado($$select t_como('a5300000-0000-0000-0000-00000000000a', 'insert into public.pedidos_loja (salao_id, numero, cliente_id) select salao_id, 99, cliente_id from public.pedidos_loja limit 1 returning to_jsonb(id)')$$));

\echo ''
\echo '4. Vender no Pix'
-- A Rita conferiu: só tinha um batom. Vende 1 batom + 1 creme, no Pix.
select t_como('b5300000-0000-0000-0000-00000000000b', format(
  'select public.vender_pedido_loja(%L, %L::jsonb, %L, 0, %L)', :'p1'::jsonb->>'pedido',
  '[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1},{"id":"55310000-0000-0000-0000-0000000000b2","qtd":1}]',
  'pix', '95300000-0000-0000-0000-00000000000d')) as v1 \gset
select t_texto('a venda: a comanda fechada, R$ 65, no Pix, no nome da Maria',
  (select c.status || ' | ' || t.total || ' | ' || (select string_agg(forma || ' ' || valor, ',') from public.pagamentos where comanda_id = c.id)
          || ' | ' || cl.nome
     from public.comandas c join public.comandas_totais t on t.id = c.id join public.clientes cl on cl.id = c.cliente_id
    where c.id = (:'v1'::jsonb->>'comanda')::uuid), 'fechada | 65.00 | pix 65.00 | Maria Souza');
select t_texto('   o estoque baixou o que foi vendido (9 batons, 4 cremes)',
  (select string_agg(nome || ' ' || estoque::int, ', ' order by nome) from public.produtos
    where id in ('55310000-0000-0000-0000-0000000000b1', '55310000-0000-0000-0000-0000000000b2')),
  'Batom vermelho 9, Creme de mãos 4');
select t_texto('   e o pedido ficou vendido, ligado à comanda',
  (select status || ' | ' || (comanda_id = (:'v1'::jsonb->>'comanda')::uuid) from public.pedidos_loja
    where id = (:'p1'::jsonb->>'pedido')::uuid), 'vendido | true');
-- O comando é montado por fora: o id do pedido entra já com as aspas certas.
create or replace function t_cmd(p_quem uuid, p_sql text) returns text language sql as $$
  select format('select t_como(%L, %L)', p_quem, p_sql)
$$;
select t_texto('não se vende duas vezes',
  erro_de(t_cmd('b5300000-0000-0000-0000-00000000000b', format(
    'select public.vender_pedido_loja(%L, %L::jsonb, %L)', :'p1'::jsonb->>'pedido',
    '[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]', 'pix'))), 'Este pedido já foi vendido.');
select t_como('c5300000-0000-0000-0000-00000000000c', format(
  'select public.fazer_pedido_loja(%L, %L::jsonb, null, %L)', '55300000-0000-0000-0000-00000000000a',
  '[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]', :'p1'::jsonb->>'pedido')) as p1b \gset
select t_texto('mandou de novo o pedido que o salão já vendeu: nasce outro (nº 3), e o vendido não muda',
  (:'p1b'::jsonb->>'numero') || ' | ' || (:'p1b'::jsonb->>'atualizado') || ' | '
    || (select count(*) from public.pedido_loja_itens where pedido_id = (:'p1'::jsonb->>'pedido')::uuid),
  '3 | false | 2');
select t_como('a5300000-0000-0000-0000-00000000000a', format(
  'select public.cancelar_pedido_loja(%L)', :'p1b'::jsonb->>'pedido'));
select t_texto('quem atende não vende',
  erro_de(t_cmd('d5300000-0000-0000-0000-00000000000d', format(
    'select public.vender_pedido_loja(%L, %L::jsonb, %L)', :'p2'::jsonb->>'pedido',
    '[{"id":"55310000-0000-0000-0000-0000000000b2","qtd":1}]', 'pix'))), 'Só o balcão e a gestão vendem.');

\echo ''
\echo '5. Vender no crediário'
select t_texto('sem CPF na ficha: o crediário recusa, e o pedido continua esperando',
  erro_de(t_cmd('b5300000-0000-0000-0000-00000000000b', format(
    'select public.vender_pedido_no_crediario(%L, %L::jsonb, null, 0, 0, null, 2, %L)', :'p2'::jsonb->>'pedido',
    '[{"tipo":"produto","id":"55310000-0000-0000-0000-0000000000b2","qtd":2}]', current_date + 10))),
  'Para vender no crediário, a ficha da cliente precisa de um CPF válido.');
select t_texto('   (esperando)', (select status from public.pedidos_loja where id = (:'p2'::jsonb->>'pedido')::uuid), 'novo');
update public.clientes set cpf = '52998224725' where salao_id = '55300000-0000-0000-0000-00000000000a';
select t_como('b5300000-0000-0000-0000-00000000000b', format(
  'select public.vender_pedido_no_crediario(%L, %L::jsonb, null, 0, 0, null, 2, %L)', :'p2'::jsonb->>'pedido',
  '[{"tipo":"produto","id":"55310000-0000-0000-0000-0000000000b2","qtd":2}]', current_date + 10)) as v2 \gset
select t_texto('com o CPF: 2 cremes em 2x de R$ 25, e o pedido vendido, ligado ao crediário',
  (select cr.valor || ' em ' || cr.parcelas || 'x | ' || p.status || ' | ' || (p.crediario_id = cr.id)
     from public.crediarios cr join public.pedidos_loja p on p.id = (:'p2'::jsonb->>'pedido')::uuid
    where cr.id = (:'v2'::jsonb->>'crediario')::uuid), '50.00 em 2x | vendido | true');

\echo ''
\echo '6. Cancelar, e o teto'
select t_pedir('[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]') as p3 \gset
select t_como('a5300000-0000-0000-0000-00000000000a', format(
  'select public.cancelar_pedido_loja(%L, %L)', :'p3'::jsonb->>'pedido', 'acabou o batom'));
select t_texto('cancelado, com o motivo, e o estoque não mexe',
  (select status || ' | ' || cancelado_motivo from public.pedidos_loja where id = (:'p3'::jsonb->>'pedido')::uuid)
    || ' | ' || (select estoque::int from public.produtos where id = '55310000-0000-0000-0000-0000000000b1'),
  'cancelado | acabou o batom | 9');
select t_pedir('[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]') from generate_series(1, 5);
select t_texto('com 5 esperando, o sexto espera a conversa do WhatsApp',
  erro_de($$select t_pedir('[{"id":"55310000-0000-0000-0000-0000000000b1","qtd":1}]')$$),
  'Você já tem pedidos esperando o salão. Aguarde a resposta pelo WhatsApp.');
select set_config('request.jwt.claim.sub', '', false);
