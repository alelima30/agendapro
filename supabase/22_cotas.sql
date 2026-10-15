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
    'max_clientes',   30, 'max_servicos',   5, 'mensagens_mes',   0,
    'agendamentos_mes', 20)
  where codigo = 'gratuito';

/* ── O GRÁTIS É SÓ PARA CONHECER, E O BÁSICO É O SISTEMA SEM MENSAGEM ──────
   Pedido do dono: "o plano grátis tem que ser bem limitado, mas bem limitado
   mesmo" — antes ele tinha o sistema inteiro menos a mensagem, e quem não
   precisa de lembrete nunca pagaria.

     Grátis     R$ 0      1 profissional, 20 horários/mês, 30 clientes,
                          5 serviços, sem produtos; agenda, clientes e o link
                          simples (sem personalizar, com o selo AgendaPro)
     Básico     R$ 49,90  1 profissional, o sistema inteiro, sem mensagens
                          automáticas (o botão manual do WhatsApp segue)
     Essencial  R$ 97     o Básico + 500 mensagens

   Os módulos travados no Grátis viram chaves de `recursos`, conferidas pelo
   banco (`exigir_recurso`, logo abaixo): caixa (com comanda), relatorios, loja
   (produtos no link), pacotes, cupons, aparencia. Nada se apaga: quem desce
   para o Grátis guarda tudo, só não lança coisa nova no que travou. */
/* A TRAVA DE MÓDULO POR PLANO. O Grátis é só para conhecer (agenda, clientes
   e o link simples); caixa, relatórios, produtos, pacotes, cupons e a
   aparência do link são do Básico para cima (logo abaixo). Quem recusa é o
   banco — num gatilho ou no começo da função —, nunca só a tela: o console
   do navegador não passa por aba escondida. Chave ausente no plano = não. */
create or replace function public.exigir_recurso(p_salao uuid, p_chave text, p_nome text)
returns void language plpgsql stable set search_path = public as $$
begin
  if not coalesce(public.recurso_bool(p_salao, p_chave), false) then
    raise exception '% está disponível a partir do plano Básico.', p_nome
      using errcode = 'check_violation';
  end if;
end $$;

/* O PLANO, PARA A EQUIPE. A assinatura só o gestor lê (preço e vencimento são
   conta do dono). Sem ela, a tela da recepção e da profissional achava que o
   salão estava no Grátis e trancava o caixa de quem paga o Básico. Isto
   devolve SÓ o código do plano em vigor — nada de preço, nada de data — e só
   para quem é da equipe daquele salão. */
create or replace function public.plano_do_salao(p_salao uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when public.e_equipe(p_salao) then public.plano_efetivo(p_salao) end
$$;
revoke all on function public.plano_do_salao(uuid) from public, anon;
grant execute on function public.plano_do_salao(uuid) to authenticated;

insert into public.planos (codigo, nome, max_profissionais, preco_mes, ordem, recursos)
values ('basico', 'Básico', 1, 49.90, 2, '{}'::jsonb)
on conflict (codigo) do nothing;           -- preço é decisão comercial: não reseta

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes',  500, 'max_servicos',  50, 'mensagens_mes', 0,
    'agenda_online', true, 'lembrete_whatsapp', false)
  where codigo = 'basico';

update public.planos set recursos = recursos || jsonb_build_object(
    'caixa', true, 'relatorios', true, 'loja', true,
    'pacotes', true, 'cupons', true, 'aparencia', true)
  where codigo <> 'gratuito';

update public.planos set recursos = recursos || jsonb_build_object(
    'caixa', false, 'relatorios', false, 'loja', false,
    'pacotes', false, 'cupons', false, 'aparencia', false)
  where codigo = 'gratuito';

