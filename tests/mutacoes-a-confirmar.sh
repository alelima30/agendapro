#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o "a confirmar" da agenda: lista do dia, mês, grade
#  e o recado de horário novo.
#
#    python3 -m http.server 8099 --directory .   (noutro terminal)
#    bash tests/mutacoes-a-confirmar.sh
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/a-confirmar.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export BASE=${BASE:-http://127.0.0.1:8099/}

ARQS="app.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mac-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mac-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mac-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mac-saida.txt) reprovações)"
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
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA (ver mutacoes-modulos.sh).
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. a lista diz \"Pendente\" em vez de \"A confirmar\""
troca app.html \
  "              a.status === 'pendente' ? 'A confirmar' : (ROTULO_STATUS[a.status] || a.status)}</span></span>" \
  "              ROTULO_STATUS[a.status] || a.status}</span></span>" \
  && rodar "a etiqueta não diz o que fazer"

echo "2. sem o Confirmar no cartão"
troca app.html \
  "          \${a.status === 'pendente' ? \`<button type=\"button\" class=\"btn btn-primario btn-peq dc-confirmar\"" \
  "          \${false ? \`<button type=\"button\" class=\"btn btn-primario btn-peq dc-confirmar\"" \
  && rodar "tem que abrir a ficha para confirmar"

echo "3. Confirmar abre a ficha por cima"
troca app.html \
  "            onclick=\"event.stopPropagation();confirmarHorario('\${a.id}')\">Confirmar</button>\` : ''}" \
  "            onclick=\"confirmarHorario('\${a.id}')\">Confirmar</button>\` : ''}" \
  && rodar "confirma e a ficha pula na tela"

echo "4. o mês não marca o dia com pendente"
troca app.html \
  "<span class=\"mes-qtd\${pend ? ' pend' : ''}\"" \
  "<span class=\"mes-qtd\"" \
  && rodar "o calendário não avisa"

echo "5. a grade do dia sem a etiqueta"
troca app.html \
  "                 \${a.status === 'pendente' ? '<i class=\"ag-pend\">a confirmar</i>' : ''}" \
  "" \
  && rodar "bloco pendente igual ao confirmado"

echo "6. o recado não fala da confirmação"
troca app.html \
  "    + (esperam ? '<br><b>' + (esperam === 1 ? '1 espera' : esperam + ' esperam')" \
  "    + (false ? '<br><b>' + (esperam === 1 ? '1 espera' : esperam + ' esperam')" \
  && rodar "horário novo sem dizer que espera o salão"

echo "7. a tarja do pendente igual à dos outros"
troca estilo.css \
  ".dia-cartao.st-pendente{ border-left-color:var(--wa-500); background:var(--wa-soft) }" \
  "" \
  && rodar "só a etiqueta separa os dois"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
