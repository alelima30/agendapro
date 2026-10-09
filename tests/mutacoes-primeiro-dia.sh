#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o que o passo a passo ganhou — o teste tem de reprovar.
#
#    python3 -m http.server 8099 --directory .          (noutro terminal)
#    bash tests/mutacoes-primeiro-dia.sh
#
#  O teste é o tests/primeiro-dia.test.mjs, na demonstração. Endereço e
#  Instagram no passo 1, "Como a cliente paga" e "A cara do seu link".
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/primeiro-dia.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html"
SQLS=""
guarda(){ echo "/tmp/mpd-$(echo "$1" | tr '/' '_')"; }
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
  if node "$T" >/tmp/mpd-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mpd-saida.txt) reprovações)"
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

echo "1. passo 1: o endereço não é gravado"
troca app.html \
  "  sl.endereco = Object.assign({}, Endereco.normalizar(sl.endereco), {" \
  "  void Object.assign({}, Endereco.normalizar(sl.endereco), {" \
  && rodar "o link continua sem dizer onde é o salão"

echo "2. passo 1: o Instagram não é gravado"
troca app.html \
  "  sl.cfg = Object.assign({}, sl.cfg, { instagram: instagramLimpo(v('pdInsta')) || null });" \
  "  ;" \
  && rodar "Informações sem o Instagram"

echo "3. pagamento: as formas não são gravadas"
troca app.html \
  "    pagamentos: Funcionamento.pagamentos({ formas: pdFormasAtuais(), obs })," \
  "    pagamentos: null," \
  && rodar "o link não pergunta como ela vai pagar"

echo "4. pagamento: marcar redesenha e apaga a observação"
troca app.html \
  "  if(bt){
    bt.classList.toggle('on', on);" \
  "  pdDesenhar(); if(false){
    bt.classList.toggle('on', on);" \
  && rodar "o que foi digitado some ao tocar numa forma"

echo "5. cara do link: a cor não é gravada"
troca app.html \
  "  sl.cfg = Object.assign({}, sl.cfg, { cor: hex });" \
  "  ;" \
  && rodar "toca na cor e o link continua como era"

echo "6. cara do link: qualquer texto vira cor"
troca app.html \
  "  if(!/^#[0-9a-f]{6}$/i.test(String(hex || ''))) return;" \
  "  ;" \
  && rodar "uma cor inválida quebra a página da cliente"

echo "7. cara do link: o logo escolhido não aparece no passo"
troca app.html \
  "  await subirImagemSalao(chave, campo);
  pdDesenhar();" \
  "  await subirImagemSalao(chave, campo);" \
  && rodar "escolheu o logo e parece que não foi"

echo "8. fim: não lembra o que ficou para depois"
troca app.html \
  "  if(!imagemDoSalao(sl, 'logo'))   depois.push('o logo');" \
  "  ;" \
  && rodar "o dono não sabe que falta o logo"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
