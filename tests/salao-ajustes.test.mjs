/* ===========================================================================
   AgendaPro — três ajustes que o dono faz, e o efeito deles

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/salao-ajustes.test.mjs

   Três pedidos que vieram de prints de um concorrente:

     1. EXCLUIR PRODUTO. A mesma conversa da equipe, e a mesma armadilha:
        `comanda_itens.produto_id` é `on delete set null`, então o banco
        deixa apagar um produto já vendido e a venda fica sem saber o que
        foi. E aqui, diferente da equipe, NÃO EXISTE nenhuma chave
        `restrict` de rede — se a tela não barrar, nada barra.

     2. DE QUANTO EM QUANTO TEMPO O LINK OFERECE. 15, 30 ou 60 minutos.
        ⚠ É peneira de EXIBIÇÃO: a agenda por dentro continua fina, e a
        recepção continua marcando em qualquer minuto.

     3. OS RECADOS DO WHATSAPP. Modelos que o dono escreve uma vez, com
        ${cliente}, ${horario} e ${empresa}.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const RAIZ = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const BASE = process.env.BANCADA || 'http://127.0.0.1:8123';

let passou = 0, falhou = 0;
const ok  = m => { console.log('  ✓ ' + m); passou++; };
const nao = (m, d) => { console.log('  ✗ ' + m + (d ? '\n      ' + d : '')); falhou++; };
const igual = (m, a, b) => JSON.stringify(a) === JSON.stringify(b) ? ok(m)
  : nao(m, `esperava ${JSON.stringify(b)}, veio ${JSON.stringify(a)}`);
const verdade = (m, c, d) => c ? ok(m) : nao(m, d || 'esperava verdadeiro');
const secao = t => console.log('\n' + t);

function novaAba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(path.join(RAIZ,'dados.js'),'utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`aj-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
/* Jornada das 08:00 às 12:00, em todo dia da semana. Quatro horas fechadas
   dão contas redondas: 16 vagas de 15 min, 8 de 30, 4 de hora em hora — e
   isso é o que torna a peneira mensurável sem depender de sorte. */
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'12:00' });
}
const serv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:100, ativo:true, aceitaOnline:true });
const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Ana Paula',
  telefone:'11988887777' });
ok('salão de teste criado, jornada das 08:00 às 12:00');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
const erros = [], avisos = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', async d => { avisos.push(d.message()); await d.accept(); });

await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1500);

const recarregar = () => p.evaluate(async () => {
  const novo = await carregarTudo();
  if(novo){ bd = novo; pintar(); }
});
const irAba = async chave => {
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} });
  await p.click(`#abas .aba[data-chave="${chave}"]`);
  await p.waitForTimeout(900);
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — EXCLUIR PRODUTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('Tirar um produto da lista');

const nunca = await dona.inserir('produtos', { salaoId: SALAO,
  nome:'Nunca Vendido ' + marca, preco:30, custo:10, ativo:true });
const vendido = await dona.inserir('produtos', { salaoId: SALAO,
  nome:'Ja Vendido ' + marca, preco:50, custo:20, ativo:true });

// Uma venda de balcão com o segundo produto: comanda avulsa, sem agendamento.
const com = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: com.id, tipo:'produto',
  produtoId: vendido.id, descricao:'Ja Vendido', qtd:1, precoUnit:50 });

await recarregar();
await irAba('produtos');

const rotulo = id => p.evaluate(i => {
  const b = [...document.querySelectorAll('#listaProdutos .btn-perigo')]
    .find(x => (x.getAttribute('onclick')||'').includes(i));
  return b ? b.textContent.trim() : null;
}, id);

igual('quem nunca foi vendido tem botão de "Excluir"',
  await rotulo(nunca.id), 'Excluir');
/* ⚠ O RÓTULO PROMETE O QUE VAI ACONTECER. "Excluir" num produto já vendido
   seria mentira: a tela vai arquivar, não apagar. */
igual('e quem já foi vendido diz "Tirar da lista"',
  await rotulo(vendido.id), 'Tirar da lista');

avisos.length = 0;
await p.evaluate(id => tirarProduto(id), nunca.id);
await p.waitForTimeout(1600);
verdade('o que nunca vendeu some do banco',
  !(await dona.lista('produtos', { salaoId: SALAO })).some(x => x.id === nunca.id));

avisos.length = 0;
await p.evaluate(id => tirarProduto(id), vendido.id);
await p.waitForTimeout(1600);

const aindaLa = (await dona.lista('produtos', { salaoId: SALAO }))
  .find(x => x.id === vendido.id);
/* ⚠ ESTA É A VERIFICAÇÃO QUE IMPORTA. `comanda_itens.produto_id` é
   `on delete set null`: o banco teria aceitado o delete, apagado o produto e
   deixado a venda sem saber o que foi vendida — calado, sem erro nenhum. E
   aqui não há chave `restrict` para servir de rede: quem barra é só a tela. */
