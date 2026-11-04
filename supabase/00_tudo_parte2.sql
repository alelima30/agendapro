-- ===========================================================================
-- AgendaPro — INSTALAÇÃO COMPLETA, PARTE 2 DE 2
--
-- O 00_tudo.sql ficou grande demais para o SQL Editor do Supabase, então ele
-- vai em duas partes. É o mesmo conteúdo, na mesma ordem.
--
--   1. Cole a PARTE 1 inteira no SQL Editor e clique em Run.
--   2. Depois cole a PARTE 2 inteira e clique em Run.
--   3. Por fim, rode o CONFERIR.sql.
--
-- Pode rodar de novo quantas vezes precisar: nada é apagado.
-- ===========================================================================

-- A TRAVA DOS ACENTOS (a mesma do 00_tudo.sql). O aviso e escrito sem acento
-- de proposito: ele precisa sair legivel justamente quando os acentos
-- chegaram trocados.
do $$
begin
  if encode(convert_to('ã', 'UTF8'), 'hex') <> 'c3a3' then
    raise exception 'PAREI SEM GRAVAR NADA: os acentos deste arquivo chegaram trocados (arquivo aberto com a codificacao errada). Abra a parte 2 pelo link do GitHub (raw), copie tudo e cole de novo.';
  end if;
end $$;


-- ###########################################################################
-- ## 22_cotas.sql
-- ###########################################################################

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

/* OS DIAS DE TESTE, NO DIA DO SALÃO. O prazo do teste grátis passou a ser
   contado no fuso do salão (criar_salao, 03): depois das 21h em Brasília o
   servidor já está no dia seguinte, e a conta pelo `current_date` dele dava
   um dia a menos. A vista é refeita AQUI, num módulo, e não só no 03: é este
   arquivo que entra também no caminho de quem atualiza (98_modulos). */
create or replace view public.minha_assinatura
with (security_invoker = true) as
  select a.salao_id,
         s.nome        as salao_nome,
         s.slug,
         s.tipo,
         a.plano,
         pl.nome       as plano_nome,
         pl.preco_mes,
         pl.max_profissionais,
         a.status,
         a.trial_ate,
         a.vence_em,
         (select count(*) from public.profissionais p
           where p.salao_id = a.salao_id and p.ativo) as profissionais_ativos,
         case when a.status = 'trial' and a.trial_ate is not null
              then greatest(a.trial_ate - (now() at time zone coalesce(s.fuso, 'America/Sao_Paulo'))::date, 0)
         end as dias_de_teste
    from public.assinaturas a
    join public.saloes s  on s.id = a.salao_id
    join public.planos pl on pl.codigo = a.plano;
grant select on public.minha_assinatura to authenticated;

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
on conflict (codigo) do update set nome = excluded.nome;
-- preço é decisão comercial: não reseta. O NOME volta sempre — colado uma vez
-- com os acentos trocados, só assim o "Básico" se conserta colando de novo.

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
/* ── O MÊS DA FRANQUIA É O DA ASSINATURA ──────────────────────────────────
   "Conta a partir do dia da assinatura." Antes o contador zerava todo dia 1º:
   quem assinava no dia 20 tinha as 500 por dez dias, e outras 500 no dia 1º.
   Agora o mês vai do dia da assinatura ao mesmo dia do mês seguinte.

   A âncora é o `vence_em`: o pagamento o leva para o mesmo dia do mês
   seguinte (13_cobranca), então o dia dele É o dia da assinatura. Pagar
   adiantado não zera nada — o vencimento só anda um mês, e o dia fica.
   Pagar atrasado recomeça de hoje, e a franquia também.

     · assinatura ativa com vencimento → do dia do vencimento, mês a mês;
     · teste grátis → o teste inteiro num ciclo só, até o dia seguinte ao
       fim dele (as 100 são do teste, e o último dia não ganha outras 100);
     · o resto (Grátis, sem vencimento) → o mês do calendário, como antes.

   Dia 31 em mês curto vira o último dia do mês: os dois limites saem da
   MESMA âncora (âncora menos k meses), então um ciclo termina exatamente
   onde o seguinte começa. Devolve o começo e o fim, no fuso do salão.
   `p_hoje` existe para o teste poder fixar o dia. */
create or replace function public.ciclo_mensagens(p_salao uuid, p_hoje date default null)
returns table (ini timestamptz, fim timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso   text;
  v_hoje   date;
  v_ancora date;
  v_ini    date;
  v_fim    date;
  k        int;
begin
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso
    from public.saloes s where s.id = p_salao;
  v_fuso := coalesce(v_fuso, 'America/Sao_Paulo');
  v_hoje := coalesce(p_hoje, (now() at time zone v_fuso)::date);

  select case when a.status = 'ativa' then a.vence_em
              when a.status = 'trial' then a.trial_ate + 1 end
    into v_ancora
    from public.assinaturas a where a.salao_id = p_salao;

  if v_ancora is null then
    v_ini := date_trunc('month', v_hoje)::date;
    v_fim := (v_ini + interval '1 month')::date;
  else
    k := (extract(year from v_ancora)::int - extract(year from v_hoje)::int) * 12
       + extract(month from v_ancora)::int - extract(month from v_hoje)::int;
    v_ini := (v_ancora - make_interval(months => k))::date;
    if v_ini > v_hoje then
      k := k + 1;
      v_ini := (v_ancora - make_interval(months => k))::date;
    end if;
    v_fim := (v_ancora - make_interval(months => k - 1))::date;
  end if;

  return query select v_ini::timestamp at time zone v_fuso,
                      v_fim::timestamp at time zone v_fuso;
end $$;

revoke all on function public.ciclo_mensagens(uuid, date) from public, anon, authenticated;

create or replace function public.mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  with mes as (select c.ini from public.ciclo_mensagens(p_salao) c)
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

  /* ⚠ A MENSAGEM QUE FICOU "ENVIANDO" E NINGUÉM RESPONDEU.

     O worker marca 'enviando' aqui e só depois manda e devolve o resultado.
     Se ele cair no meio — o teto de tempo da plataforma, a rede na hora de
     gravar o resultado —, a linha ficava 'enviando' PARA SEMPRE: não saía,
     não era cancelada pelos filtros de cima (que só olham 'pendente') e o
     histórico do painel dizia "enviando" eternamente. Achado pelo caça-bug.

     Por isso a tomada abaixo deixa um PRAZO em `proxima_em` (dez minutos,
     muito acima dos segundos de um envio), e aqui o que passou do prazo vira
     'falhou' — e não volta para a fila. A mensagem pode ter chegado: o envio
     começou, só a resposta se perdeu. Repetir arriscaria a cliente receber
     duas vezes; marcar 'enviado' seria afirmar o que não se sabe. Então
     'falhou', com o motivo escrito, e sem `enviado_em` — não gasta franquia.

     A linha antiga, presa antes deste prazo existir, tem `proxima_em` nulo:
     ela cai pela hora marcada, uma hora depois. */
  update public.notificacoes
     set status = 'falhou', erro_codigo = 'sem_resposta',
         erro_msg = 'O envio começou e o servidor não respondeu. Não dá para '
                 || 'saber se chegou — por isso não foi repetida, para não '
                 || 'mandar duas vezes.'
   where status = 'enviando'
     and coalesce(proxima_em, quando + interval '1 hour') < now();

  return query
  with alvo as (
    select n.id
      from public.notificacoes n
     where n.status = 'pendente'
       and n.quando <= now()
       and (n.proxima_em is null or n.proxima_em <= now())
       and public.pode_enviar_tipo(n.salao_id, n.tipo)
       /* ⚠ O SERVIÇO AINDA NÃO CHEGOU. O painel grava o agendamento e os
          serviços dele em duas chamadas, uma logo depois da outra. Tomada
          entre as duas, a confirmação saía com "Serviço: atendimento" e o
          valor sem os itens. Espera até um minuto pelos serviços — com a
          fila passando a cada 15 segundos, cair nesse intervalo deixou de
          ser raro. Agendamento que nunca terá serviço sai depois do minuto. */
       and not (n.agendamento_id is not null
                and n.quando > now() - interval '1 minute'
                and not exists (select 1 from public.agendamento_servicos s
                                 where s.agendamento_id = n.agendamento_id))
     order by n.quando
     limit greatest(1, p_lote)
     for update skip locked)
  update public.notificacoes n
     set status = 'enviando', tentativas = n.tentativas + 1,
         proxima_em = now() + interval '10 minutes'   -- o prazo de cima
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

-- ###########################################################################
-- ## 23_assinatura_cartao.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 23: assinatura no cartão, que se renova sozinha
--
-- ── O PROBLEMA QUE ISTO RESOLVE ───────────────────────────────────────────
-- Pix não renova. Todo mês o dono do salão precisa lembrar, abrir o painel,
-- gerar um Pix e pagar. Uma parte simplesmente não faz — e essa parte não sai
-- por insatisfação, sai por atrito. É a pior forma de perder cliente, porque
-- não aparece em lugar nenhum: some.
--
-- As duas funções do fim do 13_cobranca.sql (`assinaturas_a_vencer`,
-- `vencer_cobrancas`) existem para correr atrás desse esquecimento. Elas são
-- o reconhecimento do problema em código.
--
-- ── O DESENHO, E POR QUE ESTE E NÃO O OUTRO ───────────────────────────────
-- Assinaturas do Mercado Pago (pré-aprovação), NÃO tokenização de cartão.
--
-- O dono autoriza uma vez, numa página do próprio Mercado Pago. Nenhum dado
-- de cartão encosta no AgendaPro: não há formulário de cartão no nosso HTML,
-- não há número de cartão passando pelo nosso servidor, e não há nós
-- respondendo se algo vazar. O que volta para cá é um identificador.
--
-- De quebra, quem lida com cartão vencido, cartão trocado, tentativa que
-- falhou e nova tentativa é o Mercado Pago. Essa lista inteira é código que
-- não existe aqui.
--
-- ── O QUE ESTE ARQUIVO REAPROVEITA ────────────────────────────────────────
-- Quase tudo. Uma cobrança recorrente é só mais um pagamento:
--
--   registrar_pagamento()   idempotente pelo mp_id único, confere o valor,
--                           estende vence_em em um mês, e soma ao saldo de
--                           quem paga antes de vencer
--   cobrancas               uma linha por pagamento, com `metodo`
--   webhook-mp              o HMAC e a releitura na API já valem igual
--
-- ── ⚠ O BURACO QUE A AUDITORIA ACHOU ──────────────────────────────────────
-- Na SEGUNDA cobrança do cartão, o Mercado Pago avisa um pagamento que não
-- tem cobrança nossa: `abrir_cobranca()` só roda quando alguém clica, e
-- ninguém clica no mês 2.
--
-- `registrar_pagamento()` responderia `cobranca_desconhecida` e a assinatura
-- NÃO renovaria. O mês 1 funcionaria e o mês 2 falharia em silêncio — defeito
-- que só aparece trinta dias depois, com o salão achando que está em dia.
--
-- É por isso que existe `registrar_recorrencia()` aqui: ela CRIA a linha do
-- mês a partir da pré-aprovação e só então entrega para o caminho que já
-- funciona. A idempotência continua vindo do `mp_id` único, não de lógica
-- nova.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O CARTÃO ENTRA NO DOMÍNIO
-- ---------------------------------------------------------------------------

/* `metodo` era um check de dois valores. Boleto continua aceito de propósito
   — saiu da VENDA, não do histórico, e cobrança antiga precisa continuar
   sendo lida. Ver a nota no abrir_cobranca(). */
alter table public.cobrancas drop constraint if exists cobrancas_metodo_check;
alter table public.cobrancas
  add constraint cobrancas_metodo_check
  check (metodo in ('pix','boleto','cartao'));

/* ── ⚠ A COBRANÇA DE CARTÃO NÃO OCUPA A VAGA DA PENDENTE ──────────────────
   O `ux_cobranca_aberta` garante UMA cobrança pendente por salão. O motivo
   dele está escrito no 13_cobranca.sql, e é sobre o dono CLICANDO: sem o
   índice, cada clique em "Assinar" abria um Pix novo, e ele ficava com seis
   na mão sem saber qual valia.

   Cobrança de cartão não é clicada — é o registro de uma tentativa
   automática. E o teste mostrou o estrago de deixá-la disputar a mesma vaga:
   uma recorrência recusada fica `pendente`, e a cobrança do MÊS SEGUINTE bate
   no índice, a função estoura, o webhook devolve 500, o Mercado Pago reenvia
   para sempre — e a assinatura nunca mais renova.

   Um mês falhando travaria todos os seguintes. O índice passa a valer só para
   o que o dono pode pagar na mão; a de cartão morre sozinha pelo
   `vencer_cobrancas()`. */
drop index if exists public.ux_cobranca_aberta;
create unique index if not exists ux_cobranca_aberta
  on public.cobrancas(salao_id)
  where (status = 'pendente' and metodo <> 'cartao');

/* E pelo mesmo motivo ela não aparece como "pague isto" no painel: não tem
   Pix para copiar nem boleto para abrir, e mostrar uma cobrança que o dono
   não tem como pagar é pedir para ele ligar perguntando o que fazer. */
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
        select c.id, c.plano, c.valor, c.metodo, c.vence_em, c.itens,
               c.pix_copia_cola, c.pix_qr_base64, c.boleto_url, c.linha_digitavel
          from public.cobrancas c
         where c.salao_id = p_salao and c.status = 'pendente'
           and c.metodo <> 'cartao'
           and c.vence_em > now()
         order by c.criada_em desc limit 1) x),
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id, 'plano', h.plano, 'valor', h.valor,
               'metodo', h.metodo, 'status', h.status, 'itens', h.itens,
               'pagaEm', h.paga_em, 'criadaEm', h.criada_em)
             order by h.criada_em desc)
        from (select * from public.cobrancas
               where salao_id = p_salao and status in ('paga','devolvida')
               order by criada_em desc limit 12) h), '[]'::jsonb));
end $$;

/* O vínculo com a assinatura recorrente lá no Mercado Pago.

   Fica em `assinaturas` e não em `cobrancas` porque é UM por salão e dura
   enquanto o cartão durar — cobranças são muitas, uma por mês. */
alter table public.assinaturas
  add column if not exists mp_preapproval text;
alter table public.assinaturas
  add column if not exists cartao_desde timestamptz;

/* Único: uma pré-aprovação pertence a um salão só. Sem isto, um aviso
   recorrente casaria com dois salões e estenderia o plano do errado. */
create unique index if not exists ux_assinatura_preapproval
  on public.assinaturas(mp_preapproval)
  where mp_preapproval is not null;

-- ---------------------------------------------------------------------------
-- 2) PEDIR, LIGAR E DESLIGAR O CARTÃO
--
-- Três momentos, e vale reparar em qual deles NÃO liga nada:
--
--   preparar_cartao   o dono clicou. Confere permissão e devolve à borda o
--                     preço e o e-mail do pagador. Não escreve nada.
--   ligar_cartao      o Mercado Pago confirmou a autorização. Só o webhook.
--   cancelar_cartao   o dono desistiu da renovação automática.
-- ---------------------------------------------------------------------------

/* ⚠ POR QUE ISTO EXISTE EM VEZ DE A BORDA MONTAR O PEDIDO SOZINHA.
   Ela precisa de três coisas para falar com o Mercado Pago: se esta pessoa
   pode assinar por este salão, quanto custa o plano, e para qual e-mail
   endereçar a assinatura. As três moram no banco, e as três já têm dono aqui.

   O preço em especial: `transaction_amount` da pré-aprovação é o valor que
   vai ser debitado todo mês, para sempre. Se ele viesse do navegador, o
   checkout seria um formulário onde o cliente escolhe a própria mensalidade —
   e desta vez de forma recorrente. É a mesma regra do `abrir_cobranca()`.

   Ela é `stable` e não escreve: quem escreve é o webhook, depois. */
create or replace function public.preparar_cartao(
  p_salao uuid, p_plano text, p_quem uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_preco numeric(10,2);
  v_nome  text;
  v_pre   text;
  v_pag   jsonb;
begin
  if p_quem is null then
    raise exception 'Assinatura sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.is_super() then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  select preco_mes, nome into v_preco, v_nome
    from public.planos where codigo = p_plano;
  -- Com o preço especial do salão, se houver (13_cobranca, 1b), e os módulos
  -- adicionais dele (46_adicionais): a mensalidade do cartão nasce aqui e se
  -- repete todo mês.
  if v_preco is not null then v_preco := public.valor_da_mensalidade(p_salao, p_plano); end if;
  if v_preco is null then
    raise exception 'Plano não encontrado.' using errcode = 'check_violation';
  end if;
  if v_preco <= 0 then
    raise exception 'Este plano não é pago.' using errcode = 'check_violation';
  end if;

  /* ⚠ E SEM LINHA EM `assinaturas` NÃO SE CRIA PRÉ-APROVAÇÃO NENHUMA.

     Esta é a metade que PREVINE; o `returning` do `ligar_cartao` é a metade
     que denuncia. Sem ela, um salão sem assinatura passava por aqui, a borda
     criava a pré-aprovação no Mercado Pago, e o cartão do dono começava a ser
     debitado todo mês — sem linha nenhuma para o `registrar_recorrencia`
     encontrar depois. Cobrança de verdade, renovação nenhuma.

     A conferência é pela LINHA, não pela coluna: `mp_preapproval` nulo é o
     estado legítimo de quem ainda não pôs cartão. */
  select mp_preapproval into v_pre
    from public.assinaturas where salao_id = p_salao;
  if not found then
    raise exception 'Este salão não tem assinatura para renovar.'
      using errcode = 'check_violation';
  end if;

  v_pag := public.dados_do_pagador(p_salao);

  /* `jaLigado` é o que faz a borda recusar em vez de criar uma segunda
     pré-aprovação. Duas ativas no mesmo salão é cobrança dobrada todo mês, e
     o dono só descobre na fatura. Trocar de plano no cartão é cancelar e
     assinar de novo — dois cliques, e nenhum deles cobra em duplicidade. */
  return jsonb_build_object(
    'plano',     p_plano,
    'nomePlano', v_nome,
    'valor',     v_preco,
    'email',     v_pag->>'email',
    'nome',      v_pag->>'nome',
    'jaLigado',  v_pre is not null);
end $$;

create or replace function public.ligar_cartao(
  p_salao uuid, p_preapproval text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dono   uuid;
  v_atual  text;
  v_tocado uuid;
begin
  if p_salao is null or coalesce(p_preapproval,'') = '' then
    raise exception 'Faltou o salão ou a pré-aprovação.'
      using errcode = 'check_violation';
  end if;

  /* ⚠ Uma pré-aprovação já usada por OUTRO salão é sinal de id trocado no
     caminho, não de renovação. Recusa em vez de mover plano alheio. */
  select salao_id into v_dono from public.assinaturas
   where mp_preapproval = p_preapproval;
  if v_dono is not null and v_dono <> p_salao then
    return jsonb_build_object('ok', false, 'motivo', 'preapproval_de_outro');
  end if;

  /* ⚠ E o salão que JÁ TEM uma pré-aprovação não troca por outra por baixo.

     Sobrescrever aqui seria o pior desfecho silencioso do módulo: as duas
     continuam ativas no Mercado Pago, as duas debitam todo mês, e a gente
     perde o identificador da primeira — que é justamente o que a borda
     precisa para cancelá-la. O dono descobre na fatura, e ninguém consegue
     desligar a cobrança que sobrou.

     O mesmo aviso chegando de novo NÃO cai aqui: o Mercado Pago reenvia com o
     mesmo id, e id igual passa direto para o update, que é idempotente. Só id
     DIFERENTE é recusado — e isso a borda já impede antes, no
     `preparar_cartao`. Se chegar mesmo assim, é anomalia, e anomalia tem que
     aparecer no log em vez de virar cobrança dobrada. */
  select mp_preapproval into v_atual from public.assinaturas
   where salao_id = p_salao;
  if v_atual is not null and v_atual <> p_preapproval then
    return jsonb_build_object('ok', false, 'motivo', 'ja_tem_outro');
  end if;

  /* ⚠ E O `returning` NÃO É ENFEITE: sem ele, esta função respondia
     `{"ok": true}` depois de atualizar ZERO linhas.

     Um salão sem linha em `assinaturas` fazia o UPDATE não achar nada, e a
     função jurava ter ligado. O webhook gravava sucesso no log, o Mercado Pago
     passava a debitar o cartão todo mês, e o `registrar_recorrencia` nunca
     achava esse salão — respondia `preapproval_desconhecida` para sempre. O
     dono pagava e o plano vencia assim mesmo, sem nada no sistema explicando.

     "Não deveria acontecer" não é mecanismo. Quando acontecer, a função tem
     que dizer, e é este `returning` que faz ela dizer. */
  update public.assinaturas
     set mp_preapproval = p_preapproval,
         cartao_desde   = coalesce(cartao_desde, now()),
         atualizado_em  = now()
   where salao_id = p_salao
  returning salao_id into v_tocado;

  if v_tocado is null then
    return jsonb_build_object('ok', false, 'motivo', 'salao_sem_assinatura');
  end if;

  return jsonb_build_object('ok', true, 'salao', p_salao);
end $$;

/* ⚠ O IDENTIFICADOR DA PRÉ-APROVAÇÃO, PARA A BORDA PODER CANCELAR NA FONTE.

   Cancelar só aqui no banco não cancela nada: quem debita o cartão todo mês é
   o Mercado Pago, e ele não lê a nossa tabela. Um `cancelar_cartao()` sozinho
   daria o pior desfecho possível — o painel dizendo "renovação desligada" e a
   fatura do dono continuando a vir, todo mês, sem nada no sistema explicando.

   Então a ordem é: a borda LÊ o id aqui, cancela lá, e só depois chama o
   `cancelar_cartao()`. Efeito externo primeiro, estado local depois. Se o
   Mercado Pago recusar, nada mudou deste lado e o dono pode tentar de novo —
   não há o que desfazer.

   Ela é separada do `meu_cartao()` de propósito: aquele é a tela do dono e
   NÃO devolve o identificador. Este devolve, e por isso está fechado para o
   navegador. Um `p_quem` inventado no console viraria o id que move a
   assinatura de qualquer salão. */
create or replace function public.cartao_do_salao(p_salao uuid, p_quem uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pre text;
begin
  if p_quem is null then
    raise exception 'Consulta sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.is_super() then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  select mp_preapproval into v_pre
    from public.assinaturas where salao_id = p_salao;

  return jsonb_build_object(
    'ligado', v_pre is not null, 'preapproval', v_pre);
end $$;

/* Desligar. O plano NÃO cai na hora: o dono pagou o mês, e o mês é dele.
   Cancelar aqui só interrompe a renovação — `vence_em` continua valendo, e
   quando chegar lá a assinatura vence como qualquer outra. */
create or replace function public.cancelar_cartao(p_salao uuid, p_quem uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tocado uuid;
begin
  if p_quem is null then
    raise exception 'Cancelamento sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.is_super() then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  /* Mesmo `returning` do `ligar_cartao`, pelo mesmo motivo — e aqui o estrago
     é ainda mais direto: a borda só limpa o nosso lado DEPOIS de o Mercado
     Pago confirmar o cancelamento, e confia neste retorno para dizer ao dono
     que desligou. Um `ok` sem linha tocada seria a tela afirmando o oposto do
     que o banco sabe. */
  update public.assinaturas
     set mp_preapproval = null,
         cartao_desde   = null,
         atualizado_em  = now()
   where salao_id = p_salao
  returning salao_id into v_tocado;

  if v_tocado is null then
    return jsonb_build_object('ok', false, 'motivo', 'salao_sem_assinatura');
  end if;

  return jsonb_build_object('ok', true);
end $$;

/* ⚠ E QUANDO O CANCELAMENTO VEM DO OUTRO LADO.

   O dono pode cancelar a assinatura dentro da conta dele no Mercado Pago, sem
   passar pelo nosso painel. E o Mercado Pago cancela sozinho depois de
   tentativas demais num cartão que não passa.

   Nos dois casos o débito para e ninguém nos avisa por dentro. Se o
   `mp_preapproval` continuasse preenchido, o `assinaturas_a_vencer()` seguiria
   pulando este salão — "está no cartão, renova sozinho" — e ele venceria em
   silêncio, sem cobrança, sem lembrete e sem ninguém entender por quê. É
   exatamente o silêncio que aquelas funções existem para quebrar.

   Por isso esta é chamada pelo webhook, com o id que veio da API deles, e NÃO
   pede `p_quem`: não há pessoa nenhuma nesse caminho. A permissão dela é ser
   inalcançável de fora — só `service_role`, e só por um identificador que o
   Mercado Pago devolveu. */
create or replace function public.desligar_cartao(p_preapproval text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_salao uuid;
begin
  if coalesce(p_preapproval,'') = '' then
    return jsonb_build_object('ok', false, 'motivo', 'sem_preapproval');
  end if;

  update public.assinaturas
     set mp_preapproval = null,
         cartao_desde   = null,
         atualizado_em  = now()
   where mp_preapproval = p_preapproval
  returning salao_id into v_salao;

  if v_salao is null then
    -- Aviso de uma assinatura que não é deste sistema, ou repetido depois de
    -- já termos desligado. A borda responde 200 assim mesmo.
    return jsonb_build_object('ok', true, 'motivo', 'nada_a_desligar');
  end if;

  return jsonb_build_object('ok', true, 'salao', v_salao);
end $$;

-- ---------------------------------------------------------------------------
-- 3) A COBRANÇA DO MÊS
--
-- ⚠ Esta é a função que o buraco da auditoria exigiu. Ver o cabeçalho.
--
-- O Mercado Pago manda um pagamento por mês, cada um com id próprio, e nenhum
-- deles tem cobrança nossa esperando. Aqui a linha nasce — com o preço lido
-- do PLANO, nunca do aviso — e o resto é o caminho que já existia.
-- ---------------------------------------------------------------------------
create or replace function public.registrar_recorrencia(
  p_preapproval text, p_mp_id text, p_valor numeric, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.assinaturas;
  v_preco numeric(10,2);
  v_itens jsonb;
begin
  select * into a from public.assinaturas
   where mp_preapproval = p_preapproval
   for update;

  if not found then
    -- Aviso de uma assinatura que não é deste sistema. A borda responde 200
    -- assim mesmo: 4xx faz o Mercado Pago reenviar para sempre.
    return jsonb_build_object('ok', false, 'motivo', 'preapproval_desconhecida');
  end if;

  /* Já registrado? O mesmo aviso chega várias vezes por desenho. A trava é o
     `mp_id` único da tabela, e conferir aqui evita até criar a linha. */
  if exists (select 1 from public.cobrancas where mp_id = p_mp_id) then
    return jsonb_build_object('ok', true, 'motivo', 'ja_registrada');
  end if;

  -- O mesmo preço que a pré-aprovação nasceu (13_cobranca, 1b): sem isso o
  -- salão de preço especial teria a 2ª mensalidade recusada por divergir.
  if coalesce(public.preco_do_plano(a.salao_id, a.plano), 0) <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'plano_sem_preco');
  end if;
  -- E com os módulos adicionais: a composição que bate com o que o Mercado
  -- Pago cobrou (46_adicionais, `itens_que_batem`).
  v_itens := public.itens_que_batem(a.salao_id, a.plano, p_valor);
  v_preco := public.soma_dos_itens(v_itens);

  /* ⚠ A linha nasce com o preço do PLANO, e o `registrar_pagamento` logo
     abaixo compara com o que veio da API do Mercado Pago. Se divergirem, ele
     recusa — é a mesma trava que impede pagar R$ 57 e levar o plano de
     R$ 497, agora valendo também para a recorrência. */
  insert into public.cobrancas
    (salao_id, plano, valor, metodo, status, vence_em, mp_id, mp_status, itens)
  values (a.salao_id, a.plano, v_preco, 'cartao', 'pendente',
          now() + interval '7 days', p_mp_id, p_status, v_itens);

  -- E daqui em diante é o caminho de sempre: ele confere o valor, marca a
  -- cobrança como paga e estende `vence_em` em um mês.
  return public.registrar_pagamento(p_mp_id, p_valor, p_status);
end $$;

-- ---------------------------------------------------------------------------
-- 4) QUEM ESTÁ NO CARTÃO NÃO É COBRADO POR PIX
--
-- Sem isto, o dono que acabou de pôr o cartão receberia, cinco dias antes do
-- vencimento, um aviso pedindo para gerar um Pix — de uma conta que vai ser
-- debitada sozinha. Ele pagaria duas vezes, e a culpa seria nossa.
-- ---------------------------------------------------------------------------
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
     -- O cartão renova sozinho. Quem está nele não tem o que fazer.
     and a.mp_preapproval is null
     /* ⚠ E a cobrança de CARTÃO não conta como "já tem uma pendente".
        Este é o terceiro lugar do projeto que precisa da mesma distinção — o
        índice de cobrança aberta e o `minha_cobranca` são os outros dois. A
        regra é sempre a mesma: pendente que o dono PODE PAGAR na mão suprime
        a cobrança; tentativa automática de cartão, não.
        Sem isto, um salão que saiu do cartão com uma recorrência recusada
        atrás ficava invisível na lista de renovação — e vencia sem ninguém
        avisar, que é exatamente o silêncio que estas funções existem para
        quebrar. */
     and not exists (
       select 1 from public.cobrancas c
        where c.salao_id = a.salao_id and c.status = 'pendente'
          and c.metodo <> 'cartao'
          and c.vence_em > now())
   order by a.vence_em;
$$;

-- ---------------------------------------------------------------------------
-- 5) O QUE A TELA PRECISA SABER
--
-- Só leitura, e só do próprio salão. O `mp_preapproval` NÃO sai daqui: é o
-- identificador que move dinheiro no Mercado Pago, e a tela não precisa dele
-- para nada — só precisa saber que existe.
-- ---------------------------------------------------------------------------
create or replace function public.meu_cartao(p_salao uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.assinaturas;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  select * into a from public.assinaturas where salao_id = p_salao;
  if a.salao_id is null then return jsonb_build_object('ligado', false); end if;

  return jsonb_build_object(
    'ligado',   a.mp_preapproval is not null,
    'desde',    a.cartao_desde,
    'proxima',  a.vence_em,
    'plano',    a.plano);
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM PODE CHAMAR O QUÊ
--
-- `ligar_cartao` e `registrar_recorrencia` movem assinatura: só a borda.
-- `cancelar_cartao` e `preparar_cartao` conferem o `p_quem` por dentro, mas
-- quem chama continua sendo a borda — o painel não fala com o banco sobre
-- dinheiro. E `preparar_cartao`, que nem escreve, fica igualmente fechada:
-- ela devolve o e-mail do dono, e um `p_quem` inventado no navegador viraria
-- uma consulta de e-mail de qualquer salão pelo id.
--
-- ⚠ E o `grant ... to service_role` ao lado de cada revoke. Sem ele, o
-- `revoke ... from public` tranca a porta com o carteiro do lado de fora, e
-- o produto responde 42501 em produção sem nenhum teste reprovar. Já
-- aconteceu neste projeto, com oito funções. O `bordas.test.sql` cobra.
-- ---------------------------------------------------------------------------
revoke all on function public.preparar_cartao(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.cartao_do_salao(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ligar_cartao(uuid, text) from public, anon, authenticated;
revoke all on function public.cancelar_cartao(uuid, uuid) from public, anon, authenticated;
revoke all on function public.desligar_cartao(text) from public, anon, authenticated;
revoke all on function public.registrar_recorrencia(text, text, numeric, text)
  from public, anon, authenticated;

grant execute on function public.preparar_cartao(uuid, text, uuid) to service_role;
grant execute on function public.cartao_do_salao(uuid, uuid) to service_role;
grant execute on function public.ligar_cartao(uuid, text) to service_role;
grant execute on function public.cancelar_cartao(uuid, uuid) to service_role;
grant execute on function public.desligar_cartao(text) to service_role;
grant execute on function public.registrar_recorrencia(text, text, numeric, text)
  to service_role;

-- A tela lê a sua própria situação; a função já confere `e_gestor`.
revoke all on function public.meu_cartao(uuid) from public, anon;
grant execute on function public.meu_cartao(uuid) to authenticated, service_role;

comment on function public.registrar_recorrencia(text, text, numeric, text) is
  'A cobrança mensal do cartão: cria a linha do mês e entrega ao registrar_pagamento.';
comment on function public.meu_cartao(uuid) is
  'Se o salão está no cartão e quando é a próxima. Não devolve o id da pré-aprovação.';

-- ###########################################################################
-- ## 24_produtos.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 24: produtos que o salão vende
--
-- ── O QUE ESTE ARQUIVO DESTRAVA ───────────────────────────────────────────
-- A tabela `public.produtos` existe desde o 01_schema, a comanda já vende
-- produto, e a escada do 16_comissao já calcula comissão sobre produto.
--
-- Só que NÃO HAVIA TELA PARA CADASTRAR UM. O painel lê `bd.produtos` em três
-- lugares e o seletor de produtos da comanda está sempre vazio, porque não
-- existe por onde criar. Metade de uma função construída, e morta na água.
--
-- Este módulo é a metade que faltava: as colunas que a tela precisa, o teto
-- por plano no mesmo mecanismo das outras cotas, e o produto entrando na tela
-- "Meu Plano" ao lado de clientes e serviços.
--
-- ── ⚠ `venda_online` NASCE FALSO, E ISSO É DECISÃO ────────────────────────
-- Em `servicos` o equivalente (`aceita_online`) nasce TRUE, e está certo: um
-- serviço é cadastrado para ser marcado.
--
-- Produto é outra coisa. Os que já existirem foram cadastrados para o caixa
-- interno, e publicá-los sozinho na internet seria o SISTEMA tomando uma
-- decisão que é do dono — inclusive sobre coisas que ele pode não querer
-- anunciar, ou cujo preço de vitrine é outro. Quem liga, liga na mão.
--
-- ── O QUE NÃO ESTÁ AQUI ───────────────────────────────────────────────────
-- A loja na página da cliente é a fase seguinte, e ela tem uma asserção que
-- vale dinheiro: `custo` e `comissao_pct` NÃO podem sair na vitrine. `custo` é
-- quanto o dono paga pelo produto; publicar isso entrega a margem dele a
-- qualquer concorrente que abra a página. Quando a `vitrine()` passar a
-- devolver produtos, vai nomear campo por campo, nunca a linha inteira.
--
-- E o `estoque` continua DECORATIVO: nada no sistema o diminui, nem a comanda.
-- Ele serve, por enquanto, para o dono se organizar. Fazer a comanda dar baixa
-- é trabalho separado, útil sozinho, e é o que transforma esse número em
-- verdade.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS COLUNAS QUE A TELA PRECISA
-- ---------------------------------------------------------------------------

/* A foto é o que faz a cliente escolher — mesmo papel que `servicos.foto`, e
   mesmo formato: a URL pública do balde `salao`, com a chave
   `<salao_id>/produto-<produto_id>.jpg`.

   Não precisa de policy nova: a do 04_imagens confere apenas a PRIMEIRA pasta
   do caminho (o uuid do salão), então qualquer nome de arquivo dentro dela já
   está coberto. */
alter table public.produtos add column if not exists foto text;

/* "Shampoo" não vende; "shampoo sem sal, 300ml, para cabelo com química"
   vende. Anulável: salão pequeno começa sem escrever nada. */
alter table public.produtos add column if not exists descricao text;

/* A categoria: "Tratamento de cabelo", "Perfumaria". Texto livre, como a dos
   serviços — o painel sugere as que o salão já usa, para a mesma não sair
   escrita de dois jeitos. Na loja do link vira a fileira de filtros embaixo
   da busca. Anulável: produto sem categoria aparece em "Todos".

   ⚠ Tem que nascer AQUI, antes do 25: a `vitrine()` é função SQL, que
   resolve as colunas na hora em que é criada — sem a coluna, ela não instala. */
alter table public.produtos add column if not exists categoria text;

alter table public.produtos
  add column if not exists venda_online boolean not null default false;

/* A busca da tela e do RLS é sempre por salão. Sem índice, cada leitura varre
   a tabela inteira da plataforma — o que num banco compartilhado por muitos
   salões deixa de ser detalhe assim que o primeiro catálogo cresce. */
create index if not exists ix_produto_salao
  on public.produtos(salao_id) where ativo;

comment on column public.produtos.venda_online is
  'Se aparece na loja da página pública. Nasce falso de propósito.';

-- ---------------------------------------------------------------------------
-- 2) O TETO POR PLANO
--
-- Mesmo mecanismo de `max_clientes` e `max_servicos`: uma chave no
-- `planos.recursos`, lida por `recurso_num()`. Ausente quer dizer sem teto, e
-- é a convenção que este projeto já usa.
--
-- Os números acompanham os de serviço. Catálogo não custa nada ao sistema —
-- o teto existe para o plano Grátis não virar hospedagem de catálogo, não
-- para espremer quem paga.
-- ---------------------------------------------------------------------------
-- O Grátis não tem produto nenhum (22_cotas: o Grátis é só para conhecer).
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 0)
  where codigo = 'gratuito';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 50)
  where codigo in ('trial','individual','basico');
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 100)
  where codigo = 'duo';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 200)
  where codigo = 'time';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 350)
  where codigo = 'equipe';
update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 500)
  where codigo = 'salao';

create or replace function public.checar_limite_produtos()
returns trigger language plpgsql security definer set search_path = public as $$
declare teto int; usados int;
begin
  teto := public.recurso_num(new.salao_id, 'max_produtos');
  if teto is null then return new; end if;
  select count(*) into usados from public.produtos where salao_id = new.salao_id;
  if usados >= teto then
    raise exception 'O seu plano cobre % produtos, e o salão já tem %. Mude de plano para cadastrar mais.',
      teto, usados using errcode = 'check_violation';
  end if;
  return new;
end $$;

/* Só no INSERT, como os outros tetos deste projeto. Cobrar no UPDATE deixaria
   um salão que baixou de plano sem conseguir sequer CORRIGIR o preço do que
   já cadastrou — o teto passaria a punir quem está tentando se ajustar. */
drop trigger if exists tg_limite_produtos on public.produtos;
create trigger tg_limite_produtos before insert on public.produtos
  for each row execute function public.checar_limite_produtos();

-- ---------------------------------------------------------------------------
-- 3) PRODUTOS NA TELA "MEU PLANO"
--
-- A função inteira é reescrita porque ela devolve um jsonb montado à mão e
-- ganhou uma chave. Sem isto o dono bate no teto sem nunca ter visto uma barra
-- se encher — que é o pior jeito de descobrir um limite.
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
    'produtos', jsonb_build_object(
      'usado', (select count(*) from public.produtos where salao_id = p_salao),
      'teto',  public.recurso_num(p_salao, 'max_produtos')),
    'mensagens', jsonb_build_object(
      'usado', public.mensagens_no_mes(p_salao),
      'teto',  public.teto_mensagens(p_salao),
      -- até onde vão as do salão; o resto é a reserva da cliente (22, 2b)
      'tetoSalao', public.teto_mensagens_salao(p_salao),
      -- o dia em que a franquia renova: o mês conta da assinatura (22). No
      -- teste grátis não renova nada (vira o Grátis, sem mensagem), e
      -- "renova em" seria promessa.
      'renovaEm', (select (c.fim at time zone coalesce(s.fuso, 'America/Sao_Paulo'))::date
                     from public.ciclo_mensagens(p_salao) c, public.saloes s
                    where s.id = p_salao
                      and not exists (select 1 from public.assinaturas a
                                       where a.salao_id = p_salao and a.status = 'trial'))));
end $$;

revoke all on function public.uso_do_plano(uuid) from public, anon;
grant execute on function public.uso_do_plano(uuid) to authenticated;

/* O gatilho roda como dono, e é o que o `portas.test.sql` cobra de TODO
   gatilho deste projeto: sem `security definer` ele rodaria como quem fez o
   INSERT, e exigiria que a própria dona do salão tivesse permissão de executar
   `recurso_num()`. Já aconteceu aqui, com o `comanda_numera`, e quebrou abrir
   comanda em produção. */
revoke all on function public.checar_limite_produtos() from public, anon, authenticated;

-- ###########################################################################
-- ## 25_loja.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 25: a loja na página da cliente
--
-- A cliente vê os produtos que o dono marcou, põe no carrinho, e manda o
-- pedido pelo WhatsApp DELA. Não há checkout, não há pagamento na página, e
-- não há pedido gravado: quem fecha a venda é a conversa.
--
-- ── POR QUE O CARRINHO NÃO PASSA PELA NOSSA API DO WHATSAPP ───────────────
-- Porque o link `wa.me` abre o WhatsApp da PRÓPRIA cliente. Isso custa zero,
-- não depende de modelo aprovado nem da verificação da Meta, e — o que mais
-- importa — é ela quem escreve primeiro. Isso abre a janela de 24 horas, e o
-- dono pode responder à vontade: negociar, combinar entrega, mandar o Pix.
--
-- Pela nossa API seria uma mensagem de negócio para o dono: custo por envio,
-- modelo aprovado, e ele SEM PODER RESPONDER pelo mesmo caminho.
--
-- ── ⚠ E UMA COISA QUE NÃO DÁ PARA IMPEDIR ────────────────────────────────
-- A mensagem é montada na tela e entregue ao WhatsApp da cliente, onde ela
-- pode editar o texto antes de enviar. O preço que chega ao dono NÃO é
-- vinculante; quem confere é ele, ao montar a comanda.
--
-- Isso não é defeito a consertar: é a consequência de o pedido ser uma
-- conversa. É, também, mais um motivo para isto não ser um checkout — num
-- checkout o preço teria que valer, e aqui ele não tem como valer.
--
-- Este arquivo só reescreve a `vitrine()`. Ela é uma função SQL monolítica:
-- não há como acrescentar uma chave sem reapresentá-la inteira — e por isso
-- ela foi RECORTADA do 06_vitrine.sql por script, não redigitada. Cópia
-- inteira à mão é onde se perde uma linha sem ninguém notar, e o
-- `loja.test.sql` cobra que nenhuma chave antiga sumiu.
-- ===========================================================================

/* ── ⚠ UMA COLUNA QUE NÃO É DESTE MÓDULO, E MESMO ASSIM MORA AQUI ──────────
   `servicos.dias` é do 31_dias_servico.sql — é lá que a regra vive, com a
   explicação inteira. Só a DECLARAÇÃO precisa vir antes, e é por um motivo do
   Postgres, não de arquitetura: `create or replace function` de função SQL
   COMPILA o corpo na hora. A `vitrine()` logo abaixo lê `v.dias`, então sem a
   coluna já existente ela nem chega a ser criada — o install para com
   "column v.dias does not exist".

   Declarar no 31 não resolve: nas DUAS montagens (00_tudo e 98_modulos) o 25
   roda antes do 31. Aconteceu exatamente assim, e o banco recusou o arquivo
   inteiro.

   `if not exists` deixa a linha inofensiva: num banco que já tem a coluna ela
   não faz nada, e o 31 não a declara de novo para não haver duas verdades
   sobre o mesmo tipo. */
alter table public.servicos
  add column if not exists dias smallint[];

/* ── ⚠ E A TABELA DAS REGRAS DE PREÇO, PELA MESMÍSSIMA RAZÃO ──────────────
   A `vitrine()` logo abaixo lê `precos_regras` para montar o "a partir de" e
   a lista de regras que a página usa. Corpo de função SQL compila na hora:
   sem a tabela já existente, a `vitrine()` nem chega a ser criada e o install
   inteiro para com "relation public.precos_regras does not exist".

   Aconteceu exatamente assim — nos dois pacotes, e também na colagem em linha
   única. Declarar só no 33 não resolve: nas duas montagens o 25 roda antes.

   O dono da funcionalidade continua sendo o 33: é lá que estão o RLS, as
   policies, os grants, a escada de preço e o gatilho. Aqui fica só o que a
   `vitrine()` precisa enxergar para compilar. */
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

/* Pelo mesmo motivo, a do 32_produto_cadastro.sql: o preço pode ficar
   escondido da cliente sem o produto sumir da loja. Padrão `true`, que é o
   que a loja sempre fez — nenhum produto que já existe muda de comportamento. */
alter table public.produtos
  add column if not exists preco_visivel boolean not null default true;

create or replace function public.vitrine(p_slug text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'salao', jsonb_build_object(
      'id', s.id, 'slug', s.slug, 'nome', s.nome, 'tipo', s.tipo,
      -- "Feito com AgendaPro" no rodapé do link simples (Grátis, 22_cotas).
      'selo', not coalesce(public.recurso_bool(s.id, 'aparencia'), false),
      'logo', s.logo, 'capa', s.capa,
      'telefone', s.telefone, 'whatsapp', s.whatsapp,
      'endereco', s.endereco, 'fuso', s.fuso,
      -- A tela precisa saber até quando desenhar o calendário. Sai daqui
      -- pronto, já com o limite aplicado, para a tela não ter que repetir a
      -- regra — e não ter como discordar dela.
      'diasLiberados', public.dias_liberados(s.id),

      /* ── A APARÊNCIA QUE O SALÃO ESCOLHEU ──────────────────────────────
         Só as três chaves visuais, nomeadas uma a uma — nunca o `cfg`
         inteiro. `cfg` é jsonb e vai crescer; devolvê-lo por atacado
         significa publicar para qualquer visitante toda configuração que
         alguém puser lá no futuro, sem ninguém decidir isso. Chave nova só
         aparece aqui se for escrita aqui, de propósito.

         Nulo quer dizer "não escolheu", e a tela usa o padrão dela — assim
         salão antigo, criado antes disto existir, continua bonito sem
         precisar de migração. */
      'cor',  c.cfg->>'cor',
      'tema', c.cfg->>'tema',
      /* ── ⚠ AS QUATRO PENEIRAS, E POR QUE NENHUMA USA `::` DIRETO ──────
         `'abacaxi'::boolean` e `'abacaxi'::int` LEVANTAM no Postgres — não
         devolvem nulo. Dentro da `vitrine()` isso não é "o ajuste não pega":
         é a função inteira caindo, e ela é a ÚNICA porta da página da
         cliente. A casa sai do ar por um caractere, com o link que o salão
         mandou no WhatsApp.

         Medido, uma chave por vez, num banco de verdade: as quatro derrubavam
         a `vitrine()`. Eram as últimas — o `loja` e o `usaServicos` já tinham
         sido peneirados; estas ficaram para trás porque eu consertei a que
         estava mexendo e não varri o resto.

         ⚠ E O LADO SEGURO NÃO É O MESMO NOS QUATRO.

         `brilho` nasce LIGADO: lixo deixa ligado, que é o visual de hoje.
         `precoNaCapa` nasce DESLIGADO, e a peneira é invertida — só publica
         preço quem escreveu exatamente que quer. Lixo aqui não pode revelar
         valor que o dono não mandou mostrar; é o único dos quatro em que o
         erro custa dinheiro.
         `capaFoco` e `veu` são números sem padrão: lixo vira nulo, e a página
         usa o que ela já usava quando a chave não existia. */
      'precoNaCapa', lower(btrim(coalesce(c.cfg->>'precoNaCapa', 'false')))
                       in ('true', 't', '1', 'yes', 'sim'),
      -- A imagem de fundo da página, que o dono anexa em Identidade visual.
      -- Mora no `cfg` e não numa coluna própria de propósito: `cfg` é jsonb
      -- e já existe, então nenhum salão precisa de migração de tabela.
      'fundo', c.cfg->>'fundo',
      -- O brilho do botão principal. Ausente quer dizer LIGADO: é o padrão, e
      -- assim salão criado antes disto existir já nasce com ele.
      'brilho', lower(btrim(coalesce(c.cfg->>'brilho', 'true')))
                  not in ('false', 'f', '0', 'no', 'nao', 'não'),
      -- A letra do nome na capa. Nulo = a tela decide pelo tipo do negócio.
      'letra', c.cfg->>'letra',
      /* De onde sai o slide da capa: 'servicos' (as fotos dos serviços) ou
         'galeria' (as mídias que o dono subiu). E a galeria em si — uma
         lista de {url, tipo, legenda}. Vem nomeada, como todo o resto: o
         `cfg` inteiro nunca é devolvido. */
      'slideDe', c.cfg->>'slideDe',
      'galeria', coalesce(c.cfg->'galeria', '[]'::jsonb),
      -- Enquadramento da foto de capa (0 = topo à vista, 100 = pé) e quanto
      -- da imagem de fundo aparece por baixo do véu. Nulo = o padrão da tela.
      'capaFoco', case when c.cfg->>'capaFoco' ~ '^[0-9]+$'
                       then (c.cfg->>'capaFoco')::int end,
      'veu', case when c.cfg->>'veu' ~ '^[0-9]+$'
                  then (c.cfg->>'veu')::int end,
      /* Quanto os cartões fecham sobre a foto de fundo: 'auto', 'vidro' ou
         'fechado'. Nulo = 'auto', que é o que a tela faz sozinha — então
         salão criado antes disto não precisa de migração nenhuma.

         ⚠ Precisa ESTAR AQUI para existir. O `cfg` inteiro nunca é
         devolvido, cada chave é nomeada uma a uma, e ajuste que não aparece
         nesta lista fica preso no painel: o dono escolhe, o painel grava, a
         prévia obedece, e a página da cliente nunca fica sabendo. */
      'cartoes', c.cfg->>'cartoes',

      /* A FORMA do cartão de serviço: `reta` (o de sempre) ou
         `elegante`. Ausente vale `reta`, então salão criado antes
         disto existir não muda de aparência e não há migração.

         ⚠ É outro eixo, e não um valor de `cartoes`. Aquele decide o
         quanto o cartão FECHA sobre a foto de capa; este decide a
         forma. Juntar os dois tornaria impossível pedir moldura
         elegante com fundo de vidro. */
      'moldura', coalesce(c.cfg->>'moldura', 'reta'),

      /* ── ⚠ OS DOIS MÓDULOS DA CASA ────────────────────────────────────
         `usaServicos` e `loja` dizem com o que o estabelecimento trabalha:
         agenda, loja, ou as duas. Os dois nascem LIGADOS — é o que todo salão
         já é hoje, e nenhum deles muda de comportamento por causa destas
         linhas.

         `loja` já existia e já peneirava a lista de produtos lá embaixo. Era
         meio interruptor: o banco o respeitava, nenhuma tela o ligava, e a
         página da cliente nem o lia. Agora ele é a outra metade de um par, e
         a capa se monta a partir dos dois. Ausente = ligada, porque os
         PRODUTOS já nascem fechados um a um — exigir dois "sim" faria o dono
         marcar o produto e não entender por que nada apareceu.

         ⚠ E O NOME É `usaServicos`, NÃO `servicos`. A vitrine já devolve uma
         chave `servicos` — é a LISTA. Duas coisas diferentes com o mesmo nome
         no mesmo objeto é o tipo de colisão que compila, roda, e entrega a
         lista onde alguém esperava um sim/não.

         ⚠ E A PENEIRA É DE TEXTO, NÃO `::boolean`. Estava `(...)::boolean`
         aqui — copiado sem pensar quando o `loja` nasceu, e sem consequência
         enquanto NENHUMA TELA escrevia a chave: o `cfg` só continha o que o
         painel punha, e o painel não punha nada. A partir de agora o dono
         liga e desliga isto, e `'abacaxi'::boolean` LEVANTA no Postgres — não
         devolve nulo. Um `cfg` com lixo derrubaria a `vitrine()` inteira, que
         é a única porta da página da cliente: a casa toda sairia do ar por um
         caractere.

         É a mesma armadilha do `antecedenciaMin` com `'abc'::int` no 14, e a
         mesma resposta do `usa_comanda()` no 29 — a terceira vez que ela
         aparece neste projeto. Só desliga quem escreveu exatamente que quer
         desligar; qualquer outra coisa deixa ligado, que é o lado seguro.

         (Inline, e não uma chamada ao `usa_comanda()`: esta é uma função SQL,
         que compila o corpo na hora, e o 29 roda DEPOIS do 25 nos dois
         pacotes. Chamar dali seria a mesma pedra do `v.dias` lá em cima.) */
      'loja', lower(btrim(coalesce(c.cfg->>'loja', 'true')))
                not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'usaServicos', lower(btrim(coalesce(c.cfg->>'usaServicos', 'true')))
                       not in ('false', 'f', '0', 'no', 'nao', 'não'),

      /* ── OS SERVIÇOS QUE APARECEM NA CAPA ─────────────────────────────
         Lista de ids que o dono marcou como destaque. Um salão com vinte
         serviços não cabe numa primeira dobra de celular: sem escolha, a
         capa vira um catálogo que ninguém rola até o fim, e o serviço que
         paga a conta fica embaixo do que ninguém pede.

         ⚠ VAZIO NÃO QUER DIZER "NENHUM", quer dizer "não escolhi" — e aí a
         capa decide sozinha (os primeiros, com foto na frente). Tratar vazio
         como "esconda tudo" deixaria sem vitrine todo salão que já existe, no
         dia da atualização, sem ninguém ter pedido.

         Fica no `cfg`, e não numa coluna de `servicos`, porque é uma decisão
         da CAPA: qual é a vitrine desta casa. Em `servicos.destaque` ela
         viraria uma propriedade do serviço, e a mesma pergunta voltaria no
         dia em que a capa quisesse ORDEM — que o id numa lista já dá de
         graça, e uma coluna booleana não dá. */
      'destaques', coalesce(c.cfg->'destaques', '[]'::jsonb),

      /* ── DE QUANTO EM QUANTO TEMPO O LINK OFERECE HORÁRIO ─────────────
         15, 30 ou 60 minutos. Ausente vale 15, que é o que a agenda sempre
         fez — salão que já usa o sistema não pode acordar com a lista de
         horários diferente sem ter pedido.

         ⚠ ISTO É APARÊNCIA, NÃO DISPONIBILIDADE. A `horarios_livres()`
         continua calculando de 15 em 15, e é ela que decide o que EXISTE.
         Este número só RALEIA a lista que a cliente vê: um encaixe de 08:15
         lançado no balcão continua valendo, e a recepção continua podendo
         marcar em qualquer minuto.

         ⚠ E O CAST PASSA POR UMA PENEIRA DE TEXTO, de propósito.
         `(c.cfg->>'passoHorarios')::int` com lixo dentro — "abc", ou uma
         string vazia gravada por engano — não devolve nulo: ele LEVANTA
         ERRO, e a `vitrine()` inteira morre junto. Quer dizer: a página da
         cliente deixaria de abrir por causa de um valor torto numa chave de
         aparência. É armadilha velha conhecida deste projeto, e a saída é
         sempre a mesma — comparar como texto antes de converter. */
      'passoHorarios', case
        when c.cfg->>'passoHorarios' in ('15','30','60')
          then (c.cfg->>'passoHorarios')::int else 15 end,
      /* O salão pede senha para marcar ("Exigir senha", Meu negócio)?
         Ausente = não: todo salão que já existe segue como sempre. Booleano
         pela peneira de texto, como o `fitaBrilho` abaixo. */
      'exigeSenha', lower(btrim(coalesce(c.cfg->>'exigeSenha', 'false')))
                      in ('true', 't', '1', 'sim', 'yes'),

      /* ── A CAMADA DE PERSONALIZAÇÃO POR ESTABELECIMENTO ────────────────
         Cinco chaves, e as cinco AUSENTES no salão que nunca mexeu — que é
         o estado de todo salão que já existe. Ausente aqui não é "vazio": é
         "faça como sempre fez", e a página da cliente trata assim.

         ⚠ `cores` É UM OBJETO COM BURACOS, DE PROPÓSITO. Cada cor que o dono
         NÃO escolheu fica de fora, e a tela a calcula a partir da principal,
         como faz desde sempre — medindo contraste para decidir a letra. Se
         gravássemos as nove sempre, a conta de hoje congelaria dentro do
         salão, e melhorar o cálculo depois não chegaria em ninguém.

         `modo` ausente vale `atual`: o visual de hoje, sem nada novo ligado.
         É o que garante que ninguém acorde com a página diferente. */
      'cores',     coalesce(c.cfg->'cores', '{}'::jsonb),
      'modo',      coalesce(c.cfg->>'modo', 'atual'),
      'logoForma', coalesce(c.cfg->>'logoForma', 'circular'),
      -- A espessura do anel em volta da logo. `media` é o que a página fazia
      -- antes desta escolha existir, então salão que nunca mexeu não muda.
      'logoBorda', coalesce(c.cfg->>'logoBorda', 'media'),
      -- A forma da caixa do carrossel. `panoramico` é o 16/8 de antes.
      'slideForma', coalesce(c.cfg->>'slideForma', 'panoramico'),
      /* ── A FITA DO CARRINHO, EM METAL ─────────────────────────────────
         Cinco chaves, e as cinco AUSENTES no salão que nunca mexeu. Ausente
         não quer dizer "desligado": quer dizer "o metal de fábrica", que é o
         mesmo do botão de agendar.

         ⚠ `fitaBrilho` SAI COMO BOOLEANO, com a peneira de letra. Não é
         capricho: é a mesma armadilha do `loja` logo acima, e aqui ela morde
         mais fácil porque esta chave é gravada por um botão de dois estados
         — se alguém um dia gravar a string "nao" em vez de `false`, um
         `::boolean` derruba a `vitrine()` inteira. */
      'fitaMetal',  coalesce(c.cfg->>'fitaMetal', 'media'),
      'fitaBrilho', lower(btrim(coalesce(c.cfg->>'fitaBrilho', 'true')))
                      not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'fitaTempo',  coalesce(c.cfg->>'fitaTempo', 'media'),
      /* Sem coalesce: nulo é "não escolhi", e a página herda a cor do botão.
         Um padrão aqui seria uma cor cravada no banco. */
      'fitaCor',    c.cfg->>'fitaCor',
      'fitaBorda',  coalesce(c.cfg->>'fitaBorda', 'reta'),
      'fundoTipo', coalesce(c.cfg->>'fundoTipo', 'cor'),
      'gradiente', c.cfg->>'gradiente'
    )
    /* ── HORÁRIOS, PAGAMENTOS E A APRESENTAÇÃO ──────────────────────────────
       Num SEGUNDO jsonb_build_object, somado ao primeiro com `||`. Função no
       Postgres aceita no máximo 100 argumentos, e o objeto de cima já passa
       de 70 — mais uma rodada de chaves ali e a vitrine() inteira deixaria
       de compilar, levando junto a página de todos os salões.

       Nenhum cast: o que não for objeto vira nulo, e a página peneira de novo
       (funcionamento.js). `::jsonb` ou `::int` em texto do dono já derrubou a
       vitrine inteira neste projeto, mais de uma vez. */
    || jsonb_build_object(
      'funcionamento', case when jsonb_typeof(c.cfg->'funcionamento') = 'object'
                            then c.cfg->'funcionamento' end,
      'pagamentos',    case when jsonb_typeof(c.cfg->'pagamentos') = 'object'
                            then c.cfg->'pagamentos' end,
      'sobre',     nullif(left(btrim(coalesce(c.cfg->>'sobre', '')), 600), ''),
      'instagram', nullif(left(regexp_replace(coalesce(c.cfg->>'instagram', ''),
                                              '[^A-Za-z0-9._]', '', 'g'), 30), ''),
      /* Onde a foto de capa encontra o fundo. Só `reta` sai daqui; ausente
         (nulo) é o arco de sempre, então salão que nunca escolheu não muda. */
      'capaForma', case when c.cfg->>'capaForma' = 'reta' then 'reta' end,
      /* O estilo dos atalhos (Pagamentos, Horários, Informações). Só objeto
         passa, sem cast nenhum: os números são peneirados na página. Nulo é
         o cartão com borda de sempre. */
      'atalhos', case when jsonb_typeof(c.cfg->'atalhos') = 'object'
                      then c.cfg->'atalhos' end,
      /* O botão "Ver produtos" igual ao Agendar horário. Só 'metal' sai;
         nulo é o discreto de sempre. */
      'botaoProdutos', case when c.cfg->>'botaoProdutos' = 'metal' then 'metal' end,
      /* ── COM UMA PESSOA SÓ NO SERVIÇO, PULAR O "COM QUEM?" ──────────────
         O dono escolhe em Meu salão. Nasce DESLIGADO: a tela aparece, com
         a única pessoa já marcada — é o que o link faz hoje. A peneira é de
         texto, como a do `precoNaCapa`: `'abacaxi'::boolean` LEVANTARIA e
         derrubaria a `vitrine()` inteira; aqui lixo só mostra a tela. */
      'pularComQuem', lower(btrim(coalesce(c.cfg->>'pularComQuem', 'false')))
                        in ('true', 't', '1', 'yes', 'sim'),
      /* ── A ABERTURA COM O LOGO ─────────────────────────────────────────
         O dono escolhe em Aparência → Abertura. Só objeto passa, sem cast
         nenhum — como os atalhos: o efeito, o tempo e o fundo são peneirados
         na página (`lerIntro`), e lixo vira "sem abertura". Nulo é o link
         de sempre, que abre direto na página. */
      'intro', case when jsonb_typeof(c.cfg->'intro') = 'object'
                    then c.cfg->'intro' end
    ),

    /* ── ⚠ A LOJA, E OS DOIS CAMPOS QUE NÃO PODEM SAIR DAQUI ──────────────
       `custo` é quanto o DONO paga pelo produto. Publicar isso entrega a
       margem dele a qualquer concorrente que abra a página — e a página é
       pública por construção, sem login nenhum. `comissao_pct` é o acerto
       dele com a equipe, que também não é assunto de quem compra.

       Por isso cada campo é NOMEADO, um a um, e nunca `to_jsonb(p)`. Foi
       exatamente assim que três vazamentos apareceram na varredura de
       segurança deste projeto: função `security definer` devolvendo mais do
       que devia, sem ninguém ter decidido isso.

       ⚠ E REPARE NO QUE NÃO GOVERNA A LISTA: `estoque`.

       Seria natural esconder o que está com estoque zero. A coluna nasce ZERO
       e usá-la aqui marcaria como esgotado todo produto recém-cadastrado — e
       o dono passaria a tarde tentando entender por que a loja dele, cheia de
       produto, aparece vazia para a cliente.

       ── ⚠ E POR QUE ISSO NÃO MUDOU COM O MÓDULO 26 ─────────────────────
       Este comentário dizia "NADA no sistema movimenta o estoque — nem a
       comanda", e prometia que o "esgotado" entraria aqui no dia em que a
       comanda desse baixa. O 26_estoque.sql passou a dar, e a frase virou
       mentira. A CONCLUSÃO, porém, continua a mesma — e é por isso que a
       correção é do texto e não do código.

       Dar baixa não é o mesmo que saber quanto tem. O 26 só SUBTRAI: ninguém
       preenche a contagem inicial por ele. Salão que cadastra produto sem
       digitar quantidade continua com zero em tudo, e esconder por estoque
       continuaria escondendo a loja inteira de quem mais precisa dela.

       O "esgotado" entra no dia em que o estoque for verdade — o que depende
       de o dono ter contado, não de o sistema ter subtraído.

       Até lá, quem decide o que aparece é o `venda_online`, que é um clique
       consciente. E o pedido vai pelo WhatsApp justamente para a dona poder
       responder "essa cor acabou" — a mensagem termina em "pode confirmar o
       que tem disponível?" por este motivo. */
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', pr.id, 'nome', pr.nome, 'marca', pr.marca,
               'descricao', pr.descricao, 'foto', pr.foto,
               -- A categoria vira o filtro embaixo da busca da loja.
               'categoria', nullif(btrim(pr.categoria), ''),
               /* ⚠ NULO, e não o preço com uma marca do lado. Mandar o valor
                  e pedir para a tela não mostrar é publicar o preço mesmo
                  assim: ele viaja pela rede e fica visível a quem abrir o
                  inspetor. Preço escondido tem que sair escondido daqui. */
               'preco', case when pr.preco_visivel then pr.preco else null end)
             order by pr.nome)
        from public.produtos pr
       where pr.salao_id = s.id and pr.ativo and pr.venda_online
         and lower(btrim(coalesce(c.cfg->>'loja', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb),

    /* ── ⚠ `dias` PRECISA VIR JUNTO, E NÃO É ENFEITE ─────────────────────
       Quem RECUSA é o banco (`porque_nao_agenda`, no 31). Sem esta chave a
       página da cliente saberia que a segunda-feira não tem horário e não
       saberia POR QUÊ — e a faixa de dias marcaria o dia como "cheio", que é
       mentira: o salão está vazio, o serviço é que não é feito ali.

       "Cheio" manda a pessoa esperar uma vaga que nunca vai abrir. Com os
       dias na mão, a tela diz o que é e ela troca de dia num toque.

       Nulo ou vazio = todos os dias, igual ao banco. Serviço que já existe
       vem com nulo, e a tela não muda nada para ele. */
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'nome', v.nome, 'categoria', v.categoria,
               'descricao', v.descricao, 'duracaoMin', v.duracao_min,
               'preco', v.preco, 'foto', v.foto,
               'dias', case when v.dias is null or cardinality(v.dias) = 0
                            then null else to_jsonb(v.dias) end,

               /* ── ⚠ O PREÇO DE VERDADE, E POR QUE ELE PRECISOU VIR ───────
                  Aqui saía só `v.preco`, o do catálogo. E o `agendar()` cobra
                  a escada: regra, preço do par, catálogo. MEDIDO na bancada,
                  com o corte a R$ 90 no catálogo e R$ 130 com a profissional:

                      a vitrine mostrava ......... R$  90
                      o agendar() marcava por .... R$ 130

                  Quarenta reais de surpresa no balcão — e a tela não estava
                  errada por descuido: ela nunca soube que existia um segundo
                  preço. Esta é a pior das divergências de dinheiro do
                  projeto, porque é a única que a CLIENTE paga.

                  `precoPorProf` são só os pares que DIFEREM do catálogo: um
                  salão onde todo mundo cobra igual não carrega nada a mais.

                  `regras` já vêm NA ORDEM EM QUE GANHAM. A página pega a
                  primeira que casar e pronto — sem repetir em JavaScript a
                  conta de especificidade do 33, que é onde um espelho desses
                  diverge do original com o tempo.

                  `precoMin` é o menor que pode acontecer na janela aberta da
                  agenda, contando pares e regras. É o "a partir de" da capa,
                  onde ainda não há dia nem profissional escolhidos. */
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
               /* ⚠ A CONTA VEM ESCRITA AQUI, e não por uma chamada ao
                  `preco_minimo_do_servico()` do 33. Mesma pedra da tabela
                  logo acima: o corpo desta função compila agora, e o 33 só
                  roda daqui a oito arquivos. A função lá continua existindo
                  para quem precisar dela de fora; esta é a cópia que a
                  vitrine precisa enxergar sem depender da ordem. */
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
         /* ⚠ O MÓDULO PENEIRA A LISTA AQUI, e não só na tela. Deixar a lista
            sair e pedir para a página não desenhar seria publicar o catálogo
            de um salão que decidiu não trabalhar com serviços — visível a
            quem abrisse o inspetor. É a mesma trava que a loja já tinha, e
            pela mesma razão. */
         and lower(btrim(coalesce(c.cfg->>'usaServicos', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb),

    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'nome', coalesce(p.apelido, p.nome),
               'foto', p.foto,
               -- Lista vazia = faz tudo. É como um salão pequeno começa, e a
               -- tela já trata assim.
               'servicos', (select coalesce(jsonb_agg(sp.servico_id), '[]'::jsonb)
                              from public.servicos_profissionais sp
                             where sp.profissional_id = p.id))
             order by p.criado_em, p.id)
        from public.profissionais p
       where p.salao_id = s.id and p.ativo and p.aceita_online
         -- A cota do plano vale aqui também: profissional fora da cota não
         -- pode aparecer como opção, senão a cliente escolhe e leva um erro
         -- do gatilho na cara ao confirmar.
         and public.profissional_na_cota(p.id)), '[]'::jsonb)
  )
  from public.saloes s
  /* ⚠ O `cfg` QUE O LINK ENXERGA É O DO PLANO (22_cotas). No Grátis o link
     é o simples: as chaves de aparência saem (cada uma cai no padrão, como
     num salão recém-criado) e a loja desliga. Feito aqui, no banco, e não
     na página da cliente: a página obedece o que vem, e o dono não manda no
     navegador de quem visita. Personalizar continua guardado — volta tudo
     no dia em que ele assinar. */
  cross join lateral (select
      case when coalesce(public.recurso_bool(s.id, 'aparencia'), false) then coalesce(s.cfg, '{}'::jsonb)
           else coalesce(s.cfg, '{}'::jsonb) - array[
             'atalhos','botaoProdutos','brilho','capaFoco','capaForma','cartoes','cor',
             'cores','fitaBorda','fitaBrilho','fitaCor','fitaMetal','fitaTempo','fundo',
             'fundoTipo','galeria','gradiente','intro','letra','logoBorda','logoForma',
             'modo','moldura','slideDe','slideForma','tema','veu']
      end
      || case when coalesce(public.recurso_bool(s.id, 'loja'), false) then '{}'::jsonb
              else '{"loja": "false"}'::jsonb end as cfg) c
  where s.slug = p_slug and s.status = 'ativo'
$$;

-- ###########################################################################
-- ## 26_estoque.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 26: a comanda dá baixa no estoque
--
-- ── O QUE ESTAVA ERRADO ───────────────────────────────────────────────────
-- `produtos.estoque` existe desde o 01_schema e NADA no sistema o movimentava.
-- O dono digitava 12, vendia seis, e o sistema continuava dizendo 12 — para
-- sempre. Um número que só envelhece é pior que nenhum número: o dono confia
-- nele uma vez, erra a compra, e nunca mais olha.
--
-- Era também o que impedia a loja de mostrar "esgotado": a coluna não tinha
-- como ser verdade.
--
-- ── O MOMENTO DA BAIXA: FECHAR, E NÃO LANÇAR ──────────────────────────────
-- A tentação é dar baixa quando o item entra na comanda. Não dá certo:
-- comanda aberta e esquecida — que acontece todo dia — seguraria estoque que
-- ninguém vendeu, e o número voltaria a mentir, agora para menos.
--
-- Fechar é quando a venda é real: a conta foi paga (o `tg_fechar_comanda`
-- exige), e o dinheiro entrou no mês. Reabrir devolve.
--
-- E a simetria é garantida por travas que já existem: enquanto a comanda está
-- fechada, `tg_item_travado` não deixa item entrar, sair nem mudar. Então o
-- que foi baixado no fechamento é exatamente o que volta na reabertura — não
-- há como divergir.
--
-- O estorno não precisa de tratamento próprio: o 17_caixa EXIGE que a comanda
-- seja reaberta antes de estornar, e a reabertura já devolve.
--
-- ── ⚠ A BAIXA NUNCA RECUSA O FECHAMENTO ───────────────────────────────────
-- Vender mais do que o cadastro diz ter deixa o estoque NEGATIVO, e está
-- certo assim.
--
-- Recusar seria o sistema travando uma venda que já aconteceu: a cliente está
-- no balcão com o vidro na mão, o dinheiro na mesa, e o AgendaPro dizendo não
-- por causa de um número que ninguém atualizou desde março. O salão não
-- desfaz a venda — ele xinga o sistema, e com razão.
--
-- Negativo é informação: quer dizer "você vendeu mais do que tinha
-- registrado". É exatamente o que o dono precisa ver para arrumar a contagem.
-- ===========================================================================

create or replace function public.tg_comanda_estoque()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_sinal int;
begin
  /* ⚠ AS DUAS CONDIÇÕES SÃO A TRAVA, E CADA METADE CARREGA PESO.

     `after update of status` dispara sempre que a coluna aparece no SET —
     mesmo gravando o mesmo valor. E o painel grava a comanda inteira ao
     salvar. Então "fechada" por cima de "fechada" acontece o tempo todo.

     O que impede a baixa dobrada é o `old.status <> 'fechada'` da primeira
     linha: na segunda gravação o estado antigo JÁ é 'fechada', nenhum dos
     dois ramos casa, e a função sai sem tocar em nada.

     Simplificar para `if new.status = 'fechada'` parece inofensivo e é o
     defeito: cada gravação repetida passaria a tirar do estoque de novo, e o
     número desceria sozinho, sem venda nenhuma. É essa a mutação que o
     `estoque.test.sql` reprova.

     (Havia aqui uma guarda `if new.status is not distinct from old.status`.
     Ela não travava nada — o if/elsif abaixo já cobria o caso — e foi
     removida: duas coisas que parecem fazer o mesmo trabalho deixam ninguém
     sabendo qual é a que importa.) */
  if old.status <> 'fechada' and new.status = 'fechada' then
    v_sinal := -1;                       -- vendeu: sai do estoque
  elsif old.status = 'fechada' and new.status <> 'fechada' then
    v_sinal := 1;                        -- reabriu ou cancelou: volta
  else
    return null;                         -- aberta -> cancelada: nunca baixou
  end if;

  /* `produto_id is not null` porque o cadastro pode ter sido apagado depois
     (`on delete set null` no 01_schema). O item continua na comanda, com
     descrição e preço, e é o certo — o histórico não pode sumir. Só não há
     mais estoque para mexer.

     E é somado por produto: a mesma pomada lançada em duas linhas da comanda
     é uma baixa só, com a soma das quantidades. */
  update public.produtos p
     set estoque = p.estoque + v_sinal * i.total_qtd
    from (select ci.produto_id, sum(ci.qtd) as total_qtd
            from public.comanda_itens ci
           where ci.comanda_id = new.id
             and ci.tipo = 'produto'
             and ci.produto_id is not null
           group by ci.produto_id) i
   where p.id = i.produto_id;

  return null;
end $$;

/* AFTER, e não BEFORE: o `tg_fechar_comanda` roda antes e pode RECUSAR o
   fechamento (conta não paga, comanda vazia). Baixar estoque antes dele
   decidir seria mexer no cadastro por causa de uma venda que não aconteceu. */
drop trigger if exists tg_comanda_estoque on public.comandas;
create trigger tg_comanda_estoque
  after update of status on public.comandas
  for each row execute function public.tg_comanda_estoque();

revoke all on function public.tg_comanda_estoque() from public, anon, authenticated;

comment on function public.tg_comanda_estoque() is
  'Baixa o estoque ao fechar a comanda e devolve ao reabrir. Nunca recusa o fechamento.';

-- ###########################################################################
-- ## 27_pacotes.sql
-- ###########################################################################

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
-- ── FORA DOS DIAS: DUAS POSTURAS, E O SALÃO ESCOLHE ───────────────────────
-- Fora dos dias o BENEFÍCIO nunca vale — isso não é opcional. O que é opcional
-- é o que acontece em seguida, e mora na coluna `so_nos_dias`:
--
--   false (padrão) · a cliente marca do mesmo jeito, pelo preço cheio. A tela
--                    diz POR QUE está cobrando, em vez de mostrar o número
--                    maior em silêncio.
--   true           · o link RECUSA, com os dias escritos dentro da recusa.
--
-- O padrão é `false` de propósito: é exatamente o comportamento que já existia,
-- então a coluna nova não muda nada para nenhum pacote já vendido. Bloquear por
-- omissão transformaria um desconto num castigo, e faria isso nas costas de
-- quem comprou.
--
-- ⚠ E O QUE O BLOQUEIO NÃO É: ele não fecha a porta do salão, só a do LINK.
-- A recepção marca pelo painel em qualquer dia, cobrando — o painel grava na
-- tabela direto, e nenhuma regra da agenda online passa por lá. Conferido no
-- banco, não suposto: só `agendar()` e `horarios_livres()` chamam
-- `porque_nao_agenda()`, e nenhum dos seis gatilhos de `agendamentos` chama.
-- É essa a saída para "quero atender fora dos dias, pagando": quem decide a
-- exceção é gente do salão, com a pessoa na frente — igual ao encaixe.
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
  /* Fora dos dias: recusa (true) ou cobra o preço cheio (false). Ver o
     cabeçalho — o padrão é o comportamento que já existia. */
  so_nos_dias   boolean not null default false,
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

/* ⚠ O `create table if not exists` acima NÃO acrescenta coluna em tabela que
   já existe — ele não faz nada e segue em frente, calado. Quem já colou o 27
   antes desta versão tem a tabela SEM `so_nos_dias`, e sem esta linha o painel
   gravaria a coluna num banco que não a tem. */
alter table public.pacotes
  add column if not exists so_nos_dias boolean not null default false;

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
--
-- E a FALTA também gasta: "quando a cliente falta, a sessão do pacote deve
-- ser descontada? Sim." O horário ficou guardado para ela e ninguém mais
-- pôde usar. Cancelar continua devolvendo — e, se o salão quiser perdoar
-- uma falta, é só mudar o status para cancelado em vez de "faltou".
-- ---------------------------------------------------------------------------
create or replace function public.pacote_sessoes_restantes(p_pacote_cliente uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, pc.sessoes - (
      select count(*) from public.agendamentos a
       where a.pacote_cliente_id = pc.id
         and a.status in ('pendente','confirmado','em_atendimento','concluido','faltou')
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

-- ---------------------------------------------------------------------------
-- 4b) Os dias escritos como gente escreve
--
-- "seg, ter, qua" cabe num rótulo de tela, mas não numa frase que a cliente lê
-- quando é recusada. `{1,2,3}` vira "segunda, terça e quarta" — com o "e"
-- antes do último, porque é assim que a frase soa lida em voz alta, e uma
-- recusa é exatamente o momento em que o texto não pode parecer de máquina.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 4c) ⚠ O BLOQUEIO: esta cliente tem pacote que PROÍBE marcar neste dia?
--
-- Devolve a frase da recusa, ou NULL quando não há nada a barrar. É o espelho
-- do `pacote_que_cobre()`, com três diferenças que são o ponto todo:
--
--   · exige `so_nos_dias` — sem a coluna ligada, esta função nunca barra nada
--   · o dia da semana tem que estar FORA da lista (`not ... = any`)
--   · devolve texto, não uuid, porque recusa sem motivo escrito é a mesma
--     coisa que horário que some: a Maria abre o link na quinta, não vê nada,
--     e conclui que o salão fechou
--
-- E o resto é igual de propósito: o pacote precisa estar vivo, não vencido,
-- com sessão sobrando e cobrindo TODOS os serviços pedidos. Um pacote sem
-- sessão não bloqueia nada — ele acabou, e acabado ele não manda mais na
-- agenda de ninguém. Um pacote que cobre só metade do pedido também não: ela
-- está marcando outra coisa junto, e isso é uma marcação comum.
--
-- ⚠ A IDENTIDADE, DE NOVO, NÃO É CONFERIDA AQUI — mesmo motivo do
-- `pacote_que_cobre()`: quem exige `perfil_id = auth.uid()` é o `agendar()`.
-- A consequência é honesta e precisa estar escrita: SEM LOGIN o bloqueio não
-- pega, porque sem login o sistema não sabe que é a Maria. Ela marcaria a
-- quinta pagando o preço cheio — que é justamente o que o salão queria que
-- acontecesse fora dos dias. O bloqueio protege a SESSÃO do pacote, não a
-- agenda do salão; quem fecha a agenda de verdade é a jornada.
-- ---------------------------------------------------------------------------
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

  -- O dia é o do SALÃO, pelo mesmo motivo do `pacote_que_cobre()`.
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

  /* A frase diz as três coisas que a pessoa precisa para resolver sozinha:
     qual pacote, quais dias, e o que fazer agora. Sem a última ela fica
     parada na tela — e "não pode" sem saída é o que faz a cliente desistir. */
  return format(
    'Seu pacote %s vale %s. Para marcar fora desses dias, chame o salão no '
    || 'WhatsApp — dá para atender pagando.',
    v_nome, public.dias_por_extenso(v_dias));
end $$;

/* O que a CLIENTE LOGADA vê sobre os próprios pacotes, naquele salão.

   Só os dela: o `where c.perfil_id = auth.uid()` é o filtro, e sem login
   `auth.uid()` é NULL e a lista sai vazia. É esta função que a página usa
   para mostrar R$ 0,00 na lista de serviços — e ela nunca devolve pacote de
   outra pessoa, mesmo que o navegador peça. */
/* ⚠ O `drop` NÃO É LIMPEZA — é obrigação.

   `create or replace` não troca o tipo de retorno de uma função: acrescentar
   `so_nos_dias` à tabela devolvida faz o Postgres recusar com "cannot change
   return type of existing function". Quem já colou o 27 antes desta versão
   tem a função antiga instalada, e sem este `drop` a instalação inteira
   pararia aqui.

   E como `drop` leva os `grant` junto, os dois estão na seção 7 no fim deste
   arquivo, que roda DEPOIS — é lá que a função volta a ser chamável. */
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
  -- Vender pacote é do Básico para cima (22_cotas, exigir_recurso).
  perform public.exigir_recurso(v_salao, 'pacotes', 'Vender pacote');

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
  /* As sessões que ainda VÃO acontecer saem da agenda (43_pacote_agenda.sql:
     com a agenda fixa, o pacote já nasce com as terças marcadas). Ficando,
     a agenda mostraria "pacote (já pago)" para quem saiu do pacote, e o
     horário continuaria ocupado. O que já aconteceu fica, como sempre. */
  update public.agendamentos
     set status = 'cancelado', cancelado_motivo = 'pacote cancelado'
   where pacote_cliente_id = p_id
     and status in ('pendente', 'confirmado')
     and inicio > now();
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

-- Criar pacote é do Básico para cima (22_cotas, exigir_recurso).
create or replace function public.tg_pacote_do_plano() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.exigir_recurso(new.salao_id, 'pacotes', 'Pacote');
  return new;
end $$;
drop trigger if exists tg_pacote_do_plano on public.pacotes;
create trigger tg_pacote_do_plano before insert on public.pacotes
  for each row execute function public.tg_pacote_do_plano();

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

-- ###########################################################################
-- ## 28_sem_comanda.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 28: o salão que não quer comanda nem caixa
--
-- "Não quero trabalhar com comanda e nem caixa. Abre, coloca os serviços e já
--  começa a trabalhar."
--
-- É um pedido comum, e é legítimo: manicure sozinha, barbeiro de cadeira
-- única, quem atende em casa. Para essa gente a comanda é papelada de um
-- movimento que ela já sabe de cor, e o caixa é conferir uma gaveta que só ela
-- abre.
--
-- ── ⚠ O QUE ESTAVA POR BAIXO DO PEDIDO ────────────────────────────────────
-- Comanda e caixa JÁ eram opcionais: nada obriga a abrir nenhum dos dois, e um
-- pagamento sem caixa aberto simplesmente fica sem gaveta (ver
-- `tg_pagamento_caixa` no 17). O pedido parecia ser só de tela.
--
-- Não era. TODO o dinheiro deste sistema nasce da comanda: o `relatorio()` do
-- 12 soma `comandas_totais` de comanda FECHADA, a comissão do 16 mora em
-- `comanda_itens`, e a baixa de estoque do 26 sai do item. Um salão que nunca
-- abrisse comanda teria o mês inteiro zerado — sem erro nenhum na tela, só o
-- número errado, que é a pior forma de errar.
--
-- ── A DECISÃO: UM CAMINHO DE DINHEIRO, DUAS TELAS ─────────────────────────
-- A saída NÃO foi fazer o relatório somar agendamento quando não há comanda.
-- Isso criaria duas verdades sobre faturamento — duas contas para manter
-- iguais para sempre, e a segunda nasceria errada no primeiro recurso que
-- alguém acrescentasse só de um lado.
--
-- Em vez disso, quando o interruptor está DESLIGADO o atendimento concluído
-- vira comanda sozinho: com os serviços do próprio agendamento, o pagamento
-- pelo total, e fechada na hora. Relatório, comissão e estoque continuam
-- lendo exatamente o que sempre leram. A palavra "comanda" é que some da
-- tela — a contabilidade não some.
--
-- ── E POR QUE NO GATILHO, E NÃO NO PAINEL ─────────────────────────────────
-- Porque "o que não está no gatilho não vale" — a lição que o 15 já tinha
-- pago. Concluir um atendimento acontece em mais de um lugar: a agenda da
-- recepção, a tela de quem atende, e um dia uma automação. Regra de dinheiro
-- escrita na tela é regra que o outro caminho não chama.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O INTERRUPTOR
--
-- ⚠ O PADRÃO É LIGADO, e isso não é detalhe: a chave não existe em nenhum
-- salão de hoje, e se a ausência valesse "desligado" todos eles passariam a
-- gerar comanda automática amanhã, por cima das comandas de verdade que eles
-- abrem à mão.
--
-- ⚠ E A PENEIRA É DE TEXTO, não `::boolean`. `'abacaxi'::boolean` LEVANTA no
-- Postgres — não devolve nulo — e um `cfg` com lixo derrubaria a conclusão de
-- todo atendimento do salão. É a mesma armadilha que o `antecedenciaMin` do
-- 14 já tinha custado, com `'abc'::int`.
--
-- Só desliga quem escreveu exatamente que quer desligar. Qualquer outra coisa
-- — chave ausente, vazia, escrita errada — deixa ligado, que é o lado seguro:
-- um erro de digitação nunca apaga a comanda de ninguém.
-- ---------------------------------------------------------------------------
/* ⚠ E O PLANO MANDA ANTES DO INTERRUPTOR: no Grátis não há caixa nem
   comanda (22_cotas), e o salão trabalha como o "sem comanda" daqui — o
   atendimento concluído vira comanda sozinho, e o dinheiro do dia não se
   perde. Ligar o interruptor no Grátis não liga nada. */
create or replace function public.usa_comanda(p_salao uuid)
returns boolean language sql stable set search_path = public as $$
  select coalesce(
    (select lower(btrim(coalesce(sa.cfg->>'usaComanda', 'true')))
              not in ('false', 'f', '0', 'no', 'nao', 'não')
       from public.saloes sa where sa.id = p_salao),
    true)
    and coalesce(public.recurso_bool(p_salao, 'caixa'), false)
$$;

comment on function public.usa_comanda(uuid) is
  'O salão trabalha com comanda e caixa? cfg.usaComanda, padrão LIGADO. Desligado, o atendimento concluído vira comanda sozinho.';

-- ---------------------------------------------------------------------------
-- 2) "NÃO INFORMADO": A FORMA DE PAGAMENTO QUE FALTAVA
--
-- A comanda só fecha paga por inteiro — `tg_fechar_comanda` no 15 recusa com
-- "Ainda faltam R$ x". Então a comanda automática precisa de um pagamento, e
-- nenhuma das formas existentes servia.
--
-- Pôr 'dinheiro' seria mentira com consequência: no dia em que esse salão
-- resolvesse abrir o caixa, a gaveta passaria a esperar um dinheiro que nunca
-- entrou nela. 'cortesia' seria pior ainda — diria que o atendimento foi de
-- graça, e o faturamento sumiria.
--
-- `nao_informado` diz a verdade inteira: a cliente pagou, e o salão escolheu
-- não controlar por onde. É um fato sobre o SALÃO, não sobre a venda.
--
-- ⚠ A restrição é derrubada PELO NOME QUE ELA TEM, descoberto na hora. O
-- `01_schema.sql` a cria embutida na coluna, e o nome gerado pelo Postgres não
-- é promessa de ninguém. Acrescentar uma segunda restrição sem tirar a
-- primeira deixaria a antiga barrando 'nao_informado' — e o sintoma seria a
-- conclusão do atendimento falhando, longe daqui.
-- ---------------------------------------------------------------------------
do $$
declare v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
   where con.conrelid = 'public.pagamentos'::regclass
     and con.contype = 'c'
     and con.conkey = array[(select a.attnum from pg_attribute a
                              where a.attrelid = 'public.pagamentos'::regclass
                                and a.attname = 'forma')]
   limit 1;
  if v_nome is not null then
    execute format('alter table public.pagamentos drop constraint %I', v_nome);
  end if;
end $$;

alter table public.pagamentos
  add constraint pagamentos_forma_check
  check (forma in ('dinheiro','pix','debito','credito',
                   'transferencia','cortesia','pacote','nao_informado',
                   -- O fiado parcelado (47_crediario): só nasce pela venda no
                   -- crediário, nunca digitado na comanda.
                   'crediario'));

-- ---------------------------------------------------------------------------
-- 3) QUEM FOI O SISTEMA, E QUEM FOI GENTE
--
-- Sem esta coluna não há como desfazer: apagar "a comanda deste agendamento"
-- apagaria também a que a recepção montou à mão antes de o interruptor ser
-- desligado — com desconto, com itens acrescentados, com pagamento em duas
-- formas. Ninguém saberia por que sumiu.
--
-- Serve também para a tela: uma comanda automática não tem por que ser
-- editada, porque ela é o espelho do atendimento.
-- ---------------------------------------------------------------------------
alter table public.comandas
  add column if not exists automatica boolean not null default false;

comment on column public.comandas.automatica is
  'Nasceu sozinha ao concluir o atendimento, num salão sem comanda. Desmarcar o atendimento a apaga.';

-- ---------------------------------------------------------------------------
-- 4) ⚠ O GATILHO: CONCLUIR VIRA DINHEIRO
--
-- Cinco recusas antes de criar qualquer coisa, e nenhuma é dispensável:
--
--   · o salão usa comanda  → a tela dele faz isso, e melhor: com desconto,
--                            produto, forma de pagamento
--   · já existe comanda    → a recepção montou à mão. Uma segunda cobraria o
--                            atendimento duas vezes, e o índice único do 15
--                            derrubaria a conclusão inteira
--   · sem ficha de cliente → comanda sem cliente não existe no schema
--   · total zero           → ⚠ NÃO É CASO RARO: é o pacote. Uma manutenção
--                            coberta pelo pacote vale R$ 0,00, e
--                            `tg_fechar_comanda` recusa comanda sem itens com
--                            "Comanda sem itens não pode ser fechada" — a
--                            conclusão do atendimento morreria com essa frase,
--                            que não tem nada a ver com o que a pessoa fez.
--                            E está certo não criar: não houve dinheiro
--                            nenhum, a sessão do pacote é que foi gasta
--   · o serviço sumiu      → `left join`, para um serviço apagado do cadastro
--                            não levar o atendimento junto
--
-- A comissão NÃO é copiada daqui: o `tg_item_comissao` do 16 resolve a taxa
-- pelo cadastro, com a escada do profissional e do serviço. Mandar a de
-- `agendamento_servicos` seria congelar a taxa do dia da MARCAÇÃO, e o 16
-- existe justamente para isso não acontecer.
--
-- `aberta_por` fica nulo de propósito. Não foi ninguém: foi o sistema. Pôr o
-- nome de quem clicou seria dizer que aquela pessoa abriu uma comanda que ela
-- nunca viu.
-- ---------------------------------------------------------------------------
create or replace function public.tg_agendamento_sem_comanda()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_comanda uuid;
  v_total   numeric(10,2);
begin
  /* ── DESFAZER ────────────────────────────────────────────────────────────
     Vem primeiro porque é o caso que mais dói se faltar: a recepção conclui
     por engano, corrige, e o dinheiro de um atendimento que não houve fica no
     relatório do mês. Só apaga o que o sistema criou. */
  if coalesce(old.status, '') = 'concluido' and new.status <> 'concluido' then
    delete from public.comandas c
     where c.agendamento_id = new.id and c.automatica;
    return new;
  end if;

  if new.status <> 'concluido' or coalesce(old.status, '') = 'concluido' then
    return new;
  end if;

  if public.usa_comanda(new.salao_id) then return new; end if;
  if new.cliente_id is null then return new; end if;
  /* Sessão de PACOTE não é dinheiro de hoje: a cliente pagou adiantado, e o
     `agendar()` já gravou o valor zero. Mas a linha do serviço guarda o preço
     cheio (é sobre ele que a escada de preço e a comissão olham), e somar
     essas linhas fazia a sessão virar uma comanda fechada de preço cheio —
     faturamento em dobro e comissão de um serviço que não entrou no caixa. */
  if new.pacote_cliente_id is not null then return new; end if;
  if exists (select 1 from public.comandas c
              where c.agendamento_id = new.id) then return new; end if;

  select round(coalesce(sum(s.preco), 0), 2) into v_total
    from public.agendamento_servicos s
   where s.agendamento_id = new.id;

  /* O cupom (34_cupons.sql): o item fica com o preço cheio — é sobre ele que
     a comissão sai —, e a comanda leva o desconto, como a recepção faria. */
  v_total := v_total - least(coalesce(new.desconto, 0), coalesce(v_total, 0));

  if v_total is null or v_total <= 0 then return new; end if;

  insert into public.comandas (salao_id, agendamento_id, cliente_id, automatica,
                               desconto, desconto_motivo)
       values (new.salao_id, new.id, new.cliente_id, true, coalesce(new.desconto, 0),
               (select 'Cupom ' || cp.codigo from public.cupons cp where cp.id = new.cupom_id))
    returning id into v_comanda;

  insert into public.comanda_itens (comanda_id, tipo, servico_id, descricao,
                                    qtd, preco_unit, profissional_id)
  select v_comanda, 'servico', s.servico_id,
         coalesce(sv.nome, 'Serviço'), 1, s.preco, new.profissional_id
    from public.agendamento_servicos s
    left join public.servicos sv on sv.id = s.servico_id
   where s.agendamento_id = new.id
   order by s.ordem;

  insert into public.pagamentos (comanda_id, forma, valor)
       values (v_comanda, 'nao_informado', v_total);

  update public.comandas
     set status = 'fechada', fechada_em = now()
   where id = v_comanda;

  return new;
end $$;

/* ⚠ AFTER, e não BEFORE.

   Os itens são lidos de `agendamento_servicos`, que aponta para o
   agendamento. Num BEFORE a linha ainda não está gravada no estado que o
   resto do gatilho enxerga, e o `insert` da comanda referenciaria um
   agendamento que, para ele, ainda não terminou de existir. */
drop trigger if exists tg_agend_sem_comanda on public.agendamentos;
create trigger tg_agend_sem_comanda
  after update of status on public.agendamentos
  for each row execute function public.tg_agendamento_sem_comanda();

-- ---------------------------------------------------------------------------
-- 5) Quem pode perguntar
--
-- `usa_comanda()` responde sobre CONFIGURAÇÃO, não sobre dinheiro: a página
-- pública nunca precisa dela, e a equipe precisa para a tela saber o que
-- esconder. Fica com `authenticated`.
-- ---------------------------------------------------------------------------
revoke all on function public.usa_comanda(uuid) from public, anon;
grant execute on function public.usa_comanda(uuid) to authenticated;

-- ###########################################################################
-- ## 29_confirmacao.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 29: o salão confirma, ou o link confirma sozinho
--
-- "O cliente receberá uma mensagem de confirmação. Isso é configurável: ou o
--  dono confirma, ou a confirmação é automática assim que o cliente marca."
--
-- ── COMO ERA ──────────────────────────────────────────────────────────────
-- O `agendar()` gravava `'confirmado'` escrito à mão. O status `'pendente'`
-- existia no schema desde o começo e era tratado em todo lugar — `ha_choque`
-- conta ele, o `porque_nao_agenda` conta ele, a cota conta ele — mas NADA
-- NESTE SISTEMA CRIAVA UM. Era uma porta pronta que ninguém abria.
--
-- ── ⚠ E POR QUE NÃO BASTAVA TROCAR A PALAVRA ──────────────────────────────
-- Trocar `'confirmado'` por `'pendente'` no `agendar()` mandaria, no mesmo
-- instante, um WhatsApp dizendo "Seu horário está confirmado" — de um horário
-- que o dono ainda não olhou.
--
-- O `tg_notificar_agendamento()` do 21 dispara no INSERT e aceita os dois
-- status. Então a mudança de verdade é nas duas pontas ao mesmo tempo:
--
--   · o 21 passa a exigir `confirmado` para a confirmação E para o lembrete
--   · este módulo acrescenta o gatilho que falta: quando o horário VIRA
--     confirmado, a mensagem sai naquele momento
--
-- Sem o segundo, o salão confirmaria e a cliente nunca saberia.
--
-- ── O QUE CONTINUA SAINDO NA HORA ─────────────────────────────────────────
-- O aviso para quem vai atender (`tipo = 'novo'`). É ele que avisa o dono de
-- que tem coisa esperando resposta — segurá-lo até a confirmação seria pedir
-- que ele confirmasse algo que ninguém contou que existe.
--
-- ── O HORÁRIO FICA SEGURO ENQUANTO ESPERA ─────────────────────────────────
-- `ha_choque()` no 14 já conta `'pendente'`, então a cadeira fica reservada
-- enquanto o dono decide. Se não contasse, duas pessoas marcariam o mesmo
-- horário durante a espera — e uma delas ouviria "não" depois de já ter
-- combinado o dia.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O INTERRUPTOR
--
-- ⚠ O PADRÃO É AUTOMÁTICO, que é como o sistema sempre funcionou. Se a
-- ausência da chave valesse "o dono confirma", todo salão que já usa o link
-- acordaria amanhã com a agenda cheia de pendências que ninguém pediu — e
-- clientes esperando uma resposta que o dono não sabe que deve dar.
--
-- A peneira é de texto pelo mesmo motivo do 28: `'abacaxi'::boolean` LEVANTA
-- no Postgres, e um cast desprotegido aqui derrubaria TODA marcação do salão.
-- ---------------------------------------------------------------------------
/* ⚠ `security definer`, e a falta dele reprovou a seção 7 do teste.

   A função lê `public.saloes`, e a RLS dessa tabela é para gente com vínculo.
   Rodando como quem chama, `anon` levava `permission denied for table saloes`
   — e quem abre o link da cliente é exatamente `anon`.

   O efeito na tela seria mudo: a chamada falha, o `catch` da página engole, e
   ela cai no padrão "confirma sozinho". A cliente de um salão que confirma à
   mão leria "Pronto, está confirmado" de um horário pendente.

   Não abre nada: a resposta é um sim ou não sobre a política de um salão cujo
   link é público de propósito, e o `p_salao` é o mesmo id que está na URL. */
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

-- ---------------------------------------------------------------------------
-- 2) ⚠ A MENSAGEM QUE ESPERAVA O DONO
--
-- Reaproveita a MESMA função do 21, e isso não é economia de linhas: é a
-- garantia de que a confirmação que sai depois é idêntica à que sai na hora.
-- Uma segunda função escrita aqui divergiria da primeira no dia em que alguém
-- mexesse em só uma delas — e ninguém perceberia, porque as duas "funcionam".
--
-- Os três `insert` de lá terminam em `on conflict (salao_id, chave) do
-- nothing`, então rodar de novo não duplica nada. Confirmar duas vezes, ou
-- confirmar um horário que já tinha saído confirmado, não manda dois
-- WhatsApps.
--
-- O `when` faz o trabalho de decidir: só na TRANSIÇÃO para confirmado. Posto
-- na condição do gatilho, e não dentro da função, porque a função é do 21 e
-- não deve saber que este módulo existe.
-- ---------------------------------------------------------------------------
drop trigger if exists tg_notif_agend_confirmado on public.agendamentos;
create trigger tg_notif_agend_confirmado
  after update of status on public.agendamentos
  for each row
  when (new.status = 'confirmado' and old.status is distinct from 'confirmado')
  execute function public.tg_notificar_agendamento();

-- ---------------------------------------------------------------------------
-- 3) Quem pode perguntar
--
-- ⚠ `anon` TAMBÉM, e aqui é diferente do 28. A página da cliente precisa saber
-- ANTES de ela confirmar se o horário vai ficar pendente — é o que decide
-- entre "Pronto, está confirmado" e "Você receberá uma mensagem de
-- confirmação". E quem abre o link não tem conta.
--
-- Não vaza nada: a resposta é um sim ou não sobre a política de um salão cujo
-- link é público de propósito.
-- ---------------------------------------------------------------------------
revoke all on function public.confirma_automatico(uuid) from public;
grant execute on function public.confirma_automatico(uuid) to anon, authenticated;

-- ###########################################################################
-- ## 30_painel.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 30: os números do dashboard
--
-- Uma chamada só devolve tudo o que os cartões do dashboard desenham. A tela
-- não soma nada: escolhe o que mostrar e desenha o que veio.
--
-- ── POR QUE ISTO É UMA FUNÇÃO E NÃO DOZE CHAMADAS DE `relatorio()` ────────
-- O cartão do faturamento anual precisa de doze meses. Pelo `relatorio()`
-- seriam doze idas ao banco para abrir uma tela — num celular em rede de
-- salão, é a tela que demora tanto que ninguém abre duas vezes.
--
-- ── ⚠ E POR QUE O FATURAMENTO É CONTADO EXATAMENTE COMO LÁ ───────────────
-- Comanda FECHADA, pelo `fechada_em`, somada pela vista `comandas_totais`.
-- É a mesma definição do `relatorio()` e do Caixa, e isso não é detalhe: este
-- projeto já teve dois faturamentos discordando na mesma tela, e a conclusão
-- do dono — com razão — é parar de confiar no sistema inteiro.
--
-- Vale nos dois modos do salão. Com comanda, é a comanda que a recepção
-- fecha; sem comanda, o gatilho `tg_agend_sem_comanda` cria uma comanda
-- fechada quando o atendimento vira "concluído". Os dois caminhos terminam
-- na mesma linha, então uma consulta só serve para os dois.
--
-- ── ⚠ O FUSO É O DO SALÃO, NUNCA O DE QUEM OLHA ──────────────────────────
-- Um dono viajando leria o mês começando às 20h do dia 31. Já custou caro
-- neste projeto mais de uma vez: toda data que o banco compara está no fuso
-- do salão.
-- ===========================================================================

create or replace function public.painel_grafico(p_salao uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso  text;
  v_hoje  date;
begin
  /* Mesma linha do `relatorio()`: faturamento da casa inteira é assunto de
     GESTÃO, não da recepção nem de quem atende. E é ela que impede o dono do
     salão B de ler o ano do salão A trocando o uuid na chamada. */
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  select fuso into v_fuso from public.saloes where id = p_salao;
  v_fuso := coalesce(v_fuso, 'America/Sao_Paulo');
  v_hoje := (now() at time zone v_fuso)::date;

  return jsonb_build_object(

    /* ── DOZE MESES, INCLUSIVE OS VAZIOS ──────────────────────────────────
       O `generate_series` existe para isto: um mês sem faturamento tem que
       aparecer como zero, e não sumir. Vindo só os meses com venda, a linha
       do gráfico ligaria março a setembro como se fossem vizinhos — e o
       salão pareceria ter crescido quando na verdade ficou parado. */
    'ano', coalesce((
      select jsonb_agg(jsonb_build_object(
               'mes', to_char(m.ini, 'YYYY-MM'),
               'valor', coalesce((
                 select round(sum(t.total), 2)
                   from public.comandas_totais t
                  where t.salao_id = p_salao and t.status = 'fechada'
                    and (t.fechada_em at time zone v_fuso)::date >= m.ini::date
                    and (t.fechada_em at time zone v_fuso)::date
                        < (m.ini + interval '1 month')::date), 0))
             order by m.ini)
        from generate_series(
               date_trunc('month', v_hoje::timestamp) - interval '11 months',
               date_trunc('month', v_hoje::timestamp),
               interval '1 month') as m(ini)), '[]'::jsonb),

    -- Sete dias terminando HOJE. É a semana móvel, e não a semana do
    -- calendário: quem abre o dashboard numa terça quer os últimos sete
    -- dias, não dois dias de semana e cinco quadradinhos vazios.
    'semana', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', d.dia::date,
               'valor', coalesce((
                 select round(sum(t.total), 2)
                   from public.comandas_totais t
                  where t.salao_id = p_salao and t.status = 'fechada'
                    and (t.fechada_em at time zone v_fuso)::date = d.dia::date), 0))
             order by d.dia)
        from generate_series(v_hoje - 6, v_hoje, interval '1 day') as d(dia)),
      '[]'::jsonb),

    /* ── O QUE ESTÁ ESPERANDO O DONO ──────────────────────────────────────
       Agendamento pendente é cliente que pediu horário e ainda não teve
       resposta. É o número mais urgente do dashboard: cada unidade aqui é
       alguém esperando, e esperando é como se perde a marcação para o salão
       da esquina.

       Só do dia de hoje para a frente: pendente de semana passada já não é
       tarefa, é histórico, e misturar os dois faria o número nunca zerar. */
    'pendentes', (
      select count(*) from public.agendamentos a
       where a.salao_id = p_salao and a.status = 'pendente'
         and (a.inicio at time zone v_fuso)::date >= v_hoje),

    -- Quem vem hoje e ainda não foi atendido. O número que responde "posso
    -- sair para almoçar?".
    'hojeRestam', (
      select count(*) from public.agendamentos a
       where a.salao_id = p_salao
         and a.status in ('pendente','confirmado','em_atendimento')
         and (a.inicio at time zone v_fuso)::date = v_hoje),

    /* ── O QUE MAIS VENDE, NOS ÚLTIMOS 90 DIAS ────────────────────────────
       Noventa e não trinta: salão tem serviço de intervalo longo — luzes,
       progressiva — que em trinta dias aparece uma vez e some do ranking,
       embora seja o que paga o mês.

       Sai do ITEM, e não da comanda: uma cliente que fez corte e escova
       conta para os dois. */
    'topServicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nome', x.nome, 'qtd', x.qtd, 'valor', x.valor)
             order by x.valor desc)
        from (select coalesce(s.nome, i.descricao, 'Serviço') as nome,
                     count(*) as qtd,
                     round(sum(i.total), 2) as valor
                from public.comanda_itens i
                join public.comandas c on c.id = i.comanda_id
                left join public.servicos s on s.id = i.servico_id
               where c.salao_id = p_salao and c.status = 'fechada'
                 and i.tipo = 'servico'
                 and (c.fechada_em at time zone v_fuso)::date >= v_hoje - 90
               group by 1
               order by 3 desc
               limit 5) x), '[]'::jsonb),

    -- As clientes que mais gastaram no mesmo período. É com quem o salão
    -- fala primeiro quando abre uma agenda ou lança um pacote.
    'topClientes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nome', x.nome, 'visitas', x.visitas, 'valor', x.valor)
             order by x.valor desc)
        from (select cl.nome,
                     count(distinct t.id) as visitas,
                     round(sum(t.total), 2) as valor
                from public.comandas_totais t
                join public.clientes cl on cl.id = t.cliente_id
               where t.salao_id = p_salao and t.status = 'fechada'
                 and (t.fechada_em at time zone v_fuso)::date >= v_hoje - 90
               group by cl.id, cl.nome
               order by 3 desc
               limit 5) x), '[]'::jsonb),

    /* ── QUEM SUMIU ───────────────────────────────────────────────────────
       Cliente que já veio e não volta há mais de 60 dias. É a lista mais
       rentável que um salão tem e a que ninguém faz: trazer de volta quem já
       conhece a casa custa uma mensagem, e conquistar uma nova custa
       anúncio.

       ⚠ QUEM NUNCA VEIO NÃO ENTRA. Ficha cadastrada e nunca atendida não é
       "sumida", é cadastro — e misturá-las faria o número crescer com o
       cadastro em vez de com o problema. */
    'sumidas', (
      select count(*) from (
        select t.cliente_id, max((t.fechada_em at time zone v_fuso)::date) as ultima
          from public.comandas_totais t
         where t.salao_id = p_salao and t.status = 'fechada'
         group by t.cliente_id) u
       where u.ultima < v_hoje - 60),

    'dia', v_hoje
  );
end $$;

/* A mesma porta do `relatorio()`: só quem está logado, e a própria função
   confere se é gestão. `anon` não entra — a página pública nunca precisa
   disto, e faturamento do salão não é assunto de visitante. */
revoke all on function public.painel_grafico(uuid) from public, anon;
grant execute on function public.painel_grafico(uuid) to authenticated;

-- ###########################################################################
-- ## 31_dias_servico.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 31: o serviço que só é feito em certos dias
--
-- "Escova só de quinta a sábado." Pedido de quem tem serviço longo que só cabe
-- em dia de movimento fraco, e de quem tem profissional que vem dois dias por
-- semana fazer uma coisa específica.
--
-- ── O QUE JÁ EXISTIA, E POR QUE NÃO SERVIA ────────────────────────────────
-- A restrição de dia só existia DENTRO do pacote (`pacotes.so_nos_dias`, no
-- 27). Aquela é outra pergunta: ela diz em que dias a SESSÃO DO PACOTE pode
-- ser usada, vale só para quem tem o pacote, e o salão continua vendendo o
-- mesmo serviço a preço cheio nos outros dias. Esta aqui é sobre o serviço em
-- si, para todo mundo.
--
-- ── ⚠ ONDE A REGRA MORA, E POR QUE ─────────────────────────────────────────
-- No `porque_nao_agenda()`, que é a ÚNICA porta da política da agenda online.
-- Três coisas saem de graça por morar ali:
--
--   · o `horarios_livres()` a respeita sozinho — ele começa perguntando a esta
--     função e desiste quando ela responde. Então o dia deixa de oferecer
--     horário sem nenhuma linha a mais;
--   · o `agendar()` também pergunta antes de gravar, então a recusa é do
--     BANCO. Ninguém marca a segunda-feira mexendo no navegador;
--   · e a RECEPÇÃO continua livre. O painel grava na tabela direto, sem passar
--     por aqui. É a mesma divisão de sempre neste projeto: o link é uma
--     peneira de política, a recepção é a dona da agenda. Se a cliente ligar
--     pedindo escova na segunda e a dona quiser fazer, ela marca.
--
-- ── ⚠ NULO E VAZIO QUEREM DIZER A MESMA COISA AQUI, DE PROPÓSITO ──────────
-- Em quase todo o resto deste projeto ausente e vazio são estados diferentes,
-- e confundi-los já causou defeito três vezes. Aqui eles são o MESMO estado —
-- "todos os dias" — e é decisão, não descuido:
--
--   · nulo é o serviço que nunca foi tocado. Todo serviço que já existe nasce
--     assim no dia em que esta coluna aparece, e nenhum deles pode mudar de
--     comportamento;
--   · vazio seria "nenhum dia". Um serviço que não pode ser marcado em dia
--     nenhum não é uma configuração, é um serviço DESLIGADO — e para isso já
--     existe o `ativo`, que diz a mesma coisa num lugar onde o dono procura.
--
-- Lido como "nenhum dia", o vazio faria o serviço sumir do link sem aviso, e o
-- dono passaria a tarde procurando o defeito numa tela que está funcionando.
-- A tela do painel também se recusa a salvar zero dias; esta linha é a
-- segunda tranca, para o caso de o valor chegar por outro caminho.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) A coluna — ⚠ DECLARADA NO 25_loja.sql, e não aqui
--
-- `servicos.dias` é `smallint[]` no padrão do Postgres: 0 = domingo. O mesmo
-- formato de `pacotes.dias`, de propósito — duas grafias para a mesma ideia
-- dentro do mesmo banco é convite para erro de fuso disfarçado de erro de
-- índice.
--
-- Ela é desta funcionalidade, mas a linha `alter table` está no 25_loja.sql,
-- logo acima da `vitrine()`. Motivo do Postgres, não de arquitetura: a
-- `vitrine()` é função SQL, o `create or replace` COMPILA o corpo na hora, e
-- ela lê `v.dias`. Nas duas montagens o 25 roda antes do 31, então declarar
-- aqui faria o install inteiro parar com "column v.dias does not exist".
-- Aconteceu, e é o tipo de erro que só aparece na instalação do zero.
--
-- Aqui fica só o `comment`, que é onde um DBA vai procurar o significado.
-- ---------------------------------------------------------------------------
comment on column public.servicos.dias is
  'Dias da semana em que o LINK oferece este serviço (0=domingo). NULL ou vazio = todos os dias. A recepção nunca é limitada por isto.';

-- ---------------------------------------------------------------------------
-- 2) Qual serviço do pedido não cabe neste dia?
--
-- Devolve a frase pronta, ou NULL quando não há nada a barrar. Texto e não
-- booleano pelo mesmo motivo do `pacote_fora_do_dia()`: recusa sem motivo
-- escrito é igual a horário que some. A cliente abre a segunda-feira, não vê
-- nada, e conclui que o salão fechou.
--
-- ⚠ BASTA UM SERVIÇO DO PEDIDO ESTAR FORA. Ela escolheu corte + escova para o
-- mesmo horário; se a escova não é feita na segunda, o par não cabe na
-- segunda. Barrar só quando TODOS estão fora deixaria passar a marcação de um
-- combinado que o salão não consegue cumprir — e o problema só apareceria com
-- a cliente sentada na cadeira.
--
-- A frase nomeia o serviço porque ela pode ter escolhido três: sem o nome, a
-- pessoa não sabe qual tirar do carrinho para resolver.
-- ---------------------------------------------------------------------------
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

  /* ⚠ O DIA SAI DA DATA, E NÃO DE `now()`. Quem chama já converteu o instante
     para a data DO SALÃO — é o `porque_nao_agenda()` e o `agendar()`, os dois
     pelo fuso do salão. Recalcular aqui com o fuso do servidor poria a
     quinta-feira de alguém na quarta, e seria um daqueles defeitos que só
     aparecem depois das 21h. */
  v_dia := extract(dow from p_data)::smallint;

  select s.nome, s.dias into v_nome, v_dias
    from public.servicos s
   where s.id = any(p_servicos)
     and s.dias is not null
     and cardinality(s.dias) > 0        -- vazio é "todos", ver o cabeçalho
     and not (v_dia = any(s.dias))
   order by s.nome
   limit 1;

  if v_nome is null then return null; end if;

  /* A frase diz as três coisas que resolvem sozinhas: o que não cabe, quando
     cabe, e o que fazer agora. Sem a última ela fica sabendo que não pode e
     não sabe o que fazer — que é o mesmo que não ter resposta. */
  /* ⚠ SEM CONCORDÂNCIA DE GÊNERO NA FRASE. Aqui estava "%s é feito só %s", e
     saía "Escova é feito só quinta" — o nome do serviço é texto livre do dono,
     e metade deles é feminino. Não dá para adivinhar o gênero, e errar a
     concordância numa recusa é o tipo de detalhe que faz a página parecer
     descuidada exatamente no momento em que ela está negando alguma coisa.

     Dois-pontos resolvem sem adivinhar nada. */
  return format(
    '%s: só %s. Escolha um desses dias, tire este serviço do pedido, '
    || 'ou chame o salão no WhatsApp.',
    v_nome, public.dias_por_extenso(v_dias));
end $$;

comment on function public.servico_fora_do_dia(uuid[], date) is
  'Frase de recusa quando algum serviço do pedido não é feito no dia da semana pedido. NULL quando não há nada a barrar. Só o link usa: a recepção marca por fora.';

/* ⚠ SEM GRANT NENHUM, e não `to anon, authenticated`.

   Eu tinha liberado as duas para o anon por reflexo — "é o link que usa, o
   link é anônimo". Errado: quem o link chama é a `porque_nao_agenda()` e o
   `entrar_na_fila()`, e as duas são `security definer`. Enquanto elas rodam,
   quem executa é o DONO da função, não a cliente — então a ajudante não
   precisa estar aberta a ninguém.

   Quem apontou foi o `portas.test.sql`, que cobra justificativa de toda
   `security definer` aberta ao anon. E ele só chegou a rodar porque o
   `tests/rodar.sh` passou a instalar o módulo 31 — antes ele parava no 29, e
   estas duas funções nunca existiram no banco de teste. Um guarda que não
   enxerga metade da casa não é um guarda.

   Aberta ao anon, `servico_fora_do_dia` é uma consulta sobre serviços de
   QUALQUER salão, com o id no parâmetro: um id adivinhado devolve o nome do
   serviço na frase de recusa. Pouco, mas é mais do que zero, e de graça. */
revoke all on function public.servico_fora_do_dia(uuid[], date) from public;

-- ---------------------------------------------------------------------------
-- 2b) A MESMA PERGUNTA, PARA UM PERÍODO INTEIRO
--
-- A lista de espera não pede um dia: pede uma JANELA ("de 27 a 30, qualquer
-- turno"). A pergunta certa ali é outra — existe ALGUM dia dessa janela em
-- que o salão faz tudo o que ela pediu?
--
-- ── ⚠ POR QUE ISTO PRECISOU EXISTIR ───────────────────────────────────────
-- Sem ela, o mesmo link RECUSAVA marcar escova na segunda, com a frase certa,
-- e ACEITAVA a cliente na fila de espera de domingo a quarta — uma janela em
-- que a escova não é feita em dia nenhum.
--
-- É a pior forma de falhar que este projeto conhece: nada dá erro, a cliente
-- recebe um "pronto, a gente te avisa", e espera um telefonema que não pode
-- acontecer. Do lado do salão também não aparece nada — a fila tem um pedido
-- impossível no meio dos possíveis.
--
-- ⚠ E BASTA UM DIA PARA ACEITAR. Se a janela pega uma quinta, a fila é
-- legítima: o salão vai oferecer a quinta. Recusar uma janela por ela conter
-- dias ruins seria recusar quase todas — quase toda janela de uma semana tem
-- pelo menos um dia de fora.
-- ---------------------------------------------------------------------------
create or replace function public.servico_fora_do_periodo(
  p_servicos uuid[], p_de date, p_ate date)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_dia date;
begin
  if p_servicos is null or cardinality(p_servicos) = 0
     or p_de is null or p_ate is null or p_ate < p_de then
    return null;
  end if;

  /* Sai no primeiro dia que serve. A janela é limitada pelo `dias_liberados`
     de quem chama, então isto roda dezenas de vezes, não milhares — e para na
     primeira quinta-feira que aparecer. */
  for v_dia in select d::date from generate_series(p_de, p_ate, interval '1 day') d
  loop
    if public.servico_fora_do_dia(p_servicos, v_dia) is null then
      return null;
    end if;
  end loop;

  -- Nenhum dia serve: a frase é a mesma da recusa de marcar, para a cliente
  -- não receber duas explicações diferentes do mesmo motivo.
  return public.servico_fora_do_dia(p_servicos, p_de);
end $$;

comment on function public.servico_fora_do_periodo(uuid[], date, date) is
  'Frase de recusa quando NENHUM dia do período serve para os serviços pedidos. NULL quando pelo menos um serve. Usada pela lista de espera.';

-- Sem grant, pelo mesmo motivo da irmã: quem a chama é o `entrar_na_fila()`,
-- que é `security definer` e roda como dono.
revoke all on function public.servico_fora_do_periodo(uuid[], date, date) from public;

-- ---------------------------------------------------------------------------
-- 3) A POLÍTICA DA AGENDA ONLINE, COM O DIA DO SERVIÇO NO MEIO
--
-- ⚠ VAI INTEIRA, E NÃO UM REMENDO. `create or replace function` não sabe
-- acrescentar linha: o corpo que estiver aqui é o corpo que vale. Esta é cópia
-- fiel da versão do 19_teto_online.sql com UM bloco a mais — e, como este
-- arquivo tem número maior, é esta que passa a valer.
--
-- ⚠ E É POR ISSO QUE REINSTALAR UM MÓDULO SOZINHO NUM BANCO JÁ MONTADO
-- ESTRAGA COISA. Rodar o 19 por cima de um banco com o 31 devolve a versão
-- sem esta regra, sem erro nenhum, porque é tudo `create or replace`. Para
-- mexer no SQL, monte do zero. Está escrito no `tests/bancada/subir.sh` com o
-- caso concreto que custou uma hora.
--
-- ── ONDE O BLOCO NOVO ENTRA, E POR QUE AÍ ─────────────────────────────────
-- Depois das duas conferências de data e antes dos dois limites do fim.
--
--   · depois de "essa data já passou" e de "a agenda está liberada até": uma
--     data de ontem é problema maior, e dizer "escova é feita só às quintas"
--     sobre uma quinta-feira do mês passado seria uma resposta certa para a
--     pergunta errada;
--   · antes dos limites do balcão e da rajada, que são os únicos que a pessoa
--     NÃO tem como resolver. Mandá-la ao WhatsApp antes de avisar que bastava
--     trocar de dia é mandá-la embora à toa.
-- ---------------------------------------------------------------------------
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

  -- ── O DIA DA SEMANA DO SERVIÇO ─────────────────────────────────────────
  -- Serviço sem dias marcados não passa por aqui: a função devolve NULL e
  -- nada muda para ele. É o caso de todo serviço que já existe.
  v_motivo := public.servico_fora_do_dia(p_servicos, p_data);
  if v_motivo is not null then
    return v_motivo;
  end if;

  /* ── A RESERVA DO BALCÃO ───────────────────────────────────────────────
     A conta é em minutos e inclui o que está sendo pedido AGORA: sem isso a
     última marcação sempre passaria, e a reserva vazaria um atendimento
     inteiro — logo o maior deles, porque é o que mais demora a caber. */
  v_jornada := public.minutos_de_jornada(p_profissional, p_data);
  if v_jornada > 0 then
    v_online := public.minutos_online_no_dia(p_profissional, p_data);
    v_pedido := public.duracao_dos_servicos(p_profissional, p_servicos);
    if (v_online + v_pedido) * 100 > v_jornada * public.teto_online_pct(v_salao) then
      return 'Este dia já está quase todo marcado. '
          || 'Chame o salão no WhatsApp que a gente encaixa você.';
    end if;
  end if;

  /* ── O FREIO DE RAJADA ─────────────────────────────────────────────────
     Nenhuma das duas frases fala em limite, cota ou teto, e é decisão: quem
     lê isto na esmagadora maioria das vezes é uma cliente de verdade num
     salão movimentado, e ela precisa de um caminho, não da explicação de um
     mecanismo. O caminho é o WhatsApp, onde tem gente.

     E para quem está do outro lado tentando encher a agenda, a frase também
     não entrega nada: não diz qual é o número nem quanto falta. */
  if public.rajada_online(v_salao) >= public.teto_online_rajada(v_salao) then
    return 'A marcação pela internet está congestionada agora. '
        || 'Tente daqui a pouco, ou chame o salão no WhatsApp.';
  end if;

  return null;
end $$;

-- ###########################################################################
-- ## 32_produto_cadastro.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 32: o que faltava no cadastro de produto
--
-- Três coisas, vindas da comparação com os prints que o dono mandou:
--
--   1. o PREÇO pode ficar escondido da cliente sem esconder o produto;
--   2. cada PROFISSIONAL pode ter comissão própria naquele produto;
--   3. o estoque passa a ter HISTÓRICO — quem mexeu, quando, e por quê.
--
-- A coluna `preco_visivel` é declarada no 25_loja.sql, junto com
-- `servicos.dias` e pelo mesmo motivo do Postgres: a `vitrine()` é função SQL,
-- o `create or replace` compila o corpo na hora, e nas duas montagens o 25
-- roda antes deste arquivo. O comentário completo está lá.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O PREÇO ESCONDIDO — e por que não é o mesmo que esconder o produto
--
-- `venda_online` já decide se o produto APARECE na loja. Este é outro eixo: o
-- produto aparece, com foto e nome, e o valor sai por WhatsApp.
--
-- Não é firula de vitrine. Produto de revenda com preço tabelado pelo
-- fabricante, produto que o salão vende mais caro que a farmácia da esquina,
-- e produto cujo preço muda toda semana — nos três casos o dono quer mostrar
-- que tem, e não quer publicar quanto custa.
--
-- ⚠ PADRÃO `true`, e é o que faz esta linha não mudar nada. Todo produto que
-- já existe passa a ter `preco_visivel = true`, que é exatamente o que a loja
-- faz hoje. Ninguém acorda com a loja diferente.
-- ---------------------------------------------------------------------------
comment on column public.produtos.preco_visivel is
  'O preço aparece na loja do link? Padrão true — o que a loja sempre fez. False mostra o produto sem o valor, e a cliente pergunta no WhatsApp.';

-- ---------------------------------------------------------------------------
-- 2) COMISSÃO DO PRODUTO POR PROFISSIONAL
--
-- Espelho de `servicos_profissionais`, e de propósito: a mesma ideia com duas
-- formas diferentes dentro do mesmo banco é convite para erro.
--
-- ⚠ `id` PRÓPRIO, E NÃO SÓ A CHAVE DO PAR. É a mesma lição que
-- `servicos_profissionais` aprendeu doendo: o `Dados.subir()` compara os
-- retratos por `id`, e linha sem ele vira a chave `undefined` — duas viram a
-- mesma, a segunda sobrescreve a primeira, e sobe UMA. Sem erro nenhum. O
-- dono cadastraria a comissão de cinco pessoas e o banco ficaria com uma.
-- ---------------------------------------------------------------------------
create table if not exists public.produtos_profissionais (
  id             uuid primary key default gen_random_uuid(),
  produto_id     uuid not null references public.produtos(id) on delete cascade,
  profissional_id uuid not null references public.profissionais(id) on delete cascade,
  /* Anuláveis, e é o ponto: nulo quer dizer "este degrau não fala em
     comissão, herda de baixo". Zero quer dizer "fala, e é zero". A diferença
     é o que permite escrever "a Ana ganha 20% em tudo, menos neste produto,
     onde não ganha nada". */
  comissao_pct   numeric(5,2) check (comissao_pct between 0 and 100),
  comissao_fixa  numeric(10,2) check (comissao_fixa >= 0),
  unique (produto_id, profissional_id)
);

comment on table public.produtos_profissionais is
  'Exceção de comissão de um produto para um profissional. Linha ausente = usa a comissão do produto. Espelho de servicos_profissionais.';

alter table public.produtos_profissionais enable row level security;

/* As mesmas duas policies de `servicos_profissionais`, pelo mesmo desenho:
   quem tem acesso ao salão LÊ, quem é gestão ESCREVE.

   ⚠ E separadas por verbo, nunca `for all` numa só. Policy `for all` vale
   também para SELECT, e o Postgres soma as permissivas com OU: uma policy de
   escrita da gestão ao lado de uma de leitura restrita anula a restrição. É
   um dos dois defeitos que os testes deste projeto pegaram antes de existir
   tela, e está no README. */
drop policy if exists pp_ler on public.produtos_profissionais;
create policy pp_ler on public.produtos_profissionais for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and e_equipe(p.salao_id)) );
drop policy if exists pp_gerir on public.produtos_profissionais;
create policy pp_gerir on public.produtos_profissionais for all to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and e_gestor(p.salao_id)) )
  with check ( exists (select 1 from public.produtos p
                        where p.id = produto_id and e_gestor(p.salao_id)) );

grant select, insert, update, delete on public.produtos_profissionais to authenticated;

-- ---------------------------------------------------------------------------
-- 2b) A ESCADA DA COMISSÃO, COM O DEGRAU DO PRODUTO NO PAR
--
-- ⚠ VAI INTEIRA. `create or replace function` não acrescenta linha: o corpo
-- que estiver aqui é o que vale. Esta é cópia fiel da versão do
-- 16_comissao.sql com o ramo do produto no degrau 1.
--
-- ⚠ E ESTA FUNÇÃO DECIDE DINHEIRO. O que ela devolve é congelado dentro da
-- comanda pelo gatilho — quer dizer que um erro aqui não aparece na tela: ele
-- aparece no acerto do mês, semanas depois, quando a profissional conferir o
-- que recebeu. Por isso o degrau novo é o PRIMEIRO e não muda mais nada:
-- produto sem linha no par cai exatamente onde caía antes.
--
-- A ordem dos quatro degraus continua a mesma, e ela é a regra do negócio:
--   1. o par     — "a Ana ganha 30% nesta pomada"
--   2. o catálogo— "esta pomada paga 15% para quem vender"
--   3. a pessoa  — "a Ana ganha 20% em tudo"
--   4. zero      — ninguém disse nada
-- ---------------------------------------------------------------------------
create or replace function public.comissao_de(
  p_tipo text, p_servico uuid, p_produto uuid, p_profissional uuid,
  out pct numeric, out fixa numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  -- 1) o par
  if p_tipo = 'servico' and p_servico is not null and p_profissional is not null then
    select sp.comissao_pct, sp.comissao_fixa into pct, fixa
      from public.servicos_profissionais sp
     where sp.servico_id = p_servico and sp.profissional_id = p_profissional
       and (sp.comissao_pct is not null or sp.comissao_fixa is not null);
    if found then
      return;
    end if;
  elsif p_tipo = 'produto' and p_produto is not null and p_profissional is not null then
    /* O degrau novo. A mesma exigência do ramo do serviço: a linha só vale se
       DISSER alguma coisa. Uma linha com os dois campos nulos existe para
       nada — e, se valesse, pararia a escada aqui e devolveria nulo, que é
       zero por outro caminho. A pessoa perderia a comissão do produto e
       ninguém saberia por quê. */
    select pp.comissao_pct, pp.comissao_fixa into pct, fixa
      from public.produtos_profissionais pp
     where pp.produto_id = p_produto and pp.profissional_id = p_profissional
       and (pp.comissao_pct is not null or pp.comissao_fixa is not null);
    if found then
      return;
    end if;
  end if;

  -- 2) o catálogo
  if p_tipo = 'servico' and p_servico is not null then
    select sv.comissao_pct, sv.comissao_fixa into pct, fixa
      from public.servicos sv
     where sv.id = p_servico
       and (sv.comissao_pct is not null or sv.comissao_fixa is not null);
    if found then
      return;
    end if;
  elsif p_tipo = 'produto' and p_produto is not null then
    -- Produto sempre diz alguma coisa: `comissao_pct` é not null aqui.
    select pd.comissao_pct, pd.comissao_fixa into pct, fixa
      from public.produtos pd
     where pd.id = p_produto;
    if found then
      return;
    end if;
  end if;

  -- 3) a pessoa
  if p_profissional is not null then
    select pr.comissao_pct, pr.comissao_fixa into pct, fixa
      from public.profissionais pr
     where pr.id = p_profissional;
    if found then
      return;
    end if;
  end if;

  -- 4) ninguém disse nada
  pct := 0; fixa := 0;
end $$;

comment on function public.comissao_de(text, uuid, uuid, uuid) is
  'A escada: par, catálogo, pessoa, zero. Vale para serviço e para produto. Não aceita taxa por parâmetro.';

revoke all on function public.comissao_de(text, uuid, uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) O HISTÓRICO DO ESTOQUE
--
-- `produtos.estoque` diz quanto TEM. Não diz como chegou ali, e é a segunda
-- pergunta que todo dono faz quando o número não bate com a prateleira:
-- "quem mexeu nisso?".
--
-- ── ⚠ UM LUGAR SÓ ESCREVE, E É O QUE EVITA CONTAR DUAS VEZES ──────────────
-- O estoque muda por dois caminhos: a comanda fechando (o 26_estoque) e o
-- dono digitando outro número no cadastro. A tentação é registrar nos dois
-- lugares — e aí a baixa da comanda vira DUAS linhas no histórico, porque o
-- 26 mexe na mesma coluna que o gatilho do cadastro observa.
--
-- Então quem escreve é um gatilho só, na própria `produtos`, que vê toda
-- mudança da coluna venha de onde vier. O MOTIVO é que viaja: o 26 avisa,
-- antes de baixar, que aquela mudança é uma venda. Quem não avisar é ajuste.
--
-- ⚠ O aviso é `set_config(..., true)` — LOCAL À TRANSAÇÃO. Sem o `true` ele
-- valeria para a conexão inteira, e a conexão é reaproveitada: o próximo
-- ajuste à mão de qualquer salão sairia rotulado como venda daquela comanda.
-- ---------------------------------------------------------------------------
create table if not exists public.estoque_mov (
  id         uuid primary key default gen_random_uuid(),
  produto_id uuid not null references public.produtos(id) on delete cascade,
  de         numeric(10,2) not null,
  para       numeric(10,2) not null,
  motivo     text not null default 'ajuste',
  comanda_id uuid references public.comandas(id) on delete set null,
  quem       uuid references public.perfis(id) on delete set null,
  criado_em  timestamptz not null default now()
);

create index if not exists ix_estoque_mov_produto
  on public.estoque_mov (produto_id, criado_em desc);

comment on table public.estoque_mov is
  'Toda mudança de produtos.estoque, com de/para e o motivo. Escrita só pelo gatilho tg_produto_estoque_mov.';

alter table public.estoque_mov enable row level security;

/* ⚠ SÓ LEITURA, E SÓ PARA QUEM TEM ACESSO AO SALÃO. Não existe policy de
   escrita de propósito: quem grava é o gatilho, que é `security definer` e
   não passa por RLS. Histórico que a tela pode escrever não é histórico — é
   um campo de texto com outro nome. */
drop policy if exists em_ler on public.estoque_mov;
create policy em_ler on public.estoque_mov for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and e_equipe(p.salao_id)) );

grant select on public.estoque_mov to authenticated;

create or replace function public.tg_produto_estoque_mov()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_motivo  text;
  v_comanda uuid;
begin
  -- Gravar o mesmo número por cima não é movimento. O painel salva o produto
  -- inteiro a cada edição, então isto acontece o tempo todo.
  if new.estoque is not distinct from old.estoque then
    return null;
  end if;

  v_motivo  := coalesce(nullif(current_setting('agendapro.mov_motivo', true), ''), 'ajuste');
  v_comanda := nullif(current_setting('agendapro.mov_comanda', true), '')::uuid;

  insert into public.estoque_mov (produto_id, de, para, motivo, comanda_id, quem)
  values (new.id, old.estoque, new.estoque, v_motivo, v_comanda, auth.uid());

  return null;
end $$;

drop trigger if exists tg_produto_estoque_mov on public.produtos;
create trigger tg_produto_estoque_mov
  after update of estoque on public.produtos
  for each row execute function public.tg_produto_estoque_mov();

revoke all on function public.tg_produto_estoque_mov() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3b) A BAIXA DA COMANDA, AGORA DIZENDO QUE É VENDA
--
-- ⚠ VAI INTEIRA, de novo: cópia fiel do 26_estoque.sql com duas linhas de
-- `set_config` em volta do update. O comportamento da baixa não muda em nada
-- — e não pode mudar, porque o `estoque.test.sql` cobra a simetria entre
-- fechar e reabrir.
-- ---------------------------------------------------------------------------
create or replace function public.tg_comanda_estoque()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_sinal int;
begin
  /* As duas condições são a trava, e cada metade carrega peso. O
     `old.status <> 'fechada'` é o que impede a baixa dobrada quando o painel
     grava "fechada" por cima de "fechada" — que acontece a cada salvamento.
     Simplificar para `if new.status = 'fechada'` faria o estoque descer
     sozinho, sem venda nenhuma. É a mutação que o `estoque.test.sql` reprova. */
  if old.status <> 'fechada' and new.status = 'fechada' then
    v_sinal := -1;                       -- vendeu: sai do estoque
  elsif old.status = 'fechada' and new.status <> 'fechada' then
    v_sinal := 1;                        -- reabriu ou cancelou: volta
  else
    return null;                         -- aberta -> cancelada: nunca baixou
  end if;

  /* O recado para o gatilho do histórico, que é quem escreve. Local à
     transação (`true`), senão a conexão levaria o rótulo para o próximo que
     a usasse. */
  perform set_config('agendapro.mov_motivo',
                     case when v_sinal < 0 then 'venda' else 'devolucao' end, true);
  perform set_config('agendapro.mov_comanda', new.id::text, true);

  update public.produtos p
     set estoque = p.estoque + v_sinal * i.total_qtd
    from (select ci.produto_id, sum(ci.qtd) as total_qtd
            from public.comanda_itens ci
           where ci.comanda_id = new.id
             and ci.tipo = 'produto'
             and ci.produto_id is not null
           group by ci.produto_id) i
   where p.id = i.produto_id;

  /* Apaga o recado. ⚠ E ELE JÁ MORRERIA SOZINHO: `set_config(..., true)` é
     local à transação, e cada chamada pelo PostgREST é uma transação própria.
     Estas duas linhas valem só para o caso de alguém, um dia, fechar uma
     comanda e mexer no estoque na MESMA transação — de dentro de outra função
     do banco, que é o único jeito de isso acontecer. Custam nada e escrevem a
     intenção; por isso a mutação que as remove sobrevive, e está anotada no
     `tests/mutacoes-produto-cadastro.sh` para ninguém "consertar" a suíte por
     causa dela. */
  perform set_config('agendapro.mov_motivo', '', true);
  perform set_config('agendapro.mov_comanda', '', true);

  return null;
end $$;

comment on function public.tg_comanda_estoque() is
  'Baixa o estoque ao fechar a comanda e devolve ao reabrir. Nunca recusa o fechamento. Marca o motivo para o histórico.';

-- ---------------------------------------------------------------------------
-- 3c) Ler o histórico de um produto
--
-- Gestão only, pelo mesmo motivo do relatório: o histórico mostra quanto o
-- salão comprou e vendeu de cada coisa.
-- ---------------------------------------------------------------------------
create or replace function public.estoque_historico(p_produto uuid, p_limite int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_salao uuid;
begin
  select salao_id into v_salao from public.produtos where id = p_produto;
  if v_salao is null then
    raise exception 'Produto não encontrado.' using errcode = 'no_data_found';
  end if;
  if not public.e_gestor(v_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'quando', m.criado_em,
             'de', m.de, 'para', m.para,
             'delta', m.para - m.de,
             'motivo', m.motivo,
             -- O nome de quem mexeu, e não o uuid: a tela não tem como
             -- traduzir perfil, e o histórico existe para ser lido.
             'quem', coalesce(pf.nome, '—'))
           order by m.criado_em desc)
      from (select * from public.estoque_mov
             where produto_id = p_produto
             order by criado_em desc
             limit greatest(1, least(coalesce(p_limite, 50), 200))) m
      left join public.perfis pf on pf.id = m.quem), '[]'::jsonb);
end $$;

revoke all on function public.estoque_historico(uuid, int) from public, anon;
grant execute on function public.estoque_historico(uuid, int) to authenticated;

comment on function public.estoque_historico(uuid, int) is
  'As últimas movimentações de estoque de um produto, mais recentes primeiro. Gestão only.';

-- ###########################################################################
-- ## 33_preco_regras.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 33. PREÇO AVANÇADO: vigência, dia da semana e faixa de horário
--
-- Três regras para o mesmo serviço, que respondem a mesma pergunta do salão:
-- sábado à tarde lota e terça de manhã fica vazia.
--
--   VIGÊNCIA        "a partir de 1º de março a escova passa a R$ 80"
--   DIA DA SEMANA   "escova R$ 50 de terça a quinta, R$ 70 sexta e sábado"
--   FAIXA DE HORÁRIO "corte R$ 60 antes das 14h, R$ 80 depois das 17h"
--
-- ── ⚠ O PREÇO PASSA A SER UMA PERGUNTA, E QUEM RESPONDE É O BANCO ──────────
--
-- Até aqui "preço" era um número numa coluna, e cada lado lia a coluna que
-- conhecia. O resultado, MEDIDO antes de escrever este arquivo:
--
--     Corte feminino, catálogo .................. R$  90
--     Corte feminino com a Ana (servicos_profissionais) ... R$ 130
--
--     o LINK cobrava ....... R$ 130   (coalesce(sp.preco, sv.preco) no 09)
--     a RECEPÇÃO cobrava ... R$  90   (preco: sv.preco no app.html)
--
-- Quarenta reais de diferença no mesmo atendimento, decidido por quem clicou.
-- Não era a funcionalidade nova que faltava — era não existir UM lugar que
-- respondesse "quanto custa isto".
--
-- Agora existe: `preco_do_servico()`. E um gatilho em `agendamento_servicos`
-- aplica a resposta em TODA marcação, venha do link ou do painel. A tela pode
-- errar; a linha gravada, não.
--
-- ── A ESCADA, DE CIMA PARA BAIXO ───────────────────────────────────────────
--
--   1. a REGRA que casa com o dia e a hora da marcação, a mais específica
--   2. o preço do par serviço+profissional (`servicos_profissionais.preco`)
--   3. o preço do serviço (`servicos.preco`)
--
-- É a mesma forma da `comissao_de()` no 16, e de propósito: quem já entendeu
-- uma entende a outra.
--
-- ── ⚠ E O PREÇO CONTINUA CONGELANDO NA MARCAÇÃO ────────────────────────────
--
-- `agendamento_servicos.preco` é copiado no momento da marcação desde o
-- primeiro dia — "se o preço da tabela mudar amanhã, o que foi combinado com
-- o cliente continua valendo". Nada disso muda. O que muda é QUAL número é
-- copiado: antes era a coluna, agora é a resposta da escada para aquele dia e
-- aquela hora.
--
-- É o que impede o pior defeito possível numa tela de agenda: a cliente ver
-- R$ 50 na terça, o dono mudar a regra na quarta, e ela pagar R$ 70 no balcão.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) A TABELA DAS REGRAS
--
-- Uma linha por regra. Todos os recortes são OPCIONAIS e se combinam: uma
-- regra sem nada preenchido vale sempre, para todo mundo — que é como se
-- escreve "o preço novo entra hoje e pronto".
--
-- ⚠ `salao_id` existe mesmo dando para chegar nele pelo serviço. É o que o
-- RLS pergunta, e uma policy que precisa de JOIN para saber de quem é a linha
-- é uma policy que alguém vai escrever errado um dia.
-- ---------------------------------------------------------------------------
/* ⚠ A TABELA É DECLARADA NO 25_loja.sql, e não aqui, e isto é uma cópia
   inofensiva (`if not exists`) para quem rodar só este arquivo.

   O motivo é a ordem de compilação: a `vitrine()` do 25 lê `precos_regras`,
   corpo de função SQL compila na hora, e o 25 roda oito arquivos antes deste.
   Sem a tabela já de pé lá, a vitrine nem é criada e o install inteiro para.
   É a mesma razão de `servicos.dias` e `produtos.preco_visivel` morarem no 25.

   O dono da funcionalidade continua sendo este arquivo: RLS, policies, grants,
   a escada de preço e o gatilho estão todos aqui. */
create table if not exists public.precos_regras (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  servico_id      uuid not null references public.servicos(id) on delete cascade,
  -- Nulo = vale para quem atender. Preenchido = só com esta pessoa.
  profissional_id uuid references public.profissionais(id) on delete cascade,
  preco           numeric(10,2) not null check (preco >= 0),
  -- Vigência. Nulo dos dois lados = desde sempre, para sempre.
  de              date,
  ate             date,
  /* Dias da semana, no padrão do Postgres e do JavaScript: 0 = domingo.
     Nulo ou vazio = todo dia. Mesma convenção do `servicos.dias` no 31 e do
     `pacotes.so_nos_dias` no 27 — três lugares, uma contagem só. */
  dias            smallint[],
  -- Faixa de horário em MINUTOS desde a meia-noite, como o resto da agenda.
  -- 14h = 840. Nulo dos dois lados = o dia inteiro.
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

-- ---------------------------------------------------------------------------
-- 2) QUEM ENXERGA
--
-- Ler é da equipe: quem atende precisa saber quanto custa o que ele faz.
-- Escrever é de gestor: preço é política comercial.
--
-- ⚠ Duas policies separadas por VERBO, e não uma `for all`. Uma policy só
-- daria a quem lê o direito de escrever no dia em que alguém trocasse o
-- `using` sem lembrar do `with check`.
-- ---------------------------------------------------------------------------
alter table public.precos_regras enable row level security;

drop policy if exists pr_ler on public.precos_regras;
create policy pr_ler on public.precos_regras for select to authenticated
  using (public.e_equipe(salao_id));

drop policy if exists pr_gerir on public.precos_regras;
create policy pr_gerir on public.precos_regras for all to authenticated
  using (public.e_gestor(salao_id))
  with check (public.e_gestor(salao_id));

/* ⚠ E O GRANT DE TABELA, que é outra coisa da policy.
   A policy diz QUAIS LINHAS a pessoa alcança; o grant diz se ela alcança a
   tabela. Sem ele o PostgREST responde "permission denied for table" antes de
   a policy ser consultada — e a mensagem não fala em linha nenhuma, o que
   manda quem for depurar procurar erro no lugar errado.

   ⚠ NADA PARA O `anon`. Quem não tem login recebe os preços prontos dentro da
   `vitrine()`, que é `security definer` e escolhe o que sai. A tabela crua
   traria o preço por profissional de qualquer salão a quem adivinhasse um id. */
grant select, insert, update, delete on public.precos_regras to authenticated;

-- ---------------------------------------------------------------------------
-- 3) A REGRA MAIS ESPECÍFICA
--
-- Várias regras podem casar com o mesmo horário. "Escova R$ 50 nas terças" e
-- "escova R$ 45 em março" se cruzam numa terça de março, e alguém tem que
-- ganhar — de um jeito que dê para explicar ao dono em uma frase.
--
-- A frase é: QUANTO MAIS RECORTES A REGRA TEM, MAIS ELA MANDA.
--
--   profissional  vale 8     "só com a Carla" é o recorte mais estreito
--   dias          vale 4
--   horário       vale 2
--   vigência      vale 1     o mais largo: um período costuma pegar semanas
--
-- Somando, a regra com mais recortes ganha. Empatou, vale a mais recente —
-- porque quem cadastrou depois estava corrigindo o que cadastrou antes.
--
-- ⚠ NÃO É O MENOR PREÇO QUE GANHA, e isso é decisão. "O mais barato ganha"
-- parece generoso e tira do dono o poder de cobrar MAIS num horário disputado
-- — que é metade do motivo de ele querer isto.
-- ---------------------------------------------------------------------------
create or replace function public.preco_regra_que_vale(
  p_servico uuid, p_profissional uuid, p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  with onde as (
    select sa.fuso
      from public.servicos sv
      join public.saloes sa on sa.id = sv.salao_id
     where sv.id = p_servico
  ),
  /* O dia e a hora NO FUSO DO SALÃO, que não é o fuso de quem está olhando.
     Uma cliente em Portugal marcando às 3h da manhã dela num salão de Porto
     Alegre tem que pegar o preço do dia que é lá. Mesma conta do
     `hoje_no_salao()` no 05. */
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

-- ---------------------------------------------------------------------------
-- 4) A ESCADA INTEIRA — A ÚNICA RESPOSTA PARA "QUANTO CUSTA"
--
-- Regra → par serviço+profissional → serviço. Quem chamar isto está certo;
-- quem ler uma coluna sozinha está adivinhando.
-- ---------------------------------------------------------------------------
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

-- A soma, para o `valor_previsto`. Mesma escada, uma linha por serviço.
create or replace function public.preco_dos_servicos(
  p_profissional uuid, p_servicos uuid[], p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(public.preco_do_servico(s, p_profissional, p_quando)), 0)
           ::numeric(10,2)
    from unnest(p_servicos) as s
$$;

comment on function public.preco_dos_servicos(uuid, uuid[], timestamptz) is
  'A soma da escada de preço para os serviços pedidos, neste horário.';

/* ── ⚠ E A VERSÃO SEM DATA, QUE FICOU PARA TRÁS ──────────────────────────
   `preco_dos_servicos(profissional, servicos)` nasceu no 05, quando preço era
   uma coluna só. Ela continua existindo — o `agendar()` antigo do 05 a chama,
   e o 09 substitui esse `agendar()`, então na prática ela ficou sem uso.

   "Sem uso" é o pior estado possível para uma função de dinheiro: ela não
   incomoda ninguém e responde a pergunta errada com cara de estar certa. A
   próxima pessoa que precisar de uma soma de preços vai achá-la pelo nome,
   chamar, e não receber regra nenhuma.

   Aqui ela passa a delegar, assumindo AGORA como horário. Quem não informou o
   horário quer saber quanto custa agora — e agora é uma resposta certa, não um
   palpite.

   ⚠ E É AQUI, no 33, e não lá no 05. Função SQL compila o corpo na hora de
   criar, e o 05 roda antes do 33: chamar `preco_do_servico()` de lá quebraria
   a instalação do zero. Redefinir no módulo de número maior é o padrão que o
   `sintaxe.test.js` conhece e cobra. */
create or replace function public.preco_dos_servicos(
  p_profissional uuid, p_servicos uuid[])
returns numeric language sql stable set search_path = public as $$
  select public.preco_dos_servicos(p_profissional, p_servicos, now())
$$;

comment on function public.preco_dos_servicos(uuid, uuid[]) is
  'A soma da escada de preço para AGORA. Prefira a versão com o horário: com regra de preço, o mesmo serviço custa diferente na terça de manhã e no sábado.';

-- ---------------------------------------------------------------------------
-- 5) ⚠ O GATILHO — É ELE QUE FAZ A REGRA VALER PARA TODO MUNDO
--
-- Sem esta parte, o arquivo inteiro seria uma funcionalidade que só o link
-- usa: o painel grava `agendamento_servicos` direto na tabela, e ele escrevia
-- `sv.preco` cru — foi assim que nasceram os R$ 40 de diferença lá em cima.
--
-- Aqui o banco reescreve o preço da linha com a resposta da escada, sempre, em
-- toda marcação. A tela pode errar; a linha gravada não.
--
-- ⚠ E SÓ NO INSERT. Um `update` na linha é conserto feito à mão pela recepção
-- — "combinei R$ 100 com ela" — e recalcular por cima disso desfaria a
-- combinação na frente da cliente. O congelamento continua sendo o que era:
-- vale o que foi decidido na hora de marcar.
-- ---------------------------------------------------------------------------
/* ⚠ E ELE PREENCHE O QUE VEIO EM BRANCO — NÃO REESCREVE O QUE VEIO DECIDIDO.

   A primeira versão reescrevia sempre, e a bateria mostrou o preço disso: o
   `sem-comanda.test.mjs` tem um caso chamado "atendimento que não custou
   nada", e ele passou a custar. A recepção lança uma CORTESIA por R$ 0,00 — ou
   uma manutenção coberta — e o gatilho devolvia o preço de tabela por cima.
   Não é caso raro, e o arquivo de teste já dizia isso por escrito.

   Reescrever sempre resolveria o defeito antigo (a recepção cobrando o preço
   do catálogo) ao custo de tirar dela o direito de combinar um valor. Os dois
   são dinheiro, e o segundo é pior: é o sistema desfazendo, em silêncio, o que
   a pessoa acabou de decidir na frente da cliente.

   Então o contrato é: QUEM NÃO DISSE, O BANCO DIZ. O `agendar()` do link manda
   nulo de propósito e recebe a escada; a recepção manda o número que ela quer,
   inclusive zero. O que impede a recepção de mandar o número ERRADO não é mais
   este gatilho — é o `precoDaEscada()` do painel, que responde a mesma escada
   e é comparado com o Postgres, caso a caso, no `preco.test.mjs`. */
/* ⚠ "QUEM NÃO DISSE, O BANCO DIZ" — MAS SÓ O BALCÃO PODE DIZER.

   O contrato acima dava o direito de combinar o valor a qualquer um da
   equipe, e a policy de escrita da tabela é da equipe inteira. A
   profissional, logada, mudava o preço do PRÓPRIO atendimento direto pela
   API — de R$ 80 para R$ 500 — e, no salão sem comanda, a comanda automática
   nascia com R$ 500 e a comissão dela subia junto. Achado pelo caça-bug.

   Agora: o balcão (dono, admin, recepção — `ve_agenda_toda`) continua
   mandando o número que quiser, cortesia inclusive. Quem mais estiver logado
   recebe a escada no insert, e numa alteração o preço fica como estava.
   Sem ninguém logado (o `agendar()` do link, rotinas do servidor) nada muda:
   o link já manda nulo. */
create or replace function public.tg_preco_do_agendamento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_prof   uuid;
  v_inicio timestamptz;
  v_salao  uuid;
begin
  if auth.uid() is not null
     and (tg_op = 'INSERT' and new.preco is not null
          or tg_op = 'UPDATE' and new.preco is distinct from old.preco) then
    select a.salao_id into v_salao from public.agendamentos a where a.id = new.agendamento_id;
    if not public.ve_agenda_toda(v_salao) then
      if tg_op = 'UPDATE' then new.preco := old.preco; return new; end if;
      new.preco := null;
    end if;
  end if;
  if tg_op = 'UPDATE' then return new; end if;

  if new.preco is not null then return new; end if;

  select a.profissional_id, a.inicio into v_prof, v_inicio
    from public.agendamentos a where a.id = new.agendamento_id;

  -- Agendamento que não existe não acontece: a chave estrangeira barra antes.
  -- Esta saída é para a ordem de execução dentro de uma transação.
  if v_prof is null or v_inicio is null then new.preco := 0; return new; end if;

  new.preco := public.preco_do_servico(new.servico_id, v_prof, v_inicio);
  return new;
end $$;

/* ⚠ E O `default 0` PRECISA SAIR, senão o gatilho acima nunca vê um nulo.

   Com ele, omitir a coluna dá ZERO — e zero é indistinguível de "a recepção
   lançou uma cortesia". O contrato "quem não disse, o banco diz" só existe se
   houver como NÃO DIZER, e em SQL isso é o nulo.

   O `not null` fica: ele é conferido DEPOIS dos gatilhos `before`, então a
   linha nunca chega ao disco sem preço. O que muda é só quem preenche. */
alter table public.agendamento_servicos alter column preco drop default;

drop trigger if exists tg_preco_agend_servico on public.agendamento_servicos;
create trigger tg_preco_agend_servico
  before insert or update of preco on public.agendamento_servicos
  for each row execute function public.tg_preco_do_agendamento();

comment on function public.tg_preco_do_agendamento() is
  'Reescreve o preço da linha do agendamento com a escada do banco. É o que faz a regra valer também para o que a recepção marca.';

-- ---------------------------------------------------------------------------
-- 6) "A PARTIR DE R$ X", PARA A CAPA
--
-- Na capa a cliente ainda não escolheu dia nem hora, então não existe UM
-- preço — existe uma faixa. Mostrar o preço cheio de quem tem promoção de
-- terça é esconder a promoção; mostrar o mais barato como se fosse o preço é
-- prometer o que ela talvez não consiga.
--
-- Então a vitrine leva os dois números: o de sempre, e o menor que pode
-- acontecer dentro da janela que a agenda tem aberta. A tela escreve "a partir
-- de" só quando os dois diferem.
--
-- ⚠ A JANELA É A DA AGENDA, e não "todas as regras". Uma promoção que já
-- venceu, ou que só começa em agosto, não pode puxar o "a partir de" de hoje
-- para baixo — a cliente não consegue marcar lá.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 7) QUEM PODE CHAMAR
--
-- ⚠ NENHUMA VAI PARA O `anon`, e não é esquecimento.
--
-- O link não chama nada disto: ele recebe os preços prontos dentro da
-- `vitrine()`, que é `security definer` e já peneira o que pode sair. Abrir
-- `preco_do_servico()` ao anônimo seria entregar uma calculadora da tabela de
-- preços de QUALQUER salão a quem adivinhasse um id — inclusive dos preços por
-- profissional, que é acerto interno da casa.
--
-- O gatilho roda como dono e não precisa de grant nenhum.
-- ---------------------------------------------------------------------------
revoke all on function public.preco_regra_que_vale(uuid, uuid, timestamptz) from public;
revoke all on function public.preco_do_servico(uuid, uuid, timestamptz)     from public;
revoke all on function public.preco_dos_servicos(uuid, uuid[], timestamptz) from public;
revoke all on function public.preco_minimo_do_servico(uuid, date)           from public;

/* ⚠ E A AJUDANTE VAI JUNTO, senão as duas de cima são promessa vazia.

   `preco_do_servico()` chama `preco_regra_que_vale()`, e NENHUMA das duas é
   `security definer` — de propósito: assim o RLS continua valendo, e quem
   pergunta só recebe resposta sobre o salão em que tem vínculo. Mas função
   sem `definer` roda como quem chamou, e quem chamou precisa alcançar as duas.

   Eu tinha dado grant só nas duas de fora. O painel recebia
   `permission denied for function preco_regra_que_vale` — e só apareceu
   quando o teste chamou a função direto, porque de dentro do `agendar()` e do
   gatilho, que são `definer`, ela sempre funcionou. Grant pela metade é a
   funcionalidade que existe para quem tem privilégio e some para o resto. */
grant execute on function public.preco_regra_que_vale(uuid, uuid, timestamptz)
  to authenticated;
grant execute on function public.preco_do_servico(uuid, uuid, timestamptz)
  to authenticated;
grant execute on function public.preco_dos_servicos(uuid, uuid[], timestamptz)
  to authenticated;

-- ###########################################################################
-- ## 34_cupons.sql
-- ###########################################################################

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
-- Criar cupom é do Básico para cima (22_cotas, exigir_recurso).
create or replace function public.tg_cupom_do_plano() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.exigir_recurso(new.salao_id, 'cupons', 'Cupom');
  return new;
end $$;
drop trigger if exists tg_cupom_do_plano on public.cupons;
create trigger tg_cupom_do_plano before insert on public.cupons
  for each row execute function public.tg_cupom_do_plano();

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
  -- Cupom é do Básico para cima (22_cotas): no Grátis, nem os antigos valem.
  if not coalesce(public.recurso_bool(p_salao, 'cupons'), false) then
    return jsonb_build_object('motivo', 'Este estabelecimento não está aceitando cupons agora.');
  end if;
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
     -- No Grátis o campo de cupom nem aparece no link (22_cotas).
     and coalesce(public.recurso_bool(p_salao, 'cupons'), false)
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
        -- O sinal (09, 1e) é sobre o que ela paga: com o desconto, refeito.
        update public.agendamentos
           set cupom_id = c.id, desconto = v_desc, valor_previsto = valor_previsto - v_desc,
               sinal_exigido = case when coalesce(sinal_exigido, 0) > 0
                                    then public.sinal_do_salao(salao_id, valor_previsto - v_desc,
                                           (select array_agg(x.servico_id order by x.ordem)
                                              from public.agendamento_servicos x
                                             where x.agendamento_id = n.id),
                                           profissional_id, inicio)
                                    else sinal_exigido end
         where id = n.id;
        update public.cupom_usos
           set agendamento_id = n.id, desconto = v_desc
         where agendamento_id = a.id;
      end if;
    end if;
  end if;

  /* ⚠ O SINAL PAGO VAI JUNTO (09, 1e). Ela pagou o sinal do horário de
     terça e trocou para quinta: o horário novo nasceu pedindo sinal de novo,
     e ela pagaria duas vezes. O que já foi pago passa para o novo — e, se
     cobre o que ele pede, o novo é confirmado como o antigo seria (no salão
     que confirma sozinho, para a cliente que não precisa de confirmação). */
  if coalesce(a.sinal_pago, 0) > 0 and n.status in ('pendente', 'confirmado') then
    update public.agendamentos set sinal_pago = a.sinal_pago where id = n.id;
    update public.agendamentos x set status = 'confirmado'
     where x.id = n.id and x.status = 'pendente'
       and coalesce(x.sinal_exigido, 0) > 0 and x.sinal_pago >= x.sinal_exigido
       and public.confirma_automatico(x.salao_id)
       and not public.cliente_exige_confirmacao(x.salao_id, x.cliente_id, null);
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

-- ###########################################################################
-- ## 35_acesso.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 35: QUEM LÊ O QUÊ (os consertos de acesso do caça-bug)
--
-- As mesmas regras já escritas no 02_rls.sql, repetidas aqui para QUEM
-- ATUALIZA: o 98_modulos.sql não leva o 02, e sem este arquivo um banco
-- atualizado continuaria com as portas abertas que a instalação nova já não
-- tem. `drop ... if exists` e `create` de novo: colar duas vezes dá no mesmo.
--
-- 1) O CATÁLOGO É DA EQUIPE. Era `tem_acesso()`, que inclui o papel
--    "cliente" — e virar cliente de um salão é livre (`vinc_virar_cliente`).
--    Qualquer conta criava o vínculo com o id que a vitrine mostra e lia o
--    telefone pessoal e a comissão de cada profissional, a comissão de cada
--    serviço, os serviços desligados e a jornada. A cliente escolhe pela
--    `vitrine()` e pelas vistas públicas, que mostram só o que a página mostra.
--
-- 2) A CLIENTE NÃO ESCREVE NA PRÓPRIA FICHA. A ficha nasce e se completa
--    pelo `agendar()` (security definer). Com o UPDATE aberto ela tirava a
--    marca "precisa de confirmação" e reescrevia a anotação do salão; com o
--    INSERT aberto, uma conta criava antes uma ficha com o telefone de outra
--    pessoa e passava a receber as marcações dela.
-- ===========================================================================

drop policy if exists prof_ler on public.profissionais;
create policy prof_ler on public.profissionais for select to authenticated
  using ( public.e_equipe(salao_id) );

drop policy if exists serv_ler on public.servicos;
create policy serv_ler on public.servicos for select to authenticated
  using ( public.e_equipe(salao_id) );

drop policy if exists sp_ler on public.servicos_profissionais;
create policy sp_ler on public.servicos_profissionais for select to authenticated
  using ( exists (select 1 from public.servicos s
                   where s.id = servico_id and public.e_equipe(s.salao_id)) );

drop policy if exists jor_ler on public.jornadas;
create policy jor_ler on public.jornadas for select to authenticated
  using ( exists (select 1 from public.profissionais p
                   where p.id = profissional_id and public.e_equipe(p.salao_id)) );

drop policy if exists pp_ler on public.produtos_profissionais;
create policy pp_ler on public.produtos_profissionais for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and public.e_equipe(p.salao_id)) );

drop policy if exists em_ler on public.estoque_mov;
create policy em_ler on public.estoque_mov for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and public.e_equipe(p.salao_id)) );

drop policy if exists cli_eu_criar  on public.clientes;
drop policy if exists cli_eu_editar on public.clientes;

-- ###########################################################################
-- ## 36_excluir_conta.sql
-- ###########################################################################

-- ===========================================================================
-- 36_excluir_conta.sql — o botão "Excluir conta"
--
-- O pedido: "colocar um botão excluir conta é necessário também" — e, na
-- escolha entre guardar por um tempo ou apagar, "apaga tudo na hora".
--
-- ── O QUE ACONTECE, POR PAPEL ─────────────────────────────────────────────
--   · DONA, e a ÚNICA dona ativa do salão: o salão inteiro vai junto — agenda,
--     clientes, serviços, equipe, caixa, campanhas, cobranças. Não fica nada
--     para "desfazer", e a tela diz isso antes, com o nome de cada salão.
--   · Dona de um salão que tem OUTRA dona ativa: o salão fica com a outra; sai
--     só o vínculo de quem excluiu.
--   · Equipe (profissional, recepção, gerente): sai o login. O salão é de
--     outra pessoa e continua inteiro; o que ela fez lá (quem marcou, quem
--     abriu o caixa) fica sem o nome — as colunas `*_por` são `set null`.
--   · Cliente que entrou pelo link: sai o login. A ficha dela é do SALÃO
--     (nome e telefone que o salão cadastrou), e `clientes.perfil_id` é
--     `set null`: a ficha fica, desligada da conta.
--
-- ── ⚠ UM `DELETE FROM SALOES` SOZINHO NÃO BASTA — MEDIDO ──────────────────
-- Tudo do salão pendura em `saloes` com `on delete cascade`, mas quatro
-- chaves no caminho são `restrict`. Três delas ligam vizinhos do MESMO nível
-- (agendamentos → clientes e profissionais, comandas → clientes), e essas a
-- cascata resolve sozinha. A quarta não:
--
--     agendamento_servicos.servico_id → servicos   (restrict)
--
-- O item do atendimento mora DOIS níveis abaixo do salão (salão →
-- agendamento → item), e o serviço, um só. A cascata apaga o serviço antes de
-- descer até o item, e o Postgres recusa: «update or delete on table
-- "servicos" violates foreign key constraint
-- "agendamento_servicos_servico_id_fkey"». Foi exatamente o que o
-- `excluir-conta.test.mjs` mostrou quando esta linha saiu. Então os itens
-- saem primeiro, à mão, e o resto vai na cascata — inclusive a comanda
-- FECHADA, cujo gatilho de "não mexa" não acha mais a comanda quando os
-- itens dela saem.
--
-- ── ⚠ O CARTÃO TEM DE ESTAR DESLIGADO ANTES ──────────────────────────────
-- A renovação automática mora no Mercado Pago. Apagar o salão aqui com a
-- assinatura ligada lá deixaria o cartão sendo cobrado todo mês por um salão
-- que não existe mais — e sem tela nenhuma para desligar. O painel desliga
-- primeiro (pela borda `cancelar-cartao`, que só limpa o nosso lado depois de
-- o Mercado Pago confirmar); este arquivo RECUSA se ainda estiver ligado.
-- Não confiar só na tela é a regra da casa.
--
-- ── AS FOTOS ─────────────────────────────────────────────────────────────
-- Moram no Storage, e o Supabase não deixa apagar arquivo do Storage por SQL
-- (só pela API dele). Quem apaga a pasta do salão é o painel, ANTES de chamar
-- esta função — enquanto ainda é gestor, que é o que a policy `img_apagar`
-- exige. Depois daqui ele já não teria permissão.
-- ===========================================================================

/* O que a exclusão vai fazer, para a tela mostrar ANTES de pedir o EXCLUIR:
   os estabelecimentos em que a pessoa TRABALHA, um por linha, dizendo se o
   salão vai junto (`apaga`) e se tem cartão ligado. A regra de "sou a única
   dona" mora aqui, e não na tela, para que o aviso e a exclusão nunca
   discordem.

   ⚠ O VÍNCULO DE CLIENTE NÃO ENTRA. Quem entra pelo link ganha um vínculo
   `cliente` com o salão (01_schema), e ele não é "administrar" nada: contado
   aqui, a cliente que quisesse excluir a conta pelo link seria mandada ao
   painel de um salão que não é dela. Ele sai junto na exclusão, como todos.

   Agrupado por salão: a mesma pessoa pode ser dona E profissional no mesmo
   lugar (a chave do vínculo inclui o papel), e o salão apareceria duas vezes. */
create or replace function public.o_que_excluir_apaga()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'salao_id', x.salao_id, 'nome', x.nome, 'papel', x.papel,
           'apaga', x.apaga, 'cartao', x.cartao) order by x.nome), '[]'::jsonb)
    from (select v.salao_id, s.nome,
                 case when bool_or(v.papel = 'dono') then 'dono' else min(v.papel) end as papel,
                 bool_or(v.papel = 'dono') and not exists (
                   select 1 from public.vinculos o
                    where o.salao_id = v.salao_id and o.papel = 'dono'
                      and o.status = 'ativo' and o.perfil_id <> auth.uid()) as apaga,
                 coalesce((select a.mp_preapproval is not null
                             from public.assinaturas a
                            where a.salao_id = v.salao_id), false) as cartao
            from public.vinculos v
            join public.saloes s on s.id = v.salao_id
           where v.perfil_id = auth.uid() and v.status = 'ativo' and v.papel <> 'cliente'
           group by v.salao_id, s.nome) x
$$;
revoke all on function public.o_que_excluir_apaga() from public, anon;
grant execute on function public.o_que_excluir_apaga() to authenticated;

/* Um salão inteiro: os itens dos atendimentos primeiro, e a cascata leva o
   resto (ver o topo). Interna — ninguém de fora chama isto, só a
   `excluir_minha_conta()`, que já conferiu quem é e o que pode. */
create or replace function public.apagar_salao_inteiro(p_salao uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.agendamento_servicos s
   using public.agendamentos a
   where s.agendamento_id = a.id and a.salao_id = p_salao;
  delete from public.saloes where id = p_salao;
end $$;
revoke all on function public.apagar_salao_inteiro(uuid) from public, anon, authenticated;

create or replace function public.excluir_minha_conta(p_confirmacao text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_eu     uuid := auth.uid();
  v_salao  uuid;
  v_feitos int := 0;
begin
  if v_eu is null then
    raise exception 'Entre na sua conta para excluí-la.'
      using errcode = 'insufficient_privilege';
  end if;
  /* A palavra é conferida AQUI, e não só na tela: um clique torto, ou uma
     chamada direta à API, não apaga um salão inteiro. */
  if upper(btrim(coalesce(p_confirmacao, ''))) <> 'EXCLUIR' then
    raise exception 'Para excluir a conta, digite EXCLUIR.'
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from jsonb_array_elements(public.o_que_excluir_apaga()) x
              where (x->>'apaga')::boolean and (x->>'cartao')::boolean) then
    raise exception 'A renovação automática no cartão ainda está ligada. Desligue em Meu plano antes de excluir a conta — senão o cartão continuaria sendo cobrado.'
      using errcode = 'check_violation';
  end if;

  for v_salao in
    select (x->>'salao_id')::uuid
      from jsonb_array_elements(public.o_que_excluir_apaga()) x
     where (x->>'apaga')::boolean
  loop
    perform public.apagar_salao_inteiro(v_salao);
    v_feitos := v_feitos + 1;
  end loop;

  delete from public.vinculos where perfil_id = v_eu;
  /* O login. `perfis` vai junto (cascade), e tudo o que apontava para o
     perfil em salões de OUTRAS pessoas fica sem o nome (set null). */
  delete from auth.users where id = v_eu;

  return jsonb_build_object('ok', true, 'saloes_apagados', v_feitos);
end $$;
revoke all on function public.excluir_minha_conta(text) from public, anon;
grant execute on function public.excluir_minha_conta(text) to authenticated;

-- ###########################################################################
-- ## 37_pedidos.sql
-- ###########################################################################

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
                  'pedido_pronto','pedido_cancelado',
                  -- O pacote (45_pacote_mensagens.sql): o aviso de que está
                  -- acabando e o lembrete do pagamento a receber.
                  'pacote_renovar','pacote_pagamento','pacote_agenda'));

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
    -- Os do pacote (45). Só saem com o interruptor da plataforma ligado.
    -- A última sessão (tipo `pacote_renovar`, o nome antigo do aviso): o
    -- `agendapro_pacote_renovacao` a Meta aprovou como Marketing, e categoria
    -- não se troca. O de pagamento não sai mais (45), mas o nome fica aqui.
    when 'pacote_renovar'    then 'agendapro_pacote_ultima_sessao'
    when 'pacote_pagamento'  then 'agendapro_pacote_pagamento'
    when 'pacote_agenda'     then 'agendapro_pacote_agenda'
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
                    'pedido_a_caminho', 'pedido_pronto', 'pedido_cancelado',
                    'pacote_renovar', 'pacote_pagamento', 'pacote_agenda')
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

-- ###########################################################################
-- ## 38_suporte.sql
-- ###########################################################################

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

/* O contato de quem é DONO do salão — o WhatsApp do salão (que o admin já
   vê) muitas vezes é o da recepção. Para o "Falar com o dono" do admin. */
create or replace function public.contato_do_dono(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê o contato do dono.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('nome', p.nome, 'telefone', p.telefone,
                                        'email', coalesce(p.email, u.email)) order by p.nome)
      from public.vinculos v
      join public.perfis p on p.id = v.perfil_id
      left join auth.users u on u.id = p.id
     where v.salao_id = p_salao and v.papel = 'dono' and v.status = 'ativo'), '[]'::jsonb);
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
revoke all on function public.contato_do_dono(uuid) from public, anon;
revoke all on function public.salao_da_linha(text, jsonb) from public, anon, authenticated;
revoke all on function public.tg_suporte() from public, anon, authenticated;
revoke all on function public.definir_status_salao(uuid, text) from public;
grant execute on function public.iniciar_suporte(uuid) to authenticated;
grant execute on function public.liberar_edicao_suporte(uuid) to authenticated;
grant execute on function public.encerrar_suporte(uuid) to authenticated;
grant execute on function public.acessos_de_suporte(int) to authenticated;
grant execute on function public.estender_teste(uuid, date) to authenticated;
grant execute on function public.contato_do_dono(uuid) to authenticated;
grant execute on function public.definir_status_salao(uuid, text) to authenticated;

-- ###########################################################################
-- ## 39_teste_unico.sql
-- ###########################################################################

-- ===========================================================================
-- 39_teste_unico.sql — o teste grátis é UM por pessoa, não um por cadastro
--
-- A pergunta: "o dono do salão pode excluir a conta, cadastrar de novo e usar
-- 7 dias grátis, e fazer isso direto. O que fazer?"
--
-- ── AS DUAS PORTAS QUE ESTAVAM ABERTAS ────────────────────────────────────
--   1. Excluir e voltar. O "Excluir conta" (36) apaga o login, e com ele o
--      telefone e o e-mail ficam livres. O cadastro novo, com os MESMOS
--      dados, nascia com mais 7 dias.
--   2. Nem precisava excluir: cada salão criado pelo `criar_salao()` (03)
--      ganhava um teste — a mesma conta abria "Salão 2", "Salão 3"… e
--      trocava de casa toda semana.
--
-- ── O QUE MUDA ────────────────────────────────────────────────────────────
-- Quem ganha um teste deixa uma MARCA: o WhatsApp e o e-mail, normalizados e
-- passados por sha256. A marca não pendura em conta nenhuma, então o
-- "Excluir conta" não a leva. No cadastro seguinte com o mesmo WhatsApp ou o
-- mesmo e-mail (inclusive "ana.souza+2@gmail.com" no lugar de
-- "anasouza@gmail.com", e celular com ou sem o nono dígito), o salão nasce
-- no plano Grátis — que é onde o teste vencido cairia de qualquer jeito. A
-- conta é criada normalmente: barrar o cadastro seria perder quem talvez
-- assine; o que não se repete é o presente.
--
-- Exceção é com a plataforma: o "Estender teste" do admin (38) continua
-- dando dias a quem você quiser.
--
-- ── POR QUE HASH, E NÃO O TELEFONE ────────────────────────────────────────
-- Para saber "já usou?" basta comparar, não é preciso guardar o número. O
-- hash é o mínimo necessário (LGPD, art. 6º, III). Mas não é anonimato:
-- telefone tem poucas combinações e o hash pode ser recalculado — por isso
-- a tabela fica fechada a todo mundo, inclusive à própria plataforma pelo
-- navegador, e a Política de privacidade precisa dizer que guardamos esse
-- registro para evitar uso repetido do teste.
--
-- ── O QUE ISTO NÃO PEGA ───────────────────────────────────────────────────
-- Quem volta com OUTRO WhatsApp e OUTRO e-mail. O telefone do dono não é
-- confirmado por código no cadastro; confirmá-lo (ou pedir cartão para
-- começar o teste) é o próximo degrau, se o abuso continuar.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O REGISTRO
-- ---------------------------------------------------------------------------
create table if not exists public.testes_usados (
  marca       text primary key,              -- sha256 de 'tel:…' ou 'email:…'
  tipo        text not null check (tipo in ('telefone', 'email')),
  primeiro_em timestamptz not null default now(),
  ultimo_em   timestamptz not null default now()
);
alter table public.testes_usados enable row level security;
alter table public.testes_usados force row level security;
-- Nenhuma policy, nenhum grant: só as funções abaixo (security definer) leem
-- e escrevem.
revoke all on public.testes_usados from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) A MESMA PESSOA ESCRITA DE OUTRO JEITO
-- ---------------------------------------------------------------------------
/* Só os dígitos, com o 55 quando veio sem país (como o `para_e164()` do 08).
   Celular do Brasil escrito sem o nono dígito (55 + DDD + 8 dígitos
   começando por 6 a 9) ganha o 9: é o mesmo chip. */
create or replace function public.tel_para_teste(p text)
returns text language plpgsql immutable set search_path = public as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if length(d) in (10, 11) then d := '55' || d; end if;
  if length(d) < 8 then return null; end if;
  if length(d) = 12 and left(d, 2) = '55' and substr(d, 5, 1) ~ '[6-9]' then
    d := left(d, 4) || '9' || substr(d, 5);
  end if;
  return d;
end $$;

/* Minúsculas, sem o "+qualquercoisa" antes do @ (vale no Gmail, no Outlook e
   em quase todos), e sem os pontos no Gmail, que os ignora. */
create or replace function public.email_para_teste(p text)
returns text language plpgsql immutable set search_path = public as $$
declare e text := lower(btrim(coalesce(p, ''))); u text; dom text;
begin
  if position('@' in e) = 0 then return null; end if;
  u := split_part(e, '@', 1);
  dom := split_part(e, '@', 2);
  u := split_part(u, '+', 1);
  if dom in ('gmail.com', 'googlemail.com') then
    u := replace(u, '.', '');
    dom := 'gmail.com';
  end if;
  if u = '' or dom = '' then return null; end if;
  return u || '@' || dom;
end $$;

/* As marcas de uma pessoa: o WhatsApp e o e-mail.

   ⚠ O WHATSAPP SAI TAMBÉM DO QUE FOI DIGITADO NO CADASTRO, não só do perfil.
   Telefone que já é de outra conta entra no perfil como NULO (08_conta: o
   cadastro não pode morrer por isso). Olhando só o perfil, bastava manter a
   conta antiga, abrir outra com e-mail novo e o mesmo WhatsApp — o perfil
   novo nascia sem telefone, sem marca, e com mais 7 dias. O número digitado
   fica nos dados da conta (`raw_user_meta_data`) e é dali que ele vem. */
create or replace function public.marcas_de_teste(p_perfil uuid)
returns table (marca text, tipo text)
language sql stable security definer set search_path = public as $$
  select distinct encode(sha256(convert_to(x.chave, 'UTF8')), 'hex'), x.tipo
    from (
      select 'tel:' || public.tel_para_teste(p.telefone) as chave, 'telefone' as tipo
        from public.perfis p where p.id = p_perfil
      union all
      select 'tel:' || public.tel_para_teste(coalesce(u.raw_user_meta_data->>'telefone',
                                                     u.raw_user_meta_data->>'phone')), 'telefone'
        from auth.users u where u.id = p_perfil
      union all
      select 'email:' || public.email_para_teste(p.email), 'email'
        from public.perfis p where p.id = p_perfil
      union all
      select 'email:' || public.email_para_teste(u.email), 'email'
        from auth.users u where u.id = p_perfil
    ) x
   where x.chave is not null
$$;

create or replace function public.ja_usou_teste(p_perfil uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.marcas_de_teste(p_perfil) m
                   join public.testes_usados t on t.marca = m.marca)
$$;

create or replace function public.registrar_teste(p_perfil uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.testes_usados (marca, tipo)
  select m.marca, m.tipo from public.marcas_de_teste(p_perfil) m
  on conflict (marca) do update set ultimo_em = now()
$$;

-- ---------------------------------------------------------------------------
-- 3) ONDE O TESTE NASCE
-- ---------------------------------------------------------------------------
/* Na assinatura, e não dentro do `criar_salao()`: assim qualquer caminho que
   crie um salão em teste passa por aqui, e o 03 continua sendo a única
   versão da função de cadastro.

   O "Grátis" é escrito do jeito que o admin escreve (plano 'gratuito',
   status 'cancelada'): gratuito é a ausência de assinatura, e 'ativa' com
   preço zero leria como "pagando R$ 0". */
create or replace function public.tg_teste_uma_vez()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from 'trial' then return new; end if;
  -- O "Estender teste" e as outras ações da plataforma passam.
  if coalesce(current_setting('agendapro.plataforma', true), '') = 'sim' then return new; end if;
  -- Sem login (SQL Editor, worker) ou a própria plataforma criando salão de
  -- teste: não é cadastro de dono.
  if auth.uid() is null or public.is_super() then return new; end if;

  if public.ja_usou_teste(auth.uid()) then
    new.plano := 'gratuito';
    new.status := 'cancelada';
    new.trial_ate := null;
    new.vence_em := null;
  else
    perform public.registrar_teste(auth.uid());
  end if;
  return new;
end $$;

drop trigger if exists tg_teste_uma_vez on public.assinaturas;
create trigger tg_teste_uma_vez before insert on public.assinaturas
  for each row execute function public.tg_teste_uma_vez();

/* Ao deixar de ser dono (excluir a conta, sair do salão), as marcas de AGORA
   ficam: quem trocou de WhatsApp depois do cadastro deixa os dois. O perfil
   ainda existe neste instante — o `excluir_minha_conta()` tira os vínculos
   antes do login. */
create or replace function public.tg_dono_sai_marca()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.papel = 'dono' then
    perform public.registrar_teste(old.perfil_id);
  end if;
  return null;
end $$;

drop trigger if exists tg_dono_sai_marca on public.vinculos;
create trigger tg_dono_sai_marca after delete on public.vinculos
  for each row execute function public.tg_dono_sai_marca();

-- ---------------------------------------------------------------------------
-- 4) QUEM JÁ É DONO HOJE
-- ---------------------------------------------------------------------------
-- Sem isto, quem já está cadastrado poderia excluir e voltar uma última vez.
-- Rodar de novo não duplica nada.
insert into public.testes_usados (marca, tipo)
select m.marca, m.tipo
  from (select distinct perfil_id from public.vinculos where papel = 'dono') v
  cross join lateral public.marcas_de_teste(v.perfil_id) m
on conflict (marca) do nothing;

-- ---------------------------------------------------------------------------
-- 5) QUEM PODE CHAMAR
-- ---------------------------------------------------------------------------
revoke all on function public.marcas_de_teste(uuid) from public, anon, authenticated;
revoke all on function public.ja_usou_teste(uuid) from public, anon, authenticated;
revoke all on function public.registrar_teste(uuid) from public, anon, authenticated;
revoke all on function public.tg_teste_uma_vez() from public, anon, authenticated;
revoke all on function public.tg_dono_sai_marca() from public, anon, authenticated;

-- ###########################################################################
-- ## 40_saude.sql
-- ###########################################################################

-- ===========================================================================
-- AgendaPro — 40: o check-up do sistema (monitoramento)
--
-- "Preciso criar algo que fique monitorando o AgendaPro." O site no ar não
-- quer dizer que o sistema está funcionando: o defeito mais provável aqui é a
-- fila do WhatsApp parar calada — o despertador desligado, o token da Meta
-- vencido, a função de envio recusando — e ninguém notar até a cliente dizer
-- que não recebeu nada.
--
-- Este arquivo confere, a cada chamada:
--
--   · o banco responde (se esta função roda, responde);
--   · o despertador da fila (pg_cron) existe, está ligado e rodou agora há
--     pouco, sem falhar;
--   · a função de envio responde bem ao despertador (pg_net guarda a
--     resposta de cada chamada: 401 é o segredo trocado, 404 é a função não
--     publicada, 503 é o WhatsApp sem token);
--   · nenhuma mensagem está atrasada na fila;
--   · as mensagens não estão falhando — e, falhando, por quê, com o erro da
--     Meta traduzido e o que fazer.
--
-- E, só para o admin, o que é do NEGÓCIO e não do sistema: salão com a
-- franquia acabando e assinatura vencendo.
--
-- ── TRÊS PORTAS ────────────────────────────────────────────────────────────
--   saude_verificar()   faz a conta. Não é de ninguém de fora.
--   saude_plataforma()  o admin.html: tudo, com o nome dos salões. Só is_super().
--   saude_publica()     a função de borda `saude`, que o UptimeRobot visita:
--                       só "ok" ou "problema" e as chaves do que está errado.
--                       Nenhum nome de salão, telefone ou texto de mensagem.
--
-- O alerta sai pelo UptimeRobot, e não pelo WhatsApp do próprio sistema, de
-- propósito: se o que quebrou foi o WhatsApp, o aviso também não chegaria.
-- ===========================================================================

-- Uma linha do check-up. Função à parte só para o corpo de baixo não repetir
-- jsonb_build_object com cinco pares em cada um dos vinte lugares.
create or replace function public.saude_item(
  p_chave text, p_nivel text, p_titulo text, p_detalhe text, p_acao text default null)
returns jsonb language sql immutable set search_path = public as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'chave', p_chave, 'nivel', p_nivel, 'titulo', p_titulo,
    'detalhe', p_detalhe, 'acao', p_acao))
$$;

/* O erro da Meta, em português, e o que fazer. Os códigos são os da Cloud API
   (o worker grava `erro.code`). Os de cima param TUDO — token, conta, número,
   modelo — e por isso viram "problema"; os de baixo são de UMA cliente. */
create or replace function public.saude_erro_meta(p_codigo text)
returns text language sql immutable set search_path = public as $$
  select case p_codigo
    when '190'    then 'o token do WhatsApp venceu ou foi trocado. Gere um token permanente na Meta e atualize o segredo WHATSAPP_TOKEN no Supabase (Edge Functions, Secrets).'
    when '10'     then 'o token não tem permissão para enviar. Gere o token com a permissão whatsapp_business_messaging.'
    when '200'    then 'o token não tem permissão para enviar. Gere o token com a permissão whatsapp_business_messaging.'
    when '131005' then 'acesso negado pela Meta. Confira a permissão do token e o WHATSAPP_PHONE_ID.'
    when '131031' then 'a conta do WhatsApp Business foi bloqueada pela Meta. Veja o aviso no WhatsApp Manager.'
    when '368'    then 'a Meta bloqueou o número por um tempo, por política. Veja o WhatsApp Manager.'
    when '131042' then 'falta forma de pagamento na conta da Meta. Cadastre um cartão no WhatsApp Manager, em Pagamentos.'
    when '133010' then 'o número do WhatsApp não está registrado na API. Refaça o registro do número na Meta.'
    when '132001' then 'o modelo de mensagem não existe na Meta com esse nome e idioma. Confira os nomes no MODELOS.md.'
    when '132000' then 'o número de variáveis não bate com o modelo aprovado na Meta.'
    when '132015' then 'a Meta pausou o modelo de mensagem (qualidade baixa). Veja o WhatsApp Manager.'
    when '132016' then 'a Meta desativou o modelo de mensagem. Veja o WhatsApp Manager.'
    when '131026' then 'o número da cliente não tem WhatsApp ou não pôde receber.'
    when '131047' then 'passou da janela de 24 horas, e só modelo aprovado pode sair.'
    when '131049' then 'a Meta escolheu não entregar (limite de mensagens de marketing para a pessoa).'
    when '131056' then 'muitas mensagens seguidas para o mesmo número.'
    when '130429' then 'o limite de envio por segundo da Meta foi atingido.'
    when 'rede'   then 'erro de rede entre a função de envio e a Meta.'
    when 'sem_resposta' then 'o envio começou e a Meta não respondeu.'
    else 'erro ' || coalesce(p_codigo, 'sem código') || ' da Meta.'
  end
$$;

create or replace function public.saude_erro_grave(p_codigo text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(p_codigo in ('190','10','200','131005','131031','368','131042',
                               '133010','132001','132000','132015','132016'), false)
$$;

create or replace function public.saude_verificar()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_itens     jsonb := '[]'::jsonb;
  v_negocio   jsonb := '[]'::jsonb;
  v_jobid     bigint;
  v_schedule  text;
  v_cada      text;
  v_ativo     boolean;
  v_ultima    timestamptz;
  v_falhas_c  int;
  v_msg_c     text;
  v_status    int;
  v_tempo     boolean;
  v_erro_net  text;
  v_conteudo  text;
  v_erros_r   int;
  v_total_r   int;
  v_atrasadas int;
  v_antiga    timestamptz;
  v_presas    int;
  v_bloqueadas int;
  v_pendentes int;
  v_falhando  int;
  v_cod_agora text;
  v_falhou24  int;
  v_cod_24    text;
  v_enviadas  int;
  v_ultimo    timestamptz;
  v_grave     text;
  v_lista     text;
  v_nivel     text := 'ok';
  hm constant text := 'DD/MM HH24:MI';
begin
  -- 1. O banco. Se chegou aqui, responde.
  v_itens := v_itens || public.saude_item('banco', 'ok', 'Banco de dados', 'respondendo');

  -- 2. O despertador da fila.
  if to_regclass('cron.job') is null then
    v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
      'o pg_cron não está ligado neste banco: nada dispara o envio das mensagens.',
      'Rode o LIGAR-WHATSAPP.sql no SQL Editor do Supabase.');
  else
    select j.jobid, j.schedule, j.active into v_jobid, v_schedule, v_ativo
      from cron.job j where j.jobname = 'agendapro-notificacoes';
    -- O pg_cron escreve em inglês ("15 seconds"); a tela é em português.
    v_cada := case when v_schedule ~ '^[0-9]+ seconds?$'
                     then 'a cada ' || split_part(v_schedule, ' ', 1) || ' segundos'
                   when v_schedule = '* * * * *' then 'a cada minuto'
                   else 'no horário ' || v_schedule end;
    if v_jobid is null then
      v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
        'o despertador agendapro-notificacoes não existe: as mensagens não saem.',
        'Rode o LIGAR-WHATSAPP.sql no SQL Editor do Supabase.');
    elsif not v_ativo then
      v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
        'o despertador está pausado: as mensagens não saem.',
        'Rode o LIGAR-WHATSAPP.sql de novo, ou religue o agendapro-notificacoes no Supabase (Integrations, Cron).');
    elsif to_regclass('cron.job_run_details') is null then
      v_itens := v_itens || public.saude_item('despertador', 'ok', 'Despertador da fila',
        'ligado, ' || v_cada || '.');
    else
      /* As últimas voltas pela chave primária, e não `max(start_time)`: o
         pg_cron não apaga o histórico sozinho, e a cada 15 segundos ele passa
         de 5 mil linhas por dia. Pela chave, são 40 linhas lidas, sempre. */
      select max(d.start_time),
             count(*) filter (where d.status = 'failed'
                                and d.start_time > now() - interval '10 minutes'),
             (array_agg(d.return_message order by d.runid desc)
                filter (where d.status = 'failed'))[1]
        into v_ultima, v_falhas_c, v_msg_c
        from (select r.runid, r.start_time, r.status, r.return_message
                from cron.job_run_details r
               where r.jobid = v_jobid
               order by r.runid desc limit 40) d;
      if v_ultima is null or v_ultima < now() - interval '3 minutes' then
        v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
          case when v_ultima is null then 'o despertador nunca rodou.'
               else 'o despertador não roda desde '
                    || to_char(v_ultima at time zone 'America/Sao_Paulo', hm) || '.' end,
          'Confira em Integrations, Cron, no Supabase. Se não resolver, rode o LIGAR-WHATSAPP.sql de novo.');
      elsif v_falhas_c > 0 then
        v_itens := v_itens || public.saude_item('despertador', 'problema', 'Despertador da fila',
          'o despertador falhou ' || v_falhas_c || ' vez(es) nos últimos 10 minutos: '
          || coalesce(left(v_msg_c, 160), 'sem mensagem') || '.',
          'Rode o LIGAR-WHATSAPP.sql de novo (ele também liga o pg_net).');
      else
        v_itens := v_itens || public.saude_item('despertador', 'ok', 'Despertador da fila',
          'rodando ' || v_cada || ' (última volta às '
          || to_char(v_ultima at time zone 'America/Sao_Paulo', 'HH24:MI:SS') || ').');
      end if;
    end if;
  end if;

  -- 3. A função de envio, pelo que ela respondeu ao despertador.
  if to_regclass('net._http_response') is not null then
    select count(*) filter (where r.status_code >= 400 or r.timed_out or r.error_msg is not null),
           count(*)
      into v_erros_r, v_total_r
      from (select * from net._http_response order by id desc limit 20) r;
    select r.status_code, coalesce(r.timed_out, false), r.error_msg, left(r.content, 200)
      into v_status, v_tempo, v_erro_net, v_conteudo
      from net._http_response r order by r.id desc limit 1;

    if v_total_r = 0 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'atencao', 'Função de envio',
        'ainda não há resposta registrada da função enviar-notificacoes.',
        'Se o despertador acabou de ser ligado, espere um minuto e verifique de novo.');
    elsif v_tempo then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função enviar-notificacoes não respondeu a tempo.',
        'Abra os logs da função enviar-notificacoes no Supabase (Edge Functions).');
    elsif v_erro_net is not null then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'o despertador não conseguiu chamar a função: ' || left(v_erro_net, 160) || '.',
        'Confira o endereço da função no LIGAR-WHATSAPP.sql.');
    elsif v_status = 401 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função recusou o despertador (401): a frase do CRON_SEGREDO não é a mesma dos dois lados.',
        'Confira o segredo CRON_SEGREDO no Supabase (Edge Functions, Secrets) e o x-cron-segredo no LIGAR-WHATSAPP.sql.');
    elsif v_status = 404 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função enviar-notificacoes não está publicada (404).',
        'No GitHub: Actions, "Publicar as funções", Run workflow.');
    elsif v_status = 503 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'faltam WHATSAPP_TOKEN e/ou WHATSAPP_PHONE_ID nos segredos da função (503).',
        'Cadastre os dois no Supabase (Edge Functions, Secrets).');
    elsif v_status >= 400 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'problema', 'Função de envio',
        'a função de envio respondeu com erro ' || v_status || ': '
        || coalesce(nullif(btrim(v_conteudo), ''), 'sem detalhe') || '.',
        'Abra os logs da função enviar-notificacoes no Supabase (Edge Functions).');
    elsif v_erros_r > 5 then
      v_itens := v_itens || public.saude_item('funcao_envio', 'atencao', 'Função de envio',
        v_erros_r || ' das últimas ' || v_total_r || ' chamadas deram erro; a última foi bem.');
    else
      v_itens := v_itens || public.saude_item('funcao_envio', 'ok', 'Função de envio',
        'respondendo (última resposta: ' || v_status || ').');
    end if;
  end if;

  -- 4. A fila. Atrasada é a que já devia ter saído há 5 minutos, não está
  -- esperando nova tentativa e não está parada pela franquia do salão (essa
  -- espera de propósito, e entra no negócio, mais abaixo).
  select count(*), min(n.quando) into v_atrasadas, v_antiga
    from public.notificacoes n
   where n.status = 'pendente' and n.erro_codigo is null
     and n.quando < now() - interval '5 minutes'
     and (n.proxima_em is null or n.proxima_em < now())
     and public.pode_enviar_tipo(n.salao_id, n.tipo);
  select count(*) into v_presas
    from public.notificacoes n
   where n.status = 'enviando'
     and coalesce(n.proxima_em, n.quando + interval '1 hour') < now();
  select count(*) filter (where n.quando <= now() and not public.pode_enviar_tipo(n.salao_id, n.tipo)),
         count(*)
    into v_bloqueadas, v_pendentes
    from public.notificacoes n where n.status = 'pendente';

  if v_atrasadas > 0 or v_presas > 0 then
    v_itens := v_itens || public.saude_item('fila', 'problema', 'Fila de mensagens',
      concat_ws(' ',
        case when v_atrasadas > 0 then v_atrasadas || ' mensagem(ns) atrasada(s): a mais antiga devia ter saído em '
             || to_char(v_antiga at time zone 'America/Sao_Paulo', hm) || '.' end,
        case when v_presas > 0 then v_presas || ' presa(s) no meio do envio.' end),
      'Veja o despertador e a função de envio acima. Se os dois estiverem certos, abra os logs da função enviar-notificacoes.');
  else
    v_itens := v_itens || public.saude_item('fila', 'ok', 'Fila de mensagens',
      'nenhuma mensagem atrasada (' || v_pendentes || ' na fila para mais tarde).');
  end if;

  -- 5. As falhas: as que estão tentando de novo agora, e as das últimas 24h.
  select count(*), mode() within group (order by n.erro_codigo)
    into v_falhando, v_cod_agora
    from public.notificacoes n where n.status = 'pendente' and n.erro_codigo is not null;
  select count(*), mode() within group (order by n.erro_codigo)
    into v_falhou24, v_cod_24
    from public.notificacoes n
   where n.status = 'falhou' and n.quando > now() - interval '24 hours';
  select count(*), max(n.enviado_em) into v_enviadas, v_ultimo
    from public.notificacoes n
   where n.status in ('enviado', 'entregue', 'lido')
     and n.enviado_em > now() - interval '24 hours';
  select n.erro_codigo into v_grave
    from public.notificacoes n
   where public.saude_erro_grave(n.erro_codigo)
     and ((n.status = 'pendente') or (n.status = 'falhou' and n.quando > now() - interval '24 hours'))
   order by n.quando desc limit 1;

  if v_grave is not null then
    v_itens := v_itens || public.saude_item('falhas', 'problema', 'Envio pelo WhatsApp',
      'as mensagens estão falhando: ' || public.saude_erro_meta(v_grave),
      'Resolva na Meta ou no Supabase como dito ao lado. As que ainda estão tentando saem sozinhas depois.');
  elsif v_falhou24 >= 5 and v_falhou24 > v_enviadas then
    v_itens := v_itens || public.saude_item('falhas', 'problema', 'Envio pelo WhatsApp',
      'mais falhas que envios nas últimas 24h (' || v_falhou24 || ' falharam, '
      || v_enviadas || ' saíram). Motivo mais comum: ' || public.saude_erro_meta(v_cod_24),
      'Veja o histórico em Notificações, num salão, para o motivo de cada uma.');
  elsif v_falhando > 0 or v_falhou24 > 0 then
    v_itens := v_itens || public.saude_item('falhas', 'atencao', 'Envio pelo WhatsApp',
      concat_ws(' ',
        case when v_falhou24 > 0 then v_falhou24 || ' falharam nas últimas 24h (' || v_enviadas
             || ' saíram). Motivo mais comum: ' || public.saude_erro_meta(v_cod_24) end,
        case when v_falhando > 0 then v_falhando || ' tentando de novo agora: '
             || public.saude_erro_meta(v_cod_agora) end));
  else
    v_itens := v_itens || public.saude_item('falhas', 'ok', 'Envio pelo WhatsApp',
      v_enviadas || ' enviada(s) nas últimas 24h, nenhuma falha.');
  end if;

  -- 6. O negócio (só o admin vê): franquia acabando, assinatura vencendo.
  select string_agg(x.nome || ': ' || x.usado || ' de ' || x.teto, '; ' order by x.pct desc)
    into v_lista
    from (select s.nome, public.mensagens_no_mes(s.id) as usado,
                 public.teto_mensagens(s.id) as teto,
                 public.mensagens_no_mes(s.id)::numeric
                   / nullif(public.teto_mensagens(s.id), 0) as pct
            from public.saloes s
           where s.id in (select distinct n.salao_id from public.notificacoes n
                           where n.enviado_em > now() - interval '35 days')) x
   where x.teto > 0 and x.pct >= 0.9;
  if v_lista is not null then
    v_negocio := v_negocio || public.saude_item('franquia', 'atencao',
      'Salões com as mensagens acabando', v_lista || '.',
      'Ofereça um plano maior ou mensagens extras.');
  end if;
  if v_bloqueadas > 0 then
    v_negocio := v_negocio || public.saude_item('franquia_parada', 'atencao',
      'Mensagens paradas pela franquia', v_bloqueadas
      || ' mensagem(ns) esperando porque a franquia do salão acabou.');
  end if;

  select string_agg(s.nome || case when a.vence_em >= current_date
                                   then ' vence em ' else ' venceu em ' end
                    || to_char(a.vence_em, 'DD/MM'), '; ' order by a.vence_em)
    into v_lista
    from public.assinaturas a join public.saloes s on s.id = a.salao_id
   where a.status = 'ativa'
     and a.vence_em between current_date - 7 and current_date + 3;
  if v_lista is not null then
    v_negocio := v_negocio || public.saude_item('vencimentos', 'atencao',
      'Assinaturas vencendo', v_lista || '.',
      'Quem passa do vencimento cai para o Grátis e para de receber mensagens.');
  end if;

  -- O pior de todos, só entre os do sistema: negócio não derruba o check-up.
  select case when bool_or(i->>'nivel' = 'problema') then 'problema'
              when bool_or(i->>'nivel' = 'atencao')  then 'atencao'
              else 'ok' end
    into v_nivel
    from jsonb_array_elements(v_itens) i;

  return jsonb_build_object(
    'nivel', v_nivel,
    'verificadoEm', now(),
    'itens', v_itens,
    'negocio', v_negocio,
    'numeros', jsonb_build_object(
      'enviadas24h', v_enviadas, 'falhas24h', v_falhou24,
      'pendentes', v_pendentes, 'ultimoEnvio', v_ultimo));
end $$;

/* O admin.html. Tudo, com nome de salão: é a plataforma olhando para si. */
create or replace function public.saude_plataforma()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma abre o check-up.'
      using errcode = 'insufficient_privilege';
  end if;
  return public.saude_verificar();
end $$;

/* A função de borda `saude`, que o UptimeRobot visita. Só o nível e as CHAVES
   do que está errado ("despertador", "falhas"…): nenhum nome de salão, número
   ou texto de mensagem sai daqui, porque o endereço é público. */
create or replace function public.saude_publica()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'nivel', s->>'nivel',
    'verificadoEm', s->'verificadoEm',
    'problemas', coalesce((select jsonb_agg(i->>'chave')
                             from jsonb_array_elements(s->'itens') i
                            where i->>'nivel' = 'problema'), '[]'::jsonb),
    'atencao', coalesce((select jsonb_agg(i->>'chave')
                           from jsonb_array_elements(s->'itens') i
                          where i->>'nivel' = 'atencao'), '[]'::jsonb))
    from (select public.saude_verificar() as s) x
$$;

revoke all on function public.saude_item(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.saude_erro_meta(text)  from public, anon, authenticated;
revoke all on function public.saude_erro_grave(text) from public, anon, authenticated;
revoke all on function public.saude_verificar()      from public, anon, authenticated;
revoke all on function public.saude_publica()        from public, anon, authenticated;
revoke all on function public.saude_plataforma()     from public, anon;
grant execute on function public.saude_plataforma() to authenticated;
/* ⚠ E O CARTEIRO PRECISA DA CHAVE (a mesma lição do 13_cobranca): o
   `revoke ... from public` tira também o `service_role`, que é com quem a
   função de borda fala com o banco. */
grant execute on function public.saude_publica() to service_role;

-- ###########################################################################
-- ## 41_ficha_equipe.sql
-- ###########################################################################

-- ===========================================================================
-- 41_ficha_equipe.sql — o que só a equipe sabe: o "como fazer" de cada
-- serviço, os procedimentos (o passo a passo) e os lembretes sobre a cliente
--
-- Os pedidos: "criar um lugar que o profissional consiga fazer o
-- procedimento, exemplo: coloração loiro perolado, quais as tintas e como
-- lavar o cabelo" e "no cadastro da cliente Maria, marcar algo que lembre
-- dela: essa não gosta de conversar, ou dá problema na hora do pagamento".
--
-- ── 1) O COMO FAZER MORA NO SERVIÇO ─────────────────────────────────────────
-- `servicos.procedimento`: as tintas, os tempos, a lavagem. A tabela de
-- serviços já é só da equipe (35_acesso.sql), e o link da cliente lê o
-- cardápio pela `vitrine()`, que escolhe as colunas uma a uma — esta não vai.
--
-- ── 2) OS LEMBRETES SÃO OUTRA TABELA, E NÃO UM CAMPO NA FICHA ───────────────
-- A cliente com conta LÊ a própria ficha (`cli_eu`, 02_rls.sql): é dado dela,
-- a LGPD manda deixar ver. "Dá problema na hora do pagamento" escrito no
-- `obs` ela leria pela API. O 02 já tinha deixado escrito: anotação interna
-- que a cliente não lê vira outra tabela, e não um campo escondido nesta.
--
-- Uma linha por cliente: as marcas tocadas na tela ("Prefere não conversar",
-- "Atenção no pagamento"...) e um texto livre. Quem lê e escreve é a equipe
-- do salão — a profissional que vai atender é quem mais precisa saber.
--
-- ── 3) OS PROCEDIMENTOS: UM TÓPICO PRÓPRIO ──────────────────────────────────
-- "Tem coloração que uma é diferente da outra": o mesmo serviço Coloração é
-- Morena iluminada para uma cliente e Loiro perolado para outra. Por isso, além
-- do como fazer do serviço, a tabela `procedimentos`: o dono cria quantos
-- quiser, cada um com os produtos e o passo a passo, e pode ligar ao serviço.
-- No horário daquele serviço, a profissional vê os procedimentos dele.
-- A equipe lê; quem escreve é a gestão (como em Serviços). A cliente não lê.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O COMO FAZER DO SERVIÇO
-- ---------------------------------------------------------------------------
alter table public.servicos add column if not exists procedimento text;
do $$ begin
  alter table public.servicos add constraint servicos_procedimento_tamanho
    check (procedimento is null or length(procedimento) <= 4000);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2) OS LEMBRETES DA EQUIPE SOBRE A CLIENTE
-- ---------------------------------------------------------------------------
create table if not exists public.clientes_lembretes (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  cliente_id    uuid not null references public.clientes(id) on delete cascade,
  marcas        text[] not null default '{}',
  texto         text,
  atualizado_em timestamptz not null default now(),
  check (cardinality(marcas) <= 12),
  check (texto is null or length(texto) <= 1000)
);
create unique index if not exists ux_lembrete_cliente on public.clientes_lembretes(cliente_id);
create index if not exists ix_lembrete_salao on public.clientes_lembretes(salao_id);

/* A cliente tem de ser do salão da linha: sem isto, quem é equipe de um
   salão gravaria lembrete apontando para a ficha de outro. A policy abaixo
   já garante que quem grava é da equipe de `salao_id`; aqui se garante que a
   ficha é desse mesmo salão. (Como todo gatilho do projeto, roda como dono —
   o tests/portas.test.sql cobra.) E as marcas chegam limpas: sem repetida,
   sem vazia, cada uma com até 40 letras, na ordem tocada. */
create or replace function public.tg_lembrete_cliente()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.clientes c
                  where c.id = new.cliente_id and c.salao_id = new.salao_id) then
    raise exception 'Esta cliente não é deste salão.' using errcode = 'check_violation';
  end if;
  new.marcas := coalesce(array(
    select m from (select left(btrim(x), 40) as m, min(o) as o
                     from unnest(new.marcas) with ordinality as t(x, o)
                    where btrim(coalesce(x, '')) <> ''
                    group by left(btrim(x), 40)) s
     order by o), '{}');
  new.texto := nullif(btrim(coalesce(new.texto, '')), '');
  if tg_op = 'UPDATE' then new.atualizado_em := now(); end if;
  return new;
end $$;

drop trigger if exists tg_lembrete_cliente on public.clientes_lembretes;
create trigger tg_lembrete_cliente
  before insert or update on public.clientes_lembretes
  for each row execute function public.tg_lembrete_cliente();

-- ---------------------------------------------------------------------------
-- 3) QUEM LÊ, QUEM ESCREVE
--
-- A equipe do salão, inteira: dono, recepção e profissional. A cliente não
-- tem policy aqui — nem logada, nem pelo link. O anônimo não tem nem grant.
-- ---------------------------------------------------------------------------
alter table public.clientes_lembretes enable row level security;

drop policy if exists lembretes_equipe on public.clientes_lembretes;
create policy lembretes_equipe on public.clientes_lembretes
  for all to authenticated
  using (public.e_equipe(salao_id)) with check (public.e_equipe(salao_id));

grant select, insert, update, delete on public.clientes_lembretes to authenticated;
revoke all on public.clientes_lembretes from anon;
revoke all on function public.tg_lembrete_cliente() from public, anon, authenticated;

-- A trava do modo suporte (38_suporte.sql) vale aqui como nas outras tabelas
-- do salão: a plataforma olhando o painel não escreve sem "Liberar edição".
do $$ begin
  if to_regprocedure('public.tg_suporte()') is not null then
    drop trigger if exists zz_suporte on public.clientes_lembretes;
    create trigger zz_suporte after insert or update or delete on public.clientes_lembretes
      for each row execute function public.tg_suporte();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4) OS PROCEDIMENTOS
-- ---------------------------------------------------------------------------
create table if not exists public.procedimentos (
  id            uuid primary key default gen_random_uuid(),
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  nome          text not null,
  servico_id    uuid references public.servicos(id) on delete set null,
  produtos      text,
  passos        text,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (length(btrim(nome)) between 1 and 80),
  check (produtos is null or length(produtos) <= 2000),
  check (passos is null or length(passos) <= 8000)
);
create index if not exists ix_procedimentos_salao on public.procedimentos(salao_id);

/* O serviço ligado tem de ser do mesmo salão: sem isto, a gestão de um salão
   penduraria o procedimento num serviço de outro. Roda como dono, como todo
   gatilho do projeto; a policy abaixo já garante que quem grava é gestão de
   `salao_id`. */
create or replace function public.tg_procedimento()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.servico_id is not null and not exists (
       select 1 from public.servicos s where s.id = new.servico_id and s.salao_id = new.salao_id) then
    raise exception 'Este serviço não é deste salão.' using errcode = 'check_violation';
  end if;
  new.nome := btrim(new.nome);
  new.produtos := nullif(btrim(coalesce(new.produtos, '')), '');
  new.passos := nullif(btrim(coalesce(new.passos, '')), '');
  if tg_op = 'UPDATE' then new.atualizado_em := now(); end if;
  return new;
end $$;

drop trigger if exists tg_procedimento on public.procedimentos;
create trigger tg_procedimento
  before insert or update on public.procedimentos
  for each row execute function public.tg_procedimento();

alter table public.procedimentos enable row level security;

drop policy if exists procedimentos_ler on public.procedimentos;
create policy procedimentos_ler on public.procedimentos
  for select to authenticated using (public.e_equipe(salao_id));
drop policy if exists procedimentos_escrever on public.procedimentos;
create policy procedimentos_escrever on public.procedimentos
  for all to authenticated
  using (public.e_gestor(salao_id)) with check (public.e_gestor(salao_id));

grant select, insert, update, delete on public.procedimentos to authenticated;
revoke all on public.procedimentos from anon;
revoke all on function public.tg_procedimento() from public, anon, authenticated;

do $$ begin
  if to_regprocedure('public.tg_suporte()') is not null then
    drop trigger if exists zz_suporte on public.procedimentos;
    create trigger zz_suporte after insert or update or delete on public.procedimentos
      for each row execute function public.tg_suporte();
  end if;
end $$;

-- ###########################################################################
-- ## 42_travas.sql
-- ###########################################################################

-- ===========================================================================
-- 42_travas.sql — o que a auditoria de segurança achou, fechado no banco
--
-- O pedido: "conferir a segurança do meu app". A auditoria passou por todas
-- as tabelas, todas as funções que se chamam de fora, as funções do servidor
-- e as fotos. Quase tudo já estava trancado. Três portas não:
--
--   1. a dona de um salão SUSPENSO pela plataforma se reativava sozinha:
--      `salao_gerir` deixa a gestão editar a linha do salão, e a coluna
--      `status` ia junto — pela API, sem passar pela tela;
--   2. qualquer conta lia a linha INTEIRA de qualquer salão (o `cfg` todo):
--      virar "cliente" de um salão é um insert livre (`vinc_virar_cliente`,
--      é o que o link faz), e `tem_acesso()` conta a cliente;
--   3. `porque_nao_cabe()` dizia nome de cliente e motivo de bloqueio a
--      qualquer conta logada — essa é fechada no próprio 14_motor.sql.
--
-- Os outros achados (o painel dentro de um quadro de outro site, o e-mail na
-- tela de entrar) são das páginas, e não daqui.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O STATUS DO SALÃO É DA PLATAFORMA
--
-- Ativo, suspenso, cancelado: quem decide é a `definir_status_salao()`, que
-- só a plataforma chama. A data de criação vai junto: é histórico, e o painel
-- da plataforma lê. Pela internet (anon/authenticated), sem ser a plataforma,
-- as duas não mudam. O SQL Editor, o worker e o service_role passam (o `role`
-- deles não é anon nem authenticated), como passam no modo suporte (38).
-- ---------------------------------------------------------------------------
create or replace function public.tg_salao_campos_da_plataforma()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('role', true), 'none') not in ('anon', 'authenticated')
     or public.is_super()
     or coalesce(current_setting('agendapro.plataforma', true), '') = 'sim' then
    return new;
  end if;
  if new.status is distinct from old.status then
    raise exception 'Só a plataforma muda a situação do salão (ativo, suspenso ou cancelado).'
      using errcode = 'insufficient_privilege';
  end if;
  if new.criado_em is distinct from old.criado_em then
    raise exception 'A data de criação do salão não muda.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

drop trigger if exists tg_salao_campos_da_plataforma on public.saloes;
create trigger tg_salao_campos_da_plataforma
  before update on public.saloes
  for each row execute function public.tg_salao_campos_da_plataforma();

revoke all on function public.tg_salao_campos_da_plataforma() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) A LINHA DO SALÃO É DA EQUIPE
--
-- A cliente lê o salão pela `vitrine()`, que escolhe campo por campo o que a
-- página mostra — e diz por quê: o `cfg` é jsonb, cresce, e devolvê-lo por
-- atacado é um vazamento esperando a próxima chave. A tabela, então, fica
-- com quem trabalha no salão (e a plataforma, que o `e_equipe()` já inclui).
-- Nenhuma página da cliente lê a tabela: o `salaoPorSlug()` do dados.js
-- também passa pela vitrine.
-- ---------------------------------------------------------------------------
drop policy if exists salao_ler on public.saloes;
create policy salao_ler on public.saloes for select to authenticated
  using ( public.e_equipe(id) );

-- ###########################################################################
-- ## 43_pacote_agenda.sql
-- ###########################################################################

-- ===========================================================================
-- 43_pacote_agenda.sql — o pacote com agenda fixa, e o pagamento do pacote
--
-- O pedido: "incluir uma cliente no pacote e já agendar 4 semanas para ela —
-- ela paga mensal e vai toda terça às 14h. Na primeira terça faz mão, na
-- segunda mão e pé, na terceira só mão, na quarta mão e pé." E, logo depois:
-- "como faço a parte de pagamento para a cliente?"
--
-- ── 1) MONTAR O PACOTE: O VÍNCULO E AS SEMANAS, TUDO OU NADA ───────────────
-- `montar_pacote()` vincula a cliente e já marca cada semana, com os serviços
-- daquela semana. Antes de marcar, confere TODAS: data que passou, dia em que
-- o pacote não vale, serviço de fora do pacote, horário ocupado, bloqueio,
-- fora da jornada. Se uma semana não cabe, nada é gravado e a resposta diz
-- qual semana e por quê — a tela deixa trocar só aquela e tentar de novo.
-- Pacote pela metade (duas terças marcadas, duas não) é pior que nenhum.
--
-- ── 2) UMA MENSAGEM SÓ, COM TODAS AS DATAS ─────────────────────────────────
-- Cada horário marcado gera a sua confirmação — quatro mensagens da franquia
-- para dizer uma coisa. Aqui a primeira leva as quatro datas ("04/11, 11/11,
-- 18/11 e 25/11 às 14:00") e as outras saem da fila. É o MESMO modelo de
-- confirmação já aprovado na Meta: a lista vai no lugar da data, e nenhum
-- modelo novo precisa de aprovação. O lembrete da véspera continua saindo
-- para cada uma.
--
-- ── 3) O PAGAMENTO VIRA COMANDA, COMO TODO DINHEIRO DO SISTEMA ─────────────
-- Até aqui o preço do pacote era só referência: cada sessão sai a R$ 0,00, e
-- o dinheiro do pacote não aparecia em faturamento nenhum. O 28 já tinha
-- decidido que dinheiro tem UM caminho — comanda fechada — e o relatório, o
-- painel do dia e o dashboard leem só esse. Então `receber_pacote()` monta
-- uma comanda automática com o item "Pacote …" e o pagamento, e fecha. Sem
-- profissional no item: a venda do pacote não gera comissão, como a sessão
-- de pacote já não gerava (28).
--
-- O pacote "a receber" é o vínculo com valor combinado e sem `pago_em`. A
-- mensagem para a cliente deixa de dizer "já pago" enquanto ele estiver
-- assim (21_notificacoes.sql).
--
-- ── QUEM ──────────────────────────────────────────────────────────────────
-- O balcão e a gestão (`ve_agenda_toda`): quem marca horário e recebe
-- dinheiro no salão. Criar e editar o pacote (preço, sessões) continua sendo
-- da gestão; tirar a cliente do pacote também (27).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O PAGAMENTO NO VÍNCULO
-- ---------------------------------------------------------------------------
alter table public.pacote_clientes add column if not exists valor numeric(10,2);
alter table public.pacote_clientes add column if not exists pago_em timestamptz;
alter table public.pacote_clientes add column if not exists forma_pagamento text;
alter table public.pacote_clientes add column if not exists comanda_id uuid
  references public.comandas(id) on delete set null;
do $$ begin
  alter table public.pacote_clientes add constraint pacote_clientes_valor_check
    check (valor is null or valor >= 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.pacote_clientes add constraint pacote_clientes_forma_check
    check (forma_pagamento is null
           or forma_pagamento in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia'));
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2) RECEBER O PAGAMENTO DO PACOTE
-- ---------------------------------------------------------------------------
/* Os lembretes que ainda vão sair (da cliente e da equipe) são reescritos
   quando o pacote é pago, ou o pagamento é desfeito: a mensagem leva o valor
   e o pagamento do pacote (21, `pecas_agendamento`), e o lembrete da véspera
   não pode dizer "a pagar no salão" de um pacote que já foi pago. O que já
   saiu não se mexe. */
create or replace function public.refazer_textos_do_pacote(p_pacote_cliente uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.notificacoes n
     set corpo = coalesce(public.texto_agendamento(n.agendamento_id, 'lembrete'), n.corpo),
         variaveis = coalesce(public.variaveis_agendamento(n.agendamento_id, 'lembrete'), n.variaveis),
         modelo = public.modelo_de('lembrete')
   where n.tipo = 'lembrete' and n.status = 'pendente'
     and n.agendamento_id in (select a.id from public.agendamentos a
                               where a.pacote_cliente_id = p_pacote_cliente);
  update public.notificacoes n
     set corpo = coalesce(public.texto_lembrete_equipe(n.agendamento_id, n.profissional_id), n.corpo),
         variaveis = coalesce(public.variaveis_lembrete_equipe(n.agendamento_id, n.profissional_id), n.variaveis),
         modelo = public.modelo_de('lembrete_equipe')
   where n.tipo = 'lembrete_equipe' and n.status = 'pendente'
     and n.agendamento_id in (select a.id from public.agendamentos a
                               where a.pacote_cliente_id = p_pacote_cliente);
end $$;

create or replace function public.receber_pacote(
  p_pacote_cliente uuid, p_forma text, p_valor numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; v_valor numeric(10,2); v_comanda uuid; v_ids uuid[]; v_id uuid;
begin
  select pc.*, p.salao_id, p.nome as pacote_nome into r
    from public.pacote_clientes pc
    join public.pacotes p on p.id = pc.pacote_id
   where pc.id = p_pacote_cliente;
  if r.id is null then
    raise exception 'Não achei este pacote da cliente.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(r.salao_id) then
    raise exception 'Só o balcão e a gestão registram pagamento.'
      using errcode = 'insufficient_privilege';
  end if;
  if r.cancelado_em is not null then
    raise exception 'Este pacote foi cancelado.' using errcode = 'check_violation';
  end if;
  if r.pago_em is not null then
    raise exception 'Este pacote já está pago.' using errcode = 'check_violation';
  end if;
  if coalesce(p_forma, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
    raise exception 'Escolha como ela pagou: Pix, dinheiro, cartão ou transferência.'
      using errcode = 'check_violation';
  end if;
  v_valor := round(coalesce(p_valor, r.valor, 0), 2);
  if v_valor <= 0 then
    raise exception 'Diga quanto ela pagou.' using errcode = 'check_violation';
  end if;

  insert into public.comandas (salao_id, cliente_id, automatica)
       values (r.salao_id, r.cliente_id, true)
    returning id into v_comanda;
  insert into public.comanda_itens (comanda_id, tipo, descricao, qtd, preco_unit)
       values (v_comanda, 'servico', 'Pacote ' || r.pacote_nome, 1, v_valor);
  insert into public.pagamentos (comanda_id, forma, valor)
       values (v_comanda, p_forma, v_valor);
  update public.comandas set status = 'fechada', fechada_em = now() where id = v_comanda;

  update public.pacote_clientes
     set valor = v_valor, pago_em = now(), forma_pagamento = p_forma, comanda_id = v_comanda
   where id = p_pacote_cliente;

  /* ⚠ AS SESSÕES RESERVADAS VIRAM CONFIRMADAS. "O pacote precisa estar pago
     para marcar": vendido a receber, com agenda fixa, as semanas nascem
     pendentes (reservadas, esperando o pagamento) e a cliente ainda não
     recebe nada. Pago, as que ainda vêm são confirmadas — o gatilho do 29
     põe a confirmação e o lembrete de cada uma na fila — e as confirmações
     viram uma mensagem só, com todas as datas (ou a lista do pacote, 45). O
     lembrete que tinha sido cancelado (pagamento desfeito e refeito) volta. */
  select coalesce(array_agg(a.id order by a.inicio), '{}') into v_ids
    from public.agendamentos a
   where a.pacote_cliente_id = p_pacote_cliente and a.status = 'pendente'
     and a.arquivado_em is null and a.inicio > now();
  if cardinality(v_ids) > 0 then
    update public.agendamentos set status = 'confirmado' where id = any(v_ids);
    foreach v_id in array v_ids loop
      perform public.refazer_lembrete_cliente(v_id);
      perform public.refazer_lembrete_equipe(v_id);
    end loop;
    perform public.juntar_mensagens_do_pacote(v_ids, r.pacote_nome);
  end if;
  perform public.refazer_textos_do_pacote(p_pacote_cliente);
  return jsonb_build_object('ok', true, 'comanda', v_comanda, 'valor', v_valor,
                            'confirmadas', cardinality(v_ids));
end $$;

/* Lançou como pago por engano: a comanda automática sai (o faturamento volta
   ao que era) e o pacote volta a "a receber". Só a gestão desfaz dinheiro. */
create or replace function public.desfazer_recebimento_pacote(p_pacote_cliente uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select pc.*, p.salao_id into r
    from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
   where pc.id = p_pacote_cliente;
  if r.id is null then
    raise exception 'Não achei este pacote da cliente.' using errcode = 'check_violation';
  end if;
  if not public.e_gestor(r.salao_id) then
    raise exception 'Só o proprietário ou um administrador desfaz um recebimento.'
      using errcode = 'insufficient_privilege';
  end if;
  if r.pago_em is null then
    raise exception 'Este pacote ainda não foi pago.' using errcode = 'check_violation';
  end if;
  update public.pacote_clientes
     set pago_em = null, forma_pagamento = null, comanda_id = null
   where id = p_pacote_cliente;
  delete from public.comandas where id = r.comanda_id and automatica;
  /* A mesma regra ao contrário: sem pagamento, as sessões que ainda vêm
     voltam a ser só reserva, e os lembretes delas saem da fila. Pago de
     novo, voltam (`receber_pacote`). O que já aconteceu fica como está. */
  update public.agendamentos set status = 'pendente'
   where pacote_cliente_id = p_pacote_cliente and status = 'confirmado'
     and arquivado_em is null and inicio > now();
  update public.notificacoes n
     set status = 'cancelado', motivo = 'o pagamento do pacote foi desfeito'
   where n.status = 'pendente'
     and (n.chave = 'pacote_agenda:' || p_pacote_cliente
          or (n.tipo in ('lembrete', 'lembrete_equipe', 'confirmacao')
              and n.agendamento_id in (select a.id from public.agendamentos a
                                        where a.pacote_cliente_id = p_pacote_cliente
                                          and a.status = 'pendente')));
  perform public.refazer_textos_do_pacote(p_pacote_cliente);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 3) AS DATAS ESCRITAS COMO GENTE ESCREVE, E A MENSAGEM ÚNICA
-- ---------------------------------------------------------------------------
/* "04/11, 11/11, 18/11 e 25/11", com a hora mais comum à parte. A semana em
   outro horário leva o dela entre parênteses: "18/11 (15:00)". */
create or replace function public.datas_do_pacote(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_fuso text; v_hora text; v_lista text[];
begin
  select coalesce(sa.fuso, 'America/Sao_Paulo') into v_fuso
    from public.agendamentos a join public.saloes sa on sa.id = a.salao_id
   where a.id = p_ids[1];
  select mode() within group (order by to_char(a.inicio at time zone v_fuso, 'HH24:MI'))
    into v_hora
    from public.agendamentos a where a.id = any(p_ids);
  select array_agg(to_char(a.inicio at time zone v_fuso, 'DD/MM')
                   || case when to_char(a.inicio at time zone v_fuso, 'HH24:MI') <> v_hora
                           then ' (' || to_char(a.inicio at time zone v_fuso, 'HH24:MI') || ')'
                           else '' end
                   order by a.inicio)
    into v_lista
    from public.agendamentos a where a.id = any(p_ids);
  return jsonb_build_object('hora', v_hora, 'datas',
    case when cardinality(v_lista) <= 1 then coalesce(v_lista[1], '')
         else array_to_string(v_lista[1:cardinality(v_lista) - 1], ', ')
              || ' e ' || v_lista[cardinality(v_lista)] end);
end $$;

create or replace function public.juntar_mensagens_do_pacote(p_ids uuid[], p_pacote text)
returns void language plpgsql security definer set search_path = public as $$
declare d jsonb; v_datas text; v_hora text; v_serv text; v_data1 text; v_serv1 text; v_fuso text;
begin
  if cardinality(p_ids) < 2 then return; end if;
  d := public.datas_do_pacote(p_ids);
  v_datas := public.variavel_limpa(d->>'datas');
  v_hora  := public.variavel_limpa(d->>'hora');
  v_serv  := public.variavel_limpa('pacote ' || p_pacote);
  select to_char(a.inicio at time zone coalesce(sa.fuso, 'America/Sao_Paulo'), 'DD/MM/YYYY'),
         coalesce((select string_agg(sv.nome, ' + ' order by asv.ordem)
                     from public.agendamento_servicos asv
                     join public.servicos sv on sv.id = asv.servico_id
                    where asv.agendamento_id = a.id), 'atendimento')
    into v_data1, v_serv1
    from public.agendamentos a join public.saloes sa on sa.id = a.salao_id
   where a.id = p_ids[1];

  -- As outras semanas: a confirmação e o aviso de "novo" saem da fila. O
  -- lembrete da véspera fica. Cancelado, e não apagado: a chave continua
  -- ocupada, e um gatilho que rode de novo não recria a mensagem.
  update public.notificacoes
     set status = 'cancelado', motivo = 'pacote: uma mensagem só, com todas as datas'
   where agendamento_id = any(p_ids[2:])
     and tipo in ('confirmacao', 'novo') and status = 'pendente';

  /* Com o modelo do pacote ligado (45, `agenda_do_pacote`), a cliente recebe
     a LISTA: cada data, a hora e o que ela faz naquele dia ("ter 04/11 às
     14:00 (Mão)"). Aí a confirmação da primeira também sai — é a lista que
     confirma. Desligado, segue o jeito de antes: a confirmação de sempre,
     com as datas juntas. */
  /* Reservadas esperando o pagamento (pendentes): a cliente ainda não
     recebe nada — nem a lista. Quem atende recebe o aviso de sempre (abaixo).
     Pago, o `receber_pacote` chama esta função de novo, já confirmadas. */
  if exists (select 1 from public.agendamentos a where a.id = p_ids[1] and a.status = 'pendente') then
    null;
  elsif public.agenda_do_pacote(p_ids, p_pacote) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'pacote: a lista de horários vai numa mensagem só'
     where agendamento_id = p_ids[1] and tipo = 'confirmacao' and status = 'pendente';
  else
    -- A primeira leva todas. Confirmação: {{2}} data, {{3}} hora, {{4}} serviço.
    update public.notificacoes
       set variaveis = jsonb_set(jsonb_set(jsonb_set(variaveis,
                         '{1}', to_jsonb(v_datas)), '{2}', to_jsonb(v_hora)), '{3}', to_jsonb(v_serv)),
           corpo = replace(replace(corpo, v_data1, d->>'datas'), v_serv1, 'pacote ' || p_pacote)
     where agendamento_id = p_ids[1] and tipo = 'confirmacao' and status = 'pendente'
       and jsonb_typeof(variaveis) = 'array' and jsonb_array_length(variaveis) >= 4;
  end if;
  -- Aviso de "novo" para quem atende: {{3}} serviço, {{4}} data, {{5}} hora.
  update public.notificacoes
     set variaveis = jsonb_set(jsonb_set(jsonb_set(variaveis,
                       '{2}', to_jsonb(v_serv)), '{3}', to_jsonb(v_datas)), '{4}', to_jsonb(v_hora)),
         corpo = replace(replace(corpo, v_data1, d->>'datas'), v_serv1, 'pacote ' || p_pacote)
   where agendamento_id = p_ids[1] and tipo = 'novo' and status = 'pendente'
     and jsonb_typeof(variaveis) = 'array' and jsonb_array_length(variaveis) >= 5;
end $$;

-- ---------------------------------------------------------------------------
-- 4) MONTAR O PACOTE
--
-- p_semanas: [{ "inicio": "2026-11-04T14:00:00-03:00", "servicos": [uuid…] }, …]
-- Vazio: só vincula (o jeito de antes), com o pagamento.
-- p_forma nula: o pacote fica "a receber" pelo p_valor. Com forma: já pago.
-- ---------------------------------------------------------------------------
create or replace function public.montar_pacote(
  p_pacote uuid, p_cliente uuid, p_valor numeric default null, p_forma text default null,
  p_profissional uuid default null, p_semanas jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_pac public.pacotes%rowtype;
  v_fuso text; v_n int; i int; w jsonb;
  v_ini timestamptz; v_fim timestamptz; v_servs uuid[]; v_motivo text;
  v_inis timestamptz[] := '{}'; v_fins timestamptz[] := '{}';
  v_semanas jsonb := '[]'::jsonb; v_problema boolean := false;
  v_primeiro date; v_vence date; v_dia date;
  v_pc uuid; v_ag uuid; v_ids uuid[] := '{}'; v_ordem int; s record;
  v_reserva boolean;
begin
  select * into v_pac from public.pacotes p where p.id = p_pacote and p.ativo;
  if v_pac.id is null then
    raise exception 'Pacote não encontrado ou desativado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(v_pac.salao_id) then
    raise exception 'Só o balcão e a gestão vinculam cliente ao pacote.'
      using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(v_pac.salao_id, 'pacotes', 'Vender pacote');
  if not exists (select 1 from public.clientes c
                  where c.id = p_cliente and c.salao_id = v_pac.salao_id) then
    raise exception 'Esta cliente não é deste salão.' using errcode = 'check_violation';
  end if;
  if p_valor is not null and p_valor < 0 then
    raise exception 'O valor do pacote não pode ser negativo.' using errcode = 'check_violation';
  end if;
  if p_forma is not null and coalesce(p_valor, 0) <= 0 then
    raise exception 'Diga quanto ela pagou.' using errcode = 'check_violation';
  end if;

  p_semanas := coalesce(p_semanas, '[]'::jsonb);
  -- A lista vazia às vezes chega como `{}` (array vazio convertido no
  -- caminho): é "nenhuma semana", e não formato errado.
  if p_semanas = '{}'::jsonb then p_semanas := '[]'::jsonb; end if;
  if jsonb_typeof(p_semanas) <> 'array' then
    raise exception 'As semanas vieram num formato que não entendo.' using errcode = 'check_violation';
  end if;
  v_n := jsonb_array_length(p_semanas);
  if v_n > v_pac.sessoes then
    raise exception 'O pacote tem % sessões, e você marcou % semanas.', v_pac.sessoes, v_n
      using errcode = 'check_violation';
  end if;
  select coalesce(sa.fuso, 'America/Sao_Paulo') into v_fuso
    from public.saloes sa where sa.id = v_pac.salao_id;

  if v_n > 0 then
    if not exists (select 1 from public.profissionais pr
                    where pr.id = p_profissional and pr.salao_id = v_pac.salao_id and pr.ativo) then
      raise exception 'Escolha quem vai atender.' using errcode = 'check_violation';
    end if;
    -- A validade conta da PRIMEIRA sessão: o pacote que começa daqui a dez
    -- dias não pode perder a última terça por ter sido montado hoje.
    begin
      select min(((x->>'inicio')::timestamptz at time zone v_fuso)::date) into v_primeiro
        from jsonb_array_elements(p_semanas) x;
    exception when others then
      raise exception 'Uma das datas veio num formato que não entendo.' using errcode = 'check_violation';
    end;
    v_vence := v_primeiro + v_pac.validade_dias;

    for i in 0 .. v_n - 1 loop
      w := p_semanas->i;
      v_ini := (w->>'inicio')::timestamptz;
      v_servs := coalesce(array(select x::uuid from jsonb_array_elements_text(
                   case when jsonb_typeof(w->'servicos') = 'array' then w->'servicos' else '[]'::jsonb end) x),
                 '{}');
      v_dia := (v_ini at time zone v_fuso)::date;
      v_fim := null;
      v_motivo := case
        when cardinality(v_servs) = 0 then 'Escolha o que ela faz nesta semana.'
        when exists (select 1 from unnest(v_servs) sv(id)
                      where not exists (select 1 from public.pacote_servicos ps
                                         where ps.pacote_id = p_pacote and ps.servico_id = sv.id))
          then 'Um dos serviços desta semana não está no pacote.'
        when v_ini <= now() then 'Esta data já passou.'
        when not (extract(dow from v_dia)::smallint = any(v_pac.dias))
          then 'O pacote vale só ' || public.dias_por_extenso(v_pac.dias) || '.'
        when v_dia > v_vence
          then 'Passa da validade do pacote (vence em ' || to_char(v_vence, 'DD/MM') || ').'
      end;
      if v_motivo is null then
        v_fim := v_ini + make_interval(mins => public.duracao_dos_servicos(p_profissional, v_servs));
        v_motivo := public.porque_nao_cabe(p_profissional, v_ini, v_fim, null);
      end if;
      if v_motivo is null and exists (
           select 1 from unnest(v_inis, v_fins) as o(ini, fim)
            where o.ini < v_fim and v_ini < o.fim) then
        v_motivo := 'Bate com outra semana deste mesmo pacote.';
      end if;
      v_inis := v_inis || v_ini;
      v_fins := v_fins || coalesce(v_fim, v_ini);
      v_problema := v_problema or v_motivo is not null;
      v_semanas := v_semanas || jsonb_build_object('semana', i + 1, 'ok', v_motivo is null,
                                                   'motivo', v_motivo);
    end loop;

    if v_problema then
      return jsonb_build_object('ok', false, 'semanas', v_semanas);
    end if;
  else
    v_vence := public.hoje_no_salao(v_pac.salao_id) + v_pac.validade_dias;
  end if;

  /* A receber (valor combinado, sem forma): as semanas nascem RESERVADAS —
     pendentes, guardando o horário, sem confirmação para a cliente. Viram
     confirmadas quando o salão registra o pagamento (`receber_pacote`). */
  v_reserva := p_forma is null and coalesce(p_valor, 0) > 0;

  insert into public.pacote_clientes (pacote_id, cliente_id, sessoes, vence_em, valor)
       values (p_pacote, p_cliente, v_pac.sessoes, v_vence, nullif(round(coalesce(p_valor, 0), 2), 0))
    returning id into v_pc;

  -- Pago na hora: recebe ANTES de marcar as sessões. A mensagem de cada
  -- sessão nasce no insert dela e já sai sabendo que está pago (e não "a
  -- combinar"), e o lembrete de pagamento (45) nem chega a nascer.
  if p_forma is not null then
    perform public.receber_pacote(v_pc, p_forma, p_valor);
  end if;

  for i in 0 .. v_n - 1 loop
    w := p_semanas->i;
    v_servs := array(select x::uuid from jsonb_array_elements_text(w->'servicos') x);
    begin
      insert into public.agendamentos
        (salao_id, cliente_id, profissional_id, inicio, fim, status, origem,
         valor_previsto, criado_por, pacote_cliente_id)
      values (v_pac.salao_id, p_cliente, p_profissional, v_inis[i + 1], v_fins[i + 1],
              case when v_reserva then 'pendente' else 'confirmado' end, 'recepcao', 0, auth.uid(), v_pc)
      returning id into v_ag;
    exception when exclusion_violation then
      raise exception 'Alguém acabou de marcar no horário da semana %. Confira e tente de novo.', i + 1
        using errcode = 'check_violation';
    end;
    v_ordem := 1;
    -- Como o `agendar()` (09): a duração com o intervalo, o preço pela
    -- escada (o gatilho preenche) e a comissão do cadastro.
    for s in
      select sv.id, coalesce(sp.duracao_min, sv.duracao_min) + sv.intervalo_min as dur,
             coalesce(sv.comissao_pct, pr.comissao_pct, 0) as com
        from unnest(v_servs) with ordinality as pedido(id, pos)
        join public.servicos sv on sv.id = pedido.id
        join public.profissionais pr on pr.id = p_profissional
        left join public.servicos_profissionais sp
               on sp.servico_id = sv.id and sp.profissional_id = p_profissional
       order by pedido.pos
    loop
      insert into public.agendamento_servicos
        (agendamento_id, servico_id, ordem, duracao_min, preco, comissao_pct)
      values (v_ag, s.id, v_ordem, s.dur, null, s.com);
      v_ordem := v_ordem + 1;
    end loop;
    v_ids := v_ids || v_ag;
  end loop;

  perform public.juntar_mensagens_do_pacote(v_ids, v_pac.nome);

  return jsonb_build_object('ok', true, 'pacoteCliente', v_pc, 'agendamentos', to_jsonb(v_ids),
                            'venceEm', v_vence, 'reservadas', v_reserva and v_n > 0,
                            'datas', case when v_n > 0 then public.datas_do_pacote(v_ids) end);
end $$;

-- ---------------------------------------------------------------------------
-- 5) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.receber_pacote(uuid, text, numeric) from public, anon;
revoke all on function public.desfazer_recebimento_pacote(uuid) from public, anon;
revoke all on function public.montar_pacote(uuid, uuid, numeric, text, uuid, jsonb) from public, anon;
grant execute on function public.receber_pacote(uuid, text, numeric) to authenticated;
grant execute on function public.desfazer_recebimento_pacote(uuid) to authenticated;
grant execute on function public.montar_pacote(uuid, uuid, numeric, text, uuid, jsonb) to authenticated;
-- As peças de dentro não são de ninguém.
revoke all on function public.datas_do_pacote(uuid[]) from public, anon, authenticated;
revoke all on function public.refazer_textos_do_pacote(uuid) from public, anon, authenticated;
revoke all on function public.juntar_mensagens_do_pacote(uuid[], text) from public, anon, authenticated;

-- ###########################################################################
-- ## 44_pacote_comissao.sql
-- ###########################################################################

-- ===========================================================================
-- 44_pacote_comissao.sql — a comissão da sessão de pacote
--
-- O pedido: "o pacote, e aí quem é o profissional, e aí a definição da
-- comissão?" Até aqui a sessão de pacote não gerava comissão nenhuma: ela
-- sai a R$ 0,00 (a cliente pagou adiantado) e não vira comanda (28), e a
-- venda do pacote vira comanda SEM profissional (43). Quem atendia a Maria
-- toda terça trabalhava o mês inteiro sem comissão.
--
-- ── AS DUAS DECISÕES DO DONO ──────────────────────────────────────────────
-- 1. PROPORCIONAL. O valor do pacote é repartido pelo preço cheio de cada
--    sessão: pacote de R$ 220 com mão (R$ 40), mão e pé (R$ 90), mão, mão e
--    pé — o cheio somaria R$ 260, então cada real cheio vale R$ 220/260. A
--    semana de mão vale R$ 33,85, a de mão e pé R$ 76,15. Quem faz mais,
--    ganha mais; e a soma nunca passa do que a cliente pagou.
-- 2. AO ATENDER. A comissão conta no dia em que a sessão é concluída, mesmo
--    com o pacote ainda a receber: a profissional trabalhou, e cobrar a
--    cliente é com o salão.
--
-- ── QUEM GANHA ────────────────────────────────────────────────────────────
-- Quem ATENDEU aquela sessão (`profissional_id` do horário), e não quem foi
-- escolhida ao montar o pacote: a terça em que a Ju faltou e a Bia atendeu é
-- da Bia. A taxa é a mesma escada de sempre (`comissao_de`, 16): o par
-- serviço+profissional, o serviço, a profissional — porcentagem sobre a
-- parte da sessão, mais o valor fixo por serviço.
--
-- ── O VALOR DA SESSÃO, QUANDO NEM TODAS ESTÃO MARCADAS ────────────────────
-- Na agenda fixa, as quatro terças existem desde o primeiro dia e a conta é
-- exata. No pacote que a cliente vai marcando pelo link, as sessões que
-- ainda não existem entram pela média do preço cheio das que já existem. A
-- comissão de cada sessão é CONGELADA no dia em que ela é atendida (como a
-- taxa do item da comanda, no 16): o mês fechado não muda depois.
--
-- ── ONDE APARECE ──────────────────────────────────────────────────────────
-- No relatório do período (`relatorio`, 12), junto da comissão das comandas,
-- por profissional; e no total de comissões do painel do dia (18). Não é
-- faturamento: o dinheiro do pacote já entrou uma vez, na venda (43).
-- ===========================================================================

create table if not exists public.pacote_comissoes (
  id                uuid primary key default gen_random_uuid(),
  salao_id          uuid not null references public.saloes(id) on delete cascade,
  agendamento_id    uuid not null references public.agendamentos(id) on delete cascade,
  pacote_cliente_id uuid references public.pacote_clientes(id) on delete set null,
  profissional_id   uuid references public.profissionais(id) on delete set null,
  base              numeric(10,2) not null check (base >= 0),
  comissao          numeric(10,2) not null check (comissao >= 0),
  atendida_em       timestamptz not null default now()
);
create unique index if not exists ux_pacote_comissao_agend on public.pacote_comissoes(agendamento_id);
create index if not exists ix_pacote_comissao_salao on public.pacote_comissoes(salao_id, atendida_em);

-- ---------------------------------------------------------------------------
-- 1) A PARTE DA SESSÃO NO VALOR DO PACOTE
--
-- O fator é "quanto vale cada real de preço cheio": o valor do pacote sobre
-- o preço cheio de todas as sessões dele (as que gastam sessão, como no 27).
-- Nunca passa de 1 — a sessão não vale mais que o preço cheio.
-- ---------------------------------------------------------------------------
create or replace function public.fator_do_pacote(p_pacote_cliente uuid)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare v_valor numeric; v_sessoes int; v_soma numeric; v_n int; v_den numeric;
begin
  select coalesce(nullif(pc.valor, 0), p.preco, 0), pc.sessoes
    into v_valor, v_sessoes
    from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
   where pc.id = p_pacote_cliente;
  if coalesce(v_valor, 0) <= 0 then return 0; end if;

  select coalesce(sum(x.cheio), 0), count(*) into v_soma, v_n
    from (select a.id, coalesce(sum(s.preco), 0) as cheio
            from public.agendamentos a
            join public.agendamento_servicos s on s.agendamento_id = a.id
           where a.pacote_cliente_id = p_pacote_cliente
             and a.status in ('pendente', 'confirmado', 'em_atendimento', 'concluido')
           group by a.id) x;
  if v_n = 0 or v_soma <= 0 then return 0; end if;

  -- As sessões que ainda não existem entram pela média das que existem.
  v_den := v_soma + greatest(coalesce(v_sessoes, 0) - v_n, 0) * (v_soma / v_n);
  return least(1, v_valor / v_den);
end $$;

-- ---------------------------------------------------------------------------
-- 2) O GATILHO: CONCLUIU, CONGELA; DESFEZ, SAI
-- ---------------------------------------------------------------------------
create or replace function public.tg_pacote_comissao()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_fator numeric; v_base numeric := 0; v_com numeric := 0; s record; t record;
begin
  -- Desfazer: a recepção concluiu por engano e voltou atrás.
  if tg_op = 'UPDATE' and old.status = 'concluido' and new.status <> 'concluido' then
    delete from public.pacote_comissoes where agendamento_id = new.id;
    return new;
  end if;
  if new.status <> 'concluido' or new.pacote_cliente_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'concluido' then return new; end if;
  -- Quem abriu comanda para a sessão já tem a comissão no item dela.
  if exists (select 1 from public.comandas c where c.agendamento_id = new.id) then
    return new;
  end if;

  v_fator := public.fator_do_pacote(new.pacote_cliente_id);
  for s in select asv.servico_id, coalesce(asv.preco, 0) as preco
             from public.agendamento_servicos asv where asv.agendamento_id = new.id loop
    t := public.comissao_de('servico', s.servico_id, null, new.profissional_id);
    v_base := v_base + s.preco * v_fator;
    v_com := v_com + s.preco * v_fator * coalesce(t.pct, 0) / 100 + coalesce(t.fixa, 0);
  end loop;
  -- Arredonda UMA vez, na sessão: por serviço, as quatro terças de R$ 220
  -- somariam R$ 220,02.
  v_base := round(v_base, 2);
  v_com := round(v_com, 2);

  insert into public.pacote_comissoes
    (salao_id, agendamento_id, pacote_cliente_id, profissional_id, base, comissao)
  values (new.salao_id, new.id, new.pacote_cliente_id, new.profissional_id, v_base, v_com)
  on conflict (agendamento_id) do update
    set profissional_id = excluded.profissional_id, base = excluded.base,
        comissao = excluded.comissao, atendida_em = now();
  return new;
end $$;

drop trigger if exists tg_pacote_comissao on public.agendamentos;
create trigger tg_pacote_comissao
  after insert or update of status on public.agendamentos
  for each row execute function public.tg_pacote_comissao();

-- ---------------------------------------------------------------------------
-- 3) QUEM LÊ
--
-- Comissão é dinheiro da casa: a gestão lê, como o relatório (12). Ninguém
-- escreve pela API — só o gatilho.
-- ---------------------------------------------------------------------------
alter table public.pacote_comissoes enable row level security;
drop policy if exists pacote_comissoes_ler on public.pacote_comissoes;
create policy pacote_comissoes_ler on public.pacote_comissoes
  for select to authenticated using (public.e_gestor(salao_id));
grant select on public.pacote_comissoes to authenticated;
revoke insert, update, delete on public.pacote_comissoes from authenticated;
revoke all on public.pacote_comissoes from anon;
revoke all on function public.fator_do_pacote(uuid) from public, anon, authenticated;
revoke all on function public.tg_pacote_comissao() from public, anon, authenticated;

-- ###########################################################################
-- ## 45_pacote_mensagens.sql
-- ###########################################################################

-- ===========================================================================
-- 45_pacote_mensagens.sql — as duas mensagens do pacote
--
-- O pedido: depois do pacote com agenda fixa (43), "sim" para as duas
-- mensagens automáticas que faltavam:
--
--   · ÚLTIMA SESSÃO (era "renovação"): seis dias antes da última sessão, às
--     10h do salão, a cliente recebe "Informação sobre o seu pacote: última
--     sessão incluída terça, 01/12 às 14:00". Só quando todas as sessões
--     estão na agenda (antes disso, "a última" não é a última). Renovou
--     antes? O aviso do pacote anterior sai da fila. Sem convite para
--     renovar: com ele, a Meta aprovou o modelo como Marketing.
--   · PAGAMENTO: existiu (véspera da primeira sessão, para quem estava "a
--     receber") e saiu: o pacote a receber fica reservado até o "Recebi", e
--     aí a cliente recebe a lista de horários. Não há o que lembrar antes.
--
-- ── ⚠ SÓ SAEM COM OS MODELOS APROVADOS NA META ────────────────────────────
-- O número que manda é o do AgendaPro, e ele só manda modelo aprovado. Os
-- dois são novos (MODELOS.md): até a plataforma cadastrar, ver aprovados e
-- ligar no admin, NADA é posto na fila — e não um monte de mensagens para um
-- modelo que não existe (132001), que contariam como falha e sujariam o
-- histórico. O mesmo cuidado da forma de pagamento nas mensagens (21).
--
-- ── E O SALÃO ESCOLHE ─────────────────────────────────────────────────────
-- Em Notificações, uma chave para cada (`notifPacoteRenova`,
-- `notifPacotePaga`), ligadas por padrão: é aviso sobre o que a cliente já
-- comprou. Contam na franquia de mensagens como a confirmação.
--
-- ── A FILA ACOMPANHA O PACOTE ─────────────────────────────────────────────
-- A mensagem nasce semanas antes de sair, e muita coisa muda no caminho: a
-- terça vira quarta, a última sessão é cancelada, o pacote é pago, renovado,
-- cancelado. Em vez de cada lugar lembrar de mexer na fila, UMA função diz o
-- que deve estar lá (`avisos_do_pacote`) e os gatilhos a chamam sempre que
-- uma dessas coisas muda. A mensagem que já saiu nunca é tocada.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O INTERRUPTOR DA PLATAFORMA
-- ---------------------------------------------------------------------------
create or replace function public.mensagens_do_pacote()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                    where a.chave = 'mensagensPacote'), false)
$$;

-- ---------------------------------------------------------------------------
-- 2) GRAVAR UMA NA FILA (OU TIRAR)
--
-- p_motivo preenchido: ela não deve sair, e o que estava pendente é
-- cancelado com esse motivo. Vazio: ela deve sair em p_quando.
--
-- ⚠ EM CIMA DA HORA. Nova mensagem só nasce com folga (p_folga). A que já
-- estava na fila e ficou sem folga — o worker atrasou, a sessão mudou —
-- continua, com o texto refeito, se ainda chega antes da sessão (p_alvo);
-- se a sessão passou para antes dela, sai da fila.
--
-- ⚠ CANCELADA VOLTA. A chave é única: cancelada pela sessão que caiu, a
-- mensagem volta à fila apontando para a sessão nova, em vez de uma segunda
-- linha. Só volta o que nunca saiu (pendente ou cancelado).
-- ---------------------------------------------------------------------------
create or replace function public.gravar_aviso_do_pacote(
  p_salao uuid, p_tipo text, p_chave text, p_motivo text,
  p_quando timestamptz, p_folga interval, p_alvo timestamptz,
  p_destino text, p_cliente uuid, p_agendamento uuid, p_corpo text, p_variaveis jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v public.notificacoes%rowtype;
begin
  select * into v from public.notificacoes n where n.salao_id = p_salao and n.chave = p_chave;
  if p_motivo is not null then
    update public.notificacoes set status = 'cancelado', motivo = p_motivo
     where id = v.id and status = 'pendente';
    return;
  end if;
  if v.id is not null and v.status not in ('pendente', 'cancelado') then return; end if;

  if p_quando > now() + p_folga then
    if v.id is null then
      insert into public.notificacoes
        (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave, modelo, variaveis)
      values (p_salao, p_tipo, p_destino, p_cliente, p_agendamento, p_quando, p_corpo, p_chave,
              public.modelo_de(p_tipo), p_variaveis)
      on conflict (salao_id, chave) do nothing;
    else
      update public.notificacoes
         set status = 'pendente', motivo = null, quando = p_quando, destino = p_destino,
             agendamento_id = p_agendamento, corpo = p_corpo, variaveis = p_variaveis,
             modelo = public.modelo_de(p_tipo), tentativas = 0, proxima_em = null,
             erro_codigo = null, erro_msg = null
       where id = v.id;
    end if;
  elsif v.status = 'pendente' then
    if v.quando < p_alvo then
      update public.notificacoes
         set destino = p_destino, agendamento_id = p_agendamento, corpo = p_corpo,
             variaveis = p_variaveis
       where id = v.id;
    else
      update public.notificacoes
         set status = 'cancelado', motivo = 'a sessão passou para antes do aviso'
       where id = v.id;
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3) O QUE DEVE ESTAR NA FILA, PARA UM PACOTE DA CLIENTE
-- ---------------------------------------------------------------------------
create or replace function public.avisos_do_pacote(p_pacote_cliente uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record; v_tel text; v_fuso text; v_prim record; v_ult record; v_quando timestamptz;
  v_nome text; v_quando_txt text; v_motivo text; v_comum text;
  v_dias text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
begin
  select pc.id, pc.cliente_id, pc.pacote_id, pc.valor, pc.pago_em, pc.cancelado_em, pc.criado_em,
         p.nome as pacote, p.salao_id, sa.nome as casa, coalesce(sa.fuso, 'America/Sao_Paulo') as fuso,
         sa.cfg, c.nome as cliente, c.telefone
    into r
    from public.pacote_clientes pc
    join public.pacotes p on p.id = pc.pacote_id
    join public.saloes sa on sa.id = p.salao_id
    join public.clientes c on c.id = pc.cliente_id
   where pc.id = p_pacote_cliente;
  if r.id is null then return; end if;
  v_fuso := r.fuso;
  v_tel := public.so_digitos(r.telefone);

  -- Renovou: o aviso de renovação do pacote anterior (o mesmo pacote, desta
  -- cliente) não sai mais.
  if r.cancelado_em is null then
    update public.notificacoes n
       set status = 'cancelado', motivo = 'pacote renovado'
     where n.salao_id = r.salao_id and n.tipo = 'pacote_renovar' and n.status = 'pendente'
       and n.chave in (select 'pacote_renovar:' || x.id from public.pacote_clientes x
                        where x.cliente_id = r.cliente_id and x.pacote_id = r.pacote_id
                          and x.id <> r.id and x.criado_em < r.criado_em);
  end if;

  -- A primeira e a última sessão vivas (as mesmas que gastam sessão, no 27).
  select a.id, a.inicio, a.status into v_prim from public.agendamentos a
   where a.pacote_cliente_id = r.id and a.arquivado_em is null
     and a.status in ('pendente', 'confirmado', 'em_atendimento', 'concluido')
   order by a.inicio limit 1;
  select a.id, a.inicio, a.status into v_ult from public.agendamentos a
   where a.pacote_cliente_id = r.id and a.arquivado_em is null
     and a.status in ('pendente', 'confirmado', 'em_atendimento', 'concluido')
   order by a.inicio desc limit 1;

  -- O que vale para as duas.
  v_comum := case
    when r.cancelado_em is not null then 'pacote cancelado'
    when not public.mensagens_do_pacote() then 'mensagens do pacote desligadas'
    when coalesce(v_tel, '') = '' then 'cliente sem telefone'
    when v_prim.id is null then 'pacote sem sessão marcada'
  end;
  v_nome := public.variavel_limpa(split_part(btrim(coalesce(r.cliente, 'cliente')), ' ', 1));

  -- RENOVAÇÃO: seis dias antes da última, às 10h do salão.
  if v_comum is null then
    v_quando := ((((v_ult.inicio at time zone v_fuso)::date - 6) + time '10:00') at time zone v_fuso);
    v_quando_txt := v_dias[extract(dow from (v_ult.inicio at time zone v_fuso))::int + 1]
                    || ', ' || to_char(v_ult.inicio at time zone v_fuso, 'DD/MM "às" HH24:MI');
  end if;
  v_motivo := coalesce(v_comum, case
    when not public.notif_liga(r.salao_id, 'notifPacoteRenova', true) then 'desligado pelo salão'
    when exists (select 1 from public.pacote_clientes y
                  where y.cliente_id = r.cliente_id and y.pacote_id = r.pacote_id
                    and y.id <> r.id and y.cancelado_em is null and y.criado_em > r.criado_em)
      then 'pacote renovado'
    when public.pacote_sessoes_restantes(r.id) > 0 then 'ainda há sessão para marcar'
    when v_ult.status not in ('pendente', 'confirmado') then 'a última sessão já foi'
    -- Pacote curto (tudo numa semana): o aviso cairia antes de ele começar.
    when v_quando <= v_prim.inicio then 'pacote curto demais para o aviso'
  end);
  /* "Combine a renovação com o salão" fez a Meta aprovar o modelo como
     MARKETING (custa umas 8 vezes mais e é segurado para quem nunca falou com
     o número). Agora é só a informação — a última sessão e onde — com outro
     nome de modelo (`agendapro_pacote_ultima_sessao`, no modelo_de do 37). */
  perform public.gravar_aviso_do_pacote(r.salao_id, 'pacote_renovar', 'pacote_renovar:' || r.id,
    v_motivo, v_quando, interval '0', v_ult.inicio, v_tel, r.cliente_id, v_ult.id,
    'Olá, ' || v_nome || '. Informação sobre o seu pacote ' || r.pacote || '.'
      || E'\n\n📅 Última sessão incluída: ' || v_quando_txt
      || E'\n🏪 Local: ' || r.casa
      || E'\n\nDepois dessa sessão, o pacote se encerra. Aviso automático do sistema de agendamento.',
    jsonb_build_array(v_nome, public.variavel_limpa(r.pacote),
                      public.variavel_limpa(v_quando_txt), public.variavel_limpa(r.casa)));

  /* PAGAMENTO: não sai mais. "O pacote só é confirmado com o pagamento" —
     as sessões ficam reservadas até o salão tocar em "Recebi" (43), e aí a
     cliente recebe a lista de horários. Um lembrete de pagar antes disso
     sobrava. A chamada fica só para tirar da fila o que estivesse pendente;
     o painel continua mostrando "a receber" para o salão. */
  perform public.gravar_aviso_do_pacote(r.salao_id, 'pacote_pagamento', 'pacote_pagamento:' || r.id,
    'sem lembrete de pagamento: o pacote confirma quando o salão registra o pagamento',
    null, interval '1 hour', v_prim.inicio, v_tel, r.cliente_id, v_prim.id, null, null);
end $$;

/* Os pacotes de um salão (ou de todos) que ainda têm sessão pela frente:
   ligou ou desligou a chave, a fila de todos eles é refeita. */
create or replace function public.refazer_avisos_de_pacote(p_salao uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare x record; v_n int := 0;
begin
  for x in
    select pc.id from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
     where (p_salao is null or p.salao_id = p_salao) and pc.cancelado_em is null
       and exists (select 1 from public.agendamentos a
                    where a.pacote_cliente_id = pc.id and a.inicio > now()
                      and a.status in ('pendente', 'confirmado'))
  loop
    perform public.avisos_do_pacote(x.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

/* ── A LISTA DE HORÁRIOS, NUMA MENSAGEM SÓ ─────────────────────────────
   "E a lista de todos os horários e procedimentos do pacote?" Ao montar o
   pacote com agenda fixa (43), a cliente recebe cada data, a hora e o que
   faz naquele dia: "ter 04/11 às 14:00 (Mão); ter 11/11 às 14:00 (Mão +
   Pé)". Numa linha só, porque variável de modelo não aceita quebra de
   linha. É a confirmação do pacote: sai com a chave da confirmação ligada,
   e no lugar dela. Devolve se pôs na fila. */
create or replace function public.agenda_do_pacote(p_ids uuid[], p_pacote text)
returns boolean language plpgsql security definer set search_path = public as $$
declare r record; v_tel text; v_lista text; v_nome text;
  v_dias text[] := array['dom','seg','ter','qua','qui','sex','sáb'];
begin
  if cardinality(p_ids) < 2 or not public.mensagens_do_pacote() then return false; end if;
  select a.salao_id, a.cliente_id, a.pacote_cliente_id, c.nome as cliente, c.telefone,
         sa.nome as casa, coalesce(sa.fuso, 'America/Sao_Paulo') as fuso,
         coalesce(pr.apelido, pr.nome, '—') as prof
    into r
    from public.agendamentos a
    join public.clientes c on c.id = a.cliente_id
    join public.saloes sa on sa.id = a.salao_id
    left join public.profissionais pr on pr.id = a.profissional_id
   where a.id = p_ids[1];
  if r.salao_id is null or r.pacote_cliente_id is null
     or not public.notif_liga(r.salao_id, 'notifConfirma', true) then
    return false;
  end if;
  v_tel := public.so_digitos(r.telefone);
  if coalesce(v_tel, '') = '' then return false; end if;
  v_nome := public.variavel_limpa(split_part(btrim(coalesce(r.cliente, 'cliente')), ' ', 1));
  select string_agg(v_dias[extract(dow from (a.inicio at time zone r.fuso))::int + 1] || ' '
           || to_char(a.inicio at time zone r.fuso, 'DD/MM "às" HH24:MI')
           || ' (' || coalesce((select string_agg(sv.nome, ' + ' order by asv.ordem)
                                  from public.agendamento_servicos asv
                                  join public.servicos sv on sv.id = asv.servico_id
                                 where asv.agendamento_id = a.id), 'atendimento') || ')',
           '; ' order by a.inicio)
    into v_lista
    from public.agendamentos a where a.id = any(p_ids);

  insert into public.notificacoes
    (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave, modelo, variaveis)
  values (r.salao_id, 'pacote_agenda', v_tel, r.cliente_id, p_ids[1], now(),
          /* Sem o nome da profissional: "vai que no pacote muda o
             profissional". No lugar, o salão (Local) — e ele sai da
             primeira linha para não aparecer duas vezes. */
          'Olá, ' || v_nome || '. Seu pacote ' || p_pacote
            || ' está com os horários marcados.'
            || E'\n\n📅 Horários: ' || v_lista
            || E'\n🏪 Local: ' || r.casa
            || E'\n\nVocê recebe um lembrete antes de cada sessão. Aviso automático do sistema de agendamento.',
          'pacote_agenda:' || r.pacote_cliente_id, public.modelo_de('pacote_agenda'),
          jsonb_build_array(v_nome, public.variavel_limpa(p_pacote),
                            public.variavel_limpa(v_lista), public.variavel_limpa(r.casa)))
  on conflict (salao_id, chave) do nothing;
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 4) QUEM CHAMA: OS GATILHOS
-- ---------------------------------------------------------------------------
/* A sessão nasceu, mudou de hora, foi cancelada, atendida, arquivada ou
   trocou de pacote. ⚠ O nome vem depois de `tg_notif_agenda_mudou` na ordem
   alfabética, e é de propósito: o Postgres roda os gatilhos do mesmo evento
   nessa ordem, e aquele cancela o que aponta para a sessão cancelada — este,
   depois, devolve a mensagem à fila apontando para a sessão que sobrou. */
create or replace function public.tg_pacote_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.pacote_cliente_id is not null then
    perform public.avisos_do_pacote(new.pacote_cliente_id);
  end if;
  if tg_op = 'UPDATE' and old.pacote_cliente_id is not null
     and old.pacote_cliente_id is distinct from new.pacote_cliente_id then
    perform public.avisos_do_pacote(old.pacote_cliente_id);
  end if;
  return new;
end $$;

drop trigger if exists tg_pacote_avisos on public.agendamentos;
create trigger tg_pacote_avisos
  after insert or update of inicio, status, arquivado_em, pacote_cliente_id on public.agendamentos
  for each row execute function public.tg_pacote_avisos();

-- Pagou, desfez o pagamento, mudou o valor, cancelou o pacote.
create or replace function public.tg_pacote_cliente_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.avisos_do_pacote(new.id);
  return new;
end $$;

drop trigger if exists tg_pacote_cliente_avisos on public.pacote_clientes;
create trigger tg_pacote_cliente_avisos
  after update of pago_em, valor, cancelado_em on public.pacote_clientes
  for each row execute function public.tg_pacote_cliente_avisos();

-- O salão ligou ou desligou uma das duas chaves em Notificações.
create or replace function public.tg_salao_avisos_de_pacote()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.cfg->'notifPacoteRenova') is distinct from (new.cfg->'notifPacoteRenova')
     or (old.cfg->'notifPacotePaga') is distinct from (new.cfg->'notifPacotePaga') then
    perform public.refazer_avisos_de_pacote(new.id);
  end if;
  return new;
end $$;

drop trigger if exists tg_salao_avisos_de_pacote on public.saloes;
create trigger tg_salao_avisos_de_pacote
  after update of cfg on public.saloes
  for each row execute function public.tg_salao_avisos_de_pacote();

-- ---------------------------------------------------------------------------
-- 5) A PLATAFORMA LIGA (DEPOIS DE VER OS MODELOS APROVADOS)
-- ---------------------------------------------------------------------------
create or replace function public.definir_mensagens_do_pacote(p_ligar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma liga os modelos de mensagem.'
      using errcode = 'insufficient_privilege';
  end if;
  insert into public.plataforma_ajustes (chave, valor, atualizado_em)
       values ('mensagensPacote', to_jsonb(coalesce(p_ligar, false)), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  -- Desligou: o que estava na fila sai, de todos os salões.
  if not coalesce(p_ligar, false) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'mensagens do pacote desligadas'
     where tipo in ('pacote_renovar', 'pacote_pagamento', 'pacote_agenda') and status = 'pendente';
  end if;
  -- Ligou: os pacotes que já estão na agenda ganham as mensagens deles.
  v_n := public.refazer_avisos_de_pacote(null);
  return jsonb_build_object('ligado', public.mensagens_do_pacote(), 'pacotes', v_n);
end $$;

-- Um sim ou não da plataforma, como o `mensagens_com_pagamento` (21): o
-- painel lê para dizer ao dono que as duas ainda não estão saindo.
revoke all on function public.mensagens_do_pacote() from public, anon;
grant execute on function public.mensagens_do_pacote() to authenticated;
revoke all on function public.gravar_aviso_do_pacote(uuid, text, text, text, timestamptz, interval,
  timestamptz, text, uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.avisos_do_pacote(uuid) from public, anon, authenticated;
revoke all on function public.agenda_do_pacote(uuid[], text) from public, anon, authenticated;
revoke all on function public.refazer_avisos_de_pacote(uuid) from public, anon, authenticated;
revoke all on function public.tg_pacote_avisos() from public, anon, authenticated;
revoke all on function public.tg_pacote_cliente_avisos() from public, anon, authenticated;
revoke all on function public.tg_salao_avisos_de_pacote() from public, anon, authenticated;
revoke all on function public.definir_mensagens_do_pacote(boolean) from public, anon;
grant execute on function public.definir_mensagens_do_pacote(boolean) to authenticated;

-- ###########################################################################
-- ## 46_adicionais.sql
-- ###########################################################################

-- ===========================================================================
-- 46_adicionais.sql — os módulos adicionais, que se pagam à parte
--
-- O pedido: o Crediário (venda parcelada, o "fiado") é um módulo a mais —
-- "preciso amarrar para cobrar do dono do salão". R$ 49,90 por mês, do
-- Essencial para cima (no Básico não), liberado no teste grátis.
--
-- Até aqui cada plano liberava os seus módulos e a mensalidade era o preço do
-- plano. Agora a mensalidade é PLANO + ADICIONAIS, e a trava de módulo
-- (`recurso_bool`, `exigir_recurso`) aceita "o plano inclui" OU "contratou o
-- adicional". O mesmo desenho serve para os próximos (cartão fidelidade,
-- ficha com fotos…): é uma linha no catálogo.
--
-- ── AS REGRAS DO DONO ─────────────────────────────────────────────────────
--   · contratou com a assinatura em dia, num plano que aceita: LIBERA NA
--     HORA e entra na próxima mensalidade;
--   · inadimplente: "regularize a mensalidade primeiro";
--   · no Básico ou no teste: fica AGUARDANDO e entra junto com a mensalidade
--     de um plano que aceita ("Mudar para o Essencial + Crediário");
--   · cancelou: vale até o próximo vencimento (o mês já pago é dele); depois
--     as parcelas abertas continuam, só não se vende fiado novo — a regra de
--     quem desce de plano;
--   · recontratar depois de vencido: só libera quando a mensalidade com ele
--     for paga (sem "usa um mês de graça, cancela e repete");
--   · a plataforma dá cortesia e preço especial.
--
-- ── ⚠ O VALOR NUNCA VEM DA TELA, E O CARTÃO TEM QUE SABER ─────────────────
-- Como o plano (13): o preço é lido daqui no servidor. E quem paga no cartão
-- tem o valor guardado no Mercado Pago — mudar o adicional muda o valor LÁ,
-- pela função de borda `adicional`, ANTES de gravar aqui (efeito externo
-- primeiro, como o `cancelar-cartao`). Por isso a mudança tem duas metades:
-- `preparar_adicional` (só conta, não grava) e `aplicar_adicional` (grava, e
-- confere que a conta não mudou no meio). As duas são só da borda.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O CATÁLOGO
-- ---------------------------------------------------------------------------
create table if not exists public.adicionais (
  codigo     text primary key,
  nome       text not null,
  descricao  text not null default '',
  preco_mes  numeric(10,2) not null check (preco_mes > 0),
  -- A chave de `recursos` que ele libera (a mesma que o `exigir_recurso` pede).
  recurso    text not null,
  -- Em quais planos ele pode ser contratado.
  planos     text[] not null default '{}',
  -- O que vem junto (as 200 mensagens próprias do Crediário, por exemplo).
  recursos   jsonb not null default '{}'::jsonb,
  ativo      boolean not null default true,
  ordem      smallint not null default 0
);

-- Preço e planos são decisão comercial: colar de novo não reseta. O nome e a
-- chave voltam sempre (como os planos, no 22).
--
-- ⚠ NASCE FORA DA VENDA (`ativo = false`). A cobrança vem antes das telas do
-- Crediário: com ele à venda agora, o dono contrataria — e pagaria — um
-- módulo que ainda não tem tela. Quem põe à venda é o módulo do Crediário em
-- si, quando as telas existirem; colar este de novo não tira da venda.
insert into public.adicionais (codigo, nome, descricao, preco_mes, recurso, planos, recursos, ativo, ordem)
values ('crediario', 'Crediário',
        'Venda parcelada no fiado, com as parcelas, o "a receber" e a cobrança no WhatsApp.',
        49.90, 'crediario', array['individual', 'duo', 'time', 'equipe', 'salao'],
        '{"mensagens_crediario": 200}'::jsonb, false, 1)
on conflict (codigo) do update
  set nome = excluded.nome, descricao = excluded.descricao, recurso = excluded.recurso;

/* OS PLANOS DO CREDIÁRIO. "200 mensagens é para uma loja menor — e a loja
   maior? Precisamos de diversos planos." O mesmo módulo (a mesma chave
   `crediario`), com mais mensagens por mês: 200 por R$ 49,90, 500 por
   R$ 79,90 e 1.000 por R$ 119,90. Trocar de um para o outro é TROCA — o
   novo assume e o de antes sai da mensalidade (`conta_do_adicional`), nunca
   os dois cobrados juntos. Nascem fora da venda, como o primeiro. */
insert into public.adicionais (codigo, nome, descricao, preco_mes, recurso, planos, recursos, ativo, ordem)
values ('crediario_500', 'Crediário 500',
        'O Crediário para a loja maior: as mesmas telas, com mais mensagens para as clientes.',
        79.90, 'crediario', array['individual', 'duo', 'time', 'equipe', 'salao'],
        '{"mensagens_crediario": 500}'::jsonb, false, 2),
       ('crediario_1000', 'Crediário 1.000',
        'O Crediário para quem vende muito no fiado: as mesmas telas, com mais mensagens para as clientes.',
        119.90, 'crediario', array['individual', 'duo', 'time', 'equipe', 'salao'],
        '{"mensagens_crediario": 1000}'::jsonb, false, 3)
on conflict (codigo) do update
  set nome = excluded.nome, descricao = excluded.descricao, recurso = excluded.recurso;

-- No teste grátis, o Crediário vem liberado: é para experimentar e querer.
update public.planos set recursos = recursos || '{"crediario": true}'::jsonb
 where codigo = 'trial';

-- O catálogo: quem está logado lê (o preço aparece no painel). Quem não
-- entrou não alcança tabela nenhuma (02_rls.test) — só `planos`, por decisão.
alter table public.adicionais enable row level security;
drop policy if exists adicionais_ler on public.adicionais;
create policy adicionais_ler on public.adicionais for select to authenticated using (true);
revoke all on public.adicionais from anon, authenticated;
grant select on public.adicionais to authenticated;

-- ---------------------------------------------------------------------------
-- 2) O QUE CADA SALÃO CONTRATOU
--
--   ativo       valendo (e entra na mensalidade, se não for cortesia)
--   aguardando  pedido, mas só vale quando a mensalidade com ele for paga
--   cancelado   saiu; vale até `vale_ate` (o mês que já estava pago)
-- ---------------------------------------------------------------------------
create table if not exists public.salao_adicionais (
  salao_id       uuid not null references public.saloes(id) on delete cascade,
  adicional      text not null references public.adicionais(codigo),
  status         text not null check (status in ('ativo', 'aguardando', 'cancelado')),
  desde          timestamptz not null default now(),
  ativo_desde    timestamptz,
  cancelado_em   timestamptz,
  vale_ate       date,
  -- A plataforma deu: vale sem entrar na mensalidade.
  cortesia       boolean not null default false,
  -- O preço deste salão (a plataforma decide). Nulo: o do catálogo.
  preco_especial numeric(10,2) check (preco_especial is null or preco_especial >= 0),
  -- Já teve e cancelou: recontratar só libera depois de pagar.
  ja_teve        boolean not null default false,
  atualizado_em  timestamptz not null default now(),
  primary key (salao_id, adicional)
);

-- Preço e estado são conta do dono: a gestão lê. Ninguém escreve pela API.
alter table public.salao_adicionais enable row level security;
drop policy if exists salao_adicionais_ler on public.salao_adicionais;
create policy salao_adicionais_ler on public.salao_adicionais
  for select to authenticated using (public.e_gestor(salao_id) or public.is_super());
revoke all on public.salao_adicionais from anon, authenticated;
grant select on public.salao_adicionais to authenticated;

-- ---------------------------------------------------------------------------
-- 3) ESTÁ VALENDO?
--
-- A assinatura precisa estar em vigor num plano que aceita o adicional
-- (`plano_efetivo`: vencida vira Grátis, e o adicional para junto). A
-- cortesia vale em qualquer plano — é decisão da plataforma.
-- ---------------------------------------------------------------------------
create or replace function public.adicional_ativo(p_salao uuid, p_adicional text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.salao_adicionais sa
      join public.adicionais ad on ad.codigo = sa.adicional
     where sa.salao_id = p_salao and sa.adicional = p_adicional
       and ((sa.cortesia and sa.status = 'ativo')
            or (public.plano_efetivo(p_salao) = any(ad.planos)
                and (sa.status = 'ativo'
                     or (sa.status = 'cancelado' and sa.vale_ate >= current_date)))))
$$;

-- A trava de módulo: o plano inclui, OU um adicional ativo libera a chave.
-- ⚠ A chave de um adicional que o plano dá (o Crediário no teste grátis) só
-- vale com o adicional À VENDA: experimentar o que ainda não se pode comprar
-- não é teste, é brinde. Com vários planos do mesmo módulo (o Crediário 200,
-- 500 e 1.000), basta um deles à venda.
create or replace function public.recurso_bool(p_salao uuid, p_chave text)
returns boolean language sql stable security definer set search_path = public as $$
  select (coalesce((select (pl.recursos ->> p_chave)::boolean
                      from public.planos pl where pl.codigo = public.plano_efetivo(p_salao)), false)
          and (not exists (select 1 from public.adicionais ad where ad.recurso = p_chave)
               or exists (select 1 from public.adicionais ad where ad.recurso = p_chave and ad.ativo)))
      or exists (select 1 from public.adicionais ad
                  where ad.recurso = p_chave and public.adicional_ativo(p_salao, ad.codigo))
$$;

/* A recusa diz onde está: módulo de plano é "a partir do Básico" (como
   antes); módulo adicional é "contrate em Meu plano", com o plano mínimo. */
create or replace function public.exigir_recurso(p_salao uuid, p_chave text, p_nome text)
returns void language plpgsql stable set search_path = public as $$
declare v_nome text; v_minimo text;
begin
  if coalesce(public.recurso_bool(p_salao, p_chave), false) then return; end if;
  -- O catálogo é de quem está logado: chamada sem login (dentro de um
  -- caminho que não é `security definer`) só perde a frase do adicional.
  begin
    select ad.nome,
           (select pl.nome from public.planos pl where pl.codigo = any(ad.planos)
             order by pl.preco_mes, pl.ordem limit 1)
      into v_nome, v_minimo
      from public.adicionais ad where ad.recurso = p_chave order by ad.ordem limit 1;
  exception when insufficient_privilege then v_nome := null;
  end;
  if v_nome is not null then
    raise exception '% faz parte do módulo adicional %, a partir do plano %. Contrate em Meu plano.',
      p_nome, v_nome, coalesce(v_minimo, 'Essencial')
      using errcode = 'check_violation';
  end if;
  raise exception '% está disponível a partir do plano Básico.', p_nome
    using errcode = 'check_violation';
end $$;

-- ---------------------------------------------------------------------------
-- 4) A MENSALIDADE: O PLANO E OS ADICIONAIS
--
-- Os itens que uma mensalidade daquele plano cobra: o plano (com o preço
-- especial do salão, 13) e cada adicional ativo ou aguardando que o plano
-- aceita, sem cortesia. É daqui que o Pix, o cartão e o lembrete de
-- renovação tiram o valor — e a cobrança guarda os itens, para o histórico
-- dizer o que foi pago.
-- ---------------------------------------------------------------------------
create or replace function public.itens_da_mensalidade(p_salao uuid, p_plano text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_array(jsonb_build_object('tipo', 'plano', 'codigo', p_plano,
           'nome', (select pl.nome from public.planos pl where pl.codigo = p_plano),
           'valor', public.preco_do_plano(p_salao, p_plano)))
      || coalesce((select jsonb_agg(jsonb_build_object('tipo', 'adicional', 'codigo', ad.codigo,
                     'nome', ad.nome, 'valor', coalesce(sa.preco_especial, ad.preco_mes))
                     order by ad.ordem)
                     from public.salao_adicionais sa join public.adicionais ad on ad.codigo = sa.adicional
                    where sa.salao_id = p_salao and sa.status in ('ativo', 'aguardando')
                      and not sa.cortesia and p_plano = any(ad.planos)
                      and coalesce(sa.preco_especial, ad.preco_mes) > 0), '[]'::jsonb)
$$;

create or replace function public.soma_dos_itens(p_itens jsonb)
returns numeric language sql immutable set search_path = public as $$
  select case when exists (select 1 from jsonb_array_elements(p_itens) x
                            where x->>'tipo' = 'plano' and x->'valor' = 'null'::jsonb)
              then null
              else (select coalesce(sum((x->>'valor')::numeric), 0)::numeric(10,2)
                      from jsonb_array_elements(p_itens) x) end
$$;

create or replace function public.valor_da_mensalidade(p_salao uuid, p_plano text)
returns numeric language sql stable security definer set search_path = public as $$
  select public.soma_dos_itens(public.itens_da_mensalidade(p_salao, p_plano))
$$;

/* ⚠ A COBRANÇA DO CARTÃO É LIDA COMO O MERCADO PAGO COBROU.

   O valor do cartão mora lá, e muda pela borda `adicional` no mesmo momento
   em que muda aqui — mas "no mesmo momento" são duas chamadas. Se uma falhar
   no meio (a borda tenta desfazer, e desfazer também pode falhar), o débito
   do mês chega com um valor que não é o de agora. Recusar seria o plano do
   dono vencer em silêncio, com o cartão debitado.

   Então o mês do cartão aceita três composições, nesta ordem: a mensalidade
   de agora; só o plano; o plano com todos os adicionais que o salão tem. A
   que bater é a que vale — e o que foi PAGO passa a valer (`adicionais_pagos`):
   pagou o Crediário, tem o Crediário. Valor que não bate com nenhuma continua
   recusado, como sempre (é a trava contra pagar R$ 57 e levar R$ 497). */
create or replace function public.itens_que_batem(p_salao uuid, p_plano text, p_valor numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_agora jsonb; v_so jsonb; v_todos jsonb;
begin
  v_agora := public.itens_da_mensalidade(p_salao, p_plano);
  if public.soma_dos_itens(v_agora) = p_valor then return v_agora; end if;
  v_so := jsonb_build_array(v_agora->0);
  if public.soma_dos_itens(v_so) = p_valor then return v_so; end if;
  v_todos := v_so || coalesce((select jsonb_agg(jsonb_build_object('tipo', 'adicional',
                 'codigo', ad.codigo, 'nome', ad.nome, 'valor', coalesce(sa.preco_especial, ad.preco_mes))
                 order by ad.ordem)
                 from public.salao_adicionais sa join public.adicionais ad on ad.codigo = sa.adicional
                where sa.salao_id = p_salao and not sa.cortesia and p_plano = any(ad.planos)
                  and coalesce(sa.preco_especial, ad.preco_mes) > 0), '[]'::jsonb);
  if public.soma_dos_itens(v_todos) = p_valor then return v_todos; end if;
  return v_agora;
end $$;

/* O que um pagamento confirmado faz com os adicionais. Chamada pelo
   `registrar_pagamento` (13), depois de estender a assinatura.

     · os que vieram na mensalidade paga passam a valer (ou continuam);
     · os que o plano pago não aceita (desceu para o Básico) param — sem
       cortesia, que é da plataforma;
     · os que ficaram de fora mas o plano aceita (a cobrança era de antes de
       contratar) continuam: entram na próxima. */
create or replace function public.adicionais_pagos(p_salao uuid, p_plano text, p_itens jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.salao_adicionais sa
     set status = 'ativo', vale_ate = null, cancelado_em = null,
         ativo_desde = case when sa.status = 'ativo' then sa.ativo_desde else now() end,
         atualizado_em = now()
   where sa.salao_id = p_salao
     and sa.adicional in (select x->>'codigo' from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) x
                           where x->>'tipo' = 'adicional');
  update public.salao_adicionais sa
     set status = 'cancelado', vale_ate = current_date, cancelado_em = now(),
         ja_teve = true, atualizado_em = now()
    from public.adicionais ad
   where ad.codigo = sa.adicional and sa.salao_id = p_salao
     and sa.status = 'ativo' and not sa.cortesia and not (p_plano = any(ad.planos));
end $$;

-- O lembrete de renovação por Pix diz o valor de verdade (plano + adicionais).
-- Refeita aqui porque é `language sql` e depende das funções acima.
create or replace function public.assinaturas_a_vencer(p_dias int default 5)
returns table (salao_id uuid, salao text, whatsapp text, plano text,
               valor numeric, vence_em date)
language sql security definer set search_path = public as $$
  select a.salao_id, s.nome, s.whatsapp, a.plano,
         public.valor_da_mensalidade(a.salao_id, a.plano), a.vence_em
    from public.assinaturas a
    join public.saloes s  on s.id = a.salao_id
    join public.planos pl on pl.codigo = a.plano
   where a.status = 'ativa'
     and a.vence_em is not null
     and a.vence_em <= current_date + p_dias
     and pl.preco_mes > 0
     and a.mp_preapproval is null
     and not exists (
       select 1 from public.cobrancas c
        where c.salao_id = a.salao_id and c.status = 'pendente'
          and c.metodo <> 'cartao'
          and c.vence_em > now())
   order by a.vence_em;
$$;

-- ---------------------------------------------------------------------------
-- 5) CONTRATAR, CANCELAR, CORTESIA, PREÇO
--
-- `conta_do_adicional` decide o que acontece e quanto a mensalidade passa a
-- ser, sem gravar nada. As ações:
--   contratar | cancelar           o dono ou o administrador do salão
--   cortesia | sem_cortesia | preco   a plataforma
-- `p_quem` é quem pediu, conferido aqui (a borda roda sem sessão: o mesmo
-- motivo do `abrir_cobranca`, 13).
-- ---------------------------------------------------------------------------
create or replace function public.conta_do_adicional(
  p_salao uuid, p_adicional text, p_acao text, p_quem uuid, p_preco numeric default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  ad public.adicionais%rowtype; r public.salao_adicionais%rowtype; a public.assinaturas%rowtype;
  v_super boolean; v_em_dia boolean; v_trial boolean; v_aceita boolean;
  n jsonb; v_efeito text; v_antes numeric; v_depois numeric; v_contrib_r numeric; v_contrib_n numeric;
  v_irmao record; v_contrib_i numeric := 0; v_troca text; v_troca_nome text;
begin
  if p_quem is null then
    raise exception 'Pedido sem responsável.' using errcode = 'check_violation';
  end if;
  v_super := coalesce((select pf.super_admin from public.perfis pf where pf.id = p_quem), false);
  if p_acao in ('contratar', 'cancelar') then
    if not v_super and not exists (
         select 1 from public.vinculos v
          where v.perfil_id = p_quem and v.salao_id = p_salao
            and v.status = 'ativo' and v.papel in ('dono', 'admin')) then
      raise exception 'Só o proprietário ou um administrador contrata módulos.'
        using errcode = 'insufficient_privilege';
    end if;
  elsif p_acao in ('cortesia', 'sem_cortesia', 'preco') then
    if not v_super then
      raise exception 'Só a plataforma dá cortesia ou preço especial.'
        using errcode = 'insufficient_privilege';
    end if;
  else
    raise exception 'Ação desconhecida.' using errcode = 'check_violation';
  end if;

  select * into ad from public.adicionais where codigo = p_adicional;
  if ad.codigo is null then
    raise exception 'Módulo não encontrado.' using errcode = 'check_violation';
  end if;
  select * into a from public.assinaturas where salao_id = p_salao;
  if a.salao_id is null then
    raise exception 'Este salão não tem assinatura.' using errcode = 'check_violation';
  end if;
  select * into r from public.salao_adicionais where salao_id = p_salao and adicional = p_adicional;

  v_em_dia := a.status = 'ativa' and (a.vence_em is null or a.vence_em >= current_date);
  v_trial  := public.plano_efetivo(p_salao) = 'trial';
  v_aceita := a.plano = any(ad.planos);

  -- O estado de agora, de onde o novo parte.
  n := jsonb_build_object('status', r.status, 'cortesia', coalesce(r.cortesia, false),
         'preco_especial', r.preco_especial, 'vale_ate', r.vale_ate, 'ja_teve', coalesce(r.ja_teve, false));

  -- O IRMÃO: outro plano do mesmo módulo (o Crediário 200 de quem pede o
  -- 500), valendo ou pedido. Contratar este é TROCAR: o novo assume no
  -- mesmo estado do de antes, e o de antes sai da mensalidade.
  if p_acao = 'contratar' then
    select sa.adicional, sa.status, sa.cortesia, sa.preco_especial, ad2.nome,
           ad2.preco_mes as preco_cat, a.plano = any(ad2.planos) as aceita
      into v_irmao
      from public.salao_adicionais sa join public.adicionais ad2 on ad2.codigo = sa.adicional
     where sa.salao_id = p_salao and ad2.recurso = ad.recurso and sa.adicional <> ad.codigo
       and sa.status in ('ativo', 'aguardando')
     order by ad2.ordem limit 1;
  end if;

  if p_acao = 'contratar' then
    if not ad.ativo then
      raise exception 'Este módulo não está à venda.' using errcode = 'check_violation';
    end if;
    if r.status in ('ativo', 'aguardando') then
      v_efeito := 'ja_contratado';
    elsif v_irmao.adicional is not null then
      if not v_em_dia and not v_trial then
        raise exception 'Regularize a mensalidade primeiro: com ela em dia, a troca é feita na hora.'
          using errcode = 'check_violation';
      end if;
      n := n || jsonb_build_object('status', v_irmao.status, 'vale_ate', null, 'cortesia', false);
      v_efeito := 'trocou';
      v_troca := v_irmao.adicional; v_troca_nome := v_irmao.nome;
      v_contrib_i := case when not coalesce(v_irmao.cortesia, false) and v_irmao.aceita
                          then greatest(coalesce(v_irmao.preco_especial, v_irmao.preco_cat), 0) else 0 end;
    elsif r.status = 'cancelado' and r.vale_ate >= current_date and v_em_dia and v_aceita then
      -- Cancelou e voltou atrás dentro do mês que já estava pago.
      n := n || jsonb_build_object('status', 'ativo', 'vale_ate', null);
      v_efeito := 'voltou';
    elsif not v_em_dia and not v_trial then
      raise exception 'Regularize a mensalidade primeiro: com ela em dia, o módulo é liberado na hora.'
        using errcode = 'check_violation';
    elsif v_em_dia and v_aceita and not coalesce(r.ja_teve, false) then
      n := n || jsonb_build_object('status', 'ativo', 'vale_ate', null);
      v_efeito := 'liberado';
    elsif v_em_dia and v_aceita then
      n := n || jsonb_build_object('status', 'aguardando', 'vale_ate', null);
      v_efeito := 'aguarda_pagamento';
    else
      -- No Básico ou no teste: entra com a mensalidade de um plano que aceita.
      n := n || jsonb_build_object('status', 'aguardando', 'vale_ate', null);
      v_efeito := 'aguarda_plano';
    end if;

  elsif p_acao = 'cancelar' then
    if r.status is null or r.status = 'cancelado' then
      v_efeito := 'ja_cancelado';
    elsif r.status = 'aguardando' then
      n := n || jsonb_build_object('status', 'cancelado', 'vale_ate', null);
      v_efeito := 'desistiu';
    else
      n := n || jsonb_build_object('status', 'cancelado', 'ja_teve', true,
             'vale_ate', greatest(coalesce(a.vence_em, current_date), current_date));
      v_efeito := 'cancelado';
    end if;

  elsif p_acao = 'cortesia' then
    n := n || jsonb_build_object('status', 'ativo', 'cortesia', true, 'vale_ate', null);
    v_efeito := 'cortesia';

  elsif p_acao = 'sem_cortesia' then
    if not coalesce(r.cortesia, false) then
      v_efeito := 'sem_mudanca';
    elsif v_em_dia and v_aceita then
      n := n || jsonb_build_object('cortesia', false);           -- passa a ser cobrado
      v_efeito := 'cobrado';
    else
      n := n || jsonb_build_object('cortesia', false, 'status', 'cancelado', 'vale_ate', current_date);
      v_efeito := 'encerrado';
    end if;

  else  -- preco
    if p_preco is not null and p_preco < 0 then
      raise exception 'Preço não pode ser negativo.' using errcode = 'check_violation';
    end if;
    n := n || jsonb_build_object('preco_especial', round(p_preco, 2),
                                 'status', coalesce(r.status, 'cancelado'));
    v_efeito := 'preco';
  end if;

  -- Quanto este adicional pesa na mensalidade, antes e depois.
  v_contrib_r := case when r.status in ('ativo', 'aguardando') and not coalesce(r.cortesia, false) and v_aceita
                      then greatest(coalesce(r.preco_especial, ad.preco_mes), 0) else 0 end;
  v_contrib_n := case when n->>'status' in ('ativo', 'aguardando') and not (n->>'cortesia')::boolean and v_aceita
                      then greatest(coalesce((n->>'preco_especial')::numeric, ad.preco_mes), 0) else 0 end;
  v_antes := coalesce(public.valor_da_mensalidade(p_salao, a.plano), 0);
  v_depois := v_antes - v_contrib_r - v_contrib_i + v_contrib_n;

  return jsonb_build_object(
    'efeito', v_efeito,
    'mudou', v_efeito not in ('ja_contratado', 'ja_cancelado', 'sem_mudanca'),
    'novo', n,
    'antes', v_antes, 'depois', v_depois,
    'proxima', a.vence_em, 'plano', a.plano,
    'preapproval', a.mp_preapproval,
    'nome', ad.nome, 'preco', coalesce(r.preco_especial, ad.preco_mes),
    'troca', v_troca, 'trocaNome', v_troca_nome);
end $$;

-- Para a borda: a conta, com o id do cartão (que nunca vai para a tela).
create or replace function public.preparar_adicional(
  p_salao uuid, p_adicional text, p_acao text, p_quem uuid, p_preco numeric default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select public.conta_do_adicional(p_salao, p_adicional, p_acao, p_quem, p_preco) - 'novo'
$$;

-- Para a tela: a mesma conta, para o "sua mensalidade passa de… para…",
-- sem o id do cartão. Quem pergunta é a sessão.
create or replace function public.simular_adicional(p_salao uuid, p_adicional text, p_acao text)
returns jsonb language sql stable security definer set search_path = public as $$
  select (public.conta_do_adicional(p_salao, p_adicional, p_acao, auth.uid()) - 'novo' - 'preapproval')
         || jsonb_build_object('cartao', exists (select 1 from public.assinaturas a
                                                  where a.salao_id = p_salao and a.mp_preapproval is not null))
$$;

/* Gravar. A borda já mudou o valor no cartão para `p_esperado`; se a conta
   de agora não der o mesmo número (alguém mexeu no meio), recusa — e a
   borda desfaz lá. */
create or replace function public.aplicar_adicional(
  p_salao uuid, p_adicional text, p_acao text, p_quem uuid,
  p_preco numeric default null, p_esperado numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb; n jsonb;
begin
  -- Um salão por vez: duas abas contratando ao mesmo tempo esperam a fila.
  perform 1 from public.assinaturas where salao_id = p_salao for update;
  c := public.conta_do_adicional(p_salao, p_adicional, p_acao, p_quem, p_preco);
  if p_esperado is not null and (c->>'depois')::numeric is distinct from p_esperado then
    raise exception 'A mensalidade mudou enquanto você confirmava. Abra Meu plano de novo.'
      using errcode = 'check_violation';
  end if;
  if not (c->>'mudou')::boolean then
    return jsonb_build_object('ok', true, 'efeito', c->>'efeito', 'mensalidade', (c->>'antes')::numeric);
  end if;
  n := c->'novo';

  insert into public.salao_adicionais as sa
    (salao_id, adicional, status, cortesia, preco_especial, vale_ate, ja_teve,
     desde, ativo_desde, cancelado_em, atualizado_em)
  values (p_salao, p_adicional, n->>'status', (n->>'cortesia')::boolean,
          (n->>'preco_especial')::numeric, (n->>'vale_ate')::date, (n->>'ja_teve')::boolean,
          now(), case when n->>'status' = 'ativo' then now() end,
          case when n->>'status' = 'cancelado' then now() end, now())
  on conflict (salao_id, adicional) do update
    set status         = excluded.status,
        cortesia       = excluded.cortesia,
        preco_especial = excluded.preco_especial,
        vale_ate       = excluded.vale_ate,
        ja_teve        = excluded.ja_teve,
        desde          = case when p_acao = 'contratar' then now() else sa.desde end,
        ativo_desde    = case when excluded.status = 'ativo' and sa.status <> 'ativo' then now()
                              when excluded.status = 'ativo' then sa.ativo_desde end,
        cancelado_em   = case when excluded.status = 'cancelado' and sa.status <> 'cancelado' then now()
                              when excluded.status = 'cancelado' then sa.cancelado_em end,
        atualizado_em  = now();

  -- Trocou de plano no mesmo módulo: o de antes sai agora (não "vale até":
  -- o novo já está valendo no lugar dele).
  if c->>'efeito' = 'trocou' and c->>'troca' is not null then
    update public.salao_adicionais
       set status = 'cancelado', vale_ate = null, cancelado_em = now(),
           ja_teve = true, atualizado_em = now()
     where salao_id = p_salao and adicional = c->>'troca';
  end if;

  /* A mensalidade mudou: o Pix que estava aberto é do valor velho. Sai do
     caminho, e o próximo nasce certo. (Pago assim mesmo, vale: o
     `registrar_pagamento` credita o plano, e o adicional entra no outro.) */
  if (c->>'antes')::numeric is distinct from (c->>'depois')::numeric then
    update public.cobrancas set status = 'cancelada'
     where salao_id = p_salao and status = 'pendente' and metodo <> 'cartao';
  end if;

  return jsonb_build_object('ok', true, 'efeito', c->>'efeito',
    'status', n->>'status', 'valeAte', n->>'vale_ate',
    'mensalidade', (c->>'depois')::numeric, 'proxima', c->>'proxima');
end $$;

-- ---------------------------------------------------------------------------
-- 6) O QUE A TELA PRECISA SABER
--
-- A equipe recebe só quais módulos estão valendo (para a tela não oferecer o
-- que o banco recusa). A gestão recebe o catálogo, os preços e a mensalidade.
-- ---------------------------------------------------------------------------
create or replace function public.meus_adicionais(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.assinaturas%rowtype; v_ativos jsonb; v_recursos jsonb;
begin
  if not public.e_equipe(p_salao) and not public.is_super() then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  select coalesce(jsonb_agg(ad.codigo order by ad.ordem), '[]'::jsonb)
    into v_ativos
    from public.adicionais ad where public.adicional_ativo(p_salao, ad.codigo);
  -- As chaves liberadas — pelo adicional ou pelo plano (o teste grátis).
  select coalesce(jsonb_agg(distinct ad.recurso), '[]'::jsonb)
    into v_recursos
    from public.adicionais ad where public.recurso_bool(p_salao, ad.recurso);
  if not public.e_gestor(p_salao) and not public.is_super() then
    return jsonb_build_object('ativos', v_ativos, 'recursos', v_recursos);
  end if;

  select * into a from public.assinaturas where salao_id = p_salao;
  return jsonb_build_object(
    'ativos', v_ativos, 'recursos', v_recursos,
    'plano', a.plano,
    'emDia', a.status = 'ativa' and (a.vence_em is null or a.vence_em >= current_date),
    'teste', public.plano_efetivo(p_salao) = 'trial',
    'proxima', a.vence_em,
    'cartao', a.mp_preapproval is not null,
    'mensalidade', public.valor_da_mensalidade(p_salao, a.plano),
    'itens', public.itens_da_mensalidade(p_salao, a.plano),
    'catalogo', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', ad.codigo, 'nome', ad.nome, 'descricao', ad.descricao,
               'recurso', ad.recurso,
               'mensagens', nullif(ad.recursos->>'mensagens_crediario', '')::int,
               'preco', coalesce(sa.preco_especial, ad.preco_mes), 'precoNormal', ad.preco_mes,
               'planos', to_jsonb(ad.planos),
               'planoMinimo', (select pl.nome from public.planos pl where pl.codigo = any(ad.planos)
                                order by pl.preco_mes, pl.ordem limit 1),
               'aceitaMeuPlano', a.plano = any(ad.planos),
               'status', sa.status, 'ativo', public.adicional_ativo(p_salao, ad.codigo),
               'valeAte', sa.vale_ate, 'cortesia', coalesce(sa.cortesia, false),
               'jaTeve', coalesce(sa.ja_teve, false))
             order by ad.ordem)
        from public.adicionais ad
        left join public.salao_adicionais sa on sa.salao_id = p_salao and sa.adicional = ad.codigo
       where ad.ativo or sa.status is not null), '[]'::jsonb));
end $$;

-- A plataforma: quem tem o quê, e quanto os adicionais rendem por mês.
create or replace function public.adicionais_da_plataforma()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os adicionais de todos.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object(
    'catalogo', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome,
                  'preco', preco_mes, 'ativo', ativo) order by ordem) from public.adicionais), '[]'::jsonb),
    'saloes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'salaoId', sa.salao_id, 'salao', s.nome, 'adicional', sa.adicional, 'nome', ad.nome,
               'status', sa.status, 'ativo', public.adicional_ativo(sa.salao_id, sa.adicional),
               'cortesia', sa.cortesia, 'preco', coalesce(sa.preco_especial, ad.preco_mes),
               'precoEspecial', sa.preco_especial, 'valeAte', sa.vale_ate, 'desde', sa.desde)
             order by s.nome)
        from public.salao_adicionais sa
        join public.saloes s on s.id = sa.salao_id
        join public.adicionais ad on ad.codigo = sa.adicional), '[]'::jsonb),
    'receitaMes', coalesce((
      select sum(coalesce(sa.preco_especial, ad.preco_mes))
        from public.salao_adicionais sa join public.adicionais ad on ad.codigo = sa.adicional
       where sa.status = 'ativo' and not sa.cortesia
         and public.adicional_ativo(sa.salao_id, sa.adicional)), 0));
end $$;

-- ---------------------------------------------------------------------------
-- 7) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.adicional_ativo(uuid, text) from public, anon, authenticated;
revoke all on function public.itens_da_mensalidade(uuid, text) from public, anon, authenticated;
revoke all on function public.valor_da_mensalidade(uuid, text) from public, anon, authenticated;
revoke all on function public.itens_que_batem(uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.adicionais_pagos(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.conta_do_adicional(uuid, text, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public.assinaturas_a_vencer(int) from public, anon, authenticated;
-- As duas metades da mudança: só a borda `adicional` (bordas.test.sql cobra).
revoke all on function public.preparar_adicional(uuid, text, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public.aplicar_adicional(uuid, text, text, uuid, numeric, numeric) from public, anon, authenticated;
grant execute on function public.preparar_adicional(uuid, text, text, uuid, numeric) to service_role;
grant execute on function public.aplicar_adicional(uuid, text, text, uuid, numeric, numeric) to service_role;
-- A tela: a própria conta e a própria situação (as funções conferem a sessão).
revoke all on function public.simular_adicional(uuid, text, text) from public, anon;
revoke all on function public.meus_adicionais(uuid) from public, anon;
revoke all on function public.adicionais_da_plataforma() from public, anon;
grant execute on function public.simular_adicional(uuid, text, text) to authenticated;
grant execute on function public.meus_adicionais(uuid) to authenticated;
grant execute on function public.adicionais_da_plataforma() to authenticated;

-- ###########################################################################
-- ## 47_crediario.sql
-- ###########################################################################

-- ===========================================================================
-- 47_crediario.sql — o Crediário: vender parcelado no fiado
--
-- O pedido: "tem gente que trabalha com fiado — lingerie, e pagam parcelado
-- em 3x". A cliente leva hoje e paga todo dia 5, por três meses. É o módulo
-- adicional da 46 (R$ 49,90, do Essencial para cima).
--
-- ── COMO O DINHEIRO ANDA ──────────────────────────────────────────────────
-- A venda é uma comanda como qualquer outra: os itens, a entrada (se houver)
-- num pagamento normal, e o resto num pagamento da forma `crediario`, que
-- fecha a comanda. Então:
--
--   · VENDIDO entra no faturamento no dia da venda (a mesma regra de sempre,
--     pela comanda fechada), e o estoque sai na hora;
--   · RECEBIDO é cada parcela paga (`crediario_recebimentos`): entra no caixa
--     do dia em que entrou — o dinheiro na gaveta, o Pix com os Pix;
--   · A RECEBER e ATRASADO são as parcelas em aberto.
-- Nada é contado duas vezes: a parcela recebida não é faturamento de novo.
--
-- ── AS DECISÕES DO DONO ───────────────────────────────────────────────────
--   · nome completo, WhatsApp e CPF obrigatórios para vender no crediário
--     (e o CPF é conferido pelo dígito, aqui no banco);
--   · comissão CONFORME A CLIENTE PAGA: na venda conta só a parte paga na
--     hora; cada parcela recebida conta a parte dela, no dia em que entrou;
--   · sem juros por enquanto;
--   · pagamento parcial: o resto fica em aberto na mesma parcela;
--   · desfazer um recebimento é da gestão;
--   · módulo cancelado: as parcelas abertas continuam e o recebimento
--     continua — só não se vende fiado novo (a trava é na VENDA).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS TABELAS
-- ---------------------------------------------------------------------------
create table if not exists public.crediarios (
  id             uuid primary key default gen_random_uuid(),
  salao_id       uuid not null references public.saloes(id) on delete cascade,
  cliente_id     uuid not null references public.clientes(id),
  comanda_id     uuid not null references public.comandas(id),
  pagamento_id   uuid references public.pagamentos(id) on delete set null,
  valor          numeric(10,2) not null check (valor > 0),       -- o que foi financiado
  parcelas       smallint not null check (parcelas between 1 and 12),
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.perfis(id) on delete set null,
  -- Desfeito (vendido errado, refeito na hora): sai de tudo, fica o rastro.
  desfeito_em    timestamptz,
  desfeito_por   uuid references public.perfis(id) on delete set null
);
create unique index if not exists ux_crediario_comanda
  on public.crediarios(comanda_id) where desfeito_em is null;
create index if not exists ix_crediario_cliente on public.crediarios(cliente_id);

create table if not exists public.crediario_parcelas (
  id            uuid primary key default gen_random_uuid(),
  crediario_id  uuid not null references public.crediarios(id) on delete cascade,
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  numero        smallint not null check (numero >= 1),
  valor         numeric(10,2) not null check (valor > 0),
  vence_em      date not null,
  unique (crediario_id, numero)
);
create index if not exists ix_parcela_salao_vence on public.crediario_parcelas(salao_id, vence_em);

create table if not exists public.crediario_recebimentos (
  id            uuid primary key default gen_random_uuid(),
  parcela_id    uuid not null references public.crediario_parcelas(id) on delete cascade,
  crediario_id  uuid not null references public.crediarios(id) on delete cascade,
  salao_id      uuid not null references public.saloes(id) on delete cascade,
  valor         numeric(10,2) not null check (valor > 0),
  forma         text not null check (forma in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia')),
  -- O caixa aberto na hora (como o pagamento, 17): o dinheiro vai para a gaveta.
  caixa_id      uuid references public.caixas(id) on delete set null,
  recebido_em   timestamptz not null default now(),
  recebido_por  uuid references public.perfis(id) on delete set null,
  desfeito_em   timestamptz,
  desfeito_por  uuid references public.perfis(id) on delete set null
);
create index if not exists ix_receb_parcela on public.crediario_recebimentos(parcela_id);
create index if not exists ix_receb_salao on public.crediario_recebimentos(salao_id, recebido_em);
create index if not exists ix_receb_caixa on public.crediario_recebimentos(caixa_id);

-- Dinheiro e venda: o balcão e a gestão leem (como o caixa). Ninguém escreve
-- pela API — só as funções abaixo.
alter table public.crediarios enable row level security;
alter table public.crediario_parcelas enable row level security;
alter table public.crediario_recebimentos enable row level security;
drop policy if exists crediarios_ler on public.crediarios;
create policy crediarios_ler on public.crediarios for select to authenticated
  using (public.ve_agenda_toda(salao_id));
drop policy if exists crediario_parcelas_ler on public.crediario_parcelas;
create policy crediario_parcelas_ler on public.crediario_parcelas for select to authenticated
  using (public.ve_agenda_toda(salao_id));
drop policy if exists crediario_receb_ler on public.crediario_recebimentos;
create policy crediario_receb_ler on public.crediario_recebimentos for select to authenticated
  using (public.ve_agenda_toda(salao_id));
revoke all on public.crediarios, public.crediario_parcelas, public.crediario_recebimentos
  from anon, authenticated;
grant select on public.crediarios, public.crediario_parcelas, public.crediario_recebimentos
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2) O CPF, CONFERIDO PELO DÍGITO
--
-- Crediário é dinheiro emprestado: o CPF precisa ser de verdade, e não onze
-- números quaisquer. 111.111.111-11 passa no dígito e não é de ninguém.
-- ---------------------------------------------------------------------------
create or replace function public.cpf_valido(p_cpf text)
returns boolean language plpgsql immutable set search_path = public as $$
declare d text := public.so_digitos(p_cpf); s int; r int; i int;
begin
  if d is null or d !~ '^[0-9]{11}$' or d ~ '^(.)\1{10}$' then return false; end if;
  s := 0;
  for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  if r <> substr(d, 10, 1)::int then return false; end if;
  s := 0;
  for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
  r := (s * 10) % 11; if r = 10 then r := 0; end if;
  return r = substr(d, 11, 1)::int;
end $$;

-- ---------------------------------------------------------------------------
-- 3) O PAGAMENTO DA FORMA `crediario` SÓ NASCE PELA VENDA
--
-- A tela grava pagamentos direto na tabela (o caminho de sempre). Um
-- `crediario` gravado assim seria um fiado sem parcelas: a comanda fecharia
-- "paga" e ninguém saberia que alguém deve. Então ele só entra quando a
-- venda (`vender_no_crediario`) já criou o crediário daquele valor — e não
-- muda nem sai enquanto o crediário existir.
-- ---------------------------------------------------------------------------
create or replace function public.tg_pagamento_crediario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.forma = 'crediario' and not exists (
         select 1 from public.crediarios cr
          where cr.comanda_id = new.comanda_id and cr.desfeito_em is null
            and cr.pagamento_id is null and cr.valor = new.valor) then
      raise exception 'Venda no crediário é pelo botão "Vender no crediário" da comanda.'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if (old.forma = 'crediario' or new.forma = 'crediario')
       and (new.forma is distinct from old.forma or new.valor is distinct from old.valor
            or new.comanda_id is distinct from old.comanda_id) then
      raise exception 'O pagamento do crediário não se edita: desfaça a venda no crediário.'
        using errcode = 'check_violation';
    end if;
    return new;
  end if;
  -- DELETE
  if old.forma = 'crediario' and exists (
       select 1 from public.crediarios cr
        where cr.pagamento_id = old.id and cr.desfeito_em is null) then
    raise exception 'O pagamento do crediário não se apaga: desfaça a venda no crediário.'
      using errcode = 'check_violation';
  end if;
  return old;
end $$;

drop trigger if exists tg_pagamento_crediario on public.pagamentos;
create trigger tg_pagamento_crediario
  before insert or update or delete on public.pagamentos
  for each row execute function public.tg_pagamento_crediario();

-- Comanda vendida no crediário não reabre por baixo: as parcelas ficariam
-- penduradas numa venda que mudou.
create or replace function public.tg_comanda_crediario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'fechada' and new.status <> 'fechada' and exists (
       select 1 from public.crediarios cr
        where cr.comanda_id = new.id and cr.desfeito_em is null) then
    raise exception 'Esta comanda foi vendida no crediário. Para corrigir, desfaça a venda no crediário (no detalhe da comanda).'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists tg_comanda_crediario on public.comandas;
create trigger tg_comanda_crediario
  before update of status on public.comandas
  for each row execute function public.tg_comanda_crediario();

-- ---------------------------------------------------------------------------
-- 4) VENDER NO CREDIÁRIO
--
-- O que falta pagar da comanda vira N parcelas, a primeira em p_primeiro e
-- as outras no mesmo dia dos meses seguintes (dia 31 vira o último dia do
-- mês curto). Os centavos que sobram da divisão vão para a primeira. E a
-- comanda fecha aqui, junto — tudo ou nada.
-- ---------------------------------------------------------------------------
create or replace function public.vender_no_crediario(
  p_comanda uuid, p_parcelas int, p_primeiro date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.comandas%rowtype; t record; cli record; v_cr uuid; v_base numeric; v_resto numeric;
  v_hoje date; i int; v_pg uuid; v_lista jsonb := '[]'::jsonb; v_val numeric; v_venc date;
begin
  select * into c from public.comandas where id = p_comanda for update;
  if c.id is null then
    raise exception 'Comanda não encontrada.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(c.salao_id) then
    raise exception 'Só o balcão e a gestão vendem no crediário.' using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(c.salao_id, 'crediario', 'Vender no crediário');
  if c.status <> 'aberta' then
    raise exception 'Esta comanda não está aberta.' using errcode = 'check_violation';
  end if;
  if c.cliente_id is null then
    raise exception 'Escolha a cliente da comanda: o crediário é no nome dela.' using errcode = 'check_violation';
  end if;
  select cl.nome, cl.telefone, cl.cpf into cli from public.clientes cl where cl.id = c.cliente_id;
  if coalesce(btrim(cli.nome), '') !~ '\S+\s+\S+' then
    raise exception 'Para vender no crediário, a ficha da cliente precisa do nome completo.'
      using errcode = 'check_violation';
  end if;
  if length(coalesce(public.so_digitos(cli.telefone), '')) < 10 then
    raise exception 'Para vender no crediário, a ficha da cliente precisa do WhatsApp.'
      using errcode = 'check_violation';
  end if;
  if not public.cpf_valido(cli.cpf) then
    raise exception 'Para vender no crediário, a ficha da cliente precisa de um CPF válido.'
      using errcode = 'check_violation';
  end if;
  if p_parcelas is null or p_parcelas < 1 or p_parcelas > 12 then
    raise exception 'Escolha de 1 a 12 parcelas.' using errcode = 'check_violation';
  end if;
  v_hoje := public.hoje_no_salao(c.salao_id);
  if p_primeiro is null or p_primeiro < v_hoje or p_primeiro > v_hoje + 120 then
    raise exception 'O primeiro vencimento vai de hoje até daqui a 4 meses.' using errcode = 'check_violation';
  end if;

  select * into t from public.comandas_totais where id = p_comanda;
  if coalesce(t.subtotal, 0) <= 0 then
    raise exception 'Comanda sem itens não pode ser vendida.' using errcode = 'check_violation';
  end if;
  if coalesce(t.falta, 0) <= 0 then
    raise exception 'Esta comanda já está paga.' using errcode = 'check_violation';
  end if;

  insert into public.crediarios (salao_id, cliente_id, comanda_id, valor, parcelas, criado_por)
       values (c.salao_id, c.cliente_id, c.id, round(t.falta, 2), p_parcelas, auth.uid())
    returning id into v_cr;

  v_base := trunc(round(t.falta, 2) / p_parcelas, 2);
  v_resto := round(t.falta, 2) - v_base * p_parcelas;
  for i in 1 .. p_parcelas loop
    v_val := v_base + case when i = 1 then v_resto else 0 end;
    v_venc := (p_primeiro + make_interval(months => i - 1))::date;
    insert into public.crediario_parcelas (crediario_id, salao_id, numero, valor, vence_em)
         values (v_cr, c.salao_id, i, v_val, v_venc);
    v_lista := v_lista || jsonb_build_object('numero', i, 'valor', v_val, 'venceEm', v_venc);
  end loop;

  insert into public.pagamentos (comanda_id, forma, valor)
       values (c.id, 'crediario', round(t.falta, 2))
    returning id into v_pg;
  update public.crediarios set pagamento_id = v_pg where id = v_cr;
  update public.comandas set status = 'fechada', fechada_em = now() where id = c.id;

  return jsonb_build_object('ok', true, 'crediario', v_cr, 'valor', round(t.falta, 2),
                            'parcelas', v_lista);
end $$;

/* ── A VENDA DIRETO NA TELA DO CREDIÁRIO ────────────────────────────────
   A comanda está desligada na plataforma (o dono trabalha só com a agenda),
   e a venda a prazo não pode depender dela. Aqui a recepção escolhe a
   cliente, os itens e a entrada, e o banco monta a comanda por baixo — é ela
   que leva a venda ao faturamento, ao estoque e à comissão, como qualquer
   venda. O PREÇO É O DO CADASTRO, lido aqui (o desconto, se houver, é à
   parte e conferido pela trava da comanda). */
create or replace function public.nova_venda_no_crediario(
  p_salao uuid, p_cliente uuid, p_itens jsonb, p_profissional uuid,
  p_desconto numeric, p_entrada numeric, p_forma_entrada text,
  p_parcelas int, p_primeiro date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_com uuid; x jsonb; v_qtd numeric; v_preco numeric; v_desc text; v_falta numeric;
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão vendem no crediário.' using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(p_salao, 'crediario', 'Vender no crediário');
  if not exists (select 1 from public.clientes c where c.id = p_cliente and c.salao_id = p_salao) then
    raise exception 'Escolha a cliente.' using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Some pelo menos um item à venda.' using errcode = 'check_violation';
  end if;
  if p_profissional is not null and not exists (
       select 1 from public.profissionais pr where pr.id = p_profissional and pr.salao_id = p_salao) then
    raise exception 'Quem vendeu não é deste salão.' using errcode = 'check_violation';
  end if;

  insert into public.comandas (salao_id, cliente_id, status) values (p_salao, p_cliente, 'aberta')
    returning id into v_com;
  for x in select * from jsonb_array_elements(p_itens) loop
    v_qtd := coalesce(nullif(x->>'qtd', '')::numeric, 1);
    if v_qtd <= 0 or v_qtd > 999 then
      raise exception 'Confira a quantidade dos itens.' using errcode = 'check_violation';
    end if;
    v_desc := null;
    if x->>'tipo' = 'produto' then
      select pr.nome, pr.preco into v_desc, v_preco from public.produtos pr
       where pr.id = (x->>'id')::uuid and pr.salao_id = p_salao;
      if v_desc is null then
        raise exception 'Um dos produtos não é deste salão.' using errcode = 'check_violation';
      end if;
      insert into public.comanda_itens (comanda_id, tipo, produto_id, descricao, qtd, preco_unit, profissional_id)
           values (v_com, 'produto', (x->>'id')::uuid, v_desc, v_qtd, v_preco, p_profissional);
    elsif x->>'tipo' = 'servico' then
      select sv.nome, sv.preco into v_desc, v_preco from public.servicos sv
       where sv.id = (x->>'id')::uuid and sv.salao_id = p_salao;
      if v_desc is null then
        raise exception 'Um dos serviços não é deste salão.' using errcode = 'check_violation';
      end if;
      insert into public.comanda_itens (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
           values (v_com, 'servico', (x->>'id')::uuid, v_desc, v_qtd, v_preco, p_profissional);
    else
      raise exception 'Item de tipo desconhecido.' using errcode = 'check_violation';
    end if;
  end loop;
  if coalesce(p_desconto, 0) < 0 then
    raise exception 'O desconto não pode ser negativo.' using errcode = 'check_violation';
  end if;
  if coalesce(p_desconto, 0) > 0 then
    update public.comandas set desconto = round(p_desconto, 2) where id = v_com;
  end if;
  if coalesce(p_entrada, 0) > 0 then
    if coalesce(p_forma_entrada, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
      raise exception 'Escolha como ela pagou a entrada.' using errcode = 'check_violation';
    end if;
    select t.total - round(p_entrada, 2) into v_falta from public.comandas_totais t where t.id = v_com;
    if v_falta <= 0 then
      raise exception 'A entrada cobre a venda inteira: não sobra nada para o crediário.'
        using errcode = 'check_violation';
    end if;
    insert into public.pagamentos (comanda_id, forma, valor) values (v_com, p_forma_entrada, round(p_entrada, 2));
  end if;
  return public.vender_no_crediario(v_com, p_parcelas, p_primeiro) || jsonb_build_object('comanda', v_com);
end $$;

-- ---------------------------------------------------------------------------
-- 5) RECEBER UMA PARCELA (OU PARTE DELA)
--
-- Sem trava de módulo de propósito: módulo cancelado não impede receber o
-- que a cliente já deve.
-- ---------------------------------------------------------------------------
create or replace function public.saldo_da_parcela(p_parcela uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select p.valor - coalesce((select sum(r.valor) from public.crediario_recebimentos r
                              where r.parcela_id = p.id and r.desfeito_em is null), 0)
    from public.crediario_parcelas p where p.id = p_parcela
$$;

create or replace function public.receber_parcela(p_parcela uuid, p_valor numeric, p_forma text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p record; v_saldo numeric; v_caixa uuid; v_id uuid;
begin
  select pa.*, cr.desfeito_em as cr_desfeito into p
    from public.crediario_parcelas pa join public.crediarios cr on cr.id = pa.crediario_id
   where pa.id = p_parcela for update of pa;
  if p.id is null or p.cr_desfeito is not null then
    raise exception 'Parcela não encontrada.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(p.salao_id) then
    raise exception 'Só o balcão e a gestão registram recebimento.' using errcode = 'insufficient_privilege';
  end if;
  if coalesce(p_forma, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
    raise exception 'Escolha como ela pagou: Pix, dinheiro, cartão ou transferência.'
      using errcode = 'check_violation';
  end if;
  v_saldo := public.saldo_da_parcela(p.id);
  if v_saldo <= 0 then
    raise exception 'Esta parcela já está paga.' using errcode = 'check_violation';
  end if;
  if p_valor is null or round(p_valor, 2) <= 0 then
    raise exception 'Diga quanto ela pagou.' using errcode = 'check_violation';
  end if;
  if round(p_valor, 2) > v_saldo then
    raise exception 'Esta parcela tem % em aberto.', public.reais(v_saldo) using errcode = 'check_violation';
  end if;
  select k.id into v_caixa from public.caixas k
   where k.salao_id = p.salao_id and k.fechado_em is null limit 1;
  insert into public.crediario_recebimentos
    (parcela_id, crediario_id, salao_id, valor, forma, caixa_id, recebido_por)
  values (p.id, p.crediario_id, p.salao_id, round(p_valor, 2), p_forma, v_caixa, auth.uid())
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recebimento', v_id, 'saldo', v_saldo - round(p_valor, 2));
end $$;

-- Lançou por engano: sai da conta (e da gaveta), e fica o rastro. É da gestão.
create or replace function public.desfazer_recebimento_crediario(p_recebimento uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select * into r from public.crediario_recebimentos where id = p_recebimento for update;
  if r.id is null or r.desfeito_em is not null then
    raise exception 'Recebimento não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.e_gestor(r.salao_id) then
    raise exception 'Só o proprietário ou um administrador desfaz um recebimento.'
      using errcode = 'insufficient_privilege';
  end if;
  update public.crediario_recebimentos set desfeito_em = now(), desfeito_por = auth.uid()
   where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

/* Vendeu errado (3x em vez de 4x, a cliente errada): desfaz a venda no
   crediário — enquanto nada foi recebido. A comanda volta a ficar aberta,
   com o que faltava a pagar, para a recepção refazer. Mesma regra do
   "reabrir" da tela: de outro dia, só a gestão. */
create or replace function public.desfazer_crediario(p_crediario uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cr record; v_fuso text;
begin
  select x.*, c.fechada_em into cr from public.crediarios x
    join public.comandas c on c.id = x.comanda_id
   where x.id = p_crediario for update of x;
  if cr.id is null or cr.desfeito_em is not null then
    raise exception 'Crediário não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(cr.salao_id) then
    raise exception 'Só o balcão e a gestão desfazem a venda.' using errcode = 'insufficient_privilege';
  end if;
  select coalesce(fuso, 'America/Sao_Paulo') into v_fuso from public.saloes where id = cr.salao_id;
  if (cr.fechada_em at time zone v_fuso)::date <> public.hoje_no_salao(cr.salao_id)
     and not public.e_gestor(cr.salao_id) then
    raise exception 'Esta venda é de outro dia: só o proprietário ou um administrador desfaz.'
      using errcode = 'insufficient_privilege';
  end if;
  if exists (select 1 from public.crediario_recebimentos r
              where r.crediario_id = cr.id and r.desfeito_em is null) then
    raise exception 'Já há parcela recebida: desfaça os recebimentos antes.'
      using errcode = 'check_violation';
  end if;
  update public.crediarios set desfeito_em = now(), desfeito_por = auth.uid() where id = cr.id;
  update public.comandas set status = 'aberta', fechada_em = null where id = cr.comanda_id;
  delete from public.pagamentos where id = cr.pagamento_id;
  return jsonb_build_object('ok', true, 'comanda', cr.comanda_id);
end $$;

-- ---------------------------------------------------------------------------
-- 6) A COMISSÃO, CONFORME A CLIENTE PAGA
--
-- Na venda, a comissão da comanda conta só a parte paga na hora
-- (`fator_a_vista`: 1 nas comandas sem crediário, então nada muda nelas).
-- Cada parcela recebida conta a parte dela, por profissional, no dia em que
-- entrou (`crediario_comissoes`). A comanda de R$ 300 com R$ 100 de entrada
-- e 2x de R$ 100: um terço da comissão na venda, um terço em cada parcela.
-- ---------------------------------------------------------------------------
create or replace function public.fator_a_vista(p_comanda uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(1 - (select cr.valor from public.crediarios cr
                        where cr.comanda_id = p_comanda and cr.desfeito_em is null)
                      / nullif((select t.total from public.comandas_totais t where t.id = p_comanda), 0), 1)
$$;

/* ⚠ FUNÇÃO, E NÃO VISTA. Uma vista em cima de `comandas_totais` e de
   `comanda_itens_calculados` trava o `drop view` que o 15, o 16 e o 17 fazem
   a cada colagem do 00_tudo: a SEGUNDA colagem morria com "cannot drop view
   comandas_totais because other objects depend on it". Função não prende. */
drop view if exists public.crediario_comissoes;
create or replace function public.crediario_comissoes(p_salao uuid, p_ini timestamptz, p_fim timestamptz)
returns table (profissional_id uuid, comissao numeric)
language sql stable security definer set search_path = public as $$
  select i.profissional_id,
         round(sum(i.comissao_valor) * r.valor / nullif(t.total, 0), 2)
    from public.crediario_recebimentos r
    join public.crediarios cr on cr.id = r.crediario_id
    join public.comandas_totais t on t.id = cr.comanda_id
    join public.comanda_itens_calculados i on i.comanda_id = cr.comanda_id
   where r.salao_id = p_salao and r.recebido_em >= p_ini and r.recebido_em < p_fim
     and r.desfeito_em is null and cr.desfeito_em is null
   group by r.id, i.profissional_id, r.valor, t.total
$$;

-- ---------------------------------------------------------------------------
-- 7) O RESUMO DO PERÍODO (o relatório, 12) E A TELA DO CREDIÁRIO
-- ---------------------------------------------------------------------------
create or replace function public.crediario_no_periodo(p_salao uuid, p_ini timestamptz, p_fim timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'vendido', coalesce((select round(sum(cr.valor), 2) from public.crediarios cr
                           join public.comandas c on c.id = cr.comanda_id
                          where cr.salao_id = p_salao and cr.desfeito_em is null
                            and c.fechada_em >= p_ini and c.fechada_em < p_fim), 0),
    'recebido', coalesce((select round(sum(r.valor), 2) from public.crediario_recebimentos r
                           join public.crediarios cr on cr.id = r.crediario_id
                          where r.salao_id = p_salao and r.desfeito_em is null and cr.desfeito_em is null
                            and r.recebido_em >= p_ini and r.recebido_em < p_fim), 0),
    'aReceber', coalesce((select round(sum(greatest(public.saldo_da_parcela(pa.id), 0)), 2)
                            from public.crediario_parcelas pa
                            join public.crediarios cr on cr.id = pa.crediario_id
                           where pa.salao_id = p_salao and cr.desfeito_em is null), 0),
    'atrasado', coalesce((select round(sum(greatest(public.saldo_da_parcela(pa.id), 0)), 2)
                            from public.crediario_parcelas pa
                            join public.crediarios cr on cr.id = pa.crediario_id
                           where pa.salao_id = p_salao and cr.desfeito_em is null
                             and pa.vence_em < public.hoje_no_salao(p_salao)), 0))
$$;

/* A tela do Crediário: o resumo e as vendas com as parcelas e os
   recebimentos. As quitadas há mais de 60 dias ficam de fora (o histórico
   continua no banco). */
create or replace function public.crediario_painel(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_hoje date; v_fuso text; v_ini timestamptz;
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem o crediário.' using errcode = 'insufficient_privilege';
  end if;
  v_hoje := public.hoje_no_salao(p_salao);
  select coalesce(fuso, 'America/Sao_Paulo') into v_fuso from public.saloes where id = p_salao;
  v_ini := (date_trunc('month', v_hoje)::timestamp) at time zone v_fuso;
  return jsonb_build_object(
    'hoje', v_hoje,
    'resumo', public.crediario_no_periodo(p_salao, v_ini, now() + interval '1 day')
              || jsonb_build_object('venceHoje', coalesce((
                   select round(sum(greatest(public.saldo_da_parcela(pa.id), 0)), 2)
                     from public.crediario_parcelas pa join public.crediarios cr on cr.id = pa.crediario_id
                    where pa.salao_id = p_salao and cr.desfeito_em is null and pa.vence_em = v_hoje), 0)),
    'vendas', coalesce((
      select jsonb_agg(v order by v->>'proximo' nulls last, v->>'criadoEm' desc)
        from (select jsonb_build_object(
                'id', cr.id, 'comandaId', cr.comanda_id, 'numero', c.numero,
                'clienteId', cr.cliente_id, 'cliente', cl.nome, 'telefone', cl.telefone,
                'valor', cr.valor, 'criadoEm', cr.criado_em,
                'proximo', (select min(pa.vence_em) from public.crediario_parcelas pa
                             where pa.crediario_id = cr.id and public.saldo_da_parcela(pa.id) > 0),
                'parcelas', (select jsonb_agg(jsonb_build_object(
                               'id', pa.id, 'numero', pa.numero, 'valor', pa.valor, 'venceEm', pa.vence_em,
                               'saldo', public.saldo_da_parcela(pa.id),
                               'recebimentos', coalesce((select jsonb_agg(jsonb_build_object(
                                   'id', r.id, 'valor', r.valor, 'forma', r.forma, 'em', r.recebido_em)
                                   order by r.recebido_em)
                                  from public.crediario_recebimentos r
                                 where r.parcela_id = pa.id and r.desfeito_em is null), '[]'::jsonb))
                               order by pa.numero)
                               from public.crediario_parcelas pa where pa.crediario_id = cr.id)) as v
                from public.crediarios cr
                join public.comandas c on c.id = cr.comanda_id
                join public.clientes cl on cl.id = cr.cliente_id
               where cr.salao_id = p_salao and cr.desfeito_em is null
                 and (exists (select 1 from public.crediario_parcelas pa
                               where pa.crediario_id = cr.id and public.saldo_da_parcela(pa.id) > 0)
                      or exists (select 1 from public.crediario_recebimentos r
                                  where r.crediario_id = cr.id and r.desfeito_em is null
                                    and r.recebido_em > now() - interval '60 days'))) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- 8) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.cpf_valido(text) from public, anon;
grant execute on function public.cpf_valido(text) to authenticated;
revoke all on function public.tg_pagamento_crediario() from public, anon, authenticated;
revoke all on function public.tg_comanda_crediario() from public, anon, authenticated;
revoke all on function public.saldo_da_parcela(uuid) from public, anon, authenticated;
revoke all on function public.fator_a_vista(uuid) from public, anon, authenticated;
revoke all on function public.crediario_comissoes(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.crediario_no_periodo(uuid, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.vender_no_crediario(uuid, int, date) from public, anon;
revoke all on function public.receber_parcela(uuid, numeric, text) from public, anon;
revoke all on function public.desfazer_recebimento_crediario(uuid) from public, anon;
revoke all on function public.desfazer_crediario(uuid) from public, anon;
revoke all on function public.crediario_painel(uuid) from public, anon;
grant execute on function public.vender_no_crediario(uuid, int, date) to authenticated;
revoke all on function public.nova_venda_no_crediario(uuid, uuid, jsonb, uuid, numeric, numeric, text, int, date) from public, anon;
grant execute on function public.nova_venda_no_crediario(uuid, uuid, jsonb, uuid, numeric, numeric, text, int, date) to authenticated;
grant execute on function public.receber_parcela(uuid, numeric, text) to authenticated;
grant execute on function public.desfazer_recebimento_crediario(uuid) to authenticated;
grant execute on function public.desfazer_crediario(uuid) to authenticated;
grant execute on function public.crediario_painel(uuid) to authenticated;

-- ###########################################################################
-- ## 48_cadastro_link.sql
-- ###########################################################################

-- ===========================================================================
-- 48_cadastro_link.sql — a cliente se cadastra pelo link, sem agendar
--
-- O pedido: "no link tem como a cliente fazer o cadastro sem agendar? Aí ela
-- se cadastra e depois eu coloco ela no pacote." Até aqui, criar a conta no
-- link só LIGAVA a conta a uma ficha que o salão já tivesse com o mesmo
-- WhatsApp (`ligar_minha_ficha`, 09); sem ficha, ela só nascia no primeiro
-- horário marcado. A cliente que se cadastrava para entrar num pacote não
-- aparecia em Clientes.
--
-- Agora, quem cria a conta pelo link do salão (ou abre o link de cadastro,
-- `?cadastro=1`) ganha a ficha naquele salão: nome, WhatsApp e e-mail, com a
-- marca `pelo_link` para o dono saber de onde veio.
--
-- ── SEM DUPLICAR ──────────────────────────────────────────────────────────
-- A mesma regra da ligação: ficha com o mesmo WhatsApp e o mesmo primeiro
-- nome é DELA, e só é ligada. Mesmo WhatsApp com outro nome (mãe e filha no
-- mesmo número, ou um engano) não ganha ficha nova: o telefone já é de outra
-- ficha, e o salão resolve no balcão.
--
-- ── O TETO DO PLANO ───────────────────────────────────────────────────────
-- Conta como qualquer cliente (o gatilho do 22 continua valendo). Passou do
-- teto, a conta dela continua criada — só a ficha não nasce, e a função diz
-- por quê, sem derrubar a tela da cliente.
-- ===========================================================================

alter table public.clientes add column if not exists pelo_link boolean not null default false;

create or replace function public.cadastrar_minha_ficha(p_salao uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_perfil uuid := auth.uid(); v_nome text; v_tel text; v_email text; v_nasc date;
  v_ficha jsonb; v_cliente uuid; v_nacional text;
begin
  if v_perfil is null or p_salao is null then return null; end if;
  if not exists (select 1 from public.saloes s where s.id = p_salao and s.status = 'ativo') then
    return null;
  end if;
  -- Primeiro, o caminho de sempre: a ficha que já é dela, ou a que bate.
  v_ficha := public.ligar_minha_ficha(p_salao);
  if v_ficha->>'ficha' is not null then
    /* A ficha do balcão ganha o que a conta tem e ela não: o aniversário (é
       dele que sai Aniversariantes) e o e-mail. Só o VAZIO — a mesma regra
       do `agendar()` (09): quem manda na ficha é o salão. */
    update public.clientes c
       set nascimento = coalesce(c.nascimento, nullif(v_ficha->>'nascimento', '')::date),
           email      = coalesce(c.email, nullif(btrim(coalesce(v_ficha->>'email', '')), ''))
     where c.id = (v_ficha->>'ficha')::uuid and (c.nascimento is null or c.email is null);
    return v_ficha || jsonb_build_object('criada', false);
  end if;

  select p.nome, p.telefone, p.email, p.nascimento into v_nome, v_tel, v_email, v_nasc
    from public.perfis p where p.id = v_perfil;
  v_nacional := public.telefone_nacional(v_tel);
  if coalesce(v_nacional, '') = '' or length(v_nacional) < 10 or coalesce(btrim(v_nome), '') = '' then
    return v_ficha || jsonb_build_object('criada', false, 'motivo', 'sem_telefone');
  end if;
  -- O WhatsApp já é de outra ficha deste salão (com outro nome): não duplica.
  if exists (select 1 from public.clientes c
              where c.salao_id = p_salao
                and public.telefone_nacional(c.telefone) = v_nacional) then
    return v_ficha || jsonb_build_object('criada', false, 'motivo', 'telefone_de_outra_ficha');
  end if;

  begin
    insert into public.clientes (salao_id, perfil_id, nome, telefone, email, nascimento, pelo_link)
         values (p_salao, v_perfil, btrim(v_nome), v_nacional, v_email, v_nasc, true)
      returning id into v_cliente;
  exception when check_violation or unique_violation then
    -- O teto do plano (22) ou uma corrida com outra ficha: a conta fica.
    return v_ficha || jsonb_build_object('criada', false, 'motivo', 'nao_coube');
  end;
  return v_ficha || jsonb_build_object('ficha', v_cliente, 'criada', true);
end $$;

revoke all on function public.cadastrar_minha_ficha(uuid) from public, anon;
grant execute on function public.cadastrar_minha_ficha(uuid) to authenticated;

-- ###########################################################################
-- ## 49_remarcar.sql
-- ###########################################################################

-- ===========================================================================
-- 49_remarcar.sql — o salão remarca um horário
--
-- O pedido: "na onde entro para remarcar caso precise?" — e não havia onde.
-- A janela do atendimento só mudava a situação e a forma de pagamento. O
-- caminho que sobrava era cancelar e marcar outro no "+ Novo", e para sessão
-- de pacote isso estraga: o horário novo nasce como atendimento comum,
-- cobrando o serviço, solto do pacote.
--
-- Remarcar MOVE o próprio horário: o mesmo agendamento, com o mesmo pacote,
-- os mesmos serviços, o mesmo valor e a mesma duração, em outro dia, outra
-- hora ou com outra profissional. O lembrete da cliente e o da equipe vão
-- junto (os gatilhos do 21 reescrevem quando a hora ou a pessoa mudam).
--
-- ── O QUE O BANCO CONFERE ─────────────────────────────────────────────────
--   · quem: o balcão e a gestão remarcam qualquer horário; quem atende,
--     só o próprio, e para si mesma;
--   · o quê: só horário pendente ou confirmado, e para um instante que ainda
--     vem;
--   · onde: a mesma pergunta da agenda (`porque_nao_cabe`, 14), ignorando o
--     próprio horário. Fora da jornada dá para encaixar, com a confirmação de
--     quem remarca (e o encaixe fica com o nome dela); choque e bloqueio, não;
--   · o pacote: dentro da validade e nos dias da semana em que ele vale — as
--     mesmas regras de quando ele foi montado (43).
-- ===========================================================================

create or replace function public.remarcar_pelo_salao(
  p_agendamento uuid, p_inicio timestamptz,
  p_profissional uuid default null, p_encaixe boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a public.agendamentos%rowtype;
  v_prof uuid; v_fim timestamptz; v_fuso text; v_dia date;
  v_motivo text; v_encaixavel boolean := false; v_encaixe boolean := false;
  v_vence date; v_dias smallint[];
begin
  if auth.uid() is null then
    raise exception 'Entre de novo para remarcar.' using errcode = 'insufficient_privilege';
  end if;
  select * into a from public.agendamentos where id = p_agendamento for update;
  if a.id is null then
    raise exception 'Não achei este horário.' using errcode = 'check_violation';
  end if;
  v_prof := coalesce(p_profissional, a.profissional_id);
  if not public.ve_agenda_toda(a.salao_id) then
    if a.profissional_id is distinct from public.meu_profissional_id(a.salao_id)
       or v_prof is distinct from a.profissional_id then
      raise exception 'Só o balcão e a gestão remarcam o horário de outra pessoa.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  if a.arquivado_em is not null or a.status not in ('pendente', 'confirmado') then
    raise exception 'Só dá para remarcar um horário pendente ou confirmado.'
      using errcode = 'check_violation';
  end if;
  if p_inicio is null or p_inicio <= now() then
    raise exception 'Escolha um horário que ainda vai acontecer.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.profissionais pr
                  where pr.id = v_prof and pr.salao_id = a.salao_id and pr.ativo) then
    raise exception 'Escolha quem vai atender.' using errcode = 'check_violation';
  end if;

  v_fim := p_inicio + (a.fim - a.inicio);
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso from public.saloes s where s.id = a.salao_id;
  v_dia := (p_inicio at time zone v_fuso)::date;

  -- Sessão de pacote: a validade e os dias dele.
  if a.pacote_cliente_id is not null then
    select pc.vence_em, p.dias into v_vence, v_dias
      from public.pacote_clientes pc join public.pacotes p on p.id = pc.pacote_id
     where pc.id = a.pacote_cliente_id;
    if v_vence is not null and v_dia > v_vence then
      return jsonb_build_object('ok', false, 'encaixavel', false,
        'motivo', 'Passa da validade do pacote (vence em ' || to_char(v_vence, 'DD/MM') || ').');
    end if;
    if coalesce(cardinality(v_dias), 0) > 0
       and not (extract(dow from v_dia)::smallint = any(v_dias)) then
      return jsonb_build_object('ok', false, 'encaixavel', false,
        'motivo', 'O pacote vale só ' || public.dias_por_extenso(v_dias) || '.');
    end if;
  end if;

  v_motivo := public.porque_nao_cabe(v_prof, p_inicio, v_fim, a.id);
  if v_motivo is not null then
    -- Só a jornada o encaixe afrouxa (a mesma régua do "+ Novo").
    v_encaixavel := v_motivo like 'Fora da jornada%'
      and public.ha_choque(v_prof, p_inicio, v_fim, a.id) is null
      and public.ha_bloqueio(v_prof, p_inicio, v_fim) is null;
    if not (v_encaixavel and coalesce(p_encaixe, false)) then
      return jsonb_build_object('ok', false, 'motivo', v_motivo, 'encaixavel', v_encaixavel);
    end if;
    v_encaixe := true;
  end if;

  begin
    update public.agendamentos
       set inicio = p_inicio, fim = v_fim, profissional_id = v_prof,
           encaixe = v_encaixe,
           encaixe_por = case when v_encaixe then auth.uid() end
     where id = a.id;
  exception when exclusion_violation then
    return jsonb_build_object('ok', false, 'encaixavel', false,
      'motivo', 'Alguém acabou de marcar nesse horário. Escolha outro.');
  end;

  -- Outra profissional: a comissão passa a ser a dela (a do serviço, se
  -- houver; senão a da ficha dela) — a mesma conta de quando se marca.
  if v_prof is distinct from a.profissional_id then
    update public.agendamento_servicos asv
       set comissao_pct = coalesce(sv.comissao_pct, pr.comissao_pct, 0)
      from public.servicos sv, public.profissionais pr
     where asv.agendamento_id = a.id and sv.id = asv.servico_id and pr.id = v_prof;
  end if;

  -- O lembrete que tinha sido cancelado (remarcado em cima da hora, por
  -- exemplo) volta, para a hora nova. O que já saiu não se repete.
  perform public.refazer_lembrete_cliente(a.id);

  -- E a cliente fica sabendo: o horário de antes e o novo (52, depois que
  -- a plataforma liga o modelo e se o salão não desligou a chave). A guarda
  -- é para o banco que ainda não tem o 52.
  if to_regprocedure('public.avisar_remarcado(uuid,timestamptz,uuid)') is not null then
    perform public.avisar_remarcado(a.id, a.inicio, a.profissional_id);
  end if;

  return jsonb_build_object('ok', true, 'encaixe', v_encaixe,
    'data', to_char(p_inicio at time zone v_fuso, 'DD/MM/YYYY'),
    'hora', to_char(p_inicio at time zone v_fuso, 'HH24:MI'));
end $$;

revoke all on function public.remarcar_pelo_salao(uuid, timestamptz, uuid, boolean) from public, anon;
grant execute on function public.remarcar_pelo_salao(uuid, timestamptz, uuid, boolean) to authenticated;

/* ── QUEM ATENDEU ──────────────────────────────────────────────────────────
   "Como administrar para saber quem atendeu?" A comissão vai para a
   profissional do horário quando ele é concluído (16, 44). O Remarcar troca
   quem vai atender, mas só antes da hora — e a troca de última hora (a Ju
   faltou, a Bia atendeu às 14h) ficava com a Ju.

   Aqui o balcão diz quem atendeu, também depois da hora, enquanto o horário
   não foi concluído (concluído, a comissão já está contada). Horário de
   outro dia ainda por vir é com o Remarcar, que confere a agenda dela.

   A agenda ainda vale: se a Bia tinha outra cliente nesse mesmo horário, ela
   não atendeu esta — recusa. Fora da jornada dela (ou num bloqueio), ela
   atendeu assim mesmo: fica como ENCAIXE, o jeito que a agenda já tem de
   dizer isso. E a cliente não recebe mensagem: o horário dela não mudou. */
create or replace function public.trocar_quem_atende(p_agendamento uuid, p_profissional uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.agendamentos%rowtype; v_fuso text; v_nome text; v_encaixe boolean;
begin
  if auth.uid() is null then
    raise exception 'Entre de novo para trocar quem atendeu.' using errcode = 'insufficient_privilege';
  end if;
  select * into a from public.agendamentos where id = p_agendamento for update;
  if a.id is null then
    raise exception 'Não achei este horário.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(a.salao_id) then
    raise exception 'Só o balcão e a gestão trocam quem atendeu.' using errcode = 'insufficient_privilege';
  end if;
  if a.arquivado_em is not null or a.status not in ('pendente', 'confirmado', 'em_atendimento') then
    raise exception 'Só dá para trocar quem atendeu antes de concluir o horário.'
      using errcode = 'check_violation';
  end if;
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso from public.saloes s where s.id = a.salao_id;
  if (a.inicio at time zone v_fuso)::date > public.hoje_no_salao(a.salao_id) then
    raise exception 'Este horário é de outro dia: use Remarcar para escolher quem vai atender.'
      using errcode = 'check_violation';
  end if;
  select pr.nome into v_nome from public.profissionais pr
   where pr.id = p_profissional and pr.salao_id = a.salao_id and pr.ativo;
  if v_nome is null then
    raise exception 'Escolha quem atendeu.' using errcode = 'check_violation';
  end if;
  if p_profissional = a.profissional_id then
    return jsonb_build_object('ok', true, 'mudou', false, 'profissional', v_nome);
  end if;
  if public.ha_choque(p_profissional, a.inicio, a.fim, a.id) is not null then
    raise exception '% tem outro horário marcado nesse mesmo horário.', v_nome
      using errcode = 'check_violation';
  end if;

  v_encaixe := a.encaixe
    or not public.cabe_na_jornada(p_profissional, a.inicio, a.fim)
    or public.ha_bloqueio(p_profissional, a.inicio, a.fim) is not null;
  begin
    update public.agendamentos
       set profissional_id = p_profissional, encaixe = v_encaixe,
           encaixe_por = case when v_encaixe and not a.encaixe then auth.uid() else a.encaixe_por end
     where id = a.id;
  exception when exclusion_violation then
    raise exception '% tem outro horário marcado nesse mesmo horário.', v_nome
      using errcode = 'check_violation';
  end;

  -- A comissão passa a ser a dela (a do serviço, se houver; senão a da
  -- ficha dela) — a mesma conta do Remarcar.
  update public.agendamento_servicos asv
     set comissao_pct = coalesce(sv.comissao_pct, pr.comissao_pct, 0)
    from public.servicos sv, public.profissionais pr
   where asv.agendamento_id = a.id and sv.id = asv.servico_id and pr.id = p_profissional;

  -- O lembrete que ainda não saiu diz a profissional: refeito com a nova.
  perform public.refazer_lembrete_cliente(a.id);

  return jsonb_build_object('ok', true, 'mudou', true, 'profissional', v_nome, 'encaixe', v_encaixe);
end $$;

revoke all on function public.trocar_quem_atende(uuid, uuid) from public, anon;
grant execute on function public.trocar_quem_atende(uuid, uuid) to authenticated;

-- ###########################################################################
-- ## 50_pacote_excluir.sql
-- ###########################################################################

-- ===========================================================================
-- 50_pacote_excluir.sql — excluir um pacote que o salão não quer mais
--
-- O pedido: "no pacote não tem como excluir caso eu não queira mais; se
-- tiver pessoas agendadas no pacote, não consigo excluir — só excluir quando
-- não tiver pessoas nesse pacote".
--
-- ── AS TRÊS SITUAÇÕES ─────────────────────────────────────────────────────
--   · tem cliente NO pacote (vínculo não cancelado e ainda dentro da
--     validade): NÃO exclui, e diz quem — tire as clientes do pacote primeiro
--     (o "Tirar") ou espere vencer;
--   · nunca foi vendido: apaga de verdade, com os serviços dele;
--   · já foi vendido, e ninguém está mais nele: sai da lista (arquivado), e o
--     HISTÓRICO FICA. Apagar levaria junto, em cascata, os vínculos antigos —
--     e com eles o que diz que aquelas sessões eram do pacote e quanto ele
--     rendeu. Some da tela; não some do passado.
--
-- E o banco segura o resto: apagar direto (pela API, pela sincronização do
-- painel) um pacote com cliente ou com histórico é recusado.
-- ===========================================================================

alter table public.pacotes add column if not exists arquivado_em timestamptz;

-- Quem está NO pacote agora: não cancelado e ainda dentro da validade.
create or replace function public.clientes_no_pacote(p_pacote uuid)
returns text language sql stable security definer set search_path = public as $$
  select string_agg(c.nome, ', ' order by c.nome)
    from public.pacote_clientes pc join public.clientes c on c.id = pc.cliente_id
   where pc.pacote_id = p_pacote and pc.cancelado_em is null
     and pc.vence_em >= public.hoje_no_salao(c.salao_id)
$$;

create or replace function public.excluir_pacote(p_pacote uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_pac public.pacotes%rowtype; v_quem text;
begin
  select * into v_pac from public.pacotes where id = p_pacote;
  if v_pac.id is null then
    raise exception 'Não achei este pacote.' using errcode = 'check_violation';
  end if;
  if not public.e_gestor(v_pac.salao_id) then
    raise exception 'Só o proprietário ou um administrador exclui pacote.'
      using errcode = 'insufficient_privilege';
  end if;
  v_quem := public.clientes_no_pacote(p_pacote);
  if v_quem is not null then
    raise exception 'Ainda tem cliente neste pacote (%). Tire do pacote primeiro, ou espere vencer.', v_quem
      using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.pacote_clientes pc where pc.pacote_id = p_pacote) then
    delete from public.pacotes where id = p_pacote;
    return jsonb_build_object('ok', true, 'acao', 'apagado');
  end if;
  update public.pacotes set arquivado_em = now(), ativo = false where id = p_pacote;
  return jsonb_build_object('ok', true, 'acao', 'arquivado');
end $$;

-- A trava do banco: apagar direto não leva cliente nem histórico junto.
create or replace function public.tg_pacote_nao_apaga()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_quem text;
begin
  /* ⚠ EM CASCATA, DEIXA. Excluir a conta (36) apaga o salão, e o salão leva
     os pacotes junto — aí a trava não pode segurar, ou ninguém conseguiria
     mais excluir o próprio salão. A cascata chega aqui de dentro do gatilho
     da chave estrangeira (profundidade > 1); o apagar direto, com 1. */
  if pg_trigger_depth() > 1 then return old; end if;
  v_quem := public.clientes_no_pacote(old.id);
  if v_quem is not null then
    raise exception 'Ainda tem cliente neste pacote (%). Tire do pacote primeiro, ou espere vencer.', v_quem
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.pacote_clientes pc where pc.pacote_id = old.id) then
    raise exception 'Este pacote já foi vendido: ele sai da lista, mas o histórico fica. Use Excluir no pacote.'
      using errcode = 'check_violation';
  end if;
  return old;
end $$;
drop trigger if exists tg_pacote_nao_apaga on public.pacotes;
create trigger tg_pacote_nao_apaga before delete on public.pacotes
  for each row execute function public.tg_pacote_nao_apaga();

revoke all on function public.clientes_no_pacote(uuid) from public, anon, authenticated;
revoke all on function public.excluir_pacote(uuid) from public, anon;
grant execute on function public.excluir_pacote(uuid) to authenticated;

-- ###########################################################################
-- ## 51_google.sql
-- ###########################################################################

-- ===========================================================================
-- 51_google.sql — entrar com a conta Google: completar o cadastro
--
-- O pedido: "é possível fazer o cadastro com o Google?". O login em si é do
-- Supabase Auth (o provedor Google ligado no painel do Supabase, com o
-- Client ID e o Client Secret do Google Cloud — que NUNCA passam por aqui
-- nem pelo navegador). O que o Google entrega é só nome e e-mail.
--
-- E o salão precisa do WhatsApp (é por ele que a ficha é achada e que as
-- mensagens chegam) e do aniversário (Aniversariantes). Então, na primeira
-- vez, a tela pede os dois — e esta função os grava no perfil de quem está
-- logado. Depois disso o caminho é o de sempre: `cadastrar_minha_ficha`
-- (48) liga ou cria a ficha no salão, sem duplicar.
--
-- ── AS REGRAS ─────────────────────────────────────────────────────────────
--   · só a própria pessoa, logada;
--   · o WhatsApp que já é de OUTRA conta não é tomado (o índice único do
--     perfil não deixa, e a frase diz o que fazer: entrar com aquela conta);
--   · o perfil que já tem WhatsApp não troca por aqui;
--   · o aniversário só preenche o vazio (data impossível é recusada).
-- ===========================================================================

create or replace function public.completar_meu_cadastro(
  p_telefone text, p_nascimento date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_eu uuid := auth.uid(); v_tel text; p public.perfis%rowtype;
begin
  if v_eu is null then
    raise exception 'Entre de novo para completar o cadastro.' using errcode = 'insufficient_privilege';
  end if;
  select * into p from public.perfis where id = v_eu;
  if p.id is null then
    raise exception 'Não achei a sua conta. Entre de novo.' using errcode = 'check_violation';
  end if;
  if p_nascimento is not null and (p_nascimento > current_date or p_nascimento < date '1900-01-01') then
    raise exception 'Confira a data do aniversário.' using errcode = 'check_violation';
  end if;

  if p.telefone is null then
    v_tel := public.para_e164(p_telefone);
    if v_tel is null or length(public.so_digitos(v_tel)) < 12 then
      raise exception 'Falta o WhatsApp com DDD.' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.perfis o where o.telefone = v_tel and o.id <> v_eu) then
      raise exception 'Este WhatsApp já está em outra conta. Entre com o e-mail e a senha dela, ou fale com o salão.'
        using errcode = 'check_violation';
    end if;
    update public.perfis set telefone = v_tel where id = v_eu;
  end if;
  update public.perfis set nascimento = coalesce(nascimento, p_nascimento) where id = v_eu;

  select * into p from public.perfis where id = v_eu;
  return jsonb_build_object('nome', p.nome, 'telefone', p.telefone, 'email', p.email,
                            'nascimento', p.nascimento);
end $$;

revoke all on function public.completar_meu_cadastro(text, date) from public, anon;
grant execute on function public.completar_meu_cadastro(text, date) to authenticated;

-- ###########################################################################
-- ## 52_mensagens_novas.sql
-- ###########################################################################

-- ===========================================================================
-- 52_mensagens_novas.sql — as mensagens do Crediário e a de horário remarcado
--
-- O pedido: "todos os modelos foram enviados para a Meta, aguardando
-- aprovar — e no sistema tem que ter a opção de desligar pelo dono do salão;
-- no crediário, uma aba se ele quiser desligar cada mensagem".
--
-- ── O CREDIÁRIO (47): QUATRO AVISOS PARA A CLIENTE ──────────────────────
--   · COMPRA: logo depois da venda, o resumo — o valor e as parcelas;
--   · LEMBRETE: dois dias antes de cada vencimento, às 10h do salão;
--   · VENCE HOJE: no dia, às 10h, se a parcela ainda estiver em aberto;
--   · ATRASO: um dia depois, às 10h, se continuar em aberto. Uma vez só.
-- Pagou a parcela (ou a venda foi desfeita), o que estava na fila sai.
-- Pagou uma parte, o texto passa a dizer o que falta. Desfez o recebimento,
-- o aviso volta — se ainda der tempo.
--
-- ⚠ FRANQUIA PRÓPRIA, do plano do Crediário que a loja contratou (200 no
-- de entrada; "200 é para uma loja menor — e a loja maior?": o número mora
-- no catálogo, `adicionais.recursos.mensagens_crediario`, e um plano maior
-- é só mais uma linha lá). Elas não gastam a franquia do plano da agenda, e
-- a da agenda não as segura: o `mensagens_no_mes` deixa de contá-las e o
-- `pode_enviar_tipo` as mede à parte. Passou do limite no mês, as do
-- Crediário esperam o mês seguinte.
--
-- ── O HORÁRIO REMARCADO (49) ─────────────────────────────────────────────
-- O salão remarcou pelo painel (o dia ou a hora): a cliente recebe o
-- horário de antes e o novo. Trocar só a profissional não avisa. Remarcou de
-- novo antes de sair, só a última vai.
--
-- ── ⚠ SÓ SAEM COM OS MODELOS APROVADOS NA META ────────────────────────────
-- Como as do pacote (45): até a plataforma ver os modelos aprovados e ligar
-- no admin, NADA vai para a fila. Um interruptor para o Crediário, um para o
-- remarcado — aprovam em dias diferentes.
--
-- ── E O DONO ESCOLHE ─────────────────────────────────────────────────────
-- Uma chave para cada uma, ligadas por padrão (falam do que a cliente já
-- comprou ou marcou): `notifCredCompra`, `notifCredLembrete`,
-- `notifCredVenceHoje`, `notifCredAtraso` (na aba Mensagens do Crediário) e
-- `notifRemarcado` (em Notificações). Desligou, o que estava na fila sai.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) OS TIPOS, OS MODELOS E A FRANQUIA
-- ---------------------------------------------------------------------------
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check
  check (tipo in ('confirmacao','lembrete','resumo','novo','lembrete_equipe',
                  'pedido_novo','pedido_confirmado','pedido_a_caminho',
                  'pedido_pronto','pedido_cancelado',
                  'pacote_renovar','pacote_pagamento','pacote_agenda',
                  -- O Crediário e o remarcado (52).
                  'crediario_compra','crediario_lembrete','crediario_vence_hoje',
                  'crediario_atraso','remarcado'));

/* O modelo aprovado na Meta, por tipo — a lista inteira (a do 37 e as
   novas). Texto e ordem das variáveis no MODELOS.md. */
create or replace function public.modelo_de(p_tipo text)
returns text language sql stable set search_path = public as $$
  select case p_tipo
    when 'confirmacao'       then 'agendapro_confirmacao'
    when 'lembrete'          then 'agendapro_lembrete'
    when 'novo'              then 'agendapro_aviso_profissional'
    when 'resumo'            then 'agendapro_agenda_hoje'
    when 'lembrete_equipe'   then 'agendapro_lembrete_equipe'
    when 'pedido_novo'       then 'agendapro_pedido_novo'
    when 'pedido_confirmado' then 'agendapro_pedido_confirmado'
    when 'pedido_a_caminho'  then 'agendapro_pedido_a_caminho'
    when 'pedido_pronto'     then 'agendapro_pedido_pronto'
    when 'pedido_cancelado'  then 'agendapro_pedido_cancelado'
    -- A última sessão (tipo `pacote_renovar`, o nome antigo do aviso): o
    -- `agendapro_pacote_renovacao` a Meta aprovou como Marketing.
    when 'pacote_renovar'    then 'agendapro_pacote_ultima_sessao'
    when 'pacote_pagamento'  then 'agendapro_pacote_pagamento'
    when 'pacote_agenda'     then 'agendapro_pacote_agenda'
    when 'crediario_compra'     then 'agendapro_crediario_compra'
    when 'crediario_lembrete'   then 'agendapro_crediario_lembrete'
    when 'crediario_vence_hoje' then 'agendapro_crediario_vence_hoje'
    when 'crediario_atraso'     then 'agendapro_crediario_atraso'
    when 'remarcado'            then 'agendapro_remarcado'
  end
  || case when p_tipo in ('confirmacao', 'lembrete', 'novo', 'lembrete_equipe')
               and public.mensagens_com_pagamento()
          -- A confirmação se chama _valor1: o _pagamento dela a Meta passou
          -- para Marketing (MODELOS.md).
          then case when p_tipo = 'confirmacao' then '_valor1' else '_pagamento' end
          else '' end
$$;

-- A franquia do PLANO não conta as do Crediário: elas têm a delas.
create or replace function public.mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  with mes as (select c.ini from public.ciclo_mensagens(p_salao) c)
  select ((select count(*)
             from public.notificacoes n, mes
            where n.salao_id = p_salao
              and n.status in ('enviado','entregue','lido')
              and n.enviado_em >= mes.ini
              and n.tipo not like 'crediario%')
        + (select count(*)
             from public.campanha_destinatarios d, mes
            where d.salao_id = p_salao
              and d.status = 'enviado'
              and d.enviado_em >= mes.ini))::int
$$;

-- A franquia do Crediário: a do plano dele que a loja tem ativo (o maior,
-- se por um momento houver dois). Sem nenhum ativo (o teste grátis, que dá o
-- Crediário pelo plano), a do menor do catálogo. Contadas no mesmo ciclo do
-- plano da agenda.
drop function if exists public.crediario_teto_mensagens();
create or replace function public.crediario_teto_mensagens(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(
    max(nullif(ad.recursos->>'mensagens_crediario', '')::int)
      filter (where public.adicional_ativo(p_salao, ad.codigo)),
    min(nullif(ad.recursos->>'mensagens_crediario', '')::int),
    200)
    from public.adicionais ad where ad.recurso = 'crediario'
$$;

create or replace function public.crediario_mensagens_no_mes(p_salao uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int
    from public.notificacoes n, public.ciclo_mensagens(p_salao) c
   where n.salao_id = p_salao
     and n.status in ('enviado','entregue','lido')
     and n.enviado_em >= c.ini
     and n.tipo like 'crediario%'
$$;

/* A cota por tipo (22 e 37), com as novas: as do Crediário só com o módulo
   ativo e dentro das 200 dele; o remarcado vai para a cliente, então segue
   até o teto do plano, como a confirmação. */
create or replace function public.pode_enviar_tipo(p_salao uuid, p_tipo text)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_tipo like 'crediario%'
      then coalesce(public.recurso_bool(p_salao, 'crediario'), false)
           and public.crediario_mensagens_no_mes(p_salao) < public.crediario_teto_mensagens(p_salao)
    when public.teto_mensagens(p_salao) is null then true
    when p_tipo in ('confirmacao', 'lembrete', 'pedido_confirmado',
                    'pedido_a_caminho', 'pedido_pronto', 'pedido_cancelado',
                    'pacote_renovar', 'pacote_pagamento', 'pacote_agenda', 'remarcado')
      then public.mensagens_no_mes(p_salao) < public.teto_mensagens(p_salao)
    else public.mensagens_no_mes(p_salao) < public.teto_mensagens_salao(p_salao)
  end
$$;

-- ---------------------------------------------------------------------------
-- 2) OS INTERRUPTORES DA PLATAFORMA (depois de ver os modelos aprovados)
-- ---------------------------------------------------------------------------
create or replace function public.mensagens_do_crediario()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                    where a.chave = 'mensagensCrediario'), false)
$$;

create or replace function public.mensagem_remarcado()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                    where a.chave = 'mensagemRemarcado'), false)
$$;

-- ---------------------------------------------------------------------------
-- 3) O QUE DEVE ESTAR NA FILA, PARA UMA VENDA NO CREDIÁRIO
--
-- Uma função diz o que deve estar lá; os gatilhos a chamam sempre que algo
-- muda (a venda, um recebimento, a chave do salão, o interruptor). A gravação
-- é a do pacote (`gravar_aviso_do_pacote`, 45): cria, refaz o texto, volta
-- da fila cancelada, e nunca toca no que já saiu.
-- ---------------------------------------------------------------------------
create or replace function public.avisos_do_crediario(p_crediario uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record; pa record; v_tel text; v_nome text; v_pix text; v_pag text; v_comum text;
  v_motivo text; v_lista text; v_qual text; v_saldo numeric; v_venc text;
  v_10h timestamptz;
begin
  select cr.id, cr.salao_id, cr.cliente_id, cr.valor, cr.parcelas, cr.criado_em, cr.desfeito_em,
         cr.pagamento_id, sa.nome as casa, coalesce(sa.fuso, 'America/Sao_Paulo') as fuso, sa.cfg,
         c.nome as cliente, c.telefone
    into r
    from public.crediarios cr
    join public.saloes sa on sa.id = cr.salao_id
    join public.clientes c on c.id = cr.cliente_id
   where cr.id = p_crediario;
  if r.id is null then return; end if;
  -- A venda ainda está nascendo (as parcelas entram antes do pagamento que
  -- fecha a comanda): espera o fim, quando o `pagamento_id` chega.
  if r.pagamento_id is null and r.desfeito_em is null then return; end if;

  v_tel := public.so_digitos(r.telefone);
  v_nome := public.variavel_limpa(split_part(btrim(coalesce(r.cliente, 'cliente')), ' ', 1));
  -- A chave Pix só quando o salão aceita Pix (como o pacote, 45).
  v_pix := case when coalesce(r.cfg->'pagamentos'->'formas', '[]'::jsonb) ? 'pix'
                then 'Pix (chave: ' || nullif(btrim(coalesce(r.cfg->'pagamentos'->>'pix', '')), '') || ')' end;
  v_pag := coalesce(v_pix, 'combine com o salão');

  v_comum := case
    when r.desfeito_em is not null then 'venda desfeita'
    when not public.mensagens_do_crediario() then 'mensagens do crediário desligadas'
    when not coalesce(public.recurso_bool(r.salao_id, 'crediario'), false) then 'módulo Crediário inativo'
    when coalesce(v_tel, '') = '' then 'cliente sem telefone'
  end;

  -- COMPRA: logo depois da venda. Só a venda de agora: ligar o interruptor
  -- não manda resumo de compra antiga (a folga de -1 hora: nasce até uma
  -- hora depois da venda, e não depois disso).
  select string_agg(pa2.numero || 'ª ' || public.reais(pa2.valor) || ' em '
                    || to_char(pa2.vence_em, 'DD/MM'), '; ' order by pa2.numero)
    into v_lista
    from public.crediario_parcelas pa2 where pa2.crediario_id = r.id;
  v_motivo := coalesce(v_comum, case
    when not public.notif_liga(r.salao_id, 'notifCredCompra', true) then 'desligado pelo salão' end);
  perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_compra', 'crediario_compra:' || r.id,
    v_motivo, r.criado_em, interval '-1 hour', r.criado_em + interval '6 hours',
    v_tel, r.cliente_id, null,
    'Olá, ' || v_nome || '. Resumo da sua compra no crediário em ' || r.casa || '.'
      || E'\n\n💰 Valor no crediário: ' || public.reais(r.valor)
      || E'\n🗓️ Parcelas: ' || coalesce(v_lista, '—')
      || E'\n\nGuarde esta mensagem. Mensagem automática do sistema do salão.',
    jsonb_build_array(v_nome, public.variavel_limpa(r.casa),
                      public.variavel_limpa(public.reais(r.valor)), public.variavel_limpa(v_lista)));

  -- AS PARCELAS: lembrete, vence hoje e atraso, cada uma com a sua hora.
  for pa in select p.id, p.numero, p.valor, p.vence_em from public.crediario_parcelas p
             where p.crediario_id = r.id order by p.numero loop
    v_saldo := public.saldo_da_parcela(pa.id);
    v_qual := pa.numero || ' de ' || r.parcelas;
    v_venc := to_char(pa.vence_em, 'DD/MM');

    -- Lembrete: dois dias antes, às 10h.
    v_10h := ((pa.vence_em - 2) + time '10:00') at time zone r.fuso;
    v_motivo := coalesce(v_comum, case
      when v_saldo <= 0 then 'parcela paga'
      when not public.notif_liga(r.salao_id, 'notifCredLembrete', true) then 'desligado pelo salão' end);
    perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_lembrete', 'crediario_lembrete:' || pa.id,
      v_motivo, v_10h, interval '0', (pa.vence_em + time '00:00') at time zone r.fuso,
      v_tel, r.cliente_id, null,
      'Olá, ' || v_nome || '. Lembrete da parcela ' || v_qual || ' do seu crediário em ' || r.casa || '.'
        || E'\n\n💰 Valor: ' || public.reais(v_saldo)
        || E'\n📅 Vencimento: ' || v_venc
        || E'\n💳 Pagamento: ' || v_pag
        || E'\n\nSe você já pagou, desconsidere esta mensagem. Mensagem automática do sistema do salão.',
      jsonb_build_array(v_nome, v_qual, public.variavel_limpa(r.casa),
                        public.variavel_limpa(public.reais(v_saldo)), v_venc, public.variavel_limpa(v_pag)));

    -- Vence hoje: no dia, às 10h.
    v_10h := (pa.vence_em + time '10:00') at time zone r.fuso;
    v_motivo := coalesce(v_comum, case
      when v_saldo <= 0 then 'parcela paga'
      when not public.notif_liga(r.salao_id, 'notifCredVenceHoje', true) then 'desligado pelo salão' end);
    perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_vence_hoje', 'crediario_vence_hoje:' || pa.id,
      v_motivo, v_10h, interval '0', ((pa.vence_em + 1) + time '00:00') at time zone r.fuso,
      v_tel, r.cliente_id, null,
      'Olá, ' || v_nome || '. A parcela ' || v_qual || ' do seu crediário em ' || r.casa || ' vence hoje.'
        || E'\n\n💰 Valor: ' || public.reais(v_saldo)
        || E'\n💳 Pagamento: ' || v_pag
        || E'\n\nSe você já pagou, desconsidere esta mensagem. Mensagem automática do sistema do salão.',
      jsonb_build_array(v_nome, v_qual, public.variavel_limpa(r.casa),
                        public.variavel_limpa(public.reais(v_saldo)), public.variavel_limpa(v_pag)));

    -- Atraso: um dia depois, às 10h. Uma vez só (a chave é da parcela).
    v_10h := ((pa.vence_em + 1) + time '10:00') at time zone r.fuso;
    v_motivo := coalesce(v_comum, case
      when v_saldo <= 0 then 'parcela paga'
      when not public.notif_liga(r.salao_id, 'notifCredAtraso', true) then 'desligado pelo salão' end);
    perform public.gravar_aviso_do_pacote(r.salao_id, 'crediario_atraso', 'crediario_atraso:' || pa.id,
      v_motivo, v_10h, interval '0', ((pa.vence_em + 2) + time '00:00') at time zone r.fuso,
      v_tel, r.cliente_id, null,
      'Olá, ' || v_nome || '. A parcela ' || v_qual || ' do seu crediário em ' || r.casa
        || ' venceu em ' || v_venc || ' e ainda aparece em aberto.'
        || E'\n\n💰 Valor: ' || public.reais(v_saldo)
        || E'\n💳 Pagamento: ' || v_pag
        || E'\n\nSe você já pagou, desconsidere esta mensagem. Em caso de dúvida, fale com o salão. Mensagem automática do sistema do salão.',
      jsonb_build_array(v_nome, v_qual, public.variavel_limpa(r.casa), v_venc,
                        public.variavel_limpa(public.reais(v_saldo)), public.variavel_limpa(v_pag)));
  end loop;
end $$;

/* As vendas de um salão (ou de todos) que ainda têm parcela em aberto: ligou
   ou desligou uma chave, ou o interruptor, a fila de todas é refeita. */
create or replace function public.refazer_avisos_do_crediario(p_salao uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare x record; v_n int := 0;
begin
  for x in select cr.id from public.crediarios cr
            where (p_salao is null or cr.salao_id = p_salao)
              and cr.desfeito_em is null
              and exists (select 1 from public.crediario_parcelas pa
                           where pa.crediario_id = cr.id and public.saldo_da_parcela(pa.id) > 0) loop
    perform public.avisos_do_crediario(x.id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Os gatilhos: a venda fechou (o pagamento chegou) ou foi desfeita…
create or replace function public.tg_crediario_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.avisos_do_crediario(new.id);
  return new;
end $$;
drop trigger if exists tg_crediario_avisos on public.crediarios;
create trigger tg_crediario_avisos
  after update of pagamento_id, desfeito_em on public.crediarios
  for each row execute function public.tg_crediario_avisos();

-- …entrou um recebimento, ou um foi desfeito…
create or replace function public.tg_crediario_receb_avisos()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.avisos_do_crediario(new.crediario_id);
  return new;
end $$;
drop trigger if exists tg_crediario_receb_avisos on public.crediario_recebimentos;
create trigger tg_crediario_receb_avisos
  after insert or update of desfeito_em on public.crediario_recebimentos
  for each row execute function public.tg_crediario_receb_avisos();

-- …ou o dono mexeu numa das quatro chaves.
create or replace function public.tg_salao_avisos_do_crediario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.cfg->'notifCredCompra') is distinct from (new.cfg->'notifCredCompra')
     or (old.cfg->'notifCredLembrete') is distinct from (new.cfg->'notifCredLembrete')
     or (old.cfg->'notifCredVenceHoje') is distinct from (new.cfg->'notifCredVenceHoje')
     or (old.cfg->'notifCredAtraso') is distinct from (new.cfg->'notifCredAtraso')
     or (old.cfg->'pagamentos') is distinct from (new.cfg->'pagamentos') then
    perform public.refazer_avisos_do_crediario(new.id);
  end if;
  return new;
end $$;
drop trigger if exists tg_salao_avisos_do_crediario on public.saloes;
create trigger tg_salao_avisos_do_crediario
  after update of cfg on public.saloes
  for each row execute function public.tg_salao_avisos_do_crediario();

/* A aba Mensagens do Crediário: se já estão saindo, quanto da franquia foi
   usado, e as quatro chaves. Lê quem vê o crediário (o balcão e a gestão). */
create or replace function public.crediario_mensagens(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem o crediário.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object(
    'liberadas', public.mensagens_do_crediario(),
    'usadas', public.crediario_mensagens_no_mes(p_salao),
    'teto', public.crediario_teto_mensagens(p_salao),
    'compra', public.notif_liga(p_salao, 'notifCredCompra', true),
    'lembrete', public.notif_liga(p_salao, 'notifCredLembrete', true),
    'venceHoje', public.notif_liga(p_salao, 'notifCredVenceHoje', true),
    'atraso', public.notif_liga(p_salao, 'notifCredAtraso', true));
end $$;

-- ---------------------------------------------------------------------------
-- 4) O HORÁRIO REMARCADO
--
-- Chamado pelo `remarcar_pelo_salao` (49), com o horário e a profissional
-- de antes. Mudou o dia ou a hora, e o horário novo é no futuro: vai agora.
-- Remarcou de novo antes de sair, a anterior sai da fila — só a última vale.
-- ---------------------------------------------------------------------------
create or replace function public.avisar_remarcado(p_agendamento uuid, p_antes timestamptz,
                                                   p_prof_antes uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare a record; v_tel text; d jsonb; v_antes text;
  v_dias text[] := array['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
begin
  select ag.id, ag.salao_id, ag.cliente_id, ag.inicio, ag.status, ag.profissional_id,
         coalesce(sa.fuso, 'America/Sao_Paulo') as fuso, c.telefone
    into a
    from public.agendamentos ag
    join public.saloes sa on sa.id = ag.salao_id
    left join public.clientes c on c.id = ag.cliente_id
   where ag.id = p_agendamento;
  if a.id is null or a.inicio <= now() or a.status not in ('pendente', 'confirmado') then
    return false;
  end if;
  -- Só quando muda o DIA ou a HORA: trocar só a profissional (num pacote, a
  -- Bia no lugar da Ju) não é motivo para mensagem — o horário dela é o mesmo.
  if a.inicio = p_antes then return false; end if;
  if not public.mensagem_remarcado() or not public.notif_liga(a.salao_id, 'notifRemarcado', true) then
    return false;
  end if;
  v_tel := public.so_digitos(a.telefone);
  if coalesce(v_tel, '') = '' then return false; end if;

  d := public.pecas_agendamento(a.id);
  v_antes := v_dias[extract(dow from (p_antes at time zone a.fuso))::int + 1] || ', '
             || to_char(p_antes at time zone a.fuso, 'DD/MM "às" HH24:MI');

  update public.notificacoes
     set status = 'cancelado', motivo = 'remarcado de novo'
   where agendamento_id = a.id and tipo = 'remarcado' and status = 'pendente';

  insert into public.notificacoes
    (salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave, modelo, variaveis)
  values (a.salao_id, 'remarcado', v_tel, a.cliente_id, a.id, now(),
          'Olá, ' || (d->>'primeiro') || '. Seu horário no ' || (d->>'casa') || ' foi remarcado.'
            || E'\n\n🔁 Antes: ' || v_antes
            || E'\n📅 Nova data: ' || (d->>'data')
            || E'\n🕐 Novo horário: ' || (d->>'hora')
            || E'\n✂️ Serviço: ' || (d->>'servico')
            || E'\n👤 Profissional: ' || (d->>'prof')
            || E'\n\nSe o novo horário não for bom para você, fale com o salão. Aviso automático do sistema de agendamento.',
          'remarcado:' || a.id || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
          public.modelo_de('remarcado'),
          jsonb_build_array(public.variavel_limpa(d->>'primeiro'), public.variavel_limpa(d->>'casa'),
                            public.variavel_limpa(v_antes), public.variavel_limpa(d->>'data'),
                            public.variavel_limpa(d->>'hora'), public.variavel_limpa(d->>'servico'),
                            public.variavel_limpa(d->>'prof')))
  on conflict (salao_id, chave) do nothing;
  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 5) A PLATAFORMA LIGA E DESLIGA
-- ---------------------------------------------------------------------------
create or replace function public.definir_mensagens_do_crediario(p_ligar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.is_super() then
    raise exception 'Só a plataforma liga os modelos de mensagem.' using errcode = 'insufficient_privilege';
  end if;
  insert into public.plataforma_ajustes (chave, valor, atualizado_em)
       values ('mensagensCrediario', to_jsonb(coalesce(p_ligar, false)), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  -- Desligou: o que estava na fila sai. Ligou: as vendas em aberto ganham os
  -- avisos das parcelas que ainda vêm (o resumo de compra antiga, não).
  v_n := public.refazer_avisos_do_crediario(null);
  if not coalesce(p_ligar, false) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'mensagens do crediário desligadas'
     where tipo like 'crediario%' and status = 'pendente';
  end if;
  return jsonb_build_object('ligado', public.mensagens_do_crediario(), 'vendas', v_n);
end $$;

create or replace function public.definir_mensagem_remarcado(p_ligar boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma liga os modelos de mensagem.' using errcode = 'insufficient_privilege';
  end if;
  insert into public.plataforma_ajustes (chave, valor, atualizado_em)
       values ('mensagemRemarcado', to_jsonb(coalesce(p_ligar, false)), now())
  on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  if not coalesce(p_ligar, false) then
    update public.notificacoes
       set status = 'cancelado', motivo = 'mensagem de remarcado desligada'
     where tipo = 'remarcado' and status = 'pendente';
  end if;
  return jsonb_build_object('ligado', public.mensagem_remarcado());
end $$;

-- O que o admin lê (21), com os dois interruptores novos.
create or replace function public.ajustes_da_plataforma()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os ajustes.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object('mensagensComPagamento', public.mensagens_com_pagamento(),
    'mensagensPacote', coalesce((select a.valor = 'true'::jsonb from public.plataforma_ajustes a
                                  where a.chave = 'mensagensPacote'), false),
    'mensagensCrediario', public.mensagens_do_crediario(),
    'mensagemRemarcado', public.mensagem_remarcado());
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.crediario_teto_mensagens(uuid) from public, anon, authenticated;
revoke all on function public.crediario_mensagens_no_mes(uuid) from public, anon, authenticated;
revoke all on function public.pode_enviar_tipo(uuid, text) from public, anon, authenticated;
revoke all on function public.mensagens_no_mes(uuid) from public, anon;
grant execute on function public.mensagens_no_mes(uuid) to authenticated;
revoke all on function public.mensagens_do_crediario() from public, anon;
grant execute on function public.mensagens_do_crediario() to authenticated;
revoke all on function public.mensagem_remarcado() from public, anon;
grant execute on function public.mensagem_remarcado() to authenticated;
revoke all on function public.avisos_do_crediario(uuid) from public, anon, authenticated;
revoke all on function public.refazer_avisos_do_crediario(uuid) from public, anon, authenticated;
revoke all on function public.tg_crediario_avisos() from public, anon, authenticated;
revoke all on function public.tg_crediario_receb_avisos() from public, anon, authenticated;
revoke all on function public.tg_salao_avisos_do_crediario() from public, anon, authenticated;
revoke all on function public.avisar_remarcado(uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.crediario_mensagens(uuid) from public, anon;
grant execute on function public.crediario_mensagens(uuid) to authenticated;
revoke all on function public.definir_mensagens_do_crediario(boolean) from public, anon;
grant execute on function public.definir_mensagens_do_crediario(boolean) to authenticated;
revoke all on function public.definir_mensagem_remarcado(boolean) from public, anon;
grant execute on function public.definir_mensagem_remarcado(boolean) to authenticated;
revoke all on function public.ajustes_da_plataforma() from public, anon;
grant execute on function public.ajustes_da_plataforma() to authenticated;

-- ###########################################################################
-- ## 53_pedidos_loja.sql
-- ###########################################################################

-- ===========================================================================
-- 53_pedidos_loja.sql — o pedido da loja, gravado, e a venda no painel
--
-- O pedido do dono: "caso alguém se interesse pelos produtos e faça seu
-- pedido, no ícone do WhatsApp... a pessoa tem que fazer seu cadastro e
-- depois enviar no WhatsApp do jeito que está, e quando clicar enviar vai
-- aparecer no painel, no módulo pedidos, que aí eu tenho que confirmar a
-- lista e como será o pagamento — e o crediário, se tiver o módulo".
--
-- ── O CAMINHO ─────────────────────────────────────────────────────────────
--   1. a cliente monta o carrinho no link e toca em Enviar pelo WhatsApp;
--   2. sem conta, faz o cadastro (o link pede); a ficha nasce ou é ligada;
--   3. o pedido é GRAVADO aqui (`fazer_pedido_loja`), com número, e o
--      WhatsApp abre com o texto de sempre + "Pedido nº 12" — a conversa
--      continua entre as duas pessoas;
--   4. no painel, a aba Pedidos lista (`pedidos_loja_painel`); o balcão confere
--      os itens e VENDE: Pix, dinheiro ou cartão (`vender_pedido_loja`: a
--      comanda fecha e o estoque baixa, como qualquer venda) ou Crediário
--      (`vender_pedido_no_crediario`: a venda a prazo do 47, de uma vez);
--   5. não fechou: Cancelar.
--
-- ── ⚠ O PREÇO É O DO BANCO ────────────────────────────────────────────────
-- A página manda só quais produtos e quantos. O texto do WhatsApp a cliente
-- pode editar antes de enviar; o pedido gravado, não. E a venda lê o preço do
-- cadastro de novo — quem vende confere, e não confia no que chegou.
--
-- ── ⚠ ISTO NÃO MEXE NO RESTAURANTE ────────────────────────────────────────
-- O modo Pedidos do restaurante (37) tem as tabelas e o andamento dele
-- (entrega, preparo). Este é da loja dos outros tipos: sem entrega, sem
-- andamento — chegou, vendeu ou cancelou.
--
-- ── O ESTOQUE ─────────────────────────────────────────────────────────────
-- Só baixa na venda (a comanda fechada, 26). Pedido que não fecha não segura
-- produto.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) AS TABELAS
-- ---------------------------------------------------------------------------
create table if not exists public.pedidos_loja (
  id               uuid primary key default gen_random_uuid(),
  salao_id         uuid not null references public.saloes(id) on delete cascade,
  numero           int  not null,
  cliente_id       uuid not null references public.clientes(id) on delete cascade,
  perfil_id        uuid references public.perfis(id) on delete set null,
  status           text not null default 'novo' check (status in ('novo', 'vendido', 'cancelado')),
  cupom            text,
  total_estimado   numeric(10,2) not null default 0,
  criado_em        timestamptz not null default now(),
  vendido_em       timestamptz,
  vendido_por      uuid references public.perfis(id) on delete set null,
  comanda_id       uuid references public.comandas(id) on delete set null,
  crediario_id     uuid references public.crediarios(id) on delete set null,
  cancelado_em     timestamptz,
  cancelado_por    uuid references public.perfis(id) on delete set null,
  cancelado_motivo text,
  unique (salao_id, numero)
);
create index if not exists ix_pedido_loja_salao on public.pedidos_loja(salao_id, status, criado_em desc);
create index if not exists ix_pedido_loja_cliente on public.pedidos_loja(cliente_id);

create table if not exists public.pedido_loja_itens (
  id          uuid primary key default gen_random_uuid(),
  pedido_id   uuid not null references public.pedidos_loja(id) on delete cascade,
  produto_id  uuid references public.produtos(id) on delete set null,
  descricao   text not null,
  qtd         numeric(10,2) not null check (qtd > 0),
  preco_unit  numeric(10,2) not null check (preco_unit >= 0)
);
create index if not exists ix_pedido_loja_itens on public.pedido_loja_itens(pedido_id);

-- O balcão e a gestão leem; a cliente lê os dela. Ninguém escreve pela API —
-- só as funções abaixo.
alter table public.pedidos_loja enable row level security;
alter table public.pedido_loja_itens enable row level security;
drop policy if exists pedidos_loja_ler on public.pedidos_loja;
create policy pedidos_loja_ler on public.pedidos_loja for select to authenticated
  using (public.ve_agenda_toda(salao_id) or perfil_id = auth.uid());
drop policy if exists pedido_loja_itens_ler on public.pedido_loja_itens;
create policy pedido_loja_itens_ler on public.pedido_loja_itens for select to authenticated
  using (exists (select 1 from public.pedidos_loja p where p.id = pedido_id
                  and (public.ve_agenda_toda(p.salao_id) or p.perfil_id = auth.uid())));
revoke all on public.pedidos_loja, public.pedido_loja_itens from anon, authenticated;
grant select on public.pedidos_loja, public.pedido_loja_itens to authenticated;

-- ---------------------------------------------------------------------------
-- 2) A CLIENTE FAZ O PEDIDO (a porta do link)
--
-- Só com conta: é o cadastro que diz quem pediu (e o pedido vai para a ficha
-- dela). Sem ficha no salão, ela nasce aqui (48). No máximo 5 pedidos
-- esperando por cliente: o resto é a conversa do WhatsApp.
--
-- ⚠ CORRIGIU E MANDOU DE NOVO: o MESMO pedido. A loja sempre deixou a
-- cliente ajustar o carrinho e mandar de novo (o cupom não é gasto outra
-- vez). Com o pedido gravado, mandar de novo com `p_pedido` (o dela, ainda
-- esperando) troca os itens do mesmo número — e não enche o painel de
-- pedidos repetidos. Já vendido ou cancelado pelo salão, nasce outro.
-- ---------------------------------------------------------------------------
drop function if exists public.fazer_pedido_loja(uuid, jsonb, text);
create or replace function public.fazer_pedido_loja(p_salao uuid, p_itens jsonb, p_cupom text default null,
                                                    p_pedido uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_eu uuid := auth.uid(); v_cfg jsonb; f jsonb; v_cliente uuid; v_tel text;
  v_id uuid; v_num int; v_total numeric := 0; x record; v_ant public.pedidos_loja%rowtype;
begin
  if v_eu is null then
    raise exception 'Faça seu cadastro (ou entre) para enviar o pedido.' using errcode = 'insufficient_privilege';
  end if;
  select s.cfg into v_cfg from public.saloes s where s.id = p_salao and s.status = 'ativo';
  if not found then
    raise exception 'Este salão não está recebendo pedidos agora.' using errcode = 'check_violation';
  end if;
  if lower(btrim(coalesce(v_cfg->>'loja', 'true'))) in ('false', 'f', '0', 'no', 'nao', 'não') then
    raise exception 'Este salão não está recebendo pedidos agora.' using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'O carrinho está vazio.' using errcode = 'check_violation';
  end if;
  if jsonb_array_length(p_itens) > 50 then
    raise exception 'Pedido grande demais: combine com o salão pelo WhatsApp.' using errcode = 'check_violation';
  end if;

  -- A ficha dela neste salão: a ligada à conta; senão, o cadastro (48).
  select c.id into v_cliente from public.clientes c
   where c.salao_id = p_salao and c.perfil_id = v_eu order by c.criado_em limit 1;
  if v_cliente is null then
    f := public.cadastrar_minha_ficha(p_salao);
    v_cliente := nullif(f->>'ficha', '')::uuid;
    if v_cliente is null and f->>'motivo' = 'telefone_de_outra_ficha' then
      -- O WhatsApp dela já está numa ficha do salão: o pedido vai para essa.
      select public.telefone_nacional(p.telefone) into v_tel from public.perfis p where p.id = v_eu;
      select c.id into v_cliente from public.clientes c
       where c.salao_id = p_salao and public.telefone_nacional(c.telefone) = v_tel
       order by c.criado_em limit 1;
    end if;
    if v_cliente is null then
      if f->>'motivo' = 'sem_telefone' then
        raise exception 'Falta o seu WhatsApp no cadastro: complete e envie de novo.' using errcode = 'check_violation';
      end if;
      raise exception 'Não consegui fazer seu cadastro neste salão. Fale com ele pelo WhatsApp.'
        using errcode = 'check_violation';
    end if;
  end if;

  -- O pedido que ela já mandou e ainda espera: é ele que muda.
  if p_pedido is not null then
    select * into v_ant from public.pedidos_loja p
     where p.id = p_pedido and p.salao_id = p_salao and p.perfil_id = v_eu for update;
    if v_ant.id is not null and v_ant.status = 'novo' then
      v_id := v_ant.id; v_num := v_ant.numero;
      delete from public.pedido_loja_itens where pedido_id = v_id;
      update public.pedidos_loja
         set cupom = coalesce(nullif(left(btrim(coalesce(p_cupom, '')), 40), ''), cupom)
       where id = v_id;
    end if;
  end if;

  if v_id is null then
    if (select count(*) from public.pedidos_loja p
         where p.salao_id = p_salao and p.cliente_id = v_cliente and p.status = 'novo') >= 5 then
      raise exception 'Você já tem pedidos esperando o salão. Aguarde a resposta pelo WhatsApp.'
        using errcode = 'check_violation';
    end if;
    -- O número do pedido, um por salão, sem pular nem repetir.
    perform pg_advisory_xact_lock(hashtext('pedido_loja:' || p_salao::text));
    select coalesce(max(p.numero), 0) + 1 into v_num from public.pedidos_loja p where p.salao_id = p_salao;
    insert into public.pedidos_loja (salao_id, numero, cliente_id, perfil_id, cupom)
         values (p_salao, v_num, v_cliente, v_eu, nullif(left(btrim(coalesce(p_cupom, '')), 40), ''))
      returning id into v_id;
  end if;

  -- Os itens: só o que a loja do link mostra, com o preço do cadastro. O
  -- mesmo produto em duas linhas vira uma, com a soma.
  for x in
    select pr.id, pr.nome, pr.preco, sum(greatest(1, least(99, coalesce(nullif(i->>'qtd', '')::numeric, 1))))::numeric as qtd
      from jsonb_array_elements(p_itens) i
      join public.produtos pr on pr.id = nullif(i->>'id', '')::uuid
     where pr.salao_id = p_salao and pr.ativo and pr.venda_online
     group by pr.id, pr.nome, pr.preco
  loop
    insert into public.pedido_loja_itens (pedido_id, produto_id, descricao, qtd, preco_unit)
         values (v_id, x.id, x.nome, least(x.qtd, 99), coalesce(x.preco, 0));
    v_total := v_total + least(x.qtd, 99) * coalesce(x.preco, 0);
  end loop;
  if not exists (select 1 from public.pedido_loja_itens where pedido_id = v_id) then
    raise exception 'Estes produtos não estão mais na loja. Atualize a página.' using errcode = 'check_violation';
  end if;
  update public.pedidos_loja set total_estimado = round(v_total, 2) where id = v_id;
  return jsonb_build_object('ok', true, 'pedido', v_id, 'numero', v_num, 'total', round(v_total, 2),
                            'atualizado', v_id = p_pedido);
end $$;

-- ---------------------------------------------------------------------------
-- 3) O PAINEL: A LISTA
-- Os que esperam, e os vendidos ou cancelados dos últimos 30 dias.
-- ---------------------------------------------------------------------------
create or replace function public.pedidos_loja_painel(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem os pedidos.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'numero', p.numero, 'status', p.status, 'criadoEm', p.criado_em,
             'clienteId', p.cliente_id, 'cliente', c.nome, 'telefone', c.telefone,
             'cupom', p.cupom, 'total', p.total_estimado,
             'vendidoEm', p.vendido_em, 'comandaId', p.comanda_id, 'crediarioId', p.crediario_id,
             'canceladoEm', p.cancelado_em, 'motivo', p.cancelado_motivo,
             -- O que foi VENDIDO (a comanda): o total e as formas de pagamento.
             'vendaTotal', (select ct.total from public.comandas_totais ct where ct.id = p.comanda_id),
             'vendaFormas', (select jsonb_agg(distinct pg.forma) from public.pagamentos pg
                              where pg.comanda_id = p.comanda_id),
             'itens', coalesce((select jsonb_agg(jsonb_build_object(
                         'produtoId', i.produto_id, 'descricao', i.descricao,
                         'qtd', i.qtd, 'preco', i.preco_unit) order by i.descricao)
                         from public.pedido_loja_itens i where i.pedido_id = p.id), '[]'::jsonb))
           order by (p.status = 'novo') desc, p.criado_em desc)
      from public.pedidos_loja p
      join public.clientes c on c.id = p.cliente_id
     where p.salao_id = p_salao
       and (p.status = 'novo' or p.criado_em > now() - interval '30 days')), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 4) VENDER
--
-- O balcão manda a lista conferida (produtos e quantidades — tirou o que não
-- tem, mudou quantidade). O preço é lido do cadastro aqui. A venda é uma
-- comanda como qualquer outra, montada e fechada de uma vez: entra no
-- faturamento, no caixa aberto e na comissão, e o estoque baixa (15, 17, 26).
-- ---------------------------------------------------------------------------
create or replace function public.pedido_para_vender(p_pedido uuid)
returns public.pedidos_loja language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype;
begin
  select * into p from public.pedidos_loja where id = p_pedido for update;
  if p.id is null then
    raise exception 'Pedido não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(p.salao_id) then
    raise exception 'Só o balcão e a gestão vendem.' using errcode = 'insufficient_privilege';
  end if;
  if p.status <> 'novo' then
    raise exception 'Este pedido já foi %.', case when p.status = 'vendido' then 'vendido' else 'cancelado' end
      using errcode = 'check_violation';
  end if;
  return p;
end $$;

create or replace function public.vender_pedido_loja(
  p_pedido uuid, p_itens jsonb, p_forma text, p_desconto numeric default 0, p_profissional uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype; v_com uuid; x jsonb; v_qtd numeric; v_preco numeric; v_desc text; v_total numeric;
begin
  p := public.pedido_para_vender(p_pedido);
  if coalesce(p_forma, '') not in ('pix', 'dinheiro', 'debito', 'credito', 'transferencia') then
    raise exception 'Escolha como ela pagou: Pix, dinheiro, cartão ou transferência.' using errcode = 'check_violation';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Deixe pelo menos um item na venda.' using errcode = 'check_violation';
  end if;
  if p_profissional is not null and not exists (
       select 1 from public.profissionais pr where pr.id = p_profissional and pr.salao_id = p.salao_id) then
    raise exception 'Quem vendeu não é deste salão.' using errcode = 'check_violation';
  end if;

  insert into public.comandas (salao_id, cliente_id, status) values (p.salao_id, p.cliente_id, 'aberta')
    returning id into v_com;
  for x in select * from jsonb_array_elements(p_itens) loop
    v_qtd := coalesce(nullif(x->>'qtd', '')::numeric, 1);
    if v_qtd <= 0 or v_qtd > 999 then
      raise exception 'Confira a quantidade dos itens.' using errcode = 'check_violation';
    end if;
    select pr.nome, pr.preco into v_desc, v_preco from public.produtos pr
     where pr.id = nullif(x->>'id', '')::uuid and pr.salao_id = p.salao_id;
    if v_desc is null then
      raise exception 'Um dos produtos não é deste salão.' using errcode = 'check_violation';
    end if;
    insert into public.comanda_itens (comanda_id, tipo, produto_id, descricao, qtd, preco_unit, profissional_id)
         values (v_com, 'produto', nullif(x->>'id', '')::uuid, v_desc, v_qtd, coalesce(v_preco, 0), p_profissional);
  end loop;
  if coalesce(p_desconto, 0) < 0 then
    raise exception 'O desconto não pode ser negativo.' using errcode = 'check_violation';
  end if;
  if coalesce(p_desconto, 0) > 0 then
    update public.comandas set desconto = round(p_desconto, 2) where id = v_com;
  end if;
  select t.total into v_total from public.comandas_totais t where t.id = v_com;
  if coalesce(v_total, 0) > 0 then
    insert into public.pagamentos (comanda_id, forma, valor) values (v_com, p_forma, round(v_total, 2));
  end if;
  update public.comandas set status = 'fechada', fechada_em = now() where id = v_com;

  update public.pedidos_loja
     set status = 'vendido', vendido_em = now(), vendido_por = auth.uid(), comanda_id = v_com
   where id = p.id;
  return jsonb_build_object('ok', true, 'comanda', v_com, 'total', round(coalesce(v_total, 0), 2));
end $$;

/* No crediário: a venda a prazo do 47 (nome completo, WhatsApp e CPF na
   ficha, as parcelas, a entrada), e o pedido vendido — na mesma transação:
   ou os dois, ou nenhum. */
create or replace function public.vender_pedido_no_crediario(
  p_pedido uuid, p_itens jsonb, p_profissional uuid, p_desconto numeric,
  p_entrada numeric, p_forma_entrada text, p_parcelas int, p_primeiro date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype; r jsonb;
begin
  p := public.pedido_para_vender(p_pedido);
  r := public.nova_venda_no_crediario(p.salao_id, p.cliente_id, p_itens, p_profissional,
         p_desconto, p_entrada, p_forma_entrada, p_parcelas, p_primeiro);
  update public.pedidos_loja
     set status = 'vendido', vendido_em = now(), vendido_por = auth.uid(),
         comanda_id = nullif(r->>'comanda', '')::uuid, crediario_id = nullif(r->>'crediario', '')::uuid
   where id = p.id;
  return r || jsonb_build_object('pedido', p.id);
end $$;

-- ---------------------------------------------------------------------------
-- 5) CANCELAR
-- ---------------------------------------------------------------------------
create or replace function public.cancelar_pedido_loja(p_pedido uuid, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype;
begin
  p := public.pedido_para_vender(p_pedido);
  update public.pedidos_loja
     set status = 'cancelado', cancelado_em = now(), cancelado_por = auth.uid(),
         cancelado_motivo = nullif(left(btrim(coalesce(p_motivo, '')), 200), '')
   where id = p.id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 5b) O RECIBO
--
-- "Nos pedidos preciso ver o que eu vendi, um recibo com todos os itens, e
-- mandar o PDF no WhatsApp ou imprimir." O recibo é o que foi VENDIDO — a
-- comanda, com a lista conferida no balcão —, não o que a cliente pediu:
-- tirou um item que não tinha, ele não aparece. Com o pagamento (as formas,
-- e as parcelas, se foi no crediário) e quem vendeu.
-- ---------------------------------------------------------------------------
create or replace function public.recibo_do_pedido_loja(p_pedido uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.pedidos_loja%rowtype; s public.saloes%rowtype; t record; c record;
begin
  select * into p from public.pedidos_loja where id = p_pedido;
  if p.id is null then
    raise exception 'Pedido não encontrado.' using errcode = 'check_violation';
  end if;
  if not public.ve_agenda_toda(p.salao_id) then
    raise exception 'Só o balcão e a gestão veem o recibo.' using errcode = 'insufficient_privilege';
  end if;
  if p.status <> 'vendido' or p.comanda_id is null then
    raise exception 'Este pedido ainda não foi vendido.' using errcode = 'check_violation';
  end if;
  select * into s from public.saloes where id = p.salao_id;
  select ct.numero, ct.subtotal, ct.desconto, ct.acrescimo, ct.total, ct.fechada_em into t
    from public.comandas_totais ct where ct.id = p.comanda_id;
  select cl.nome, cl.telefone into c from public.clientes cl where cl.id = p.cliente_id;
  return jsonb_build_object(
    'salao', jsonb_build_object('nome', s.nome,
               'telefone', coalesce(nullif(btrim(coalesce(s.whatsapp, '')), ''), s.telefone),
               'endereco', s.endereco),
    'numero', p.numero, 'comanda', t.numero,
    'vendidoEm', coalesce(p.vendido_em, t.fechada_em),
    'vendidoPor', (select pf.nome from public.perfis pf where pf.id = p.vendido_por),
    'cliente', c.nome, 'telefone', c.telefone,
    'itens', coalesce((select jsonb_agg(jsonb_build_object('descricao', i.descricao, 'qtd', i.qtd,
                 'preco', i.preco_unit, 'total', round(i.qtd * i.preco_unit, 2)) order by i.descricao)
                 from public.comanda_itens i where i.comanda_id = p.comanda_id), '[]'::jsonb),
    'subtotal', t.subtotal, 'desconto', t.desconto, 'acrescimo', t.acrescimo, 'total', t.total,
    'pagamentos', coalesce((select jsonb_agg(jsonb_build_object('forma', pg.forma, 'valor', pg.valor)
                 order by (pg.forma = 'crediario'), pg.recebido_em)
                 from public.pagamentos pg where pg.comanda_id = p.comanda_id), '[]'::jsonb),
    'parcelas', coalesce((select jsonb_agg(jsonb_build_object('numero', pa.numero, 'valor', pa.valor,
                 'venceEm', pa.vence_em) order by pa.numero)
                 from public.crediario_parcelas pa where pa.crediario_id = p.crediario_id), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.fazer_pedido_loja(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.fazer_pedido_loja(uuid, jsonb, text, uuid) to authenticated;
revoke all on function public.pedidos_loja_painel(uuid) from public, anon;
grant execute on function public.pedidos_loja_painel(uuid) to authenticated;
revoke all on function public.pedido_para_vender(uuid) from public, anon, authenticated;
revoke all on function public.vender_pedido_loja(uuid, jsonb, text, numeric, uuid) from public, anon;
grant execute on function public.vender_pedido_loja(uuid, jsonb, text, numeric, uuid) to authenticated;
revoke all on function public.vender_pedido_no_crediario(uuid, jsonb, uuid, numeric, numeric, text, int, date) from public, anon;
grant execute on function public.vender_pedido_no_crediario(uuid, jsonb, uuid, numeric, numeric, text, int, date) to authenticated;
revoke all on function public.cancelar_pedido_loja(uuid, text) from public, anon;
grant execute on function public.cancelar_pedido_loja(uuid, text) to authenticated;
revoke all on function public.recibo_do_pedido_loja(uuid) from public, anon;
grant execute on function public.recibo_do_pedido_loja(uuid) to authenticated;

-- ###########################################################################
-- ## 54_sino.sql
-- ###########################################################################

-- ===========================================================================
-- 54_sino.sql — o sino do painel
--
-- O pedido: "dentro do painel do dono do salão, um ícone de sino para as
-- notificações do sistema". Cada aviso morava num canto: o pedido novo na
-- aba Pedidos, o horário esperando na agenda, a parcela atrasada no
-- Crediário, o fim do teste numa faixa. O sino junta o que PEDE AÇÃO, com
-- o número, e cada item leva à tela onde se resolve.
--
-- ── O QUE ENTRA ───────────────────────────────────────────────────────────
-- Só coisa de verdade, contada aqui, na hora. Nada é gravado para o sino: o
-- item some sozinho quando o motivo some (o horário foi confirmado, a
-- parcela foi paga). Não há "marcar como lido" nesses — lido é resolvido.
--
--   a_confirmar   horários esperando o "sim" do salão (sem os de pacote a
--                 receber, que esperam o pagamento, não uma resposta);
--   sinal         horários esperando o salão conferir o Pix do sinal;
--   pedidos_loja  pedidos da loja novos (53);
--   pedidos       pedidos do restaurante recebidos e ainda não aceitos (37);
--   parcelas      parcelas do crediário vencidas e não pagas (47);
--   mensagens     mensagens do WhatsApp que falharam nos últimos 7 dias;
--   franquia      80% ou mais das mensagens do mês usadas;
--   assinatura    teste no fim, assinatura vencendo (no Pix) ou vencida,
--                 pagamento pendente;
--   conta_excluida  clientes que excluíram a conta do link (56), até o balcão
--                 ver o aviso.
--
-- E os AVISOS DO AGENDAPRO: o que a plataforma escreve no admin (novidade,
-- manutenção, recado) aparece no sino de todos os salões até a pessoa
-- marcar como lido.
--
-- ── QUEM VÊ O QUÊ ─────────────────────────────────────────────────────────
-- A mesma régua das telas, decidida AQUI e não na tela:
--   · quem atende vê só os próprios horários a confirmar;
--   · o balcão (recepção e gestão) vê a agenda toda, o sinal, os pedidos da
--     loja e as parcelas — as telas dessas coisas pedem `ve_agenda_toda`;
--   · mensagens, franquia e assinatura são da gestão (`e_gestor`);
--   · o aviso da plataforma vai para a gestão ou para a equipe toda,
--     conforme quem escreveu escolheu.
-- ===========================================================================

create table if not exists public.avisos_plataforma (
  id            uuid primary key default gen_random_uuid(),
  titulo        text not null check (length(btrim(titulo)) between 3 and 120),
  texto         text not null check (length(btrim(texto)) between 3 and 2000),
  -- 'gestao': dono e gerente; 'equipe': todo mundo que entra no painel.
  para          text not null default 'gestao' check (para in ('gestao', 'equipe')),
  publicado_em  timestamptz not null default now(),
  -- Some depois deste dia, no relógio de Brasília (manutenção marcada,
  -- promoção com prazo).
  ate           date,
  arquivado_em  timestamptz,
  criado_por    uuid references public.perfis(id) on delete set null
);
create index if not exists ix_avisos_plataforma_vivos
  on public.avisos_plataforma(publicado_em desc) where arquivado_em is null;
/* PARA UM SALÃO SÓ ("como envio somente para um usuário?"): com o salão
   escolhido, o aviso aparece só no sino dele — a prorrogação da cortesia de
   um dono, um recado para uma casa. Vazio: para todos os salões. */
alter table public.avisos_plataforma
  add column if not exists salao_id uuid references public.saloes(id) on delete cascade;

create table if not exists public.avisos_lidos (
  aviso_id   uuid not null references public.avisos_plataforma(id) on delete cascade,
  perfil_id  uuid not null references public.perfis(id) on delete cascade,
  lido_em    timestamptz not null default now(),
  primary key (aviso_id, perfil_id)
);

-- Ninguém lê nem escreve direto: só pelas funções abaixo.
alter table public.avisos_plataforma enable row level security;
alter table public.avisos_lidos enable row level security;
revoke all on public.avisos_plataforma from public, anon, authenticated;
revoke all on public.avisos_lidos from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- O sino: os itens (contados agora) e os avisos não lidos.
-- ---------------------------------------------------------------------------
create or replace function public.sino_do_painel(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_toda boolean; v_gestor boolean; v_prof uuid; v_hoje date; v_fuso text;
  v_itens jsonb := '[]'::jsonb; v_avisos jsonb; n int; v_valor numeric;
  v_uso int; v_teto int; s record; v_cfg jsonb; v_nomes text[]; v_hor int; v_pac int;
begin
  if auth.uid() is null or p_salao is null or not public.e_equipe(p_salao) then
    raise exception 'Só a equipe do salão vê os avisos.' using errcode = 'insufficient_privilege';
  end if;
  v_toda   := public.ve_agenda_toda(p_salao);
  v_gestor := public.e_gestor(p_salao);
  v_prof   := public.meu_profissional_id(p_salao);
  v_hoje   := public.hoje_no_salao(p_salao);
  select coalesce(sa.fuso, 'America/Sao_Paulo'), coalesce(sa.cfg, '{}'::jsonb) into v_fuso, v_cfg
    from public.saloes sa where sa.id = p_salao;

  -- Horários a confirmar. Para o balcão, os do sinal ficam no item deles.
  select count(*) into n
    from public.agendamentos ag
   where ag.salao_id = p_salao and ag.status = 'pendente' and ag.arquivado_em is null
     and (ag.inicio at time zone v_fuso)::date >= v_hoje
     and (v_toda or (v_prof is not null and ag.profissional_id = v_prof))
     and not (v_toda and coalesce(ag.sinal_exigido, 0) > 0
              and coalesce(ag.sinal_pago, 0) < ag.sinal_exigido)
     and not exists (select 1 from public.pacote_clientes pc
                      where pc.id = ag.pacote_cliente_id and coalesce(pc.valor, 0) > 0
                        and pc.pago_em is null and pc.cancelado_em is null);
  if n > 0 then
    v_itens := v_itens || jsonb_build_object('tipo', 'a_confirmar', 'qtd', n);
  end if;

  if v_toda then
    -- O sinal por Pix esperando o salão conferir (o prazo ainda não venceu:
    -- vencido, o agendador libera o horário sozinho).
    select count(*) into n
      from public.agendamentos ag
     where ag.salao_id = p_salao and ag.status = 'pendente' and ag.arquivado_em is null
       and coalesce(ag.sinal_exigido, 0) > 0 and coalesce(ag.sinal_pago, 0) < ag.sinal_exigido
       and (ag.sinal_ate is null or ag.sinal_ate >= now())
       and (ag.inicio at time zone v_fuso)::date >= v_hoje;
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'sinal', 'qtd', n);
    end if;

    -- Pedidos da loja esperando a venda — só com a loja ligada em Meu
    -- negócio (Produtos à venda: Sim), a mesma chave da aba Pedidos.
    select count(*) into n from public.pedidos_loja pl
     where pl.salao_id = p_salao and pl.status = 'novo'
       and lower(btrim(coalesce(v_cfg->>'loja', 'true'))) not in ('false', 'f', '0', 'no', 'nao', 'não');
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'pedidos_loja', 'qtd', n);
    end if;

    -- Parcelas vencidas do crediário, com o que falta receber delas.
    select count(*), coalesce(round(sum(x.saldo), 2), 0) into n, v_valor
      from (select public.saldo_da_parcela(pa.id) as saldo
              from public.crediario_parcelas pa
              join public.crediarios cr on cr.id = pa.crediario_id
             where pa.salao_id = p_salao and cr.desfeito_em is null
               and pa.vence_em < v_hoje) x
     where x.saldo > 0;
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'parcelas', 'qtd', n, 'valor', v_valor);
    end if;

    -- Clientes que excluíram a conta do link (56) e o balcão ainda não viu:
    -- quem, e quantas ainda têm horário marcado ou pacote ativo.
    select count(*), (array_agg(c.nome order by c.conta_excluida_em desc))[1:3],
           count(*) filter (where exists (select 1 from public.agendamentos a
                                           where a.cliente_id = c.id and a.arquivado_em is null
                                             and a.status in ('pendente', 'confirmado') and a.inicio > now())),
           count(*) filter (where exists (select 1 from public.pacote_clientes pc
                                           where pc.cliente_id = c.id and pc.cancelado_em is null
                                             and pc.vence_em >= v_hoje))
      into n, v_nomes, v_hor, v_pac
      from public.clientes c
     where c.salao_id = p_salao and c.conta_excluida_em is not null
       and c.conta_excluida_vista_em is null
       and c.conta_excluida_em > now() - interval '30 days';
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'conta_excluida', 'qtd', n,
        'nomes', to_jsonb(coalesce(v_nomes, '{}'::text[])), 'comHorario', v_hor, 'comPacote', v_pac);
    end if;
  end if;

  -- Pedidos do restaurante recebidos e ainda não aceitos (a equipe toda vê).
  select count(*) into n from public.pedidos pe
   where pe.salao_id = p_salao and pe.status = 'recebido';
  if n > 0 then
    v_itens := v_itens || jsonb_build_object('tipo', 'pedidos', 'qtd', n);
  end if;

  if v_gestor then
    -- Mensagens que falharam na última semana.
    select count(*) into n from public.notificacoes nt
     where nt.salao_id = p_salao and nt.status = 'falhou'
       and nt.criado_em >= now() - interval '7 days';
    if n > 0 then
      v_itens := v_itens || jsonb_build_object('tipo', 'mensagens', 'qtd', n);
    end if;

    -- A franquia de mensagens do mês (sem teto, ou teto zero: nada a dizer).
    v_teto := public.teto_mensagens(p_salao);
    if coalesce(v_teto, 0) > 0 then
      v_uso := public.mensagens_no_mes(p_salao);
      if v_uso >= ceil(v_teto * 0.8) then
        v_itens := v_itens || jsonb_build_object('tipo', 'franquia', 'qtd', 1,
          'usado', v_uso, 'teto', v_teto, 'pct', least(round(v_uso * 100.0 / v_teto), 100));
      end if;
    end if;

    -- A assinatura. No cartão a renovação é automática: vencer não é aviso.
    select a.status, a.trial_ate, a.vence_em, a.mp_preapproval into s
      from public.assinaturas a where a.salao_id = p_salao;
    if s.status = 'inadimplente' then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'inadimplente');
    elsif s.status = 'trial' and s.trial_ate between v_hoje and v_hoje + 3 then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'teste',
        'dias', s.trial_ate - v_hoje);
    elsif s.status = 'ativa' and s.vence_em is not null and s.mp_preapproval is null
          and s.vence_em between v_hoje and v_hoje + 5 then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'vence',
        'dias', s.vence_em - v_hoje);
    elsif s.status = 'ativa' and s.vence_em is not null
          and s.vence_em < v_hoje and s.vence_em >= v_hoje - 30 then
      v_itens := v_itens || jsonb_build_object('tipo', 'assinatura', 'qtd', 1, 'situacao', 'venceu',
        'dias', v_hoje - s.vence_em);
    end if;
  end if;

  -- Os avisos do AgendaPro que esta pessoa ainda não leu.
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'titulo', x.titulo, 'texto', x.texto,
           'publicadoEm', x.publicado_em) order by x.publicado_em desc), '[]'::jsonb)
    into v_avisos
    from (select ap.* from public.avisos_plataforma ap
           where ap.arquivado_em is null
             and (ap.ate is null or ap.ate >= (now() at time zone 'America/Sao_Paulo')::date)
             and (ap.para = 'equipe' or v_gestor)
             and (ap.salao_id is null or ap.salao_id = p_salao)
             and not exists (select 1 from public.avisos_lidos al
                              where al.aviso_id = ap.id and al.perfil_id = auth.uid())
           order by ap.publicado_em desc limit 10) x;

  return jsonb_build_object('itens', v_itens, 'avisos', v_avisos);
end $$;

revoke all on function public.sino_do_painel(uuid) from public, anon;
grant execute on function public.sino_do_painel(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- "Marcar como lido": o aviso sai do sino desta pessoa (dos outros, não).
-- ---------------------------------------------------------------------------
create or replace function public.marcar_aviso_lido(p_aviso uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'Entre de novo para marcar o aviso.' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.avisos_plataforma ap where ap.id = p_aviso) then
    raise exception 'Este aviso não existe mais.' using errcode = 'check_violation';
  end if;
  insert into public.avisos_lidos (aviso_id, perfil_id) values (p_aviso, auth.uid())
  on conflict (aviso_id, perfil_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.marcar_aviso_lido(uuid) from public, anon;
grant execute on function public.marcar_aviso_lido(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- O admin: publicar, listar e arquivar os avisos. Só a plataforma.
-- ---------------------------------------------------------------------------
-- A versão de antes, sem o salão: sai, para não ficarem duas.
drop function if exists public.publicar_aviso_plataforma(text, text, text, date);
create or replace function public.publicar_aviso_plataforma(
  p_titulo text, p_texto text, p_para text default 'gestao', p_ate date default null,
  p_salao uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_titulo text := btrim(coalesce(p_titulo, '')); v_texto text := btrim(coalesce(p_texto, ''));
begin
  if not public.is_super() then
    raise exception 'Só a plataforma publica avisos para os salões.' using errcode = 'insufficient_privilege';
  end if;
  if length(v_titulo) < 3 or length(v_titulo) > 120 then
    raise exception 'O título precisa ter de 3 a 120 letras.' using errcode = 'check_violation';
  end if;
  if length(v_texto) < 3 or length(v_texto) > 2000 then
    raise exception 'O texto precisa ter de 3 a 2.000 letras.' using errcode = 'check_violation';
  end if;
  if coalesce(p_para, 'gestao') not in ('gestao', 'equipe') then
    raise exception 'Escolha para quem é o aviso.' using errcode = 'check_violation';
  end if;
  if p_ate is not null and p_ate < (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'A data de saída já passou.' using errcode = 'check_violation';
  end if;
  if p_salao is not null and not exists (select 1 from public.saloes s where s.id = p_salao) then
    raise exception 'Não achei esse salão.' using errcode = 'check_violation';
  end if;
  insert into public.avisos_plataforma (titulo, texto, para, ate, criado_por, salao_id)
       values (v_titulo, v_texto, coalesce(p_para, 'gestao'), p_ate, auth.uid(), p_salao)
    returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.arquivar_aviso_plataforma(p_aviso uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma tira avisos do ar.' using errcode = 'insufficient_privilege';
  end if;
  update public.avisos_plataforma set arquivado_em = now()
   where id = p_aviso and arquivado_em is null;
  return jsonb_build_object('ok', found);
end $$;

create or replace function public.avisos_plataforma_admin()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os avisos publicados.' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', ap.id, 'titulo', ap.titulo, 'texto', ap.texto,
           'para', ap.para, 'publicadoEm', ap.publicado_em, 'ate', ap.ate,
           'salaoId', ap.salao_id, 'salao', (select s.nome from public.saloes s where s.id = ap.salao_id),
           'noAr', ap.arquivado_em is null
                    and (ap.ate is null or ap.ate >= (now() at time zone 'America/Sao_Paulo')::date),
           'lidos', (select count(*) from public.avisos_lidos al where al.aviso_id = ap.id))
           order by ap.publicado_em desc)
      from (select * from public.avisos_plataforma order by publicado_em desc limit 30) ap), '[]'::jsonb);
end $$;

revoke all on function public.publicar_aviso_plataforma(text, text, text, date, uuid) from public, anon;
revoke all on function public.arquivar_aviso_plataforma(uuid) from public, anon;
revoke all on function public.avisos_plataforma_admin() from public, anon;
grant execute on function public.publicar_aviso_plataforma(text, text, text, date, uuid) to authenticated;
grant execute on function public.arquivar_aviso_plataforma(uuid) to authenticated;
grant execute on function public.avisos_plataforma_admin() to authenticated;

-- ###########################################################################
-- ## 55_relatorio_vendas.sql
-- ###########################################################################

-- ===========================================================================
-- 55_relatorio_vendas.sql — a loja e os pacotes no Relatórios
--
-- O pedido: "acrescentar tudo que fizemos de ontem pra hoje; no relatório,
-- deixar bem organizado de forma que todos entendam". O Relatórios já tinha
-- o faturamento, a comissão, as formas de pagamento, o crediário, o que mais
-- saiu, as clientes e a agenda. Faltavam as vendas que nasceram depois:
--
--   · a LOJA PELO LINK (53): quantos pedidos chegaram, quantos viraram venda
--     (e quantos no crediário), quantos foram cancelados, quanto rendeu e o
--     que mais saiu por ela;
--   · os PACOTES (27, 43): quantos foram vendidos e por quanto, quanto foi
--     recebido e quanto está a receber, e as sessões feitas e as faltas (que
--     gastam a sessão, 27).
--
-- Uma função à parte do `relatorio()` (12), e não mais um pedaço dele: o
-- relatório de sempre continua igual, e banco sem este arquivo só não mostra
-- os dois blocos novos. As mesmas regras: só a gestão, o mesmo recurso do
-- plano, o dia do salão.
--
-- ⚠ O VALOR DA LOJA E O DOS PACOTES JÁ ESTÃO NO FATURAMENTO. A venda da loja
-- é uma comanda fechada; o pacote, a comanda do pagamento. Aqui é o detalhe
-- de onde veio parte do dinheiro — não um dinheiro a mais. A tela diz isso.
-- ===========================================================================

create or replace function public.relatorio_vendas(p_salao uuid, p_de date, p_ate date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_fuso text; v_ini timestamptz; v_fim timestamptz;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  perform public.exigir_recurso(p_salao, 'relatorios', 'O relatório');
  if p_de is null or p_ate is null or p_ate < p_de then
    raise exception 'Confira as datas do período.' using errcode = 'check_violation';
  end if;
  select coalesce(s.fuso, 'America/Sao_Paulo') into v_fuso from public.saloes s where s.id = p_salao;
  v_ini := (p_de::timestamp) at time zone v_fuso;
  v_fim := ((p_ate + 1)::timestamp) at time zone v_fuso;   -- fim exclusivo

  return jsonb_build_object(
    -- ── A LOJA PELO LINK ──────────────────────────────────────────────────
    -- Chegou conta pela data do pedido; vendido, pela data da venda;
    -- cancelado, pela do cancelamento. "Esperando" é agora, não do período.
    'loja', jsonb_build_object(
      'recebidos', (select count(*) from public.pedidos_loja pl
                     where pl.salao_id = p_salao and pl.criado_em >= v_ini and pl.criado_em < v_fim),
      'vendidos', (select count(*) from public.pedidos_loja pl
                    where pl.salao_id = p_salao and pl.status = 'vendido'
                      and pl.vendido_em >= v_ini and pl.vendido_em < v_fim),
      'noCrediario', (select count(*) from public.pedidos_loja pl
                       where pl.salao_id = p_salao and pl.status = 'vendido' and pl.crediario_id is not null
                         and pl.vendido_em >= v_ini and pl.vendido_em < v_fim),
      'cancelados', (select count(*) from public.pedidos_loja pl
                      where pl.salao_id = p_salao and pl.status = 'cancelado'
                        and pl.cancelado_em >= v_ini and pl.cancelado_em < v_fim),
      'esperando', (select count(*) from public.pedidos_loja pl
                     where pl.salao_id = p_salao and pl.status = 'novo'),
      'valor', coalesce((select round(sum(ct.total), 2) from public.pedidos_loja pl
                          join public.comandas_totais ct on ct.id = pl.comanda_id
                         where pl.salao_id = p_salao and pl.status = 'vendido'
                           and pl.vendido_em >= v_ini and pl.vendido_em < v_fim), 0),
      'produtos', coalesce((select jsonb_agg(jsonb_build_object('nome', y.nome, 'qtd', y.qtd, 'valor', y.valor)
                                    order by y.valor desc)
                              from (select i.descricao as nome, round(sum(i.qtd), 2) as qtd,
                                           round(sum(i.qtd * i.preco_unit), 2) as valor
                                      from public.comanda_itens i
                                      join public.pedidos_loja pl on pl.comanda_id = i.comanda_id
                                     where pl.salao_id = p_salao and pl.status = 'vendido'
                                       and pl.vendido_em >= v_ini and pl.vendido_em < v_fim
                                     group by i.descricao
                                     order by 3 desc limit 8) y), '[]'::jsonb)),

    -- ── OS PACOTES ────────────────────────────────────────────────────────
    -- Vendido conta pela data da venda (o vínculo da cliente com o pacote);
    -- recebido, pela do pagamento. "A receber" é agora. As sessões e as
    -- faltas, pelo dia do atendimento — a falta gasta a sessão (27).
    'pacotes', jsonb_build_object(
      'vendidos', (select count(*) from public.pacote_clientes pc
                     join public.pacotes p on p.id = pc.pacote_id
                    where p.salao_id = p_salao and pc.cancelado_em is null
                      and pc.criado_em >= v_ini and pc.criado_em < v_fim),
      'valorVendido', coalesce((select round(sum(coalesce(pc.valor, p.preco)), 2)
                                  from public.pacote_clientes pc
                                  join public.pacotes p on p.id = pc.pacote_id
                                 where p.salao_id = p_salao and pc.cancelado_em is null
                                   and pc.criado_em >= v_ini and pc.criado_em < v_fim), 0),
      'recebido', coalesce((select round(sum(pc.valor), 2)
                              from public.pacote_clientes pc
                              join public.pacotes p on p.id = pc.pacote_id
                             where p.salao_id = p_salao and pc.pago_em >= v_ini and pc.pago_em < v_fim), 0),
      'aReceber', coalesce((select round(sum(pc.valor), 2)
                              from public.pacote_clientes pc
                              join public.pacotes p on p.id = pc.pacote_id
                             where p.salao_id = p_salao and coalesce(pc.valor, 0) > 0
                               and pc.pago_em is null and pc.cancelado_em is null), 0),
      'sessoesFeitas', (select count(*) from public.agendamentos a
                         where a.salao_id = p_salao and a.pacote_cliente_id is not null
                           and a.status = 'concluido' and a.arquivado_em is null
                           and a.inicio >= v_ini and a.inicio < v_fim),
      'faltas', (select count(*) from public.agendamentos a
                  where a.salao_id = p_salao and a.pacote_cliente_id is not null
                    and a.status = 'faltou' and a.arquivado_em is null
                    and a.inicio >= v_ini and a.inicio < v_fim),
      'porPacote', coalesce((select jsonb_agg(jsonb_build_object('nome', z.nome, 'vendidos', z.n, 'valor', z.valor)
                                     order by z.valor desc, z.nome)
                               from (select p.nome, count(*) as n, round(sum(coalesce(pc.valor, p.preco)), 2) as valor
                                       from public.pacote_clientes pc
                                       join public.pacotes p on p.id = pc.pacote_id
                                      where p.salao_id = p_salao and pc.cancelado_em is null
                                        and pc.criado_em >= v_ini and pc.criado_em < v_fim
                                      group by p.nome) z), '[]'::jsonb))
  );
end $$;

revoke all on function public.relatorio_vendas(uuid, date, date) from public, anon;
grant execute on function public.relatorio_vendas(uuid, date, date) to authenticated;

-- ###########################################################################
-- ## 56_conta_excluida.sql
-- ###########################################################################

-- ===========================================================================
-- 56_conta_excluida.sql — a cliente excluiu a conta: o salão fica sabendo
--
-- O pedido: "e quando algum cliente excluir a conta dele, o que aparece pro
-- dono do salão?" Não aparecia nada. A exclusão (36) tira só o login dela: a
-- ficha é do SALÃO e continua em Clientes (`clientes.perfil_id` vira nulo),
-- com os horários marcados — e os lembretes, que vão para o WhatsApp da
-- ficha. O dono não tinha como saber que ela não entra mais pelo link.
--
-- Agora a ficha guarda QUANDO a conta sumiu (`conta_excluida_em`), Clientes
-- mostra "excluiu a conta do link em 04/11", e o sino avisa o balcão — com
-- quantas ainda têm horário marcado ou pacote ativo, que é o que pede uma
-- ligação. Visto o aviso, ele sai do sino (`conta_excluida_vista_em`); a
-- marca na ficha fica.
--
-- ── COMO O BANCO SABE ─────────────────────────────────────────────────────
-- Pelo próprio caminho da exclusão: apagar a conta (auth.users) apaga o
-- perfil, e a chave `clientes.perfil_id ... on delete set null` desliga a
-- ficha. O gatilho abaixo vê esse desligamento e confere que o perfil não
-- existe mais — então foi a CONTA que sumiu (pelo botão Excluir conta ou
-- pelo painel do Supabase), e não outra coisa desligando a ficha. Se ela
-- voltar e criar conta de novo com o mesmo WhatsApp, a ficha é religada e a
-- marca sai.
-- ===========================================================================

alter table public.clientes add column if not exists conta_excluida_em timestamptz;
alter table public.clientes add column if not exists conta_excluida_vista_em timestamptz;

create or replace function public.tg_cliente_conta_excluida()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.perfil_id is not null and new.perfil_id is null
     and not exists (select 1 from public.perfis p where p.id = old.perfil_id) then
    new.conta_excluida_em := now();
    new.conta_excluida_vista_em := null;
  elsif new.perfil_id is not null and old.perfil_id is null then
    -- Voltou: criou conta de novo e a ficha foi religada.
    new.conta_excluida_em := null;
    new.conta_excluida_vista_em := null;
  end if;
  return new;
end $$;
revoke all on function public.tg_cliente_conta_excluida() from public, anon, authenticated;
drop trigger if exists tg_cliente_conta_excluida on public.clientes;
create trigger tg_cliente_conta_excluida
  before update of perfil_id on public.clientes
  for each row execute function public.tg_cliente_conta_excluida();

-- O balcão viu o aviso do sino: sai de lá (a marca na ficha fica).
create or replace function public.ver_contas_excluidas(p_salao uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.ve_agenda_toda(p_salao) then
    raise exception 'Só o balcão e a gestão veem este aviso.' using errcode = 'insufficient_privilege';
  end if;
  update public.clientes set conta_excluida_vista_em = now()
   where salao_id = p_salao and conta_excluida_em is not null and conta_excluida_vista_em is null;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'vistas', n);
end $$;

revoke all on function public.ver_contas_excluidas(uuid) from public, anon;
grant execute on function public.ver_contas_excluidas(uuid) to authenticated;
