create or replace function public.tem_acesso(p_salao uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(is_super() or papel_no_salao(p_salao) is not null, false)
$$;

create or replace function public.e_equipe(p_salao uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(is_super()
      or papel_no_salao(p_salao) in ('dono','admin','recepcao','profissional'), false)
$$;

create or replace function public.e_gestor(p_salao uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(is_super() or papel_no_salao(p_salao) in ('dono','admin'), false)
$$;

create or replace function public.ve_agenda_toda(p_salao uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(is_super() or papel_no_salao(p_salao) in ('dono','admin','recepcao'), false)
$$;

create or replace function public.comanda_numera()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.numero is null then
    new.numero := public.proximo_numero(new.salao_id, 'comanda');
  end if;
  return new;
end $$;

revoke all on function public.proximo_numero(uuid, text)
  from public, anon, authenticated;

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
      'precoNaCapa', coalesce((s.cfg->>'precoNaCapa')::boolean, false),
      'fundo', s.cfg->>'fundo',
      'brilho', coalesce((s.cfg->>'brilho')::boolean, true),
      'letra', s.cfg->>'letra',
      'slideDe', s.cfg->>'slideDe',
      'galeria', coalesce(s.cfg->'galeria', '[]'::jsonb),
      'capaFoco', (s.cfg->>'capaFoco')::int,
      'veu', (s.cfg->>'veu')::int,
      'cartoes', s.cfg->>'cartoes'
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

alter table public.clientes
  add column if not exists aceita_marketing boolean not null default true;
alter table public.clientes
  add column if not exists marketing_saiu_em timestamptz;
create table if not exists public.campanhas (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  nome          text not null check (length(btrim(nome)) between 2 and 120),
  tipo          text not null default 'promocao'
                check (tipo in ('promocao','lembrete','confirmacao','aniversario',
                                'ausente','retorno','aviso','personalizada')),
  corpo         text,
  template_nome text,
  template_idioma text not null default 'pt_BR',
  status        text not null default 'rascunho'
                check (status in ('rascunho','agendada','processando','concluida',
                                  'cancelada','concluida_com_falhas')),
  agendada_para timestamptz,
  intervalo_min int not null default 5  check (intervalo_min between 3 and 300),
  intervalo_max int not null default 12 check (intervalo_max between 3 and 600),
  check (intervalo_max >= intervalo_min),
  iniciada_em   timestamptz,
  concluida_em  timestamptz,
  criada_por    uuid references public.perfis(id) on delete set null,
  criada_em     timestamptz not null default now(),
  check (coalesce(nullif(btrim(template_nome), ''), nullif(btrim(corpo), '')) is not null)
);
create index if not exists ix_camp_salao on public.campanhas(salao_id, criada_em desc);
create index if not exists ix_camp_rodando on public.campanhas(status)
  where status = 'processando';
create table if not exists public.campanha_destinatarios (
  id            uuid primary key default gen_random_uuid(),
  campanha_id   uuid not null references public.campanhas(id) on delete cascade,
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  cliente_id    uuid not null references public.clientes(id) on delete cascade,
  telefone      text not null,
  status        text not null default 'pendente'
                check (status in ('pendente','processando','enviado','falhou','cancelado')),
  tentativas    smallint not null default 0 check (tentativas >= 0),
  proxima_em    timestamptz,
  tentado_em    timestamptz,
  enviado_em    timestamptz,
  erro_codigo   text,
  erro_msg      text,
  wam_id        text,
  criado_em     timestamptz not null default now(),
  constraint ux_camp_dest unique (campanha_id, cliente_id)
);
create index if not exists ix_dest_camp on public.campanha_destinatarios(campanha_id, status);
create index if not exists ix_dest_fila
  on public.campanha_destinatarios(campanha_id, criado_em)
  where status = 'pendente';
alter table public.campanhas               enable row level security;
alter table public.campanha_destinatarios  enable row level security;
alter table public.campanhas               force row level security;
alter table public.campanha_destinatarios  force row level security;
drop policy if exists camp_ler    on public.campanhas;
drop policy if exists camp_gerir  on public.campanhas;
drop policy if exists dest_ler    on public.campanha_destinatarios;
drop policy if exists dest_gerir  on public.campanha_destinatarios;
create policy camp_ler on public.campanhas
  for select using ( public.e_equipe(salao_id) );
create policy camp_gerir on public.campanhas
  for all using ( public.e_gestor(salao_id) )
       with check ( public.e_gestor(salao_id) );
create policy dest_ler on public.campanha_destinatarios
  for select using ( public.e_equipe(salao_id) );
create policy dest_gerir on public.campanha_destinatarios
  for all using ( public.e_gestor(salao_id) )
       with check ( public.e_gestor(salao_id) );
revoke all on public.campanhas              from anon;
revoke all on public.campanha_destinatarios from anon;
grant select, insert, update, delete on public.campanhas              to authenticated;
grant select, insert, update, delete on public.campanha_destinatarios to authenticated;
create or replace function public.publico_da_campanha(
  p_salao   uuid,
  p_tipo    text default 'promocao',
  p_criterio text default 'todos',
  p_dias    int  default 90,
  p_ids     uuid[] default null)
returns table (cliente_id uuid, nome text, telefone text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  return query
  select c.id, c.nome, c.telefone
    from public.clientes c
   where c.salao_id = p_salao
     and public.so_digitos(c.telefone) is not null
     and (p_tipo <> 'promocao' or c.aceita_marketing)
     and case p_criterio
           when 'selecionados' then c.id = any(coalesce(p_ids, '{}'::uuid[]))
           when 'sumidos' then not exists (
             select 1 from public.agendamentos a
              where a.cliente_id = c.id
                and a.arquivado_em is null
                and a.status = 'concluido'
                and a.inicio > now() - make_interval(days => greatest(p_dias, 1)))
           when 'aniversario' then
             c.nascimento is not null
             and to_char(c.nascimento, 'MM-DD')
               = to_char(public.hoje_no_salao(p_salao), 'MM-DD')
           when 'faltaram' then exists (
             select 1 from public.agendamentos a
              where a.cliente_id = c.id
                and a.arquivado_em is null
                and a.status = 'faltou'
                and a.inicio > now() - make_interval(days => greatest(p_dias, 1)))
           else true
         end
   order by c.nome;
end $$;
revoke all on function public.publico_da_campanha(uuid, text, text, int, uuid[]) from public;
grant execute on function public.publico_da_campanha(uuid, text, text, int, uuid[])
  to authenticated;
create or replace function public.montar_fila(
  p_campanha uuid,
  p_criterio text default 'todos',
  p_dias     int  default 90,
  p_ids      uuid[] default null)
returns int
language plpgsql security definer set search_path = public as $$
declare
  c public.campanhas%rowtype;
  n int;
begin
  select * into c from public.campanhas where id = p_campanha;
  if c.id is null or not public.e_gestor(c.salao_id) then
    raise exception 'Campanha não encontrada.' using errcode = 'insufficient_privilege';
  end if;
  if c.status <> 'rascunho' then
    raise exception 'Esta campanha já saiu do rascunho.' using errcode = 'check_violation';
  end if;
  insert into public.campanha_destinatarios (campanha_id, salao_id, cliente_id, telefone)
  select c.id, c.salao_id, p.cliente_id, public.so_digitos(p.telefone)
    from public.publico_da_campanha(c.salao_id, c.tipo, p_criterio, p_dias, p_ids) p
  on conflict (campanha_id, cliente_id) do nothing;
  select count(*) into n from public.campanha_destinatarios where campanha_id = c.id;
  return n;
end $$;
revoke all on function public.montar_fila(uuid, text, int, uuid[]) from public;
grant execute on function public.montar_fila(uuid, text, int, uuid[]) to authenticated;
create or replace function public.iniciar_campanha(p_campanha uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.campanhas%rowtype;
  n int;
begin
  select * into c from public.campanhas where id = p_campanha;
  if c.id is null or not public.e_gestor(c.salao_id) then
    raise exception 'Campanha não encontrada.' using errcode = 'insufficient_privilege';
  end if;
  if c.status not in ('rascunho','agendada') then
    raise exception 'Esta campanha já foi iniciada.' using errcode = 'check_violation';
  end if;
  select count(*) into n from public.campanha_destinatarios
   where campanha_id = c.id and status = 'pendente';
  if n = 0 then
    raise exception 'Nenhum destinatário na fila.' using errcode = 'check_violation';
  end if;
  update public.campanhas
     set status = 'processando', iniciada_em = now()
   where id = c.id;
  return jsonb_build_object('ok', true, 'pendentes', n);
end $$;
create or replace function public.cancelar_campanha(p_campanha uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.campanhas%rowtype;
  n int;
begin
  select * into c from public.campanhas where id = p_campanha;
  if c.id is null or not public.e_gestor(c.salao_id) then
    raise exception 'Campanha não encontrada.' using errcode = 'insufficient_privilege';
  end if;
  if c.status in ('concluida','concluida_com_falhas','cancelada') then
    raise exception 'Esta campanha já terminou.' using errcode = 'check_violation';
  end if;
  update public.campanha_destinatarios
     set status = 'cancelado'
   where campanha_id = c.id and status = 'pendente';
  get diagnostics n = row_count;
  update public.campanhas
     set status = 'cancelada', concluida_em = now()
   where id = c.id;
  return jsonb_build_object('ok', true, 'cancelados', n);
end $$;
revoke all on function public.iniciar_campanha(uuid)  from public;
revoke all on function public.cancelar_campanha(uuid) from public;
grant execute on function public.iniciar_campanha(uuid)  to authenticated;
grant execute on function public.cancelar_campanha(uuid) to authenticated;
create or replace function public.placar_campanha(p_campanha uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.campanhas%rowtype;
begin
  select * into c from public.campanhas where id = p_campanha;
  if c.id is null or not public.e_equipe(c.salao_id) then
    raise exception 'Campanha não encontrada.' using errcode = 'insufficient_privilege';
  end if;
  return (
    select jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'status', c.status, 'tipo', c.tipo,
      'iniciadaEm', c.iniciada_em, 'concluidaEm', c.concluida_em,
      'corpo', c.corpo, 'template', c.template_nome,
      'total',      count(*),
      'enviadas',   count(*) filter (where d.status = 'enviado'),
      'falhas',     count(*) filter (where d.status = 'falhou'),
      'pendentes',  count(*) filter (where d.status in ('pendente','processando')),
      'cancelados', count(*) filter (where d.status = 'cancelado'),
      'ultimoEnvio', max(d.enviado_em))
      from public.campanha_destinatarios d where d.campanha_id = c.id);
end $$;
revoke all on function public.placar_campanha(uuid) from public;
grant execute on function public.placar_campanha(uuid) to authenticated;
create or replace function public.fila_proxima(p_lote int default 1)
returns table (
  destinatario_id uuid, campanha_id uuid, telefone text,
  nome text, salao text, corpo text, template_nome text, template_idioma text,
  tentativas smallint, intervalo_min int, intervalo_max int)
language plpgsql security definer set search_path = public as $$
begin
  return query
  with alvo as (
    select d.id
      from public.campanha_destinatarios d
      join public.campanhas c on c.id = d.campanha_id
     where d.status = 'pendente'
       and c.status = 'processando'
       and (d.proxima_em is null or d.proxima_em <= now())
     order by d.criado_em
     for update of d skip locked
     limit greatest(coalesce(p_lote, 1), 1)
  ),
  tomados as (
    update public.campanha_destinatarios d
       set status = 'processando',
           tentativas = d.tentativas + 1,
           tentado_em = now()
      from alvo a
     where d.id = a.id
     returning d.*
  )
  select t.id, t.campanha_id, t.telefone,
         cl.nome, s.nome, c.corpo, c.template_nome, c.template_idioma,
         t.tentativas, c.intervalo_min, c.intervalo_max
    from tomados t
    join public.campanhas c  on c.id  = t.campanha_id
    join public.clientes  cl on cl.id = t.cliente_id
    join public.saloes    s  on s.id  = t.salao_id;
end $$;
create or replace function public.fila_resultado(
  p_destinatario uuid,
  p_ok           boolean,
  p_wam_id       text default null,
  p_erro_codigo  text default null,
  p_erro_msg     text default null,
  p_permanente   boolean default false)
returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.campanha_destinatarios%rowtype;
begin
  select * into d from public.campanha_destinatarios where id = p_destinatario;
  if d.id is null then return; end if;
  if p_ok then
    update public.campanha_destinatarios
       set status = 'enviado', enviado_em = now(), wam_id = p_wam_id,
           erro_codigo = null, erro_msg = null, proxima_em = null
     where id = d.id;
  elsif p_permanente or d.tentativas >= 3 then
    update public.campanha_destinatarios
       set status = 'falhou', erro_codigo = p_erro_codigo,
           erro_msg = left(coalesce(p_erro_msg, ''), 500), proxima_em = null
     where id = d.id;
  else
    update public.campanha_destinatarios
       set status = 'pendente', erro_codigo = p_erro_codigo,
           erro_msg = left(coalesce(p_erro_msg, ''), 500),
           proxima_em = now() + make_interval(secs => 30 * power(4, d.tentativas - 1))
     where id = d.id;
  end if;
  update public.campanhas c
     set status = case
           when exists (select 1 from public.campanha_destinatarios x
                         where x.campanha_id = c.id and x.status = 'falhou')
             then 'concluida_com_falhas' else 'concluida' end,
         concluida_em = now()
   where c.id = d.campanha_id
     and c.status = 'processando'
     and not exists (select 1 from public.campanha_destinatarios x
                      where x.campanha_id = c.id
                        and x.status in ('pendente','processando'));
end $$;
revoke all on function public.fila_proxima(int) from public;
revoke all on function public.fila_resultado(uuid, boolean, text, text, text, boolean)
  from public;
grant execute on function public.fila_proxima(int) to service_role;
grant execute on function public.fila_resultado(uuid, boolean, text, text, text, boolean)
  to service_role;

create table if not exists public.convites_equipe (
  id         uuid primary key default gen_random_uuid(),
  salao_id   uuid not null references public.saloes(id) on delete cascade,
  papel      text not null check (papel in ('admin','recepcao','profissional')),
  para_quem  text,
  profissional_id uuid references public.profissionais(id) on delete cascade,
  token      uuid not null default gen_random_uuid(),
  expira_em  timestamptz not null default now() + interval '7 days',
  usado_em   timestamptz,
  usado_por  uuid references public.perfis(id) on delete set null,
  revogado_em timestamptz,
  criado_por uuid references public.perfis(id) on delete set null,
  criado_em  timestamptz not null default now()
);
alter table public.convites_equipe
  add column if not exists profissional_id uuid
  references public.profissionais(id) on delete cascade;
create unique index if not exists ux_convite_token on public.convites_equipe(token);
create index if not exists ix_convite_salao on public.convites_equipe(salao_id, criado_em desc);
alter table public.convites_equipe enable row level security;
alter table public.convites_equipe force row level security;
drop policy if exists conv_gerir on public.convites_equipe;
create policy conv_gerir on public.convites_equipe for all to authenticated
  using ( public.e_gestor(salao_id) ) with check ( public.e_gestor(salao_id) );
revoke all on public.convites_equipe from anon;
grant select, insert, update, delete on public.convites_equipe to authenticated;
drop function if exists public.criar_convite(uuid, text, text);
create or replace function public.criar_convite(
  p_salao uuid, p_papel text, p_para_quem text default null,
  p_profissional uuid default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_token uuid;
  pr public.profissionais%rowtype;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Só quem administra o salão pode convidar.'
      using errcode = 'insufficient_privilege';
  end if;
  if p_papel not in ('admin','recepcao','profissional') then
    raise exception 'Papel inválido para convite.' using errcode = 'check_violation';
  end if;
  if p_papel = 'profissional' then
    if p_profissional is null then
      raise exception 'Escolha de quem é a agenda. Cadastre a pessoa em Equipe antes de dar o login.'
        using errcode = 'check_violation';
    end if;
    select * into pr from public.profissionais where id = p_profissional;
    if pr.id is null or pr.salao_id <> p_salao then
      raise exception 'Esta agenda não é deste salão.' using errcode = 'check_violation';
    end if;
    if pr.perfil_id is not null then
      raise exception 'A agenda de % já tem login.', pr.nome
        using errcode = 'check_violation';
    end if;
  else
    p_profissional := null;
  end if;
  insert into public.convites_equipe
         (salao_id, papel, para_quem, profissional_id, criado_por)
       values (p_salao, p_papel,
               nullif(btrim(coalesce(p_para_quem, '')), ''),
               p_profissional, auth.uid())
    returning token into v_token;
  return jsonb_build_object('token', v_token);
end $$;
create or replace function public.ver_convite(p_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.convites_equipe%rowtype;
  s public.saloes%rowtype;
begin
  select * into c from public.convites_equipe where token = p_token;
  if c.id is null
     or c.usado_em is not null
     or c.revogado_em is not null
     or c.expira_em < now() then
    return jsonb_build_object('valido', false);
  end if;
  select * into s from public.saloes where id = c.salao_id;
  if s.id is null or s.status <> 'ativo' then
    return jsonb_build_object('valido', false);
  end if;
  return jsonb_build_object(
    'valido', true,
    'salao',  s.nome,
    'tipo',   s.tipo,
    'logo',   s.logo,
    'papel',  c.papel,
    'paraQuem', c.para_quem);
end $$;
create or replace function public.aceitar_convite(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.convites_equipe%rowtype;
  v_eu uuid := auth.uid();
begin
  if v_eu is null then
    raise exception 'Entre na sua conta para aceitar o convite.'
      using errcode = 'insufficient_privilege';
  end if;
  select * into c from public.convites_equipe where token = p_token for update;
  if c.id is null
     or c.usado_em is not null
     or c.revogado_em is not null
     or c.expira_em < now() then
    raise exception 'Este convite não vale mais. Peça outro ao salão.'
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.vinculos v
              where v.perfil_id = v_eu and v.salao_id = c.salao_id
                and v.papel = c.papel and v.status = 'ativo') then
    return jsonb_build_object('ok', true, 'jaEra', true, 'salaoId', c.salao_id);
  end if;
  insert into public.vinculos (perfil_id, salao_id, papel, status)
       values (v_eu, c.salao_id, c.papel, 'ativo')
  on conflict (perfil_id, salao_id, papel)
    do update set status = 'ativo';
  if c.papel = 'profissional' and c.profissional_id is not null then
    update public.profissionais
       set perfil_id = v_eu
     where id = c.profissional_id and salao_id = c.salao_id
       and perfil_id is null;
  end if;
  update public.convites_equipe
     set usado_em = now(), usado_por = v_eu
   where id = c.id;
  return jsonb_build_object('ok', true, 'salaoId', c.salao_id, 'papel', c.papel);
end $$;
create or replace function public.equipe_com_acesso(p_salao uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'perfilId', p.id,
             'nome',     p.nome,
             'papel',    v.papel,
             'desde',    v.criado_em,
             'souEu',    p.id = auth.uid())
           order by array_position(
             array['dono','admin','recepcao','profissional'], v.papel), p.nome)
      from public.vinculos v
      join public.perfis p on p.id = v.perfil_id
     where v.salao_id = p_salao
       and v.status = 'ativo'
       and v.papel <> 'cliente'), '[]'::jsonb);
end $$;
create or replace function public.remover_acesso(
  p_salao uuid, p_perfil uuid, p_papel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_donos int;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Só quem administra o salão pode mexer nos acessos.'
      using errcode = 'insufficient_privilege';
  end if;
  if p_papel = 'dono' then
    if p_perfil = auth.uid() then
      raise exception 'Você não pode tirar o próprio acesso de dono.'
        using errcode = 'check_violation';
    end if;
    select count(*) into v_donos from public.vinculos
     where salao_id = p_salao and papel = 'dono' and status = 'ativo';
    if v_donos <= 1 then
      raise exception 'Este é o único dono do salão. Passe a titularidade antes.'
        using errcode = 'check_violation';
    end if;
  end if;
  delete from public.vinculos
   where salao_id = p_salao and perfil_id = p_perfil and papel = p_papel;
  return jsonb_build_object('ok', true);
end $$;
create or replace function public.revogar_convite(p_convite uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.convites_equipe%rowtype;
begin
  select * into c from public.convites_equipe where id = p_convite;
  if c.id is null or not public.e_gestor(c.salao_id) then
    raise exception 'Convite não encontrado.' using errcode = 'insufficient_privilege';
  end if;
  update public.convites_equipe set revogado_em = now()
   where id = c.id and usado_em is null and revogado_em is null;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.criar_convite(uuid, text, text, uuid) from public;
revoke all on function public.ver_convite(uuid)                 from public;
revoke all on function public.aceitar_convite(uuid)             from public;
revoke all on function public.equipe_com_acesso(uuid)           from public;
revoke all on function public.remover_acesso(uuid, uuid, text)  from public;
revoke all on function public.revogar_convite(uuid)             from public;
grant execute on function public.criar_convite(uuid, text, text, uuid) to authenticated;
grant execute on function public.ver_convite(uuid)                to anon, authenticated;
grant execute on function public.aceitar_convite(uuid)            to authenticated;
grant execute on function public.equipe_com_acesso(uuid)          to authenticated;
grant execute on function public.remover_acesso(uuid, uuid, text) to authenticated;
grant execute on function public.revogar_convite(uuid)            to authenticated;

create or replace function public.relatorio(
  p_salao uuid, p_de date, p_ate date)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso  text;
  v_ini   timestamptz;
  v_fim   timestamptz;
  v_dias  int;
  v_ini_a timestamptz;
  v_fim_a timestamptz;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  if p_de is null or p_ate is null or p_ate < p_de then
    raise exception 'Confira as datas do período.' using errcode = 'check_violation';
  end if;
  select fuso into v_fuso from public.saloes where id = p_salao;
  v_fuso := coalesce(v_fuso, 'America/Sao_Paulo');
  v_ini := (p_de::timestamp) at time zone v_fuso;
  v_fim := ((p_ate + 1)::timestamp) at time zone v_fuso;
  v_dias  := (p_ate - p_de) + 1;
  v_fim_a := v_ini;
  v_ini_a := v_ini - make_interval(days => v_dias);
  return jsonb_build_object(
    'de',  p_de,
    'ate', p_ate,
    'dias', v_dias,
    'faturamento', coalesce((
      select round(sum(t.total), 2) from public.comandas_totais t
        join public.comandas c on c.id = t.id
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini and c.fechada_em < v_fim), 0),
    'atendimentos', (
      select count(*) from public.comandas c
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini and c.fechada_em < v_fim),
    'descontos', coalesce((
      select round(sum(c.desconto), 2) from public.comandas c
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini and c.fechada_em < v_fim), 0),
    'faturamentoAntes', coalesce((
      select round(sum(t.total), 2) from public.comandas_totais t
        join public.comandas c on c.id = t.id
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini_a and c.fechada_em < v_fim_a), 0),
    'formas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'forma', f.forma, 'valor', f.valor, 'taxa', f.taxa)
             order by f.valor desc)
        from (select pg.forma,
                     round(sum(pg.valor), 2) as valor,
                     round(sum(pg.taxa), 2)  as taxa
                from public.pagamentos pg
                join public.comandas c on c.id = pg.comanda_id
               where c.salao_id = p_salao and c.status = 'fechada'
                 and c.fechada_em >= v_ini and c.fechada_em < v_fim
               group by pg.forma) f), '[]'::jsonb),
    'comissoes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'profissionalId', x.pid, 'nome', x.nome,
               'vendido', x.vendido, 'comissao', x.comissao,
               'itens', x.itens)
             order by x.comissao desc)
        from (select i.profissional_id as pid,
                     coalesce(pr.apelido, pr.nome, 'sem profissional') as nome,
                     round(sum(i.total), 2)          as vendido,
                     round(sum(i.comissao_valor), 2) as comissao,
                     count(*)                        as itens
                from public.comanda_itens_calculados i
                join public.comandas c on c.id = i.comanda_id
                left join public.profissionais pr on pr.id = i.profissional_id
               where c.salao_id = p_salao and c.status = 'fechada'
                 and c.fechada_em >= v_ini and c.fechada_em < v_fim
               group by i.profissional_id, coalesce(pr.apelido, pr.nome, 'sem profissional')) x),
      '[]'::jsonb),
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nome', y.nome, 'qtd', y.qtd, 'valor', y.valor)
             order by y.valor desc)
        from (select i.descricao as nome,
                     round(sum(i.qtd), 2)   as qtd,
                     round(sum(i.total), 2) as valor
                from public.comanda_itens i
                join public.comandas c on c.id = i.comanda_id
               where c.salao_id = p_salao and c.status = 'fechada'
                 and c.fechada_em >= v_ini and c.fechada_em < v_fim
               group by i.descricao
               order by 3 desc limit 12) y), '[]'::jsonb),
    'agenda', (
      select jsonb_build_object(
        'concluidos', count(*) filter (where a.status = 'concluido'),
        'faltas',     count(*) filter (where a.status = 'faltou'),
        'cancelados', count(*) filter (where a.status = 'cancelado'),
        'marcados',   count(*),
        'perdido', coalesce(round(sum(a.valor_previsto)
                     filter (where a.status in ('faltou','cancelado')), 2), 0))
        from public.agendamentos a
       where a.salao_id = p_salao
         and a.arquivado_em is null
         and a.inicio >= v_ini and a.inicio < v_fim),
    'clientes', (
      select jsonb_build_object(
        'atendidas', count(distinct c.cliente_id),
        'novas', count(distinct c.cliente_id) filter (
          where not exists (
            select 1 from public.comandas c2
             where c2.cliente_id = c.cliente_id
               and c2.salao_id = p_salao
               and c2.status = 'fechada'
               and c2.fechada_em < v_ini)))
        from public.comandas c
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini and c.fechada_em < v_fim)
  );
