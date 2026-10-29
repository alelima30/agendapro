-- ===========================================================================
-- 41_ficha_equipe.sql — o que só a equipe sabe: o "como fazer" de cada
-- serviço e os lembretes sobre a cliente
--
-- Os pedidos: "criar um lugar que o profissional consiga fazer o
-- procedimento, exemplo: coloração loiro perolado, quais as tintas e como
-- lavar o cabelo" e "no cadastro da cliente Maria, marcar algo que lembre
-- dela: essa não gosta de conversar, ou dá problema na hora do pagamento".
--
-- ── 1) O COMO FAZER MORA NO SERVIÇO ─────────────────────────────────────────
-- `servicos.procedimento`: as tintas, os tempos, a lavagem. A tabela de
-- serviços já é só da equipe (35_acesso.sql), e o link da cliente lê o
-- cardápio pela `vitrine()`, que escolhe as colunas uma a uma — esta não vai.
--
-- ── 2) OS LEMBRETES SÃO OUTRA TABELA, E NÃO UM CAMPO NA FICHA ───────────────
-- A cliente com conta LÊ a própria ficha (`cli_eu`, 02_rls.sql): é dado dela,
-- a LGPD manda deixar ver. "Dá problema na hora do pagamento" escrito no
-- `obs` ela leria pela API. O 02 já tinha deixado escrito: anotação interna
-- que a cliente não lê vira outra tabela, e não um campo escondido nesta.
--
-- Uma linha por cliente: as marcas tocadas na tela ("Prefere não conversar",
-- "Atenção no pagamento"...) e um texto livre. Quem lê e escreve é a equipe
-- do salão — a profissional que vai atender é quem mais precisa saber.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O COMO FAZER DO SERVIÇO
-- ---------------------------------------------------------------------------
alter table public.servicos add column if not exists procedimento text;
do $$ begin
  alter table public.servicos add constraint servicos_procedimento_tamanho
    check (procedimento is null or length(procedimento) <= 4000);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2) OS LEMBRETES DA EQUIPE SOBRE A CLIENTE
-- ---------------------------------------------------------------------------
create table if not exists public.clientes_lembretes (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  cliente_id    uuid not null references public.clientes(id) on delete cascade,
  marcas        text[] not null default '{}',
  texto         text,
  atualizado_em timestamptz not null default now(),
  check (cardinality(marcas) <= 12),
  check (texto is null or length(texto) <= 1000)
);
create unique index if not exists ux_lembrete_cliente on public.clientes_lembretes(cliente_id);
create index if not exists ix_lembrete_salao on public.clientes_lembretes(salao_id);

/* A cliente tem de ser do salão da linha: sem isto, quem é equipe de um
   salão gravaria lembrete apontando para a ficha de outro. A policy abaixo
   já garante que quem grava é da equipe de `salao_id`; aqui se garante que a
   ficha é desse mesmo salão. (Como todo gatilho do projeto, roda como dono —
   o tests/portas.test.sql cobra.) E as marcas chegam limpas: sem repetida,
   sem vazia, cada uma com até 40 letras, na ordem tocada. */
create or replace function public.tg_lembrete_cliente()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.clientes c
                  where c.id = new.cliente_id and c.salao_id = new.salao_id) then
    raise exception 'Esta cliente não é deste salão.' using errcode = 'check_violation';
  end if;
  new.marcas := coalesce(array(
    select m from (select left(btrim(x), 40) as m, min(o) as o
                     from unnest(new.marcas) with ordinality as t(x, o)
                    where btrim(coalesce(x, '')) <> ''
                    group by left(btrim(x), 40)) s
     order by o), '{}');
  new.texto := nullif(btrim(coalesce(new.texto, '')), '');
  if tg_op = 'UPDATE' then new.atualizado_em := now(); end if;
  return new;
end $$;

drop trigger if exists tg_lembrete_cliente on public.clientes_lembretes;
create trigger tg_lembrete_cliente
  before insert or update on public.clientes_lembretes
  for each row execute function public.tg_lembrete_cliente();

-- ---------------------------------------------------------------------------
-- 3) QUEM LÊ, QUEM ESCREVE
--
-- A equipe do salão, inteira: dono, recepção e profissional. A cliente não
-- tem policy aqui — nem logada, nem pelo link. O anônimo não tem nem grant.
-- ---------------------------------------------------------------------------
alter table public.clientes_lembretes enable row level security;

drop policy if exists lembretes_equipe on public.clientes_lembretes;
create policy lembretes_equipe on public.clientes_lembretes
  for all to authenticated
  using (public.e_equipe(salao_id)) with check (public.e_equipe(salao_id));

grant select, insert, update, delete on public.clientes_lembretes to authenticated;
revoke all on public.clientes_lembretes from anon;
revoke all on function public.tg_lembrete_cliente() from public, anon, authenticated;

-- A trava do modo suporte (38_suporte.sql) vale aqui como nas outras tabelas
-- do salão: a plataforma olhando o painel não escreve sem "Liberar edição".
do $$ begin
  if to_regprocedure('public.tg_suporte()') is not null then
    drop trigger if exists zz_suporte on public.clientes_lembretes;
    create trigger zz_suporte after insert or update or delete on public.clientes_lembretes
      for each row execute function public.tg_suporte();
  end if;
end $$;
