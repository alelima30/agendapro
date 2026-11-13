-- ===========================================================================
-- 58_fuso.sql — o fuso horário do salão: escolher, e trocar sem mexer em
--               nenhum horário marcado
--
-- ── O QUE FALTAVA ─────────────────────────────────────────────────────────
-- `saloes.fuso` existe desde o primeiro dia e TUDO o respeita: o link da
-- cliente, a agenda, os lembretes, os relatórios, o "hoje" do caixa. Só que
-- não havia onde escolher. Todo salão nascia em 'America/Sao_Paulo' e ficava
-- lá — inclusive os de Manaus, Cuiabá, Campo Grande, Porto Velho, Boa Vista
-- e Rio Branco, que vivem uma ou duas horas atrás de Brasília.
--
-- Para esse salão a agenda PARECE certa: ele escreve 14:00, a tela mostra
-- 14:00, a cliente marca 14:00. O que erra é o relógio por baixo. O sistema
-- acha que agora é uma hora mais tarde do que é ali, então:
--   · o lembrete de "2 horas antes" sai 3 horas antes;
--   · o link para de oferecer o horário das 14:00 às 13:00 (acha que passou);
--   · o "hoje" vira à 23h, e o caixa do fim da noite cai no dia seguinte;
--   · o resumo das 8h chega às 7h.
--
-- ── O QUE ESTE ARQUIVO FAZ ────────────────────────────────────────────────
--   1. valida o fuso (nome que o Postgres E o navegador conhecem);
--   2. ao trocar, MOVE os instantes guardados para que cada horário continue
--      no MESMO horário de parede: quem marcou às 14:00 continua às 14:00;
--   3. guarda o histórico da troca;
--   4. trava a agenda do salão por 90 segundos depois da troca, para aparelho
--      com a tela aberta no relógio antigo não marcar com uma hora de erro;
--   5. dá ao painel a função `mudar_fuso()`.
--
-- ── POR QUE MOVER, E NÃO SÓ TROCAR O NOME ─────────────────────────────────
-- O banco guarda INSTANTES (timestamptz). "14:00 em São Paulo" e "14:00 em
-- Manaus" são instantes diferentes, com uma hora entre eles. Trocar só o
-- texto do fuso faria toda a agenda — passada e futura — aparecer uma hora
-- mais cedo: a cliente das 14:00 viraria cliente das 13:00, e chegaria com o
-- salão já tendo desistido dela. É o pior defeito possível numa agenda.
--
-- Então a regra é uma só, e vale para todo caminho (o painel, o cadastro, o
-- suporte no SQL Editor, uma chamada direta na API): o fuso mudou, os
-- horários de parede NÃO mudam. Quem garante é um gatilho em `saloes`, e não
-- uma função que alguém pode esquecer de chamar.
--
-- O QUE É MOVIDO — o que foi ESCRITO como hora de parede:
--   · agendamentos.inicio/fim (todos: o histórico também tem que continuar
--     dizendo 14:00, senão o relatório do mês passado muda de dia);
--   · bloqueios.inicio/fim;
--   · notificacoes.quando das que ainda vão sair (o lembrete acompanha o
--     horário dele);
--   · campanhas.agendada_para das que ainda não começaram.
-- O QUE NÃO É — o que foi CARIMBADO com o relógio de verdade (criado_em,
-- pagamento recebido, comanda fechada, mensagem enviada): esses instantes
-- estão certos, e passam a aparecer na hora certa da cidade.
--
-- ── POR QUE OS GATILHOS DA AGENDA SÃO DESLIGADOS DURANTE A MUDANÇA ────────
-- Mover o `inicio` é, para os gatilhos, uma remarcação: o `tg_notif_agenda_
-- mudou` mandaria "seu horário foi remarcado" para TODA cliente com horário
-- futuro, o `tg_agend_cabe` recusaria os do passado, o limite do plano
-- contaria tudo de novo. Nada disso aconteceu: nenhum horário mudou de
-- lugar no relógio de ninguém.
--
-- `alter table ... disable trigger user` vale só dentro desta transação e
-- segura a tabela enquanto ela dura — ninguém grava agendamento no meio, em
-- salão nenhum, por uma fração de segundo. Se qualquer coisa falhar, tudo
-- volta: os horários, o fuso e os gatilhos. A trava `agenda_sem_choque` NÃO
-- é gatilho e continua valendo o tempo todo.
--
-- ── POR QUE EM DOIS PASSOS ────────────────────────────────────────────────
-- A `agenda_sem_choque` confere linha por linha, na hora. Com dois horários
-- colados (9h–10h e 10h–11h), mover o primeiro uma hora para a frente bate
-- no segundo, que ainda não saiu do lugar — e a troca inteira cairia por um
-- choque que não existe. Então tudo vai primeiro para 100 anos adiante (em
-- horas exatas, para a volta ser a mesma conta) e de lá para o lugar certo.
-- ===========================================================================

