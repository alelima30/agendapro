-- ===========================================================================
-- AgendaPro — os produtos que o salão vende
--
-- ── O QUE ESTE ARQUIVO EXISTE PARA PEGAR ──────────────────────────────────
-- O módulo 24 é pequeno, e é justamente por isso que ele tem uma decisão fácil
-- de desfazer sem querer: `venda_online` NASCE FALSO.
--
-- Em `servicos` o equivalente nasce TRUE. Alguém lendo os dois lado a lado vai
-- achar que é esquecimento e "corrigir" — e nesse dia todo produto que o salão
-- cadastrou para o caixa interno aparece na internet de uma vez, com o preço
-- de balcão, sem ninguém ter decidido isso.
--
-- É o tipo de regressão que não quebra nada: tudo continua funcionando, só que
-- publicado.
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── Cenário: um salão no plano Grátis, que é o que tem o teto mais baixo ───
insert into auth.users (id) values
  ('a1000000-0000-0000-0000-00000000000a') on conflict do nothing;
insert into public.perfis (id, nome, email) values
  ('a1000000-0000-0000-0000-00000000000a', 'Dona do Balcão', 'balcao@teste.com')
  on conflict (id) do update
    set nome = excluded.nome, email = excluded.email;
insert into public.saloes (id, slug, nome) values
  ('a1000000-1111-0000-0000-00000000000b', 'salao-produtos', 'Salão com Produtos');
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a1000000-0000-0000-0000-00000000000a',
   'a1000000-1111-0000-0000-00000000000b', 'dono', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values
  ('a1000000-1111-0000-0000-00000000000b', 'gratuito', 'ativa');

\echo ''
\echo 'AS COLUNAS QUE A TELA PRECISA'

select t_verdade('produtos ganhou foto, descricao e venda_online',
  (select count(*) = 3 from information_schema.columns
    where table_schema = 'public' and table_name = 'produtos'
      and column_name in ('foto','descricao','venda_online')));

\echo ''
\echo 'E A DECISÃO QUE É FÁCIL DESFAZER SEM QUERER'

insert into public.produtos (salao_id, nome, preco) values
  ('a1000000-1111-0000-0000-00000000000b', 'Shampoo sem sal', 45.00);

/* ⚠ NASCE FECHADO.

   Produto cadastrado para o caixa interno não vai para a internet sozinho.
   Quem publica é o dono, na mão — inclusive porque o preço de balcão pode não
   ser o preço que ele quer anunciar. Em `servicos` o padrão é o contrário, e
   é essa diferença que alguém vai tentar "uniformizar" um dia. */
select t_falso('produto novo NÃO nasce à venda na página pública',
  (select venda_online from public.produtos
    where salao_id = 'a1000000-1111-0000-0000-00000000000b'));

-- E o contrário, para esta verificação não passar com uma coluna que é sempre
-- falsa: ligar tem que funcionar.
update public.produtos set venda_online = true
 where salao_id = 'a1000000-1111-0000-0000-00000000000b';
select t_verdade('mas o dono consegue ligar',
  (select venda_online from public.produtos
    where salao_id = 'a1000000-1111-0000-0000-00000000000b'));

\echo ''
\echo 'O TETO DO PLANO'

/* Devolve a mensagem do banco, ou null quando passou. */
create or replace function criou_produto(p_salao uuid, p_nome text)
returns text language plpgsql as $$
begin
  insert into public.produtos (salao_id, nome, preco) values (p_salao, p_nome, 10.00);
  return null;
exception when others then return sqlerrm; end $$;

-- O teto do Grátis, lido da tabela — nunca escrito à mão aqui.
select (recursos->>'max_produtos')::int as teto_gratis
  from public.planos where codigo = 'gratuito' \gset

select t_verdade('o plano Grátis tem teto de produtos',
  :teto_gratis > 0);

