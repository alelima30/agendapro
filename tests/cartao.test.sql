-- ===========================================================================
-- AgendaPro — a assinatura no cartão renova sozinha, e só uma vez por mês
--
-- ── O QUE ESTE ARQUIVO EXISTE PARA PEGAR ──────────────────────────────────
-- O defeito que a auditoria previu antes de existir código: na SEGUNDA
-- cobrança, o Mercado Pago avisa um pagamento que não tem cobrança nossa —
-- `abrir_cobranca()` só roda quando alguém clica, e ninguém clica no mês 2.
--
-- Se `registrar_recorrencia()` não criasse a linha do mês, o mês 1 renovaria
-- e o mês 2 falharia em silêncio. O salão acharia que está em dia por trinta
-- dias, e aí perderia o plano sem ter feito nada errado.
--
-- É o pior formato de defeito que existe: só aparece depois, e parece culpa
-- do cliente.
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── Cenário: um salão pagante, no plano Dupla ─────────────────────────────
insert into auth.users (id) values
  ('e0000000-0000-0000-0000-00000000000a') on conflict do nothing;
/* ⚠ `do update`, e não `do nothing`.
   O perfil já nasce junto com o `auth.users`, com nome genérico e sem e-mail.
   Com `do nothing` o insert vira silenciosamente um no-op, e o e-mail que este
   arquivo precisa nunca chega à tabela — foi o que aconteceu: o teste do
   `preparar_cartao` reprovou dizendo que o e-mail do dono era nulo, e o defeito
   estava aqui, não na função. */
insert into public.perfis (id, nome, email) values
  ('e0000000-0000-0000-0000-00000000000a', 'Dona do Cartão', 'cartao@teste.com')
  on conflict (id) do update
    set nome = excluded.nome, email = excluded.email;
insert into public.saloes (id, slug, nome) values
  ('e0000000-1111-0000-0000-00000000000b', 'salao-cartao', 'Salão do Cartão');
insert into public.vinculos (perfil_id, salao_id, papel, status) values
  ('e0000000-0000-0000-0000-00000000000a',
   'e0000000-1111-0000-0000-00000000000b', 'dono', 'ativo');
insert into public.assinaturas (salao_id, plano, status, vence_em) values
  ('e0000000-1111-0000-0000-00000000000b', 'duo', 'ativa', current_date + 3);

\echo ''
\echo 'LIGAR O CARTÃO'

select t_verdade('ligar_cartao aceita a pré-aprovação',
  (public.ligar_cartao('e0000000-1111-0000-0000-00000000000b', 'PREAPP-1')->>'ok')::boolean);

