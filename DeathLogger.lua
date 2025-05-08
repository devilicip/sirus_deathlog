-------------------------------------------------------------------------------------------------
-- Copyright 2024-2025 Lyubimov Vladislav (grifon7676@gmail.com)
-- Copyright 2025 Norzia (devilicip2@gmail.com) for sirus-wow
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
local wholib = LibStub and LibStub("LibWho-2.0", true)
if wholib then
    wholib = wholib:Library()
	    wholib:SetWhoLibDebug(false) -- LibWho Debug

end
local useLibWho = wholib ~= nil

local DEBUG = false -- DEBUG debug
local function Debug(...)
    if DEBUG then
        print("|cff00ccff[DEBUG]|r " .. strjoin(" ", tostringall(...)))
    end
end
Debug("LibWho status:", wholib and "LOADED" or "MISSING")

local Utils = _G[addonName.."_Utils"] or {}
if not next(Utils) then
	error("|cFFFF0000Не удалось загрузить DeathLogger_Utils.lua!|r")
end

local Options = {}
local defaults = {}
local guildMembers = {}
local isManualGuildRequest = false
local isUpdatingGuild = false
local lastGuildUpdateTime = 0
local GUILD_UPDATE_THROTTLE = 2
local guildUpdateFrame = CreateFrame("Frame")
local guildUpdateDelay = 0
local guildUpdatePending = false
widgetInstance = nil
local isFullWindow = false
local lastRequestedPlayer = nil
local pendingRequest = nil
local DeathLogWidget = {}
DeathLogWidget.__index = DeathLogWidget
DeathLoggerDB = DeathLoggerDB or {}
DeathLoggerDB.entries = DeathLoggerDB.entries or {}
parseGuild = ""

--

local function SaveFramePositionAndSize(frame)
    if frame == widgetInstance.mainWnd then
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
        DeathLoggerDB.point = point
        DeathLoggerDB.relativePoint = relativePoint
        DeathLoggerDB.xOfs = xOfs
        DeathLoggerDB.yOfs = yOfs
        DeathLoggerDB.width = frame:GetWidth()
        DeathLoggerDB.height = frame:GetHeight()
    end
end

local DeathLoggerTooltip = CreateFrame("GameTooltip", "DeathLoggerTooltip", UIParent, "SharedTooltipTemplate")
local DeathLog_L = {
	minimap_btn_left_click = "Left-click to open/close log",
	minimap_btn_right_click = "Right-click to open menu",
}

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

-- минимап

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
})

DeathLog_minimap_button.OnTooltipShow = function(tooltip)
	UpdateAddOnMemoryUsage()
	local memoryUsage = GetAddOnMemoryUsage(addonName)
	local memoryUsageMB = memoryUsage / 1024

	tooltip:AddLine(addonName)
	tooltip:AddLine(DeathLog_L.minimap_btn_left_click)
	tooltip:AddLine(DeathLog_L.minimap_btn_right_click)
	tooltip:AddLine(string.format("Память: %.2f MB", memoryUsageMB))
end

local function initMinimapButton()
	local DeathLog_minimap_button_stub = LibStub("LibDBIcon-1.0", true)
	if DeathLog_minimap_button_stub then
		if not DeathLog_minimap_button_stub:IsRegistered(addonName) then
			DeathLog_minimap_button_stub:Register(addonName, DeathLog_minimap_button, {
				icon = "Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull",
				minimapPos = DeathLoggerDB.minimapIcon.minimapPos or 333, 
			})
		end
		DeathLog_minimap_button_stub:Refresh(addonName, DeathLoggerDB.minimapIcon)
		if DeathLoggerDB.show_minimap == false then
			DeathLog_minimap_button_stub:Hide(addonName)
		else
			DeathLog_minimap_button_stub:Show(addonName)
		end
	else
		print("LibDBIcon-1.0 не загружена. Иконка на миникарте не будет отображаться.")
	end
end

-- обработка ги записей

