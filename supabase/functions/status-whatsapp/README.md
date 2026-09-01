# O que a Meta conta depois do envio

O `enviar-notificacoes` manda e escreve **enviado**. Esta função é a outra
metade: recebe o que a Meta conta depois e move a linha para **entregue**,
**lido** ou **falhou**.

Sem ela esses três estados não existem — e o painel diz isso, em vez de
estimar.

---

## Por que o `falhou` é o que mais importa

`delivered` e `read` são informação. `failed` é **correção**.

A Meta aceita a mensagem, devolve um `wam_id`, e a linha vira `enviado` — já
tendo custado cota. Só depois ela descobre que não dá para entregar: número que
não tem WhatsApp, bloqueio, aparelho que nunca voltou. **Sem esta função, essa
linha diz "enviado" para sempre**, e o salão acha que avisou.

E a cota volta sozinha: `mensagens_no_mes()` conta só enviado/entregue/lido,
então sair para `falhou` devolve o crédito sem nenhuma conta a mais. Mensagem
que não chegou não pode custar.

---

## Os dois segredos

No painel do Supabase, em **Edge Functions → Secrets**:

```
META_APP_SECRET          o App Secret do app (Configurações → Básico).
                         NÃO é o token de envio.
WHATSAPP_VERIFY_TOKEN    uma frase sua, qualquer. É a mesma que você vai
                         digitar no painel da Meta ao cadastrar a URL.
```

> ⚠ **Sem `META_APP_SECRET`, nada passa** — nem um aviso legítimo. É de
> propósito: o endereço é público por obrigação, e "sem segredo = aceita tudo"
> deixaria a porta aberta exatamente enquanto ninguém terminou de configurar.
>
> Nenhum destes valores pode entrar no `config.js` nem em qualquer arquivo do
> painel. O painel é HTML servido do GitHub Pages: tudo o que chega nele é
> público por construção.

Publicar:

```bash
supabase functions deploy status-whatsapp --no-verify-jwt
```

`--no-verify-jwt` é obrigatório aqui: a Meta chama sem token do Supabase. Quem
guarda a porta é a assinatura, não o JWT.

---

## Cadastrar a URL na Meta

Em **WhatsApp → Configuração → Webhooks → Editar**:

```
URL de retorno de chamada   https://SEU-PROJETO.supabase.co/functions/v1/status-whatsapp
Token de verificação        a mesma frase que você pôs em WHATSAPP_VERIFY_TOKEN
```

Clique em **Verificar e salvar**. A Meta faz um GET com o token; a função
devolve o desafio em texto puro e o cadastro fecha. Se der erro, é quase sempre
o token diferente dos dois lados.

Depois, em **Gerenciar**, assine o campo **`messages`** — é por ele que os
status chegam. É o único que interessa: mensagem que a cliente escreve para o
salão chega no mesmo campo e é **ignorada de propósito**, porque responder a
isso é chatbot, que está fora desta fase.

---

## Como conferir que está funcionando

Depois de uma mensagem sair de verdade:

```sql
select tipo, status, wam_id, erro_codigo, erro_msg, enviado_em
  from public.notificacoes
 where wam_id is not null
 order by enviado_em desc
 limit 10;
```

O caminho normal é `enviado → entregue → lido`, em segundos. Se ficar parado em
`enviado` por muito tempo, o webhook não está chegando — confira o cadastro e o
campo `messages` assinado.

---

## As três travas

1. **Assinatura.** `X-Hub-Signature-256` é um HMAC-SHA256 do corpo cru feito
   com o App Secret. Sem bater, é 401. Está em `assinatura.js`, ao lado, e é
   testada em `tests/status-whatsapp.test.js` — no Node, importando o mesmo
   arquivo que o Deno importa.

2. **O `wam_id`.** Mesmo com a assinatura boa, o corpo não escolhe qual linha
   muda: ele diz um id que a Meta gerou no envio, e que só casa com uma linha
   que este sistema mandou.

3. **O banco.** `notificacao_status()` nunca anda para trás — um `delivered`
   atrasado não desfaz um `lido` — e nunca ressuscita uma linha cancelada.

---

## Por que quase tudo responde 200

Aviso de mensagem que não é nossa, status que não tratamos, corpo estranho:
tudo `200`. A Meta reenvia o que não devolve 2xx, em escala crescente, e
**desativa o webhook** depois de insistir bastante. O `401` é reservado para
assinatura errada, que é tentativa de fraude e tem que constar no log.
