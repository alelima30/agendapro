-- ===========================================================================
-- AgendaPro — o Crediário (47_crediario.sql)
--
-- A Maria leva uma lingerie de R$ 300: R$ 100 de entrada no Pix e o resto
-- em 2x de R$ 100, a primeira daqui a um mês. A Ju ganha 10% de comissão.
--
--   1. o CPF é conferido pelo dígito;
--   2. sem o módulo, não vende (e diz onde contratar); sem CPF, não vende;
--   3. a venda: a comanda fecha com a entrada e o crediário, as parcelas
--      nascem (os centavos na primeira), e ninguém digita um "crediario" à mão,
--      nem reabre a comanda por baixo;
--   4. o relatório: vendido no faturamento, a comissão só da parte paga;
--   5. receber parte da parcela, em dinheiro: entra na gaveta, a comissão
--      da parte recebida conta hoje; não recebe a mais; desfazer é da gestão;
--   6. desfazer a venda no crediário só sem nada recebido;
--   7. módulo cancelado: não vende novo, mas recebe o que já deve;
--   8. quem atende não vê nada disso.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4700000-0000-0000-0000-00000000000a'),  -- Ana  — dona
  ('b4700000-0000-0000-0000-00000000000b'),  -- Rita — recepção
  ('d4700000-0000-0000-0000-00000000000d');  -- Ju   — profissional
insert into public.perfis (id, nome, telefone) values
  ('a4700000-0000-0000-0000-00000000000a', 'Ana',  '+5511947000001'),
  ('b4700000-0000-0000-0000-00000000000b', 'Rita', '+5511947000002'),
  ('d4700000-0000-0000-0000-00000000000d', 'Ju',   '+5511947000004')
on conflict (id) do update set nome = excluded.nome;
insert into public.saloes (id, slug, nome, tipo, fuso) values
  ('54700000-0000-0000-0000-00000000000a', 'crediario-ana', 'Lingerie da Ana', 'salao', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('54700000-0000-0000-0000-00000000000a', 'individual', 'ativa', current_date + 20);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a4700000-0000-0000-0000-00000000000a', '54700000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('b4700000-0000-0000-0000-00000000000b', '54700000-0000-0000-0000-00000000000a', 'recepcao', 'ativo'),
  ('d4700000-0000-0000-0000-00000000000d', '54700000-0000-0000-0000-00000000000a', 'profissional', 'ativo');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct) values
  ('94700000-0000-0000-0000-00000000000d', '54700000-0000-0000-0000-00000000000a',
   'd4700000-0000-0000-0000-00000000000d', 'Ju', 10);
insert into public.servicos (id, salao_id, nome, duracao_min, preco, comissao_pct) values
  ('54710000-0000-0000-0000-0000000000a1', '54700000-0000-0000-0000-00000000000a', 'Conjunto renda', 30, 300, 10);
insert into public.clientes (id, salao_id, nome, telefone, cpf) values
  ('c4710000-0000-0000-0000-00000000000a', '54700000-0000-0000-0000-00000000000a', 'Maria Souza', '5511947000003', '52998224725'),
  ('c4710000-0000-0000-0000-00000000000b', '54700000-0000-0000-0000-00000000000a', 'Joana Lima',  '5511947000005', null);
insert into public.comandas (id, salao_id, cliente_id, status) values
  ('54720000-0000-0000-0000-00000000000a', '54700000-0000-0000-0000-00000000000a', 'c4710000-0000-0000-0000-00000000000a', 'aberta'),
  ('54720000-0000-0000-0000-00000000000b', '54700000-0000-0000-0000-00000000000a', 'c4710000-0000-0000-0000-00000000000b', 'aberta'),
  ('54720000-0000-0000-0000-00000000000c', '54700000-0000-0000-0000-00000000000a', 'c4710000-0000-0000-0000-00000000000a', 'aberta');
insert into public.comanda_itens (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id, comissao_pct)
  select c, 'servico', '54710000-0000-0000-0000-0000000000a1', 'Conjunto renda', 1,
         case when c = '54720000-0000-0000-0000-00000000000c' then 100 else 300 end,
         '94700000-0000-0000-0000-00000000000d', 10
    from unnest(array['54720000-0000-0000-0000-00000000000a', '54720000-0000-0000-0000-00000000000b',
                      '54720000-0000-0000-0000-00000000000c']::uuid[]) c;
insert into public.pagamentos (comanda_id, forma, valor) values
  ('54720000-0000-0000-0000-00000000000a', 'pix', 100);
insert into public.caixas (id, salao_id, valor_abertura) values
  ('54730000-0000-0000-0000-00000000000a', '54700000-0000-0000-0000-00000000000a', 50);
grant usage on schema auth to anon, authenticated;

select (public.hoje_no_salao('54700000-0000-0000-0000-00000000000a') + 30) as primeiro \gset

