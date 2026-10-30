-- ===========================================================================
-- AgendaPro — os módulos adicionais (46_adicionais.sql)
--
-- O Crediário: R$ 49,90 por mês, do Essencial para cima, liberado no teste.
--
--   1. o catálogo; o Essencial sem o módulo recusa, e diz onde contratar;
--   2. a profissional não contrata; o dono contrata e LIBERA NA HORA, e a
--      mensalidade passa de R$ 97 para R$ 146,90 (o Pix velho sai do caminho);
--   3. o Pix nasce com os dois itens; pago, o módulo continua;
--   4. cancelar vale até o vencimento; depois, para;
--   5. recontratar depois de vencido só libera com a mensalidade paga;
--   6. inadimplente não contrata; no Básico fica aguardando e entra junto
--      com o Essencial; descer para o Básico para o módulo;
--   7. no teste vem liberado;
--   8. o cartão: a conta leva o id da pré-aprovação (só para a borda); o mês
--      do cartão aceita as composições conhecidas e recusa o resto;
--   9. a plataforma dá cortesia e preço especial; ninguém mais;
--  10. a conta que mudou no meio é recusada; quem chama o quê.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('a4600000-0000-0000-0000-00000000000a', 'ana@adicional.com'),    -- dona do Essencial
  ('a4600000-0000-0000-0000-00000000000b', 'bia@adicional.com'),    -- dona do Básico
  ('a4600000-0000-0000-0000-00000000000c', 'cris@adicional.com'),   -- dona no teste
  ('a4600000-0000-0000-0000-00000000000d', 'dani@adicional.com'),   -- dona inadimplente
  ('a4600000-0000-0000-0000-00000000000e', 'edu@adicional.com'),    -- dono no cartão
  ('d4600000-0000-0000-0000-00000000000d', 'ju@adicional.com'),     -- profissional da Ana
  ('e4600000-0000-0000-0000-0000000000ad', 'plataforma@adicional.com');
insert into public.perfis (id, nome, telefone) values
  ('a4600000-0000-0000-0000-00000000000a', 'Ana',  '+5511946000001'),
  ('a4600000-0000-0000-0000-00000000000b', 'Bia',  '+5511946000002'),
  ('a4600000-0000-0000-0000-00000000000c', 'Cris', '+5511946000003'),
  ('a4600000-0000-0000-0000-00000000000d', 'Dani', '+5511946000004'),
  ('a4600000-0000-0000-0000-00000000000e', 'Edu',  '+5511946000005'),
  ('d4600000-0000-0000-0000-00000000000d', 'Ju',   '+5511946000006'),
  ('e4600000-0000-0000-0000-0000000000ad', 'Plataforma', '+5511946000009')
on conflict (id) do update set nome = excluded.nome;
update public.perfis set super_admin = true where id = 'e4600000-0000-0000-0000-0000000000ad';

insert into public.saloes (id, slug, nome, tipo, fuso) values
  ('54600000-0000-0000-0000-00000000000a', 'adic-ana',  'Lingerie da Ana', 'salao', 'America/Sao_Paulo'),
  ('54600000-0000-0000-0000-00000000000b', 'adic-bia',  'Salão da Bia',    'salao', 'America/Sao_Paulo'),
  ('54600000-0000-0000-0000-00000000000c', 'adic-cris', 'Salão da Cris',   'salao', 'America/Sao_Paulo'),
  ('54600000-0000-0000-0000-00000000000d', 'adic-dani', 'Salão da Dani',   'salao', 'America/Sao_Paulo'),
  ('54600000-0000-0000-0000-00000000000e', 'adic-edu',  'Salão do Edu',    'salao', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status, vence_em, trial_ate) values
  ('54600000-0000-0000-0000-00000000000a', 'individual', 'ativa', current_date + 20, null),
  ('54600000-0000-0000-0000-00000000000b', 'basico',     'ativa', current_date + 20, null),
  ('54600000-0000-0000-0000-00000000000c', 'trial',      'trial', null, current_date + 5),
  ('54600000-0000-0000-0000-00000000000d', 'individual', 'inadimplente', current_date - 3, null),
  ('54600000-0000-0000-0000-00000000000e', 'individual', 'ativa', current_date + 20, null);
