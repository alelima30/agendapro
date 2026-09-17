-- ===========================================================================
-- AgendaPro — 28: o salão que não quer comanda nem caixa
--
-- "Não quero trabalhar com comanda e nem caixa. Abre, coloca os serviços e já
--  começa a trabalhar."
--
-- É um pedido comum, e é legítimo: manicure sozinha, barbeiro de cadeira
-- única, quem atende em casa. Para essa gente a comanda é papelada de um
-- movimento que ela já sabe de cor, e o caixa é conferir uma gaveta que só ela
-- abre.
--
-- ── ⚠ O QUE ESTAVA POR BAIXO DO PEDIDO ────────────────────────────────────
-- Comanda e caixa JÁ eram opcionais: nada obriga a abrir nenhum dos dois, e um
-- pagamento sem caixa aberto simplesmente fica sem gaveta (ver
-- `tg_pagamento_caixa` no 17). O pedido parecia ser só de tela.
--
-- Não era. TODO o dinheiro deste sistema nasce da comanda: o `relatorio()` do
-- 12 soma `comandas_totais` de comanda FECHADA, a comissão do 16 mora em
-- `comanda_itens`, e a baixa de estoque do 26 sai do item. Um salão que nunca
-- abrisse comanda teria o mês inteiro zerado — sem erro nenhum na tela, só o
-- número errado, que é a pior forma de errar.
--
-- ── A DECISÃO: UM CAMINHO DE DINHEIRO, DUAS TELAS ─────────────────────────
-- A saída NÃO foi fazer o relatório somar agendamento quando não há comanda.
-- Isso criaria duas verdades sobre faturamento — duas contas para manter
-- iguais para sempre, e a segunda nasceria errada no primeiro recurso que
-- alguém acrescentasse só de um lado.
--
-- Em vez disso, quando o interruptor está DESLIGADO o atendimento concluído
-- vira comanda sozinho: com os serviços do próprio agendamento, o pagamento
-- pelo total, e fechada na hora. Relatório, comissão e estoque continuam
-- lendo exatamente o que sempre leram. A palavra "comanda" é que some da
-- tela — a contabilidade não some.
--
-- ── E POR QUE NO GATILHO, E NÃO NO PAINEL ─────────────────────────────────
-- Porque "o que não está no gatilho não vale" — a lição que o 15 já tinha
-- pago. Concluir um atendimento acontece em mais de um lugar: a agenda da
-- recepção, a tela de quem atende, e um dia uma automação. Regra de dinheiro
-- escrita na tela é regra que o outro caminho não chama.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) O INTERRUPTOR
--
-- ⚠ O PADRÃO É LIGADO, e isso não é detalhe: a chave não existe em nenhum
-- salão de hoje, e se a ausência valesse "desligado" todos eles passariam a
-- gerar comanda automática amanhã, por cima das comandas de verdade que eles
-- abrem à mão.
--
-- ⚠ E A PENEIRA É DE TEXTO, não `::boolean`. `'abacaxi'::boolean` LEVANTA no
-- Postgres — não devolve nulo — e um `cfg` com lixo derrubaria a conclusão de
-- todo atendimento do salão. É a mesma armadilha que o `antecedenciaMin` do
-- 14 já tinha custado, com `'abc'::int`.
--
-- Só desliga quem escreveu exatamente que quer desligar. Qualquer outra coisa
-- — chave ausente, vazia, escrita errada — deixa ligado, que é o lado seguro:
-- um erro de digitação nunca apaga a comanda de ninguém.
-- ---------------------------------------------------------------------------
create or replace function public.usa_comanda(p_salao uuid)
returns boolean language sql stable set search_path = public as $$
  select coalesce(
    (select lower(btrim(coalesce(sa.cfg->>'usaComanda', 'true')))
              not in ('false', 'f', '0', 'no', 'nao', 'não')
       from public.saloes sa where sa.id = p_salao),
    true)
$$;

