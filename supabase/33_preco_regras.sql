-- ===========================================================================
-- AgendaPro — 33. PREÇO AVANÇADO: vigência, dia da semana e faixa de horário
--
-- Três regras para o mesmo serviço, que respondem a mesma pergunta do salão:
-- sábado à tarde lota e terça de manhã fica vazia.
--
--   VIGÊNCIA        "a partir de 1º de março a escova passa a R$ 80"
--   DIA DA SEMANA   "escova R$ 50 de terça a quinta, R$ 70 sexta e sábado"
--   FAIXA DE HORÁRIO "corte R$ 60 antes das 14h, R$ 80 depois das 17h"
--
-- ── ⚠ O PREÇO PASSA A SER UMA PERGUNTA, E QUEM RESPONDE É O BANCO ──────────
--
-- Até aqui "preço" era um número numa coluna, e cada lado lia a coluna que
-- conhecia. O resultado, MEDIDO antes de escrever este arquivo:
--
--     Corte feminino, catálogo .................. R$  90
--     Corte feminino com a Ana (servicos_profissionais) ... R$ 130
--
--     o LINK cobrava ....... R$ 130   (coalesce(sp.preco, sv.preco) no 09)
--     a RECEPÇÃO cobrava ... R$  90   (preco: sv.preco no app.html)
--
-- Quarenta reais de diferença no mesmo atendimento, decidido por quem clicou.
-- Não era a funcionalidade nova que faltava — era não existir UM lugar que
-- respondesse "quanto custa isto".
--
-- Agora existe: `preco_do_servico()`. E um gatilho em `agendamento_servicos`
-- aplica a resposta em TODA marcação, venha do link ou do painel. A tela pode
-- errar; a linha gravada, não.
--
-- ── A ESCADA, DE CIMA PARA BAIXO ───────────────────────────────────────────
--
--   1. a REGRA que casa com o dia e a hora da marcação, a mais específica
--   2. o preço do par serviço+profissional (`servicos_profissionais.preco`)
--   3. o preço do serviço (`servicos.preco`)
--
-- É a mesma forma da `comissao_de()` no 16, e de propósito: quem já entendeu
-- uma entende a outra.
--
-- ── ⚠ E O PREÇO CONTINUA CONGELANDO NA MARCAÇÃO ────────────────────────────
--
-- `agendamento_servicos.preco` é copiado no momento da marcação desde o
-- primeiro dia — "se o preço da tabela mudar amanhã, o que foi combinado com
-- o cliente continua valendo". Nada disso muda. O que muda é QUAL número é
-- copiado: antes era a coluna, agora é a resposta da escada para aquele dia e
-- aquela hora.
--
-- É o que impede o pior defeito possível numa tela de agenda: a cliente ver
-- R$ 50 na terça, o dono mudar a regra na quarta, e ela pagar R$ 70 no balcão.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) A TABELA DAS REGRAS
--
-- Uma linha por regra. Todos os recortes são OPCIONAIS e se combinam: uma
-- regra sem nada preenchido vale sempre, para todo mundo — que é como se
-- escreve "o preço novo entra hoje e pronto".
--
-- ⚠ `salao_id` existe mesmo dando para chegar nele pelo serviço. É o que o
-- RLS pergunta, e uma policy que precisa de JOIN para saber de quem é a linha
-- é uma policy que alguém vai escrever errado um dia.
-- ---------------------------------------------------------------------------
/* ⚠ A TABELA É DECLARADA NO 25_loja.sql, e não aqui, e isto é uma cópia
   inofensiva (`if not exists`) para quem rodar só este arquivo.

   O motivo é a ordem de compilação: a `vitrine()` do 25 lê `precos_regras`,
   corpo de função SQL compila na hora, e o 25 roda oito arquivos antes deste.
   Sem a tabela já de pé lá, a vitrine nem é criada e o install inteiro para.
   É a mesma razão de `servicos.dias` e `produtos.preco_visivel` morarem no 25.

   O dono da funcionalidade continua sendo este arquivo: RLS, policies, grants,
   a escada de preço e o gatilho estão todos aqui. */
