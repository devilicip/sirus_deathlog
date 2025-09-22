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
local Stats = _G[addonName.."_Stats"] or {}
local Sync = _G.DeathLoggerSync or {}

if not next(Utils) then
    error("|cFFFF0000Не удалось загрузить DeathLogger_Utils.lua!|r")
end
if not next(Stats) then
    error("|cFFFF0000Не удалось загрузить DeathLogger_Stats.lua!|r")
elseif DEBUG then
    print("|cFF00FF00Death Logger|r: Модуль статистики загружен")
end
if not next(Sync) then
    error("|cFFFF0000Не удалось загрузить DeathLogger_Sync.lua!|r")
elseif DEBUG then
    print("|cFF00FF00Death Logger|r: Модуль синхронизации загружен")
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
_G.DeathLoggerDB = DeathLoggerDB or {}
DeathLoggerDB.entries = DeathLoggerDB.entries or {}
parseGuild = ""
local isLoggingOut = false
local guildCache = DeathLoggerDB.guildCache or {}
local deathOverlayFrames = {}
DeathLoggerDB.announceDeathToGuild = DeathLoggerDB.announceDeathToGuild or true
_G.widgetInstance = nil

local DL_EdgeGlow = nil
local DL_EdgeGlowSettings = {
    edgeThickness = 8,
    fadeInDuration = 0.3,
    fadeOutDuration = 0.7,
    holdDuration = 0.5,
    flashCount = 2,
    flashDelay = 0.1
}
local FILTERS = {
    ALL = 1,
    ALLIANCE = 2, 
    HORDE = 3
}

--

