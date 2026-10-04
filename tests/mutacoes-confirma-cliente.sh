#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a cliente que precisa de confirmação.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-confirma-cliente.sh
#
#  As do banco trocam o 09_cliente.sql inteiro na bancada (psql) e devolvem
#  o original ao terminar cada uma — o arquivo é feito para rodar de novo.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/confirma-cliente.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html agendar.html"
for a in $ARQS; do cp "$a" "/tmp/mcf-$(basename "$a")"; done
cp supabase/09_cliente.sql /tmp/mcf-09.sql
restaurar(){
  for a in $ARQS; do cp "/tmp/mcf-$(basename "$a")" "$a"; done
  $PSQL -f /tmp/mcf-09.sql >/dev/null 2>&1 || echo "  !! não consegui devolver o 09_cliente.sql à bancada"
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mcf-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mcf-saida.txt) reprovações)"
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

trocaSql(){
  cp /tmp/mcf-09.sql /tmp/mcf-mutante.sql
  troca /tmp/mcf-mutante.sql "$1" "$2" || return $?
  $PSQL -f /tmp/mcf-mutante.sql >/dev/null 2>&1 \
    || { echo "  ✗ NÃO RODOU — o 09 mutante não entrou no banco"; perdida=$((perdida+1)); return 9; }
}

echo "1. banco: o agendar() ignora a marca"
trocaSql "             and not public.cliente_exige_confirmacao(v_salao, v_cliente, v_tel)
" "" && rodar "a cliente marcada sai confirmada"

echo "2. banco: a marca só vale pela ficha achada"
trocaSql "       and (c.id = p_cliente
            or (coalesce(public.so_digitos(p_tel), '') <> ''" \
  "       and (c.id = p_cliente
            or (false" && rodar "trocou o primeiro nome e escapou"

echo "3. banco: a pergunta fica aberta"
trocaSql "revoke all on function public.cliente_exige_confirmacao(uuid, uuid, text)
  from public, anon, authenticated;" \
  "grant execute on function public.cliente_exige_confirmacao(uuid, uuid, text) to anon, authenticated;" \
  && rodar "qualquer um descobre quem está marcada"

echo "4. o link diz confirmado para quem ficou esperando"
troca agendar.html \
  "  if(!salaoConfirmaSozinho || statusDaMarcacao === 'pendente'){" \
  "  if(!salaoConfirmaSozinho){" \
  && rodar "promete em nome do salão"

echo "5. o painel não grava a marca"
troca app.html \
  "    exigeConfirmacao: !!(document.getElementById('kExigeConf') || {}).checked," \
  "" \
  && rodar "marca na tela, nada no banco"

echo "6. a lista não mostra quem está marcada"
troca app.html \
  "          ? ' <span class=\"tag t-pend\" title=\"O que ela marcar pelo link espera sua confirmação\">confirma antes</span>' : ''}\${" \
  "          ? '' : ''}\${" \
  && rodar "o dono esquece quem marcou"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