comment on function public.usa_comanda(uuid) is
  'O salão trabalha com comanda e caixa? cfg.usaComanda, padrão LIGADO. Desligado, o atendimento concluído vira comanda sozinho.';

-- ---------------------------------------------------------------------------
-- 2) "NÃO INFORMADO": A FORMA DE PAGAMENTO QUE FALTAVA
--
-- A comanda só fecha paga por inteiro — `tg_fechar_comanda` no 15 recusa com
-- "Ainda faltam R$ x". Então a comanda automática precisa de um pagamento, e
-- nenhuma das formas existentes servia.
--
-- Pôr 'dinheiro' seria mentira com consequência: no dia em que esse salão
-- resolvesse abrir o caixa, a gaveta passaria a esperar um dinheiro que nunca
-- entrou nela. 'cortesia' seria pior ainda — diria que o atendimento foi de
-- graça, e o faturamento sumiria.
--
-- `nao_informado` diz a verdade inteira: a cliente pagou, e o salão escolheu
-- não controlar por onde. É um fato sobre o SALÃO, não sobre a venda.
--
-- ⚠ A restrição é derrubada PELO NOME QUE ELA TEM, descoberto na hora. O
-- `01_schema.sql` a cria embutida na coluna, e o nome gerado pelo Postgres não
-- é promessa de ninguém. Acrescentar uma segunda restrição sem tirar a
-- primeira deixaria a antiga barrando 'nao_informado' — e o sintoma seria a
-- conclusão do atendimento falhando, longe daqui.
-- ---------------------------------------------------------------------------
do $$
declare v_nome text;
begin
  select con.conname into v_nome
    from pg_constraint con
   where con.conrelid = 'public.pagamentos'::regclass
     and con.contype = 'c'
     and con.conkey = array[(select a.attnum from pg_attribute a
                              where a.attrelid = 'public.pagamentos'::regclass
                                and a.attname = 'forma')]
   limit 1;
  if v_nome is not null then
    execute format('alter table public.pagamentos drop constraint %I', v_nome);
  end if;
end $$;

alter table public.pagamentos
  add constraint pagamentos_forma_check
  check (forma in ('dinheiro','pix','debito','credito',
                   'transferencia','cortesia','pacote','nao_informado'));

-- ---------------------------------------------------------------------------
-- 3) QUEM FOI O SISTEMA, E QUEM FOI GENTE
--
-- Sem esta coluna não há como desfazer: apagar "a comanda deste agendamento"
-- apagaria também a que a recepção montou à mão antes de o interruptor ser
-- desligado — com desconto, com itens acrescentados, com pagamento em duas
-- formas. Ninguém saberia por que sumiu.
--
-- Serve também para a tela: uma comanda automática não tem por que ser
-- editada, porque ela é o espelho do atendimento.
-- ---------------------------------------------------------------------------
alter table public.comandas
  add column if not exists automatica boolean not null default false;

comment on column public.comandas.automatica is
  'Nasceu sozinha ao concluir o atendimento, num salão sem comanda. Desmarcar o atendimento a apaga.';

