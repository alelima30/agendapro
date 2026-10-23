#!/usr/bin/env bash
# ===========================================================================
#  Quebrar de propósito o lembrete para o salão — o teste tem de reprovar.
#
#    bash tests/bancada/subir.sh          (noutro terminal)
#    bash tests/mutacoes-lembrete-salao.sh
#
#  O teste é o tests/lembrete-salao.test.mjs, na bancada. Cada mutação entra
#  no banco da bancada pelo próprio 21_notificacoes.sql, e o original volta no
#  fim (e a cada rodada).
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
T=tests/lembrete-salao.test.mjs
PSQL="psql -h ${PGHOST_BANCADA:-/tmp} -p ${PGPORT_BANCADA:-5444} -U postgres -d app -v ON_ERROR_STOP=1 -q"

ARQS="supabase/21_notificacoes.sql"
SQLS="supabase/21_notificacoes.sql"
guarda(){ echo "/tmp/mls-$(echo "$1" | tr '/' '_')"; }
for a in $ARQS; do cp "$a" "$(guarda "$a")"; done
aplicar(){ for f in $SQLS; do $PSQL -f "$f" >/dev/null 2>&1 || return 1; done; }
restaurar(){
  for a in $ARQS; do cp "$(guarda "$a")" "$a"; done
  aplicar || echo "  !! não consegui devolver o SQL original à bancada"
}
trap restaurar EXIT

viva=0; morta=0; perdida=0
rodar(){
  if ! aplicar; then
    echo "  ✗ NÃO RODOU — o SQL mutante não entrou no banco ($1)"; perdida=$((perdida+1))
    restaurar; return 0
  fi
  if node "$T" >/tmp/mls-saida.txt 2>&1; then
    echo "  ✗ SOBREVIVEU — $1"; viva=$((viva+1))
  else
    echo "  ✓ morreu — $1  ($(grep -c '✗' /tmp/mls-saida.txt) reprovações)"
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
F=supabase/21_notificacoes.sql

echo "1. vem ligado de fábrica"
troca $F \
  "     and public.notif_liga(a.salao_id, 'notifLembreteEquipe', false) then
    v_min    :=" \
  "     and public.notif_liga(a.salao_id, 'notifLembreteEquipe', true) then
    v_min    :=" \
  && rodar "todo salão passa a pagar por mensagem que não pediu"

# (Tirar o "não repetir o telefone" é mutação EQUIVALENTE: a chave da fila
#  leva o telefone, e a segunda linha esbarra na primeira. Fica a regra no
#  código, por clareza; a mutação que importa é achar o dono certo.)
echo "2. "o dono" não acha o dono"
troca $F \
  "           and v.papel in ('dono', 'admin') and v.status = 'ativo'" \
  "           and v.papel in ('profissional') and v.status = 'ativo'" \
  && rodar "o dono escolhe receber e ninguém recebe"

echo "3. o tempo é o do lembrete da cliente"
troca $F \
  "    v_min    := greatest(0, least(1440,
                  public.notif_num(a.salao_id, 'notifLembreteEquipeMin', 60)));" \
  "    v_min    := public.lembrete_minutos(a.salao_id);" \
  && rodar "o ajuste do salão não vale"

echo "4. o cancelado não revive"
troca $F \
  "     where public.notificacoes.status = 'cancelado';" \
  "     where false;" \
  && rodar "voltar o ajuste deixa a profissional sem lembrete"

echo "5. remarcar não leva o lembrete"
troca $F \
  "  if new.inicio is distinct from old.inicio
     or new.profissional_id is distinct from old.profissional_id then
    perform public.refazer_lembrete_equipe(new.id);
  end if;" \
  "" \
  && rodar "lembrete na hora velha"

echo "6. trocar de profissional não dispara nada"
troca $F \
  "  after update of inicio, status, arquivado_em, profissional_id on public.agendamentos" \
  "  after update of inicio, status, arquivado_em on public.agendamentos" \
  && rodar "a antiga é lembrada de um horário que não é dela"

