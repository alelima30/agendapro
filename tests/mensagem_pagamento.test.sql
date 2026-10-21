-- ===========================================================================
-- AgendaPro — a forma de pagamento nas mensagens (21_notificacoes.sql)
--
-- "Temos que colocar o pagamento — Pix, cartão de crédito — nos modelos, para
-- o profissional e a cliente." O que se confere:
--   1. desligado (o padrão), tudo sai como sempre: o modelo de hoje e o mesmo
--      número de variáveis — o modelo cadastrado na Meta não quebra;
--   2. só a plataforma liga;
--   3. ligado, a confirmação, o lembrete, o aviso à profissional e o lembrete
--      para o salão vão pelo `*_pagamento`, com a forma como ÚLTIMA variável
--      e a linha "💳 Pagamento" no texto do histórico;
--   4. ligar refaz o que já estava na fila, e desligar volta;
--   5. o que vai escrito: Pix, Cartão de crédito, Pacote (já pago), A combinar;
--   6. a recepção trocar a forma depois de marcado reescreve o que não saiu.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
  ('6e000000-0000-0000-0000-0000000000ad', 'plataforma@exemplo.com', '{"nome":"Plataforma","telefone":"+5511900001111"}'),
  ('6e000000-0000-0000-0000-0000000000d0', 'dona@exemplo.com', '{"nome":"Dona Lia","telefone":"+5511900002222"}');
update public.perfis set super_admin = true where id = '6e000000-0000-0000-0000-0000000000ad';

insert into public.saloes (id, slug, nome, tipo, status, cfg) values
  ('6e100000-0000-0000-0000-000000000001', 'studio-lia', 'Studio Lia', 'salao', 'ativo',
   '{"notifLembreteEquipe": true, "notifLembreteEquipeMin": 60}');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('6e100000-0000-0000-0000-000000000001', 'time', 'ativa', current_date + 30);
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('6e000000-0000-0000-0000-0000000000d0', '6e100000-0000-0000-0000-000000000001', 'dono', 'ativo');
insert into public.profissionais (id, salao_id, nome, telefone, ativo) values
  ('6e200000-0000-0000-0000-000000000001', '6e100000-0000-0000-0000-000000000001', 'Bia Souza', '11988887777', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '6e200000-0000-0000-0000-000000000001', d, '07:00', '22:00' from generate_series(0, 6) d;
insert into public.servicos (id, salao_id, nome, duracao_min, preco) values
  ('6e300000-0000-0000-0000-000000000001', '6e100000-0000-0000-0000-000000000001', 'Corte', 30, 60);
insert into public.clientes (id, salao_id, nome, telefone) values
  ('6e400000-0000-0000-0000-000000000001', '6e100000-0000-0000-0000-000000000001', 'Maria Lima', '11977776666');

-- Um horário daqui a uns dias, dentro da jornada, no fuso do salão.
create or replace function marcar(p_id uuid, p_dia int, p_forma text) returns void
language plpgsql as $f$
declare v_ini timestamptz := (date_trunc('day', now() at time zone 'America/Sao_Paulo')
                              + make_interval(days => p_dia, hours => 10)) at time zone 'America/Sao_Paulo';
begin
  insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status,
                                   valor_previsto, forma_pagamento)
  values (p_id, '6e100000-0000-0000-0000-000000000001', '6e400000-0000-0000-0000-000000000001',
          '6e200000-0000-0000-0000-000000000001', v_ini, v_ini + interval '30 minutes',
          'confirmado', 60, p_forma);
  insert into public.agendamento_servicos (agendamento_id, servico_id, duracao_min, preco)
  values (p_id, '6e300000-0000-0000-0000-000000000001', 30, 60);
end $f$;

create or replace function linha(p_ag uuid, p_tipo text) returns public.notificacoes
language sql as $f$
  select * from public.notificacoes where agendamento_id = p_ag and tipo = p_tipo
   and status = 'pendente' order by criado_em desc limit 1
$f$;

\echo ''
\echo 'Desligado, que é como nasce'
select marcar('6e500000-0000-0000-0000-000000000001', 3, 'pix');
select t_verdade('1. a confirmação vai pelo modelo de hoje, com as 6 variáveis de hoje',
  (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).modelo = 'agendapro_confirmacao'
  and jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).variaveis) = 6);
select t_verdade('   o aviso à profissional também (6)',
  (linha('6e500000-0000-0000-0000-000000000001', 'novo')).modelo = 'agendapro_aviso_profissional'
  and jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'novo')).variaveis) = 6);
select t_verdade('   e o lembrete para o salão (7)',
  (linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).modelo = 'agendapro_lembrete_equipe'
  and jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).variaveis) = 7);
select t_verdade('   e o texto do histórico não fala de pagamento (não foi o que saiu)',
  (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).corpo not like '%Pagamento%');

\echo ''
\echo 'Quem liga'
select set_config('request.jwt.claim.sub', '6e000000-0000-0000-0000-0000000000d0', false);
select t_verdade('2. a dona do salão não liga os modelos da plataforma',
  recusado($$select public.definir_mensagens_com_pagamento(true)$$));
