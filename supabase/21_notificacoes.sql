-- ===========================================================================
-- AgendaPro — 21: confirmação, lembrete e resumo do dia
--
-- ── O QUE ESTA FASE É, E O QUE ELA NÃO É ──────────────────────────────────
-- Três mensagens que nascem da AGENDA e de mais nada:
--
--     confirmação        quando o horário é marcado
--     lembrete           uma vez, antes do horário
--     resumo do dia      uma vez por manhã, para quem trabalha
--
-- Não é campanha, não é promoção, não é disparo em massa. A diferença não é
-- de tamanho: é de origem. Campanha é um lote que alguém decide mandar;
-- estas três são consequência de um agendamento existir, e por isso quem as
-- cria é um gatilho, não uma tela.
--
-- ── A REGRA QUE MANDA EM TUDO AQUI ────────────────────────────────────────
-- NADA É MARCADO COMO ENVIADO SEM TER SIDO ENVIADO.
--
-- Enquanto a conta na Meta não estiver aprovada, as linhas nascem
-- `pendente` e ficam. O painel mostra "pendente", que é a verdade. Marcar
-- como enviada uma mensagem que não saiu é pior do que não ter mensagem
-- nenhuma: o salão para de ligar para a cliente confiando num aviso que
-- ninguém recebeu.
--
-- ── POR QUE UMA FILA, E NÃO UM ENVIO DIRETO ───────────────────────────────
-- Porque as três mensagens têm HORA. A confirmação sai agora; o lembrete sai
-- daqui a dois dias menos duas horas; o resumo sai amanhã às 8h. Um envio
-- direto teria de acontecer no instante do clique — e o lembrete não tem
-- clique nenhum.
--
-- A fila também é o que dá idempotência de graça: a chave única no banco
-- recusa a segunda tentativa, e nenhum caminho de código precisa lembrar de
-- conferir. É a mesma lição do 10_campanhas.sql.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O TELEFONE DE QUEM ATENDE
--
-- `profissionais` nasceu sem telefone: até agora ninguém precisava falar com
-- a pessoa, só marcar na agenda dela. A notificação de "novo agendamento"
-- precisa, e sem coluna não há para onde mandar.
--
-- Anulável de propósito: profissional que não quer receber nada no WhatsApp
-- simplesmente não tem número aqui, e isso é uma resposta legítima — não um
-- cadastro pela metade.
-- ---------------------------------------------------------------------------
alter table public.profissionais
  add column if not exists telefone text;

-- Duas chaves de vontade, por pessoa. O `cfg` do salão liga o recurso para a
-- casa; estas duas deixam cada um decidir por si dentro do que a casa ligou.
alter table public.profissionais
  add column if not exists notif_novo boolean not null default true;
alter table public.profissionais
  add column if not exists notif_resumo boolean not null default true;

-- ---------------------------------------------------------------------------
-- 2) AS CONFIGURAÇÕES DO SALÃO
--
-- Moram no `cfg` (jsonb), como `diasLiberados` e `tetoOnlinePct`. Tabela nova
-- para sete chaves seria tabela para manter, migrar e conferir sem ganhar
-- nada — e o `cfg` já é o lugar onde a tela sabe gravar.
--
-- Cada uma tem padrão, e o padrão é o comportamento de hoje quando existe um:
-- salão que nunca abriu a tela de notificações não muda de comportamento por
-- causa de uma publicação.
-- ---------------------------------------------------------------------------
create or replace function public.notif_liga(p_salao uuid, p_chave text,
                                             p_padrao boolean default true)
returns boolean language sql stable set search_path = public as $$
  select coalesce(
    (select (cfg->>p_chave)::boolean from public.saloes
      where id = p_salao and cfg->>p_chave in ('true','false')),
    p_padrao)
$$;

create or replace function public.notif_num(p_salao uuid, p_chave text,
                                            p_padrao int)
returns int language sql stable set search_path = public as $$
  select coalesce(
    (select (cfg->>p_chave)::int from public.saloes
      where id = p_salao and cfg->>p_chave ~ '^[0-9]+$'),
    p_padrao)
$$;

/* Quantos minutos antes o lembrete sai. Zero desliga — e desligar por aqui é
   diferente de desligar pela chave `notifLembrete`: um é "não quero lembrete",
   o outro é "quero, mas não sei quando". Os dois desligam; só o primeiro
   aparece desmarcado na tela. */
