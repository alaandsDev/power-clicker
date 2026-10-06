# Testing

## Automated (unit tests)
They run automatically on every **Play in Studio** (`DevConfig.RunTestsInStudio`). Output:
```
[TESTS] N passed, 0 failed (17 specs, …)
```
Failures are printed as `[TESTS][FAIL] Spec > describe > test: message`.

| Spec | Covers |
|---|---|
| RateLimiter | burst, refill, per-key isolation, spam simulation (1000 req/s), clock going backwards |
| Guard | NaN/inf, ranges, integers, UTF-8, unknown keys, extra args |
| TableUtil | deep copy, reconcile (no overwrite, no shared refs), freeze |
| EconomyFormulas | monotonic costs, max level, negatives, huge levels capped, combo clamp, sanitize |
| ConfigValidator | shipped configs valid, plus detection of 7 kinds of broken config |
| SignalTry | signal delivery/disconnect/once, isolation of erroring handlers, Try |
| Migrations | sequential steps, missing step, failing step, future/invalid versions |
| DataSanitizer | NaN/inf repair, Instances/functions removed, arrays kept contiguous, cycles |
| PlayerDataStore | new player, existing player, transient failure retry, **persistent failure ≠ new player**, live lock respected, lock handoff, stale lock takeover, future version untouched, corrupt untouched, cancel on leave, player isolation, lock refresh, **no write after lock lost**, idempotent release, save retry/failure, missing record |
| FormulasPhase2 | NumberFormat, ComboLogic (cap/timeout/decay), PowerFormula (unknown/invalid layers ignored, NaN base, cap) |
| Economy | CurrencyLogic (invalid amounts, never negative, cap, corrupted balance), UpgradeLogic (no funds, cost, max level, unknown id, gems vs power, corrupted level, effects), RebirthLogic (refuse, reset/keep/reward, growing cost, max) |
| ClickPatternDetector | flags zero-jitter fast clicking; not human jitter, not slow clicking; one signal per window |
| Localization | same keys in every locale, same placeholders, every upgrade/world/pet/egg/rarity translated, locale resolution, number separators |
| Pets | PetLogic (unique uids, stale counter safe, unknown pet/variant, inventory cap, equip ownership/dup/cap, slot upgrades+passes, multiplier ignores unknown, equip best, lock/delete, sanitize), EggOdds (sum 1, luck shifts to rare, clamp, pick boundaries, 100k-roll distribution), EggLogic (no funds, charge+roll+stats, full inventory refused before charge, unknown egg/locked world, mythic counter) |
| Worlds | unlock requires rebirths/cost/previous world, disabled/unknown/already, travel rules, sanitize, eggs only in own world |
| Retention | BoostLogic (stack cap, invalid, highest-per-category, tick/expire), RewardLogic (combo grant, atomic on full inventory/invalid entry), DailyRewardLogic (first, interval, cycle loop, streak reset, clock backwards, valid rewards), QuestLogic (cap, claim once, daily reset), AchievementLogic (thresholds, worlds, idempotent), CodeLogic (normalize/format, validate) |
| LevelFormula | nível pela curva geométrica, limites exatos de cada nível, lixo (NaN/negativo), número gigante sem travar |
| CutLogic | requisito de vitórias, compra única, melhor corte vale, curva sempre crescente, registro corrompido |
| AuraRuneLogic | auras (posse, requisito, velocidade dentro do teto), runas (slots, cópias, multiplicador, sorteio por mundo, reparo) |
| CosmeticLogic | espadas e auras cosméticas: desbloqueio por renascimento/vitória/estágio, equipar só o que é seu, tetos de partícula, reparo |
| Purchases | receipt ledger idempotency, FIFO trimming, one-time offers, NaN robux, unconfigured ids unresolvable, paid pets bypass inventory cap, all products have valid rewards |

Tests use only pure modules or the explicitly named `MockDataStoreBackend`. They never touch a real DataStore.

Add a test: create `src/server/Tests/<Area>/<Name>.spec.luau` returning `function(T) ... end` (see TestRunner).

## Manual — Phase 1 checklist

| # | Scenario | How | Expected | Status |
|---|---|---|---|---|
| 1 | Boot + tests | Play `PowerClicker_StudioMock.rbxlx` | `Configs valid`, `booted 3 services`, `[TESTS] … 0 failed` | ✅ Phase 2: 102/102, 0 failed (12 specs) |
| 2 | New player | same | `created new data (sessions=1)`, client `Data loaded` | ✅ |
| 3 | Autosave | wait 60 s | `user=… saved` | ✅ |
| 4 | Leave / close | Stop | `saved + released` | ✅ |
| 5 | Script Analysis | Window › Script › Analysis | 0 errors, 0 type warnings from our scripts | ✅ 0 errors / 0 warnings (strict) |
| 6 | Real DataStore unavailable | Play `PowerClicker.rbxlx` on an unpublished place | player kicked with the "couldn't load" + Studio hint; **no data created** | ⏳ |
| 7 | Real DataStore | publish + enable API access, play twice | second session `loaded data (sessions=2)` | ⏳ |
| 8 | Multiplayer | Test › Clients and Servers › 2–5 players | every player loads; data isolated | ⏳ |
| 9 | Wrong-direction remote | Client command bar: `game.ReplicatedStorage.Remotes.DataChanged:FireServer()` repeatedly | ignored; AntiExploit logs (Debug) | ⏳ |
| 10 | Remote spam | client: `for i=1,100 do game.ReplicatedStorage.Remotes.ClientReady:FireServer() end` | only 2 accepted; rest `RateLimited` | ⏳ |
| 11 | Invalid args | client: `...ClientReady:FireServer(0/0, {}, "x")` | dropped, `InvalidArguments` | ⏳ |

## Manual — Phase 2 checklist (Studio, `PowerClicker_StudioMock.rbxlx`)

