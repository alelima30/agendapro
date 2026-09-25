#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a prévia da capa, a divisão da foto e o fundo no
#  computador — uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-previa-capa.sh
#
#  Cada mutação que sobreviver é um jeito de a prévia voltar a prometer uma
#  coisa e o link mostrar outra — "a prévia não está igual o real".
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/previa-capa.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mpc-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mpc-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mpc-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mpc-saida.txt) reprovações)"
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

echo "1. a página esquece a divisão escolhida no caminho da vitrine"
troca agendar.html \
  "      capaForma: s.capaForma || null," \
  "" \
  && rodar "Reta na prévia, arco no link"

echo "2. a página não marca o atributo"
troca agendar.html \
  "  if((s.capaForma || c.capaForma) === 'reta') raiz.setAttribute('data-capa', 'reta');" \
  "  if(false) raiz.setAttribute('data-capa', 'reta');" \
  && rodar "escolha gravada e ignorada"

echo "3. o CSS da divisão reta some"
troca estilo.css \
  '[data-capa="reta"] .hero-foto{ border-bottom-left-radius:0; border-bottom-right-radius:0 }' \
  "" \
  && rodar "atributo certo, foto curva"

echo "4. o painel deixa de gravar a divisão"
troca app.html \
  "    capaForma: aparencia.capaForma," \
  "" \
  && rodar "escolhe Reta, salva, e nada"

echo "5. a prévia volta a cortar a foto reto"
troca estilo.css \
  "  border-bottom-left-radius:50% 10px;
  border-bottom-right-radius:50% 10px;
}
.fone-capa.reta{ border-radius:0 }" \
  "}
.fone-capa.reta{ border-radius:0 }" \
  && rodar "a queixa do print: prévia reta, página curva"

echo "6. a prévia ignora a escolha Reta"
troca app.html \
  "\${aparencia.capaForma === 'reta' ? ' reta' : ''}" \
  "" \
  && rodar "Reta escolhida, prévia curva"

echo "7. a logo da prévia volta a ficar solta embaixo da foto"
troca estilo.css \
  "  width:60px; height:60px; margin-top:-33px; position:relative;" \
  "  width:60px; height:60px; position:relative;" \
  && rodar "a logo não monta na foto"

echo "8. a prévia esquece o tamanho do premium"
troca estilo.css \
  "  width:66px; height:66px; margin-top:-34px;" \
  "  width:60px; height:60px; margin-top:-33px;" \
  && rodar "logo do premium do tamanho do atual"

echo "9. a prévia esquece a foto mais alta do premium"
troca estilo.css \
  '.fone[data-modo="premium"] .fone-capa{ aspect-ratio:3 / 2 }' \
  "" \
  && rodar "premium com a faixa baixa"

echo "10. a moldura grossa da prévia fica média"
troca app.html \
  "grossa:'5.1px'" \
  "grossa:'2.8px'" \
  && rodar "anel fino na prévia, grosso no link"

echo "11. a prévia ignora a cor da moldura"
troca app.html \
  "  let cor = c.moldura;" \
  "  let cor = null;" \
  && rodar "anel amarelo no link, escuro na prévia"

echo "12. o premium da prévia usa o cartão como reserva do anel"
troca app.html \
  "    cor = aparencia.modo === 'premium'" \
  "    cor = false" \
  && rodar "reserva diferente da página"

echo "13. a forma da logo some da prévia"
troca estilo.css \
  '.fone[data-logo="quadrado"] .fone-selo{ border-radius:4% }' \
  '.fone[data-logo="quadrado"] .fone-selo{ border-radius:21% }' \
  && rodar "logo quadrada no link, arredondada na prévia"

echo "14. a página volta a cravar o anel do premium"
troca estilo.css \
  "  box-shadow:0 0 0 var(--selo-anel, 5px) var(--selo-cor, var(--bg)), var(--sombra-md);" \
  "  box-shadow:0 0 0 5px var(--bg), var(--sombra-md);" \
  && rodar "premium ignorando a moldura escolhida"

