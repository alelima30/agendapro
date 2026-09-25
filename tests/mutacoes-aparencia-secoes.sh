#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a tela de Aparência em seções e a separação das
#  cores — uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-aparencia-secoes.sh
#
#  Cada mutação que sobreviver é um jeito de uma cor voltar a mexer no que
#  não é dela, ou de a tela voltar a misturar as configurações.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/aparencia-secoes.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mas-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mas-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mas-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mas-saida.txt) reprovações)"
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

echo "1. o texto volta a pintar o pino"
troca estilo.css \
  ".marca-end .rua .ic-svg,
.opcao .ic.ic-neutro .ic-svg{ color:var(--ico, var(--ico-texto)) }" \
  "" \
  && rodar "Textos → verde, pino verde"

echo "2. o relógio volta a seguir o texto secundário"
troca estilo.css \
  "[data-moldura=\"elegante\"] .sv-cartao-relogio .ic-svg{ color:var(--ico, var(--ico-discreto)) }" \
  "" \
  && rodar "texto mexendo em ícone"

echo "3. os ícones dos botões voltam a obedecer a Cor dos ícones"
troca estilo.css \
  ".boas-cta .ic-svg, .boas-b2 .ic-svg," \
  ".boas-b2 .ic-svg," \
  && rodar "calendário na cor dos ícones, dentro do botão"

echo "4. os atalhos ignoram os Ícones de destaque"
troca estilo.css \
  ".recurso-ic{ display:inline-flex; color:var(--at-tinta, var(--ico-destaque, var(--ac-marca, var(--ac-600)))) }" \
  ".recurso-ic{ display:inline-flex; color:var(--at-tinta, var(--ac-marca, var(--ac-600))) }" \
  && rodar "ícone de destaque escolhido e ignorado"

echo "5. os ícones dos atalhos voltam a seguir o texto de destaque"
troca estilo.css \
  ".recurso-ic{ display:inline-flex; color:var(--at-tinta, var(--ico-destaque, var(--ac-marca, var(--ac-600)))) }" \
  ".recurso-ic{ display:inline-flex; color:var(--at-tinta, var(--ico-destaque, var(--ac-600))) }" \
  && rodar "Destaque → ícones"

echo "6. o Horários volta a seguir o texto de destaque"
troca estilo.css \
  "  color:var(--at-tinta, var(--ac-marca, var(--ac-600)));
}" \
  "  color:var(--at-tinta, var(--ac-600));
}" \
  && rodar "Destaque → Horários"

echo "7. a página não guarda a cor da marca à parte"
troca agendar.html \
  "  p('--ac-marca', escuro ? mexer(cor, 0.30) : mexer(cor, -0.28));" \
  "" \
  && rodar "tudo volta a depender do destaque"

echo "8. a página ignora os Ícones de destaque"
troca agendar.html \
  "  if(iconeDestaque) p('--ico-destaque', iconeDestaque);" \
  "" \
  && rodar "escolhido e ignorado"

echo "9. a janela do Horários volta ao texto de destaque"
troca estilo.css \
  "  color:var(--ico-destaque, var(--ac-marca, var(--ac-600))); background:var(--ac-soft);
}
.folha-ic svg{" \
  "  color:var(--ac-600); background:var(--ac-soft);
}
.folha-ic svg{" \
  && rodar "ícone da janela na cor do texto"

echo "10. a cor própria do atalho perde para a Cor dos ícones"
troca estilo.css \
  ".recurso-ic .ic-svg, .folha-ic .ic-svg," \
  ".folha-ic .ic-svg," \
  && rodar "vermelho escolhido, azul na tela"

echo "11. Cor dos ícones volta para o meio dos textos"
troca app.html \
  "  ['coresTextos', ['titulo', 'texto', 'discreto', 'destaque']],
  ['coresIcones', ['icone', 'iconeDestaque']]," \
  "  ['coresTextos', ['titulo', 'texto', 'discreto', 'destaque', 'icone']],
  ['coresIcones', ['iconeDestaque']]," \
  && rodar "configurações misturadas"

echo "12. a Moldura do logo volta para Textos"
troca app.html \
  "  ['coresBordas', ['borda', 'moldura']]," \
  "  ['coresBordas', ['borda']],
  ['coresTextos2', ['moldura']]," \
  && rodar "moldura longe das bordas"

echo "13. o HEX some"
troca app.html \
  "  pintarPreviaFone();
  ligarHex();
}" \
  "  pintarPreviaFone();
}" \
  && rodar "sem campo de código"

echo "14. o HEX aceita qualquer coisa"
troca app.html \
  "  return /^[0-9a-f]{6}\$/i.test(t) ? '#' + t.toLowerCase() : null;" \
  "  return '#' + t.toLowerCase();" \
  && rodar "código torto vira cor"

echo "15. o HEX curto não é expandido"
troca app.html \
  "  if(/^[0-9a-f]{3}\$/i.test(t)) t = t.split('').map(c => c + c).join('');
" \
  "" \
  && rodar "f0a não vira #FF00AA"

echo "16. o HEX grava por fora da função da cor"
troca app.html \
  "        cor.dispatchEvent(new Event('input', { bubbles: true }));
" \
  "" \
  && rodar "quadrado muda e a escolha não"

echo "17. o quadrado do ícone mostra a cor da marca"
troca app.html \
  "  if(chave === 'icone') return PADRAO_TEMA[escuro ? 'escuro' : 'claro'].texto;
" \
  "" \
  && rodar "quadrado mentindo"

echo "18. o quadrado da moldura mostra a cor da marca"
troca app.html \
  "  if(chave === 'moldura') return corDoAnelPadrao();" \
  "" \
  && rodar "quadrado mentindo"

echo "19. Gradientes sempre oferece usar"
troca app.html \
  "  mostrar('gradUsar', !comGrad);" \
  "  mostrar('gradUsar', true);" \
  && rodar "botão para ligar o que já está ligado"

echo "20. a prévia perde o pino"
troca estilo.css \
  ".fone-topo .fone-pino, .fone-topo .fone-pino svg{" \
  ".fone-pino, .fone-pino svg{" \
  && rodar "Cor dos ícones sem aparecer na prévia"

echo "21. a prévia ignora os Ícones de destaque"
troca estilo.css \
  "  color:var(--fone-at-tinta, var(--fone-iconeDestaque, var(--fone-ac-marca, var(--fone-ac, var(--fone-marca))))) }" \
  "  color:var(--fone-at-tinta, var(--fone-ac-marca, var(--fone-ac, var(--fone-marca)))) }" \
  && rodar "prévia na marca, link colorido"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