| # | Scenario | How | Expected |
|---|---|---|---|
| 2.0 | Join | Play | button shows LOADING... until data arrives, then CLICK!; server logs `snapshot sent (~0.2s after join)` |
| 2.1 | Click | click the button | floating "+1", Power rises, combo counts up |
| 2.2 | Combo decay | stop clicking ~2 s | combo drops, then disappears |
| 2.3 | First upgrade | reach 20 Power, Upgrades, Click Strength | cost charged, "+2 per click", badge "!" when affordable |
| 2.4 | No funds | buy without funds | toast "Not enough!", nothing charged |
| 2.5 | Overdrive | click 400x or Debug > Overdrive | orange button, "OVERDRIVE x3 20s", per click x3, then 10s cooldown |
| 2.6 | Rebirth refused | Rebirth panel below cost | "Not enough Power"; server refuses if forced |
| 2.7 | Rebirth | Debug > Rebirth | flash, toast "+10 Gems", Power 0, Power upgrades reset, Gem upgrades kept, multiplier x1.5 |
| 2.8 | Gem upgrade | Debug > +100 Gems, Gems tab, Eternal Power | multiplier rises, kept after rebirth |
| 2.9 | Auto click | Debug > Auto Click | "+X (auto)" 4x/s without clicking, no combo |
| 2.10 | Click spam | command bar (client): `for i=1,200 do game.ReplicatedStorage.Remotes.Click:FireServer() end` | only ~burst accepted; AntiExploit logs (Debug level) |
| 2.11 | Bad args | `game.ReplicatedStorage.Remotes.BuyUpgrade:InvokeServer("FreeMoney")` | `{Ok=false, Code="InvalidRequest"}` |
| 2.12 | Debug in live | publish, join as non-admin | no debug panel; DebugCommand returns `Forbidden` |
| 2.13 | Mobile | Studio device emulator (phone) | button large, panels fit, safe area respected |
| 2.14 | Console | gamepad R2 / X | clicks register |
| 2.15 | Multiplayer | Test > 2-3 players | each has own Power/combo/overdrive |

## Manual — Phase 3 checklist

| # | Scenario | How | Expected |
|---|---|---|---|
| 3.1 | Egg shop | Ovos panel | 3 eggs, prices, chances per pet colored by rarity, "Sorte: x1" |
| 3.2 | No funds | hatch Ovo Básico with 0 Power | toast "Saldo insuficiente!", nothing charged |
| 3.3 | Hatch | Debug +1M Power, hatch | shake + reveal with rarity color, Power charged 2K, pet in Pets panel |
| 3.4 | Legendary/Mythic | Debug +100 Gems several times, Ovo Místico | colored full-screen flash; other players get a toast |
| 3.5 | Equip | Pets panel, tap a pet, Equipar | ✅ on card, "Equipados 1/3", per-click multiplier rises, ball follows the character |
| 3.6 | Equip limit | equip 4 pets | "Todos os espaços de pet estão ocupados!" |
| 3.7 | Equip best | button | strongest 3 equipped |
| 3.8 | Lock/Delete | lock, then try delete; unlock, delete twice (confirm) | locked pet can't be deleted; deleted pet removed/unequipped |
| 3.9 | Pet slots upgrade | Gems tab, Espaços de Pet | "Equipados x/4" |
| 3.10 | Inventory full | 50 pets, hatch | "Inventário de pets cheio!" and NO charge |
| 3.11 | Fake uid | client: `Remotes.PetAction:InvokeServer("Equip","99999")` | `NotOwned` |
| 3.12 | Fake egg | client: `Remotes.HatchEgg:InvokeServer("GoldenEgg")` | `InvalidRequest` |
| 3.13 | Hatch spam | invoke HatchEgg 20x fast | only ~1 per 0.75 s accepted |
| 3.14 | Multiplayer | 2 players | each sees the other's pets following them |

## Manual — Phases 4–5 checklist

> Os itens 4.x exigem ligar `GameConfig.Dev.EnableAllWorldsInStudio = true` (desligado por padrão para o Studio mostrar o jogo publicado). Desligue de novo depois.

| # | Scenario | How | Expected |
|---|---|---|---|
| 4.1 | Worlds panel | Mundos | 5 worlds; Treino "Você está aqui"; others "Bloqueado" (Studio: all enabled) |
| 4.2 | Unlock refused | City without rebirths | "Renascimentos insuficientes!" |
| 4.3 | Unlock | Debug Rebirth x5 + Gems, Desbloquear City | cost charged, toast, button "Viajar" |
| 4.4 | Travel | Viajar | character teleported to the City platform; per-click multiplier x10 |
| 4.5 | Eggs per world | open Ovos in City | "Não há ovos neste mundo." |
| 4.6 | Rejoin | leave in City and rejoin | spawns in City |
| 5.1 | Daily | Prêmios, RESGATAR | day 1 reward; button shows countdown; badge disappears |
| 5.2 | Next day | Debug "Pular dia" | day 2 claimable; after claim streak 2 |
| 5.3 | Device clock | change the PC clock | nothing changes (server clock only) |
| 5.4 | Codes | RELEASE, then again, then "xyz" | +25 Gemas; "Você já usou esse código."; "Código inválido." |
| 5.5 | Quests | click 100x | toast "Missão concluída", badge; Resgatar grants Gems |
| 5.6 | Daily quests | Debug "Pular dia" | daily quests reset |
| 5.7 | Achievements | first click / 1K clicks / first rebirth | toast + Gems automatically |
| 5.8 | Boosts | Debug "Boosts" | HUD "2x Power 15:00" countdown; per-click x2; expires |
| 5.9 | Ranking | Ranking panel | Studio: local ranking note; your row highlighted |
| 5.10 | leaderstats | player list | Power and Rebirths columns |

## Manual — Phase 6 checklist

| # | Scenario | How | Expected |
|---|---|---|---|
| 6.1 | Shop | Loja panel | Offers/Passes/Items tabs; every button "Em breve" while ids are 0 |
| 6.2 | Prompt refused | client: `Remotes.PromptPurchase:InvokeServer("GemsSmall")` with id 0 | `NotAvailable` (no prompt) |
| 6.3 | Passes (Studio) | Debug "Teste: passes" | per-click x2.5 (2x × VIP 1.25), luck x2, "Equipados x/6", auto click on, VIP Crown Cat pet once, [VIP] chat tag |
| 6.4 | Starter pack (Studio) | Debug "Teste: pacote" twice | first: pet + 250 Gemas + boosts; Offer shows "Adquirido ✓"; second grant also works (debug bypasses the prompt) and uses a new purchase id |
| 6.5 | Auto click toggle | Passes tab, toggle | ON/OFF; without the pass → `NotOwned` |
| 6.6 | Real product (live test server) | configure ids, buy GemsSmall | gems once; server log `granted GemsSmall (purchase …)`; rejoin → no re-grant |
| 6.7 | Receipt retry | buy while DataStore throttled (or kick right after purchase) | granted exactly once after rejoin |
| 6.8 | Game pass (live) | buy 2x Power | benefit applies immediately (PromptGamePassPurchaseFinished) and after rejoin (UserOwnsGamePassAsync) |

## Manual — Phase 7 checklist

