# saude — o check-up do sistema, para o monitor de fora

Endereço (público, sem login):

```
https://ialjrnighxntuirzmppt.supabase.co/functions/v1/saude
```

- **200**: tudo certo (ou só "atenção", que não merece alerta).
- **503**: problema. O monitor avisa você.

O corpo diz o nível e as chaves do que está errado, sem nenhum dado de salão:

```json
{ "nivel": "problema", "problemas": ["despertador"], "atencao": [], "verificadoEm": "…" }
```

| Chave | O que é |
|---|---|
| `banco` | o banco não respondeu |
| `despertador` | o pg_cron da fila (`agendapro-notificacoes`) não existe, está pausado, parou ou está falhando |
| `funcao_envio` | a função `enviar-notificacoes` recusa o despertador (401 = CRON_SEGREDO, 404 = não publicada, 503 = sem token do WhatsApp) |
| `fila` | há mensagem atrasada (devia ter saído há mais de 5 minutos) |
| `falhas` | as mensagens estão falhando na Meta (token vencido, conta bloqueada, modelo pausado…) |

O que está errado e **o que fazer** aparece no `admin.html`, no cartão
**Saúde do sistema**.

## Ligar o alerta no UptimeRobot (grátis)

1. Crie a conta em **uptimerobot.com**.
2. **New monitor** → tipo **HTTP(s)**.
3. **URL**: o endereço acima. **Intervalo**: 5 minutos.
4. Em **Alert contacts**, marque o seu e-mail (e o app do UptimeRobot no
   celular, se quiser notificação).
5. Salve. Ele avisa quando o endereço responder 503 e quando voltar a 200.

Faça um segundo monitor, do mesmo jeito, com
`https://www.agendaprogestao.com.br` — esse vigia se o site está no ar.

## Publicação

Sai junto das outras pelo workflow **Publicar as funções** (GitHub →
Actions), com `--no-verify-jwt`: o monitor não tem token do Supabase.