end $$;
revoke all on function public.relatorio(uuid, date, date) from public;
grant execute on function public.relatorio(uuid, date, date) to authenticated;

create table if not exists public.cobrancas (
  id          uuid primary key default gen_random_uuid(),
  salao_id    uuid not null references public.saloes(id) on delete cascade,
  plano       text not null references public.planos(codigo),
  valor       numeric(10,2) not null check (valor > 0),
  metodo      text not null check (metodo in ('pix','boleto')),
  status      text not null default 'pendente'
              check (status in ('pendente','paga','vencida','cancelada','devolvida')),
  vence_em    timestamptz not null,
  criada_em   timestamptz not null default now(),
  paga_em     timestamptz,
  mp_id       text unique,
  mp_status   text,
  pix_copia_cola text,
  pix_qr_base64  text,
  boleto_url     text,
  linha_digitavel text,
  aberta_por  uuid references public.perfis(id) on delete set null
);
create index if not exists ix_cobranca_salao
  on public.cobrancas(salao_id, criada_em desc);
create unique index if not exists ux_cobranca_aberta
  on public.cobrancas(salao_id) where (status = 'pendente');
alter table public.cobrancas enable row level security;
drop policy if exists cobranca_ler on public.cobrancas;
create policy cobranca_ler on public.cobrancas for select to authenticated
  using ( e_gestor(salao_id) );
