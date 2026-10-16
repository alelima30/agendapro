/* ===========================================================================
   AgendaPro — o modo Pedidos no banco (37_pedidos.sql)

     bash tests/bancada/subir.sh          (deixe rodando noutro terminal)
     node tests/pedidos.test.mjs

   O pedido: restaurante e pizzaria fazem PEDIDO, não agendamento — com
   entrega, taxa por bairro, pagamento na entrega, o andamento numa tela e a
   confirmação no WhatsApp quando o estabelecimento aceita.

   O que este arquivo cobra é o que a tela não pode garantir sozinha:
     1. o preço é o do cadastro — carrinho adulterado não muda o total;
     2. item de outro estabelecimento, fora do cardápio ou sem preço não entra;
     3. taxa por bairro, pedido mínimo, troco, formas de pagamento, entrega e
        retirada, horário de funcionamento e "Recebendo pedidos" valem aqui;
     4. limites contra pedido de mentira;
     5. o andamento só anda para a frente, e só a equipe mexe;
     6. cada etapa põe UMA mensagem na fila, com o modelo e as variáveis na
        ordem do MODELOS.md — e o que perdeu o sentido sai da fila;
     7. a cliente acompanha e cancela pelo segredo, e só antes do aceite.
   =========================================================================== */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from './pg.mjs';

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
const recusa = async f => { try{ await f(); return null; }catch(e){ return e.message || String(e); } };

const banco = new pg.Client({ host: process.env.PGHOST || '/tmp',
  port: Number(process.env.PGPORT || 5444), user: process.env.PGUSER || 'postgres',
  database: process.env.PGBANCO || 'app' });
await banco.connect();
const q = async (sql, args) => (await banco.query(sql, args)).rows;
const um = async (sql, args) => (await q(sql, args))[0];

const m = Date.now().toString(36) + Math.floor(Math.random()*1000);
let tel = 920000000 + (Date.now() % 50000000);
async function dona(nome, tipo){
  const d = aba();
  await d.criarConta({ email:`pd-${nome.toLowerCase()}-${m}@teste.com`, senha:'minhasenhaboa',
    nome, telefone:'+5511' + (tel++) });
  const cr = await d.chamar('criar_salao', { p_nome_salao: nome + ' ' + m, p_tipo: tipo,
    p_telefone:'(11) 97777-1234', p_documento:null, p_origem:null });
  d.salao = cr[0].salao_id; d.slug = cr[0].slug; d.nomeSalao = nome + ' ' + m;
  return d;
}
const pizza = await dona('Pizzaria', 'restaurante');
const outra = await dona('Cantina', 'restaurante');
const salao = await dona('Salao', 'salao');
const cfg = async (d, pedidos, extra) => {
  const atual = (await um(`select cfg from public.saloes where id = $1`, [d.salao])).cfg || {};
  await q(`update public.saloes set cfg = $2 where id = $1`,
    [d.salao, Object.assign({}, atual, extra || {}, pedidos === undefined ? {} : { pedidos })]);
};
const produto = (d, o) => d.inserir('produtos', Object.assign({ salaoId: d.salao, custo:0, estoque:0,
  ativo:true, vendaOnline:true }, o));
const calabresa = await produto(pizza, { nome:'Pizza calabresa', preco:45 });
const refri     = await produto(pizza, { nome:'Refrigerante 2L', preco:12 });
const escondido = await produto(pizza, { nome:'Prato do dia', preco:30 });
await q(`update public.produtos set preco_visivel = false where id = $1`, [escondido.id]);
const foraDoLink = await produto(pizza, { nome:'Pizza congelada', preco:25, vendaOnline:false });
const daOutra   = await produto(outra, { nome:'Lasanha', preco:40 });
ok('dois restaurantes e um salão, com o cardápio montado');

const cliente = aba();                       // a página: sem login
const pedido = (extra) => Object.assign({ nome:'Bruna Costa', telefone:'(11) 96543-2100',
  entrega:'retirada', pagamento:'pix', itens:[{ produto: calabresa.id, quantidade: 2 }] }, extra);
