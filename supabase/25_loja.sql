-- ===========================================================================
-- AgendaPro — 25: a loja na página da cliente
--
-- A cliente vê os produtos que o dono marcou, põe no carrinho, e manda o
-- pedido pelo WhatsApp DELA. Não há checkout, não há pagamento na página, e
-- não há pedido gravado: quem fecha a venda é a conversa.
--
-- ── POR QUE O CARRINHO NÃO PASSA PELA NOSSA API DO WHATSAPP ───────────────
-- Porque o link `wa.me` abre o WhatsApp da PRÓPRIA cliente. Isso custa zero,
-- não depende de modelo aprovado nem da verificação da Meta, e — o que mais
-- importa — é ela quem escreve primeiro. Isso abre a janela de 24 horas, e o
-- dono pode responder à vontade: negociar, combinar entrega, mandar o Pix.
--
-- Pela nossa API seria uma mensagem de negócio para o dono: custo por envio,
-- modelo aprovado, e ele SEM PODER RESPONDER pelo mesmo caminho.
--
-- ── ⚠ E UMA COISA QUE NÃO DÁ PARA IMPEDIR ────────────────────────────────
-- A mensagem é montada na tela e entregue ao WhatsApp da cliente, onde ela
-- pode editar o texto antes de enviar. O preço que chega ao dono NÃO é
-- vinculante; quem confere é ele, ao montar a comanda.
--
-- Isso não é defeito a consertar: é a consequência de o pedido ser uma
-- conversa. É, também, mais um motivo para isto não ser um checkout — num
-- checkout o preço teria que valer, e aqui ele não tem como valer.
--
-- Este arquivo só reescreve a `vitrine()`. Ela é uma função SQL monolítica:
-- não há como acrescentar uma chave sem reapresentá-la inteira — e por isso
-- ela foi RECORTADA do 06_vitrine.sql por script, não redigitada. Cópia
-- inteira à mão é onde se perde uma linha sem ninguém notar, e o
-- `loja.test.sql` cobra que nenhuma chave antiga sumiu.
-- ===========================================================================

/* ── ⚠ UMA COLUNA QUE NÃO É DESTE MÓDULO, E MESMO ASSIM MORA AQUI ──────────
   `servicos.dias` é do 31_dias_servico.sql — é lá que a regra vive, com a
   explicação inteira. Só a DECLARAÇÃO precisa vir antes, e é por um motivo do
   Postgres, não de arquitetura: `create or replace function` de função SQL
   COMPILA o corpo na hora. A `vitrine()` logo abaixo lê `v.dias`, então sem a
   coluna já existente ela nem chega a ser criada — o install para com
   "column v.dias does not exist".

   Declarar no 31 não resolve: nas DUAS montagens (00_tudo e 98_modulos) o 25
   roda antes do 31. Aconteceu exatamente assim, e o banco recusou o arquivo
   inteiro.

   `if not exists` deixa a linha inofensiva: num banco que já tem a coluna ela
   não faz nada, e o 31 não a declara de novo para não haver duas verdades
   sobre o mesmo tipo. */
alter table public.servicos
  add column if not exists dias smallint[];

/* ── ⚠ E A TABELA DAS REGRAS DE PREÇO, PELA MESMÍSSIMA RAZÃO ──────────────
   A `vitrine()` logo abaixo lê `precos_regras` para montar o "a partir de" e
   a lista de regras que a página usa. Corpo de função SQL compila na hora:
   sem a tabela já existente, a `vitrine()` nem chega a ser criada e o install
   inteiro para com "relation public.precos_regras does not exist".

   Aconteceu exatamente assim — nos dois pacotes, e também na colagem em linha
   única. Declarar só no 33 não resolve: nas duas montagens o 25 roda antes.

   O dono da funcionalidade continua sendo o 33: é lá que estão o RLS, as
   policies, os grants, a escada de preço e o gatilho. Aqui fica só o que a
   `vitrine()` precisa enxergar para compilar. */
