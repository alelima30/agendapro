/* ===========================================================================
   AgendaPro — o passo a passo do primeiro dia

     python3 -m http.server 8099 --directory .
     PLAYWRIGHT=… node tests/primeiro-dia.test.mjs

   ── O QUE ESTE ARQUIVO GUARDA ──────────────────────────────────────────────
   O assistente é a única tela do sistema que ESCREVE CADASTRO SOZINHA. Um
   toque cria serviço, produto e profissional de verdade, nas mesmas tabelas
   que a tela de Serviços usa — e um erro aqui não aparece como tela quebrada,
   aparece como preço errado na parede do salão, ou como profissional sem
   coluna na agenda.

   Por isso quase toda verificação daqui olha o `bd` depois do clique, e não a
   tela: o que importa é o que ficou gravado.

   As três que mais custaram para existir:

     · o horário POUSA em alguém. `jornadas` tem `profissional_id`; horário
       guardado só no `cfg` do salão é um ajuste bonito que não abre um único
       horário na agenda.

     · quem já tem horário próprio NÃO é sobrescrito. A pessoa que sai às 16h
       na sexta não pode voltar às 19h porque o dono reabriu o assistente.

     · `produtos.comissao_pct` é `not null` — ao contrário da coluna do
       serviço. Null aqui faz o Postgres recusar a gravação INTEIRA da tela,
       e o cadastro inteiro se perde por causa de um campo em branco.
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
const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
const p = await ctx.newPage();
const erros = [];
let avisos = [];
p.on('pageerror', x => erros.push('pageerror: ' + x.message));
p.on('console', c => { if(c.type() === 'error') erros.push('console: ' + c.text()); });
p.on('dialog', d => { avisos.push(d.message()); d.accept(); });

await p.goto(BASE + 'app.html?demo=1');
await p.waitForTimeout(2200);

/* Deixa o salão como um salão recém-cadastrado: sem serviço, sem equipe, sem
   produto e sem marca nenhuma do assistente. É o estado que a pessoa encontra
   no minuto seguinte ao cadastro. */
const esvaziar = () => p.evaluate(() => {
  bd.servicos      = bd.servicos.filter(s => s.salaoId !== salaoAtual);
  bd.profissionais = bd.profissionais.filter(x => x.salaoId !== salaoAtual);
  bd.produtos      = (bd.produtos || []).filter(x => x.salaoId !== salaoAtual);
  bd.agendamentos  = []; bd.comandas = []; bd.pacote_servicos = [];
  const sl = acharSalao(salaoAtual);
  sl.cfg = Object.assign({}, sl.cfg, { primeiroDia:null, horario:null });
  pdOferecido.clear();
  pdHorario = null; pdCategorias = null; pdProdutosSim = null; pdDoSalao = null;
  salvar();
});

/* ── 1 · Quando ele aparece, e quando não aparece ────────────────────────── */
console.log('\nQuando o assistente aparece sozinho');

await esvaziar();
await p.evaluate(() => iniciar());
await p.waitForTimeout(500);
e('salão vazio: ele abre sozinho, no passo 1',
  await p.evaluate(() => !document.getElementById('primeiroDia').hidden
    && document.getElementById('pdContador').textContent === 'Passo 1 de 8'),
  await p.evaluate(() => document.getElementById('pdContador').textContent));

/* ⚠ QUEM TRABALHA NA RECEPÇÃO NÃO DECIDE PREÇO DE SERVIÇO.
   Um assistente de oito passos de cadastro caindo na tela dela seria oferecer
   um trabalho que não é dela — e que o RLS recusaria no meio do caminho. */
const semRecepcao = await p.evaluate(() => {
  document.getElementById('primeiroDia').hidden = true;
  pdOferecido.clear();
  const antes = window.meuPapel;
  window.meuPapel = () => 'recepcao';
  iniciar();
  const abriu = !document.getElementById('primeiroDia').hidden;
  window.meuPapel = antes;
  return abriu;
});
e('para quem é da recepção, não abre', !semRecepcao,
  'a recepcionista recebeu um cadastro de serviços para fazer');

const jaMontado = await p.evaluate(() => {
  document.getElementById('primeiroDia').hidden = true;
  pdOferecido.clear();
  bd.servicos.push({ id:id(), salaoId:salaoAtual, nome:'Corte', categoria:'',
    duracaoMin:30, intervaloMin:0, preco:40, comissaoPct:null,
    comissaoFixa:null, foto:null, ativo:true });
  bd.profissionais.push({ id:id(), salaoId:salaoAtual, nome:'Ana',
    comissaoPct:0, comissaoFixa:null, cor:'#2563EB', ativo:true, telefone:null,
    notifNovo:true, notifResumo:false, foto:null, jornada:{ 1:[[540,1140]] } });
  salvar(); iniciar();
  return !document.getElementById('primeiroDia').hidden;
});
/* Quem já usava o sistema antes de este assistente existir não pode receber
   um passo a passo de cadastro — seria sugerir que falta alguma coisa. */
e('salão que já tem serviço e horário: não abre', !jaMontado,
  'o assistente apareceu para um salão que já estava funcionando');

await esvaziar();
await p.evaluate(() => { document.getElementById('primeiroDia').hidden = true; });

/* ── 2 · A barra e o contador ────────────────────────────────────────────── */
console.log('\nA barra de progresso');

