/* ===========================================================================
   AgendaPro — os dois módulos da casa: serviços e produtos

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/modulos.test.mjs

   O pedido: "pense no sistema como dois módulos independentes — SERVIÇOS /
   AGENDAMENTO e PRODUTOS / LOJA. Cada um pode estar ativo ou inativo, e a
   página inicial deve montar automaticamente a interface de acordo com essas
   escolhas."

   ── AS QUATRO COMBINAÇÕES, E POR QUE AS QUATRO ENTRAM ──────────────────────
   Dois interruptores dão quatro estados, e três deles são fáceis de esquecer:
   quem escreve o código pensa em "os dois ligados" (o de hoje) e testa "a
   loja desligada". Sobram "só a loja" — a casa que só vende — e "os dois
   desligados", que não é engano: é o cartão de visita de quem ainda está
   montando o catálogo.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. o BANCO peneira as listas, e não só a tela. Módulo desligado com a
        lista saindo na resposta é catálogo publicado para quem abrir o
        inspetor;
     2. a peneira é de LETRA. `(cfg->>'loja')::boolean` LEVANTA com lixo, e
        quem cai é a `vitrine()` — a única porta da página da cliente. A casa
        inteira sai do ar por um caractere;
     3. a CAPA se monta sozinha nas quatro combinações, e não sobra bloco
        vazio em nenhuma;
     4. o dono grava a escolha no painel e ela FICA. "Escolhi, salvei, voltou
        como estava" é o defeito que o dashboard já entregou uma vez.
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

const arte = (a, b) => 'data:image/svg+xml;base64,' + Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360">`
  + `<rect width="640" height="360" fill="${a}"/>`
  + `<circle cx="320" cy="180" r="120" fill="${b}"/></svg>`).toString('base64');

const marca = Date.now().toString(36) + Math.floor(Math.random()*1000);
const dona = novaAba();
await dona.criarConta({ email:`mod-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Rita Alves', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa Dupla',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++){
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i,
                                   inicio:'08:00', fim:'19:00' });
}
await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte feminino',
  duracaoMin:30, intervaloMin:0, preco:90, ativo:true, aceitaOnline:true,
  categoria:'Cabelo', foto: arte('#7C3AED', '#C084FC') });
await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova',
  duracaoMin:40, intervaloMin:0, preco:70, ativo:true, aceitaOnline:true,
  categoria:'Cabelo' });

/* ⚠ SÓ DOIS PRODUTOS, DE PROPÓSITO. A vitrine da capa mostra até quatro,
   então com dois não "sobra" nada — e é exatamente aí que o "Ver todos os
   produtos" some, se ele ainda depender de sobrar. A tela da loja é a única
   que deixa mudar quantidade e enviar o pedido: vitrine sem saída é vitrine
   quebrada, e um salão pequeno é quem mais cai nisso. */
await dona.inserir('produtos', { salaoId: SALAO, nome:'Shampoo Reparador',
  preco:45, custo:20, ativo:true, vendaOnline:true, foto: arte('#065F46','#34D399') });
await dona.inserir('produtos', { salaoId: SALAO, nome:'Máscara Nutritiva',
  preco:60, custo:25, ativo:true, vendaOnline:true });

const COR = '#6D28D9';
await dona.atualizar('saloes', SALAO, {
  whatsapp:'(11) 98111-3251',
  endereco:{ logradouro:'Rua Avanhandava', numero:'10',
             bairro:'Cidade Nova', cidade:'Itu', uf:'SP' },
  logo: arte('#4C1D95', '#A78BFA'),
  capa: arte('#2E1065', '#7C3AED'),
  cfg: { diasLiberados:30, cor: COR } });
ok('casa criada: 2 serviços, 2 produtos, WhatsApp e a cor dela');

