local _, Addon = ...
local defaults = {
	version = { major = 0, minor = 3, build = 0 },
	bar = {
		x = 0, y = 0, width = 512, height = 24, locked = false, visible = true,
		marks = {
			showFirst = false, list = {0, 10, 30, 120, 300}, showLast = false
		}
	},
	spellDb = {
		-- spellID list of all spells which CD is longer than 2sec (record is removed after CD expiration)
		-- this is needed because there is more than 20k spell id's which is impossible to scan after each loading
	},
	blacklisted = {
		spell = { -- spellID list of ignored
			8690 --Hearthstone
		},
		item = { -- itemID list of ignored
		}
	},
	['debug'] = false
}

-- export
Addon.defaults = defaults