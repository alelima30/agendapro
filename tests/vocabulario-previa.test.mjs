/* ===========================================================================
   AgendaPro — a prévia fala as mesmas palavras do link

     node tests/vocabulario-previa.test.mjs

   ── O RELATO ───────────────────────────────────────────────────────────────
   Dois prints da Barbearia Lima: a prévia dizia "Nossos serviços" e "Quem
   atende"; o link, "Nossos cortes" e "Quem corta" — com um cartão de Barba
   embaixo. "Tem que aparecer Nossos serviços, e não cortes." A barbearia
   passou a falar "Nossos serviços", "Quem atende" e "Agendar horário"; e a
   prévia, que escrevia as palavras do salão para todo tipo de negócio, passou
   a usar as do link.

   ── O QUE ESTE ARQUIVO PROTEGE ─────────────────────────────────────────────
     1. A barbearia não fala mais de "corte" nos títulos nem no botão.
     2. Para CADA tipo de negócio do link (o VOCABULARIO do agendar.html), a
        prévia (o VOC_DO_TIPO do app.html) diz o mesmo botão, o mesmo título
        dos serviços e o mesmo título da equipe.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);

const link = fs.readFileSync(path.join(RAIZ, 'agendar.html'), 'utf8');
const painel = fs.readFileSync(path.join(RAIZ, 'app.html'), 'utf8');
const trecho = (txt, de, ate) => { const i = txt.indexOf(de); if(i < 0) return null;
  const f = txt.indexOf(ate, i); return f < 0 ? null : txt.slice(i, f + ate.length); };

const vocLink = trecho(link, 'const VOCABULARIO = {', '\n};');
const vocPrev = trecho(painel, 'const VOC_DO_TIPO = {', '\n};');
const padrao  = trecho(painel, 'const VOC_PADRAO = ', ';\n');
const funcao  = trecho(painel, 'const vocPrevia = ', ';\n');
if(!vocLink || !vocPrev || !padrao || !funcao){
  nao('achei o vocabulário nos dois arquivos', JSON.stringify({ vocLink: !!vocLink, vocPrev: !!vocPrev, padrao: !!padrao, funcao: !!funcao }));
  process.exit(1);
}
const VOCABULARIO = new Function(vocLink + '; return VOCABULARIO;')();
const vocPrevia = new Function(vocPrev + padrao + funcao + ' return vocPrevia;')();

console.log('\n1. A barbearia');
igual('fala "Nossos serviços", "Quem atende" e "Agendar horário" — nenhum "corte"',
  [VOCABULARIO.barbearia.oferecemos, VOCABULARIO.barbearia.atende, VOCABULARIO.barbearia.acao],
  ['Nossos serviços', 'Quem atende', 'Agendar horário']);

console.log('\n2. Cada tipo de negócio: a prévia = o link');
for(const tipo of Object.keys(VOCABULARIO)){
  const l = VOCABULARIO[tipo], sl = { tipo };
  igual(`${tipo}: botão, título dos serviços e título da equipe`,
    [vocPrevia(sl, 'acao'), vocPrevia(sl, 'oferecemos'), vocPrevia(sl, 'atende')],
    [l.acao, l.oferecemos, l.atende]);
}
igual('salão sem tipo: as palavras do salão', [vocPrevia({}, 'acao'), vocPrevia({}, 'oferecemos'), vocPrevia({}, 'atende')],
  [VOCABULARIO.salao.acao, VOCABULARIO.salao.oferecemos, VOCABULARIO.salao.atende]);

console.log(falhou ? `\n✗ ${falhou} de ${passou + falhou} falharam.` : `\n✓ ${passou} passaram, 0 falharam.`);
process.exit(falhou ? 1 : 0);