drop policy if exists cobranca_gerir on public.cobrancas;
create policy cobranca_gerir on public.cobrancas for all to authenticated
  using ( is_super() ) with check ( is_super() );
revoke all on public.cobrancas from anon, authenticated;
grant select on public.cobrancas to authenticated;
create or replace function public.abrir_cobranca(
  p_salao uuid, p_plano text, p_metodo text, p_quem uuid)
returns public.cobrancas
language plpgsql security definer set search_path = public as $$
declare
  v_preco numeric(10,2);
  v_dias  int;
  v_ja    public.cobrancas;
  v_nova  public.cobrancas;
begin
  if p_quem is null then
    raise exception 'Cobrança sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  if p_metodo not in ('pix','boleto') then
    raise exception 'Forma de pagamento desconhecida.' using errcode = 'check_violation';
  end if;
  select preco_mes into v_preco from public.planos where codigo = p_plano;
  if v_preco is null then
    raise exception 'Plano não encontrado.' using errcode = 'check_violation';
  end if;
  if v_preco <= 0 then
    raise exception 'Este plano não é pago.' using errcode = 'check_violation';
  end if;
  select * into v_ja from public.cobrancas
   where salao_id = p_salao and status = 'pendente'
   for update;
  if found then
    if v_ja.plano = p_plano and v_ja.metodo = p_metodo and v_ja.vence_em > now() then
      return v_ja;
    end if;
    update public.cobrancas set status = 'cancelada' where id = v_ja.id;
  end if;
  v_dias := case when p_metodo = 'boleto' then 3 else 1 end;
  insert into public.cobrancas (salao_id, plano, valor, metodo, vence_em, aberta_por)
  values (p_salao, p_plano, v_preco, p_metodo,
          now() + make_interval(days => v_dias), p_quem)
  returning * into v_nova;
  return v_nova;
end $$;
create or replace function public.anotar_cobranca(
  p_id uuid, p_mp_id text, p_mp_status text,
  p_pix text default null, p_qr text default null,
  p_boleto text default null, p_linha text default null)
returns void
language sql security definer set search_path = public as $$
  update public.cobrancas
     set mp_id = p_mp_id, mp_status = p_mp_status,
         pix_copia_cola = coalesce(p_pix, pix_copia_cola),
         pix_qr_base64  = coalesce(p_qr, pix_qr_base64),
         boleto_url     = coalesce(p_boleto, boleto_url),
         linha_digitavel = coalesce(p_linha, linha_digitavel)
   where id = p_id;
$$;
create or replace function public.dados_do_pagador(p_salao uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'nome',      coalesce(pf.nome, s.nome),
    'email',     pf.email,
    'documento', d.documento,
    'salao',     s.nome)
    from public.saloes s
    left join public.documentos_cobranca d on d.salao_id = s.id
    left join lateral (
      select p.nome, p.email
        from public.vinculos v
        join public.perfis p on p.id = v.perfil_id
       where v.salao_id = s.id and v.status = 'ativo' and v.papel = 'dono'
       order by v.criado_em limit 1) pf on true
   where s.id = p_salao;
