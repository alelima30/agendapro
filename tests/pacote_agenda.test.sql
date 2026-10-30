-- ===========================================================================
-- AgendaPro — o pacote com agenda fixa e o pagamento do pacote (43)
--
-- "Ela paga mensal e vai toda terça às 14h: na primeira faz mão, na segunda
--  mão e pé, na terceira só mão, na quarta mão e pé."
--
--   1. a recepção monta: o vínculo e as 4 terças, cada uma com o seu serviço
--      e a sua duração, já confirmadas e cobertas pelo pacote;
--   2. uma mensagem só, com as 4 datas; o lembrete de cada uma fica;
--   3. "a receber": a mensagem não diz "já pago";
--   4. tudo ou nada: uma semana que não cabe devolve o porquê e não grava
--      nada; dia fora do pacote; mais semanas que sessões;
--   5. receber vira comanda fechada (o faturamento vê); não recebe duas
--      vezes; desfazer é da gestão;
--   6. só vincular, já pago; quem atende não monta; a cliente não monta;
--   7. tirar do pacote tira as terças que ainda vão acontecer.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4300000-0000-0000-0000-00000000000a'),  -- Ana   — dona
  ('b4300000-0000-0000-0000-00000000000b'),  -- Rita  — recepção
  ('d4300000-0000-0000-0000-00000000000d'),  -- Ju    — profissional
  ('c4300000-0000-0000-0000-00000000000c');  -- Maria — cliente com conta
insert into public.perfis (id, nome, telefone) values
  ('a4300000-0000-0000-0000-00000000000a', 'Ana',   '+5511943000001'),
  ('b4300000-0000-0000-0000-00000000000b', 'Rita',  '+5511943000002'),
  ('d4300000-0000-0000-0000-00000000000d', 'Ju',    '+5511943000004'),
  ('c4300000-0000-0000-0000-00000000000c', 'Maria', '+5511943000003')
on conflict (id) do update set nome = excluded.nome;

