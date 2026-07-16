class_name ObjectiveDef
extends Resource
## Data definition for an escape objective (launch plan 3.1: objectives are
## DATA + a prefab, never engine changes). An objective is: a clue that spawns
## at one of several candidate spots, an action spot where the work happens,
## and an id the round loop listens for. The Landline is the first content.

@export var id: String = ""
@export var display_name: String = ""
@export var clue_spots: Array[Vector3] = []   ## world positions (already scaled)
@export var action_spot: Vector3 = Vector3.ZERO
@export var action_prompt: String = "HOLD E"

static func landline() -> ObjectiveDef:
	var def := ObjectiveDef.new()
	def.id = "landline"
	def.display_name = "The Landline"
	for spot: Vector3 in HouseSuburban.CLUE_SPOTS:
		def.clue_spots.append(HouseSuburban.scaled(spot))
	def.action_spot = HouseSuburban.scaled(HouseSuburban.PHONE_SPOT)
	def.action_prompt = "E: DIAL"
	return def
