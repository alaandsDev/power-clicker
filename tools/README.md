# tools/

Ferramentas de desenvolvimento. Nada aqui entra no jogo publicado.
Rode tudo **a partir da raiz do repositório**.

## Dependências

| Para | Instalar |
|---|---|
| scripts `.py` (Python 3.10+) | já vem com o Python |
| `render_map.py` (planta PNG) e `render_map3d.py` | `pip install -r tools/requirements-render.txt` (pillow, numpy) |
| `tools/lune/*` | [Lune](https://github.com/lune-org/lune) **0.8.9**: `rokit install` (já fixado no `rokit.toml`) ou baixe o binário da página de releases do Lune |

Saídas geradas vão para `build/`, que está no `.gitignore` — não versione renders.

## Ferramentas do projeto

| Comando | O que faz |
|---|---|
| `python tools/audit.py` | Auditoria estática: remotes, APIs depreciadas, `print` solto, textos faltando/duplicados, limpeza por jogador |
| `python tools/render_map.py --check` | Valida a planta pelos configs (áreas, pads, corredor em ordem, altura do paredão). Sem `--check` gera `build/mapa_planta.png` |
| `python tools/simulate_economy.py --hours 2` | Simulação de economia por perfil de jogador |
| `python tools/check_world_layout.py` | Valida as zonas antigas (desligadas por `ZoneConfig.Build`) |
| `python tools/build_place.py [--studio-mock]` | Gera `build/PowerClicker.rbxlx` sem Rojo |
| `python tools/publish_place.py` | Publica via Open Cloud (chave em variável de ambiente; **nunca** no repositório) |

## Validação fora do Studio (Lune)

`tools/lune/env.luau` monta `src/` como instâncias Roblox dentro do Lune e
carrega os módulos de verdade (com stubs para serviços que só existem no
Roblox). Os scripts abaixo usam esse ambiente. Todos saem com código 1 quando
encontram problema.

```bash
lune run tools/lune/run_tests.luau      # specs de src/server/Tests (o mesmo TestRunner do Studio)
lune run tools/lune/check_world.luau    # WorldBuilder + geometria do mapa
lune run tools/lune/check_hud.luau      # layout do HUD em 5 resoluções/entradas
lune run tools/lune/check_sword.luau    # espada equipada aplicada ao personagem (SwordService real)
lune run tools/lune/export_map.luau     # mapa -> build/map_parts.json
python tools/render_map3d.py            # build/map_parts.json -> build/render/mapa_*.png
```

- **run_tests** — roda os ~225 testes. Três falhas conhecidas (anteriores ao
  polimento, ver `TESTING.md`) são listadas à parte e não derrubam o código de
  saída; qualquer falha nova derruba.
- **check_world** — constrói o mundo inicial e verifica chão sem buracos, borda
  da ilha sem frestas (360°), paredão inescalável, caminho livre até o
  corredor, piso contínuo e as 10 barreiras em linha e em ordem (cada fileira
  com detalhes visuais sem colisão), praça final fechada e portal de frente
  sem obstrução; constrói todos os mundos do `WorldConfig` e imprime a
  contagem de instâncias. **Spawn:** SpawnLocation e marcador no eixo da
  avenida olhando +X, existência do `SpawnCameraController`, e — simulando a
  mesma câmera que ele monta — placa, espada e barreira 1 dentro do quadro e
  sem nada opaco no meio. (A versão anterior só comparava a direção do
  marcador e deu falso positivo: no Roblox a câmera não acompanha o
  `PivotTo` do servidor.)
- **check_sword** — roda o `SwordService` de verdade com dados/rede/jogadores
  simulados: jogador novo (personagem antes dos dados e mão chegando depois),
  respawn, troca pelo remote, reentrada, dados migrados, equipada inválida ou
  não possuída (cai para a inicial) e corridas (uma espada só, nada na
  mochila). O `EquipTool` simulado imita o Studio: sem mão, a espada se perde.
- **check_hud** — inicializa os controllers do cliente na ordem do
  `ClientBootstrap` e mede o HUD com tudo visível (pior caso, incluindo
  tutorial e avisos): sem sobreposição, tudo dentro da tela; faixa de
  feedback com no máximo 6 números de clique e 3 do automático, cujo trajeto
  não cruza rodapé, botão, menu nem moedas e não sobe sobre o personagem.
  Resoluções: PC 16:9, toque 16:9, celular em paisagem, tablet 4:3 e
  ultrawide.
- **export_map + render_map3d** — render 3D aproximado (vista ao nascer, visão
  geral, entrada do Caminho, de cima). Primitivas chapadas, sem texturas: serve
  para composição e poluição de texto, não para acabamento.

### Requer validação no Studio (nenhuma ferramenta daqui afirma isto)

- Câmera real ao nascer e ao respawnar (o `SpawnCameraController` move a câmera
  depois do teleporte; o Lune só checa a geometria que essa câmera veria).
- Legibilidade real da placa (SurfaceGui), da espada do portão e das barreiras.
- Espada soldada na mão, visível, seguindo o braço, e replicada aos outros.
- Tamanho real de texto no HUD (TextScaled, fontes) e sensação de leitura.

### Limites (isto NÃO substitui o Studio)

- Física, colisão do personagem, câmera real, toque, replicação, DataStore,
  compras e sons não existem aqui.
- A geometria é checada por amostragem de pontos em peças sólidas; o
  resolvedor de layout do HUD não mede texto nem `AutomaticSize` complexo.
- `Random` é um gerador próprio: a decoração aleatória sai diferente da do
  Roblox (a geometria estrutural não depende dela).
- O `CFrame.lookAt` do Lune 0.8.9 tem o eixo Z espelhado; o `env.luau`
  substitui por uma versão correta para os módulos do jogo.
- `ShopController`, `VipController`, `InteractController` e
  `PetFollowController` usam serviços sem stub e são pulados no `check_hud`.

### Arte

`upload_assets.py`, `prepare_web_art.py`, `remove_checker.py`,
`remove_flat_bg.py` — pipeline das imagens em `art/`.
