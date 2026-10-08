-- ===========================================================================
-- AgendaPro — 35: QUEM LÊ O QUÊ (os consertos de acesso do caça-bug)
--
-- As mesmas regras já escritas no 02_rls.sql, repetidas aqui para QUEM
-- ATUALIZA: o 98_modulos.sql não leva o 02, e sem este arquivo um banco
-- atualizado continuaria com as portas abertas que a instalação nova já não
-- tem. `drop ... if exists` e `create` de novo: colar duas vezes dá no mesmo.
--
-- 1) O CATÁLOGO É DA EQUIPE. Era `tem_acesso()`, que inclui o papel
--    "cliente" — e virar cliente de um salão é livre (`vinc_virar_cliente`).
--    Qualquer conta criava o vínculo com o id que a vitrine mostra e lia o
--    telefone pessoal e a comissão de cada profissional, a comissão de cada
--    serviço, os serviços desligados e a jornada. A cliente escolhe pela
--    `vitrine()` e pelas vistas públicas, que mostram só o que a página mostra.
--
-- 2) A CLIENTE NÃO ESCREVE NA PRÓPRIA FICHA. A ficha nasce e se completa
--    pelo `agendar()` (security definer). Com o UPDATE aberto ela tirava a
--    marca "precisa de confirmação" e reescrevia a anotação do salão; com o
--    INSERT aberto, uma conta criava antes uma ficha com o telefone de outra
--    pessoa e passava a receber as marcações dela.
-- ===========================================================================

drop policy if exists prof_ler on public.profissionais;
create policy prof_ler on public.profissionais for select to authenticated
  using ( public.e_equipe(salao_id) );

drop policy if exists serv_ler on public.servicos;
create policy serv_ler on public.servicos for select to authenticated
  using ( public.e_equipe(salao_id) );

drop policy if exists sp_ler on public.servicos_profissionais;
create policy sp_ler on public.servicos_profissionais for select to authenticated
  using ( exists (select 1 from public.servicos s
                   where s.id = servico_id and public.e_equipe(s.salao_id)) );

drop policy if exists jor_ler on public.jornadas;
create policy jor_ler on public.jornadas for select to authenticated
  using ( exists (select 1 from public.profissionais p
                   where p.id = profissional_id and public.e_equipe(p.salao_id)) );

drop policy if exists pp_ler on public.produtos_profissionais;
create policy pp_ler on public.produtos_profissionais for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and public.e_equipe(p.salao_id)) );

drop policy if exists em_ler on public.estoque_mov;
create policy em_ler on public.estoque_mov for select to authenticated
  using ( exists (select 1 from public.produtos p
                   where p.id = produto_id and public.e_equipe(p.salao_id)) );

drop policy if exists cli_eu_criar  on public.clientes;
drop policy if exists cli_eu_editar on public.clientes;
