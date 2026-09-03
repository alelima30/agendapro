# Os quatro modelos, para cadastrar na Meta

**Gerenciador do WhatsApp → Modelos de mensagem → Criar modelo.**

Para os quatro, sempre:

| campo | valor |
|---|---|
| Categoria | **Utilidade** |
| Idioma | **Português (BR)** |
| Cabeçalho | nenhum |
| Botões | nenhum |

> **Categoria importa muito no bolso.** Utilidade custa cerca de **R$ 0,045**
> por mensagem no Brasil. Marketing custa **R$ 0,31–0,38** — oito vezes mais.
> Se a Meta reclassificar um modelo seu como marketing, o custo dele muda
> junto. Por isso nenhum destes textos vende nada: são todos aviso puro.

---

## ⚠ Antes de cadastrar, leia isto

**Modelo aprovado praticamente não se edita.** Para mudar uma vírgula você cria
outro e espera nova aprovação.

E a **ordem** das variáveis é um contrato com o banco. Se você trocar `{{2}}` e
`{{3}}` de lugar no texto cadastrado, toda cliente passa a receber a data no
lugar do horário — e o histórico do painel continua mostrando certo, porque ele
mostra o `corpo`, não o que foi enviado. Seria um defeito invisível.

**Copie os textos abaixo exatamente como estão.**

---

## 1. `agendapro_confirmacao`

Sai assim que a cliente marca.

```
Olá, {{1}}! Seu agendamento foi confirmado.

📅 Data: {{2}}
🕐 Horário: {{3}}
✂️ Serviço: {{4}}
👤 Profissional: {{5}}

Até breve!
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome da cliente | Maria |
| `{{2}}` | data | 15/09/2026 |
| `{{3}}` | horário | 14:30 |
| `{{4}}` | serviço | Corte + Escova |
| `{{5}}` | profissional | Ana |

---

## 2. `agendapro_lembrete`

Sai o tanto de horas antes que o dono escolher (padrão: 2h).

```
🔔 Olá, {{1}}! Passando para lembrar do seu horário.

📅 {{2}}
🕐 {{3}}
✂️ {{4}}
👤 {{5}}

Esperamos você!
```

Mesmas cinco variáveis da confirmação, na mesma ordem.

---

## 3. `agendapro_novo`

Vai para o **profissional**, avisando que entrou horário na agenda dele.

```
🔔 Novo agendamento na sua agenda.

Cliente: {{1}}
Serviço: {{2}}
Data: {{3}}
Horário: {{4}}

Confira na agenda.
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | nome completo da cliente | Maria Souza |
| `{{2}}` | serviço | Corte + Escova |
| `{{3}}` | data | 15/09/2026 |
| `{{4}}` | horário | 14:30 |

> Aqui é o nome **completo**, e não só o primeiro: é ele que a pessoa vai
> procurar na agenda.

---

## 4. `agendapro_resumo`

O resumo do dia, uma vez pela manhã.

```
Bom dia! Segue a agenda de hoje — {{1}}.

{{2}}

Bom trabalho!
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | nome do salão | Salão da Ana |
| `{{2}}` | a agenda do dia | `09:00 — Maria — Corte · 10:30 — Joana — Escova · Total: 2 atendimentos` |

> **Por que a lista vem numa linha só, com " · " no meio:** variável de modelo
> **não aceita quebra de linha** — nem tabulação, nem quatro espaços seguidos.
> A Meta recusa. O painel continua mostrando a lista bonita, uma por linha; só
> o que viaja é achatado.

---

## As regras que quebram o envio sem avisar direito

| regra | o que acontece se quebrar |
|---|---|
| variável vazia | a mensagem inteira é recusada |
| quebra de linha dentro da variável | recusada |
| o texto não pode começar nem terminar com variável | o cadastro é recusado |
| duas variáveis coladas (`{{1}} {{2}}` sem texto entre elas) | o cadastro é recusado |

O banco já trata as duas primeiras: `variavel_limpa()` troca vazio por `—`,
achata espaço e corta em 900 caracteres. As duas últimas dependem do texto que
você cadastrar — e os quatro acima já respeitam.

---

## Depois de aprovar

Nada a fazer no código. Os nomes já estão gravados em `modelo_de()`, no
`21_notificacoes.sql`, e cada linha da fila nasce com o modelo e as variáveis
prontas.

Para conferir que bate:

```sql
select tipo, modelo, variaveis, corpo
  from public.notificacoes
 order by criado_em desc
 limit 5;
```

`variaveis` tem que ter 5 itens na confirmação e no lembrete, 4 no novo e 2 no
resumo — na ordem das tabelas acima.
