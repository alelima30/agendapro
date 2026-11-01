-- ===========================================================================
-- 48_cadastro_link.sql — a cliente se cadastra pelo link, sem agendar
--
-- O pedido: "no link tem como a cliente fazer o cadastro sem agendar? Aí ela
-- se cadastra e depois eu coloco ela no pacote." Até aqui, criar a conta no
-- link só LIGAVA a conta a uma ficha que o salão já tivesse com o mesmo
-- WhatsApp (`ligar_minha_ficha`, 09); sem ficha, ela só nascia no primeiro
-- horário marcado. A cliente que se cadastrava para entrar num pacote não
-- aparecia em Clientes.
--
-- Agora, quem cria a conta pelo link do salão (ou abre o link de cadastro,
-- `?cadastro=1`) ganha a ficha naquele salão: nome, WhatsApp e e-mail, com a
-- marca `pelo_link` para o dono saber de onde veio.
--
-- ── SEM DUPLICAR ──────────────────────────────────────────────────────────
-- A mesma regra da ligação: ficha com o mesmo WhatsApp e o mesmo primeiro
-- nome é DELA, e só é ligada. Mesmo WhatsApp com outro nome (mãe e filha no
-- mesmo número, ou um engano) não ganha ficha nova: o telefone já é de outra
-- ficha, e o salão resolve no balcão.
--
-- ── O TETO DO PLANO ───────────────────────────────────────────────────────
-- Conta como qualquer cliente (o gatilho do 22 continua valendo). Passou do
-- teto, a conta dela continua criada — só a ficha não nasce, e a função diz
-- por quê, sem derrubar a tela da cliente.
-- ===========================================================================

alter table public.clientes add column if not exists pelo_link boolean not null default false;

create or replace function public.cadastrar_minha_ficha(p_salao uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_perfil uuid := auth.uid(); v_nome text; v_tel text; v_email text; v_nasc date;
  v_ficha jsonb; v_cliente uuid; v_nacional text;
begin
  if v_perfil is null or p_salao is null then return null; end if;
  if not exists (select 1 from public.saloes s where s.id = p_salao and s.status = 'ativo') then
    return null;
  end if;
  -- Primeiro, o caminho de sempre: a ficha que já é dela, ou a que bate.
  v_ficha := public.ligar_minha_ficha(p_salao);
  if v_ficha->>'ficha' is not null then
    /* A ficha do balcão ganha o que a conta tem e ela não: o aniversário (é
       dele que sai Aniversariantes) e o e-mail. Só o VAZIO — a mesma regra
       do `agendar()` (09): quem manda na ficha é o salão. */
    update public.clientes c
       set nascimento = coalesce(c.nascimento, nullif(v_ficha->>'nascimento', '')::date),
           email      = coalesce(c.email, nullif(btrim(coalesce(v_ficha->>'email', '')), ''))
     where c.id = (v_ficha->>'ficha')::uuid and (c.nascimento is null or c.email is null);
    return v_ficha || jsonb_build_object('criada', false);
  end if;

  select p.nome, p.telefone, p.email, p.nascimento into v_nome, v_tel, v_email, v_nasc
    from public.perfis p where p.id = v_perfil;
  v_nacional := public.telefone_nacional(v_tel);
  if coalesce(v_nacional, '') = '' or length(v_nacional) < 10 or coalesce(btrim(v_nome), '') = '' then
    return v_ficha || jsonb_build_object('criada', false, 'motivo', 'sem_telefone');
  end if;
  -- O WhatsApp já é de outra ficha deste salão (com outro nome): não duplica.
  if exists (select 1 from public.clientes c
              where c.salao_id = p_salao
                and public.telefone_nacional(c.telefone) = v_nacional) then
    return v_ficha || jsonb_build_object('criada', false, 'motivo', 'telefone_de_outra_ficha');
  end if;

  begin
    insert into public.clientes (salao_id, perfil_id, nome, telefone, email, nascimento, pelo_link)
         values (p_salao, v_perfil, btrim(v_nome), v_nacional, v_email, v_nasc, true)
      returning id into v_cliente;
  exception when check_violation or unique_violation then
    -- O teto do plano (22) ou uma corrida com outra ficha: a conta fica.
    return v_ficha || jsonb_build_object('criada', false, 'motivo', 'nao_coube');
  end;
  return v_ficha || jsonb_build_object('ficha', v_cliente, 'criada', true);
end $$;

revoke all on function public.cadastrar_minha_ficha(uuid) from public, anon;
grant execute on function public.cadastrar_minha_ficha(uuid) to authenticated;
