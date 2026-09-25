/* ===========================================================================
   AgendaPro — o JavaScript de cada tela precisa ao menos COMPILAR

     node tests/sintaxe.test.js

   POR QUE ESTE ARQUIVO EXISTE
   Escrevi um comentário assim, dentro de um template literal:

       <!-- o campo `profissionais.foto` já existia esperando -->

   As crases fecharam a string no meio do HTML, e o script inteiro do painel
   deixou de compilar. A tela não abria — nem um pedaço dela.

   O que me contou não foi um teste do painel: foi o teste de IMAGENS, numa
   linha que diz "nenhum erro de JavaScript na página", com a mensagem
   "missing ) after argument list". Diagnóstico de raspão, na suíte errada,
   apontando para o arquivo errado.

   Um erro de sintaxe não merece investigação: merece uma linha dizendo o
   arquivo e o número. É o teste mais barato daqui e o que falha mais cedo.
   =========================================================================== */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RAIZ = path.dirname(__dirname);
const TELAS = ['app.html', 'agendar.html', 'criar.html', 'entrar.html',
               'admin.html', 'index.html', 'nova-senha.html'];
const AVULSOS = ['dados.js', 'demo.js', 'imagens.js', 'icones.js',
                 'endereco.js', 'funcionamento.js', 'config.js', 'sw.js'];

let ok = 0, falhas = 0;
const dizer = (bom, msg, extra) => {
  if(bom){ ok++; console.log('  ✓ ' + msg); }
  else { falhas++; console.log('  ✗ ' + msg + (extra ? '\n      ' + extra : '')); }
};

// Onde cada <script> começa no arquivo, para o número da linha do erro bater
// com o número da linha no HTML — senão o recado manda procurar no lugar
// errado, que é o vício que este arquivo existe para não repetir.
function scriptsDe(texto){
  const achados = [];
  const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
  let m;
  while((m = re.exec(texto)) !== null){
    achados.push({ codigo: m[1], linha: texto.slice(0, m.index).split('\n').length });
  }
  return achados;
}

console.log('\nO JavaScript embutido em cada tela compila');
for(const tela of TELAS){
  const caminho = path.join(RAIZ, tela);
  if(!fs.existsSync(caminho)){ dizer(false, tela + ' não existe'); continue; }
  const texto = fs.readFileSync(caminho, 'utf8');
  const blocos = scriptsDe(texto);
  let problema = null;
  for(const b of blocos){
    try{
      new vm.Script(b.codigo, { filename: tela });
    }catch(e){
      // A linha que o motor reporta é relativa ao bloco; somada ao começo do
      // bloco, vira a linha do arquivo que se abre no editor.
      const dentro = Number((String(e.stack).match(/<anonymous>:(\d+)|:(\d+)\n/) || [])[1] || 0);
      problema = e.message + (dentro ? ' — perto da linha ' + (b.linha + dentro) + ' de ' + tela : '');
      break;
    }
  }
  dizer(!problema, tela + ' compila', problema);
}

console.log('\nE os arquivos .js soltos');
for(const arq of AVULSOS){
  const caminho = path.join(RAIZ, arq);
  if(!fs.existsSync(caminho)){ dizer(false, arq + ' não existe'); continue; }
  try{
    new vm.Script(fs.readFileSync(caminho, 'utf8'), { filename: arq });
    dizer(true, arq + ' compila');
  }catch(e){ dizer(false, arq + ' compila', e.message); }
}

/* ── A ARMADILHA QUE CAUSOU ISTO ──────────────────────────────────────────
   Comentário HTML dentro de template literal é normal e útil — explica o
   markup ali onde ele é escrito. O que não pode é conter crase, porque a
   crase não sabe que está dentro de um comentário: ela fecha a string.

   O teste acima já pegaria, mas só depois do estrago. Este aponta o lugar. */
