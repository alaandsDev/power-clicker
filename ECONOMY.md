# Economy

All values live in `src/shared/Config/*`. Formulas live **only** in `src/shared/Formulas/` (`EconomyFormulas`, `PowerFormula`, `ComboLogic`, `EggOdds`).

## Formulas

| What | Formula | Config |
|---|---|---|
| Upgrade cost (level L → L+1) | `ceil(BaseCost × CostGrowth^L)` | UpgradeConfig |
| Rebirth cost (r done) | `ceil(200,000 × 2.3^r)` | RebirthConfig |
| Gems per rebirth | `floor(15 + 8r)` | RebirthConfig |
| Rebirth multiplier | `1 + 0.5 × R` | RebirthConfig |
| Combo multiplier | `min(1 + 0.02 × stacks, 2)`, 50 stacks max | ComboConfig |
| Overdrive | 400 manual clicks to charge, ×3 for 20 s, 10 s cooldown | OverdriveConfig |
| Pet multiplier | `1 + Σ(bonus × variantScale)` of equipped pets (3 slots base, +1 per Pet Slots level, +3 pass, max 12) | PetConfig |
| Egg chances | `weight × luck` for Rare+ rarities, normalized; luck capped at 5 | EggConfig, EggOdds |
| Boosts | highest per category (Power / Luck), never multiplied together | BoostConfig |

Power per click (server only, `PowerFormula` + `PowerService`):
```
(1 + ClickStrength) × Upgrade(1 + 0.25·PowerBoost) × Rebirth × Pet × World
  × Permanent(1 + 0.1·EternalPower) × GamePass × TemporaryBoost × Overdrive × Combo
```
Every stored amount is sanitized (finite, ≥ 0, ≤ `1e100`).

## Phase 8 audit: full simulation

Script: the scratch simulation mirrors every formula above. It plays greedily: buy the best upgrade, open up to 8 Basic Eggs per rebirth cycle, spend Gems on permanent upgrades (keeping a reserve for the next world), rebirth when affordable, unlock worlds as soon as possible. It counts **active play time only** and ignores Gems from daily rewards, quests and achievements, so real players move a bit faster than this.

### Problem found

With the Phase 1 values (rebirth growth 2.75, rebirth Gems `10 + 5r`, City costing 5,000 Gems):
- **No profile reached the second world in 12 h.** Rebirths give only ~100 Gems by rebirth 5.
- Progress **stalled at ~8–9 rebirths**, because cost grew ×2.75 per rebirth while the multiplier grew only linearly.

### Rebalance applied

| Value | Before | After |
|---|---|---|
| Rebirth cost growth | 2.75 | **2.3** |
| Gems per rebirth | 10 + 5r | **15 + 8r** |
| City | 5 rebirths + 5,000 Gems | **5 rebirths + 100 Gems** |
| Volcano | 15 + 50,000 | **12 + 500** |
| Space | 35 + 500,000 | **20 + 2,000** |
| Galaxy | 75 + 5,000,000 | **30 + 6,000** |

### Results after the rebalance (minutes of active play)

| Profile | 1st upgrade | 1st rebirth | 5 rebirths | City | 10 rebirths | Volcano | 20 rebirths |
|---|---|---|---|---|---|---|---|
| A casual (3 CPS) | 0.1 | 25 | 118 | 118 | 220 | — (20 h) | — |
| B active (6 CPS) | 0.1 | 8.5 | 40 | 40 | 73 | 419 (~7 h) | — |
| C active + passes (2x Power, VIP, 2x Luck, +3 pets) | 0.0 | 2.9 | 13 | 13 | 22 | 130 | 700 |
| D very active (10 CPS) | 0.0 | 4.0 | 18 | 18 | 32 | 189 | 1020 |

Takeaways:
- **Onboarding:** the first upgrade comes within seconds and the first egg within 1–2 minutes (2K Power). The first rebirth takes ~8 min for an active player and ~25 min for a casual one.
- **Paying players** (C) progress about **3× faster** than an equally active free player (B). They still need long sessions for Volcano and beyond, so the economy isn't trivialized. Boosts can't stack multiplicatively, which keeps paid boosts bounded.
- **Long-term goals always exist:** Space and Galaxy weren't reached in 20 h by anyone, which leaves room for weekly content.
- **Inflation:** costs grow exponentially (2.3^r) against polynomial/multiplicative growth (rebirth, gem upgrades, worlds ×10). Numbers stay far below the `1e100` cap within the planned content.