/* ── A FRANQUIA DE MENSAGENS, REVISTA PELO USO DE VERDADE ─────────────────
   Cada atendimento gasta duas mensagens da cliente (confirmação e lembrete).
   Com 300, um profissional sozinho que atende 6 por dia acabava a franquia no
   fim do mês — e o lembrete é justamente o que ele paga para ter. A conta
   nova cobre ~300–350 por profissional, que é o que a cliente gasta:

     Teste grátis   100   (7 dias; custo máximo ~R$ 5 por teste)
     Essencial      500   Dupla   800   Time  1.100
     Equipe       2.000   Salão 3.600

   A ~R$ 0,05 por mensagem, a franquia usada inteira fica entre 26% e 36% da
   mensalidade — e quase ninguém usa inteira. Quando chega ao fim, as do salão
   param antes (seção 2b), e as últimas ficam para a cliente. */
update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes',  500, 'max_servicos',  50, 'mensagens_mes', 100)
  where codigo = 'trial';

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes',  500, 'max_servicos',  50, 'mensagens_mes', 500)
  where codigo = 'individual';

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 1000, 'max_servicos', 100, 'mensagens_mes', 800)
  where codigo = 'duo';

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 2000, 'max_servicos', 200, 'mensagens_mes',1100)
  where codigo = 'time';

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 3500, 'max_servicos', 350, 'mensagens_mes',2000)
  where codigo = 'equipe';

update public.planos set recursos = recursos || jsonb_build_object(
    'max_clientes', 5000, 'max_servicos', 500, 'mensagens_mes',3600)
  where codigo = 'salao';

-- ---------------------------------------------------------------------------
-- 1b) A ESCADA DE PREÇO, RECALCULADA PELO CUSTO REAL
--
-- ── O DEFEITO QUE ESTAVA NA TABELA ────────────────────────────────────────
-- A franquia de mensagem subia mais rápido que o preço, então a margem PIORAVA
-- conforme o cliente crescia — o contrário do que uma escada de planos deve
-- fazer. Com a mensagem de utilidade a R$ 0,045 no Brasil:
--
--                    antes                        depois
--   Individual  R$  57 / 300 msgs = 31,6% de custo    R$  97 / 300 = 13,9%
--   Duo         R$  87 / 600      = 41,4%             R$ 157 / 500 = 14,3%
--   Time        R$ 127 /1000      = 47,2%             R$ 197 / 700 = 16,0%
--   Equipe      R$ 187 /1500      = 48,1%  ←pior      R$ 297 /1200 = 18,2%
--   Salão       R$ 297 /2000      = 40,4%             R$ 497 /2200 = 19,9%
--
-- O Equipe entregava quase METADE da mensalidade em WhatsApp. E o Salão dava
-- 20 vagas por R$ 297 — R$ 14,85 por profissional, o cliente maior sendo o
-- pior negócio.
--
-- ── POR QUE COM `where preco_mes = <o valor antigo>` ──────────────────────
-- O `insert ... on conflict` do 01_schema NÃO atualiza `preco_mes`, e isso é
-- deliberado: preço é decisão comercial e não pode ser resetado por recolagem.
-- Esta migração respeita a mesma regra. Ela casa pelo preço ANTIGO, então roda
-- uma vez; se amanhã você mudar um preço à mão, recolar isto não desfaz.
-- ---------------------------------------------------------------------------

/* ⚠ Reduzir vaga de plano em uso deixaria salão acima do teto. O Salão vai de
   20 para 12 vagas, e o Equipe de 5 para 6 (esse só cresce, é seguro).

   Nenhum gatilho deste projeto desativa profissional — quem está acima do teto
   continua trabalhando, só não cadastra mais. Ainda assim, cortar vaga de
   alguém que está usando é decisão comercial, não migração: esta trava recusa
   a mudança inteira em vez de fazer isso em silêncio. */
do $$
declare v_estourando int;
begin
  select count(*) into v_estourando from (
    select a.salao_id
      from public.assinaturas a
      join public.profissionais pr on pr.salao_id = a.salao_id and pr.ativo
     where a.plano = 'salao'
     group by a.salao_id
    having count(*) > 12) x;

  if v_estourando > 0 then
    /* ⚠ `||` e não literais colados. Concatenação implícita ('a' 'b') só vale
       com quebra de linha entre eles — e este arquivo tem que sobreviver a ser
       colado NUMA LINHA SÓ, que é como ele chega quando alguém copia no
       celular. O teste de colagem pegou isto na primeira execução. */
    raise exception '%',
      'Há ' || v_estourando || ' salão(ões) no plano Salão com mais de 12 '
      || 'profissionais ativos. Reduzir a vaga agora os deixaria acima do '
      || 'teto. Resolva com eles antes, ou mantenha 20 vagas e ajuste só o '
      || 'preço.'
      using errcode = 'check_violation';
  end if;
