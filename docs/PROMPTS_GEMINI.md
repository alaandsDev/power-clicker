# Prompts para o Gemini — monstros e chefes

17 imagens: 12 monstros (um por zona) e 5 chefes (um por mundo).

**Por que fundo magenta:** o Gemini não entrega PNG com transparência. Pedindo um
fundo chapado `#FF00FF` (magenta puro), que nunca aparece na arte do jogo, eu
recorto depois com `python tools/remove_flat_bg.py --all`.

---

## Passo 1 — cole este bloco antes de cada pedido

```
Você vai gerar arte de personagem para um jogo Roblox chamado "Power Clicker",
um simulador de cliques para crianças e adolescentes (8 a 16 anos).

ESTILO OBRIGATÓRIO
- Render 3D cartoon, estilo simulador moderno do Roblox / Pixar simplificado.
- Formas arredondadas e fofas, contorno escuro grosso, cores saturadas.
- Iluminação suave vinda de cima, sem sombras duras.
- Paleta do jogo: amarelo #FFC42D, laranja #FF7A3C, rosa #FF3C78, ciano #50DCFF, roxo #8C5AFF.

ENQUADRAMENTO OBRIGATÓRIO
- Personagem de FRENTE, olhando para a câmera, corpo inteiro, pés ou base visíveis.
- Centralizado, ocupando cerca de 85% da altura da imagem.
- Sem perspectiva forçada, sem ângulo de baixo ou de cima, sem corte.
- Quadrado, 1024x1024.

FUNDO OBRIGATÓRIO
- Fundo totalmente chapado na cor magenta #FF00FF, sem gradiente, sem textura,
  sem sombra projetada no chão, sem cenário.
- Nenhum elemento da arte pode usar magenta ou rosa muito próximo de #FF00FF.

REGRAS
- O monstro apanha o jogo inteiro, então precisa ser simpático e engraçado,
  nunca assustador. Sem sangue, sem ferimentos, sem caveiras, sem armas realistas.
- Nenhum texto, número, logotipo ou marca d'água na imagem.
```

## Passo 2 — peça um por vez

Cole o bloco acima e depois uma das linhas abaixo. Salve com o nome indicado.

### Mundo Treino
1. `mob_Meadow.png` — Um saco de pancada vivo: saco de boxe bege com cintas de couro, olhinhos determinados, sobrancelha franzida, luvinhas de boxe vermelhas, algumas folhinhas de grama grudadas no corpo.
2. `mob_Quarry.png` — Um golem baixinho feito de pedras cinzentas empilhadas, olhos amarelos brilhando entre as frestas, marcas de picareta no corpo, poeirinha saindo dos ombros.
3. `mob_Storm.png` — Um elemental de raio: nuvenzinha fofa e arredondada azul-ciano com braços feitos de eletricidade, olhos brilhantes, raios amarelos estalando em volta.
4. `mob_Void.png` — Um orbe do vazio: esfera roxa escura flutuando, um olho grande e curioso no centro, anéis de energia roxa girando em volta, pontinhos de estrela sendo sugados.

### Mundo Cidade
5. `mob_Rooftops.png` — Um drone entregador rebelde: drone quadradinho branco e ciano com quatro hélices, olho-câmera grande, caixinha de entrega pendurada, luzes piscando, cara de traquinas.
6. `mob_Downtown.png` — Uma placa de neon que ganhou vida: letreiro de neon rosa e ciano com tubos formando braços finos, olhos feitos de lâmpadas, base de metal com fios soltos faiscando.

### Mundo Vulcão
7. `mob_Crater.png` — Um brutamontes atarracado de rocha vulcânica escura com rachaduras laranja brilhando por dentro, braços grandes, fumacinha saindo da cabeça, expressão emburrada e engraçada.
8. `mob_LavaCore.png` — Um coração de magma: esfera de lava incandescente presa por correntes de obsidiana, olhos de fogo, pingos de lava escorrendo, aura laranja intensa.

### Mundo Espaço
9. `mob_Orbit.png` — Um satélite velho e desajeitado: painéis solares tortos, antena parabólica como chapéu, um olho de lente, adesivos desbotados, pequenas faíscas.
10. `mob_Nebula.png` — Uma água-viva cósmica: corpo translúcido roxo e rosa com estrelas dentro como um aquário do espaço, tentáculos com pontinhas brilhantes, brilho suave.

### Mundo Galáxia
11. `mob_StarForge.png` — Um pequeno autômato ferreiro dourado com corpo em formato de bigorna, braços de martelo, uma forja acesa no peito soltando faíscas douradas, olhinhos de brasa.
12. `mob_EventHorizon.png` — Um devorador de luz: criatura arredondada de silhueta escura com borda arco-íris, boca sorridente feita de luz, anéis de energia rosa e roxa girando ao redor.

### Chefes (maiores e mais imponentes, mesmo enquadramento)
13. `boss_Training.png` — O Rei dos Sacos de Pancada: saco de boxe gigante com coroa dourada torta, capa vermelha pequena, bigode, luvas douradas, pose de valentão simpático.
14. `boss_City.png` — A Grua Titã: robô montado com peças de obra, cabeça de guindaste com farol aceso, braços de viga de aço, cones de trânsito nos ombros, luzes ciano piscando.
15. `boss_Volcano.png` — Um dragão de magma gorducho: pele de pedra vulcânica com rachaduras de lava, asinhas pequenas demais para o corpo, fumaça pelas narinas, sentado.
16. `boss_Space.png` — A Sentinela da Estação: núcleo robótico flutuante com anel de propulsores, olho central azul-ciano enorme, braços mecânicos segurando asteroides pequenos.
17. `boss_Galaxy.png` — O Titã Cósmico: gigante feito de galáxia e nuvens de estrelas, coroa de cristais flutuando acima da cabeça, olhos brancos brilhantes, mãos soltando poeira estelar arco-íris.

---

## Passo 3 — trazer para o jogo

1. Salve tudo em `art/monsters/` com os nomes exatos acima.
2. Recorte o fundo: `python tools/remove_flat_bg.py --all`
3. Envie: `python tools/upload_assets.py`
4. Me avise para eu trocar as formas geométricas pelos recortes.

**Comece pelos 5 do Treino** (itens 1 a 4 e o 13). São os que todo jogador novo vê,
e com eles já dá para julgar se o estilo funciona antes de gerar os outros 12.
