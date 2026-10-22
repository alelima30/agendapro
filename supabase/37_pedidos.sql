-- ===========================================================================
-- 37_pedidos.sql — o modo Pedidos: restaurante, pizzaria, lanchonete
--
-- O pedido: "se for um restaurante? fosse fazer pedido não teria que mudar
-- invés de agendar e ser pedido? ... no pedido tem que a pessoa faça a
-- confirmação". Escolhida a versão completa: o pedido fica GRAVADO, o
-- estabelecimento acompanha numa tela (Recebido → Em preparo → Saiu para
-- entrega → Entregue), a cliente recebe a confirmação no WhatsApp quando ele
-- aceita, com taxa de entrega por bairro e pagamento na entrega.
--
-- ── ⚠ ISTO NÃO MEXE NA LOJA QUE JÁ EXISTE ──────────────────────────────────
-- A loja do salão (25_loja) continua exatamente como era: carrinho no
-- navegador e o texto indo pelo WhatsApp DA CLIENTE, sem gravar nada. O modo
-- Pedidos vale só para o tipo `restaurante`, e usa o MESMO cadastro de
-- produtos — no restaurante eles são o cardápio.
--
-- ── ⚠ O PREÇO É O DO BANCO, NUNCA O DA TELA ───────────────────────────────
-- A página manda só QUAIS itens e QUANTOS. Preço, subtotal, taxa de entrega,
-- pedido mínimo e total são calculados aqui, a partir do cadastro. Um carrinho
-- adulterado no navegador ("pizza a R$ 0,01") não muda um centavo do que fica
-- gravado. Regra da casa: valor financeiro não depende do frontend.
--
-- ── E A MENSAGEM SAI PELA FILA, NO SERVIDOR ───────────────────────────────
-- Aceitar, sair para entrega, ficar pronto e cancelar põem UMA linha na fila
-- `notificacoes` (21), com o modelo aprovado e as variáveis — e quem manda é
-- o worker `enviar-notificacoes`, com a cota do plano conferida lá. Nada sai
-- do navegador, e sem a conta da Meta ligada a linha fica "pendente", que é
-- a verdade. Os textos dos modelos novos estão no MODELOS.md.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O TIPO NOVO
-- O `check` do 01_schema só vale para quem instala do zero (é de um `create
-- table if not exists`). Aqui ele é refeito com o restaurante incluído.
-- ---------------------------------------------------------------------------
alter table public.saloes drop constraint if exists saloes_tipo_check;
alter table public.saloes add constraint saloes_tipo_check
  check (tipo in ('salao','barbearia','estetica','manicure',
                  'clinica','tatuagem','pet','outro','restaurante'));

-- ---------------------------------------------------------------------------
-- 2) AS TABELAS
-- ---------------------------------------------------------------------------
create table if not exists public.pedidos (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  -- 1, 2, 3... por estabelecimento (contadores, como a comanda).
  numero        bigint not null,
  -- A ficha da cliente no estabelecimento, quando deu para achar ou criar.
  -- Nome e telefone ficam TAMBÉM aqui: o pedido diz quem pediu mesmo que a
  -- ficha seja apagada ou que o plano não comporte ficha nova.
  cliente_id    uuid references public.clientes(id) on delete set null,
  nome          text not null,
  telefone      text not null,
  tipo_entrega  text not null check (tipo_entrega in ('entrega','retirada')),
  -- { rua, numero, complemento, bairro, referencia } — só na entrega.
  endereco      jsonb,
  bairro        text,
  subtotal      numeric(10,2) not null check (subtotal >= 0),
  taxa_entrega  numeric(10,2) not null default 0 check (taxa_entrega >= 0),
  total         numeric(10,2) not null check (total >= 0),
  pagamento     text not null check (pagamento in ('pix','dinheiro','cartao')),
  troco_para    numeric(10,2) check (troco_para is null or troco_para >= 0),
  observacao    text,
  status        text not null default 'recebido'
                check (status in ('recebido','em_preparo','saiu','pronto',
                                  'entregue','cancelado')),
  motivo        text,
  cancelado_por text check (cancelado_por in ('cliente','casa')),
  -- O segredo da cliente para acompanhar e cancelar, como o do agendamento:
  -- quem tem o token é quem pediu. O id nunca vai para a página.
  token         uuid not null default gen_random_uuid(),
  criado_em     timestamptz not null default now(),
  aceito_em     timestamptz,
  saiu_em       timestamptz,
  pronto_em     timestamptz,
  entregue_em   timestamptz,
  cancelado_em  timestamptz,
  unique (salao_id, numero)
);
create unique index if not exists ux_pedido_token on public.pedidos(token);
create index if not exists ix_pedido_salao on public.pedidos(salao_id, criado_em desc);
create index if not exists ix_pedido_aberto on public.pedidos(salao_id, status)
  where status not in ('entregue','cancelado');
create index if not exists ix_pedido_telefone on public.pedidos(salao_id, telefone)
  where status = 'recebido';

