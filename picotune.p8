pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
local function load_audio_from_file(filename)
	reload(0x3100, 0x3100, 0x11ff, filename)
end

local selected_pattern = 0

-- cosmetic
local pattern_cursor_blink_phase = 0
local pattern_display_oy = {}
for pattern_index = 0, 63 do
	pattern_display_oy[pattern_index] = 0
end

function _init()
	poke(0x5f2c, 3)
	load_audio_from_file 'test.p8'
	music(0)
end

function _update60()
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

	-- playing pattern animation
	for pattern_index = 0, 63 do
		local target_oy = stat(24) == pattern_index and -3 or 0
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
		local is_empty = true

		-- get the starting address of this music pattern in memory
		local start_address = 0x3100 + 4 * pattern_index

		-- check if sfx is enabled in any of the channels
		for address = start_address, start_address + 3 do
			if band(bnot(peek(address)), 0b01000000) > 0 then
				is_empty = false
			end
		end

		-- check for flags
		local is_begin_loop = band(peek(start_address), 0b10000000) > 0
		local is_end_loop = band(peek(start_address + 1), 0b10000000) > 0
		local is_stop = band(peek(start_address + 2), 0b10000000) > 0

		-- draw a line representing the pattern
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
		line(selected_pattern, 32 + oy, selected_pattern, 40 + oy, 7)
	end
end
