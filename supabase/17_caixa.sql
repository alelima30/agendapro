-- ===========================================================================
-- AgendaPro — 17: o caixa do dia, e o estorno
--
-- ── O QUE FALTAVA ─────────────────────────────────────────────────────────
-- Havia pagamento e não havia GAVETA. O sistema sabia que a cliente pagou
-- R$ 50 em dinheiro e não sabia responder a única pergunta que a recepção
-- faz no fim do dia: "quanto tem que ter aqui dentro?"
--
-- E não havia como desfazer. Pagamento lançado errado — R$ 50 no débito que
-- foram em dinheiro, o valor digitado com um zero a mais — só saía apagando
-- a linha, o que some com o rastro: some o erro, some quem errou, e some a
-- razão de a gaveta não bater.
--
-- ── AS DUAS COISAS SÃO A MESMA COISA ──────────────────────────────────────
-- Estão no mesmo arquivo porque a conferência da gaveta é justamente o que
-- torna o estorno necessário: o caixa não bate, e aí se descobre o
-- pagamento errado. Um sem o outro deixa a recepção com um problema e sem a
-- ferramenta.
--
-- ── POR QUE O ESTORNO EXIGE A COMANDA ABERTA ──────────────────────────────
-- Estornar uma comanda FECHADA a deixaria fechada e com saldo a receber —
-- dois fatos que se contradizem, e que a tela teria de exibir juntos.
--
-- Reabrir sozinha seria pior: `fechada_em` viraria nulo, e a venda sairia do
-- mês em que aconteceu sem entrar em nenhum outro. Um relatório já conferido
-- encolheria, e ninguém saberia por quê.
--
-- Então o estorno não reabre nada: ele EXIGE que a comanda já esteja aberta.
-- Reabrir é um gesto que já existe, é deliberado, e quem o faz sabe que está
-- mexendo num fechamento. A ordem fica: reabrir, estornar, corrigir, fechar.
--
-- ── O QUE CONTA NA GAVETA ─────────────────────────────────────────────────
-- Só DINHEIRO. Cartão e Pix não estão na gaveta — conferir a gaveta contra o
-- total recebido faria a recepção procurar a tarde inteira uma diferença que
-- é só a maquininha. Os outros meios aparecem no fechamento como informação,
-- separados, sem entrar na conta do que se conta à mão.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O CAIXA
-- ---------------------------------------------------------------------------
create table if not exists public.caixas (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,

  aberto_em     timestamptz not null default now(),
  aberto_por    uuid references public.perfis(id) on delete set null,
  -- O troco que fica na gaveta de um dia para o outro.
  valor_abertura numeric(10,2) not null default 0 check (valor_abertura >= 0),

  fechado_em    timestamptz,
  fechado_por   uuid references public.perfis(id) on delete set null,
  -- O que foi CONTADO à mão no fim do dia. Nulo enquanto aberto.
  valor_contado numeric(10,2) check (valor_contado >= 0),

  observacao    text,

  -- Fechado tem que ter as três coisas juntas, ou nenhuma.
  check ( (fechado_em is null and valor_contado is null)
       or (fechado_em is not null and valor_contado is not null) )
);

create index if not exists ix_caixa_salao
  on public.caixas(salao_id, aberto_em desc);

/* ⚠ UM CAIXA ABERTO POR SALÃO, e o índice é quem garante.

   Conferir com `select ... where fechado_em is null` antes de inserir não
   garante nada: duas recepções abrindo ao mesmo tempo passam as duas pela
   conferência antes de qualquer uma gravar. O dinheiro do dia se dividiria
   entre dois caixas, e a gaveta não bateria em nenhum dos dois — com os dois
   "corretos" pela conta deles.

   Índice único parcial não tem essa brecha: quem chega em segundo lugar
   esbarra no banco. */
create unique index if not exists ux_caixa_aberto
  on public.caixas(salao_id) where (fechado_em is null);

alter table public.caixas enable row level security;
alter table public.caixas force row level security;

drop policy if exists caixa_ver on public.caixas;
create policy caixa_ver on public.caixas for select to authenticated
  using ( public.ve_agenda_toda(salao_id) );

