# Os cinco modelos, para cadastrar na Meta

**Gerenciador do WhatsApp → Modelos de mensagem → Criar modelo.**

Para os cinco, sempre:

| campo | valor |
|---|---|
| Categoria | **Utilidade** |
| Idioma | **Português (BR)** |
| Cabeçalho | nenhum |
| Botões | nenhum — **menos no resumo do dia**, que tem um (veja o 4) |

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
🏪 Local: {{6}}

Até breve!
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome da cliente | Maria |
| `{{2}}` | data | 15/09/2026 |
| `{{3}}` | horário | 14:30 |
| `{{4}}` | serviço | Corte + Escova |
| `{{5}}` | profissional | Ana |
| `{{6}}` | nome do salão | Salão da Ana |

> **Por que o nome do salão.** O número que manda é do AgendaPro, um só para
> todos os salões — a cliente vê "Agendapro" no topo da conversa. Sem o nome
> da casa no texto, ela não sabe onde é o horário.

---

## 2. `agendapro_lembrete`

Sai o tanto de horas antes que o dono escolher (padrão: 2h).

```
🔔 Olá, {{1}}! Passando para lembrar do seu horário.

📅 Data: {{2}}
🕐 Horário: {{3}}
✂️ Serviço: {{4}}
👤 Profissional: {{5}}
🏪 Local: {{6}}

Esperamos você!
```

Mesmas seis variáveis da confirmação, na mesma ordem.

> **Por que "Data:", "Horário:" e os outros rótulos.** A Meta recusa modelo
> com variável demais para o tamanho do texto fixo. Sem os rótulos seriam seis
> variáveis para umas dez palavras — o mesmo modelo, mais curto, volta
> recusado.

---

## 3. `agendapro_aviso_profissional`

Vai para **quem atende**, avisando que entrou horário na agenda dela.

```
Olá, {{1}}. Um horário foi agendado com você.

👤 Cliente: {{2}}
✂️ Serviço: {{3}}
📅 Data: {{4}}
🕐 Horário: {{5}}
🏪 Local: {{6}}

Aviso automático do sistema de agendamento.
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome de quem atende | Ana |
| `{{2}}` | nome completo da cliente | Maria Souza |
| `{{3}}` | serviço | Corte + Escova |
| `{{4}}` | data | 15/10/2026 |
| `{{5}}` | horário | 14:30 |
| `{{6}}` | nome do salão | Salão da Ana |

> Aqui é o nome **completo** da cliente, e não só o primeiro: é ele que a
> profissional vai procurar na agenda.

> **Por que não é mais o `agendapro_novo1`.** A Meta o reclassificou como
> **Marketing** — o "🔔 Novo agendamento… Confira na agenda" foi lido como
> chamada — e mensagem de marketing ela segura para quem nunca conversou com
> o número: o aviso saía como "enviado" e não chegava. Este segue a forma da
> confirmação, que passou como Utilidade: endereçado à pessoa, sobre **um**
> agendamento, com o local, sem chamada para ação. O `agendapro_novo1` pode ser
> apagado na Meta: o sistema não usa mais.

---

## 4. `agendapro_agenda_hoje`

O resumo do dia, uma vez pela manhã, para o dono e para cada profissional.

```
Olá, {{1}}. Este é o resumo da sua agenda de hoje.

🏪 Local: {{2}}
📋 Atendimentos: {{3}}
🕐 Primeiro horário: {{4}}

Aviso automático do sistema de agendamento.
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome de quem recebe | Ana |
| `{{2}}` | nome do salão | Salão da Ana |
| `{{3}}` | quantos atendimentos | 5 |
| `{{4}}` | o primeiro horário | 09:00 com Maria (Corte) |

**Este tem um botão:** Adicionar botão → **Visitar o site**

| campo | valor |
|---|---|
| Texto do botão | `Ver agenda` |
| Tipo de URL | **Estática** |
| URL | o endereço do painel, o mesmo que você abre para entrar — ex.: `https://alelima30.github.io/agendapro/app.html` |

> **Por que não vai a lista inteira.** Variável de modelo **não aceita quebra
> de linha**. A lista achatada saía como uma linha só, enorme, e ainda
> repetia o "Bom dia" e o nome do salão. Agora vão só quantos e o primeiro, e
> a lista bonita, uma por linha, fica no painel — que é para onde o botão
> leva. O histórico do painel continua guardando a lista inteira.

> **Por que o nome não é mais `agendapro_resumo` nem `agendapro_agenda_dia`.**
> O primeiro mandava a lista numa linha só. O segundo a Meta reclassificou
> como **Marketing**: o "☀️ Bom dia!" de abertura e o "Toque no botão para
> ver a agenda completa" foram lidos como chamada — e marketing ela segura
> para quem nunca conversou com o número. Este tem as mesmas quatro
> variáveis, no formato de aviso de conta, sem chamada no texto. Os dois
> antigos podem ser apagados na Meta. E o nome é sempre outro porque nome de
> modelo apagado fica preso por semanas.

---

## 5. `agendapro_lembrete_equipe`

O **lembrete para o salão**: antes do atendimento, para quem vai atender, para
o dono, ou para os dois — o salão escolhe em **Mensagens da agenda**. Vem
desligado; o tempo é separado do lembrete da cliente.

```
Olá, {{1}}. Lembrete de um horário agendado.

👤 Cliente: {{2}}
✂️ Serviço: {{3}}
💼 Profissional: {{4}}
📅 Data: {{5}}
🕐 Horário: {{6}}
🏪 Local: {{7}}

Aviso automático do sistema de agendamento.
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome de **quem recebe** | Ju |
| `{{2}}` | nome completo da cliente | Maria Souza |
| `{{3}}` | serviço | Corte + Escova |
| `{{4}}` | quem vai atender | Bia |
| `{{5}}` | data | 15/10/2026 |
| `{{6}}` | horário | 14:30 |
| `{{7}}` | nome do salão | Salão da Ana |

> **Por que o {{4}}.** Quem recebe pode não ser quem atende: o dono recebendo o
> lembrete do horário da Bia precisa ler "Profissional: Bia".

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

`variaveis` tem que ter 6 itens na confirmação, no lembrete e no aviso à
profissional, 4 no resumo e 7 no lembrete para o salão — na ordem das tabelas acima.
