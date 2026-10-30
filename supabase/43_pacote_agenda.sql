-- ===========================================================================
-- 43_pacote_agenda.sql — o pacote com agenda fixa, e o pagamento do pacote
--
-- O pedido: "incluir uma cliente no pacote e já agendar 4 semanas para ela —
-- ela paga mensal e vai toda terça às 14h. Na primeira terça faz mão, na
-- segunda mão e pé, na terceira só mão, na quarta mão e pé." E, logo depois:
-- "como faço a parte de pagamento para a cliente?"
--
-- ── 1) MONTAR O PACOTE: O VÍNCULO E AS SEMANAS, TUDO OU NADA ───────────────
-- `montar_pacote()` vincula a cliente e já marca cada semana, com os serviços
-- daquela semana. Antes de marcar, confere TODAS: data que passou, dia em que
-- o pacote não vale, serviço de fora do pacote, horário ocupado, bloqueio,
-- fora da jornada. Se uma semana não cabe, nada é gravado e a resposta diz
-- qual semana e por quê — a tela deixa trocar só aquela e tentar de novo.
-- Pacote pela metade (duas terças marcadas, duas não) é pior que nenhum.
--
-- ── 2) UMA MENSAGEM SÓ, COM TODAS AS DATAS ─────────────────────────────────
-- Cada horário marcado gera a sua confirmação — quatro mensagens da franquia
-- para dizer uma coisa. Aqui a primeira leva as quatro datas ("04/11, 11/11,
-- 18/11 e 25/11 às 14:00") e as outras saem da fila. É o MESMO modelo de
-- confirmação já aprovado na Meta: a lista vai no lugar da data, e nenhum
-- modelo novo precisa de aprovação. O lembrete da véspera continua saindo
-- para cada uma.
--
-- ── 3) O PAGAMENTO VIRA COMANDA, COMO TODO DINHEIRO DO SISTEMA ─────────────
-- Até aqui o preço do pacote era só referência: cada sessão sai a R$ 0,00, e
-- o dinheiro do pacote não aparecia em faturamento nenhum. O 28 já tinha
-- decidido que dinheiro tem UM caminho — comanda fechada — e o relatório, o
-- painel do dia e o dashboard leem só esse. Então `receber_pacote()` monta
-- uma comanda automática com o item "Pacote …" e o pagamento, e fecha. Sem
-- profissional no item: a venda do pacote não gera comissão, como a sessão
-- de pacote já não gerava (28).
--
-- O pacote "a receber" é o vínculo com valor combinado e sem `pago_em`. A
-- mensagem para a cliente deixa de dizer "já pago" enquanto ele estiver
-- assim (21_notificacoes.sql).
--
-- ── QUEM ──────────────────────────────────────────────────────────────────
-- O balcão e a gestão (`ve_agenda_toda`): quem marca horário e recebe
-- dinheiro no salão. Criar e editar o pacote (preço, sessões) continua sendo
-- da gestão; tirar a cliente do pacote também (27).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O PAGAMENTO NO VÍNCULO
-- ---------------------------------------------------------------------------
alter table public.pacote_clientes add column if not exists valor numeric(10,2);
alter table public.pacote_clientes add column if not exists pago_em timestamptz;
alter table public.pacote_clientes add column if not exists forma_pagamento text;
alter table public.pacote_clientes add column if not exists comanda_id uuid
  references public.comandas(id) on delete set null;