create or replace function public.lembrete_minutos(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select case when public.notif_liga(p_salao, 'notifLembrete', true)
              then greatest(0, least(1440,
                     public.notif_num(p_salao, 'notifLembreteMin', 120)))
              else 0 end
$$;

-- ---------------------------------------------------------------------------
-- 3) A FILA
--
-- Uma linha por mensagem, com a hora em que ela deve sair. O worker não
-- guarda nada em memória e o navegador não decide nada.
--
-- `corpo` é gravado no momento em que a linha nasce, e REESCRITO quando o
-- agendamento muda de hora (seção 7). Guardar o texto pronto é o que faz o
-- histórico dizer o que de fato foi mandado, em vez de remontar depois com
-- dados que já mudaram.
-- ---------------------------------------------------------------------------
create table if not exists public.notificacoes (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,

  tipo            text not null
                  check (tipo in ('confirmacao','lembrete','resumo','novo')),

  -- Para onde vai. Copiado no momento em que a linha nasce: se a ficha trocar
  -- de número depois, o histórico continua dizendo para onde foi.
  destino         text not null,
  -- De quem é o telefone acima. Os dois são anuláveis porque a mensagem é ou
  -- para a cliente, ou para quem trabalha — nunca para os dois.
  cliente_id      uuid references public.clientes(id) on delete set null,
  profissional_id uuid references public.profissionais(id) on delete set null,
  -- A confirmação e o lembrete morrem com o agendamento. O resumo não tem
  -- agendamento: ele fala de vários.
  agendamento_id  uuid references public.agendamentos(id) on delete cascade,

  -- O instante em que deve sair. É por ele que o worker varre.
  quando          timestamptz not null,
  corpo           text not null,

  /* ⚠ OS SEIS ESTADOS, E POR QUE SÃO SEIS.
     `pendente` é o estado de quem ainda não saiu — inclusive quando a conta
     na Meta não existe. `entregue` e `lido` só chegam por webhook de status,
     e enquanto o webhook não existir eles nunca aparecem. Estado que o
     sistema não sabe apurar é estado que ele não escreve. */
  status          text not null default 'pendente'
                  check (status in ('pendente','enviando','enviado',
                                    'entregue','lido','falhou','cancelado')),
  tentativas      smallint not null default 0 check (tentativas >= 0),
  proxima_em      timestamptz,
  enviado_em      timestamptz,
  erro_codigo     text,
  erro_msg        text,
  -- O que a Meta devolve, para casar o webhook de status quando ele existir.
  wam_id          text,
  -- Por que foi cancelada, quando foi: 'agendamento cancelado', 'venceu'.
  motivo          text,

  /* ⚠ A TRAVA CONTRA MENSAGEM REPETIDA.

     Refresh, duplo clique, retentativa, worker reiniciado, gatilho disparando
     duas vezes numa transação que voltou atrás: todos terminam tentando
     inserir a MESMA mensagem. A chave é natural, não sorteada —
     'lembrete:<agendamento>' é sempre a mesma string para o mesmo horário —
     e por isso o banco recusa a segunda antes de qualquer código pensar. */
  chave           text not null,

  criado_em       timestamptz not null default now()
);

create unique index if not exists ux_notif_chave
  on public.notificacoes(salao_id, chave);
-- O índice do worker: o que está pendente e já passou da hora, na ordem.
create index if not exists ix_notif_fila
  on public.notificacoes(quando)
  where status = 'pendente';
create index if not exists ix_notif_salao
  on public.notificacoes(salao_id, criado_em desc);
create index if not exists ix_notif_cliente
  on public.notificacoes(cliente_id, criado_em desc);
/* O índice do webhook de status. A Meta avisa de duas a três vezes por
   mensagem (delivered, read, e às vezes failed), e cada aviso é um `update
   ... where wam_id = ?`. Sem índice isso é uma varredura da fila inteira por
   aviso — barato hoje, com a fila vazia, e caro exatamente quando o volume
   chegar. Parcial porque só a linha já enviada tem wam_id. */
create index if not exists ix_notif_wam
  on public.notificacoes(wam_id)
  where wam_id is not null;

alter table public.notificacoes enable row level security;
alter table public.notificacoes force row level security;

