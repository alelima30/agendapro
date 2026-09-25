#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a prévia com produtos, o botão Ver produtos e o
#  toque na prévia — uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-previa-produtos.sh
#
#  Cada mutação que sobreviver é um jeito de a prévia voltar a mentir sobre
#  o link, ou de o toque levar a lugar nenhum.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/previa-produtos.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mpp-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mpp-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mpp-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mpp-saida.txt) reprovações)"
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

echo "1. a prévia esquece os produtos"
troca app.html \
  "       \${temPr ? \`<div class=\"fone-svs\" data-cfg=\"produtos\">" \
  "       \${false ? \`<div class=\"fone-svs\" data-cfg=\"produtos\">" \
  && rodar "o print dele: link com produtos, prévia sem"

echo "2. a prévia esquece o Ver produtos"
troca app.html \
  "  if(temPr) botoes.push(['produtos', 'Ver produtos']);
" \
  "" \
  && rodar "um botão a menos na prévia"

echo "3. a prévia esquece o convite"
troca app.html \
  "         <p class=\"fone-boas-sub\" data-cfg=\"endereco\">\${escapar(convite)}</p>
" \
  "" \
  && rodar "Bem-vindo sem texto"

echo "4. a prévia perde a ordem de nome"
troca app.html \
  "    .sort((a, b) => String(a.nome || '').localeCompare(String(b.nome || ''), 'pt'));" \
  "    ;" \
  && rodar "Shampoo primeiro na prévia, Máscara no link"

echo "5. o slide volta ao 4:3"
troca app.html \
  "               style=\"aspect-ratio:\${FORMA[aparencia.slideForma] || '16 / 8'}\">" \
  "               style=\"aspect-ratio:4 / 3\">" \
  && rodar "slide de outra forma"

echo "6. o slide perde o nome"
troca app.html \
  "    \${legenda ? \`<span class=\"fone-slide-leg\">\${escapar(legenda)}</span>\` : ''}
" \
  "" \
  && rodar "slide sem legenda"

echo "7. o véu engrossa blocos sem foto"
troca app.html \
  "  const cartoesFechados = fotoNoFundo && (aparencia.cartoes === 'fechado'" \
  "  const cartoesFechados = (aparencia.cartoes === 'fechado'" \
  && rodar "blocos com fundo sobre fundo liso"

echo "8. o preço da prévia volta à cor do botão"
troca estilo.css \
  "  color:var(--fone-ac, var(--fone-destaque, var(--fone-marca)))}" \
  "  color:var(--fone-destaque, var(--fone-marca))}" \
  && rodar "preço roxo na prévia, azul no link"

echo "9. a página ignora o Igual ao Agendar"
troca agendar.html \
  "  const metalProd = (salao.botaoProdutos || cfg.botaoProdutos) === 'metal';" \
  "  const metalProd = false;" \
  && rodar "escolhido e ignorado"

echo "10. o botão perde a marca de produtos"
troca agendar.html \
  "    + (t === 'loja' ? ' boas-produtos' : '');" \
  "    + '';" \
  && rodar "cor dos produtos sem onde entrar"

echo "11. a página ignora a cor dos produtos"
troca agendar.html \
  "  document.body.classList.toggle('tem-cor-produtos', !!produtos);" \
  "  document.body.classList.toggle('tem-cor-produtos', false);" \
  && rodar "cor escolhida e ignorada"

echo "12. o metal dos produtos volta à cor dos botões"
troca estilo.css \
  "  --acao:var(--prod-cor); --acao-txt:var(--prod-txt); --acao-hover:var(--prod-hover);
" \
  "" \
  && rodar "rosa escolhido, roxo na tela"

echo "13. o discreto ignora a cor"
troca estilo.css \
  "body.tem-cor-produtos .boas-b2.boas-produtos{
  color:var(--prod-cor);" \
  "body.tem-cor-produtos .boas-b2.boas-produtos{
  color:inherit;" \
  && rodar "discreto sem a cor dele"

echo "14. o carrinho ignora a cor dos produtos"
troca estilo.css \
  "  background:color-mix(in srgb, var(--prod-cor) 14%, transparent); color:var(--prod-cor);
}" \
  "  background:color-mix(in srgb, var(--prod-cor) 14%, transparent);
}" \
  && rodar "carrinho na cor da marca"

echo "15. o Ver todos ignora a cor dos produtos"
troca agendar.html \
  "    <button class=\"ver-todos ver-todos-produtos\" onclick=\"irPara('loja')\">" \
  "    <button class=\"ver-todos\" onclick=\"irPara('loja')\">" \
  && rodar "ver todos na cor da marca"

echo "16. a página esquece o botão no caminho da vitrine"
troca agendar.html \
  "      botaoProdutos: s.botaoProdutos || null,
" \
  "" \
  && rodar "a vitrine entrega e a página joga fora"

echo "17. o painel não grava o estilo"
troca app.html \
  "    botaoProdutos: aparencia.botaoProdutos,
" \
  "" \
  && rodar "escolhe, salva, e nada"

echo "18. a prévia ignora a cor dos produtos no metal"
troca app.html \
  "  const metalProd = corProd || corDoBotaoNaPrevia();" \
  "  const metalProd = corDoBotaoNaPrevia();" \
  && rodar "rosa no link, roxo na prévia"

echo "19. tocar não leva a lugar nenhum"
troca app.html \
  "      if(el && alvo.contains(el)) irParaConfig(el.dataset.cfg);" \
  "      if(false) irParaConfig(el.dataset.cfg);" \
  && rodar "toque morto"

echo "20. tocar não acende o controle"
troca app.html \
  "    el.classList.add('ap-alvo');
" \
  "" \
  && rodar "rola e não mostra onde"

echo "21. tocar não rola até o controle"
troca app.html \
  "  visiveis[0].scrollIntoView({ behavior:'smooth', block:'center' });
" \
  "" \
  && rodar "acende fora da tela"

echo "22. o Agendar horário perde o endereço"
troca app.html \
  "      return \`<div class=\"fone-cta\${brilho}\" data-cfg=\"agendar\">\${rot}</div>\`;" \
  "      return \`<div class=\"fone-cta\${brilho}\">\${rot}</div>\`;" \
  && rodar "tocar no botão leva ao Bem-vindo"

echo "23. a logo leva ao lugar errado"
troca app.html \
  "  logo:     ['.cor-linha[data-chave=\"moldura\"]', '#reguaLogoBorda', '#reguaLogoForma']," \
  "  logo:     ['#reguaLogoForma']," \
  && rodar "a moldura longe do toque"

echo "24. o quadrado da fita volta à cor da marca"
troca app.html \
  "    fc.value = aparencia.fitaCor || corDoBotaoNaPrevia();   // a fita herda o BOTÃO, e não a marca" \
  "    fc.value = aparencia.fitaCor || aparencia.cor;" \
  && rodar "quadrado azul, fita roxa"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
