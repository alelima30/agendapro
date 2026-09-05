-- ===========================================================================
-- AgendaPro — 23: assinatura no cartão, que se renova sozinha
--
-- ── O PROBLEMA QUE ISTO RESOLVE ───────────────────────────────────────────
-- Pix não renova. Todo mês o dono do salão precisa lembrar, abrir o painel,
-- gerar um Pix e pagar. Uma parte simplesmente não faz — e essa parte não sai
-- por insatisfação, sai por atrito. É a pior forma de perder cliente, porque
-- não aparece em lugar nenhum: some.
--
-- As duas funções do fim do 13_cobranca.sql (`assinaturas_a_vencer`,
-- `vencer_cobrancas`) existem para correr atrás desse esquecimento. Elas são
-- o reconhecimento do problema em código.
--
-- ── O DESENHO, E POR QUE ESTE E NÃO O OUTRO ───────────────────────────────
-- Assinaturas do Mercado Pago (pré-aprovação), NÃO tokenização de cartão.
--
-- O dono autoriza uma vez, numa página do próprio Mercado Pago. Nenhum dado
-- de cartão encosta no AgendaPro: não há formulário de cartão no nosso HTML,
-- não há número de cartão passando pelo nosso servidor, e não há nós
-- respondendo se algo vazar. O que volta para cá é um identificador.
--
-- De quebra, quem lida com cartão vencido, cartão trocado, tentativa que
-- falhou e nova tentativa é o Mercado Pago. Essa lista inteira é código que
-- não existe aqui.
--
-- ── O QUE ESTE ARQUIVO REAPROVEITA ────────────────────────────────────────
-- Quase tudo. Uma cobrança recorrente é só mais um pagamento:
--
--   registrar_pagamento()   idempotente pelo mp_id único, confere o valor,
--                           estende vence_em em um mês, e soma ao saldo de
--                           quem paga antes de vencer
--   cobrancas               uma linha por pagamento, com `metodo`
--   webhook-mp              o HMAC e a releitura na API já valem igual
--
-- ── ⚠ O BURACO QUE A AUDITORIA ACHOU ──────────────────────────────────────
-- Na SEGUNDA cobrança do cartão, o Mercado Pago avisa um pagamento que não
-- tem cobrança nossa: `abrir_cobranca()` só roda quando alguém clica, e
-- ninguém clica no mês 2.
--
-- `registrar_pagamento()` responderia `cobranca_desconhecida` e a assinatura
-- NÃO renovaria. O mês 1 funcionaria e o mês 2 falharia em silêncio — defeito
-- que só aparece trinta dias depois, com o salão achando que está em dia.
--
-- É por isso que existe `registrar_recorrencia()` aqui: ela CRIA a linha do
-- mês a partir da pré-aprovação e só então entrega para o caminho que já
-- funciona. A idempotência continua vindo do `mp_id` único, não de lógica
-- nova.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O CARTÃO ENTRA NO DOMÍNIO
-- ---------------------------------------------------------------------------

/* `metodo` era um check de dois valores. Boleto continua aceito de propósito
   — saiu da VENDA, não do histórico, e cobrança antiga precisa continuar
   sendo lida. Ver a nota no abrir_cobranca(). */
alter table public.cobrancas drop constraint if exists cobrancas_metodo_check;
alter table public.cobrancas
  add constraint cobrancas_metodo_check
  check (metodo in ('pix','boleto','cartao'));

/* ── ⚠ A COBRANÇA DE CARTÃO NÃO OCUPA A VAGA DA PENDENTE ──────────────────
   O `ux_cobranca_aberta` garante UMA cobrança pendente por salão. O motivo
   dele está escrito no 13_cobranca.sql, e é sobre o dono CLICANDO: sem o
   índice, cada clique em "Assinar" abria um Pix novo, e ele ficava com seis
   na mão sem saber qual valia.

   Cobrança de cartão não é clicada — é o registro de uma tentativa
   automática. E o teste mostrou o estrago de deixá-la disputar a mesma vaga:
   uma recorrência recusada fica `pendente`, e a cobrança do MÊS SEGUINTE bate
   no índice, a função estoura, o webhook devolve 500, o Mercado Pago reenvia
   para sempre — e a assinatura nunca mais renova.

   Um mês falhando travaria todos os seguintes. O índice passa a valer só para
   o que o dono pode pagar na mão; a de cartão morre sozinha pelo
   `vencer_cobrancas()`. */
drop index if exists public.ux_cobranca_aberta;
create unique index if not exists ux_cobranca_aberta
  on public.cobrancas(salao_id)
  where (status = 'pendente' and metodo <> 'cartao');

