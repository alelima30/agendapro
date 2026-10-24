-- ===========================================================================
-- AgendaPro — 40: o check-up do sistema (monitoramento)
--
-- "Preciso criar algo que fique monitorando o AgendaPro." O site no ar não
-- quer dizer que o sistema está funcionando: o defeito mais provável aqui é a
-- fila do WhatsApp parar calada — o despertador desligado, o token da Meta
-- vencido, a função de envio recusando — e ninguém notar até a cliente dizer
-- que não recebeu nada.
--
-- Este arquivo confere, a cada chamada:
--
--   · o banco responde (se esta função roda, responde);
--   · o despertador da fila (pg_cron) existe, está ligado e rodou agora há
--     pouco, sem falhar;
--   · a função de envio responde bem ao despertador (pg_net guarda a
--     resposta de cada chamada: 401 é o segredo trocado, 404 é a função não
--     publicada, 503 é o WhatsApp sem token);
--   · nenhuma mensagem está atrasada na fila;
--   · as mensagens não estão falhando — e, falhando, por quê, com o erro da
--     Meta traduzido e o que fazer.
--
-- E, só para o admin, o que é do NEGÓCIO e não do sistema: salão com a
-- franquia acabando e assinatura vencendo.
--
-- ── TRÊS PORTAS ────────────────────────────────────────────────────────────
--   saude_verificar()   faz a conta. Não é de ninguém de fora.
--   saude_plataforma()  o admin.html: tudo, com o nome dos salões. Só is_super().
--   saude_publica()     a função de borda `saude`, que o UptimeRobot visita:
--                       só "ok" ou "problema" e as chaves do que está errado.
--                       Nenhum nome de salão, telefone ou texto de mensagem.
--
-- O alerta sai pelo UptimeRobot, e não pelo WhatsApp do próprio sistema, de
-- propósito: se o que quebrou foi o WhatsApp, o aviso também não chegaria.
-- ===========================================================================

-- Uma linha do check-up. Função à parte só para o corpo de baixo não repetir
-- jsonb_build_object com cinco pares em cada um dos vinte lugares.
create or replace function public.saude_item(
  p_chave text, p_nivel text, p_titulo text, p_detalhe text, p_acao text default null)
returns jsonb language sql immutable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'chave', p_chave, 'nivel', p_nivel, 'titulo', p_titulo,
    'detalhe', p_detalhe, 'acao', p_acao))
$$;

/* O erro da Meta, em português, e o que fazer. Os códigos são os da Cloud API
   (o worker grava `erro.code`). Os de cima param TUDO — token, conta, número,
   modelo — e por isso viram "problema"; os de baixo são de UMA cliente. */
create or replace function public.saude_erro_meta(p_codigo text)
returns text language sql immutable set search_path = public as $$
  select case p_codigo
    when '190'    then 'o token do WhatsApp venceu ou foi trocado. Gere um token permanente na Meta e atualize o segredo WHATSAPP_TOKEN no Supabase (Edge Functions, Secrets).'
    when '10'     then 'o token não tem permissão para enviar. Gere o token com a permissão whatsapp_business_messaging.'
    when '200'    then 'o token não tem permissão para enviar. Gere o token com a permissão whatsapp_business_messaging.'
    when '131005' then 'acesso negado pela Meta. Confira a permissão do token e o WHATSAPP_PHONE_ID.'
    when '131031' then 'a conta do WhatsApp Business foi bloqueada pela Meta. Veja o aviso no WhatsApp Manager.'
    when '368'    then 'a Meta bloqueou o número por um tempo, por política. Veja o WhatsApp Manager.'
    when '131042' then 'falta forma de pagamento na conta da Meta. Cadastre um cartão no WhatsApp Manager, em Pagamentos.'
    when '133010' then 'o número do WhatsApp não está registrado na API. Refaça o registro do número na Meta.'
    when '132001' then 'o modelo de mensagem não existe na Meta com esse nome e idioma. Confira os nomes no MODELOS.md.'
    when '132000' then 'o número de variáveis não bate com o modelo aprovado na Meta.'
    when '132015' then 'a Meta pausou o modelo de mensagem (qualidade baixa). Veja o WhatsApp Manager.'
    when '132016' then 'a Meta desativou o modelo de mensagem. Veja o WhatsApp Manager.'
    when '131026' then 'o número da cliente não tem WhatsApp ou não pôde receber.'
    when '131047' then 'passou da janela de 24 horas, e só modelo aprovado pode sair.'
    when '131049' then 'a Meta escolheu não entregar (limite de mensagens de marketing para a pessoa).'
    when '131056' then 'muitas mensagens seguidas para o mesmo número.'
    when '130429' then 'o limite de envio por segundo da Meta foi atingido.'
    when 'rede'   then 'erro de rede entre a função de envio e a Meta.'
    when 'sem_resposta' then 'o envio começou e a Meta não respondeu.'
    else 'erro ' || coalesce(p_codigo, 'sem código') || ' da Meta.'
  end