$$;
revoke all on function public.dados_do_pagador(uuid) from public, anon, authenticated;
create or replace function public.registrar_pagamento(
  p_mp_id text, p_valor numeric, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c public.cobrancas;
  v_base date;
begin
  select * into c from public.cobrancas
   where mp_id = p_mp_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'cobranca_desconhecida');
  end if;
  if c.status = 'paga' then
    return jsonb_build_object('ok', true, 'motivo', 'ja_registrada');
  end if;
  if p_status <> 'approved' then
    update public.cobrancas set mp_status = p_status where id = c.id;
    return jsonb_build_object('ok', true, 'motivo', 'nao_aprovado');
  end if;
  if p_valor is distinct from c.valor then
    update public.cobrancas
       set mp_status = 'valor_divergente:' || coalesce(p_valor::text, 'null')
     where id = c.id;
    return jsonb_build_object('ok', false, 'motivo', 'valor_divergente');
  end if;
  update public.cobrancas
     set status = 'paga', paga_em = now(), mp_status = p_status
   where id = c.id;
  select greatest(coalesce(a.vence_em, current_date), current_date)
    into v_base
    from public.assinaturas a where a.salao_id = c.salao_id;
  update public.assinaturas
     set plano = c.plano,
         status = 'ativa',
         trial_ate = null,
         vence_em = coalesce(v_base, current_date) + interval '1 month',
         atualizado_em = now()
   where salao_id = c.salao_id;
  return jsonb_build_object('ok', true, 'salao', c.salao_id, 'plano', c.plano);
end $$;
revoke all on function public.abrir_cobranca(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function public.anotar_cobranca(uuid, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.registrar_pagamento(text, numeric, text) from public, anon, authenticated;
create or replace function public.minha_cobranca(p_salao uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object(
    'aberta', (
      select to_jsonb(x) from (
        select c.id, c.plano, c.valor, c.metodo, c.vence_em,
               c.pix_copia_cola, c.pix_qr_base64, c.boleto_url, c.linha_digitavel
          from public.cobrancas c
         where c.salao_id = p_salao and c.status = 'pendente'
           and c.vence_em > now()
         order by c.criada_em desc limit 1) x),
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id, 'plano', h.plano, 'valor', h.valor,
               'metodo', h.metodo, 'status', h.status,
               'pagaEm', h.paga_em, 'criadaEm', h.criada_em)
             order by h.criada_em desc)
        from (select * from public.cobrancas
               where salao_id = p_salao and status in ('paga','devolvida')
               order by criada_em desc limit 12) h), '[]'::jsonb)
  );
end $$;
revoke all on function public.minha_cobranca(uuid) from public;
grant execute on function public.minha_cobranca(uuid) to authenticated;
create or replace function public.assinaturas_a_vencer(p_dias int default 5)
returns table (salao_id uuid, salao text, whatsapp text, plano text,
               valor numeric, vence_em date)
language sql security definer set search_path = public as $$
  select a.salao_id, s.nome, s.whatsapp, a.plano, pl.preco_mes, a.vence_em
    from public.assinaturas a
    join public.saloes s  on s.id = a.salao_id
    join public.planos pl on pl.codigo = a.plano
   where a.status = 'ativa'
     and a.vence_em is not null
     and a.vence_em <= current_date + p_dias
     and pl.preco_mes > 0
     and not exists (
       select 1 from public.cobrancas c
        where c.salao_id = a.salao_id and c.status = 'pendente'
          and c.vence_em > now())
   order by a.vence_em;
$$;
create or replace function public.vencer_cobrancas()
returns int
language sql security definer set search_path = public as $$
  with mortas as (
    update public.cobrancas set status = 'vencida'
     where status = 'pendente' and vence_em <= now()
     returning 1)
  select count(*)::int from mortas;
$$;
revoke all on function public.assinaturas_a_vencer(int) from public, anon, authenticated;
revoke all on function public.vencer_cobrancas() from public, anon, authenticated;

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
  v_cedo_demais constant interval := '30 minutes';
  j         record;
  v_ini     timestamptz;
  v_fim     timestamptz;
begin
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

create or replace function public.reais(v numeric)
returns text language sql immutable set search_path = public as $$
  select 'R$ ' || replace(replace(replace(
           to_char(coalesce(v, 0), 'FM999,999,990.00'),
           '.', '|'), ',', '.'), '|', ',')
$$;
update public.comandas c
   set agendamento_id = null
 where c.agendamento_id is not null
   and c.status <> 'cancelada'
   and c.id <> (
     select d.id from public.comandas d
      where d.agendamento_id = c.agendamento_id
        and d.status <> 'cancelada'
      order by (select count(*) from public.pagamentos p
                 where p.comanda_id = d.id) desc,
               (select count(*) from public.comanda_itens i
                 where i.comanda_id = d.id) desc,
               d.aberta_em asc,
               d.id asc
      limit 1);
create unique index if not exists ux_comanda_agendamento
  on public.comandas(agendamento_id)
  where (agendamento_id is not null and status <> 'cancelada');
alter table public.comandas
  add column if not exists acrescimo numeric(10,2) not null default 0
    check (acrescimo >= 0);
comment on column public.comandas.acrescimo is
  'Taxa de urgência, domingo, deslocamento. Entra no total e NÃO gera comissão.';
drop view if exists public.comandas_totais;
create view public.comandas_totais
with (security_invoker = true) as
  select c.id,
         c.salao_id,
         c.numero,
         c.status,
         coalesce(sum(i.total), 0)                                as subtotal,
         c.desconto,
         c.acrescimo,
         coalesce(sum(i.total), 0) - c.desconto + c.acrescimo     as total,
         coalesce(sum(round(i.qtd * i.preco_unit * i.comissao_pct / 100, 2)), 0)
                                                                  as comissao_total,
         coalesce((select sum(p.valor) from public.pagamentos p
                    where p.comanda_id = c.id), 0)                as pago,
         (coalesce(sum(i.total), 0) - c.desconto + c.acrescimo)
           - coalesce((select sum(p.valor) from public.pagamentos p
                        where p.comanda_id = c.id), 0)            as falta,
         case
           when c.status = 'cancelada' then 'cancelado'
           when coalesce((select sum(p.valor) from public.pagamentos p
                           where p.comanda_id = c.id), 0) = 0 then 'pendente'
           when coalesce((select sum(p.valor) from public.pagamentos p
                           where p.comanda_id = c.id), 0)
                >= (coalesce(sum(i.total), 0) - c.desconto + c.acrescimo)
             then 'pago'
           else 'parcial'
         end                                                      as situacao
    from public.comandas c
    left join public.comanda_itens i on i.comanda_id = c.id
   group by c.id;
grant select on public.comandas_totais to authenticated;
create or replace function public.conferir_desconto(p_comanda uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_sub  numeric(10,2);
  v_desc numeric(10,2);
begin
  select coalesce(sum(i.total), 0) into v_sub
    from public.comanda_itens i where i.comanda_id = p_comanda;
  select c.desconto into v_desc
    from public.comandas c where c.id = p_comanda;
  if v_desc > v_sub then
    raise exception
      'O desconto de % não pode ser maior que o valor dos itens (%).',
      public.reais(v_desc), public.reais(v_sub)
      using errcode = 'check_violation';
  end if;
end $$;
create or replace function public.tg_comanda_desconto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.conferir_desconto(new.id);
  return new;
end $$;
create or replace function public.tg_item_desconto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.conferir_desconto(coalesce(new.comanda_id, old.comanda_id));
  return coalesce(new, old);
end $$;
drop trigger if exists tg_comanda_desconto on public.comandas;
create constraint trigger tg_comanda_desconto
  after update of desconto on public.comandas
  deferrable initially immediate
  for each row execute function public.tg_comanda_desconto();
drop trigger if exists tg_item_desconto on public.comanda_itens;
create constraint trigger tg_item_desconto
  after insert or update or delete on public.comanda_itens
  deferrable initially immediate
  for each row execute function public.tg_item_desconto();
create or replace function public.tg_pagamento_cabe()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_total numeric(10,2);
  v_pago  numeric(10,2);
begin
  select t.total into v_total from public.comandas_totais t where t.id = new.comanda_id;
  select coalesce(sum(p.valor), 0) into v_pago
    from public.pagamentos p
   where p.comanda_id = new.comanda_id
     and (tg_op = 'INSERT' or p.id <> new.id);
  if v_total is null then
    raise exception 'Comanda não encontrada.' using errcode = 'check_violation';
  end if;
  if v_pago + new.valor > v_total + 0.005 then
    raise exception
      'Pagamento de % excede o que falta nesta comanda: %.',
      public.reais(new.valor), public.reais(greatest(v_total - v_pago, 0))
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists tg_pagamento_cabe on public.pagamentos;
create trigger tg_pagamento_cabe
  before insert or update of valor, comanda_id on public.pagamentos
  for each row execute function public.tg_pagamento_cabe();
create or replace function public.tg_comanda_travada()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_status text;
  v_com    uuid;
begin
  v_com := coalesce(
    case tg_table_name
      when 'comanda_itens' then coalesce(new.comanda_id, old.comanda_id)
      when 'pagamentos'    then coalesce(new.comanda_id, old.comanda_id)
    end);
  select c.status into v_status from public.comandas c where c.id = v_com;
  if v_status = 'fechada' then
    raise exception 'Esta comanda está fechada. Reabra antes de alterar.'
      using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists tg_item_travado on public.comanda_itens;
create trigger tg_item_travado
  before insert or update or delete on public.comanda_itens
  for each row execute function public.tg_comanda_travada();
drop trigger if exists tg_pagamento_travado on public.pagamentos;
create trigger tg_pagamento_travado
  before insert or update or delete on public.pagamentos
  for each row execute function public.tg_comanda_travada();
create or replace function public.tg_comanda_valor_travado()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'fechada' and new.status = 'fechada'
     and (new.desconto is distinct from old.desconto
       or new.acrescimo is distinct from old.acrescimo) then
    raise exception 'Esta comanda está fechada. Reabra antes de alterar.'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists tg_comanda_valor_travado on public.comandas;
create trigger tg_comanda_valor_travado
  before update of desconto, acrescimo on public.comandas
  for each row execute function public.tg_comanda_valor_travado();
create or replace function public.tg_fechar_comanda()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  t record;
begin
  if new.status <> 'fechada' or old.status = 'fechada' then
    return new;
  end if;
  select * into t from public.comandas_totais where id = new.id;
  if t.subtotal <= 0 then
    raise exception 'Comanda sem itens não pode ser fechada.'
      using errcode = 'check_violation';
  end if;
  if t.falta > 0.005 then
    raise exception 'Ainda faltam % para fechar esta comanda.',
      public.reais(t.falta) using errcode = 'check_violation';
  end if;
  if new.fechada_em is null then new.fechada_em := now(); end if;
  return new;
end $$;
drop trigger if exists tg_fechar_comanda on public.comandas;
create trigger tg_fechar_comanda
  before update of status on public.comandas
  for each row execute function public.tg_fechar_comanda();
revoke all on function public.conferir_desconto(uuid) from public, anon, authenticated;
revoke all on function public.reais(numeric) from public;
grant execute on function public.reais(numeric) to anon, authenticated;

alter table public.servicos_profissionais
  add column if not exists id uuid not null default gen_random_uuid();
create unique index if not exists ux_sp_id on public.servicos_profissionais(id);
alter table public.servicos_profissionais
  add column if not exists comissao_pct numeric(5,2)
    check (comissao_pct between 0 and 100);
alter table public.servicos_profissionais
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);
alter table public.servicos
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);
alter table public.produtos
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);
alter table public.profissionais
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);
alter table public.comanda_itens
  add column if not exists comissao_fixa numeric(10,2) not null default 0
    check (comissao_fixa >= 0);
