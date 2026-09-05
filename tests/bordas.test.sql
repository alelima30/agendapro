-- ===========================================================================
-- AgendaPro — o que as funções de borda precisam alcançar
--
-- ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
-- O `portas.test.sql` guarda um lado: que nada esteja aberto demais. Este
-- guarda o outro: que nada esteja FECHADO demais.
--
-- Os dois erros custam igual, e o segundo é mais difícil de ver — porque não
-- vaza nada, não dá erro em teste nenhum, e só aparece no dia em que o
-- produto roda de verdade.
--
-- ── O QUE ACONTECEU ────────────────────────────────────────────────────────
-- Eu escrevi, em três módulos:
--
--     revoke all on function public.abrir_cobranca(...) from public, anon, authenticated;
--
-- A intenção estava certa: essas funções mexem em dinheiro e em fila, e
-- ninguém logado deve chamá-las direto.
--
-- O que eu não vi é que `revoke ... from public` tira o acesso de TODO MUNDO,
-- inclusive do `service_role` — o papel com que as funções de borda falam com
-- o banco. Ser função de borda não dá privilégio: `service_role` contorna o
-- RLS, não a permissão de EXECUTE.
--
-- Resultado: oito funções trancadas com o carteiro do lado de fora.
--
--   abrir_cobranca, anotar_cobranca, dados_do_pagador   o checkout inteiro
--   registrar_pagamento                                 o webhook do pagamento
--   gerar_resumos, notificacao_proxima/_resultado       o worker do WhatsApp
--   notificacao_status                                  o webhook da Meta
--
-- Descoberto em produção, no primeiro checkout de verdade: 42501,
-- insufficient_privilege, e o painel dizendo "Não consegui abrir a cobrança".
-- O mesmo esperava o worker de mensagens, para o dia da aprovação da Meta —
-- fila cheia e nada saindo.
--
-- ── POR QUE A SUÍTE NÃO PEGOU ──────────────────────────────────────────────
-- Todos os testes de banco chamam como `postgres`, que é superusuário e
-- IGNORA grant. Superusuário nunca leva 42501. Os testes estavam certos sobre
-- o que faziam e cegos para o papel que importa lá fora.
--
-- Este arquivo pergunta pelo papel certo.
-- ===========================================================================

\set ON_ERROR_STOP on

-- ── O QUE CADA FUNÇÃO DE BORDA CHAMA ───────────────────────────────────────
-- A lista sai do `grep "rpc('...')"` nos index.ts. Ao criar função de borda
-- nova, acrescente aqui o que ela chama — é uma linha, e ela vale para
-- sempre.
create temporary table borda_precisa (assinatura text primary key, quem text);
insert into borda_precisa values
  ('public.abrir_cobranca(uuid,text,text,uuid)',                    'criar-cobranca'),
  ('public.anotar_cobranca(uuid,text,text,text,text,text,text)',    'criar-cobranca'),
  ('public.dados_do_pagador(uuid)',                                 'criar-cobranca'),
  ('public.registrar_pagamento(text,numeric,text)',                 'webhook-mp'),
  ('public.gerar_resumos(timestamptz)',                             'enviar-notificacoes'),
  ('public.notificacao_proxima(int)',                               'enviar-notificacoes'),
  ('public.notificacao_resultado(uuid,boolean,text,text,text)',     'enviar-notificacoes'),
  ('public.notificacao_status(text,text,text,text)',                'status-whatsapp'),
  ('public.fila_proxima(int)',                                      'enviar-campanha'),
  ('public.fila_resultado(uuid,boolean,text,text,text,boolean)',    'enviar-campanha'),
  ('public.preparar_cartao(uuid,text,uuid)',                        'assinar-cartao'),
  ('public.cartao_do_salao(uuid,uuid)',                             'cancelar-cartao'),
  ('public.cancelar_cartao(uuid,uuid)',                             'cancelar-cartao'),
  ('public.ligar_cartao(uuid,text)',                                'webhook-mp'),
  ('public.desligar_cartao(text)',                                  'webhook-mp'),
  ('public.registrar_recorrencia(text,text,numeric,text)',          'webhook-mp');

do $$
declare r record; faltando text := '';
begin
  for r in select * from borda_precisa order by quem, assinatura loop
    if to_regprocedure(r.assinatura) is null then
      perform t_falha('a função ' || r.assinatura || ' (usada pela borda '
                      || r.quem || ') não existe — a lista envelheceu');
    elsif not has_function_privilege('service_role',
                                     to_regprocedure(r.assinatura)::oid, 'EXECUTE') then
      faltando := faltando || E'\n      • ' || r.assinatura
               || '   ← ' || r.quem;
    end if;
  end loop;

  if faltando <> '' then
    perform t_falha(
      'a borda NÃO consegue chamar:' || faltando
      || E'\n      → um `revoke ... from public` tirou do service_role junto.'
      || ' Some `grant execute ... to service_role` no arquivo-fonte, ao lado'
      || ' do revoke. Sem isso o produto responde 42501 em produção e nenhum'
      || ' teste reprova.');
  else
    perform t_ok('a borda alcança as ' || (select count(*) from borda_precisa)
                 || ' funções de que precisa');
  end if;
end $$;

-- ── E CONTINUA FECHADO PARA QUEM NÃO É A BORDA ─────────────────────────────
-- Sem esta metade, o conserto do erro acima poderia ser "libera para todo
-- mundo" — que passaria aqui e reabriria os buracos que o portas.test.sql
-- fechou. As duas verificações têm que valer juntas.
do $$
declare r record; abertas text := '';
begin
  for r in
    select assinatura from borda_precisa
     -- A fila da campanha é chamada pelo painel também, quando o dono dispara.
     where assinatura not like 'public.fila_%'
     order by 1
  loop
    if has_function_privilege('anon', to_regprocedure(r.assinatura)::oid, 'EXECUTE')
    or has_function_privilege('authenticated',
                              to_regprocedure(r.assinatura)::oid, 'EXECUTE') then
      abertas := abertas || E'\n      • ' || r.assinatura;
    end if;
  end loop;

  if abertas <> '' then
    perform t_falha('função de borda alcançável por quem não é a borda:'
                    || abertas
                    || E'\n      → estas movem dinheiro e fila. Só service_role.');
  else
    perform t_ok('e nenhuma delas é alcançável por anon ou por usuário logado');
  end if;
end $$;

-- ── O CASO QUE COMEÇOU TUDO, NOMEADO ───────────────────────────────────────
-- A verificação acima já cobre. Esta fica porque um teste genérico diz "algo
-- mudou", e este diz O QUÊ — e conta a história de quando aconteceu.
do $$
begin
  perform t_verdade('o checkout: a borda abre cobrança',
    has_function_privilege('service_role',
      to_regprocedure('public.abrir_cobranca(uuid,text,text,uuid)')::oid, 'EXECUTE'));
  perform t_verdade('o worker: a borda pega a próxima mensagem da fila',
    has_function_privilege('service_role',
      to_regprocedure('public.notificacao_proxima(int)')::oid, 'EXECUTE'));
end $$;
