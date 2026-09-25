#!/usr/bin/env bash
# ===========================================================================
#  Quebrar a conta de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-conta.sh
#
#  ⚠ A PRIMEIRA É A QUE PAGA O ARQUIVO. Ela tira a conferência da senha atual,
#  que é exatamente o estado em que o `PUT /user` do Supabase vive por padrão:
#  ele troca a senha só com a sessão aberta, sem perguntar a de antes. Se a
#  suíte não reprovar isso, a tela de senha é um cadeado pintado na porta.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/conta.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST="${PGHOST:-/tmp}" PGPORT="${PGPORT:-5444}" PGUSER="${PGUSER:-postgres}"

ARQS="app.html dados.js"
for a in $ARQS; do cp "$a" "/tmp/mc-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mc-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){ # $1 = nome
  bash versao.sh >/dev/null 2>&1
  if node "$T" >/tmp/mc-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mc-saida.txt) reprovações)"
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
  # ⚠ MUTAÇÃO QUE NÃO RODA NÃO É MUTAÇÃO MORTA. O trecho sumiu ou passou a
  # aparecer duas vezes, e o placar seguia dizendo "N mortas, 0 vivas" com
  # uma a menos. Aconteceu no mutacoes-modulos.sh: a nº 5 ficou sem rodar por
  # sessões inteiras, porque o "!!" passava no meio da saída sem contar.
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. a senha atual deixa de ser conferida pelo servidor"
troca dados.js \
  "    const r = await auth('token?grant_type=password',
                         { email: eu.email, password: atual });
    guardarSessao({ token: r.access_token, refresh: r.refresh_token,
                    usuarioId: (r.user && r.user.id) || eu.id,
                    expiraEm: quandoVence(r) });
    return auth('user', { password: nova }, 'PUT');" \
  "    return auth('user', { password: nova }, 'PUT');" \
  && rodar "troca sem conferir a senha atual"

echo "2. a conferência vira validação de tela (dá para contornar pelo console)"
troca dados.js \
  "    const r = await auth('token?grant_type=password',
                         { email: eu.email, password: atual });" \
  "    if(!atual || atual.length < 8) throw new Error('Senha atual errada.');
    const r = { access_token: (sessao||{}).token, refresh_token: (sessao||{}).refresh,
                user: { id: eu.id } };" \
  && rodar "conferência só na tela"

echo "3. o e-mail vem do perfis, e não do auth.users"
troca dados.js \
  "    const u = await auth('user', null, 'GET');
    return u ? { id: u.id, email: u.email || '', telefone: u.phone || '' } : null;" \
  "    const s = this.sessao() || {};
    const p = await this.lista('perfis', { id: s.usuarioId });
    const u = p[0] || {};
    return { id: u.id, email: '', telefone: u.telefone || '' };" \
  && rodar "e-mail da cópia, não da fonte"

echo "4. a repetição da senha nova deixa de ser conferida"
troca app.html \
  "  if(nova !== nova2){
    recadoDaSenha('', '<b>As duas senhas novas não são iguais.</b> '
      + 'Confira a segunda.');
    return;
  }" \
  "" \
  && rodar "repetição não conferida"

echo "5. some o mínimo de 8 caracteres"
troca app.html \
  "  if(nova.length < 8){
    recadoDaSenha('', '<b>A senha nova precisa de pelo menos 8 caracteres.</b>');
    return;
  }" \
  "" \
  && rodar "senha curta aceita"

echo "6. a senha atual errada vira um erro cru, sem dizer o que fazer"
troca app.html \
  "    if(cod === 'invalid_credentials' || /invalid login/i.test(cru)){
      recado = '<b>A senha atual não confere.</b> Se você não lembra, saia e '
        + 'use \"Esqueci minha senha\" na tela de entrada.';
    } else if(cod === 'same_password'){" \
  "    if(false){
      recado = '';
    } else if(cod === 'same_password'){" \
  && rodar "erro cru na cara da pessoa"

echo "7. a tela fecha calada depois de trocar"
troca app.html \
  "  recadoDaSenha('ok', '<b>Pronto, senha trocada.</b> Você continua conectado '
    + 'aqui. Nos outros aparelhos, entre de novo com a senha nova.');" \
  "  fecharModal();" \
  && rodar "troca sem confirmação na tela"

echo "8. o campo do e-mail vira disabled, e não dá mais para copiar"
troca app.html \
  "        <input id=\"contaEmail\" readonly onclick=\"this.select()\"" \
  "        <input id=\"contaEmail\" disabled onclick=\"this.select()\"" \
  && rodar "e-mail que não dá para copiar"

echo "9. a demonstração passa a prometer troca de senha"
troca app.html \
  "  if(!NA_NUVEM){
    alvo.innerHTML = \`<div class=\"aviso info\" style=\"margin:0\">" \
  "  if(false){
    alvo.innerHTML = \`<div class=\"aviso info\" style=\"margin:0\">" \
  && rodar "cadeado pintado na demonstração"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
