-- ===========================================================================
-- 38_suporte.sql — o modo suporte: a plataforma abre o painel de um salão
--
-- O pedido: "se o dono do salão precisa de suporte, como faço?" — e, entre
-- abrir já editando ou abrir só olhando, "só leitura com liberar edição".
--
-- ── POR QUE ISTO MORA NO BANCO, E NÃO SÓ NA TELA ──────────────────────────
-- A conta da plataforma (`perfis.super_admin`) já podia ler e escrever em
-- qualquer salão: `e_gestor()`, `e_equipe()` e companhia respondem sim para
-- ela. O painel escondia os salões dos outros (o `sohMeusSaloes()` do
-- app.html) justamente para ela não mexer na agenda de um cliente achando
-- que era a dela. Abrir o painel de um cliente sem trava nenhuma seria
-- devolver exatamente esse risco.
--
-- Então a trava é um gatilho nas tabelas do salão: quando quem grava é a
-- conta da plataforma, num salão em que ela NÃO trabalha, a gravação só
-- passa com uma sessão de suporte aberta e a edição liberada nas últimas
-- duas horas. Sem isso, o banco recusa com uma frase que a tela mostra.
-- E o que passa fica registrado (antes e depois), por sessão.
--
-- O que NÃO é tocado:
--   · o dono, a equipe e a cliente: o gatilho sai na primeira linha;
--   · o worker, o webhook e o SQL Editor: não têm `auth.uid()` de plataforma;
--   · as funções da plataforma (`definir_status_salao()`, mudar plano,
--     estender teste): marcam a transação como "da plataforma", e passam.
--     Assinatura e cobrança nem têm o gatilho — são da plataforma por
--     natureza.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O REGISTRO
-- ---------------------------------------------------------------------------
create table if not exists public.suporte_acessos (
  id             uuid primary key default gen_random_uuid(),
  salao_id       uuid not null references public.saloes(id) on delete cascade,
  perfil_id      uuid not null references public.perfis(id) on delete cascade,
  iniciado_em    timestamptz not null default now(),
  edicao_desde   timestamptz,          -- quando "Liberar edição" foi apertado
  encerrado_em   timestamptz
);
create index if not exists ix_suporte_acessos_salao on public.suporte_acessos(salao_id, iniciado_em desc);

create table if not exists public.suporte_alteracoes (
  id          bigint generated always as identity primary key,
  acesso_id   uuid not null references public.suporte_acessos(id) on delete cascade,
  salao_id    uuid not null references public.saloes(id) on delete cascade,
  tabela      text not null,
  operacao    text not null,
  registro    text,
  antes       jsonb,
  depois      jsonb,
  quando      timestamptz not null default now()
);
create index if not exists ix_suporte_alteracoes_acesso on public.suporte_alteracoes(acesso_id);

alter table public.suporte_acessos enable row level security;
alter table public.suporte_acessos force row level security;
alter table public.suporte_alteracoes enable row level security;
alter table public.suporte_alteracoes force row level security;

/* Quem LÊ: a plataforma, e a GESTÃO do próprio salão — o dono tem direito de
   saber quando o suporte entrou na casa dele e o que mudou. Quem ESCREVE:
   ninguém direto; só as funções abaixo e o gatilho. */
drop policy if exists suporte_acessos_ler on public.suporte_acessos;
create policy suporte_acessos_ler on public.suporte_acessos for select to authenticated
  using ( public.is_super() or public.e_gestor(salao_id) );
drop policy if exists suporte_alteracoes_ler on public.suporte_alteracoes;
create policy suporte_alteracoes_ler on public.suporte_alteracoes for select to authenticated
  using ( public.is_super() or public.e_gestor(salao_id) );
revoke all on public.suporte_acessos, public.suporte_alteracoes from anon, authenticated;
grant select on public.suporte_acessos, public.suporte_alteracoes to authenticated;