await p.evaluate(() => abrirPrimeiroDia(1));
await p.waitForTimeout(200);
const passos = [];
for(let i = 1; i <= 8; i++){
  passos.push(await p.evaluate(() => ({
    contador: document.getElementById('pdContador').textContent,
    titulo:   document.getElementById('pdTitulo').textContent,
    barra:    document.getElementById('pdBarra').style.width,
    corpo:    document.getElementById('pdCorpo').innerHTML.length,
    voltar:   document.getElementById('pdVoltar').style.visibility,
    proximo:  document.getElementById('pdProximo').textContent.trim(),
  })));
  if(i < 8) await p.evaluate(() => pdAndar(1));
  await p.waitForTimeout(120);
}
e('os oito passos têm título e corpo',
  passos.every(x => x.titulo.length > 3 && x.corpo > 100),
  JSON.stringify(passos.map(x => [x.titulo, x.corpo])));
e('o contador acompanha — ' + passos.map((_, i) => i + 1).join(','),
  passos.every((x, i) => x.contador === 'Passo ' + (i + 1) + ' de 8'),
  JSON.stringify(passos.map(x => x.contador)));
e('a barra cresce até 100% — ' + passos.map(x => x.barra).join(' '),
  passos[0].barra === '13%' && passos[7].barra === '100%'
  && passos.every((x, i) => i === 0 || parseInt(x.barra) > parseInt(passos[i-1].barra)),
  JSON.stringify(passos.map(x => x.barra)));
/* Sumindo em vez de ficar invisível, os outros botões do rodapé pulariam de
   lugar entre o primeiro passo e o segundo. */
e('no passo 1 o "Voltar" fica invisível, mas ocupa o lugar dele',
  passos[0].voltar === 'hidden' && passos[1].voltar !== 'hidden');
e('no último passo o botão diz "Terminei", e não "Próximo"',
  /Terminei/.test(passos[7].proximo) && passos.slice(0, 7)
    .every(x => /Próximo/.test(x.proximo)), passos[7].proximo);

/* ── 3 · O horário ───────────────────────────────────────────────────────── */
console.log('\nO horário de atendimento');

await p.evaluate(() => { pdPasso = 2; pdDesenhar(); });
await p.waitForTimeout(200);

const semana = await p.evaluate(() => ({
  cartoes: document.querySelectorAll('#pdCorpo .pd-dia').length,
  fechados: [...document.querySelectorAll('#pdCorpo .pd-dia.fechado')].length,
  primeiro: document.querySelector('#pdCorpo .pd-dia b').textContent.trim(),
  ultimo: [...document.querySelectorAll('#pdCorpo .pd-dia b')].pop().textContent.trim(),
}));
e('os sete dias aparecem, de segunda a domingo — ' + semana.primeiro
  + ' … ' + semana.ultimo,
  semana.cartoes === 7 && semana.primeiro === 'segunda' && semana.ultimo === 'domingo',
  JSON.stringify(semana));
e('e domingo nasce fechado, como quase todo salão', semana.fechados === 1,
  semana.fechados + ' dias fechados');

/* ⚠ COPIAR NÃO PODE ABRIR DOMINGO DE BRINDE.
   Quem tem o mesmo horário de segunda a sexta aperta "copiar" sem pensar. Se
   o botão abrisse todos os dias, o salão descobriria isso no primeiro domingo
   em que uma cliente marcasse — e alguém teria que ir trabalhar. */
const copiou = await p.evaluate(() => {
  document.getElementById('pdH1a').value = '08:00';
  document.getElementById('pdH1b').value = '18:00';
  pdCopiarDia(1);
  const h = pdHorarioAtual();
  return { segunda: h[1], terca: h[2], sabado: h[6], domingo: h[0] || null };
});
e('copiar leva o horário para os outros dias abertos',
  JSON.stringify(copiou.terca) === '[[480,1080]]'
  && JSON.stringify(copiou.sabado) === '[[480,1080]]',
  JSON.stringify(copiou));
e('e NÃO abre o dia que estava fechado', copiou.domingo === null,
  'o domingo abriu sozinho: ' + JSON.stringify(copiou.domingo));

const virou = await p.evaluate(() => {
  pdVirarDia(0);
  const abriu = !!pdHorarioAtual()[0];
  pdVirarDia(0);
  return { abriu, fechou: !pdHorarioAtual()[0] };
});
e('abrir e fechar um dia funciona nos dois sentidos',
  virou.abriu && virou.fechou, JSON.stringify(virou));

const almoco = await p.evaluate(() => {
  pdAlmoco(1, true);
  const com = pdHorarioAtual()[1];
  pdAlmoco(1, false);
  return { com, sem: pdHorarioAtual()[1] };
});
e('o intervalo de almoço parte o dia em duas faixas — '
  + JSON.stringify(almoco.com),
  almoco.com.length === 2 && almoco.com[0][1] < almoco.com[1][0]
  && almoco.com[0][0] === 480 && almoco.com[1][1] === 1080,
  JSON.stringify(almoco));
e('e tirar o intervalo junta de volta num dia só',
  JSON.stringify(almoco.sem) === '[[480,1080]]', JSON.stringify(almoco.sem));

/* ⚠ HORA INVERTIDA NÃO PODE PASSAR CALADA, E NEM APAGAR O DIA.
   Apagar seria o assistente fechando a terça por conta própria porque alguém
   digitou 18:00 no campo de abrir. */
avisos = [];
const invertido = await p.evaluate(() => {
  const antes = pdPasso;
  document.getElementById('pdH2a').value = '18:00';
  document.getElementById('pdH2b').value = '09:00';
  pdAndar(1);
  return { ficou: pdPasso === antes, terca: pdHorarioAtual()[2] };
});
await p.waitForTimeout(120);
e('hora invertida barra o "Próximo"', invertido.ficou,
  'o assistente avançou com a terça de 18h às 9h');
