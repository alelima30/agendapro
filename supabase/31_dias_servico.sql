-- ===========================================================================
-- AgendaPro — 31: o serviço que só é feito em certos dias
--
-- "Escova só de quinta a sábado." Pedido de quem tem serviço longo que só cabe
-- em dia de movimento fraco, e de quem tem profissional que vem dois dias por
-- semana fazer uma coisa específica.
--
-- ── O QUE JÁ EXISTIA, E POR QUE NÃO SERVIA ────────────────────────────────
-- A restrição de dia só existia DENTRO do pacote (`pacotes.so_nos_dias`, no
-- 27). Aquela é outra pergunta: ela diz em que dias a SESSÃO DO PACOTE pode
-- ser usada, vale só para quem tem o pacote, e o salão continua vendendo o
-- mesmo serviço a preço cheio nos outros dias. Esta aqui é sobre o serviço em
-- si, para todo mundo.
--
-- ── ⚠ ONDE A REGRA MORA, E POR QUE ─────────────────────────────────────────
-- No `porque_nao_agenda()`, que é a ÚNICA porta da política da agenda online.
-- Três coisas saem de graça por morar ali:
--
--   · o `horarios_livres()` a respeita sozinho — ele começa perguntando a esta
--     função e desiste quando ela responde. Então o dia deixa de oferecer
--     horário sem nenhuma linha a mais;
--   · o `agendar()` também pergunta antes de gravar, então a recusa é do
--     BANCO. Ninguém marca a segunda-feira mexendo no navegador;
--   · e a RECEPÇÃO continua livre. O painel grava na tabela direto, sem passar
--     por aqui. É a mesma divisão de sempre neste projeto: o link é uma
--     peneira de política, a recepção é a dona da agenda. Se a cliente ligar
--     pedindo escova na segunda e a dona quiser fazer, ela marca.
--
-- ── ⚠ NULO E VAZIO QUEREM DIZER A MESMA COISA AQUI, DE PROPÓSITO ──────────
-- Em quase todo o resto deste projeto ausente e vazio são estados diferentes,
-- e confundi-los já causou defeito três vezes. Aqui eles são o MESMO estado —
-- "todos os dias" — e é decisão, não descuido:
--
--   · nulo é o serviço que nunca foi tocado. Todo serviço que já existe nasce
--     assim no dia em que esta coluna aparece, e nenhum deles pode mudar de
--     comportamento;
--   · vazio seria "nenhum dia". Um serviço que não pode ser marcado em dia
--     nenhum não é uma configuração, é um serviço DESLIGADO — e para isso já
--     existe o `ativo`, que diz a mesma coisa num lugar onde o dono procura.
--
-- Lido como "nenhum dia", o vazio faria o serviço sumir do link sem aviso, e o
-- dono passaria a tarde procurando o defeito numa tela que está funcionando.
-- A tela do painel também se recusa a salvar zero dias; esta linha é a
-- segunda tranca, para o caso de o valor chegar por outro caminho.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) A coluna — ⚠ DECLARADA NO 25_loja.sql, e não aqui
--
-- `servicos.dias` é `smallint[]` no padrão do Postgres: 0 = domingo. O mesmo
-- formato de `pacotes.dias`, de propósito — duas grafias para a mesma ideia
-- dentro do mesmo banco é convite para erro de fuso disfarçado de erro de
-- índice.
--
-- Ela é desta funcionalidade, mas a linha `alter table` está no 25_loja.sql,
-- logo acima da `vitrine()`. Motivo do Postgres, não de arquitetura: a
-- `vitrine()` é função SQL, o `create or replace` COMPILA o corpo na hora, e
-- ela lê `v.dias`. Nas duas montagens o 25 roda antes do 31, então declarar
-- aqui faria o install inteiro parar com "column v.dias does not exist".
-- Aconteceu, e é o tipo de erro que só aparece na instalação do zero.
--
-- Aqui fica só o `comment`, que é onde um DBA vai procurar o significado.
-- ---------------------------------------------------------------------------
comment on column public.servicos.dias is
  'Dias da semana em que o LINK oferece este serviço (0=domingo). NULL ou vazio = todos os dias. A recepção nunca é limitada por isto.';

