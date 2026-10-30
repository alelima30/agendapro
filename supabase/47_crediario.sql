-- ===========================================================================
-- 47_crediario.sql — o Crediário: vender parcelado no fiado
--
-- O pedido: "tem gente que trabalha com fiado — lingerie, e pagam parcelado
-- em 3x". A cliente leva hoje e paga todo dia 5, por três meses. É o módulo
-- adicional da 46 (R$ 49,90, do Essencial para cima).
--
-- ── COMO O DINHEIRO ANDA ──────────────────────────────────────────────────
-- A venda é uma comanda como qualquer outra: os itens, a entrada (se houver)
-- num pagamento normal, e o resto num pagamento da forma `crediario`, que
-- fecha a comanda. Então:
--
--   · VENDIDO entra no faturamento no dia da venda (a mesma regra de sempre,
--     pela comanda fechada), e o estoque sai na hora;
--   · RECEBIDO é cada parcela paga (`crediario_recebimentos`): entra no caixa
--     do dia em que entrou — o dinheiro na gaveta, o Pix com os Pix;
--   · A RECEBER e ATRASADO são as parcelas em aberto.
-- Nada é contado duas vezes: a parcela recebida não é faturamento de novo.
--
-- ── AS DECISÕES DO DONO ───────────────────────────────────────────────────
--   · nome completo, WhatsApp e CPF obrigatórios para vender no crediário
--     (e o CPF é conferido pelo dígito, aqui no banco);
--   · comissão CONFORME A CLIENTE PAGA: na venda conta só a parte paga na
--     hora; cada parcela recebida conta a parte dela, no dia em que entrou;
--   · sem juros por enquanto;
--   · pagamento parcial: o resto fica em aberto na mesma parcela;
--   · desfazer um recebimento é da gestão;
--   · módulo cancelado: as parcelas abertas continuam e o recebimento
--     continua — só não se vende fiado novo (a trava é na VENDA).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS TABELAS
-- ---------------------------------------------------------------------------
create table if not exists public.crediarios (
  id             uuid primary key default gen_random_uuid(),
  salao_id       uuid not null references public.saloes(id) on delete cascade,
  cliente_id     uuid not null references public.clientes(id),
  comanda_id     uuid not null references public.comandas(id),
  pagamento_id   uuid references public.pagamentos(id) on delete set null,
  valor          numeric(10,2) not null check (valor > 0),       -- o que foi financiado
  parcelas       smallint not null check (parcelas between 1 and 12),
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.perfis(id) on delete set null,
  -- Desfeito (vendido errado, refeito na hora): sai de tudo, fica o rastro.
  desfeito_em    timestamptz,
  desfeito_por   uuid references public.perfis(id) on delete set null
);
create unique index if not exists ux_crediario_comanda
  on public.crediarios(comanda_id) where desfeito_em is null;
create index if not exists ix_crediario_cliente on public.crediarios(cliente_id);

create table if not exists public.crediario_parcelas (
  id            uuid primary key default gen_random_uuid(),
  crediario_id  uuid not null references public.crediarios(id) on delete cascade,
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  numero        smallint not null check (numero >= 1),
  valor         numeric(10,2) not null check (valor > 0),
  vence_em      date not null,
  unique (crediario_id, numero)
);
create index if not exists ix_parcela_salao_vence on public.crediario_parcelas(salao_id, vence_em);

