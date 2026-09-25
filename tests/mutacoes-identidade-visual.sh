#!/usr/bin/env bash
# ===========================================================================
#  Quebrar a identidade visual de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-identidade-visual.sh
#
#  Teste verde não prova nada sozinho: prova que o código passa, não que o
#  teste OLHA. Cada mutação aqui estraga uma regra e exige que a suíte
#  reprove. Mutação que sobrevive é buraco na suíte — ou, duas vezes neste
#  projeto, defeito de projeto que ninguém tinha visto.
#
#  ⚠ AS MUTAÇÕES DAQUI SÃO QUASE TODAS DO LADO "NADA PODE MUDAR". É onde um
#  defeito não dá sinal: a personalização que não funciona o dono reclama no
#  mesmo dia; a que vaza chega calada no salão que nunca abriu a tela.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/identidade-visual.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST="${PGHOST:-/tmp}" PGPORT="${PGPORT:-5444}" PGUSER="${PGUSER:-postgres}"

for a in agendar.html app.html estilo.css supabase/25_loja.sql; do
  cp "$a" "/tmp/mv-$(basename "$a")"
done
restaurar(){
  for a in agendar.html app.html estilo.css supabase/25_loja.sql; do
    cp "/tmp/mv-$(basename "$a")" "$a"
  done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){ # $1 = nome da mutação
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mv-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mv-saida.txt) reprovações)"
    morta=$((morta+1))
  fi
  restaurar
}

troca(){ python3 - "$1" "$2" "$3" <<'PY'
import sys
arq, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(arq, encoding='utf-8').read()
if de not in s:
    print('!! trecho não encontrado em ' + arq); sys.exit(9)
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

echo "1. o modo Atual também marca o <html>"
troca agendar.html \
  "if(modo === 'personalizado' || modo === 'premium')" \
  "if(true)" && rodar "modo Atual marcando o <html>"

echo "2. o logo circular também marca o <html>"
troca agendar.html \
  "if(forma === 'arredondado' || forma === 'quadrado')" \
  "if(true)" && rodar "logo circular marcando o <html>"

echo "3. as nove cores são todas gravadas, e não só as escolhidas"
troca app.html \
  "if(corValida(v)) limpo[chave] = v;" \
  "limpo[chave] = corValida(v) ? v : aparencia.cor;" \
  && rodar "gravando as nove cores sempre"

# ⚠ ESTA PRECISA DA LINHA SEGUINTE PARA MIRAR DIREITO. `sl.cfg =
# Object.assign({}, sl.cfg, {` aparece DEZ vezes no app.html — uma por tela
# que grava alguma coisa no `cfg` — e o `troca` substitui a primeira. Na
# primeira tentativa esta mutação estragou o `salvarNotificacoes()`, que esta
# suíte não exercita, e "sobreviveu": mutação mal-formada parece buraco na
# suíte e manda consertar o que não está quebrado. O `cor: aparencia.cor`
# embaixo é o que distingue a tela de Aparência das outras nove.
echo "4. salvar a aparência sobrescreve o cfg inteiro"
troca app.html \
  "sl.cfg = Object.assign({}, sl.cfg, {
    cor: aparencia.cor," \
  "sl.cfg = Object.assign({}, {
    cor: aparencia.cor," \
  && rodar "aparência apagando o cfg das outras telas"

echo "5. as cores escolhidas entram ANTES do cálculo"
python3 - <<'PY'
s = open('agendar.html', encoding='utf-8').read()
alvo = "  aplicarCoresSoltas(s, p, escuro);\n}"
if alvo not in s: print('!! não achei a chamada'); raise SystemExit(9)
s = s.replace(alvo, "}", 1)
s = s.replace("  const p = (k, v) => raiz.style.setProperty(k, v);\n",
              "  const p = (k, v) => raiz.style.setProperty(k, v);\n"
              "  aplicarCoresSoltas(s, p, escuro);\n", 1)
open('agendar.html', 'w', encoding='utf-8').write(s)
PY
rodar "escolha do dono aplicada antes do cálculo"

echo "6. o gradiente não tira a foto de fundo"
troca agendar.html \
  "  const fundo = (tipoFundo === 'imagem' || tipoFundo === 'cor') ? fotoAnexada : null;" \
  "  const fundo = fotoAnexada;" \
  && rodar "foto e gradiente empilhados"

echo "7. gradiente torto é aceito sem conferir"
troca agendar.html \
  "  if(!(cores.length === 2 || cores.length === 3) || !cores.every(corValida)){" \
  "  if(false){" \
  && rodar "gradiente sem conferência"

# ── ⚠ A ÚNICA MUTAÇÃO DE BANCO, E POR QUE ELA PODE SER FEITA ASSIM ─────────
# O cabeçalho do `tests/bancada/subir.sh` proíbe reinstalar um módulo sozinho:
# neste projeto uma função pode ser definida em mais de um arquivo, e vale a
# do NÚMERO MAIOR — reinstalar um módulo baixo por cima desfaz, calado, o que
# um mais alto corrigiu.
#
# O `25_loja.sql` é o caso em que isso não acontece, e foi conferido antes de
# escrever isto: ele define UMA função só (`vitrine`), e nenhum módulo de 26 a
# 30 a redefine. Ele é a última palavra sobre a única coisa que ele diz, então
# reinstalá-lo devolve exatamente o que o `00_tudo.sql` termina instalando.
#
# Se um dia o 26+ passar a mexer na `vitrine`, este bloco vira uma armadilha:
# apague-o e remonte a bancada inteira em vez de consertá-lo.
echo "8. a vitrine() não leva as cores escolhidas"
if troca supabase/25_loja.sql \
  "'cores',     coalesce(s.cfg->'cores', '{}'::jsonb)," \
  "'cores',     '{}'::jsonb,"; then
  psql -q -d app -v ON_ERROR_STOP=1 -f supabase/25_loja.sql >/dev/null 2>&1
  rodar "vitrine() sem as cores"
  psql -q -d app -v ON_ERROR_STOP=1 -f supabase/25_loja.sql >/dev/null 2>&1
fi

echo "9. o CSS do logo quadrado com o seletor errado"
troca estilo.css \
  '[data-logo="quadrado"]    .marca-selo{ border-radius:4px }' \
  '[data-logo="quadradox"]   .marca-selo{ border-radius:4px }' \
  && rodar "CSS do logo quadrado sem alvo"

echo
echo "  $morta morreram, $viva sobreviveram"
[ "$viva" -eq 0 ] || echo "  ⚠ mutação viva é buraco na suíte — ou defeito de projeto"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
