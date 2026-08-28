-- ===========================================================================
-- AgendaPro — 19: o teto do link público
--
-- ── O QUE FOI MEDIDO ──────────────────────────────────────────────────────
-- Numa bancada de pé, com SÓ a chave publicável — a mesma que está à vista no
-- config.js, e que está certa ali, porque quem protege é o RLS:
--
--     horários que o link oferece para amanhã: 45
--       telefone 11910000000: marcou 3 · "Você já tem 3 horários marcados"
--       telefone 11910000001: marcou 3 · "Você já tem 3 horários marcados"
--       telefone 11910000002: marcou 3 · "Você já tem 3 horários marcados"
--       telefone 11910000003: marcou 3 · "Você já tem 3 horários marcados"
--     marcados: 12 com 4 telefones · horários restantes: 0 (eram 45)
--
-- Quatro telefones inventados fecharam o dia inteiro de uma profissional em
-- menos de um minuto, sem login nenhum. O freio de "3 horários abertos"
-- existe e funciona — só que conta por FICHA, e a ficha nasce do telefone que
-- a pessoa digitou. Telefone novo, ficha nova, freio zerado.
--
-- ── O NÚMERO FIXO QUE EU IA ESCREVER, E POR QUE ELE NÃO SERVE ─────────────
-- A primeira versão deste arquivo era um teto de 20 marcações por salão por
-- dia. O teste reprovou na cara: as 12 marcações acima JÁ ERAM o dia inteiro.
-- Numa agenda de 08:00 às 20:00 com serviço de uma hora cabem doze pessoas —
-- um teto de vinte nunca chega a valer, e um teto de dez estraga o dia de um
-- salão movimentado.
--
-- Não existe número fixo certo, porque "o dia" tem tamanho diferente em cada
-- salão. O que funciona é limite que ANDA COM A AGENDA. São dois, e cada um
-- cobre o que o outro não cobre:
--
--   a reserva do balcão   o link nunca ocupa a agenda inteira de alguém
--   o freio de rajada     doze marcações em um minuto não é gente marcando
--
-- ── ISTO É CURATIVO, E É BOM DIZER ────────────────────────────────────────
-- Sem provar que o telefone é de quem digitou, dá para encarecer o estrago e
-- não dá para impedi-lo. Quem impede é o código por WhatsApp, que depende da
-- verificação na Meta. Até lá, o que estes dois limites compram é tempo: o
-- salão nunca amanhece com a agenda inteira tomada, e encher o mês passa a
-- exigir horas de insistência em vez de um minuto.
--
-- ── POR QUE NO `porque_nao_agenda()` E NÃO NO `agendar()` ─────────────────
-- Porque é ali que moram as regras de POLÍTICA da agenda online — o plano, os
-- dias liberados, o serviço que aceita online — e porque as DUAS pontas leem
-- a mesma função:
--
--     horarios_livres()  não oferece o horário
--     agendar()          recusa a marcação
--
-- Posto só no `agendar()`, o link continuaria oferecendo horário para recusá-
-- lo no clique. Posto aqui, o dia aparece sem vaga, que é o que a pessoa já
-- sabe ler — e o balcão continua enxergando as vagas, porque o painel escreve
-- direto na tabela e não passa por aqui.
--
-- ── O TETO É DO LINK, NUNCA DA CASA ───────────────────────────────────────
-- Um limite que pegasse no balcão deixaria a recepção sem poder anotar quem
-- ligou justamente no dia em que a internet mandou gente demais — o contrário
-- do que se quer.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) A RESERVA DO BALCÃO
--
-- Quanto da jornada de um profissional, num dia, o link pode ocupar. O resto
-- fica guardado para quem liga, para quem entra na loja e para o encaixe.
--
-- 70% é o padrão porque deixa a conta redonda para o dono: de dez cadeiras, o
-- link marca sete e três ficam com a casa. Quem trabalha só com marcação pela
-- internet põe 100 e desliga a reserva — aí quem protege é o freio de rajada
-- lá embaixo, sozinho.
--
-- Mesma forma do `dias_liberados()`: mora no `cfg`, tem padrão, e é aparado
-- nas duas pontas.
-- ---------------------------------------------------------------------------
create or replace function public.teto_online_pct(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select greatest(10, least(100,
    coalesce((select (cfg->>'tetoOnlinePct')::int from public.saloes
               where id = p_salao and cfg->>'tetoOnlinePct' ~ '^[0-9]+$'), 70)))
$$;

-- ---------------------------------------------------------------------------
-- 2) O FREIO DE RAJADA
--
-- Quantas pessoas DESCONHECIDAS o link aceita, no salão inteiro, em dez
-- minutos.
--
-- ⚠ O "desconhecidas" não é enfeite, e custou uma reprova para aparecer.
--
-- A primeira versão contava toda marcação online da janela, com teto de
-- cinco. Um teste de auditoria — que exercita a geometria da agenda marcando
-- vários horários seguidos — reprovou inteiro com "congestionada". E aquilo
-- não era um defeito do teste: era o retrato de uma coisa que acontece de
-- verdade no salão. O dono publica um story, oito pessoas marcam em dez
-- minutos, e o freio manda todas embora — justamente no melhor momento do
-- mês. Um limite que estraga o dia bom não é proteção, é prejuízo.
--
-- Contando só ficha NOVA, o freio passa a separar as duas coisas: uma correria
-- de clientes conhecidas — a turma remarcando depois de um story — não ENCHE o
-- contador e nunca aciona o freio; um script, que só sabe inventar telefone, é
-- 100% ficha nova e bate no teto na hora.
--
-- ⚠ E o que isto NÃO quer dizer, para ninguém se enganar lendo depois: quando
-- o freio DISPARA, ele segura o link para todo mundo por até dez minutos —
-- inclusive para uma cliente conhecida que chegar no meio. A função
-- `porque_nao_agenda()` responde sobre o DIA e o PROFISSIONAL; ela não sabe
-- quem está do outro lado, porque quem descobre a ficha é o `agendar()`, mais
-- adiante. Deixar cada cliente de fora exigiria copiar o `agendar()` inteiro
-- para dentro deste módulo e mantê-lo igual ao 09_cliente.sql para sempre —
-- caro demais para dez minutos de porta fechada num evento raro.
--
-- É por isso que o padrão é dez, e não cinco: o custo de errar para o lado
-- apertado é fechar a porta num dia bom.
--
-- Dez é muito para um salão de uma a três pessoas — dez desconhecidas
-- marcando no mesmo intervalo de dez minutos é um dia excepcional — e é pouco
-- para quem está rodando um script.
--
-- ⚠ E este conta TUDO que foi criado na janela, inclusive cancelado. É de
-- propósito, e é a diferença entre este e a reserva de cima: a reserva mede
-- ocupação, e cancelar devolve a cadeira; a rajada mede INSISTÊNCIA, e marcar
-- e desmarcar depressa é justamente o padrão que se quer barrar.
-- ---------------------------------------------------------------------------
create or replace function public.teto_online_rajada(p_salao uuid)
returns int language sql stable set search_path = public as $$
  select greatest(1, least(100,
    coalesce((select (cfg->>'tetoOnlineRajada')::int from public.saloes
               where id = p_salao and cfg->>'tetoOnlineRajada' ~ '^[0-9]+$'), 10)))
