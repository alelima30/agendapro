-- ===========================================================================
-- AgendaPro — as mensagens do Crediário e a de horário remarcado (52)
--
-- A Maria leva uma lingerie de R$ 300 em 3x de R$ 100, a primeira daqui a
-- dez dias.
--
--   1. com a plataforma desligada (modelos esperando a Meta), nada na fila;
--   2. ligou: as vendas em aberto ganham os avisos das parcelas — e o resumo
--      de compra antiga, não;
--   3. venda nova: o resumo sai agora; cada parcela tem lembrete (2 dias
--      antes), vence hoje e atraso (1 dia depois), às 10h do salão;
--   4. pagou parte: o texto diz o que falta; pagou tudo: sai da fila;
--      desfez o recebimento: volta;
--   5. as chaves do dono, uma por uma;
--   6. desfez a venda: tudo sai;
--   7. a franquia própria: 200 por mês, fora da do plano; módulo inativo,
--      nada sai;
--   8. a aba Mensagens: o balcão lê, quem atende não;
--   9. a plataforma desliga: o que estava na fila sai;
--  10. o horário remarcado: o de antes e o novo; remarcou de novo, só a
--      última; a chave do dono; sem a plataforma, nada.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5200000-0000-0000-0000-00000000000a'),  -- Ana  — dona
  ('b5200000-0000-0000-0000-00000000000b'),  -- Rita — recepção
  ('d5200000-0000-0000-0000-00000000000d'),  -- Ju   — profissional
  ('e5200000-0000-0000-0000-0000000000ad');  -- a plataforma
insert into public.perfis (id, nome, telefone) values
  ('a5200000-0000-0000-0000-00000000000a', 'Ana',  '+5511952000001'),
  ('b5200000-0000-0000-0000-00000000000b', 'Rita', '+5511952000002'),
  ('d5200000-0000-0000-0000-00000000000d', 'Ju',   '+5511952000004'),
  ('e5200000-0000-0000-0000-0000000000ad', 'Plataforma', '+5511952000009')
on conflict (id) do update set nome = excluded.nome;
update public.perfis set super_admin = true where id = 'e5200000-0000-0000-0000-0000000000ad';
insert into public.saloes (id, slug, nome, tipo, fuso, cfg) values
  ('55200000-0000-0000-0000-00000000000a', 'mensagens-novas', 'Lingerie da Ana', 'salao', 'America/Sao_Paulo',
   '{"pagamentos":{"formas":["pix","dinheiro"],"pix":"ana@salao.com"}}');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('55200000-0000-0000-0000-00000000000a', 'individual', 'ativa', current_date + 20);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a5200000-0000-0000-0000-00000000000a', '55200000-0000-0000-0000-00000000000a', 'dono', 'ativo'),
  ('b5200000-0000-0000-0000-00000000000b', '55200000-0000-0000-0000-00000000000a', 'recepcao', 'ativo'),
  ('d5200000-0000-0000-0000-00000000000d', '55200000-0000-0000-0000-00000000000a', 'profissional', 'ativo');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct) values
  ('95200000-0000-0000-0000-00000000000d', '55200000-0000-0000-0000-00000000000a',
   'd5200000-0000-0000-0000-00000000000d', 'Ju', 10);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '95200000-0000-0000-0000-00000000000d', d, '08:00', '20:00' from generate_series(0, 6) d;
insert into public.servicos (id, salao_id, nome, duracao_min, preco, comissao_pct) values
  ('55210000-0000-0000-0000-0000000000a1', '55200000-0000-0000-0000-00000000000a', 'Conjunto renda', 30, 300, 10);
insert into public.clientes (id, salao_id, nome, telefone, cpf) values
  ('c5210000-0000-0000-0000-00000000000a', '55200000-0000-0000-0000-00000000000a', 'Maria Souza', '5511952000003', '52998224725');
update public.adicionais set ativo = true where codigo = 'crediario';
insert into public.salao_adicionais (salao_id, adicional, status, ativo_desde)
  values ('55200000-0000-0000-0000-00000000000a', 'crediario', 'ativo', now());
grant usage on schema auth to anon, authenticated;

select (public.hoje_no_salao('55200000-0000-0000-0000-00000000000a') + 10) as primeiro \gset

create or replace function t_como(p_quem uuid, p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_quem::text, true);
  set local role authenticated;
  execute p_sql into r;
  reset role;
  return r;
