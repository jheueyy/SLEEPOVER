class_name ObjectiveDef
extends Resource
## Data definition for an escape objective (launch plan 3.1: objectives are
## DATA + a prefab, never engine changes). Every objective is a CLUE -> ACTION
## pair with randomized bindings. The runtime behaviour lives in Objective.gd,
## keyed off `kind`; this resource is pure data + the catalog of all six.

enum Kind { LANDLINE, BREAKER, DOG, DEADBOLT, GARAGE_CODE, GLASSES }

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.LANDLINE
@export var clue_spots: Array[Vector3] = []   ## candidate clue positions (scaled)
@export var action_spot: Vector3 = Vector3.ZERO
@export var action_prompt: String = "E: USE"
@export var solve_secs: float = 0.0           ## hold-to-solve time (deadbolt/dog/glasses)
@export var code_len: int = 0                  ## digits/symbols for entry types
@export var noise_sound: String = "click"      ## SoundKit key for the action ping
@export var noise_loudness: float = 0.8

static func _scaled_pool(pool: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Vector3 in pool:
		out.append(HouseSuburban.scaled(p))
	return out

## The full catalog. RoundManager picks a random 5 of these each round.
static func all() -> Array[ObjectiveDef]:
	return [_landline(), _breaker(), _dog(), _deadbolt(), _garage_code(), _glasses()]

static func _landline() -> ObjectiveDef:
	var d := ObjectiveDef.new()
	d.id = "landline"
	d.display_name = "The Landline"
	d.kind = Kind.LANDLINE
	d.clue_spots = _scaled_pool(HouseSuburban.CLUE_SPOTS)
	d.action_spot = HouseSuburban.scaled(HouseSuburban.PHONE_SPOT)
	d.action_prompt = "E: DIAL"
	d.code_len = 4
	d.noise_sound = "click"
	d.noise_loudness = 0.8
	return d

static func _breaker() -> ObjectiveDef:
	var d := ObjectiveDef.new()
	d.id = "breaker"
	d.display_name = "The Breaker"
	d.kind = Kind.BREAKER
	d.clue_spots = _scaled_pool(HouseSuburban.BREAKER_DIAGRAM_SPOTS)
	d.action_spot = HouseSuburban.scaled(HouseSuburban.BREAKER_BOX_SPOT)
	d.action_prompt = "E: SET FUSES (1-3)"
	d.code_len = 3           # a 3-fuse colour order, keys 1/2/3
	d.noise_sound = "clatter"
	d.noise_loudness = 0.85
	return d

static func _dog() -> ObjectiveDef:
	var d := ObjectiveDef.new()
	d.id = "dog"
	d.display_name = "The Dog Has The Keys"
	d.kind = Kind.DOG
	d.clue_spots = [HouseSuburban.scaled(HouseSuburban.DOG_SNACK_SPOT)]
	d.action_spot = Vector3.ZERO  # the dog moves; resolved at runtime
	d.action_prompt = "E: GRAB SNACK"
	d.noise_sound = "bark"
	d.noise_loudness = 0.7
	return d

static func _deadbolt() -> ObjectiveDef:
	var d := ObjectiveDef.new()
	d.id = "deadbolt"
	d.display_name = "The Deadbolt"
	d.kind = Kind.DEADBOLT
	d.clue_spots = []
	d.action_spot = HouseSuburban.scaled(HouseSuburban.DEADBOLT_SPOT)
	d.action_prompt = "HOLD E (needs 2)"
	d.solve_secs = 3.0
	d.noise_sound = "click"
	d.noise_loudness = 0.5
	return d

static func _garage_code() -> ObjectiveDef:
	var d := ObjectiveDef.new()
	d.id = "garage_code"
	d.display_name = "The Garage Code"
	d.kind = Kind.GARAGE_CODE
	d.clue_spots = _scaled_pool(HouseSuburban.GARAGE_CLUE_SPOTS)
	d.action_spot = HouseSuburban.scaled(HouseSuburban.GARAGE_KEYPAD_SPOT)
	d.action_prompt = "E: KEYPAD"
	d.code_len = 4
	d.noise_sound = "beep"
	d.noise_loudness = 0.85
	return d

static func _glasses() -> ObjectiveDef:
	var d := ObjectiveDef.new()
	d.id = "glasses"
	d.display_name = "The Glasses"
	d.kind = Kind.GLASSES
	d.clue_spots = _scaled_pool(HouseSuburban.GLASSES_SPOTS)
	d.action_spot = Vector3.ZERO  # the glasses ARE the clue; pick them up
	d.action_prompt = "E: GRAB GLASSES"
	d.noise_sound = "click"
	d.noise_loudness = 0.25
	return d
