-- ===========================================================================
-- AgendaPro — 29: o salão confirma, ou o link confirma sozinho
--
-- "O cliente receberá uma mensagem de confirmação. Isso é configurável: ou o
--  dono confirma, ou a confirmação é automática assim que o cliente marca."
--
-- ── COMO ERA ──────────────────────────────────────────────────────────────
-- O `agendar()` gravava `'confirmado'` escrito à mão. O status `'pendente'`
-- existia no schema desde o começo e era tratado em todo lugar — `ha_choque`
-- conta ele, o `porque_nao_agenda` conta ele, a cota conta ele — mas NADA
-- NESTE SISTEMA CRIAVA UM. Era uma porta pronta que ninguém abria.
--
-- ── ⚠ E POR QUE NÃO BASTAVA TROCAR A PALAVRA ──────────────────────────────
-- Trocar `'confirmado'` por `'pendente'` no `agendar()` mandaria, no mesmo
-- instante, um WhatsApp dizendo "Seu horário está confirmado" — de um horário
-- que o dono ainda não olhou.
--
-- O `tg_notificar_agendamento()` do 21 dispara no INSERT e aceita os dois
-- status. Então a mudança de verdade é nas duas pontas ao mesmo tempo:
--
--   · o 21 passa a exigir `confirmado` para a confirmação E para o lembrete
--   · este módulo acrescenta o gatilho que falta: quando o horário VIRA
--     confirmado, a mensagem sai naquele momento
--
-- Sem o segundo, o salão confirmaria e a cliente nunca saberia.
--
-- ── O QUE CONTINUA SAINDO NA HORA ─────────────────────────────────────────
-- O aviso para quem vai atender (`tipo = 'novo'`). É ele que avisa o dono de
-- que tem coisa esperando resposta — segurá-lo até a confirmação seria pedir
-- que ele confirmasse algo que ninguém contou que existe.
--
-- ── O HORÁRIO FICA SEGURO ENQUANTO ESPERA ─────────────────────────────────
-- `ha_choque()` no 14 já conta `'pendente'`, então a cadeira fica reservada
-- enquanto o dono decide. Se não contasse, duas pessoas marcariam o mesmo
-- horário durante a espera — e uma delas ouviria "não" depois de já ter
-- combinado o dia.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O INTERRUPTOR
--
-- ⚠ O PADRÃO É AUTOMÁTICO, que é como o sistema sempre funcionou. Se a
-- ausência da chave valesse "o dono confirma", todo salão que já usa o link
-- acordaria amanhã com a agenda cheia de pendências que ninguém pediu — e
-- clientes esperando uma resposta que o dono não sabe que deve dar.
--
-- A peneira é de texto pelo mesmo motivo do 28: `'abacaxi'::boolean` LEVANTA
-- no Postgres, e um cast desprotegido aqui derrubaria TODA marcação do salão.
-- ---------------------------------------------------------------------------
/* ⚠ `security definer`, e a falta dele reprovou a seção 7 do teste.

   A função lê `public.saloes`, e a RLS dessa tabela é para gente com vínculo.
   Rodando como quem chama, `anon` levava `permission denied for table saloes`
   — e quem abre o link da cliente é exatamente `anon`.

   O efeito na tela seria mudo: a chamada falha, o `catch` da página engole, e
   ela cai no padrão "confirma sozinho". A cliente de um salão que confirma à
   mão leria "Pronto, está confirmado" de um horário pendente.

   Não abre nada: a resposta é um sim ou não sobre a política de um salão cujo
   link é público de propósito, e o `p_salao` é o mesmo id que está na URL. */
create or replace function public.confirma_automatico(p_salao uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select lower(btrim(coalesce(sa.cfg->>'confirmaAuto', 'true')))
              not in ('false', 'f', '0', 'no', 'nao', 'não')
       from public.saloes sa where sa.id = p_salao),
    true)
$$;

comment on function public.confirma_automatico(uuid) is
  'O link confirma sozinho? cfg.confirmaAuto, padrão SIM. Desligado, o agendamento nasce pendente e espera o salão.';

-- ---------------------------------------------------------------------------
-- 2) ⚠ A MENSAGEM QUE ESPERAVA O DONO
--
-- Reaproveita a MESMA função do 21, e isso não é economia de linhas: é a
-- garantia de que a confirmação que sai depois é idêntica à que sai na hora.
-- Uma segunda função escrita aqui divergiria da primeira no dia em que alguém
-- mexesse em só uma delas — e ninguém perceberia, porque as duas "funcionam".
--
-- Os três `insert` de lá terminam em `on conflict (salao_id, chave) do
-- nothing`, então rodar de novo não duplica nada. Confirmar duas vezes, ou
-- confirmar um horário que já tinha saído confirmado, não manda dois
-- WhatsApps.
--
-- O `when` faz o trabalho de decidir: só na TRANSIÇÃO para confirmado. Posto
-- na condição do gatilho, e não dentro da função, porque a função é do 21 e
-- não deve saber que este módulo existe.
-- ---------------------------------------------------------------------------
drop trigger if exists tg_notif_agend_confirmado on public.agendamentos;
create trigger tg_notif_agend_confirmado
  after update of status on public.agendamentos
  for each row
  when (new.status = 'confirmado' and old.status is distinct from 'confirmado')
  execute function public.tg_notificar_agendamento();

-- ---------------------------------------------------------------------------
-- 3) Quem pode perguntar
--
-- ⚠ `anon` TAMBÉM, e aqui é diferente do 28. A página da cliente precisa saber
-- ANTES de ela confirmar se o horário vai ficar pendente — é o que decide
-- entre "Pronto, está confirmado" e "Você receberá uma mensagem de
-- confirmação". E quem abre o link não tem conta.
--
-- Não vaza nada: a resposta é um sim ou não sobre a política de um salão cujo
-- link é público de propósito.
-- ---------------------------------------------------------------------------
revoke all on function public.confirma_automatico(uuid) from public;
grant execute on function public.confirma_automatico(uuid) to anon, authenticated;