local function CreateEdgeGlow()
    if DL_EdgeGlow then return DL_EdgeGlow end
    
    DL_EdgeGlow = CreateFrame("Frame", "DL_EdgeGlow", UIParent)
    DL_EdgeGlow:SetAllPoints()
    DL_EdgeGlow:SetFrameStrata("FULLSCREEN_DIALOG")
    DL_EdgeGlow:Hide()
    local edges = {}
    for i = 1, 4 do
        edges[i] = DL_EdgeGlow:CreateTexture(nil, "BACKGROUND")
        -- edges[i]:SetTexture(1,0,0)
        edges[i]:SetTexture("Interface\\Buttons\\WHITE8X8")
        edges[i]:SetAlpha(0)
    end
    
    edges[1]:SetPoint("TOPLEFT", DL_EdgeGlow, "TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", DL_EdgeGlow, "TOPRIGHT", 0, 0)
    edges[1]:SetHeight(DL_EdgeGlowSettings.edgeThickness)
    edges[2]:SetPoint("BOTTOMLEFT", DL_EdgeGlow, "BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", DL_EdgeGlow, "BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(DL_EdgeGlowSettings.edgeThickness)
    edges[3]:SetPoint("TOPLEFT", DL_EdgeGlow, "TOPLEFT", 0, -DL_EdgeGlowSettings.edgeThickness)
    edges[3]:SetPoint("BOTTOMLEFT", DL_EdgeGlow, "BOTTOMLEFT", 0, DL_EdgeGlowSettings.edgeThickness)
    edges[3]:SetWidth(DL_EdgeGlowSettings.edgeThickness)
    edges[4]:SetPoint("TOPRIGHT", DL_EdgeGlow, "TOPRIGHT", 0, -DL_EdgeGlowSettings.edgeThickness)
    edges[4]:SetPoint("BOTTOMRIGHT", DL_EdgeGlow, "BOTTOMRIGHT", 0, DL_EdgeGlowSettings.edgeThickness)
    edges[4]:SetWidth(DL_EdgeGlowSettings.edgeThickness)
    
    DL_EdgeGlow.edges = edges
    return DL_EdgeGlow
end

local function ShowEdgeGlow(color)
    local glow = CreateEdgeGlow()
    local settings = DL_EdgeGlowSettings
    local flashColor = color or { r = 1, g = 0, b = 0, a = 0.7 }
    
    for i = 1, 4 do
        glow.edges[i]:SetTexture(flashColor.r, flashColor.g, flashColor.b, flashColor.a)
        glow.edges[i]:SetAlpha(0)
    end
    
    local flashCount = settings.flashCount
    local startTime = GetTime()
    local isFadingIn = true
    local isHolding = false
    
    glow:SetScript("OnUpdate", function(self, elapsed)
        local currentTime = GetTime() - startTime
        local progress
        
        if isFadingIn then
            progress = currentTime / settings.fadeInDuration
            if progress >= 1 then
                progress = 1
                isFadingIn = false
                startTime = GetTime()
                isHolding = true
            end
            for i = 1, 4 do
                self.edges[i]:SetAlpha(progress * flashColor.a)
            end
        elseif isHolding then
            if currentTime >= settings.holdDuration then
                isHolding = false
                startTime = GetTime()
            end
        else
            progress = 1 - (currentTime / settings.fadeOutDuration)
            if progress <= 0 then
                progress = 0
                flashCount = flashCount - 1
                if flashCount > 0 then
                    startTime = GetTime() + settings.flashDelay
                    isFadingIn = true
                else
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                end
            end
            for i = 1, 4 do
                self.edges[i]:SetAlpha(progress * flashColor.a)
            end
        end
    end)
    
    glow:Show()
end

function ShowDeathOverlay(color)
    local flashColor = (HCBL_Settings and HCBL_Settings.fontColor) or color or { r = 1, g = 0, b = 0, a = 0.7 }
    ShowEdgeGlow(flashColor)
end

--

local function SaveFramePositionAndSize(frame)
    if frame == widgetInstance.mainWnd then
        local point, _, relativePoint, xOfs, yOfs = frame:GetPoint()
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
        print("LibDBIcon-1.0 не загружена. Иконка на миникарте не будет отображаться")
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
                Debug("Обработан useLibWho", name, " Гильдия", guild)
                break
            end
        end
    else
        for i = 1, GetNumWhoResults() do
            name, guild = GetWhoInfo(i)
            if name and strlower(name) == strlower(pendingRequest) then
                guild = guild or ""
                Debug("Обработан GetWhoInfo", name, " Гильдия", guild)
                break
            end
        end
    end
    
    if name then
        guildCache[name] = guild or ""
        Debug("Добавлено в кэш гильдий:", name, "->", guildCache[name])
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

local function GetCachedGuild(playerName)
    if not playerName then return "" end
    
    if guildCache[playerName] ~= nil then
        Debug("Гильдия из кэша для", playerName, ":", guildCache[playerName])
        return guildCache[playerName]
    end
    
    if IsInGuild() then
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, online, _, _, _, _, _, _, guild = GetGuildRosterInfo(i)
            if name and name == playerName then
                guildCache[playerName] = guild or ""
                Debug("Гильдия из гильд-листа для", playerName, ":", guildCache[playerName])
                return guildCache[playerName]
            end
        end
    end
    
    Debug("Гильдия не найдена для", playerName)
    return ""
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

local function UpdateGuildMembers() -- проверка только из онлайна  
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
                                          Utils.ColorWord("[" .. Utils.TimeNow() .. "]", "Белый")
    local name = Utils.ColorWord(data.name, Utils.classes[data.classID])
    local coloredRace, race, side = Utils.GetRaceData(data.raceID)
    local level = data.level >= 70 and Utils.ColorWord(data.level .. " ур.", "Фиолетовый") or
                  data.level >= 60 and Utils.ColorWord(data.level .. " ур.", "Синий") or
                  data.level .. " ур."
    local cause = Utils.causes[data.causeID] or data.causeID
    
    local guildInfo = ""
    if Utils.IsPlayerInGuild(data.name) then
        guildInfo = " |cFF00FF00[Гильдия]|r"
        Debug("Плашка [Гильдия] установлена (Death)")
        ShowDeathOverlay(HCBL_Settings and HCBL_Settings.fontColor)
        Debug("[Флеш окно] Событие смерти игрока из гильдии")
    end
    
    local guildDisplay = ""
    if parseGuild and parseGuild ~= "" then
        guildDisplay = " |cffffcc00<"..parseGuild..">|r"
    end
    
    Debug("Обработка FormatData (Death)")
    local mainStr = string.format("%s %s %s %s %s %s", timeData, name, coloredRace, level, guildInfo, guildDisplay)
    local tooltip = string.format(
        "%s\nИмя: %s\nУровень: %d\nКласс: %s\nРаса: %s\nФракция: %s\nЛокация: %s\nПричина: %s",
        Utils.ColorWord("Провален", "Красный"), data.name, data.level, Utils.classes[data.classID], race, side, data.locationStr, cause)
    
    if data.causeID == 7 then
        tooltip = tooltip .. "\nОт: " .. data.enemyName .. " " .. data.enemyLevel .. "-го уровня"
    end
	
    if parseGuild and parseGuild ~= "" then
        tooltip = tooltip .. "\nГильдия: " .. parseGuild
    end
    
    local class = Utils.classes[data.classID] or "Unknown" 
    return mainStr, tooltip, data.name, class, side
end

local function FormatCompletedChallengeData(data)
    local timeData = Utils.ColorWord("[" .. Utils.TimeNow() .. "]", "Золотой")
    local name = Utils.ColorWord(data.name, Utils.classes[data.classID])
    local coloredRace, race, side = Utils.GetRaceData(data.raceID)
    
    local guildInfo = ""
    if Utils.IsPlayerInGuild(data.name) then
        guildInfo = " |cFF00FF00[Гильдия]|r"
        Debug("Плашка [Гильдия] установлена (Complete)")
    end
    
    local guildDisplay = ""
    if parseGuild and parseGuild ~= "" then
        guildDisplay = " |cffffcc00<"..parseGuild..">|r"
    end
    
    Debug("Обработка FormatCompletedChallengeData")
    local mainStr = string.format("%s %s %s %s %s %s", timeData, name, coloredRace, Utils.ColorWord("завершил испытание!", "Золотой"), guildInfo, guildDisplay)
    local tooltip = string.format("%s\nИмя: %s\nКласс: %s\nРаса: %s\nФракция: %s",
        Utils.ColorWord("Пройден", "Зеленый"), data.name, Utils.classes[data.classID], race, side)
    
    if parseGuild and parseGuild ~= "" then
        tooltip = tooltip .. "\nГильдия: " .. parseGuild
    end
    
    return mainStr, tooltip, data.name, side
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
    local statsWidth = screenWidth * 0.8
    local statsHeight = screenHeight * 0.65
    local initialWidthStat = screenWidth * 0.6
    local initialHeightStat = screenHeight * 0.5
    local FULL_WINDOW_SPLIT = 0.6
    
    instance.mainWnd = CreateFrame("Frame", "DLDialogFrame_v2", UIParent)
    -- instance.mainWnd:SetFrameStrata("DIALOG")
    
    instance.mainWnd:SetSize(initialWidth, initialHeight)
    if DeathLoggerDB.point and type(DeathLoggerDB.point) == "table" then
        instance.mainWnd:SetPoint(
            DeathLoggerDB.point[1] or "CENTER",
            UIParent,
            DeathLoggerDB.point[3] or "CENTER",
            DeathLoggerDB.point[4] or 0,
            DeathLoggerDB.point[5] or 0
        )
    else
        instance.mainWnd:SetPoint(
            DeathLoggerDB.point or "CENTER",
            UIParent,
            DeathLoggerDB.relativePoint or "CENTER",
            DeathLoggerDB.xOfs or 0,
            DeathLoggerDB.yOfs or 0
        )
    end
    
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
    instance.mainWnd:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)
    
    local separator = instance.mainWnd:CreateTexture(nil, "ARTWORK")
    separator:SetTexture(1, 1, 1, 0.5)
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", instance.mainWnd.title, "BOTTOMLEFT", 0, -8)
    separator:SetPoint("TOPRIGHT", -10, -8)
    
    instance.currentFilterId = DeathLoggerDB.currentFilterId or FILTERS.ALL
    
    -- статистика
    instance.fullWindow = CreateFrame("Frame", "DLStatsParentFrame_v2", UIParent)
    instance.fullWindow:SetSize(statsWidth, statsHeight)
    instance.fullWindow:SetPoint("CENTER")
    instance.fullWindow:EnableKeyboard(true)
    instance.fullWindow:Hide()
    instance.fullWindow:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        self:Hide()
        instance.mainWnd:Show()
        instance.toggleSizeButton:SetText("Статистика")
        isFullWindow = false
        end
    end)
    instance.fullWindow:SetScript("OnShow", function()
        if not instance.statsInstance then
            instance.statsInstance = Stats.new(instance.fullWindow)
        end
        instance.statsInstance:ClearContent()
        instance.statsInstance:UpdateStats()
        isFullWindow = false
    end)
    
    local closeButton = CreateFrame("Button", nil, instance.mainWnd, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -1, -1)
    closeButton:SetScript("OnClick", function() 
        instance:Hide()
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
            print("|cFF00FF00Death Logger|r: Список умерших сброшен")
        end,
        timeout = 20,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    instance.allianceBtn = instance:CreateFilterButton(
        "Interface\\Icons\\Achievement_PVP_A_A", 
        "Фильтр: Альянс + Нейтрал",
        function() instance:ApplyFilter(FILTERS.ALLIANCE) end,
        resetButton, "TOPLEFT", -5, 0
    )
    instance.allianceBtn.filterId = FILTERS.ALLIANCE
        
    instance.hordeBtn = instance:CreateFilterButton(
        "Interface\\Icons\\Achievement_PVP_H_H", 
        "Фильтр: Орда + Нейтрал", 
        function() instance:ApplyFilter(FILTERS.HORDE) end,
        instance.allianceBtn, "TOPLEFT", -5, 0
    )
    instance.hordeBtn.filterId = FILTERS.HORDE
        
    instance.allBtn = instance:CreateFilterButton(
        "Interface\\Icons\\Ability_dualwield", 
        "Фильтр: Все фракции",
        function() instance:ApplyFilter(FILTERS.ALL) end,
        instance.hordeBtn, "TOPLEFT", -5, 0
    )
    instance.allBtn.filterId = FILTERS.ALL
    
    instance.toggleSizeButton = CreateFrame("Button", nil, instance.mainWnd, "GameMenuButtonTemplate")
    instance.toggleSizeButton:SetSize(100, 22)
    instance.toggleSizeButton:SetPoint("TOPRIGHT", instance.allBtn, "TOPLEFT", -5, 0)
    instance.toggleSizeButton:SetText("Статистика")
    instance.toggleSizeButton:SetNormalFontObject("GameFontNormal")
    instance.toggleSizeButton:SetHighlightFontObject("GameFontHighlight")
    instance.toggleSizeButton:SetScript("OnClick", function()
        isFullWindow = not isFullWindow
        if isFullWindow then
            instance.fullWindow:Show()
            instance.mainWnd:Hide()
        else
            instance.fullWindow:Hide()
            instance.mainWnd:Show()
        end
    end)
    
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
    if DEBUG then print("[DeathLogger] Загружено записей:", #DeathLoggerDB.entries) end
    
    instance.textFrames = {}
    instance.previousEntry = nil
    instance.currentFilter = nil
    return instance
end

function DeathLogWidget:CreateFilterButton(texture, tooltip, onClickFunc, relativeTo, point, x, y)
    local button = CreateFrame("Button", nil, self.mainWnd)
    button:SetSize(22, 22)
    button:SetNormalTexture(texture)
    button:SetPoint("TOPRIGHT", relativeTo, point or "TOPLEFT", x or -5, y or 0)
    button:SetScript("OnClick", onClickFunc)
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
            print("[DEBUG] Имя игрока не найдено")
        end
        elseif button == "LeftButton" then
            if IsShiftKeyDown() then
                if self.playerName then
                    local messageSuffix = self.text:GetText():find("завершил") and " ГЦ" or " F"
                    ChatFrame_OpenChat("/g " .. self.playerName .. messageSuffix, DEFAULT_CHAT_FRAME)
                end
            else
                if self.playerName then
                    ChatFrame_SendTell(self.playerName)
                else
                    print("[DEBUG] Имя игрока не найдено. Невозможно открыть приватный чат")
                end
            end
        end
    end)
    return frame
end

--    entry.text:SetWidth(9999)

function DeathLogWidget:AddEntry(data, tooltip, faction, playerName, parseGuild, class, timestamp)
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
        ["Орда"] = "Interface\\Icons\\Achievement_PVP_H_H",
        ["Нейтрал"] = "Interface\\Icons\\Inv_misc_questionmark"
    })[faction] or "Interface\\Icons\\Inv_misc_questionmark"
    
    -- Debug("Обработка AddEntry")
    -- Debug("------------------")
    entry.text:SetText(data)
    entry.playerName = playerName
    entry.tooltip = tooltip
    entry.faction = faction
    entry.parseGuild = parseGuild
    entry.class = class
    entry.factionIcon:SetTexture(factionIcon)
    self:AddTooltip(entry, tooltip)
    
    local shouldShow = true
    
    if self.currentFilterId == FILTERS.ALLIANCE then
        shouldShow = faction == "Альянс" or faction == "Нейтрал"
    elseif self.currentFilterId == FILTERS.HORDE then
        shouldShow = faction == "Орда" or faction == "Нейтрал"
    end
    
    if shouldShow and DeathLoggerDB.guildOnly then
        shouldShow = Utils.IsPlayerInGuild(playerName)
    end
    
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

