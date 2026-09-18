/* ===========================================================================
   AgendaPro — o cadastro que a cliente preenche antes de confirmar

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/cadastro-cliente.test.mjs

   ── O QUE MUDOU, E O QUE ESTÁ EM JOGO ──────────────────────────────────────
   O link pedia nome e WhatsApp. Agora pede também o aniversário — e oferece
   o e-mail, que é opcional.

   Cada campo novo num formulário de marcação é um lugar a mais onde a pessoa
   desiste. Quem chega pelo Instagram para ver quanto custa uma escova não
   está com paciência de cadastro, e o número que mede isso não aparece em
   teste nenhum: são as marcações que deixam de existir.

   Por isso o que este arquivo cobra não é só "os campos estão lá". É:

     · que o cadastro fique NO FIM, depois do preço e do horário;
     · que seja UMA VEZ SÓ — o aparelho lembra, e a segunda marcação não
       pede nada de novo;
     · que o e-mail seja de verdade opcional, e não opcional no rótulo e
       obrigatório na validação;
     · que o que ela digitou não sobrescreva o que o salão corrigiu.

   ⚠ E a ficha do painel: a coluna `clientes.email` existia desde o começo e
   não tinha campo na tela. Enquanto ninguém digitava, ninguém sentia falta.
   Com o link PEDINDO o e-mail, a ausência vira defeito — o dono vê a cliente
   preencher e não encontra em lugar nenhum.
   =========================================================================== */
import { createRequire } from 'node:module';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BASE = process.env.BASE || 'http://127.0.0.1:8099/';

let ok = 0, ruim = 0;
const e = (m, c, d) => c ? (console.log('  ✓ ' + m), ok++)
                         : (console.log('  ✗ ' + m + (d ? '\n      ' + d : '')), ruim++);

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:430, height:860 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });
p.on('dialog', d => d.accept());

await p.goto(BASE + 'agendar.html?salao=studio-bella&demo=1');
await p.waitForTimeout(2200);

/* Chega ao passo do cadastro pelo caminho de sempre: serviço, profissional e
   um horário de verdade da lista. Escolher o horário pela tela, e não à mão,
   é o que mantém o teste preso ao caminho que a pessoa percorre. */
const chegarAosDados = async () => {
  await p.evaluate(() => {
    escolha.servicos = [bd.servicos.filter(s => s.salaoId === salao.id && s.ativo)[0].id];
    escolha.profissionalId =
      bd.profissionais.filter(x => x.salaoId === salao.id && x.ativo)[0].id;
    irPara('quando');
  });
  await p.waitForTimeout(500);
  await p.evaluate(() => {
    const b = [...document.querySelectorAll('#p-quando button')]
      .find(x => /^\d\d:\d\d$/.test(x.textContent.trim()));
    if(b) b.click();
  });
  await p.waitForTimeout(250);
  await p.evaluate(() => irPara('dados'));
  await p.waitForTimeout(300);
};

const preencher = (nome, tel, nasc, email) => p.evaluate(([n, t, d, m]) => {
  document.getElementById('dNome').value  = n;
  document.getElementById('dTel').value   = t;
  document.getElementById('dNasc').value  = d;
  document.getElementById('dEmail').value = m;
  salvarDados();
  return { tela, aviso: (document.getElementById('avisoDados').innerText || '').trim() };
}, [nome, tel, nasc, email]);

await chegarAosDados();

/* ── 1 · A tela ──────────────────────────────────────────────────────────── */
console.log('\nO passo do cadastro');

const tela = await p.evaluate(() => ({
  titulo: document.querySelector('#p-dados h2').textContent.trim(),
  sub:    document.querySelector('#p-dados .sub').textContent.trim(),
  campos: [...document.querySelectorAll('#p-dados input')].map(i => i.id),
  max:    document.getElementById('dNasc').max,
  rotulos: [...document.querySelectorAll('#p-dados label')]
             .map(l => l.textContent.replace(/\s+/g, ' ').trim()),
}));
console.log('      ' + JSON.stringify(tela.campos));
e('os quatro campos do cadastro estão na tela',
  ['dNome','dTel','dNasc','dEmail'].every(x => tela.campos.includes(x)),
  JSON.stringify(tela.campos));