const vitrine = async () => {
  const v = await dona.chamar('vitrine', { p_slug: SLUG });
  return Array.isArray(v) ? v[0] : v;
};
const ligar = async (servicos, loja) => {
  const sl = (await dona.lista('saloes', { id: SALAO }))[0];
  const cfg = Object.assign({}, sl.cfg);
  if(servicos === undefined) delete cfg.usaServicos; else cfg.usaServicos = servicos;
  if(loja === undefined)     delete cfg.loja;        else cfg.loja = loja;
  await dona.atualizar('saloes', SALAO, { cfg });
};

/* ══════════════════════════════════════════════════════════════════════════
   1 — O BANCO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · A vitrine() peneira as listas, e não só a tela');

let v = await vitrine();
igual('sem nenhuma chave, os serviços estão ligados', v.salao.usaServicos, true);
igual('e a loja também', v.salao.loja, true);
igual('os dois serviços saem', (v.servicos || []).length, 2);
igual('e os dois produtos', (v.produtos || []).length, 2);

await ligar(false, undefined);
v = await vitrine();
igual('desligados os serviços, a vitrine diz que não', v.salao.usaServicos, false);
/* ⚠ A LISTA SOME DA RESPOSTA, e não só do desenho. Deixar os serviços saírem
   e pedir para a página não os desenhar publica o catálogo de uma casa que
   decidiu não trabalhar com serviços — basta abrir o inspetor. */
igual('e a lista de serviços vem VAZIA', (v.servicos || []).length, 0);
igual('os produtos continuam inteiros', (v.produtos || []).length, 2);

await ligar(undefined, false);
v = await vitrine();
igual('desligada a loja, a vitrine diz que não', v.salao.loja, false);
igual('e a lista de produtos vem vazia', (v.produtos || []).length, 0);
igual('os serviços voltam', (v.servicos || []).length, 2);

await ligar(false, false);
v = await vitrine();
igual('com os dois desligados, nenhum serviço', (v.servicos || []).length, 0);
igual('e nenhum produto', (v.produtos || []).length, 0);
verdade('mas a casa continua respondendo: nome, logo e endereço',
  !!v.salao && v.salao.nome === 'Casa Dupla' && !!v.salao.logo);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A PENEIRA É DE LETRA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · Lixo no cfg não derruba a página da cliente');

/* ⚠ ESTA É A VERIFICAÇÃO QUE PAGA O ARQUIVO.

   O `loja` nasceu com `(s.cfg->>'loja')::boolean`, e ficou anos sem morder
   porque NENHUMA TELA escrevia a chave: o `cfg` só continha o que o painel
   punha. A partir do momento em que o dono liga e desliga isto, a chave passa
   a existir — e `'abacaxi'::boolean` LEVANTA no Postgres, não devolve nulo.

   Quem cai é a `vitrine()`, que é a única porta da página da cliente. Não é
   "a loja some": é a casa inteira fora do ar, com o link que ela mandou para
   as clientes no WhatsApp. */
await ligar('talvez', 'sei la');
/* O `try` não é frouxidão: com `::boolean` a chamada LEVANTA, e sem o `catch`
   o arquivo morre aqui com um rastro de pilha — a verificação nunca chega a
   dizer o que estava medindo. Assim ela reprova falando. */
try{ v = await vitrine(); }
catch(e){ v = null; nao('com lixo nas duas chaves, a vitrine ainda responde',
                        'a vitrine LEVANTOU: ' + e.message); }
if(v) verdade('com lixo nas duas chaves, a vitrine ainda responde',
              !!(v && v.salao));
v = v || { salao:{}, servicos:[], produtos:[] };
igual('e o lixo deixa LIGADO, que é o lado seguro', v.salao.usaServicos, true);
igual('a loja idem', v.salao.loja, true);
igual('as listas voltam inteiras', (v.servicos||[]).length + (v.produtos||[]).length, 4);

await ligar('FALSE', ' Não ');
v = await vitrine();
igual('"FALSE" com maiúscula desliga', v.salao.usaServicos, false);
igual('" Não " com espaço e acento também', v.salao.loja, false);

await ligar('0', 'f');
v = await vitrine();
igual('"0" desliga', v.salao.usaServicos, false);
igual('"f" desliga', v.salao.loja, false);

