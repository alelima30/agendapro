alter table public.agendamentos
  add column if not exists arquivado_em timestamptz;
do $trava_choque$
begin
  if exists (select 1 from pg_constraint
              where conname = 'agenda_sem_choque'
                and conrelid = 'public.agendamentos'::regclass
                and pg_get_constraintdef(oid) not like '%arquivado_em%') then
    alter table public.agendamentos drop constraint agenda_sem_choque;
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'agenda_sem_choque'
                    and conrelid = 'public.agendamentos'::regclass) then
    alter table public.agendamentos add constraint agenda_sem_choque
      exclude using gist (
        profissional_id with =,
        tstzrange(inicio, fim, '[)') with &&
      ) where (status in ('pendente','confirmado','em_atendimento','concluido')
               and arquivado_em is null);
  end if;
end $trava_choque$;

create table if not exists public.precos_regras (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  servico_id      uuid not null references public.servicos(id) on delete cascade,
  profissional_id uuid references public.profissionais(id) on delete cascade,
  preco           numeric(10,2) not null check (preco >= 0),
  de              date,
  ate             date,
  dias            smallint[],
  hora_ini        int,
  hora_fim        int,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  constraint preco_regra_vigencia  check (de is null or ate is null or ate >= de),
  constraint preco_regra_faixa     check (
    (hora_ini is null and hora_fim is null)
    or (hora_ini is not null and hora_fim is not null
        and hora_ini >= 0 and hora_fim <= 1440 and hora_fim > hora_ini)),
  constraint preco_regra_dias      check (
    dias is null or (array_length(dias, 1) between 1 and 7
                     and 0 <= all(dias) and 7 > all(dias)))
);
create index if not exists ix_preco_regra_servico
  on public.precos_regras (servico_id) where ativo;
comment on table public.precos_regras is
  'Preço por vigência, dia da semana e faixa de horário. Recortes opcionais e combináveis; a regra mais específica ganha. Ver preco_do_servico().';
alter table public.precos_regras enable row level security;
drop policy if exists pr_ler on public.precos_regras;
create policy pr_ler on public.precos_regras for select to authenticated
  using (public.e_equipe(salao_id));
drop policy if exists pr_gerir on public.precos_regras;
create policy pr_gerir on public.precos_regras for all to authenticated
  using (public.e_gestor(salao_id))
  with check (public.e_gestor(salao_id));

create or replace function public.so_digitos(p_texto text)
returns text language sql immutable set search_path = public as $$
  select nullif(regexp_replace(coalesce(p_texto, ''), '[^0-9]', '', 'g'), '')
$$;

create or replace function public.mesmo_primeiro_nome(a text, b text)
returns boolean language sql immutable set search_path = public as $$
  select case when a is null or b is null then false else (
    select p <> '' and q <> ''
       and length(p) >= 2 and length(q) >= 2
       and left(p, least(length(p), length(q)))
         = left(q, least(length(p), length(q)))
      from (select lower(split_part(btrim(a), ' ', 1)) as p,
                   lower(split_part(btrim(b), ' ', 1)) as q) n
  ) end
$$;

update public.clientes
   set telefone = null
 where telefone is not null
   and public.so_digitos(telefone) is null;
with alvo as (
  select c.id,
         public.so_digitos(c.telefone) as limpo,
         row_number() over (partition by c.salao_id, public.so_digitos(c.telefone)
                            order by c.criado_em, c.id) as ordem
    from public.clientes c
   where c.telefone is not null
     and public.so_digitos(c.telefone) is not null
     and c.telefone <> public.so_digitos(c.telefone)
)
update public.clientes c
   set telefone = a.limpo
  from alvo a
 where c.id = a.id
   and a.ordem = 1
   and not exists (select 1 from public.clientes o
                    where o.salao_id = c.salao_id
                      and o.id <> c.id
                      and o.telefone = a.limpo);
do $trava$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'cli_tel_so_digitos'
                    and conrelid = 'public.clientes'::regclass) then
    alter table public.clientes
      add constraint cli_tel_so_digitos
      check (telefone is null or telefone ~ '^[0-9]+$') not valid;
  end if;
end $trava$;

alter table public.agendamentos
  add column if not exists encaixe boolean not null default false;
alter table public.agendamentos
  add column if not exists encaixe_por uuid references public.perfis(id)
    on delete set null;
comment on column public.agendamentos.encaixe is
  'Marcado fora da jornada, com confirmação explícita de quem tem acesso ao salão.';
create or replace function public.jornada_costurada(
  p_profissional uuid, p_data date)
returns table (inicio timestamptz, fim timestamptz)
language sql stable security definer set search_path = public as $$
  with fuso as (
    select coalesce(sa.fuso, 'America/Sao_Paulo') as z
      from public.profissionais p
      join public.saloes sa on sa.id = p.salao_id
     where p.id = p_profissional
  ),
  cruas as (
    select j.inicio, j.fim from public.jornadas j
     where j.profissional_id = p_profissional
       and j.dia_semana = extract(dow from p_data)::smallint
  ),
  marcadas as (
    select c.inicio, c.fim,
           case when c.inicio <= max(c.fim) over (
                  order by c.inicio, c.fim
                  rows between unbounded preceding and 1 preceding)
                then 0 else 1 end as nova
      from cruas c
  ),
  grupos as (
    select m.inicio, m.fim,
           sum(m.nova) over (order by m.inicio, m.fim
                             rows between unbounded preceding and current row) as g
      from marcadas m
  )
  select ((p_data + min(gr.inicio)) at time zone f.z),
         ((p_data + max(gr.fim))    at time zone f.z)
    from grupos gr cross join fuso f
   group by gr.g, f.z
   order by 1;
$$;
create or replace function public.cabe_na_jornada(
  p_profissional uuid, p_inicio timestamptz, p_fim timestamptz)
returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.jornadas
                      where profissional_id = p_profissional)
      or exists (
    select 1 from public.jornada_costurada(
                    p_profissional,
                    (p_inicio at time zone coalesce(
                       (select sa.fuso from public.profissionais p
                          join public.saloes sa on sa.id = p.salao_id
                         where p.id = p_profissional), 'America/Sao_Paulo'))::date) j
     where p_inicio >= j.inicio and p_fim <= j.fim);
$$;
create or replace function public.ha_bloqueio(
  p_profissional uuid, p_inicio timestamptz, p_fim timestamptz)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(b.motivo, 'bloqueado')
    from public.bloqueios b
    join public.profissionais p on p.id = p_profissional
   where b.salao_id = p.salao_id
     and (b.profissional_id = p_profissional or b.profissional_id is null)
     and tstzrange(b.inicio, b.fim, '[)') && tstzrange(p_inicio, p_fim, '[)')
   limit 1;
$$;
create or replace function public.ha_choque(
  p_profissional uuid, p_inicio timestamptz, p_fim timestamptz,
  p_ignorar uuid default null)
returns uuid
language sql stable security definer set search_path = public as $$
  select a.id from public.agendamentos a
   where a.profissional_id = p_profissional
     and a.status in ('pendente','confirmado','em_atendimento','concluido')
     and a.arquivado_em is null
     and (p_ignorar is null or a.id <> p_ignorar)
     and tstzrange(a.inicio, a.fim, '[)') && tstzrange(p_inicio, p_fim, '[)')
   limit 1;
$$;
create or replace function public.porque_nao_cabe(
  p_profissional uuid, p_inicio timestamptz, p_fim timestamptz,
  p_ignorar uuid default null)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_prof   record;
  v_motivo text;
  v_outro  uuid;
  v_fuso   text;
begin
  if p_inicio is null or p_fim is null or p_fim <= p_inicio then
    return 'Confira o horário: o fim tem que ser depois do início.';
  end if;
  select p.id, p.nome, p.ativo, sa.fuso, sa.status as status_salao
    into v_prof
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional;
  if v_prof.id is null then
    return 'Profissional não encontrado.';
  end if;
  if not v_prof.ativo then
    return format('%s está desativado(a) na equipe.', v_prof.nome);
  end if;
  if v_prof.status_salao <> 'ativo' then
    return 'Este salão está suspenso.';
  end if;
  v_fuso := coalesce(v_prof.fuso, 'America/Sao_Paulo');
  v_outro := public.ha_choque(p_profissional, p_inicio, p_fim, p_ignorar);
  if v_outro is not null then
    return (select format('%s já tem %s das %s às %s.',
              v_prof.nome,
              coalesce(c.nome, 'um atendimento'),
              to_char(a.inicio at time zone v_fuso, 'HH24:MI'),
              to_char(a.fim    at time zone v_fuso, 'HH24:MI'))
              from public.agendamentos a
              left join public.clientes c on c.id = a.cliente_id
             where a.id = v_outro);
  end if;
  v_motivo := public.ha_bloqueio(p_profissional, p_inicio, p_fim);
  if v_motivo is not null then
    return format('Horário bloqueado na agenda de %s: %s.', v_prof.nome, v_motivo);
  end if;
  if not public.cabe_na_jornada(p_profissional, p_inicio, p_fim) then
    return format('Fora da jornada de %s neste dia.', v_prof.nome);
  end if;
  return null;