e('e o aviso diz QUAL é o dia', /terça/i.test(avisos.join(' ')),
  avisos.join(' | ') || '(nenhum aviso)');
e('e o dia continua aberto — não foi apagado pelo erro',
  !!invertido.terca, JSON.stringify(invertido.terca));

await p.evaluate(() => {
  document.getElementById('pdH2a').value = '08:00';
  document.getElementById('pdH2b').value = '18:00';
  pdLer2();
});

/* ── 4 · O horário pousa em alguém ───────────────────────────────────────── */
console.log('\nO horário vira agenda de verdade');

const pousou = await p.evaluate(() => {
  // Uma pessoa sem horário nenhum, e outra com horário próprio.
  bd.profissionais.push(
    { id:'pd-sem', salaoId:salaoAtual, nome:'Sem horário', comissaoPct:0,
      comissaoFixa:null, cor:'#2563EB', ativo:true, telefone:null,
      notifNovo:true, notifResumo:false, foto:null, jornada:{} },
    { id:'pd-com', salaoId:salaoAtual, nome:'Sai às 16h', comissaoPct:0,
      comissaoFixa:null, cor:'#7C3AED', ativo:true, telefone:null,
      notifNovo:true, notifResumo:false, foto:null, jornada:{ 5:[[540,960]] } });
  pdAplicarHorario();
  return {
    sem: acharProf('pd-sem').jornada,
    com: acharProf('pd-com').jornada,
    cfg: (acharSalao(salaoAtual).cfg || {}).horario,
  };
});
e('quem não tinha horário recebe o do salão',
  JSON.stringify(pousou.sem[1]) === '[[480,1080]]',
  JSON.stringify(pousou.sem));
/* Sem esta linha, reabrir o assistente devolveria a pessoa ao horário da
   casa — e ela descobriria no dia em que uma cliente marcasse às 18h numa
   sexta em que ela já foi embora. */
e('e quem já tinha horário próprio NÃO é mexido',
  JSON.stringify(pousou.com) === '{"5":[[540,960]]}',
  JSON.stringify(pousou.com));
e('o horário do salão também fica guardado, para os próximos cadastros',
  pousou.cfg && JSON.stringify(pousou.cfg[1]) === '[[480,1080]]',
  JSON.stringify(pousou.cfg));

await p.evaluate(() => {
  bd.profissionais = bd.profissionais.filter(x => !String(x.id).startsWith('pd-'));
  salvar();
});

/* ── 5 · As categorias e os serviços ─────────────────────────────────────── */
console.log('\nOs serviços, num toque');

await p.evaluate(() => { pdPasso = 3; pdCategorias = null; pdDesenhar(); });
await p.waitForTimeout(150);
const cats = await p.evaluate(() => ({
  total: document.querySelectorAll('#pdCorpo .pd-op').length,
  marcadas: [...document.querySelectorAll('#pdCorpo .pd-op.on')]
    .map(b => b.textContent.trim().replace(/\s*✓$/, '')),
  tipo: acharSalao(salaoAtual).tipo,
}));
e('todas as categorias aparecem — ' + cats.total, cats.total === 12,
  String(cats.total));
/* O tipo PRÉ-MARCA, e nada mais: uma barbearia que faz sobrancelha existe, e
   esconder a opção para manter o palpite limpo seria o palpite mandando. */
e('e as do tipo de negócio (' + cats.tipo + ') já vêm marcadas — '
  + cats.marcadas.join(', '),
  cats.marcadas.length >= 1 && cats.marcadas.length < 12,
  JSON.stringify(cats.marcadas));

await p.evaluate(() => { pdPasso = 4; pdDesenhar(); });
await p.waitForTimeout(150);

const criou = await p.evaluate(() => {
  const antes = doSalao(bd.servicos).length;
  pdVirarServico('cabelo', 1);          // Corte masculino, 30 min, R$ 40
  const s = doSalao(bd.servicos).find(x => x.nome === 'Corte masculino');
  return { antes, depois: doSalao(bd.servicos).length, s };
});
e('um toque cadastra o serviço',
  criou.depois === criou.antes + 1 && !!criou.s, JSON.stringify(criou));
/* O preço é chute — mas é o chute ESCRITO NO BOTÃO. O que não pode acontecer
   é a tela oferecer R$ 40 e o cadastro nascer com outro número. */
e('com a duração e o preço que o botão prometia — '
  + (criou.s || {}).duracaoMin + ' min, ' + (criou.s || {}).preco,
  criou.s && criou.s.duracaoMin === 30 && criou.s.preco === 40
  && criou.s.categoria === 'Cabelo' && criou.s.ativo === true
  && criou.s.salaoId === (await p.evaluate(() => salaoAtual)),
  JSON.stringify(criou.s));
e('e o botão fica marcado depois do toque',
  await p.evaluate(() => [...document.querySelectorAll('#pdCorpo .pd-sug.on')]
    .some(b => /Corte masculino/.test(b.textContent))));

const tirou = await p.evaluate(() => {
  pdVirarServico('cabelo', 1);
  return doSalao(bd.servicos).some(x => x.nome === 'Corte masculino');
});
e('tocar de novo tira o serviço', !tirou, 'o serviço ficou cadastrado');

/* ⚠ CADASTRO EM USO NÃO SOME POR UM TOQUE DISTRAÍDO.
   Ele está preso a atendimentos que já aconteceram; apagar deixaria a agenda
   e o relatório apontando para o nada. */
