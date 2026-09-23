/* ===========================================================================
   AgendaPro — tirar alguém da equipe sem perder o histórico

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/equipe-sair.test.mjs

   ── O PEDIDO ───────────────────────────────────────────────────────────────
   "Eu tenho que conseguir excluir o profissional se quiser."

   Dava para editar e dava para bloquear horário. Não dava para tirar — e o
   dono ficava com a pessoa na lista, ocupando vaga do plano, sem saída
   nenhuma a não ser desmarcar "atende" escondido dentro do formulário.

   ── ⚠ POR QUE ISTO NÃO É UM `delete` E PRONTO ──────────────────────────────
   Duas chaves estrangeiras apontam para `profissionais`, e elas reagem de
   jeitos OPOSTOS:

     · `agendamentos.profissional_id` é `on delete restrict` — o banco RECUSA,
       alto e claro;

     · `comanda_itens.profissional_id` é `on delete set null` — o banco
       ACEITA, apaga a pessoa e deixa o item de comanda sem dono. Calado.

   O segundo é o perigoso, e é o que nenhum teste pegaria por acidente: a
   venda de balcão (comanda avulsa, sem agendamento nenhum) perderia a
   comissão sem erro, sem aviso e sem ninguém notar até o fechamento do mês.

   Por isso metade deste arquivo é sobre ele.
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
await dona.criarConta({ email:`eq-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;

const daCasa = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: daCasa.id, diaSemana:i,
                                   inicio:'08:00', fim:'20:00' });
}
const serv = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte',
  duracaoMin:30, intervaloMin:0, preco:100, ativo:true, aceitaOnline:true });
const cli = await dona.inserir('clientes', { salaoId: SALAO, nome:'Clara',
  telefone:'11' + (900000000 + Math.floor(Math.random()*99999999)) });
ok('salão de teste criado');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
const erros = [], avisos = [];
p.on('pageerror', e => erros.push(e.message));
/* `confirm` e `alert` travam o Playwright e somem com a mensagem. Aceitar e
   GUARDAR é o que transforma "a tela não fez nada" em "a tela disse isto" —
   e aqui o TEXTO importa, porque o pedido é que o dono entenda o que vai
   acontecer antes de acontecer. */
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
const naEquipe = () => p.evaluate(() =>
  [...document.querySelectorAll('#listaEquipe .card h3')].map(h => h.textContent.trim()));
const noBanco = async () => (await dona.lista('profissionais', { salaoId: SALAO }))
  .map(x => x.nome).sort();

async function abrirEquipe(){
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} });
  await p.click('#abas .aba[data-chave="equipe"]');
  await p.waitForTimeout(900);
}

/* ══════════════════════════════════════════════════════════════════════════
   1 — QUEM NUNCA TRABALHOU SOME DE VERDADE

   É o cadastro errado: nome digitado torto, pessoa que ia começar e não
   começou. Não há histórico a preservar, e "arquivar" deixaria lixo na lista
   para sempre.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Quem nunca atendeu sai de vez');

/* ⚠ A COTA DO PLANO É DE UM PROFISSIONAL. Inserir a segunda pelo `dona` (que
   fala direto com o PostgREST) esbarraria no gatilho da cota e o teste
   morreria num erro que não tem nada a ver com exclusão. Por isso a dona da
   casa sai de cena primeiro — e volta depois, arquivada, quando for a vez
   dela. */
await dona.atualizar('profissionais', daCasa.id, { ativo: false });
const novata = await dona.inserir('profissionais', { salaoId: SALAO,
  nome:'Novata ' + marca, comissaoPct: 30, ativo: true });
await recarregar();
await abrirEquipe();

verdade('a lista traz as duas', (await naEquipe()).length === 2,
  JSON.stringify(await naEquipe()));
verdade('e cada cartão tem um botão de tirar da equipe',
  await p.evaluate(() =>
    document.querySelectorAll('#listaEquipe .btn-perigo').length) === 2);

/* ⚠ O RÓTULO PROMETE O QUE VAI ACONTECER. Quem nunca trabalhou lê "Excluir";
   quem já trabalhou lê "Tirar da equipe", porque apagar não é o que a tela
   vai fazer. Botão que promete uma coisa e faz outra é pior que botão
   nenhum. */
igual('e em quem nunca trabalhou o botão diz "Excluir"',
  await p.evaluate(id => {
    const c = [...document.querySelectorAll('#listaEquipe .card')]
      .find(x => (x.querySelector('.btn-perigo').getAttribute('onclick')||'').includes(id));
    return c ? c.querySelector('.btn-perigo').textContent.trim() : null;
  }, novata.id), 'Excluir');