-- ---------------------------------------------------------------------------
-- 2) ENTRAR, LIBERAR, SAIR
-- ---------------------------------------------------------------------------
create or replace function public.iniciar_suporte(p_salao uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_nome text;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma abre o painel de outro salão.' using errcode = 'insufficient_privilege';
  end if;
  select nome into v_nome from public.saloes where id = p_salao;
  if v_nome is null then
    raise exception 'Salão não encontrado.' using errcode = 'check_violation';
  end if;
  -- Uma sessão por vez, por salão: a anterior que ficou aberta (aba fechada
  -- sem "Sair") é encerrada aqui, e a edição dela não vale mais.
  update public.suporte_acessos set encerrado_em = now()
   where perfil_id = auth.uid() and salao_id = p_salao and encerrado_em is null;
  insert into public.suporte_acessos (salao_id, perfil_id) values (p_salao, auth.uid())
  returning id into v_id;
  return jsonb_build_object('acesso', v_id, 'salao', p_salao, 'nome', v_nome);
end $$;

create or replace function public.liberar_edicao_suporte(p_acesso uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.suporte_acessos;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma libera edição.' using errcode = 'insufficient_privilege';
  end if;
  select * into v from public.suporte_acessos where id = p_acesso and perfil_id = auth.uid();
  if v.id is null or v.encerrado_em is not null then
    raise exception 'Esta sessão de suporte já foi encerrada. Abra o painel de novo pelo admin.'
      using errcode = 'check_violation';
  end if;
  update public.suporte_acessos set edicao_desde = now() where id = p_acesso;
  return jsonb_build_object('ok', true, 'ate', now() + interval '2 hours');
end $$;

create or replace function public.encerrar_suporte(p_acesso uuid)
returns void language sql security definer set search_path = public as $$
  update public.suporte_acessos set encerrado_em = now()
   where id = p_acesso and perfil_id = auth.uid() and encerrado_em is null
$$;

/* Os acessos recentes, para o admin.html: quem, quando, se liberou edição e
   quantas alterações saíram. */
create or replace function public.acessos_de_suporte(p_limite int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os acessos.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(x order by x->>'iniciadoEm' desc) from (
      select jsonb_build_object(
        'id', a.id, 'salao', s.nome, 'slug', s.slug,
        'quem', coalesce(p.nome, '—'),
        'iniciadoEm', a.iniciado_em, 'edicaoDesde', a.edicao_desde, 'encerradoEm', a.encerrado_em,
        'alteracoes', (select count(*) from public.suporte_alteracoes x where x.acesso_id = a.id)) as x
        from public.suporte_acessos a
        join public.saloes s on s.id = a.salao_id
        left join public.perfis p on p.id = a.perfil_id
       order by a.iniciado_em desc
       limit greatest(1, least(coalesce(p_limite, 30), 200))) t), '[]'::jsonb);
end $$;

/* Estender o teste de um salão até uma data. Volta a ser teste mesmo que já
   tenha vencido (a casa estava no Grátis e ganha mais dias). */
create or replace function public.estender_teste(p_salao uuid, p_ate date)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma estende teste.' using errcode = 'insufficient_privilege';
  end if;
  if p_ate is null or p_ate < current_date then
    raise exception 'Escolha uma data de hoje em diante.' using errcode = 'check_violation';
  end if;
  if p_ate > current_date + 90 then
    raise exception 'Teste de mais de 90 dias não é teste: mude o plano.' using errcode = 'check_violation';
  end if;
  perform set_config('agendapro.plataforma', 'sim', true);
  insert into public.assinaturas (salao_id, plano, status, trial_ate, atualizado_em)
       values (p_salao, 'trial', 'trial', p_ate, now())
  on conflict (salao_id) do update
     set plano = 'trial', status = 'trial', trial_ate = p_ate, vence_em = null, atualizado_em = now();
  return jsonb_build_object('ok', true, 'salao', p_salao, 'trialAte', p_ate,
                            'planoEfetivo', public.plano_efetivo(p_salao));
end $$;

-- ---------------------------------------------------------------------------
-- 3) A TRAVA, E O REGISTRO DO QUE MUDOU
-- ---------------------------------------------------------------------------
/* O salão de uma linha qualquer: pela coluna `salao_id`, ou pela mãe — a
   jornada é da profissional, o item é da comanda, a sessão é do pacote. */
create or replace function public.salao_da_linha(p_tabela text, p_linha jsonb)
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  if p_linha ? 'salao_id' then return (p_linha->>'salao_id')::uuid; end if;
  case p_tabela
    when 'saloes' then return (p_linha->>'id')::uuid;
    when 'jornadas' then select salao_id into v from public.profissionais where id = (p_linha->>'profissional_id')::uuid;
    when 'servicos_profissionais' then
      select salao_id into v from public.servicos where id = (p_linha->>'servico_id')::uuid;
    when 'produtos_profissionais', 'estoque_mov' then
      select salao_id into v from public.produtos where id = (p_linha->>'produto_id')::uuid;
    when 'pacote_servicos', 'pacote_clientes' then
      select salao_id into v from public.pacotes where id = (p_linha->>'pacote_id')::uuid;
    when 'agendamento_servicos' then select salao_id into v from public.agendamentos where id = (p_linha->>'agendamento_id')::uuid;
    when 'comanda_itens', 'pagamentos' then select salao_id into v from public.comandas where id = (p_linha->>'comanda_id')::uuid;
    when 'pedido_itens' then select salao_id into v from public.pedidos where id = (p_linha->>'pedido_id')::uuid;
    else v := null;
  end case;
  return v;