/* ══════════════════════════════════════════════════════════════════════════
   3 — A CAPA SE MONTA SOZINHA
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · As quatro combinações, num celular de 412px');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

async function capa(){
  const ctx = await nav.newContext({ viewport:{ width:412, height:915 },
                                     isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => {
    const m = document.querySelector('#capaMarca');
    return m && m.textContent.trim().length > 0;
  }, null, { timeout: 15000 });
  await p.waitForTimeout(500);
  return p;
}

/* Mede o mesmo em toda combinação. `alturaVazio` é a pergunta "sobrou bloco
   vazio?" feita ao navegador: um container sem conteúdo que mesmo assim ocupa
   altura é o buraco que o pedido mandou não deixar. */
const medir = p => p.evaluate(() => {
  const alt = id => {
    const e = document.getElementById(id);
    if(!e) return null;
    return { vazio: e.innerHTML.trim() === '', altura: Math.round(e.offsetHeight) };
  };
  const rodape = document.getElementById('rodapeAcao');
  const est = getComputedStyle(document.documentElement);
  return {
    principal: (document.querySelector('#capaBoas .boas-cta') || {}).textContent
                 ? document.querySelector('#capaBoas .boas-cta').textContent.trim() : null,
    segundo: (document.querySelector('#capaBoas .boas-b2') || {}).textContent
                 ? document.querySelector('#capaBoas .boas-b2').textContent.trim() : null,
    convite: (document.querySelector('.boas-sub') || {}).textContent.trim(),
    servicos: alt('capaServicos'),
    loja: alt('capaLoja'),
    cartoesServico: document.querySelectorAll('#capaServicos .sv-cartao').length,
    cartoesProduto: document.querySelectorAll('#capaLoja .pr-cartao').length,
    verTodosProdutos: !!Array.from(document.querySelectorAll('#capaLoja .ver-todos'))
      .find(b => /produtos/i.test(b.textContent)),
    peVisivel: rodape ? getComputedStyle(rodape).display !== 'none' : null,
    peRotulo: (document.getElementById('btPrincipal') || {}).textContent || '',
    zapNaCapa: !!document.querySelector('#capaBoas a[href*="wa.me"]'),
    palavraProduto: /produto/i.test(document.getElementById('p-capa').textContent),
    acao: est.getPropertyValue('--acao').trim().toUpperCase(),
    rolaDeLado: document.documentElement.scrollWidth
              > document.documentElement.clientWidth,
  };
});

// ── 3a · os dois ligados ────────────────────────────────────────────────
await ligar(undefined, undefined);
let p = await capa();
let m = await medir(p);
console.log('      DOIS: ' + JSON.stringify(m));
igual('com os dois, o botão de metal é o de agendar', m.principal, 'Agendar horário');
igual('e o segundo, discreto, leva aos produtos', m.segundo, 'Ver produtos');
verdade('o convite fala das duas coisas',
  /serviço/i.test(m.convite) && /produto/i.test(m.convite), m.convite);
igual('os dois serviços na vitrine', m.cartoesServico, 2);
igual('e os dois produtos', m.cartoesProduto, 2);
/* ⚠ COM DOIS PRODUTOS NÃO SOBRA NADA, e o link tem que estar lá assim mesmo:
   é a tela da loja que deixa mudar quantidade e enviar o pedido. */
verdade('"Ver todos os produtos" aparece mesmo sem sobrar produto',
  m.verTodosProdutos);

/* ⚠ A FOTO DO PRODUTO APARECE INTEIRA, e não recortada no quadrado.

   Era `center/cover`. Para foto de serviço isso funciona — cabelo, unha, um
   ambiente: é cena, e qualquer pedaço conta a mesma história. Para produto
   não: foto de produto é um vidro em pé, quase sempre em retrato, e o
   quadrado come justamente o rótulo, que é a única coisa que identifica o que
   está à venda.

   `contain` sobre uma cópia BORRADA da mesma imagem — o que o carrossel da
   capa já faz desde sempre. O dono não precisa recortar nada antes de subir. */
