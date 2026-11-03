# Task Status

How to read this:

- **Code complete** means the system is implemented, it parses as Luau and it passes selene lint.
- Nothing has been run in Roblox yet. Every acceptance check that needs a running game is listed under *Needs Studio*.
- *Studio work* is building models, the map or UI, which was deliberately left for Studio.

Validation done so far:

- Every file was parsed with StyLua's Luau parser.
- selene reported no undefined variables, unused variables or parse errors.
- Automated specs were written for the economy and data logic, but they have **not been executed**. Run them in Studio with `Workspace.RunTests = true`.

| # | Task | Status | Notes / what still needs Studio |
| --- | --- | --- | --- |
| 1 | Game and order | Code complete | Core loop first; expansions are data-gated by `ContentConfig.EnabledPhases` and model availability. |
| 2 | Code standards | Code complete | PascalCase custom names, one module per system, comments only for non-obvious decisions. StyLua/selene configs included. |
| 3 | Project structure | Code complete | Server/Shared/Client split; contracts in `RemoteContracts` with validators and per-player token buckets. *Needs Studio:* two-client join test. |
| 4 | Economy and starter config | Code complete | $25 start, free starter bolt, free Scrap Bin (40 s cooldown), costs shown before purchase. No extra currencies, rebirths, pets or paid luck. |
| 5 | Item data model | Code complete | Definitions (`ItemCatalog`) are separate from owned instances (`ItemFactory`). Traits, condition and seed are rolled once and saved. Rarity, effort (`TargetSeconds`) and condition are independent. |
| 6 | First catalog (20 items) | Code complete / Studio work | All 20 defined with stages and variants. *Studio work:* 20 models following the model contract. |
| 7 | Rarity pools | Code complete | Six tiers; empty tiers drop out with renormalized, displayed odds. Spec simulates 100,000 rolls. |
| 8 | Rust removal prototype | Code complete | Cell-layer coverage, no runtime texture painting or per-pixel parts. *Needs Studio:* visual check and mobile profiling with real models. |
| 9 | Map blockout | Studio work | Required tags and plot structure are in the build guide. |
| 10 | Workshop ownership | Code complete | Plot assignment and release, server-only plot writes, exactly one active job (bench and stand share the slot). *Needs Studio:* multi-player test. |
| 11 | Persistence | Code complete | Schema version and migrations, UpdateAsync session lock, retries, kick on failed load (never defaults over data), refuses newer schemas, autosave, release on leave, BindToClose, job snapshots in save hooks. *Needs Studio:* rejoin tests with API access. |
| 12 | Inventory | Code complete | States Storage/Bench/Tray/Display; load-time repair enforces one location per item; favorites block selling and scrapping; full storage blocks rolls with a reason; shelving keeps progress. |
| 13 | Server rolling | Code complete | One non-yielding transaction; cooldown, unlock, capacity, funds; in-flight lock and rate limit. Specs cover the failure cases. |
| 14 | Dice reveal | Code complete / Studio work | Local dice spin, skippable; the reveal shows the server's returned item. *Studio work:* dice, crates, reveal UI. |
| 15 | Bench placement and camera | Code complete | Auto-scaled to a comfortable size, orbit camera with zoom limits, item rotate and flip, movement disabled, touch two-finger camera with one-finger tool. *Needs Studio:* PC and mobile pass on every starter item. |
| 16 | Wire brush | Code complete | Server validates ownership, job, tool, stage, bench distance, contact distance and time-bounded work. Specs cover spam, empty space and stalls. *Studio work:* tool model, sounds, particles. |
| 17 | Polishing | Code complete | Separate stage and layer; stage order enforced; brush can't work Polish. |
| 18 | Completion | Code complete | Forgiving mean-cleanliness threshold, remaining-spot markers near the end, single completion guard. |
| 19 | Restoration result | Code complete / Studio work | Before/after viewports, details, value; Sell/Store/Display move the same record; closing leaves it on the tray. |
| 20 | Selling | Code complete | Buyer and workshop counter; server price; atomic remove-and-pay; explicit scrap rule for unfinished items. |
| 21 | Skill tree definition | Code complete | 34 nodes across Root, Restoration, Luck, Business and cross-branch milestones; validator checks cycles, reachability, effects and positions. |
| 22 | Upgrade purchases and effects | Code complete | Prerequisites, funds, max rank, in-flight lock; effects always derived, so they can't double-apply. |
| 23 | Skill tree UI | Code complete / Studio work | Template-cloned nodes and lines, states, prerequisites, prices, current and next effect, real odds before and after for luck nodes, zoom. *Studio work:* board UI. |
| 24 | Core interface | Code complete / Studio work | HUD, inventory with real model previews, bench tool bar, loading and error messages. *Studio work:* layouts at phone and desktop sizes. |
| 25 | Tutorial | Code complete | Five action-driven steps, saved, skippable, starter resources kept. |
| 26 | Collection index | Code complete | Discovery and restoration recorded permanently; one-time discovery and set rewards keyed in `ClaimedRewards`. |
| 27 | Map art | Studio work | Art direction notes are in the build guide. |
| 28 | Balance | Provisional | Numbers in the README; needs real play sessions. |
| 29 | Multiplayer, security, persistence checks | Partly done | Automated specs for transactions, data repair and rate limits. *Needs Studio:* the live multi-client and exploit pass. |
| 30 | First release verification | Not done | Requires the built game. |
| 31–36 | Content expansions | Code complete / Studio work | All listed items defined with fitting stages, mounts and variants; large items use the stand (same slot). *Studio work:* models. |
| 37 | Advanced stages | Code complete | Scrape, Treat, Grind and Detail layers with distinct tools, base-tool fallbacks, Surface protection. |
| 38 | Rare variants | Code complete | Saved traits revealed progressively; unrevealed variant parts never replicate; nothing rerolls. |
| 39 | Luck expansion | Code complete | Specialized pools, transparent pity with saved counters, Lucky Streak, odds UI. |
| 40 | Business and Restoration expansion | Code complete | Specialist collectors, commission bonus, treatment, detail picks, polishing wheel; milestones unlock Commissions, Appraisal and Set Sales. |
| 41 | Safe skill reset | Code complete | Preview of refund, fee and lost capabilities; refund never exceeds recorded spend; no items removed; base tools keep jobs workable. |
| 42 | Displays and customization | Code complete / Studio work | Slots saved, visitors can inspect but not edit, cosmetics never add job slots. |
| 43 | Collection sets | Code complete | Nine sets; set sale needs real owned items, confirmation and the Set Sales unlock. |
| 44 | Commissions | Code complete | Only requests rollable items up to Rare; consumed once; never pays less than a normal sale. |
| 45 | Daily and weekly | Code complete | UTC day and week keys saved in the profile; no streak penalty. |
| 46 | Themed and timed orders | Code complete | Six-hour featured rotation with real pools; timed order is optional and expiry never touches items. |
| 47 | Auto-roll | Code complete | Normal roll path each time; stops on any failure or leave; opt-in scrap filter only for plain Common/Uncommon items with no hidden features; reviewable log. |
| 48 | Audio, animation, social | Code complete / Studio work | Hooks for all sounds and effects; settings for sound, effects and dice skipping. *Studio work:* assets. |
| 49 | Expansion regression | Not done | Requires the built game. Migration framework is in place (`ProfileSchema.Migrations`). |
| 50 | Handoff | This document, README and build guide | |

## Known limitations

- **Not run in Roblox.** Bugs that only show at runtime (wrong instance names in your build, API behavior differences, timing) may still exist. Run the specs first, then a two-client playtest.
- A brush contact can affect cells on the far side of a very thin item if they are within the tool radius. Keep cells on thin items at least a tool radius apart through the thickness, or use smaller tools for those items.
- The owner works on a local copy of the bench item. Visitors see the server copy, which updates about five times a second and is not rotated.
- Cell order follows cell names. Renaming or adding cells in a model invalidates saved progress for items mid-restoration on that model's current stage. That stage restarts from its seed and the item is kept.
- If DataStores are down at join, the player is kicked rather than allowed to play unsaved. This is deliberate.
