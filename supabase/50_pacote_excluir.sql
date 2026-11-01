-- ===========================================================================
-- 50_pacote_excluir.sql — excluir um pacote que o salão não quer mais
--
-- O pedido: "no pacote não tem como excluir caso eu não queira mais; se
-- tiver pessoas agendadas no pacote, não consigo excluir — só excluir quando
-- não tiver pessoas nesse pacote".
--
-- ── AS TRÊS SITUAÇÕES ─────────────────────────────────────────────────────
--   · tem cliente NO pacote (vínculo não cancelado e ainda dentro da
--     validade): NÃO exclui, e diz quem — tire as clientes do pacote primeiro
--     (o "Tirar") ou espere vencer;
--   · nunca foi vendido: apaga de verdade, com os serviços dele;
--   · já foi vendido, e ninguém está mais nele: sai da lista (arquivado), e o
--     HISTÓRICO FICA. Apagar levaria junto, em cascata, os vínculos antigos —
--     e com eles o que diz que aquelas sessões eram do pacote e quanto ele
--     rendeu. Some da tela; não some do passado.
--
-- E o banco segura o resto: apagar direto (pela API, pela sincronização do
-- painel) um pacote com cliente ou com histórico é recusado.
-- ===========================================================================

alter table public.pacotes add column if not exists arquivado_em timestamptz;

-- Quem está NO pacote agora: não cancelado e ainda dentro da validade.
create or replace function public.clientes_no_pacote(p_pacote uuid)
returns text language sql stable security definer set search_path = public as $$
  select string_agg(c.nome, ', ' order by c.nome)
    from public.pacote_clientes pc join public.clientes c on c.id = pc.cliente_id
   where pc.pacote_id = p_pacote and pc.cancelado_em is null
     and pc.vence_em >= public.hoje_no_salao(c.salao_id)
$$;

create or replace function public.excluir_pacote(p_pacote uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pac public.pacotes%rowtype; v_quem text;
begin
  select * into v_pac from public.pacotes where id = p_pacote;
  if v_pac.id is null then
    raise exception 'Não achei este pacote.' using errcode = 'check_violation';
  end if;
  if not public.e_gestor(v_pac.salao_id) then
    raise exception 'Só o proprietário ou um administrador exclui pacote.'
      using errcode = 'insufficient_privilege';
  end if;
  v_quem := public.clientes_no_pacote(p_pacote);
  if v_quem is not null then
    raise exception 'Ainda tem cliente neste pacote (%). Tire do pacote primeiro, ou espere vencer.', v_quem
      using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.pacote_clientes pc where pc.pacote_id = p_pacote) then
    delete from public.pacotes where id = p_pacote;
    return jsonb_build_object('ok', true, 'acao', 'apagado');
  end if;
  update public.pacotes set arquivado_em = now(), ativo = false where id = p_pacote;
  return jsonb_build_object('ok', true, 'acao', 'arquivado');
end $$;

-- A trava do banco: apagar direto não leva cliente nem histórico junto.
create or replace function public.tg_pacote_nao_apaga()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_quem text;
begin
  /* ⚠ EM CASCATA, DEIXA. Excluir a conta (36) apaga o salão, e o salão leva
     os pacotes junto — aí a trava não pode segurar, ou ninguém conseguiria
     mais excluir o próprio salão. A cascata chega aqui de dentro do gatilho
     da chave estrangeira (profundidade > 1); o apagar direto, com 1. */
  if pg_trigger_depth() > 1 then return old; end if;
  v_quem := public.clientes_no_pacote(old.id);
  if v_quem is not null then
    raise exception 'Ainda tem cliente neste pacote (%). Tire do pacote primeiro, ou espere vencer.', v_quem
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.pacote_clientes pc where pc.pacote_id = old.id) then
    raise exception 'Este pacote já foi vendido: ele sai da lista, mas o histórico fica. Use Excluir no pacote.'
      using errcode = 'check_violation';
  end if;
  return old;
end $$;
drop trigger if exists tg_pacote_nao_apaga on public.pacotes;
create trigger tg_pacote_nao_apaga before delete on public.pacotes
  for each row execute function public.tg_pacote_nao_apaga();

revoke all on function public.clientes_no_pacote(uuid) from public, anon, authenticated;
revoke all on function public.excluir_pacote(uuid) from public, anon;
grant execute on function public.excluir_pacote(uuid) to authenticated;
