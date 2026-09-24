-- ===========================================================================
-- AgendaPro — 32: o que faltava no cadastro de produto
--
-- Três coisas, vindas da comparação com os prints que o dono mandou:
--
--   1. o PREÇO pode ficar escondido da cliente sem esconder o produto;
--   2. cada PROFISSIONAL pode ter comissão própria naquele produto;
--   3. o estoque passa a ter HISTÓRICO — quem mexeu, quando, e por quê.
--
-- A coluna `preco_visivel` é declarada no 25_loja.sql, junto com
-- `servicos.dias` e pelo mesmo motivo do Postgres: a `vitrine()` é função SQL,
-- o `create or replace` compila o corpo na hora, e nas duas montagens o 25
-- roda antes deste arquivo. O comentário completo está lá.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O PREÇO ESCONDIDO — e por que não é o mesmo que esconder o produto
--
-- `venda_online` já decide se o produto APARECE na loja. Este é outro eixo: o
-- produto aparece, com foto e nome, e o valor sai por WhatsApp.
--
-- Não é firula de vitrine. Produto de revenda com preço tabelado pelo
-- fabricante, produto que o salão vende mais caro que a farmácia da esquina,
-- e produto cujo preço muda toda semana — nos três casos o dono quer mostrar
-- que tem, e não quer publicar quanto custa.
--
-- ⚠ PADRÃO `true`, e é o que faz esta linha não mudar nada. Todo produto que
-- já existe passa a ter `preco_visivel = true`, que é exatamente o que a loja
-- faz hoje. Ninguém acorda com a loja diferente.
-- ---------------------------------------------------------------------------
comment on column public.produtos.preco_visivel is
  'O preço aparece na loja do link? Padrão true — o que a loja sempre fez. False mostra o produto sem o valor, e a cliente pergunta no WhatsApp.';

-- ---------------------------------------------------------------------------
-- 2) COMISSÃO DO PRODUTO POR PROFISSIONAL
--
-- Espelho de `servicos_profissionais`, e de propósito: a mesma ideia com duas
-- formas diferentes dentro do mesmo banco é convite para erro.
--
-- ⚠ `id` PRÓPRIO, E NÃO SÓ A CHAVE DO PAR. É a mesma lição que
-- `servicos_profissionais` aprendeu doendo: o `Dados.subir()` compara os
-- retratos por `id`, e linha sem ele vira a chave `undefined` — duas viram a
-- mesma, a segunda sobrescreve a primeira, e sobe UMA. Sem erro nenhum. O
-- dono cadastraria a comissão de cinco pessoas e o banco ficaria com uma.
-- ---------------------------------------------------------------------------
create table if not exists public.produtos_profissionais (
  id             uuid primary key default gen_random_uuid(),
  produto_id     uuid not null references public.produtos(id) on delete cascade,
  profissional_id uuid not null references public.profissionais(id) on delete cascade,
  /* Anuláveis, e é o ponto: nulo quer dizer "este degrau não fala em
     comissão, herda de baixo". Zero quer dizer "fala, e é zero". A diferença
     é o que permite escrever "a Ana ganha 20% em tudo, menos neste produto,
     onde não ganha nada". */
  comissao_pct   numeric(5,2) check (comissao_pct between 0 and 100),
  comissao_fixa  numeric(10,2) check (comissao_fixa >= 0),
  unique (produto_id, profissional_id)
);

comment on table public.produtos_profissionais is
  'Exceção de comissão de um produto para um profissional. Linha ausente = usa a comissão do produto. Espelho de servicos_profissionais.';

alter table public.produtos_profissionais enable row level security;

/* As mesmas duas policies de `servicos_profissionais`, pelo mesmo desenho:
   quem tem acesso ao salão LÊ, quem é gestão ESCREVE.

   ⚠ E separadas por verbo, nunca `for all` numa só. Policy `for all` vale
   também para SELECT, e o Postgres soma as permissivas com OU: uma policy de
   escrita da gestão ao lado de uma de leitura restrita anula a restrição. É
   um dos dois defeitos que os testes deste projeto pegaram antes de existir
   tela, e está no README. */