/* Quem vê o histórico: a gestão e a recepção — é ela que atende o telefone
   quando a cliente diz "não recebi nada". Quem atende vê só as suas, que é o
   mesmo corte da agenda.

   Ninguém ESCREVE por aqui. As linhas nascem de gatilho e mudam de estado
   pelo worker, que usa a chave secreta. Uma tela que pudesse marcar como
   enviada seria uma tela que mente. */
drop policy if exists notif_ler on public.notificacoes;
create policy notif_ler on public.notificacoes for select to authenticated
  using ( public.ve_agenda_toda(salao_id)
          or profissional_id = public.meu_profissional_id(salao_id) );

revoke all on public.notificacoes from anon, authenticated;
grant select on public.notificacoes to authenticated;

-- ---------------------------------------------------------------------------
-- 4) O TEXTO
--
-- Montado no banco, e não na tela, porque quem manda é o worker — que não tem
-- tela. As variáveis do pedido ({{nome}}, {{data}}, {{horario}}, {{servico}},
-- {{profissional}}, {{empresa}}) são substituídas aqui, uma vez, e o
-- resultado fica gravado.
--
-- Tudo no FUSO DO SALÃO. Uma cliente lendo "14:00" precisa que sejam 14:00 no
-- salão, não no servidor.
-- ---------------------------------------------------------------------------
create or replace function public.texto_agendamento(
  p_agendamento uuid, p_tipo text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  a public.agendamentos%rowtype;
  v_fuso  text;
  v_casa  text;
  v_cli   text;
  v_prof  text;
  v_serv  text;
  v_data  text;
  v_hora  text;
begin
  select * into a from public.agendamentos where id = p_agendamento;
  if a.id is null then return null; end if;

  select coalesce(s.fuso, 'America/Sao_Paulo'), s.nome
    into v_fuso, v_casa
    from public.saloes s where s.id = a.salao_id;

  select coalesce(c.nome, a.atendido_nome, 'cliente') into v_cli
    from public.clientes c where c.id = a.cliente_id;
  select coalesce(p.apelido, p.nome, '—') into v_prof
    from public.profissionais p where p.id = a.profissional_id;

  select string_agg(sv.nome, ' + ' order by asv.ordem) into v_serv
    from public.agendamento_servicos asv
    join public.servicos sv on sv.id = asv.servico_id
   where asv.agendamento_id = a.id;
  v_serv := coalesce(v_serv, 'atendimento');

  v_data := to_char(a.inicio at time zone v_fuso, 'DD/MM/YYYY');
  v_hora := to_char(a.inicio at time zone v_fuso, 'HH24:MI');

  if p_tipo = 'confirmacao' then
    return format(
      'Olá, %s! Seu agendamento foi realizado com sucesso.'
      || E'\n\n📅 Data: %s'
      || E'\n🕐 Horário: %s'
      || E'\n✂️ Serviço: %s'
      || E'\n👤 Profissional: %s'
      || E'\n🏪 %s',
      split_part(v_cli, ' ', 1), v_data, v_hora, v_serv, v_prof, v_casa);

  elsif p_tipo = 'lembrete' then
    return format(
      '🔔 Olá, %s!'
      || E'\n\nEste é um lembrete do seu agendamento:'
      || E'\n\n📅 %s'
      || E'\n🕐 %s'
      || E'\n✂️ %s'
      || E'\n👤 %s'
      || E'\n\nEsperamos você!',
      split_part(v_cli, ' ', 1), v_data, v_hora, v_serv, v_prof);

  elsif p_tipo = 'novo' then
    return format(
      '🔔 Novo agendamento'
      || E'\n\nCliente: %s'
      || E'\nServiço: %s'
      || E'\nData: %s'
      || E'\nHorário: %s',
      v_cli, v_serv, v_data, v_hora);
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- 5) O RESUMO DO DIA
--
-- Uma mensagem só, com vários atendimentos dentro — e por isso o consumo dela
-- é UM, naturalmente: é uma linha na fila. O item 18 do pedido sai de graça
-- da modelagem, sem contador especial.
--
-- `p_profissional` nulo quer dizer "o salão inteiro", que é o resumo do dono
-- com equipe. Preenchido, é o resumo de uma pessoa só.
--
-- O período (dia inteiro / manhã / tarde) recorta por hora NO FUSO DO SALÃO.
-- ---------------------------------------------------------------------------
create or replace function public.texto_resumo(
  p_salao uuid, p_profissional uuid, p_dia date, p_periodo text default 'dia')
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso text;
  v_casa text;
  v_ini  timestamptz;
  v_fim  timestamptz;
  v_h1   int;
  v_h2   int;
  v_quem text;
  v_corpo text := '';
  v_total int := 0;
  v_sozinho boolean;
  r record;
  p record;
