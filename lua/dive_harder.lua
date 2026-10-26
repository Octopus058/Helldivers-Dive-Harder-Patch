-- Dive Harder Patch 0.1.0
-- 1) unlock defeated factions; 2) hidden objectives (question marks) shown from mission start;
-- 3) results-screen chat font fix; 4) new MOD SETTINGS page in the pause menu;
-- 5) main-menu version label (QoL on top, Dive Harder below it).
do
	local G = DiveHarderPatch or {}

	DiveHarderPatch = G

	if not G.inited then
		G.inited = true
		G.raw = 0
		G.issued = setmetatable({}, { __mode = "k" })
		G.wrapped_fns = setmetatable({}, { __mode = "k" })
		G.extensions = G.extensions or {
			labels = {},
			options = {},
			apply = {},
			tick = {}
		}
	end

	local SECTION = "diveharder"
	local POINTS = 0.95
	local VERSION = "Dive Harder: v.0.1.0"
	local MOD_TITLE = "MOD SETTINGS"

	local function setting(key, default)
		local ok, value = pcall(function()
			return Application.user_setting(SECTION, key)
		end)

		if ok and value ~= nil then
			return value
		end

		return default
	end

	local function set_setting(key, value)
		pcall(function()
			Application.set_user_setting(SECTION, key, value)
		end)
	end

	local function qol_setting(key, default)
		local ok, value = pcall(function()
			return Application.user_setting("qol", key)
		end)

		if ok and value ~= nil then
			return value
		end

		return default
	end

	function G.front_on()
		return setting("front_unlock", true) ~= false
	end

	function G.hidden_on()
		return setting("reveal_hidden", false) == true
	end

	-- ---------------------------------------------------------------- defeated factions
	local function patched(raw)
		if G.raw > 0 or type(raw) ~= "table" or not G.front_on() then
			return raw
		end

		if G.src == raw and G.out then
			return G.out
		end

		local out, any = {}, false

		for i, s in ipairs(raw) do
			if type(s) == "table" and s.status == "defeated" and type(s.points_max) == "number" and s.points_max > 0 then
				local c = {}

				for k, v in pairs(s) do
					c[k] = v
				end

				c.status = "active"
				c.points = math.floor(s.points_max * POINTS)
				out[i] = c
				any = true
			else
				out[i] = s
			end
		end

		if not any then
			return raw
		end

		G.src, G.out = raw, out
		G.issued[out] = raw

		return out
	end

	local function as_raw(f)
		local function finish(ok, ...)
			G.raw = G.raw - 1

			if not ok then
				error((...), 0)
			end

			return ...
		end

		return function(...)
			G.raw = G.raw + 1

			return finish(pcall(f, ...))
		end
	end

	local function hook_campaign()
		local cm = rawget(_G, "CampaignManager")

		if type(cm) ~= "table" or type(cm.get_campaign_status) ~= "function" then
			return false
		end

		if cm.get_campaign_status ~= G.get_status then
			local orig = cm.get_campaign_status

			G.get_status = function(...)
				return patched(orig(...))
			end
			cm.get_campaign_status = G.get_status
		end

		return true
	end

	local function hook_save()
		local sm = rawget(_G, "SaveManager")

		if type(sm) ~= "table" or type(sm.set) ~= "function" then
			return false
		end

		if sm.set ~= G.save_set then
			local orig = sm.set

			G.save_set = function(self, key, value, ...)
				if key == "last_shown_recap_status" and value ~= nil and G.issued[value] then
					value = G.issued[value]
				end

				return orig(self, key, value, ...)
			end
			sm.set = G.save_set
		end

		return true
	end

	local function hook_recap()
		local cls = rawget(_G, "MenuScreenCampaignRecap")

		if type(cls) ~= "table" then
			return false
		end

		local names = {}

		for k, f in pairs(cls) do
			if type(f) == "function" and not G.wrapped_fns[f] then
				names[#names + 1] = k
			end
		end

		for _, k in ipairs(names) do
			local w = as_raw(cls[k])

			G.wrapped_fns[w] = true
			cls[k] = w
		end

		return true
	end

	-- ---------------------------------------------------------------- hidden objectives
	local function hook_level()
		local lvl = rawget(_G, "Level")

		if type(lvl) ~= "table" or type(lvl.get_data) ~= "function" then
			return false
		end

		if lvl.get_data == G.level_get_data then
			return true
		end

		local orig = lvl.get_data

		G.level_get_data = function(...)
			if select(2, ...) == "objective_hidden_data" and G.hidden_on() then
				return nil
			end

			return orig(...)
		end
		lvl.get_data = G.level_get_data

		return true
	end

	-- ---------------------------------------------------------------- enemy health
	-- tiers: off / hard (x1.5) / helldive (x2); enemies only, players untouched
	local HEALTH_FACTORS = {
		off = 1,
		hard = 1.5,
		helldive = 2
	}

	local function health_factor()
		local value = setting("enemy_health", "off")

		if type(value) == "number" then
			return value
		end

		return HEALTH_FACTORS[value] or 1
	end

	local function is_enemy_entity(unit)
		local ok, value = pcall(function()
			return EntityAux.has_component(unit, "enemy")
		end)

		return ok and value or false
	end

	-- total damage an enemy can absorb = max_hitpoints + |constitution|, so both are scaled
	local scaled_states = setmetatable({}, {
		__mode = "k"
	})

	local function scale_enemy_health(self, unit, state, is_master)
		local factor = health_factor()

		if factor == 1 or type(state) ~= "table" then
			return
		end

		if type(state.max_hitpoints) ~= "number" or not is_enemy_entity(unit) then
			return
		end

		-- keep the original values: a repeated setup rescales from the base and never multiplies twice
		local base = scaled_states[state]

		if not base then
			base = {
				max = state.max_hitpoints,
				constitution = state.constitution
			}
			scaled_states[state] = base
		end

		state.max_hitpoints = base.max * factor

		if type(base.constitution) == "number" then
			state.constitution = base.constitution * factor
		end

		if is_master then
			-- the host is authoritative: spawn hitpoints and the hitpoints_real synced to clients both scale
			state.hitpoints = state.max_hitpoints

			if type(self.set_protected) == "function" then
				pcall(function()
					self:set_protected(state, "hitpoints_real", state.max_hitpoints)
				end)
			end
		end
	end

	local function hook_health()
		local cls = rawget(_G, "HealthComponent")

		if type(cls) ~= "table" or type(cls.setup_master) ~= "function" then
			return false
		end

		if cls.setup_master == G.hc_setup_master then
			return true
		end

		local orig_master = cls.setup_master
		local orig_slave = cls.setup_slave

		G.hc_setup_master = function(self, unit, data, ...)
			local result = orig_master(self, unit, data, ...)

			pcall(function()
				scale_enemy_health(self, unit, data and data.state, true)
			end)

			return result
		end
		cls.setup_master = G.hc_setup_master

		if type(orig_slave) == "function" then
			G.hc_setup_slave = function(self, unit, data, ...)
				local result = orig_slave(self, unit, data, ...)

				pcall(function()
					scale_enemy_health(self, unit, data and data.state, false)
				end)

				return result
			end
			cls.setup_slave = G.hc_setup_slave
		end

		return true
	end

	-- ---------------------------------------------------------------- text
	-- every mod option is uppercase; QoL keys get an empty prefix in place of the game's "LOC:"
	local LABELS = {
		mod_settings = "MOD SETTINGS",
		options_apply_changes = "APPLY CHANGES",
		dh_section_qol = "QoL",
		dh_section_dh = "DIVE HARDER",
		dh_front_unlock = "UNLOCK DEFEATED FACTIONS",
		dh_reveal_hidden = "SHOW HIDDEN OBJECTIVES",
		dh_enemy_health = "ENEMY HEALTH",
		dh_hud_ping = "HUD PING",
		dh_ping_window = "PING WINDOW",
		display_player_text_as_chat = "PLAYER NAMES AS CHAT FONT",
		custom_lobby_name_show = "SHOW CUSTOM LOBBY NAME",
		ps_buttons_show = "PS BUTTONS",
		override_viewport_aspect_ratio = "OVERRIDE VIEWPORT ASPECT RATIO",
		camera_shake_multiplier = "CAMERA SHAKE MULTIPLIER",
		main_menu_tutorial = "TRAINING",
		stratagem_emergency_beacon = "EMERGENCY BEACON",
		skip_intro_video = "SKIP INTRO VIDEO",
		comm_time = "COMMENT TIME INTERVAL",
		control_interact = "INTERACT HOLD",
		menu_not_sticky = "WEAPON SWAP HOLD",
		press_cross_to_join = "ALLOW LOCAL PLAYER JOIN",
		mission_type_genocide = "RETALIATORY MISSION CHANCE"
	}

	local function hook_loc()
		local lm = rawget(_G, "LocalizationManager")

		if type(lm) ~= "table" or type(lm.string) ~= "function" then
			return false
		end

		if lm.string == G.loc_string then
			return true
		end

		local orig = lm.string

		G.loc_string = function(self, key, ...)
			if type(key) == "string" then
				local label = LABELS[key] or G.extensions.labels[key]

				if label then
					return label
				end
			end

			local text = orig(self, key, ...)

			-- untranslated keys come back as "LOC:xxx"; show the key uppercase with underscores stripped
			if type(text) == "string" and type(key) == "string" and text:sub(1, 4) == "LOC:" then
				return key:gsub("_", " "):upper()
			end

			return text
		end
		lm.string = G.loc_string

		return true
	end

	-- ---------------------------------------------------------------- results-screen chat font
	local function hook_guimanager()
		local cls = rawget(_G, "GuiManager")

		if type(cls) ~= "table" or type(cls.update) ~= "function" then
			return false
		end

		if cls.update == G.gm_update then
			return true
		end

		local orig = cls.update

		G.gm_update = function(self, ...)
			local result = orig(self, ...)

			pcall(function()
				local q = Application.user_setting("qol", "display_player_text")

				if q ~= nil then
					self.display_player_text = q
				end
			end)

			return result
		end
		cls.update = G.gm_update

		return true
	end

	-- ---------------------------------------------------------------- mod options
	local QOL_SPECS = {
		{
			group = "display_player_text_as_chat",
			key = "display_player_text",
			default = false,
			values = {
				{
					"OFF",
					false
				},
				{
					"ON",
					true
				}
			}
		},
		{
			group = "custom_lobby_name_show",
			key = "custom_lobby_name_show",
			default = false,
			values = {
				{
					"OFF",
					false
				},
				{
					"ON",
					true
				}
			}
		},
		{
			group = "ps_buttons_show",
			key = "ps_buttons_show",
			default = false,
			values = {
				{
					"OFF",
					false
				},
				{
					"ON",
					true
				}
			}
		},
		{
			group = "override_viewport_aspect_ratio",
			key = "override_viewport_aspect_ratio",
			default = false,
			values = {
				{
					"OFF",
					false
				},
				{
					"ON",
					true
				}
			}
		},
		{
			group = "camera_shake_multiplier",
			key = "camera_shake_multiplier",
			default = 1,
			values = {
				{
					"0%",
					0
				},
				{
					"25%",
					0.25
				},
				{
					"50%",
					0.5
				},
				{
					"75%",
					0.75
				},
				{
					"100%",
					1
				},
				{
					"125%",
					1.25
				},
				{
					"150%",
					1.5
				},
				{
					"175%",
					1.75
				},
				{
					"200%",
					2
				},
				{
					"1000%",
					10
				}
			}
		},
		{
			group = "main_menu_tutorial",
			key = "train_mode",
			default = false,
			values = {
				{
					"YES",
					true
				},
				{
					"NO",
					false
				}
			}
		},
		{
			group = "stratagem_emergency_beacon",
			key = "has_emergency_beacon",
			default = true,
			values = {
				{
					"YES",
					true
				},
				{
					"NO",
					false
				}
			}
		},
		{
			group = "skip_intro_video",
			key = "skip_splash",
			default = false,
			values = {
				{
					"YES",
					true
				},
				{
					"NO",
					false
				}
			}
		},
		{
			group = "comm_time",
			key = "comm_time",
			default = 3,
			values = {
				{
					"3",
					3
				},
				{
					"2",
					2
				}
			}
		},
		{
			group = "control_interact",
			key = "interact_hold",
			default = true,
			values = {
				{
					"HOLD",
					true
				},
				{
					"MASH",
					false
				}
			}
		},
		{
			group = "menu_not_sticky",
			key = "weapon_swap_hold_support",
			default = false,
			values = {
				{
					"SUPPORT WEAPON",
					true
				},
				{
					"SIDEARM",
					false
				}
			}
		},
		{
			group = "press_cross_to_join",
			key = "allow_adding_local_player",
			default = true,
			values = {
				{
					"YES",
					true
				},
				{
					"NO",
					false
				}
			}
		},
		{
			group = "mission_type_genocide",
			key = "rs_chance",
			default = 0.33,
			values = {
				{
					"0%",
					0
				},
				{
					"33%",
					0.33
				},
				{
					"66%",
					0.66
				},
				{
					"100%",
					1
				}
			}
		}
	}

	local QOL_GRAPHICS_GROUPS = {}
	local QOL_OPTION_GROUPS = {}

	for _, spec in ipairs(QOL_SPECS) do
		if spec.group == "main_menu_tutorial" or spec.group == "stratagem_emergency_beacon" or spec.group == "skip_intro_video" or spec.group == "comm_time" or spec.group == "control_interact" or spec.group == "menu_not_sticky" or spec.group == "press_cross_to_join" or spec.group == "mission_type_genocide" then
			QOL_OPTION_GROUPS[spec.group] = true
		else
			QOL_GRAPHICS_GROUPS[spec.group] = true
		end
	end

	local function make_group(name, key, default)
		local on

		if default == false then
			on = setting(key, false) == true
		else
			on = setting(key, true) ~= false
		end

		return {
			name = name,
			localize_sub_options = false,
			options = {
				selected_index = on and 2 or 1,
				{
					value = false,
					name = "OFF"
				},
				{
					value = true,
					name = "ON"
				}
			}
		}
	end

	-- optional modules appended to this file build their rows with this helper
	G.make_toggle_row = make_group

	local function make_choice_group(name, key, default, values)
		local current = setting(key, default)
		local selected = 1
		local exact = false

		for i, item in ipairs(values) do
			if item[2] == current then
				selected = i
				exact = true

				break
			end
		end

		-- the value may have been stored as float32 by the config; snap to the nearest tier
		if not exact and type(current) == "number" then
			local best

			for i, item in ipairs(values) do
				if type(item[2]) == "number" then
					local diff = math.abs(item[2] - current)

					if best == nil or diff < best then
						best = diff
						selected = i
					end
				end
			end
		end

		local options = {
			selected_index = selected
		}

		for _, item in ipairs(values) do
			options[#options + 1] = {
				value = item[2],
				name = item[1]
			}
		end

		return {
			name = name,
			localize_sub_options = false,
			options = options
		}
	end

	local function build_qol_group(spec)
		local current = qol_setting(spec.key, spec.default)
		local selected = 1
		local exact = false

		for i, item in ipairs(spec.values) do
			if item[2] == current then
				selected = i
				exact = true

				break
			end
		end

		-- the value may come back as float32 (0.66 is not exact); snap to the nearest step
		if not exact then
			local best

			for i, item in ipairs(spec.values) do
				if type(item[2]) == "number" and type(current) == "number" then
					local diff = math.abs(item[2] - current)

					if best == nil or diff < best then
						best = diff
						selected = i
					end
				end
			end
		end

		local options = {
			selected_index = selected
		}

		for _, item in ipairs(spec.values) do
			options[#options + 1] = {
				value = item[2],
				name = item[1]
			}
		end

		return {
			name = spec.group,
			localize_sub_options = false,
			options = options
		}
	end

	local function read_ours(self)
		local opts = self.options

		if type(opts) ~= "table" then
			return
		end

		local pairs_list = {
			{
				"dh_front_unlock",
				"front_unlock"
			},
			{
				"dh_reveal_hidden",
				"reveal_hidden"
			},
			{
				"dh_enemy_health",
				"enemy_health",
				"raw"
			},
			{
				"dh_hud_ping",
				"hud_ping"
			},
			{
				"dh_ping_window",
				"ping_window",
				"raw"
			}
		}

		for _, item in ipairs(pairs_list) do
			local g = opts[item[1]]

			if type(g) == "table" and type(g.options) == "table" then
				local sel = g.options[g.options.selected_index]

				if sel ~= nil then
					if item[3] == "raw" then
						set_setting(item[2], sel.value)
					else
						set_setting(item[2], sel.value ~= false)
					end
				end
			end
		end

		-- optional modules write their own settings on APPLY
		for _, fn in ipairs(G.extensions.apply) do
			pcall(fn, opts)
		end
	end

	local function write_qol_settings(self)
		local opts = self.options

		if type(opts) ~= "table" then
			return
		end

		for _, spec in ipairs(QOL_SPECS) do
			local g = opts[spec.group]

			if type(g) == "table" and type(g.options) == "table" then
				local sel = g.options[g.options.selected_index]

				if sel ~= nil then
					pcall(function()
						Application.set_user_setting("qol", spec.key, sel.value)
					end)
				end
			end
		end
	end

	-- strip QoL options and this mod's options from the Graphics page (they live in MOD SETTINGS now)
	local function hook_graphics()
		local cls = rawget(_G, "MenuScreenGraphics")

		if type(cls) ~= "table" or type(cls.update_options) ~= "function" then
			return false
		end

		if cls.update_options == G.update_options then
			return true
		end

		local orig_update = cls.update_options

		G.update_options = function(self, ...)
			local result = orig_update(self, ...)

			pcall(function()
				local opts = self.options

				if type(opts) ~= "table" then
					return
				end

				for i = #opts, 1, -1 do
					local item = opts[i]

					if item and QOL_GRAPHICS_GROUPS[item.name] then
						table.remove(opts, i)
					end
				end
			end)

			return result
		end
		cls.update_options = G.update_options

		return true
	end

	-- strip QoL options from the SETTINGS (Options) page
	local function hook_options()
		local cls = rawget(_G, "MenuScreenOptions")

		if type(cls) ~= "table" or type(cls.on_enter) ~= "function" then
			return false
		end

		if cls.on_enter == G.options_on_enter then
			return true
		end

		local orig = cls.on_enter

		G.options_on_enter = function(self, ...)
			local result = orig(self, ...)

			pcall(function()
				local opts = self.options

				if type(opts) ~= "table" then
					return
				end

				for i = #opts, 1, -1 do
					local item = opts[i]

					if item and QOL_OPTION_GROUPS[item.name] then
						table.remove(opts, i)
					end
				end
			end)

			return result
		end
		cls.on_enter = G.options_on_enter

		return true
	end

	-- MOD SETTINGS: replace the pause menu's own option list instead of pushing a new page
	local function build_mod_options(main)
		local opts = {}

		local function add(group)
			-- the pause menu uses a row height of 30; with this many rows tighten it so the last row stays on screen
			if group.spacing == nil then
				group.spacing = -5
			end

			opts[#opts + 1] = group

			if group.name then
				opts[group.name] = group
			end
		end

		-- the QoL group only shows when QoL is installed; none of these 13 keys is read in vanilla
		local has_qol = false

		pcall(function()
			local info = rawget(_G, "QOL_GAME_INFORMATION")

			has_qol = type(info) == "string" and #info > 0
		end)

		if has_qol then
			add({
				name = "dh_section_qol",
				dh_header = true
			})

			for _, spec in ipairs(QOL_SPECS) do
				add(build_qol_group(spec))
			end
		end

		add({
			name = "dh_section_dh",
			dh_header = true
		})
		add(make_group("dh_front_unlock", "front_unlock"))
		add(make_group("dh_reveal_hidden", "reveal_hidden", false))
		add(make_choice_group("dh_enemy_health", "enemy_health", "off", {
			{ "OFF", "off" },
			{ "HARD", "hard" },
			{ "HELLDIVE", "helldive" }
		}))

		-- HUD ping / recent-sample window
		if type(G.ping_hud_supported) == "function" then
			add(make_group("dh_hud_ping", "hud_ping", false))
			add(make_choice_group("dh_ping_window", "ping_window", 5, {
				{ "3", 3 },
				{ "5", 5 },
				{ "10", 10 }
			}))
		end

		-- optional modules append their own rows
		for _, build in ipairs(G.extensions.options) do
			local ok, row = pcall(build)

			if ok and type(row) == "table" then
				add(row)
			end
		end

		add({})
		add({
			name = "options_apply_changes",
			buttons = {
				"menu_back_button",
				"menu_campaign_select"
			},
			on_pressed = function()
				pcall(function()
					pcall(write_qol_settings, main)
					pcall(read_ours, main)
					Application.save_user_settings()
				end)

				local current_name = main.options and main.options[main.selected_option] and main.options[main.selected_option].name

				main.options = build_mod_options(main)

				local index = 1

				if current_name then
					for i, item in ipairs(main.options) do
						if item.name == current_name then
							index = i

							break
						end
					end
				end

				main.selected_option = index
			end
		})

		return opts
	end

	-- the cursor cache must be cleared when swapping lists or leaving the page:
	-- otherwise update_selected_option_cursor writes a mod-page row index back into the short list and errors
	local function clear_cursor(main)
		local field = main.selected_option_field_name_cursor

		if type(field) == "string" then
			main[field] = nil
		end

		main.cursor_moved = nil
		main.cursor_selection_direction = nil
	end

	local function mod_enter(main)
		main.dh_saved_options = main.options
		main.dh_saved_selected = main.selected_option
		main.dh_mod_page = true
		main.options = build_mod_options(main)
		main.selected_option = 1

		for i, item in ipairs(main.options) do
			if item.name and not item.dh_header then
				main.selected_option = i

				break
			end
		end

		clear_cursor(main)
	end

	local function mod_exit(main)
		main.dh_mod_page = nil
		main.options = main.dh_saved_options or main.options
		main.dh_saved_options = nil
		main.selected_option = main.dh_saved_selected or 1

		if main.selected_option > #main.options then
			main.selected_option = #main.options
		elseif main.selected_option < 1 then
			main.selected_option = 1
		end

		clear_cursor(main)
	end

	local function mod_move(main, direction)
		local guard = 0

		while guard < 128 do
			main.selected_option = main.selected_option + direction

			if main.selected_option > #main.options then
				main.selected_option = 1
			elseif main.selected_option < 1 then
				main.selected_option = #main.options
			end

			local item = main.options[main.selected_option]

			if item and item.name and not item.dh_header then
				return
			end

			guard = guard + 1
		end
	end

	local function hook_title()
		local base = rawget(_G, "MenuScreenBase")

		if type(base) ~= "table" or type(base.draw_title) ~= "function" then
			return false
		end

		if base.draw_title == G.draw_title then
			return true
		end

		local orig = base.draw_title

		G.draw_title = function(self, gui, dt, text)
			if self and self.dh_mod_page then
				return orig(self, gui, dt, MOD_TITLE)
			end

			return orig(self, gui, dt, text)
		end
		base.draw_title = G.draw_title

		return true
	end

	local function hook_settings_menu()
		local cls = rawget(_G, "MenuScreenMain")
		local base = rawget(_G, "MenuScreenBase")

		if type(cls) ~= "table" or type(cls.on_enter) ~= "function" or type(cls.handle_input) ~= "function" then
			return false
		end

		if cls.handle_input == G.main_handle then
			return true
		end

		local orig_on_enter = cls.on_enter
		local orig_handle = cls.handle_input

		G.main_on_enter = function(self, ...)
			local result = orig_on_enter(self, ...)

			pcall(function()
				-- every fresh entry lands on the normal list, so a page left half-open cannot leak through
				self.dh_mod_page = nil
				self.dh_saved_options = nil
				self.dh_saved_selected = nil

				clear_cursor(self)

				local opts = self.options

				if type(opts) ~= "table" then
					return
				end

				for _, item in ipairs(opts) do
					if item.name == "mod_settings" then
						return
					end
				end

				for i, item in ipairs(opts) do
					if item.name == "menu_settings" then
						table.insert(opts, i + 1, {
							name = "mod_settings"
						})

						return
					end
				end

				opts[#opts + 1] = {
					name = "mod_settings"
				}
			end)

			return result
		end
		cls.on_enter = G.main_on_enter

		-- convert raw game input into menu actions (the pause menu hands us game input, so reading select fails)
		local function to_menu_input(self, input)
			local converted = input

			pcall(function()
				converted = base.get_user_inputs(self, input)
			end)

			if type(converted) ~= "table" then
				converted = input
			end

			return converted
		end

		-- MOD SETTINGS input; the caller wraps this in pcall and falls back to the normal menu instead of erroring
		local function mod_input(self, menu_input)
			local item = self.options[self.selected_option]

			if menu_input.back or base.was_text_button_clicked(self, menu_input, "back") then
				self:play_sound_back(nil, self.user_pad_number)
				mod_exit(self)
			elseif menu_input.up then
				self:play_sound_scroll(nil, self.user_pad_number)
				mod_move(self, -1)
			elseif menu_input.down then
				self:play_sound_scroll(nil, self.user_pad_number)
				mod_move(self, 1)
			elseif menu_input.left then
				if item and item.options then
					self:update_option_selection(item, -1)
					self:play_sound_scroll(nil, self.user_pad_number)
				end
			elseif menu_input.right then
				if item and item.options then
					self:update_option_selection(item, 1)
					self:play_sound_scroll(nil, self.user_pad_number)
				end
			elseif item and item.options and menu_input.select_mouse and self.cursor_selection_direction then
				-- clicking the left / right arrows also changes the value
				if base.was_option_selected(self, menu_input, nil, "select_mouse") then
					self:update_option_selection(item, self.cursor_selection_direction)
					self:play_sound_scroll(nil, self.user_pad_number)
				end
			elseif item and item.on_pressed then
				if base.was_option_selected(self, menu_input) or base.was_option_selected(self, menu_input, nil, "select_mouse") then
					self:play_sound_accept(nil, self.user_pad_number)
					item.on_pressed()
				end
			end

			self.cursor_selection_direction = nil

			pcall(base.reset_clickable_buttons, self)
		end

		G.main_handle = function(self, input, ...)
			if type(base) ~= "table" or type(input) ~= "table" then
				return orig_handle(self, input, ...)
			end

			if self.init_frame then
				return orig_handle(self, input, ...)
			end

			local menu_input = to_menu_input(self, input)

			-- refresh the mouse position for this frame first, otherwise hit tests use last frame's coordinates
			pcall(base.handle_input_cursor, self, menu_input)

			if self.dh_mod_page then
				local ok = pcall(mod_input, self, menu_input)

				if not ok then
					pcall(mod_exit, self)
				end

				return
			end

			local blocked = false

			pcall(function()
				blocked = self.state_stack and #self.state_stack > 0
			end)

			if not blocked then
				pcall(function()
					blocked = self.dropdown_menu and self.dropdown_menu:is_active(menu_input)
				end)
			end

			local open = false

			if not blocked then
				pcall(function()
					local item = self.options and self.options[self.selected_option]

					if item and item.name == "mod_settings" then
						if base.was_option_selected(self, menu_input) or base.was_option_selected(self, menu_input, nil, "select_mouse") then
							open = true
						end
					end
				end)
			end

			if open then
				pcall(function()
					mod_enter(self)
					self:play_sound_accept(nil, self.user_pad_number)
				end)

				return
			end

			return orig_handle(self, input, ...)
		end
		cls.handle_input = G.main_handle

		return true
	end

	local function draw_version(self, with_qol)
		local gui = self.gui_manager

		if type(gui) ~= "table" or type(gui.begin_layout) ~= "function" or type(gui.draw_text) ~= "function" then
			return
		end

		local fonts = rawget(_G, "FontSettings")

		if type(fonts) ~= "table" or type(fonts.fonts) ~= "table" or not fonts.fonts.body_large then
			return
		end

		local font = fonts.fonts.body_large
		local y = with_qol and -font.font_size * 2 or -font.font_size

		gui:begin_layout(Vector3(96, -54, 0), nil, "left", "top")
		gui:begin_template({
			to_upper_case = false,
			color = Color(255, 255, 255, 255),
			font_name = font.class,
			font_size = font.font_size,
			anchor = Vector2(0, 0)
		})
		gui:draw_text(VERSION, Vector3(0, y, 1))
		gui:end_template()
		gui:end_layout()
	end

	local function hook_mainmenu()
		local cls = rawget(_G, "StateMainMenu")

		if type(cls) ~= "table" or type(cls.update) ~= "function" then
			return false
		end

		if cls.update == G.mainmenu_update then
			return true
		end

		local orig = cls.update

		G.mainmenu_update = function(self, ...)
			local qol = rawget(_G, "QOL_GAME_INFORMATION")
			local has_qol = type(qol) == "string" and #qol > 0
			local result = orig(self, ...)

			pcall(draw_version, self, has_qol)

			return result
		end
		cls.update = G.mainmenu_update

		return true
	end

	-- the MOD SETTINGS page must not draw the pause menu's "SQUAD MEMBER" header and red strip
	-- vanilla MenuScreenMain.update draws both for any instance whose state_name ~= "main_menu",
	-- so the page pretends to be the main menu while it is open
	local function hook_mod_update()
		local cls = rawget(_G, "MenuScreenMain")

		if type(cls) ~= "table" or type(cls.update) ~= "function" then
			return false
		end

		if cls.update == G.main_update then
			return true
		end

		local orig = cls.update

		G.main_update = function(self, ...)
			if type(self) == "table" and self.dh_mod_page then
				local saved = self.state_name

				self.state_name = "main_menu"

				local ok, err = pcall(orig, self, ...)

				self.state_name = saved

				if not ok then
					error(err, 0)
				end

				return
			end

			return orig(self, ...)
		end
		cls.update = G.main_update

		return true
	end

	-- ---------------------------------------------------------------- per-frame install
	local function tick()
		if not G.hooked_campaign then
			G.hooked_campaign = hook_campaign()
		end

		if not G.hooked_save then
			G.hooked_save = hook_save()
		end

		if not G.hooked_recap then
			G.hooked_recap = hook_recap()
		end

		if not G.hooked_level then
			G.hooked_level = hook_level()
		end

		if not G.hooked_health then
			G.hooked_health = hook_health()
		end

		if not G.hooked_loc then
			G.hooked_loc = hook_loc()
		end

		if not G.hooked_graphics then
			G.hooked_graphics = hook_graphics()
		end

		if not G.hooked_options then
			G.hooked_options = hook_options()
		end

		if not G.hooked_title then
			G.hooked_title = hook_title()
		end

		if not G.hooked_settings_menu then
			G.hooked_settings_menu = hook_settings_menu()
		end

		if not G.hooked_mod_update then
			G.hooked_mod_update = hook_mod_update()
		end

		if not G.hooked_gm then
			G.hooked_gm = hook_guimanager()
		end

		if not G.hooked_mainmenu then
			G.hooked_mainmenu = hook_mainmenu()
		end

		-- optional modules appended to this file get a per-frame tick
		for _, fn in ipairs(G.extensions.tick) do
			pcall(fn)
		end

		-- HUD ping / ping window / friends refresh (both editions)
		if type(G.ping_hud_tick) == "function" then
			pcall(G.ping_hud_tick)
		end
	end

	pcall(tick)

	local wm = rawget(_G, "WorldManager")

	if not G.wm_hooked and type(wm) == "table" and type(wm.update) == "function" then
		G.wm_hooked = true

		local orig = wm.update

		wm.update = function(self, dt, ...)
			local ok, err = pcall(tick)

			if not ok then
				G.errors = (G.errors or 0) + 1
				G.last_error = err
			end

			return orig(self, dt, ...)
		end
	end
end