drop policy if exists pp_ler on public.produtos_profissionais;
create policy pp_ler on public.produtos_profissionais for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and tem_acesso(p.salao_id)) );
drop policy if exists pp_gerir on public.produtos_profissionais;
create policy pp_gerir on public.produtos_profissionais for all to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and e_gestor(p.salao_id)) )
  with check ( exists (select 1 from public.produtos p
                        where p.id = produto_id and e_gestor(p.salao_id)) );

grant select, insert, update, delete on public.produtos_profissionais to authenticated;

-- ---------------------------------------------------------------------------
-- 2b) A ESCADA DA COMISSÃO, COM O DEGRAU DO PRODUTO NO PAR
--
-- ⚠ VAI INTEIRA. `create or replace function` não acrescenta linha: o corpo
-- que estiver aqui é o que vale. Esta é cópia fiel da versão do
-- 16_comissao.sql com o ramo do produto no degrau 1.
--
-- ⚠ E ESTA FUNÇÃO DECIDE DINHEIRO. O que ela devolve é congelado dentro da
-- comanda pelo gatilho — quer dizer que um erro aqui não aparece na tela: ele
-- aparece no acerto do mês, semanas depois, quando a profissional conferir o
-- que recebeu. Por isso o degrau novo é o PRIMEIRO e não muda mais nada:
-- produto sem linha no par cai exatamente onde caía antes.
--
-- A ordem dos quatro degraus continua a mesma, e ela é a regra do negócio:
--   1. o par     — "a Ana ganha 30% nesta pomada"
--   2. o catálogo— "esta pomada paga 15% para quem vender"
--   3. a pessoa  — "a Ana ganha 20% em tudo"
--   4. zero      — ninguém disse nada
-- ---------------------------------------------------------------------------
create or replace function public.comissao_de(
  p_tipo text, p_servico uuid, p_produto uuid, p_profissional uuid,
  out pct numeric, out fixa numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  -- 1) o par
  if p_tipo = 'servico' and p_servico is not null and p_profissional is not null then
    select sp.comissao_pct, sp.comissao_fixa into pct, fixa
      from public.servicos_profissionais sp
     where sp.servico_id = p_servico and sp.profissional_id = p_profissional
       and (sp.comissao_pct is not null or sp.comissao_fixa is not null);
    if found then
      return;
    end if;
  elsif p_tipo = 'produto' and p_produto is not null and p_profissional is not null then
    /* O degrau novo. A mesma exigência do ramo do serviço: a linha só vale se
       DISSER alguma coisa. Uma linha com os dois campos nulos existe para
       nada — e, se valesse, pararia a escada aqui e devolveria nulo, que é
       zero por outro caminho. A pessoa perderia a comissão do produto e
       ninguém saberia por quê. */
    select pp.comissao_pct, pp.comissao_fixa into pct, fixa
      from public.produtos_profissionais pp
     where pp.produto_id = p_produto and pp.profissional_id = p_profissional
       and (pp.comissao_pct is not null or pp.comissao_fixa is not null);
    if found then
      return;
    end if;
  end if;

  -- 2) o catálogo
  if p_tipo = 'servico' and p_servico is not null then
    select sv.comissao_pct, sv.comissao_fixa into pct, fixa
      from public.servicos sv
     where sv.id = p_servico
       and (sv.comissao_pct is not null or sv.comissao_fixa is not null);
    if found then
      return;
    end if;
  elsif p_tipo = 'produto' and p_produto is not null then
    -- Produto sempre diz alguma coisa: `comissao_pct` é not null aqui.
    select pd.comissao_pct, pd.comissao_fixa into pct, fixa
      from public.produtos pd
     where pd.id = p_produto;
    if found then
      return;
    end if;
  end if;

  -- 3) a pessoa
  if p_profissional is not null then
    select pr.comissao_pct, pr.comissao_fixa into pct, fixa
      from public.profissionais pr
     where pr.id = p_profissional;
    if found then
      return;
    end if;
  end if;

  -- 4) ninguém disse nada
  pct := 0; fixa := 0;
end $$;

