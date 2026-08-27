-- ===========================================================================
-- AgendaPro — a comissão é do banco, não do navegador
--
-- As perguntas que este arquivo responde são as que, erradas, tiram dinheiro
-- do salão ou do bolso de quem atende:
--
--   0. O defeito original volta se a trava sair?
--   1. O que o navegador manda na taxa é ignorado?
--   2. A escada respeita par > catálogo > pessoa > zero?
--   3. Um degrau que diz ZERO ganha do degrau de baixo?
--   4. Comissão fixa multiplica pela quantidade?
--   5. Sobre líquido, o desconto da comanda entra rateado?
--   6. O acréscimo fica FORA da comissão?
--   7. Mudar o cadastro amanhã mexe na comissão de ontem?
--   8. A data de corte segura a regra nova?
-- ===========================================================================

\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo) values
  ('c0000000-1111-0000-0000-00000000000a', 'salao-comissao', 'Salão Comissão', 'salao');
insert into public.assinaturas (salao_id, plano, status) values
  ('c0000000-1111-0000-0000-00000000000a', 'time', 'ativa');

insert into public.profissionais (id, salao_id, nome, comissao_pct) values
  ('c0000000-5555-0000-0000-00000000000a', 'c0000000-1111-0000-0000-00000000000a', 'Ana', 40),
  ('c0000000-5555-0000-0000-00000000000b', 'c0000000-1111-0000-0000-00000000000a', 'Bia', 30);

-- Um serviço que NÃO diz nada: herda de quem executou.
insert into public.servicos (id, salao_id, nome, duracao_min, preco) values
  ('c0000000-6666-0000-0000-00000000000a', 'c0000000-1111-0000-0000-00000000000a',
   'Corte', 60, 100);
-- Um serviço que diz 50%: ganha do profissional.
insert into public.servicos (id, salao_id, nome, duracao_min, preco, comissao_pct) values
  ('c0000000-6666-0000-0000-00000000000b', 'c0000000-1111-0000-0000-00000000000a',
   'Escova', 60, 200, 50);
-- Um serviço que diz ZERO de propósito.
insert into public.servicos (id, salao_id, nome, duracao_min, preco, comissao_pct) values
  ('c0000000-6666-0000-0000-00000000000c', 'c0000000-1111-0000-0000-00000000000a',
   'Cortesia da casa', 30, 50, 0);

insert into public.clientes (id, salao_id, nome, telefone) values
  ('c0000000-7777-0000-0000-00000000000a', 'c0000000-1111-0000-0000-00000000000a',
   'Clara', '5511900001001');

-- Uma comanda de trabalho, aberta.
insert into public.comandas (id, salao_id, cliente_id, status) values
  ('c0000000-aaaa-0000-0000-00000000000a', 'c0000000-1111-0000-0000-00000000000a',
   'c0000000-7777-0000-0000-00000000000a', 'aberta');

\echo ''
\echo '0) SEM A TRAVA, o defeito original volta'

-- Desliga o gatilho e refaz exatamente a medição que motivou este módulo:
-- serviço de 50%, navegador dizendo 100%, banco aceitando.
alter table public.comanda_itens disable trigger tg_item_comissao;

insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit,
   profissional_id, comissao_pct)
values ('c0000000-bbbb-0000-0000-000000000001',
        'c0000000-aaaa-0000-0000-00000000000a', 'servico',
        'c0000000-6666-0000-0000-00000000000b', 'Escova', 1, 200,
        'c0000000-5555-0000-0000-00000000000a', 100);

select t_verdade('sem a trava, a taxa do navegador passa (é o defeito)',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000001') = 100);

delete from public.comanda_itens where id = 'c0000000-bbbb-0000-0000-000000000001';
alter table public.comanda_itens enable trigger tg_item_comissao;

\echo ''
\echo '1) COM a trava, o que o navegador manda é ignorado'

insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit,
   profissional_id, comissao_pct)
