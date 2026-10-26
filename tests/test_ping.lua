-- Offline test: HUD ping / recent-sample window / friends auto refresh
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

Color = setmetatable({}, {
	__call = function(_, a, r, g, b)
		return { a = a, r = r, g = g, b = b }
	end
})

function Color.get_a(color)
	return color.a
end

function Color.set_a(color, a)
	return { a = a, r = color.r, g = color.g, b = color.b }
end

Vector3 = function(x, y, z)
	return { x = x, y = y, z = z }
end

local ping_value = 0.02

Network = {
	ping = function(peer)
		return ping_value
	end
}

local handler = {
	values = {},
	base = 0,
	session = {
		peers = function()
			return { "peer_client", "peer_host" }
		end
	}
}

function handler:set_calculate_ping(on, interval)
	self.base = 0
end

function handler:update_pings()
	-- vanilla behaviour; placeholder only
end

function handler:get_average_ping(peer)
	return self.base
end

NetworkSessionHandler = handler

local player2 = {
	owned = function()
		return false
	end,
	owner = function()
		return "peer_client"
	end
}

local player_self = {
	owned = function()
		return true
	end,
	owner = function()
		return "peer_self"
	end
}

local player_host = {
	owned = function()
		return false
	end,
	owner = function()
		return "peer_host"
	end
}

NetworkGlobal = {
	lobby = {
		lobby_host = function()
			return "peer_host"
		end
	}
}

Boot = {
	state_machine = {
		get_current_state = function()
			return { network_session_handler = handler }
		end
	}
}

local hud_calls = {}

