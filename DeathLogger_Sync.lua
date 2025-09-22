-------------------------------------------------------------------------------------------------
-- Copyright 2024-2025 Lyubimov Vladislav (grifon7676@gmail.com)
-- Copyright 2025 Norzia (devilicip2@gmail.com) for sirus-wow
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the "Software"), to deal in the Software without
-- restriction, including without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or
-- substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-------------------------------------------------------------------------------------------------

local addonName = "DeathLogger"
local Utils = _G[addonName.."_Utils"]
local DeathLoggerSync = {}
local time = time
local date = date
_G.DeathLoggerSync = DeathLoggerSync
DeathLoggerSync.isLoggingOut = false
DeathLoggerSync.progressBar = nil
DeathLoggerSync.progressText = nil

DeathLoggerSync.PREFIX = "ASMSG_TOSEND_DL_SYNC"
DeathLoggerSync.VERSION = 3
DeathLoggerSync.THROTTLE = 1.5
DeathLoggerSync.lastSyncTime = 0
DeathLoggerSync.MAX_SYNC_ENTRIES = 200 -- максимальное количество записей для синхры

DeathLoggerSync.MSG_TYPE = {
    NEW_ENTRY = "N", -- новая запись
    REQUEST_FULL = "R", -- запрос полной истории
    FULL_ENTRY = "F", -- отправка одной записи
    COUNT = "C" -- количество записей
}

DeathLoggerDB.syncEntries = DeathLoggerDB.syncEntries or {}
DeathLoggerDB.syncIndex = DeathLoggerDB.syncIndex or {}

-- дебаг
local function DebugSync(...)
    if DeathLoggerSync.DEBUG then
        print("|cff00ccff[SYNC DEBUG]|r " .. strjoin(" ", tostringall(...)))
    end
end

function DeathLoggerSync:SetDebug(enabled)
    self.DEBUG = enabled
    DeathLoggerDB.syncDebug = enabled
    
    if enabled then
        print("|cff00ccff[SYNC]|r Режим отладки |cff00ff00ВКЛЮЧЕН|r")
        DebugSync("Отладка активирована")
    else
        print("|cff00ccff[SYNC]|r Режим отладки |cffff0000ВЫКЛЮЧЕН|r")
    end
end

function DeathLoggerSync:ToggleDebug()
    self:SetDebug(not self.DEBUG)
end

local function SortMainEntries()
    if not DeathLoggerDB.entries or #DeathLoggerDB.entries <= 1 then
        return
    end
    
    table.sort(DeathLoggerDB.entries, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
end

-- модуль синхронизации
function DeathLoggerSync:Init(mainAddon)
    self.main = mainAddon
    self.Utils = mainAddon.Utils
    self.DEBUG = DeathLoggerDB.syncDebug or false
    
    if not DeathLoggerDB.syncEntries or type(DeathLoggerDB.syncEntries) ~= "table" then
        DeathLoggerDB.syncEntries = {}
        DebugSync("syncEntries не существует, инициализируем пустой таблицей")
    end
    
    if not DeathLoggerDB.syncIndex or type(DeathLoggerDB.syncIndex) ~= "table" then
        DeathLoggerDB.syncIndex = {}
        DebugSync("syncIndex не существует, инициализируем пустой таблицей")
    end
    
    SortMainEntries()

    self.eventFrame = self.eventFrame or CreateFrame("Frame")
    self.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, message, channel, sender = ...
            if prefix == self.PREFIX then
                self:OnSyncMessage(prefix, message, channel, sender)
            end
        end
    end)
    
    self:BuildSyncIndex()
end

local function CreateDLNotificationsystem()
    if DeathLoggerSync.DLNotifications then return end
    
    local DLoggernotificationFrame = CreateFrame("Frame", "DLPremiumDLoggernotificationFrame", UIParent)
    DLoggernotificationFrame:SetSize(380, 100)
    DLoggernotificationFrame:SetPoint("TOP", 0, -120)
    DLoggernotificationFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    DLoggernotificationFrame:SetAlpha(0)
    DLoggernotificationFrame:SetScale(0.8)
    DLoggernotificationFrame:Hide()
    
    DLoggernotificationFrame.glow = DLoggernotificationFrame:CreateTexture(nil, "ARTWORK")
    DLoggernotificationFrame.glow:SetPoint("CENTER")
    DLoggernotificationFrame.glow:SetSize(400, 110)
    DLoggernotificationFrame.glow:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTabGlow")
    DLoggernotificationFrame.glow:SetTexCoord(0.2, 0.8, 0.2, 0.8)
    DLoggernotificationFrame.glow:SetVertexColor(0.3, 0.5, 1, 0.4)
    DLoggernotificationFrame.glow:SetBlendMode("ADD")
    
    DLoggernotificationFrame.title = DLoggernotificationFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    DLoggernotificationFrame.title:SetPoint("TOP", 0, -15)
    DLoggernotificationFrame.title:SetTextColor(1, 0.8, 0.2, 1)
    DLoggernotificationFrame.title:SetJustifyH("CENTER")
    
    DLoggernotificationFrame.text = DLoggernotificationFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    DLoggernotificationFrame.text:SetPoint("TOP", DLoggernotificationFrame.title, "BOTTOM", 0, -5)
    DLoggernotificationFrame.text:SetWidth(300)
    DLoggernotificationFrame.text:SetJustifyH("CENTER")
    DLoggernotificationFrame.text:SetTextColor(0.9, 0.9, 1, 1)
    
    DLoggernotificationFrame.progressBar = CreateFrame("StatusBar", nil, DLoggernotificationFrame)
    DLoggernotificationFrame.progressBar:SetPoint("CENTER", DLoggernotificationFrame.text, "BOTTOM", 0, -16)
    DLoggernotificationFrame.progressBar:SetSize(300 - 8, 12)
    DLoggernotificationFrame.progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    DLoggernotificationFrame.progressBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND")
    DLoggernotificationFrame.progressBar:SetStatusBarColor(0, 0.6, 0, 1)
    DLoggernotificationFrame.progressBar:SetMinMaxValues(0, 100)
    DLoggernotificationFrame.progressBar:SetValue(0)
	
    DLoggernotificationFrame.progressBar.background = CreateFrame("Frame", nil, DLoggernotificationFrame.progressBar)
    DLoggernotificationFrame.progressBar.background:SetPoint("TOPLEFT", -4, 4)
    DLoggernotificationFrame.progressBar.background:SetPoint("BOTTOMRIGHT", 4, -4)
    DLoggernotificationFrame.progressBar.background:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, 
        tileSize = 16, 
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    DLoggernotificationFrame.progressBar.background:SetBackdropColor(0, 0, 0, 0.6)
    DLoggernotificationFrame.progressBar.background:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    DLoggernotificationFrame.progressBar.background:SetFrameLevel(0)
    
    DLoggernotificationFrame.progressText = DLoggernotificationFrame.progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    DLoggernotificationFrame.progressText:SetPoint("CENTER")
    DLoggernotificationFrame.progressText:SetText("Синхронизация 0%")
    
    DeathLoggerSync.DLNotifications = DLoggernotificationFrame
