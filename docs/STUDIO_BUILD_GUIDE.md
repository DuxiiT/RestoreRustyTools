# Studio Build Guide

The code finds everything below by **name** or **CollectionService tag**. Missing pieces are reported once in the Output window and skipped, so you can build in any order. Names are case-sensitive.

## 1. Assets: `ReplicatedStorage.Assets`

```
Assets (Folder)
  ItemModels (Folder)      one Model per item, named by the item's Id (or its ModelName)
  Tools (Folder)           one Model per tool Id, held at the contact point while working
  Effects (Folder)         particle and marker templates
  Sounds (Folder)          Sound templates
  Prompts (Folder)
    InspectPrompt          ProximityPrompt added to displayed items so visitors can inspect them
  Customization (Folder)
    <Category> (Folder)    Lamp, Floor, Sign, Shelving, Bench, Cabinet
      <OptionId> (Model)   for example Lamp/BrassLamp; placed at the plot's matching anchor
```

### Item model contract (the important one)

```
Bolt (Model)               the pivot is the reference point for all restoration math
  Clean (Model or Folder)  the fully restored look. Name is a convention only.
  Layer_Brush (Folder)     coverage cells for the Brush stage
    Cell_001 (Part/MeshPart)
    Cell_002 ...
  Layer_Polish (Folder)    only if the item lists the Polish stage
  Variants (Folder)        optional hidden features
    MakersStamp (Model/Folder/Part)   named exactly like the variant Id
```

- **One layer folder per stage the item lists**: `Layer_Scrape`, `Layer_Treat`, `Layer_Grind`, `Layer_Brush`, `Layer_Detail`, `Layer_Polish`. An item with no cells in a required layer is not available and is never rolled.
- **Cells** are thin parts that sit just above the clean surface and carry the corroded look, with a rust Texture or Decal on them, or a rusty MeshPart. Give each cell a unique name; names set the cell order. Aim for roughly 30–150 cells per layer, each 0.3–0.6 studs once the item is on the bench. Items are auto-scaled so their largest side is 3.5 studs on the bench and 7 studs on the stand.
- A cell's **Transparency** (and its Decal/Texture transparency) is the fully corroded look. As coverage drops the cell fades out, and it disappears when clean.
- Later stage layers sit **under** earlier ones. For example, the dull tarnish of `Layer_Polish` sits under the rust of `Layer_Brush`, so brushing reveals tarnish and polishing reveals the final finish. Keep the clean finish believable; not everything should be chrome.
- **Mixed materials:** set a string attribute `Surface` on cells over wood (`"Wood"`) or paint (`"Paint"`). Metal-only tools (treatment brush, grinder) don't affect those cells, and they don't count toward stages those tools work. Wood and paint parts that never need cleaning shouldn't be cells at all.
- **Variants** sit on the clean model under the rust. The server keeps unrevealed variant folders off the network and adds them when restoration progress reaches the variant's `RevealAt`.
- Rusty and restored appearances should differ clearly: the rusty silhouette comes from the cells, the restored one from `Clean`.

### Tools, effects, sounds

| Name | Kind | Used for |
| --- | --- | --- |
| `Tools/WireBrush`, `PolishCloth`, `TreatmentBrush`, `Scraper`, `RotaryGrinder`, `DetailPick`, `PolishingWheel` | Model | Tool shown at the contact point (−Z faces into the surface) |
| `Effects/Contact_RustFlakes`, `Contact_Grime`, `Contact_Verdigris` | Part with ParticleEmitter(s) | Enabled while the tool touches the item |
| `Effects/RemainingMarker` | SelectionBox, Highlight or BillboardGui | Marks the last dirty cells near completion |
| `Effects/TutorialHighlight` | Highlight | Tutorial target highlight |
| `Sounds/Brush`, `Polish`, `Treat`, `Scrape`, `Grind`, `Detail` | Sound | Looped while working. Optional material variants: `Brush_Rust`, `Brush_SoftMetal` |
| `Sounds/DiceRoll`, `Sale`, `Upgrade`, `Celebrate_Small`, `Celebrate_Big`, `Reveal_<Rarity>` | Sound | One-shot feedback |

