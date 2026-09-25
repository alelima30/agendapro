#!/usr/bin/env bash
# ===========================================================================
# AgendaPro — roda TUDO, de uma vez
#
#   bash tests/tudo.sh
#
# ── POR QUE ISTO EXISTE ────────────────────────────────────────────────────
# Antes eram nove comandos diferentes, um por suíte, e cinco deles pediam uma
# variável `PLAYWRIGHT=` cujo valor certo não estava escrito em lugar nenhum —
# o cabeçalho dos arquivos diz `.../node_modules/playwright`, que é reticência,
# não caminho.
#
# Com o caminho errado o Node não avisa que a suíte não rodou: ele cospe um
# rastro de pilha e sai. Rodando as suítes em sequência e batendo o olho, o que
# se vê é uma tela sem nenhum ✗ — que é exatamente a cara de tudo passando.
# Aconteceu comigo: cinco suítes não rodaram e o placar parecia limpo.
#
# Então aqui a regra é outra: quem não roda REPROVA, com o mesmo peso de quem
# falha. Suíte que não rodou não é suíte verde; é suíte sem notícia.
# ===========================================================================
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$AQUI")"
cd "$RAIZ"

# ── Achar o Playwright sozinho ─────────────────────────────────────────────
# Pedir o caminho para quem roda o teste é transferir para a pessoa um problema
# que o script resolve em três tentativas.
if [ -z "${PLAYWRIGHT:-}" ]; then
  for tentativa in \
    "$AQUI/bancada/node_modules/playwright" \
    "$RAIZ/node_modules/playwright" \
    "$(npm root -g 2>/dev/null)/playwright"
  do
    [ -d "$tentativa" ] && { PLAYWRIGHT="$tentativa"; break; }
  done
fi
if [ -z "${PLAYWRIGHT:-}" ]; then
  echo "✗ Não achei o Playwright. Instale com 'npm i -g playwright' ou aponte:"
  echo "    PLAYWRIGHT=/caminho/para/node_modules/playwright bash tests/tudo.sh"
  exit 1
fi
export PLAYWRIGHT

# ── Onde está o Chromium ───────────────────────────────────────────────────
# Nesta máquina de desenvolvimento ele mora em /opt/pw-browsers/chromium. No
# CI, quem sabe o caminho é o próprio Playwright, e apontar para /opt lá faria
# TODAS as suítes de navegador falharem com "executable doesn't exist" — um
# erro sobre caminho, que ninguém lê como "estou na outra máquina".
if [ -z "${CHROMIUM:-}" ] && [ -x /opt/pw-browsers/chromium ]; then
  CHROMIUM=/opt/pw-browsers/chromium
fi
if [ -z "${CHROMIUM:-}" ] || [ ! -x "$CHROMIUM" ]; then
  CHROMIUM="$(node -e "console.log(require('$PLAYWRIGHT').chromium.executablePath())" 2>/dev/null || true)"
fi
if [ -z "${CHROMIUM:-}" ] || [ ! -x "$CHROMIUM" ]; then
  echo "✗ Não achei o Chromium. Instale com 'npx playwright install chromium'"
  echo "  ou aponte:  CHROMIUM=/caminho/para/chromium bash tests/tudo.sh"
  exit 1
fi
export CHROMIUM

ESTATICO="${ESTATICO:-http://127.0.0.1:8099}"
BANCADA="${BANCADA:-http://127.0.0.1:8123}"
export BASE="${BASE:-$ESTATICO/}"
export BANCADA

no_ar() { curl -s -o /dev/null --max-time 2 "$1" 2>/dev/null; }

echo "▸ Playwright: $PLAYWRIGHT"
no_ar "$ESTATICO/criar.html" \
  || { echo "✗ Nada servindo em $ESTATICO — rode:  python3 -m http.server 8099 --directory ."; exit 1; }
no_ar "$BANCADA/" \
  || { echo "✗ A bancada não está de pé em $BANCADA — rode:  bash tests/bancada/subir.sh"; exit 1; }

falhou=0
reprovadas=()
quantas=0