alter table public.saloes add column if not exists fuso_mudou_em timestamptz;

create table if not exists public.fuso_mudancas (
  id            bigint generated always as identity primary key,
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  de            text not null,
  para          text not null,
  quando        timestamptz not null default now(),
  quem          uuid,
  agendamentos  int not null default 0,
  bloqueios     int not null default 0,
  lembretes     int not null default 0,
  campanhas     int not null default 0,
  obs           text
);
create index if not exists ix_fuso_mudancas_salao on public.fuso_mudancas(salao_id, id);

-- Histórico de suporte: ninguém lê nem escreve pela API. Quem grava é o
-- gatilho; quem lê é o `mudar_fuso()` (o resultado da própria troca) e o
-- dono do banco.
alter table public.fuso_mudancas enable row level security;
revoke all on public.fuso_mudancas from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1) FUSO VÁLIDO
--
-- O Postgres aceita muita coisa como fuso: 'BRT', 'UTC+3', 'posix/...'. O
-- navegador não — `Intl.DateTimeFormat` levanta com qualquer coisa que não
-- seja um nome da lista. E um fuso que o navegador recusa derruba a agenda,
-- o link e o caixa de uma vez, porque todos formatam hora com ele.
--
-- Então vale só nome no formato Região/Cidade que o Postgres conheça.
-- ---------------------------------------------------------------------------
create or replace function public.fuso_valido(p_fuso text)
returns boolean language sql stable set search_path = public as $$
  select p_fuso is not null
     and (p_fuso = 'UTC' or p_fuso ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+){1,2}$')
     and p_fuso !~* '^(posix|right)/'
     and exists (select 1 from pg_timezone_names z where z.name = p_fuso)
$$;