const foto = await p.evaluate(() => {
  /* ⚠ O CARTÃO COM FOTO, e não o primeiro da grade. A vitrine ordena por
     nome, e aqui a "Máscara Nutritiva" (sem foto) vem antes do "Shampoo
     Reparador" (com foto) — o `querySelector` seco media o cartão do
     placeholder e reprovava um código certo. */
  const f = Array.from(document.querySelectorAll('#capaLoja .pr-foto'))
    .find(x => (x.getAttribute('style') || '').includes('--pr-foto'));
  if(!f) return null;
  const e = getComputedStyle(f);
  const b = getComputedStyle(f, '::before');
  return { tamanho: e.backgroundSize, url: e.backgroundImage,
           borraoTamanho: b.backgroundSize, borraoFiltro: b.filter,
           borraoTemFoto: (b.backgroundImage || '').includes('url(') };
});
console.log('      FOTO: ' + JSON.stringify(foto));
verdade('a foto do produto aparece inteira, sem corte',
  foto && foto.tamanho === 'contain', JSON.stringify(foto));
verdade('e o fundo é uma cópia borrada dela mesma, não uma tarja cinza',
  foto && foto.borraoTamanho === 'cover' && /blur/.test(foto.borraoFiltro)
       && foto.borraoTemFoto, JSON.stringify(foto));
igual('o pé continua sendo o de agendar', m.peRotulo.trim(), 'Agendar horário');
igual('e a cor é a do salão, não uma cor cravada', m.acao, COR.toUpperCase());
verdade('nada rola de lado', !m.rolaDeLado);
await p.context().close();

// ── 3b · só serviços ────────────────────────────────────────────────────
await ligar(true, false);
p = await capa();
m = await medir(p);
console.log('      SÓ SERVIÇOS: ' + JSON.stringify(m));
igual('só serviços: um botão só, e é o de agendar', m.principal, 'Agendar horário');
igual('sem segundo botão', m.segundo, null);
/* ⚠ NEM A PALAVRA "PRODUTO" NA CAPA. Prometer "confira nossos produtos" a
   quem desligou a loja manda a cliente procurar uma seção que não existe — e
   ela conclui que a página está quebrada, não que a casa não vende. */
verdade('e a palavra "produto" não aparece em lugar nenhum da capa',
  !m.palavraProduto);
igual('o bloco da loja fica vazio', m.loja.vazio, true);
igual('e sem ocupar altura nenhuma', m.loja.altura, 0);
igual('os serviços continuam', m.cartoesServico, 2);
await p.context().close();

// ── 3c · só a loja ──────────────────────────────────────────────────────
await ligar(false, true);
p = await capa();
m = await medir(p);
console.log('      SÓ LOJA: ' + JSON.stringify(m));
igual('só loja: o botão de metal passa a ser o dos produtos',
  m.principal, 'Ver produtos');
igual('sem segundo botão', m.segundo, null);
verdade('o convite fala de pedido, e não de horário',
  /pedido/i.test(m.convite) && !/horário/i.test(m.convite), m.convite);
igual('o bloco dos serviços fica vazio', m.servicos.vazio, true);
igual('e sem ocupar altura', m.servicos.altura, 0);
igual('os produtos aparecem', m.cartoesProduto, 2);
/* O pé mudou de destino junto com o rótulo. Rótulo certo levando ao lugar
   errado é pior que rótulo errado: a pessoa toca confiante. */
igual('o pé diz "Ver produtos"', m.peRotulo.trim(), 'Ver produtos');
await p.click('#btPrincipal');
await p.waitForTimeout(700);
igual('e ele leva mesmo à loja',
  await p.evaluate(() => document.body.getAttribute('data-passo')), 'loja');
await p.context().close();

// ── 3d · nenhum dos dois ────────────────────────────────────────────────
await ligar(false, false);
p = await capa();
m = await medir(p);
console.log('      NENHUM: ' + JSON.stringify(m));
igual('sem módulo nenhum, não há botão de agendar nem de produtos',
  m.segundo, null);
