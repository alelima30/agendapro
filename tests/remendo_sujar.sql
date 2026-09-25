-- ===========================================================================
-- Deixa o banco do jeito que a instalação de verdade está HOJE, antes do
-- remendo. Carregado por tests/rodar.sh, nunca sozinho.
--
-- O 00_tudo.sql já traz a correção do telefone, então um banco recém-criado
-- nasce limpo — e um teste que rodasse só nele aprovaria um remendo vazio.
-- Aqui a correção é DESFEITA de propósito e o cadastro é sujado com os dois
-- estragos medidos, para o remendo ter o que consertar.
-- ===========================================================================

\set ON_ERROR_STOP on

-- A instalação antiga não tinha a trava. Sem tirar, nada sujo entra.
alter table public.clientes drop constraint if exists cli_tel_so_digitos;

insert into public.saloes (id, slug, nome, tipo) values
  ('aaaaaaaa-9999-0000-0000-000000000001', 'salao-sujo', 'Salão Sujo', 'salao');

-- `criado_em` explícito: a migração desempata pela ordem de cadastro, e sem
-- data fixa as quatro fichas nascem no mesmo instante e o desempate vira
-- sorteio — o teste passaria ou falharia conforme o dia.
insert into public.clientes (id, salao_id, nome, telefone, criado_em) values
  -- 1) Passou sem deixar número. O painel gravou string vazia.
  ('dddddddd-9999-0000-0000-00000000000a',
   'aaaaaaaa-9999-0000-0000-000000000001', 'Sem número', '',
   '2026-01-01 10:00-03'),
  -- 2) Cadastrada no balcão, com máscara. Ninguém mais tem esse número.
  ('dddddddd-9999-0000-0000-00000000000b',
   'aaaaaaaa-9999-0000-0000-000000000001', 'Com máscara', '(11) 98888-7777',
   '2026-01-01 11:00-03'),
  -- 3 e 4) A MESMA pessoa em duas fichas: uma veio pelo link da cliente (já
  -- em dígitos), outra do balcão (com máscara). Limpar a 4 criaria dois
  -- telefones iguais no mesmo salão, e `ux_cli_tel` derrubaria a migração.
  ('dddddddd-9999-0000-0000-00000000000c',
   'aaaaaaaa-9999-0000-0000-000000000001', 'Dividida (link)', '51999990000',
   '2026-01-01 12:00-03'),
  ('dddddddd-9999-0000-0000-00000000000d',
   'aaaaaaaa-9999-0000-0000-000000000001', 'Dividida (balcão)', '(51) 99999-0000',
   '2026-01-01 13:00-03');

-- ===========================================================================
-- E A INSTALAÇÃO DE HOJE NÃO TEM O PREÇO AVANÇADO: ele nasceu agora, no 33.
--
-- Sem desfazer isso aqui, o banco do teste já vem com a escada pronta — o
-- 00_tudo.sql traz — e o remendo seria aprovado mesmo saindo SEM ela. Foi
-- exatamente o que aconteceu: o remendo levava o `agendar()` que pergunta o
-- preço à escada e não levava a escada, e nada acusou.
--
-- É a mesma razão do telefone aqui em cima, escrita no cabeçalho deste
-- arquivo: teste que roda só em banco limpo aprova remendo vazio.
-- ===========================================================================
drop trigger if exists tg_preco_agend_servico on public.agendamento_servicos;
drop function if exists public.tg_preco_do_agendamento();
drop function if exists public.preco_minimo_do_servico(uuid, date);
drop function if exists public.preco_dos_servicos(uuid, uuid[], timestamptz);
drop function if exists public.preco_do_servico(uuid, uuid, timestamptz);
drop function if exists public.preco_regra_que_vale(uuid, uuid, timestamptz);
drop table if exists public.precos_regras;

-- O `default 0` é o que faz o gatilho parecer dispensável: com ele no lugar,
-- uma linha sem preço nasce ZERADA em vez de nascer nula, e o gatilho — que
-- só preenche nulo — nunca roda. Tirar o default é metade do módulo 33.
alter table public.agendamento_servicos alter column preco set default 0;

-- Uma profissional e um serviço, para o conferidor ter em que medir preço.
insert into public.profissionais (id, salao_id, nome, ativo, aceita_online)
values ('bbbbbbbb-9999-0000-0000-000000000001',
        'aaaaaaaa-9999-0000-0000-000000000001', 'Rita', true, true);
insert into public.servicos (id, salao_id, nome, duracao_min, preco, ativo)
values ('cccccccc-9999-0000-0000-000000000001',
        'aaaaaaaa-9999-0000-0000-000000000001', 'Corte', 60, 90, true);
