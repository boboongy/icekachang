extends Node
## Autoload "Sound": the music loop, the rain loop, the shaver loop and one-shot effects, all
## from assets/audio/ (placeholders made by tools/audio/make_sounds.py; the owner may swap in
## real recordings with the same names). Mute silences the Master bus and is kept in the save.
## Players pause with the tree (focus loss, portrait), so nothing plays behind the browser.

const MUSIC_DB := -9.0
const RAIN_DB := -6.0
const SHAVE_DB := -8.0
const SFX_DB := {"scoop": -3.0, "pour": -6.0, "ladle": -4.0, "coin": -4.0, "click": -8.0,
	"serve": -5.0, "bin": -4.0, "day": -6.0}
const POOL := 6

var muted := false

var _streams := {}
var _music: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _shave: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for n in SFX_DB.keys() + ["music", "rain", "shave"]:
		_streams[n] = load("res://assets/audio/%s.wav" % n)
	_music = _player("music", MUSIC_DB)
	_rain = _player("rain", RAIN_DB)
	_shave = _player("shave", SHAVE_DB)
	for i in POOL:
		_pool.append(_player("", 0.0))
	set_muted(Game.muted)
	set_music(Game.music)


## Quitting with a stream still playing leaks its playback object.
func _exit_tree() -> void:
	for p in [_music, _rain, _shave] + _pool:
		p.stop()


func _player(stream: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if stream != "":
		var s: AudioStreamWAV = _streams[stream]
		if s.loop_mode == AudioStreamWAV.LOOP_DISABLED:     # in case the import lost the smpl loop
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = int(s.get_length() * s.mix_rate)
		p.stream = s
	p.volume_db = db
	add_child(p)
	return p


## One-shot effect by name (see SFX_DB). `pitch` > 1 = higher.
func play(sfx: String, pitch := 1.0) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sfx]
	p.volume_db = SFX_DB[sfx]
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()


## The shaver's grinding loop while the player holds it.
func shave(on: bool) -> void:
	if on and not _shave.playing:
		_shave.play()
	elif not on:
		_shave.stop()


func set_rain(on: bool) -> void:
	if on and not _rain.playing:
		_rain.play()
	elif not on:
		_rain.stop()


func is_raining() -> bool:
	return _rain.playing


func set_music(on: bool) -> void:
	if on and not _music.playing:
		_music.play()
	elif not on:
		_music.stop()


func is_music_playing() -> bool:
	return _music.playing


func set_muted(on: bool) -> void:
	muted = on
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), on)
