-------------------------------------------------------------------------------------------------
-- Copyright 2024-2025 Lyubimov Vladislav (grifon7676@gmail.com)
-- With addition by Norzia (devilicip2@gmail.com) for sirus-wow
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the “Software”), to deal in the Software without
-- restriction, including without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or
-- substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-------------------------------------------------------------------------------------------------

local addonName = "DeathLogger"

local Utils = _G[addonName.."_Utils"] or {}
if not next(Utils) then
	error("|cFFFF0000Не удалось загрузить DeathLogger_Utils.lua!|r")
end

local DeathLogWidget = {}
local guildMembers = {}
DeathLogWidget.__index = DeathLogWidget
DeathLoggerDB = DeathLoggerDB or {}
DeathLoggerDB.entries = DeathLoggerDB.entries or {}
local widgetInstance = nil

local DeathLoggerTooltip = CreateFrame("GameTooltip", "DeathLoggerTooltip", UIParent, "SharedTooltipTemplate")
local DeathLog_L = {
	minimap_btn_left_click = "Left-click to open/close log",
	minimap_btn_right_click = "Right-click to open menu",
}

local function SaveFramePositionAndSize(frame)
	local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
	DeathLoggerDB.point = point
	DeathLoggerDB.relativePoint = relativePoint
	DeathLoggerDB.xOfs = xOfs
	DeathLoggerDB.yOfs = yOfs
	DeathLoggerDB.width = frame:GetWidth()
	DeathLoggerDB.height = frame:GetHeight()
end

local function ShowTooltip(self)
	DeathLoggerTooltip:SetOwner(self, "ANCHOR_TOP")
	DeathLoggerTooltip:SetText(self.tooltip, 1, 1, 1, 1, false)
	DeathLoggerTooltip:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	DeathLoggerTooltip:SetBackdropColor(0, 0, 0, 1)
	DeathLoggerTooltip:Show()
end

local function HideTooltip(self)
	DeathLoggerTooltip:Hide()
end

--

local DeathLog_minimap_button = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
	type = "data source",
	text = addonName,
	icon = "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull",
	OnClick = function(self, btn)
		if btn == "LeftButton" then
			if widgetInstance and widgetInstance:IsShown() then
				widgetInstance:Hide()
			else
				if not widgetInstance then
					widgetInstance = DeathLogWidget.new()
				end
				widgetInstance:Show()
			end
		else
			InterfaceOptionsFrame_OpenToCategory(addonName)
		end
	end,
	OnTooltipShow = function(tooltip)
		tooltip:AddLine(addonName)
		tooltip:AddLine(DeathLog_L.minimap_btn_left_click)
		tooltip:AddLine(DeathLog_L.minimap_btn_right_click)
	end,
})

local function initMinimapButton()
	local DeathLog_minimap_button_stub = LibStub("LibDBIcon-1.0", true)
	if DeathLog_minimap_button_stub then
		if not DeathLog_minimap_button_stub:IsRegistered(addonName) then
			DeathLog_minimap_button_stub:Register(addonName, DeathLog_minimap_button, {
				icon = "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull",
			})
		end
		if DeathLoggerDB.show_minimap == false then
			DeathLog_minimap_button_stub:Hide(addonName)
		else
			DeathLog_minimap_button_stub:Show(addonName)
		end
	else
		print("LibDBIcon-1.0 не загружена. Иконка на миникарте не будет отображаться.")
	end
end

DeathLog_minimap_button.OnTooltipShow = function(tooltip)
	UpdateAddOnMemoryUsage()
	local memoryUsage = GetAddOnMemoryUsage(addonName)
	local memoryUsageMB = memoryUsage / 1024

	tooltip:AddLine(addonName)
	tooltip:AddLine(DeathLog_L.minimap_btn_left_click)
	tooltip:AddLine(DeathLog_L.minimap_btn_right_click)
	tooltip:AddLine(string.format("Память: %.2f MB", memoryUsageMB))
end

--

