# Power Clicker — auditoria e plano da Torre

> **Correção de layout (durante a Fase H):** a torre vertical virou um
> **corredor reto horizontal** (Tower Layout → Linear Progression Corridor).
> Os dez estágios, o HP, as recompensas e todos os sistemas continuam os
> mesmos; mudou a geometria. Ver ROADMAP.md.

Documento das Etapas 1 e 2 do pedido de reestruturação. **Nada de economia foi
alterado para escrever isto**; os números abaixo são os que estão no projeto
hoje.

---

## 1. Auditoria — o que existe

34 serviços no servidor, 32 controllers no cliente, `DataVersion 5`,
180 arquivos Luau, `tools/audit.py` limpo.

### Sistemas completos e em produção

| Sistema | Onde | Observação |
| --- | --- | --- |
| Dados (lock de sessão, migração, sanitização) | `DataService/*` | 5 versões, migrações testadas |
| Rede validada (rate limit + Guard) | `NetService`, `RemoteDefinitions` | 29 remotes, todo ClientToServer com limite |
| Clique (combo, overdrive, auto, hold) | `ClickService`, `ClickController` | hold a 9/s com jitter |
| Força (12 camadas + base) | `PowerService`, `PowerFormula` | provedores registrados por sistema |
| Melhorias (temporárias e permanentes) | `UpgradeService` | compra 1x/10x/Máx |
| Renascimento | `RebirthService`, `RebirthConfig` | custo 200K × 2,3^r, +0,5 mult/renasc. |
| Pets e ovos | `PetService`, `EggService` | 17 pets, 3 ovos, pesos documentados |
| Monetização | `MonetizationService` | 5 passes + 8 produtos com id real; escada x2→x4→x8 |
| Vitórias + corredor | `WallService`, `WallConfig` | 6 estágios, fileiras, pads, teleporte |
| Cortes (dano fixo por clique) | `CutService`, `CutConfig` | 8 níveis, pads com prompt |
| Auras | `AuraService` | 6 auras, gemas, +velocidade e +Power |
| Runas | `RuneService` | 20 runas, drop de chefe |
| Temporada, missões, conquistas, códigos, social, cosmético, ranking | vários | funcionando |

### Sistemas desligados ou órfãos

| Item | Situação | Impacto |
| --- | --- | --- |
| Zonas de treino (ilhas, pontes, monstros) | `ZoneConfig.Build = false` | **a maior fonte de Power do jogo saiu do ar** |
| `ZoneService` / `TargetService` | rodando, sem alvos | ociosos, sem erro |
| Mundos 2–5 (Cidade, Vulcão, Espaço, Galáxia) | existem, com multiplicador ×10 a ×10.000 | conflitam com "uma torre só" (ver §3) |
| Chefe (`BossService`) | gira entre mundos | é a única fonte de runas |
| Sons | todos os `SoundId` vazios | nenhum áudio no jogo |
| `simulate_economy.py` | modela zonas/alvos | **diagnóstico atual é inválido** |

### Economia hoje (valores reais)

- **Clique**: base 1 + melhoria `ClickStrength` (+1/nível, custo 20 × 1,2^n) + corte (Corte 1 = +1 … Corte 8 = +400).
- **Multiplicadores**: `PowerBoost` (+25%/nível), renascimento (+50% cada), pets (soma dos bônus: Dog +10% … Dragão Celestial +2000%), mundo (×1 a ×10.000), aura (×1,05 a ×3), runas (até ×2,2 cada, 3 slots), passes, boosts, combo, overdrive.
- **Ovos**: Básico 2K Power; Floresta 25 gemas; Místico 150 gemas.
- **Renascimento**: 200K Power, crescendo ×2,3; dá 15 + 8×r gemas.
- **Barreiras**: 60 → 1,2K → 25K → 600K → 20M → 900M de HP por fileira (4 a 6 fileiras).
- **Vitórias**: pads de +1/+2 até +4K/+8K.

### Riscos de regressão identificados

1. **Buraco de renda**: com as zonas desligadas, sobraram clique, orbes e baús de sessão. A curva que levava ao primeiro renascimento em ~13 min (jogador dedicado) não existe mais nesse formato.
2. **Projeto sem git**: não há desfazer. Qualquer remoção grande precisa ser feita por flag (como foi com as zonas), não por apagar arquivo.
3. **Jogadores reais já têm dados** (`DataVersion 5`, compras de gemas e passes feitas). Toda mudança de forma exige migração.
4. **Simulador defasado**: qualquer número que ele imprimir hoje está errado para o jogo atual.

---

## 2. Conflitos entre o pedido e o que já está implementado

Pontos em que o pedido contradiz algo que já existe e está no ar. **Precisam de
decisão sua antes da implementação.**

### C1 — Auras: cosmético ou poder?

O pedido diz "a aura não deve dar multiplicador de força por padrão". As auras
atuais dão **+velocidade e ×1,05 a ×3 de Power**, foram compradas com gemas e
estão publicadas.

- **Opção A (recomendada)**: as 6 auras atuais ficam como estão (quem comprou não perde nada) e a coleção nova — a de raridades Comum→Mítica do pedido — nasce **puramente cosmética**, com nome próprio na UI.
- **Opção B**: tirar o Power das auras atuais e devolver as gemas gastas por migração. Mais fiel ao pedido, mas mexe em compra feita.

### C2 — Espadas: progressão ou cosmético?

O pedido pede arma cosmética sem segunda economia de dano. Hoje a espada **é** a
representação visual do Corte, e o Corte dá dano fixo.