console.log('\nCrase dentro de comentário HTML embutido');
for(const tela of TELAS){
  const caminho = path.join(RAIZ, tela);
  if(!fs.existsSync(caminho)) continue;
  const texto = fs.readFileSync(caminho, 'utf8');
  const suspeitos = [];
  for(const b of scriptsDe(texto)){
    const re = /<!--[\s\S]*?-->/g;
    let m;
    while((m = re.exec(b.codigo)) !== null){
      if(m[0].includes('`')){
        suspeitos.push('linha ~' + (b.linha + b.codigo.slice(0, m.index).split('\n').length));
      }
    }
  }
  dizer(suspeitos.length === 0,
    tela + ': nenhum comentário embutido com crase',
    suspeitos.join(', '));
}

/* ── UM AJUSTE DE APARÊNCIA ATRAVESSA TRÊS ARQUIVOS ───────────────────────
   O caminho de um ajuste que o dono escolhe em "Meu salão" até virar pixel
   na tela da cliente passa por três lugares, em arquivos diferentes:

       app.html          salvarAparencia() grava a chave no `cfg`
         ↓
       06_vitrine.sql    vitrine() devolve a chave (o `cfg` cru nunca sai)
         ↓
       agendar.html      bdDaVitrine() copia a chave para o salão da tela

   Esquecer qualquer um dos dois últimos não dá erro nenhum. O dono escolhe,
   o painel grava, a PRÉVIA do painel obedece — e a página da cliente
   continua igual. Não há o que investigar: nada quebrou.

   Já aconteceu duas vezes, com `veu` e com `cartoes`, e as duas foram
   descobertas por acaso. Este bloco troca "alguém repara" por "o teste
   reprova", e passa a valer para toda chave nova sem ninguém precisar
   lembrar de escrever teste para ela.

   A conferência é de TEXTO de propósito: um teste de navegador precisaria
   saber o que cada chave FAZ na tela, e a próxima chave nasceria sem
   cobertura de novo. */
console.log('\nA aparência atravessa do painel até a página da cliente');
{
  const app = fs.readFileSync(path.join(RAIZ, 'app.html'), 'utf8');
  const vitrine = fs.readFileSync(
    path.join(RAIZ, 'supabase', '06_vitrine.sql'), 'utf8');
  const cliente = fs.readFileSync(path.join(RAIZ, 'agendar.html'), 'utf8');

  /* 1) As chaves de APARÊNCIA — as que `salvarAparencia()` grava, e só elas.

     ⚠ A primeira versão procurava `sl.cfg = Object.assign(...)` no arquivo
     inteiro e pegava a PRIMEIRA que achasse. Funcionou enquanto só a
     aparência escrevia no `cfg`. Quando o cadastro do salão e as notificações
     passaram a escrever também, o guarda começou a exigir que
     `notifLembreteMin` atravessasse até a página da cliente — que é
     exatamente o contrário do certo: configuração interna do salão não tem o
     que fazer no navegador de quem marca horário.

     Recortar a função pelo nome é o que faz esta verificação continuar
     falando da aparência quando o arquivo cresce. */
  const corpoAparencia = (app.match(
    /function salvarAparencia\(\)\{([\s\S]*?)\n\}/) || [])[1] || '';
  const grava = corpoAparencia.match(
    /sl\.cfg = Object\.assign\(\{\}, sl\.cfg, \{([\s\S]*?)\}\);/);
  const chaves = grava
    ? [...grava[1].matchAll(/^\s*([A-Za-z][A-Za-z0-9_]*)\s*:/gm)].map(m => m[1])
    : [];
  dizer(chaves.length > 0,
    'achei as chaves de aparência que o painel grava (' + chaves.length + ')',
    'o salvarAparencia() mudou de forma — conserte esta busca, não apague a '
    + 'verificação');

  /* 2) As chaves que a vitrine() devolve: o nome antes da vírgula, que é como
        o jsonb_build_object batiza cada campo. */
  const devolve = new Set(
    [...vitrine.matchAll(/'([A-Za-z][A-Za-z0-9_]*)'\s*,/g)].map(m => m[1]));

  // 3) As chaves que a página da cliente copia para o salão dela.
  const bloco = cliente.match(/saloes:\s*\[\{([\s\S]*?)\}\],/);
  const copia = new Set(bloco
    ? [...bloco[1].matchAll(/([A-Za-z][A-Za-z0-9_]*)\s*:/g)].map(m => m[1])
    : []);
  dizer(copia.size > 0, 'achei a lista que a página da cliente remonta',
    'o bdDaVitrine() mudou de forma — conserte esta busca');

  const semVitrine = chaves.filter(k => !devolve.has(k));
  dizer(semVitrine.length === 0,
    'toda chave gravada pelo painel sai na vitrine()',
    semVitrine.join(', ') + ' — o dono escolhe e a página da cliente nunca '
    + 'fica sabendo (supabase/06_vitrine.sql)');

  const semCliente = chaves.filter(k => !copia.has(k));
  dizer(semCliente.length === 0,
    'e toda chave é copiada pela página da cliente',
    semCliente.join(', ') + ' — a vitrine devolve e o bdDaVitrine() joga '
    + 'fora (agendar.html)');
}