comment on column public.comanda_itens.comissao_pct is
  'Congelada pelo gatilho no lançamento. NÃO é o que o navegador mandou.';
comment on column public.comanda_itens.comissao_fixa is
  'Por unidade: 2 itens a R$ 5 fixos = R$ 10. Congelada junto com a pct.';
alter table public.saloes
  add column if not exists comissao_sobre text not null default 'bruto'
    check (comissao_sobre in ('bruto','liquido'));
alter table public.saloes
  add column if not exists comissao_regra_desde date;
comment on column public.saloes.comissao_regra_desde is
  'A regra vale para comanda aberta a partir daqui. Nulo = nunca virou.';
alter table public.comandas
  add column if not exists comissao_sobre text not null default 'bruto'
    check (comissao_sobre in ('bruto','liquido'));
create or replace function public.comissao_de(
  p_tipo text, p_servico uuid, p_produto uuid, p_profissional uuid,
  out pct numeric, out fixa numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_tipo = 'servico' and p_servico is not null and p_profissional is not null then
    select sp.comissao_pct, sp.comissao_fixa into pct, fixa
      from public.servicos_profissionais sp
     where sp.servico_id = p_servico and sp.profissional_id = p_profissional
       and (sp.comissao_pct is not null or sp.comissao_fixa is not null);
    if found then
      return;
    end if;
  end if;
  if p_tipo = 'servico' and p_servico is not null then
    select sv.comissao_pct, sv.comissao_fixa into pct, fixa
      from public.servicos sv
     where sv.id = p_servico
       and (sv.comissao_pct is not null or sv.comissao_fixa is not null);
    if found then
      return;
    end if;
  elsif p_tipo = 'produto' and p_produto is not null then
    select pd.comissao_pct, pd.comissao_fixa into pct, fixa
      from public.produtos pd
     where pd.id = p_produto;
    if found then
      return;
    end if;
  end if;
  if p_profissional is not null then
    select pr.comissao_pct, pr.comissao_fixa into pct, fixa
      from public.profissionais pr
     where pr.id = p_profissional;
    if found then
      return;
    end if;
  end if;
  pct := 0; fixa := 0;
end $$;
comment on function public.comissao_de(text, uuid, uuid, uuid) is
  'A escada: par, catálogo, pessoa, zero. Não aceita taxa por parâmetro.';
revoke all on function public.comissao_de(text, uuid, uuid, uuid)
  from public, anon, authenticated;
create or replace function public.tg_item_comissao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t record;
begin
  if tg_op = 'UPDATE'
     and new.tipo is not distinct from old.tipo
     and new.servico_id is not distinct from old.servico_id
     and new.produto_id is not distinct from old.produto_id
     and new.profissional_id is not distinct from old.profissional_id then
    new.comissao_pct  := old.comissao_pct;
    new.comissao_fixa := old.comissao_fixa;
    return new;
  end if;
  select * into t from public.comissao_de(
    new.tipo, new.servico_id, new.produto_id, new.profissional_id);
  new.comissao_pct  := coalesce(t.pct, 0);
  new.comissao_fixa := coalesce(t.fixa, 0);
  return new;
end $$;
drop trigger if exists tg_item_comissao on public.comanda_itens;
create trigger tg_item_comissao
  before insert or update on public.comanda_itens
  for each row execute function public.tg_item_comissao();
create or replace function public.tg_comanda_regra() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_sobre text;
  v_desde date;
  v_fuso  text;
begin
  select coalesce(s.comissao_sobre, 'bruto'), s.comissao_regra_desde,
         coalesce(s.fuso, 'America/Sao_Paulo')
    into v_sobre, v_desde, v_fuso
    from public.saloes s where s.id = new.salao_id;
  if v_desde is null
     or (new.aberta_em at time zone v_fuso)::date < v_desde then
    new.comissao_sobre := 'bruto';
  else
    new.comissao_sobre := v_sobre;
  end if;
  return new;
end $$;
drop trigger if exists tg_comanda_regra on public.comandas;
create trigger tg_comanda_regra
  before insert on public.comandas
  for each row execute function public.tg_comanda_regra();
drop view if exists public.comandas_totais;
drop view if exists public.comanda_itens_calculados;
alter table public.comanda_itens drop column if exists comissao_valor;
create view public.comanda_itens_calculados
with (security_invoker = true) as
  select i.id, i.comanda_id, i.tipo, i.servico_id, i.produto_id, i.descricao,
         i.qtd, i.preco_unit, i.profissional_id,
         i.comissao_pct, i.comissao_fixa, i.total,
         b.base_comissao,
         round(b.base_comissao * i.comissao_pct / 100, 2)
           + round(i.qtd * i.comissao_fixa, 2) as comissao_valor
    from public.comanda_itens i
    join public.comandas c on c.id = i.comanda_id
    cross join lateral (
      select case
               when c.comissao_sobre = 'liquido' and c.desconto > 0 and s.sub > 0
               then i.total - round(c.desconto * i.total / s.sub, 2)
               else i.total
             end as base_comissao
        from (select coalesce(sum(x.total), 0) as sub
                from public.comanda_itens x
               where x.comanda_id = i.comanda_id) s
    ) b;
comment on view public.comanda_itens_calculados is
  'O único lugar que calcula comissão. Relatório, totais e tela leem daqui.';
grant select on public.comanda_itens_calculados to authenticated;
create view public.comandas_totais
with (security_invoker = true) as
  select c.id,
         c.salao_id,
         c.cliente_id,
         c.agendamento_id,
         c.numero,
         c.status,
         c.aberta_em,
         c.fechada_em,
         c.comissao_sobre,
         coalesce(i.subtotal, 0)                        as subtotal,
         c.desconto,
         c.acrescimo,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo as total,
         coalesce(i.comissao, 0)                        as comissao_total,
         coalesce(p.pago, 0)                            as pago,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
           - coalesce(p.pago, 0)                        as falta,
         case
           when c.status = 'cancelada' then 'cancelado'
           when coalesce(p.pago, 0) = 0 then 'pendente'
           when coalesce(p.pago, 0)
                >= coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
             then 'pago'
           else 'parcial'
         end                                            as situacao
    from public.comandas c
    left join (select k.comanda_id,
                      sum(k.total)          as subtotal,
                      sum(k.comissao_valor) as comissao
                 from public.comanda_itens_calculados k
                group by k.comanda_id) i on i.comanda_id = c.id
    left join (select g.comanda_id, sum(g.valor) as pago
                 from public.pagamentos g
                group by g.comanda_id) p on p.comanda_id = c.id;
grant select on public.comandas_totais to authenticated;

create table if not exists public.caixas (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  aberto_em     timestamptz not null default now(),
  aberto_por    uuid references public.perfis(id) on delete set null,
  valor_abertura numeric(10,2) not null default 0 check (valor_abertura >= 0),
  fechado_em    timestamptz,
  fechado_por   uuid references public.perfis(id) on delete set null,
  valor_contado numeric(10,2) check (valor_contado >= 0),
  observacao    text,
  check ( (fechado_em is null and valor_contado is null)
       or (fechado_em is not null and valor_contado is not null) )
);
create index if not exists ix_caixa_salao
  on public.caixas(salao_id, aberto_em desc);
create unique index if not exists ux_caixa_aberto
  on public.caixas(salao_id) where (fechado_em is null);
alter table public.caixas enable row level security;
alter table public.caixas force row level security;
drop policy if exists caixa_ver on public.caixas;
create policy caixa_ver on public.caixas for select to authenticated
  using ( public.ve_agenda_toda(salao_id) );
drop policy if exists caixa_gerir on public.caixas;
create policy caixa_gerir on public.caixas for all to authenticated
  using ( public.ve_agenda_toda(salao_id) )
  with check ( public.ve_agenda_toda(salao_id) );
revoke all on public.caixas from anon;
grant select, insert, update on public.caixas to authenticated;
create table if not exists public.caixa_movimentos (
  id         uuid primary key default gen_random_uuid(),
  caixa_id   uuid not null references public.caixas(id) on delete cascade,
  salao_id   uuid not null references public.saloes(id) on delete cascade,
  tipo       text not null check (tipo in ('sangria','suprimento')),
  valor      numeric(10,2) not null check (valor > 0),
  motivo     text not null check (length(btrim(motivo)) >= 3),
  quem       uuid references public.perfis(id) on delete set null,
  criado_em  timestamptz not null default now()
);
create index if not exists ix_mov_caixa on public.caixa_movimentos(caixa_id);
alter table public.caixa_movimentos enable row level security;
alter table public.caixa_movimentos force row level security;
drop policy if exists mov_gerir on public.caixa_movimentos;
create policy mov_gerir on public.caixa_movimentos for all to authenticated
  using ( public.ve_agenda_toda(salao_id) )
  with check ( public.ve_agenda_toda(salao_id) );
revoke all on public.caixa_movimentos from anon;
grant select, insert on public.caixa_movimentos to authenticated;
create or replace function public.tg_mov_caixa_aberto() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.caixas c
              where c.id = new.caixa_id and c.fechado_em is not null) then
    raise exception 'Este caixa já foi fechado. Abra o caixa do dia para lançar.'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists tg_mov_caixa_aberto on public.caixa_movimentos;
