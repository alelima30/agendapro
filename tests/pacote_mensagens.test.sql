-- ===========================================================================
-- AgendaPro — as mensagens do pacote (45_pacote_mensagens.sql)
--
-- A Maria vai toda terça às 14h, pacote de R$ 220 "a receber".
--
--   1. com a plataforma desligada (os modelos ainda não aprovados), nada vai
--      para a fila; a dona não liga, a plataforma liga;
--   2. ligado: o aviso da última sessão seis dias antes da última terça, às
--      10h, pelo modelo que não é Marketing; lembrete de pagamento, nenhum
--      ("o pacote só é confirmado com o pagamento");
--   3. a última terça muda de dia: o aviso muda junto (hora e texto);
--   4. a última terça cai e volta: o aviso cai e volta, sem linha nova;
--   5. "Recebi" e desfazer: o aviso fica, e lembrete de pagamento não nasce;
--   6. a chave do salão desliga e religa o aviso;
--   7. a primeira sessão chega perto: nem assim nasce lembrete de pagamento;
--   8. renovou: o aviso do pacote antigo sai; o novo tem a lista de horários
--      com o salão (e não a profissional); cancelar o pacote tira o aviso;
--   9. agenda incompleta não tem "última sessão"; cliente sem telefone, nada;
--  10. a plataforma desliga: tudo o que estava na fila sai; e as peças de
--      dentro não abrem para ninguém.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4500000-0000-0000-0000-00000000000a'),  -- Ana — dona
  ('d4500000-0000-0000-0000-00000000000d'),  -- Ju  — profissional
  ('e4500000-0000-0000-0000-0000000000ad');  -- a plataforma
insert into public.perfis (id, nome, telefone) values
  ('a4500000-0000-0000-0000-00000000000a', 'Ana', '+5511945000001'),
  ('d4500000-0000-0000-0000-00000000000d', 'Ju',  '+5511945000004'),
  ('e4500000-0000-0000-0000-0000000000ad', 'Plataforma', '+5511945000009')
on conflict (id) do update set nome = excluded.nome;
update public.perfis set super_admin = true where id = 'e4500000-0000-0000-0000-0000000000ad';

insert into public.saloes (id, slug, nome, status, fuso, cfg) values
  ('54500000-0000-0000-0000-00000000000a', 'pacote-mensagens', 'Salão Recado', 'ativo',
   'America/Sao_Paulo', '{"pagamentos":{"formas":["pix","dinheiro"],"pix":"pix@recado.com"}}');
insert into public.assinaturas (salao_id, plano, status) values
  ('54500000-0000-0000-0000-00000000000a', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a4500000-0000-0000-0000-00000000000a', '54500000-0000-0000-0000-00000000000a', 'dono'),
  ('d4500000-0000-0000-0000-00000000000d', '54500000-0000-0000-0000-00000000000a', 'profissional');
insert into public.profissionais (id, salao_id, perfil_id, nome, ativo) values
  ('94500000-0000-0000-0000-00000000000d', '54500000-0000-0000-0000-00000000000a',
   'd4500000-0000-0000-0000-00000000000d', 'Ju', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '94500000-0000-0000-0000-00000000000d', d, '08:00', '20:00' from generate_series(0, 6) d;
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco) values
  ('54510000-0000-0000-0000-0000000000a1', '54500000-0000-0000-0000-00000000000a', 'Mão', 45, 0, 40),
  ('54510000-0000-0000-0000-0000000000a2', '54500000-0000-0000-0000-00000000000a', 'Pé',  45, 0, 50);
insert into public.pacotes (id, salao_id, nome, preco, sessoes, validade_dias) values
  ('54520000-0000-0000-0000-0000000000b1', '54500000-0000-0000-0000-00000000000a', 'Mão e pé mensal', 220, 4, 30);
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('54520000-0000-0000-0000-0000000000b1', '54510000-0000-0000-0000-0000000000a1'),
  ('54520000-0000-0000-0000-0000000000b1', '54510000-0000-0000-0000-0000000000a2');
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c4510000-0000-0000-0000-00000000000a', '54500000-0000-0000-0000-00000000000a', 'Maria Souza', '5511945000003'),
  ('c4510000-0000-0000-0000-00000000000b', '54500000-0000-0000-0000-00000000000a', 'Lia Prado',   '5511945000005'),
  ('c4510000-0000-0000-0000-00000000000c', '54500000-0000-0000-0000-00000000000a', 'Rosa Sem Fone', null);

-- A terça da semana que vem (de 7 a 13 dias daqui): a véspera e o aviso
-- caem sempre no futuro, rode o teste quando rodar.
select (current_date + ((2 - extract(dow from current_date)::int + 7) % 7) + 7) as terca \gset
grant usage on schema auth to anon, authenticated;

-- As semanas do pacote, a partir de uma terça: mão / mão e pé / mão / mão e pé.
create or replace function t_semanas(p_terca date, p_n int) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object(
    'inicio', to_char(((p_terca + (n - 1) * 7) + time '14:00') at time zone 'America/Sao_Paulo',
                      'YYYY-MM-DD"T"HH24:MI:SSOF'),
    'servicos', case when n % 2 = 1 then '["54510000-0000-0000-0000-0000000000a1"]'::jsonb
                     else '["54510000-0000-0000-0000-0000000000a1","54510000-0000-0000-0000-0000000000a2"]'::jsonb end)
    order by n) from generate_series(1, p_n) n