$$;

-- ---------------------------------------------------------------------------
-- 3) AS DUAS MEDIDAS
--
-- `minutos_online_no_dia` conta MINUTOS, não marcações: o slot tem tamanho
-- diferente para cada serviço, e contar cabeças faria uma escova de duas
-- horas valer o mesmo que uma sobrancelha de quinze minutos.
--
-- Cancelado, faltou e arquivado ficam de fora — são exatamente os estados que
-- devolvem a cadeira. Contá-los faria uma cliente que se organizou e desmarcou
-- roubar a vaga da próxima.
-- ---------------------------------------------------------------------------
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

-- Os minutos que o profissional trabalha naquele dia, pela jornada já
-- costurada — a mesma que o `horarios_livres()` percorre. Zero quer dizer
-- folga, e aí nem se chega a perguntar de reserva.
create or replace function public.minutos_de_jornada(
  p_profissional uuid, p_data date)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(extract(epoch from (j.fim - j.inicio)) / 60), 0)::int
    from public.jornada_costurada(p_profissional, p_data) j
$$;

/* Só quem o salão nunca viu: ficha aberta nas últimas 24 horas. Cliente que
   já foi atendida ali tem ficha velha e não entra nesta conta — pode marcar,
   desmarcar e remarcar à vontade, que o freio não a enxerga. */
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

-- ---------------------------------------------------------------------------
-- 4) A POLÍTICA DA AGENDA ONLINE, COM OS DOIS LIMITES NO FIM
--
-- Cópia fiel do 05_agenda.sql com um bloco a mais. Vai inteira, e não um
-- remendo, porque `create or replace function` não sabe acrescentar linha: o
-- corpo que estiver aqui é o corpo que vale.
--
-- Os limites entram por ÚLTIMO de propósito. Todas as recusas acima são sobre
-- a escolha da pessoa — serviço errado, data que passou, profissional que não
-- atende online — e ela resolve mudando a escolha. Estes dois são os únicos
-- que não têm conserto do lado dela, e mandá-la para o WhatsApp antes de
-- conferir o resto seria mandá-la embora por um motivo que talvez nem fosse o
-- dela.
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

comment on function public.teto_online_pct(uuid) is
  'Quanto da jornada de um profissional o link pode ocupar num dia. cfg.tetoOnlinePct, padrão 70.';
comment on function public.teto_online_rajada(uuid) is
  'Quantas pessoas NOVAS o link aceita no salão em 10 minutos. cfg.tetoOnlineRajada, padrão 10.';
