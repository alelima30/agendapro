#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o estilo dos atalhos (Pagamentos, Horários,
#  Informações) — uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-atalhos.sh
#
#  Cada mutação que sobreviver é um jeito de o dono escolher "Sem moldura"
#  ou "Com assombreamento" e ver outra coisa — ou de o salão que nunca
#  escolheu acordar com a página diferente.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/atalhos.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mat-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mat-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mat-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mat-saida.txt) reprovações)"
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

echo "1. a página esquece os atalhos no caminho da vitrine"
troca agendar.html \
  "      atalhos: (s.atalhos && typeof s.atalhos === 'object') ? s.atalhos : null,
" \
  "" \
  && rodar "a vitrine entrega e a página joga fora"

echo "2. a página não aplica o estilo"
troca agendar.html \
  "  aplicarAtalhos(s.atalhos || c.atalhos);
" \
  "" \
  && rodar "escolha gravada e ignorada"

echo "3. o Sem moldura volta a ter caixa"
troca estilo.css \
  '[data-atalhos="limpo"] .recurso{ background:transparent; box-shadow:none }' \
  '[data-atalhos="limpo"] .recurso{ box-shadow:none }' \
  && rodar "fundo de cartão no sem moldura"

echo "4. a borda volta nos estilos novos"
troca estilo.css \
  "[data-atalhos] .recurso{ border-color:transparent }" \
  "" \
  && rodar "moldura no com assombreamento"

echo "5. a sombra some do Com assombreamento"
troca estilo.css \
  "  box-shadow:0 var(--at-distancia, 4px) var(--at-desfoque, 16px)
             color-mix(in srgb, var(--at-cor, #000) var(--at-opacidade, 10%), transparent);
}" \
  "}" \
  && rodar "assombreamento sem sombra"

echo "6. o Sem moldura volta a levantar no mouse"
troca estilo.css \
  "[data-atalhos=\"limpo\"] .recurso:hover{ transform:none }" \
  "" \
  && rodar "efeito de botão tradicional"