| # | Scenario | How | Expected |
|---|---|---|---|
| 7.1 | Loading | Play | branded "⚡ POWER CLICKER ⚡ / Carregando..." until data arrives, then fades |
| 7.2 | Onboarding | Debug "Resetar dados" | banner "Clique no botão…", then Melhorias pulses, then Ovos, Pets, Renascer; "Tutorial concluído!" at the end |
| 7.3 | Settings | Ajustes | toggles persist after rejoin (real DataStore) |
| 7.4 | Reduced effects | enable | no floating numbers / ring / flashes / Overdrive glow |
| 7.5 | Panels | open any panel | quick pop-in animation |
| 7.6 | Mobile | Studio device emulator (phone, landscape) | everything fits; big button; toasts don't cover the button |

## Manual — World maps

| # | Scenario | How | Expected |
|---|---|---|---|
| W.1 | Training map | Play | grass island: trees, fence, flowers, dummies, sunny sky, no force-field bubble |
| W.2 | Egg stands | walk to the 3 eggs, press E / tap | Ovos panel opens; stand shows name + price |
| W.3 | Rebirth altar | press E | Renascer panel opens. (O portal de Mundos só existe com algum mundo além do Treino habilitado — por padrão, não aparece.) |
| W.4 | Other worlds (Studio, com `EnableAllWorldsInStudio = true`) | Debug Liberar mundos, travel to each | City at sunset with lit windows, Volcano with lava and a red sky, Space with stars and asteroids, Galaxy with crystals and rings |
| W.5 | Fall off the island | walk off the edge | respawn at the current world's spawn |
| W.6 | Performance | Studio MicroProfiler / Stats | stable FPS; each world is ~300 anchored parts |

## Static audit
`python tools/audit.py` checks remotes (handlers/listeners), deprecated APIs, stray prints, localization keys and per-player cleanup. Run it before every build; it must print `OK`.

## Later phases (planned)
Click (normal, spam, multiple players, reconnect) · Pets (add, equip, unequip, full inventory, nonexistent pet, duplication) · Eggs (no funds, funds, RNG distribution over 100k rolls, spam) · Rebirth (below requirement, at requirement, reward, reset, many) · Monetization (gamepass, product, **repeated receipt**, failed processing) · Security (spam, invalid args, negatives, huge numbers, wrong types, out-of-order calls).

---

## Lista de teste manual (reestruturação: Caminho do Poder)

O que precisa ser verificado dentro do Roblox Studio ou no jogo publicado —
nada disto é coberto pelos testes automáticos, porque depende de física,
câmera, toque e replicação.

### Jogador novo
1. Entrar com uma conta sem dados: nasce na praça, com o Corte 1 e a Lâmina de Ferro.
2. Segurar o clique: ganha Power contínuo, arco aparece na cor da espada.
3. Barra de Nível enche e sobe de nível.
4. Andar pelo caminho de pedra até a boca do corredor.
5. Quebrar a barreira 1 (3 fileiras), pegar o pad e ser teleportado à praça.

### Jogador existente (dados antigos)
6. Entrar com a conta que já jogava: **não pode ser expulso nem resetado**.
7. Conferir que gemas, pets, melhorias e renascimentos continuam lá.
8. Quem estava num mundo dormente (Cidade/Vulcão/Espaço/Galáxia) é trazido para a praça, não cai no vazio.
9. Espadas e auras cosméticas já conquistadas aparecem desbloqueadas na entrada.

### Corredor
10. As 10 áreas estão em linha reta, no mesmo nível, sem escada.
11. Cada barreira tem arco, e dá para ver a luz do tema seguinte ao fundo.
12. A faixa do corredor aparece ao chegar perto e some no lobby.
13. O pad de voltar funciona em todas as áreas.
14. A barreira 10 é visivelmente maior e o portal diz "em breve" (e não teleporta).
14b. A praça final termina num maciço de rocha: não dá para andar além do portal nem cair do fim do mapa.

### Treino (Campo de Treinamento — ver bloco TR)
15. Ficar no pedestal de cada alvo liberado: o aviso "Treinando" aparece com o ganho por segundo.
16. Pular ou sair do pedestal para o ganho.
17. Alvo com requisito de Renascimentos não paga antes do requisito e mostra "Você precisa de X Renascimentos para treinar aqui."

### Economia
18. Comprar corte nos pads da entrada do Caminho do Poder (E) — preço e requisito conferem.
19. Renascer: a tela mostra requisito, quanto falta, ganho e **o que fica**.
20. Após renascer: Power zera, pets/gemas/vitórias/cortes/espadas/auras/progresso do Caminho permanecem.
21. Ovo do Caminho (id `TowerEgg`) só abre depois do estágio 5; Ovo do Colosso depois do 10.

### Interface
22. Moedas na horizontal no topo, sem sobrepor nada.
23. Menu: quatro botões principais maiores (Melhorias, Pets, Ovos, Renascer); "Mais" abre um painel flutuante em grade com os secundários e vira ✕.
24. Painel "Progresso" mostra os 10 estágios e marca o atual.
25. Testar em celular (375x812), tablet e PC: nada cortado, botão de clique alcançável com o polegar.

### Limites e segurança
26. Tentar sair da ilha pulando nos paredões de rocha: não dá para subir (face vertical, no mínimo 58 studs).
27. Cair do corredor: não existe vão entre a ilha e a entrada.
28. Dois jogadores no mesmo servidor quebrando a mesma barreira: ambos recebem o pad, uma vez cada.

---

## Testes automáticos: falhas que já existiam

Rodando os 225 testes fora do Studio (Lune), 3 falham **também na `main`**
(nada a ver com o polimento). Ao dar Play no Studio você deve ver
`[TESTS] 222 passed, 3 failed`:

| Spec | Causa |
|---|---|
| EconomyFormulas › RebirthMultiplier | o teste ainda espera o multiplicador linear `1 + 0,5R`; a Fase H mudou para `1,75^R` |
| AuraRuneLogic › "drops nothing..." | o teste espera que um sorteio de 0,999999 não dê runa, mas `RuneConfig.Drop.MaxChance = 1` |
| LevelFormula › "levels up exactly on the step cost" | arredondamento: `TotalFor(2)` dá 117,50000000000004 e o nível 2 vira 1 Power "atrasado" |

Não foram corrigidos (economia/fórmulas fora do escopo do polimento).

## Lista de teste manual — polimento (HUD + lobby + Caminho)

Nada disto foi testado no Roblox Studio: foi validado por compilação, testes
unitários, auditoria e simulação geométrica/de layout fora do Roblox. **Precisa
de Play no Studio.**

### Antes de começar
P.1. Conferir que `GameConfig.Dev.EnableAllWorldsInStudio = false` (padrão novo): só o mundo inicial é construído, sem os mundos 2–5.
P.2. Output sem erros vermelhos no boot; `[TESTS] 222 passed, 3 failed` (ver tabela acima).

