-- ===========================================================================
-- 36_excluir_conta.sql — o botão "Excluir conta"
--
-- O pedido: "colocar um botão excluir conta é necessário também" — e, na
-- escolha entre guardar por um tempo ou apagar, "apaga tudo na hora".
--
-- ── O QUE ACONTECE, POR PAPEL ─────────────────────────────────────────────
--   · DONA, e a ÚNICA dona ativa do salão: o salão inteiro vai junto — agenda,
--     clientes, serviços, equipe, caixa, campanhas, cobranças. Não fica nada
--     para "desfazer", e a tela diz isso antes, com o nome de cada salão.
--   · Dona de um salão que tem OUTRA dona ativa: o salão fica com a outra; sai
--     só o vínculo de quem excluiu.
--   · Equipe (profissional, recepção, gerente): sai o login. O salão é de
--     outra pessoa e continua inteiro; o que ela fez lá (quem marcou, quem
--     abriu o caixa) fica sem o nome — as colunas `*_por` são `set null`.
--   · Cliente que entrou pelo link: sai o login. A ficha dela é do SALÃO
--     (nome e telefone que o salão cadastrou), e `clientes.perfil_id` é
--     `set null`: a ficha fica, desligada da conta.
--
-- ── ⚠ UM `DELETE FROM SALOES` SOZINHO NÃO BASTA — MEDIDO ──────────────────
-- Tudo do salão pendura em `saloes` com `on delete cascade`, mas quatro
-- chaves no caminho são `restrict`. Três delas ligam vizinhos do MESMO nível
-- (agendamentos → clientes e profissionais, comandas → clientes), e essas a
-- cascata resolve sozinha. A quarta não:
--
--     agendamento_servicos.servico_id → servicos   (restrict)
--
-- O item do atendimento mora DOIS níveis abaixo do salão (salão →
-- agendamento → item), e o serviço, um só. A cascata apaga o serviço antes de
-- descer até o item, e o Postgres recusa: «update or delete on table
-- "servicos" violates foreign key constraint
-- "agendamento_servicos_servico_id_fkey"». Foi exatamente o que o
-- `excluir-conta.test.mjs` mostrou quando esta linha saiu. Então os itens
-- saem primeiro, à mão, e o resto vai na cascata — inclusive a comanda
-- FECHADA, cujo gatilho de "não mexa" não acha mais a comanda quando os
-- itens dela saem.
--
-- ── ⚠ O CARTÃO TEM DE ESTAR DESLIGADO ANTES ──────────────────────────────
-- A renovação automática mora no Mercado Pago. Apagar o salão aqui com a
-- assinatura ligada lá deixaria o cartão sendo cobrado todo mês por um salão
-- que não existe mais — e sem tela nenhuma para desligar. O painel desliga
-- primeiro (pela borda `cancelar-cartao`, que só limpa o nosso lado depois de
-- o Mercado Pago confirmar); este arquivo RECUSA se ainda estiver ligado.
-- Não confiar só na tela é a regra da casa.
--
-- ── AS FOTOS ─────────────────────────────────────────────────────────────
-- Moram no Storage, e o Supabase não deixa apagar arquivo do Storage por SQL
-- (só pela API dele). Quem apaga a pasta do salão é o painel, ANTES de chamar
-- esta função — enquanto ainda é gestor, que é o que a policy `img_apagar`
-- exige. Depois daqui ele já não teria permissão.
-- ===========================================================================

/* O que a exclusão vai fazer, para a tela mostrar ANTES de pedir o EXCLUIR:
   os estabelecimentos em que a pessoa TRABALHA, um por linha, dizendo se o
   salão vai junto (`apaga`) e se tem cartão ligado. A regra de "sou a única
   dona" mora aqui, e não na tela, para que o aviso e a exclusão nunca
   discordem.

   ⚠ O VÍNCULO DE CLIENTE NÃO ENTRA. Quem entra pelo link ganha um vínculo
   `cliente` com o salão (01_schema), e ele não é "administrar" nada: contado
   aqui, a cliente que quisesse excluir a conta pelo link seria mandada ao
   painel de um salão que não é dela. Ele sai junto na exclusão, como todos.

   Agrupado por salão: a mesma pessoa pode ser dona E profissional no mesmo
   lugar (a chave do vínculo inclui o papel), e o salão apareceria duas vezes. */