echo "7. o bloco dos atalhos perde para o hover"
troca estilo.css \
  "[data-atalhos=\"sombra\"] .recurso{
  background:var(--painel);" \
  ".sem-peso[data-atalhos=\"sombra\"] .recurso, [data-atalhos=\"sombra\"] .recurso:not(:hover){
  background:var(--painel);" \
  && rodar "sombra do hover por cima da escolhida"

echo "8. o Horários guarda o tingido no Sem moldura"
troca estilo.css \
  "[data-atalhos=\"limpo\"] .recurso{ background:transparent; box-shadow:none }" \
  "[data-atalhos=\"limpo\"] .recurso:not(.destaque){ background:transparent; box-shadow:none }" \
  && rodar "caixa lilás só no Horários"

echo "9. a página aceita desfoque sem teto"
troca agendar.html \
  "  raiz.style.setProperty('--at-desfoque',  num(sb.desfoque, 40, 16) + 'px');" \
  "  raiz.style.setProperty('--at-desfoque',  num(sb.desfoque, 9999, 16) + 'px');" \
  && rodar "desfoque de 999px vindo do banco"

echo "10. a página aceita cor torta"
troca agendar.html \
  "  raiz.style.setProperty('--at-cor', corValida(sb.cor) ? sb.cor : '#000000');" \
  "  raiz.style.setProperty('--at-cor', sb.cor || '#000000');" \
  && rodar "texto do dono dentro do CSS"

echo "11. a página aceita qualquer estilo"
troca agendar.html \
  "  const estilo = (a && typeof a === 'object' && ['limpo', 'sombra'].includes(a.estilo))
    ? a.estilo : null;" \
  "  const estilo = (a && typeof a === 'object' && a.estilo) ? a.estilo : null;" \
  && rodar "estilo desconhecido tirando a borda"

echo "12. o painel deixa de gravar os atalhos"
troca app.html \
  "    atalhos: aparencia.atalhos,
" \
  "" \
  && rodar "escolhe, salva, e nada"

echo "13. mexer à mão não vira personalizada"
troca app.html \
  "    sb.intensidade = bate || 'personalizada';" \
  "" \
  && rodar "Forte marcada com números que não são os dela"

echo "14. os controles ficam ligados no Sem moldura"
troca app.html \
  "    el.disabled = !ligado;" \
  "    el.disabled = false;" \
  && rodar "sombra ajustável sem sombra nenhuma"

echo "15. a prévia ignora o estilo"
troca app.html \
  "          data-atalhos=\"\${aparencia.atalhos.estilo}\"
" \
  "" \
  && rodar "prévia com borda, link sem moldura"

echo "16. a prévia do Sem moldura mantém a caixa"
troca estilo.css \
  '.fone[data-atalhos="limpo"] .fone-recurso{ background:transparent; box-shadow:none }' \
  '' \
  && rodar "prévia com caixa"

echo "17. a prévia usa a sombra no tamanho do link"
troca app.html \
  "  const sb = aparencia.atalhos.sombra, k = 234 / 412;" \
  "  const sb = aparencia.atalhos.sombra, k = 1;" \
  && rodar "sombra da prévia quase o dobro"

echo "18. reabrir o painel perde o estilo salvo"
troca app.html \
  "    estilo: ['limpo', 'sombra'].includes(a.estilo) ? a.estilo : 'borda'," \
  "    estilo: 'borda'," \
  && rodar "painel dizendo Com borda para quem salvou sombra"

echo "19. a página ignora as cores escolhidas"
troca agendar.html \
  "    if(corValida(cores[k])) raiz.style.setProperty('--at-' + k, cores[k]);" \
  "    if(false) raiz.style.setProperty('--at-' + k, cores[k]);" \
  && rodar "cor escolhida, link na cor da marca"

echo "20. a página aceita cor torta"
troca agendar.html \
  "    if(corValida(cores[k])) raiz.style.setProperty('--at-' + k, cores[k]);" \
  "    if(cores[k]) raiz.style.setProperty('--at-' + k, cores[k]);" \
  && rodar "texto do dono dentro do CSS"

echo "21. o Horários perde a cor dele"
troca estilo.css \
  '.recurso[data-recurso="horarios"]    { --at-tinta:var(--at-horarios) }' \
  "" \
  && rodar "Horários escolhido vermelho, link na marca"

echo "22. o ícone não acompanha a cor escolhida"
troca estilo.css \
  ".recurso-ic{ display:inline-flex; color:var(--at-tinta, var(--ac-600)) }" \
  ".recurso-ic{ display:inline-flex; color:var(--ac-600) }" \
  && rodar "nome vermelho, ícone azul"

echo "23. o tingido do Horários fica na cor da marca"
troca estilo.css \
  "  background:color-mix(in srgb, var(--at-tinta, var(--ac-600)) 13%, var(--painel));" \
  "  background:color-mix(in srgb, var(--ac-600) 13%, var(--painel));" \
  && rodar "letra vermelha sobre lilás"

echo "24. herdar não tira a cor"
troca app.html \
  "  if(corValida(hex)) c[chave] = hex; else delete c[chave];" \
  "  if(corValida(hex)) c[chave] = hex;" \
  && rodar "herdar que não herda"

echo "25. a prévia não sabe qual atalho é qual"
troca app.html \
  ' data-recurso="${qual}"><span data-ico' \
  '><span data-ico' \
  && rodar "prévia na cor da marca, link colorido"

echo "26. o painel perde as cores ao reabrir"
troca app.html \
  "      .filter(([, v]) => corValida(v))),
    sombra: {" \
  "      .filter(() => false)),
    sombra: {" \
  && rodar "cores salvas somem do painel"

echo "27. o aviso de contraste some"
troca app.html \
  "    const pouco = tem && Math.min(...atras.map(f => contrasteEntre(at.cores[k], f))) < 3;" \
  "    const pouco = false;" \
  && rodar "preto sobre preto sem aviso"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
