-- ===========================================================================
-- AgendaPro — os defeitos de banco que o caça-bug achou, e que não voltam
--
--   1. O catálogo (telefone e comissão da equipe) não abre para quem só
--      "virou cliente" do salão.
--   2. A cliente não escreve na própria ficha: não tira a marca "precisa de
--      confirmação", não cria ficha com o telefone de outra pessoa.
--   3. O mesmo WhatsApp, com ou sem o 55, é a mesma ficha.
--   4. Sessão de pacote não vira comanda de preço cheio no salão sem comanda.
--   5. O estorno sai da gaveta de hoje, não do caixa de ontem já fechado.
--   6. Remarcar pelo link leva o cupom junto — e não reaproveita cupom de
--      horário desmarcado há tempo.
--   7. A profissional não muda o preço do próprio atendimento.
--
-- E as duas decisões do dono do produto que vieram depois:
--   8. Cupom na loja só com a cliente dentro da conta — e chamar em
--      repetição não esgota o cupom.
--   9. "Eu e mais alguém": o pacote cobre só o horário dela.
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── Cenário ────────────────────────────────────────────────────────────────
insert into public.saloes (id, slug, nome, tipo, status, fuso, cfg) values
  ('cb000000-1111-0000-0000-000000000001', 'salao-cacabug', 'Salão Caça', 'salao',
   'ativo', 'America/Sao_Paulo', '{"diasLiberados": 30, "usaComanda": false}');
insert into public.assinaturas (salao_id, plano, status) values
  ('cb000000-1111-0000-0000-000000000001', 'time', 'ativa');

-- A dona, a profissional (Bia, com login), um estranho e uma cliente com conta.
insert into auth.users (id, email) values
  ('cb000000-0000-0000-0000-00000000000d', 'dona@cacabug.com'),
  ('cb000000-0000-0000-0000-00000000000b', 'bia@cacabug.com'),
  ('cb000000-0000-0000-0000-00000000000e', 'estranho@cacabug.com'),
  ('cb000000-0000-0000-0000-00000000000c', 'carla@cacabug.com');
insert into public.perfis (id, nome, telefone) values
  ('cb000000-0000-0000-0000-00000000000d', 'Dona', '+5511900003001'),
  ('cb000000-0000-0000-0000-00000000000b', 'Bia',  '+5511900003002'),
  ('cb000000-0000-0000-0000-00000000000e', 'Estranho', '+5511900003003'),
  ('cb000000-0000-0000-0000-00000000000c', 'Carla', '+5551911112222')
on conflict (id) do nothing;
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('cb000000-0000-0000-0000-00000000000d', 'cb000000-1111-0000-0000-000000000001', 'dono', 'ativo'),
  ('cb000000-0000-0000-0000-00000000000b', 'cb000000-1111-0000-0000-000000000001', 'profissional', 'ativo');

