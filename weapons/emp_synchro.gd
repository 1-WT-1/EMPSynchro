extends Sprite

export  var repairReplacementPrice = 450000
export  var repairReplacementTime = 1
export  var repairFixPrice = 30000
export  var repairFixTime = 12

export  var powerDraw = 420000.0
export  var power = 375000.0
export  var maxCharge = 11250000
export  var discharge = 37500.0
export  var minCharge = 562500
export var maxStormCharge = 956250  #11250000
export  var maxStorms = 10
export  var systemName = "SYSTEM_SYNCHRO_EMP"
export  var maxDistance = 4500.0
export  var hostilityDistance = 4500.0
export  var command = "w"
export  var pitchScale = 12
export  var penetration = 24
export (PackedScene) var stormScene
export  var hostilityForFullCharge = 10.0

export  var kineticDamageScale = 0.025
export  var afterImageTime = 0.4
export  var afterImageMin = 0.2

export  var mass = 17000

export (Array, NodePath) var spark_sprites = [
	NodePath("Sprite6")
]

var ray = Vector2(0, - maxDistance)

var ship
var firepower = 0
var readpower = 0

func boresight():
	return {
		"start": global_position,
		"range": maxDistance,
		"angle": (2 * PI / 360) * 0.1,
		"direction": global_rotation
	}

var slot
func getSlotName(param):
	return "weaponSlot.%s.%s" % [slot, param]

func _ready():
	ship = getShip()
	var parent = get_parent()
	if "slot" in parent:
		slot = parent.slot


	for s in sparks:
		s.material = s.material.duplicate()
		timeOffsets.append(randf() * 60)
	material = material.duplicate()
	
	#extra Sprites
	for path in spark_sprites:
		if has_node(path):
			var s = get_node(path)
			s.material = s.material.duplicate()
			extraSprites.append(s)

func getStatus():
	return 100

func shouldFire():
	return ship.powerBalance > maxCharge * 0.5

func getPower():
	return charge / maxCharge

func getShip():
	var c = self
	while not c.has_method("getConfig") and c != null:
		c = c.get_parent()
	return c

func fire(p):
	firepower = clamp(p, 0, 1)

onready var audioCharge = $AudioCharge
onready var audioFire = $AudioFire
onready var flare = $Flare
onready var flareEnergy = flare.energy
onready var beamCore = $BeamCore
onready var slotName = name
onready var sparks = [$Sparks1, $Sparks2, $Sparks3]
onready var timeOffsets = []
onready var initialSparkRect = sparks[0].region_rect
var extraSprites = []

export (float, 0, 1, 0.05) var kineticPart = 0.05
export (float, 0, 1, 0.05) var thermalPart = 0.0
export (float, 0, 1, 0.05) var empPart = 0.1
export (float, 0, 1, 0.05) var lingeringPart = 0.85

var afterImage = 0
var cycle = 0.0
var charge = 0.0
func _physics_process(delta):
	fade(delta)
	if firepower > 0:
		var pd = powerDraw
		var energyRequired = delta * firepower * pd
		var energy = ship.drawEnergy(energyRequired)
		charge = clamp(charge + energy * power / powerDraw, 0, maxCharge)
		if not audioCharge.playing and ship.isPlayerControlled():
			audioCharge.play()
		audioCharge.pitch_scale = max(sqrt(charge / maxCharge) * pitchScale, 0.1)
	else:
		if charge > minCharge:
			audioCharge.stop()
			if ship.isPlayerControlled():
				audioFire.play()

			var space_state = get_world_2d().direct_space_state
			var hitpoint = space_state.intersect_ray(global_position, global_position + ray.rotated(global_rotation), ship.physicsExclude, 35)

			var distance = maxDistance
			if ship.isPlayerControlled():
				CurrentGame.logEvent("LOG_EVENT_DIVE", {"LOG_EVENT_DETAILS_SYNCHRO": charge / 1000000.0})

			if hitpoint and Tool.claim(hitpoint.collider):
				var output = charge
				if output >= maxCharge:
					Achivements.achive("PLAYSTYLE_UNLIMITED_POWER")
				var penvec = (hitpoint.position - global_position).normalized() * penetration * (charge / maxCharge)
				var hit = hitpoint.position + penvec
				var hitDistance = global_position.distance_to(hit)
				distance = hitDistance
				if hitpoint.collider.has_method("applyEnergyDamage"):
					hitpoint.collider.applyEnergyDamage(output * thermalPart, hit, delta)
				if hitpoint.collider.has_method("applyKineticDamage"):
					hitpoint.collider.applyKineticDamage(output * kineticPart * kineticDamageScale, hit)
				if hitpoint.collider.has_method("applyEmpDamage"):
					hitpoint.collider.applyEmpDamage(output * empPart, hit, delta)
				if hitpoint.collider.has_method("applyHostility"):
					hitpoint.collider.applyHostility(
						ship.faction,
						(charge / maxCharge) * hostilityForFullCharge * (1 - clamp((hitDistance - hostilityDistance) / hostilityDistance, 0, 1))
					)
				ship.youHit(hitpoint.collider, charge / maxCharge)
				flare.global_position = hit
				flare.visible = true
				flare.rotation = randf() * 2 * PI
				Tool.release(hitpoint.collider)
				var field = ship.get_parent()

				var stormPower = output * lingeringPart
				var perStormPower = stormPower / maxStorms
				var nr = maxStorms
				while stormPower >= 0 and nr > 0:
					nr -= 1
					var storm = stormScene.instance()
					var c = min(max(maxStormCharge, perStormPower), stormPower)
					storm.chargeLimit = c
					storm.global_position = hit
					Tool.deferCallInPhysics(field, "add_child", [storm])
					stormPower -= c
			else:
				flare.visible = false
			beamCore.scale = Vector2(1, distance / 512)
			beamCore.visible = true
			var srect = Rect2(initialSparkRect.position, initialSparkRect.size)
			for s in sparks:
				srect.size.y = distance / s.scale.y + s.position.y - s.offset.y
				s.region_rect = srect
				s.material.set_shader_param("regionScale", initialSparkRect.size / srect.size)
				s.visible = true
			afterImage = min(afterImageTime * sqrt(charge / maxCharge), afterImageMin)
			charge = 0
		else:
			charge = clamp(charge - discharge * delta, 0, maxCharge)
			if charge > 0:
				audioCharge.pitch_scale = max(sqrt(charge / maxCharge) * pitchScale, 0.1)
			else:
				if audioCharge.is_playing():
					audioCharge.stop()

func fade(delta):
	afterImage -= delta
	if afterImage <= 0:
		flare.visible = false
		beamCore.visible = false
		beamCore.modulate.a = 1
		for s in sparks:
			s.visible = false
	else:
		var d = max(afterImage, 0) / afterImageTime
		flare.energy = flareEnergy * d
		beamCore.modulate.a = d
		for s in sparks:
			s.modulate.a = d


var time = 0
func _process(delta):
	var sb = charge / maxCharge
	material.set_shader_param("sparkBias", sb)
	for s in extraSprites:
		s.material.set_shader_param("sparkBias", sb)

	var nr = 0
	for s in sparks:
		s.material.set_shader_param("timeOffset", time + timeOffsets[nr])
		nr += 1
	time += delta
