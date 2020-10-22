local ADDON, Addon = ...
Addon.Cooldowns = {
	['spell']={},
	['item']={}
}
Addon.Casts = {}
Addon.Frames = {
	['spell']={},
	['item']={}
}
Addon.TimeMarks = {}
Addon.UI_Initialized = false

-- /console scriptErrors 1

local _G = getfenv(0)
local L = Addon.translations

-- spell and inventory functions
local GetSpellCooldown = _G.GetSpellCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetContainerItemCooldown = _G.GetContainerItemCooldown
local GetContainerItemLink = _G.GetContainerItemLink
local GetContainerNumSlots = _G.GetContainerNumSlots
local GetSpellInfo = _G.GetSpellInfo
local GetItemInfo = _G.GetItemInfo

-- util functions
local GetTime = _G.GetTime
local pairs = _G.pairs
local ipairs = _G.ipairs
local floor = _G.math.floor

-- slash commands
function Addon:Slash_lock()
	CooldownTimerDb.bar.locked = not CooldownTimerDb.bar.locked
	if CooldownTimerDb.bar.locked == false then
		self.Utils:Log('unlocked, you can freely move bar')
	else
		self.Utils:Log('locked')
	end
end

function Addon:Slash_reset()
	self.Utils:Log('saving factory settings')
	CooldownTimerDb = self.defaults
	self.frame:ClearAllPoints()
	self.frame:SetPoint("CENTER", UIParent, "CENTER", CooldownTimerDb.bar.x, CooldownTimerDb.bar.y)
end

function Addon:Slash_toggle()
	CooldownTimerDb.bar.visible = not CooldownTimerDb.bar.visible
	if CooldownTimerDb.bar.visible then self.frame:Show() else self.frame:Hide() end
end

function Addon:Slash_debug()
	CooldownTimerDb.debug = not CooldownTimerDb.debug
	self.Utils:Log('debug state:'..(CooldownTimerDb.debug and 'true' or 'false'))
end

function Addon:PrintHelp()
	self.Utils:Log('Usage: /ct <command>')
	self.Utils:LogRaw(' Commands:')
	self.Utils:LogRaw('  debug => toggle debug messages')
	self.Utils:LogRaw('  lock => lock/unlock bar position')
	self.Utils:LogRaw('  reset => reset bar position and settings')
	self.Utils:LogRaw('  toggle => show/hide bar')
end

-- entry point
function Addon:OnLoad()
	local frame = CreateFrame("Frame", nil, UIParent)

	frame:RegisterEvent('ADDON_LOADED')
	frame:RegisterEvent('PLAYER_ENTERING_WORLD')
	frame:RegisterEvent('BAG_UPDATE_COOLDOWN')
	frame:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED')
	frame:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	frame:RegisterEvent('PLAYER_LOGIN')

	self.frame = frame
	frame:SetScript("OnEvent", function(_, event, ...)
		local func = self[event]
		if type(func) == 'function' then
			return func(self, event, ...)
		end
	end)
	
	frame:SetScript('OnMouseDown', function(self)
		if not CooldownTimerDb.bar.locked then
			self:StartMoving()
		end
 	end)
	
	frame:SetScript('OnMouseUp', function (self, button)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		local ox, oy = UIParent:GetCenter()
		CooldownTimerDb.bar.x = (x - ox)
		CooldownTimerDb.bar.y = (y - oy)
	end)

	-- setup slash commands
    _G[('SLASH_%s1'):format(ADDON)] = ('/%s'):format(ADDON:lower())
    _G[('SLASH_%s2'):format(ADDON)] = '/ct'
	
	SlashCmdList[ADDON] = function(arg, ...)
		local args = self.Utils:Split(arg, ' ')
		local cmd = table.remove(args, 1);
		local func = self['Slash_'..cmd:lower()]
		if type(func) == 'function' then
			return func(self, args)
		else 
			self:PrintHelp()
		end
	end
	
	self.OnLoad = nil
end

-- debug hooks
GameTooltip:HookScript("OnTooltipSetSpell", function(self)
	if CooldownTimerDb.debug then 
		local _, id = self:GetSpell()
		if id  then
			self:AddLine("    ")
			self:AddLine("Spell ID: " .. tostring(id), 1, 1, 1)
		end
	end
end)

-- events
function Addon:PLAYER_LOGIN()
	CooldownTimerDb = self.Utils:MigrateSettings(self.defaults, CooldownTimerDb)
end

function Addon:ADDON_LOADED(event, addonName)
	-- this event is called for each loaded addon
    if ADDON ~= addonName then
        return
    end
	
    self.frame:UnregisterEvent(event)