comment on function public.comissao_de(text, uuid, uuid, uuid) is
  'A escada: par, catálogo, pessoa, zero. Vale para serviço e para produto. Não aceita taxa por parâmetro.';

revoke all on function public.comissao_de(text, uuid, uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) O HISTÓRICO DO ESTOQUE
--
-- `produtos.estoque` diz quanto TEM. Não diz como chegou ali, e é a segunda
-- pergunta que todo dono faz quando o número não bate com a prateleira:
-- "quem mexeu nisso?".
--
-- ── ⚠ UM LUGAR SÓ ESCREVE, E É O QUE EVITA CONTAR DUAS VEZES ──────────────
-- O estoque muda por dois caminhos: a comanda fechando (o 26_estoque) e o
-- dono digitando outro número no cadastro. A tentação é registrar nos dois
-- lugares — e aí a baixa da comanda vira DUAS linhas no histórico, porque o
-- 26 mexe na mesma coluna que o gatilho do cadastro observa.
--
-- Então quem escreve é um gatilho só, na própria `produtos`, que vê toda
-- mudança da coluna venha de onde vier. O MOTIVO é que viaja: o 26 avisa,
-- antes de baixar, que aquela mudança é uma venda. Quem não avisar é ajuste.
--
-- ⚠ O aviso é `set_config(..., true)` — LOCAL À TRANSAÇÃO. Sem o `true` ele
-- valeria para a conexão inteira, e a conexão é reaproveitada: o próximo
-- ajuste à mão de qualquer salão sairia rotulado como venda daquela comanda.
-- ---------------------------------------------------------------------------
create table if not exists public.estoque_mov (
  id         uuid primary key default gen_random_uuid(),
  produto_id uuid not null references public.produtos(id) on delete cascade,
  de         numeric(10,2) not null,
  para       numeric(10,2) not null,
  motivo     text not null default 'ajuste',
  comanda_id uuid references public.comandas(id) on delete set null,
  quem       uuid references public.perfis(id) on delete set null,
  criado_em  timestamptz not null default now()
);

create index if not exists ix_estoque_mov_produto
  on public.estoque_mov (produto_id, criado_em desc);

comment on table public.estoque_mov is
  'Toda mudança de produtos.estoque, com de/para e o motivo. Escrita só pelo gatilho tg_produto_estoque_mov.';

alter table public.estoque_mov enable row level security;

/* ⚠ SÓ LEITURA, E SÓ PARA QUEM TEM ACESSO AO SALÃO. Não existe policy de
   escrita de propósito: quem grava é o gatilho, que é `security definer` e
   não passa por RLS. Histórico que a tela pode escrever não é histórico — é
   um campo de texto com outro nome. */
drop policy if exists em_ler on public.estoque_mov;
create policy em_ler on public.estoque_mov for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and tem_acesso(p.salao_id)) );

grant select on public.estoque_mov to authenticated;

create or replace function public.tg_produto_estoque_mov()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_motivo  text;
  v_comanda uuid;
begin
  -- Gravar o mesmo número por cima não é movimento. O painel salva o produto
  -- inteiro a cada edição, então isto acontece o tempo todo.
  if new.estoque is not distinct from old.estoque then
    return null;
  end if;

  v_motivo  := coalesce(nullif(current_setting('agendapro.mov_motivo', true), ''), 'ajuste');
  v_comanda := nullif(current_setting('agendapro.mov_comanda', true), '')::uuid;

  insert into public.estoque_mov (produto_id, de, para, motivo, comanda_id, quem)
  values (new.id, old.estoque, new.estoque, v_motivo, v_comanda, auth.uid());

  return null;
end $$;

drop trigger if exists tg_produto_estoque_mov on public.produtos;
create trigger tg_produto_estoque_mov
  after update of estoque on public.produtos
  for each row execute function public.tg_produto_estoque_mov();

