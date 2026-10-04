# Análise do core loop — Caminho do Poder

Base: `tools/lune/check_corridor.luau` (WallService real sobre o mapa gerado),
`tools/simulate_economy.py` (perfis casual/ativo/muito ativo) e os configs.
**Nenhum número de economia foi alterado.** Tudo que depende de física,
câmera, toque, som ou sensação **REQUER VALIDAÇÃO NO ROBLOX STUDIO**.

## 1. Retorno depois de morrer/resetar

Respawn é sempre no lobby (spawn em x = -30, olhando para a avenida). O
progresso (`PlayerData.Tower`) não se perde — coberto pelo `check_corridor`.
O que pesa é voltar:

| Barreira | Distância do spawn | Andando (16 studs/s) | HP das barreiras anteriores a quebrar de novo |
|---|---|---|---|
| 1 Madeira | 290 | 18 s | 0 |
| 2 Pedra Reforçada | 500 | 31 s | 180 |
| 3 Gelo Eterno | 720 | 45 s | ~2 mil |
| 4 Cristal | 940 | 59 s | ~16 mil |
| 5 Dourada | 1.160 | 72 s | ~128 mil |
| 6 Pedra Antiga | 1.390 | 87 s | ~1,2 mi |
| 7 Vulcânica | 1.620 | 101 s | ~10 mi |
| 8 Magma | 1.850 | 116 s | ~85 mi |
| 9 Energética | 2.090 | 131 s | ~805 mi |
| 10 Colosso | 2.396 | 150 s | ~6,8 bi |

Leitura:
- As barreiras são **individuais por jogador** (ver "Multiplayer" abaixo) e se
  refazem, para quem abriu, 14 s depois de abertas. Para chegar à barreira N, o jogador quebra de novo todas as
  anteriores — mas com o dano de quem já chegou em N, as anteriores caem em
  poucos golpes (cada estágio pede ~8–10x o anterior). O custo real é
  **andar**: 1–2,5 min para voltar ao estágio 5–10, mais a quebra.
- Até a barreira 3 (primeiros minutos) o retorno é curto (≤ 45 s): aceitável.
- Do estágio 5 em diante a volta vira fricção de verdade.

**Proposta (não implementada):** um "atalho do Caminho" — ao lado do portão,
um pad que leva o jogador para a ÁREA do maior estágio que ele já conquistou
(`Tower.Highest + 1`, antes da barreira). Server-side, reaproveita
`WorldService`/`PivotTo`, não muda HP nem recompensa, e não pula nenhuma
barreira não conquistada. Alternativa mais barata: deixar as fileiras dos
estágios já conquistados sem colisão só para aquele jogador (colisão local no
cliente). Recomendo o atalho: é explícito e não cria diferenças de colisão
entre jogadores.

## 2. Primeiros 5 minutos (jogador novo)

Números de partida: golpe 2 (base 1 + Corte 1), clique segurado 9/s,
Força do Clique custa 20 Power, Corte 2 custa 250 Power + 1 vitória, Ovo Básico
2.000 Power, barreira 1 = 3 fileiras de 60 HP. O simulador NÃO conta a
caminhada; somei a estimativa dela.

| Tempo | O que acontece |
|---|---|
| 0:00 | Nasce olhando a avenida, o portão e a barreira 1. Tutorial: "clique no botão". Chip de objetivo: "quebre a Barreira 1 — siga a avenida" (novo). |
| 0:05–0:15 | 15 cliques concluem o 1º passo; o tutorial manda comprar Força do Clique (20 Power). |
| 0:20–0:40 | Anda ~18 s até a barreira 1; a faixa mostra estágio, HP e "≈N golpes". 180 HP caem em ~10–20 s segurando. |
| ~0:40 | "💥 BARREIRA 1 DESTRUÍDA!". Escolhe um pad (+1 ou +2 vitórias na primeira vez) e volta para a praça — ou passa direto pelos pads para tentar a Barreira 2. |
| 0:40–1:00 | Corte 2 liberado (1 vitória + 250 Power). Simulação: Corte 2 aos 34 s–1 min. |
| 1:00–2:00 | Barreira 2 (450 x 4): ativo cai aos ~46 s de jogo, casual ~2 min (+ caminhada). |
| 2:00–5:00 | Barreira 3 (3.500 x 4): ativo ~2 min, casual ~6 min. Barreira 4 (28 mil x 4) mostra "Forte demais: treine e melhore o Corte" para quase todos até ~5–8 min. |

Problemas encontrados:
1. **Tutorial puxa para longe do Caminho.** Passos: clicar → Melhorias → Ovo
   Básico → Pets → Renascer. Nenhum passo fala do Caminho, e o passo do Ovo
   pede 2.000 Power — fica vários minutos na tela competindo com o objetivo.
   A mensagem final ainda mandava "desbloquear a Cidade" (mundo dormente):
   **corrigido** para apontar o Caminho. *Recomendação (não implementada):*
   um passo "quebre a Barreira 1" logo depois da Força do Clique. Exige
   cuidado porque o progresso do tutorial é salvo nos dados.
