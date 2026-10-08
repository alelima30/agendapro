-- ===========================================================================
-- AgendaPro — 34: CUPONS DE DESCONTO (agendamento no link e loja)
--
-- O salão cria um código — BEMVINDA10, NATAL15 — e a cliente digita no link:
-- na tela "Confira seu agendamento" e no carrinho da loja.
--
-- As regras que o dono escolhe:
--   · desconto em % ou em valor (R$);
--   · onde vale: agendamento, produtos, ou os dois;
--   · só alguns serviços (vazio = todos);
--   · validade: de / até (dias do salão);
--   · limite total de usos, e/ou 1 uso por cliente.
--
-- ⚠ O DESCONTO SAI DAQUI, NUNCA DO NAVEGADOR. A tela pergunta
-- (`conferir_cupom`) para mostrar o valor antes de confirmar, mas quem grava
-- é o `agendar()` (09_cliente.sql), que recalcula tudo na hora de marcar. Um
-- navegador que mandasse "desconto: 50" não teria onde mandar.
--
-- ⚠ O ITEM DO AGENDAMENTO CONTINUA COM O PREÇO CHEIO. O desconto mora em
-- `agendamentos.desconto` (e o `valor_previsto` já sai com ele descontado):
-- a comissão é calculada sobre o serviço, e o relatório sabe quanto o cupom
-- custou ao salão. A comanda nasce com o mesmo desconto (painel e 28).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O cupom
-- ---------------------------------------------------------------------------
create table if not exists public.cupons (
  id               uuid primary key default gen_random_uuid(),
  salao_id         uuid not null references public.saloes(id) on delete cascade,
  codigo           text not null,
  tipo             text not null default 'pct' check (tipo in ('pct', 'valor')),
  valor            numeric(10,2) not null check (valor > 0),
  vale_agendamento boolean not null default true,
  vale_produtos    boolean not null default false,
  -- Nulo ou vazio = todos os serviços. Só pesa no agendamento.
  servicos         uuid[],
  inicio           date,
  fim              date,
  limite_total     int check (limite_total is null or limite_total > 0),
  um_por_cliente   boolean not null default true,
  ativo            boolean not null default true,
  criado_em        timestamptz not null default now(),
  constraint cupom_pct_ate_100 check (tipo <> 'pct' or valor <= 100),
  constraint cupom_codigo_forma check (codigo ~ '^[A-Z0-9_-]{3,30}$'),
  constraint cupom_periodo check (fim is null or inicio is null or fim >= inicio),
  constraint cupom_vale_algo check (vale_agendamento or vale_produtos)
);
create unique index if not exists ux_cupom_codigo on public.cupons (salao_id, codigo);

/* O código é guardado em MAIÚSCULAS e sem espaço, pelo banco. A cliente
   digita "bemvinda10 " no celular e tem que valer; e dois cupons "Natal" e
   "NATAL" no mesmo salão seriam o mesmo para quem digita. */
create or replace function public.tg_cupom_codigo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.codigo := upper(regexp_replace(coalesce(new.codigo, ''), '\s', '', 'g'));
  return new;
end $$;
drop trigger if exists tg_cupom_codigo on public.cupons;
create trigger tg_cupom_codigo before insert or update of codigo on public.cupons
  for each row execute function public.tg_cupom_codigo();

-- ---------------------------------------------------------------------------
-- 2) Cada uso
--
-- Um uso do agendamento aponta para ele, e só CONTA enquanto o agendamento
-- valer: cancelado ou arquivado devolve o uso (a cliente desmarcou; o cupom
-- não pode morrer por isso). Apagado, o uso vai junto (cascade).
-- ---------------------------------------------------------------------------
create table if not exists public.cupom_usos (
  id             uuid primary key default gen_random_uuid(),
  cupom_id       uuid not null references public.cupons(id) on delete cascade,
  salao_id       uuid not null references public.saloes(id) on delete cascade,
  origem         text not null check (origem in ('agendamento', 'produtos')),
  agendamento_id uuid references public.agendamentos(id) on delete cascade,
  -- Nacional, só dígitos (sem o 55): é por ele que "1 por cliente" compara.
  telefone       text,
  desconto       numeric(10,2) not null default 0,
  criado_em      timestamptz not null default now()
);
create index if not exists ix_cupom_usos_cupom on public.cupom_usos (cupom_id);

