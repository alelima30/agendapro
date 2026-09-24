/* ===========================================================================
   AgendaPro — a sua conta: o e-mail de acesso e a troca de senha

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/conta.test.mjs

   O pedido: "tem que ter no cadastro do salão o e-mail cadastrado e a
   possibilidade de trocar a senha".

   Faltavam as duas. Quem esquecia com qual endereço tinha se cadastrado não
   tinha onde olhar, e trocar a senha exigia SAIR, pedir "esqueci minha senha"
   e esperar um e-mail — para trocar uma senha que a pessoa sabe.

   ── O QUE ESTE ARQUIVO MEDE, E POR QUÊ ─────────────────────────────────────
   Tela de senha erra de dois jeitos, e os dois são caros:

     1. TROCAR SEM CONFERIR A ATUAL. O `PUT /user` do Supabase aceita a troca
        só com a sessão aberta. Numa recepção, o computador destravado um
        minuto basta para alguém trancar a dona para fora do próprio salão.
        A conferência tem que ser DO SERVIDOR — validação de tela é contornada
        por quem abrir o console, e o PUT continua passando.

     2. DIZER QUE TROCOU SEM TER TROCADO. É o pior: a pessoa anota a senha
        nova, sai, e não consegue mais entrar. Aqui a prova é entrar DE VERDADE
        com a senha nova, e levar recusa com a velha.
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
const EMAIL = `conta-${marca}@teste.com`;
const SENHA_VELHA = 'minhasenhaboa';
const SENHA_NOVA  = 'outrasenhamelhor';

const dona = novaAba();
await dona.criarConta({ email: EMAIL, senha: SENHA_VELHA, nome:'Rita Alves',
  telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Casa da Conta',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id;
ok('conta e salão criados');

/* ══════════════════════════════════════════════════════════════════════════
   1 — O dados.js, sem navegador
   ══════════════════════════════════════════════════════════════════════════ */
secao('1 · As duas funções novas do dados.js');

const eu = await dona.minhaConta();
console.log('      ' + JSON.stringify(eu));
igual('minhaConta() devolve o e-mail com que a pessoa entra', eu.email, EMAIL);
verdade('e o id dela', !!eu.id);

/* ⚠ A SENHA ERRADA TEM QUE SER RECUSADA PELO SERVIDOR. Esta é a verificação
   que sustenta a tela inteira: sem ela, a senha atual vira enfeite. */
let recusou = null;
try{ await dona.trocarMinhaSenha({ atual:'senhaerradamesmo', nova: SENHA_NOVA }); }
catch(e){ recusou = e; }
verdade('com a senha atual errada, a troca é RECUSADA', !!recusou,
  'a troca passou sem conferir a senha atual');
verdade('e o servidor diz que a credencial é inválida',
  recusou && (String(recusou.codigo) === 'invalid_credentials'
              || /invalid/i.test(String(recusou.message))),
  recusou ? `codigo=${recusou.codigo} msg=${recusou.message}` : '');

/* ⚠ E A SENHA VELHA CONTINUA VALENDO depois da recusa. Uma tentativa falha
   não pode deixar a conta num meio-termo. */
const conferir = novaAba();
await conferir.entrar({ email: EMAIL, senha: SENHA_VELHA });
ok('depois da recusa, a senha velha ainda entra');

// Agora a troca de verdade.
await dona.trocarMinhaSenha({ atual: SENHA_VELHA, nova: SENHA_NOVA });
ok('com a senha atual certa, a troca é aceita');

/* ⚠ A PROVA É ENTRAR, e não a função ter devolvido sem erro. "Disse que
   trocou e não trocou" é o pior defeito possível aqui: a pessoa anota a
   senha nova, sai, e não consegue mais entrar. */
const comNova = novaAba();
await comNova.entrar({ email: EMAIL, senha: SENHA_NOVA });
ok('a senha NOVA entra de verdade');

let velhaRecusada = null;
const comVelha = novaAba();
try{ await comVelha.entrar({ email: EMAIL, senha: SENHA_VELHA }); }
catch(e){ velhaRecusada = e; }
verdade('e a senha velha para de entrar', !!velhaRecusada,
  'a senha antiga continua valendo — a troca não pegou');