const fazer = (d, extra) => cliente.chamar('fazer_pedido', { p_slug: d.slug, p_pedido: pedido(extra) });
const limparPedidos = d => q(`delete from public.pedidos where salao_id = $1`, [d.salao]);

/* ══════════════════════════════════════════════════════════════════════════
   1 — QUEM RECEBE PEDIDO
   ══════════════════════════════════════════════════════════════════════════ */
secao('1. Quem recebe pedido pelo link');
const casa = await cliente.chamar('pedidos_da_casa', { p_slug: pizza.slug });
igual('o restaurante recebe, aberto, com os padrões de quem acabou de abrir',
  [casa.ligado, casa.aberto, casa.entrega, casa.retirada, Number(casa.taxaPadrao), Number(casa.minimo),
   casa.pagamentos, casa.servicosTambem],
  [true, true, true, true, 0, 0, ['pix', 'dinheiro', 'cartao'], false]);
igual('o salão de beleza não recebe pedido', (await cliente.chamar('pedidos_da_casa', { p_slug: salao.slug })).ligado, false);
const doSalao = await recusa(() => cliente.chamar('fazer_pedido', { p_slug: salao.slug, p_pedido: pedido() }));
verdade('e o banco recusa um pedido para ele', /não recebe pedidos pelo link/.test(doSalao || ''), doSalao);

/* ══════════════════════════════════════════════════════════════════════════
   2 — O PREÇO É O DO BANCO
   ══════════════════════════════════════════════════════════════════════════ */
secao('2. O preço é o do cadastro');
const r1 = await fazer(pizza, { itens:[{ produto: calabresa.id, quantidade: 2, preco: 0.01, total: 0.02 },
                                        { produto: refri.id, quantidade: 1, preco: 0 }],
                                total: 0.03, subtotal: 0.03 });
igual('carrinho adulterado (preço 0,01): o total sai do cadastro — 2×45 + 12 = 102',
  [Number(r1.subtotal), Number(r1.taxa), Number(r1.total), r1.status], [102, 0, 102, 'recebido']);
const gravado = await um(`select numero, total, telefone, cliente_id from public.pedidos where token = $1`, [r1.token]);
igual('gravado com o número 1, o total certo e o telefone só com dígitos',
  [Number(gravado.numero), Number(gravado.total), gravado.telefone], [1, 102, '11965432100']);
verdade('e ligado à ficha da cliente no restaurante', !!gravado.cliente_id);
const itens = await q(`select i.nome, i.preco, i.quantidade from public.pedido_itens i join public.pedidos p on p.id = i.pedido_id
  where p.token = $1 order by i.ordem`, [r1.token]);
igual('os itens com nome e preço copiados do cadastro', itens.map(i => [i.nome, Number(i.preco), i.quantidade]),
  [['Pizza calabresa', 45, 2], ['Refrigerante 2L', 12, 1]]);
const r2 = await fazer(pizza, { telefone:'(11) 95555-0001' });
igual('o próximo pedido é o número 2', Number(r2.numero), 2);
await limparPedidos(pizza);

secao('3. O que não entra');
const casos = [
  ['item de outro restaurante', { itens:[{ produto: daOutra.id, quantidade: 1 }] }, /saiu do cardápio/],
  ['item fora do link (venda online desligada)', { itens:[{ produto: foraDoLink.id, quantidade: 1 }] }, /saiu do cardápio/],
  ['item com o preço escondido', { itens:[{ produto: escondido.id, quantidade: 1 }] }, /sem preço no cardápio/],
  ['quantidade zero', { itens:[{ produto: calabresa.id, quantidade: 0 }] }, /quantidade/],
  ['quantidade 100', { itens:[{ produto: calabresa.id, quantidade: 100 }] }, /quantidade/],
  ['quantidade que não é número', { itens:[{ produto: calabresa.id, quantidade: '2; drop' }] }, /quantidade/],
  ['pedido vazio', { itens:[] }, /vazio/],
  ['sem nome', { nome:'  ' }, /nome/],
  ['telefone sem DDD', { telefone:'96543-2100' }, /DDD/],
  ['forma de pagamento inventada', { pagamento:'fiado' }, /como vai pagar/],
  ['entrega sem bairro', { entrega:'entrega', endereco:{ rua:'Rua A', numero:'10' } }, /rua, o número e o bairro/],
  ['nem entrega nem retirada', { entrega:'voando' }, /entrega e retirada/],
];
for(const [nome, extra, esperado] of casos){
  const e = await recusa(() => fazer(pizza, extra));
  verdade(`recusa: ${nome}`, esperado.test(e || ''), e);
}
igual('e nenhum desses virou pedido', Number((await um(`select count(*) n from public.pedidos where salao_id = $1`, [pizza.salao])).n), 0);