### Lobby
L.1. Ao nascer **e ao respawnar**, a câmera fica atrás do personagem, no eixo da avenida, enquadrando o portão (placa CAMINHO DO PODER legível, espada inteira no alto) e a barreira 1 ao fundo. (Correção de rodada de Studio: o servidor teleporta com PivotTo e a câmera padrão não acompanhava; agora o SpawnCameraController alinha a câmera depois do teleporte.)
L.2. Não existe portal "🌍 Mundos" atrás do spawn.
L.3. Áreas sem discos coloridos saturados; cada uma tem estandarte pequeno. Treino e Loja mostram só o ícone.
L.4. Calçadas de pedra ligam a praça a Ovos, Pets, Loja, Renascer, Treino e Spawn.
L.5. Academia: piso escuro, pórtico com anilhas atrás, rack de halteres; as 4 máquinas pagam como antes (aviso "Treinando").
L.6. Loja: barracas com toldo listrado e gema na vitrine; os quiosques Melhorias e Loja abrem os painéis.
L.7. Pads de corte: de longe só "Corte N"; chegando perto aparecem dano, preço e vitórias. Comprar com E continua funcionando.
L.8. Quadro de recordes no lado oeste da praça, **com o ranking visível na face virada para a praça** (foi girado 180°; se aparecer em branco, a face ficou do lado errado).
L.9. Paredões: andar em volta da ilha inteira; não há fresta para cair, e pular não sobe. Testar também perto dos pilares do portão (lados do corredor).
L.10. Cascata no paredão sudoeste e lago a oeste não ficam em cima de nenhuma área.
L.11. Performance: Stats/MicroProfiler no celular emulado; o mapa inicial tem ~1.635 instâncias (antes ~2.315).

### Caminho do Poder
C.0. Da entrada, a barreira 1 lê como obstáculo de madeira (tábuas, travessa em X, cintas de ferro); as outras têm tijolos, rachaduras ou placas rebitadas conforme o tema. Ao quebrar uma fileira, os detalhes dela somem junto; quando o estágio se refaz, voltam.
C.1. Atravessar o portão: a primeira área e a barreira 1 continuam lá, em linha reta.
C.2. Quebrar a barreira 1, pegar o pad e voltar: tudo igual a antes.
C.3. Ir até depois da barreira 10: a praça final termina num maciço de rocha; o portal "em breve" fica de frente, com moldura, e não teleporta. Não dá para cair do fim.

### HUD
H.1. Topo: Power, Gemas e Vitórias numa linha; nada cobre essas três pílulas — **nem o tutorial roxo nem os avisos**, que agora aparecem logo abaixo delas.
H.2. "Mais": abre um painel em grade **ao lado** do menu (não uma coluna até o fim da tela); o botão vira ✕ / "Fechar"; tocar num item abre o painel e fecha o "Mais".
H.3. Badge: um item secundário com "!" (ex.: missão para resgatar) acende o "!" do "Mais".
H.4. Melhorias: o "!" só aparece quando surge uma melhoria nova ao alcance; abrir o painel apaga.
H.5. Rodapé: botão CLIQUE do mesmo tamanho; acima dele a faixa "Nv. X · COMBO xN · 🔥 %" e a barra de nível, agora maiores e legíveis. Clicar rápido (inclusive tocando no mundo): no máximo 6 números, sobem pouco **acima** da faixa e somem rápido, sem cobrir o personagem.
H.6. Auto Click (Debug): o ganho automático aparece somado, no máximo 1 número a cada ~0,8 s, à direita da faixa; nunca se acumula no centro.
H.7. Overdrive: a faixa mostra "🔥 x3 · 20s" e depois a recarga.
H.8. Chefe (esperar ou forçar pelo Debug): barra compacta **abaixo** das moedas, só no mundo onde ele está.
H.9. Perto de uma barreira, a faixa do corredor aparece embaixo das moedas sem sobrepor buffs/treino/chefe.
H.10. Celular (375x812 em paisagem), tablet e PC: nada cortado, CLIQUE alcançável.

### Espada equipada (bug da espada inicial invisível)
S.1. Jogador novo (Debug "Resetar dados" ou conta nova): a espada inicial aparece **na mão** ao nascer, e a UI mostra a mesma como "Equipada".
S.2. Morrer/respawnar (resetar o personagem): a espada equipada reaparece na mão.
S.3. Desbloquear outra espada e equipar: a da mão troca; não fica a antiga.
S.4. Sair e entrar de novo: a última espada equipada reaparece.
S.5. Conta com dados antigos: aparece uma espada válida.
S.6. Equipar várias vezes rápido e respawnar em seguida: Explorer > Workspace > personagem tem **um só** `CutBlade`; Backpack vazio.
S.7. Outro jogador (Test > 2 jogadores) vê a espada na mão do primeiro.

Coberto fora do Studio: `lune run tools/lune/check_sword.luau` (ordem de eventos,
fallback e duplicação) e `SwordEquip.spec` (qual espada vale). Solda na mão,
visual e replicação **só no Studio**.

### Core loop do Caminho (rodada de gameplay) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
G.1. Jogador novo: o chip "⚔️ Objetivo: quebre a Barreira 1 — siga a avenida" aparece no lobby e some ao chegar no corredor e de vez após a 1ª barreira.
G.2. Perto da barreira 1: faixa com "⚔ Estágio 1 — Madeira", barra de HP, "≈N golpes · Prêmio". Barreira forte demais (ex.: chegar à 4 cedo) mostra "⚠ Forte demais: treine e melhore o Corte" em vermelho.
G.3. Golpear: faísca pequena na face da barreira, no ponto mais perto do personagem, na cor da espada; a barra responde a cada golpe; nada de efeito empilhando.
G.4. Fileira quebrando: estilhaços na cor da madeira e das tábuas; tábuas, X e cintas da fileira somem junto; não sobra nada flutuando nem parede invisível; a fileira de trás continua sólida.
G.5. Última fileira: anúncio "💥 BARREIRA 1 DESTRUÍDA!" + "Escolha UM prêmio (volta para a praça) ou passe direto: Barreira 2" por ~2,5 s, sem bloquear a tela. Outro jogador perto vê só "Barreira 1 aberta por X"; longe, nada.
G.6. Pads (jogador novo, primeira vez): "+1 Vitória(s)" paga +1 e leva para a praça; "x2 · +2 Vitórias" paga +2 e leva para a praça; "Voltar (sem prêmio)" leva para a praça sem pagar. Só um prêmio por abertura.
G.6b. Repetindo a barreira 1: as placas mudam para o valor de repetição deste jogador e o x2 continua mostrando e pagando o dobro do normal.
G.6c. Para chegar à barreira 2: quebrar a 1 e passar direto pelos pads, sem pisar em nenhum.
G.6d. Não existe compra em Robux nos pads (nenhum prompt deve aparecer). Se aparecer, é bug.
G.7. Ficar parado DENTRO do bloco da barreira quando os 14 s acabam: ela não se fecha em cima do personagem; fecha quando ele sai.
G.8. Depois de passar, virar e golpear a barreira 1 por trás: não tira HP.
G.9. Na área 2, resetar o personagem: renasce no spawn olhando a avenida, espada na mão (um `CutBlade` só), progresso igual no painel Progresso. Cronometrar a volta até a barreira 2 (estimado: ~31 s andando + quebrar a 1 de novo).
G.10. Dois jogadores: um quebra, o outro passa junto; cada um pega o próprio pad uma vez.
G.11. Ovo gigante (Ovos), Guardião de Poder (Treino) e halo roxo (Renascer) reconhecíveis de longe; nenhum compete com o portão vindo do spawn. Sem cascata no paredão sul.