create table if not exists public.precos_regras (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  servico_id      uuid not null references public.servicos(id) on delete cascade,
  -- Nulo = vale para quem atender. Preenchido = só com esta pessoa.
  profissional_id uuid references public.profissionais(id) on delete cascade,
  preco           numeric(10,2) not null check (preco >= 0),
  -- Vigência. Nulo dos dois lados = desde sempre, para sempre.
  de              date,
  ate             date,
  /* Dias da semana, no padrão do Postgres e do JavaScript: 0 = domingo.
     Nulo ou vazio = todo dia. Mesma convenção do `servicos.dias` no 31 e do
     `pacotes.so_nos_dias` no 27 — três lugares, uma contagem só. */
  dias            smallint[],
  -- Faixa de horário em MINUTOS desde a meia-noite, como o resto da agenda.
  -- 14h = 840. Nulo dos dois lados = o dia inteiro.
  hora_ini        int,
  hora_fim        int,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),

  constraint preco_regra_vigencia  check (de is null or ate is null or ate >= de),
  constraint preco_regra_faixa     check (
    (hora_ini is null and hora_fim is null)
    or (hora_ini is not null and hora_fim is not null
        and hora_ini >= 0 and hora_fim <= 1440 and hora_fim > hora_ini)),
  constraint preco_regra_dias      check (
    dias is null or (array_length(dias, 1) between 1 and 7
                     and 0 <= all(dias) and 7 > all(dias)))
);

create index if not exists ix_preco_regra_servico
  on public.precos_regras (servico_id) where ativo;

comment on table public.precos_regras is
  'Preço por vigência, dia da semana e faixa de horário. Recortes opcionais e combináveis; a regra mais específica ganha. Ver preco_do_servico().';

-- ---------------------------------------------------------------------------
-- 2) QUEM ENXERGA
--
-- Ler é da equipe: quem atende precisa saber quanto custa o que ele faz.
-- Escrever é de gestor: preço é política comercial.
--
-- ⚠ Duas policies separadas por VERBO, e não uma `for all`. Uma policy só
-- daria a quem lê o direito de escrever no dia em que alguém trocasse o
-- `using` sem lembrar do `with check`.
-- ---------------------------------------------------------------------------
alter table public.precos_regras enable row level security;

drop policy if exists pr_ler on public.precos_regras;
create policy pr_ler on public.precos_regras for select to authenticated
  using (public.e_equipe(salao_id));

drop policy if exists pr_gerir on public.precos_regras;
create policy pr_gerir on public.precos_regras for all to authenticated
  using (public.e_gestor(salao_id))
  with check (public.e_gestor(salao_id));

/* ⚠ E O GRANT DE TABELA, que é outra coisa da policy.
   A policy diz QUAIS LINHAS a pessoa alcança; o grant diz se ela alcança a
   tabela. Sem ele o PostgREST responde "permission denied for table" antes de
   a policy ser consultada — e a mensagem não fala em linha nenhuma, o que
   manda quem for depurar procurar erro no lugar errado.

   ⚠ NADA PARA O `anon`. Quem não tem login recebe os preços prontos dentro da
   `vitrine()`, que é `security definer` e escolhe o que sai. A tabela crua
   traria o preço por profissional de qualquer salão a quem adivinhasse um id. */
grant select, insert, update, delete on public.precos_regras to authenticated;

