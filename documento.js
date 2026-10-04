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

/* ── DATA QUE SE DIGITA ────────────────────────────────────────────────────
   `<input type="date">` no Android só abre o calendário: não deixa digitar.
   Para um aniversário de 1958, isso é rolar o seletor de ano por 68 anos.
   "Tenho que conseguir digitar dia, mês e ano — ou pôr pela agenda ao lado."

   `dataDigitavel(campo)` põe um campo de texto dd/mm/aaaa na frente do campo
   de data, e o campo de data fica INVISÍVEL por cima do ícone de calendário:
   tocar no ícone é tocar nele, e o celular abre o seletor de sempre.

   ⚠ O CAMPO DE DATA CONTINUA SENDO O QUE GUARDA O VALOR, em ISO
   (aaaa-mm-dd). Quem lê `.value` dele — o salvar, a conferência de idade, a
   memória do aparelho — não precisa saber que existe um texto na frente.
   Escrever `.value` nele por código também atualiza o texto (o setter é
   trocado só nesta instância). */
function dataDeBr(t){
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(String(t || '').trim());
  if(!m) return '';
  const d = +m[1], mes = +m[2], a = +m[3];
  const dt = new Date(a, mes - 1, d);
  if(dt.getFullYear() !== a || dt.getMonth() !== mes - 1 || dt.getDate() !== d) return '';
  return m[3] + '-' + m[2] + '-' + m[1];
}
function brDeData(iso){
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ''));
  return m ? m[3] + '/' + m[2] + '/' + m[1] : '';
}
function mascaraData(el){
  const d = soDigitos(el.value).slice(0, 8);
  el.value = d.length > 4 ? d.slice(0, 2) + '/' + d.slice(2, 4) + '/' + d.slice(4)
           : d.length > 2 ? d.slice(0, 2) + '/' + d.slice(2) : d;
}
function dataDigitavel(campo){
  if(!campo || campo.dataset.digitavel) return;
  campo.dataset.digitavel = '1';
  const caixa = document.createElement('span');
  caixa.className = 'data-caixa';
  const txt = document.createElement('input');
  txt.type = 'text';
  txt.inputMode = 'numeric';
  txt.placeholder = 'dd/mm/aaaa';
  txt.maxLength = 10;
  txt.id = campo.id + 'Txt';
  txt.className = 'data-txt';
  txt.autocomplete = campo.getAttribute('autocomplete') || 'off';
  const rot = campo.id && document.querySelector('label[for="' + campo.id + '"]');
  if(rot) rot.setAttribute('for', txt.id);
  else {
    const lab = campo.closest('.campo') && campo.closest('.campo').querySelector('label');
    if(lab) txt.setAttribute('aria-label', lab.textContent.trim());
  }
  const ic = document.createElement('span');
  ic.className = 'data-ic';
  ic.setAttribute('data-ico', 'calendario');
  ic.setAttribute('aria-hidden', 'true');
  campo.parentNode.insertBefore(caixa, campo);
  caixa.appendChild(txt);
  caixa.appendChild(ic);
  caixa.appendChild(campo);
  campo.classList.add('data-escolher');
  campo.removeAttribute('autocomplete');
  campo.setAttribute('aria-label', 'Escolher no calendário');

  // Escrever no campo de data por código (memória do aparelho, ficha aberta)
  // atualiza o texto — menos enquanto a pessoa está digitando nele.
  const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
  Object.defineProperty(campo, 'value', {
    configurable: true,
    get(){ return desc.get.call(this); },
    set(v){ desc.set.call(this, v); if(document.activeElement !== txt) txt.value = brDeData(desc.get.call(this)); },
  });
  txt.value = brDeData(campo.value);

  txt.addEventListener('input', () => {
    mascaraData(txt);
    desc.set.call(campo, dataDeBr(txt.value));
    campo.dispatchEvent(new Event('change', { bubbles: true }));
  });
  // Só quando a mudança veio do calendário: o aviso de mudança que o próprio
  // texto dispara (acima) voltaria aqui e apagaria a data pela metade.
  const doCalendario = () => { if(document.activeElement !== txt) txt.value = brDeData(desc.get.call(campo)); };
  campo.addEventListener('input', doCalendario);
  campo.addEventListener('change', doCalendario);
  // No computador o clique no campo não abre o seletor sozinho.
  campo.addEventListener('click', () => { try{ campo.showPicker(); }catch(e){} });
  if(global.aplicarIcones) global.aplicarIcones(caixa);
}
// Digitou alguma coisa que não virou data (31/02, ano pela metade)?
function dataIncompleta(campo){
  const t = campo && document.getElementById(campo.id + 'Txt');
  return !!(t && t.value.trim() && !campo.value);
}

global.Documento = { soDigitos, cpfValido, cnpjValido, mascara, mascaraCpf,
                     dataDigitavel, dataDeBr, brDeData, mascaraData, dataIncompleta };

})(window);