### Campo de Treinamento (TR) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
Renascimentos no Studio: comando de Debug "Rebirth" (renasce de verdade e completa o Power que faltar); "ResetData" volta a 0.
TR.1. **0 Renascimento**: no I (Boneco) o chip "Treinando" aparece e o Power sobe; o boneco balança a cada ~0,7 s. II, III e IV mostram cadeado, placa "🔒 REQUER ♻ X RENASCIMENTOS" e energia apagada.
TR.2. **Insuficiente**: com 0 no II (precisa 1) / com 5 no IV (precisa 6): nenhum ganho, chip some, aparece UMA vez "Você precisa de X Renascimentos para treinar aqui."; ficar parado ou pular dentro não repete; sair e voltar avisa de novo.
TR.3. **Exato**: com 1 no II, com 3 no III, com 6 no IV: treina. O cadeado some e a placa vira "♻ X RENASCIMENTOS" em verde.
TR.4. **Acima**: com 10+ todos treinam; o IV dá o maior ganho por segundo (1,80 × poder por clique).
TR.5. **Troca de alvo**: andar do I para o IV: o chip troca o valor na hora, sem ficar preso no anterior.
TR.6. **Renascer parado no alvo**: renascer com 5 → 6 em cima do IV: libera no próximo segundo, sem relogar; o cadeado some.
TR.7. **Respawn**: resetar o personagem em cima de um alvo: o chip some; ao voltar, treina normalmente.
TR.8. **Rejoin**: sair e entrar: os Renascimentos voltam do save, os cadeados batem com o que o jogador tem (nada do treino é salvo).
TR.9. **Visual**: I madeira/palha, II espantalho com placas e correntes (placas vibram, faíscas pequenas), III guerreiro de metal com energia que acende no golpe, IV guardião com núcleo que pulsa e runas girando. Placas legíveis de perto e baixas (não escondem o boneco). Nenhum boneco ataca, anda ou tem barra de vida.
TR.10. **Power ganho**: anotar o Power, ficar 30 s no I com o clique solto: ganho ≈ poder por clique × 0,35 × 30 (II 0,70; III 1,20; IV 1,80).
TR.11. **Multiplayer** (Test > 2 jogadores): A (0 Renascimento) e B (6+). B treinando no IV: os dois veem o núcleo pulsar; A vê o IV com cadeado (é por jogador), B sem. A no IV não ganha nada e recebe o aviso; B ganha.
TR.12. **Circulação**: andar entre os quatro pedestais e da entrada até cada placa sem prender; nada do campo na avenida.
TR.13. **Efeitos reduzidos** ligado: sem faíscas no Espantalho; o resto do movimento continua.

Coberto fora do Studio: `lune run tools/lune/check_training.luau` (config, mundo,
trava no servidor com jogadores falsos, cliente) e `TrainingLogic.spec`.

### Central do Aventureiro — Missões e Prêmios (RW) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
A área fica ao sul da praça (z ≈ 92), no fim da calçada que sai da praça.
RW.1. Chegando pela calçada: a calçada encosta no piso (sem faixa de grama no meio); Missões à ESQUERDA, Prêmios à DIREITA e, no centro, um troféu dourado num pedestal baixo (não tapa o mural nem o baú). Setas douradas no piso: mural → troféu → baú.
RW.2. Nenhuma árvore, pedra ou copa sobre o piso; nada (telhado, arco, presente) passando da borda.
RW.3. Placas "📋 MISSÕES / COMPLETE DESAFIOS" e "🎁 PRÊMIOS / COLETE SUAS RECOMPENSAS" inteiras, legíveis de perto, sem nada na frente; nenhum letreiro flutuante antigo ("Missões"/"Prêmios" em BillboardGui) sobrando.
RW.4. Em frente ao quadro: "E — Ver missões" abre o painel de Missões de sempre (mesmo progresso, mesmas missões).
RW.5. Em frente ao baú: "E — Pegar prêmios" abre o painel Prêmios de sempre (recompensa diária + código); resgatar funciona igual a antes.
RW.6. Andar: entrar → quadro → centro → baú → sair, sem prender; com pet equipado, o pet segue sem ficar preso no caixote, no pedestal ou nos pilares.
RW.7. De longe (spawn, praça e avenida) a área não compete com o portão do Caminho do Poder.
RW.8. Os chips/badges de Missões no HUD continuam iguais (nada novo na tela).
RW.9. Baú com prêmio diário disponível (badge do menu Prêmios aceso): brilho dourado dentro do baú respirando, poucas faíscas e um "!" pequeno balançando. Pegar o prêmio: em até 1 s o baú volta ao estado tranquilo (sem "!", sem faíscas) junto com o badge.
RW.10. "Efeitos reduzidos" ligado com prêmio disponível: sem faíscas; o "!" e o brilho continuam.
RW.11. Dar a volta no troféu e passar entre ele e as estações, a pé e com pet, sem prender.

Coberto fora do Studio: `lune run tools/lune/check_rewards_area.luau`.