-- ---------------------------------------------------------------------------
-- 2) Qual serviço do pedido não cabe neste dia?
--
-- Devolve a frase pronta, ou NULL quando não há nada a barrar. Texto e não
-- booleano pelo mesmo motivo do `pacote_fora_do_dia()`: recusa sem motivo
-- escrito é igual a horário que some. A cliente abre a segunda-feira, não vê
-- nada, e conclui que o salão fechou.
--
-- ⚠ BASTA UM SERVIÇO DO PEDIDO ESTAR FORA. Ela escolheu corte + escova para o
-- mesmo horário; se a escova não é feita na segunda, o par não cabe na
-- segunda. Barrar só quando TODOS estão fora deixaria passar a marcação de um
-- combinado que o salão não consegue cumprir — e o problema só apareceria com
-- a cliente sentada na cadeira.
--
-- A frase nomeia o serviço porque ela pode ter escolhido três: sem o nome, a
-- pessoa não sabe qual tirar do carrinho para resolver.
-- ---------------------------------------------------------------------------
create or replace function public.servico_fora_do_dia(
  p_servicos uuid[], p_data date)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_dia   smallint;
  v_nome  text;
  v_dias  smallint[];
begin
  if p_servicos is null or cardinality(p_servicos) = 0 or p_data is null then
    return null;
  end if;

  /* ⚠ O DIA SAI DA DATA, E NÃO DE `now()`. Quem chama já converteu o instante
     para a data DO SALÃO — é o `porque_nao_agenda()` e o `agendar()`, os dois
     pelo fuso do salão. Recalcular aqui com o fuso do servidor poria a
     quinta-feira de alguém na quarta, e seria um daqueles defeitos que só
     aparecem depois das 21h. */
  v_dia := extract(dow from p_data)::smallint;

  select s.nome, s.dias into v_nome, v_dias
    from public.servicos s
   where s.id = any(p_servicos)
     and s.dias is not null
     and cardinality(s.dias) > 0        -- vazio é "todos", ver o cabeçalho
     and not (v_dia = any(s.dias))
   order by s.nome
   limit 1;

  if v_nome is null then return null; end if;

  /* A frase diz as três coisas que resolvem sozinhas: o que não cabe, quando
     cabe, e o que fazer agora. Sem a última ela fica sabendo que não pode e
     não sabe o que fazer — que é o mesmo que não ter resposta. */
  /* ⚠ SEM CONCORDÂNCIA DE GÊNERO NA FRASE. Aqui estava "%s é feito só %s", e
     saía "Escova é feito só quinta" — o nome do serviço é texto livre do dono,
     e metade deles é feminino. Não dá para adivinhar o gênero, e errar a
     concordância numa recusa é o tipo de detalhe que faz a página parecer
     descuidada exatamente no momento em que ela está negando alguma coisa.

     Dois-pontos resolvem sem adivinhar nada. */
  return format(
    '%s: só %s. Escolha um desses dias, tire este serviço do pedido, '
    || 'ou chame o salão no WhatsApp.',
    v_nome, public.dias_por_extenso(v_dias));
end $$;

comment on function public.servico_fora_do_dia(uuid[], date) is
  'Frase de recusa quando algum serviço do pedido não é feito no dia da semana pedido. NULL quando não há nada a barrar. Só o link usa: a recepção marca por fora.';

/* ⚠ SEM GRANT NENHUM, e não `to anon, authenticated`.

   Eu tinha liberado as duas para o anon por reflexo — "é o link que usa, o
   link é anônimo". Errado: quem o link chama é a `porque_nao_agenda()` e o
   `entrar_na_fila()`, e as duas são `security definer`. Enquanto elas rodam,
   quem executa é o DONO da função, não a cliente — então a ajudante não
   precisa estar aberta a ninguém.

   Quem apontou foi o `portas.test.sql`, que cobra justificativa de toda
   `security definer` aberta ao anon. E ele só chegou a rodar porque o
   `tests/rodar.sh` passou a instalar o módulo 31 — antes ele parava no 29, e
   estas duas funções nunca existiram no banco de teste. Um guarda que não
   enxerga metade da casa não é um guarda.

   Aberta ao anon, `servico_fora_do_dia` é uma consulta sobre serviços de
   QUALQUER salão, com o id no parâmetro: um id adivinhado devolve o nome do
   serviço na frase de recusa. Pouco, mas é mais do que zero, e de graça. */
