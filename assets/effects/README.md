# Extracted effects

Cut from the 4 × 2 grid in `sprites.svg`, left to right:

- `explosion_00`–`explosion_03`: top row.
- `bullet_00`–`bullet_03`: bottom row.

Each frame is available as SVG and transparent PNG. Explosion frames use a shared 88 × 120 canvas, with each visible sprite centered at (44, 60). Bullet frames use a 32 × 80 canvas, with their tips aligned at (16, 10) so animation does not shift the leading edge. Three stray tracing marks at the sheet edges were removed.

Use `explosion.tres` or `bullet.tres` with Godot AnimatedSprite2D. Both play at 12 FPS; the bullet loops and the explosion plays once. Adjust playback speed as needed. The resources use the SVG frames.

## william

Cut from the 4 frames stacked top to bottom in `william.svg` (repo root) as `william_00`–`william_03`. Frames use a shared 456 × 272 canvas with each sprite centered, at the sheet's 1:1 scale. Stray tracing marks between frames were removed. The frames are unpainted line art (`unassigned` in `assets/assets.json`) until they're painted in the Ship Painter. `william.tres` plays once at 12 FPS. Nothing in the game uses it yet.
