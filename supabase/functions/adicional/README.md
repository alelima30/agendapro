# `adicional` — contratar e cancelar módulos adicionais (o Crediário)

O dono contrata ou cancela um módulo adicional em **Meu plano → Módulos
adicionais**. A plataforma dá cortesia e preço especial no **admin**. Os três
passam por esta função, que roda no servidor.

| ordem | o quê | onde |
|---|---|---|
| 1 | a conta: pode? quanto a mensalidade passa a ser? (não grava) | `preparar_adicional` (46) |
| 2 | o valor da assinatura no cartão, se o salão paga no cartão | `PUT /preapproval/{id}` no Mercado Pago |
| 3 | gravar, conferindo que a conta não mudou no meio | `aplicar_adicional` (46) |

Se o passo 3 falhar depois do 2, o valor do cartão volta ao de antes.

Quem paga no Pix não tem nada no Mercado Pago para mudar: o próximo Pix já
nasce com o valor novo (`abrir_cobranca`, 13).

## Publicar

É publicada sozinha pelo GitHub (Actions → "Publicar as funções") quando muda
no `main`. Na mão:

```
supabase functions deploy adicional --project-ref SEU_REF
```

Usa os segredos que já existem: `MP_ACCESS_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`
e `SUPABASE_ANON_KEY`. Nenhum segredo novo.

## O que a tela manda

Só `salaoId`, `adicional` (`crediario`) e `acao` (`contratar`, `cancelar`; a
plataforma também `cortesia`, `sem_cortesia`, `preco` com `preco`). O preço do
módulo nunca vem da tela: é lido do banco.
