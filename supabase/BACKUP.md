# Backup do banco — a cópia de toda noite

Todo dia às **03:17 (Brasília)** o GitHub copia o banco do AgendaPro, confere
que a cópia tem os dados da agenda, **tranca com a sua senha** e guarda por
**30 dias**. Quem faz é o `.github/workflows/backup.yml`, rodando o
`supabase/backup.sh`. O `tests/backup.test.sh` prova a ida e a volta.

O que entra: tudo do sistema (`public`: salões, agenda, clientes, serviços,
assinaturas…), as contas de login (`auth`) e o registro das fotos
(`storage`). Os **arquivos** das fotos ficam no armazenamento do Supabase e
não entram nesta cópia.

## Ligar (uma vez)

1. **O endereço do banco.** No Supabase, botão **Connect** (no alto) →
   **Connection String** → escolha **Session pooler** → copie o endereço.
   Ele termina em `pooler.supabase.com:5432/postgres` e tem `[YOUR-PASSWORD]`
   no meio: troque pela senha do banco.
   - Não lembra a senha? **Project Settings → Database → Reset database
     password**. O site e o link não usam essa senha; trocar não derruba nada.
   - ⚠ Use o **Session pooler**, não o *Direct connection*: no plano grátis, o
     direto não é alcançado pelas máquinas do GitHub.
2. **No GitHub**, no repositório `agendapro`: **Settings → Secrets and
   variables → Actions → New repository secret**, e crie dois:
   - `SUPABASE_DB_URL` → o endereço do passo 1, com a senha;
   - `BACKUP_SENHA` → uma frase sua, com **16 caracteres ou mais**.
     **Guarde essa frase num lugar seguro.** Sem ela, nenhuma cópia abre — nem
     para quem a baixar, nem para você.
3. **Testar agora:** **Actions → Backup do banco → Run workflow**. Em um ou dois
   minutos fica verde, e a cópia aparece embaixo, em **Artifacts**, como
   `backup-AAAA-MM-DD`.

Nunca cole o endereço do banco nem a senha numa conversa: eles vão só nos
segredos do GitHub.

Se uma noite falhar, o GitHub manda um e-mail para você.

## Onde estão as cópias

**Actions → Backup do banco →** clique na corrida do dia → **Artifacts →
backup-AAAA-MM-DD**. Baixa um `.zip` com o arquivo
`agendapro-AAAA-MM-DD.dump.gpg` dentro — trancado.

## Restaurar

Restaurar é trabalho técnico e mexe no banco de verdade: faça junto de quem
cuida do sistema, com o arquivo e a senha na mão. O caminho:

```bash
# 1. Destrancar (pede a BACKUP_SENHA)
gpg --output banco.dump --decrypt agendapro-AAAA-MM-DD.dump.gpg

# 2. Ver o que tem dentro
pg_restore --list banco.dump | less
```

**Recuperar algo apagado** (um salão, uns horários) — o caso mais comum:
restaure a cópia num banco **à parte** (um projeto novo e vazio do Supabase,
ou um Postgres local), e de lá copie só as linhas que faltam para o banco de
verdade. Nunca restaure por cima do banco que está no ar.

```bash
pg_restore --no-owner --no-privileges --schema=public \
  --dbname="ENDEREÇO-DO-BANCO-À-PARTE" banco.dump
```

**Perdeu o projeto inteiro:**
1. Crie um projeto novo no Supabase.
2. Restaure o sistema: o comando acima, com o endereço do projeto novo. Os
   gatilhos são criados depois dos dados — nenhum WhatsApp sai na restauração.
3. As contas de login:
   `pg_restore --no-owner --data-only --schema=auth -t users -t identities --dbname="..." banco.dump`
4. Cole o `00_tudo.sql` (recria permissões e regras) e rode o `CONFERIR.sql`.
5. Só então ligue o WhatsApp (`LIGAR-WHATSAPP.sql`) e troque a URL e a chave no
   `config.js` para as do projeto novo.
