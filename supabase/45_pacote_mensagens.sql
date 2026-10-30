-- ===========================================================================
-- 45_pacote_mensagens.sql — as duas mensagens do pacote
--
-- O pedido: depois do pacote com agenda fixa (43), "sim" para as duas
-- mensagens automáticas que faltavam:
--
--   · RENOVAÇÃO: seis dias antes da última sessão, às 10h do salão, a cliente
--     recebe "Aviso sobre o seu pacote: a última sessão é terça, 01/12 às
--     14:00 — para continuar, combine a renovação com o salão". Só quando
--     todas as sessões estão na agenda (antes disso, "a última" não é a
--     última). Renovou antes? O aviso do pacote anterior sai da fila.
--   · PAGAMENTO: na véspera da primeira sessão, às 10h, quem está "a receber"
--     recebe o lembrete com o valor e a chave Pix. Tocou em "Recebi" antes?
--     O lembrete sai da fila.
--
-- ── ⚠ SÓ SAEM COM OS MODELOS APROVADOS NA META ────────────────────────────
-- O número que manda é o do AgendaPro, e ele só manda modelo aprovado. Os
-- dois são novos (MODELOS.md): até a plataforma cadastrar, ver aprovados e
-- ligar no admin, NADA é posto na fila — e não um monte de mensagens para um
-- modelo que não existe (132001), que contariam como falha e sujariam o
-- histórico. O mesmo cuidado da forma de pagamento nas mensagens (21).
--
-- ── E O SALÃO ESCOLHE ─────────────────────────────────────────────────────
-- Em Notificações, uma chave para cada (`notifPacoteRenova`,
-- `notifPacotePaga`), ligadas por padrão: é aviso sobre o que a cliente já
-- comprou. Contam na franquia de mensagens como a confirmação.
--
-- ── A FILA ACOMPANHA O PACOTE ─────────────────────────────────────────────
-- A mensagem nasce semanas antes de sair, e muita coisa muda no caminho: a
-- terça vira quarta, a última sessão é cancelada, o pacote é pago, renovado,
-- cancelado. Em vez de cada lugar lembrar de mexer na fila, UMA função diz o
-- que deve estar lá (`avisos_do_pacote`) e os gatilhos a chamam sempre que
-- uma dessas coisas muda. A mensagem que já saiu nunca é tocada.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O INTERRUPTOR DA PLATAFORMA
-- ---------------------------------------------------------------------------
create or replace function public.mensagens_do_pacote()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                    where a.chave = 'mensagensPacote'), false)
$$;

-- ---------------------------------------------------------------------------
-- 2) GRAVAR UMA NA FILA (OU TIRAR)
--
-- p_motivo preenchido: ela não deve sair, e o que estava pendente é
-- cancelado com esse motivo. Vazio: ela deve sair em p_quando.
--
-- ⚠ EM CIMA DA HORA. Nova mensagem só nasce com folga (p_folga). A que já
-- estava na fila e ficou sem folga — o worker atrasou, a sessão mudou —
-- continua, com o texto refeito, se ainda chega antes da sessão (p_alvo);
-- se a sessão passou para antes dela, sai da fila.
--
-- ⚠ CANCELADA VOLTA. A chave é única: cancelada pela sessão que caiu, a
-- mensagem volta à fila apontando para a sessão nova, em vez de uma segunda
-- linha. Só volta o que nunca saiu (pendente ou cancelado).
-- ---------------------------------------------------------------------------
create or replace function public.gravar_aviso_do_pacote(
  p_salao uuid, p_tipo text, p_chave text, p_motivo text,
  p_quando timestamptz, p_folga interval, p_alvo timestamptz,
  p_destino text, p_cliente uuid, p_agendamento uuid, p_corpo text, p_variaveis jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v public.notificacoes%rowtype;
begin
  select * into v from public.notificacoes n where n.salao_id = p_salao and n.chave = p_chave;
  if p_motivo is not null then
    update public.notificacoes set status = 'cancelado', motivo = p_motivo
     where id = v.id and status = 'pendente';
    return;
  end if;
  if v.id is not null and v.status not in ('pendente', 'cancelado') then return; end if;

  if p_quando > now() + p_folga then
    if v.id is null then
      insert into public.notificacoes
        (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave, modelo, variaveis)
      values (p_salao, p_tipo, p_destino, p_cliente, p_agendamento, p_quando, p_corpo, p_chave,
              public.modelo_de(p_tipo), p_variaveis)
      on conflict (salao_id, chave) do nothing;
    else
      update public.notificacoes
         set status = 'pendente', motivo = null, quando = p_quando, destino = p_destino,
             agendamento_id = p_agendamento, corpo = p_corpo, variaveis = p_variaveis,
             modelo = public.modelo_de(p_tipo), tentativas = 0, proxima_em = null,
             erro_codigo = null, erro_msg = null
       where id = v.id;
    end if;
  elsif v.status = 'pendente' then
    if v.quando < p_alvo then
      update public.notificacoes
         set destino = p_destino, agendamento_id = p_agendamento, corpo = p_corpo,
             variaveis = p_variaveis
       where id = v.id;
    else
      update public.notificacoes
         set status = 'cancelado', motivo = 'a sessão passou para antes do aviso'
       where id = v.id;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3) O QUE DEVE ESTAR NA FILA, PARA UM PACOTE DA CLIENTE
