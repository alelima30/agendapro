#!/usr/bin/env bash
# ===========================================================================
#  A trava dos acentos do 00_tudo.sql, e o item 0 do CONFERIR
#
#    bash tests/acentos.test.sh        (precisa do Postgres da bancada no ar)
#
#  O QUE ACONTECEU: o 00_tudo.sql foi aberto com a codificação errada antes
#  de ser colado, e a produção ficou com "SalÃ£o" e "Teste grÃ¡tis" no nome
#  dos planos — e em todo texto das funções, inclusive o que vai para a
#  cliente.
#
#  O QUE ISTO PROTEGE:
#    1. colado com os acentos trocados, o 00_tudo.sql para na primeira
#       instrução, com aviso legível, sem criar nada;
#    2. um banco que já ficou com acento trocado aparece como FALTA no
#       CONFERIR;
#    3. colar o arquivo certo por cima conserta os nomes — o Básico também.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
# O banco vem do ambiente (no CI, localhost:5432); esta máquina é só o padrão.
P="psql -h ${PGHOST_BANCADA:-${PGHOST:-/tmp}} -p ${PGPORT_BANCADA:-${PGPORT:-5444}} -U ${PGUSER:-postgres}"
DB=acentos_teste
TROCADO=$(mktemp --suffix=.sql)
trap 'rm -f "$TROCADO"; $P -d postgres -qc "drop database if exists $DB;" >/dev/null 2>&1' EXIT

ok=0; ruim=0
e(){ if [ "$2" = "1" ]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1"; [ -n "${3:-}" ] && echo "      $3"; ruim=$((ruim+1)); fi; }

python3 -c "
import sys
s = open('supabase/00_tudo.sql', encoding='utf-8').read()
open(sys.argv[1], 'w', encoding='utf-8').write(s.encode('utf-8').decode('cp1252', errors='replace'))
" "$TROCADO"

$P -d postgres -qc "drop database if exists $DB;" >/dev/null 2>&1
$P -d postgres -qc "create database $DB;" >/dev/null
$P -d $DB -q -f tests/00_stub_supabase.sql >/dev/null 2>&1

echo "1) Colado com os acentos trocados"
saida=$($P -d $DB -v ON_ERROR_STOP=1 -q -f "$TROCADO" 2>&1 | grep -v NOTICE | head -2)
e "para logo no começo, dizendo o que fazer" \
  "$(echo "$saida" | grep -q 'PAREI SEM GRAVAR NADA' && echo 1)" "$saida"
e "e o aviso sai legível (sem acento no texto)" \
  "$(echo "$saida" | grep -q 'link do GitHub (raw)' && echo 1)" "$saida"
n=$($P -d $DB -tAc "select count(*) from pg_tables where schemaname='public'")
e "e não cria nenhuma tabela ($n)" "$([ "$n" = "0" ] && echo 1)"

echo "2) Um banco que já ficou com acento trocado"
$P -d $DB -q -f supabase/00_tudo.sql >/dev/null 2>&1
$P -d $DB -qc "update public.planos set nome = convert_from(convert_to(nome,'UTF8'),'LATIN1') where nome ~ '[^ -~]';"
c=$($P -d $DB -tA -F'|' -f supabase/CONFERIR.sql 2>/dev/null | grep 'Acentos do banco')
e "o CONFERIR acusa FALTA no item dos acentos" "$(echo "$c" | grep -q '|FALTA|' && echo 1)" "$c"
$P -d $DB -qc "update public.planos set nome = nome;" >/dev/null
$P -d $DB -qc "create or replace function public.teste_acento() returns text language sql as \$x\$ select 'N' || 'Ã£o' \$x\$;" >/dev/null
$P -d $DB -qc "update public.planos set nome = convert_from(convert_to(nome,'LATIN1'),'UTF8') where nome ~ 'Ã';" >/dev/null 2>&1
c=$($P -d $DB -tA -F'|' -f supabase/CONFERIR.sql 2>/dev/null | grep 'Acentos do banco')
e "e acusa também texto trocado dentro de função" "$(echo "$c" | grep -q '|FALTA|' && echo 1)" "$c"
$P -d $DB -qc "drop function public.teste_acento();" >/dev/null

echo "3) Colado de novo, do jeito certo"
$P -d $DB -qc "update public.planos set nome = convert_from(convert_to(nome,'UTF8'),'LATIN1') where nome ~ '[^ -~]';"
$P -d $DB -q -f supabase/00_tudo.sql >/dev/null 2>&1
nomes=$($P -d $DB -tAc "select string_agg(codigo || '=' || nome, ' ' order by codigo) from public.planos")
e "os nomes voltam, o Básico também" \
  "$(echo "$nomes" | grep -q 'basico=Básico' && echo "$nomes" | grep -q 'salao=Salão' && echo "$nomes" | grep -q 'trial=Teste grátis' && echo 1)" "$nomes"
c=$($P -d $DB -tA -F'|' -f supabase/CONFERIR.sql 2>/dev/null | grep 'Acentos do banco')
e "e o CONFERIR volta a dizer certo" "$(echo "$c" | grep -q '|certo|' && echo 1)" "$c"

echo
if [ $ruim -eq 0 ]; then echo "✓ $ok verificações dos acentos."; else echo "✗ $ruim de $((ok+ruim)) falharam."; fi
[ $ruim -eq 0 ]