local function FormatData(data)
	local timeData = data.level >= 70 and Utils.ColorWord("[" .. Utils.TimeNow() .. "]", "Фиолетовый") or
					 data.level >= 60 and Utils.ColorWord("[" .. Utils.TimeNow() .. "]", "Синий") or
					 data.level >= 10 and Utils.ColorWord("[" .. Utils.TimeNow() .. "]", "Белый")

	local name = Utils.ColorWord(data.name, Utils.classes[data.classID])
	local coloredRace, race, side = Utils.GetRaceData(data.raceID)
	local level = data.level >= 70 and Utils.ColorWord(data.level .. " ур.", "Фиолетовый") or
			data.level >= 60 and Utils.ColorWord(data.level .. " ур.", "Синий") or
			data.level .. " ур."
	local cause = Utils.causes[data.causeID] or data.causeID

	local guildInfo = ""
	if Utils.IsPlayerInGuild(data.name) then
		guildInfo = " |cFF00FF00[Гильдия]|r"
	end

	local mainStr = string.format("%s %s %s %s%s", timeData, name, coloredRace, level, guildInfo)
	local tooltip = string.format(
		"%s\nИмя: %s\nУровень: %d\nКласс: %s\nРаса: %s\nФракция: %s\nЛокация: %s\nПричина: %s",
		Utils.ColorWord("Провален", "Красный"), data.name, data.level, Utils.classes[data.classID], race, side, data.locationStr, cause)
	if data.causeID == 7 then
		tooltip = tooltip .. "\nОт: " .. data.enemyName .. " " .. data.enemyLevel .. "-го уровня"
	end
	if Utils.IsPlayerInGuild(data.name) then
		tooltip = tooltip .. "\n|cFF00FF00Член гильдии|r"
	end
	return mainStr, tooltip, data.name
end

local function FormatCompletedChallengeData(data)
	local timeData = Utils.ColorWord("[" .. Utils.TimeNow() .. "]", "Золотой")
	local name = Utils.ColorWord(data.name, Utils.classes[data.classID])
	local coloredRace, race, side = Utils.GetRaceData(data.raceID)

	local guildInfo = ""
	if Utils.IsPlayerInGuild(data.name) then
		guildInfo = " |cFF00FF00[Гильдия]|r"
	end

	local mainStr = string.format("%s %s %s %s%s", timeData, name, coloredRace, Utils.ColorWord("завершил испытание!", "Золотой"), guildInfo)
	local tooltip = string.format("%s\nИмя: %s\nКласс: %s\nРаса: %s\nФракция: %s",
		Utils.ColorWord("Пройден", "Зеленый"), data.name, Utils.classes[data.classID], race, side)
	if Utils.IsPlayerInGuild(data.name) then
		tooltip = tooltip .. "\n|cFF00FF00Член гильдии|r"
	end
	return mainStr, tooltip, data.name
end

--

