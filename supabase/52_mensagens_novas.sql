-- ===========================================================================
-- 52_mensagens_novas.sql — as mensagens do Crediário e a de horário remarcado
--
-- O pedido: "todos os modelos foram enviados para a Meta, aguardando
-- aprovar — e no sistema tem que ter a opção de desligar pelo dono do salão;
-- no crediário, uma aba se ele quiser desligar cada mensagem".
--
-- ── O CREDIÁRIO (47): QUATRO AVISOS PARA A CLIENTE ──────────────────────
--   · COMPRA: logo depois da venda, o resumo — o valor e as parcelas;
--   · LEMBRETE: dois dias antes de cada vencimento, às 10h do salão;
--   · VENCE HOJE: no dia, às 10h, se a parcela ainda estiver em aberto;
--   · ATRASO: um dia depois, às 10h, se continuar em aberto. Uma vez só.
-- Pagou a parcela (ou a venda foi desfeita), o que estava na fila sai.
-- Pagou uma parte, o texto passa a dizer o que falta. Desfez o recebimento,
-- o aviso volta — se ainda der tempo.
--
-- ⚠ FRANQUIA PRÓPRIA, do plano do Crediário que a loja contratou (200 no
-- de entrada; "200 é para uma loja menor — e a loja maior?": o número mora
-- no catálogo, `adicionais.recursos.mensagens_crediario`, e um plano maior
-- é só mais uma linha lá). Elas não gastam a franquia do plano da agenda, e
-- a da agenda não as segura: o `mensagens_no_mes` deixa de contá-las e o
-- `pode_enviar_tipo` as mede à parte. Passou do limite no mês, as do
-- Crediário esperam o mês seguinte.
--
-- ── O HORÁRIO REMARCADO (49) ─────────────────────────────────────────────
-- O salão remarcou pelo painel (o dia ou a hora): a cliente recebe o
-- horário de antes e o novo. Trocar só a profissional não avisa. Remarcou de
-- novo antes de sair, só a última vai.
--
-- ── ⚠ SÓ SAEM COM OS MODELOS APROVADOS NA META ────────────────────────────
-- Como as do pacote (45): até a plataforma ver os modelos aprovados e ligar
-- no admin, NADA vai para a fila. Um interruptor para o Crediário, um para o
-- remarcado — aprovam em dias diferentes.
--
-- ── E O DONO ESCOLHE ─────────────────────────────────────────────────────
-- Uma chave para cada uma, ligadas por padrão (falam do que a cliente já
-- comprou ou marcou): `notifCredCompra`, `notifCredLembrete`,
-- `notifCredVenceHoje`, `notifCredAtraso` (na aba Mensagens do Crediário) e
-- `notifRemarcado` (em Notificações). Desligou, o que estava na fila sai.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) OS TIPOS, OS MODELOS E A FRANQUIA
-- ---------------------------------------------------------------------------
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in ('confirmacao','lembrete','resumo','novo','lembrete_equipe',
                  'pedido_novo','pedido_confirmado','pedido_a_caminho',
                  'pedido_pronto','pedido_cancelado',
                  'pacote_renovar','pacote_pagamento','pacote_agenda',
                  -- O Crediário e o remarcado (52).
                  'crediario_compra','crediario_lembrete','crediario_vence_hoje',
                  'crediario_atraso','remarcado'));

/* O modelo aprovado na Meta, por tipo — a lista inteira (a do 37 e as
   novas). Texto e ordem das variáveis no MODELOS.md. */
create or replace function public.modelo_de(p_tipo text)
returns text language sql stable set search_path = public as $$
  select case p_tipo
    when 'confirmacao'       then 'agendapro_confirmacao'
    when 'lembrete'          then 'agendapro_lembrete'
    when 'novo'              then 'agendapro_aviso_profissional'
    when 'resumo'            then 'agendapro_agenda_hoje'
    when 'lembrete_equipe'   then 'agendapro_lembrete_equipe'
    when 'pedido_novo'       then 'agendapro_pedido_novo'
    when 'pedido_confirmado' then 'agendapro_pedido_confirmado'
    when 'pedido_a_caminho'  then 'agendapro_pedido_a_caminho'
    when 'pedido_pronto'     then 'agendapro_pedido_pronto'
    when 'pedido_cancelado'  then 'agendapro_pedido_cancelado'
    -- A última sessão (tipo `pacote_renovar`, o nome antigo do aviso): o
    -- `agendapro_pacote_renovacao` a Meta aprovou como Marketing.
    when 'pacote_renovar'    then 'agendapro_pacote_ultima_sessao'
    when 'pacote_pagamento'  then 'agendapro_pacote_pagamento'
    when 'pacote_agenda'     then 'agendapro_pacote_agenda'
    when 'crediario_compra'     then 'agendapro_crediario_compra'
    when 'crediario_lembrete'   then 'agendapro_crediario_lembrete'
    when 'crediario_vence_hoje' then 'agendapro_crediario_vence_hoje'
    when 'crediario_atraso'     then 'agendapro_crediario_atraso'
    when 'remarcado'            then 'agendapro_remarcado'
  end
  || case when p_tipo in ('confirmacao', 'lembrete', 'novo', 'lembrete_equipe')
               and public.mensagens_com_pagamento()
          -- A confirmação se chama _valor1: o _pagamento dela a Meta passou
          -- para Marketing (MODELOS.md).
          then case when p_tipo = 'confirmacao' then '_valor1' else '_pagamento' end
          else '' end