/* ── E O QUARTO LUGAR, QUE NINGUÉM VÊ ─────────────────────────────────────
   A verificação de cima lê o `06_vitrine.sql` como fonte da verdade, e está
   certa: é lá que a `vitrine()` nasce. Só que ela não é a última palavra.

   A `vitrine()` é uma função SQL monolítica — não há como acrescentar uma
   chave sem reapresentá-la INTEIRA. Então todo módulo que precise devolver
   mais alguma coisa faz `create or replace` por cima, e o banco fica com a
   definição do módulo de número MAIOR. Hoje é o `25_loja.sql`.

   O efeito: chave escrita no 06 e esquecida no 25 passa neste teste, passa em
   todo o resto, e não existe no banco. É o mesmo silêncio do bloco acima —
   agora com o teste que o vigiava olhando para o arquivo errado.

   Já quase aconteceu com a `moldura`, na primeira vez em que este arquivo
   cobrou o 06 e eu acrescentei a chave só lá.

   Por isso a conferência é entre o 06 e o ÚLTIMO módulo que reescreve a
   função — descoberto por varredura, e não por nome, para que o módulo 31 que
   um dia reescrever a vitrine de novo entre nesta conta sozinho. */
/* ⚠ SEM OS COMENTÁRIOS, E ISSO NÃO É DETALHE.
   O 25_loja.sql explica o `cartoes` escrevendo "'auto', 'vidro' ou 'fechado'"
   num comentário. Contando o texto cru, `auto` virava uma "chave" — e como os
   arquivos montados são gerados SEM comentário, ela aparecia lá como chave
   PERDIDA. O guarda reprovava um arquivo correto, apontando para uma palavra
   que nunca foi chave de nada.

   É a mesma limpeza do `montar-modulos.sh`, pelo mesmo motivo: o que conta é o
   que o Postgres lê. Fica no escopo de cima porque DOIS blocos precisam dela —
   o da vitrine e o das funções redefinidas — e uma cópia em cada seria duas
   regras que um dia divergem. */
const semComentarios = sql => sql
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n').map(l => { const c = l.indexOf('--'); return c >= 0 ? l.slice(0, c) : l; })
  .join('\n');