drop policy if exists caixa_gerir on public.caixas;
create policy caixa_gerir on public.caixas for all to authenticated
  using ( public.ve_agenda_toda(salao_id) )
  with check ( public.ve_agenda_toda(salao_id) );

-- Quem atende NÃO enxerga o caixa: é dinheiro do salão inteiro, e a Fase 2
-- pede que profissional não veja informação financeira global.
revoke all on public.caixas from anon;
grant select, insert, update on public.caixas to authenticated;

-- ---------------------------------------------------------------------------
-- 2) SANGRIA E SUPRIMENTO
-- ---------------------------------------------------------------------------
-- Sangria: dinheiro que SAI da gaveta sem ser troco (levar ao banco, pagar o
-- entregador). Suprimento: dinheiro que ENTRA sem ser venda (trazer troco).
--
-- `motivo` é obrigatório, e não é burocracia: uma sangria sem motivo é
-- indistinguível de um desfalque na hora de conferir, três dias depois.
create table if not exists public.caixa_movimentos (
  id         uuid primary key default gen_random_uuid(),
  caixa_id   uuid not null references public.caixas(id) on delete cascade,
  salao_id   uuid not null references public.saloes(id) on delete cascade,
  tipo       text not null check (tipo in ('sangria','suprimento')),
  valor      numeric(10,2) not null check (valor > 0),
  motivo     text not null check (length(btrim(motivo)) >= 3),
  quem       uuid references public.perfis(id) on delete set null,
  criado_em  timestamptz not null default now()
);

create index if not exists ix_mov_caixa on public.caixa_movimentos(caixa_id);

alter table public.caixa_movimentos enable row level security;
alter table public.caixa_movimentos force row level security;

drop policy if exists mov_gerir on public.caixa_movimentos;
create policy mov_gerir on public.caixa_movimentos for all to authenticated
  using ( public.ve_agenda_toda(salao_id) )
  with check ( public.ve_agenda_toda(salao_id) );

revoke all on public.caixa_movimentos from anon;
grant select, insert on public.caixa_movimentos to authenticated;

-- Movimento em caixa já fechado reescreveria uma conferência assinada.
create or replace function public.tg_mov_caixa_aberto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.caixas c
              where c.id = new.caixa_id and c.fechado_em is not null) then
    raise exception 'Este caixa já foi fechado. Abra o caixa do dia para lançar.'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists tg_mov_caixa_aberto on public.caixa_movimentos;
create trigger tg_mov_caixa_aberto
  before insert on public.caixa_movimentos
  for each row execute function public.tg_mov_caixa_aberto();

-- ---------------------------------------------------------------------------
-- 3) O PAGAMENTO SABE EM QUAL CAIXA CAIU
-- ---------------------------------------------------------------------------
-- Sem esta coluna, "quanto entrou hoje em dinheiro" só poderia ser respondido
-- por intervalo de horas — e um caixa que vira a madrugada, ou dois turnos no
-- mesmo dia, dariam a resposta errada.
alter table public.pagamentos
  add column if not exists caixa_id uuid
  references public.caixas(id) on delete set null;

create index if not exists ix_pgto_caixa on public.pagamentos(caixa_id);

-- Preenchido pelo BANCO, com o caixa que estiver aberto. A tela não escolhe:
-- deixar a tela mandar o caixa é deixar um pagamento cair no caixa de ontem
-- por causa de uma aba que ficou aberta.
create or replace function public.tg_pagamento_caixa() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_salao uuid;
begin
  if new.caixa_id is not null then
    -- Já veio escolhido (importação, correção): respeita, mas não inventa.
    return new;
  end if;
  select c.salao_id into v_salao from public.comandas c where c.id = new.comanda_id;
  select k.id into new.caixa_id
    from public.caixas k
   where k.salao_id = v_salao and k.fechado_em is null
   limit 1;
  return new;
end $$;

drop trigger if exists tg_pagamento_caixa on public.pagamentos;
create trigger tg_pagamento_caixa
  before insert on public.pagamentos
  for each row execute function public.tg_pagamento_caixa();

