#!/usr/bin/env bash
# ===========================================================================
#  Desfazer de propósito cada conserto do caça-bug — o teste tem de reprovar.
#
#    bash tests/bancada/subir.sh                       (noutro terminal)
#    python3 -m http.server 8099 --directory .         (noutro terminal)
#    bash tests/mutacoes-caca-bug.sh
#
#  Os defeitos de banco têm o tests/caca_bug.test.sql; aqui é a tela
#  (tests/caca-bug.test.mjs). A do banco muda o .sql, aplica na bancada e
#  devolve o original — no arquivo e no banco — ao terminar.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/caca-bug.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html agendar.html supabase/34_cupons.sql supabase/09_cliente.sql"
SQLS="supabase/34_cupons.sql supabase/09_cliente.sql"
guarda(){ echo "/tmp/mcb-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
aplicar(){ for f in $SQLS; do $PSQL -f "$f" >/dev/null 2>&1 || return 1; done; }
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  aplicar || echo "  !! não consegui devolver o SQL original à bancada"
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  bash versao.sh >/dev/null 2>&1
  if ! aplicar; then
    echo "  ✗ NÃO RODOU — o SQL mutante não entrou no banco ($1)"; perdida=$((perdida+1))
    restaurar; return 0
  fi
  if node "$T" >/tmp/mcb-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mcb-saida.txt) reprovações)"
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
  [ $r -eq 0 ] || { echo "  ✗ NÃO RODOU — conserte o trecho procurado"; perdida=$((perdida+1)); }
  return $r
}

echo "1. link: a capa vai crua para dentro do url()"
troca agendar.html \
  "style=\"background-image:url('\${urlNoCss(salao.capa)}');--foco:\${" \
  "style=\"background-image:url('\${salao.capa}');--foco:\${" \
  && rodar "a capa roda código"

echo "2. link: salão que não existe mostra a demonstração"
troca agendar.html \
  "  if(passo) passo.classList.add('so-recado');" \
  "  if(passo) passo.classList.add('x');" \
  && rodar "o texto da demonstração aparece"

echo "3. link: o +55 vira DDD"
troca agendar.html \
  "  if(v.length >= 12 && v.startsWith('55')) v = v.slice(2);
  v = v.slice(0,11);" \
  "  v = v.slice(0,11);" \
  && rodar "(55) 51999-9988"

echo "4. link: dia fechado vira cheio"
troca agendar.html \
  "  return !!func && !Funcionamento.periodosDoDia(func, diaDaSemana(data));" \
  "  return false;" \
  && rodar "domingo cheio com lista de espera"

echo "5. link: eu e mais alguém cobra um só"
troca agendar.html \
  "  const precoOutra = ambos ? precoNoHorario(escolha.inicio + duracaoEscolhida()) : 0;" \
  "  const precoOutra = 0;" \
  && rodar "o total é de uma pessoa"

echo "6. link: a marca da remarcação fica para a próxima marcação"
troca agendar.html \
  "    delete escolha.remarcar; delete escolha.descontoAntigo; delete escolha.remarcarLocal;" \
  "    ;" \
  && rodar "desistir de remarcar cancela outro horário"

echo "7. link: remarcar só cancela (o cupom fica para trás)"
troca agendar.html \
  "        await Dados.chamar('remarcar_agendamento', { p_token_antigo: velho, p_token_novo: novoToken });" \
  "        await Dados.chamar('cancelar_agendamento', { p_token: velho });" \
  && rodar "o desconto some na remarcação"

echo "8. banco: remarcar não leva o desconto"
troca supabase/34_cupons.sql \
  "      if v_desc > 0 then
        update public.agendamentos" \
  "      if false then
        update public.agendamentos" \
  && rodar "a tela promete e o banco cobra cheio"

echo "9. link: sair deixa o cadastro na tela"
troca agendar.html \
  "    if(el && 'value' in el) el.value = '';" \
  "    ;" \
  && rodar "a próxima pessoa marca no telefone da anterior"

echo "10. loja: a busca exige acento"
troca agendar.html \
  "      || plano(p.nome).includes(busca)" \
  "      || String(p.nome).toLowerCase().includes(busca)" \
  && rodar "mascara não acha Máscara"

echo "11. loja: reenviar o pedido corrigido gasta outro uso"
troca agendar.html \
  "  return !!(cupomLoja && (cupomLoja.usado || cupomLoja.chave === chaveDoCupomLoja()));" \
  "  return !!(cupomLoja && cupomLoja.chave === chaveDoCupomLoja());" \
  && rodar "o limite da loja chega duas vezes mais rápido"

echo "12. painel: Hoje volta à lista simples"
troca app.html \
  "       <div class=\"dia-lista\">\${aindaVem.map(cartaoDoDia).join('')}</div>\`" \
  "       <div>\${aindaVem.map(a => a.id).join('')}</div>\`" \
  && rodar "Hoje diferente do mês"

echo "13. painel: Dashboard de outro salão"
troca app.html \
  "  if(dashDados && dashSalao === salaoAtual && !forcar) return desenharDash();" \
  "  if(dashDados && !forcar) return desenharDash();" \
  && rodar "os números de uma unidade na outra"

echo "14. painel: as gravações correm juntas"
troca app.html \
  "    const tarefa = _filaGravacao.then(() => {" \
  "    const tarefa = Promise.resolve().then(() => {" \
  && rodar "item tirado da comanda volta no banco"

