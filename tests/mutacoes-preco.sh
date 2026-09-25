#!/usr/bin/env bash
# ===========================================================================
#  Quebrar o preço avançado de propósito, uma regra por vez.
#
#    bash tests/bancada/subir.sh        (noutro terminal)
#    bash tests/mutacoes-preco.sh
#
#  ⚠ ESTE É O ARQUIVO DE MUTAÇÃO QUE MAIS IMPORTA DO PROJETO, porque é o único
#  em que toda mutação que sobreviver é um jeito de cobrar da cliente um valor
#  diferente do que ela viu.
#
#  Antes deste módulo existiam TRÊS preços para o mesmo atendimento — o que a
#  vitrine mostrava, o que o link cobrava e o que a recepção cobrava — e
#  nenhum teste reprovava. Medido: R$ 40 de diferença, decidido por quem
#  clicou. A escada existe para que exista UMA resposta; estas mutações
#  conferem que a suíte percebe quando ela deixa de ser uma.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/preco.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
export PGHOST="${PGHOST:-/tmp}" PGPORT="${PGPORT:-5444}" PGUSER="${PGUSER:-postgres}"

ARQS="app.html agendar.html supabase/33_preco_regras.sql supabase/25_loja.sql"
for a in $ARQS; do cp "$a" "/tmp/mpr-$(basename "$a")"; done
restaurar(){
  for a in $ARQS; do cp "/tmp/mpr-$(basename "$a")" "$a"; done
  bash versao.sh >/dev/null 2>&1
  psql -q -d app -v ON_ERROR_STOP=1 -f supabase/33_preco_regras.sql >/dev/null 2>&1
  psql -q -d app -v ON_ERROR_STOP=1 -f supabase/25_loja.sql >/dev/null 2>&1
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){ # $1 = nome, $2 = "sql" quando precisa reinstalar
  bash versao.sh >/dev/null 2>&1
  if [ "${2:-}" = sql ]; then
    psql -q -d app -v ON_ERROR_STOP=1 -f supabase/33_preco_regras.sql >/dev/null 2>&1
    psql -q -d app -v ON_ERROR_STOP=1 -f supabase/25_loja.sql >/dev/null 2>&1
  fi
  if node "$T" >/tmp/mpr-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mpr-saida.txt) reprovações)"
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

echo "1. o desempate vira 'o menor preço ganha'"
troca supabase/33_preco_regras.sql \
  "   order by (case when r.profissional_id is not null then 8 else 0 end)" \
  "   order by r.preco asc, (case when r.profissional_id is not null then 8 else 0 end)" \
  && rodar "menor preço ganhando do mais específico" sql

echo "2. a regra com profissional deixa de ganhar das outras"
troca supabase/33_preco_regras.sql \
  "   order by (case when r.profissional_id is not null then 8 else 0 end)
          + (case when r.dias is not null" \
  "   order by (case when r.profissional_id is not null then 0 else 0 end)
          + (case when r.dias is not null" \
  && rodar "profissional sem peso no desempate" sql

echo "3. a faixa de horário fecha os dois lados"
troca supabase/33_preco_regras.sql \
  "     and (r.hora_ini is null or (q.min >= r.hora_ini and q.min < r.hora_fim))" \
  "     and (r.hora_ini is null or (q.min >= r.hora_ini and q.min <= r.hora_fim))" \
  && rodar "meio-dia pertencendo às duas faixas" sql

echo "4. a escada pula o preço do par serviço+profissional"
troca supabase/33_preco_regras.sql \
  "    (select sp.preco from public.servicos_profissionais sp
      where sp.servico_id = p_servico and sp.profissional_id = p_profissional)," \
  "" \
  && rodar "par ignorado, volta o catálogo" sql

echo "5. a vigência deixa de ser olhada"
troca supabase/33_preco_regras.sql \
  "     and (r.de   is null or q.dia >= r.de)" \
  "     and (true or q.dia >= r.de)" \
  && rodar "promoção futura valendo hoje" sql

echo "6. o gatilho reescreve por cima do que a recepção decidiu"
troca supabase/33_preco_regras.sql \
  "  if new.preco is not null then return new; end if;" \
  "" \
  && rodar "cortesia e valor combinado apagados" sql

echo "7. o gatilho some: a recepção volta a gravar o que a tela mandar"
troca supabase/33_preco_regras.sql \
  "create trigger tg_preco_agend_servico
  before insert on public.agendamento_servicos
  for each row execute function public.tg_preco_do_agendamento();" \
  "" \
  && rodar "sem gatilho, a linha nasce sem preço" sql

echo "8. a vitrine esconde o preço por profissional de novo"
# A primeira versão desta mutação produzia SQL inválido: o 25_loja.sql não
# instalava, a função ANTIGA continuava no banco, e o teste passava. Mutação
# que não chega a existir parece buraco na suíte e manda consertar o que não
# está quebrado — foi a segunda vez que isso aconteceu no projeto.
troca supabase/25_loja.sql \
  "               'precoPorProf', (
                 select jsonb_object_agg(sp.profissional_id, sp.preco)
                   from public.servicos_profissionais sp
                   join public.profissionais p2 on p2.id = sp.profissional_id
                  where sp.servico_id = v.id and sp.preco is not null
                    and sp.preco <> v.preco and p2.ativo and p2.aceita_online)," \
  "               'precoPorProf', null," \
  && rodar "cliente vendo um preço e pagando outro" sql

echo "9. as regras da vitrine saem fora de ordem"
troca supabase/25_loja.sql \
  "                        order by (case when r.profissional_id is not null then 8 else 0 end)" \
  "                        order by (case when r.profissional_id is not null then 0 else 0 end)" \
  && rodar "ordem de quem ganha embaralhada" sql

echo "10. o espelho da tela para de olhar a faixa de horário"
troca agendar.html \
  "    if(r.horaIni != null){
      if(minutos == null) continue;
      if(minutos < r.horaIni || minutos >= r.horaFim) continue;
    }" \
  "" \
  && rodar "espelho ignorando o horário"

echo "11. o espelho da tela para de olhar o dia da semana"
troca agendar.html \
  "    if(Array.isArray(r.dias) && r.dias.length && !r.dias.includes(dow)) continue;" \
  "" \
  && rodar "espelho ignorando o dia"

echo "12. o espelho da tela ignora o preço do par"
troca agendar.html \
  "  const base = (profId && sv.precoPorProf && sv.precoPorProf[profId] != null)
    ? Number(sv.precoPorProf[profId])
    : Number(sv.preco);" \
  "  const base = Number(sv.preco);" \
  && rodar "espelho sem o degrau do par"

echo ""
echo "$morta mortas, $viva vivas"
[ "$perdida" -eq 0 ] || echo "  ⚠ $perdida mutação(ões) não rodaram"
[ "$viva" -eq 0 ] && [ "$perdida" -eq 0 ]
