#!/usr/bin/env bash
# ===========================================================================
#  Quebrar o fundo da página de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-fundo.sh
#
#  Cada mutação que sobreviver é um jeito de o dono escolher um fundo e ver
#  outro — no quadrado, na prévia ou no link. Foi a queixa repetida três
#  vezes: "o fundo só tem claro e escuro".
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/fundo.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mfu-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mfu-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mfu-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mfu-saida.txt) reprovações)"
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
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA. O trecho sumiu ou passou a
  # aparecer duas vezes, e o placar seguia dizendo "N mortas, 0 vivas" com
  # uma a menos. Aconteceu no mutacoes-modulos.sh: a nº 5 ficou sem rodar por
  # sessões inteiras, porque o "!!" passava no meio da saída sem contar.
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. o quadrado volta a mostrar a cor da marca"
troca app.html \
  'value="${tem ? escolhida : corHerdada(chave)}"' \
  'value="${tem ? escolhida : aparencia.cor}"' \
  && rodar "fundo bege, quadrado azul"

echo "2. as letras param de acompanhar o fundo"
troca app.html \
  "  if(t) aparencia.tema = t;" \
  "" \
  && rodar "fundo escuro com letra escura"

echo "3. o gradiente decide as letras só pela ponta de cima"
troca app.html \
  "    if(corValida(a) && corValida(b)) fundos = [a, b];" \
  "    if(corValida(a) && corValida(b)) fundos = [a];" \
  && rodar "a ponta de baixo ilegível"

echo "4. o gradiente decide as letras só pela ponta de baixo"
troca app.html \
  "    if(corValida(a) && corValida(b)) fundos = [a, b];" \
  "    if(corValida(a) && corValida(b)) fundos = [b];" \
  && rodar "a ponta de cima ilegível"

echo "5. escolher Gradiente volta a não guardar nada"
troca app.html \
  "  if(v === 'gradiente' && !aparencia.gradiente) aparencia.gradiente = padraoGradiente();" \
  "" \
  && rodar "salvar sem mexer grava nulo"

echo "6. Cor sólida volta a ser gravada como 'cor'"
troca app.html \
  "    fundoTipo: aparencia.fundoTipo === 'cor' ? 'solida' : aparencia.fundoTipo," \
  "    fundoTipo: aparencia.fundoTipo," \
  && rodar "a foto antiga por cima da cor escolhida"

echo "7. a página deixa a foto entrar com qualquer tipo que não seja gradiente"
troca agendar.html \
  "  const fundo = (tipoFundo === 'imagem' || tipoFundo === 'cor') ? fotoAnexada : null;" \
  "  const fundo = tipoFundo !== 'gradiente' ? fotoAnexada : null;" \
  && rodar "cor sólida com foto"

echo "8. a página tira a foto de quem nunca escolheu"
troca agendar.html \
  "  const fundo = (tipoFundo === 'imagem' || tipoFundo === 'cor') ? fotoAnexada : null;" \
  "  const fundo = tipoFundo === 'imagem' ? fotoAnexada : null;" \
  && rodar "a foto de meses atrás sumindo sozinha"

echo "9. o painel mostra Cor sólida para quem tem foto e nunca escolheu"
troca app.html \
  "      : (imagemDoSalao(sl, 'fundo') ? 'imagem' : 'cor')," \
  "      : 'cor'," \
  && rodar "o painel dizendo o contrário do link"

echo "10. a prévia para de desenhar o gradiente"
troca app.html \
  '    fora += `;--fone-grad:linear-gradient(180deg, ${a} 0%, ${b} 100%)`;' \
  "" \
  && rodar "Gradiente escolhido, prévia lisa"

echo "11. a prévia volta ao fundo do painel quando nada foi escolhido"
troca app.html \
  "  if(!corValida(c.papel)) fora += \`;--fone-papel:\${corHerdada('papel')}\`;" \
  "" \
  && rodar "prévia #141416, página #0B1220"

echo "12. a Imagem esconde o próprio campo de anexar"
troca app.html \
  "  mostrar('imagemCampos',   aparencia.fundoTipo === 'imagem');" \
  "  mostrar('imagemCampos',   false);" \
  && rodar "Imagem escolhida e nada para anexar"

echo "13. o padrão do cartão escuro volta ao número antigo"
troca app.html \
  "  escuro: { papel:'#0B1220', card:'#131C2E', titulo:'#E8EEF7'," \
  "  escuro: { papel:'#0B1220', card:'#131A26', titulo:'#E8EEF7'," \
  && rodar "painel e página discordando do cartão"

echo "14. o CSS da prévia perde o gradiente"
troca estilo.css \
  ".fone.com-grad{ background-image:var(--fone-grad, none) }" \
  "" \
  && rodar "variável pronta, ninguém pintando"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
