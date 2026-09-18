-- ===========================================================================
-- AgendaPro — 09: a cliente mexe no que é dela
--
-- ── O PROBLEMA ─────────────────────────────────────────────────────────────
-- Marcar não pede identificação, e está certo: atrito na primeira vez custa
-- cliente, e o estrago de uma marcação falsa é pequeno. Mas VER, CANCELAR e
-- REMARCAR mexem em dado de alguém. Sem prova de identidade, bastaria saber o
-- telefone da vizinha para cancelar o corte dela.
--
-- A prova óbvia seria um código por SMS. Ela custa um provedor de SMS, uma
-- Edge Function e um contrato — e sem nada disso a tela ficava mostrando um
-- código simulado, que é pior que não ter: parece verificação e não é.
--
-- ── A PROVA QUE NÃO PRECISA DE SMS ─────────────────────────────────────────
-- Quando alguém marca, o banco devolve um SEGREDO daquela marcação. Quem tem
-- o segredo é quem marcou — ninguém mais o viu passar. O navegador guarda, e
-- é com ele que a pessoa vê, cancela ou remarca.
--
-- É o mesmo desenho do "gerenciar sua reserva" de companhia aérea e hotel, e
-- ele tem três propriedades que importam aqui:
--
--   · não dá para adivinhar: uuid v4 tem 122 bits de acaso;
--   · não dá para enumerar: saber o telefone, o nome ou o id do salão não
--     ajuda em nada;
--   · funciona no WhatsApp: o mesmo link vai na mensagem de confirmação, e
--     aí a pessoa gerencia do celular dela mesmo depois de limpar o
--     navegador.
--
-- O que ele NÃO faz: não junta as marcações de vários aparelhos. Quem marcou
-- no computador do trabalho e quer cancelar do celular precisa do link. É uma
-- limitação honesta — e o dia em que houver SMS, ela cai.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O segredo
--
-- Coluna nova nas duas tabelas em que a cliente mexe. `default` cobre as
-- linhas que já existem e as que entrarem por outro caminho — inclusive as
-- que a recepção criar pelo painel, que assim também podem ser gerenciadas
-- pela cliente se o salão mandar o link.
-- ---------------------------------------------------------------------------
alter table public.agendamentos
  add column if not exists gerenciar_token uuid not null default gen_random_uuid();

alter table public.lista_espera
  add column if not exists gerenciar_token uuid not null default gen_random_uuid();

-- Sem índice, cancelar vira varredura na tabela inteira de agendamentos da
-- plataforma. Único porque o segredo é a chave: dois iguais seriam duas
-- pessoas mexendo na mesma marcação.
create unique index if not exists ix_agend_token on public.agendamentos (gerenciar_token);
create unique index if not exists ix_espera_token on public.lista_espera (gerenciar_token);

-- ---------------------------------------------------------------------------
-- 1b) O CPF da cliente
--
-- `clientes` já tinha nome, telefone, e-mail e nascimento. O CPF entra ao lado
-- deles, como coluna de verdade e não dentro do `ficha` jsonb: ele identifica
-- pessoa, e o `ficha` é para o que é livre por natureza — fórmula de cor,
-- preferência, alerta.
--
-- ⚠ SEM `check`, E SEM ÍNDICE ÚNICO. Os dois seriam defensáveis no papel e
-- caros aqui:
--
--   · um `check` de onze dígitos derruba a gravação INTEIRA da tela quando
--     um CPF malformado escapa por qualquer caminho — e este projeto já
--     pagou esse preço uma vez, com um campo opcional em branco derrubando o
--     cadastro todo. Quem garante o formato é a normalização nos dois pontos
--     de escrita: aqui no `agendar()` e no painel;
--
--   · um índice único por salão recusaria a marcação quando duas fichas
--     acabassem com o mesmo CPF — e a recusa cairia sobre a CLIENTE, no
--     meio de marcar, por causa de uma duplicidade de cadastro que é do
--     salão resolver. Ficha repetida é problema de cadastro, não motivo para
--     alguém não conseguir marcar um corte.
-- ---------------------------------------------------------------------------
alter table public.clientes add column if not exists cpf text;