create trigger tg_mov_caixa_aberto
  before insert on public.caixa_movimentos
  for each row execute function public.tg_mov_caixa_aberto();
alter table public.pagamentos
  add column if not exists caixa_id uuid
  references public.caixas(id) on delete set null;
create index if not exists ix_pgto_caixa on public.pagamentos(caixa_id);
create or replace function public.tg_pagamento_caixa() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_salao uuid;
begin
  if new.caixa_id is not null then
    return new;
  end if;
  select c.salao_id into v_salao from public.comandas c where c.id = new.comanda_id;
  select k.id into new.caixa_id
    from public.caixas k
   where k.salao_id = v_salao and k.fechado_em is null
   limit 1;
  return new;
end $$;
drop trigger if exists tg_pagamento_caixa on public.pagamentos;
create trigger tg_pagamento_caixa
  before insert on public.pagamentos
  for each row execute function public.tg_pagamento_caixa();
create table if not exists public.estornos (
  id           uuid primary key default gen_random_uuid(),
  pagamento_id uuid not null references public.pagamentos(id) on delete cascade,
  salao_id     uuid not null references public.saloes(id) on delete cascade,
  valor        numeric(10,2) not null check (valor > 0),
  motivo       text not null check (length(btrim(motivo)) >= 3),
  quem         uuid references public.perfis(id) on delete set null,
  criado_em    timestamptz not null default now()
);
create index if not exists ix_estorno_pgto on public.estornos(pagamento_id);
alter table public.estornos enable row level security;
alter table public.estornos force row level security;
drop policy if exists estorno_gerir on public.estornos;
create policy estorno_gerir on public.estornos for all to authenticated
  using ( public.ve_agenda_toda(salao_id) )
  with check ( public.ve_agenda_toda(salao_id) );
revoke all on public.estornos from anon;
grant select, insert on public.estornos to authenticated;
create or replace function public.tg_estorno_cabe() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_valor  numeric;
  v_ja     numeric;
  v_status text;
  v_salao  uuid;
begin
  select p.valor, c.status, c.salao_id
    into v_valor, v_status, v_salao
    from public.pagamentos p
    join public.comandas c on c.id = p.comanda_id
   where p.id = new.pagamento_id;
  if v_valor is null then
    raise exception 'Pagamento não encontrado.' using errcode = 'no_data_found';
  end if;
  new.salao_id := v_salao;
  if v_status = 'fechada' then
    raise exception 'Reabra a comanda antes de estornar este pagamento.'
      using errcode = 'check_violation';
  end if;
  if v_status = 'cancelada' then
    raise exception 'Esta comanda foi cancelada.' using errcode = 'check_violation';
  end if;
  select coalesce(sum(e.valor), 0) into v_ja
    from public.estornos e where e.pagamento_id = new.pagamento_id;
  if new.valor > v_valor - v_ja + 0.005 then
    raise exception 'Estorno de % maior que o disponível neste pagamento: %.',
      public.reais(new.valor), public.reais(v_valor - v_ja)
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists tg_estorno_cabe on public.estornos;
create trigger tg_estorno_cabe
  before insert on public.estornos
  for each row execute function public.tg_estorno_cabe();
drop view if exists public.comandas_totais;
create view public.comandas_totais
with (security_invoker = true) as
  select c.id,
         c.salao_id,
         c.cliente_id,
         c.agendamento_id,
         c.numero,
         c.status,
         c.aberta_em,
         c.fechada_em,
         c.comissao_sobre,
         coalesce(i.subtotal, 0)                        as subtotal,
         c.desconto,
         c.acrescimo,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo as total,
         coalesce(i.comissao, 0)                        as comissao_total,
         coalesce(p.pago, 0)                            as pago,
         coalesce(p.estornado, 0)                       as estornado,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
           - coalesce(p.pago, 0)                        as falta,
         case
           when c.status = 'cancelada' then 'cancelado'
           when coalesce(p.pago, 0) = 0 then 'pendente'
           when coalesce(p.pago, 0)
                >= coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
             then 'pago'
           else 'parcial'
         end                                            as situacao
    from public.comandas c
    left join (select k.comanda_id,
                      sum(k.total)          as subtotal,
                      sum(k.comissao_valor) as comissao
                 from public.comanda_itens_calculados k
                group by k.comanda_id) i on i.comanda_id = c.id
    left join (select g.comanda_id,
                      sum(g.valor) - coalesce(sum(e.estornado), 0) as pago,
                      coalesce(sum(e.estornado), 0)                as estornado
                 from public.pagamentos g
                 left join (select x.pagamento_id, sum(x.valor) as estornado
                              from public.estornos x
                             group by x.pagamento_id) e
                        on e.pagamento_id = g.id
                group by g.comanda_id) p on p.comanda_id = c.id;
grant select on public.comandas_totais to authenticated;
create or replace function public.tg_pagamento_cabe()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_total numeric(10,2);
  v_pago  numeric(10,2);
begin
  select t.total into v_total from public.comandas_totais t where t.id = new.comanda_id;
  select coalesce(sum(p.valor), 0) - coalesce(sum(e.estornado), 0)
    into v_pago
    from public.pagamentos p
    left join (select x.pagamento_id, sum(x.valor) as estornado
                 from public.estornos x group by x.pagamento_id) e
           on e.pagamento_id = p.id
   where p.comanda_id = new.comanda_id
     and (tg_op = 'INSERT' or p.id <> new.id);
  if v_total is null then
    raise exception 'Comanda não encontrada.' using errcode = 'check_violation';
  end if;
  if v_pago + new.valor > v_total + 0.005 then
    raise exception
      'Pagamento de % excede o que falta nesta comanda: %.',
      public.reais(new.valor), public.reais(greatest(v_total - v_pago, 0))
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create or replace function public.conferir_caixa(p_caixa uuid)
returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  k         public.caixas%rowtype;
  v_dinheiro numeric;
  v_sangria  numeric;
  v_suprim   numeric;
  v_esperado numeric;
begin
  select * into k from public.caixas where id = p_caixa;
  if k.id is null then
    raise exception 'Caixa não encontrado.' using errcode = 'no_data_found';
  end if;
  if not public.ve_agenda_toda(k.salao_id) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  select coalesce(sum(g.valor), 0) - coalesce(sum(e.estornado), 0)
    into v_dinheiro
    from public.pagamentos g
    left join (select x.pagamento_id, sum(x.valor) as estornado
                 from public.estornos x group by x.pagamento_id) e
           on e.pagamento_id = g.id
   where g.caixa_id = p_caixa and g.forma = 'dinheiro';
  select coalesce(sum(m.valor) filter (where m.tipo = 'sangria'), 0),
         coalesce(sum(m.valor) filter (where m.tipo = 'suprimento'), 0)
    into v_sangria, v_suprim
    from public.caixa_movimentos m where m.caixa_id = p_caixa;
  v_esperado := k.valor_abertura + v_dinheiro + v_suprim - v_sangria;
  return jsonb_build_object(
    'id',            k.id,
    'abertoEm',      k.aberto_em,
    'fechadoEm',     k.fechado_em,
    'valorAbertura', k.valor_abertura,
    'dinheiro',      v_dinheiro,
    'suprimentos',   v_suprim,
    'sangrias',      v_sangria,
    'esperado',      v_esperado,
    'contado',       k.valor_contado,
    'diferenca',     case when k.valor_contado is null then null
                          else round(k.valor_contado - v_esperado, 2) end,
    'outrosMeios', coalesce((
      select jsonb_agg(jsonb_build_object('forma', y.forma, 'valor', y.valor)
                       order by y.valor desc)
        from (select g.forma,
                     round(sum(g.valor) - coalesce(sum(e.estornado), 0), 2) as valor
                from public.pagamentos g
                left join (select x.pagamento_id, sum(x.valor) as estornado
                             from public.estornos x group by x.pagamento_id) e
                       on e.pagamento_id = g.id
               where g.caixa_id = p_caixa and g.forma <> 'dinheiro'
               group by g.forma) y), '[]'::jsonb),
    'movimentos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', m.tipo, 'valor', m.valor, 'motivo', m.motivo,
               'criadoEm', m.criado_em) order by m.criado_em)
        from public.caixa_movimentos m where m.caixa_id = p_caixa), '[]'::jsonb)
  );
end $$;
revoke all on function public.conferir_caixa(uuid) from public, anon;
grant execute on function public.conferir_caixa(uuid) to authenticated;
create or replace function public.fechar_caixa(
  p_caixa uuid, p_contado numeric, p_observacao text default null)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare k public.caixas%rowtype;
begin
  select * into k from public.caixas where id = p_caixa;
  if k.id is null then
    raise exception 'Caixa não encontrado.' using errcode = 'no_data_found';
  end if;
  if not public.ve_agenda_toda(k.salao_id) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  if k.fechado_em is not null then
    raise exception 'Este caixa já foi fechado.' using errcode = 'check_violation';
  end if;
  if p_contado is null or p_contado < 0 then
    raise exception 'Informe quanto tem na gaveta.' using errcode = 'check_violation';
  end if;
  update public.caixas
     set fechado_em = now(), fechado_por = auth.uid(),
         valor_contado = p_contado,
         observacao = coalesce(p_observacao, observacao)
   where id = p_caixa;
  return public.conferir_caixa(p_caixa);
end $$;
revoke all on function public.fechar_caixa(uuid, numeric, text) from public, anon;
grant execute on function public.fechar_caixa(uuid, numeric, text) to authenticated;