console.log('\nO último módulo a reescrever a vitrine() não perdeu chave nenhuma');
{
  const dir = path.join(RAIZ, 'supabase');

  const chavesDe = txt => {
    /* Só o corpo da função: `create or replace ... vitrine` até o `$$;` que a
       fecha. Sem isto, comentário de cabeçalho com aspas entraria na conta. */
    const corpo = semComentarios(txt).match(
      /create or replace function public\.vitrine\b[\s\S]*?\$\$;/);
    return corpo
      ? new Set([...corpo[0].matchAll(/'([A-Za-z][A-Za-z0-9_]*)'\s*,/g)]
          .map(m => m[1]))
      : null;
  };

  /* Os módulos numerados, e só eles: o `00_tudo`, o `98_modulos` e o
     `99_remendo` são montados por script a partir destes, e conferir a cópia
     em vez do original esconderia justamente um script desatualizado. */
  const modulos = fs.readdirSync(dir)
    .filter(f => /^(?!00_)\d\d_.*\.sql$/.test(f) && !/^9\d_/.test(f))
    .sort();
  const reescrevem = modulos.filter(
    f => /create or replace function public\.vitrine\b/.test(
      fs.readFileSync(path.join(dir, f), 'utf8')));

  dizer(reescrevem.length > 0 && reescrevem[0] === '06_vitrine.sql',
    'a vitrine() nasce no 06_vitrine.sql',
    'quem define primeiro agora é ' + (reescrevem[0] || 'ninguém')
    + ' — o bloco acima lê o 06 e passou a olhar para o arquivo errado');

  const ultimo = reescrevem[reescrevem.length - 1];
  const nasce = chavesDe(fs.readFileSync(path.join(dir, '06_vitrine.sql'), 'utf8'));
  const vale  = chavesDe(fs.readFileSync(path.join(dir, ultimo), 'utf8'));

  dizer(nasce && nasce.size > 0 && vale && vale.size > 0,
    'consegui ler as duas definições (' + ultimo + ' é a que o banco guarda)',
    'o recorte da função falhou — conserte esta busca, não apague a verificação');

  const perdidas = [...(nasce || [])].filter(k => !(vale || new Set()).has(k));
  dizer(perdidas.length === 0,
    'e ' + ultimo + ' devolve tudo o que o 06_vitrine.sql devolve',
    perdidas.join(', ') + ' — está no 06 e o ' + ultimo + ' reescreve a função '
    + 'por cima sem ela, então no banco essa chave não existe');

  /* ── E OS ARQUIVOS MONTADOS, QUE SÃO ONDE ISSO CHEGA AO BANCO ───────────
     A verificação acima compara dois MÓDULOS. Não é onde o estrago acontece:
     ninguém cola módulo no Supabase. Cola-se o `00_tudo.sql`, ou o
     `98_modulos.sql` para atualizar, ou o `99_remendo.sql` quando o grande
     chegou picotado. Cada um é montado por um script diferente, e cada script
     decide por conta própria qual vitrine leva.

     O `99_remendo.sql` levava a do 06, escrita à mão no `montar-remendo.sh`.
     Colado depois do `98_modulos.sql`, ele REINSTALAVA a versão antiga e a
     loja sumia da página da cliente — sem erro, com o painel continuando a
     listar os produtos. Medido: a vitrine tinha `produtos` antes do remendo e
     não tinha depois.

     A primeira versão deste bloco não teria pego isso, porque eu a escrevi
     olhando só para o par 06 × 25 que tinha na frente. Estes três casos são a
     correção: a conta é sobre o que o banco RECEBE. */
  const montados = ['00_tudo.sql', '98_modulos.sql', '99_remendo.sql'];
  for(const arq of montados){
    const caminho = path.join(dir, arq);
    if(!fs.existsSync(caminho)){ dizer(false, arq + ' existe'); continue; }
    const texto = semComentarios(fs.readFileSync(caminho, 'utf8'));
    /* A ÚLTIMA definição do arquivo, que é a que fica de pé: os três levam a
       função mais de uma vez, de propósito — o 06 traz os `grant` e o módulo
       traz as chaves novas. Quem vale é quem chega por último. */
    const todas = texto.match(
      /create or replace function public\.vitrine\b[\s\S]*?\$\$;/g) || [];
    const final = todas.length
      ? new Set([...todas[todas.length - 1]
          .matchAll(/'([A-Za-z][A-Za-z0-9_]*)'\s*,/g)].map(m => m[1]))
      : new Set();
    const faltam = [...(vale || [])].filter(k => !final.has(k));
    dizer(todas.length > 0 && faltam.length === 0,
      arq + ' entrega a vitrine completa (' + todas.length + 'x, ' + final.size + ' chaves)',
      !todas.length
        ? 'este arquivo não leva vitrine() nenhuma — rode o montar correspondente'
        : faltam.join(', ') + ' — a última vitrine deste arquivo é mais VELHA '
          + 'que a do ' + ultimo + '. Quem colar isto por cima de uma '
          + 'instalação boa desfaz o módulo, sem erro nenhum.');
  }
}

