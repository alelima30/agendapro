-- ===========================================================================
-- AgendaPro — o fuso horário do salão (58_fuso.sql)
--
-- "Não posso perder nada sobre horários marcados."
--
-- O banco guarda instantes; a agenda mostra hora de parede. Trocar o fuso sem
-- mexer nos instantes faria a cliente das 14:00 virar cliente das 13:00. Este
-- arquivo prova que isso NÃO acontece, por caminho nenhum:
--
--   1. só entra nome de fuso que o banco e o navegador conhecem;
--   2. trocar não muda horário nenhum: passado, futuro, colado um no outro,
--      cancelado, virando a meia-noite, arquivado — nem bloqueio;
--   3. o lembrete e a campanha agendada acompanham; nada é "remarcado", e a
--      cliente não recebe mensagem nenhuma por causa da troca;
--   4. o outro salão não é tocado, e os gatilhos da agenda voltam ligados;
--   5. por 90 segundos ninguém grava horário (o aparelho com a tela antiga);
--   6. ida e volta devolve cada instante exatamente onde estava;
--   7. para o leste e por duas horas; o prazo do sinal não passa do horário;
--   8. quem pode trocar — e a troca direto na tabela move igual;
--   9. fuso antigo inválido não trava a correção;
--  10. se dois horários colidissem no fuso novo, NADA muda.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a5800000-0000-0000-0000-00000000000a'),  -- Ana   — dona do salão A
  ('b5800000-0000-0000-0000-00000000000b'),  -- Rita  — recepção do A
  ('d5800000-0000-0000-0000-00000000000d'),  -- Ju    — profissional do A
  ('e5800000-0000-0000-0000-00000000000e'),  -- Eva   — dona do salão B
  ('f5800000-0000-0000-0000-00000000000f');  -- Sol   — plataforma
insert into public.perfis (id, nome, telefone, super_admin) values
  ('a5800000-0000-0000-0000-00000000000a', 'Ana',  '+5592958000001', false),
  ('b5800000-0000-0000-0000-00000000000b', 'Rita', '+5592958000002', false),
  ('d5800000-0000-0000-0000-00000000000d', 'Ju',   '+5592958000004', false),
  ('e5800000-0000-0000-0000-00000000000e', 'Eva',  '+5592958000005', false),
  ('f5800000-0000-0000-0000-00000000000f', 'Sol',  '+5592958000006', true)
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone,
                               super_admin = excluded.super_admin;

-- Os dois salões já existem há tempo (a trava de 90 s só vale para salão com
-- mais de 10 minutos de vida; o recém-criado é o cadastro ajustando o fuso).
insert into public.saloes (id, slug, nome, status, fuso, criado_em) values
  ('58000000-0000-0000-0000-00000000000a', 'fuso-a', 'Salão de Manaus',  'ativo', 'America/Sao_Paulo', now() - interval '30 days'),
  ('58000000-0000-0000-0000-00000000000b', 'fuso-b', 'Salão do Vizinho', 'ativo', 'America/Sao_Paulo', now() - interval '30 days'),
  ('58000000-0000-0000-0000-00000000000c', 'fuso-c', 'Salão Antigo',     'ativo', 'America/Sao_Paulo', now() - interval '30 days');
insert into public.assinaturas (salao_id, plano, status) values
  ('58000000-0000-0000-0000-00000000000a', 'time', 'ativa'),
  ('58000000-0000-0000-0000-00000000000b', 'time', 'ativa'),
  ('58000000-0000-0000-0000-00000000000c', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a5800000-0000-0000-0000-00000000000a', '58000000-0000-0000-0000-00000000000a', 'dono'),
  ('b5800000-0000-0000-0000-00000000000b', '58000000-0000-0000-0000-00000000000a', 'recepcao'),
  ('d5800000-0000-0000-0000-00000000000d', '58000000-0000-0000-0000-00000000000a', 'profissional'),
  ('e5800000-0000-0000-0000-00000000000e', '58000000-0000-0000-0000-00000000000b', 'dono'),
  ('a5800000-0000-0000-0000-00000000000a', '58000000-0000-0000-0000-00000000000c', 'dono');
insert into public.profissionais (id, salao_id, perfil_id, nome, telefone, ativo) values
  ('95800000-0000-0000-0000-0000000000a1', '58000000-0000-0000-0000-00000000000a',
   'd5800000-0000-0000-0000-00000000000d', 'Ju',  '92958000004', true),
  ('95800000-0000-0000-0000-0000000000a2', '58000000-0000-0000-0000-00000000000a', null, 'Bia', '92958000007', true),
  ('95800000-0000-0000-0000-0000000000b1', '58000000-0000-0000-0000-00000000000b', null, 'Lia', '92958000008', true),
  ('95800000-0000-0000-0000-0000000000c1', '58000000-0000-0000-0000-00000000000c', null, 'Nina', '92958000009', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select p, d, '00:00', '23:59' from generate_series(0, 6) d,
    unnest(array['95800000-0000-0000-0000-0000000000a1','95800000-0000-0000-0000-0000000000a2',
                 '95800000-0000-0000-0000-0000000000b1','95800000-0000-0000-0000-0000000000c1']::uuid[]) p;
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c5800000-0000-0000-0000-0000000000a1', '58000000-0000-0000-0000-00000000000a', 'Maria Souza', '92958001001'),
  ('c5800000-0000-0000-0000-0000000000a2', '58000000-0000-0000-0000-00000000000a', 'Joana Lima',  '92958001002'),
  ('c5800000-0000-0000-0000-0000000000b1', '58000000-0000-0000-0000-00000000000b', 'Carla Dias',  '92958001003'),
  ('c5800000-0000-0000-0000-0000000000c1', '58000000-0000-0000-0000-00000000000c', 'Dona Rosa',   '92958001004');
grant usage on schema auth to anon, authenticated;

create or replace function t_em(p_dia date, p_hora text, p_fuso text default 'America/Sao_Paulo')
returns timestamptz language sql as $$ select (p_dia + p_hora::time) at time zone p_fuso $$;
create or replace function t_rot(p timestamptz, p_fuso text)
returns text language sql as $$ select to_char(p at time zone p_fuso, 'YYYY-MM-DD HH24:MI') $$;

-- Chama como a pessoa, e volta.
create or replace function t_como(p_quem uuid, p_sql text) returns text
language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_quem::text, ''), true);
  perform set_config('role', case when p_quem is null then 'anon' else 'authenticated' end, true);
  begin
    execute p_sql into r;
  exception when others then
    perform set_config('role', 'postgres', true);
    perform set_config('request.jwt.claim.sub', '', true);
    return 'ERRO: ' || sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(r, '');