begin
  select coalesce(s.fuso, 'America/Sao_Paulo'), s.nome into v_fuso, v_casa
    from public.saloes s where s.id = p_salao;
  if v_fuso is null then return null; end if;

  -- A janela do período, em horas do salão. Os limites são configuráveis:
  -- salão que abre às 7h não tem "manhã das 8h".
  if p_periodo = 'manha' then
    v_h1 := public.notif_num(p_salao, 'notifManhaIni', 0);
    v_h2 := public.notif_num(p_salao, 'notifManhaFim', 12);
  elsif p_periodo = 'tarde' then
    v_h1 := public.notif_num(p_salao, 'notifTardeIni', 12);
    v_h2 := public.notif_num(p_salao, 'notifTardeFim', 24);
  else
    v_h1 := 0; v_h2 := 24;
  end if;

  v_ini := ((p_dia::timestamp) + make_interval(hours => v_h1)) at time zone v_fuso;
  v_fim := ((p_dia::timestamp) + make_interval(hours => v_h2)) at time zone v_fuso;

  /* ⚠ O DONO QUE TRABALHA SOZINHO (item 6 do pedido).

     Um salão de uma pessoa não precisa de cabeçalho de equipe: "👤 Alessandro"
     sozinho em cima da própria lista é ruído que só existe porque o código não
     olhou. A pergunta é quantos profissionais ATIVOS a casa tem, e ela é
     respondida aqui, não num ajuste que alguém teria de lembrar de marcar. */
  select count(*) = 1 into v_sozinho
    from public.profissionais where salao_id = p_salao and ativo;

  if p_profissional is not null or v_sozinho then
    select coalesce(pr.apelido, pr.nome) into v_quem
      from public.profissionais pr
     where pr.id = coalesce(p_profissional,
             (select id from public.profissionais
               where salao_id = p_salao and ativo limit 1));

    for r in
      select a.inicio,
             coalesce(c.nome, a.atendido_nome, 'sem nome') as cliente,
             coalesce((select string_agg(sv.nome, ' + ' order by asv.ordem)
                         from public.agendamento_servicos asv
                         join public.servicos sv on sv.id = asv.servico_id
                        where asv.agendamento_id = a.id), 'atendimento') as servico
        from public.agendamentos a
        left join public.clientes c on c.id = a.cliente_id
       where a.salao_id = p_salao
         and a.profissional_id = coalesce(p_profissional,
               (select id from public.profissionais
                 where salao_id = p_salao and ativo limit 1))
         and a.arquivado_em is null
         and a.status in ('pendente','confirmado','em_atendimento')
         and a.inicio >= v_ini and a.inicio < v_fim
       order by a.inicio
    loop
      v_total := v_total + 1;
      v_corpo := v_corpo || E'\n' || to_char(r.inicio at time zone v_fuso, 'HH24:MI')
              || ' — ' || r.cliente || ' — ' || r.servico;
    end loop;

    if v_total = 0 then return null; end if;   -- dia vazio não vira mensagem
    return format('☀️ Bom dia%s!' || E'\n\nSua agenda de hoje' || E'\n%s'
                  || E'\n\nTotal: %s atendimento%s',
                  case when p_profissional is not null
                       then ', ' || split_part(v_quem, ' ', 1) else '' end,
                  v_corpo, v_total, case when v_total = 1 then '' else 's' end);
  end if;

  -- O dono com equipe: um bloco por profissional, e quem não tem ninguém
  -- marcado hoje simplesmente não aparece.
  for p in
    select pr.id, coalesce(pr.apelido, pr.nome) as nome
      from public.profissionais pr
     where pr.salao_id = p_salao and pr.ativo
     order by pr.nome
  loop
    declare
      v_bloco text := '';
      v_n int := 0;
    begin
      for r in
        select a.inicio,
               coalesce(c.nome, a.atendido_nome, 'sem nome') as cliente,
               coalesce((select string_agg(sv.nome, ' + ' order by asv.ordem)
                           from public.agendamento_servicos asv
                           join public.servicos sv on sv.id = asv.servico_id
                          where asv.agendamento_id = a.id), 'atendimento') as servico
          from public.agendamentos a
          left join public.clientes c on c.id = a.cliente_id
         where a.salao_id = p_salao
           and a.profissional_id = p.id
           and a.arquivado_em is null
           and a.status in ('pendente','confirmado','em_atendimento')
           and a.inicio >= v_ini and a.inicio < v_fim
         order by a.inicio
      loop
        v_n := v_n + 1; v_total := v_total + 1;
        v_bloco := v_bloco || E'\n' || to_char(r.inicio at time zone v_fuso, 'HH24:MI')
                || ' — ' || r.cliente || ' — ' || r.servico;
      end loop;
      if v_n > 0 then
        v_corpo := v_corpo || E'\n\n👤 ' || p.nome || v_bloco;
      end if;
    end;
  end loop;

  if v_total = 0 then return null; end if;
  return format('☀️ Bom dia!' || E'\n\nAgenda de hoje — %s%s'
                || E'\n\nTotal: %s agendamento%s',
                v_casa, v_corpo, v_total,
                case when v_total = 1 then '' else 's' end);
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM CRIA AS LINHAS
--
-- Um gatilho no agendamento. `on conflict do nothing` mais a chave única: o
-- mesmo agendamento nunca gera duas confirmações, nem que o gatilho rode duas
-- vezes.
--
-- ⚠ Nada é criado para horário que já passou. Marcar às 15h um atendimento
-- das 9h da manhã — coisa que a recepção faz o tempo todo para registrar o
-- que já aconteceu — não pode mandar "seu agendamento foi realizado" nem
-- lembrete nenhum.
-- ---------------------------------------------------------------------------
create or replace function public.tg_notificar_agendamento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_tel_cli  text;
  v_tel_prof text;
  v_min      int;
  v_quando   timestamptz;
  v_corpo    text;