revoke all on function public.servico_fora_do_dia(uuid[], date) from public;

-- ---------------------------------------------------------------------------
-- 2b) A MESMA PERGUNTA, PARA UM PERÍODO INTEIRO
--
-- A lista de espera não pede um dia: pede uma JANELA ("de 27 a 30, qualquer
-- turno"). A pergunta certa ali é outra — existe ALGUM dia dessa janela em
-- que o salão faz tudo o que ela pediu?
--
-- ── ⚠ POR QUE ISTO PRECISOU EXISTIR ───────────────────────────────────────
-- Sem ela, o mesmo link RECUSAVA marcar escova na segunda, com a frase certa,
-- e ACEITAVA a cliente na fila de espera de domingo a quarta — uma janela em
-- que a escova não é feita em dia nenhum.
--
-- É a pior forma de falhar que este projeto conhece: nada dá erro, a cliente
-- recebe um "pronto, a gente te avisa", e espera um telefonema que não pode
-- acontecer. Do lado do salão também não aparece nada — a fila tem um pedido
-- impossível no meio dos possíveis.
--
-- ⚠ E BASTA UM DIA PARA ACEITAR. Se a janela pega uma quinta, a fila é
-- legítima: o salão vai oferecer a quinta. Recusar uma janela por ela conter
-- dias ruins seria recusar quase todas — quase toda janela de uma semana tem
-- pelo menos um dia de fora.
-- ---------------------------------------------------------------------------
create or replace function public.servico_fora_do_periodo(
  p_servicos uuid[], p_de date, p_ate date)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_dia date;
begin
  if p_servicos is null or cardinality(p_servicos) = 0
     or p_de is null or p_ate is null or p_ate < p_de then
    return null;
  end if;

  /* Sai no primeiro dia que serve. A janela é limitada pelo `dias_liberados`
     de quem chama, então isto roda dezenas de vezes, não milhares — e para na
     primeira quinta-feira que aparecer. */
  for v_dia in select d::date from generate_series(p_de, p_ate, interval '1 day') d
  loop
    if public.servico_fora_do_dia(p_servicos, v_dia) is null then
      return null;
    end if;
  end loop;

  -- Nenhum dia serve: a frase é a mesma da recusa de marcar, para a cliente
  -- não receber duas explicações diferentes do mesmo motivo.
  return public.servico_fora_do_dia(p_servicos, p_de);
end $$;

comment on function public.servico_fora_do_periodo(uuid[], date, date) is
  'Frase de recusa quando NENHUM dia do período serve para os serviços pedidos. NULL quando pelo menos um serve. Usada pela lista de espera.';

-- Sem grant, pelo mesmo motivo da irmã: quem a chama é o `entrar_na_fila()`,
-- que é `security definer` e roda como dono.
revoke all on function public.servico_fora_do_periodo(uuid[], date, date) from public;

-- ---------------------------------------------------------------------------
-- 3) A POLÍTICA DA AGENDA ONLINE, COM O DIA DO SERVIÇO NO MEIO
--
-- ⚠ VAI INTEIRA, E NÃO UM REMENDO. `create or replace function` não sabe
-- acrescentar linha: o corpo que estiver aqui é o corpo que vale. Esta é cópia
-- fiel da versão do 19_teto_online.sql com UM bloco a mais — e, como este
-- arquivo tem número maior, é esta que passa a valer.
--
-- ⚠ E É POR ISSO QUE REINSTALAR UM MÓDULO SOZINHO NUM BANCO JÁ MONTADO
-- ESTRAGA COISA. Rodar o 19 por cima de um banco com o 31 devolve a versão
-- sem esta regra, sem erro nenhum, porque é tudo `create or replace`. Para
-- mexer no SQL, monte do zero. Está escrito no `tests/bancada/subir.sh` com o
-- caso concreto que custou uma hora.
--
-- ── ONDE O BLOCO NOVO ENTRA, E POR QUE AÍ ─────────────────────────────────
-- Depois das duas conferências de data e antes dos dois limites do fim.
--
--   · depois de "essa data já passou" e de "a agenda está liberada até": uma
--     data de ontem é problema maior, e dizer "escova é feita só às quintas"
--     sobre uma quinta-feira do mês passado seria uma resposta certa para a
--     pergunta errada;
--   · antes dos limites do balcão e da rajada, que são os únicos que a pessoa
--     NÃO tem como resolver. Mandá-la ao WhatsApp antes de avisar que bastava
--     trocar de dia é mandá-la embora à toa.
-- ---------------------------------------------------------------------------
create or replace function public.porque_nao_agenda(
  p_profissional uuid, p_data date, p_servicos uuid[])
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_salao   uuid;
  v_hoje    date;
  v_jornada int;
  v_online  int;
  v_pedido  int;
  v_motivo  text;
