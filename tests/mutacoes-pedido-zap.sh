#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a barra do pedido e o botão do WhatsApp.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-pedido-zap.sh
#
#  Cada mutação que sobreviver é um jeito de o logo sumir, o total sair
#  cortado ou o Enviar deixar de se ler.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/pedido-zap.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mpz-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mpz-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mpz-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mpz-saida.txt) reprovações)"
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

echo "1. a regra volta a casar com o span do logo"
troca estilo.css \
  "  .carrinho-fita .cf-zap .cf-zap-txt{ display:none }" \
  "  .carrinho-fita .cf-zap span:not(.ic-svg){ display:none }" \
  && rodar "logo some a 360px"

echo "2. o texto volta no celular estreito"
troca estilo.css \
  "  .carrinho-fita .cf-zap .cf-zap-txt{ display:none }" \
  "" \
  && rodar "Enviar pedido a 360px"

echo "3. o total volta a dividir a linha com a contagem"
troca agendar.html \
  "        <b>\${totalEscrito()}</b>
        <span>\${n === 1 ? '1 produto' : n + ' produtos'} · Ver meu pedido</span>" \
  "        <b>\${n === 1 ? '1 produto' : n + ' produtos'} · \${totalEscrito()}</b>
        <span>Ver meu pedido</span>" \
  && rodar "total cortado"

echo "4. o Enviar volta ao painel"
troca estilo.css \
  "  background:var(--fita-txt, var(--acao-txt)); color:var(--fita-base, var(--acao));" \
  "  background:var(--painel); color:var(--acao);" \
  && rodar "roxo sobre azul-marinho"

echo "5. a letra do Enviar volta à cor do botão"
troca estilo.css \
  "  background:var(--fita-txt, var(--acao-txt)); color:var(--fita-base, var(--acao));" \
  "  background:var(--fita-txt, var(--acao-txt)); color:var(--acao);" \
  && rodar "Enviar sem contraste na fita escolhida"

echo "6. a página não calcula a letra da fita"
troca agendar.html \
  "p('--fita-cor', cor); p('--fita-txt', letraSobre(cor));" \
  "p('--fita-cor', cor);" \
  && rodar "letra branca na fita clara"

echo "7. a fita ignora a letra dela"
troca estilo.css \
  "  background:var(--fita-cor, var(--acao)); color:var(--fita-txt, var(--acao-txt));" \
  "  background:var(--fita-cor, var(--acao)); color:var(--acao-txt);" \
  && rodar "letra da fita errada"

echo "8. o botão perde o nome para leitor de tela"
troca agendar.html \
  ' aria-label="Enviar pedido no WhatsApp">' \
  '>' \
  && rodar "botão sem nome"

echo "9. a prévia perde o logo"
troca app.html \
  '<span class="fone-fita-zap"><span data-ico="whatsapp"></span>Enviar</span>' \
  '<span class="fone-fita-zap">Enviar</span>' \
  && rodar "prévia sem logo"

echo "10. a prévia volta ao botão branco do painel"
troca estilo.css \
  "  background:var(--fone-fita-txt, var(--fone-marca-txt)); color:var(--fone-fita-base);" \
  "  background:var(--painel); color:var(--fone-fita-base);" \
  && rodar "prévia diferente da página"

echo "11. a prévia não calcula a letra da fita"
troca app.html \
  ";--fone-fita-txt:\${letraSobre(aparencia.fitaCor)}" \
  "" \
  && rodar "prévia com letra errada"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
