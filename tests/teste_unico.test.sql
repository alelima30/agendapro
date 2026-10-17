-- ===========================================================================
-- AgendaPro — o teste grátis é um por pessoa (39_teste_unico.sql)
--
-- O caso que motivou: o dono exclui a conta, cadastra de novo e ganha mais 7
-- dias — toda semana. O que se confere:
--   1. o primeiro salão de uma pessoa nasce em teste, como sempre;
--   2. o segundo salão da MESMA conta nasce no Grátis;
--   3. excluída a conta, a marca fica: voltar com o mesmo e-mail (mesmo
--      escrito com pontos e "+", no Gmail) ou o mesmo WhatsApp (com ou sem o
--      nono dígito) nasce no Grátis;
--   4. quem já era dono antes deste módulo e exclui a conta também deixa a
--      marca;
--   5. pessoa nova, e quem só trabalhava num salão, ganham o teste;
--   6. o "Estender teste" da plataforma continua dando dias;
--   7. ninguém lê o registro pelo navegador.
-- ===========================================================================
\set ON_ERROR_STOP on

create or replace function cadastrar(p_id uuid, p_email text, p_nome text, p_tel text) returns void
language sql as $f$
  insert into auth.users (id, email, raw_user_meta_data)
  values (p_id, p_email, jsonb_build_object('nome', p_nome, 'telefone', p_tel))
$f$;

create or replace function abrir_salao(p_quem uuid, p_nome text) returns uuid
language plpgsql as $f$
declare v uuid;
begin
  perform set_config('request.jwt.claim.sub', p_quem::text, false);
  select salao_id into v from public.criar_salao(p_nome_salao => p_nome, p_telefone => '+5511900000000');
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $f$;

create or replace function em_teste(p_salao uuid) returns boolean
language sql as $f$
  select public.plano_efetivo(p_salao) = 'trial'
     and exists (select 1 from public.assinaturas a where a.salao_id = p_salao
                    and a.status = 'trial' and a.trial_ate >= current_date)
$f$;

create or replace function no_gratis(p_salao uuid) returns boolean
language sql as $f$
  select public.plano_efetivo(p_salao) = 'gratuito'
     and exists (select 1 from public.assinaturas a where a.salao_id = p_salao
                    and a.plano = 'gratuito' and a.trial_ate is null)
$f$;

create or replace function excluir(p_quem uuid) returns void
language plpgsql as $f$
begin
  perform set_config('request.jwt.claim.sub', p_quem::text, false);
  perform public.excluir_minha_conta('EXCLUIR');
  perform set_config('request.jwt.claim.sub', '', false);
end $f$;

\echo ''
\echo 'A mesma pessoa escrita de outro jeito'
select t_verdade('o e-mail do Gmail ignora maiúsculas, pontos, "+etiqueta" e o googlemail',
  public.email_para_teste(' Ana.Souza+Teste2@GoogleMail.com ') = 'anasouza@gmail.com');
select t_verdade('fora do Gmail, os pontos ficam (são outra caixa), e a etiqueta sai',
  public.email_para_teste('ana.souza+x@empresa.com.br') = 'ana.souza@empresa.com.br');
select t_verdade('celular sem o nono dígito é o mesmo chip',
  public.tel_para_teste('+55 11 8765-4321') = public.tel_para_teste('+5511987654321'));
select t_verdade('e fixo não ganha nono dígito',
  public.tel_para_teste('+551133334444') = '551133334444');

\echo ''
\echo 'A primeira vez, e a segunda'
select cadastrar('7e000000-0000-0000-0000-0000000000a1', 'ana.souza@gmail.com', 'Ana Souza', '+5511987654321');
select abrir_salao('7e000000-0000-0000-0000-0000000000a1', 'Studio Ana') as s1 \gset
select t_verdade('1. o primeiro salão da Ana nasce em teste', em_teste(:'s1'));
select abrir_salao('7e000000-0000-0000-0000-0000000000a1', 'Studio Ana 2') as s2 \gset
select t_verdade('2. o segundo salão da mesma conta nasce no Grátis', no_gratis(:'s2'));
select t_verdade('   e o primeiro continua em teste', em_teste(:'s1'));

\echo ''
\echo 'Excluir e voltar'
select excluir('7e000000-0000-0000-0000-0000000000a1');
select t_verdade('a conta da Ana foi excluída de verdade',
  not exists (select 1 from auth.users where id = '7e000000-0000-0000-0000-0000000000a1')
  and not exists (select 1 from public.saloes where id in (:'s1', :'s2')));
select t_verdade('   mas a marca de que ela já usou o teste ficou',
  (select count(*) from public.testes_usados) >= 2);
select t_verdade('   e a marca não guarda o telefone nem o e-mail em claro',
  not exists (select 1 from public.testes_usados where marca like '%@%' or marca like '%5511%'));

select cadastrar('7e000000-0000-0000-0000-0000000000a2', 'Ana.Souza+volta@gmail.com', 'Ana Souza', '+5511911112222');
select abrir_salao('7e000000-0000-0000-0000-0000000000a2', 'Studio Ana de Novo') as s3 \gset
select t_verdade('3. voltou com o mesmo Gmail escrito de outro jeito: nasce no Grátis', no_gratis(:'s3'));

