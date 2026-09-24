#!/usr/bin/env bash
# ===========================================================================
#  Quebrar a fita do carrinho de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-fita.sh
#
#  Cinco escolhas atravessando cinco paradas — painel, vitrine, ponte, o
#  `aplicarFita()` e o CSS — dão vinte e cinco jeitos de quebrar em silêncio.
#  Estas são as que dá para cometer amanhã sem má intenção.
#
#  ⚠ AS MAIS IMPORTANTES SÃO AS DO LADO "NADA PODE MUDAR": salão que nunca
#  abriu esta tela tem que continuar com a fita de fábrica, e a cor tem que
#  continuar saindo da personalização. Defeito que LIGA alguma coisa o dono
#  reclama no mesmo dia; defeito que muda a página de quem não pediu nada
#  chega calado.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/fita.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST="${PGHOST:-/tmp}" PGPORT="${PGPORT:-5444}" PGUSER="${PGUSER:-postgres}"

ARQS="app.html agendar.html estilo.css supabase/25_loja.sql"
for a in $ARQS; do cp "$a" "/tmp/mf-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mf-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0
# Reinstalar o 25 sozinho é seguro: ele é o ÚLTIMO a definir a vitrine(), e o
# `sintaxe.test.js` cobra que continue sendo.
rodar(){ # $1 = nome, $2 = "sql" quando precisa reinstalar
  bash versao.sh >/dev/null 2>&1
  [ "${2:-}" = sql ] && psql -q -d app -v ON_ERROR_STOP=1 \
      -f supabase/25_loja.sql >/dev/null 2>&1
  if node "$T" >/tmp/mf-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mf-saida.txt) reprovações)"
    morta=$((morta+1))
  fi
  restaurar
  [ "${2:-}" = sql ] && psql -q -d app -v ON_ERROR_STOP=1 \
      -f supabase/25_loja.sql >/dev/null 2>&1
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
}

echo "1. a vitrine para de devolver o metal escolhido"
troca supabase/25_loja.sql \
  "      'fitaMetal',  coalesce(s.cfg->>'fitaMetal', 'media')," \
  "      'fitaMetal',  'media'," \
  && rodar "escolha presa no painel" sql

echo "2. fitaBrilho volta a ser lido com ::boolean"
troca supabase/25_loja.sql \
  "      'fitaBrilho', lower(btrim(coalesce(s.cfg->>'fitaBrilho', 'true')))
                      not in ('false', 'f', '0', 'no', 'nao', 'não')," \
  "      'fitaBrilho', coalesce((s.cfg->>'fitaBrilho')::boolean, true)," \
  && rodar "peneira de brilho com ::boolean" sql

echo "3. a ponte esquece a cor da fita"
troca agendar.html \
  "      fitaCor: s.fitaCor || null," \
  "      fitaCor: null," \
  && rodar "cor não atravessa a ponte"

echo "4. o padrão passa a escrever variável"
troca agendar.html \
  "  if(t && t !== '5.2s') p('--fita-tempo', t); else fora('--fita-tempo');" \
  "  if(t) p('--fita-tempo', t); else fora('--fita-tempo');" \
  && rodar "padrão virando escolha"

# ⚠ AQUI NÃO DÁ PARA MUTAR O VAZAMENTO DE `--acao`, e tentei duas vezes.
#
# A ideia era estragar a separação entre a cor da fita e a cor do botão: um
# `p('--acao', cor)` dentro do `aplicarFita()`. Sobreviveu. Depois com
# `!important`. Sobreviveu de novo.
#
# Não é buraco na suíte: o `aplicarModo()` roda ANTES do `p('--acao', cor)` do
# `aplicarAparencia()`, e os dois escrevem no MESMO bloco de estilo embutido.
# Ali `!important` não protege nada — um `setProperty` posterior sem
# prioridade substitui o valor e a prioridade junto. O vazamento é apagado
# três linhas depois de nascer.
#
# A verificação "a cor do botão continua a do salão" fica no teste, porque a
# regra é real. O que não existe é como quebrá-la de dentro daquela função.
#
# No lugar dela, a mutação que MORDE: o CSS ignorando a escolha.

echo "5. o CSS ignora a cor escolhida e usa a do botão"
troca estilo.css \
  "  background:var(--fita-cor, var(--acao)); color:var(--acao-txt);" \
  "  background:var(--acao); color:var(--acao-txt);" \
  && rodar "cor escolhida que não chega no pixel"

echo "6. o brilho parado vira opacidade zero (animação continua rodando)"
troca estilo.css \
  '[data-fita-brilho="nao"] .carrinho-fita::after{ display:none }' \
  '[data-fita-brilho="nao"] .carrinho-fita::after{ opacity:0 }' \
  && rodar "animação rodando escondida"

echo "7. o interruptor GERAL de brilho deixa de valer para a fita"
troca estilo.css \
  "body.sem-brilho .carrinho-fita::after{ animation:none; opacity:0 }" \
  "body.sem-brilho .carrinho-fita::after{ opacity:.99 }" \
  && rodar "interruptor geral virando mentira"

echo "8. o texto da fita volta para baixo da faixa de luz"
troca estilo.css \
  ".carrinho-fita > *{ position:relative; z-index:1 }" \
  ".carrinho-fita > *{ position:relative }" \
  && rodar "valor do pedido piscando de branco"

echo "9. chapado passa a escrever luz zero, e o gradiente volta"
troca agendar.html \
  "  const METAL = { suave: ['18%','12%'], media: ['30%','18%'], forte: ['46%','30%'] };" \
  "  const METAL = { chapado: ['0%','0%'], suave: ['18%','12%'], media: ['30%','18%'], forte: ['46%','30%'] };" \
  && rodar "chapado que não é chapado"

echo "10. o salvar esquece a cor da fita"
troca app.html \
  "    fitaCor: aparencia.fitaCor || null," \
  "    fitaCor: null," \
  && rodar "cor que não grava"

echo "11. a prévia mente sobre a intensidade"
troca estilo.css \
  '.fone-fita[data-metal="forte"]{ --ff-luz:46%; --ff-sombra:30% }' \
  '.fone-fita[data-metal="forte"]{ --ff-luz:18%; --ff-sombra:12% }' \
  && rodar "prévia com número diferente da página"

echo ""
echo "$morta mortas, $viva vivas"
[ "$viva" -eq 0 ]
