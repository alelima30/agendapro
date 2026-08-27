-- ===========================================================================
-- AgendaPro — 16: a comissão passa a ser do banco
--
-- ── O DEFEITO QUE ESTE ARQUIVO EXISTE PARA CONSERTAR ───────────────────────
-- A comissão de cada item da comanda vinha PRONTA do navegador. O `app.html`
-- fazia o `coalesce(servico.comissaoPct, profissional.comissaoPct)` em
-- JavaScript e mandava o número; o banco gravava o que chegasse.
--
-- Medido contra um banco de verdade, antes de escrever uma linha disto:
-- serviço cadastrado com 40% de comissão, item inserido dizendo 100%, e o
-- banco aceitou — R$ 100 de venda, R$ 100 de comissão.
--
--    descricao | preco_unit | comissao_pct | comissao_valor
--    Corte     |     100.00 |       100.00 |         100.00
--
-- O que torna isso indefensável é que a MESMA regra já era aplicada no banco
-- pelo outro caminho: quando a cliente marca pelo link, o `agendar()` resolve
-- `coalesce(sv.comissao_pct, pr.comissao_pct, 0)` dentro do Postgres. Duas
-- portas para a mesma regra, uma trancada e outra encostada — o mesmo padrão
-- que já produziu quase todo defeito sério deste projeto.
--
-- ── O QUE MUDA, E POR QUE ASSIM ────────────────────────────────────────────
-- 1. A TAXA é resolvida pelo banco e CONGELADA no item.
-- 2. O VALOR é DERIVADO da taxa congelada — não guardado.
--
-- A segunda metade é o que impede o relatório de um mês fechado de mudar
-- sozinho. Se o valor fosse recalculado ao vivo a partir do cadastro, mudar
-- a comissão de um serviço em dezembro reescreveria o faturamento de março.
-- Se a taxa fica no item, o valor é função de coisas que já não mudam mais:
-- a taxa daquele dia, o preço daquele dia, o desconto daquela comanda.
--
-- Determinístico e impossível de divergir, porque só existe UM lugar que
-- calcula: a vista `comanda_itens_calculados`. O relatório lê dela, a vista
-- de totais lê dela, a tela lê dela.
--
-- ── A ESCADA DA COMISSÃO ───────────────────────────────────────────────────
-- Ganha o primeiro degrau que DIZ ALGUMA COISA:
--
--   1. o par serviço+profissional   "a escova da Ana paga 60%"
--   2. o serviço (ou o produto)     "toda escova paga 50%"
--   3. o profissional               "a Ana paga 40% no que fizer"
--   4. nada                         zero
--
-- Cada degrau pode falar em PORCENTAGEM, em VALOR FIXO, ou nos dois — R$ 5
-- por unidade vendida mais 10% do preço é um arranjo comum em produto.
--
-- "Diz alguma coisa" é ter `comissao_pct` OU `comissao_fixa` não nulo. Um
-- degrau que diz `0` está dizendo zero de propósito, e ganha do degrau de
-- baixo: é assim que se combina "a Ana ganha 40% em tudo, MENOS na escova".
--
-- ⚠ `produtos.comissao_pct` é `not null default 0`, diferente de
-- `servicos.comissao_pct`, que é nulo para herdar. Então produto nunca herda
-- do profissional: a comissão do produto é do produto. Não é descuido, é o
-- que já estava valendo — mudar para nulo transformaria "0%" em "herda" em
-- todo salão que já usa, e ninguém pediu isso.
--
-- ── BRUTO OU LÍQUIDO, COM DATA DE CORTE ────────────────────────────────────
-- `comissao_sobre` é do SALÃO, mas fica CONGELADO NA COMANDA quando ela
-- abre. Sem isso, virar a chave hoje mudaria a comissão de toda comanda
-- ainda aberta — e a de qualquer mês que fosse reaberto.
--
-- `comissao_regra_desde` é a data de corte: a regra nova vale para comanda
-- aberta a partir dela. Antes disso, bruto, que é como sempre foi. A data
-- existe para a mudança ter um começo declarado, e não "o dia em que
-- alguém mexeu no ajuste".
--
-- O acréscimo NÃO entra na comissão, no bruto nem no líquido: taxa de
-- domingo é do salão, não é serviço de ninguém.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) ONDE A COMISSÃO PODE SER DITA
-- ---------------------------------------------------------------------------

-- O par serviço+profissional. A tabela já existia para preço e duração
-- diferentes por pessoa; comissão é a terceira coisa que varia pelo par.
alter table public.servicos_profissionais
  add column if not exists comissao_pct numeric(5,2)
    check (comissao_pct between 0 and 100);
alter table public.servicos_profissionais
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);

