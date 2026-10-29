-- ===========================================================================
-- AgendaPro — o que só a equipe sabe (41_ficha_equipe.sql)
--
-- "Coloração loiro perolado: quais as tintas e como lavar o cabelo" e "a
-- Maria não gosta de conversar, dá problema na hora do pagamento".
--
--   1. o lembrete grava limpo (marcas sem repetir, texto sem espaço sobrando);
--   2. a equipe inteira lê e escreve: dono e profissional;
--   3. a CLIENTE NÃO LÊ — nem logada, que lê a própria ficha; nem anônima;
--   4. o salão vizinho não lê, e ninguém aponta lembrete para ficha de
--      outro salão;
--   5. o como fazer do serviço é da equipe: a vitrine (o link) não leva;
--   6. apagar a cliente leva o lembrete junto; o modo suporte trava.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('a4100000-0000-0000-0000-00000000000a'),  -- Ana   — dona do salão A
  ('b4100000-0000-0000-0000-00000000000b'),  -- Bia   — profissional no A
  ('c4100000-0000-0000-0000-00000000000c'),  -- Maria — cliente do A e do B
  ('e4100000-0000-0000-0000-00000000000e');  -- Zé    — dono do salão B

insert into public.saloes (id, slug, nome, status) values
  ('54100000-0000-0000-0000-00000000000a', 'ficha-a', 'Salão A', 'ativo'),
  ('54100000-0000-0000-0000-00000000000b', 'ficha-b', 'Barbearia B', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values
  ('54100000-0000-0000-0000-00000000000a', 'time', 'ativa'),
  ('54100000-0000-0000-0000-00000000000b', 'time', 'ativa');

insert into public.perfis (id, nome, telefone) values
  ('a4100000-0000-0000-0000-00000000000a', 'Ana',   '+5511941000001'),
  ('b4100000-0000-0000-0000-00000000000b', 'Bia',   '+5511941000002'),
  ('c4100000-0000-0000-0000-00000000000c', 'Maria', '+5511941000003'),
  ('e4100000-0000-0000-0000-00000000000e', 'Zé',    '+5511941000005')
on conflict (id) do update set nome = excluded.nome, telefone = excluded.telefone;

insert into public.vinculos (perfil_id, salao_id, papel) values
  ('a4100000-0000-0000-0000-00000000000a', '54100000-0000-0000-0000-00000000000a', 'dono'),
  ('b4100000-0000-0000-0000-00000000000b', '54100000-0000-0000-0000-00000000000a', 'profissional'),
  ('c4100000-0000-0000-0000-00000000000c', '54100000-0000-0000-0000-00000000000a', 'cliente'),
  ('c4100000-0000-0000-0000-00000000000c', '54100000-0000-0000-0000-00000000000b', 'cliente'),
  ('e4100000-0000-0000-0000-00000000000e', '54100000-0000-0000-0000-00000000000b', 'dono');

insert into public.profissionais (id, salao_id, perfil_id, nome) values
  ('94100000-0000-0000-0000-00000000000a', '54100000-0000-0000-0000-00000000000a',
   'a4100000-0000-0000-0000-00000000000a', 'Ana'),
  ('94100000-0000-0000-0000-00000000000b', '54100000-0000-0000-0000-00000000000a',
   'b4100000-0000-0000-0000-00000000000b', 'Bia');

insert into public.clientes (id, salao_id, perfil_id, nome, telefone, obs) values
  ('c4110000-0000-0000-0000-00000000000a', '54100000-0000-0000-0000-00000000000a',
   'c4100000-0000-0000-0000-00000000000c', 'Maria', '5511941000003', 'Gosta de café'),
  ('c4110000-0000-0000-0000-00000000000b', '54100000-0000-0000-0000-00000000000b',
   'c4100000-0000-0000-0000-00000000000c', 'Maria', '5511941000003', null);

insert into public.servicos (id, salao_id, nome, duracao_min, preco, procedimento) values
  ('54200000-0000-0000-0000-00000000000a', '54100000-0000-0000-0000-00000000000a',
   'Coloração loiro perolado', 120, 350,
   'Tinta 9.1 + 0.11, ox 20 vol, 35 min. Lavar com shampoo sem sulfato.');

grant usage on schema auth to anon, authenticated;

\echo ''
\echo '1 e 2. A equipe grava e lê'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'a4100000-0000-0000-0000-00000000000a';
  insert into public.clientes_lembretes (salao_id, cliente_id, marcas, texto) values
    ('54100000-0000-0000-0000-00000000000a', 'c4110000-0000-0000-0000-00000000000a',
     array['Prefere não conversar', '  ', 'Atenção no pagamento', 'Prefere não conversar '],
     '   Paga só no Pix, e pede para dividir.  ');
  do $$ begin
    perform t_texto('a dona grava: as marcas sem a vazia e sem a repetida, na ordem',
      (select array_to_string(marcas, ' | ') from public.clientes_lembretes),
      'Prefere não conversar | Atenção no pagamento');
    perform t_texto('e o texto sem espaço sobrando',
      (select texto from public.clientes_lembretes), 'Paga só no Pix, e pede para dividir.');
    perform t_verdade('um lembrete por cliente: o segundo é recusado',
      recusado($q$insert into public.clientes_lembretes (salao_id, cliente_id, marcas)
                 values ('54100000-0000-0000-0000-00000000000a',
                         'c4110000-0000-0000-0000-00000000000a', array['Costuma atrasar'])$q$));
  end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'b4100000-0000-0000-0000-00000000000b';
  do $$ begin
    perform t_igual('a profissional que vai atender lê o lembrete',
      (select count(*) from public.clientes_lembretes), 1);
    update public.clientes_lembretes set marcas = marcas || array['Costuma atrasar'];
    perform t_igual('e acrescenta uma marca',
      (select cardinality(marcas) from public.clientes_lembretes)::bigint, 3);
    perform t_texto('lê o como fazer do serviço',
      (select procedimento from public.servicos where id = '54200000-0000-0000-0000-00000000000a'),
      'Tinta 9.1 + 0.11, ox 20 vol, 35 min. Lavar com shampoo sem sulfato.');
    perform t_texto('não aponta lembrete para a ficha da Maria no salão B',
      erro_de($q$insert into public.clientes_lembretes (salao_id, cliente_id, marcas)
                 values ('54100000-0000-0000-0000-00000000000a',
                         'c4110000-0000-0000-0000-00000000000b', array['x'])$q$),
      'Esta cliente não é deste salão.');
  end $$;
commit;

\echo ''
\echo '3. A cliente não lê'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'c4100000-0000-0000-0000-00000000000c';
  do $$ declare n bigint; begin
    perform t_igual('logada, a Maria lê a própria ficha (é dela, a LGPD manda)',
      (select count(*) from public.clientes), 2);
    perform t_igual('mas o lembrete da equipe não aparece para ela',
      (select count(*) from public.clientes_lembretes), 0);
    perform t_verdade('nem consegue criar um',
      recusado($q$insert into public.clientes_lembretes (salao_id, cliente_id, marcas)
                 values ('54100000-0000-0000-0000-00000000000a',
                         'c4110000-0000-0000-0000-00000000000a', array['ok'])$q$));
    delete from public.clientes_lembretes;
    get diagnostics n = row_count;
    perform t_igual('nem apagar o que a equipe escreveu', n, 0);
    perform t_igual('e não lê o como fazer dos serviços',
      (select count(*) from public.servicos), 0);
  end $$;
commit;

begin;
  set local role anon;
  do $$ begin
    perform t_verdade('anônimo (o link sem login) nem chega na tabela',
      recusado('select 1 from public.clientes_lembretes'));
  end $$;
commit;

\echo ''
\echo '4. O salão vizinho'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'e4100000-0000-0000-0000-00000000000e';
  do $$ begin
    perform t_igual('o dono do salão B não vê o lembrete do A',
      (select count(*) from public.clientes_lembretes), 0);
    perform t_verdade('não grava no salão A',
      recusado($q$insert into public.clientes_lembretes (salao_id, cliente_id, marcas)
                 values ('54100000-0000-0000-0000-00000000000a',
                         'c4110000-0000-0000-0000-00000000000a', array['x'])$q$));
    perform t_texto('nem aponta a ficha do A como se fosse do B',
      erro_de($q$insert into public.clientes_lembretes (salao_id, cliente_id, marcas)
                 values ('54100000-0000-0000-0000-00000000000b',
                         'c4110000-0000-0000-0000-00000000000a', array['x'])$q$),
      'Esta cliente não é deste salão.');
  end $$;
commit;

\echo ''
\echo '5. O como fazer não sai pelo link'
do $$
declare v text := public.vitrine('ficha-a')::text;
begin
  perform t_verdade('a vitrine traz o serviço', v like '%Coloração loiro perolado%');
  perform t_falso('mas não o como fazer', v like '%Tinta 9.1%' or v like '%procedimento%');
  perform t_verdade('e o como fazer tem limite de tamanho',
    recusado($q$update public.servicos set procedimento = repeat('a', 4001)
               where id = '54200000-0000-0000-0000-00000000000a'$q$));
end $$;

\echo ''
\echo '6. Apagar a cliente, e o modo suporte'
do $$ begin
  perform t_verdade('a trava do modo suporte está na tabela',
    exists (select 1 from pg_trigger where tgname = 'zz_suporte'
              and tgrelid = 'public.clientes_lembretes'::regclass));
  delete from public.clientes where id = 'c4110000-0000-0000-0000-00000000000a';
  perform t_igual('apagar a ficha leva o lembrete junto',
    (select count(*) from public.clientes_lembretes), 0);
end $$;
