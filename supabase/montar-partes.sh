#!/usr/bin/env bash
# ===========================================================================
# Gera 00_tudo_parte1.sql e 00_tudo_parte2.sql — o 00_tudo.sql em DUAS
# metades, para o SQL Editor do Supabase.
#
# ── POR QUE ─────────────────────────────────────────────────────────────────
# O 00_tudo.sql passou de 1 MB, e o editor recusa: "Query is too large to be
# run via the SQL Editor". O conteúdo é o MESMO, na MESMA ordem, cortado entre
# dois módulos (depois do 21_notificacoes) — cada metade com uns 500 KB, e
# folga para crescer. Cola-se a parte 1, roda; depois a parte 2, roda.
#
# Cortar entre módulos é seguro: cada módulo é feito para rodar sozinho e de
# novo (é assim que o tests/rodar.sh os carrega, um a um). A parte 2 só usa
# o que a parte 1 criou — a mesma ordem do arquivo inteiro.
#
# Gerado dos MESMOS arquivos-fonte, nunca escrito à mão. O montar.sh chama
# este no fim. Opcional: a pasta de onde ler os módulos (padrão: esta).
# ===========================================================================
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONTE="${1:-$AQUI}"

PARTE1="01_schema.sql 02_rls.sql 03_onboarding.sql 04_imagens.sql 05_agenda.sql 06_vitrine.sql 07_plataforma.sql 08_conta.sql 09_cliente.sql 10_campanhas.sql 11_equipe.sql 12_relatorios.sql 13_cobranca.sql 14_motor.sql 15_comanda.sql 16_comissao.sql 17_caixa.sql 18_painel.sql 19_teto_online.sql 20_corrida.sql 21_notificacoes.sql"
PARTE2="22_cotas.sql 23_assinatura_cartao.sql 24_produtos.sql 25_loja.sql 26_estoque.sql 27_pacotes.sql 28_sem_comanda.sql 29_confirmacao.sql 30_painel.sql 31_dias_servico.sql 32_produto_cadastro.sql 33_preco_regras.sql 34_cupons.sql 35_acesso.sql 36_excluir_conta.sql 37_pedidos.sql 38_suporte.sql 39_teste_unico.sql 40_saude.sql 41_ficha_equipe.sql 42_travas.sql 43_pacote_agenda.sql 44_pacote_comissao.sql 45_pacote_mensagens.sql 46_adicionais.sql 47_crediario.sql 48_cadastro_link.sql 49_remarcar.sql 50_pacote_excluir.sql"

cabeca() {
  cat <<CAB
-- ===========================================================================
-- AgendaPro — INSTALAÇÃO COMPLETA, PARTE $1 DE 2
--
-- O 00_tudo.sql ficou grande demais para o SQL Editor do Supabase, então ele
-- vai em duas partes. É o mesmo conteúdo, na mesma ordem.
--
--   1. Cole a PARTE 1 inteira no SQL Editor e clique em Run.
--   2. Depois cole a PARTE 2 inteira e clique em Run.
--   3. Por fim, rode o CONFERIR.sql.
--
-- Pode rodar de novo quantas vezes precisar: nada é apagado.
-- ===========================================================================

-- A TRAVA DOS ACENTOS (a mesma do 00_tudo.sql). O aviso e escrito sem acento
-- de proposito: ele precisa sair legivel justamente quando os acentos
-- chegaram trocados.
do \$\$
begin
  if encode(convert_to('ã', 'UTF8'), 'hex') <> 'c3a3' then
    raise exception 'PAREI SEM GRAVAR NADA: os acentos deste arquivo chegaram trocados (arquivo aberto com a codificacao errada). Abra a parte $1 pelo link do GitHub (raw), copie tudo e cole de novo.';
  end if;
end \$\$;

CAB
}

montar() {
  local n="$1" lista="$2" saida="$AQUI/00_tudo_parte$1.sql"
  cabeca "$n" > "$saida"
  for f in $lista; do
    {
      echo ''
      echo '-- ###########################################################################'
      echo "-- ## $f"
      echo '-- ###########################################################################'
      echo ''
      cat "$FONTE/$f"
    } >> "$saida"
  done
  echo "00_tudo_parte$n.sql: $(wc -c < "$saida") bytes"
}

montar 1 "$PARTE1"
montar 2 "$PARTE2"