/* ⚠ A SESSÃO DE QUEM TROCOU CONTINUA VALENDO. Derrubar a própria pessoa no
   meio do trabalho, para ela ter que entrar de novo, é castigo por ter feito
   a coisa certa. */
const aindaDentro = await dona.lista('saloes', { id: SALAO });
igual('e quem trocou continua conectado, sem precisar entrar de novo',
  (aindaDentro[0] || {}).id, SALAO);

/* ══════════════════════════════════════════════════════════════════════════
   2 — A TELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('2 · O cartão "Sua conta" no painel');

const nav = await chromium.launch({ executablePath: CHROMIUM });
const ctx = await nav.newContext({ viewport:{ width:1360, height:900 } });
const p = await ctx.newPage();
const erros = [];
p.on('pageerror', e => erros.push(e.message));
p.on('dialog', async d => { await d.accept(); });
await p.addInitScript(([b, s]) => {
  window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
  localStorage.setItem('agendapro.sessao', JSON.stringify(s));
}, [BASE, dona.sessao()]);
await p.goto(BASE + '/app.html');
await p.waitForTimeout(4000);
await p.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await p.waitForTimeout(1200);
await p.click('#abas .aba[data-chave="salao"]');
/* A leitura da conta é uma ida ao servidor: espera o "Carregando…" sair, em
   vez de um tempo fixo. Tempo fixo correndo contra a rede é o defeito que
   fez o `dashboard.test.mjs` falhar dentro da bateria e passar sozinho. */
await p.waitForFunction(() => {
  const e = document.getElementById('contaCorpo');
  return e && !/Carregando/.test(e.textContent);
}, null, { timeout: 15000 });

const naTela = await p.evaluate(() => ({
  email: (document.getElementById('contaEmail') || {}).value,
  soLeitura: (document.getElementById('contaEmail') || {}).readOnly,
  temBotao: !!Array.from(document.querySelectorAll('#contaCorpo button'))
    .find(b => /Trocar minha senha/.test(b.textContent)),
}));
console.log('      ' + JSON.stringify(naTela));
igual('o cartão mostra o e-mail de acesso', naTela.email, EMAIL);
/* `readonly` e não `disabled`: campo desabilitado não deixa selecionar, e a
   pessoa vem aqui justamente para copiar o endereço. */
igual('o campo é só de leitura, mas dá para selecionar e copiar',
  naTela.soLeitura, true);
verdade('e existe o botão de trocar a senha', naTela.temBotao);

// ── A senha atual errada, pela tela ──────────────────────────────────────
await p.evaluate(() => abrirTrocaDeSenha());
await p.waitForTimeout(400);
const campos = await p.evaluate(() => ({
  atual: !!document.getElementById('senhaAtual'),
  nova: !!document.getElementById('senhaNova'),
  nova2: !!document.getElementById('senhaNova2'),
  tipoAtual: (document.getElementById('senhaAtual') || {}).type,
}));
verdade('o formulário pede a atual, a nova e a repetição',
  campos.atual && campos.nova && campos.nova2, JSON.stringify(campos));
igual('e os campos escondem o que é digitado', campos.tipoAtual, 'password');

/* ⚠ A REPETIÇÃO É CONFERIDA ANTES DE IR AO SERVIDOR. Senha nova é digitada às
   cegas: um dedo torto e a pessoa fica trancada fora sem saber o que digitou.
   Isto NÃO substitui a conferência da atual, que é do servidor — são duas
   coisas diferentes, e a de baixo é a que protege. */
await p.evaluate(([a, b]) => {
  document.getElementById('senhaAtual').value = a;
  document.getElementById('senhaNova').value = b;
  document.getElementById('senhaNova2').value = b + 'x';
}, [SENHA_NOVA, 'umasenhalonga']);
await p.evaluate(() => salvarSenhaNova());
await p.waitForTimeout(600);
verdade('digitando a repetição diferente, a tela avisa e não chama o servidor',
  /não são iguais/i.test(await p.textContent('#recadoSenha')),
  await p.textContent('#recadoSenha'));

await p.evaluate(() => {
  document.getElementById('senhaNova').value = 'curta';
  document.getElementById('senhaNova2').value = 'curta';
});
await p.evaluate(() => salvarSenhaNova());
await p.waitForTimeout(600);
verdade('senha curta demais também é barrada antes',
  /8 caracteres/i.test(await p.textContent('#recadoSenha')),
  await p.textContent('#recadoSenha'));