-- ---------------------------------------------------------------------------
-- 2) agendar() passa a devolver o segredo, e a receber a ficha
--
-- Mudar o que uma função devolve exige derrubá-la antes: `create or replace`
-- recusa alterar o tipo de retorno.
--
-- ⚠ E O DROP TAMBÉM É O QUE IMPEDE DUAS `agendar()` VIVAS AO MESMO TEMPO.
--
-- No Postgres, acrescentar parâmetro — mesmo com `default` — não altera a
-- função: cria uma SOBRECARGA. Sem os drops, o banco acumularia uma
-- `agendar()` por versão — a de sete argumentos do 05_agenda.sql, a de nove
-- de quando entrou o cadastro, a de dez de agora — todas liberadas para o
-- anon ao mesmo tempo, e qual delas o PostgREST escolhe depende dos nomes
-- que o navegador mandar. Uma página velha em cache continuaria marcando
-- pela antiga, que ignora o cadastro inteiro — e o que a cliente preencheu
-- sumiria sem erro nenhum, que é o pior jeito de sumir.
--
-- Por isso os drops são CUMULATIVOS: cada assinatura que já existiu continua
-- listada aqui para sempre. Tirar uma da lista, um dia, é deixar viva a
-- sobrecarga que ela derrubava — num banco que já estava instalado.
-- ---------------------------------------------------------------------------
-- A de sete (do 05_agenda.sql) e a de nove (a versão anterior deste arquivo).
-- As duas caem, sempre, para nunca sobrar sobrecarga viva.
drop function if exists public.agendar(uuid, timestamptz, uuid[], text, text, text, text);
drop function if exists public.agendar(uuid, timestamptz, uuid[], text, text, text, text,
                                       text, date);

create or replace function public.agendar(
  p_profissional  uuid,
  p_inicio        timestamptz,
  p_servicos      uuid[],
  p_nome          text,
  p_telefone      text,
  p_atendido_nome text default null,
  p_obs           text default null,
  p_email         text default null,
  p_nascimento    date default null,
  p_cpf           text default null)
returns table (id uuid, inicio timestamptz, fim timestamptz, valor numeric,
               token uuid)
language plpgsql security definer set search_path = public as $$
declare
  v_salao    uuid;
  v_fuso     text;
  v_data     date;
  v_motivo   text;
  v_duracao  int;
  v_tel      text;
  v_nome     text;
  v_cliente  uuid;
  v_perfil   uuid;
  v_agend    uuid;
  v_token    uuid;
  v_fim      timestamptz;
  v_valor    numeric(10,2);
  v_abertos  int;
  v_quem     text;
  v_ordem    smallint := 1;
  v_pacote   uuid;
  s          record;