-- ---------------------------------------------------------------------------
-- 2) A MUDANÇA
-- ---------------------------------------------------------------------------
create or replace function public.fuso_mover_horarios(p_salao uuid, p_de text, p_para text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c_longe constant interval := interval '876000 hours';
  g        record;
  v_parados text[] := '{}';
  v_cmd    text;
  n_ag int := 0; n_bl int := 0; n_no int := 0; n_ca int := 0;
  v_obs    text;
begin
  if p_de is not distinct from p_para then
    return jsonb_build_object('agendamentos', 0, 'bloqueios', 0, 'lembretes', 0, 'campanhas', 0);
  end if;

  /* O fuso antigo não era um fuso (alguém gravou lixo pela API quando ainda
     não havia validação): não existe hora de parede para preservar, e toda
     conta com ele já levantava. Só registra. */
  if not public.fuso_valido(p_de) then
    insert into public.fuso_mudancas (salao_id, de, para, quem, obs)
    values (p_salao, coalesce(p_de, ''), p_para, auth.uid(),
            'o fuso anterior não era válido: nenhum horário foi movido');
    return jsonb_build_object('agendamentos', 0, 'bloqueios', 0, 'lembretes', 0, 'campanhas', 0);
  end if;

  /* Ninguém marca neste salão enquanto os horários andam: é a mesma trava
     que o `agendar()` pega antes de olhar a agenda. */
  perform public.travar_agenda(p_salao);

  /* Os que JÁ estavam desligados continuam desligados depois. */
  for g in
    select c.relname as tabela, t.tgname
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
     where t.tgrelid in ('public.agendamentos'::regclass, 'public.bloqueios'::regclass)
       and not t.tgisinternal and t.tgenabled = 'D'
  loop
    v_parados := v_parados || format('alter table public.%I disable trigger %I', g.tabela, g.tgname);
  end loop;

  alter table public.agendamentos disable trigger user;
  alter table public.bloqueios    disable trigger user;

  /* Passo 1: para longe. Passo 2: de lá para a mesma hora de parede no fuso
     novo. A duração é copiada, não recalculada — um horário de 45 minutos
     continua com 45 minutos mesmo que um dia um dos fusos tenha horário de
     verão no meio. */
  update public.agendamentos
     set inicio = inicio + c_longe, fim = fim + c_longe
   where salao_id = p_salao;

  update public.agendamentos
     set inicio = ((inicio - c_longe) at time zone p_de) at time zone p_para,
         fim    = (((inicio - c_longe) at time zone p_de) at time zone p_para) + (fim - inicio),
         /* O prazo do sinal é relógio de verdade e não anda. Só não pode
            passar a vencer DEPOIS de o horário começar. */
         sinal_ate = case when sinal_ate is null then null
                          else least(sinal_ate,
                                     ((inicio - c_longe) at time zone p_de) at time zone p_para) end
   where salao_id = p_salao;
  get diagnostics n_ag = row_count;

  update public.bloqueios
     set inicio = (inicio at time zone p_de) at time zone p_para,
         fim    = ((inicio at time zone p_de) at time zone p_para) + (fim - inicio)
   where salao_id = p_salao;
  get diagnostics n_bl = row_count;

  alter table public.agendamentos enable trigger user;
  alter table public.bloqueios    enable trigger user;
  foreach v_cmd in array v_parados loop
    execute v_cmd;
  end loop;

  /* O que ainda vai sair acompanha o horário dele. O que já devia ter saído
     (quando <= agora) sai agora, como ia sair. */
  update public.notificacoes
     set quando = (quando at time zone p_de) at time zone p_para
   where salao_id = p_salao and status = 'pendente' and quando > now();
  get diagnostics n_no = row_count;

  update public.campanhas
     set agendada_para = (agendada_para at time zone p_de) at time zone p_para
   where salao_id = p_salao and status in ('rascunho', 'agendada')
     and agendada_para is not null and agendada_para > now();
  get diagnostics n_ca = row_count;

  insert into public.fuso_mudancas
    (salao_id, de, para, quem, agendamentos, bloqueios, lembretes, campanhas, obs)
  values (p_salao, p_de, p_para, auth.uid(), n_ag, n_bl, n_no, n_ca, v_obs);

  return jsonb_build_object('agendamentos', n_ag, 'bloqueios', n_bl,
                            'lembretes', n_no, 'campanhas', n_ca);
exception
  when exclusion_violation then
    /* Só acontece se a hora de parede de dois horários coincidir no fuso
       novo e não coincidia no antigo (virada de horário de verão). Nada foi
       gravado: a transação inteira volta. */
    raise exception 'Não deu para trocar o fuso: dois horários do mesmo profissional ficariam um em cima do outro. Nada foi alterado. Fale com o suporte.'
      using errcode = 'exclusion_violation';
end $$;

-- ---------------------------------------------------------------------------
-- 3) OS GATILHOS EM `saloes`
--
-- ANTES: valida o nome e carimba a hora da troca. `fuso_mudou_em` não é
-- campo de ninguém: o que vier escrito nele é ignorado.
--
-- ⚠ Salão criado há menos de 10 minutos não é carimbado: é o cadastro
-- ajustando o próprio fuso (criar.html), com um aparelho só e nenhuma tela
-- antiga aberta. Sem isso, o dono de Manaus passaria o primeiro minuto e
-- meio do sistema sem conseguir marcar o primeiro horário.
-- ---------------------------------------------------------------------------
create or replace function public.tg_salao_fuso()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.fuso := nullif(btrim(coalesce(new.fuso, '')), '');

  if tg_op = 'INSERT' then
    if new.fuso is null then new.fuso := 'America/Sao_Paulo'; end if;
    if new.fuso <> 'America/Sao_Paulo' and not public.fuso_valido(new.fuso) then
      raise exception 'Não conheço o fuso horário "%". Use um nome como America/Sao_Paulo ou America/Manaus.', new.fuso
        using errcode = 'check_violation';
    end if;
    new.fuso_mudou_em := null;
    return new;
  end if;

  if new.fuso is null then
    raise exception 'O salão precisa de um fuso horário.' using errcode = 'check_violation';
  end if;

  if new.fuso is distinct from old.fuso then
    if not public.fuso_valido(new.fuso) then
      raise exception 'Não conheço o fuso horário "%". Use um nome como America/Sao_Paulo ou America/Manaus.', new.fuso
        using errcode = 'check_violation';
    end if;
    new.fuso_mudou_em := case
      when old.criado_em > now() - interval '10 minutes' then old.fuso_mudou_em
      else now() end;
  elsif coalesce(current_setting('role', true), 'none') in ('anon', 'authenticated') then
    /* Carimbo não é campo de quem usa: o que vier da API é ignorado. O dono
       do banco (o suporte, no SQL Editor) pode adiantar o fim da trava. */
    new.fuso_mudou_em := old.fuso_mudou_em;
  end if;
  return new;
end $$;

drop trigger if exists tg_salao_fuso on public.saloes;
create trigger tg_salao_fuso
  before insert or update on public.saloes
  for each row execute function public.tg_salao_fuso();

create or replace function public.tg_salao_fuso_mover()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.fuso is distinct from old.fuso then
    perform public.fuso_mover_horarios(new.id, old.fuso, new.fuso);
  end if;
  return null;