### Rare pets
- **Legendary:** the Mystic Egg (150 Gems) has ~15% Legendary odds, so ~1,000 Gems on average. With 2x Luck (pass/boost) it takes about half as many.
- **Mythic:** Celestial Dragon has a 0.1% chance per Mystic Egg, ~150k Gems on average. It's meant to be very rare, and the announcement is broadcast server-wide.
- The greedy simulation spends Gems on permanent upgrades first, so it never bought Mystic Eggs. The estimates above are analytical.

### Still to watch with live data
- Gem income from daily rewards, quests and achievements (not included in the simulation).
- Worlds 2–5 need their own eggs and pets. Pet bonuses in new worlds should scale with the world multiplier so pets stay relevant.
- Real CPS distribution (mobile vs PC) to fine-tune combo/overdrive.

## Fases 9 a 13: novas fontes de Power (simulador em `tools/simulate_economy.py`)

Rode `python tools/simulate_economy.py --hours 3` depois de qualquer mudanca de
balanceamento. Ele le as configs reais e simula tres perfis, mostrando de onde
vem o Power. A regra que ele checa sozinho: **clicar (mais alvos) tem que ser a
maior parte da renda**; se cair abaixo de 50%, o jogo virou "esperar evento" e
ele avisa.

Resultado da versao atual (3 h de sessao):

| Perfil | Renascimentos | Cliques+alvos | Orbes | Chefe | Baus | Marcos |
|---|---|---|---|---|---|---|
| Casual (1,5 cps) | 5 | 82% | 12% | 0% | 6% | Pedreira 26 min, 1o renascimento 26 min |
| Dedicado (4 cps) | 8 | 82% | 11% | 5% | 2% | Tempestade 2,3 h |
| Hardcore (8 cps) | 9 | 89% | 8% | 3% | 1% | Tempestade 1,4 h |

Ajustes feitos por causa dessa simulacao:
- **Zonas**: as exigencias subiram (Pedreira 250 mil -> 1,5 mi; Tempestade
  25 mi + 1 renascimento -> 400 mi + 3; Vazio 5 bi + 3 -> 120 bi + 8). Antes,
  um jogador dedicado terminava as quatro zonas em menos de 2 h.
- **Baus de sessao**: valiam quase 20% da renda de um casual; foram pela metade.
- **Alvos**: a recompensa e sempre menor que a vida do alvo (travado por teste e
  pela validacao de config), entao bater em alvo acelera, mas nunca imprime Power.
- **Chefe**: o bolo e fixo (75% da vida) e dividido pelo dano de cada um, entao
  servidor cheio nao multiplica a economia.
- **Hora Feliz** (x1,5 diaria, x2 no fim de semana) e **bonus de amigos**
  (+5% por amigo, ate +30%) multiplicam tudo isso e ficam de fora da tabela;
  sao o teto do que o jogo entrega num fim de semana com amigos.

---

# Diagnóstico atual (Fase A da reestruturação da Torre)

Rodado com `python tools/simulate_economy.py`, que foi **reescrito** para o jogo
como ele está hoje: clique segurado (9/s), cortes, corredor de barreiras,
vitórias, ovos/pets, melhorias e renascimento. A versão anterior ainda contava
as zonas de treino — que estão desligadas (`ZoneConfig.Build = false`) — e por
isso reportava uma renda que não existe mais.

**Nenhum valor foi alterado para este diagnóstico.** Ele é a base para a Fase H.

## Perfis simulados

| Perfil | Como joga |
|---|---|
| casual | segura o clique 35% do tempo, pega 25% dos orbes, não luta chefe |
| ativo | 75% do tempo, 70% dos orbes, luta chefe |
| muito ativo | 95% do tempo, 90% dos orbes, luta chefe |
| pós-renascimento | como o ativo, mas começando com 5 renascimentos e zero de tudo |

## Resultado (sessão de 2 h)

