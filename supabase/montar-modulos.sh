#!/usr/bin/env bash
# ===========================================================================
# Gera supabase/98_modulos.sql — campanhas e convite de equipe,
# SEM UM COMENTÁRIO
#
# ── POR QUE NÃO MANDAR O 00_tudo.sql ───────────────────────────────────────
# Ele tem 170 KB. Copiado no celular, ou por seleção de mouse, as quebras de
# linha às vezes se perdem — e aí cada `--` engole o resto da linha. Quase
# nada é executado, e o editor do Supabase responde "Success. No rows
# returned", que é verdade: um arquivo inteiramente comentado de fato não faz
# nada. Já aconteceu neste projeto, com o conferidor acusando função FALTA
# depois de um "Success".
#
# Este arquivo é imune: nenhum comentário, nem `--` nem `/* */`. Colado numa
# linha só, roda igual — e o tests/rodar.sh cola das duas formas.
#
# É gerado dos MESMOS arquivos-fonte, nunca escrito à mão.
# ===========================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import re

def limpar(sql):
    sql = re.sub(r'/\*.*?\*/', '', sql, flags=re.S)
    fora = []
    for linha in sql.split('\n'):
        c = linha.find('--')
        if c >= 0: linha = linha[:c]
        if linha.strip(): fora.append(linha.rstrip())
    return '\n'.join(fora)

def recortar(fonte, cabeca):
    i = fonte.index(cabeca)
    return fonte[i:fonte.index('$$;', i) + 3]

rls = open('supabase/02_rls.sql', encoding='utf-8').read()

# Os quatro auxiliares de permissão, com o `coalesce` que impede o NULL.
#
# `papel_no_salao()` é NULL para quem não tem vínculo, e `NULL in (...)` é
# NULL. Dentro de uma policy isso barra igual — policy só deixa passar TRUE.
# Dentro de `if not e_gestor(x) then raise`, NÃO: `not NULL` é NULL, o `if`
# não dispara, e a função segue como se a permissão existisse.
#
# As funções do 10_campanhas.sql conferem permissão exatamente assim. Sem
# estes quatro aqui, o módulo instala com um buraco de autorização.
auxiliares = [
    recortar(rls, 'create or replace function public.tem_acesso('),
    recortar(rls, 'create or replace function public.e_equipe('),
    recortar(rls, 'create or replace function public.e_gestor('),
    recortar(rls, 'create or replace function public.ve_agenda_toda('),
]

partes = [limpar(a) for a in auxiliares]

# ⚠ O GATILHO QUE NUMERA A COMANDA, E O REVOKE QUE SÓ É SEGURO COM ELE.
#
# `comanda_numera` era o ÚNICO gatilho do projeto sem `security definer`, e por
# isso rodava como QUEM FEZ a operação — exigindo que a própria dona do salão
# tivesse permissão de executar `proximo_numero`.
#
# Isso importa porque `proximo_numero` ESCREVE e não confere nada: aberta ao
# `anon`, deixava qualquer um inflar a numeração de comanda de qualquer salão.
# Medido: três chamadas anônimas levaram o contador de 1 para 3.
#
# Os dois têm que viajar JUNTOS e NESTA ORDEM. Revogar sem o definer quebra
# abrir comanda na hora — foi o que aconteceu, em produção, quando mandei o
# revoke sozinho.
#
# E entram aqui, e não só no 01_schema.sql, porque o `atualizar.test.sh`
# mostrou que o conserto chegava apenas a quem instala do zero: quem atualiza
# cola o 98_modulos.sql, e ficaria com o gatilho velho e a função aberta.
schema = open('supabase/01_schema.sql', encoding='utf-8').read()
partes.append(limpar(recortar(
    schema, 'create or replace function public.comanda_numera()')))
partes.append('revoke all on function public.proximo_numero(uuid, text)\n'
              '  from public, anon, authenticated;')

# ⚠ O 06_vitrine.sql pega carona aqui, e ele NÃO é um módulo.
#
# É a função que a página da cliente chama para saber tudo sobre o salão, e
# ela mora nos arquivos de base — que só chegam ao banco de produção pelo
# 00_tudo.sql, de 170 KB, que ninguém cola por vontade própria.
#
# O efeito de deixá-la de fora é silencioso e desanimador: o dono escolhe um
# ajuste novo em Aparência, o painel grava, a prévia obedece, e a página da
# cliente continua igual. Aconteceu com `cartoes`, e vai acontecer com o
# próximo ajuste que nascer.
#
# `create or replace function` — colar por cima é seguro, e colar duas vezes
# dá no mesmo.
partes.append(limpar(open('supabase/06_vitrine.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/10_campanhas.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/11_equipe.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/12_relatorios.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/13_cobranca.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/14_motor.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/15_comanda.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/16_comissao.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/17_caixa.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/18_painel.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/19_teto_online.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/20_corrida.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/21_notificacoes.sql', encoding='utf-8').read()))
partes.append(limpar(open('supabase/22_cotas.sql', encoding='utf-8').read()))

saida = '\n\n'.join(partes) + '\n'
assert '--' not in saida, 'sobrou comentário: o arquivo perde a imunidade'
open('supabase/98_modulos.sql', 'w', encoding='utf-8').write(saida)
print('supabase/98_modulos.sql —', saida.count('\n'), 'linhas')
PY