avisos = [];
const emUso = await p.evaluate(() => {
  pdVirarServico('cabelo', 1);
  const s = doSalao(bd.servicos).find(x => x.nome === 'Corte masculino');
  bd.agendamentos.push({ id:id(), salaoId:salaoAtual, data:'2026-01-05',
    inicio:540, fim:570, status:'concluido',
    servicos:[{ servicoId:s.id, duracaoMin:30, preco:40 }] });
  pdVirarServico('cabelo', 1);
  return doSalao(bd.servicos).some(x => x.id === s.id);
});
await p.waitForTimeout(120);
e('serviço já usado na agenda não é apagado pelo assistente', emUso,
  'um serviço com atendimento no histórico sumiu');
e('e o aviso ensina o caminho certo: desativar em Serviços',
  /desative em Serviços/i.test(avisos.join(' ')),
  avisos.join(' | ') || '(nenhum aviso)');

await p.evaluate(() => { bd.agendamentos = []; salvar(); });

const aMao = await p.evaluate(() => {
  document.getElementById('pdSvNome').value  = 'Corte na régua';
  document.getElementById('pdSvDur').value   = '45';
  document.getElementById('pdSvPreco').value = '55';
  pdServicoAMao();
  return doSalao(bd.servicos).find(x => x.nome === 'Corte na régua');
});
e('o que não está na lista entra à mão — 45 min, R$ 55',
  aMao && aMao.duracaoMin === 45 && aMao.preco === 55 && aMao.ativo === true,
  JSON.stringify(aMao));

/* ── 6 · A equipe ────────────────────────────────────────────────────────── */
console.log('\nA equipe');

await p.evaluate(() => { pdPasso = 5; pdDesenhar(); });
await p.waitForTimeout(150);

const equipe = await p.evaluate(() => {
  document.getElementById('pdEqNome').value = 'Bianca';
  pdEquipeAMao();
  const b = doSalao(bd.profissionais).find(x => x.nome === 'Bianca');
  return { b, horario: (acharSalao(salaoAtual).cfg || {}).horario };
});
e('quem entra na equipe nasce ativo e com cor própria',
  equipe.b && equipe.b.ativo === true && /^#[0-9A-F]{6}$/i.test(equipe.b.cor || ''),
  JSON.stringify(equipe.b && { ativo: equipe.b.ativo, cor: equipe.b.cor }));
/* Profissional sem jornada não tem coluna na agenda — seria um cadastro que
   não atende ninguém, e o dono só descobriria ao abrir a agenda no dia. */
e('e já com o horário do salão, senão não teria coluna na agenda',
  equipe.b && JSON.stringify(equipe.b.jornada) === JSON.stringify(equipe.horario),
  JSON.stringify(equipe.b && equipe.b.jornada));

avisos = [];
const naoTira = await p.evaluate(() => {
  const b = doSalao(bd.profissionais).find(x => x.nome === 'Bianca');
  bd.agendamentos.push({ id:id(), salaoId:salaoAtual, profissionalId:b.id,
    data:'2026-01-05', inicio:540, fim:570, status:'concluido', servicos:[] });
  pdTirarDaEquipe(b.id);
  return doSalao(bd.profissionais).some(x => x.id === b.id);
});
await p.waitForTimeout(120);
e('quem já tem atendimento na agenda não é apagado', naoTira,
  'a pessoa sumiu, e com ela a comissão do que já atendeu');
e('e o aviso ensina o caminho: desativar em Equipe',
  /desative em Equipe/i.test(avisos.join(' ')),
  avisos.join(' | ') || '(nenhum aviso)');

await p.evaluate(() => { bd.agendamentos = []; salvar(); });
const saiu = await p.evaluate(() => {
  const b = doSalao(bd.profissionais).find(x => x.nome === 'Bianca');
  pdTirarDaEquipe(b.id);
  return doSalao(bd.profissionais).some(x => x.nome === 'Bianca');
});
e('sem histórico, dá para tirar', !saiu, 'não saiu');

/* ── 7 · Os produtos, se houver ──────────────────────────────────────────── */
console.log('\nOs produtos — só para quem vende');

await p.evaluate(() => { pdPasso = 6; pdProdutosSim = null; pdDesenhar(); });
await p.waitForTimeout(150);

const semProduto = await p.evaluate(() => {
  pdEscolherProdutos(false);
  return {
    sugestoes: document.querySelectorAll('#pdCorpo .pd-sug').length,
    campo: !!document.getElementById('pdPrNome'),
    texto: document.getElementById('pdCorpo').innerText,
    cfg: ((acharSalao(salaoAtual).cfg || {}).primeiroDia || {}).vendeProdutos,
  };
});
e('quem diz "só serviços" não vê lista de produto nenhuma',
  semProduto.sugestoes === 0 && !semProduto.campo,
  semProduto.sugestoes + ' sugestões');
e('e a resposta fica guardada', semProduto.cfg === false,
  String(semProduto.cfg));
e('com o recado de que a aba continua lá para depois',
  /Nada aqui é para sempre|continua no menu/i.test(semProduto.texto),
  semProduto.texto.slice(0, 160));

const comProduto = await p.evaluate(() => {
  pdEscolherProdutos(true);
  const sugestoes = document.querySelectorAll('#pdCorpo .pd-sug').length;
  pdVirarProduto('cabelo', 0);            // Shampoo, R$ 45
  const pr = doSalao(bd.produtos || []).find(x => x.nome === 'Shampoo');
  return { sugestoes, pr };
});
e('quem diz que vende recebe as sugestões da categoria dele — '
  + comProduto.sugestoes, comProduto.sugestoes > 0, String(comProduto.sugestoes));
