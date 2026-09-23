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
