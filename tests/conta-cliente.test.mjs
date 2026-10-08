/* ===========================================================================
   AgendaPro — a conta da cliente no link (e-mail e senha)

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/conta-cliente.test.mjs

   O motivo: o pacote vendido no balcão só dá o R$ 0,00 com a cliente LOGADA
   (27_pacotes.sql), e o link não tinha onde criar conta nem entrar. Na
   prática, ninguém usava o pacote. E "Meus horários" só mostrava o que foi
   marcado no próprio aparelho.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. sem conta: o atalho "Entrar na minha conta" na capa, e o "Entrar" no
        topo das telas;
     2. a tela de conta: Entrar e Criar conta, com as frases de erro em
        português (senha errada, e-mail que já tem conta, senha curta);
     3. criar a conta liga a ficha do balcão (telefone e primeiro nome, sem o
        55) e o pacote aparece na capa;
     4. marcando logada: R$ 0,00 na conferência, e o banco grava zero com o
        pacote;
     5. noutro aparelho, ao entrar, "Meus horários" mostra o que ela marcou;
     6. a senha opcional no cadastro cria a conta junto, e a marcação sai
        ligada a ela;
     7. sair volta tudo ao normal;
     8. primeiro nome diferente não liga (o critério do banco, escrito);
     9. o painel diz quem do pacote tem conta;
    10. o "esqueci a senha" e a confirmação voltam para o link do salão;
    11. a 360px a tela cabe; nenhum erro de JavaScript.
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

function aba(){
  const g = {};
  const j = { AGENDAPRO:{ url:BASE, chave:'k', ambiente:'bancada' },
    localStorage:{ getItem:k=>(k in g?g[k]:null), setItem:(k,v)=>{g[k]=String(v)},
                   removeItem:k=>{delete g[k]} } };
  new Function('window','console','fetch','localStorage',
    fs.readFileSync(path.join(RAIZ,'dados.js'),'utf8'))(
    j, { info(){}, error(){}, log(){} }, fetch, j.localStorage);
  return j.Dados;
}

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const n8 = String(Date.now() % 100000000).padStart(8, '0');
const TEL_MARIA = '519' + n8;               // como o balcão digita: DDD + número
const TEL_BEA   = '518' + n8;
const TEL_ANA   = '517' + n8;
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;

const dona = aba();
await dona.criarConta({ email:`cc-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:60,
  intervaloMin:0, preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA } });

// O pacote vendido no balcão, para duas fichas que o salão cadastrou.
const pacote = await dona.inserir('pacotes', { salaoId: SALAO, nome:'Escova em dia', preco:150,
  sessoes:4, validadeDias:90, dias:[0,1,2,3,4,5,6], ativo:true });
await dona.inserir('pacote_servicos', { pacoteId: pacote.id, servicoId: escova.id });
const fichaMaria = await dona.inserir('clientes', { salaoId: SALAO, nome:'Maria Souza', telefone: TEL_MARIA });
const fichaBea   = await dona.inserir('clientes', { salaoId: SALAO, nome:'Beatriz Lima', telefone: TEL_BEA });
await dona.chamar('vender_pacote', { p_pacote: pacote.id, p_cliente: fichaMaria.id });
await dona.chamar('vender_pacote', { p_pacote: pacote.id, p_cliente: fichaBea.id });
const perfilDa = async id => ((await dona.lista('clientes', { salaoId: SALAO })).find(c => c.id === id) || {}).perfilId || null;

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];
async function aparelho(largura = 390){
  const ctx = await nav.newContext({ viewport:{ width: largura, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  p.on('dialog', d => d.accept());
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(800);
  return { p, ctx };
}
const atalhos = p => p.evaluate(() => [...document.querySelectorAll('#capaAtalhos .atalho b')].map(b => b.textContent.trim()));
const logada = p => p.evaluate(() => !!(Dados.sessaoAtual && Dados.sessaoAtual()));
const aviso = p => p.evaluate(() => document.getElementById('avisoConta').innerText.replace(/\s+/g, ' ').trim());

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. Sem conta: as portas de entrada');
const A = await aparelho();
{
  const p = A.p;
  igual('a capa oferece "Entrar na minha conta"', (await atalhos(p)).includes('Entrar na minha conta'), true);
  await p.click('.boas-cta'); await p.waitForTimeout(400);
  igual('nas telas de dentro, "Entrar" no topo', await p.evaluate(() => {
    const b = document.getElementById('btEu'); return [!!b.offsetParent, b.textContent.trim()]; }), [true, 'Entrar']);
  await p.click('#btEu'); await p.waitForTimeout(300);
  const t = await p.evaluate(() => ({ tela, titulo: document.getElementById('contaTitulo').textContent,
    abas: [...document.querySelectorAll('.conta-abas button')].map(b => b.textContent + (b.classList.contains('on') ? ' ●' : '')),
    criar: !!document.getElementById('contaCriarCampos').offsetParent,
    esqueci: !!document.getElementById('linhaEsqueci').offsetParent,
    bp: document.getElementById('btPrincipal').textContent.trim() }));
  igual('abre a tela de conta, em Entrar', [t.tela, t.titulo, t.abas, t.criar, t.esqueci, t.bp],
    ['conta', 'Entrar', ['Entrar ●', 'Criar conta'], false, true, 'Entrar']);

  secao('2. Criar conta, e as frases de erro');
  await p.click('#abaCriar'); await p.waitForTimeout(200);
  igual('em Criar conta: nome e WhatsApp aparecem, o esqueci some', await p.evaluate(() =>
    [document.getElementById('contaTitulo').textContent, !!document.getElementById('contaCriarCampos').offsetParent,
     !!document.getElementById('linhaEsqueci').offsetParent, document.getElementById('btPrincipal').textContent.trim()]),
    ['Criar conta', true, false, 'Criar conta']);
  await p.fill('#cNome', 'Maria');
  await p.fill('#cTel', masc(TEL_MARIA));
  await p.fill('#cEmail', `maria-${m}@t.com`);
  await p.fill('#cSenha', 'curta');
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  verdade('senha curta: diz quantos caracteres', /pelo menos 8/.test(await aviso(p)), await aviso(p));
  await p.fill('#cSenha', 'senhaboa123');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);

  secao('3. A conta liga a ficha do balcão, e o pacote aparece');
  igual('entrou, e voltou para onde estava', [await logada(p), await p.evaluate(() => tela)], [true, 'servico']);
  igual('no banco, a ficha "Maria Souza" (telefone sem o 55) ficou ligada à conta',
    !!(await perfilDa(fichaMaria.id)), true);
  await p.click('#btVoltar'); await p.waitForTimeout(500);
  const at = await atalhos(p);
  igual('na capa: Meus pacotes, e não mais o "Entrar"', [at.includes('Meus pacotes'), at.includes('Entrar na minha conta')], [true, false]);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  igual('o topo mostra o nome dela', await p.evaluate(() => document.getElementById('btEu').textContent.trim()), 'Maria');

  secao('4. Marcando logada: R$ 0,00, e o banco concorda');
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(2500);
  /* ⚠ AMANHÃ, e não o primeiro horário de hoje: perto da hora, o "Cancelar"
     dá lugar a "fale com o salão" (regra das 2 horas), e o item 5 passava de
     madrugada e falhava de manhã. */
  await p.locator('#listaDias .dia:not(.sem)').nth(1).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.waitForTimeout(300);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  const dados = await p.evaluate(() => ({ tela, conta: document.getElementById('dadosConta').innerText.trim(),
    senha: !!document.getElementById('campoSenhaCadastro').offsetParent,
    nome: document.getElementById('dNome').value, tel: document.getElementById('dTel').value }));
  igual('o cadastro já sabe quem ela é, e não pede senha', [dados.tela, /Você está na sua conta/.test(dados.conta),
    dados.senha, dados.nome, dados.tel], ['dados', true, false, 'Maria', masc(TEL_MARIA)]);
  /* LOGADA: só confirmar o nome. Dos outros, só o que a conta não tem — e a
     conta nasce sem aniversário. WhatsApp e e-mail ela já deu. */
  const vis = () => p.evaluate(() => ({
    titulo: document.getElementById('dadosTitulo').textContent,
    campos: ['campoNome','campoTel','campoNasc','campoCpf','campoEmail']
      .filter(id => !!document.getElementById(id).offsetParent),
    conta: document.getElementById('dadosConta').innerText.replace(/\s+/g, ' ') }));
  const v1 = await vis();
  igual('logada: "Confirme seu cadastro", e só o que falta vira campo (o aniversário) — o nome não',
    [v1.titulo, v1.campos], ['Confirme seu cadastro', ['campoNasc']]);
  verdade('o cartão mostra nome, WhatsApp e e-mail da conta, e o jeito de trocar de conta',
    /Nome Maria/.test(v1.conta) && v1.conta.includes(masc(TEL_MARIA)) && v1.conta.includes(`maria-${m}@t.com`)
    && /Entrar com outra conta/.test(v1.conta), v1.conta);
  await p.fill('#dNasc', '1990-05-04');
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  // O `toLocaleString` separa "R$" do número com espaço que não quebra.
  const total = await p.evaluate(() => document.querySelector('#resumoFinal .cf-total b').textContent.trim().replace(/\s/g, ' '));
  igual('na conferência: R$ 0,00', total, 'R$ 0,00');
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const ags = await dona.lista('agendamentos', { salaoId: SALAO });
  const ag = ags[ags.length - 1];
  igual('marcado: o banco grava zero e aponta o pacote', [await p.evaluate(() => tela), Number(ag.valorPrevisto),
    !!(ag.pacoteClienteId || ag.pacote_cliente_id), ag.clienteId === fichaMaria.id], ['pronto', 0, true, true]);
  await p.evaluate(() => irPara('meus')); await p.waitForTimeout(2000);
  const meus = await p.evaluate(() => document.getElementById('listaMeus').innerText);
  igual('neste aparelho, que também guardou a marcação, ela aparece uma vez só',
    (meus.match(/Escova/g) || []).length, 1);
  /* A foto do dono: logo depois de cadastrar e marcar, Meus horários com o
     topo dizendo "Entrar". */
  igual('em Meus horários, o topo não diz "Entrar" para quem já entrou', await p.evaluate(() => {
    const b = document.getElementById('btEu'); return b.offsetParent ? b.textContent.trim() : '(escondido)'; }), '(escondido)');

  // A segunda marcação: o aniversário já foi dado, então sobra só o nome.
  await p.evaluate(() => irPara('capa', true)); await p.waitForTimeout(400);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  if(await p.evaluate(() => !escolha.servicos.length)) await p.click('#listaServicos .sv-cartao');
  await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(2500);
  await p.locator('#listaDias .dia:not(.sem)').nth(2).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.waitForTimeout(300);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  const v2 = await vis();
  igual('na segunda vez, logada, nenhum campo: só conferir e continuar',
    [await p.evaluate(() => tela), v2.campos, /Confira seus dados e toque em Continuar/.test(await p.evaluate(() =>
      document.getElementById('dadosSub').textContent))], ['dados', [], true]);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  igual('e o Continuar segue direto para a conferência', await p.evaluate(() => tela), 'confirmar');
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. Noutro aparelho: entrar traz os horários');
{
  const { p, ctx } = await aparelho();
  await p.click('#btEu').catch(() => {});
  await p.evaluate(() => irPara('meus')); await p.waitForTimeout(800);
  const antes = await p.evaluate(() => document.getElementById('listaMeus').innerText.replace(/\s+/g, ' '));
  verdade('sem conta, Meus horários convida a entrar', /Entre na sua conta/.test(antes) && /Nenhum horário neste aparelho/.test(antes), antes.slice(0, 160));
  await p.click('#listaMeus button:has-text("Entrar")'); await p.waitForTimeout(300);
  await p.fill('#cEmail', `maria-${m}@t.com`);
  await p.fill('#cSenha', 'errada123');
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  verdade('senha errada: "E-mail ou senha não conferem"', /E-mail ou senha não conferem/.test(await aviso(p)), await aviso(p));
  await p.fill('#cSenha', 'senhaboa123');
  await p.click('#btPrincipal'); await p.waitForTimeout(3000);
  const depois = await p.evaluate(() => ({ tela, txt: document.getElementById('listaMeus').innerText.replace(/\s+/g, ' ') }));
  igual('volta para Meus horários', depois.tela, 'meus');
  verdade('e mostra a escova marcada no outro celular, com Remarcar e Cancelar',
    /Na sua conta/.test(depois.txt) && /Escova/.test(depois.txt) && /Cancelar/.test(depois.txt), depois.txt.slice(0, 240));

  secao('7. Sair');
  await p.click('#p-meus button:has-text("Sair desta conta")'); await p.waitForTimeout(1500);
  igual('sai da conta e volta à capa, com o "Entrar" de novo', [await logada(p), await p.evaluate(() => tela),
    (await atalhos(p)).includes('Entrar na minha conta'), (await atalhos(p)).includes('Meus pacotes')], [false, 'capa', true, false]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2b. E-mail que já tem conta');
{
  const { p, ctx } = await aparelho();
  const cadastros = [];
  p.on('request', r => { if(/\/auth\/v1\/signup/.test(r.url())) cadastros.push(decodeURIComponent(r.url())); });
  await p.evaluate(() => abrirConta('criar')); await p.waitForTimeout(200);
  await p.fill('#cNome', 'Maria'); await p.fill('#cTel', masc(TEL_MARIA));
  await p.fill('#cEmail', `maria-${m}@t.com`); await p.fill('#cSenha', 'outrasenha1');
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  verdade('diz que o e-mail já tem conta, e oferece entrar', /Este e-mail já tem conta/.test(await aviso(p))
    && await p.isVisible('#avisoConta button:has-text("Entrar com ele")'), await aviso(p));
  verdade('o e-mail de confirmação da conta nova volta para o link do salão',
    cadastros.length === 1 && cadastros[0].includes('redirect_to=') && cadastros[0].includes('agendar.html?salao=' + SLUG), cadastros.join(' | '));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. A senha opcional no cadastro cria a conta junto');
{
  const { p, ctx } = await aparelho();
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(2500);
  await p.click('#listaHoras .hora'); await p.waitForTimeout(300);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  igual('sem conta, o cadastro mostra "Já tem conta?" e a senha opcional', await p.evaluate(() =>
    [/Já tem conta\?/.test(document.getElementById('dadosConta').innerText), !!document.getElementById('campoSenhaCadastro').offsetParent]),
    [true, true]);
  igual('e, sem conta, o cadastro inteiro', await p.evaluate(() => [document.getElementById('dadosTitulo').textContent,
    ['campoNome','campoTel','campoNasc','campoCpf','campoEmail'].every(id => !!document.getElementById(id).offsetParent)]),
    ['Seu cadastro', true]);
  await p.fill('#dNome', 'Ana Paula'); await p.fill('#dTel', masc(TEL_ANA));
  await p.fill('#dNasc', '1992-03-02'); await p.fill('#dEmail', `ana-${m}@t.com`);
  await p.fill('#dSenha', '123');
  await p.click('#btPrincipal'); await p.waitForTimeout(400);
  verdade('senha curta no cadastro: diz o mínimo, ou para deixar em branco', /8 caracteres — ou deixe em branco/.test(
    await p.evaluate(() => document.getElementById('avisoDados').innerText)));
  await p.fill('#dSenha', 'senhadaana1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('a conta nasce e ela segue para a conferência, já logada', [await p.evaluate(() => tela), await logada(p)], ['confirmar', true]);
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  const fichaAna = (await dona.lista('clientes', { salaoId: SALAO })).find(c => c.nome === 'Ana Paula');
  verdade('a ficha nova da Ana nasce ligada à conta', !!(fichaAna && fichaAna.perfilId), JSON.stringify(fichaAna));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('8. Primeiro nome diferente não liga');
{
  const { p, ctx } = await aparelho();
  await p.evaluate(() => abrirConta('criar')); await p.waitForTimeout(200);
  await p.fill('#cNome', 'Bia'); await p.fill('#cTel', masc(TEL_BEA));
  await p.fill('#cEmail', `bia-${m}@t.com`); await p.fill('#cSenha', 'senhadabia1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('"Bia" com a ficha de "Beatriz Lima": a conta entra, a ficha não liga, e o pacote não aparece',
    [await logada(p), await perfilDa(fichaBea.id), (await atalhos(p)).includes('Meus pacotes')], [true, null, false]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('9. No painel: quem do pacote tem conta');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.clientes) && bd.clientes.length, null, { timeout: 20000 });
  await p.waitForTimeout(800);
  const linhas = await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true);
    irPara('pacotes'); return new Promise(r => setTimeout(() => r([...document.querySelectorAll('table.tab tr')]
      .map(tr => tr.innerText.replace(/\s+/g, ' ').trim()).filter(t => /Maria|Beatriz/.test(t))), 600)); });
  verdade('Maria "com conta", Beatriz "sem conta ainda"', linhas.some(l => /Maria Souza com conta/.test(l))
    && linhas.some(l => /Beatriz Lima sem conta ainda/.test(l)), JSON.stringify(linhas));
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('10. Esqueci a senha e a confirmação voltam para o link');
{
  const { p, ctx } = await aparelho();
  const pedidos = [];
  p.on('request', r => { if(/\/auth\/v1\/(recover|resend|signup)/.test(r.url())) pedidos.push(decodeURIComponent(r.url())); });
  await p.evaluate(() => abrirConta('entrar')); await p.waitForTimeout(200);
  await p.fill('#cEmail', `maria-${m}@t.com`);
  await p.click('#linhaEsqueci button'); await p.waitForTimeout(800);
  verdade('o pedido de senha nova volta, depois, para este salão', pedidos.some(u =>
    u.includes('nova-senha.html?volta=' + encodeURIComponent('agendar.html?salao=' + SLUG))), pedidos.join(' | '));
  verdade('e a tela não diz se o e-mail existe', /Se houver conta com/.test(await aviso(p)));
  await p.evaluate(() => reenviarConfirmacaoCliente()); await p.waitForTimeout(600);
  verdade('o reenvio da confirmação também volta para o link', pedidos.some(u =>
    /resend\?redirect_to=.*agendar\.html\?salao=/.test(u)), pedidos.join(' | '));

  secao('11. A 360px');
  await ctx.close();
  const B = await aparelho(360);
  await B.p.evaluate(() => abrirConta('criar')); await B.p.waitForTimeout(300);
  igual('a tela de conta cabe, sem rolar de lado', await B.p.evaluate(() => document.documentElement.scrollWidth - innerWidth <= 0), true);
  await B.ctx.close();
}
await A.ctx.close();

/* ══════════════════════════════════════════════════════════════════════════ */
secao('12. O banco, sem a tela');
{
  const anon = aba();
  let barrou = 0;
  for(const [fn, args] of [['ligar_minha_ficha', { p_salao: SALAO }], ['meus_agendamentos_da_conta', {}]]){
    try{ await anon.chamar(fn, args); }catch(e){ barrou++; }
  }
  igual('sem login, as duas funções novas recusam', barrou, 2);

  const bia = aba();
  await bia.entrar({ email:`bia-${m}@t.com`, senha:'senhadabia1' });
  igual('a Bia não vê a marcação da Maria pela conta', await bia.chamar('meus_agendamentos_da_conta', {}), []);

  /* Duas contas com o mesmo WhatsApp não existem: a segunda nasce sem
     telefone (08_conta.sql), e sem telefone não liga ficha nenhuma. */
  const donaDaFicha = await perfilDa(fichaMaria.id);
  const outra = aba();
  await outra.criarConta({ email:`outra-${m}@t.com`, senha:'senhaqualquer1', nome:'Maria', telefone:'+55' + TEL_MARIA });
  const r1 = await outra.chamar('ligar_minha_ficha', { p_salao: SALAO });
  igual('o WhatsApp da Maria numa segunda conta: nasce sem telefone e não liga nada',
    [r1 && r1.telefone, r1 && r1.ficha, await perfilDa(fichaMaria.id)], [null, null, donaDaFicha]);

  /* Número reciclado: a Maria trocou de WhatsApp, e a ficha dela no salão
     ficou com o número velho — já ligada à conta dela. A operadora repassou
     esse número, e quem o recebeu (outra Maria, ou alguém que sabe o nome)
     cria conta com ele. Telefone e nome batem; o que segura a ficha, e o
     pacote, é ela já ter dona. */
  const TEL_VELHO = '516' + n8;
  await dona.atualizar('clientes', fichaMaria.id, { telefone: TEL_VELHO });
  const intrusa = aba();
  await intrusa.criarConta({ email:`intrusa-${m}@t.com`, senha:'senhaqualquer1', nome:'Maria', telefone:'+55' + TEL_VELHO });
  const r = await intrusa.chamar('ligar_minha_ficha', { p_salao: SALAO });
  igual('número reciclado: a ficha (e o pacote) continua com a Maria',
    [r && r.telefone, r && r.ficha, await perfilDa(fichaMaria.id)], ['+55' + TEL_VELHO, null, donaDaFicha]);
  igual('e a intrusa não enxerga os horários dela', await intrusa.chamar('meus_agendamentos_da_conta', {}), []);
  igual('nem o pacote', await intrusa.chamar('meus_pacotes', { p_salao: SALAO }), []);
  await dona.atualizar('clientes', fichaMaria.id, { telefone: TEL_MARIA });
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('12b. Criar conta com um WhatsApp que já é de outra conta');
{
  const { p, ctx } = await aparelho();
  await p.evaluate(() => abrirConta('criar')); await p.waitForTimeout(200);
  await p.fill('#cNome', 'Maria'); await p.fill('#cTel', masc(TEL_MARIA));
  await p.fill('#cEmail', `esqueci-${m}@t.com`); await p.fill('#cSenha', 'senhanova12');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  const t = await p.evaluate(() => ({ tela, titulo: document.getElementById('contaTitulo').textContent,
    email: document.getElementById('cEmail').value }));
  verdade('avisa que o WhatsApp é de outra conta, e oferece entrar com ela',
    /este WhatsApp já está em outra conta/.test(await aviso(p)) && t.tela === 'conta' && t.titulo === 'Entrar' && t.email === '',
    JSON.stringify(t) + ' ' + await aviso(p));
  await p.fill('#cEmail', `maria-${m}@t.com`); await p.fill('#cSenha', 'senhaboa123');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('entrando com a conta antiga ali mesmo, o pacote aparece', [await p.evaluate(() => tela),
    await p.evaluate(() => sessao && sessao.email), (await atalhos(p)).includes('Meus pacotes')],
    ['capa', `maria-${m}@t.com`, true]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('13. A volta do e-mail de confirmação');
{
  const quem = aba();
  await quem.entrar({ email:`maria-${m}@t.com`, senha:'senhaboa123' });
  const s = quem.sessao();
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG + '#access_token=' + s.token
    + '&refresh_token=' + (s.refresh || '') + '&expires_in=3600&token_type=bearer&type=signup');
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(1500);
  igual('o link do e-mail entra na conta, e o token sai da barra de endereço',
    [await logada(p), await p.evaluate(() => location.hash), (await atalhos(p)).includes('Meus pacotes')], [true, '', true]);
  await ctx.close();

  const ctx2 = await nav.newContext({ viewport:{ width:390, height:880 } });
  const p2 = await ctx2.newPage();
  p2.on('pageerror', e => erros.push(e.message));
  await p2.goto(BASE + '/agendar.html?salao=' + SLUG + '#access_token=' + s.token + '&type=recovery');
  await p2.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p2.waitForTimeout(800);
  igual('o de "esqueci a senha" não vira login aqui', [await logada(p2), await p2.evaluate(() => location.hash)], [false, '']);
  await ctx2.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
