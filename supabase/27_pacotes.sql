-- ===========================================================================
-- AgendaPro — 27: pacotes de serviço
--
-- O dono cria "Pacote Unha em Dia": 4 manutenções, vale 90 dias, de segunda a
-- quarta. Vincula a Maria. A Maria, LOGADA no link, marca manutenção e vê
-- R$ 0,00 — porque ela já pagou o pacote.
--
-- ── ⚠ POR QUE SÓ LOGADA, E ISSO NÃO É RIGOR À TOA ─────────────────────────
-- O sistema identifica a cliente de dois jeitos. Com conta, `auth.uid()` é
-- prova: senha é algo que só ela sabe. Sem conta, a ficha é achada PELO
-- TELEFONE — e o `ficha_do_cliente()` no 05_agenda.sql já diz, com todas as
-- letras, que sem SMS não existe prova de que o número seja de quem digitou.
--
-- Enquanto o benefício era só "cair na ficha certa", errar custava um telefone
-- trocado. Com pacote, passaria a custar ATENDIMENTO DE GRAÇA: quem soubesse o
-- número da Maria marcaria no lugar dela sem pagar.
--
-- Por isso o desconto exige `perfil_id = auth.uid()`. Não é a tela que decide:
-- é esta função, no banco, e quem chamar por fora leva o preço cheio.
--
-- ── O QUE ESTE MÓDULO NÃO FAZ: CONTADOR ───────────────────────────────────
-- Não existe coluna `sessoes_usadas`. As sessões gastas são CONTADAS a partir
-- dos agendamentos que apontam para o pacote.
--
-- Contador guardado precisa ser incrementado ao marcar, decrementado ao
-- cancelar, e não pode ser mexido duas vezes por um UPDATE que grave o mesmo
-- status de novo. É a mesma armadilha do estoque no 26, e lá ela exigiu uma
-- trava explícita e um teste de mutação para não baixar em dobro.
--
-- Contando, nada disso existe: cancelar muda o status, a conta muda junto, e
-- não há estado para divergir. Custa um `count(*)` num índice.
--
-- ── E A VALIDADE, E OS DIAS ───────────────────────────────────────────────
-- Validade porque pacote vendido há dois anos que continua valendo é prejuízo
-- esquecido. Dias porque é assim que o pacote enche segunda e terça: "vale de
-- segunda a quarta" é a regra que faz o desconto trabalhar pelo salão.
--
-- ⚠ Fora dos dias o BENEFÍCIO não vale, mas a cliente continua marcando — pelo
-- preço cheio. Bloquear seria tirar dela uma coisa que ela já tem hoje, e
-- transformar um desconto num castigo.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O pacote que o salão oferece
-- ---------------------------------------------------------------------------
create table if not exists public.pacotes (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  nome          text not null,
  descricao     text,
  -- Quanto o salão cobra pelo pacote. Não é cobrado aqui: a venda é uma
  -- comanda comum, como qualquer outra. Este número serve para o dono lembrar
  -- quanto combinou e para a tela mostrar.
  preco         numeric(10,2) not null default 0,
  sessoes       int not null,
  validade_dias int not null default 90,
  /* Os dias da semana em que o benefício vale, no padrão do Postgres:
     0 = domingo … 6 = sábado. É o MESMO de `jornadas.dia_semana`, de
     propósito — dois jeitos de numerar dia da semana no mesmo banco é um
     erro esperando a primeira pessoa distraída. */
  dias          smallint[] not null default '{0,1,2,3,4,5,6}',
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  constraint pacotes_sessoes_check   check (sessoes between 1 and 365),
  constraint pacotes_validade_check  check (validade_dias between 1 and 3650),
  constraint pacotes_preco_check     check (preco >= 0),
  /* `<@` é "está contido em", e é a forma que o Postgres aceita aqui: uma
     restrição CHECK não pode conter subconsulta, então o `not exists (select
     ... from unnest(dias))` que eu tinha escrito derrubava a instalação
     inteira com "cannot use subquery in check constraint".

     Contenção diz a mesma coisa sem subconsulta: todo número da lista tem que
     ser um dos sete dias. E `array_length` garante que a lista não é vazia —
     pacote sem dia nenhum nunca valeria, e seria um pacote invisível que o
     dono não entenderia por que não funciona. */
  constraint pacotes_dias_check      check (
    array_length(dias, 1) between 1 and 7
    and dias <@ array[0,1,2,3,4,5,6]::smallint[])
);
create index if not exists ix_pacote_salao on public.pacotes(salao_id) where ativo;

