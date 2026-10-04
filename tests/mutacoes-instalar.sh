#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o instalar o salão no celular.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-instalar.sh
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/instalar.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="agendar.html"
for a in $ARQS; do cp "$a" "/tmp/min-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/min-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/min-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/min-saida.txt) reprovações)"
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



echo "1. start_url relativo dentro do blob"
troca agendar.html \
  "    start_url: alvo.href," \
  "    start_url: alvo.pathname + alvo.search," \
  && rodar "o app instalado não sabe onde abrir"

echo "2. ícones relativos dentro do blob"
troca agendar.html \
  "      { src: abs('icones/icone-192.png'), sizes: '192x192', type: 'image/png', purpose: 'any' }," \
  "      { src: 'icones/icone-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' }," \
  && rodar "o Chrome descarta o ícone e não oferece instalar"

echo "3. a instrução esquece o WhatsApp"
troca agendar.html \
  "            <b>Abrir no Chrome</b>. Dentro do WhatsApp não dá para instalar.</li>" \
  "            </li>" \
  && rodar "procura Instalar num menu que não tem"

echo "4. sem o copiar link"
troca agendar.html \
  "        <button class=\"link\" onclick=\"copiarLinkDoSalao(this)\">Copiar o link</button>" \
  "" \
  && rodar "sem jeito de levar o link para o Chrome"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
