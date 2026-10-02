# Fundação reaproveitável

O que foi construído aqui que **não é específico de clicker** e vale copiar para um
jogo novo. A ideia: começar o próximo projeto com o encanamento pronto (dados,
rede, boot, UI, ferramentas) e gastar o tempo na mecânica.

Tudo abaixo é caminho relativo à raiz do PowerClicker.

---

## 1. O que copiar (e em que ordem)

Copie nesta ordem — cada nível só depende dos anteriores.

### Nível 1 — utilitários puros (copiar inteiro, sem editar)

| Arquivo | Para que serve |
| --- | --- |
| `src/shared/Utils/Logger.luau` | log com prefixo por sistema; é o único lugar com `print` |
| `src/shared/Utils/Signal.luau` | eventos internos entre serviços |
| `src/shared/Utils/Try.luau` | `pcall` com mensagem útil; usado no boot |
| `src/shared/Utils/TableUtil.luau` | cópia profunda, `DeepFreeze`, `IsArray` |
| `src/shared/Utils/Guard.luau` | validação de argumento de remote (`Args`, `OneOf`, `KeyOf`, `Integer`...) |
| `src/shared/Utils/RateLimiter.luau` | token bucket por jogador |
| `src/shared/Utils/NumberFormat.luau` | `1.2K`, `3.4M`, duração — só se o jogo mostrar números grandes |

### Nível 2 — dados (a parte que mais dá trabalho e mais dói se faltar)

| Arquivo | Observação |
| --- | --- |
| `src/server/Services/DataService/init.luau` | carga com retry, lock de sessão, autosave, `BindToClose`, `MarkChanged` para replicar só o que mudou |
| `src/server/Services/DataService/PlayerDataStore.luau` | acesso ao DataStore com lock e retentativa |
| `src/server/Services/DataService/DataSanitizer.luau` | NaN/inf/Instance/chave numérica → conserta e reporta, em vez de perder o save inteiro |
| `src/server/Services/DataService/Migrations.luau` | `Steps[n]` leva da versão n para n+1; roda em cópia, se falhar não toca no original |
| `src/server/Services/DataService/DataStoreBackend.luau` / `MockDataStoreBackend.luau` | real vs. memória (Studio), com aviso alto de que o mock não salva |
| `src/server/Services/DataService/DataTemplate.luau` | **troque o conteúdo**, mantenha a estrutura (`Create(now)` + `ServerOnlyKeys`) |
| `src/server/ServerConfig/DataConfig.luau` | **troque `StoreName`** antes de rodar. Manter o nome do PowerClicker misturaria os dados dos dois jogos |

Regra que veio junto e vale manter: **mudou a forma de `PlayerData` → sobe
`DataVersion` e escreve a migração**. Os testes em `src/server/Tests/Data/`
cobrem isso e também podem ser copiados.

### Nível 3 — rede

| Arquivo | Observação |
| --- | --- |
| `src/shared/Net/RemoteDefinitions.luau` | **esvazie a tabela** e declare os remotes do jogo novo. A regra fica: todo `ClientToServer` precisa de `RateLimit` |
| `src/server/Services/NetService.luau` | cria os remotes a partir da tabela, aplica rate limit, valida com `Guard`, avisa no boot se algum remote não tem handler |
| `src/client/Net/ClientNet.luau` | `Fire`, `Invoke` (com timeout e resposta padrão), `On` |
| `src/server/Services/AntiExploitService.luau` | só se o jogo novo tiver ação repetida do cliente |

O contrato que sustenta tudo: **o cliente nunca é confiável**. Ele pede, o
servidor decide, e a resposta é sempre `{ Ok, Code?, Data }` — nunca um erro cru.

### Nível 4 — boot

| Arquivo | Observação |
| --- | --- |
| `src/server/ServerBootstrap.server.luau` | congela configs → valida → `Init()` de todos → `Start()` de todos → testes no Studio. **Troque só o `SERVICE_ORDER`** |
| `src/client/ClientBootstrap.client.luau` | mesma ideia com `CONTROLLER_ORDER` |
| `src/shared/Formulas/ConfigValidator.luau` | **reescreva as regras**, mantenha o formato: recebe um "bundle" e devolve lista de erros, então dá para testar com config quebrada de propósito |
| `src/server/Tests/TestRunner.luau` | roda os `*.spec.luau` no Studio |

Serviço novo = arquivo em `Services/` com `Init`/`Start` + uma linha no
`SERVICE_ORDER` depois de quem ele depende. `Init` não pode ceder (yield).

### Nível 5 — UI e texto

