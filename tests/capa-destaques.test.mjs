/* ===========================================================================
   AgendaPro — a vitrine da capa: quem escolhe, e o que o toque vale

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/capa-destaques.test.mjs

   ── O PEDIDO, EM TRÊS PARTES ───────────────────────────────────────────────
   "Se tem diversos serviços, eu tenho que escolher quais ficaram na frente e
    já clicar e aparecer selecionado. Aparecer ver todos os serviços. Meus
    agendamentos e assinaturas/pacotes."

   São três coisas diferentes, e cada uma quebra de um jeito:

     1. O DONO ESCOLHE O QUE VAI NA FRENTE. A escolha atravessa quatro
        lugares — a estrela no painel, o `cfg` do salão, a `vitrine()` e a
        capa. Cada travessia é um ponto onde ela some sem erro nenhum: o dono
        marca, a tela obedece, e a cliente nunca fica sabendo.

     2. O TOQUE NO CARTÃO VALE. Ele abria a lista com TUDO desmarcado — a
        pessoa via a foto do corte, tocava querendo marcar aquele corte, e
        tinha que procurar o mesmo serviço de novo, agora em texto.

     3. OS ATALHOS DE QUEM JÁ É CLIENTE. "Meus horários" e "Meus pacotes".

   ── ⚠ E A PARTE QUE MAIS IMPORTA ───────────────────────────────────────────
   LISTA VAZIA NÃO QUER DIZER "NENHUM". Quer dizer "o dono ainda não
   escolheu" — que é o estado de TODO salão que já existe no dia em que isto
   entra no ar. Se vazio virasse "esconda tudo", a atualização apagaria a
   vitrine de todo mundo de uma vez, sem ninguém ter pedido.

   Essa é a falha que não dá sinal em desenvolvimento, porque aqui todo salão
   de teste nasce com escolha. Metade deste arquivo é sobre ela.
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
const ok  = (m) => { console.log('  ✓ ' + m); passou++; };
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
await dona.criarConta({ email:`capa-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa ' + marca,
  p_tipo:'salao', p_telefone:'(11) 3222-1100', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;

const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'09:00', fim:'19:00' });
}

/* ── OITO SERVIÇOS, E O NÚMERO NÃO É POR ACASO ────────────────────────────
   O teto da capa é SEIS. Com seis ou menos não há o que escolher e não há o
   que esconder: o defeito só existe acima do teto. Com oito, sobram dois —
   e "sobram dois" é o que faz o botão "Ver todos" ter razão de existir.

   Três com foto e cinco sem, de propósito: a capa automática põe quem tem
   foto na frente, e com todos iguais essa ordem passaria despercebida. */
const FOTO = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
const NOMES = ['Corte', 'Barba', 'Escova', 'Luzes', 'Hidratação',
               'Progressiva', 'Penteado', 'Coloração'];
const SVS = [];
for(let i = 0; i < NOMES.length; i++){
  SVS.push(await dona.inserir('servicos', { salaoId: SALAO, nome: NOMES[i],
    preco: 50 + i * 10, duracaoMin: 30, intervaloMin: 0,
    ativo: true, aceitaOnline: true, foto: i < 3 ? FOTO : null }));
}
ok(`salão de teste criado, com ${SVS.length} serviços (3 com foto)`);

const nav = await chromium.launch({ executablePath: CHROMIUM });

/* ══════════════════════════════════════════════════════════════════════════
   1 — A CAPA DO SALÃO QUE NUNCA ESCOLHEU NADA

   ⚠ Esta seção vem PRIMEIRO de propósito. É o estado de todo salão que já
   existe, e é o único momento em que ele pode ser medido: daqui para baixo o
   teste marca destaques e não há como voltar a "nunca escolheu".
   ══════════════════════════════════════════════════════════════════════════ */
secao('O salão que nunca escolheu nada — que é todo salão de hoje');

const v0 = await dona.chamar('vitrine', { p_slug: SLUG });
const daVitrine0 = Array.isArray(v0) ? v0[0] : v0;
igual('a vitrine() devolve lista vazia quando o cfg não tem a chave',
  daVitrine0.salao.destaques, []);
verdade('e continua sem devolver o cfg inteiro',
  daVitrine0.salao.cfg === undefined,
  'o cfg cru veio junto — chave nova cairia na vitrine sem ninguém decidir');