end $$;
-- Uma venda de R$ 300 em 3x, pela tela do crediário (a recepção vende).
create or replace function t_vender(p_primeiro date) returns uuid language plpgsql as $$
begin
  return (t_como('b5200000-0000-0000-0000-00000000000b', format(
    $q$select public.nova_venda_no_crediario('55200000-0000-0000-0000-00000000000a',
         'c5210000-0000-0000-0000-00000000000a',
         '[{"tipo":"servico","id":"55210000-0000-0000-0000-0000000000a1","qtd":1}]'::jsonb,
         '95200000-0000-0000-0000-00000000000d', 0, 0, null, 3, %L)$q$, p_primeiro))->>'crediario')::uuid;
end $$;
create or replace function t_msg(p_tipo text, p_id uuid) returns public.notificacoes language sql as $$
  select * from public.notificacoes where chave = p_tipo || ':' || p_id
$$;
create or replace function t_parcela(p_cr uuid, p_n int) returns uuid language sql as $$
  select id from public.crediario_parcelas where crediario_id = p_cr and numero = p_n
$$;
create or replace function t_hora(p_q timestamptz) returns text language sql as $$
  select to_char(p_q at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI')
$$;
create or replace function t_plataforma(p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', 'e5200000-0000-0000-0000-0000000000ad', true);
  execute p_sql into r;
  return r;
end $$;

\echo ''
\echo '1. Plataforma desligada: nada na fila'
select t_vender(:'primeiro') as cr1 \gset
select t_igual('vendeu, com os modelos ainda na Meta: nenhuma mensagem do crediário',
  (select count(*) from public.notificacoes where tipo like 'crediario%'), 0);
select t_verdade('a dona não liga o interruptor da plataforma',
  recusado($$select t_como('a5200000-0000-0000-0000-00000000000a', 'select public.definir_mensagens_do_crediario(true)')$$));

\echo ''
\echo '2. Ligou: as parcelas em aberto ganham os avisos; resumo de compra antiga, não'
update public.crediarios set criado_em = now() - interval '2 hours' where id = :'cr1';
select t_plataforma('select public.definir_mensagens_do_crediario(true)') as ligou \gset
select t_verdade('a plataforma liga, e a venda em aberto é conferida',
  (:'ligou'::jsonb->>'vendas')::int >= 1 and public.mensagens_do_crediario());
select t_igual('   resumo da compra de duas horas atrás: não nasce',
  (select count(*) from public.notificacoes where chave = 'crediario_compra:' || :'cr1'), 0);
select t_texto('   o lembrete da 1ª parcela, sim: dois dias antes, às 10h',
  t_hora((t_msg('crediario_lembrete', t_parcela(:'cr1', 1))).quando),
  to_char(:'primeiro'::date - 2, 'YYYY-MM-DD') || ' 10:00');

\echo ''
\echo '3. Venda nova: o resumo agora, e os três avisos de cada parcela'
select t_vender(:'primeiro') as cr \gset
select t_texto('o resumo da compra sai agora, pelo modelo dele',
  (t_msg('crediario_compra', :'cr')).modelo || ' | ' || (t_msg('crediario_compra', :'cr')).status
    || ' | ' || ((t_msg('crediario_compra', :'cr')).quando <= now())::text,
  'agendapro_crediario_compra | pendente | true');
select t_texto('   com o nome, o salão, o valor e as parcelas numa linha',
  (t_msg('crediario_compra', :'cr')).variaveis::text,
  '["Maria", "Lingerie da Ana", "R$ 300,00", "1ª R$ 100,00 em ' || to_char(:'primeiro'::date, 'DD/MM')
    || '; 2ª R$ 100,00 em ' || to_char((:'primeiro'::date + interval '1 month')::date, 'DD/MM')
    || '; 3ª R$ 100,00 em ' || to_char((:'primeiro'::date + interval '2 months')::date, 'DD/MM') || '"]');
select t_verdade('   para o WhatsApp da Maria',
  (t_msg('crediario_compra', :'cr')).destino = '5511952000003');
select t_igual('cada parcela com os três: 9 avisos',
  (select count(*) from public.notificacoes n join public.crediario_parcelas p
     on n.chave in ('crediario_lembrete:' || p.id, 'crediario_vence_hoje:' || p.id, 'crediario_atraso:' || p.id)
    where p.crediario_id = :'cr' and n.status = 'pendente'), 9);
select t_texto('lembrete: dois dias antes, 10h; com a parcela, o valor, o vencimento e o Pix',
  t_hora((t_msg('crediario_lembrete', t_parcela(:'cr', 2))).quando) || ' | '
    || (t_msg('crediario_lembrete', t_parcela(:'cr', 2))).variaveis::text,
  to_char((:'primeiro'::date + interval '1 month')::date - 2, 'YYYY-MM-DD') || ' 10:00 | '
    || '["Maria", "2 de 3", "Lingerie da Ana", "R$ 100,00", "'
    || to_char((:'primeiro'::date + interval '1 month')::date, 'DD/MM') || '", "Pix (chave: ana@salao.com)"]');
select t_texto('vence hoje: no dia, 10h',
  t_hora((t_msg('crediario_vence_hoje', t_parcela(:'cr', 1))).quando) || ' | '
    || (t_msg('crediario_vence_hoje', t_parcela(:'cr', 1))).modelo,
  to_char(:'primeiro'::date, 'YYYY-MM-DD') || ' 10:00 | agendapro_crediario_vence_hoje');
select t_texto('atraso: um dia depois, 10h, com a data em que venceu',
  t_hora((t_msg('crediario_atraso', t_parcela(:'cr', 1))).quando) || ' | '
    || ((t_msg('crediario_atraso', t_parcela(:'cr', 1))).variaveis->>3),
  to_char(:'primeiro'::date + 1, 'YYYY-MM-DD') || ' 10:00 | ' || to_char(:'primeiro'::date, 'DD/MM'));
select t_verdade('   e o texto do histórico, sem ameaça: "ainda aparece em aberto"',
  (t_msg('crediario_atraso', t_parcela(:'cr', 1))).corpo like
    'Olá, Maria. A parcela 1 de 3 do seu crediário em Lingerie da Ana venceu em %ainda aparece em aberto.%Valor: R$ 100,00%Em caso de dúvida, fale com o salão.%');

\echo ''
\echo '4. Pagou parte, pagou tudo, desfez'
select t_como('b5200000-0000-0000-0000-00000000000b',
  format('select public.receber_parcela(%L, 40, %L)', t_parcela(:'cr', 1), 'pix')) as rec1 \gset
select t_texto('pagou R$ 40: o lembrete passa a dizer os R$ 60 que faltam',
  (t_msg('crediario_lembrete', t_parcela(:'cr', 1))).variaveis->>3, 'R$ 60,00');
select t_verdade('   no corpo também', (t_msg('crediario_vence_hoje', t_parcela(:'cr', 1))).corpo like '%Valor: R$ 60,00%');
select t_como('b5200000-0000-0000-0000-00000000000b',
  format('select public.receber_parcela(%L, 60, %L)', t_parcela(:'cr', 1), 'dinheiro')) as rec2 \gset
select t_texto('quitou a 1ª: os três avisos dela saem da fila',
  (select string_agg(distinct n.status || ' ' || n.motivo, ',') from public.notificacoes n
    where n.chave in ('crediario_lembrete:' || t_parcela(:'cr', 1), 'crediario_vence_hoje:' || t_parcela(:'cr', 1),
                      'crediario_atraso:' || t_parcela(:'cr', 1))), 'cancelado parcela paga');
select t_texto('   os da 2ª continuam', (t_msg('crediario_atraso', t_parcela(:'cr', 2))).status, 'pendente');
select t_como('a5200000-0000-0000-0000-00000000000a',
  format('select public.desfazer_recebimento_crediario(%L)', :'rec2'::jsonb->>'recebimento'));
select t_texto('desfez o recebimento: voltam, com os R$ 60 que faltam',
  (t_msg('crediario_atraso', t_parcela(:'cr', 1))).status || ' | '
    || ((t_msg('crediario_atraso', t_parcela(:'cr', 1))).variaveis->>4), 'pendente | R$ 60,00');
select t_igual('   a mesma linha (nenhuma mensagem dobrada)',
  (select count(*) from public.notificacoes where chave = 'crediario_atraso:' || t_parcela(:'cr', 1)), 1);

\echo ''
\echo '5. As chaves do dono, uma por uma'
update public.saloes set cfg = cfg || '{"notifCredAtraso": false}' where id = '55200000-0000-0000-0000-00000000000a';
select t_texto('desligou o aviso de atraso: os de atraso saem, com o motivo',
  (select string_agg(distinct n.status || ' ' || n.motivo, ',') from public.notificacoes n
    join public.crediario_parcelas p on n.chave = 'crediario_atraso:' || p.id where p.crediario_id = :'cr'),
  'cancelado desligado pelo salão');
select t_texto('   o lembrete e o vence hoje ficam',
  (t_msg('crediario_lembrete', t_parcela(:'cr', 2))).status || ' ' || (t_msg('crediario_vence_hoje', t_parcela(:'cr', 2))).status,
  'pendente pendente');
update public.saloes set cfg = cfg || '{"notifCredAtraso": true, "notifCredLembrete": false}' where id = '55200000-0000-0000-0000-00000000000a';
select t_texto('religou o atraso e desligou o lembrete: troca',
  (t_msg('crediario_atraso', t_parcela(:'cr', 2))).status || ' ' || (t_msg('crediario_lembrete', t_parcela(:'cr', 2))).status,
  'pendente cancelado');
update public.saloes set cfg = cfg || '{"notifCredLembrete": true}' where id = '55200000-0000-0000-0000-00000000000a';
select t_verdade('desligou o resumo da compra: a venda seguinte não tem resumo, mas tem os avisos',
  true);
update public.saloes set cfg = cfg || '{"notifCredCompra": false}' where id = '55200000-0000-0000-0000-00000000000a';
select t_vender(:'primeiro'::date + 1) as cr2 \gset
select t_texto('   (sem resumo; com o lembrete da 1ª)',
  coalesce((t_msg('crediario_compra', :'cr2')).status, 'nenhum') || ' | ' || (t_msg('crediario_lembrete', t_parcela(:'cr2', 1))).status,
  'nenhum | pendente');
update public.saloes set cfg = cfg || '{"notifCredCompra": true}' where id = '55200000-0000-0000-0000-00000000000a';

\echo ''
\echo '6. Desfez a venda: tudo sai'
select t_como('b5200000-0000-0000-0000-00000000000b', format('select public.desfazer_crediario(%L)', :'cr2'));
select t_igual('nenhum aviso da venda desfeita fica pendente',
  (select count(*) from public.notificacoes n join public.crediario_parcelas p
     on n.chave like 'crediario_%:' || p.id where p.crediario_id = :'cr2' and n.status = 'pendente'), 0);
select t_texto('   com o motivo', (t_msg('crediario_lembrete', t_parcela(:'cr2', 1))).motivo, 'venda desfeita');

\echo ''
\echo '7. A franquia própria'
-- Saem cinco da agenda e três do crediário (o worker marcaria assim).
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
  select '55200000-0000-0000-0000-00000000000a', 'confirmacao', '5511952000003', now(), 'x',
         't-conf-' || g, 'enviado', now() from generate_series(1, 5) g;
update public.notificacoes set status = 'enviado', enviado_em = now()
 where chave in ('crediario_compra:' || :'cr', 'crediario_lembrete:' || t_parcela(:'cr', 3),
                 'crediario_vence_hoje:' || t_parcela(:'cr', 3));
select t_texto('as do crediário não gastam a franquia do plano, e contam na delas',
  public.mensagens_no_mes('55200000-0000-0000-0000-00000000000a') || ' | '
    || public.crediario_mensagens_no_mes('55200000-0000-0000-0000-00000000000a'), '5 | 3');
select t_verdade('dentro das 200: podem sair', public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'crediario_atraso'));
-- O plano no teto (franquia de mensagens zerada): a agenda para, o crediário não.
update public.planos set recursos = recursos || '{"mensagens_mes": 5}' where codigo = 'individual';
select t_texto('o plano no teto: a confirmação para, o crediário segue',
  public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'confirmacao')::text || ' | '
    || public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'crediario_lembrete')::text, 'false | true');