| Perfil | Renasc. | Vitórias | Corte | Estágios | Power total |
|---|---|---|---|---|---|
| casual | 3 | 4.522 | Cut4 | 4/6 | 17,6M |
| ativo | 6 | 6.492 | Cut5 | 4/6 | 114M |
| muito ativo | 6 | 6.412 | Cut5 | 4/6 | 104M |
| pós-renascimento | +1 | 10.652 | Cut5 | 4/6 | 202M |

Origem do Power em todos os perfis: **clique 80–85%**, orbes 7–10%, chefe ~4%,
baús 1–12%.

## Problemas encontrados

### P1 — Vitórias hiperinflacionadas (grave)

O pad paga o mesmo valor toda vez que a barreira cai, e a barreira mais baixa é
farmável para sempre. Em 2 h o jogador ativo junta **6.492 vitórias**; em 6 h,
**35.000**. Para comparar: o Corte 8, que deveria ser meta de fim de jogo, pede
6.000, e a aura mais cara pede 800.

Efeito: tudo que é gatilhado por vitória deixa de ser meta no primeiro dia.

### P2 — Renascimento virou rotina, não decisão

6 renascimentos em 2 h (um a cada ~15 min no início). O pedido quer que
renascer seja uma escolha com peso. Hoje o custo (×2,3) cresce mais devagar que
o Power do jogador no começo.

### P3 — Nenhuma renda passiva

Sem as zonas, 80–85% do Power vem do dedo no botão. Não existe nada que renda
enquanto o jogador organiza pets ou escolhe melhoria. É exatamente o buraco que
a área de treino do pedido preenche.

### P4 — Barreiras com salto brusco

Estágios 1–4 caem em minutos; o 5 (Obsidiana, 20M × 5 fileiras) e o 6 (Cristal,
900M × 6) não saem em 6 h de jogo em nenhum perfil. Entre o 4 e o 5 há um salto
de ~33×, sem degrau no meio.

### P5 — Pets saturam cedo

O ovo básico (único comprável com Power) vai até Wolf (+60%). Com 3 slots
equipados, o multiplicador de pets satura em poucos minutos. Os ovos melhores
custam gemas, e gemas só vêm de renascimento (15 + 8r), então o sistema de pets
some do meio do jogo.

### P6 — Gemas sem torneira

Fora do renascimento e de recompensas pontuais, não há gema no jogo. Com 6
renascimentos o jogador tem ~150 gemas: dá 6 ovos de floresta, nada perto do
Místico (150 cada).

## O que o simulador ainda NÃO modela

Sendo honesto sobre os limites deste diagnóstico:

- ovos de gema (Floresta/Místico) e a compra deles;
- auras, runas e multiplicador de mundo;
- passes e boosts comprados;
- a área de treino (não existe ainda) — há a opção `--training` para simular
  uma hipótese antes de implementá-la;
- jogador com mais de um por servidor dividindo o chefe.

## Recomendações para a Fase H (ainda não aplicadas)

1. Vitórias: pad com rendimento decrescente ao refarmar a mesma barreira, ou
   pagamento por "primeira vez no dia" + valor menor no repeat.
2. Renascimento: elevar o crescimento do custo, ou exigir estágio da torre.
3. Treino: renda passiva na casa de 30–50% do clique ativo.
4. Barreiras: redistribuir os 10 estágios numa curva sem o salto de 33×.
5. Pets/gemas: uma torneira de gemas ligada à torre (recompensa por estágio).

## Atualização da Fase B — curva da torre

A torre passou de 6 para 10 estágios e a curva foi refeita para eliminar o
salto de ×33 apontado em P4. Agora cada estágio pede de 8 a 12 vezes o total do
anterior:

| # | Estágio | HP/fileira | Fileiras | Total | Salto | Gemas (1ª vez) |
|---|---|---|---|---|---|---|
| 1 | Madeira | 60 | 3 | 180 | — | 0 |
| 2 | Pedra Reforçada | 450 | 4 | 1.800 | 10,0× | 5 |
| 3 | Gelo Eterno | 3.500 | 4 | 14.000 | 7,8× | 10 |
| 4 | Cristal Energizado | 28.000 | 4 | 112.000 | 8,0× | 20 |
| 5 | Estrutura Dourada | 220.000 | 5 | 1,1M | 9,8× | 35 |
| 6 | Pedra Antiga | 1,8M | 5 | 9M | 8,2× | 60 |
| 7 | Rocha Vulcânica | 15M | 5 | 75M | 8,3× | 100 |
| 8 | Magma Cristalizado | 120M | 6 | 720M | 9,6× | 170 |
| 9 | Barreira Energética | 1B | 6 | 6B | 8,3× | 280 |
| 10 | Colosso | 9B | 8 | 72B | 12,0× | 500 |

