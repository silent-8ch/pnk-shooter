class_name PaletteFrames
## Recolors a SpriteFrames of painted art (palette strategy in assets/assets.json):
## each frame is re-rendered from its painted SVG with ShipSkin.apply_palette.
## Slot k takes palette[k - 1]; slots beyond the palette keep their painted color.
##
## Painted SVGs are imported with importer="keep" (like the ships) so the raw text
## ships in the export; a .tres therefore references the same-named PNG preview,
## and the SVG next to it is the source. Frames with no SVG are reused as-is.
## Cached per (frames, palette, scale), so e.g. every bullet of one color shares
## one SpriteFrames.

static var _cache := {}


static func recolor(frames: SpriteFrames, palette: Array[Color], scale: float = 1.0) -> SpriteFrames:
	var key := _key(frames, palette, scale)
	if _cache.has(key):
		return _cache[key]
	var out := SpriteFrames.new()
	for anim in frames.get_animation_names():
		if not out.has_animation(anim):
			out.add_animation(anim)
		out.set_animation_loop(anim, frames.get_animation_loop(anim))
		out.set_animation_speed(anim, frames.get_animation_speed(anim))
		for i in frames.get_frame_count(anim):
			out.add_frame(anim, _recolor_texture(frames.get_frame_texture(anim, i), palette, scale),
				frames.get_frame_duration(anim, i))
	_cache[key] = out
	return out


## The painted SVG behind a frame: the frame itself, or the .svg beside its .png.
static func source_svg(tex: Texture2D) -> String:
	if tex == null or tex.resource_path == "":
		return ""
	var path := tex.resource_path
	if path.get_extension() != "svg":
		path = path.get_basename() + ".svg"
	return path if FileAccess.file_exists(path) else ""


static func _recolor_texture(src: Texture2D, palette: Array[Color], scale: float) -> Texture2D:
	var path := source_svg(src)
	if path == "":
		return src
	var svg := FileAccess.get_file_as_string(path)
	if svg == "":
		return src
	var tex := ShipSkin.render(svg, palette, scale)
	return tex if tex else src


static func _key(frames: SpriteFrames, palette: Array[Color], scale: float) -> String:
	var parts := PackedStringArray([frames.resource_path if frames.resource_path else str(frames.get_instance_id()), str(scale)])
	for c in palette:
		parts.append(c.to_html())
	return "|".join(parts)