verdade('o que já foi vendido NÃO é apagado', !!aindaLa,
  'foi apagado — e o banco não reclamou, porque a chave é `set null`');
igual('ele é arquivado', aindaLa && aindaLa.ativo, false);
verdade('a conversa explica por quê, falando da venda',
  avisos.some(t => /venda/i.test(t)), JSON.stringify(avisos));

const itens = await dona.lista('comanda_itens', { comandaId: com.id });
igual('e o item da comanda continua sabendo qual produto foi',
  itens.length === 1 ? itens[0].produtoId : null, vendido.id);

/* ══════════════════════════════════════════════════════════════════════════
   2 — DE QUANTO EM QUANTO TEMPO O LINK OFERECE

   ⚠ A conta é de propósito redonda: jornada de 08:00 a 12:00, serviço de 30
   minutos. Com passo de 15 a última vaga que cabe é 11:30, então são 15
   vagas; com 30, são 8 (08:00…11:30); com 60, são 4 (08:00…11:00).
   ══════════════════════════════════════════════════════════════════════════ */
secao('O link oferece de 15, de 30 ou de hora em hora');

const ctxCli = await nav.newContext({ viewport:{ width:412, height:915 } });
async function horariosDoLink(){
  const c = await ctxCli.newPage();
  c.on('pageerror', e => erros.push('cliente: ' + e.message));
  await c.goto(BASE + '/agendar.html?salao=' + SLUG);
  await c.waitForTimeout(2400);
  const r = await c.evaluate(async id => {
    escolha.servicos = [id];
    const p0 = bd.profissionais.filter(x => x.salaoId === salao.id && x.ativo)[0];
    escolha.profissionalId = p0.id;
    // `pedirVagas()` e' quem pergunta ao banco e enche o cache `vagas`; sem
    // ele o `horariosLivres()` em modo nuvem devolve lista vazia.
    await pedirVagas();
    // Amanhã, para não esbarrar na antecedência mínima de hoje.
    const d = somarDias(hoje(), 1);
    return { passo: salao.passoHorarios,
             horas: horariosLivres(p0.id, d, duracaoNaAgenda()).map(hm) };
  }, serv.id);
  await c.close();
  return r;
}

const de15 = await horariosDoLink();
console.log('      ' + JSON.stringify(de15).slice(0, 200));
igual('sem escolher nada, o padrão continua 15 — como sempre foi',
  de15.passo, 15);
verdade('e a lista traz os quartos de hora', de15.horas.includes('08:15'),
  JSON.stringify(de15.horas));

// O dono escolhe 30 no painel.
await irAba('salao');
await p.evaluate(() => escolherPassoLink(30));
await p.waitForTimeout(300);
await p.evaluate(() => salvarCadastroSalao());
await p.waitForTimeout(1800);
igual('a escolha chega ao banco',
  ((await dona.lista('saloes', { id: SALAO }))[0].cfg || {}).passoHorarios, 30);

const de30 = await horariosDoLink();
console.log('      ' + JSON.stringify(de30).slice(0, 200));
igual('a vitrine leva o valor até a página da cliente', de30.passo, 30);
verdade('e 08:15 some da lista', !de30.horas.includes('08:15'),
  JSON.stringify(de30.horas));
verdade('mas 08:00 e 08:30 continuam',
  de30.horas.includes('08:00') && de30.horas.includes('08:30'),
  JSON.stringify(de30.horas));
verdade('sobram menos horários do que antes',
  de30.horas.length > 0 && de30.horas.length < de15.horas.length,
  de15.horas.length + ' → ' + de30.horas.length);

await p.evaluate(() => escolherPassoLink(60));
await p.waitForTimeout(300);
await p.evaluate(() => salvarCadastroSalao());
await p.waitForTimeout(1800);
const de60 = await horariosDoLink();
console.log('      ' + JSON.stringify(de60).slice(0, 160));
verdade('de hora em hora, só sobram horas cheias',
  de60.horas.length > 0 && de60.horas.every(h => /:00$/.test(h)),
  JSON.stringify(de60.horas));

/* ⚠ E A AGENDA POR DENTRO NÃO MUDOU. Este ajuste é sobre o que a cliente vê.
   Se ele tivesse mexido na `horarios_livres()`, o horário deixaria de
   existir para todo mundo — inclusive para a recepção querendo encaixar. */
const amanha = new Date(Date.now() + 26*3600*1000).toISOString().slice(0,10);
const doBanco = await dona.chamar('horarios_livres', {
  p_profissional: prof.id, p_data: amanha, p_servicos: [serv.id] });
const horasDoBanco = (Array.isArray(doBanco) ? doBanco : [])
  .map(x => String(x.horarios_livres || x).slice(11, 16));
