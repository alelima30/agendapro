#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a tela de senha nova quando o link não serve.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-senha-link.sh
#
#  Cada mutação que sobreviver é um jeito de o aviso voltar a sair em
#  colunas, de a cliente se perder no painel, ou de o link ser gasto antes
#  de ela tocar em Salvar.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/senha-link.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}

ARQS="nova-senha.html dados.js"
for a in $ARQS; do cp "$a" "/tmp/msl-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/msl-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/msl-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/msl-saida.txt) reprovações)"
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

echo "1. o aviso volta a ser flex"
troca nova-senha.html \
  "  display:block;padding:12px 14px;border-radius:var(--r-sm);" \
  "  display:flex;gap:10px;padding:12px 14px;border-radius:var(--r-sm);" \
  && rodar "título, frase e link em colunas"

echo "2. o detalhe do erro vai cru para a tela"
troca nova-senha.html \
  "'<br><span class=\"mono\">' + escapar(detalhe) + '</span>'" \
  "'<br><span class=\"mono\">' + detalhe + '</span>'" \
  && rodar "texto da barra de endereço vira HTML"

echo "3. qualquer volta é aceita"
troca nova-senha.html \
  "  return /^agendar\\.html\\?salao=[a-z0-9-]{1,60}\$/.test(v) ? v : '';" \
  "  return v;" \
  && rodar "a tela vira redirecionador para fora"

echo "4. pedir outro link esquece a volta"
troca nova-senha.html \
  "    await Dados.pedirNovaSenha(email, VOLTA || undefined);" \
  "    await Dados.pedirNovaSenha(email);" \
  && rodar "a cliente troca a senha e cai no painel"

echo "5. limite de envio vira erro de conexão"
troca nova-senha.html \
  "    if(cod.indexOf('rate_limit') >= 0 || e.status === 429
       || /after \\d+ seconds|rate limit|security purposes/i.test(cru)){" \
  "    if(false){" \
  && rodar "manda conferir o wi-fi quando era só esperar"

echo "6. o link com código é gasto ao abrir"
troca nova-senha.html \
  "      entrada = { hash: q.get('token_hash') };" \
  "      { entrada = { hash: q.get('token_hash') };
        Dados.abrirLinkDeSenha(entrada.hash).then(s => Object.assign(entrada, s)).catch(() => {}); }" \
  && rodar "antivírus ou segundo toque gastam o link"

echo "7. o link com código não é lido"
troca nova-senha.html \
  "    else if(q.get('token_hash') && (q.get('type') || 'recovery') === 'recovery')" \
  "    else if(false)" \
  && rodar "o link novo cai em \"Falta o link\""

echo "8. link gasto no Salvar vira erro genérico"
troca nova-senha.html \
  "    if(venceu(e)) return semLink('vencido');" \
  "" \
  && rodar "a pessoa fica sem saber que precisa de outro link"

echo "9. o código vai ao servidor com o tipo errado"
troca dados.js \
  "      headers: { 'apikey': cfg.chave, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'recovery', token_hash: tokenHash })," \
  "      headers: { 'apikey': cfg.chave, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'signup', token_hash: tokenHash })," \
  && rodar "o código vai com o tipo errado"

echo "10. a cliente vê os textos do painel"
troca nova-senha.html \
  "  a.href = VOLTA; a.textContent = 'Voltar para o salão';" \
  "" \
  && rodar "o caminho de volta é a tela de entrar do painel"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