e('e um toque cadastra o produto com o preço prometido',
  comProduto.pr && comProduto.pr.preco === 45 && comProduto.pr.ativo === true,
  JSON.stringify(comProduto.pr));
/* ⚠ ZERO, E NÃO NULL. `produtos.comissao_pct` é `not null default 0` — ao
   contrário de `servicos.comissao_pct`, que é anulável de propósito. Null
   aqui faz o Postgres recusar a gravação INTEIRA da tela, e o cadastro se
   perde por causa de um campo que ninguém preencheu. Está escrito por
   extenso no `salvarProduto()`, e custou um teste próprio para aparecer. */
e('com a comissão em ZERO, que é o que a coluna do banco aceita',
  comProduto.pr && comProduto.pr.comissaoPct === 0
  && comProduto.pr.comissaoFixa === null,
  JSON.stringify(comProduto.pr && { pct: comProduto.pr.comissaoPct,
                                    fixa: comProduto.pr.comissaoFixa }));

/* ── 8 · Como o salão trabalha ───────────────────────────────────────────── */
console.log('\nOs dois interruptores');

await p.evaluate(() => { pdPasso = 7; pdDesenhar(); });
await p.waitForTimeout(150);

const reguas = await p.evaluate(() => ({
  comanda:  document.querySelectorAll('#pdReguaComanda button').length,
  confirma: document.querySelectorAll('#pdReguaConfirma button').length,
  ligados:  document.querySelectorAll('#primeiroDia .regua button.on').length,
}));
e('as duas réguas aparecem, com uma opção acesa em cada',
  reguas.comanda === 2 && reguas.confirma === 2 && reguas.ligados === 2,
  JSON.stringify(reguas));

const gravou = await p.evaluate(() => {
  pdEscolherComanda(false);
  pdEscolherConfirma(false);
  pdGuardar7();
  const cfg = acharSalao(salaoAtual).cfg || {};
  return { usa: cfg.usaComanda, conf: cfg.confirmaAuto,
           aba: minhasTelas().some(t => t[0] === 'caixa') };
});
/* `?? true` e não `||`: com `||`, escolher "Só a agenda" gravaria `true` e a
   aba Caixa voltaria sozinha depois de salvar. */
e('escolher "Só a agenda" grava FALSE, e não volta para true',
  gravou.usa === false && gravou.conf === false, JSON.stringify(gravou));
e('e a aba Caixa some do menu na mesma hora', !gravou.aba,
  'a aba continuou no menu');

/* ⚠ UM TEXTO SÓ PARA AS DUAS TELAS.
   Esta explicação é lida aqui e em Meu salão. Duas redações envelhecem em
   velocidades diferentes, e a que envelhece é sempre a que o dono lê
   primeiro — no dia em que está decidindo. */
const mesmoTexto = await p.evaluate(() => {
  const noAssistente = document.getElementById('pdExplicaComanda').innerHTML;
  const noAssistente2 = document.getElementById('pdExplicaConfirma').innerHTML;
  document.getElementById('primeiroDia').hidden = true;
  irPara('salao');
  const emMeuSalao  = document.getElementById('explicaComanda').innerHTML;
  const emMeuSalao2 = document.getElementById('explicaConfirma').innerHTML;
  return { a: noAssistente === emMeuSalao, b: noAssistente2 === emMeuSalao2,
           amostra: noAssistente.slice(0, 60) };
});
e('a explicação da comanda é a MESMA em Meu salão', mesmoTexto.a,
  mesmoTexto.amostra);
e('e a da confirmação também', mesmoTexto.b);

const botaoDeVolta = await p.evaluate(() => {
  const bt = document.getElementById('btPrimeiroDia');
  if(!bt) return { tem:false };
  bt.click();
  return { tem:true, abriu: !document.getElementById('primeiroDia').hidden };
});
e('e Meu salão tem o botão que reabre o assistente',
  botaoDeVolta.tem && botaoDeVolta.abriu, JSON.stringify(botaoDeVolta));

await p.evaluate(() => {
  const sl = acharSalao(salaoAtual);
  sl.cfg = Object.assign({}, sl.cfg, { usaComanda:true, confirmaAuto:true });
  comandaEscolhida = null; confirmaEscolhida = null;
  salvar(); iniciar();
  document.getElementById('primeiroDia').hidden = true;
});

/* ── 9 · O link e o QR ───────────────────────────────────────────────────── */
console.log('\nO link, com o QR');

// O fecho fala do estado do salão, então o salão precisa estar num estado
// conhecido: um serviço vivo e alguém com horário para atendê-lo.
await p.evaluate(() => {
  if(!doSalao(bd.profissionais).some(temJornadaAlguma)){
    bd.profissionais.push({ id:id(), salaoId:salaoAtual, nome:'Ana',
      comissaoPct:0, comissaoFixa:null, cor:'#2563EB', ativo:true,
      telefone:null, notifNovo:true, notifResumo:false, foto:null,
      jornada:{ 1:[[540,1140]] } });
  }
  salvar();
});
await p.evaluate(() => { abrirPrimeiroDia(8); });
await p.waitForTimeout(250);

const fim = await p.evaluate(() => {
  const link = document.getElementById('pdLink');
  const svg = document.querySelector('#pdQrCaixa svg');
  return {
    link: link ? link.value : '',
    slug: acharSalao(salaoAtual).slug,
    temQr: !!svg,
    caixa: svg ? svg.getAttribute('viewBox') : null,
    rotulo: svg ? svg.getAttribute('aria-label') : null,
    largura: svg ? Math.round(svg.getBoundingClientRect().width) : 0,
    texto: document.getElementById('pdCorpo').innerText,
  };
});
e('o link é o do salão, pelo slug — ' + fim.link,
  fim.link.includes('agendar.html?salao=' + fim.slug), fim.link);