$$;

create or replace function public.saude_erro_grave(p_codigo text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(p_codigo in ('190','10','200','131005','131031','368','131042',
                               '133010','132001','132000','132015','132016'), false)
$$;

create or replace function public.saude_verificar()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_itens     jsonb := '[]'::jsonb;
  v_negocio   jsonb := '[]'::jsonb;
  v_jobid     bigint;
  v_schedule  text;
  v_cada      text;
  v_ativo     boolean;
  v_ultima    timestamptz;
  v_falhas_c  int;
  v_msg_c     text;
  v_status    int;
  v_tempo     boolean;
  v_erro_net  text;
  v_conteudo  text;
  v_erros_r   int;
  v_total_r   int;
  v_atrasadas int;
  v_antiga    timestamptz;
  v_presas    int;
  v_bloqueadas int;
  v_pendentes int;
  v_falhando  int;
  v_cod_agora text;
  v_falhou24  int;
  v_cod_24    text;
  v_enviadas  int;
  v_ultimo    timestamptz;
  v_grave     text;
  v_lista     text;
  v_nivel     text := 'ok';
  hm constant text := 'DD/MM HH24:MI';
begin
  -- 1. O banco. Se chegou aqui, responde.
  v_itens := v_itens || public.saude_item('banco', 'ok', 'Banco de dados', 'respondendo');

  -- 2. O despertador da fila.
  if to_regclass('cron.job') is null then
    v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
      'o pg_cron não está ligado neste banco: nada dispara o envio das mensagens.',
      'Rode o LIGAR-WHATSAPP.sql no SQL Editor do Supabase.');
  else
    select j.jobid, j.schedule, j.active into v_jobid, v_schedule, v_ativo
      from cron.job j where j.jobname = 'agendapro-notificacoes';
    -- O pg_cron escreve em inglês ("15 seconds"); a tela é em português.
    v_cada := case when v_schedule ~ '^[0-9]+ seconds?$'
                     then 'a cada ' || split_part(v_schedule, ' ', 1) || ' segundos'
                   when v_schedule = '* * * * *' then 'a cada minuto'
                   else 'no horário ' || v_schedule end;
    if v_jobid is null then
      v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
        'o despertador agendapro-notificacoes não existe: as mensagens não saem.',
        'Rode o LIGAR-WHATSAPP.sql no SQL Editor do Supabase.');
    elsif not v_ativo then
      v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
        'o despertador está pausado: as mensagens não saem.',
        'Rode o LIGAR-WHATSAPP.sql de novo, ou religue o agendapro-notificacoes no Supabase (Integrations, Cron).');
    elsif to_regclass('cron.job_run_details') is null then
      v_itens := v_itens || public.saude_item('despertador', 'ok', 'Despertador da fila',
        'ligado, ' || v_cada || '.');
    else
      /* As últimas voltas pela chave primária, e não `max(start_time)`: o
         pg_cron não apaga o histórico sozinho, e a cada 15 segundos ele passa
         de 5 mil linhas por dia. Pela chave, são 40 linhas lidas, sempre. */
      select max(d.start_time),
             count(*) filter (where d.status = 'failed'
                                and d.start_time > now() - interval '10 minutes'),
             (array_agg(d.return_message order by d.runid desc)
                filter (where d.status = 'failed'))[1]
        into v_ultima, v_falhas_c, v_msg_c
        from (select r.runid, r.start_time, r.status, r.return_message
                from cron.job_run_details r
               where r.jobid = v_jobid
               order by r.runid desc limit 40) d;
      if v_ultima is null or v_ultima < now() - interval '3 minutes' then
        v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
          case when v_ultima is null then 'o despertador nunca rodou.'
               else 'o despertador não roda desde '
                    || to_char(v_ultima at time zone 'America/Sao_Paulo', hm) || '.' end,
          'Confira em Integrations, Cron, no Supabase. Se não resolver, rode o LIGAR-WHATSAPP.sql de novo.');
      elsif v_falhas_c > 0 then
        v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
          'o despertador falhou ' || v_falhas_c || ' vez(es) nos últimos 10 minutos: '
          || coalesce(left(v_msg_c, 160), 'sem mensagem') || '.',
          'Rode o LIGAR-WHATSAPP.sql de novo (ele também liga o pg_net).');
      else
        v_itens := v_itens || public.saude_item('despertador', 'ok', 'Despertador da fila',
          'rodando ' || v_cada || ' (última volta às '
          || to_char(v_ultima at time zone 'America/Sao_Paulo', 'HH24:MI:SS') || ').');
      end if;
    end if;
  end if;

  -- 3. A função de envio, pelo que ela respondeu ao despertador.
  if to_regclass('net._http_response') is not null then
    select count(*) filter (where r.status_code >= 400 or r.timed_out or r.error_msg is not null),
           count(*)
      into v_erros_r, v_total_r
      from (select * from net._http_response order by id desc limit 20) r;
    select r.status_code, coalesce(r.timed_out, false), r.error_msg, left(r.content, 200)
      into v_status, v_tempo, v_erro_net, v_conteudo
      from net._http_response r order by r.id desc limit 1;

    if v_total_r = 0 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'atencao', 'Função de envio',
        'ainda não há resposta registrada da função enviar-notificacoes.',
        'Se o despertador acabou de ser ligado, espere um minuto e verifique de novo.');
    elsif v_tempo then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função enviar-notificacoes não respondeu a tempo.',
        'Abra os logs da função enviar-notificacoes no Supabase (Edge Functions).');
    elsif v_erro_net is not null then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'o despertador não conseguiu chamar a função: ' || left(v_erro_net, 160) || '.',
        'Confira o endereço da função no LIGAR-WHATSAPP.sql.');
    elsif v_status = 401 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função recusou o despertador (401): a frase do CRON_SEGREDO não é a mesma dos dois lados.',
        'Confira o segredo CRON_SEGREDO no Supabase (Edge Functions, Secrets) e o x-cron-segredo no LIGAR-WHATSAPP.sql.');
    elsif v_status = 404 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função enviar-notificacoes não está publicada (404).',
        'No GitHub: Actions, "Publicar as funções", Run workflow.');
    elsif v_status = 503 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'faltam WHATSAPP_TOKEN e/ou WHATSAPP_PHONE_ID nos segredos da função (503).',
        'Cadastre os dois no Supabase (Edge Functions, Secrets).');
    elsif v_status >= 400 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função de envio respondeu com erro ' || v_status || ': '
        || coalesce(nullif(btrim(v_conteudo), ''), 'sem detalhe') || '.',
        'Abra os logs da função enviar-notificacoes no Supabase (Edge Functions).');
    elsif v_erros_r > 5 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'atencao', 'Função de envio',
        v_erros_r || ' das últimas ' || v_total_r || ' chamadas deram erro; a última foi bem.');
    else
      v_itens := v_itens || public.saude_item('funcao_envio', 'ok', 'Função de envio',
        'respondendo (última resposta: ' || v_status || ').');
    end if;
  end if;

  -- 4. A fila. Atrasada é a que já devia ter saído há 5 minutos, não está
  -- esperando nova tentativa e não está parada pela franquia do salão (essa
  -- espera de propósito, e entra no negócio, mais abaixo).
  select count(*), min(n.quando) into v_atrasadas, v_antiga
    from public.notificacoes n
   where n.status = 'pendente' and n.erro_codigo is null
     and n.quando < now() - interval '5 minutes'
     and (n.proxima_em is null or n.proxima_em < now())
     and public.pode_enviar_tipo(n.salao_id, n.tipo);
  select count(*) into v_presas
    from public.notificacoes n
   where n.status = 'enviando'
     and coalesce(n.proxima_em, n.quando + interval '1 hour') < now();
  select count(*) filter (where n.quando <= now() and not public.pode_enviar_tipo(n.salao_id, n.tipo)),
         count(*)
    into v_bloqueadas, v_pendentes
    from public.notificacoes n where n.status = 'pendente';

  if v_atrasadas > 0 or v_presas > 0 then
    v_itens := v_itens || public.saude_item('fila', 'problema', 'Fila de mensagens',
      concat_ws(' ',
        case when v_atrasadas > 0 then v_atrasadas || ' mensagem(ns) atrasada(s): a mais antiga devia ter saído em '
             || to_char(v_antiga at time zone 'America/Sao_Paulo', hm) || '.' end,
        case when v_presas > 0 then v_presas || ' presa(s) no meio do envio.' end),
      'Veja o despertador e a função de envio acima. Se os dois estiverem certos, abra os logs da função enviar-notificacoes.');
  else
    v_itens := v_itens || public.saude_item('fila', 'ok', 'Fila de mensagens',
      'nenhuma mensagem atrasada (' || v_pendentes || ' na fila para mais tarde).');
  end if;

  -- 5. As falhas: as que estão tentando de novo agora, e as das últimas 24h.
  select count(*), mode() within group (order by n.erro_codigo)
    into v_falhando, v_cod_agora
    from public.notificacoes n where n.status = 'pendente' and n.erro_codigo is not null;
  select count(*), mode() within group (order by n.erro_codigo)
    into v_falhou24, v_cod_24
    from public.notificacoes n
   where n.status = 'falhou' and n.quando > now() - interval '24 hours';
  select count(*), max(n.enviado_em) into v_enviadas, v_ultimo
    from public.notificacoes n
   where n.status in ('enviado', 'entregue', 'lido')
     and n.enviado_em > now() - interval '24 hours';
  select n.erro_codigo into v_grave
    from public.notificacoes n
   where public.saude_erro_grave(n.erro_codigo)
     and ((n.status = 'pendente') or (n.status = 'falhou' and n.quando > now() - interval '24 hours'))
   order by n.quando desc limit 1;

  if v_grave is not null then
    v_itens := v_itens || public.saude_item('falhas', 'problema', 'Envio pelo WhatsApp',
      'as mensagens estão falhando: ' || public.saude_erro_meta(v_grave),
      'Resolva na Meta ou no Supabase como dito ao lado. As que ainda estão tentando saem sozinhas depois.');
  elsif v_falhou24 >= 5 and v_falhou24 > v_enviadas then
    v_itens := v_itens || public.saude_item('falhas', 'problema', 'Envio pelo WhatsApp',
      'mais falhas que envios nas últimas 24h (' || v_falhou24 || ' falharam, '
      || v_enviadas || ' saíram). Motivo mais comum: ' || public.saude_erro_meta(v_cod_24),
      'Veja o histórico em Notificações, num salão, para o motivo de cada uma.');
  elsif v_falhando > 0 or v_falhou24 > 0 then
    v_itens := v_itens || public.saude_item('falhas', 'atencao', 'Envio pelo WhatsApp',
      concat_ws(' ',
        case when v_falhou24 > 0 then v_falhou24 || ' falharam nas últimas 24h (' || v_enviadas
             || ' saíram). Motivo mais comum: ' || public.saude_erro_meta(v_cod_24) end,
        case when v_falhando > 0 then v_falhando || ' tentando de novo agora: '
             || public.saude_erro_meta(v_cod_agora) end));
  else
    v_itens := v_itens || public.saude_item('falhas', 'ok', 'Envio pelo WhatsApp',
      v_enviadas || ' enviada(s) nas últimas 24h, nenhuma falha.');
  end if;

  -- 6. O negócio (só o admin vê): franquia acabando, assinatura vencendo.
  select string_agg(x.nome || ': ' || x.usado || ' de ' || x.teto, '; ' order by x.pct desc)
    into v_lista
    from (select s.nome, public.mensagens_no_mes(s.id) as usado,
                 public.teto_mensagens(s.id) as teto,
                 public.mensagens_no_mes(s.id)::numeric
                   / nullif(public.teto_mensagens(s.id), 0) as pct
            from public.saloes s
           where s.id in (select distinct n.salao_id from public.notificacoes n
                           where n.enviado_em > now() - interval '35 days')) x
   where x.teto > 0 and x.pct >= 0.9;
  if v_lista is not null then
    v_negocio := v_negocio || public.saude_item('franquia', 'atencao',
      'Salões com as mensagens acabando', v_lista || '.',
      'Ofereça um plano maior ou mensagens extras.');
  end if;
  if v_bloqueadas > 0 then
    v_negocio := v_negocio || public.saude_item('franquia_parada', 'atencao',
      'Mensagens paradas pela franquia', v_bloqueadas
      || ' mensagem(ns) esperando porque a franquia do salão acabou.');
  end if;

  select string_agg(s.nome || case when a.vence_em >= current_date
                                   then ' vence em ' else ' venceu em ' end
                    || to_char(a.vence_em, 'DD/MM'), '; ' order by a.vence_em)
    into v_lista
    from public.assinaturas a join public.saloes s on s.id = a.salao_id
   where a.status = 'ativa'
     and a.vence_em between current_date - 7 and current_date + 3;
  if v_lista is not null then
    v_negocio := v_negocio || public.saude_item('vencimentos', 'atencao',
      'Assinaturas vencendo', v_lista || '.',
      'Quem passa do vencimento cai para o Grátis e para de receber mensagens.');
  end if;

  -- O pior de todos, só entre os do sistema: negócio não derruba o check-up.
  select case when bool_or(i->>'nivel' = 'problema') then 'problema'
              when bool_or(i->>'nivel' = 'atencao')  then 'atencao'
              else 'ok' end
    into v_nivel
    from jsonb_array_elements(v_itens) i;

  return jsonb_build_object(
    'nivel', v_nivel,
    'verificadoEm', now(),
    'itens', v_itens,
    'negocio', v_negocio,
    'numeros', jsonb_build_object(
      'enviadas24h', v_enviadas, 'falhas24h', v_falhou24,
      'pendentes', v_pendentes, 'ultimoEnvio', v_ultimo));