echo "7. a varredura sai do agendador"
troca $F \
  "  perform public.gerar_lembretes_equipe();
  -- E o da cliente" \
  "  -- E o da cliente" \
  && rodar "ligar e desligar não valem para o que já estava marcado"

echo "8. horário pendente também ganha lembrete"
troca $F \
  "  if a.status = 'confirmado' and a.arquivado_em is null and a.inicio > now()
     and public.notif_liga(a.salao_id, 'notifLembreteEquipe', false) then" \
  "  if a.status in ('confirmado', 'pendente') and a.arquivado_em is null and a.inicio > now()
     and public.notif_liga(a.salao_id, 'notifLembreteEquipe', false) then" \
  && rodar "a equipe é lembrada de horário que pode ser recusado"

echo "9. quem desligou o seu em Equipe recebe igual"
troca $F \
  "         where pr.id = a.profissional_id and pr.notif_lembrete;" \
  "         where pr.id = a.profissional_id;" \
  && rodar "a escolha da pessoa não vale"

echo "10. a saudação é de quem atende, e não de quem recebe"
troca $F \
  "    from public.profissionais pr where pr.id = p_destinatario;" \
  "    from public.profissionais pr
   where pr.id = (select profissional_id from public.agendamentos where id = p_agendamento);" \
  && rodar "\"Olá, Bia\" no WhatsApp da dona"

echo "11. o que não vale mais fica na fila"
troca $F \
  "     and not (n.chave = any(v_chaves))
     and not (v_chegou and n.destino = any(v_tels));" \
  "     and false;" \
  && rodar "dois lembretes, um na hora velha"

echo "12. \"quem recebe\" não é lido"
troca $F \
  "      if v_para not in ('atende', 'dono', 'ambos') then v_para := 'atende'; end if;" \
  "      v_para := 'atende';" \
  && rodar "o dono escolhe e nada muda"

echo "13. chegada a hora, ninguém recebe (o defeito do lembrete das 9h)"
troca $F \
  "    if v_min > 0 then
      select coalesce(cfg->>'notifLembreteEquipePara', 'atende') into v_para" \
  "    if v_min > 0 and v_quando > now() then
      select coalesce(cfg->>'notifLembreteEquipePara', 'atende') into v_para" \
  && rodar "o lembrete do salão é cancelado na hora de sair"

echo "14. com a hora chegada, o pendente de outra chave é cancelado"
troca $F \
  "     and not (v_chegou and n.destino = any(v_tels));" \
  "     ;" \
  && rodar "remarcou para daqui a pouco e o lembrete some"

echo "15. o cancelado na hora de sair não volta"
troca $F \
  "       and n.status = 'cancelado' and n.chave = any(v_chaves)" \
  "       and false" \
  && rodar "o lembrete que o defeito cancelou fica perdido"

echo "16. o lembrete da hora velha fica para depois do atendimento"
troca $F \
  "       set quando = now(),
           corpo = coalesce(public.texto_lembrete_equipe(a.id, n.profissional_id), n.corpo)," \
  "       set corpo = coalesce(public.texto_lembrete_equipe(a.id, n.profissional_id), n.corpo)," \
  && rodar "remarcou para mais cedo e o lembrete sai depois"

echo "17. com a hora chegada, nasce lembrete novo em cima da hora"
troca $F \
  "       and n.status = 'pendente' and n.destino = any(v_tels) and n.quando > now();
    return;
  end if;" \
  "       and n.status = 'pendente' and n.destino = any(v_tels) and n.quando > now();
  end if;" \
  && rodar "quem passa a atender na hora recebe lembrete atrasado"

echo
echo "mortas: $morta · sobreviveram: $viva · não rodaram: $perdida"
[ $viva -eq 0 ] && [ $perdida -eq 0 ]