end $$;

/* O dia-base: daqui a três dias. Fica numa tabela (e não em `current_date`
   solto) para o teste não mudar de dia se cruzar a meia-noite no meio; e é
   lido por função porque o psql não troca variável dentro de `do $$ ... $$`. */
create temporary table t_base as select current_date + 3 as d;
create or replace function t_d() returns date language sql as $$ select d from t_base $$;
select d from t_base \gset

-- ── A agenda do salão A ────────────────────────────────────────────────────
insert into public.agendamentos
  (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto, encaixe) values
  -- o mês passado, concluído
  ('a5810000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a1', '95800000-0000-0000-0000-0000000000a1',
   t_em(t_d() - 13, '09:00'), t_em(t_d() - 13, '10:00'), 'concluido', 'recepcao', 80, false),
  -- três colados, com a Ju: é o caso que derruba uma mudança feita linha a linha
  ('a5810000-0000-0000-0000-000000000002', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a1', '95800000-0000-0000-0000-0000000000a1',
   t_em(t_d(), '09:00'), t_em(t_d(), '10:00'), 'confirmado', 'recepcao', 80, false),
  ('a5810000-0000-0000-0000-000000000003', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a2', '95800000-0000-0000-0000-0000000000a1',
   t_em(t_d(), '10:00'), t_em(t_d(), '11:00'), 'confirmado', 'recepcao', 80, false),
  ('a5810000-0000-0000-0000-000000000004', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a1', '95800000-0000-0000-0000-0000000000a1',
   t_em(t_d(), '11:00'), t_em(t_d(), '11:45'), 'confirmado', 'recepcao', 60, false),
  -- virando a meia-noite, com a Bia
  ('a5810000-0000-0000-0000-000000000006', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a2', '95800000-0000-0000-0000-0000000000a2',
   t_em(t_d(), '23:30'), t_em(t_d() + 1, '00:15'), 'confirmado', 'recepcao', 90, true),
  -- arquivado
  ('a5810000-0000-0000-0000-000000000008', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a1', '95800000-0000-0000-0000-0000000000a2',
   t_em(t_d() + 2, '14:00'), t_em(t_d() + 2, '15:00'), 'confirmado', 'recepcao', 80, false);
-- cancelado, em cima dos dois primeiros (cancelado não ocupa a cadeira)
insert into public.agendamentos
  (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto) values
  ('a5810000-0000-0000-0000-000000000005', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a2', '95800000-0000-0000-0000-0000000000a1',
   t_em(t_d(), '09:30'), t_em(t_d(), '10:30'), 'cancelado', 'recepcao', 80);
-- esperando o sinal, com o prazo no próprio horário
insert into public.agendamentos
  (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto,
   sinal_exigido, sinal_ate) values
  ('a5810000-0000-0000-0000-000000000007', '58000000-0000-0000-0000-00000000000a',
   'c5800000-0000-0000-0000-0000000000a1', '95800000-0000-0000-0000-0000000000a2',
   t_em(t_d() - 1, '15:00'), t_em(t_d() - 1, '16:00'), 'pendente', 'online', 80,
   20, t_em(t_d() - 1, '15:00'));
update public.agendamentos set arquivado_em = now() where id = 'a5810000-0000-0000-0000-000000000008';

insert into public.bloqueios (id, salao_id, profissional_id, inicio, fim, motivo) values
  ('b5810000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-00000000000a',
   '95800000-0000-0000-0000-0000000000a1', t_em(t_d() + 1, '00:00'), t_em(t_d() + 2, '00:00'), 'Folga'),
  ('b5810000-0000-0000-0000-000000000002', '58000000-0000-0000-0000-00000000000a',
   null, t_em(t_d() + 4, '12:00'), t_em(t_d() + 4, '13:00'), 'Almoço da equipe');

-- Uma mensagem que JÁ saiu (não anda) e duas campanhas.
insert into public.notificacoes (id, salao_id, tipo, destino, cliente_id, agendamento_id, quando, corpo, chave, status, enviado_em) values
  ('e5810000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-00000000000a', 'lembrete', '92958001001',
   'c5800000-0000-0000-0000-0000000000a1', 'a5810000-0000-0000-0000-000000000001',
   t_em(t_d() - 14, '09:00'), 'Seu horário é amanhã às 09:00', 'lembrete:teste-enviado', 'enviado', now() - interval '13 days');
