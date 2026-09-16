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

partes = [
    limpar(arquivar),
    limpar(digitos),
    limpar(primeiro),
    limpar(telefone),
    limpar(livres),
    "revoke all on function public.horarios_livres(uuid, date, uuid[]) from public;",
    "grant execute on function public.horarios_livres(uuid, date, uuid[]) to anon, authenticated;",
    limpar(ficha),
    "revoke all on function public.ficha_do_cliente(uuid, text, text) from public;",
    limpar(open('supabase/09_cliente.sql', encoding='utf-8').read()),
] + [limpar(v) for v in vitrines]
saida = '\n\n'.join(partes) + '\n'
assert '--' not in saida, 'sobrou comentário: o remendo perde a imunidade'
open('supabase/99_remendo.sql', 'w', encoding='utf-8').write(saida)
print('supabase/99_remendo.sql —', saida.count('\n'), 'linhas')
PY