### Caminho do Poder — Fase 0: placa de HP, título e HUD (PH) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
Câmeras: aproxime ao máximo sem entrar em 1ª pessoa (próxima), a distância padrão ao nascer (padrão) e afaste bastante (distante). Telas: Test > Device (1920x1080, 1366x768, iPad, iPhone em paisagem).
PH.1. Diante da Barreira 1, câmera padrão: a placa "1 · Madeira" + barra + "60 / 60" + pontos das fileiras aparece NA FRENTE da barreira, um pouco acima da cabeça; nada no topo da barreira.
PH.2. Repetir na Barreira 5 e no Colosso (10): mesma altura na tela, apesar de o Colosso ser bem mais alto.
PH.3. Câmeras próxima e distante nas três barreiras: a placa inteira na tela, sem cobrir o personagem e sem encostar nas moedas ou na faixa do corredor.
PH.4. Andar de um lado ao outro da barreira: a placa acompanha o lado do jogador e nunca passa da borda da barreira.
PH.5. Bater: a barra cai na hora; o pedaço perdido fica claro por um instante (~0,25 s) e some. Sem atraso visível.
PH.6. Abaixo de 25% a barra muda de cor (laranja); abaixo de 10%, vermelha com pulso leve. Nada pisca a placa inteira.
PH.7. Quebrar a fileira 1: a placa passa para a fileira 2, barra cheia, ponto da 1 apagado.
PH.8. Quebrar a última fileira: a placa some na hora (nada de "0 / X" no corredor); os pads e o Voltar ficam sem disputa.
PH.9. Uma placa por vez: diante da 1 não aparece a da 2; no lobby e no meio de uma área longe da barreira (> 70 studs) não aparece nenhuma; nenhuma placa através das paredes.
PH.10. Morrer/resetar diante da barreira: a placa some e volta com o mesmo HP (o seu) ao chegar de novo.
PH.11. Dois jogadores (Test > 2): A deixa a Barreira 1 em ~20%, B em ~80%. Cada um vê o PRÓPRIO valor; quando A quebra, a placa de B continua.
PH.12. Título: ao cruzar o começo de cada área aparece "⚔ N · NOME" (ex.: "⚔ 7 · ROCHA VULCÂNICA") por ~1,5 s abaixo das moedas e some; andar para trás e para frente na fronteira não repete em seguida. A placa flutuante "Estágio N — Nome" não existe mais.
PH.13. Faixa do corredor: uma linha só, "Seu golpe: X · ≈N golpes · Prêmio Y" (ou "⚠ Forte demais..."), sem nome e sem barra de HP; clicar continua abrindo o painel de Progresso.
PH.14. Efeitos reduzidos: sem pulso nos <10%; placa, nome, HP e título continuam.
PH.15. Celular: a placa não cobre o CLIQUE, o Auto, os recursos nem o personagem; o texto continua legível com a câmera distante.

Coberto fora do Studio: `lune run tools/lune/check_power_hud.luau` (projeção da câmera, uma placa por vez, A 20% / B 80%, rastro, <25%/<10%, quebra, respawn, título, faixa).

### Caminho do Poder — Fase A: fundação (PA) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
PA.1. Do lobby, passar pelo portão: a faixa central de placas (o "Caminho") começa colada no portão, com uma soleira; nada de "caixa genérica" logo na entrada.
PA.2. Andar da Barreira 1 até o portal em 3ª pessoa: as paredes sobem e descem por terço (não é mais uma linha reta), um pilar por terço de cada lado, capitéis no topo; a avenida continua larga (~80 studs entre pilares).
PA.3. No último terço de cada área, a faixa e o piso já começam a mostrar o próximo estágio (ex.: fim da 2 com placas de gelo; fim da 8 com metal); depois da barreira, a zona de decisão já está no material do próximo — sem troca seca numa linha.
PA.4. Zona de decisão: moldura rente ao chão em volta dos pads; +1, x2 e Voltar nos mesmos lugares de sempre; pisar em cada um faz o mesmo de antes (prêmio → praça; Voltar → praça sem prêmio; passar reto continua).
PA.5. Nada no meio do caminho: correr colado na parede e no centro, com 1, 3 e o máximo de pets equipados — ninguém prende em pilar, borda ou moldura (as bordas da faixa e as molduras não têm colisão).
PA.6. Barreira 1: nenhuma ilha flutuante sobre ela nem sobre o resto do corredor (olhar para cima em cada área).
PA.7. Luz: o corredor ficou com 11 PointLights (arcos + portal). Conferir se alguma área ficou escura demais em 3ª pessoa; Neon dos estágios de energia (4, 6, 8, 9, 10) continua brilhando sem a luz por fileira.
PA.8. Colosso (10): área maior e paredes mais altas; o portal continua inerte ("em breve"), sem teleporte.
PA.9. Dois jogadores: A abre a Barreira 5, B não; A atravessa, B continua batendo na fileira inteira; pads de A funcionam, B não consegue passar sem quebrar.
PA.10. Desempenho no celular: andar do portão ao portal sem queda perceptível de FPS (menos luzes que antes).

Coberto fora do Studio: `lune run tools/lune/check_power_path.luau` (10 trechos, piso plano e sem furo, safe lane, rota de avatar + pets, limites, transições, silhueta, barreiras/pads/portal intocados, decoração global fora, orçamento) e `python tools/render_power_path.py` (renders nas mesmas câmeras).


### Caminho do Poder — Fase B: temas 1–3 (PB) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
PB.1. Entrada da floresta: do portão, terra nas laterais, trilha de pedra no meio, paredes de rocha com borda de grama; as duas árvores antigas (no meio da área) formam a entrada natural e a copa fica ACIMA da cabeça — andar por baixo sem a câmera bater nela.
PB.2. Barreira 1: troncos nas bordas e o galho grosso por cima das fileiras emolduram a barreira; a placa de HP, a espada e o Corte ficam livres nas câmeras próxima e distante (nada entre o jogador e a face).
PB.3. Transição 1→2: no fim da floresta aparecem pedra talhada e tambores de coluna; depois da Barreira 1 o piso já é de pedra — a natureza recua, não há corte seco.
PB.4. Ruínas: colunas (algumas quebradas), blocos caídos, lajes partidas; o ARCO quebrado é assimétrico (um lado inteiro com a verga, o outro partido com o pedaço no chão) e a verga passa bem acima da cabeça.
PB.5. Barreira 2: umbrais de pedra nas bordas e a verga partida em cima — "entrada bloqueada de uma construção antiga"; placa de HP e Corte livres.
PB.6. Pedra → frost → gelo: no último terço das ruínas, frost no chão junto das paredes e no topo de um bloco; depois da Barreira 2, crosta de gelo na base das paredes e lascas de gelo antes da área 3.
PB.7. Gelo: portal de gelo na entrada (presas inclinadas + verga alta com pingentes), formações de gelo grandes nas laterais, pingentes no topo das paredes, poças congeladas; a Lighting do mundo NÃO muda.
PB.8. Barreira 3: blocos e placas de gelo nas bordas e a crosta por cima das fileiras — "selada pelo gelo"; placa de HP, espada e Corte legíveis contra o gelo (contraste da placa).
PB.9. Placa de HP nas barreiras 1–3: aparece inteira em todas as posições laterais (andar de um lado ao outro); nenhuma peça do cenário na frente dela.
PB.10. Pets: correr do portão até depois da Barreira 3 com 1, 3 e o máximo de pets — no meio e nas bordas da faixa (±16) ninguém prende; colado na parede há cenário (esperado, é fora da safe lane), mas os pets não ficam presos ao voltar para a faixa.
PB.11. CutFx: quebrar uma fileira em cada barreira 1–3 — o Corte e os pedaços não somem atrás de tronco, umbral ou gelo.
PB.12. Dois jogadores (Test > 2): os dois veem o mesmo cenário; a cintilação do gelo é local de cada um (liga só para quem está perto).
PB.13. Efeitos reduzidos: com a opção ligada, nenhuma cintilação nas formações de gelo; desligada, poucas partículas perto delas (até 180 studs) e nenhuma longe.
PB.14. Celular: andar do portão até a Barreira 3 e voltar — leitura das 3 regiões sem texto (silhueta, material, landmark), sem cenário cobrindo os botões de CLIQUE/Auto.
PB.15. FPS: comparar com a Fase A no mesmo aparelho no meio de cada área 1–3 (+109 peças, 0 luzes novas, 2 emissores com LOD); sem queda perceptível.

