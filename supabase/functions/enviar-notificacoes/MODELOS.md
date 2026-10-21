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

# Os quatro com o valor e a forma de pagamento

"Falta forma de pagamento e valor" nos modelos, para o profissional e a
cliente. São os mesmos quatro de cima que falam de **um** agendamento, com
duas linhas a mais no fim: **💰 Valor** e **💳 Pagamento** — sempre as **duas
últimas** variáveis, nessa ordem. Mesmas regras: **Utilidade**, **Português
(BR)**, sem cabeçalho e sem botão.

- **Valor**: o total do atendimento, como o painel mostra — a soma dos
  serviços, menos o desconto do cupom (ex.: **R$ 80,00**). Sessão de pacote
  sai **R$ 0,00**.
- **Pagamento**: **Pix**, **Dinheiro**, **Cartão de débito**, **Cartão de
  crédito** (o que a cliente escolheu no link ou a recepção anotou),
  **Pacote (já pago)**, **Sem custo**, ou **A combinar no salão** quando
  ninguém informou.

> **⚠ A ordem para ligar.** Enquanto estes quatro não estiverem
> **aprovados**, o sistema continua mandando os de cima — nada muda. Depois
> da aprovação, ligue em **admin → Mensagens do WhatsApp → Ligar a forma de
> pagamento**. Ligar antes faria toda confirmação e todo aviso sair para um
> modelo que não existe (erro 132001), e não chegar. Os de cima podem ficar
> cadastrados: desligando, o sistema volta para eles na hora.

## 1b. `agendapro_confirmacao_pagamento`

```
Olá, {{1}}! Seu agendamento foi confirmado.

📅 Data: {{2}}
🕐 Horário: {{3}}
✂️ Serviço: {{4}}
👤 Profissional: {{5}}
🏪 Local: {{6}}
💰 Valor: {{7}}
💳 Pagamento: {{8}}

Até breve!
```

As seis da confirmação, na mesma ordem; `{{7}}` o valor (ex.: R$ 80,00) e
`{{8}}` a forma de pagamento (ex.: Pix).

## 2b. `agendapro_lembrete_pagamento`

```
🔔 Olá, {{1}}! Passando para lembrar do seu horário.

📅 Data: {{2}}
🕐 Horário: {{3}}
✂️ Serviço: {{4}}
👤 Profissional: {{5}}
🏪 Local: {{6}}
💰 Valor: {{7}}
💳 Pagamento: {{8}}

Esperamos você!
```

As seis do lembrete, na mesma ordem; `{{7}}` o valor e `{{8}}` a forma de
pagamento.

## 3b. `agendapro_aviso_profissional_pagamento`

```
Olá, {{1}}. Um horário foi agendado com você.

👤 Cliente: {{2}}
✂️ Serviço: {{3}}
📅 Data: {{4}}
🕐 Horário: {{5}}
🏪 Local: {{6}}
💰 Valor: {{7}}
💳 Pagamento: {{8}}

Aviso automático do sistema de agendamento.
```

As seis do aviso à profissional, na mesma ordem; `{{7}}` o valor e `{{8}}`
como a cliente vai pagar — o que a profissional precisa saber antes de a
cliente sentar.

## 5b. `agendapro_lembrete_equipe_pagamento`

```
Olá, {{1}}. Lembrete de um horário agendado.

👤 Cliente: {{2}}
✂️ Serviço: {{3}}
💼 Profissional: {{4}}
📅 Data: {{5}}
🕐 Horário: {{6}}
🏪 Local: {{7}}
💰 Valor: {{8}}
💳 Pagamento: {{9}}

Aviso automático do sistema de agendamento.
```

As sete do lembrete para o salão, na mesma ordem; `{{8}}` o valor e `{{9}}` a
forma de pagamento.

---

# Os cinco do modo Pedidos (restaurante, pizzaria, lanchonete)

Só são usados por estabelecimento do tipo **Restaurante** (`37_pedidos.sql`).
Mesmas regras de cima: **Utilidade**, **Português (BR)**, sem cabeçalho e sem
botão. Enquanto não forem aprovados, as mensagens do pedido ficam **pendentes**
na fila — nada é dado como enviado sem ter saído.

## 6. `agendapro_pedido_novo`

Vai para o **WhatsApp do estabelecimento** quando chega um pedido pelo link.

```
Novo pedido no {{1}}: #{{2}}, de {{3}}.

💰 Total: {{4}}
🛵 {{5}}

O pedido está na tela de Pedidos.
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | nome do estabelecimento | Pizzaria do Zé |
| `{{2}}` | número do pedido | 12 |
| `{{3}}` | primeiro nome de quem pediu | Bruna |
| `{{4}}` | total | R$ 58,00 |
| `{{5}}` | entrega ou retirada | entrega no bairro Centro |

## 7. `agendapro_pedido_confirmado`

Vai para a **cliente** quando o estabelecimento toca em **Aceitar**.

```
Olá, {{1}}! O {{2}} confirmou o seu pedido #{{3}}.

💰 Total: {{4}}
⏱️ Previsão: {{5}}

Obrigado pela preferência!
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome da cliente | Bruna |
| `{{2}}` | nome do estabelecimento | Pizzaria do Zé |
| `{{3}}` | número do pedido | 12 |
| `{{4}}` | total | R$ 58,00 |
| `{{5}}` | tempo estimado (Pedidos e entrega) | 40 a 60 min |

## 8. `agendapro_pedido_a_caminho`

Vai para a cliente quando o pedido de **entrega** sai.

```
Olá, {{1}}! O seu pedido #{{2}} saiu para entrega.

🏪 {{3}}

Até já!
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome da cliente | Bruna |
| `{{2}}` | número do pedido | 12 |
| `{{3}}` | nome do estabelecimento | Pizzaria do Zé |

## 9. `agendapro_pedido_pronto`

Vai para a cliente quando o pedido de **retirada** fica pronto.

```
Olá, {{1}}! O seu pedido #{{2}} está pronto para retirar.

🏪 {{3}}

Até já!
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome da cliente | Bruna |
| `{{2}}` | número do pedido | 12 |
| `{{3}}` | nome do estabelecimento | Pizzaria do Zé |

## 10. `agendapro_pedido_cancelado`

Vai para a cliente quando o **estabelecimento** cancela (quando é ela quem
cancela, pelo link, não vai mensagem: ela já sabe).

```
Olá, {{1}}. O pedido #{{2}} foi cancelado.

🏪 {{3}}
Motivo: {{4}}

Qualquer dúvida, fale com o estabelecimento.
```

| variável | conteúdo | exemplo |
|---|---|---|
| `{{1}}` | primeiro nome da cliente | Bruna |
| `{{2}}` | número do pedido | 12 |
| `{{3}}` | nome do estabelecimento | Pizzaria do Zé |
| `{{4}}` | motivo escrito por quem cancelou | acabou a massa |

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
Nos do pedido: 5 no pedido novo e no confirmado, 3 no "a caminho" e no
"pronto", e 4 no cancelado. Os nomes deles estão no `modelo_de()` do
`37_pedidos.sql`.
