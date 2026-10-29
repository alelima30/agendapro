#!/usr/bin/env bash
# ===========================================================================
#  A cópia do banco (supabase/backup.sh), de ida e de volta
#
#    bash tests/bancada/subir.sh          (noutro terminal)
#    bash tests/backup.test.sh
#
#  Copia o banco da bancada como o robô de toda noite copia o do Supabase, e
#  faz o caminho do supabase/BACKUP.md ao contrário: destranca e restaura num
#  banco limpo. Backup que nunca foi restaurado é esperança, não backup.
#
#    1. sem os segredos, ou com senha curta, para e diz o que falta;
#    2. sai só a cópia trancada — a aberta não fica na pasta;
#    3. trancada, não abre como cópia do Postgres, nem com a senha errada;
#    4. com a senha certa, destranca e restaura: a agenda volta igual.
# ===========================================================================
set -u
cd "$(dirname "$0")/.."
H="${PGHOST:-/tmp}"; PT="${PGPORT:-5444}"; U="${PGUSER:-postgres}"; B="${PGBANCO:-app}"
P="psql -h $H -p $PT -U $U -qtA"
DESTINO=backup_restaurado
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DESTINO;" >/dev/null 2>&1' EXIT

ok=0; ruim=0
e(){ if [ -n "$2" ]; then echo "  ✓ $1"; ok=$((ok+1)); else echo "  ✗ $1${3:+
      $3}"; ruim=$((ruim+1)); fi; }

URL="postgresql://$U@/$B?host=$H&port=$PT"
SENHA="uma-frase-bem-comprida-de-teste"

# Um salão com um horário marcado, para a volta ter o que conferir (a bancada
# recém-montada pode estar vazia, e "0 volta igual a 0" não prova nada).
MARCA=$(date +%s%N | tail -c 9)
SAL="b0000000-0000-0000-0000-0000$MARCA"; SAL=${SAL:0:36}
AGE="b1000000-0000-0000-0000-0000$MARCA"; AGE=${AGE:0:36}
USR="b2000000-0000-0000-0000-0000$MARCA"; USR=${USR:0:36}
$P -d "$B" -v ON_ERROR_STOP=1 >/dev/null <<SQL
insert into auth.users (id, email) values ('$USR', 'backup-$MARCA@teste.com');
insert into public.saloes (id, slug, nome, tipo, status) values ('$SAL', 'backup-$MARCA', 'Salão Backup', 'salao', 'ativo');
insert into public.assinaturas (salao_id, plano, status) values ('$SAL', 'time', 'ativa');
insert into public.profissionais (id, salao_id, nome, ativo) values ('$SAL', '$SAL', 'Ana', true);
insert into public.jornadas (profissional_id, dia_semana, inicio, fim)
  select '$SAL', d, '00:00', '23:59' from generate_series(0, 6) d;
insert into public.servicos (id, salao_id, nome, duracao_min, preco) values ('$SAL', '$SAL', 'Corte', 30, 60);
insert into public.clientes (id, salao_id, nome, telefone) values ('$SAL', '$SAL', 'Maria Backup', '11977770000');
insert into public.agendamentos (id, salao_id, cliente_id, profissional_id, inicio, fim, status, valor_previsto)
  values ('$AGE', '$SAL', '$SAL', '$SAL',
          (current_date + 3 + time '10:00') at time zone 'America/Sao_Paulo',
          (current_date + 3 + time '10:30') at time zone 'America/Sao_Paulo', 'confirmado', 60);
SQL
limpar(){ $P -d "$B" -c "delete from public.saloes where id='$SAL'; delete from auth.users where id='$USR';" >/dev/null 2>&1; }
trap 'limpar; rm -rf "$TMP"; $P -d postgres -c "drop database if exists $DESTINO;" >/dev/null 2>&1' EXIT

echo ""
echo "1. Os segredos"
s=$(SUPABASE_DB_URL="" BACKUP_SENHA="$SENHA" bash supabase/backup.sh "$TMP/a" 2>&1); r=$?
e "sem o endereço do banco, para dizendo o que falta" "$([ $r -ne 0 ] && echo "$s" | grep -q 'SUPABASE_DB_URL' && echo 1)" "$s"
s=$(SUPABASE_DB_URL="$URL" BACKUP_SENHA="curta" bash supabase/backup.sh "$TMP/a" 2>&1); r=$?
e "senha curta não serve (16 caracteres ou mais)" "$([ $r -ne 0 ] && echo "$s" | grep -q '16 caracteres' && echo 1)" "$s"

