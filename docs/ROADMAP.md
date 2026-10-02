# Power Clicker — plano até o lançamento

O que já existe (fases 1 a 8): clique com combo e Overdrive, melhorias, gemas, renascimento,
pets e ovos, 5 mundos, missões, prêmios diários, códigos, ranking, passes e produtos,
salvamento seguro com trava de sessão, anti-exploit e 167 testes.

O que falta é o que os simuladores de sucesso têm e nós não: **algo para bater no mapa**,
**zonas que exigem força**, **itens para pegar**, **eventos** e **status visível**.
Referências pesquisadas estão no fim.

---

## Fase 9 — Zonas e alvos (o coração que falta) ✅ FEITA

O jogador deixa de olhar só para um botão: ele anda, bate em alvos e conquista terreno.

- **Alvos batíveis** (sacos de pancada / cristais): têm vida, apanham do seu clique,
  quebram com recompensa em Power e voltam depois de alguns segundos.
- **Zonas** em ilhas flutuantes ligadas por pontes, cada uma com multiplicador maior
  (x1 → x3 → x8 → x20 → x50) e exigência de Power total ou renascimentos.
- **Portão com placa** em cada zona, dizendo o que falta para entrar.
- Quem tentar entrar sem ter a força é devolvido ao início, pelo servidor.
- Multiplicador de zona entra como uma camada nova na fórmula de Power.

## Fase 10 — Coletáveis e chefe do servidor ✅ FEITA (baús ficaram para a 12)

- **Orbes de Power** nascendo pelo mapa; quem pegar leva o prêmio (corrida entre jogadores).
- **Baús** que aparecem de tempos em tempos na zona mais alta.
- **Chefe do servidor** a cada X minutos: todo mundo bate junto, prêmio por dano,
  e um bônus de 2x Power para o servidor inteiro quando cai.

## Fase 11 — Status visível ✅ FEITA (aura, plaquinha, VIP)

- **Rastros e auras** ganhos por renascimento, zona e VIP.
- **Pets seguindo** com aparência por raridade (já temos o seguidor, falta o brilho).
- **Título acima da cabeça**: nome, renascimentos e zona atual.
- **Efeito de renascimento** em tela cheia, visível para todos do servidor.

## Fase 12 — Retenção de longo prazo ✅ FEITA (baús de sessão, hora feliz, passe)

- **Prêmio por tempo de jogo** na sessão (a cada 5 min).
- **Missões diárias** que trocam todo dia, além das fixas que já existem.
- **Passe de temporada** simples: 20 níveis, gratuito e VIP.
- **Evento de fim de semana**: 2x Power e ovo por tempo limitado.

## Fase 13 — Social ✅ FEITA

- **Bônus de amigos**: +10% de Power por amigo no servidor.
- **Rank do servidor** visível no placar 3D (já temos o placar).
- **Presente de grupo**: bônus para quem entra no grupo do jogo.

## Fase 15 — Auras e runas ✅ FEITA

- **Auras compradas com gemas** (uma equipada por vez): dão velocidade de
  corrida e multiplicador de Power (camada `Aura`). A aura equipada também
  troca o anel que todos veem no personagem.
- **Runas dos chefes**: comum / incomum / lendária / mítica, uma por mundo
  (20 runas). Caem só de chefe, sorteio no servidor, com peso melhor para
  quem bateu mais. Multiplicam Power na camada `Rune`, em 3 espaços.
- **Chefe gira entre os mundos** (antes só nascia no mundo inicial), então as
  runas de Cidade, Vulcão, Espaço e Galáxia são alcançáveis.
- Compras em lote nas melhorias (1x / 10x / Máx) e HUD sem a tira de pets.

## Fase 16 — Virada de estilo (clicker de arena) ✅ EM ANDAMENTO

Referência: os clickers de espada com corredor de vitórias (Steal/Sword style).

- **Mapa quadriculado**: chão em blocos de 20 studs em duas tonalidades, praça
  quadrada e colinas em degraus. Mundos afastados para 8.000 studs (antes
  apareciam no horizonte e quase encostavam no corredor novo).
- **Vitórias**: terceira moeda, nunca reseta, com ranking próprio.
- **Corredor das Vitórias**: 6 estágios, cada um com 4–6 fileiras do mesmo
  material; quebra fileira a fileira, a passagem abre por 14s, pega um win pad
  e volta para a praça.
- **Cortes**: pads na frente do spawn que vendem dano fixo por clique (base da
  PowerFormula), pagos em Power e liberados por vitórias.
- **Segurar o clique** (9/s com jitter) e **barra de Nível** derivada do Power.
- **Auras** com requisito de vitórias e card no formato da referência.
- **Escada de passes** x2 → x4 → x8 (só o maior conta).

Falta desta fase: espadas + forja, inventário em abas, troca (liberada só
depois do Mundo 2) e o relógio de evento no topo da tela.

## Fase B (reestruturação) — Torre vertical ⚠️ SUBSTITUÍDA

