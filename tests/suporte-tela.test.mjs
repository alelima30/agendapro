/* ===========================================================================
   AgendaPro — o modo suporte, pela porta da frente

     bash tests/bancada/subir.sh
     PLAYWRIGHT=.../node_modules/playwright node tests/suporte-tela.test.mjs

   O pedido: "se o dono do salão precisa de suporte, como faço?" — e, entre
   abrir já editando ou só olhando, "só leitura com liberar edição".

   O suporte.test.sql prova a trava no banco. Aqui, o caminho de quem usa:
     · no admin, cada salão tem "Abrir painel", "Falar com o dono" e
       "Estender teste", e o teste vencido não aparece mais como "teste até";
     · o painel abre no salão do cliente, e SÓ nele, com a faixa no topo;
     · só leitura: mexer não grava, e a tela diz por quê;
     · "Liberar edição" pergunta antes, e aí grava — registrado;
     · "Sair do suporte" encerra a sessão e volta ao admin;
     · uma dona comum com o endereço do suporte na mão abre o painel dela.
   =========================================================================== */
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
const exigir = createRequire(import.meta.url);
const { chromium } = exigir(process.env.PLAYWRIGHT || 'playwright');
const CHROMIUM = process.env.CHROMIUM || '/opt/pw-browsers/chromium';
const BANCADA = process.env.BANCADA || 'http://127.0.0.1:8123';

let ok = 0, mau = 0;
const diz = (bom, msg, extra) => bom
  ? (ok++, console.log('  ✓ ' + msg))
  : (mau++, console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')));

const sql = q => execSync('psql -At -v ON_ERROR_STOP=1', { input: q, env: { ...process.env,
  PGHOST: process.env.PGHOST || '/tmp', PGPORT: process.env.PGPORT || '5444',
  PGUSER: process.env.PGUSER || 'postgres', PGDATABASE: process.env.PGBANCO || 'app' } }).toString().trim();

const marca = Date.now().toString(36) + Math.floor(Math.random() * 1000);
let seq = 0;
async function conta(nome){
  const tel = '+5511' + String(900000000 + (Date.now() + (++seq) * 7919) % 99999999);
  const j = await fetch(BANCADA + '/auth/v1/signup', { method: 'POST',
    headers: { apikey: 'k', 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: nome.toLowerCase().replace(/\W+/g, '') + '-' + marca + '@teste.com',
      password: 'senha-de-teste', data: { nome, telefone: tel } }) }).then(r => r.json());
  return { token: j.access_token, usuarioId: j.user.id, tel };
}
const rpc = (s, f, a) => fetch(BANCADA + '/rest/v1/rpc/' + f, { method: 'POST',
  headers: { apikey: 'k', Authorization: 'Bearer ' + s.token, 'Content-Type': 'application/json' },
  body: JSON.stringify(a || {}) }).then(r => r.json());

// A dona do salão que pede ajuda, um vizinho, e a plataforma.
const ju = await conta('Ju Barbosa');
const salaoJu = (await rpc(ju, 'criar_salao', { p_nome_salao: 'Studio Ju ' + marca, p_tipo: 'salao',
  p_telefone: '(11) 3333-' + String(1000 + seq), p_documento: null, p_origem: null }))[0].salao_id;
const ze = await conta('Ze Vizinho');
const salaoZe = (await rpc(ze, 'criar_salao', { p_nome_salao: 'Barbearia Ze ' + marca, p_tipo: 'barbearia',
  p_telefone: '(11) 3333-' + String(2000 + seq), p_documento: null, p_origem: null }))[0].salao_id;
const servJu = sql(`insert into servicos (salao_id, nome, duracao_min, preco) values ('${salaoJu}', 'Escova da Ju', 40, 80) returning id`).split('\n')[0];
sql(`insert into servicos (salao_id, nome, duracao_min, preco) values ('${salaoZe}', 'Corte do Ze', 30, 50)`);
// O teste da Ju venceu ontem: é o caso da etiqueta que mentia.
sql(`update assinaturas set trial_ate = current_date - 1 where salao_id = '${salaoJu}'`);
const plat = await conta('Plataforma');
sql(`update perfis set super_admin = true where id = '${plat.usuarioId}'`);
const precoJu = () => Number(sql(`select preco from servicos where id = '${servJu}'`));

