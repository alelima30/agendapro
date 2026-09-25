#!/usr/bin/env bash
# ===========================================================================
#  Quebrar o cadastro de produto de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-produto-cadastro.sh
#
#  ⚠ A METADE DA COMISSÃO É A QUE MAIS PRECISA DISTO. O que a `comissao_de()`
#  devolve é CONGELADO dentro do item da comanda pelo gatilho — quer dizer que
#  um erro ali não aparece na tela. Ele aparece no acerto do mês, semanas
#  depois, quando a profissional conferir o que recebeu; e aí já foram dezenas
#  de comandas com a taxa errada gravada.
#
#  Teste verde não prova que ele olha. Cada mutação aqui estraga uma regra e
#  exige que a suíte reprove.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/produto-cadastro.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST="${PGHOST:-/tmp}" PGPORT="${PGPORT:-5444}" PGUSER="${PGUSER:-postgres}"

ARQS="app.html agendar.html supabase/32_produto_cadastro.sql supabase/25_loja.sql"
for a in $ARQS; do cp "$a" "/tmp/mp-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mp-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
# ⚠ MUTAÇÃO DE SQL PRECISA REINSTALAR O MÓDULO. E aqui dá para reinstalar o 32
# sozinho porque ele é o ÚLTIMO a definir tudo o que define — foi conferido:
# nenhum módulo depois dele toca `comissao_de`, `tg_comanda_estoque` ou
# `estoque_historico`. Para qualquer outro módulo, a regra do
# `tests/bancada/subir.sh` vale: remonte do zero.
rodar(){ # $1 = nome, $2 = "sql" quando precisa reinstalar
  bash versao.sh >/dev/null 2>&1
  [ "${2:-}" = sql ] && psql -q -d app -v ON_ERROR_STOP=1 \
      -f supabase/32_produto_cadastro.sql >/dev/null 2>&1
  if node "$T" >/tmp/mp-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mp-saida.txt) reprovações)"
    morta=$((morta+1))
  fi
  restaurar
  [ "${2:-}" = sql ] && psql -q -d app -v ON_ERROR_STOP=1 \
      -f supabase/32_produto_cadastro.sql >/dev/null 2>&1
  return 0
}

troca(){ python3 - "$1" "$2" "$3" <<'PY'
import sys
arq, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(arq, encoding='utf-8').read()
if de not in s:
    print('!! trecho não encontrado em ' + arq); sys.exit(9)
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

echo "1. o degrau novo da comissão some"
troca supabase/32_produto_cadastro.sql \
  "  elsif p_tipo = 'produto' and p_produto is not null and p_profissional is not null then" \
  "  elsif false then" \
  && rodar "escada sem o degrau do par de produto" sql

echo "2. o degrau novo aceita linha que não diz nada"
troca supabase/32_produto_cadastro.sql \
  "     where pp.produto_id = p_produto and pp.profissional_id = p_profissional
       and (pp.comissao_pct is not null or pp.comissao_fixa is not null);" \
  "     where pp.produto_id = p_produto and pp.profissional_id = p_profissional;" \
  && rodar "linha vazia parando a escada" sql

echo "3. a exceção de um produto vale para todos"
troca supabase/32_produto_cadastro.sql \
  "     where pp.produto_id = p_produto and pp.profissional_id = p_profissional
       and (pp.comissao_pct is not null" \
  "     where pp.profissional_id = p_profissional
       and (pp.comissao_pct is not null" \
  && rodar "exceção vazando para os outros produtos" sql

echo "4. a vitrine manda o preço mesmo escondido"
troca supabase/25_loja.sql \
  "               'preco', case when pr.preco_visivel then pr.preco else null end)" \
  "               'preco', pr.preco)" \
  && { psql -q -d app -v ON_ERROR_STOP=1 -f supabase/25_loja.sql >/dev/null 2>&1
       rodar "preço escondido saindo do banco assim mesmo"
       psql -q -d app -v ON_ERROR_STOP=1 -f supabase/25_loja.sql >/dev/null 2>&1; }

echo "5. o histórico registra o mesmo número por cima"
troca supabase/32_produto_cadastro.sql \
  "  if new.estoque is not distinct from old.estoque then
    return null;
  end if;" \
  "  if false then
    return null;
  end if;" \
  && rodar "histórico enchendo de linhas de 8 para 8" sql

echo "6. a venda não se identifica, e vira ajuste"
troca supabase/32_produto_cadastro.sql \
  "  perform set_config('agendapro.mov_motivo',
                     case when v_sinal < 0 then 'venda' else 'devolucao' end, true);" \
  "  perform set_config('agendapro.mov_motivo', '', true);" \
  && rodar "venda sem motivo no histórico" sql

# ⚠ ESTA SOBREVIVE, E NÃO É BURACO NA SUÍTE — é mutação que não dá para
# observar de fora. `set_config(..., true)` já é LOCAL À TRANSAÇÃO: o rótulo
# morre no commit, com ou sem as duas linhas de limpeza. E cada chamada pelo
# PostgREST é uma transação própria, então nenhum teste que fale pela rede
# consegue ver a diferença.
#
# As duas linhas ficam assim mesmo: elas valem para o caso de alguém, um dia,
# fechar uma comanda e mexer no estoque na MESMA transação — de dentro de uma
# função do banco, que é o único jeito de isso acontecer. Custam nada e
# escrevem a intenção.
#
# Fica registrada para ninguém "consertar" a suíte por causa dela.
echo "7. o rótulo de venda gruda na conexão (sobrevive de propósito — ver acima)"
troca supabase/32_produto_cadastro.sql \
  "  perform set_config('agendapro.mov_motivo', '', true);
  perform set_config('agendapro.mov_comanda', '', true);

  return null;" \
  "  return null;" \
  && rodar "rótulo de venda sobrando para o próximo ajuste" sql

echo "8. o histórico abre para quem não é gestão"
troca supabase/32_produto_cadastro.sql \
  "  if not public.e_gestor(v_salao) then
    raise exception 'Sem permissão neste salão.'
      using errcode = 'insufficient_privilege';
  end if;" \
  "  if false then
    raise exception 'x';
  end if;" \
  && rodar "histórico aberto a qualquer conta" sql

echo "9. o interruptor do preço nasce desligado"
troca app.html \
  "             \${!p || p.precoVisivel !== false ? 'checked' : ''}>" \
  "             \${p && p.precoVisivel === true ? 'checked' : ''}>" \
  && rodar "preço nascendo escondido em produto novo"

echo
echo "  $morta morreram, $viva sobreviveram"
[ "$viva" -eq 0 ] || echo "  ⚠ mutação viva é buraco na suíte — ou defeito de projeto"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