select t_verdade('   nem lê os ajustes', recusado($$select public.ajustes_da_plataforma()$$));
select set_config('request.jwt.claim.sub', '6e000000-0000-0000-0000-0000000000ad', false);
select (public.definir_mensagens_com_pagamento(true)->>'refeitas')::int as refeitas \gset
select t_verdade('   a plataforma liga — ' || :refeitas || ' mensagem(ns) da fila refeitas',
  (public.ajustes_da_plataforma()->>'mensagensComPagamento')::boolean and :refeitas >= 4);
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo 'Ligado'
select t_verdade('3. a confirmação que já estava na fila passa ao modelo com pagamento',
  (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).modelo = 'agendapro_confirmacao_pagamento');
select t_verdade('   com 7 variáveis, e a última é "Pix"',
  jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).variaveis) = 7
  and (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).variaveis->>6 = 'Pix');
select t_verdade('   e o histórico diz "💳 Pagamento: Pix"',
  (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).corpo like '%💳 Pagamento: Pix%');
select t_verdade('   o lembrete da cliente também (7, Pix)',
  (linha('6e500000-0000-0000-0000-000000000001', 'lembrete')).modelo = 'agendapro_lembrete_pagamento'
  and (linha('6e500000-0000-0000-0000-000000000001', 'lembrete')).variaveis->>6 = 'Pix');
select t_verdade('   o aviso à profissional também (7, Pix)',
  (linha('6e500000-0000-0000-0000-000000000001', 'novo')).modelo = 'agendapro_aviso_profissional_pagamento'
  and jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'novo')).variaveis) = 7
  and (linha('6e500000-0000-0000-0000-000000000001', 'novo')).variaveis->>6 = 'Pix'
  and (linha('6e500000-0000-0000-0000-000000000001', 'novo')).corpo like '%💳 Pagamento: Pix%');
select t_verdade('   e o lembrete para o salão (8, Pix)',
  (linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).modelo = 'agendapro_lembrete_equipe_pagamento'
  and jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).variaveis) = 8
  and (linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).variaveis->>7 = 'Pix'
  and (linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).corpo like '%💳 Pagamento: Pix%');
select t_verdade('   o resumo do dia não muda (não é de um agendamento só)',
  public.modelo_de('resumo') = 'agendapro_agenda_hoje');

\echo ''
\echo 'O que vai escrito'
select marcar('6e500000-0000-0000-0000-000000000002', 4, null);
select t_verdade('5. sem forma informada: "A combinar no salão"',
  (linha('6e500000-0000-0000-0000-000000000002', 'confirmacao')).variaveis->>6 = 'A combinar no salão');
update public.agendamentos set forma_pagamento = 'credito' where id = '6e500000-0000-0000-0000-000000000002';
select t_verdade('6. a recepção anota "cartão de crédito" depois: o que não saiu passa a dizer isso',
  (linha('6e500000-0000-0000-0000-000000000002', 'lembrete')).variaveis->>6 = 'Cartão de crédito'
  and (linha('6e500000-0000-0000-0000-000000000002', 'novo')).variaveis->>6 = 'Cartão de crédito'
  and (linha('6e500000-0000-0000-0000-000000000002', 'lembrete_equipe')).variaveis->>7 = 'Cartão de crédito');

insert into public.pacotes (id, salao_id, nome, sessoes, validade_dias, preco)
  values ('6e600000-0000-0000-0000-000000000001', '6e100000-0000-0000-0000-000000000001', 'Corte do mês', 4, 60, 200);
insert into public.pacote_clientes (id, pacote_id, cliente_id, sessoes, vence_em)
  values ('6e700000-0000-0000-0000-000000000001', '6e600000-0000-0000-0000-000000000001',
          '6e400000-0000-0000-0000-000000000001', 4, current_date + 60);
update public.agendamentos set pacote_cliente_id = '6e700000-0000-0000-0000-000000000001'
 where id = '6e500000-0000-0000-0000-000000000002';
select t_verdade('   atendimento pelo pacote: "Pacote (já pago)"',
  public.pecas_agendamento('6e500000-0000-0000-0000-000000000002')->>'pagamento' = 'Pacote (já pago)');

\echo ''
\echo 'Desligar volta'
select set_config('request.jwt.claim.sub', '6e000000-0000-0000-0000-0000000000ad', false);
select public.definir_mensagens_com_pagamento(false);
select set_config('request.jwt.claim.sub', '', false);
select t_verdade('4. desligado de novo, o que está na fila volta ao modelo de antes, com 6',
  (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).modelo = 'agendapro_confirmacao'
  and jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).variaveis) = 6
  and (linha('6e500000-0000-0000-0000-000000000001', 'confirmacao')).corpo not like '%Pagamento%');
select t_verdade('   e o lembrete para o salão volta a 7',
  jsonb_array_length((linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).variaveis) = 7
  and (linha('6e500000-0000-0000-0000-000000000001', 'lembrete_equipe')).modelo = 'agendapro_lembrete_equipe');