-- Quais serviços o pacote cobre. Sem nenhuma linha o pacote não cobre nada —
-- e é o certo: pacote que cobre "tudo" por omissão viraria desconto geral no
-- dia em que alguém cadastrasse um serviço caro sem reparar.
create table if not exists public.pacote_servicos (
  /* ⚠ O `id` NÃO É ENFEITE, e custou um bug para eu lembrar.

     A chave de verdade é o par (pacote, serviço) — é ela que impede a mesma
     linha duas vezes. Mas o `dados.js` sincroniza por `id`: sem a coluna, ele
     recusa a gravação inteira do painel com "1 linha(s) sem id no retrato
     atual", e o pacote nascia SEM SERVIÇO NENHUM, dizendo na própria tela que
     não valia para nada.

     Os testes de banco não pegaram porque inserem direto, sem passar pelo
     caminho da tela. Só apareceu quando abri o painel e cliquei em Salvar.

     `servicos_profissionais` já tinha passado por isto e ganhou um `ux_sp_id`
     pelo mesmo motivo — aqui é a mesma solução, de propósito. */
  id         uuid not null default gen_random_uuid(),
  pacote_id  uuid not null references public.pacotes(id)  on delete cascade,
  servico_id uuid not null references public.servicos(id) on delete cascade,
  primary key (pacote_id, servico_id)
);
create unique index if not exists ux_pacserv_id on public.pacote_servicos(id);

-- ---------------------------------------------------------------------------
-- 2) O pacote que a CLIENTE comprou
--
-- `sessoes` e `vence_em` são COPIADOS na venda, não lidos do pacote na hora de
-- usar. O dono pode mudar o pacote amanhã — subir de 4 para 6 sessões, mudar a
-- validade — e quem comprou ontem comprou o de ontem. Ler do pacote faria a
-- mudança valer para trás, em silêncio, para todo mundo.
-- ---------------------------------------------------------------------------
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

-- O agendamento aponta para o pacote que o cobriu. É desta coluna que sai a
-- contagem de sessões gastas — e é ela que faz cancelar devolver a sessão sem
-- ninguém escrever código para isso.
alter table public.agendamentos
  add column if not exists pacote_cliente_id uuid
    references public.pacote_clientes(id) on delete set null;
create index if not exists ix_agend_pacote
  on public.agendamentos(pacote_cliente_id)
  where pacote_cliente_id is not null;

-- ---------------------------------------------------------------------------
-- 3) Quantas sessões ainda cabem
--
-- Contado, nunca guardado. Os mesmos status que o resto do sistema considera
-- vivos — cancelado devolve a sessão porque deixa de contar, e não porque
-- alguém lembrou de decrementar.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 4) ⚠ O CORAÇÃO: qual pacote desta cliente cobre estes serviços, neste dia
--
-- Devolve o `pacote_clientes.id` ou NULL. Cinco condições, e nenhuma é
-- dispensável:
--
--   · o pacote é DELA (e a identidade é conferida por quem chama, ver abaixo)
--   · não foi cancelado e não venceu
--   · o dia da semana está na lista do pacote
--   · o pacote cobre TODOS os serviços pedidos — cobrir só metade e dar tudo
--     de graça seria um desconto que ninguém decidiu
--   · ainda há sessão
--
-- ⚠ A IDENTIDADE NÃO É CONFERIDA AQUI, E É DE PROPÓSITO. Esta função responde
-- sobre uma ficha; quem garante que a ficha é de quem está pedindo é o
-- `agendar()`, que exige `perfil_id = auth.uid()`. Misturar as duas coisas
-- faria o painel — que legitimamente marca pela cliente, no balcão — não
-- conseguir usar o pacote dela.
-- ---------------------------------------------------------------------------
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

  -- O dia é o do SALÃO, não o de quem está olhando. Uma cliente em Portugal
  -- marcando às 3h da manhã dela para um salão de Porto Alegre tem que cair no
  -- dia que é lá — senão o pacote de segunda vale no domingo.
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
     -- Cobre TODOS os serviços pedidos: nenhum de fora.
     and not exists (
       select 1 from unnest(p_servicos) as pedido(id)
        where not exists (
          select 1 from public.pacote_servicos ps
           where ps.pacote_id = p.id and ps.servico_id = pedido.id))
     and public.pacote_sessoes_restantes(pc.id) > 0
   -- O que vence primeiro é usado primeiro: sobra menos sessão perdida.
   order by pc.vence_em, pc.criado_em
   limit 1;

  return v_id;
