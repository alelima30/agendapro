#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a abertura com o logo no link da cliente.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-intro-link.sh
#
#  Cada mutação que sobreviver é um jeito de a abertura não aparecer, de
#  aparecer sempre (e segurar quem volta), de não deixar pular, de ignorar
#  o que o dono escolheu, ou de a prévia do painel mentir sobre ela.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/intro-link.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
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

echo "1. o link não toca a abertura"
troca agendar.html \
  "  irPara('capa', true);
  tocarIntro(s);" \
  "  irPara('capa', true);" \
  && rodar "escolhida e nunca vista"

echo "2. toca a cada visita à capa"
troca agendar.html \
  "    if(sessionStorage.getItem(marca)) return;
" \
  "" \
  && rodar "quem recarrega assiste de novo"

echo "3. o toque não pula"
troca agendar.html \
  "  el.addEventListener('click', sair);
" \
  "" \
  && rodar "presa na abertura"

echo "4. ela não sai sozinha"
troca agendar.html \
  "  document.body.appendChild(el);
  setTimeout(sair, ms);" \
  "  document.body.appendChild(el);" \
  && rodar "a capa nunca aparece"

echo "5. \"reduzir movimento\" ignorado"
troca agendar.html \
  "  const ms = calmo ? 700 : INTRO_TEMPO[intro.tempo];" \
  "  const ms = INTRO_TEMPO[intro.tempo];" \
  && rodar "três segundos para quem pediu calma"

echo "6. lixo do banco vira efeito"
troca agendar.html \
  "  if(!['aparecer', 'deslizar', 'brilho'].includes(i.efeito)) return null;
" \
  "" \
  && rodar "intro-abacaxi"

echo "7. o nome sempre aparece"
troca agendar.html \
  "    \${intro.nome ? \`<div class=\"intro-nome\">" \
  "    \${true ? \`<div class=\"intro-nome\">" \
  && rodar "\"só o logo\" ignorado"

echo "8. o fundo da página ignorado"
troca agendar.html \
  "    + (intro.fundo === 'pagina' ? ' intro-pagina' : '');" \
  "    + '';" \
  && rodar "sempre na cor do botão"

echo "9. a página não lê a escolha"
troca agendar.html \
  "      intro: (s.intro && typeof s.intro === 'object') ? s.intro : null,
" \
  "" \
  && rodar "o painel grava e o link não sabe"

echo "10. o painel não grava"
troca app.html \
  "    intro: introParaGravar(),
" \
  "" \
  && rodar "Salvar sem efeito"

echo "11. a prévia na cor do painel"
troca app.html \
  "\`;--i-fundo:\${pagina ? papel : botao}" \
  "\`;--x-fundo:\${pagina ? papel : botao}" \
  && rodar "prévia azul, link rosa"

echo "12. réguas vivas com \"Sem abertura\""
troca app.html \
  "  if(op) op.style.display = i.efeito === 'sem' ? 'none' : '';
" \
  "" \
  && rodar "régua que não muda nada"

echo "13. escolher o efeito não mostra"
troca app.html \
  "  if(campo === 'efeito' && valor !== 'sem') verIntroNaPrevia();
" \
  "" \
  && rodar "escolher às cegas"

echo "14. o logo quadrado vira arredondado"
troca estilo.css \
  "[data-logo=\"quadrado\"]    .intro-logo{ border-radius:6px }" \
  "" \
  && rodar "forma diferente da capa"

echo "15. a animação continua com \"reduzir movimento\""
troca estilo.css \
  "  .intro .intro-logo, .intro .intro-nome, .intro .intro-logo::after{ animation:none !important }
" \
  "" \
  && rodar "movimento para quem pediu calma"

echo "16. a abertura não cobre a tela"
troca estilo.css \
  "  position:fixed; inset:0; z-index:9999;" \
  "  position:static;" \
  && rodar "a capa aparece por baixo"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