## 2. Map

Tag stations with CollectionService (Tag Editor). Proximity checks use the tagged part or model's position. **ProximityPrompts** that open menus carry their own tags.

| Tag | On | Purpose |
| --- | --- | --- |
| `SalvageDepot` | Part/Model | Rolling requires being within 40 studs |
| `SalvageDice` | Part or Model | The big dice animated during a roll |
| `SalvageDepotPrompt` | ProximityPrompt | Opens the crate menu |
| `Buyer` | Part/Model | Selling is allowed near the buyer or in your own workshop |
| `BuyerPrompt` | ProximityPrompt | Opens the inventory for selling |
| `SkillBoard` | Part/Model | Courtyard skill board |
| `SkillBoardPrompt` | ProximityPrompt | Opens the planning board |
| `CollectionGallery` / `GalleryPrompt` | Part / ProximityPrompt | Collection index |
| `CommissionBoard` / `CommissionPrompt` | Part / ProximityPrompt | Commissions |
| `DeliveryTruck` / `DeliveryPrompt` | Part / ProximityPrompt | Daily delivery pickup at the truck entrance |
| `WorkshopPlot` | Model | One per server slot (match **Players → Max Players**) |

### Workshop plot (`WorkshopPlot` model)

```
Plot (Model, tagged WorkshopPlot)     its pivot is the plot center (60-stud interaction radius)
  BenchAnchor (Part)                  item rests on its top face, facing the anchor's front
  StandAnchor (Part, optional)        large-project stand; same single active job slot
  TrayAnchor (Part)                   finished-item tray
  DisplaySlots (Folder)               Parts named Slot1, Slot2, … in order of unlock
  CustomizationAnchors (Folder)       Parts named Lamp, Floor, Sign, Shelving, Bench, Cabinet
  OwnerSpawn (SpawnLocation)          owner respawns here
  OwnerSign (Part)                    with a SurfaceGui containing a TextLabel named OwnerLabel
  ...prompts (tagged ProximityPrompts inside parts):
     WorkshopBench          opens the bench view (or the inventory if the bench is empty)
     WorkshopSellCounter    opens the inventory for selling
     WorkshopStorage        opens the inventory
     WorkshopUpgradeBoard   opens the planning board
```

Keep the bench brightly lit with neutral light so rust contrast stays readable. The server creates a `Runtime` folder in each plot for the items it places. Don't put your own objects there.

## 3. UI (`StarterGui`)

Every list is filled by cloning a **template** you design. Make the template invisible; the code clones it, makes the clone visible, and puts clones in the template's parent, which should use a UIListLayout or UIGridLayout. Set `ResetOnSpawn = false` on every ScreenGui. Labels can be TextLabels or TextButtons unless the table says Button.

**HudGui**
- `MoneyLabel`, `CapacityLabel`
- `Buttons/` with `InventoryButton`, `RollButton`, `SkillTreeButton`, `CollectionButton`, `CommissionsButton`, `WorkshopButton`, `SettingsButton` (all buttons)
- `JobPanel/` with `ItemNameLabel`, `StageLabel`, `ProgressBar/Fill`, `OpenBenchButton`
- `Notifications/NotificationTemplate` (TextLabel)

**BenchGui** (shown in bench view)
- `ToolBar/ToolTemplate` (button, optional child `NameLabel`). Clones get the attributes `Equipped` and `Locked`.
- `StageLabel`, `ProgressBar/Fill`, `HintLabel`
- Buttons: `ExitButton`, `ShelveButton`, `FlipButton`, `RotateLeftButton`, `RotateRightButton`, `ZoomInButton`, `ZoomOutButton`

