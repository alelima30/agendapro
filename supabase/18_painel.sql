-- ===========================================================================
-- AgendaPro — 18: o painel do dia
--
-- ── QUE PERGUNTA ELE RESPONDE ─────────────────────────────────────────────
-- A que o dono faz ao abrir o sistema de manhã, e de novo no fim da tarde:
-- "como está hoje?". Hoje ele só tinha a agenda — que mostra horários, não
-- dinheiro — e o Relatórios, que é do MÊS e exige escolher um período.
--
-- Não é um relatório menor. É outra pergunta: o relatório olha para trás e
-- fecha contas; o painel olha para AGORA e responde o que ainda dá para
-- fazer com o dia — quem falta chegar, quanto ainda há para receber, se a
-- gaveta está aberta.
--
-- ── UMA CHAMADA SÓ, PELO MESMO MOTIVO DO RELATÓRIO ────────────────────────
-- Seis perguntas em seis chamadas seriam seis idas ao servidor para montar
-- UMA tela, e seis chances de mostrar um pedaço de hoje e outro de ontem se
-- a virada do dia acontecer no meio. Vai tudo num jsonb.
--
-- ── O DIA É O DO SALÃO ────────────────────────────────────────────────────
-- Pelo `fuso` do salão, como no relatório. Um dono olhando o painel de outro
-- fuso veria o dia começar na hora errada, e a agenda "de hoje" traria os
-- atendimentos de ontem à noite.
--
-- ── QUEM VÊ ───────────────────────────────────────────────────────────────
-- `e_gestor`. Faturamento do dia e o que falta receber são da casa, não da
-- recepção nem de quem atende — a Fase 2 pede isso em uma linha, e é a mesma
-- trava que impede ler o dia do salão do vizinho trocando o uuid.
-- ===========================================================================

create or replace function public.painel_hoje(
  p_salao uuid, p_dia date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_fuso  text;
  v_hoje  date;
  v_ini   timestamptz;
  v_fim   timestamptz;
  v_ini_o timestamptz;   -- ontem, para a comparação
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

  -- `p_dia` existe para o teste poder fixar o dia, e para o dono conseguir
  -- olhar ontem sem abrir o relatório. Sem ele, hoje NO FUSO DO SALÃO.
  v_hoje := coalesce(p_dia, (now() at time zone v_fuso)::date);

  v_ini   := (v_hoje::timestamp) at time zone v_fuso;
  v_fim   := ((v_hoje + 1)::timestamp) at time zone v_fuso;   -- exclusivo
  v_fim_o := v_ini;
  v_ini_o := v_ini - interval '1 day';

  select k.id into v_caixa
    from public.caixas k
   where k.salao_id = p_salao and k.fechado_em is null
   limit 1;

  return jsonb_build_object(
    'dia',  v_hoje,
    'fuso', v_fuso,

    /* ── A AGENDA DE HOJE ────────────────────────────────────────────────
       Contada por `inicio`, que é quando o atendimento acontece — e não por
       quando foi marcado. Arquivado fica de fora: é o mesmo critério da
       agenda na tela, e divergir aqui faria o painel contar um atendimento
       que a agenda não mostra. */
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

    /* ── O DINHEIRO DE HOJE ──────────────────────────────────────────────
       Faturamento é o das comandas FECHADAS, pelo `fechada_em` — é o mesmo
       critério do relatório, de propósito: dois números com o mesmo nome
       contados de jeitos diferentes é o defeito mais caro que um sistema
       assim pode ter, porque os dois parecem certos.

       `aReceber` é o outro lado: o que está lançado e ainda não entrou.
       Nunca soma com o faturamento — some ao lado, com nome próprio. */
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

    /* ── ONTEM, PARA SABER SE HOJE ESTÁ BOM ──────────────────────────────
       Número sozinho não diz nada: R$ 1.200 é ótimo numa terça e ruim num
       sábado. A comparação é o que transforma o número em informação. */
    'ontem', (
      select jsonb_build_object(
        'faturamento', coalesce(round(sum(t.total), 2), 0),
        'comandas',    count(*))
        from public.comandas c
        join public.comandas_totais t on t.id = c.id
       where c.salao_id = p_salao and c.status = 'fechada'
         and c.fechada_em >= v_ini_o and c.fechada_em < v_fim_o),

    /* ── A GAVETA ────────────────────────────────────────────────────────
       Só o essencial: se está aberta e quanto deveria ter. O detalhe fica
       na tela do caixa. */
    'caixa', case when v_caixa is null then null
                  else public.conferir_caixa(v_caixa) end,

    /* ── QUEM AINDA VEM ──────────────────────────────────────────────────
       Os próximos do dia, para o dono saber se pode sair para almoçar.
       Nome da cliente só para quem é gestor — e esta função já é. */
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