end

function Addon:UNIT_SPELLCAST_SUCCEEDED(event, unitID, skillID, spellID)
	if self.Utils:IsInArray(CooldownTimerDb.blacklisted.spell, spellID) then
		self.Utils:LogDebug('[spell|'..spellId..'] blacklisted')
		return 
	end
	local spellName, _, icon = GetSpellInfo(spellID)
	if not spellName then return end
	if not icon then return end
	
	self.Casts[spellID] = {['icon']=icon, ['spellName']=spellName}
	self.Utils:LogDebug('Spellcast detected: '..spellName..'['..spellID..'|'..icon..']')
end

function Addon:BAG_UPDATE_COOLDOWN(event)
	self:ScanEquiped()
	self:ScanBags()
end

function Addon:SPELL_UPDATE_COOLDOWN(event)
	for spellID, data in pairs(self.Casts) do
		if self.Utils:IsInArray(CooldownTimerDb.blacklisted.spell, spellID) then 
			self.Utils:LogDebug('[spell|'..spellID..'] blacklisted')
		else
			local _, duration = GetSpellCooldown(spellID)
			self.Utils:LogDebug('[spell|'..spellID..'] cooldown for spellID:'..spellID..' duration:'..duration)
			if not duration then break end
			
			if duration > 2 then
				self.Casts[spellID] = nil
				if CooldownTimerDb.spellDb[spellID] == nil then
					CooldownTimerDb.spellDb[spellID] = {['spellName']=data.spellName}
				end
				self:InsertNewCooldown(spellID, 'spell', data.icon, data.spellName, duration)
			end
		end
	end
end

function Addon:PLAYER_ENTERING_WORLD(event)
	if self.UI_Initialized then return end
	
	self.frame:SetFrameStrata('LOW')
	self.frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		insets = {left = 2, top = 2, right = 2, bottom = 2},
		edgeSize = 8, tile = false
	})
	self.frame:SetBackdropColor(0,0,0,1)
	self.frame:ClearAllPoints()
	self.frame:SetWidth(CooldownTimerDb.bar.width)
	self.frame:SetHeight(CooldownTimerDb.bar.height)
	self.frame:SetPoint("CENTER", UIParent, "CENTER", CooldownTimerDb.bar.x, CooldownTimerDb.bar.y)
	self.frame:EnableMouse(true)
	self.frame:SetMovable(true)
	self.frame:SetResizable(true)
	self.frame:SetMinResize(128,24)
	if CooldownTimerDb.bar.visible then self.frame:Show() end
	local stampsCount = getn(CooldownTimerDb.bar.marks.list)
	for idx,m in ipairs(CooldownTimerDb.bar.marks.list) do
		local markFrame = self:CreateTimeMark(m, stampsCount, idx)
		if markFrame ~= nil then
			tinsert(self.TimeMarks, markFrame)
		end
	end
	
	self.UI_Initialized = true
	self:ScanAndRestore()
	self.Utils:Log(L.MSG_INITIALIZED)
end

-- internals
function Addon:InsertNewCooldown(id, type, icon, name, duration)
	if self.Cooldowns[type][id] == nil or self.Cooldowns[type][id].initialized == false then
		self.Utils:LogDebug('['..type..'|'..id..'] Creating new Cooldown for '..name..'[icon:'..icon..'|duration:'..duration..'sec]')
		self.Cooldowns[type][id] = {['icon'] = icon, ['name'] = name, ['duration'] = duration, ['initialized'] = false}
		self.Frames[type][id] = self:CreateNewCooldownFrame(id, type)
	elseif self.Cooldowns[type][id].duration ~= duration then
		self.Frames[type][id]:Hide()
		self.Frames[type][id] = nil
		self.Cooldowns[type][id] = {['icon'] = icon, ['name'] = name, ['duration'] = duration, ['initialized'] = false}
		self.Frames[type][id] = self:CreateNewCooldownFrame(id, type)
	else
		self.Utils:LogDebug('['..type..'|'..id..'] Restarting Cooldown for '..name..'[icon:'..icon..'|duration:'..duration..'sec]')
		self:RestartCooldown(id, type)
	end
end

