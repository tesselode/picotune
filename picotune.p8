pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
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

local function load_audio_from_file(filename)
	reload(0x3100, 0x3100, 0x11ff, filename)
	local tracks = {}
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
	return tracks
end

-->8
-- now playing
local tracks = {}
local is_playing = false
local selected_row = 'minimap'
local selected_pattern = 0
local selected_button = 2

-- cosmetic
local pattern_cursor_blink_phase = 0
local pattern_display_oy = {}
for pattern_index = 0, 63 do
	pattern_display_oy[pattern_index] = 0
end

function _init()
	poke(0x5f2c, 3)
	tracks = load_audio_from_file 'test.p8'
end

function _update60()
	-- switch rows
	if selected_row == 'minimap' and btnp(3) then
		selected_row = 'controls'
	end
	if selected_row == 'controls' and btnp(2) then
		selected_row = 'minimap'
	end

	if selected_row == 'minimap' then
		-- pattern navigation
		if btnp(0) then
			selected_pattern -= 1
			if selected_pattern < 0 then
				selected_pattern = 63
			end
			pattern_cursor_blink_phase = 0
		elseif btnp(1) then
			selected_pattern += 1
			if selected_pattern > 63 then
				selected_pattern = 0
			end
			pattern_cursor_blink_phase = 0
		end
	elseif selected_row == 'controls' then
		-- player controls
		if btnp(0) then
			selected_button = max(1, selected_button - 1)
		elseif btnp(1) then
			selected_button = min(3, selected_button + 1)
		end
	end

	if btnp(4) then
		if selected_row == 'minimap' then
		-- start/stop music on minimap
			if is_playing and selected_pattern == stat(24) then
				music(-1)
				is_playing = false
			else
				music(selected_pattern)
				is_playing = not is_pattern_empty(selected_pattern)
			end
		elseif selected_row == 'controls' then
			if selected_button == 1 then
				-- previous track
				for pattern_index = selected_pattern - 1, 0, -1 do
					if tracks[pattern_index] then
						selected_pattern = pattern_index
						if is_playing then
							music(selected_pattern)
						end
						break
					end
				end
			elseif selected_button == 2 then
				-- play/stop button
				if is_playing then
					music(-1)
					is_playing = false
				else
					music(selected_pattern)
					is_playing = true
				end
			elseif selected_button == 3 then
				-- next track
				for pattern_index = selected_pattern + 1, 63 do
					if tracks[pattern_index] then
						selected_pattern = pattern_index
						if is_playing then
							music(selected_pattern)
						end
						break
					end
				end
			end
		end
	end

	-- playing pattern animation
	for pattern_index = 0, 63 do
		local target_oy = (is_playing and stat(24) == pattern_index) and -2 or 0
		if pattern_display_oy[pattern_index] < target_oy then
			pattern_display_oy[pattern_index] += 1/4
		elseif pattern_display_oy[pattern_index] > target_oy then
			pattern_display_oy[pattern_index] -= 1/4
		end
	end

	-- pattern cursor animation
	pattern_cursor_blink_phase += 1/60
end

function _draw()
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
		local oy = pattern_display_oy[pattern_index]
		line(pattern_index, 32 + oy, pattern_index, 40 + oy, color)
	end

	-- draw pattern cursor
	if sin(pattern_cursor_blink_phase) < 0 then
		local oy = pattern_display_oy[selected_pattern]
		local color = selected_row == 'minimap' and 7 or 6
		line(selected_pattern, 32 + oy, selected_pattern, 40 + oy, color)
	end

	-- draw player controls
	if selected_row == 'controls' and selected_button == 1 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(4, 18, 44)
	if selected_row == 'controls' and selected_button == 2 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(is_playing and 2 or 1, 28, 44)
	if selected_row == 'controls' and selected_button == 3 then
		pal(14, 7)
	else
		pal(14, 14)
	end
	spr(3, 38, 44)
	pal()
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000ee000000eeeee000e00e000000e00e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000eeee0000eeeee000ee0ee0000ee0ee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000eeeeee00eeeee000eeeeee00eeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000770000eeee2200eeeee000ee2ee2002ee2ee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000ee220000eeeee000e20e200002e02e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000022000000222220002002000000200200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
