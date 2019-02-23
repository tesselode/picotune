pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
-- utilities

-- string utilities
local function get_cart_name(filename)
	for pos = 1, #filename - 2 do
		if sub(filename, pos, pos + 2) == '.p8' then
			return sub(filename, 1, pos - 1)
		end
	end
	return filename
end

local function clip_text(text)
	if #text > 16 then
		return sub(text, 1, 13) .. '...'
	end
	return text
end

-- audio utilities
local function is_pattern_empty(pattern_index)
	local start_address = 0x3100 + 4 * pattern_index
	for address = start_address, start_address + 3 do
		if band(bnot(peek(address)), 0b01000000) > 0 then
			return false
		end
	end
	return true
end

local function get_pattern_flags(pattern_index)
	local start_address = 0x3100 + 4 * pattern_index
	local is_begin_loop = band(peek(start_address), 0b10000000) > 0
	local is_end_loop = band(peek(start_address + 1), 0b10000000) > 0
	local is_stop = band(peek(start_address + 2), 0b10000000) > 0
	return is_begin_loop, is_end_loop, is_stop
end

local function get_note_volume(sfx, channel, note)
	local note_address = 0x3200 + 68 * sfx + 2 * note
	return band(shr(peek(note_address + 1), 1), 0b00000111)
end

local function get_track_number(tracks, pattern)
	local track_number = 0
	for track_position, _ in pairs(tracks) do
		if pattern >= track_position then
			track_number += 1
		end
	end
	return track_number
end

-- drawing utilities
function print_shadow(text, x, y, color, shadow_color, align)
	align = align or 0
	x -= #text * 4 * align
	print(text, x, y + 1, shadow_color)
	print(text, x, y, color)
end

-- state management
local state = {}

local current_state

local function switch_state(state, ...)
	if current_state and current_state.previous then
		current_state:previous(state, ...)
	end
	current_state = state
	if current_state.enter then
		current_state:enter(state, ...)
	end
end

-->8
-- music playback
local cart_name = ''
local tracks = {}
local is_playing = false

local function load_audio_from_file(filename)
	cart_name = get_cart_name(filename)
	reload(0x3100, 0x3100, 0x11ff, filename)
	tracks = {}
	local in_track = false
	for pattern_index = 0, 63 do
		local is_begin_loop, is_end_loop, is_stop = get_pattern_flags(pattern_index)
		if is_pattern_empty(pattern_index) or is_end_loop or is_stop then
			in_track = false
		elseif not in_track then
			in_track = true
			tracks[pattern_index] = true
		end
	end
end

-->8
-- menu

state.menu = {
	selected = 1,
	oy = 0,
}

function state.menu:enter()
	self.options = {
		{
			text = 'now playing...',
			confirm = function()
				switch_state(state.now_playing)
			end,
		},
	}
	for filename in all(dir()) do
		add(self.options, {
			text = get_cart_name(filename),
			confirm = function()
				load_audio_from_file(filename)
				switch_state(state.now_playing)
			end,
		})
	end
end

