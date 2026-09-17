#!/usr/bin/env bash
# ===========================================================================
# Gera supabase/99_remendo.sql — o caminho da cliente, SEM UM COMENTÁRIO
#
# ── POR QUE ESTE ARQUIVO EXISTE ────────────────────────────────────────────
# O 00_tudo.sql tem 166 KB e é feito para ser colado inteiro. Copiado no
# celular, ou por seleção de mouse, as quebras de linha às vezes se perdem —
# e aí cada `--` engole o resto da linha. Quase nada é executado, e o editor
# do Supabase responde "Success. No rows returned", que é verdade: um arquivo
# inteiramente comentado de fato não faz nada.
#
# Aconteceu de verdade. O conferidor mostrou ficha_do_cliente FALTA e
# vitrine_com_galeria FALTA depois de um "Success".
#
# Este remendo é imune: nenhum comentário, nem `--` nem `/* */`. Colado numa
# linha só, roda igual — está testado das duas formas.
#
# É gerado dos MESMOS arquivos-fonte, nunca escrito à mão: divergir do
# 00_tudo.sql seria criar uma segunda verdade sobre o que o banco deve ter.
# ===========================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import os, re

def limpar(sql):
    sql = re.sub(r'/\*.*?\*/', '', sql, flags=re.S)
    fora = []
    for linha in sql.split('\n'):
        c = linha.find('--')
        if c >= 0: linha = linha[:c]
        if linha.strip(): fora.append(linha.rstrip())
    return '\n'.join(fora)

fonte01 = open('supabase/01_schema.sql', encoding='utf-8').read()
fonte05 = open('supabase/05_agenda.sql', encoding='utf-8').read()

def recortar(fonte, cabeca):
    i = fonte.index(cabeca)
    return fonte[i:fonte.index('$$;', i) + 3]

def recortar_ate(fonte, cabeca, rodape):
    i = fonte.index(cabeca)
    return fonte[i:fonte.index(rodape, i) + len(rodape)]

ficha = recortar(fonte05, 'create or replace function public.ficha_do_cliente')
# `so_digitos` é a régua do telefone, e a migração logo abaixo chama ela. Vem
# junto para o remendo não depender de a instalação já ter a versão certa.
digitos = recortar(fonte05, 'create or replace function public.so_digitos(')
# `mesmo_primeiro_nome` decide se uma ficha achada pelo telefone pode virar
# "minha". `ficha_do_cliente` e `agendar` chamam as duas; sem ela aqui o
# remendo instala funções que referenciam algo que não existe.
primeiro = recortar(fonte05, 'create or replace function public.mesmo_primeiro_nome(')
# A migração do telefone da ficha (seção 4.4) não é função: é UPDATE mais a
# trava `cli_tel_so_digitos`. O recortador antigo só sabia achar funções, e por
# isso a correção que arruma os cadastros já gravados ficava fora do remendo —
# quem colava o remendo levava a tela corrigida e o banco sujo do mesmo jeito.
telefone = recortar_ate(fonte05,
                        'update public.clientes\n   set telefone = null',
                        'end $trava$;')
# `arquivado_em` e a trava anti-choque refeita. Sem a COLUNA, tudo o que vem
# depois aqui referencia campo que não existe e o remendo inteiro morre na
# primeira linha — e o painel, que já sabe arquivar, levaria 400 a cada
# gravação. A trava precisa ser refeita junto: a antiga não conhece a coluna,
# e sem isso arquivar não libera o horário, que é metade do que arquivar é.
arquivar = recortar_ate(fonte01,
                        'alter table public.agendamentos\n  add column if not exists arquivado_em',
                        'end $trava_choque$;')
