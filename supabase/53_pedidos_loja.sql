-- ===========================================================================
-- 53_pedidos_loja.sql — o pedido da loja, gravado, e a venda no painel
--
-- O pedido do dono: "caso alguém se interesse pelos produtos e faça seu
-- pedido, no ícone do WhatsApp... a pessoa tem que fazer seu cadastro e
-- depois enviar no WhatsApp do jeito que está, e quando clicar enviar vai
-- aparecer no painel, no módulo pedidos, que aí eu tenho que confirmar a
-- lista e como será o pagamento — e o crediário, se tiver o módulo".
--
-- ── O CAMINHO ─────────────────────────────────────────────────────────────
--   1. a cliente monta o carrinho no link e toca em Enviar pelo WhatsApp;
--   2. sem conta, faz o cadastro (o link pede); a ficha nasce ou é ligada;
--   3. o pedido é GRAVADO aqui (`fazer_pedido_loja`), com número, e o
--      WhatsApp abre com o texto de sempre + "Pedido nº 12" — a conversa
--      continua entre as duas pessoas;
--   4. no painel, a aba Pedidos lista (`pedidos_loja_painel`); o balcão confere
--      os itens e VENDE: Pix, dinheiro ou cartão (`vender_pedido_loja`: a
--      comanda fecha e o estoque baixa, como qualquer venda) ou Crediário
--      (`vender_pedido_no_crediario`: a venda a prazo do 47, de uma vez);
--   5. não fechou: Cancelar.
--
-- ── ⚠ O PREÇO É O DO BANCO ────────────────────────────────────────────────
-- A página manda só quais produtos e quantos. O texto do WhatsApp a cliente
-- pode editar antes de enviar; o pedido gravado, não. E a venda lê o preço do
-- cadastro de novo — quem vende confere, e não confia no que chegou.
--
-- ── ⚠ ISTO NÃO MEXE NO RESTAURANTE ────────────────────────────────────────
-- O modo Pedidos do restaurante (37) tem as tabelas e o andamento dele
-- (entrega, preparo). Este é da loja dos outros tipos: sem entrega, sem
-- andamento — chegou, vendeu ou cancelou.
--
-- ── O ESTOQUE ─────────────────────────────────────────────────────────────
-- Só baixa na venda (a comanda fechada, 26). Pedido que não fecha não segura
-- produto.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS TABELAS
-- ---------------------------------------------------------------------------
create table if not exists public.pedidos_loja (
  id               uuid primary key default gen_random_uuid(),
  salao_id         uuid not null references public.saloes(id) on delete cascade,
  numero           int  not null,
  cliente_id       uuid not null references public.clientes(id) on delete cascade,
  perfil_id        uuid references public.perfis(id) on delete set null,
  status           text not null default 'novo' check (status in ('novo', 'vendido', 'cancelado')),
  cupom            text,
  total_estimado   numeric(10,2) not null default 0,
  criado_em        timestamptz not null default now(),
  vendido_em       timestamptz,
  vendido_por      uuid references public.perfis(id) on delete set null,
  comanda_id       uuid references public.comandas(id) on delete set null,
  crediario_id     uuid references public.crediarios(id) on delete set null,
  cancelado_em     timestamptz,
  cancelado_por    uuid references public.perfis(id) on delete set null,
  cancelado_motivo text,
  unique (salao_id, numero)
);
create index if not exists ix_pedido_loja_salao on public.pedidos_loja(salao_id, status, criado_em desc);
create index if not exists ix_pedido_loja_cliente on public.pedidos_loja(cliente_id);

create table if not exists public.pedido_loja_itens (
  id          uuid primary key default gen_random_uuid(),
  pedido_id   uuid not null references public.pedidos_loja(id) on delete cascade,
  produto_id  uuid references public.produtos(id) on delete set null,
  descricao   text not null,
  qtd         numeric(10,2) not null check (qtd > 0),
  preco_unit  numeric(10,2) not null check (preco_unit >= 0)
);
create index if not exists ix_pedido_loja_itens on public.pedido_loja_itens(pedido_id);

-- O balcão e a gestão leem; a cliente lê os dela. Ninguém escreve pela API —
-- só as funções abaixo.
alter table public.pedidos_loja enable row level security;
alter table public.pedido_loja_itens enable row level security;
drop policy if exists pedidos_loja_ler on public.pedidos_loja;
create policy pedidos_loja_ler on public.pedidos_loja for select to authenticated
  using (public.ve_agenda_toda(salao_id) or perfil_id = auth.uid());
