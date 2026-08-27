-- ===========================================================================
-- AgendaPro — o caixa do dia e o estorno
--
-- As perguntas que este arquivo responde são as que, erradas, fazem a gaveta
-- não bater — e fazem alguém ser acusado por uma diferença que o sistema
-- criou:
--
--   0. As travas, desligadas, deixam o defeito voltar?
--   1. Dá para abrir dois caixas no mesmo salão?
--   2. O pagamento cai sozinho no caixa aberto?
--   3. Cartão e Pix ficam FORA da conta da gaveta?
--   4. Sangria e suprimento entram com o sinal certo?
--   5. Estorno maior que o pagamento passa?
--   6. Estorno em comanda fechada passa?
--   7. Depois do estorno, a comanda volta a dever?
--   8. Movimento em caixa já fechado passa?
--   9. A diferença é a conta certa, e some quando o caixa reabre a conferir?
-- ===========================================================================

\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo) values
  ('d0000000-1111-0000-0000-00000000000a', 'salao-caixa', 'Salão Caixa', 'salao');
insert into public.assinaturas (salao_id, plano, status) values
  ('d0000000-1111-0000-0000-00000000000a', 'time', 'ativa');
insert into public.profissionais (id, salao_id, nome, comissao_pct) values
  ('d0000000-5555-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a', 'Ana', 40);
insert into public.servicos (id, salao_id, nome, duracao_min, preco, comissao_pct) values
  ('d0000000-6666-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a',
   'Corte', 60, 100, 40);
insert into public.clientes (id, salao_id, nome, telefone) values
  ('d0000000-7777-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a',
   'Clara', '5511900002001');

/* ⚠ Uma DONA logada, e não só linhas na tabela.

   `conferir_caixa()` e `fechar_caixa()` conferem `ve_agenda_toda()`, que
   depende de `auth.uid()`. Sem sessão o uid é nulo, a função recusa com "Sem
   permissão neste salão", e o teste morre numa linha que não tem defeito.

   Os INSERTs continuam passando porque o teste roda como superusuário, que
   ignora RLS — mas função com `if not e_gestor(...) then raise` não é RLS: é
   código, e código não se ignora. É a mesma armadilha do `abrir_cobranca`,
   que recusava 100% das chamadas de produção por conferir permissão de quem
   não tinha sessão nenhuma. */
insert into auth.users (id, email) values
  ('d0000000-0000-0000-0000-00000000000d', 'dona-caixa@teste.com');
insert into public.perfis (id, nome, telefone) values
  ('d0000000-0000-0000-0000-00000000000d', 'Dona do Caixa', '+5511900002099')
on conflict (id) do nothing;
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('d0000000-0000-0000-0000-00000000000d',
   'd0000000-1111-0000-0000-00000000000a', 'dono', 'ativo');

select set_config('request.jwt.claim.sub',
                  'd0000000-0000-0000-0000-00000000000d', false);
select t_verdade('logada como a dona do salão',
  public.ve_agenda_toda('d0000000-1111-0000-0000-00000000000a'));

\echo ''
\echo '1) Um caixa aberto por salão'

insert into public.caixas (id, salao_id, valor_abertura) values
  ('d0000000-cccc-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a', 200);

select t_verdade('o segundo caixa aberto é recusado',
  recusado($q$
    insert into public.caixas (salao_id, valor_abertura)
    values ('d0000000-1111-0000-0000-00000000000a', 50)
  $q$));

-- Mas outro SALÃO abre o dele sem problema: a trava é por salão.
insert into public.saloes (id, slug, nome, tipo) values
  ('d0000000-1111-0000-0000-00000000000b', 'outro-caixa', 'Outro', 'salao');
insert into public.assinaturas (salao_id, plano, status) values
  ('d0000000-1111-0000-0000-00000000000b', 'time', 'ativa');

select t_verdade('outro salão abre o caixa dele',
  not recusado($q$
    insert into public.caixas (salao_id, valor_abertura)
    values ('d0000000-1111-0000-0000-00000000000b', 30)
  $q$));

\echo ''
\echo '2) O pagamento cai sozinho no caixa aberto'

insert into public.comandas (id, salao_id, cliente_id, status) values
  ('d0000000-aaaa-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a',
   'd0000000-7777-0000-0000-00000000000a', 'aberta');
