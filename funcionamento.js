/* ===========================================================================
   AgendaPro — horários de funcionamento (e as formas de pagamento)
   ---------------------------------------------------------------------------
   Guardado em `saloes.cfg.funcionamento`, um objeto com uma chave por dia da
   semana — "0" é domingo, como o `getDay()` do JavaScript e o `dow` do
   Postgres — e, em cada dia, a lista de períodos:

       { "1": [["08:00","12:00"], ["13:30","18:00"]], "0": [], ... }

   Lista vazia é dia fechado. Vários períodos no mesmo dia são o almoço.

   ── POR QUE UM ARQUIVO SÓ ──────────────────────────────────────────────────
   A mesma pergunta — "está aberto agora? quando abre?" — é respondida em dois
   lugares: na página da cliente e na prévia do painel. Duas contas escritas
   separadas divergem na primeira borda (meio-dia, meia-noite, o intervalo do
   almoço) e a prévia passa a prometer o que a página não faz. É a lição que
   este projeto já pagou com as cores e com o preço.

   ── O QUE NÃO ESTÁ AQUI, DE PROPÓSITO ──────────────────────────────────────
   Nenhum horário de exemplo. Salão sem horário cadastrado recebe `null` e a
   página esconde o status inteiro — "08:00 – 18:00" inventado seria a casa
   prometendo uma porta aberta que ninguém combinou.

   E nada de período que atravessa a meia-noite (22:00 – 02:00). O editor
   recusa com a instrução de dividir em dois dias; aceitar faria "aberto
   agora" depender de olhar o dia anterior, e é a conta que mais erra.
   =========================================================================== */