values ('c0000000-bbbb-0000-0000-000000000002',
        'c0000000-aaaa-0000-0000-00000000000a', 'servico',
        'c0000000-6666-0000-0000-00000000000b', 'Escova', 1, 200,
        'c0000000-5555-0000-0000-00000000000a', 100);

select t_verdade('a taxa gravada é a do cadastro (50), não a do navegador (100)',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000002') = 50);

select t_verdade('e o valor sai de 50% de 200 = 100',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000002') = 100.00);

-- Mandar zero também é mandar: não dá para zerar a comissão de alguém pela
-- tela. Este é o lado do defeito que rouba de quem atende, não do salão.
insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit,
   profissional_id, comissao_pct)
values ('c0000000-bbbb-0000-0000-000000000003',
        'c0000000-aaaa-0000-0000-00000000000a', 'servico',
        'c0000000-6666-0000-0000-00000000000b', 'Escova', 1, 200,
        'c0000000-5555-0000-0000-00000000000a', 0);

select t_verdade('mandar 0 também é ignorado: continua 50',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000003') = 50);

delete from public.comanda_itens
 where id in ('c0000000-bbbb-0000-0000-000000000002',
              'c0000000-bbbb-0000-0000-000000000003');

\echo ''
\echo '2) A escada: par > catálogo > pessoa > zero'

-- Sem par cadastrado, o serviço "Corte" não diz nada: herda da Ana (40%).
insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('c0000000-bbbb-0000-0000-000000000010',
        'c0000000-aaaa-0000-0000-00000000000a', 'servico',
        'c0000000-6666-0000-0000-00000000000a', 'Corte', 1, 100,
        'c0000000-5555-0000-0000-00000000000a');

select t_igual('serviço calado herda a pessoa (Ana, 40%)',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000010')::bigint, 40::bigint);

-- A mesma linha, com a Bia (30%), prova que é da PESSOA e não fixo.
update public.comanda_itens
   set profissional_id = 'c0000000-5555-0000-0000-00000000000b'
 where id = 'c0000000-bbbb-0000-0000-000000000010';

select t_igual('trocar quem executou reabre a taxa (Bia, 30%)',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000010')::bigint, 30::bigint);

-- Agora o par fala mais alto que os dois.
insert into public.servicos_profissionais
  (servico_id, profissional_id, comissao_pct) values
  ('c0000000-6666-0000-0000-00000000000a',
   'c0000000-5555-0000-0000-00000000000b', 70);

update public.comanda_itens
   set profissional_id = 'c0000000-5555-0000-0000-00000000000a'
 where id = 'c0000000-bbbb-0000-0000-000000000010';
update public.comanda_itens
   set profissional_id = 'c0000000-5555-0000-0000-00000000000b'
 where id = 'c0000000-bbbb-0000-0000-000000000010';

select t_igual('o par ganha do serviço e da pessoa (70%)',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000010')::bigint, 70::bigint);

delete from public.comanda_itens
 where id = 'c0000000-bbbb-0000-0000-000000000010';

-- ⚠ Desfaz o par, senão ele contamina as seções seguintes.
--
-- Não é limpeza cosmética: sem esta linha a seção 4 pedia "10% de 200 + 2x12
-- = 44" e recebia 140 — porque o par (Corte, Bia) continuava cadastrado em
-- 70% e, corretamente, ganhava do serviço. O teste reprovou por sujeira que
-- ele mesmo deixou, e a escada estava certa.
delete from public.servicos_profissionais
 where servico_id = 'c0000000-6666-0000-0000-00000000000a';

\echo ''
\echo '3) Um degrau que diz ZERO ganha do degrau de baixo'

-- "A Ana ganha 40% em tudo, MENOS na cortesia da casa." Se zero fosse lido
-- como "não disse nada", a Ana receberia 40% de um serviço que o salão dá
-- de graça — e ninguém perceberia, porque o item some no meio da comanda.
insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('c0000000-bbbb-0000-0000-000000000020',
        'c0000000-aaaa-0000-0000-00000000000a', 'servico',
        'c0000000-6666-0000-0000-00000000000c', 'Cortesia da casa', 1, 50,
        'c0000000-5555-0000-0000-00000000000a');

select t_verdade('serviço com 0% zera, mesmo com a pessoa em 40%',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000020') = 0);

delete from public.comanda_itens
 where id = 'c0000000-bbbb-0000-0000-000000000020';

\echo ''
\echo '4) Comissão fixa, e fixa junto com percentual'

update public.servicos set comissao_pct = null, comissao_fixa = 12
 where id = 'c0000000-6666-0000-0000-00000000000a';

insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('c0000000-bbbb-0000-0000-000000000030',
        'c0000000-aaaa-0000-0000-00000000000a', 'servico',
        'c0000000-6666-0000-0000-00000000000a', 'Corte', 3, 100,
        'c0000000-5555-0000-0000-00000000000a');

select t_verdade('fixa multiplica pela quantidade: 3 x 12 = 36',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000030') = 36.00);

select t_verdade('e a pct fica zerada, porque o degrau que falou foi o fixo',
  (select comissao_pct from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000030') = 0);

-- Os dois no mesmo degrau: R$ 12 por unidade MAIS 10% do preço.
update public.servicos set comissao_pct = 10, comissao_fixa = 12
 where id = 'c0000000-6666-0000-0000-00000000000a';
update public.comanda_itens set qtd = 2
 where id = 'c0000000-bbbb-0000-0000-000000000030';
-- A taxa é congelada: mexer na quantidade NÃO reabre o cadastro.
select t_verdade('mexer na qtd não reabre a taxa (ainda 0% + 12 fixos)',
  (select comissao_pct  from public.comanda_itens
    where id = 'c0000000-bbbb-0000-0000-000000000030') = 0
  and (select comissao_fixa from public.comanda_itens
        where id = 'c0000000-bbbb-0000-0000-000000000030') = 12);

select t_verdade('e o valor acompanha a qtd nova: 2 x 12 = 24',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000030') = 24.00);

-- Reabrindo de propósito (trocando quem executou), o degrau novo entra
-- inteiro: 10% de 200 = 20, mais 2 x 12 = 24, total 44.
update public.comanda_itens
   set profissional_id = 'c0000000-5555-0000-0000-00000000000b'
 where id = 'c0000000-bbbb-0000-0000-000000000030';

select t_verdade('reabrindo, pct e fixa vêm juntas: 10% de 200 + 2x12 = 44',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000030') = 44.00);

delete from public.comanda_itens
 where id = 'c0000000-bbbb-0000-0000-000000000030';
update public.servicos set comissao_pct = null, comissao_fixa = null
 where id = 'c0000000-6666-0000-0000-00000000000a';

\echo ''
\echo '5) Sobre o líquido, o desconto entra rateado'

-- A comanda desta seção nasce com a regra 'liquido' congelada.
update public.saloes
   set comissao_sobre = 'liquido', comissao_regra_desde = current_date - 30
 where id = 'c0000000-1111-0000-0000-00000000000a';

insert into public.comandas (id, salao_id, cliente_id, status) values
  ('c0000000-aaaa-0000-0000-00000000000b', 'c0000000-1111-0000-0000-00000000000a',
   'c0000000-7777-0000-0000-00000000000a', 'aberta');

select t_texto('a comanda nasceu com a regra congelada',
  (select comissao_sobre from public.comandas
    where id = 'c0000000-aaaa-0000-0000-00000000000b'), 'liquido');

-- Dois itens: 100 (Ana, 40%) e 300 (Bia, 30%). Subtotal 400.
insert into public.comanda_itens
  (id, comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('c0000000-bbbb-0000-0000-000000000040',
        'c0000000-aaaa-0000-0000-00000000000b', 'servico',
        'c0000000-6666-0000-0000-00000000000a', 'Corte', 1, 100,
        'c0000000-5555-0000-0000-00000000000a'),
       ('c0000000-bbbb-0000-0000-000000000041',
        'c0000000-aaaa-0000-0000-00000000000b', 'servico',
        'c0000000-6666-0000-0000-00000000000a', 'Corte longo', 1, 300,
        'c0000000-5555-0000-0000-00000000000b');

-- Sem desconto ainda: bruto e líquido dão o mesmo.
select t_verdade('sem desconto, o líquido é igual ao bruto (40 + 90 = 130)',
  (select round(sum(comissao_valor), 2) from public.comanda_itens_calculados
    where comanda_id = 'c0000000-aaaa-0000-0000-00000000000b') = 130.00);

-- Desconto de 40 sobre 400 = 10%. Cada item perde 10% da sua base.
update public.comandas set desconto = 40
 where id = 'c0000000-aaaa-0000-0000-00000000000b';

select t_verdade('o item de 100 vira base 90, e 40% dele = 36',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000040') = 36.00);

select t_verdade('o item de 300 vira base 270, e 30% dele = 81',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000041') = 81.00);

-- E o mesmo cenário no BRUTO tem que voltar a dar 130: é a prova de que a
-- regra é lida da comanda, e não do salão no momento da consulta.
update public.comandas set comissao_sobre = 'bruto'
 where id = 'c0000000-aaaa-0000-0000-00000000000b';

select t_verdade('no bruto, o desconto não toca na comissão (130)',
  (select round(sum(comissao_valor), 2) from public.comanda_itens_calculados
    where comanda_id = 'c0000000-aaaa-0000-0000-00000000000b') = 130.00);

update public.comandas set comissao_sobre = 'liquido'
 where id = 'c0000000-aaaa-0000-0000-00000000000b';

\echo ''
\echo '6) O acréscimo fica FORA da comissão'

-- Taxa de domingo é do salão. Se entrasse na base, quem atende ganharia
-- comissão sobre uma cobrança que não é serviço de ninguém.
update public.comandas set acrescimo = 100
 where id = 'c0000000-aaaa-0000-0000-00000000000b';

select t_verdade('acréscimo de 100 não muda a comissão (36 + 81 = 117)',
  (select round(sum(comissao_valor), 2) from public.comanda_itens_calculados
    where comanda_id = 'c0000000-aaaa-0000-0000-00000000000b') = 117.00);

select t_verdade('mas ele entra no total a pagar (400 - 40 + 100 = 460)',
  (select total from public.comandas_totais
    where id = 'c0000000-aaaa-0000-0000-00000000000b') = 460.00);

\echo ''
\echo '7) Mudar o cadastro amanhã NÃO mexe na comissão de ontem'

-- É o motivo de a taxa ser congelada no item em vez de derivada do cadastro.
-- Sem isso, um reajuste de comissão em dezembro reescreveria o fechamento
-- de março, e o relatório de um mês conferido mudaria de valor sozinho.
update public.profissionais set comissao_pct = 90
 where id in ('c0000000-5555-0000-0000-00000000000a',
              'c0000000-5555-0000-0000-00000000000b');

select t_verdade('a comissão dos itens já lançados não se mexeu (117)',
  (select round(sum(comissao_valor), 2) from public.comanda_itens_calculados
    where comanda_id = 'c0000000-aaaa-0000-0000-00000000000b') = 117.00);

update public.profissionais set comissao_pct = 40
 where id = 'c0000000-5555-0000-0000-00000000000a';
update public.profissionais set comissao_pct = 30
 where id = 'c0000000-5555-0000-0000-00000000000b';

\echo ''
\echo '8) A data de corte segura a regra nova'

-- Sem data, virar a chave não vale para ninguém: mudança de regra de
-- dinheiro precisa de um começo declarado, não do dia em que alguém mexeu
-- no ajuste sem avisar.
update public.saloes
   set comissao_sobre = 'liquido', comissao_regra_desde = null
 where id = 'c0000000-1111-0000-0000-00000000000a';

insert into public.comandas (id, salao_id, cliente_id, status) values
  ('c0000000-aaaa-0000-0000-00000000000c', 'c0000000-1111-0000-0000-00000000000a',
   'c0000000-7777-0000-0000-00000000000a', 'aberta');

select t_texto('sem data de corte, a comanda nasce no bruto',
  (select comissao_sobre from public.comandas
    where id = 'c0000000-aaaa-0000-0000-00000000000c'), 'bruto');

-- Data no futuro: ainda não vale.
update public.saloes set comissao_regra_desde = current_date + 10
 where id = 'c0000000-1111-0000-0000-00000000000a';

insert into public.comandas (id, salao_id, cliente_id, status) values
  ('c0000000-aaaa-0000-0000-00000000000d', 'c0000000-1111-0000-0000-00000000000a',
   'c0000000-7777-0000-0000-00000000000a', 'aberta');

select t_texto('data no futuro: a comanda de hoje ainda é bruto',
  (select comissao_sobre from public.comandas
    where id = 'c0000000-aaaa-0000-0000-00000000000d'), 'bruto');

-- Data que já passou: vale.
update public.saloes set comissao_regra_desde = current_date - 1
 where id = 'c0000000-1111-0000-0000-00000000000a';

insert into public.comandas (id, salao_id, cliente_id, status) values
  ('c0000000-aaaa-0000-0000-00000000000e', 'c0000000-1111-0000-0000-00000000000a',
   'c0000000-7777-0000-0000-00000000000a', 'aberta');

select t_texto('data que já passou: a comanda nova é líquido',
  (select comissao_sobre from public.comandas
    where id = 'c0000000-aaaa-0000-0000-00000000000e'), 'liquido');

\echo ''
\echo '9) Produto tem comissão própria'

insert into public.produtos (id, salao_id, nome, preco, comissao_pct, comissao_fixa)
values ('c0000000-8888-0000-0000-00000000000a',
        'c0000000-1111-0000-0000-00000000000a', 'Shampoo', 60, 10, 5);

insert into public.comanda_itens
  (id, comanda_id, tipo, produto_id, descricao, qtd, preco_unit, profissional_id)
values ('c0000000-bbbb-0000-0000-000000000050',
        'c0000000-aaaa-0000-0000-00000000000a', 'produto',
        'c0000000-8888-0000-0000-00000000000a', 'Shampoo', 2, 60,
        'c0000000-5555-0000-0000-00000000000a');

select t_verdade('produto: 10% de 120 + 2 x 5 = 22',
  (select comissao_valor from public.comanda_itens_calculados
    where id = 'c0000000-bbbb-0000-0000-000000000050') = 22.00);

\echo ''
\echo '10) A escada não aceita taxa por parâmetro'

-- A assinatura de `comissao_de` é a garantia estrutural: não existe um
-- parâmetro por onde uma taxa entre. Se alguém acrescentar um, este teste
-- reprova, e é para reprovar.
-- Casar com o texto inteiro da assinatura seria frágil e enganoso: o
-- `pg_get_function_identity_arguments` inclui os parâmetros de SAÍDA, e a
-- primeira versão deste teste reprovou por isso, sem haver defeito nenhum.
--
-- O que importa não é o texto: é que nenhum parâmetro de ENTRADA sirva para
-- alguém passar uma taxa. É isso que está escrito abaixo.
select t_verdade('comissao_de não tem por onde receber uma taxa',
  not exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      cross join unnest(coalesce(p.proargnames, '{}')) with ordinality as a(nome, pos)
     where n.nspname = 'public' and p.proname = 'comissao_de'
       and (p.proargmodes is null or p.proargmodes[a.pos] in ('i','b','v'))
       and a.nome ~* 'pct|comissao|taxa|valor'));

select t_verdade('e a coluna guardada some: quem calcula é a vista',
  not exists (select 1 from information_schema.columns
               where table_name = 'comanda_itens'
                 and column_name = 'comissao_valor'));