end $$;
create or replace function public.avaliar_horario(
  p_profissional uuid, p_inicio timestamptz, p_fim timestamptz,
  p_ignorar uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_motivo text;
begin
  v_motivo := public.porque_nao_cabe(p_profissional, p_inicio, p_fim, p_ignorar);
  if v_motivo is null then
    return jsonb_build_object('cabe', true);
  end if;
  return jsonb_build_object(
    'cabe', false,
    'motivo', v_motivo,
    'encaixavel',
      public.ha_choque(p_profissional, p_inicio, p_fim, p_ignorar) is null
      and public.ha_bloqueio(p_profissional, p_inicio, p_fim) is null);
end $$;
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
  if public.ha_choque(new.profissional_id, new.inicio, new.fim, new.id)
     is not null then
    raise exception 'Esse horário já está ocupado.'
      using errcode = 'exclusion_violation';
  end if;
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
drop trigger if exists tg_agend_cabe on public.agendamentos;
create trigger tg_agend_cabe
  before insert or update of inicio, fim, profissional_id, status, encaixe
  on public.agendamentos
  for each row execute function public.checar_cabe_agendamento();
create or replace function public.horarios_livres(
  p_profissional uuid, p_data date, p_servicos uuid[])
returns setof timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v_duracao int;
  v_passo   constant interval := '15 minutes';
  v_cedo_demais interval;
  v_cfg     jsonb;
  j         record;
  v_ini     timestamptz;
  v_fim     timestamptz;
begin
  select sa.cfg into v_cfg
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional;
  v_cedo_demais := make_interval(mins => least(greatest(
    case when coalesce(v_cfg->>'antecedenciaMin', '') ~ '^[0-9]+$'
         then (v_cfg->>'antecedenciaMin')::int else 30 end, 0), 10080));
  if public.porque_nao_agenda(p_profissional, p_data, p_servicos) is not null then
    return;
  end if;
  v_duracao := public.duracao_dos_servicos(p_profissional, p_servicos);
  if v_duracao <= 0 then return; end if;
  for j in select * from public.jornada_costurada(p_profissional, p_data) loop
    v_ini := j.inicio;
    while v_ini + make_interval(mins => v_duracao) <= j.fim loop
      v_fim := v_ini + make_interval(mins => v_duracao);
      if v_ini >= now() + v_cedo_demais
         and public.ha_choque(p_profissional, v_ini, v_fim) is null
         and public.ha_bloqueio(p_profissional, v_ini, v_fim) is null
      then
        return next v_ini;
      end if;
      v_ini := v_ini + v_passo;
    end loop;
  end loop;
end $$;
revoke all on function public.jornada_costurada(uuid, date) from public, anon, authenticated;
revoke all on function public.cabe_na_jornada(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.ha_bloqueio(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.ha_choque(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.porque_nao_cabe(uuid, timestamptz, timestamptz, uuid) from public;
revoke all on function public.avaliar_horario(uuid, timestamptz, timestamptz, uuid) from public;
grant execute on function public.porque_nao_cabe(uuid, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.avaliar_horario(uuid, timestamptz, timestamptz, uuid) to authenticated;

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

create or replace function public.horarios_livres(
  p_profissional uuid, p_data date, p_servicos uuid[])
returns setof timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  v_duracao int;
  v_passo   constant interval := '15 minutes';
  v_cedo_demais interval;
  v_cfg     jsonb;
  j         record;
  v_ini     timestamptz;
  v_fim     timestamptz;
begin
  select sa.cfg into v_cfg
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional;
  v_cedo_demais := make_interval(mins => least(greatest(
    case when coalesce(v_cfg->>'antecedenciaMin', '') ~ '^[0-9]+$'
         then (v_cfg->>'antecedenciaMin')::int else 30 end, 0), 10080));
  if public.porque_nao_agenda(p_profissional, p_data, p_servicos) is not null then
    return;
  end if;
  v_duracao := public.duracao_dos_servicos(p_profissional, p_servicos);
  if v_duracao <= 0 then return; end if;
  for j in select * from public.jornada_costurada(p_profissional, p_data) loop
    v_ini := j.inicio;
    while v_ini + make_interval(mins => v_duracao) <= j.fim loop
      v_fim := v_ini + make_interval(mins => v_duracao);
      if v_ini >= now() + v_cedo_demais
         and public.ha_choque(p_profissional, v_ini, v_fim) is null
         and public.ha_bloqueio(p_profissional, v_ini, v_fim) is null
      then
        return next v_ini;
      end if;
      v_ini := v_ini + v_passo;
    end loop;
  end loop;
end $$;

revoke all on function public.horarios_livres(uuid, date, uuid[]) from public;

grant execute on function public.horarios_livres(uuid, date, uuid[]) to anon, authenticated;

create or replace function public.ficha_do_cliente(
  p_salao uuid, p_nome text, p_tel text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_perfil  uuid := auth.uid();
  v_cliente uuid;
begin
  if v_perfil is not null then
    select c.id into v_cliente from public.clientes c
     where c.salao_id = p_salao and c.perfil_id = v_perfil;
  end if;
  if v_cliente is null and p_tel is not null then
    select c.id into v_cliente from public.clientes c
     where c.salao_id = p_salao and c.telefone = p_tel;
  end if;
  if v_cliente is null then
    insert into public.clientes (salao_id, perfil_id, nome, telefone)
         values (p_salao, v_perfil, p_nome, p_tel)
      returning clientes.id into v_cliente;
    return v_cliente;
  end if;
  update public.clientes c
     set perfil_id = case
           when c.perfil_id is not null then c.perfil_id
           when v_perfil is null then null
           when public.mesmo_primeiro_nome(c.nome, p_nome) then v_perfil
           else null end,
         telefone  = case
           when p_tel is null or p_tel = c.telefone then c.telefone
           when exists (select 1 from public.clientes o
                         where o.salao_id = p_salao
                           and o.telefone = p_tel
                           and o.id <> c.id) then c.telefone
           else p_tel end
   where c.id = v_cliente;
  return v_cliente;
end $$;

revoke all on function public.ficha_do_cliente(uuid, text, text) from public;

create table if not exists public.pacotes (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  nome          text not null,
  descricao     text,
  preco         numeric(10,2) not null default 0,
  sessoes       int not null,
  validade_dias int not null default 90,
  dias          smallint[] not null default '{0,1,2,3,4,5,6}',
  so_nos_dias   boolean not null default false,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  constraint pacotes_sessoes_check   check (sessoes between 1 and 365),
  constraint pacotes_validade_check  check (validade_dias between 1 and 3650),
  constraint pacotes_preco_check     check (preco >= 0),
  constraint pacotes_dias_check      check (
    array_length(dias, 1) between 1 and 7
    and dias <@ array[0,1,2,3,4,5,6]::smallint[])
);
create index if not exists ix_pacote_salao on public.pacotes(salao_id) where ativo;
alter table public.pacotes
  add column if not exists so_nos_dias boolean not null default false;
create table if not exists public.pacote_servicos (
  id         uuid not null default gen_random_uuid(),
  pacote_id  uuid not null references public.pacotes(id)  on delete cascade,
  servico_id uuid not null references public.servicos(id) on delete cascade,
  primary key (pacote_id, servico_id)
);
create unique index if not exists ux_pacserv_id on public.pacote_servicos(id);
create table if not exists public.pacote_clientes (
  id           uuid primary key default gen_random_uuid(),
  pacote_id    uuid not null references public.pacotes(id)  on delete cascade,
  cliente_id   uuid not null references public.clientes(id) on delete cascade,
  sessoes      int  not null,
  vence_em     date not null,
  criado_em    timestamptz not null default now(),
  cancelado_em timestamptz,
  constraint pacote_clientes_sessoes_check check (sessoes between 1 and 365)
);
create index if not exists ix_pacote_cliente
  on public.pacote_clientes(cliente_id) where cancelado_em is null;
alter table public.agendamentos
  add column if not exists pacote_cliente_id uuid
    references public.pacote_clientes(id) on delete set null;
create index if not exists ix_agend_pacote
  on public.agendamentos(pacote_cliente_id)
  where pacote_cliente_id is not null;
create or replace function public.pacote_sessoes_restantes(p_pacote_cliente uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, pc.sessoes - (
      select count(*) from public.agendamentos a
       where a.pacote_cliente_id = pc.id
         and a.status in ('pendente','confirmado','em_atendimento','concluido')
         and a.arquivado_em is null))
    from public.pacote_clientes pc
   where pc.id = p_pacote_cliente
$$;
create or replace function public.pacote_que_cobre(
  p_cliente uuid, p_servicos uuid[], p_quando timestamptz)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso text;
  v_data date;
  v_dia  smallint;
  v_id   uuid;
begin
  if p_cliente is null or p_servicos is null or cardinality(p_servicos) = 0 then
    return null;
  end if;
  select sa.fuso into v_fuso
    from public.clientes c
    join public.saloes sa on sa.id = c.salao_id
   where c.id = p_cliente;
  if v_fuso is null then return null; end if;
  v_data := (p_quando at time zone v_fuso)::date;
  v_dia  := extract(dow from v_data)::smallint;
  select pc.id into v_id
    from public.pacote_clientes pc
    join public.pacotes p on p.id = pc.pacote_id
   where pc.cliente_id = p_cliente
     and pc.cancelado_em is null
     and pc.vence_em >= v_data
     and p.ativo
     and v_dia = any(p.dias)
     and not exists (
       select 1 from unnest(p_servicos) as pedido(id)
        where not exists (
          select 1 from public.pacote_servicos ps
           where ps.pacote_id = p.id and ps.servico_id = pedido.id))
     and public.pacote_sessoes_restantes(pc.id) > 0
   order by pc.vence_em, pc.criado_em
   limit 1;
  return v_id;
end $$;
create or replace function public.dias_por_extenso(p_dias smallint[])
returns text language plpgsql immutable set search_path = public as $$
declare v_nomes text[]; v_n int;
begin
  select array_agg(x.nome order by x.d) into v_nomes
    from (select distinct d,
                 (array['domingo','segunda','terça','quarta',
                        'quinta','sexta','sábado'])[d + 1] as nome
            from unnest(coalesce(p_dias, '{}'::smallint[])) as d
           where d between 0 and 6) x;
  v_n := coalesce(array_length(v_nomes, 1), 0);
  if v_n = 0 then return ''; end if;
  if v_n = 1 then return v_nomes[1]; end if;
  return array_to_string(v_nomes[1:v_n - 1], ', ') || ' e ' || v_nomes[v_n];
end $$;
create or replace function public.pacote_fora_do_dia(
  p_cliente uuid, p_servicos uuid[], p_quando timestamptz)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso text;
  v_data date;
  v_dia  smallint;
  v_nome text;
  v_dias smallint[];
begin
  if p_cliente is null or p_servicos is null or cardinality(p_servicos) = 0 then
    return null;
  end if;
  select sa.fuso into v_fuso
    from public.clientes c
    join public.saloes sa on sa.id = c.salao_id
   where c.id = p_cliente;
  if v_fuso is null then return null; end if;
  v_data := (p_quando at time zone v_fuso)::date;
  v_dia  := extract(dow from v_data)::smallint;
  select p.nome, p.dias into v_nome, v_dias
    from public.pacote_clientes pc
    join public.pacotes p on p.id = pc.pacote_id
   where pc.cliente_id = p_cliente
     and pc.cancelado_em is null
     and pc.vence_em >= v_data
     and p.ativo
     and p.so_nos_dias
     and not (v_dia = any(p.dias))
     and not exists (
       select 1 from unnest(p_servicos) as pedido(id)
        where not exists (
          select 1 from public.pacote_servicos ps
           where ps.pacote_id = p.id and ps.servico_id = pedido.id))
     and public.pacote_sessoes_restantes(pc.id) > 0
   order by pc.vence_em, pc.criado_em
   limit 1;
  if v_nome is null then return null; end if;
  return format(
    'Seu pacote %s vale %s. Para marcar fora desses dias, chame o salão no '
    || 'WhatsApp — dá para atender pagando.',
    v_nome, public.dias_por_extenso(v_dias));
end $$;
drop function if exists public.meus_pacotes(uuid);
create or replace function public.meus_pacotes(p_salao uuid)
returns table (id uuid, nome text, servicos uuid[], dias smallint[],
               vence_em date, restantes int, so_nos_dias boolean)
language sql stable security definer set search_path = public as $$
  select pc.id, p.nome,
         (select coalesce(array_agg(ps.servico_id), '{}')
            from public.pacote_servicos ps where ps.pacote_id = p.id),
         p.dias, pc.vence_em, public.pacote_sessoes_restantes(pc.id),
         p.so_nos_dias
    from public.pacote_clientes pc
    join public.pacotes  p on p.id = pc.pacote_id
    join public.clientes c on c.id = pc.cliente_id
   where c.salao_id = p_salao
     and c.perfil_id = auth.uid()
     and auth.uid() is not null
     and pc.cancelado_em is null
     and pc.vence_em >= public.hoje_no_salao(p_salao)
     and p.ativo
     and public.pacote_sessoes_restantes(pc.id) > 0
   order by pc.vence_em
$$;
create or replace function public.vender_pacote(p_pacote uuid, p_cliente uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_salao uuid; v_sess int; v_val int; v_id uuid;
begin
  select p.salao_id, p.sessoes, p.validade_dias into v_salao, v_sess, v_val
    from public.pacotes p where p.id = p_pacote and p.ativo;
  if v_salao is null then
    raise exception 'Pacote não encontrado ou desativado.'
      using errcode = 'check_violation';
  end if;
  if not public.e_gestor(v_salao) then
    raise exception 'Só o proprietário ou um administrador pode vender pacote.'
      using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.clientes c
                  where c.id = p_cliente and c.salao_id = v_salao) then
    raise exception 'Esta cliente não é deste salão.'
      using errcode = 'check_violation';
  end if;
  insert into public.pacote_clientes (pacote_id, cliente_id, sessoes, vence_em)
       values (p_pacote, p_cliente, v_sess,
               public.hoje_no_salao(v_salao) + v_val)
    returning pacote_clientes.id into v_id;
  return v_id;
end $$;
create or replace function public.cancelar_pacote_cliente(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_salao uuid;
begin
  select c.salao_id into v_salao
    from public.pacote_clientes pc
    join public.clientes c on c.id = pc.cliente_id
   where pc.id = p_id;
  if v_salao is null then return; end if;
  if not public.e_gestor(v_salao) then
    raise exception 'Só o proprietário ou um administrador pode cancelar pacote.'
      using errcode = 'insufficient_privilege';
  end if;
  update public.pacote_clientes set cancelado_em = now()
   where id = p_id and cancelado_em is null;
end $$;
alter table public.pacotes          enable row level security;
alter table public.pacote_servicos  enable row level security;
alter table public.pacote_clientes  enable row level security;
drop policy if exists pacotes_ler on public.pacotes;
create policy pacotes_ler on public.pacotes
  for select using (public.e_equipe(salao_id));
drop policy if exists pacotes_escrever on public.pacotes;
create policy pacotes_escrever on public.pacotes
  for all using (public.e_gestor(salao_id)) with check (public.e_gestor(salao_id));
drop policy if exists pservicos_ler on public.pacote_servicos;
create policy pservicos_ler on public.pacote_servicos
  for select using (exists (select 1 from public.pacotes p
                             where p.id = pacote_id and public.e_equipe(p.salao_id)));
drop policy if exists pservicos_escrever on public.pacote_servicos;
create policy pservicos_escrever on public.pacote_servicos
  for all using (exists (select 1 from public.pacotes p
                          where p.id = pacote_id and public.e_gestor(p.salao_id)))
  with check (exists (select 1 from public.pacotes p
                       where p.id = pacote_id and public.e_gestor(p.salao_id)));
drop policy if exists pclientes_ler on public.pacote_clientes;
create policy pclientes_ler on public.pacote_clientes
  for select using (exists (select 1 from public.clientes c
                             where c.id = cliente_id and public.e_equipe(c.salao_id)));
drop policy if exists pclientes_escrever on public.pacote_clientes;
create policy pclientes_escrever on public.pacote_clientes
  for all using (exists (select 1 from public.clientes c
                          where c.id = cliente_id and public.e_gestor(c.salao_id)))
  with check (exists (select 1 from public.clientes c
                       where c.id = cliente_id and public.e_gestor(c.salao_id)));
grant select, insert, update, delete on public.pacotes         to authenticated;
grant select, insert, update, delete on public.pacote_servicos to authenticated;
grant select, insert, update, delete on public.pacote_clientes to authenticated;
revoke all on function public.pacote_sessoes_restantes(uuid) from public, anon;
revoke all on function public.pacote_que_cobre(uuid, uuid[], timestamptz) from public, anon;
revoke all on function public.pacote_fora_do_dia(uuid, uuid[], timestamptz) from public, anon;
revoke all on function public.meus_pacotes(uuid)              from public, anon;
revoke all on function public.vender_pacote(uuid, uuid)       from public, anon;
revoke all on function public.cancelar_pacote_cliente(uuid)   from public, anon;
grant execute on function public.pacote_sessoes_restantes(uuid) to authenticated;
grant execute on function public.meus_pacotes(uuid)             to authenticated;
grant execute on function public.vender_pacote(uuid, uuid)      to authenticated;
grant execute on function public.cancelar_pacote_cliente(uuid)  to authenticated;
comment on function public.pacote_que_cobre(uuid, uuid[], timestamptz) is
  'Qual pacote da cliente cobre estes serviços neste dia. NÃO confere identidade — quem chama é que exige perfil_id = auth.uid().';
comment on function public.pacote_fora_do_dia(uuid, uuid[], timestamptz) is
  'Frase de recusa quando o pacote tem so_nos_dias e o dia está fora da lista. NULL quando não há nada a barrar. Só o link usa: a recepção marca por fora.';
comment on table public.pacotes is
  'Pacotes que o salão vende. `dias` no padrão do Postgres: 0=domingo. `so_nos_dias` faz o link recusar fora dos dias; o painel marca assim mesmo.';

create or replace function public.confirma_automatico(p_salao uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select lower(btrim(coalesce(sa.cfg->>'confirmaAuto', 'true')))
              not in ('false', 'f', '0', 'no', 'nao', 'não')
       from public.saloes sa where sa.id = p_salao),
    true)
$$;
comment on function public.confirma_automatico(uuid) is
  'O link confirma sozinho? cfg.confirmaAuto, padrão SIM. Desligado, o agendamento nasce pendente e espera o salão.';
drop trigger if exists tg_notif_agend_confirmado on public.agendamentos;
create trigger tg_notif_agend_confirmado
  after update of status on public.agendamentos
  for each row
  when (new.status = 'confirmado' and old.status is distinct from 'confirmado')
  execute function public.tg_notificar_agendamento();
revoke all on function public.confirma_automatico(uuid) from public;
grant execute on function public.confirma_automatico(uuid) to anon, authenticated;

create table if not exists public.precos_regras (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  servico_id      uuid not null references public.servicos(id) on delete cascade,
  profissional_id uuid references public.profissionais(id) on delete cascade,
  preco           numeric(10,2) not null check (preco >= 0),
  de              date,
  ate             date,
  dias            smallint[],
  hora_ini        int,
  hora_fim        int,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  constraint preco_regra_vigencia  check (de is null or ate is null or ate >= de),
  constraint preco_regra_faixa     check (
    (hora_ini is null and hora_fim is null)
    or (hora_ini is not null and hora_fim is not null
        and hora_ini >= 0 and hora_fim <= 1440 and hora_fim > hora_ini)),
  constraint preco_regra_dias      check (
    dias is null or (array_length(dias, 1) between 1 and 7
                     and 0 <= all(dias) and 7 > all(dias)))
);
create index if not exists ix_preco_regra_servico
  on public.precos_regras (servico_id) where ativo;
comment on table public.precos_regras is
  'Preço por vigência, dia da semana e faixa de horário. Recortes opcionais e combináveis; a regra mais específica ganha. Ver preco_do_servico().';
alter table public.precos_regras enable row level security;
drop policy if exists pr_ler on public.precos_regras;
create policy pr_ler on public.precos_regras for select to authenticated
  using (public.e_equipe(salao_id));
drop policy if exists pr_gerir on public.precos_regras;
create policy pr_gerir on public.precos_regras for all to authenticated
  using (public.e_gestor(salao_id))
  with check (public.e_gestor(salao_id));
grant select, insert, update, delete on public.precos_regras to authenticated;
create or replace function public.preco_regra_que_vale(
  p_servico uuid, p_profissional uuid, p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  with onde as (
    select sa.fuso
      from public.servicos sv
      join public.saloes sa on sa.id = sv.salao_id
     where sv.id = p_servico
  ),
  quando as (
    select (p_quando at time zone o.fuso)::date            as dia,
           extract(dow from (p_quando at time zone o.fuso))::smallint as dow,
           (extract(hour from (p_quando at time zone o.fuso)) * 60
            + extract(minute from (p_quando at time zone o.fuso)))::int as min
      from onde o
  )
  select r.preco
    from public.precos_regras r, quando q
   where r.ativo
     and r.servico_id = p_servico
     and (r.profissional_id is null or r.profissional_id = p_profissional)
     and (r.de   is null or q.dia >= r.de)
     and (r.ate  is null or q.dia <= r.ate)
     and (r.dias is null or array_length(r.dias, 1) is null or q.dow = any(r.dias))
     and (r.hora_ini is null or (q.min >= r.hora_ini and q.min < r.hora_fim))
   order by (case when r.profissional_id is not null then 8 else 0 end)
          + (case when r.dias is not null
                   and array_length(r.dias, 1) is not null then 4 else 0 end)
          + (case when r.hora_ini is not null then 2 else 0 end)
          + (case when r.de is not null or r.ate is not null then 1 else 0 end)
            desc,
            r.criado_em desc, r.id desc
   limit 1
$$;
comment on function public.preco_regra_que_vale(uuid, uuid, timestamptz) is
  'O preço da regra mais específica que casa com este horário, ou NULL quando nenhuma casa. Não é o menor preço: é a regra com mais recortes.';
create or replace function public.preco_do_servico(
  p_servico uuid, p_profissional uuid, p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  select coalesce(
    public.preco_regra_que_vale(p_servico, p_profissional, p_quando),
    (select sp.preco from public.servicos_profissionais sp
      where sp.servico_id = p_servico and sp.profissional_id = p_profissional),
    (select sv.preco from public.servicos sv where sv.id = p_servico),
    0)::numeric(10,2)
$$;
comment on function public.preco_do_servico(uuid, uuid, timestamptz) is
  'Quanto custa este serviço, com esta pessoa, neste horário. Escada: regra de preço, preço do par, preço do serviço.';
create or replace function public.preco_dos_servicos(
  p_profissional uuid, p_servicos uuid[], p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(public.preco_do_servico(s, p_profissional, p_quando)), 0)
           ::numeric(10,2)
    from unnest(p_servicos) as s
$$;
comment on function public.preco_dos_servicos(uuid, uuid[], timestamptz) is
  'A soma da escada de preço para os serviços pedidos, neste horário.';
create or replace function public.preco_dos_servicos(
  p_profissional uuid, p_servicos uuid[])
returns numeric language sql stable set search_path = public as $$
  select public.preco_dos_servicos(p_profissional, p_servicos, now())
$$;
comment on function public.preco_dos_servicos(uuid, uuid[]) is
  'A soma da escada de preço para AGORA. Prefira a versão com o horário: com regra de preço, o mesmo serviço custa diferente na terça de manhã e no sábado.';
create or replace function public.tg_preco_do_agendamento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_prof   uuid;
  v_inicio timestamptz;
begin
  if new.preco is not null then return new; end if;
  select a.profissional_id, a.inicio into v_prof, v_inicio
    from public.agendamentos a where a.id = new.agendamento_id;
  if v_prof is null or v_inicio is null then new.preco := 0; return new; end if;
  new.preco := public.preco_do_servico(new.servico_id, v_prof, v_inicio);
  return new;
end $$;
alter table public.agendamento_servicos alter column preco drop default;
drop trigger if exists tg_preco_agend_servico on public.agendamento_servicos;
create trigger tg_preco_agend_servico
  before insert on public.agendamento_servicos
  for each row execute function public.tg_preco_do_agendamento();
comment on function public.tg_preco_do_agendamento() is
  'Reescreve o preço da linha do agendamento com a escada do banco. É o que faz a regra valer também para o que a recepção marca.';
create or replace function public.preco_minimo_do_servico(
  p_servico uuid, p_ate date)
returns numeric language sql stable set search_path = public as $$
  select least(
    (select sv.preco from public.servicos sv where sv.id = p_servico),
    (select min(r.preco) from public.precos_regras r
      where r.ativo and r.servico_id = p_servico
        and (r.de  is null or r.de  <= p_ate)
        and (r.ate is null or r.ate >= current_date)))::numeric(10,2)
$$;
comment on function public.preco_minimo_do_servico(uuid, date) is
  'O menor preço que pode acontecer para este serviço dentro da janela aberta da agenda. Serve para o "a partir de" da capa.';
revoke all on function public.preco_regra_que_vale(uuid, uuid, timestamptz) from public;
revoke all on function public.preco_do_servico(uuid, uuid, timestamptz)     from public;
revoke all on function public.preco_dos_servicos(uuid, uuid[], timestamptz) from public;
revoke all on function public.preco_minimo_do_servico(uuid, date)           from public;
grant execute on function public.preco_regra_que_vale(uuid, uuid, timestamptz)
  to authenticated;
grant execute on function public.preco_do_servico(uuid, uuid, timestamptz)
  to authenticated;
grant execute on function public.preco_dos_servicos(uuid, uuid[], timestamptz)
  to authenticated;

alter table public.agendamentos
  add column if not exists gerenciar_token uuid not null default gen_random_uuid();
alter table public.lista_espera
  add column if not exists gerenciar_token uuid not null default gen_random_uuid();
create unique index if not exists ix_agend_token on public.agendamentos (gerenciar_token);
create unique index if not exists ix_espera_token on public.lista_espera (gerenciar_token);
alter table public.clientes add column if not exists cpf text;
drop function if exists public.agendar(uuid, timestamptz, uuid[], text, text, text, text);
drop function if exists public.agendar(uuid, timestamptz, uuid[], text, text, text, text,
                                       text, date);
create or replace function public.agendar(
  p_profissional  uuid,
  p_inicio        timestamptz,
  p_servicos      uuid[],
  p_nome          text,
  p_telefone      text,
  p_atendido_nome text default null,
  p_obs           text default null,
  p_email         text default null,
  p_nascimento    date default null,
  p_cpf           text default null)
returns table (id uuid, inicio timestamptz, fim timestamptz, valor numeric,
               token uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_salao    uuid;
  v_fuso     text;
  v_data     date;
  v_motivo   text;
  v_duracao  int;
  v_tel      text;
  v_nome     text;
  v_cliente  uuid;
  v_perfil   uuid;
  v_agend    uuid;
  v_token    uuid;
  v_fim      timestamptz;
  v_valor    numeric(10,2);
  v_abertos  int;
  v_quem     text;
  v_ordem    smallint := 1;
  v_pacote   uuid;
  s          record;
begin
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  v_tel  := public.so_digitos(p_telefone);
  if v_nome is null then
    raise exception 'Diga seu nome para a gente saber quem esperar.'
      using errcode = 'check_violation';
  end if;
  if v_tel is null or length(v_tel) < 10 or length(v_tel) > 13 then
    raise exception 'Confira o telefone: precisa do DDD.'
      using errcode = 'check_violation';
  end if;
  select p.salao_id, sa.fuso into v_salao, v_fuso
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional;
  if v_salao is null then
    raise exception 'Este profissional não está atendendo pela agenda online.'
      using errcode = 'check_violation';
  end if;
  v_data := (p_inicio at time zone v_fuso)::date;
  v_motivo := public.porque_nao_agenda(p_profissional, v_data, p_servicos);
  if v_motivo is not null then
    raise exception '%', v_motivo using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from public.horarios_livres(p_profissional, v_data, p_servicos) h
     where h = p_inicio)
  then
    raise exception 'Esse horário não está mais livre. Escolha outro, por favor.'
      using errcode = 'check_violation';
  end if;
  v_duracao := public.duracao_dos_servicos(p_profissional, p_servicos);
  v_valor   := public.preco_dos_servicos(p_profissional, p_servicos, p_inicio);
  v_fim     := p_inicio + make_interval(mins => v_duracao);
  v_perfil := auth.uid();
  v_cliente := public.ficha_do_cliente(v_salao, v_nome, v_tel);
  update public.clientes c
     set email      = coalesce(c.email, nullif(btrim(coalesce(p_email, '')), '')),
         nascimento = coalesce(c.nascimento, p_nascimento),
         cpf        = coalesce(c.cpf,
                        case when public.so_digitos(p_cpf) ~ '^[0-9]{11}$'
                             then public.so_digitos(p_cpf) end)
   where c.id = v_cliente
     and (c.email is null or c.nascimento is null or c.cpf is null);
  if nullif(btrim(coalesce(p_atendido_nome, '')), '') is null then
    select case when not public.mesmo_primeiro_nome(c.nome, v_nome)
                  then v_nome end
      into v_quem
      from public.clientes c where c.id = v_cliente;
  else
    v_quem := btrim(p_atendido_nome);
  end if;
  if v_perfil is not null and exists (
       select 1 from public.clientes c
        where c.id = v_cliente and c.perfil_id = v_perfil)
  then
    v_pacote := public.pacote_que_cobre(v_cliente, p_servicos, p_inicio);
    if v_pacote is not null then v_valor := 0; end if;
    if v_pacote is null then
      v_motivo := public.pacote_fora_do_dia(v_cliente, p_servicos, p_inicio);
      if v_motivo is not null then
        raise exception '%', v_motivo using errcode = 'check_violation';
      end if;
    end if;
  end if;
  select count(*) into v_abertos from public.agendamentos a
   where a.cliente_id = v_cliente
     and a.status in ('pendente','confirmado')
     and a.arquivado_em is null
     and a.inicio > now();
  if v_abertos >= 3 then
    raise exception 'Você já tem 3 horários marcados aqui. Cancele um antes de marcar outro.'
      using errcode = 'check_violation';
  end if;
  begin
    insert into public.agendamentos
      (salao_id, cliente_id, profissional_id, inicio, fim, status, origem,
       valor_previsto, atendido_nome, obs, criado_por, pacote_cliente_id)
    values
      (v_salao, v_cliente, p_profissional, p_inicio, v_fim,
       case when public.confirma_automatico(v_salao) then 'confirmado'
            else 'pendente' end, 'online',
       v_valor, v_quem,
       nullif(btrim(coalesce(p_obs, '')), ''), v_perfil, v_pacote)
    returning agendamentos.id, agendamentos.gerenciar_token into v_agend, v_token;
  exception
    when exclusion_violation then
      raise exception 'Alguém acabou de marcar esse horário. Escolha outro, por favor.'
        using errcode = 'check_violation';
  end;
  for s in
    select sv.id, coalesce(sp.duracao_min, sv.duracao_min) + sv.intervalo_min as dur,
           null::numeric as preco,
           coalesce(sv.comissao_pct, pr.comissao_pct, 0) as com
      from unnest(p_servicos) with ordinality as pedido(id, pos)
      join public.servicos sv on sv.id = pedido.id
      join public.profissionais pr on pr.id = p_profissional
      left join public.servicos_profissionais sp
             on sp.servico_id = sv.id and sp.profissional_id = p_profissional
     order by pedido.pos
  loop
    insert into public.agendamento_servicos
      (agendamento_id, servico_id, ordem, duracao_min, preco, comissao_pct)
    values (v_agend, s.id, v_ordem, s.dur, s.preco, s.com);
    v_ordem := v_ordem + 1;
  end loop;
  return query select v_agend, p_inicio, v_fim, v_valor, v_token;
end $$;
create or replace function public.meus_agendamentos(p_tokens uuid[])
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'inicio'), '[]'::jsonb) from (
    select jsonb_build_object(
      'token',     a.gerenciar_token,
      'inicio',    a.inicio,
      'fim',       a.fim,
      'status',    a.status,
      'atendido',  a.atendido_nome,
      'valor',     a.valor_previsto,
      'salao',     sa.nome,
      'slug',      sa.slug,
      'fuso',      sa.fuso,
      'profissional', coalesce(p.apelido, p.nome),
      'servicos', coalesce((
        select jsonb_agg(sv.nome order by asv.ordem)
          from public.agendamento_servicos asv
          join public.servicos sv on sv.id = asv.servico_id
         where asv.agendamento_id = a.id), '[]'::jsonb),
      'profissionalId', a.profissional_id,
      'servicoIds', coalesce((
        select jsonb_agg(asv.servico_id order by asv.ordem)
          from public.agendamento_servicos asv
         where asv.agendamento_id = a.id), '[]'::jsonb),
      'podeMexer', a.status in ('pendente','confirmado')
                   and a.inicio > now() + interval '2 hours'
    ) as x
      from public.agendamentos a
      join public.saloes sa        on sa.id = a.salao_id
      join public.profissionais p  on p.id  = a.profissional_id
     where a.gerenciar_token = any(coalesce(p_tokens, '{}'::uuid[]))
       and a.arquivado_em is null
  ) t
$$;
create or replace function public.cancelar_agendamento(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.agendamentos%rowtype;
begin
  select * into a from public.agendamentos where gerenciar_token = p_token;
  if a.id is null then
    raise exception 'Não achei esse horário. Confira o link.'
      using errcode = 'check_violation';
  end if;
  if a.status not in ('pendente','confirmado') then
    raise exception 'Este horário já foi %.',
      case a.status when 'cancelado' then 'cancelado'
                    when 'concluido' then 'atendido'
                    else a.status end
      using errcode = 'check_violation';
  end if;
  if a.inicio <= now() + interval '2 hours' then
    raise exception 'Faltam menos de 2 horas. Fale com o salão para desmarcar.'
      using errcode = 'check_violation';
  end if;
  update public.agendamentos
     set status = 'cancelado', cancelado_motivo = 'cancelado pelo cliente'
   where id = a.id;
  return jsonb_build_object('ok', true);
end $$;
create or replace function public.entrar_na_fila(
  p_salao      uuid,
  p_servicos   uuid[],
  p_nome       text,
  p_telefone   text,
  p_de         date,
  p_ate        date,
  p_profissional uuid default null,
  p_turno      text default 'qualquer',
  p_obs        text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tel     text;
  v_nome    text;
  v_cliente uuid;
  v_perfil  uuid := auth.uid();
  v_dur     int;
  v_hoje    date;
  v_token   uuid;
  v_abertas int;
  v_motivo  text;
begin
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  v_tel  := public.so_digitos(p_telefone);
  if v_nome is null then
    raise exception 'Diga seu nome para a gente saber quem avisar.'
      using errcode = 'check_violation';
  end if;
  if v_tel is null or length(v_tel) < 10 or length(v_tel) > 13 then
    raise exception 'Confira o telefone: precisa do DDD.'
      using errcode = 'check_violation';
  end if;
  if p_servicos is null or cardinality(p_servicos) = 0 then
    raise exception 'Escolha pelo menos um serviço.'
      using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.saloes
                  where id = p_salao and status = 'ativo') then
    raise exception 'Este salão não está aceitando pedidos agora.'
      using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from unnest(p_servicos) as pedido(id)
     where not exists (
       select 1 from public.servicos s
        where s.id = pedido.id and s.salao_id = p_salao
          and s.ativo and s.aceita_online))
  then
    raise exception 'Um dos serviços escolhidos não está disponível.'
      using errcode = 'check_violation';
  end if;
  v_hoje := public.hoje_no_salao(p_salao);
  if p_de < v_hoje or p_ate < p_de then
    raise exception 'Confira as datas do período.'
      using errcode = 'check_violation';
  end if;
  if p_ate > v_hoje + public.dias_liberados(p_salao) then
    raise exception 'A agenda está liberada até %.',
      to_char(v_hoje + public.dias_liberados(p_salao), 'DD/MM/YYYY')
      using errcode = 'check_violation';
  end if;
  v_motivo := public.servico_fora_do_periodo(p_servicos, p_de, p_ate);
  if v_motivo is not null then
    raise exception '%', v_motivo using errcode = 'check_violation';
  end if;
  v_cliente := public.ficha_do_cliente(p_salao, v_nome, v_tel);
  select count(*) into v_abertas from public.lista_espera
   where cliente_id = v_cliente and status = 'aguardando';
  if v_abertas >= 3 then
    raise exception 'Você já está em 3 listas de espera aqui. Saia de uma antes de entrar noutra.'
      using errcode = 'check_violation';
  end if;
  v_dur := public.duracao_dos_servicos(
             coalesce(p_profissional,
                      (select id from public.profissionais
                        where salao_id = p_salao and ativo limit 1)),
             p_servicos);
  insert into public.lista_espera
    (salao_id, cliente_id, profissional_id, servicos, duracao_min,
     de, ate, turno, obs, status)
  values
    (p_salao, v_cliente, p_profissional, to_jsonb(p_servicos), greatest(v_dur, 1),
     p_de, p_ate, coalesce(nullif(btrim(p_turno), ''), 'qualquer'),
     nullif(btrim(coalesce(p_obs, '')), ''), 'aguardando')
  returning gerenciar_token into v_token;
  return jsonb_build_object('token', v_token);
end $$;
create or replace function public.minha_fila(p_tokens uuid[])
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'de'), '[]'::jsonb) from (
    select jsonb_build_object(
      'token',  e.gerenciar_token,
      'de',     e.de,
      'ate',    e.ate,
      'turno',  e.turno,
      'status', e.status,
      'salao',  sa.nome,
      'slug',   sa.slug
    ) as x
      from public.lista_espera e
      join public.saloes sa on sa.id = e.salao_id
     where e.gerenciar_token = any(coalesce(p_tokens, '{}'::uuid[]))
       and e.status = 'aguardando'
  ) t
$$;
create or replace function public.sair_da_fila(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update public.lista_espera
     set status = 'desistiu'
   where gerenciar_token = p_token and status = 'aguardando';
  if not found then
    raise exception 'Não achei esse pedido na lista.'
      using errcode = 'check_violation';
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.meus_agendamentos(uuid[])   from public;
revoke all on function public.cancelar_agendamento(uuid)  from public;
revoke all on function public.minha_fila(uuid[])          from public;
revoke all on function public.sair_da_fila(uuid)          from public;
revoke all on function public.entrar_na_fila(uuid, uuid[], text, text, date, date,
                                             uuid, text, text) from public;
revoke all on function public.agendar(uuid, timestamptz, uuid[], text, text, text,
                                      text, text, date, text) from public;
grant execute on function public.meus_agendamentos(uuid[])   to anon, authenticated;
grant execute on function public.cancelar_agendamento(uuid)  to anon, authenticated;
grant execute on function public.minha_fila(uuid[])          to anon, authenticated;
grant execute on function public.sair_da_fila(uuid)          to anon, authenticated;
grant execute on function public.entrar_na_fila(uuid, uuid[], text, text, date, date,
                                                uuid, text, text) to anon, authenticated;
grant execute on function public.agendar(uuid, timestamptz, uuid[], text, text, text,
                                         text, text, date, text) to anon, authenticated;

create or replace function public.vitrine(p_slug text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'salao', jsonb_build_object(
      'id', s.id, 'slug', s.slug, 'nome', s.nome, 'tipo', s.tipo,
      'logo', s.logo, 'capa', s.capa,
      'telefone', s.telefone, 'whatsapp', s.whatsapp,
      'endereco', s.endereco, 'fuso', s.fuso,
      'diasLiberados', public.dias_liberados(s.id),
      'cor',  s.cfg->>'cor',
      'tema', s.cfg->>'tema',
      'precoNaCapa', lower(btrim(coalesce(s.cfg->>'precoNaCapa', 'false')))
                       in ('true', 't', '1', 'yes', 'sim'),
      'fundo', s.cfg->>'fundo',
      'brilho', lower(btrim(coalesce(s.cfg->>'brilho', 'true')))
                  not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'letra', s.cfg->>'letra',
      'slideDe', s.cfg->>'slideDe',
      'galeria', coalesce(s.cfg->'galeria', '[]'::jsonb),
      'capaFoco', case when s.cfg->>'capaFoco' ~ '^[0-9]+$'
                       then (s.cfg->>'capaFoco')::int end,
      'veu', case when s.cfg->>'veu' ~ '^[0-9]+$'
                  then (s.cfg->>'veu')::int end,
      'cartoes', s.cfg->>'cartoes',
      'moldura', coalesce(s.cfg->>'moldura', 'reta'),
      'cores',     coalesce(s.cfg->'cores', '{}'::jsonb),
      'modo',      coalesce(s.cfg->>'modo', 'atual'),
      'logoForma', coalesce(s.cfg->>'logoForma', 'circular'),
      'logoBorda', coalesce(s.cfg->>'logoBorda', 'media'),
      'slideForma', coalesce(s.cfg->>'slideForma', 'panoramico'),
      'fitaMetal',  coalesce(s.cfg->>'fitaMetal', 'media'),
      'fitaBrilho', lower(btrim(coalesce(s.cfg->>'fitaBrilho', 'true')))
                      not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'fitaTempo',  coalesce(s.cfg->>'fitaTempo', 'media'),
      'fitaCor',    s.cfg->>'fitaCor',
      'fitaBorda',  coalesce(s.cfg->>'fitaBorda', 'reta'),
      'fundoTipo', coalesce(s.cfg->>'fundoTipo', 'cor'),
      'gradiente', s.cfg->>'gradiente'
    ),
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'nome', v.nome, 'categoria', v.categoria,
               'descricao', v.descricao, 'duracaoMin', v.duracao_min,
               'preco', v.preco, 'foto', v.foto)
             order by v.categoria nulls last, v.nome)
        from public.servicos v
       where v.salao_id = s.id and v.ativo and v.aceita_online), '[]'::jsonb),
    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'nome', coalesce(p.apelido, p.nome),
               'foto', p.foto,
               'servicos', (select coalesce(jsonb_agg(sp.servico_id), '[]'::jsonb)
                              from public.servicos_profissionais sp
                             where sp.profissional_id = p.id))
             order by p.criado_em, p.id)
        from public.profissionais p
       where p.salao_id = s.id and p.ativo and p.aceita_online
         and public.profissional_na_cota(p.id)), '[]'::jsonb)
  )
  from public.saloes s
  where s.slug = p_slug and s.status = 'ativo'
