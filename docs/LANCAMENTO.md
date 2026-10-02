# Checklist de lançamento — Power Clicker

Ordem sugerida. O que está marcado já está feito no código; o que tem `[ ]` depende de você.

## 1. Antes de publicar

- [x] 180+ testes automáticos passando no Studio
- [x] Audit estático limpo (`python tools/audit.py`)
- [x] Economia simulada (`python tools/simulate_economy.py --hours 3`)
- [x] Salvamento com trava de sessão, migração de versão e proteção contra perda de dados
- [x] Debug travado fora do Studio (`AdminConfig.DebugEnabledInLive = false`, lista vazia)
- [x] Passes e produtos com IDs reais no `ProductConfig`
- [x] 34 imagens enviadas e ligadas em `AssetIds`
- [ ] Ícone e as 3 thumbnails na página do jogo (`art/upload_web/`)
- [ ] Nome e descrição da experiência revisados
- [ ] Teste de compra real no jogo publicado (produto barato primeiro)
- [ ] Teste de salvamento: jogar, sair, voltar e conferir o progresso

## 2. Configurações do jogo (Studio → Configurações)

- [ ] **Studio Access to API Services** ligado (para testar DataStore no Studio)
- [ ] Gênero e faixa etária preenchidos
- [ ] Chat e bate-papo conforme a faixa etária escolhida
- [ ] Servidores: 12 a 20 jogadores por servidor é o comum para simuladores

## 3. Opcionais que ainda posso ligar

- [ ] **Grupo do jogo**: me passe o ID para ativar o presente de grupo (`SocialConfig.Group.GroupId`)
- [ ] **Sons**: todos os efeitos estão com ID vazio (`AudioConfig`); o jogo roda em silêncio até você subir os sons
- [ ] **Modelos 3D de pets e ovos**: hoje são imagens; dá para usar modelos em `Assets.Pets`
- [ ] **Mundos 2 a 5**: só o Treino está liberado (`WorldConfig.Enabled`); os outros ficam para atualizações

## 4. Depois de publicar

- [ ] Ver o gráfico de retenção do dia 1 na página de estatísticas
- [ ] Conferir erros no Developer Console do jogo ao vivo (F9)
- [ ] Ajustar preços conforme a conversão real
- [ ] Trocar a temporada do passe (`SeasonConfig.Id`) quando a primeira acabar

## 5. Como publicar (quando a tela do Studio falha)

A tela "Publicar experiência" do Studio às vezes trava em "Falha ao buscar" e não
lista as experiências. Nesse caso, publique pela API:

1. `python tools/build_place.py` (gera `build/PowerClicker.rbxlx`)
2. Abra esse arquivo no Studio e **salve com Ctrl+S**. O XML que geramos é
   simplificado e a API o recusa ("Invalid Content stream"); ao salvar, o Studio
   reescreve o arquivo no formato dele, que ela aceita. Não precisa de `.rbxl`.
3. Defina as variáveis (chave com permissão **Place Publishing**, universo e lugar).
4. `python tools/publish_place.py --saved` para testar sem liberar aos jogadores.
5. `python tools/publish_place.py` para publicar.

Depois de publicar, entre no jogo e aperte **F9**: se aparecer
`USING MockDataStoreBackend` em laranja, foi enviado o arquivo de teste — republique.

## 6. Comandos úteis

```bash
python tools/audit.py
```

```bash
python tools/simulate_economy.py --hours 3
```

```bash
python tools/check_world_layout.py
```

```bash
python tools/build_place.py
```

```bash
python tools/build_place.py --studio-mock
```
