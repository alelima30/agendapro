#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito as travas do Grátis e o Básico — o teste tem de
#  reprovar.
#
#    bash tests/bancada/subir.sh          (noutro terminal)
#    PLAYWRIGHT=… bash tests/mutacoes-planos.sh
#
#  O teste é o tests/planos-modulos.test.mjs, na bancada (banco e tela). Cada
#  mutação entra no banco pelo próprio arquivo SQL que ela mexe — e, quando
#  esse arquivo reescreve os planos, os que vêm depois dele no 00_tudo também
#  —, e o original volta no fim de cada rodada.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/planos-modulos.test.mjs
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="supabase/12_relatorios.sql supabase/17_caixa.sql supabase/22_cotas.sql
      supabase/24_produtos.sql supabase/25_loja.sql supabase/27_pacotes.sql
      supabase/28_sem_comanda.sql supabase/34_cupons.sql app.html"
guarda(){ echo "/tmp/mpl-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
SQLS=""
aplicar(){ for f in $SQLS; do $PSQL -f "$f" >/dev/null 2>&1 || return 1; done; }
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  aplicar || echo "  !! não consegui devolver o SQL original à bancada"
}
trap 'SQLS="supabase/22_cotas.sql supabase/24_produtos.sql"; restaurar' EXIT

viva=0; morta=0; perdida=0
rodar(){
  if ! aplicar; then
    echo "  ✗ NÃO RODOU — o SQL mutante não entrou no banco ($1)"; perdida=$((perdida+1))
    restaurar; return 0
  fi
  if node "$T" >/tmp/mpl-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mpl-saida.txt) reprovações)"
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

echo "1. o caixa abre no Grátis"
SQLS="supabase/17_caixa.sql"
troca supabase/17_caixa.sql \
  "  perform public.exigir_recurso(new.salao_id, 'caixa', 'O caixa');" \
  "  null;" && rodar "caixa e comanda no plano de graça"

echo "2. o relatório sai no Grátis"
SQLS="supabase/12_relatorios.sql"
troca supabase/12_relatorios.sql \
  "  perform public.exigir_recurso(p_salao, 'relatorios', 'O relatório');" \
  "" && rodar "relatório pelo console no Grátis"

echo "3. cria pacote no Grátis"
SQLS="supabase/27_pacotes.sql"
troca supabase/27_pacotes.sql \
  "  perform public.exigir_recurso(new.salao_id, 'pacotes', 'Pacote');" \
  "  null;" && rodar "pacote novo no Grátis"

echo "4. vende pacote no Grátis"
SQLS="supabase/27_pacotes.sql"
troca supabase/27_pacotes.sql \
  "  perform public.exigir_recurso(v_salao, 'pacotes', 'Vender pacote');" \
  "" && rodar "vende o pacote antigo no Grátis"

echo "5. cria cupom no Grátis"
SQLS="supabase/34_cupons.sql"
troca supabase/34_cupons.sql \
  "  perform public.exigir_recurso(new.salao_id, 'cupons', 'Cupom');" \
  "  null;" && rodar "cupom novo no Grátis"

echo "6. o cupom antigo vale no Grátis"
SQLS="supabase/34_cupons.sql"
troca supabase/34_cupons.sql \
  "  if not coalesce(public.recurso_bool(p_salao, 'cupons'), false) then
    return jsonb_build_object('motivo', 'Este estabelecimento não está aceitando cupons agora.');" \
  "  if false then
    return jsonb_build_object('motivo', 'Este estabelecimento não está aceitando cupons agora.');" \
  && rodar "desconto do cupom antigo no Grátis"

echo "7. o link do Grátis mostra o campo de cupom"
SQLS="supabase/34_cupons.sql"
troca supabase/34_cupons.sql \
  "     and coalesce(public.recurso_bool(p_salao, 'cupons'), false)
\$\$;" \
  "\$\$;" && rodar "campo de cupom no link simples"

echo "8. a comanda liga no Grátis pelo interruptor"
SQLS="supabase/28_sem_comanda.sql"
troca supabase/28_sem_comanda.sql \
  "    and coalesce(public.recurso_bool(p_salao, 'caixa'), false)
\$\$;" \
  "\$\$;" && rodar "comanda e caixa no Grátis"

echo "9. o link do Grátis sai com a aparência personalizada"
SQLS="supabase/25_loja.sql"
troca supabase/25_loja.sql \
  "      case when coalesce(public.recurso_bool(s.id, 'aparencia'), false) then coalesce(s.cfg, '{}'::jsonb)" \
  "      case when true then coalesce(s.cfg, '{}'::jsonb)" \
  && rodar "aparência premium de graça"

echo "10. a loja aparece no link do Grátis"
SQLS="supabase/25_loja.sql"
troca supabase/25_loja.sql \
  "              else '{\"loja\": \"false\"}'::jsonb end as cfg) c" \
  "              else '{}'::jsonb end as cfg) c" \
  && rodar "loja no plano de graça"

echo "11. o link do Grátis perde o selo"
SQLS="supabase/25_loja.sql"
troca supabase/25_loja.sql \
  "      'selo', not coalesce(public.recurso_bool(s.id, 'aparencia'), false)," \
  "      'selo', false," && rodar "sem a propaganda do AgendaPro"

echo "12. o Grátis ganha o caixa no plano"
SQLS="supabase/22_cotas.sql supabase/24_produtos.sql"
troca supabase/22_cotas.sql \
  "    'caixa', false, 'relatorios', false, 'loja', false," \
  "    'caixa', true, 'relatorios', false, 'loja', false," && rodar "o plano de graça com caixa"

echo "13. o Grátis volta aos 40 horários"
SQLS="supabase/22_cotas.sql supabase/24_produtos.sql"
troca supabase/22_cotas.sql \
  "    'agendamentos_mes', 20)" \
  "    'agendamentos_mes', 40)" && rodar "o Grátis menos limitado"

echo "14. o Grátis volta a ter produto"
SQLS="supabase/24_produtos.sql"
troca supabase/24_produtos.sql \
  "update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 0)
  where codigo = 'gratuito';" \
  "update public.planos set recursos = recursos || jsonb_build_object('max_produtos', 10)
  where codigo = 'gratuito';" && rodar "catálogo de produtos de graça"

echo "16. qualquer um descobre o plano de qualquer salão"
SQLS="supabase/22_cotas.sql supabase/24_produtos.sql"
troca supabase/22_cotas.sql \
  "  select case when public.e_equipe(p_salao) then public.plano_efetivo(p_salao) end" \
  "  select public.plano_efetivo(p_salao)" && rodar "plano do salão para quem é de fora"

echo "15. a tela não trava nada"
SQLS=""
troca app.html \
  "  return v === undefined || v === true;" \
  "  return true;" && rodar "a tela oferece o que o banco nega"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
