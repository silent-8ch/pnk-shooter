# Extracted effects

Cut from the 4 × 2 grid in `sprites.svg`, left to right:

- `explosion_00`–`explosion_03`: top row.
- `bullet_00`–`bullet_03`: bottom row.

Each frame is available as SVG and transparent PNG. Explosion frames use a shared 88 × 120 canvas, with each visible sprite centered at (44, 60). Bullet frames use a 32 × 80 canvas, with their tips aligned at (16, 10) so animation does not shift the leading edge. The SVG fill is white so `modulate` can tint it; the PNGs are the original black. Three stray tracing marks at the sheet edges were removed.

Use `explosion.tres` or `bullet.tres` with Godot AnimatedSprite2D. Both play at 12 FPS; the bullet loops and the explosion plays once. Adjust playback speed as needed. The resources use the SVG frames.
