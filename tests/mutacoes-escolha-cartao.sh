#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a escolha de serviços com o cartão da capa.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-escolha-cartao.sh
#
#  Cada mutação que sobreviver é um jeito de a escolha voltar a ser fileira,
#  de a moldura não seguir a de Aparência, ou de a escolhida não se ver.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/escolha-cartao.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mec-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mec-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mec-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mec-saida.txt) reprovações)"
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

echo "1. a escolha perde o modo de escolher"
troca agendar.html \
  "        return cartaoDeServico(s, { elegante, temAlgumaFoto, sel, escolher: true," \
  "        return cartaoDeServico(s, { elegante, temAlgumaFoto, sel," \
  && rodar "seta no lugar da marca"

echo "2. a escolha ignora a moldura de Aparência"
troca agendar.html \
  "  const elegante = (salao.moldura || (salao.cfg||{}).moldura) === 'elegante';
  // A mesma regra da capa: com foto" \
  "  const elegante = false;
  // A mesma regra da capa: com foto" \
  && rodar "sempre clássica"

echo "3. a escolha esquece a regra das fotos"
troca agendar.html \
  "  const temAlgumaFoto = todos.some(s => s.foto);
  alvo.innerHTML =" \
  "  const temAlgumaFoto = false;
  alvo.innerHTML =" \
  && rodar "sem a inicial"

echo "4. o cartão não diz se está escolhido"
troca agendar.html \
  "                  o.escolher ? \` aria-pressed=\"\${o.sel ? 'true' : 'false'}\"\` : ''}" \
  "                  ''}" \
  && rodar "leitor de tela sem saber"

echo "5. a borda da escolhida não acende"
troca agendar.html \
  "        <button class=\"sv-cartao\${s.foto ? '' : ' sem-foto'}\${o.sel ? ' sel' : ''}\${" \
  "        <button class=\"sv-cartao\${s.foto ? '' : ' sem-foto'}\${" \
  && rodar "escolhida igual às outras"

echo "6. a marca não ganha o visto"
troca agendar.html \
  "<span class=\"sv-cartao-marca\">\${o.sel ? ico('ok') : ''}</span>" \
  "<span class=\"sv-cartao-marca\"></span>" \
  && rodar "círculo sempre vazio"

echo "7. a marca não enche"
troca estilo.css \
  ".sv-cartao.sel .sv-cartao-marca{ background:var(--acao); border-color:var(--acao) }" \
  "" \
  && rodar "visto sem fundo"

echo "8. a marca fica no alto na Curvada"
troca estilo.css \
  "[data-moldura=\"elegante\"] .sv-cartao-marca{ top:auto; bottom:11px; right:11px }" \
  "" \
  && rodar "marca fora do lugar da seta"

echo "9. o relógio some a cada toque"
troca agendar.html \
  "  // data-ico, e sem esta linha ele sumia a cada toque.
  if(window.aplicarIcones) aplicarIcones(alvo);" \
  "  // data-ico, e sem esta linha ele sumia a cada toque." \
  && rodar "duração sem relógio"

echo "10. o combo perde o selo"
troca agendar.html \
  "          combo: ehCombo(s), acao: \`alternarServico('\${s.id}')\`," \
  "          acao: \`alternarServico('\${s.id}')\`," \
  && rodar "combo sem COMBO"

echo "11. o cartão não mostra o preço"
troca agendar.html \
  "              \${o.preco ? \`<span class=\"sv-cartao-preco\">\${o.preco}</span>\` : ''}" \
  "" \
  && rodar "escolher sem saber quanto custa"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