function DeathLogWidget.new()
	local instance = setmetatable({}, DeathLogWidget)
	instance.currentFilter = nil
	instance.textFrames = {}
	local windowAlpha = .5
	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()
	local maxWidth = screenWidth * 0.45
	local maxHeight = screenHeight * 0.70
	local minWidth = DeathLoggerDB.minWidth or 100
	local minHeight = DeathLoggerDB.minHeight or 100

	instance.mainWnd = CreateFrame("Frame", "DLDialogFrame", UIParent)
	instance.mainWnd:SetSize(DeathLoggerDB.width or minWidth, DeathLoggerDB.height or minHeight)
	instance.mainWnd:SetPoint(DeathLoggerDB.point or "CENTER", UIParent, DeathLoggerDB.relativePoint or "CENTER", DeathLoggerDB.xOfs or 0, DeathLoggerDB.yOfs or 0)
	instance.mainWnd:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	instance.mainWnd:SetBackdropColor(0, 0, 0, windowAlpha)
	
	local closeButton = CreateFrame("Button", nil, instance.mainWnd, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", instance.mainWnd, "TOPRIGHT", -1, -1)
	closeButton:SetScript("OnClick", function()
		widgetInstance:Hide()
	end)

	local resetButton = CreateFrame("Button", nil, instance.mainWnd, "GameMenuButtonTemplate")
	resetButton:SetSize(80, 22)
	resetButton:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -1, -3)
	resetButton:SetText("Сбросить")
	resetButton:SetNormalFontObject("GameFontNormal")
	resetButton:SetHighlightFontObject("GameFontHighlight")
	resetButton:SetScript("OnClick", function()
		StaticPopup_Show("DEATHLOGGER_CONFIRM_RESET")
	end)

	StaticPopupDialogs["DEATHLOGGER_CONFIRM_RESET"] = {
		text = "Вы уверены что хотите очистить список умерших?",
		button1 = "Да",
		button2 = "Нет",
		OnAccept = function()
			if widgetInstance and widgetInstance.textFrames then
				for _, frame in ipairs(widgetInstance.textFrames) do
					frame:Hide()
				end
				widgetInstance.textFrames = {}
				widgetInstance.previousEntry = nil
				widgetInstance.scrollFrame:UpdateScrollChildRect()
			end

			DeathLoggerDB.entries = {}
			print("|cFF00FF00Death Logger|r: Список умерших сброшен.")
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}

	local function CreateFilterButton(parent, texture, tooltip, onClick)
		local button = CreateFrame("Button", nil, parent)
		button:SetSize(22, 22)
		button:SetNormalTexture(texture)
		button:SetScript("OnClick", onClick)
		button:SetScript("OnEnter", function(self) ShowTooltip(self) end)
		button:SetScript("OnLeave", HideTooltip)
		button.tooltip = tooltip
		return button
	end

	local allianceFilterButton = CreateFilterButton(instance.mainWnd, "Interface\\Icons\\Achievement_PVP_A_A", "Фильтр: Альянс + Нейтрал", function()
		instance:ApplyFilter(function(entry) return entry.faction == "Альянс" or entry.faction == "Нейтрал" end)
	end)

	local hordeFilterButton = CreateFilterButton(instance.mainWnd, "Interface\\Icons\\Achievement_PVP_H_H", "Фильтр: Орда + Нейтрал", function()
		instance:ApplyFilter(function(entry) return entry.faction == "Орда" or entry.faction == "Нейтрал" end)
	end)

	local allFilterButton = CreateFilterButton(instance.mainWnd, "Interface\\Icons\\Ability_dualwield", "Фильтр: Все фракции", function()
		instance:ApplyFilter(function(entry) return true end)
	end)

	allianceFilterButton:SetPoint("TOPRIGHT", resetButton, "TOPLEFT", -5, 0)
	hordeFilterButton:SetPoint("TOPRIGHT", allianceFilterButton, "TOPLEFT", -5, 0)
	allFilterButton:SetPoint("TOPRIGHT", hordeFilterButton, "TOPLEFT", -5, 0)

	instance.mainWnd.title = instance.mainWnd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	instance.mainWnd.title:SetPoint("TOPLEFT", instance.mainWnd, "TOPLEFT", 10, -8)
	instance.mainWnd.title:SetPoint("TOPRIGHT", resetButton, "TOPLEFT", -10, -8)
	instance.mainWnd.title:SetJustifyH("LEFT")
	instance.mainWnd.title:SetJustifyV("CENTER")
	instance.mainWnd.title:SetText("Death Log")

	local separator = instance.mainWnd:CreateTexture(nil, "ARTWORK")
	separator:SetTexture(1, 1, 1, windowAlpha)
	separator:SetHeight(1)
	separator:SetPoint("TOPLEFT", instance.mainWnd.title, "BOTTOMLEFT", 0, -8)
	separator:SetPoint("TOPRIGHT", instance.mainWnd, "TOPRIGHT", -10, -8)

	instance.mainWnd:SetMovable(true)
	instance.mainWnd:EnableMouse(true)
	instance.mainWnd:RegisterForDrag("LeftButton")
	instance.mainWnd:SetScript("OnDragStart", instance.mainWnd.StartMoving)
	instance.mainWnd:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveFramePositionAndSize(self)
		instance.mainWnd:StopMovingOrSizing()
		instance.mainWnd.isResizing = false
	end)	
	instance.mainWnd:SetResizable(true)

	instance.scrollFrame = CreateFrame("ScrollFrame", nil, instance.mainWnd, "UIPanelScrollFrameTemplate")
	instance.scrollFrame:SetPoint("TOPLEFT", instance.mainWnd, "TOPLEFT", 10, -30)
	instance.scrollFrame:SetPoint("BOTTOMRIGHT", instance.mainWnd, "BOTTOMRIGHT", -30, 15)

	instance.scrollChild = CreateFrame("Frame", nil, instance.scrollFrame)
	instance.scrollChild:SetSize(instance.scrollFrame:GetWidth(), 1)
	instance.scrollFrame:SetScrollChild(instance.scrollChild)
	instance.scrollFrame:SetScript("OnSizeChanged", function()
		instance.scrollChild:SetWidth(instance.scrollFrame:GetWidth())
	end)

	local resizeButton = CreateFrame("Button", nil, instance.mainWnd)
	resizeButton:SetSize(16, 16)
	resizeButton:SetPoint("BOTTOMRIGHT", -2, 3)
	resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		
	resizeButton:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			instance.mainWnd:StartSizing("BOTTOMRIGHT")
			instance.mainWnd.isResizing = true
		end
	end)

	resizeButton:SetScript("OnMouseUp", function(self, button)
		if instance.mainWnd.isResizing then
			instance.mainWnd:StopMovingOrSizing()
			instance.mainWnd.isResizing = false
			SaveFramePositionAndSize(instance.mainWnd)
		end
	end)
	
	resizeButton:SetScript("OnClick", function(self, button)
		if not instance.mainWnd.isResizing then
			instance.mainWnd:StopMovingOrSizing()
			instance.mainWnd.isResizing = false
		end
	end)
	
	instance.mainWnd:SetMinResize(minWidth, minHeight)
	instance.mainWnd:SetMaxResize(maxWidth, maxHeight)
	
	instance.mainWnd:SetScript("OnSizeChanged", function(self, width, height)
		width = math.max(minWidth, math.min(width, maxWidth))
		height = math.max(minHeight, math.min(height, maxHeight))
		
		self:SetSize(width, height)
		instance.scrollFrame:SetSize(width - 40, height - 45)
		instance.scrollChild:SetWidth(width - 40)
		instance:UpdateEntriesPosition()
	end)

	local clickCatcher = CreateFrame("Frame", nil, UIParent)
	clickCatcher:SetAllPoints()
	clickCatcher:SetFrameStrata("DIALOG")
	clickCatcher:EnableMouse(true)
	clickCatcher:SetAlpha(0)
	clickCatcher:Hide()

	clickCatcher:SetScript("OnMouseDown", function()
		if resizeButton.isResizing then
			instance.mainWnd:StopMovingOrSizing()
			resizeButton.isResizing = false
			resizeButton:SetButtonState("NORMAL", false)
		end
		clickCatcher:Hide()
	end)

	instance.mainWnd:SetScript("OnMouseDown", function(self)
		clickCatcher:Show()
	end)

	instance.mainWnd:SetScript("OnMouseUp", function()
		clickCatcher:Hide()
	end)

	instance.textFrames = {}
	instance.previousEntry = nil

	return instance