-- Дополнительно: добавить метод очистки пула либо проработать фоновую загрузку
function DeathLogWidget:ClearPool()
    if self.textFrames then
        for i = #self.textFrames, 1, -1 do
            local frame = self.textFrames[i]
            if frame then
                frame:Hide()
                if self.framePool then
                    table.insert(self.framePool, frame)
                end
            end
        end
        self.textFrames = {}
    end
    self.previousEntry = nil
    self.scrollChild:SetHeight(1)
    self.scrollFrame:UpdateScrollChildRect()
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

function DeathLogWidget:ApplyFilter(filterId)
    self.currentFilterId = filterId
    DeathLoggerDB.currentFilterId = filterId
    
    self.allBtn:SetAlpha(filterId == FILTERS.ALL and 1.0 or 0.5)
    self.allianceBtn:SetAlpha(filterId == FILTERS.ALLIANCE and 1.0 or 0.5)
    self.hordeBtn:SetAlpha(filterId == FILTERS.HORDE and 1.0 or 0.5)
    
    local filterFunc
    if filterId == FILTERS.ALLIANCE then
        filterFunc = function(entry) return entry.faction == "Альянс" or entry.faction == "Нейтрал" end
    elseif filterId == FILTERS.HORDE then
        filterFunc = function(entry) return entry.faction == "Орда" or entry.faction == "Нейтрал" end
    else
        filterFunc = function(entry) return true end
    end
    
    for _, frame in ipairs(self.textFrames) do
        local shouldShow = filterFunc(frame)
        
        if DeathLoggerDB.guildOnly then
            shouldShow = shouldShow and Utils.IsPlayerInGuild(frame.playerName)
        end
        
        frame:SetShown(shouldShow)
    end
    
    self:UpdateEntriesPosition()
