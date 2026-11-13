-- ===========================================================================
-- 57_plano_fechado.sql — a consulta do plano deixa de ser pública
--
-- ── O QUE ESTAVA ABERTO ───────────────────────────────────────────────────
-- `plano_efetivo(salao)` respondia a QUALQUER UM, sem login, qual plano um
-- salão paga. O id do salão não é segredo: sai da própria vitrine pública.
-- Então bastava abrir o link de um concorrente e perguntar ao banco:
--
--     plano_efetivo(id)            → 'gratuito', 'basico', 'salao'...
--     recurso_bool(id, 'caixa')    → tem ou não tem o módulo
--     recurso_num(id, 'mensagens_mes'), limite_profissionais(id)
--
-- E, com uma conta qualquer (criar conta é grátis): `mensagens_no_mes(id)`,
-- quantas mensagens o salão mandou este mês; `pode_enviar(id)`, se ele já
-- bateu na franquia; `teto_mensagens(id)` e `usa_comanda(id)`.
--
-- Nada disso vazava cliente, agenda ou dinheiro — é "que plano o vizinho
-- assina e quanto ele usa". Mas é informação comercial do salão, e ninguém
-- de fora tem por que saber.
--
-- ── POR QUE ESTAVAM ABERTAS ───────────────────────────────────────────────
-- O portas.test.sql as justificava assim: "usada em policy e nos limites".
-- Era verdade no começo do projeto e deixou de ser: hoje nenhuma policy as
-- cita, e TODO caminho que chega nelas passa antes por uma função ou por um
-- gatilho `security definer` — que roda como o dono do banco, não como quem
-- chamou. Conferido no próprio banco (pg_proc, pg_policies, pg_views) antes
-- de fechar, e pela bateria inteira depois.
--
-- As três que não são `security definer` (`exigir_recurso`, `teto_mensagens`
-- e `usa_comanda`) só são chamadas de dentro de quem é. E nenhuma tela chama
-- nenhuma delas: o painel lê o plano pelo `plano_do_salao()`, pelo
-- `uso_do_plano()` e pela vista `minha_assinatura`, que conferem quem pede.
--
-- ── A QUE FICA ABERTA, E POR QUÊ ──────────────────────────────────────────
-- `profissional_na_cota(prof)` continua: a vista pública
-- `profissionais_publicos` a usa no filtro, e função dentro de vista roda
-- com a permissão de QUEM CONSULTA (só as tabelas é que usam a do dono).
-- Fechá-la apagaria a equipe inteira do link. E ela não conta nada que o
-- link já não mostre: quem está na cota é exatamente quem aparece lá.
--
-- ── POR NOME, E NÃO POR ASSINATURA ────────────────────────────────────────
-- O laço fecha TODA função com estes nomes, com os argumentos que tiver. Um
-- banco que veio sendo atualizado pode guardar uma versão antiga com outra
-- assinatura, e um `revoke` escrito para a assinatura de hoje a deixaria
-- aberta sem ninguém notar.
--
-- O `grant ... to service_role` vem junto de propósito: no Supabase o
-- `service_role` (o worker de mensagens) recebe o direito por padrão, mas
-- num banco em que ele só herdava do `public` o revoke o deixaria de fora.
-- ===========================================================================

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as funcao
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('plano_efetivo', 'limite_profissionais',
                         'recurso_num', 'recurso_bool', 'exigir_recurso',
                         'teto_mensagens', 'usa_comanda',
                         'mensagens_no_mes', 'pode_enviar')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.funcao);
    execute format('grant execute on function %s to service_role', r.funcao);
  end loop;
end $$;