end

function DeathLogWidget:AddTooltip(target, tooltip)
	target.tooltip = tooltip
	target:SetScript("OnEnter", ShowTooltip)
	target:SetScript("OnLeave", HideTooltip)
end

function DeathLogWidget:CreateTextFrame()
	local frame = CreateFrame("Frame", nil, self.scrollChild)
	frame:SetHeight(14)
	frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT")
	frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT")
	frame:EnableMouse(true)

	frame.factionIcon = frame:CreateTexture(nil, "OVERLAY")
	frame.factionIcon:SetSize(14, 14)
	frame.factionIcon:SetPoint("LEFT", frame, "LEFT", 5, 0)

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.text:SetPoint("LEFT", frame.factionIcon, "RIGHT", 5, 0)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetJustifyV("TOP")

	frame:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			if IsShiftKeyDown() then
				if self.playerName then
					ChatFrame_OpenChat("/g " .. self.playerName .. " F", DEFAULT_CHAT_FRAME)
				end
			else
				if self.playerName then
					ChatFrame_SendTell(self.playerName)
				else
					print("[DEBUG] Имя игрока не найдено. Невозможно открыть приватный чат.")
				end
			end
		end
	end)
	return frame
end

function DeathLogWidget:AddEntry(data, tooltip, faction, playerName)
	local entry = self:CreateTextFrame()
	table.insert(self.textFrames, 1, entry)
	entry.text:SetText(data)
	entry.playerName = playerName
	entry.tooltip = tooltip
	entry.faction = faction
	self:AddTooltip(entry, tooltip)

	if faction == "Альянс" then
		entry.factionIcon:SetTexture("Interface\\Icons\\Achievement_PVP_A_A")
	elseif faction == "Орда" then
		entry.factionIcon:SetTexture("Interface\\Icons\\Achievement_PVP_H_H")
	else
		entry.factionIcon:SetTexture("Interface\\Icons\\Inv_misc_questionmark")
	end

	local shouldShow = true
	if self.currentFilter then
		shouldShow = self.currentFilter(entry)
	end
	if DeathLoggerDB.guildOnly then
		shouldShow = shouldShow and Utils.IsPlayerInGuild(playerName)
	end
	entry:SetShown(shouldShow)

	self:UpdateEntriesPosition()