$$;
revoke all on public.saloes_publicos        from anon, authenticated;
revoke all on public.servicos_publicos      from anon, authenticated;
revoke all on public.profissionais_publicos from anon, authenticated;
revoke all on function public.vitrine(text) from public;
grant execute on function public.vitrine(text) to anon, authenticated;

alter table public.servicos
  add column if not exists dias smallint[];
create table if not exists public.precos_regras (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  servico_id      uuid not null references public.servicos(id) on delete cascade,
  profissional_id uuid references public.profissionais(id) on delete cascade,
  preco           numeric(10,2) not null check (preco >= 0),
  de              date,
  ate             date,
  dias            smallint[],
  hora_ini        int,
  hora_fim        int,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),
  constraint preco_regra_vigencia  check (de is null or ate is null or ate >= de),
  constraint preco_regra_faixa     check (
    (hora_ini is null and hora_fim is null)
    or (hora_ini is not null and hora_fim is not null
        and hora_ini >= 0 and hora_fim <= 1440 and hora_fim > hora_ini)),
  constraint preco_regra_dias      check (
    dias is null or (array_length(dias, 1) between 1 and 7
                     and 0 <= all(dias) and 7 > all(dias)))
);
alter table public.produtos
  add column if not exists preco_visivel boolean not null default true;