$$;
create or replace function t_msg(p_pc uuid, p_tipo text) returns public.notificacoes language sql as $$
  select * from public.notificacoes where chave = p_tipo || ':' || p_pc
$$;
create or replace function t_sessao(p_pc uuid, p_n int) returns uuid language sql as $$
  select id from public.agendamentos where pacote_cliente_id = p_pc order by inicio offset p_n - 1 limit 1
$$;

\echo ''
\echo '1. Desligado na plataforma: nada na fila'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select (public.montar_pacote('54520000-0000-0000-0000-0000000000b1', 'c4510000-0000-0000-0000-00000000000a',
            220, null, '94500000-0000-0000-0000-00000000000d', t_semanas(:'terca', 4))->>'pacoteCliente') as pc \gset
commit;
select t_igual('montado a receber, com os modelos desligados: nenhuma mensagem do pacote',
  (select count(*) from public.notificacoes where tipo in ('pacote_renovar', 'pacote_pagamento')), 0);
select t_verdade('   (e, a receber, as sessões ficam reservadas: nem a confirmação sai ainda)',
  not exists (select 1 from public.notificacoes where agendamento_id = t_sessao(:'pc', 1) and tipo = 'confirmacao')
  and (select status from public.agendamentos where id = t_sessao(:'pc', 1)) = 'pendente');

select set_config('request.jwt.claim.sub', 'a4500000-0000-0000-0000-00000000000a', false);
select t_verdade('a dona não liga os modelos da plataforma',
  recusado($$select public.definir_mensagens_do_pacote(true)$$));
