/* ===========================================================================
   AgendaPro — cupom de desconto

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     python3 -m http.server 8099 --directory .   (a parte da demonstração)
     PLAYWRIGHT=/caminho/node_modules/playwright node tests/cupons.test.mjs

   O pedido: "Temos que colocar cupom de desconto" — no agendamento pelo link
   e nos produtos da loja do link, com limite de usos, só alguns serviços,
   % ou valor fixo, e validade.

   ── O QUE ESTE ARQUIVO MEDE ────────────────────────────────────────────────
     1. a conta, no banco: %, valor, serviços, validade, desligado, onde vale,
        produtos — e que o código vale digitado de qualquer jeito;
     2. o agendar() com cupom: grava o desconto e o valor já descontado; 1 por
        cliente (também com +55); limite total, e o uso que VOLTA quando o
        horário é desmarcado; código errado não marca pelo preço cheio;
     3. a loja: o uso registrado e o limite;
     4. o que é fechado: a tabela, a conta, a ficha, e a prévia sem telefone;
     5. a comanda nasce com o desconto (sem comanda e no painel);
     6. o painel: a lista, criar pelo formulário, código repetido, desligar,
        o detalhe do agendamento;
     7. o link: aplicar, código errado, total, marcar com o cupom, e o cupom
        recusado na hora de marcar;
     8. a loja do link: aplicar, o carrinho que muda, a mensagem com o cupom
        e o uso registrado uma vez só;
     9. as cores saem do tema; salão sem cupom não mostra o campo;
    10. nenhum erro de JavaScript.
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
// A demonstração não abre pela bancada (lá a página é da nuvem): servidor
// estático, como nos outros testes de demonstração.
//   python3 -m http.server 8099 --directory .
const ESTATICO = process.env.BASE || 'http://127.0.0.1:8099/';

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
const um = r => Array.isArray(r) ? r[0] : r;
async function falha(fn){ try{ await fn(); return null; }catch(e){ return e.message || String(e); } }

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
const n7 = String(Date.now() % 10000000).padStart(7, '0');
const tel = k => '51' + k + n7;                 // 11 dígitos, um por pessoa
const masc = d => `(${d.slice(0,2)}) ${d.slice(2,7)}-${d.slice(7)}`;
const diaMais = d => { const x = new Date(); x.setDate(x.getDate() + d); return x.toISOString().slice(0, 10); };

const dona = aba();
await dona.criarConta({ email:`cp-${m}@teste.com`, senha:'minhasenhaboa',
  nome:'Ju Barbosa', telefone:'+5511' + (900000000 + (Date.now() % 89999999)) });
const cr = await dona.chamar('criar_salao', { p_nome_salao:'Salão Megatop',
  p_tipo:'salao', p_telefone:'(11) 98111-3251', p_documento:null, p_origem:null });
const SALAO = cr[0].salao_id, SLUG = cr[0].slug;
const prof = (await dona.lista('profissionais', { salaoId: SALAO }))[0];
for(let i = 0; i <= 6; i++)
  await dona.inserir('jornadas', { profissionalId: prof.id, diaSemana:i, inicio:'08:00', fim:'19:00' });
const escova = await dona.inserir('servicos', { salaoId: SALAO, nome:'Escova', duracaoMin:30, intervaloMin:0,
  preco:50, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const corte = await dona.inserir('servicos', { salaoId: SALAO, nome:'Corte', duracaoMin:30, intervaloMin:0,
  preco:80, ativo:true, aceitaOnline:true, categoria:'Cabelo' });
const shampoo = await dona.inserir('produtos', { salaoId: SALAO, nome:'Shampoo', preco:40, ativo:true,
  vendaOnline:true, precoVisivel:true, estoque:20 });
const SEMANA = [0,1,2,3,4,5,6].reduce((o, d) => (o[d] = [['00:00','00:00']], o), {});
// Sem comanda: o atendimento concluído vira comanda sozinho (28) — é por ela
// que se vê o desconto chegar ao caixa.
await dona.atualizar('saloes', SALAO, { cfg:{ diasLiberados:30, cor:'#B8356B', funcionamento: SEMANA,
  confirmaAuto:true, usaComanda:false } });

const cupom = (codigo, x) => dona.inserir('cupons', Object.assign({ salaoId: SALAO, codigo, tipo:'pct',
  valor:10, valeAgendamento:true, valeProdutos:false, umPorCliente:true, ativo:true }, x));
const BEM     = await cupom(' bemvinda10 ', {});
const CORTE15 = await cupom('CORTE15',  { tipo:'valor', valor:15, servicos:[corte.id] });
await cupom('VENCIDO',  { fim: diaMais(-1) });
await cupom('FUTURO',   { inicio: diaMais(5) });
await cupom('DESLIGADO',{ ativo:false });
const LOJA20  = await cupom('LOJA20',   { valor:20, valeAgendamento:false, valeProdutos:true, limiteTotal:1, umPorCliente:false });
const DOIS    = await cupom('DOIS',     { valor:50, limiteTotal:2, umPorCliente:false });
const LOJA10  = await cupom('LOJA10',   { valor:10, valeAgendamento:false, valeProdutos:true, umPorCliente:false });

const anon = aba();
/* Cupom NA LOJA só com a cliente dentro da conta (decisão do dono do produto,
   depois do caça-bug): quem confere o cálculo da loja aqui é uma conta. */