/* ══════════════════════════════════════════════════════════════════════════
   4 — AS REGRAS DO ESTABELECIMENTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('4. Taxa por bairro, mínimo, troco, entrega e retirada');
await cfg(pizza, { taxaPadrao: 6 });
const semLista = await fazer(pizza, { entrega:'entrega', endereco:{ rua:'Rua A', numero:'10', bairro:'Qualquer' } });
igual('sem lista de bairros, a taxa padrão vale para qualquer um: 90 + 6', [Number(semLista.taxa), Number(semLista.total)], [6, 96]);
await cfg(pizza, { taxaPadrao: 6, taxas:[{ bairro:'Centro', taxa: 5 }, { bairro:'São João', taxa: 8.5 }] });
const centro = await fazer(pizza, { telefone:'(11) 95555-0002', entrega:'entrega', endereco:{ rua:'Rua B', numero:'2', bairro:'  centro ' } });
igual('com lista, o bairro escrito de outro jeito acha a taxa dele (5)', [Number(centro.taxa), Number(centro.total)], [5, 95]);
const joao = await fazer(pizza, { telefone:'(11) 95555-0003', entrega:'entrega', endereco:{ rua:'Rua C', numero:'3', bairro:'Sao Joao' } });
igual('"Sao Joao" sem acento acha "São João" (8,50)', Number(joao.taxa), 8.5);
const bairroGravado = await um(`select bairro, endereco->>'bairro' b2 from public.pedidos where token = $1`, [joao.token]);
igual('e grava o bairro como o restaurante escreveu', [bairroGravado.bairro, bairroGravado.b2], ['São João', 'São João']);
const longe = await recusa(() => fazer(pizza, { telefone:'(11) 95555-0004', entrega:'entrega', endereco:{ rua:'R', numero:'1', bairro:'Longe' } }));
verdade('bairro fora da lista: não entrega lá', /não entrega no bairro Longe/.test(longe || ''), longe);
await limparPedidos(pizza);

await cfg(pizza, { minimo: 100 });
const pouco = await recusa(() => fazer(pizza));
verdade('abaixo do pedido mínimo (90 < 100): recusa e diz o mínimo', /mínimo é de R\$ 100,00/.test(pouco || ''), pouco);
await cfg(pizza, { minimo: 100 });
const noMinimo = await fazer(pizza, { itens:[{ produto: calabresa.id, quantidade: 2 }, { produto: refri.id, quantidade: 1 }] });
verdade('no mínimo, passa', Number(noMinimo.total) === 102);
await limparPedidos(pizza);

await cfg(pizza, { pagamentos:['pix'], retirada: false });
verdade('forma de pagamento desligada pelo restaurante: recusa',
  /como vai pagar/.test(await recusa(() => fazer(pizza, { pagamento:'dinheiro', entrega:'entrega',
    endereco:{ rua:'R', numero:'1', bairro:'X' } })) || ''));
verdade('retirada desligada: recusa e diz que só entrega',
  /só entrega/.test(await recusa(() => fazer(pizza)) || ''));
await cfg(pizza, {});
const trocoCurto = await recusa(() => fazer(pizza, { pagamento:'dinheiro', troco:'50' }));
verdade('troco para menos que o total: recusa', /troco precisa ser para um valor maior/.test(trocoCurto || ''), trocoCurto);
const comTroco = await fazer(pizza, { pagamento:'dinheiro', troco:'100,00' });
igual('troco para 100: grava', Number((await um(`select troco_para from public.pedidos where token = $1`, [comTroco.token])).troco_para), 100);
await limparPedidos(pizza);

secao('5. Fechado, sem receber, e o plano');
await cfg(pizza, { aceitando: false });
verdade('"Recebendo pedidos" desligado: recusa', /não está recebendo pedidos/.test(await recusa(() => fazer(pizza)) || ''));
igual('e a página fica sabendo que não está aberto', (await cliente.chamar('pedidos_da_casa', { p_slug: pizza.slug })).aberto, false);
// Um dia aberto que não é hoje: tem horário cadastrado, e hoje está fechado.
const hoje = Number((await um(`select extract(dow from now() at time zone 'America/Sao_Paulo')::int d`)).d);
const funcionamento = {}; for(let d = 0; d < 7; d++) funcionamento[d] = d === (hoje + 3) % 7 ? [['08:00', '18:00']] : [];
await cfg(pizza, {}, { funcionamento });
verdade('fora do horário de funcionamento: recusa', /fechado agora/.test(await recusa(() => fazer(pizza)) || ''));
const agoraAberto = {}; for(let d = 0; d < 7; d++) agoraAberto[d] = [['00:00', '00:00']];
await cfg(pizza, {}, { funcionamento: agoraAberto });
verdade('aberto o dia todo ("00:00" a "00:00"): passa', !!(await fazer(pizza)).token);
await limparPedidos(pizza);
await q(`update public.assinaturas set plano = 'gratuito', status = 'ativa', vence_em = null where salao_id = $1`, [pizza.salao]);
verdade('no plano Grátis (sem loja): recusa', /não estão disponíveis/.test(await recusa(() => fazer(pizza)) || ''));
igual('e a página fica sabendo', (await cliente.chamar('pedidos_da_casa', { p_slug: pizza.slug })).ligado, false);
await q(`update public.assinaturas set plano = 'trial', status = 'trial', trial_ate = current_date + 7 where salao_id = $1`, [pizza.salao]);

secao('6. Limite contra pedido de mentira');
for(let i = 0; i < 3; i++) await fazer(pizza, { telefone:'(11) 94444-0000' });
const quarto = await recusa(() => fazer(pizza, { telefone:'(11) 94444-0000' }));
verdade('o quarto pedido esperando aceite, do mesmo telefone, é recusado', /esperando a confirmação/.test(quarto || ''), quarto);
verdade('outro telefone continua pedindo', !!(await fazer(pizza, { telefone:'(11) 94444-1111' })).token);
await limparPedidos(pizza);

/* ══════════════════════════════════════════════════════════════════════════
   5 — A CLIENTE ACOMPANHA E CANCELA
   ══════════════════════════════════════════════════════════════════════════ */
