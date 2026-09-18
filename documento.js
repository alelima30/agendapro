/* ===========================================================================
   AgendaPro — CPF e CNPJ: máscara e dígito verificador

   ── POR QUE ISTO VIROU ARQUIVO ────────────────────────────────────────────
   O `cpfValido` e o `cnpjValido` nasceram dentro do `criar.html`, e ficaram
   lá sem uso nenhum — o comentário de lá dizia, com todas as letras, que o
   documento passaria a ser pedido na hora de assinar "e é lá que eles
   voltam". Voltaram antes: o link da cliente passou a oferecer o campo de
   CPF, e a ficha do painel também.

   Três cópias de um algoritmo de dígito verificador em três arquivos é como
   uma delas fica diferente das outras sem ninguém perceber — e a que fica
   diferente aceita documento que as outras recusam, ou o contrário. Conta
   que se repete mora num lugar só.

   ⚠ E O QUE ESTE ARQUIVO NÃO FAZ.

   Dígito verificador não diz que o CPF EXISTE, nem que é de quem digitou.
   Ele só diz que os onze números são consistentes entre si. "111.111.111-11"
   passa na conta e é recusado aqui à mão, junto com as outras nove
   sequências repetidas, que são o erro de digitação mais comum que existe.

   Quem diz se o documento é de alguém é a Receita, e isso não se pergunta de
   dentro de um navegador.
   =========================================================================== */
(function(global){
'use strict';

function soDigitos(t){ return String(t == null ? '' : t).replace(/\D/g, ''); }

/* A conta oficial: cada dígito verificador sai da soma ponderada dos
   anteriores, módulo 11, com 10 virando zero. Duas passadas — uma para cada
   dígito do fim. */
function cpfValido(cpf){
  cpf = soDigitos(cpf);
  // Sequência repetida passa na conta dos dígitos e não é CPF de ninguém.
  if(cpf.length !== 11 || /^(\d)\1{10}$/.test(cpf)) return false;
  for(const [ate, pos] of [[9, 10], [10, 11]]){
    let soma = 0;
    for(let i = 0; i < ate; i++) soma += Number(cpf[i]) * (pos - i);
    let d = (soma * 10) % 11;
    if(d === 10) d = 0;
    if(d !== Number(cpf[ate])) return false;
  }
  return true;
}

function cnpjValido(cnpj){
  cnpj = soDigitos(cnpj);
  if(cnpj.length !== 14 || /^(\d)\1{13}$/.test(cnpj)) return false;
  const calc = tam => {
    let soma = 0, pos = tam - 7;
    for(let i = tam; i >= 1; i--){
      soma += Number(cnpj[tam - i]) * pos--;
      if(pos < 2) pos = 9;
    }
    const r = soma % 11;
    return r < 2 ? 0 : 11 - r;
  };
  return calc(12) === Number(cnpj[12]) && calc(13) === Number(cnpj[13]);
}

/* Pontua enquanto a pessoa digita, aceitando CPF ou CNPJ pelo tamanho. É o
   `mascaraDoc` que morava no criar.html, letra por letra. */
function mascara(el){
  let v = soDigitos(el.value).slice(0, 14);
  if(v.length <= 11){
    v = v.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2')
         .replace(/(\d{3})(\d{1,2})$/, '$1-$2');
  } else {
    v = v.replace(/^(\d{2})(\d)/, '$1.$2').replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
         .replace(/\.(\d{3})(\d)/, '.$1/$2').replace(/(\d{4})(\d)/, '$1-$2');
  }
  el.value = v;
}

/* Só CPF: trava em onze dígitos. A cliente de um salão é pessoa, e deixar o
   campo crescer até catorze só serviria para ela digitar um CNPJ sem que
   nada na tela dissesse que aquilo não cabe ali. */
function mascaraCpf(el){
  let v = soDigitos(el.value).slice(0, 11);
  v = v.replace(/(\d{3})(\d)/, '$1.$2').replace(/(\d{3})(\d)/, '$1.$2')
       .replace(/(\d{3})(\d{1,2})$/, '$1-$2');
  el.value = v;
}

global.Documento = { soDigitos, cpfValido, cnpjValido, mascara, mascaraCpf };

})(window);