select cadastrar('7e000000-0000-0000-0000-0000000000a3', 'outro.email@exemplo.com', 'Ana S', '+551187654321');
select abrir_salao('7e000000-0000-0000-0000-0000000000a3', 'Ana Beleza') as s4 \gset
select t_verdade('   voltou com e-mail novo e o mesmo WhatsApp sem o nono dígito: Grátis', no_gratis(:'s4'));

\echo ''
\echo 'Quem já era dono antes deste módulo'
-- Criado por fora (como estava no banco antes): vínculo e teste sem marca.
select cadastrar('7e000000-0000-0000-0000-0000000000b1', 'veterana@exemplo.com', 'Vera Lima', '+5521977776666');
insert into public.saloes (id, slug, nome, tipo, status)
  values ('7e100000-0000-0000-0000-0000000000b1', 'casa-da-vera', 'Casa da Vera', 'salao', 'ativo');
insert into public.assinaturas (salao_id, plano, status, trial_ate)
  values ('7e100000-0000-0000-0000-0000000000b1', 'trial', 'trial', current_date + 3);
insert into public.vinculos (perfil_id, salao_id, papel, status)
  values ('7e000000-0000-0000-0000-0000000000b1', '7e100000-0000-0000-0000-0000000000b1', 'dono', 'ativo');
delete from public.testes_usados where marca in (select marca from public.marcas_de_teste('7e000000-0000-0000-0000-0000000000b1'));
select excluir('7e000000-0000-0000-0000-0000000000b1');
select cadastrar('7e000000-0000-0000-0000-0000000000b2', 'veterana@exemplo.com', 'Vera Lima', '+5521977776666');
select abrir_salao('7e000000-0000-0000-0000-0000000000b2', 'Casa da Vera') as s5 \gset
select t_verdade('4. ao excluir a conta, a dona antiga deixa a marca — e volta no Grátis', no_gratis(:'s5'));

\echo ''
\echo 'O que não muda'
select cadastrar('7e000000-0000-0000-0000-0000000000c1', 'bia@exemplo.com', 'Bia Rocha', '+5531955554444');
select abrir_salao('7e000000-0000-0000-0000-0000000000c1', 'Bia Studio') as s6 \gset
select t_verdade('5. pessoa nova ganha os 7 dias', em_teste(:'s6'));

-- Sem excluir nada: a Bia abre OUTRA conta, e-mail novo, mesmo WhatsApp. O
-- perfil novo nasce sem telefone (o número já é da primeira conta).
select cadastrar('7e000000-0000-0000-0000-0000000000c9', 'bia.outra@exemplo.com', 'Bia R', '(31) 95555-4444');
select t_verdade('   (a conta nova da Bia nasceu sem telefone no perfil, como sempre foi)',
  (select telefone from public.perfis where id = '7e000000-0000-0000-0000-0000000000c9') is null);
select abrir_salao('7e000000-0000-0000-0000-0000000000c9', 'Bia Studio 2') as s8 \gset
select t_verdade('   e mesmo assim o salão nasce no Grátis: o número digitado conta', no_gratis(:'s8'));

select cadastrar('7e000000-0000-0000-0000-0000000000c2', 'caio@exemplo.com', 'Caio Prado', '+5531944443333');
insert into public.vinculos (perfil_id, salao_id, papel, status)
  values ('7e000000-0000-0000-0000-0000000000c2', :'s6', 'profissional', 'ativo');
delete from public.vinculos where perfil_id = '7e000000-0000-0000-0000-0000000000c2';
select abrir_salao('7e000000-0000-0000-0000-0000000000c2', 'Barbearia do Caio') as s7 \gset
select t_verdade('   quem só trabalhava no salão da Bia ganha o teste no salão dele', em_teste(:'s7'));

select cadastrar('7e000000-0000-0000-0000-0000000000ad', 'plataforma@exemplo.com', 'Plataforma', '+5511900009999');
update public.perfis set super_admin = true where id = '7e000000-0000-0000-0000-0000000000ad';
select set_config('request.jwt.claim.sub', '7e000000-0000-0000-0000-0000000000ad', false);
select public.estender_teste(:'s3', current_date + 7);
select set_config('request.jwt.claim.sub', '', false);
select t_verdade('6. a plataforma ainda dá teste a quem quiser, pelo "Estender teste"', em_teste(:'s3'));

\echo ''
\echo 'Ninguém lê o registro'
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '7e000000-0000-0000-0000-0000000000c1';
  do $$ begin perform t_verdade('7. a dona logada não lê a tabela de marcas',
    recusado('select count(*) from public.testes_usados')); end $$;
  do $$ begin perform t_verdade('   nem pergunta se um telefone já usou o teste',
    recusado($q$select public.ja_usou_teste('7e000000-0000-0000-0000-0000000000a2')$q$)); end $$;
  do $$ begin perform t_verdade('   nem grava marca por conta própria',
    recusado($q$select public.registrar_teste('7e000000-0000-0000-0000-0000000000c1')$q$)); end $$;
rollback;
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '7e000000-0000-0000-0000-0000000000ad';
  do $$ begin perform t_verdade('   nem a plataforma, pelo navegador',
    recusado('select count(*) from public.testes_usados')); end $$;
rollback;