secao('7. A cliente acompanha e cancela pelo segredo');
await q(`update public.saloes set whatsapp = '11977771234' where id = $1`, [pizza.salao]);
const p1 = await fazer(pizza, { entrega:'entrega', endereco:{ rua:'Rua das Flores', numero:'12', bairro:'Centro' } });
const visto = await cliente.chamar('meu_pedido', { p_token: p1.token });
igual('pelo segredo ela vê o número, a etapa, os itens e o total',
  [Number(visto.numero), visto.status, visto.itens.length, Number(visto.total), visto.casa], [Number(p1.numero), 'recebido', 1, 90, pizza.nomeSalao]);
verdade('e não vê o telefone nem o nome gravados (não precisa)', !('telefone' in visto) && !('nome' in visto), JSON.stringify(Object.keys(visto)));
igual('segredo que não existe: nada', await cliente.chamar('meu_pedido', { p_token: '00000000-0000-0000-0000-000000000000' }), null);
const naFila = await q(`select tipo, destino, modelo, variaveis, status from public.notificacoes where pedido_id = (select id from public.pedidos where token = $1)`, [p1.token]);
igual('o pedido novo avisou o restaurante no WhatsApp dele, com o modelo e as cinco variáveis',
  naFila.map(n => [n.tipo, n.destino, n.modelo, n.variaveis.length, n.status]),
  [['pedido_novo', '11977771234', 'agendapro_pedido_novo', 5, 'pendente']]);
igual('na ordem do MODELOS.md: empresa, número, nome, total, modo', naFila[0].variaveis,
  [pizza.nomeSalao, String(p1.numero), 'Bruna', 'R$ 90,00', 'entrega no bairro Centro']);
