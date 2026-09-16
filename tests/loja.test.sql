-- ===========================================================================
-- AgendaPro — a loja pública, e o que ela NÃO pode publicar
--
-- ── A VERIFICAÇÃO QUE VALE DINHEIRO ───────────────────────────────────────
-- `produtos.custo` é quanto o DONO paga pelo produto. A `vitrine()` é
-- `security definer` e responde a QUALQUER PESSOA, sem login — é assim que a
-- página da cliente funciona. Um `to_jsonb(pr)` no lugar dos campos nomeados
-- entregaria a margem do salão a qualquer concorrente que abrisse a página, e
-- nada quebraria: a loja continuaria funcionando, só que publicando o custo.
--
-- Foi exatamente essa a forma dos três vazamentos que a varredura de segurança
-- deste projeto encontrou. Por isso aqui a conferência não é "o custo está
-- certo" — é "o custo NÃO ESTÁ LÁ".
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── Cenário: um salão com dois produtos, um publicado e um só de balcão ───
insert into auth.users (id) values
  ('b1000000-0000-0000-0000-00000000000a') on conflict do nothing;
insert into public.perfis (id, nome, email) values
  ('b1000000-0000-0000-0000-00000000000a', 'Dona da Loja', 'loja@teste.com')
  on conflict (id) do update
    set nome = excluded.nome, email = excluded.email;
insert into public.saloes (id, slug, nome, whatsapp, status) values
  ('b1000000-1111-0000-0000-00000000000b', 'salao-loja', 'Salão com Loja',
   '11988887777', 'ativo');
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('b1000000-0000-0000-0000-00000000000a',
   'b1000000-1111-0000-0000-00000000000b', 'dono', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values
  ('b1000000-1111-0000-0000-00000000000b', 'duo', 'ativa');

insert into public.produtos
  (id, salao_id, nome, marca, descricao, preco, custo, comissao_pct,
   estoque, ativo, venda_online) values
  ('b1000000-2222-0000-0000-00000000000c',
   'b1000000-1111-0000-0000-00000000000b', 'Shampoo sem sal', 'MarcaX',
   'Para cabelo com química', 45.00, 18.00, 15.00, 0, true, true),
  ('b1000000-2222-0000-0000-00000000000d',
   'b1000000-1111-0000-0000-00000000000b', 'Pomada do balcão', 'MarcaY',
   null, 30.00, 12.00, 10.00, 50, true, false);

\echo ''
\echo 'O QUE A LOJA PUBLICA'

select t_igual('só o produto marcado aparece',
  jsonb_array_length(public.vitrine('salao-loja')->'produtos')::bigint, 1::bigint);

select t_texto('e é o certo',
  public.vitrine('salao-loja')->'produtos'->0->>'nome', 'Shampoo sem sal');

select t_texto('com o preço de venda',
  public.vitrine('salao-loja')->'produtos'->0->>'preco', '45.00');

select t_texto('e a descrição, que é o que faz escolher',
  public.vitrine('salao-loja')->'produtos'->0->>'descricao',
  'Para cabelo com química');

\echo ''
\echo 'E O QUE ELA NÃO PUBLICA — ESTA É A SEÇÃO QUE IMPORTA'

/* ⚠ Cada campo por nome. Uma verificação genérica ("não vazou nada") passaria
   com uma lista vazia, e é justamente o que aconteceria se alguém quebrasse a
   consulta. As de cima garantem que TEM produto; estas garantem o que falta
   dentro dele. */
select t_falso('o CUSTO não sai — é a margem do dono',
  public.vitrine('salao-loja')->'produtos'->0 ? 'custo');
select t_falso('nem a comissão, que é o acerto dele com a equipe',
  public.vitrine('salao-loja')->'produtos'->0 ? 'comissaoPct');
select t_falso('nem em snake_case, que é como a coluna se chama',
  public.vitrine('salao-loja')->'produtos'->0 ? 'comissao_pct');
select t_falso('nem o estoque',
  public.vitrine('salao-loja')->'produtos'->0 ? 'estoque');

/* E a prova pelo valor, não só pela chave: 18.00 é o custo do shampoo, e ele
   não pode aparecer em canto nenhum do que a página pública recebe. */
select t_falso('e o número do custo não aparece em lugar nenhum da vitrine',
  public.vitrine('salao-loja')::text like '%18.00%');

\echo ''
\echo 'O INTERRUPTOR DA LOJA'

select t_verdade('a loja nasce ligada, porque o produto já nasce fechado',
  (public.vitrine('salao-loja')->'salao'->>'loja')::boolean);

update public.saloes set cfg = cfg || '{"loja": false}'::jsonb
 where slug = 'salao-loja';

select t_falso('o dono consegue pausar a loja inteira',
  (public.vitrine('salao-loja')->'salao'->>'loja')::boolean);
select t_igual('e aí nenhum produto sai, sem ele desmarcar nada',
  jsonb_array_length(public.vitrine('salao-loja')->'produtos')::bigint, 0::bigint);

update public.saloes set cfg = cfg - 'loja' where slug = 'salao-loja';
select t_igual('e volta ao religar',
  jsonb_array_length(public.vitrine('salao-loja')->'produtos')::bigint, 1::bigint);

\echo ''
\echo 'O ESTOQUE NÃO GOVERNA A LOJA — E ISSO É DE PROPÓSITO'

/* O shampoo publicado está com estoque ZERO, que é o default da coluna. Se a
   loja escondesse o que está zerado, todo produto recém-cadastrado nasceria
   esgotado e o dono passaria a tarde procurando o defeito.

   Nada no sistema movimenta `estoque` — nem a comanda. Quando movimentar, o
   "esgotado" entra aqui, com um teste que hoje não teria como existir. */
select t_igual('produto com estoque zero continua à venda',
  (select count(*) from public.produtos
    where id = 'b1000000-2222-0000-0000-00000000000c' and estoque = 0), 1::bigint);
select t_igual('e aparece na loja mesmo assim',
  jsonb_array_length(public.vitrine('salao-loja')->'produtos')::bigint, 1::bigint);

\echo ''
\echo 'E NENHUMA CHAVE ANTIGA SUMIU NA CÓPIA'

/* ⚠ A `vitrine()` foi recortada inteira para ganhar uma chave. Cópia inteira é
   onde se perde uma linha sem ninguém notar — e o sintoma seria mudo: o dono
   escolhe um ajuste, o painel grava, a prévia obedece, e a página da cliente
   continua igual. Já aconteceu neste projeto, com `cartoes`. */
select t_verdade('o objeto salão manteve tudo o que tinha',
  (public.vitrine('salao-loja')->'salao') ?& array[
    'id','slug','nome','tipo','logo','capa','telefone','whatsapp',
    'endereco','fuso','diasLiberados','cor','tema','precoNaCapa','cartoes']);
select t_verdade('e a vitrine continua trazendo serviços e profissionais',
  (public.vitrine('salao-loja')) ?& array['salao','servicos','profissionais','produtos']);

\echo ''
\echo 'E O CATÁLOGO CRU CONTINUA FECHADO'

/* A loja publica pela `vitrine()`, que é `security definer` e escolhe o que
   sai. A TABELA continua inalcançável — senão bastaria pedir `produtos?select=*`
   com a chave publicável para levar custo e comissão de todo salão. */
select t_falso('anon não lê a tabela de produtos',
  has_table_privilege('anon', 'public.produtos', 'SELECT'));
