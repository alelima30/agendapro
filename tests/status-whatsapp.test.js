/* ===========================================================================
   AgendaPro — o webhook de status não acredita em quem bate na porta

     node tests/status-whatsapp.test.js

   O endereço é público por obrigação: a Meta precisa alcançá-lo sem login.
   Qualquer pessoa na internet pode fazer POST nele dizendo "esta mensagem foi
   lida" ou "esta mensagem falhou".

   O segundo é o que dói: `falhou` DEVOLVE COTA, porque `mensagens_no_mes()`
   conta só enviado/entregue/lido. Um curl repetido seria mensagem de graça
   para sempre. O que separa o aviso da Meta do curl de qualquer um é uma
   função só — e é esta.

   Este arquivo importa o MESMO módulo que o Deno importa. Não é uma cópia da
   lógica: é a lógica.
   =========================================================================== */
import { assinaturaConfere, desafioConfere, statusesDoAviso,
         hmacHex, iguaisEmTempoConstante }
  from '../supabase/functions/status-whatsapp/assinatura.js';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
const falso   = (m, c, d) => !c ? ok(m) : nao(m, d);
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
const secao = t => console.log('\n' + t);

const SEGREDO = 'app-secret-do-painel-da-meta';

// Um aviso como a Meta manda: envelope fundo, statuses lá no fim.
const aviso = (statuses) => ({
  object: 'whatsapp_business_account',
  entry: [{
    id: '1234567890',
    changes: [{
      field: 'messages',
      value: {
        messaging_product: 'whatsapp',
        metadata: { display_phone_number: '5511999999999', phone_number_id: '99' },
        statuses,
      },
    }],
  }],
});

// Assina como a Meta assinaria: HMAC do corpo CRU.
async function assinado(corpo, { segredo = SEGREDO } = {}){
  const corpoBruto = JSON.stringify(corpo);
  return { corpoBruto,
           cabecalho: 'sha256=' + await hmacHex(segredo, corpoBruto) };
}

/* ══════════════════════════════════════════════════════════════════════════
   1. O AVISO LEGÍTIMO PASSA
   Sem esta primeira asserção, todas as recusas abaixo ficariam verdes com uma
   função que devolvesse `false` sempre — e a Meta nunca conseguiria falar.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O aviso de verdade passa');

const bom = await assinado(aviso([{ id:'wamid.AAA', status:'delivered' }]));
verdade('assinatura correta é aceita',
  await assinaturaConfere({ segredo: SEGREDO, ...bom }));

verdade('e com o hex em maiúsculas também',
  await assinaturaConfere({ segredo: SEGREDO, corpoBruto: bom.corpoBruto,
    cabecalho: bom.cabecalho.toUpperCase() }));

verdade('e com espaço em volta',
  await assinaturaConfere({ segredo: SEGREDO, corpoBruto: bom.corpoBruto,
    cabecalho: '  ' + bom.cabecalho + '  ' }));

/* ══════════════════════════════════════════════════════════════════════════
   2. O QUE TEM QUE SER RECUSADO
   ══════════════════════════════════════════════════════════════════════════ */
secao('O que não passa');

falso('cabeçalho vazio',
  await assinaturaConfere({ segredo: SEGREDO, corpoBruto: bom.corpoBruto, cabecalho: '' }));
falso('cabeçalho sem o prefixo sha256=',
  await assinaturaConfere({ segredo: SEGREDO, corpoBruto: bom.corpoBruto,
    cabecalho: bom.cabecalho.slice(7) }));
falso('assinatura que não é hexadecimal',
  await assinaturaConfere({ segredo: SEGREDO, corpoBruto: bom.corpoBruto,
    cabecalho: 'sha256=' + 'z'.repeat(64) }));
falso('assinatura com tamanho errado',
  await assinaturaConfere({ segredo: SEGREDO, corpoBruto: bom.corpoBruto,
    cabecalho: 'sha256=deadbeef' }));

// Assinado com OUTRO segredo: é o caso de quem descobriu o formato mas não a
// chave. É o ataque realista.
{
  const chutado = await assinado(aviso([{ id:'wamid.AAA', status:'read' }]),
    { segredo: 'chutei-o-app-secret' });
  falso('assinado com outro segredo é recusado',
    await assinaturaConfere({ segredo: SEGREDO, ...chutado }));
}

/* ⚠ TROCAR O CORPO DEPOIS DE ASSINAR.
   O ataque provável não é forjar o HMAC do zero: é pegar um aviso legítimo
   ("wamid.AAA foi entregue") e trocar o conteúdo — o id da mensagem, ou o
   status para `failed`, que devolve cota. Se o corpo não entrasse no HMAC,
   funcionaria. */
{
  const outro = JSON.stringify(aviso([{ id:'wamid.AAA', status:'failed' }]));
  falso('aviso legítimo com o corpo trocado é recusado',
    await assinaturaConfere({ segredo: SEGREDO,
      cabecalho: bom.cabecalho, corpoBruto: outro }));
}
{
  // Um byte só de diferença.
  falso('e um caractere trocado no corpo já derruba',
    await assinaturaConfere({ segredo: SEGREDO, cabecalho: bom.cabecalho,
      corpoBruto: bom.corpoBruto.replace('wamid.AAA', 'wamid.AAB') }));
}

