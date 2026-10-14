#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito os aniversariantes do painel — o teste tem de reprovar.
#
#    bash tests/bancada/subir.sh          (noutro terminal)
#    bash tests/mutacoes-aniversarios.sh
#
#  O teste é o tests/aniversarios.test.mjs, na bancada.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/aniversarios.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html"
guarda(){ echo "/tmp/mniv-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mniv-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mniv-saida.txt) reprovações)"
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

echo "1. o 29 de fevereiro some nos anos comuns"
troca app.html \
  "      const caiHoje = mm === mesN && (dd === diaN
        || (mesN === 2 && diaN === 29 && dd === 28 && !bissexto(a)));" \
  "      const caiHoje = mm === mesN && dd === diaN;" \
  && rodar "quem nasceu em 29/02 fica três anos sem parabéns"

echo "2. o 29 de fevereiro cai no 28 também no ano bissexto"
troca app.html \
  "dd === 28 && !bissexto(a)));" \
  "dd === 28));" \
  && rodar "parabéns duas vezes no ano bissexto"

echo "3. o \"hoje\" vira o do aparelho, e não o do salão"
troca app.html \
  "function aniversariantes(dias){
  const hj = hoje();" \
  "function aniversariantes(dias){
  const hj = iso(new Date(Date.now() + 864e5));" \
  && rodar "o aviso adianta ou atrasa um dia"

echo "4. a janela não inclui o último dia"
troca app.html \
  "    for(let k = 0; k <= dias; k++){" \
  "    for(let k = 0; k < dias; k++){" \
  && rodar "hoje some do Hoje (janela zero) e o 7º dia some do Dashboard"

echo "5. o cartão do Hoje some"
troca app.html \
  "  alvoHoje.innerHTML = kpis + gaveta + blocoNiverHoje() + prox;" \
  "  alvoHoje.innerHTML = kpis + gaveta + prox;" \
  && rodar "ninguém fica sabendo do aniversário"

echo "6. o botão aparece antes do dia"
troca app.html \
  "    \${x.faltam === 0
      ? \`<button type=\"button\" class=\"btn btn-peq\" onclick=\"darParabens" \
  "    \${x.faltam >= 0
      ? \`<button type=\"button\" class=\"btn btn-peq\" onclick=\"darParabens" \
  && rodar "convite a mandar parabéns adiantado"

echo "7. o botão volta a abrir a janela de escolher recado"
troca app.html \
  "  mandarRecado(num, 'aniversario', JSON.stringify({" \
  "  escolherRecado(num, ({" \
  && rodar "um toque a mais, e o recado errado à mão"

echo "8. o recado leva o nome inteiro"
troca app.html \
  "  mandarRecado(num, 'aniversario', JSON.stringify({
    cliente: (nomeCliente(clienteId) || '').split(' ')[0]," \
  "  mandarRecado(num, 'aniversario', JSON.stringify({
    cliente: (nomeCliente(clienteId) || '')," \
  && rodar "\"Oi Bia Souza\" — cara de robô"

echo "9. ficha sem telefone abre conversa com ninguém"
troca app.html \
  "function darParabens(clienteId){
  const num = zapDoCliente(clienteId);
  if(!num){" \
  "function darParabens(clienteId){
  const num = zapDoCliente(clienteId) || '55';
  if(!num){" \
  && rodar "o WhatsApp abre em \"número inválido\""

echo "10. o cartão do Hoje aparece mesmo vazio"
troca app.html \
  "  const hoje0 = aniversariantes(0);
  if(!hoje0.length) return '';" \
  "  const hoje0 = aniversariantes(0);" \
  && rodar "um cartão vazio todo dia ensina a não olhar"

echo "11. a idade de ficha sem ano plausível"
troca app.html \
  "                   idade: anoN >= 1900 && idade > 0 && idade < 120 ? idade : null });" \
  "                   idade: idade });" \
  && rodar "\"faz 2026 anos\" para quem não deu o ano"

echo "12. o cartão entra no padrão de quem nunca mexeu no Dashboard"
troca app.html \
  "const PADRAO_DASHBOARD = ['pendentes', 'fatAno', 'fatSemana'];" \
  "const PADRAO_DASHBOARD = ['pendentes', 'fatAno', 'fatSemana', 'aniversarios'];" \
  && rodar "muda o dashboard de todo salão sem ninguém pedir"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
