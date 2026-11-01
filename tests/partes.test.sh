#!/usr/bin/env bash
# ===========================================================================
# As duas partes do 00_tudo.sql (supabase/montar-partes.sh)
#
#   1. cada parte cabe no SQL Editor do Supabase, com folga (< 950 KB — ele
#      recusou o arquivo inteiro com 1.026.868 bytes);
#   2. juntas, têm EXATAMENTE os módulos do 00_tudo.sql, na mesma ordem;
#   3. estão em dia: geradas de novo, saem idênticas às do repositório.
# ===========================================================================
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$AQUI")"
S="$RAIZ/supabase"
falhou=0
ok(){ echo "  ✓ $1"; }
nao(){ echo "  ✗ $1"; falhou=1; }

for n in 1 2; do
  t=$(wc -c < "$S/00_tudo_parte$n.sql")
  [ "$t" -lt 950000 ] && ok "a parte $n cabe no editor ($t bytes)" \
    || nao "a parte $n passou do limite do editor ($t bytes): mova o corte no montar-partes.sh"
done

mods(){ grep -o '^-- ## [0-9][0-9]_[a-z_]*\.sql' "$@" | sed 's/^.*## //'; }
if [ "$(mods "$S/00_tudo.sql")" = "$(cat <(mods "$S/00_tudo_parte1.sql") <(mods "$S/00_tudo_parte2.sql"))" ]; then
  ok "juntas, os mesmos módulos do 00_tudo.sql, na mesma ordem"
else
  nao "as partes não batem com o 00_tudo.sql — falta módulo novo no montar-partes.sh?"
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -r "$S/." "$TMP/"
bash "$TMP/montar-partes.sh" >/dev/null
if cmp -s "$TMP/00_tudo_parte1.sql" "$S/00_tudo_parte1.sql" && cmp -s "$TMP/00_tudo_parte2.sql" "$S/00_tudo_parte2.sql"; then
  ok "em dia com os módulos (geradas de novo, saem iguais)"
else
  nao "as partes estão velhas: rode supabase/montar.sh"
fi
exit $falhou