/* ── O AVISO DE DIREITOS AUTORAIS, EM TODA PÁGINA ─────────────────────────
   Sem página nenhuma de fora: a tela que faltar é justamente a que alguém vai
   abrir, copiar e dizer que não sabia. E a próxima página do projeto nasce
   sem o aviso a menos que algo cobre — que é a função desta verificação.

   O texto é conferido por inteiro, não por pedaço: aviso legal com metade da
   frase não é aviso legal. */
console.log('\nO aviso de direitos autorais está em todas as telas');
{
  const AVISO = 'AgendaPro · Todos os direitos reservados. Software protegido '
    + 'por direitos autorais (Lei 9.610/98 e Lei 9.609/98). Reprodução, '
    + 'distribuição ou uso não autorizado são proibidos.';

  const COM_AVISO = TELAS.concat(['convite.html']);
  for(const tela of COM_AVISO){
    const caminho = path.join(RAIZ, tela);
    if(!fs.existsSync(caminho)){ dizer(false, tela + ' não existe'); continue; }
    const texto = fs.readFileSync(caminho, 'utf8');
    dizer(texto.includes(AVISO), tela + ' traz o aviso, por inteiro',
      texto.includes('rodape-legal')
        ? 'o bloco existe mas o TEXTO mudou — se foi de propósito, atualize '
          + 'esta verificação junto'
        : 'falta o <p class="rodape-legal"> nesta tela');
  }
}

/* ── O CONTRATO DOS MODELOS DO WHATSAPP ───────────────────────────────────
   O texto de cada modelo é cadastrado NA META, à mão, a partir do MODELOS.md.
   As variáveis que o preenchem são montadas no banco, em
   `variaveis_agendamento()`. Os dois lados só combinam por acordo.

   E o desacordo é invisível: se `{{2}}` e `{{3}}` trocarem de lugar no texto
   cadastrado, toda cliente passa a receber a data onde deveria estar o
   horário — e o histórico do painel continua mostrando certo, porque ele
   mostra o `corpo`, montado por outro caminho. Não haveria erro, log, nem
   reclamação que apontasse para a causa.

   Modelo aprovado praticamente não se edita: para mudar uma vírgula você cria
   outro e espera nova aprovação. Errar aqui é caro.

   A conferência é de TEXTO porque o outro lado do contrato é um documento que
   uma pessoa copia com o mouse. Não há banco que pegue isso. */