igual('cancelar antes do aceite: pode', await cliente.chamar('cancelar_meu_pedido', { p_token: p1.token }), true);
const cancelado = await um(`select status, cancelado_por from public.pedidos where token = $1`, [p1.token]);
igual('fica cancelado, por quem pediu', [cancelado.status, cancelado.cancelado_por], ['cancelado', 'cliente']);
igual('e o aviso que ainda estava na fila sai dela', (await um(`select status from public.notificacoes where pedido_id = (select id from public.pedidos where token = $1)`, [p1.token])).status, 'cancelado');

/* ══════════════════════════════════════════════════════════════════════════
   6 — O ESTABELECIMENTO MUDA O ANDAMENTO
   ══════════════════════════════════════════════════════════════════════════ */
secao('8. O andamento, pela equipe');
const p2 = await fazer(pizza, { telefone:'(11) 93333-2222', entrega:'entrega', endereco:{ rua:'R', numero:'5', bairro:'Centro' } });
const id2 = (await um(`select id from public.pedidos where token = $1`, [p2.token])).id;
const mudar = (d, st, motivo) => d.chamar('mudar_status_pedido', { p_pedido: id2, p_status: st, p_motivo: motivo || null });
verdade('a página (sem login) não muda o andamento', !!(await recusa(() => cliente.chamar('mudar_status_pedido', { p_pedido: id2, p_status: 'em_preparo' }))));
verdade('a dona de OUTRO restaurante também não', /Sem permissão/.test(await recusa(() => mudar(outra, 'em_preparo')) || ''));
verdade('pular de recebido para entregue: não', /não pode ir para/.test(await recusa(() => mudar(pizza, 'entregue')) || ''));
await cfg(pizza, { tempo: '40 a 60 min' });
await mudar(pizza, 'em_preparo');
const aceite = await q(`select tipo, destino, modelo, variaveis from public.notificacoes where pedido_id = $1 and tipo <> 'pedido_novo'`, [id2]);
igual('aceitar põe a confirmação na fila, para a cliente, com o tempo estimado',
  aceite.map(n => [n.tipo, n.destino, n.modelo, n.variaveis]),
  [['pedido_confirmado', '11933332222', 'agendapro_pedido_confirmado', ['Bruna', pizza.nomeSalao, String(p2.numero), 'R$ 90,00', '40 a 60 min']]]);
verdade('aceitar duas vezes (duplo clique): a segunda é recusada', !!(await recusa(() => mudar(pizza, 'em_preparo'))));
igual('e a confirmação não sai em dobro', Number((await um(`select count(*) n from public.notificacoes where pedido_id = $1 and tipo = 'pedido_confirmado'`, [id2])).n), 1);
verdade('pedido de entrega não fica "pronto para retirar"', /não pode ir para/.test(await recusa(() => mudar(pizza, 'pronto')) || ''));
igual('a cliente já não cancela depois do aceite', await cliente.chamar('cancelar_meu_pedido', { p_token: p2.token }), false);
await mudar(pizza, 'saiu');
const saiu = await q(`select tipo, status from public.notificacoes where pedido_id = $1 and tipo like 'pedido_%' and tipo <> 'pedido_novo' order by criado_em`, [id2]);
igual('"saiu para entrega" entra na fila, e a confirmação que ainda não tinha saído é aposentada',
  saiu.map(n => [n.tipo, n.status]), [['pedido_confirmado', 'cancelado'], ['pedido_a_caminho', 'pendente']]);
verdade('voltar de "saiu" para "em preparo": não', /não pode ir para/.test(await recusa(() => mudar(pizza, 'em_preparo')) || ''));
await mudar(pizza, 'entregue');
const fim = await um(`select status, aceito_em is not null a, saiu_em is not null s, entregue_em is not null e from public.pedidos where id = $1`, [id2]);
igual('entregue, com a hora de cada etapa', [fim.status, fim.a, fim.s, fim.e], ['entregue', true, true, true]);
igual('entregar não manda mensagem nova', Number((await um(`select count(*) n from public.notificacoes where pedido_id = $1 and status = 'pendente'`, [id2])).n), 0);
igual('a cliente vê "entregue" pelo segredo', (await cliente.chamar('meu_pedido', { p_token: p2.token })).status, 'entregue');

