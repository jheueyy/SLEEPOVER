extends Node
## Global "noise ping" bus (autoloaded as NoiseBus).
##
## The Week 1 monster hunts by noise, not sight. Anything loud — a hop landing,
## a barrel roll, a knocked prop later — calls emit_noise() with a world position
## and a 0..1 loudness. The monster subscribes and investigates the loudest recent
## ping. This is the seed of the Part 3 "hunts by noise and light" AI.

signal noise_emitted(position: Vector3, loudness: float)

func emit_noise(position: Vector3, loudness: float) -> void:
	noise_emitted.emit(position, loudness)