const ctxCli = await nav.newContext({ viewport:{ width:412, height:915 } });
const erros = [];
async function abrirCapa(){
  const p = await ctxCli.newPage();
  p.on('pageerror', e => erros.push('pageerror: ' + e.message));
  p.on('console', c => { if(c.type()==='error') erros.push('console: ' + c.text()); });
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForTimeout(2400);
  return p;
}

const lerCapa = (p) => p.evaluate(() => {
  const bt = document.querySelector('.ver-todos');
  /* A lista de escolher não é desenhada enquanto a capa está na tela — o
     `desenhar()` só chama o que o passo da vez precisa. Chamo à mão porque
     o que interessa aqui é a comparação: o que a capa RESUME contra o que a
     lista OFERECE. Sem ela, "a capa mostra seis" não prova que os outros
     dois continuam alcançáveis. */
  desenharServicos();
  return {
    nomes: [...document.querySelectorAll('#capaServicos .sv-cartao')]
             .map(c => c.querySelector('.sv-cartao-txt b').textContent.trim()),
    verTodos: !!bt,
    contagem: bt ? (bt.querySelector('.ver-todos-n')||{}).textContent : null,
    naLista: [...document.querySelectorAll('#listaServicos .opcao')].length,
  };
});

let cli = await abrirCapa();
const auto = await lerCapa(cli);
console.log('      ' + JSON.stringify(auto));

/* ⚠ A AFIRMAÇÃO QUE SEGURA A ATUALIZAÇÃO INTEIRA. Sem escolha, a capa não
   pode ficar vazia — e é exatamente o que ela ficaria se "[]" fosse lido
   como "nenhum" em vez de "não escolhi". */
verdade('sem escolha nenhuma, a capa NÃO fica vazia', auto.nomes.length > 0,
  'a capa saiu sem serviço nenhum — é a atualização apagando a vitrine de '
  + 'todo salão que já existe, de uma vez');
igual('ela se vira sozinha e mostra seis — o teto', auto.nomes.length, 6);
igual('com quem tem foto na frente, porque foto é o que faz vitrine',
  auto.nomes.slice(0, 3).slice().sort(), ['Barba','Corte','Escova']);

/* ── E O QUE NÃO COUBE NÃO PODE SUMIR ────────────────────────────────────
   Esconder dois serviços sem porta de saída seria trocar um defeito (capa
   comprida demais) por outro bem pior (serviço que a cliente não consegue
   pedir). O NÚMERO no botão é o total, e não o que sobrou: "ver todos" já
   diz que são todos, e quem lê quer saber o tamanho do cardápio. */
verdade('e "Ver todos os serviços" aparece, porque dois ficaram de fora',
  auto.verTodos, 'sem o botão, os dois que não couberam viram serviço morto');
igual('com o total ao lado, para valer a pena tocar', auto.contagem, '8');
igual('e a lista de escolher continua com todos os oito', auto.naLista, 8);

/* ══════════════════════════════════════════════════════════════════════════
   2 — O DONO MARCA, NO PAINEL

   A parte que não existia: a `vitrine()` sabia ler a escolha, e não havia
   onde fazê-la. Funcionalidade sem tela é funcionalidade que não existe.
   ══════════════════════════════════════════════════════════════════════════ */
secao('A estrela no painel');

const ctxDona = await nav.newContext({ viewport:{ width:1360, height:900 } });
const painel = await ctxDona.newPage();
painel.on('pageerror', e => erros.push('painel: ' + e.message));
await painel.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await painel.goto(BASE + '/app.html');
await painel.waitForTimeout(4000);
// O passo a passo do primeiro dia abre sozinho num salão novo e cobre a tela.
await painel.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await painel.waitForTimeout(1500);
await painel.click('#abas .aba[data-chave="servicos"]');
await painel.waitForTimeout(1200);