Simulação de 4 h com essa curva:

| Perfil | Estágios | Renasc. | Vitórias | Power total |
|---|---|---|---|---|
| casual | 5/10 | 5 | 6.348 | 77,6M |
| ativo | 6/10 | 7 | 10.063 | 425M |
| muito ativo | 6/10 | 7 | 10.443 | 431M |
| pós-renascimento | 6/10 | +3 | 11.883 | 549M |

Leitura: os quatro primeiros estágios caem nos primeiros 15 minutos (ensino),
do 5 ao 6 leva a primeira hora, e do 7 ao 10 é o longo prazo — é a forma que o
pedido descreve. **P1 (vitórias infladas) e P2 (renascimento virou rotina)
continuam abertos**, por serem calibração da Fase H.

As gemas de primeira conquista somam 1.180 no total, o que resolve P6 (gema sem
torneira) sem precisar vender nada.

## Atualização da Fase D — área de treino

Quatro máquinas na área de Treino, pagas em "cliques por segundo
equivalentes" (`poderPorClique × Rate × tempo`), então o treino acompanha todos
os multiplicadores do jogador e nunca vira uma segunda economia com números
próprios.

| Máquina | Rende | Exige |
|---|---|---|
| Saco de Pancada | 0,35 clique/s | — |
| Halteres | 0,70 | 10 vitórias |
| Esteira | 1,20 | 60 vitórias |
| Máquina de Força | 1,80 | 300 vitórias |

Teto de segurança: `MaxShareOfHoldClick = 0,25`, ou seja, nenhuma máquina pode
pagar mais que 25% do clique segurado (9/s), **mesmo que alguém edite o config
errado**. O clique ativo continua sendo o melhor Power por segundo — o treino é
para quando o jogador está organizando pets, escolhendo melhoria ou conversando.

Simulação de 4 h com o treino ligado (o tempo em máquina sai do tempo de
clique, porque não dá para fazer os dois):

| Perfil | Treino na renda | Estágios | 1º renascimento | Power total |
|---|---|---|---|---|
| casual (treina 40% do tempo) | 23,6% | 5/10 | 27min (era 25min) | 62,5M (era 77,6M) |
| ativo (20%) | 5,1% | 6/10 | 14min | 345M |
| muito ativo (5%) | ~1% | 6/10 | 12min | 354M |

Leitura: o treino tira o jogador casual do "só clicar" sem passar na frente de
quem clica — quem clica mais ainda ganha mais. **P3 (nenhuma renda passiva)
resolvido.**

## Atualização da Fase G — ovos, pets e renascimento

### Probabilidades (sem sorte; todas somam 100%)

| Ovo | Moeda | Preço | Libera com | Chances |
|---|---|---|---|---|
| Ovo Básico | Power | 2.000 | — | Cachorro 50%, Gato 30%, Coelho 14%, Raposa 5%, Lobo 1% |
| Ovo da Floresta | Gemas | 25 | — | Cervo 45%, Coruja 30%, Urso 18%, Pantera 6,5%, Unicórnio 0,5% |
| Ovo Místico | Gemas | 150 | — | Raposa Esp. 50%, Golem 35%, Fênix 12%, Dragão 2,9%, Dragão Celestial 0,1% |
| **Ovo da Torre** | Gemas | 400 | estágio 5 | Gárgula 46%, Cavaleiro 30%, Grifo 17%, Titã 6,5%, Dragão Eclipse 0,5% |
| **Ovo do Colosso** | Gemas | 2.500 | estágio 10 | Guardião 55%, Serafim 29%, Nova 15%, Colosso Menor 1% |

A sorte (upgrade + passe) só mexe nos pesos de Raro para cima, e é limitada a
×5 — as chances acima são o piso.