insert into public.campanhas (id, salao_id, nome, tipo, corpo, status, agendada_para) values
  ('ca581000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-00000000000a', 'Promo de sábado',  'promocao', 'Oi {{nome}}', 'agendada',  t_em(t_d() - 1, '10:00')),
  ('ca581000-0000-0000-0000-000000000002', '58000000-0000-0000-0000-00000000000a', 'Promo do mês passado', 'promocao', 'Oi {{nome}}', 'concluida', t_em(t_d() - 20, '10:00')),
  ('ca581000-0000-0000-0000-000000000003', '58000000-0000-0000-0000-00000000000a', 'Rascunho sem data', 'promocao', 'Oi {{nome}}', 'rascunho',  null);

-- ── O vizinho ──────────────────────────────────────────────────────────────
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto) values
  ('a5820000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-00000000000b',
   'c5800000-0000-0000-0000-0000000000b1', '95800000-0000-0000-0000-0000000000b1',
   t_em(t_d(), '09:00'), t_em(t_d(), '10:00'), 'confirmado', 'recepcao', 80);

-- ── O retrato de antes ─────────────────────────────────────────────────────
create temporary table antes_ag as
  select id, salao_id, inicio, fim, status, sinal_ate,
         t_rot(inicio, 'America/Sao_Paulo') as rot_ini, t_rot(fim, 'America/Sao_Paulo') as rot_fim
    from public.agendamentos where salao_id in ('58000000-0000-0000-0000-00000000000a', '58000000-0000-0000-0000-00000000000b');
create temporary table antes_bl as
  select id, inicio, fim, t_rot(inicio, 'America/Sao_Paulo') as rot_ini, t_rot(fim, 'America/Sao_Paulo') as rot_fim
    from public.bloqueios where salao_id = '58000000-0000-0000-0000-00000000000a';
create temporary table antes_no as
  select id, salao_id, tipo, status, quando, corpo, chave, (status = 'pendente' and quando > now()) as anda
    from public.notificacoes where salao_id in ('58000000-0000-0000-0000-00000000000a', '58000000-0000-0000-0000-00000000000b');
create temporary table antes_ca as
  select id, status, agendada_para from public.campanhas where salao_id = '58000000-0000-0000-0000-00000000000a';

do $$
begin
  perform t_igual('o salão A tem 8 horários no retrato', (select count(*) from antes_ag
     where salao_id = '58000000-0000-0000-0000-00000000000a'), 8);
  perform t_verdade('e o sistema já deixou lembretes marcados para os de daqui a três dias',
    (select count(*) from antes_no where tipo = 'lembrete' and anda) >= 3);
end $$;

