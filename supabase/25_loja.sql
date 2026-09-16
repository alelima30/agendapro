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
      'precoNaCapa', coalesce((s.cfg->>'precoNaCapa')::boolean, false),
      -- A imagem de fundo da página, que o dono anexa em Identidade visual.
      -- Mora no `cfg` e não numa coluna própria de propósito: `cfg` é jsonb
      -- e já existe, então nenhum salão precisa de migração de tabela.
      'fundo', s.cfg->>'fundo',
      -- O brilho do botão principal. Ausente quer dizer LIGADO: é o padrão, e
      -- assim salão criado antes disto existir já nasce com ele.
      'brilho', coalesce((s.cfg->>'brilho')::boolean, true),
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
      'capaFoco', (s.cfg->>'capaFoco')::int,
      'veu', (s.cfg->>'veu')::int,
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

      /* O interruptor da loja inteira. Ausente = ligada: os PRODUTOS já
         nascem fechados um a um, e exigir dois "sim" faria o dono marcar o
         produto e não entender por que nada apareceu. Serve para pausar a
         loja sem desmarcar vinte produtos. */
      'loja', coalesce((s.cfg->>'loja')::boolean, true)
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

       Seria natural esconder o que está com estoque zero. Só que a coluna
       nasce ZERO e NADA no sistema a movimenta — nem a comanda. Usá-la aqui
       marcaria como esgotado todo produto recém-cadastrado, e o dono passaria
       a tarde tentando entender por que a loja dele está vazia.

       Quem decide o que aparece é o `venda_online`, que é um clique
       consciente. Quando a comanda passar a dar baixa, o estoque vira verdade
       e o "esgotado" entra aqui — com o teste que hoje não teria como
       existir. */
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', pr.id, 'nome', pr.nome, 'marca', pr.marca,
               'descricao', pr.descricao, 'preco', pr.preco, 'foto', pr.foto)
             order by pr.nome)
        from public.produtos pr
       where pr.salao_id = s.id and pr.ativo and pr.venda_online
         and coalesce((s.cfg->>'loja')::boolean, true)), '[]'::jsonb),

    'servicos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'nome', v.nome, 'categoria', v.categoria,
               'descricao', v.descricao, 'duracaoMin', v.duracao_min,
               'preco', v.preco, 'foto', v.foto)
             order by v.categoria nulls last, v.nome)
        from public.servicos v
       where v.salao_id = s.id and v.ativo and v.aceita_online), '[]'::jsonb),

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
