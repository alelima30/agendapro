#!/usr/bin/env bash
# ===========================================================================
#  Quebrar o aviso da loja de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-loja-aviso.sh
#
#  Cada mutação que sobreviver é um jeito de o painel dizer "está tudo certo"
#  enquanto a página da cliente esconde os produtos — que é exatamente a
#  reclamação que o aviso existe para responder.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/loja-aviso.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

cp app.html /tmp/mla-app.html
restaurar(){ cp /tmp/mla-app.html app.html; bash versao.sh >/dev/null 2>&1; }
trap restaurar EXIT

viva=0; morta=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mla-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mla-saida.txt) reprovações)"
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
}

echo "1. o aviso para de olhar o WhatsApp"
troca app.html \
  "  if(!zapDaCasa(s, o.zap))" \
  "  if(false)" \
  && rodar "salão sem número, painel calado"

echo "2. o espelho usa a régua do numeroWhatsapp() — aceita 13 dígitos sem o 55"
troca app.html \
  "  if(so.length >= 12 && so.startsWith('55')) return so;
  return '';
}" \
  "  if(so.length >= 12) return so;
  return '';
}" \
  && rodar "número estrangeiro: painel diz certo, página esconde"

echo "3. \"tem alguma coisa escrita\" no lugar de \"dá para abrir a conversa\""
troca app.html \
  "  if(!zapDaCasa(s, o.zap))" \
  "  if(!String(o.zap != null ? o.zap : (s.whatsapp || s.telefone || '')).trim())" \
  && rodar "número sem DDD passando por bom"

echo "4. Produtos deixa de mostrar o aviso"
troca app.html \
  "  const porque = souGestor() ? porqueALojaNaoAparece() : '';" \
  "  const porque = '';" \
  && rodar "a lista dizendo 'à venda' sem ressalva"

echo "5. a aba Dados pergunta pelo SALVO, e não pelo digitado"
troca app.html \
  "porqueALojaNaoAparece(null, { loja: true, zap: digitado })" \
  "porqueALojaNaoAparece(null, { loja: true })" \
  && rodar "o aviso não some enquanto digita"

echo "6. o campo WhatsApp deixa de redesenhar o aviso"
troca app.html \
  'placeholder="(11) 99999-8888"
                 oninput="explicarModulos()"' \
  'placeholder="(11) 99999-8888"' \
  && rodar "digitar não muda nada na tela"

echo "7. o aviso para de conferir o 'Vender na página do salão'"
troca app.html \
  "    && p.ativo !== false && p.vendaOnline);" \
  "    && p.ativo !== false);" \
  && rodar "nenhum produto marcado, painel calado"

echo "8. o aviso para de conferir se a loja está ligada"
troca app.html \
  "  if(!loja)
    return 'A loja está <b>desligada</b>" \
  "  if(false)
    return 'A loja está <b>desligada</b>" \
  && rodar "loja desligada, painel calado"

echo ""
echo "$morta mortas, $viva vivas"
[ "$viva" -eq 0 ]
