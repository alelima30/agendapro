/* ===========================================================================
   AgendaPro — o QR do link

     node tests/qr.test.js

   ── ⚠ COMO SE CONFERE UM QR SEM UM LEITOR ──────────────────────────────────
   Não há decodificador nesta máquina — nem biblioteca, nem o `BarcodeDetector`
   do navegador (conferido: não existe neste Chromium). E QR errado é o pior
   tipo de defeito: o desenho fica bonito, a tela parece pronta, e só quem
   aponta o telefone descobre — no espelho do salão, depois de impresso.

   Então a conferência é por três caminhos que erram de formas diferentes:

   1. O EXEMPLO DO PRÓPRIO PADRÃO. A ISO/IEC 18004 traz um caso resolvido à
      mão, com os bytes de correção escritos. Se o meu Reed-Solomon devolve
      exatamente aqueles dez números, a matemática está certa — e essa é uma
      referência que NÃO saiu da minha cabeça, que é o que faz ela valer.

   2. A ESTRUTURA. Os três quadrados de canto, as linhas de referência, o
      módulo sempre preto, o tamanho da matriz por versão. São regras fixas
      do formato, e cada uma pega uma classe diferente de engano no desenho.

   3. A VOLTA. Um leitor pequeno, escrito aqui, que desfaz a máscara e lê os
      bytes de volta do lugar onde foram postos. Não prova que um telefone lê
      — prova que o que foi escrito está onde deveria, que é o erro mais
      provável quando se escreve isto pela primeira vez.
   =========================================================================== */
const fs = require('fs');
const path = require('path');