-- ---------------------------------------------------------------------------
-- 4) O ESTORNO
-- ---------------------------------------------------------------------------
create table if not exists public.estornos (
  id           uuid primary key default gen_random_uuid(),
  pagamento_id uuid not null references public.pagamentos(id) on delete cascade,
  salao_id     uuid not null references public.saloes(id) on delete cascade,
  valor        numeric(10,2) not null check (valor > 0),
  motivo       text not null check (length(btrim(motivo)) >= 3),
  quem         uuid references public.perfis(id) on delete set null,
  criado_em    timestamptz not null default now()
);

create index if not exists ix_estorno_pgto on public.estornos(pagamento_id);

alter table public.estornos enable row level security;
alter table public.estornos force row level security;

drop policy if exists estorno_gerir on public.estornos;
create policy estorno_gerir on public.estornos for all to authenticated
  using ( public.ve_agenda_toda(salao_id) )
  with check ( public.ve_agenda_toda(salao_id) );

revoke all on public.estornos from anon;
-- Sem UPDATE e sem DELETE de propósito: estorno é registro do que aconteceu.
-- Corrigir um estorno errado é lançar o pagamento de novo, não apagar a
-- linha — apagar sumiria com o rastro, que é exatamente o que o estorno
-- existe para preservar.
grant select, insert on public.estornos to authenticated;

/* As três travas do estorno, num gatilho só.

   Elas moram aqui, e não na tela, pelo mesmo motivo de sempre neste
   projeto: regra de dinheiro que não está num gatilho é regra que não
   existe. A recepção alcança a tabela `estornos` direto pelo PostgREST. */
create or replace function public.tg_estorno_cabe() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_valor  numeric;
  v_ja     numeric;
  v_status text;
  v_salao  uuid;
begin
  select p.valor, c.status, c.salao_id
    into v_valor, v_status, v_salao
    from public.pagamentos p
    join public.comandas c on c.id = p.comanda_id
   where p.id = new.pagamento_id;

  if v_valor is null then
    raise exception 'Pagamento não encontrado.' using errcode = 'no_data_found';
  end if;

  -- 1) o salão do estorno é o da comanda, e não o que a tela disser
  new.salao_id := v_salao;

  -- 2) comanda fechada não estorna. Ver o cabeçalho: estornar sem reabrir
  --    deixaria a comanda fechada e devendo ao mesmo tempo.
  if v_status = 'fechada' then
    raise exception 'Reabra a comanda antes de estornar este pagamento.'
      using errcode = 'check_violation';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Esta comanda foi cancelada.' using errcode = 'check_violation';
  end if;

  -- 3) não se estorna mais do que se recebeu
  select coalesce(sum(e.valor), 0) into v_ja
    from public.estornos e where e.pagamento_id = new.pagamento_id;

  if new.valor > v_valor - v_ja + 0.005 then
    raise exception 'Estorno de % maior que o disponível neste pagamento: %.',
      public.reais(new.valor), public.reais(v_valor - v_ja)
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

drop trigger if exists tg_estorno_cabe on public.estornos;
create trigger tg_estorno_cabe
  before insert on public.estornos
  for each row execute function public.tg_estorno_cabe();

-- ---------------------------------------------------------------------------
-- 5) O QUE JÁ FOI PAGO PASSA A DESCONTAR O QUE FOI ESTORNADO
-- ---------------------------------------------------------------------------
-- Sem isto, uma comanda estornada continuaria "paga" e fecharia de novo sem
-- ninguém receber nada — o estorno seria enfeite.
drop view if exists public.comandas_totais;

