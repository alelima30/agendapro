-- ===========================================================================
-- 46_adicionais.sql — os módulos adicionais, que se pagam à parte
--
-- O pedido: o Crediário (venda parcelada, o "fiado") é um módulo a mais —
-- "preciso amarrar para cobrar do dono do salão". R$ 49,90 por mês, do
-- Essencial para cima (no Básico não), liberado no teste grátis.
--
-- Até aqui cada plano liberava os seus módulos e a mensalidade era o preço do
-- plano. Agora a mensalidade é PLANO + ADICIONAIS, e a trava de módulo
-- (`recurso_bool`, `exigir_recurso`) aceita "o plano inclui" OU "contratou o
-- adicional". O mesmo desenho serve para os próximos (cartão fidelidade,
-- ficha com fotos…): é uma linha no catálogo.
--
-- ── AS REGRAS DO DONO ─────────────────────────────────────────────────────
--   · contratou com a assinatura em dia, num plano que aceita: LIBERA NA
--     HORA e entra na próxima mensalidade;
--   · inadimplente: "regularize a mensalidade primeiro";
--   · no Básico ou no teste: fica AGUARDANDO e entra junto com a mensalidade
--     de um plano que aceita ("Mudar para o Essencial + Crediário");
--   · cancelou: vale até o próximo vencimento (o mês já pago é dele); depois
--     as parcelas abertas continuam, só não se vende fiado novo — a regra de
--     quem desce de plano;
--   · recontratar depois de vencido: só libera quando a mensalidade com ele
--     for paga (sem "usa um mês de graça, cancela e repete");
--   · a plataforma dá cortesia e preço especial.
--
-- ── ⚠ O VALOR NUNCA VEM DA TELA, E O CARTÃO TEM QUE SABER ─────────────────
-- Como o plano (13): o preço é lido daqui no servidor. E quem paga no cartão
-- tem o valor guardado no Mercado Pago — mudar o adicional muda o valor LÁ,
-- pela função de borda `adicional`, ANTES de gravar aqui (efeito externo
-- primeiro, como o `cancelar-cartao`). Por isso a mudança tem duas metades:
-- `preparar_adicional` (só conta, não grava) e `aplicar_adicional` (grava, e
-- confere que a conta não mudou no meio). As duas são só da borda.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O CATÁLOGO
-- ---------------------------------------------------------------------------
create table if not exists public.adicionais (
  codigo     text primary key,
  nome       text not null,
  descricao  text not null default '',
  preco_mes  numeric(10,2) not null check (preco_mes > 0),
  -- A chave de `recursos` que ele libera (a mesma que o `exigir_recurso` pede).
  recurso    text not null,
  -- Em quais planos ele pode ser contratado.
  planos     text[] not null default '{}',
  -- O que vem junto (as 200 mensagens próprias do Crediário, por exemplo).
  recursos   jsonb not null default '{}'::jsonb,
  ativo      boolean not null default true,
  ordem      smallint not null default 0
);

-- Preço e planos são decisão comercial: colar de novo não reseta. O nome e a
-- chave voltam sempre (como os planos, no 22).
--
-- ⚠ NASCE FORA DA VENDA (`ativo = false`). A cobrança vem antes das telas do
-- Crediário: com ele à venda agora, o dono contrataria — e pagaria — um
-- módulo que ainda não tem tela. Quem põe à venda é o módulo do Crediário em
-- si, quando as telas existirem; colar este de novo não tira da venda.
insert into public.adicionais (codigo, nome, descricao, preco_mes, recurso, planos, recursos, ativo, ordem)
values ('crediario', 'Crediário',
        'Venda parcelada no fiado, com as parcelas, o "a receber" e a cobrança no WhatsApp.',
        49.90, 'crediario', array['individual', 'duo', 'time', 'equipe', 'salao'],
        '{"mensagens_crediario": 200}'::jsonb, false, 1)
on conflict (codigo) do update
  set nome = excluded.nome, descricao = excluded.descricao, recurso = excluded.recurso;