/* A CONTA que usou (`auth.uid()`). Na loja é ela que identifica a cliente: o
   cupom da loja só vale com a cliente dentro da conta (6), e quem só compra
   pode nem ter ficha no salão — sem ficha não há telefone para o "1 por
   cliente" comparar. O padrão preenche sozinho, também no `agendar()` de quem
   está logada; sem login fica nulo. Coluna e padrão em dois passos: o padrão
   não reescreve as linhas que já existiam. */
alter table public.cupom_usos
  add column if not exists perfil_id uuid references auth.users(id) on delete set null;
alter table public.cupom_usos alter column perfil_id set default auth.uid();
create index if not exists ix_cupom_usos_perfil on public.cupom_usos (cupom_id, perfil_id);

-- ---------------------------------------------------------------------------
-- 3) O agendamento guarda o cupom e quanto ele descontou
-- ---------------------------------------------------------------------------
alter table public.agendamentos
  add column if not exists cupom_id uuid references public.cupons(id) on delete set null;
alter table public.agendamentos
  add column if not exists desconto numeric(10,2) not null default 0;

-- ---------------------------------------------------------------------------
-- 4) A conta — uma função só, para a prévia da tela e para a gravação
--
-- Devolve jsonb: { cupom_id, codigo, desconto, base, motivo, rotulo }.
-- `motivo` não nulo = não vale, e ele já vem escrito para a cliente ler.
--
-- `p_travar`: dentro do `agendar()` o cupom é travado (`for update`) antes
-- de contar os usos — duas clientes usando o último cupom no mesmo segundo
-- não podem passar as duas.
--
-- ⚠ Cupom desligado e cupom que não existe dão a MESMA resposta: senão a tela
-- diria a quem chuta códigos quais existem.
-- ---------------------------------------------------------------------------
create or replace function public.cupom_calcular(
  p_salao        uuid,
  p_codigo       text,
  p_origem       text,
  p_servicos     uuid[],
  p_profissional uuid,
  p_inicio       timestamptz,
  p_itens        jsonb,
  p_tel          text,
  p_cliente      uuid,
  p_travar       boolean default false)
-- Volátil, e não `stable`: com `p_travar` ela trava a linha (`for update`), e o
-- Postgres não deixa função `stable` fazer isso.
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c        public.cupons%rowtype;
  v_cod    text := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  v_hoje   date;
  v_tel    text := nullif(public.telefone_nacional(p_tel), '');
  v_base   numeric(10,2) := 0;
  v_desc   numeric(10,2);
  v_usos   int;
  v_rotulo text;
  it       record;
