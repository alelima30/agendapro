-- ===========================================================================
-- AgendaPro — o que o mundo lá fora consegue chamar
--
-- ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
-- No Postgres, função nova nasce EXECUTÁVEL POR TODO MUNDO. `security definer`
-- passa por cima do RLS de propósito. Juntando as duas coisas sem um `revoke`,
-- o resultado é um buraco pronto — e silencioso, porque nada quebra.
--
-- Aconteceu duas vezes neste projeto, e as duas foram achadas por varredura
-- manual, meses depois:
--
--   texto_resumo(salao, null, dia)   devolvia a AGENDA DO DIA INTEIRA de
--                                    qualquer salão, com nome de cliente,
--                                    sem login. O id do salão sai da própria
--                                    vitrine pública.
--   proximo_numero(salao, nome)      deixava qualquer um ESCREVER: três
--                                    chamadas anônimas levaram o contador de
--                                    comanda de um salão de 1 para 3.
--
-- A causa das duas foi a mesma: eu revoquei umas funções e esqueci outras.
-- Memória não é mecanismo.
--
-- ── COMO ELE DECIDE ────────────────────────────────────────────────────────
-- Lista TODA `security definer` do schema public que o `anon` alcança e exige
-- que cada uma esteja na lista abaixo, escrita à mão e justificada.
--
-- A lista é curta de propósito. Ficar longa é sinal, não conveniência: cada
-- nome aqui é uma porta que dá para a internet sem senha.
--
-- ⚠ AO REPROVAR, A PERGUNTA NÃO É "COMO FAÇO O TESTE PASSAR".
-- É "esta função pode mesmo ser chamada por quem não tem conta?". Quase
-- sempre a resposta é não, e o conserto é um `revoke` no arquivo-fonte —
-- não uma linha nova aqui.
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── O QUE PODE, E POR QUÊ ──────────────────────────────────────────────────
create temporary table porta_aberta (nome text primary key, porque text);
insert into porta_aberta values
  -- A página pública de agendamento. É o produto: a cliente marca sem conta.
  ('vitrine',                 'a página da cliente lê o salão por aqui'),
  ('horarios_livres',         'os horários que a cliente vê'),
  ('horarios_livres_periodo', 'idem, a semana inteira'),
  ('porque_nao_agenda',       'explica à cliente por que o horário não serve'),
  ('agendar',                 'a cliente marcando — o produto inteiro'),
  ('entrar_na_fila',          'a cliente entrando na fila de espera'),

  -- Caminhos por TOKEN: quem tem o link tem o direito, e o token é o segredo.
  ('cancelar_agendamento',    'link de cancelar, mandado à cliente'),
  ('sair_da_fila',            'idem, para a fila'),
  ('meus_agendamentos',       'a cliente vendo os horários dela, por token'),
  ('minha_fila',              'idem'),
  ('ver_convite',             'o convite de equipe, antes de ter conta'),

  -- Cadastro: precisam responder a quem ainda não tem login.
  ('slug_disponivel',         'confere o apelido enquanto a pessoa digita'),
  ('sugerir_slug',            'sugere um apelido no cadastro'),

  -- Só falam sobre QUEM ESTÁ CHAMANDO. Sem sessão devolvem nulo ou falso, e
  -- por isso não contam nada de ninguém.
  ('is_super',                'sobre quem chama'),
  ('papel_no_salao',          'sobre quem chama'),
  ('tem_acesso',              'sobre quem chama'),
  ('e_equipe',                'sobre quem chama'),
  ('e_gestor',                'sobre quem chama'),
  ('ve_agenda_toda',          'sobre quem chama'),
  ('meu_profissional_id',     'sobre quem chama'),
  ('meu_cliente_id',          'sobre quem chama'),
  ('tenho_item_na_comanda',   'sobre quem chama'),

  -- Usadas DENTRO de policies. Se o anon perder o acesso, o RLS quebra.
  ('cliente_da_comanda',      'usada em policy; devolve um id, não dado'),
  ('salao_da_comanda',        'usada em policy; devolve um id, não dado'),
  ('plano_efetivo',           'usada em policy e nos limites'),
  ('limite_profissionais',    'usada nos limites de cota'),
  ('recurso_num',             'usada nos limites de cota'),
  ('recurso_bool',            'usada nos limites de cota'),
  ('profissional_na_cota',    'usada nos limites de cota');

-- ── A CONFERÊNCIA ──────────────────────────────────────────────────────────
-- Gatilho fica de fora: função que devolve `trigger` não é chamável pela API.
do $$
declare r record; sobrando text := '';
begin
  for r in
    select p.proname as nome, pg_get_function_arguments(p.oid) as args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prosecdef
       and pg_get_function_result(p.oid) <> 'trigger'
       and has_function_privilege('anon', p.oid, 'EXECUTE')
       and p.proname not in (select nome from porta_aberta)
     order by 1
  loop
    sobrando := sobrando || E'\n      • ' || r.nome || '(' || r.args || ')';
  end loop;

  if sobrando <> '' then
    perform t_falha(
      'função security definer aberta ao anon sem justificativa:' || sobrando
      || E'\n      → se ela não precisa ser pública, o conserto é um revoke no'
      || ' arquivo-fonte, não um nome novo na lista do portas.test.sql');
  else
    perform t_ok('nenhuma porta aberta ao anon fora da lista');
  end if;