e('e a tela se chama "Seu cadastro" — ' + tela.titulo,
  /cadastro/i.test(tela.titulo), tela.titulo);
/* A promessa de "só na primeira vez" é o que compra a paciência da pessoa
   para preencher. Se ela não estiver escrita, o campo a mais parece
   permanente. */
e('e promete que é só na primeira vez',
  /primeira vez/i.test(tela.sub), tela.sub);
e('o e-mail é marcado como opcional NO RÓTULO, onde o olho está',
  tela.rotulos.some(r => /e-mail/i.test(r) && /opcional/i.test(r)),
  JSON.stringify(tela.rotulos));
/* Sem `max`, o seletor de data oferece 2035 de bandeja — e a pessoa só
   descobre o problema depois, no fim do caminho. */
e('e o calendário do aniversário fecha em hoje — ' + tela.max,
  /^\d{4}-\d{2}-\d{2}$/.test(tela.max || ''), String(tela.max));

/* ⚠ O CADASTRO FICA NO FIM, E ISTO É O QUE MAIS IMPORTA AQUI.
   Quem chega só para ver o preço não pode esbarrar num formulário antes
   dele. É a diferença entre um visitante que vira cliente e um que fecha a
   aba. */
const ordem = await p.evaluate(() => {
  const passos = [...document.querySelectorAll('.passo')].map(s => s.id);
  return { passos, iDados: passos.indexOf('p-dados'),
           iServico: passos.indexOf('p-servico'), iQuando: passos.indexOf('p-quando') };
});
e('e ele vem DEPOIS do serviço e do horário, nunca na entrada',
  ordem.iDados > ordem.iServico && ordem.iDados > ordem.iQuando,
  JSON.stringify(ordem));

/* ── 2 · O que passa e o que não passa ───────────────────────────────────── */
console.log('\nO que o formulário aceita');

const semNome = await preencher('', '(11) 98888-7777', '1990-04-17', '');
e('sem nome, não passa', semNome.tela === 'dados' && /nome/i.test(semNome.aviso),
  JSON.stringify(semNome));

const semTel = await preencher('Marta Prado', '9999', '1990-04-17', '');
e('sem WhatsApp completo, não passa',
  semTel.tela === 'dados' && /whatsapp|ddd/i.test(semTel.aviso),
  JSON.stringify(semTel));

const semNasc = await preencher('Marta Prado', '(11) 98888-7777', '', '');
e('sem aniversário, não passa',
  semNasc.tela === 'dados' && /anivers/i.test(semNasc.aviso),
  JSON.stringify(semNasc));

const futuro = await preencher('Marta Prado', '(11) 98888-7777', '2099-01-01', '');
/* Barrado AQUI e não no banco: deixar passar faria a pessoa levar a recusa
   no fim do caminho, quando já achava que tinha terminado. */
e('aniversário que ainda não chegou, não passa',
  futuro.tela === 'dados' && /não chegou|ano/i.test(futuro.aviso),
  JSON.stringify(futuro));

const antigo = await preencher('Marta Prado', '(11) 98888-7777', '1802-05-01', '');
e('e ano absurdo também não',
  antigo.tela === 'dados' && /ano/i.test(antigo.aviso), JSON.stringify(antigo));

const emailTorto = await preencher('Marta Prado', '(11) 98888-7777',
                                   '1990-04-17', 'marta@');
e('e-mail pela metade, não passa',
  emailTorto.tela === 'dados' && /e-mail/i.test(emailTorto.aviso),
  JSON.stringify(emailTorto));