const estrelas = await painel.evaluate(() => {
  const bs = [...document.querySelectorAll('.tabela .estrela')];
  const r = bs.length ? bs[0].getBoundingClientRect() : null;
  return {
    quantas: bs.length,
    linhas: document.querySelectorAll('.tabela tbody tr').length,
    ligadas: bs.filter(b => b.classList.contains('on')).length,
    largura: r ? Math.round(r.width) : 0,
    altura: r ? Math.round(r.height) : 0,
    // O leitor de tela precisa saber se está ligada — a cor não fala com ele.
    marcada: bs.length ? bs[0].getAttribute('aria-pressed') : null,
  };
});
console.log('      ' + JSON.stringify(estrelas));
igual('toda linha de serviço ganha uma estrela',
  estrelas.quantas, estrelas.linhas);
igual('e nenhuma nasce ligada — ninguém escolheu ainda', estrelas.ligadas, 0);
/* 40px é o piso de alvo de toque do projeto, e o `celular.test.mjs` cobra
   isso na tela inteira. Aqui de novo, porque esta tabela vira CARTÃO no
   celular: a estrela é o botão novo, e é o primeiro candidato a nascer do
   tamanho do ícone. */
verdade(`a estrela é alvo de toque (${estrelas.largura}×${estrelas.altura}px)`,
  estrelas.largura >= 40 && estrelas.altura >= 40,
  'menor que 40px não se acerta com o polegar');
igual('e diz ao leitor de tela que está desligada', estrelas.marcada, 'false');

/* ── ⚠ A ORDEM DE MARCAÇÃO É A ORDEM DA CAPA, E O ROTEIRO AQUI É ESCOLHIDO
       PARA PODER PROVAR ISSO ───────────────────────────────────────────────
   A sequência termina em PROGRESSIVA, CORTE, LUZES — que não é a ordem
   alfabética desses três (Corte, Luzes, Progressiva) nem a de cadastro
   (Corte, Luzes, Progressiva, que por acaso coincide).

   Isso não é capricho. Uma primeira versão deste teste terminava numa ordem
   que POR ACASO era a alfabética, e aí ele ficava verde com a capa ordenando
   por nome — quer dizer, com a escolha do dono sendo desfeita em silêncio,
   que é exatamente o defeito que ele veio pegar. Só a mutação mostrou isso.

   Com três ordens diferentes, a única forma de a capa sair certa é ela estar
   mesmo respeitando o que o dono marcou. */
const idLuzes = SVS[3].id, idCorte = SVS[0].id, idProg = SVS[5].id;
await painel.evaluate(id => virarDestaque(id), idProg);
await painel.waitForTimeout(900);
await painel.evaluate(id => virarDestaque(id), idLuzes);
await painel.waitForTimeout(900);

const noBanco = await dona.lista('saloes', { id: SALAO });
igual('as duas escolhas chegam ao banco, na ordem em que foram feitas',
  (noBanco[0].cfg || {}).destaques, [idProg, idLuzes]);

const depois = await painel.evaluate(() =>
  [...document.querySelectorAll('.tabela .estrela')]
    .filter(b => b.classList.contains('on')).length);
igual('e a tabela repinta com as duas acesas', depois, 2);

/* ⚠ O MESMO BOTÃO TIRA. Sem isso o dono marca por engano e não tem como
   desfazer a não ser apagando o serviço. */
await painel.evaluate(id => virarDestaque(id), idLuzes);
await painel.waitForTimeout(900);
const tirou = await dona.lista('saloes', { id: SALAO });
igual('tocar de novo na mesma estrela tira o serviço da capa',
  (tirou[0].cfg || {}).destaques, [idProg]);

await painel.evaluate(id => virarDestaque(id), idCorte);
await painel.waitForTimeout(900);

/* ⚠ E O RESTO DO `cfg` CONTINUA LÁ. Gravar `{destaques}` por cima em vez de
   somar apagaria cor, tema e janela da agenda de uma vez — e o estrago só
   apareceria dias depois, sem ninguém ligar uma coisa à outra. */
await dona.atualizar('saloes', SALAO, { cfg: Object.assign({},
  (await dona.lista('saloes', { id: SALAO }))[0].cfg, { cor:'#0C7568', diasLiberados:45 }) });