begin
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  v_tel  := public.so_digitos(p_telefone);

  if v_nome is null then
    raise exception 'Diga seu nome para a gente saber quem esperar.'
      using errcode = 'check_violation';
  end if;

  if v_tel is null or length(v_tel) < 10 or length(v_tel) > 13 then
    raise exception 'Confira o telefone: precisa do DDD.'
      using errcode = 'check_violation';
  end if;

  select p.salao_id, sa.fuso into v_salao, v_fuso
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional;

  if v_salao is null then
    raise exception 'Este profissional não está atendendo pela agenda online.'
      using errcode = 'check_violation';
  end if;

  v_data := (p_inicio at time zone v_fuso)::date;

  v_motivo := public.porque_nao_agenda(p_profissional, v_data, p_servicos);
  if v_motivo is not null then
    raise exception '%', v_motivo using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from public.horarios_livres(p_profissional, v_data, p_servicos) h
     where h = p_inicio)
  then
    raise exception 'Esse horário não está mais livre. Escolha outro, por favor.'
      using errcode = 'check_violation';
  end if;

  v_duracao := public.duracao_dos_servicos(p_profissional, p_servicos);
  v_valor   := public.preco_dos_servicos(p_profissional, p_servicos);
  v_fim     := p_inicio + make_interval(mins => v_duracao);

  v_perfil := auth.uid();

  -- Uma função só para as três chamadas — ver `ficha_do_cliente()` no
  -- 05_agenda.sql. Aqui estava a terceira cópia da busca só-por-telefone,
  -- e era ESTA a que rodava: o 09 substitui o agendar() do 05.
  v_cliente := public.ficha_do_cliente(v_salao, v_nome, v_tel);

  /* ══════════════════════════════════════════════════════════════════════
     O CADASTRO QUE A CLIENTE PREENCHEU

     O link pede e-mail e aniversário antes de confirmar. Eles chegam aqui e
     pousam na ficha — que é o único lugar onde servem para alguma coisa: o
     salão abre a ficha e vê, e o aniversário do mês sai de `nascimento`.

     ⚠ `is null` NAS DUAS PONTAS, E ESSA É A REGRA INTEIRA.

     Só preenche o que está VAZIO. Nunca corrige, nunca apaga:

       · a recepção pode ter arrumado um e-mail digitado errado, e o
         preenchimento automático do navegador da cliente mandaria o errado
         de volta na marcação seguinte — a correção do salão duraria até o
         próximo corte;

       · campo em branco no formulário não pode zerar o que já estava lá.
         `coalesce` sozinho não bastaria: `nullif(btrim(...), '')` é o que
         transforma "  " em null antes de a conta começar.

     Quem manda na ficha é o salão. A cliente só preenche o que falta.
     ══════════════════════════════════════════════════════════════════════ */
  /* ⚠ O CPF É NORMALIZADO AQUI, E CPF TORTO É IGNORADO EM SILÊNCIO.

     Guardado só se sobrarem exatamente onze dígitos. Não há `check` na
     coluna de propósito (o motivo está lá em cima, na seção 1b), então esta
     linha é o que garante que o que entra na coluna tem forma de CPF.

     E o que não tem é DESCARTADO, nunca recusado: o campo é opcional, a tela
     já avisou quem digitou errado, e derrubar a marcação inteira por causa
     dele seria cobrar da cliente o preço de um campo que ela nem precisava
     preencher. Marcar o corte é o que importa; o CPF é acessório. */
  update public.clientes c
     set email      = coalesce(c.email, nullif(btrim(coalesce(p_email, '')), '')),
         nascimento = coalesce(c.nascimento, p_nascimento),
         cpf        = coalesce(c.cpf,
                        case when public.so_digitos(p_cpf) ~ '^[0-9]{11}$'
                             then public.so_digitos(p_cpf) end)
   where c.id = v_cliente
     and (c.email is null or c.nascimento is null or c.cpf is null);

  /* QUEM DE FATO VEM, quando o nome informado não é o da ficha.

     A ficha é reencontrada pelo telefone, e sem SMS não há prova de que o
     número seja de quem digitou. Se alguém marca com o número da mãe, o
     horário cai na ficha da mãe — e o salão liga para a mãe perguntando de
     um horário que ela não marcou.

     Não dá para impedir sem verificar o número de verdade. Dá para o salão
     saber: o nome informado fica registrado em `atendido_nome`, que o painel
     mostra como "Quem vem". Melhor um nome a mais na tela do que um telefone
     errado em silêncio. */
  if nullif(btrim(coalesce(p_atendido_nome, '')), '') is null then
    select case when not public.mesmo_primeiro_nome(c.nome, v_nome)
                  then v_nome end
      into v_quem
      from public.clientes c where c.id = v_cliente;
  else
    v_quem := btrim(p_atendido_nome);
  end if;

  /* ══════════════════════════════════════════════════════════════════════
     O PACOTE, E A ÚNICA LINHA QUE SEPARA DESCONTO DE ROMBO

     Se a cliente tem pacote cobrindo estes serviços, neste dia, com sessão
     sobrando, o atendimento sai por R$ 0,00 — ela já pagou.

     ⚠ `c.perfil_id = v_perfil and v_perfil is not null` NÃO É REDUNDANTE.

     A ficha é reencontrada PELO TELEFONE quando não há login, e o
     `ficha_do_cliente()` diz, no 05_agenda.sql, que sem SMS não existe prova
     de que o número seja de quem digitou. Sem esta condição, qualquer pessoa
     que soubesse o telefone da Maria marcaria de graça no lugar dela — e o
     salão só descobriria na hora de fechar a conta, com a cliente na cadeira.

     Com login, `auth.uid()` é prova: senha é algo que só ela sabe.

     E o preço sai DAQUI, nunca do navegador. Quem chamar `agendar()` por fora
     com o mesmo horário leva o preço cheio, porque quem decide é esta linha.
     ══════════════════════════════════════════════════════════════════════ */
  if v_perfil is not null and exists (
       select 1 from public.clientes c
        where c.id = v_cliente and c.perfil_id = v_perfil)
  then
    v_pacote := public.pacote_que_cobre(v_cliente, p_servicos, p_inicio);
    if v_pacote is not null then v_valor := 0; end if;

    /* ── O DIA FORA DO PACOTE ─────────────────────────────────────────────
       Só chega aqui quem NÃO foi coberta — se o pacote cobriu, o dia estava
       certo por definição, e perguntar de novo seria perguntar duas vezes a
       mesma coisa com respostas que podem divergir.

       A recusa é do LINK, e só do link. O painel grava na tabela direto e não
       passa por aqui: a recepção marca a quinta-feira da Maria cobrando, que é
       exatamente a saída que o texto da recusa oferece a ela.

       ⚠ E ela mora AQUI DENTRO, no mesmo `if` do desconto, não no
       `porque_nao_agenda()`. Aquela função responde sobre o DIA e o
       PROFISSIONAL — ela não sabe quem está do outro lado, e o 19_teto_online
       já explica por quê. Um bloqueio de pacote colocado lá fecharia a
       quinta-feira para o salão inteiro por causa do pacote de uma pessoa. */
    if v_pacote is null then
      v_motivo := public.pacote_fora_do_dia(v_cliente, p_servicos, p_inicio);
      if v_motivo is not null then
        raise exception '%', v_motivo using errcode = 'check_violation';
      end if;
    end if;
  end if;

  select count(*) into v_abertos from public.agendamentos a
   where a.cliente_id = v_cliente
     and a.status in ('pendente','confirmado')
     and a.arquivado_em is null
     and a.inicio > now();

  if v_abertos >= 3 then
    raise exception 'Você já tem 3 horários marcados aqui. Cancele um antes de marcar outro.'
      using errcode = 'check_violation';
  end if;

  /* ⚠ O STATUS SAI DA CONFIGURAÇÃO DO SALÃO, e não escrito à mão.

     Aqui estava `'confirmado'` fixo, e o `'pendente'` era uma porta que o
     schema tinha desde o começo e ninguém abria: `ha_choque`, a cota e o
     `porque_nao_agenda` já contavam pendente, mas nada criava um.

     O salão que confirma à mão recebe pendente — e a cadeira fica reservada
     enquanto ele decide, porque `ha_choque()` conta pendente. Se não contasse,
     duas pessoas marcariam o mesmo horário durante a espera, e uma delas
     ouviria "não" depois de já ter combinado o dia.

     Quem NÃO configurou nada continua recebendo confirmado, como sempre —
     `confirma_automatico()` no 29 tem o padrão do lado de quem já usa. */
  begin
    insert into public.agendamentos
      (salao_id, cliente_id, profissional_id, inicio, fim, status, origem,
       valor_previsto, atendido_nome, obs, criado_por, pacote_cliente_id)
    values
      (v_salao, v_cliente, p_profissional, p_inicio, v_fim,
       case when public.confirma_automatico(v_salao) then 'confirmado'
            else 'pendente' end, 'online',
       v_valor, v_quem,
       nullif(btrim(coalesce(p_obs, '')), ''), v_perfil, v_pacote)
    returning agendamentos.id, agendamentos.gerenciar_token into v_agend, v_token;
  exception
    when exclusion_violation then
      raise exception 'Alguém acabou de marcar esse horário. Escolha outro, por favor.'
        using errcode = 'check_violation';
  end;

  for s in
    select sv.id, coalesce(sp.duracao_min, sv.duracao_min) + sv.intervalo_min as dur,
           coalesce(sp.preco, sv.preco) as preco,
           coalesce(sv.comissao_pct, pr.comissao_pct, 0) as com
      from unnest(p_servicos) with ordinality as pedido(id, pos)
      join public.servicos sv on sv.id = pedido.id
      join public.profissionais pr on pr.id = p_profissional
      left join public.servicos_profissionais sp
             on sp.servico_id = sv.id and sp.profissional_id = p_profissional
     order by pedido.pos
  loop
    insert into public.agendamento_servicos
      (agendamento_id, servico_id, ordem, duracao_min, preco, comissao_pct)
    values (v_agend, s.id, v_ordem, s.dur, s.preco, s.com);
    v_ordem := v_ordem + 1;
  end loop;

  return query select v_agend, p_inicio, v_fim, v_valor, v_token;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Ver o que é meu
