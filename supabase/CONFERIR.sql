-- ===========================================================================
-- AgendaPro — meu banco está em dia?
--
-- Cole isto no SQL Editor do Supabase e rode. Ele NÃO MUDA NADA: só olha e
-- responde. Serve para antes de atualizar (para ver o que falta) e depois
-- (para ver se pegou).
--
-- Cada linha devolve um veredito. Só interessa a coluna do meio:
--
--     certo    está como tem que estar
--     FALTA    não existe aí, e o 98_modulos.sql traz
--     ERRADO   existe, mas de um jeito que quebra alguma coisa
--
-- Havendo qualquer FALTA ou ERRADO, o conserto é sempre o mesmo: colar o
-- `supabase/98_modulos.sql` inteiro e rodar este arquivo de novo.
-- ===========================================================================

with conferencia(ordem, item, veredito, detalhe) as (

  -- ⚠ A PRIMEIRA É A QUE DERRUBA A MARCAÇÃO.
  --
  -- A página manda `p_email`, `p_nascimento` e `p_cpf`. Um banco com a versão
  -- antiga não reconhece esses nomes, e o PostgREST responde 404 (PGRST202)
  -- em vez de marcar — a cliente chega ao fim e o botão falha.
  --
  -- Duas versões vivas ao mesmo tempo é igualmente ruim, e mais traiçoeiro:
  -- aí quem escolhe é o PostgREST, e uma página em cache pode marcar pela
  -- antiga, que engole o cadastro sem erro nenhum.
  select 1, 'agendar() — a marcação pelo link',
         case
           when count(*) = 0 then 'FALTA'
           when count(*) > 1 then 'ERRADO'
           when max(pronargs) = 10 then 'certo'
           else 'FALTA'
         end,
         count(*)::text || ' versão(ões), argumentos: '
           || coalesce(string_agg(pronargs::text, ' e ' order by pronargs), '—')
           || '  (o certo é 1 versão, com 10)'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'agendar'

  union all
  -- O cadastro que a cliente preenche antes de confirmar.
  select 2, 'ficha da cliente — e-mail, aniversário e CPF',
         case when count(*) = 3 then 'certo' else 'FALTA' end,
         'colunas presentes: '
           || coalesce(string_agg(column_name, ', ' order by column_name), 'nenhuma')
           || '  (o certo é cpf, email, nascimento)'
    from information_schema.columns
   where table_schema = 'public' and table_name = 'clientes'
     and column_name in ('cpf', 'email', 'nascimento')

  union all
  select 3, 'pacotes — a aba e o R$ 0,00 no link',
         case when to_regclass('public.pacotes') is null then 'FALTA' else 'certo' end,
         coalesce(to_regclass('public.pacotes')::text, 'tabela não existe')

  union all
  select 4, 'pacote só em certos dias da semana',
         case when exists (select 1 from information_schema.columns
                            where table_schema='public' and table_name='pacotes'
                              and column_name='so_nos_dias')
              then 'certo' else 'FALTA' end, ''

  union all
  select 5, 'comanda e caixa opcionais',
         case when to_regprocedure('public.usa_comanda(uuid)') is null
              then 'FALTA' else 'certo' end, ''

  union all
  -- Sem o gatilho, desligar a comanda no painel faz o mês do salão ir a
  -- zero: o atendimento concluído deixa de virar dinheiro em lugar nenhum.
  select 6, 'atendimento concluído vira dinheiro sem comanda',
         case when exists (select 1 from pg_trigger
                            where tgname = 'tg_agend_sem_comanda' and not tgisinternal)
              then 'certo' else 'FALTA' end, ''

  union all
  select 7, 'confirmação manual ou automática',
         case when to_regprocedure('public.confirma_automatico(uuid)') is null
              then 'FALTA' else 'certo' end, ''

  union all
  -- O segredo que a cliente guarda ao marcar. É com ele que ela vê, cancela
  -- e remarca — sem senha e sem código.
  select 8, 'o segredo de gerenciar o horário',
         case when exists (select 1 from information_schema.columns
                            where table_schema='public' and table_name='agendamentos'
                              and column_name='gerenciar_token')
              then 'certo' else 'FALTA' end, ''

  union all
  /* ⚠ ESTE FALHA CALADO, e é por isso que ele está aqui.

     Os destaques da capa não precisaram de tabela nova: eles moram no `cfg`,
     que já existe. Quer dizer que o painel GRAVA a escolha mesmo num banco
     desatualizado — a estrela acende, o dono vê que funcionou — e a
     `vitrine()` velha simplesmente não devolve a chave. A capa da cliente
     continua se virando sozinha, que é o comportamento antigo e não parece
     defeito nenhum.

     Do lado de cá não há erro para ler. Só perguntando à função dá para
     saber, e é o que esta linha faz. */
  select 9, 'os destaques da capa — o que o dono põe na frente',
         case when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
              when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                   like '%''destaques''%' then 'certo'
              else 'FALTA' end,
         case when to_regprocedure('public.vitrine(text)') is null
              then 'a função vitrine() não existe'
              when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                   like '%''destaques''%' then ''
              else 'a vitrine() é de antes: o painel grava a escolha e a '
                || 'página da cliente nunca fica sabendo' end
)
select item                                as "o que",
       veredito                            as "está",
       nullif(detalhe, '')                 as "detalhe"
  from conferencia
 order by ordem;