verdade('o banco continua oferecendo de 15 em 15 para quem marca por dentro',
  horasDoBanco.some(h => /:15$|:45$/.test(h)),
  JSON.stringify(horasDoBanco).slice(0, 200));

/* ══════════════════════════════════════════════════════════════════════════
   3 — OS RECADOS DO WHATSAPP
   ══════════════════════════════════════════════════════════════════════════ */
secao('Os recados que o dono escreve uma vez');

const preenchido = await p.evaluate(() => ({
  padrao: preencherRecado(modeloDoSalao('confirmacao'),
    { cliente:'Ana', horario:'terça às 10:00', empresa:'Casa' }),
  semHorario: preencherRecado(modeloDoSalao('contato'),
    { cliente:'Ana', horario:'', empresa:'Casa' }),
  chaveTorta: preencherRecado('Oi ${nome}, tudo bem?', { cliente:'Ana' }),
}));
console.log('      ' + JSON.stringify(preenchido));

verdade('os parâmetros são trocados pelos valores',
  /Ana/.test(preenchido.padrao) && /terça às 10:00/.test(preenchido.padrao)
  && /Casa/.test(preenchido.padrao), preenchido.padrao);

/* ⚠ SEM HORÁRIO, O "de" QUE O ANTECEDE TEM QUE SAIR JUNTO. Falando pela
   ficha da cliente não há horário nenhum, e "sobre seu horário de ." é o
   tipo de detalhe que faz a mensagem parecer automática — que é justamente
   o contrário do que ela existe para ser. */
verdade('sem horário, não sobra um "de" solto nem espaço duplo',
  !/\sde\s*\.|\s{2,}/.test(preenchido.semHorario), preenchido.semHorario);

/* ⚠ E UM PARÂMETRO ERRADO SAI, em vez de ir literal. A cliente receber "Oi
   ${nome}!" estraga exatamente a impressão que a mensagem existe para criar. */
verdade('parâmetro que não existe vira vazio, e não vai literal',
  !/\$\{/.test(preenchido.chaveTorta), preenchido.chaveTorta);

// O dono reescreve um dos recados, do jeito da casa dele.
await irAba('salao');
await p.evaluate(() => {
  document.getElementById('msg-confirmacao').value =
    'E aí ${cliente}, beleza? Teu horário ${horario} tá marcado. ${empresa}';
});
await p.evaluate(() => salvarCadastroSalao());
await p.waitForTimeout(1800);

const gravado = ((await dona.lista('saloes', { id: SALAO }))[0].cfg || {}).mensagens || {};
verdade('o texto dele chega ao banco', /beleza/.test(gravado.confirmacao || ''),
  JSON.stringify(gravado));
/* ⚠ O CAMPO QUE ELE NÃO MEXEU NÃO PODE IR PARA O BANCO.

   Ele nasce VAZIO, com o nosso texto só como dica cinza. Gravar o vazio
   encheria o `cfg` de strings em branco; gravar o NOSSO TEXTO seria pior
   ainda — congelaria a redação de hoje dentro do salão, e melhorar o padrão
   depois não chegaria em ninguém que já tivesse salvado a tela uma vez, que
   é todo mundo.

   Vazio quer dizer "use o seu". Só o que ele escreveu é dele. */
igual('só o recado que ele reescreveu foi parar no cfg',
  Object.keys(gravado).sort(), ['confirmacao']);

const usando = await p.evaluate(() => preencherRecado(modeloDoSalao('confirmacao'),
  { cliente:'Ana', horario:'terça às 10:00', empresa:'Casa' }));
verdade('e é o texto dele que sai na hora de mandar', /E aí Ana, beleza/.test(usando),
  usando);

// O botão de parâmetro escreve a chave certa, no lugar do cursor.
const inserido = await p.evaluate(() => {
  const c = document.getElementById('msg-aniversario');
  c.value = 'Parabéns '; c.selectionStart = c.selectionEnd = c.value.length;
  porParametro('aniversario', 'cliente');
  return c.value;
});

/* ⚠ E O CAMPO EM BRANCO MOSTRA O PADRÃO COMO DICA, não como conteúdo. Sem a
   dica, o dono abre a tela, vê quatro caixas vazias e conclui que o sistema
   não manda recado nenhum — quando na verdade manda, com o nosso texto. */
const vazios = await p.evaluate(() => {
  const c = document.getElementById('msg-indisponivel');
  return { valor: c.value, dica: c.placeholder };
});
igual('o recado que ele nunca escreveu tem o campo vazio', vazios.valor, '');
verdade('mas a dica cinza mostra o que vai sair assim mesmo',
  /não está mais disponível/i.test(vazios.dica), vazios.dica);
igual('o botão de parâmetro insere a chave escrita do jeito certo',
  inserido, 'Parabéns ${cliente}');

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