insert into public.profissionais (id, salao_id, perfil_id, nome, telefone, ativo, aceita_online, comissao_pct) values
  ('cb000000-2222-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001',
   'cb000000-0000-0000-0000-00000000000b', 'Bia', '11987654321', true, true, 45);
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco, ativo, aceita_online) values
  ('cb000000-3333-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001',
   'Corte', 60, 0, 80, true, true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
select 'cb000000-2222-0000-0000-000000000001', d, '09:00', '18:00' from generate_series(0,6) d;

create or replace function dia_cb() returns date language sql stable as $f$
  select (now() at time zone 'America/Sao_Paulo')::date + 2
$f$;
create or replace function vaga_cb() returns timestamptz language sql stable as $f$
  select min(h) from public.horarios_livres('cb000000-2222-0000-0000-000000000001'::uuid,
    dia_cb(), array['cb000000-3333-0000-0000-000000000001'::uuid]) h
$f$;

\echo ''
\echo '1) O catálogo é da equipe'

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000e';
  -- Virar cliente continua livre…
  insert into public.vinculos (perfil_id, salao_id, papel, status) values
    ('cb000000-0000-0000-0000-00000000000e', 'cb000000-1111-0000-0000-000000000001', 'cliente', 'ativo');
  -- …mas não abre a tabela da equipe.
  do $$ begin perform t_igual('quem só virou cliente não lê os profissionais (telefone, comissão)',
    (select count(*) from public.profissionais where salao_id = 'cb000000-1111-0000-0000-000000000001'), 0); end $$;
  do $$ begin perform t_igual('nem os serviços com a comissão',
    (select count(*) from public.servicos where salao_id = 'cb000000-1111-0000-0000-000000000001'), 0); end $$;
  do $$ begin perform t_igual('nem a jornada',
    (select count(*) from public.jornadas where profissional_id = 'cb000000-2222-0000-0000-000000000001'), 0); end $$;
commit;

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000d';
  do $$ begin perform t_igual('a dona continua lendo a equipe',
    (select count(*) from public.profissionais where salao_id = 'cb000000-1111-0000-0000-000000000001'), 1); end $$;
commit;

\echo ''
\echo '2) A cliente não escreve na própria ficha'

insert into public.clientes (id, salao_id, perfil_id, nome, telefone, exige_confirmacao, obs) values
  ('cb000000-7777-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001',
   'cb000000-0000-0000-0000-00000000000c', 'Carla', '51911112222', true, 'paga no pix');

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000c';
  update public.clientes set exige_confirmacao = false, obs = 'mudei', telefone = '51900000000'
   where id = 'cb000000-7777-0000-0000-000000000001';
  do $$ begin perform t_verdade('criar ficha com o telefone de outra pessoa é recusado',
    recusado($q$ insert into public.clientes (salao_id, perfil_id, nome, telefone)
                 values ('cb000000-1111-0000-0000-000000000001',
                         'cb000000-0000-0000-0000-00000000000c', 'Outra', '51955554444') $q$)); end $$;
commit;

select t_verdade('a marca "precisa de confirmação" continua lá',
  (select exige_confirmacao from public.clientes where id = 'cb000000-7777-0000-0000-000000000001'));
select t_texto('a anotação do salão também',
  (select obs from public.clientes where id = 'cb000000-7777-0000-0000-000000000001'), 'paga no pix');
select t_texto('e o telefone',
  (select telefone from public.clientes where id = 'cb000000-7777-0000-0000-000000000001'), '51911112222');

\echo ''
\echo '3) Com ou sem o 55, a mesma ficha'

select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  perform public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
    array['cb000000-3333-0000-0000-000000000001'::uuid], 'Maria Souza', '(51) 99999-8888');
  perform public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
    array['cb000000-3333-0000-0000-000000000001'::uuid], 'Maria', '+55 51 99999-8888');
end $$;
select t_igual('"+55 51 99999-8888" acha a ficha de "(51) 99999-8888" — uma ficha só',
  (select count(*) from public.clientes
    where salao_id = 'cb000000-1111-0000-0000-000000000001' and telefone like '%51999998888'), 1);
select t_igual('e as duas marcações estão nela',
  (select count(*) from public.agendamentos a join public.clientes c on c.id = a.cliente_id
    where c.salao_id = 'cb000000-1111-0000-0000-000000000001' and c.telefone = '51999998888'), 2);

\echo ''
\echo '4) Sessão de pacote não vira comanda de preço cheio'

insert into public.pacotes (id, salao_id, nome, sessoes, preco, validade_dias, ativo) values
  ('cb000000-8888-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001', '4 cortes', 4, 240, 90, true);
insert into public.pacote_servicos (pacote_id, servico_id) values
  ('cb000000-8888-0000-0000-000000000001', 'cb000000-3333-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-00000000000d', false);
select public.vender_pacote('cb000000-8888-0000-0000-000000000001', 'cb000000-7777-0000-0000-000000000001');

select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-00000000000c', false);
create temporary table do_pacote as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Carla', '51911112222');
select set_config('request.jwt.claim.sub', '', false);

select t_verdade('a marcação pelo pacote sai por zero e presa ao pacote',
  (select a.valor_previsto = 0 and a.pacote_cliente_id is not null
     from public.agendamentos a where a.id = (select id from do_pacote)));
update public.agendamentos set status = 'concluido' where id = (select id from do_pacote);
select t_igual('concluída, ela NÃO vira comanda (a sessão já foi paga)',
  (select count(*) from public.comandas where agendamento_id = (select id from do_pacote)), 0);

-- A de controle: sem pacote, concluir continua virando dinheiro.
create temporary table sem_pacote as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Dora Lima', '51933334444');
update public.agendamentos set status = 'concluido' where id = (select id from sem_pacote);
select t_igual('e a sem pacote vira comanda, como sempre',
  (select count(*) from public.comandas where agendamento_id = (select id from sem_pacote)), 1);

\echo ''
\echo '5) O estorno sai da gaveta de hoje'