-- ===========================================================================
\echo ''
\echo '1. Só entra fuso que existe'
-- ===========================================================================
do $$
declare e text;
begin
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'BRT')::text$q$);
  perform t_verdade('sigla não é fuso (BRT) — ' || e, e like 'ERRO: Não conheço o fuso horário "BRT"%');
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'UTC+3')::text$q$);
  perform t_verdade('nem conta de cabeça (UTC+3): o navegador não abre a agenda com isso', e like 'ERRO: Não conheço%');
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'posix/America/Manaus')::text$q$);
  perform t_verdade('nem o apelido interno do Postgres (posix/...)', e like 'ERRO: Não conheço%');
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'Marte/Olimpo')::text$q$);
  perform t_verdade('nem cidade que não existe', e like 'ERRO: Não conheço%');
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', '  ')::text$q$);
  perform t_verdade('nem vazio', e like 'ERRO: Não conheço%');

  e := erro_de($q$update public.saloes set fuso = 'Marte/Olimpo' where id = '58000000-0000-0000-0000-00000000000a'$q$);
  perform t_verdade('direto na tabela também não entra — ' || coalesce(e, 'passou'), e like 'Não conheço o fuso horário "Marte/Olimpo"%');
  e := erro_de($q$update public.saloes set fuso = '' where id = '58000000-0000-0000-0000-00000000000a'$q$);
  perform t_verdade('nem fica sem fuso', e like 'O salão precisa de um fuso horário%');
  e := erro_de($q$insert into public.saloes (slug, nome, fuso) values ('fuso-lixo', 'Lixo', 'Qualquer/Coisa')$q$);
  perform t_verdade('salão novo com fuso inventado é recusado', e like 'Não conheço o fuso horário%');

  insert into public.saloes (id, slug, nome, fuso) values
    ('58000000-0000-0000-0000-0000000000d1', 'fuso-nulo', 'Sem Fuso', null);
  perform t_texto('salão novo sem fuso nasce em Brasília',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-0000000000d1'), 'America/Sao_Paulo');
  insert into public.saloes (id, slug, nome, fuso) values
    ('58000000-0000-0000-0000-0000000000d2', 'fuso-acre', 'Do Acre', 'America/Rio_Branco');
  perform t_texto('e com um fuso de verdade nasce nele',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-0000000000d2'), 'America/Rio_Branco');

  perform t_texto('depois de tanta recusa, o salão A continua onde estava',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-00000000000a'), 'America/Sao_Paulo');
  perform t_igual('e nenhum horário saiu do lugar',
    (select count(*) from public.agendamentos a join antes_ag b using (id) where a.inicio <> b.inicio or a.fim <> b.fim), 0);
end $$;

-- ===========================================================================
\echo ''
\echo '2. A dona troca para Manaus: nenhum horário muda'
-- ===========================================================================
do $$
declare r jsonb; e text;
begin
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')::text$q$);
  perform t_verdade('a função respondeu — ' || e, e not like 'ERRO:%');
  r := e::jsonb;
  perform t_verdade('a troca aconteceu — ' || r::text, (r->>'ok')::boolean and (r->>'mudou')::boolean);
  perform t_texto('de Brasília', r->>'de', 'America/Sao_Paulo');
  perform t_texto('para Manaus', r->>'fuso', 'America/Manaus');
  perform t_igual('e diz quantos horários foram mantidos: os 8', (r->>'agendamentos')::bigint, 8);
  perform t_igual('e os 2 bloqueios', (r->>'bloqueios')::bigint, 2);
  perform t_igual('as mensagens que ainda vão sair',
    (r->>'lembretes')::bigint, (select count(*) from antes_no where anda and salao_id = '58000000-0000-0000-0000-00000000000a'));
  perform t_igual('e a campanha agendada para depois de amanhã', (r->>'campanhas')::bigint, 1);

  perform t_texto('o salão agora está em Manaus',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-00000000000a'), 'America/Manaus');

  -- ⚠ O CORAÇÃO DO ARQUIVO.
  perform t_igual('TODO horário continua na mesma hora de parede — o começo',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.inicio, 'America/Manaus') = b.rot_ini), 8);
  perform t_igual('e o fim', (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.fim, 'America/Manaus') = b.rot_fim), 8);
  perform t_igual('o instante de cada um andou exatamente a uma hora de diferença entre as cidades',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and a.inicio = b.inicio + interval '1 hour' and a.fim = b.fim + interval '1 hour'), 8);
  perform t_igual('ninguém mudou de situação (confirmado, cancelado, pendente, concluído)',
    (select count(*) from public.agendamentos a join antes_ag b using (id) where a.status <> b.status), 0);
  perform t_texto('o das 23:30 continua virando a meia-noite',
    (select t_rot(inicio, 'America/Manaus') || ' → ' || to_char(fim at time zone 'America/Manaus', 'HH24:MI')
       from public.agendamentos where id = 'a5810000-0000-0000-0000-000000000006'),
    to_char(t_d(), 'YYYY-MM-DD') || ' 23:30 → 00:15');
  perform t_igual('os três colados continuam colados, sem buraco e sem choque',
    (select count(*) from public.agendamentos x join public.agendamentos y on y.inicio = x.fim
      where x.id in ('a5810000-0000-0000-0000-000000000002', 'a5810000-0000-0000-0000-000000000003')
        and y.id in ('a5810000-0000-0000-0000-000000000003', 'a5810000-0000-0000-0000-000000000004')), 2);

  perform t_igual('os bloqueios também: a folga continua sendo o dia inteiro',
    (select count(*) from public.bloqueios a join antes_bl b using (id)
      where t_rot(a.inicio, 'America/Manaus') = b.rot_ini and t_rot(a.fim, 'America/Manaus') = b.rot_fim), 2);

  perform t_igual('o salão vizinho não foi tocado',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000b' and a.inicio = b.inicio and a.fim = b.fim), 1);
end $$;

-- ===========================================================================
\echo ''
\echo '3. As mensagens: o lembrete acompanha, e ninguém é "remarcado"'
-- ===========================================================================
do $$
begin
  perform t_igual('nenhuma mensagem nova nasceu da troca',
    (select count(*) from public.notificacoes n
      where n.salao_id = '58000000-0000-0000-0000-00000000000a'
        and not exists (select 1 from antes_no b where b.id = n.id)), 0);
  perform t_igual('em especial, nenhum "seu horário foi remarcado"',
    (select count(*) from public.notificacoes where salao_id = '58000000-0000-0000-0000-00000000000a' and tipo = 'remarcado'), 0);
  perform t_igual('nenhuma mudou de situação, nem de texto',
    (select count(*) from public.notificacoes n join antes_no b using (id)
      where n.status <> b.status or n.corpo is distinct from b.corpo), 0);
  perform t_igual('as que ainda iam sair andaram junto com o horário delas',
    (select count(*) from public.notificacoes n join antes_no b using (id)
      where b.anda and b.salao_id = '58000000-0000-0000-0000-00000000000a'
        and n.quando = b.quando + interval '1 hour'),
    (select count(*) from antes_no where anda and salao_id = '58000000-0000-0000-0000-00000000000a'));
  perform t_igual('as que já deviam ter saído (a confirmação de agora) saem agora mesmo',
    (select count(*) from public.notificacoes n join antes_no b using (id)
      where not b.anda and n.quando <> b.quando), 0);
  perform t_verdade('o lembrete do horário das 09:00 continua na mesma distância dele',
    (select n.quando - a.inicio from public.notificacoes n join public.agendamentos a on a.id = n.agendamento_id
      where n.tipo = 'lembrete' and a.id = 'a5810000-0000-0000-0000-000000000002')
    = (select b.quando - g.inicio from antes_no b join antes_ag g on g.id = 'a5810000-0000-0000-0000-000000000002'
        where b.tipo = 'lembrete' and b.chave = 'lembrete:a5810000-0000-0000-0000-000000000002'));

  -- O conferidor que roda a cada 15 segundos concorda com o que ficou: não
  -- refaz, não duplica, não cancela.
  perform public.gerar_lembretes_cliente();
  perform t_igual('e o conferidor de lembretes não acha nada para refazer',
    (select count(*) from public.notificacoes
      where agendamento_id = 'a5810000-0000-0000-0000-000000000002' and tipo = 'lembrete' and status = 'pendente'), 1);

  perform t_texto('a campanha agendada para as 10:00 continua para as 10:00',
    (select to_char(c.agendada_para at time zone 'America/Manaus', 'HH24:MI') || ' · '
            || (c.agendada_para - b.agendada_para)::text
       from public.campanhas c join antes_ca b using (id) where c.id = 'ca581000-0000-0000-0000-000000000001'),
    '10:00 · 01:00:00');
  perform t_igual('a que já foi enviada (e o rascunho sem data) ficam como estavam',
    (select count(*) from public.campanhas c join antes_ca b using (id)
      where c.id <> 'ca581000-0000-0000-0000-000000000001'
        and c.agendada_para is distinct from b.agendada_para), 0);
end $$;

-- ===========================================================================
\echo ''
\echo '4. O que fica registrado, e os gatilhos de volta'
-- ===========================================================================
do $$
declare l public.fuso_mudancas%rowtype;
begin
  select * into l from public.fuso_mudancas where salao_id = '58000000-0000-0000-0000-00000000000a' order by id desc limit 1;
  perform t_verdade('a troca ficou no histórico, com quem fez',
    l.de = 'America/Sao_Paulo' and l.para = 'America/Manaus'
    and l.quem = 'a5800000-0000-0000-0000-00000000000a' and l.agendamentos = 8 and l.bloqueios = 2);
  perform t_igual('só uma linha: as tentativas recusadas não deixaram rastro',
    (select count(*) from public.fuso_mudancas where salao_id = '58000000-0000-0000-0000-00000000000a'), 1);
  perform t_igual('TODOS os gatilhos da agenda e dos bloqueios estão ligados de novo',
    (select count(*) from pg_trigger
      where tgrelid in ('public.agendamentos'::regclass, 'public.bloqueios'::regclass)
        and not tgisinternal and tgenabled <> 'O'), 0);
  perform t_verdade('e são os mesmos de antes (nenhum sumiu)',
    (select count(*) from pg_trigger where tgrelid = 'public.agendamentos'::regclass and not tgisinternal) >= 14);
  perform t_falso('o histórico não é lido pela API',
    has_table_privilege('authenticated', 'public.fuso_mudancas', 'select')
    or has_table_privilege('anon', 'public.fuso_mudancas', 'select'));
end $$;

-- ===========================================================================
\echo ''
\echo '5. Noventa segundos sem gravar horário'
-- ===========================================================================
do $$
declare e text;
begin
  perform t_verdade('a hora da troca ficou carimbada',
    (select fuso_mudou_em > now() - interval '1 minute' from public.saloes where id = '58000000-0000-0000-0000-00000000000a'));

  /* O aparelho da recepção, com a tela aberta desde antes: ele ainda escreve
     "14:00 America/Sao_Paulo", e isso agora são 13:00 em Manaus. */
  e := t_como('b5800000-0000-0000-0000-00000000000b', format($q$
    insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
    values ('58000000-0000-0000-0000-00000000000a', 'c5800000-0000-0000-0000-0000000000a2',
            '95800000-0000-0000-0000-0000000000a2', '%s 14:00:00 America/Sao_Paulo', '%s 15:00:00 America/Sao_Paulo',
            'confirmado', 'recepcao', 80) returning id::text$q$, t_d() + 5, t_d() + 5));
  perform t_verdade('a recepção não consegue marcar com o relógio antigo — ' || e,
    e like 'ERRO: O relógio do salão acabou de ser ajustado%');
  perform t_igual('e nada foi gravado',
    (select count(*) from public.agendamentos where salao_id = '58000000-0000-0000-0000-00000000000a'), 8);

  e := t_como('b5800000-0000-0000-0000-00000000000b', format($q$
    update public.agendamentos set inicio = '%s 16:00:00 America/Sao_Paulo', fim = '%s 17:00:00 America/Sao_Paulo'
     where id = 'a5810000-0000-0000-0000-000000000004' returning id::text$q$, t_d(), t_d()));
  perform t_verdade('nem remarcar', e like 'ERRO: O relógio do salão acabou de ser ajustado%');

  e := t_como('a5800000-0000-0000-0000-00000000000a', format($q$
    insert into public.bloqueios (salao_id, profissional_id, inicio, fim, motivo)
    values ('58000000-0000-0000-0000-00000000000a', '95800000-0000-0000-0000-0000000000a2',
            '%s 08:00:00 America/Sao_Paulo', '%s 09:00:00 America/Sao_Paulo', 'Médico') returning id::text$q$,
    t_d() + 5, t_d() + 5));
  perform t_verdade('nem bloquear', e like 'ERRO: O relógio do salão acabou de ser ajustado%');

  -- O que NÃO é horário continua: cancelar não espera.
  e := t_como('b5800000-0000-0000-0000-00000000000b', $q$
    update public.agendamentos set status = 'cancelado' where id = 'a5810000-0000-0000-0000-000000000004' returning status$q$);
  perform t_texto('cancelar continua funcionando no meio da trava', e, 'cancelado');

  -- E o vizinho nem fica sabendo.
  e := t_como('e5800000-0000-0000-0000-00000000000e', format($q$
    insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
    values ('58000000-0000-0000-0000-00000000000b', 'c5800000-0000-0000-0000-0000000000b1',
            '95800000-0000-0000-0000-0000000000b1', '%s 14:00:00 America/Sao_Paulo', '%s 15:00:00 America/Sao_Paulo',
            'confirmado', 'recepcao', 80) returning 'gravou'$q$, t_d() + 5, t_d() + 5));
  perform t_texto('o salão vizinho marca normalmente', e, 'gravou');

  -- A dona não desliga a trava escrevendo no campo.
  e := t_como('a5800000-0000-0000-0000-00000000000a', $q$
    update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000a' returning 'ok'$q$);
  perform t_verdade('quem é do salão não apaga o carimbo pela API',
    (select fuso_mudou_em is not null from public.saloes where id = '58000000-0000-0000-0000-00000000000a'));
end $$;

-- Passados os 90 segundos (o suporte pode adiantar, pelo SQL Editor).
update public.saloes set fuso_mudou_em = now() - interval '2 minutes'
 where id = '58000000-0000-0000-0000-00000000000a';
do $$
declare e text;
begin
  e := t_como('b5800000-0000-0000-0000-00000000000b', format($q$
    insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
    values ('a5810000-0000-0000-0000-000000000099', '58000000-0000-0000-0000-00000000000a',
            'c5800000-0000-0000-0000-0000000000a2', '95800000-0000-0000-0000-0000000000a2',
            '%s 14:00:00 America/Manaus', '%s 15:00:00 America/Manaus', 'confirmado', 'recepcao', 80)
    returning 'gravou'$q$, t_d() + 5, t_d() + 5));
  perform t_texto('depois do minuto e meio, a recepção marca de novo — já no relógio de Manaus', e, 'gravou');
end $$;

-- ===========================================================================
\echo ''
\echo '6. Ida e volta: cada instante volta exatamente para onde estava'
-- ===========================================================================
do $$
declare r jsonb; e text;
begin
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Sao_Paulo')::text$q$);
  perform t_verdade('a função respondeu — ' || e, e not like 'ERRO:%');
  r := e::jsonb;
  perform t_verdade('voltou para Brasília — ' || r::text, (r->>'mudou')::boolean);
  perform t_igual('os 8 de antes estão no MESMO instante de quando tudo começou',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a' and a.inicio = b.inicio and a.fim = b.fim), 8);
  perform t_igual('o prazo do sinal também',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.sinal_ate is distinct from b.sinal_ate), 0);
  perform t_igual('os bloqueios também',
    (select count(*) from public.bloqueios a join antes_bl b using (id) where a.inicio = b.inicio and a.fim = b.fim), 2);
  perform t_texto('e o que a recepção marcou em Manaus continua às 14:00',
    (select t_rot(inicio, 'America/Sao_Paulo') from public.agendamentos where id = 'a5810000-0000-0000-0000-000000000099'),
    to_char(t_d() + 5, 'YYYY-MM-DD') || ' 14:00');
  perform t_texto('trocar para o fuso que já é não faz nada',
    t_como('a5800000-0000-0000-0000-00000000000a',
      $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Sao_Paulo')->>'mudou'$q$), 'false');
  perform t_igual('e não vira linha no histórico',
    (select count(*) from public.fuso_mudancas where salao_id = '58000000-0000-0000-0000-00000000000a'), 2);
end $$;
update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000a';

-- ===========================================================================
\echo ''
\echo '7. Para o leste, e por duas horas'
-- ===========================================================================
do $$
declare r jsonb; e text;
begin
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Noronha')::text$q$);
  perform t_verdade('a função respondeu — ' || e, e not like 'ERRO:%');
  r := e::jsonb;
  perform t_igual('Fernando de Noronha (uma hora na frente): todo horário na mesma hora de parede',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.inicio, 'America/Noronha') = b.rot_ini and t_rot(a.fim, 'America/Noronha') = b.rot_fim), 8);
  perform t_igual('os instantes andaram uma hora para TRÁS',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a' and a.inicio = b.inicio - interval '1 hour'), 8);
  /* O prazo do sinal é relógio de verdade e não anda. Mas o horário veio
     uma hora para cá: sem o teto, o prazo venceria com a cliente já sentada. */
  perform t_verdade('o prazo do sinal não passa do começo do horário',
    (select sinal_ate = inicio from public.agendamentos where id = 'a5810000-0000-0000-0000-000000000007'));
end $$;
update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000a';

do $$
declare r jsonb; e text;
begin
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Rio_Branco')::text$q$);
  perform t_verdade('a função respondeu — ' || e, e not like 'ERRO:%');
  r := e::jsonb;
  perform t_igual('Acre (duas horas atrás de Brasília): todo horário na mesma hora de parede',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.inicio, 'America/Rio_Branco') = b.rot_ini and t_rot(a.fim, 'America/Rio_Branco') = b.rot_fim), 8);
  perform t_igual('a duas horas de Brasília',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a' and a.inicio = b.inicio + interval '2 hours'), 8);
  perform t_igual('e a duração de cada um é a mesma do começo',
    (select count(*) from public.agendamentos a join antes_ag b using (id) where a.fim - a.inicio <> b.fim - b.inicio), 0);
end $$;
update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000a';

-- ===========================================================================
\echo ''
\echo '8. Quem pode trocar'
-- ===========================================================================
do $$
declare e text; v_acesso uuid;
begin
  e := t_como(null, $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')::text$q$);
  perform t_verdade('visitante sem login nem chama — ' || e, e like 'ERRO: permission denied%');
  e := t_como('b5800000-0000-0000-0000-00000000000b', $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')::text$q$);
  perform t_verdade('a recepção não troca', e like 'ERRO: Só quem administra o salão troca o fuso horário%');
  e := t_como('d5800000-0000-0000-0000-00000000000d', $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')::text$q$);
  perform t_verdade('quem atende não troca', e like 'ERRO: Só quem administra%');
  e := t_como('e5800000-0000-0000-0000-00000000000e', $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')::text$q$);
  perform t_verdade('a dona do salão vizinho não troca o fuso deste', e like 'ERRO: Só quem administra%');
  perform t_texto('nada disso mexeu no fuso',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-00000000000a'), 'America/Rio_Branco');

  -- A recepção tentando direto na tabela: o RLS não deixa nem a linha passar.
  e := t_como('b5800000-0000-0000-0000-00000000000b', $q$
    with u as (update public.saloes set fuso = 'America/Manaus' where id = '58000000-0000-0000-0000-00000000000a' returning 1)
    select count(*)::text from u$q$);
  perform t_texto('direto na tabela, a recepção não altera linha nenhuma', e, '0');

  -- ⚠ A dona direto na tabela (é o caminho do cadastro, e o de qualquer
  -- chamada na API): troca E move, porque quem move é o gatilho.
  e := t_como('a5800000-0000-0000-0000-00000000000a', $q$
    with u as (update public.saloes set fuso = 'America/Cuiaba' where id = '58000000-0000-0000-0000-00000000000a' returning 1)
    select count(*)::text from u$q$);
  perform t_texto('a dona, direto na tabela, troca', e, '1');
  perform t_igual('e os horários foram junto do mesmo jeito: mesma hora de parede em Cuiabá',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.inicio, 'America/Cuiaba') = b.rot_ini and t_rot(a.fim, 'America/Cuiaba') = b.rot_fim), 8);

  update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000a';

  /* A plataforma atendendo um pedido ("troca o fuso para mim"): vale a regra
     do modo suporte, como para qualquer outra alteração no salão de alguém —
     sem "Liberar edição" é só leitura, e com ela fica registrado. */
  e := t_como('f5800000-0000-0000-0000-00000000000f', $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')->>'fuso'$q$);
  perform t_verdade('a plataforma, sem liberar a edição, não troca — ' || e, e like 'ERRO: Modo suporte: só leitura%');
  perform t_texto('e o fuso fica onde estava',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-00000000000a'), 'America/Cuiaba');
  perform t_igual('com os horários no lugar (a tentativa voltou inteira)',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.inicio, 'America/Cuiaba') = b.rot_ini), 8);

  v_acesso := (t_como('f5800000-0000-0000-0000-00000000000f',
    $q$select public.iniciar_suporte('58000000-0000-0000-0000-00000000000a')->>'acesso'$q$))::uuid;
  perform t_como('f5800000-0000-0000-0000-00000000000f',
    format($q$select public.liberar_edicao_suporte('%s')::text$q$, v_acesso));
  e := t_como('f5800000-0000-0000-0000-00000000000f', $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Manaus')->>'fuso'$q$);
  perform t_texto('com "Liberar edição", a plataforma troca pelo salão', e, 'America/Manaus');
  perform t_igual('e os horários continuam na mesma hora de parede',
    (select count(*) from public.agendamentos a join antes_ag b using (id)
      where a.salao_id = '58000000-0000-0000-0000-00000000000a'
        and t_rot(a.inicio, 'America/Manaus') = b.rot_ini and t_rot(a.fim, 'America/Manaus') = b.rot_fim), 8);
  perform t_verdade('a troca ficou no registro do suporte: o fuso de antes e o de depois',
    exists (select 1 from public.suporte_alteracoes x
             where x.acesso_id = v_acesso and x.tabela = 'saloes'
               and x.antes->>'fuso' = 'America/Cuiaba' and x.depois->>'fuso' = 'America/Manaus'));
  perform t_igual('e só ela: mover os horários não vira nove "alterações" no registro',
    (select count(*) from public.suporte_alteracoes x
      where x.acesso_id = v_acesso and x.tabela in ('agendamentos', 'bloqueios')), 0);
  perform t_como('f5800000-0000-0000-0000-00000000000f',
    format($q$select public.encerrar_suporte('%s')::text$q$, v_acesso));
end $$;

-- ===========================================================================
\echo ''
\echo '8b. Salão recém-criado: o cadastro ajusta o fuso sem travar o primeiro horário'
-- ===========================================================================
insert into public.saloes (id, slug, nome, status) values
  ('58000000-0000-0000-0000-0000000000e1', 'fuso-novo', 'Acabou de Nascer', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values ('58000000-0000-0000-0000-0000000000e1', 'time', 'ativa');
insert into public.vinculos (perfil_id, salao_id, papel) values
  ('e5800000-0000-0000-0000-00000000000e', '58000000-0000-0000-0000-0000000000e1', 'dono');
insert into public.profissionais (id, salao_id, nome, ativo) values
  ('95800000-0000-0000-0000-0000000000e1', '58000000-0000-0000-0000-0000000000e1', 'Eva', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '95800000-0000-0000-0000-0000000000e1', d, '08:00', '20:00' from generate_series(0, 6) d;
insert into public.clientes (id, salao_id, nome, telefone) values
  ('c5800000-0000-0000-0000-0000000000e1', '58000000-0000-0000-0000-0000000000e1', 'Primeira Cliente', '92958001009');
do $$
declare e text;
begin
  e := t_como('e5800000-0000-0000-0000-00000000000e', $q$
    with u as (update public.saloes set fuso = 'America/Manaus' where id = '58000000-0000-0000-0000-0000000000e1' returning fuso)
    select fuso from u$q$);
  perform t_texto('o cadastro grava o fuso do aparelho', e, 'America/Manaus');
  perform t_verdade('sem carimbo: não há tela antiga aberta num salão de um minuto de vida',
    (select fuso_mudou_em is null from public.saloes where id = '58000000-0000-0000-0000-0000000000e1'));
  e := t_como('e5800000-0000-0000-0000-00000000000e', format($q$
    insert into public.agendamentos (salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto)
    values ('58000000-0000-0000-0000-0000000000e1', 'c5800000-0000-0000-0000-0000000000e1',
            '95800000-0000-0000-0000-0000000000e1', '%s 10:00:00 America/Manaus', '%s 11:00:00 America/Manaus',
            'confirmado', 'recepcao', 50) returning 'gravou'$q$, t_d(), t_d()));
  perform t_texto('e a dona marca o primeiro horário na hora', e, 'gravou');
end $$;

-- ===========================================================================
\echo ''
\echo '9. Fuso antigo inválido (gravado antes de existir a conferência)'
-- ===========================================================================
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto) values
  ('a5830000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-00000000000c',
   'c5800000-0000-0000-0000-0000000000c1', '95800000-0000-0000-0000-0000000000c1',
   t_em(:'d'::date, '09:00'), t_em(:'d'::date, '10:00'), 'confirmado', 'recepcao', 80);
alter table public.saloes disable trigger tg_salao_fuso;
alter table public.saloes disable trigger tg_salao_fuso_mover;
update public.saloes set fuso = 'Lixo/Antigo' where id = '58000000-0000-0000-0000-00000000000c';
alter table public.saloes enable trigger tg_salao_fuso;
alter table public.saloes enable trigger tg_salao_fuso_mover;
do $$
declare e text; v_ini timestamptz;
begin
  select inicio into v_ini from public.agendamentos where id = 'a5830000-0000-0000-0000-000000000001';
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000c', 'America/Sao_Paulo')->>'fuso'$q$);
  perform t_texto('o salão com lixo no fuso consegue consertar', e, 'America/Sao_Paulo');
  perform t_verdade('sem mexer em horário nenhum: não havia hora de parede para preservar',
    (select inicio = v_ini from public.agendamentos where id = 'a5830000-0000-0000-0000-000000000001'));
  perform t_verdade('e o histórico diz o porquê',
    (select obs like '%nenhum horário foi movido%' from public.fuso_mudancas
      where salao_id = '58000000-0000-0000-0000-00000000000c' order by id desc limit 1));
end $$;
update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000c';

-- ===========================================================================
\echo ''
\echo '10. Se dois horários colidissem no fuso novo, nada muda'
-- ===========================================================================
/* A única forma de dois horários do mesmo profissional, que não se tocam,
   caírem na mesma hora de parede é a virada do horário de verão. Em São
   Paulo, na noite de 17 para 18 de fevereiro de 2018, as 23:00 aconteceram
   DUAS vezes. A Bahia não tinha horário de verão: lá, as duas são a mesma. */
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, origem, valor_previsto) values
  ('a5830000-0000-0000-0000-0000000000f1', '58000000-0000-0000-0000-00000000000c',
   'c5800000-0000-0000-0000-0000000000c1', '95800000-0000-0000-0000-0000000000c1',
   '2018-02-18 01:00:00+00', '2018-02-18 01:30:00+00', 'concluido', 'recepcao', 50),
  ('a5830000-0000-0000-0000-0000000000f2', '58000000-0000-0000-0000-00000000000c',
   'c5800000-0000-0000-0000-0000000000c1', '95800000-0000-0000-0000-0000000000c1',
   '2018-02-18 02:00:00+00', '2018-02-18 02:30:00+00', 'concluido', 'recepcao', 50);
create temporary table antes_c as
  select id, inicio, fim from public.agendamentos where salao_id = '58000000-0000-0000-0000-00000000000c';
do $$
declare e text;
begin
  perform t_texto('os dois dizem 23:00 em São Paulo, e não se tocam',
    (select string_agg(to_char(inicio at time zone 'America/Sao_Paulo', 'HH24:MI'), ' e ' order by inicio)
       from public.agendamentos where id in ('a5830000-0000-0000-0000-0000000000f1', 'a5830000-0000-0000-0000-0000000000f2')),
    '23:00 e 23:00');
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000c', 'America/Bahia')::text$q$);
  perform t_verdade('a troca é recusada, dizendo que nada foi alterado — ' || e,
    e like 'ERRO: Não deu para trocar o fuso: dois horários do mesmo profissional%Nada foi alterado%');
  perform t_texto('o fuso ficou onde estava',
    (select fuso from public.saloes where id = '58000000-0000-0000-0000-00000000000c'), 'America/Sao_Paulo');
  perform t_igual('TODOS os horários estão no mesmo instante de antes da tentativa',
    (select count(*) from public.agendamentos a join antes_c b using (id) where a.inicio = b.inicio and a.fim = b.fim),
    (select count(*) from antes_c));
  perform t_igual('os gatilhos da agenda não ficaram desligados pelo caminho',
    (select count(*) from pg_trigger
      where tgrelid in ('public.agendamentos'::regclass, 'public.bloqueios'::regclass)
        and not tgisinternal and tgenabled <> 'O'), 0);
  perform t_igual('e a tentativa não entrou no histórico',
    (select count(*) from public.fuso_mudancas where salao_id = '58000000-0000-0000-0000-00000000000c' and para = 'America/Bahia'), 0);
  perform t_verdade('nem carimbou a trava: a recepção continua marcando',
    (select fuso_mudou_em is null from public.saloes where id = '58000000-0000-0000-0000-00000000000c'));
end $$;

-- ===========================================================================
\echo ''
\echo '11. Um gatilho que já estava desligado continua desligado'
-- ===========================================================================
alter table public.agendamentos disable trigger tg_pacote_avisos;
do $$
declare e text;
begin
  update public.saloes set fuso_mudou_em = null where id = '58000000-0000-0000-0000-00000000000a';
  e := t_como('a5800000-0000-0000-0000-00000000000a',
    $q$select public.mudar_fuso('58000000-0000-0000-0000-00000000000a', 'America/Sao_Paulo')->>'fuso'$q$);
  perform t_texto('a troca acontece', e, 'America/Sao_Paulo');
  perform t_texto('o que o suporte tinha desligado de propósito não é religado por tabela',
    (select tgenabled::text from pg_trigger where tgrelid = 'public.agendamentos'::regclass and tgname = 'tg_pacote_avisos'), 'D');
  perform t_igual('e só ele',
    (select count(*) from pg_trigger
      where tgrelid in ('public.agendamentos'::regclass, 'public.bloqueios'::regclass)
        and not tgisinternal and tgenabled <> 'O'), 1);
end $$;
alter table public.agendamentos enable trigger tg_pacote_avisos;