### Por que dois ovos novos

O diagnóstico apontou P5 (pets saturam cedo: o único ovo de Power ia até +60%) e
P6 (gemas sem torneira). Os dois ovos novos ligam uma coisa na outra: as gemas
de primeira conquista da torre (1.180 no total) são exatamente o que paga o Ovo
da Torre (400) e, mais tarde, o do Colosso (2.500). Pets de +2,5 a +90 de bônus
voltam a mexer o multiplicador no meio e no fim do jogo.

### Renascimento

A tela agora responde, antes de confirmar: quantos renascimentos você tem, o
que ganha (gemas e multiplicador de x para y), **quanto falta em Power**, o que
reseta e — a linha que faltava — **o que fica**: gemas, pets, vitórias, cortes,
espadas, auras e o progresso da torre. Nenhum valor da curva foi alterado; isso
é Fase H.

---

# Fase H — mudanças de economia aplicadas

Primeira vez nesta reestruturação que valores mudam. Cada linha tem o antigo, o
novo e por quê.

| O quê | Antes | Depois | Por quê |
|---|---|---|---|
| Pads de vitória ao repetir | 100% sempre | 20% no seu melhor estágio, caindo 55% por degrau abaixo dele (piso 2%) | P1: farmar a barreira de madeira para sempre dava 35.000 vitórias em 6 h, e o Corte 8 — meta de fim de jogo — pede 6.000 |
| Custo do renascimento | ×2,3 por vez | **×3,2** | P2: renascer a cada ~15 min virou rotina, não decisão |
| Multiplicador do renascimento | `1 + 0,5 × R` (linear) | **`1,75 ^ R` (composto)** | o motivo real do travamento: a torre cresce ~8× por estágio e um bônus linear fica para trás — todos paravam no estágio 6 com 10% de dano a menos que o necessário para o 7, e nada no jogo mudaria isso |
| Gemas por renascimento | `15 + 8r` | **`30 + 20r`** | com as antigas, o jogador terminava 12 h com ~40 gemas e o multiplicador de pets congelado em +60%: os ovos bons ficavam inalcançáveis |

Testei o crescimento do custo em 2,7, 3,2 e 3,8 antes de escolher: 3,2 é o que
dá ~1 renascimento a cada 40 min para o jogador ativo sem travar o longo prazo.

## Como ficou (simulação)

Sessão de 2 h:

| Perfil | Estágios | Renasc. | Vitórias | Por clique |
|---|---|---|---|---|
| casual | 5/10 | 3 | 557 | 4,45K |
| ativo | 7/10 | 6 | 1.927 | 50,3K |
| muito ativo | 7/10 | 6 | 2.311 | 41,9K |
| pós-renascimento | 7/10 | +2 | 3.859 | 122K |

Sessão de 12 h:

| Perfil | Estágios | Renasc. | Vitórias | Por clique |
|---|---|---|---|---|
| casual | 7/10 | 8 | 11.657 | 221K |
| ativo | 9/10 | 11 | 49.207 | 2,94M |
| muito ativo | 9/10 | 11 | 60.151 | 2,38M |
| pós-renascimento | 9/10 | +6 | 55.779 | 3,03M |

Leitura: os quatro primeiros estágios ensinam em minutos, o 5–7 ocupam as
primeiras horas, o 8–9 o primeiro dia e o **estágio 10 é meta de vários dias** —
que é o que o pedido descreve para o fim da primeira jornada.

## Efeito em quem já joga

O renascimento composto é um **buff** para quem já tem renascimentos: com 8, o
multiplicador sai de ×5 (linear) para ×57. Ninguém perde nada; a progressão de
quem já estava avançado acelera. O custo do próximo renascimento sobe
(×3,2 em vez de ×2,3), mas o ganho por renascimento sobe muito mais.

## O que continua em aberto

- As vitórias ainda chegam a dezenas de milhares numa sessão longa. É normal do
  gênero (o jogo de referência mostra vitórias em "26,4 octilhões"), e todos os
  portões de vitória do jogo ficam abaixo de 6.000 — ou seja, inflação sem
  consequência de balanceamento.
- O simulador ainda não modela auras de poder, runas, passes nem boosts; os
  números acima são, portanto, um **piso**.