-- Uma chamada como a recepção (ou outra pessoa), numa transação só.
create or replace function t_como(p_quem uuid, p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_quem::text, true);
  set local role authenticated;
  execute p_sql into r;
  reset role;
  return r;
end $$;

\echo ''
\echo '1. O CPF'
select t_verdade('CPF de verdade passa', public.cpf_valido('529.982.247-25'));
select t_falso('dígito errado não passa', public.cpf_valido('529.982.247-24'));
select t_falso('111.111.111-11 não é de ninguém', public.cpf_valido('11111111111'));
select t_falso('nem número curto', public.cpf_valido('1234567890'));

\echo ''
\echo '2. Quando não vende'
select t_verdade('sem o módulo: diz que é módulo adicional e onde contratar',
  erro_de(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.vender_no_crediario(%L, 2, %L)', '54720000-0000-0000-0000-00000000000a', :'primeiro')))
  like 'Vender no crediário faz parte do módulo adicional Crediário%');
-- A Ana contratou (aqui, direto: a contratação está no adicionais.test.sql).
update public.adicionais set ativo = true where codigo = 'crediario';
insert into public.salao_adicionais (salao_id, adicional, status, ativo_desde)
  values ('54700000-0000-0000-0000-00000000000a', 'crediario', 'ativo', now());
select t_verdade('a Joana sem CPF: "a ficha precisa de um CPF válido"',
  erro_de(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.vender_no_crediario(%L, 2, %L)', '54720000-0000-0000-0000-00000000000b', :'primeiro')))
  like '%CPF válido%');
select t_verdade('vencimento no passado não serve',
  erro_de(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.vender_no_crediario(%L, 2, %L)', '54720000-0000-0000-0000-00000000000a',
           (:'primeiro'::date - 40)::text)))
  like 'O primeiro vencimento%');
select t_verdade('quem atende não vende no crediário',
  recusado(format($$select t_como(%L, %L)$$, 'd4700000-0000-0000-0000-00000000000d',
    format('select public.vender_no_crediario(%L, 2, %L)', '54720000-0000-0000-0000-00000000000a', :'primeiro'))));

\echo ''
\echo '3. A venda'
select t_como('b4700000-0000-0000-0000-00000000000b',
  format('select public.vender_no_crediario(%L, 2, %L)', '54720000-0000-0000-0000-00000000000a', :'primeiro')) as venda \gset
select t_texto('a recepção vende: R$ 200 em 2x de R$ 100',
  (:'venda'::jsonb->>'valor') || ' | ' || (:'venda'::jsonb->'parcelas'->0->>'valor') || ' + '
    || (:'venda'::jsonb->'parcelas'->1->>'valor'), '200.00 | 100.00 + 100.00');
select t_texto('a primeira daqui a um mês, a segunda no mesmo dia do mês seguinte',
  (select string_agg(vence_em::text, ' / ' order by numero) from public.crediario_parcelas
    where crediario_id = (:'venda'::jsonb->>'crediario')::uuid),
  :'primeiro' || ' / ' || ((:'primeiro'::date + interval '1 month')::date)::text);
select t_texto('a comanda fecha, com a entrada e o crediário',
  (select c.status || ' | ' || (select string_agg(p.forma || ' ' || p.valor, ' + ' order by p.valor)
                                  from public.pagamentos p where p.comanda_id = c.id)
     from public.comandas c where c.id = '54720000-0000-0000-0000-00000000000a'),
  'fechada | pix 100.00 + crediario 200.00');
select t_como('b4700000-0000-0000-0000-00000000000b',
  format('select public.vender_no_crediario(%L, 3, %L)', '54720000-0000-0000-0000-00000000000c', :'primeiro')) as venda3 \gset
select t_texto('R$ 100 em 3x: os centavos vão para a primeira',
  (select string_agg(valor::text, ' + ' order by numero) from public.crediario_parcelas
    where crediario_id = (:'venda3'::jsonb->>'crediario')::uuid), '33.34 + 33.33 + 33.33');
select t_verdade('ninguém digita um "crediario" à mão na comanda',
  erro_de($$insert into public.pagamentos (comanda_id, forma, valor)
    values ('54720000-0000-0000-0000-00000000000b', 'crediario', 300)$$) like 'Venda no crediário é pelo botão%');
select t_verdade('nem reabre a comanda vendida no crediário',
  erro_de($$update public.comandas set status = 'aberta', fechada_em = null
    where id = '54720000-0000-0000-0000-00000000000a'$$) like 'Esta comanda foi vendida no crediário%');

\echo ''
\echo '4. O relatório da venda'
select t_como('a4700000-0000-0000-0000-00000000000a',
  format('select public.relatorio(%L, current_date - 1, current_date + 1)', '54700000-0000-0000-0000-00000000000a')) as rel \gset