echo "15. painel: regra de preço com o id() escondido"
troca app.html \
  "function salvarRegraDePreco(servicoId, regraId){" \
  "function salvarRegraDePreco(servicoId, regraId, id){" \
  && rodar "+ Nova regra de preço não grava"

echo "16. painel: editar o serviço apaga quem está inativa"
troca app.html \
  "    .filter(x => x.servicoId !== servicoId || !naTela.has(x.profissionalId));" \
  "    .filter(x => x.servicoId !== servicoId);" \
  && rodar "preço especial de quem está de férias some"

echo "17. painel: serviço desativado some do cupom"
troca app.html \
  "  return doSalao(bd.servicos).filter(s => s.ativo || ja.has(s.id));" \
  "  return doSalao(bd.servicos).filter(s => s.ativo);" \
  && rodar "o cupom vira de todos os serviços"

echo "18. painel: pacote conta pelo dia aberto na agenda"
troca app.html \
  "    const vivas = vendas.filter(v => v.venceEm >= hoje());" \
  "    const vivas = vendas.filter(v => v.venceEm >= diaAtual);" \
  && rodar "contagem muda ao andar na agenda"

echo "19. painel: busca de cliente exige acento"
troca app.html \
  "    !busca || semAcento(c.nome).includes(busca)
    || (buscaDig.length >= 3" \
  "    !busca || c.nome.toLowerCase().includes(busca)
    || (false" \
  && rodar "jose não acha José"

echo "20. painel: bloqueio não sai"
troca app.html \
  "  bd.bloqueios = bd.bloqueios.filter(x => x.id !== bid);
  salvar(); fecharModal(); pintar();" \
  "  salvar(); fecharModal(); pintar();" \
  && rodar "bloqueio digitado errado fica para sempre"

echo "21. painel: a profissional vê a equipe toda no + Agendamento"
troca app.html \
  "  const so = vejoTudo() ? null : minhaFichaDeProf();
  const profs = so ? [so] : profsAtivos(), servs = servsAtivos(), clis = clientesDo();" \
  "  const so = null;
  const profs = so ? [so] : profsAtivos(), servs = servsAtivos(), clis = clientesDo();" \
  && rodar "marcar para a colega termina em erro"

echo "22. painel: a recepção vê a comissão das colegas"
troca app.html \
  "  if(!souGestor()){ alvoC.innerHTML = ''; return; }" \
  "  if(false){ alvoC.innerHTML = ''; return; }" \
  && rodar "comissão das colegas no Caixa"

echo "23. painel: a comanda entra no dia em que abriu"
troca app.html \
  "  if(comandaFechada(c) && c.fechadaEm){" \
  "  if(false){" \
  && rodar "o dinheiro de hoje cai em ontem"

echo "24. painel: o link da demonstração vai para a nuvem"
troca app.html \
  "function sufixoDemo(){ return NA_NUVEM ? '' : '&demo=1'; }" \
  "function sufixoDemo(){ return ''; }" \
  && rodar "Salão não encontrado na demonstração"

echo "25. painel: o passo a passo não preenche o funcionamento"
troca app.html \
  "    if(F.normalizar(func)) sl.cfg = Object.assign({}, sl.cfg, { funcionamento: func });" \
  "    ;" \
  && rodar "horário de funcionamento vazio depois do assistente"

echo "26. painel: sessão de pacote sai com o preço cheio"
troca app.html \
  "  if(ag.pacoteClienteId) return 0;" \
  "  ;" \
  && rodar "a agenda cobra o que o pacote já pagou"

echo "27. banco: o pacote cobre a acompanhante"
troca supabase/09_cliente.sql \
  "  if v_perfil is not null and not coalesce(p_acompanhante, false) and exists (" \
  "  if v_perfil is not null and exists (" \
  && rodar "a acompanhante é atendida de graça"

echo "28. link: o segundo horário não diz que é da acompanhante"
troca agendar.html \
  "        await marcar(segundoIso, filho || null, false, true);" \
  "        await marcar(segundoIso, filho || null, false, false);" \
  && rodar "o banco gasta duas sessões"

echo "29. link: o total de eu e mais alguém com pacote volta a R\$ 0"
troca agendar.html \
  "  const total = real((coberto ? 0 : precoDela) + precoOutra - desc);" \
  "  const total = coberto ? 'R\$ 0,00' : real(precoDela + precoOutra - desc);" \
  && rodar "a tela promete de graça e o salão cobra"

echo "30. banco: cupom na loja sem conta"
troca supabase/34_cupons.sql \
  "  if v_uid is null then
    return jsonb_build_object('ok', false, 'entrar', true," \
  "  if false then
    return jsonb_build_object('ok', false, 'entrar', true," \
  && rodar "qualquer um gasta o cupom por fora"

echo "31. banco: a mesma conta gasta um uso a cada chamada"
troca supabase/34_cupons.sql \
  "  if found then
    return jsonb_build_object('ok', true, 'motivo', null, 'codigo', c.codigo," \
  "  if false then
    return jsonb_build_object('ok', true, 'motivo', null, 'codigo', c.codigo," \
  && rodar "chamar em repetição esgota o cupom"

echo "32. link: a caixa do cupom da loja mostra o campo sem conta"
troca agendar.html \
  "  if(!logada()){
    return \`<details" \
  "  if(false){
    return \`<details" \
  && rodar "a cliente digita e só descobre a recusa no fim"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
