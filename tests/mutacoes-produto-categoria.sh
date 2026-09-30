#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a categoria dos produtos (painel e loja do link).
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-produto-categoria.sh
#
#  Cada mutação que sobreviver é um jeito de a categoria não chegar ao link,
#  de o filtro não filtrar, ou de a mesma categoria virar duas.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/produto-categoria.test.mjs
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

echo "1. a página joga a categoria fora"
troca agendar.html \
  "      categoria: x.categoria || null,
" \
  "" \
  && rodar "o painel guarda e o link não sabe"

echo "2. o filtro não filtra"
troca agendar.html \
  "(!filtroLoja || chaveCategoria(p.categoria) === filtroLoja)" \
  "(true)" \
  && rodar "tocar e ver tudo igual"

echo "3. maiúscula separa a categoria no link"
troca agendar.html \
  "    const k = rot.toLocaleLowerCase('pt');" \
  "    const k = rot;" \
  && rodar "dois \"tratamento de cabelo\""

echo "4. tocar de novo não desmarca"
troca agendar.html \
  "  filtroLoja = c && c === filtroLoja ? null : c;" \
  "  filtroLoja = c;" \
  && rodar "presa numa categoria"

echo "5. a fileira aparece sem categoria nenhuma"
troca agendar.html \
  "    fileira.style.display = lojaCatsAtuais.length ? '' : 'none';" \
  "    fileira.style.display = '';" \
  && rodar "faixa vazia na tela"

echo "6. o nome da categoria sai cru"
troca agendar.html \
  "onclick=\"escolherCategoriaLoja(\${i - 1})\">\${escapar(c.rot)}</button>" \
  "onclick=\"escolherCategoriaLoja(\${i - 1})\">\${c.rot}</button>" \
  && rodar "HTML do dono na página da cliente"

echo "7. o painel não grava"
troca app.html \
  "    categoria: limparCategoria(document.getElementById('pCat').value) || null,
" \
  "" \
  && rodar "Salvar sem efeito"

echo "8. o painel sem a etiqueta"
troca app.html \
  "\`<span class=\"tag-cat\"><span data-ico=\"etiqueta\"></span>" \
  "\`<span class=\"tag-catX\"><span data-ico=\"etiqueta\"></span>" \
  && rodar "categoria invisível na lista"

echo "9. sugestões repetidas no cadastro"
troca app.html \
  "    const k = c.toLocaleLowerCase('pt');" \
  "    const k = c;" \
  && rodar "a mesma categoria duas vezes"

echo "10. a escolhida fora do tema"
troca estilo.css \
  ".loja-cat.on{ background:var(--acao); color:var(--acao-txt); border-color:var(--acao) }
" \
  "" \
  && rodar "não se vê qual está marcada"

echo "11. a fileira empurra a página de lado"
troca estilo.css \
  "  display:flex; gap:8px; overflow-x:auto; overscroll-behavior-x:contain;" \
  "  display:flex; gap:8px;" \
  && rodar "página rolando de lado"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
