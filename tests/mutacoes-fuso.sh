#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o fuso do salão (58_fuso.sql e as telas). Uma regra
#  por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-fuso.sh
#
#  Cada mutação que sobreviver é um jeito de um horário marcado sair do lugar
#  — ou de um aparelho gravar com uma hora de erro — sem teste nenhum acusar.
#  As do banco são aplicadas na bancada e desfeitas em seguida.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/fuso-tela.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST=${PGHOST:-/tmp} PGPORT=${PGPORT:-5444} PGUSER=${PGUSER:-postgres}
BANCO=${PGBANCO:-app}

ARQS="app.html agendar.html supabase/58_fuso.sql"
for a in $ARQS; do cp "$a" "/tmp/mfu-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mfu-$(basename "$a")" "$a"; done
  psql -q -d "$BANCO" -f supabase/58_fuso.sql >/dev/null 2>&1
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  psql -q -d "$BANCO" -f supabase/58_fuso.sql >/dev/null 2>&1
  if node "$T" >/tmp/mfu-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mfu-saida.txt) reprovações)"
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

echo "1. o banco troca o fuso e deixa os instantes onde estavam"
troca supabase/58_fuso.sql \
  "     set inicio = ((inicio - c_longe) at time zone p_de) at time zone p_para," \
  "     set inicio = (inicio - c_longe)," \
  && rodar "a cliente das 09:00 vira cliente das 08:00"

echo "2. a trava de 90 segundos não trava"
troca supabase/58_fuso.sql \
  "                and s.fuso_mudou_em > now() - interval '90 seconds') then" \
  "                and s.fuso_mudou_em > now() + interval '90 seconds') then" \
  && rodar "aparelho com o relógio antigo grava com uma hora de erro"

echo "3. qualquer texto vale como fuso"
troca supabase/58_fuso.sql \
  "     and exists (select 1 from pg_timezone_names z where z.name = p_fuso)" \
  "     and true" \
  && rodar "fuso inventado derruba a agenda no navegador"

echo "4. a sincronização não pergunta o fuso"
troca app.html \
  "  if(await conferirFuso()) return 0;" \
  "  if(false) return 0;" \
  && rodar "o outro aparelho pinta a agenda uma hora fora"

echo "5. o painel acha que o fuso nunca muda"
troca app.html \
  "  if(!noBanco || noBanco === sl.fuso) return false;" \
  "  if(true) return false;" \
  && rodar "o outro aparelho segue no relógio antigo"

echo "6. a lista troca na tela antes de o banco confirmar"
troca app.html \
  "  if(sel && sl) sel.value = sl.fuso;" \
  "  if(false) sel.value = sl.fuso;" \
  && rodar "cancelar deixa a tela dizendo Manaus num salão de Brasília"

echo "7. a dica do relógio do aparelho nunca aparece"
troca app.html \
  "  if(Math.abs(dif) < 30) return '';" \
  "  if(true) return '';" \
  && rodar "o salão de Manaus não fica sabendo que precisa trocar"

echo "8. o link da cliente não confere o relógio antes de marcar"
troca agendar.html \
  "  return !!(f && f !== salao.fuso);" \
  "  return false;" \
  && rodar "a página aberta desde antes marca uma hora errada"

echo "9. a tela promete mas não diz quantos horários ficaram"
troca app.html \
  "    if(n) partes.push(n === 1 ? '1 horário marcado' : n + ' horários marcados');" \
  "    if(false) partes.push('');" \
  && rodar "troca sem prestar contas dos horários"

echo
echo "morreram $morta · sobreviveram $viva · não rodaram $perdida"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