select t_texto('faturamento: a venda inteira, no dia da venda (R$ 300 + R$ 100)',
  :'rel'::jsonb->>'faturamento', '400.00');
select t_texto('e o que entrou como crediário aparece nas formas',
  (select f->>'valor' from jsonb_array_elements(:'rel'::jsonb->'formas') f where f->>'forma' = 'crediario'), '300.00');
select t_texto('a comissão da Ju: só a parte paga na hora (R$ 10 de R$ 30; a de R$ 100 em 3x, nada)',
  (select c->>'comissao' from jsonb_array_elements(:'rel'::jsonb->'comissoes') c where c->>'nome' = 'Ju'), '10.00');
select t_texto('o crediário do período: vendido R$ 300, a receber R$ 300, nada atrasado',
  (:'rel'::jsonb->'crediario'->>'vendido') || ' | ' || (:'rel'::jsonb->'crediario'->>'aReceber')
    || ' | ' || (:'rel'::jsonb->'crediario'->>'atrasado'), '300.00 | 300.00 | 0');

\echo ''
\echo '5. Receber'
select (select id from public.crediario_parcelas where crediario_id = (:'venda'::jsonb->>'crediario')::uuid
         and numero = 1) as p1 \gset
select t_texto('a Maria paga R$ 60 da primeira, em dinheiro: sobram R$ 40',
  t_como('b4700000-0000-0000-0000-00000000000b',
    format('select public.receber_parcela(%L, 60, %L)', :'p1', 'dinheiro'))->>'saldo', '40.00');
select t_como('b4700000-0000-0000-0000-00000000000b',
  format('select public.conferir_caixa(%L)', '54730000-0000-0000-0000-00000000000a')) as cx \gset
select t_texto('entra na gaveta: R$ 50 de troco + R$ 60',
  :'cx'::jsonb->>'esperado', '110.00');
select t_falso('e o "crediario" da venda não aparece como dinheiro recebido no caixa',
  exists (select 1 from jsonb_array_elements(:'cx'::jsonb->'outrosMeios') m where m->>'forma' = 'crediario'));
select t_como('a4700000-0000-0000-0000-00000000000a',
  format('select public.relatorio(%L, current_date - 1, current_date + 1)', '54700000-0000-0000-0000-00000000000a')) as rel2 \gset
select t_texto('a comissão da parte recebida conta hoje: R$ 10 + R$ 6',
  (select c->>'comissao' from jsonb_array_elements(:'rel2'::jsonb->'comissoes') c where c->>'nome' = 'Ju'), '16.00');
select t_texto('   sem contar a parcela como item vendido de novo',
  (select c->>'itens' || ' | ' || (c->>'vendido') from jsonb_array_elements(:'rel2'::jsonb->'comissoes') c
    where c->>'nome' = 'Ju'), '2 | 400.00');
select t_texto('o recebido do período: R$ 60, e o faturamento não muda',
  (:'rel2'::jsonb->'crediario'->>'recebido') || ' | ' || (:'rel2'::jsonb->>'faturamento'), '60.00 | 400.00');
select t_texto('o painel do dia soma a mesma comissão',
  t_como('a4700000-0000-0000-0000-00000000000a',
    format('select public.painel_hoje(%L)', '54700000-0000-0000-0000-00000000000a'))->'dinheiro'->>'comissoes',
  '16.00');