create or replace function public.painel_hoje(
  p_salao uuid, p_dia date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso  text;
  v_hoje  date;
  v_ini   timestamptz;
  v_fim   timestamptz;
  v_ini_o timestamptz;
  v_fim_o timestamptz;
  v_caixa uuid;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  select fuso into v_fuso from public.saloes where id = p_salao;
  if not found then
    raise exception 'Salão não encontrado.' using errcode = 'no_data_found';
  end if;
  v_fuso := coalesce(v_fuso, 'America/Sao_Paulo');
  v_hoje := coalesce(p_dia, (now() at time zone v_fuso)::date);
  v_ini   := (v_hoje::timestamp) at time zone v_fuso;
  v_fim   := ((v_hoje + 1)::timestamp) at time zone v_fuso;
  v_fim_o := v_ini;
  v_ini_o := v_ini - interval '1 day';
  select k.id into v_caixa
    from public.caixas k
   where k.salao_id = p_salao and k.fechado_em is null
   limit 1;
  return jsonb_build_object(
    'dia',  v_hoje,
    'fuso', v_fuso,
    'agenda', (
      select jsonb_build_object(
        'total',     count(*),
        'aguardando', count(*) filter (where a.status in ('pendente','confirmado')),
        'atendendo', count(*) filter (where a.status = 'em_atendimento'),
        'concluidos', count(*) filter (where a.status = 'concluido'),
        'faltas',    count(*) filter (where a.status = 'faltou'),
        'cancelados', count(*) filter (where a.status = 'cancelado'))
        from public.agendamentos a
       where a.salao_id = p_salao
         and a.arquivado_em is null
         and a.inicio >= v_ini and a.inicio < v_fim),
    'dinheiro', (
      select jsonb_build_object(
        'faturamento', coalesce(round(sum(t.total) filter (
                         where c.status = 'fechada'), 2), 0),
        'comandas',    count(*) filter (where c.status = 'fechada'),
        'ticket',      case when count(*) filter (where c.status = 'fechada') > 0
                            then round(sum(t.total) filter (where c.status = 'fechada')
                                       / count(*) filter (where c.status = 'fechada'), 2)
                            else 0 end,
        'comissoes',   coalesce(round(sum(t.comissao_total) filter (
                         where c.status = 'fechada'), 2), 0),
        'estornado',   coalesce(round(sum(t.estornado) filter (
                         where c.status = 'fechada'), 2), 0))
        from public.comandas c
        join public.comandas_totais t on t.id = c.id
       where c.salao_id = p_salao
         and c.fechada_em >= v_ini and c.fechada_em < v_fim),
    'aReceber', coalesce((
      select round(sum(t.falta), 2)
        from public.comandas c
        join public.comandas_totais t on t.id = c.id
       where c.salao_id = p_salao
         and c.status = 'aberta'
         and t.falta > 0), 0),
    'ontem', (
      select jsonb_build_object(
        'faturamento', coalesce(round(sum(t.total), 2), 0),
        'comandas',    count(*))
        from public.comandas c
        join public.comandas_totais t on t.id = c.id
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini_o and c.fechada_em < v_fim_o),
    'caixa', case when v_caixa is null then null
                  else public.conferir_caixa(v_caixa) end,
    'proximos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'inicio', x.inicio, 'cliente', x.cliente,
               'profissional', x.profissional, 'status', x.status)
             order by x.inicio)
        from (select a.inicio, a.status,
                     coalesce(cl.nome, a.atendido_nome, 'sem nome') as cliente,
                     coalesce(pr.apelido, pr.nome, '—')             as profissional
                from public.agendamentos a
                left join public.clientes cl on cl.id = a.cliente_id
                left join public.profissionais pr on pr.id = a.profissional_id
               where a.salao_id = p_salao
                 and a.arquivado_em is null
                 and a.status in ('pendente','confirmado','em_atendimento')
                 and a.inicio >= greatest(v_ini, now())
                 and a.inicio < v_fim
               order by a.inicio
               limit 6) x), '[]'::jsonb)
  );
end $$;
comment on function public.painel_hoje(uuid, date) is
  'O dia do salão num jsonb só: agenda, dinheiro, gaveta e quem ainda vem.';
revoke all on function public.painel_hoje(uuid, date) from public, anon;
grant execute on function public.painel_hoje(uuid, date) to authenticated;

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
create or replace function public.minutos_de_jornada(
  p_profissional uuid, p_data date)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(extract(epoch from (j.fim - j.inicio)) / 60), 0)::int
    from public.jornada_costurada(p_profissional, p_data) j
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
revoke all on function public.minutos_online_no_dia(uuid, date) from public, anon;
revoke all on function public.minutos_de_jornada(uuid, date)    from public, anon;
revoke all on function public.rajada_online(uuid)               from public, anon;
grant execute on function public.minutos_online_no_dia(uuid, date) to authenticated;
grant execute on function public.minutos_de_jornada(uuid, date)    to authenticated;
grant execute on function public.rajada_online(uuid)               to authenticated;
create or replace function public.porque_nao_agenda(
  p_profissional uuid, p_data date, p_servicos uuid[])
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_salao   uuid;
  v_hoje    date;
  v_jornada int;
  v_online  int;
  v_pedido  int;
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
comment on function public.teto_online_pct(uuid) is
  'Quanto da jornada de um profissional o link pode ocupar num dia. cfg.tetoOnlinePct, padrão 70.';
comment on function public.teto_online_rajada(uuid) is
  'Quantas pessoas NOVAS o link aceita no salão em 10 minutos. cfg.tetoOnlineRajada, padrão 10.';

create or replace function public.travar_agenda(p_salao uuid)
returns void language sql set search_path = public as $$
  select pg_advisory_xact_lock(hashtext(p_salao::text))
$$;
revoke all on function public.travar_agenda(uuid) from public, anon, authenticated;
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
    return new;
  end if;
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
comment on function public.travar_agenda(uuid) is
  'Trava consultiva por salão, até o fim da transação. Bloqueio e atendimento não se cruzam.';

alter table public.profissionais
  add column if not exists telefone text;
alter table public.profissionais
  add column if not exists notif_novo boolean not null default true;
alter table public.profissionais
  add column if not exists notif_resumo boolean not null default true;
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
create or replace function public.lembrete_minutos(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select case when public.notif_liga(p_salao, 'notifLembrete', true)
              then greatest(0, least(1440,
                     public.notif_num(p_salao, 'notifLembreteMin', 120)))
              else 0 end
$$;
create table if not exists public.notificacoes (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  tipo            text not null
                  check (tipo in ('confirmacao','lembrete','resumo','novo')),
  destino         text not null,
  cliente_id      uuid references public.clientes(id) on delete set null,
  profissional_id uuid references public.profissionais(id) on delete set null,
  agendamento_id  uuid references public.agendamentos(id) on delete cascade,
  quando          timestamptz not null,
  corpo           text not null,
  status          text not null default 'pendente'
                  check (status in ('pendente','enviando','enviado',
                                    'entregue','lido','falhou','cancelado')),
  tentativas      smallint not null default 0 check (tentativas >= 0),
  proxima_em      timestamptz,
  enviado_em      timestamptz,
  erro_codigo     text,
  erro_msg        text,
  wam_id          text,
  motivo          text,
  chave           text not null,
  criado_em       timestamptz not null default now()
);
create unique index if not exists ux_notif_chave
  on public.notificacoes(salao_id, chave);
create index if not exists ix_notif_fila
  on public.notificacoes(quando)
  where status = 'pendente';
create index if not exists ix_notif_salao
  on public.notificacoes(salao_id, criado_em desc);
create index if not exists ix_notif_cliente
  on public.notificacoes(cliente_id, criado_em desc);
create index if not exists ix_notif_wam
  on public.notificacoes(wam_id)
  where wam_id is not null;
alter table public.notificacoes enable row level security;
alter table public.notificacoes force row level security;
drop policy if exists notif_ler on public.notificacoes;
create policy notif_ler on public.notificacoes for select to authenticated
  using ( public.ve_agenda_toda(salao_id)
          or profissional_id = public.meu_profissional_id(salao_id) );
revoke all on public.notificacoes from anon, authenticated;
grant select on public.notificacoes to authenticated;
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
alter table public.notificacoes
  add column if not exists modelo text;
alter table public.notificacoes
  add column if not exists variaveis jsonb;
create or replace function public.variavel_limpa(p_texto text, p_teto int default 900)
returns text language sql immutable set search_path = public as $$
  select case
    when t = '' then '—'
    when length(t) > p_teto then left(t, p_teto - 1) || '…'
    else t
  end
  from (select btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')) as t) x
$$;
create or replace function public.variavel_lista(p_texto text, p_teto int default 900)
returns text language sql immutable set search_path = public as $$
  select public.variavel_limpa(
    regexp_replace(
      regexp_replace(coalesce(p_texto, ''), '[\r\n]+', ' · ', 'g'),
      '( · )+', ' · ', 'g'),
    p_teto)
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
    if v_total = 0 then return null; end if;
    return format('☀️ Bom dia%s!' || E'\n\nSua agenda de hoje' || E'\n%s'
                  || E'\n\nTotal: %s atendimento%s',
                  case when p_profissional is not null
                       then ', ' || split_part(v_quem, ' ', 1) else '' end,
                  v_corpo, v_total, case when v_total = 1 then '' else 's' end);
  end if;
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
  if v_tel_cli is not null and v_min > 0 then
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
drop trigger if exists tg_notif_agendamento on public.agendamentos;
create trigger tg_notif_agendamento
  after insert on public.agendamentos
  for each row execute function public.tg_notificar_agendamento();
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
             corpo  = coalesce(public.texto_agendamento(new.id, 'lembrete'), corpo),
             variaveis = coalesce(
               public.variaveis_agendamento(new.id, 'lembrete'), variaveis)
       where agendamento_id = new.id and tipo = 'lembrete' and status = 'pendente';
    else
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
create or replace function public.tg_notificacao_servico_mudou()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ag uuid;
begin
  v_ag := coalesce(new.agendamento_id, old.agendamento_id);
  update public.notificacoes n
     set corpo = coalesce(public.texto_agendamento(v_ag, n.tipo), n.corpo),
         variaveis = coalesce(
           public.variaveis_agendamento(v_ag, n.tipo), n.variaveis)
   where n.agendamento_id = v_ag
     and n.status = 'pendente'
     and n.tipo in ('confirmacao','lembrete','novo');
  return coalesce(new, old);
end $$;
drop trigger if exists tg_notif_servico on public.agendamento_servicos;
create trigger tg_notif_servico
  after insert or update or delete on public.agendamento_servicos
  for each row execute function public.tg_notificacao_servico_mudou();
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
    if extract(hour from (p_agora at time zone v_fuso))::int < v_hora then
      continue;
    end if;
    v_periodo := coalesce(
      (select cfg->>'notifResumoPeriodo' from public.saloes where id = s.id), 'dia');
    if v_periodo not in ('dia','manha','tarde') then v_periodo := 'dia'; end if;
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
          (salao_id, tipo, destino, quando, corpo, chave, modelo, variaveis)
        values (s.id, 'resumo', v_tel, p_agora, v_corpo,
                'resumo:casa:' || v_hoje, public.modelo_de('resumo'),
                jsonb_build_array(
                  public.variavel_limpa(
                    (select nome from public.saloes where id = s.id)),
                  public.variavel_lista(v_corpo)))
        on conflict (salao_id, chave) do nothing;
        n := n + 1;
      end if;
    end if;
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
            (salao_id, tipo, destino, profissional_id, quando, corpo, chave,
             modelo, variaveis)
          values (s.id, 'resumo', v_tel, pr.id, p_agora, v_corpo,
                  'resumo:' || pr.id || ':' || v_hoje,
                  public.modelo_de('resumo'),
                  jsonb_build_array(
                    public.variavel_limpa(
                      (select nome from public.saloes where id = s.id)),
                    public.variavel_lista(v_corpo)))
          on conflict (salao_id, chave) do nothing;
          n := n + 1;
        end if;
      end loop;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.gerar_resumos(timestamptz) from public, anon, authenticated;
revoke all on function public.pecas_agendamento(uuid)
  from public, anon, authenticated;
revoke all on function public.texto_agendamento(uuid, text)
  from public, anon, authenticated;
revoke all on function public.variaveis_agendamento(uuid, text)
  from public, anon, authenticated;
revoke all on function public.texto_resumo(uuid, uuid, date, text)
  from public, anon, authenticated;
comment on table public.notificacoes is
  'Fila das mensagens que nascem da agenda: confirmação, lembrete, resumo e aviso ao profissional.';
comment on function public.gerar_resumos(timestamptz) is
  'Põe o resumo do dia na fila para os salões cuja hora já chegou. Idempotente por dia.';

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes',  100, 'max_servicos',  10, 'mensagens_mes',   0)
  where codigo = 'gratuito';
update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes',  500, 'max_servicos',  50, 'mensagens_mes', 300)
  where codigo in ('trial','individual');
update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 1000, 'max_servicos', 100, 'mensagens_mes', 600)
  where codigo = 'duo';
update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 2000, 'max_servicos', 200, 'mensagens_mes',1000)
  where codigo = 'time';