end

function DeathLogWidget:UpdateEntriesPosition()
	local previousEntry = nil
	local totalHeight = 0
	for _, frame in ipairs(self.textFrames) do
		if frame:IsShown() then
			if previousEntry then
				frame:SetPoint("TOPLEFT", previousEntry, "BOTTOMLEFT", 0, -1)
				frame:SetPoint("TOPRIGHT", previousEntry, "BOTTOMRIGHT", 0, -1)
			else
				frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, 0)
				frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, 0)
			end
			previousEntry = frame
			totalHeight = totalHeight + frame:GetHeight() + 1
		end
	end
	self.scrollChild:SetHeight(totalHeight)
	self.scrollFrame:UpdateScrollChildRect()
	
end

function DeathLogWidget:ApplyFilter(filterFunc)
	self.currentFilter = filterFunc
	for _, frame in ipairs(self.textFrames) do
		local shouldShow = filterFunc(frame)
		if DeathLoggerDB.guildOnly then
			shouldShow = shouldShow and Utils.IsPlayerInGuild(frame.playerName)
		end
		if shouldShow then
			frame:Show()
		else
			frame:Hide()
		end
	end
	self:UpdateEntriesPosition()
end

function DeathLogWidget:Show()
	widgetInstance.mainWnd:Show()
	DeathLoggerDB.isShown = true
end

function DeathLogWidget:Hide()
	widgetInstance.mainWnd:Hide()
	DeathLoggerDB.isShown = false
end

function DeathLogWidget:IsShown()
	return widgetInstance.mainWnd:IsShown()
end

--

local function SaveEntry(data, tooltip, faction, playerName)
	if not DeathLoggerDB.entries then
		DeathLoggerDB.entries = {}
	end
	table.insert(DeathLoggerDB.entries, {
		data = data,
		tooltip = tooltip,
		faction = faction,
		playerName = playerName
	})
end

local function GetPlayerGuildName()
	if IsInGuild() then
		local guildName = GetGuildInfo("player")
		if guildName then
			return guildName
		else
			return "Данные гильдии загружаются..."
		end
	else
		return "Не состоит в гильдии"
	end
end

local function UpdateGuildMembers()
	if IsInGuild() then
		GuildRoster()
		local numMembers = GetNumGuildMembers()
		for i = 1, numMembers do
			local name = GetGuildRosterInfo(i)
			if name then
				table.insert(guildMembers, name)
			end
		end
	end
end

local function OnDeath(text)
	UpdateGuildMembers()
	local dataMap = Utils.StringToMap(text)
	if not dataMap.name then
		return
	end

	local deadPlayerData, tooltip, playerName = FormatData(dataMap)
	local _, _, faction = Utils.GetRaceData(dataMap.raceID)

	if widgetInstance then
		widgetInstance:AddEntry(deadPlayerData, tooltip, faction, playerName)
	end
	SaveEntry(deadPlayerData, tooltip, faction, playerName)
end

local function OnComplete(text)
	UpdateGuildMembers()
	local dataMap = Utils.StringToMap(text)
	if not dataMap.name then
		return
	end
	
	local challengeCompletedData, tooltip, playerName = FormatCompletedChallengeData(dataMap)
	local _, _, faction = Utils.GetRaceData(dataMap.raceID)

	if widgetInstance then
		widgetInstance:AddEntry(challengeCompletedData, tooltip, faction, playerName)
	end
	SaveEntry(challengeCompletedData, tooltip, faction, playerName)
end

local function InitWindow(shouldShow)
	if not widgetInstance then
		widgetInstance = DeathLogWidget.new()
	end
	if shouldShow then
		widgetInstance:Show()
	else
		widgetInstance:Hide()
	end
end

local function SlashCommandHandle(msg)
	if widgetInstance then
		if widgetInstance:IsShown() then
			widgetInstance:Hide()
		else
			widgetInstance:Show()
		end
		return
	end
	DeathLoggerDB.showOnStartup = false
	InitWindow(true)