end $$;

/* O admin.html. Tudo, com nome de salão: é a plataforma olhando para si. */
create or replace function public.saude_plataforma()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma abre o check-up.'
      using errcode = 'insufficient_privilege';
  end if;
  return public.saude_verificar();
end $$;

/* A função de borda `saude`, que o UptimeRobot visita. Só o nível e as CHAVES
   do que está errado ("despertador", "falhas"…): nenhum nome de salão, número
   ou texto de mensagem sai daqui, porque o endereço é público. */
create or replace function public.saude_publica()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'nivel', s->>'nivel',
    'verificadoEm', s->'verificadoEm',
    'problemas', coalesce((select jsonb_agg(i->>'chave')
                             from jsonb_array_elements(s->'itens') i
                            where i->>'nivel' = 'problema'), '[]'::jsonb),
    'atencao', coalesce((select jsonb_agg(i->>'chave')
                           from jsonb_array_elements(s->'itens') i
                          where i->>'nivel' = 'atencao'), '[]'::jsonb))
    from (select public.saude_verificar() as s) x
$$;

revoke all on function public.saude_item(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.saude_erro_meta(text)  from public, anon, authenticated;
revoke all on function public.saude_erro_grave(text) from public, anon, authenticated;
revoke all on function public.saude_verificar()      from public, anon, authenticated;
revoke all on function public.saude_publica()        from public, anon, authenticated;
revoke all on function public.saude_plataforma()     from public, anon;
grant execute on function public.saude_plataforma() to authenticated;
/* ⚠ E O CARTEIRO PRECISA DA CHAVE (a mesma lição do 13_cobranca): o
   `revoke ... from public` tira também o `service_role`, que é com quem a
   função de borda fala com o banco. */
grant execute on function public.saude_publica() to service_role;
