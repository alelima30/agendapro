#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a aparência fácil: as cores da logo e o
#  "Arrumar para mim". Uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-aparencia-facil.sh
#
#  Cada mutação que sobreviver é um jeito de o dono tocar no botão fácil
#  e sair com uma página feia, ilegível ou diferente da que viu.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/aparencia-facil.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/maf-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/maf-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/maf-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/maf-saida.txt) reprovações)"
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

echo "1. toda logo vira página clara"
troca app.html \
  "    const escuro = transparente ? lMedia > 0.75 : lMedia < 0.38;" \
  "    const escuro = false;" \
  && rodar "selo preto e dourado numa página branca"

echo "2. experimentar duas logos esquece o que o dono tinha"
troca app.html \
  "  modeloAntes = modeloAntes || JSON.parse(JSON.stringify(aparencia));" \
  "  modeloAntes = JSON.parse(JSON.stringify(aparencia));" \
  && rodar "Voltar devolve a logo anterior, não a aparência dele"

echo "3. o botão da logo liga sem logo"
troca app.html \
  "    <button type=\"button\" class=\"btn btn-p\" id=\"btCorDaLogo\" \${logo && !lendoLogo ? '' : 'disabled'}" \
  "    <button type=\"button\" class=\"btn btn-p\" id=\"btCorDaLogo\" \${!lendoLogo ? '' : 'disabled'}" \
  && rodar "botão que não tem o que ler"

echo "4. logo que não carrega: silêncio"
troca app.html \
  "    alert('Não consegui ler as cores da sua logo.\\n\\nEscolha um modelo pronto aqui embaixo, '" \
  "    void('Não consegui ler as cores da sua logo.\\n\\nEscolha um modelo pronto aqui embaixo, '" \
  && rodar "toque que não faz nada e não diz nada"

echo "5. o Arrumar só conserta a letra dos botões"
troca app.html \
  "      consertos.push({ chave, cor, piso, fundos: soFundo ? fundos : soCartao ? [cartao] : [cartao, ...fundos] });" \
  "" \
  && rodar "aviso que o Arrumar não tira"

echo "6. o topo da Aparência não avisa"
troca app.html \
  "  pintarAvisoDeLeitura(queixas);" \
  "" \
  && rodar "aviso só onde ninguém passa"

echo "7. o Arrumar mexe também nos fundos"
troca app.html \
  "  for(const x of lista) c[x.chave] = corLegivel(x.cor, x.fundos, Math.max(x.piso, x.chave === 'discreto' ? 2.5 : 4.5));" \
  "  for(const x of lista) c[x.chave] = corLegivel(x.cor, x.fundos, Math.max(x.piso, x.chave === 'discreto' ? 2.5 : 4.5)); c.card = '#F3F4F6';" \
  && rodar "cartão trocado sem pedir"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
