extends SceneTree
## Renders every voice and a music excerpt to docs/audio/, and measures them.
##
## The previews exist because this project is developed on machines with no
## audio device: the container falls back to Godot's dummy driver, so nobody
## here can listen. The numbers below are the check that survives that — a
## footstep that is two seconds long, a voice clipping at full scale or a
## buffer that is silent all show up in the table — and the .wav files are how
## a human with speakers finally judges it.
##
##     godot --headless --path . --script scripts/audio/render_previews.gd
##
## docs/audio/ carries a .gdignore, so these files are documentation and never
## build inputs. Nothing in the game loads them; the game synthesises its
## voices at load time from the same code.

const OUT_DIR := "res://docs/audio"
const EXCERPT_SECONDS := 42.0


func _initialize() -> void:
	var dir := DirAccess.open("res://docs")
	if dir != null and not dir.dir_exists("audio"):
		dir.make_dir("audio")

	print("| voice | s | rate | peak | rms | dc | file kB |")
	print("| --- | --- | --- | --- | --- | --- | --- |")

	var failures := 0
	for name: String in Voices.names():
		var rate := Voices.rate_of(name)
		var buf := Voices.build_buffer(name)
		var stream := Voices.build(name)
		var path := "%s/%s.wav" % [OUT_DIR, name]
		var err := stream.save_to_wav(path)
		if err != OK:
			printerr("could not write %s: %d" % [path, err])
			failures += 1
			continue
		print("| %s | %.3f | %d | %.3f | %.4f | %+.5f | %d |" % [
			name, float(buf.size()) / float(rate), rate,
			Synth.peak(buf), Synth.rms(buf), Synth.dc_offset(buf),
			_size_kb(path),
		])

	_render_music(failures)


func _render_music(failures: int) -> void:
	var excerpt := Music.render_excerpt(EXCERPT_SECONDS)
	var stream := Synth.to_wav(excerpt, Music.RATE, false)
	var path := OUT_DIR + "/music_excerpt.wav"
	var err := stream.save_to_wav(path)
	if err != OK:
		printerr("could not write %s: %d" % [path, err])
		failures += 1
	else:
		print("| music_excerpt | %.3f | %d | %.3f | %.4f | %+.5f | %d |" % [
			float(excerpt.size()) / float(Music.RATE), Music.RATE,
			Synth.peak(excerpt), Synth.rms(excerpt), Synth.dc_offset(excerpt),
			_size_kb(path),
		])

	# The stems as the game plays them, so the loop seam can be auditioned on
	# its own rather than only inside the mixed excerpt.
	var stems := {"music_bed": Music.build_bed(), "music_drive": Music.build_drive()}
	for name: String in stems:
		var buf: PackedFloat32Array = stems[name]
		var stem_path := "%s/%s.wav" % [OUT_DIR, name]
		if Synth.to_wav(buf, Music.RATE, true).save_to_wav(stem_path) != OK:
			printerr("could not write " + stem_path)
			failures += 1
			continue
		print("| %s | %.3f | %d | %.3f | %.4f | %+.5f | %d |" % [
			name, float(buf.size()) / float(Music.RATE), Music.RATE,
			Synth.peak(buf), Synth.rms(buf), Synth.dc_offset(buf),
			_size_kb(stem_path),
		])

	print("\nloop %.3f s · %d samples @ %d Hz · %d bars at %.0f BPM" % [
		Music.loop_seconds(), Music.loop_samples(), Music.RATE,
		Music.BARS, Music.BPM,
	])
	if failures > 0:
		printerr("render_previews: %d failure(s)" % failures)
		quit(1)
		return
	quit(0)


func _size_kb(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	return int(file.get_length() / 1024)