--
-- Recebe a lista de segredos que o navegador guardou e devolve as marcações
-- correspondentes, já com o nome do serviço e de quem atende — a cliente não
-- alcança `servicos` nem `profissionais` diretamente, e não precisa.
--
-- Segredo que não existe simplesmente não devolve linha. Sem mensagem de erro
-- diferente: "este código não existe" versus "existe mas não é seu" seria um
-- oráculo para quem quisesse tentar.
-- ---------------------------------------------------------------------------
create or replace function public.meus_agendamentos(p_tokens uuid[])
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'inicio'), '[]'::jsonb) from (
    select jsonb_build_object(
      'token',     a.gerenciar_token,
      'inicio',    a.inicio,
      'fim',       a.fim,
      'status',    a.status,
      'atendido',  a.atendido_nome,
      'valor',     a.valor_previsto,
      'salao',     sa.nome,
      'slug',      sa.slug,
      'fuso',      sa.fuso,
      'profissional', coalesce(p.apelido, p.nome),
      'servicos', coalesce((
        select jsonb_agg(sv.nome order by asv.ordem)
          from public.agendamento_servicos asv
          join public.servicos sv on sv.id = asv.servico_id
         where asv.agendamento_id = a.id), '[]'::jsonb),
      /* Os IDS, além dos nomes. Nome serve para ler; para REMARCAR a tela
         precisa recompor a escolha, e escolha se faz com id. Sem isto a
         remarcação só existia no modo de demonstração — a nuvem mostrava o
         botão em lugar nenhum, e quem quisesse trocar de horário tinha que
         cancelar primeiro, ficando sem nada enquanto procurava outro.

         Não é dado novo exposto: quem tem o token deste agendamento já é
         dono dele, e os dois ids são justamente o que ele acabou de
         escolher. */
      'profissionalId', a.profissional_id,
      'servicoIds', coalesce((
        select jsonb_agg(asv.servico_id order by asv.ordem)
          from public.agendamento_servicos asv
         where asv.agendamento_id = a.id), '[]'::jsonb),
      -- A tela precisa saber se ainda dá tempo de mexer. A regra mora aqui
      -- para as duas pontas não discordarem: `cancelar_agendamento()` cobra
      -- o mesmo limite, e nada é oferecido para ser recusado depois.
      'podeMexer', a.status in ('pendente','confirmado')
                   and a.inicio > now() + interval '2 hours'
    ) as x
      from public.agendamentos a
      join public.saloes sa        on sa.id = a.salao_id
      join public.profissionais p  on p.id  = a.profissional_id
     where a.gerenciar_token = any(coalesce(p_tokens, '{}'::uuid[]))
       and a.arquivado_em is null
  ) t
