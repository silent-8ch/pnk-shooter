# Obstacle art

Terrain the players fly around: asteroids and pieces of a broken space station.
The game shows an outline with the piece id for any piece that has no art yet.
Draw one and it replaces the outline everywhere that piece is used.

## How to add art

- Save as `assets/obstacles/<id>.png` or `assets/obstacles/<id>.svg`, e.g. `girder.png`.
- Draw at the piece size below, or at an exact multiple of it (2x is good for phones).
  The game scales it to the size.
- Top-down view, same as the ships. Transparent background.
- The collision shape is a circle or a rectangle filling the size, so keep the solid
  part of the drawing inside it. The outline in `pieces.json` is only the placeholder.
- Pieces that spin get rotated in the game, so don't bake in a light direction.
- Pieces placed with `dir: -1` in a level are drawn mirrored left to right.

## Repeating pieces

- `girder` and `hull` are tile pieces. A level places a run of N segments, so draw
  one segment whose left and right edges line up seamlessly with the next copy.
- Each run gets its end caps on both sides: `girder_end_l` / `girder_end_r` and
  `hull_end_l` / `hull_end_r`. Draw the caps as broken, jagged ends, with the
  inner edge matching the segment.

## Pieces

| id | size (px) | kind | health | what to draw |
|---|---|---|---|---|
| `asteroid_s` | 36 x 36 | spins | 3 hits | Small lumpy rock, a few craters. Drawn top-down; it spins in game, so no lighting direction baked in. Can be shot apart. |
| `asteroid_m` | 60 x 60 | spins | 8 hits | Medium rock, deeper craters and a cracked face. Spins in game. Can be shot apart. |
| `asteroid_l` | 100 x 100 | spins | indestructible | Big boulder you must fly around. Heavy craters, maybe a mineral vein. Spins slowly in game. Indestructible. |
| `debris` | 28 x 28 | spins | 2 hits | Twisted scrap of station metal: bent plate with a torn edge and a dangling cable. Spins in game. Can be shot apart. |
| `girder` | 64 x 18 | tiles left-right | indestructible | One segment of a lattice truss (two rails with X bracing). TILES left-to-right: the left and right edges must line up seamlessly with the next copy. Indestructible. |
| `girder_end_l` | 24 x 18 | end cap | indestructible | Left end cap of a girder run: the truss snapped off, bent rails and a jagged break facing left. Its right edge joins a girder segment seamlessly. |
| `girder_end_r` | 24 x 18 | end cap | indestructible | Right end cap of a girder run: the truss snapped off with a jagged break facing right. Its left edge joins a girder segment seamlessly. |
| `hull` | 64 x 56 | tiles left-right | indestructible | One section of space-station hull seen from above: plating panels, a row of windows (some dark, some lit), pipes. TILES left-to-right seamlessly. Indestructible. |
| `hull_end_l` | 32 x 56 | end cap | indestructible | Left end of a hull run, torn open: ragged plating, exposed ribs and floors, sparks optional. Its right edge joins a hull segment seamlessly. |
| `hull_end_r` | 32 x 56 | end cap | indestructible | Right end of a hull run, torn open (mirror the idea of the left end, but draw it separately). Its left edge joins a hull segment seamlessly. |
| `solar_panel` | 44 x 88 | fixed | indestructible | Detached solar array: grid of dark blue cells on a frame, one corner crumpled. Tall and narrow. Indestructible. |
| `ring_arc` | 120 x 44 | fixed | indestructible | Piece of a broken habitat ring: a curved band (bowing upward) with windows along it, both ends sheared off. Indestructible. |
| `reactor` | 70 x 70 | fixed | indestructible | Round reactor module ripped from a station: concentric rings, a glowing center, stubs of pipes around the rim. Indestructible. |

## Adding a new piece

Add an entry to `pieces.json` with these fields:
- `id`, `name`, `description`, `size`, `shape` (`circle` or `rect`), `hp` (0 = indestructible)
- `outline`: placeholder polygon, in px from the center
- Optional: `spin`, `tile`, `caps`, and `cap: true` for an end cap

The level designer and the game both read this file.

## Drawn so far

- `asteroid_s`, `asteroid_m`, `asteroid_l`: drawn on drawing sheet 16 (page 2 of
  `tools/ship-painter/sheet.js`), scanned as `Scan 7.jpeg`, traced by hand into one SVG
  (`scan7/LP4Hb01.svg`) and cut into one SVG per asteroid. Fills were added under the
  outline by `scan.js --svg` and colored by hand: slot 1 outline, slot 2 the rock,
  slot 3 the craters (`fixed` in `assets/assets.json`).