2. **Período morto entre a barreira 3 e a 4** (casual ~2–6 min, ativo ~2–5
   min): a 4 pede ~8x a 3. É calibração de economia — **não alterado**. A
   faixa agora diz "Forte demais: treine e melhore o Corte" em vez de deixar
   o jogador bater sem progresso visível. Se o teste real confirmar tédio,
   a recomendação é olhar o preço do Corte 3 (5 mil) e o HP da barreira 4
   numa rodada de economia separada.
3. **Clique vale em qualquer lugar.** Quem fica clicando na praça ganha Power
   mas não vê o objetivo. O chip de objetivo (até a 1ª barreira cair) e o
   enquadramento do spawn cobrem isso.
4. **Sem áudio.** Todos os `SoundId` estão vazios (`AudioConfig`); os efeitos
   novos de golpe e quebra chamam `WallHit`/`WallBreak`, que ficam mudos até
   alguém subir os sons.
5. **Aviso de quebra para o servidor inteiro** (antes, toda quebra gerava um
   aviso para todo mundo): **corrigido** — quem quebrou vê o anúncio grande,
   quem está perto um aviso curto, o resto nada.

## 3. Transição barreira 1 → barreira 2 (corrigido após teste no Studio)

O design do jogo (o mesmo do código original, antes do commit 92ef647) é:

    quebrar a barreira → ESCOLHER um pad (normal ou x2) → receber → volta
    para a praça (fim da corrida) → nova tentativa

Os 3 pads de cada estágio (`WallConfig.Stages[n].Pads`):
- **pad 1 (normal)**: `Pads[1]` vitórias (1 na madeira);
- **pad 2 ("x2")**: `Pads[2]`, o dobro do normal na maioria dos estágios
  (no Gelo é 8 e 15: a placa mostra o valor, sem "x2");
- **Voltar**: sem prêmio, leva para a praça.

**Não existe compra em Robux nos pads.** Nenhum Developer Product ou Game Pass
do `ProductConfig` dá vitórias; o x2 é só o segundo pad. Se a intenção é um pad
pago, é um sistema novo (produto a criar no site do Roblox + fluxo de
ProcessReceipt) e fica para uma decisão separada.

Para chegar à barreira 2 o jogador **passa direto pelos pads** sem pegar nenhum
(enquanto a passagem está aberta). Pegar qualquer prêmio encerra a corrida.

O commit 92ef647 tinha removido a volta para a praça; foi restaurada. Ficaram:
golpe só na fileira à frente, a barreira não se fecha em cima de ninguém,
anúncio só para quem quebrou, faixa de golpes, VFX e detalhes.

### Bug do x2 pagando igual ao normal

1. A conquista do estágio era gravada na hora da quebra, ANTES do toque no
   pad; o pad via "já conquistado" e pagava a fração de repetição (20%) até na
   primeira vez.
2. Cada pad arredondava sozinho com piso 1: 1 × 0,2 e 2 × 0,2 viravam 1 e 1.

Correção: `WinPadRules` (uma regra só, usada pelo servidor e pela placa).
A primeira conquista vale por abertura e por jogador, e o pad x2 vale sempre
(pad normal) × 2.

### Multiplayer — barreiras individuais

Cada jogador faz o PRÓPRIO Caminho do Poder, mesmo no mesmo servidor:

- **Servidor (`WallService`)** guarda por jogador o HP de cada fileira, a
  abertura, a janela dos pads (14 s), o prêmio da abertura e as barreiras já
  atravessadas. O progresso salvo (`PlayerData.Tower`) já era por jogador; não
  houve migração nem mudança de DataStore.
- **As peças das fileiras no Workspace são compartilhadas e ficam sempre
  inteiras e sólidas no servidor.** Cada cliente recebe só o próprio estado
  (remote `WallState`) e o `WallController` esconde e tira a colisão das
  fileiras que AQUELE jogador quebrou, localmente. A física do personagem roda
  no cliente dono dele: ele atravessa, os outros continuam batendo na fileira.
- **Anti-exploit:** o servidor confere a posição de cada jogador contra as
  barreiras DELE a cada 0,25 s (e antes de cada golpe e pad). Quem está além de
  uma barreira que não abriu volta para a frente dela; golpe e pad não valem.
  Tirar a fileira no próprio cliente não dá progresso, prêmio nem acesso.
- Não existem mais: HP global, barreira quebrada por outro, janela global,
  reconstrução esperando "alguém" sair (só o próprio jogador conta) nem aviso
  de quebra para o servidor inteiro.

`tools/lune/check_corridor.luau` cobre os 9 cenários multiplayer (M1–M9) com o
`WallService` real e um cliente simulado por jogador. A física real da
passagem local REQUER VALIDAÇÃO NO ROBLOX STUDIO com 2 jogadores.
