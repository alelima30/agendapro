#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o Voltar escrito do link e o produto aberto.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-voltar-produto.sh
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/voltar-produto.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mvp-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mvp-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mvp-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mvp-saida.txt) reprovações)"
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



echo "1. Para quem fica sem Voltar"
troca agendar.html \
  "const VOLTAR_ESCRITO = ['servico', 'quem', 'quemOutra'," \
  "const VOLTAR_ESCRITO = ['servico', 'quemOutra'," \
  && rodar "a tela sem botão nenhum prende a cliente"

echo "2. o Voltar escrito some de todas"
troca agendar.html \
  "  if(VOLTAR_ESCRITO.includes(tela)){
    const sozinho" \
  "  if(false){
    const sozinho" \
  && rodar "só o ‹ pequeno do topo"

echo "3. o Voltar aparece mas não volta"
troca agendar.html \
  "  if(VOLTAR_ESCRITO.includes(tela)) return voltar();" \
  "" \
  && rodar "toca e nada acontece"

echo "4. o Adicionar do cartão abre o produto"
troca agendar.html \
  "  if(ev && ev.target && ev.target.closest('button')) return;" \
  "" \
  && rodar "quem só queria pôr no carrinho sai da loja"

echo "5. a descrição perde as quebras de linha"
troca estilo.css \
  "color:var(--txt2); white-space:pre-line; overflow-wrap:anywhere }" \
  "color:var(--txt2); overflow-wrap:anywhere }" \
  && rodar "o texto do salão vira um bloco só"

echo "6. a fita do carrinho repete o pé no produto"
troca agendar.html \
  "&& tela !== 'loja' && tela !== 'produto';" \
  "&& tela !== 'loja';" \
  && rodar "dois Enviar pedido um sobre o outro"

echo "7. Ver meu pedido só adiciona"
troca agendar.html \
  "    return n ? irPara('loja') : mudarNoCarrinho(produtoAbertoId, 1);" \
  "    return mudarNoCarrinho(produtoAbertoId, 1);" \
  && rodar "o botão diz uma coisa e faz outra"

echo "8. a foto do produto pequena"
troca estilo.css \
  ".pr-foto.prod-grande{ aspect-ratio:auto; height:min(58vh, 440px);" \
  ".pr-foto.prod-grande{ aspect-ratio:auto; height:120px;" \
  && rodar "abre o produto e a foto continua miúda"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