e('o QR é desenhado ao lado dele', fim.temQr && /^0 0 (\d+) \1$/.test(fim.caixa || ''),
  String(fim.caixa));
e('com rótulo para quem usa leitor de tela', /QR/i.test(fim.rotulo || ''),
  fim.rotulo);
e('e do tamanho de quem confere na tela, não de meia página — '
  + fim.largura + 'px', fim.largura > 100 && fim.largura < 220,
  String(fim.largura));

/* ⚠ O QR TEM QUE SER DO LINK QUE ESTÁ NA CAIXA AO LADO.
   Um QR impresso que leva ao salão errado fica colado na parede por meses,
   mandando cliente para outro lugar. Refeito e comparado módulo a módulo. */
const confere = await p.evaluate(() => {
  const desenhado = document.querySelector('#pdQrCaixa svg path').getAttribute('d');
  const refeito = new DOMParser()
    .parseFromString(QR.svg(document.getElementById('pdLink').value), 'image/svg+xml')
    .querySelector('path').getAttribute('d');
  return desenhado === refeito;
});
e('e o desenho é exatamente o do link que está do lado', confere,
  'o QR na parede levaria a um endereço diferente do que o dono copiou');

e('o botão de baixar aponta para a caixa DESTE passo, e não para a do painel',
  await p.evaluate(() => [...document.querySelectorAll('#pdCorpo button')]
    .some(b => (b.getAttribute('onclick') || '').includes("baixarQr('pdQrCaixa')")),
  ), 'baixaria o QR da outra tela, que num salão novo nem foi desenhada');

/* O fecho honesto: o link existe desde o primeiro minuto, e sem serviço ele
   abre e não oferece nada. Dizer "pronto!" aqui seria mentir na última tela. */
e('com serviço e equipe, o fecho diz que já dá para marcar',
  /Está tudo de pé/.test(fim.texto), fim.texto.slice(-220));

const semNada = await p.evaluate(() => {
  const guardados = bd.servicos;
  bd.servicos = bd.servicos.filter(s => s.salaoId !== salaoAtual);
  pdDesenhar();
  const txt = document.getElementById('pdCorpo').innerText;
  bd.servicos = guardados; pdDesenhar();
  return txt;
});
e('e sem serviço nenhum ele avisa que o link ainda não deixa marcar',
  /ainda não deixa marcar/i.test(semNada) && /nenhum serviço/i.test(semNada),
  semNada.slice(-220));

/* ── 10 · Fechar no meio não perde nada ──────────────────────────────────── */
console.log('\nFechar no meio, e voltar depois');

const noMeio = await p.evaluate(() => {
  abrirPrimeiroDia(1);
  pdAndar(1); pdAndar(1);            // chega no passo 3
  pdFechar();
  const marca = (acharSalao(salaoAtual).cfg || {}).primeiroDia || {};
  return { fechou: document.getElementById('primeiroDia').hidden,
           passo: marca.passo, feito: !!marca.feito };
});
e('fechar no meio guarda em que passo a pessoa parou — ' + noMeio.passo,
  noMeio.fechou && noMeio.passo === 3 && !noMeio.feito, JSON.stringify(noMeio));

const voltou = await p.evaluate(() => {
  pdOferecido.clear();
  bd.servicos = bd.servicos.filter(s => s.salaoId !== salaoAtual);
  salvar(); iniciar();
  return { abriu: !document.getElementById('primeiroDia').hidden,
           contador: document.getElementById('pdContador').textContent };
});
e('e ao voltar ele recomeça exatamente dali — ' + voltou.contador,
  voltou.abriu && voltou.contador === 'Passo 3 de 8', JSON.stringify(voltou));

const terminou = await p.evaluate(() => {
  pdPasso = 8; pdDesenhar(); pdAndar(1);      // "Terminei"
  const marca = (acharSalao(salaoAtual).cfg || {}).primeiroDia || {};
  pdOferecido.clear();
  iniciar();
  return { feito: !!marca.feito,
           voltou: !document.getElementById('primeiroDia').hidden };
});
e('terminado, ele marca que acabou', terminou.feito, JSON.stringify(terminou));
/* Assistente que reaparece depois de terminado vira lembrete de uma tarefa
   que acabou — e o botão em Meu salão é o caminho de volta para quem quiser. */
e('e nunca mais aparece sozinho, nem com o salão ainda vazio',
  !terminou.voltou, 'apareceu de novo depois de terminado');


/* ══════════════════════════════════════════════════════════════════════════
   O SALÃO QUE JÁ EXISTIA — e os quatro defeitos que ele revelou

   Tudo acima roda num salão vazio, que é o caso para o qual o assistente foi
   feito. Mas ele é REABRÍVEL, e reabri-lo num salão que já trabalha foi o
   que quebrou na mão do dono:

     · o serviço cadastrado em "Não está na lista?" não aparecia em canto
       nenhum — ia para o banco e sumia de vista. A pessoa cadastrava de
       novo, achando que não tinha funcionado;
     · ele nascia com categoria VAZIA, e serviço sem categoria cai num bloco
       solto na página da cliente;
     · a sugestão do catálogo gravava "Cabelo" onde o salão escrevia
       "cabelo", e a página da cliente passou a mostrar DUAS seções "Cabelo"
       e DUAS "Unhas";
     · e nada disso esperava o banco responder.
   ══════════════════════════════════════════════════════════════════════════ */