const nav = await chromium.launch({ executablePath: CHROMIUM });
async function aba(sessao, url, largura = 1280){
  const ctx = await nav.newContext({ viewport: { width: largura, height: 900 } });
  await ctx.addInitScript(([base, s]) => {
    window.AGENDAPRO = { url: base, chave: 'k', ambiente: 'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s));
  }, [BANCADA, sessao]);
  const p = await ctx.newPage();
  p.erros = []; p.dialogos = []; p.responder = null;
  p.on('pageerror', e => p.erros.push(e.message));
  p.on('dialog', d => {
    p.dialogos.push(d.message());
    if(d.type() === 'prompt') d.accept(p.responder == null ? undefined : String(p.responder));
    else if(d.type() === 'confirm') d.accept();
    else d.dismiss();
  });
  await p.goto(BANCADA + '/' + url);
  return p;
}
const linhaDoJu = '#corpo tr:has-text("Studio Ju ' + marca + '")';

console.log('\nNo admin');
{
  const p = await aba(plat, 'admin.html');
  await p.waitForSelector(linhaDoJu, { timeout: 15000 });
  const href = await p.getAttribute(linhaDoJu + ' a:has-text("Abrir painel")', 'href');
  diz(href === 'app.html?suporte=' + salaoJu, 'cada salão tem "Abrir painel", no endereço do modo suporte', href);
  diz(await p.getAttribute(linhaDoJu + ' a:has-text("Abrir painel")', 'target') === '_blank',
    'e abre noutra aba, sem fechar o admin');
  const etq = (await p.textContent(linhaDoJu + ' .etq')).trim();
  diz(/teste venceu/.test(etq) && !/teste até/.test(etq),
    'o teste vencido aparece como vencido (antes: "teste até" com a data passada)', etq);

  await p.click(linhaDoJu + ' button:has-text("Falar com o dono")');
  await p.waitForSelector(linhaDoJu + ' .contato', { timeout: 8000 });
  const contato = await p.textContent(linhaDoJu + ' .contato');
  const zap = await p.getAttribute(linhaDoJu + ' .contato a:has-text("WhatsApp")', 'href');
  diz(/Ju Barbosa/.test(contato) && zap === 'https://wa.me/' + ju.tel.replace(/\D/g, ''),
    '"Falar com o dono" traz o nome e o WhatsApp de quem é dono', contato + ' · ' + zap);

  p.responder = 10;
  await p.click(linhaDoJu + ' button:has-text("Estender teste")');
  await p.waitForTimeout(1200);
  const ate = sql(`select status || ' ' || (trial_ate - current_date) from assinaturas where salao_id = '${salaoJu}'`);
  diz(ate === 'trial 10', '"Estender teste" pergunta os dias e devolve o salão ao teste', ate);
  await p.waitForSelector(linhaDoJu + ' .etq', { timeout: 8000 });
  diz(/teste até/.test(await p.textContent(linhaDoJu + ' .etq')), 'e a etiqueta volta a dizer "teste até"');
  diz(p.erros.length === 0, 'sem erro de JavaScript no admin', p.erros.join(' | '));
  await p.context().close();
}

console.log('\nO painel do cliente, em modo suporte');
{
  const p = await aba(plat, 'app.html?suporte=' + salaoJu);
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && bd.saloes && salaoAtual, null, { timeout: 15000 });
  await p.waitForTimeout(600);
  const r = await p.evaluate(() => ({
    saloes: bd.saloes.map(s => s.id), atual: salaoAtual,
    servicos: bd.servicos.map(s => s.nome), perfis: bd.perfis.map(x => x.nome),
    faixa: (document.getElementById('faixaSuporte') || {}).textContent || '',
    visivel: (document.getElementById('faixaSuporte') || {}).offsetParent !== null,
    titulo: document.title,
  }));
  diz(r.atual === salaoJu && r.saloes.length === 1 && r.saloes[0] === salaoJu,
    'o painel abre no salão da Ju — e só nele', JSON.stringify(r.saloes));
  diz(r.servicos.includes('Escova da Ju') && !r.servicos.includes('Corte do Ze'),
    'com os dados dela, e nada da casa do vizinho', JSON.stringify(r.servicos));
  diz(!r.perfis.includes('Ze Vizinho'), 'nem o perfil de quem não é da casa', JSON.stringify(r.perfis));
  diz(r.visivel && /Modo suporte/.test(r.faixa) && r.faixa.includes('Studio Ju ' + marca) && /só leitura/.test(r.faixa),
    'a faixa no topo diz: modo suporte, o nome do salão, só leitura', r.faixa.trim().slice(0, 140));
  diz(/^Suporte · /.test(r.titulo), 'e a aba do navegador também', r.titulo);
  diz(!p.dialogos.length, 'abrir não dispara aviso nenhum (nada foi gravado na abertura)', p.dialogos.join(' | '));

  // Mexer sem liberar: o banco recusa, a tela explica e volta ao que é.
  await p.evaluate(async id => {
    bd.servicos.find(s => s.id === id).preco = 1;
    await salvar();
  }, servJu);
  await p.waitForTimeout(1200);
  diz(precoJu() === 80, 'só leitura: mudar o preço não grava no banco', 'preço ' + precoJu());
  diz(p.dialogos.some(d => /Modo suporte: só leitura/.test(d) && /Liberar edição/.test(d)) &&
      !p.dialogos.some(d => /NÃO consegui salvar/.test(d)),
    'e a tela diz por quê, e o que fazer — não "NÃO consegui salvar"', p.dialogos.join(' | '));
  diz(await p.evaluate(id => Number(bd.servicos.find(s => s.id === id).preco), servJu) === 80,
    'a tela volta ao preço de verdade');

  // As ações da conta errada saem do caminho.
  p.dialogos.length = 0;
  await p.evaluate(() => assinar('individual', 'pix'));
  diz(p.dialogos.some(d => /modo suporte não dá para assinar/i.test(d)),
    'assinar plano pelo salão do cliente é recusado na tela', p.dialogos.join(' | '));
  await p.evaluate(() => irPara('conta'));
  await p.waitForTimeout(300);
  diz(await p.evaluate(() => !document.getElementById('btExcluirConta')),
    '"Excluir minha conta" não aparece (excluiria a conta da plataforma)');

  // Liberar edição.
  p.dialogos.length = 0;
  await p.click('#faixaSuporte button:has-text("Liberar edição")');
  await p.waitForTimeout(800);
  const faixa2 = await p.evaluate(() => ({ txt: document.getElementById('faixaSuporte').textContent,
    editando: document.getElementById('faixaSuporte').classList.contains('editando') }));
  diz(p.dialogos.some(d => /Liberar edição em/.test(d) && /registrado/.test(d)),
    '"Liberar edição" pergunta antes, dizendo que fica registrado', p.dialogos.join(' | '));
  diz(faixa2.editando && /edição liberada até \d{2}:\d{2}/.test(faixa2.txt),
    'e a faixa muda: edição liberada, até que horas', faixa2.txt.trim().slice(0, 140));
  p.dialogos.length = 0;
  await p.evaluate(async id => {
    bd.servicos.find(s => s.id === id).preco = 85;
    await salvar();
  }, servJu);
  await p.waitForTimeout(1200);
  diz(precoJu() === 85 && !p.dialogos.length, 'com a edição liberada, grava', 'preço ' + precoJu() + ' · ' + p.dialogos.join(' | '));
  const reg = sql(`select count(*) from suporte_alteracoes x join suporte_acessos a on a.id = x.acesso_id
    where a.salao_id = '${salaoJu}' and x.tabela = 'servicos' and (x.antes->>'preco')::numeric = 80 and (x.depois->>'preco')::numeric = 85`);
  diz(reg === '1', 'e fica registrado: o antes e o depois', 'registros: ' + reg);

  // Sair do suporte.
  await Promise.all([
    p.waitForURL(/admin\.html/, { timeout: 8000 }).catch(() => {}),
    p.click('#faixaSuporte button:has-text("Sair do suporte")'),
  ]);
  diz(/admin\.html/.test(p.url()), '"Sair do suporte" volta ao admin', p.url());
  const aberto = sql(`select count(*) from suporte_acessos where salao_id = '${salaoJu}' and encerrado_em is null`);
  diz(aberto === '0', 'e a sessão de suporte fica encerrada no banco', 'abertas: ' + aberto);
  diz(p.erros.length === 0, 'sem erro de JavaScript no painel', p.erros.join(' | '));

  // O admin, de volta, mostra o acesso.
  await p.waitForSelector('#corpo h2:has-text("Acessos de suporte")', { timeout: 10000 });
  const acesso = await p.textContent('#corpo h2:has-text("Acessos de suporte") + .rolo tbody tr:first-child');
  diz(acesso.includes('Studio Ju ' + marca) && /liberada às/.test(acesso) && /encerrado/.test(acesso),
    'o admin lista o acesso: salão, edição liberada, encerrado', acesso.replace(/\s+/g, ' ').trim());
  await p.context().close();
}

console.log('\nUma dona comum com o endereço do suporte');
{
  const p = await aba(ju, 'app.html?suporte=' + salaoZe);
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && bd.saloes && salaoAtual, null, { timeout: 15000 });
  await p.waitForTimeout(500);
  const r = await p.evaluate(() => ({ atual: salaoAtual, servicos: bd.servicos.map(s => s.nome),
    faixa: document.getElementById('faixaSuporte').style.display }));
  diz(r.atual === salaoJu && r.servicos.includes('Escova da Ju') && !r.servicos.includes('Corte do Ze'),
    'abre o painel DELA, como sempre — o banco recusou o suporte', JSON.stringify(r));
  diz(r.faixa === 'none', 'sem faixa de suporte');
  diz(!p.dialogos.length && p.erros.length === 0, 'sem aviso nem erro na cara dela', p.dialogos.concat(p.erros).join(' | '));
  const abertoZe = sql(`select count(*) from suporte_acessos where salao_id = '${salaoZe}'`);
  diz(abertoZe === '0', 'e nenhuma sessão de suporte foi aberta na casa do vizinho', abertoZe);
  await p.context().close();
}

await nav.close();
console.log(`\n${ok} ok, ${mau} falha(s)`);
process.exit(mau ? 1 : 0);
