#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o horário do "+ Agendamento" — o teste tem de reprovar.
#
#    python3 -m http.server 8099 --directory .          (noutro terminal)
#    bash tests/mutacoes-horario-form.sh
#
#  O teste é o tests/horario-form.test.mjs, na demonstração.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/horario-form.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html"
SQLS=""
guarda(){ echo "/tmp/mhf-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
aplicar(){ for f in $SQLS; do $PSQL -f "$f" >/dev/null 2>&1 || return 1; done; }
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  aplicar || echo "  !! não consegui devolver o SQL original à bancada"
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if ! aplicar; then
    echo "  ✗ NÃO RODOU — o SQL mutante não entrou no banco ($1)"; perdida=$((perdida+1))
    restaurar; return 0
  fi
  if node "$T" >/tmp/mhf-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mhf-saida.txt) reprovações)"
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

echo "1. o campo vazio volta a ser meia-noite"
troca app.html \
  "  if(!m) return null;
  const h = Number(m[1]), mi = Number(m[2]);" \
  "  if(!m) return 0;
  const h = Number(m[1]), mi = Number(m[2]);" \
  && rodar "00:00 e Fora da jornada para quem não escolheu"

echo "2. os horários livres não aparecem"
troca app.html \
  "  pintarLivresDoForm(profId, data, dur, ini);
  if(ini === null){" \
  "  if(ini === null){" \
  && rodar "a recepção não vê o que está livre"

echo "3. o Agendar marca sem hora"
troca app.html \
  "  if(ini === null){
    alert('Escolha o horário: toque" \
  "  if(false){
    alert('Escolha o horário: toque" \
  && rodar "marca um horário que ninguém escolheu"

echo "4. hoje mostra horário que já passou"
troca app.html \
  "  if(data === agora.data) livres = livres.filter(t => t >= agora.min);" \
  "  ;" \
  && rodar "oferece as 9h às 15h"

echo "5. os botões são refeitos no meio do toque"
troca app.html \
  "  if(livres.length && alvo.dataset.chave === chave){" \
  "  if(false){" \
  && rodar "o primeiro toque se perde"

echo "6. a máscara deixa passar minuto que não existe"
troca app.html \
  "  if(m && m[0] > '5') m = '';" \
  "  ;" \
  && rodar "12:60"

echo "7. a hora não se completa ao sair do campo"
troca app.html \
  "  return String(h).padStart(2, '0') + ':' + String(mi).padStart(2, '0');" \
  "  return t;" \
  && rodar "9:30 fica 9:30 e 7 fica 7"

echo "8. o bloqueio em branco vira meia-noite"
troca app.html \
  "  if(ini == null || fim == null){ alert('Confira as horas do bloqueio (ex.: 12:00 e 13:00).'); return; }" \
  "  ;" \
  && rodar "bloqueio sem hora sem explicação"

echo "9. o dia cheio não oferece os próximos dias"
troca app.html \
  "    const prox = data ? proximosDiasComVaga(profId, data, dur, 3) : [];" \
  "    const prox = [];" \
  && rodar "dia cheio vira beco sem saída"

echo "10. os campos de hora voltam a abrir o relógio do celular"
troca app.html \
  "const ATRIB_HORA = 'type=\"text\" inputmode=\"numeric\"" \
  "const ATRIB_HORA = 'type=\"time\" inputmode=\"numeric\"" \
  && rodar "o botão de confirmar some no Android"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