-- No teste grátis, o Crediário vem liberado: é para experimentar e querer.
update public.planos set recursos = recursos || '{"crediario": true}'::jsonb
 where codigo = 'trial';

-- O catálogo: quem está logado lê (o preço aparece no painel). Quem não
-- entrou não alcança tabela nenhuma (02_rls.test) — só `planos`, por decisão.
alter table public.adicionais enable row level security;
drop policy if exists adicionais_ler on public.adicionais;
create policy adicionais_ler on public.adicionais for select to authenticated using (true);
revoke all on public.adicionais from anon, authenticated;
grant select on public.adicionais to authenticated;

-- ---------------------------------------------------------------------------
-- 2) O QUE CADA SALÃO CONTRATOU
--
--   ativo       valendo (e entra na mensalidade, se não for cortesia)
--   aguardando  pedido, mas só vale quando a mensalidade com ele for paga
--   cancelado   saiu; vale até `vale_ate` (o mês que já estava pago)
-- ---------------------------------------------------------------------------
create table if not exists public.salao_adicionais (
  salao_id       uuid not null references public.saloes(id) on delete cascade,
  adicional      text not null references public.adicionais(codigo),
  status         text not null check (status in ('ativo', 'aguardando', 'cancelado')),
  desde          timestamptz not null default now(),
  ativo_desde    timestamptz,
  cancelado_em   timestamptz,
  vale_ate       date,
  -- A plataforma deu: vale sem entrar na mensalidade.
  cortesia       boolean not null default false,
  -- O preço deste salão (a plataforma decide). Nulo: o do catálogo.
  preco_especial numeric(10,2) check (preco_especial is null or preco_especial >= 0),
  -- Já teve e cancelou: recontratar só libera depois de pagar.
  ja_teve        boolean not null default false,
  atualizado_em  timestamptz not null default now(),
  primary key (salao_id, adicional)
);

-- Preço e estado são conta do dono: a gestão lê. Ninguém escreve pela API.
alter table public.salao_adicionais enable row level security;
drop policy if exists salao_adicionais_ler on public.salao_adicionais;
create policy salao_adicionais_ler on public.salao_adicionais
  for select to authenticated using (public.e_gestor(salao_id) or public.is_super());
revoke all on public.salao_adicionais from anon, authenticated;
grant select on public.salao_adicionais to authenticated;

-- ---------------------------------------------------------------------------
-- 3) ESTÁ VALENDO?
--
-- A assinatura precisa estar em vigor num plano que aceita o adicional
-- (`plano_efetivo`: vencida vira Grátis, e o adicional para junto). A
-- cortesia vale em qualquer plano — é decisão da plataforma.
-- ---------------------------------------------------------------------------
create or replace function public.adicional_ativo(p_salao uuid, p_adicional text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.salao_adicionais sa
      join public.adicionais ad on ad.codigo = sa.adicional
     where sa.salao_id = p_salao and sa.adicional = p_adicional
       and ((sa.cortesia and sa.status = 'ativo')
            or (public.plano_efetivo(p_salao) = any(ad.planos)
                and (sa.status = 'ativo'
                     or (sa.status = 'cancelado' and sa.vale_ate >= current_date)))))
$$;

-- A trava de módulo: o plano inclui, OU um adicional ativo libera a chave.
create or replace function public.recurso_bool(p_salao uuid, p_chave text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select (pl.recursos ->> p_chave)::boolean
                     from public.planos pl where pl.codigo = public.plano_efetivo(p_salao)), false)
      or exists (select 1 from public.adicionais ad
                  where ad.recurso = p_chave and public.adicional_ativo(p_salao, ad.codigo))
$$;

/* A recusa diz onde está: módulo de plano é "a partir do Básico" (como
   antes); módulo adicional é "contrate em Meu plano", com o plano mínimo. */