end

local function SaveEntriesOnLogout()
	if not DeathLoggerDB then
		DeathLoggerDB = {}
	end
	
	DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
	DeathLoggerDB.isShown = widgetInstance and widgetInstance:IsShown() or false
	DeathLoggerDB.guildMembers = nil
	DeathLoggerDB.minWidth = DeathLoggerDB.minWidth or 100
	DeathLoggerDB.minHeight = DeathLoggerDB.minHeight or 100
	DeathLoggerDB.width = DeathLoggerDB.width or DeathLoggerDB.minWidth
	DeathLoggerDB.height = DeathLoggerDB.height or DeathLoggerDB.minHeight
	
	if widgetInstance and widgetInstance.textFrames then
		DeathLoggerDB.entries = {}
		for _, entry in ipairs(widgetInstance.textFrames) do
			table.insert(DeathLoggerDB.entries, {
				data = entry.text:GetText(),
				tooltip = entry.tooltip,
				faction = entry.faction,
				playerName = entry.playerName
			})
		end
	else
		if not widgetInstance then
		end
		if not widgetInstance.textFrames then
		end
	end
end

local function LoadEntries()
	if DeathLoggerDB.entries and widgetInstance then
		for i = #DeathLoggerDB.entries, 1, -1 do
			local entryData = DeathLoggerDB.entries[i]
			widgetInstance:AddEntry(entryData.data, entryData.tooltip, entryData.faction, entryData.playerName)
		end
		widgetInstance:ApplyFilter(function(entry)
			if DeathLoggerDB.guildOnly then
				return Utils.IsPlayerInGuild(entry.playerName)
			else
				return true
			end
		end)
	end
	if DeathLoggerDB.guildMembers then
		guildMembers = DeathLoggerDB.guildMembers
	end
end

local function CreateOptionsPanel()
	local panel = CreateFrame("Frame")
	panel.name = addonName

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(addonName)

	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()
	local maxWidth = screenWidth * 0.45
	local maxHeight = screenHeight * 0.70
	local minWidthLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minWidthLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
	minWidthLabel:SetText("Минимальная ширина окна (%):")

	local minWidthSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
	minWidthSlider:SetPoint("TOPLEFT", minWidthLabel, "BOTTOMLEFT", 0, -10)
	minWidthSlider:SetWidth(200)
	minWidthSlider:SetMinMaxValues(10, 45)
	minWidthSlider:SetValueStep(1)
	minWidthSlider:SetValue((DeathLoggerDB.minWidth or 100) / screenWidth * 100)
	minWidthSlider.tooltipText = "Установите минимальную ширину окна в процентах от ширины экрана (макс. 45%)"
	minWidthSlider.Low:SetText("10%")
	minWidthSlider.High:SetText("45%")
	minWidthSlider.Text = minWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minWidthSlider.Text:SetPoint("TOP", minWidthSlider, "BOTTOM", 0, -5)
	minWidthSlider.Text:SetText(math.floor((DeathLoggerDB.minWidth or 100) / screenWidth * 100) .. "%")
	minWidthSlider:SetScript("OnValueChanged", function(self, value)
		local percent = math.floor(value)
		self.Text:SetText(percent .. "%")
		DeathLoggerDB.minWidth = screenWidth * percent / 100
		DeathLoggerDB.width = DeathLoggerDB.minWidth
		if widgetInstance then
			widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth or 100, DeathLoggerDB.minHeight or 100)
			widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
			local currentWidth, currentHeight = widgetInstance.mainWnd:GetSize()
			widgetInstance.mainWnd:SetWidth(math.min(DeathLoggerDB.minWidth, maxWidth))
		end
		widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
	end)

	local minHeightLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minHeightLabel:SetPoint("TOPLEFT", minWidthSlider, "BOTTOMLEFT", 0, -30)
	minHeightLabel:SetText("Минимальная высота окна (%):")

	local minHeightSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
	minHeightSlider:SetPoint("TOPLEFT", minHeightLabel, "BOTTOMLEFT", 0, -10)
	minHeightSlider:SetWidth(200)
	minHeightSlider:SetMinMaxValues(10, 70)
	minHeightSlider:SetValueStep(1)
	minHeightSlider:SetValue((DeathLoggerDB.minHeight or 100) / screenHeight * 100)
	minHeightSlider.tooltipText = "Установите минимальную высоту окна в процентах от высоты экрана (макс. 70%)"
	minHeightSlider.Low:SetText("10%")
	minHeightSlider.High:SetText("70%")
	minHeightSlider.Text = minHeightSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minHeightSlider.Text:SetPoint("TOP", minHeightSlider, "BOTTOM", 0, -5)
	minHeightSlider.Text:SetText(math.floor((DeathLoggerDB.minHeight or 100) / screenHeight * 100) .. "%")
	minHeightSlider:SetScript("OnValueChanged", function(self, value)
	local percent = math.floor(value)
	self.Text:SetText(percent .. "%")
	DeathLoggerDB.minHeight = screenHeight * percent / 100
	DeathLoggerDB.height = DeathLoggerDB.minHeight
		if widgetInstance then
			widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
			widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
			local currentWidth, currentHeight = widgetInstance.mainWnd:GetSize()
			widgetInstance.mainWnd:SetHeight(math.min(DeathLoggerDB.minHeight, maxHeight))
		end
	widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
	end)

	local guildOnlyCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	guildOnlyCheckbox:SetPoint("TOPLEFT", minHeightSlider, "BOTTOMLEFT", 0, -30)
	guildOnlyCheckbox.text:SetText("Показывать только гильдейские смерти")
	guildOnlyCheckbox:SetChecked(DeathLoggerDB.guildOnly or false)
	guildOnlyCheckbox:SetScript("OnClick", function(self)
		DeathLoggerDB.guildOnly = self:GetChecked()
		if widgetInstance then
			widgetInstance:ApplyFilter(function(entry) return true end)
		end
	end)

	guildOnlyCheckbox.tooltipText = "Если включено, будут отображаться только смерти игроков из вашей гильдии.\n\n|cFF00FF00Примечание:|r Если игрок удалил игрового персонажа фильтр не будет применяться."
	guildOnlyCheckbox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)

	guildOnlyCheckbox:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
	end)

	InterfaceOptions_AddCategory(panel)