Proposta: manter a separação que já existe de fato — **Corte = progressão**
(dano, comprado com Power), **Skin da espada = cosmético** (modelo, cor,
partículas, efeito de corte). Não há conflito real, só de nome; o que falta é a
camada de skins.

### C3 — Mundos 2–5 vs "uma torre só"

O pedido diz explicitamente "não quero seis mapas independentes". Os mundos
existem, têm requisito de renascimento e multiplicador de ×10 a ×10.000 — ou
seja, **são a espinha dorsal da economia de longo prazo**.

- **Opção A (recomendada)**: os 10 estágios da torre **substituem** os mundos como progressão visível; os mundos viram dormentes por flag (como as zonas), e o multiplicador de mundo migra para o estágio da torre, preservando a curva.
- **Opção B**: manter os mundos e colocar uma torre em cada um (vira o que você não quer).

### C4 — Área de treino

As ilhas de treino acabaram de ser desligadas a seu pedido, e o novo texto pede
uma área de treino no lobby. São coisas diferentes: o pedido novo é uma área
**no chão do lobby**, com equipamentos, não ilhas flutuantes com ponte. É o que
eu faria — e ela resolve o buraco de renda do item 1.

---

## 3. Plano técnico

Ordem pensada por dependência: nada de UI antes de a torre existir, nada de
economia antes do simulador falar a verdade.

### Fase A — Simulador honesto (pré-requisito de tudo)

Sem isto, qualquer número é chute.

1. Reescrever `tools/simulate_economy.py` para o jogo atual: clique com hold, cortes, barreiras, vitórias, pets, treino, renascimento.
2. Perfis pedidos: casual, ativo, muito ativo, e **pós-renascimento**.
3. Saída: tempo até cada marco (1º ovo, 1º pet relevante, cada barreira, 1º renascimento, torre completa).
4. Entrega: diagnóstico em `ECONOMY.md`, **sem alterar valor nenhum ainda**.

### Fase B — Torre vertical de 10 estágios

5. `WallConfig` passa de 6 para 10 estágios, com tema, cor, material e HP por fileira.
6. Geometria vertical: o `WorldBuilder` monta a torre em altura (plataforma → barreira → plataforma), com elevador/escada entre estágios em vez do corredor plano de hoje.
7. `WallService` é reaproveitado inteiro: fileiras, HP, janela aberta, pads e teleporte já atendem ao pedido.
8. Estágio 10: arena maior, barreira colossal, efeito próprio e portal "em breve" (sem conteúdo falso atrás).

### Fase C — Lobby

9. Praça central, área de treino, área de ovos, área de pets, loja, renascimento e a entrada da torre — cada uma com identidade visual, não objetos soltos.
10. Torre visível do lobby.
11. Decoração: árvores, pedras, ilhotas, nuvens, cascata, iluminação.

### Fase D — Treino

12. Equipamentos físicos no lobby; o jogador interage e ganha Power por ciclo, com validação de servidor (sem laço por jogador: um tick central).
13. Indicador de "treinando" e de ganho por segundo.
14. Regra de equilíbrio: o treino rende menos por segundo que o clique ativo, mas não exige atenção — os dois continuam úteis.

### Fase E — Cortes, espadas e efeitos

15. Camada de **skins** de espada (modelo, cor, material) separada do Corte.
16. Efeitos de corte: trilha, impacto na barreira, efeito especial no golpe que quebra.
17. Teto de partículas por jogador para não derrubar FPS em servidor cheio.

### Fase F — Auras cosméticas

18. Coleção por raridade (Comum → Mítica), uma equipada por vez, desbloqueada por progressão.
19. Partículas limitadas e nada que tape o personagem ou a barreira.

### Fase G — Pets, ovos e renascimento

20. Ovos: chances explícitas na UI (já existem no servidor), animação por raridade, preço acompanhando a curva nova.
21. Inventário: ordenação por raridade e multiplicador, equipar melhores.
22. Renascimento: tela que mostra requisito, benefício, o que reseta e o que fica, antes de confirmar.

### Fase H — Economia

23. Só agora: ajustar valores com base na Fase A, documentando antigo → novo e o porquê.
24. Migração versionada se alguma forma de dado mudar.

### Fase I — UI/UX

25. Hierarquia: Força em destaque, Gemas e Vitórias menores; secundários agrupados.
26. HUD da torre: estágio, barreira, força necessária, dano, próxima recompensa — sem tapar a barreira.
27. Design system único (tipografia, cantos, cores, estados, espaçamentos).

### Fase J — Polimento

28. Sons (hoje não existe nenhum — depende de você subir os áudios).
29. Teste em celular, tablet e PC.

---

## 4. O que será preservado (compromisso)

- Todo o salvamento e os dados de quem já joga, com migração versionada.
- Pets, inventário, ovos e suas probabilidades.
- Melhorias, renascimento e seus dados.
- Passes e produtos já criados e vendidos.
- Vitórias, cortes, runas e auras já comprados.
- Arquitetura: servidor decide, cliente só mostra.

---

## 5. O que depende de você

1. **Decidir C1, C2 e C3** (auras, espadas, mundos).
2. Sons: nenhum `SoundId` está preenchido.
3. Ícone e thumbnails na página do jogo (`art/upload_web/`).
4. Ids dos passes 4x e 8x, se quiser a escada completa.
5. Animação de golpe da espada (precisa de um asset de animação publicado na sua conta).

---

*Etapas 1 e 2 do pedido de reestruturação. A implementação começa pela Fase A,
que não altera nenhum valor — só mede.*
