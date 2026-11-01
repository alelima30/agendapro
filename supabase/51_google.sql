-- ===========================================================================
-- 51_google.sql — entrar com a conta Google: completar o cadastro
--
-- O pedido: "é possível fazer o cadastro com o Google?". O login em si é do
-- Supabase Auth (o provedor Google ligado no painel do Supabase, com o
-- Client ID e o Client Secret do Google Cloud — que NUNCA passam por aqui
-- nem pelo navegador). O que o Google entrega é só nome e e-mail.
--
-- E o salão precisa do WhatsApp (é por ele que a ficha é achada e que as
-- mensagens chegam) e do aniversário (Aniversariantes). Então, na primeira
-- vez, a tela pede os dois — e esta função os grava no perfil de quem está
-- logado. Depois disso o caminho é o de sempre: `cadastrar_minha_ficha`
-- (48) liga ou cria a ficha no salão, sem duplicar.
--
-- ── AS REGRAS ─────────────────────────────────────────────────────────────
--   · só a própria pessoa, logada;
--   · o WhatsApp que já é de OUTRA conta não é tomado (o índice único do
--     perfil não deixa, e a frase diz o que fazer: entrar com aquela conta);
--   · o perfil que já tem WhatsApp não troca por aqui;
--   · o aniversário só preenche o vazio (data impossível é recusada).
-- ===========================================================================

create or replace function public.completar_meu_cadastro(
  p_telefone text, p_nascimento date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_eu uuid := auth.uid(); v_tel text; p public.perfis%rowtype;
begin
  if v_eu is null then
    raise exception 'Entre de novo para completar o cadastro.' using errcode = 'insufficient_privilege';
  end if;
  select * into p from public.perfis where id = v_eu;
  if p.id is null then
    raise exception 'Não achei a sua conta. Entre de novo.' using errcode = 'check_violation';
  end if;
  if p_nascimento is not null and (p_nascimento > current_date or p_nascimento < date '1900-01-01') then
    raise exception 'Confira a data do aniversário.' using errcode = 'check_violation';
  end if;

  if p.telefone is null then
    v_tel := public.para_e164(p_telefone);
    if v_tel is null or length(public.so_digitos(v_tel)) < 12 then
      raise exception 'Falta o WhatsApp com DDD.' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.perfis o where o.telefone = v_tel and o.id <> v_eu) then
      raise exception 'Este WhatsApp já está em outra conta. Entre com o e-mail e a senha dela, ou fale com o salão.'
        using errcode = 'check_violation';
    end if;
    update public.perfis set telefone = v_tel where id = v_eu;
  end if;
  update public.perfis set nascimento = coalesce(nascimento, p_nascimento) where id = v_eu;

  select * into p from public.perfis where id = v_eu;
  return jsonb_build_object('nome', p.nome, 'telefone', p.telefone, 'email', p.email,
                            'nascimento', p.nascimento);
end $$;

revoke all on function public.completar_meu_cadastro(text, date) from public, anon;
grant execute on function public.completar_meu_cadastro(text, date) to authenticated;
