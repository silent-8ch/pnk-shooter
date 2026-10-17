# Filler art

Twelve static, transparent 256 × 256 SVG images, drawn with irregular white
outlines and the flat candy colors used by ship01 and ship02.
Animated combat effects are included in `fx/` and connected to gameplay.

Open `res://scenes/filler_preview.tscn` and press **F6** to view the set.

| Asset | Suggested displayed height | Use |
| --- | --- | --- |
| scout.svg | 36 px | Small ship; nose points up |
| bomber.svg | 60 px | Heavy ship; nose points up |
| asteroid_large.svg | 64 px | Large obstacle |
| asteroid_small.svg | 32 px | Small obstacle |
| satellite.svg | 72 px | Scenery or rescue objective |
| space_mine.svg | 32 px | Stationary hazard |
| pickup_health.svg | 24 px | Health pickup |
| pickup_shield.svg | 24 px | Shield pickup |
| pickup_weapon.svg | 24 px | Weapon pickup |
| bolt_player.svg | 16 px | Player projectile; tip points up |
| bolt_enemy.svg | 16 px | Enemy projectile; tip points down |
| debris.svg | 40 px | Static cluster of wreckage |

## Godot setup

Drag an SVG onto a scene to create a Sprite2D, or assign it to an existing
Sprite2D's Texture. Leave import scale at 1.0. For a target height of 36 px,
set the sprite's uniform scale to `36.0 / 256.0` (0.140625). The canvas includes
transparent margins, so the visible drawing is slightly smaller.

```gdscript
var texture := preload("res://assets/filler/scout.svg")
$Body.texture = texture
$Body.scale = Vector2.ONE * (36.0 / texture.get_height())
$Body.flip_v = true # Enemy ships face down.
```

`enemy.gd` currently assigns its texture in `_ready()`. To use a filler ship
there, replace that assignment with the snippet above, or add the asset to the
ship registry and select its index. These illustrations have no `data-slot`
metadata: ShipSkin passes their colors through unchanged. New registry entries
also become player choices; add palette metadata separately if recoloring is
wanted.

`bullet.tscn` now uses an AnimatedSprite2D Body. To use a static bolt instead,
replace its Sprite Frames with a single-frame animation containing the bolt.
Keep the Area2D, collision shape, movement, light, and replication nodes.

For obstacles and pickups, place the Sprite2D under an Area2D and add a separate
CollisionShape2D sized to the visible art. Images supply no collision, damage,
collection logic, or animation. Keep the debris cluster decorative unless each
piece is given a separate sprite and collision shape.

## Animated effects (wired into gameplay)

`fx/` contains individual transparent 128 × 128 SVG frames and ready-made
Godot SpriteFrames resources:

| Resource | Frames | FPS | Playback |
| --- | --- | --- | --- |
| muzzle.tres | 4 | 30 | One shot |
| smoke.tres | 6 | 10 | One shot |

Player bullets use an AnimatedSprite2D with `res://assets/effects/bullet.tres`;
wreck blasts use `res://assets/effects/explosion.tres`. Each replicated bullet
creates a local muzzle flash at its launch position. The muzzle artwork's base
is near the bottom of its canvas; the spawn offset puts it at the ship's nose.
Enemy wrecks trigger explosion and smoke on each peer through the existing wreck
RPC. Physics, damage, firing rate, bullet lights, and wreck pieces are retained.
Smoke also rises 24 px and fades over 0.6 seconds. One-shot effects free themselves.

For another effect, use the helper from a Node2D whose coordinates match `pos`:

```gdscript
const Effect := preload("res://scripts/sprite_effect.gd")

# Call once for each event, on every peer that should see it.
Effect.spawn($Effects, pos, Effect.EXPLOSION, 56.0)
Effect.spawn($Effects, pos, Effect.SMOKE, 64.0)
```

For manual editor setup, add an AnimatedSprite2D, assign a `.tres` file to
Sprite Frames, and play `default`. Scale uniformly by `desired_height / 128.0`.
Connect `animation_finished` to `queue_free` for one-shot nodes. Frame filenames
are zero-based and ordered numerically. These assets are authored SVGs; no image
generation service or external runtime dependency is required.