Coberto fora do Studio: `lune run tools/lune/check_power_path.luau` seção 10 (landmarks 1–3, molduras das barreiras, transições físicas, cenário fora da safe lane / da frente da barreira / das fileiras / dos pads / da câmera, estágios 4–10 sem cenário, orçamento por estágio, emissores ≤ 2 locais e desligados, controlador com LOD e Efeitos reduzidos) e `python tools/render_power_path.py <json> <saida> <tag> B` (câmeras da Fase B).

### Caminho do Poder — Fase C: temas 4–6 (PC) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
PC.1. Gelo → Cristal: depois da Barreira 3, a lasca de cristal; no começo do 4, formações de GELO com ponta de CRISTAL violeta (angular), depois o primeiro veio de energia no chão. Não é "azul → ciano": o cristal é violeta/mineral, a energia é só a linha clara.
PC.2. Estágio 4: o "vale de cristais" — a formação maior à esquerda (3 prismas, veio de energia, motes subindo devagar), a menor à direita; cristais saindo das paredes; piso escuro com veios finos. Nada de "boate ciano".
PC.3. Barreira 4: pilares de cristal com veio nas bordas, linhas de energia no chão junto às paredes indo até eles e a barra de cristal por cima — "alimentada pelos cristais". Placa de HP legível contra o cristal e o ciano da barreira.
PC.4. Cristal → Ouro: no fim do 4, cristais em pedestais com cinta de ouro; depois da Barreira 4, bloco de cantaria com friso de ouro; no começo do 5, um resto de cristal num berço de ouro.
PC.5. Estágio 5: templo PRESERVADO e organizado (não ruína): pilastras com capitel de ouro, nichos, medalhão no piso da faixa, os dois PÓRTICOS simétricos com o símbolo de ouro na parede. O corredor NÃO é amarelo: pedra quente com ouro só nos acabamentos.
PC.6. Barreira 5: portão selado do templo — pilares com capitel de ouro e o frontão triangular com o símbolo acima das fileiras.
PC.7. Ouro → Ancestral: no fim do 5 aparecem blocos pesados de granito com UMA runa; o ouro some.
PC.8. Estágio 6: granito escuro, placas enormes na faixa, blocos gigantes embutidos nas paredes, poucos sulcos rúnicos e três MONÓLITOS irregulares com uma runa cada — o jogador parece pequeno. Conferir se os monólitos não somem contra a parede escura na luz real.
PC.9. Barreira 6: selo ancestral — duas pedras enormes com energia vazando pela face interna e a pedra de cobertura com uma runa longa.
PC.10. Primeiro calor do 7: no último terço do 6 e depois da Barreira 6, fissuras com brasa, pedra escurecida e brasas raras subindo de um respiro junto à parede. SEM lava.
PC.11. Placa de HP nas barreiras 4–6: inteira e legível em todas as posições laterais (contra cristal, ouro e runas).
PC.12. CutFx nas barreiras 4–6: o Corte e os pedaços não somem atrás de pilar de cristal, pilar do templo ou pedra do selo.
PC.13. Pets: correr do 4 ao fim do 6 com 1, 3 e o máximo — no meio e nas bordas da faixa (±16) ninguém prende (atenção aos pórticos e monólitos).
PC.14. Dois jogadores: os dois veem o mesmo cenário; motes e brasas são locais (ligam só para quem está perto).
PC.15. Efeitos reduzidos: nenhum mote nem brasa; landmarks, arquitetura, runas e barreira continuam.
PC.16. Celular: as 3 regiões reconhecíveis sem texto; nada cobre CLIQUE/Auto.
PC.17. FPS: comparar com a Fase B no meio de cada área 4–6 (+107 peças, 0 luzes novas, 2 emissores novos com LOD, 0 loops novos).

Coberto fora do Studio: `lune run tools/lune/check_power_path.luau` seção 10 (landmarks 1–6, molduras 1–6, transições 3→4, 4→5, 5→6 e calor do 7, Neon só como acento, cenário fora da safe lane / frente da barreira / fileiras / pads / câmera, estágios 7–10 sem cenário, orçamento por estágio e por fase, emissores ≤ 5 com um único controlador) e `python tools/render_power_path.py <json> <saida> <tag> C`.