create table if not exists public.crediario_recebimentos (
  id            uuid primary key default gen_random_uuid(),
  parcela_id    uuid not null references public.crediario_parcelas(id) on delete cascade,
  crediario_id  uuid not null references public.crediarios(id) on delete cascade,
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  valor         numeric(10,2) not null check (valor > 0),
  forma         text not null check (forma in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia')),
  -- O caixa aberto na hora (como o pagamento, 17): o dinheiro vai para a gaveta.
  caixa_id      uuid references public.caixas(id) on delete set null,
  recebido_em   timestamptz not null default now(),
  recebido_por  uuid references public.perfis(id) on delete set null,
  desfeito_em   timestamptz,
  desfeito_por  uuid references public.perfis(id) on delete set null
);
create index if not exists ix_receb_parcela on public.crediario_recebimentos(parcela_id);
create index if not exists ix_receb_salao on public.crediario_recebimentos(salao_id, recebido_em);
create index if not exists ix_receb_caixa on public.crediario_recebimentos(caixa_id);

-- Dinheiro e venda: o balcão e a gestão leem (como o caixa). Ninguém escreve
-- pela API — só as funções abaixo.
alter table public.crediarios enable row level security;
alter table public.crediario_parcelas enable row level security;
alter table public.crediario_recebimentos enable row level security;
drop policy if exists crediarios_ler on public.crediarios;
create policy crediarios_ler on public.crediarios for select to authenticated
  using (public.ve_agenda_toda(salao_id));
drop policy if exists crediario_parcelas_ler on public.crediario_parcelas;
create policy crediario_parcelas_ler on public.crediario_parcelas for select to authenticated
  using (public.ve_agenda_toda(salao_id));
drop policy if exists crediario_receb_ler on public.crediario_recebimentos;
create policy crediario_receb_ler on public.crediario_recebimentos for select to authenticated
  using (public.ve_agenda_toda(salao_id));
revoke all on public.crediarios, public.crediario_parcelas, public.crediario_recebimentos
  from anon, authenticated;
grant select on public.crediarios, public.crediario_parcelas, public.crediario_recebimentos
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2) O CPF, CONFERIDO PELO DÍGITO
--
-- Crediário é dinheiro emprestado: o CPF precisa ser de verdade, e não onze
-- números quaisquer. 111.111.111-11 passa no dígito e não é de ninguém.
-- ---------------------------------------------------------------------------
create or replace function public.cpf_valido(p_cpf text)
returns boolean language plpgsql immutable set search_path = public as $$
declare d text := public.so_digitos(p_cpf); s int; r int; i int;
begin
  if d is null or d !~ '^[0-9]{11}$' or d ~ '^(.)\1{10}$' then return false; end if;
  s := 0;
  for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> substr(d, 10, 1)::int then return false; end if;
  s := 0;
  for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

-- ---------------------------------------------------------------------------
-- 3) O PAGAMENTO DA FORMA `crediario` SÓ NASCE PELA VENDA
--
-- A tela grava pagamentos direto na tabela (o caminho de sempre). Um
-- `crediario` gravado assim seria um fiado sem parcelas: a comanda fecharia
-- "paga" e ninguém saberia que alguém deve. Então ele só entra quando a
-- venda (`vender_no_crediario`) já criou o crediário daquele valor — e não
-- muda nem sai enquanto o crediário existir.
-- ---------------------------------------------------------------------------
create or replace function public.tg_pagamento_crediario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.forma = 'crediario' and not exists (
         select 1 from public.crediarios cr
          where cr.comanda_id = new.comanda_id and cr.desfeito_em is null
            and cr.pagamento_id is null and cr.valor = new.valor) then
      raise exception 'Venda no crediário é pelo botão "Vender no crediário" da comanda.'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if (old.forma = 'crediario' or new.forma = 'crediario')
       and (new.forma is distinct from old.forma or new.valor is distinct from old.valor
            or new.comanda_id is distinct from old.comanda_id) then
      raise exception 'O pagamento do crediário não se edita: desfaça a venda no crediário.'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;
  -- DELETE
  if old.forma = 'crediario' and exists (
       select 1 from public.crediarios cr
        where cr.pagamento_id = old.id and cr.desfeito_em is null) then
    raise exception 'O pagamento do crediário não se apaga: desfaça a venda no crediário.'
      using errcode = 'check_violation';
  end if;
  return old;
end $$;

drop trigger if exists tg_pagamento_crediario on public.pagamentos;
create trigger tg_pagamento_crediario
  before insert or update or delete on public.pagamentos
  for each row execute function public.tg_pagamento_crediario();

-- Comanda vendida no crediário não reabre por baixo: as parcelas ficariam
-- penduradas numa venda que mudou.
create or replace function public.tg_comanda_crediario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'fechada' and new.status <> 'fechada' and exists (
       select 1 from public.crediarios cr
        where cr.comanda_id = new.id and cr.desfeito_em is null) then
    raise exception 'Esta comanda foi vendida no crediário. Para corrigir, desfaça a venda no crediário (no detalhe da comanda).'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists tg_comanda_crediario on public.comandas;
create trigger tg_comanda_crediario
  before update of status on public.comandas
  for each row execute function public.tg_comanda_crediario();