end

function DeathLoggerSync:UpdateProgressBar(progress)
    if self.DLNotifications and self.DLNotifications:IsShown() and self.DLNotifications.progressBar then
        self.DLNotifications.progressBar:SetValue(progress)
        self.DLNotifications.progressText:SetText(string.format("Синхронизация %d%%", progress))
        
        if self.DLNotifications.startTime then
            self.DLNotifications.startTime = GetTime()
            self.DLNotifications.duration = 15.0
        end
    end
end

-- анимация
local function AnimateFrameIn(frame, duration)
    duration = duration or 0.3
    frame:Show()
    frame:SetAlpha(0)
    frame:SetScale(0.8)
    
    local startTime = GetTime()
    local animTimer = CreateFrame("Frame")
    animTimer:SetScript("OnUpdate", function(self, elapsed)
        local progress = (GetTime() - startTime) / duration
        
        if progress >= 1 then
            frame:SetAlpha(1)
            frame:SetScale(1)
            self:SetScript("OnUpdate", nil)
        else
            frame:SetAlpha(progress)
            frame:SetScale(0.8 + (0.2 * progress))
        end
    end)
end

local function AnimateFrameOut(frame, duration, onComplete)
    duration = duration or 4
    local startAlpha = frame:GetAlpha()
    
    local animTimer = CreateFrame("Frame")
    animTimer:SetScript("OnUpdate", function(self, elapsed)
        local progress = (GetTime() - (frame.startTime or GetTime())) / duration
        
        if progress >= 1 then
            frame:SetAlpha(0)
            if onComplete then onComplete() end
            self:SetScript("OnUpdate", nil)
        else
            frame:SetAlpha(startAlpha * (1 - progress))
        end
    end)
end

local function ShowNotification(title, message, duration, progress)
    duration = duration or 10.0
    
    if not DeathLoggerDB.syncNotifications then
        return
    end
    
    if not DeathLoggerSync.DLNotifications then
        CreateDLNotificationsystem()
    end
    
    local frame = DeathLoggerSync.DLNotifications
    
    if frame:IsShown() and frame.progressBar:IsShown() and progress == nil then
        DebugSync("Прогресс-бар активен, пропускаем обычное уведомление")
        return
    end
    
    frame.title:SetText(title)
    frame.text:SetText(message)
    
    if progress then
        frame.progressBar:SetValue(progress)
        frame.progressText:SetText(string.format("%d%%", progress))
        frame.progressBar:Show()
        frame.progressText:Show()
    else
        frame.progressBar:Hide()
        frame.progressText:Hide()
    end
    
    frame.startTime = GetTime()
    frame.duration = duration
    
    if not frame:IsShown() then
        AnimateFrameIn(frame, 0.3)
    end
    
    if not DeathLoggerSync.NotificationTimer then
        DeathLoggerSync.NotificationTimer = CreateFrame("Frame")
    end
    
    DeathLoggerSync.NotificationTimer:SetScript("OnUpdate", function(self, elapsed)
        if frame:IsShown() and frame.startTime then
            local elapsedTime = GetTime() - frame.startTime
            if elapsedTime >= frame.duration then
                AnimateFrameOut(frame, 2, function()
                    frame:Hide()
                    frame.startTime = nil
                end)
            end
        end
    end)
end

local function ShowSyncRequestNotification()
    ShowNotification("Запрос истории", "Запрос данных о смертях и синхронизации отправлен", 10)
end

local function ShowSyncCompleteNotification()
    if DeathLoggerSync.DLNotifications and DeathLoggerSync.DLNotifications:IsShown() then
        AnimateFrameOut(DeathLoggerSync.DLNotifications, 0.5, function()
            DeathLoggerSync.DLNotifications:Hide()
            ShowNotification("Синхронизация", "История смертей успешно отправлена", 3.5)
        end)
    else
        ShowNotification("Синхронизация", "История смертей успешно отправлена", 3.5)
    end
end

local function ShowNewEntryNotification(sender, playerName)
    if DeathLoggerSync.DLNotifications and DeathLoggerSync.DLNotifications:IsShown() and 
       DeathLoggerSync.DLNotifications.progressBar:IsShown() then
        DebugSync("Прогресс-бар активен, пропускаем уведомление о новой записи")
        return
    end
    
    ShowNotification("Новая запись", string.format("Получена запись от |cffFFD100%s|r: %s", sender, playerName), 4.0)
end

local function ShowSyncProgressNotification(title, message, progress, duration)
    duration = duration or 60.0
    ShowNotification(title, message, duration, progress)
end

function DeathLoggerSync:GetIndexSize()
    local count = 0
    for _ in pairs(DeathLoggerDB.syncIndex or {}) do
        count = count + 1
    end
    return count
end

