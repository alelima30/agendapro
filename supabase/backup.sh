#!/usr/bin/env bash
# ===========================================================================
# AgendaPro — a cópia do banco, trancada com senha
#
#   SUPABASE_DB_URL=... BACKUP_SENHA=... bash supabase/backup.sh [pasta]
#
# Quem roda isto todo dia é o .github/workflows/backup.yml. Restaurar está no
# supabase/BACKUP.md.
#
# ── POR QUE EXISTE ─────────────────────────────────────────────────────────
# "Precisamos ter backup?" No plano grátis, o Supabase não guarda cópia que
# dê para restaurar pelo painel: horário apagado sem querer, um defeito, um
# problema na conta — e não havia volta.
#
# ── O QUE ENTRA ────────────────────────────────────────────────────────────
#   public   tudo do sistema: salões, agenda, clientes, serviços, assinaturas…
#   auth     as contas de login (para quem entra continuar entrando)
#   storage  o registro das fotos (os ARQUIVOS das fotos moram fora do banco,
#            no armazenamento do Supabase, e não entram aqui)
# O resto (cron, extensões, os esquemas internos do Supabase) é recriado
# colando o 00_tudo.sql e o LIGAR-WHATSAPP.sql.
#
# ── TRANCADA ───────────────────────────────────────────────────────────────
# A cópia tem nome, telefone e aniversário de cliente, e o login de todo
# mundo. Sai daqui só depois de trancada com AES-256 e a BACKUP_SENHA; a cópia
# aberta nunca é guardada. Sem a senha, o arquivo não serve para nada — nem
# para quem o baixar do GitHub, nem para você: guarde a senha.
# ===========================================================================
set -euo pipefail

if [ -z "${SUPABASE_DB_URL:-}" ] || [ -z "${BACKUP_SENHA:-}" ]; then
  echo "::error::Faltam SUPABASE_DB_URL e/ou BACKUP_SENHA (supabase/BACKUP.md diz onde achar)." >&2
  exit 1
fi
if [ "${#BACKUP_SENHA}" -lt 16 ]; then
  echo "::error::A BACKUP_SENHA precisa de pelo menos 16 caracteres." >&2
  exit 1
fi

# Os dois erros de quem cola o endereço pela primeira vez, ditos com o que
# fazer (o pg_dump responderia "missing key/value separator", que não ajuda):
#   · a senha do banco com ? # / @ — dentro do endereço, eles cortam a senha;
#   · o "Direct connection", que as máquinas do GitHub não alcançam no grátis.
credenciais="${SUPABASE_DB_URL#*://}"; credenciais="${credenciais%@*}"
servidor="${SUPABASE_DB_URL##*@}"
case "$credenciais" in
  *[?#/@]*)
    echo "::error::A senha do banco tem um caractere especial (? # / ou @), que quebra o endereço. Troque a senha do banco por uma só com letras e números (supabase/BACKUP.md) e atualize o SUPABASE_DB_URL." >&2
    exit 1 ;;
esac
case "$servidor" in
  db.*.supabase.co*)
    echo "::error::Este é o endereço \"Direct connection\", que o GitHub não alcança no plano grátis. No Supabase, em Connect, escolha \"Session pooler\" (termina em pooler.supabase.com) e atualize o SUPABASE_DB_URL." >&2
    exit 1 ;;
esac

SAIDA="${1:-saida}"
DIA="${DIA:-$(TZ=America/Sao_Paulo date +%Y-%m-%d)}"
mkdir -p "$SAIDA"
CRU="$SAIDA/banco.dump"
# A cópia aberta não sobrevive ao script, dê certo ou dê errado.
trap 'rm -f "$CRU" "$SAIDA/indice.txt"' EXIT

pg_dump --dbname="$SUPABASE_DB_URL" --format=custom --no-owner --no-privileges \
        --schema=public --schema=auth --schema=storage --file="$CRU"

# Conferir ANTES de trancar: uma cópia vazia que diz "backup ok" é pior que
# nenhuma, porque ninguém vai atrás dela.
pg_restore --list "$CRU" > "$SAIDA/indice.txt"
for t in saloes agendamentos clientes profissionais servicos assinaturas; do
  if ! grep -q "TABLE DATA public $t " "$SAIDA/indice.txt"; then
    echo "::error::A cópia não tem os dados de public.$t — nada foi guardado." >&2
    exit 1
  fi
done
echo "Cópia de $DIA: $(du -h "$CRU" | cut -f1), $(grep -c 'TABLE DATA' "$SAIDA/indice.txt") tabelas com dados."

# A senha entra pelo descritor 3, e não na linha de comando: ali ela
# apareceria na lista de processos.
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
    --symmetric --cipher-algo AES256 \
    --output "$SAIDA/agendapro-$DIA.dump.gpg" "$CRU" 3<<<"$BACKUP_SENHA"
echo "Trancada: $SAIDA/agendapro-$DIA.dump.gpg"