end

function DeathLogWidget:Show()
    if isFullWindow then
        if self.statsInstance then
            self.statsInstance:UpdateStats()
        end
        self.fullWindow:Show()
        self.mainWnd:Hide()
    else
        if DeathLoggerDB.point then
            self.mainWnd:ClearAllPoints()
            -- обработка таблицы для первых версий аддона при переходе от нулевой (первой) к новой версии DL
            if type(DeathLoggerDB.point) == "table" then
                self.mainWnd:SetPoint(
                    DeathLoggerDB.point[1] or "CENTER",
                    UIParent,
                    DeathLoggerDB.point[3] or "CENTER",
                    DeathLoggerDB.point[4] or 0,
                    DeathLoggerDB.point[5] or 0
                )
            else
                -- нормальный случай 
                self.mainWnd:SetPoint(
                    DeathLoggerDB.point,
                    UIParent,
                    DeathLoggerDB.relativePoint,
                    DeathLoggerDB.xOfs,
                    DeathLoggerDB.yOfs
                )
            end
        end
        self.fullWindow:Hide()
        self.mainWnd:Show()
    end
    DeathLoggerDB.isShown = true
end

function DeathLogWidget:Hide()
    self.mainWnd:Hide()
    if self.fullWindow then
        self.fullWindow:Hide()
    end
    DeathLoggerDB.isShown = false
