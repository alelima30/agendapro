-- ===========================================================================
-- AgendaPro — a comanda dá baixa no estoque
--
-- ── OS DOIS DEFEITOS QUE ESTE ARQUIVO EXISTE PARA PEGAR ───────────────────
--
-- 1. BAIXA DOBRADA. O gatilho é `after update of status`, e o painel grava a
--    comanda inteira ao salvar — inclusive quando o status não mudou. Sem a
--    guarda de transição, cada gravação repetida tirava o produto do estoque
--    de novo, e o número descia sozinho sem venda nenhuma.
--
-- 2. ASSIMETRIA. Fechar tira; reabrir tem que devolver EXATAMENTE o mesmo.
--    Se as duas metades divergirem, cada ciclo de abre-fecha deixa um resto —
--    e o erro se acumula devagar, que é o formato mais difícil de enxergar:
--    ninguém nota no dia, e em dois meses o estoque não bate com nada.
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── Cenário: um salão com um produto contado ──────────────────────────────
insert into auth.users (id) values
  ('c1000000-0000-0000-0000-00000000000a') on conflict do nothing;
insert into public.perfis (id, nome, email) values
  ('c1000000-0000-0000-0000-00000000000a', 'Dona do Estoque', 'est@teste.com')
  on conflict (id) do update
    set nome = excluded.nome, email = excluded.email;
insert into public.saloes (id, slug, nome) values
  ('c1000000-1111-0000-0000-00000000000b', 'salao-estoque', 'Salão do Estoque');
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('c1000000-0000-0000-0000-00000000000a',
   'c1000000-1111-0000-0000-00000000000b', 'dono', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values
  ('c1000000-1111-0000-0000-00000000000b', 'duo', 'ativa');
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c1000000-3333-0000-0000-00000000000e',
   'c1000000-1111-0000-0000-00000000000b', 'Cliente do Balcão', '11977776666');

insert into public.produtos (id, salao_id, nome, preco, estoque) values
  ('c1000000-2222-0000-0000-00000000000c',
   'c1000000-1111-0000-0000-00000000000b', 'Pomada', 30.00, 10),
  ('c1000000-2222-0000-0000-00000000000d',
   'c1000000-1111-0000-0000-00000000000b', 'Shampoo', 45.00, 1);

/* Abre uma comanda com itens e devolve o id. O pagamento entra junto, porque
   o `tg_fechar_comanda` exige a conta paga para deixar fechar. */
create or replace function comanda_de(p_pomada numeric, p_shampoo numeric)
returns uuid language plpgsql as $$
declare v_id uuid; v_total numeric := 0;
begin
  insert into public.comandas (salao_id, cliente_id)
       values ('c1000000-1111-0000-0000-00000000000b',
               'c1000000-3333-0000-0000-00000000000e')
  returning id into v_id;

  if p_pomada > 0 then
    insert into public.comanda_itens
      (comanda_id, tipo, produto_id, descricao, qtd, preco_unit)
    values (v_id, 'produto', 'c1000000-2222-0000-0000-00000000000c',
            'Pomada', p_pomada, 30.00);
    v_total := v_total + p_pomada * 30.00;
  end if;
  if p_shampoo > 0 then
    insert into public.comanda_itens
      (comanda_id, tipo, produto_id, descricao, qtd, preco_unit)
    values (v_id, 'produto', 'c1000000-2222-0000-0000-00000000000d',
            'Shampoo', p_shampoo, 45.00);
    v_total := v_total + p_shampoo * 45.00;
  end if;

  insert into public.pagamentos (comanda_id, forma, valor)
       values (v_id, 'dinheiro', v_total);
  return v_id;
end $$;

create or replace function estoque_de(p_id uuid) returns numeric
language sql as $$ select estoque from public.produtos where id = p_id $$;

\echo ''
\echo 'FECHAR TIRA DO ESTOQUE'

select comanda_de(2, 0) as c1 \gset

select t_verdade('enquanto a comanda está aberta, o estoque não se mexe',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 10);

update public.comandas set status = 'fechada' where id = :'c1';

select t_verdade('ao fechar, saem as 2 unidades vendidas',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 8);

\echo ''
\echo 'E GRAVAR DE NOVO NÃO TIRA OUTRA VEZ'