$$;

-- ---------------------------------------------------------------------------
-- 4) Cancelar
--
-- As DUAS horas de antecedência não são burocracia: cadeira cancelada em cima
-- da hora não é revendida, e o prejuízo é do salão. Quem precisa cancelar
-- depois disso fala com a casa — e aí é uma conversa, não um botão.
-- ---------------------------------------------------------------------------
create or replace function public.cancelar_agendamento(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.agendamentos%rowtype;
begin
  select * into a from public.agendamentos where gerenciar_token = p_token;

  -- Mesma frase para "não existe" e para "não é seu": qualquer diferença
  -- entre as duas responde perguntas para quem está tentando adivinhar.
  if a.id is null then
    raise exception 'Não achei esse horário. Confira o link.'
      using errcode = 'check_violation';
  end if;

  if a.status not in ('pendente','confirmado') then
    raise exception 'Este horário já foi %.',
      case a.status when 'cancelado' then 'cancelado'
                    when 'concluido' then 'atendido'
                    else a.status end
      using errcode = 'check_violation';
  end if;

  if a.inicio <= now() + interval '2 hours' then
    raise exception 'Faltam menos de 2 horas. Fale com o salão para desmarcar.'
      using errcode = 'check_violation';
  end if;

  update public.agendamentos
     set status = 'cancelado', cancelado_motivo = 'cancelado pelo cliente'
   where id = a.id;

  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 5) A lista de espera