create table if not exists public.precos_regras (
  id              uuid primary key default gen_random_uuid(),
  salao_id        uuid not null references public.saloes(id) on delete cascade,
  servico_id      uuid not null references public.servicos(id) on delete cascade,
  profissional_id uuid references public.profissionais(id) on delete cascade,
  preco           numeric(10,2) not null check (preco >= 0),
  de              date,
  ate             date,
  dias            smallint[],
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

/* Pelo mesmo motivo, a do 32_produto_cadastro.sql: o preço pode ficar
   escondido da cliente sem o produto sumir da loja. Padrão `true`, que é o
   que a loja sempre fez — nenhum produto que já existe muda de comportamento. */
alter table public.produtos
  add column if not exists preco_visivel boolean not null default true;

create or replace function public.vitrine(p_slug text)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'salao', jsonb_build_object(
      'id', s.id, 'slug', s.slug, 'nome', s.nome, 'tipo', s.tipo,
      'logo', s.logo, 'capa', s.capa,
      'telefone', s.telefone, 'whatsapp', s.whatsapp,
      'endereco', s.endereco, 'fuso', s.fuso,
      -- A tela precisa saber até quando desenhar o calendário. Sai daqui
      -- pronto, já com o limite aplicado, para a tela não ter que repetir a
      -- regra — e não ter como discordar dela.
      'diasLiberados', public.dias_liberados(s.id),

      /* ── A APARÊNCIA QUE O SALÃO ESCOLHEU ──────────────────────────────
         Só as três chaves visuais, nomeadas uma a uma — nunca o `cfg`
         inteiro. `cfg` é jsonb e vai crescer; devolvê-lo por atacado
         significa publicar para qualquer visitante toda configuração que
         alguém puser lá no futuro, sem ninguém decidir isso. Chave nova só
         aparece aqui se for escrita aqui, de propósito.

         Nulo quer dizer "não escolheu", e a tela usa o padrão dela — assim
         salão antigo, criado antes disto existir, continua bonito sem
         precisar de migração. */
      'cor',  s.cfg->>'cor',
      'tema', s.cfg->>'tema',
      /* ── ⚠ AS QUATRO PENEIRAS, E POR QUE NENHUMA USA `::` DIRETO ──────
         `'abacaxi'::boolean` e `'abacaxi'::int` LEVANTAM no Postgres — não
         devolvem nulo. Dentro da `vitrine()` isso não é "o ajuste não pega":
         é a função inteira caindo, e ela é a ÚNICA porta da página da
         cliente. A casa sai do ar por um caractere, com o link que o salão
         mandou no WhatsApp.

         Medido, uma chave por vez, num banco de verdade: as quatro derrubavam
         a `vitrine()`. Eram as últimas — o `loja` e o `usaServicos` já tinham
         sido peneirados; estas ficaram para trás porque eu consertei a que
         estava mexendo e não varri o resto.

         ⚠ E O LADO SEGURO NÃO É O MESMO NOS QUATRO.

         `brilho` nasce LIGADO: lixo deixa ligado, que é o visual de hoje.
         `precoNaCapa` nasce DESLIGADO, e a peneira é invertida — só publica
         preço quem escreveu exatamente que quer. Lixo aqui não pode revelar
         valor que o dono não mandou mostrar; é o único dos quatro em que o
         erro custa dinheiro.
         `capaFoco` e `veu` são números sem padrão: lixo vira nulo, e a página
         usa o que ela já usava quando a chave não existia. */
      'precoNaCapa', lower(btrim(coalesce(s.cfg->>'precoNaCapa', 'false')))
                       in ('true', 't', '1', 'yes', 'sim'),
      -- A imagem de fundo da página, que o dono anexa em Identidade visual.
      -- Mora no `cfg` e não numa coluna própria de propósito: `cfg` é jsonb
      -- e já existe, então nenhum salão precisa de migração de tabela.
      'fundo', s.cfg->>'fundo',
      -- O brilho do botão principal. Ausente quer dizer LIGADO: é o padrão, e
      -- assim salão criado antes disto existir já nasce com ele.
      'brilho', lower(btrim(coalesce(s.cfg->>'brilho', 'true')))
                  not in ('false', 'f', '0', 'no', 'nao', 'não'),
      -- A letra do nome na capa. Nulo = a tela decide pelo tipo do negócio.
      'letra', s.cfg->>'letra',
      /* De onde sai o slide da capa: 'servicos' (as fotos dos serviços) ou
         'galeria' (as mídias que o dono subiu). E a galeria em si — uma
         lista de {url, tipo, legenda}. Vem nomeada, como todo o resto: o
         `cfg` inteiro nunca é devolvido. */
      'slideDe', s.cfg->>'slideDe',
      'galeria', coalesce(s.cfg->'galeria', '[]'::jsonb),
      -- Enquadramento da foto de capa (0 = topo à vista, 100 = pé) e quanto
      -- da imagem de fundo aparece por baixo do véu. Nulo = o padrão da tela.
      'capaFoco', case when s.cfg->>'capaFoco' ~ '^[0-9]+$'
                       then (s.cfg->>'capaFoco')::int end,
      'veu', case when s.cfg->>'veu' ~ '^[0-9]+$'
                  then (s.cfg->>'veu')::int end,
      /* Quanto os cartões fecham sobre a foto de fundo: 'auto', 'vidro' ou
         'fechado'. Nulo = 'auto', que é o que a tela faz sozinha — então
         salão criado antes disto não precisa de migração nenhuma.

         ⚠ Precisa ESTAR AQUI para existir. O `cfg` inteiro nunca é
         devolvido, cada chave é nomeada uma a uma, e ajuste que não aparece
         nesta lista fica preso no painel: o dono escolhe, o painel grava, a
         prévia obedece, e a página da cliente nunca fica sabendo. */
      'cartoes', s.cfg->>'cartoes',

      /* A FORMA do cartão de serviço: `reta` (o de sempre) ou
         `elegante`. Ausente vale `reta`, então salão criado antes
         disto existir não muda de aparência e não há migração.

         ⚠ É outro eixo, e não um valor de `cartoes`. Aquele decide o
         quanto o cartão FECHA sobre a foto de capa; este decide a
         forma. Juntar os dois tornaria impossível pedir moldura
         elegante com fundo de vidro. */
      'moldura', coalesce(s.cfg->>'moldura', 'reta'),

      /* ── ⚠ OS DOIS MÓDULOS DA CASA ────────────────────────────────────
         `usaServicos` e `loja` dizem com o que o estabelecimento trabalha:
         agenda, loja, ou as duas. Os dois nascem LIGADOS — é o que todo salão
         já é hoje, e nenhum deles muda de comportamento por causa destas
         linhas.

         `loja` já existia e já peneirava a lista de produtos lá embaixo. Era
         meio interruptor: o banco o respeitava, nenhuma tela o ligava, e a
         página da cliente nem o lia. Agora ele é a outra metade de um par, e
         a capa se monta a partir dos dois. Ausente = ligada, porque os
         PRODUTOS já nascem fechados um a um — exigir dois "sim" faria o dono
         marcar o produto e não entender por que nada apareceu.

         ⚠ E O NOME É `usaServicos`, NÃO `servicos`. A vitrine já devolve uma
         chave `servicos` — é a LISTA. Duas coisas diferentes com o mesmo nome
         no mesmo objeto é o tipo de colisão que compila, roda, e entrega a
         lista onde alguém esperava um sim/não.

         ⚠ E A PENEIRA É DE TEXTO, NÃO `::boolean`. Estava `(...)::boolean`
         aqui — copiado sem pensar quando o `loja` nasceu, e sem consequência
         enquanto NENHUMA TELA escrevia a chave: o `cfg` só continha o que o
         painel punha, e o painel não punha nada. A partir de agora o dono
         liga e desliga isto, e `'abacaxi'::boolean` LEVANTA no Postgres — não
         devolve nulo. Um `cfg` com lixo derrubaria a `vitrine()` inteira, que
         é a única porta da página da cliente: a casa toda sairia do ar por um
         caractere.

         É a mesma armadilha do `antecedenciaMin` com `'abc'::int` no 14, e a
         mesma resposta do `usa_comanda()` no 29 — a terceira vez que ela
         aparece neste projeto. Só desliga quem escreveu exatamente que quer
         desligar; qualquer outra coisa deixa ligado, que é o lado seguro.

         (Inline, e não uma chamada ao `usa_comanda()`: esta é uma função SQL,
         que compila o corpo na hora, e o 29 roda DEPOIS do 25 nos dois
         pacotes. Chamar dali seria a mesma pedra do `v.dias` lá em cima.) */
      'loja', lower(btrim(coalesce(s.cfg->>'loja', 'true')))
                not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'usaServicos', lower(btrim(coalesce(s.cfg->>'usaServicos', 'true')))
                       not in ('false', 'f', '0', 'no', 'nao', 'não'),

      /* ── OS SERVIÇOS QUE APARECEM NA CAPA ─────────────────────────────
         Lista de ids que o dono marcou como destaque. Um salão com vinte
         serviços não cabe numa primeira dobra de celular: sem escolha, a
         capa vira um catálogo que ninguém rola até o fim, e o serviço que
         paga a conta fica embaixo do que ninguém pede.

         ⚠ VAZIO NÃO QUER DIZER "NENHUM", quer dizer "não escolhi" — e aí a
         capa decide sozinha (os primeiros, com foto na frente). Tratar vazio
         como "esconda tudo" deixaria sem vitrine todo salão que já existe, no
         dia da atualização, sem ninguém ter pedido.

         Fica no `cfg`, e não numa coluna de `servicos`, porque é uma decisão
         da CAPA: qual é a vitrine desta casa. Em `servicos.destaque` ela
         viraria uma propriedade do serviço, e a mesma pergunta voltaria no
         dia em que a capa quisesse ORDEM — que o id numa lista já dá de
         graça, e uma coluna booleana não dá. */
      'destaques', coalesce(s.cfg->'destaques', '[]'::jsonb),

      /* ── DE QUANTO EM QUANTO TEMPO O LINK OFERECE HORÁRIO ─────────────
         15, 30 ou 60 minutos. Ausente vale 15, que é o que a agenda sempre
         fez — salão que já usa o sistema não pode acordar com a lista de
         horários diferente sem ter pedido.

         ⚠ ISTO É APARÊNCIA, NÃO DISPONIBILIDADE. A `horarios_livres()`
         continua calculando de 15 em 15, e é ela que decide o que EXISTE.
         Este número só RALEIA a lista que a cliente vê: um encaixe de 08:15
         lançado no balcão continua valendo, e a recepção continua podendo
         marcar em qualquer minuto.

         ⚠ E O CAST PASSA POR UMA PENEIRA DE TEXTO, de propósito.
         `(s.cfg->>'passoHorarios')::int` com lixo dentro — "abc", ou uma
         string vazia gravada por engano — não devolve nulo: ele LEVANTA
         ERRO, e a `vitrine()` inteira morre junto. Quer dizer: a página da
         cliente deixaria de abrir por causa de um valor torto numa chave de
         aparência. É armadilha velha conhecida deste projeto, e a saída é
         sempre a mesma — comparar como texto antes de converter. */
      'passoHorarios', case
        when s.cfg->>'passoHorarios' in ('15','30','60')
          then (s.cfg->>'passoHorarios')::int else 15 end,

      /* ── A CAMADA DE PERSONALIZAÇÃO POR ESTABELECIMENTO ────────────────
         Cinco chaves, e as cinco AUSENTES no salão que nunca mexeu — que é
         o estado de todo salão que já existe. Ausente aqui não é "vazio": é
         "faça como sempre fez", e a página da cliente trata assim.

         ⚠ `cores` É UM OBJETO COM BURACOS, DE PROPÓSITO. Cada cor que o dono
         NÃO escolheu fica de fora, e a tela a calcula a partir da principal,
         como faz desde sempre — medindo contraste para decidir a letra. Se
         gravássemos as nove sempre, a conta de hoje congelaria dentro do
         salão, e melhorar o cálculo depois não chegaria em ninguém.

         `modo` ausente vale `atual`: o visual de hoje, sem nada novo ligado.
         É o que garante que ninguém acorde com a página diferente. */
      'cores',     coalesce(s.cfg->'cores', '{}'::jsonb),
      'modo',      coalesce(s.cfg->>'modo', 'atual'),
      'logoForma', coalesce(s.cfg->>'logoForma', 'circular'),
      -- A espessura do anel em volta da logo. `media` é o que a página fazia
      -- antes desta escolha existir, então salão que nunca mexeu não muda.
      'logoBorda', coalesce(s.cfg->>'logoBorda', 'media'),
      -- A forma da caixa do carrossel. `panoramico` é o 16/8 de antes.
      'slideForma', coalesce(s.cfg->>'slideForma', 'panoramico'),
      /* ── A FITA DO CARRINHO, EM METAL ─────────────────────────────────
         Cinco chaves, e as cinco AUSENTES no salão que nunca mexeu. Ausente
         não quer dizer "desligado": quer dizer "o metal de fábrica", que é o
         mesmo do botão de agendar.

         ⚠ `fitaBrilho` SAI COMO BOOLEANO, com a peneira de letra. Não é
         capricho: é a mesma armadilha do `loja` logo acima, e aqui ela morde
         mais fácil porque esta chave é gravada por um botão de dois estados
         — se alguém um dia gravar a string "nao" em vez de `false`, um
         `::boolean` derruba a `vitrine()` inteira. */
      'fitaMetal',  coalesce(s.cfg->>'fitaMetal', 'media'),
      'fitaBrilho', lower(btrim(coalesce(s.cfg->>'fitaBrilho', 'true')))
                      not in ('false', 'f', '0', 'no', 'nao', 'não'),
      'fitaTempo',  coalesce(s.cfg->>'fitaTempo', 'media'),
      /* Sem coalesce: nulo é "não escolhi", e a página herda a cor do botão.
         Um padrão aqui seria uma cor cravada no banco. */
      'fitaCor',    s.cfg->>'fitaCor',
      'fitaBorda',  coalesce(s.cfg->>'fitaBorda', 'reta'),
      'fundoTipo', coalesce(s.cfg->>'fundoTipo', 'cor'),
      'gradiente', s.cfg->>'gradiente'
    )
    /* ── HORÁRIOS, PAGAMENTOS E A APRESENTAÇÃO ──────────────────────────────
       Num SEGUNDO jsonb_build_object, somado ao primeiro com `||`. Função no
       Postgres aceita no máximo 100 argumentos, e o objeto de cima já passa
       de 70 — mais uma rodada de chaves ali e a vitrine() inteira deixaria
       de compilar, levando junto a página de todos os salões.

       Nenhum cast: o que não for objeto vira nulo, e a página peneira de novo
       (funcionamento.js). `::jsonb` ou `::int` em texto do dono já derrubou a
       vitrine inteira neste projeto, mais de uma vez. */
    || jsonb_build_object(
      'funcionamento', case when jsonb_typeof(s.cfg->'funcionamento') = 'object'
                            then s.cfg->'funcionamento' end,
      'pagamentos',    case when jsonb_typeof(s.cfg->'pagamentos') = 'object'
                            then s.cfg->'pagamentos' end,
      'sobre',     nullif(left(btrim(coalesce(s.cfg->>'sobre', '')), 600), ''),
      'instagram', nullif(left(regexp_replace(coalesce(s.cfg->>'instagram', ''),
                                              '[^A-Za-z0-9._]', '', 'g'), 30), ''),
      /* Onde a foto de capa encontra o fundo. Só `reta` sai daqui; ausente
         (nulo) é o arco de sempre, então salão que nunca escolheu não muda. */
      'capaForma', case when s.cfg->>'capaForma' = 'reta' then 'reta' end,
      /* O estilo dos atalhos (Pagamentos, Horários, Informações). Só objeto
         passa, sem cast nenhum: os números são peneirados na página. Nulo é
         o cartão com borda de sempre. */
      'atalhos', case when jsonb_typeof(s.cfg->'atalhos') = 'object'
                      then s.cfg->'atalhos' end,
      /* O botão "Ver produtos" igual ao Agendar horário. Só 'metal' sai;
         nulo é o discreto de sempre. */
      'botaoProdutos', case when s.cfg->>'botaoProdutos' = 'metal' then 'metal' end
    ),

    /* ── ⚠ A LOJA, E OS DOIS CAMPOS QUE NÃO PODEM SAIR DAQUI ──────────────
       `custo` é quanto o DONO paga pelo produto. Publicar isso entrega a
       margem dele a qualquer concorrente que abra a página — e a página é
       pública por construção, sem login nenhum. `comissao_pct` é o acerto
       dele com a equipe, que também não é assunto de quem compra.

       Por isso cada campo é NOMEADO, um a um, e nunca `to_jsonb(p)`. Foi
       exatamente assim que três vazamentos apareceram na varredura de
       segurança deste projeto: função `security definer` devolvendo mais do
       que devia, sem ninguém ter decidido isso.

       ⚠ E REPARE NO QUE NÃO GOVERNA A LISTA: `estoque`.

       Seria natural esconder o que está com estoque zero. A coluna nasce ZERO
       e usá-la aqui marcaria como esgotado todo produto recém-cadastrado — e
       o dono passaria a tarde tentando entender por que a loja dele, cheia de
       produto, aparece vazia para a cliente.

       ── ⚠ E POR QUE ISSO NÃO MUDOU COM O MÓDULO 26 ─────────────────────
       Este comentário dizia "NADA no sistema movimenta o estoque — nem a
       comanda", e prometia que o "esgotado" entraria aqui no dia em que a
       comanda desse baixa. O 26_estoque.sql passou a dar, e a frase virou
       mentira. A CONCLUSÃO, porém, continua a mesma — e é por isso que a
       correção é do texto e não do código.

       Dar baixa não é o mesmo que saber quanto tem. O 26 só SUBTRAI: ninguém
       preenche a contagem inicial por ele. Salão que cadastra produto sem
       digitar quantidade continua com zero em tudo, e esconder por estoque
       continuaria escondendo a loja inteira de quem mais precisa dela.

       O "esgotado" entra no dia em que o estoque for verdade — o que depende
       de o dono ter contado, não de o sistema ter subtraído.

       Até lá, quem decide o que aparece é o `venda_online`, que é um clique
       consciente. E o pedido vai pelo WhatsApp justamente para a dona poder
       responder "essa cor acabou" — a mensagem termina em "pode confirmar o
       que tem disponível?" por este motivo. */
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', pr.id, 'nome', pr.nome, 'marca', pr.marca,
               'descricao', pr.descricao, 'foto', pr.foto,
               /* ⚠ NULO, e não o preço com uma marca do lado. Mandar o valor
                  e pedir para a tela não mostrar é publicar o preço mesmo
                  assim: ele viaja pela rede e fica visível a quem abrir o
                  inspetor. Preço escondido tem que sair escondido daqui. */
               'preco', case when pr.preco_visivel then pr.preco else null end)
             order by pr.nome)
        from public.produtos pr
       where pr.salao_id = s.id and pr.ativo and pr.venda_online
         and lower(btrim(coalesce(s.cfg->>'loja', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb),

    /* ── ⚠ `dias` PRECISA VIR JUNTO, E NÃO É ENFEITE ─────────────────────
       Quem RECUSA é o banco (`porque_nao_agenda`, no 31). Sem esta chave a
       página da cliente saberia que a segunda-feira não tem horário e não
       saberia POR QUÊ — e a faixa de dias marcaria o dia como "cheio", que é
       mentira: o salão está vazio, o serviço é que não é feito ali.

       "Cheio" manda a pessoa esperar uma vaga que nunca vai abrir. Com os
       dias na mão, a tela diz o que é e ela troca de dia num toque.

       Nulo ou vazio = todos os dias, igual ao banco. Serviço que já existe
       vem com nulo, e a tela não muda nada para ele. */
    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'nome', v.nome, 'categoria', v.categoria,
               'descricao', v.descricao, 'duracaoMin', v.duracao_min,
               'preco', v.preco, 'foto', v.foto,
               'dias', case when v.dias is null or cardinality(v.dias) = 0
                            then null else to_jsonb(v.dias) end,

               /* ── ⚠ O PREÇO DE VERDADE, E POR QUE ELE PRECISOU VIR ───────
                  Aqui saía só `v.preco`, o do catálogo. E o `agendar()` cobra
                  a escada: regra, preço do par, catálogo. MEDIDO na bancada,
                  com o corte a R$ 90 no catálogo e R$ 130 com a profissional:

                      a vitrine mostrava ......... R$  90
                      o agendar() marcava por .... R$ 130

                  Quarenta reais de surpresa no balcão — e a tela não estava
                  errada por descuido: ela nunca soube que existia um segundo
                  preço. Esta é a pior das divergências de dinheiro do
                  projeto, porque é a única que a CLIENTE paga.

                  `precoPorProf` são só os pares que DIFEREM do catálogo: um
                  salão onde todo mundo cobra igual não carrega nada a mais.

                  `regras` já vêm NA ORDEM EM QUE GANHAM. A página pega a
                  primeira que casar e pronto — sem repetir em JavaScript a
                  conta de especificidade do 33, que é onde um espelho desses
                  diverge do original com o tempo.

                  `precoMin` é o menor que pode acontecer na janela aberta da
                  agenda, contando pares e regras. É o "a partir de" da capa,
                  onde ainda não há dia nem profissional escolhidos. */
               'precoPorProf', (
                 select jsonb_object_agg(sp.profissional_id, sp.preco)
                   from public.servicos_profissionais sp
                   join public.profissionais p2 on p2.id = sp.profissional_id
                  where sp.servico_id = v.id and sp.preco is not null
                    and sp.preco <> v.preco and p2.ativo and p2.aceita_online),
               'regras', (
                 select jsonb_agg(jsonb_build_object(
                          'profissionalId', r.profissional_id, 'preco', r.preco,
                          'de', r.de, 'ate', r.ate,
                          'dias', case when r.dias is null
                                         or cardinality(r.dias) = 0
                                       then null else to_jsonb(r.dias) end,
                          'horaIni', r.hora_ini, 'horaFim', r.hora_fim)
                        order by (case when r.profissional_id is not null then 8 else 0 end)
                               + (case when r.dias is not null
                                        and cardinality(r.dias) > 0 then 4 else 0 end)
                               + (case when r.hora_ini is not null then 2 else 0 end)
                               + (case when r.de is not null or r.ate is not null
                                       then 1 else 0 end) desc,
                                 r.criado_em desc, r.id desc)
                   from public.precos_regras r
                  where r.servico_id = v.id and r.ativo
                    and (r.ate is null or r.ate >= public.hoje_no_salao(s.id))
                    and (r.de  is null or r.de  <= public.hoje_no_salao(s.id)
                                               + public.dias_liberados(s.id))),
               /* ⚠ A CONTA VEM ESCRITA AQUI, e não por uma chamada ao
                  `preco_minimo_do_servico()` do 33. Mesma pedra da tabela
                  logo acima: o corpo desta função compila agora, e o 33 só
                  roda daqui a oito arquivos. A função lá continua existindo
                  para quem precisar dela de fora; esta é a cópia que a
                  vitrine precisa enxergar sem depender da ordem. */
               'precoMin', least(
                 v.preco,
                 (select min(r2.preco) from public.precos_regras r2
                   where r2.ativo and r2.servico_id = v.id
                     and (r2.de  is null or r2.de  <= public.hoje_no_salao(s.id)
                                                    + public.dias_liberados(s.id))
                     and (r2.ate is null or r2.ate >= public.hoje_no_salao(s.id))),
                 (select min(sp.preco) from public.servicos_profissionais sp
                   join public.profissionais p3 on p3.id = sp.profissional_id
                  where sp.servico_id = v.id and sp.preco is not null
                    and p3.ativo and p3.aceita_online)))
             order by v.categoria nulls last, v.nome)
        from public.servicos v
       where v.salao_id = s.id and v.ativo and v.aceita_online
         /* ⚠ O MÓDULO PENEIRA A LISTA AQUI, e não só na tela. Deixar a lista
            sair e pedir para a página não desenhar seria publicar o catálogo
            de um salão que decidiu não trabalhar com serviços — visível a
            quem abrisse o inspetor. É a mesma trava que a loja já tinha, e
            pela mesma razão. */
         and lower(btrim(coalesce(s.cfg->>'usaServicos', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb),

    'profissionais', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'nome', coalesce(p.apelido, p.nome),
               'foto', p.foto,
               -- Lista vazia = faz tudo. É como um salão pequeno começa, e a
               -- tela já trata assim.
               'servicos', (select coalesce(jsonb_agg(sp.servico_id), '[]'::jsonb)
                              from public.servicos_profissionais sp
                             where sp.profissional_id = p.id))
             order by p.criado_em, p.id)
        from public.profissionais p
       where p.salao_id = s.id and p.ativo and p.aceita_online
         -- A cota do plano vale aqui também: profissional fora da cota não
         -- pode aparecer como opção, senão a cliente escolhe e leva um erro
         -- do gatilho na cara ao confirmar.
         and public.profissional_na_cota(p.id)), '[]'::jsonb)
  )
  from public.saloes s
  where s.slug = p_slug and s.status = 'ativo'
$$;
