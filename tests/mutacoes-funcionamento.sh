#!/usr/bin/env bash
# ===========================================================================
#  Quebrar os horários de funcionamento de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-funcionamento.sh
#
#  Cada mutação que sobreviver é um jeito de a página dizer ABERTO com a
#  porta fechada, ou prometer um horário que o dono não cadastrou.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/funcionamento.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css funcionamento.js"
for a in $ARQS; do cp "$a" "/tmp/mfn-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mfn-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mfn-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mfn-saida.txt) reprovações)"
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
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA. O trecho sumiu ou passou a
  # aparecer duas vezes, e o placar seguia dizendo "N mortas, 0 vivas" com
  # uma a menos. Aconteceu no mutacoes-modulos.sh: a nº 5 ficou sem rodar por
  # sessões inteiras, porque o "!!" passava no meio da saída sem contar.
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. o fim do período passa a contar como aberto"
troca funcionamento.js \
  "    if(ag.min >= p.ini && ag.min < p.fim){" \
  "    if(ag.min >= p.ini && ag.min <= p.fim){" \
  && rodar "18:00 em ponto ainda ABERTO"

echo "2. o almoço não é olhado: o próximo período de hoje some"
troca funcionamento.js \
  "  if(depois) return { aberto: false, detalhe: 'Abre às ' + hhmm(depois.ini) };" \
  "" \
  && rodar "no almoço, 'abre amanhã'"

echo "3. 'amanhã' vira o nome do dia"
troca funcionamento.js \
  "    const quando = k === 1 ? 'amanhã'" \
  "    const quando = k === 1 ? NA_FRASE[d]" \
  && rodar "abre terça, dito na segunda à noite"

echo "4. períodos encostados deixam de ser emendados"
troca funcionamento.js \
  "      if(ult && p.ini <= ult.fim) ult.fim = Math.max(ult.fim, p.fim);" \
  "      if(ult && p.ini < ult.fim) ult.fim = Math.max(ult.fim, p.fim);" \
  && rodar "08-12 e 12-18 dizendo 'até 12:00'"

echo "5. semana toda fechada passa a ser 'cadastrada'"
troca funcionamento.js \
  "  return algum ? dias : null;" \
  "  return dias;" \
  && rodar "FECHADO para sempre na página"

echo "6. o relógio ignora o fuso do salão"
troca funcionamento.js \
  "    timeZone: fuso || 'America/Sao_Paulo', weekday:'short'," \
  "    timeZone: 'UTC', weekday:'short'," \
  && rodar "aberto no fuso de Londres"

echo "7. o editor deixa passar horários cruzados"
troca funcionamento.js \
  "      if(ps[i].ini < ps[i - 1].fim){" \
  "      if(false){" \
  && rodar "08-12 e 11-14 aceitos"

echo "8. o salvar ignora a validação"
troca app.html \
  "  if(queixasHorario.length){" \
  "  if(false){" \
  && rodar "horário torto gravado"

echo "9. abrir um dia deixa de copiar o anterior"
troca app.html \
  "  funcEscolhido[d] = copia || [['', '']];" \
  "  funcEscolhido[d] = [['', '']];" \
  && rodar "cada dia digitado do zero"

echo "10. todos fechados no painel gravam sete listas vazias"
troca app.html \
  "  return algum ? saida : null;
}" \
  "  return saida;
}" \
  && rodar "desligar o horário não desliga"

echo "11. a página mostra Informações para quem não cadastrou nada"
troca agendar.html \
  "  if(extra || botoes.length) botoes.push(['informacoes', 'info', 'Informações']);" \
  "  botoes.push(['informacoes', 'info', 'Informações']);" \
  && rodar "página que já estava no ar mudando sozinha"

echo "12. o destaque vai sempre para a segunda"
troca agendar.html \
  "        return \`<div class=\"semana-dia\${d === ag.dow ? ' hoje' : ''}" \
  "        return \`<div class=\"semana-dia\${d === 1 ? ' hoje' : ''}" \
  && rodar "hoje é sábado e a segunda acesa"

echo "13. o cartão não se atualiza sozinho"
troca agendar.html \
  "    if(tela === 'capa') desenharStatusDaCasa();" \
  "" \
  && rodar "ABERTO na hora do almoço"

echo "14. trocar de tela deixa a folha aberta"
troca agendar.html \
  "  if(typeof fecharFolha === 'function') fecharFolha(true);" \
  "" \
  && rodar "folha flutuando sobre a loja"

echo "15. o botão Horários com cor cravada"
troca estilo.css \
  "  background:var(--ac-soft); border-color:var(--ac-line); color:var(--ac-600);
}
.recurso:hover" \
  "  background:#EDE9FE; border-color:#C4B5FD; color:#6D28D9;
}
.recurso:hover" \
  && rodar "salão verde com botão roxo"

echo "16. o dia de hoje com cor cravada"
troca estilo.css \
  ".semana-dia.hoje{ background:var(--ac-soft) }" \
  ".semana-dia.hoje{ background:rgba(109,40,217,.10) }" \
  && rodar "folha roxa em salão vermelho"

echo "17. o endereço volta a entrar sem escape na folha"
troca agendar.html \
  "  if(end.length) itens.push(['local', 'Endereço', escapar(end.join(' · '))," \
  "  if(end.length) itens.push(['local', 'Endereço', end.join(' · ')," \
  && rodar "HTML do dono rodando no celular da cliente"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
