#!/usr/bin/env bash
# ===========================================================================
#  Quebrar os dois módulos de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-modulos.sh
#
#  Teste verde não prova nada sozinho: prova que o código passa, não que o
#  teste OLHA. Cada mutação aqui estraga uma regra e exige que o
#  `modulos.test.mjs` reprove.
#
#  ⚠ AS PRIMEIRAS TRÊS SÃO DO BANCO, e são as que valem mais. Defeito de tela
#  o dono vê no mesmo dia; defeito na `vitrine()` chega calado — a lista sai
#  na resposta de uma casa que desligou o módulo, ou a função inteira levanta
#  e a página da cliente some sem ninguém saber por quê.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/modulos.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST="${PGHOST:-/tmp}" PGPORT="${PGPORT:-5444}" PGUSER="${PGUSER:-postgres}"

ARQS="app.html agendar.html supabase/25_loja.sql"
for a in $ARQS; do cp "$a" "/tmp/mm-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mm-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
# ⚠ MUTAÇÃO DE SQL PRECISA REINSTALAR O MÓDULO. Dá para reinstalar o 25
# sozinho porque ele é o ÚLTIMO a definir a `vitrine()` — é o que o
# `sintaxe.test.js` confere e cobra. Para qualquer outro módulo vale a regra
# do `tests/bancada/subir.sh`: remonte do zero.
rodar(){ # $1 = nome, $2 = "sql" quando precisa reinstalar
  bash versao.sh >/dev/null 2>&1
  [ "${2:-}" = sql ] && psql -q -d app -v ON_ERROR_STOP=1 \
      -f supabase/25_loja.sql >/dev/null 2>&1
  if node "$T" >/tmp/mm-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mm-saida.txt) reprovações)"
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
  local r=$?
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA. O trecho sumiu ou passou a
  # aparecer duas vezes, e o placar seguia dizendo "N mortas, 0 vivas" com
  # uma a menos. Aconteceu no mutacoes-modulos.sh: a nº 5 ficou sem rodar por
  # sessões inteiras, porque o "!!" passava no meio da saída sem contar.
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. a peneira volta a ser ::boolean, e lixo no cfg derruba a vitrine"
troca supabase/25_loja.sql \
  "      'loja', lower(btrim(coalesce(s.cfg->>'loja', 'true')))
                not in ('false', 'f', '0', 'no', 'nao', 'não')," \
  "      'loja', coalesce((s.cfg->>'loja')::boolean, true)," \
  && rodar "cfg lido com ::boolean" sql

echo "2. o banco deixa a lista de serviços sair com o módulo desligado"
troca supabase/25_loja.sql \
  "         and lower(btrim(coalesce(s.cfg->>'usaServicos', 'true')))
               not in ('false', 'f', '0', 'no', 'nao', 'não')), '[]'::jsonb)," \
  "         ), '[]'::jsonb)," \
  && rodar "lista saindo com o módulo desligado" sql

echo "3. chave ausente passa a valer DESLIGADO"
troca supabase/25_loja.sql \
  "      'usaServicos', lower(btrim(coalesce(s.cfg->>'usaServicos', 'true')))" \
  "      'usaServicos', lower(btrim(coalesce(s.cfg->>'usaServicos', 'false')))" \
  && rodar "ausente valendo desligado" sql

# ⚠ ESTAS DUAS JÁ SOBREVIVERAM UMA VEZ, e a lição virou outra coisa.
#
# Elas estragam a cópia de `usaServicos` e `loja` no `bdDaVitrine()`. Na
# primeira rodada a tela saía igual com a chave certa, errada ou ausente — e
# eu concluí que as linhas eram inúteis e as apaguei.
#
# Estavam mesmo inúteis enquanto o rodapé olhava a LISTA. Só que "lista vazia"
# tem duas causas — módulo desligado, ou salão que acabou de nascer — e tratar
# as duas igual tirou o botão de entrada de todo salão na primeira hora. Quem
# mostrou foi o `cliente-nuvem.test.mjs`.
#
# Agora o rodapé pergunta pelo MÓDULO, as duas linhas voltaram, e as mutações
# morrem. A lição não é "mutação viva pede teste novo" nem "pede código a
# menos": é que mutação viva quer dizer que ninguém ainda sabe para que aquela
# linha serve.

echo "4. o bdDaVitrine() esquece de copiar os serviços"
troca agendar.html \
  "      usaServicos: s.usaServicos !== false," \
  "      usaServicos: true," \
  && rodar "módulo não atravessa a ponte"

