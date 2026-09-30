#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a Etapa 2 do agendamento (para quem é).
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-etapa2.sh
#
#  Cada mutação que sobreviver é um jeito de o "para mim" pedir nome, de o
#  Continuar ligar sem a relação ou sem o nome, ou de a pessoa se perder no
#  caminho até o banco.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/etapa2.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/me2-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/me2-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/me2-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/me2-saida.txt) reprovações)"
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

echo "1. o serviço pula a Etapa 2"
troca agendar.html \
  "  if(tela === 'servico')   return irPara('quem');" \
  "  if(tela === 'servico')   return irPara('prof');" \
  && rodar "sem perguntar para quem"

echo "2. Para mim não segue direto"
troca agendar.html \
  "  if(q === 'mim'){ mudarPara('mim'); return irPara('prof'); }" \
  "  if(q === 'mim'){ mudarPara('mim'); }" \
  && rodar "para mim abre a tela do nome"

echo "3. o Continuar liga sem a relação"
troca agendar.html \
  "  if(!escolha.relacao) return 'Escolha a relação com você';" \
  "" \
  && rodar "só o nome basta"

echo "4. o nome em branco conta"
troca agendar.html \
  "  if(!(escolha.filhoNome || '').trim()) return 'Digite o nome da pessoa';" \
  "  if(!(escolha.filhoNome || '')) return 'Digite o nome da pessoa';" \
  && rodar "espaços valem como nome"

echo "5. o Continuar não desliga"
troca agendar.html \
  "  bp.disabled = !!falta;" \
  "  bp.disabled = false;" \
  && rodar "botão ligado sem nada"

echo "6. a relação não vai junto do nome"
troca agendar.html \
  "  return nome && r && r[0] !== 'outra' ? nome + ' (' + r[1].toLowerCase() + ')' : nome;" \
  "  return nome;" \
  && rodar "o salão não sabe que é a filha"

echo "7. \"Outra pessoa\" vira \"(outra pessoa)\""
troca agendar.html \
  "  return nome && r && r[0] !== 'outra' ? nome + ' (' + r[1].toLowerCase() + ')' : nome;" \
  "  return nome && r ? nome + ' (' + r[1].toLowerCase() + ')' : nome;" \
  && rodar "parêntese sem sentido"

echo "8. o \"eu também\" é esquecido"
troca agendar.html \
  "  mudarPara(escolha.junto ? 'ambos' : 'filho');" \
  "  mudarPara('filho');" \
  && rodar "um horário só para dois"

echo "9. trocar quem é atendido não solta o horário"
troca agendar.html \
  "  escolha.data = null; escolha.inicio = null;
}
function escolherQuem(q){" \
  "}
function escolherQuem(q){" \
  && rodar "duração nova, horário velho"

echo "10. o voltar esquece a relação"
troca agendar.html \
  "  document.getElementById('gradeRelacao').innerHTML = RELACOES.map(([v, rot, emoji]) => \`
    <button type=\"button\" class=\"rel-card\${escolha.relacao === v ? ' sel' : ''}\"" \
  "  document.getElementById('gradeRelacao').innerHTML = RELACOES.map(([v, rot, emoji]) => \`
    <button type=\"button\" class=\"rel-card\"" \
  && rodar "a escolhida não aparece marcada"

echo "11. a primeira tela não marca a porta escolhida"
troca agendar.html \
  "    if(b) b.classList.toggle('sel', escolha.quem === q);" \
  "" \
  && rodar "voltar sem saber o que escolheu"

echo "12. a primeira tela mostra o botão de baixo"
troca agendar.html \
  "  if(tela === 'quem')        { desenharQuem();      trilhaAte(2); rodape.style.display = 'none'; }" \
  "  if(tela === 'quem')        { desenharQuem();      trilhaAte(2); }" \
  && rodar "botão repetindo o cartão"

echo "13. a trilha não anda na Etapa 2"
troca agendar.html \
  "  if(tela === 'quemOutra')   { desenharQuemOutra(); trilhaAte(2); acertarBotaoQuem(); }" \
  "  if(tela === 'quemOutra')   { desenharQuemOutra(); trilhaAte(1); acertarBotaoQuem(); }" \
  && rodar "trilha parada"

echo "14. as relações em uma coluna"
troca estilo.css \
  ".rel-grade{ display:grid; grid-template-columns:repeat(2, minmax(0, 1fr));" \
  ".rel-grade{ display:grid; grid-template-columns:1fr;" \
  && rodar "lista comprida no celular"

echo "15. o nome não chega ao banco"
troca agendar.html \
  "  const unit = duracaoEscolhida();
  const filho = nomeDoAtendido();" \
  "  const unit = duracaoEscolhida();
  const filho = '';" \
  && rodar "agendamento sem a pessoa"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