-- Chegou a 200 no crediário: espera o mês que vem.
insert into public.notificacoes (salao_id, tipo, destino, quando, corpo, chave, status, enviado_em)
  select '55200000-0000-0000-0000-00000000000a', 'crediario_lembrete', '5511952000003', now(), 'x',
         't-cred-' || g, 'enviado', now() from generate_series(1, 197) g;
select t_falso('200 do crediário no mês (o plano de entrada): a próxima espera',
  public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'crediario_lembrete'));
-- A loja maior: um plano do Crediário com 500 (o número vem do catálogo).
insert into public.adicionais (codigo, nome, preco_mes, recurso, planos, recursos, ativo, ordem)
  values ('crediario_teste500', 'Crediário 500', 79.90, 'crediario',
          array['individual', 'duo', 'time', 'equipe', 'salao'], '{"mensagens_crediario": 500}', true, 2);
update public.salao_adicionais set adicional = 'crediario_teste500'
 where salao_id = '55200000-0000-0000-0000-00000000000a' and adicional = 'crediario';
select t_texto('com o plano de 500, o limite é 500 e ela ainda pode mandar',
  public.crediario_teto_mensagens('55200000-0000-0000-0000-00000000000a')::text || ' | '
    || public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'crediario_lembrete')::text, '500 | true');
