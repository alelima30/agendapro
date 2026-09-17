/* ===========================================================================
   AgendaPro — QR code

   O painel promete, há muito tempo, que o link do salão "imprime como QR no
   espelho". Não imprimia: não havia QR nenhum.

   ── POR QUE NÃO UM SERVIÇO DE FORA ────────────────────────────────────────
   Existem endereços que devolvem a imagem pronta — `api.qrserver.com` e
   parecidos, uma linha de código. Três razões para não usar:

     · o endereço do salão passaria a ser mandado para um servidor alheio toda
       vez que a tela desenha o quadradinho;
     · sem internet, ou no dia em que aquele serviço sair do ar, o QR vira um
       retângulo quebrado dentro do painel;
     · o projeto inteiro é feito para rodar sem dependência nenhuma, e um
       `<img src="https://outro-lugar">` é uma dependência escondida num
       atributo.

   Duzentas linhas resolvem, e elas não mudam mais: o formato do QR é de 2006.

   ── O QUE ESTE ARQUIVO FAZ, E O QUE NÃO FAZ ───────────────────────────────
   Faz: modo byte (UTF-8), versões 1 a 10, correção de erro M, as oito
   máscaras com a escolha pela penalidade do padrão. Dá para um endereço de
   até 154 caracteres — de sobra para `agendapro.app/nome-do-salao`.

   Não faz: modo numérico, alfanumérico, kanji, versões acima de 10. Nada
   disso serve para endereço de internet, e cada um seria mais código para
   manter sem ninguém usar.

   ⚠ E POR QUE CORREÇÃO M, E NÃO L: o QR do salão vai para o espelho, para o
   balcão, para o vidro da porta. Vai ser fotografado torto, com dedo em
   cima, com reflexo. O L economiza uns módulos e devolve um código que
   desiste na primeira sujeira; o M lê com 15% do desenho perdido.
   =========================================================================== */