avisos.length = 0;
await p.evaluate(id => tirarDaEquipe(id), novata.id);
await p.waitForTimeout(1800);

verdade('a confirmação avisa que não tem volta',
  avisos.some(t => /não tem volta/i.test(t)), JSON.stringify(avisos));
verdade('some da tela', !(await naEquipe()).some(n => /Novata/.test(n)),
  JSON.stringify(await naEquipe()));
verdade('e some do BANCO, não só da tela',
  !(await noBanco()).some(n => /Novata/.test(n)),
  JSON.stringify(await noBanco()));
verdade('sem erro de JavaScript', erros.length === 0, erros.join(' | '));

/* ══════════════════════════════════════════════════════════════════════════
   2 — QUEM JÁ ATENDEU É ARQUIVADA, NÃO APAGADA

   `agendamentos.profissional_id` é `on delete restrict`: apagar levaria junto
   o registro de quem fez o quê e a comissão daquele dia.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Quem já atendeu não pode ser apagada');

await dona.atualizar('profissionais', daCasa.id, { ativo: true });
const amanha = new Date(Date.now() + 26*3600*1000).toISOString().slice(0,10);
const ag = await dona.chamar('agendar_interno', {
  p_salao: SALAO, p_cliente: cli.id, p_profissional: daCasa.id,
  p_inicio: amanha + 'T13:00:00Z', p_servicos: [serv.id],
}).catch(() => null);

// Nem todo banco expõe o `agendar_interno`; havendo recusa, insere direto.
if(!ag){
  await dona.inserir('agendamentos', { salaoId: SALAO, clienteId: cli.id,
    profissionalId: daCasa.id, inicio: amanha + 'T13:00:00Z',
    fim: amanha + 'T13:30:00Z', status:'confirmado' });
}
await recarregar();
await abrirEquipe();

igual('agora o botão dela diz "Tirar da equipe"',
  await p.evaluate(id => {
    const c = [...document.querySelectorAll('#listaEquipe .card')]
      .find(x => (x.querySelector('.btn-perigo').getAttribute('onclick')||'').includes(id));
    return c ? c.querySelector('.btn-perigo').textContent.trim() : null;
  }, daCasa.id), 'Tirar da equipe');

avisos.length = 0;
await p.evaluate(id => tirarDaEquipe(id), daCasa.id);
await p.waitForTimeout(1800);

verdade('a conversa diz quanto histórico existe',
  avisos.some(t => /atendimento/i.test(t)), JSON.stringify(avisos));
verdade('e explica o que muda: agenda, link e cota do plano',
  avisos.some(t => /agenda/i.test(t) && /link/i.test(t) && /plano/i.test(t)),
  JSON.stringify(avisos));

const depois = (await dona.lista('profissionais', { salaoId: SALAO }))
  .find(x => x.id === daCasa.id);
verdade('ela CONTINUA no banco', !!depois, 'sumiu — o histórico foi junto');
igual('mas fora da equipe', depois && depois.ativo, false);
igual('e o atendimento dela continua lá, com dono',
  (await dona.lista('agendamentos', { salaoId: SALAO }))
    .filter(a => a.profissionalId === daCasa.id).length, 1);

/* ⚠ E TENTAR DE NOVO NÃO PODE APAGAR. Já arquivada, o botão volta a dizer
   "Excluir" — e sem esta trava o segundo toque cairia no caminho da exclusão
   de verdade, que é justamente o que o histórico impede. */
avisos.length = 0;
await recarregar();
await abrirEquipe();
await p.evaluate(id => tirarDaEquipe(id), daCasa.id);
await p.waitForTimeout(1500);
verdade('tocar de novo em quem já saiu não apaga — só explica por quê',
  avisos.some(t => /já está fora da equipe/i.test(t)), JSON.stringify(avisos));
verdade('e ela continua no banco depois da segunda tentativa',
  !!(await dona.lista('profissionais', { salaoId: SALAO }))
      .find(x => x.id === daCasa.id));

/* ══════════════════════════════════════════════════════════════════════════
   3 — ⚠ O CASO QUE O BANCO NÃO BARRA

   Uma profissional com ITEM DE COMANDA e NENHUM agendamento. É a venda de
   balcão: alguém entrou, comprou, pagou, e não houve marcação nenhuma.

   `comanda_itens.profissional_id` é `on delete set null`. Quer dizer: o
   `delete` PASSA. O banco apaga a pessoa e deixa o item sem dono, sem erro e
   sem aviso — a comissão daquela venda vira de ninguém.

   Contar só agendamento deixaria este caso escapar inteiro. É o motivo de o
   `historicoDe()` somar os dois.
   ══════════════════════════════════════════════════════════════════════════ */
secao('⚠ Só venda de balcão, nenhum agendamento — o caso que o banco deixa passar');