update public.assinaturas set mp_preapproval = 'pre-edu', cartao_desde = now()
 where salao_id = '54600000-0000-0000-0000-00000000000e';
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a4600000-0000-0000-0000-00000000000a', '54600000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('d4600000-0000-0000-0000-00000000000d', '54600000-0000-0000-0000-00000000000a', 'profissional', 'ativo'),
  ('a4600000-0000-0000-0000-00000000000b', '54600000-0000-0000-0000-00000000000b', 'dono', 'ativo'),
  ('a4600000-0000-0000-0000-00000000000c', '54600000-0000-0000-0000-00000000000c', 'dono', 'ativo'),
  ('a4600000-0000-0000-0000-00000000000d', '54600000-0000-0000-0000-00000000000d', 'dono', 'ativo'),
  ('a4600000-0000-0000-0000-00000000000e', '54600000-0000-0000-0000-00000000000e', 'dono', 'ativo');
grant usage on schema auth to anon, authenticated;

\echo ''
\echo '0. Fora da venda até as telas do Crediário existirem'
select t_falso('o Crediário nasce fora da venda',
  (select ativo from public.adicionais where codigo = 'crediario'));
select t_verdade('e fora da venda ninguém contrata',
  erro_de($$select public.conta_do_adicional('54600000-0000-0000-0000-00000000000a', 'crediario', 'contratar',
    'a4600000-0000-0000-0000-00000000000a')$$) like 'Este módulo não está à venda%');
select set_config('request.jwt.claim.sub', 'a4600000-0000-0000-0000-00000000000a', false);
set role authenticated;
select t_igual('nem aparece em Meu plano',
  jsonb_array_length(public.meus_adicionais('54600000-0000-0000-0000-00000000000a')->'catalogo'), 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);
-- Daqui para baixo, à venda (como ficará quando as telas existirem).
update public.adicionais set ativo = true where codigo = 'crediario';

-- O caminho da borda `adicional`: a conta, e gravar com o valor da conta.
create or replace function t_mudar(p_salao uuid, p_acao text, p_quem uuid, p_preco numeric default null)
returns jsonb language plpgsql as $$
declare c jsonb;
begin
  c := public.preparar_adicional(p_salao, 'crediario', p_acao, p_quem, p_preco);
  return public.aplicar_adicional(p_salao, 'crediario', p_acao, p_quem, p_preco, (c->>'depois')::numeric);
end $$;
-- O Mercado Pago confirmando um Pix.
create or replace function t_pagar(p_cob uuid, p_mp text) returns jsonb language plpgsql as $$
declare v numeric;
begin
  select valor into v from public.cobrancas where id = p_cob;
  perform public.anotar_cobranca(p_cob, p_mp, 'pending');
  return public.registrar_pagamento(p_mp, v, 'approved');
end $$;

\echo ''
\echo '1. O catálogo, e a trava'
select t_texto('o Crediário: R$ 49,90, do Essencial para cima, sem o Básico',
  (select preco_mes || ' | ' || ('individual' = any(planos)) || ' | ' || ('basico' = any(planos))
     from public.adicionais where codigo = 'crediario'), '49.90 | true | false');
