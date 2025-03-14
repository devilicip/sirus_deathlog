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
local DeathLogWidget = {}
local guildMembers = {}
local previousGuildMembers = {}
local isUpdating = false
local updateInterval = 60  -- 60 сек
local timeSinceLastUpdate = 0

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

    instance.mainWnd = CreateFrame("Frame", "MyDialogFrame", UIParent)
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
	
	resizeButton:SetScript("OnClick", function(self, button)
		if not instance.mainWnd.isResizing then
			instance.mainWnd.isResizing = false
		end
	end)
	
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
	
	instance.mainWnd:SetScript("OnSizeChanged", function(self, width, height)
		if width > maxWidth then
			width = maxWidth
		end
		if height > maxHeight then
			height = maxHeight
		end
		if width < minWidth then
			width = minWidth
		end
		if height < minHeight then
			height = minHeight
		end

		self:SetSize(width, height)
		instance.scrollFrame:SetSize(width - 40, height - 45)
		instance.scrollChild:SetWidth(width - 40)
		instance:UpdateEntriesPosition()
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

-- на тест быстрая проверка
-- local function IsPlayerInGuild(targetName)
    -- for _, name in ipairs(guildMembers) do
        -- if name == targetName then
            -- return true
        -- end
    -- end
    -- return false
-- end

local function IsPlayerInGuild(targetName)
    if IsInGuild() then
        local numMembers = GetNumGuildMembers()
        for i = 1, numMembers do
            local name = GetGuildRosterInfo(i)
            if name == targetName then
                return true
            end
        end
    end
    return false
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
        shouldShow = shouldShow and IsPlayerInGuild(playerName)
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
			shouldShow = shouldShow and IsPlayerInGuild(frame.playerName)
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

local _, core = ...

local classes = {
	[1] = "Воин",
	[2] = "Паладин",
	[3] = "Охотник",
	[4] = "Разбойник",
	[5] = "Жрец",
	[6] = "Рыцарь смерти",
	[7] = "Шаман",
	[8] = "Маг",
	[9] = "Чернокнижник",
	[11] = "Друид"
}

local alliances = {
	[0] = "Орда",
	[1] = "Альянс",
	[2] = "Нейтрал",
	[3] = "Неопределено"
}

local races = {
	[1] = { "Человек", "Альянс" },
	[2] = { "Орк", "Орда" },
	[3] = { "Дворф", "Альянс" },
	[4] = { "Ночной эльф", "Альянс" },
	[5] = { "Нежить", "Орда" },
	[6] = { "Таурен", "Орда" },
	[7] = { "Гном", "Альянс" },
	[8] = { "Тролль", "Орда" },
	[9] = { "Гоблин", "Орда" },
	[10] = { "Эльф крови", "Орда" },
	[11] = { "Дреней", "Альянс" },
	[12] = { "Ворген", "Альянс" },
	[13] = { "Нага", "Орда" },
	[14] = { "Пандарен", "Альянс" },
	[15] = { "Высший Эльф", "Альянс" },
	[16] = { "Пандарен", "Орда" },
	[17] = { "Ночнорожденный", "Орда" },
	[18] = { "Озаренный Дреней", "Альянс" },
	[19] = { "Вульпера", "Альянс" },
	[20] = { "Вульпера", "Орда" },
	[21] = { "Вульпера", "Нейтрал" },
	[22] = { "Пандарен", "Нейтрал" },
	[23] = { "Зандалар", "Орда" },
	[24] = { "Эльф Бездны", "Альянс" },
	[25] = { "Эредар", "Орда" },
	[26] = { "Дворф Черного Железа", "Альянс" },
	[27] = { "Драктир", "Нейтрал" },	-- для альянс или орда нет определения расы, поэтому драктиры по умолчанию нейтрал
	[28] = { "Драктир", "Орда" }, -- для возможного учета но на форуме отписались что это не возможно
	[29] = { "Драктир", "Альянс" }	-- для возможного учета https://forum.sirus.su/threads/draktiry-bez-opredelenija-frakcii.492874/
}

local colors = {
	["Орда"] = "FFFF0000",
	["Альянс"] = "FF0070DD",
	["Нейтрал"] = "FF777C87",
	["Неопределено"] = "FF000000",
	["Воин"] = "FFC69B6D",
	["Паладин"] = "FFF48CBA",
	["Охотник"] = "FFAAD372",
	["Разбойник"] = "FFFFF468",
	["Жрец"] = "FFF0EBE0",
	["Рыцарь смерти"] = "FFC41E3B", -- не участвует в ХК режиме
	["Шаман"] = "FF2359FF",
	["Маг"] = "FF68CCEF",
	["Чернокнижник"] = "FF9382C9",
	["Друид"] = "FFFF7C0A",
	["Золотой"] = "FFFF8000",
	["Зеленый"] = "FF00FF00",
	["Синий"] = "FF0070DD",
	["Фиолетовый"] = "FFA335EE",
	["Неизвестно"] = "FFFF69B4",
	["Красный"] = "FFFF0000",
	["Белый"] = "FFFFFFFF"
}

local causes = {
	[0] = "Усталость",
	[1] = "Утопление",
	[2] = "Падение",
	[3] = "Лава",
	[4] = "Болото",
	[5] = "Огонь",
	[6] = "Падение в бездну",
	[7] = "Убийство",
	[8] = "Дуэль/PVP",
	[9] = "Дружеский огонь",
	[10] = "От собственных действий",  -- взято из игровых данных
}

local function ColorWord(word, colorRepr)
	if not word or not colorRepr then return nil end
	local colorCode = colors[colorRepr]
	if not colorCode then return nil end
	return "|c" .. colorCode .. word .. "|r"
end

local function ExtractName(str)
	if not str then
		print("[DEBUG][ExtractName] Входная строка пуста или равна nil.")
		return nil
	end
	local name = str:match("^[^:]+")
	if not name then
		print("[DEBUG][ExtractName] Не удалось извлечь имя из строки:", str)
	end
	return name
end

local function StringToMap(str)
	local tbl = {}
	local keys = { "name", "raceID", "sideID", "classID", "level", "locationStr", "causeID", "enemyName", "enemyLevel" }
	local index = 1
	for str in string.gmatch(str, "[^:]+") do
		tbl[keys[index]] = tonumber(str) or str
		index = index + 1
	end
	tbl.name = ExtractName(str)
	return tbl
end

local function TimeNow()
	return date("%H:%M", GetServerTime())
end

local function GetRaceData(id)
	local raceTuple = races[id]
	local coloredRace, race, side
	if raceTuple then
		race = raceTuple[1]
		side = raceTuple[2]
		coloredRace = ColorWord(race, side)
	else
		race = id
		coloredRace = race
		side = "Неизвестно"
	end
	return coloredRace, race, side
end

local function FormatData(data)
	local timeData = data.level >= 70 and ColorWord("[" .. TimeNow() .. "]", "Фиолетовый") or
					 data.level >= 60 and ColorWord("[" .. TimeNow() .. "]", "Синий") or
					 data.level >= 10 and ColorWord("[" .. TimeNow() .. "]", "Белый")

	local name = ColorWord(data.name, classes[data.classID])
	local coloredRace, race, side = GetRaceData(data.raceID)
	local level = data.level >= 70 and ColorWord(data.level .. " ур.", "Фиолетовый") or
				  data.level >= 60 and ColorWord(data.level .. " ур.", "Синий") or
				  data.level .. " ур."
	local cause = causes[data.causeID] or data.causeID

	local guildInfo = ""
	if IsPlayerInGuild(data.name) then
		guildInfo = " |cFF00FF00[Гильдия]|r"
	end

	local mainStr = string.format("%s %s %s %s%s", timeData, name, coloredRace, level, guildInfo)
	local tooltip = string.format(
		"%s\nИмя: %s\nУровень: %d\nКласс: %s\nРаса: %s\nФракция: %s\nЛокация: %s\nПричина: %s",
		ColorWord("Провален", "Красный"), data.name, data.level, classes[data.classID], race, side, data.locationStr, cause)
	if data.causeID == 7 then
		tooltip = tooltip .. "\nОт: " .. data.enemyName .. " " .. data.enemyLevel .. "-го уровня"
	end
	if IsPlayerInGuild(data.name) then
		tooltip = tooltip .. "\n|cFF00FF00Член гильдии|r"
	end
	return mainStr, tooltip, data.name
end

local function FormatCompletedChallengeData(data)
	local timeData = ColorWord("[" .. TimeNow() .. "]", "Золотой")
	local name = ColorWord(data.name, classes[data.classID])
	local coloredRace, race, side = GetRaceData(data.raceID)

	local guildInfo = ""
	if IsPlayerInGuild(data.name) then
		guildInfo = " |cFF00FF00[Гильдия]|r"
	end

	local mainStr = string.format("%s %s %s %s%s", timeData, name, coloredRace, ColorWord("завершил испытание!", "Золотой"), guildInfo)
	local tooltip = string.format("%s\nИмя: %s\nКласс: %s\nРаса: %s\nФракция: %s",
		ColorWord("Пройден", "Зеленый"), data.name, classes[data.classID], race, side)
	if IsPlayerInGuild(data.name) then
		tooltip = tooltip .. "\n|cFF00FF00Член гильдии|r"
	end
	return mainStr, tooltip, data.name
end

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

local function UpdateGuildMembers()
    guildMembers = {}
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
	local dataMap = StringToMap(text)
	if not dataMap.name then
		return
	end
	
	UpdateGuildMembers()
	
	local deadPlayerData, tooltip, playerName = FormatData(dataMap)
	local _, _, faction = GetRaceData(dataMap.raceID)

	if widgetInstance then
		widgetInstance:AddEntry(deadPlayerData, tooltip, faction, playerName)
	end

	SaveEntry(deadPlayerData, tooltip, faction, playerName)
end

local function OnComplete(text)
	local dataMap = StringToMap(text)
	if not dataMap.name then
		return
	end

	UpdateGuildMembers()

	local challengeCompletedData, tooltip, playerName = FormatCompletedChallengeData(dataMap)
	local _, _, faction = GetRaceData(dataMap.raceID)
	if widgetInstance then
		widgetInstance:AddEntry(challengeCompletedData, tooltip, faction, playerName)
	end
	SaveEntry(challengeCompletedData, tooltip, faction, playerName)
end

local function OnEvent(self, event, prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
	if prefix == "ASMSG_HARDCORE_DEATH" then
		OnDeath(text)
	elseif prefix == "ASMSG_HARDCORE_COMPLETE" then
		OnComplete(text)
	end
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

local function SaveSettingsOnLogout()
	if not DeathLoggerDB then
		DeathLoggerDB = {}
	end
	DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
	DeathLoggerDB.isShown = widgetInstance and widgetInstance:IsShown() or false
	DeathLoggerDB.guildMembers = guildMembers
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
        for _, entryData in ipairs(DeathLoggerDB.entries) do
            widgetInstance:AddEntry(entryData.data, entryData.tooltip, entryData.faction, entryData.playerName)
        end
        widgetInstance:ApplyFilter(function(entry)
            if DeathLoggerDB.guildOnly then
                return IsPlayerInGuild(entry.playerName)
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
	minWidthSlider:SetValue((DeathLoggerDB.minWidth) / screenWidth * 100)
	minWidthSlider.tooltipText = "Установите минимальную ширину окна в процентах от ширины экрана (макс. 45%)"
	minWidthSlider.Low:SetText("10%")
	minWidthSlider.High:SetText("45%")
	minWidthSlider.Text = minWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minWidthSlider.Text:SetPoint("TOP", minWidthSlider, "BOTTOM", 0, -5)
	minWidthSlider.Text:SetText(math.floor((DeathLoggerDB.minWidth) / screenWidth * 100) .. "%")
	minWidthSlider:SetScript("OnValueChanged", function(self, value)
		local percent = math.floor(value)
		self.Text:SetText(percent .. "%")
		DeathLoggerDB.minWidth = screenWidth * percent / 100
		DeathLoggerDB.width = DeathLoggerDB.minWidth  -- Сохраняем текущую ширину
		if widgetInstance then
			widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
			widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
			local currentWidth, currentHeight = widgetInstance.mainWnd:GetSize()
			widgetInstance.mainWnd:SetWidth(math.min(DeathLoggerDB.minWidth, maxWidth))
		end
	end)

	local minHeightLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minHeightLabel:SetPoint("TOPLEFT", minWidthSlider, "BOTTOMLEFT", 0, -30)
	minHeightLabel:SetText("Минимальная высота окна (%):")

	local minHeightSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
	minHeightSlider:SetPoint("TOPLEFT", minHeightLabel, "BOTTOMLEFT", 0, -10)
	minHeightSlider:SetWidth(200)
	minHeightSlider:SetMinMaxValues(10, 70)
	minHeightSlider:SetValueStep(1)
	minHeightSlider:SetValue((DeathLoggerDB.minHeight) / screenHeight * 100)
	minHeightSlider.tooltipText = "Установите минимальную высоту окна в процентах от высоты экрана (макс. 70%)"
	minHeightSlider.Low:SetText("10%")
	minHeightSlider.High:SetText("70%")
	minHeightSlider.Text = minHeightSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minHeightSlider.Text:SetPoint("TOP", minHeightSlider, "BOTTOM", 0, -5)
	minHeightSlider.Text:SetText(math.floor((DeathLoggerDB.minHeight) / screenHeight * 100) .. "%")

	minHeightSlider:SetScript("OnValueChanged", function(self, value)
		local percent = math.floor(value)
		self.Text:SetText(percent .. "%")
		DeathLoggerDB.minHeight = screenHeight * percent / 100
		DeathLoggerDB.height = DeathLoggerDB.minHeight  -- Сохраняем текущую высоту
		if widgetInstance then
			widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
			widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
			local currentWidth, currentHeight = widgetInstance.mainWnd:GetSize()
			widgetInstance.mainWnd:SetHeight(math.min(DeathLoggerDB.minHeight, maxHeight))
		end
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

    local memoryLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memoryLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -200)
    memoryLabel:SetText("Используемая память: ")

    local memoryValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    memoryValue:SetPoint("LEFT", memoryLabel, "RIGHT", 5, 0)

    local function UpdateMemoryUsage()
        UpdateAddOnMemoryUsage()
        local memoryUsage = GetAddOnMemoryUsage(addonName)
        local memoryUsageMB = memoryUsage / 1024
        memoryValue:SetText(string.format("%.2f MB", memoryUsageMB))
    end

    panel:SetScript("OnShow", UpdateMemoryUsage)

    -- local refreshButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    -- refreshButton:SetSize(120, 22)
    -- refreshButton:SetPoint("TOPLEFT", memoryLabel, "BOTTOMLEFT", 0, -10)
    -- refreshButton:SetText("Обновить память")
    -- refreshButton:SetScript("OnClick", UpdateMemoryUsage)

	InterfaceOptions_AddCategory(panel)
end

local function OnReady(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "DeathLogger" then
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("CHAT_MSG_ADDON")
        self:SetScript("OnEvent", OnEvent)
        print("|cFF00FF00Death Logger|r успешно загружен.")

        DeathLoggerDB = DeathLoggerDB or {}
        DeathLoggerDB.entries = DeathLoggerDB.entries or {}
        DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
        DeathLoggerDB.showOnStartup = DeathLoggerDB.showOnStartup or false
        DeathLoggerDB.isShown = DeathLoggerDB.isShown ~= nil and DeathLoggerDB.isShown or false

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

        initMinimapButton()
        CreateOptionsPanel()

        if widgetInstance then
            LoadEntries()
            widgetInstance:ApplyFilter(function(entry) return true end)
        end
    end
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == "DeathLogger" then
        OnReady(self, event, ...)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text = ...
        if prefix == "ASMSG_HARDCORE_DEATH" then
            OnDeath(text)
        elseif prefix == "ASMSG_HARDCORE_COMPLETE" then
            OnComplete(text)
        end
	elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        if message:find("присоединился к гильдии") or message:find("покинул гильдию") then
            GuildRoster()
        end
    end
end

SLASH_DEATHLOGGER1, SLASH_DEATHLOGGER2 = "/deathlog", "/dl"
SlashCmdList["DEATHLOGGER"] = SlashCommandHandle

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "DeathLogger" then
        OnReady(self, event, ...)
    elseif event == "PLAYER_LOGOUT" then
        SaveSettingsOnLogout()
    else
        OnEvent(self, event, ...)
    end
end)