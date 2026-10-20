# Feature brainstorm: expanding current mechanics

Recommended picks are marked `*`.

## Current mechanics (baseline)
- **Ship build**: FTL-style reactor + systems (shields, engines, weapons, drones, medbay, piloting), guns (photon double/rapid, missile, autocannon, beam, heal beam), drones (option, rescue), hull (armor, +ship). Exp is currency; lost on death, recovered via escape pod. `scripts/systems.gd`, `scripts/player.gd`
- **Enemies**: weaver, diver, striker, tank, orbiter, turret, elite, boss (per-kind attacks), tetran, rival (host-flown player-like ship). Stage scaling on hp/speed/points. `scripts/enemy.gd`, `scripts/rival.gd`
- **Run structure**: stage = waves → elite → refit → boss → refit → fork (vote between two level kinds, each with a reward). 6 kinds with scenery hazards. `scripts/level_kinds.gd`, `scripts/scenery/*`
- **Rescue economy**: enemy pods, astronauts, rescue drones, tail, stations, cleanup bots. `scripts/escape_pod.gd`, `scripts/station.gd`
- **Score**: aim streak, untouched streak, score mult reward, high scores log. Solo save game. Fun-time droids on palindrome clock times.
- **Co-op**: LAN up to 8, AI buddy, AI pilot, friendly fire, late join, party votes.
- **Pipeline**: hand-drawn scans → ship painter → palettes/normals; level designer JSON.

## Brainstorm by mechanic