end $$;

update public.planos set nome = 'Essencial', preco_mes = 97.00
 where codigo = 'individual' and preco_mes = 57.00;

update public.planos set nome = 'Dupla', preco_mes = 157.00
 where codigo = 'duo' and preco_mes = 87.00;

update public.planos set preco_mes = 197.00
 where codigo = 'time' and preco_mes = 127.00;

update public.planos set preco_mes = 297.00, max_profissionais = 6
 where codigo = 'equipe' and preco_mes = 187.00;

update public.planos set preco_mes = 497.00, max_profissionais = 12
 where codigo = 'salao' and preco_mes = 297.00;

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
/* ⚠ E A CAMPANHA CONTA TAMBÉM (2c). Mensagem de campanha sai pelo mesmo
   número e é paga do mesmo jeito; uma franquia que não a contasse seria uma
   franquia com porta dos fundos. Hoje nenhuma sai (nenhum plano libera),
   então o número não muda — mas no dia em que liberar, já conta. */
create or replace function public.mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  with mes as (
    select (date_trunc('month',
              now() at time zone coalesce(s.fuso, 'America/Sao_Paulo')))
              at time zone coalesce(s.fuso, 'America/Sao_Paulo') as ini
      from public.saloes s where s.id = p_salao)
  select ((select count(*)
             from public.notificacoes n, mes
            where n.salao_id = p_salao
              and n.status in ('enviado','entregue','lido')
              and n.enviado_em >= mes.ini)
        + (select count(*)
             from public.campanha_destinatarios d, mes
            where d.salao_id = p_salao
              and d.status = 'enviado'
              and d.enviado_em >= mes.ini))::int
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
-- 2b) A RESERVA DA CLIENTE
--
-- Quando a franquia está no fim, nem toda mensagem vale o mesmo. A cliente
-- que não recebe o lembrete é a que falta; o salão tem a agenda aberta no
-- celular. Então as mensagens PARA O SALÃO — aviso de horário novo, lembrete
-- para o salão, resumo do dia — usam até 90% da franquia, e os últimos 10%
-- ficam só para a confirmação e o lembrete da cliente.
--
-- No teto, para tudo, como antes: a franquia é o que o plano paga, e passar
-- dela é custo que ninguém cobriu.
--
-- Tipo que não seja da cliente cai na regra do salão, inclusive um que ainda
-- não existe: errar para o lado de gastar menos.
-- ---------------------------------------------------------------------------
create or replace function public.teto_mensagens_salao(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select case when x.t is null then null else floor(x.t * 0.9)::int end
    from (select public.teto_mensagens(p_salao) as t) x
$$;

create or replace function public.pode_enviar_tipo(p_salao uuid, p_tipo text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when public.teto_mensagens(p_salao) is null then true
    when p_tipo in ('confirmacao', 'lembrete')
      then public.mensagens_no_mes(p_salao) < public.teto_mensagens(p_salao)
    else public.mensagens_no_mes(p_salao) < public.teto_mensagens_salao(p_salao)
  end
$$;

-- Só o worker (service_role) e o `uso_do_plano()` (security definer) leem.
revoke all on function public.teto_mensagens_salao(uuid)   from public, anon, authenticated;
revoke all on function public.pode_enviar_tipo(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2c) A CAMPANHA NÃO PASSA POR FORA DO LIMITE
--
-- As campanhas (promoção, aniversário — 10_campanhas) tinham fila própria, e
-- o `fila_proxima()` não perguntava por cota nenhuma: um salão no Grátis,
-- pelo console do navegador, montava uma campanha para a clientela inteira
-- e ela sairia pelo número do AgendaPro, sem limite e sem contar no mês —
-- e mensagem de promoção é a mais cara (~R$ 0,35) e a que mais arrisca o
-- número, que é um só para todos os salões. Não há tela de campanha hoje;
-- a porta estava aberta pelo banco.
--
-- Agora: campanha só sai se o PLANO tiver `campanhas_whatsapp` ligado (nenhum
-- tem — ausente é não), e ainda assim dentro da franquia, pela regra das
-- mensagens do salão (para nos 90%, a reserva fica para a cliente). Quem
-- confere é o banco, no `iniciar_campanha()` e no `fila_proxima()` — a tela
-- não decide nada.
-- ---------------------------------------------------------------------------
create or replace function public.campanha_liberada(p_salao uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.recurso_bool(p_salao, 'campanhas_whatsapp')
     and public.pode_enviar_tipo(p_salao, 'campanha')
$$;
revoke all on function public.campanha_liberada(uuid) from public, anon, authenticated;

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
      'teto',  public.teto_mensagens(p_salao),
      -- até onde vão as do salão; o resto é a reserva da cliente (22, 2b)
      'tetoSalao', public.teto_mensagens_salao(p_salao)));
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
       tela também mostra, mas quem recusa é esta linha. Conferida POR TIPO:
       perto do fim, as do salão param antes e as da cliente seguem (2b).

   E um quarto, que as seis horas não pegavam: a mensagem de um horário que
   JÁ COMEÇOU não sai. Um lembrete das 12h para as 14h, parado pela
   franquia, ainda estava "dentro do prazo" às 17h — e sairia, se um
   `falhou` devolvesse crédito, três horas depois do atendimento. */
/* ⚠ O tipo de retorno mudou: entrou `modelo` e `variaveis`. Postgres não troca
   assinatura de função que devolve tabela com `create or replace` — tem que
   derrubar antes. */
drop function if exists public.notificacao_proxima(int);
create or replace function public.notificacao_proxima(p_lote int default 1)
returns table (id uuid, salao_id uuid, destino text, corpo text, tipo text,
               modelo text, variaveis jsonb)
language plpgsql security definer set search_path = public as $$
begin
  -- Primeiro, aposenta o que venceu: sai da fila sem sair para ninguém.
  update public.notificacoes
     set status = 'cancelado', motivo = 'venceu antes de ser enviada'
   where status = 'pendente' and quando < now() - interval '6 hours';

  -- E o que é de um horário que já começou. O resumo não tem agendamento
  -- (fala do dia inteiro) e por isso não entra aqui. Os tipos vão escritos
  -- para que uma mensagem futura de DEPOIS do atendimento não caia nisto.
  update public.notificacoes n
     set status = 'cancelado', motivo = 'o horário já passou'
    from public.agendamentos a
   where n.status = 'pendente'
     and n.tipo in ('confirmacao', 'lembrete', 'novo', 'lembrete_equipe')
     and n.agendamento_id = a.id
     and a.inicio <= now();

  return query
  with alvo as (
    select n.id
      from public.notificacoes n
     where n.status = 'pendente'
       and n.quando <= now()
       and (n.proxima_em is null or n.proxima_em <= now())
       and public.pode_enviar_tipo(n.salao_id, n.tipo)
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

/* ⚠ E de volta para quem precisa. O worker e o webhook falam como
   `service_role`, e o `revoke ... from public` acima tira o acesso dele
   junto — ser função de borda não dá privilégio nenhum: `service_role`
   contorna o RLS, não a permissão de EXECUTE. */
grant execute on function public.notificacao_proxima(int) to service_role;
grant execute on function public.notificacao_resultado(uuid, boolean, text, text, text)
  to service_role;
grant execute on function public.notificacao_status(text, text, text, text)
  to service_role;

comment on function public.uso_do_plano(uuid) is
  'Uso e teto de profissionais, clientes, serviços e mensagens do mês, num jsonb só.';
comment on function public.notificacao_proxima(int) is
  'Fila do worker. Só service_role: contorna o RLS para atender todos os salões.';
comment on function public.notificacao_status(text, text, text, text) is
  'Webhook de status da Meta: entregue, lido e falhou, casados pelo wam_id. Nunca anda para trás.';