-- ---------------------------------------------------------------------------
-- 3) A REGRA MAIS ESPECÍFICA
--
-- Várias regras podem casar com o mesmo horário. "Escova R$ 50 nas terças" e
-- "escova R$ 45 em março" se cruzam numa terça de março, e alguém tem que
-- ganhar — de um jeito que dê para explicar ao dono em uma frase.
--
-- A frase é: QUANTO MAIS RECORTES A REGRA TEM, MAIS ELA MANDA.
--
--   profissional  vale 8     "só com a Carla" é o recorte mais estreito
--   dias          vale 4
--   horário       vale 2
--   vigência      vale 1     o mais largo: um período costuma pegar semanas
--
-- Somando, a regra com mais recortes ganha. Empatou, vale a mais recente —
-- porque quem cadastrou depois estava corrigindo o que cadastrou antes.
--
-- ⚠ NÃO É O MENOR PREÇO QUE GANHA, e isso é decisão. "O mais barato ganha"
-- parece generoso e tira do dono o poder de cobrar MAIS num horário disputado
-- — que é metade do motivo de ele querer isto.
-- ---------------------------------------------------------------------------
create or replace function public.preco_regra_que_vale(
  p_servico uuid, p_profissional uuid, p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  with onde as (
    select sa.fuso
      from public.servicos sv
      join public.saloes sa on sa.id = sv.salao_id
     where sv.id = p_servico
  ),
  /* O dia e a hora NO FUSO DO SALÃO, que não é o fuso de quem está olhando.
     Uma cliente em Portugal marcando às 3h da manhã dela num salão de Porto
     Alegre tem que pegar o preço do dia que é lá. Mesma conta do
     `hoje_no_salao()` no 05. */
  quando as (
    select (p_quando at time zone o.fuso)::date            as dia,
           extract(dow from (p_quando at time zone o.fuso))::smallint as dow,
           (extract(hour from (p_quando at time zone o.fuso)) * 60
            + extract(minute from (p_quando at time zone o.fuso)))::int as min
      from onde o
  )
  select r.preco
    from public.precos_regras r, quando q
   where r.ativo
     and r.servico_id = p_servico
     and (r.profissional_id is null or r.profissional_id = p_profissional)
     and (r.de   is null or q.dia >= r.de)
     and (r.ate  is null or q.dia <= r.ate)
     and (r.dias is null or array_length(r.dias, 1) is null or q.dow = any(r.dias))
     and (r.hora_ini is null or (q.min >= r.hora_ini and q.min < r.hora_fim))
   order by (case when r.profissional_id is not null then 8 else 0 end)
          + (case when r.dias is not null
                   and array_length(r.dias, 1) is not null then 4 else 0 end)
          + (case when r.hora_ini is not null then 2 else 0 end)
          + (case when r.de is not null or r.ate is not null then 1 else 0 end)
            desc,
            r.criado_em desc, r.id desc
   limit 1
$$;

comment on function public.preco_regra_que_vale(uuid, uuid, timestamptz) is
  'O preço da regra mais específica que casa com este horário, ou NULL quando nenhuma casa. Não é o menor preço: é a regra com mais recortes.';

-- ---------------------------------------------------------------------------
-- 4) A ESCADA INTEIRA — A ÚNICA RESPOSTA PARA "QUANTO CUSTA"
--
-- Regra → par serviço+profissional → serviço. Quem chamar isto está certo;
-- quem ler uma coluna sozinha está adivinhando.
-- ---------------------------------------------------------------------------
create or replace function public.preco_do_servico(
  p_servico uuid, p_profissional uuid, p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  select coalesce(
    public.preco_regra_que_vale(p_servico, p_profissional, p_quando),
    (select sp.preco from public.servicos_profissionais sp
      where sp.servico_id = p_servico and sp.profissional_id = p_profissional),
    (select sv.preco from public.servicos sv where sv.id = p_servico),
    0)::numeric(10,2)
$$;

comment on function public.preco_do_servico(uuid, uuid, timestamptz) is
  'Quanto custa este serviço, com esta pessoa, neste horário. Escada: regra de preço, preço do par, preço do serviço.';

-- A soma, para o `valor_previsto`. Mesma escada, uma linha por serviço.
create or replace function public.preco_dos_servicos(
  p_profissional uuid, p_servicos uuid[], p_quando timestamptz)
returns numeric language sql stable set search_path = public as $$
  select coalesce(sum(public.preco_do_servico(s, p_profissional, p_quando)), 0)
           ::numeric(10,2)
    from unnest(p_servicos) as s
$$;

comment on function public.preco_dos_servicos(uuid, uuid[], timestamptz) is
  'A soma da escada de preço para os serviços pedidos, neste horário.';

/* ── ⚠ E A VERSÃO SEM DATA, QUE FICOU PARA TRÁS ──────────────────────────
   `preco_dos_servicos(profissional, servicos)` nasceu no 05, quando preço era
   uma coluna só. Ela continua existindo — o `agendar()` antigo do 05 a chama,
   e o 09 substitui esse `agendar()`, então na prática ela ficou sem uso.

   "Sem uso" é o pior estado possível para uma função de dinheiro: ela não
   incomoda ninguém e responde a pergunta errada com cara de estar certa. A
   próxima pessoa que precisar de uma soma de preços vai achá-la pelo nome,
   chamar, e não receber regra nenhuma.

   Aqui ela passa a delegar, assumindo AGORA como horário. Quem não informou o
   horário quer saber quanto custa agora — e agora é uma resposta certa, não um
   palpite.

   ⚠ E É AQUI, no 33, e não lá no 05. Função SQL compila o corpo na hora de
   criar, e o 05 roda antes do 33: chamar `preco_do_servico()` de lá quebraria
   a instalação do zero. Redefinir no módulo de número maior é o padrão que o
   `sintaxe.test.js` conhece e cobra. */
create or replace function public.preco_dos_servicos(
  p_profissional uuid, p_servicos uuid[])
returns numeric language sql stable set search_path = public as $$
  select public.preco_dos_servicos(p_profissional, p_servicos, now())
$$;

comment on function public.preco_dos_servicos(uuid, uuid[]) is
  'A soma da escada de preço para AGORA. Prefira a versão com o horário: com regra de preço, o mesmo serviço custa diferente na terça de manhã e no sábado.';

-- ---------------------------------------------------------------------------
-- 5) ⚠ O GATILHO — É ELE QUE FAZ A REGRA VALER PARA TODO MUNDO
--
-- Sem esta parte, o arquivo inteiro seria uma funcionalidade que só o link
-- usa: o painel grava `agendamento_servicos` direto na tabela, e ele escrevia
-- `sv.preco` cru — foi assim que nasceram os R$ 40 de diferença lá em cima.
--
-- Aqui o banco reescreve o preço da linha com a resposta da escada, sempre, em
-- toda marcação. A tela pode errar; a linha gravada não.
--
-- ⚠ E SÓ NO INSERT. Um `update` na linha é conserto feito à mão pela recepção
-- — "combinei R$ 100 com ela" — e recalcular por cima disso desfaria a
-- combinação na frente da cliente. O congelamento continua sendo o que era:
-- vale o que foi decidido na hora de marcar.
-- ---------------------------------------------------------------------------
/* ⚠ E ELE PREENCHE O QUE VEIO EM BRANCO — NÃO REESCREVE O QUE VEIO DECIDIDO.

   A primeira versão reescrevia sempre, e a bateria mostrou o preço disso: o
   `sem-comanda.test.mjs` tem um caso chamado "atendimento que não custou
   nada", e ele passou a custar. A recepção lança uma CORTESIA por R$ 0,00 — ou
   uma manutenção coberta — e o gatilho devolvia o preço de tabela por cima.
   Não é caso raro, e o arquivo de teste já dizia isso por escrito.

   Reescrever sempre resolveria o defeito antigo (a recepção cobrando o preço
   do catálogo) ao custo de tirar dela o direito de combinar um valor. Os dois
   são dinheiro, e o segundo é pior: é o sistema desfazendo, em silêncio, o que
   a pessoa acabou de decidir na frente da cliente.

   Então o contrato é: QUEM NÃO DISSE, O BANCO DIZ. O `agendar()` do link manda
   nulo de propósito e recebe a escada; a recepção manda o número que ela quer,
   inclusive zero. O que impede a recepção de mandar o número ERRADO não é mais
   este gatilho — é o `precoDaEscada()` do painel, que responde a mesma escada
   e é comparado com o Postgres, caso a caso, no `preco.test.mjs`. */