local function ProcessWhoResults()
    if not pendingRequest then 
        Debug("WHO_LIST_UPDATE: Нет активного запроса")
        return 
    end
    
    Debug("Обработка WHO для:", pendingRequest)
    local name, guild
    
    if useLibWho then
        for i = 1, GetNumWhoResults() do
            local result = GetWhoInfo(i)
            if result and strlower(result) == strlower(pendingRequest) then
                name = result
                guild = select(2, GetWhoInfo(i)) or ""
				    Debug("Обработка useLibWho")
                break
            end
        end
    else
        for i = 1, GetNumWhoResults() do
            name, guild = GetWhoInfo(i)
            if name and strlower(name) == strlower(pendingRequest) then
                guild = guild or ""
				    Debug("Обработка GetWhoInfo")
                break
            end
        end
    end

    if isManualGuildRequest then
        if name then
            local guildText = guild ~= "" and "|cffffcc00<"..guild..">|r" or "|cffaaaaaa<без гильдии>|r"
            print(string.format("|cff00ccff[Инфо]|r %s: %s", name, guildText))
        else
            print("|cffff0000[Ошибка]|r Игрок '"..pendingRequest.."' не найден")
        end
        isManualGuildRequest = false
    else
        parseGuild = guild or ""
    end
    
    pendingRequest = nil
    if not useLibWho then
        FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE")
        SetWhoToUI(0)
    end
end

local function RequestPlayerInfo(playerName)
    lastRequestedPlayer = playerName
    if useLibWho then
        wholib:Who(playerName, nil, ProcessWhoResults)
    else
        SetWhoToUI(1)
        SendWho(playerName)
    end
end

local original_ChatFrame_OnHyperlinkShow
local function NewChatFrame_OnHyperlinkShow(frame, link, text, button)
    if IsShiftKeyDown() and button == "RightButton" then
        isManualGuildRequest = true
        local playerName = link:match("player:([^:]+)")
        if playerName then
            playerName = playerName:gsub("-%S+$", "")
            pendingRequest = playerName
            RequestPlayerInfo(playerName)
            return
        end
    end
    return original_ChatFrame_OnHyperlinkShow(frame, link, text, button)
end