echo "15. a cor escrita da marca na prévia deixa de ser puxada"
troca app.html \
  "  const ac = corValida(c.destaque) ? c.destaque : mexer(cor, escuro ? 0.30 : -0.28);" \
  "  const ac = corValida(c.destaque) ? c.destaque : cor;" \
  && rodar "Bem-vindo e Horários com a cor crua"

echo "16. a prévia ignora o Destaque escolhido"
troca app.html \
  "  const ac = corValida(c.destaque) ? c.destaque : mexer(cor, escuro ? 0.30 : -0.28);" \
  "  const ac = mexer(cor, escuro ? 0.30 : -0.28);" \
  && rodar "destaque dourado no link, azul na prévia"

echo "17. a prévia ignora a Secundária no Bem-vindo"
troca app.html \
  "  const soft = corValida(c.secundaria)" \
  "  const soft = false" \
  && rodar "fundo suave da cor errada"

echo "18. o cartão de fábrica deixa de ir para a prévia"
troca app.html \
  "  if(!corValida(c.card)) fora += \`;--fone-card:\${corHerdada('card')}\`;" \
  "" \
  && rodar "#1D1D20 na prévia, #131C2E no link"

echo "19. o Bem-vindo da prévia volta a ser transparente sobre o fundo escolhido"
troca estilo.css \
  ".fone.com-papel .fone-boas, .fone.com-grad .fone-boas{" \
  ".fone.com-papel-nao .fone-boas, .fone.com-grad-nao .fone-boas{" \
  && rodar "Bem-vindo roxo sobre roxo na prévia"

echo "20. o Horários da prévia perde a letra da marca"
troca estilo.css \
  "  border-color:color-mix(in srgb, var(--fone-ac, var(--fone-marca)) 38%, var(--fone-card, var(--painel)));
  color:var(--fone-ac, var(--fone-marca));
}" \
  "  border-color:color-mix(in srgb, var(--fone-ac, var(--fone-marca)) 38%, var(--fone-card, var(--painel)));
}" \
  && rodar "letra do Horários cinza"

echo "21. o verde da prévia no escuro volta ao do painel"
troca estilo.css \
  ".fone-escuro{ --fone-su:#4ADE80;" \
  ".fone-escuro{ --fone-su:#15803D;" \
  && rodar "ABERTO verde-escuro na prévia"

echo "22. no computador, a coluna não pinta o gradiente"
troca estilo.css \
  "    background:var(--bg-grad) 0 0 / cover no-repeat fixed var(--bg) !important;" \
  "    background:var(--bg) !important;" \
  && rodar "coluna lisa, gradiente sumido"

echo "23. no computador, o gradiente volta à tela inteira"
troca estilo.css \
  "  body.tem-papel, body.tem-gradiente, body.tem-fundo{ background:var(--mesa) }" \
  "" \
  && rodar "a queixa do print: roxo de ponta a ponta"

echo "24. a foto de fundo não encolhe para a coluna"
troca estilo.css \
  "  .fundo-imagem, .fundo-veu{ left:50%; right:auto; width:480px; transform:translateX(-50%) }" \
  "" \
  && rodar "foto na tela inteira do computador"

echo "25. a regra do computador vale também no celular"
troca estilo.css \
  "@media (min-width:481px){
  body.tem-papel, body.tem-gradiente" \
  "@media (min-width:0px){
  body.tem-papel, body.tem-gradiente" \
  && rodar "celular com a foto fora da tela"

echo "26. o papel cobre a foto de fundo no computador"
troca estilo.css \
  "  body.tem-fundo .app{ background:transparent !important; box-shadow:var(--sombra) }" \
  "" \
  && rodar "foto escondida atrás do papel"

echo "27. a margem do escuro vira outra cor"
troca estilo.css \
  "  --mesa:#0B1220;" \
  "  --mesa:#1A1030;" \
  && rodar "margem que não é o papel de fábrica"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