> **Histórico.** A torre vertical descrita abaixo foi construída e depois
> **substituída pelo CAMINHO DO PODER**: um corredor horizontal reto, no mesmo
> nível do chão (ver "Tower Layout → Linear Progression Corridor" mais abaixo).
> Os 10 estágios, HP, recompensas e dados (`PlayerData.Tower`, DataVersion 6)
> continuam os mesmos; só a geometria mudou. O nome "Tower" sobrevive apenas em
> ids internos, que não podem ser renomeados.

- 10 estágios empilhados com tema próprio (madeira → ruínas → gelo → cristal →
  ouro → pedra antiga → vulcânica → magma → energia → colosso).
- Subida em ziguezague com rampa e corrimão; 440 studs de altura, pegada de
  470 × 135 studs.
- Barreira de 3 a 8 fileiras por estágio, cada fileira com HP próprio.
- Primeira conquista de cada estágio paga gemas (torneira que faltava) e fica
  registrada em `PlayerData.Tower` (DataVersion 6).
- Estágio 10 com sala maior, barreira colossal e portal "em breve" inerte.
- Curva sem o salto de ×33 (ver ECONOMY.md).

## Fases C e D (reestruturação) — Lobby e treino ✅ FEITAS

- **Lobby por áreas** (LobbyConfig): praça, ovos, pets, loja/melhorias,
  renascimento, treino e torre — cada uma com piso, anel de neon e letreiro.
  As coordenadas soltas do WorldBuilder (SPAWN_Z, ALTAR_X...) sumiram.
- Caminho de pedra da praça até a torre, ilhotas flutuantes, nuvens e cachoeira.
- **tools/render_map.py**: desenha a planta a partir dos configs e valida
  sobreposição de áreas, pads fora de área, inclinação de rampa e pé-direito.
  Pegou 7 erros de layout antes de irem para o jogo.
- **Área de treino** (TrainingConfig + TrainingService): 4 máquinas com visual
  próprio, um laço central no servidor, teto de 25% do clique segurado e aviso
  no HUD enquanto treina.

## Fase E (reestruturação) — Espadas e cortes ✅ FEITA

- **SwordConfig**: 8 skins cosméticas (ferro → colosso) com lâmina, rastro,
  brilho e cor do arco próprios. Nenhuma dá dano — quem dá é o Corte.
- Desbloqueio por **progressão**, não por compra: estágio da torre,
  renascimentos ou vitórias. O servidor concede sozinho ao atingir a condição.
- `SwordService` passou a ser o dono da aparência da lâmina (o `CutService`
  ficou só com o dano), com `DataVersion 7` e migração.
- Painel "Espadas" com a lâmina desenhada, raridade e o que falta para liberar.
- **Feedback na barreira**: a fileira pisca na cor da espada ao tomar dano,
  escurece conforme o HP cai e estilhaça ao quebrar (tudo local, com pool de
  peças e teto de frequência).

## Fase F (reestruturação) — Auras cosméticas ✅ FEITA

- **AuraSkinConfig**: 8 auras por raridade (Comum → Mítica), com partículas,
  anel e brilho próprios; desbloqueio por estágio da torre, renascimentos ou
  vitórias.
- **Nenhuma delas registra provedor no PowerService** — é impossível uma aura
  cosmética mexer na economia por acidente.
- As auras de gemas (velocidade + Power) continuam intactas: quem comprou não
  perde nada. O painel virou duas abas: "Poder" e "Visual".
- Tetos no config (`MaxRate`, `MaxSize`), um emissor por jogador e luz só nas
  duas raridades mais altas, para servidor cheio não derrubar FPS de celular.
- `DataVersion 8` com migração.

## Fase G (reestruturação) — Pets, ovos e renascimento ✅ FEITA

- Dois ovos novos presos a estágios da torre (Ovo da Torre no 5, Ovo do Colosso
  no 10) com 9 pets novos (+2,5 a +90), ligando a torneira de gemas da torre ao
  sistema de pets (resolve P5 e P6 do diagnóstico).
- `EggLogic` checa o estágio ANTES de cobrar; o painel mostra qual estágio falta.
- Bancadas de ovo passaram a ficar em arco (cinco em linha estouravam o piso).
- Tela de renascimento completa: requisito, quanto falta, ganho, o que reseta e
  **o que fica** — a linha que faz o jogador se sentir seguro para renascer.
- Probabilidades dos 5 ovos documentadas no ECONOMY.md (todas somam 100%).

## Fase H (reestruturação) — Economia ✅ FEITA

Primeira fase a mudar valores, com antes → depois em ECONOMY.md:

- Pads de vitória com rendimento decrescente ao repetir (P1).
- Renascimento mais caro (×2,3 → ×3,2) e mais valioso (P2).
- **Multiplicador de renascimento virou composto** (1,75^R em vez de 1+0,5R):
  era a causa real de todos travarem no estágio 6 — torre exponencial contra
  bônus linear.