$$;

-- A franquia do PLANO não conta as do Crediário: elas têm a delas.
create or replace function public.mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  with mes as (select c.ini from public.ciclo_mensagens(p_salao) c)
  select ((select count(*)
             from public.notificacoes n, mes
            where n.salao_id = p_salao
              and n.status in ('enviado','entregue','lido')
              and n.enviado_em >= mes.ini
              and n.tipo not like 'crediario%')
        + (select count(*)
             from public.campanha_destinatarios d, mes
            where d.salao_id = p_salao
              and d.status = 'enviado'
              and d.enviado_em >= mes.ini))::int
$$;

-- A franquia do Crediário: a do plano dele que a loja tem ativo (o maior,
-- se por um momento houver dois). Sem nenhum ativo (o teste grátis, que dá o
-- Crediário pelo plano), a do menor do catálogo. Contadas no mesmo ciclo do
-- plano da agenda.
drop function if exists public.crediario_teto_mensagens();
create or replace function public.crediario_teto_mensagens(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(
    max(nullif(ad.recursos->>'mensagens_crediario', '')::int)
      filter (where public.adicional_ativo(p_salao, ad.codigo)),
    min(nullif(ad.recursos->>'mensagens_crediario', '')::int),
    200)
    from public.adicionais ad where ad.recurso = 'crediario'
$$;

create or replace function public.crediario_mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int
    from public.notificacoes n, public.ciclo_mensagens(p_salao) c
   where n.salao_id = p_salao
     and n.status in ('enviado','entregue','lido')
     and n.enviado_em >= c.ini
     and n.tipo like 'crediario%'
$$;

/* A cota por tipo (22 e 37), com as novas: as do Crediário só com o módulo
   ativo e dentro das 200 dele; o remarcado vai para a cliente, então segue
   até o teto do plano, como a confirmação. */
create or replace function public.pode_enviar_tipo(p_salao uuid, p_tipo text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_tipo like 'crediario%'
      then coalesce(public.recurso_bool(p_salao, 'crediario'), false)
           and public.crediario_mensagens_no_mes(p_salao) < public.crediario_teto_mensagens(p_salao)
    when public.teto_mensagens(p_salao) is null then true
    when p_tipo in ('confirmacao', 'lembrete', 'pedido_confirmado',
                    'pedido_a_caminho', 'pedido_pronto', 'pedido_cancelado',
                    'pacote_renovar', 'pacote_pagamento', 'pacote_agenda', 'remarcado')
      then public.mensagens_no_mes(p_salao) < public.teto_mensagens(p_salao)
    else public.mensagens_no_mes(p_salao) < public.teto_mensagens_salao(p_salao)
  end
$$;

-- ---------------------------------------------------------------------------
-- 2) OS INTERRUPTORES DA PLATAFORMA (depois de ver os modelos aprovados)
-- ---------------------------------------------------------------------------
create or replace function public.mensagens_do_crediario()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                    where a.chave = 'mensagensCrediario'), false)
$$;

create or replace function public.mensagem_remarcado()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                    where a.chave = 'mensagemRemarcado'), false)
$$;

