-- ===========================================================================
-- O que o 99_remendo.sql tinha que ter feito com o cadastro sujo.
-- Carregado por tests/rodar.sh depois de colar o remendo.
-- ===========================================================================

\set ON_ERROR_STOP on

select t_texto('string vazia virou nulo',
  (select telefone from public.clientes
    where id = 'dddddddd-9999-0000-0000-00000000000a'),
  null);

select t_texto('máscara virou dígitos',
  (select telefone from public.clientes
    where id = 'dddddddd-9999-0000-0000-00000000000b'),
  '11988887777');

select t_texto('a ficha que já estava limpa não foi mexida',
  (select telefone from public.clientes
    where id = 'dddddddd-9999-0000-0000-00000000000c'),
  '51999990000');

-- A que colide fica como está, de propósito. Juntar as duas fichas é mover
-- agendamento e comanda de uma para a outra: some dinheiro ou some
-- atendimento, e ninguém fica sabendo qual. Fica para o salão decidir.
select t_texto('a ficha que colidia ficou intacta',
  (select telefone from public.clientes
    where id = 'dddddddd-9999-0000-0000-00000000000d'),
  '(51) 99999-0000');

select t_verdade('a trava cli_tel_so_digitos existe',
  exists (select 1 from pg_constraint
           where conname = 'cli_tel_so_digitos'
             and conrelid = 'public.clientes'::regclass));

-- A trava é o que impede o defeito de voltar por outro caminho: um painel
-- antigo em cache, um import de planilha, uma inserção pelo painel do
-- Supabase. Conferir que ela EXISTE não basta — `not valid` também existe e
-- não recusaria nada se estivesse escrita errada.
select t_verdade('telefone novo com máscara é recusado',
  recusado($$insert into public.clientes (salao_id, nome, telefone)
             values ('aaaaaaaa-9999-0000-0000-000000000001',
                     'Nova', '(31) 97777-6666')$$));

select t_verdade('telefone novo em dígitos passa',
  not recusado($$insert into public.clientes (salao_id, nome, telefone)
                 values ('aaaaaaaa-9999-0000-0000-000000000001',
                         'Nova', '31977776666')$$));

-- Duas fichas sem número no mesmo salão: era o "duplicate key value violates
-- unique constraint ux_cli_tel" que a recepção levava ao cadastrar a segunda
-- pessoa que passou sem deixar telefone.
select t_verdade('dá para cadastrar duas fichas sem telefone',
  not recusado($$insert into public.clientes (salao_id, nome, telefone) values
                 ('aaaaaaaa-9999-0000-0000-000000000001', 'Sem número 2', null),
                 ('aaaaaaaa-9999-0000-0000-000000000001', 'Sem número 3', null)$$));

-- ===========================================================================
-- A ESCADA DE PREÇO INTEIRA — TABELA, FUNÇÕES, GATILHO E O DEFAULT FORA
--
-- O `sujar` apagou tudo isso, imitando a instalação de antes do módulo 33. O
-- remendo tem que devolver os quatro. Faltando qualquer um, marcar pelo link
-- para de funcionar — e não com preço errado: com a marcação RECUSADA, porque
-- o `agendar()` grava `null::numeric` de propósito numa coluna `not null`.
-- ===========================================================================
select t_verdade('a tabela das regras de preço voltou',
  to_regclass('public.precos_regras') is not null);

select t_verdade('as três funções da escada voltaram',
  to_regprocedure('public.preco_regra_que_vale(uuid, uuid, timestamptz)') is not null
  and to_regprocedure('public.preco_do_servico(uuid, uuid, timestamptz)') is not null
  and to_regprocedure('public.preco_dos_servicos(uuid, uuid[], timestamptz)') is not null);

select t_verdade('o gatilho do preço voltou',
  exists (select 1 from pg_trigger
           where tgname = 'tg_preco_agend_servico'
             and tgrelid = 'public.agendamento_servicos'::regclass
             and not tgisinternal));

-- Conferir que o gatilho existe não basta. Com o `default 0` de volta na
-- coluna, uma linha sem preço nasce ZERADA e o gatilho — que só preenche
-- nulo — nunca roda. O módulo são as duas coisas.
select t_verdade('e o default 0 saiu da coluna',
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'agendamento_servicos'
      and column_name = 'preco') is null);

-- E agora medindo, que é o que importa: uma regra de R$ 50 para um serviço de
-- catálogo R$ 90, uma linha lançada SEM preço, e o preço que ficou gravado.
insert into public.precos_regras (salao_id, servico_id, preco) values
  ('aaaaaaaa-9999-0000-0000-000000000001',
   'cccccccc-9999-0000-0000-000000000001', 50);

-- `encaixe` pula a conferência de jornada: aqui o assunto é preço, e montar
-- uma jornada só para o gatilho poder rodar mistura duas medições.
insert into public.agendamentos
  (id, salao_id, cliente_id, profissional_id, inicio, fim, encaixe) values
  ('eeeeeeee-9999-0000-0000-000000000001',
   'aaaaaaaa-9999-0000-0000-000000000001',
   'dddddddd-9999-0000-0000-00000000000c',
   'bbbbbbbb-9999-0000-0000-000000000001',
   '2026-03-03 13:00-03', '2026-03-03 14:00-03', true);

insert into public.agendamento_servicos
  (agendamento_id, servico_id, ordem, duracao_min)
values ('eeeeeeee-9999-0000-0000-000000000001',
        'cccccccc-9999-0000-0000-000000000001', 1, 60);

select t_texto('linha lançada sem preço nasce com o preço da regra',
  (select preco::text from public.agendamento_servicos
    where agendamento_id = 'eeeeeeee-9999-0000-0000-000000000001'),
  '50.00');