drop policy if exists pedido_loja_itens_ler on public.pedido_loja_itens;
create policy pedido_loja_itens_ler on public.pedido_loja_itens for select to authenticated
  using (exists (select 1 from public.pedidos_loja p where p.id = pedido_id
                  and (public.ve_agenda_toda(p.salao_id) or p.perfil_id = auth.uid())));
revoke all on public.pedidos_loja, public.pedido_loja_itens from anon, authenticated;
grant select on public.pedidos_loja, public.pedido_loja_itens to authenticated;

-- ---------------------------------------------------------------------------
-- 2) A CLIENTE FAZ O PEDIDO (a porta do link)
--
-- Só com conta: é o cadastro que diz quem pediu (e o pedido vai para a ficha
-- dela). Sem ficha no salão, ela nasce aqui (48). No máximo 5 pedidos
-- esperando por cliente: o resto é a conversa do WhatsApp.
--
-- ⚠ CORRIGIU E MANDOU DE NOVO: o MESMO pedido. A loja sempre deixou a
-- cliente ajustar o carrinho e mandar de novo (o cupom não é gasto outra
-- vez). Com o pedido gravado, mandar de novo com `p_pedido` (o dela, ainda
-- esperando) troca os itens do mesmo número — e não enche o painel de
-- pedidos repetidos. Já vendido ou cancelado pelo salão, nasce outro.
-- ---------------------------------------------------------------------------
drop function if exists public.fazer_pedido_loja(uuid, jsonb, text);
create or replace function public.fazer_pedido_loja(p_salao uuid, p_itens jsonb, p_cupom text default null,
                                                    p_pedido uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_eu uuid := auth.uid(); v_cfg jsonb; f jsonb; v_cliente uuid; v_tel text;
  v_id uuid; v_num int; v_total numeric := 0; x record; v_ant public.pedidos_loja%rowtype;
begin
  if v_eu is null then
    raise exception 'Faça seu cadastro (ou entre) para enviar o pedido.' using errcode = 'insufficient_privilege';
  end if;
  select s.cfg into v_cfg from public.saloes s where s.id = p_salao and s.status = 'ativo';
  if not found then
    raise exception 'Este salão não está recebendo pedidos agora.' using errcode = 'check_violation';
  end if;
  if lower(btrim(coalesce(v_cfg->>'loja', 'true'))) in ('false', 'f', '0', 'no', 'nao', 'não') then
    raise exception 'Este salão não está recebendo pedidos agora.' using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'O carrinho está vazio.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_itens) > 50 then
    raise exception 'Pedido grande demais: combine com o salão pelo WhatsApp.' using errcode = 'check_violation';
  end if;

  -- A ficha dela neste salão: a ligada à conta; senão, o cadastro (48).
  select c.id into v_cliente from public.clientes c
   where c.salao_id = p_salao and c.perfil_id = v_eu order by c.criado_em limit 1;
  if v_cliente is null then
    f := public.cadastrar_minha_ficha(p_salao);
    v_cliente := nullif(f->>'ficha', '')::uuid;
    if v_cliente is null and f->>'motivo' = 'telefone_de_outra_ficha' then
      -- O WhatsApp dela já está numa ficha do salão: o pedido vai para essa.
      select public.telefone_nacional(p.telefone) into v_tel from public.perfis p where p.id = v_eu;
      select c.id into v_cliente from public.clientes c
       where c.salao_id = p_salao and public.telefone_nacional(c.telefone) = v_tel
       order by c.criado_em limit 1;
    end if;
    if v_cliente is null then
      if f->>'motivo' = 'sem_telefone' then
        raise exception 'Falta o seu WhatsApp no cadastro: complete e envie de novo.' using errcode = 'check_violation';
      end if;
      raise exception 'Não consegui fazer seu cadastro neste salão. Fale com ele pelo WhatsApp.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- O pedido que ela já mandou e ainda espera: é ele que muda.
  if p_pedido is not null then
    select * into v_ant from public.pedidos_loja p
     where p.id = p_pedido and p.salao_id = p_salao and p.perfil_id = v_eu for update;
    if v_ant.id is not null and v_ant.status = 'novo' then
      v_id := v_ant.id; v_num := v_ant.numero;
      delete from public.pedido_loja_itens where pedido_id = v_id;
      update public.pedidos_loja
         set cupom = coalesce(nullif(left(btrim(coalesce(p_cupom, '')), 40), ''), cupom)
       where id = v_id;
    end if;
  end if;

  if v_id is null then
    if (select count(*) from public.pedidos_loja p
         where p.salao_id = p_salao and p.cliente_id = v_cliente and p.status = 'novo') >= 5 then
      raise exception 'Você já tem pedidos esperando o salão. Aguarde a resposta pelo WhatsApp.'
        using errcode = 'check_violation';
    end if;
    -- O número do pedido, um por salão, sem pular nem repetir.
    perform pg_advisory_xact_lock(hashtext('pedido_loja:' || p_salao::text));
    select coalesce(max(p.numero), 0) + 1 into v_num from public.pedidos_loja p where p.salao_id = p_salao;
    insert into public.pedidos_loja (salao_id, numero, cliente_id, perfil_id, cupom)
         values (p_salao, v_num, v_cliente, v_eu, nullif(left(btrim(coalesce(p_cupom, '')), 40), ''))
      returning id into v_id;
  end if;

  -- Os itens: só o que a loja do link mostra, com o preço do cadastro. O
  -- mesmo produto em duas linhas vira uma, com a soma.
  for x in
    select pr.id, pr.nome, pr.preco, sum(greatest(1, least(99, coalesce(nullif(i->>'qtd', '')::numeric, 1))))::numeric as qtd
      from jsonb_array_elements(p_itens) i
      join public.produtos pr on pr.id = nullif(i->>'id', '')::uuid
     where pr.salao_id = p_salao and pr.ativo and pr.venda_online
     group by pr.id, pr.nome, pr.preco
  loop
    insert into public.pedido_loja_itens (pedido_id, produto_id, descricao, qtd, preco_unit)
         values (v_id, x.id, x.nome, least(x.qtd, 99), coalesce(x.preco, 0));
    v_total := v_total + least(x.qtd, 99) * coalesce(x.preco, 0);
  end loop;
  if not exists (select 1 from public.pedido_loja_itens where pedido_id = v_id) then
    raise exception 'Estes produtos não estão mais na loja. Atualize a página.' using errcode = 'check_violation';
  end if;
  update public.pedidos_loja set total_estimado = round(v_total, 2) where id = v_id;
  return jsonb_build_object('ok', true, 'pedido', v_id, 'numero', v_num, 'total', round(v_total, 2),
                            'atualizado', v_id = p_pedido);
end $$;

-- ---------------------------------------------------------------------------
-- 3) O PAINEL: A LISTA
-- Os que esperam, e os vendidos ou cancelados dos últimos 30 dias.
-- ---------------------------------------------------------------------------
create or replace function public.pedidos_loja_painel(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem os pedidos.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'numero', p.numero, 'status', p.status, 'criadoEm', p.criado_em,
             'clienteId', p.cliente_id, 'cliente', c.nome, 'telefone', c.telefone,
             'cupom', p.cupom, 'total', p.total_estimado,
             'vendidoEm', p.vendido_em, 'comandaId', p.comanda_id, 'crediarioId', p.crediario_id,
             'canceladoEm', p.cancelado_em, 'motivo', p.cancelado_motivo,
             -- O que foi VENDIDO (a comanda): o total e as formas de pagamento.
             'vendaTotal', (select ct.total from public.comandas_totais ct where ct.id = p.comanda_id),
             'vendaFormas', (select jsonb_agg(distinct pg.forma) from public.pagamentos pg
                              where pg.comanda_id = p.comanda_id),
             'itens', coalesce((select jsonb_agg(jsonb_build_object(
                         'produtoId', i.produto_id, 'descricao', i.descricao,
                         'qtd', i.qtd, 'preco', i.preco_unit) order by i.descricao)
                         from public.pedido_loja_itens i where i.pedido_id = p.id), '[]'::jsonb))
           order by (p.status = 'novo') desc, p.criado_em desc)
      from public.pedidos_loja p
      join public.clientes c on c.id = p.cliente_id
     where p.salao_id = p_salao
       and (p.status = 'novo' or p.criado_em > now() - interval '30 days')), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 4) VENDER