### 1. Ship systems and guns
- `*` **Ship traits**: each of the 5 ships gets a passive (e.g. 01 +1 engine bar free, 02 +1 reactor, 03 cheaper weapons, 04 +1 armor, 05 drones cost 1 less). Ships are cosmetic today; this makes ship select a choice. Small: a `trait` key in `Ships.LIST` read by `Systems`/`Player`.
- `*` **New guns**: MINES (drop behind, drift up, blast), SPREAD (short fan, power 2), RAILGUN (hold to charge, pierces a column), FLAK (autocannon level that also pops boss shots in a radius), EMP (stuns turrets and the rival briefly).
- **New systems**: CLOAK (enemies and rival lose aim for N s, drains reactor), TRACTOR (pulls pickups/pods in from range; pairs with rescue), SENSORS (reveals loot obstacles, enemy hp bars, cuts storm darkness), HANGAR (launches a fighter drone that hunts on its own).
- **System damage**: a hit has a chance to knock a powered system offline until MEDBAY/REPAIR fixes it (FTL's core loop). Makes medbay matter beyond healing.
- **Overcharge**: push a system one bar over capacity for a few seconds, then it goes offline. Action-bar button.
- **Loadout presets**: two saved power layouts toggled from the action bar (fight vs. rescue).

### 2. Enemies
- `*` **New wave types**: BOMBER (drops mines in its lane), SCOUT/KAMIKAZE (fast, homes in, cheap), SHIELDER (projects a shield bubble over neighbours; kill it first), CARRIER (big, spits weavers until killed), SNIPER (telegraphed line, then a fast shot), HEALER (enemy heal beam that grows its friends, mirroring the player's). Unused filler art for scout, bomber, mine and satellite already exists (`.claude/worktrees/*/assets/filler/ART_HANDOFF.md`).
- `*` **Boss phases**: at 50% hp each kind's boss switches pattern (tetran arms speed up, starbase turret fans become double, storm chain lightning follows the player). Second-tier boss art/attacks from stage 4+.
- **Rival progression**: rival copies your armed guns (fires missiles if you do), persistent named rivals that return across stages with a grudge banner, rival escape pod that, if rescued, becomes an AI buddy for the stage.
- **Elite affixes**: wave enemies occasionally spawn with one affix (armored, fast, splits on death, shielded), shown by a palette tint. Reuses stage color ramp.
- **Formation events in the level designer**: a "pincer" (two lines from both sides), "wall" (tanks across all lanes with one gap).

### 3. Level kinds and run structure
- `*` **New kinds**: NEBULA (low visibility, pickups drift, orbiters), DERELICT FLEET (huge hulk obstacles, turrets on them), MINEFIELD (mines as obstacles, slow drift), SUN CORONA (heat ticks unless shaded behind obstacles), ENEMY HOMEWORLD (final kind only offered from stage N, hardest boss, ends the run with a win screen).
- **Run map**: the route taken shown at forks and on results (kinds visited, rewards taken). Cheap, uses existing fork data.
- **Kind modifiers**: a fork option can carry a mutator ("double hazards", "no stations", "rivals only") for a bigger reward.
- **Win condition**: after N stages the homeworld fork appears; beating it logs a win in high scores. Currently runs are endless.

### 4. Forks and rewards
- `*` **More rewards**: free gun unlock (pick at next refit), +1 drone, rival bounty (next rival drops 3 exp), station call (station every 15 s next stage), mystery (revealed on arrival).
- `*` **Risky forks**: one gate offers a harder next stage (stage +1 scaling) for a doubled reward.
- **Fork shop**: spend party exp at the gate on consumables (one-shot shield, extra spare) before entering.

### 5. Rescue economy
- `*` **Crew**: rescued pods turned in become crew who staff a system (+1 effective bar on it, no reactor cost). Lost when the ship is lost (spill as astronauts). Ties rescue directly to the systems game.
- **Station types**: repair station (full heal on dock), trading post (sell tail for upgrade levels instead of exp), ammo depot (reloads missiles).
- **Station defense event**: a station under attack; keep it alive until it docks for a bonus.
- **VIPs**: a rare astronaut with a bounty banner, worth 5x.

### 6. Scoring, streaks, modes
- `*` **Daily seed run**: one shared `run_seed` per day, scores logged separately. Scenery already derives hazards from `run_seed`.
- **Kill-chain combo**: kills within 1.5 s chain for a score multiplier shown as a float text.
- **Achievements/medals**: untouched boss, no-exp-spent stage, 100 aim streak, full tail turn-in; shown on results and ship select.
- **Modes**: boss rush (bosses only with refits between), survival (no bosses, waves ramp), time attack (score in 5 min).
- **Mutators menu**: pick run modifiers from the lobby (friendly fire off, double enemies, one life). There is no difficulty selector today; this would be it.
- **Haptics**: vibrate on hits, boss kills and streak milestones (Android only target, none today).

### 7. Co-op and versus
- **Dead players fly a drone**: while waiting on a spare, a dead player pilots a rescue drone or cleanup bot that can fetch their own pod.
- **Versus mode**: one player flies the rival ship at the top of the screen (Rival already runs as a host-driven ship).
- **Exp gifting**: at a refit a player can send exp to a teammate.
- **Online play**: relay/NAT punch so the LAN lobby works over the internet.

### 8. Meta-progression and persistence
- **Hangar unlocks**: palettes and ships unlocked by medals; pilot profile with lifetime stats (kills, rescues, best streaks).
- **Codex**: enemies/bosses seen with their art and the kid's scans.
- **Co-op save**: save a multiplayer run (host) and resume with whoever rejoins.

### 9. Art pipeline (plays to the hand-drawn strength)
- `*` **Scanned enemies and bosses**: run the scan-to-ship pipeline on enemy/boss drawings so each kind's boss is its own drawing rather than a recolored player ship. The three scans in the repo root look like boss/ship concepts. Tetran, the elite and rescue stations are still drawn in code and waiting for art.
- **Scanned obstacles**: the obstacle `pieces.json` already supports art per piece; draw asteroids/girders.
- **In-game sticker**: pick a scan at ship select as a decal.

### 10. Fun time and events
- **More clock events**: top-of-the-hour "rush minute" (double pickups), birthday mode from a settings date.
- **Seasonal palettes** on the stage color ramp.

## Recommended first batch (rough order, each independently shippable)
1. Ship traits (small, immediate variety at ship select)
2. Boss phases (deepens existing bosses, no new art)
3. New wave types: shielder, bomber, carrier (level designer gains pieces)
4. Risky forks + 3 new rewards
5. Crew from rescued pods (links rescue to systems)
6. Mines + spread guns
7. Daily seed run
8. Scanned bosses via the existing painter pipeline

## Verification (for whichever feature is picked next)
- Unit tests under `test/unit` match the existing per-feature pattern (`test_rival.gd`, `test_boss.gd`, etc.).
- Run the Godot test runner (`test/pre_run.gd`/`post_run.gd` harness) and the level-designer/ship-painter JS tests when those tools change.
- Deploy APK to the Pixel 6 Pro after each fix (existing memory rule).