create or replace function public.vitrine(p_slug text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'salao', jsonb_build_object(
      'id', s.id, 'slug', s.slug, 'nome', s.nome, 'tipo', s.tipo,
      'logo', s.logo, 'capa', s.capa,
      'telefone', s.telefone, 'whatsapp', s.whatsapp,
      'endereco', s.endereco, 'fuso', s.fuso,
      'diasLiberados', public.dias_liberados(s.id),
      'cor',  s.cfg->>'cor',
      'tema', s.cfg->>'tema',
      'precoNaCapa', lower(btrim(coalesce(s.cfg->>'precoNaCapa', 'false')))
                       in ('true', 't', '1', 'yes', 'sim'),
      'fundo', s.cfg->>'fundo',
      'brilho', lower(btrim(coalesce(s.cfg->>'brilho', 'true')))
                  not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'letra', s.cfg->>'letra',
      'slideDe', s.cfg->>'slideDe',
      'galeria', coalesce(s.cfg->'galeria', '[]'::jsonb),
      'capaFoco', case when s.cfg->>'capaFoco' ~ '^[0-9]+$'
                       then (s.cfg->>'capaFoco')::int end,
      'veu', case when s.cfg->>'veu' ~ '^[0-9]+$'
                  then (s.cfg->>'veu')::int end,
      'cartoes', s.cfg->>'cartoes',
      'moldura', coalesce(s.cfg->>'moldura', 'reta'),
      'loja', lower(btrim(coalesce(s.cfg->>'loja', 'true')))
                not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'usaServicos', lower(btrim(coalesce(s.cfg->>'usaServicos', 'true')))
                       not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'destaques', coalesce(s.cfg->'destaques', '[]'::jsonb),
      'passoHorarios', case
        when s.cfg->>'passoHorarios' in ('15','30','60')
          then (s.cfg->>'passoHorarios')::int else 15 end,
      'cores',     coalesce(s.cfg->'cores', '{}'::jsonb),
      'modo',      coalesce(s.cfg->>'modo', 'atual'),
      'logoForma', coalesce(s.cfg->>'logoForma', 'circular'),
      'logoBorda', coalesce(s.cfg->>'logoBorda', 'media'),
      'slideForma', coalesce(s.cfg->>'slideForma', 'panoramico'),
      'fitaMetal',  coalesce(s.cfg->>'fitaMetal', 'media'),
      'fitaBrilho', lower(btrim(coalesce(s.cfg->>'fitaBrilho', 'true')))
                      not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'fitaTempo',  coalesce(s.cfg->>'fitaTempo', 'media'),
      'fitaCor',    s.cfg->>'fitaCor',
      'fitaBorda',  coalesce(s.cfg->>'fitaBorda', 'reta'),
      'fundoTipo', coalesce(s.cfg->>'fundoTipo', 'cor'),
      'gradiente', s.cfg->>'gradiente'
    )
    || jsonb_build_object(
      'funcionamento', case when jsonb_typeof(s.cfg->'funcionamento') = 'object'
                            then s.cfg->'funcionamento' end,
      'pagamentos',    case when jsonb_typeof(s.cfg->'pagamentos') = 'object'
                            then s.cfg->'pagamentos' end,
      'sobre',     nullif(left(btrim(coalesce(s.cfg->>'sobre', '')), 600), ''),
      'instagram', nullif(left(regexp_replace(coalesce(s.cfg->>'instagram', ''),
                                              '[^A-Za-z0-9._]', '', 'g'), 30), '')
    ),
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', pr.id, 'nome', pr.nome, 'marca', pr.marca,
               'descricao', pr.descricao, 'foto', pr.foto,
               'preco', case when pr.preco_visivel then pr.preco else null end)
             order by pr.nome)
        from public.produtos pr
       where pr.salao_id = s.id and pr.ativo and pr.venda_online
         and lower(btrim(coalesce(s.cfg->>'loja', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb),
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'nome', v.nome, 'categoria', v.categoria,
               'descricao', v.descricao, 'duracaoMin', v.duracao_min,
               'preco', v.preco, 'foto', v.foto,
               'dias', case when v.dias is null or cardinality(v.dias) = 0
                            then null else to_jsonb(v.dias) end,
               'precoPorProf', (
                 select jsonb_object_agg(sp.profissional_id, sp.preco)
                   from public.servicos_profissionais sp
                   join public.profissionais p2 on p2.id = sp.profissional_id
                  where sp.servico_id = v.id and sp.preco is not null
                    and sp.preco <> v.preco and p2.ativo and p2.aceita_online),
               'regras', (
                 select jsonb_agg(jsonb_build_object(
                          'profissionalId', r.profissional_id, 'preco', r.preco,
                          'de', r.de, 'ate', r.ate,
                          'dias', case when r.dias is null
                                         or cardinality(r.dias) = 0
                                       then null else to_jsonb(r.dias) end,
                          'horaIni', r.hora_ini, 'horaFim', r.hora_fim)
                        order by (case when r.profissional_id is not null then 8 else 0 end)
                               + (case when r.dias is not null
                                        and cardinality(r.dias) > 0 then 4 else 0 end)
                               + (case when r.hora_ini is not null then 2 else 0 end)
                               + (case when r.de is not null or r.ate is not null
                                       then 1 else 0 end) desc,
                                 r.criado_em desc, r.id desc)
                   from public.precos_regras r
                  where r.servico_id = v.id and r.ativo
                    and (r.ate is null or r.ate >= public.hoje_no_salao(s.id))
                    and (r.de  is null or r.de  <= public.hoje_no_salao(s.id)
                                               + public.dias_liberados(s.id))),
               'precoMin', least(
                 v.preco,
                 (select min(r2.preco) from public.precos_regras r2
                   where r2.ativo and r2.servico_id = v.id
                     and (r2.de  is null or r2.de  <= public.hoje_no_salao(s.id)
                                                    + public.dias_liberados(s.id))
                     and (r2.ate is null or r2.ate >= public.hoje_no_salao(s.id))),
                 (select min(sp.preco) from public.servicos_profissionais sp
                   join public.profissionais p3 on p3.id = sp.profissional_id
                  where sp.servico_id = v.id and sp.preco is not null
                    and p3.ativo and p3.aceita_online)))
             order by v.categoria nulls last, v.nome)
        from public.servicos v
       where v.salao_id = s.id and v.ativo and v.aceita_online
         and lower(btrim(coalesce(s.cfg->>'usaServicos', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb),
    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'nome', coalesce(p.apelido, p.nome),
               'foto', p.foto,
               'servicos', (select coalesce(jsonb_agg(sp.servico_id), '[]'::jsonb)
                              from public.servicos_profissionais sp
                             where sp.profissional_id = p.id))
             order by p.criado_em, p.id)
        from public.profissionais p
       where p.salao_id = s.id and p.ativo and p.aceita_online
         and public.profissional_na_cota(p.id)), '[]'::jsonb)
  )
  from public.saloes s
  where s.slug = p_slug and s.status = 'ativo'