const compradora = aba();
await compradora.criarConta({ email:`cp-loja-${m}@teste.com`, senha:'senhadaloja1',
  nome:'Lu Compras', telefone:'+5511' + (910000000 + (Date.now() % 89999999)) });
async function vaga(d, servicos){
  const h = await anon.chamar('horarios_livres', { p_profissional: prof.id, p_data: diaMais(d), p_servicos: servicos });
  return (Array.isArray(h) ? h : []).map(x => typeof x === 'string' ? x : Object.values(x)[0])[0];
}
async function marcar(nome, telefone, d, servicos, cupomTxt){
  const r = await anon.chamar('agendar', Object.assign({ p_profissional: prof.id, p_inicio: await vaga(d, servicos),
    p_servicos: servicos, p_nome: nome, p_telefone: telefone }, cupomTxt ? { p_cupom: cupomTxt } : {}));
  return um(r);
}
const agendamentos = () => dona.lista('agendamentos', { salaoId: SALAO });
const conferir = (codigo, x) => anon.chamar('conferir_cupom', Object.assign({ p_salao: SALAO, p_codigo: codigo,
  p_origem:'agendamento', p_servicos:[escova.id], p_profissional: prof.id }, x)).then(um);

/* ══════════════════════════════════════════════════════════════════════════ */
secao('1. A conta, no banco');
igual('o código é guardado em maiúsculas e sem espaço', BEM.codigo, 'BEMVINDA10');
{
  const r = await conferir('bemvinda10');
  igual('10% numa escova de R$ 50: R$ 5, com o rótulo "10%"', [r.ok, Number(r.desconto), r.rotulo], [true, 5, '10%']);
  igual('digitado com espaço e minúscula, vale igual', (await conferir(' BemVinda10 ')).ok, true);
  const c1 = await conferir('CORTE15');
  igual('o de um serviço só não vale para outro', [c1.ok, c1.motivo], [false, 'Este cupom não vale para os serviços escolhidos.']);
  const c2 = await conferir('CORTE15', { p_servicos:[escova.id, corte.id] });
  igual('e com ele na escolha desconta o valor fixo, com vírgula', [c2.ok, Number(c2.desconto), c2.rotulo], [true, 15, 'R$ 15,00']);
  verdade('vencido diz quando venceu', /^Este cupom venceu em \d\d\/\d\d\/\d{4}\.$/.test((await conferir('VENCIDO')).motivo));
  verdade('o que ainda não começou diz quando começa', /^Este cupom começa a valer em \d\d\/\d\d\/\d{4}\.$/.test((await conferir('FUTURO')).motivo));
  const des = await conferir('DESLIGADO'), inex = await conferir('NAOEXISTE');
  igual('desligado responde igual a inexistente (não revela quais códigos existem)',
    [des.motivo, inex.motivo], ['Cupom não encontrado. Confira as letras e os números.', 'Cupom não encontrado. Confira as letras e os números.']);
  igual('o da loja não vale no agendamento', (await conferir('LOJA20')).motivo, 'Este cupom vale só para os produtos da loja.');
  igual('o do agendamento não vale na loja',
    (await compradora.chamar('conferir_cupom', { p_salao: SALAO, p_codigo:'BEMVINDA10', p_origem:'produtos',
      p_itens:[{ id: shampoo.id, qtd: 1 }] }).then(um)).motivo, 'Este cupom vale só para agendamento.');
  const semConta = await conferir('LOJA20', { p_origem:'produtos', p_itens:[{ id: shampoo.id, qtd: 2 }] });
  igual('na loja, sem conta, a prévia pede para entrar', [semConta.ok, semConta.entrar, semConta.motivo],
    [false, true, 'Entre na sua conta para usar o cupom na loja.']);
  const naLoja = (codigo, itens) => compradora.chamar('conferir_cupom', { p_salao: SALAO, p_codigo: codigo,
    p_origem:'produtos', p_itens: itens }).then(um);
  const lj = await naLoja('LOJA20', [{ id: shampoo.id, qtd: 2 }]);
  igual('logada: 20% em dois shampoos de R$ 40: R$ 16 (o preço sai do cadastro)', [lj.ok, Number(lj.desconto)], [true, 16]);
  igual('item inventado não vira base de desconto',
    (await naLoja('LOJA20', [{ id: corte.id, qtd: 5 }])).motivo,
    'Escolha um produto com preço antes de usar o cupom.');
  igual('o salão tem cupom valendo, nos dois lugares', um(await anon.chamar('salao_tem_cupom', { p_salao: SALAO })),
    { produtos: true, agendamento: true });
  igual('e um salão sem cupom não tem', um(await anon.chamar('salao_tem_cupom', { p_salao: '00000000-0000-4000-8000-000000000000' })),
    { produtos: false, agendamento: false });
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('2. O agendar() com cupom');
const TEL_ANA = tel('91'), TEL_BIA = tel('92'), TEL_CAU = tel('93'), TEL_DEB = tel('94'), TEL_EVA = tel('95');
let AG_ANA, AG_CAU;
{
  const f = await marcar('Ana Lima', TEL_ANA, 1, [escova.id], 'bemvinda10');
  AG_ANA = f.id;
  const a = (await agendamentos()).find(x => x.id === f.id);
  igual('grava o desconto, o cupom e o valor já descontado (R$ 45)',
    [Number(a.desconto), a.cupomId, Number(a.valorPrevisto), Number(f.valor)], [5, BEM.id, 45, 45]);

  const antes = (await agendamentos()).length;
  igual('a mesma cliente não usa duas vezes',
    await falha(() => marcar('Ana Lima', TEL_ANA, 2, [escova.id], 'BEMVINDA10')), 'Cupom: Você já usou este cupom.');
  igual('nem com +55 na frente e outro nome (vale pelo WhatsApp)',
    await falha(() => marcar('Aninha', '+55 ' + TEL_ANA, 2, [escova.id], 'BEMVINDA10')), 'Cupom: Você já usou este cupom.');
  igual('código errado não marca pelo preço cheio: recusa',
    await falha(() => marcar('Ana Lima', TEL_ANA, 2, [escova.id], 'INVENTADO')), 'Cupom: Cupom não encontrado. Confira as letras e os números.');
  igual('e nenhuma das três recusas deixou horário marcado', (await agendamentos()).length, antes);

  const b = await marcar('Bia Souza', TEL_BIA, 2, [escova.id], 'DOIS');
  AG_CAU = (await marcar('Cau Reis', TEL_CAU, 2, [escova.id], 'DOIS')).id;
  igual('limite de 2: o terceiro uso é recusado',
    await falha(() => marcar('Deb Melo', TEL_DEB, 3, [escova.id], 'DOIS')), 'Cupom: Este cupom já foi usado o máximo de vezes.');
  await dona.atualizar('agendamentos', b.id, { status:'cancelado' });
  // Recusa aqui é o defeito medido: vira ✗ com o motivo, e não um tombo.
  let d = null, porQue = '';
  try{ d = await marcar('Deb Melo', TEL_DEB, 3, [escova.id], 'DOIS'); }catch(e){ porQue = e.message; }
  igual('desmarcado um horário, o uso volta para o cupom', d ? Number(d.valor) : porQue, 25);

  const sem = await marcar('Eva Dias', TEL_EVA, 3, [escova.id]);
  igual('sem cupom, nada muda: preço cheio e desconto zero',
    [Number(sem.valor), Number((await agendamentos()).find(x => x.id === sem.id).desconto)], [50, 0]);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('3. A loja: o uso registrado e o limite');
{
  const r0 = um(await anon.chamar('usar_cupom_no_pedido', { p_salao: SALAO, p_codigo:'loja20', p_itens:[{ id: shampoo.id, qtd: 2 }] }));
  igual('sem conta, o pedido com cupom é recusado (e não gasta o cupom)', [r0.ok, r0.entrar], [false, true]);
  const r1 = um(await compradora.chamar('usar_cupom_no_pedido', { p_salao: SALAO, p_codigo:'loja20', p_itens:[{ id: shampoo.id, qtd: 2 }] }));
  igual('logada, o pedido com cupom registra o uso e devolve o desconto do banco', [r1.ok, Number(r1.desconto), r1.codigo], [true, 16, 'LOJA20']);
  const outra = aba();
  await outra.criarConta({ email:`cp-loja2-${m}@teste.com`, senha:'senhadaloja2',
    nome:'Mel Compras', telefone:'+5511' + (920000000 + (Date.now() % 79999999)) });
  const r2 = um(await outra.chamar('usar_cupom_no_pedido', { p_salao: SALAO, p_codigo:'LOJA20', p_itens:[{ id: shampoo.id, qtd: 1 }] }));
  igual('limite de 1: o pedido de outra conta é recusado', [r2.ok, r2.motivo], [false, 'Este cupom já foi usado o máximo de vezes.']);
  const usos = um(await dona.chamar('usos_dos_cupons', { p_salao: SALAO }));
  igual('a contagem do painel: BEMVINDA10 1, DOIS 2 (o desmarcado não conta), LOJA20 1',
    [usos[BEM.id], usos[DOIS.id], usos[LOJA20.id]], [1, 2, 1]);
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('4. O que é fechado');
{
  const lidos = await anon.lista('cupons', { salaoId: SALAO }).catch(() => []);
  igual('sem login, ninguém lê a lista de cupons', (lidos || []).length, 0);
  verdade('a conta (cupom_calcular) não responde por fora, nem para a dona',
    !!(await falha(() => anon.chamar('cupom_calcular', { p_salao: SALAO, p_codigo:'BEMVINDA10', p_origem:'agendamento',
      p_servicos:[escova.id], p_profissional: prof.id, p_inicio: null, p_itens: null, p_tel: null, p_cliente: null })))
    && !!(await falha(() => dona.chamar('cupom_calcular', { p_salao: SALAO, p_codigo:'BEMVINDA10', p_origem:'agendamento',
      p_servicos:[escova.id], p_profissional: prof.id, p_inicio: null, p_itens: null, p_tel: null, p_cliente: null }))));
  verdade('a ficha de quem está logado (cupom_minha_ficha) também não',
    !!(await falha(() => anon.chamar('cupom_minha_ficha', { p_salao: SALAO }))));
  verdade('a prévia não aceita telefone: ninguém pergunta "o número tal já usou?"',
    !!(await falha(() => anon.chamar('conferir_cupom', { p_salao: SALAO, p_codigo:'BEMVINDA10', p_origem:'agendamento',
      p_servicos:[escova.id], p_telefone: TEL_ANA }))));
  verdade('nem o pedido da loja',
    !!(await falha(() => anon.chamar('usar_cupom_no_pedido', { p_salao: SALAO, p_codigo:'LOJA10',
      p_itens:[{ id: shampoo.id, qtd: 1 }], p_telefone: TEL_ANA }))));
  verdade('e a contagem de usos não sai para quem não é do salão',
    !!(await falha(() => anon.chamar('usos_dos_cupons', { p_salao: SALAO }))));
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('5. A comanda nasce com o desconto');
{
  const porQue = await falha(() => dona.atualizar('agendamentos', AG_ANA, { status:'concluido' }));
  const c = (await dona.lista('comandas', { salaoId: SALAO })).find(x => x.agendamentoId === AG_ANA);
  igual('sem comanda: a automática leva o desconto e o motivo',
    porQue || (c && [Number(c.desconto), c.descontoMotivo]), [5, 'Cupom BEMVINDA10']);
}

const nav = await chromium.launch({ executablePath: CHROMIUM });
const erros = [];

/* ══════════════════════════════════════════════════════════════════════════ */
secao('6. O painel');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  const dialogos = [];
  p.on('pageerror', e => erros.push('painel: ' + e.message));
  p.on('dialog', d => { dialogos.push(d.message()); d.type() === 'confirm' ? d.accept() : d.dismiss(); });
  await p.addInitScript(([b, s]) => { window.AGENDAPRO = { url:b, chave:'k', ambiente:'bancada' };
    localStorage.setItem('agendapro.sessao', JSON.stringify(s)); }, [BASE, dona.sessao()]);
  await p.goto(BASE + '/app.html');
  const chegou = await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.cupons) && bd.cupons.length >= 8,
    null, { timeout: 20000 }).then(() => true, () => false);
  verdade('o painel recebe os cupons do banco', chegou, 'bd.cupons não chegou com os 8 cupons do salão');
  await p.waitForTimeout(800);
  await p.evaluate(() => { try{ fecharModal(); }catch(e){} if(typeof pdFechar === 'function') pdFechar(true); });
  verdade('"Cupons" está no menu, em Cadastros', await p.evaluate(() =>
    !!document.querySelector('#abas .aba[data-chave="cupons"]')));
  await p.evaluate(() => irPara('cupons'));
  await p.waitForFunction(() => /2 usos/.test((document.querySelector('[data-cupom] .cupom-usos') || {}).textContent || '')
    || [...document.querySelectorAll('.cupom-usos')].some(x => /usos?/.test(x.textContent)), null, { timeout: 8000 }).catch(() => {});
  const cartao = cod => p.evaluate(c => {
    const el = [...document.querySelectorAll('#listaCupons .cupom-cartao')].find(x => x.querySelector('h3').textContent.trim().startsWith(c));
    return el ? el.innerText.replace(/\s+/g, ' ') : '';
  }, cod);
  const bem = await cartao('BEMVINDA10'), dois = await cartao('DOIS');
  verdade('BEMVINDA10: valendo, 10%, todos os serviços, 1 uso, 1 por cliente',
    /valendo/.test(bem) && /10% de desconto/.test(bem) && /Serviços: todos/.test(bem) && /1 uso/.test(bem) && /1 por cliente/.test(bem), bem);
  verdade('DOIS: 2 usos de 2, esgotado', /esgotado/.test(dois) && /2 usos · limite de 2/.test(dois), dois);
  verdade('CORTE15 mostra o valor fixo e o serviço', /R\$\s?15,00 de desconto/.test(await cartao('CORTE15')) && /Serviços: Corte/.test(await cartao('CORTE15')));
  igual('vencido, ainda não começou, desligado',
    [/vencido/.test(await cartao('VENCIDO')), /ainda não começou/.test(await cartao('FUTURO')), /desligado/.test(await cartao('DESLIGADO'))], [true, true, true]);
  verdade('o da loja diz que vale na loja', /vale na loja/.test(await cartao('LOJA20')));

  // Criar pelo formulário, digitando como o dono digita.
  await p.click('#btNovoCupom'); await p.waitForTimeout(300);
  await p.type('#cpCodigo', 'natal 15!');
  igual('o código vira maiúsculas e perde o que não pode', await p.inputValue('#cpCodigo'), 'NATAL15');
  await p.selectOption('#cpTipo', 'valor');
  igual('com valor fixo o rótulo diz R$', await p.textContent('#cpValorRot'), 'Quanto (R$)');
  await p.fill('#cpValor', '15');
  await p.check(`#cpServicos input[value="${corte.id}"]`);
  await p.check('#cpProd');
  await p.fill('#cpInicioTxt', '01/12/2026'); await p.fill('#cpFimTxt', '31/12/2026');
  await p.fill('#cpLimite', '30');
  await p.uncheck('#cpUmPor');
  await p.evaluate(() => salvarCupom(null)); await p.waitForTimeout(2500);
  const natal = (await dona.lista('cupons', { salaoId: SALAO })).find(x => x.codigo === 'NATAL15');
  igual('grava no banco: R$ 15, Corte, agendamento e loja, 01/12 a 31/12, limite 30, sem "1 por cliente"',
    natal && [natal.tipo, Number(natal.valor), natal.servicos, natal.valeAgendamento, natal.valeProdutos,
              natal.inicio, natal.fim, natal.limiteTotal, natal.umPorCliente, natal.ativo],
    ['valor', 15, [corte.id], true, true, '2026-12-01', '2026-12-31', 30, false, true]);

  // Código repetido: avisa, não grava.
  await p.click('#btNovoCupom'); await p.waitForTimeout(300);
  await p.fill('#cpCodigo', 'BEMVINDA10'); await p.fill('#cpValor', '5');
  dialogos.length = 0;
  await p.evaluate(() => salvarCupom(null)); await p.waitForTimeout(400);
  verdade('código repetido: avisa e não grava', /Já existe um cupom BEMVINDA10/.test(dialogos.join(' | ')), dialogos.join(' | '));
  await p.evaluate(() => fecharModal());

  // Desligar.
  await p.evaluate(id => abrirCupom(id), natal.id); await p.waitForTimeout(300);
  igual('editar abre com o que está gravado', [await p.inputValue('#cpCodigo'), await p.inputValue('#cpInicioTxt'),
    await p.isChecked('#cpProd'), await p.isChecked('#cpUmPor')], ['NATAL15', '01/12/2026', true, false]);
  await p.uncheck('#cpAtivo');
  await p.evaluate(id => salvarCupom(id), natal.id); await p.waitForTimeout(2500);
  igual('desmarcar "Cupom ativo" desliga no banco',
    (await dona.lista('cupons', { salaoId: SALAO })).find(x => x.id === natal.id).ativo, false);

  // Data pela metade não passa.
  await p.click('#btNovoCupom'); await p.waitForTimeout(300);
  await p.fill('#cpCodigo', 'METADE'); await p.fill('#cpValor', '5'); await p.fill('#cpFimTxt', '31/12');
  dialogos.length = 0;
  await p.evaluate(() => salvarCupom(null)); await p.waitForTimeout(400);
  verdade('data pela metade: pede para conferir, e não grava', /Confira as datas/.test(dialogos.join(' | '))
    && !(await dona.lista('cupons', { salaoId: SALAO })).some(x => x.codigo === 'METADE'), dialogos.join(' | '));
  await p.evaluate(() => fecharModal());

  // O detalhe do agendamento e o total.
  await p.evaluate(() => irPara('agenda')); await p.waitForTimeout(400);
  const det = await p.evaluate(id => { abrirDetalhe(id);
    const a = bd.agendamentos.find(x => x.id === id);
    return { txt: document.getElementById('modalCorpo').innerText.replace(/\s+/g, ' '), total: totalDe(a) }; }, AG_CAU);
  verdade('o detalhe mostra o cupom e o desconto', /Cupom DOIS · − R\$\s?25,00/.test(det.txt), det.txt);
  igual('e o total do horário já sai descontado', det.total, 25);
  await p.evaluate(() => fecharModal());

  // A comanda aberta pelo painel leva o desconto.
  const cmd = await p.evaluate(async id => { await comandaDoAgendamento(id);
    const c = bd.comandas.find(x => x.agendamentoId === id); try{ fecharModal(); }catch(e){}
    return c ? [c.desconto, c.descontoMotivo] : null; }, AG_CAU);
  igual('a comanda que o painel abre nasce com o desconto do cupom', cmd, [25, 'Cupom DOIS']);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('7. O link: o cupom na tela de confirmar');
async function ateConfirmar(nome, telefone){
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('link: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(700);
  await p.click('.boas-cta'); await p.waitForTimeout(300);
  await p.click('#listaServicos .sv-cartao:has-text("Escova")'); await p.click('#btPrincipal'); await p.waitForTimeout(300);
  await p.click('#quemMim'); await p.waitForTimeout(500);
  if(await p.evaluate(() => tela === 'prof')) await p.click('#btPrincipal');
  await p.waitForTimeout(1800);
  await p.locator('#listaDias .dia:not(.sem)').nth(6).click();
  await p.waitForFunction(() => document.querySelectorAll('#listaHoras .hora').length > 0, null, { timeout: 10000 });
  await p.click('#listaHoras .hora'); await p.click('#btPrincipal'); await p.waitForTimeout(800);
  await p.fill('#dNome', nome); await p.fill('#dTel', masc(telefone));
  if(await p.isVisible('#dNasc')) await p.fill('#dNasc', '1990-01-01');
  if(await p.isVisible('#dEmail')) await p.fill('#dEmail', `x-${telefone}@t.com`);
  await p.click('#btPrincipal'); await p.waitForTimeout(1200);
  return { ctx, p };
}
// O `toLocaleString` separa "R$" do número com espaço que não quebra.
const totalNaTela = p => p.evaluate(() => ((document.querySelector('#resumoFinal .cf-total b') || {}).textContent || '').replace(/\s/g, ' '));
async function aplicar(p, codigo, idTxt){
  const txt = idTxt || '#cupomAgendaTxt';
  if(!(await p.isVisible(txt))) await p.click((idTxt ? '#lojaCupomCaixa' : '#cfCupomCaixa') + ' summary');
  await p.fill(txt, codigo);
  await p.click((idTxt ? '#lojaCupomCaixa' : '#cfCupomCaixa') + ' .cupom-aplicar');
  await p.waitForTimeout(1200);
}
const TEL_FIA = tel('96');
{
  const { ctx, p } = await ateConfirmar('Fia Rocha', TEL_FIA);
  igual('na tela de confirmar aparece "Tem um cupom de desconto?", fechado',
    await p.evaluate(() => { const d = document.getElementById('cfCupomCaixa');
      return d ? [tela, /Tem um cupom de desconto\?/.test(d.innerText), d.open] : null; }), ['confirmar', true, false]);
  igual('antes do cupom, o total é o preço cheio', await totalNaTela(p), 'R$ 50,00');

  await aplicar(p, 'errado1');
  igual('código errado: diz o motivo, e o total não muda',
    [await p.evaluate(() => (document.querySelector('#cfCupom .cupom-erro') || {}).textContent || ''), await totalNaTela(p)],
    ['Cupom não encontrado. Confira as letras e os números.', 'R$ 50,00']);
  await aplicar(p, 'corte15');
  igual('o de outro serviço: diz que não vale para os escolhidos',
    await p.evaluate(() => (document.querySelector('#cfCupom .cupom-erro') || {}).textContent || ''),
    'Este cupom não vale para os serviços escolhidos.');

  await aplicar(p, ' bemvinda10');
  const okTxt = await p.evaluate(() => (document.getElementById('cupomAgendaOk') || {}).innerText || '');
  verdade('aceito: "Cupom BEMVINDA10 aplicado", 10%, − R$ 5,00',
    /Cupom BEMVINDA10 aplicado/.test(okTxt) && /10%/.test(okTxt) && /− R\$\s?5,00/.test(okTxt), okTxt);
  igual('o resumo ganha a linha do cupom e o total desce para R$ 45,00',
    [await totalNaTela(p), await p.evaluate(() => [...document.querySelectorAll('#resumoFinal .cf-linha small')].some(s => s.textContent === 'Cupom BEMVINDA10'))],
    ['R$ 45,00', true]);

  // Tirar e pôr de novo.
  await p.click('#cupomAgendaOk .link'); await p.waitForTimeout(300);
  igual('"Tirar" devolve o preço cheio', await totalNaTela(p), 'R$ 50,00');
  await aplicar(p, 'BEMVINDA10');

  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  igual('marca com o cupom', await p.evaluate(() => tela), 'pronto');
  const meu = (await agendamentos()).filter(x => x.status !== 'cancelado').find(x =>
    x.cupomId === BEM.id && x.id !== AG_ANA);
  igual('no banco: desconto de R$ 5 e valor de R$ 45', meu && [Number(meu.desconto), Number(meu.valorPrevisto)], [5, 45]);
  await ctx.close();
}
{
  // A mesma cliente, noutro aparelho: a prévia aceita (sem login ela não é
  // reconhecida), mas o agendar() recusa — e a tela explica e deixa marcar sem.
  const { ctx, p } = await ateConfirmar('Fia Rocha', TEL_FIA);
  await aplicar(p, 'BEMVINDA10');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  const r = await p.evaluate(() => ({ tela, aviso: document.getElementById('avisoConfirmar').innerText.replace(/\s+/g, ' '),
    erro: (document.querySelector('#cfCupom .cupom-erro') || {}).textContent || '' }));
  verdade('o cupom recusado na hora de marcar: fica na tela, diz o motivo, e nada foi marcado',
    r.tela === 'confirmar' && /O cupom não foi aceito/.test(r.aviso) && /Você já usou este cupom/.test(r.aviso)
    && r.erro === 'Você já usou este cupom.', JSON.stringify(r));
  igual('o total volta ao preço cheio', await totalNaTela(p), 'R$ 50,00');
  const antes = (await agendamentos()).length;
  await p.click('#btPrincipal'); await p.waitForTimeout(3500);
  igual('e o mesmo botão marca sem o cupom', [await p.evaluate(() => tela), (await agendamentos()).length], ['pronto', antes + 1]);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('8. A loja do link');
{
  const ctx = await nav.newContext({ viewport:{ width:390, height:880 }, isMobile:true, hasTouch:true });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('loja: ' + e.message));
  await p.goto(BASE + '/agendar.html?salao=' + SLUG);
  await p.waitForFunction(() => typeof tela !== 'undefined' && tela === 'capa', null, { timeout: 15000 });
  await p.waitForTimeout(900);
  await p.evaluate(id => { window.__abertos = []; window.open = u => { window.__abertos.push(u); return null; };
    mudarNoCarrinho(id, 1); irPara('loja'); }, shampoo.id);
  await p.waitForTimeout(500);
  verdade('com produto no carrinho, a loja oferece o cupom', await p.isVisible('#lojaCupomCaixa'));
  await p.click('#lojaCupomCaixa summary'); await p.waitForTimeout(200);
  igual('sem conta: a caixa pede para entrar, e não mostra o campo do código',
    await p.evaluate(() => [/entre na sua conta/i.test(document.getElementById('lojaCupomCaixa').innerText),
      !!document.getElementById('cupomLojaTxt'),
      [...document.querySelectorAll('#lojaCupomCaixa button')].map(b => b.textContent.trim())]),
    [true, false, ['Entrar', 'Criar conta']]);
  await p.click('#lojaCupomCaixa button:has-text("Criar conta")'); await p.waitForTimeout(300);
  await p.fill('#cNome', 'Gal Prado'); await p.fill('#cTel', masc(tel('97')));
  await p.fill('#cEmail', `gal-${m}@t.com`); await p.fill('#cSenha', 'senhadagal1');
  await p.click('#btPrincipal'); await p.waitForTimeout(2500);
  igual('criou a conta e voltou para a loja, com o carrinho e o campo do código',
    await p.evaluate(() => [tela, logada(), carrinho[Object.keys(carrinho)[0]], !!document.getElementById('cupomLojaTxt') || null]),
    ['loja', true, 1, true]);
  await aplicar(p, 'BEMVINDA10', '#cupomLojaTxt');
  igual('o do agendamento é recusado na loja', await p.evaluate(() => (document.querySelector('#listaProdutos .cupom-erro') || {}).textContent || ''),
    'Este cupom vale só para agendamento.');
  await aplicar(p, 'loja10', '#cupomLojaTxt');
  const resumo = () => p.evaluate(() => (document.querySelector('#listaProdutos .recado b') || {}).textContent || '');
  verdade('aceito: R$ 40 − 10% = R$ 36,00', /Cupom LOJA10 aplicado/.test(await p.evaluate(() => (document.getElementById('cupomLojaOk') || {}).innerText || ''))
    && /R\$\s?36,00/.test(await resumo()), await resumo());
  await p.evaluate(id => mudarNoCarrinho(id, 1), shampoo.id); await p.waitForTimeout(1500);
  verdade('o carrinho mudou: pergunta de novo, e o desconto acompanha (R$ 72,00)',
    /R\$\s?72,00/.test(await resumo()) && /− R\$\s?8,00/.test(await p.evaluate(() => (document.getElementById('cupomLojaOk') || {}).innerText || '')), await resumo());

  const usosAntes = um(await dona.chamar('usos_dos_cupons', { p_salao: SALAO }))[LOJA10.id] || 0;
  await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  const msg = decodeURIComponent((await p.evaluate(() => window.__abertos.slice(-1)[0] || '')).split('?text=')[1] || '');
  verdade('a mensagem do WhatsApp leva o cupom e o total com desconto',
    /Cupom LOJA10 \(10%\): desconto de R\$\s?8,00/.test(msg) && /Total estimado: R\$\s?72,00/.test(msg), msg);
  const usosDepois = um(await dona.chamar('usos_dos_cupons', { p_salao: SALAO }))[LOJA10.id] || 0;
  igual('e o uso ficou registrado no banco', usosDepois - usosAntes, 1);
  await p.click('#btPrincipal'); await p.waitForTimeout(1500);
  igual('mandar de novo o mesmo pedido não gasta outro uso',
    (um(await dona.chamar('usos_dos_cupons', { p_salao: SALAO }))[LOJA10.id] || 0) - usosAntes, 1);
  await p.click('#cupomLojaOk .link'); await p.waitForTimeout(300);
  await p.click('#btPrincipal'); await p.waitForTimeout(800);
  const semCupom = decodeURIComponent((await p.evaluate(() => window.__abertos.slice(-1)[0] || '')).split('?text=')[1] || '');
  verdade('sem o cupom, a mensagem é a de sempre', !/Cupom/.test(semCupom) && /Total estimado: R\$\s?80,00/.test(semCupom), semCupom);

  /* ══════════════════════════════════════════════════════════════════════ */
  secao('9. As cores saem do tema; salão sem cupom não mostra o campo');
  await aplicar(p, 'LOJA10', '#cupomLojaTxt');
  await p.evaluate(() => tirarCupomLoja()); await p.waitForTimeout(200);
  const cores = await p.evaluate(() => {
    const b = document.querySelector('#lojaCupomCaixa .cupom-aplicar');
    if(!b) return null;
    const raiz = getComputedStyle(document.documentElement);
    const prova = document.createElement('i'); document.body.appendChild(prova);
    prova.style.color = 'var(--acao)'; const acao = getComputedStyle(prova).color;
    prova.style.color = 'var(--acao-txt)'; const acaoTxt = getComputedStyle(prova).color;
    prova.remove();
    return [getComputedStyle(b).backgroundColor === acao, getComputedStyle(b).color === acaoTxt, !!raiz];
  });
  igual('o botão Aplicar usa a cor do botão do tema (--acao / --acao-txt)', cores, [true, true, true]);
  const css = fs.readFileSync(path.join(RAIZ, 'estilo.css'), 'utf8');
  const blocoCss = css.slice(css.indexOf('.cupom-linha'), css.indexOf('.cupom-ok-txt small'));
  verdade('e o CSS do cupom não tem cor escrita (só variáveis do tema)', blocoCss.length > 200
    && !/#[0-9a-f]{3,8}\b|rgba?\(|hsl\(/i.test(blocoCss), blocoCss.match(/#[0-9a-f]{3,8}\b|rgba?\(|hsl\(/i));
  igual('salão sem cupom valendo: o campo some da loja', await p.evaluate(() => {
    salaoTemCupom = { agendamento: false, produtos: false }; desenharLoja();
    return !!document.getElementById('lojaCupomCaixa'); }), false);
  await ctx.close();
}

/* ══════════════════════════════════════════════════════════════════════════ */
secao('10. Na demonstração');
{
  const ctx = await nav.newContext({ viewport:{ width:1280, height:900 } });
  const p = await ctx.newPage();
  p.on('pageerror', e => erros.push('demo: ' + e.message));
  await p.goto(ESTATICO + 'app.html?demo=1');
  await p.waitForFunction(() => typeof bd !== 'undefined' && bd && Array.isArray(bd.agendamentos), null, { timeout: 15000 });
  await p.waitForTimeout(600);
  const txt = await p.evaluate(() => { try{ fecharModal(); }catch(e){}
    irPara('cupons'); return document.getElementById('listaCupons').innerText.replace(/\s+/g, ' '); });
  verdade('a aba Cupons abre com o cupom de exemplo, sem erro', /BEMVINDA10/.test(txt), txt);
  // Demonstração gravada antes desta versão: sem a lista, a tela não estoura.
  const vazio = await p.evaluate(() => { delete bd.cupons; pintarCupons(); return document.getElementById('listaCupons').innerText; });
  verdade('e uma demonstração antiga, sem a lista, mostra "Nenhum cupom ainda"', /Nenhum cupom ainda/.test(vazio), vazio);
  await ctx.close();
}

igual('\nnenhum erro de JavaScript', erros, []);
await nav.close();
console.log(`\n${falhou ? '✗' : '✓'} ${passou} passaram, ${falhou} falharam.`);
process.exit(falhou ? 1 : 0);
