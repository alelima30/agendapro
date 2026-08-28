-- ===========================================================================
-- AgendaPro — 20: bloqueio e atendimento param de passar juntos
--
-- ── O QUE FOI MEDIDO ──────────────────────────────────────────────────────
-- Duas conexões, caminho normal, sem encaixe, jornada aberta:
--
--     A inseriu o atendimento (sem comitar)
--     B inseriu o bloqueio    (sem comitar)
--     A comitou
--     B comitou
--     depois das duas: {"atendimentos":"1","bloqueios":"1"}
--
-- O almoço e o atendimento ficaram no mesmo horário, e nada detecta o estado
-- depois. A grade desenha um bloco em cima do outro — foi o que já aconteceu
-- uma vez nos dados de demonstração, e ninguém percebeu até alguém olhar.
--
-- ── POR QUE PASSAVA ───────────────────────────────────────────────────────
-- Atendimento contra atendimento é uma CONSTRAINT: `agenda_sem_choque`, um
-- EXCLUDE com GiST. Constraint não tem corrida — o banco recusa e pronto.
--
-- Atendimento contra BLOQUEIO são duas tabelas, e EXCLUDE não atravessa duas
-- tabelas. A regra virou um par de gatilhos, e gatilho enxerga só o que já
-- foi comitado. Em READ COMMITTED — o padrão do Postgres e o que o Supabase
-- usa — as duas transações abertas ao mesmo tempo são invisíveis uma para a
-- outra: cada gatilho consulta, não acha nada, e deixa passar.
--
-- Não é caso de laboratório. É a recepção bloqueando o almoço no exato
-- momento em que uma cliente confirma pelo link, que é justamente o horário
-- em que as duas coisas competem.
--
-- ── O CONSERTO, E POR QUE ESTE E NÃO OUTRO ────────────────────────────────
-- `pg_advisory_xact_lock`, chaveado pelo salão, tomado no COMEÇO dos dois
-- caminhos — antes de qualquer consulta. Quem chega em segundo espera o
-- primeiro comitar, e aí enxerga o que ele gravou. A trava morre sozinha no
-- fim da transação; não há o que esquecer de soltar.
--
-- Foram consideradas duas alternativas:
--
--   · `select … from saloes … for update` — funciona, e prende a linha do
--     salão. Aí toda marcação passa a brigar com quem estiver salvando os
--     dados do salão em "Meu salão", por um motivo que não tem nada a ver.
--     Trava consultiva não toca em linha nenhuma.
--
--   · SERIALIZABLE — correto e caro: exigiria a aplicação inteira saber
--     repetir transação que falhou por serialização, e o PostgREST não sabe.
--
-- Fica registrado o conserto MAIOR, para quando houver fôlego: bloqueio virar
-- um agendamento de um tipo próprio, na mesma tabela, para o mesmo EXCLUDE
-- cobrir os dois casos e a regra deixar de ter duas metades.
--
-- ── O CUSTO ───────────────────────────────────────────────────────────────
-- Uma trava por salão, mantida por alguns milissegundos, e só enquanto se
-- escreve na agenda daquele salão. Dois salões diferentes nunca se esperam.
-- Dentro de um salão, duas marcações simultâneas passam a ser sequenciais —
-- que é exatamente o que se quer, e num volume de salão nem se mede.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A trava, num lugar só
--
-- `hashtext` do uuid: `pg_advisory_xact_lock` quer um bigint. Duas chaves
-- diferentes podem colidir no mesmo número — e colisão aqui não causa erro
-- nenhum, só faz dois salões esperarem um ao outro por alguns milissegundos.
-- Trocar correção por raridade seria o contrário do que este arquivo faz.
-- ---------------------------------------------------------------------------
create or replace function public.travar_agenda(p_salao uuid)
returns void language sql set search_path = public as $$
  select pg_advisory_xact_lock(hashtext(p_salao::text))
$$;