-- ---------------------------------------------------------------------------
-- 4) ⚠ O GATILHO: CONCLUIR VIRA DINHEIRO
--
-- Cinco recusas antes de criar qualquer coisa, e nenhuma é dispensável:
--
--   · o salão usa comanda  → a tela dele faz isso, e melhor: com desconto,
--                            produto, forma de pagamento
--   · já existe comanda    → a recepção montou à mão. Uma segunda cobraria o
--                            atendimento duas vezes, e o índice único do 15
--                            derrubaria a conclusão inteira
--   · sem ficha de cliente → comanda sem cliente não existe no schema
--   · total zero           → ⚠ NÃO É CASO RARO: é o pacote. Uma manutenção
--                            coberta pelo pacote vale R$ 0,00, e
--                            `tg_fechar_comanda` recusa comanda sem itens com
--                            "Comanda sem itens não pode ser fechada" — a
--                            conclusão do atendimento morreria com essa frase,
--                            que não tem nada a ver com o que a pessoa fez.
--                            E está certo não criar: não houve dinheiro
--                            nenhum, a sessão do pacote é que foi gasta
--   · o serviço sumiu      → `left join`, para um serviço apagado do cadastro
--                            não levar o atendimento junto
--
-- A comissão NÃO é copiada daqui: o `tg_item_comissao` do 16 resolve a taxa
-- pelo cadastro, com a escada do profissional e do serviço. Mandar a de
-- `agendamento_servicos` seria congelar a taxa do dia da MARCAÇÃO, e o 16
-- existe justamente para isso não acontecer.
--
-- `aberta_por` fica nulo de propósito. Não foi ninguém: foi o sistema. Pôr o
-- nome de quem clicou seria dizer que aquela pessoa abriu uma comanda que ela
-- nunca viu.
-- ---------------------------------------------------------------------------
create or replace function public.tg_agendamento_sem_comanda()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_comanda uuid;
  v_total   numeric(10,2);
begin
  /* ── DESFAZER ────────────────────────────────────────────────────────────
     Vem primeiro porque é o caso que mais dói se faltar: a recepção conclui
     por engano, corrige, e o dinheiro de um atendimento que não houve fica no
     relatório do mês. Só apaga o que o sistema criou. */
  if coalesce(old.status, '') = 'concluido' and new.status <> 'concluido' then
    delete from public.comandas c
     where c.agendamento_id = new.id and c.automatica;
    return new;
  end if;

  if new.status <> 'concluido' or coalesce(old.status, '') = 'concluido' then
    return new;
  end if;

  if public.usa_comanda(new.salao_id) then return new; end if;
  if new.cliente_id is null then return new; end if;
  if exists (select 1 from public.comandas c
              where c.agendamento_id = new.id) then return new; end if;

  select round(coalesce(sum(s.preco), 0), 2) into v_total
    from public.agendamento_servicos s
   where s.agendamento_id = new.id;

  if v_total is null or v_total <= 0 then return new; end if;

  insert into public.comandas (salao_id, agendamento_id, cliente_id, automatica)
       values (new.salao_id, new.id, new.cliente_id, true)
    returning id into v_comanda;

  insert into public.comanda_itens (comanda_id, tipo, servico_id, descricao,
                                    qtd, preco_unit, profissional_id)
  select v_comanda, 'servico', s.servico_id,
         coalesce(sv.nome, 'Serviço'), 1, s.preco, new.profissional_id
    from public.agendamento_servicos s
    left join public.servicos sv on sv.id = s.servico_id
   where s.agendamento_id = new.id
   order by s.ordem;

  insert into public.pagamentos (comanda_id, forma, valor)
       values (v_comanda, 'nao_informado', v_total);

  update public.comandas
     set status = 'fechada', fechada_em = now()
   where id = v_comanda;

  return new;
end $$;

/* ⚠ AFTER, e não BEFORE.

   Os itens são lidos de `agendamento_servicos`, que aponta para o
   agendamento. Num BEFORE a linha ainda não está gravada no estado que o
   resto do gatilho enxerga, e o `insert` da comanda referenciaria um
   agendamento que, para ele, ainda não terminou de existir. */
drop trigger if exists tg_agend_sem_comanda on public.agendamentos;
create trigger tg_agend_sem_comanda
  after update of status on public.agendamentos
  for each row execute function public.tg_agendamento_sem_comanda();

-- ---------------------------------------------------------------------------
-- 5) Quem pode perguntar
--
-- `usa_comanda()` responde sobre CONFIGURAÇÃO, não sobre dinheiro: a página
-- pública nunca precisa dela, e a equipe precisa para a tela saber o que
-- esconder. Fica com `authenticated`.
-- ---------------------------------------------------------------------------
revoke all on function public.usa_comanda(uuid) from public, anon;
grant execute on function public.usa_comanda(uuid) to authenticated;
