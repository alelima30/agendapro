/* ===========================================================================
   AgendaPro — a conferência da assinatura do aviso do Mercado Pago

   ── POR QUE ESTE ARQUIVO É .js E NÃO .ts ───────────────────────────────────
   Porque ele precisa rodar nos DOIS lados: o Deno importa daqui, e o teste
   (tests/webhook-assinatura.test.js) importa exatamente o mesmo arquivo, no
   Node. Sem build, sem transpilar, sem duas cópias.

   E precisa ser testado. Esta função é o que separa "o Mercado Pago avisou
   que pagaram" de "alguém na internet escreveu que pagaram" — o endereço do
   webhook é público por obrigação. Uma cópia dela num arquivo que ninguém
   consegue executar fora do Deno seria a parte mais crítica do sistema sendo
   a única sem teste.

   Usa só WebCrypto, que Deno e Node 20+ têm nativamente.
   =========================================================================== */

/* O texto que o Mercado Pago assinou, exatamente nesta ordem e com estes
   pontos-e-vírgulas. Errar um caractere aqui faz TODO aviso legítimo ser
   recusado — e o sintoma seria "ninguém consegue assinar", dias depois. */
/* E sem as partes que não vieram: a regra do Mercado Pago é tirar do texto o
   valor que não estiver no aviso — `request-id:;` vazio faria a conta dar
   outra, e um aviso legítimo sem `x-request-id` seria recusado. */
export function manifesto(dataId, requestId, ts){
  return (dataId ? `id:${String(dataId).toLowerCase()};` : '')
       + (requestId ? `request-id:${requestId};` : '')
       + (ts ? `ts:${ts};` : '');
}

/* ⚠ Comparar com `===` vaza, pelo tempo, o tamanho do prefixo que bateu. É
   pouco por tentativa, e é explorável em cima de um endereço que aceita
   tentativas ilimitadas. Comparação de tamanho fixo custa nada. */
export function iguaisEmTempoConstante(a, b){
  if(typeof a !== 'string' || typeof b !== 'string') return false;
  if(a.length !== b.length) return false;
  let dif = 0;
  for(let i = 0; i < a.length; i++) dif |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return dif === 0;
}

export async function hmacHex(segredo, texto){
  const chave = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(segredo),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const bruto = await crypto.subtle.sign(
    'HMAC', chave, new TextEncoder().encode(texto));
  return [...new Uint8Array(bruto)]
    .map(b => b.toString(16).padStart(2, '0')).join('');
}

/* A conferência inteira. Devolve true só quando TUDO bate.

   `agoraMs` entra por parâmetro para o teste poder envelhecer um aviso sem
   mexer no relógio da máquina. */
export async function assinaturaConfere(opcoes){
  return (await conferirAssinatura(opcoes)).ok;
}

/* POR QUE recusou — ou `null`, quando confere. */
export async function motivoDaRecusa(opcoes){
  return (await conferirAssinatura(opcoes)).motivo;
}

/* A conferência com o relatório: { ok, motivo, variante, diag }.

   ── AS VARIAÇÕES, E POR QUE ELAS NÃO ABREM PORTA NENHUMA ──────────────────
   No primeiro Pix de verdade o aviso chegou do painel e a conta não bateu.
   Ou a chave colada no Supabase não é a do painel, ou o texto que o Mercado
   Pago assinou não é exatamente o que montamos — e "assinatura inválida" não
   diz qual. Então a conferência tenta, nesta ordem:

     1. a regra do Mercado Pago: id DA URL (sem ele, a parte sai), request-id
        se veio, ts;
     2. o id do CORPO, quando a URL não trouxe;
     3. sem o request-id — o cabeçalho pode ter sido reescrito no caminho até
        a função;
     4. cada uma com a chave aparada (espaço ou quebra de linha colados junto
        no Supabase).

   TODAS exigem a chave secreta: quem não a tem não acerta nenhuma. O id
   trocado continua recusado (ele entra na conta), e o aviso velho também (a
   janela vem antes). `variante` diz qual bateu, para o log mostrar — e a
   gente fixar a regra certa e tirar as outras. `diag` diz, quando nada bate,
   o que veio e o que não veio — sem nunca levar chave ou hash. */
export async function conferirAssinatura(
  { segredo, xSignature, xRequestId, dataId, dataIdCorpo,
    agoraMs = Date.now(), janelaSegundos = 600 }){

  const recusa = (motivo, diag) => ({ ok: false, motivo, variante: null, diag: diag || null });

  /* Sem segredo configurado não há o que conferir. Recusar é o certo: aceitar
     deixaria o endereço aberto justamente enquanto ninguém terminou de
     configurar — que é quando ninguém está olhando. */
  if(!segredo) return recusa('MP_WEBHOOK_SECRET não configurado');
  if(!xSignature) return recusa('sem o cabeçalho x-signature (aviso que não veio do webhook do painel)');
  const idUrl = dataId ? String(dataId) : '';
  const idCorpo = dataIdCorpo ? String(dataIdCorpo) : '';
  if(!idUrl && !idCorpo) return recusa('sem o id do pagamento');

  const partes = new Map();
  for(const p of String(xSignature).split(',')){
    const i = p.indexOf('=');
    if(i < 0) continue;
    partes.set(p.slice(0, i).trim(), p.slice(i + 1).trim());
  }
  const ts = partes.get('ts');
  const v1 = partes.get('v1');
  if(!ts || !v1) return recusa('o x-signature não traz ts e v1');

  /* Janela de tempo. Sem ela, um aviso legítimo capturado hoje pode ser
     reenviado daqui a um ano e a assinatura continuaria válida — para sempre.
     A idempotência do banco já cobriria o estrago, mas defesa em profundidade
     custa cinco linhas. */
  const idade = Math.abs(agoraMs / 1000 - Number(ts));
  if(!Number.isFinite(idade)) return recusa('ts não é número');
  if(idade > janelaSegundos) return recusa(`aviso fora da janela de ${janelaSegundos} s (${Math.round(idade)} s)`);

  const req = xRequestId ? String(xRequestId) : '';
  const textos = [['regra do Mercado Pago', manifesto(idUrl, req, ts)]];
  if(!idUrl && idCorpo) textos.push(['id do corpo', manifesto(idCorpo, req, ts)]);
  if(req) textos.push(['sem request-id', manifesto(idUrl || idCorpo, '', ts)]);

  const chaves = [['', segredo]];
  if(String(segredo).trim() !== segredo) chaves.push([' (chave aparada)', String(segredo).trim()]);

  for(const [nomeChave, chave] of chaves){
    for(const [nome, texto] of textos){
      if(iguaisEmTempoConstante(await hmacHex(chave, texto), v1)){
        return { ok: true, motivo: null, variante: nome + nomeChave, diag: null };
      }
    }
  }
  return recusa('a conta não bate com o MP_WEBHOOK_SECRET (chave diferente da do painel, ou do outro modo)', {
    idNaUrl: !!idUrl, idNoCorpo: !!idCorpo, temRequestId: !!req,
    tamanhoChave: String(segredo).length,
    chaveComEspaco: String(segredo).trim() !== segredo,
  });
}