function Addon:CreateTimeMark(time, total, idx)
	local isFirst, isLast = idx == 1, idx == total
	local mark = self.frame:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
	
	mark.barWidth = self.frame:GetWidth() / (total-1)
	mark.left = isFirst and 5 or (mark.barWidth*(idx-1))
	mark.isFirst = isFirst
	mark.isLast = isLast
	mark.time = time
	
	self.Utils:LogDebug('Mark F:'..(isFirst and 1 or 0)..' L:'..(isLast and 1 or 0)..' idx:'..idx..' all:'..total..' left:'..mark.left)
	mark:SetParent(self.frame)
	if (isFirst and CooldownTimerDb.bar.marks.showFirst) or (isLast and CooldownTimerDb.bar.marks.showLast) or ((not isFirst) and (not isLast)) then 
		mark:Show()
	else
		mark:Hide()
	end
	local origin = isFirst and "LEFT" or (isLast and "RIGHT" or "CENTER")
	local related = isLast and "RIGHT" or "LEFT"
	mark:SetPoint(origin, self.frame, related, isLast and 0 or mark.left, 0)
		
	if time > 60 then
		local minutes = format("%01.f", floor(time/60))
		local seconds = format("%02.f", floor(time - minutes *60))
		mark:SetText(minutes..':'..seconds)
	else
		mark:SetText(time..'sec')
	end
	
	if (not isFirst) and (not isLast) then
		local topLine = self.frame:CreateTexture()
		topLine:SetColorTexture(1,1,1,.35)
		topLine:SetPoint("CENTER", mark, origin, 0, 0)
		topLine:SetSize(1, self.frame:GetHeight() *.8)
	end
	
	return mark
end

function Addon:CreateNewCooldownFrame(id, type)
	local f = CreateFrame("Frame", nil, self.frame)
	f.id = id
	f.type = type
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetTexture(self.Cooldowns[type][id].icon)
	f.tex:SetTexCoord(0.09, 0.91, 0.09, 0.91)
	f.tex:ClearAllPoints()
	f.tex:SetWidth(CooldownTimerDb.bar.height-4)
	f.tex:SetHeight(CooldownTimerDb.bar.height-4)
	
	f:SetParent(self.frame)
	f:ClearAllPoints()
	f:SetWidth(CooldownTimerDb.bar.height-4)
	f:SetHeight(CooldownTimerDb.bar.height-4)
	f:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
	f:Show()
	
	f.anim = f:CreateAnimationGroup()
	local markCount = getn(self.TimeMarks)
	local animId, totalLeft = 1, 0
	local cd = self.Cooldowns[type][id]
	if cd.duration > self.TimeMarks[markCount].time then
		local waitDuration = cd.duration - self.TimeMarks[markCount].time
		f.anim[animId] = f.anim:CreateAnimation("Alpha")
		f.anim[animId]:SetFromAlpha(0.25)
		f.anim[animId]:SetToAlpha(1)
		f.anim[animId]:SetDuration(waitDuration)
		f.anim[animId]:SetOrder(animId)
		self.Utils:LogDebug('['..type..'|'..id..'] more than maximum, need to wait '..waitDuration..' seconds')
		animId = animId+1
	end
	for	idx=markCount,2,-1 do
		local m1, m2 = self.TimeMarks[idx], self.TimeMarks[idx-1]
		local isFirst = m2.isFirst
		local timeTo, timeFrom, leftTo, leftFrom, barWidth = m1.time, m2 == nil and 0 or m2.time, m1.left, m2 == nil and 0 or m2.left, m1.barWidth
		if cd.duration > timeFrom and cd.duration <= timeTo then
			local segmentDuration = cd.duration - timeFrom
			local segmentOffset = (segmentDuration / (timeTo-timeFrom)) * barWidth
			
			f.anim[animId] = f.anim:CreateAnimation("Translation")
			local finalOffset = -segmentOffset + (isFirst and 4 or 0)
			f.anim[animId]:SetOffset(finalOffset, 0)
			f.anim[animId]:SetOrder(animId)
			f.anim[animId]:SetDuration(segmentDuration)
			animId = animId+1
			totalLeft = totalLeft+segmentOffset
			self.Utils:LogDebug('['..type..'|'..id..'] starting segment offset:'..segmentOffset..' duration:'..segmentDuration)
		elseif cd.duration > timeFrom and cd.duration > timeTo then
			f.anim[animId] = f.anim:CreateAnimation("Translation")
			f.anim[animId]:SetOffset(-barWidth + (isFirst and 4 or 0), 0)
			f.anim[animId]:SetOrder(animId)
			f.anim[animId]:SetDuration(timeTo-timeFrom)
			animId = animId+1
			totalLeft = totalLeft+barWidth
			self.Utils:LogDebug('['..type..'|'..id..'] full segment width:'..barWidth..' duration:'..(timeTo-timeFrom))
		end
	end
	f.totalLeft = totalLeft
	f.tex:SetPoint("LEFT", f, "LEFT", totalLeft, 0)
	f.pulse = f:CreateAnimationGroup()
	f.pulse[1] = f.pulse:CreateAnimation("Scale")
	f.pulse[1]:SetFromScale(1, 1)
	f.pulse[1]:SetToScale(3, 3)
	f.pulse[1]:SetDuration(0.25)
	f.pulse[1]:SetOrigin("LEFT", 4, 0)
	
	f.fade = f:CreateAnimationGroup()
	f.fade[1] = f.fade:CreateAnimation("Alpha")
	f.fade[1]:SetFromAlpha(1)
	f.fade[1]:SetToAlpha(0)
	f.fade[1]:SetDuration(0.25)
	
	f.anim:SetScript("OnFinished", function(self, requested)
		if not requested then
			f.tex:SetPoint("LEFT", f, "LEFT", 4, 0)
			f.fade:Play()
			f.pulse:Play()
		end
	end)
	f.pulse:SetScript("OnFinished", function(self, requested)
		if not requested then
			self.Utils:LogDebug('['..type..'|'..id..'] CD finished')
			f:Hide()
			-- clear saved spellId
			if f.type == 'spell' then CooldownTimerDb.spellDb[f.id] = nil end
		end
	end)
	
	self.Cooldowns[type][id].initialized = true
	f.anim:Play()
	return f
