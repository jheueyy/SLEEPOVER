class_name BagEyes
extends RefCounted
## Drives a bag's googly eyes — the character's whole soul. Holds the pupil and
## eyelid nodes built by BagVisual and animates them per mood each frame. One
## BagEyes per bag (local player + each remote ghost); call apply(mood, delta).

enum Mood { IDLE, ALERT, SHUT, SPIRAL, DROOP, SLEEPY }

var _pupils: Array[Node3D] = []       ## [left, right] pupil nodes
var _pupil_home: Array[Vector3] = []  ## each pupil's rest position
var _lids: Array[Node3D] = []         ## [left, right] eyelid nodes (slide down to close)
var _lid_open_y: Array[float] = []    ## each lid's open (raised) y
var _height: float = 0.9

var _blink_t: float = 0.0
var _dart_t: float = 0.0
var _spin: float = 0.0
var _closed: float = 0.0              ## 0 open .. 1 shut (smoothed)

func setup(pupils: Array, lids: Array, height: float) -> void:
	_height = height
	for p: Node3D in pupils:
		_pupils.append(p)
		_pupil_home.append(p.position)
	for l: Node3D in lids:
		_lids.append(l)
		_lid_open_y.append(l.position.y)
	_blink_t = randf_range(2.0, 5.0)

func apply(mood: Mood, delta: float) -> void:
	if _pupils.is_empty():
		return
	# How closed the lids should be for this mood.
	var target_closed := 0.0
	match mood:
		Mood.SHUT: target_closed = 0.94
		Mood.SLEEPY: target_closed = 0.72
		Mood.DROOP: target_closed = 0.42
		Mood.ALERT: target_closed = -0.15   # eyes go WIDE (lids lift past open)
	# Idle blink: a quick full close every few seconds when otherwise open.
	if mood == Mood.IDLE:
		_blink_t -= delta
		if _blink_t <= 0.0:
			_blink_t = randf_range(2.5, 6.0)
		target_closed = 1.0 if _blink_t < 0.12 else 0.0
	_closed = lerpf(_closed, target_closed, clampf(12.0 * delta, 0.0, 1.0))

	# Pupil offset by mood: darting (alert), spiralling (tumble), sinking (droop).
	var offset := Vector3.ZERO
	match mood:
		Mood.ALERT:
			_dart_t -= delta
			if _dart_t <= 0.0:
				_dart_t = randf_range(0.12, 0.3)
			offset = Vector3(sign(sin(_dart_t * 40.0)), 0.4, 0.0) * 0.03 * _height
		Mood.SPIRAL:
			_spin += delta * 10.0
			offset = Vector3(cos(_spin), sin(_spin), 0.0) * 0.045 * _height
		Mood.DROOP, Mood.SLEEPY:
			offset = Vector3(0, -0.03 * _height, 0)

	for i in _pupils.size():
		_pupils[i].position = _pupil_home[i].lerp(_pupil_home[i] + offset,
			clampf(14.0 * delta, 0.0, 1.0))
		# Lids: a top lid that slides DOWN to cover the eye. clamp negative
		# (ALERT) to a slight lift so the eye reads "wide" not inverted.
		if i < _lids.size():
			var drop := clampf(_closed, -0.2, 1.0) * 0.19 * _height
			_lids[i].position.y = _lid_open_y[i] - drop
