-- ===========================================================================
-- 49_remarcar.sql — o salão remarca um horário
--
-- O pedido: "na onde entro para remarcar caso precise?" — e não havia onde.
-- A janela do atendimento só mudava a situação e a forma de pagamento. O
-- caminho que sobrava era cancelar e marcar outro no "+ Novo", e para sessão
-- de pacote isso estraga: o horário novo nasce como atendimento comum,
-- cobrando o serviço, solto do pacote.
--
-- Remarcar MOVE o próprio horário: o mesmo agendamento, com o mesmo pacote,
-- os mesmos serviços, o mesmo valor e a mesma duração, em outro dia, outra
-- hora ou com outra profissional. O lembrete da cliente e o da equipe vão
-- junto (os gatilhos do 21 reescrevem quando a hora ou a pessoa mudam).
--
-- ── O QUE O BANCO CONFERE ─────────────────────────────────────────────────
--   · quem: o balcão e a gestão remarcam qualquer horário; quem atende,
--     só o próprio, e para si mesma;
--   · o quê: só horário pendente ou confirmado, e para um instante que ainda
--     vem;
--   · onde: a mesma pergunta da agenda (`porque_nao_cabe`, 14), ignorando o
--     próprio horário. Fora da jornada dá para encaixar, com a confirmação de
--     quem remarca (e o encaixe fica com o nome dela); choque e bloqueio, não;
--   · o pacote: dentro da validade e nos dias da semana em que ele vale — as
--     mesmas regras de quando ele foi montado (43).
-- ===========================================================================

create or replace function public.remarcar_pelo_salao(
  p_agendamento uuid, p_inicio timestamptz,
  p_profissional uuid default null, p_encaixe boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.agendamentos%rowtype;
  v_prof uuid; v_fim timestamptz; v_fuso text; v_dia date;
  v_motivo text; v_encaixavel boolean := false; v_encaixe boolean := false;
  v_vence date; v_dias smallint[];
begin
  if auth.uid() is null then
    raise exception 'Entre de novo para remarcar.' using errcode = 'insufficient_privilege';
  end if;
  select * into a from public.agendamentos where id = p_agendamento for update;
  if a.id is null then
    raise exception 'Não achei este horário.' using errcode = 'check_violation';
  end if;
  v_prof := coalesce(p_profissional, a.profissional_id);
  if not public.ve_agenda_toda(a.salao_id) then
    if a.profissional_id is distinct from public.meu_profissional_id(a.salao_id)
       or v_prof is distinct from a.profissional_id then
      raise exception 'Só o balcão e a gestão remarcam o horário de outra pessoa.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if a.arquivado_em is not null or a.status not in ('pendente', 'confirmado') then
    raise exception 'Só dá para remarcar um horário pendente ou confirmado.'
      using errcode = 'check_violation';
  end if;
  if p_inicio is null or p_inicio <= now() then
    raise exception 'Escolha um horário que ainda vai acontecer.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.profissionais pr
                  where pr.id = v_prof and pr.salao_id = a.salao_id and pr.ativo) then
    raise exception 'Escolha quem vai atender.' using errcode = 'check_violation';
  end if;

  v_fim := p_inicio + (a.fim - a.inicio);
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso from public.saloes s where s.id = a.salao_id;
  v_dia := (p_inicio at time zone v_fuso)::date;

  -- Sessão de pacote: a validade e os dias dele.
  if a.pacote_cliente_id is not null then
    select pc.vence_em, p.dias into v_vence, v_dias
      from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
     where pc.id = a.pacote_cliente_id;
    if v_vence is not null and v_dia > v_vence then
      return jsonb_build_object('ok', false, 'encaixavel', false,
        'motivo', 'Passa da validade do pacote (vence em ' || to_char(v_vence, 'DD/MM') || ').');
    end if;
    if coalesce(cardinality(v_dias), 0) > 0
       and not (extract(dow from v_dia)::smallint = any(v_dias)) then
      return jsonb_build_object('ok', false, 'encaixavel', false,
        'motivo', 'O pacote vale só ' || public.dias_por_extenso(v_dias) || '.');
    end if;
  end if;

  v_motivo := public.porque_nao_cabe(v_prof, p_inicio, v_fim, a.id);
  if v_motivo is not null then
    -- Só a jornada o encaixe afrouxa (a mesma régua do "+ Novo").
    v_encaixavel := v_motivo like 'Fora da jornada%'
      and public.ha_choque(v_prof, p_inicio, v_fim, a.id) is null
      and public.ha_bloqueio(v_prof, p_inicio, v_fim) is null;
    if not (v_encaixavel and coalesce(p_encaixe, false)) then
      return jsonb_build_object('ok', false, 'motivo', v_motivo, 'encaixavel', v_encaixavel);
    end if;
    v_encaixe := true;
  end if;

  begin
    update public.agendamentos
       set inicio = p_inicio, fim = v_fim, profissional_id = v_prof,
           encaixe = v_encaixe,
           encaixe_por = case when v_encaixe then auth.uid() end
     where id = a.id;
  exception when exclusion_violation then
    return jsonb_build_object('ok', false, 'encaixavel', false,
      'motivo', 'Alguém acabou de marcar nesse horário. Escolha outro.');
  end;

  -- Outra profissional: a comissão passa a ser a dela (a do serviço, se
  -- houver; senão a da ficha dela) — a mesma conta de quando se marca.
  if v_prof is distinct from a.profissional_id then
    update public.agendamento_servicos asv
       set comissao_pct = coalesce(sv.comissao_pct, pr.comissao_pct, 0)
      from public.servicos sv, public.profissionais pr
     where asv.agendamento_id = a.id and sv.id = asv.servico_id and pr.id = v_prof;
  end if;

  -- O lembrete que tinha sido cancelado (remarcado em cima da hora, por
  -- exemplo) volta, para a hora nova. O que já saiu não se repete.
  perform public.refazer_lembrete_cliente(a.id);

  -- E a cliente fica sabendo: o horário de antes e o novo (52, depois que
  -- a plataforma liga o modelo e se o salão não desligou a chave). A guarda
  -- é para o banco que ainda não tem o 52.
  if to_regprocedure('public.avisar_remarcado(uuid,timestamptz,uuid)') is not null then
    perform public.avisar_remarcado(a.id, a.inicio, a.profissional_id);
  end if;

  return jsonb_build_object('ok', true, 'encaixe', v_encaixe,
    'data', to_char(p_inicio at time zone v_fuso, 'DD/MM/YYYY'),
    'hora', to_char(p_inicio at time zone v_fuso, 'HH24:MI'));