verdade('o cartão oferece o WhatsApp, que é o que sobra', m.zapNaCapa);
igual('os dois blocos ficam vazios',
  [m.servicos.vazio, m.loja.vazio], [true, true]);
igual('e nenhum deles ocupa altura',
  [m.servicos.altura, m.loja.altura], [0, 0]);
/* ⚠ O PÉ SOME. Ele abriria uma lista de serviços vazia — o botão mais visível
   da tela levando ao nada. */
igual('e o botão fixo do rodapé some', m.peVisivel, false);
verdade('a casa continua se apresentando: nome e endereço',
  await p.evaluate(() => /Casa Dupla/.test(document.querySelector('.marca-salao').textContent)));
await p.context().close();

igual('nenhum erro de página nas quatro combinações', erros, []);

/* ══════════════════════════════════════════════════════════════════════════
   3e — A PRIMEIRA HORA DE UM SALÃO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3e · Módulo ligado e nada cadastrado ainda');

/* ⚠ "NÃO VEIO SERVIÇO NENHUM" TEM DUAS CAUSAS, e elas pedem telas diferentes.

   A casa desligou o módulo, ou a casa acabou de nascer. A segunda é o estado
   de TODO salão na primeira hora: o cadastro entrega o link no fim, e a dona
   manda para as clientes antes de lançar os serviços.

   Eu tratei as duas igual — o rodapé olhava a LISTA — e tirei o botão de
   entrada de quem tinha acabado de se cadastrar. A página já sabia dizer "o
   salão ainda não publicou os serviços"; ninguém chegava nessa tela para ler.
   Quem pegou foi o `cliente-nuvem.test.mjs`, que guarda essa hora.

   Fica aqui também porque é a mesma decisão que esta suíte mede — e porque um
   teste de módulos que não sabe distinguir "desligado" de "vazio" está medindo
   a coisa errada. */
const novo = novaAba();
await novo.criarConta({ email:`zero-${marca}@teste.com`, senha:'minhasenhaboa',
  nome:'Dona Zero', telefone:'+5551' + (800000000 + (Date.now() % 89999999)) });
const crZero = await novo.chamar('criar_salao', { p_nome_salao:'Casa Zero',
  p_tipo:'salao', p_telefone:'(51) 99887-6600', p_documento:null, p_origem:null });

const ctxZ = await nav.newContext({ viewport:{ width:412, height:915 },
                                    isMobile:true, hasTouch:true });
const pz = await ctxZ.newPage();
await pz.goto(BASE + '/agendar.html?salao=' + crZero[0].slug);
await pz.waitForTimeout(2200);
const zero = await pz.evaluate(() => {
  const r = document.getElementById('rodapeAcao');
  return {
    peVisivel: getComputedStyle(r).display !== 'none',
    peRotulo: (document.getElementById('btPrincipal') || {}).textContent || '',
    convite: !!document.querySelector('#capaBoas .boas-cta'),
    semProdutos: !document.querySelector('#capaBoas .boas-b2'),
  };
});
console.log('      ZERO: ' + JSON.stringify(zero));
verdade('salão sem nada cadastrado continua com o botão do rodapé',
  zero.peVisivel, JSON.stringify(zero));
igual('e ele diz agendar', zero.peRotulo.trim(), 'Agendar horário');
verdade('o cartão de boas-vindas também tem o caminho', zero.convite);
/* ⚠ E NÃO GANHA "VER PRODUTOS". A loja nasce LIGADA no `cfg`: olhar o módulo
   aqui poria esse botão na capa de todo salão que existe hoje, levando a uma
   prateleira vazia. Deste lado o vazio quer dizer "não vendemos", e não
   "ainda não". */
verdade('mas não ganha um botão de produtos que ele não tem',
  zero.semProdutos);
await pz.click('#btPrincipal');
await pz.waitForTimeout(700);
verdade('e o botão leva à tela que explica que ainda não há serviços',
  /ainda não publicou/.test(
    await pz.textContent('#listaServicos')));
await ctxZ.close();