(function (global) {
'use strict';

// A ordem da semana como se lê num balcão: segunda primeiro, domingo por último.
const ORDEM = [1, 2, 3, 4, 5, 6, 0];
const NOMES = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira',
               'Quinta-feira', 'Sexta-feira', 'Sábado'];
// Como o dia aparece no meio de uma frase: "Abre segunda às 08:00".
const NA_FRASE = ['domingo', 'segunda', 'terça', 'quarta', 'quinta',
                  'sexta', 'sábado'];

const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;

/* "HH:MM" em minutos do dia. O fechamento "00:00" quer dizer MEIA-NOITE, o
   fim do dia (1440) — é o único jeito de dizer "até meia-noite" com o seletor
   de hora do celular, que não oferece 24:00. */
function minutos(txt, ehFim){
  if(!HORA.test(String(txt || ''))) return null;
  const [h, m] = txt.split(':').map(Number);
  const v = h * 60 + m;
  return (ehFim && v === 0) ? 1440 : v;
}
function hhmm(min){
  const v = min % 1440;
  return String(Math.floor(v / 60)).padStart(2, '0') + ':'
       + String(v % 60).padStart(2, '0');
}

/* ═══════════════════════════════════════════════════════════════════════════
   O QUE VEM DO BANCO, PENEIRADO

   Devolve { 0: [{ini, fim}], ..., 6: [...] } em minutos, cada dia ordenado e
   com os períodos que se tocam ou se cruzam emendados — ou `null` quando não
   há NENHUM dia aberto. `null` é "não informado", e a página esconde o
   status; um salão com todos os dias fechados seria o cartão FECHADO para
   sempre na primeira dobra da página, que é pior do que não dizer nada.

   Aceita lixo sem quebrar: o `cfg` é jsonb e já recebeu de tudo neste
   projeto. Período torto é descartado, dia torto vira fechado.
   ═══════════════════════════════════════════════════════════════════════════ */
function normalizar(cru){
  if(!cru || typeof cru !== 'object' || Array.isArray(cru)) return null;
  const dias = {};
  let algum = false;
  for(let d = 0; d <= 6; d++){
    const lista = Array.isArray(cru[d]) ? cru[d] : (Array.isArray(cru[String(d)]) ? cru[String(d)] : []);
    const ps = [];
    for(const p of lista){
      const a = Array.isArray(p) ? p[0] : (p && p.ini);
      const b = Array.isArray(p) ? p[1] : (p && p.fim);
      const ini = minutos(a, false), fim = minutos(b, true);
      if(ini === null || fim === null || fim <= ini) continue;
      ps.push({ ini, fim });
    }
    ps.sort((x, y) => x.ini - y.ini);
    const juntos = [];
    for(const p of ps){
      const ult = juntos[juntos.length - 1];
      if(ult && p.ini <= ult.fim) ult.fim = Math.max(ult.fim, p.fim);
      else juntos.push({ ini: p.ini, fim: p.fim });
    }
    dias[d] = juntos;
    if(juntos.length) algum = true;
  }
  return algum ? dias : null;
}

/* ═══════════════════════════════════════════════════════════════════════════
   O QUE O EDITOR DO PAINEL RECUSA

   Recebe o formato do banco ("HH:MM") e devolve as queixas, dia a dia, na
   língua de quem está preenchendo. O `normalizar()` descartaria esses
   períodos em silêncio — e o dono veria o horário sumir depois de salvar sem
   entender por quê. Aqui ele lê o motivo antes.
   ═══════════════════════════════════════════════════════════════════════════ */
function validar(cru){
  const queixas = [];
  for(const d of ORDEM){
    const lista = (cru && Array.isArray(cru[d])) ? cru[d] : [];
    const ps = [];
    lista.forEach(([a, b], i) => {
      const n = lista.length > 1 ? ' (' + (i + 1) + 'º horário)' : '';
      if(!HORA.test(String(a || '')) || !HORA.test(String(b || ''))){
        queixas.push(NOMES[d] + n + ': preencha a abertura e o fechamento.');
        return;
      }
      const ini = minutos(a, false), fim = minutos(b, true);
      if(fim <= ini){
        queixas.push(NOMES[d] + n + ': o fechamento precisa ser depois da '
          + 'abertura. Para passar da meia-noite, feche às 00:00 e abra de '
          + 'novo no dia seguinte.');
        return;
      }
      ps.push({ ini, fim });
    });
    ps.sort((x, y) => x.ini - y.ini);
    for(let i = 1; i < ps.length; i++){
      if(ps[i].ini < ps[i - 1].fim){
        queixas.push(NOMES[d] + ': dois horários se cruzam ('
          + hhmm(ps[i - 1].ini) + '–' + hhmm(ps[i - 1].fim) + ' e '
          + hhmm(ps[i].ini) + '–' + hhmm(ps[i].fim) + ').');
      }
    }
  }
  return queixas;
}

/* ═══════════════════════════════════════════════════════════════════════════
   AGORA, NO RELÓGIO DO SALÃO

   O instante vem do relógio do APARELHO, e é convertido para o fuso do
   salão. A cliente que viajou, ou que está com o celular em outro fuso, tem
   que ver "aberto" quando a porta do salão está aberta — e não quando a do
   hotel dela estaria.

   `hourCycle:'h23'` e não `hour12:false`, pelo mesmo motivo do `noFuso()`
   da página: alguns navegadores devolvem "24" para a meia-noite.
   ═══════════════════════════════════════════════════════════════════════════ */
const DOW = { Sun:0, Mon:1, Tue:2, Wed:3, Thu:4, Fri:5, Sat:6 };
function agora(fuso, quando){
  const d = quando instanceof Date ? quando : new Date(quando || Date.now());
  const partes = new Intl.DateTimeFormat('en-US', {
    timeZone: fuso || 'America/Sao_Paulo', weekday:'short',
    hour:'2-digit', minute:'2-digit', hourCycle:'h23',
  }).formatToParts(d);
  const g = t => (partes.find(x => x.type === t) || {}).value;
  return { dow: DOW[g('weekday')], min: (Number(g('hour')) % 24) * 60 + Number(g('minute')) };
}

/* ═══════════════════════════════════════════════════════════════════════════
   ABERTO OU FECHADO, E A FRASE DO LADO

       ABERTO   Hoje, até 18:00
       FECHADO  Abre às 13:30            (no intervalo do almoço)
       FECHADO  Abre amanhã às 08:00
       FECHADO  Abre segunda às 08:00    (sábado à noite, domingo fechado)

   `func` é o que o `normalizar()` devolve. `null` devolve `null`: não há o
   que dizer, e quem chama esconde o cartão.

   ⚠ O FIM É ABERTO: às 18:00 em ponto, com o horário até 18:00, está FECHADO.
   É o mesmo contrato da faixa de preço (08:00–12:00 não inclui o meio-dia),
   e o único em que dois períodos encostados — 08:00–12:00 e 12:00–18:00 —
   não se contradizem sobre o meio-dia.
   ═══════════════════════════════════════════════════════════════════════════ */
function estado(func, ag){
  if(!func || !ag || !(ag.dow >= 0)) return null;
  const hojeP = func[ag.dow] || [];
  for(const p of hojeP){
    if(ag.min >= p.ini && ag.min < p.fim){
      /* Aberto até a meia-noite e abrindo de novo à 00:00: a porta não fecha
         na virada. Diz o fechamento de verdade, amanhã. */
      if(p.fim === 1440){
        const amanha = func[(ag.dow + 1) % 7] || [];
        if(amanha.length && amanha[0].ini === 0)
          return { aberto: true, detalhe: 'Até amanhã às ' + hhmm(amanha[0].fim) };
        return { aberto: true, detalhe: 'Hoje, até meia-noite' };
      }
      return { aberto: true, detalhe: 'Hoje, até ' + hhmm(p.fim) };
    }
  }
  const depois = hojeP.find(p => p.ini > ag.min);
  if(depois) return { aberto: false, detalhe: 'Abre às ' + hhmm(depois.ini) };
  for(let k = 1; k <= 7; k++){
    const d = (ag.dow + k) % 7;
    const ps = func[d] || [];
    if(!ps.length) continue;
    const quando = k === 1 ? 'amanhã'
                 : k === 7 ? 'na próxima ' + NA_FRASE[d]
                 : NA_FRASE[d];
    return { aberto: false, detalhe: 'Abre ' + quando + ' às ' + hhmm(ps[0].ini) };
  }
  return { aberto: false, detalhe: 'Sem horário de atendimento' };
}

// "08:00 – 12:00" por período, ou null para dia fechado.
function periodosDoDia(func, d){
  const ps = (func && func[d]) || [];
  return ps.length ? ps.map(p => hhmm(p.ini) + ' – ' + hhmm(p.fim)) : null;
}

/* ═══════════════════════════════════════════════════════════════════════════
   AS FORMAS DE PAGAMENTO

   Moram aqui porque são a mesma família de informação — o que a casa diz
   sobre si mesma, fora da agenda — e porque painel e página precisam da
   mesma lista com os mesmos nomes. Guardado em `cfg.pagamentos`:

       { formas: ['pix', 'credito'], obs: 'Parcelamos em até 3x' }

   Sem nenhuma forma marcada e sem observação, `null`: o botão some da
   página, pelo mesmo motivo do horário não informado.
   ═══════════════════════════════════════════════════════════════════════════ */
const PAGAMENTOS = [
  ['pix',      'Pix',               'pix'],
  ['dinheiro', 'Dinheiro',          'dinheiro'],
  ['debito',   'Cartão de débito',  'cartao'],
  ['credito',  'Cartão de crédito', 'cartao'],
];
function pagamentos(cru){
  if(!cru || typeof cru !== 'object') return null;
  const validas = PAGAMENTOS.map(x => x[0]);
  const formas = (Array.isArray(cru.formas) ? cru.formas : [])
    .map(String).filter((f, i, a) => validas.includes(f) && a.indexOf(f) === i);
  const obs = String(cru.obs || '').trim().slice(0, 200);
  return (formas.length || obs) ? { formas, obs } : null;
}

global.Funcionamento = { ORDEM, NOMES, NA_FRASE, PAGAMENTOS, minutos, hhmm,
  normalizar, validar, agora, estado, periodosDoDia, pagamentos };

})(typeof window !== 'undefined' ? window : globalThis);
