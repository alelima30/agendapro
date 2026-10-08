#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o cupom de desconto.
#
#    bash tests/bancada/subir.sh                       (noutro terminal)
#    python3 -m http.server 8099 --directory .         (noutro terminal)
#    bash tests/mutacoes-cupons.sh
#
#  As do banco mudam o próprio arquivo .sql (para o sintaxe.test.js conferir
#  que o trecho ainda existe), aplicam na bancada com psql e devolvem o
#  original — no arquivo e no banco — ao terminar cada uma.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/cupons.test.mjs
export PLAYWRIGHT=${PLAYWRIGHT:-/opt/node22/lib/node_modules/playwright}
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="app.html agendar.html dados.js estilo.css supabase/34_cupons.sql supabase/09_cliente.sql supabase/28_sem_comanda.sql"
SQLS="supabase/34_cupons.sql supabase/09_cliente.sql supabase/28_sem_comanda.sql"
guarda(){ echo "/tmp/mcp-$(echo "$1" | tr '/' '_')"; }
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
  if node "$T" >/tmp/mcp-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mcp-saida.txt) reprovações)"
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

echo "1. banco: a porcentagem vira o preço inteiro"
troca supabase/34_cupons.sql \
  "  end if;

  v_desc := case when c.tipo = 'pct' then round(v_base * c.valor / 100, 2)" \
  "  end if;

  v_desc := case when c.tipo = 'pct' then v_base" \
  && rodar "10% dá 100%"

echo "2. banco: cupom vencido continua valendo"
troca supabase/34_cupons.sql \
  "  if c.fim is not null and v_hoje > c.fim then" \
  "  if false then" \
  && rodar "a validade não vale"

echo "3. banco: o cupom de um serviço vale para todos"
troca supabase/34_cupons.sql \
  "      if c.servicos is null or cardinality(c.servicos) = 0 or it.s = any(c.servicos) then" \
  "      if true then" \
  && rodar "só alguns serviços não vale"

echo "4. banco: horário desmarcado continua gastando o cupom"
troca supabase/34_cupons.sql \
  "            or (a.status <> 'cancelado' and a.arquivado_em is null));
    if v_usos >= c.limite_total then" \
  "            or true);
    if v_usos >= c.limite_total then" \
  && rodar "o uso não volta"

echo "5. banco: 1 por cliente não é cobrado"
troca supabase/34_cupons.sql \
  "  if c.um_por_cliente and (v_tel is not null or p_cliente is not null) then" \
  "  if false then" \
  && rodar "a mesma cliente usa de novo"

echo "6. banco: cupom desligado continua valendo"
troca supabase/34_cupons.sql \
  "   where x.salao_id = p_salao and x.codigo = v_cod and x.ativo;" \
  "   where x.salao_id = p_salao and x.codigo = v_cod;" \
  && rodar "desligar não desliga"

echo "7. banco: a conta fica aberta a qualquer um"
troca supabase/34_cupons.sql \
  "revoke all on function public.cupom_calcular(uuid, text, text, uuid[], uuid, timestamptz, jsonb, text, uuid, boolean)
  from public, anon, authenticated;" \
  "grant execute on function public.cupom_calcular(uuid, text, text, uuid[], uuid, timestamptz, jsonb, text, uuid, boolean) to anon, authenticated;" \
  && rodar "qualquer um chama a conta por fora"

echo "8. banco: o pedido da loja não registra o uso"
troca supabase/34_cupons.sql \
  "  insert into public.cupom_usos (cupom_id, salao_id, origem, telefone, perfil_id, desconto)
       values ((r->>'cupom_id')::uuid, p_salao, 'produtos',
               nullif(public.telefone_nacional(eu.telefone), ''), auth.uid(),
               (r->>'desconto')::numeric);" \
  "  perform 1;" \
  && rodar "o limite da loja nunca chega"