update public.salao_adicionais set adicional = 'crediario'
 where salao_id = '55200000-0000-0000-0000-00000000000a' and adicional = 'crediario_teste500';
delete from public.adicionais where codigo = 'crediario_teste500';
select t_igual('   de volta ao de entrada: 200', public.crediario_teto_mensagens('55200000-0000-0000-0000-00000000000a'), 200);
delete from public.notificacoes where chave like 't-cred-%' or chave like 't-conf-%';
select t_verdade('   (abaixo das 200 de novo, sai)', public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'crediario_lembrete'));
update public.salao_adicionais set status = 'cancelado', vale_ate = current_date - 1
 where salao_id = '55200000-0000-0000-0000-00000000000a' and adicional = 'crediario';
select t_falso('módulo Crediário cancelado: nada do crediário sai',
  public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'crediario_lembrete'));
update public.salao_adicionais set status = 'ativo', vale_ate = null
 where salao_id = '55200000-0000-0000-0000-00000000000a' and adicional = 'crediario';

\echo ''
\echo '8. A aba Mensagens do Crediário'
select t_como('b5200000-0000-0000-0000-00000000000b',
  $$select public.crediario_mensagens('55200000-0000-0000-0000-00000000000a')$$) as aba \gset
select t_texto('o balcão lê: liberadas, quanto usou, o teto e as quatro chaves',
  (:'aba'::jsonb->>'liberadas') || ' | ' || (:'aba'::jsonb->>'usadas') || ' de ' || (:'aba'::jsonb->>'teto')
    || ' | ' || (:'aba'::jsonb->>'compra') || ' ' || (:'aba'::jsonb->>'lembrete') || ' '
    || (:'aba'::jsonb->>'venceHoje') || ' ' || (:'aba'::jsonb->>'atraso'),
  'true | 3 de 200 | true true true true');