rodar() {
  local nome="$1"; shift
  quantas=$((quantas + 1))
  echo ""
  echo "▸ $nome"
  local saida
  saida="$("$@" 2>&1)"
  local codigo=$?
  # Só as duas últimas linhas: o placar. O detalhe fica para quem reprova.
  echo "$saida" | tail -2
  if [ $codigo -ne 0 ]; then
    # Se saiu por erro sem ter falhado teste — módulo faltando, bancada caída —
    # o rastro inteiro importa, porque ninguém adivinha isso pelo placar.
    echo "$saida" | grep -q "falharam" || { echo "   ── não chegou a rodar ──"; echo "$saida" | tail -12; }

    # ⚠ AS LINHAS QUE REPROVARAM, AQUI MESMO, E O RASTRO INTEIRO NUM ARQUIVO.
    #
    # Antes saía só o placar — "✗ 2 de 73 verificações falharam" — e o resto
    # era descartado. Para uma suíte que reprova SEMPRE, tudo bem: roda de novo
    # sozinha e o detalhe aparece.
    #
    # Para uma que reprova SÓ NO CONJUNTO, não: rodar sozinha dá verde, e a
    # única chance de saber o que houve foi jogada fora. Aconteceu comigo, e me
    # custou várias rodadas de bisseção às cegas atrás de duas linhas que o
    # corredor tinha na mão e apagou.
    #
    # Falha intermitente é justamente a que mais precisa do detalhe, e a que
    # menos chance tem de ser reproduzida sob demanda.
    echo "$saida" | grep -E '^[[:space:]]*✗' | head -12 | sed 's/^/   /'
    local arq="${TMPDIR:-/tmp}/agendapro-reprovou-$(echo "$nome" | tr -c 'a-zA-Z0-9' '-').txt"
    printf '%s\n' "$saida" > "$arq"
    echo "   ── saída inteira em $arq ──"

    falhou=1; reprovadas+=("$nome")
  fi
}

