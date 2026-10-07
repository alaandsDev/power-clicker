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
| `python tools/simulate_economy.py --hours 2` | Simulação de economia por perfil de jogador (legado; a auditoria canônica é `tools/lune/econ_audit.luau`) |
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
lune run tools/lune/check_corridor.luau # loop do Caminho do Poder (WallService real sobre o mapa)
lune run tools/lune/check_cuts.luau     # vitrine dos Cortes + camada de corte do golpe (mesma config)
lune run tools/lune/check_swing.luau    # postura de combate + golpe da espada a cada hit, sincronizado com o corte
lune run tools/lune/check_fx.luau       # efeitos de combate: impacto, rachaduras, quebra, câmera, números
lune run tools/lune/check_polish.luau   # sem luz constante no personagem; pets menores em formação atrás
lune run tools/lune/check_station.luau  # protótipo: estação de Melhorias como máquina (orçamento, posição, prompt, movimento)
lune run tools/lune/export_map.luau     # mapa -> build/map_parts.json
lune run tools/lune/check_zones.luau    # zonas dormentes (Build = false) não dão bônus pela posição
lune run tools/lune/check_econ_model.luau # fidelidade do simulador da auditoria de economia
lune run tools/lune/econ_audit.luau     # auditoria da progressão 1→10 (Markdown; seções e runs=N, scenario=A|B|C)
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
- **check_corridor** — o `WallService` real sobre o mapa gerado, com vários
  jogadores no mesmo servidor e um CLIENTE simulado por jogador (ambiente
  próprio, mapa próprio e o `WallController` real recebendo só o `WallState`
  daquele jogador). Barreiras individuais: golpe de A não muda o HP de B; só
  quem quebrou vê a passagem e tem a fileira sem colisão no cliente; quem
  atravessa sem ter quebrado volta para a frente da barreira e não ganha nada;
  quem entra depois recebe o próprio estado; sair e voltar mantém o progresso
  salvo; as peças do servidor nunca mudam. Mais o loop de sempre: ordem, golpe
  de frente/trás, os 3 pads (normal, x2 = 2x, Voltar), prêmio volta para a
  praça, gemas da primeira vez uma vez só, não refaz em cima do jogador, não
  dá para contornar/pular, e a distância/tempo de volta do spawn. (Adapta só
  no carregamento: `.Position` -> `.CFrame.Position`, janela de 0,5 s e o
  PivotTo do "levar de volta".)