create view public.comandas_totais
with (security_invoker = true) as
  select c.id,
         c.salao_id,
         c.cliente_id,
         c.agendamento_id,
         c.numero,
         c.status,
         c.aberta_em,
         c.fechada_em,
         c.comissao_sobre,
         coalesce(i.subtotal, 0)                        as subtotal,
         c.desconto,
         c.acrescimo,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo as total,
         coalesce(i.comissao, 0)                        as comissao_total,
         coalesce(p.pago, 0)                            as pago,
         coalesce(p.estornado, 0)                       as estornado,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
           - coalesce(p.pago, 0)                        as falta,
         case
           when c.status = 'cancelada' then 'cancelado'
           when coalesce(p.pago, 0) = 0 then 'pendente'
           when coalesce(p.pago, 0)
                >= coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
             then 'pago'
           else 'parcial'
         end                                            as situacao
    from public.comandas c
    left join (select k.comanda_id,
                      sum(k.total)          as subtotal,
                      sum(k.comissao_valor) as comissao
                 from public.comanda_itens_calculados k
                group by k.comanda_id) i on i.comanda_id = c.id
    left join (select g.comanda_id,
                      -- `pago` já é LÍQUIDO de estorno: é o que sobrou de
                      -- verdade. Quem lê esta coluna — a trava do
                      -- fechamento, a tela, o relatório — passa a enxergar
                      -- o estorno sem precisar saber que ele existe.
                      sum(g.valor) - coalesce(sum(e.estornado), 0) as pago,
                      coalesce(sum(e.estornado), 0)                as estornado
                 from public.pagamentos g
                 left join (select x.pagamento_id, sum(x.valor) as estornado
                              from public.estornos x
                             group by x.pagamento_id) e
                        on e.pagamento_id = g.id
                group by g.comanda_id) p on p.comanda_id = c.id;

grant select on public.comandas_totais to authenticated;

-- ---------------------------------------------------------------------------
-- 5b) A TRAVA DO PAGAMENTO PRECISA ENXERGAR O ESTORNO
-- ---------------------------------------------------------------------------
-- `tg_pagamento_cabe` nasceu na Fase 2A somando `pagamentos.valor` cru. Com
-- o estorno existindo, essa soma passa a mentir na pior hora:
--
--   comanda de R$ 100, paga em dinheiro, valor errado
--   estorno de R$ 100
--   a recepção tenta lançar o pagamento certo  →  RECUSADO
--   "Pagamento de R$ 100,00 excede o que falta nesta comanda: R$ 0,00"
--
-- A trava diria que a comanda está paga por uma soma que já não é verdade, e
-- travaria justamente a correção que o estorno existe para permitir. O
-- estorno viraria um beco sem saída.
--
-- Foi o `caixa.test.sql` que pegou, na seção que lança o pagamento novo
-- depois de estornar — e não numa seção sobre a trava, três arquivos longe
-- da causa.
create or replace function public.tg_pagamento_cabe()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_total numeric(10,2);
  v_pago  numeric(10,2);
