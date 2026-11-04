-- ===========================================================================
-- 56_conta_excluida.sql — a cliente excluiu a conta: o salão fica sabendo
--
-- O pedido: "e quando algum cliente excluir a conta dele, o que aparece pro
-- dono do salão?" Não aparecia nada. A exclusão (36) tira só o login dela: a
-- ficha é do SALÃO e continua em Clientes (`clientes.perfil_id` vira nulo),
-- com os horários marcados — e os lembretes, que vão para o WhatsApp da
-- ficha. O dono não tinha como saber que ela não entra mais pelo link.
--
-- Agora a ficha guarda QUANDO a conta sumiu (`conta_excluida_em`), Clientes
-- mostra "excluiu a conta do link em 04/11", e o sino avisa o balcão — com
-- quantas ainda têm horário marcado ou pacote ativo, que é o que pede uma
-- ligação. Visto o aviso, ele sai do sino (`conta_excluida_vista_em`); a
-- marca na ficha fica.
--
-- ── COMO O BANCO SABE ─────────────────────────────────────────────────────
-- Pelo próprio caminho da exclusão: apagar a conta (auth.users) apaga o
-- perfil, e a chave `clientes.perfil_id ... on delete set null` desliga a
-- ficha. O gatilho abaixo vê esse desligamento e confere que o perfil não
-- existe mais — então foi a CONTA que sumiu (pelo botão Excluir conta ou
-- pelo painel do Supabase), e não outra coisa desligando a ficha. Se ela
-- voltar e criar conta de novo com o mesmo WhatsApp, a ficha é religada e a
-- marca sai.
-- ===========================================================================

alter table public.clientes add column if not exists conta_excluida_em timestamptz;
alter table public.clientes add column if not exists conta_excluida_vista_em timestamptz;

create or replace function public.tg_cliente_conta_excluida()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.perfil_id is not null and new.perfil_id is null
     and not exists (select 1 from public.perfis p where p.id = old.perfil_id) then
    new.conta_excluida_em := now();
    new.conta_excluida_vista_em := null;
  elsif new.perfil_id is not null and old.perfil_id is null then
    -- Voltou: criou conta de novo e a ficha foi religada.
    new.conta_excluida_em := null;
    new.conta_excluida_vista_em := null;
  end if;
  return new;
end $$;
revoke all on function public.tg_cliente_conta_excluida() from public, anon, authenticated;
drop trigger if exists tg_cliente_conta_excluida on public.clientes;
create trigger tg_cliente_conta_excluida
  before update of perfil_id on public.clientes
  for each row execute function public.tg_cliente_conta_excluida();

-- O balcão viu o aviso do sino: sai de lá (a marca na ficha fica).
create or replace function public.ver_contas_excluidas(p_salao uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem este aviso.' using errcode = 'insufficient_privilege';
  end if;
  update public.clientes set conta_excluida_vista_em = now()
   where salao_id = p_salao and conta_excluida_em is not null and conta_excluida_vista_em is null;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'vistas', n);
end $$;

revoke all on function public.ver_contas_excluidas(uuid) from public, anon;
grant execute on function public.ver_contas_excluidas(uuid) to authenticated;
