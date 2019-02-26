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
local function print_shadow(text, x, y, color, shadow_color, align)
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
-- startup sequence

state.startup = {}

function state.startup:enter()
	self.time = 0
end

function state.startup:update()
	self.time += 1
	if self.time == 20 then
		sfx(8)
	end
	if self.time >= 100 then
		switch_state(state.menu)
	end
end

function state.startup:draw()
	cls()
	local width = self.time > 50 and 36
		or self.time > 40 and 6
		or self.time > 30 and 4
		or self.time > 20 and 2
		or 0
	sspr(0, 32, width, 8, 12, 28, width, 8)
end

-->8
-- menu

state.menu = {
	top_bar_height = 8,
	selected = 1,
	oy = -64,
}

function state.menu:enter()
	self.options = {}
	for filename in all(dir()) do
		add(self.options, {
			text = get_cart_name(filename),
			confirm = function()
				if cart_name ~= get_cart_name(filename) then
					load_audio_from_file(filename)
					music(-1)
					is_playing = false
				end
				switch_state(state.now_playing)
			end,
		})
	end

	-- cosmetic
	self.long_text_scroll_phase = 0
end

function state.menu:update()
	if #self.options > 0 then
		-- input
		if btnp(2) then
			self.selected -= 1
			if self.selected < 1 then
				self.selected = #self.options
			end
			self.long_text_scroll_phase = 0
		elseif btnp(3) then
			self.selected += 1
			if self.selected > #self.options then
				self.selected = 1
			end
			self.long_text_scroll_phase = 0
		elseif btnp(4) then
			self.options[self.selected].confirm()
		end

		-- text overflow scrolling
		self.long_text_scroll_phase += 1/60

		-- smooth scrolling
		local target_oy = 8 * (self.selected - 4)
		target_oy = min(target_oy, 8 * #self.options - 62)
		target_oy = max(-self.top_bar_height, target_oy)
		self.oy += (target_oy - self.oy) / 4
		if abs(self.oy - target_oy) < .25 then
			self.oy = target_oy
		end
	end
end

function state.menu:draw()
	cls(0)

	-- draw top bar
	spr(7, 0, 0, 5, 1)
	print_shadow(stat(93) .. ':' .. stat(94), 8, 1, 7, 2)

	if #self.options > 0 then
		-- draw menu options
		print_shadow('🅾️', 48, 1, 12, 1)
		spr(17, 56, 0)
		clip(0, self.top_bar_height, 64, 64)
		camera(0, self.oy)
		for i = 1, #self.options do
			local y = 8 * (i - 1)
			if i == self.selected then
				rectfill(0, y, 64, y + 7, 2)
				local ox = 0
				if #self.options[i].text > 16 then
					local overflow = #self.options[i].text * 4 + 2 - 64
					ox = overflow * (.5 + .49 * sin(self.long_text_scroll_phase / 4 + .25))
				end
				print_shadow(self.options[i].text, 1 - flr(ox), y + 1, 7, 1)
			else
				print(self.options[i].text, 1, y + 2, 7)
			end
		end
		camera()
		clip()
	else
		-- draw help text
		camera(0, -12)
		print_shadow('no music found', 32, 4, 7, 1, .5)
		rectfill(0, 14, 64, 22, 2)
		print_shadow('> folder', 32, 16, 7, 0, .5)
		print_shadow('put carts here!', 32, 28, 7, 1, .5)
		print_shadow('♥', 31, 40 + 2.5 * sin(time() / 4), 14, 2, .5)
		camera()
	end
end

-->8
-- now playing screen

state.now_playing = {}

function state.now_playing:enter()
	self.selected_row = 'controls'
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
			self.selected_button = min(4, self.selected_button + 1)
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
				for pattern_index = stat(24) - 1, 0, -1 do
					if tracks[pattern_index] then
						music(pattern_index)
						is_playing = true
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
				for pattern_index = stat(24) + 1, 63 do
					if tracks[pattern_index] then
						music(pattern_index)
						is_playing = true
						break
					end
				end
			elseif self.selected_button == 4 then
				switch_state(state.visualizer)
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
	spr(4, 2, 44)
	if self.selected_row == 'controls' and self.selected_button == 2 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(is_playing and 2 or 1, 12, 44)
	if self.selected_row == 'controls' and self.selected_button == 3 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(3, 22, 44)
	if self.selected_row == 'controls' and self.selected_button == 4 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(5, 54, 44)
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

	-- top bar
	spr(7, 0, 0, 5, 1)
	print_shadow(stat(93) .. ':' .. stat(94), 8, 1, 7, 2)
	print_shadow('❎', 56, 1, 12, 1)
	spr(17, 47, 0, 1, 1, true)
end

-->8
-- visualizers

local particles_visualizer = {}

function particles_visualizer:start()
	self.planets = {
		{x = 16, y = 16, mass = 1},
		{x = 48, y = 16, mass = 1},
		{x = 48, y = 48, mass = 1},
		{x = 16, y = 48, mass = 1},
	}
	self.particles = {}
	for i = 1, 32 do
		add(self.particles, {x = rnd(64), y = rnd(64), vx = 0, vy = 0})
	end
end

function particles_visualizer:update()
	-- update planet masses
	for channel = 0, 3 do
		local volume = 0
		local sfx = stat(16 + channel)
		local note = stat(20 + channel)
		if sfx ~= -1 and note ~= -1 then
			volume = get_note_volume(sfx, channel, note)
		end
		local planet = self.planets[channel + 1]
		planet.mass += (volume - planet.mass) * .1
		planet.mass = max(volume, planet.mass)
	end

	-- update particles
	for particle in all(self.particles) do
		-- gravity
		for planet in all(self.planets) do
			local dist2 = (planet.x - particle.x) ^ 2 + (planet.y - particle.y) ^ 2
			local force = .01 * planet.mass / dist2
			force = min(force, .1)
			particle.vx += (planet.x - particle.x) * force
			particle.vy += (planet.y - particle.y) * force
		end
		-- apply velocity
		particle.x += particle.vx
		particle.y += particle.vy
		-- bounce off screen edges
		if particle.x < 0 then
			particle.x = 1
			particle.vx *= -1
		end
		if particle.x > 64 then
			particle.x = 63
			particle.vx *= -1
		end
		if particle.y < 0 then
			particle.y = 1
			particle.vy *= -1
		end
		if particle.y > 64 then
			particle.y = 63
			particle.vy *= -1
		end
	end
end

function particles_visualizer:draw()
	cls()
	for planet in all(self.planets) do
		local color = planet.mass > 6 and 7
			or planet.mass > 3 and 6
			or 5
		circfill(planet.x, planet.y, planet.mass + 1, color)
	end
	for p in all(self.particles) do
		local speed2 = p.vx ^ 2 + p.vy ^ 2
		local color = speed2 > 1/10 and 12
			or speed2 > 1/20 and 13
			or speed2 > 1/30 and 2
			or 1
		line(p.x, p.y, p.x - p.vx * 6.5, p.y - p.vy * 6.5, color)
	end
end

state.visualizer = {}

function state.visualizer:enter()
	cls()
	self.visualizer = particles_visualizer
	self.visualizer:start()
end

function state.visualizer:update()
	self.visualizer:update()
	if btnp(5) then
		switch_state(state.now_playing)
	end
end

function state.visualizer:draw()
	self.visualizer:draw()
end

-->8
-- main loop

function _init()
	poke(0x5f2c, 3)
	switch_state(state.startup)
end

function _update60()
	current_state:update()
end

function _draw()
	current_state:draw()
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000ee000000eeeee000e00e000000e00e00000000000000000000b00000000000000000000000000000000000000000000000000000000000000000000
007007000eeee0000eeeee000ee0ee0000ee0ee000e000e000000000000b00000000000000000000000000000000000000000000000000000000000000000000
000770000eeeeee00eeeee000eeeeee00eeeeee00e2e0e2000000000000b0e000000000000000000000000000000000000000000000000000000000000000000
000770000eeee2200eeeee000ee2ee2002ee2ee00202e200000000000c0b0e000000000000000000000000000000000000000000000000000000000000000000
007007000ee220000eeeee000e20e200002e02e000002000000000000c0b0e000000000000000000000000000000000000000000000000000000000000000000
00000000022000000222220002002000000200200000000000000000010302000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000cc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000cccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000111cc100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000c1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b0007770000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b0007270700000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b0007070200000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b0e07770707770777077707070777077700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b0e07220707220727027207070727072700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c0b0e07000707000707007007070707077700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0c0b0e07000707770777007707770707077200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01030202000202220222002202220202022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010700000c0500c0310000018050180310000013050130310000024050280502b0503005030031300110000000000000000000000000000000000000000000000000000000000000000000000000000000000000
