#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o botão de baixo do link ("Agendar horário") — na
#  prévia e com cor própria. Uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-rodape.sh
#
#  Cada mutação que sobreviver é um jeito de o dono escolher a cor do botão
#  de baixo e ver outra coisa — ou de a prévia esconder o botão de novo.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/botao-de-baixo.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mrd-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mrd-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mrd-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mrd-saida.txt) reprovações)"
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

echo "1. a prévia volta a não ter o botão de baixo"
troca app.html \
  "       \${previaDoRodape(sl, comServicos, temPr)}" \
  "" \
  && rodar "Agendar horário só no link"

echo "2. a prévia ignora a cor escolhida"
troca app.html \
  "  const fundo = corValida(c.rodape) ? c.rodape : corDoBotaoNaPrevia();" \
  "  const fundo = corDoBotaoNaPrevia();" \
  && rodar "prévia na Cor dos botões, link marrom"

echo "3. o link ignora a cor escolhida"
troca agendar.html \
  "  document.body.classList.toggle('tem-cor-rodape', !!rodape);" \
  "  document.body.classList.toggle('tem-cor-rodape', false);" \
  && rodar "cor salva e botão de sempre"

echo "4. a cor do botão de baixo pinta também o Agendar do Bem-vindo"
troca estilo.css \
  "body.tem-cor-rodape #btPrincipal:not(:disabled){" \
  "body.tem-cor-rodape #btPrincipal:not(:disabled), body.tem-cor-rodape .boas .boas-cta{" \
  && rodar "os dois botões mudam juntos"

echo "5. só o fundo escolhido, e a letra não acompanha"
troca agendar.html \
  "  if(rodape || letraRodape) p('--cor-letra-rodape', letraRodape || letraSobre(rodape));" \
  "  if(rodape || letraRodape) p('--cor-letra-rodape', letraRodape || '#FFFFFF');" \
  && rodar "letra branca em botão amarelo-claro"

echo "6. tocar na prévia não leva às cores"
troca app.html \
  "  rodape:   ['.cor-linha[data-chave=\"rodape\"]', '.cor-linha[data-chave=\"letraRodape\"]']," \
  "" \
  && rodar "toque que não vai a lugar nenhum"

echo "8. a prévia volta a escrever as palavras do salão para todo negócio"
troca app.html \
  "         <div class=\"fone-rot\" data-cfg=\"tituloEquipe\">\${escapar(vocPrevia(sl, 'atende'))}</div>" \
  "         <div class=\"fone-rot\" data-cfg=\"tituloEquipe\">Quem corta</div>" \
  && rodar "prévia e link com títulos diferentes"

echo "7. o botão de baixo sai do grupo dos botões"
troca app.html \
  "  ['coresBotoes', ['botao', 'letraAgendar', 'rodape', 'letraRodape']]," \
  "  ['coresBotoes', ['botao', 'letraAgendar']]," \
  && rodar "a cor existe e ninguém acha"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