end $$;

-- ── E AS QUE JÁ FORAM BURACO, UMA A UMA ────────────────────────────────────
-- A conferência acima já cobre estas. Elas ficam nomeadas mesmo assim porque
-- um teste genérico que reprova diz "algo mudou"; estes dizem QUAL, e contam
-- o que aconteceu quando aconteceu.
do $$
declare f text;
begin
  foreach f in array array[
    'public.texto_agendamento(uuid,text)',
    'public.texto_resumo(uuid,uuid,date,text)',
    'public.pecas_agendamento(uuid)',
    'public.variaveis_agendamento(uuid,text)']
  loop
    if to_regprocedure(f) is null then
      perform t_falha(f || ' não existe — a busca envelheceu');
    else
      perform t_falso('anon NÃO chama ' || split_part(f, '(', 1),
        has_function_privilege('anon', to_regprocedure(f)::oid, 'EXECUTE'));
      perform t_falso('nem usuário logado chama ' || split_part(f, '(', 1),
        has_function_privilege('authenticated', to_regprocedure(f)::oid, 'EXECUTE'));
    end if;
  end loop;
end $$;

do $$
begin
  perform t_falso('ninguém de fora escreve na numeração de comanda',
    has_function_privilege('anon',
      to_regprocedure('public.proximo_numero(uuid,text)')::oid, 'EXECUTE')
    or has_function_privilege('authenticated',
      to_regprocedure('public.proximo_numero(uuid,text)')::oid, 'EXECUTE'));
  perform t_falso('nem lê o percentual de comissão de ninguém',
    has_function_privilege('anon',
      to_regprocedure('public.comissao_de(text,uuid,uuid,uuid)')::oid, 'EXECUTE')
    or has_function_privilege('authenticated',
      to_regprocedure('public.comissao_de(text,uuid,uuid,uuid)')::oid, 'EXECUTE'));
end $$;

/* ── ⚠ TODO GATILHO PRECISA SER `security definer` ─────────────────────────
   Esta é a verificação que teria evitado o pior erro desta sessão.

   Gatilho sem `security definer` roda como QUEM FEZ A OPERAÇÃO. Então tudo o
   que ele chama precisa estar liberado para o usuário comum — e revogar
   qualquer uma dessas funções quebra o produto na hora.

   Foi exatamente o que aconteceu: `comanda_numera` era o único gatilho sem
   definer do projeto. Eu revoguei a `proximo_numero` de `authenticated`
   afirmando que "gatilho roda como dono", e abrir comanda passou a dar
   `permission denied` — em produção, na mão do dono do salão.

   A afirmação estava certa para 40 gatilhos e errada para um. Este bloco
   troca "eu me lembro" por "o banco responde". */
do $$
declare r record; fora text := '';
begin
  for r in
    select p.proname as nome
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and pg_get_function_result(p.oid) = 'trigger'
       and not p.prosecdef
     order by 1
  loop
    fora := fora || E'\n      • ' || r.nome || '()';
  end loop;

  if fora <> '' then
    perform t_falha(
      'gatilho sem security definer:' || fora
      || E'\n      → ele roda como o usuário, então tudo o que ele chama tem'
      || ' de estar liberado para `authenticated`. Ou põe o definer, ou não'
      || ' revogue nada que ele use.');
  else
    perform t_ok('todo gatilho roda como dono, e não como quem chamou');
  end if;
end $$;

-- ── E O CAMINHO LEGÍTIMO CONTINUA ABERTO ───────────────────────────────────
-- Sem isto, tudo acima ficaria verde com um banco onde ninguém chama nada —
-- e o produto estaria quebrado.
do $$
begin
  perform t_verdade('a cliente ainda alcança a vitrine',
    has_function_privilege('anon',
      to_regprocedure('public.vitrine(text)')::oid, 'EXECUTE'));
  perform t_verdade('e ainda consegue marcar horário',
    has_function_privilege('anon',
      to_regprocedure('public.agendar(uuid,timestamptz,uuid[],text,text,text,text)')::oid,
      'EXECUTE'));
end $$;

-- ── O GATILHO CONTINUA NUMERANDO ───────────────────────────────────────────
-- Revogar `proximo_numero` de todo mundo só é seguro porque o gatilho roda
-- como dono. Isto prova, em vez de supor.
do $$
declare v bigint;
begin
  set local role authenticated;
  begin
    v := public.proximo_numero(gen_random_uuid(), 'x');
    perform t_falha('usuário logado conseguiu chamar proximo_numero direto');
  exception
    when insufficient_privilege then
      perform t_ok('usuário logado leva permission denied ao tentar direto');
    when others then
      perform t_falha('esperava permission denied, veio: ' || sqlerrm);
  end;
  reset role;
end $$;