/* ⚠ E A SENHA ATUAL ERRADA DÁ UMA FRASE QUE DIZ O QUE FAZER. "Erro 400" faz
   a pessoa achar que o sistema quebrou; "a senha atual não confere" faz ela
   tentar outra. */
await p.evaluate(() => {
  document.getElementById('senhaAtual').value = 'senhaerradamesmo';
  document.getElementById('senhaNova').value = 'terceirasenhaboa';
  document.getElementById('senhaNova2').value = 'terceirasenhaboa';
});
await p.evaluate(() => salvarSenhaNova());
await p.waitForFunction(() =>
  /não confere|não consegui/i.test(
    (document.getElementById('recadoSenha') || {}).textContent || ''),
  null, { timeout: 15000 });
verdade('com a atual errada, a tela diz exatamente isso',
  /senha atual não confere/i.test(await p.textContent('#recadoSenha')),
  await p.textContent('#recadoSenha'));
/* E indica a saída de quem realmente não lembra, em vez de deixar a pessoa
   presa na tela. */
verdade('e aponta o "esqueci minha senha" para quem não lembra mesmo',
  /esqueci minha senha/i.test(await p.textContent('#recadoSenha')));

// ── E a troca que funciona, pela tela ────────────────────────────────────
const SENHA_TRES = 'aterceirasenhaboa';
await p.evaluate(([a, b]) => {
  document.getElementById('senhaAtual').value = a;
  document.getElementById('senhaNova').value = b;
  document.getElementById('senhaNova2').value = b;
}, [SENHA_NOVA, SENHA_TRES]);
await p.evaluate(() => salvarSenhaNova());
await p.waitForFunction(() =>
  /trocada|não consegui|não confere/i.test(
    (document.getElementById('recadoSenha') || {}).textContent || ''),
  null, { timeout: 15000 });
const fim = await p.textContent('#recadoSenha');
verdade('com tudo certo, a tela confirma que trocou', /trocada/i.test(fim), fim);
/* ⚠ E CONFIRMA EM VEZ DE FECHAR CALADO. Fechar sem dizer nada deixa a dúvida
   "será que trocou?" — e é a dúvida que faz a pessoa trocar de novo, ou
   anotar a senha num papel para não arriscar. */
verdade('e diz o que acontece nos outros aparelhos',
  /outros aparelhos/i.test(fim), fim);

const comTres = novaAba();
await comTres.entrar({ email: EMAIL, senha: SENHA_TRES });
ok('e a senha escolhida na tela entra de verdade');

igual('nenhum erro de página', erros, []);

/* ══════════════════════════════════════════════════════════════════════════
   3 — A DEMONSTRAÇÃO
   ══════════════════════════════════════════════════════════════════════════ */
secao('3 · Em demonstração não há conta, e a tela diz isso');

/* ⚠ NÃO PROMETER O QUE NÃO EXISTE. Na demonstração o banco mora no navegador
   e quem abre a página já está dentro: um campo de senha ali seria um
   cadeado pintado na porta. */
const ESTATICO = process.env.ESTATICO || 'http://127.0.0.1:8099/';
const ctxD = await nav.newContext({ viewport:{ width:1360, height:900 } });
const pd = await ctxD.newPage();
const errosD = [];
pd.on('pageerror', e => errosD.push(e.message));
await pd.goto(ESTATICO + 'app.html?demo=1');
await pd.waitForTimeout(3000);
await pd.evaluate(() => { if(typeof pdFechar === 'function') pdFechar(true); });
await pd.waitForTimeout(900);
await pd.click('#abas .aba[data-chave="salao"]');
await pd.waitForTimeout(900);
const demo = await pd.evaluate(() => ({
  texto: (document.getElementById('contaCorpo') || {}).textContent || '',
  temCampo: !!document.getElementById('contaEmail'),
}));
console.log('      ' + JSON.stringify(demo).slice(0, 220));
verdade('o cartão existe e explica que ali não há conta',
  /demonstração/i.test(demo.texto), demo.texto.slice(0, 140));
verdade('e não oferece campo de e-mail nem troca de senha', !demo.temCampo);
igual('nenhum erro na demonstração', errosD, []);

await nav.close();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
