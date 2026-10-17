-- ===========================================================================
-- 39_teste_unico.sql — o teste grátis é UM por pessoa, não um por cadastro
--
-- A pergunta: "o dono do salão pode excluir a conta, cadastrar de novo e usar
-- 7 dias grátis, e fazer isso direto. O que fazer?"
--
-- ── AS DUAS PORTAS QUE ESTAVAM ABERTAS ────────────────────────────────────
--   1. Excluir e voltar. O "Excluir conta" (36) apaga o login, e com ele o
--      telefone e o e-mail ficam livres. O cadastro novo, com os MESMOS
--      dados, nascia com mais 7 dias.
--   2. Nem precisava excluir: cada salão criado pelo `criar_salao()` (03)
--      ganhava um teste — a mesma conta abria "Salão 2", "Salão 3"… e
--      trocava de casa toda semana.
--
-- ── O QUE MUDA ────────────────────────────────────────────────────────────
-- Quem ganha um teste deixa uma MARCA: o WhatsApp e o e-mail, normalizados e
-- passados por sha256. A marca não pendura em conta nenhuma, então o
-- "Excluir conta" não a leva. No cadastro seguinte com o mesmo WhatsApp ou o
-- mesmo e-mail (inclusive "ana.souza+2@gmail.com" no lugar de
-- "anasouza@gmail.com", e celular com ou sem o nono dígito), o salão nasce
-- no plano Grátis — que é onde o teste vencido cairia de qualquer jeito. A
-- conta é criada normalmente: barrar o cadastro seria perder quem talvez
-- assine; o que não se repete é o presente.
--
-- Exceção é com a plataforma: o "Estender teste" do admin (38) continua
-- dando dias a quem você quiser.
--
-- ── POR QUE HASH, E NÃO O TELEFONE ────────────────────────────────────────
-- Para saber "já usou?" basta comparar, não é preciso guardar o número. O
-- hash é o mínimo necessário (LGPD, art. 6º, III). Mas não é anonimato:
-- telefone tem poucas combinações e o hash pode ser recalculado — por isso
-- a tabela fica fechada a todo mundo, inclusive à própria plataforma pelo
-- navegador, e a Política de privacidade precisa dizer que guardamos esse
-- registro para evitar uso repetido do teste.
--
-- ── O QUE ISTO NÃO PEGA ───────────────────────────────────────────────────
-- Quem volta com OUTRO WhatsApp e OUTRO e-mail. O telefone do dono não é
-- confirmado por código no cadastro; confirmá-lo (ou pedir cartão para
-- começar o teste) é o próximo degrau, se o abuso continuar.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O REGISTRO
-- ---------------------------------------------------------------------------
create table if not exists public.testes_usados (
  marca       text primary key,              -- sha256 de 'tel:…' ou 'email:…'
  tipo        text not null check (tipo in ('telefone', 'email')),
  primeiro_em timestamptz not null default now(),
  ultimo_em   timestamptz not null default now()
);
alter table public.testes_usados enable row level security;
alter table public.testes_usados force row level security;
-- Nenhuma policy, nenhum grant: só as funções abaixo (security definer) leem
-- e escrevem.
revoke all on public.testes_usados from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) A MESMA PESSOA ESCRITA DE OUTRO JEITO
-- ---------------------------------------------------------------------------
/* Só os dígitos, com o 55 quando veio sem país (como o `para_e164()` do 08).
   Celular do Brasil escrito sem o nono dígito (55 + DDD + 8 dígitos
   começando por 6 a 9) ganha o 9: é o mesmo chip. */
create or replace function public.tel_para_teste(p text)
returns text language plpgsql immutable set search_path = public as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if length(d) in (10, 11) then d := '55' || d; end if;
  if length(d) < 8 then return null; end if;
  if length(d) = 12 and left(d, 2) = '55' and substr(d, 5, 1) ~ '[6-9]' then
    d := left(d, 4) || '9' || substr(d, 5);
  end if;
  return d;
end $$;

/* Minúsculas, sem o "+qualquercoisa" antes do @ (vale no Gmail, no Outlook e
   em quase todos), e sem os pontos no Gmail, que os ignora. */
create or replace function public.email_para_teste(p text)
returns text language plpgsql immutable set search_path = public as $$
declare e text := lower(btrim(coalesce(p, ''))); u text; dom text;
begin
  if position('@' in e) = 0 then return null; end if;
  u := split_part(e, '@', 1);
  dom := split_part(e, '@', 2);
  u := split_part(u, '+', 1);
  if dom in ('gmail.com', 'googlemail.com') then
    u := replace(u, '.', '');
    dom := 'gmail.com';
  end if;
  if u = '' or dom = '' then return null; end if;
  return u || '@' || dom;
end $$;