const RAIZ = path.dirname(__dirname);
const g = {};
new Function('window', fs.readFileSync(path.join(RAIZ, 'qr.js'), 'utf8'))(g);
const QR = g.QR;

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const verdade = (m, c, d) => c ? ok(m) : nao(m, d);
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}\n      veio    ${JSON.stringify(a)}`);
const secao = t => console.log('\n' + t);

/* ══════════════════════════════════════════════════════════════════════════
   1 — ⚠ A PROPRIEDADE QUE DEFINE UM REED-SOLOMON VÁLIDO

   Eu comecei escrevendo aqui os dez bytes de correção do exemplo resolvido da
   ISO, de memória. Eles não bateram — e passei um bom tempo caçando um defeito
   no gerador antes de perceber que a constante é que podia estar errada. Não
   tenho o documento à mão para conferir, e medida que depende da minha memória
   não é medida: é a mesma cabeça conferindo a si mesma duas vezes.

   Então a conferência é pela DEFINIÇÃO, que não depende de lembrar nada:

     a palavra completa — dados seguidos da correção — é, por construção,
     múltipla do polinômio gerador. Logo ela vale ZERO em cada uma das raízes
     dele: α⁰, α¹, … αⁿ⁻¹.

   Isso pega tudo o que pode dar errado aqui, e cada coisa por um motivo
   diferente:

     · gerador invertido → as raízes passam a ser outras, e as contas não
       zeram (foi exatamente este o defeito: eu trocava qual termo subia de
       grau, e (x+1)(x+2) virava 2x²+3x+1);
     · divisão errada → o resto não é o resto, e não zera;
     · ordem trocada na saída → a palavra deixa de ser o polinômio que era.

   E o gerador ainda é conferido contra o do padrão para dez bytes, que é um
   número que dá para recontar à mão pela fórmula.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A matemática da correção de erro');

/* As tabelas do campo, refeitas aqui do zero — se o `qr.js` tivesse escolhido
   outro polinômio, as contas abaixo divergiriam. */
const EXP = new Uint8Array(512), LOG = new Uint8Array(256);
(function(){ let x = 1;
  for(let i = 0; i < 255; i++){ EXP[i] = x; LOG[x] = i; x <<= 1; if(x & 0x100) x ^= 0x11D; }
  for(let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();
const mul = (a, b) => (a === 0 || b === 0) ? 0 : EXP[LOG[a] + LOG[b]];

/* O gerador de grau 10 do padrão, em inteiros. Este dá para reconstruir à
   mão: é (x+α⁰)(x+α¹)…(x+α⁹) multiplicado passo a passo. */
const GER10 = [1, 216, 194, 159, 111, 199, 94, 95, 113, 157, 193];
let g10 = [1];
for(let i = 0; i < 10; i++){
  const n = new Array(g10.length + 1).fill(0);
  for(let j = 0; j < g10.length; j++){ n[j] ^= g10[j]; n[j + 1] ^= mul(g10[j], EXP[i]); }
  g10 = n;
}
igual('o gerador de grau 10 bate com o do padrão', g10, GER10);

/* A palavra completa vale zero em cada raiz do gerador. */
function valeEm(palavra, alfa){
  let v = 0;
  for(const b of palavra) v = mul(v, alfa) ^ b;
  return v;
}
const DADOS_ISO = [0x10, 0x20, 0x0C, 0x56, 0x61, 0x80, 0xEC, 0x11,
                   0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11];

for(const quantos of [10, 16, 22, 26]){
  const ec = QR._correcao(DADOS_ISO, quantos);
  const palavra = DADOS_ISO.concat(ec);
  const sobras = [];
  for(let k = 0; k < quantos; k++){
    const v = valeEm(palavra, EXP[k]);
    if(v !== 0) sobras.push('α^' + k + '→' + v);
  }
  verdade(`com ${quantos} bytes de correção, a palavra zera nas ${quantos} raízes`,
    ec.length === quantos && sobras.length === 0,
    sobras.slice(0, 4).join(', '));
}

/* E a correção MUDA com os dados: um gerador que devolvesse sempre a mesma
   coisa zeraria nas raízes por acaso de nunca ter sido testado com dois
   conjuntos diferentes. */
const outro = DADOS_ISO.slice(); outro[0] ^= 0xFF;
verdade('mudar um byte dos dados muda a correção',
  JSON.stringify(QR._correcao(DADOS_ISO, 10)) !== JSON.stringify(QR._correcao(outro, 10)));

/* ══════════════════════════════════════════════════════════════════════════
   2 — OS BITS DOS DADOS
   ══════════════════════════════════════════════════════════════════════════ */
secao('A codificação em modo byte');

const bits = QR._bitsDoTexto('A', 1);
igual('o primeiro byte traz o modo 0100 e o começo do tamanho',
  bits[0], 0b01000000);
igual('o segundo traz o resto do tamanho (1) e o começo do "A" (0x41)',
  bits[1], 0b00010100);
/* O enchimento alterna 0xEC e 0x11 a partir do primeiro byte livre. Onde ele
   TERMINA depende de quantos bytes sobraram — com treze, acaba no 0xEC. Eu
   tinha cravado os dois últimos como [EC, 11] e a medida reprovou um gerador
   certo; o que importa é a alternância, não onde ela para. */
const enchimento = bits.slice(3);
igual('o enchimento alterna 0xEC e 0x11 a partir do primeiro byte livre',
  enchimento, enchimento.map((_, i) => i % 2 === 0 ? 0xEC : 0x11));
igual('com exatamente os 16 bytes que a versão 1 comporta', bits.length, 16);

/* ⚠ O CONTADOR MUDA DE TAMANHO NA VERSÃO 10, e errar isso produz um QR que
   o leitor aceita e lê torto — o pior tipo de erro, porque parece funcionar. */
const b9  = QR._bitsDoTexto('A', 9);
const b10 = QR._bitsDoTexto('A', 10);
igual('na versão 9 o contador ocupa 8 bits', b9[1], 0b00010100);
/* ⚠ E NADA AQUI CAI EM BYTE REDONDO. O indicador de modo tem QUATRO bits,
   então o contador e o texto ficam deslocados meio byte para sempre. Eu tinha
   escrito a expectativa como se o "A" começasse num byte inteiro, e a medida
   reprovou um gerador que estava certo.

   Conferido à mão, bit a bit: 0100 | 0000000000000001 | 01000001 | 0000
   agrupado de oito em oito dá 0x40, 0x00, 0x14, 0x10 — e o 0xEC do
   enchimento em seguida. */
igual('e na 10 ocupa 16 — tudo anda meio byte',
  b10.slice(0, 5), [0x40, 0x00, 0x14, 0x10, 0xEC]);

/* ══════════════════════════════════════════════════════════════════════════
   3 — OS BITS DO FORMATO

   Também tabelados no padrão: correção M com cada uma das oito máscaras.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Os quinze bits do formato');

const FORMATO_M = [0x5412, 0x5125, 0x5E7C, 0x5B4B,
                   0x45F9, 0x40CE, 0x4F97, 0x4AA0];
igual('os oito valores batem com a tabela do padrão',
  [0,1,2,3,4,5,6,7].map(k => QR._bitsDoFormato(k)), FORMATO_M);

/* ══════════════════════════════════════════════════════════════════════════
   4 — A ESTRUTURA DO DESENHO
   ══════════════════════════════════════════════════════════════════════════ */
secao('A estrutura da matriz');

const m = QR.matriz('https://agendapro.app/studio-bella');
const n = m.length;
console.log('      ' + n + '×' + n + ' módulos');
verdade('a matriz é quadrada e de tamanho válido — ' + n,
  n >= 21 && n <= 57 && (n - 17) % 4 === 0, String(n));
verdade('nenhum módulo ficou indefinido',
  m.every(l => l.every(c => c === 0 || c === 1)),
  'sobrou null: algum pedaço do desenho não foi preenchido');

/* Os três quadrados de canto. Cada um é um anel preto de 7×7 com um miolo
   3×3 — é por eles que o leitor acha o código e descobre a rotação. */
const quadradoOk = (lin, col) => {
  for(let i = 0; i < 7; i++) for(let j = 0; j < 7; j++){
    const anel = i === 0 || i === 6 || j === 0 || j === 6;
    const miolo = i >= 2 && i <= 4 && j >= 2 && j <= 4;
    if(m[lin + i][col + j] !== (anel || miolo ? 1 : 0)) return false;
  }
  return true;
};
verdade('o quadrado de cima à esquerda está inteiro', quadradoOk(0, 0));
verdade('o de cima à direita também', quadradoOk(0, n - 7));
verdade('e o de baixo à esquerda', quadradoOk(n - 7, 0));

/* As duas linhas de referência: preto, branco, preto, branco… É por elas que
   o leitor mede o tamanho de um módulo. */
let refOk = true;
for(let i = 8; i < n - 8; i++){
  if(m[6][i] !== (i % 2 === 0 ? 1 : 0)) refOk = false;
  if(m[i][6] !== (i % 2 === 0 ? 1 : 0)) refOk = false;
}
verdade('as duas linhas de referência alternam certo', refOk);

verdade('o módulo que é sempre preto está preto', m[n - 8][8] === 1);

/* A zona de silêncio no SVG: quatro módulos brancos em volta. Sem ela o
   leitor não acha onde o código começa em cima de um fundo colorido. */
const desenho = QR.svg('https://agendapro.app/studio-bella');
const caixa = (desenho.match(/viewBox="0 0 (\d+) (\d+)"/) || []);
igual('o SVG reserva os quatro módulos de borda dos dois lados',
  Number(caixa[1]), n + 8);
verdade('e desenha um fundo branco por baixo', /<rect[^>]*fill="#FFFFFF"/.test(desenho),
  desenho.slice(0, 200));

/* ══════════════════════════════════════════════════════════════════════════
   5 — ⚠ A VOLTA: LER DE NOVO O QUE FOI ESCRITO

   Um leitor pequeno, que faz o caminho inverso: acha a máscara nos bits do
   formato, desfaz, percorre o ziguezague na mesma ordem e remonta os bytes.
   Se o que sai não for o que entrou, alguma coisa foi posta no lugar errado.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Lendo o desenho de volta');

function ler(m, versao){
  const n = m.length;

  // 1. A máscara, de volta dos quinze bits do formato.
  let formato = 0;
  for(let i = 0; i <= 5; i++)  formato |= m[8][i] << i;
  formato |= m[8][7] << 6; formato |= m[8][8] << 7; formato |= m[7][8] << 8;
  for(let i = 9; i <= 14; i++) formato |= m[14 - i][8] << i;
  const cru = formato ^ 0b101010000010010;
  /* ⚠ A MÁSCARA MORA NOS BITS 10 A 12, e não nos três de baixo. Os quinze
     bits do formato são: dois de correção, três de máscara, e dez de BCH —
     nessa ordem, do mais alto para o mais baixo. Eu li os três últimos, que
     são pedaço do BCH, e o leitor desfez a máscara errada: os bytes voltaram
     embaralhados desde o primeiro. */
  const mascara = (cru >> 10) & 0b111;

  // 2. Os lugares reservados, remontados do mesmo jeito que na escrita.
  const base = [];
  for(let i = 0; i < n; i++) base.push(new Array(n).fill(null));
  const quadrado = (lin, col) => {
    for(let i = -1; i <= 7; i++) for(let j = -1; j <= 7; j++){
      const y = lin + i, x = col + j;
      if(y >= 0 && y < n && x >= 0 && x < n) base[y][x] = 1;
    }
  };
  quadrado(0, 0); quadrado(0, n - 7); quadrado(n - 7, 0);
  for(let i = 0; i < n; i++){ base[6][i] = 1; base[i][6] = 1; }
  const ALINHA = [ [], [], [6,18], [6,22], [6,26], [6,30], [6,34],
                   [6,22,38], [6,24,42], [6,26,46], [6,28,50] ][versao];
  for(const a of ALINHA) for(const b of ALINHA){
    if((a <= 8 && b <= 8) || (a <= 8 && b >= n - 9) || (a >= n - 9 && b <= 8)) continue;
    for(let i = -2; i <= 2; i++) for(let j = -2; j <= 2; j++) base[a + i][b + j] = 1;
  }
  for(let i = 0; i < 9; i++){ base[8][i] = 1; base[i][8] = 1; }
  for(let i = n - 8; i < n; i++){ base[8][i] = 1; base[i][8] = 1; }

  // 3. O ziguezague, desfazendo a máscara de cada módulo que é dado.
  const MASC = [
    (l, c) => (l + c) % 2 === 0, (l) => l % 2 === 0, (l, c) => c % 3 === 0,
    (l, c) => (l + c) % 3 === 0,
    (l, c) => (Math.floor(l / 2) + Math.floor(c / 3)) % 2 === 0,
    (l, c) => (l * c) % 2 + (l * c) % 3 === 0,
    (l, c) => (((l * c) % 2) + ((l * c) % 3)) % 2 === 0,
    (l, c) => (((l + c) % 2) + ((l * c) % 3)) % 2 === 0,
  ][mascara];

  const bits = [];
  let subindo = true;
  for(let col = n - 1; col > 0; col -= 2){
    if(col === 6) col--;
    for(let k = 0; k < n; k++){
      const lin = subindo ? n - 1 - k : k;
      for(const c of [col, col - 1]){
        if(base[lin][c]) continue;
        bits.push(m[lin][c] ^ (MASC(lin, c) ? 1 : 0));
      }
    }
    subindo = !subindo;
  }
  const bytes = [];
  for(let i = 0; i + 8 <= bits.length; i += 8){
    let b = 0;
    for(let j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
    bytes.push(b);
  }
  return { mascara, bytes };
}

/* Um texto que cabe na versão 1 sem bloco nem intercalação: assim a volta
   compara os bytes na ordem em que saíram do `_bitsDoTexto`, e uma diferença
   aponta para o DESENHO, não para a intercalação. */
/* ⚠ CATORZE BYTES É O TETO DA VERSÃO 1 com correção M: 16 bytes de dados,
   menos 12 bits de cabeçalho e 4 de terminador. Eu tinha escrito um endereço
   de 17 e o gerador subiu para a versão 2, certíssimo — e a volta, que eu
   mandava ler como versão 1, caiu no quadradinho de alinhamento do 2 e leu
   lixo a partir do décimo byte. */
const TEXTO = 'agendapro';
const m1 = QR.matriz(TEXTO);
igual('o texto curto cabe na versão 1', m1.length, 21);

const lido = ler(m1, 1);
const escrito = QR._bitsDoTexto(TEXTO, 1);
console.log('      máscara escolhida: ' + lido.mascara);
igual('os dezesseis bytes de dados voltam iguais aos que entraram',
  lido.bytes.slice(0, 16), escrito);

/* E o texto de verdade, remontado dos bytes: é o que o telefone vai ver. */
/* E o texto remontado do fluxo de bits, como o padrão manda ler: quatro bits
   de modo, oito de tamanho, e o resto em bytes. É o que o telefone faz. */
function textoDeVolta(bytes){
  const bits = [];
  for(const b of bytes) for(let i = 7; i >= 0; i--) bits.push((b >> i) & 1);
  const pega = (de, quantos) => {
    let v = 0;
    for(let i = 0; i < quantos; i++) v = (v << 1) | bits[de + i];
    return v;
  };
  const modo = pega(0, 4);
  const tam  = pega(4, 8);
  const saida = [];
  for(let i = 0; i < tam; i++) saida.push(pega(12 + i * 8, 8));
  return { modo, tam, texto: Buffer.from(saida).toString('utf8') };
}
const volta = textoDeVolta(lido.bytes);
igual('o modo lido de volta é o modo byte', volta.modo, 0b0100);
igual('o tamanho lido de volta é o tamanho do texto', volta.tam, TEXTO.length);
igual('e o endereço remontado é o endereço original', volta.texto, TEXTO);

/* ══════════════════════════════════════════════════════════════════════════
   6 — OS TAMANHOS
   ══════════════════════════════════════════════════════════════════════════ */
secao('Textos de tamanhos diferentes');

for(const [texto, esperado] of [
  ['a', 21],
  ['https://agendapro.app/barbearia-do-joao', 29],
  ['x'.repeat(100), 41],
]){
  const mm = QR.matriz(texto);
  verdade(`"${texto.slice(0, 28)}${texto.length > 28 ? '…' : ''}" → ${mm.length}×${mm.length}`,
    mm.length === esperado, 'esperava ' + esperado);
}

let estourou = null;
try{ QR.matriz('x'.repeat(300)); }catch(e){ estourou = e.message; }
verdade('texto longo demais avisa em vez de desenhar errado',
  estourou !== null && /longo/i.test(estourou), String(estourou));

/* Acentos e emoji: o endereço pode ter, e UTF-8 gasta mais de um byte. Um
   contador que contasse LETRAS em vez de BYTES quebraria só aqui. */
const comAcento = QR.matriz('agendapro.app/salão-da-inês');
verdade('endereço com acento desenha sem quebrar', comAcento.length >= 21);

console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
