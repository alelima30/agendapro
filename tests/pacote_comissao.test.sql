-- ===========================================================================
-- AgendaPro — a comissão da sessão de pacote (44_pacote_comissao.sql)
--
-- O exemplo do dono: pacote de R$ 220, mão R$ 40, pé R$ 50; no mês, mão /
-- mão e pé / mão / mão e pé; a profissional ganha 40%.
--
--   1. proporcional: a semana de mão vale R$ 33,85 (comissão R$ 13,54); a
--      de mão e pé, R$ 76,15 (R$ 30,46); as quatro somam os R$ 220;
--   2. conta ao atender, mesmo com o pacote a receber;
--   3. ganha quem atendeu (a terça da Bia é da Bia, com a taxa dela) e a
--      escada vale (par serviço+profissional com valor fixo);
--   4. desfazer o "atendido" tira a comissão;
--   5. aparece no relatório e no painel do dia; a venda do pacote não vira
--      linha "sem profissional"; quem atende não lê a tabela.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4400000-0000-0000-0000-00000000000a'),  -- Ana — dona
  ('d4400000-0000-0000-0000-00000000000d');  -- Ju  — profissional
insert into public.perfis (id, nome, telefone) values
  ('a4400000-0000-0000-0000-00000000000a', 'Ana', '+5511944000001'),
  ('d4400000-0000-0000-0000-00000000000d', 'Ju',  '+5511944000004')
