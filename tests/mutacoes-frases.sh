#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a cor de cada frase do topo — uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-frases.sh
#
#  Cada mutação que sobreviver é um jeito de uma frase mudar a cor de outra,
#  de a prévia mentir, ou de o dono escolher uma cor que não chega na página.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/frases.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mfr-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mfr-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
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
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA (ver mutacoes-modulos.sh).
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. o nome volta a seguir só os títulos"
troca estilo.css \
  ".marca-salao h2{ color:var(--cor-nome, var(--txt)) }" \
  "" \
  && rodar "o nome não muda"

echo "2. a rua esquece a cor dela"
troca estilo.css \
  ".marca-end .rua{ font-size:14.5px; color:var(--cor-rua, var(--txt2)) }" \
  ".marca-end .rua{ font-size:14.5px; color:var(--txt2) }" \
  && rodar "rua na cor do texto"

echo "3. bairro e cidade na cor da rua"
troca estilo.css \
  "color:var(--cor-lugar, var(--txt3)); margin-top:1px }" \
  "color:var(--cor-rua, var(--txt3)); margin-top:1px }" \
  && rodar "duas frases, uma cor"

echo "4. o horário de hoje sem cor própria"
troca estilo.css \
  ".status-txt{ flex:1; min-width:0; color:var(--cor-horario, var(--txt2)) }" \
  ".status-txt{ flex:1; min-width:0 }" \
  && rodar "Até amanhã sem cor"

echo "5. o Bem-vindo volta ao destaque"
troca estilo.css \
  "color:var(--cor-bemvindo, var(--ac-600)); margin-bottom:2px;" \
  "color:var(--ac-600); margin-bottom:2px;" \
  && rodar "Bem-vindo sem cor"

echo "6. a frase do Bem-vindo pega a cor do Bem-vindo"
troca estilo.css \
  "color:var(--cor-convite, var(--txt2)); margin:0 0 11px;" \
  "color:var(--cor-bemvindo, var(--txt2)); margin:0 0 11px;" \
  && rodar "convite na cor errada"

echo "7. a página não escreve as variáveis das frases"
troca agendar.html \
  "    if(cor) p(variavel, cor);" \
  "" \
  && rodar "escolhe e nada chega"

echo "8. a letra do Agendar pinta também o Ver produtos"
troca estilo.css \
  "body.tem-letra-agendar .boas .boas-cta:not(.boas-produtos){ color:var(--cor-letra-agendar) }" \
  "body.tem-letra-agendar .boas .boas-cta{ color:var(--cor-letra-agendar) }" \
  && rodar "Ver produtos de metal com a letra do Agendar"

echo "9. a letra do Ver produtos perde para a cor dos produtos"
troca estilo.css \
  "body.tem-letra-produtos .boas .boas-produtos{ color:var(--cor-letra-produtos) }" \
  "body.tem-letra-produtos .boas-produtos{ color:var(--cor-letra-produtos) }" \
  && rodar "a cor dos produtos ganha"

echo "10. a classe da letra do Agendar não liga"
troca agendar.html \
  "  document.body.classList.toggle('tem-letra-agendar', !!letraAgendar);" \
  "" \
  && rodar "letra escolhida, botão igual"

echo "11. a frase herdada mostra a cor da marca"
troca app.html \
  "  if(pai) return pai === 'destaque' ? corEscritaDaMarca()
    : corValida(c[pai]) ? c[pai] : corHerdada(pai);" \
  "" \
  && rodar "quadrado mente sobre a herança"

echo "12. o horário herda do cinza"
troca app.html \
  "  horario:'texto', bemVindo:'destaque', convite:'texto'," \
  "  horario:'discreto', bemVindo:'destaque', convite:'texto'," \
  && rodar "diz que acompanha o que não acompanha"

echo "13. a prévia da rua a 60%"
troca estilo.css \
  ".fone-topo [data-cfg=\"rua\"]{ opacity:1;" \
  ".fone-topo [data-cfg=\"rua\"]{ opacity:.6;" \
  && rodar "cor escolhida apagada"

echo "14. a prévia do nome esquece a cor dele"
troca estilo.css \
  "  color:var(--fone-nomeSalao, var(--fone-titulo, inherit))}" \
  "  color:var(--fone-titulo, inherit)}" \
  && rodar "prévia diferente da página"

echo "15. a prévia do horário esquece a cor dele"
troca estilo.css \
  ".fone-status-txt{ flex:1; min-width:0; color:var(--fone-horario, var(--fone-texto, var(--txt2))) }" \
  ".fone-status-txt{ flex:1; min-width:0; color:var(--fone-texto, var(--txt2)) }" \
  && rodar "horário da prévia sem cor"