-- local function UpdateGuildMembers()  -- все игроки онлайн + оффлайн
    -- if not IsInGuild() then 
        -- guildMembers = {}
        -- return 
    -- end
    
    -- local numMembers = GetNumGuildMembers()
    -- if numMembers == 0 then return end
    
    -- local newMembers = {}
    -- for i = 1, numMembers do
        -- local name = GetGuildRosterInfo(i)
        -- if name then
            -- table.insert(newMembers, name)
        -- end
    -- end
    
    -- if #newMembers ~= #guildMembers or not Utils.TablesEqual(newMembers, guildMembers) then
        -- guildMembers = newMembers
        -- Debug("Список гильдии обновлен. Участников: " .. #guildMembers)
    -- end
-- end

local function UpdateGuildMembers() -- проверка только из онлайна5к6ьт  
    if not IsInGuild() then 
        guildMembers = {}
        return 
    end
    
    local numMembers = GetNumGuildMembers()
    if numMembers == 0 then return end
    
    local newMembers = {}
    for i = 1, numMembers do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then 
            table.insert(newMembers, name)
        end
    end
    
    if #newMembers ~= #guildMembers or not Utils.TablesEqual(newMembers, guildMembers) then
        guildMembers = newMembers
        Debug("Список гильдии обновлен. Онлайн участников: " .. #guildMembers)
    end
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

-- обработка даты

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
	local rawGuild = ""
	if parseGuild == nil or parseGuild == "" then
		rawGuild = ""
	else
		rawGuild = "|cffffcc00<"..parseGuild..">|r"
	end
	Debug("Обработка FormatData")
    local mainStr = string.format("%s %s %s %s %s %s", timeData, name, coloredRace, level, guildInfo, rawGuild)
    local tooltip = string.format(
        "%s\nИмя: %s\nУровень: %d\nКласс: %s\nРаса: %s\nФракция: %s\nЛокация: %s\nГильдия: %s\nПричина: %s",
        Utils.ColorWord("Провален", "Красный"), data.name, data.level, Utils.classes[data.classID], race, side, data.locationStr, parseGuild, cause)
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
	local rawGuild = ""
	if parseGuild == nil or parseGuild == "" then
		rawGuild = ""
	else
		rawGuild = "|cffffcc00<"..parseGuild..">|r"
	end

	local mainStr = string.format("%s %s %s %s %s %s", timeData, name, coloredRace, Utils.ColorWord("завершил испытание!", "Золотой"), guildInfo, rawGuild)
	local tooltip = string.format("%s\nИмя: %s\nКласс: %s\nРаса: %s\nФракция: %s\nГильдия: %s",
		Utils.ColorWord("Пройден", "Зеленый"), data.name, Utils.classes[data.classID], race, side, parseGuild)
	if Utils.IsPlayerInGuild(data.name) then
		tooltip = tooltip .. "\n|cFF00FF00Член гильдии|r"
	end
	return mainStr, tooltip, data.name
end

-- окно DL Widget

function DeathLogWidget.new()
    local instance = setmetatable({}, DeathLogWidget)
    local screenWidth, screenHeight = GetScreenWidth(), GetScreenHeight()
    local minWidth = DeathLoggerDB.minWidth or (screenWidth * 0.5)
    local minHeight = DeathLoggerDB.minHeight or (screenHeight * 0.4)
    local maxWidth = screenWidth * 0.8
    local maxHeight = screenHeight * 0.7
    local initialWidth = DeathLoggerDB.width or (screenWidth * 0.6)
    local initialHeight = DeathLoggerDB.height or (screenHeight * 0.5)
	local minWidthStat = screenWidth * 0.5
    local minHeightStat = screenHeight * 0.4
    local maxWidthStat = screenWidth * 0.8
    local maxHeightStat = screenHeight * 0.7
	local initialWidthStat = screenWidth * 0.6
    local initialHeightStat = screenHeight * 0.5
    local FULL_WINDOW_SPLIT = 0.6
    
    instance.mainWnd = CreateFrame("Frame", "DLDialogFrame", UIParent)
    instance.mainWnd:SetSize(initialWidth, initialHeight)
    instance.mainWnd:SetPoint(
        DeathLoggerDB.point or "CENTER", 
        UIParent, 
        DeathLoggerDB.relativePoint or "CENTER", 
        DeathLoggerDB.xOfs or 0, 
        DeathLoggerDB.yOfs or 0
    )
    instance.mainWnd:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    instance.mainWnd:SetBackdropColor(0, 0, 0, 0.5)
    instance.mainWnd.title = instance.mainWnd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    instance.mainWnd.title:SetPoint("TOPLEFT", 10, -8)
    instance.mainWnd.title:SetText("Death Log")
    
    local separator = instance.mainWnd:CreateTexture(nil, "ARTWORK")
    separator:SetTexture(1, 1, 1, 0.5)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", instance.mainWnd.title, "BOTTOMLEFT", 0, -8)
    separator:SetPoint("TOPRIGHT", -10, -8)
    
    instance.fullWindow = CreateFrame("Frame", "DLFullDialogFrame", UIParent)
    instance.fullWindow:SetSize(initialWidthStat, initialHeightStat)
    instance.fullWindow:SetPoint("CENTER")
    instance.fullWindow:SetBackdrop(instance.mainWnd:GetBackdrop())
    instance.fullWindow:SetBackdropColor(0, 0, 0, 0.5)
    instance.fullWindow:Hide()
	instance.fullWindow:SetScript("OnSizeChanged", function(self, width, height)
        width = math.max(minWidthStat, math.min(width, maxWidthStat))
        height = math.max(minHeightStat, math.min(height, maxHeightStat))
        self:SetSize(width, height)
        
        instance.statsFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", width * FULL_WINDOW_SPLIT, 10)
        instance.imageFrame:SetPoint("TOPLEFT", instance.statsFrame, "TOPRIGHT", 10, 0)
        instance.imageFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -10, 10)
    end)
    instance.fullWindow:SetMinResize(minWidthStat, minHeightStat)
    instance.fullWindow:SetMaxResize(maxWidthStat, maxHeightStat)
	
    instance.statsFrame = CreateFrame("Frame", nil, instance.fullWindow)
    instance.statsFrame:SetPoint("TOPLEFT", 10, -30)
    instance.statsFrame:SetPoint("BOTTOMRIGHT", instance.fullWindow, "BOTTOMLEFT", instance.fullWindow:GetWidth() * 0.7, 10)
    
    instance.imageFrame = CreateFrame("Frame", nil, instance.fullWindow)
    instance.imageFrame:SetPoint("TOPLEFT", instance.statsFrame, "TOPRIGHT", 10, 0)
    instance.imageFrame:SetPoint("BOTTOMRIGHT", -10, 10)
    
	instance.koboldImage = instance.imageFrame:CreateTexture(nil, "ARTWORK")
	instance.koboldImage:SetAllPoints()
	instance.koboldImage:SetTexture("Interface\\Icons\\Ability_Repair")
	instance.koboldImage:SetTexCoord(0.1, 0.9, 0.1, 0.9)

	instance.koboldImage = instance.statsFrame:CreateTexture(nil, "ARTWORK")
	instance.koboldImage:SetAllPoints()
	instance.koboldImage:SetTexture("Interface\\Icons\\Ability_Ambush")
	instance.koboldImage:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	
    instance.statsTitle = instance.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    instance.statsTitle:SetPoint("CENTER", instance.statsFrame, "TOP", 0, 15)
    instance.statsTitle:SetText("Статистика")
    
	local fullWindowCloseButton = CreateFrame("Button", nil, instance.fullWindow, "UIPanelCloseButton")
	fullWindowCloseButton:SetPoint("TOPRIGHT", instance.fullWindow, "TOPRIGHT", -1, -1)
	fullWindowCloseButton:SetScript("OnClick", function()
		isFullWindow = false
		instance.fullWindow:Hide()
		instance.mainWnd:Show()
		instance.toggleSizeButton:SetNormalFontObject("GameFontNormal")
		instance.toggleSizeButton:SetHighlightFontObject("GameFontHighlight")
		instance.toggleSizeButton:SetText("Статистика1")
	end)
	
	instance.fullWindow:SetMovable(true)
	instance.fullWindow:EnableMouse(true)
	instance.fullWindow:SetResizable(true)
	instance.fullWindow:RegisterForDrag("LeftButton")
	instance.fullWindow:SetScript("OnDragStart", instance.fullWindow.StartMoving)
	instance.fullWindow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)

	local fullResizeButton = CreateFrame("Button", nil, instance.fullWindow)
	fullResizeButton:SetSize(16, 16)
	fullResizeButton:SetPoint("BOTTOMRIGHT", -2, 3)
	fullResizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	fullResizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	fullResizeButton:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			instance.fullWindow:StartSizing("BOTTOMRIGHT")
		end
	end)
	fullResizeButton:SetScript("OnMouseUp", function(self, button)
		instance.fullWindow:StopMovingOrSizing()
	end)

    local closeButton = CreateFrame("Button", nil, instance.mainWnd, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -1, -1)
    closeButton:SetScript("OnClick", function() instance:Hide() end)
    
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
		timeout = 20,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
    
    local allianceBtn = instance:CreateFilterButton(
        "Interface\\Icons\\Achievement_PVP_A_A", 
        "Фильтр: Альянс + Нейтрал",
        function(entry) return entry.faction == "Альянс" or entry.faction == "Нейтрал" end,
        resetButton, "TOPLEFT", -5, 0
    )
    
    local hordeBtn = instance:CreateFilterButton(
        "Interface\\Icons\\Achievement_PVP_H_H", 
        "Фильтр: Орда + Нейтрал",
        function(entry) return entry.faction == "Орда" or entry.faction == "Нейтрал" end,
        allianceBtn, "TOPLEFT", -5, 0
    )
    
    local allBtn = instance:CreateFilterButton(
        "Interface\\Icons\\Ability_dualwield", 
        "Фильтр: Все фракции",
        function(entry) return true end,
        hordeBtn, "TOPLEFT", -5, 0
    )
    
    -- Раскомментировать в 1.6
    -- instance.toggleSizeButton = CreateFrame("Button", nil, instance.mainWnd, "GameMenuButtonTemplate")
    -- instance.toggleSizeButton:SetSize(100, 22)
    -- instance.toggleSizeButton:SetPoint("TOPRIGHT", allBtn, "TOPLEFT", -5, 0)
    -- instance.toggleSizeButton:SetText("Статистика")
	-- instance.toggleSizeButton:SetNormalFontObject("GameFontNormal")
	-- instance.toggleSizeButton:SetHighlightFontObject("GameFontHighlight")
    -- instance.toggleSizeButton:SetScript("OnClick", function()
        -- isFullWindow = not isFullWindow
        -- if isFullWindow then
            -- local point, relativeTo, relativePoint, xOfs, yOfs = instance.mainWnd:GetPoint()
            -- instance.fullWindow:ClearAllPoints()
            -- instance.fullWindow:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
            -- instance.mainWnd:Hide()
            -- instance.fullWindow:Show()
            -- instance.toggleSizeButton:SetText("Обычный режим")
        -- else
            -- instance.fullWindow:Hide()
            -- instance.mainWnd:Show()
            -- instance.toggleSizeButton:SetText("Статистика")
        -- end
    -- end)
    
    instance.scrollFrame = CreateFrame("ScrollFrame", nil, instance.mainWnd, "UIPanelScrollFrameTemplate")
    instance.scrollFrame:SetPoint("TOPLEFT", 10, -30)
    instance.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 15)
    
    instance.scrollChild = CreateFrame("Frame", nil, instance.scrollFrame)
    instance.scrollChild:SetSize(instance.scrollFrame:GetWidth(), 1)
    instance.scrollFrame:SetScrollChild(instance.scrollChild)
    
    instance.mainWnd:SetMovable(true)
    instance.mainWnd:EnableMouse(true)
    instance.mainWnd:RegisterForDrag("LeftButton")
    instance.mainWnd:SetScript("OnDragStart", instance.mainWnd.StartMoving)
    instance.mainWnd:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePositionAndSize(self)
    end)
    instance.mainWnd:SetResizable(true)
    instance.mainWnd:SetMinResize(minWidth, minHeight)
    instance.mainWnd:SetMaxResize(maxWidth, maxHeight)
    
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
            SaveFramePositionAndSize(instance.mainWnd)
            instance.mainWnd.isResizing = false
        end
    end)
    
    instance.textFrames = {}
    instance.previousEntry = nil
    instance.currentFilter = nil
    return instance