begin
  if v_cod = '' or p_salao is null then
    return jsonb_build_object('motivo', 'Digite o código do cupom.');
  end if;

  select * into c from public.cupons x
   where x.salao_id = p_salao and x.codigo = v_cod and x.ativo;
  if not found then
    return jsonb_build_object('motivo', 'Cupom não encontrado. Confira as letras e os números.');
  end if;
  if p_travar then
    perform 1 from public.cupons x where x.id = c.id for update;
  end if;

  select (now() at time zone coalesce(s.fuso, 'America/Sao_Paulo'))::date into v_hoje
    from public.saloes s where s.id = p_salao;

  if c.inicio is not null and v_hoje < c.inicio then
    return jsonb_build_object('motivo', 'Este cupom começa a valer em '
      || to_char(c.inicio, 'DD/MM/YYYY') || '.');
  end if;
  if c.fim is not null and v_hoje > c.fim then
    return jsonb_build_object('motivo', 'Este cupom venceu em '
      || to_char(c.fim, 'DD/MM/YYYY') || '.');
  end if;
  if p_origem = 'agendamento' and not c.vale_agendamento then
    return jsonb_build_object('motivo', 'Este cupom vale só para os produtos da loja.');
  end if;
  if p_origem = 'produtos' and not c.vale_produtos then
    return jsonb_build_object('motivo', 'Este cupom vale só para agendamento.');
  end if;

  -- Os usos que contam: produto sempre; agendamento enquanto ele valer.
  if c.limite_total is not null then
    select count(*) into v_usos
      from public.cupom_usos u
      left join public.agendamentos a on a.id = u.agendamento_id
     where u.cupom_id = c.id
       and (u.agendamento_id is null
            or (a.status <> 'cancelado' and a.arquivado_em is null));
    if v_usos >= c.limite_total then
      return jsonb_build_object('motivo', 'Este cupom já foi usado o máximo de vezes.');
    end if;
  end if;

  if c.um_por_cliente and (v_tel is not null or p_cliente is not null) then
    if exists (
      select 1 from public.cupom_usos u
        left join public.agendamentos a on a.id = u.agendamento_id
       where u.cupom_id = c.id
         and (u.agendamento_id is null
              or (a.status <> 'cancelado' and a.arquivado_em is null))
         and ((v_tel is not null and u.telefone = v_tel)
              or (p_cliente is not null and a.cliente_id = p_cliente)))
    then
      return jsonb_build_object('motivo', 'Você já usou este cupom.');
    end if;
  end if;

  -- A base: o que o cupom alcança.
  if p_origem = 'agendamento' then
    for it in select distinct s from unnest(coalesce(p_servicos, '{}')) s loop
      if c.servicos is null or cardinality(c.servicos) = 0 or it.s = any(c.servicos) then
        v_base := v_base + coalesce(public.preco_do_servico(it.s, p_profissional, p_inicio), 0);
      end if;
    end loop;
    if v_base <= 0 then
      return jsonb_build_object('motivo', 'Este cupom não vale para os serviços escolhidos.');
    end if;
  else
    select coalesce(sum(p.preco * least(greatest(coalesce((e->>'qtd')::int, 1), 1), 99)), 0)
      into v_base
      from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
      join public.produtos p on p.id = (e->>'id')::uuid
     where p.salao_id = p_salao and p.ativo and p.venda_online and p.preco is not null;
    if v_base <= 0 then
      return jsonb_build_object('motivo', 'Escolha um produto com preço antes de usar o cupom.');
    end if;
  end if;

  v_desc := case when c.tipo = 'pct' then round(v_base * c.valor / 100, 2)
                 else least(c.valor, v_base) end;
  -- Vírgula escrita à mão: o `to_char` com D depende do idioma do banco.
  v_rotulo := case when c.tipo = 'pct'
                then replace(trim(trailing '.' from trim(trailing '0' from c.valor::text)), '.', ',') || '%'
                else 'R$ ' || replace(to_char(c.valor, 'FM999999990.00'), '.', ',') end;

  return jsonb_build_object('cupom_id', c.id, 'codigo', c.codigo, 'desconto', v_desc,
                            'base', v_base, 'rotulo', v_rotulo, 'motivo', null);
end $$;

-- ---------------------------------------------------------------------------
-- 5) A prévia, para a tela do link
--
-- O que a cliente vê ANTES de confirmar. Não grava nada; o `agendar()` refaz
-- a conta na hora de marcar. Não devolve o id do cupom: a tela não precisa.
--
-- ⚠ SEM TELEFONE DIGITADO. "1 por cliente" aqui só olha a conta de quem está
-- logado (a ficha dela neste salão). Aceitar um telefone qualquer faria desta
-- função, aberta a qualquer um, um jeito de perguntar "o número tal já usou
-- o cupom tal?". Quem não entrou na conta vê a recusa na hora de marcar —
-- o `agendar()` confere pelo WhatsApp que ela mesma informou.
-- ---------------------------------------------------------------------------
create or replace function public.cupom_minha_ficha(p_salao uuid,
                                                    out telefone text, out cliente_id uuid)
language sql stable security definer set search_path = public as $$
  select c.telefone, c.id from public.clientes c
   where c.salao_id = p_salao and auth.uid() is not null and c.perfil_id = auth.uid()
   limit 1
$$;