end

function Addon:RestartCooldown(id, type)
	self.Frames[type][id]:Show()
	self.Frames[type][id].tex:SetPoint("LEFT", self.Frames[type][id], "LEFT", self.Frames[type][id].totalLeft, 0)
	if self.Frames[type][id].pulse:IsPlaying() then self.Frames[type][id].pulse:Stop() end
	if self.Frames[type][id].fade:IsPlaying() then self.Frames[type][id].fade:Stop() end
	
	self.Frames[type][id].anim:Restart()
end

function Addon:ScanEquiped()
	for i=1,18 do
		-- GetInventoryItemCooldown will always return full CD -> remaining needs to be calculated
		local start, duration, active = GetInventoryItemCooldown('player', i)
		if active == 1 and start > 0 and duration > 3 then
			local finalDuration = duration - (GetTime() - start)
			local link = GetInventoryItemLink('player', i)
			if link then
				local id = link:match('item:(%d+)')
				local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
				self.Utils:LogDebug('Inventory item: '..name..'['..id..'|'..icon..'] state:['..start..'|'..duration..'|'..GetTime()..']')
				self:InsertNewCooldown(id, 'item', icon, name, finalDuration)
			end
		end
	end
end

function Addon:ScanBags()
	for i=0,4 do
		local slots = GetContainerNumSlots(i)
		for j=1, slots do
			-- GetContainerItemCooldown will always return full CD -> remaining needs to be calculated
			local start, duration, active = GetContainerItemCooldown(i,j)
			if active == 1 and start > 0 and duration > 3 then
				local finalDuration = duration - (GetTime() - start)
				local link = GetContainerItemLink(i,j)
				if link then
					local id = link:match('item:(%d+)')
					local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id)
					self.Utils:LogDebug('Bag item: '..name..'['..id..'|'..icon..'] state:['..start..'|'..duration..'|'..GetTime()..']')
					self:InsertNewCooldown(id, 'item', icon, name, finalDuration)
				end
			end
		end
	end
end

function Addon:ScanAndRestore()
	local now = GetTime()
	local toRemove = {}
	-- spells
	for spellID,_ in pairs(CooldownTimerDb.spellDb) do
		if self.Utils:IsInArray(CooldownTimerDb.blacklisted, spellID) then 
			self.Utils:LogDebug('[spell|'..spellId..'] blacklisted')
		else
			local spellName, _, icon = GetSpellInfo(spellID)
			local startTime, duration, enabled = GetSpellCooldown(spellID)
			if spellName == nil or icon == nil or duration == nil then
				self.Utils:LogDebug('[spell|'..spellId..'] out of date, removing from local DB')
				tinsert(toRemove, spellID)
			end
			local remaining = duration - (now - startTime)
			if enabled == 1 and remaining > 2 then
				self.Utils:LogDebug('[spell|'..spellId..'] restoring running CD with duration:'..remaining)
				self:InsertNewCooldown(spellID, 'spell', icon, spellName, remaining)
			end
		end
	end
	for idx,s in pairs(toRemove) do
		CooldownTimerDb.spellDb[s] = nil
	end
	-- items
	self:ScanEquiped()
	self:ScanBags()
end

Addon:OnLoad()

-- exports
_G[ADDON] = Addon