on conflict (id) do update set nome = excluded.nome;
insert into public.saloes (id, slug, nome, status, fuso) values
  ('54400000-0000-0000-0000-00000000000a', 'pacote-comissao', 'Salão Comissão', 'ativo', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status) values
  ('54400000-0000-0000-0000-00000000000a', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a4400000-0000-0000-0000-00000000000a', '54400000-0000-0000-0000-00000000000a', 'dono'),
  ('d4400000-0000-0000-0000-00000000000d', '54400000-0000-0000-0000-00000000000a', 'profissional');
insert into public.profissionais (id, salao_id, perfil_id, nome, comissao_pct, ativo) values
  ('94400000-0000-0000-0000-00000000000d', '54400000-0000-0000-0000-00000000000a',
   'd4400000-0000-0000-0000-00000000000d', 'Ju', 40, true),
  ('94400000-0000-0000-0000-00000000000b', '54400000-0000-0000-0000-00000000000a', null, 'Bia', 50, true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select p, d, '08:00', '20:00' from generate_series(0, 6) d,
    unnest(array['94400000-0000-0000-0000-00000000000d','94400000-0000-0000-0000-00000000000b']::uuid[]) p;
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco) values
  ('54410000-0000-0000-0000-0000000000a1', '54400000-0000-0000-0000-00000000000a', 'Mão', 45, 0, 40),
  ('54410000-0000-0000-0000-0000000000a2', '54400000-0000-0000-0000-00000000000a', 'Pé',  45, 0, 50);
insert into public.pacotes (id, salao_id, nome, preco, sessoes, validade_dias) values
  ('54420000-0000-0000-0000-0000000000b1', '54400000-0000-0000-0000-00000000000a', 'Mão e pé mensal', 220, 4, 30);
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('54420000-0000-0000-0000-0000000000b1', '54410000-0000-0000-0000-0000000000a1'),
  ('54420000-0000-0000-0000-0000000000b1', '54410000-0000-0000-0000-0000000000a2');
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c4410000-0000-0000-0000-00000000000a', '54400000-0000-0000-0000-00000000000a', 'Maria Souza', '5511944000003');

select (current_date + ((2 - extract(dow from current_date)::int + 7) % 7) + 7) as terca \gset
grant usage on schema auth to anon, authenticated;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4400000-0000-0000-0000-00000000000a';
  select public.montar_pacote('54420000-0000-0000-0000-0000000000b1', 'c4410000-0000-0000-0000-00000000000a',
    220, null, '94400000-0000-0000-0000-00000000000d',
    (select jsonb_agg(jsonb_build_object(
       'inicio', to_char(((:'terca'::date + (n - 1) * 7) + time '14:00') at time zone 'America/Sao_Paulo',
                         'YYYY-MM-DD"T"HH24:MI:SSOF'),
       'servicos', case when n % 2 = 1 then '["54410000-0000-0000-0000-0000000000a1"]'::jsonb
                        else '["54410000-0000-0000-0000-0000000000a1","54410000-0000-0000-0000-0000000000a2"]'::jsonb end)
       order by n) from generate_series(1, 4) n));
commit;

create temp table s as
  select row_number() over (order by a.inicio) as n, a.id
    from public.agendamentos a join public.pacote_clientes pc on pc.id = a.pacote_cliente_id
   where pc.cliente_id = 'c4410000-0000-0000-0000-00000000000a';

\echo ''
\echo '1 e 2. Proporcional, ao atender, com o pacote a receber'
update public.agendamentos set status = 'concluido' where id = (select id from s where n = 1);
update public.agendamentos set status = 'concluido' where id = (select id from s where n = 2);
do $$ begin
  perform t_verdade('o pacote está a receber (ninguém pagou ainda)',
    (select pago_em is null from public.pacote_clientes where cliente_id = 'c4410000-0000-0000-0000-00000000000a'));
  perform t_texto('semana de mão: vale R$ 33,85 e a Ju ganha R$ 13,54',
    (select base || ' | ' || comissao || ' | ' || pr.nome from public.pacote_comissoes pk
       join public.profissionais pr on pr.id = pk.profissional_id
      where pk.agendamento_id = (select id from s where n = 1)), '33.85 | 13.54 | Ju');
  perform t_texto('semana de mão e pé: vale R$ 76,15 e a Ju ganha R$ 30,46',
    (select base || ' | ' || comissao from public.pacote_comissoes
      where agendamento_id = (select id from s where n = 2)), '76.15 | 30.46');
end $$;

\echo ''
\echo '3. Ganha quem atendeu, e a escada vale'
-- A terça 3 quem atende é a Bia (50%), e a escada do par diz: Mão com a Bia
-- paga 50% mais R$ 5 fixos.
insert into public.servicos_profissionais (servico_id, profissional_id, comissao_pct, comissao_fixa)
  values ('54410000-0000-0000-0000-0000000000a1', '94400000-0000-0000-0000-00000000000b', 50, 5);
update public.agendamentos set profissional_id = '94400000-0000-0000-0000-00000000000b'
 where id = (select id from s where n = 3);
update public.agendamentos set status = 'concluido' where id = (select id from s where n = 3);
update public.agendamentos set status = 'concluido' where id = (select id from s where n = 4);
do $$ begin
  perform t_texto('a terça da Bia é da Bia, com a taxa do par (50% + R$ 5)',
    (select base || ' | ' || comissao || ' | ' || pr.nome from public.pacote_comissoes pk
       join public.profissionais pr on pr.id = pk.profissional_id
      where pk.agendamento_id = (select id from s where n = 3)), '33.85 | 21.92 | Bia');
  perform t_texto('as quatro sessões somam o valor do pacote',
    (select sum(base)::text from public.pacote_comissoes pk
      where pk.agendamento_id in (select id from s)), '220.00');
end $$;

\echo ''
\echo '4. Desfazer o atendido'
update public.agendamentos set status = 'confirmado' where id = (select id from s where n = 4);
do $$ begin
  perform t_igual('voltou de "atendido": a comissão sai',
    (select count(*) from public.pacote_comissoes where agendamento_id = (select id from s where n = 4)), 0);
end $$;
update public.agendamentos set status = 'concluido' where id = (select id from s where n = 4);

\echo ''
\echo '5. No relatório e no painel do dia'
-- O pacote é pago: a venda vira comanda sem profissional, e não pode virar
-- uma linha "sem profissional" no relatório de comissões.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4400000-0000-0000-0000-00000000000a';
  select public.receber_pacote((select id from public.pacote_clientes
                                 where cliente_id = 'c4410000-0000-0000-0000-00000000000a'), 'pix');
  create temp table rel on commit drop as
    select public.relatorio('54400000-0000-0000-0000-00000000000a', current_date - 1, current_date + 1) as r,
           public.painel_hoje('54400000-0000-0000-0000-00000000000a') as h;
  do $$
  declare r jsonb := (select r from rel); h jsonb := (select h from rel);
  begin
    perform t_texto('o relatório: Ju com as três terças dela (13,54 + 30,46 + 30,46)',
      (select c->>'comissao' from jsonb_array_elements(r->'comissoes') c where c->>'nome' = 'Ju'), '74.46');
    perform t_texto('e a Bia com a dela',
      (select c->>'comissao' from jsonb_array_elements(r->'comissoes') c where c->>'nome' = 'Bia'), '21.92');
    perform t_falso('a venda do pacote não aparece como "sem profissional"',
      exists (select 1 from jsonb_array_elements(r->'comissoes') c where c->>'nome' = 'sem profissional'));
    perform t_texto('o faturamento conta o pacote uma vez só (a venda)',
      r->>'faturamento', '220.00');
    perform t_texto('e o painel do dia soma as comissões das sessões de hoje',
      h->'dinheiro'->>'comissoes', '96.38');
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'd4400000-0000-0000-0000-00000000000d';
  do $$ begin
    perform t_igual('quem atende não lê a tabela de comissões (é dinheiro da casa)',
      (select count(*) from public.pacote_comissoes), 0);
  end $$;
commit;