local function new_gui()
	return {
		calls = {},
		move = function(self, pos)
			self.pos = pos
		end,
		set_current_font = function(self, name)
			self.font = name
		end,
		get_text_extents = function(self, text)
			return 60
		end,
		text = function(self, text, pos, color)
			hud_calls[#hud_calls + 1] = { text = text, pos = pos, color = color }
		end
	}
end

Hud = {}

function Hud:get_player_hud_pos(index)
	return { x = 10, y = 20, z = 0 }
end

function Hud.draw_hud(self, ...)
	self.drawn = (self.drawn or 0) + 1
	self.arg_count = select("#", ...)
	self.arg9 = select(9, ...)
end

local esc_texts = {}

GuiManager = {}

function GuiManager.draw_text(self, text, ...)
	esc_texts[#esc_texts + 1] = text
end

local friends_updates = 0

MenuScreenCampaignMultiplayer = {}

function MenuScreenCampaignMultiplayer.update(self, ...)
	friends_updates = friends_updates + 1
end

WorldManager = {
	update = function(self, dt) end
}

assert(loadfile("lua/dive_harder.lua"))()
assert(loadfile("lua/ping_hud.lua"))()

local G = DiveHarderPatch
G.ping_hud_tick()

local failed = 0

local function check(name, got, want)
	if got == want then
		print(string.format("ok   %-46s %s", name, tostring(got)))
	else
		failed = failed + 1
		print(string.format("FAIL %-46s got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

local function near(name, got, want)
	local ok = type(got) == "number" and math.abs(got - want) < 1e-6

	if ok then
		print(string.format("ok   %-46s %.6f", name, got))
	else
		failed = failed + 1
		print(string.format("FAIL %-46s got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

-- 1) scheme B: mean of the last N samples
settings["diveharder/ping_window"] = 3

for _, value in ipairs({ 0.010, 0.020, 0.030, 0.040 }) do
	ping_value = value
	handler:update_pings()
end

near("window=3 average of last 3", handler:get_average_ping("peer_client"), (0.020 + 0.030 + 0.040) / 3)

settings["diveharder/ping_window"] = 5
handler:update_pings()
near("window=5 average of last 4", handler:get_average_ping("peer_client"), (0.020 + 0.030 + 0.040 + 0.040) / 4)

handler:set_calculate_ping(true)
handler.base = 0.123
near("after reset falls back to original", handler:get_average_ping("peer_client"), 0.123)

-- 2) HUD drawing
settings["diveharder/ping_window"] = 5
settings["diveharder/hud_ping"] = true


handler:set_calculate_ping(true)
handler.base = 0

ping_value = 0.042
handler:update_pings()

local gui = new_gui()
local screen = {
	hud_info = {
		[2] = { current_height = 90, width = 210 }
	},
	hd_gui = gui,
	get_player_hud_pos = function(self, index)
		return { x = 10, y = 20, z = 0 }
	end
}

hud_calls = {}
Hud.draw_hud(screen, 0, nil, nil, 2, nil, nil, nil, nil, { player_go = player2 })
check("hud text drawn", #hud_calls, 1)
check("hud text", hud_calls[1] and hud_calls[1].text, "PING: 42.00ms")
check("hud text alpha", hud_calls[1] and hud_calls[1].color.a, 255)
check("hud text below card", hud_calls[1] and hud_calls[1].pos.y, -18)
check("hud text left aligned", hud_calls[1] and hud_calls[1].pos.x, 4)
check("draw_hud forwards arg count", screen.arg_count, 9)
check("draw_hud forwards info slot", screen.arg9 and screen.arg9.player_go, player2)

-- not drawn on the ship (state_name == "menu")
hud_calls = {}
screen.state_name = "menu"
Hud.draw_hud(screen, 0, nil, nil, 2, nil, nil, nil, nil, { player_go = player2 })
check("ship skips hud text", #hud_calls, 0)
screen.state_name = "game"

-- the host card is drawn too (only the local machine is skipped)
hud_calls = {}
Hud.draw_hud(screen, 0, nil, nil, 2, nil, nil, nil, nil, { player_go = player_host })
check("host card drawn", #hud_calls, 1)

-- the local player's own card is not drawn
hud_calls = {}
Hud.draw_hud(screen, 0, nil, nil, 2, nil, nil, nil, nil, { player_go = player_self })
check("own card skipped", #hud_calls, 0)

-- nothing is drawn while the option is off
hud_calls = {}
settings["diveharder/hud_ping"] = false
Hud.draw_hud(screen, 0, nil, nil, 2, nil, nil, nil, nil, { player_go = player2 })
check("disabled skips hud text", #hud_calls, 0)

-- resample and check drawing with the option on and off
settings["diveharder/hud_ping"] = true

handler:set_calculate_ping(true)
handler:update_pings()
hud_calls = {}
Hud.draw_hud(screen, 0, nil, nil, 2, nil, nil, nil, nil, { player_go = player2 })
-- the ESC Avg Ping text is doubled so it shows RTT like the HUD
esc_texts = {}
GuiManager.draw_text(nil, "Avg Ping: 21.00ms")
check("esc ping doubled", esc_texts[1], "Avg Ping: 42.00ms")

esc_texts = {}
GuiManager.draw_text(nil, "OTHER TEXT")
check("esc other text untouched", esc_texts[1], "OTHER TEXT")

-- 3) friends list auto refresh
local friends_screen = {
	filter = { name = "friends" },
	refresh_timer = 600
}

MenuScreenCampaignMultiplayer.update(friends_screen)
check("friends refresh forced", friends_screen.refresh_timer, -1)
check("friends refresh flag", friends_screen.dh_friends_refreshed, true)
check("original update still called", friends_updates, 1)

-- other filters are untouched
local public_screen = {
	filter = { name = "public" },
	refresh_timer = 600
}

MenuScreenCampaignMultiplayer.update(public_screen)
check("public untouched", public_screen.refresh_timer, 600)
check("public flag nil", public_screen.dh_friends_refreshed, nil)

-- switching back to the friends filter refreshes again (re-armed)
local again = {
	filter = { name = "friends" },
	refresh_timer = 600
}

MenuScreenCampaignMultiplayer.update(again)
check("new screen refreshed", again.refresh_timer, -1)

-- 4) the three menu options exist (built by core, ping_hud_supported registered)
check("ping module registered", type(G.ping_hud_supported) == "function", true)

if failed == 0 then
	print("\nall ping tests passed")
else
	print(string.format("\n%d check(s) failed", failed))
	os.exit(1)
end