end

function DeathLogWidget:CreateFilterButton(texture, tooltip, filterFunc, relativeTo, point, x, y)
    local button = CreateFrame("Button", nil, self.mainWnd)
    button:SetSize(22, 22)
    button:SetNormalTexture(texture)
    button:SetPoint("TOPRIGHT", relativeTo, point or "TOPLEFT", x or -5, y or 0)
    button:SetScript("OnClick", function() self:ApplyFilter(filterFunc) end)
    button:SetScript("OnEnter", function(self) 
        ShowTooltip(self) 
    end)
    button:SetScript("OnLeave", HideTooltip)
    button.tooltip = tooltip
    return button
end

function DeathLogWidget:AddTooltip(target, tooltip)
	target.tooltip = tooltip
	target:SetScript("OnEnter", ShowTooltip)
	target:SetScript("OnLeave", HideTooltip)
end

function DeathLogWidget:CreateTextFrame()
	local frame = CreateFrame("Frame", nil, self.scrollChild)
    frame:SetSize(self.scrollChild:GetWidth(), 14)

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
    frame.text:SetNonSpaceWrap(false)
    frame.text:SetWordWrap(false)

	frame:SetScript("OnMouseUp", function(self, button)
	    if button == "RightButton" and IsShiftKeyDown() then
        if self.playerName then
            -- /dlguild /dlinfo
            isManualGuildRequest = true
            SlashCmdList["DEATHLOGGERINFO"](self.playerName)
        else
            print("[DEBUG] Имя игрока не найдено.")
        end
		elseif button == "LeftButton" then
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

--    entry.text:SetWidth(9999)

function DeathLogWidget:AddEntry(data, tooltip, faction, playerName, parseGuild)
    self.textFrames = self.textFrames or {}
    self.framePool = self.framePool or {}
    
    local entry
    if #self.framePool > 0 then
        entry = table.remove(self.framePool)
        entry:Show()
    else
        entry = self:CreateTextFrame()
    end

    local factionIcon = ({
        ["Альянс"] = "Interface\\Icons\\Achievement_PVP_A_A",
        ["Орда"] = "Interface\\Icons\\Achievement_PVP_H_H"
    })[faction] or "Interface\\Icons\\Inv_misc_questionmark"
	Debug("Обработка AddEntry")
    entry.text:SetText(data)
    entry.playerName = playerName
    entry.tooltip = tooltip
    entry.faction = faction
    entry.parseGuild = parseGuild
    entry.factionIcon:SetTexture(factionIcon)
    self:AddTooltip(entry, tooltip)

    local isInGuild = Utils.IsPlayerInGuild(playerName)
    entry._guildCache = isInGuild

    local shouldShow = (not self.currentFilter or self.currentFilter(entry)) and
                     (not DeathLoggerDB.guildOnly or entry._guildCache)

    entry:SetShown(shouldShow)

    table.insert(self.textFrames, 1, entry)

    if not self.updatePending then
        self.updatePending = true
        local timerFrame = CreateFrame("Frame")
        local elapsed = 0
        
        timerFrame:SetScript("OnUpdate", function(_, delta)
            elapsed = elapsed + delta
            if elapsed >= 0 then
                self:UpdateEntriesPosition()
                timerFrame:SetScript("OnUpdate", nil)
                self.updatePending = nil
            end
        end)
    end
end

-- Дополнительно: Добавить метод очистки пула либо проработать фоновую загрузку
function DeathLogWidget:ClearPool()
    for i = #self.textFrames, 1, -1 do
        local frame = self.textFrames[i]
        frame:Hide()
        table.insert(self.framePool, frame)
        table.remove(self.textFrames, i)
    end
end

function DeathLogWidget:UpdateEntriesPosition()
    local visibleEntries = {}
    for i = 1, #self.textFrames do
        local frame = self.textFrames[i]
        if frame:IsShown() then
            table.insert(visibleEntries, frame)
        end
    end

    local prevFrame, totalHeight
    for i = 1, #visibleEntries do
        local frame = visibleEntries[i]
        frame:ClearAllPoints()
        if prevFrame then
            frame:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -2)
            totalHeight = totalHeight + 16 -- 14 высота + 2 отступ
        else
            frame:SetPoint("TOPLEFT", self.scrollChild, 0, 0)
            totalHeight = 14
        end
        prevFrame = frame
    end

    self.scrollChild:SetHeight(totalHeight or 0)
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
    if isFullWindow then
        self.fullWindow:Show()
        self.mainWnd:Hide()
    else
        self.fullWindow:Hide()
        self.mainWnd:Show()
    end
    DeathLoggerDB.isShown = true
