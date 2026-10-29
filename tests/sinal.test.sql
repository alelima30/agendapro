-- ===========================================================================
-- AgendaPro — o sinal por Pix para garantir o horário (09_cliente.sql, 1e)
--
-- "Como fazer para colocar sinal?" — quem marca pelo link paga uma parte
-- para a chave Pix do salão, e o dono confirma quando o comprovante chega.
--
--   1. percentual: o horário entra pendente, com o valor e o prazo do banco;
--   2. "Meus horários" diz quanto, até quando e para onde mandar;
--   3. valor fixo nunca passa do valor do atendimento;
--   4. sem chave Pix, ou sem sinal ligado, nada muda (confirma como antes);
--   5. o dono confirmar é o sinal ter chegado;
--   6. prazo vencido libera o horário — sozinho, de carona no agendador;
--   7. remarcar leva o sinal pago junto;
--   8. as funções são internas.
-- ===========================================================================
\set ON_ERROR_STOP on

insert into public.saloes (id, slug, nome, tipo, status, fuso, whatsapp, cfg) values
  ('51000000-1111-0000-0000-000000000001', 'sinal-pct', 'Studio Sinal', 'salao', 'ativo',
   'America/Sao_Paulo', '11988887777',
   '{"diasLiberados": 30, "pagamentos": {"formas": ["pix", "credito"], "pix": "pix@studiosinal.com.br",
     "sinal": {"tipo": "pct", "valor": 10, "prazoMin": 60, "titular": "Ju Barbosa",
               "regra": "Devolvo o sinal se cancelar até 24 horas antes."}}}'),
  ('51000000-1111-0000-0000-000000000002', 'sinal-fixo', 'Barbearia Fixo', 'salao', 'ativo',
   'America/Sao_Paulo', null,
   '{"diasLiberados": 30, "pagamentos": {"formas": ["pix"], "pix": "11999990000",
     "sinal": {"tipo": "fixo", "valor": 80}}}'),
  ('51000000-1111-0000-0000-000000000003', 'sinal-sem-chave', 'Salão Sem Chave', 'salao', 'ativo',
   'America/Sao_Paulo', null,
   '{"diasLiberados": 30, "pagamentos": {"formas": ["pix"], "sinal": {"tipo": "pct", "valor": 10}}}'),
  ('51000000-1111-0000-0000-000000000004', 'sinal-nenhum', 'Salão Sem Sinal', 'salao', 'ativo',
   'America/Sao_Paulo', null,
   '{"diasLiberados": 30, "pagamentos": {"formas": ["pix"], "pix": "pix@semsinal.com"}}');
insert into public.assinaturas (salao_id, plano, status)
  select id, 'time', 'ativa' from public.saloes where slug like 'sinal-%';

insert into public.profissionais (id, salao_id, nome, ativo, aceita_online)
  select ('51000000-2222-0000-0000-00000000000' || right(id::text, 1))::uuid, id, 'Ana', true, true
    from public.saloes where slug like 'sinal-%';
insert into public.servicos (id, salao_id, nome, duracao_min, intervalo_min, preco, ativo, aceita_online)
  select ('51000000-3333-0000-0000-00000000000' || right(id::text, 1))::uuid, id, 'Escova', 30, 0, 50, true, true
    from public.saloes where slug like 'sinal-%';
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select p.id, d, '08:00', '20:00' from public.profissionais p, generate_series(0, 6) d
   where p.salao_id in (select id from public.saloes where slug like 'sinal-%');

-- A n-ésima vaga livre daqui a três dias, no salão n.
create or replace function vaga_s(p_salao int, p_n int) returns timestamptz
language sql stable as $f$
  select h from public.horarios_livres(('51000000-2222-0000-0000-00000000000' || p_salao)::uuid,
                                       (now() at time zone 'America/Sao_Paulo')::date + 3,
                                       array[('51000000-3333-0000-0000-00000000000' || p_salao)::uuid]) h
   order by h offset p_n - 1 limit 1
$f$;
create or replace function marcar_s(p_salao int, p_n int, p_nome text, p_tel text)
returns table (id uuid, token uuid) language sql as $f$
  select a.id, a.token from public.agendar(('51000000-2222-0000-0000-00000000000' || p_salao)::uuid,
    vaga_s(p_salao, p_n), array[('51000000-3333-0000-0000-00000000000' || p_salao)::uuid],
    p_nome, p_tel) a
$f$;
create or replace function ag(p_id uuid) returns public.agendamentos language sql as $f$
  select * from public.agendamentos where id = p_id
$f$;
create or replace function meu(p_token uuid) returns jsonb language sql as $f$
  select public.meus_agendamentos(array[p_token])->0
$f$;

\echo ''
\echo '1. Percentual (10% de R$ 50)'
create temporary table a1 as select * from marcar_s(1, 1, 'Bia Lima', '11911110001');
select t_texto('com sinal, o horário entra pendente (o salão confirma sozinho, mas não sem o sinal)',
  (ag((select id from a1))).status, 'pendente');
select t_texto('o sinal é 10% do que ela vai pagar: R$ 5,00, calculado pelo banco',
  (ag((select id from a1))).sinal_exigido::text, '5.00');
select t_verdade('o prazo é de 1 hora a partir de agora',
  (ag((select id from a1))).sinal_ate between now() + interval '59 minutes' and now() + interval '61 minutes');
select t_texto('e nada pago ainda', (ag((select id from a1))).sinal_pago::text, '0.00');