- **check_swing** — o golpe procedural da espada (`SwordSwing` +
  `SwordSwingController`) e o `SlashController` reais sobre um personagem R15
  montado no Lune, com relógio simulado: hit dispara o golpe; 9 hits/s por
  30 s sem acumular instâncias nem criar Animation; combo estrito A→B→C;
  o golpe volta para a postura (e, sem espada, o C0 volta
  exatamente ao original); troca de skin e respawn no meio do golpe; corte
  (CutFx) desenhado no impacto e na diagonal do golpe; "Efeitos reduzidos"
  mantém o golpe; outros jogadores golpeiam perto e nada longe; o golpe não
  lê dano/economia. POSTURA DE COMBATE (bloco P): espada baixa e para o lado
  (nem vertical, nem cruzando o corpo), braço esquerdo afastado, cabeça para
  frente, respiração sutil; andando/correndo/pulando vira "carregar";
  transições sem tranco (máx. por quadro) em parado↔andando, golpe→postura,
  equipar/guardar, trocar de lâmina e respawn; nenhuma skin encosta a ponta
  no chão (modelo no plano do corpo); R6 e Joint Upgrade; outros jogadores
  perto também ficam na postura. COMBO VISUAL (bloco K): A, B, C e volta ao
  A; spam a 9/s e Auto Click (no ritmo dos ticks do servidor, 30 s sem
  acumular) seguem o ciclo; clicando com o Auto ligado não há golpe extra;
  o Corte segue a direção (A "/", B "\", C vertical) e o sentido de varrer,
  mantendo cor/riscos; o C só fica um pouco mais marcado (Corte 1,15×,
  rastro mais longo) com a mesma duração; recomeça no A após 1,2 s parado,
  no respawn e na troca de espada; R6/R15/Joint Upgrade; reduzidos mantêm o
  movimento; ponto do impacto deslocado (A esq., B dir., C centro) na mesma
  face; nada do combo conhece dano/Power e o ritmo do servidor não muda.
  RUNTIME (bloco R), contra falso positivo: o harness simula o quadro do
  Roblox — "Animator" reescrevendo o `Transform` todo quadro (com o
  "toolnone" do Roblox entrando com fade), a pose no `PreSimulation`, as
  juntas resolvendo as PARTES e a verificação no `PostSimulation` — e mede
  onde o braço e a mão de verdade ficaram: postura longe do toolnone e igual
  com/sem ele; A/B/C com a mão em lugares diferentes e na direção certa;
  sem acumular quando nada reescreve o `Transform`; Motor6D trocado por
  AnimationConstraint depois do spawn (rig remonta); algo reescrevendo o
  `Transform` depois da camada (detectado, troca para Offset); logs
  `[SwordRuntime]`; teste mínimo (`workspace.SwordMinimalTest`).
- **check_fx** — os controllers reais do combate (`WallController`,
  `SwordSwingController`, `SlashController`, `CombatFxController`) sobre o
  mapa, com um "servidor" mínimo mandando o `WallState` do jogador e relógio
  simulado: golpe, corte e impacto no mesmo instante e no ponto de contato
  (combo: A à esquerda, B à direita, C no centro e marcado, sem crítico);
  tema por barreira; evolução dos Cortes; rachaduras pelo HP; hit forte,
  câmera por nível, hit stop e quebra final/Colosso; números agrupados (≤ 4);
  "Efeitos reduzidos"; golpe de outro jogador sem impacto na minha barreira;
  spam 9 hits/s (30 s + 6 barreiras x Cortes 1/2/4/8, ligado e reduzido) sem
  acumular instâncias, emissores ou luzes; respawn e troca de espada.
- **check_station** — PROTÓTIPO da estação de Melhorias como máquina
  (`World/StationMachines` + `StationFxController`): mesmo prompt de antes
  (um só, `OpenPanel = "Upgrades"`); orçamento (≤ 130 peças, nenhuma luz,
  nenhum BillboardGui, partículas poucas); escala 2–3x o avatar; placas
  físicas viradas para a praça com distância de leitura limitada; pegada
  dentro do piso da área, fora das calçadas/caminho/spawn e longe da Loja;
  plataforma de interação na frente e ao alcance; reverter pelo LobbyConfig
  (sem `Style`) volta o quiosque; no cliente núcleo/anéis giram, setas
  sobem, técnico olha para quem chega, nada roda longe nem é criado.
  Polimento (bloco P): ≤ 120 peças; núcleo maior e em camadas (anel
  frontal → núcleo → halo traseiro com braços); anéis medidos em toda a
  volta sem entrar em coluna/bacia/tampa/halo; colunas com painel
  embutido; console-terminal inclinado com tela; doca no piso (plataforma
  rente, rampa, seta gravada); hierarquia da placa; gema da Loja 30% menor
  com a Loja acessível; estado "jogador no ponto de uso" (núcleo/setas um
  pouco mais rápidos, tela responde, volta ao sair).
  `render_map3d.py` gera `_upgrades_{far,mid,near,side}.png`.
- **check_polish** — nenhuma luz constante presa ao personagem (auras de
  poder e cosméticas, pets); espada parada contida (luz baixa, rastro
  desligado, skins neon com fio de energia); pets ~25% menores e em formação
  atrás do jogador (1–8 pets, simétrica, sem sobreposição), seguindo com
  suavização, contornando o personagem numa virada de 180° e reaparecendo
  na vaga depois de um teleporte. (Os chips de buff e o botão AUTO são
  medidos no `check_hud`; o brilho da espada no golpe no `check_fx`.)
- **check_cuts** — a vitrine dos pads de Corte (`CutShowcaseController`) e a
  camada de corte do golpe (`SlashController`) de verdade sobre o mapa: cada
  corte tem pad, pedestal, orbe e placa sem colisão e o prompt de compra
  igual; ZONA LIVRE da avenida (`LobbyConfig.CutStations`, mínimo de 12
  studs): nenhum pad, pedestal, placa, orbe, prompt, risco ou faísca da
  demonstração entra nela; fileiras simétricas, dentro do adro e sem
  encostar em outra peça do lobby; prompts alcançáveis da borda da avenida;
  da câmera do spawn, nada das estações cobre a janela avenida → barreira 1;
  vistas da avenida (43 câmeras), placas e nomes de estações
  diferentes não se sobrepõem na tela; estados ATIVO/COMPRADO/DISPONÍVEL/
  BLOQUEADO; vitrine e golpe tocam a MESMA receita (`CutVisuals.For`); pausa
  de 1,5–3 s entre demonstrações; nada toca longe, sem personagem ou com
  efeitos reduzidos; peças não acumulam em 3 min simulados, sem conexões
  novas por passo; nada vai ao servidor nem muda dados. (Desliga só o laço
  de fundo do controller e usa relógio simulado.)
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
- Combate: golpe por cima da pose do Animator, rastro, impacto, rachaduras,
  quebra, tremor de câmera (enjoo), números na tela e FPS com 2+ jogadores.
- Vitrine dos Cortes e camada de corte do golpe: cor, brilho (Neon/PointLight),
  faíscas (ParticleEmitter), varredura do risco e leitura real das placas
  (SurfaceGui) e nomes (BillboardGui) — o `check_cuts` mede só geometria e lógica.

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
