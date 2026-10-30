-- ===========================================================================
-- 44_pacote_comissao.sql — a comissão da sessão de pacote
--
-- O pedido: "o pacote, e aí quem é o profissional, e aí a definição da
-- comissão?" Até aqui a sessão de pacote não gerava comissão nenhuma: ela
-- sai a R$ 0,00 (a cliente pagou adiantado) e não vira comanda (28), e a
-- venda do pacote vira comanda SEM profissional (43). Quem atendia a Maria
-- toda terça trabalhava o mês inteiro sem comissão.
--
-- ── AS DUAS DECISÕES DO DONO ──────────────────────────────────────────────
-- 1. PROPORCIONAL. O valor do pacote é repartido pelo preço cheio de cada
--    sessão: pacote de R$ 220 com mão (R$ 40), mão e pé (R$ 90), mão, mão e
--    pé — o cheio somaria R$ 260, então cada real cheio vale R$ 220/260. A
--    semana de mão vale R$ 33,85, a de mão e pé R$ 76,15. Quem faz mais,
--    ganha mais; e a soma nunca passa do que a cliente pagou.
-- 2. AO ATENDER. A comissão conta no dia em que a sessão é concluída, mesmo
--    com o pacote ainda a receber: a profissional trabalhou, e cobrar a
--    cliente é com o salão.
--
-- ── QUEM GANHA ────────────────────────────────────────────────────────────
-- Quem ATENDEU aquela sessão (`profissional_id` do horário), e não quem foi
-- escolhida ao montar o pacote: a terça em que a Ju faltou e a Bia atendeu é
-- da Bia. A taxa é a mesma escada de sempre (`comissao_de`, 16): o par
-- serviço+profissional, o serviço, a profissional — porcentagem sobre a
-- parte da sessão, mais o valor fixo por serviço.
--
-- ── O VALOR DA SESSÃO, QUANDO NEM TODAS ESTÃO MARCADAS ────────────────────
-- Na agenda fixa, as quatro terças existem desde o primeiro dia e a conta é
-- exata. No pacote que a cliente vai marcando pelo link, as sessões que
-- ainda não existem entram pela média do preço cheio das que já existem. A
-- comissão de cada sessão é CONGELADA no dia em que ela é atendida (como a
-- taxa do item da comanda, no 16): o mês fechado não muda depois.
--
-- ── ONDE APARECE ──────────────────────────────────────────────────────────
-- No relatório do período (`relatorio`, 12), junto da comissão das comandas,
-- por profissional; e no total de comissões do painel do dia (18). Não é
-- faturamento: o dinheiro do pacote já entrou uma vez, na venda (43).
-- ===========================================================================

create table if not exists public.pacote_comissoes (
  id                uuid primary key default gen_random_uuid(),
  salao_id          uuid not null references public.saloes(id) on delete cascade,
  agendamento_id    uuid not null references public.agendamentos(id) on delete cascade,
  pacote_cliente_id uuid references public.pacote_clientes(id) on delete set null,
  profissional_id   uuid references public.profissionais(id) on delete set null,
  base              numeric(10,2) not null check (base >= 0),
  comissao          numeric(10,2) not null check (comissao >= 0),
  atendida_em       timestamptz not null default now()
);
create unique index if not exists ux_pacote_comissao_agend on public.pacote_comissoes(agendamento_id);
create index if not exists ix_pacote_comissao_salao on public.pacote_comissoes(salao_id, atendida_em);

