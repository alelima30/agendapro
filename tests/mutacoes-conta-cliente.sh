#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito a conta da cliente no link.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-conta-cliente.sh
#
#  Cada mutação que sobreviver é um jeito de a cliente entrar e o pacote não
#  valer, de os horários dela não aparecerem noutro celular — ou, nas do
#  banco, de uma conta pegar a ficha (e o pacote) de outra pessoa.
#
#  As do banco trocam a função direto na bancada (psql) e devolvem o trecho
#  7 do 09_cliente.sql inteiro ao terminar cada uma.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/conta-cliente.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html agendar.html dados.js"
for a in $ARQS; do cp "$a" "/tmp/mcc-$(basename "$a")"; done
L=$(grep -n '7) A CONTA DA CLIENTE' supabase/09_cliente.sql | cut -d: -f1)
sed -n "$((L-1)),\$p" supabase/09_cliente.sql > /tmp/mcc-sec7.sql
restaurar(){
  for a in $ARQS; do cp "/tmp/mcc-$(basename "$a")" "$a"; done
  $PSQL -f /tmp/mcc-sec7.sql >/dev/null 2>&1 \
    || echo "  !! não consegui devolver o 09_cliente.sql à bancada"
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mcc-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mcc-saida.txt) reprovações)"
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

# A do banco: troca no trecho 7 copiado e aplica na bancada.
trocaSql(){
  cp /tmp/mcc-sec7.sql /tmp/mcc-mutante.sql
  troca /tmp/mcc-mutante.sql "$1" "$2" || return $?
  $PSQL -f /tmp/mcc-mutante.sql >/dev/null 2>&1 \
    || { echo "  ✗ NÃO RODOU — a função mutante não entrou no banco"; perdida=$((perdida+1)); return 9; }
}

echo "1. banco: conta nova toma ficha que já tem dona"
trocaSql "       and c.perfil_id is null
" "" && rodar "a intrusa leva a ficha e o pacote da Maria"

echo "2. banco: liga sem conferir o primeiro nome"
trocaSql "       and public.mesmo_primeiro_nome(c.nome, v_nome)
" "" && rodar "\"Bia\" pega a ficha da \"Beatriz\""

echo "3. banco: compara o telefone como veio"
trocaSql "public.telefone_nacional(c.telefone) = public.telefone_nacional(v_tel)" \
  "public.so_digitos(c.telefone) = public.so_digitos(v_tel)" \
  && rodar "ficha do balcão (sem 55) nunca liga à conta (+55)"

echo "4. banco: horários da conta sem filtrar a conta"
trocaSql "       and c.perfil_id = auth.uid()
" "" && rodar "qualquer conta vê os horários de todo mundo"

echo "5. banco: anon chama as funções da conta"
trocaSql "grant execute on function public.ligar_minha_ficha(uuid)      to authenticated;" \
  "grant execute on function public.ligar_minha_ficha(uuid)      to authenticated, anon;
grant execute on function public.meus_agendamentos_da_conta() to anon;" \
  && rodar "sem login, as funções respondem"

echo "6. a página entra e não liga a ficha"
troca agendar.html \
  "  try{ f = await Dados.chamar('ligar_minha_ficha', { p_salao: salao.id }); }" \
  "  try{ f = null; }" \
  && rodar "logada, e o pacote não vale"

echo "7. entrou, e os pacotes não são buscados de novo"
troca agendar.html \
  "  meusDaNuvem = null;
  await carregarMeusPacotes();
  return f;" \
  "  meusDaNuvem = null;
  return f;" \
  && rodar "Meus pacotes só aparece depois de recarregar"

echo "8. Meus horários não pergunta à conta"
troca agendar.html \
  "        naConta ? Dados.chamar('meus_agendamentos_da_conta', {}) : []," \
  "        []," \
  && rodar "noutro celular, nada aparece"

echo "9. a mesma marcação duas vezes"
troca agendar.html \
  "        if(a && a.token && !porToken.has(a.token)) porToken.set(a.token, a);" \
  "        if(a && a.token) porToken.set(a.token + Math.random(), a);" \
  && rodar "aparelho e conta acham a mesma escova, e ela aparece em dobro"

echo "10. sair não sai da conta"
troca agendar.html \
  "  if(logada()){ try{ await Dados.sair(); }catch(e){} }" \
  "" \
  && rodar "toca em Sair e continua logada"

echo "11. a senha do cadastro é ignorada"
troca agendar.html \
  "    return criarContaNoCadastro(nome, tel, nasc, email, cpf, senha);" \
  "" \
  && rodar "digitou senha e a conta não nasceu"

echo "12. senha errada vira erro genérico"
troca agendar.html \
  "  if(eh('invalid_credentials', /invalid login|invalid_grant|credentials/i))" \
  "  if(false)" \
  && rodar "\"não conferem\" some"

echo "13. a capa não oferece entrar"
troca agendar.html \
  "    atalhos.push([ 'conta', 'usuario', 'Entrar na minha conta'," \
  "    if(0) atalhos.push([ 'conta', 'usuario', 'Entrar na minha conta'," \
  && rodar "sem porta de entrada na capa"

echo "14. esqueci a senha volta para o painel"
troca agendar.html \
  "    await Dados.pedirNovaSenha(email, 'agendar.html?salao=' + salao.slug);" \
  "    await Dados.pedirNovaSenha(email);" \
  && rodar "a cliente troca a senha e cai no painel do dono"

echo "15. a volta do e-mail aceita a de recuperação"
troca agendar.html \
  "    if(NA_NUVEM && h.get('access_token') && h.get('type') !== 'recovery')" \
  "    if(NA_NUVEM && h.get('access_token'))" \
  && rodar "o link de senha nova vira login"

echo "16. a volta do e-mail não guarda o token"
troca agendar.html \
  "      Dados.entrarComToken({ token: h.get('access_token'), refresh: h.get('refresh_token') });" \
  "      void 0;" \
  && rodar "confirmou o e-mail e continua de fora"

echo "17. o cadastro de conta perde o caminho de volta"
troca dados.js \
  "auth('signup' + (volta ? '?redirect_to=' + encodeURIComponent(volta) : '')" \
  "auth('signup'" \
  && rodar "o e-mail de confirmação manda para a raiz do site"

echo "18. o painel troca com conta e sem conta"
troca app.html \
  "\${c.perfilId
                ? '<span class=\"tag t-ok\">com conta</span>'" \
  "\${!c.perfilId
                ? '<span class=\"tag t-ok\">com conta</span>'" \
  && rodar "o dono vê o contrário"

echo "19. WhatsApp de outra conta, e a tela calada"
troca agendar.html \
  "  if(f && typeof f === 'object' && !f.telefone && !f.ficha){" \
  "  if(false){" \
  && rodar "a conta nasce sem ficha, e a cliente acha que o pacote sumiu"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