/* E pelo mesmo motivo ela não aparece como "pague isto" no painel: não tem
   Pix para copiar nem boleto para abrir, e mostrar uma cobrança que o dono
   não tem como pagar é pedir para ele ligar perguntando o que fazer. */
create or replace function public.minha_cobranca(p_salao uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  return jsonb_build_object(
    'aberta', (
      select to_jsonb(x) from (
        select c.id, c.plano, c.valor, c.metodo, c.vence_em,
               c.pix_copia_cola, c.pix_qr_base64, c.boleto_url, c.linha_digitavel
          from public.cobrancas c
         where c.salao_id = p_salao and c.status = 'pendente'
           and c.metodo <> 'cartao'
           and c.vence_em > now()
         order by c.criada_em desc limit 1) x),
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', h.id, 'plano', h.plano, 'valor', h.valor,
               'metodo', h.metodo, 'status', h.status,
               'pagaEm', h.paga_em, 'criadaEm', h.criada_em)
             order by h.criada_em desc)
        from (select * from public.cobrancas
               where salao_id = p_salao and status in ('paga','devolvida')
               order by criada_em desc limit 12) h), '[]'::jsonb));
end $$;

/* O vínculo com a assinatura recorrente lá no Mercado Pago.

   Fica em `assinaturas` e não em `cobrancas` porque é UM por salão e dura
   enquanto o cartão durar — cobranças são muitas, uma por mês. */
alter table public.assinaturas
  add column if not exists mp_preapproval text;
alter table public.assinaturas
  add column if not exists cartao_desde timestamptz;

/* Único: uma pré-aprovação pertence a um salão só. Sem isto, um aviso
   recorrente casaria com dois salões e estenderia o plano do errado. */
create unique index if not exists ux_assinatura_preapproval
  on public.assinaturas(mp_preapproval)
  where mp_preapproval is not null;

-- ---------------------------------------------------------------------------
-- 2) PEDIR, LIGAR E DESLIGAR O CARTÃO
--
-- Três momentos, e vale reparar em qual deles NÃO liga nada:
--
--   preparar_cartao   o dono clicou. Confere permissão e devolve à borda o
--                     preço e o e-mail do pagador. Não escreve nada.
--   ligar_cartao      o Mercado Pago confirmou a autorização. Só o webhook.
--   cancelar_cartao   o dono desistiu da renovação automática.
-- ---------------------------------------------------------------------------

/* ⚠ POR QUE ISTO EXISTE EM VEZ DE A BORDA MONTAR O PEDIDO SOZINHA.
   Ela precisa de três coisas para falar com o Mercado Pago: se esta pessoa
   pode assinar por este salão, quanto custa o plano, e para qual e-mail
   endereçar a assinatura. As três moram no banco, e as três já têm dono aqui.

   O preço em especial: `transaction_amount` da pré-aprovação é o valor que
   vai ser debitado todo mês, para sempre. Se ele viesse do navegador, o
   checkout seria um formulário onde o cliente escolhe a própria mensalidade —
   e desta vez de forma recorrente. É a mesma regra do `abrir_cobranca()`.

   Ela é `stable` e não escreve: quem escreve é o webhook, depois. */