-- ---------------------------------------------------------------------------
-- 3) O QUE DEVE ESTAR NA FILA, PARA UMA VENDA NO CREDIÁRIO
--
-- Uma função diz o que deve estar lá; os gatilhos a chamam sempre que algo
-- muda (a venda, um recebimento, a chave do salão, o interruptor). A gravação
-- é a do pacote (`gravar_aviso_do_pacote`, 45): cria, refaz o texto, volta
-- da fila cancelada, e nunca toca no que já saiu.
-- ---------------------------------------------------------------------------
create or replace function public.avisos_do_crediario(p_crediario uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record; pa record; v_tel text; v_nome text; v_pix text; v_pag text; v_comum text;
  v_motivo text; v_lista text; v_qual text; v_saldo numeric; v_venc text;
  v_10h timestamptz;
begin
  select cr.id, cr.salao_id, cr.cliente_id, cr.valor, cr.parcelas, cr.criado_em, cr.desfeito_em,
         cr.pagamento_id, sa.nome as casa, coalesce(sa.fuso, 'America/Sao_Paulo') as fuso, sa.cfg,
         c.nome as cliente, c.telefone
    into r
    from public.crediarios cr
    join public.saloes sa on sa.id = cr.salao_id
    join public.clientes c on c.id = cr.cliente_id
   where cr.id = p_crediario;
  if r.id is null then return; end if;
  -- A venda ainda está nascendo (as parcelas entram antes do pagamento que
  -- fecha a comanda): espera o fim, quando o `pagamento_id` chega.
  if r.pagamento_id is null and r.desfeito_em is null then return; end if;

  v_tel := public.so_digitos(r.telefone);
  v_nome := public.variavel_limpa(split_part(btrim(coalesce(r.cliente, 'cliente')), ' ', 1));
  -- A chave Pix só quando o salão aceita Pix (como o pacote, 45).
  v_pix := case when coalesce(r.cfg->'pagamentos'->'formas', '[]'::jsonb) ? 'pix'
                then 'Pix (chave: ' || nullif(btrim(coalesce(r.cfg->'pagamentos'->>'pix', '')), '') || ')' end;
  v_pag := coalesce(v_pix, 'combine com o salão');

  v_comum := case
    when r.desfeito_em is not null then 'venda desfeita'
    when not public.mensagens_do_crediario() then 'mensagens do crediário desligadas'
    when not coalesce(public.recurso_bool(r.salao_id, 'crediario'), false) then 'módulo Crediário inativo'
    when coalesce(v_tel, '') = '' then 'cliente sem telefone'
  end;

  -- COMPRA: logo depois da venda. Só a venda de agora: ligar o interruptor
  -- não manda resumo de compra antiga (a folga de -1 hora: nasce até uma
  -- hora depois da venda, e não depois disso).
  select string_agg(pa2.numero || 'ª ' || public.reais(pa2.valor) || ' em '
                    || to_char(pa2.vence_em, 'DD/MM'), '; ' order by pa2.numero)
    into v_lista
    from public.crediario_parcelas pa2 where pa2.crediario_id = r.id;
  v_motivo := coalesce(v_comum, case
    when not public.notif_liga(r.salao_id, 'notifCredCompra', true) then 'desligado pelo salão' end);
  perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_compra', 'crediario_compra:' || r.id,
    v_motivo, r.criado_em, interval '-1 hour', r.criado_em + interval '6 hours',
    v_tel, r.cliente_id, null,
    'Olá, ' || v_nome || '. Resumo da sua compra no crediário em ' || r.casa || '.'
      || E'\n\n💰 Valor no crediário: ' || public.reais(r.valor)
      || E'\n🗓️ Parcelas: ' || coalesce(v_lista, '—')
      || E'\n\nGuarde esta mensagem. Mensagem automática do sistema do salão.',
    jsonb_build_array(v_nome, public.variavel_limpa(r.casa),
                      public.variavel_limpa(public.reais(r.valor)), public.variavel_limpa(v_lista)));

  -- AS PARCELAS: lembrete, vence hoje e atraso, cada uma com a sua hora.
  for pa in select p.id, p.numero, p.valor, p.vence_em from public.crediario_parcelas p
             where p.crediario_id = r.id order by p.numero loop
    v_saldo := public.saldo_da_parcela(pa.id);
    v_qual := pa.numero || ' de ' || r.parcelas;
    v_venc := to_char(pa.vence_em, 'DD/MM');

    -- Lembrete: dois dias antes, às 10h.
    v_10h := ((pa.vence_em - 2) + time '10:00') at time zone r.fuso;
    v_motivo := coalesce(v_comum, case
      when v_saldo <= 0 then 'parcela paga'
      when not public.notif_liga(r.salao_id, 'notifCredLembrete', true) then 'desligado pelo salão' end);
    perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_lembrete', 'crediario_lembrete:' || pa.id,
      v_motivo, v_10h, interval '0', (pa.vence_em + time '00:00') at time zone r.fuso,
      v_tel, r.cliente_id, null,
      'Olá, ' || v_nome || '. Lembrete da parcela ' || v_qual || ' do seu crediário em ' || r.casa || '.'
        || E'\n\n💰 Valor: ' || public.reais(v_saldo)
        || E'\n📅 Vencimento: ' || v_venc
        || E'\n💳 Pagamento: ' || v_pag
        || E'\n\nSe você já pagou, desconsidere esta mensagem. Mensagem automática do sistema do salão.',
      jsonb_build_array(v_nome, v_qual, public.variavel_limpa(r.casa),
                        public.variavel_limpa(public.reais(v_saldo)), v_venc, public.variavel_limpa(v_pag)));

    -- Vence hoje: no dia, às 10h.
    v_10h := (pa.vence_em + time '10:00') at time zone r.fuso;
    v_motivo := coalesce(v_comum, case
      when v_saldo <= 0 then 'parcela paga'
      when not public.notif_liga(r.salao_id, 'notifCredVenceHoje', true) then 'desligado pelo salão' end);
    perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_vence_hoje', 'crediario_vence_hoje:' || pa.id,
      v_motivo, v_10h, interval '0', ((pa.vence_em + 1) + time '00:00') at time zone r.fuso,
      v_tel, r.cliente_id, null,
      'Olá, ' || v_nome || '. A parcela ' || v_qual || ' do seu crediário em ' || r.casa || ' vence hoje.'
        || E'\n\n💰 Valor: ' || public.reais(v_saldo)
        || E'\n💳 Pagamento: ' || v_pag
        || E'\n\nSe você já pagou, desconsidere esta mensagem. Mensagem automática do sistema do salão.',
      jsonb_build_array(v_nome, v_qual, public.variavel_limpa(r.casa),
                        public.variavel_limpa(public.reais(v_saldo)), public.variavel_limpa(v_pag)));

    -- Atraso: um dia depois, às 10h. Uma vez só (a chave é da parcela).
    v_10h := ((pa.vence_em + 1) + time '10:00') at time zone r.fuso;
    v_motivo := coalesce(v_comum, case
      when v_saldo <= 0 then 'parcela paga'
      when not public.notif_liga(r.salao_id, 'notifCredAtraso', true) then 'desligado pelo salão' end);
    perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_atraso', 'crediario_atraso:' || pa.id,
      v_motivo, v_10h, interval '0', ((pa.vence_em + 2) + time '00:00') at time zone r.fuso,
      v_tel, r.cliente_id, null,
      'Olá, ' || v_nome || '. A parcela ' || v_qual || ' do seu crediário em ' || r.casa
        || ' venceu em ' || v_venc || ' e ainda aparece em aberto.'
        || E'\n\n💰 Valor: ' || public.reais(v_saldo)
        || E'\n💳 Pagamento: ' || v_pag
        || E'\n\nSe você já pagou, desconsidere esta mensagem. Em caso de dúvida, fale com o salão. Mensagem automática do sistema do salão.',
      jsonb_build_array(v_nome, v_qual, public.variavel_limpa(r.casa), v_venc,
                        public.variavel_limpa(public.reais(v_saldo)), public.variavel_limpa(v_pag)));
  end loop;