end $$;

create or replace function public.tg_suporte()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_linha jsonb; v_salao uuid; v_acesso uuid;
begin
  -- Quem não é a plataforma passa direto: é a imensa maioria das gravações.
  if auth.uid() is null or not public.is_super() then return null; end if;
  if coalesce(current_setting('agendapro.plataforma', true), '') = 'sim' then return null; end if;
  v_linha := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  v_salao := public.salao_da_linha(tg_table_name, v_linha);
  if v_salao is null then return null; end if;
  -- A conta da plataforma que também trabalha num salão (o dela) mexe nele
  -- como qualquer dono. Vínculo de cliente não conta.
  if public.papel_no_salao(v_salao) in ('dono','admin','recepcao','profissional') then return null; end if;

  select id into v_acesso from public.suporte_acessos
   where perfil_id = auth.uid() and salao_id = v_salao and encerrado_em is null
     and edicao_desde is not null and edicao_desde > now() - interval '2 hours'
   order by edicao_desde desc limit 1;
  if v_acesso is null then
    raise exception 'Modo suporte: só leitura. Toque em "Liberar edição" para mexer neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.suporte_alteracoes (acesso_id, salao_id, tabela, operacao, registro, antes, depois)
  values (v_acesso, v_salao, tg_table_name, tg_op, v_linha->>'id',
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end $$;

/* As tabelas do salão. De fora, de propósito: assinaturas, cobranças e o
   documento do dono (da plataforma e do faturamento), a fila de mensagens
   (é o sistema que escreve, e ela já vem atrás de um agendamento que passou
   pela trava) e os próprios registros. */
do $$
declare t text;
begin
  foreach t in array array[
    'saloes', 'profissionais', 'jornadas', 'servicos', 'servicos_profissionais', 'clientes',
    'agendamentos', 'agendamento_servicos', 'bloqueios', 'lista_espera', 'produtos',
    'produtos_profissionais', 'estoque_mov', 'pacotes', 'pacote_servicos', 'pacote_clientes',
    'cupons', 'cupom_usos', 'comandas', 'comanda_itens', 'pagamentos', 'caixas',
    'caixa_movimentos', 'estornos', 'precos_regras', 'campanhas', 'campanha_destinatarios',
    'vinculos', 'convites_equipe', 'pedidos', 'pedido_itens']
  loop
    if to_regclass('public.' || t) is not null then
      execute format('drop trigger if exists zz_suporte on public.%I', t);
      execute format('create trigger zz_suporte after insert or update or delete on public.%I'
                     || ' for each row execute function public.tg_suporte()', t);
    end if;
  end loop;
end $$;

-- As funções da plataforma que gravam em tabela do salão passam pela trava
-- marcadas como da plataforma. Suspender é a única hoje.
create or replace function public.definir_status_salao(p_salao uuid, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_antes text;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma suspende salão.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_status not in ('ativo','suspenso','cancelado') then
    raise exception 'Status % não existe.', p_status using errcode = 'check_violation';
  end if;

  select status into v_antes from public.saloes where id = p_salao;
  if v_antes is null then
    raise exception 'Salão não encontrado.' using errcode = 'check_violation';
  end if;

  perform set_config('agendapro.plataforma', 'sim', true);
  update public.saloes set status = p_status where id = p_salao;

  return jsonb_build_object('salaoId', p_salao, 'de', v_antes, 'para', p_status);
end $$;

-- ---------------------------------------------------------------------------
-- 4) QUEM PODE CHAMAR
-- ---------------------------------------------------------------------------
revoke all on function public.iniciar_suporte(uuid) from public, anon;
revoke all on function public.liberar_edicao_suporte(uuid) from public, anon;
revoke all on function public.encerrar_suporte(uuid) from public, anon;
revoke all on function public.acessos_de_suporte(int) from public, anon;
revoke all on function public.estender_teste(uuid, date) from public, anon;
revoke all on function public.salao_da_linha(text, jsonb) from public, anon, authenticated;
revoke all on function public.tg_suporte() from public, anon, authenticated;
revoke all on function public.definir_status_salao(uuid, text) from public;
grant execute on function public.iniciar_suporte(uuid) to authenticated;
grant execute on function public.liberar_edicao_suporte(uuid) to authenticated;
grant execute on function public.encerrar_suporte(uuid) to authenticated;
grant execute on function public.acessos_de_suporte(int) to authenticated;
grant execute on function public.estender_teste(uuid, date) to authenticated;
grant execute on function public.definir_status_salao(uuid, text) to authenticated;
