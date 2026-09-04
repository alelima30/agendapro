#!/usr/bin/env bash
# ===========================================================================
# Gera supabase/functions/dist/<nome>.ts — cada função de borda num ARQUIVO SÓ
#
#   bash supabase/montar-funcoes.sh
#
# ── POR QUE ISTO EXISTE ────────────────────────────────────────────────────
# `webhook-mp` e `status-whatsapp` são dois arquivos cada: o `index.ts` e o
# `assinatura.js` ao lado. Essa separação não é organização — é o que permite
# testar a conferência de assinatura no Node, importando EXATAMENTE o mesmo
# arquivo que o Deno importa. É a parte mais crítica das duas funções, e sem
# isso ela seria a única sem teste.
#
# Publicar pela CLI (`supabase functions deploy`) manda a pasta inteira e não
# tem problema nenhum. Mas quem publica pelo PAINEL do Supabase cola código
# numa caixa, e aí dois arquivos viram uma dança que não vale a pena.
#
# Então este script costura: pega o `assinatura.js`, tira os `export`, e
# substitui a linha do import pelo conteúdo dele. O resultado é um arquivo
# que faz a mesma coisa e cola de uma vez.
#
# ── ⚠ O QUE ESTE ARQUIVO NÃO É ────────────────────────────────────────────
# Não é uma segunda versão da função. É uma CÓPIA GERADA, e é regerada a cada
# execução. Editar `dist/` é criar uma segunda verdade sobre o que a função
# faz — o mesmo erro que o projeto evita no SQL, onde 00_tudo.sql e
# 98_modulos.sql saem sempre dos mesmos fontes.
#
# Se precisar mudar a função, mude o `index.ts` ou o `assinatura.js` e rode
# isto de novo.
# ===========================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p supabase/functions/dist

python3 - <<'PY'
import io, os, re

AVISO = (
'/* ===========================================================================\n'
'   GERADO POR supabase/montar-funcoes.sh — NÃO EDITE ESTE ARQUIVO.\n'
'\n'
'   É a costura de index.ts + assinatura.js num arquivo só, para colar no\n'
'   painel do Supabase sem precisar da CLI. Mudou alguma coisa? Mude o fonte\n'
'   e rode o script de novo.\n'
'   =========================================================================== */\n\n')

for nome in sorted(os.listdir('supabase/functions')):
    pasta = os.path.join('supabase/functions', nome)
    idx = os.path.join(pasta, 'index.ts')
    if not os.path.isfile(idx):
        continue

    codigo = io.open(idx, encoding='utf-8').read()
    juntados = []

    # Cada `import { ... } from './arquivo.js';` vira o conteúdo do arquivo,
    # sem os `export` — que só existem para o import funcionar.
    def costurar(m):
        alvo = os.path.join(pasta, m.group(1))
        if not os.path.isfile(alvo):
            raise SystemExit('%s: import de %s que não existe' % (nome, m.group(1)))
        juntados.append(m.group(1))
        dentro = io.open(alvo, encoding='utf-8').read()
        dentro = re.sub(r'^export\s+', '', dentro, flags=re.M)
        return ('/* ── ' + m.group(1) + ', costurado aqui ─────────────────────'
                ' ── */\n' + dentro)

    saida = re.sub(r"^import\s*\{[^}]*\}\s*from\s*'\./([\w.-]+)';\s*$",
                   costurar, codigo, flags=re.M)

    # Garante que não sobrou import local nenhum — um esquecido faz a função
    # subir e morrer na primeira chamada, com "module not found".
    sobrou = re.findall(r"from\s*'\./", saida)
    if sobrou:
        raise SystemExit('%s: sobrou import local' % nome)

    destino = os.path.join('supabase/functions/dist', nome + '.ts')
    io.open(destino, 'w', encoding='utf-8').write(AVISO + saida)
    print('  %-22s %s' % (nome, ('+ ' + ', '.join(juntados)) if juntados
                                 else '(já era um arquivo só)'))
PY
