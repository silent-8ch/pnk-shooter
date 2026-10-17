# Art handoff: effect images needed

As of 2026-10-16.

PNK Shooter needs 8 hand-drawn effect images (listed below) to replace effects
the game currently draws with code: sparks, flashes, rings and smoke puffs. It
is a Godot 4.6 2D co-op shooter for phones, portrait 540 × 960, GL
Compatibility renderer.

## Context

- **Style:** match `assets/filler/`: irregular white outlines, flat candy
  colors, transparent background. Ships are `assets/ship01.svg` and
  `assets/ship02.svg`.
- **Format:** SVG only. Sizes are given per image below; animation frames are
  128 × 128 like `assets/filler/fx/`.
- **Tinting:** most effect images are drawn in **white or light gray** so the
  game can tint them per explosion (it picks one of 4 fire color ramps per
  explosion, so each one looks different).
- **Lighting:** ships are lit with normal maps; effects are **not** lit and stay
  full brightness, so effects need no normal maps.

## Already done (don't redraw)

| Asset | Where | Notes |
| --- | --- | --- |
| Player/enemy ships | `assets/ship01.svg`, `ship02.svg` | Palette-recolored at runtime; normal maps baked |
| Shot (bullet) | `assets/filler/fx/shot_00..03.svg` | 4 frames, loops |
| Muzzle flash | `assets/filler/fx/muzzle_00..03.svg` | 4 frames, one shot |
| Explosion | `assets/filler/fx/explosion_00..05.svg` | 6 frames, plays at the wreck's blast point |
| Smoke puff (blast) | `assets/filler/fx/smoke_00..05.svg` | 6 frames, rises and fades |
| 12 filler sprites | `assets/filler/*.svg` | Scout, bomber, asteroids, satellite, mine, pickups, bolts, debris; not used in game yet |

Wreck parts (the pieces a destroyed ship breaks into) are cut from the ship
SVG by code (`scripts/ship_parts.gd`), so they need no art.

## Images needed

Priority 1 replaces effects the game draws with code today; priority 2 covers
events that have no visual yet.

| # | Image | Priority | Files | Canvas | Frames | Color | Replaces / used for |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Spark | 1 | `fx/spark_00..02.svg` | 32 × 32 | 3 variants (not animation) | White, tintable | Explosion spark particles (24–48 per blast); now a blurry dot |
| 2 | Ember streak | 1 | `fx/ember.svg` | 16 × 48 | 1 | White, tintable | Fast sparks stretched along their flight direction |
| 3 | Smoke trail puff | 1 | `fx/trail_puff_00..02.svg` | 64 × 64 | 3 variants | Light gray, tintable | Smoke trail behind a veering wreck (40 puffs); now a soft dot |
| 4 | Blast flash | 1 | `fx/flash.svg` | 128 × 128 | 1 | White core, pale yellow edge | The 0.12 s flash at the blast center; now a plain circle |
| 5 | Shockwave ring | 1 | `fx/ring.svg` | 256 × 256 | 1 | White, tintable | 1–2 expanding rings per blast; now a thin arc. Uneven, broken edge preferred |
| 6 | Hit spark | 2 | `fx/hit_00..03.svg` | 64 × 64 | 4 frames, one shot, ~30 fps | Yellow-white | Bullet hitting something that survives (bosses, shields later) |
| 7 | Player hit / shield flash | 2 | `fx/player_hit_00..03.svg` | 128 × 128 | 4 frames, one shot | Cyan-white | Player losing HP; currently no feedback |
| 8 | Thruster flame | 2 | `fx/thrust_00..03.svg` | 32 × 64 | 4 frames, loop, ~16 fps | White core, tintable | Engine flame under each ship's thrusters |

Variants (rows 1 and 3) are different shapes of the same thing; the game picks
one at random so effects don't look stamped.

## Format and delivery

- Put files in `assets/filler/fx/`, names as in the table, frames zero-padded
  (`_00`, `_01`, …).
- Plain SVG with `width`, `height` and `viewBox` set to the canvas size;
  transparent background; no embedded raster images, filters, blur or masks
  (the phone SVG renderer drops them).
- Center the drawing on the canvas. Leave about 10% margin so tinting and
  scaling don't clip.
- "Tintable" means draw in white or light gray only: the game multiplies by a
  color, so anything dark stays dark.
- Soft edges come from shape, not blur: use a few stacked shapes with lower
  opacity.
- Animated sets also get a SpriteFrames `.tres` next to them, like
  `fx/explosion.tres` (one-shot sets: `loop: false`).
- Keep each SVG under 5 KB; up to 48 sparks are on screen at once on a phone.
- Deliver art only. Don't edit the scripts below; they're being changed in
  parallel.

## Where each image gets wired in

For whoever wires the art in.

| Image | Code location | What changes |
| --- | --- | --- |
| Spark, ember | `scripts/wreck.gd` `_burst()` | Swap `_soft_dot()` for a random spark texture; ember via `particle_flag_align_y` |
| Smoke trail puff | `scripts/wreck.gd` `_make_smoke()` | Swap `_soft_dot()` texture; keep the gray color ramp |
| Blast flash, ring | `scripts/wreck.gd` `_draw()` | Replace `draw_circle` / `draw_arc` with textured sprites, same timing and sizes |
| Hit spark | `scripts/enemy.gd` `take_damage()` | Play via `scripts/sprite_effect.gd` when the hit doesn't kill |
| Player hit | `scripts/player.gd` `take_damage()` | Needs an RPC so every peer plays it |
| Thruster flame | `scenes/player.tscn`, `scenes/enemy.tscn` | Looping AnimatedSprite2D behind the Body, at the thruster positions |

Every effect plays on each device from a shared random seed, so each image
needs to look right at random rotation, at 30%–170% scale, and tinted to any
of the 4 fire ramps.
