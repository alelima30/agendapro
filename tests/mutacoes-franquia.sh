#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a franquia e a reserva da cliente — o teste tem de
#  reprovar.
#
#    bash tests/bancada/subir.sh          (noutro terminal)
#    bash tests/mutacoes-franquia.sh
#
#  O teste é o tests/franquia.test.mjs, na bancada. Cada mutação entra no
#  banco da bancada pelos próprios 22_cotas.sql e 24_produtos.sql, e o
#  original volta no fim (e a cada rodada).
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/franquia.test.mjs
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

# Na ordem do 00_tudo: o 24 redefine o uso_do_plano() do 22; o 10 (campanhas)
# chama a regra do 22 em tempo de execução.
ARQS="supabase/10_campanhas.sql supabase/22_cotas.sql supabase/24_produtos.sql"
SQLS="supabase/10_campanhas.sql supabase/22_cotas.sql supabase/24_produtos.sql"
guarda(){ echo "/tmp/mfr-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
aplicar(){ for f in $SQLS; do $PSQL -f "$f" >/dev/null 2>&1 || return 1; done; }
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  aplicar || echo "  !! não consegui devolver o SQL original à bancada"
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  if ! aplicar; then
    echo "  ✗ NÃO RODOU — o SQL mutante não entrou no banco ($1)"; perdida=$((perdida+1))
    restaurar; return 0
  fi
  if node "$T" >/tmp/mfr-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mfr-saida.txt) reprovações)"
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
F=supabase/22_cotas.sql

echo "1. o teste grátis volta a ter a franquia do Essencial"
troca $F \
  "'mensagens_mes', 100)
  where codigo = 'trial';" \
  "'mensagens_mes', 300)
  where codigo = 'trial';" \
  && rodar "cada teste pode custar três vezes mais"

echo "2. o Essencial fica nos 300"
troca $F \
  "'mensagens_mes', 500)
  where codigo = 'individual';" \
  "'mensagens_mes', 300)
  where codigo = 'individual';" \
  && rodar "quem atende 6 por dia fica sem lembrete no fim do mês"

echo "3. o lembrete da cliente cai na regra do salão"
troca $F \
  "    when p_tipo in ('confirmacao', 'lembrete')" \
  "    when p_tipo in ('confirmacao')" \
  && rodar "a cliente perde o lembrete antes do salão perder o resumo"

echo "4. as do salão vão até o teto"
troca $F \
  "    else public.mensagens_no_mes(p_salao) < public.teto_mensagens_salao(p_salao)" \
  "    else public.mensagens_no_mes(p_salao) < public.teto_mensagens(p_salao)" \
  && rodar "não sobra reserva nenhuma para a cliente"

echo "5. o worker ignora o tipo"
troca $F \
  "       and public.pode_enviar_tipo(n.salao_id, n.tipo)" \
  "       and public.pode_enviar(n.salao_id)" \
  && rodar "a reserva existe e ninguém a respeita"

echo "6. a reserva vira 20%"
troca $F \
  "floor(x.t * 0.9)::int" \
  "floor(x.t * 0.8)::int" \
  && rodar "o salão perde o aviso cedo demais"

echo "7. lembrete de horário que já passou sai"
troca $F \
  "     and a.inicio <= now();" \
  "     and a.inicio <= now() - interval '1 day';" \
  && rodar "\"seu horário é daqui a duas horas\" depois do atendimento"

echo "8. o prazo pega horário que ainda vem"
troca $F \
  "     and a.inicio <= now();" \
  "     and a.inicio <= now() + interval '1 day';" \
  && rodar "o lembrete de amanhã é cancelado hoje"

echo "9. a tela não recebe até onde vão as do salão"
troca supabase/24_produtos.sql \
  "      'tetoSalao', public.teto_mensagens_salao(p_salao)));" \
  "      'tetoSalao', null));" \
  && rodar "a tela promete o aviso antigo"

echo "10. a regra da reserva aberta para qualquer um"
troca $F \
  "revoke all on function public.pode_enviar_tipo(uuid, text) from public, anon, authenticated;" \
  "grant execute on function public.pode_enviar_tipo(uuid, text) to anon, authenticated;" \
  && rodar "a função do worker fica na mão da rua"

echo "11. a fila de campanha não pergunta pelo limite"
troca supabase/10_campanhas.sql \
  "       and public.campanha_liberada(d.salao_id)
     order by d.criado_em" \
  "     order by d.criado_em" \
  && rodar "campanha pelo console sai sem limite, pelo número de todos"

echo "12. iniciar a campanha não recusa"
troca supabase/10_campanhas.sql \
  "  if not public.campanha_liberada(c.salao_id) then" \
  "  if false then" \
  && rodar "o dono do Grátis inicia campanha pelo console"

echo "13. a regra da campanha esquece o plano"
troca $F \
  "  select public.recurso_bool(p_salao, 'campanhas_whatsapp')
     and public.pode_enviar_tipo(p_salao, 'campanha')" \
  "  select public.pode_enviar_tipo(p_salao, 'campanha')" \
  && rodar "todo plano manda promoção pelo número do AgendaPro"

echo "14. a regra da campanha esquece a franquia"
troca $F \
  "  select public.recurso_bool(p_salao, 'campanhas_whatsapp')
     and public.pode_enviar_tipo(p_salao, 'campanha')" \
  "  select public.recurso_bool(p_salao, 'campanhas_whatsapp')" \
  && rodar "plano que libera campanha manda sem teto"

echo "15. campanha enviada não conta no mês"
troca $F \
  "              and d.status = 'enviado'" \
  "              and false" \
  && rodar "a franquia com porta dos fundos"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