**RollGui**
- `Window/CloseButton`
- `Window/PoolList/PoolTemplate`: `NameLabel`, `DescriptionLabel`, `CostLabel`, `OddsLabel`, `PityLabel`, `StatusLabel`, `RollButton`
- `Window/AutoRoll/` (hidden until unlocked): `ToggleButton`, `NextPoolButton`, `PoolLabel`, `ScrapCommonsButton`, `ScrapUncommonsButton`, `LogLabel`
- `Reveal/`: `Viewport` (ViewportFrame), `NameLabel`, `RarityLabel`, `EffortLabel`, `DetailsLabel`, `SkipButton`, `ContinueButton`, `RestoreButton`

**InventoryGui**
- `Window/CloseButton`, `Window/CapacityLabel`, `Window/ShelveButton`, `Window/BulkSellButton`
- `Window/List/ItemTemplate`: `Viewport`, `NameLabel`, `RarityLabel`, `StatusLabel`, `ValueLabel`, `FavoriteButton`, `PrimaryButton`, `SellButton`, `ScrapButton`, `DisplayButton`

**ResultGui**: `Window/` with `BeforeViewport`, `AfterViewport`, `NameLabel`, `RarityLabel`, `DetailsLabel`, `ValueLabel`, `SellButton`, `StoreButton`, `DisplayButton`, `CloseButton`

**SkillTreeGui**
- `Window/Board` (ScrollingFrame recommended) containing `Canvas` (Frame) with `NodeTemplate` (button with `NameLabel`, `RankLabel`; size set in **offset** pixels) and `LineTemplate` (thin Frame)
- `Window/Details/`: `NameLabel`, `DescriptionLabel`, `StateLabel`, `PrereqLabel`, `CostLabel`, `CurrentEffectLabel`, `NextEffectLabel`, `OddsLabel`, `BuyButton`
- `Window/CloseButton`, `Window/ZoomInButton`, `Window/ZoomOutButton`, `Window/ResetButton`
- Node clones get the attributes `State` (Owned / Available / Locked), `Major` and `Branch` for styling. The background color is also set per state.

**CollectionGui**: `Window/CloseButton`; `Window/SetList/SetTemplate` with `NameLabel`, `ProgressLabel`, `RewardLabel`, `ClaimButton`, `SellSetButton`, and `Entries/EntryTemplate` (`NameLabel`, `StatusLabel`, optional `Viewport`)

**TutorialGui**: `Prompt/` with `PromptLabel` and `SkipButton`

**CommissionGui**: `Window/` with `CloseButton`, `LockedLabel`, `FeaturedLabel`, `WeekLabel`, `OfferList/OfferTemplate` (`TitleLabel`, `RewardLabel`, `DeadlineLabel`, `SubmitButton`, `DeclineButton`), `Daily/` (`StatusLabel`, `ClaimButton`), `Weekly/ChallengeTemplate` (`DescriptionLabel`, `ProgressLabel`, `RewardLabel`, `ClaimButton`)

**WorkshopGui**: `Window/` with `CloseButton`, `DisplayList/SlotTemplate` (`SlotLabel`, `ItemLabel`, `RemoveButton`), `CosmeticList/CosmeticTemplate` (`NameLabel`, `PriceLabel`, `BuyButton`, `ApplyButton`)

**InspectGui**: `InspectPanel/` with `NameLabel`, `RarityLabel`, `TraitsLabel`, `OwnerLabel`, `CloseButton`

**SettingsGui**: `Window/` with `CloseButton`, `SoundToggle`, `EffectsToggle`, `SkipRollToggle`, `VolumeLabel`, `VolumeUpButton`, `VolumeDownButton`, `SkipTutorialButton`

**DialogGui**: `Dialog/` with `MessageLabel`, `ConfirmButton`, `CancelButton` (used for every confirmation)

Use readable text sizes, keep content inside safe screen margins (`ScreenInsets = CoreUISafeInsets`), and show rarity as text and color together. The code already writes rarity names into rarity labels.