end $$;

revoke all on function public.remarcar_pelo_salao(uuid, timestamptz, uuid, boolean) from public, anon;
grant execute on function public.remarcar_pelo_salao(uuid, timestamptz, uuid, boolean) to authenticated;

/* ── QUEM ATENDEU ──────────────────────────────────────────────────────────
   "Como administrar para saber quem atendeu?" A comissão vai para a
   profissional do horário quando ele é concluído (16, 44). O Remarcar troca
   quem vai atender, mas só antes da hora — e a troca de última hora (a Ju
   faltou, a Bia atendeu às 14h) ficava com a Ju.

   Aqui o balcão diz quem atendeu, também depois da hora, enquanto o horário
   não foi concluído (concluído, a comissão já está contada). Horário de
   outro dia ainda por vir é com o Remarcar, que confere a agenda dela.

   A agenda ainda vale: se a Bia tinha outra cliente nesse mesmo horário, ela
   não atendeu esta — recusa. Fora da jornada dela (ou num bloqueio), ela
   atendeu assim mesmo: fica como ENCAIXE, o jeito que a agenda já tem de
   dizer isso. E a cliente não recebe mensagem: o horário dela não mudou. */
create or replace function public.trocar_quem_atende(p_agendamento uuid, p_profissional uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.agendamentos%rowtype; v_fuso text; v_nome text; v_encaixe boolean;
begin
  if auth.uid() is null then
    raise exception 'Entre de novo para trocar quem atendeu.' using errcode = 'insufficient_privilege';
  end if;
  select * into a from public.agendamentos where id = p_agendamento for update;
  if a.id is null then
    raise exception 'Não achei este horário.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(a.salao_id) then
    raise exception 'Só o balcão e a gestão trocam quem atendeu.' using errcode = 'insufficient_privilege';
  end if;
  if a.arquivado_em is not null or a.status not in ('pendente', 'confirmado', 'em_atendimento') then
    raise exception 'Só dá para trocar quem atendeu antes de concluir o horário.'
      using errcode = 'check_violation';
  end if;
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso from public.saloes s where s.id = a.salao_id;
  if (a.inicio at time zone v_fuso)::date > public.hoje_no_salao(a.salao_id) then
    raise exception 'Este horário é de outro dia: use Remarcar para escolher quem vai atender.'
      using errcode = 'check_violation';
  end if;
  select pr.nome into v_nome from public.profissionais pr
   where pr.id = p_profissional and pr.salao_id = a.salao_id and pr.ativo;
  if v_nome is null then
    raise exception 'Escolha quem atendeu.' using errcode = 'check_violation';
  end if;
  if p_profissional = a.profissional_id then
    return jsonb_build_object('ok', true, 'mudou', false, 'profissional', v_nome);
  end if;
  if public.ha_choque(p_profissional, a.inicio, a.fim, a.id) is not null then
    raise exception '% tem outro horário marcado nesse mesmo horário.', v_nome
      using errcode = 'check_violation';
  end if;

  v_encaixe := a.encaixe
    or not public.cabe_na_jornada(p_profissional, a.inicio, a.fim)
    or public.ha_bloqueio(p_profissional, a.inicio, a.fim) is not null;
  begin
    update public.agendamentos
       set profissional_id = p_profissional, encaixe = v_encaixe,
           encaixe_por = case when v_encaixe and not a.encaixe then auth.uid() else a.encaixe_por end
     where id = a.id;
  exception when exclusion_violation then
    raise exception '% tem outro horário marcado nesse mesmo horário.', v_nome
      using errcode = 'check_violation';
  end;

  -- A comissão passa a ser a dela (a do serviço, se houver; senão a da
  -- ficha dela) — a mesma conta do Remarcar.
  update public.agendamento_servicos asv
     set comissao_pct = coalesce(sv.comissao_pct, pr.comissao_pct, 0)
    from public.servicos sv, public.profissionais pr
   where asv.agendamento_id = a.id and sv.id = asv.servico_id and pr.id = p_profissional;

  -- O lembrete que ainda não saiu diz a profissional: refeito com a nova.
  perform public.refazer_lembrete_cliente(a.id);

  return jsonb_build_object('ok', true, 'mudou', true, 'profissional', v_nome, 'encaixe', v_encaixe);
end $$;

revoke all on function public.trocar_quem_atende(uuid, uuid) from public, anon;
grant execute on function public.trocar_quem_atende(uuid, uuid) to authenticated;