# `horarios_livres` entra no remendo desde que ela passou a costurar as faixas
# de jornada. Sem ela aqui, quem só cola o remendo continua com a lista de
# horários duplicada e fora de ordem — o remendo tem que levar a correção
# inteira, senão ele conserta metade e ninguém percebe qual metade.
#
# ⚠ E ELA VEM DO ÚLTIMO MÓDULO QUE A REESCREVE, NÃO DO 05.
#
# Aqui estava `recortar(fonte05, ...)` escrito à mão, e era um DOWNGRADE: o
# 14_motor.sql reescreve a `horarios_livres()` por cima, e a do 05 é morta
# numa instalação completa. Quem colasse o remendo trocava o motor de verdade
# pela versão anterior — sem erro nenhum, porque as duas compilam.
#
# Foi assim que a antecedência mínima sumiu na primeira tentativa: escrevi o
# ajuste no 05, instalei, e a agenda ignorou. As duas funções existiam, e a
# de número maior era a que valia.
#
# Por VARREDURA, como a vitrine logo abaixo: o módulo que um dia reescrever o
# motor de novo entra nesta conta sozinho.
motores = [f for f in sorted(os.listdir('supabase'))
           if re.match(r'(?!00_)\d\d_.*\.sql$', f) and not re.match(r'9\d_', f)
           and 'create or replace function public.horarios_livres('
               in open('supabase/' + f, encoding='utf-8').read()]
assert motores, 'ninguém define horarios_livres() — o remendo sairia sem o motor'
livres = recortar(open('supabase/' + motores[-1], encoding='utf-8').read(),
                  'create or replace function public.horarios_livres(')

# ⚠ E O MÓDULO DO MOTOR VEM INTEIRO, não só a `horarios_livres()`.
#
# Recortar só ela levava um motor que chama `jornada_costurada()`,
# `ha_choque()` e `ha_bloqueio()` — as três nascidas no MESMO 14_motor.sql, e
# nenhuma delas vinha junto. Num banco que não tivesse o 14, o remendo entrava
# com "Success" e a primeira listagem de horários morria com `function
# public.jornada_costurada(uuid, date) does not exist`. Medido.
#
# É o mesmo defeito dos pacotes logo abaixo, e a mesma cura: quem carrega uma
# função carrega o módulo dela. Recorte é para quando se quer UMA coisa de um
# arquivo grande; aqui se quer o motor, e o motor são as quatro.
motor_inteiro = open('supabase/' + motores[-1], encoding='utf-8').read()

# ⚠ E LEVAR UM MÓDULO INTEIRO TEM UM PREÇO: ele traz as funções que um módulo
# MAIS NOVO reescreveu depois.
#
# O 14_motor.sql define `checar_cabe_agendamento()`, e o 20_corrida.sql a
# reescreve. Colando o 14 sozinho por cima de uma instalação boa, o remendo
# consertava o motor e DESFAZIA a trava da corrida — sem erro nenhum, porque
# as duas compilam. É exatamente o estrago da vitrine descrito abaixo, e eu
# acabei de reintroduzi-lo por outro caminho; quem pegou foi o guardião do
# `sintaxe.test.js`, que cobra que os arquivos de colar levem sempre a ÚLTIMA
# definição de cada função.
#
# Então, para todo módulo que entra inteiro, vem atrás a versão vigente de
# cada função que um módulo posterior reescreveu. `create or replace` duas
# vezes dá no mesmo, e a última é a que fica.
todos_mods = sorted(f for f in os.listdir('supabase')
                    if re.match(r'(?!00_)\d\d_.*\.sql$', f)
                    and not re.match(r'9\d_', f))

def define(arquivo, nome):
    return re.search(r'create or replace function\s+public\.' + nome + r'\s*\(',
                     open('supabase/' + arquivo, encoding='utf-8').read())

def inteiro_com_consertos(arquivo):
    """O módulo, mais a versão VIGENTE do que outro módulo reescreveu depois."""
    fonte = open('supabase/' + arquivo, encoding='utf-8').read()
    saida = [fonte]
    for nome in dict.fromkeys(re.findall(
            r'create or replace function public\.(\w+)', fonte)):
        donos = [f for f in todos_mods if define(f, nome)]
        if donos and donos[-1] != arquivo:
            saida.append(recortar(
                open('supabase/' + donos[-1], encoding='utf-8').read(),
                'create or replace function public.' + nome + '('))
    return saida