-- Completa até o teto. Já existe 1; faltam teto-1.
do $$
declare i int; teto int;
begin
  teto := public.recurso_num('a1000000-1111-0000-0000-00000000000b', 'max_produtos');
  for i in 2..teto loop
    insert into public.produtos (salao_id, nome, preco)
    values ('a1000000-1111-0000-0000-00000000000b', 'Produto ' || i, 10.00);
  end loop;
end $$;

select t_igual('o salão chegou exatamente ao teto',
  (select count(*) from public.produtos
    where salao_id = 'a1000000-1111-0000-0000-00000000000b'), :teto_gratis::bigint);

select t_verdade('e o próximo é recusado, com o número na mensagem',
  criou_produto('a1000000-1111-0000-0000-00000000000b', 'Um a mais')
    like 'O seu plano cobre%produtos%');

/* ⚠ E O TETO NÃO PODE TRAVAR QUEM ESTÁ SE AJUSTANDO.
   O gatilho é só de INSERT de propósito: um salão que baixou de plano precisa
   continuar conseguindo CORRIGIR o preço do que já cadastrou. Cobrar no UPDATE
   faria o teto punir exatamente quem está tentando se acertar. */
update public.produtos set preco = 39.90
 where salao_id = 'a1000000-1111-0000-0000-00000000000b' and nome = 'Shampoo sem sal';
select t_verdade('no teto, editar o que já existe continua funcionando',
  (select preco = 39.90 from public.produtos
    where salao_id = 'a1000000-1111-0000-0000-00000000000b'
      and nome = 'Shampoo sem sal'));

\echo ''
\echo 'E O DONO VÊ A BARRA ANTES DE BATER NO TETO'

/* `uso_do_plano` exige `e_gestor`, que pergunta pelo `auth.uid()`. Rodando
   como superusuário não há sessão nenhuma, e ela recusa com razão. */
select set_config('request.jwt.claim.sub',
                  'a1000000-0000-0000-0000-00000000000a', false);

select t_igual('uso_do_plano conta os produtos',
  ((public.uso_do_plano('a1000000-1111-0000-0000-00000000000b')
     ->'produtos'->>'usado')::int)::bigint, :teto_gratis::bigint);
select t_igual('e mostra o teto, para a barra ter fim',
  ((public.uso_do_plano('a1000000-1111-0000-0000-00000000000b')
     ->'produtos'->>'teto')::int)::bigint, :teto_gratis::bigint);

/* As outras chaves não podem sumir quando esta função é reescrita — foi uma
   cópia inteira, e cópia inteira é onde se perde uma linha sem notar. */
select t_verdade('e as quatro chaves antigas continuam lá',
  (select public.uso_do_plano('a1000000-1111-0000-0000-00000000000b'))
    ?& array['profissionais','clientes','servicos','mensagens']);

select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo 'E O CATÁLOGO NÃO É PÚBLICO — O CUSTO MORA NELE'

/* Enquanto a loja não existe, ninguém sem login lê `produtos`. E quando ela
   existir, quem publica é a `vitrine()`, nomeando campo por campo: `custo` é
   quanto o dono paga pelo produto, e publicar isso entrega a margem dele a
   qualquer concorrente que abra a página. */
select t_falso('anon não lê a tabela de produtos',
  has_table_privilege('anon', 'public.produtos', 'SELECT'));
select t_falso('nem escreve',
  has_table_privilege('anon', 'public.produtos', 'INSERT'));

select t_verdade('a tabela tem RLS ligado',
  (select relrowsecurity from pg_class where oid = 'public.produtos'::regclass));

/* O gatilho roda como dono. Sem `security definer` ele rodaria como quem fez o
   INSERT e exigiria que a dona do salão pudesse executar `recurso_num()` —
   que é exatamente como o `comanda_numera` quebrou abrir comanda em produção. */
select t_verdade('o gatilho do teto é security definer',
  (select prosecdef from pg_proc where proname = 'checar_limite_produtos'));