begin
  if new.status not in ('pendente','confirmado') or new.arquivado_em is not null then
    return new;
  end if;
  if new.inicio <= now() then return new; end if;

  select public.so_digitos(c.telefone) into v_tel_cli
    from public.clientes c where c.id = new.cliente_id;

  -- ── Confirmação, agora ──────────────────────────────────────────────
  if v_tel_cli is not null
     and public.notif_liga(new.salao_id, 'notifConfirma', true) then
    v_corpo := public.texto_agendamento(new.id, 'confirmacao');
    if v_corpo is not null then
      insert into public.notificacoes
        (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave)
      values (new.salao_id, 'confirmacao', v_tel_cli, new.cliente_id, new.id,
              now(), v_corpo, 'confirmacao:' || new.id)
      on conflict (salao_id, chave) do nothing;
    end if;
  end if;

  -- ── Lembrete, na hora configurada ───────────────────────────────────
  v_min := public.lembrete_minutos(new.salao_id);
  if v_tel_cli is not null and v_min > 0 then
    v_quando := new.inicio - make_interval(mins => v_min);
    -- Quem marca para daqui a uma hora com lembrete de duas não recebe
    -- lembrete: a hora dele já passou. Não é falha, é aritmética.
    if v_quando > now() then
      v_corpo := public.texto_agendamento(new.id, 'lembrete');
      if v_corpo is not null then
        insert into public.notificacoes
          (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave)
        values (new.salao_id, 'lembrete', v_tel_cli, new.cliente_id, new.id,
                v_quando, v_corpo, 'lembrete:' || new.id)
        on conflict (salao_id, chave) do nothing;
      end if;
    end if;
  end if;

  -- ── Aviso para quem vai atender ─────────────────────────────────────
  select public.so_digitos(pr.telefone) into v_tel_prof
    from public.profissionais pr
   where pr.id = new.profissional_id and pr.notif_novo;

  if v_tel_prof is not null
     and public.notif_liga(new.salao_id, 'notifProfNovo', true) then
    v_corpo := public.texto_agendamento(new.id, 'novo');
    if v_corpo is not null then
      insert into public.notificacoes
        (salao_id, tipo, destino, profissional_id, agendamento_id, quando, corpo, chave)
      values (new.salao_id, 'novo', v_tel_prof, new.profissional_id, new.id,
              now(), v_corpo, 'novo:' || new.id)
      on conflict (salao_id, chave) do nothing;
    end if;
  end if;

  return new;