/* ══════════════════════════════════════════════════════════════════════════
   4 — A DEMONSTRAÇÃO, ONDE NÃO EXISTE BANCO PARA PENEIRAR
   ══════════════════════════════════════════════════════════════════════════ */
secao('4 · Em demonstração quem peneira é a página');

/* ⚠ ESTA SEÇÃO EXISTE PORQUE UMA MUTAÇÃO SOBREVIVEU.

   Tirei a peneira de dentro do `produtosDaLoja()` e a suíte continuou verde:
   na bancada a `vitrine()` já tinha esvaziado a lista, então a peneira da
   tela nunca era a que decidia. Verificação que não vê o código sumir não
   protege o código.

   A demonstração é o modo em que ela decide sozinha: sem `window.AGENDAPRO`
   não há servidor, o `bd` sai do `localStorage` com o `cfg` CRU, e o valor
   pode chegar como a string "false" — que `Boolean('false')` transforma em
   `true`. É um modo que a gente publica: é como o link abre para quem só
   está experimentando o sistema.

   O endereço é o `:8099`, o servidor de arquivos, e não a bancada — a
   bancada serve o mesmo HTML mas com o banco atrás. */
const ESTATICO = process.env.ESTATICO || 'http://127.0.0.1:8099/';
const ctxD = await nav.newContext({ viewport:{ width:412, height:915 },
                                    isMobile:true, hasTouch:true });
const pd = await ctxD.newPage();
const errosD = [];
pd.on('pageerror', e => errosD.push(e.message));
await pd.goto(ESTATICO + 'agendar.html?salao=studio-bella&demo=1');
await pd.waitForTimeout(2200);

// Como o dono desligaria: a chave no cfg do salão. Em demonstração ela chega
// à tela sem passar por função nenhuma do banco.
const demoCom = (valor) => pd.evaluate((v) => {
  const sl = bd.saloes.find(x => x.id === salao.id);
  sl.cfg = Object.assign({}, sl.cfg, v);
  salao = sl;
  desenhar();
  return {
    produtos: document.querySelectorAll('#capaLoja .pr-cartao').length,
    servicos: document.querySelectorAll('#capaServicos .sv-cartao').length,
    lojaVazia: document.getElementById('capaLoja').innerHTML.trim() === '',
  };
}, valor);

let d = await demoCom({});
verdade('em demonstração, sem chave, a casa mostra produtos e serviços',
  d.produtos > 0 && d.servicos > 0, JSON.stringify(d));

d = await demoCom({ loja:false });
igual('com loja:false (booleano), os produtos somem', d.produtos, 0);
igual('e o bloco fica vazio', d.lojaVazia, true);
verdade('os serviços não vão junto', d.servicos > 0, JSON.stringify(d));

/* ⚠ A STRING "false" É O CASO DE VERDADE. O jsonb do Postgres devolve texto,
   e `Boolean('false')` é `true`: uma peneira feita com `!!` traria a loja de
   volta para todo salão que a desligou. */
d = await demoCom({ loja:'false' });
igual('com a STRING "false", os produtos também somem', d.produtos, 0);

d = await demoCom({ loja:'talvez' });
verdade('e com lixo a loja fica LIGADA, que é o lado seguro',
  d.produtos > 0, JSON.stringify(d));

d = await demoCom({ loja:true, usaServicos:false });
igual('desligando os serviços, eles somem', d.servicos, 0);
verdade('e os produtos ficam', d.produtos > 0, JSON.stringify(d));

igual('nenhum erro na demonstração', errosD, []);
await ctxD.close();

/* ══════════════════════════════════════════════════════════════════════════
   5 — O DONO ESCOLHE NO PAINEL, E A ESCOLHA FICA
   ══════════════════════════════════════════════════════════════════════════ */
secao('5 · O painel grava, e a escolha sobrevive ao recarregar');

await ligar(undefined, undefined);