await dona.atualizar('profissionais', daCasa.id, { ativo: false });
const balcao = await dona.inserir('profissionais', { salaoId: SALAO,
  nome:'Balcao ' + marca, comissaoPct: 40, ativo: true });
const com = await dona.inserir('comandas', { salaoId: SALAO, clienteId: cli.id });
await dona.inserir('comanda_itens', { comandaId: com.id, tipo:'servico',
  servicoId: serv.id, descricao:'Corte', qtd:1, precoUnit:100,
  profissionalId: balcao.id });
await recarregar();
await abrirEquipe();

igual('sem agendamento nenhum, o botão dela AINDA diz "Tirar da equipe"',
  await p.evaluate(id => {
    const c = [...document.querySelectorAll('#listaEquipe .card')]
      .find(x => (x.querySelector('.btn-perigo').getAttribute('onclick')||'').includes(id));
    return c ? c.querySelector('.btn-perigo').textContent.trim() : null;
  }, balcao.id), 'Tirar da equipe');

avisos.length = 0;
await p.evaluate(id => tirarDaEquipe(id), balcao.id);
await p.waitForTimeout(1800);

verdade('a conversa fala do item de comanda, e não de atendimento',
  avisos.some(t => /item de comanda/i.test(t)), JSON.stringify(avisos));

const aindaLa = (await dona.lista('profissionais', { salaoId: SALAO }))
  .find(x => x.id === balcao.id);
verdade('ela NÃO foi apagada', !!aindaLa,
  'foi apagada — e o banco não reclamou, porque a chave é `set null`');
igual('foi arquivada', aindaLa && aindaLa.ativo, false);

/* A prova final, e a única que importa de verdade: o item de comanda
   continua com dono. Se a exclusão tivesse passado, este campo estaria nulo
   e a comissão daquela venda seria de ninguém — sem erro em lugar nenhum. */
const itens = await dona.lista('comanda_itens', { comandaId: com.id });
igual('e o item de comanda continua com dono',
  itens.length === 1 ? itens[0].profissionalId : null, balcao.id);

/* ══════════════════════════════════════════════════════════════════════════
   4 — UMA PESSOA SÓ NÃO PRECISA DE COLUNA COM NOME

   "Se tiver um só, tanto faz, não aparecer quando tiver um só profissional."

   Num salão de uma pessoa o cabeçalho diz o nome de quem já está olhando a
   própria agenda. É uma faixa a menos no celular, que é onde a agenda mais
   sofre de espaço.

   ⚠ MAS SÓ SOME QUANDO NÃO HÁ RECADO. O cabeçalho carrega três avisos que
   explicam uma grade vazia — "folga", "fora do plano", "desativada". Sem
   eles, quem abre um dia de folga vê uma grade riscada sem explicação, e a
   conclusão razoável é que o sistema perdeu os horários.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Um profissional só: a coluna perde o nome, mas não o recado');

await dona.atualizar('profissionais', daCasa.id, { ativo: true });
await recarregar();
await p.evaluate(() => { try{ fecharModal(); }catch(e){} });
await p.click('#abas .aba[data-chave="agenda"]');
await p.waitForTimeout(900);

const naGrade = () => p.evaluate(() => ({
  colunas: document.querySelectorAll('#grade .col').length,
  cabecalhos: document.querySelectorAll('#grade .col-h').length,
  texto: (document.getElementById('grade') || {}).innerText || '',
}));

// Uma quarta-feira qualquer, em que ela trabalha (jornada 08:00–20:00 todo dia).
await p.evaluate(d => { diaAtual = d; vistaAgenda = 'dia'; pintar(); }, amanha);
await p.waitForTimeout(700);
const comJornada = await naGrade();
igual('a grade tem uma coluna só', comJornada.colunas, 1);
igual('e nenhum cabeçalho — o nome dela seria dizer o óbvio',
  comJornada.cabecalhos, 0);

/* Agora o dia em que ela não trabalha. A grade fica riscada de ponta a
   ponta, e sem a palavra "folga" isso parece defeito. */
await p.evaluate(() => {
  // Só na memória da tela: não grava. O que se mede aqui é o DESENHO, e
  // gravar chamaria o banco sem necessidade nenhuma.
  doSalao(bd.profissionais).find(x => x.ativo).jornada = {};
  vistaAgenda = 'dia'; pintar();
});
await p.waitForTimeout(700);
const semJornada = await naGrade();
igual('no dia de folga o cabeçalho volta', semJornada.cabecalhos, 2);
verdade('e ele diz "folga", que é o que explica a grade vazia',
  /folga/i.test(semJornada.texto), semJornada.texto.slice(0, 120));

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 3).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
