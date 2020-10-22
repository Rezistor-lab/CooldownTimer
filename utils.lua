local ADDON, Addon = ...
local Utils = {}

local L = Addon.translations

-- util functions
local pairs = _G.pairs
local ipairs = _G.ipairs

local Migrations = {
	[0]={next=nil, version='0_3_0'},
	--[2]={next=IDX, version='0_4_0', transform='FromXXXToYYY'}
}

-- Logging
function Utils:Log(msg)
	print('|c0000FF80<'..ADDON..'> '..msg..'|r')
end

function Utils:LogRaw(msg)
	print('|c0000FF80'..msg..'|r')
end

function Utils:LogDebug(msg)
	if CooldownTimerDb ~= nil and CooldownTimerDb.debug == true then Utils:Log(msg) end
end

function Utils:Dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. Utils:Dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

function Utils:Split(str, delimiter)
	local words = {}
	for w in (str .. delimiter):gmatch("([^"..delimiter.."]*)"..delimiter) do 
		table.insert(words, w) 
	end
	return words
end

-- Utils
function Utils:DeepCopy(from)
	local to = {}
	for k,v in pairs(from) do
		if type(v) == "table" then
			to[k] = Utils:DeepCopy(v)
		else
			to[k] = v
		end
	end
	return to
end

function Utils:CopyDefaults(src, dst)
	if type(src) ~= "table" then return {} end
	if dst == nil then dst = {} end
	for k, v in pairs(src) do
		if type(v) == "table" then -- If the value is a sub-table:
			dst[k] = Utils:CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function Utils:IsInArray(tab, val)
    for _, value in ipairs(tab) do
        if value == val then return true end
    end

    return false
end

-- Migrations
function Utils:MigrateSettings(default, stored)
	local storedVersion = stored.version and (stored.version.major..'_'..stored.version.minor..'_'..stored.version.build) or ''
	local defaultVersion = default.version.major..'_'..default.version.minor..'_'..default.version.build
	if storedVersion == defaultVersion then
		Utils:LogDebug('Settings up to date')
		return stored 
	end
	
	while true do
		local nextMig = Migrations:GetNextMigration(storedVersion)
		if nextMig == nil or nextMig.next == nil or Migrations[nextMig.next] == nil or Migrations[nextMig.next].transform == nil then 
			return stored 
		end
		Utils:LogDebug('Migrations settings from version:'..storedVersion..' to:'..Migrations[nextMig.next].version)
		local func = Migrations[Migrations[nextMig.next].transform]
		if type(func) == 'function' then
			stored = func(self, stored)
		end
		storedVersion = Migrations[nextMig.next].version
	end
end

function Migrations:GetNextMigration(fromVersion)
	for _,data in pairs(Migrations) do
		if data.version == fromVersion then return data end
	end
	
	return nil
end

function Migrations:FromNilTo020(prev)
	return {
		version = { major = 0, minor = 2, build = 0 },
		debug = prev.debug,
		bar = Utils:DeepCopy(prev.bar),
		spellDb = Utils:DeepCopy(prev.spellDb),
		blacklisted = {
			spell = prev.blacklisted,
			item = {}
		}
	}
end

function Migrations:From020To030(prev)
	return {
		version = { major = 0, minor = 3, build = 0 },
		debug = prev.debug,
		bar = Utils:DeepCopy(prev.bar),
		spellDb = {},
		blacklisted = Utils:DeepCopy(prev.blacklisted)
	}
end

-- export
Addon.Utils = Utils
Addon.Migrations = Migrations