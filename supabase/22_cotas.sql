-- ===========================================================================
-- AgendaPro — 22: as cotas do plano e o consumo de mensagem
--
-- ── O QUE JÁ EXISTIA, E POR QUE ESTE ARQUIVO NÃO REESCREVE NADA ───────────
-- O sistema já tinha o mecanismo certo: `planos.recursos` é um jsonb, e
-- `recurso_num()` / `recurso_bool()` leem uma chave dele. `max_profissionais`
-- já é aplicado por gatilho, e `agendamentos_mes` também. Nada disso muda.
--
-- O que faltava eram três cotas — cliente, serviço e mensagem — e um
-- contador de consumo. Entram como CHAVES NOVAS no mesmo jsonb, aplicadas
-- pelo mesmo padrão de gatilho. Nenhum número novo espalhado pelo código: a
-- lista está na seção 1 e em mais lugar nenhum.
--
-- ── UMA DIVERGÊNCIA QUE PRECISA FICAR ESCRITA ─────────────────────────────
-- O pedido descreve quatro planos — START, ESSENCIAL, PRO e MARKETING, de
-- R$ 0 a R$ 159,90. O sistema no ar tem SETE, de R$ 57 a R$ 297, com salão
-- assinando. Renomear e reprecificar plano de quem já paga é decisão
-- comercial, não técnica, e desfazer isso depois é bem mais caro do que
-- fazer.
--
-- Então este arquivo implementa a ESTRUTURA que o pedido descreve — cota
-- central, configurável, sem número solto — sobre os planos que existem. As
-- cotas foram mapeadas por tamanho: o grátis recebe as do START, e os pagos
-- recebem escala crescente até o Salão. Trocar qualquer uma é editar a
-- seção 1.
--
-- ── O QUE NÃO ENTRA AQUI ──────────────────────────────────────────────────
-- Nada apaga dado. O item 33 do pedido é regra deste arquivo: se o salão
-- descer de plano e ficar acima do teto, o que existe CONTINUA existindo — só
-- não dá para incluir mais. Nenhum gatilho deste arquivo faz delete.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS COTAS, NUM LUGAR SÓ
--
-- `max_clientes`, `max_servicos` e `mensagens_mes` entram no `recursos` de
-- cada plano. Ausente = sem teto, que é a convenção que `recurso_num()` já
-- usava para `agendamentos_mes`.
--
-- `mensagens_mes: 0` é diferente de ausente: zero quer dizer "este plano não
-- tem WhatsApp", e é o que o pedido pede para o START.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 2) O CONSUMO DO MÊS
--
-- Conta o que SAIU, não o que foi criado. Uma mensagem parada na fila porque
-- a conta da Meta ainda não existe não gasta cota de ninguém — e no dia em
-- que passar a sair, aí sim conta.
--
-- O mês é o do SALÃO. Sem isso, um envio das 22h do dia 31 em São Paulo
-- cairia no mês seguinte, porque o servidor fala UTC. É o mesmo cuidado do
-- `checar_limite_agendamentos`, e o mesmo defeito que já apareceu duas vezes
-- neste projeto.
--
-- ⚠ O resumo do dia conta UM, com dez atendimentos dentro — e conta um porque
-- é uma linha, não porque exista um contador especial para ele.
-- ---------------------------------------------------------------------------
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

/* O teto do plano. Null = sem teto; zero = plano sem WhatsApp. Os dois são
   estados legítimos e diferentes, e quem lê precisa distinguir. */
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

