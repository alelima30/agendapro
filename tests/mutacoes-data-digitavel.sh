#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o aniversário que se digita (dd/mm/aaaa).
#
#    bash tests/bancada/subir.sh        e python3 -m http.server 8099 (noutro terminal)
#    bash tests/mutacoes-data-digitavel.sh
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/data-digitavel.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="documento.js estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mdd-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mdd-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mdd-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mdd-saida.txt) reprovações)"
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



echo "1. sem as barras automáticas"
troca documento.js \
  "  el.value = d.length > 4 ? d.slice(0, 2) + '/' + d.slice(2, 4) + '/' + d.slice(4)
           : d.length > 2 ? d.slice(0, 2) + '/' + d.slice(2) : d;" \
  "  el.value = d;" \
  && rodar "04101990 não vira data nenhuma"

echo "2. 31/02 aceito"
troca documento.js \
  "  if(dt.getFullYear() !== a || dt.getMonth() !== mes - 1 || dt.getDate() !== d) return '';" \
  "" \
  && rodar "data que não existe vai para o banco"

echo "3. o que o aparelho lembra não aparece escrito"
troca documento.js \
  "    set(v){ desc.set.call(this, v); if(document.activeElement !== txt) txt.value = brDeData(desc.get.call(this)); }," \
  "    set(v){ desc.set.call(this, v); }," \
  && rodar "o texto fica vazio com a data guardada"

echo "4. data torta passa calada"
troca documento.js \
  "  return !!(t && t.value.trim() && !campo.value);" \
  "  return false;" \
  && rodar "\"falta\" em vez de \"confira\""

echo "5. o calendário apaga o que se digita"
troca documento.js \
  "  const doCalendario = () => { if(document.activeElement !== txt) txt.value = brDeData(desc.get.call(campo)); };" \
  "  const doCalendario = () => { txt.value = brDeData(desc.get.call(campo)); };" \
  && rodar "cada número digitado some"

echo "6. o ícone não abre o calendário"
troca estilo.css \
  ".data-caixa .data-escolher{ position:absolute; right:3px;" \
  ".data-caixa .data-escolher{ position:absolute; left:3px;" \
  && rodar "toca no ícone e nada"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