end $$;

/* As vendas de um salão (ou de todos) que ainda têm parcela em aberto: ligou
   ou desligou uma chave, ou o interruptor, a fila de todas é refeita. */
create or replace function public.refazer_avisos_do_crediario(p_salao uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare x record; v_n int := 0;
begin
  for x in select cr.id from public.crediarios cr
            where (p_salao is null or cr.salao_id = p_salao)
              and cr.desfeito_em is null
              and exists (select 1 from public.crediario_parcelas pa
                           where pa.crediario_id = cr.id and public.saldo_da_parcela(pa.id) > 0) loop
    perform public.avisos_do_crediario(x.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Os gatilhos: a venda fechou (o pagamento chegou) ou foi desfeita…
create or replace function public.tg_crediario_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.avisos_do_crediario(new.id);
  return new;
end $$;
drop trigger if exists tg_crediario_avisos on public.crediarios;
create trigger tg_crediario_avisos
  after update of pagamento_id, desfeito_em on public.crediarios
  for each row execute function public.tg_crediario_avisos();

-- …entrou um recebimento, ou um foi desfeito…
create or replace function public.tg_crediario_receb_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.avisos_do_crediario(new.crediario_id);
  return new;
end $$;
drop trigger if exists tg_crediario_receb_avisos on public.crediario_recebimentos;
create trigger tg_crediario_receb_avisos
  after insert or update of desfeito_em on public.crediario_recebimentos
  for each row execute function public.tg_crediario_receb_avisos();

-- …ou o dono mexeu numa das quatro chaves.
create or replace function public.tg_salao_avisos_do_crediario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.cfg->'notifCredCompra') is distinct from (new.cfg->'notifCredCompra')
     or (old.cfg->'notifCredLembrete') is distinct from (new.cfg->'notifCredLembrete')
     or (old.cfg->'notifCredVenceHoje') is distinct from (new.cfg->'notifCredVenceHoje')
     or (old.cfg->'notifCredAtraso') is distinct from (new.cfg->'notifCredAtraso')
     or (old.cfg->'pagamentos') is distinct from (new.cfg->'pagamentos') then
    perform public.refazer_avisos_do_crediario(new.id);
  end if;
  return new;
end $$;
drop trigger if exists tg_salao_avisos_do_crediario on public.saloes;
create trigger tg_salao_avisos_do_crediario
  after update of cfg on public.saloes
  for each row execute function public.tg_salao_avisos_do_crediario();

/* A aba Mensagens do Crediário: se já estão saindo, quanto da franquia foi
   usado, e as quatro chaves. Lê quem vê o crediário (o balcão e a gestão). */
create or replace function public.crediario_mensagens(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem o crediário.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object(
    'liberadas', public.mensagens_do_crediario(),
    'usadas', public.crediario_mensagens_no_mes(p_salao),
    'teto', public.crediario_teto_mensagens(p_salao),
    'compra', public.notif_liga(p_salao, 'notifCredCompra', true),
    'lembrete', public.notif_liga(p_salao, 'notifCredLembrete', true),
    'venceHoje', public.notif_liga(p_salao, 'notifCredVenceHoje', true),
    'atraso', public.notif_liga(p_salao, 'notifCredAtraso', true));
end $$;

-- ---------------------------------------------------------------------------
-- 4) O HORÁRIO REMARCADO
--
-- Chamado pelo `remarcar_pelo_salao` (49), com o horário e a profissional
-- de antes. Mudou o dia ou a hora, e o horário novo é no futuro: vai agora.
-- Remarcou de novo antes de sair, a anterior sai da fila — só a última vale.
-- ---------------------------------------------------------------------------
create or replace function public.avisar_remarcado(p_agendamento uuid, p_antes timestamptz,
                                                   p_prof_antes uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare a record; v_tel text; d jsonb; v_antes text;
  v_dias text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
begin
  select ag.id, ag.salao_id, ag.cliente_id, ag.inicio, ag.status, ag.profissional_id,
         coalesce(sa.fuso, 'America/Sao_Paulo') as fuso, c.telefone
    into a
    from public.agendamentos ag
    join public.saloes sa on sa.id = ag.salao_id
    left join public.clientes c on c.id = ag.cliente_id
   where ag.id = p_agendamento;
  if a.id is null or a.inicio <= now() or a.status not in ('pendente', 'confirmado') then
    return false;
  end if;
  -- Só quando muda o DIA ou a HORA: trocar só a profissional (num pacote, a
  -- Bia no lugar da Ju) não é motivo para mensagem — o horário dela é o mesmo.
  if a.inicio = p_antes then return false; end if;
  if not public.mensagem_remarcado() or not public.notif_liga(a.salao_id, 'notifRemarcado', true) then
    return false;
  end if;
  v_tel := public.so_digitos(a.telefone);
  if coalesce(v_tel, '') = '' then return false; end if;

  d := public.pecas_agendamento(a.id);
  v_antes := v_dias[extract(dow from (p_antes at time zone a.fuso))::int + 1] || ', '
             || to_char(p_antes at time zone a.fuso, 'DD/MM "às" HH24:MI');

  update public.notificacoes
     set status = 'cancelado', motivo = 'remarcado de novo'
   where agendamento_id = a.id and tipo = 'remarcado' and status = 'pendente';

  insert into public.notificacoes
    (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave, modelo, variaveis)
  values (a.salao_id, 'remarcado', v_tel, a.cliente_id, a.id, now(),
          'Olá, ' || (d->>'primeiro') || '. Seu horário no ' || (d->>'casa') || ' foi remarcado.'
            || E'\n\n🔁 Antes: ' || v_antes
            || E'\n📅 Nova data: ' || (d->>'data')
            || E'\n🕐 Novo horário: ' || (d->>'hora')
            || E'\n✂️ Serviço: ' || (d->>'servico')
            || E'\n👤 Profissional: ' || (d->>'prof')
            || E'\n\nSe o novo horário não for bom para você, fale com o salão. Aviso automático do sistema de agendamento.',
          'remarcado:' || a.id || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
          public.modelo_de('remarcado'),
          jsonb_build_array(public.variavel_limpa(d->>'primeiro'), public.variavel_limpa(d->>'casa'),
                            public.variavel_limpa(v_antes), public.variavel_limpa(d->>'data'),
                            public.variavel_limpa(d->>'hora'), public.variavel_limpa(d->>'servico'),
                            public.variavel_limpa(d->>'prof')))
  on conflict (salao_id, chave) do nothing;
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 5) A PLATAFORMA LIGA E DESLIGA
-- ---------------------------------------------------------------------------
create or replace function public.definir_mensagens_do_crediario(p_ligar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma liga os modelos de mensagem.' using errcode = 'insufficient_privilege';
  end if;
  insert into public.plataforma_ajustes (chave, valor, atualizado_em)
       values ('mensagensCrediario', to_jsonb(coalesce(p_ligar, false)), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  -- Desligou: o que estava na fila sai. Ligou: as vendas em aberto ganham os
  -- avisos das parcelas que ainda vêm (o resumo de compra antiga, não).
  v_n := public.refazer_avisos_do_crediario(null);
  if not coalesce(p_ligar, false) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'mensagens do crediário desligadas'
     where tipo like 'crediario%' and status = 'pendente';
  end if;
  return jsonb_build_object('ligado', public.mensagens_do_crediario(), 'vendas', v_n);
end $$;

create or replace function public.definir_mensagem_remarcado(p_ligar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma liga os modelos de mensagem.' using errcode = 'insufficient_privilege';
  end if;
  insert into public.plataforma_ajustes (chave, valor, atualizado_em)
       values ('mensagemRemarcado', to_jsonb(coalesce(p_ligar, false)), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  if not coalesce(p_ligar, false) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'mensagem de remarcado desligada'
     where tipo = 'remarcado' and status = 'pendente';
  end if;
  return jsonb_build_object('ligado', public.mensagem_remarcado());
end $$;

-- O que o admin lê (21), com os dois interruptores novos.
create or replace function public.ajustes_da_plataforma()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os ajustes.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object('mensagensComPagamento', public.mensagens_com_pagamento(),
    'mensagensPacote', coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                                  where a.chave = 'mensagensPacote'), false),
    'mensagensCrediario', public.mensagens_do_crediario(),
    'mensagemRemarcado', public.mensagem_remarcado());
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.crediario_teto_mensagens(uuid) from public, anon, authenticated;
revoke all on function public.crediario_mensagens_no_mes(uuid) from public, anon, authenticated;
revoke all on function public.pode_enviar_tipo(uuid, text) from public, anon, authenticated;
revoke all on function public.mensagens_no_mes(uuid) from public, anon;
grant execute on function public.mensagens_no_mes(uuid) to authenticated;
revoke all on function public.mensagens_do_crediario() from public, anon;
grant execute on function public.mensagens_do_crediario() to authenticated;
revoke all on function public.mensagem_remarcado() from public, anon;
grant execute on function public.mensagem_remarcado() to authenticated;
revoke all on function public.avisos_do_crediario(uuid) from public, anon, authenticated;
revoke all on function public.refazer_avisos_do_crediario(uuid) from public, anon, authenticated;
revoke all on function public.tg_crediario_avisos() from public, anon, authenticated;
revoke all on function public.tg_crediario_receb_avisos() from public, anon, authenticated;
revoke all on function public.tg_salao_avisos_do_crediario() from public, anon, authenticated;
revoke all on function public.avisar_remarcado(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.crediario_mensagens(uuid) from public, anon;
grant execute on function public.crediario_mensagens(uuid) to authenticated;
revoke all on function public.definir_mensagens_do_crediario(boolean) from public, anon;
grant execute on function public.definir_mensagens_do_crediario(boolean) to authenticated;
revoke all on function public.definir_mensagem_remarcado(boolean) from public, anon;
grant execute on function public.definir_mensagem_remarcado(boolean) to authenticated;
revoke all on function public.ajustes_da_plataforma() from public, anon;
grant execute on function public.ajustes_da_plataforma() to authenticated;