s=$(SUPABASE_DB_URL="postgresql://postgres:abc?def@db.xyz.supabase.co:5432/postgres" BACKUP_SENHA="$SENHA" bash supabase/backup.sh "$TMP/a" 2>&1); r=$?
e "senha do banco com ? no endereço: diz para trocar a senha" "$([ $r -ne 0 ] && echo "$s" | grep -q 'caractere especial' && echo 1)" "$s"
s=$(SUPABASE_DB_URL="postgresql://postgres:abcdef@db.xyz.supabase.co:5432/postgres" BACKUP_SENHA="$SENHA" bash supabase/backup.sh "$TMP/a" 2>&1); r=$?
e "endereço Direct connection: diz para usar o Session pooler" "$([ $r -ne 0 ] && echo "$s" | grep -q 'Session pooler' && echo 1)" "$s"

echo ""
echo "2. A cópia"
s=$(SUPABASE_DB_URL="$URL" BACKUP_SENHA="$SENHA" DIA=teste bash supabase/backup.sh "$TMP/b" 2>&1); r=$?
e "copiou e trancou" "$([ $r -eq 0 ] && [ -s "$TMP/b/agendapro-teste.dump.gpg" ] && echo 1)" "$s"
e "e diz o tamanho e quantas tabelas" "$(echo "$s" | grep -q 'tabelas com dados' && echo 1)" "$s"
e "a cópia aberta não fica na pasta" "$([ ! -e "$TMP/b/banco.dump" ] && [ "$(ls "$TMP/b" | wc -l)" -eq 1 ] && echo 1)" "$(ls "$TMP/b")"

echo ""
echo "3. Trancada"
e "o arquivo trancado não abre como cópia do Postgres" \
  "$(pg_restore --list "$TMP/b/agendapro-teste.dump.gpg" >/dev/null 2>&1 || echo 1)"
e "nem com a senha errada" \
  "$(gpg --batch --quiet --pinentry-mode loopback --passphrase 'outra-senha-qualquer-errada' \
       --decrypt "$TMP/b/agendapro-teste.dump.gpg" >/dev/null 2>&1 || echo 1)"

echo ""
echo "4. Destrancar e restaurar (o caminho do BACKUP.md)"
gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 \
    --output "$TMP/banco.dump" --decrypt "$TMP/b/agendapro-teste.dump.gpg" 3<<<"$SENHA"
e "com a senha certa, destranca" "$(pg_restore --list "$TMP/banco.dump" 2>/dev/null | grep -q 'TABLE DATA public agendamentos ' && echo 1)"
$P -d postgres -c "drop database if exists $DESTINO;" >/dev/null 2>&1
$P -d postgres -c "create database $DESTINO;" >/dev/null
# Os esquemas do Supabase (auth, storage) já existem num projeto de verdade;
# no banco limpo, a própria cópia os cria. As extensões vêm antes, como no
# 00_tudo.sql.
$P -d "$DESTINO" -c "create extension if not exists pgcrypto; create extension if not exists citext;" >/dev/null 2>&1
pg_restore -h "$H" -p "$PT" -U "$U" --no-owner --no-privileges --dbname="$DESTINO" "$TMP/banco.dump" 2>"$TMP/erros.txt"
for t in saloes agendamentos clientes profissionais servicos assinaturas; do
  a=$($P -d "$B" -c "select count(*) from public.$t")
  d=$($P -d "$DESTINO" -c "select count(*) from public.$t" 2>/dev/null)
  e "public.$t volta igual ($a linhas)" "$([ -n "$d" ] && [ "$a" = "$d" ] && echo 1)" "na cópia: '$d'"
done
e "o horário marcado volta, com a cliente e a hora" \
  "$([ "$($P -d "$DESTINO" -c "select c.nome || ' ' || to_char(a.inicio at time zone 'America/Sao_Paulo', 'HH24:MI')
          from public.agendamentos a join public.clientes c on c.id = a.cliente_id where a.id = '$AGE'" 2>/dev/null)" \
       = "Maria Backup 10:00" ] && echo 1)"
a=$($P -d "$B" -c "select count(*) from auth.users")
d=$($P -d "$DESTINO" -c "select count(*) from auth.users" 2>/dev/null)
e "e as contas de login também ($a)" "$([ -n "$d" ] && [ "$a" = "$d" ] && echo 1)" "na cópia: '$d'"

echo ""
if [ "$ruim" -eq 0 ]; then echo "✓ $ok verificações do backup."; else echo "✗ $ruim de $((ok+ruim)) falharam."; exit 1; fi