insert into public.comanda_itens
  (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('d0000000-aaaa-0000-0000-00000000000a', 'servico',
        'd0000000-6666-0000-0000-00000000000a', 'Corte', 1, 100,
        'd0000000-5555-0000-0000-00000000000a');

insert into public.pagamentos (id, comanda_id, forma, valor) values
  ('d0000000-9999-0000-0000-00000000000a', 'd0000000-aaaa-0000-0000-00000000000a',
   'dinheiro', 60);

select t_verdade('o pagamento achou o caixa aberto sozinho',
  (select caixa_id from public.pagamentos
    where id = 'd0000000-9999-0000-0000-00000000000a')
  = 'd0000000-cccc-0000-0000-00000000000a');

\echo ''
\echo '3) Cartão e Pix ficam FORA da conta da gaveta'

-- Se entrassem, a recepção passaria a tarde procurando uma diferença que é
-- só a maquininha.
insert into public.pagamentos (id, comanda_id, forma, valor) values
  ('d0000000-9999-0000-0000-00000000000b', 'd0000000-aaaa-0000-0000-00000000000a',
   'credito', 40);

select t_verdade('o esperado conta só o dinheiro (200 + 60 = 260)',
  (public.conferir_caixa('d0000000-cccc-0000-0000-00000000000a')->>'esperado')::numeric
  = 260.00);

select t_verdade('e o crédito aparece à parte',
  (public.conferir_caixa('d0000000-cccc-0000-0000-00000000000a')
     ->'outrosMeios'->0->>'valor')::numeric = 40.00);

\echo ''
\echo '4) Sangria e suprimento, cada um com o seu sinal'

insert into public.caixa_movimentos (caixa_id, salao_id, tipo, valor, motivo) values
  ('d0000000-cccc-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a',
   'sangria', 100, 'levei ao banco'),
  ('d0000000-cccc-0000-0000-00000000000a', 'd0000000-1111-0000-0000-00000000000a',
   'suprimento', 30, 'troco para o dia');

select t_verdade('esperado = 200 + 60 + 30 - 100 = 190',
  (public.conferir_caixa('d0000000-cccc-0000-0000-00000000000a')->>'esperado')::numeric
  = 190.00);

select t_verdade('sangria sem motivo é recusada',
  recusado($q$
    insert into public.caixa_movimentos (caixa_id, salao_id, tipo, valor, motivo)
    values ('d0000000-cccc-0000-0000-00000000000a',
            'd0000000-1111-0000-0000-00000000000a', 'sangria', 10, '')
  $q$));

\echo ''
\echo '5) Não se estorna mais do que se recebeu'

select t_verdade('estorno de 100 num pagamento de 60 é recusado',
  recusado($q$
    insert into public.estornos (pagamento_id, salao_id, valor, motivo)
    values ('d0000000-9999-0000-0000-00000000000a',
            'd0000000-1111-0000-0000-00000000000a', 100, 'valor errado')
  $q$));

-- Dois estornos parciais que somados passam também não podem.
insert into public.estornos (pagamento_id, salao_id, valor, motivo) values
  ('d0000000-9999-0000-0000-00000000000a',
   'd0000000-1111-0000-0000-00000000000a', 40, 'digitei a mais');

select t_verdade('o segundo estorno parcial que estoura também é recusado',
  recusado($q$
    insert into public.estornos (pagamento_id, salao_id, valor, motivo)
    values ('d0000000-9999-0000-0000-00000000000a',
            'd0000000-1111-0000-0000-00000000000a', 30, 'de novo')
  $q$));

select t_verdade('mas o que cabe passa (faltavam 20)',
  not recusado($q$
    insert into public.estornos (pagamento_id, salao_id, valor, motivo)
    values ('d0000000-9999-0000-0000-00000000000a',
            'd0000000-1111-0000-0000-00000000000a', 20, 'o resto')
  $q$));

\echo ''
\echo '6) O estorno desconta da gaveta e da comanda'

-- 60 recebidos, 60 estornados: a gaveta volta a 200 + 0 + 30 - 100 = 130.
select t_verdade('a gaveta desconta o que foi devolvido (130)',
  (public.conferir_caixa('d0000000-cccc-0000-0000-00000000000a')->>'esperado')::numeric
  = 130.00);

-- E a comanda volta a dever: 100 de total, 40 no crédito, 60 devolvidos.
select t_verdade('a comanda volta a dever os 60 (falta = 60)',
  (select falta from public.comandas_totais
    where id = 'd0000000-aaaa-0000-0000-00000000000a') = 60.00);

select t_verdade('e a situação sai de "pago" para "parcial"',
  (select situacao from public.comandas_totais
    where id = 'd0000000-aaaa-0000-0000-00000000000a') = 'parcial');

\echo ''
\echo '7) Comanda fechada não estorna — reabra antes'

-- Uma comanda paga por inteiro, fechada.
insert into public.comandas (id, salao_id, cliente_id, status) values
  ('d0000000-aaaa-0000-0000-00000000000b', 'd0000000-1111-0000-0000-00000000000a',
   'd0000000-7777-0000-0000-00000000000a', 'aberta');
insert into public.comanda_itens
  (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('d0000000-aaaa-0000-0000-00000000000b', 'servico',
        'd0000000-6666-0000-0000-00000000000a', 'Corte', 1, 100,
        'd0000000-5555-0000-0000-00000000000a');
insert into public.pagamentos (id, comanda_id, forma, valor) values
  ('d0000000-9999-0000-0000-00000000000c', 'd0000000-aaaa-0000-0000-00000000000b',
   'dinheiro', 100);
update public.comandas set status = 'fechada'
 where id = 'd0000000-aaaa-0000-0000-00000000000b';

select t_texto('estornar comanda fechada explica o que fazer',
  erro_de($q$
    insert into public.estornos (pagamento_id, salao_id, valor, motivo)
    values ('d0000000-9999-0000-0000-00000000000c',
            'd0000000-1111-0000-0000-00000000000a', 100, 'devolvido')
  $q$),
  'Reabra a comanda antes de estornar este pagamento.');

-- Reabrindo, passa.
update public.comandas set status = 'aberta', fechada_em = null
 where id = 'd0000000-aaaa-0000-0000-00000000000b';

select t_verdade('com a comanda reaberta, o estorno passa',
  not recusado($q$
    insert into public.estornos (pagamento_id, salao_id, valor, motivo)
    values ('d0000000-9999-0000-0000-00000000000c',
            'd0000000-1111-0000-0000-00000000000a', 100, 'devolvido')
  $q$));

select t_verdade('e ela não fecha mais enquanto não for paga de novo',
  recusado($q$
    update public.comandas set status = 'fechada'
     where id = 'd0000000-aaaa-0000-0000-00000000000b'
  $q$));

\echo ''
\echo '8) O salão do estorno é o da comanda, não o que mandaram'

-- Mandar o salão errado seria uma linha de dinheiro contada no salão do
-- vizinho — e o RLS a esconderia de quem deveria vê-la.
insert into public.pagamentos (id, comanda_id, forma, valor) values
  ('d0000000-9999-0000-0000-00000000000d', 'd0000000-aaaa-0000-0000-00000000000b',
   'dinheiro', 50);
insert into public.estornos (id, pagamento_id, salao_id, valor, motivo) values
  ('d0000000-eeee-0000-0000-00000000000a', 'd0000000-9999-0000-0000-00000000000d',
   'd0000000-1111-0000-0000-00000000000b', 50, 'salao errado de proposito');

select t_verdade('o gatilho corrigiu o salão do estorno',
  (select salao_id from public.estornos
    where id = 'd0000000-eeee-0000-0000-00000000000a')
  = 'd0000000-1111-0000-0000-00000000000a');

\echo ''
\echo '9) Fechar o caixa, e o que acontece depois'

do $$
declare r jsonb;
begin
  -- Conta 120 na gaveta quando o esperado é 130: faltam 10.
  r := public.fechar_caixa('d0000000-cccc-0000-0000-00000000000a', 120, 'faltou troco');
  if (r->>'diferenca')::numeric = -10.00 then
    perform t_ok('a diferença sai negativa quando falta na gaveta (-10)');
  else
    perform t_falha(format('esperava -10,00 e veio %s', r->>'diferenca'));
  end if;
end $$;

select t_verdade('caixa fechado não fecha de novo',
  recusado($q$ select public.fechar_caixa('d0000000-cccc-0000-0000-00000000000a', 130) $q$));

select t_verdade('movimento em caixa fechado é recusado',
  recusado($q$
    insert into public.caixa_movimentos (caixa_id, salao_id, tipo, valor, motivo)
    values ('d0000000-cccc-0000-0000-00000000000a',
            'd0000000-1111-0000-0000-00000000000a', 'sangria', 5, 'atrasada')
  $q$));

-- Com o caixa do dia fechado, dá para abrir o de amanhã.
select t_verdade('com o anterior fechado, abre-se outro',
  not recusado($q$
    insert into public.caixas (salao_id, valor_abertura)
    values ('d0000000-1111-0000-0000-00000000000a', 120)
  $q$));

\echo ''
\echo '10) Estorno é registro: não se apaga nem se edita'

select t_verdade('authenticated não tem update em estornos',
  not exists (select 1 from information_schema.role_table_grants
               where table_name = 'estornos' and grantee = 'authenticated'
                 and privilege_type = 'UPDATE'));

select t_verdade('nem delete',
  not exists (select 1 from information_schema.role_table_grants
               where table_name = 'estornos' and grantee = 'authenticated'
                 and privilege_type = 'DELETE'));

select t_verdade('e anon não alcança o caixa',
  not exists (select 1 from information_schema.role_table_grants
               where table_name in ('caixas','caixa_movimentos','estornos')
                 and grantee = 'anon'));