console.log('\nOs modelos do WhatsApp combinam com o que o banco preenche');
{
  const md = fs.readFileSync(path.join(RAIZ, 'supabase', 'functions',
    'enviar-notificacoes', 'MODELOS.md'), 'utf8');
  const sql = fs.readFileSync(path.join(RAIZ, 'supabase',
    '21_notificacoes.sql'), 'utf8');

  const nomes = [...sql.matchAll(/when '(\w+)'\s+then '(agendapro_\w+)'/g)]
    .map(m => ({ tipo: m[1], modelo: m[2] }));
  dizer(nomes.length === 4,
    `achei os quatro modelos no modelo_de() (${nomes.length})`,
    'o modelo_de() mudou de forma — conserte esta busca, não apague a verificação');

  const blocoDe = nome => {
    const i = md.indexOf('`' + nome + '`');
    if(i < 0) return null;
    const m = md.slice(i).match(/```\n([\s\S]*?)```/);
    return m ? m[1] : null;
  };

  const corpoVA = (sql.match(
    /function public\.variaveis_agendamento\(([\s\S]*?)\nend \$\$;/) || [])[1] || '';
  const conta = t => (t.match(/variavel_limpa\(/g) || []).length;
  const ramo  = re => (corpoVA.match(re) || [])[1] || '';
  const noSql = {
    confirmacao: conta(ramo(/'confirmacao','lembrete'\) then([\s\S]*?)elsif/)),
    novo:        conta(ramo(/p_tipo = 'novo' then([\s\S]*?)end if;/)),
  };
  noSql.lembrete = noSql.confirmacao;            // o mesmo ramo atende os dois
  // O resumo é montado no gerar_resumos: nome do salão + a lista do dia.
  noSql.resumo = /modelo_de\('resumo'\)[\s\S]{0,400}?variavel_lista\(/.test(sql)
    ? 2 : 0;

  for(const { tipo, modelo } of nomes){
    const corpo = blocoDe(modelo);
    if(!corpo){ dizer(false, `${modelo}: tem seção no MODELOS.md`); continue; }

    const numeros = [...corpo.matchAll(/\{\{(\d+)\}\}/g)].map(m => +m[1]);
    const distintos = [...new Set(numeros)].sort((a, b) => a - b);

    dizer(distintos.length === noSql[tipo],
      `${modelo}: ${distintos.length} variáveis no texto e ${noSql[tipo]} no banco`,
      'o texto cadastrado na Meta e o variaveis_agendamento() têm que casar em '
      + 'QUANTIDADE e em ORDEM — a ordem só o olho confere, esta linha guarda '
      + 'o número');

    // {{1}},{{3}} faz a Meta recusar o cadastro, e um {{2}} esquecido desloca
    // todas as seguintes.
    dizer(distintos.every((n, i) => n === i + 1),
      `${modelo}: variáveis numeradas de 1 a ${distintos.length}, sem pular`,
      JSON.stringify(distintos));

    /* A Meta recusa modelo cujo corpo começa ou termina em variável. Descobrir
       no cadastro custa uma ida e volta; descobrir aqui não custa nada. */
    const limpo = corpo.trim();
    dizer(!limpo.startsWith('{{') && !limpo.endsWith('}}'),
      `${modelo}: o texto não começa nem termina com variável`,
      'a Meta recusa o cadastro assim');
  }
}

/* ── TODA FUNÇÃO DEFINIDA DUAS VEZES, E NÃO SÓ A VITRINE ──────────────────
   O bloco acima vigia a `vitrine()`. Escrevi aquele guarda depois de a
   `vitrine()` me enganar — e ele é específico demais, porque o problema não é
   da vitrine: é de QUALQUER função redefinida em mais de um módulo.

   Aconteceu de novo, com a `horarios_livres()`. Ela existe no 05_agenda.sql e
   é reescrita pelo 14_motor.sql. Escrevi a antecedência mínima no 05,
   instalei, e a agenda ignorou: a régua do painel gravava no `cfg` e o motor
   seguia com os 30 minutos de sempre. As duas funções compilam, as duas
   existem, e a de número maior é a que vale. Nada avisa.

   Custou uma corrida inteira de testes para descobrir — e o guarda da vitrine,
   que tinha exatamente esse formato, não olhava para ela.

   ── O QUE ESTE BLOCO FAZ ──────────────────────────────────────────────────
   Não tenta adivinhar qual versão é a certa: ele LISTA. Função definida em
   dois módulos é um fato que quem for mexer precisa saber antes de editar, e
   a lista é a diferença entre "eu sabia" e "descobri depois de instalar".

   Só REPROVA quando a definição que os arquivos de colar levam não é a
   ÚLTIMA — que é o defeito de verdade, o mesmo que fez o remendo desfazer a
   loja e quase fez o 98 desfazer o motor. */
console.log('\nFunção definida em mais de um módulo: qual versão viaja');
{
  const dir = path.join(RAIZ, 'supabase');
  const mods = fs.readdirSync(dir)
    .filter(f => /^(?!00_)\d\d_.*\.sql$/.test(f) && !/^9\d_/.test(f)).sort();

  // nome da função -> módulos que a definem, em ordem de instalação
  const onde = new Map();
  for(const f of mods){
    const txt = fs.readFileSync(path.join(dir, f), 'utf8');
    for(const m of txt.matchAll(
        /create or replace function\s+public\.([a-z0-9_]+)\s*\(/gi)){
      const n = m[1].toLowerCase();
      if(!onde.has(n)) onde.set(n, []);
      if(!onde.get(n).includes(f)) onde.get(n).push(f);
    }
  }
  const repetidas = [...onde].filter(([, fs2]) => fs2.length > 1);
  dizer(true, 'funções reescritas por outro módulo: ' + repetidas.length
    + (repetidas.length
        ? ' (' + repetidas.map(([n, fs2]) =>
            n + ': ' + fs2.join('→')).join('; ') + ')' : ''));

  /* E agora o que importa: nos arquivos que alguém COLA, a última definição
     de cada uma dessas funções tem que ser a do último módulo. Se for a de um
     módulo anterior, colar aquele arquivo DESFAZ o mais novo. */
  const corpoFinal = (txt, nome) => {
    const todas = [...txt.matchAll(new RegExp(
      'create or replace function\\s+public\\.' + nome + '\\s*\\([\\s\\S]*?\\$\\$;', 'gi'))];
    return todas.length ? todas[todas.length - 1][0] : null;
  };
  const marcaDe = corpo => corpo
    ? semComentarios(corpo).replace(/\s+/g, ' ').trim() : null;

  for(const [nome, arquivos] of repetidas){
    const esperado = marcaDe(corpoFinal(
      fs.readFileSync(path.join(dir, arquivos[arquivos.length - 1]), 'utf8'), nome));
    for(const alvo of ['00_tudo.sql', '98_modulos.sql', '99_remendo.sql']){
      const caminho = path.join(dir, alvo);
      if(!fs.existsSync(caminho)) continue;
      const txt = fs.readFileSync(caminho, 'utf8');
      const achado = marcaDe(corpoFinal(txt, nome));
      if(achado === null) continue;   // este arquivo não leva esta função
      dizer(achado === esperado,
        alvo + ' leva a versão boa de ' + nome + '()',
        'a última ' + nome + '() deste arquivo NÃO é a do '
        + arquivos[arquivos.length - 1] + ' — quem colar isto por cima de uma '
        + 'instalação boa volta para uma versão antiga, sem erro nenhum');
    }
  }
}

/* ═══════════════════════════════════════════════════════════════════════════
   O REMENDO NÃO PODE CHAMAR O QUE ELE NÃO TRAZ

   O 99_remendo.sql é o arquivo de RESGATE: cola-se quando o 00_tudo.sql chegou
   picotado. Ele pode se apoiar no núcleo antigo — `e_gestor`, `hoje_no_salao`,
   coisas dos primeiros módulos, que qualquer instalação tem. O que ele NÃO
   pode é chamar uma função que só nasce num módulo tardio sem trazer esse
   módulo junto.

   O PL/pgSQL não avisa: ele só resolve o nome na hora de EXECUTAR. Então o
   remendo instala limpo, o editor do Supabase diz "Success", e o estrago
   aparece na primeira cliente que tenta marcar.

   Aconteceu duas vezes, e as duas foram medidas num banco de verdade:

     · `horarios_livres()` vinha recortada do 14_motor.sql e chamava
       `jornada_costurada()`, `ha_choque()` e `ha_bloqueio()` — as três do
       mesmo 14, nenhuma delas no remendo. Toda listagem de horários morria.
     · o 09_cliente.sql inteiro chamava `pacote_que_cobre()` e
       `pacote_fora_do_dia()`, do 27. Toda marcação de cliente LOGADA morria.

   A regra que este bloco cobra: se a versão que VALE HOJE de uma função mora
   num módulo de número 10 ou maior, o remendo tem que trazer a definição dela.

   ⚠ "A QUE VALE HOJE", E NÃO "TODAS". Aqui estava
   `onde.get(n).every(f => Number(f.slice(0,2)) >= 10)` — a função só era
   cobrada se NENHUM módulo cedo a definisse. Parece a mesma coisa e não é:

     · o `preco_dos_servicos` nasce no 05_agenda.sql com duas colunas e é
       reescrito no 33_preco_regras.sql com três, pegando o horário;
     · o `agendar()` do remendo chama a de TRÊS;
     · havia um dono cedo, então este bloco deixava passar.

   O remendo saiu chamando uma assinatura que ele não trazia, e este teste
   aprovou. Medido depois: 0 definições no arquivo, a chamada na linha 829, e
   `function public.preco_dos_servicos(uuid, uuid[], timestamptz) does not
   exist` na primeira marcação pelo link.

   O gerador tinha o mesmo ponto cego, escrito com as mesmas palavras. Um
   guardião que repete a suposição do que ele guarda não guarda nada — foi a
   suposição, e não o descuido, que passou nos dois lugares.
   ═══════════════════════════════════════════════════════════════════════════ */
console.log('\nO remendo traz tudo o que chama');
{
  const dir = path.join(RAIZ, 'supabase');
  const caminho = path.join(dir, '99_remendo.sql');
  if(fs.existsSync(caminho)){
    const rem = fs.readFileSync(caminho, 'utf8');
    const definidas = new Set([...rem.matchAll(
      /create or replace function\s+public\.(\w+)/gi)].map(m => m[1]));
    const chamadas = new Set([...rem.matchAll(/public\.(\w+)\s*\(/g)]
      .map(m => m[1]).filter(n => !definidas.has(n)));

    const mods = fs.readdirSync(dir)
      .filter(f => /^(?!00_)\d\d_.*\.sql$/.test(f) && !/^9\d_/.test(f)).sort();
    const onde = new Map();
    for(const f of mods){
      const txt = fs.readFileSync(path.join(dir, f), 'utf8');
      for(const m of txt.matchAll(/create or replace function\s+public\.(\w+)/gi)){
        if(!onde.has(m[1])) onde.set(m[1], []);
        if(!onde.get(m[1]).includes(f)) onde.get(m[1]).push(f);
      }
    }

    const faltando = [...chamadas].filter(n => onde.has(n)
      && Number(onde.get(n).at(-1).slice(0, 2)) >= 10).sort();

    dizer(faltando.length === 0,
      'o 99_remendo.sql define toda função de módulo tardio que ele chama',
      'chama sem trazer: ' + faltando.map(n => n + '() do ' + onde.get(n).join('/'))
        .join(', ') + ' — o remendo instala com "Success" e a agenda morre na '
      + 'primeira chamada de verdade');
  }
}

/* ── TODA MUTAÇÃO ACHA O TRECHO QUE ELA QUEBRA ─────────────────────────────
   Os tests/mutacoes-*.sh trocam um trecho exato do código e conferem que
   o teste reprova. Quando o código muda e o trecho some, a mutação não roda
   — o script avisa "NÃO RODOU", mas só quando alguém roda o script, e
   ninguém roda as dez a cada mudança. Numa reorganização da tela de
   Aparência apareceram catorze assim, sete delas paradas havia rodadas.

   Aqui a conferência é a cada suíte: cada `troca ARQUIVO "de"` precisa
   achar o trecho exatamente UMA vez. */
console.log('\nToda mutação ainda acha o trecho que ela quebra');
{
  const dq = t => t.replace(/\\([\\"$`])/g, '$1');
  const perdidas = [];
  let contadas = 0;
  for(const f of fs.readdirSync(__dirname).filter(n => /^mutacoes-.*\.sh$/.test(n)).sort()){
    const txt = fs.readFileSync(path.join(__dirname, f), 'utf8');
    for(const m of txt.matchAll(/troca (\S+) \\\n  ("((?:[^"\\]|\\.)*)"|'([^']*)') \\\n/gs)){
      const alvo = path.join(RAIZ, m[1]);
      if(!fs.existsSync(alvo)) continue;
      const de = m[3] !== undefined ? dq(m[3]) : m[4];
      const n = fs.readFileSync(alvo, 'utf8').split(de).length - 1;
      contadas++;
      if(n !== 1) perdidas.push(`${f} → ${m[1]} (${n}x): ${de.slice(0, 60).replace(/\n/g, '⏎')}`);
    }
  }
  dizer(contadas > 100 && perdidas.length === 0,
    `as ${contadas} mutações acham o trecho, uma vez cada`,
    perdidas.join('\n      ') || 'poucas mutações encontradas: a busca mudou de forma?');
}

console.log('\n' + (falhas
  ? `✗ ${falhas} problema(s) de sintaxe.`
  : `✓ ${ok} verificações de sintaxe.`));
process.exit(falhas ? 1 : 0);
