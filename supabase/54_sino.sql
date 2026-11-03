-- ===========================================================================
-- 54_sino.sql — o sino do painel
--
-- O pedido: "dentro do painel do dono do salão, um ícone de sino para as
-- notificações do sistema". Cada aviso morava num canto: o pedido novo na
-- aba Pedidos, o horário esperando na agenda, a parcela atrasada no
-- Crediário, o fim do teste numa faixa. O sino junta o que PEDE AÇÃO, com
-- o número, e cada item leva à tela onde se resolve.
--
-- ── O QUE ENTRA ───────────────────────────────────────────────────────────
-- Só coisa de verdade, contada aqui, na hora. Nada é gravado para o sino: o
-- item some sozinho quando o motivo some (o horário foi confirmado, a
-- parcela foi paga). Não há "marcar como lido" nesses — lido é resolvido.
--
--   a_confirmar   horários esperando o "sim" do salão (sem os de pacote a
--                 receber, que esperam o pagamento, não uma resposta);
--   sinal         horários esperando o salão conferir o Pix do sinal;
--   pedidos_loja  pedidos da loja novos (53);
--   pedidos       pedidos do restaurante recebidos e ainda não aceitos (37);
--   parcelas      parcelas do crediário vencidas e não pagas (47);
--   mensagens     mensagens do WhatsApp que falharam nos últimos 7 dias;
--   franquia      80% ou mais das mensagens do mês usadas;
--   assinatura    teste no fim, assinatura vencendo (no Pix) ou vencida,
--                 pagamento pendente.
--
-- E os AVISOS DO AGENDAPRO: o que a plataforma escreve no admin (novidade,
-- manutenção, recado) aparece no sino de todos os salões até a pessoa
-- marcar como lido.
--
-- ── QUEM VÊ O QUÊ ─────────────────────────────────────────────────────────
-- A mesma régua das telas, decidida AQUI e não na tela:
--   · quem atende vê só os próprios horários a confirmar;
--   · o balcão (recepção e gestão) vê a agenda toda, o sinal, os pedidos da
--     loja e as parcelas — as telas dessas coisas pedem `ve_agenda_toda`;
--   · mensagens, franquia e assinatura são da gestão (`e_gestor`);
--   · o aviso da plataforma vai para a gestão ou para a equipe toda,
--     conforme quem escreveu escolheu.
-- ===========================================================================

create table if not exists public.avisos_plataforma (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null check (length(btrim(titulo)) between 3 and 120),
  texto         text not null check (length(btrim(texto)) between 3 and 2000),
  -- 'gestao': dono e gerente; 'equipe': todo mundo que entra no painel.
  para          text not null default 'gestao' check (para in ('gestao', 'equipe')),
  publicado_em  timestamptz not null default now(),
  -- Some depois deste dia, no relógio de Brasília (manutenção marcada,
  -- promoção com prazo).
  ate           date,
  arquivado_em  timestamptz,
  criado_por    uuid references public.perfis(id) on delete set null
);
create index if not exists ix_avisos_plataforma_vivos
  on public.avisos_plataforma(publicado_em desc) where arquivado_em is null;

create table if not exists public.avisos_lidos (
  aviso_id   uuid not null references public.avisos_plataforma(id) on delete cascade,
  perfil_id  uuid not null references public.perfis(id) on delete cascade,
  lido_em    timestamptz not null default now(),
  primary key (aviso_id, perfil_id)
);