create or replace function public.conferir_cupom(
  p_salao        uuid,
  p_codigo       text,
  p_origem       text,
  p_servicos     uuid[]      default null,
  p_profissional uuid        default null,
  p_inicio       timestamptz default null,
  p_itens        jsonb       default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; eu record;
begin
  if p_origem not in ('agendamento', 'produtos') then
    return jsonb_build_object('ok', false, 'motivo', 'Cupom não encontrado. Confira as letras e os números.');
  end if;
  -- Na loja, só com a cliente dentro da conta (6).
  if p_origem = 'produtos' then
    r := public.cupom_loja_da_conta(p_salao, p_codigo, false);
    if r is not null then return r; end if;
  end if;
  select * into eu from public.cupom_minha_ficha(p_salao);
  r := public.cupom_calcular(p_salao, p_codigo, p_origem, p_servicos, p_profissional,
                             p_inicio, p_itens, eu.telefone, eu.cliente_id, false);
  return jsonb_build_object('ok', r->>'motivo' is null, 'codigo', r->>'codigo',
    'desconto', coalesce((r->>'desconto')::numeric, 0), 'rotulo', r->>'rotulo',
    'motivo', r->>'motivo');
end $$;

-- ---------------------------------------------------------------------------
-- 6) O cupom no pedido da loja — SÓ COM A CLIENTE DENTRO DA CONTA
--
-- O pedido vai pelo WhatsApp, e o salão fecha preço e pagamento na conversa.
-- Ainda assim o uso é REGISTRADO aqui, na hora de enviar: é ele que conta
-- para o limite total.
--
-- ⚠ POR QUE A CONTA. Aberta a qualquer um, esta função gastava o cupom sem
-- pedido nenhum: chamada em repetição por fora do link, ela registrava um uso
-- por chamada até o limite, e o cupom do salão morria antes de a primeira
-- cliente de verdade chegar (achado pelo caça-bug; decisão do dono do
-- produto: cupom na loja só com login). Com a conta:
--   · o mesmo pedido mandado de novo no MESMO DIA (ela corrigiu o carrinho)
--     não gasta outro uso — chamar em repetição não esgota nada;
--   · "1 por cliente" compara pela conta, mesmo para quem não tem ficha;
--   · cada uso tem dono (`perfil_id`), e o salão vê de quem foi.
-- ---------------------------------------------------------------------------
create or replace function public.cupom_loja_da_conta(p_salao uuid, p_codigo text,
                                                      p_travar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c      public.cupons%rowtype;
  v_uid  uuid := auth.uid();
  v_fuso text;
  v_ja   numeric(10,2);
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'entrar', true,
      'motivo', 'Entre na sua conta para usar o cupom na loja.');
  end if;

  select * into c from public.cupons x
   where x.salao_id = p_salao and x.ativo and x.vale_produtos
     and x.codigo = upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  -- Código que não existe: quem responde é a conta de sempre (cupom_calcular).
  if not found then return null; end if;
  if p_travar then
    perform 1 from public.cupons x where x.id = c.id for update;
  end if;

  -- O pedido de hoje, mandado de novo: o uso já está registrado.
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso
    from public.saloes s where s.id = p_salao;
  select u.desconto into v_ja from public.cupom_usos u
   where u.cupom_id = c.id and u.origem = 'produtos' and u.perfil_id = v_uid
     and (u.criado_em at time zone v_fuso)::date = (now() at time zone v_fuso)::date
   order by u.criado_em desc limit 1;
  if found then
    return jsonb_build_object('ok', true, 'motivo', null, 'codigo', c.codigo,
      'desconto', v_ja, 'repetido', true,
      'rotulo', case when c.tipo = 'pct'
                  then replace(trim(trailing '.' from trim(trailing '0' from c.valor::text)), '.', ',') || '%'
                  else 'R$ ' || replace(to_char(c.valor, 'FM999999990.00'), '.', ',') end);
  end if;

  -- 1 por cliente, pela conta (na loja ou num agendamento que ainda vale).
  if c.um_por_cliente and exists (
       select 1 from public.cupom_usos u
         left join public.agendamentos a on a.id = u.agendamento_id
        where u.cupom_id = c.id and u.perfil_id = v_uid
          and (u.agendamento_id is null
               or (a.status <> 'cancelado' and a.arquivado_em is null)))
  then
    return jsonb_build_object('ok', false, 'motivo', 'Você já usou este cupom.');
  end if;
  return null;
end $$;