const ctxP = await nav.newContext({ viewport:{ width:1360, height:900 } });
const pa = await ctxP.newPage();
const errosP = [];
pa.on('pageerror', e => errosP.push(e.message));
pa.on('dialog', async d => { await d.accept(); });
await pa.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await pa.goto(BASE + '/app.html');
await pa.waitForTimeout(4000);
await pa.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await pa.waitForTimeout(1200);
await pa.click('#abas .aba[data-chave="salao"]');
await pa.waitForTimeout(900);

const reguas = await pa.evaluate(() => ({
  servico: !!document.getElementById('reguaModServico'),
  loja: !!document.getElementById('reguaModLoja'),
  nServico: document.querySelectorAll('#reguaModServico button').length,
  marcado: (document.querySelector('#reguaModServico button.on') || {}).textContent,
  explica: (document.getElementById('explicaModulos') || {}).textContent || '',
}));
console.log('      ' + JSON.stringify(reguas));
verdade('as duas réguas estão na tela', reguas.servico && reguas.loja);
igual('cada uma com Sim e Não', reguas.nServico, 2);
igual('e nascem em Sim, que é o que toda casa já é', reguas.marcado, 'Sim');
verdade('a frase diz o que a CLIENTE vai ver, não o que foi marcado',
  /serviços e com a vitrine/i.test(reguas.explica), reguas.explica);

/* ⚠ ALVO DE TOQUE. A caixinha de marcar já reprovou nesta tela uma vez — 13px
   num aparelho de 375 — e foi por isso que o projeto passou a usar régua. */
const alvo = await pa.evaluate(() => Math.round(
  document.querySelector('#reguaModLoja button').getBoundingClientRect().height));
verdade('os botões da régua têm alvo de toque de gente', alvo >= 36, String(alvo));

// O dono desliga a loja, do jeito que ele desligaria: clicando.
await pa.evaluate(() => {
  const bt = Array.from(document.querySelectorAll('#reguaModLoja button'))
    .find(b => b.textContent.trim() === 'Não');
  bt.click();
});
await pa.waitForTimeout(300);
const depoisDoClique = await pa.evaluate(() =>
  (document.getElementById('explicaModulos') || {}).textContent || '');
verdade('a frase muda na hora, antes mesmo de salvar',
  /só com os serviços/i.test(depoisDoClique), depoisDoClique);

await pa.evaluate(() => salvarCadastroSalao());
await pa.waitForTimeout(2000);
const gravado = ((await dona.lista('saloes', { id: SALAO }))[0].cfg || {});
igual('a escolha chega ao banco', gravado.loja, false);
igual('e o outro módulo não foi junto', gravado.usaServicos, true);

/* ⚠ E ELA FICA. "Escolhi, salvei, e voltou como estava" é exatamente o que o
   dashboard entregou uma vez — a tela mostrava o estado errado depois de
   gravar, e ninguém percebeu porque o teste chamava a função pelo nome em vez
   de recarregar. */
await pa.reload();
await pa.waitForTimeout(4000);
await pa.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await pa.waitForTimeout(900);
await pa.click('#abas .aba[data-chave="salao"]');
await pa.waitForTimeout(900);
const marcadoDepois = await pa.evaluate(() => ({
  loja: (document.querySelector('#reguaModLoja button.on') || {}).textContent,
  servico: (document.querySelector('#reguaModServico button.on') || {}).textContent,
}));
igual('ao reabrir o painel, a loja continua em Não', marcadoDepois.loja, 'Não');
igual('e os serviços continuam em Sim', marcadoDepois.servico, 'Sim');

/* ⚠ E A ABA DE PRODUTOS CONTINUA NO PAINEL. Este interruptor é sobre a PÁGINA
   DA CLIENTE. O catálogo alimenta a comanda — vender um shampoo no balcão não
   tem nada a ver com vender pelo link — e esconder a aba junto tiraria do dono
   uma venda que ele faz todo dia. */
verdade('a aba Produtos do painel continua lá, mesmo com a loja desligada',
  await pa.evaluate(() => !!document.querySelector('#abas .aba[data-chave="produtos"]')));

igual('nenhum erro no painel', errosP, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
