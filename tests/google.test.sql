-- ===========================================================================
-- AgendaPro — entrar com o Google: completar o cadastro (51_google.sql)
--
-- O Google entrega nome e e-mail. O salão precisa do WhatsApp e do
-- aniversário, e `completar_meu_cadastro` os grava no perfil de quem entrou.
--
--   1. a conta do Google nasce sem WhatsApp (só nome e e-mail);
--   2. sem login não completa; o anon nem chama;
--   3. completa: WhatsApp no padrão (+55…) e o aniversário;
--   4. o WhatsApp de OUTRA conta não é tomado, e a frase diz o que fazer;
--   5. quem já tem WhatsApp não troca por aqui; o aniversário só o vazio;
--   6. data impossível é recusada;
--   7. depois, a ficha do salão nasce com os dois (48).
-- ===========================================================================
\set ON_ERROR_STOP on

-- Como o Supabase grava quem entra pelo Google: nome no full_name, sem telefone.
insert into auth.users (id, email, raw_user_meta_data) values
  ('c5100000-0000-0000-0000-0000000000f1', 'gabi@gmail.com',
   '{"full_name":"Gabriela Prado","avatar_url":"https://x/y.png"}');
insert into auth.users (id, email, raw_user_meta_data) values
  ('c5100000-0000-0000-0000-0000000000a1', 'outra@t.com',
   '{"nome":"Outra Pessoa","telefone":"+5511951000001"}');
insert into public.saloes (id, slug, nome, status, fuso) values
  ('55100000-0000-0000-0000-00000000000a', 'google-salao', 'Studio Google', 'ativo', 'America/Sao_Paulo');
insert into public.assinaturas (salao_id, plano, status) values
  ('55100000-0000-0000-0000-00000000000a', 'time', 'ativa');
grant usage on schema auth to anon, authenticated;

create or replace function t_completar(p_quem uuid, p_tel text, p_nasc date) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_quem::text, ''), true);
  perform set_config('role', 'authenticated', true);
  r := public.completar_meu_cadastro(p_tel, p_nasc);
  perform set_config('role', 'postgres', true);
  return r;
end $$;

\echo ''
\echo '1. A conta do Google nasce sem WhatsApp'
select t_texto('com o nome do Google e sem telefone',
  (select nome || ' | ' || coalesce(telefone, 'sem telefone') from public.perfis
    where id = 'c5100000-0000-0000-0000-0000000000f1'), 'Gabriela Prado | sem telefone');

\echo ''
\echo '2. Quem chama'
select t_verdade('o anon não executa',
  not has_function_privilege('anon', 'public.completar_meu_cadastro(text,date)', 'execute'));
select t_texto('sem login, não completa',
  erro_de($$select t_completar(null, '(11) 95100-0002', '1990-01-01')$$),
  'Entre de novo para completar o cadastro.');

\echo ''
\echo '4. O WhatsApp de outra conta não é tomado'
select t_texto('diz que já está em outra conta, e o que fazer',
  erro_de($$select t_completar('c5100000-0000-0000-0000-0000000000f1', '(11) 95100-0001', '1990-01-01')$$),
  'Este WhatsApp já está em outra conta. Entre com o e-mail e a senha dela, ou fale com o salão.');

\echo ''
\echo '6. Data impossível'
select t_texto('aniversário no futuro é recusado',
  erro_de($$select t_completar('c5100000-0000-0000-0000-0000000000f1', '(11) 95100-0002', current_date + 1)$$),
  'Confira a data do aniversário.');
select t_texto('WhatsApp sem DDD é recusado',
  erro_de($$select t_completar('c5100000-0000-0000-0000-0000000000f1', '9510', '1990-01-01')$$),
  'Falta o WhatsApp com DDD.');

\echo ''
\echo '3. Completa'
select t_completar('c5100000-0000-0000-0000-0000000000f1', '(11) 95100-0002', '1993-08-15') as r3 \gset
select t_texto('WhatsApp no padrão e o aniversário, no perfil',
  (select telefone || ' | ' || nascimento::text from public.perfis
    where id = 'c5100000-0000-0000-0000-0000000000f1'), '+5511951000002 | 1993-08-15');
select t_texto('e devolve os dados da conta', :'r3'::jsonb->>'telefone', '+5511951000002');

\echo ''
\echo '5. Quem já tem WhatsApp não troca por aqui; o aniversário só o vazio'
select t_completar('c5100000-0000-0000-0000-0000000000f1', '(11) 95100-0009', '2000-01-01') as r5 \gset
select t_texto('continua o mesmo WhatsApp e o mesmo aniversário',
  (select telefone || ' | ' || nascimento::text from public.perfis
    where id = 'c5100000-0000-0000-0000-0000000000f1'), '+5511951000002 | 1993-08-15');

\echo ''
\echo '7. A ficha do salão nasce com os dois'
select set_config('request.jwt.claim.sub', 'c5100000-0000-0000-0000-0000000000f1', false);
set role authenticated;
select public.cadastrar_minha_ficha('55100000-0000-0000-0000-00000000000a') as r7 \gset
reset role;
select t_texto('ficha com nome do Google, WhatsApp, e-mail e aniversário',
  (select nome || ' | ' || telefone || ' | ' || email || ' | ' || nascimento::text
     from public.clientes where id = (:'r7'::jsonb->>'ficha')::uuid),
  'Gabriela Prado | 11951000002 | gabi@gmail.com | 1993-08-15');
select set_config('request.jwt.claim.sub', '', false);