begin
  select t.total into v_total from public.comandas_totais t where t.id = new.comanda_id;

  select coalesce(sum(p.valor), 0) - coalesce(sum(e.estornado), 0)
    into v_pago
    from public.pagamentos p
    left join (select x.pagamento_id, sum(x.valor) as estornado
                 from public.estornos x group by x.pagamento_id) e
           on e.pagamento_id = p.id
   where p.comanda_id = new.comanda_id
     and (tg_op = 'INSERT' or p.id <> new.id);

  if v_total is null then
    raise exception 'Comanda não encontrada.' using errcode = 'check_violation';
  end if;

  if v_pago + new.valor > v_total + 0.005 then
    raise exception
      'Pagamento de % excede o que falta nesta comanda: %.',
      public.reais(new.valor), public.reais(greatest(v_total - v_pago, 0))
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 6) A CONFERÊNCIA DA GAVETA
-- ---------------------------------------------------------------------------
-- Devolve tudo o que o fechamento precisa mostrar, num jsonb só: o esperado
-- em dinheiro, o que veio por cada meio, os movimentos, e — quando já
-- fechado — a diferença entre o contado e o esperado.
create or replace function public.conferir_caixa(p_caixa uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  k         public.caixas%rowtype;
  v_dinheiro numeric;
  v_sangria  numeric;
  v_suprim   numeric;
  v_esperado numeric;
begin
  select * into k from public.caixas where id = p_caixa;
  if k.id is null then
    raise exception 'Caixa não encontrado.' using errcode = 'no_data_found';
  end if;
  if not public.ve_agenda_toda(k.salao_id) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;

  -- Só dinheiro entra na conta da gaveta, e já descontado o que foi
  -- estornado: devolver R$ 50 tira R$ 50 da gaveta.
  select coalesce(sum(g.valor), 0) - coalesce(sum(e.estornado), 0)
    into v_dinheiro
    from public.pagamentos g
    left join (select x.pagamento_id, sum(x.valor) as estornado
                 from public.estornos x group by x.pagamento_id) e
           on e.pagamento_id = g.id
   where g.caixa_id = p_caixa and g.forma = 'dinheiro';

  select coalesce(sum(m.valor) filter (where m.tipo = 'sangria'), 0),
         coalesce(sum(m.valor) filter (where m.tipo = 'suprimento'), 0)
    into v_sangria, v_suprim
    from public.caixa_movimentos m where m.caixa_id = p_caixa;

  v_esperado := k.valor_abertura + v_dinheiro + v_suprim - v_sangria;

  return jsonb_build_object(
    'id',            k.id,
    'abertoEm',      k.aberto_em,
    'fechadoEm',     k.fechado_em,
    'valorAbertura', k.valor_abertura,
    'dinheiro',      v_dinheiro,
    'suprimentos',   v_suprim,
    'sangrias',      v_sangria,
    'esperado',      v_esperado,
    'contado',       k.valor_contado,
    -- Positivo: sobrou na gaveta. Negativo: faltou.
    'diferenca',     case when k.valor_contado is null then null
                          else round(k.valor_contado - v_esperado, 2) end,
    -- Os outros meios NÃO entram no esperado, e aparecem à parte para a
    -- recepção conferir com a maquininha sem confundir com a gaveta.
    'outrosMeios', coalesce((
      select jsonb_agg(jsonb_build_object('forma', y.forma, 'valor', y.valor)
                       order by y.valor desc)
        from (select g.forma,
                     round(sum(g.valor) - coalesce(sum(e.estornado), 0), 2) as valor
                from public.pagamentos g
                left join (select x.pagamento_id, sum(x.valor) as estornado
                             from public.estornos x group by x.pagamento_id) e
                       on e.pagamento_id = g.id
               where g.caixa_id = p_caixa and g.forma <> 'dinheiro'
               group by g.forma) y), '[]'::jsonb),
    'movimentos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', m.tipo, 'valor', m.valor, 'motivo', m.motivo,
               'criadoEm', m.criado_em) order by m.criado_em)
        from public.caixa_movimentos m where m.caixa_id = p_caixa), '[]'::jsonb)
  );
end $$;

revoke all on function public.conferir_caixa(uuid) from public, anon;
grant execute on function public.conferir_caixa(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) FECHAR O CAIXA
-- ---------------------------------------------------------------------------
-- Fechar é gravar o que foi CONTADO. A diferença não é gravada: ela é
-- sempre recalculada de coisas que já não mudam — o valor de abertura, os
-- pagamentos daquele caixa, os movimentos daquele caixa. Diferença guardada
-- é mais um número para ficar velho.
create or replace function public.fechar_caixa(
  p_caixa uuid, p_contado numeric, p_observacao text default null)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare k public.caixas%rowtype;
begin
  select * into k from public.caixas where id = p_caixa;
  if k.id is null then
    raise exception 'Caixa não encontrado.' using errcode = 'no_data_found';
  end if;
  if not public.ve_agenda_toda(k.salao_id) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  if k.fechado_em is not null then
    raise exception 'Este caixa já foi fechado.' using errcode = 'check_violation';
  end if;
  if p_contado is null or p_contado < 0 then
    raise exception 'Informe quanto tem na gaveta.' using errcode = 'check_violation';
  end if;

  update public.caixas
     set fechado_em = now(), fechado_por = auth.uid(),
         valor_contado = p_contado,
         observacao = coalesce(p_observacao, observacao)
   where id = p_caixa;

  return public.conferir_caixa(p_caixa);
end $$;

revoke all on function public.fechar_caixa(uuid, numeric, text) from public, anon;
grant execute on function public.fechar_caixa(uuid, numeric, text) to authenticated;