/* ⚠ OPCIONAL NO RÓTULO TEM QUE SER OPCIONAL NA VALIDAÇÃO.
   Campo escrito "opcional" que barra em branco é a pior combinação: a pessoa
   lê que pode pular, pula, e leva um "não" que não entende. */
const semEmail = await preencher('Marta Prado', '(11) 98888-7777', '1990-04-17', '');
e('mas SEM e-mail passa — ele é opcional de verdade',
  semEmail.tela === 'confirmar', JSON.stringify(semEmail));

/* ── 3 · O que fica gravado ──────────────────────────────────────────────── */
console.log('\nO que vai para a ficha');

await p.evaluate(() => irPara('dados'));
await p.waitForTimeout(250);
const completo = await preencher('Marta Prado', '(11) 98888-7777',
                                 '1990-04-17', 'marta@exemplo.com');
e('com tudo preenchido, segue para a confirmação',
  completo.tela === 'confirmar', JSON.stringify(completo));

const ficha = await p.evaluate(() => {
  const c = bd.clientes.find(x => x.nome === 'Marta Prado');
  return c ? { nome:c.nome, nascimento:c.nascimento, email:c.email } : null;
});
e('a ficha guardou o aniversário — ' + (ficha || {}).nascimento,
  ficha && ficha.nascimento === '1990-04-17', JSON.stringify(ficha));
e('e o e-mail', ficha && ficha.email === 'marta@exemplo.com', JSON.stringify(ficha));

/* ── 4 · Só na primeira vez ──────────────────────────────────────────────── */
console.log('\nA segunda marcação');

const lembrou = await p.evaluate(() => {
  // Esquece o que está na tela, como se fosse uma visita nova.
  for(const i of ['dNome','dTel','dNasc','dEmail']) document.getElementById(i).value = '';
  desenharDados();
  return {
    nome:  document.getElementById('dNome').value,
    tel:   document.getElementById('dTel').value,
    nasc:  document.getElementById('dNasc').value,
    email: document.getElementById('dEmail').value,
    recado: (document.getElementById('reconhecido').innerText || '').trim(),
  };
});
console.log('      ' + JSON.stringify(lembrou));
/* Sem isto, "só na primeira vez" seria propaganda enganosa escrita na
   própria tela: quem marca todo mês redigitaria o aniversário doze vezes
   por ano. */
e('o aparelho devolve o cadastro inteiro, e não só nome e telefone',
  lembrou.nome === 'Marta Prado' && lembrou.nasc === '1990-04-17'
  && lembrou.email === 'marta@exemplo.com' && !!lembrou.tel,
  JSON.stringify(lembrou));
e('e diz de quem ele está lembrando, para quem não for ela poder trocar',
  /Marta Prado/.test(lembrou.recado), lembrou.recado);

/* ⚠ QUEM MANDA NA FICHA É O SALÃO — a mesma regra do `agendar()` no
   09_cliente.sql, que aqui precisa valer igual porque na demonstração não há
   banco para aplicá-la. Se as duas divergirem, o mesmo gesto dá resultado
   diferente na demonstração e na nuvem, e quem descobre é o dono achando que
   achou um defeito num dos dois. */
const naoDesfaz = await p.evaluate(() => {
  const c = bd.clientes.find(x => x.nome === 'Marta Prado');
  c.email = 'marta.prado@certo.com';          // a recepção corrigiu
  garantirFicha('Marta Prado', '(11) 98888-7777', '1990-04-17', 'marta@exemplo.com');
  return bd.clientes.find(x => x.nome === 'Marta Prado').email;
});
e('a correção da recepção não é desfeita pelo navegador da cliente',
  naoDesfaz === 'marta.prado@certo.com', naoDesfaz);