end $$;

drop trigger if exists tg_notif_agendamento on public.agendamentos;
create trigger tg_notif_agendamento
  after insert on public.agendamentos
  for each row execute function public.tg_notificar_agendamento();

-- ---------------------------------------------------------------------------
-- 7) CANCELOU, MUDOU DE HORA
--
-- Os itens 11 e 12 do pedido, no mesmo gatilho porque são a mesma pergunta:
-- "o que está na fila ainda vale?".
--
-- Cancelado, faltou ou arquivado: o que ainda não saiu é cancelado. Mensagem
-- que já saiu não se desfaz — o histórico continua contando que ela saiu.
--
-- Mudou de hora: o lembrete é reagendado E REESCRITO. Sem reescrever o corpo,
-- a mensagem sairia na hora certa dizendo a hora errada, que é o pior dos
-- dois mundos.
-- ---------------------------------------------------------------------------
create or replace function public.tg_notificacao_agenda_mudou()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_min    int;
  v_quando timestamptz;
begin
  if new.status in ('cancelado','faltou') or new.arquivado_em is not null then
    update public.notificacoes
       set status = 'cancelado',
           motivo = case when new.arquivado_em is not null then 'agendamento arquivado'
                         when new.status = 'faltou' then 'cliente faltou'
                         else 'agendamento cancelado' end
     where agendamento_id = new.id and status = 'pendente';
    return new;
  end if;

  if new.inicio is distinct from old.inicio then
    v_min := public.lembrete_minutos(new.salao_id);
    v_quando := new.inicio - make_interval(mins => v_min);

    if v_min > 0 and v_quando > now() then
      update public.notificacoes
         set quando = v_quando,
             corpo  = coalesce(public.texto_agendamento(new.id, 'lembrete'), corpo)
       where agendamento_id = new.id and tipo = 'lembrete' and status = 'pendente';
    else
      -- Remarcado para daqui a pouco: não há mais lembrete que caiba.
      update public.notificacoes
         set status = 'cancelado', motivo = 'remarcado para depois da hora do lembrete'
       where agendamento_id = new.id and tipo = 'lembrete' and status = 'pendente';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tg_notif_agenda_mudou on public.agendamentos;
create trigger tg_notif_agenda_mudou
  after update of inicio, status, arquivado_em on public.agendamentos
  for each row execute function public.tg_notificacao_agenda_mudou();

-- ---------------------------------------------------------------------------
-- 7b) O SERVIÇO CHEGA DEPOIS DO AGENDAMENTO
--
-- ⚠ MEDIDO, E ERA DEFEITO DE VERDADE.
--
-- O agendamento e os serviços dele são duas tabelas. Tanto o painel quanto o
-- `agendar()` do link inserem o agendamento PRIMEIRO e as linhas de serviço
-- depois — não dá para ser diferente, a chave estrangeira exige o pai antes
-- do filho.
--
-- Só que o gatilho da seção 6 dispara no insert do agendamento, quando
-- `agendamento_servicos` ainda está vazio. O `texto_agendamento()` não acha
-- serviço nenhum, cai no padrão, e a confirmação sai dizendo:
--
--     ✂️ Serviço: atendimento
--
-- em vez de "Corte". Toda confirmação e todo lembrete do sistema, sempre.
--
-- Quem pegou foi o teste, na primeira execução. A saída não é montar o texto
-- só na hora de enviar — o corpo gravado é o que faz o histórico dizer o que
-- de fato foi mandado. É reescrever o corpo quando o serviço chega, que é
-- também o que conserta trocar o serviço de um horário já marcado.
-- ---------------------------------------------------------------------------
create or replace function public.tg_notificacao_servico_mudou()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ag uuid;
begin
  v_ag := coalesce(new.agendamento_id, old.agendamento_id);
  update public.notificacoes n
     set corpo = coalesce(public.texto_agendamento(v_ag, n.tipo), n.corpo)
   where n.agendamento_id = v_ag
     and n.status = 'pendente'
     and n.tipo in ('confirmacao','lembrete','novo');
  return coalesce(new, old);
end $$;

