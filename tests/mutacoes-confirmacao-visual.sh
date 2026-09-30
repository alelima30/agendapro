#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito "Confira seu agendamento" e "Agendamento enviado!".
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-confirmacao-visual.sh
#
#  Cada mutação que sobreviver é um jeito de a tela prometer um status que o
#  salão não escolheu, de uma cor escrita escapar do tema, ou de um botão
#  levar ao lugar errado.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/confirmacao-visual.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="app.html agendar.html estilo.css"
for a in $ARQS; do cp "$a" "/tmp/mcv-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mcv-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mcv-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mcv-saida.txt) reprovações)"
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

echo "1. o status ignora o dono"
troca agendar.html \
  "  return salaoConfirmaSozinho
    ? \`<div class=\"cf-status cf-status-ok\">" \
  "  return false
    ? \`<div class=\"cf-status cf-status-ok\">" \
  && rodar "\"aguardando\" para quem confirma na hora"

echo "2. o título do fim sempre \"enviado\""
troca agendar.html \
  "    pendente ? 'Agendamento enviado!' : 'Agendamento confirmado!';" \
  "    'Agendamento enviado!';" \
  && rodar "confirmado dito como enviado"

echo "3. o selo sempre de espera"
troca agendar.html \
  "    + \`<div class=\"cf-chip-linha\">\${pendente" \
  "    + \`<div class=\"cf-chip-linha\">\${true" \
  && rodar "espera que não existe"

echo "4. o dia no alto sem \"-feira\""
troca agendar.html \
  "<b>\${diaCompleto(escolha.data)} às \${hm(escolha.inicio)}</b>" \
  "<b>\${dataLonga(escolha.data)} às \${hm(escolha.inicio)}</b>" \
  && rodar "quinta, 01/10"

echo "5. \"Alterar horário\" leva aos serviços"
troca agendar.html \
  "  if(tela === 'confirmar') return irPara('quando');" \
  "  if(tela === 'confirmar') return irPara('servico');" \
  && rodar "recomeçar do zero"

echo "6. \"Voltar para a home\" leva aos serviços"
troca agendar.html \
  "    historico = [];
    irPara('capa', true);
  }
}" \
  "    historico = [];
    irPara('servico', true);
  }
}" \
  && rodar "a home que não é a home"

echo "7. a observação não chega"
troca agendar.html \
  "<textarea id=\"fRecado\" rows=\"3\"" \
  "<textarea id=\"fRecadoX\" rows=\"3\"" \
  && rodar "observação perdida"

echo "8. o total sem destaque"
troca estilo.css \
  ".cf-total .cf-txt b{ font-size:23px;" \
  ".cf-total .cf-txt b{ font-size:15.5px;" \
  && rodar "o valor some entre as linhas"

echo "9. uma cor escrita no ícone do total"
troca estilo.css \
  ".cf-ic-cheio{ background:var(--acao);" \
  ".cf-ic-cheio{ background:#8E2457;" \
  && rodar "vinho em todo tema"

echo "10. o Alterar horário fora da identidade"
troca estilo.css \
  "  background:var(--painel); color:var(--ac-600); border:1.5px solid var(--ac-line); font-weight:700;
" \
  "" \
  && rodar "botão cinza qualquer"

echo "11. o status com cara de erro"
troca estilo.css \
  ".cf-status b{ display:block; font-size:16px; font-weight:700; color:var(--ac-600) }" \
  ".cf-status b{ display:block; font-size:16px; font-weight:700; color:var(--erro) }" \
  && rodar "aguardando em vermelho"

echo "12. no celular, os botões espremidos lado a lado"
troca estilo.css \
  "  body[data-passo=\"confirmar\"] .rodape-acao{ flex-direction:column-reverse }
" \
  "" \
  && rodar "texto quebrando dentro do botão"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