select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-00000000000d', false);
insert into public.caixas (id, salao_id, valor_abertura) values
  ('cb000000-cccc-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001', 0);
insert into public.comandas (id, salao_id, cliente_id, status) values
  ('cb000000-aaaa-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001',
   'cb000000-7777-0000-0000-000000000001', 'aberta');
insert into public.comanda_itens (comanda_id, tipo, servico_id, descricao, qtd, preco_unit, profissional_id)
values ('cb000000-aaaa-0000-0000-000000000001', 'servico', 'cb000000-3333-0000-0000-000000000001',
        'Corte', 1, 100, 'cb000000-2222-0000-0000-000000000001');
insert into public.pagamentos (id, comanda_id, forma, valor) values
  ('cb000000-9999-0000-0000-000000000001', 'cb000000-aaaa-0000-0000-000000000001', 'dinheiro', 100);
select public.fechar_caixa('cb000000-cccc-0000-0000-000000000001', 100);
select t_verdade('o caixa de ontem fecha certinho (diferença zero)',
  (public.conferir_caixa('cb000000-cccc-0000-0000-000000000001')->>'diferenca')::numeric = 0);

insert into public.caixas (id, salao_id, valor_abertura) values
  ('cb000000-cccc-0000-0000-000000000002', 'cb000000-1111-0000-0000-000000000001', 100);
insert into public.estornos (pagamento_id, salao_id, valor, motivo) values
  ('cb000000-9999-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001', 100, 'valor errado');

select t_verdade('o estorno cai no caixa aberto agora',
  (select caixa_id from public.estornos where pagamento_id = 'cb000000-9999-0000-0000-000000000001')
  = 'cb000000-cccc-0000-0000-000000000002');
select t_verdade('o caixa de ontem, já fechado, NÃO muda (continua diferença zero)',
  (public.conferir_caixa('cb000000-cccc-0000-0000-000000000001')->>'diferenca')::numeric = 0);
select t_verdade('e a gaveta de hoje espera 0 (100 de troco − 100 devolvidos)',
  (public.conferir_caixa('cb000000-cccc-0000-0000-000000000002')->>'esperado')::numeric = 0);
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo '6) Remarcar leva o cupom junto'

insert into public.cupons (id, salao_id, codigo, tipo, valor, vale_agendamento, um_por_cliente, ativo) values
  ('cb000000-dddd-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001', 'BEM10', 'pct', 10, true, true, true);

create temporary table velho as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Eva Rocha', '51977778888',
  null, null, null, null, null, 'bem10');
select t_verdade('marcou com o cupom: R$ 72', (select valor from velho) = 72);

create temporary table novo as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Eva Rocha', '51977778888');
select t_verdade('o horário novo nasce pelo preço cheio (o cupom ainda está no antigo)',
  (select valor from novo) = 80);

select public.remarcar_agendamento((select token from velho), (select token from novo));

select t_texto('o antigo saiu, como remarcado',
  (select status || ' / ' || cancelado_motivo from public.agendamentos where id = (select id from velho)),
  'cancelado / remarcado pelo cliente');
select t_verdade('e o novo ficou com o cupom: desconto de R$ 8, valor R$ 72',
  (select a.cupom_id = 'cb000000-dddd-0000-0000-000000000001' and a.desconto = 8 and a.valor_previsto = 72
     from public.agendamentos a where a.id = (select id from novo)));
select t_igual('é o MESMO uso que mudou de horário — continua um só',
  (select count(*) from public.cupom_usos where cupom_id = 'cb000000-dddd-0000-0000-000000000001'), 1);
select t_verdade('e ele aponta para o horário novo',
  (select agendamento_id from public.cupom_usos where cupom_id = 'cb000000-dddd-0000-0000-000000000001')
  = (select id from novo));

-- O abuso: um horário com cupom desmarcado não vira desconto depois.
create temporary table outro as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb(),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Eva Rocha', '51977778888');
select t_verdade('o horário antigo já desmarcado não é remarcado de novo',
  recusado(format('select public.remarcar_agendamento(%L, %L)',
                  (select token from velho), (select token from outro))));
update public.agendamentos set criado_em = now() - interval '2 hours' where id = (select id from outro);
select t_verdade('nem um horário "novo" marcado há horas recebe o cupom de outro',
  recusado(format('select public.remarcar_agendamento(%L, %L)',
                  (select token from novo), (select token from outro))));

\echo ''
\echo '7) A profissional não muda o preço do próprio atendimento'