-- ---------------------------------------------------------------------------
-- 3) OS TETOS DE CADASTRO
--
-- Mesmo padrão do `max_profissionais` que já existia: gatilho `before insert`,
-- que sai na primeira linha quando o plano não tem teto.
--
-- ⚠ Só no INSERT. Editar uma ficha que já existe não pode ser bloqueado por
-- cota — senão o salão que desceu de plano fica sem conseguir corrigir o
-- telefone da própria cliente, que é castigo sem propósito.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 4) O QUE A TELA "MEU PLANO" MOSTRA
--
-- Um jsonb só, pelo mesmo motivo do `painel_hoje()`: quatro perguntas em
-- quatro chamadas seriam quatro idas ao servidor para montar uma tela.
--
-- Devolve usado e teto de cada coisa. Teto null vira null no jsonb — a tela
-- desenha "sem limite" em vez de uma barra que nunca enche.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 5) A FILA, DO LADO DO WORKER
--
-- ⚠ TUDO NESTA SEÇÃO É SÓ PARA `service_role`.
--
-- Estas funções contornam o RLS de propósito: o worker não é dono de salão
-- nenhum e precisa atender todos. Se alguma aparecer concedida a
-- `authenticated`, dá para varrer o telefone de qualquer salão da plataforma.
-- ---------------------------------------------------------------------------

/* Pega o próximo da fila e marca 'enviando' NA MESMA transação.

   `for update skip locked` é o que torna isto seguro com mais de um worker:
   quem chega depois pula a linha travada em vez de esperar por ela, e a
   mesma mensagem nunca é entregue duas vezes.

   Três filtros que não são detalhe:

     · hora chegada — `quando <= now()`;
     · não venceu — mensagem parada há mais de seis horas NÃO sai. "Seu
       horário é daqui a duas horas", entregue no dia seguinte, é pior que
       silêncio;
     · o salão pode enviar — cota do plano, conferida AQUI, no servidor. A
       tela também mostra, mas quem recusa é esta linha. */
create or replace function public.notificacao_proxima(p_lote int default 1)
returns table (id uuid, salao_id uuid, destino text, corpo text, tipo text)
language plpgsql security definer set search_path = public as $$
begin
  -- Primeiro, aposenta o que venceu: sai da fila sem sair para ninguém.
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
  returning n.id, n.salao_id, n.destino, n.corpo, n.tipo;
end $$;

/* O worker devolve o que aconteceu. `enviado_em` só é carimbado no sucesso —
   é dele que sai o consumo do mês, e carimbar no erro faria a falha custar
   cota.

   Três tentativas, com espera crescente. Depois disso a mensagem é dada por
   perdida: retentar para sempre é como uma fila entope. */
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

/* O webhook de status da Meta casa pelo `wam_id`. Três avisos entram por aqui:

     delivered → entregue
     read      → lido
     failed    → falhou

   ── POR QUE O `failed` VALE MAIS DO QUE PARECE ─────────────────────────────
   Os dois primeiros são informação. O terceiro é correção.

   `failed` é a Meta dizendo que ACEITOU a mensagem — devolveu `wam_id`, e por
   isso a linha já está 'enviado' e já custou cota — e depois não conseguiu
   entregar: número que não tem WhatsApp, bloqueio, aparelho que nunca voltou.
   Sem tratá-lo, a linha diz "enviado" para sempre, e o salão continua achando
   que avisou.

   E a cota volta sozinha: `mensagens_no_mes()` conta só enviado/entregue/
   lido, então sair para 'falhou' devolve o crédito sem nenhuma conta a mais.
   Mensagem que não chegou não pode custar.

   `sent` chega junto e é ignorado de propósito: o worker já escreveu
   'enviado' quando a API respondeu OK, e é ele quem sabe a hora certa. */
drop function if exists public.notificacao_status(text, text);
create or replace function public.notificacao_status(
  p_wam_id text, p_status text,
  p_codigo text default null, p_msg text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  /* Só cai para 'falhou' quem ainda está em 'enviado'. Depois de entregue ou
     lido, um `failed` atrasado é ruído: a mensagem chegou, e alguém leu. */
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
     -- Nunca para trás: 'lido' não volta a ser 'entregue' se o webhook
     -- chegar fora de ordem, o que a Meta não garante.
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