// Recarrega o `bd` da tela a partir do banco: a gravação acima foi por fora,
// direto no PostgREST, e sem isto a tela guardaria o cfg velho e o
// sobrescreveria na próxima estrela — que é justamente o que se quer medir.
await painel.evaluate(async () => {
  const novo = await carregarTudo();
  if(novo){ bd = novo; pintar(); }
});
await painel.waitForTimeout(1500);
await painel.evaluate(id => virarDestaque(id), idLuzes);
await painel.waitForTimeout(900);
const juntos = (await dona.lista('saloes', { id: SALAO }))[0].cfg || {};
verdade('e marcar mais uma não apaga o resto do cfg',
  juntos.cor === '#0C7568' && juntos.diasLiberados === 45,
  JSON.stringify(juntos));
igual('a terceira entra no fim da fila',
  juntos.destaques, [idProg, idCorte, idLuzes]);

/* ══════════════════════════════════════════════════════════════════════════
   3 — A ESCOLHA CHEGA À CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('A capa obedece à escolha do dono');

const v1 = await dona.chamar('vitrine', { p_slug: SLUG });
igual('a vitrine() devolve os três ids, na ordem',
  (Array.isArray(v1) ? v1[0] : v1).salao.destaques,
  [idProg, idCorte, idLuzes]);

await cli.close();
cli = await abrirCapa();
const escolhida = await lerCapa(cli);
console.log('      ' + JSON.stringify(escolhida));
igual('a capa mostra só os três marcados, na ordem do dono',
  escolhida.nomes, ['Progressiva', 'Corte', 'Luzes']);
igual('e o botão continua com o total do cardápio', escolhida.contagem, '8');
igual('a lista de escolher segue com todos os oito', escolhida.naLista, 8);

/* ── ⚠ SERVIÇO MARCADO QUE DEIXA DE EXISTIR ──────────────────────────────
   O dono desativa um serviço meses depois e ninguém lembra de desmarcar a
   estrela. O id fica no `cfg` apontando para nada. Se isso virasse um cartão
   em branco, ou um erro de JavaScript, a capa quebraria por causa de uma
   faxina de cadastro. */
await dona.atualizar('servicos', idLuzes, { ativo: false });
await cli.close();
cli = await abrirCapa();
const semLuzes = await lerCapa(cli);
igual('serviço marcado que foi desativado some da capa, sem deixar buraco',
  semLuzes.nomes, ['Progressiva', 'Corte']);
await dona.atualizar('servicos', idLuzes, { ativo: true });

/* ══════════════════════════════════════════════════════════════════════════
   4 — O TOQUE NO CARTÃO VALE

   Era o defeito mais caro dos três, porque parecia funcionar: a tela mudava.
   ══════════════════════════════════════════════════════════════════════════ */
secao('Tocar no cartão já escolhe o serviço');

await cli.close();
cli = await abrirCapa();
await cli.click('#capaServicos .sv-cartao');
await cli.waitForTimeout(700);

const apos = await cli.evaluate(() => ({
  tela,
  escolhidos: escolha.servicos.length,
  marcados: document.querySelectorAll('#listaServicos .opcao.sel').length,
}));
console.log('      ' + JSON.stringify(apos));
igual('o toque leva à lista de serviços', apos.tela, 'servico');
igual('e o serviço tocado já vai escolhido', apos.escolhidos, 1);
verdade('a lista abre com ele marcado, e não com tudo em branco',
  apos.marcados === 1, apos.marcados + ' marcados na lista');

/* ⚠ A LISTA CONTINUA ABERTA DE PROPÓSITO, e não pula para os horários:
   somar um segundo serviço ("corte + barba") é comum, e pular tiraria essa
   chance sem avisar. */
verdade('a lista continua aberta para somar um segundo serviço',
  apos.tela === 'servico');

/* Voltando à capa: o cartão precisa DIZER que foi tocado. Sem a marca, a
   pessoa que volta pelo botão de trás do navegador acha que o toque falhou
   e toca de novo. */
const voltando = await cli.evaluate(() => {
  irPara('capa');
  const c = document.querySelector('#capaServicos .sv-cartao');
  return { sel: c.classList.contains('sel'),
           borda: getComputedStyle(c).borderColor };
});
verdade('de volta na capa, o cartão escolhido aparece selecionado',
  voltando.sel, 'sem a marca, ela toca de novo achando que falhou');

/* ⚠ E TOCAR DE NOVO NÃO PODE DESMARCAR. É o que um "alternar" faria, e o
   gesto de quem volta à capa é conferir, não desfazer. */