--
-- O dia cheio é onde o sistema comum perde o cliente: mostra "sem horário" e
-- a pessoa fecha a página. Aqui ela deixa o nome, e a cadeira que vagar tem
-- para quem ser oferecida.
--
-- Como `agendar()`, a duração sai dos SERVIÇOS e nunca do navegador: sem
-- isso, a fila encheria de pedidos de três horas que ninguém pediu.
-- ---------------------------------------------------------------------------
create or replace function public.entrar_na_fila(
  p_salao      uuid,
  p_servicos   uuid[],
  p_nome       text,
  p_telefone   text,
  p_de         date,
  p_ate        date,
  p_profissional uuid default null,
  p_turno      text default 'qualquer',
  p_obs        text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tel     text;
  v_nome    text;
  v_cliente uuid;
  v_perfil  uuid := auth.uid();
  v_dur     int;
  v_hoje    date;
  v_token   uuid;
  v_abertas int;
begin
  v_nome := nullif(btrim(coalesce(p_nome, '')), '');
  v_tel  := public.so_digitos(p_telefone);

  if v_nome is null then
    raise exception 'Diga seu nome para a gente saber quem avisar.'
      using errcode = 'check_violation';
  end if;
  if v_tel is null or length(v_tel) < 10 or length(v_tel) > 13 then
    raise exception 'Confira o telefone: precisa do DDD.'
      using errcode = 'check_violation';
  end if;
  if p_servicos is null or cardinality(p_servicos) = 0 then
    raise exception 'Escolha pelo menos um serviço.'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from public.saloes
                  where id = p_salao and status = 'ativo') then
    raise exception 'Este salão não está aceitando pedidos agora.'
      using errcode = 'check_violation';
  end if;

  -- Serviço tem que ser DESTE salão e estar aberto ao online, pela mesma
  -- razão de `agendar()`: sem conferir, dá para entrar na fila de um salão
  -- pedindo o serviço de outro, colando o id na chamada.
  if exists (
    select 1 from unnest(p_servicos) as pedido(id)
     where not exists (
       select 1 from public.servicos s
        where s.id = pedido.id and s.salao_id = p_salao
          and s.ativo and s.aceita_online))
  then
    raise exception 'Um dos serviços escolhidos não está disponível.'
      using errcode = 'check_violation';
  end if;

  v_hoje := public.hoje_no_salao(p_salao);
  if p_de < v_hoje or p_ate < p_de then
    raise exception 'Confira as datas do período.'
      using errcode = 'check_violation';
  end if;
  if p_ate > v_hoje + public.dias_liberados(p_salao) then
    raise exception 'A agenda está liberada até %.',
      to_char(v_hoje + public.dias_liberados(p_salao), 'DD/MM/YYYY')
      using errcode = 'check_violation';
  end if;

  -- Mesma função das outras duas. Entrar na fila com um número diferente do
  -- que está na ficha dava o mesmo erro de chave duplicada do agendamento.
  v_cliente := public.ficha_do_cliente(p_salao, v_nome, v_tel);

  -- O mesmo freio de spam de `agendar()`, e pelo mesmo motivo: é um
  -- formulário aberto na internet.
  select count(*) into v_abertas from public.lista_espera
   where cliente_id = v_cliente and status = 'aguardando';
  if v_abertas >= 3 then
    raise exception 'Você já está em 3 listas de espera aqui. Saia de uma antes de entrar noutra.'
      using errcode = 'check_violation';
  end if;

  v_dur := public.duracao_dos_servicos(
             coalesce(p_profissional,
                      (select id from public.profissionais
                        where salao_id = p_salao and ativo limit 1)),
             p_servicos);

  insert into public.lista_espera
    (salao_id, cliente_id, profissional_id, servicos, duracao_min,
     de, ate, turno, obs, status)
  values
    (p_salao, v_cliente, p_profissional, to_jsonb(p_servicos), greatest(v_dur, 1),
     p_de, p_ate, coalesce(nullif(btrim(p_turno), ''), 'qualquer'),
     nullif(btrim(coalesce(p_obs, '')), ''), 'aguardando')
  returning gerenciar_token into v_token;

  return jsonb_build_object('token', v_token);