select t_verdade('quem atende não lê',
  recusado($$select t_como('d5200000-0000-0000-0000-00000000000d', 'select public.crediario_mensagens(''55200000-0000-0000-0000-00000000000a'')')$$));
select t_verdade('o anon nem chama; as peças de dentro não abrem para ninguém',
  not has_function_privilege('anon', 'public.crediario_mensagens(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.avisos_do_crediario(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.avisar_remarcado(uuid,timestamptz,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.crediario_mensagens_no_mes(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.crediario_teto_mensagens(uuid)', 'execute'));

\echo ''
\echo '9. A plataforma desliga'
select t_plataforma('select public.definir_mensagens_do_crediario(false)');
select t_igual('nada do crediário fica pendente',
  (select count(*) from public.notificacoes where tipo like 'crediario%' and status = 'pendente'), 0);
select t_texto('   com o motivo', (t_msg('crediario_atraso', t_parcela(:'cr', 2))).motivo,
  'mensagens do crediário desligadas');
select t_texto('   e o que já tinha saído não foi tocado', (t_msg('crediario_compra', :'cr')).status, 'enviado');

\echo ''
\echo '10. O horário remarcado'
-- A Maria marcou com a Ju daqui a 5 dias, às 14h.
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
  values ('a5210000-0000-0000-0000-0000000000f1', '55200000-0000-0000-0000-00000000000a',
          'c5210000-0000-0000-0000-00000000000a', '95200000-0000-0000-0000-00000000000d',
          ((current_date + 5) + time '14:00') at time zone 'America/Sao_Paulo',
          ((current_date + 5) + time '14:30') at time zone 'America/Sao_Paulo', 'confirmado', 'recepcao', 300);