secao('9. Retirada, cancelamento pela casa e aviso desligado');
const p3 = await fazer(pizza, { telefone:'(11) 93333-3333' });
const id3 = (await um(`select id from public.pedidos where token = $1`, [p3.token])).id;
await pizza.chamar('mudar_status_pedido', { p_pedido: id3, p_status: 'em_preparo' });
await pizza.chamar('mudar_status_pedido', { p_pedido: id3, p_status: 'pronto' });
igual('retirada: "pronto para retirar" vai para a cliente',
  (await um(`select modelo from public.notificacoes where pedido_id = $1 and status = 'pendente'`, [id3])).modelo, 'agendapro_pedido_pronto');
const p4 = await fazer(pizza, { telefone:'(11) 93333-4444' });
const id4 = (await um(`select id from public.pedidos where token = $1`, [p4.token])).id;
await pizza.chamar('mudar_status_pedido', { p_pedido: id4, p_status: 'cancelado', p_motivo: 'acabou a massa' });
const canc = await um(`select variaveis, modelo from public.notificacoes where pedido_id = $1 and tipo = 'pedido_cancelado'`, [id4]);
igual('cancelado pela casa: a cliente recebe o motivo', [canc.modelo, canc.variaveis[3]], ['agendapro_pedido_cancelado', 'acabou a massa']);
igual('e o pedido guarda quem cancelou', (await um(`select cancelado_por from public.pedidos where id = $1`, [id4])).cancelado_por, 'casa');
await cfg(pizza, { avisarCliente: false, avisarCasa: false });
const p5 = await fazer(pizza, { telefone:'(11) 93333-5555' });
const id5 = (await um(`select id from public.pedidos where token = $1`, [p5.token])).id;
await pizza.chamar('mudar_status_pedido', { p_pedido: id5, p_status: 'em_preparo' });
igual('com os dois avisos desligados, nada entra na fila', Number((await um(`select count(*) n from public.notificacoes where pedido_id = $1`, [id5])).n), 0);

secao('10. A lista da tela e quem enxerga');
const lista = await pizza.chamar('pedidos_da_loja', { p_salao: pizza.salao, p_horas: 24 });
verdade('a dona vê os pedidos do dia, com os itens dentro', Array.isArray(lista) && lista.length >= 4 && lista.every(p => Array.isArray(p.itens) && p.itens.length),
  JSON.stringify(lista && lista.length));
verdade('a dona de outro restaurante não', /Sem permissão/.test(await recusa(() => outra.chamar('pedidos_da_loja', { p_salao: pizza.salao })) || ''));
verdade('nem a página sem login', !!(await recusa(() => cliente.chamar('pedidos_da_loja', { p_salao: pizza.salao }))));
igual('e a tabela, lida direto pela outra dona, não devolve nada', (await outra.lista('pedidos', { salao_id: pizza.salao })).length, 0);
const anonLe = await cliente.lista('pedidos', { salao_id: pizza.salao }).then(x => x.length, e => 'recusado: ' + e.message);
verdade('nem a página sem login lê a tabela', anonLe === 0 || /^recusado/.test(String(anonLe)), String(anonLe));
const daCota = await um(`select public.pode_enviar_tipo($1, 'pedido_confirmado') a, public.pode_enviar_tipo($1, 'pedido_novo') b`, [pizza.salao]);
verdade('a cota do plano vale para as mensagens do pedido', daCota.a !== null && daCota.b !== null);

secao('11. Excluir a conta leva os pedidos junto');
const r = await pizza.chamar('excluir_minha_conta', { p_confirmacao: 'EXCLUIR' });
igual('a dona do restaurante exclui a conta, com pedidos e mensagens na fila', r && r.saloes_apagados, 1);
igual('e não sobra pedido nenhum dele', Number((await um(`select count(*) n from public.pedidos where salao_id = $1`, [pizza.salao])).n), 0);

await banco.end();
console.log(`\n${passou} passaram, ${falhou} falharam`);
process.exit(falhou ? 1 : 0);