end $$;

create or replace function public.minha_fila(p_tokens uuid[])
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'de'), '[]'::jsonb) from (
    select jsonb_build_object(
      'token',  e.gerenciar_token,
      'de',     e.de,
      'ate',    e.ate,
      'turno',  e.turno,
      'status', e.status,
      'salao',  sa.nome,
      'slug',   sa.slug
    ) as x
      from public.lista_espera e
      join public.saloes sa on sa.id = e.salao_id
     where e.gerenciar_token = any(coalesce(p_tokens, '{}'::uuid[]))
       and e.status = 'aguardando'
  ) t
$$;

create or replace function public.sair_da_fila(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update public.lista_espera
     set status = 'desistiu'
   where gerenciar_token = p_token and status = 'aguardando';

  if not found then
    raise exception 'Não achei esse pedido na lista.'
      using errcode = 'check_violation';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- 6) Quem pode chamar
--
-- Tudo para `anon`: a cliente que abre o link não fez login, e é ela quem
-- precisa disso. O segredo é a credencial — as funções não confiam em nada
-- além dele, e nenhuma delas aceita "me dê a lista de fulano".
--
-- E `anon` continua SEM alcançar `agendamentos`, `clientes` e `lista_espera`
-- pelas tabelas. Todo o acesso passa por estas funções, que só respondem a
-- quem apresenta o segredo daquela linha.
-- ---------------------------------------------------------------------------
revoke all on function public.meus_agendamentos(uuid[])   from public;
revoke all on function public.cancelar_agendamento(uuid)  from public;
revoke all on function public.minha_fila(uuid[])          from public;
revoke all on function public.sair_da_fila(uuid)          from public;
revoke all on function public.entrar_na_fila(uuid, uuid[], text, text, date, date,
                                             uuid, text, text) from public;
revoke all on function public.agendar(uuid, timestamptz, uuid[], text, text, text,
                                      text, text, date, text) from public;

grant execute on function public.meus_agendamentos(uuid[])   to anon, authenticated;
grant execute on function public.cancelar_agendamento(uuid)  to anon, authenticated;
grant execute on function public.minha_fila(uuid[])          to anon, authenticated;
grant execute on function public.sair_da_fila(uuid)          to anon, authenticated;
grant execute on function public.entrar_na_fila(uuid, uuid[], text, text, date, date,
                                                uuid, text, text) to anon, authenticated;
grant execute on function public.agendar(uuid, timestamptz, uuid[], text, text, text,
                                         text, text, date, text) to anon, authenticated;