select set_config('request.jwt.claim.sub', 'e4500000-0000-0000-0000-0000000000ad', false);
select (public.definir_mensagens_do_pacote(true)->>'pacotes')::int as refeitos \gset
select t_verdade('a plataforma liga, e o pacote que já estava na agenda ganha as mensagens',
  :refeitos >= 1 and (public.ajustes_da_plataforma()->>'mensagensPacote')::boolean);
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '2. O aviso da última sessão, na hora certa e com o texto certo'
select t_texto('última sessão: seis dias antes da última terça, às 10h do salão',
  to_char((t_msg(:'pc', 'pacote_renovar')).quando at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'),
  to_char(:'terca'::date + 21 - 6, 'YYYY-MM-DD') || ' 10:00');
select t_texto('   pelo modelo novo (o de renovação a Meta aprovou como Marketing): nome, pacote, última sessão e salão',
  (t_msg(:'pc', 'pacote_renovar')).modelo || ' | ' || (t_msg(:'pc', 'pacote_renovar')).variaveis::text,
  'agendapro_pacote_ultima_sessao | ["Maria", "Mão e pé mensal", "terça, '
    || to_char(:'terca'::date + 21, 'DD/MM') || ' às 14:00", "Salão Recado"]');
select t_verdade('   sem convite para renovar, no texto do histórico',
  (t_msg(:'pc', 'pacote_renovar')).corpo like 'Olá, Maria. Informação sobre o seu pacote Mão e pé mensal.%Última sessão incluída: terça, %Local: Salão Recado%Depois dessa sessão, o pacote se encerra.%'
  and (t_msg(:'pc', 'pacote_renovar')).corpo not like '%renova%');
select t_verdade('   presa à última terça, para o número da Maria',
  (t_msg(:'pc', 'pacote_renovar')).agendamento_id = t_sessao(:'pc', 4)
  and (t_msg(:'pc', 'pacote_renovar')).destino = '5511945000003'
  and (t_msg(:'pc', 'pacote_renovar')).status = 'pendente');
select t_igual('lembrete de pagamento: não nasce (a receber, as sessões esperam o "Recebi")',
  (select count(*) from public.notificacoes where chave = 'pacote_pagamento:' || :'pc'), 0);
select t_verdade('o aviso conta na franquia como as mensagens da cliente',
  public.pode_enviar_tipo('54500000-0000-0000-0000-00000000000a', 'pacote_renovar'));

\echo ''
\echo '3. A última terça vira quarta, às 15h'
update public.agendamentos set inicio = inicio + interval '1 day 1 hour', fim = fim + interval '1 day 1 hour'
 where id = t_sessao(:'pc', 4);
select t_texto('o aviso anda um dia junto',
  to_char((t_msg(:'pc', 'pacote_renovar')).quando at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'),
  to_char(:'terca'::date + 22 - 6, 'YYYY-MM-DD') || ' 10:00');
select t_texto('   e o texto diz a nova data (e não a velha)',
  (t_msg(:'pc', 'pacote_renovar')).variaveis->>2,
  'quarta, ' || to_char(:'terca'::date + 22, 'DD/MM') || ' às 15:00');
select t_verdade('   no corpo também',
  (t_msg(:'pc', 'pacote_renovar')).corpo like '%Última sessão incluída: quarta, ' || to_char(:'terca'::date + 22, 'DD/MM') || ' às 15:00%');

\echo ''
\echo '4. A última cai e volta'
update public.agendamentos set status = 'cancelado' where id = t_sessao(:'pc', 4);
select t_texto('cancelada a última: sobra sessão para marcar, o aviso sai da fila',
  (t_msg(:'pc', 'pacote_renovar')).status, 'cancelado');
update public.agendamentos set status = 'confirmado'
 where id = (select id from public.agendamentos where pacote_cliente_id = :'pc' and status = 'cancelado');
select t_texto('voltou: o aviso volta para a fila',
  (t_msg(:'pc', 'pacote_renovar')).status, 'pendente');
select t_igual('   a mesma linha (nenhuma mensagem dobrada)',
  (select count(*) from public.notificacoes where tipo = 'pacote_renovar' and chave = 'pacote_renovar:' || :'pc'), 1);

\echo ''
\echo '5. Recebi, e desfazer'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select public.receber_pacote(:'pc', 'pix');
commit;
select t_texto('pagou: o aviso da última sessão fica', (t_msg(:'pc', 'pacote_renovar')).status, 'pendente');
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select public.desfazer_recebimento_pacote(:'pc');
commit;
select t_igual('desfez o recebimento: e lembrete de pagamento continua sem nascer',
  (select count(*) from public.notificacoes where chave = 'pacote_pagamento:' || :'pc'), 0);

\echo ''
\echo '6. A chave do salão'
update public.saloes set cfg = cfg || '{"notifPacoteRenova": false}' where id = '54500000-0000-0000-0000-00000000000a';
select t_texto('desligou o aviso da última sessão em Notificações: sai da fila',
  (t_msg(:'pc', 'pacote_renovar')).status || ' | ' || (t_msg(:'pc', 'pacote_renovar')).motivo,
  'cancelado | desligado pelo salão');
update public.saloes set cfg = cfg || '{"notifPacoteRenova": true}' where id = '54500000-0000-0000-0000-00000000000a';
select t_texto('religou: volta', (t_msg(:'pc', 'pacote_renovar')).status, 'pendente');

\echo ''
\echo '7. A primeira sessão passa para daqui a pouco'
-- Para amanhã às 14h (ou hoje às 14h, se ainda não deu 9h): dentro da
-- jornada, no futuro, e com a véspera às 10h já sem folga — rode o teste
-- a qualquer hora do dia.
update public.agendamentos
   set inicio = ((case when extract(hour from now() at time zone 'America/Sao_Paulo') >= 9
                       then (now() at time zone 'America/Sao_Paulo')::date + 1
                       else (now() at time zone 'America/Sao_Paulo')::date end + time '14:00')
                 at time zone 'America/Sao_Paulo'),
       fim   = ((case when extract(hour from now() at time zone 'America/Sao_Paulo') >= 9
                       then (now() at time zone 'America/Sao_Paulo')::date + 1
                       else (now() at time zone 'America/Sao_Paulo')::date end + time '14:45')
                 at time zone 'America/Sao_Paulo')
 where id = t_sessao(:'pc', 1);
select t_igual('a primeira chegou perto, ainda a receber: nem assim nasce lembrete de pagamento',
  (select count(*) from public.notificacoes where chave = 'pacote_pagamento:' || :'pc'), 0);

\echo ''
\echo '8. Renovou'
-- Com a forma de pagamento nas mensagens ligada, para ver o que a
-- confirmação das terças novas diz.
select set_config('request.jwt.claim.sub', 'e4500000-0000-0000-0000-0000000000ad', false);
select public.definir_mensagens_com_pagamento(true);
select set_config('request.jwt.claim.sub', '', false);
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select (public.montar_pacote('54520000-0000-0000-0000-0000000000b1', 'c4510000-0000-0000-0000-00000000000a',
            220, 'pix', '94500000-0000-0000-0000-00000000000d', t_semanas(:'terca'::date + 28, 4))->>'pacoteCliente') as pc2 \gset
commit;
select t_texto('o aviso do pacote antigo sai da fila',
  (t_msg(:'pc', 'pacote_renovar')).status || ' | ' || (t_msg(:'pc', 'pacote_renovar')).motivo,
  'cancelado | pacote renovado');
select t_texto('o novo tem o dele, seis dias antes da última terça nova',
  to_char((t_msg(:'pc2', 'pacote_renovar')).quando at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI'),
  to_char(:'terca'::date + 49 - 6, 'YYYY-MM-DD') || ' 10:00');
select t_igual('pago no balcão: o lembrete de pagamento nem chegou a nascer',
  (select count(*) from public.notificacoes where chave = 'pacote_pagamento:' || :'pc2'), 0);
select t_verdade('   e as mensagens das terças novas dizem "já pago (Pix)", e não "a pagar" (o antigo, a receber, ainda diz)',
  not exists (select 1 from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
               where a.pacote_cliente_id = :'pc2' and n.corpo like '%a pagar%')
  and exists (select 1 from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
               where a.pacote_cliente_id = :'pc2' and n.tipo = 'lembrete' and n.status = 'pendente'
                 and n.corpo like '%Pacote já pago (Pix)%' and n.corpo like '%R$ 0,00 — sessão do pacote%')
  and exists (select 1 from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
               where a.pacote_cliente_id = :'pc2' and n.tipo = 'lembrete' and n.status = 'pendente')
  and public.pecas_agendamento(t_sessao(:'pc', 1))->>'pagamento' = 'Pacote a pagar no salão');
select t_texto('com o modelo do pacote ligado, a cliente recebe a lista: cada data, a hora e o procedimento',
  (t_msg(:'pc2', 'pacote_agenda')).modelo || ' | ' || ((t_msg(:'pc2', 'pacote_agenda')).variaveis->>2),
  'agendapro_pacote_agenda | ter ' || to_char(:'terca'::date + 28, 'DD/MM') || ' às 14:00 (Mão); ter '
    || to_char(:'terca'::date + 35, 'DD/MM') || ' às 14:00 (Mão + Pé); ter '
    || to_char(:'terca'::date + 42, 'DD/MM') || ' às 14:00 (Mão); ter '
    || to_char(:'terca'::date + 49, 'DD/MM') || ' às 14:00 (Mão + Pé)');
select t_igual('   no lugar da confirmação (nenhuma confirmação do pacote fica na fila)',
  (select count(*) from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
    where a.pacote_cliente_id = :'pc2' and n.tipo = 'confirmacao' and n.status = 'pendente'), 0);
select t_texto('   com o salão no lugar da profissional ("vai que muda"), quatro variáveis, e saindo agora',
  ((t_msg(:'pc2', 'pacote_agenda')).variaveis->>3) || ' | '
    || jsonb_array_length((t_msg(:'pc2', 'pacote_agenda')).variaveis) || ' | '
    || ((t_msg(:'pc2', 'pacote_agenda')).quando <= now() + interval '1 minute')::text, 'Salão Recado | 4 | true');
select t_verdade('   e o texto do histórico: sem a profissional, com o Local',
  (t_msg(:'pc2', 'pacote_agenda')).corpo like 'Olá, Maria. Seu pacote Mão e pé mensal está com os horários marcados.%Local: Salão Recado%'
  and (t_msg(:'pc2', 'pacote_agenda')).corpo not like '%Profissional%');
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select public.cancelar_pacote_cliente(:'pc2');
commit;
select t_texto('tirou a cliente do pacote: o aviso sai',
  (t_msg(:'pc2', 'pacote_renovar')).status, 'cancelado');

\echo ''
\echo '9. Agenda incompleta, cliente sem telefone'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select (public.montar_pacote('54520000-0000-0000-0000-0000000000b1', 'c4510000-0000-0000-0000-00000000000b',
            200, null, '94500000-0000-0000-0000-00000000000d',
            t_semanas(:'terca'::date + 1, 2))->>'pacoteCliente') as pc3 \gset
  select (public.montar_pacote('54520000-0000-0000-0000-0000000000b1', 'c4510000-0000-0000-0000-00000000000c',
            200, null, '94500000-0000-0000-0000-00000000000d',
            t_semanas(:'terca'::date + 2, 4))->>'pacoteCliente') as pc4 \gset
commit;
select t_igual('duas das quatro sessões marcadas: não há "última sessão" para avisar',
  (select count(*) from public.notificacoes where chave = 'pacote_renovar:' || :'pc3'), 0);
select t_igual('   e lembrete de pagamento também não',
  (select count(*) from public.notificacoes where chave = 'pacote_pagamento:' || :'pc3'), 0);
-- Um pacote inteiro e pago da Lia, nas sextas: o aviso dele fica na fila
-- para a seção 10 ver a plataforma desligar.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4500000-0000-0000-0000-00000000000a';
  select (public.montar_pacote('54520000-0000-0000-0000-0000000000b1', 'c4510000-0000-0000-0000-00000000000b',
            200, 'pix', '94500000-0000-0000-0000-00000000000d',
            t_semanas(:'terca'::date + 3, 4))->>'pacoteCliente') as pc5 \gset
commit;
select t_texto('   o pacote inteiro da Lia, pago: aviso da última sessão na fila',
  (t_msg(:'pc5', 'pacote_renovar')).status, 'pendente');
select t_igual('cliente sem telefone: nenhuma das duas',
  (select count(*) from public.notificacoes where chave in ('pacote_renovar:' || :'pc4', 'pacote_pagamento:' || :'pc4')), 0);

\echo ''
\echo '10. A plataforma desliga; e ninguém chama as peças de dentro'
select set_config('request.jwt.claim.sub', 'e4500000-0000-0000-0000-0000000000ad', false);
select public.definir_mensagens_do_pacote(false);
select set_config('request.jwt.claim.sub', '', false);
select t_igual('desligou: nada do pacote fica pendente',
  (select count(*) from public.notificacoes
    where tipo in ('pacote_renovar', 'pacote_pagamento') and status = 'pendente'), 0);
select t_texto('   com o motivo escrito', (t_msg(:'pc5', 'pacote_renovar')).motivo,
  'mensagens do pacote desligadas');
select set_config('request.jwt.claim.sub', 'a4500000-0000-0000-0000-00000000000a', false);
set role authenticated;
select t_verdade('a dona não chama o motor das mensagens',
  recusado(format('select public.avisos_do_pacote(%L)', :'pc'))
  and recusado('select public.refazer_avisos_de_pacote(null)')
  and recusado(format('select public.gravar_aviso_do_pacote(%L, ''pacote_renovar'', ''x'', null, now(), ''0'', now(), ''1'', null, null, ''x'', ''[]'')',
                      '54500000-0000-0000-0000-00000000000a')));
select t_verdade('   ela só lê se as mensagens do pacote estão liberadas (o aviso da tela)',
  public.mensagens_do_pacote() = false);
reset role;
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select t_verdade('nem quem não entrou', recusado('select public.definir_mensagens_do_pacote(true)')
  and recusado('select public.mensagens_do_pacote()'));
reset role;