-- Ninguém lê nem escreve direto: só pelas funções abaixo.
alter table public.avisos_plataforma enable row level security;
alter table public.avisos_lidos enable row level security;
revoke all on public.avisos_plataforma from public, anon, authenticated;
revoke all on public.avisos_lidos from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- O sino: os itens (contados agora) e os avisos não lidos.
-- ---------------------------------------------------------------------------
create or replace function public.sino_do_painel(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_toda boolean; v_gestor boolean; v_prof uuid; v_hoje date; v_fuso text;
  v_itens jsonb := '[]'::jsonb; v_avisos jsonb; n int; v_valor numeric;
  v_uso int; v_teto int; s record; v_cfg jsonb;
begin
  if auth.uid() is null or p_salao is null or not public.e_equipe(p_salao) then
    raise exception 'Só a equipe do salão vê os avisos.' using errcode = 'insufficient_privilege';
  end if;
  v_toda   := public.ve_agenda_toda(p_salao);
  v_gestor := public.e_gestor(p_salao);
  v_prof   := public.meu_profissional_id(p_salao);
  v_hoje   := public.hoje_no_salao(p_salao);
  select coalesce(sa.fuso, 'America/Sao_Paulo'), coalesce(sa.cfg, '{}'::jsonb) into v_fuso, v_cfg
    from public.saloes sa where sa.id = p_salao;

  -- Horários a confirmar. Para o balcão, os do sinal ficam no item deles.
  select count(*) into n
    from public.agendamentos ag
   where ag.salao_id = p_salao and ag.status = 'pendente' and ag.arquivado_em is null
     and (ag.inicio at time zone v_fuso)::date >= v_hoje
     and (v_toda or (v_prof is not null and ag.profissional_id = v_prof))
     and not (v_toda and coalesce(ag.sinal_exigido, 0) > 0
              and coalesce(ag.sinal_pago, 0) < ag.sinal_exigido)
     and not exists (select 1 from public.pacote_clientes pc
                      where pc.id = ag.pacote_cliente_id and coalesce(pc.valor, 0) > 0
                        and pc.pago_em is null and pc.cancelado_em is null);
  if n > 0 then
    v_itens := v_itens || jsonb_build_object('tipo', 'a_confirmar', 'qtd', n);
  end if;

  if v_toda then
    -- O sinal por Pix esperando o salão conferir (o prazo ainda não venceu:
    -- vencido, o agendador libera o horário sozinho).
    select count(*) into n
      from public.agendamentos ag
     where ag.salao_id = p_salao and ag.status = 'pendente' and ag.arquivado_em is null
       and coalesce(ag.sinal_exigido, 0) > 0 and coalesce(ag.sinal_pago, 0) < ag.sinal_exigido
       and (ag.sinal_ate is null or ag.sinal_ate >= now())
       and (ag.inicio at time zone v_fuso)::date >= v_hoje;
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'sinal', 'qtd', n);
    end if;

    -- Pedidos da loja esperando a venda — só com a loja ligada em Meu
    -- negócio (Produtos à venda: Sim), a mesma chave da aba Pedidos.
    select count(*) into n from public.pedidos_loja pl
     where pl.salao_id = p_salao and pl.status = 'novo'
       and lower(btrim(coalesce(v_cfg->>'loja', 'true'))) not in ('false', 'f', '0', 'no', 'nao', 'não');
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'pedidos_loja', 'qtd', n);
    end if;

    -- Parcelas vencidas do crediário, com o que falta receber delas.
    select count(*), coalesce(round(sum(x.saldo), 2), 0) into n, v_valor
      from (select public.saldo_da_parcela(pa.id) as saldo
              from public.crediario_parcelas pa
              join public.crediarios cr on cr.id = pa.crediario_id
             where pa.salao_id = p_salao and cr.desfeito_em is null
               and pa.vence_em < v_hoje) x
     where x.saldo > 0;
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'parcelas', 'qtd', n, 'valor', v_valor);
    end if;
  end if;

  -- Pedidos do restaurante recebidos e ainda não aceitos (a equipe toda vê).
  select count(*) into n from public.pedidos pe
   where pe.salao_id = p_salao and pe.status = 'recebido';
  if n > 0 then
    v_itens := v_itens || jsonb_build_object('tipo', 'pedidos', 'qtd', n);
  end if;

  if v_gestor then
    -- Mensagens que falharam na última semana.
    select count(*) into n from public.notificacoes nt
     where nt.salao_id = p_salao and nt.status = 'falhou'
       and nt.criado_em >= now() - interval '7 days';
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'mensagens', 'qtd', n);
    end if;

    -- A franquia de mensagens do mês (sem teto, ou teto zero: nada a dizer).
    v_teto := public.teto_mensagens(p_salao);
    if coalesce(v_teto, 0) > 0 then
      v_uso := public.mensagens_no_mes(p_salao);
      if v_uso >= ceil(v_teto * 0.8) then
        v_itens := v_itens || jsonb_build_object('tipo', 'franquia', 'qtd', 1,
          'usado', v_uso, 'teto', v_teto, 'pct', least(round(v_uso * 100.0 / v_teto), 100));
      end if;
    end if;

    -- A assinatura. No cartão a renovação é automática: vencer não é aviso.
    select a.status, a.trial_ate, a.vence_em, a.mp_preapproval into s
      from public.assinaturas a where a.salao_id = p_salao;
    if s.status = 'inadimplente' then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'inadimplente');
    elsif s.status = 'trial' and s.trial_ate between v_hoje and v_hoje + 3 then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'teste',
        'dias', s.trial_ate - v_hoje);
    elsif s.status = 'ativa' and s.vence_em is not null and s.mp_preapproval is null
          and s.vence_em between v_hoje and v_hoje + 5 then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'vence',
        'dias', s.vence_em - v_hoje);
    elsif s.status = 'ativa' and s.vence_em is not null
          and s.vence_em < v_hoje and s.vence_em >= v_hoje - 30 then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'venceu',
        'dias', v_hoje - s.vence_em);
    end if;
  end if;

  -- Os avisos do AgendaPro que esta pessoa ainda não leu.
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'titulo', x.titulo, 'texto', x.texto,
           'publicadoEm', x.publicado_em) order by x.publicado_em desc), '[]'::jsonb)
    into v_avisos
    from (select ap.* from public.avisos_plataforma ap
           where ap.arquivado_em is null
             and (ap.ate is null or ap.ate >= (now() at time zone 'America/Sao_Paulo')::date)
             and (ap.para = 'equipe' or v_gestor)
             and not exists (select 1 from public.avisos_lidos al
                              where al.aviso_id = ap.id and al.perfil_id = auth.uid())
           order by ap.publicado_em desc limit 10) x;

  return jsonb_build_object('itens', v_itens, 'avisos', v_avisos);