# Primeiro de todos, e de propósito: erro de sintaxe derruba a tela inteira,
# e sem esta linha ele aparecia de raspão noutra suíte, apontando outro
# arquivo. Custa menos de um segundo.
rodar "sintaxe"           node "$AQUI/sintaxe.test.js"
rodar "banco (SQL)"        bash "$AQUI/rodar.sh"
# Logo depois do banco, e de propósito: o `rodar.sh` instala tudo do zero
# antes de cada arquivo, e por isso é CEGO para o que só quebra em quem
# atualiza. Este confere que os dois caminhos terminam no mesmo banco.
rodar "atualizar o banco"  bash "$AQUI/atualizar.test.sh"
rodar "colunas"            node "$AQUI/colunas.test.js"
rodar "nuvem"              node "$AQUI/nuvem.test.mjs"
rodar "cota"               node "$AQUI/cota.test.mjs"
# A tela do produto passando pelo dados.js de verdade. O produtos.test.sql
# cobre o módulo, mas insere como superusuário, com os valores à mão — e
# foi na TRADUÇÃO da tela para colunas que o cadastro quebrou.
rodar "produto grava"      node "$AQUI/produto-grava.test.mjs"
rodar "funil na nuvem"     node "$AQUI/funil-nuvem.test.mjs"
rodar "link da cliente"    node "$AQUI/cliente-nuvem.test.mjs"
rodar "senha"              node "$AQUI/senha.test.mjs"
rodar "cadastro"           node "$AQUI/cadastro.test.mjs"
rodar "abertura"           node "$AQUI/abertura.test.mjs"
rodar "celular"            node "$AQUI/celular.test.mjs"
rodar "imagens"            node "$AQUI/imagens.test.mjs"
rodar "plataforma"         node "$AQUI/plataforma.test.mjs"
rodar "aparência"          node "$AQUI/aparencia.test.mjs"
rodar "segurança"          node "$AQUI/seguranca.test.mjs"
rodar "segredos"           node "$AQUI/segredos.test.js"
rodar "instalar"           node "$AQUI/instalar.test.mjs"
rodar "auditoria"          node "$AQUI/auditoria.test.mjs"
rodar "fluxo"              node "$AQUI/fluxo-auditoria.test.mjs"
rodar "sincronia"          node "$AQUI/sincronia.test.mjs"
rodar "whatsapp"           node "$AQUI/whatsapp.test.mjs"
rodar "varredura"          node "$AQUI/varredura.test.mjs"
rodar "grade"              node "$AQUI/grade.test.mjs"
rodar "ficha repetida"     node "$AQUI/ficha-repetida.test.mjs"
rodar "semana"             node "$AQUI/semana.test.mjs"
rodar "arquivar"           node "$AQUI/arquivar.test.mjs"
rodar "confere grade"      node "$AQUI/confere-grade.test.mjs"
rodar "cartão legível"     node "$AQUI/cartao-legivel.test.mjs"
rodar "abas do salão"      node "$AQUI/abas-salao.test.mjs"
rodar "convite da equipe"  node "$AQUI/convite.test.mjs"
rodar "papéis no painel"   node "$AQUI/papeis.test.mjs"
rodar "relatórios"         node "$AQUI/relatorios.test.mjs"
rodar "assinatura do webhook" node "$AQUI/webhook-assinatura.test.js"
rodar "status do WhatsApp"  node "$AQUI/status-whatsapp.test.js"
rodar "checkout"           node "$AQUI/cobranca.test.mjs"
rodar "motor da agenda"    node "$AQUI/motor.test.mjs"
rodar "teto do link"       node "$AQUI/teto-online.test.mjs"
rodar "fila de espera"     node "$AQUI/fila-espera.test.mjs"
rodar "corrida da agenda"  node "$AQUI/corrida.test.mjs"
rodar "fecho de dia"       node "$AQUI/fecho-dia.test.mjs"
rodar "notificações"       node "$AQUI/notificacoes.test.mjs"
rodar "notificações na tela" node "$AQUI/notif-tela.test.mjs"
rodar "banco atrasado"     node "$AQUI/banco-atrasado.test.mjs"
rodar "escada da comissão" node "$AQUI/comissao.test.mjs"
rodar "caixa na tela"     node "$AQUI/caixa-tela.test.mjs"
rodar "cartões na foto"   node "$AQUI/cartoes.test.mjs"
rodar "moldura do cartão" node "$AQUI/moldura.test.mjs"
rodar "oferta de plano"   node "$AQUI/oferta-plano.test.mjs"
rodar "carrinho da loja"  node "$AQUI/carrinho.test.mjs"
rodar "antecedência"      node "$AQUI/antecedencia.test.mjs"
rodar "pacotes"          node "$AQUI/pacotes.test.mjs"
rodar "pacotes na tela"  node "$AQUI/pacotes-tela.test.mjs"
rodar "sem comanda"          node "$AQUI/sem-comanda.test.mjs"
rodar "sem comanda na tela"  node "$AQUI/sem-comanda-tela.test.mjs"
rodar "confirmação"          node "$AQUI/confirmacao.test.mjs"
rodar "confirmação na tela"  node "$AQUI/confirmacao-tela.test.mjs"
rodar "agenda do mês"        node "$AQUI/mes.test.mjs"
rodar "QR"                   node "$AQUI/qr.test.js"
rodar "QR na tela"           node "$AQUI/qr-tela.test.mjs"
rodar "o primeiro dia"       node "$AQUI/primeiro-dia.test.mjs"
rodar "cadastro da cliente"  node "$AQUI/cadastro-cliente.test.mjs"
rodar "capa da cliente"      node "$AQUI/capa-servicos.test.mjs"
rodar "destaques da capa"    node "$AQUI/capa-destaques.test.mjs"
rodar "sair da equipe"       node "$AQUI/equipe-sair.test.mjs"
rodar "dashboard"            node "$AQUI/dashboard.test.mjs"
rodar "ajustes do salão"     node "$AQUI/salao-ajustes.test.mjs"
rodar "identidade visual"    node "$AQUI/identidade-visual.test.mjs"
rodar "dias por serviço"     node "$AQUI/dias-servico.test.mjs"
rodar "cadastro de produto" node "$AQUI/produto-cadastro.test.mjs"
rodar "visual da capa"       node "$AQUI/capa-visual.test.mjs"
rodar "os dois módulos"      node "$AQUI/modulos.test.mjs"
rodar "a fita do carrinho"   node "$AQUI/fita.test.mjs"
rodar "sua conta"            node "$AQUI/conta.test.mjs"
rodar "todas as telas"       node "$AQUI/telas.test.mjs"
rodar "preço avançado"       node "$AQUI/preco.test.mjs"
rodar "aviso da loja"         node "$AQUI/loja-aviso.test.mjs"
rodar "fundo da página"       node "$AQUI/fundo.test.mjs"

echo ""
if [ "$falhou" -eq 0 ]; then
  # Contado, não escrito à mão. O número escrito envelhece: ficou em "35"
  # enquanto duas suítes novas entravam, e "✓ Tudo passou — as 35 suítes"
  # continuava saindo, verdadeiro e desatualizado ao mesmo tempo. É o mesmo
  # defeito do carimbo de versão, no lugar onde ele custa mais caro: o
  # placar da suíte é o que se olha antes de publicar.
  echo "✓ Tudo passou — as $quantas suítes."
else
  echo "✗ Reprovaram: ${reprovadas[*]}"
  echo "  Nada deve ser publicado assim."
  exit 1
fi