revoke all on function public.tg_produto_estoque_mov() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3b) A BAIXA DA COMANDA, AGORA DIZENDO QUE É VENDA
--
-- ⚠ VAI INTEIRA, de novo: cópia fiel do 26_estoque.sql com duas linhas de
-- `set_config` em volta do update. O comportamento da baixa não muda em nada
-- — e não pode mudar, porque o `estoque.test.sql` cobra a simetria entre
-- fechar e reabrir.
-- ---------------------------------------------------------------------------
create or replace function public.tg_comanda_estoque()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_sinal int;
begin
  /* As duas condições são a trava, e cada metade carrega peso. O
     `old.status <> 'fechada'` é o que impede a baixa dobrada quando o painel
     grava "fechada" por cima de "fechada" — que acontece a cada salvamento.
     Simplificar para `if new.status = 'fechada'` faria o estoque descer
     sozinho, sem venda nenhuma. É a mutação que o `estoque.test.sql` reprova. */
  if old.status <> 'fechada' and new.status = 'fechada' then
    v_sinal := -1;                       -- vendeu: sai do estoque
  elsif old.status = 'fechada' and new.status <> 'fechada' then
    v_sinal := 1;                        -- reabriu ou cancelou: volta
  else
    return null;                         -- aberta -> cancelada: nunca baixou
  end if;

  /* O recado para o gatilho do histórico, que é quem escreve. Local à
     transação (`true`), senão a conexão levaria o rótulo para o próximo que
     a usasse. */
  perform set_config('agendapro.mov_motivo',
                     case when v_sinal < 0 then 'venda' else 'devolucao' end, true);
  perform set_config('agendapro.mov_comanda', new.id::text, true);

  update public.produtos p
     set estoque = p.estoque + v_sinal * i.total_qtd
    from (select ci.produto_id, sum(ci.qtd) as total_qtd
            from public.comanda_itens ci
           where ci.comanda_id = new.id
             and ci.tipo = 'produto'
             and ci.produto_id is not null
           group by ci.produto_id) i
   where p.id = i.produto_id;

  /* Apaga o recado. ⚠ E ELE JÁ MORRERIA SOZINHO: `set_config(..., true)` é
     local à transação, e cada chamada pelo PostgREST é uma transação própria.
     Estas duas linhas valem só para o caso de alguém, um dia, fechar uma
     comanda e mexer no estoque na MESMA transação — de dentro de outra função
     do banco, que é o único jeito de isso acontecer. Custam nada e escrevem a
     intenção; por isso a mutação que as remove sobrevive, e está anotada no
     `tests/mutacoes-produto-cadastro.sh` para ninguém "consertar" a suíte por
     causa dela. */
  perform set_config('agendapro.mov_motivo', '', true);
  perform set_config('agendapro.mov_comanda', '', true);

  return null;
end $$;

comment on function public.tg_comanda_estoque() is
  'Baixa o estoque ao fechar a comanda e devolve ao reabrir. Nunca recusa o fechamento. Marca o motivo para o histórico.';

-- ---------------------------------------------------------------------------
-- 3c) Ler o histórico de um produto
--
-- Gestão only, pelo mesmo motivo do relatório: o histórico mostra quanto o
-- salão comprou e vendeu de cada coisa.
-- ---------------------------------------------------------------------------
create or replace function public.estoque_historico(p_produto uuid, p_limite int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_salao uuid;
begin
  select salao_id into v_salao from public.produtos where id = p_produto;
  if v_salao is null then
    raise exception 'Produto não encontrado.' using errcode = 'no_data_found';
  end if;
  if not public.e_gestor(v_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'quando', m.criado_em,
             'de', m.de, 'para', m.para,
             'delta', m.para - m.de,
             'motivo', m.motivo,
             -- O nome de quem mexeu, e não o uuid: a tela não tem como
             -- traduzir perfil, e o histórico existe para ser lido.
             'quem', coalesce(pf.nome, '—'))
           order by m.criado_em desc)
      from (select * from public.estoque_mov
             where produto_id = p_produto
             order by criado_em desc
             limit greatest(1, least(coalesce(p_limite, 50), 200))) m
      left join public.perfis pf on pf.id = m.quem), '[]'::jsonb);
end $$;

revoke all on function public.estoque_historico(uuid, int) from public, anon;
grant execute on function public.estoque_historico(uuid, int) to authenticated;

comment on function public.estoque_historico(uuid, int) is
  'As últimas movimentações de estoque de um produto, mais recentes primeiro. Gestão only.';
