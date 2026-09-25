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

  union all
  -- Os números do dashboard. Sem esta função a aba abre e explica o que
  -- fazer, em vez de dar erro em inglês — mas não desenha nada.
  select 10, 'os números do dashboard',
         case when to_regprocedure('public.painel_grafico(uuid)') is null
              then 'FALTA' else 'certo' end,
         case when to_regprocedure('public.painel_grafico(uuid)') is null
              then 'o dashboard vai abrir vazio, pedindo esta atualização'
              else '' end

  union all
  /* A identidade visual do estabelecimento, pelo mesmo caminho silencioso do
     item 9: a `vitrine()` de antes não conhece as chaves novas, o painel
     grava a escolha do dono e a página da cliente nunca fica sabendo.

     ⚠ Aqui ela some sem parecer defeito nenhum, que é o pior caso: a página
     continua bonita, com as cores calculadas de sempre. O dono vai jurar que
     escolheu e que não pegou — e está certo. */
  select 11, 'as cores e o modo que o dono escolhe para o link',
         case when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
              when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                   like '%''logoForma''%' then 'certo'
              else 'FALTA' end,
         case when to_regprocedure('public.vitrine(text)') is null
              then 'a função vitrine() não existe'
              when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                   like '%''logoForma''%' then ''
              else 'a vitrine() é de antes: a tela de Aparência salva, e a '
                || 'página da cliente continua com o visual calculado' end

  union all
  /* Os dias da semana por serviço. Três peças têm que estar de pé, e por isso
     esta linha olha as três: a COLUNA (senão o painel nem grava), a FUNÇÃO que
     escreve a recusa, e a `porque_nao_agenda()` chamando a função — que é o
     que faz a recusa valer para o `horarios_livres()` e para o `agendar()`.

     ⚠ A terceira é a que falha calado. Com a coluna e a função no lugar mas a
     `porque_nao_agenda()` de antes, o dono marca "escova só de quinta a
     sábado", a tela grava, e o link continua oferecendo segunda-feira. Sem
     erro nenhum: só uma regra que não é perguntada a ninguém. */
  select 12, 'o serviço que só é feito em certos dias',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema='public' and table_name='servicos'
                               and column_name='dias') then 'FALTA'
           when to_regprocedure('public.servico_fora_do_dia(uuid[], date)') is null
             then 'FALTA'
           when pg_get_functiondef(to_regprocedure(
                  'public.porque_nao_agenda(uuid, date, uuid[])'))
                like '%servico_fora_do_dia%' then 'certo'
           else 'FALTA' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema='public' and table_name='servicos'
                               and column_name='dias')
             then 'falta a coluna servicos.dias — o painel não tem onde gravar'
           when to_regprocedure('public.servico_fora_do_dia(uuid[], date)') is null
             then 'falta a função que escreve a recusa'
           when pg_get_functiondef(to_regprocedure(
                  'public.porque_nao_agenda(uuid, date, uuid[])'))
                like '%servico_fora_do_dia%' then ''
           else 'a porque_nao_agenda() é de antes: o dono marca os dias, a tela '
             || 'grava, e o link continua oferecendo os outros' end
  union all
  /* Os dois módulos da casa. A pergunta é UMA: a `vitrine()` de hoje sabe
     responder "esta casa trabalha com serviços?" e "vende produtos?".

     ⚠ E A CONFERÊNCIA OLHA A PENEIRA, não só o nome da chave. Com
     `(cfg->>'loja')::boolean` as duas chaves aparecem no texto da função e
     tudo parece no lugar — até o dia em que um caractere estranho entra no
     `cfg` e a `vitrine()` LEVANTA. Aí não é a loja que some: é a página
     inteira da cliente, com o link que o salão mandou no WhatsApp.

     Por isso o teste é o `lower(btrim(`: é a assinatura da peneira de letra,
     a mesma do `usa_comanda()`. */
  select 13, 'os dois módulos: serviços e loja',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%usaServicos%' then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                like '%(s.cfg->>''loja'')::boolean%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%usaServicos%'
             then 'a vitrine() é de antes dos módulos: o painel liga e desliga, '
               || 'e a página da cliente não fica sabendo'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                like '%(s.cfg->>''loja'')::boolean%'
             then 'a peneira ainda é ::boolean: um caractere estranho no cfg '
               || 'derruba a página inteira da cliente'
           else '' end
  union all
  /* O preço avançado. Cinco peças, e as duas últimas falham caladas: sem o
     GATILHO, a regra vale só para quem marca pelo link, e a recepção continua
     cobrando o preço do catálogo. Foi medido antes de existir: R$ 40 de
     diferença no mesmo atendimento, decidido por quem clicou.

     E sem tirar o DEFAULT 0 da coluna o gatilho não roda para a linha
     lançada sem preço — ela nasce zerada, e zero não é nulo. Sem o gatilho E
     com o default, é pior: o link grava nulo de propósito numa coluna que não
     aceita nulo, e a marcação é recusada. O 99_remendo.sql saiu assim uma
     vez, e só uma linha lançada de verdade mostrou. */
  select 14, 'preço por dia, horário e vigência',
         case
           when to_regclass('public.precos_regras') is null then 'FALTA'
           when to_regprocedure(
                  'public.preco_do_servico(uuid, uuid, timestamp with time zone)')
                is null then 'FALTA'
           when to_regprocedure(
                  'public.preco_dos_servicos(uuid, uuid[], timestamp with time zone)')
                is null then 'FALTA'
           when not exists (select 1 from pg_trigger
                             where tgname = 'tg_preco_agend_servico'
                               and not tgisinternal) then 'FALTA'
           when (select column_default from information_schema.columns
                  where table_schema = 'public'
                    and table_name = 'agendamento_servicos'
                    and column_name = 'preco') is not null then 'FALTA'
           else 'certo' end,
         case
           when to_regclass('public.precos_regras') is null
             then 'falta a tabela — o painel não tem onde gravar as regras'
           when to_regprocedure(
                  'public.preco_do_servico(uuid, uuid, timestamp with time zone)')
                is null
             then 'falta a escada: o preço volta a ser uma coluna por leitor'
           when to_regprocedure(
                  'public.preco_dos_servicos(uuid, uuid[], timestamp with time zone)')
                is null
             then 'falta a conta com horário: marcar pelo link dá erro'
           when not exists (select 1 from pg_trigger
                             where tgname = 'tg_preco_agend_servico'
                               and not tgisinternal)
             then 'falta o gatilho: a regra vale para o link e a recepção '
               || 'continua cobrando o catálogo'
           when (select column_default from information_schema.columns
                  where table_schema = 'public'
                    and table_name = 'agendamento_servicos'
                    and column_name = 'preco') is not null
             then 'a coluna do preço ainda nasce com zero: a linha lançada '
               || 'sem preço fica R$ 0,00 em vez do preço da regra'
           else '' end
  union all
  /* Os horários de funcionamento, os pagamentos e a apresentação. Sem as
     chaves na vitrine(), o painel grava a semana e a página da cliente nunca
     fica sabendo: nenhum erro, só o cartão ABERTO/FECHADO que não aparece. */
  select 15, 'horários, pagamentos e informações na página',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%funcionamento%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%funcionamento%'
             then 'a vitrine() é de antes dos horários: o painel grava e a '
               || 'página da cliente não mostra'
           else '' end
)
select item                                as "o que",
       veredito                            as "está",
       nullif(detalhe, '')                 as "detalhe"
  from conferencia
 order by ordem;