create or replace function public.tg_preco_do_agendamento()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_prof   uuid;
  v_inicio timestamptz;
begin
  if new.preco is not null then return new; end if;

  select a.profissional_id, a.inicio into v_prof, v_inicio
    from public.agendamentos a where a.id = new.agendamento_id;

  -- Agendamento que não existe não acontece: a chave estrangeira barra antes.
  -- Esta saída é para a ordem de execução dentro de uma transação.
  if v_prof is null or v_inicio is null then new.preco := 0; return new; end if;

  new.preco := public.preco_do_servico(new.servico_id, v_prof, v_inicio);
  return new;
end $$;

/* ⚠ E O `default 0` PRECISA SAIR, senão o gatilho acima nunca vê um nulo.

   Com ele, omitir a coluna dá ZERO — e zero é indistinguível de "a recepção
   lançou uma cortesia". O contrato "quem não disse, o banco diz" só existe se
   houver como NÃO DIZER, e em SQL isso é o nulo.

   O `not null` fica: ele é conferido DEPOIS dos gatilhos `before`, então a
   linha nunca chega ao disco sem preço. O que muda é só quem preenche. */
alter table public.agendamento_servicos alter column preco drop default;

drop trigger if exists tg_preco_agend_servico on public.agendamento_servicos;
create trigger tg_preco_agend_servico
  before insert on public.agendamento_servicos
  for each row execute function public.tg_preco_do_agendamento();