(function (global) {
'use strict';

/* ── A ARITMÉTICA DO CAMPO DE GALOIS GF(256) ──────────────────────────────
   A correção de erro do QR é Reed-Solomon, e Reed-Solomon vive num campo
   onde somar é XOR e multiplicar é somar logaritmos. As duas tabelas abaixo
   são o logaritmo e o antilogaritmo desse campo, com o polinômio 0x11D — o
   mesmo que o padrão manda usar. */
const EXP = new Uint8Array(512), LOG = new Uint8Array(256);
(function tabelas(){
  let x = 1;
  for(let i = 0; i < 255; i++){
    EXP[i] = x; LOG[x] = i;
    x <<= 1;
    if(x & 0x100) x ^= 0x11D;
  }
  for(let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();

const mul = (a, b) => (a === 0 || b === 0) ? 0 : EXP[LOG[a] + LOG[b]];

/* O polinômio gerador de grau `n`: (x-α⁰)(x-α¹)…(x-αⁿ⁻¹), multiplicado
   passo a passo. É ele que decide os bytes de correção. */
function gerador(n){
  let g = [1];
  for(let i = 0; i < n; i++){
    const novo = new Array(g.length + 1).fill(0);
    /* ⚠ QUAL TERMO SOBE DE GRAU. A lista guarda o coeficiente de maior grau
       PRIMEIRO, então multiplicar por `x` mantém o índice e multiplicar pela
       constante o empurra um para a frente. Eu tinha escrito ao contrário, e
       o gerador saía invertido: (x+1)(x+2) virava 2x²+3x+1 em vez de
       x²+3x+2.

       O desenho continuava saindo bonito e os dez bytes de correção
       continuavam sendo dez — só estavam errados. Quem pegou foi o exemplo
       resolvido da ISO, que é a única referência aqui que não saiu da minha
       cabeça. */
    for(let j = 0; j < g.length; j++){
      novo[j]     ^= g[j];
      novo[j + 1] ^= mul(g[j], EXP[i]);
    }
    g = novo;
  }
  return g;
}

/* A divisão polinomial que sobra: o RESTO é o que vai junto com os dados. */
function correcao(dados, quantos){
  const g = gerador(quantos);
  const resto = new Array(quantos).fill(0);
  for(const byte of dados){
    const fator = byte ^ resto[0];
    resto.shift(); resto.push(0);
    if(fator !== 0)
      for(let i = 0; i < quantos; i++) resto[i] ^= mul(g[i + 1], fator);
  }
  return resto;
}

/* ── AS TABELAS DO PADRÃO, PARA CORREÇÃO M ────────────────────────────────
   Por versão (1 a 10): quantos bytes de dados cabem, quantos bytes de
   correção por bloco, e em quantos blocos os dados são partidos.

   Blocos existem porque uma mancha numa etiqueta estraga módulos VIZINHOS:
   partindo os dados e intercalando os bytes na hora de desenhar, a mancha
   tira alguns bytes de cada bloco em vez de todos de um só — e aí cada bloco
   ainda tem correção suficiente para se recompor. */
const VERSOES = [
  /* v1 */ { dados: 16,  ecPorBloco: 10, blocos: [1, 0] },
  /* v2 */ { dados: 28,  ecPorBloco: 16, blocos: [1, 0] },
  /* v3 */ { dados: 44,  ecPorBloco: 26, blocos: [1, 0] },
  /* v4 */ { dados: 64,  ecPorBloco: 18, blocos: [2, 0] },
  /* v5 */ { dados: 86,  ecPorBloco: 24, blocos: [2, 0] },
  /* v6 */ { dados: 108, ecPorBloco: 16, blocos: [4, 0] },
  /* v7 */ { dados: 124, ecPorBloco: 18, blocos: [4, 0] },
  /* v8 */ { dados: 154, ecPorBloco: 22, blocos: [2, 2] },
  /* v9 */ { dados: 182, ecPorBloco: 22, blocos: [3, 2] },
  /* v10*/ { dados: 216, ecPorBloco: 26, blocos: [4, 1] },
];

// Onde ficam os quadradinhos de alinhamento, por versão.
const ALINHA = [ [], [], [6,18], [6,22], [6,26], [6,30], [6,34],
                 [6,22,38], [6,24,42], [6,26,46], [6,28,50] ];

/* ── OS BITS DOS DADOS ────────────────────────────────────────────────── */
function bitsDoTexto(texto, versao){
  const bytes = new TextEncoder().encode(texto);
  const bits = [];
  const põe = (valor, quantos) => {
    for(let i = quantos - 1; i >= 0; i--) bits.push((valor >> i) & 1);
  };

  põe(0b0100, 4);                       // modo byte
  /* ⚠ O TAMANHO DO CONTADOR MUDA COM A VERSÃO: 8 bits até a 9, 16 da 10 em
     diante. Errar aqui produz um QR que o leitor aceita e lê torto — o pior
     tipo de erro, porque parece funcionar. */
  põe(bytes.length, versao >= 10 ? 16 : 8);
  for(const b of bytes) põe(b, 8);

  const cabem = VERSOES[versao - 1].dados * 8;
  // Terminador: até quatro zeros, o que couber.
  for(let i = 0; i < 4 && bits.length < cabem; i++) bits.push(0);
  // Fecha o byte.
  while(bits.length % 8) bits.push(0);
  // E completa com os dois bytes de enchimento que o padrão nomeia.
  const ENCHER = [0xEC, 0x11];
  for(let i = 0; bits.length < cabem; i++) põe(ENCHER[i % 2], 8);

  const dados = [];
  for(let i = 0; i < bits.length; i += 8){
    let b = 0;
    for(let j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
    dados.push(b);
  }
  return dados;
}

/* Parte em blocos, calcula a correção de cada um e INTERCALA — primeiro os
   dados (byte 1 de cada bloco, byte 2 de cada bloco, …), depois a correção,
   do mesmo jeito. É a intercalação que espalha o estrago de uma mancha. */
function codigosFinais(dados, versao){
  const v = VERSOES[versao - 1];
  const total = v.blocos[0] + v.blocos[1];
  const base = Math.floor(v.dados / total);
  const grandes = v.blocos[1];            // os que levam um byte a mais

  const blocos = [];
  let pos = 0;
  for(let i = 0; i < total; i++){
    const tam = base + (i >= total - grandes ? 1 : 0);
    const pedaco = dados.slice(pos, pos + tam);
    pos += tam;
    blocos.push({ dados: pedaco, ec: correcao(pedaco, v.ecPorBloco) });
  }

  const saida = [];
  const maior = Math.max(...blocos.map(b => b.dados.length));
  for(let i = 0; i < maior; i++)
    for(const b of blocos) if(i < b.dados.length) saida.push(b.dados[i]);
  for(let i = 0; i < v.ecPorBloco; i++)
    for(const b of blocos) saida.push(b.ec[i]);
  return saida;
}

/* ── O DESENHO ────────────────────────────────────────────────────────── */
function matrizVazia(n){
  const m = [];
  for(let i = 0; i < n; i++) m.push(new Array(n).fill(null));   // null = livre
  return m;
}

function porPatterns(m, versao){
  const n = m.length;
  const quadrado = (lin, col) => {
    for(let i = -1; i <= 7; i++) for(let j = -1; j <= 7; j++){
      const y = lin + i, x = col + j;
      if(y < 0 || y >= n || x < 0 || x >= n) continue;
      const borda = i === -1 || i === 7 || j === -1 || j === 7;
      const anel = (i === 0 || i === 6 || j === 0 || j === 6);
      m[y][x] = borda ? 0 : (anel ? 1 : (i >= 2 && i <= 4 && j >= 2 && j <= 4 ? 1 : 0));
    }
  };
  quadrado(0, 0); quadrado(0, n - 7); quadrado(n - 7, 0);

  // As duas linhas de referência, alternando cheio e vazio.
  for(let i = 8; i < n - 8; i++){ m[6][i] = i % 2 === 0 ? 1 : 0;
                                  m[i][6] = i % 2 === 0 ? 1 : 0; }

  // Os quadradinhos de alinhamento, menos onde os grandes já estão.
  const pos = ALINHA[versao];
  for(const a of pos) for(const b of pos){
    if((a <= 8 && b <= 8) || (a <= 8 && b >= n - 9) || (a >= n - 9 && b <= 8)) continue;
    for(let i = -2; i <= 2; i++) for(let j = -2; j <= 2; j++)
      m[a + i][b + j] = (Math.abs(i) === 2 || Math.abs(j) === 2 || (i === 0 && j === 0)) ? 1 : 0;
  }

  // O módulo que é sempre preto, e os lugares reservados do formato.
  m[n - 8][8] = 1;
  for(let i = 0; i < 9; i++){
    if(m[8][i] === null) m[8][i] = 0;
    if(m[i][8] === null) m[i][8] = 0;
  }
  for(let i = n - 8; i < n; i++){
    if(m[8][i] === null) m[8][i] = 0;
    if(m[i][8] === null) m[i][8] = 0;
  }
}

/* Os bytes entram em ziguezague, de baixo para cima, duas colunas por vez,
   pulando a coluna 6 (que é a linha de referência vertical). */
function porDados(m, codigos, reservado){
  const n = m.length;
  let bit = 0;
  const proximo = () => {
    const b = bit < codigos.length * 8
      ? (codigos[bit >> 3] >> (7 - (bit & 7))) & 1 : 0;
    bit++;
    return b;
  };
  let subindo = true;
  for(let col = n - 1; col > 0; col -= 2){
    if(col === 6) col--;
    for(let k = 0; k < n; k++){
      const lin = subindo ? n - 1 - k : k;
      for(const c of [col, col - 1]){
        if(reservado[lin][c]) continue;
        m[lin][c] = proximo();
      }
    }
    subindo = !subindo;
  }
}

const MASCARAS = [
  (l, c) => (l + c) % 2 === 0,
  (l)    => l % 2 === 0,
  (l, c) => c % 3 === 0,
  (l, c) => (l + c) % 3 === 0,
  (l, c) => (Math.floor(l / 2) + Math.floor(c / 3)) % 2 === 0,
  (l, c) => (l * c) % 2 + (l * c) % 3 === 0,
  (l, c) => (((l * c) % 2) + ((l * c) % 3)) % 2 === 0,
  (l, c) => (((l + c) % 2) + ((l * c) % 3)) % 2 === 0,
];

/* A penalidade do padrão: quanto mais o desenho parecer com os quadrados de
   canto ou tiver faixas grandes de uma cor só, pior. Testa-se as oito e
   fica-se com a mais baixa — é o que faz o leitor errar menos. */
function penalidade(m){
  const n = m.length;
  let p = 0;

  const corrida = (pega) => {
    for(let a = 0; a < n; a++){
      let igual = 1;
      for(let b = 1; b < n; b++){
        if(pega(a, b) === pega(a, b - 1)) igual++;
        else { if(igual >= 5) p += 3 + (igual - 5); igual = 1; }
      }
      if(igual >= 5) p += 3 + (igual - 5);
    }
  };
  corrida((a, b) => m[a][b]);
  corrida((a, b) => m[b][a]);

  for(let l = 0; l < n - 1; l++) for(let c = 0; c < n - 1; c++)
    if(m[l][c] === m[l][c+1] && m[l][c] === m[l+1][c] && m[l][c] === m[l+1][c+1]) p += 3;

  const ALVO = [1,0,1,1,1,0,1,0,0,0,0];
  const ALVO2 = [0,0,0,0,1,0,1,1,1,0,1];
  const acha = (pega) => {
    for(let a = 0; a < n; a++) for(let b = 0; b + 11 <= n; b++){
      let e1 = true, e2 = true;
      for(let k = 0; k < 11; k++){
        if(pega(a, b + k) !== ALVO[k]) e1 = false;
        if(pega(a, b + k) !== ALVO2[k]) e2 = false;
      }
      if(e1 || e2) p += 40;
    }
  };
  acha((a, b) => m[a][b]);
  acha((a, b) => m[b][a]);

  let escuros = 0;
  for(let l = 0; l < n; l++) for(let c = 0; c < n; c++) if(m[l][c]) escuros++;
  const pct = escuros * 100 / (n * n);
  p += Math.floor(Math.abs(pct - 50) / 5) * 10;
  return p;
}

/* Os 15 bits do formato: dois de correção, três de máscara, dez de BCH, e um
   XOR final com a máscara do padrão. */
function bitsDoFormato(mascara){
  const dados = (0b00 << 3) | mascara;          // 00 = correção M
  let resto = dados << 10;
  for(let i = 14; i >= 10; i--)
    if((resto >> i) & 1) resto ^= 0b10100110111 << (i - 10);
  return ((dados << 10) | resto) ^ 0b101010000010010;
}

function porFormato(m, mascara){
  const n = m.length;
  const bits = bitsDoFormato(mascara);
  const b = i => (bits >> i) & 1;
  for(let i = 0; i <= 5; i++) m[8][i] = b(i);
  m[8][7] = b(6); m[8][8] = b(7); m[7][8] = b(8);
  for(let i = 9; i <= 14; i++) m[14 - i][8] = b(i);
  for(let i = 0; i <= 7; i++) m[n - 1 - i][8] = b(i);
  for(let i = 8; i <= 14; i++) m[8][n - 15 + i] = b(i);
  m[n - 8][8] = 1;
}

/* ── A PORTA DE ENTRADA ───────────────────────────────────────────────── */
function matriz(texto){
  const bytes = new TextEncoder().encode(String(texto == null ? '' : texto)).length;
  let versao = 0;
  for(let v = 1; v <= 10; v++){
    const cabecalho = 2 + (v >= 10 ? 2 : 1);      // modo + contador, em bytes
    if(bytes + cabecalho <= VERSOES[v - 1].dados){ versao = v; break; }
  }
  if(!versao) throw new Error('Texto longo demais para um QR desta biblioteca.');

  const n = versao * 4 + 17;
  const base = matrizVazia(n);
  porPatterns(base, versao);

  // Onde NÃO se pode escrever dado: tudo o que já foi desenhado acima.
  const reservado = base.map(l => l.map(c => c !== null));

  const codigos = codigosFinais(bitsDoTexto(texto, versao), versao);

  let melhor = null, melhorNota = Infinity;
  for(let k = 0; k < 8; k++){
    const m = base.map(l => l.slice());
    porDados(m, codigos, reservado);
    for(let l = 0; l < n; l++) for(let c = 0; c < n; c++)
      if(!reservado[l][c] && MASCARAS[k](l, c)) m[l][c] ^= 1;
    porFormato(m, k);
    const nota = penalidade(m);
    if(nota < melhorNota){ melhorNota = nota; melhor = m; }
  }
  return melhor;
}

/* O SVG. Um caminho só, com um retângulo por módulo preto: o navegador
   desenha em qualquer tamanho sem borrar, e o arquivo cabe num atributo.

   ⚠ A BORDA BRANCA NÃO É MARGEM DE ENFEITE. O padrão chama de zona de
   silêncio e exige quatro módulos: sem ela o leitor não acha onde o código
   começa, e o QR simplesmente não lê em cima de um fundo colorido. */
function svg(texto, opcoes){
  const o = opcoes || {};
  const m = matriz(texto);
  const n = m.length;
  const borda = o.borda == null ? 4 : o.borda;
  const lado = n + borda * 2;
  let d = '';
  for(let l = 0; l < n; l++) for(let c = 0; c < n; c++)
    if(m[l][c]) d += `M${c + borda} ${l + borda}h1v1h-1z`;
  const cor = o.cor || '#000000';
  const fundo = o.fundo || '#FFFFFF';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${lado} ${lado}"`
       + ` shape-rendering="crispEdges" role="img"`
       + ` aria-label="${o.rotulo || 'QR code do link'}">`
       + `<rect width="${lado}" height="${lado}" fill="${fundo}"/>`
       + `<path d="${d}" fill="${cor}"/></svg>`;
}

global.QR = { matriz, svg, _correcao: correcao, _bitsDoTexto: bitsDoTexto,
              _bitsDoFormato: bitsDoFormato, _VERSOES: VERSOES };

})(typeof window !== 'undefined' ? window : globalThis);