update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 3500, 'max_servicos', 350, 'mensagens_mes',1500)
  where codigo = 'equipe';
update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 5000, 'max_servicos', 500, 'mensagens_mes',2000)
  where codigo = 'salao';
create or replace function public.mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int
    from public.notificacoes n
    join public.saloes s on s.id = n.salao_id
   where n.salao_id = p_salao
     and n.status in ('enviado','entregue','lido')
     and n.enviado_em >= (date_trunc('month',
           now() at time zone coalesce(s.fuso, 'America/Sao_Paulo')))
           at time zone coalesce(s.fuso, 'America/Sao_Paulo')
$$;
create or replace function public.teto_mensagens(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select public.recurso_num(p_salao, 'mensagens_mes')
$$;
create or replace function public.pode_enviar(p_salao uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when public.teto_mensagens(p_salao) is null then true
    else public.mensagens_no_mes(p_salao) < public.teto_mensagens(p_salao)
  end
$$;
revoke all on function public.mensagens_no_mes(uuid) from public, anon;
revoke all on function public.teto_mensagens(uuid)   from public, anon;
revoke all on function public.pode_enviar(uuid)      from public, anon;
grant execute on function public.mensagens_no_mes(uuid) to authenticated;
grant execute on function public.teto_mensagens(uuid)   to authenticated;
grant execute on function public.pode_enviar(uuid)      to authenticated;
create or replace function public.checar_limite_clientes()
returns trigger language plpgsql security definer set search_path = public as $$
declare teto int; usados int;
begin
  teto := public.recurso_num(new.salao_id, 'max_clientes');
  if teto is null then return new; end if;
  select count(*) into usados from public.clientes where salao_id = new.salao_id;
  if usados >= teto then
    raise exception 'O seu plano cobre % clientes, e o salão já tem %. Mude de plano para cadastrar mais.',
      teto, usados using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists tg_limite_clientes on public.clientes;
create trigger tg_limite_clientes before insert on public.clientes
  for each row execute function public.checar_limite_clientes();
create or replace function public.checar_limite_servicos()
returns trigger language plpgsql security definer set search_path = public as $$
declare teto int; usados int;
begin
  teto := public.recurso_num(new.salao_id, 'max_servicos');
  if teto is null then return new; end if;
  select count(*) into usados from public.servicos where salao_id = new.salao_id;
  if usados >= teto then
    raise exception 'O seu plano cobre % serviços, e o salão já tem %. Mude de plano para cadastrar mais.',
      teto, usados using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists tg_limite_servicos on public.servicos;
create trigger tg_limite_servicos before insert on public.servicos
  for each row execute function public.checar_limite_servicos();
create or replace function public.uso_do_plano(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_plano text;
  v_nome  text;
  v_preco numeric;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  select a.plano, pl.nome, pl.preco_mes into v_plano, v_nome, v_preco
    from public.assinaturas a
    join public.planos pl on pl.codigo = a.plano
   where a.salao_id = p_salao;
  return jsonb_build_object(
    'plano', v_plano, 'nome', v_nome, 'precoMes', v_preco,
    'profissionais', jsonb_build_object(
      'usado', (select count(*) from public.profissionais
                 where salao_id = p_salao and ativo),
      'teto',  (select max_profissionais from public.planos where codigo = v_plano)),
    'clientes', jsonb_build_object(
      'usado', (select count(*) from public.clientes where salao_id = p_salao),
      'teto',  public.recurso_num(p_salao, 'max_clientes')),
    'servicos', jsonb_build_object(
      'usado', (select count(*) from public.servicos where salao_id = p_salao),
      'teto',  public.recurso_num(p_salao, 'max_servicos')),
    'mensagens', jsonb_build_object(
      'usado', public.mensagens_no_mes(p_salao),
      'teto',  public.teto_mensagens(p_salao)));
end $$;
revoke all on function public.uso_do_plano(uuid) from public, anon;
grant execute on function public.uso_do_plano(uuid) to authenticated;
drop function if exists public.notificacao_proxima(int);
create or replace function public.notificacao_proxima(p_lote int default 1)
returns table (id uuid, salao_id uuid, destino text, corpo text, tipo text,
               modelo text, variaveis jsonb)
language plpgsql security definer set search_path = public as $$
begin
  update public.notificacoes
     set status = 'cancelado', motivo = 'venceu antes de ser enviada'
   where status = 'pendente' and quando < now() - interval '6 hours';
  return query
  with alvo as (
    select n.id
      from public.notificacoes n
     where n.status = 'pendente'
       and n.quando <= now()
       and (n.proxima_em is null or n.proxima_em <= now())
       and public.pode_enviar(n.salao_id)
     order by n.quando
     limit greatest(1, p_lote)
     for update skip locked)
  update public.notificacoes n
     set status = 'enviando', tentativas = n.tentativas + 1, proxima_em = null
    from alvo
   where n.id = alvo.id
  returning n.id, n.salao_id, n.destino, n.corpo, n.tipo,
            n.modelo, n.variaveis;
end $$;
create or replace function public.notificacao_resultado(
  p_id uuid, p_ok boolean, p_wam_id text default null,
  p_codigo text default null, p_msg text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.notificacoes%rowtype;
begin
  select * into v from public.notificacoes where id = p_id;
  if v.id is null then return; end if;
  if p_ok then
    update public.notificacoes
       set status = 'enviado', enviado_em = now(), wam_id = p_wam_id,
           erro_codigo = null, erro_msg = null
     where id = p_id;
  elsif v.tentativas >= 3 then
    update public.notificacoes
       set status = 'falhou', erro_codigo = p_codigo, erro_msg = p_msg
     where id = p_id;
  else
    update public.notificacoes
       set status = 'pendente', erro_codigo = p_codigo, erro_msg = p_msg,
           proxima_em = now() + make_interval(mins => v.tentativas * 5)
     where id = p_id;
  end if;
end $$;
drop function if exists public.notificacao_status(text, text);
create or replace function public.notificacao_status(
  p_wam_id text, p_status text,
  p_codigo text default null, p_msg text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_status = 'falhou' then
    update public.notificacoes
       set status = 'falhou', erro_codigo = p_codigo, erro_msg = p_msg
     where wam_id = p_wam_id and status = 'enviado';
    return;
  end if;
  if p_status not in ('entregue','lido') then return; end if;
  update public.notificacoes
     set status = p_status
   where wam_id = p_wam_id
     and status in ('enviado','entregue')
     and (p_status = 'lido' or status = 'enviado');
end $$;
revoke all on function public.notificacao_proxima(int)
  from public, anon, authenticated;
revoke all on function public.notificacao_resultado(uuid, boolean, text, text, text)
  from public, anon, authenticated;
revoke all on function public.notificacao_status(text, text, text, text)
  from public, anon, authenticated;
comment on function public.uso_do_plano(uuid) is
  'Uso e teto de profissionais, clientes, serviços e mensagens do mês, num jsonb só.';
comment on function public.notificacao_proxima(int) is
  'Fila do worker. Só service_role: contorna o RLS para atender todos os salões.';
comment on function public.notificacao_status(text, text, text, text) is
  'Webhook de status da Meta: entregue, lido e falhou, casados pelo wam_id. Nunca anda para trás.';