create or replace function public.exigir_recurso(p_salao uuid, p_chave text, p_nome text)
returns void language plpgsql stable set search_path = public as $$
declare v_nome text; v_minimo text;
begin
  if coalesce(public.recurso_bool(p_salao, p_chave), false) then return; end if;
  -- O catálogo é de quem está logado: chamada sem login (dentro de um
  -- caminho que não é `security definer`) só perde a frase do adicional.
  begin
    select ad.nome,
           (select pl.nome from public.planos pl where pl.codigo = any(ad.planos)
             order by pl.preco_mes, pl.ordem limit 1)
      into v_nome, v_minimo
      from public.adicionais ad where ad.recurso = p_chave order by ad.ordem limit 1;
  exception when insufficient_privilege then v_nome := null;
  end;
  if v_nome is not null then
    raise exception '% faz parte do módulo adicional %, a partir do plano %. Contrate em Meu plano.',
      p_nome, v_nome, coalesce(v_minimo, 'Essencial')
      using errcode = 'check_violation';
  end if;
  raise exception '% está disponível a partir do plano Básico.', p_nome
    using errcode = 'check_violation';
end $$;

-- ---------------------------------------------------------------------------
-- 4) A MENSALIDADE: O PLANO E OS ADICIONAIS
--
-- Os itens que uma mensalidade daquele plano cobra: o plano (com o preço
-- especial do salão, 13) e cada adicional ativo ou aguardando que o plano
-- aceita, sem cortesia. É daqui que o Pix, o cartão e o lembrete de
-- renovação tiram o valor — e a cobrança guarda os itens, para o histórico
-- dizer o que foi pago.
-- ---------------------------------------------------------------------------
create or replace function public.itens_da_mensalidade(p_salao uuid, p_plano text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_array(jsonb_build_object('tipo', 'plano', 'codigo', p_plano,
           'nome', (select pl.nome from public.planos pl where pl.codigo = p_plano),
           'valor', public.preco_do_plano(p_salao, p_plano)))
      || coalesce((select jsonb_agg(jsonb_build_object('tipo', 'adicional', 'codigo', ad.codigo,
                     'nome', ad.nome, 'valor', coalesce(sa.preco_especial, ad.preco_mes))
                     order by ad.ordem)
                     from public.salao_adicionais sa join public.adicionais ad on ad.codigo = sa.adicional
                    where sa.salao_id = p_salao and sa.status in ('ativo', 'aguardando')
                      and not sa.cortesia and p_plano = any(ad.planos)
                      and coalesce(sa.preco_especial, ad.preco_mes) > 0), '[]'::jsonb)
$$;

create or replace function public.soma_dos_itens(p_itens jsonb)
returns numeric language sql immutable set search_path = public as $$
  select case when exists (select 1 from jsonb_array_elements(p_itens) x
                            where x->>'tipo' = 'plano' and x->'valor' = 'null'::jsonb)
              then null
              else (select coalesce(sum((x->>'valor')::numeric), 0)::numeric(10,2)
                      from jsonb_array_elements(p_itens) x) end
$$;

create or replace function public.valor_da_mensalidade(p_salao uuid, p_plano text)
returns numeric language sql stable security definer set search_path = public as $$
  select public.soma_dos_itens(public.itens_da_mensalidade(p_salao, p_plano))
$$;

/* ⚠ A COBRANÇA DO CARTÃO É LIDA COMO O MERCADO PAGO COBROU.

   O valor do cartão mora lá, e muda pela borda `adicional` no mesmo momento
   em que muda aqui — mas "no mesmo momento" são duas chamadas. Se uma falhar
   no meio (a borda tenta desfazer, e desfazer também pode falhar), o débito
   do mês chega com um valor que não é o de agora. Recusar seria o plano do
   dono vencer em silêncio, com o cartão debitado.

   Então o mês do cartão aceita três composições, nesta ordem: a mensalidade
   de agora; só o plano; o plano com todos os adicionais que o salão tem. A
   que bater é a que vale — e o que foi PAGO passa a valer (`adicionais_pagos`):
   pagou o Crediário, tem o Crediário. Valor que não bate com nenhuma continua
   recusado, como sempre (é a trava contra pagar R$ 57 e levar R$ 497). */
create or replace function public.itens_que_batem(p_salao uuid, p_plano text, p_valor numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_agora jsonb; v_so jsonb; v_todos jsonb;
begin
  v_agora := public.itens_da_mensalidade(p_salao, p_plano);
  if public.soma_dos_itens(v_agora) = p_valor then return v_agora; end if;
  v_so := jsonb_build_array(v_agora->0);
  if public.soma_dos_itens(v_so) = p_valor then return v_so; end if;
  v_todos := v_so || coalesce((select jsonb_agg(jsonb_build_object('tipo', 'adicional',
                 'codigo', ad.codigo, 'nome', ad.nome, 'valor', coalesce(sa.preco_especial, ad.preco_mes))
                 order by ad.ordem)
                 from public.salao_adicionais sa join public.adicionais ad on ad.codigo = sa.adicional
                where sa.salao_id = p_salao and not sa.cortesia and p_plano = any(ad.planos)
                  and coalesce(sa.preco_especial, ad.preco_mes) > 0), '[]'::jsonb);
  if public.soma_dos_itens(v_todos) = p_valor then return v_todos; end if;
  return v_agora;
end $$;

/* O que um pagamento confirmado faz com os adicionais. Chamada pelo
   `registrar_pagamento` (13), depois de estender a assinatura.

     · os que vieram na mensalidade paga passam a valer (ou continuam);
     · os que o plano pago não aceita (desceu para o Básico) param — sem
       cortesia, que é da plataforma;
     · os que ficaram de fora mas o plano aceita (a cobrança era de antes de
       contratar) continuam: entram na próxima. */
create or replace function public.adicionais_pagos(p_salao uuid, p_plano text, p_itens jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.salao_adicionais sa
     set status = 'ativo', vale_ate = null, cancelado_em = null,
         ativo_desde = case when sa.status = 'ativo' then sa.ativo_desde else now() end,
         atualizado_em = now()
   where sa.salao_id = p_salao
     and sa.adicional in (select x->>'codigo' from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) x
                           where x->>'tipo' = 'adicional');
  update public.salao_adicionais sa
     set status = 'cancelado', vale_ate = current_date, cancelado_em = now(),
         ja_teve = true, atualizado_em = now()
    from public.adicionais ad
   where ad.codigo = sa.adicional and sa.salao_id = p_salao
     and sa.status = 'ativo' and not sa.cortesia and not (p_plano = any(ad.planos));
end $$;

-- O lembrete de renovação por Pix diz o valor de verdade (plano + adicionais).
-- Refeita aqui porque é `language sql` e depende das funções acima.
create or replace function public.assinaturas_a_vencer(p_dias int default 5)
returns table (salao_id uuid, salao text, whatsapp text, plano text,
               valor numeric, vence_em date)
language sql security definer set search_path = public as $$
  select a.salao_id, s.nome, s.whatsapp, a.plano,
         public.valor_da_mensalidade(a.salao_id, a.plano), a.vence_em
    from public.assinaturas a
    join public.saloes s  on s.id = a.salao_id
    join public.planos pl on pl.codigo = a.plano
   where a.status = 'ativa'
     and a.vence_em is not null
     and a.vence_em <= current_date + p_dias
     and pl.preco_mes > 0
     and a.mp_preapproval is null
     and not exists (
       select 1 from public.cobrancas c
        where c.salao_id = a.salao_id and c.status = 'pendente'
          and c.metodo <> 'cartao'
          and c.vence_em > now())
   order by a.vence_em;
$$;

-- ---------------------------------------------------------------------------
-- 5) CONTRATAR, CANCELAR, CORTESIA, PREÇO
--
-- `conta_do_adicional` decide o que acontece e quanto a mensalidade passa a
-- ser, sem gravar nada. As ações:
--   contratar | cancelar           o dono ou o administrador do salão
--   cortesia | sem_cortesia | preco   a plataforma
-- `p_quem` é quem pediu, conferido aqui (a borda roda sem sessão: o mesmo
-- motivo do `abrir_cobranca`, 13).
-- ---------------------------------------------------------------------------
create or replace function public.conta_do_adicional(
  p_salao uuid, p_adicional text, p_acao text, p_quem uuid, p_preco numeric default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  ad public.adicionais%rowtype; r public.salao_adicionais%rowtype; a public.assinaturas%rowtype;
  v_super boolean; v_em_dia boolean; v_trial boolean; v_aceita boolean;
  n jsonb; v_efeito text; v_antes numeric; v_depois numeric; v_contrib_r numeric; v_contrib_n numeric;
begin
  if p_quem is null then
    raise exception 'Pedido sem responsável.' using errcode = 'check_violation';
  end if;
  v_super := coalesce((select pf.super_admin from public.perfis pf where pf.id = p_quem), false);
  if p_acao in ('contratar', 'cancelar') then
    if not v_super and not exists (
         select 1 from public.vinculos v
          where v.perfil_id = p_quem and v.salao_id = p_salao
            and v.status = 'ativo' and v.papel in ('dono', 'admin')) then
      raise exception 'Só o proprietário ou um administrador contrata módulos.'
        using errcode = 'insufficient_privilege';
    end if;
  elsif p_acao in ('cortesia', 'sem_cortesia', 'preco') then
    if not v_super then
      raise exception 'Só a plataforma dá cortesia ou preço especial.'
        using errcode = 'insufficient_privilege';
    end if;
  else
    raise exception 'Ação desconhecida.' using errcode = 'check_violation';
  end if;

  select * into ad from public.adicionais where codigo = p_adicional;
  if ad.codigo is null then
    raise exception 'Módulo não encontrado.' using errcode = 'check_violation';
  end if;
  select * into a from public.assinaturas where salao_id = p_salao;
  if a.salao_id is null then
    raise exception 'Este salão não tem assinatura.' using errcode = 'check_violation';
  end if;
  select * into r from public.salao_adicionais where salao_id = p_salao and adicional = p_adicional;

  v_em_dia := a.status = 'ativa' and (a.vence_em is null or a.vence_em >= current_date);
  v_trial  := public.plano_efetivo(p_salao) = 'trial';
  v_aceita := a.plano = any(ad.planos);

  -- O estado de agora, de onde o novo parte.
  n := jsonb_build_object('status', r.status, 'cortesia', coalesce(r.cortesia, false),
         'preco_especial', r.preco_especial, 'vale_ate', r.vale_ate, 'ja_teve', coalesce(r.ja_teve, false));

  if p_acao = 'contratar' then
    if not ad.ativo then
      raise exception 'Este módulo não está à venda.' using errcode = 'check_violation';
    end if;
    if r.status in ('ativo', 'aguardando') then
      v_efeito := 'ja_contratado';
    elsif r.status = 'cancelado' and r.vale_ate >= current_date and v_em_dia and v_aceita then
      -- Cancelou e voltou atrás dentro do mês que já estava pago.
      n := n || jsonb_build_object('status', 'ativo', 'vale_ate', null);
      v_efeito := 'voltou';
    elsif not v_em_dia and not v_trial then
      raise exception 'Regularize a mensalidade primeiro: com ela em dia, o módulo é liberado na hora.'
        using errcode = 'check_violation';
    elsif v_em_dia and v_aceita and not coalesce(r.ja_teve, false) then
      n := n || jsonb_build_object('status', 'ativo', 'vale_ate', null);
      v_efeito := 'liberado';
    elsif v_em_dia and v_aceita then
      n := n || jsonb_build_object('status', 'aguardando', 'vale_ate', null);
      v_efeito := 'aguarda_pagamento';
    else
      -- No Básico ou no teste: entra com a mensalidade de um plano que aceita.
      n := n || jsonb_build_object('status', 'aguardando', 'vale_ate', null);
      v_efeito := 'aguarda_plano';
    end if;

  elsif p_acao = 'cancelar' then
    if r.status is null or r.status = 'cancelado' then
      v_efeito := 'ja_cancelado';
    elsif r.status = 'aguardando' then
      n := n || jsonb_build_object('status', 'cancelado', 'vale_ate', null);
      v_efeito := 'desistiu';
    else
      n := n || jsonb_build_object('status', 'cancelado', 'ja_teve', true,
             'vale_ate', greatest(coalesce(a.vence_em, current_date), current_date));
      v_efeito := 'cancelado';
    end if;

  elsif p_acao = 'cortesia' then
    n := n || jsonb_build_object('status', 'ativo', 'cortesia', true, 'vale_ate', null);
    v_efeito := 'cortesia';

  elsif p_acao = 'sem_cortesia' then
    if not coalesce(r.cortesia, false) then
      v_efeito := 'sem_mudanca';
    elsif v_em_dia and v_aceita then
      n := n || jsonb_build_object('cortesia', false);           -- passa a ser cobrado
      v_efeito := 'cobrado';
    else
      n := n || jsonb_build_object('cortesia', false, 'status', 'cancelado', 'vale_ate', current_date);
      v_efeito := 'encerrado';
    end if;

  else  -- preco
    if p_preco is not null and p_preco < 0 then
      raise exception 'Preço não pode ser negativo.' using errcode = 'check_violation';
    end if;
    n := n || jsonb_build_object('preco_especial', round(p_preco, 2),
                                 'status', coalesce(r.status, 'cancelado'));
    v_efeito := 'preco';
  end if;

  -- Quanto este adicional pesa na mensalidade, antes e depois.
  v_contrib_r := case when r.status in ('ativo', 'aguardando') and not coalesce(r.cortesia, false) and v_aceita
                      then greatest(coalesce(r.preco_especial, ad.preco_mes), 0) else 0 end;
  v_contrib_n := case when n->>'status' in ('ativo', 'aguardando') and not (n->>'cortesia')::boolean and v_aceita
                      then greatest(coalesce((n->>'preco_especial')::numeric, ad.preco_mes), 0) else 0 end;
  v_antes := coalesce(public.valor_da_mensalidade(p_salao, a.plano), 0);
  v_depois := v_antes - v_contrib_r + v_contrib_n;

  return jsonb_build_object(
    'efeito', v_efeito,
    'mudou', v_efeito not in ('ja_contratado', 'ja_cancelado', 'sem_mudanca'),
    'novo', n,
    'antes', v_antes, 'depois', v_depois,
    'proxima', a.vence_em, 'plano', a.plano,
    'preapproval', a.mp_preapproval,
    'nome', ad.nome, 'preco', coalesce(r.preco_especial, ad.preco_mes));
end $$;

-- Para a borda: a conta, com o id do cartão (que nunca vai para a tela).
create or replace function public.preparar_adicional(
  p_salao uuid, p_adicional text, p_acao text, p_quem uuid, p_preco numeric default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select public.conta_do_adicional(p_salao, p_adicional, p_acao, p_quem, p_preco) - 'novo'
$$;

-- Para a tela: a mesma conta, para o "sua mensalidade passa de… para…",
-- sem o id do cartão. Quem pergunta é a sessão.
create or replace function public.simular_adicional(p_salao uuid, p_adicional text, p_acao text)
returns jsonb language sql stable security definer set search_path = public as $$
  select (public.conta_do_adicional(p_salao, p_adicional, p_acao, auth.uid()) - 'novo' - 'preapproval')
         || jsonb_build_object('cartao', exists (select 1 from public.assinaturas a
                                                  where a.salao_id = p_salao and a.mp_preapproval is not null))
$$;

/* Gravar. A borda já mudou o valor no cartão para `p_esperado`; se a conta
   de agora não der o mesmo número (alguém mexeu no meio), recusa — e a
   borda desfaz lá. */
create or replace function public.aplicar_adicional(
  p_salao uuid, p_adicional text, p_acao text, p_quem uuid,
  p_preco numeric default null, p_esperado numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c jsonb; n jsonb;
begin
  -- Um salão por vez: duas abas contratando ao mesmo tempo esperam a fila.
  perform 1 from public.assinaturas where salao_id = p_salao for update;
  c := public.conta_do_adicional(p_salao, p_adicional, p_acao, p_quem, p_preco);
  if p_esperado is not null and (c->>'depois')::numeric is distinct from p_esperado then
    raise exception 'A mensalidade mudou enquanto você confirmava. Abra Meu plano de novo.'
      using errcode = 'check_violation';
  end if;
  if not (c->>'mudou')::boolean then
    return jsonb_build_object('ok', true, 'efeito', c->>'efeito', 'mensalidade', (c->>'antes')::numeric);
  end if;
  n := c->'novo';

  insert into public.salao_adicionais as sa
    (salao_id, adicional, status, cortesia, preco_especial, vale_ate, ja_teve,
     desde, ativo_desde, cancelado_em, atualizado_em)
  values (p_salao, p_adicional, n->>'status', (n->>'cortesia')::boolean,
          (n->>'preco_especial')::numeric, (n->>'vale_ate')::date, (n->>'ja_teve')::boolean,
          now(), case when n->>'status' = 'ativo' then now() end,
          case when n->>'status' = 'cancelado' then now() end, now())
  on conflict (salao_id, adicional) do update
    set status         = excluded.status,
        cortesia       = excluded.cortesia,
        preco_especial = excluded.preco_especial,
        vale_ate       = excluded.vale_ate,
        ja_teve        = excluded.ja_teve,
        desde          = case when p_acao = 'contratar' then now() else sa.desde end,
        ativo_desde    = case when excluded.status = 'ativo' and sa.status <> 'ativo' then now()
                              when excluded.status = 'ativo' then sa.ativo_desde end,
        cancelado_em   = case when excluded.status = 'cancelado' and sa.status <> 'cancelado' then now()
                              when excluded.status = 'cancelado' then sa.cancelado_em end,
        atualizado_em  = now();

  /* A mensalidade mudou: o Pix que estava aberto é do valor velho. Sai do
     caminho, e o próximo nasce certo. (Pago assim mesmo, vale: o
     `registrar_pagamento` credita o plano, e o adicional entra no outro.) */
  if (c->>'antes')::numeric is distinct from (c->>'depois')::numeric then
    update public.cobrancas set status = 'cancelada'
     where salao_id = p_salao and status = 'pendente' and metodo <> 'cartao';
  end if;

  return jsonb_build_object('ok', true, 'efeito', c->>'efeito',
    'status', n->>'status', 'valeAte', n->>'vale_ate',
    'mensalidade', (c->>'depois')::numeric, 'proxima', c->>'proxima');
end $$;

-- ---------------------------------------------------------------------------
-- 6) O QUE A TELA PRECISA SABER
--
-- A equipe recebe só quais módulos estão valendo (para a tela não oferecer o
-- que o banco recusa). A gestão recebe o catálogo, os preços e a mensalidade.
-- ---------------------------------------------------------------------------
create or replace function public.meus_adicionais(p_salao uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.assinaturas%rowtype; v_ativos jsonb; v_recursos jsonb;
begin
  if not public.e_equipe(p_salao) and not public.is_super() then
    raise exception 'Sem permissão neste salão.' using errcode = 'insufficient_privilege';
  end if;
  select coalesce(jsonb_agg(ad.codigo order by ad.ordem), '[]'::jsonb),
         coalesce(jsonb_agg(ad.recurso order by ad.ordem), '[]'::jsonb)
    into v_ativos, v_recursos
    from public.adicionais ad where public.adicional_ativo(p_salao, ad.codigo);
  if not public.e_gestor(p_salao) and not public.is_super() then
    return jsonb_build_object('ativos', v_ativos, 'recursos', v_recursos);
  end if;

  select * into a from public.assinaturas where salao_id = p_salao;
  return jsonb_build_object(
    'ativos', v_ativos, 'recursos', v_recursos,
    'plano', a.plano,
    'emDia', a.status = 'ativa' and (a.vence_em is null or a.vence_em >= current_date),
    'teste', public.plano_efetivo(p_salao) = 'trial',
    'proxima', a.vence_em,
    'cartao', a.mp_preapproval is not null,
    'mensalidade', public.valor_da_mensalidade(p_salao, a.plano),
    'itens', public.itens_da_mensalidade(p_salao, a.plano),
    'catalogo', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', ad.codigo, 'nome', ad.nome, 'descricao', ad.descricao,
               'preco', coalesce(sa.preco_especial, ad.preco_mes), 'precoNormal', ad.preco_mes,
               'planos', to_jsonb(ad.planos),
               'planoMinimo', (select pl.nome from public.planos pl where pl.codigo = any(ad.planos)
                                order by pl.preco_mes, pl.ordem limit 1),
               'aceitaMeuPlano', a.plano = any(ad.planos),
               'status', sa.status, 'ativo', public.adicional_ativo(p_salao, ad.codigo),
               'valeAte', sa.vale_ate, 'cortesia', coalesce(sa.cortesia, false),
               'jaTeve', coalesce(sa.ja_teve, false))
             order by ad.ordem)
        from public.adicionais ad
        left join public.salao_adicionais sa on sa.salao_id = p_salao and sa.adicional = ad.codigo
       where ad.ativo or sa.status is not null), '[]'::jsonb));
