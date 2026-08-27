-- ===========================================================================
-- AgendaPro — "eu já rodei o 98_modulos.sql?"
--
-- Cole no SQL Editor do Supabase e clique em Run. Devolve UMA linha.
--
-- ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
-- É a pergunta mais frequente entre uma publicação e a colagem seguinte, e
-- ela não tinha resposta rápida: o `conferir_instalacao.sql` tem 400 linhas
-- e confere o schema inteiro — bom para depois de instalar, demais para
-- "será que eu colei?".
--
-- E ninguém de fora consegue responder pelo dono: o banco é dele, e o painel
-- não tem como saber o que está instalado sem tentar e falhar.
--
-- ── COMO ELE DECIDE ────────────────────────────────────────────────────────
-- Procura o MARCO de cada módulo — uma função ou tabela que só existe se
-- aquele arquivo rodou. Não confere o módulo inteiro de propósito: quem cola
-- o 98_modulos.sql cola inteiro, então o marco basta, e um arquivo curto é
-- um arquivo que a pessoa realmente usa.
--
-- O veredito olha os DOIS marcos mais novos — `painel_hoje` e a coluna `id`
-- do par serviço+profissional. É o par que importa: dá para ter rodado uma
-- versão de ontem, com o painel já lá, e não ter a coluna do par. Nesse
-- estado a tela de preço por profissional grava e PERDE linha em silêncio,
-- que é o pior defeito que este projeto já teve.
--
-- Conferido nos dois sentidos antes de existir: num banco completo diz
-- "TUDO INSTALADO", e num banco com só a base antiga diz "FALTA COLAR".
-- ===========================================================================

select
  case when to_regprocedure('public.relatorio(uuid,date,date)') is null
       then '✗ FALTA'  else '✓ ok' end                          as "12 relatórios",
  case when to_regprocedure('public.abrir_cobranca(uuid,text,text,uuid)') is null
       then '✗ FALTA'  else '✓ ok' end                          as "13 cobrança",
  case when to_regprocedure('public.avaliar_horario(uuid,timestamptz,timestamptz,uuid)') is null
       then '✗ FALTA'  else '✓ ok' end                          as "14 motor",
  case when to_regclass('public.comanda_itens_calculados') is null
       then '✗ FALTA'  else '✓ ok' end                          as "16 comissão",
  case when to_regclass('public.caixas') is null
       then '✗ FALTA'  else '✓ ok' end                          as "17 caixa",
  case when to_regprocedure('public.painel_hoje(uuid,date)') is null
       then '✗ FALTA'  else '✓ ok' end                          as "18 painel",
  case when not exists (select 1 from information_schema.columns
                         where table_name = 'servicos_profissionais'
                           and column_name = 'id')
       then '✗ FALTA'  else '✓ ok' end                          as "par com id",
  case when to_regprocedure('public.painel_hoje(uuid,date)') is not null
        and exists (select 1 from information_schema.columns
                     where table_name = 'servicos_profissionais'
                       and column_name = 'id')
       then 'TUDO INSTALADO — nada a fazer'
       else 'FALTA COLAR o 98_modulos.sql mais recente' end     as "veredito";