end

function DeathLogWidget:Hide()
    self.mainWnd:Hide()
    self.fullWindow:Hide()
    DeathLoggerDB.isShown = false
end

function DeathLogWidget:IsShown()
    return self.mainWnd:IsShown() or self.fullWindow:IsShown()
end

-- дата 

local function SaveEntry(data, tooltip, faction, playerName, parseGuild)
    if not DeathLoggerDB.entries then
        DeathLoggerDB.entries = {}
    end
    table.insert(DeathLoggerDB.entries, 1, {
        data = data,
        tooltip = tooltip,
        faction = faction,
        playerName = playerName,
        parseGuild = parseGuild
    })
end

local function OnDeath(text)
	if IsInGuild() then
		UpdateGuildMembers()
	end

	local parseGuild = ""
	
	local dataMap = Utils.StringToMap(text)
	if not dataMap.name then
		return
	end

	pendingRequest = dataMap.name
    RequestPlayerInfo(pendingRequest)

    local dataMap = Utils.StringToMap(text)
    local causeID = dataMap.causeID or 0

    if causeID < 0 or causeID > 11 then
        causeID = 10
    end

    HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or _G.deathIcons[0]
    
    Debug("[OnDeath] causeID:", causeID)
    Debug("[OnDeath] Путь к иконке:", HCBL_Settings.currentDeathIcon)

    if HardcoreLossBanner and HardcoreLossBanner.CustomDeathIcon then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(HCBL_Settings.currentDeathIcon)
        Debug("[OnDeath] Иконка установлена.")
    end

    local timerFrame = CreateFrame("Frame")
    local elapsedTime = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTime = elapsedTime + elapsed
        if elapsedTime >= 0.8 then
            local deadPlayerData, tooltip, playerName = FormatData(dataMap)
            local _, _, faction = Utils.GetRaceData(dataMap.raceID)

            if widgetInstance then
                widgetInstance:AddEntry(deadPlayerData, tooltip, faction, playerName, parseGuild)
                widgetInstance:UpdateEntriesPosition()
            end

            SaveEntry(deadPlayerData, tooltip, faction, playerName, parseGuild)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function OnComplete(text)
	if IsInGuild() then
		UpdateGuildMembers()
	end

	local parseGuild = ""
	
	local dataMap = Utils.StringToMap(text)
	if not dataMap.name then
		return
	end
	    
	pendingRequest = dataMap.name
    RequestPlayerInfo(pendingRequest)

    local dataMap = Utils.StringToMap(text)
    local causeID = 11


    if causeID < 0 or causeID > 11 then
        causeID = 10
    end

    HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or _G.deathIcons[0]
    
    Debug("[OnDeath] causeID:", causeID)
    Debug("[OnDeath] Путь к иконке:", HCBL_Settings.currentDeathIcon)

    if HardcoreLossBanner and HardcoreLossBanner.CustomDeathIcon then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(HCBL_Settings.currentDeathIcon)
        Debug("[OnDeath] Иконка установлена.")
    end

    local timerFrame = CreateFrame("Frame")
    local elapsedTime = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTime = elapsedTime + elapsed
        if elapsedTime >= 0.8 then
			local challengeCompletedData, tooltip, playerName = FormatCompletedChallengeData(dataMap)
			local _, _, faction = Utils.GetRaceData(dataMap.raceID)

			if widgetInstance then
				widgetInstance:AddEntry(challengeCompletedData, tooltip, faction, playerName, parseGuild)
				widgetInstance:UpdateEntriesPosition()
			end
	
			SaveEntry(challengeCompletedData, tooltip, faction, playerName, parseGuild)
			self:SetScript("OnUpdate", nil)
	    end
    end)
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