insert into public.agendamento_servicos (agendamento_id, servico_id, ordem, preco, duracao_min)
  values ('a5210000-0000-0000-0000-0000000000f1', '55210000-0000-0000-0000-0000000000a1', 1, 300, 30);
create or replace function t_remarcar(p_dia int, p_hora text) returns jsonb language sql as $$
  select t_como('a5200000-0000-0000-0000-00000000000a', format(
    'select public.remarcar_pelo_salao(%L, %L)', 'a5210000-0000-0000-0000-0000000000f1',
    ((current_date + p_dia) + p_hora::time) at time zone 'America/Sao_Paulo'))
$$;
select t_remarcar(6, '15:30') as rm1 \gset
select t_verdade('sem a plataforma ligar o modelo: remarcou, e nada na fila',
  (:'rm1'::jsonb->>'ok')::boolean
  and not exists (select 1 from public.notificacoes where tipo = 'remarcado'));
select t_plataforma('select public.definir_mensagem_remarcado(true)');
select t_remarcar(7, '16:00') as rm2 \gset
select t_verdade('ligado: remarcou de novo, para o dia 7 às 16h', (:'rm2'::jsonb->>'ok')::boolean);
select t_texto('a cliente recebe o de antes e o novo, pelo modelo do remarcado',
  (select n.modelo || ' | ' || n.variaveis::text from public.notificacoes n
    where n.tipo = 'remarcado' and n.status = 'pendente'),
  'agendapro_remarcado | ["Maria", "Lingerie da Ana", "'
    || (array['domingo','segunda','terça','quarta','quinta','sexta','sábado'])[extract(dow from current_date + 6)::int + 1]
    || ', ' || to_char(current_date + 6, 'DD/MM') || ' às 15:30", "' || to_char(current_date + 7, 'DD/MM/YYYY')
    || '", "16:00", "Conjunto renda", "Ju"]');
select t_verdade('   saindo agora, para o número dela, com o texto do histórico',
  (select n.quando <= now() and n.destino = '5511952000003'
          and n.corpo like 'Olá, Maria. Seu horário no Lingerie da Ana foi remarcado.%Antes: %Nova data: %Novo horário: 16:00%Se o novo horário não for bom para você, fale com o salão.%'
     from public.notificacoes n where n.tipo = 'remarcado' and n.status = 'pendente'));
select t_remarcar(8, '09:00') as rm3 \gset
select t_verdade('remarcou de novo antes de sair: só a última fica',
  (:'rm3'::jsonb->>'ok')::boolean
  and (select count(*) from public.notificacoes where tipo = 'remarcado' and status = 'pendente') = 1
  and (select count(*) from public.notificacoes where tipo = 'remarcado' and motivo = 'remarcado de novo') = 1);
update public.saloes set cfg = cfg || '{"notifRemarcado": false}' where id = '55200000-0000-0000-0000-00000000000a';
select t_remarcar(9, '09:00') as rm4 \gset
select t_verdade('o dono desligou a chave: remarcou, e nenhuma nova',
  (:'rm4'::jsonb->>'ok')::boolean
  and (select count(*) from public.notificacoes where tipo = 'remarcado') = 2);
update public.saloes set cfg = cfg || '{"notifRemarcado": true}' where id = '55200000-0000-0000-0000-00000000000a';
select t_verdade('o remarcado vai para a cliente: conta como a confirmação, até o teto do plano',
  public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'remarcado')
    = public.pode_enviar_tipo('55200000-0000-0000-0000-00000000000a', 'confirmacao'));
select t_plataforma('select public.definir_mensagem_remarcado(false)');
select t_texto('a plataforma desliga: o que estava na fila sai',
  (select string_agg(distinct status || ' ' || motivo, ',') from public.notificacoes
    where tipo = 'remarcado' and motivo <> 'remarcado de novo'), 'cancelado mensagem de remarcado desligada');
select t_texto('o admin lê os dois interruptores',
  t_plataforma('select public.ajustes_da_plataforma()')->>'mensagensCrediario' || ' '
    || (t_plataforma('select public.ajustes_da_plataforma()')->>'mensagemRemarcado'), 'false false');
update public.planos set recursos = recursos - 'mensagens_mes' where codigo = 'individual';
select set_config('request.jwt.claim.sub', '', false);
