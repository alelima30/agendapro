-- ===========================================================================
-- PRECOS.sql — todos os planos no preço de tabela, para todo mundo
--
-- Cole no SQL Editor do Supabase e rode UMA vez. Serve para desfazer o teste
-- de R$ 1,00: o Essencial a R$ 1 (no plano ou como "preço especial" de um
-- salão) volta ao valor certo, e nenhum salão fica com preço diferente.
--
-- Por que é um arquivo à parte, e não parte do 00_tudo.sql: preço é decisão
-- comercial. O 00_tudo, colado de novo, NUNCA mexe em preço — senão um preço
-- que você mudasse amanhã voltaria sozinho na próxima colagem. Este arquivo
-- mexe, de propósito, e só quando você o roda.
--
-- Para mudar um preço no futuro, troque o número na lista abaixo e rode de
-- novo.
-- ===========================================================================

update public.planos p
   set preco_mes = v.preco
  from (values
          ('gratuito',     0.00),
          ('trial',        0.00),
          ('basico',      49.90),
          ('individual',  97.00),
          ('duo',        157.00),
          ('time',       197.00),
          ('equipe',     297.00),
          ('salao',      497.00)
       ) as v(codigo, preco)
 where p.codigo = v.codigo;

-- Os preços especiais por salão (13_cobranca, 1b) também saem: todo mundo
-- paga a tabela. Para dar desconto a um salão depois, use o preço especial
-- dele de novo — os cupons do sistema são do salão para as clientes dele, e
-- não descontam a mensalidade do AgendaPro.
update public.assinaturas
   set precos_especiais = '{}'::jsonb
 where precos_especiais is distinct from '{}'::jsonb;

-- O resultado, para conferir na tela do Supabase.
select codigo, nome, preco_mes
  from public.planos
 order by ordem, codigo;