select t_verdade('e a assinatura passa a saber que está no cartão',
  (select mp_preapproval = 'PREAPP-1' and cartao_desde is not null
     from public.assinaturas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'));

/* ⚠ A mesma pré-aprovação em dois salões seria id trocado no caminho, não
   renovação — e mover o plano do salão errado é o pior desfecho possível. */
insert into public.saloes (id, slug, nome) values
  ('e0000000-2222-0000-0000-00000000000c', 'outro-cartao', 'Outro Salão');
insert into public.assinaturas (salao_id, plano, status) values
  ('e0000000-2222-0000-0000-00000000000c', 'duo', 'ativa');
select t_falso('a mesma pré-aprovação NÃO é aceita noutro salão',
  (public.ligar_cartao('e0000000-2222-0000-0000-00000000000c', 'PREAPP-1')->>'ok')::boolean);

\echo ''
\echo 'A PRIMEIRA COBRANÇA DO MÊS'

-- O preço do plano Dupla, lido da tabela — nunca escrito à mão aqui.
select preco_mes as preco_duo from public.planos where codigo = 'duo' \gset

select t_verdade('a primeira recorrência é registrada',
  (public.registrar_recorrencia('PREAPP-1', 'MP-CARD-1', :preco_duo, 'approved')->>'ok')::boolean);

select t_texto('nasceu uma cobrança de cartão',
  (select metodo from public.cobrancas where mp_id = 'MP-CARD-1'), 'cartao');
select t_texto('e ela ficou paga',
  (select status from public.cobrancas where mp_id = 'MP-CARD-1'), 'paga');

\echo ''
\echo 'A SEGUNDA — QUE É O MOTIVO DESTE ARQUIVO'

-- Trinta dias depois: nenhum clique, nenhuma cobrança esperando.
select vence_em::text as venc_apos_1 from public.assinaturas
 where salao_id = 'e0000000-1111-0000-0000-00000000000b' \gset

select t_verdade('a segunda recorrência TAMBÉM é registrada, sem clique nenhum',
  (public.registrar_recorrencia('PREAPP-1', 'MP-CARD-2', :preco_duo, 'approved')->>'ok')::boolean);

select t_texto('e a assinatura andou mais um mês',
  (select vence_em::text from public.assinaturas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'),
  (:'venc_apos_1'::date + interval '1 month')::date::text);

\echo ''
\echo 'O MESMO AVISO CHEGANDO DUAS VEZES'

/* O Mercado Pago reenvia até receber 200, e reenvia de novo a cada mudança do
   pagamento. Cada chegada somando um mês daria meio ano a quem pagou um. */
select vence_em::text as venc_apos_2 from public.assinaturas
 where salao_id = 'e0000000-1111-0000-0000-00000000000b' \gset

select t_texto('aviso repetido responde "já registrada"',
  public.registrar_recorrencia('PREAPP-1', 'MP-CARD-2', :preco_duo, 'approved')->>'motivo',
  'ja_registrada');
select t_texto('e NÃO estende de novo',
  (select vence_em::text from public.assinaturas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'),
  :'venc_apos_2');

\echo ''
\echo 'O QUE NÃO PODE ATIVAR'

select t_falso('pré-aprovação desconhecida não move nada',
  (public.registrar_recorrencia('NAO-EXISTE', 'MP-X', :preco_duo, 'approved')->>'ok')::boolean);

/* Valor divergente: é a trava que impede pagar o plano pequeno e levar o
   grande. Ela já existia no registrar_pagamento, e tem que continuar valendo
   pela recorrência — que é um caminho novo até ela. */
select t_falso('valor divergente não ativa',
  (public.registrar_recorrencia('PREAPP-1', 'MP-CARD-3', 1.00, 'approved')->>'ok')::boolean);
select t_texto('e a cobrança fica marcada como divergente, não paga',
  (select status from public.cobrancas where mp_id = 'MP-CARD-3'), 'pendente');

select t_texto('pagamento recusado pelo cartão não ativa',
  public.registrar_recorrencia('PREAPP-1', 'MP-CARD-4', :preco_duo, 'rejected')->>'motivo',
  'nao_aprovado');

/* ⚠ E UM MÊS RUIM NÃO TRAVA OS SEGUINTES.

   Este bloco existe por causa de um defeito que este arquivo pegou antes de
   ir para produção: as duas cobranças acima ficaram `pendente`, e o
   `ux_cobranca_aberta` — que garante uma pendente por salão — recusava a
   terceira. Na prática: uma recorrência recusada travava a do mês seguinte,
   o webhook devolvia 500, e a assinatura nunca mais renovava.

   O índice passou a valer só para o que o dono paga na mão. */
select t_verdade('depois de duas falhas, o mês seguinte ainda entra',
  (public.registrar_recorrencia('PREAPP-1', 'MP-CARD-5', :preco_duo, 'approved')->>'ok')::boolean);

select t_igual('e as três cobranças de cartão convivem',
  (select count(*) from public.cobrancas
    where mp_id in ('MP-CARD-3','MP-CARD-4','MP-CARD-5')), 3::bigint);

/* A cobrança de cartão não é "pague isto": não tem Pix nem boleto. Se ela
   aparecesse como aberta, o dono ligaria perguntando o que copiar.

   ⚠ `minha_cobranca` é a tela do dono, e exige `e_gestor` — que pergunta pelo
   `auth.uid()`. Rodando como superusuário não há sessão nenhuma, e ela recusa
   com razão. Fingir a sessão da dona é o que faz este teste medir o que o
   painel dela vai ver, e não o que um superusuário veria. */
select set_config('request.jwt.claim.sub',
                  'e0000000-0000-0000-0000-00000000000a', false);
select t_verdade('e nenhuma delas aparece como cobrança a pagar no painel',
  (select public.minha_cobranca('e0000000-1111-0000-0000-00000000000b')->'aberta')
    = 'null'::jsonb);
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo 'QUEM ESTÁ NO CARTÃO NÃO É COBRADO POR PIX'

/* Sem isto o dono receberia, cinco dias antes, um pedido para gerar Pix de
   uma conta que vai ser debitada sozinha — e pagaria duas vezes. */
update public.assinaturas set vence_em = current_date + 2
 where salao_id = 'e0000000-1111-0000-0000-00000000000b';

select t_igual('o salão no cartão fica FORA da lista de cobrança',
  (select count(*) from public.assinaturas_a_vencer(5)
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'), 0::bigint);

-- E o contrário: sem cartão, ele volta para a lista. Sem esta metade, a
-- verificação acima passaria com uma função que não devolve ninguém.
select public.cancelar_cartao('e0000000-1111-0000-0000-00000000000b',
                              'e0000000-0000-0000-0000-00000000000a');
select t_igual('e volta para a lista assim que o cartão sai',
  (select count(*) from public.assinaturas_a_vencer(5)
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'), 1::bigint);

\echo ''
\echo 'CANCELAR NÃO DERRUBA O PLANO NA HORA'

select t_texto('o plano continua ativo depois de cancelar o cartão',
  (select status from public.assinaturas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'), 'ativa');
select t_verdade('e a data de vencimento não foi tocada',
  (select vence_em = current_date + 2 from public.assinaturas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'));

\echo ''
\echo 'O QUE A BORDA PERGUNTA ANTES DE FALAR COM O MERCADO PAGO'

/* Devolve a mensagem do banco, ou null quando a chamada passou. */
create or replace function preparou(p_salao uuid, p_plano text, p_quem uuid)
returns text language plpgsql as $$
begin
  perform public.preparar_cartao(p_salao, p_plano, p_quem);
  return null;
exception when others then return sqlerrm; end $$;

/* ⚠ O preço sai da TABELA, e é o número que vai virar `transaction_amount` da
   pré-aprovação — o valor debitado todo mês, para sempre. Se ele pudesse vir
   da tela, a mensalidade seria escolhida pelo cliente, e de forma recorrente. */
select t_verdade('preparar_cartao lê o preço do plano, não o recebe',
  (public.preparar_cartao('e0000000-1111-0000-0000-00000000000b', 'duo',
     'e0000000-0000-0000-0000-00000000000a')->>'valor')::numeric = :preco_duo);

select t_texto('e devolve o e-mail do dono, que é para quem a assinatura vai',
  public.preparar_cartao('e0000000-1111-0000-0000-00000000000b', 'duo',
    'e0000000-0000-0000-0000-00000000000a')->>'email', 'cartao@teste.com');

select t_falso('com o cartão desligado, jaLigado é falso',
  (public.preparar_cartao('e0000000-1111-0000-0000-00000000000b', 'duo',
     'e0000000-0000-0000-0000-00000000000a')->>'jaLigado')::boolean);

/* Quem não tem vínculo não pergunta preço nem e-mail de salão alheio. Sem
   isto, um `p_quem` inventado seria uma consulta de e-mail por id de salão. */
insert into auth.users (id) values
  ('e0000000-0000-0000-0000-00000000000d') on conflict do nothing;
insert into public.perfis (id, nome, email) values
  ('e0000000-0000-0000-0000-00000000000d', 'Estranho', 'estranho@teste.com')
  on conflict (id) do update
    set nome = excluded.nome, email = excluded.email;

select t_verdade('quem não é da casa não prepara nada',
  preparou('e0000000-1111-0000-0000-00000000000b', 'duo',
           'e0000000-0000-0000-0000-00000000000d') like 'Sem permissão%');

-- Plano sem preço é o Grátis. Criar uma pré-aprovação de R$ 0,00 só serviria
-- para o Mercado Pago recusar com uma mensagem ilegível.
select t_verdade('e plano de graça não vira assinatura no cartão',
  preparou('e0000000-1111-0000-0000-00000000000b', 'gratuito',
           'e0000000-0000-0000-0000-00000000000a') is not null);

\echo ''
\echo 'O IDENTIFICADOR QUE A BORDA PRECISA PARA CANCELAR NA FONTE'

select public.ligar_cartao('e0000000-1111-0000-0000-00000000000b', 'PREAPP-2');

select t_verdade('agora jaLigado é verdadeiro',
  (public.preparar_cartao('e0000000-1111-0000-0000-00000000000b', 'duo',
     'e0000000-0000-0000-0000-00000000000a')->>'jaLigado')::boolean);

/* ⚠ E UMA PRÉ-APROVAÇÃO NÃO É TROCADA POR OUTRA POR BAIXO.

   Sobrescrever seria o pior desfecho silencioso deste módulo: as duas
   continuam ativas no Mercado Pago, as duas debitam todo mês, e a gente perde
   o identificador da primeira — que é justamente o que a borda precisa para
   cancelá-la. O dono descobre na fatura, e ninguém consegue desligar a
   cobrança que sobrou. */
select t_texto('a segunda pré-aprovação do mesmo salão é recusada',
  public.ligar_cartao('e0000000-1111-0000-0000-00000000000b', 'PREAPP-3')
    ->>'motivo', 'ja_tem_outro');
select t_texto('e a primeira continua sendo a que vale',
  (select mp_preapproval from public.assinaturas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'), 'PREAPP-2');

/* Mas o MESMO id repetido passa: o Mercado Pago reenvia o aviso de
   autorização até receber 200, e recusar o reenvio faria a trava acima
   quebrar exatamente o caminho feliz. */
select t_verdade('o mesmo id chegando de novo continua passando',
  (public.ligar_cartao('e0000000-1111-0000-0000-00000000000b', 'PREAPP-2')
    ->>'ok')::boolean);

/* A borda tem que ler o id ANTES de limpar, senão cancela no banco e o
   Mercado Pago continua debitando — com o painel dizendo que parou. */
select t_texto('cartao_do_salao entrega o id da pré-aprovação à borda',
  public.cartao_do_salao('e0000000-1111-0000-0000-00000000000b',
    'e0000000-0000-0000-0000-00000000000a')->>'preapproval', 'PREAPP-2');

create or replace function leu_cartao(p_salao uuid, p_quem uuid)
returns text language plpgsql as $$
begin
  perform public.cartao_do_salao(p_salao, p_quem);
  return null;
exception when others then return sqlerrm; end $$;

select t_verdade('mas não para quem não é da casa',
  leu_cartao('e0000000-1111-0000-0000-00000000000b',
             'e0000000-0000-0000-0000-00000000000d') like 'Sem permissão%');

/* E a tela do dono NÃO recebe o id. Ela só precisa saber que existe; o
   identificador é o que move dinheiro no Mercado Pago. */
select set_config('request.jwt.claim.sub',
                  'e0000000-0000-0000-0000-00000000000a', false);
select t_verdade('meu_cartao diz que está ligado',
  (public.meu_cartao('e0000000-1111-0000-0000-00000000000b')->>'ligado')::boolean);
select t_verdade('e NÃO devolve a pré-aprovação para a tela',
  not (public.meu_cartao('e0000000-1111-0000-0000-00000000000b') ? 'preapproval'));
select set_config('request.jwt.claim.sub', '', false);

\echo ''
\echo 'QUANDO O CANCELAMENTO VEM DO OUTRO LADO'

/* O dono pode cancelar dentro da conta dele no Mercado Pago, e o Mercado Pago
   cancela sozinho depois de tentativas demais num cartão que não passa. Nos
   dois casos o débito para e ninguém nos avisa por dentro.

   Se o `mp_preapproval` ficasse preenchido, o salão continuaria marcado como
   "renova sozinho" e venceria em silêncio — sem cobrança, sem lembrete, e sem
   nada no sistema explicando. Não há pessoa nenhuma neste caminho: quem
   identifica o salão é o id que veio da API deles. */
select t_texto('desligar_cartao acha o salão pelo id da pré-aprovação',
  public.desligar_cartao('PREAPP-2')->>'salao',
  'e0000000-1111-0000-0000-00000000000b');

select t_igual('e o salão volta na hora para a lista de renovação',
  (select count(*) from public.assinaturas_a_vencer(5)
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'), 1::bigint);

select t_texto('o mesmo aviso de novo não quebra nada',
  public.desligar_cartao('PREAPP-2')->>'motivo', 'nada_a_desligar');
select t_texto('nem um id que nunca foi nosso',
  public.desligar_cartao('NUNCA-EXISTIU')->>'motivo', 'nada_a_desligar');

\echo ''
\echo 'E O PIX NÃO APAGA O RASTRO DA TENTATIVA DO CARTÃO'

/* ⚠ O QUARTO LUGAR QUE PRECISA DA MESMA DISTINÇÃO.

   `abrir_cobranca()` procura "a pendente do salão" para reaproveitar ou
   cancelar. As tentativas recusadas do cartão também ficam `pendente`, e sem
   o filtro elas entravam nessa busca: o dono que saiu do cartão e clicava em
   Pix via a linha do cartão ser marcada como cancelada — apagando o registro
   de por que a renovação falhou, que é justamente o que o suporte vai
   procurar. E como agora várias podem coexistir, o `select into` pegava uma
   qualquer delas. */
select public.abrir_cobranca('e0000000-1111-0000-0000-00000000000b', 'duo',
  'pix', 'e0000000-0000-0000-0000-00000000000a');

select t_igual('as duas recusas do cartão continuam pendentes',
  (select count(*) from public.cobrancas
    where mp_id in ('MP-CARD-3','MP-CARD-4') and status = 'pendente'), 2::bigint);

select t_igual('e o Pix novo nasceu do lado delas',
  (select count(*) from public.cobrancas
    where salao_id = 'e0000000-1111-0000-0000-00000000000b'
      and metodo = 'pix' and status = 'pendente'), 1::bigint);

\echo ''
\echo 'E NINGUÉM DE NAVEGADOR CHAMA ESTAS FUNÇÕES'

select t_falso('authenticated não liga cartão',
  has_function_privilege('authenticated',
    'public.ligar_cartao(uuid,text)', 'EXECUTE'));
select t_falso('nem registra recorrência',
  has_function_privilege('authenticated',
    'public.registrar_recorrencia(text,text,numeric,text)', 'EXECUTE'));
select t_falso('nem prepara a assinatura, que devolve e-mail do dono',
  has_function_privilege('authenticated',
    'public.preparar_cartao(uuid,text,uuid)', 'EXECUTE'));
select t_falso('nem lê o id da pré-aprovação',
  has_function_privilege('authenticated',
    'public.cartao_do_salao(uuid,uuid)', 'EXECUTE'));
select t_falso('nem desliga cartão por id, que não pergunta quem é',
  has_function_privilege('authenticated',
    'public.desligar_cartao(text)', 'EXECUTE'));
select t_falso('e anon não desliga cartão nenhum',
  has_function_privilege('anon', 'public.desligar_cartao(text)', 'EXECUTE'));
select t_verdade('mas a borda registra',
  has_function_privilege('service_role',
    'public.registrar_recorrencia(text,text,numeric,text)', 'EXECUTE'));

/* A tela do dono é a exceção: `meu_cartao` é chamada pelo painel, e confere
   `e_gestor` por dentro. Sem esta linha, um "revoke tudo" passaria despercebido
   e o painel diria "não consegui ler" para todo mundo. */
select t_verdade('a tela do dono lê a própria situação',
  has_function_privilege('authenticated', 'public.meu_cartao(uuid)', 'EXECUTE'));
select t_falso('e anon não',
  has_function_privilege('anon', 'public.meu_cartao(uuid)', 'EXECUTE'));
