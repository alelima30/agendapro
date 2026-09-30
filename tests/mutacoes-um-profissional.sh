#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o "Com quem?" de uma pessoa só.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-um-profissional.sh
#
#  Cada mutação que sobreviver é um jeito de o "Tanto faz" voltar quando não
#  decide nada, de a única pessoa não vir marcada, de o voltar soltar o
#  horário já escolhido, ou de o "ir direto" do painel não chegar ao link.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/um-profissional.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mup-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mup-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mup-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mup-saida.txt) reprovações)"
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

echo "1. o \"Tanto faz\" aparece com uma pessoa só"
troca agendar.html \
  "  if(!unico) html += \`<button class=\"opcao \${qualquer?'sel':''}\" onclick=\"escolherProf('*')\">" \
  "  html += \`<button class=\"opcao \${qualquer?'sel':''}\" onclick=\"escolherProf('*')\">" \
  && rodar "escolha que não decide nada"

echo "2. a única pessoa não vem marcada"
troca agendar.html \
  "  if(unico && escolha.profissionalId !== aptos[0].id){" \
  "  if(false){" \
  && rodar "toque a mais para seguir"

echo "3. contar a equipe, e não quem faz o serviço"
troca agendar.html \
  "  const unico = aptos.length === 1;" \
  "  const unico = profsDoSalao().length === 1;" \
  && rodar "barba com Tanto faz"

echo "4. o voltar solta o horário"
troca agendar.html \
  "  if(unico && escolha.profissionalId !== aptos[0].id){" \
  "  if(unico){" \
  && rodar "horário perdido no voltar"

echo "5. o \"Com quem?\" não pergunta ao banco"
troca agendar.html \
  "  if(NA_NUVEM && vagasChave !== chaveDasVagas(ids)){ pedirVagas(ids); return; }" \
  "" \
  && rodar "\"sem horário\" com a agenda livre"

echo "6. a pergunta sai com a chave errada"
troca agendar.html \
  "function chaveDasVagas(ids){
  const aptos = ids || (" \
  "function chaveDasVagas(ids){
  const aptos = (" \
  && rodar "o banco perguntado a cada tela"

echo "7. a página não lê a escolha do dono"
troca agendar.html \
  "      pularComQuem: s.pularComQuem === true," \
  "" \
  && rodar "o painel diz pular e o link mostra"

echo "8. pular mesmo com duas pessoas no serviço"
troca agendar.html \
  "    && profsQueAtendem(escolha.servicos).length === 1;" \
  "    && profsQueAtendem(escolha.servicos).length >= 1;" \
  && rodar "a cliente perde a escolha de com quem"

echo "9. pular sem marcar a única pessoa"
troca agendar.html \
  "    escolha.profissionalId = unica.id;" \
  "" \
  && rodar "horários de ninguém"

echo "10. \"Para outra pessoa\" não pula"
troca agendar.html \
  "  mudarPara(escolha.junto ? 'ambos' : 'filho');
  seguirDepoisDoQuem();" \
  "  mudarPara(escolha.junto ? 'ambos' : 'filho');
  irPara('prof');" \
  && rodar "um caminho pula e o outro não"

echo "11. o painel não grava a escolha"
troca app.html \
  "    pularComQuem: pularComQuemEscolhido ?? ((sl.cfg || {}).pularComQuem === true)," \
  "" \
  && rodar "tocar e salvar sem efeito"

echo "12. o painel nasce em \"Ir direto\""
troca app.html \
  "    pularComQuemEscolhido = (sl.cfg || {}).pularComQuem === true;" \
  "    pularComQuemEscolhido = true;" \
  && rodar "salão acorda com o caminho mudado"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