### Espada — ritmo visual e corpo no golpe (SW) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
Antes de começar: no Output, filtrar por `[SwordRuntime]` — cada golpe visual escreve `COMBO = X | GameplayHits N | VisualSwings M` (só no Studio); o painel de debug mostra `HITS n / SWINGS m`, RIG, BACKEND e COMBO.
SW.1. SEGURAR o clique 10 s numa barreira (cronometrar): o número de hits/dano é o de antes (≈ 9/s; o HP cai no mesmo ritmo, a faixa "≈N golpes" não muda) e a espada faz ≈ 38 golpes VISUAIS legíveis (≈ 3,8/s): dá para ver preparação → corte → recuperação em cada um. Nada de braço tremendo.
SW.2. Soltar o clique no meio: o personagem termina o golpe em curso (+ no máximo 1) e PARA — não continua batendo sozinho.
SW.3. Clique único: o golpe A sai NA HORA (sem atraso). Esperar 1 s, clicar: B. Esperar, clicar: C. Esperar > 1,2 s, clicar: volta ao A.
SW.4. Spam manual (cliques rápidos e irregulares): nenhum golpe é cortado no meio, nada acumula, A→B→C continua.
SW.5. Auto Click ligado (sem clicar): os hits continuam a 4/s e a espada faz ≈ 3,8 golpes/s, em A→B→C — sem "liquidificador".
SW.6. Corpo: em A o tronco gira um pouco acompanhando o corte (direita → esquerda) e o braço esquerdo abre; em B o contrário; no C o tronco sobe/recua e desce para frente, o braço esquerdo recolhe. A cabeça acompanha só de leve e continua olhando o alvo. Não pode parecer "manequim + braço".
SW.7. Postura entre golpes: parado com a espada, a postura de combate (espada baixa, para o lado) — o braço não volta para o "braço reto" do Roblox entre os golpes.
SW.8. Andar, correr e pular batendo: pernas/locomoção normais, o golpe sai por cima, nada trava nem quebra o braço.
SW.9. Rastro (Trail) da lâmina: acompanha o golpe visual; segurando, não pisca 9 vezes por segundo.
SW.10. CutFx/impacto: continuam aparecendo por hit (como antes). Avaliar se ~9 impactos/s + ~6–7 Cortes/s ficam exagerados contra 3,8 golpes/s (NÃO alterado nesta correção — só observar e reportar).
SW.11. Respawn no meio do combo: o novo corpo começa no A, sem golpe herdado. Trocar de espada (skin) no meio: combo recomeça no A.
SW.12. R15 normal, R15 com Avatar Joint Upgrade (AnimationConstraint) e R6: os três golpeiam com o mesmo ritmo; no R6 só os ombros participam (o R6 não tem cintura/pescoço separados — limitação conhecida).
SW.13. Dois jogadores (Test > 2): o golpe do outro jogador por perto também sai no ritmo visual limitado (não a cada sinal).
SW.14. Efeitos reduzidos: o golpe da espada e o corpo continuam; só arco/Corte somem (como antes).
SW.15. Sem camera shake novo por golpe; o feedback de câmera continua o do CombatFx.

### Caminho do Poder — Fase D: endgame 7–9 (PD) — REQUER VALIDAÇÃO NO ROBLOX STUDIO
PD.1. 6 → 7: depois da Barreira 6, fissuras quentes e brasas continuam e crescem; a pedra ancestral dá lugar ao basalto — a sensação é de "descer" para uma região muito quente (o piso continua na mesma altura).
PD.2. Estágio 7: basalto e rocha rachada em camadas, colunas de basalto na parede, fissuras quentes (uma cruza a faixa rente ao chão, sem colisão), respiro com um fio de fumaça e brasas. Landmark: dois PAREDÕES de basalto quebrados e inclinados com pontas — o jogador parece pequeno. Ainda NÃO é lava.
PD.3. Barreira 7: massa de rocha vulcânica — blocos de basalto com pontas nas bordas, fissura quente na face interna, laje bruta por cima com uma veia de brasa.
PD.4. 7 → 8: no fim do 7 as fissuras cruzam a faixa e o primeiro cristal vermelho rompe o basalto; no começo do 8, mais fissuras e cristais.
PD.5. Estágio 8: rocha NEGRA, duas formações de CRISTAL DE MAGMA (vermelho profundo, núcleo laranja, rocha negra levantada na base) assimétricas, magma correndo entre elas e vazando das paredes, faíscas no cristal maior. Não pode parecer "vulcânico 2".
PD.6. Barreira 8: pilares de cristal vermelho com núcleo laranja nas bordas e a laje de rocha negra com a veia de magma por cima.
PD.7. 8 → 9: no fim do 8 o cristal escurece e o veio vira violeta; a linha de energia fria substitui a fissura térmica; no começo do 9, mais cristal escuro e o primeiro circuito.
PD.8. Estágio 9: grafite, azul profundo e violeta; circuitos "cortando" a faixa (rente; o piso físico é contínuo), painéis com linha de energia, uma parede cujo topo se soltou e flutua, fragmentos pairando, e os dois ARCOS FLUTUANTES (blocos suspensos por feixes de energia). Nada é plataforma nem alcançável; nada se mexe (estático de propósito).
PD.9. Barreira 9: contenção de energia — pilones escuros com anéis de energia e a viga de contenção por cima. Mais contida que um final: a 10 é o grande momento.
PD.10. Pré-10: depois da Barreira 9, dois pilones bem mais altos que as paredes abrindo para fora e linhas de energia convergindo para frente. Olhando do meio do 9: Barreira 9 → além → "tem algo grande depois". Nada do Colosso construído.
PD.11. Placa de HP nas barreiras 7–9: inteira e legível em todas as posições laterais (contra basalto, vermelho e violeta).
PD.12. Sword Swing nas barreiras 7–9: personagem, espada e o golpe A/B/C continuam legíveis contra os fundos escuros (não pode sumir no preto do 8/9).
PD.13. CutFx e impacto nas barreiras 7–9: não somem atrás de pilar/pilone, não se confundem com o Neon do cenário.
PD.14. Pets: correr do 7 ao fim do 9 com 1, 3 e o máximo — ninguém prende (atenção a paredões, formações e arcos).
PD.15. Dois jogadores: mesmo cenário; fumaça, brasas, faíscas e motes são locais (só perto).
PD.16. Efeitos reduzidos: sem fumaça/brasas/faíscas/motes; landmarks, arquitetura, linhas de energia e barreiras continuam.
PD.17. Celular: as 3 regiões reconhecíveis sem texto; a fumaça não pesa (1 respiro, 1,2 partícula/s); nada cobre CLIQUE/Auto.
PD.18. FPS: comparar com a Fase C no meio de cada área 7–9 (+130 peças, 0 luzes novas, +4 emissores com LOD, 0 loops novos).
PD.19. Iluminação: 7–9 são escuros de propósito, sem PointLight nova — conferir se o avatar, a faixa e os pads continuam visíveis na luz real (se escuro demais, clarear a COR das superfícies, não adicionar luz).
PD.20. Pads 7–9: +N, x2 e Voltar legíveis contra o piso escuro e os circuitos; mesmos lugares, mesma lógica; passar reto continua.

Coberto fora do Studio: `lune run tools/lune/check_power_path.luau` seção 10 (landmarks 1–9, molduras 1–9, transições 6→7, 7→8, 8→9 e pré-10, Neon só como acento, cenário fora da safe lane / frente da barreira / fileiras / pads / câmera, estágio 10 sem cenário, orçamento por fase e estágio, emissores ≤ 9 com um único controlador) e `python tools/render_power_path.py <json> <saida> <tag> D`.
