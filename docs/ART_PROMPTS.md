# Power Clicker: pacote de prompts de arte

Para gerar no Claude Design. **Cole o Guia de Estilo primeiro**, depois cada bloco.
Salve cada imagem com o **nome de arquivo indicado**, para eu ligar tudo no código sem confusão.

---

## 0. Guia de estilo (colar antes de tudo)

> Você vai criar a arte do jogo Roblox "Power Clicker", um simulador/clicker de energia elétrica para público jovem (8–16 anos).
> **Estilo:** cartoon 3D brilhante (estilo simulador moderno do Roblox), formas arredondadas e fofas, cores saturadas, contorno escuro grosso, iluminação suave com brilho/aura elétrica azul-ciano e amarela. Todas as imagens devem parecer do mesmo jogo.
> **Paleta principal:** amarelo energia (#FFC42D), laranja (#FF7A3C), rosa (#FF3C78), azul-ciano (#50DCFF), roxo (#8C5AFF), fundo escuro azul-noite (#181A28).
> **Regras:** sem logotipo do Roblox, sem personagens de outras marcas, sem texto a não ser quando pedido, sem símbolo de dinheiro real. Nada de sangue, armas ou violência.

---

## 1. Ícone do jogo (refazer versão limpa)
Arquivo: `game_icon.png` · **1024×1024**, fundo preenchido (não transparente)

> Ícone do jogo "Power Clicker". No centro, um grande botão redondo brilhante sendo pressionado por um cursor de mouse estilizado, explodindo em raios elétricos azul-ciano e faíscas amarelas. Título "POWER CLICKER" no topo, em letras 3D grossas (POWER em azul, CLICKER em amarelo-dourado), com contorno escuro. Fundo azul-noite com brilho roxo. **Nenhum outro texto ou número na imagem.** Composição limpa e legível mesmo pequena (150 px).

---

## 2. Thumbnails da página do jogo (3 imagens)
Arquivos: `thumb_1.png`, `thumb_2.png`, `thumb_3.png` · **1920×1080**

> **Thumb 1:** um personagem Roblox genérico (bloco, sem marca) clicando num grande botão retangular laranja-rosa brilhante; números "+10K" saltando; raios ao redor; ilha de treino verde ao fundo; título "POWER CLICKER" pequeno no canto superior esquerdo.
>
> **Thumb 2:** vários pets fofos flutuando em volta de um personagem: cachorro, gato, raposa, dragão e unicórnio brilhando; um ovo mágico roxo rachando com luz saindo. Texto curto: "CHOQUE PETS RAROS!".
>
> **Thumb 3:** colagem de 4 mundos em diagonal: ilha de treino ensolarada, cidade ao pôr do sol com prédios iluminados, vulcão com lava, estação espacial com asteroides. Texto curto: "EXPLORE 5 MUNDOS!".
>
> Sem pedir "like"/"favorite", sem links, sem preços.

---

## 3. Ícones do menu e HUD (12)
**512×512 PNG, fundo transparente, sem texto**, objeto centralizado ocupando ~80%, legível em 48 px.

| Arquivo | Prompt |
|---|---|
| `icon_power.png` | raio elétrico amarelo-laranja grosso e brilhante |
| `icon_gems.png` | gema/diamante lapidado azul-ciano com reflexo |
| `icon_upgrades.png` | seta grossa para cima verde com brilho e faíscas |
| `icon_rebirth.png` | duas setas circulares roxas formando um ciclo, com brilho mágico |
| `icon_pets.png` | patinha fofa ciano com coraçãozinho |
| `icon_eggs.png` | ovo mágico creme com manchas coloridas e brilho |
| `icon_worlds.png` | planeta azul e verde com anel dourado |
| `icon_rewards.png` | caixa de presente verde com laço dourado, tampa levemente aberta com luz |
| `icon_quests.png` | pergaminho enrolado com um check verde |
| `icon_ranking.png` | troféu dourado com estrela |
| `icon_shop.png` | sacola/carrinho de compras amarelo com estrela |
| `icon_settings.png` | engrenagem cinza-metálica brilhante |

---

## 4. Pets (17)
**512×512 PNG, fundo transparente, sem texto**, pet inteiro de frente em pose fofa, olhos grandes, estilo chibi. **Quanto mais raro, mais brilho, aura e detalhes mágicos.**

| Arquivo | Pet | Raridade | Prompt |
|---|---|---|---|
| `pet_Dog.png` | Cachorro | Comum | filhote de cachorro caramelo sorrindo, simples |
| `pet_Cat.png` | Gato | Comum | gatinho cinza fofo sentado, simples |
| `pet_Bunny.png` | Coelho | Incomum | coelhinho branco com bochechas rosadas, leve brilho verde |
| `pet_Deer.png` | Cervo | Incomum | filhote de cervo com pintinhas e chifrinhos, leve brilho verde |
| `pet_Fox.png` | Raposa | Raro | raposa laranja com cauda felpuda, aura azul suave |
| `pet_Owl.png` | Coruja | Raro | corujinha marrom de olhos enormes, aura azul |
| `pet_Bear.png` | Urso | Raro | ursinho marrom robusto e fofo, aura azul |
| `pet_SpiritFox.png` | Raposa Espiritual | Raro | raposa etérea azul-translúcida com chamas espirituais nas pontas das caudas |
| `pet_Wolf.png` | Lobo | Épico | lobo cinza-prateado imponente mas fofo, aura roxa e faíscas |
| `pet_Panther.png` | Pantera | Épico | pantera negra com olhos verdes brilhantes, aura roxa |
| `pet_Golem.png` | Golem | Épico | golem de pedra fofo com runas brilhando em ciano, aura roxa |
| `pet_StarterDragonling.png` | Dragãozinho Inicial | Épico (exclusivo) | filhote de dragão laranja com asinhas, estrela no peito, aura roxa |
| `pet_Unicorn.png` | Unicórnio | Lendário | unicórnio branco com crina arco-íris e chifre dourado, aura dourada intensa e estrelinhas |
| `pet_Phoenix.png` | Fênix | Lendário | fênix de fogo laranja e vermelho com asas abertas em chamas, aura dourada |
| `pet_Dragon.png` | Dragão | Lendário | dragão verde-esmeralda poderoso e fofo, asas abertas, aura dourada e raios |
| `pet_VipCrownCat.png` | Gato Coroado VIP | Lendário (VIP) | gato branco elegante com coroa dourada com joias e capa vermelha, aura dourada |
| `pet_CelestialDragon.png` | Dragão Celestial | Mítico | dragão cósmico com corpo feito de galáxia e estrelas, chifres de cristal, aura arco-íris intensa com partículas — o pet mais épico do jogo |

---

## 5. Ovos (3)
**512×512 PNG, fundo transparente, sem texto**, ovo inteiro, de pé.

| Arquivo | Prompt |
|---|---|
| `egg_BasicEgg.png` | Ovo Básico: ovo creme liso com manchas marrons suaves, simples e limpo |
| `egg_ForestEgg.png` | Ovo da Floresta: ovo verde com folhas e vinhas enroladas, pequenas flores, brilho verde |
| `egg_MysticEgg.png` | Ovo Místico: ovo roxo-escuro com runas brilhantes em ciano e rachaduras de luz dourada, aura mágica |

---

## 6. Game Passes (5)
**512×512 PNG.** O Roblox mostra passes **cortados em círculo**: mantenha o conteúdo importante no centro (círculo interno de ~420 px). Fundo preenchido com gradiente da cor indicada.

| Arquivo | Pass | Prompt |
|---|---|---|
| `pass_DoublePower.png` | 2x Power | raio amarelo gigante com "2X" grande em 3D dourado, fundo gradiente laranja |
| `pass_AutoClick.png` | Auto Clique | mãozinha-robô/cursor mecânico clicando sozinho um botão, engrenagens e raios, fundo gradiente azul |
| `pass_ExtraPets.png` | +3 Pets | três pets fofos lado a lado (cachorro, gato, raposa) com "+3" grande, fundo gradiente ciano |
| `pass_DoubleLuck.png` | 2x Sorte | trevo de quatro folhas brilhante com "2X" e estrelas, fundo gradiente verde |
| `pass_VIP.png` | VIP | coroa dourada com joias e a palavra "VIP" em letras douradas grossas, faíscas, fundo gradiente roxo-real |

---

## 7. Developer Products (8)
**512×512 PNG**, fundo preenchido com gradiente, o item no centro. (Aparecem na tela de compra do Roblox.)

| Arquivo | Produto | Prompt |
|---|---|---|
| `product_PowerBoost2x.png` | Boost 2x Power (15 min) | frasco de poção amarela com raio dentro, "2X" e um reloginho, fundo laranja |
| `product_PowerBoost5x.png` | Boost 5x Power (10 min) | poção laranja-vermelha maior e mais intensa com "5X" e raios, fundo vermelho |
| `product_LuckBoost.png` | Boost 2x Sorte (15 min) | poção verde com trevo dentro, "2X" e reloginho, fundo verde |
| `product_InstantOverdrive.png` | Overdrive instantâneo | botão pulsando explodindo em energia laranja com velocímetro no máximo, fundo laranja-escuro |
| `product_GemsSmall.png` | 100 Gemas | pequena pilha com 3 gemas azuis, fundo azul |
| `product_GemsMedium.png` | 550 Gemas | saquinho aberto cheio de gemas azuis, fundo azul mais intenso |
| `product_GemsLarge.png` | 1.200 Gemas | baú de tesouro transbordando gemas azuis brilhando, fundo azul-roxo |
| `product_StarterPack.png` | Pacote Inicial | caixa-presente especial com fita dourada, de onde saem o Dragãozinho Inicial, gemas e poções; estrela "OFERTA ÚNICA", fundo roxo com raios |

---

## 8. Extras (opcionais)
| Arquivo | Tamanho | Prompt |
|---|---|---|
| `logo_title.png` | 1024×512, transparente | só o título "POWER CLICKER" em letras 3D (POWER azul, CLICKER dourado), com raio entre as palavras, para a tela de carregamento |
| `badge_vip.png` | 256×256, transparente | selo VIP com coroa dourada, para aparecer ao lado do nome |

---

## Depois de gerar
1. Publique o jogo (necessário para enviar imagens).
2. Rode `python tools/remove_checker.py --all` (tira o fundo xadrez → PNG transparente) e depois `python tools/upload_assets.py` com a sua chave Open Cloud (instruções no topo do arquivo). Os IDs vão sozinhos para `src/shared/Config/AssetIds.luau` e o jogo passa a usar as imagens (menu/HUD, pets, ovos).
3. **Ícone e thumbnails (1 e 2):** Arquivo → Configurações do jogo → Informações básicas.
4. **Passes e produtos (6 e 7):** [create.roblox.com](https://create.roblox.com) → sua experiência → Monetização → crie cada Game Pass / Developer Product já com a imagem.
5. Me mande a lista `arquivo = ID` (e os IDs dos passes/produtos) que eu ligo tudo no código.