alter table public.servicos
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);

alter table public.produtos
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);

alter table public.profissionais
  add column if not exists comissao_fixa numeric(10,2)
    check (comissao_fixa >= 0);

-- No item, a taxa congelada. `comissao_pct` já existia; a fixa é nova.
alter table public.comanda_itens
  add column if not exists comissao_fixa numeric(10,2) not null default 0
    check (comissao_fixa >= 0);

comment on column public.comanda_itens.comissao_pct is
  'Congelada pelo gatilho no lançamento. NÃO é o que o navegador mandou.';
comment on column public.comanda_itens.comissao_fixa is
  'Por unidade: 2 itens a R$ 5 fixos = R$ 10. Congelada junto com a pct.';

-- A regra do salão, e desde quando.
alter table public.saloes
  add column if not exists comissao_sobre text not null default 'bruto'
    check (comissao_sobre in ('bruto','liquido'));
alter table public.saloes
  add column if not exists comissao_regra_desde date;

comment on column public.saloes.comissao_regra_desde is
  'A regra vale para comanda aberta a partir daqui. Nulo = nunca virou.';

-- E a regra congelada na comanda, no dia em que ela abriu.
alter table public.comandas
  add column if not exists comissao_sobre text not null default 'bruto'
    check (comissao_sobre in ('bruto','liquido'));

-- ---------------------------------------------------------------------------
-- 2) A ESCADA
-- ---------------------------------------------------------------------------
-- Devolve a taxa que vale para este item. É `stable`, não `volatile`: só lê.
--
-- Não recebe nada do navegador além de QUEM e O QUÊ — o resto sai do
-- cadastro. É essa assinatura que faz a regra ser inegociável: não há
-- parâmetro por onde passar uma taxa.
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
  'A escada: par, catálogo, pessoa, zero. Não aceita taxa por parâmetro.';

-- ---------------------------------------------------------------------------
-- 3) O GATILHO QUE CONGELA A TAXA
-- ---------------------------------------------------------------------------
-- ⚠ Ele IGNORA o que veio no INSERT. De propósito.
--
-- A tentação era conferir e recusar quando divergisse. Seria pior: a tela
-- que hoje manda a taxa continuaria mandando, e qualquer diferença de
-- arredondamento entre o JavaScript e o Postgres viraria um erro na cara da
-- recepção no meio do atendimento. Sobrescrever não tem esse risco e fecha
-- a porta do mesmo jeito.
--
-- Só recalcula quando algo que MUDA a taxa muda: o serviço, o produto ou
-- quem executou. Editar a quantidade de um item não pode reabrir a taxa —
-- se o cadastro tiver mudado no meio, o item sairia com uma comissão que
-- não é a do dia em que foi lançado.
create or replace function public.tg_item_comissao() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t record;
begin
  if tg_op = 'UPDATE'
     and new.tipo is not distinct from old.tipo
     and new.servico_id is not distinct from old.servico_id
     and new.produto_id is not distinct from old.produto_id
     and new.profissional_id is not distinct from old.profissional_id then
    -- Nada que mexa na taxa mudou: preserva a congelada.
    new.comissao_pct  := old.comissao_pct;
    new.comissao_fixa := old.comissao_fixa;
    return new;
  end if;

  select * into t from public.comissao_de(
    new.tipo, new.servico_id, new.produto_id, new.profissional_id);

  new.comissao_pct  := coalesce(t.pct, 0);
  new.comissao_fixa := coalesce(t.fixa, 0);
  return new;
end $$;

drop trigger if exists tg_item_comissao on public.comanda_itens;
create trigger tg_item_comissao
  before insert or update on public.comanda_itens
  for each row execute function public.tg_item_comissao();

-- ---------------------------------------------------------------------------
-- 4) O GATILHO QUE CONGELA A REGRA NA COMANDA
-- ---------------------------------------------------------------------------
create or replace function public.tg_comanda_regra() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_sobre text;
  v_desde date;
  v_fuso  text;
begin
  select coalesce(s.comissao_sobre, 'bruto'), s.comissao_regra_desde,
         coalesce(s.fuso, 'America/Sao_Paulo')
    into v_sobre, v_desde, v_fuso
    from public.saloes s where s.id = new.salao_id;

  -- Sem data de corte, a regra nova não vale para ninguém: virar a chave e
  -- esquecer a data não pode mudar comissão às escondidas.
  if v_desde is null
     or (new.aberta_em at time zone v_fuso)::date < v_desde then
    new.comissao_sobre := 'bruto';
  else
    new.comissao_sobre := v_sobre;
  end if;
  return new;
end $$;

drop trigger if exists tg_comanda_regra on public.comandas;
create trigger tg_comanda_regra
  before insert on public.comandas
  for each row execute function public.tg_comanda_regra();

