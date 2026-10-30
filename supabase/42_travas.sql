-- ===========================================================================
-- 42_travas.sql — o que a auditoria de segurança achou, fechado no banco
--
-- O pedido: "conferir a segurança do meu app". A auditoria passou por todas
-- as tabelas, todas as funções que se chamam de fora, as funções do servidor
-- e as fotos. Quase tudo já estava trancado. Três portas não:
--
--   1. a dona de um salão SUSPENSO pela plataforma se reativava sozinha:
--      `salao_gerir` deixa a gestão editar a linha do salão, e a coluna
--      `status` ia junto — pela API, sem passar pela tela;
--   2. qualquer conta lia a linha INTEIRA de qualquer salão (o `cfg` todo):
--      virar "cliente" de um salão é um insert livre (`vinc_virar_cliente`,
--      é o que o link faz), e `tem_acesso()` conta a cliente;
--   3. `porque_nao_cabe()` dizia nome de cliente e motivo de bloqueio a
--      qualquer conta logada — essa é fechada no próprio 14_motor.sql.
--
-- Os outros achados (o painel dentro de um quadro de outro site, o e-mail na
-- tela de entrar) são das páginas, e não daqui.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O STATUS DO SALÃO É DA PLATAFORMA
--
-- Ativo, suspenso, cancelado: quem decide é a `definir_status_salao()`, que
-- só a plataforma chama. A data de criação vai junto: é histórico, e o painel
-- da plataforma lê. Pela internet (anon/authenticated), sem ser a plataforma,
-- as duas não mudam. O SQL Editor, o worker e o service_role passam (o `role`
-- deles não é anon nem authenticated), como passam no modo suporte (38).
-- ---------------------------------------------------------------------------
create or replace function public.tg_salao_campos_da_plataforma()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('role', true), 'none') not in ('anon', 'authenticated')
     or public.is_super()
     or coalesce(current_setting('agendapro.plataforma', true), '') = 'sim' then
    return new;
  end if;
  if new.status is distinct from old.status then
    raise exception 'Só a plataforma muda a situação do salão (ativo, suspenso ou cancelado).'
      using errcode = 'insufficient_privilege';
  end if;
  if new.criado_em is distinct from old.criado_em then
    raise exception 'A data de criação do salão não muda.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end $$;

drop trigger if exists tg_salao_campos_da_plataforma on public.saloes;
create trigger tg_salao_campos_da_plataforma
  before update on public.saloes
  for each row execute function public.tg_salao_campos_da_plataforma();

revoke all on function public.tg_salao_campos_da_plataforma() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) A LINHA DO SALÃO É DA EQUIPE
--
-- A cliente lê o salão pela `vitrine()`, que escolhe campo por campo o que a
-- página mostra — e diz por quê: o `cfg` é jsonb, cresce, e devolvê-lo por
-- atacado é um vazamento esperando a próxima chave. A tabela, então, fica
-- com quem trabalha no salão (e a plataforma, que o `e_equipe()` já inclui).
-- Nenhuma página da cliente lê a tabela: o `salaoPorSlug()` do dados.js
-- também passa pela vitrine.
-- ---------------------------------------------------------------------------
drop policy if exists salao_ler on public.saloes;
create policy salao_ler on public.saloes for select to authenticated
  using ( public.e_equipe(id) );