-- ---------------------------------------------------------------------------
create or replace function public.avisos_do_pacote(p_pacote_cliente uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record; v_tel text; v_fuso text; v_prim record; v_ult record; v_quando timestamptz;
  v_nome text; v_quando_txt text; v_pix text; v_motivo text; v_comum text;
  v_dias text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
begin
  select pc.id, pc.cliente_id, pc.pacote_id, pc.valor, pc.pago_em, pc.cancelado_em, pc.criado_em,
         p.nome as pacote, p.salao_id, sa.nome as casa, coalesce(sa.fuso, 'America/Sao_Paulo') as fuso,
         sa.cfg, c.nome as cliente, c.telefone
    into r
    from public.pacote_clientes pc
    join public.pacotes p on p.id = pc.pacote_id
    join public.saloes sa on sa.id = p.salao_id
    join public.clientes c on c.id = pc.cliente_id
   where pc.id = p_pacote_cliente;
  if r.id is null then return; end if;
  v_fuso := r.fuso;
  v_tel := public.so_digitos(r.telefone);

  -- Renovou: o aviso de renovação do pacote anterior (o mesmo pacote, desta
  -- cliente) não sai mais.
  if r.cancelado_em is null then
    update public.notificacoes n
       set status = 'cancelado', motivo = 'pacote renovado'
     where n.salao_id = r.salao_id and n.tipo = 'pacote_renovar' and n.status = 'pendente'
       and n.chave in (select 'pacote_renovar:' || x.id from public.pacote_clientes x
                        where x.cliente_id = r.cliente_id and x.pacote_id = r.pacote_id
                          and x.id <> r.id and x.criado_em < r.criado_em);
  end if;

  -- A primeira e a última sessão vivas (as mesmas que gastam sessão, no 27).
  select a.id, a.inicio, a.status into v_prim from public.agendamentos a
   where a.pacote_cliente_id = r.id and a.arquivado_em is null
     and a.status in ('pendente', 'confirmado', 'em_atendimento', 'concluido')
   order by a.inicio limit 1;
  select a.id, a.inicio, a.status into v_ult from public.agendamentos a
   where a.pacote_cliente_id = r.id and a.arquivado_em is null
     and a.status in ('pendente', 'confirmado', 'em_atendimento', 'concluido')
   order by a.inicio desc limit 1;

  -- O que vale para as duas.
  v_comum := case
    when r.cancelado_em is not null then 'pacote cancelado'
    when not public.mensagens_do_pacote() then 'mensagens do pacote desligadas'
    when coalesce(v_tel, '') = '' then 'cliente sem telefone'
    when v_prim.id is null then 'pacote sem sessão marcada'
  end;
  v_nome := public.variavel_limpa(split_part(btrim(coalesce(r.cliente, 'cliente')), ' ', 1));

  -- RENOVAÇÃO: seis dias antes da última, às 10h do salão.
  if v_comum is null then
    v_quando := ((((v_ult.inicio at time zone v_fuso)::date - 6) + time '10:00') at time zone v_fuso);
    v_quando_txt := v_dias[extract(dow from (v_ult.inicio at time zone v_fuso))::int + 1]
                    || ', ' || to_char(v_ult.inicio at time zone v_fuso, 'DD/MM "às" HH24:MI');
  end if;
  v_motivo := coalesce(v_comum, case
    when not public.notif_liga(r.salao_id, 'notifPacoteRenova', true) then 'desligado pelo salão'
    when exists (select 1 from public.pacote_clientes y
                  where y.cliente_id = r.cliente_id and y.pacote_id = r.pacote_id
                    and y.id <> r.id and y.cancelado_em is null and y.criado_em > r.criado_em)
      then 'pacote renovado'
    when public.pacote_sessoes_restantes(r.id) > 0 then 'ainda há sessão para marcar'
    when v_ult.status not in ('pendente', 'confirmado') then 'a última sessão já foi'
    -- Pacote curto (tudo numa semana): o aviso cairia antes de ele começar.
    when v_quando <= v_prim.inicio then 'pacote curto demais para o aviso'
  end);
  perform public.gravar_aviso_do_pacote(r.salao_id, 'pacote_renovar', 'pacote_renovar:' || r.id,
    v_motivo, v_quando, interval '0', v_ult.inicio, v_tel, r.cliente_id, v_ult.id,
    'Olá, ' || v_nome || '. Aviso sobre o seu pacote ' || r.pacote || ' no ' || r.casa || '.'
      || E'\n\n📅 Última sessão do pacote: ' || v_quando_txt
      || E'\n\nDepois dessa data o pacote termina. Para manter os seus horários, '
      || 'combine a renovação com o salão.'
      || E'\n\nAviso automático do sistema de agendamento.',
    jsonb_build_array(v_nome, public.variavel_limpa(r.pacote),
                      public.variavel_limpa(r.casa), public.variavel_limpa(v_quando_txt)));

  -- PAGAMENTO: véspera da primeira sessão, às 10h, enquanto estiver a receber.
  -- Montado em cima da hora (folga de uma hora), o dono acabou de combinar
  -- com ela: sem lembrete.
  if v_comum is null then
    v_quando := ((((v_prim.inicio at time zone v_fuso)::date - 1) + time '10:00') at time zone v_fuso);
  end if;
  -- A chave Pix só quando o salão aceita Pix (como o sinal, no 09).
  v_pix := case when coalesce(r.cfg->'pagamentos'->'formas', '[]'::jsonb) ? 'pix'
                then 'Pix (chave: ' || nullif(btrim(coalesce(r.cfg->'pagamentos'->>'pix', '')), '') || ')' end;
  v_motivo := coalesce(v_comum, case
    when not public.notif_liga(r.salao_id, 'notifPacotePaga', true) then 'desligado pelo salão'
    when coalesce(r.valor, 0) <= 0 then 'pacote sem valor a receber'
    when r.pago_em is not null then 'pacote pago'
  end);
  perform public.gravar_aviso_do_pacote(r.salao_id, 'pacote_pagamento', 'pacote_pagamento:' || r.id,
    v_motivo, v_quando, interval '1 hour', v_prim.inicio, v_tel, r.cliente_id, v_prim.id,
    'Olá, ' || v_nome || '. Lembrete do pagamento do seu pacote ' || r.pacote
      || ' no ' || r.casa || '.'
      || E'\n\n💰 Valor: ' || public.reais(r.valor)
      || E'\n💳 Pagamento: ' || coalesce(v_pix, 'combine com o salão')
      || E'\n\nSe você já pagou, desconsidere esta mensagem.'
      || E'\n\nAviso automático do sistema de agendamento.',
    jsonb_build_array(v_nome, public.variavel_limpa(r.pacote), public.variavel_limpa(r.casa),
                      public.variavel_limpa(public.reais(r.valor)),
                      public.variavel_limpa(coalesce(v_pix, 'combine com o salão'))));
end $$;

/* Os pacotes de um salão (ou de todos) que ainda têm sessão pela frente:
   ligou ou desligou a chave, a fila de todos eles é refeita. */
create or replace function public.refazer_avisos_de_pacote(p_salao uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare x record; v_n int := 0;
begin
  for x in
    select pc.id from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
     where (p_salao is null or p.salao_id = p_salao) and pc.cancelado_em is null
       and exists (select 1 from public.agendamentos a
                    where a.pacote_cliente_id = pc.id and a.inicio > now()
                      and a.status in ('pendente', 'confirmado'))
  loop
    perform public.avisos_do_pacote(x.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- 4) QUEM CHAMA: OS GATILHOS
-- ---------------------------------------------------------------------------
/* A sessão nasceu, mudou de hora, foi cancelada, atendida, arquivada ou
   trocou de pacote. ⚠ O nome vem depois de `tg_notif_agenda_mudou` na ordem
   alfabética, e é de propósito: o Postgres roda os gatilhos do mesmo evento
   nessa ordem, e aquele cancela o que aponta para a sessão cancelada — este,
   depois, devolve a mensagem à fila apontando para a sessão que sobrou. */
create or replace function public.tg_pacote_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.pacote_cliente_id is not null then
    perform public.avisos_do_pacote(new.pacote_cliente_id);
  end if;
  if tg_op = 'UPDATE' and old.pacote_cliente_id is not null
     and old.pacote_cliente_id is distinct from new.pacote_cliente_id then
    perform public.avisos_do_pacote(old.pacote_cliente_id);
  end if;
  return new;
end $$;

drop trigger if exists tg_pacote_avisos on public.agendamentos;
create trigger tg_pacote_avisos
  after insert or update of inicio, status, arquivado_em, pacote_cliente_id on public.agendamentos
  for each row execute function public.tg_pacote_avisos();

-- Pagou, desfez o pagamento, mudou o valor, cancelou o pacote.
create or replace function public.tg_pacote_cliente_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.avisos_do_pacote(new.id);
  return new;
end $$;

drop trigger if exists tg_pacote_cliente_avisos on public.pacote_clientes;
create trigger tg_pacote_cliente_avisos
  after update of pago_em, valor, cancelado_em on public.pacote_clientes
  for each row execute function public.tg_pacote_cliente_avisos();

-- O salão ligou ou desligou uma das duas chaves em Notificações.
create or replace function public.tg_salao_avisos_de_pacote()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.cfg->'notifPacoteRenova') is distinct from (new.cfg->'notifPacoteRenova')
     or (old.cfg->'notifPacotePaga') is distinct from (new.cfg->'notifPacotePaga') then
    perform public.refazer_avisos_de_pacote(new.id);
  end if;
  return new;
end $$;

drop trigger if exists tg_salao_avisos_de_pacote on public.saloes;
create trigger tg_salao_avisos_de_pacote
  after update of cfg on public.saloes
  for each row execute function public.tg_salao_avisos_de_pacote();

-- ---------------------------------------------------------------------------
-- 5) A PLATAFORMA LIGA (DEPOIS DE VER OS MODELOS APROVADOS)
-- ---------------------------------------------------------------------------
create or replace function public.definir_mensagens_do_pacote(p_ligar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma liga os modelos de mensagem.'
      using errcode = 'insufficient_privilege';
  end if;
  insert into public.plataforma_ajustes (chave, valor, atualizado_em)
       values ('mensagensPacote', to_jsonb(coalesce(p_ligar, false)), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  -- Desligou: o que estava na fila sai, de todos os salões.
  if not coalesce(p_ligar, false) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'mensagens do pacote desligadas'
     where tipo in ('pacote_renovar', 'pacote_pagamento') and status = 'pendente';
  end if;
  -- Ligou: os pacotes que já estão na agenda ganham as mensagens deles.
  v_n := public.refazer_avisos_de_pacote(null);
  return jsonb_build_object('ligado', public.mensagens_do_pacote(), 'pacotes', v_n);
end $$;

-- Um sim ou não da plataforma, como o `mensagens_com_pagamento` (21): o
-- painel lê para dizer ao dono que as duas ainda não estão saindo.
revoke all on function public.mensagens_do_pacote() from public, anon;
grant execute on function public.mensagens_do_pacote() to authenticated;
revoke all on function public.gravar_aviso_do_pacote(uuid, text, text, text, timestamptz, interval,
  timestamptz, text, uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.avisos_do_pacote(uuid) from public, anon, authenticated;
revoke all on function public.refazer_avisos_de_pacote(uuid) from public, anon, authenticated;
revoke all on function public.tg_pacote_avisos() from public, anon, authenticated;
revoke all on function public.tg_pacote_cliente_avisos() from public, anon, authenticated;
revoke all on function public.tg_salao_avisos_de_pacote() from public, anon, authenticated;
revoke all on function public.definir_mensagens_do_pacote(boolean) from public, anon;
grant execute on function public.definir_mensagens_do_pacote(boolean) to authenticated;