create or replace function public.preparar_cartao(
  p_salao uuid, p_plano text, p_quem uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_preco numeric(10,2);
  v_nome  text;
  v_pre   text;
  v_pag   jsonb;
begin
  if p_quem is null then
    raise exception 'Assinatura sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.is_super() then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  select preco_mes, nome into v_preco, v_nome
    from public.planos where codigo = p_plano;
  if v_preco is null then
    raise exception 'Plano não encontrado.' using errcode = 'check_violation';
  end if;
  if v_preco <= 0 then
    raise exception 'Este plano não é pago.' using errcode = 'check_violation';
  end if;

  select mp_preapproval into v_pre
    from public.assinaturas where salao_id = p_salao;

  v_pag := public.dados_do_pagador(p_salao);

  /* `jaLigado` é o que faz a borda recusar em vez de criar uma segunda
     pré-aprovação. Duas ativas no mesmo salão é cobrança dobrada todo mês, e
     o dono só descobre na fatura. Trocar de plano no cartão é cancelar e
     assinar de novo — dois cliques, e nenhum deles cobra em duplicidade. */
  return jsonb_build_object(
    'plano',     p_plano,
    'nomePlano', v_nome,
    'valor',     v_preco,
    'email',     v_pag->>'email',
    'nome',      v_pag->>'nome',
    'jaLigado',  v_pre is not null);
end $$;

create or replace function public.ligar_cartao(
  p_salao uuid, p_preapproval text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_dono  uuid;
  v_atual text;
begin
  if p_salao is null or coalesce(p_preapproval,'') = '' then
    raise exception 'Faltou o salão ou a pré-aprovação.'
      using errcode = 'check_violation';
  end if;

  /* ⚠ Uma pré-aprovação já usada por OUTRO salão é sinal de id trocado no
     caminho, não de renovação. Recusa em vez de mover plano alheio. */
  select salao_id into v_dono from public.assinaturas
   where mp_preapproval = p_preapproval;
  if v_dono is not null and v_dono <> p_salao then
    return jsonb_build_object('ok', false, 'motivo', 'preapproval_de_outro');
  end if;

  /* ⚠ E o salão que JÁ TEM uma pré-aprovação não troca por outra por baixo.

     Sobrescrever aqui seria o pior desfecho silencioso do módulo: as duas
     continuam ativas no Mercado Pago, as duas debitam todo mês, e a gente
     perde o identificador da primeira — que é justamente o que a borda
     precisa para cancelá-la. O dono descobre na fatura, e ninguém consegue
     desligar a cobrança que sobrou.

     O mesmo aviso chegando de novo NÃO cai aqui: o Mercado Pago reenvia com o
     mesmo id, e id igual passa direto para o update, que é idempotente. Só id
     DIFERENTE é recusado — e isso a borda já impede antes, no
     `preparar_cartao`. Se chegar mesmo assim, é anomalia, e anomalia tem que
     aparecer no log em vez de virar cobrança dobrada. */
  select mp_preapproval into v_atual from public.assinaturas
   where salao_id = p_salao;
  if v_atual is not null and v_atual <> p_preapproval then
    return jsonb_build_object('ok', false, 'motivo', 'ja_tem_outro');
  end if;

  update public.assinaturas
     set mp_preapproval = p_preapproval,
         cartao_desde   = coalesce(cartao_desde, now()),
         atualizado_em  = now()
   where salao_id = p_salao;

  return jsonb_build_object('ok', true, 'salao', p_salao);
end $$;

/* ⚠ O IDENTIFICADOR DA PRÉ-APROVAÇÃO, PARA A BORDA PODER CANCELAR NA FONTE.

   Cancelar só aqui no banco não cancela nada: quem debita o cartão todo mês é
   o Mercado Pago, e ele não lê a nossa tabela. Um `cancelar_cartao()` sozinho
   daria o pior desfecho possível — o painel dizendo "renovação desligada" e a
   fatura do dono continuando a vir, todo mês, sem nada no sistema explicando.

   Então a ordem é: a borda LÊ o id aqui, cancela lá, e só depois chama o
   `cancelar_cartao()`. Efeito externo primeiro, estado local depois. Se o
   Mercado Pago recusar, nada mudou deste lado e o dono pode tentar de novo —
   não há o que desfazer.

   Ela é separada do `meu_cartao()` de propósito: aquele é a tela do dono e
   NÃO devolve o identificador. Este devolve, e por isso está fechado para o
   navegador. Um `p_quem` inventado no console viraria o id que move a
   assinatura de qualquer salão. */
create or replace function public.cartao_do_salao(p_salao uuid, p_quem uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_pre text;
begin
  if p_quem is null then
    raise exception 'Consulta sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.is_super() then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  select mp_preapproval into v_pre
    from public.assinaturas where salao_id = p_salao;

  return jsonb_build_object(
    'ligado', v_pre is not null, 'preapproval', v_pre);
end $$;

/* Desligar. O plano NÃO cai na hora: o dono pagou o mês, e o mês é dele.
   Cancelar aqui só interrompe a renovação — `vence_em` continua valendo, e
   quando chegar lá a assinatura vence como qualquer outra. */
create or replace function public.cancelar_cartao(p_salao uuid, p_quem uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if p_quem is null then
    raise exception 'Cancelamento sem responsável.' using errcode = 'check_violation';
  end if;
  if not exists (
        select 1 from public.vinculos v
         where v.perfil_id = p_quem and v.salao_id = p_salao
           and v.status = 'ativo' and v.papel in ('dono','admin'))
     and not public.is_super() then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;

  update public.assinaturas
     set mp_preapproval = null,
         cartao_desde   = null,
         atualizado_em  = now()
   where salao_id = p_salao;

  return jsonb_build_object('ok', true);
end $$;

/* ⚠ E QUANDO O CANCELAMENTO VEM DO OUTRO LADO.

   O dono pode cancelar a assinatura dentro da conta dele no Mercado Pago, sem
   passar pelo nosso painel. E o Mercado Pago cancela sozinho depois de
   tentativas demais num cartão que não passa.

   Nos dois casos o débito para e ninguém nos avisa por dentro. Se o
   `mp_preapproval` continuasse preenchido, o `assinaturas_a_vencer()` seguiria
   pulando este salão — "está no cartão, renova sozinho" — e ele venceria em
   silêncio, sem cobrança, sem lembrete e sem ninguém entender por quê. É
   exatamente o silêncio que aquelas funções existem para quebrar.

   Por isso esta é chamada pelo webhook, com o id que veio da API deles, e NÃO
   pede `p_quem`: não há pessoa nenhuma nesse caminho. A permissão dela é ser
   inalcançável de fora — só `service_role`, e só por um identificador que o
   Mercado Pago devolveu. */
create or replace function public.desligar_cartao(p_preapproval text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_salao uuid;
begin
  if coalesce(p_preapproval,'') = '' then
    return jsonb_build_object('ok', false, 'motivo', 'sem_preapproval');
  end if;

  update public.assinaturas
     set mp_preapproval = null,
         cartao_desde   = null,
         atualizado_em  = now()
   where mp_preapproval = p_preapproval
  returning salao_id into v_salao;

  if v_salao is null then
    -- Aviso de uma assinatura que não é deste sistema, ou repetido depois de
    -- já termos desligado. A borda responde 200 assim mesmo.
    return jsonb_build_object('ok', true, 'motivo', 'nada_a_desligar');
  end if;

  return jsonb_build_object('ok', true, 'salao', v_salao);
end $$;

-- ---------------------------------------------------------------------------
-- 3) A COBRANÇA DO MÊS
--
-- ⚠ Esta é a função que o buraco da auditoria exigiu. Ver o cabeçalho.
--
-- O Mercado Pago manda um pagamento por mês, cada um com id próprio, e nenhum
-- deles tem cobrança nossa esperando. Aqui a linha nasce — com o preço lido
-- do PLANO, nunca do aviso — e o resto é o caminho que já existia.
-- ---------------------------------------------------------------------------
create or replace function public.registrar_recorrencia(
  p_preapproval text, p_mp_id text, p_valor numeric, p_status text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.assinaturas;
  v_preco numeric(10,2);
begin
  select * into a from public.assinaturas
   where mp_preapproval = p_preapproval
   for update;

  if not found then
    -- Aviso de uma assinatura que não é deste sistema. A borda responde 200
    -- assim mesmo: 4xx faz o Mercado Pago reenviar para sempre.
    return jsonb_build_object('ok', false, 'motivo', 'preapproval_desconhecida');
  end if;

  /* Já registrado? O mesmo aviso chega várias vezes por desenho. A trava é o
     `mp_id` único da tabela, e conferir aqui evita até criar a linha. */
  if exists (select 1 from public.cobrancas where mp_id = p_mp_id) then
    return jsonb_build_object('ok', true, 'motivo', 'ja_registrada');
  end if;

  select preco_mes into v_preco from public.planos where codigo = a.plano;
  if coalesce(v_preco, 0) <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'plano_sem_preco');
  end if;

  /* ⚠ A linha nasce com o preço do PLANO, e o `registrar_pagamento` logo
     abaixo compara com o que veio da API do Mercado Pago. Se divergirem, ele
     recusa — é a mesma trava que impede pagar R$ 57 e levar o plano de
     R$ 497, agora valendo também para a recorrência. */
  insert into public.cobrancas
    (salao_id, plano, valor, metodo, status, vence_em, mp_id, mp_status)
  values (a.salao_id, a.plano, v_preco, 'cartao', 'pendente',
          now() + interval '7 days', p_mp_id, p_status);

  -- E daqui em diante é o caminho de sempre: ele confere o valor, marca a
  -- cobrança como paga e estende `vence_em` em um mês.
  return public.registrar_pagamento(p_mp_id, p_valor, p_status);
end $$;

-- ---------------------------------------------------------------------------
-- 4) QUEM ESTÁ NO CARTÃO NÃO É COBRADO POR PIX
--
-- Sem isto, o dono que acabou de pôr o cartão receberia, cinco dias antes do
-- vencimento, um aviso pedindo para gerar um Pix — de uma conta que vai ser
-- debitada sozinha. Ele pagaria duas vezes, e a culpa seria nossa.
-- ---------------------------------------------------------------------------
create or replace function public.assinaturas_a_vencer(p_dias int default 5)
returns table (salao_id uuid, salao text, whatsapp text, plano text,
               valor numeric, vence_em date)
language sql security definer set search_path = public as $$
  select a.salao_id, s.nome, s.whatsapp, a.plano, pl.preco_mes, a.vence_em
    from public.assinaturas a
    join public.saloes s  on s.id = a.salao_id
    join public.planos pl on pl.codigo = a.plano
   where a.status = 'ativa'
     and a.vence_em is not null
     and a.vence_em <= current_date + p_dias
     and pl.preco_mes > 0
     -- O cartão renova sozinho. Quem está nele não tem o que fazer.
     and a.mp_preapproval is null
     /* ⚠ E a cobrança de CARTÃO não conta como "já tem uma pendente".
        Este é o terceiro lugar do projeto que precisa da mesma distinção — o
        índice de cobrança aberta e o `minha_cobranca` são os outros dois. A
        regra é sempre a mesma: pendente que o dono PODE PAGAR na mão suprime
        a cobrança; tentativa automática de cartão, não.
        Sem isto, um salão que saiu do cartão com uma recorrência recusada
        atrás ficava invisível na lista de renovação — e vencia sem ninguém
        avisar, que é exatamente o silêncio que estas funções existem para
        quebrar. */
     and not exists (
       select 1 from public.cobrancas c
        where c.salao_id = a.salao_id and c.status = 'pendente'
          and c.metodo <> 'cartao'
          and c.vence_em > now())
   order by a.vence_em;
$$;

-- ---------------------------------------------------------------------------
-- 5) O QUE A TELA PRECISA SABER
--
-- Só leitura, e só do próprio salão. O `mp_preapproval` NÃO sai daqui: é o
-- identificador que move dinheiro no Mercado Pago, e a tela não precisa dele
-- para nada — só precisa saber que existe.
-- ---------------------------------------------------------------------------
create or replace function public.meu_cartao(p_salao uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.assinaturas;
begin
  if not public.e_gestor(p_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;
  select * into a from public.assinaturas where salao_id = p_salao;
  if a.salao_id is null then return jsonb_build_object('ligado', false); end if;

  return jsonb_build_object(
    'ligado',   a.mp_preapproval is not null,
    'desde',    a.cartao_desde,
    'proxima',  a.vence_em,
    'plano',    a.plano);
end $$;

-- ---------------------------------------------------------------------------
-- 6) QUEM PODE CHAMAR O QUÊ
--
-- `ligar_cartao` e `registrar_recorrencia` movem assinatura: só a borda.
-- `cancelar_cartao` e `preparar_cartao` conferem o `p_quem` por dentro, mas
-- quem chama continua sendo a borda — o painel não fala com o banco sobre
-- dinheiro. E `preparar_cartao`, que nem escreve, fica igualmente fechada:
-- ela devolve o e-mail do dono, e um `p_quem` inventado no navegador viraria
-- uma consulta de e-mail de qualquer salão pelo id.
--
-- ⚠ E o `grant ... to service_role` ao lado de cada revoke. Sem ele, o
-- `revoke ... from public` tranca a porta com o carteiro do lado de fora, e
-- o produto responde 42501 em produção sem nenhum teste reprovar. Já
-- aconteceu neste projeto, com oito funções. O `bordas.test.sql` cobra.
-- ---------------------------------------------------------------------------
revoke all on function public.preparar_cartao(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.cartao_do_salao(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ligar_cartao(uuid, text) from public, anon, authenticated;
revoke all on function public.cancelar_cartao(uuid, uuid) from public, anon, authenticated;
revoke all on function public.desligar_cartao(text) from public, anon, authenticated;
revoke all on function public.registrar_recorrencia(text, text, numeric, text)
  from public, anon, authenticated;

grant execute on function public.preparar_cartao(uuid, text, uuid) to service_role;
grant execute on function public.cartao_do_salao(uuid, uuid) to service_role;
grant execute on function public.ligar_cartao(uuid, text) to service_role;
grant execute on function public.cancelar_cartao(uuid, uuid) to service_role;
grant execute on function public.desligar_cartao(text) to service_role;
grant execute on function public.registrar_recorrencia(text, text, numeric, text)
  to service_role;

-- A tela lê a sua própria situação; a função já confere `e_gestor`.
revoke all on function public.meu_cartao(uuid) from public, anon;
grant execute on function public.meu_cartao(uuid) to authenticated, service_role;

comment on function public.registrar_recorrencia(text, text, numeric, text) is
  'A cobrança mensal do cartão: cria a linha do mês e entrega ao registrar_pagamento.';
comment on function public.meu_cartao(uuid) is
  'Se o salão está no cartão e quando é a próxima. Não devolve o id da pré-aprovação.';