-- ---------------------------------------------------------------------------
-- 4) VENDER NO CREDIÁRIO
--
-- O que falta pagar da comanda vira N parcelas, a primeira em p_primeiro e
-- as outras no mesmo dia dos meses seguintes (dia 31 vira o último dia do
-- mês curto). Os centavos que sobram da divisão vão para a primeira. E a
-- comanda fecha aqui, junto — tudo ou nada.
-- ---------------------------------------------------------------------------
create or replace function public.vender_no_crediario(
  p_comanda uuid, p_parcelas int, p_primeiro date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.comandas%rowtype; t record; cli record; v_cr uuid; v_base numeric; v_resto numeric;
  v_hoje date; i int; v_pg uuid; v_lista jsonb := '[]'::jsonb; v_val numeric; v_venc date;
begin
  select * into c from public.comandas where id = p_comanda for update;
  if c.id is null then
    raise exception 'Comanda não encontrada.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(c.salao_id) then
    raise exception 'Só o balcão e a gestão vendem no crediário.' using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(c.salao_id, 'crediario', 'Vender no crediário');
  if c.status <> 'aberta' then
    raise exception 'Esta comanda não está aberta.' using errcode = 'check_violation';
  end if;
  if c.cliente_id is null then
    raise exception 'Escolha a cliente da comanda: o crediário é no nome dela.' using errcode = 'check_violation';
  end if;
  select cl.nome, cl.telefone, cl.cpf into cli from public.clientes cl where cl.id = c.cliente_id;
  if coalesce(btrim(cli.nome), '') !~ '\S+\s+\S+' then
    raise exception 'Para vender no crediário, a ficha da cliente precisa do nome completo.'
      using errcode = 'check_violation';
  end if;
  if length(coalesce(public.so_digitos(cli.telefone), '')) < 10 then
    raise exception 'Para vender no crediário, a ficha da cliente precisa do WhatsApp.'
      using errcode = 'check_violation';
  end if;
  if not public.cpf_valido(cli.cpf) then
    raise exception 'Para vender no crediário, a ficha da cliente precisa de um CPF válido.'
      using errcode = 'check_violation';
  end if;
  if p_parcelas is null or p_parcelas < 1 or p_parcelas > 12 then
    raise exception 'Escolha de 1 a 12 parcelas.' using errcode = 'check_violation';
  end if;
  v_hoje := public.hoje_no_salao(c.salao_id);
  if p_primeiro is null or p_primeiro < v_hoje or p_primeiro > v_hoje + 120 then
    raise exception 'O primeiro vencimento vai de hoje até daqui a 4 meses.' using errcode = 'check_violation';
  end if;

  select * into t from public.comandas_totais where id = p_comanda;
  if coalesce(t.subtotal, 0) <= 0 then
    raise exception 'Comanda sem itens não pode ser vendida.' using errcode = 'check_violation';
  end if;
  if coalesce(t.falta, 0) <= 0 then
    raise exception 'Esta comanda já está paga.' using errcode = 'check_violation';
  end if;

  insert into public.crediarios (salao_id, cliente_id, comanda_id, valor, parcelas, criado_por)
       values (c.salao_id, c.cliente_id, c.id, round(t.falta, 2), p_parcelas, auth.uid())
    returning id into v_cr;

  v_base := trunc(round(t.falta, 2) / p_parcelas, 2);
  v_resto := round(t.falta, 2) - v_base * p_parcelas;
  for i in 1 .. p_parcelas loop
    v_val := v_base + case when i = 1 then v_resto else 0 end;
    v_venc := (p_primeiro + make_interval(months => i - 1))::date;
    insert into public.crediario_parcelas (crediario_id, salao_id, numero, valor, vence_em)
         values (v_cr, c.salao_id, i, v_val, v_venc);
    v_lista := v_lista || jsonb_build_object('numero', i, 'valor', v_val, 'venceEm', v_venc);
  end loop;

  insert into public.pagamentos (comanda_id, forma, valor)
       values (c.id, 'crediario', round(t.falta, 2))
    returning id into v_pg;
  update public.crediarios set pagamento_id = v_pg where id = v_cr;
  update public.comandas set status = 'fechada', fechada_em = now() where id = c.id;

  return jsonb_build_object('ok', true, 'crediario', v_cr, 'valor', round(t.falta, 2),
                            'parcelas', v_lista);
end $$;

/* ── A VENDA DIRETO NA TELA DO CREDIÁRIO ────────────────────────────────
   A comanda está desligada na plataforma (o dono trabalha só com a agenda),
   e a venda a prazo não pode depender dela. Aqui a recepção escolhe a
   cliente, os itens e a entrada, e o banco monta a comanda por baixo — é ela
   que leva a venda ao faturamento, ao estoque e à comissão, como qualquer
   venda. O PREÇO É O DO CADASTRO, lido aqui (o desconto, se houver, é à
   parte e conferido pela trava da comanda). */
create or replace function public.nova_venda_no_crediario(
  p_salao uuid, p_cliente uuid, p_itens jsonb, p_profissional uuid,
  p_desconto numeric, p_entrada numeric, p_forma_entrada text,
  p_parcelas int, p_primeiro date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_com uuid; x jsonb; v_qtd numeric; v_preco numeric; v_desc text; v_falta numeric;
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão vendem no crediário.' using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(p_salao, 'crediario', 'Vender no crediário');
  if not exists (select 1 from public.clientes c where c.id = p_cliente and c.salao_id = p_salao) then
    raise exception 'Escolha a cliente.' using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Some pelo menos um item à venda.' using errcode = 'check_violation';
  end if;
  if p_profissional is not null and not exists (
       select 1 from public.profissionais pr where pr.id = p_profissional and pr.salao_id = p_salao) then
    raise exception 'Quem vendeu não é deste salão.' using errcode = 'check_violation';
  end if;

  insert into public.comandas (salao_id, cliente_id, status) values (p_salao, p_cliente, 'aberta')
    returning id into v_com;
  for x in select * from jsonb_array_elements(p_itens) loop
    v_qtd := coalesce(nullif(x->>'qtd', '')::numeric, 1);
    if v_qtd <= 0 or v_qtd > 999 then
      raise exception 'Confira a quantidade dos itens.' using errcode = 'check_violation';
    end if;
    v_desc := null;
    if x->>'tipo' = 'produto' then
      select pr.nome, pr.preco into v_desc, v_preco from public.produtos pr
       where pr.id = (x->>'id')::uuid and pr.salao_id = p_salao;
      if v_desc is null then
        raise exception 'Um dos produtos não é deste salão.' using errcode = 'check_violation';
      end if;
      insert into public.comanda_itens (comanda_id, tipo, produto_id, descricao, qtd, preco_unit, profissional_id)
           values (v_com, 'produto', (x->>'id')::uuid, v_desc, v_qtd, v_preco, p_profissional);
    elsif x->>'tipo' = 'servico' then
      select sv.nome, sv.preco into v_desc, v_preco from public.servicos sv
       where sv.id = (x->>'id')::uuid and sv.salao_id = p_salao;
      if v_desc is null then
        raise exception 'Um dos serviços não é deste salão.' using errcode = 'check_violation';
      end if;
      insert into public.comanda_itens (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
           values (v_com, 'servico', (x->>'id')::uuid, v_desc, v_qtd, v_preco, p_profissional);
    else
      raise exception 'Item de tipo desconhecido.' using errcode = 'check_violation';
    end if;
  end loop;
  if coalesce(p_desconto, 0) < 0 then
    raise exception 'O desconto não pode ser negativo.' using errcode = 'check_violation';
  end if;
  if coalesce(p_desconto, 0) > 0 then
    update public.comandas set desconto = round(p_desconto, 2) where id = v_com;
  end if;
  if coalesce(p_entrada, 0) > 0 then
    if coalesce(p_forma_entrada, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
      raise exception 'Escolha como ela pagou a entrada.' using errcode = 'check_violation';
    end if;
    select t.total - round(p_entrada, 2) into v_falta from public.comandas_totais t where t.id = v_com;
    if v_falta <= 0 then
      raise exception 'A entrada cobre a venda inteira: não sobra nada para o crediário.'
        using errcode = 'check_violation';
    end if;
    insert into public.pagamentos (comanda_id, forma, valor) values (v_com, p_forma_entrada, round(p_entrada, 2));
  end if;
  return public.vender_no_crediario(v_com, p_parcelas, p_primeiro) || jsonb_build_object('comanda', v_com);
end $$;

-- ---------------------------------------------------------------------------
-- 5) RECEBER UMA PARCELA (OU PARTE DELA)
--
-- Sem trava de módulo de propósito: módulo cancelado não impede receber o
-- que a cliente já deve.
-- ---------------------------------------------------------------------------
create or replace function public.saldo_da_parcela(p_parcela uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select p.valor - coalesce((select sum(r.valor) from public.crediario_recebimentos r
                              where r.parcela_id = p.id and r.desfeito_em is null), 0)
    from public.crediario_parcelas p where p.id = p_parcela
$$;

create or replace function public.receber_parcela(p_parcela uuid, p_valor numeric, p_forma text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; v_saldo numeric; v_caixa uuid; v_id uuid;
begin
  select pa.*, cr.desfeito_em as cr_desfeito into p
    from public.crediario_parcelas pa join public.crediarios cr on cr.id = pa.crediario_id
   where pa.id = p_parcela for update of pa;
  if p.id is null or p.cr_desfeito is not null then
    raise exception 'Parcela não encontrada.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(p.salao_id) then
    raise exception 'Só o balcão e a gestão registram recebimento.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(p_forma, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
    raise exception 'Escolha como ela pagou: Pix, dinheiro, cartão ou transferência.'
      using errcode = 'check_violation';
  end if;
  v_saldo := public.saldo_da_parcela(p.id);
  if v_saldo <= 0 then
    raise exception 'Esta parcela já está paga.' using errcode = 'check_violation';
  end if;
  if p_valor is null or round(p_valor, 2) <= 0 then
    raise exception 'Diga quanto ela pagou.' using errcode = 'check_violation';
  end if;
  if round(p_valor, 2) > v_saldo then
    raise exception 'Esta parcela tem % em aberto.', public.reais(v_saldo) using errcode = 'check_violation';
  end if;
  select k.id into v_caixa from public.caixas k
   where k.salao_id = p.salao_id and k.fechado_em is null limit 1;
  insert into public.crediario_recebimentos
    (parcela_id, crediario_id, salao_id, valor, forma, caixa_id, recebido_por)
  values (p.id, p.crediario_id, p.salao_id, round(p_valor, 2), p_forma, v_caixa, auth.uid())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recebimento', v_id, 'saldo', v_saldo - round(p_valor, 2));
end $$;

-- Lançou por engano: sai da conta (e da gaveta), e fica o rastro. É da gestão.
create or replace function public.desfazer_recebimento_crediario(p_recebimento uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select * into r from public.crediario_recebimentos where id = p_recebimento for update;
  if r.id is null or r.desfeito_em is not null then
    raise exception 'Recebimento não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.e_gestor(r.salao_id) then
    raise exception 'Só o proprietário ou um administrador desfaz um recebimento.'
      using errcode = 'insufficient_privilege';
  end if;
  update public.crediario_recebimentos set desfeito_em = now(), desfeito_por = auth.uid()
   where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

/* Vendeu errado (3x em vez de 4x, a cliente errada): desfaz a venda no
   crediário — enquanto nada foi recebido. A comanda volta a ficar aberta,
   com o que faltava a pagar, para a recepção refazer. Mesma regra do
   "reabrir" da tela: de outro dia, só a gestão. */
create or replace function public.desfazer_crediario(p_crediario uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cr record; v_fuso text;
begin
  select x.*, c.fechada_em into cr from public.crediarios x
    join public.comandas c on c.id = x.comanda_id
   where x.id = p_crediario for update of x;
  if cr.id is null or cr.desfeito_em is not null then
    raise exception 'Crediário não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(cr.salao_id) then
    raise exception 'Só o balcão e a gestão desfazem a venda.' using errcode = 'insufficient_privilege';
  end if;
  select coalesce(fuso, 'America/Sao_Paulo') into v_fuso from public.saloes where id = cr.salao_id;
  if (cr.fechada_em at time zone v_fuso)::date <> public.hoje_no_salao(cr.salao_id)
     and not public.e_gestor(cr.salao_id) then
    raise exception 'Esta venda é de outro dia: só o proprietário ou um administrador desfaz.'
      using errcode = 'insufficient_privilege';
  end if;
  if exists (select 1 from public.crediario_recebimentos r
              where r.crediario_id = cr.id and r.desfeito_em is null) then
    raise exception 'Já há parcela recebida: desfaça os recebimentos antes.'
      using errcode = 'check_violation';
  end if;
  update public.crediarios set desfeito_em = now(), desfeito_por = auth.uid() where id = cr.id;
  update public.comandas set status = 'aberta', fechada_em = null where id = cr.comanda_id;
  delete from public.pagamentos where id = cr.pagamento_id;
  return jsonb_build_object('ok', true, 'comanda', cr.comanda_id);
end $$;

-- ---------------------------------------------------------------------------
-- 6) A COMISSÃO, CONFORME A CLIENTE PAGA
--
-- Na venda, a comissão da comanda conta só a parte paga na hora
-- (`fator_a_vista`: 1 nas comandas sem crediário, então nada muda nelas).
-- Cada parcela recebida conta a parte dela, por profissional, no dia em que
-- entrou (`crediario_comissoes`). A comanda de R$ 300 com R$ 100 de entrada
-- e 2x de R$ 100: um terço da comissão na venda, um terço em cada parcela.
-- ---------------------------------------------------------------------------
create or replace function public.fator_a_vista(p_comanda uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(1 - (select cr.valor from public.crediarios cr
                        where cr.comanda_id = p_comanda and cr.desfeito_em is null)
                      / nullif((select t.total from public.comandas_totais t where t.id = p_comanda), 0), 1)
$$;

/* ⚠ FUNÇÃO, E NÃO VISTA. Uma vista em cima de `comandas_totais` e de
   `comanda_itens_calculados` trava o `drop view` que o 15, o 16 e o 17 fazem
   a cada colagem do 00_tudo: a SEGUNDA colagem morria com "cannot drop view
   comandas_totais because other objects depend on it". Função não prende. */
drop view if exists public.crediario_comissoes;
create or replace function public.crediario_comissoes(p_salao uuid, p_ini timestamptz, p_fim timestamptz)
returns table (profissional_id uuid, comissao numeric)
language sql stable security definer set search_path = public as $$
  select i.profissional_id,
         round(sum(i.comissao_valor) * r.valor / nullif(t.total, 0), 2)
    from public.crediario_recebimentos r
    join public.crediarios cr on cr.id = r.crediario_id
    join public.comandas_totais t on t.id = cr.comanda_id
    join public.comanda_itens_calculados i on i.comanda_id = cr.comanda_id
   where r.salao_id = p_salao and r.recebido_em >= p_ini and r.recebido_em < p_fim
     and r.desfeito_em is null and cr.desfeito_em is null
   group by r.id, i.profissional_id, r.valor, t.total
$$;

-- ---------------------------------------------------------------------------
-- 7) O RESUMO DO PERÍODO (o relatório, 12) E A TELA DO CREDIÁRIO
-- ---------------------------------------------------------------------------
create or replace function public.crediario_no_periodo(p_salao uuid, p_ini timestamptz, p_fim timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'vendido', coalesce((select round(sum(cr.valor), 2) from public.crediarios cr
                           join public.comandas c on c.id = cr.comanda_id
                          where cr.salao_id = p_salao and cr.desfeito_em is null
                            and c.fechada_em >= p_ini and c.fechada_em < p_fim), 0),
    'recebido', coalesce((select round(sum(r.valor), 2) from public.crediario_recebimentos r
                           join public.crediarios cr on cr.id = r.crediario_id
                          where r.salao_id = p_salao and r.desfeito_em is null and cr.desfeito_em is null
                            and r.recebido_em >= p_ini and r.recebido_em < p_fim), 0),
    'aReceber', coalesce((select round(sum(greatest(public.saldo_da_parcela(pa.id), 0)), 2)
                            from public.crediario_parcelas pa
                            join public.crediarios cr on cr.id = pa.crediario_id
                           where pa.salao_id = p_salao and cr.desfeito_em is null), 0),
    'atrasado', coalesce((select round(sum(greatest(public.saldo_da_parcela(pa.id), 0)), 2)
                            from public.crediario_parcelas pa
                            join public.crediarios cr on cr.id = pa.crediario_id
                           where pa.salao_id = p_salao and cr.desfeito_em is null
                             and pa.vence_em < public.hoje_no_salao(p_salao)), 0))
$$;

/* A tela do Crediário: o resumo e as vendas com as parcelas e os
   recebimentos. As quitadas há mais de 60 dias ficam de fora (o histórico
   continua no banco). */
create or replace function public.crediario_painel(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_hoje date; v_fuso text; v_ini timestamptz;
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem o crediário.' using errcode = 'insufficient_privilege';
  end if;
  v_hoje := public.hoje_no_salao(p_salao);
  select coalesce(fuso, 'America/Sao_Paulo') into v_fuso from public.saloes where id = p_salao;
  v_ini := (date_trunc('month', v_hoje)::timestamp) at time zone v_fuso;
  return jsonb_build_object(
    'hoje', v_hoje,
    'resumo', public.crediario_no_periodo(p_salao, v_ini, now() + interval '1 day')
              || jsonb_build_object('venceHoje', coalesce((
                   select round(sum(greatest(public.saldo_da_parcela(pa.id), 0)), 2)
                     from public.crediario_parcelas pa join public.crediarios cr on cr.id = pa.crediario_id
                    where pa.salao_id = p_salao and cr.desfeito_em is null and pa.vence_em = v_hoje), 0)),
    'vendas', coalesce((
      select jsonb_agg(v order by v->>'proximo' nulls last, v->>'criadoEm' desc)
        from (select jsonb_build_object(
                'id', cr.id, 'comandaId', cr.comanda_id, 'numero', c.numero,
                'clienteId', cr.cliente_id, 'cliente', cl.nome, 'telefone', cl.telefone,
                'valor', cr.valor, 'criadoEm', cr.criado_em,
                'proximo', (select min(pa.vence_em) from public.crediario_parcelas pa
                             where pa.crediario_id = cr.id and public.saldo_da_parcela(pa.id) > 0),
                'parcelas', (select jsonb_agg(jsonb_build_object(
                               'id', pa.id, 'numero', pa.numero, 'valor', pa.valor, 'venceEm', pa.vence_em,
                               'saldo', public.saldo_da_parcela(pa.id),
                               'recebimentos', coalesce((select jsonb_agg(jsonb_build_object(
                                   'id', r.id, 'valor', r.valor, 'forma', r.forma, 'em', r.recebido_em)
                                   order by r.recebido_em)
                                  from public.crediario_recebimentos r
                                 where r.parcela_id = pa.id and r.desfeito_em is null), '[]'::jsonb))
                               order by pa.numero)
                               from public.crediario_parcelas pa where pa.crediario_id = cr.id)) as v
                from public.crediarios cr
                join public.comandas c on c.id = cr.comanda_id
                join public.clientes cl on cl.id = cr.cliente_id
               where cr.salao_id = p_salao and cr.desfeito_em is null
                 and (exists (select 1 from public.crediario_parcelas pa
                               where pa.crediario_id = cr.id and public.saldo_da_parcela(pa.id) > 0)
                      or exists (select 1 from public.crediario_recebimentos r
                                  where r.crediario_id = cr.id and r.desfeito_em is null
                                    and r.recebido_em > now() - interval '60 days'))) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- 8) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.cpf_valido(text) from public, anon;
grant execute on function public.cpf_valido(text) to authenticated;
revoke all on function public.tg_pagamento_crediario() from public, anon, authenticated;
revoke all on function public.tg_comanda_crediario() from public, anon, authenticated;
revoke all on function public.saldo_da_parcela(uuid) from public, anon, authenticated;
revoke all on function public.fator_a_vista(uuid) from public, anon, authenticated;
revoke all on function public.crediario_comissoes(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.crediario_no_periodo(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.vender_no_crediario(uuid, int, date) from public, anon;
revoke all on function public.receber_parcela(uuid, numeric, text) from public, anon;
revoke all on function public.desfazer_recebimento_crediario(uuid) from public, anon;
revoke all on function public.desfazer_crediario(uuid) from public, anon;
revoke all on function public.crediario_painel(uuid) from public, anon;
grant execute on function public.vender_no_crediario(uuid, int, date) to authenticated;
revoke all on function public.nova_venda_no_crediario(uuid, uuid, jsonb, uuid, numeric, numeric, text, int, date) from public, anon;
grant execute on function public.nova_venda_no_crediario(uuid, uuid, jsonb, uuid, numeric, numeric, text, int, date) to authenticated;
grant execute on function public.receber_parcela(uuid, numeric, text) to authenticated;
grant execute on function public.desfazer_recebimento_crediario(uuid) to authenticated;
grant execute on function public.desfazer_crediario(uuid) to authenticated;
grant execute on function public.crediario_painel(uuid) to authenticated;