end

function DeathLogWidget:IsShown()
    return self.mainWnd:IsShown() or self.fullWindow:IsShown()
end

-- дата 

local function SaveEntry(data, tooltip, faction, playerName, parseGuild, class, timestamp)
    if not DeathLoggerDB.entries then DeathLoggerDB.entries = {} end
    
    if not playerName or playerName == "" or not data or data == "" then
        if DEBUG then
            print("|cff00ccff[DEBUG]|r Попытка сохранить невалидную запись")
        end
        return
    end
    
    local clean_data = data:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    
    -- добавляем запись в базу с позицией timestamp
    local newEntry = {
        data = data,
        tooltip = tooltip,
        faction = faction,
        playerName = playerName,
        parseGuild = parseGuild,
        class = class,
        timestamp = timestamp or time()
    }
    
    local insertIndex = 1
    for i, entry in ipairs(DeathLoggerDB.entries) do
        if (entry.timestamp or 0) < (newEntry.timestamp or 0) then
            insertIndex = i
            break
        else
            insertIndex = i + 1
        end
    end
    
    table.insert(DeathLoggerDB.entries, insertIndex, newEntry)
end

local function OnDeath(text)
    -- валидность на пустой текст от синхронизации
    if not text or type(text) ~= "string" then
        Debug("OnDeath received invalid text:", text)
        return
    end
    
    if IsInGuild() then
        UpdateGuildMembers()
    end
    
    local parseGuild = ""
    
    local dataMap = Utils.StringToMap(text)
    if not dataMap.name then
        return
    end
    
    -- проверка является ли умерший сам игрок и включена ли настройка
    if dataMap.name == UnitName("player") and DeathLoggerDB.announceDeathToGuild and IsInGuild() then
    Debug("Событие собственной смерти")
        local cause = Utils.causes[dataMap.causeID] or dataMap.causeID
        local message = string.format("%s (%d уровня) погиб в %s от %s", 
            dataMap.name, dataMap.level, dataMap.locationStr, cause)
        
        local cleanMessage = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        Debug("Пытаемся отправить сообщение:", cleanMessage)
        Debug("Длина сообщения:", string.len(cleanMessage))
        
        local success, err = pcall(SendChatMessage, cleanMessage, "GUILD")
        if success then
            Debug("Сообщение отправлено успешно")
        else
            Debug("Ошибка отправки:", err)
            local simpleMessage = string.format("%s погиб от %s в %s", 
                dataMap.name, cause, dataMap.locationStr)
            Debug("Сообщение в упрощенном варианте отправлено", simpleMessage)    
            SendChatMessage(simpleMessage, "GUILD")
        end
    end
    
    pendingRequest = dataMap.name
    RequestPlayerInfo(pendingRequest)
    
    local causeID = dataMap.causeID or 0
    if causeID < 0 or causeID > 11 then
        causeID = 10
    end
    
    HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or _G.deathIcons[0]
    Debug("[OnDeath] causeID:", causeID, "| Путь к иконке:",HCBL_Settings.currentDeathIcon)
    
    if HardcoreLossBanner and HardcoreLossBanner.CustomDeathIcon then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(HCBL_Settings.currentDeathIcon)
        Debug("[OnDeath] Баннер установлен")
    end
    
    local timerFrame = CreateFrame("Frame")
    local elapsedTime = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTime = elapsedTime + elapsed
        if elapsedTime >= 0.5 then
        local deadPlayerData, tooltip, playerName, class, side = FormatData(dataMap)
            local _, _, faction = Utils.GetRaceData(dataMap.raceID)
            local class = Utils.classes[dataMap.classID] or "Unknown"
            
            if widgetInstance then
                widgetInstance:AddEntry(deadPlayerData, tooltip, faction, playerName, parseGuild)
                widgetInstance:ApplyFilter(widgetInstance.currentFilterId)
                widgetInstance:UpdateEntriesPosition()
            end
            
            SaveEntry(deadPlayerData, tooltip, side, playerName, parseGuild, class, dataMap.timestamp)
            
            -- синхронизация
            if Sync and Sync.SaveEntryWithSync then
                dataMap.guild = GetCachedGuild(dataMap.name)
	            dataMap.timestamp = time()
                Sync:SaveEntryWithSync(dataMap)
            end
            
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function OnComplete(text)
    -- валидность на пустой текст от синхронизации
    if not text or type(text) ~= "string" then
        Debug("OnComplete received invalid text:", text)
        return
    end
    
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
    
    local causeID = 11
    if causeID < 0 or causeID > 11 then
        causeID = 10
    end
    
    HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or _G.deathIcons[0]
    Debug("[OnComplete] causeID:", causeID, "| Путь к иконке:",HCBL_Settings.currentDeathIcon)
    
    if HardcoreLossBanner and HardcoreLossBanner.CustomDeathIcon then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(HCBL_Settings.currentDeathIcon)
        Debug("[OnComplete] Баннер установлен")
    end
    
    local timerFrame = CreateFrame("Frame")
    local elapsedTime = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTime = elapsedTime + elapsed
        if elapsedTime >= 0.5 then
            local challengeCompletedData, tooltip, playerName, class, side = FormatCompletedChallengeData(dataMap)
            local _, _, faction = Utils.GetRaceData(dataMap.raceID)
            local class = Utils.classes[dataMap.classID] or "Unknown"
            
            if widgetInstance then
                widgetInstance:AddEntry(challengeCompletedData, tooltip, faction, playerName, parseGuild)
                widgetInstance:ApplyFilter(widgetInstance.currentFilterId)
                widgetInstance:UpdateEntriesPosition()
            end
            
            SaveEntry(challengeCompletedData, tooltip, faction, playerName, parseGuild, class, dataMap.timestamp)
            
            -- синхронизация
            if Sync and Sync.SaveEntryWithSync then
                dataMap.guild = GetCachedGuild(dataMap.name)
	            dataMap.timestamp = time()
                Sync:SaveEntryWithSync(dataMap)
            end
            
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function SortEntriesByTimestamp()
    if not DeathLoggerDB.entries or #DeathLoggerDB.entries <= 1 then
        return
    end
    
    table.sort(DeathLoggerDB.entries, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
end

local function InitWindow(shouldShow)
    if not _G.widgetInstance then
        _G.widgetInstance = DeathLogWidget.new()
    end
    if shouldShow then
        _G.widgetInstance:Show()
    else
        _G.widgetInstance:Hide()
    end
end

-- слеш команды

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

local function CleanupSyncData()
    if not (Sync and Sync.DEBUG) then
        if DeathLoggerDB.syncEntries then
            local count = #DeathLoggerDB.syncEntries
            DeathLoggerDB.syncEntries = {}
            if DEBUG then
                print("|cff00ccff[DEBUG]|r Очищено записей синхронизации: " .. count)
            end
        end
    else
        if DEBUG then
            print("|cff00ccff[DEBUG]|r Режим отладки Sync: данные НЕ очищаются")
        end
    end
end

-- сохранение загрузка запией

local function SaveEntriesOnLogout()
    isLoggingOut = true
    
    if DL_EdgeGlow then
        DL_EdgeGlow:Hide()
    end
    
    if widgetInstance and widgetInstance.currentFilterId then
        DeathLoggerDB.currentFilterId = widgetInstance.currentFilterId
        Debug("Фильтр сохранен при выходе:", DeathLoggerDB.currentFilterId)
    end
    
    if Sync and Sync.CleanupSyncData then
        Sync:CleanupSyncData()
    end
    
    guildCache = {}
    DeathLoggerDB.guildCache = guildCache
    Debug("Кэш гильдий очищен при выходе из игры")
    
    DeathLoggerDB.syncEnabled = DeathLoggerDB.syncEnabled
    DeathLoggerDB.autoSync = DeathLoggerDB.autoSync  
    DeathLoggerDB.syncNotifications = DeathLoggerDB.syncNotifications
    DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
    DeathLoggerDB.announceDeathToGuild = DeathLoggerDB.announceDeathToGuild or false
    DeathLoggerDB.isShown = widgetInstance and widgetInstance:IsShown() or false
    DeathLoggerDB.guildMembers = guildMembers
    DeathLoggerDB.minWidth = DeathLoggerDB.minWidth or 200
    DeathLoggerDB.minHeight = DeathLoggerDB.minHeight or 100
    DeathLoggerDB.width = DeathLoggerDB.width or DeathLoggerDB.minWidth
    DeathLoggerDB.height = DeathLoggerDB.height or DeathLoggerDB.minHeight
    DeathLoggerDB.HCBL_Settings = DeathLoggerDB.HCBL_Settings or {}
    Utils.CopyTable(HCBL_Settings, DeathLoggerDB.HCBL_Settings)
end

function LoadEntries()
    if DeathLoggerDB.entries and widgetInstance then
        table.sort(DeathLoggerDB.entries, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)
        
        widgetInstance:ClearPool()
        
        local totalEntries = #DeathLoggerDB.entries
        local maxEntriesToLoad = math.min(totalEntries, 777)
        
        for i = maxEntriesToLoad, 1, -1 do
            local entryData = DeathLoggerDB.entries[i]
            widgetInstance:AddEntry(entryData.data, entryData.tooltip, entryData.faction, entryData.playerName, entryData.parseGuild, entryData.class, entryData.timestamp)
        end
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
            DeathLoggerDB.announceDeathToGuild = DeathLoggerDB.announceDeathToGuild or false
            
            -- инициализация синхронизации
		    SortEntriesByTimestamp()
            if Sync and Sync.Init then
                Sync:Init(self)
            end
            -- 
            original_ChatFrame_OnHyperlinkShow = ChatFrame_OnHyperlinkShow
            ChatFrame_OnHyperlinkShow = NewChatFrame_OnHyperlinkShow
            self:UnregisterEvent("ADDON_LOADED")
            
            DeathLoggerDB.entries = DeathLoggerDB.entries or {}
            DeathLoggerDB.guildMembers = DeathLoggerDB.guildMembers or {}
            DeathLoggerDB.guildOnly = DeathLoggerDB.guildOnly or false
            DeathLoggerDB.currentFilterId = DeathLoggerDB.currentFilterId or FILTERS.ALL
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
                if widgetInstance.fullWindow then
                    widgetInstance.statsInstance = Stats.new(widgetInstance.fullWindow)
                end
            end
            
            LoadEntries()
            
            if DeathLoggerDB.currentFilterId then
                widgetInstance:ApplyFilter(DeathLoggerDB.currentFilterId)
            else
                widgetInstance:ApplyFilter(FILTERS.ALL)
            end
            if DeathLoggerDB.guildOnly then
                widgetInstance:ApplyFilter(widgetInstance.currentFilterId)
            end
            
            if DeathLoggerDB.isShown then
                widgetInstance:Show()
            else
                widgetInstance:Hide()
            end
            
            if DeathLoggerDB.isShown and DeathLoggerDB.statsShown then
                widgetInstance.fullWindow:Show()
                widgetInstance.mainWnd:Hide()
            end
            
            initMinimapButton()
            Options.CreateOptionsPanel()
            if HardcoreLossBanner then
                Options.UpdateBannerElements()
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
            Debug("[ASMSG_HARDCORE_DEATH] Обработка OnDeath", text)
        elseif prefix == "ASMSG_HARDCORE_COMPLETE" then
            OnComplete(text)
            local causeID = 11
            HCBL_Settings.currentDeathIcon = _G.deathIcons[causeID] or 11
            Debug("[ASMSG_HARDCORE_COMPLETE] Обработка OnComplete", text)
        elseif prefix == DeathLoggerSync.PREFIX then
            DeathLoggerSync:OnSyncMessage(prefix, text, channel, sender)
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
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        if (isLogin or isReload) and DeathLoggerDB.autoSync and DeathLoggerDB.syncEnabled and IsInGuild() then
            local delayFrame = CreateFrame("Frame")
            local elapsed = 0
            delayFrame:SetScript("OnUpdate", function(self, delta)
                elapsed = elapsed + delta
                if elapsed >= 3 then  -- 3 сек задержки
                    self:SetScript("OnUpdate", nil)
                    if DeathLoggerSync and DeathLoggerSync.RequestFullSync then
                        DeathLoggerSync:RequestFullSync()
                        Debug("автосинхронизация при входе в мир")
                    end
                end
            end)
        end
    elseif event == "PLAYER_LEAVING_WORLD" then
        local isLogout = ...
        if isLogout then
            isLoggingOut = true
            SaveEntriesOnLogout()
        else
            if DEBUG then
                Debug("переход между зонами - данные синхронизации сохраняются")
            end
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
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:SetScript("OnEvent", OnEvent)