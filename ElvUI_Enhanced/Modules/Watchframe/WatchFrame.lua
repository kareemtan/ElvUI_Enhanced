local E, L, V, P, G = unpack(ElvUI)
local WF = E:NewModule('Enhanced_WatchFrame', 'AceHook-3.0', 'AceEvent-3.0')

local _G = _G
local ipairs, tonumber = ipairs, tonumber
local strfind, format = strfind, format

local GetQuestIndexForWatch = GetQuestIndexForWatch
local GetQuestLogTitle = GetQuestLogTitle
local GetQuestLogCompletionText = GetQuestLogCompletionText
local GetQuestDifficultyColor = GetQuestDifficultyColor
local IsInInstance, IsResting, UnitAffectingCombat = IsInInstance, IsResting, UnitAffectingCombat
local GetAchievementInfo = GetAchievementInfo
local hooksecurefunc = hooksecurefunc

local WatchFrame = _G.WatchFrame
local WATCHFRAME_LINKBUTTONS = _G.WATCHFRAME_LINKBUTTONS

local statedriver = {
	['NONE'] = function()
		WatchFrame.userCollapsed = false
		WatchFrame_Expand(WatchFrame)
		WatchFrame:Show()
	end,
	['COLLAPSED'] = function()
		WatchFrame.userCollapsed = true
		WatchFrame_Collapse(WatchFrame)
		WatchFrame:Show()
	end,
	['HIDDEN'] = function()
		WatchFrame:Hide()
	end
}

function WF:ChangeState()
	if UnitAffectingCombat('player') then
		WF:RegisterEvent('PLAYER_REGEN_ENABLED', 'ChangeState')
		WF.inCombat = true
		return
	end

	if IsResting() then
		statedriver[WF.db.city](WatchFrame)
	else
		local _, instanceType = IsInInstance()
		if instanceType == 'pvp' then
			statedriver[WF.db.pvp](WatchFrame)
		elseif instanceType == 'arena' then
			statedriver[WF.db.arena](WatchFrame)
		elseif instanceType == 'party' then
			statedriver[WF.db.party](WatchFrame)
		elseif instanceType == 'raid' then
			statedriver[WF.db.raid](WatchFrame)
		else
			statedriver['NONE'](WatchFrame)
		end
	end

	if WF.inCombat then
		WF:UnregisterEvent('PLAYER_REGEN_ENABLED')
		WF.inCombat = nil
	end
end

function WF:UpdateSettings()
	if WF.db.enable then
		WF:RegisterEvent('PLAYER_ENTERING_WORLD', 'ChangeState')
		WF:RegisterEvent('PLAYER_UPDATE_RESTING', 'ChangeState')
	else
		WF:UnregisterEvent('PLAYER_ENTERING_WORLD')
		WF:UnregisterEvent('PLAYER_UPDATE_RESTING')
	end
end