/* As marcas de uma pessoa: o WhatsApp e o e-mail.

   ⚠ O WHATSAPP SAI TAMBÉM DO QUE FOI DIGITADO NO CADASTRO, não só do perfil.
   Telefone que já é de outra conta entra no perfil como NULO (08_conta: o
   cadastro não pode morrer por isso). Olhando só o perfil, bastava manter a
   conta antiga, abrir outra com e-mail novo e o mesmo WhatsApp — o perfil
   novo nascia sem telefone, sem marca, e com mais 7 dias. O número digitado
   fica nos dados da conta (`raw_user_meta_data`) e é dali que ele vem. */
create or replace function public.marcas_de_teste(p_perfil uuid)
returns table (marca text, tipo text)
language sql stable security definer set search_path = public as $$
  select distinct encode(sha256(convert_to(x.chave, 'UTF8')), 'hex'), x.tipo
    from (
      select 'tel:' || public.tel_para_teste(p.telefone) as chave, 'telefone' as tipo
        from public.perfis p where p.id = p_perfil
      union all
      select 'tel:' || public.tel_para_teste(coalesce(u.raw_user_meta_data->>'telefone',
                                                     u.raw_user_meta_data->>'phone')), 'telefone'
        from auth.users u where u.id = p_perfil
      union all
      select 'email:' || public.email_para_teste(p.email), 'email'
        from public.perfis p where p.id = p_perfil
      union all
      select 'email:' || public.email_para_teste(u.email), 'email'
        from auth.users u where u.id = p_perfil
    ) x
   where x.chave is not null
$$;

create or replace function public.ja_usou_teste(p_perfil uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.marcas_de_teste(p_perfil) m
                   join public.testes_usados t on t.marca = m.marca)
$$;

create or replace function public.registrar_teste(p_perfil uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.testes_usados (marca, tipo)
  select m.marca, m.tipo from public.marcas_de_teste(p_perfil) m
  on conflict (marca) do update set ultimo_em = now()
$$;

-- ---------------------------------------------------------------------------
-- 3) ONDE O TESTE NASCE
-- ---------------------------------------------------------------------------
/* Na assinatura, e não dentro do `criar_salao()`: assim qualquer caminho que
   crie um salão em teste passa por aqui, e o 03 continua sendo a única
   versão da função de cadastro.

   O "Grátis" é escrito do jeito que o admin escreve (plano 'gratuito',
   status 'cancelada'): gratuito é a ausência de assinatura, e 'ativa' com
   preço zero leria como "pagando R$ 0". */
create or replace function public.tg_teste_uma_vez()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from 'trial' then return new; end if;
  -- O "Estender teste" e as outras ações da plataforma passam.
  if coalesce(current_setting('agendapro.plataforma', true), '') = 'sim' then return new; end if;
  -- Sem login (SQL Editor, worker) ou a própria plataforma criando salão de
  -- teste: não é cadastro de dono.
  if auth.uid() is null or public.is_super() then return new; end if;

  if public.ja_usou_teste(auth.uid()) then
    new.plano := 'gratuito';
    new.status := 'cancelada';
    new.trial_ate := null;
    new.vence_em := null;
  else
    perform public.registrar_teste(auth.uid());
  end if;
  return new;
end $$;

drop trigger if exists tg_teste_uma_vez on public.assinaturas;
create trigger tg_teste_uma_vez before insert on public.assinaturas
  for each row execute function public.tg_teste_uma_vez();

/* Ao deixar de ser dono (excluir a conta, sair do salão), as marcas de AGORA
   ficam: quem trocou de WhatsApp depois do cadastro deixa os dois. O perfil
   ainda existe neste instante — o `excluir_minha_conta()` tira os vínculos
   antes do login. */
create or replace function public.tg_dono_sai_marca()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.papel = 'dono' then
    perform public.registrar_teste(old.perfil_id);
  end if;
  return null;
end $$;

drop trigger if exists tg_dono_sai_marca on public.vinculos;
create trigger tg_dono_sai_marca after delete on public.vinculos
  for each row execute function public.tg_dono_sai_marca();

-- ---------------------------------------------------------------------------
-- 4) QUEM JÁ É DONO HOJE
-- ---------------------------------------------------------------------------
-- Sem isto, quem já está cadastrado poderia excluir e voltar uma última vez.
-- Rodar de novo não duplica nada.
insert into public.testes_usados (marca, tipo)
select m.marca, m.tipo
  from (select distinct perfil_id from public.vinculos where papel = 'dono') v
  cross join lateral public.marcas_de_teste(v.perfil_id) m
on conflict (marca) do nothing;

-- ---------------------------------------------------------------------------
-- 5) QUEM PODE CHAMAR
-- ---------------------------------------------------------------------------
revoke all on function public.marcas_de_teste(uuid) from public, anon, authenticated;
revoke all on function public.ja_usou_teste(uuid) from public, anon, authenticated;
revoke all on function public.registrar_teste(uuid) from public, anon, authenticated;
revoke all on function public.tg_teste_uma_vez() from public, anon, authenticated;
revoke all on function public.tg_dono_sai_marca() from public, anon, authenticated;
