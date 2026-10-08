#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a forma de pagamento — o teste tem de reprovar.
#
#    bash tests/bancada/subir.sh                       (noutro terminal)
#    bash tests/mutacoes-pagamento.sh
#
#  O teste é o tests/forma-pagamento.test.mjs. A do banco muda o 09_cliente,
#  aplica na bancada e devolve o original — no arquivo e no banco.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/forma-pagamento.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html agendar.html dados.js estilo.css supabase/09_cliente.sql"
SQLS="supabase/09_cliente.sql"
guarda(){ echo "/tmp/mfp-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
aplicar(){ for f in $SQLS; do $PSQL -f "$f" >/dev/null 2>&1 || return 1; done; }
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  aplicar || echo "  !! não consegui devolver o SQL original à bancada"
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if ! aplicar; then
    echo "  ✗ NÃO RODOU — o SQL mutante não entrou no banco ($1)"; perdida=$((perdida+1))
    restaurar; return 0
  fi
  if node "$T" >/tmp/mfp-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mfp-saida.txt) reprovações)"
    morta=$((morta+1))
  fi
  restaurar
  return 0
}

troca(){ python3 - "$1" "$2" "$3" <<'PY'
import sys
arq, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(arq, encoding='utf-8').read()
n = s.count(de)
if n != 1:
    print('!! o trecho aparece %d vezes em %s' % (n, arq)); sys.exit(9)
open(arq, 'w', encoding='utf-8').write(s.replace(de, para, 1))
PY
  local r=$?
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. banco: o agendar() não grava a forma"
troca supabase/09_cliente.sql \
  "       (v_cupom->>'cupom_id')::uuid, v_desconto, v_forma)" \
  "       (v_cupom->>'cupom_id')::uuid, v_desconto, null)" \
  && rodar "a escolha da cliente se perde"

echo "2. banco: grava forma que o salão não aceita"
troca supabase/09_cliente.sql \
  "           and not v_aceitas ? v_forma) then" \
  "           and false) then" \
  && rodar "dinheiro num salão que só aceita Pix"

echo "3. link: a confirmação não pergunta"
troca agendar.html \
  "  desenharFormaPagamento();
  desenharCupomAgenda();" \
  "  desenharCupomAgenda();" \
  && rodar "a pergunta some"

echo "4. link: marca sem escolher"
troca agendar.html \
  "  if(faltaFormaPagamento()) return;" \
  "  ;" \
  && rodar "o salão não sabe como ela paga"

echo "5. link: a escolha não sobe"
troca agendar.html \
  "          ? { p_forma_pagamento: escolha.formaPagamento } : {})," \
  "          ? {} : {})," \
  && rodar "a tela mostra Pix e o banco não sabe"

echo "6. link: oferece forma que o salão não aceita"
troca agendar.html \
  "  return pag && pag.formas.length ? todas.filter(([k]) => pag.formas.includes(k)) : todas;" \
  "  return todas;" \
  && rodar "dinheiro aparece num salão que só aceita Pix"

echo "7. link: o resumo não mostra a forma"
troca agendar.html \
  "        ? linha('cartao', 'Pagamento (no salão)', escapar(nomeDaForma(escolha.formaPagamento))) : '')" \
  "        ? '' : '')" \
  && rodar "ela confirma sem ver o que escolheu"

echo "8. link: Meus horários não mostra a forma"
troca agendar.html \
  "            nomeDaForma(a.forma_pagamento) ? ' · ' + escapar(nomeDaForma(a.forma_pagamento)) : ''}</div></div>" \
  "            ''}</div></div>" \
  && rodar "ela não lembra o que disse"

echo "9. painel: o cartão do dia não mostra a forma"
troca app.html \
  "          \${nomeDaFormaPagamento(a.formaPagamento)
            ? \`<span class=\"dc-pag\">" \
  "          \${false
            ? \`<span class=\"dc-pag\">" \
  && rodar "a recepção não vê como ela vai pagar"

echo "10. painel: trocar a forma no detalhe não grava"
troca app.html \
  "  if(forma) a.formaPagamento = forma.value || null;" \
  "  ;" \
  && rodar "a recepção troca e volta o de antes"

echo "11. painel: a comanda não vem com a forma"
troca app.html \
  "  if(cForma && doAg && nomeDaFormaPagamento(doAg.formaPagamento)) cForma.value = doAg.formaPagamento;" \
  "  ;" \
  && rodar "o balcão procura de novo na lista"

echo "12. painel: o + Agendamento não grava a forma"
troca app.html \
  "    formaPagamento: (document.getElementById('fFormaPag') || {}).value || null," \
  "    formaPagamento: null," \
  && rodar "marcado por telefone sem a forma"

echo "13. dados.js: a coluna não é traduzida"
troca dados.js \
  "pacoteClienteId:'pacote_cliente_id', formaPagamento:'forma_pagamento'," \
  "pacoteClienteId:'pacote_cliente_id'," \
  && rodar "o painel não lê nem grava a forma"

echo "14. cor escrita na escolha"
troca estilo.css \
  ".cf-pag-op.on{ border-color:var(--ac-600);" \
  ".cf-pag-op.on{ border-color:#123456;" \
  && rodar "a escolha não segue o tema"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