const deNovo = await cli.evaluate(() => {
  const c = document.querySelector('#capaServicos .sv-cartao');
  c.click();
  return { tela, escolhidos: escolha.servicos.length };
});
igual('tocar no mesmo cartão outra vez não desmarca', deNovo.escolhidos, 1);

/* ══════════════════════════════════════════════════════════════════════════
   5 — OS ATALHOS DE QUEM JÁ É CLIENTE
   ══════════════════════════════════════════════════════════════════════════ */
secao('Meus horários e Meus pacotes');

await cli.close();
cli = await abrirCapa();

const semNada = await cli.evaluate(() =>
  document.querySelectorAll('#capaAtalhos .atalho').length);
/* ⚠ ATALHO PARA LISTA VAZIA É PIOR QUE ATALHO NENHUM: a pessoa toca, não
   encontra nada, e passa a desconfiar do resto da página. */
igual('aparelho que nunca marcou aqui não vê atalho nenhum', semNada, 0);

const comAtalhos = await cli.evaluate(() => {
  sessao = { perfilId:'x', nome:'Bia', telefone:'11999990000' };
  meusPacotes = [{ nome:'Pacote 5 escovas', restantes:2, servicos:[],
                   vence_em:null, so_nos_dias:false, dias:[] }];
  desenharCapa();
  const bs = [...document.querySelectorAll('#capaAtalhos .atalho')];
  const r = bs.length ? bs[0].getBoundingClientRect() : null;
  return {
    quantos: bs.length,
    titulos: bs.map(b => b.querySelector('b').textContent.trim()),
    subs: bs.map(b => b.querySelector('.atalho-txt span').textContent.trim()),
    altura: r ? Math.round(r.height) : 0,
  };
});
console.log('      ' + JSON.stringify(comAtalhos));
igual('com conta e com pacote, os dois atalhos aparecem', comAtalhos.quantos, 2);
igual('e dizem o que são',
  comAtalhos.titulos, ['Meus horários', 'Meus pacotes']);
/* O número de sessões no subtítulo é o que faz o atalho valer: "Meus
   pacotes" sozinho não responde a pergunta que ela tem, que é quantas
   sobraram. */
verdade('o atalho do pacote já diz quantas sessões sobraram',
  /2 sessões/.test(comAtalhos.subs[1]), comAtalhos.subs[1]);
verdade(`e o cartão é alvo de toque (${comAtalhos.altura}px de altura)`,
  comAtalhos.altura >= 40, 'menor que 40px não se acerta com o polegar');

const naTela = await cli.evaluate(() => {
  irPara('pacotes');
  const c = document.querySelector('#listaPacotes .pacote-cartao');
  return { tela,
           // `on` é a classe que o `irPara()` põe no passo da vez.
           visivel: document.getElementById('p-pacotes').classList.contains('on'),
           nome: c ? c.querySelector('b').textContent.trim() : null,
           restantes: c ? c.querySelector('.pacote-n').textContent.trim() : null };
});
console.log('      ' + JSON.stringify(naTela));
igual('o atalho abre a tela dos pacotes', naTela.tela, 'pacotes');
verdade('e ela está mesmo na tela', naTela.visivel);
igual('com o nome do pacote', naTela.nome, 'Pacote 5 escovas');
/* O número é o que ela veio ver. Escrito por extenso no meio de um parágrafo
   ele se perde; em corpo grande, é a primeira coisa que o olho encontra. */
igual('e as sessões que sobraram em destaque', naTela.restantes, '2');

/* ── SEM PACOTE, A TELA EXPLICA ──────────────────────────────────────────
   Ela pode chegar aqui pelo histórico do navegador depois de gastar a
   última sessão. Uma tela em branco parece defeito. */
const vazio = await cli.evaluate(() => {
  meusPacotes = [];
  desenharPacotes();
  const r = document.querySelector('#listaPacotes .recado');
  return r ? r.textContent.trim() : null;
});
verdade('sem pacote nenhum, a tela diz isso em vez de ficar em branco',
  !!vazio && /ainda não tem pacote/i.test(vazio), String(vazio));

verdade('nada disso deu erro de JavaScript', erros.length === 0,
  erros.slice(0, 4).join(' | '));

await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
