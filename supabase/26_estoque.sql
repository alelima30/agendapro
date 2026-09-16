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