insert into public.saloes (id, slug, nome, status, fuso) values
  ('54300000-0000-0000-0000-00000000000a', 'pacote-fixo', 'Salão Pacote Fixo', 'ativo', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status) values
  ('54300000-0000-0000-0000-00000000000a', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a4300000-0000-0000-0000-00000000000a', '54300000-0000-0000-0000-00000000000a', 'dono'),
  ('b4300000-0000-0000-0000-00000000000b', '54300000-0000-0000-0000-00000000000a', 'recepcao'),
  ('d4300000-0000-0000-0000-00000000000d', '54300000-0000-0000-0000-00000000000a', 'profissional'),
  ('c4300000-0000-0000-0000-00000000000c', '54300000-0000-0000-0000-00000000000a', 'cliente');
insert into public.profissionais (id, salao_id, perfil_id, nome, telefone, ativo) values
  ('94300000-0000-0000-0000-00000000000d', '54300000-0000-0000-0000-00000000000a',
   'd4300000-0000-0000-0000-00000000000d', 'Ju', '11943000004', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '94300000-0000-0000-0000-00000000000d', d, '08:00', '20:00' from generate_series(0, 6) d;
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco) values
  ('54310000-0000-0000-0000-0000000000a1', '54300000-0000-0000-0000-00000000000a', 'Mão', 45, 0, 40),
  ('54310000-0000-0000-0000-0000000000a2', '54300000-0000-0000-0000-00000000000a', 'Pé',  45, 0, 50),
  ('54310000-0000-0000-0000-0000000000a3', '54300000-0000-0000-0000-00000000000a', 'Escova', 45, 0, 70);
insert into public.servicos_profissionais (servico_id, profissional_id)
  select s, '94300000-0000-0000-0000-00000000000d'
    from unnest(array['54310000-0000-0000-0000-0000000000a1','54310000-0000-0000-0000-0000000000a2',
                      '54310000-0000-0000-0000-0000000000a3']::uuid[]) s;
insert into public.pacotes (id, salao_id, nome, preco, sessoes, validade_dias) values
  ('54320000-0000-0000-0000-0000000000b1', '54300000-0000-0000-0000-00000000000a',
   'Mão e pé mensal', 300, 4, 30),
  ('54320000-0000-0000-0000-0000000000b2', '54300000-0000-0000-0000-00000000000a',
   'Só de segunda', 100, 4, 30);
update public.pacotes set dias = '{1}' where id = '54320000-0000-0000-0000-0000000000b2';
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('54320000-0000-0000-0000-0000000000b1', '54310000-0000-0000-0000-0000000000a1'),
  ('54320000-0000-0000-0000-0000000000b1', '54310000-0000-0000-0000-0000000000a2'),
  ('54320000-0000-0000-0000-0000000000b2', '54310000-0000-0000-0000-0000000000a1');
insert into public.clientes (id, salao_id, perfil_id, nome, telefone) values
  ('c4310000-0000-0000-0000-00000000000a', '54300000-0000-0000-0000-00000000000a',
   'c4300000-0000-0000-0000-00000000000c', 'Maria Souza', '5511943000003'),
  ('c4310000-0000-0000-0000-00000000000b', '54300000-0000-0000-0000-00000000000a', null,
   'Joana Lima', '5511943000099');

-- A primeira terça a pelo menos uma semana de hoje, e as datas das 4 terças
-- às 14h de Brasília, no formato que a tela manda.
select (current_date + ((2 - extract(dow from current_date)::int + 7) % 7) + 7) as terca \gset
create temp table semanas as
  select n, to_char(((:'terca'::date + (n - 1) * 7) + time '14:00') at time zone 'America/Sao_Paulo',
                    'YYYY-MM-DD"T"HH24:MI:SSOF') as inicio
    from generate_series(1, 4) n;
grant select on semanas to authenticated;

grant usage on schema auth to anon, authenticated;

\echo ''
\echo '1. A recepção monta o pacote com as 4 terças'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4300000-0000-0000-0000-00000000000b';
  create temp table r1 on commit drop as
    select public.montar_pacote('54320000-0000-0000-0000-0000000000b1', 'c4310000-0000-0000-0000-00000000000a',
      300, null, '94300000-0000-0000-0000-00000000000d',
      (select jsonb_agg(jsonb_build_object('inicio', inicio, 'servicos',
                case when n % 2 = 1 then '["54310000-0000-0000-0000-0000000000a1"]'::jsonb
                     else '["54310000-0000-0000-0000-0000000000a1","54310000-0000-0000-0000-0000000000a2"]'::jsonb end)
                order by n) from semanas)) as r;
  do $$ begin
    perform t_verdade('montou', (select (r->>'ok')::boolean from r1));
  end $$;
commit;

do $$
declare v_pc uuid := (select id from public.pacote_clientes where cliente_id = 'c4310000-0000-0000-0000-00000000000a');
begin
  perform t_igual('as 4 terças estão na agenda, confirmadas e cobertas pelo pacote',
    (select count(*) from public.agendamentos where pacote_cliente_id = v_pc
       and status = 'confirmado' and valor_previsto = 0 and origem = 'recepcao'), 4);
  perform t_texto('na ordem: mão, mão e pé, mão, mão e pé',
    (select string_agg(x.s, ' | ' order by x.inicio) from (
       select a.inicio, string_agg(sv.nome, ' + ' order by asv.ordem) s
         from public.agendamentos a
         join public.agendamento_servicos asv on asv.agendamento_id = a.id
         join public.servicos sv on sv.id = asv.servico_id
        where a.pacote_cliente_id = v_pc group by a.id, a.inicio) x),
    'Mão | Mão + Pé | Mão | Mão + Pé');
  perform t_texto('cada semana com a sua duração (45 e 90 minutos)',
    (select string_agg((extract(epoch from fim - inicio) / 60)::int::text, ',' order by inicio)
       from public.agendamentos where pacote_cliente_id = v_pc), '45,90,45,90');
  perform t_texto('todas às 14h, nas terças',
    (select string_agg(distinct to_char(inicio at time zone 'America/Sao_Paulo', 'Dy HH24:MI'), ',')
       from public.agendamentos where pacote_cliente_id = v_pc), 'Tue 14:00');
  perform t_texto('o vínculo fica a receber, com o valor combinado',
    (select valor::text || '|' || coalesce(pago_em::text, 'sem pagamento')
       from public.pacote_clientes where id = v_pc), '300.00|sem pagamento');
  perform t_igual('a validade conta da primeira terça (vence 30 dias depois dela)',
    (select (vence_em - (select min((inicio at time zone 'America/Sao_Paulo')::date)
                           from public.agendamentos where pacote_cliente_id = v_pc))
       from public.pacote_clientes where id = v_pc), 30);
end $$;

\echo ''
\echo '2. Uma mensagem só, com as 4 datas'
do $$
declare v_pc uuid := (select id from public.pacote_clientes where cliente_id = 'c4310000-0000-0000-0000-00000000000a');
  v_datas text := (select string_agg(to_char(inicio at time zone 'America/Sao_Paulo', 'DD/MM'), ', ' order by inicio)
                     from public.agendamentos where pacote_cliente_id = v_pc);
begin
  v_datas := regexp_replace(v_datas, ', ([^,]*)$', ' e \1');
  perform t_igual('uma confirmação na fila para a cliente, e não quatro',
    (select count(*) from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
      where a.pacote_cliente_id = v_pc and n.tipo = 'confirmacao' and n.status = 'pendente'), 1);
  perform t_texto('com as quatro datas no lugar da data',
    (select n.variaveis->>1 from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
      where a.pacote_cliente_id = v_pc and n.tipo = 'confirmacao' and n.status = 'pendente'), v_datas);
  perform t_texto('a hora, e o pacote no lugar do serviço',
    (select (n.variaveis->>2) || ' | ' || (n.variaveis->>3) from public.notificacoes n
       join public.agendamentos a on a.id = n.agendamento_id
      where a.pacote_cliente_id = v_pc and n.tipo = 'confirmacao' and n.status = 'pendente'),
    '14:00 | pacote Mão e pé mensal');
  perform t_igual('as outras três confirmações saíram da fila (canceladas, com o motivo)',
    (select count(*) from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
      where a.pacote_cliente_id = v_pc and n.tipo = 'confirmacao' and n.status = 'cancelado'
        and n.motivo like 'pacote:%'), 3);
  perform t_igual('quem atende recebe um aviso só, também',
    (select count(*) from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
      where a.pacote_cliente_id = v_pc and n.tipo = 'novo' and n.status = 'pendente'), 1);
  perform t_igual('e o lembrete da véspera fica para cada terça',
    (select count(*) from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
      where a.pacote_cliente_id = v_pc and n.tipo = 'lembrete' and n.status = 'pendente'), 4);
end $$;

\echo ''
\echo '3. A receber: a mensagem não diz "já pago"'
do $$ begin
  perform t_texto('o pagamento do horário diz que é a combinar',
    (select public.pecas_agendamento(a.id)->>'pagamento' from public.agendamentos a
       join public.pacote_clientes pc on pc.id = a.pacote_cliente_id
      where pc.cliente_id = 'c4310000-0000-0000-0000-00000000000a' limit 1),
    'Pacote (pagamento a combinar com o salão)');
end $$;

\echo ''
\echo '4. Tudo ou nada'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4300000-0000-0000-0000-00000000000b';
  do $$
  declare r jsonb; v_antes bigint := (select count(*) from public.pacote_clientes);
  begin
    -- A Joana nas mesmas terças: a segunda (mão e pé, 14h–15h30) bate.
    r := public.montar_pacote('54320000-0000-0000-0000-0000000000b1', 'c4310000-0000-0000-0000-00000000000b',
      300, null, '94300000-0000-0000-0000-00000000000d',
      (select jsonb_agg(jsonb_build_object('inicio', inicio, 'servicos',
               '["54310000-0000-0000-0000-0000000000a1"]'::jsonb) order by n) from semanas));
    perform t_verdade('com horário ocupado, não monta', not (r->>'ok')::boolean);
    perform t_verdade('e diz, na semana, com quem está o horário (a recepção pode ver)',
      (r->'semanas'->0->>'motivo') like '%Maria Souza%');
    perform t_igual('nada foi gravado — nem o vínculo', (select count(*) from public.pacote_clientes), v_antes);

    r := public.montar_pacote('54320000-0000-0000-0000-0000000000b2', 'c4310000-0000-0000-0000-00000000000b',
      100, null, '94300000-0000-0000-0000-00000000000d',
      jsonb_build_array(jsonb_build_object('inicio', (select inicio from semanas where n = 1),
                                           'servicos', '["54310000-0000-0000-0000-0000000000a1"]'::jsonb)));
    perform t_texto('terça num pacote só de segunda: diz os dias',
      r->'semanas'->0->>'motivo', 'O pacote vale só segunda.');

    perform t_texto('serviço de fora do pacote é recusado na semana',
      public.montar_pacote('54320000-0000-0000-0000-0000000000b1', 'c4310000-0000-0000-0000-00000000000b',
        300, null, '94300000-0000-0000-0000-00000000000d',
        jsonb_build_array(jsonb_build_object('inicio', (select inicio from semanas where n = 1),
          'servicos', '["54310000-0000-0000-0000-0000000000a3"]'::jsonb)))->'semanas'->0->>'motivo',
      'Um dos serviços desta semana não está no pacote.');

    perform t_texto('mais semanas que sessões é recusado',
      erro_de($q$select public.montar_pacote('54320000-0000-0000-0000-0000000000b1',
        'c4310000-0000-0000-0000-00000000000b', 300, null, '94300000-0000-0000-0000-00000000000d',
        (select jsonb_agg(jsonb_build_object('inicio', to_char(((current_date + 30 + g * 7) + time '09:00')
            at time zone 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
            'servicos', '["54310000-0000-0000-0000-0000000000a1"]'::jsonb)) from generate_series(1, 5) g))$q$),
      'O pacote tem 4 sessões, e você marcou 5 semanas.');
  end $$;
commit;

\echo ''
\echo '5. Receber o pagamento'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4300000-0000-0000-0000-00000000000b';
  select public.receber_pacote((select id from public.pacote_clientes
                                 where cliente_id = 'c4310000-0000-0000-0000-00000000000a'), 'pix');
commit;
do $$
declare pc record;
begin
  select * into pc from public.pacote_clientes where cliente_id = 'c4310000-0000-0000-0000-00000000000a';
  perform t_verdade('a recepção recebeu no Pix: o pacote fica pago',
    pc.pago_em is not null and pc.forma_pagamento = 'pix' and pc.comanda_id is not null);
  perform t_texto('virou uma comanda fechada, automática, com o item do pacote',
    (select c.status || ' | ' || c.automatica || ' | ' || i.descricao || ' | ' || i.preco_unit
       from public.comandas c join public.comanda_itens i on i.comanda_id = c.id where c.id = pc.comanda_id),
    'fechada | true | Pacote Mão e pé mensal | 300.00');
  perform t_texto('paga no Pix, pelo valor do pacote',
    (select forma || ' ' || valor from public.pagamentos where comanda_id = pc.comanda_id), 'pix 300.00');
  perform t_texto('e o faturamento vê: o total da comanda é o do pacote',
    (select total::text from public.comandas_totais where id = pc.comanda_id), '300.00');
  perform t_texto('agora a mensagem do horário diz que o pacote está pago',
    (select public.pecas_agendamento(a.id)->>'pagamento' from public.agendamentos a
      where a.pacote_cliente_id = pc.id limit 1), 'Pacote (já pago)');
end $$;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4300000-0000-0000-0000-00000000000b';
  do $$ begin
    perform t_texto('não recebe duas vezes',
      erro_de($q$select public.receber_pacote((select id from public.pacote_clientes
        where cliente_id = 'c4310000-0000-0000-0000-00000000000a'), 'pix')$q$),
      'Este pacote já está pago.');
    perform t_texto('desfazer não é da recepção',
      erro_de($q$select public.desfazer_recebimento_pacote((select id from public.pacote_clientes
        where cliente_id = 'c4310000-0000-0000-0000-00000000000a'))$q$),
      'Só o proprietário ou um administrador desfaz um recebimento.');
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4300000-0000-0000-0000-00000000000a';
  create temp table cm on commit drop as
    select comanda_id from public.pacote_clientes where cliente_id = 'c4310000-0000-0000-0000-00000000000a';
  select public.desfazer_recebimento_pacote((select id from public.pacote_clientes
                                              where cliente_id = 'c4310000-0000-0000-0000-00000000000a'));
  do $$ begin
    perform t_verdade('a dona desfaz: a comanda sai e o pacote volta a "a receber"',
      not exists (select 1 from public.comandas where id = (select comanda_id from cm))
      and (select pago_em is null and valor = 300 from public.pacote_clientes
            where cliente_id = 'c4310000-0000-0000-0000-00000000000a'));
  end $$;
commit;

\echo ''
\echo '6. Só vincular, já pago; quem atende e a cliente não montam'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4300000-0000-0000-0000-00000000000a';
  create temp table r6 on commit drop as
    select public.montar_pacote('54320000-0000-0000-0000-0000000000b1', 'c4310000-0000-0000-0000-00000000000b',
      280, 'dinheiro') as r;
  do $$ begin
    perform t_verdade('sem semanas: só o vínculo, já pago em dinheiro, pelo valor dado',
      (select (r->>'ok')::boolean from r6)
      and exists (select 1 from public.pacote_clientes pc
                   join public.pagamentos pg on pg.comanda_id = pc.comanda_id
                  where pc.cliente_id = 'c4310000-0000-0000-0000-00000000000b'
                    and pc.forma_pagamento = 'dinheiro' and pg.valor = 280)
      and not exists (select 1 from public.agendamentos a join public.pacote_clientes pc
                       on pc.id = a.pacote_cliente_id
                      where pc.cliente_id = 'c4310000-0000-0000-0000-00000000000b'));
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'd4300000-0000-0000-0000-00000000000d';
  do $$ begin
    perform t_texto('quem atende não monta pacote',
      erro_de($q$select public.montar_pacote('54320000-0000-0000-0000-0000000000b1',
        'c4310000-0000-0000-0000-00000000000b', 300)$q$),
      'Só o balcão e a gestão vinculam cliente ao pacote.');
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'c4300000-0000-0000-0000-00000000000c';
  do $$ begin
    perform t_verdade('a cliente não monta pacote para si',
      recusado($q$select public.montar_pacote('54320000-0000-0000-0000-0000000000b1',
        'c4310000-0000-0000-0000-00000000000a', 0)$q$));
    perform t_verdade('nem se dá o pacote como pago',
      recusado($q$select public.receber_pacote((select id from public.pacote_clientes limit 1), 'pix', 1)$q$));
  end $$;
commit;

\echo ''
\echo '7. Tirar do pacote tira as terças que vão acontecer'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4300000-0000-0000-0000-00000000000a';
  select public.cancelar_pacote_cliente((select id from public.pacote_clientes
                                          where cliente_id = 'c4310000-0000-0000-0000-00000000000a'));
commit;
do $$ begin
  perform t_igual('as 4 terças saíram da agenda, com o motivo',
    (select count(*) from public.agendamentos a join public.pacote_clientes pc on pc.id = a.pacote_cliente_id
      where pc.cliente_id = 'c4310000-0000-0000-0000-00000000000a'
        and a.status = 'cancelado' and a.cancelado_motivo = 'pacote cancelado'), 4);
  perform t_igual('e os lembretes delas não saem mais',
    (select count(*) from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
       join public.pacote_clientes pc on pc.id = a.pacote_cliente_id
      where pc.cliente_id = 'c4310000-0000-0000-0000-00000000000a' and n.status = 'pendente'), 0);
end $$;

\echo ''
\echo '8. Sem semanas, de qualquer jeito que a lista vazia chegue'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4300000-0000-0000-0000-00000000000a';
  do $$ begin
    perform t_verdade('lista vazia como {} (o caminho converte) vincula sem marcar nada',
      (public.montar_pacote('54320000-0000-0000-0000-0000000000b2', 'c4310000-0000-0000-0000-00000000000a',
        null, null, null, '{}'::jsonb)->>'ok')::boolean);
    perform t_verdade('e como nulo também',
      (public.montar_pacote('54320000-0000-0000-0000-0000000000b2', 'c4310000-0000-0000-0000-00000000000b',
        null, null, null, null)->>'ok')::boolean);
  end $$;
commit;