console.log('\nReabrindo num salão que já trabalha');

/* O salão ganha a grafia dele: tudo em "cabelo", minúsculo, como quem
   digitou à mão às pressas. */
await p.evaluate(() => {
  /* As secoes de cima esvaziam o salao de proposito. Aqui ele precisa estar
     CHEIO, e cheio do jeito de quem cadastrou a mao: a grafia minuscula e' o
     que faz o defeito existir. */
  bd.servicos.push(
    { id:id(), salaoId:salaoAtual, nome:'Corte simples', categoria:'cabelo',
      duracaoMin:30, intervaloMin:0, preco:45, comissaoPct:null,
      comissaoFixa:null, foto:null, ativo:true },
    { id:id(), salaoId:salaoAtual, nome:'Pe e mao', categoria:'unhas',
      duracaoMin:60, intervaloMin:0, preco:60, comissaoPct:null,
      comissaoFixa:null, foto:null, ativo:true });
  for(const s of doSalao(bd.servicos)) if(!s.categoria) s.categoria = 'cabelo';
  const sl = acharSalao(salaoAtual);
  sl.cfg = Object.assign({}, sl.cfg,
    { primeiroDia: { categorias: ['cabelo', 'unhas'] } });
  salvar();
  abrirPrimeiroDia(4);
});
await p.waitForTimeout(400);

const seletor = await p.evaluate(() =>
  [...document.querySelectorAll('#pdSvCat option')].map(o => o.textContent.trim()));
console.log('      ' + JSON.stringify(seletor));
/* Sem o seletor, tudo o que entrava por ali nascia sem categoria. */
e('o campo à mão tem seletor de categoria, com as marcadas no passo anterior',
  seletor.includes('Cabelo') && seletor.includes('Unhas'),
  JSON.stringify(seletor));
e('e uma saída para quem não quer categoria nenhuma',
  seletor.some(o => /sem categoria/i.test(o)), JSON.stringify(seletor));

const svAMao = await p.evaluate(async () => {
  document.getElementById('pdSvNome').value  = 'Corte navalhado';
  document.getElementById('pdSvDur').value   = '40';
  document.getElementById('pdSvPreco').value = '55';
  document.getElementById('pdSvCat').value   = 'Cabelo';
  await pdServicoAMao();
  const s = doSalao(bd.servicos).find(x => x.nome === 'Corte navalhado');
  return { naTela: /Corte navalhado/.test(document.getElementById('pdCorpo').innerText),
           // `.pd-cat` e' maiuscula por CSS, e o `innerText` respeita o
           // `text-transform` — dai o /i.
           secao:  /seus serviços/i.test(document.getElementById('pdCorpo').innerText),
           categoria: s ? s.categoria : null,
           duracao: s ? s.duracaoMin : null };
});
console.log('      ' + JSON.stringify(svAMao));
/* O defeito era este: cadastrava, e a tela não mudava. Só o contador lá
   embaixo mexia, e ninguém olha contador. */
e('o serviço cadastrado à mão APARECE na tela do passo',
  svAMao.naTela && svAMao.secao, JSON.stringify(svAMao));
/* ⚠ E a categoria sai com a GRAFIA DO SALÃO, não a do catálogo. O seletor
   mostra "Cabelo" porque é o rótulo bonito; o que vai para a coluna é
   "cabelo", que é como o salão já escreve. Sem isso, a página da cliente
   ganha uma segunda seção com o mesmo nome. */
e('com a categoria escolhida, na grafia que o salão já usa — '
  + JSON.stringify(svAMao.categoria),
  svAMao.categoria === 'cabelo', JSON.stringify(svAMao));

const daSugestao = await p.evaluate(async () => {
  await pdVirarServico('cabelo', 1);          // Corte masculino
  const s = doSalao(bd.servicos).find(x => x.nome === 'Corte masculino');
  return { categoria: s ? s.categoria : null,
           grafias: [...new Set(doSalao(bd.servicos).map(x => x.categoria))] };
});
console.log('      ' + JSON.stringify(daSugestao));
e('e a sugestão do catálogo também respeita a grafia do salão',
  daSugestao.categoria === 'cabelo', JSON.stringify(daSugestao));
e('nenhuma grafia nova de categoria nasceu — ' + JSON.stringify(daSugestao.grafias),
  !daSugestao.grafias.some(g => g && g !== 'cabelo' && g !== 'unhas'),
  JSON.stringify(daSugestao.grafias));

/* ⚠ E A PÁGINA DA CLIENTE JUNTA O QUE JÁ ESTÁ GRAVADO TORTO.

   A grafia nova deixou de nascer, mas o que já existe continua lá — e era
   ele que produzia as duas seções. O agrupamento passou a ignorar caixa e
   acento, o que repara a base sem mexer numa linha dela. */
const agrupa = await p.evaluate(() => {
  const finge = [
    { nome:'a', categoria:'Cabelo' }, { nome:'b', categoria:'cabelo' },
    { nome:'c', categoria:'CABELO' }, { nome:'d', categoria:'Unhas'  },
    { nome:'e', categoria:'unhas'  }, { nome:'f', categoria:''       },
  ];
  // A mesma função que a página da cliente usa, carregada aqui pelo iframe.
  const q = document.createElement('iframe');
  q.src = 'agendar.html?salao=studio-bella&demo=1';
  return new Promise(pronto => {
    q.onload = () => {
      const g = q.contentWindow.agruparPorCategoria(finge, 'Serviços');
      q.remove();
      pronto(g.map(x => x.rotulo + ':' + x.lista.length));
    };
    document.body.appendChild(q);
  });
});
console.log('      ' + JSON.stringify(agrupa));
e('três grafias de "Cabelo" viram UMA seção na página da cliente — '
  + JSON.stringify(agrupa),
  agrupa.length === 3 && agrupa.includes('Cabelo:3') && agrupa.includes('Unhas:2'),
  JSON.stringify(agrupa));
