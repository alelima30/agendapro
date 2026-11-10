#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a cor de dentro dos cartões de serviço e de
#  produto. Uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-cartao-dentro.sh
#
#  Cada mutação que sobreviver é um jeito de o dono escolher a cor de dentro
#  e ver outra coisa no link ou na prévia.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/cartao-por-dentro.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mcd-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mcd-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mcd-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mcd-saida.txt) reprovações)"
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

echo "1. o link ignora a cor de dentro dos serviços"
troca agendar.html \
  "  document.body.classList.toggle('tem-fundo-servico', !!fundoServico);" \
  "  document.body.classList.toggle('tem-fundo-servico', false);" \
  && rodar "cor salva e cartão branco no link"

echo "2. a cor dos serviços pinta também os produtos"
troca estilo.css \
  "body.tem-fundo-servico .sv-cartao{ background:var(--cor-fundo-servico) }" \
  "body.tem-fundo-servico .sv-cartao, body.tem-fundo-servico .pr-cartao{ background:var(--cor-fundo-servico) }" \
  && rodar "produtos creme sem ninguém pedir"

echo "3. a prévia ignora a cor de dentro dos serviços"
troca app.html \
  "          corValida((aparencia.cores || {}).fundoServico) ? ' com-fundo-servico' : ''}\${" \
  "          ''}\${" \
  && rodar "prévia branca, link creme"

echo "4. as linhas saem de baixo da moldura"
troca app.html \
  "  ['coresMolduraCartoes', ['fundoServico', 'fundoProduto']]," \
  "" \
  && rodar "a cor existe e ninguém acha"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
