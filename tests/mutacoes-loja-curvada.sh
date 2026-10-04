#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a tela de produtos na moldura curvada e na cor do tema.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-loja-curvada.sh
#
#  Cada mutação que sobreviver é um jeito de a loja ignorar a moldura de
#  Aparência, ou de o Adicionar e o botão de baixo voltarem ao branco e ao
#  cinza de antes.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/loja-curvada.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mlc-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mlc-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mlc-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mlc-saida.txt) reprovações)"
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

echo "1. a loja ignora a Curvada"
troca agendar.html \
  "  const curva = (salao.moldura || (salao.cfg || {}).moldura) === 'elegante';" \
  "  const curva = false;" \
  && rodar "fileiras com a curva escolhida"

echo "2. a loja sempre curva"
troca agendar.html \
  "  const curva = (salao.moldura || (salao.cfg || {}).moldura) === 'elegante';" \
  "  const curva = true;" \
  && rodar "a Clássica perde as fileiras"

echo "3. o Adicionar sem a classe"
troca agendar.html \
  "    : \`<button class=\"btn btn-peq loja-add\"" \
  "    : \`<button class=\"btn btn-peq\"" \
  && rodar "Adicionar branco de novo"

echo "4. o cartão perde a descrição"
troca agendar.html \
  "          \${p.descricao ? \`<span class=\"loja-desc\">\${escapar(p.descricao)}</span>\` : ''}
" \
  "" \
  && rodar "descrição sumida na curva"

echo "5. o Adicionar sem a cor"
troca estilo.css \
  "  background:var(--acao); color:var(--acao-txt); border:1px solid var(--acao);
  font-weight:700;" \
  "  font-weight:700;" \
  && rodar "papel com contorno"

echo "6. a cor dos produtos ignorada"
troca estilo.css \
  "body.tem-cor-produtos #listaProdutos .loja-add, body.tem-cor-produtos #produtoAberto .loja-add{
  background:var(--prod-cor);" \
  "body.tem-cor-produtos #listaProdutos .loja-addX, body.tem-cor-produtos #produtoAberto .loja-addX{
  background:var(--prod-cor);" \
  && rodar "loja numa cor, capa noutra"

echo "7. o botão de baixo cinza"
troca estilo.css \
  "body[data-passo=\"loja\"] #btPrincipal:disabled{" \
  "body[data-passo=\"nenhum\"] #btPrincipal:disabled{" \
  && rodar "cinza chapado de volta"

echo "8. a letra do botão de baixo cinza"
troca estilo.css \
  "  color:var(--ac-600) !important;
  border:1px solid color-mix(in srgb, var(--acao) 32%, var(--painel)) !important;" \
  "  border:1px solid color-mix(in srgb, var(--acao) 32%, var(--painel)) !important;" \
  && rodar "fundo rosado, letra cinza"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