SlashCmdList["DEATHLOGGER"] = function(input)
    if widgetInstance then
        if widgetInstance:IsShown() then
            widgetInstance:Hide()
        else
            widgetInstance:Show()
        end
    else
        DeathLoggerDB.showOnStartup = false
        InitWindow(true)
    end
end

SlashCmdList["DEATHLOGGERINFO"] = function(input)
    local playerName = strtrim(input)
    if playerName == "" then
        print("|cFF00FF00Death Logger|r: Использование: /dlinfo или /dlguild <имя игрока>")
        return
    end
    isManualGuildRequest = true
    pendingRequest = playerName:gsub("-%S+$", "")
    RequestPlayerInfo(pendingRequest)
end

-- сохранение загрузка запией

local function SaveEntriesOnLogout()
    DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
    DeathLoggerDB.isShown = widgetInstance and widgetInstance:IsShown() or false
    DeathLoggerDB.guildMembers = guildMembers
    DeathLoggerDB.minWidth = DeathLoggerDB.minWidth or 200
    DeathLoggerDB.minHeight = DeathLoggerDB.minHeight or 100
    DeathLoggerDB.width = DeathLoggerDB.width or DeathLoggerDB.minWidth
    DeathLoggerDB.height = DeathLoggerDB.height or DeathLoggerDB.minHeight
	DeathLoggerDB.HCBL_Settings = DeathLoggerDB.HCBL_Settings or {}
	Utils.CopyTable(HCBL_Settings, DeathLoggerDB.HCBL_Settings)