/* ══════════════════════════════════════════════════════════════════════════
   3. SEM SEGREDO CONFIGURADO, NADA PASSA
   É o estado entre subir a função e cadastrar a URL no painel da Meta. Se
   "sem segredo" significasse "aceita tudo", o endereço ficaria aberto
   exatamente enquanto ninguém está olhando.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Sem META_APP_SECRET configurado');

falso('sem segredo, o aviso é recusado',
  await assinaturaConfere({ segredo: '', ...bom }));
falso('e nem um aviso perfeito passa',
  await assinaturaConfere({ segredo: undefined, ...bom }));

/* ══════════════════════════════════════════════════════════════════════════
   4. O APERTO DE MÃO DO CADASTRO
   ══════════════════════════════════════════════════════════════════════════ */
secao('O aperto de mão do cadastro da URL');

const TOKEN = 'a-frase-que-eu-digitei-no-painel';
verdade('token certo e modo subscribe passa',
  desafioConfere({ modo:'subscribe', token:TOKEN, esperado:TOKEN }));
falso('token errado não',
  desafioConfere({ modo:'subscribe', token:'outra-frase', esperado:TOKEN }));
falso('modo que não é subscribe não',
  desafioConfere({ modo:'unsubscribe', token:TOKEN, esperado:TOKEN }));
falso('sem WHATSAPP_VERIFY_TOKEN configurado, nada passa',
  desafioConfere({ modo:'subscribe', token:TOKEN, esperado:'' }));
falso('nem com o token vazio dos dois lados',
  desafioConfere({ modo:'subscribe', token:'', esperado:'' }));

/* ══════════════════════════════════════════════════════════════════════════
   5. DESEMBRULHAR O AVISO
   O envelope da Meta é fundo, e cada nível pode faltar. Um webhook que
   estoura com payload estranho é um webhook que a Meta desativa.
   ══════════════════════════════════════════════════════════════════════════ */
secao('O que sai do envelope');

igual('delivered vira entregue',
  statusesDoAviso(aviso([{ id:'wamid.A', status:'delivered' }])),
  [{ wamId:'wamid.A', status:'entregue', codigo:null, msg:null }]);

igual('read vira lido',
  statusesDoAviso(aviso([{ id:'wamid.B', status:'read' }])),
  [{ wamId:'wamid.B', status:'lido', codigo:null, msg:null }]);

igual('failed vira falhou, com o motivo',
  statusesDoAviso(aviso([{ id:'wamid.C', status:'failed',
    errors:[{ code:131026, title:'Message undeliverable' }] }])),
  [{ wamId:'wamid.C', status:'falhou', codigo:'131026',
     msg:'Message undeliverable' }]);

/* `sent` chega junto de todo envio e é ignorado de propósito: o worker já
   escreveu 'enviado', com a hora certa, quando a API respondeu OK. */
igual('sent é ignorado', statusesDoAviso(aviso([{ id:'wamid.D', status:'sent' }])), []);
igual('status que a Meta inventar amanhã é ignorado',
  statusesDoAviso(aviso([{ id:'wamid.E', status:'deleted' }])), []);
igual('status sem id é ignorado',
  statusesDoAviso(aviso([{ status:'delivered' }])), []);

// Vários numa tacada só, que é como a Meta agrupa.
igual('vários avisos no mesmo pacote saem todos',
  statusesDoAviso(aviso([
    { id:'wamid.1', status:'delivered' },
    { id:'wamid.2', status:'sent' },
    { id:'wamid.3', status:'read' },
  ])).map(s => s.wamId + ':' + s.status),
  ['wamid.1:entregue', 'wamid.3:lido']);

/* ⚠ MENSAGEM DE CLIENTE NÃO É DA CONTA DESTE ARQUIVO.
   `value.messages` é por onde chega gente escrevendo para o salão. Responder
   a isso é chatbot, que está fora desta fase de propósito. */
igual('mensagem que chega de cliente é ignorada',
  statusesDoAviso({ object:'whatsapp_business_account', entry:[{ changes:[{
    value:{ messages:[{ from:'5511999999999', text:{ body:'oi' } }] } }] }] }),
  []);

secao('E nada de payload estranho derruba a função');
igual('corpo vazio', statusesDoAviso({}), []);
igual('nulo', statusesDoAviso(null), []);
igual('texto no lugar do objeto', statusesDoAviso('sei lá'), []);
igual('entry que não é lista', statusesDoAviso({ entry:'x' }), []);
igual('changes que não é lista', statusesDoAviso({ entry:[{ changes:{} }] }), []);
igual('statuses que não é lista',
  statusesDoAviso({ entry:[{ changes:[{ value:{ statuses:'x' } }] }] }), []);
igual('value ausente', statusesDoAviso({ entry:[{ changes:[{}] }] }), []);

/* ══════════════════════════════════════════════════════════════════════════
   6. A COMPARAÇÃO É DE TAMANHO FIXO
   ══════════════════════════════════════════════════════════════════════════ */
secao('A comparação não vaza pelo tempo');
verdade('iguais dão true', iguaisEmTempoConstante('abcdef', 'abcdef'));
falso('tamanhos diferentes dão false', iguaisEmTempoConstante('abc', 'abcdef'));
falso('mesmo tamanho e conteúdo diferente dá false',
  iguaisEmTempoConstante('abcdef', 'abcdeg'));
falso('e nada que não seja texto passa', iguaisEmTempoConstante(null, null));

console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
