/* ===========================================================================
   AgendaPro — que dia é hoje PARA O SALÃO

   ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
   Um teste de tela vive em dois relógios ao mesmo tempo: o do processo Node
   que monta o cenário, e o do salão, que é quem manda no painel. `hoje()` do
   app.html devolve o dia no `fuso` do salão — `saloes.fuso`, `not null
   default 'America/Sao_Paulo'` — porque é assim que `a.data` e `c.data` são
   contados, e é assim que o `relatorio()` e o `painel_hoje()` fecham o dia.

   Enquanto os dois relógios caem no mesmo dia, `new Date().toISOString()`
   dentro do teste funciona por coincidência. A bancada e o CI rodam em UTC,
   o salão de teste nasce em America/Sao_Paulo, e das 00:00 às 03:00 UTC os
   dois discordam — três horas por dia em que o teste marcava para um dia e o
   painel abria noutro.

   Não é bug do produto: é o teste falando um calendário e o app falando
   outro. Aqui ele passa a falar o do salão, que é o que a recepção vê.

   ── COMO USAR ──────────────────────────────────────────────────────────────
       import { hojeNoSalao, maisDias } from './dia.mjs';
       const AMANHA = maisDias(1);                    // no fuso padrão
       const HOJE   = hojeNoSalao('America/Manaus');  // noutro fuso

   O `n` de `maisDias` anda em dias de CALENDÁRIO a partir do dia do salão —
   e não 24 horas a partir de agora, que é o que `Date.now() + 864e5` faz e
   que erra sempre que o dia tem 23 ou 25 horas.
   =========================================================================== */

export const FUSO_PADRAO = 'America/Sao_Paulo';

// O dia do salão, em 'AAAA-MM-DD'. Mesmo cálculo do `instanteParaTela()`.
export function hojeNoSalao(fuso = FUSO_PADRAO, quando = new Date()){
  return new Intl.DateTimeFormat('en-CA',
    { timeZone: fuso, year:'numeric', month:'2-digit', day:'2-digit' })
    .format(quando);
}

// `n` dias de calendário depois (ou antes, com n negativo) do dia do salão.
export function maisDias(n, fuso = FUSO_PADRAO, quando = new Date()){
  const [a, m, d] = hojeNoSalao(fuso, quando).split('-').map(Number);
  const x = new Date(Date.UTC(a, m - 1, d + n));
  return x.toISOString().slice(0, 10);
}

/* O dia da semana (0 = domingo) daquele dia de calendário, sem passar por
   fuso nenhum: a data já é uma data, e reinterpretá-la num fuso é justamente
   o erro que este arquivo existe para não repetir. */
export function diaDaSemana(dataIso){
  const [a, m, d] = dataIso.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d)).getUTCDay();
}

/* O deslocamento do fuso naquele dia ('-03:00'), para montar o timestamptz
   que o banco guarda. Repetido em cinco suítes antes de morar aqui. */
export function deslocamento(dataIso, fuso = FUSO_PADRAO){
  return new Intl.DateTimeFormat('en-US',
    { timeZone: fuso, timeZoneName:'longOffset' })
    .formatToParts(new Date(dataIso + 'T12:00:00Z'))
    .find(x => x.type === 'timeZoneName').value.replace('GMT', '');
}