# ⚠ A VITRINE VEM DO ÚLTIMO MÓDULO QUE A REESCREVE, E NÃO DO 06.
#
# `vitrine()` é uma função SQL monolítica: não há como acrescentar uma chave
# sem reapresentá-la inteira. Então todo módulo que precise devolver mais
# alguma coisa faz `create or replace` por cima, e o banco fica com a do
# módulo de número MAIOR. Hoje é o 25_loja.sql, que acrescentou os produtos.
#
# Aqui estava `06_vitrine.sql` escrito à mão, e isso fazia o REMENDO DESFAZER
# O MÓDULO: colado depois do 98_modulos.sql, ele reinstalava a versão antiga
# da função e a loja sumia da página da cliente. Sem erro nenhum — o painel
# continuava listando os produtos, e só a página de quem compra ficava vazia.
#
# Medido antes de consertar: instalada a base, a vitrine tinha `produtos`;
# colado o 99_remendo.sql por cima, não tinha mais.
#
# E o remendo é justamente o arquivo de resgate, o que se cola quando o
# 00_tudo.sql chegou picotado. Quem mais precisa dele era quem levava o
# estrago.
#
# Por VARREDURA e não por nome: o módulo que um dia reescrever a vitrine de
# novo entra nesta conta sozinho, sem ninguém precisar lembrar deste arquivo.
#
# ── E OS DOIS VÃO JUNTOS, NESTA ORDEM ─────────────────────────────────────
# O 06 não é só a função: é ele que traz os `revoke` das três views e o
# `grant execute ... to anon, authenticated` sem o qual a página da cliente
# recebe "permission denied". O 25 traz só a função, mais completa.
#
# Mandar apenas o 25 deixaria de fora as permissões; apenas o 06, a loja.
# Então saem os dois, na ordem em que o 00_tudo.sql os instala — e a última
# definição, que é a que o banco guarda, é a completa. `create or replace`
# duas vezes dá no mesmo.
modulos = sorted(f for f in os.listdir('supabase')
                 if re.match(r'(?!00_)\d\d_.*\.sql$', f) and not re.match(r'9\d_', f))
reescrevem = [f for f in modulos
              if 'create or replace function public.vitrine'
                 in open('supabase/' + f, encoding='utf-8').read()]
assert reescrevem and reescrevem[0] == '06_vitrine.sql', \
    'a vitrine() deixou de nascer no 06 — este recorte precisa ser revisto'
vitrines = [open('supabase/' + f, encoding='utf-8').read() for f in reescrevem]

# ⚠ OS PACOTES VÊM INTEIROS, E ANTES DO 09 — senão o remendo instala um
# `agendar()` QUEBRADO.
#
# O 09_cliente.sql, que entra logo abaixo, chama `pacote_que_cobre()` e
# `pacote_fora_do_dia()`. Nenhuma das duas nascia aqui, e o PL/pgSQL não
# reclama na criação: ele só resolve o nome na hora de executar. Então o
# remendo instalava limpo, dizia "Success", e a primeira cliente LOGADA a
# marcar levava `function public.pacote_que_cobre(...) does not exist`.
#
# Medido num banco sem o módulo 27: o remendo entrou com exit 0, o `agendar()`
# ficou lá, e a chamada derrubou.
#
# É o mesmo estrago da vitrine logo acima, e pela mesma razão: este é o arquivo
# de RESGATE, o que se cola quando o 00_tudo.sql chegou picotado. Quem mais
# precisa dele era exatamente quem levava a agenda quebrada.
#
# Vem o módulo inteiro, com `create table if not exists` e `add column if not
# exists`: num banco que já tem os pacotes, não muda nada; num que não tem,
# cria. Por varredura, para o dia em que outro módulo mexer nos pacotes.
#
# ⚠ Quem DEFINE, não quem menciona. Escrevi `'public.pacote_que_cobre(' in ...`
# e isso casava também com o 09_cliente.sql, que apenas CHAMA a função — o
# remendo sairia com o 09 duas vezes, e a ordem certa por acidente.
pacotes = [f for f in modulos if define(f, 'pacote_que_cobre')]
assert pacotes, 'ninguém define pacote_que_cobre() — o remendo sairia quebrado'

