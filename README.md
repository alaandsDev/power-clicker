# Power Clicker

Roblox clicker/simulator. Server-authoritative, config-driven, modular Luau.

**Status: all 8 phases implemented.** Validated in Studio up to Phase 2. Phases 3–8 are built, statically audited and unit tested, but still need a Studio run (see [MVP checklist](#mvp-checklist)). Core loop, pets & eggs, worlds, retention, monetization, polish and audit are all done; PT-BR is the default language.

Other docs: [ECONOMY.md](ECONOMY.md) · [SECURITY.md](SECURITY.md) · [TESTING.md](TESTING.md)

---

## Getting the code into Studio

### Option A — Rojo (recommended, live sync)
1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder (installs the Rojo version pinned in `rokit.toml`).
2. Install the Rojo plugin in Studio.
3. `rojo serve` → in Studio: Plugins › Rojo › Connect.

### Option B — no tools (standalone place)
```bash
python tools/build_place.py
```
Opens as `build/PowerClicker.rbxlx`. For offline Studio testing (unpublished place):
```bash
python tools/build_place.py --studio-mock
```
→ `build/PowerClicker_StudioMock.rbxlx`, which uses the in-memory **MockDataStoreBackend (nothing is saved)**. Source files are never modified by this flag.

Static audit (no Roblox needed): `python tools/audit.py`

> `src/` is the source of truth. Never edit scripts inside Studio for a build place — changes are lost on the next build.

---

## Architecture

```
ReplicatedStorage.Shared          (src/shared)   — visible to clients: NO secrets
  Config/        all balancing data (economy, pets, eggs, worlds, products...)
  Formulas/      EconomyFormulas, PowerFormula, ComboLogic, EggOdds, WorldRules,
                 DailyRewardLogic, TimeRules (pure, shared), ConfigValidator
  Localization/  Text module + Strings/ptBR, Strings/en (all player-facing text)
  Net/           RemoteDefinitions (single source of truth for remotes)
  Utils/         Signal, TableUtil, Logger, RateLimiter, Guard, Try, NumberFormat
  Types          shared Luau types (PlayerData, PetData, EggData...)
ReplicatedStorage.Remotes         created at runtime by NetService ONLY
ReplicatedStorage.Assets/{Pets,Eggs}  client-rendered models (TODO_ASSET; placeholders used)

ServerScriptService.Server        (src/server)
  ServerBootstrap                 the only server Script
  ServerConfig/  server-only: DataConfig, AdminConfig, CodeConfig, AntiExploitConfig, DevConfig
  Services/      AntiExploitService, NetService, DataService/, CurrencyService, PowerService,
                 OverdriveService, PetService, EggService, WorldService, ClickService,
                 UpgradeService, RebirthService, BoostService, RewardService,
                 DailyRewardService, QuestService, AchievementService, CodeService,
                 LeaderboardService, MonetizationService, SettingsService, DebugService
  Logic/         pure rules: CurrencyLogic, UpgradeLogic, RebirthLogic, PetLogic, EggLogic,
                 WorldLogic, BoostLogic, RewardLogic, QuestLogic, AchievementLogic,
                 CodeLogic, PurchaseLogic, ClickPatternDetector
  World/         WorldBuilder (procedural low-poly maps + interactive stations)
  Tests/         TestRunner + *.spec modules (Studio only)

ServerStorage.Assets/Worlds       server-only models (TODO_ASSET)
StarterPlayerScripts.Client       (src/client)
  ClientBootstrap                 the only LocalScript
  Controllers/   DataController, UIController, SoundController, NotificationController,
                 GameStateController, MenuController, HudController, ClickController,
                 UpgradeController, RebirthController, PetController, EggController,
                 WorldController, RewardsController, QuestController,
                 LeaderboardController, ShopController, VipController,
                 SettingsController, TutorialController, PetFollowController,
                 DebugController
  UI/            Theme, Build (instance helpers), Messages, RewardText
  Net/           ClientNet
ReplicatedFirst.LoadingScreen     (src/first) branded loading screen until data arrives
Workspace.Map/{Worlds,Spawns,Teleporters,Interactables}
```

### Boot order (ServerBootstrap)
1. Deep-freeze every config module (runtime mutation → error).
2. `ConfigValidator` cross-checks all configs. Errors abort boot in Studio.
3. `Init()` each service in `SERVICE_ORDER` (wiring only, no yields).
4. `Start()` each service (loops, player events).
5. Studio only: run unit tests.

Add a service: create `Services/<Name>.luau` with `Init`/`Start`, append to `SERVICE_ORDER` after its dependencies. No circular requires. When two services would depend on each other, inject a callback (see `NetService.SetReadyPredicate`).

### Data flow
```
Client ──(intent + ids)──▶ NetService gate ──▶ Service (validates state, mutates data)
                          rate limit / ready /             │
                          argument validation              ▼
                                               DataService.MarkChanged(player, key)
                                                           │ batched every 0.1 s
Client ◀──── DataChanged(key, value) / DataSnapshot ───────┘
```
The client never sends amounts, prices, multipliers or results.

### Services
| Service | Responsibility |
|---|---|
| AntiExploitService | Collects suspicion signals, decays them, logs thresholds. Never bans; kick disabled by default. |
| NetService | Creates remotes from `RemoteDefinitions`; direction check, rate limit, data-ready check, argument validation, protected handler. |
| DataService | Session-locked load/save, migrations, reconcile, sanitize, autosave, BindToClose, batched replication. Signals: `PlayerLoaded`, `PlayerReady` (data + client listening), `PlayerReleasing`, `DataReset` (Studio). |
| CurrencyService | The only way currencies change (`Add/Remove/Reset/CanAfford`). Never yields, so check-then-mutate is atomic. |
| PowerService | Builds `PowerFormula` inputs, caches power per click, multiplier **providers** per layer, pushes `PowerInfo`. |
| OverdriveService | Charge from manual clicks, activation/duration/cooldown, `Overdrive` provider. |
| ClickService | `Click` remote: combo, gain, stats, overdrive charge, pattern signal; server-side Auto Click ticks; batched `ClickFeedback`. |
| UpgradeService | `BuyUpgrade(id)` via UpgradeLogic; invalidates power. |
| RebirthService | `Rebirth()` via RebirthLogic; resets/rewards; notifies. |
| PetService | `PetAction(action, uid?)`: equip/unequip/equip best/lock/delete via PetLogic; `Pet` power provider; `Grant()` for trusted sources; publishes `EquippedPets`/capacity attributes. |
| EggService | `HatchEgg(eggId)`: EggLogic with a server `Random`; luck providers; broadcasts rare hatches. |
| WorldService | `UnlockWorld` / `TravelWorld`; server-side teleport to `Map.Spawns.<SpawnName>`; placeholder maps for enabled worlds without art. |
| BoostService | Remaining-seconds boosts ticked while online; `TemporaryBoost` power provider + `Boosts` luck provider. |
| RewardService | Atomic grant of reward lists (currency/boost/pet) for every source. |
| DailyRewardService | `ClaimDaily` on the server clock (7-day cycle, 20h interval, 48h streak reset). |
| QuestService | Generic quests fed by gameplay signals; `ClaimQuest`; daily reset (UTC); playtime tracking. |
| AchievementService | Data-driven achievements evaluated ≤1/s per player; auto-granted rewards (retried if blocked). |
| CodeService | `RedeemCode`; server-only CodeConfig; once per player; optional global cap via atomic DataStore counter. |
| LeaderboardService | leaderstats (Power, Rebirths) + global OrderedDataStore boards (Clicks, Rebirths, Power log-scale), batched writes/reads. |
| MonetizationService | Game pass ownership + benefits (GamePass power/luck layers, extra pet slots, auto click, VIP), `ProcessReceipt` (idempotent ledger + SaveNow before `PurchaseGranted`), server-side purchase prompts. |
| SettingsService | `UpdateSettings(key, value)` with per-key validation (volumes 0–1, booleans). |
| DebugService | Dev commands gated by AdminConfig (Studio: on; live: off). |

Game rules live in `src/server/Logic/*` as pure functions over `PlayerData` (unit tested); services only add remotes, signals and replication.

### Remotes
| Name | Direction | Purpose |
|---|---|---|
| ClientReady | C→S | Client listeners are connected; send snapshot |
| Click | C→S | "I clicked" with no arguments; 20/s + burst 10 |
| BuyUpgrade | C→S (fn) | `(upgradeId)` → `{Ok, Code, Data={Level,Cost}}` |
| Rebirth | C→S (fn) | `()` → `{Ok, Code, Data={Rebirths,Gems}}` |
| HatchEgg | C→S (fn) | `(eggId)` → `{Ok, Code, Data={Uid,PetId,Rarity,...}}` |
| PetAction | C→S (fn) | `(action, uid?)` Equip/Unequip/EquipBest/Delete/Lock/Unlock |
| UnlockWorld | C→S (fn) | `(worldId)` requirements + cost server-side |
| TravelWorld | C→S (fn) | `(worldId)` server teleports the character |
| ClaimDaily | C→S (fn) | `()` server clock only |
| ClaimQuest | C→S (fn) | `(questId)` |
| RedeemCode | C→S (fn) | `(code)` 1 per 5 s (brute-force protection) |
| PromptPurchase | C→S (fn) | `(key)` server validates, then opens the Roblox prompt |
| SetAutoClick | C→S (fn) | `(enabled)` requires the Auto Click pass |
| UpdateSettings | C→S (fn) | `(key, value)` validated per key |
| DebugCommand | C→S (fn) | `(command, amount?)`, AdminConfig-gated |
| DataSnapshot | S→C | Full client-safe data view |
| DataChanged | S→C | `(topLevelKey, value)` batched |
| Notify | S→C | `(kind, payload)` toasts (e.g. Rebirth) |
| ClickFeedback | S→C | `(manualGain, manualClicks, combo, autoGain)` batched |
| PowerInfo | S→C | `{PerClick, Base, Total, Layers}` on change |
| OverdriveState | S→C | `(active, remaining, cooldown)` |
| Leaderboards | S→C | `{ [boardId] = { Entries, Local } }` every refresh |
| DebugAccess | S→C | `(allowed)` once on ready |

`Purchases` is server-only and never replicated (`DataTemplate.ServerOnlyKeys`).

---

## How to…

**Add a pet** — `Config/PetConfig.luau`: add `Id = pet("Id", "Name", "Rarity", bonus, "EggId")`, then add `{ PetId = "Id", Weight = n }` to that egg in `EggConfig`, and a `pet.<Id>.name` string in both `Localization/Strings` files (a test enforces it). The validator fails the boot if pet and egg don't match. Never rename or remove a shipped pet id (it lives in player data). Model: put a BasePart named `ModelName` in `ReplicatedStorage.Assets.Pets` (placeholder ball otherwise).

**Add/translate text** — every player-facing string lives in `src/shared/Localization/Strings/ptBR.luau` and `en.luau` (same keys; tested). Use `Text.Get("key", { name = value })`. Default language: `GameConfig.Localization.ForceLocale` (`"pt-br"`; set `nil` to follow each player's Roblox language).

**Add an egg** — `EggConfig.Eggs`: new entry (`WorldId`, `Currency`, `Price`, `Drops`). Add its id to the world's `Eggs` list in `WorldConfig`.

**World maps** — `src/server/World/WorldBuilder.luau` generates every enabled world at server start: ground, spawn pad, egg stands (one per `WorldConfig.Eggs`), rebirth altar, portal and themed decoration, all deterministic. Stations have ProximityPrompts (`E` / gamepad `Y` / tap) that open the matching panel; actions still go through remotes. Lighting per world lives in `Config/AmbientConfig.luau` and is applied client-side. To use a hand-made map, place a model named `<WorldId>` in `Workspace.Map.Worlds` plus a spawn part in `Workspace.Map.Spawns`; the builder then skips that world. Only use free models from verified creators, and delete every script inside them (backdoor risk).

**Add a world** — `WorldConfig.Worlds`: unique `Order`, `Multiplier`, `Requirement`, `SpawnName`, `Eggs`, plus `world.<Id>.name` strings. Build the map as `Workspace.Map.Worlds.<Id>` and a spawn part `Workspace.Map.Spawns.<SpawnName>` (otherwise a placeholder platform is generated). Keep `Enabled = false` until the map is ready; in Studio `GameConfig.Dev.EnableAllWorldsInStudio` lets you test disabled worlds.

**Add a gamepass / product** — create it in the Creator Dashboard, then in `ProductConfig` set the real `GamePassId` / `ProductId` (0 = "Em breve": never prompted or granted). Products grant `Rewards` (`Currency`/`Boost`/`Pet`) through the idempotent receipt flow; passes grant `Benefits` (PowerMultiplier, LuckMultiplier, ExtraEquipSlots, AutoClick, Vip). Add `pass.<Key>.name/.desc` or `product.<Key>.name` strings. Prices are always read live from Roblox; `SuggestedPriceRobux` is documentation only.

**Go-live checklist for monetization**: create the 5 passes + 8 products, paste ids in `ProductConfig`, publish, test each purchase in a live test server (Studio purchases are free test purchases), verify the receipt log line and that rejoining doesn't re-grant.

**Add a quest** — `QuestConfig.Quests`: pick an existing `Type` (Clicks, Rebirths, EggsOpened, PetsHatched, Playtime, Overdrives, WorldsUnlocked), set `Target`, `Rewards`, `Repeat` ("Once"/"Daily") and add `quest.<Id>.name` strings.

**Add an achievement** — `AchievementConfig`: either `Stat` + `Threshold` (stat must exist in `PlayerData.Stats`) or `WorldId`; add `achievement.<Id>.name/.desc` strings.

**Add a promo code** — `src/server/ServerConfig/CodeConfig.luau` only (never in Shared). Uppercase A–Z/0–9, optional `ExpiresAt` (unix UTC) and `MaxRedemptions` (global, atomic counter).

**Add a power multiplier** (pets, boosts, gamepasses...). Never multiply power anywhere else. In your service's `Init`:
```lua
PowerService.RegisterProvider("Pet", function(player, data) return 1 + petBonus end)
```
and call `PowerService.Invalidate(player)` whenever that value changes. The layer name must be in `EconomyConfig.MultiplierLayers`.

**Add an upgrade** — `UpgradeConfig.Temporary` (Power, resets) or `.Permanent` (Gems, kept). Ids must be unique across both. `EffectType` decides what it does; new effect types need code where they are consumed.

**Add a remote** — `Net/RemoteDefinitions.luau` (ClientToServer needs a `RateLimit`), then in the owning service's `Init`:
```lua
NetService.On("OpenEgg", Guard.Args(Guard.KeyOf(EggConfig.Eggs)), function(player, eggId) ... end)
```

**Change the data schema** — see "Data" below.

---

## Data

- Store: `DataConfig.StoreName`, key `Player_<UserId>`, **UpdateAsync only**.
- Record: `{ Data = PlayerData, Meta = { Session, LastReleasedSession, CreatedAt, LastSaveTime, SaveCount, LoadCount } }`.
- Session lock per join (GUID). A lock not refreshed for `StaleLockSeconds` (300 s) may be taken over (crashed server). Autosave refreshes it every 60 s.
- Load outcome: `New` only when the store answered successfully with no record. `Failed`, `Locked`, `Corrupt`, `FutureVersion` → player is kicked with an explanation; **nothing is saved for that session**.
- Schema change: bump `DataConfig.DataVersion`, add `Migrations.Steps[old] = function(data) ... end`. Migrations run on a copy; if one fails the original data is kept and the player is kicked.

---

## Decisions log (Phase 1)

| Decision | Why |
|---|---|
| Rojo file layout + Python build fallback | Code in git / reviewable; the fallback works with no install. |
| Custom session locking (no ProfileStore) | No third-party dependency needed; small and fully unit tested. ProfileStore is a valid later swap. |
| Session id per join, not per server | A fast rejoin to the same server cannot load stale data under our own lock. |
| No automatic fallback to the Mock backend | A silent fallback would pretend data is saved. Mock is opt-in, Studio-only, loudly logged. |
| Boost multipliers: highest per category, don't multiply | Keeps paid boosts strong but bounded (see ECONOMY.md). |
| Numbers are doubles capped at `1e100` | Plenty for a clicker; always finite and JSON-safe. |
| Auto Click = server ticks, doesn't build combo/overdrive | No client-reported click counts; active play still matters. |
| One `Click` event per click (no client batching) | A client-reported "N clicks" is exactly what must never be trusted; 20/s is cheap. |
| Pure `Logic/` modules + thin services | Economy rules are testable without Players/DataStores. |
| UI built in code (no Studio-authored GUI) | Everything reviewable in git; uniform `UIScale` from a 1280x720 reference, device safe area. |
| UI text in English | Roblox auto-translation localizes English source strings (PT-BR included). |
| Combo/floating numbers predicted on the client | Instant feedback; server values (Power, combo) always win. |

---

## Roadmap
- [x] **Phase 1** — structure, bootstrap, types, configs, DataService, networking, tests, docs
- [x] **Phase 2** — Power, Click (+rate limit), Combo, Overdrive, Upgrades, Gems, Rebirth, base UI, DebugService
- [x] PT-BR localization (all text in `Localization/`)
- [x] **Phase 3** — Pets, inventory, equip, eggs, server RNG, pet multiplier, pet visuals
- [x] **Phase 4** — Worlds (unlock, travel, server teleport, world multiplier, eggs per world, placeholder maps)
- [x] **Phase 5** — Boosts core, daily rewards, quests, achievements, codes, leaderboards + leaderstats
- [x] **Phase 6** — Game passes, developer products (ProcessReceipt), boosts, VIP (tag, +25%, exclusive pet), starter pack, shop UI
- [x] **Phase 7** — Onboarding derived from gameplay, settings panel, loading screen, panel transitions, click ring, Overdrive glow, reduced-effects mode, SFX registry (TODO_ASSET audio)
- [x] **Phase 8** — Economy simulation + rebalance (ECONOMY.md), static audit tool (`tools/audit.py`), security/performance review (SECURITY.md)

## MVP checklist

✅ done and verified in Studio · 🧪 implemented + unit tested, needs a Studio/live run · ⏳ needs Roblox-side setup

| Item | Status |
|---|---|
| Core, DataStore (session lock, retries, migrations, no data loss on failure) | ✅ (Mock backend) · ⏳ real DataStore needs a published place |
| Click, Combo, Overdrive, Upgrades, Rebirth, Gems | ✅ |
| Pets, Eggs, Inventory, Equip | 🧪 |
| Worlds | 🧪 (MVP ships Training only; others Studio-testable) |
| Daily rewards, Quests, Achievements, Codes | 🧪 |
| Leaderboards | 🧪 · ⏳ global boards need a published place |
| Game passes, Developer products | 🧪 · ⏳ create products, paste ids in ProductConfig |
| Mobile / console | 🧪 (uniform UIScale, big touch button, gamepad R2/X); needs a device-emulator pass |
| Multiplayer | 🧪 (per-player state everywhere, audited) · needs a 2–5 player Studio test |
| Anti-exploit (validation, rate limits, signals) | ✅ foundation · 🧪 Phase 3–6 remotes |
| Data-loss protection | ✅ |
| Performance / security / economy audits | ✅ (see SECURITY.md, ECONOMY.md) |
| Documentation | ✅ |
| No mocks posing as production | ✅ (only `MockDataStoreBackend`, Studio/test, loudly logged) |
| No critical values controlled by the client | ✅ (`tools/audit.py` + review) |
| Final assets (models, icons, audio, maps) | ⏳ every placeholder is marked `TODO_ASSET` |