-- очистка данных синхронизации
function DeathLoggerSync:CleanupSyncData()
    if self.DEBUG then
        DebugSync("Режим отладки: данные синхронизации НЕ очищаются")
        DebugSync("Всего записей в sync базе:", #DeathLoggerDB.syncEntries)
        DebugSync("Размер индекса:", self:GetIndexSize())
        return
    end
    
    local count = #DeathLoggerDB.syncEntries
    DeathLoggerDB.syncEntries = {}
    DeathLoggerDB.syncIndex = {}
    
    if DeathLoggerDB.syncNotifications then
        print("|cff00ccff[DeathLogger]|r Очищено " .. count .. " записей синхронизации")
    end
end

function DeathLoggerSync:OnLogout()
    if self.isLoggingOut and not self.DEBUG then
        self:CleanupSyncData()
        DebugSync("Данные синхронизации очищены при выходе")
        self.isLoggingOut = false
        if self.DLoggernotificationFrame then
            self.DLoggernotificationFrame:Hide()
            self.DLoggernotificationFrame = nil
        end
        
    elseif self.DEBUG then
        DebugSync("Режим отладки: данные сохранены при выходе")
    end
end

-- индекс для быстрого поиска дубликатов
function DeathLoggerSync:BuildSyncIndex()
    DeathLoggerDB.syncIndex = {}
    
    if not DeathLoggerDB.syncEntries or type(DeathLoggerDB.syncEntries) ~= "table" then
        DeathLoggerDB.syncEntries = {}
        DebugSync("syncEntries не существует, инициализируем пустой таблицей")
        return
    end
    
    for _, entry in ipairs(DeathLoggerDB.syncEntries) do
        if entry.playerName and entry.class and entry.factionID then
            local key = self:GetDuplicateKey(entry)
            DeathLoggerDB.syncIndex[key] = true
        end
    end
    
    DebugSync("Индекс построен. Записей в индексе:", self:GetIndexSize())
end

-- проверка валидности записи
function DeathLoggerSync:IsValidEntry(entryData)
    if not entryData then
        DebugSync("Запись невалидна: entryData is nil")
        return false
    end
    
    if not entryData.playerName or entryData.playerName == "" then
        DebugSync("Запись невалидна: отсутствует имя игрока")
        return false
    end
    
    if not entryData.class or entryData.class == "" then
        DebugSync("Запись невалидна: отсутствует класс")
        return false
    end
    
    if entryData.causeID == 0 then
        DebugSync("Запись валидна (завершение испытания):", entryData.playerName)
        return true
    end
    
    if not entryData.level or entryData.level == 0 then
        DebugSync("Запись невалидна: отсутствует уровень")
        return false
    end
    
    if not entryData.locationStr or entryData.locationStr == "" then
        DebugSync("Запись невалидна: отсутствует локация")
        return false
    end
    
    if entryData.causeID == 7 then
        if not entryData.enemyName or entryData.enemyName == "" then
            DebugSync("Запись невалидна: убийство без имени врага")
            return false
        end
    end
    
    -- DebugSync("Запись валидна:", entryData.playerName)
    return true
end

-- сериализация для сообщений
function DeathLoggerSync:SerializeDeathData(entryData, msgType)
    if not entryData or not self:IsValidEntry(entryData) then 
        DebugSync("Ошибка сериализации: невалидные данные")
        return nil 
    end
    
    msgType = msgType or self.MSG_TYPE.NEW_ENTRY
    
    local classID = entryData.classID or Utils:GetClassIDByName(entryData.class or "") or 0
    local guildName = entryData.guild or ""
    local timestamp = entryData.timestamp or time()
    
    if entryData.causeID == 0 then
        local syncData = string.format("%s:%d:%d:%d:%d::%d:%d",
            entryData.playerName or "",
            entryData.raceID or 0,
            entryData.factionID or 0,
            classID,
            entryData.level or 0,
            entryData.causeID or 0,
            timestamp
        )
        
        local finalMessage = string.format("v=%d|t=%s|d=%s|g=%s",
            self.VERSION,
            msgType,
            syncData,
            guildName
        )
        
        -- DebugSync("Сериализованы данные завершения испытания:", finalMessage)
        return finalMessage
    end
    
    local syncData = string.format("%s:%d:%d:%d:%d:%s:%d:%d",
        entryData.playerName or "",
        entryData.raceID or 0,
        entryData.factionID or 0,
        classID,
        entryData.level or 0,
        entryData.locationStr or "",
        entryData.causeID or 0,
        timestamp
    )
    
    if entryData.causeID == 7 then
        syncData = syncData .. string.format(":%s:%d",
            entryData.enemyName or "",
            entryData.enemyLevel or 0
        )
    end
    
    local finalMessage = string.format("v=%d|t=%s|d=%s|g=%s",
        self.VERSION,
        msgType,
        syncData,
        guildName
    )
    
    -- DebugSync("Сериализованные данные:", finalMessage)
    return finalMessage
end

-- десериализация сообщения
function DeathLoggerSync:DeserializeDeathData(message)
    -- DebugSync("Десериализация сообщения:", message)
    
    local version, msgType, dataStr, guildName
    for part in message:gmatch("([^|]+)") do
        local k, v = part:match("^([^=]+)=(.+)$")
        if k == "v" then version = tonumber(v) end
        if k == "t" then msgType = v end
        if k == "d" then dataStr = v end
        if k == "g" then guildName = v end
        if version and msgType and dataStr and guildName ~= nil then break end
    end
    
    if not version or version ~= self.VERSION then
        DebugSync("Несовместимая версия:", version, "ожидалась:", self.VERSION)
        return nil
    end
    
    if msgType ~= self.MSG_TYPE.NEW_ENTRY and msgType ~= self.MSG_TYPE.FULL_ENTRY then
        DebugSync("Неизвестный тип сообщения:", msgType)
        return nil
    end
    
    if not dataStr then
        DebugSync("Нет данных в сообщении")
        return nil
    end
    
    local parts = {}
    for part in dataStr:gmatch("([^:]+)") do
        table.insert(parts, part)
    end
    
    local isTrialCompletion = (#parts == 8 and parts[6] == "") or (#parts == 7 and not parts[6]:match("%d"))
    
    if isTrialCompletion then
        local entryData = {
            playerName = parts[1],
            raceID = tonumber(parts[2]) or 0,
            factionID = tonumber(parts[3]) or 0,
            classID = tonumber(parts[4]) or 0,
            class = Utils.classes[tonumber(parts[4]) or 0] or "Unknown",
            level = tonumber(parts[5]) or 0,
            locationStr = "",
            causeID = 0,
            timestamp = tonumber(parts[8]) or time(),
            guild = guildName ~= "" and guildName or nil,
            msgType = msgType
        }
        
        -- DebugSync("Десериализовано завершение испытания:", entryData.playerName, "Тип:", msgType)
        return entryData
    else
        local hasTimestamp = #parts >= 8
        local minParts = hasTimestamp and 8 or 7
        
        if #parts < minParts then
            DebugSync("Недостаточно данных в сообщении:", #parts)
            return nil
        end
        
        local classID = tonumber(parts[4]) or 0
        local className = Utils.classes[classID] or "Unknown"
        
        local entryData = {
            playerName = parts[1],
            raceID = tonumber(parts[2]) or 0,
            factionID = tonumber(parts[3]) or 0,
            classID = classID,
            class = className,
            level = tonumber(parts[5]) or 0,
            locationStr = parts[6],
            causeID = tonumber(parts[7]) or 0,
            timestamp = hasTimestamp and tonumber(parts[8]) or time(),
            guild = guildName ~= "" and guildName or nil,
            msgType = msgType
        }
        
        if entryData.causeID == 7 then
            local mobIndex = hasTimestamp and 9 or 8
            if #parts >= mobIndex + 1 then
                entryData.enemyName = parts[mobIndex]
                entryData.enemyLevel = tonumber(parts[mobIndex + 1]) or 0
            end
        end
        
        -- DebugSync("Десериализована стандартная запись:", entryData.playerName, "Тип:", msgType)
        return entryData
    end
end

-- проверка на дубликат class+faction+playerName  -- излишне
-- function DeathLoggerSync:IsDuplicateByNameAndClass(entryData)
    -- if not DeathLoggerDB.entries or #DeathLoggerDB.entries == 0 then
        -- DebugSync("Основной список пуст, дубликатов нет")
        -- return false
    -- end
    
    -- local newName = strlower(entryData.playerName or "")
    -- local newClass = strlower(entryData.class or "")
    
    -- DebugSync("Поиск дубликата для:", newName, "Класс:", newClass)
    -- DebugSync("Всего записей в основном списке:", #DeathLoggerDB.entries)
    
    -- for i, existingEntry in ipairs(DeathLoggerDB.entries) do
        -- if existingEntry and existingEntry.playerName then
            -- local existingName = strlower(existingEntry.playerName or "")
            -- local existingClass = strlower(existingEntry.class or "")
            
            -- if existingName == newName and existingClass == newClass then
                -- DebugSync("ДУБЛИКАТ НАЙДЕН в записи", i, ":", entryData.playerName)
                -- return true
            -- end
        -- end
    -- end
    
    -- DebugSync("Дубликатов не найдено для:", entryData.playerName)
    -- return false
-- end

-- проверка нв дубликат в основном списке
function DeathLoggerSync:IsDuplicateInMainList(entryData)
    if not DeathLoggerDB.entries or #DeathLoggerDB.entries == 0 then
        DebugSync("Основной список пуст, дубликатов нет")
        return false
    end
    
    local newName = strlower(entryData.playerName or "")
    local newClass = strlower(entryData.class or "")
    
    -- DebugSync("Поиск дубликата в основном списке для:", newName, "Класс:", newClass)
    -- DebugSync("Всего записей в основном списке:", #DeathLoggerDB.entries)
    
    for i, existingEntry in ipairs(DeathLoggerDB.entries) do
        if existingEntry and existingEntry.playerName then
            local existingName = strlower(existingEntry.playerName or "")
            local existingClass = strlower(existingEntry.class or "")
            
            if existingName == newName and existingClass == newClass then
                -- DebugSync("ДУБЛИКАТ НАЙДЕН в основном списке", i, ":", entryData.playerName)
                return true
            end
        end
    end
    
    -- DebugSync("Дубликатов в основном списке не найдено для:", entryData.playerName)
    return false
end

-- проверка на дубликат в sync

function DeathLoggerSync:IsDuplicateInSyncDB(entryData)
    if not DeathLoggerDB.syncIndex then 
        DeathLoggerDB.syncIndex = {}
        DebugSync("Индекс не инициализирован, инициализируем")
        return false 
    end
    
    local key = self:GetDuplicateKey(entryData)
    local isDuplicate = DeathLoggerDB.syncIndex[key] == true
    
    -- DebugSync("Проверка дубликата в sync базе:", entryData.playerName, "Ключ:", key, "Дубликат:", isDuplicate)
    
    return isDuplicate
end

function DeathLoggerSync:AddToIndex(entryData)
    if not DeathLoggerDB.syncIndex then
        DeathLoggerDB.syncIndex = {}
    end
    
    local key = self:GetDuplicateKey(entryData)
    DeathLoggerDB.syncIndex[key] = true
    
    -- DebugSync("Добавлено в индекс:", key)
end

-- добавление записи в sync базу
function DeathLoggerSync:AddToSyncDB(entryData)
    if not DeathLoggerDB.syncEntries then
        DeathLoggerDB.syncEntries = {}
    end
    
    if self:IsDuplicateInSyncDB(entryData) then
        -- DebugSync("Запись уже есть в sync базе, не добавляем:", entryData.playerName)
        return false
    end
    
    table.insert(DeathLoggerDB.syncEntries, 1, entryData)
    self:AddToIndex(entryData)
    
    if #DeathLoggerDB.syncEntries > self.MAX_SYNC_ENTRIES then
        local removedEntry = table.remove(DeathLoggerDB.syncEntries)
        if removedEntry then
            local oldKey = self:GetDuplicateKey(removedEntry)
            DeathLoggerDB.syncIndex[oldKey] = nil
        end
    end
    
    -- DebugSync("Добавлено в sync базу. Всего записей:", #DeathLoggerDB.syncEntries)
    return true
end

function DeathLoggerSync:AddToMainList(entryData)
    if not DeathLoggerDB.entries then
        DeathLoggerDB.entries = {}
    end
    
    if self:IsDuplicateInMainList(entryData) then
        -- DebugSync("Запись уже есть в основном списке, не добавляем:", entryData.playerName)
        return false
    end
    
    local formattedData, tooltip, playerName, class, side = self:FormatEntryForMainUI(entryData)
    
    if formattedData then
        local mainEntry = {
            data = formattedData,
            tooltip = tooltip,
            faction = side,
            playerName = playerName,
            parseGuild = entryData.guild or "",
            class = class,
            timestamp = entryData.timestamp or time()
        }
        
        local insertIndex = 1
        for i, existingEntry in ipairs(DeathLoggerDB.entries) do
            if (existingEntry.timestamp or 0) < (mainEntry.timestamp or 0) then
                insertIndex = i
                break
            else
                insertIndex = i + 1
            end
        end
        
        table.insert(DeathLoggerDB.entries, insertIndex, mainEntry)
        
        if widgetInstance then
            widgetInstance:ClearPool()
            LoadEntries()
        end
        
        -- DebugSync("Добавлено в основной список. Всего записей:", #DeathLoggerDB.entries)
        return true
    end
    
    return false
end

function DeathLoggerSync:SortMainEntries()
    if not DeathLoggerDB.entries or #DeathLoggerDB.entries <= 1 then
        return
    end
    
    table.sort(DeathLoggerDB.entries, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)
end

-- запросы 
function DeathLoggerSync:SyncNewEntry(entryData)
    DebugSync("Попытка синхронизации записи:", entryData.playerName)
    DebugSync("В гильдии:", IsInGuild())
    DebugSync("Синхронизация включена:", DeathLoggerDB.syncEnabled)
    
    if not IsInGuild() or not DeathLoggerDB.syncEnabled then
        DebugSync("Отправка отменена: не в гильдии или синхронизация отключена")
        return
    end
    
    if not self:IsValidEntry(entryData) then
        DebugSync("Отправка отменена: невалидная запись")
        return
    end
    
    local currentTime = GetTime()
    if currentTime - self.lastSyncTime < self.THROTTLE then
        DebugSync("Троттлинг, слишком рано после последней отправки")
        return
    end
    
    local message = self:SerializeDeathData(entryData)
    if message then
        SendAddonMessage(self.PREFIX, message, "GUILD")
        self.lastSyncTime = currentTime
        -- DebugSync("Отправлена запись:", entryData.playerName, "Канал: GUILD")
    else
        DebugSync("Ошибка сериализации, запись не отправлена")
    end
end

function DeathLoggerSync:RequestFullSync()
    if not IsInGuild() or not DeathLoggerDB.syncEnabled then
        DebugSync("Запрос отменен: не в гильдии или синхронизация отключена")
        return 
    end
    
    local message = string.format("v=%d|t=%s", 
        self.VERSION, self.MSG_TYPE.REQUEST_FULL)
    
    SendAddonMessage(self.PREFIX, message, "GUILD")
    
    DebugSync("Отправлен запрос полной истории:", message)
    
    if DeathLoggerDB.syncNotifications then
        ShowSyncRequestNotification()
    end
end

function DeathLoggerSync:OnSyncMessage(prefix, message, channel, sender)
    if not prefix or prefix ~= self.PREFIX or not message or message == "" then
        return
    end
    
    channel = channel or "unknown"
    sender = sender or "unknown"
    
    -- DebugSync("Синхро-сообщение от", sender, "в канале", channel)
    
    if channel ~= "GUILD" then
        -- DebugSync("Негильдейский канал, игнорируем:", channel)
        return
    end
    
    if sender == UnitName("player") then
        -- DebugSync("Собственное сообщение, игнорируем")
        return
    end

    -- DebugSync("Получено сообщение от:", sender, "Содержимое:", message)
    
    local version, msgType, count
    for part in message:gmatch("([^|]+)") do
        local k, v = part:match("^([^=]+)=(.+)$")
        if k == "v" then version = tonumber(v) end
        if k == "t" then msgType = v end
        if k == "count" then count = tonumber(v) end
    end
    
    if not version or version ~= self.VERSION then
        DebugSync("Несовместимая версия:", version, "ожидалась:", self.VERSION)
        return
    end
    
    if not msgType then
        DebugSync("Не удалось определить тип сообщения")
        return
    end
    
if msgType == self.MSG_TYPE.COUNT then
    count = tonumber(count)
    if not count then
        DebugSync("Не удалось извлечь количество записей из сообщения COUNT, используем 50")
        count = 50
    end

    DebugSync("Получено количество записей от:", sender, "Количество:", count)
    
    self.receivingSync = {
        total = count,
        received = 0,
        startTime = GetTime(),
        lastReceivedTime = GetTime(),
        sender = sender
    }
    
    ShowSyncProgressNotification("Получение истории", 
        string.format("Получение данных от |cffFFD100%s|r (%d записей)", sender, count), 
        0, 15)
		
        elseif msgType == self.MSG_TYPE.FULL_ENTRY then
            -- DebugSync("Получена запись из полной истории от:", sender)
            
            if not self.receivingSync then
                local entryData = self:DeserializeDeathData(message)
                if entryData then
                    self:ProcessIncomingEntry(entryData, sender)
                else
                    DebugSync("Ошибка десериализации записи полной истории")
                end
                return
            end
            
            if self.receivingSync.sender ~= sender then
                DebugSync("Получена запись от другого отправителя, игнорируем")
                return
            end
            
            self.receivingSync.received = (self.receivingSync.received or 0) + 1
            self.receivingSync.lastReceivedTime = GetTime()
            
            if self.receivingSync.total and self.receivingSync.total > 0 then
                local progress = math.min(100, (self.receivingSync.received / self.receivingSync.total) * 100)
                self:UpdateProgressBar(progress)
            end
            
            local entryData = self:DeserializeDeathData(message)
            if entryData then
                self:ProcessIncomingEntry(entryData, sender)
            else
                DebugSync("Ошибка десериализации записи полной истории")
            end
            
            if self.receivingSync.total and self.receivingSync.received >= self.receivingSync.total then
                if self.DLNotifications and self.DLNotifications:IsShown() then
                    self.DLNotifications.text:SetText("Синхронизация завершена")
                    self.DLNotifications.startTime = GetTime()
                    self.DLNotifications.duration = 5.0
                end
            self.receivingSync = nil
            DebugSync("Получение всех записей завершено")
            end
			
        elseif msgType == self.MSG_TYPE.REQUEST_FULL then
            DebugSync("Получен запрос полной истории от:", sender)
            self:SendFullHistory(sender)
            
        elseif msgType == self.MSG_TYPE.NEW_ENTRY then
            DebugSync("Получена новая запись от:", sender)
            
            -- для одиночных записей проверяем уровень игрока
            local playerLevel = UnitLevel("player")
            local maxLevel = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()] or 80
            
            if playerLevel < maxLevel then
                DebugSync("Получение одиночной записи отменено: игрок не максимального уровня")
                return
            end
            
            local entryData = self:DeserializeDeathData(message)
            if entryData then
                self:ProcessIncomingEntry(entryData, sender)
            else
                DebugSync("Ошибка десериализации записи")
            end
    else
        DebugSync("Неизвестный тип сообщения:", msgType)
    end
end

if not DeathLoggerSync.timeoutFrame then
    DeathLoggerSync.timeoutFrame = CreateFrame("Frame")
    DeathLoggerSync.timeoutFrame:SetScript("OnUpdate", function(_, elapsed)
        if DeathLoggerSync.receivingSync then
            if not DeathLoggerSync.receivingSync.lastReceivedTime then
                DeathLoggerSync.receivingSync.lastReceivedTime = GetTime()
            end
            
            if DeathLoggerSync.receivingSync.total and 
               DeathLoggerSync.receivingSync.received and 
               DeathLoggerSync.receivingSync.received >= DeathLoggerSync.receivingSync.total then
                if DeathLoggerSync.DLNotifications and DeathLoggerSync.DLNotifications:IsShown() then
                    DeathLoggerSync.DLNotifications.text:SetText("Синхронизация завершена")
                    DeathLoggerSync.DLNotifications.startTime = GetTime() - 12
                end
                DeathLoggerSync.receivingSync = nil
                DebugSync("Синхронизация завершена, получены все записи")
            else
                if GetTime() - DeathLoggerSync.receivingSync.lastReceivedTime > 5 then
                    if DeathLoggerSync.DLNotifications and DeathLoggerSync.DLNotifications:IsShown() then
                        DeathLoggerSync.DLNotifications.text:SetText("Синхронизация завершена (таймаут)")
                        DeathLoggerSync.DLNotifications.startTime = GetTime() - 12
                    end
                    DeathLoggerSync.receivingSync = nil
                    DebugSync("Синхронизация завершена по таймауту")
                end
            end
        end
    end)
end

DeathLoggerSync.updateFrame = DeathLoggerSync.updateFrame or CreateFrame("Frame")
DeathLoggerSync.updateFrame:SetScript("OnUpdate", function(_, elapsed)
    if DeathLoggerSync.receivingSync then
        if GetTime() - DeathLoggerSync.receivingSync.startTime > 3 and 
           GetTime() - DeathLoggerSync.receivingSync.lastReceivedTime > 3 then
            DeathLoggerSync.receivingSync = nil
            DebugSync("Синхронизация завершена по таймауту")
        end
    end
end)

-- отправка полной истории
DeathLoggerSync.sendFrame = DeathLoggerSync.sendFrame or CreateFrame("Frame")

function DeathLoggerSync:SendFullHistory(target)
    if not IsInGuild() then
        DebugSync("Не в гильдии, отправка истории отменена")
        return 
    end
    
    if not DeathLoggerDB.syncEntries or #DeathLoggerDB.syncEntries == 0 then
        DebugSync("Нет записей в sync базе для отправки")
        return 
    end
    
    local validEntries = {}
    for _, entry in ipairs(DeathLoggerDB.syncEntries) do
        if self:IsValidEntry(entry) then
            table.insert(validEntries, entry)
        end
    end
    
    if #validEntries == 0 then
        DebugSync("Нет валидных записей в sync базе для отправки")
        return 
    end
    
    self.sendFrame:SetScript("OnUpdate", nil)
    
    DebugSync("Отправляю историю sync базы для", target or "гильдии")
    DebugSync("Всего записей в sync базе:", #DeathLoggerDB.syncEntries)
    DebugSync("Валидных записей:", #validEntries)
    
    local maxEntries = math.min(#validEntries, self.MAX_SYNC_ENTRIES)
    DebugSync("Будет отправлено записей:", maxEntries)
    
    local entriesToSend = {}
    for i = #validEntries, 1, -1 do
        table.insert(entriesToSend, validEntries[i])
    end
    
    local actualCount = #entriesToSend
    local countMessage = string.format("v=%d|t=%s|count=%d",
        self.VERSION, self.MSG_TYPE.COUNT, actualCount)
    SendAddonMessage(self.PREFIX, countMessage, "GUILD")
    DebugSync("Будет отправлено количество записей:", actualCount)
    
    ShowSyncProgressNotification("Отправка истории", 
        string.format("Отправка данных синхронизации (%d записей)", actualCount), 
        0, 15)
    
    self.sendData = {
        entries = entriesToSend,
        sent = 0,
        maxEntries = actualCount,
        delay = 0.2,
        lastSendTime = 0
    }
    
    self.sendFrame:SetScript("OnUpdate", function(frame, elapsed)
        self.sendData.lastSendTime = self.sendData.lastSendTime + elapsed
        
        if self.sendData.lastSendTime >= self.sendData.delay and self.sendData.sent < self.sendData.maxEntries then
            self.sendData.lastSendTime = 0
            self.sendData.sent = self.sendData.sent + 1
            
            local entry = self.sendData.entries[self.sendData.sent]
            if entry then
                local message = self:SerializeDeathData(entry, self.MSG_TYPE.FULL_ENTRY)
                if message then
                    SendAddonMessage(self.PREFIX, message, "GUILD")
                    -- DebugSync("Отправлена запись", self.sendData.sent, "из", self.sendData.maxEntries, ":", entry.playerName)
                end
            end
            
            local progress = (self.sendData.sent / self.sendData.maxEntries) * 100
            self:UpdateProgressBar(progress)
            
            if self.sendData.sent >= self.sendData.maxEntries then
                frame:SetScript("OnUpdate", nil)
                self.sendData = nil
                DebugSync("Отправка истории sync базы завершена")
                
                if self.DLNotifications and self.DLNotifications:IsShown() then
                    self.DLNotifications.text:SetText("Отправка завершена")
                    self.DLNotifications.startTime = GetTime()
                    self.DLNotifications.duration = 5.0
                end
                
                if DeathLoggerDB.syncNotifications then
                    if not self.completionTimer then
                        self.completionTimer = CreateFrame("Frame")
                    end
                    
                    self.completionTimer.startTime = GetTime()
                    self.completionTimer:SetScript("OnUpdate", function(timerFrame, elapsed)
                        if GetTime() - timerFrame.startTime >= 0.5 then
                            timerFrame:SetScript("OnUpdate", nil)
                            ShowSyncCompleteNotification()
                        end
                    end)
                end
            end
        end
    end)
end

--отображение сохраненных записей синхронизации
function DeathLoggerSync:ShowSyncEntries(numEntries)
    numEntries = numEntries or 50
    
    if not DeathLoggerDB.syncEntries or #DeathLoggerDB.syncEntries == 0 then
        print("|cff00ccff[DeathLogger]|r Нет сохраненных записей синхронизации")
        return
    end
    
    local totalEntries = #DeathLoggerDB.syncEntries
    local showCount = math.min(numEntries, totalEntries)
    
    print(string.format("|cff00ccff[DeathLogger]|r Последние %d из %d записей синхронизации:", showCount, totalEntries))
    print("|cff00ccff========================================|r")
    
    for i = 1, showCount do
        local entry = DeathLoggerDB.syncEntries[i]
        if entry then
            local formattedData, tooltip, playerName, class = self:FormatEntryForMainUI(entry)
            
            if formattedData then
                print(string.format("%d. %s", i, formattedData))
            else
                local causeText = entry.causeID == 7 and 
                    string.format("Убийство (%s ур. %d)", entry.enemyName or "?", entry.enemyLevel or 0) or
                    Utils.causes[entry.causeID or 0] or "Неизвестно"
                
                local classColor = "|cFFFFFFFF"
                if entry.classID and RAID_CLASS_COLORS[entry.classID] then
                    local color = RAID_CLASS_COLORS[entry.classID]
                    classColor = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
                end
                
                local guildInfo = entry.guild and entry.guild ~= "" and 
                    string.format(" |cff00ff00<%s>|r", entry.guild) or ""
                
                print(string.format("%d. %s%s%s |cffFFD100(%d)|r - %s |cff888888(%s)|r",
                    i,
                    classColor,
                    entry.playerName or "Неизвестно",
                    guildInfo,
                    entry.level or 0,
                    causeText,
                    entry.locationStr or "Неизвестно"
                ))
            end
        end
    end
    
    if showCount < totalEntries then
        print(string.format("|cff00ccff... и еще %d записей|r", totalEntries - showCount))
    end
end

-- присваивание "ключа" для сравнения по классу+имени
function DeathLoggerSync:GetDuplicateKey(entryData)
    return string.format("%s:%s", 
        strlower(entryData.class or ""),
        strlower(entryData.playerName or ""))
end


function DeathLoggerSync:ProcessIncomingEntry(entryData, sender)
    DebugSync("Обработка входящей записи от:", sender, "Игрок:", entryData.playerName, "Тип:", entryData.msgType)
    
    if not entryData.playerName or not entryData.class or not entryData.factionID then
        DebugSync("Невалидная запись: отсутствуют обязательные поля")
        return
    end
    
    -- одиночные записи проверка уровня игрока
    if entryData.msgType == self.MSG_TYPE.NEW_ENTRY then
        local playerLevel = UnitLevel("player")
        local maxLevel = MAX_PLAYER_LEVEL_TABLE[GetExpansionLevel()] or 80
        
        if playerLevel < maxLevel then
            DebugSync("Получение одиночной записи отменено: игрок не максимального уровня")
            return
        end
    end
    
    local addedToSync = self:AddToSyncDB(entryData)
    
    local addedToMain = false
    if not self:IsDuplicateInMainList(entryData) then
        addedToMain = self:AddToMainList(entryData)
    end
    
    DebugSync("Обработана запись от:", sender, 
              "Sync база:", addedToSync and "добавлено" or "пропущено", 
              "Основной список:", addedToMain and "добавлено" or "пропущено")
    
    if addedToMain and DeathLoggerDB.syncNotifications then
        local shouldShow = true
        if self.DLNotifications and self.DLNotifications:IsShown() and self.DLNotifications.progressBar:IsShown() then
            shouldShow = false
            DebugSync("Прогресс-бар активен, пропускаем уведомление о новой записи")
        end
        
        if shouldShow then
            ShowNewEntryNotification(sender, entryData.playerName)
        end
    end
end

-- форматрование записи для интерфейса
function DeathLoggerSync:FormatEntryForMainUI(entryData)
    if not entryData then return nil end
    
    local function formatTime(timestamp)
        return timestamp and date("%H:%M", timestamp) or "Неизвестно"
    end
    
    local timeData = formatTime(entryData.timestamp)
    
    local timeData = entryData.level >= 70 and Utils.ColorWord("[" .. formatTime(entryData.timestamp) .. "]", "Фиолетовый") or
                     entryData.level >= 60 and Utils.ColorWord("[" .. formatTime(entryData.timestamp) .. "]", "Синий") or
                     entryData.level >= 10 and Utils.ColorWord("[" .. formatTime(entryData.timestamp) .. "]", "Белый") or
                     entryData.level == 1 and Utils.ColorWord("[" .. formatTime(entryData.timestamp) .. "]", "Золотой")
    
    local className = entryData.class or "Unknown"
    
    -- испытание завершено
    if entryData.level == 1 then
        local name = Utils.ColorWord(entryData.playerName or "Неизвестно", className)
        local coloredRace, race, side = Utils.GetRaceData(entryData.raceID or 0)
        
        local mainStr = string.format("%s %s %s |cFFFF8000завершил испытание!|r",
            timeData, "|TInterface\\BUTTONS\\Arrow-Down-Down:14:14:0:0|t " .. name, coloredRace)
        
        local tooltip = string.format("|cFF00FF00Пройден|r\nИмя: %s\nКласс: %s\nРаса: %s\nФракция: %s",
            entryData.playerName or "Неизвестно", 
            className,
            race, 
            side)
        
        if entryData.guild and entryData.guild ~= "" then
            mainStr = mainStr .. " |cffffcc00<"..entryData.guild..">|r"
            tooltip = tooltip .. "\nГильдия: " .. entryData.guild
        end
        
        return mainStr, tooltip, entryData.playerName, className, side
    end
    
    -- испытание провалено
    local name = "|TInterface\\BUTTONS\\Arrow-Down-Down:14:14:0:0|t " .. Utils.ColorWord(entryData.playerName or "Неизвестно", className)
    local coloredRace, race, side = Utils.GetRaceData(entryData.raceID or 0)
    
    local level = entryData.level >= 70 and Utils.ColorWord(entryData.level .. " ур.", "Фиолетовый") or
                  entryData.level >= 60 and Utils.ColorWord(entryData.level .. " ур.", "Синий") or
                  entryData.level >= 10  and Utils.ColorWord(entryData.level .. " ур.", "Белый")
    
    local mainStr = string.format("%s %s %s %s", timeData, name, coloredRace, level)
    local tooltip = string.format("|cFFFF0000Провален|r\nИмя: %s\nУровень: %d\nКласс: %s\nРаса: %s\nФракция: %s\nЛокация: %s\nПричина: %s",
        entryData.playerName or "Неизвестно", 
        entryData.level or 0, 
        className,
        race, 
        side, 
        entryData.locationStr or "Неизвестно", 
        Utils.causes[entryData.causeID or 0] or "Неизвестно")
    
    if entryData.causeID == 7 then
        tooltip = tooltip .. "\nОт: " .. (entryData.enemyName or "неизвестно") .. " " .. (entryData.enemyLevel or 0) .. "-го уровня"
    end
    
    if entryData.guild and entryData.guild ~= "" then
        mainStr = mainStr .. " |cffffcc00<"..entryData.guild..">|r"
        tooltip = tooltip .. "\nГильдия: " .. entryData.guild
    end
	
    return mainStr, tooltip, entryData.playerName, className, side
end

-- сохраняем записи для синхры
function DeathLoggerSync:SaveEntryWithSync(dataMap)
    if not dataMap then return nil end
    
    local _, _, side = Utils.GetRaceData(dataMap.raceID or 0)
    local className = Utils.classes[dataMap.classID or 0] or "Unknown"
    
    local entryData = {
        playerName = dataMap.name or "",
        raceID = dataMap.raceID or 0,
        factionID = dataMap.sideID or 0,
        classID = dataMap.classID or 0,
        class = className,
        level = dataMap.level or 0,
        locationStr = dataMap.locationStr or "",
        causeID = dataMap.causeID or 0,
        enemyName = dataMap.enemyName or "",
        enemyLevel = dataMap.enemyLevel or 0,
        guild = dataMap.guild or "",
        timestamp = dataMap.timestamp or time()
    }
    
    local addedToSync = self:AddToSyncDB(entryData)
    
    local addedToMain = self:AddToMainList(entryData)
    
    if addedToSync then
        self:SyncNewEntry(entryData)
    end
    
    DebugSync("Сохранение завершено:", 
              "Sync база:", addedToSync and "добавлено" or "пропущено", 
              "Основной список:", addedToMain and "добавлено" or "пропущено")
    
    return addedToMain and entryData or nil
end

-- отображение и очистка статистики синхронизации
function DeathLoggerSync:ShowSyncStats()
    local syncCount = DeathLoggerDB.syncEntries and #DeathLoggerDB.syncEntries or 0
    local mainCount = DeathLoggerDB.entries and #DeathLoggerDB.entries or 0
    local indexSize = self:GetIndexSize()
    
    print("|cff00ccff[DeathLogger]|r Статистика синхронизации:")
    print("|cff00ccff========================================|r")
    print(string.format("Записей в основном списке: |cffFFD100%d|r", mainCount))
    print(string.format("Записей в sync базе: |cffFFD100%d|r", syncCount))
    print(string.format("Записей в индексе: |cffFFD100%d|r", indexSize))
    print(string.format("Синхронизация: |cff%s|r", DeathLoggerDB.syncEnabled and "00ff00ВКЛЮЧЕНА" or "ffff00ВЫКЛЮЧЕНА"))
    print(string.format("Уведомления: |cff%s|r", DeathLoggerDB.syncNotifications and "00ff00ВКЛЮЧЕНЫ" or "ffff00ВЫКЛЮЧЕНЫ"))
    print(string.format("Отладка: |cff%s|r", self.DEBUG and "00ff00ВКЛЮЧЕНА" or "ffff00ВЫКЛЮЧЕНА"))
end

function DeathLoggerSync:ClearAllSyncData()
    DeathLoggerDB.syncEntries = {}
    DeathLoggerDB.syncIndex = {}
    
    print("|cff00ccff[DeathLogger]|r Все данные синхронизации очищены")
    self:ShowSyncStats()
end

function DeathLoggerSync:ToggleSync()
    DeathLoggerDB.syncEnabled = not DeathLoggerDB.syncEnabled
    
    if DeathLoggerDB.syncEnabled then
        print("|cff00ccff[DeathLogger]|r Синхронизация |cff00ff00ВКЛЮЧЕНА|r")
    else
        print("|cff00ccff[DeathLogger]|r Синхронизация |cffff0000ВЫКЛЮЧЕНА|r")
    end
end

-- уведомления
function DeathLoggerSync:ToggleNotifications()
    DeathLoggerDB.syncNotifications = DeathLoggerDB.syncNotifications == nil and true or not DeathLoggerDB.syncNotifications
    
    if DeathLoggerDB.syncNotifications then
        print("|cff00ccff[DeathLogger]|r Уведомления |cff00ff00ВКЛЮЧЕНЫ|r")
    else
        print("|cff00ccff[DeathLogger]|r Уведомления |cffff0000ВЫКЛЮЧЕНЫ|r")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        DeathLoggerSync.isLoggingOut = true
        DeathLoggerSync:OnLogout()
    end
end)

-- API
DeathLoggerSync.API = {
    ToggleDebug = function() DeathLoggerSync:ToggleDebug() end,
    ShowSyncStats = function() DeathLoggerSync:ShowSyncStats() end,
    ShowSyncEntries = function(num) DeathLoggerSync:ShowSyncEntries(num) end,
    ClearAllSyncData = function() DeathLoggerSync:ClearAllSyncData() end,
    ToggleSync = function() DeathLoggerSync:ToggleSync() end,
    ToggleNotifications = function() DeathLoggerSync:ToggleNotifications() end,
    RequestFullSync = function() DeathLoggerSync:RequestFullSync() end
}

-- отладка  -- переделать на простую отладку к релизу
SLASH_DEATHLOGGERSYNC1 = "/dlsync"
SlashCmdList["DEATHLOGGERSYNC"] = function(msg)
    local command = strlower(msg or "")
    
    if command == "debug" then
        DeathLoggerSync.API.ToggleDebug()
    elseif command == "stats" then
        DeathLoggerSync.API.ShowSyncStats()
    elseif command:find("^show") then
        local num = tonumber(command:match("show%s+(%d+)")) or 50
        DeathLoggerSync.API.ShowSyncEntries(num)
    elseif command == "clear" then
        DeathLoggerSync.API.ClearAllSyncData()
    elseif command == "toggle" then
        DeathLoggerSync.API.ToggleSync()
    elseif command == "notify" then
        DeathLoggerSync.API.ToggleNotifications()
    elseif command == "request" then
        DeathLoggerSync.API.RequestFullSync()
    else
        print("|cff00ccff[DeathLogger Sync]|r Команды:")
        print("|cff00ccff/dlsync debug|r - переключить отладку")
        print("|cff00ccff/dlsync stats|r - показать статистику")
        print("|cff00ccff/dlsync show [число]|r - показать записи")
        print("|cff00ccff/dlsync clear|r - очистить данные")
        print("|cff00ccff/dlsync toggle|r - переключить синхронизацию")
        print("|cff00ccff/dlsync notify|r - переключить уведомления")
        print("|cff00ccff/dlsync request|r - запросить историю")
    end
end