$$;

create or replace function public.porque_nao_agenda(
  p_profissional uuid, p_data date, p_servicos uuid[])
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_salao   uuid;
  v_hoje    date;
  v_jornada int;
  v_online  int;
  v_pedido  int;
  v_motivo  text;
begin
  if p_servicos is null or cardinality(p_servicos) = 0 then
    return 'Escolha pelo menos um serviço.';
  end if;
  select p.salao_id into v_salao
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional
     and p.ativo and p.aceita_online
     and sa.status = 'ativo';
  if v_salao is null then
    return 'Este profissional não está atendendo pela agenda online.';
  end if;
  if not public.profissional_na_cota(p_profissional) then
    return 'Este profissional não está atendendo pela agenda online.';
  end if;
  if not public.recurso_bool(v_salao, 'agenda_online') then
    return 'Este salão não está aceitando marcação pela internet.';
  end if;
  if exists (
    select 1 from unnest(p_servicos) as pedido(id)
     where not exists (
       select 1 from public.servicos s
        where s.id = pedido.id and s.salao_id = v_salao
          and s.ativo and s.aceita_online))
  then
    return 'Um dos serviços escolhidos não está disponível.';
  end if;
  if not public.profissional_faz(p_profissional, p_servicos) then
    return 'Este profissional não faz todos os serviços escolhidos.';
  end if;
  v_hoje := public.hoje_no_salao(v_salao);
  if p_data < v_hoje then
    return 'Essa data já passou.';
  end if;
  if p_data > v_hoje + public.dias_liberados(v_salao) then
    return format('A agenda está liberada até %s.',
                  to_char(v_hoje + public.dias_liberados(v_salao), 'DD/MM/YYYY'));
  end if;
  v_motivo := public.servico_fora_do_dia(p_servicos, p_data);
  if v_motivo is not null then
    return v_motivo;
  end if;
  v_jornada := public.minutos_de_jornada(p_profissional, p_data);
  if v_jornada > 0 then
    v_online := public.minutos_online_no_dia(p_profissional, p_data);
    v_pedido := public.duracao_dos_servicos(p_profissional, p_servicos);
    if (v_online + v_pedido) * 100 > v_jornada * public.teto_online_pct(v_salao) then
      return 'Este dia já está quase todo marcado. '
          || 'Chame o salão no WhatsApp que a gente encaixa você.';
    end if;
  end if;
  if public.rajada_online(v_salao) >= public.teto_online_rajada(v_salao) then
    return 'A marcação pela internet está congestionada agora. '
        || 'Tente daqui a pouco, ou chame o salão no WhatsApp.';
  end if;
  return null;