-- ---------------------------------------------------------------------------
-- 1) A PARTE DA SESSÃO NO VALOR DO PACOTE
--
-- O fator é "quanto vale cada real de preço cheio": o valor do pacote sobre
-- o preço cheio de todas as sessões dele (as que gastam sessão, como no 27).
-- Nunca passa de 1 — a sessão não vale mais que o preço cheio.
-- ---------------------------------------------------------------------------
create or replace function public.fator_do_pacote(p_pacote_cliente uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_valor numeric; v_sessoes int; v_soma numeric; v_n int; v_den numeric;
begin
  select coalesce(nullif(pc.valor, 0), p.preco, 0), pc.sessoes
    into v_valor, v_sessoes
    from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
   where pc.id = p_pacote_cliente;
  if coalesce(v_valor, 0) <= 0 then return 0; end if;

  select coalesce(sum(x.cheio), 0), count(*) into v_soma, v_n
    from (select a.id, coalesce(sum(s.preco), 0) as cheio
            from public.agendamentos a
            join public.agendamento_servicos s on s.agendamento_id = a.id
           where a.pacote_cliente_id = p_pacote_cliente
             and a.status in ('pendente', 'confirmado', 'em_atendimento', 'concluido')
           group by a.id) x;
  if v_n = 0 or v_soma <= 0 then return 0; end if;

  -- As sessões que ainda não existem entram pela média das que existem.
  v_den := v_soma + greatest(coalesce(v_sessoes, 0) - v_n, 0) * (v_soma / v_n);
  return least(1, v_valor / v_den);
end $$;

-- ---------------------------------------------------------------------------
-- 2) O GATILHO: CONCLUIU, CONGELA; DESFEZ, SAI
-- ---------------------------------------------------------------------------
create or replace function public.tg_pacote_comissao()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_fator numeric; v_base numeric := 0; v_com numeric := 0; s record; t record;
begin
  -- Desfazer: a recepção concluiu por engano e voltou atrás.
  if tg_op = 'UPDATE' and old.status = 'concluido' and new.status <> 'concluido' then
    delete from public.pacote_comissoes where agendamento_id = new.id;
    return new;
  end if;
  if new.status <> 'concluido' or new.pacote_cliente_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'concluido' then return new; end if;
  -- Quem abriu comanda para a sessão já tem a comissão no item dela.
  if exists (select 1 from public.comandas c where c.agendamento_id = new.id) then
    return new;
  end if;

  v_fator := public.fator_do_pacote(new.pacote_cliente_id);
  for s in select asv.servico_id, coalesce(asv.preco, 0) as preco
             from public.agendamento_servicos asv where asv.agendamento_id = new.id loop
    t := public.comissao_de('servico', s.servico_id, null, new.profissional_id);
    v_base := v_base + s.preco * v_fator;
    v_com := v_com + s.preco * v_fator * coalesce(t.pct, 0) / 100 + coalesce(t.fixa, 0);
  end loop;
  -- Arredonda UMA vez, na sessão: por serviço, as quatro terças de R$ 220
  -- somariam R$ 220,02.
  v_base := round(v_base, 2);
  v_com := round(v_com, 2);

  insert into public.pacote_comissoes
    (salao_id, agendamento_id, pacote_cliente_id, profissional_id, base, comissao)
  values (new.salao_id, new.id, new.pacote_cliente_id, new.profissional_id, v_base, v_com)
  on conflict (agendamento_id) do update
    set profissional_id = excluded.profissional_id, base = excluded.base,
        comissao = excluded.comissao, atendida_em = now();
  return new;
end $$;

drop trigger if exists tg_pacote_comissao on public.agendamentos;
create trigger tg_pacote_comissao
  after insert or update of status on public.agendamentos
  for each row execute function public.tg_pacote_comissao();

-- ---------------------------------------------------------------------------
-- 3) QUEM LÊ
--
-- Comissão é dinheiro da casa: a gestão lê, como o relatório (12). Ninguém
-- escreve pela API — só o gatilho.
-- ---------------------------------------------------------------------------
alter table public.pacote_comissoes enable row level security;
drop policy if exists pacote_comissoes_ler on public.pacote_comissoes;
create policy pacote_comissoes_ler on public.pacote_comissoes
  for select to authenticated using (public.e_gestor(salao_id));
grant select on public.pacote_comissoes to authenticated;
revoke insert, update, delete on public.pacote_comissoes from authenticated;
revoke all on public.pacote_comissoes from anon;
revoke all on function public.fator_do_pacote(uuid) from public, anon, authenticated;
revoke all on function public.tg_pacote_comissao() from public, anon, authenticated;