end $$;

/* O que a CLIENTE LOGADA vê sobre os próprios pacotes, naquele salão.

   Só os dela: o `where c.perfil_id = auth.uid()` é o filtro, e sem login
   `auth.uid()` é NULL e a lista sai vazia. É esta função que a página usa
   para mostrar R$ 0,00 na lista de serviços — e ela nunca devolve pacote de
   outra pessoa, mesmo que o navegador peça. */
create or replace function public.meus_pacotes(p_salao uuid)
returns table (id uuid, nome text, servicos uuid[], dias smallint[],
               vence_em date, restantes int)
language sql stable security definer set search_path = public as $$
  select pc.id, p.nome,
         (select coalesce(array_agg(ps.servico_id), '{}')
            from public.pacote_servicos ps where ps.pacote_id = p.id),
         p.dias, pc.vence_em, public.pacote_sessoes_restantes(pc.id)
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

-- ---------------------------------------------------------------------------
-- 5) Vender o pacote para uma cliente
--
-- Copia sessões e validade do pacote NAQUELE momento, e é por isso que a
-- venda é uma função e não um insert da tela: a tela mandaria os números, e
-- número que vem do navegador é número que alguém edita.
-- ---------------------------------------------------------------------------
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

  -- A ficha tem que ser DESTE salão. Sem isto, um gestor venderia pacote do
  -- salão dele para a cliente de outro salão — e o benefício viajaria junto.
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

  /* Cancelar NÃO apaga: marca. Os agendamentos que já usaram sessões continuam
     apontando para cá, e apagar a linha os deixaria órfãos — o histórico do
     salão diria que aquele atendimento foi de graça sem dizer por quê. */
  update public.pacote_clientes set cancelado_em = now()
   where id = p_id and cancelado_em is null;
end $$;

-- ---------------------------------------------------------------------------
-- 6) RLS
--
-- Os pacotes do salão são cadastro: a equipe lê, o gestor escreve. As vendas
-- também. O que a CLIENTE alcança é só o `meus_pacotes()`, que é
-- `security definer` e filtra por `auth.uid()` — a tabela em si ela não lê.
-- ---------------------------------------------------------------------------
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

/* ⚠ RLS NÃO É PERMISSÃO — É FILTRO.

   Com as policies escritas e sem estes `grant`, o painel levava
   "permission denied for table pacotes" na primeira gravação. Postgres precisa
   das duas coisas: o GRANT abre a porta, a POLICY decide quem passa. Uma sem a
   outra é porta trancada ou porta escancarada — aqui foi a primeira, e o
   sintoma apareceu no teste antes de aparecer no painel.

   Só `authenticated`: `anon` não tem nada a fazer nestas tabelas. O que a
   cliente alcança é o `meus_pacotes()`, que é `security definer` e filtra por
   `auth.uid()`. */
grant select, insert, update, delete on public.pacotes         to authenticated;
grant select, insert, update, delete on public.pacote_servicos to authenticated;
grant select, insert, update, delete on public.pacote_clientes to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Quem pode chamar
--
-- `meus_pacotes` vai para `authenticated` e NÃO para `anon`: sem login não há
-- pacote nenhum a mostrar, e deixar aberta seria oferecer a `anon` uma função
-- que só sabe responder vazio — com o risco de um dia alguém afrouxar o filtro
-- e não reparar que a porta estava aberta.
-- ---------------------------------------------------------------------------
revoke all on function public.pacote_sessoes_restantes(uuid) from public, anon;
revoke all on function public.pacote_que_cobre(uuid, uuid[], timestamptz) from public, anon;
revoke all on function public.meus_pacotes(uuid)              from public, anon;
revoke all on function public.vender_pacote(uuid, uuid)       from public, anon;
revoke all on function public.cancelar_pacote_cliente(uuid)   from public, anon;

grant execute on function public.pacote_sessoes_restantes(uuid) to authenticated;
grant execute on function public.meus_pacotes(uuid)             to authenticated;
grant execute on function public.vender_pacote(uuid, uuid)      to authenticated;
grant execute on function public.cancelar_pacote_cliente(uuid)  to authenticated;

comment on function public.pacote_que_cobre(uuid, uuid[], timestamptz) is
  'Qual pacote da cliente cobre estes serviços neste dia. NÃO confere identidade — quem chama é que exige perfil_id = auth.uid().';
comment on table public.pacotes is
  'Pacotes que o salão vende. `dias` no padrão do Postgres: 0=domingo.';