echo "9. banco: o agendar() grava o desconto e cobra o preço cheio"
troca supabase/09_cliente.sql \
  "    v_valor    := v_valor - v_desconto;" \
  "    v_valor    := v_valor;" \
  && rodar "valor_previsto sem o desconto"

echo "10. banco: código errado marca pelo preço cheio"
troca supabase/09_cliente.sql \
  "      raise exception 'Cupom: %', v_cupom->>'motivo' using errcode = 'check_violation';" \
  "      v_cupom := jsonb_build_object('desconto', 0);" \
  && rodar "a recusa vira preço cheio calado"

echo "11. banco: o agendar() não registra o uso"
troca supabase/09_cliente.sql \
  "  if v_desconto > 0 then
    insert into public.cupom_usos" \
  "  if false then
    insert into public.cupom_usos" \
  && rodar "1 por cliente e limite nunca chegam"

echo "12. banco: a comanda automática esquece o desconto"
troca supabase/28_sem_comanda.sql \
  "       values (new.salao_id, new.id, new.cliente_id, true, coalesce(new.desconto, 0)," \
  "       values (new.salao_id, new.id, new.cliente_id, true, 0," \
  && rodar "o caixa cobra o preço cheio"

echo "13. painel: o total do horário ignora o cupom"
troca app.html \
  "  return Math.max(0, cheio - (Number(ag.desconto) || 0));" \
  "  return cheio;" \
  && rodar "a agenda mostra o preço cheio"

echo "14. painel: a comanda nasce sem o desconto"
troca app.html \
  "      desconto: doPacote ? cheio : (Number(a.desconto) || 0)," \
  "      desconto: doPacote ? cheio : 0," \
  && rodar "o balcão cobra o preço cheio"

echo "15. painel: os serviços marcados não vão para o banco"
troca app.html \
  "    servicos: servicos.length ? servicos : null," \
  "    servicos: null," \
  && rodar "só alguns serviços vira todos"

echo "16. painel: a tabela de cupons não sincroniza"
troca dados.js \
  "  'cupons',
" \
  "" \
  && rodar "o cadastro não chega ao banco"

echo "17. link: o código não sobe com a marcação"
troca agendar.html \
  "      ...(comCupom && cupom ? { p_cupom: cupom } : {})," \
  "      ...({})," \
  && rodar "a tela mostra desconto e o banco cobra cheio"

echo "18. link: o total ignora o cupom"
troca agendar.html \
  "  const total = real((coberto ? 0 : precoDela) + precoOutra - desc);" \
  "  const total = real((coberto ? 0 : precoDela) + precoOutra);" \
  && rodar "aplicou e o total não desce"

echo "19. loja: o carrinho muda e a prévia velha continua"
troca agendar.html \
  "  return !!(cupomLoja && (cupomLoja.usado || cupomLoja.chave === chaveDoCupomLoja()));" \
  "  return !!cupomLoja;" \
  && rodar "desconto de outro pedido"

echo "20. loja: o pedido sai sem registrar o uso"
troca agendar.html \
  "  const comCupom = mostraCupomLoja() && cupomLojaVale() && !cupomLoja.usado;" \
  "  const comCupom = false;" \
  && rodar "o limite da loja nunca chega"

echo "21. link: o cupom recusado na hora de marcar vira erro genérico"
troca agendar.html \
  "    if(doCupom){" \
  "    if(false){" \
  && rodar "a cliente não sabe que é o cupom"

echo "22. loja: o campo aparece em salão sem cupom"
troca agendar.html \
  "  return NA_NUVEM && salaoTemCupom.produtos && totalDoCarrinho() > 0;" \
  "  return NA_NUVEM && totalDoCarrinho() > 0;" \
  && rodar "a cliente procura um código que não existe"

echo "23. cor escrita no botão do cupom"
troca estilo.css \
  "  background:var(--acao); color:var(--acao-txt); font:inherit; font-size:15px; font-weight:700;" \
  "  background:#123456; color:var(--acao-txt); font:inherit; font-size:15px; font-weight:700;" \
  && rodar "o botão não segue o tema"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
