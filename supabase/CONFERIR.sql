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
           -- 11 desde o cupom (34_cupons.sql): a página manda `p_cupom`.
           -- 12 desde `p_acompanhante` (o pacote não cobre quem veio junto).
           -- 13 desde `p_forma_pagamento` (como ela vai pagar).
           when max(pronargs) = 13 then 'certo'
           else 'FALTA'
         end,
         count(*)::text || ' versão(ões), argumentos: '
           || coalesce(string_agg(pronargs::text, ' e ' order by pronargs), '—')
           || '  (o certo é 1 versão, com 13)'
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
  -- E existir não basta: a versão antiga do gatilho cobrava a sessão de
  -- pacote pelo preço cheio e esquecia o desconto do cupom.
  select 6, 'atendimento concluído vira dinheiro sem comanda',
         case when not exists (select 1 from pg_trigger
                                where tgname = 'tg_agend_sem_comanda' and not tgisinternal)
                then 'FALTA'
              when pg_get_functiondef('public.tg_agendamento_sem_comanda()'::regprocedure)
                     not like '%pacote_cliente_id%'
                or pg_get_functiondef('public.tg_agendamento_sem_comanda()'::regprocedure)
                     not like '%new.desconto%'
                then 'ANTIGO'
              else 'certo' end,
         case when exists (select 1 from pg_trigger
                            where tgname = 'tg_agend_sem_comanda' and not tgisinternal)
               and (pg_get_functiondef('public.tg_agendamento_sem_comanda()'::regprocedure)
                      not like '%pacote_cliente_id%'
                 or pg_get_functiondef('public.tg_agendamento_sem_comanda()'::regprocedure)
                      not like '%new.desconto%')
              then 'cole o 00_tudo.sql de novo: a comanda automática ainda cobra a '
                || 'sessão de pacote e ignora o cupom (28_sem_comanda.sql)'
              else '' end

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
  union all
  /* A divisão da foto de capa (reta ou arredondada). Sem a chave na
     vitrine(), o dono escolhe "Reta", a prévia mostra reta e o link continua
     com o arco — a prévia prometendo o que a página não faz. */
  select 16, 'divisão da foto de capa na página',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%capaForma%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%capaForma%'
             then 'a vitrine() é de antes da divisão da foto: "Reta" aparece '
               || 'na prévia e não no link'
           else '' end
  union all
  /* O estilo dos atalhos (sem moldura / com assombreamento). Sem a chave, a
     prévia muda e o link continua com o cartão com borda. */
  select 17, 'estilo dos atalhos na página',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%''atalhos''%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%''atalhos''%'
             then 'a vitrine() é de antes do estilo dos atalhos: a prévia '
               || 'muda e o link não'
           else '' end
  union all
  /* O botão "Ver produtos" igual ao Agendar horário. Sem a chave, a prévia
     mostra o botão cheio e o link continua com o discreto. */
  select 18, 'botão Ver produtos na página',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%botaoProdutos%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%botaoProdutos%'
             then 'a vitrine() é de antes do botão Ver produtos: a prévia '
               || 'muda e o link não'
           else '' end
  union all
  /* Pular o "Com quem?" com uma pessoa só. Sem a chave, o dono escolhe
     "Ir direto para os horários" no painel e o link continua mostrando. */
  select 19, 'pular o "Com quem?" com uma pessoa só',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%pularComQuem%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%pularComQuem%'
             then 'a vitrine() é de antes desta escolha: o painel grava e o '
               || 'link continua mostrando o "Com quem?"'
           else '' end
  union all
  /* A abertura com o logo. Sem a chave, a prévia do painel toca a abertura
     e o link continua abrindo direto na página. */
  select 20, 'abertura com o logo',
         case
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%''intro''%' then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%''intro''%'
             then 'a vitrine() é de antes da abertura: a prévia mostra e o '
               || 'link não'
           else '' end
  union all
  /* A categoria dos produtos: a coluna, e a vitrine devolvendo. Sem as duas,
     o painel guarda a categoria e a loja do link não mostra o filtro. */
  select 21, 'categoria dos produtos',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'produtos'
                               and column_name = 'categoria') then 'FALTA'
           when to_regprocedure('public.vitrine(text)') is null then 'FALTA'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%pr.categoria%' then 'FALTA'
           else 'certo' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'produtos'
                               and column_name = 'categoria')
             then 'falta a coluna produtos.categoria — rode o 00_tudo.sql'
           when to_regprocedure('public.vitrine(text)') is null
             then 'a vitrine() nem existe — rode o 00_tudo.sql'
           when pg_get_functiondef(to_regprocedure('public.vitrine(text)'))
                not like '%pr.categoria%'
             then 'a vitrine() é de antes da categoria: o painel guarda e a '
               || 'loja do link não filtra'
           else '' end
  union all
  /* A conta da cliente no link: ligar a ficha do balcão à conta (e o pacote
     junto) e "Meus horários" em qualquer aparelho. */
  select 22, 'conta da cliente no link',
         case
           when to_regprocedure('public.ligar_minha_ficha(uuid)') is null
             or to_regprocedure('public.meus_agendamentos_da_conta()') is null
             then 'FALTA'
           when has_function_privilege('anon', 'public.ligar_minha_ficha(uuid)', 'execute')
             or has_function_privilege('anon', 'public.meus_agendamentos_da_conta()', 'execute')
             then 'ABERTA'
           else 'certo' end,
         case
           when to_regprocedure('public.ligar_minha_ficha(uuid)') is null
             or to_regprocedure('public.meus_agendamentos_da_conta()') is null
             then 'falta o 09_cliente.sql novo: a cliente entra, mas o pacote '
               || 'e os horários dela não aparecem'
           when has_function_privilege('anon', 'public.ligar_minha_ficha(uuid)', 'execute')
             or has_function_privilege('anon', 'public.meus_agendamentos_da_conta()', 'execute')
             then 'quem não entrou consegue chamar as funções da conta — rode o '
               || '09_cliente.sql de novo'
           else '' end
  union all
  /* A cliente que precisa de confirmação: a marca na ficha, e o agendar()
     que respeita ela. A função não pode estar aberta: diria a qualquer um,
     pelo telefone, quem está marcada no salão. */
  select 23, 'cliente que precisa de confirmação',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'clientes'
                               and column_name = 'exige_confirmacao')
             or to_regprocedure('public.cliente_exige_confirmacao(uuid,uuid,text)') is null
             or coalesce(position('cliente_exige_confirmacao' in pg_get_functiondef(
                  to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)'))), 0) = 0
             then 'FALTA'
           when has_function_privilege('anon', 'public.cliente_exige_confirmacao(uuid,uuid,text)', 'execute')
             or has_function_privilege('authenticated', 'public.cliente_exige_confirmacao(uuid,uuid,text)', 'execute')
             then 'ABERTA'
           else 'certo' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'clientes'
                               and column_name = 'exige_confirmacao')
             or to_regprocedure('public.cliente_exige_confirmacao(uuid,uuid,text)') is null
             or coalesce(position('cliente_exige_confirmacao' in pg_get_functiondef(
                  to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)'))), 0) = 0
             then 'falta o 09_cliente.sql novo: a marca "precisa de confirmação" '
               || 'na ficha não segura o horário da cliente'
           when has_function_privilege('anon', 'public.cliente_exige_confirmacao(uuid,uuid,text)', 'execute')
             or has_function_privilege('authenticated', 'public.cliente_exige_confirmacao(uuid,uuid,text)', 'execute')
             then 'qualquer um consegue perguntar quem está marcado — rode o '
               || '09_cliente.sql de novo'
           else '' end
  union all
  /* Os cupons: as tabelas, o desconto no agendamento, a prévia do link e o
     agendar() que aplica o cupom. A conta em si (`cupom_calcular`) e a ficha
     de quem está logado (`cupom_minha_ficha`) não podem estar abertas: só o
     banco chama. */
  select 24, 'cupons de desconto',
         case
           when to_regclass('public.cupons') is null or to_regclass('public.cupom_usos') is null
             or not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'agendamentos'
                               and column_name = 'desconto')
             or to_regprocedure('public.conferir_cupom(uuid,text,text,uuid[],uuid,timestamptz,jsonb)') is null
             or to_regprocedure('public.usar_cupom_no_pedido(uuid,text,jsonb)') is null
             or to_regprocedure('public.salao_tem_cupom(uuid)') is null
             or to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)') is null
             then 'FALTA'
           when has_function_privilege('anon', 'public.cupom_calcular(uuid,text,text,uuid[],uuid,timestamptz,jsonb,text,uuid,boolean)', 'execute')
             or has_function_privilege('authenticated', 'public.cupom_calcular(uuid,text,text,uuid[],uuid,timestamptz,jsonb,text,uuid,boolean)', 'execute')
             or has_function_privilege('anon', 'public.cupom_minha_ficha(uuid)', 'execute')
             then 'ABERTA'
           else 'certo' end,
         case
           when to_regclass('public.cupons') is null or to_regclass('public.cupom_usos') is null
             or not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'agendamentos'
                               and column_name = 'desconto')
             or to_regprocedure('public.conferir_cupom(uuid,text,text,uuid[],uuid,timestamptz,jsonb)') is null
             or to_regprocedure('public.usar_cupom_no_pedido(uuid,text,jsonb)') is null
             or to_regprocedure('public.salao_tem_cupom(uuid)') is null
             or to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)') is null
             then 'falta o 34_cupons.sql (e o 09_cliente.sql novo): o cupom não '
               || 'aparece no link nem desconta'
           when has_function_privilege('anon', 'public.cupom_calcular(uuid,text,text,uuid[],uuid,timestamptz,jsonb,text,uuid,boolean)', 'execute')
             or has_function_privilege('authenticated', 'public.cupom_calcular(uuid,text,text,uuid[],uuid,timestamptz,jsonb,text,uuid,boolean)', 'execute')
             or has_function_privilege('anon', 'public.cupom_minha_ficha(uuid)', 'execute')
             then 'a conta do cupom está aberta — rode o 34_cupons.sql de novo'
           else '' end
  union all
  /* O que o caça-bug achou e foi consertado no banco. Cada linha aqui é um
     defeito reproduzido — se alguma voltar, é porque um arquivo antigo foi
     colado por cima. */
  select 25, 'consertos do caça-bug',
         case
           when to_regclass('public.estornos') is null
             or not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'estornos'
                               and column_name = 'caixa_id')
             or to_regprocedure('public.remarcar_agendamento(uuid,uuid)') is null
             then 'FALTA'
           when exists (select 1 from pg_policies
                         where schemaname = 'public'
                           and tablename in ('profissionais','servicos','servicos_profissionais','jornadas')
                           and cmd = 'SELECT' and qual like '%tem_acesso%')
             or exists (select 1 from pg_policies
                         where schemaname = 'public' and tablename = 'clientes'
                           and policyname in ('cli_eu_editar','cli_eu_criar'))
             then 'ABERTA'
           when pg_get_functiondef('public.ficha_do_cliente(uuid,text,text)'::regprocedure)
                  not like '%''55'' ||%'
             or not exists (select 1 from pg_trigger
                             where tgname = 'tg_preco_agend_servico'
                               and pg_get_triggerdef(oid) like '%UPDATE OF preco%')
             then 'ANTIGO'
           else 'certo' end,
         case
           when to_regclass('public.estornos') is null
             or not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'estornos'
                               and column_name = 'caixa_id')
             or to_regprocedure('public.remarcar_agendamento(uuid,uuid)') is null
             then 'cole o 00_tudo.sql de novo (17_caixa e 34_cupons)'
           when exists (select 1 from pg_policies
                         where schemaname = 'public'
                           and tablename in ('profissionais','servicos','servicos_profissionais','jornadas')
                           and cmd = 'SELECT' and qual like '%tem_acesso%')
             or exists (select 1 from pg_policies
                         where schemaname = 'public' and tablename = 'clientes'
                           and policyname in ('cli_eu_editar','cli_eu_criar'))
             then 'telefone e comissão da equipe, ou a ficha da cliente, ainda '
               || 'abertos — cole o 00_tudo.sql de novo (02_rls)'
           when pg_get_functiondef('public.ficha_do_cliente(uuid,text,text)'::regprocedure)
                  not like '%''55'' ||%'
             or not exists (select 1 from pg_trigger
                             where tgname = 'tg_preco_agend_servico'
                               and pg_get_triggerdef(oid) like '%UPDATE OF preco%')
             then 'cole o 00_tudo.sql de novo (05_agenda e 33_preco_regras)'
           else '' end
  union all
  /* As duas decisões do dono do produto depois do caça-bug:
     · cupom na loja só com a cliente dentro da conta — sem isso, o pedido
       gastava o cupom em repetição, sem compra nenhuma;
     · no "eu e mais alguém", o pacote cobre só o horário dela. */
  select 26, 'cupom da loja com conta; pacote só de quem comprou',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'cupom_usos'
                               and column_name = 'perfil_id')
             or to_regprocedure('public.cupom_loja_da_conta(uuid,text,boolean)') is null
             or to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)') is null
             then 'FALTA'
           when has_function_privilege('anon', 'public.cupom_loja_da_conta(uuid,text,boolean)', 'execute')
             or has_function_privilege('authenticated', 'public.cupom_loja_da_conta(uuid,text,boolean)', 'execute')
             or pg_get_functiondef('public.usar_cupom_no_pedido(uuid,text,jsonb)'::regprocedure)
                  not like '%cupom_loja_da_conta%'
             then 'ABERTA'
           when pg_get_functiondef(to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)'))
                  not like '%p_acompanhante, false%'
             then 'ANTIGO'
           else 'certo' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'cupom_usos'
                               and column_name = 'perfil_id')
             or to_regprocedure('public.cupom_loja_da_conta(uuid,text,boolean)') is null
             or to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)') is null
             then 'cole o 00_tudo.sql de novo (34_cupons e 09_cliente)'
           when has_function_privilege('anon', 'public.cupom_loja_da_conta(uuid,text,boolean)', 'execute')
             or has_function_privilege('authenticated', 'public.cupom_loja_da_conta(uuid,text,boolean)', 'execute')
             or pg_get_functiondef('public.usar_cupom_no_pedido(uuid,text,jsonb)'::regprocedure)
                  not like '%cupom_loja_da_conta%'
             then 'o cupom da loja ainda vale sem conta — cole o 00_tudo.sql de novo'
           when pg_get_functiondef(to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)'))
                  not like '%p_acompanhante, false%'
             then 'o pacote ainda cobre a acompanhante — cole o 00_tudo.sql de novo'
           else '' end
  union all
  /* Como a cliente vai pagar: a coluna no agendamento, a trava das quatro
     formas, e o agendar() que grava o que ela escolheu no link. */
  select 27, 'forma de pagamento na marcação',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'agendamentos'
                               and column_name = 'forma_pagamento')
             or not exists (select 1 from pg_constraint where conname = 'agend_forma_pagamento')
             or to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)') is null
             then 'FALTA'
           else 'certo' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'agendamentos'
                               and column_name = 'forma_pagamento')
             or not exists (select 1 from pg_constraint where conname = 'agend_forma_pagamento')
             or to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text,text,date,text,text,boolean,text)') is null
             then 'cole o 00_tudo.sql de novo (09_cliente): a forma de pagamento '
               || 'que a cliente escolhe não é gravada'
           else '' end
  union all
  /* O número do WhatsApp é do AgendaPro, um só para todos os salões. A
     confirmação e o lembrete têm de levar o nome da casa — e o modelo
     cadastrado na Meta espera SEIS variáveis. Com cinco, a Meta recusa cada
     mensagem com o erro 132000.

     E os nomes têm de ser os que a Meta aprovou: o aviso ao profissional é
     'agendapro_aviso_profissional' (o de utilidade; o 'agendapro_novo1' virou
     marketing e não chegava), e o resumo do dia é 'agendapro_agenda_hoje' (o curto,
     com botão). Nome que não existe lá volta 132001. */
  /* Com "mensagens com valor" ligado no admin, o aviso e o lembrete do
     salão vão pelos modelos `_pagamento` (item 40): o sufixo é tirado antes
     de comparar, senão estas duas linhas acusavam FALTA num banco certo. */
  select 28, 'mensagens do WhatsApp: salão no texto e os modelos certos',
         case
           when to_regprocedure('public.variaveis_agendamento(uuid,text)') is null
             or pg_get_functiondef(to_regprocedure('public.variaveis_agendamento(uuid,text)'))
                  not like '%''casa''%'
             or to_regprocedure('public.variaveis_resumo(uuid,uuid,date,text,text)') is null
             or to_regprocedure('public.modelo_de(text)') is null
             or regexp_replace(public.modelo_de('novo'), '_pagamento$', '')
                  is distinct from 'agendapro_aviso_profissional'
             or public.modelo_de('resumo') is distinct from 'agendapro_agenda_hoje'
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.variaveis_agendamento(uuid,text)') is null
             or pg_get_functiondef(to_regprocedure('public.variaveis_agendamento(uuid,text)'))
                  not like '%''casa''%'
             or to_regprocedure('public.variaveis_resumo(uuid,uuid,date,text,text)') is null
             or to_regprocedure('public.modelo_de(text)') is null
             or regexp_replace(public.modelo_de('novo'), '_pagamento$', '')
                  is distinct from 'agendapro_aviso_profissional'
             or public.modelo_de('resumo') is distinct from 'agendapro_agenda_hoje'
             then 'cole o 00_tudo.sql de novo (21_notificacoes): as mensagens saem '
               || 'sem o nome do salão ou com nome de modelo que a Meta não tem'
           else '' end
  union all
  /* O lembrete para o salão: a vontade de cada pessoa, o tipo novo na fila,
     o modelo, e a varredura de carona no agendador (sem ela, ligar o lembrete
     não valeria para o que já estava marcado). */
  select 29, 'lembrete para o salão (quem atende / dono)',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'profissionais'
                               and column_name = 'notif_lembrete')
             or to_regprocedure('public.refazer_lembrete_equipe(uuid)') is null
             or to_regprocedure('public.gerar_lembretes_equipe()') is null
             or not exists (select 1 from pg_constraint
                             where conname = 'notificacoes_tipo_check'
                               and pg_get_constraintdef(oid) like '%lembrete_equipe%')
             or regexp_replace(public.modelo_de('lembrete_equipe'), '_pagamento$', '')
                  is distinct from 'agendapro_lembrete_equipe'
             or pg_get_functiondef(to_regprocedure('public.gerar_resumos(timestamptz)'))
                  not like '%gerar_lembretes_equipe%'
             then 'FALTA'
           else 'certo' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'profissionais'
                               and column_name = 'notif_lembrete')
             or to_regprocedure('public.refazer_lembrete_equipe(uuid)') is null
             or to_regprocedure('public.gerar_lembretes_equipe()') is null
             or not exists (select 1 from pg_constraint
                             where conname = 'notificacoes_tipo_check'
                               and pg_get_constraintdef(oid) like '%lembrete_equipe%')
             or regexp_replace(public.modelo_de('lembrete_equipe'), '_pagamento$', '')
                  is distinct from 'agendapro_lembrete_equipe'
             or pg_get_functiondef(to_regprocedure('public.gerar_resumos(timestamptz)'))
                  not like '%gerar_lembretes_equipe%'
             then 'cole o 00_tudo.sql de novo (21_notificacoes): o lembrete para '
               || 'o salão não está instalado'
           else '' end
  union all
  /* A franquia nova (teste 100, Essencial 500…), a reserva da cliente no
     worker, e o prazo: mensagem de horário que já começou não sai. */
  select 30, 'franquia de mensagens e reserva da cliente',
         case
           when (select (recursos->>'mensagens_mes')::int from public.planos
                  where codigo = 'trial') is distinct from 100
             or (select (recursos->>'mensagens_mes')::int from public.planos
                  where codigo = 'individual') is distinct from 500
             or to_regprocedure('public.pode_enviar_tipo(uuid,text)') is null
             or pg_get_functiondef(to_regprocedure('public.notificacao_proxima(integer)'))
                  not like '%pode_enviar_tipo%'
             or pg_get_functiondef(to_regprocedure('public.notificacao_proxima(integer)'))
                  not like '%o horário já passou%'
             or pg_get_functiondef(to_regprocedure('public.uso_do_plano(uuid)'))
                  not like '%tetoSalao%'
             then 'FALTA'
           else 'certo' end,
         case
           when (select (recursos->>'mensagens_mes')::int from public.planos
                  where codigo = 'trial') is distinct from 100
             or (select (recursos->>'mensagens_mes')::int from public.planos
                  where codigo = 'individual') is distinct from 500
             or to_regprocedure('public.pode_enviar_tipo(uuid,text)') is null
             or pg_get_functiondef(to_regprocedure('public.notificacao_proxima(integer)'))
                  not like '%pode_enviar_tipo%'
             or pg_get_functiondef(to_regprocedure('public.notificacao_proxima(integer)'))
                  not like '%o horário já passou%'
             or pg_get_functiondef(to_regprocedure('public.uso_do_plano(uuid)'))
                  not like '%tetoSalao%'
             then 'cole o 00_tudo.sql de novo (22_cotas e 24_produtos): a franquia '
               || 'nova ou a reserva da cliente não está instalada'
           else '' end
  union all
  /* O preço especial por salão (13, 1b) lido pelo Pix, e a campanha presa
     ao plano e à franquia (22, 2c) — a porta dos fundos do limite. */
  select 31, 'preço especial por salão e campanha dentro do limite',
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'assinaturas'
                               and column_name = 'precos_especiais')
             or to_regprocedure('public.preco_do_plano(uuid,text)') is null
             or pg_get_functiondef(to_regprocedure('public.abrir_cobranca(uuid,text,text,uuid)'))
                  not like '%preco_do_plano%'
             or to_regprocedure('public.campanha_liberada(uuid)') is null
             or pg_get_functiondef(to_regprocedure('public.fila_proxima(integer)'))
                  not like '%campanha_liberada%'
             then 'FALTA'
           else 'certo' end,
         case
           when not exists (select 1 from information_schema.columns
                             where table_schema = 'public' and table_name = 'assinaturas'
                               and column_name = 'precos_especiais')
             or to_regprocedure('public.preco_do_plano(uuid,text)') is null
             or pg_get_functiondef(to_regprocedure('public.abrir_cobranca(uuid,text,text,uuid)'))
                  not like '%preco_do_plano%'
             or to_regprocedure('public.campanha_liberada(uuid)') is null
             or pg_get_functiondef(to_regprocedure('public.fila_proxima(integer)'))
                  not like '%campanha_liberada%'
             then 'cole o 00_tudo.sql de novo (13_cobranca, 10_campanhas e 22_cotas)'
           else '' end
  union all
  /* Os planos novos: o Básico (R$ 49,90, sem mensagens) e o Grátis só para
     conhecer — as travas de módulo no banco e o link simples. */
  select 32, 'Básico sem mensagens e Grátis bem limitado',
         case
           when (select preco_mes from public.planos where codigo = 'basico') is null
             or (select (recursos->>'mensagens_mes')::int from public.planos where codigo = 'basico') is distinct from 0
             or (select (recursos->>'caixa')::boolean from public.planos where codigo = 'gratuito') is distinct from false
             or (select (recursos->>'agendamentos_mes')::int from public.planos where codigo = 'gratuito') is distinct from 20
             or to_regprocedure('public.exigir_recurso(uuid,text,text)') is null
             or pg_get_functiondef(to_regprocedure('public.usa_comanda(uuid)')) not like '%caixa%'
             or pg_get_functiondef(to_regprocedure('public.vitrine(text)')) not like '%aparencia%'
             or not exists (select 1 from pg_trigger where tgname = 'tg_caixa_do_plano')
             or to_regprocedure('public.plano_do_salao(uuid)') is null
             or has_function_privilege('anon', 'public.plano_do_salao(uuid)', 'execute')
             then 'FALTA'
           else 'certo' end,
         case
           when (select preco_mes from public.planos where codigo = 'basico') is null
             or (select (recursos->>'mensagens_mes')::int from public.planos where codigo = 'basico') is distinct from 0
             or (select (recursos->>'caixa')::boolean from public.planos where codigo = 'gratuito') is distinct from false
             or (select (recursos->>'agendamentos_mes')::int from public.planos where codigo = 'gratuito') is distinct from 20
             or to_regprocedure('public.exigir_recurso(uuid,text,text)') is null
             or pg_get_functiondef(to_regprocedure('public.usa_comanda(uuid)')) not like '%caixa%'
             or pg_get_functiondef(to_regprocedure('public.vitrine(text)')) not like '%aparencia%'
             or not exists (select 1 from pg_trigger where tgname = 'tg_caixa_do_plano')
             or to_regprocedure('public.plano_do_salao(uuid)') is null
             or has_function_privilege('anon', 'public.plano_do_salao(uuid)', 'execute')
             then 'cole o 00_tudo.sql de novo (planos novos e travas de módulo)'
           else '' end
  union all
  /* O Pix gerado e não pago dá para cancelar (13_cobranca), e o horário
     trocado por outro volta como "remarcado" na lista da cliente (09). */
  select 34, 'Cancelar o Pix em aberto e o horário remarcado',
         case
           when to_regprocedure('public.cancelar_minha_cobranca(uuid)') is null
             or has_function_privilege('anon', 'public.cancelar_minha_cobranca(uuid)', 'execute')
             or pg_get_functiondef(to_regprocedure('public.meus_agendamentos(uuid[])')) not like '%remarcado%'
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.cancelar_minha_cobranca(uuid)') is null
             or has_function_privilege('anon', 'public.cancelar_minha_cobranca(uuid)', 'execute')
             or pg_get_functiondef(to_regprocedure('public.meus_agendamentos(uuid[])')) not like '%remarcado%'
             then 'cole o 00_tudo.sql de novo (13_cobranca e 09_cliente)'
           else '' end
  union all
  /* O botão Excluir conta (36_excluir_conta): as duas funções que a tela
     chama, nenhuma aberta a quem não entrou, e a que apaga o salão inteiro
     fechada até para quem entrou — só a excluir_minha_conta() a chama. */
  select 35, 'Excluir conta',
         case
           when to_regprocedure('public.excluir_minha_conta(text)') is null
             or to_regprocedure('public.o_que_excluir_apaga()') is null
             or has_function_privilege('anon', 'public.excluir_minha_conta(text)', 'execute')
             or has_function_privilege('authenticated', 'public.apagar_salao_inteiro(uuid)', 'execute')
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.excluir_minha_conta(text)') is null
             or to_regprocedure('public.o_que_excluir_apaga()') is null
             or has_function_privilege('anon', 'public.excluir_minha_conta(text)', 'execute')
             or has_function_privilege('authenticated', 'public.apagar_salao_inteiro(uuid)', 'execute')
             then 'cole o 00_tudo.sql de novo (36_excluir_conta)'
           else '' end
  union all
  /* O modo Pedidos (37_pedidos): as tabelas, a porta da página (aberta a quem
     não entrou, porque a cliente não faz login), a do andamento (fechada a
     ela), o tipo Restaurante e as mensagens do pedido na fila. */
  select 36, 'Pedidos do restaurante',
         case
           when to_regclass('public.pedidos') is null
             or to_regclass('public.pedido_itens') is null
             or to_regprocedure('public.fazer_pedido(text,jsonb)') is null
             or not has_function_privilege('anon', 'public.fazer_pedido(text,jsonb)', 'execute')
             or to_regprocedure('public.mudar_status_pedido(uuid,text,text)') is null
             or has_function_privilege('anon', 'public.mudar_status_pedido(uuid,text,text)', 'execute')
             or public.modelo_de('pedido_confirmado') is distinct from 'agendapro_pedido_confirmado'
             or pg_get_constraintdef((select oid from pg_constraint where conname = 'saloes_tipo_check'
                                       and conrelid = 'public.saloes'::regclass)) not like '%restaurante%'
             or pg_get_constraintdef((select oid from pg_constraint where conname = 'notificacoes_tipo_check'
                                       and conrelid = 'public.notificacoes'::regclass)) not like '%pedido_novo%'
             then 'FALTA'
           else 'certo' end,
         case
           when to_regclass('public.pedidos') is null
             or to_regclass('public.pedido_itens') is null
             or to_regprocedure('public.fazer_pedido(text,jsonb)') is null
             or not has_function_privilege('anon', 'public.fazer_pedido(text,jsonb)', 'execute')
             or to_regprocedure('public.mudar_status_pedido(uuid,text,text)') is null
             or has_function_privilege('anon', 'public.mudar_status_pedido(uuid,text,text)', 'execute')
             or public.modelo_de('pedido_confirmado') is distinct from 'agendapro_pedido_confirmado'
             or pg_get_constraintdef((select oid from pg_constraint where conname = 'saloes_tipo_check'
                                       and conrelid = 'public.saloes'::regclass)) not like '%restaurante%'
             or pg_get_constraintdef((select oid from pg_constraint where conname = 'notificacoes_tipo_check'
                                       and conrelid = 'public.notificacoes'::regclass)) not like '%pedido_novo%'
             then 'cole o 00_tudo.sql de novo (37_pedidos)'
           else '' end
  union all
  /* As filas não prendem (caça-bug, segunda varredura): mensagem que o
     worker tomou e não devolveu vira "falhou" com o motivo, em vez de ficar
     "enviando" para sempre — e a campanha não fica "processando" eterna. */
  select 37, 'Filas que não prendem (agenda e campanhas)',
         case
           when (select prosrc from pg_proc where oid = to_regprocedure('public.notificacao_proxima(integer)'))
                  not like '%sem_resposta%'
             or (select prosrc from pg_proc where oid = to_regprocedure('public.fila_proxima(integer)'))
                  not like '%sem_resposta%'
             then 'FALTA'
           else 'certo' end,
         case
           when (select prosrc from pg_proc where oid = to_regprocedure('public.notificacao_proxima(integer)'))
                  not like '%sem_resposta%'
             or (select prosrc from pg_proc where oid = to_regprocedure('public.fila_proxima(integer)'))
                  not like '%sem_resposta%'
             then 'cole o 00_tudo.sql de novo (10_campanhas e 22_cotas)'
           else '' end
  union all
  /* O modo suporte: a plataforma abre o painel de um salão só olhando, e só
     grava depois de "Liberar edição" — com o que mudou registrado. */
  select 38, 'Modo suporte (só leitura, com "Liberar edição")',
         case
           when to_regprocedure('public.iniciar_suporte(uuid)') is null
             or to_regprocedure('public.contato_do_dono(uuid)') is null
             or to_regclass('public.suporte_alteracoes') is null
             or not exists (select 1 from pg_trigger where tgname = 'zz_suporte'
                              and tgrelid = 'public.servicos'::regclass)
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.iniciar_suporte(uuid)') is null
             or to_regprocedure('public.contato_do_dono(uuid)') is null
             or to_regclass('public.suporte_alteracoes') is null
             or not exists (select 1 from pg_trigger where tgname = 'zz_suporte'
                              and tgrelid = 'public.servicos'::regclass)
             then 'cole o 00_tudo.sql de novo (38_suporte)'
           else '' end
  union all
  /* O teste grátis é um por pessoa: excluir a conta e voltar com o mesmo
     WhatsApp ou e-mail não ganha mais 7 dias. */
  select 39, 'Teste grátis uma vez por WhatsApp e e-mail',
         case
           when to_regclass('public.testes_usados') is null
             or not exists (select 1 from pg_trigger where tgname = 'tg_teste_uma_vez'
                              and tgrelid = 'public.assinaturas'::regclass)
             then 'FALTA'
           else 'certo' end,
         case
           when to_regclass('public.testes_usados') is null
             or not exists (select 1 from pg_trigger where tgname = 'tg_teste_uma_vez'
                              and tgrelid = 'public.assinaturas'::regclass)
             then 'cole o 00_tudo.sql de novo (39_teste_unico)'
           else '' end
  union all
  /* A forma de pagamento nas mensagens: os modelos com valor (MODELOS.md), que a
     plataforma liga no admin depois de aprovados na Meta. "certo" aqui quer
     dizer que o banco sabe montá-los — não que estejam ligados. */
  select 40, 'Mensagens com valor e forma de pagamento (pronto para ligar)',
         case
           when to_regprocedure('public.definir_mensagens_com_pagamento(boolean)') is null
             or not exists (select 1 from pg_trigger where tgname = 'tg_notif_pagamento'
                              and tgrelid = 'public.agendamentos'::regclass)
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.definir_mensagens_com_pagamento(boolean)') is null
             or not exists (select 1 from pg_trigger where tgname = 'tg_notif_pagamento'
                              and tgrelid = 'public.agendamentos'::regclass)
             then 'cole o 00_tudo.sql de novo (21_notificacoes)'
           when public.mensagens_com_pagamento() then 'ligado'
           else 'desligado — ligue no admin depois de aprovar os 4 modelos com valor' end
  union all
  /* A fila do WhatsApp: espera o serviço chegar antes de mandar a confirmação
     (22_cotas) e passa a cada 15 segundos (LIGAR-WHATSAPP.sql). O despertador
     mora no `cron`, que só existe com o pg_cron ligado: lido por
     `query_to_xml`, esta conferência não quebra num banco sem ele. */
  select 41, 'Fila do WhatsApp: a cada 15 segundos, esperando o serviço',
         case
           when not exists (select 1 from pg_proc where proname = 'notificacao_proxima'
                              and prosrc like '%agendamento_servicos%')
             then 'FALTA'
           when to_regclass('cron.job') is not null
                and coalesce((xpath('/table/row/schedule/text()', query_to_xml(
                      'select schedule from cron.job where jobname = ''agendapro-notificacoes''',
                      false, false, '')))[1]::text, '') <> '15 seconds'
             then 'FALTA'
           else 'certo' end,
         case
           when not exists (select 1 from pg_proc where proname = 'notificacao_proxima'
                              and prosrc like '%agendamento_servicos%')
             then 'cole o 00_tudo.sql de novo (22_cotas)'
           when to_regclass('cron.job') is null then ''
           else (select case
                   when x.s is null then 'o despertador não está ligado — rode o LIGAR-WHATSAPP.sql'
                   when x.s = '15 seconds' then 'despertador a cada 15 segundos'
                   else 'o despertador está em "' || x.s
                        || '" — rode o cron.alter_job do LIGAR-WHATSAPP.sql' end
                   from (select (xpath('/table/row/schedule/text()', query_to_xml(
                           'select schedule from cron.job where jobname = ''agendapro-notificacoes''',
                           false, false, '')))[1]::text as s) x)
           end
  union all
  /* O lembrete da cliente acompanha o tempo escolhido em Notificações: a
     varredura que move os lembretes já na fila quando o ajuste muda. */
  select 42, 'Lembrete da cliente segue o tempo de Notificações',
         case
           when to_regprocedure('public.gerar_lembretes_cliente()') is null
             or not exists (select 1 from pg_proc where proname = 'gerar_resumos'
                              and prosrc like '%gerar_lembretes_cliente%')
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.gerar_lembretes_cliente()') is null
             or not exists (select 1 from pg_proc where proname = 'gerar_resumos'
                              and prosrc like '%gerar_lembretes_cliente%')
             then 'cole o 00_tudo.sql de novo (21_notificacoes)'
           else '' end
  union all
  /* O lembrete para o salão SAI na hora dele: antes da correção, a varredura
     que roda antes de cada envio o cancelava exatamente na hora de sair
     ("o horário, quem atende ou o ajuste do lembrete mudou"). */
  select 43, 'Lembrete para o salão sai na hora dele',
         case
           when not exists (select 1 from pg_proc where proname = 'refazer_lembrete_equipe'
                              and prosrc like '%v_chegou%')
             then 'FALTA'
           else 'certo' end,
         case
           when not exists (select 1 from pg_proc where proname = 'refazer_lembrete_equipe'
                              and prosrc like '%v_chegou%')
             then 'cole o 00_tudo.sql de novo (21_notificacoes)'
           else '' end
  union all
  /* O mês das mensagens conta do dia da assinatura, e não do dia 1º. */
  select 44, 'Mensagens contam do dia da assinatura',
         case
           when to_regprocedure('public.ciclo_mensagens(uuid,date)') is null
             or not exists (select 1 from pg_proc where proname = 'mensagens_no_mes'
                              and prosrc like '%ciclo_mensagens%')
             then 'FALTA'
           else 'certo' end,
         case
           when to_regprocedure('public.ciclo_mensagens(uuid,date)') is null
             or not exists (select 1 from pg_proc where proname = 'mensagens_no_mes'
                              and prosrc like '%ciclo_mensagens%')
             then 'cole o 00_tudo.sql de novo (22_cotas)'
           else '' end
  union all
  /* OS ACENTOS. Colado com a codificação errada, o banco fica com "Ã£" no
     lugar de "ã" — no nome do plano que o dono vê e em todo texto das
     funções, inclusive o que vai para a cliente. O padrão ("Ã" seguido de um
     caractere entre U+0080 e U+00BF, que português de verdade nunca tem) é
     montado com chr() para esta conferência funcionar mesmo se ela própria
     tiver sido colada com os acentos trocados. Vem primeiro na lista. */
  select 0, 'Acentos do banco sem troca',
         case
           when exists (select 1 from public.planos
                         where nome ~ (chr(195) || '[' || chr(128) || '-' || chr(191) || ']'))
             or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public'
                           and p.prosrc ~ (chr(195) || '[' || chr(128) || '-' || chr(191) || ']'))
             then 'FALTA'
           else 'certo' end,
         case
           when exists (select 1 from public.planos
                         where nome ~ (chr(195) || '[' || chr(128) || '-' || chr(191) || ']'))
             or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public'
                           and p.prosrc ~ (chr(195) || '[' || chr(128) || '-' || chr(191) || ']'))
             then 'os acentos chegaram trocados: abra o 00_tudo.sql pelo link do GitHub (raw), copie tudo e cole de novo'
           else '' end
)
select item                                as "o que",
       veredito                            as "está",
       nullif(detalhe, '')                 as "detalhe"
  from conferencia
 order by ordem;
