pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
local function load_audio_from_file(filename)
	reload(0x3100, 0x3100, 0x11ff, filename)
end

function _init()
	poke(0x5f2c, 3)
	load_audio_from_file 'test.p8'
	music(0)
end

function _update60()
end

function _draw()
	cls()
	print(stat(24), 0, 0, 7)
	print(stat(26), 0, 8, 7)
end