e('e o rótulo mostrado é a primeira grafia, que é a do salão',
  agrupa[0] === 'Cabelo:3', JSON.stringify(agrupa));

await p.evaluate(() => { document.getElementById('primeiroDia').hidden = true; });


/* ⚠ E O ASSISTENTE ESPERA O BANCO RESPONDER ANTES DE REDESENHAR.

   Este é o defeito que produziu os outros dois relatos — "tirei e não saiu" e
   "adicionar dá erro" — e ele não aparece na demonstração, onde `salvar()`
   grava no localStorage e volta na mesma linha. Na nuvem é uma PROMESSA, e
   ela era jogada fora:

       bd.profissionais.push(…);
       salvar();          // promessa descartada
       pdDesenhar();      // desenhava o "feito" antes da resposta

   Aí a cota do plano recusava o segundo profissional, o `salvar()` avisava e
   recarregava o `bd` do banco — mas a pessoa já estava desenhada na lista.
   Aparecia cadastrada sem existir; e "Tirar" nela não tirava nada, porque no
   banco ela nunca esteve.

   A medida não finge uma recusa: ela troca o `salvar()` por um que demora, e
   cobra que o desenho aconteça DEPOIS. É a propriedade que faltava, e a que
   faz o aviso do banco chegar antes da tela mentir. */
const esperou = await p.evaluate(async () => {
  const salvarOriginal = window.salvar;
  const desenhoOriginal = window.pdDesenhar;
  let gravou = 0, desenhou = 0, ordem = 0;
  window.salvar = () => new Promise(pronto =>
    setTimeout(() => { gravou = ++ordem; pronto(); }, 80));
  window.pdDesenhar = function(){
    desenhou = ++ordem;
    return desenhoOriginal.apply(this, arguments);
  };
  try{
    document.getElementById('pdEqNome') ||
      (pdPasso = 5, desenhoOriginal());          // garante o campo na tela
    document.getElementById('pdEqNome').value = 'Quem Espera';
    await pdEquipeAMao();
  } finally {
    window.salvar = salvarOriginal;
    window.pdDesenhar = desenhoOriginal;
  }
  return { gravou, desenhou };
});
console.log('      ' + JSON.stringify(esperou));
e('o desenho acontece DEPOIS de o banco responder — '
  + JSON.stringify(esperou),
  esperou.gravou > 0 && esperou.desenhou > esperou.gravou,
  'o assistente redesenhou antes da resposta: é assim que ele mostra como '
  + 'feito o que o banco recusou');

/* ── 11 · No celular ─────────────────────────────────────────────────────── */
console.log('\nNo celular');

const cel = await ctx.newPage();
cel.on('pageerror', x => erros.push('celular pageerror: ' + x.message));
cel.on('dialog', d => d.accept());
await cel.setViewportSize({ width:375, height:667 });
await cel.goto(BASE + 'app.html?demo=1');
await cel.waitForTimeout(2200);

const noCelular = [];
for(const passo of [1,2,3,4,5,6,7,8]){
  await cel.evaluate(n => { abrirPrimeiroDia(n); }, passo);
  await cel.waitForTimeout(180);
  noCelular.push(await cel.evaluate(() => {
    const raiz = document.getElementById('primeiroDia');
    const pequenos = [...raiz.querySelectorAll('button, input, select, a')]
      .filter(el => { const r = el.getBoundingClientRect();
                      return r.height > 0 && r.height < 40; })
      .map(el => (el.textContent || el.id || el.tagName).trim().slice(0, 20));
    const miudos = [...raiz.querySelectorAll('*')]
      .filter(el => el.children.length === 0 && (el.textContent || '').trim())
      .filter(el => parseFloat(getComputedStyle(el).fontSize) < 11)
      .map(el => (el.textContent || '').trim().slice(0, 20));
    return {
      vaza: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      pequenos, miudos,
      cabe: Math.round(raiz.querySelector('.pd-caixa').getBoundingClientRect().width),
    };
  }));
}
console.log('      375px: ' + JSON.stringify(noCelular.map(x => x.cabe)));
e('em 375px nenhum passo faz a página rolar para o lado',
  noCelular.every(x => x.vaza === 0),
  JSON.stringify(noCelular.map(x => x.vaza)));
/* A regra da casa: 40px de alvo. Uma hora de abrir com 30px de altura é o
   tipo de campo que se erra com o polegar e só se percebe depois. */
e('e todo alvo de toque tem os 40px da casa',
  noCelular.every(x => !x.pequenos.length),
  JSON.stringify(noCelular.map((x, i) => x.pequenos.length ? [i+1, x.pequenos] : null)
    .filter(Boolean)));
e('e nenhum texto abaixo de 11px',
  noCelular.every(x => !x.miudos.length),
  JSON.stringify(noCelular.map(x => x.miudos).flat()));
e('o assistente ocupa a tela inteira no celular, sem caixinha rolando dentro '
  + 'de caixinha', noCelular.every(x => x.cabe === 375),
  JSON.stringify(noCelular.map(x => x.cabe)));

e('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${ok} passaram, ${ruim} falharam`);
process.exit(ruim ? 1 : 0);