function state.menu:update()
	if btnp(2) then
		self.selected -= 1
		if self.selected < 1 then
			self.selected = #self.options
		end
	elseif btnp(3) then
		self.selected += 1
		if self.selected > #self.options then
			self.selected = 1
		end
	elseif btnp(4) then
		self.options[self.selected].confirm()
	end

	local target_oy = 8 * (self.selected - 4)
	target_oy = min(target_oy, 8 * #self.options - 62)
	target_oy = max(0, target_oy)
	self.oy += (target_oy - self.oy) / 4
end

function state.menu:draw()
	cls()
	camera(0, self.oy)
	for i = 1, #self.options do
		local y = 8 * (i - 1)
		if i == self.selected then
			rectfill(0, y, 64, y + 8, 1)
		end
		print(self.options[i].text, 1, y + 2, 7)
	end
	camera()
end

-->8
-- now playing screen

state.now_playing = {}

function state.now_playing:enter()
	self.selected_row = 'minimap'
	self.selected_pattern = 0
	self.selected_button = 2

	-- cosmetic
	self.pattern_cursor_blink_phase = 0
	self.pattern_display_oy = {}
	for pattern_index = 0, 63 do
		self.pattern_display_oy[pattern_index] = 0
	end
	self.visualizer_bars = {0, 0, 0, 0}
	self.track_info_text_oy = 0
end

function state.now_playing:update()
	-- switch rows
	if self.selected_row == 'minimap' and btnp(3) then
		self.selected_row = 'controls'
	end
	if self.selected_row == 'controls' and btnp(2) then
		self.selected_row = 'minimap'
	end

	if self.selected_row == 'minimap' then
		-- pattern navigation
		if btnp(0) then
			self.selected_pattern -= 1
			if self.selected_pattern < 0 then
				self.selected_pattern = 63
			end
			self.pattern_cursor_blink_phase = 0
		elseif btnp(1) then
			self.selected_pattern += 1
			if self.selected_pattern > 63 then
				self.selected_pattern = 0
			end
			self.pattern_cursor_blink_phase = 0
		end
	elseif self.selected_row == 'controls' then
		-- player controls
		if btnp(0) then
			self.selected_button = max(1, self.selected_button - 1)
		elseif btnp(1) then
			self.selected_button = min(3, self.selected_button + 1)
		end
	end

	if btnp(4) then
		if self.selected_row == 'minimap' then
		-- start/stop music on minimap
			if is_playing and self.selected_pattern == stat(24) then
				music(-1)
				is_playing = false
			else
				music(self.selected_pattern)
				is_playing = not is_pattern_empty(self.selected_pattern)
			end
		elseif self.selected_row == 'controls' then
			if self.selected_button == 1 then
				-- previous track
				for pattern_index = self.selected_pattern - 1, 0, -1 do
					if tracks[pattern_index] then
						self.selected_pattern = pattern_index
						if is_playing then
							music(self.selected_pattern)
						end
						break
					end
				end
			elseif self.selected_button == 2 then
				-- play/stop button
				if is_playing then
					music(-1)
					is_playing = false
				else
					music(self.selected_pattern)
					is_playing = not is_pattern_empty(self.selected_pattern)
				end
			elseif self.selected_button == 3 then
				-- next track
				for pattern_index = self.selected_pattern + 1, 63 do
					if tracks[pattern_index] then
						self.selected_pattern = pattern_index
						if is_playing then
							music(self.selected_pattern)
						end
						break
					end
				end
			end
		end
	end

	if btnp(5) then
		switch_state(state.menu)
	end

	-- playing pattern animation
	for pattern_index = 0, 63 do
		local target_oy = (is_playing and stat(24) == pattern_index) and -2 or 0
		if self.pattern_display_oy[pattern_index] < target_oy then
			self.pattern_display_oy[pattern_index] += 1/4
		elseif self.pattern_display_oy[pattern_index] > target_oy then
			self.pattern_display_oy[pattern_index] -= 1/4
		end
	end

	-- pattern cursor animation
	self.pattern_cursor_blink_phase += 1/60

	-- bar visualizer
	for channel = 0, 3 do
		local volume = 0
		local sfx = stat(16 + channel)
		local note = stat(20 + channel)
		if sfx ~= -1 and note ~= -1 then
			volume = get_note_volume(sfx, channel, note)
		end
		if volume > self.visualizer_bars[channel + 1] then
			self.visualizer_bars[channel + 1] = volume
		elseif self.visualizer_bars[channel + 1] > volume then
			self.visualizer_bars[channel + 1] -= 1/2
		end
	end

	-- track info text animation
	if sin(time() / 16) <= 0 then
		if self.track_info_text_oy > 0 then
			self.track_info_text_oy -= 1/2
		end
	else
		if self.track_info_text_oy < 8 then
			self.track_info_text_oy += 1/2
		end
	end
end

function state.now_playing:draw()
	cls()

	-- draw music minimap
	for pattern_index = 0, 63 do
		local is_empty = is_pattern_empty(pattern_index)
		local is_begin_loop, is_end_loop, is_stop = get_pattern_flags(pattern_index)
		local color = is_begin_loop and 14
			or is_end_loop and 2
			or is_stop and 8
			or is_empty and 1
			or 13
		local oy = self.pattern_display_oy[pattern_index]
		line(pattern_index, 32 + oy, pattern_index, 40 + oy, color)
	end

	-- draw pattern cursor
	if sin(self.pattern_cursor_blink_phase) < 0 then
		local oy = self.pattern_display_oy[self.selected_pattern]
		local color = self.selected_row == 'minimap' and 7 or 6
		line(self.selected_pattern, 32 + oy, self.selected_pattern, 40 + oy, color)
	end

	-- draw player controls
	if self.selected_row == 'controls' and self.selected_button == 1 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(4, 18, 44)
	if self.selected_row == 'controls' and self.selected_button == 2 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(is_playing and 2 or 1, 28, 44)
	if self.selected_row == 'controls' and self.selected_button == 3 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(3, 38, 44)
	pal()

	-- draw visualizer bars
	for channel = 0, 3 do
		local v = self.visualizer_bars[channel + 1]
		for i = 0, self.visualizer_bars[channel + 1] do
			local y = 28 - 2 * i
			local color = i > 6 and 8
				or i > 4 and 10
				or i > 2 and 11
				or i > 0 and 12
				or 1
			line(16 * channel + 1, y, 16 * channel + 14, y, color)
		end
	end

	-- draw cart name
	local track_number = get_track_number(tracks, stat(24))
	local track_text = is_playing and 'track ' .. track_number or 'stopped'
	clip(0, 53, 64, 8)
	camera(0, self.track_info_text_oy)
	print_shadow(clip_text(cart_name), 32, 54, 6, 1, .5)
	print_shadow(track_text, 32, 62, 6, 1, .5)
	camera()
	clip()
end

-->8
-- main loop

function _init()
	poke(0x5f2c, 3)
	switch_state(state.menu)
end

function _update60()
	current_state:update()
end

function _draw()
	current_state:draw()
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000ee000000eeeee000e00e000000e00e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000eeee0000eeeee000ee0ee0000ee0ee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000eeeeee00eeeee000eeeeee00eeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000eeee2200eeeee000ee2ee2002ee2ee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000ee220000eeeee000e20e200002e02e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000022000000222220002002000000200200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