end

local function OnReady(self, event, arg1, ...)
	if event == "ADDON_LOADED" and arg1 == "DeathLogger" then
		self:SetScript("OnEvent", OnEvent)
	end
end

local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		local addonName = ...
		if addonName == "DeathLogger" then
			self:UnregisterEvent("ADDON_LOADED")

			DeathLoggerDB = DeathLoggerDB or {}
			DeathLoggerDB.entries = DeathLoggerDB.entries or {}
			DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
			DeathLoggerDB.isShown = DeathLoggerDB.isShown ~= nil and DeathLoggerDB.isShown or false
			DeathLoggerDB.showOnStartup = DeathLoggerDB.showOnStartup or false
			DeathLoggerDB.minWidth = DeathLoggerDB.minWidth or 100
			DeathLoggerDB.minHeight = DeathLoggerDB.minHeight or 100
			DeathLoggerDB.width = DeathLoggerDB.width or DeathLoggerDB.minWidth
			DeathLoggerDB.height = DeathLoggerDB.height or DeathLoggerDB.minHeight

			if DeathLoggerDB.guildMembers then
				guildMembers = DeathLoggerDB.guildMembers
			else
				guildMembers = {}
			end

			if not widgetInstance then
				widgetInstance = DeathLogWidget.new()
			end
			if DeathLoggerDB.isShown then
				widgetInstance:Show()
			else
				widgetInstance:Hide()
			end

			if widgetInstance then
				LoadEntries()
				widgetInstance:ApplyFilter(function(entry) return true end)
			end
		
			initMinimapButton()
			CreateOptionsPanel()
			print("|cFF00FF00Death Logger|r успешно загружен.")
		end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, text, _, sender = ...
		if prefix == "ASMSG_HARDCORE_DEATH" then
			OnDeath(text)
		elseif prefix == "ASMSG_HARDCORE_COMPLETE" then
			OnComplete(text)
		end
	elseif event == "GUILD_ROSTER_UPDATE" then
		GuildRoster()
	elseif event == "PLAYER_LOGOUT" then
		SaveEntriesOnLogout()
	end
end

SLASH_DEATHLOGGER1, SLASH_DEATHLOGGER2 = "/deathlog", "/dl"
SlashCmdList["DEATHLOGGER"] = SlashCommandHandle

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", OnEvent)