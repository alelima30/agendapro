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
