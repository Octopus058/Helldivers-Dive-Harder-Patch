-- Offline test: the ENEMY HEALTH option on the MOD SETTINGS page: presence, switching, saving
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

MenuScreenBase = {}

function MenuScreenBase.get_user_inputs(self, input)
	return input
end

function MenuScreenBase.was_option_selected(self, input, other, field)
	return input[field or "select"] == true
end

function MenuScreenBase.was_text_button_clicked()
	return false
end

function MenuScreenBase.handle_input_cursor() end

function MenuScreenBase.reset_clickable_buttons(self)
	self.selected_text_buttons = {}
	self.selected_scroll_buttons = {}
end

function MenuScreenBase.draw_title() end

MenuScreenMain = {}

function MenuScreenMain.on_enter(self, params)
	self.options = {
		{ name = "menu_settings" },
		{ name = "main_menu_quit_game" }
	}
	self.selected_option = 1
end

function MenuScreenMain.handle_input(self, input) end

function MenuScreenMain.update(self, dt, ...)
	self.seen_state_name = self.state_name
end

function MenuScreenMain.update_option_selection(self, item, direction)
	item.options.selected_index = item.options.selected_index + direction

	if item.options.selected_index < 1 then
		item.options.selected_index = #item.options
	elseif item.options.selected_index > #item.options then
		item.options.selected_index = 1
	end
end

WorldManager = {
	update = function(self, dt) end
}

assert(loadfile("lua/dive_harder.lua"))()
assert(loadfile("lua/ping_hud.lua"))()

local failed = 0

local function check(name, got, want)
	if got == want then
		print(string.format("ok   %-40s %s", name, tostring(got)))
	else
		failed = failed + 1
		print(string.format("FAIL %-40s got=%s want=%s", name, tostring(got), tostring(want)))
	end
end

local function new_screen()
	return {
		user_pad_number = 1,
		state_name = "menu",
		state_stack = {},
		play_sound_accept = function() end,
		play_sound_scroll = function() end,
		play_sound_back = function() end
	}
end

local function find_index(screen, name)
	for i, item in ipairs(screen.options) do
		if item.name == name then
			return i
		end
	end
end

-- 1) MOD SETTINGS is inserted into the pause menu
local screen = new_screen()
MenuScreenMain.on_enter(screen, {})
check("MOD SETTINGS inserted", find_index(screen, "mod_settings") ~= nil, true)

-- 2) selecting it and pressing accept takes over the page
screen.selected_option = find_index(screen, "mod_settings")
MenuScreenMain.handle_input(screen, { select = true })
check("page opened", screen.dh_mod_page, true)

local health_index = find_index(screen, "dh_enemy_health")
check("ENEMY HEALTH row exists", health_index ~= nil, true)

local health = screen.options[health_index]
check("ENEMY HEALTH option count", health.options and #health.options, 3)
check("option 1", health.options[1].name, "OFF")
check("option 2", health.options[2].name, "HARD")
check("option 3", health.options[3].name, "HELLDIVE")
check("option 1 value", health.options[1].value, "off")
check("option 2 value", health.options[2].value, "hard")
check("option 3 value", health.options[3].value, "helldive")

-- 3) switch to HELLDIVE, also set HUD PING / PING WINDOW, then APPLY CHANGES saves them
health.options.selected_index = 3

local hud_ping_index = find_index(screen, "dh_hud_ping")
local window_index = find_index(screen, "dh_ping_window")

check("HUD PING row exists", hud_ping_index ~= nil, true)
check("PING WINDOW row exists", window_index ~= nil, true)
check("window values", window_index and #screen.options[window_index].options, 3)

screen.options[hud_ping_index].options.selected_index = 2   -- ON
screen.options[window_index].options.selected_index = 1     -- 3

local apply_index = find_index(screen, "options_apply_changes")
check("APPLY row exists", apply_index ~= nil, true)

screen.selected_option = apply_index
MenuScreenMain.handle_input(screen, { select = true })
check("saved value", settings["diveharder/enemy_health"], "helldive")
check("saved hud ping", settings["diveharder/hud_ping"], true)
check("saved window", settings["diveharder/ping_window"], 3)

-- 4) reopening the page reads the saved values
MenuScreenMain.on_enter(screen, {})
screen.selected_option = find_index(screen, "mod_settings")
MenuScreenMain.handle_input(screen, { select = true })
health = screen.options[find_index(screen, "dh_enemy_health")]
check("value restored on reopen", health.options.selected_index, 3)

-- 5) while drawing, state_name is treated as main_menu (drops the SQUAD header)
MenuScreenMain.update(screen, 0.1, 0)
check("drawn as main_menu", screen.seen_state_name, "main_menu")
check("state_name restored", screen.state_name, "menu")

-- 6) ESC leaves the page and returns to the normal list
MenuScreenMain.handle_input(screen, { back = true })
check("page left", screen.dh_mod_page, nil)
check("options restored", find_index(screen, "menu_settings") ~= nil, true)

-- 7) no QoL means no QoL group; it appears after QoL is detected and the page is reopened
MenuScreenMain.on_enter(screen, {})
screen.selected_option = find_index(screen, "mod_settings")
MenuScreenMain.handle_input(screen, { select = true })
check("no QoL rows without QoL", find_index(screen, "display_player_text_as_chat"), nil)

MenuScreenMain.handle_input(screen, { back = true })
QOL_GAME_INFORMATION = "QoL: v.test"
MenuScreenMain.on_enter(screen, {})
screen.selected_option = find_index(screen, "mod_settings")
MenuScreenMain.handle_input(screen, { select = true })
check("QoL rows appear with QoL", find_index(screen, "display_player_text_as_chat") ~= nil, true)
QOL_GAME_INFORMATION = nil

if failed == 0 then
	print("\nall menu tests passed")
else
	print(string.format("\n%d check(s) failed", failed))
	os.exit(1)
end