create or replace function public.o_que_excluir_apaga()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'salao_id', x.salao_id, 'nome', x.nome, 'papel', x.papel,
           'apaga', x.apaga, 'cartao', x.cartao) order by x.nome), '[]'::jsonb)
    from (select v.salao_id, s.nome,
                 case when bool_or(v.papel = 'dono') then 'dono' else min(v.papel) end as papel,
                 bool_or(v.papel = 'dono') and not exists (
                   select 1 from public.vinculos o
                    where o.salao_id = v.salao_id and o.papel = 'dono'
                      and o.status = 'ativo' and o.perfil_id <> auth.uid()) as apaga,
                 coalesce((select a.mp_preapproval is not null
                             from public.assinaturas a
                            where a.salao_id = v.salao_id), false) as cartao
            from public.vinculos v
            join public.saloes s on s.id = v.salao_id
           where v.perfil_id = auth.uid() and v.status = 'ativo' and v.papel <> 'cliente'
           group by v.salao_id, s.nome) x
$$;
revoke all on function public.o_que_excluir_apaga() from public, anon;
grant execute on function public.o_que_excluir_apaga() to authenticated;

/* Um salão inteiro: os itens dos atendimentos primeiro, e a cascata leva o
   resto (ver o topo). Interna — ninguém de fora chama isto, só a
   `excluir_minha_conta()`, que já conferiu quem é e o que pode. */
create or replace function public.apagar_salao_inteiro(p_salao uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.agendamento_servicos s
   using public.agendamentos a
   where s.agendamento_id = a.id and a.salao_id = p_salao;
  delete from public.saloes where id = p_salao;
end $$;
revoke all on function public.apagar_salao_inteiro(uuid) from public, anon, authenticated;

create or replace function public.excluir_minha_conta(p_confirmacao text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_eu     uuid := auth.uid();
  v_salao  uuid;
  v_feitos int := 0;
begin
  if v_eu is null then
    raise exception 'Entre na sua conta para excluí-la.'
      using errcode = 'insufficient_privilege';
  end if;
  /* A palavra é conferida AQUI, e não só na tela: um clique torto, ou uma
     chamada direta à API, não apaga um salão inteiro. */
  if upper(btrim(coalesce(p_confirmacao, ''))) <> 'EXCLUIR' then
    raise exception 'Para excluir a conta, digite EXCLUIR.'
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from jsonb_array_elements(public.o_que_excluir_apaga()) x
              where (x->>'apaga')::boolean and (x->>'cartao')::boolean) then
    raise exception 'A renovação automática no cartão ainda está ligada. Desligue em Meu plano antes de excluir a conta — senão o cartão continuaria sendo cobrado.'
      using errcode = 'check_violation';
  end if;

  for v_salao in
    select (x->>'salao_id')::uuid
      from jsonb_array_elements(public.o_que_excluir_apaga()) x
     where (x->>'apaga')::boolean
  loop
    perform public.apagar_salao_inteiro(v_salao);
    v_feitos := v_feitos + 1;
  end loop;

  delete from public.vinculos where perfil_id = v_eu;
  /* O login. `perfis` vai junto (cascade), e tudo o que apontava para o
     perfil em salões de OUTRAS pessoas fica sem o nome (set null). */
  delete from auth.users where id = v_eu;

  return jsonb_build_object('ok', true, 'saloes_apagados', v_feitos);
end $$;
revoke all on function public.excluir_minha_conta(text) from public, anon;
grant execute on function public.excluir_minha_conta(text) to authenticated;