end $$;

create or replace function public.servico_fora_do_periodo(
  p_servicos uuid[], p_de date, p_ate date)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_dia date;
begin
  if p_servicos is null or cardinality(p_servicos) = 0
     or p_de is null or p_ate is null or p_ate < p_de then
    return null;
  end if;
  for v_dia in select d::date from generate_series(p_de, p_ate, interval '1 day') d
  loop
    if public.servico_fora_do_dia(p_servicos, v_dia) is null then
      return null;
    end if;
  end loop;
  return public.servico_fora_do_dia(p_servicos, p_de);
end $$;

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
  if v_tel_cli is not null
     and new.status = 'confirmado'
     and public.notif_liga(new.salao_id, 'notifConfirma', true) then
    v_corpo := public.texto_agendamento(new.id, 'confirmacao');
    if v_corpo is not null then
      insert into public.notificacoes
        (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo,
         chave, modelo, variaveis)
      values (new.salao_id, 'confirmacao', v_tel_cli, new.cliente_id, new.id,
              now(), v_corpo, 'confirmacao:' || new.id,
              public.modelo_de('confirmacao'),
              public.variaveis_agendamento(new.id, 'confirmacao'))
      on conflict (salao_id, chave) do nothing;
    end if;
  end if;
  v_min := public.lembrete_minutos(new.salao_id);
  if v_tel_cli is not null and new.status = 'confirmado' and v_min > 0 then
    v_quando := new.inicio - make_interval(mins => v_min);
    if v_quando > now() then
      v_corpo := public.texto_agendamento(new.id, 'lembrete');
      if v_corpo is not null then
        insert into public.notificacoes
          (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo,
           chave, modelo, variaveis)
        values (new.salao_id, 'lembrete', v_tel_cli, new.cliente_id, new.id,
                v_quando, v_corpo, 'lembrete:' || new.id,
                public.modelo_de('lembrete'),
                public.variaveis_agendamento(new.id, 'lembrete'))
        on conflict (salao_id, chave) do nothing;
      end if;
    end if;
  end if;
  select public.so_digitos(pr.telefone) into v_tel_prof
    from public.profissionais pr
   where pr.id = new.profissional_id and pr.notif_novo;
  if v_tel_prof is not null
     and public.notif_liga(new.salao_id, 'notifProfNovo', true) then
    v_corpo := public.texto_agendamento(new.id, 'novo');
    if v_corpo is not null then
      insert into public.notificacoes
        (salao_id, tipo, destino, profissional_id, agendamento_id, quando, corpo,
         chave, modelo, variaveis)
      values (new.salao_id, 'novo', v_tel_prof, new.profissional_id, new.id,
              now(), v_corpo, 'novo:' || new.id,
              public.modelo_de('novo'),
              public.variaveis_agendamento(new.id, 'novo'))
      on conflict (salao_id, chave) do nothing;
    end if;
  end if;
  return new;