create table if not exists public.pedido_itens (
  id          uuid primary key default gen_random_uuid(),
  pedido_id   uuid not null references public.pedidos(id) on delete cascade,
  -- `set null`: tirar um item do cardápio não apaga o histórico do pedido.
  produto_id  uuid references public.produtos(id) on delete set null,
  -- Nome e preço COPIADOS na hora do pedido: mudar o cardápio amanhã não
  -- reescreve o que a cliente pediu hoje.
  nome        text not null,
  preco       numeric(10,2) not null check (preco >= 0),
  quantidade  int not null check (quantidade between 1 and 99),
  observacao  text,
  ordem       smallint not null default 1
);
create index if not exists ix_pedido_item on public.pedido_itens(pedido_id);

alter table public.pedidos enable row level security;
alter table public.pedidos force row level security;
alter table public.pedido_itens enable row level security;
alter table public.pedido_itens force row level security;

/* Quem LÊ: a equipe do estabelecimento. Quem ESCREVE: ninguém por aqui — o
   pedido nasce no `fazer_pedido()` e muda de estado no
   `mudar_status_pedido()`, que conferem tudo. Uma tela que pudesse gravar o
   total direto seria uma tela que decide o preço. */
drop policy if exists pedidos_ler on public.pedidos;
create policy pedidos_ler on public.pedidos for select to authenticated
  using ( public.e_equipe(salao_id) );
drop policy if exists pedido_itens_ler on public.pedido_itens;
create policy pedido_itens_ler on public.pedido_itens for select to authenticated
  using ( exists (select 1 from public.pedidos p
                   where p.id = pedido_id and public.e_equipe(p.salao_id)) );
revoke all on public.pedidos, public.pedido_itens from anon, authenticated;
grant select on public.pedidos, public.pedido_itens to authenticated;

-- ---------------------------------------------------------------------------
-- 3) AS MENSAGENS DO PEDIDO NA FILA
-- ---------------------------------------------------------------------------
alter table public.notificacoes
  add column if not exists pedido_id uuid references public.pedidos(id) on delete cascade;
create index if not exists ix_notif_pedido on public.notificacoes(pedido_id)
  where pedido_id is not null;

/* ⚠ A MESMA LISTA ESTÁ NO 21_notificacoes. Lá ela é refeita a cada colagem do
   00_tudo — e, se lá faltassem os tipos do pedido, colar de novo num banco
   que já tem mensagem de pedido estouraria no `add constraint` (a trava
   confere as linhas que já existem). As duas listas andam juntas. */
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in ('confirmacao','lembrete','resumo','novo','lembrete_equipe',
                  'pedido_novo','pedido_confirmado','pedido_a_caminho',
                  'pedido_pronto','pedido_cancelado'));

/* O modelo aprovado na Meta, por tipo — a lista inteira, porque esta função
   substitui a do 21 (a de número maior vale). Com o sufixo `_pagamento` dos
   quatro que falam de um agendamento, quando a plataforma ligou os modelos
   com a forma de pagamento (21, `mensagens_com_pagamento()`). */
create or replace function public.modelo_de(p_tipo text)
returns text language sql stable set search_path = public as $$
  select case p_tipo
    when 'confirmacao'       then 'agendapro_confirmacao'
    when 'lembrete'          then 'agendapro_lembrete'
    when 'novo'              then 'agendapro_aviso_profissional'
    when 'resumo'            then 'agendapro_agenda_hoje'
    when 'lembrete_equipe'   then 'agendapro_lembrete_equipe'
    -- Os do pedido (37). Texto e ordem das variáveis no MODELOS.md.
    when 'pedido_novo'       then 'agendapro_pedido_novo'
    when 'pedido_confirmado' then 'agendapro_pedido_confirmado'
    when 'pedido_a_caminho'  then 'agendapro_pedido_a_caminho'
    when 'pedido_pronto'     then 'agendapro_pedido_pronto'
    when 'pedido_cancelado'  then 'agendapro_pedido_cancelado'
  end
  || case when p_tipo in ('confirmacao', 'lembrete', 'novo', 'lembrete_equipe')
               and public.mensagens_com_pagamento()
          -- A confirmação se chama _valor1: o _pagamento dela a Meta passou
          -- para Marketing, e categoria não se troca depois (MODELOS.md). O
          -- "1" é o nome com que ela foi aprovada na Meta.
          then case when p_tipo = 'confirmacao' then '_valor1' else '_pagamento' end
          else '' end
$$;

/* A cota por tipo (22_cotas), com os do pedido no lugar certo: os que vão
   para a CLIENTE seguem até o teto do plano, como a confirmação e o lembrete;
   o aviso para o estabelecimento para antes, nos 90%, como os do salão. */