echo "16. a prévia do Agendar sem a letra"
troca estilo.css \
  ".fone-cta[data-cfg=\"agendar\"]{ color:var(--fone-letraAgendar, var(--fone-marca-txt)) }" \
  "" \
  && rodar "letra só na página"

echo "17. os botões da prévia sem ícone"
troca app.html \
  "    const ic = \`<span data-ico=" \
  "    const ic = '' || \`<span data-x=" \
  && rodar "sem o logo do botão"

echo "18. tocar no horário leva ao cartão"
troca app.html \
  "<span class=\"fone-status-txt\" data-cfg=\"horario\">" \
  "<span class=\"fone-status-txt\">" \
  && rodar "toque no lugar errado"

echo "19. tocar na rua leva ao texto"
troca app.html \
  "  rua:      ['.cor-linha[data-chave=\"rua\"]']," \
  "  rua:      ['.cor-linha[data-chave=\"texto\"]']," \
  && rodar "toque no lugar errado"

echo "20. o aviso mede o Bem-vindo contra o fundo da página"
troca app.html \
  "  olhar('bemVindo',  'o Bem-vindo',               3,   'quadro');" \
  "  olhar('bemVindo',  'o Bem-vindo',               3);" \
  && rodar "acusa o que se lê"

echo "21. o aviso não olha a rua"
troca app.html \
  "  olhar('rua',       'a rua',                     4.5, 'topo');" \
  "" \
  && rodar "rua ilegível sem aviso"

echo "22. o aviso não olha a letra do botão"
troca app.html \
  "  noBotao('letraAgendar', 'a letra do Agendar horário', corDoBotaoNaPrevia());" \
  "" \
  && rodar "letra invisível sem aviso"

echo "23. a letra do Ver produtos some do painel"
troca app.html \
  "  ['coresProdutos', ['produtos', 'letraProdutos']]," \
  "  ['coresProdutos', ['produtos']]," \
  && rodar "sem onde escolher"

echo "24. o título dos serviços perde para o .cat da página"
troca estilo.css \
  "#capaServicos > .cat{ color:var(--cor-tit-servicos, var(--txt3)) !important }" \
  "#capaServicos > .cat{ color:var(--cor-tit-servicos, var(--txt3)) }" \
  && rodar "Nossos serviços sem cor"

echo "25. o nome do produto esquece a cor dele"
troca estilo.css \
  "overflow:hidden; font-size:13px; font-weight:650; color:var(--cor-nome-produto, var(--txt));" \
  "overflow:hidden; font-size:13px; font-weight:650;" \
  && rodar "nome do produto sem cor"

echo "26. o preço do serviço pega a cor do preço do produto"
troca estilo.css \
  "color:var(--cor-preco-servico, var(--ac-600)) }" \
  "color:var(--cor-preco-produto, var(--ac-600)) }" \
  && rodar "dois preços, uma cor"

echo "27. o Ver todos os produtos não liga a classe"
troca agendar.html \
  "  document.body.classList.toggle('tem-cor-ver-produtos', !!verProdutos);" \
  "" \
  && rodar "Ver todos sem cor"

echo "28. a legenda do slide sempre branca"
troca estilo.css \
  "  color:var(--cor-legenda, #fff);" \
  "  color:#fff;" \
  && rodar "legenda sem cor"

echo "29. o nome de quem atende esquece a cor"
troca estilo.css \
  "#capaEquipe .tt{ color:var(--cor-nome-equipe, var(--txt)) }" \
  "" \
  && rodar "equipe sem cor"

echo "30. a duração escolhida fica apagada na prévia"
troca estilo.css \
  ".fone .fone-cartao-dur.com-cor{ opacity:1; color:var(--fone-duracao) }" \
  "" \
  && rodar "prévia a 60%"

echo "31. o nome de quem atende some do painel"
troca app.html \
  "  ['coresFrasesEquipe',   ['tituloEquipe', 'nomeEquipe']]," \
  "  ['coresFrasesEquipe',   ['tituloEquipe']]," \
  && rodar "sem onde escolher"

echo "32. a legenda herdada mostra a cor da marca"
troca app.html \
  "  if(chave === 'legenda') return '#FFFFFF';" \
  "" \
  && rodar "quadrado mente"

echo "33. tocar no nome do produto leva aos títulos"
troca app.html \
  "  nomeProduto:      ['.cor-linha[data-chave=\"nomeProduto\"]']," \
  "  nomeProduto:      ['.cor-linha[data-chave=\"titulo\"]']," \
  && rodar "toque no lugar errado"

echo "34. a página não escreve a cor da duração"
troca agendar.html \
  "    descServico:'--cor-desc-servico', precoServico:'--cor-preco-servico', duracao:'--cor-duracao'," \
  "    descServico:'--cor-desc-servico', precoServico:'--cor-preco-servico'," \
  && rodar "duração escolhida e nada"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