end $$;

create or replace function public.travar_agenda(p_salao uuid)
returns void language sql set search_path = public as $$
  select pg_advisory_xact_lock(hashtext(p_salao::text))
$$;

create or replace function public.lembrete_minutos(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select case when public.notif_liga(p_salao, 'notifLembrete', true)
              then greatest(0, least(1440,
                     public.notif_num(p_salao, 'notifLembreteMin', 120)))
              else 0 end
$$;

create or replace function public.minutos_de_jornada(
  p_profissional uuid, p_data date)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(extract(epoch from (j.fim - j.inicio)) / 60), 0)::int
    from public.jornada_costurada(p_profissional, p_data) j
$$;

create or replace function public.minutos_online_no_dia(
  p_profissional uuid, p_data date)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(
           extract(epoch from (a.fim - a.inicio)) / 60), 0)::int
    from public.agendamentos a
    join public.profissionais p on p.id = a.profissional_id
    join public.saloes s        on s.id = p.salao_id
   where a.profissional_id = p_profissional
     and a.origem = 'online'
     and a.arquivado_em is null
     and a.status in ('pendente','confirmado','em_atendimento','concluido')
     and (a.inicio at time zone coalesce(s.fuso, 'America/Sao_Paulo'))::date = p_data
$$;

create or replace function public.modelo_de(p_tipo text)
returns text language sql immutable set search_path = public as $$
  select case p_tipo
    when 'confirmacao' then 'agendapro_confirmacao'
    when 'lembrete'    then 'agendapro_lembrete'
    when 'novo'        then 'agendapro_novo'
    when 'resumo'      then 'agendapro_resumo'
  end