select t_verdade('não recebe mais do que está em aberto',
  erro_de(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.receber_parcela(%L, 50, %L)', :'p1', 'pix'))) like 'Esta parcela tem R$ 40,00 em aberto%');
select (select id from public.crediario_recebimentos where parcela_id = :'p1') as rec1 \gset
select t_verdade('desfazer o recebimento não é da recepção',
  recusado(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.desfazer_recebimento_crediario(%L)', :'rec1'))));
select t_como('a4700000-0000-0000-0000-00000000000a',
  format('select public.desfazer_recebimento_crediario(%L)', :'rec1'));
select t_texto('a dona desfaz: a parcela volta a R$ 100 e a gaveta volta a R$ 50',
  public.saldo_da_parcela(:'p1') || ' | ' || (t_como('a4700000-0000-0000-0000-00000000000a',
    format('select public.conferir_caixa(%L)', '54730000-0000-0000-0000-00000000000a'))->>'esperado'),
  '100.00 | 50.00');
select t_como('b4700000-0000-0000-0000-00000000000b',
  format('select public.receber_parcela(%L, 100, %L)', :'p1', 'pix'));
select t_texto('paga inteira no Pix: quitada', public.saldo_da_parcela(:'p1')::text, '0.00');

\echo ''
\echo '6. Desfazer a venda no crediário'
select t_verdade('com parcela recebida, não desfaz',
  erro_de(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.desfazer_crediario(%L)', :'venda'::jsonb->>'crediario'))) like 'Já há parcela recebida%');
select t_como('b4700000-0000-0000-0000-00000000000b',
  format('select public.desfazer_crediario(%L)', :'venda3'::jsonb->>'crediario'));
select t_texto('sem nada recebido: a comanda volta aberta, devendo os R$ 100',
  (select c.status || ' | ' || t.falta from public.comandas c join public.comandas_totais t on t.id = c.id
    where c.id = '54720000-0000-0000-0000-00000000000c'), 'aberta | 100.00');

\echo ''
\echo '7. Módulo cancelado'
update public.salao_adicionais set status = 'cancelado', vale_ate = current_date - 1
 where salao_id = '54700000-0000-0000-0000-00000000000a';
select t_verdade('não vende fiado novo',
  recusado(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.vender_no_crediario(%L, 2, %L)', '54720000-0000-0000-0000-00000000000c', :'primeiro'))));
select (select id from public.crediario_parcelas where crediario_id = (:'venda'::jsonb->>'crediario')::uuid
         and numero = 2) as p2 \gset
select t_texto('mas recebe o que a Maria já deve',
  t_como('b4700000-0000-0000-0000-00000000000b',
    format('select public.receber_parcela(%L, 100, %L)', :'p2', 'debito'))->>'saldo', '0.00');
select t_texto('e a tela do crediário continua mostrando a venda',
  jsonb_array_length(t_como('b4700000-0000-0000-0000-00000000000b',
    format('select public.crediario_painel(%L)', '54700000-0000-0000-0000-00000000000a'))->'vendas')::text, '1');

\echo ''
\echo '7b. A venda direto na tela do crediário (sem comanda na tela)'
update public.salao_adicionais set status = 'ativo', vale_ate = null
 where salao_id = '54700000-0000-0000-0000-00000000000a';
insert into public.produtos (id, salao_id, nome, preco) values
  ('54740000-0000-0000-0000-0000000000a1', '54700000-0000-0000-0000-00000000000a', 'Sutiã renda', 120);
select t_como('b4700000-0000-0000-0000-00000000000b',
  format('select public.nova_venda_no_crediario(%L, %L, %L, %L, %s, %s, %L, %s, %L)',
    '54700000-0000-0000-0000-00000000000a', 'c4710000-0000-0000-0000-00000000000a',
    '[{"tipo":"produto","id":"54740000-0000-0000-0000-0000000000a1","qtd":2,"preco":1}]',
    '94700000-0000-0000-0000-00000000000d', 0, 40, 'pix', 2, :'primeiro')) as direta \gset
select t_texto('2 sutiãs pelo preço do cadastro (o preço mandado pela tela é ignorado): R$ 240, R$ 40 de entrada, 2x de R$ 100',
  (select t.total || ' | ' || (select string_agg(p.forma || ' ' || p.valor, ' + ' order by p.valor)
                                from public.pagamentos p where p.comanda_id = t.id)
     from public.comandas_totais t where t.id = (:'direta'::jsonb->>'comanda')::uuid)
    || ' | ' || (:'direta'::jsonb->'parcelas'->0->>'valor'),
  '240.00 | pix 40.00 + crediario 200.00 | 100.00');
select t_texto('   a comanda por baixo está fechada (vai ao faturamento e ao estoque)',
  (select status from public.comandas where id = (:'direta'::jsonb->>'comanda')::uuid), 'fechada');
select t_verdade('entrada que cobre tudo não vira crediário',
  erro_de(format($$select t_como(%L, %L)$$, 'b4700000-0000-0000-0000-00000000000b',
    format('select public.nova_venda_no_crediario(%L, %L, %L, null, 0, 240, %L, 2, %L)',
      '54700000-0000-0000-0000-00000000000a', 'c4710000-0000-0000-0000-00000000000a',
      '[{"tipo":"produto","id":"54740000-0000-0000-0000-0000000000a1","qtd":2}]', 'pix', :'primeiro')))
  like 'A entrada cobre a venda inteira%');
select t_texto('   e nada fica pela metade (nenhuma comanda aberta sobrando)',
  (select count(*)::text from public.comandas where salao_id = '54700000-0000-0000-0000-00000000000a'
      and status = 'aberta' and id <> '54720000-0000-0000-0000-00000000000c'
      and id <> '54720000-0000-0000-0000-00000000000b'), '0');

\echo ''
\echo '8. Quem atende não vê'
select t_verdade('a Ju não abre a tela do crediário',
  recusado(format($$select t_como(%L, %L)$$, 'd4700000-0000-0000-0000-00000000000d',
    format('select public.crediario_painel(%L)', '54700000-0000-0000-0000-00000000000a'))));
select t_texto('nem lê as parcelas',
  t_como('d4700000-0000-0000-0000-00000000000d',
    'select to_jsonb(count(*)) from public.crediario_parcelas')::text, '0');