create or replace function public.usar_cupom_no_pedido(
  p_salao    uuid,
  p_codigo   text,
  p_itens    jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; eu record;
begin
  r := public.cupom_loja_da_conta(p_salao, p_codigo, true);
  if r is not null then return r; end if;
  select * into eu from public.cupom_minha_ficha(p_salao);
  r := public.cupom_calcular(p_salao, p_codigo, 'produtos', null, null, null,
                             p_itens, eu.telefone, eu.cliente_id, true);
  if r->>'motivo' is not null then
    return jsonb_build_object('ok', false, 'motivo', r->>'motivo');
  end if;
  insert into public.cupom_usos (cupom_id, salao_id, origem, telefone, perfil_id, desconto)
       values ((r->>'cupom_id')::uuid, p_salao, 'produtos',
               nullif(public.telefone_nacional(eu.telefone), ''), auth.uid(),
               (r->>'desconto')::numeric);
  return jsonb_build_object('ok', true, 'codigo', r->>'codigo',
    'desconto', (r->>'desconto')::numeric, 'rotulo', r->>'rotulo');
end $$;

-- ---------------------------------------------------------------------------
-- 6b) O salão tem cupom valendo? — para o link decidir se mostra o campo
--
-- Sem isto, "Tem um cupom?" apareceria em todo salão, inclusive no que nunca
-- criou um, e a cliente ficaria procurando um código que não existe. Responde
-- só sim ou não, por lugar; nenhum código sai daqui.
-- ---------------------------------------------------------------------------
create or replace function public.salao_tem_cupom(p_salao uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  with hoje as (
    select (now() at time zone coalesce(s.fuso, 'America/Sao_Paulo'))::date as d
      from public.saloes s where s.id = p_salao
  )
  select jsonb_build_object(
    'agendamento', coalesce(bool_or(c.vale_agendamento), false),
    'produtos',    coalesce(bool_or(c.vale_produtos), false))
    from public.cupons c, hoje
   where c.salao_id = p_salao and c.ativo
     and (c.inicio is null or c.inicio <= hoje.d)
     and (c.fim is null or c.fim >= hoje.d)
$$;

-- ---------------------------------------------------------------------------
-- 6c) Remarcar pelo link, levando o cupom junto
--
-- Remarcar é marcar o novo e soltar o antigo — nessa ordem, para a cliente
-- não ficar sem nenhum dos dois. Só que, com o antigo ainda de pé, o "1 por
-- cliente" via o cupom já usado, e o horário novo saía pelo preço cheio: quem
-- tinha pago R$ 40 terminava em R$ 50 só por trocar o dia. Achado pelo
-- caça-bug, reproduzido no link e pela API.
--
-- Esta função faz as duas coisas de uma vez, no banco: solta o antigo (com a
-- mesma regra do `cancelar_agendamento()`, das duas horas) e passa o cupom e
-- o uso dele para o novo. É o MESMO uso que muda de horário, não um uso novo
-- — por isso não confere validade nem limite de novo, e o desconto é
-- recalculado para os serviços do horário novo.
--
-- ⚠ O novo precisa ser da mesma ficha, do mesmo salão, e recém-marcado; e o
-- antigo precisa estar de pé agora. Sem isso, um horário com cupom
-- desmarcado há meses viraria desconto em qualquer marcação nova.
-- ---------------------------------------------------------------------------
create or replace function public.remarcar_agendamento(p_token_antigo uuid, p_token_novo uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a      public.agendamentos%rowtype;
  n      public.agendamentos%rowtype;
  c      public.cupons%rowtype;
  v_base numeric(10,2) := 0;
  v_desc numeric(10,2) := 0;
  it     record;
begin
  select * into a from public.agendamentos where gerenciar_token = p_token_antigo for update;
  select * into n from public.agendamentos where gerenciar_token = p_token_novo for update;

  if a.id is null or n.id is null or a.id = n.id
     or n.salao_id <> a.salao_id or n.cliente_id is distinct from a.cliente_id
     or n.criado_em < now() - interval '30 minutes' then
    raise exception 'Não achei esse horário. Confira o link.' using errcode = 'check_violation';
  end if;
  if a.status not in ('pendente', 'confirmado') then
    raise exception 'Este horário já foi %.',
      case a.status when 'cancelado' then 'cancelado'
                    when 'concluido' then 'atendido' else a.status end
      using errcode = 'check_violation';
  end if;
  if a.inicio <= now() + interval '2 hours' then
    raise exception 'Faltam menos de 2 horas. Fale com o salão para desmarcar.'
      using errcode = 'check_violation';
  end if;

  update public.agendamentos
     set status = 'cancelado', cancelado_motivo = 'remarcado pelo cliente'
   where id = a.id;

  if a.cupom_id is not null and coalesce(a.desconto, 0) > 0
     and n.cupom_id is null and n.pacote_cliente_id is null
     and n.status in ('pendente', 'confirmado') then
    select * into c from public.cupons where id = a.cupom_id;
    if found then
      for it in select s.servico_id, s.preco from public.agendamento_servicos s
                 where s.agendamento_id = n.id loop
        if c.servicos is null or cardinality(c.servicos) = 0 or it.servico_id = any(c.servicos) then
          v_base := v_base + coalesce(it.preco, 0);
        end if;
      end loop;
      v_desc := case when c.tipo = 'pct' then round(v_base * c.valor / 100, 2)
                     else least(c.valor, v_base) end;
      v_desc := least(v_desc, n.valor_previsto);
      if v_desc > 0 then
        update public.agendamentos
           set cupom_id = c.id, desconto = v_desc, valor_previsto = valor_previsto - v_desc
         where id = n.id;
        update public.cupom_usos
           set agendamento_id = n.id, desconto = v_desc
         where agendamento_id = a.id;
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'desconto', v_desc);
end $$;