function WF:UpdateWatchFrame()
	local db = WF.db
	if not db or not WatchFrame or WatchFrame.userCollapsed then return end

	for _, link in ipairs(WATCHFRAME_LINKBUTTONS or {}) do
		if link.type == 'QUEST' then
			local questIndex = GetQuestIndexForWatch(link.index)
			if questIndex then
				local title, level = GetQuestLogTitle(questIndex)
				local color = GetQuestDifficultyColor(level)
				local startLine, lastLine = link.startLine, link.lastLine

				for i = startLine, lastLine do
					local line = link.lines[i]
					if line and line.text then
						local text = line.text:GetText() or ''

						if i == startLine then
							if db.level and not strfind(text, '^%[.*%].*') then
								text = format('[%d] %s', level, text)
								line.text:SetText(text)
							end
							if db.color then
								line.text:SetTextColor(color.r, color.g, color.b)
							end
						elseif db.color then
							local r, g, b = 1, 1, 1
							if text == GetQuestLogCompletionText(questIndex) then
								r, g, b = 0.25, 1, 0.25
							else
								local _, _, num, needed = strfind(text, '([%d]+)/([%d]+)')
								if num and needed then
									local progress = tonumber(num) / tonumber(needed)
									r, g, b = E:ColorGradient(progress, 1, 0, 0, 1, 1, 0, 0.25, 1, 0.25)
								end
							end
							line.text:SetTextColor(r, g, b)
						end
					end
				end
			end
		elseif link.type == 'ACHIEVEMENT' and db.color then
			local startLine, lastLine = link.startLine, link.lastLine
			local achievementID = link.id or link.index
			local completed = false

			if achievementID and type(achievementID) == 'number' then
				completed = select(4, GetAchievementInfo(achievementID))
			end

			local criteriaMap = {}
			if achievementID and GetAchievementNumCriteria then
				local numCriteria = GetAchievementNumCriteria(achievementID)
				for i = 1, numCriteria do
					local critText, _, done, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i)
					if critText and critText ~= '' then
						criteriaMap[critText] = {
							done = done,
							quantity = quantity or 0,
							reqQuantity = reqQuantity or 0
						}
					end
				end
			end

			for i = startLine, lastLine do
				local line = link.lines[i]
				if line and line.text then
					local text = line.text:GetText() or ''

					if i == startLine then
						-- Main achievement title
						if completed then
							line.text:SetTextColor(0.25, 1, 0.25)
						else
							line.text:SetTextColor(1, 0.82, 0)
						end
					else
						local r, g, b = 1, 1, 1
						local hasProgress = false

						-- Check for criteria progress
						for critText, data in pairs(criteriaMap) do
							if text:find(critText, 1, true) then
								if data.reqQuantity > 0 then
									hasProgress = true
									if data.done then
										r, g, b = 0.25, 1, 0.25
									else
										local progress = data.quantity / data.reqQuantity
										r, g, b = E:ColorGradient(progress, 1, 0, 0, 1, 1, 0, 0.25, 1, 0.25)
									end
								elseif data.done then
									hasProgress = true
									r, g, b = 0.25, 1, 0.25
								end
								break
							end
						end

						if not hasProgress then
							local _, _, num, needed = strfind(text, '([%d]+)%s*/%s*([%d]+)')
							if num and needed then
								hasProgress = true
								local progress = tonumber(num) / tonumber(needed)
								r, g, b = E:ColorGradient(progress, 1, 0, 0, 1, 1, 0, 0.25, 1, 0.25)
							end
						end

						-- Only apply color if there's actual progress tracking
						if hasProgress then
							line.text:SetTextColor(r, g, b)
						end
					end
				end
			end
		end
	end
end

local function RestoreQuestColors()
	if not WF.db or not WF.db.color then return end
	WF:UpdateWatchFrame()
end

function WF:QuestLevelToggle()
	if WF.db.level or WF:IsHooked('WatchFrame_Update') then
		if not WF:IsHooked('WatchFrame_Update') then
			WF:SecureHook('WatchFrame_Update', 'UpdateWatchFrame')
		end
	elseif not WF.db.level and not WF.db.color then
		if WF:IsHooked('WatchFrame_Update') then
			WF:Unhook('WatchFrame_Update')
		end
	end
	WatchFrame_Update()
end

function WF:QuestColorToggle()
	if WF.db.color or WF:IsHooked('WatchFrame_Update') then
		if not WF:IsHooked('WatchFrame_Update') then
			WF:SecureHook('WatchFrame_Update', 'UpdateWatchFrame')
		end
	elseif not WF.db.color and not WF.db.level then
		if WF:IsHooked('WatchFrame_Update') then
			WF:Unhook('WatchFrame_Update')
		end
	end
	WatchFrame_Update()
end

function WF:Initialize()
	WF.db = E.db.enhanced.watchframe

	WF:UpdateSettings()
	WF:QuestLevelToggle()
	WF:QuestColorToggle()

	-- Hook color restoration on mouse leave
	hooksecurefunc('WatchFrame_Update', function()
		if not WF.db or not WF.db.color then return end
		for _, button in ipairs(WATCHFRAME_LINKBUTTONS or {}) do
			if not button.__colorHooked then
				button:HookScript('OnLeave', RestoreQuestColors)
				button.__colorHooked = true
			end
		end
	end)
end

E:RegisterModule(WF:GetName())