\echo ''
\echo '2. "Meus horários" diz como pagar'
select t_texto('o valor', meu((select token from a1))->'sinal'->>'valor', '5.00');
select t_texto('a chave Pix do salão', meu((select token from a1))->'sinal'->>'chave', 'pix@studiosinal.com.br');
select t_texto('quem recebe', meu((select token from a1))->'sinal'->>'titular', 'Ju Barbosa');
select t_verdade('a regra de cancelamento', meu((select token from a1))->'sinal'->>'regra' like 'Devolvo%');
select t_texto('o WhatsApp para o comprovante', meu((select token from a1))->'sinal'->>'whatsapp', '11988887777');
select t_texto('e que ainda não foi pago', meu((select token from a1))->'sinal'->>'pago', 'false');
select t_verdade('com o prazo', (meu((select token from a1))->'sinal'->>'ate') is not null);

\echo ''
\echo '3. Valor fixo'
create temporary table a2 as select * from marcar_s(2, 1, 'Caio Reis', '11911110002');
select t_texto('R$ 80 fixo num atendimento de R$ 50: o sinal fica nos R$ 50',
  (ag((select id from a2))).sinal_exigido::text, '50.00');
select t_texto('sem WhatsApp nem telefone no salão, não há número para o comprovante',
  coalesce(meu((select token from a2))->'sinal'->>'whatsapp', '(vazio)'), '(vazio)');

\echo ''
\echo '4. Sem chave Pix, ou sem sinal ligado: como antes'
create temporary table a3 as select * from marcar_s(3, 1, 'Duda Melo', '11911110003');
select t_verdade('sinal ligado sem chave Pix: não há para onde mandar, e não cobra',
  (ag((select id from a3))).sinal_exigido = 0 and (ag((select id from a3))).status = 'confirmado');
create temporary table a4 as select * from marcar_s(4, 1, 'Eva Dias', '11911110004');
select t_verdade('sem sinal ligado: confirmado na hora, sem prazo',
  (ag((select id from a4))).sinal_exigido = 0 and (ag((select id from a4))).status = 'confirmado'
  and (ag((select id from a4))).sinal_ate is null);
select t_verdade('e "Meus horários" não fala em sinal', meu((select token from a4))->'sinal' = 'null'::jsonb);
select t_texto('atendimento que sai por R$ 0 (pacote) não tem sinal',
  public.sinal_do_salao('51000000-1111-0000-0000-000000000001', 0)::text, '0');

\echo ''
\echo '5. O dono confirma: o sinal chegou'
update public.agendamentos set status = 'confirmado' where id = (select id from a1);
select t_texto('confirmar marca o sinal como pago', (ag((select id from a1))).sinal_pago::text, '5.00');
select t_texto('e "Meus horários" passa a dizer pago', meu((select token from a1))->'sinal'->>'pago', 'true');

\echo ''
\echo '6. O prazo venceu'
create temporary table a5 as select * from marcar_s(1, 3, 'Fê Souza', '11911110005');
update public.agendamentos set sinal_ate = now() - interval '1 minute' where id = (select id from a5);
select t_igual('vencido e sem sinal: um horário liberado', public.liberar_sinais_vencidos()::bigint, 1);
select t_texto('volta a ficar livre (cancelado)', (ag((select id from a5))).status, 'cancelado');
select t_texto('dizendo por quê', (ag((select id from a5))).cancelado_motivo, 'sinal não pago no prazo');
select t_texto('e a cliente vê o motivo em "Meus horários"', meu((select token from a5))->>'sinalVencido', 'true');
select t_texto('o confirmado (sinal pago) não é tocado', (ag((select id from a1))).status, 'confirmado');
select t_verdade('e o horário vencido pode ser marcado de novo',
  exists (select 1 from public.horarios_livres('51000000-2222-0000-0000-000000000001',
            (now() at time zone 'America/Sao_Paulo')::date + 3,
            array['51000000-3333-0000-0000-000000000001'::uuid]) h
          where h = (ag((select id from a5))).inicio));

create temporary table a6 as select * from marcar_s(1, 5, 'Gi Melo', '11911110006');
update public.agendamentos set sinal_ate = now() - interval '1 minute' where id = (select id from a6);
select public.gerar_resumos();
select t_texto('sozinho: o agendador (gerar_resumos) libera o vencido',
  (ag((select id from a6))).status, 'cancelado');

update public.saloes set cfg = jsonb_set(cfg, '{pagamentos,sinal,prazoMin}', '5')
 where slug = 'sinal-fixo';
select t_texto('prazo de 5 minutos vira 10', public.sinal_prazo('51000000-1111-0000-0000-000000000002')::text, '00:10:00');
select t_texto('sem prazo, 1 hora', public.sinal_prazo('51000000-1111-0000-0000-000000000003')::text, '01:00:00');

\echo ''
\echo '7. Remarcar leva o sinal pago'
create temporary table a7 as select * from marcar_s(1, 7, 'Helô Prado', '11911110007');
update public.agendamentos set status = 'confirmado' where id = (select id from a7);
create temporary table a8 as select * from marcar_s(1, 9, 'Helô Prado', '11911110007');
select t_texto('o horário novo nasce pedindo sinal', (ag((select id from a8))).status, 'pendente');
select public.remarcar_agendamento((select token from a7), (select token from a8));
select t_texto('remarcou: o sinal pago vai junto', (ag((select id from a8))).sinal_pago::text, '5.00');
select t_texto('e o novo fica confirmado, sem pagar duas vezes', (ag((select id from a8))).status, 'confirmado');

\echo ''
\echo '8. Internas'
select t_falso('nem anon nem logado executam as funções do sinal',
  has_function_privilege('anon', 'public.liberar_sinais_vencidos()', 'execute')
  or has_function_privilege('authenticated', 'public.liberar_sinais_vencidos()', 'execute')
  or has_function_privilege('anon', 'public.sinal_do_salao(uuid, numeric)', 'execute')
  or has_function_privilege('anon', 'public.sinal_prazo(uuid)', 'execute'));
