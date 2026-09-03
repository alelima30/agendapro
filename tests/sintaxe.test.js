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
                 'endereco.js', 'config.js', 'sw.js'];

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

console.log('\n' + (falhas
  ? `✗ ${falhas} problema(s) de sintaxe.`
  : `✓ ${ok} verificações de sintaxe.`));
process.exit(falhas ? 1 : 0);