# ⚠ E AQUI NÃO HÁ MUTAÇÃO 5, de propósito.
#
# A gêmea desta de cima seria estragar a cópia do `loja`. Ela SOBREVIVE, e não
# é buraco na suíte: na nuvem nada lê `salao.loja`. O rodapé pergunta pelo
# módulo dos SERVIÇOS (é lá que "vazio" é ambíguo) e, do lado dos produtos,
# pergunta pela lista — que a `vitrine()` já esvaziou quando a loja está
# desligada. Não existe tela capaz de notar a diferença.
#
# A linha fica assim mesmo. O `moduloLigado()` lê as duas chaves do mesmo
# jeito, e tirar uma faria a próxima pessoa que precisar do estado da loja na
# nuvem cair exatamente no buraco em que eu caí com os serviços: a chave não
# está lá, ninguém repara, e o comportamento erra calado.
#
# Mutação viva vale registro; nem toda mutação viva vale conserto.

echo "5. o rodapé volta a olhar a lista, e não o módulo"
# Com a linha de antes: o mesmo "if(casaFazServicos()){" existe também no
# rodapé dos pacotes, e sem ela o trecho aparecia duas vezes e a mutação
# simplesmente não rodava.
troca agendar.html \
  "                               trilhaAte(0);
                               if(casaFazServicos()){
                                 bp.textContent = voc('acao');" \
  "                               trilhaAte(0);
                               if(servicosDoSalao().length){
                                 bp.textContent = voc('acao');" \
  && rodar "rodapé olhando a lista"

echo "6. produtosDaLoja() deixa de olhar o módulo"
troca agendar.html \
  "const produtosDaLoja = () => (!salao || !casaVendeProdutos() ? []" \
  "const produtosDaLoja = () => (!salao ? []" \
  && rodar "consulta sem a peneira"

echo "7. o rodapé volta a apontar sempre para serviços"
troca agendar.html \
  "  if(tela === 'capa'){
    if(casaFazServicos()) return irPara('servico');
    if(produtosDaLoja().length && zapDoSalao()) return irPara('loja');
    return;
  }" \
  "  if(tela === 'capa')      return irPara('servico');" \
  && rodar "botão do pé com destino fixo"

echo "8. o cartão promete produtos a quem não vende produto"
troca agendar.html \
  "    : (temSv)          ? 'Escolha o serviço e agende seu horário em poucos toques.'" \
  "    : (temSv)          ? 'Escolha o serviço, agende seu horário ou confira nossos produtos.'" \
  && rodar "convite prometendo o que não existe"

echo "9. o salvar usa || e desligar a loja não gruda"
troca app.html \
  "    loja:        modLojaEscolhida    ?? true," \
  "    loja:        modLojaEscolhida    || true," \
  && rodar "|| no salvar, o Não vira Sim"

echo "10. a régua nasce em Sim, ignorando o que está gravado"
troca app.html \
  "    modLojaEscolhida    = usaLojaNoLink();" \
  "    modLojaEscolhida    = true;" \
  && rodar "régua sem ler o banco"

echo "11. a equipe volta a aparecer sem agendamento"
troca agendar.html \
  "const profsDoSalao = () => !casaFazServicos() ? [] : bd.profissionais.filter(p =>" \
  "const profsDoSalao = () => bd.profissionais.filter(p =>" \
  && rodar "Quem atende numa casa sem agenda"

echo "12. o rótulo 'Quem atende' fica mesmo sem ninguém embaixo"
troca agendar.html \
  "  rotEq.style.display = equipe.length ? '' : 'none';" \
  "  rotEq.style.display = '';" \
  && rodar "título em cima de nada"

echo "13. o atalho Meus horários volta sem agendamento"
troca agendar.html \
  "  if(sessao && casaFazServicos()){
    atalhos.push([ 'meus', 'calendario', 'Meus horários'," \
  "  if(sessao){
    atalhos.push([ 'meus', 'calendario', 'Meus horários'," \
  && rodar "atalho para a agenda desligada"

echo "14. o botão com o nome volta sem agendamento"
troca agendar.html \
  "  if(sessao && tela !== 'meus' && casaFazServicos()){" \
  "  if(sessao && tela !== 'meus'){" \
  && rodar "o nome dela levando à agenda desligada"

echo "15. a prévia ignora o módulo de serviços"
troca app.html \
  "  const comServicos = usaServicosNoLink(sl);" \
  "  const comServicos = true;" \
  && rodar "prévia com serviços que o link não tem"

echo "16. a prévia mantém o botão de agendar sem agendamento"
troca app.html \
  "  if(comServicos) botoes.push(['agendar', 'Agendar horário']);" \
  "  botoes.push(['agendar', 'Agendar horário']);" \
  && rodar "botão de agendar na prévia de uma loja"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
