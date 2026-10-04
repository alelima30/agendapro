#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito os cartões de serviço do "Novo agendamento".
#
#    python3 -m http.server 8099 --directory .   (noutro terminal)
#    bash tests/mutacoes-servicos-form.sh
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/servicos-form.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export BASE=${BASE:-http://127.0.0.1:8099/}

ARQS="app.html"
for a in $ARQS; do cp "$a" "/tmp/msf-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/msf-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/msf-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/msf-saida.txt) reprovações)"
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

echo "1. a caixinha volta a aparecer"
troca app.html \
  ".lista-serv .serv-op input{position:absolute;opacity:0;" \
  ".lista-serv .serv-op input{" \
  && rodar "caixinha numa linha, nome noutra"

echo "2. tocar não pinta o cartão"
troca app.html \
  "  cx.closest('.serv-op').classList.toggle('on', cx.checked);" \
  "" \
  && rodar "marcado sem moldura nem visto"

echo "3. a busca esconde o que já foi marcado"
troca app.html \
  "    el.style.display = acha || el.querySelector('input').checked ? '' : 'none';" \
  "    el.style.display = acha ? '' : 'none';" \
  && rodar "parece que a escolha foi desfeita"

echo "4. a busca liga para acento"
troca app.html \
  "  return String(t || '').normalize('NFD').replace(/[\\u0300-\\u036f]/g, '').toLowerCase();" \
  "  return String(t || '').toLowerCase();" \
  && rodar "\"coloracao\" não acha Coloração"

echo "5. nada achado fica em branco"
troca app.html \
  "  if(nada) nada.style.display = achados ? 'none' : '';" \
  "" \
  && rodar "busca vazia sem explicação"

echo "6. busca até para três serviços"
troca app.html \
  "      \${servs.length > 6 ? \`<input id=\"fBuscaServ\"" \
  "      \${servs.length > 0 ? \`<input id=\"fBuscaServ\"" \
  && rodar "campo a mais para quem não precisa"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