const completaOVazio = await p.evaluate(() => {
  const c = bd.clientes.find(x => x.nome === 'Marta Prado');
  c.nascimento = '';                          // ficha pela metade
  garantirFicha('Marta Prado', '(11) 98888-7777', '1988-02-02', 'marta@exemplo.com');
  const d = bd.clientes.find(x => x.nome === 'Marta Prado');
  return { nasc: d.nascimento, email: d.email };
});
e('mas o campo que estava VAZIO é preenchido',
  completaOVazio.nasc === '1988-02-02', JSON.stringify(completaOVazio));
e('e o preenchimento de um não mexe no outro',
  completaOVazio.email === 'marta.prado@certo.com', JSON.stringify(completaOVazio));

/* ── 5 · No celular ──────────────────────────────────────────────────────── */
console.log('\nNo celular');

await p.evaluate(() => irPara('dados'));
await p.waitForTimeout(300);
const cel = await p.evaluate(() => {
  const raiz = document.getElementById('p-dados');
  const pequenos = [...raiz.querySelectorAll('input, button, select')]
    .filter(el => { const r = el.getBoundingClientRect();
                    return r.height > 0 && r.height < 40; })
    .map(el => el.id || el.tagName);
  const miudos = [...raiz.querySelectorAll('*')]
    .filter(el => !el.children.length && (el.textContent || '').trim())
    .filter(el => parseFloat(getComputedStyle(el).fontSize) < 11)
    .map(el => (el.textContent || '').trim().slice(0, 24));
  /* 16px no <input> é o que impede o iOS de dar zoom sozinho ao tocar no
     campo — e o zoom desloca a tela inteira no meio do preenchimento. */
  const miopes = [...raiz.querySelectorAll('input')]
    .filter(el => parseFloat(getComputedStyle(el).fontSize) < 16)
    .map(el => el.id);
  return {
    vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    pequenos, miudos, miopes,
  };
});
console.log('      430px: ' + JSON.stringify(cel));
e('a página não rola para o lado', cel.vaza === 0, 'sobram ' + cel.vaza + 'px');
e('todo campo tem os 40px de alvo da casa', !cel.pequenos.length,
  JSON.stringify(cel.pequenos));
e('nenhum texto abaixo de 11px', !cel.miudos.length, JSON.stringify(cel.miudos));
e('e nenhum campo abaixo de 16px, que faria o iPhone dar zoom sozinho',
  !cel.miopes.length, JSON.stringify(cel.miopes));

/* ── 6 · A ficha do painel ───────────────────────────────────────────────── */
console.log('\nO e-mail na ficha do painel');

const painel = await ctx.newPage();
painel.on('pageerror', x => erros.push('painel pageerror: ' + x.message));
painel.on('dialog', d => d.accept());
await painel.setViewportSize({ width:1280, height:900 });
await painel.goto(BASE + 'app.html?demo=1');
await painel.waitForTimeout(2200);

const naFicha = await painel.evaluate(() => {
  const c = doSalao(bd.clientes)[0];
  abrirCliente(c.id);
  return {
    tem: !!document.getElementById('kEmail'),
    valor: (document.getElementById('kEmail') || {}).value,
    idDoCliente: c.id,
  };
});
/* A coluna existe desde o primeiro dia; o campo é que faltava. Com o link
   PEDINDO o e-mail, um dado que entra e não aparece é pior que dado nenhum. */
e('a ficha do painel tem o campo de e-mail', naFicha.tem,
  'a cliente preenche pelo link e o dono não encontra em lugar nenhum');

const gravou = await painel.evaluate(cid => {
  document.getElementById('kEmail').value = 'novo@exemplo.com';
  salvarCliente(cid);
  return (bd.clientes.find(c => c.id === cid) || {}).email;
}, naFicha.idDoCliente);
e('e o que o dono digita ali é gravado', gravou === 'novo@exemplo.com', gravou);

const voltou = await painel.evaluate(cid => {
  abrirCliente(cid);
  return document.getElementById('kEmail').value;
}, naFicha.idDoCliente);
e('e reaparece ao abrir a ficha de novo', voltou === 'novo@exemplo.com', voltou);

e('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