-- ---------------------------------------------------------------------------
-- 7) Quantas vezes cada cupom foi usado — para a lista do painel
-- ---------------------------------------------------------------------------
create or replace function public.usos_dos_cupons(p_salao uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(x.cupom_id, x.n), '{}'::jsonb)
    from (select u.cupom_id, count(*) as n
            from public.cupom_usos u
            left join public.agendamentos a on a.id = u.agendamento_id
           where u.salao_id = p_salao and public.e_equipe(p_salao)
             and (u.agendamento_id is null
                  or (a.status <> 'cancelado' and a.arquivado_em is null))
           group by u.cupom_id) x
$$;

-- ---------------------------------------------------------------------------
-- 8) Quem enxerga, quem escreve, quem chama
--
-- Os cupons são cadastro do salão: a equipe lê, o gestor escreve. A cliente
-- não lê a tabela — alcança só a prévia (`conferir_cupom`) e o pedido da loja
-- (`usar_cupom_no_pedido`), que respondem um código de cada vez.
-- `cupom_calcular`, `cupom_minha_ficha` e `cupom_loja_da_conta` não são de
-- ninguém: só o `agendar()` e as funções acima chamam.
-- ---------------------------------------------------------------------------
alter table public.cupons     enable row level security;
alter table public.cupom_usos enable row level security;

drop policy if exists cupons_ler on public.cupons;
create policy cupons_ler on public.cupons
  for select using (public.e_equipe(salao_id));
drop policy if exists cupons_escrever on public.cupons;
create policy cupons_escrever on public.cupons
  for all using (public.e_gestor(salao_id)) with check (public.e_gestor(salao_id));

drop policy if exists cupom_usos_ler on public.cupom_usos;
create policy cupom_usos_ler on public.cupom_usos
  for select using (public.e_equipe(salao_id));

grant select, insert, update, delete on public.cupons to authenticated;
grant select on public.cupom_usos to authenticated;
revoke all on public.cupons, public.cupom_usos from anon;

revoke all on function public.cupom_calcular(uuid, text, text, uuid[], uuid, timestamptz, jsonb, text, uuid, boolean)
  from public, anon, authenticated;
revoke all on function public.cupom_minha_ficha(uuid) from public, anon, authenticated;
revoke all on function public.cupom_loja_da_conta(uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.conferir_cupom(uuid, text, text, uuid[], uuid, timestamptz, jsonb) from public;
revoke all on function public.usar_cupom_no_pedido(uuid, text, jsonb) from public;
revoke all on function public.salao_tem_cupom(uuid) from public;
revoke all on function public.usos_dos_cupons(uuid) from public, anon;
grant execute on function public.conferir_cupom(uuid, text, text, uuid[], uuid, timestamptz, jsonb) to anon, authenticated;
grant execute on function public.usar_cupom_no_pedido(uuid, text, jsonb) to anon, authenticated;
grant execute on function public.salao_tem_cupom(uuid) to anon, authenticated;
-- Pelo segredo dos dois horários, como o `cancelar_agendamento()`: quem tem o
-- token é dona do horário.
revoke all on function public.remarcar_agendamento(uuid, uuid) from public;
grant execute on function public.remarcar_agendamento(uuid, uuid) to anon, authenticated;
grant execute on function public.usos_dos_cupons(uuid) to authenticated;
