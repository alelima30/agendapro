# A assinatura no cartão — como colocar no ar

Renovação automática pelo **Mercado Pago Assinaturas** (pré-aprovação). São
duas funções novas, e as duas rodam **no servidor**:

| Pasta | O que faz |
|---|---|
| `assinar-cartao` | o dono clica → cria a pré-aprovação e devolve o link de autorização |
| `cancelar-cartao` | o dono desliga → cancela **no Mercado Pago** e só então no banco |

O `webhook-mp`, que já existia, passa a entender mais dois avisos: a
autorização do cartão e a cobrança mensal.

---

## ⚠ Nenhum dado de cartão passa pelo AgendaPro

Não há campo de número, CVV ou validade em nenhum arquivo deste projeto. O
dono digita o cartão **na página do Mercado Pago**, e o que volta para cá é um
identificador de assinatura.

Isso não é economia de trabalho — é o que faz o AgendaPro não ser responsável
por guardar cartão de ninguém, e não ter que responder se algo vazar. De
quebra, cartão vencido, cartão trocado, tentativa recusada e nova tentativa
são problema deles: essa lista inteira é código que não existe aqui.

---

## 1. Do lado do Mercado Pago

Na mesma aplicação que você já usa para o Pix
(**[Suas integrações](https://www.mercadopago.com.br/developers/panel)**):

1. Em **Webhooks**, na URL que já está cadastrada
   (`https://SEU_REF.supabase.co/functions/v1/webhook-mp`), marque **mais dois
   eventos**, além de *Pagamentos*:

   | Evento | Para quê |
   |---|---|
   | **Planos e Assinaturas** (`subscription_preapproval`) | liga o cartão quando o dono autoriza, e desliga quando ele cancela |
   | **Pagamentos de assinaturas** (`subscription_authorized_payment`) | a cobrança de todo mês |

   > **Sem o segundo evento a assinatura funciona no mês 1 e para no mês 2**, em
   > silêncio, com o salão achando que está em dia. É o defeito mais caro
   > possível de deixar passar aqui, porque só aparece trinta dias depois e
   > parece culpa do cliente.

2. O `MP_WEBHOOK_SECRET` continua o mesmo — é por URL, não por evento.

### A conta precisa poder receber assinaturas

Assinaturas exigem a conta com dados fiscais completos, como o Pix. E há uma
recusa que confunde todo mundo na primeira tentativa: **o Mercado Pago não
deixa alguém assinar de si mesmo**. Se o e-mail do responsável no cadastro do
salão for o mesmo da conta que recebe, o pedido volta com *"Invalid users
involved"*. A borda traduz isso numa frase legível — mas se você estiver
testando com a sua própria conta, é isso.

---

## 2. Instalar

```bash
supabase functions deploy assinar-cartao  --project-ref SEU_REF
supabase functions deploy cancelar-cartao --project-ref SEU_REF
supabase functions deploy webhook-mp      --project-ref SEU_REF --no-verify-jwt
```

> `--no-verify-jwt` **só** no `webhook-mp`. As outras duas são chamadas pelo
> painel, com o token de sessão do dono, e é ele que diz quem está pedindo.

Sem a CLI, colando no editor do painel do Supabase:

- `assinar-cartao` e `cancelar-cartao` são **um arquivo só** — cole o
  `index.ts` de cada pasta, direto;
- `webhook-mp` importa o `assinatura.js` ao lado, então precisa da versão
  costurada: rode `bash supabase/montar-funcoes.sh` e cole
  `supabase/functions/dist/webhook-mp.ts`.

O `dist/` é **gerado** e não vai para o Git de propósito — ele é cópia, e cópia
versionada vira uma segunda verdade sobre o que a função faz.

E o SQL, no **SQL Editor**:

```
supabase/23_assinatura_cartao.sql
```

(ou o `98_modulos.sql`, que já traz este junto com os outros módulos).

---

## 3. As variáveis de ambiente

Só uma é nova; as outras já estão lá para o Pix.

| Nome | Onde achar |
|---|---|
| `PAINEL_URL` | **novo, e obrigatório**: para onde o Mercado Pago devolve o dono depois de autorizar. Ex.: `https://seu-usuario.github.io/agendapro/app.html` |
| `MP_ACCESS_TOKEN` | já configurada |
| `SUPABASE_SERVICE_ROLE_KEY` | já vem preenchida |

O `MP_WEBHOOK_URL` **não** é usado aqui, e isso é de propósito: os avisos da
assinatura chegam pelo webhook cadastrado no painel do Mercado Pago, que é o
único que vem assinado. Mandar a URL no pedido ligaria uma segunda via de
entrega, no formato antigo, que o `webhook-mp` recusaria com 401 — enchendo de
ruído o log reservado para tentativa de fraude.

Sem `PAINEL_URL`, a borda cai no `PAINEL_ORIGEM`; sem os dois, ela responde
503 com uma frase pedindo para pagar no Pix — a pré-aprovação exige um
`back_url`, e inventar um levaria o dono para uma página que não existe.

---

## 4. Como o dinheiro anda, mês a mês

```
   o dono clica "Assinar no cartão"
        │
        ├─ assinar-cartao  →  POST /preapproval  (status: pending)
        │                     devolve init_point → abre a página do MP
        │
   o dono autoriza lá
        │
        ├─ webhook  subscription_preapproval (authorized)
        │     └─ lê /preapproval/{id} na API  →  ligar_cartao(salão, id)
        │
        ├─ webhook  subscription_authorized_payment   ← todo mês, sozinho
        │     └─ lê /authorized_payments/{id} na API
        │        →  registrar_recorrencia(...)  cria a cobrança do mês
        │           e entrega ao registrar_pagamento(), que estende +1 mês
        │
   o dono desliga
        └─ cancelar-cartao  →  PUT /preapproval/{id} {status: cancelled}
                            →  e SÓ ENTÃO cancelar_cartao() no banco
```

Três coisas que valem reparar:

**A borda não liga o cartão.** Chegar em `assinar-cartao` é ter clicado num
botão; não é ter autorizado nada. Quem liga é o webhook, com o dado relido da
API do Mercado Pago. Se fosse a borda, bastaria clicar e fechar a aba para o
salão constar como pagante.

**A cobrança do mês 2 não tem clique nenhum atrás dela.** É por isso que
existe `registrar_recorrencia()`: ela cria a linha do mês — com o preço lido
de `planos`, nunca do aviso — e só então entrega para o caminho que já
funcionava no Pix.

**Cancelar bate no Mercado Pago primeiro.** Efeito externo antes do estado
local. Se a ordem fosse a outra, um erro de rede deixaria o painel dizendo
"renovação desligada" com a fatura do dono continuando a chegar todo mês.

---

## 5. Trocar de plano

Não dá para trocar direto: é **desligar e assinar de novo**, dois cliques. A
borda recusa uma segunda pré-aprovação no mesmo salão de propósito — duas
ativas é cobrança dobrada todo mês, e o dono só descobre na fatura.

---

## 6. Conferir que está de pé

```bash
bash tests/rodar.sh      # cartao.test.sql e bordas.test.sql, no banco
```

E de ponta a ponta, com credenciais `TEST-` e um usuário de teste:

1. assine no cartão e autorize na página do Mercado Pago;
2. no log de `webhook-mp`, procure `webhook-mp preapproval ... {"ok":true`;
3. `select mp_preapproval, cartao_desde, vence_em from assinaturas where salao_id = ...`;
4. no painel do Mercado Pago, a assinatura tem que aparecer como **autorizada**;
5. desligue pelo painel e confira que ela ficou **cancelada** lá também — este
   é o passo que ninguém testa e o único que o dono percebe no bolso.

---

## O que este desenho protege, e como

| Ataque | O que segura |
|---|---|
| escolher a própria mensalidade | `transaction_amount` vem de `planos`, no banco; a tela manda só o código do plano |
| marcar-se como pagante sem pagar | a borda não liga cartão; quem liga é o webhook, com o dado relido da API |
| forjar o aviso de autorização | HMAC-SHA256 com `MP_WEBHOOK_SECRET`, o mesmo do Pix |
| mentir no corpo do aviso | o `external_reference` que diz de qual salão é vem da API do Mercado Pago |
| reenviar o aviso da cobrança mensal | `cobrancas.mp_id` é único; a segunda chegada responde `ja_registrada` |
| apontar a assinatura para outro salão | `ux_assinatura_preapproval` é único, e `ligar_cartao` recusa pré-aprovação de outro |
| pagar o plano pequeno e levar o grande | o valor é conferido contra o preço do plano antes de ativar |
| ligar cartão pelo console do navegador | `ligar_cartao`, `registrar_recorrencia` e `desligar_cartao` são negadas a `anon` e `authenticated` |
| descobrir o e-mail do dono de qualquer salão | `preparar_cartao` confere o vínculo de quem pediu, e não é alcançável do navegador |
| um mês recusado travar os seguintes | o índice de cobrança aberta ignora `metodo = 'cartao'` |