do $$ begin
  alter table public.pacote_clientes add constraint pacote_clientes_valor_check
    check (valor is null or valor >= 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.pacote_clientes add constraint pacote_clientes_forma_check
    check (forma_pagamento is null
           or forma_pagamento in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia'));
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2) RECEBER O PAGAMENTO DO PACOTE
-- ---------------------------------------------------------------------------
create or replace function public.receber_pacote(
  p_pacote_cliente uuid, p_forma text, p_valor numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_valor numeric(10,2); v_comanda uuid;
begin
  select pc.*, p.salao_id, p.nome as pacote_nome into r
    from public.pacote_clientes pc
    join public.pacotes p on p.id = pc.pacote_id
   where pc.id = p_pacote_cliente;
  if r.id is null then
    raise exception 'Não achei este pacote da cliente.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(r.salao_id) then
    raise exception 'Só o balcão e a gestão registram pagamento.'
      using errcode = 'insufficient_privilege';
  end if;
  if r.cancelado_em is not null then
    raise exception 'Este pacote foi cancelado.' using errcode = 'check_violation';
  end if;
  if r.pago_em is not null then
    raise exception 'Este pacote já está pago.' using errcode = 'check_violation';
  end if;
  if coalesce(p_forma, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
    raise exception 'Escolha como ela pagou: Pix, dinheiro, cartão ou transferência.'
      using errcode = 'check_violation';
  end if;
  v_valor := round(coalesce(p_valor, r.valor, 0), 2);
  if v_valor <= 0 then
    raise exception 'Diga quanto ela pagou.' using errcode = 'check_violation';
  end if;

  insert into public.comandas (salao_id, cliente_id, automatica)
       values (r.salao_id, r.cliente_id, true)
    returning id into v_comanda;
  insert into public.comanda_itens (comanda_id, tipo, descricao, qtd, preco_unit)
       values (v_comanda, 'servico', 'Pacote ' || r.pacote_nome, 1, v_valor);
  insert into public.pagamentos (comanda_id, forma, valor)
       values (v_comanda, p_forma, v_valor);
  update public.comandas set status = 'fechada', fechada_em = now() where id = v_comanda;

  update public.pacote_clientes
     set valor = v_valor, pago_em = now(), forma_pagamento = p_forma, comanda_id = v_comanda
   where id = p_pacote_cliente;
  return jsonb_build_object('ok', true, 'comanda', v_comanda, 'valor', v_valor);
end $$;

/* Lançou como pago por engano: a comanda automática sai (o faturamento volta
   ao que era) e o pacote volta a "a receber". Só a gestão desfaz dinheiro. */
create or replace function public.desfazer_recebimento_pacote(p_pacote_cliente uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select pc.*, p.salao_id into r
    from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
   where pc.id = p_pacote_cliente;
  if r.id is null then
    raise exception 'Não achei este pacote da cliente.' using errcode = 'check_violation';
  end if;
  if not public.e_gestor(r.salao_id) then
    raise exception 'Só o proprietário ou um administrador desfaz um recebimento.'
      using errcode = 'insufficient_privilege';
  end if;
  if r.pago_em is null then
    raise exception 'Este pacote ainda não foi pago.' using errcode = 'check_violation';
  end if;
  update public.pacote_clientes
     set pago_em = null, forma_pagamento = null, comanda_id = null
   where id = p_pacote_cliente;
  delete from public.comandas where id = r.comanda_id and automatica;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 3) AS DATAS ESCRITAS COMO GENTE ESCREVE, E A MENSAGEM ÚNICA
-- ---------------------------------------------------------------------------
/* "04/11, 11/11, 18/11 e 25/11", com a hora mais comum à parte. A semana em
   outro horário leva o dela entre parênteses: "18/11 (15:00)". */
create or replace function public.datas_do_pacote(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_fuso text; v_hora text; v_lista text[];
begin
  select coalesce(sa.fuso, 'America/Sao_Paulo') into v_fuso
    from public.agendamentos a join public.saloes sa on sa.id = a.salao_id
   where a.id = p_ids[1];
  select mode() within group (order by to_char(a.inicio at time zone v_fuso, 'HH24:MI'))
    into v_hora
    from public.agendamentos a where a.id = any(p_ids);
  select array_agg(to_char(a.inicio at time zone v_fuso, 'DD/MM')
                   || case when to_char(a.inicio at time zone v_fuso, 'HH24:MI') <> v_hora
                           then ' (' || to_char(a.inicio at time zone v_fuso, 'HH24:MI') || ')'
                           else '' end
                   order by a.inicio)
    into v_lista
    from public.agendamentos a where a.id = any(p_ids);
  return jsonb_build_object('hora', v_hora, 'datas',
    case when cardinality(v_lista) <= 1 then coalesce(v_lista[1], '')
         else array_to_string(v_lista[1:cardinality(v_lista) - 1], ', ')
              || ' e ' || v_lista[cardinality(v_lista)] end);
end $$;

create or replace function public.juntar_mensagens_do_pacote(p_ids uuid[], p_pacote text)
returns void language plpgsql security definer set search_path = public as $$
declare d jsonb; v_datas text; v_hora text; v_serv text; v_data1 text; v_serv1 text; v_fuso text;
begin
  if cardinality(p_ids) < 2 then return; end if;
  d := public.datas_do_pacote(p_ids);
  v_datas := public.variavel_limpa(d->>'datas');
  v_hora  := public.variavel_limpa(d->>'hora');
  v_serv  := public.variavel_limpa('pacote ' || p_pacote);
  select to_char(a.inicio at time zone coalesce(sa.fuso, 'America/Sao_Paulo'), 'DD/MM/YYYY'),
         coalesce((select string_agg(sv.nome, ' + ' order by asv.ordem)
                     from public.agendamento_servicos asv
                     join public.servicos sv on sv.id = asv.servico_id
                    where asv.agendamento_id = a.id), 'atendimento')
    into v_data1, v_serv1
    from public.agendamentos a join public.saloes sa on sa.id = a.salao_id
   where a.id = p_ids[1];

  -- As outras semanas: a confirmação e o aviso de "novo" saem da fila. O
  -- lembrete da véspera fica. Cancelado, e não apagado: a chave continua
  -- ocupada, e um gatilho que rode de novo não recria a mensagem.
  update public.notificacoes
     set status = 'cancelado', motivo = 'pacote: uma mensagem só, com todas as datas'
   where agendamento_id = any(p_ids[2:])
     and tipo in ('confirmacao', 'novo') and status = 'pendente';

  -- A primeira leva todas. Confirmação: {{2}} data, {{3}} hora, {{4}} serviço.
  update public.notificacoes
     set variaveis = jsonb_set(jsonb_set(jsonb_set(variaveis,
                       '{1}', to_jsonb(v_datas)), '{2}', to_jsonb(v_hora)), '{3}', to_jsonb(v_serv)),
         corpo = replace(replace(corpo, v_data1, d->>'datas'), v_serv1, 'pacote ' || p_pacote)
   where agendamento_id = p_ids[1] and tipo = 'confirmacao' and status = 'pendente'
     and jsonb_typeof(variaveis) = 'array' and jsonb_array_length(variaveis) >= 4;
  -- Aviso de "novo" para quem atende: {{3}} serviço, {{4}} data, {{5}} hora.
  update public.notificacoes
     set variaveis = jsonb_set(jsonb_set(jsonb_set(variaveis,
                       '{2}', to_jsonb(v_serv)), '{3}', to_jsonb(v_datas)), '{4}', to_jsonb(v_hora)),
         corpo = replace(replace(corpo, v_data1, d->>'datas'), v_serv1, 'pacote ' || p_pacote)
   where agendamento_id = p_ids[1] and tipo = 'novo' and status = 'pendente'
     and jsonb_typeof(variaveis) = 'array' and jsonb_array_length(variaveis) >= 5;
end $$;

-- ---------------------------------------------------------------------------
-- 4) MONTAR O PACOTE
--
-- p_semanas: [{ "inicio": "2026-11-04T14:00:00-03:00", "servicos": [uuid…] }, …]
-- Vazio: só vincula (o jeito de antes), com o pagamento.
-- p_forma nula: o pacote fica "a receber" pelo p_valor. Com forma: já pago.
-- ---------------------------------------------------------------------------
create or replace function public.montar_pacote(
  p_pacote uuid, p_cliente uuid, p_valor numeric default null, p_forma text default null,
  p_profissional uuid default null, p_semanas jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pac public.pacotes%rowtype;
  v_fuso text; v_n int; i int; w jsonb;
  v_ini timestamptz; v_fim timestamptz; v_servs uuid[]; v_motivo text;
  v_inis timestamptz[] := '{}'; v_fins timestamptz[] := '{}';
  v_semanas jsonb := '[]'::jsonb; v_problema boolean := false;
  v_primeiro date; v_vence date; v_dia date;
  v_pc uuid; v_ag uuid; v_ids uuid[] := '{}'; v_ordem int; s record;
begin
  select * into v_pac from public.pacotes p where p.id = p_pacote and p.ativo;
  if v_pac.id is null then
    raise exception 'Pacote não encontrado ou desativado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(v_pac.salao_id) then
    raise exception 'Só o balcão e a gestão vinculam cliente ao pacote.'
      using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(v_pac.salao_id, 'pacotes', 'Vender pacote');
  if not exists (select 1 from public.clientes c
                  where c.id = p_cliente and c.salao_id = v_pac.salao_id) then
    raise exception 'Esta cliente não é deste salão.' using errcode = 'check_violation';
  end if;
  if p_valor is not null and p_valor < 0 then
    raise exception 'O valor do pacote não pode ser negativo.' using errcode = 'check_violation';
  end if;
  if p_forma is not null and coalesce(p_valor, 0) <= 0 then
    raise exception 'Diga quanto ela pagou.' using errcode = 'check_violation';
  end if;

  p_semanas := coalesce(p_semanas, '[]'::jsonb);
  -- A lista vazia às vezes chega como `{}` (array vazio convertido no
  -- caminho): é "nenhuma semana", e não formato errado.
  if p_semanas = '{}'::jsonb then p_semanas := '[]'::jsonb; end if;
  if jsonb_typeof(p_semanas) <> 'array' then
    raise exception 'As semanas vieram num formato que não entendo.' using errcode = 'check_violation';
  end if;
  v_n := jsonb_array_length(p_semanas);
  if v_n > v_pac.sessoes then
    raise exception 'O pacote tem % sessões, e você marcou % semanas.', v_pac.sessoes, v_n
      using errcode = 'check_violation';
  end if;
  select coalesce(sa.fuso, 'America/Sao_Paulo') into v_fuso
    from public.saloes sa where sa.id = v_pac.salao_id;

  if v_n > 0 then
    if not exists (select 1 from public.profissionais pr
                    where pr.id = p_profissional and pr.salao_id = v_pac.salao_id and pr.ativo) then
      raise exception 'Escolha quem vai atender.' using errcode = 'check_violation';
    end if;
    -- A validade conta da PRIMEIRA sessão: o pacote que começa daqui a dez
    -- dias não pode perder a última terça por ter sido montado hoje.
    begin
      select min(((x->>'inicio')::timestamptz at time zone v_fuso)::date) into v_primeiro
        from jsonb_array_elements(p_semanas) x;
    exception when others then
      raise exception 'Uma das datas veio num formato que não entendo.' using errcode = 'check_violation';
    end;
    v_vence := v_primeiro + v_pac.validade_dias;

    for i in 0 .. v_n - 1 loop
      w := p_semanas->i;
      v_ini := (w->>'inicio')::timestamptz;
      v_servs := coalesce(array(select x::uuid from jsonb_array_elements_text(
                   case when jsonb_typeof(w->'servicos') = 'array' then w->'servicos' else '[]'::jsonb end) x),
                 '{}');
      v_dia := (v_ini at time zone v_fuso)::date;
      v_fim := null;
      v_motivo := case
        when cardinality(v_servs) = 0 then 'Escolha o que ela faz nesta semana.'
        when exists (select 1 from unnest(v_servs) sv(id)
                      where not exists (select 1 from public.pacote_servicos ps
                                         where ps.pacote_id = p_pacote and ps.servico_id = sv.id))
          then 'Um dos serviços desta semana não está no pacote.'
        when v_ini <= now() then 'Esta data já passou.'
        when not (extract(dow from v_dia)::smallint = any(v_pac.dias))
          then 'O pacote vale só ' || public.dias_por_extenso(v_pac.dias) || '.'
        when v_dia > v_vence
          then 'Passa da validade do pacote (vence em ' || to_char(v_vence, 'DD/MM') || ').'
      end;
      if v_motivo is null then
        v_fim := v_ini + make_interval(mins => public.duracao_dos_servicos(p_profissional, v_servs));
        v_motivo := public.porque_nao_cabe(p_profissional, v_ini, v_fim, null);
      end if;
      if v_motivo is null and exists (
           select 1 from unnest(v_inis, v_fins) as o(ini, fim)
            where o.ini < v_fim and v_ini < o.fim) then
        v_motivo := 'Bate com outra semana deste mesmo pacote.';
      end if;
      v_inis := v_inis || v_ini;
      v_fins := v_fins || coalesce(v_fim, v_ini);
      v_problema := v_problema or v_motivo is not null;
      v_semanas := v_semanas || jsonb_build_object('semana', i + 1, 'ok', v_motivo is null,
                                                   'motivo', v_motivo);
    end loop;

    if v_problema then
      return jsonb_build_object('ok', false, 'semanas', v_semanas);
    end if;
  else
    v_vence := public.hoje_no_salao(v_pac.salao_id) + v_pac.validade_dias;
  end if;

  insert into public.pacote_clientes (pacote_id, cliente_id, sessoes, vence_em, valor)
       values (p_pacote, p_cliente, v_pac.sessoes, v_vence, nullif(round(coalesce(p_valor, 0), 2), 0))
    returning id into v_pc;

  -- Pago na hora: recebe ANTES de marcar as sessões. A mensagem de cada
  -- sessão nasce no insert dela e já sai sabendo que está pago (e não "a
  -- combinar"), e o lembrete de pagamento (45) nem chega a nascer.
  if p_forma is not null then
    perform public.receber_pacote(v_pc, p_forma, p_valor);
  end if;

  for i in 0 .. v_n - 1 loop
    w := p_semanas->i;
    v_servs := array(select x::uuid from jsonb_array_elements_text(w->'servicos') x);
    begin
      insert into public.agendamentos
        (salao_id, cliente_id, profissional_id, inicio, fim, status, origem,
         valor_previsto, criado_por, pacote_cliente_id)
      values (v_pac.salao_id, p_cliente, p_profissional, v_inis[i + 1], v_fins[i + 1],
              'confirmado', 'recepcao', 0, auth.uid(), v_pc)
      returning id into v_ag;
    exception when exclusion_violation then
      raise exception 'Alguém acabou de marcar no horário da semana %. Confira e tente de novo.', i + 1
        using errcode = 'check_violation';
    end;
    v_ordem := 1;
    -- Como o `agendar()` (09): a duração com o intervalo, o preço pela
    -- escada (o gatilho preenche) e a comissão do cadastro.
    for s in
      select sv.id, coalesce(sp.duracao_min, sv.duracao_min) + sv.intervalo_min as dur,
             coalesce(sv.comissao_pct, pr.comissao_pct, 0) as com
        from unnest(v_servs) with ordinality as pedido(id, pos)
        join public.servicos sv on sv.id = pedido.id
        join public.profissionais pr on pr.id = p_profissional
        left join public.servicos_profissionais sp
               on sp.servico_id = sv.id and sp.profissional_id = p_profissional
       order by pedido.pos
    loop
      insert into public.agendamento_servicos
        (agendamento_id, servico_id, ordem, duracao_min, preco, comissao_pct)
      values (v_ag, s.id, v_ordem, s.dur, null, s.com);
      v_ordem := v_ordem + 1;
    end loop;
    v_ids := v_ids || v_ag;
  end loop;

  perform public.juntar_mensagens_do_pacote(v_ids, v_pac.nome);

  return jsonb_build_object('ok', true, 'pacoteCliente', v_pc, 'agendamentos', to_jsonb(v_ids),
                            'venceEm', v_vence,
                            'datas', case when v_n > 0 then public.datas_do_pacote(v_ids) end);
end $$;

-- ---------------------------------------------------------------------------
-- 5) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.receber_pacote(uuid, text, numeric) from public, anon;
revoke all on function public.desfazer_recebimento_pacote(uuid) from public, anon;
revoke all on function public.montar_pacote(uuid, uuid, numeric, text, uuid, jsonb) from public, anon;
grant execute on function public.receber_pacote(uuid, text, numeric) to authenticated;
grant execute on function public.desfazer_recebimento_pacote(uuid) to authenticated;
grant execute on function public.montar_pacote(uuid, uuid, numeric, text, uuid, jsonb) to authenticated;
-- As peças de dentro não são de ninguém.
revoke all on function public.datas_do_pacote(uuid[]) from public, anon, authenticated;
revoke all on function public.juntar_mensagens_do_pacote(uuid[], text) from public, anon, authenticated;