drop trigger if exists tg_notif_servico on public.agendamento_servicos;
create trigger tg_notif_servico
  after insert or update or delete on public.agendamento_servicos
  for each row execute function public.tg_notificacao_servico_mudou();

-- ---------------------------------------------------------------------------
-- 8) O RESUMO ENTRA NA FILA
--
-- Chamada pelo agendador, de minuto em minuto. Para cada salão cujo horário
-- de resumo já chegou HOJE no fuso dele, cria a linha — uma por destinatário.
--
-- `p_agora` existe para o teste poder fixar o instante. Sem ele, esta função
-- só seria testável esperando dar oito da manhã.
--
-- A chave inclui o DIA, então rodar de minuto em minuto o dia inteiro cria
-- uma linha só: as outras 1.439 chamadas esbarram na chave única.
-- ---------------------------------------------------------------------------
create or replace function public.gerar_resumos(p_agora timestamptz default now())
returns int language plpgsql security definer set search_path = public as $$
declare
  s record;
  pr record;
  v_fuso    text;
  v_hoje    date;
  v_hora    int;
  v_periodo text;
  v_corpo   text;
  v_tel     text;
  n int := 0;
begin
  for s in select id, coalesce(fuso, 'America/Sao_Paulo') as fuso from public.saloes
            where status = 'ativo'
  loop
    if not public.notif_liga(s.id, 'notifResumo', false) then continue; end if;

    v_fuso := s.fuso;
    v_hoje := (p_agora at time zone v_fuso)::date;
    v_hora := public.notif_num(s.id, 'notifResumoHora', 8);

    -- Ainda não deu a hora no salão.
    if extract(hour from (p_agora at time zone v_fuso))::int < v_hora then
      continue;
    end if;

    v_periodo := coalesce(
      (select cfg->>'notifResumoPeriodo' from public.saloes where id = s.id), 'dia');
    if v_periodo not in ('dia','manha','tarde') then v_periodo := 'dia'; end if;

    -- ── O dono, com a visão que o tamanho da casa pede ────────────────
    v_corpo := public.texto_resumo(s.id, null, v_hoje, v_periodo);
    if v_corpo is not null then
      select public.so_digitos(pr2.telefone) into v_tel
        from public.profissionais pr2
        join public.vinculos v on v.perfil_id = pr2.perfil_id
                              and v.salao_id = pr2.salao_id
       where pr2.salao_id = s.id and pr2.ativo and pr2.notif_resumo
         and v.papel in ('dono','admin') and v.status = 'ativo'
       limit 1;
      if v_tel is not null then
        insert into public.notificacoes
          (salao_id, tipo, destino, quando, corpo, chave)
        values (s.id, 'resumo', v_tel, p_agora, v_corpo,
                'resumo:casa:' || v_hoje)
        on conflict (salao_id, chave) do nothing;
        n := n + 1;
      end if;
    end if;

    /* ── Cada profissional, a agenda dele ──────────────────────────────
       Só quando a casa tem mais de um: com uma pessoa só, o resumo do dono
       ACIMA já é a agenda dela, e mandar os dois seria mandar a mesma lista
       duas vezes e cobrar duas mensagens. */
    if (select count(*) from public.profissionais
         where salao_id = s.id and ativo) > 1 then
      for pr in select id, telefone from public.profissionais
                 where salao_id = s.id and ativo and notif_resumo
                   and telefone is not null
      loop
        v_corpo := public.texto_resumo(s.id, pr.id, v_hoje, v_periodo);
        v_tel   := public.so_digitos(pr.telefone);
        if v_corpo is not null and v_tel is not null then
          insert into public.notificacoes
            (salao_id, tipo, destino, profissional_id, quando, corpo, chave)
          values (s.id, 'resumo', v_tel, pr.id, p_agora, v_corpo,
                  'resumo:' || pr.id || ':' || v_hoje)
          on conflict (salao_id, chave) do nothing;
          n := n + 1;
        end if;
      end loop;
    end if;
  end loop;
  return n;
end $$;

revoke all on function public.gerar_resumos(timestamptz) from public, anon, authenticated;

comment on table public.notificacoes is
  'Fila das mensagens que nascem da agenda: confirmação, lembrete, resumo e aviso ao profissional.';
comment on function public.gerar_resumos(timestamptz) is
  'Põe o resumo do dia na fila para os salões cuja hora já chegou. Idempotente por dia.';
