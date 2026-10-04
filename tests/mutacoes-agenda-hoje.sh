#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a agenda que acorda no dia de hoje.
#
#    python3 -m http.server 8099 --directory .   (noutro terminal)
#    bash tests/mutacoes-agenda-hoje.sh
#
#  Cada mutação que sobreviver é um jeito de o painel voltar a abrir num dia
#  velho, de jogar o dono para hoje sem o dia ter virado, ou de os números
#  voltarem para cima da agenda.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/agenda-hoje.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export BASE=${BASE:-http://127.0.0.1:8099/}

ARQS="app.html"
for a in $ARQS; do cp "$a" "/tmp/mah-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mah-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mah-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mah-saida.txt) reprovações)"
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

echo "1. o dia nunca vira"
troca app.html \
  "  if(h === _hojeVisto) return;
  _hojeVisto = h;" \
  "  return;
  _hojeVisto = h;" \
  && rodar "acorda dias depois no dia velho"

echo "2. vira o dia mas a agenda fica onde estava"
troca app.html \
  "  _hojeVisto = h;
  diaAtual = h;" \
  "  _hojeVisto = h;" \
  && rodar "a data muda e a agenda não"

echo "3. qualquer volta ao app joga para hoje"
troca app.html \
  "  if(h === _hojeVisto) return;
  _hojeVisto = h;" \
  "  _hojeVisto = h;" \
  && rodar "sair um minuto apaga o dia que ele escolheu"

echo "4. sem o relógio de um minuto"
troca app.html \
  "  setInterval(conferirViradaDoDia, 60000);" \
  "" \
  && rodar "aberto na tela, a meia-noite passa e nada muda"

echo "5. os números voltam para cima da agenda"
troca app.html \
  "    <div class=\"kpis\" id=\"kpisDia\"></div>
    <p class=\"nota\" id=\"notaAgenda\"></p>" \
  "    <p class=\"nota\" id=\"notaAgenda\"></p>" \
  && troca app.html \
  "    <!-- Onde a grade confessa que não deu conta. Vazio em dia normal. -->" \
  "    <div class=\"kpis\" id=\"kpisDia\"></div>
    <!-- Onde a grade confessa que não deu conta. Vazio em dia normal. -->" \
  && rodar "cartões antes do calendário"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