/* ⚠ O painel grava a comanda inteira ao salvar, inclusive com o status igual —
   e `after update of status` dispara sempre que a coluna aparece no SET, mesmo
   sem o valor mudar.

   Quem impede a baixa dobrada é o `old.status <> 'fechada'` do gatilho.
   Simplificar para `if new.status = 'fechada'` parece inofensivo e faz o
   estoque descer sozinho, sem venda nenhuma — foi contra ESSA mutação que
   esta verificação foi medida.

   (A primeira versão dela foi medida contra a mutação errada: eu tinha posto
   no gatilho uma guarda `is not distinct from` que era redundante, e removê-la
   não reprovava nada. Um teste que não consegue falhar é pior que teste
   nenhum — parece cobertura e não é.) */
update public.comandas set status = 'fechada' where id = :'c1';
update public.comandas set status = 'fechada' where id = :'c1';

select t_verdade('três gravações de "fechada" dão UMA baixa só',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 8);

\echo ''
\echo 'REABRIR DEVOLVE EXATAMENTE O MESMO'

update public.comandas set status = 'aberta' where id = :'c1';
select t_verdade('reabriu, voltou para 10',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 10);

/* ⚠ E o ciclo não pode deixar resto. Se fechar e reabrir divergirem em
   qualquer coisa, o erro se acumula devagar — ninguém nota no dia, e em dois
   meses o estoque não bate com nada. */
do $$
declare i int;
begin
  for i in 1..5 loop
    update public.comandas set status = 'fechada' where id = (select id from public.comandas
      where salao_id = 'c1000000-1111-0000-0000-00000000000b' order by aberta_em limit 1);
    update public.comandas set status = 'aberta'  where id = (select id from public.comandas
      where salao_id = 'c1000000-1111-0000-0000-00000000000b' order by aberta_em limit 1);
  end loop;
end $$;

select t_verdade('cinco ciclos de abre-fecha não deixam resto',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 10);

\echo ''
\echo 'CANCELAR UMA COMANDA FECHADA TAMBÉM DEVOLVE'

update public.comandas set status = 'fechada'  where id = :'c1';
update public.comandas set status = 'cancelada' where id = :'c1';
select t_verdade('cancelou depois de fechada, o estoque volta',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 10);

\echo ''
\echo 'E A BAIXA NUNCA RECUSA O FECHAMENTO'

/* ⚠ O Shampoo tem 1 em estoque, e a cliente está levando 3.

   Recusar aqui seria o sistema travando uma venda que já aconteceu — a pessoa
   no balcão, o dinheiro na mesa — por causa de um número que ninguém atualiza
   desde março. O salão não desfaz a venda; ele para de usar o sistema.

   Negativo é informação: "você vendeu mais do que tinha registrado". */
select comanda_de(0, 3) as c2 \gset
update public.comandas set status = 'fechada' where id = :'c2';

select t_verdade('vender mais do que tem fecha a comanda do mesmo jeito',
  (select status from public.comandas where id = :'c2') = 'fechada');
select t_verdade('e o estoque fica NEGATIVO, que é o aviso',
  estoque_de('c1000000-2222-0000-0000-00000000000d') = -2);

\echo ''
\echo 'SERVIÇO NÃO MEXE EM ESTOQUE'

insert into public.servicos (id, salao_id, nome, duracao_min, preco) values
  ('c1000000-4444-0000-0000-00000000000f',
   'c1000000-1111-0000-0000-00000000000b', 'Corte', 30, 50.00);

do $$
declare v uuid;
begin
  insert into public.comandas (salao_id, cliente_id)
       values ('c1000000-1111-0000-0000-00000000000b',
               'c1000000-3333-0000-0000-00000000000e') returning id into v;
  insert into public.comanda_itens
    (comanda_id, tipo, servico_id, descricao, qtd, preco_unit)
  values (v, 'servico', 'c1000000-4444-0000-0000-00000000000f', 'Corte', 1, 50.00);
  insert into public.pagamentos (comanda_id, forma, valor) values (v, 'dinheiro', 50.00);
  update public.comandas set status = 'fechada' where id = v;
end $$;

select t_verdade('comanda só de serviço não mexe em produto nenhum',
  estoque_de('c1000000-2222-0000-0000-00000000000c') = 10
  and estoque_de('c1000000-2222-0000-0000-00000000000d') = -2);

\echo ''
\echo 'E O GATILHO OBEDECE A REGRA DA CASA'

select t_verdade('o gatilho do estoque é security definer',
  (select prosecdef from pg_proc where proname = 'tg_comanda_estoque'));
select t_falso('e ninguém de navegador o executa direto',
  has_function_privilege('authenticated', 'public.tg_comanda_estoque()', 'EXECUTE'));
