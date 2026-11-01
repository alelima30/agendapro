-- ===========================================================================
-- AgendaPro — a cliente se cadastra pelo link, sem agendar (48_cadastro_link)
--
--   1. sem login não há o que cadastrar; o anon nem chama;
--   2. conta nova sem ficha: a ficha NASCE no salão, marcada "pelo link",
--      com nome, WhatsApp (sem o 55) e e-mail da conta;
--   3. chamar de novo não duplica;
--   4. a ficha que o salão já tinha (mesmo WhatsApp, mesmo nome) é LIGADA,
--      sem marca e sem ficha nova;
--   5. mesmo WhatsApp com outro nome: não duplica, e diz por quê;
--   6. conta sem telefone (o número já era de outra conta): não cria;
--   7. o teto do plano: a ficha não nasce e a conta segue, sem erro;
--   8. salão suspenso: nada;
--   9. o caminho de sempre (`ligar_minha_ficha`) continua sem criar ficha.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('a4800000-0000-0000-0000-00000000000a', 'dona@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000001', 'lu@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000002', 'mari@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000003', 'filha@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000004', 'semtel@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000005', 'cheio@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000006', 'outra@cadlink.com');
insert into public.perfis (id, nome, telefone, email) values
  ('a4800000-0000-0000-0000-00000000000a', 'Dona',          '+5511948000000', 'dona@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000001', 'Luana Souza',   '+5511948000001', 'lu@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000002', 'Mariana Lopes', '+5511948000002', 'mari@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000003', 'Beatriz Lopes', '+5511948000003', 'filha@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000004', 'Sem Telefone',  null,             'semtel@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000005', 'Carla Cheia',   '+5511948000005', 'cheio@cadlink.com'),
  ('c4800000-0000-0000-0000-000000000006', 'Outra Pessoa',  '+5511948000006', 'outra@cadlink.com')
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone, email = excluded.email;

insert into public.saloes (id, slug, nome, tipo, fuso) values
  ('54800000-0000-0000-0000-00000000000a', 'cadlink-ana',   'Studio da Ana',  'salao', 'America/Sao_Paulo'),
  ('54800000-0000-0000-0000-00000000000b', 'cadlink-cheio', 'Salão Lotado',   'salao', 'America/Sao_Paulo'),
  ('54800000-0000-0000-0000-00000000000c', 'cadlink-susp',  'Salão Suspenso', 'salao', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status, vence_em, trial_ate) values
  ('54800000-0000-0000-0000-00000000000a', 'individual', 'ativa', current_date + 20, null),
  ('54800000-0000-0000-0000-00000000000b', 'gratuito',   'ativa', null, null),
  ('54800000-0000-0000-0000-00000000000c', 'individual', 'ativa', current_date + 20, null);
update public.saloes set status = 'suspenso' where id = '54800000-0000-0000-0000-00000000000c';
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('a4800000-0000-0000-0000-00000000000a', '54800000-0000-0000-0000-00000000000a', 'dono', 'ativo');
-- As fichas que o salão já tinha, feitas no balcão: a Mariana (gravada com
-- o 55, como as antigas) e a Joana, mãe da Beatriz — a filha criou a conta
-- com o WhatsApp que está na ficha da mãe.
insert into public.clientes (salao_id, nome, telefone) values
  ('54800000-0000-0000-0000-00000000000a', 'Mariana', '5511948000002'),
  ('54800000-0000-0000-0000-00000000000a', 'Joana Lopes', '11948000003');
-- O Salão Lotado já tem as 30 do plano grátis.
insert into public.clientes (salao_id, nome, telefone)
  select '54800000-0000-0000-0000-00000000000b', 'Cliente ' || g, '119480100' || lpad(g::text, 2, '0')
    from generate_series(1, 30) g;
grant usage on schema auth to anon, authenticated;

create or replace function t_como(p_quem uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_quem::text, ''), false);
end $$;

