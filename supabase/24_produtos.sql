-- ===========================================================================
-- AgendaPro — 24: produtos que o salão vende
--
-- ── O QUE ESTE ARQUIVO DESTRAVA ───────────────────────────────────────────
-- A tabela `public.produtos` existe desde o 01_schema, a comanda já vende
-- produto, e a escada do 16_comissao já calcula comissão sobre produto.
--
-- Só que NÃO HAVIA TELA PARA CADASTRAR UM. O painel lê `bd.produtos` em três
-- lugares e o seletor de produtos da comanda está sempre vazio, porque não
-- existe por onde criar. Metade de uma função construída, e morta na água.
--
-- Este módulo é a metade que faltava: as colunas que a tela precisa, o teto
-- por plano no mesmo mecanismo das outras cotas, e o produto entrando na tela
-- "Meu Plano" ao lado de clientes e serviços.
--
-- ── ⚠ `venda_online` NASCE FALSO, E ISSO É DECISÃO ────────────────────────
-- Em `servicos` o equivalente (`aceita_online`) nasce TRUE, e está certo: um
-- serviço é cadastrado para ser marcado.
--
-- Produto é outra coisa. Os que já existirem foram cadastrados para o caixa
-- interno, e publicá-los sozinho na internet seria o SISTEMA tomando uma
-- decisão que é do dono — inclusive sobre coisas que ele pode não querer
-- anunciar, ou cujo preço de vitrine é outro. Quem liga, liga na mão.
--
-- ── O QUE NÃO ESTÁ AQUI ───────────────────────────────────────────────────
-- A loja na página da cliente é a fase seguinte, e ela tem uma asserção que
-- vale dinheiro: `custo` e `comissao_pct` NÃO podem sair na vitrine. `custo` é
-- quanto o dono paga pelo produto; publicar isso entrega a margem dele a
-- qualquer concorrente que abra a página. Quando a `vitrine()` passar a
-- devolver produtos, vai nomear campo por campo, nunca a linha inteira.
--
-- E o `estoque` continua DECORATIVO: nada no sistema o diminui, nem a comanda.
-- Ele serve, por enquanto, para o dono se organizar. Fazer a comanda dar baixa
-- é trabalho separado, útil sozinho, e é o que transforma esse número em
-- verdade.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS COLUNAS QUE A TELA PRECISA
-- ---------------------------------------------------------------------------

/* A foto é o que faz a cliente escolher — mesmo papel que `servicos.foto`, e
   mesmo formato: a URL pública do balde `salao`, com a chave
   `<salao_id>/produto-<produto_id>.jpg`.

   Não precisa de policy nova: a do 04_imagens confere apenas a PRIMEIRA pasta
   do caminho (o uuid do salão), então qualquer nome de arquivo dentro dela já
   está coberto. */
alter table public.produtos add column if not exists foto text;

/* "Shampoo" não vende; "shampoo sem sal, 300ml, para cabelo com química"
   vende. Anulável: salão pequeno começa sem escrever nada. */
alter table public.produtos add column if not exists descricao text;

alter table public.produtos
  add column if not exists venda_online boolean not null default false;

/* A busca da tela e do RLS é sempre por salão. Sem índice, cada leitura varre
   a tabela inteira da plataforma — o que num banco compartilhado por muitos
   salões deixa de ser detalhe assim que o primeiro catálogo cresce. */
create index if not exists ix_produto_salao
  on public.produtos(salao_id) where ativo;

comment on column public.produtos.venda_online is
  'Se aparece na loja da página pública. Nasce falso de propósito.';

-- ---------------------------------------------------------------------------
-- 2) O TETO POR PLANO
--
-- Mesmo mecanismo de `max_clientes` e `max_servicos`: uma chave no
-- `planos.recursos`, lida por `recurso_num()`. Ausente quer dizer sem teto, e
-- é a convenção que este projeto já usa.
--
-- Os números acompanham os de serviço. Catálogo não custa nada ao sistema —
-- o teto existe para o plano Grátis não virar hospedagem de catálogo, não
-- para espremer quem paga.
-- ---------------------------------------------------------------------------
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 10)
  where codigo = 'gratuito';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 50)
  where codigo in ('trial','individual');
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 100)
  where codigo = 'duo';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 200)
  where codigo = 'time';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 350)
  where codigo = 'equipe';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 500)
  where codigo = 'salao';

create or replace function public.checar_limite_produtos()
returns trigger language plpgsql security definer set search_path = public as $$
declare teto int; usados int;
begin
  teto := public.recurso_num(new.salao_id, 'max_produtos');
  if teto is null then return new; end if;
  select count(*) into usados from public.produtos where salao_id = new.salao_id;
  if usados >= teto then
    raise exception 'O seu plano cobre % produtos, e o salão já tem %. Mude de plano para cadastrar mais.',
      teto, usados using errcode = 'check_violation';
  end if;
  return new;
end $$;

/* Só no INSERT, como os outros tetos deste projeto. Cobrar no UPDATE deixaria
   um salão que baixou de plano sem conseguir sequer CORRIGIR o preço do que
   já cadastrou — o teto passaria a punir quem está tentando se ajustar. */
drop trigger if exists tg_limite_produtos on public.produtos;
create trigger tg_limite_produtos before insert on public.produtos
  for each row execute function public.checar_limite_produtos();

-- ---------------------------------------------------------------------------
-- 3) PRODUTOS NA TELA "MEU PLANO"
--
-- A função inteira é reescrita porque ela devolve um jsonb montado à mão e
-- ganhou uma chave. Sem isto o dono bate no teto sem nunca ter visto uma barra
-- se encher — que é o pior jeito de descobrir um limite.
-- ---------------------------------------------------------------------------
create or replace function public.uso_do_plano(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_plano text;
  v_nome  text;
  v_preco numeric;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;

  select a.plano, pl.nome, pl.preco_mes into v_plano, v_nome, v_preco
    from public.assinaturas a
    join public.planos pl on pl.codigo = a.plano
   where a.salao_id = p_salao;

  return jsonb_build_object(
    'plano', v_plano, 'nome', v_nome, 'precoMes', v_preco,
    'profissionais', jsonb_build_object(
      'usado', (select count(*) from public.profissionais
                 where salao_id = p_salao and ativo),
      'teto',  (select max_profissionais from public.planos where codigo = v_plano)),
    'clientes', jsonb_build_object(
      'usado', (select count(*) from public.clientes where salao_id = p_salao),
      'teto',  public.recurso_num(p_salao, 'max_clientes')),
    'servicos', jsonb_build_object(
      'usado', (select count(*) from public.servicos where salao_id = p_salao),
      'teto',  public.recurso_num(p_salao, 'max_servicos')),
    'produtos', jsonb_build_object(
      'usado', (select count(*) from public.produtos where salao_id = p_salao),
      'teto',  public.recurso_num(p_salao, 'max_produtos')),
    'mensagens', jsonb_build_object(
      'usado', public.mensagens_no_mes(p_salao),
      'teto',  public.teto_mensagens(p_salao)));
end $$;

revoke all on function public.uso_do_plano(uuid) from public, anon;
grant execute on function public.uso_do_plano(uuid) to authenticated;

/* O gatilho roda como dono, e é o que o `portas.test.sql` cobra de TODO
   gatilho deste projeto: sem `security definer` ele rodaria como quem fez o
   INSERT, e exigiria que a própria dona do salão tivesse permissão de executar
   `recurso_num()`. Já aconteceu aqui, com o `comanda_numera`, e quebrou abrir
   comanda em produção. */
revoke all on function public.checar_limite_produtos() from public, anon, authenticated;
