# Restore Rusty Tools

A Roblox game about rolling for rusty objects, restoring them by hand, selling or displaying them, and growing a workshop through a connected skill tree.

**Loop:** Roll → Receive item → Place on bench → Restore → Sell / Store / Display → Buy upgrades → Repeat.

This repository has the game code only. Item models, the map and every piece of UI are built in Roblox Studio. The code binds to them by name and CollectionService tag, and it never creates models or UI. The exact names and tags it expects are in [docs/STUDIO_BUILD_GUIDE.md](docs/STUDIO_BUILD_GUIDE.md).

## Setup

1. Install [Rojo](https://rojo.space) (7.x) and the Rojo Studio plugin.
2. Run `rojo serve` in this folder and connect from Studio. The project maps:
   - `src/Shared` → `ReplicatedStorage.Shared`
   - `src/Server` → `ServerScriptService.Server`
   - `src/Client` → `StarterPlayer.StarterPlayerScripts.Client`
3. In Studio, enable **Game Settings → Security → Enable Studio Access to API Services** to test real saving. Without it, the server uses temporary in-memory storage and warns you.
4. Build the assets, map and UI described in the build guide. The server prints the items that are still missing models. Items without a valid model can never be rolled, so a partly built catalog is safe.

### Running the automated checks

Set a boolean attribute `RunTests = true` on `Workspace` and press Play in Studio. The runner in `src/Server/Tests` prints `[Tests] N passed, M failed` and one line per failure. The tests cover roll odds (100,000-roll simulation), pity, economy transactions (no double charge or grant, sell-once, favorites, capacity), skill-tree structure (cycles, reachability, base-tool fallbacks), restoration math (spatial locality, empty-space contacts, flood and stall protection, calibration), profile migration and repair, and rate limiting.

Formatting and lint configs are included (`stylua.toml`, `selene.toml` with a minimal `roblox_lite.yml` std).

## Code layout

```
src/Shared/                 Replicated to everyone
  Config/                   All tunable data: items, rarities, pools, tools, stages, variants,
                            skill tree, collections, tutorial, commissions, schedules, cosmetics
  Config/Items/             Item catalog split by content phase (task 6, 31–36)
  Content/ItemCatalog       Resolves and validates item definitions
  Logic/                    Pure shared rules used by both server and client:
    RestorationMath         Spatial coverage model, calibration, completion
    RollOdds                Exact odds tables, luck, pity
    PriceCalculator         Sale and scrap prices
    StatCalculator          Derived stats and unlocks from skill nodes
    SkillTreeRules          Node state, descriptions, structural validation
    EffortEstimator         Expected job length shown at the reveal
    CoverageCodec           Compact cell coverage encoding (saves and network)
    CellVisuals             Coverage value → cell visibility
    Schedule                Day/week/featured rotation from server time
  Net/                      Remote contracts, argument validators, client remote access
  Util/                     Signal, Result, TableUtil, Format

src/Server/
  Main.server.luau          Initializes services in dependency order
  GameEvents                Cross-system gameplay signals
  Logic/                    Pure server logic (testable without players)
    ProfileSchema           Saved layout, migrations, location repair
    ProfileTransactions     Roll, sell, purchase and reset transactions
    ItemFactory             Creates owned items and rolls hidden traits once
    RateLimiter             Token buckets
  Services/                 One service per game system (see the table below)
  Tests/                    *.spec modules and the Studio test runner

src/Client/
  Main.client.luau          Initializes controllers
  Ui/UiUtil                 Binding helpers for Studio-built UI (finds, clones templates)
  Controllers/              Presentation and input only; the server decides every outcome
```

| Service | Responsibility |
| --- | --- |
| `ContentRegistry` | Validates config at startup; publishes which items have usable models |
| `PlayerDataService` + `DataStoreGateway` | Session-locked load, migration, autosave, release, shutdown |
| `NetworkService` | Creates remotes; rate limit, validation, loaded check, in-flight lock |
| `StateReplicator` | Batched, client-safe snapshots of each player's own state |
| `WorkshopService` | Plot assignment and release; all physical objects in a plot |
| `RestorationService` | Bench jobs, server-authoritative coverage, stages, trait reveal, completion |
| `RollService` | Server-resolved rolls |
| `SalesService` | Selling, bulk sale, set sale |
| `DisplayService` | Display slots and cosmetics |
| `InventoryService` | Favorites, finishing choices, settings |
| `SkillTreeService` | Purchases and safe reset |
| `CollectionIndexService` | Permanent discovery records and one-time rewards |
| `TutorialService` | Action-based tutorial progress |
| `ScheduleService` | Daily delivery, weekly challenges, featured rotation |
| `CommissionService` | Customer requests and optional timed orders |
| `AutoRollService` | Optional auto-roll with safe, logged scrap filters |

## How restoration works

Each item model has one folder of **cell parts** per restoration stage (`Layer_Brush`, `Layer_Polish`, …) laid over the clean model. A cell has a coverage value from 1 (corroded) to 0 (clean), and its transparency follows that value. The client raycasts the tool against a local copy of the bench item. It converts each hit to item-pivot space and sends up to 12 points per batch, about 12 times a second. The server:

- checks the job, the equipped and unlocked tool, the stage the tool can work, and the distance to the bench;
- drops points that aren't within 0.35 studs of a workable cell, so brushing empty space does nothing;
- applies work capped by real elapsed time (at most 0.2 s per batch) and splits it across the points, so spamming remotes or points can't speed up cleaning;
- removes coverage only from cells within the tool radius, with falloff, so untouched areas stay rusty;
- calibrates per-cell hardness from the item's `TargetSeconds`, so job length doesn't depend on how many cells the modeler made;
- completes a stage when mean cleanliness reaches a forgiving threshold (94%, lowered by Steady Hands), highlights the remaining spots near the end, and marks completion exactly once.

The client predicts with the same math and reconciles to each server acknowledgement. This works on mobile because there is no runtime texture painting and no per-pixel parts. Each item has a few dozen to a couple hundred cells, and each acknowledgement is one short string.

## Adding content

**Item:** add an entry to a file in `src/Shared/Config/Items/` with `Id`, `Name`, `Category`, `Rarity`, `Material`, `TargetSeconds`, `Stages` and `Variants` (optional: `Mount = "Stand"`, `BaseValue`, `ModelName`). Then build its model in `ReplicatedStorage.Assets.ItemModels`. `BaseValue` defaults to `FlatValue + ValuePerSecond × TargetSeconds` for its rarity, which keeps long jobs worth doing. Pools pick up items by category automatically.

**Upgrade:** add a node to `src/Shared/Config/SkillTree.luau` with `Prices` (one per rank), `Requires`, `Position` and `Effects`. Startup validation, and the tests, reject cycles, unreachable nodes, unknown stats, tools or pools, and overlapping board positions.

**Crate:** add a pool to `SalvagePools.luau`. Odds shown to players are computed from the same table the server rolls from.

**Collection set, challenge, cosmetic:** `CollectionSets.luau`, `ScheduleConfig.luau`, `WorkshopConfig.luau`.

To release expansions gradually, set `ContentConfig.EnabledPhases` (for example `{ 1 }` for the starter release only).

## First-session economy (provisional)

You start with $25 and a free starter bolt. Restoring and selling the bolt pays $17 plus a one-time $9 discovery bonus, which covers the first upgrade (Stiffer Bristles, $35). The Scrap Bin is free every 40 s, so a player with $0 always has a next job. The Hardware Crate costs $25, with expected value around $50. Value per second of work rises with rarity, but small rare items stay quick (Pocket Watch: 45 s) and large commons pay for their time (Kettle: 90 s, $84). All numbers are in `EconomyConfig`, `RarityConfig`, the item files and the skill tree, and they need tuning from real play sessions.

## Validation status

See [docs/TASK_STATUS.md](docs/TASK_STATUS.md) for the task-by-task list. In short:

- **Done here:** every file parses as Luau (checked with StyLua's parser), and selene reports no undefined or unused variables.
- **Not done yet:** nothing has been run in Roblox. The Studio tests exist but have not been executed, and there has been no multiplayer, mobile or performance testing. These need Studio, the models, the map and the UI.