revoke all on function public.travar_agenda(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1) MARCANDO: trava, depois confere os bloqueios
--
-- Cópia fiel do 01_schema.sql com a trava na primeira linha útil. Ela vem
-- ANTES do `return new` dos estados que liberam a cadeira, de propósito: um
-- cancelamento não precisa de trava, e pegá-la ali só faria a recepção
-- esperar para desmarcar.
-- ---------------------------------------------------------------------------
create or replace function public.checar_bloqueio_agendamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  motivo_conflito text;
begin
  if new.status not in ('pendente','confirmado','em_atendimento','concluido')
     or new.arquivado_em is not null then
    return new;                    -- cancelado, faltou e arquivado liberam
  end if;

  -- ⚠ Antes da consulta, sempre. Depois dela a trava não serve para nada:
  -- o que se quer impedir é justamente ler antes de o outro comitar.
  perform public.travar_agenda(new.salao_id);

  select coalesce(b.motivo, 'bloqueado') into motivo_conflito
    from public.bloqueios b
   where b.salao_id = new.salao_id
     and (b.profissional_id = new.profissional_id or b.profissional_id is null)
     and tstzrange(b.inicio, b.fim, '[)') && tstzrange(new.inicio, new.fim, '[)')
   limit 1;

  if motivo_conflito is not null then
    raise exception 'Horário indisponível: %', motivo_conflito
      using errcode = 'exclusion_violation';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 2) BLOQUEANDO: a mesma trava, do outro lado
--
-- Tem que ser a MESMA chave, senão as duas transações pegam travas diferentes
-- e continuam sem se ver. Por isso a chave é o salão, e não o profissional:
-- bloqueio com `profissional_id` nulo vale para a casa inteira, e precisa
-- brigar com a marcação de qualquer pessoa dela.
-- ---------------------------------------------------------------------------
create or replace function public.checar_agendamento_bloqueio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  perform public.travar_agenda(new.salao_id);

  select count(*) into n
    from public.agendamentos a
   where a.salao_id = new.salao_id
     and (new.profissional_id is null or a.profissional_id = new.profissional_id)
     and a.status in ('pendente','confirmado','em_atendimento','concluido')
     and a.arquivado_em is null
     and tstzrange(a.inicio, a.fim, '[)') && tstzrange(new.inicio, new.fim, '[)');

  if n > 0 then
    raise exception
      'Existe atendimento marcado nesse período (% no total). Remarque antes de bloquear.', n
      using errcode = 'exclusion_violation';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- 3) E O GATILHO QUE RODA ANTES DE TODOS
--
-- Gatilhos do mesmo evento disparam em ordem alfabética de nome:
-- `tg_agend_cabe` vem antes de `tg_agend_vs_bloqueio`. O `cabe` também lê
-- bloqueio, então sem a trava aqui ele leria cedo demais — e recusaria ou
-- deixaria passar por um retrato velho da tabela.
--
-- Pegar a mesma trava duas vezes na mesma transação não custa nada: o
-- Postgres já a tem, e a segunda chamada volta na hora.
-- ---------------------------------------------------------------------------
create or replace function public.checar_cabe_agendamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status not in ('pendente','confirmado','em_atendimento','concluido')
     or new.arquivado_em is not null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.inicio = old.inicio
     and new.fim = old.fim
     and new.profissional_id = old.profissional_id then
    return new;
  end if;

  if new.encaixe then
    return new;
  end if;

  perform public.travar_agenda(new.salao_id);

  if public.ha_choque(new.profissional_id, new.inicio, new.fim, new.id)
     is not null then
    raise exception 'Esse horário já está ocupado.'
      using errcode = 'exclusion_violation';
  end if;

  -- O motivo do bloqueio fica de fora: "médico", "terapia" e "advogado" são
  -- assunto de quem trabalha no salão, não de quem está marcando.
  if public.ha_bloqueio(new.profissional_id, new.inicio, new.fim)
     is not null then
    raise exception 'Esse horário está bloqueado na agenda.'
      using errcode = 'check_violation';
  end if;

  if not public.cabe_na_jornada(new.profissional_id, new.inicio, new.fim) then
    raise exception 'Fora da jornada de trabalho deste profissional.'
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

comment on function public.travar_agenda(uuid) is
  'Trava consultiva por salão, até o fim da transação. Bloqueio e atendimento não se cruzam.';