-- ---------------------------------------------------------------------------
-- 5) O ÚNICO LUGAR QUE CALCULA COMISSÃO
-- ---------------------------------------------------------------------------
-- `comissao_valor` era uma coluna GERADA E GUARDADA:
--
--     generated always as (round(qtd * preco_unit * comissao_pct / 100, 2))
--
-- Coluna gerada só enxerga a PRÓPRIA LINHA. Comissão sobre líquido precisa
-- do desconto da comanda e do subtotal dela — que estão noutras linhas — e
-- por isso a coluna gerada não tinha como existir junto com esta regra.
--
-- Vira vista. E a vista consegue ser a única, porque tudo que ela lê já
-- está congelado: a taxa no item, a regra na comanda, o preço no item, o
-- desconto na comanda. Mudar o cadastro amanhã não mexe em nada disto.
--
-- ⚠ Rateio com centavo: o desconto é dividido entre os itens na proporção
-- do valor de cada um, e a soma dos rateios arredondados pode ficar um
-- centavo longe do desconto total. Para comissão isso é aceitável e está
-- dito aqui para ninguém "consertar" depois achando que é defeito.
drop view if exists public.comandas_totais;
drop view if exists public.comanda_itens_calculados;

alter table public.comanda_itens drop column if exists comissao_valor;

create view public.comanda_itens_calculados
with (security_invoker = true) as
  select i.id, i.comanda_id, i.tipo, i.servico_id, i.produto_id, i.descricao,
         i.qtd, i.preco_unit, i.profissional_id,
         i.comissao_pct, i.comissao_fixa, i.total,
         b.base_comissao,
         round(b.base_comissao * i.comissao_pct / 100, 2)
           + round(i.qtd * i.comissao_fixa, 2) as comissao_valor
    from public.comanda_itens i
    join public.comandas c on c.id = i.comanda_id
    cross join lateral (
      select case
               when c.comissao_sobre = 'liquido' and c.desconto > 0 and s.sub > 0
               then i.total - round(c.desconto * i.total / s.sub, 2)
               else i.total
             end as base_comissao
        from (select coalesce(sum(x.total), 0) as sub
                from public.comanda_itens x
               where x.comanda_id = i.comanda_id) s
    ) b;

comment on view public.comanda_itens_calculados is
  'O único lugar que calcula comissão. Relatório, totais e tela leem daqui.';

grant select on public.comanda_itens_calculados to authenticated;

-- ---------------------------------------------------------------------------
-- 6) A VISTA DE TOTAIS, REFEITA SOBRE A DE CIMA
-- ---------------------------------------------------------------------------
create view public.comandas_totais
with (security_invoker = true) as
  select c.id,
         c.salao_id,
         c.cliente_id,
         c.agendamento_id,
         c.numero,
         c.status,
         c.aberta_em,
         c.fechada_em,
         c.comissao_sobre,
         coalesce(i.subtotal, 0)                        as subtotal,
         c.desconto,
         c.acrescimo,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo as total,
         coalesce(i.comissao, 0)                        as comissao_total,
         coalesce(p.pago, 0)                            as pago,
         coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
           - coalesce(p.pago, 0)                        as falta,
         /* ⚠ O VOCABULÁRIO É O MESMO DE ANTES, palavra por palavra.

            Ao refazer esta vista eu escrevi 'paga', 'fechada', 'em aberto'.
            Parecia melhor português e era mudança gratuita: o
            `comanda.test.sql` reprovou com «esperava "pago", veio "paga"»,
            e estava certo — a tela mapeia estes valores em
            `{parcial:[...], pago:[...]}`, e renomear aqui apagaria a cor do
            cartão da comanda sem ninguém ligar uma coisa à outra.

            Este arquivo mexe em COMISSÃO. Trocar nome de estado de pagamento
            de carona é como se corrige uma coisa e se quebra outra. */
         case
           when c.status = 'cancelada' then 'cancelado'
           when coalesce(p.pago, 0) = 0 then 'pendente'
           when coalesce(p.pago, 0)
                >= coalesce(i.subtotal, 0) - c.desconto + c.acrescimo
             then 'pago'
           else 'parcial'
         end                                            as situacao
    from public.comandas c
    left join (select k.comanda_id,
                      sum(k.total)          as subtotal,
                      sum(k.comissao_valor) as comissao
                 from public.comanda_itens_calculados k
                group by k.comanda_id) i on i.comanda_id = c.id
    left join (select g.comanda_id, sum(g.valor) as pago
                 from public.pagamentos g
                group by g.comanda_id) p on p.comanda_id = c.id;

grant select on public.comandas_totais to authenticated;