-- Outro dia: acima, horários do dia foram "concluídos" no futuro só para o
-- teste, e isso não acontece na vida real.
create temporary table da_bia as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid,
  (select min(h) from public.horarios_livres('cb000000-2222-0000-0000-000000000001'::uuid,
     dia_cb() + 1, array['cb000000-3333-0000-0000-000000000001'::uuid]) h),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Fabi Melo', '51966665555');
-- O id num variável do psql: a tabela temporária é do superusuário, e o papel
-- `authenticated` não a enxerga.
select id as bia_ag from da_bia \gset

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000b';
  update public.agendamento_servicos set preco = 500 where agendamento_id = :'bia_ag';
commit;
select t_verdade('logada como profissional, mudar o preço para R$ 500 não muda nada',
  (select preco from public.agendamento_servicos where agendamento_id = (select id from da_bia)) = 80);

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000d';
  update public.agendamento_servicos set preco = 70 where agendamento_id = :'bia_ag';
commit;
select t_verdade('a dona (balcão) continua combinando o valor',
  (select preco from public.agendamento_servicos where agendamento_id = (select id from da_bia)) = 70);

\echo ''
\echo '8) Cupom na loja só dentro da conta'

insert into public.produtos (id, salao_id, nome, preco, ativo, venda_online) values
  ('cb000000-eeee-0000-0000-000000000001', 'cb000000-1111-0000-0000-000000000001', 'Shampoo', 40, true, true);
insert into public.cupons (id, salao_id, codigo, tipo, valor, vale_agendamento, vale_produtos,
                           um_por_cliente, limite_total, ativo) values
  ('cb000000-dddd-0000-0000-000000000002', 'cb000000-1111-0000-0000-000000000001', 'LOJA10', 'pct', 10,
   false, true, false, 3, true),
  ('cb000000-dddd-0000-0000-000000000003', 'cb000000-1111-0000-0000-000000000001', 'UMAVEZ', 'pct', 20,
   false, true, true, null, true);

begin;
  set local role anon;
  select set_config('request.jwt.claim.sub', '', true);
  do $$ declare r jsonb; begin
    r := public.usar_cupom_no_pedido('cb000000-1111-0000-0000-000000000001', 'loja10',
           '[{"id": "cb000000-eeee-0000-0000-000000000001", "qtd": 1}]');
    perform t_texto('sem conta, o pedido da loja não usa cupom — e diz para entrar',
      (r->>'ok') || ' / ' || (r->>'entrar') || ' / ' || (r->>'motivo'),
      'false / true / Entre na sua conta para usar o cupom na loja.');
    r := public.conferir_cupom('cb000000-1111-0000-0000-000000000001', 'loja10', 'produtos',
           null, null, null, '[{"id": "cb000000-eeee-0000-0000-000000000001", "qtd": 1}]');
    perform t_texto('e a prévia diz o mesmo', (r->>'ok') || ' / ' || (r->>'entrar'), 'false / true');
    r := public.conferir_cupom('cb000000-1111-0000-0000-000000000001', 'BEM10', 'agendamento',
           array['cb000000-3333-0000-0000-000000000001'::uuid], 'cb000000-2222-0000-0000-000000000001');
    perform t_verdade('no agendamento, sem conta, o cupom continua valendo', (r->>'ok')::boolean);
  end $$;
commit;
select t_igual('nenhum uso registrado sem conta',
  (select count(*) from public.cupom_usos where cupom_id = 'cb000000-dddd-0000-0000-000000000002'), 0);

-- O abuso: a mesma conta chamando em repetição, por fora do link.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000e';
  do $$ declare r jsonb; i int; ok int := 0; begin
    for i in 1..5 loop
      r := public.usar_cupom_no_pedido('cb000000-1111-0000-0000-000000000001', 'LOJA10',
             '[{"id": "cb000000-eeee-0000-0000-000000000001", "qtd": 2}]');
      if (r->>'ok')::boolean and (r->>'desconto')::numeric = 8 then ok := ok + 1; end if;
    end loop;
    perform t_igual('logada: as 5 chamadas respondem o mesmo pedido, com o desconto (R$ 8)', ok, 5);
  end $$;
commit;
select t_igual('e só UM uso foi gasto — chamar em repetição não esgota o cupom',
  (select count(*) from public.cupom_usos where cupom_id = 'cb000000-dddd-0000-0000-000000000002'), 1);
