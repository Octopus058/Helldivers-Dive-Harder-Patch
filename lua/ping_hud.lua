-- Dive Harder Patch: HUD ping + recent-sample ping window + friends list auto refresh
--
-- 1) scheme B: keep the last N raw ping samples per peer and hook get_average_ping to return
--    the mean (the ESC Avg Ping text and the HUD PING both read it, so the numbers agree)
-- 2) HUD: draw "PING: xx.xxms" below each player card; only the local machine is skipped
-- 3) friends list: force one refresh when the FRIENDS filter is entered, so host info shows up
do
	local G = DiveHarderPatch or {}

	DiveHarderPatch = G

	local DEFAULT_WINDOW = 5

	local function read_setting(key, default)
		local ok, value = pcall(function()
			return Application.user_setting("diveharder", key)
		end)

		if ok and value ~= nil then
			return value
		end

		return default
	end

	-- diagnostic switches (diveharder section of user_settings.config, applied on restart):
	--   ping_hud_off = true       disables the whole module
	--   ping_sample_off = true    stops ping sampling only (falls back to the vanilla median)
	--   friends_fix_off = true    stops the friends auto refresh only
	local function flag_off(key)
		return read_setting(key, false) == true
	end

	local function hud_on()
		return read_setting("hud_ping", false) == true
	end

	local function window_size()
		local value = tonumber(read_setting("ping_window", DEFAULT_WINDOW))

		if value == 3 or value == 5 or value == 10 then
			return value
		end

		return DEFAULT_WINDOW
	end

	-- peer -> last N raw ping samples (seconds)
	local samples = {}

	local function push_sample(peer, value)
		local ring = samples[peer]

		if type(ring) ~= "table" then
			ring = {}
			samples[peer] = ring
		end

		ring[#ring + 1] = value

		local limit = window_size()

		while #ring > limit do
			table.remove(ring, 1)
		end
	end

	-- only sample peers that are already in the game session;
	-- never call Network.ping() on lobby members: a peer without a connection can crash the engine
	local function peer_list(self)
		local list = {}
		local seen = {}

		local ok, peers = pcall(function()
			return self.session:peers()
		end)

		if ok and type(peers) == "table" then
			for _, peer in ipairs(peers) do
				if peer ~= nil and not seen[peer] then
					seen[peer] = true
					list[#list + 1] = peer
				end
			end
		end

		return list
	end

	local function sample_peers(self)
		for _, peer in ipairs(peer_list(self)) do
			local ok, value = pcall(function()
				return Network.ping(peer)
			end)

			if ok and type(value) == "number" then
				push_sample(peer, value)
			end
		end
	end

	local function average_for(peer)
		local ring = samples[peer]

		if type(ring) ~= "table" or #ring == 0 then
			return nil
		end

		local count = math.min(#ring, window_size())
		local sum = 0

		for i = #ring - count + 1, #ring do
			sum = sum + ring[i]
		end

		return sum / count
	end

	-- scheme B: mean of the last N samples; fall back to the original function when there is none
	local function hook_ping()
		local cls = rawget(_G, "NetworkSessionHandler")

		if type(cls) ~= "table" or type(cls.get_average_ping) ~= "function" then
			return false
		end

		if cls.get_average_ping == G.ping_get then
			return true
		end

		local orig_update = cls.update_pings
		local orig_get = cls.get_average_ping
		local orig_set = cls.set_calculate_ping

		if type(orig_update) == "function" then
			cls.update_pings = function(self, ...)
				local result = orig_update(self, ...)

				pcall(sample_peers, self)

				return result
			end

			G.ping_update = cls.update_pings
		end

		cls.get_average_ping = function(self, peer)
			local average = average_for(peer)

			if average then
				return average
			end

			return orig_get(self, peer)
		end
		G.ping_get = cls.get_average_ping

		if type(orig_set) == "function" then
			cls.set_calculate_ping = function(self, ...)
				samples = {}

				return orig_set(self, ...)
			end
			G.ping_set = cls.set_calculate_ping
		end

		return true
	end

	local function current_state()
		local ok, state = pcall(function()
			return Boot.state_machine:get_current_state()
		end)

		if ok then
			return state
		end

		return nil
	end

	local function network_handler()
		local state = current_state()

		if type(state) == "table" and type(state.network_session_handler) == "table" then
			return state.network_session_handler
		end

		return nil
	end

	local function is_owned(player_go)
		local ok, owned = pcall(function()
			return player_go:owned()
		end)

		return ok and owned
	end

	local function draw_ping(self, index, info)
		if not hud_on() then
			return
		end

		-- mission only; not drawn on the ship (state_name == "menu")
		if self.state_name == "menu" then
			return
		end

		if type(self.hud_info) ~= "table" or type(self.hud_info[index]) ~= "table" then
			return
		end

		local player_go = info and info.player_go

		if type(player_go) ~= "table" then
			return
		end

		-- only skip players on the local machine (host itself / split screen); every client is drawn
		if is_owned(player_go) then
			return
		end

		local handler = network_handler()

		if type(handler) ~= "table" then
			return
		end

		local function owner_of(go)
			local ok, owner = pcall(function()
				return go:owner()
			end)

			if ok then
				return owner
			end

			return nil
		end

		local owner = owner_of(player_go)

		-- some player_go values have no owner; fall back to the avatar unit's owner
		if owner == nil and type(info) == "table" then
			local ok, unit = pcall(function()
				return player_go:get("avatar_unit")
			end)

			if ok and unit ~= nil then
				local ok2, unit_owner = pcall(function()
					return EntityAux.owner(unit)
				end)

				if ok2 then
					owner = unit_owner
				end
			end
		end

		if owner == nil then
			return
		end

		local ping = average_for(owner)

		if ping == nil then
			local ok, value = pcall(function()
				return handler:get_average_ping(owner)
			end)

			if ok and type(value) == "number" then
				ping = value
			end
		end

		if type(ping) ~= "number" or ping <= 0 then
			return
		end

		local gui = self.hd_gui

		if type(gui) ~= "table" or type(gui.text) ~= "function" or type(gui.move) ~= "function" then
			return
		end

		local ok3, base = pcall(function()
			return self:get_player_hud_pos(index)
		end)

		if not ok3 or base == nil then
			return
		end

		-- Network.ping() returns seconds (RTT); x1000 gives the standard ms figure
		local text = string.format("PING: %.2fms", ping * 1000)

		-- below the card edge (the card owns 0..current_height, so negative y goes below it), left aligned
		local row_y = -18
		local row_x = 4

		pcall(function()
			gui:move(Vector3(base.x, base.y, 0))
			gui:set_current_font("body")
			gui:text(text, Vector3(row_x, row_y, 4), Color(255, 240, 210, 160))
			gui:set_current_font("body_large")
		end)
	end

	-- "Avg Ping: xx.xxms" in the ESC player list is *0.5*1000 (half RTT);
	-- double the number in GuiManager.draw_text so it matches the HUD's RTT
	local function hook_esc_text()
		local cls = rawget(_G, "GuiManager")

		if type(cls) ~= "table" or type(cls.draw_text) ~= "function" then
			return false
		end

		if cls.draw_text == G.esc_draw then
			return true
		end

		local orig = cls.draw_text
		local prefix = "Avg Ping: "

		G.esc_draw = function(self, text, ...)
			if type(text) == "string" and text:sub(1, #prefix) == prefix then
				local number = text:match("^Avg Ping: (%-?%d+%.?%d*)ms$")
				local value = number and tonumber(number)

				if value then
					return orig(self, string.format("Avg Ping: %.2fms", value * 2), ...)
				end
			end

			return orig(self, text, ...)
		end
		cls.draw_text = G.esc_draw

		return true
	end

	local function hook_hud()
		local cls = rawget(_G, "Hud")

		if type(cls) ~= "table" or type(cls.draw_hud) ~= "function" then
			return false
		end

		if cls.draw_hud == G.hud_draw then
			return true
		end

		local orig = cls.draw_hud

		-- draw_hud takes 11 arguments besides self and that list changes between versions, so forward ...
		G.hud_draw = function(self, ...)
			local count = select("#", ...)
			local args = { ... }
			local result = orig(self, unpack(args, 1, count))

			pcall(draw_ping, self, args[4], args[9])

			return result
		end
		cls.draw_hud = G.hud_draw

		return true
	end

	-- friends list: make refresh_timer expire as soon as the FRIENDS filter is entered, running the vanilla refresh
	local function hook_friends()
		local cls = rawget(_G, "MenuScreenCampaignMultiplayer")

		if type(cls) ~= "table" or type(cls.update) ~= "function" then
			return false
		end

		if cls.update == G.friends_update then
			return true
		end

		local orig = cls.update

		G.friends_update = function(self, ...)
			local result = orig(self, ...)

			pcall(function()
				local filter = self.filter

				if type(filter) == "table" and filter.name == "friends" then
					if not self.dh_friends_refreshed then
						self.dh_friends_refreshed = true

						if type(self.refresh_timer) == "number" then
							self.refresh_timer = -1
						end
					end
				else
					self.dh_friends_refreshed = nil
				end
			end)

			return result
		end
		cls.update = G.friends_update

		return true
	end

	function G.ping_hud_supported()
		return true
	end

	function G.ping_hud_tick()
		if flag_off("ping_hud_off") then
			return
		end

		if not flag_off("ping_sample_off") and not G.hooked_ping then
			G.hooked_ping = hook_ping()
		end

		if not G.hooked_hud then
			G.hooked_hud = hook_hud()
		end

		if not G.hooked_esc then
			G.hooked_esc = hook_esc_text()
		end

		if not flag_off("friends_fix_off") and not G.hooked_friends then
			G.hooked_friends = hook_friends()
		end
	end
end