end

local function LoadEntries()
    if DeathLoggerDB.entries and widgetInstance then
        local totalEntries = #DeathLoggerDB.entries
        local maxEntriesToLoad = math.min(totalEntries, 1000)
        for i = maxEntriesToLoad, 1, -1 do
            local entryData = DeathLoggerDB.entries[i]
            widgetInstance:AddEntry(entryData.data, entryData.tooltip, entryData.faction, entryData.playerName, entryData.parseGuild)
        end
        widgetInstance:ApplyFilter(function(entry)
            if DeathLoggerDB.guildOnly then
                return Utils.IsPlayerInGuild(entry.playerName)
            else
                return true
            end
        end)
    end
end

-- инициализация

local function OnEvent(self, event, ...)
	if event == "ADDON_LOADED" then
		local addonName = ...
		if addonName == "DeathLogger" then
			DeathLoggerDB = DeathLoggerDB or {}
            DeathLoggerDB.HCBL_Settings = DeathLoggerDB.HCBL_Settings or {}
            
            Options = _G.DeathLogger_Options or {}
            local optionDefaults = Options.defaults or {}
            Utils.CopyTable(optionDefaults, DeathLoggerDB.HCBL_Settings)
            DeathLoggerDB.HCBL_Settings.initialized = true
            HCBL_Settings = DeathLoggerDB.HCBL_Settings			
            DeathLoggerDB.HCBL_Settings.dl_ver = Options.defaults.dl_ver

			-- Возможно это более правильная загрузка. Тестировать.
			-- if not DeathLoggerDB.HCBL_Settings or not DeathLoggerDB.HCBL_Settings.initialized then
				-- DeathLoggerDB.HCBL_Settings = DeathLoggerDB.HCBL_Settings or {}
				-- Utils.CopyTable(defaults, DeathLoggerDB.HCBL_Settings)
				-- DeathLoggerDB.HCBL_Settings.initialized = true
			-- end
			-- HCBL_Settings = DeathLoggerDB.HCBL_Settings
		
		    original_ChatFrame_OnHyperlinkShow = ChatFrame_OnHyperlinkShow
			ChatFrame_OnHyperlinkShow = NewChatFrame_OnHyperlinkShow
			self:UnregisterEvent("ADDON_LOADED")

			DeathLoggerDB.entries = DeathLoggerDB.entries or {}
			DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
			DeathLoggerDB.isShown = DeathLoggerDB.isShown ~= nil and DeathLoggerDB.isShown or false
			DeathLoggerDB.showOnStartup = DeathLoggerDB.showOnStartup or false
			DeathLoggerDB.minWidth = DeathLoggerDB.minWidth or 200
			DeathLoggerDB.minHeight = DeathLoggerDB.minHeight or 100
			DeathLoggerDB.width = DeathLoggerDB.width or DeathLoggerDB.minWidth
			DeathLoggerDB.height = DeathLoggerDB.height or DeathLoggerDB.minHeight
	        DeathLoggerDB.minimapIcon = DeathLoggerDB.minimapIcon or {}
            DeathLoggerDB.minimapIcon.minimapPos = DeathLoggerDB.minimapIcon.minimapPos or 333 

			if not original_ChatFrame_OnHyperlinkShow then
				original_ChatFrame_OnHyperlinkShow = ChatFrame_OnHyperlinkShow
			end

			if DeathLoggerDB.guildMembers then
				local unique = {}
				for _, name in ipairs(DeathLoggerDB.guildMembers) do
					unique[name] = true
			end
			guildMembers = {}
				for name in pairs(unique) do
					table.insert(guildMembers, name)
				end
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
			Options.CreateOptionsPanel()
			if HardcoreLossBanner then
                Options.UpdateBannerElements() -- Применить настройки масштаба -- возможно излишнее
            end
		    Options.SetupOriginalBanner()
			print("|cFF00FF00Death Logger|r успешно загружен.")
		end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, text, _, sender = ...
		if prefix == "ASMSG_HARDCORE_DEATH" then
			OnDeath(text)
            local cutData = Utils.StringToMap(text)
            local causeID = cutData.causeID or 0
			HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or 10
            Debug("Received causeID:", causeID, "| Icon:", HCBL_Settings.currentDeathIcon)
		    Debug("Обработка OnDeath", text)
		elseif prefix == "ASMSG_HARDCORE_COMPLETE" then
			OnComplete(text)
			local causeID = 11
			HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or ""
            Debug("Received causeID:", causeID, "| Icon:", HCBL_Settings.currentDeathIcon)
		    Debug("Обработка OnComplete", text)
		end
	elseif event == "WHO_LIST_UPDATE" then
		if pendingRequest then
			ProcessWhoResults()
		end
	elseif event == "GUILD_ROSTER_UPDATE" and not isUpdatingGuild then
    local currentTime = GetTime()
    if currentTime - lastGuildUpdateTime > GUILD_UPDATE_THROTTLE and not isUpdatingGuild then
        lastGuildUpdateTime = currentTime
        isUpdatingGuild = true
        Debug("Начало обработки GUILD_ROSTER_UPDATE")
        GuildRoster()
        
        guildUpdatePending = true
        guildUpdateDelay = 0
        guildUpdateFrame:SetScript("OnUpdate", function(self, elapsed)
            guildUpdateDelay = guildUpdateDelay + elapsed
            if guildUpdateDelay >= 1 then
                self:SetScript("OnUpdate", nil)
                if IsInGuild() then
                    UpdateGuildMembers()
                    Debug("Гильдия обновлена. Участников: " .. #guildMembers)
                end
                isUpdatingGuild = false
                guildUpdatePending = false
            end
        end)
    end
	elseif event == "PLAYER_LOGOUT" then
		SaveEntriesOnLogout()
	end
end

SLASH_DEATHLOGGER1, SLASH_DEATHLOGGER2 = "/deathlog", "/dl"
SLASH_DEATHLOGGERINFO1, SLASH_DEATHLOGGERINFO2 = "/dlinfo", "/dlguild"

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("WHO_LIST_UPDATE")
frame:SetScript("OnEvent", OnEvent)