end $$;

-- A plataforma: quem tem o quê, e quanto os adicionais rendem por mês.
create or replace function public.adicionais_da_plataforma()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_super() then
    raise exception 'Só a plataforma vê os adicionais de todos.' using errcode = 'insufficient_privilege';
  end if;
  return jsonb_build_object(
    'catalogo', coalesce((select jsonb_agg(jsonb_build_object('codigo', codigo, 'nome', nome,
                  'preco', preco_mes, 'ativo', ativo) order by ordem) from public.adicionais), '[]'::jsonb),
    'saloes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'salaoId', sa.salao_id, 'salao', s.nome, 'adicional', sa.adicional, 'nome', ad.nome,
               'status', sa.status, 'ativo', public.adicional_ativo(sa.salao_id, sa.adicional),
               'cortesia', sa.cortesia, 'preco', coalesce(sa.preco_especial, ad.preco_mes),
               'precoEspecial', sa.preco_especial, 'valeAte', sa.vale_ate, 'desde', sa.desde)
             order by s.nome)
        from public.salao_adicionais sa
        join public.saloes s on s.id = sa.salao_id
        join public.adicionais ad on ad.codigo = sa.adicional), '[]'::jsonb),
    'receitaMes', coalesce((
      select sum(coalesce(sa.preco_especial, ad.preco_mes))
        from public.salao_adicionais sa join public.adicionais ad on ad.codigo = sa.adicional
       where sa.status = 'ativo' and not sa.cortesia
         and public.adicional_ativo(sa.salao_id, sa.adicional)), 0));