\echo ''
\echo '1. Sem login, nada; o anon nem chama'
select t_como(null);
select t_verdade('sem login devolve nada',
  public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000a') is null);
select t_verdade('o anon não executa',
  not has_function_privilege('anon', 'public.cadastrar_minha_ficha(uuid)', 'execute'));
select t_verdade('quem está logado executa',
  has_function_privilege('authenticated', 'public.cadastrar_minha_ficha(uuid)', 'execute'));

\echo ''
\echo '2. Conta nova sem ficha: a ficha nasce, marcada "pelo link"'
select t_como('c4800000-0000-0000-0000-000000000001');
set role authenticated;
select public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000a') as r1 \gset
reset role;
select t_verdade('criou a ficha', (:'r1'::jsonb->>'criada')::boolean);
select t_verdade('e devolve a ficha', :'r1'::jsonb->>'ficha' is not null);
select t_texto('com nome, WhatsApp sem o 55, e-mail e a marca',
  (select nome || ' | ' || telefone || ' | ' || email || ' | ' || pelo_link
     from public.clientes where id = (:'r1'::jsonb->>'ficha')::uuid),
  'Luana Souza | 11948000001 | lu@cadlink.com | true');
select t_verdade('ligada à conta dela',
  (select perfil_id from public.clientes where id = (:'r1'::jsonb->>'ficha')::uuid)
    = 'c4800000-0000-0000-0000-000000000001');
select t_texto('devolve os dados da conta como o ligar_minha_ficha',
  :'r1'::jsonb->>'nome', 'Luana Souza');

\echo ''
\echo '3. De novo: não duplica'
set role authenticated;
select public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000a') as r2 \gset
reset role;
select t_falso('a segunda vez não cria', (:'r2'::jsonb->>'criada')::boolean);
select t_texto('e devolve a mesma ficha', :'r2'::jsonb->>'ficha', :'r1'::jsonb->>'ficha');
select t_igual('uma ficha só dela',
  (select count(*)::int from public.clientes
    where salao_id = '54800000-0000-0000-0000-00000000000a' and perfil_id = 'c4800000-0000-0000-0000-000000000001'), 1);

\echo ''
\echo '4. A ficha do balcão (mesmo WhatsApp, mesmo nome) é ligada'
select t_como('c4800000-0000-0000-0000-000000000002');
set role authenticated;
select public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000a') as r3 \gset
reset role;
select t_falso('não cria', (:'r3'::jsonb->>'criada')::boolean);
select t_verdade('liga a ficha que o salão tinha',
  (select perfil_id = 'c4800000-0000-0000-0000-000000000002' and nome = 'Mariana' and not pelo_link
     from public.clientes where id = (:'r3'::jsonb->>'ficha')::uuid));
select t_igual('e o salão continua com uma ficha nesse WhatsApp',
  (select count(*)::int from public.clientes
    where salao_id = '54800000-0000-0000-0000-00000000000a'
      and public.telefone_nacional(telefone) = '11948000002'), 1);

\echo ''
\echo '5. Mesmo WhatsApp, outro nome: não duplica, e diz por quê'
select t_como('c4800000-0000-0000-0000-000000000003');
set role authenticated;
select public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000a') as r4 \gset
reset role;
select t_verdade('sem ficha', :'r4'::jsonb->>'ficha' is null);
select t_texto('o motivo', :'r4'::jsonb->>'motivo', 'telefone_de_outra_ficha');
select t_texto('a ficha da mãe fica como estava, sem conta',
  (select nome || ' | ' || coalesce(perfil_id::text, 'sem conta') from public.clientes
    where salao_id = '54800000-0000-0000-0000-00000000000a'
      and public.telefone_nacional(telefone) = '11948000003'), 'Joana Lopes | sem conta');

\echo ''
\echo '6. Conta sem telefone: não cria'
select t_como('c4800000-0000-0000-0000-000000000004');
set role authenticated;
select public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000a') as r5 \gset
reset role;
select t_verdade('sem ficha', :'r5'::jsonb->>'ficha' is null);
select t_texto('o motivo', :'r5'::jsonb->>'motivo', 'sem_telefone');

\echo ''
\echo '7. O teto do plano: a ficha não nasce, e não dá erro'
select t_como('c4800000-0000-0000-0000-000000000005');
set role authenticated;
select public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000b') as r6 \gset
reset role;
select t_verdade('sem ficha', :'r6'::jsonb->>'ficha' is null);
select t_texto('o motivo', :'r6'::jsonb->>'motivo', 'nao_coube');
select t_igual('o salão continua com as 30',
  (select count(*)::int from public.clientes where salao_id = '54800000-0000-0000-0000-00000000000b'), 30);

\echo ''
\echo '8. Salão suspenso: nada'
select t_como('c4800000-0000-0000-0000-000000000006');
set role authenticated;
select t_verdade('devolve nada',
  public.cadastrar_minha_ficha('54800000-0000-0000-0000-00000000000c') is null);
reset role;
select t_igual('e não criou ficha',
  (select count(*)::int from public.clientes where salao_id = '54800000-0000-0000-0000-00000000000c'), 0);

\echo ''
\echo '9. O ligar_minha_ficha continua só ligando'
set role authenticated;
select public.ligar_minha_ficha('54800000-0000-0000-0000-00000000000a') as r7 \gset
reset role;
select t_verdade('sem ficha que bata, não cria', :'r7'::jsonb->>'ficha' is null);
select t_igual('a Outra Pessoa não ganhou ficha',
  (select count(*)::int from public.clientes
    where salao_id = '54800000-0000-0000-0000-00000000000a' and perfil_id = 'c4800000-0000-0000-0000-000000000006'), 0);
select t_como(null);
