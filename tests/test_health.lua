-- Offline test: enemy health multipliers (off / hard / helldive) against fake components
package.path = package.path

local settings = {}

Application = {
	user_setting = function(section, key)
		return settings[section .. "/" .. key]
	end,
	set_user_setting = function(section, key, value)
		settings[section .. "/" .. key] = value
	end,
	save_user_settings = function() end
}

local is_enemy = {}

EntityAux = {
	has_component = function(unit, name)
		return name == "enemy" and is_enemy[unit] == true
	end
}

HealthComponent = {}

function HealthComponent:set_protected(state, key, value)
	self.protected = self.protected or {}
	self.protected[key] = value
end

function HealthComponent.setup_master(self, unit, data)
	local s = data.state

	s.max_hitpoints = s.health
	s.constitution = -(s.constitution or 0)
	s.hitpoints = s.max_hitpoints
	self:set_protected(s, "hitpoints_real", s.max_hitpoints)

	return "orig"
end

function HealthComponent.setup_slave(self, unit, data)
	local s = data.state

	s.max_hitpoints = s.health
	s.constitution = -(s.constitution or 0)

	return "orig"
end

WorldManager = {
	update = function(self, dt) end
}

assert(loadfile("lua/dive_harder.lua"))()

local function new_state(health, constitution)
	return {
		health = health,
		constitution = constitution
	}
end

local enemy = {}
is_enemy[enemy] = true

local player = {}
is_enemy[player] = false

local failed = 0

local function check(name, got, want)
	if got == want then
		print(string.format("ok   %-38s %s", name, tostring(got)))
	else
		failed = failed + 1
		print(string.format("FAIL %-38s got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

local function setup(state, unit, master)
	local component = setmetatable({}, { __index = HealthComponent })
	local data = { state = state }

	if master then
		HealthComponent.setup_master(component, unit, data)
	else
		HealthComponent.setup_slave(component, unit, data)
	end

	return state, component
end

-- off
settings["diveharder/enemy_health"] = "off"
local s1 = setup(new_state(100, 50), enemy, true)
check("off max", s1.max_hitpoints, 100)
check("off constitution", s1.constitution, -50)
check("off hitpoints", s1.hitpoints, 100)

-- hard (x1.5)
settings["diveharder/enemy_health"] = "hard"
local s2, c2 = setup(new_state(100, 50), enemy, true)
check("hard max", s2.max_hitpoints, 150)
check("hard constitution", s2.constitution, -75)
check("hard hitpoints", s2.hitpoints, 150)
check("hard hitpoints_real", c2.protected.hitpoints_real, 150)
check("hard total", s2.max_hitpoints + math.abs(s2.constitution), 225)

-- helldive (x2)
settings["diveharder/enemy_health"] = "helldive"
local s3 = setup(new_state(100, 50), enemy, true)
check("helldive max", s3.max_hitpoints, 200)
check("helldive constitution", s3.constitution, -100)
check("helldive hitpoints", s3.hitpoints, 200)
check("helldive total", s3.max_hitpoints + math.abs(s3.constitution), 300)

-- players are not affected
settings["diveharder/enemy_health"] = "helldive"
local s4 = setup(new_state(100, 50), player, true)
check("player max", s4.max_hitpoints, 100)
check("player constitution", s4.constitution, -50)

-- a repeated setup does not stack
settings["diveharder/enemy_health"] = "hard"
local comp = setmetatable({}, { __index = HealthComponent })
local data = { state = new_state(100, 50) }

HealthComponent.setup_master(comp, enemy, data)
local first = data.state.max_hitpoints
HealthComponent.setup_master(comp, enemy, data)
check("re-setup no stacking (first)", first, 150)
check("re-setup no stacking (again)", data.state.max_hitpoints, 150)

-- client side (slave): only the max is scaled, the synced hitpoints are left alone
settings["diveharder/enemy_health"] = "helldive"
local s5 = setup(new_state(80, 20), enemy, false)
check("slave max", s5.max_hitpoints, 160)
check("slave constitution", s5.constitution, -40)
check("slave hitpoints untouched", s5.hitpoints, nil)

-- unknown config values fall back to off
settings["diveharder/enemy_health"] = "bogus"
local s6 = setup(new_state(100, 50), enemy, true)
check("unknown value -> off", s6.max_hitpoints, 100)

if failed == 0 then
	print("\nall health tests passed")
else
	print(string.format("\n%d check(s) failed", failed))
	os.exit(1)
end