| Arquivo | Observação |
| --- | --- |
| `src/client/UI/Build.luau` | `Build.new/label/button/icon/corner/progressBar` + mapeamento automático de cor para painel claro |
| `src/client/UI/Anim.luau` | pop, shake, flash, contagem, partículas |
| `src/client/UI/Theme.luau` | **troque as cores e ícones**, mantenha a estrutura (`Colors`, `Panel`, `Hud`, `Icons`, `IconImages`) |
| `src/client/Controllers/UIController.luau` | canvas com escala uniforme, `CreatePanel`, painel único aberto por vez |
| `src/client/Controllers/MenuController.luau` | grade de botões com tooltip e badge |
| `src/client/Controllers/DataController.luau` | espelho somente-leitura dos dados do servidor |
| `src/client/Controllers/NotificationController.luau` | toasts |
| `src/shared/Localization/` | `Text.Get/GetFor/Name`, pt-BR + en, com teste de paridade de chaves |

### Nível 6 — ferramentas (copiar a pasta `tools/` e ajustar os nomes)

| Arquivo | Observação |
| --- | --- |
| `tools/build_place.py` | gera o `.rbxlx` sem Rojo, seguindo as convenções do Rojo. Ajuste o nome do place e o `default.project.json` |
| `tools/publish_place.py` | publica via Open Cloud. **Lê a chave de `ROBLOX_API_KEY` do ambiente — a chave é sua e nunca entra no repositório nem no chat.** Ajuste `universe`/`place` |
| `tools/audit.py` | remotes sem handler/listener, `print` fora do Logger, globais depreciados, chaves de string duplicadas ou faltando, tabela por jogador que nunca é limpa |
| `tools/upload_assets.py` | sobe as imagens e gera `AssetIds.luau` (retomável) |
| `tools/remove_checker.py` / `remove_flat_bg.py` | recorte de fundo da arte gerada por IA |

---

## 2. O que **não** copiar

Isso é PowerClicker, não fundação:

- `src/shared/Config/` — exceto `GameConfig.luau` (nome, versão, localização,
  limites numéricos), que vale como modelo.
- `src/shared/Formulas/` — exceto `ConfigValidator`; o resto é economia de clicker.
- `src/server/Logic/`, quase todos os `Services/` de jogo (Click, Pet, Egg,
  Rebirth, Overdrive, Zone, Target, Boss, Season, Aura, Rune...).
- `src/server/World/WorldBuilder.luau` — o mapa é deste jogo.
- Arte em `art/` e os ids em `AssetIds.luau`.

---

## 3. Armadilhas que já custaram tempo aqui

Vale levar prontas para o próximo:

1. **Publicação**: o `.rbxlx` gerado pelo `build_place.py` é recusado pela API
   ("Invalid Content stream"). O ciclo que funciona é: gerar → abrir no Studio →
   `Ctrl+S` → `publish_place.py`. O script já checa isso e recusa o arquivo errado.
2. **`--saved` não publica**: sobe a versão sem colocar no ar. Sem a flag = ao vivo.
3. **Nunca publicar o build `_StudioMock`**: ele usa armazenamento em memória e
   não salva nada. O `publish_place.py` se recusa.
4. **Chave de DataStore**: tabela salva não pode ter chave numérica misturada com
   formato de lista — guarde número como string (`["7"] = true`).
5. **BillboardGui**: dimensionar em *studs* (`UDim2.fromScale`) e não em pixels,
   senão a placa fica gigante de perto e ilegível de longe.
6. **`FindFirstChildOfClass` devolve `Instance?`**: sob `--!strict`, checar com
   `:IsA(...)` antes de usar propriedade específica.
7. **API que cede (yield) em signal**: `IsFriendsWithAsync`, `IsInGroupAsync` e
   afins precisam de `task.spawn` para não travar quem disparou o sinal.
8. **Ícone que não carrega**: `ImageLabel.IsLoaded` mente para painel fechado
   (o Roblox só baixa quando vai desenhar). Use `ContentProvider:PreloadAsync`
   com callback de status e caia para emoji quando falhar.

---

## 4. Ordem sugerida para começar o jogo novo

1. Pasta nova + `default.project.json` + `tools/`.
2. Níveis 1 a 4 acima (utilitários → dados → rede → boot). Nesse ponto o jogo
   sobe vazio, salva e replica — é o marco que importa.
3. `DataTemplate` com a forma de dados do jogo novo e `DataConfig.StoreName` próprio.
4. Um serviço de mecânica + um controller, ponta a ponta, com um remote só.
5. Localização e `tools/audit.py` ligados desde cedo — corrigir chave faltando
   depois de 300 strings é bem pior.

---

*Escrito ao fechar o PowerClicker (auras, runas e compra em lote publicadas).
O estado e as pendências do jogo em si estão no `ROADMAP.md` e no `LANCAMENTO.md`.*