end $$;

drop trigger if exists tg_salao_fuso_mover on public.saloes;
create trigger tg_salao_fuso_mover
  after update of fuso on public.saloes
  for each row execute function public.tg_salao_fuso_mover();

-- ---------------------------------------------------------------------------
-- 4) A TRAVA DE 90 SEGUNDOS
--
-- O painel escreve o horário JUNTO com o nome do fuso que ele tem na memória
-- ('2026-08-22 14:00:00 America/Sao_Paulo'), e o link devolve o instante que
-- recebeu antes. Um aparelho com a tela aberta desde antes da troca ainda
-- pensa no relógio antigo — e o horário que ele gravasse nasceria com uma
-- hora de erro, sem aviso nenhum.
--
-- Por 90 segundos depois da troca, ninguém grava horário neste salão. É o
-- tempo de toda tela aberta notar a mudança e se atualizar sozinha (o painel
-- confere a cada 40 segundos e ao voltar para a aba). Pega também a gravação
-- que estava no ar esperando a troca terminar.
--
-- Chama `aa_` para rodar ANTES dos outros gatilhos da agenda: a pessoa tem
-- que ler "o relógio foi ajustado", e não "fora da jornada" — que é o que o
-- horário com uma hora de erro pareceria para o `tg_agend_cabe`.
--
-- Só `inicio` e `fim`: concluir, cancelar e cobrar continuam funcionando.
-- ---------------------------------------------------------------------------
create or replace function public.tg_fuso_recem_mudado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.saloes s
              where s.id = new.salao_id
                and s.fuso_mudou_em is not null
                and s.fuso_mudou_em > now() - interval '90 seconds') then
    raise exception 'O relógio do salão acabou de ser ajustado. Espere um minuto, atualize a página e tente de novo.'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  return new;
end $$;

drop trigger if exists aa_fuso_recente on public.agendamentos;
create trigger aa_fuso_recente
  before insert or update of inicio, fim on public.agendamentos
  for each row execute function public.tg_fuso_recem_mudado();

drop trigger if exists aa_fuso_recente on public.bloqueios;
create trigger aa_fuso_recente
  before insert or update of inicio, fim on public.bloqueios
  for each row execute function public.tg_fuso_recem_mudado();

-- ---------------------------------------------------------------------------
-- 5) O QUE O PAINEL CHAMA
--
-- Devolve o que aconteceu, para a tela poder dizer "47 horários continuam no
-- mesmo horário" em vez de só "pronto".
-- ---------------------------------------------------------------------------
create or replace function public.mudar_fuso(p_salao uuid, p_fuso text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_de   text;
  v_para text := nullif(btrim(coalesce(p_fuso, '')), '');
  v_log  public.fuso_mudancas%rowtype;
begin
  if auth.uid() is null or p_salao is null
     or not (public.e_gestor(p_salao) or public.is_super()) then
    raise exception 'Só quem administra o salão troca o fuso horário.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_para is null or not public.fuso_valido(v_para) then
    raise exception 'Não conheço o fuso horário "%".', coalesce(p_fuso, '')
      using errcode = 'check_violation';
  end if;

  select s.fuso into v_de from public.saloes s where s.id = p_salao for update;
  if not found then
    raise exception 'Não achei este salão.' using errcode = 'no_data_found';
  end if;
  if v_de = v_para then
    return jsonb_build_object('ok', true, 'mudou', false, 'fuso', v_para);
  end if;

  update public.saloes set fuso = v_para where id = p_salao;

  select * into v_log from public.fuso_mudancas
   where salao_id = p_salao order by id desc limit 1;

  return jsonb_build_object(
    'ok', true, 'mudou', true, 'de', v_de, 'fuso', v_para,
    'agendamentos', coalesce(v_log.agendamentos, 0),
    'bloqueios',    coalesce(v_log.bloqueios, 0),
    'lembretes',    coalesce(v_log.lembretes, 0),
    'campanhas',    coalesce(v_log.campanhas, 0));
end $$;

revoke all on function public.fuso_valido(text)                      from public, anon, authenticated;
revoke all on function public.fuso_mover_horarios(uuid, text, text)  from public, anon, authenticated;
revoke all on function public.tg_salao_fuso()                        from public, anon, authenticated;
revoke all on function public.tg_salao_fuso_mover()                  from public, anon, authenticated;
revoke all on function public.tg_fuso_recem_mudado()                 from public, anon, authenticated;
revoke all on function public.mudar_fuso(uuid, text)                 from public, anon;
grant execute on function public.mudar_fuso(uuid, text) to authenticated;