end $$;

-- ---------------------------------------------------------------------------
-- 7) QUEM CHAMA
-- ---------------------------------------------------------------------------
revoke all on function public.adicional_ativo(uuid, text) from public, anon, authenticated;
revoke all on function public.itens_da_mensalidade(uuid, text) from public, anon, authenticated;
revoke all on function public.valor_da_mensalidade(uuid, text) from public, anon, authenticated;
revoke all on function public.itens_que_batem(uuid, text, numeric) from public, anon, authenticated;
revoke all on function public.adicionais_pagos(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.conta_do_adicional(uuid, text, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public.assinaturas_a_vencer(int) from public, anon, authenticated;
-- As duas metades da mudança: só a borda `adicional` (bordas.test.sql cobra).
revoke all on function public.preparar_adicional(uuid, text, text, uuid, numeric) from public, anon, authenticated;
revoke all on function public.aplicar_adicional(uuid, text, text, uuid, numeric, numeric) from public, anon, authenticated;
grant execute on function public.preparar_adicional(uuid, text, text, uuid, numeric) to service_role;
grant execute on function public.aplicar_adicional(uuid, text, text, uuid, numeric, numeric) to service_role;
-- A tela: a própria conta e a própria situação (as funções conferem a sessão).
revoke all on function public.simular_adicional(uuid, text, text) from public, anon;
revoke all on function public.meus_adicionais(uuid) from public, anon;
revoke all on function public.adicionais_da_plataforma() from public, anon;
grant execute on function public.simular_adicional(uuid, text, text) to authenticated;
grant execute on function public.meus_adicionais(uuid) to authenticated;
grant execute on function public.adicionais_da_plataforma() to authenticated;