end $$;

revoke all on function public.sino_do_painel(uuid) from public, anon;
grant execute on function public.sino_do_painel(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- "Marcar como lido": o aviso sai do sino desta pessoa (dos outros, não).
-- ---------------------------------------------------------------------------
create or replace function public.marcar_aviso_lido(p_aviso uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Entre de novo para marcar o aviso.' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.avisos_plataforma ap where ap.id = p_aviso) then
    raise exception 'Este aviso não existe mais.' using errcode = 'check_violation';
  end if;
  insert into public.avisos_lidos (aviso_id, perfil_id) values (p_aviso, auth.uid())
  on conflict (aviso_id, perfil_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.marcar_aviso_lido(uuid) from public, anon;
grant execute on function public.marcar_aviso_lido(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- O admin: publicar, listar e arquivar os avisos. Só a plataforma.
-- ---------------------------------------------------------------------------
create or replace function public.publicar_aviso_plataforma(
  p_titulo text, p_texto text, p_para text default 'gestao', p_ate date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_titulo text := btrim(coalesce(p_titulo, '')); v_texto text := btrim(coalesce(p_texto, ''));
begin
  if not public.is_super() then
    raise exception 'Só a plataforma publica avisos para os salões.' using errcode = 'insufficient_privilege';
  end if;
  if length(v_titulo) < 3 or length(v_titulo) > 120 then
    raise exception 'O título precisa ter de 3 a 120 letras.' using errcode = 'check_violation';
  end if;
  if length(v_texto) < 3 or length(v_texto) > 2000 then
    raise exception 'O texto precisa ter de 3 a 2.000 letras.' using errcode = 'check_violation';
  end if;
  if coalesce(p_para, 'gestao') not in ('gestao', 'equipe') then
    raise exception 'Escolha para quem é o aviso.' using errcode = 'check_violation';
  end if;
  if p_ate is not null and p_ate < (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'A data de saída já passou.' using errcode = 'check_violation';
  end if;
  insert into public.avisos_plataforma (titulo, texto, para, ate, criado_por)
       values (v_titulo, v_texto, coalesce(p_para, 'gestao'), p_ate, auth.uid())
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.arquivar_aviso_plataforma(p_aviso uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma tira avisos do ar.' using errcode = 'insufficient_privilege';
  end if;
  update public.avisos_plataforma set arquivado_em = now()
   where id = p_aviso and arquivado_em is null;
  return jsonb_build_object('ok', found);
end $$;

create or replace function public.avisos_plataforma_admin()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os avisos publicados.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', ap.id, 'titulo', ap.titulo, 'texto', ap.texto,
           'para', ap.para, 'publicadoEm', ap.publicado_em, 'ate', ap.ate,
           'noAr', ap.arquivado_em is null
                    and (ap.ate is null or ap.ate >= (now() at time zone 'America/Sao_Paulo')::date),
           'lidos', (select count(*) from public.avisos_lidos al where al.aviso_id = ap.id))
           order by ap.publicado_em desc)
      from (select * from public.avisos_plataforma order by publicado_em desc limit 30) ap), '[]'::jsonb);
end $$;

revoke all on function public.publicar_aviso_plataforma(text, text, text, date) from public, anon;
revoke all on function public.arquivar_aviso_plataforma(uuid) from public, anon;
revoke all on function public.avisos_plataforma_admin() from public, anon;
grant execute on function public.publicar_aviso_plataforma(text, text, text, date) to authenticated;
grant execute on function public.arquivar_aviso_plataforma(uuid) to authenticated;
grant execute on function public.avisos_plataforma_admin() to authenticated;