--
-- O balcão manda a lista conferida (produtos e quantidades — tirou o que não
-- tem, mudou quantidade). O preço é lido do cadastro aqui. A venda é uma
-- comanda como qualquer outra, montada e fechada de uma vez: entra no
-- faturamento, no caixa aberto e na comissão, e o estoque baixa (15, 17, 26).
-- ---------------------------------------------------------------------------
create or replace function public.pedido_para_vender(p_pedido uuid)
returns public.pedidos_loja language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype;
begin
  select * into p from public.pedidos_loja where id = p_pedido for update;
  if p.id is null then
    raise exception 'Pedido não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(p.salao_id) then
    raise exception 'Só o balcão e a gestão vendem.' using errcode = 'insufficient_privilege';
  end if;
  if p.status <> 'novo' then
    raise exception 'Este pedido já foi %.', case when p.status = 'vendido' then 'vendido' else 'cancelado' end
      using errcode = 'check_violation';
  end if;
  return p;
end $$;

create or replace function public.vender_pedido_loja(
  p_pedido uuid, p_itens jsonb, p_forma text, p_desconto numeric default 0, p_profissional uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype; v_com uuid; x jsonb; v_qtd numeric; v_preco numeric; v_desc text; v_total numeric;
begin
  p := public.pedido_para_vender(p_pedido);
  if coalesce(p_forma, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
    raise exception 'Escolha como ela pagou: Pix, dinheiro, cartão ou transferência.' using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Deixe pelo menos um item na venda.' using errcode = 'check_violation';
  end if;
  if p_profissional is not null and not exists (
       select 1 from public.profissionais pr where pr.id = p_profissional and pr.salao_id = p.salao_id) then
    raise exception 'Quem vendeu não é deste salão.' using errcode = 'check_violation';
  end if;

  insert into public.comandas (salao_id, cliente_id, status) values (p.salao_id, p.cliente_id, 'aberta')
    returning id into v_com;
  for x in select * from jsonb_array_elements(p_itens) loop
    v_qtd := coalesce(nullif(x->>'qtd', '')::numeric, 1);
    if v_qtd <= 0 or v_qtd > 999 then
      raise exception 'Confira a quantidade dos itens.' using errcode = 'check_violation';
    end if;
    select pr.nome, pr.preco into v_desc, v_preco from public.produtos pr
     where pr.id = nullif(x->>'id', '')::uuid and pr.salao_id = p.salao_id;
    if v_desc is null then
      raise exception 'Um dos produtos não é deste salão.' using errcode = 'check_violation';
    end if;
    insert into public.comanda_itens (comanda_id, tipo, produto_id, descricao, qtd, preco_unit, profissional_id)
         values (v_com, 'produto', nullif(x->>'id', '')::uuid, v_desc, v_qtd, coalesce(v_preco, 0), p_profissional);
  end loop;
  if coalesce(p_desconto, 0) < 0 then
    raise exception 'O desconto não pode ser negativo.' using errcode = 'check_violation';
  end if;
  if coalesce(p_desconto, 0) > 0 then
    update public.comandas set desconto = round(p_desconto, 2) where id = v_com;
  end if;
  select t.total into v_total from public.comandas_totais t where t.id = v_com;
  if coalesce(v_total, 0) > 0 then
    insert into public.pagamentos (comanda_id, forma, valor) values (v_com, p_forma, round(v_total, 2));
  end if;
  update public.comandas set status = 'fechada', fechada_em = now() where id = v_com;

  update public.pedidos_loja
     set status = 'vendido', vendido_em = now(), vendido_por = auth.uid(), comanda_id = v_com
   where id = p.id;
  return jsonb_build_object('ok', true, 'comanda', v_com, 'total', round(coalesce(v_total, 0), 2));
end $$;

/* No crediário: a venda a prazo do 47 (nome completo, WhatsApp e CPF na
   ficha, as parcelas, a entrada), e o pedido vendido — na mesma transação:
   ou os dois, ou nenhum. */
create or replace function public.vender_pedido_no_crediario(
  p_pedido uuid, p_itens jsonb, p_profissional uuid, p_desconto numeric,
  p_entrada numeric, p_forma_entrada text, p_parcelas int, p_primeiro date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype; r jsonb;
begin
  p := public.pedido_para_vender(p_pedido);
  r := public.nova_venda_no_crediario(p.salao_id, p.cliente_id, p_itens, p_profissional,
         p_desconto, p_entrada, p_forma_entrada, p_parcelas, p_primeiro);
  update public.pedidos_loja
     set status = 'vendido', vendido_em = now(), vendido_por = auth.uid(),
         comanda_id = nullif(r->>'comanda', '')::uuid, crediario_id = nullif(r->>'crediario', '')::uuid
   where id = p.id;
  return r || jsonb_build_object('pedido', p.id);
end $$;

-- ---------------------------------------------------------------------------
-- 5) CANCELAR
-- ---------------------------------------------------------------------------
create or replace function public.cancelar_pedido_loja(p_pedido uuid, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype;
begin
  p := public.pedido_para_vender(p_pedido);
  update public.pedidos_loja
     set status = 'cancelado', cancelado_em = now(), cancelado_por = auth.uid(),
         cancelado_motivo = nullif(left(btrim(coalesce(p_motivo, '')), 200), '')
   where id = p.id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 5b) O RECIBO
--
-- "Nos pedidos preciso ver o que eu vendi, um recibo com todos os itens, e
-- mandar o PDF no WhatsApp ou imprimir." O recibo é o que foi VENDIDO — a
-- comanda, com a lista conferida no balcão —, não o que a cliente pediu:
-- tirou um item que não tinha, ele não aparece. Com o pagamento (as formas,
-- e as parcelas, se foi no crediário) e quem vendeu.
-- ---------------------------------------------------------------------------
create or replace function public.recibo_do_pedido_loja(p_pedido uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype; s public.saloes%rowtype; t record; c record;
begin
  select * into p from public.pedidos_loja where id = p_pedido;
  if p.id is null then
    raise exception 'Pedido não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(p.salao_id) then
    raise exception 'Só o balcão e a gestão veem o recibo.' using errcode = 'insufficient_privilege';
  end if;
  if p.status <> 'vendido' or p.comanda_id is null then
    raise exception 'Este pedido ainda não foi vendido.' using errcode = 'check_violation';
  end if;
  select * into s from public.saloes where id = p.salao_id;
  select ct.numero, ct.subtotal, ct.desconto, ct.acrescimo, ct.total, ct.fechada_em into t
    from public.comandas_totais ct where ct.id = p.comanda_id;
  select cl.nome, cl.telefone into c from public.clientes cl where cl.id = p.cliente_id;
  return jsonb_build_object(
    'salao', jsonb_build_object('nome', s.nome,
               'telefone', coalesce(nullif(btrim(coalesce(s.whatsapp, '')), ''), s.telefone),
               'endereco', s.endereco),
    'numero', p.numero, 'comanda', t.numero,
    'vendidoEm', coalesce(p.vendido_em, t.fechada_em),
    'vendidoPor', (select pf.nome from public.perfis pf where pf.id = p.vendido_por),
    'cliente', c.nome, 'telefone', c.telefone,
    'itens', coalesce((select jsonb_agg(jsonb_build_object('descricao', i.descricao, 'qtd', i.qtd,
                 'preco', i.preco_unit, 'total', round(i.qtd * i.preco_unit, 2)) order by i.descricao)
                 from public.comanda_itens i where i.comanda_id = p.comanda_id), '[]'::jsonb),
    'subtotal', t.subtotal, 'desconto', t.desconto, 'acrescimo', t.acrescimo, 'total', t.total,
    'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('forma', pg.forma, 'valor', pg.valor)
                 order by (pg.forma = 'crediario'), pg.recebido_em)
                 from public.pagamentos pg where pg.comanda_id = p.comanda_id), '[]'::jsonb),
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object('numero', pa.numero, 'valor', pa.valor,
                 'venceEm', pa.vence_em) order by pa.numero)
                 from public.crediario_parcelas pa where pa.crediario_id = p.crediario_id), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.fazer_pedido_loja(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.fazer_pedido_loja(uuid, jsonb, text, uuid) to authenticated;
revoke all on function public.pedidos_loja_painel(uuid) from public, anon;
grant execute on function public.pedidos_loja_painel(uuid) to authenticated;
revoke all on function public.pedido_para_vender(uuid) from public, anon, authenticated;
revoke all on function public.vender_pedido_loja(uuid, jsonb, text, numeric, uuid) from public, anon;
grant execute on function public.vender_pedido_loja(uuid, jsonb, text, numeric, uuid) to authenticated;
revoke all on function public.vender_pedido_no_crediario(uuid, jsonb, uuid, numeric, numeric, text, int, date) from public, anon;
grant execute on function public.vender_pedido_no_crediario(uuid, jsonb, uuid, numeric, numeric, text, int, date) to authenticated;
revoke all on function public.cancelar_pedido_loja(uuid, text) from public, anon;
grant execute on function public.cancelar_pedido_loja(uuid, text) to authenticated;
revoke all on function public.recibo_do_pedido_loja(uuid) from public, anon;
grant execute on function public.recibo_do_pedido_loja(uuid) to authenticated;