# ⚠ E A CONFIRMAÇÃO, PELO MESMO MOTIVO, MAIS UM.
#
# O `agendar()` chama `confirma_automatico()`, e o fechamento de dependências
# lá embaixo puxaria essa função sozinho. Só que o módulo 29 tem também um
# GATILHO — o que manda a mensagem quando o dono confirma — e gatilho não é
# chamada de função: o fechamento não enxerga.
#
# Sem ele, um banco resgatado pelo remendo deixaria o agendamento nascer
# pendente e NUNCA avisaria a cliente quando o salão confirmasse. O pior tipo
# de defeito: tudo instalado, nada acusando, e a cliente esperando uma
# mensagem que não vem.
confirmacao = [f for f in modulos if define(f, 'confirma_automatico')]
assert confirmacao, 'ninguém define confirma_automatico() — o remendo sairia quebrado'

partes = [
    limpar(arquivar),
    limpar(digitos),
    limpar(primeiro),
    limpar(telefone),
] + [limpar(x) for x in inteiro_com_consertos(motores[-1])] + [
    limpar(livres),
    "revoke all on function public.horarios_livres(uuid, date, uuid[]) from public;",
    "grant execute on function public.horarios_livres(uuid, date, uuid[]) to anon, authenticated;",
    limpar(ficha),
    "revoke all on function public.ficha_do_cliente(uuid, text, text) from public;",
] + [limpar(x) for f in pacotes + confirmacao
                for x in inteiro_com_consertos(f)] + [
    limpar(open('supabase/09_cliente.sql', encoding='utf-8').read()),
] + [limpar(v) for v in vitrines]

# ── ⚠ O FECHAMENTO DA CADEIA ──────────────────────────────────────────────
#
# Puxar uma função de módulo tardio puxa as DELA junto, e isso não para no
# primeiro nível. Carregar o 14_motor.sql inteiro obrigou a trazer a
# `checar_cabe_agendamento()` vigente, que é do 20_corrida.sql — e essa chama
# `travar_agenda()`, que também só existe no 20. Remendar caso a caso daria um
# arquivo que fecha hoje e abre de novo no próximo módulo.
#
# Então a conta é feita até parar: enquanto houver função chamada aqui dentro
# que só nasce num módulo 10+, entra a versão VIGENTE dela. No fim, o remendo
# não chama nada que ele mesmo não traga — que é o que o `sintaxe.test.js`
# cobra, e a razão de o guardião existir.
#
# O limite de 12 voltas não é medo de laço infinito: é para uma dependência
# circular aparecer como erro de montagem, e não como um arquivo enorme que
# ninguém entende por que cresceu.
def recortar_re(fonte, nome):
    m = re.search(r'create or replace function\s+public\.' + nome + r'\s*\(', fonte)
    return fonte[m.start():fonte.index('$$;', m.start()) + 3]

def faltantes(texto):
    tem = set(re.findall(r'create or replace function\s+public\.(\w+)', texto))
    fora = []
    for nome in sorted(set(re.findall(r'public\.(\w+)\s*\(', texto)) - tem):
        donos = [f for f in todos_mods if define(f, nome)]
        if donos and all(int(f[:2]) >= 10 for f in donos):
            fora.append((nome, donos[-1]))
    return fora

for _ in range(12):
    pendentes = faltantes('\n\n'.join(partes))
    if not pendentes:
        break
    for nome, arquivo in pendentes:
        partes.append(limpar(recortar_re(
            open('supabase/' + arquivo, encoding='utf-8').read(), nome)))
else:
    raise SystemExit('a cadeia de dependências do remendo não fechou em 12 '
                     'voltas — provavelmente há um ciclo')

saida = '\n\n'.join(partes) + '\n'
assert '--' not in saida, 'sobrou comentário: o remendo perde a imunidade'
open('supabase/99_remendo.sql', 'w', encoding='utf-8').write(saida)
print('supabase/99_remendo.sql —', saida.count('\n'), 'linhas')
PY