begin
  if p_servicos is null or cardinality(p_servicos) = 0 then
    return 'Escolha pelo menos um serviço.';
  end if;

  select p.salao_id into v_salao
    from public.profissionais p
    join public.saloes sa on sa.id = p.salao_id
   where p.id = p_profissional
     and p.ativo and p.aceita_online
     and sa.status = 'ativo';

  if v_salao is null then
    return 'Este profissional não está atendendo pela agenda online.';
  end if;

  if not public.profissional_na_cota(p_profissional) then
    return 'Este profissional não está atendendo pela agenda online.';
  end if;

  if not public.recurso_bool(v_salao, 'agenda_online') then
    return 'Este salão não está aceitando marcação pela internet.';
  end if;

  if exists (
    select 1 from unnest(p_servicos) as pedido(id)
     where not exists (
       select 1 from public.servicos s
        where s.id = pedido.id and s.salao_id = v_salao
          and s.ativo and s.aceita_online))
  then
    return 'Um dos serviços escolhidos não está disponível.';
  end if;

  if not public.profissional_faz(p_profissional, p_servicos) then
    return 'Este profissional não faz todos os serviços escolhidos.';
  end if;

  v_hoje := public.hoje_no_salao(v_salao);

  if p_data < v_hoje then
    return 'Essa data já passou.';
  end if;

  if p_data > v_hoje + public.dias_liberados(v_salao) then
    return format('A agenda está liberada até %s.',
                  to_char(v_hoje + public.dias_liberados(v_salao), 'DD/MM/YYYY'));
  end if;

  -- ── O DIA DA SEMANA DO SERVIÇO ─────────────────────────────────────────
  -- Serviço sem dias marcados não passa por aqui: a função devolve NULL e
  -- nada muda para ele. É o caso de todo serviço que já existe.
  v_motivo := public.servico_fora_do_dia(p_servicos, p_data);
  if v_motivo is not null then
    return v_motivo;
  end if;

  /* ── A RESERVA DO BALCÃO ───────────────────────────────────────────────
     A conta é em minutos e inclui o que está sendo pedido AGORA: sem isso a
     última marcação sempre passaria, e a reserva vazaria um atendimento
     inteiro — logo o maior deles, porque é o que mais demora a caber. */
  v_jornada := public.minutos_de_jornada(p_profissional, p_data);
  if v_jornada > 0 then
    v_online := public.minutos_online_no_dia(p_profissional, p_data);
    v_pedido := public.duracao_dos_servicos(p_profissional, p_servicos);
    if (v_online + v_pedido) * 100 > v_jornada * public.teto_online_pct(v_salao) then
      return 'Este dia já está quase todo marcado. '
          || 'Chame o salão no WhatsApp que a gente encaixa você.';
    end if;
  end if;

  /* ── O FREIO DE RAJADA ─────────────────────────────────────────────────
     Nenhuma das duas frases fala em limite, cota ou teto, e é decisão: quem
     lê isto na esmagadora maioria das vezes é uma cliente de verdade num
     salão movimentado, e ela precisa de um caminho, não da explicação de um
     mecanismo. O caminho é o WhatsApp, onde tem gente.

     E para quem está do outro lado tentando encher a agenda, a frase também
     não entrega nada: não diz qual é o número nem quanto falta. */
  if public.rajada_online(v_salao) >= public.teto_online_rajada(v_salao) then
    return 'A marcação pela internet está congestionada agora. '
        || 'Tente daqui a pouco, ou chame o salão no WhatsApp.';
  end if;

  return null;
end $$;