$$;

create or replace function public.notif_liga(p_salao uuid, p_chave text,
                                             p_padrao boolean default true)
returns boolean language sql stable set search_path = public as $$
  select coalesce(
    (select (cfg->>p_chave)::boolean from public.saloes
      where id = p_salao and cfg->>p_chave in ('true','false')),
    p_padrao)
$$;

create or replace function public.rajada_online(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int
    from public.agendamentos a
    join public.clientes c on c.id = a.cliente_id
   where a.salao_id = p_salao
     and a.origem = 'online'
     and a.criado_em > now() - interval '10 minutes'
     and c.criado_em > now() - interval '24 hours'
$$;

create or replace function public.servico_fora_do_dia(
  p_servicos uuid[], p_data date)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_dia   smallint;
  v_nome  text;
  v_dias  smallint[];
begin
  if p_servicos is null or cardinality(p_servicos) = 0 or p_data is null then
    return null;
  end if;
  v_dia := extract(dow from p_data)::smallint;
  select s.nome, s.dias into v_nome, v_dias
    from public.servicos s
   where s.id = any(p_servicos)
     and s.dias is not null
     and cardinality(s.dias) > 0
     and not (v_dia = any(s.dias))
   order by s.nome
   limit 1;
  if v_nome is null then return null; end if;
  return format(
    '%s: só %s. Escolha um desses dias, tire este serviço do pedido, '
    || 'ou chame o salão no WhatsApp.',
    v_nome, public.dias_por_extenso(v_dias));
end $$;

create or replace function public.teto_online_pct(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select greatest(10, least(100,
    coalesce((select (cfg->>'tetoOnlinePct')::int from public.saloes
               where id = p_salao and cfg->>'tetoOnlinePct' ~ '^[0-9]+$'), 70)))
$$;

create or replace function public.teto_online_rajada(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select greatest(1, least(100,
    coalesce((select (cfg->>'tetoOnlineRajada')::int from public.saloes
               where id = p_salao and cfg->>'tetoOnlineRajada' ~ '^[0-9]+$'), 10)))
$$;

create or replace function public.texto_agendamento(
  p_agendamento uuid, p_tipo text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  j jsonb;
  v_casa text; v_cli text; v_prof text; v_serv text;
  v_data text; v_hora text;
begin
  j := public.pecas_agendamento(p_agendamento);
  if j is null then return null; end if;
  v_cli  := j->>'cliente';  v_prof := j->>'prof';
  v_serv := j->>'servico';  v_casa := j->>'casa';
  v_data := j->>'data';     v_hora := j->>'hora';
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

create or replace function public.variaveis_agendamento(
  p_agendamento uuid, p_tipo text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j jsonb;
begin
  j := public.pecas_agendamento(p_agendamento);
  if j is null then return null; end if;
  if p_tipo in ('confirmacao','lembrete') then
    return jsonb_build_array(
      public.variavel_limpa(j->>'primeiro'), public.variavel_limpa(j->>'data'),
      public.variavel_limpa(j->>'hora'),     public.variavel_limpa(j->>'servico'),
      public.variavel_limpa(j->>'prof'));
  elsif p_tipo = 'novo' then
    return jsonb_build_array(
      public.variavel_limpa(j->>'cliente'), public.variavel_limpa(j->>'servico'),
      public.variavel_limpa(j->>'data'),    public.variavel_limpa(j->>'hora'));
  end if;
  return null;
end $$;

create or replace function public.notif_num(p_salao uuid, p_chave text,
                                            p_padrao int)
returns int language sql stable set search_path = public as $$
  select coalesce(
    (select (cfg->>p_chave)::int from public.saloes
      where id = p_salao and cfg->>p_chave ~ '^[0-9]+$'),
    p_padrao)
$$;

create or replace function public.pecas_agendamento(p_agendamento uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  a public.agendamentos%rowtype;
  v_fuso text; v_casa text; v_cli text; v_prof text; v_serv text;
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
  return jsonb_build_object(
    'cliente',  coalesce(v_cli, 'cliente'),
    'primeiro', split_part(coalesce(v_cli, 'cliente'), ' ', 1),
    'prof',     coalesce(v_prof, '—'),
    'servico',  coalesce(v_serv, 'atendimento'),
    'casa',     coalesce(v_casa, '—'),
    'data',     to_char(a.inicio at time zone v_fuso, 'DD/MM/YYYY'),
    'hora',     to_char(a.inicio at time zone v_fuso, 'HH24:MI'));
end $$;

create or replace function public.variavel_limpa(p_texto text, p_teto int default 900)
returns text language sql immutable set search_path = public as $$
  select case
    when t = '' then '—'
    when length(t) > p_teto then left(t, p_teto - 1) || '…'
    else t
  end
  from (select btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')) as t) x
$$;