- Gemas por renascimento de `15+8r` para `30+20r`, destravando os ovos bons.
- Simulação: 2 h chega ao estágio 5–7; 12 h ao 7–9; estágio 10 é meta de dias.

## Tower Layout → Linear Progression Corridor (CAMINHO DO PODER) ✅ FEITO — layout atual

Correção de layout pedida durante a Fase H. **Nenhum sistema foi refeito**: HP,
recompensas, gemas, dados, serviços, pets, ovos, treino, armas e economia
ficaram exatamente como estavam — mudou a geometria e a apresentação.

- As dez barreiras saíram de salas empilhadas para **um corredor reto, todo no
  mesmo nível**, indo para +X: lobby → área 1 → barreira 1 → ... → área 10 →
  barreira 10 → portal.
- Sem escadas, sem andares, sem subida.
- **Transição gradual** entre temas: piso e paredes vão virando a cor do tema
  seguinte ao longo da área, em vez de trocar de uma vez.
- **Arco** emoldurando cada barreira (o checkpoint visual) e **postes acesos na
  cor do próximo tema**, para o jogador ver de longe que há algo diferente
  adiante.
- Área final 1,6× maior, barreira de 8 fileiras e o portal "em breve" depois
  de uma praça aberta.
- `render_map.py` passou a validar o corredor: ordem dos estágios, caminhada
  vazia entre barreiras (teto de 80 studs), vão entre a ilha e a entrada, e
  área final maior que as outras.

## Fases I e J (reestruturação) — UI/UX e polimento ✅ FEITAS

- **Hierarquia no menu**: cinco principais (Melhorias, Pets, Ovos, Renascer,
  Progresso) maiores e sempre visíveis; os sete secundários atrás do botão
  "Mais". A decisão de o que é principal vive num lugar só (MenuController).
- **Faixa do corredor**: ao chegar perto de uma barreira aparece estágio, nome,
  vida da fileira, seu golpe e o prêmio — estreita e no alto, sem tapar a
  barreira.
- **Painel "Progresso"**: os 10 estágios em ordem, com conquistado / atual /
  fechado, HP, prêmio e gemas de primeira vez. Substituiu "Mundos" no menu.
- **Muralha no lugar da cerca**: a ilha é fechada por montanhas em degraus de
  14 studs (o pulo do Roblox sobe 7,2), com a única abertura na boca do
  corredor. O render valida essa altura.
- **Mundos 2–5 dormentes** (C3): deixaram de ser construídos (~4.000 peças a
  menos por servidor) e quem tinha save neles é trazido para a praça na carga.
- Specs novas: LevelFormula, CutLogic, AuraRuneLogic, CosmeticLogic.
- `TESTING.md` com a lista de 28 verificações manuais da reestruturação.

## Passada de UI/UX — redução de poluição visual ✅ FEITA

Só apresentação; nenhum sistema, economia ou funcionalidade mudou.

**Removido da tela**: painel grande de metas (3 barras permanentes), texto solto
de Power por clique na coluna, linha "Cosmético" repetida em cada card de espada
e de aura, badge permanente de Runas/Espadas/Progresso.

**Compactado**: moedas −18% (162×44), botões de menu −25% (54px), botão CLIQUE
de 300×90 para 230×70, barra de nível de 520×44 para 330×26, buffs viraram chip
pequeno sob as moedas.

**Contextual**: faixa do Caminho (estágio, nome, barra de HP, prêmio) aparece só
perto de uma barreira e abre o painel completo no clique; missões viraram o chip
"📋 Missões 2/3"; Progresso saiu da grade permanente para o "Mais".

**Sempre visível**: moedas no topo, 4 botões principais + "Mais", ganho por
clique, botão CLIQUE e barra de nível.

**Nomenclatura**: "Torre" saiu de todos os textos visíveis — a identidade é
CAMINHO DO PODER. Ids internos e DataStore ficaram como estavam de propósito.

Ocupação vertical no canvas de referência (1280×720): topo 12%, rodapé 21%,
menu 25%, **67% da altura livre no meio** para mapa e personagem.

## Fase 14 — Lançamento

- Revisão de economia com simulação (jogador casual, dedicado, pagante).
- Passada de som e de desempenho, teste em celular fraco.
- Auditoria de segurança e de dados.
- Ícone, thumbnails, descrição e publicação.

---

## Referências

- [Core loops — Roblox Creator Hub](https://create.roblox.com/docs/production/game-design/core-loops)
- [Roblox Simulator Games: Core Mechanics and Progression](https://metablox.gg/wiki/genres/simulation/)
- [Roblox Clicker Games: Fast Progression and Core Mechanics](https://metablox.gg/wiki/genres/clicker/)
- [Clicker Simulator (Roblox)](https://www.roblox.com/games/134719268825886/Clicker-Simulator)
- [Boxing Clicker Simulator (Roblox)](https://www.roblox.com/games/14361173627/Boxing-Clicker-Simulator)