comment on function public.tg_preco_do_agendamento() is
  'Reescreve o preço da linha do agendamento com a escada do banco. É o que faz a regra valer também para o que a recepção marca.';

-- ---------------------------------------------------------------------------
-- 6) "A PARTIR DE R$ X", PARA A CAPA
--
-- Na capa a cliente ainda não escolheu dia nem hora, então não existe UM
-- preço — existe uma faixa. Mostrar o preço cheio de quem tem promoção de
-- terça é esconder a promoção; mostrar o mais barato como se fosse o preço é
-- prometer o que ela talvez não consiga.
--
-- Então a vitrine leva os dois números: o de sempre, e o menor que pode
-- acontecer dentro da janela que a agenda tem aberta. A tela escreve "a partir
-- de" só quando os dois diferem.
--
-- ⚠ A JANELA É A DA AGENDA, e não "todas as regras". Uma promoção que já
-- venceu, ou que só começa em agosto, não pode puxar o "a partir de" de hoje
-- para baixo — a cliente não consegue marcar lá.
-- ---------------------------------------------------------------------------
create or replace function public.preco_minimo_do_servico(
  p_servico uuid, p_ate date)
returns numeric language sql stable set search_path = public as $$
  select least(
    (select sv.preco from public.servicos sv where sv.id = p_servico),
    (select min(r.preco) from public.precos_regras r
      where r.ativo and r.servico_id = p_servico
        and (r.de  is null or r.de  <= p_ate)
        and (r.ate is null or r.ate >= current_date)))::numeric(10,2)
$$;

comment on function public.preco_minimo_do_servico(uuid, date) is
  'O menor preço que pode acontecer para este serviço dentro da janela aberta da agenda. Serve para o "a partir de" da capa.';

-- ---------------------------------------------------------------------------
-- 7) QUEM PODE CHAMAR
--
-- ⚠ NENHUMA VAI PARA O `anon`, e não é esquecimento.
--
-- O link não chama nada disto: ele recebe os preços prontos dentro da
-- `vitrine()`, que é `security definer` e já peneira o que pode sair. Abrir
-- `preco_do_servico()` ao anônimo seria entregar uma calculadora da tabela de
-- preços de QUALQUER salão a quem adivinhasse um id — inclusive dos preços por
-- profissional, que é acerto interno da casa.
--
-- O gatilho roda como dono e não precisa de grant nenhum.
-- ---------------------------------------------------------------------------
revoke all on function public.preco_regra_que_vale(uuid, uuid, timestamptz) from public;
revoke all on function public.preco_do_servico(uuid, uuid, timestamptz)     from public;
revoke all on function public.preco_dos_servicos(uuid, uuid[], timestamptz) from public;
revoke all on function public.preco_minimo_do_servico(uuid, date)           from public;

/* ⚠ E A AJUDANTE VAI JUNTO, senão as duas de cima são promessa vazia.

   `preco_do_servico()` chama `preco_regra_que_vale()`, e NENHUMA das duas é
   `security definer` — de propósito: assim o RLS continua valendo, e quem
   pergunta só recebe resposta sobre o salão em que tem vínculo. Mas função
   sem `definer` roda como quem chamou, e quem chamou precisa alcançar as duas.

   Eu tinha dado grant só nas duas de fora. O painel recebia
   `permission denied for function preco_regra_que_vale` — e só apareceu
   quando o teste chamou a função direto, porque de dentro do `agendar()` e do
   gatilho, que são `definer`, ela sempre funcionou. Grant pela metade é a
   funcionalidade que existe para quem tem privilégio e some para o resto. */
grant execute on function public.preco_regra_que_vale(uuid, uuid, timestamptz)
  to authenticated;
grant execute on function public.preco_do_servico(uuid, uuid, timestamptz)
  to authenticated;
grant execute on function public.preco_dos_servicos(uuid, uuid[], timestamptz)
  to authenticated;
