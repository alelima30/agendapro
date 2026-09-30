#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito os modelos prontos — uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-modelos.sh
#
#  Cada mutação que sobreviver é um jeito de experimentar gravar sem querer,
#  de o "Voltar" não voltar, ou de o modelo levar junto o que era do salão.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/modelos.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mmo-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mmo-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mmo-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mmo-saida.txt) reprovações)"
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
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA (ver mutacoes-modulos.sh).
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. experimentar já grava"
troca app.html \
  "  aparencia.atalhos.sombra.intensidade = intensidadeDa(aparencia.atalhos.sombra);
  pintarAparencia();" \
  "  aparencia.atalhos.sombra.intensidade = intensidadeDa(aparencia.atalhos.sombra);
  salvarAparencia(); pintarAparencia();" \
  && rodar "o toque vai direto ao banco"

echo "2. o antes é guardado a cada modelo"
troca app.html \
  "  if(!modeloAntes) modeloAntes = JSON.parse(JSON.stringify(aparencia));" \
  "  modeloAntes = JSON.parse(JSON.stringify(aparencia));" \
  && rodar "Voltar volta ao modelo anterior"

echo "3. o Voltar não devolve"
troca app.html \
  "  if(modeloAntes) aparencia = modeloAntes;" \
  "" \
  && rodar "o modelo fica na tela"

echo "4. as cores do modelo se misturam com as de antes"
troca app.html \
  "    cores: Object.assign({}, m.cores)," \
  "    cores: Object.assign({}, aparencia.cores, m.cores)," \
  && rodar "sobra a cor dos produtos de antes"

echo "5. a cor de cada atalho fica"
troca app.html \
  "    atalhos: lerAtalhos(Object.assign({ cores:{} }, m.atalhos))," \
  "    atalhos: lerAtalhos(Object.assign({ cores: aparencia.atalhos.cores }, m.atalhos))," \
  && rodar "Horários na cor antiga"

echo "6. a intensidade da sombra não é refeita"
troca app.html \
  "  aparencia.atalhos.sombra.intensidade = intensidadeDa(aparencia.atalhos.sombra);" \
  "" \
  && rodar "Suave marcada com números de outra"

echo "7. a cor da fita de antes fica"
troca app.html \
  "    fitaBrilho: m.fita.brilho, fitaTempo: m.fita.tempo, fitaCor: ''," \
  "    fitaBrilho: m.fita.brilho, fitaTempo: m.fita.tempo," \
  && rodar "fita vermelha no modelo"

echo "8. modelo liso apaga o gradiente montado"
troca app.html \
  "    gradiente: m.gradiente || aparencia.gradiente," \
  "    gradiente: m.gradiente || null," \
  && rodar "o gradiente dele some"

echo "9. salvar não encerra o modelo"
troca app.html \
  "  // Salvar é aceitar: o que está na prévia passa a ser o de verdade.
  modeloAntes = null; modeloAtual = null;" \
  "" \
  && rodar "Voltar desfaz o que foi salvo"

echo "10. o Salvar do pé deixa a barra"
troca app.html \
  "  // Sai o \"Nada foi salvo ainda\" dos modelos: agora foi.
  pintarModelos();" \
  "" \
  && rodar "diz que nada foi salvo depois de salvar"

echo "11. trocar de salão leva o modelo junto"
troca app.html \
  "    aparencia = lerAparencia();
    modeloAntes = null; modeloAtual = null;" \
  "    aparencia = lerAparencia();" \
  && rodar "o Voltar de um salão no outro"

echo "12. o cartão não experimenta"
troca app.html \
  "data-modelo=\"\${m.id}\" onclick=\"experimentarModelo('\${m.id}')\">" \
  "data-modelo=\"\${m.id}\">" \
  && rodar "tocar não faz nada"

echo "13. a barra aparece sem modelo"
troca app.html \
  "  barra.style.display = m ? '' : 'none';" \
  "  barra.style.display = '';" \
  && rodar "barra vazia no topo"

echo "14. o cartão tocado não se marca"
troca app.html \
  "class=\"modelo\${modeloAtual === m.id ? ' on' : ''}\"" \
  "class=\"modelo\"" \
  && rodar "qual está na prévia?"

echo "15. sem entrada no índice"
troca app.html \
  "        <button type=\"button\" onclick=\"irParaSecaoAp('apModelos')\">✨ Modelos prontos</button>
" \
  "" \
  && rodar "o índice não leva aos modelos"

echo "16. os ícones da prévia somem a cada mudança"
troca app.html \
  "  if(window.aplicarIcones) aplicarIcones(alvo);
  if(!alvo._toque){" \
  "  if(!alvo._toque){" \
  && rodar "atalhos sem ícone"

echo "17. o convite volta ao cinza do painel"
troca estilo.css \
  ".fone .fone-boas-sub{" \
  ".fone-boas-sub{" \
  && rodar "escuro sobre o escuro"

echo "18. um modelo com texto que não se lê"
troca app.html \
  "texto:'#5E4A4F'" \
  "texto:'#C9B5BA'" \
  && rodar "texto claro no papel claro"

echo "19. um modelo com nome de profissão"
troca app.html \
  "nome:'Algodão Doce'" \
  "nome:'Unhas Algodão Doce'" \
  && rodar "o nome é da profissão"

echo "20. o Usar não confirma"
troca app.html \
  "  barra.innerHTML = \`<span>✓ Pronto: <b>\${escapar(m.nome)}</b> é o visual do seu link agora." \
  "  barra.innerHTML = \`<span>✓ <b>\${escapar(m.nome)}</b> é o visual do seu link agora." \
  && rodar "sem o Pronto"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
