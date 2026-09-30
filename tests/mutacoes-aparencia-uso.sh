#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o que a revisão da tela de Aparência consertou.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-aparencia-uso.sh
#
#  Cada mutação que sobreviver é um jeito de o dono sair sem salvar sem
#  saber, de não achar a prévia no celular, ou de ler um nome que engana.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/aparencia-uso.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mau-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mau-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mau-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mau-saida.txt) reprovações)"
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

echo "1. a barra nunca acusa mudança"
troca app.html \
  "  return JSON.stringify(emOrdem(iria)) !== JSON.stringify(emOrdem(lerAparencia()));" \
  "  return false;" \
  && rodar "sai sem salvar sem saber"

echo "2. a barra compara sem pôr as chaves em ordem"
troca app.html \
  "  return JSON.stringify(emOrdem(iria)) !== JSON.stringify(emOrdem(lerAparencia()));" \
  "  return JSON.stringify(iria) !== JSON.stringify(lerAparencia());" \
  && rodar "acusa mudança ao abrir"

echo "3. a tela não repinta a barra"
troca app.html \
  "    k in FRASE_HERDA_DE || k === 'legenda' || k === 'verTodosProdutos')) det.open = true;
  pintarBarraAp();" \
  "    k in FRASE_HERDA_DE || k === 'legenda' || k === 'verTodosProdutos')) det.open = true;" \
  && rodar "mudou e a barra não veio"

echo "4. salvar não tira a barra"
troca app.html \
  "  pintarModelos();
  pintarBarraAp();" \
  "  pintarModelos();" \
  && rodar "salvo e dizendo que não"

echo "5. Desfazer não desfaz"
troca app.html \
  "  aparencia = lerAparencia();
  modeloAntes = null; modeloAtual = null;
  pintarAparencia();" \
  "  modeloAntes = null; modeloAtual = null;
  pintarAparencia();" \
  && rodar "o botão mente"

echo "6. a barra aparece limpa no computador"
troca estilo.css \
  "  .ap-barra:not(.suja){ display:none }" \
  "" \
  && rodar "barra vazia sempre na tela"

echo "7. a prévia do celular não sobe por cima"
troca estilo.css \
  "  body.ap-previa-aberta .ap-previa{
    position:fixed;" \
  "  body.ap-previa-aberta .ap-previa{
    position:static;" \
  && rodar "Ver prévia não mostra nada"

echo "8. tocar na prévia não a fecha"
troca app.html \
  "  fecharPreviaCelular();
  const alvos = [];" \
  "  const alvos = [];" \
  && rodar "prévia por cima do controle"

echo "9. tocar na prévia não abre as frases recolhidas"
troca app.html \
  "    if(dobra) dobra.open = true;" \
  "" \
  && rodar "o toque leva a lugar nenhum"

echo "10. as frases escolhidas continuam recolhidas"
troca app.html \
  "    k in FRASE_HERDA_DE || k === 'legenda' || k === 'verTodosProdutos')) det.open = true;" \
  "    k in FRASE_HERDA_DE || k === 'legenda' || k === 'verTodosProdutos')) det.open = false;" \
  && rodar "o que ele escolheu escondido"

echo "11. o personalizado de antes fica sem botão aceso"
troca app.html \
  "  const modoNaTela = aparencia.modo === 'premium' ? 'premium' : 'atual';" \
  "  const modoNaTela = aparencia.modo;" \
  && rodar "nenhum modo aceso"

echo "12. tocar no Simples troca o personalizado"
troca app.html \
  "  const valorDo = v => v === 'atual' && aparencia.modo === 'personalizado' ? 'personalizado' : v;" \
  "  const valorDo = v => v;" \
  && rodar "mudança que não muda nada"

echo "13. o botão de limpar volta a se chamar Personalizado"
troca app.html \
  "         Limpar cores</button>\`;" \
  "         Personalizado</button>\`;" \
  && rodar "nome que engana"

echo "14. o HEX volta a cortar no celular"
troca estilo.css \
  "@media (max-width:420px){ .cor-hex{ width:84px; padding:0 6px; letter-spacing:0 } }" \
  "@media (max-width:420px){ .cor-hex{ width:78px; padding:0 7px } }" \
  && rodar "#AA224"

echo "15. o HEX do gradiente volta para a esquerda"
troca app.html \
  "      else if(linha) linha.appendChild(hex);" \
  "" \
  && rodar "código colado no quadrado"

echo "16. o acento some"
troca app.html \
  "Modo de exibição</div>" \
  "Modo de exibicao</div>" \
  && rodar "exibicao"

echo "17. o Ver prévia some do celular"
troca estilo.css \
  "  body.ap-previa-aberta .ap-ver-previa{ display:none }" \
  "  .ap-ver-previa{ display:none }" \
  && rodar "prévia sem caminho"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