select t_falso('o Essencial sem o módulo não vende no crediário',
  public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario'));
select t_verdade('e a recusa diz que é módulo adicional, a partir do Essencial, em Meu plano',
  erro_de($$select public.exigir_recurso('54600000-0000-0000-0000-00000000000a', 'crediario', 'Vender no crediário')$$)
    like 'Vender no crediário faz parte do módulo adicional Crediário, a partir do plano Essencial. Contrate em Meu plano.');
select t_verdade('os módulos de plano continuam dizendo "a partir do Básico"',
  erro_de($$select public.exigir_recurso('54600000-0000-0000-0000-00000000000a', 'nao_existe', 'Isto')$$)
    like 'Isto está disponível a partir do plano Básico.');

\echo ''
\echo '2. Contratar'
select (public.abrir_cobranca('54600000-0000-0000-0000-00000000000a', 'individual', 'pix',
        'a4600000-0000-0000-0000-00000000000a')).id as pix_velho \gset
select t_verdade('a profissional não contrata',
  recusado($$select t_mudar('54600000-0000-0000-0000-00000000000a', 'contratar', 'd4600000-0000-0000-0000-00000000000d')$$));
select set_config('request.jwt.claim.sub', 'a4600000-0000-0000-0000-00000000000a', false);
set role authenticated;
select (public.simular_adicional('54600000-0000-0000-0000-00000000000a', 'crediario', 'contratar')) as sim \gset
reset role;
select t_texto('a tela mostra a conta antes: de R$ 97 para R$ 146,90, liberado na hora',
  (:'sim'::jsonb->>'antes') || ' → ' || (:'sim'::jsonb->>'depois') || ' | ' || (:'sim'::jsonb->>'efeito'),
  '97.00 → 146.90 | liberado');
select t_falso('   sem o id do cartão (esse é só da borda)', :'sim'::jsonb ? 'preapproval');
select t_texto('o dono contrata: liberado agora',
  t_mudar('54600000-0000-0000-0000-00000000000a', 'contratar', 'a4600000-0000-0000-0000-00000000000a')->>'efeito',
  'liberado');
select t_verdade('e o crediário passa a valer', public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario'));
select t_texto('a mensalidade: Essencial + Crediário',
  public.valor_da_mensalidade('54600000-0000-0000-0000-00000000000a', 'individual')::text, '146.90');
select t_texto('o Pix que estava aberto (do valor velho) saiu do caminho',
  (select status from public.cobrancas where id = :'pix_velho'), 'cancelada');
set role authenticated;
select t_texto('a dona vê a mensalidade e o módulo ativo',
  (public.meus_adicionais('54600000-0000-0000-0000-00000000000a')->>'mensalidade')
    || ' | ' || (public.meus_adicionais('54600000-0000-0000-0000-00000000000a')->'catalogo'->0->>'ativo'),
  '146.90 | true');
select set_config('request.jwt.claim.sub', 'd4600000-0000-0000-0000-00000000000d', false);
select t_texto('a profissional só sabe que o módulo vale (sem preço nem mensalidade)',
  public.meus_adicionais('54600000-0000-0000-0000-00000000000a')::text, '{"ativos": ["crediario"], "recursos": ["crediario"]}');
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '3. O Pix do mês'
select (public.abrir_cobranca('54600000-0000-0000-0000-00000000000a', 'individual', 'pix',
        'a4600000-0000-0000-0000-00000000000a')).id as pix1 \gset
select t_texto('o Pix nasce com os dois itens',
  (select valor || ' | ' || (select string_agg(x->>'nome' || ' ' || (x->>'valor'), ' + ')
                               from jsonb_array_elements(itens) x)
     from public.cobrancas where id = :'pix1'), '146.90 | Essencial 97.00 + Crediário 49.90');
select t_pagar(:'pix1', 'mp-ana-1');
select t_texto('pago: um mês a mais, e o módulo continua',
  (select (vence_em - current_date) > 40 from public.assinaturas where salao_id = '54600000-0000-0000-0000-00000000000a')::text
    || ' | ' || public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario'), 'true | true');
select t_texto('o lembrete de renovação diz o valor de verdade',
  (select valor::text from public.assinaturas_a_vencer(400) where salao_id = '54600000-0000-0000-0000-00000000000a'),
  '146.90');

\echo ''
\echo '4. Cancelar'
select t_texto('cancelou: vale até o vencimento (o mês já pago)',
  t_mudar('54600000-0000-0000-0000-00000000000a', 'cancelar', 'a4600000-0000-0000-0000-00000000000a')->>'valeAte',
  (select vence_em::text from public.assinaturas where salao_id = '54600000-0000-0000-0000-00000000000a'));
select t_texto('   continua valendo até lá, e a próxima mensalidade volta a R$ 97',
  public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario')
    || ' | ' || public.valor_da_mensalidade('54600000-0000-0000-0000-00000000000a', 'individual'), 'true | 97.00');
update public.salao_adicionais set vale_ate = current_date - 1
 where salao_id = '54600000-0000-0000-0000-00000000000a';
select t_falso('passou do vencimento: para', public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario'));

\echo ''
\echo '5. Recontratar'
select t_texto('já teve e cancelou: fica aguardando a mensalidade paga',
  t_mudar('54600000-0000-0000-0000-00000000000a', 'contratar', 'a4600000-0000-0000-0000-00000000000a')->>'efeito',
  'aguarda_pagamento');
select t_falso('   e não vale enquanto isso', public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario'));
select (public.abrir_cobranca('54600000-0000-0000-0000-00000000000a', 'individual', 'pix',
        'a4600000-0000-0000-0000-00000000000a')).id as pix2 \gset
select t_texto('o Pix já vem com ele', (select valor::text from public.cobrancas where id = :'pix2'), '146.90');
select t_pagar(:'pix2', 'mp-ana-2');
select t_verdade('pago: liberado', public.recurso_bool('54600000-0000-0000-0000-00000000000a', 'crediario'));

\echo ''
\echo '6. Inadimplente, Básico, descer de plano'
select t_verdade('inadimplente: "regularize a mensalidade primeiro"',
  erro_de($$select t_mudar('54600000-0000-0000-0000-00000000000d', 'contratar', 'a4600000-0000-0000-0000-00000000000d')$$)
    like 'Regularize a mensalidade primeiro%');
select t_texto('no Básico: fica aguardando o Essencial',
  t_mudar('54600000-0000-0000-0000-00000000000b', 'contratar', 'a4600000-0000-0000-0000-00000000000b')->>'efeito',
  'aguarda_plano');
select t_texto('   não vale, e o Pix do Básico não cobra o módulo',
  public.recurso_bool('54600000-0000-0000-0000-00000000000b', 'crediario')
    || ' | ' || public.valor_da_mensalidade('54600000-0000-0000-0000-00000000000b', 'basico'), 'false | 49.90');
select (public.abrir_cobranca('54600000-0000-0000-0000-00000000000b', 'individual', 'pix',
        'a4600000-0000-0000-0000-00000000000b')).id as pix_bia \gset
select t_texto('"Mudar para o Essencial + Crediário": o Pix do Essencial vem com ele',
  (select valor::text from public.cobrancas where id = :'pix_bia'), '146.90');
select t_pagar(:'pix_bia', 'mp-bia-1');
select t_texto('pago: Essencial, com o Crediário valendo',
  (select plano from public.assinaturas where salao_id = '54600000-0000-0000-0000-00000000000b')
    || ' | ' || public.recurso_bool('54600000-0000-0000-0000-00000000000b', 'crediario'), 'individual | true');
select (public.abrir_cobranca('54600000-0000-0000-0000-00000000000b', 'basico', 'pix',
        'a4600000-0000-0000-0000-00000000000b')).id as pix_bia2 \gset
select t_texto('voltar para o Básico: o Pix é só do Básico',
  (select valor::text from public.cobrancas where id = :'pix_bia2'), '49.90');
select t_pagar(:'pix_bia2', 'mp-bia-2');
select t_texto('pago o Básico: o módulo para (as parcelas abertas ficam, mas não vende fiado novo)',
  public.recurso_bool('54600000-0000-0000-0000-00000000000b', 'crediario')
    || ' | ' || (select status from public.salao_adicionais where salao_id = '54600000-0000-0000-0000-00000000000b'),
  'false | cancelado');

\echo ''
\echo '7. No teste grátis'
select t_verdade('vem liberado para experimentar', public.recurso_bool('54600000-0000-0000-0000-00000000000c', 'crediario'));
select t_texto('e dá para pedir junto com a primeira mensalidade',
  t_mudar('54600000-0000-0000-0000-00000000000c', 'contratar', 'a4600000-0000-0000-0000-00000000000c')->>'efeito',
  'aguarda_plano');

\echo ''
\echo '8. No cartão'
select public.preparar_adicional('54600000-0000-0000-0000-00000000000e', 'crediario', 'contratar',
       'a4600000-0000-0000-0000-00000000000e') as conta_edu \gset
select t_texto('a conta da borda leva o id da pré-aprovação e os dois valores',
  (:'conta_edu'::jsonb->>'preapproval') || ' | ' || (:'conta_edu'::jsonb->>'antes') || ' → ' || (:'conta_edu'::jsonb->>'depois'),
  'pre-edu | 97.00 → 146.90');
select t_texto('preparar não grava nada',
  (select count(*) from public.salao_adicionais where salao_id = '54600000-0000-0000-0000-00000000000e')::text, '0');
select t_mudar('54600000-0000-0000-0000-00000000000e', 'contratar', 'a4600000-0000-0000-0000-00000000000e');
select public.registrar_recorrencia('pre-edu', 'mp-edu-1', 146.90, 'approved')->>'ok' as r1 \gset
select t_texto('o mês do cartão com o módulo: registra os dois itens',
  :'r1' || ' | ' || (select jsonb_array_length(itens) from public.cobrancas where mp_id = 'mp-edu-1'), 'true | 2');
select public.registrar_recorrencia('pre-edu', 'mp-edu-2', 97.00, 'approved')->>'ok' as r2 \gset
select t_texto('o mês com o valor de antes (o cartão ainda não tinha mudado): só o plano, sem recusar',
  :'r2' || ' | ' || (select jsonb_array_length(itens) from public.cobrancas where mp_id = 'mp-edu-2'), 'true | 1');
select t_mudar('54600000-0000-0000-0000-00000000000e', 'cancelar', 'a4600000-0000-0000-0000-00000000000e');
select public.registrar_recorrencia('pre-edu', 'mp-edu-3', 146.90, 'approved')->>'ok' as r3 \gset
select t_texto('cancelou, mas o cartão ainda cobrou com ele: pagou, tem',
  :'r3' || ' | ' || (select status from public.salao_adicionais where salao_id = '54600000-0000-0000-0000-00000000000e'),
  'true | ativo');
select t_texto('valor que não bate com nada continua recusado',
  public.registrar_recorrencia('pre-edu', 'mp-edu-4', 120.00, 'approved')->>'motivo', 'valor_divergente');

\echo ''
\echo '9. Cortesia e preço especial'
select t_verdade('o dono não se dá cortesia',
  recusado($$select t_mudar('54600000-0000-0000-0000-00000000000b', 'cortesia', 'a4600000-0000-0000-0000-00000000000b')$$));
select t_mudar('54600000-0000-0000-0000-00000000000b', 'cortesia', 'e4600000-0000-0000-0000-0000000000ad');
select t_texto('a plataforma dá cortesia (até no Básico): vale, e não entra na mensalidade',
  public.recurso_bool('54600000-0000-0000-0000-00000000000b', 'crediario')
    || ' | ' || public.valor_da_mensalidade('54600000-0000-0000-0000-00000000000b', 'basico'), 'true | 49.90');
select t_mudar('54600000-0000-0000-0000-00000000000a', 'preco', 'e4600000-0000-0000-0000-0000000000ad', 29.90);
select t_texto('e preço especial para um salão',
  public.valor_da_mensalidade('54600000-0000-0000-0000-00000000000a', 'individual')::text, '126.90');
select set_config('request.jwt.claim.sub', 'a4600000-0000-0000-0000-00000000000a', false);
set role authenticated;
select t_verdade('a dona não vê os adicionais de todos', recusado('select public.adicionais_da_plataforma()'));
reset role;
select set_config('request.jwt.claim.sub', 'e4600000-0000-0000-0000-0000000000ad', false);
set role authenticated;
select t_texto('a plataforma vê quanto os adicionais rendem por mês (Ana R$ 29,90 + Edu R$ 49,90; a cortesia não conta)',
  public.adicionais_da_plataforma()->>'receitaMes', '79.80');
reset role;
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '10. A conta que mudou no meio, e quem chama o quê'
select t_verdade('gravar com um valor que não é o da conta é recusado',
  erro_de($$select public.aplicar_adicional('54600000-0000-0000-0000-00000000000a', 'crediario', 'cancelar',
    'a4600000-0000-0000-0000-00000000000a', null, 1.00)$$) like 'A mensalidade mudou%');
select set_config('request.jwt.claim.sub', 'a4600000-0000-0000-0000-00000000000a', false);
set role authenticated;
select t_verdade('a dona não chama as metades da borda',
  recusado($$select public.preparar_adicional('54600000-0000-0000-0000-00000000000a', 'crediario', 'contratar',
    'a4600000-0000-0000-0000-00000000000a')$$)
  and recusado($$select public.aplicar_adicional('54600000-0000-0000-0000-00000000000a', 'crediario', 'cortesia',
    'e4600000-0000-0000-0000-0000000000ad')$$));
select t_verdade('nem escreve na tabela',
  recusado($$insert into public.salao_adicionais (salao_id, adicional, status, cortesia)
    values ('54600000-0000-0000-0000-00000000000a', 'crediario', 'ativo', true)$$));
select t_verdade('nem lê a dos outros salões',
  (select count(*) from public.salao_adicionais where salao_id <> '54600000-0000-0000-0000-00000000000a') = 0);
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select t_verdade('quem não entrou não pergunta nada',
  recusado($$select public.meus_adicionais('54600000-0000-0000-0000-00000000000a')$$)
  and recusado($$select public.simular_adicional('54600000-0000-0000-0000-00000000000a', 'crediario', 'contratar')$$));
select t_verdade('nem lê o catálogo', recusado('select count(*) from public.adicionais'));
reset role;
select set_config('request.jwt.claim.sub', 'd4600000-0000-0000-0000-00000000000d', false);
set role authenticated;
select t_verdade('quem está logado lê o catálogo (o preço aparece no painel)',
  (select count(*) from public.adicionais where codigo = 'crediario') = 1);
reset role;
select set_config('request.jwt.claim.sub', '', false);