select t_verdade('o uso tem dono: a conta que pediu',
  (select perfil_id from public.cupom_usos where cupom_id = 'cb000000-dddd-0000-0000-000000000002')
  = 'cb000000-0000-0000-0000-00000000000e');

begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000c';
  do $$ begin perform t_verdade('outra conta, outro uso',
    (public.usar_cupom_no_pedido('cb000000-1111-0000-0000-000000000001', 'LOJA10',
       '[{"id": "cb000000-eeee-0000-0000-000000000001", "qtd": 1}]')->>'ok')::boolean); end $$;
commit;
select t_igual('agora são 2 usos', (select count(*) from public.cupom_usos
  where cupom_id = 'cb000000-dddd-0000-0000-000000000002'), 2);

-- "1 por cliente" pela conta, mesmo sem ficha no salão.
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000e';
  do $$ begin perform t_verdade('UMAVEZ: a primeira vez vale (quem só compra, sem ficha)',
    (public.usar_cupom_no_pedido('cb000000-1111-0000-0000-000000000001', 'UMAVEZ',
       '[{"id": "cb000000-eeee-0000-0000-000000000001", "qtd": 1}]')->>'ok')::boolean); end $$;
commit;
update public.cupom_usos set criado_em = now() - interval '2 days'
 where cupom_id = 'cb000000-dddd-0000-0000-000000000003';
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = 'cb000000-0000-0000-0000-00000000000e';
  do $$ begin perform t_texto('e noutro dia a mesma conta ouve "Você já usou"',
    public.usar_cupom_no_pedido('cb000000-1111-0000-0000-000000000001', 'UMAVEZ',
       '[{"id": "cb000000-eeee-0000-0000-000000000001", "qtd": 1}]')->>'motivo',
    'Você já usou este cupom.'); end $$;
commit;

select t_falso('a regra da conta (cupom_loja_da_conta) não é chamada por fora',
  has_function_privilege('anon', 'public.cupom_loja_da_conta(uuid,text,boolean)', 'execute')
  or has_function_privilege('authenticated', 'public.cupom_loja_da_conta(uuid,text,boolean)', 'execute'));

\echo ''
\echo '9) "Eu e mais alguém": o pacote é só dela'

-- A Carla tem o pacote de 4 cortes (seção 4), e está dentro da conta.
create or replace function sessoes_carla() returns int language sql as $f$
  select count(*)::int from public.agendamentos a
   where a.pacote_cliente_id is not null and a.status <> 'cancelado'
     and a.cliente_id = 'cb000000-7777-0000-0000-000000000001'
$f$;
create or replace function vaga_cb3(p_depois timestamptz) returns timestamptz language sql stable as $f$
  select min(h) from public.horarios_livres('cb000000-2222-0000-0000-000000000001'::uuid,
    dia_cb() + 3, array['cb000000-3333-0000-0000-000000000001'::uuid]) h
   where p_depois is null or h >= p_depois
$f$;
select sessoes_carla() as antes \gset

select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-00000000000c', false);
create temporary table dela as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid, vaga_cb3(null),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Carla', '51911112222');
create temporary table da_amiga as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid,
  vaga_cb3((select fim from dela)),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Carla', '51911112222',
  p_atendido_nome => 'Lia (amiga)', p_acompanhante => true);
select set_config('request.jwt.claim.sub', '', false);

select t_verdade('o horário dela sai pelo pacote: R$ 0',
  (select valor from dela) = 0
  and (select pacote_cliente_id is not null from public.agendamentos where id = (select id from dela)));
select t_verdade('o da acompanhante sai pelo preço normal (R$ 80), fora do pacote',
  (select valor from da_amiga) = 80
  and (select pacote_cliente_id is null and valor_previsto = 80
         from public.agendamentos where id = (select id from da_amiga)));
select t_igual('uma sessão só foi gasta, não duas', sessoes_carla() - :antes, 1);

-- E "para outra pessoa" (a filha, sozinha) continua como era.
select set_config('request.jwt.claim.sub', 'cb000000-0000-0000-0000-00000000000c', false);
create temporary table da_filha as
select * from public.agendar('cb000000-2222-0000-0000-000000000001'::uuid,
  vaga_cb3((select fim from da_amiga)),
  array['cb000000-3333-0000-0000-000000000001'::uuid], 'Carla', '51911112222',
  p_atendido_nome => 'Nina (filha)');
select set_config('request.jwt.claim.sub', '', false);
select t_verdade('"para outra pessoa" continua usando o pacote, como antes',
  (select valor from da_filha) = 0);