create or replace function public.pode_enviar_tipo(p_salao uuid, p_tipo text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when public.teto_mensagens(p_salao) is null then true
    when p_tipo in ('confirmacao', 'lembrete', 'pedido_confirmado',
                    'pedido_a_caminho', 'pedido_pronto', 'pedido_cancelado')
      then public.mensagens_no_mes(p_salao) < public.teto_mensagens(p_salao)
    else public.mensagens_no_mes(p_salao) < public.teto_mensagens_salao(p_salao)
  end
$$;
revoke all on function public.pode_enviar_tipo(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4) A CONFIGURAÇÃO DOS PEDIDOS
-- Mora em `saloes.cfg.pedidos`, como o resto das escolhas do estabelecimento:
--   { aceitando, entrega, retirada, taxaPadrao, taxas:[{bairro,taxa}],
--     minimo, tempo, pagamentos:[pix,dinheiro,cartao], avisarCliente,
--     avisarCasa }
-- Cada chave ausente tem o padrão de quem acabou de abrir: recebendo,
-- entrega e retirada, sem taxa, sem mínimo, as três formas de pagamento e os
-- dois avisos ligados.
-- ---------------------------------------------------------------------------
create or replace function public.cfg_pedidos(p_salao uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'aceitando', coalesce((p->>'aceitando')::boolean, true),
    'entrega',   coalesce((p->>'entrega')::boolean, true),
    'retirada',  coalesce((p->>'retirada')::boolean, true),
    'taxaPadrao', greatest(coalesce(case when p->>'taxaPadrao' ~ '^[0-9]+([.][0-9]+)?$'
                                         then (p->>'taxaPadrao')::numeric end, 0), 0),
    'taxas', coalesce((select jsonb_agg(jsonb_build_object(
                         'bairro', btrim(t->>'bairro'),
                         'taxa', greatest(coalesce(case when t->>'taxa' ~ '^[0-9]+([.][0-9]+)?$'
                                                        then (t->>'taxa')::numeric end, 0), 0)))
                         from jsonb_array_elements(case when jsonb_typeof(p->'taxas') = 'array'
                                                        then p->'taxas' else '[]'::jsonb end) t
                        where coalesce(btrim(t->>'bairro'), '') <> ''), '[]'::jsonb),
    'minimo', greatest(coalesce(case when p->>'minimo' ~ '^[0-9]+([.][0-9]+)?$'
                                     then (p->>'minimo')::numeric end, 0), 0),
    'tempo', nullif(left(btrim(coalesce(p->>'tempo', '')), 40), ''),
    'pagamentos', coalesce((select jsonb_agg(x) from jsonb_array_elements_text(
                              case when jsonb_typeof(p->'pagamentos') = 'array'
                                   then p->'pagamentos' else '[]'::jsonb end) x
                             where x in ('pix','dinheiro','cartao')),
                           '["pix","dinheiro","cartao"]'::jsonb),
    'avisarCliente', coalesce((p->>'avisarCliente')::boolean, true),
    'avisarCasa',    coalesce((p->>'avisarCasa')::boolean, true))
  from (select case when jsonb_typeof(s.cfg->'pedidos') = 'object'
                    then s.cfg->'pedidos' else '{}'::jsonb end as p
          from public.saloes s where s.id = p_salao) x
$$;
revoke all on function public.cfg_pedidos(uuid) from public, anon, authenticated;

/* "HH:MM" em minutos — a mesma conta do funcionamento.js, com o fechamento
   "00:00" querendo dizer meia-noite (1440). */
create or replace function public.minutos_do_dia(p_hora text, p_fim boolean)
returns int language sql immutable set search_path = public as $$
  select case when coalesce(p_hora, '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    then case when p_fim and p_hora = '00:00' then 1440
              else split_part(p_hora, ':', 1)::int * 60 + split_part(p_hora, ':', 2)::int end
  end
$$;

/* Aberto agora, pelo horário de funcionamento do estabelecimento, no fuso
   DELE. Sem horário cadastrado vale aberto: quem nunca preencheu não pode
   ficar sem pedido por isso — o interruptor "Recebendo pedidos" do painel é
   que fecha à mão. */
create or replace function public.aberto_agora(p_salao uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_func  jsonb;
  v_fuso  text;
  v_agora timestamp;
  v_min   int;
  v_per   jsonb;
begin
  select case when jsonb_typeof(s.cfg->'funcionamento') = 'object' then s.cfg->'funcionamento' end,
         coalesce(s.fuso, 'America/Sao_Paulo')
    into v_func, v_fuso
    from public.saloes s where s.id = p_salao;
  if v_func is null or not exists (
       select 1 from jsonb_each(v_func) d
        where jsonb_typeof(d.value) = 'array' and jsonb_array_length(d.value) > 0) then
    return true;
  end if;
  v_agora := now() at time zone v_fuso;
  v_min := extract(hour from v_agora)::int * 60 + extract(minute from v_agora)::int;
  for v_per in
    select value from jsonb_array_elements(case
      when jsonb_typeof(v_func->(extract(dow from v_agora)::int::text)) = 'array'
      then v_func->(extract(dow from v_agora)::int::text) else '[]'::jsonb end)
  loop
    if public.minutos_do_dia(v_per->>0, false) <= v_min
       and v_min < public.minutos_do_dia(v_per->>1, true) then
      return true;
    end if;
  end loop;
  return false;
end $$;
revoke all on function public.aberto_agora(uuid) from public, anon, authenticated;
revoke all on function public.minutos_do_dia(text, boolean) from public, anon, authenticated;

/* O que a página da cliente precisa saber antes de montar o pedido. Pública
   (a página não tem login), e por isso só o que a cliente já veria: nenhum
   dado de quem pediu, nenhum número interno. */
create or replace function public.pedidos_da_casa(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.saloes; c jsonb;
begin
  select * into s from public.saloes where slug = p_slug and status = 'ativo';
  if s.id is null then return jsonb_build_object('ligado', false); end if;
  c := public.cfg_pedidos(s.id);
  return c || jsonb_build_object(
    'ligado', s.tipo = 'restaurante' and coalesce(public.recurso_bool(s.id, 'loja'), false),
    'aberto', (c->>'aceitando')::boolean and public.aberto_agora(s.id),
    -- No restaurante a agenda só aparece se o dono LIGOU os serviços à mão
    -- (uma reserva de mesa, um rodízio com hora marcada).
    'servicosTambem', coalesce(s.cfg->>'usaServicos', '') = 'true');
end $$;
revoke all on function public.pedidos_da_casa(text) from public;
grant execute on function public.pedidos_da_casa(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) OS TEXTOS DAS MENSAGENS
-- Uma fonte (`pecas_pedido`) e dois formatos — o texto que o histórico do
-- painel mostra e as variáveis do modelo — pelo mesmo motivo do
-- `pecas_agendamento()` do 21: duas cópias das mesmas regras divergem.
-- ---------------------------------------------------------------------------
create or replace function public.pecas_pedido(p_pedido uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'nome',    split_part(btrim(p.nome), ' ', 1),
    'empresa', s.nome,
    'numero',  p.numero::text,
    'total',   public.reais(p.total),
    'tempo',   coalesce(public.cfg_pedidos(p.salao_id)->>'tempo', 'em breve'),
    'modo',    case when p.tipo_entrega = 'entrega'
                    then 'entrega' || coalesce(' no bairro ' || nullif(btrim(p.bairro), ''), '')
                    else 'retirada no balcão' end,
    'motivo',  coalesce(nullif(btrim(p.motivo), ''), 'não informado'),
    'itens',   (select count(*) from public.pedido_itens i where i.pedido_id = p.id))
  from public.pedidos p join public.saloes s on s.id = p.salao_id
  where p.id = p_pedido
$$;
revoke all on function public.pecas_pedido(uuid) from public, anon, authenticated;

create or replace function public.texto_pedido(p_pedido uuid, p_tipo text)
returns text language sql stable security definer set search_path = public as $$
  select case p_tipo
    when 'pedido_novo' then
      'Novo pedido no ' || (x->>'empresa') || ': #' || (x->>'numero') || ', de ' || (x->>'nome')
      || '. Total ' || (x->>'total') || ', ' || (x->>'modo') || '.'
    when 'pedido_confirmado' then
      'Olá, ' || (x->>'nome') || '! O ' || (x->>'empresa') || ' confirmou o seu pedido #'
      || (x->>'numero') || ' (' || (x->>'total') || '). Previsão: ' || (x->>'tempo') || '.'
    when 'pedido_a_caminho' then
      'Olá, ' || (x->>'nome') || '! O seu pedido #' || (x->>'numero') || ' do '
      || (x->>'empresa') || ' saiu para entrega.'
    when 'pedido_pronto' then
      'Olá, ' || (x->>'nome') || '! O seu pedido #' || (x->>'numero') || ' do '
      || (x->>'empresa') || ' está pronto para retirar.'
    when 'pedido_cancelado' then
      'Olá, ' || (x->>'nome') || '. O pedido #' || (x->>'numero') || ' do '
      || (x->>'empresa') || ' foi cancelado. Motivo: ' || (x->>'motivo') || '.'
  end
  from (select public.pecas_pedido(p_pedido) as x) y
$$;
revoke all on function public.texto_pedido(uuid, text) from public, anon, authenticated;

/* As variáveis NA ORDEM do modelo cadastrado — contrato com o MODELOS.md. */
create or replace function public.variaveis_pedido(p_pedido uuid, p_tipo text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case p_tipo
    when 'pedido_novo' then jsonb_build_array(
      public.variavel_limpa(x->>'empresa'), public.variavel_limpa(x->>'numero'),
      public.variavel_limpa(x->>'nome'), public.variavel_limpa(x->>'total'),
      public.variavel_limpa(x->>'modo'))
    when 'pedido_confirmado' then jsonb_build_array(
      public.variavel_limpa(x->>'nome'), public.variavel_limpa(x->>'empresa'),
      public.variavel_limpa(x->>'numero'), public.variavel_limpa(x->>'total'),
      public.variavel_limpa(x->>'tempo'))
    when 'pedido_cancelado' then jsonb_build_array(
      public.variavel_limpa(x->>'nome'), public.variavel_limpa(x->>'numero'),
      public.variavel_limpa(x->>'empresa'), public.variavel_limpa(x->>'motivo'))
    else jsonb_build_array(
      public.variavel_limpa(x->>'nome'), public.variavel_limpa(x->>'numero'),
      public.variavel_limpa(x->>'empresa'))
  end
  from (select public.pecas_pedido(p_pedido) as x) y
$$;
revoke all on function public.variaveis_pedido(uuid, text) from public, anon, authenticated;

/* Uma mensagem do pedido na fila. A chave natural ('pedido_confirmado:<id>')
   é a trava contra repetição: clicar duas vezes em "Aceitar" não manda duas.
   E antes de entrar a nova, sai o que ficou pendente e perdeu o sentido —
   "saiu para entrega" parado na fila depois de entregue não sai mais. */
create or replace function public.enfileirar_pedido(p_pedido uuid, p_tipo text, p_destino text)
returns void language plpgsql security definer set search_path = public as $$
declare v public.pedidos;
begin
  select * into v from public.pedidos where id = p_pedido;
  if v.id is null or coalesce(public.so_digitos(p_destino), '') = ''
     or length(public.so_digitos(p_destino)) < 10 then
    return;
  end if;
  insert into public.notificacoes
    (salao_id, tipo, destino, cliente_id, pedido_id, quando, corpo, modelo, variaveis, chave)
  values (v.salao_id, p_tipo, public.so_digitos(p_destino),
          case when p_tipo = 'pedido_novo' then null else v.cliente_id end,
          v.id, now(), public.texto_pedido(v.id, p_tipo),
          public.modelo_de(p_tipo), public.variaveis_pedido(v.id, p_tipo),
          p_tipo || ':' || v.id)
  on conflict (salao_id, chave) do nothing;
end $$;
revoke all on function public.enfileirar_pedido(uuid, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6) FAZER O PEDIDO — a porta da página da cliente
-- ---------------------------------------------------------------------------
create or replace function public.fazer_pedido(p_slug text, p_pedido jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s          public.saloes;
  c          jsonb;
  v_nome     text;
  v_tel      text;
  v_modo     text;
  v_end      jsonb;
  v_bairro   text;
  v_taxa     numeric(10,2) := 0;
  v_pag      text;
  v_troco    numeric(10,2);
  v_obs      text;
  v_subtotal numeric(10,2) := 0;
  v_total    numeric(10,2);
  v_cliente  uuid;
  v_pedido   uuid;
  v_numero   bigint;
  v_token    uuid;
  v_ordem    smallint := 0;
  v_qtd      int;
  v_item     jsonb;
  pr         record;
begin
  select * into s from public.saloes where slug = p_slug and status = 'ativo';
  if s.id is null then
    raise exception 'Estabelecimento não encontrado.' using errcode = 'no_data_found';
  end if;
  if s.tipo <> 'restaurante' then
    raise exception 'Este estabelecimento não recebe pedidos pelo link.'
      using errcode = 'check_violation';
  end if;
  /* O plano manda (22_cotas): sem a loja no plano, não há cardápio no link —
     e portanto não há pedido. Conferido aqui, não na tela. */
  if not coalesce(public.recurso_bool(s.id, 'loja'), false) then
    raise exception 'Os pedidos pelo link não estão disponíveis para este estabelecimento agora.'
      using errcode = 'check_violation';
  end if;
  c := public.cfg_pedidos(s.id);
  if not (c->>'aceitando')::boolean then
    raise exception 'O % não está recebendo pedidos agora.', s.nome
      using errcode = 'check_violation';
  end if;
  if not public.aberto_agora(s.id) then
    raise exception 'O % está fechado agora. Os pedidos voltam quando abrir.', s.nome
      using errcode = 'check_violation';
  end if;

  v_nome := nullif(left(btrim(coalesce(p_pedido->>'nome', '')), 80), '');
  v_tel  := public.so_digitos(p_pedido->>'telefone');
  if v_nome is null then
    raise exception 'Diga o seu nome para o pedido.' using errcode = 'check_violation';
  end if;
  if v_tel is null or length(v_tel) < 10 or length(v_tel) > 13 then
    raise exception 'Confira o WhatsApp: precisa do DDD.' using errcode = 'check_violation';
  end if;

  v_modo := p_pedido->>'entrega';
  if v_modo not in ('entrega', 'retirada') or v_modo is null then
    raise exception 'Escolha entre entrega e retirada.' using errcode = 'check_violation';
  end if;
  if not (c->>v_modo)::boolean then
    raise exception '%', case v_modo when 'entrega' then 'Este estabelecimento não faz entrega — só retirada.'
                                     else 'Este estabelecimento não faz retirada — só entrega.' end
      using errcode = 'check_violation';
  end if;

  if v_modo = 'entrega' then
    v_end := case when jsonb_typeof(p_pedido->'endereco') = 'object' then p_pedido->'endereco' else '{}'::jsonb end;
    v_end := jsonb_build_object(
      'rua',         nullif(left(btrim(coalesce(v_end->>'rua', '')), 120), ''),
      'numero',      nullif(left(btrim(coalesce(v_end->>'numero', '')), 20), ''),
      'complemento', nullif(left(btrim(coalesce(v_end->>'complemento', '')), 80), ''),
      'bairro',      nullif(left(btrim(coalesce(v_end->>'bairro', '')), 80), ''),
      'referencia',  nullif(left(btrim(coalesce(v_end->>'referencia', '')), 120), ''));
    if v_end->>'rua' is null or v_end->>'numero' is null or v_end->>'bairro' is null then
      raise exception 'Para entregar, preencha a rua, o número e o bairro.'
        using errcode = 'check_violation';
    end if;
    v_bairro := v_end->>'bairro';
    /* A taxa por bairro: com lista, o bairro tem de estar nela (comparado sem
       acento e sem maiúscula) — bairro fora da lista é bairro onde não se
       entrega. Sem lista, a taxa padrão vale para qualquer um. */
    if jsonb_array_length(c->'taxas') > 0 then
      select (t->>'taxa')::numeric, t->>'bairro' into v_taxa, v_bairro
        from jsonb_array_elements(c->'taxas') t
       where public.virar_slug(t->>'bairro') = public.virar_slug(v_end->>'bairro')
       limit 1;
      if not found then
        raise exception 'O % não entrega no bairro %.', s.nome, v_end->>'bairro'
          using errcode = 'check_violation';
      end if;
      v_end := v_end || jsonb_build_object('bairro', v_bairro);
    else
      v_taxa := (c->>'taxaPadrao')::numeric;
    end if;
  end if;

  v_pag := p_pedido->>'pagamento';
  if v_pag is null or not (c->'pagamentos') ? v_pag then
    raise exception 'Escolha como vai pagar.' using errcode = 'check_violation';
  end if;
  v_obs := nullif(left(btrim(coalesce(p_pedido->>'observacao', '')), 300), '');

  if jsonb_typeof(p_pedido->'itens') <> 'array' or jsonb_array_length(p_pedido->'itens') = 0 then
    raise exception 'O pedido está vazio.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_pedido->'itens') > 50 then
    raise exception 'Itens demais num pedido só.' using errcode = 'check_violation';
  end if;

  /* ⚠ OS LIMITES CONTRA PEDIDO DE MENTIRA. A página é aberta a qualquer um,
     sem login — é o que faz um restaurante receber pedido. Então: o mesmo
     telefone não deixa mais de três pedidos esperando o aceite, e o
     estabelecimento não recebe mais de sessenta em dez minutos. Um pedido
     de verdade nunca chega perto disso. */
  if (select count(*) from public.pedidos p
       where p.salao_id = s.id and p.telefone = v_tel and p.status = 'recebido') >= 3 then
    raise exception 'Você já tem pedidos esperando a confirmação. Aguarde ou cancele um antes de fazer outro.'
      using errcode = 'check_violation';
  end if;
  if (select count(*) from public.pedidos p
       where p.salao_id = s.id and p.criado_em > now() - interval '10 minutes') >= 60 then
    raise exception 'Muitos pedidos agora. Tente de novo em alguns minutos.'
      using errcode = 'check_violation';
  end if;

  -- O preço de cada item sai do cadastro. Da página vem só o que e quantos.
  for v_item in select value from jsonb_array_elements(p_pedido->'itens') loop
    v_qtd := case when coalesce(v_item->>'quantidade', '') ~ '^[0-9]{1,2}$'
                  then (v_item->>'quantidade')::int end;
    if v_qtd is null or v_qtd < 1 or v_qtd > 99 then
      raise exception 'Confira a quantidade dos itens.' using errcode = 'check_violation';
    end if;
    select pr2.id, pr2.nome, pr2.preco, pr2.preco_visivel into pr
      from public.produtos pr2
     where pr2.id::text = coalesce(v_item->>'produto', '') and pr2.salao_id = s.id
       and pr2.ativo and pr2.venda_online;
    if pr.id is null then
      raise exception 'Um dos itens saiu do cardápio. Confira o pedido.'
        using errcode = 'check_violation';
    end if;
    if not pr.preco_visivel then
      raise exception 'O item % está sem preço no cardápio e não pode ser pedido pelo link.', pr.nome
        using errcode = 'check_violation';
    end if;
    v_subtotal := v_subtotal + pr.preco * v_qtd;
  end loop;

  if v_subtotal < (c->>'minimo')::numeric then
    raise exception 'O pedido mínimo é de %.', public.reais((c->>'minimo')::numeric)
      using errcode = 'check_violation';
  end if;
  v_total := v_subtotal + v_taxa;

  if v_pag = 'dinheiro' and coalesce(p_pedido->>'troco', '') <> '' then
    if not (p_pedido->>'troco') ~ '^[0-9]+([.,][0-9]{1,2})?$' then
      raise exception 'Confira o valor do troco.' using errcode = 'check_violation';
    end if;
    v_troco := replace(p_pedido->>'troco', ',', '.')::numeric;
    if v_troco < v_total then
      raise exception 'O troco precisa ser para um valor maior que o total (%).', public.reais(v_total)
        using errcode = 'check_violation';
    end if;
  end if;

  /* A ficha da cliente no estabelecimento, pela mesma porta do agendamento.
     Se não der (o plano não comporta ficha nova, por exemplo), o pedido entra
     assim mesmo: nome e telefone ficam no próprio pedido. Perder o pedido por
     causa da ficha seria perder a venda. */
  begin
    v_cliente := public.ficha_do_cliente(s.id, v_nome, v_tel);
  exception when others then
    v_cliente := null;
  end;

  v_numero := public.proximo_numero(s.id, 'pedido');
  insert into public.pedidos
    (salao_id, numero, cliente_id, nome, telefone, tipo_entrega, endereco, bairro,
     subtotal, taxa_entrega, total, pagamento, troco_para, observacao)
  values (s.id, v_numero, v_cliente, v_nome, v_tel, v_modo,
          case when v_modo = 'entrega' then v_end end,
          case when v_modo = 'entrega' then v_bairro end,
          v_subtotal, v_taxa, v_total, v_pag, v_troco, v_obs)
  returning id, token into v_pedido, v_token;

  for v_item in select value from jsonb_array_elements(p_pedido->'itens') loop
    v_ordem := v_ordem + 1;
    insert into public.pedido_itens (pedido_id, produto_id, nome, preco, quantidade, observacao, ordem)
    select v_pedido, pr2.id, pr2.nome, pr2.preco, (v_item->>'quantidade')::int,
           nullif(left(btrim(coalesce(v_item->>'observacao', '')), 160), ''), v_ordem
      from public.produtos pr2
     where pr2.id::text = v_item->>'produto' and pr2.salao_id = s.id;
  end loop;

  -- O aviso para o estabelecimento, no WhatsApp dele (se ligado).
  if (c->>'avisarCasa')::boolean then
    perform public.enfileirar_pedido(v_pedido, 'pedido_novo', coalesce(s.whatsapp, s.telefone));
  end if;

  return jsonb_build_object('numero', v_numero, 'token', v_token,
                            'subtotal', v_subtotal, 'taxa', v_taxa, 'total', v_total,
                            'status', 'recebido');
end $$;
revoke all on function public.fazer_pedido(text, jsonb) from public;
grant execute on function public.fazer_pedido(text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7) A CLIENTE ACOMPANHA E, ANTES DO ACEITE, CANCELA
-- ---------------------------------------------------------------------------
create or replace function public.meu_pedido(p_token uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'numero', p.numero, 'status', p.status, 'criado_em', p.criado_em,
    'entrega', p.tipo_entrega, 'bairro', p.bairro,
    'subtotal', p.subtotal, 'taxa', p.taxa_entrega, 'total', p.total,
    'pagamento', p.pagamento, 'troco', p.troco_para, 'motivo', p.motivo,
    'cancelado_por', p.cancelado_por,
    'itens', (select coalesce(jsonb_agg(jsonb_build_object(
                'nome', i.nome, 'quantidade', i.quantidade, 'preco', i.preco,
                'observacao', i.observacao) order by i.ordem), '[]'::jsonb)
                from public.pedido_itens i where i.pedido_id = p.id),
    'casa', s.nome, 'slug', s.slug, 'whatsapp', coalesce(s.whatsapp, s.telefone),
    'tempo', public.cfg_pedidos(s.id)->>'tempo')
  from public.pedidos p join public.saloes s on s.id = p.salao_id
  where p.token = p_token
$$;
revoke all on function public.meu_pedido(uuid) from public;
grant execute on function public.meu_pedido(uuid) to anon, authenticated;

create or replace function public.cancelar_meu_pedido(p_token uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v public.pedidos;
begin
  select * into v from public.pedidos where token = p_token for update;
  -- Depois do aceite, a cozinha já começou: cancelar é com o estabelecimento.
  if v.id is null or v.status <> 'recebido' then return false; end if;
  update public.pedidos
     set status = 'cancelado', cancelado_por = 'cliente', cancelado_em = now(),
         motivo = 'cancelado por quem pediu'
   where id = v.id;
  update public.notificacoes set status = 'cancelado', motivo = 'o pedido foi cancelado'
   where pedido_id = v.id and status = 'pendente';
  return true;
end $$;
revoke all on function public.cancelar_meu_pedido(uuid) from public;
grant execute on function public.cancelar_meu_pedido(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8) O ESTABELECIMENTO MUDA O ANDAMENTO
-- ---------------------------------------------------------------------------
/* O caminho de cada pedido. Na entrega: recebido → em preparo → saiu →
   entregue; na retirada: recebido → em preparo → pronto → entregue. Cancelar
   vale em qualquer ponto antes de entregue. Pular para "entregue" direto do
   preparo também vale (o balcão que entrega na hora). Andar para trás, não:
   um "saiu" que volta para "recebido" mandaria de novo a mensagem de aceite. */
create or replace function public.mudar_status_pedido(
  p_pedido uuid, p_status text, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v    public.pedidos;
  c    jsonb;
  pode text[];
begin
  select * into v from public.pedidos where id = p_pedido for update;
  if v.id is null or not public.e_equipe(v.salao_id) then
    raise exception 'Sem permissão neste estabelecimento.'
      using errcode = 'insufficient_privilege';
  end if;
  pode := case v.status
    when 'recebido'   then array['em_preparo', 'cancelado']
    when 'em_preparo' then array[case v.tipo_entrega when 'entrega' then 'saiu' else 'pronto' end,
                                 'entregue', 'cancelado']
    when 'saiu'       then array['entregue', 'cancelado']
    when 'pronto'     then array['entregue', 'cancelado']
    else array[]::text[] end;
  if not (p_status = any(pode)) then
    raise exception 'Este pedido está "%" e não pode ir para "%".', v.status, p_status
      using errcode = 'check_violation';
  end if;

  update public.pedidos set
    status       = p_status,
    aceito_em    = case when p_status = 'em_preparo' then now() else aceito_em end,
    saiu_em      = case when p_status = 'saiu' then now() else saiu_em end,
    pronto_em    = case when p_status = 'pronto' then now() else pronto_em end,
    entregue_em  = case when p_status = 'entregue' then now() else entregue_em end,
    cancelado_em = case when p_status = 'cancelado' then now() else cancelado_em end,
    cancelado_por = case when p_status = 'cancelado' then 'casa' else cancelado_por end,
    motivo       = case when p_status = 'cancelado'
                        then nullif(left(btrim(coalesce(p_motivo, '')), 200), '') else motivo end
   where id = v.id;

  -- O que ficou pendente na fila e perdeu o sentido sai antes da nova.
  update public.notificacoes set status = 'cancelado', motivo = 'o pedido mudou de etapa'
   where pedido_id = v.id and status = 'pendente';

  c := public.cfg_pedidos(v.salao_id);
  if (c->>'avisarCliente')::boolean then
    perform public.enfileirar_pedido(v.id, case p_status
        when 'em_preparo' then 'pedido_confirmado'
        when 'saiu'       then 'pedido_a_caminho'
        when 'pronto'     then 'pedido_pronto'
        when 'cancelado'  then 'pedido_cancelado' end, v.telefone)
      where p_status <> 'entregue';
  end if;
  return jsonb_build_object('ok', true, 'status', p_status);
end $$;
revoke all on function public.mudar_status_pedido(uuid, text, text) from public, anon;
grant execute on function public.mudar_status_pedido(uuid, text, text) to authenticated;

/* A lista da tela de Pedidos: o que está em andamento, de qualquer dia, e o
   que terminou nas últimas `p_horas` horas — com os itens dentro. Uma
   chamada só, que a tela repete de tempos em tempos para ver o pedido novo
   chegar. */
create or replace function public.pedidos_da_loja(p_salao uuid, p_horas int default 24)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.e_equipe(p_salao) then
    raise exception 'Sem permissão neste estabelecimento.'
      using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'numero', p.numero, 'status', p.status,
             'nome', p.nome, 'telefone', p.telefone, 'entrega', p.tipo_entrega,
             'endereco', p.endereco, 'bairro', p.bairro,
             'subtotal', p.subtotal, 'taxa', p.taxa_entrega, 'total', p.total,
             'pagamento', p.pagamento, 'troco', p.troco_para,
             'observacao', p.observacao, 'motivo', p.motivo,
             'cancelado_por', p.cancelado_por,
             'criado_em', p.criado_em, 'aceito_em', p.aceito_em,
             'saiu_em', p.saiu_em, 'pronto_em', p.pronto_em,
             'entregue_em', p.entregue_em, 'cancelado_em', p.cancelado_em,
             'itens', (select coalesce(jsonb_agg(jsonb_build_object(
                         'nome', i.nome, 'quantidade', i.quantidade, 'preco', i.preco,
                         'observacao', i.observacao) order by i.ordem), '[]'::jsonb)
                         from public.pedido_itens i where i.pedido_id = p.id))
           order by p.criado_em desc)
      from public.pedidos p
     where p.salao_id = p_salao
       and (p.status not in ('entregue', 'cancelado')
            or p.criado_em > now() - make_interval(hours => greatest(1, least(coalesce(p_horas, 24), 24 * 31))))
  ), '[]'::jsonb);
end $$;
revoke all on function public.pedidos_da_loja(uuid, int) from public, anon;
grant execute on function public.pedidos_da_loja(uuid, int) to authenticated;
