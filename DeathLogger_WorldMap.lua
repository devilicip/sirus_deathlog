-- Copyright 2025-2026 Norzia (devilicip2@gmail.com) for sirus-wow
-- Thanks to testers and Сегодня я не Умру guild
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the "Software"), to deal in the Software without
-- restriction, including without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or
-- substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
local addonName = "DeathLogger"
local DeathLoggerWorldMap = {}
DeathLoggerWorldMap.__index = DeathLoggerWorldMap
-- Дебаг режим (по умолчанию выключен для производительности)
local WMDebug = false
local WMDebugPrefix = "|cff00ccff[WMDebug]|r "
-- Флаг инициализации
local initialized = false
-- Отслеживание текущей зоны для фильтрации маркеров
local currentZoneName = nil
local currentContinentID = nil
-- Настройки по умолчанию
local DEFAULT_SETTINGS = {
    enabled = false,
    showDeathMarkers = true,
    showChallengeMarkers = true,
    markerSize = 16,
    clusterRadius = 50,
    showTooltips = true,
    filterByLevel = false,
    minLevel = 1,
    maxLevel = 70,
    filterByFaction = "ALL",
    filterByGuild = false,
    maxMarkers = 100,
    showPlayerDeaths = true,
    showGuildDeaths = true,
    markerOpacity = 1.0,
    filterByZone = true  -- НОВАЯ НАСТРОЙКА: фильтрация по зоне
}
-- Безопасная функция форматирования
local function SafeFormat(message, ...)
    if select('#', ...) == 0 then
        return message
    end
    local args = {...}
    for i = 1, #args do
        local arg = args[i]
        if arg == nil then
            args[i] = "nil"
        elseif type(arg) == "table" then
            args[i] = "table"
        elseif type(arg) == "boolean" then
            args[i] = arg and "true" or "false"
        end
    end
    local success, result = pcall(string.format, message, unpack(args))
    if success then
        return result
    else
        return message .. " [Ошибка форматирования]"
    end
end
-- Глобальная функция для дебага
function DLWMDebug(message, ...)
    if WMDebug then
        local formatted = SafeFormat(message, ...)
        print(WMDebugPrefix .. formatted)
    end
end
-- Методы для дебага
function DeathLoggerWorldMap:Debug(message, ...)
    if WMDebug then
        local formatted = SafeFormat(message, ...)
        print(WMDebugPrefix .. formatted)
    end
end
function DeathLoggerWorldMap:EnableDebug()
    WMDebug = true
    print(WMDebugPrefix .. "Отладка модуля карты мира включена")
end
function DeathLoggerWorldMap:DisableDebug()
    WMDebug = false
    print(WMDebugPrefix .. "Отладка модуля карты мира выключена")
end
function DeathLoggerWorldMap:ToggleDebug()
    WMDebug = not WMDebug
    print(WMDebugPrefix .. "Отладка модуля карты мира: " .. (WMDebug and "ВКЛ" or "ВЫКЛ"))
end
-- Функция trim для строк
if not string.trim then
    string.trim = function(s)
        return s:match("^%s*(.-)%s*$")
    end
end
-- Функция ленивой инициализации - вызывается только при первом открытии карты
function DeathLoggerWorldMap:LazyInit()
    if initialized then
        self:Debug("LazyInit: уже инициализировано")
        return
    end
    self:Debug("Ленивая инициализация модуля карты мира")

    -- Проверяем доступность карты мира
    if not WorldMapFrame then
        self:Debug("WorldMapFrame не найден!")
        return
    end

    -- Создаем родительский фрейм для маркеров
    self.parentFrame = CreateFrame("Frame", "DeathLoggerWorldMapParent", WorldMapFrame)
    self.parentFrame:SetAllPoints(WorldMapFrame)
    self.parentFrame:SetFrameStrata("MEDIUM")
    self.parentFrame:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10)
    self.parentFrame:Hide() -- По умолчанию скрыт

    -- Создаем элементы управления на карте мира
    self:CreateWorldMapControls()

    -- Загружаем данные локаций
    self:LoadLocationData()

    -- Инициализируем таблицу соответствий ID карт
    self:InitMapIDTable()

    -- Регистрируем события
    self:RegisterEvents()

    -- Инициализируем настройки
    if not DeathLoggerDB then
        DeathLoggerDB = {
            entries = {},
            worldMapSettings = {},
            locationHistory = {}
        }
    end

    DeathLoggerDB.worldMapSettings = DeathLoggerDB.worldMapSettings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if DeathLoggerDB.worldMapSettings[k] == nil then
            DeathLoggerDB.worldMapSettings[k] = v
        end
    end

    self.settings = DeathLoggerDB.worldMapSettings

    -- Инициализируем отслеживание зоны
    currentZoneName = self:GetCurrentMapZone()
    currentContinentID = GetCurrentMapContinent()
    self:Debug("Инициализация зоны: %s (континент: %d)", currentZoneName or "Неизвестно", currentContinentID or 0)

    -- Если модуль был включен, показываем parentFrame
    if self.settings.enabled then
        self.parentFrame:Show()
    end

    initialized = true
    self:Debug("Ленивая инициализация завершена")
end
function DeathLoggerWorldMap:new()
    -- Не вызываем инициализацию здесь - только создаем экземпляр
    local instance = setmetatable({}, DeathLoggerWorldMap)
    instance.markers = {}
    instance.clusters = {}
    instance.locationData = {}
    instance.timers = {}
    instance.testMarkers = {}
    self:Debug("Экземпляр DeathLoggerWorldMap создан (ленивая инициализация)")
    return instance
end
-- НОВАЯ ФУНКЦИЯ: Получить название зоны на текущей карте мира
function DeathLoggerWorldMap:GetCurrentMapZone()
    local mapID = GetCurrentMapAreaID()
    local mapName
    -- Способ 1: Используем GetMapInfo() (если доступен)
    if GetMapInfo then
        mapName = GetMapInfo() 
        if mapName and mapName ~= "" then
            self:Debug("GetCurrentMapZone: mapID=%d, GetMapInfo=%s", mapID, mapName)
            return mapName
        end
    end

    -- Способ 2: Используем GetRealZoneText() если доступен
    if GetRealZoneText then
        mapName = GetRealZoneText()
        if mapName and mapName ~= "" then
            self:Debug("GetCurrentMapZone: mapID=%d, GetRealZoneText=%s", mapID, mapName)
            return mapName
        end
    end

    -- Способ 3: Используем GetSubZoneText() для подзон
    local subZone = GetSubZoneText()
    if subZone and subZone ~= "" then
        self:Debug("GetCurrentMapZone: mapID=%d, GetSubZoneText=%s", mapID, subZone)
        return subZone
    end

    -- Способ 4: Используем статическую таблицу соответствий
    if mapID and self.mapIDtoName then
        mapName = self.mapIDtoName[mapID]
        if mapName then
            self:Debug("GetCurrentMapZone: mapID=%d, static table=%s", mapID, mapName)
            return mapName
        end
    end

    -- Запасной вариант
    mapName = GetZoneText()
    self:Debug("GetCurrentMapZone: mapID=%d, GetZoneText=%s (запасной)", mapID or 0, mapName or "nil")
    return mapName
end
-- Функция для преобразования названия зоны в ID карты
function DeathLoggerWorldMap:GetZoneMapID(zoneName)
    if not zoneName then return nil end
    -- Ищем в загруженных данных локаций
    for location, data in pairs(self.locationData) do
        if strlower(location) == strlower(zoneName) or 
           (data.zone and strlower(data.zone) == strlower(zoneName)) then
            self:Debug("Найден ID зоны для %s: continent=%d", zoneName, data.continent or 0)
            return data.continent or 0
        end
    end

    -- Проверяем известные зоны
    local zoneMap = {
        -- Континент 1: Калимдор
        ["Дуротар"] = 1,
        ["Мулгор"] = 1,
        ["Степи"] = 1,
        ["Скалистые горы"] = 1,
        ["Ясеневый лес"] = 1,
        ["Тысяча Игл"] = 1,
        ["Пылевые топи"] = 1,
        ["Танарис"] = 1,
        ["Фералас"] = 1,
        ["Азшара"] = 1,
        ["Остров Лазурной Дымки"] = 1,
        ["Ун'Горо"] = 1,
        ["Силитус"] = 1,
        ["Зимние Ключи"] = 1,
        ["Внутренние земли"] = 1,
        ["Выжженные земли"] = 1,
        ["Когтистые горы"] = 1,
        
        -- Континент 2: Восточные королевства
        ["Тирисфальские леса"] = 2,
        ["Элвиннский лес"] = 2,
        ["Дун Морог"] = 2,
        ["Тельдрассил"] = 2,
        ["Чернолесье"] = 2,
        ["Красногорье"] = 2,
        ["Сумеречный лес"] = 2,
        ["Нагорье Арати"] = 2,
        ["Внутренние земли"] = 2,
        ["Болотина"] = 2,
        ["Тернистая долина"] = 2,
        ["Бесплодные земли"] = 2,
        ["Выжженные земли"] = 2,
        ["Западные Чумные земли"] = 2,
        ["Восточные Чумные земли"] = 2,
        ["Лок Модан"] = 2,
        
        -- Континент 3: Запределье (Outland)
        ["Пустоверть"] = 3,
        ["Зангартопь"] = 3,
        ["Лес Террокар"] = 3,
        ["Награнд"] = 3,
        ["Острогорье"] = 3,
        ["Долина Призрачной Луны"] = 3,
        ["Полуостров Адского Пламени"] = 3,
        ["Шаттрат"] = 3,
        
        -- Континент 4: Нордскол
        ["Драконий Погост"] = 4,
        ["Борейская тундра"] = 4,
        ["Ревущий фьорд"] = 4,
        ["Лес Хрустальной Песни"] = 4,
        ["Зул'Драк"] = 4,
        ["Низина Шолазар"] = 4,
        ["Грозовая Гряда"] = 4,
        ["Ледяная Корона"] = 4,
        ["Даларан"] = 4,
    }

    local mapID = zoneMap[zoneName]
    if mapID then
        self:Debug("Найден ID зоны в карте: %s -> %d", zoneName, mapID)
    else
        self:Debug("ID зоны не найден для: %s", zoneName)
    end

    return mapID
end
-- Функция для отображения смертей в текущей зоне
function DeathLoggerWorldMap:ShowDeathsInCurrentZone()
    if not WMDebug then
        print(WMDebugPrefix .. "Отладка выключена. Включите ее для использования этой функции.")
        return
    end
    if not DeathLoggerDB or not DeathLoggerDB.entries then
        print(WMDebugPrefix .. "Нет данных о смертях в базе данных")
        return
    end

    local currentZone = self:GetCurrentMapZone()
    local currentContinent = GetCurrentMapContinent()
    local mapID = GetCurrentMapAreaID()
    local zoneText = GetZoneText()  
    local subZoneText = GetSubZoneText()

    print("|cff00ccff========== DeathLogger: Поиск смертей ==========|r")
    print("Текущая зона на карте: |cFF00FF00" .. (currentZone or "Неизвестно") .. "|r")
    print("ID карты: |cFF00FF00" .. (mapID or "N/A") .. "|r")
    print("Континент: |cFF00FF00" .. (currentContinent or "Неизвестно") .. "|r")
    print("GetZoneText: |cFF00FF00" .. (zoneText or "N/A") .. "|r")
    print("GetSubZoneText: |cFF00FF00" .. (subZoneText or "N/A") .. "|r")
    print("Всего записей в базе: |cFF00FF00" .. (#DeathLoggerDB.entries or 0) .. "|r")
    print("  ")

    local zoneDeaths = {}
    local totalDeaths = 0
    local foundEntries = 0

    -- Собираем смерти в текущей зоне
    for i, entry in ipairs(DeathLoggerDB.entries) do
        foundEntries = foundEntries + 1
        
        if entry and (entry.playerName or entry.name) then
            local playerName = entry.playerName or entry.name or "Неизвестно"
            local locationInfo = self:ParseLocation(entry)
            
            if locationInfo and locationInfo.zone then
                local entryZone = locationInfo.zone
                local entryContinent = locationInfo.continent or self:GetZoneMapID(entryZone)
                
                -- Сравниваем зоны
                local zoneMatch = false
                if currentZone and entryZone then
                    zoneMatch = self:CompareZones(currentZone, entryZone)
                    
                    if not zoneMatch and zoneText then
                        zoneMatch = self:CompareZones(zoneText, entryZone)
                    end
                    
                    if not zoneMatch and subZoneText then
                        zoneMatch = self:CompareZones(subZoneText, entryZone)
                    end
                    
                    if not zoneMatch and entry.tooltip then
                        local tooltipLower = strlower(entry.tooltip)
                        local currentZoneLower = strlower(currentZone)
                        zoneMatch = string.find(tooltipLower, currentZoneLower) or
                                     string.find(currentZoneLower, tooltipLower)
                    end
                end
                
                if zoneMatch then
                    if not zoneDeaths[playerName] then
                        zoneDeaths[playerName] = {
                            name = playerName,
                            class = entry.class or "Неизвестно",
                            level = entry.level,
                            faction = entry.faction or "Нейтрал",
                            guild = entry.parseGuild,
                            deaths = 0,
                            entries = {}
                        }
                    end
                     
                    zoneDeaths[playerName].deaths = zoneDeaths[playerName].deaths + 1
                    table.insert(zoneDeaths[playerName].entries, {
                        timestamp = entry.timestamp,
                        locationInfo = locationInfo,
                        tooltip = entry.tooltip
                    })
                    totalDeaths = totalDeaths + 1
                     
                    self:Debug("Найдена смерть в зоне: %s - %s", playerName, entryZone)
                end
            end
        end
    end

    -- Сортируем игроков по количеству смертей
    local sortedPlayers = {}
    for name, data in pairs(zoneDeaths) do
        table.insert(sortedPlayers, data)
    end

    table.sort(sortedPlayers, function(a, b)
        return a.deaths > b.deaths
    end)

    -- Выводим статистику
    if #sortedPlayers == 0 then
        print("|cFFFF0000В зоне '" .. (currentZone or "Неизвестно") .. "' не найдено записей о смертях.|r")
        print("  ")
        print("|cFF00FF00Отладка:|r ")
        print("Проверено записей: " .. foundEntries)
        print("Текущая зона для поиска: " .. (currentZone or "nil"))
        print("ID карты: " .. (mapID or "nil"))
        print("Континент: " .. (currentContinent or "nil"))
        
        -- Для отладки покажем первые несколько записей
        if WMDebug and DeathLoggerDB.entries and #DeathLoggerDB.entries > 0 then
            print("  ")
            print("|cFF00FF00Первые 5 записей в базе:|r ")
            for i = 1, math.min(5, #DeathLoggerDB.entries) do
                local entry = DeathLoggerDB.entries[i]
                if entry then
                    local playerName = entry.playerName or entry.name or "? "
                    local locInfo = self:ParseLocation(entry)
                    local location = locInfo and locInfo.zone or "? "
                    
                    local tooltipLocation = "нет "
                    if entry.tooltip then
                        local locMatch = string.match(entry.tooltip, "Локация:%s*([^\n\r]+)")
                        if locMatch then
                            tooltipLocation = locMatch:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                        end
                    end
                    
                    print(string.format("%d. %s - %s (класс: %s, локация из tooltip: %s)", 
                        i, playerName, location, entry.class or "? ", tooltipLocation))
                end
            end
        end
    else
        print("|cFF00FF00Найдено смертей в зоне: |cFFFF0000" .. totalDeaths .. "|r")
        print("Уникальных игроков: |cFFFF0000" .. #sortedPlayers .. "|r")
        print("Проверено записей: " .. foundEntries)
        print("  ")
        print("|cFF00FF00Топ смертей в зоне:|r ")
        
        for i, player in ipairs(sortedPlayers) do
            if i <= 20 then
                local classColor = "|cFFFFFFFF "
                local classColors = {
                    ["Воин"] = "|cFFC79C6E ",
                    ["Паладин"] = "|cFFF58CBA ",
                    ["Охотник"] = "|cFFABD473 ",
                    ["Разбойник"] = "|cFFFFF569 ",
                    ["Жрец"] = "|cFFFFFFFF ",
                    ["Рыцарь смерти"] = "|cFFFF4D6D ",
                    ["Шаман"] = "|cFF0070DE ",
                    ["Маг"] = "|cFF69CCF0 ",
                    ["Чернокнижник"] = "|cFF9482C9 ",
                    ["Монах"] = "|cFF00FF96 ",
                    ["Друид"] = "|cFFFF7D0A ",
                }
                if player.class and classColors[player.class] then
                    classColor = classColors[player.class]
                end
                
                local factionIcon = " "
                if player.faction == "Альянс" then
                    factionIcon = "|TInterface\\PVPFrame\\PVP-Currency-Alliance:14:14:0:0|t  "
                elseif player.faction == "Орда" then
                    factionIcon = "|TInterface\\PVPFrame\\PVP-Currency-Horde:14:14:0:0|t  "
                end
                
                local guildStr = " "
                if player.guild and player.guild ~= "" then
                    guildStr = " |cFFFFFF00<" .. player.guild .. ">|r  "
                end
                
                print(string.format("%d. %s%s%s%s - |cFFFF0000%d смертей|r", 
                    i, factionIcon, classColor, player.name, guildStr, player.deaths))
            end
        end
        
        -- Показываем подробную информацию по последним смертям
        print("  ")
        print("|cFF00FF00Последние смерти в зоне:|r ")
        
        local recentDeaths = {}
        for _, player in ipairs(sortedPlayers) do
            for _, entry in ipairs(player.entries) do
                table.insert(recentDeaths, {
                    name = player.name,
                    class = player.class,
                    timestamp = entry.timestamp,
                    locationInfo = entry.locationInfo
                })
            end
        end
        
        table.sort(recentDeaths, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)
        
        for i = 1, math.min(10, #recentDeaths) do
            local death = recentDeaths[i]
            if death.timestamp then
                local timeAgo = time() - death.timestamp
                local timeStr
                
                if timeAgo < 60 then
                    timeStr = string.format("%d сек назад", timeAgo)
                elseif timeAgo < 3600 then
                    timeStr = string.format("%d мин назад", math.floor(timeAgo / 60))
                elseif timeAgo < 86400 then
                    timeStr = string.format("%d час назад", math.floor(timeAgo / 3600))
                else
                    timeStr = string.format("%d дн назад", math.floor(timeAgo / 86400))
                end
                
                local locationText = death.locationInfo and death.locationInfo.zone or "неизвестно"
                print(string.format("  |cFF888888•|r %s (%s) - смерть в %s (%s)", 
                    death.name or "Неизвестно", death.class or "? ", locationText, timeStr))
            end
        end
    end

    print("|cff00ccff============================================|r")
end
function DeathLoggerWorldMap:DebugZoneDetection()
    print("|cff00ccff========== Отладка определения зоны ==========|r")
    print("GetCurrentMapAreaID(): " .. (GetCurrentMapAreaID() or "nil"))
    print("GetCurrentMapContinent(): " .. (GetCurrentMapContinent() or "nil"))
    print("GetCurrentMapZone(): " .. (self:GetCurrentMapZone() or "nil"))
    print("GetZoneText(): " .. (GetZoneText() or "nil"))
    print("GetSubZoneText(): " .. (GetSubZoneText() or "nil"))
    if GetMapInfo then
        print("GetMapInfo(): " .. (GetMapInfo() or "nil"))
    end

    if GetRealZoneText then
        print("GetRealZoneText(): " .. (GetRealZoneText() or "nil"))
    end

    local x, y = GetPlayerMapPosition("player")
    if x and y and x > 0 and y > 0 then
        print("Координаты игрока: " .. string.format("%.2f, %.2f", x * 100, y * 100))
    end

    print("|cff00ccff============================================|r")
end
function DeathLoggerWorldMap:DebugEntries()
    if not DeathLoggerDB or not DeathLoggerDB.entries then
        print("|cFFFF0000Нет записей в БД|r")
        return
    end
    print("|cff00ccff========== Отладка записей DeathLogger ==========|r")
    print("Всего записей: " .. #DeathLoggerDB.entries)
    print("  ")

    for i, entry in ipairs(DeathLoggerDB.entries) do
        if i <= 10 then
            print(string.format("|cFF00FF00%d.|r Тип: %s", i, type(entry)))
            
            if type(entry) == "table" then
                local playerName = self:GetEntryName(entry)
                local locationInfo = self:ParseLocation(entry)
                
                print("   |cFFFFFF00playerName:|r " .. tostring(playerName or "НЕТ"))
                print("   |cFFFFFF00class:|r " .. tostring(entry.class or "НЕТ"))
                print("   |cFFFFFF00faction:|r " .. tostring(entry.faction or "НЕТ"))
                print("   |cFFFFFF00level:|r " .. tostring(entry.level or "НЕТ"))
                
                if locationInfo then
                    print("   |cFFFFFF00location (парсинг):|r " .. tostring(locationInfo.zone or "НЕТ"))
                    print("   |cFFFFFF00continent:|r " .. tostring(locationInfo.continent or "НЕТ"))
                    print("   |cFFFFFF00coordinates:|r " .. string.format("%.2f, %.2f", locationInfo.x or 0, locationInfo.y or 0))
                else
                    print("   |cFFFF0000location:|r НЕ УДАЛОСЬ ОПРЕДЕЛИТЬ")
                end
                
                print("   |cFFFFFF00timestamp:|r " .. tostring(entry.timestamp or "НЕТ") .. 
                      (entry.timestamp and (" (" .. date("%Y-%m-%d %H:%M", entry.timestamp) .. ")") or ""))
                
                if entry.tooltip then
                    local preview = entry.tooltip:gsub("\n", "   "):sub(1, 80)
                    if #entry.tooltip > 80 then
                        preview = preview .. "..."
                    end
                    print("   |cFFFFFF00tooltip:|r " .. preview)
                end
            end
            print("---")
        end
    end

    print("|cff00ccff============================================|r")
end
function DeathLoggerWorldMap:DebugEntry(index)
    if not DeathLoggerDB or not DeathLoggerDB.entries then
        print("|cFFFF0000Нет записей в БД|r")
        return
    end
    index = tonumber(index) or 1

    if index < 1 or index > #DeathLoggerDB.entries then
        print(string.format("|cFFFF0000Запись #%d не существует (всего записей: %d)|r", index, #DeathLoggerDB.entries))
        return
    end

    local entry = DeathLoggerDB.entries[index]

    print("|cff00ccff========== Детальный разбор записи #" .. index .. " ==========|r")
    print("Тип записи: " .. type(entry))

    if type(entry) == "table" then
        print("|cFF00FF00Все поля записи:|r ")
        for k, v in pairs(entry) do
            if type(v) == "string" then
                print(string.format("   %s: %s", k, v:sub(1, 100)))
            else
                print(string.format("   %s: %s", k, tostring(v)))
            end
        end
        
        print("  ")
        print("|cFF00FF00Результаты парсинга:|r ")
        
        local playerName = self:GetEntryName(entry)
        print("GetEntryName: " .. tostring(playerName))
        
        local faction = self:GetEntryFaction(entry)
        print("GetEntryFaction: " .. tostring(faction))
        
        local locationInfo = self:ParseLocation(entry)
        if locationInfo then
            print("ParseLocation: УСПЕШНО")
            print("   zone: " .. tostring(locationInfo.zone))
            print("   continent: " .. tostring(locationInfo.continent))
            print("   x, y: " .. string.format("%.2f, %.2f", locationInfo.x or 0, locationInfo.y or 0))
            print("   rawLocation: " .. tostring(locationInfo.rawLocation))
        else
            print("ParseLocation: |cFFFF0000НЕУДАЧНО|r")
        end
        
        if entry.tooltip then
            local locationMatch = string.match(entry.tooltip, "Локация:%s*([^\n\r]+)")
            if locationMatch then
                print("Локация в tooltip (сырая): " .. locationMatch)
                local cleanLocation = locationMatch:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                print("Локация в tooltip (очищенная): " .. cleanLocation)
            else
                print("|cFFFF0000В tooltip не найдена строка 'Локация:'|r")
                print("Первые 200 символов tooltip:")
                print(entry.tooltip:sub(1, 200))
            end
        end
    end

    print("|cff00ccff============================================|r")
end
-- Функция для автоматического показа смертей при открытии карты
function DeathLoggerWorldMap:AutoShowZoneDeathsOnMapOpen()
    if not WMDebug then
        return
    end
    self:CleanupTimers()

    local isMinimized = false
    if WorldMapFrameSizeDownButton and WorldMapFrameSizeDownButton:IsVisible() then
        isMinimized = false
    elseif WorldMapFrameSizeUpButton and WorldMapFrameSizeUpButton:IsVisible() then
        isMinimized = true
    end

    if WorldMapFrame:IsVisible() and not isMinimized then
        local currentZone = self:GetCurrentMapZone()
        local currentContinent = GetCurrentMapContinent()
        
        if not self.lastZoneCheck or (self.lastZoneCheck.zone ~= currentZone or self.lastZoneCheck.continent ~= currentContinent or time() - self.lastZoneCheck.time > 10) then
            self:CreateDelayedUpdate(1.0, function()
                self:Debug("Автоматический показ смертей в зоне: %s", currentZone or "Неизвестно")
                self:ShowDeathsInCurrentZone()
                
                self.lastZoneCheck = {
                    zone = currentZone,
                    continent = currentContinent,
                    time = time()
                }
            end)
        end
    end
end
-- НОВАЯ ФУНКЦИЯ: Принудительное обновление при смене зоны
function DeathLoggerWorldMap:ForceUpdateOnZoneChange()
    self:Debug("Принудительное обновление при смене зоны")
    
    local newZone = self:GetCurrentMapZone()
    local newContinent = GetCurrentMapContinent()
    
    if newZone ~= currentZoneName or newContinent ~= currentContinentID then
        self:Debug("Зона изменилась: %s -> %s", currentZoneName or "nil", newZone or "nil")
        currentZoneName = newZone
        currentContinentID = newContinent
        
        if self.settings and self.settings.enabled then
            self:UpdateMarkers()
            print("|cFF00FF00Death Logger|r: Обновлены маркеры для зоны: " .. (newZone or "Неизвестно"))
        end
    end
end
function DeathLoggerWorldMap:CreateWorldMapControls()
    self:Debug("Создание элементов управления на карте мира")
    if not WorldMapFrame then
        self:Debug("WorldMapFrame не доступен")
        return
    end

    if WorldMapZoomOutButton then
        self:Debug("WorldMapZoomOutButton найден, создаем кнопку")
        
        local button = CreateFrame("Button", "DeathLoggerWorldMapButton", WorldMapFrame)
        button:SetSize(24, 24)
        button:SetPoint("LEFT", WorldMapZoomOutButton, "RIGHT", 5, 0)
        button:SetFrameStrata("HIGH")
        
        local texture = button:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
        texture:SetVertexColor(1, 0, 0)
        button.texture = texture
        
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if DeathLoggerDB and DeathLoggerDB.worldMapSettings and DeathLoggerDB.worldMapSettings.enabled then
                GameTooltip:SetText("Death Logger ✓", 0, 1, 0)
                GameTooltip:AddLine("ЛКМ: выключить маркеры", 1, 1, 1)
            else
                GameTooltip:SetText("Death Logger", 1, 0, 0)
                GameTooltip:AddLine("ЛКМ: включить маркеры", 1, 1, 1)
            end
            GameTooltip:AddLine("ПКМ: показать меню", 1, 1, 1)
            GameTooltip:AddLine("Shift+ПКМ: отладка", 0.5, 0.5, 1)
            GameTooltip:Show()
        end)
        
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        button:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                DeathLoggerWorldMap_Toggle()
            elseif button == "RightButton" then
                if IsShiftKeyDown() then
                    local debugMenu = {
                        {
                            text = "Отладка карты",
                            isTitle = true,
                            notCheckable = true
                        },
                        {
                            text = WMDebug and "|cFF00FF00ВКЛ|r Отладка" or "|cFFFF0000ВЫКЛ|r Отладка",
                            func = function()
                                DeathLoggerWorldMap:ToggleDebug()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Показать информацию",
                            func = function()
                                DeathLoggerWorldMap:ShowDebugInfo()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Показать смерти в зоне",
                            func = function()
                                DeathLoggerWorldMap:ShowDeathsInCurrentZone()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Тест маркеров",
                            func = function()
                                DeathLoggerWorldMap:TestMarkers()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Быстрый тест",
                            func = function()
                                DeathLoggerWorldMap:QuickTest()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Очистить маркеры",
                            func = function()
                                DeathLoggerWorldMap:ClearAllMarkers()
                            end,
                            notCheckable = true
                        }
                    }
                    EasyMenu(debugMenu, UIParent, "cursor", 0, 0, "MENU")
                elseif _G.DeathLoggerWorldMap and _G.DeathLoggerWorldMap.dropdown then
                    ToggleDropDownMenu(1, nil, _G.DeathLoggerWorldMap.dropdown, self, 0, 0)
                end
            end
        end)
        
        self.toggleButton = button
        
        local dropdown = CreateFrame("Frame", "DeathLoggerWorldMapDropdown", WorldMapFrame, "UIDropDownMenuTemplate")
        self.dropdownFrame = dropdown
        dropdown:SetPoint("LEFT", button, "RIGHT", 5, 0)
        dropdown:SetFrameStrata("HIGH")
        
        UIDropDownMenu_Initialize(dropdown, function(self, level)
            DeathLoggerWorldMap:InitializeDropdown(level)
        end)
        
        self.dropdown = dropdown
        
        self:Debug("Элементы управления созданы успешно")
    else
        self:Debug("WorldMapZoomOutButton не найден, используем альтернативное позиционирование")
        
        local button = CreateFrame("Button", "DeathLoggerWorldMapButton", WorldMapFrame)
        button:SetSize(24, 24)
        button:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -50, 10)
        button:SetFrameStrata("HIGH")
        
        local texture = button:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
        texture:SetVertexColor(1, 0, 0)
        button.texture = texture
        
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if DeathLoggerDB and DeathLoggerDB.worldMapSettings and DeathLoggerDB.worldMapSettings.enabled then
                GameTooltip:SetText("Death Logger ✓", 0, 1, 0)
                GameTooltip:AddLine("ЛКМ: выключить маркеры", 1, 1, 1)
            else
                GameTooltip:SetText("Death Logger", 1, 0, 0)
                GameTooltip:AddLine("ЛКМ: включить маркеры", 1, 1, 1)
            end
            GameTooltip:AddLine("ПКМ: показать меню", 1, 1, 1)
            GameTooltip:AddLine("Shift+ПКМ: отладка", 0.5, 0.5, 1)
            GameTooltip:Show()
        end)
        
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        button:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                DeathLoggerWorldMap_Toggle()
            elseif button == "RightButton" then
                if IsShiftKeyDown() then
                    local debugMenu = {
                        {
                            text = "Отладка карты",
                            isTitle = true,
                            notCheckable = true
                        },
                        {
                            text = WMDebug and "|cFF00FF00ВКЛ|r Отладка" or "|cFFFF0000ВЫКЛ|r Отладка",
                            func = function()
                                DeathLoggerWorldMap:ToggleDebug()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Показать информацию",
                            func = function()
                                DeathLoggerWorldMap:ShowDebugInfo()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Показать смерти в зоне",
                            func = function()
                                DeathLoggerWorldMap:ShowDeathsInCurrentZone()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Тест маркеров",
                            func = function()
                                DeathLoggerWorldMap:TestMarkers()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Быстрый тест",
                            func = function()
                                DeathLoggerWorldMap:QuickTest()
                            end,
                            notCheckable = true
                        },
                        {
                            text = "Очистить маркеры",
                            func = function()
                                DeathLoggerWorldMap:ClearAllMarkers()
                            end,
                            notCheckable = true
                        }
                    }
                    EasyMenu(debugMenu, UIParent, "cursor", 0, 0, "MENU")
                elseif _G.DeathLoggerWorldMap and _G.DeathLoggerWorldMap.dropdown then
                    ToggleDropDownMenu(1, nil, _G.DeathLoggerWorldMap.dropdown, self, 0, 0)
                end
            end
        end)
        
        local dropdown = CreateFrame("Frame", "DeathLoggerWorldMapDropdown", WorldMapFrame, "UIDropDownMenuTemplate")
        self.dropdownFrame = dropdown
        dropdown:SetPoint("LEFT", button, "RIGHT", 5, 0)
        dropdown:SetFrameStrata("HIGH")
        
        UIDropDownMenu_Initialize(dropdown, function(self, level)
            DeathLoggerWorldMap:InitializeDropdown(level)
        end)
        
        self.toggleButton = button
        self.dropdown = dropdown
        self:Debug("Кнопка создана в альтернативном месте")
    end

    self:UpdateButtonAppearance()
    self:UpdateDropdownText()

    -- По умолчанию скрываем кнопку (будет показана при открытии карты)
    if self.toggleButton then
        self.toggleButton:Hide()
    end
    if self.dropdown then
        self.dropdown:Hide()
    end
end
function DeathLoggerWorldMap:UpdateButtonAppearance()
    if not self.toggleButton or not self.toggleButton.texture then
        self:Debug("Кнопка или текстура не найдены")
        return
    end
    if not self.settings then
        if DeathLoggerDB and DeathLoggerDB.worldMapSettings then
            self.settings = DeathLoggerDB.worldMapSettings
        else
            return
        end
    end

    if self.settings and self.settings.enabled then
        self.toggleButton.texture:SetVertexColor(0, 1, 0)
        self:Debug("Кнопка обновлена: зеленый")
    else
        self.toggleButton.texture:SetVertexColor(1, 0, 0)
        self:Debug("Кнопка обновлена: красный")
    end
end
function DeathLoggerWorldMap:InitializeDropdown(level)
    self:Debug("Инициализация dropdown, уровень: %d", level)
    if not level then return end

    if not self.settings then
        if not DeathLoggerDB then
            DeathLoggerDB = {
                entries = {},
                worldMapSettings = {},
                locationHistory = {}
            }
        end
        DeathLoggerDB.worldMapSettings = DeathLoggerDB.worldMapSettings or {}
        for k, v in pairs(DEFAULT_SETTINGS) do
            if DeathLoggerDB.worldMapSettings[k] == nil then
                DeathLoggerDB.worldMapSettings[k] = v
            end
        end
        self.settings = DeathLoggerDB.worldMapSettings
    end

    local info = UIDropDownMenu_CreateInfo()

    if level == 1 then
        info.isTitle = true
        info.text = "Death Logger"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        
        info.isTitle = false
        info.notCheckable = false
        
        info.text = "Включить маркеры"
        info.checked = self.settings.enabled
        info.func = function()
            self:ToggleEnabled()
            self:UpdateButtonAppearance()
        end
        UIDropDownMenu_AddButton(info, level)
        
        info.disabled = false
        info.checked = nil
        
        info.text = "  "
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        
        info.disabled = false
        info.text = "Показать смерти"
        info.checked = self.settings.showDeathMarkers
        info.func = function()
            self.settings.showDeathMarkers = not self.settings.showDeathMarkers
            DeathLoggerDB.worldMapSettings.showDeathMarkers = self.settings.showDeathMarkers
            self:ScheduleUpdate()
        end
        UIDropDownMenu_AddButton(info, level)
        
        info.text = "Показать завершения"
        info.checked = self.settings.showChallengeMarkers
        info.func = function()
            self.settings.showChallengeMarkers = not self.settings.showChallengeMarkers
            DeathLoggerDB.worldMapSettings.showChallengeMarkers = self.settings.showChallengeMarkers
            self:ScheduleUpdate()
        end
        UIDropDownMenu_AddButton(info, level)
        
        info.text = "Показать тултипы"
        info.checked = self.settings.showTooltips
        info.func = function()
            self.settings.showTooltips = not self.settings.showTooltips
            DeathLoggerDB.worldMapSettings.showTooltips = self.settings.showTooltips
        end
        UIDropDownMenu_AddButton(info, level)
        
        info.text = "  "
        info.disabled = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        
        info.disabled = false
        info.text = "Фильтры"
        info.hasArrow = true
        info.notCheckable = true
        info.value = "filters"
        UIDropDownMenu_AddButton(info, level)
        
        info.text = "Настройки"
        info.hasArrow = true
        info.value = "settings"
        UIDropDownMenu_AddButton(info, level)
        
        info.hasArrow = true
        info.text = "Отладка"
        info.value = "debug"
        UIDropDownMenu_AddButton(info, level)
        
        info.hasArrow = false
        info.text = "Обновить маркеры"
        info.notCheckable = true
        info.func = function()
            self:ScheduleUpdate()
            print("|cFF00FF00Death Logger|r: Маркеры обновлены")
        end
        UIDropDownMenu_AddButton(info, level)
        
    elseif level == 2 then
        local value = UIDROPDOWNMENU_MENU_VALUE
        
        if value == "filters" then
            info.isTitle = true
            info.text = "Фильтры"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
            info.isTitle = false
            
            info.text = "Фильтровать по уровню"
            info.checked = self.settings.filterByLevel
            info.func = function()
                self.settings.filterByLevel = not self.settings.filterByLevel
                DeathLoggerDB.worldMapSettings.filterByLevel = self.settings.filterByLevel
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Фракция: " .. (self.settings.filterByFaction == "ALL" and "Все" or 
                        self.settings.filterByFaction == "ALLIANCE" and "Альянс" or "Орда")
            info.hasArrow = true
            info.value = "faction"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
            info.hasArrow = false
            info.text = "Только моя гильдия"
            info.checked = self.settings.filterByGuild
            info.func = function()
                self.settings.filterByGuild = not self.settings.filterByGuild
                DeathLoggerDB.worldMapSettings.filterByGuild = self.settings.filterByGuild
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Показать мои смерти"
            info.checked = self.settings.showPlayerDeaths
            info.func = function()
                self.settings.showPlayerDeaths = not self.settings.showPlayerDeaths
                DeathLoggerDB.worldMapSettings.showPlayerDeaths = self.settings.showPlayerDeaths
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
             
            info.text = "Показать смерти гильдии"
            info.checked = self.settings.showGuildDeaths
            info.func = function()
                self.settings.showGuildDeaths = not self.settings.showGuildDeaths
                DeathLoggerDB.worldMapSettings.showGuildDeaths = self.settings.showGuildDeaths
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "  "
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
            info.disabled = false
            info.text = "Только текущая зона"
            info.checked = self.settings.filterByZone
            info.func = function()
                self.settings.filterByZone = not self.settings.filterByZone
                DeathLoggerDB.worldMapSettings.filterByZone = self.settings.filterByZone
                self:ForceUpdateOnZoneChange()
                print("|cFF00FF00Death Logger|r: Фильтрация по зоне " .. (self.settings.filterByZone and "ВКЛЮЧЕНА" or "ВЫКЛЮЧЕНА"))
            end
            UIDropDownMenu_AddButton(info, level)
            
        elseif value == "settings" then
            info.isTitle = true
            info.text = "Настройки"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
            info.isTitle = false
            
            local sizeText = "Маленький"
            if self.settings.markerSize == 16 then
                sizeText = "Средний"
            elseif self.settings.markerSize == 24 then
                sizeText = "Большой"
            end
            
            info.text = "Размер маркеров: " .. sizeText
            info.hasArrow = true
            info.value = "markerSize"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
            info.hasArrow = false
            info.text = "Кластеризация"
            info.checked = self.settings.clusterRadius > 0
            info.func = function()
                if self.settings.clusterRadius > 0 then
                    self.settings.clusterRadius = 0
                else
                    self.settings.clusterRadius = 50
                end
                DeathLoggerDB.worldMapSettings.clusterRadius = self.settings.clusterRadius
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Макс. маркеров: " .. self.settings.maxMarkers
            info.hasArrow = true
            info.value = "maxMarkers"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
        elseif value == "faction" then
            info.text = "Все фракции"
            info.checked = self.settings.filterByFaction == "ALL"
            info.func = function()
                self.settings.filterByFaction = "ALL"
                DeathLoggerDB.worldMapSettings.filterByFaction = "ALL"
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Альянс и нейтральные"
            info.checked = self.settings.filterByFaction == "ALLIANCE"
            info.func = function()
                self.settings.filterByFaction = "ALLIANCE"
                DeathLoggerDB.worldMapSettings.filterByFaction = "ALLIANCE"
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Орда и нейтральные"
            info.checked = self.settings.filterByFaction == "HORDE"
            info.func = function()
                self.settings.filterByFaction = "HORDE"
                DeathLoggerDB.worldMapSettings.filterByFaction = "HORDE"
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
        elseif value == "markerSize" then
            info.text = "Маленький (12px)"
            info.checked = self.settings.markerSize == 12
            info.func = function()
                self.settings.markerSize = 12
                DeathLoggerDB.worldMapSettings.markerSize = 12
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Средний (16px)"
            info.checked = self.settings.markerSize == 16
            info.func = function()
                self.settings.markerSize = 16
                DeathLoggerDB.worldMapSettings.markerSize = 16
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Большой (24px)"
            info.checked = self.settings.markerSize == 24
            info.func = function()
                self.settings.markerSize = 24
                DeathLoggerDB.worldMapSettings.markerSize = 24
                self:ScheduleUpdate()
            end
            UIDropDownMenu_AddButton(info, level)
            
        elseif value == "maxMarkers" then
            local markersList = {50, 100, 200, 500}
            for _, count in ipairs(markersList) do
                info.text = tostring(count) .. " маркеров"
                info.checked = self.settings.maxMarkers == count
                info.func = function()
                    self.settings.maxMarkers = count
                    DeathLoggerDB.worldMapSettings.maxMarkers = count
                    self:ScheduleUpdate()
                end
                UIDropDownMenu_AddButton(info, level)
            end
            
        elseif value == "debug" then
            info.isTitle = true
            info.text = "Отладка карты"
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
            
            info.isTitle = false
            info.notCheckable = true
            
            info.text = WMDebug and "|cFF00FF00ВКЛ|r Отладка" or "|cFFFF0000ВЫКЛ|r Отладка"
            info.func = function()
                DeathLoggerWorldMap:ToggleDebug()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Показать информацию"
            info.func = function()
                DeathLoggerWorldMap:ShowDebugInfo()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Показать смерти в зоне"
            info.func = function()
                DeathLoggerWorldMap:ShowDeathsInCurrentZone()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Тест маркеров"
            info.func = function()
                DeathLoggerWorldMap:TestMarkers()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Быстрый тест (центр карты)"
            info.func = function()
                DeathLoggerWorldMap:QuickTest()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Очистить все маркеры"
            info.func = function()
                DeathLoggerWorldMap:ClearAllMarkers()
            end
            UIDropDownMenu_AddButton(info, level)
            
            info.text = "Экспорт локаций"
            info.func = function()
                DeathLoggerWorldMap:ExportLocationData()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end
-- Функция отображения отладочной информации
function DeathLoggerWorldMap:ShowDebugInfo()
    print("|cff00ccff========== DeathLogger WorldMap Debug Info ==========|r")
    print("Версия модуля карты: 1.0")
    print("Отладка: " .. (WMDebug and "|cFF00FF00ВКЛ|r" or "|cFFFF0000ВЫКЛ|r"))
    print("Состояние модуля: " .. (self.settings and self.settings.enabled and "|cFF00FF00Включен|r" or "|cFFFF0000Выключен|r"))
    print("Родительский фрейм: " .. (self.parentFrame and "|cFF00FF00Создан|r" or "|cFFFF0000Отсутствует|r"))
    if self.parentFrame then
        print("  Видимость: " .. (self.parentFrame:IsVisible() and "|cFF00FF00Видим|r" or "|cFFFF0000Скрыт|r"))
    end

    print("Кнопка переключения: " .. (self.toggleButton and "|cFF00FF00Создана|r" or "|cFFFF0000Отсутствует|r"))
    print("Dropdown меню: " .. (self.dropdown and "|cFF00FF00Создан|r" or "|cFFFF0000Отсутствует|r"))
    print("Маркеры: " .. (#self.markers > 0 and "|cFF00FF00" .. #self.markers .. " шт.|r" or "|cFFFF0000Нет|r"))

    if DeathLoggerDB then
        print("Записей в DeathLoggerDB: " .. (#DeathLoggerDB.entries or 0))
        print("Настроек карты: " .. (DeathLoggerDB.worldMapSettings and "|cFF00FF00Есть|r" or "|cFFFF0000Нет|r"))
        print("Истории локаций: " .. (DeathLoggerDB.locationHistory and "|cFF00FF00Есть|r" or "|cFFFF0000Нет|r"))
    else
        print("DeathLoggerDB: |cFFFF0000Отсутствует|r")
    end

    local continent = GetCurrentMapContinent()
    local mapID = GetCurrentMapAreaID()
    local zone = GetZoneText()

    print("Текущий континент: " .. (continent or "N/A"))
    print("ID карты: " .. (mapID or "N/A"))
    print("Зона: " .. (zone or "N/A"))
    print("Текущая зона (отслеживание): " .. (currentZoneName or "N/A"))
    print("Текущий континент (отслеживание): " .. (currentContinentID or "N/A"))

    local x, y = GetPlayerMapPosition("player")
    if x and y and x > 0 and y > 0 then
        print("Координаты игрока: " .. string.format("%.2f, %.2f", x * 100, y * 100))
    else
        print("Координаты игрока: |cFFFF0000Недоступны|r")
    end

    print("|cff00ccff============================================|r")
end
-- Функция тестирования маркеров
function DeathLoggerWorldMap:TestMarkers()
    self:Debug("Запуск теста маркеров")
    if not self.parentFrame then
        print("|cFFFF0000Death Logger|r: Родительский фрейм не создан")
        return
    end

    if not self.parentFrame:IsVisible() then
        self:Debug("parentFrame не видим, показываем его")
        self.parentFrame:Show()
    end

    local testMarkers = {
        {x = 0.1, y = 0.1, color = {1, 0, 0}, text = "Тест 1 (Левый верх)"},
        {x = 0.9, y = 0.1, color = {0, 1, 0}, text = "Тест 2 (Правый верх)"},
        {x = 0.1, y = 0.9, color = {0, 0, 1}, text = "Тест 3 (Левый низ)"},
        {x = 0.9, y = 0.9, color = {1, 1, 0}, text = "Тест 4 (Правый низ)"},
        {x = 0.5, y = 0.5, color = {1, 0, 1}, text = "Центр карты"}
    }

    for i, test in ipairs(testMarkers) do
        local marker = CreateFrame("Button", "DeathLoggerTestMarker" .. i, self.parentFrame)
        marker:SetSize(20, 20)
        marker:SetFrameStrata("HIGH")
        
        local texture = marker:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        texture:SetVertexColor(unpack(test.color))
        
        local mapWidth = WorldMapFrame:GetWidth()
        local mapHeight = WorldMapFrame:GetHeight()
        
        self:Debug("Размеры карты: %dx%d", mapWidth, mapHeight)
        
        marker:SetPoint("CENTER", self.parentFrame, "TOPLEFT", 
            test.x * mapWidth, -test.y * mapHeight)
        
        marker:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Тестовый маркер " .. i)
            GameTooltip:AddLine(test.text, 1, 1, 1)
            GameTooltip:AddLine(string.format("Координаты: %.1f, %.1f", test.x * 100, test.y * 100), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        
        marker:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        marker:Show()
        
        if not self.testMarkers then
            self.testMarkers = {}
        end
        table.insert(self.testMarkers, marker)
    end

    print("|cFF00FF00Death Logger|r: Тестовые маркеры созданы")
    self:Debug("Создано %d тестовых маркеров", #testMarkers)
end
-- Функция быстрого теста
function DeathLoggerWorldMap:QuickTest()
    self:Debug("=== БЫСТРЫЙ ТЕСТ МАРКЕРОВ ===")
    if not WorldMapFrame or not WorldMapFrame:IsVisible() then
        print("|cFFFF0000Death Logger|r: Откройте карту мира сначала!")
        return
    end

    if not self.parentFrame then
        self:Debug("parentFrame не создан, инициализируем")
        self:LazyInit()
    end

    if not self.parentFrame then
        print("|cFFFF0000Death Logger|r: Не удалось создать родительский фрейм")
        return
    end

    if not self.parentFrame:IsVisible() then
        self:Debug("parentFrame не видим, показываем его")
        self.parentFrame:Show()
    end

    if self.testMarkers then
        for _, marker in pairs(self.testMarkers) do
            if marker then
                marker:Hide()
                marker:SetParent(nil)
            end
        end
    end

    local testMarker = CreateFrame("Button", nil, self.parentFrame)
    testMarker:SetSize(20, 20)
    testMarker:SetFrameStrata("HIGH")

    local texture = testMarker:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
    texture:SetVertexColor(0, 1, 0)

    testMarker:SetPoint("CENTER", self.parentFrame, "CENTER", 0, 0)

    testMarker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Тестовый маркер", 0, 1, 0)
        GameTooltip:AddLine("Быстрый тест - центр карты", 1, 1, 1)
        GameTooltip:Show()
    end)

    testMarker:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    testMarker:Show()

    if not self.testMarkers then
        self.testMarkers = {}
    end
    table.insert(self.testMarkers, testMarker)

    print("|cFF00FF00Death Logger|r: Тестовый маркер создан в центре карты")
    self:Debug("Тестовый маркер создан в центре карты")
end
-- Функция очистки всех маркеров
function DeathLoggerWorldMap:ClearAllMarkers()
    self:Debug("Очистка всех маркеров")
    if self.markers then
        for _, marker in pairs(self.markers) do
            if marker then
                marker:Hide()
                marker:SetParent(nil)
            end
        end
        self.markers = {}
    end

    if self.testMarkers then
        for _, marker in pairs(self.testMarkers) do
            if marker then
                marker:Hide()
                marker:SetParent(nil)
            end
        end
        self.testMarkers = {}
    end

    print("|cFF00FF00Death Logger|r: Все маркеры очищены")
end
-- Функция экспорта данных локаций
function DeathLoggerWorldMap:ExportLocationData()
    self:Debug("Экспорт данных локаций")
    if not self.locationData or not next(self.locationData) then
        print("|cFFFF0000Death Logger|r: Нет данных локаций для экспорта")
        return
    end

    print("|cff00ccff========== Экспорт данных локаций ==========|r")
    for location, data in pairs(self.locationData) do
        print(string.format("%s: x=%.2f, y=%.2f, zone=%s, continent=%d",
            location, data.x or 0, data.y or 0, data.zone or "?", data.continent or 0))
    end
    print("|cff00ccff===========================================|r")
end
-- ИСПРАВЛЕННАЯ ФУНКЦИЯ: Уникальные ID для каждой зоны
function DeathLoggerWorldMap:InitMapIDTable()
    self.mapIDtoName = {
        -- Калимдор
        [1] = "Дуротар",
        [7] = "Мулгор",
        [10] = "Степи",
        [12] = "Скалистые горы",
        [14] = "Ясеневый лес",
        [15] = "Тысяча Игл",
        [17] = "Пылевые топи",
        [41] = "Танарис",
        [43] = "Фералас",
        [16] = "Азшара",
        [3524] = "Остров Лазурной Дымки",
        [490] = "Ун'Горо",
        [1377] = "Силитус",
        [618] = "Зимние Ключи",
        [47] = "Внутренние земли",
        [46] = "Выжженные земли",
        [400] = "Когтистые горы",
        -- Восточные Королевства
        [85] = "Тирисфальские леса",
        [137] = "Элвиннский лес",
        [1] = "Дун Морог",
        [141] = "Тельдрассил",
        [10] = "Чернолесье",
        [44] = "Красногорье",
        [8] = "Сумеречный лес",
        [45] = "Нагорье Арати",
        [11] = "Внутренние земли",
        [130] = "Болотина",
        [33] = "Тернистая долина",
        [3] = "Нагорье Арати",
        [4] = "Бесплодные земли",
        [51] = "Выжженные земли",
        [139] = "Западные Чумные земли",
        [28] = "Восточные Чумные земли",
        [38] = "Лок Модан",
        [36] = "Нагорье Арати",
        
        -- Запределье
        [3483] = "Пустоверть",
        [3521] = "Зангартопь",
        [3519] = "Лес Террокар",
        [3518] = "Награнд",
        [3522] = "Острогорье",
        [3520] = "Долина Призрачной Луны",
        [3487] = "Полуостров Адского Пламени",
        [3703] = "Шаттрат",
        
        -- Нордскол (ИСПРАВЛЕНО: уникальные ID для каждой зоны)
        [3537] = "Драконий Погост",
        [3538] = "Борейская тундра",
        [3539] = "Ревущий фьорд",
        [3540] = "Лес Хрустальной Песни",
        [3541] = "Зул'Драк",
        [3542] = "Низина Шолазар",
        [3543] = "Грозовая Гряда",
        [3544] = "Ледяная Корона",
        [4395] = "Даларан",
        
        -- Альтернативные ID (для совместимости)
        [1421] = "Дуротар",
        [1417] = "Мулгор",
        [1418] = "Степи",
        [1419] = "Скалистые горы",
        [1438] = "Тельдрассил",
        [1431] = "Дун Морог",
        [1420] = "Тирисфальские леса",
        [1426] = "Красногорье",
        [1437] = "Элвиннский лес",
        [1432] = "Чернолесье",
        [1433] = "Сумеречный лес",
    }
end
-- ИСПРАВЛЕННАЯ ФУНКЦИЯ: Реальные координаты для городов
function DeathLoggerWorldMap:LoadLocationData()
    self.locationData = {
        -- Восточные Королевства
        ["Штормград"] = { x = 0.67, y = 0.73, zone = "Элвиннский лес", continent = 2 },
        ["Стальгорн"] = { x = 0.52, y = 0.15, zone = "Дун Морог", continent = 2 },
        ["Подгород"] = { x = 0.63, y = 0.43, zone = "Тирисфальские леса", continent = 2 },
        ["Каражан"] = { x = 0.45, y = 0.65, zone = "Красногорье", continent = 2 },
        ["Шаттрат"] = { x = 0.54, y = 0.39, zone = "Лес Террокар", continent = 3 },
        -- Калимдор
        ["Оргриммар"] = { x = 0.31, y = 0.38, zone = "Дуротар", continent = 1 },
        ["Громовой Утес"] = { x = 0.45, y = 0.52, zone = "Мулгор", continent = 1 },
        ["Дарнасс"] = { x = 0.35, y = 0.25, zone = "Тельдрассил", continent = 1 },
        ["Экзодар"] = { x = 0.25, y = 0.15, zone = "Остров Лазурной Дымки", continent = 1 },
        
        -- Нордскол
        ["Даларан"] = { x = 0.42, y = 0.54, zone = "Ледяная Корона", continent = 4 },
        
        -- Подземелья
        ["Мертвые копи"] = { x = 0.40, y = 0.60, zone = "Красногорье", continent = 2 },
        ["Монастырь Алого Ордена"] = { x = 0.60, y = 0.40, zone = "Тирисфальские леса", continent = 2 },
        ["Некроситет"] = { x = 0.55, y = 0.55, zone = "Западные Чумные земли", continent = 2 },
        ["Курганы Иглошкурых"] = { x = 0.35, y = 0.45, zone = "Степи", continent = 1 },
    }

    -- Загружаем историю локаций из сохраненных данных
    if DeathLoggerDB and DeathLoggerDB.locationHistory then
        for location, coords in pairs(DeathLoggerDB.locationHistory) do
            if not self.locationData[location] then
                self.locationData[location] = coords
            end
        end
    end
end
function DeathLoggerWorldMap:CompareZones(zone1, zone2)
    if not zone1 or not zone2 then return false end
    local z1 = strlower(zone1)
    local z2 = strlower(zone2)

    if z1 == z2 then return true end

    local function normalize(str)
        str = str:gsub("^the%s+", ""):gsub("%s+the%s+", " ")
        str = str:gsub("%s+", " "):trim()
        return str
    end

    local n1 = normalize(z1)
    local n2 = normalize(z2)

    if n1 == n2 then return true end

    if string.find(z1, z2, 1, true) or string.find(z2, z1, 1, true) then
        return true
    end

    return false
end
function DeathLoggerWorldMap:DiagnoseDatabase()
    print("|cff00ccff========== ДИАГНОСТИКА БАЗЫ ДАННЫХ ==========|r")
    if not DeathLoggerDB then
        print("DeathLoggerDB: |cFFFF0000НЕ СУЩЕСТВУЕТ|r")
        return
    end

    print("DeathLoggerDB: |cFF00FF00СУЩЕСТВУЕТ|r")
    print("Тип DeathLoggerDB: " .. type(DeathLoggerDB))

    if not DeathLoggerDB.entries then
        print("DeathLoggerDB.entries: |cFFFF0000НЕ СУЩЕСТВУЕТ|r")
        return
    end

    print("DeathLoggerDB.entries: |cFF00FF00СУЩЕСТВУЕТ|r")
    print("Тип entries: " .. type(DeathLoggerDB.entries))
    print("Длина entries: " .. #DeathLoggerDB.entries)

    print("  ")
    print("|cFF00FF00Первые 5 записей:|r ")
    for i = 1, math.min(5, #DeathLoggerDB.entries) do
        local entry = DeathLoggerDB.entries[i]
        print(string.format("%d. Тип: %s", i, type(entry)))
        
        if type(entry) == "table" then
            local keys = {}
            for k, v in pairs(entry) do
                table.insert(keys, tostring(k))
            end
            print("   |cFFFFFF00Ключи:|r " .. table.concat(keys, ", "))
            
            print("   |cFFFFFF00playerName:|r " .. tostring(entry.playerName or "НЕТ"))
            print("   |cFFFFFF00class:|r " .. tostring(entry.class or "НЕТ"))
            print("   |cFFFFFF00faction:|r " .. tostring(entry.faction or "НЕТ"))
            print("   |cFFFFFF00level:|r " .. tostring(entry.level or "НЕТ"))
            print("   |cFFFFFF00timestamp:|r " .. tostring(entry.timestamp or "НЕТ") .. 
                  (entry.timestamp and (" (" .. date("%Y-%m-%d %H:%M", entry.timestamp) .. ")") or ""))
            print("   |cFFFFFF00parseGuild:|r " .. tostring(entry.parseGuild or "НЕТ"))
            
            local location = "НЕТ"
            if entry.tooltip then
                local locationMatch = string.match(entry.tooltip, "Локация:%s*([^\n\r]+)")
                if locationMatch then
                    location = locationMatch:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                end
                print("   |cFFFFFF00tooltip (первые 100 символов):|r " .. entry.tooltip:sub(1, 100):gsub("\n", "   "))
            end
            print("   |cFFFFFF00локация (из tooltip):|r " .. location)
        end
        print("---")
    end

    print("  ")
    print("|cFF00FF00Статистика по локациям:|r ")
    local locationStats = {}
    for i, entry in ipairs(DeathLoggerDB.entries) do
        if type(entry) == "table" and entry.tooltip then
            local location = string.match(entry.tooltip, "Локация:%s*([^\n\r]+)")
            if location then
                location = location:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                locationStats[location] = (locationStats[location] or 0) + 1
            end
        end
    end

    if next(locationStats) then
        for location, count in pairs(locationStats) do
            print(string.format("   %s: %d смертей", location, count))
        end
    else
        print("   Нет данных о локациях")
    end

    print("|cff00ccff============================================|r")
end
function DeathLoggerWorldMap:ParseLocation(entry)
    if not entry then
        self:Debug("ParseLocation: entry отсутствует")
        return nil
    end
    self:Debug("Парсинг локации для %s", entry.playerName or "nil")

    if entry.tooltip and entry.tooltip ~= "" then
        local locationMatch = string.match(entry.tooltip, "Локация:%s*([^\n\r]+)")
        
        if locationMatch then
            local cleanLocation = locationMatch:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
            self:Debug("Извлечена локация из tooltip: %s", cleanLocation)
            
            local continent = self:GetZoneMapID(cleanLocation)
            local x, y = 0.5, 0.5
            
            if self.locationData and self.locationData[cleanLocation] then
                x = self.locationData[cleanLocation].x or 0.5
                y = self.locationData[cleanLocation].y or 0.5
                continent = self.locationData[cleanLocation].continent or continent
            end
            
            return {
                x = x,
                y = y,
                zone = cleanLocation,
                continent = continent or 0,
                rawLocation = cleanLocation
            }
        else
            local altMatch = string.match(entry.tooltip, "Место:%s*([^\n\r]+)") or
                            string.match(entry.tooltip, "Зона:%s*([^\n\r]+)")
            
            if altMatch then
                local cleanLocation = altMatch:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
                self:Debug("Извлечена альтернативная локация: %s", cleanLocation)
                
                return {
                    x = 0.5, y = 0.5,
                    zone = cleanLocation,
                    continent = self:GetZoneMapID(cleanLocation) or 0,
                    rawLocation = cleanLocation
                }
            end
        end
    end

    if entry.location and entry.location ~= "" then
        self:Debug("Используем поле location: %s", entry.location)
        return {
            x = 0.5, y = 0.5,
            zone = entry.location,
            continent = self:GetZoneMapID(entry.location) or 0,
            rawLocation = entry.location
        }
    end

    self:Debug("Не удалось определить локацию для %s", entry.playerName or "nil")
    return nil
end
function DeathLoggerWorldMap:GetEnglishZoneName(russianName)
    if not russianName then return nil end
    local zoneTranslation = {
        ["Дуротар"] = "Durotar",
        ["Мулгор"] = "Mulgore",
        ["Степи"] = "The Barrens",
        ["Скалистые горы"] = "Stonetalon Mountains",
        ["Ясеневый лес"] = "Ashenvale",
        ["Тысяча Игл"] = "Thousand Needles",
        ["Пылевые топи"] = "Dustwallow Marsh",
        ["Танарис"] = "Tanaris",
        ["Фералас"] = "Feralas",
        ["Азшара"] = "Azshara",
        ["Ун'Горо"] = "Un'Goro Crater",
        ["Силитус"] = "Silithus",
        ["Зимние Ключи"] = "Winterspring",
        ["Когтистые горы"] = "Felwood",
        
        ["Тирисфальские леса"] = "Tirisfal Glades",
        ["Элвиннский лес"] = "Elwynn Forest",
        ["Дун Морог"] = "Dun Morogh",
        ["Тельдрассил"] = "Teldrassil",
        ["Чернолесье"] = "Duskwood",
        ["Красногорье"] = "Redridge Mountains",
        ["Сумеречный лес"] = "Twilight Grove",
        ["Нагорье Арати"] = "Arathi Highlands",
        ["Внутренние земли"] = "The Hinterlands",
        ["Болотина"] = "Swamp of Sorrows",
        ["Тернистая долина"] = "Stranglethorn Vale",
        ["Бесплодные земли"] = "Badlands",
        ["Выжженные земли"] = "Blasted Lands",
        ["Западные Чумные земли"] = "Western Plaguelands",
        ["Восточные Чумные земли"] = "Eastern Plaguelands",
        ["Лок Модан"] = "Loch Modan",
        
        ["Пустоверть"] = "Hellfire Peninsula",
        ["Зангартопь"] = "Zangarmarsh",
        ["Лес Террокар"] = "Terokkar Forest",
        ["Награнд"] = "Nagrand",
        ["Острогорье"] = "Blade's Edge Mountains",
        ["Долина Призрачной Луны"] = "Shadowmoon Valley",
        ["Полуостров Адского Пламени"] = "Hellfire Peninsula",
        ["Шаттрат"] = "Shattrath City",
        
        ["Драконий Погост"] = "Dragonblight",
        ["Борейская тундра"] = "Borean Tundra",
        ["Ревущий фьорд"] = "Howling Fjord",
        ["Лес Хрустальной Песни"] = "Crystalsong Forest",
        ["Зул'Драк"] = "Zul'Drak",
        ["Низина Шолазар"] = "Sholazar Basin",
        ["Грозовая Гряда"] = "Storm Peaks",
        ["Ледяная Корона"] = "Icecrown",
        ["Даларан"] = "Dalaran",
        
        ["Каражан"] = "Karazhan",
        ["Зул'Гуруб"] = "Zul'Gurub",
        ["Руины Ан'Киража"] = "Ruins of Ahn'Qiraj",
        ["Ан'Кираж"] = "Ahn'Qiraj",
        ["Испытания"] = "The Stockade",
        ["Тюрьма"] = "The Stockade",
        ["Мертвые копи"] = "Deadmines",
        ["Пещеры Стенаний"] = "Wailing Caverns",
        ["Крепость Темного Клыка"] = "Shadowfang Keep",
        ["Лабиринты Иглошкурых"] = "Razorfen Downs",
        ["Курганы Иглошкурых"] = "Razorfen Kraul",
        ["Монастырь Алого Ордена"] = "Scarlet Monastery",
        ["Гномреган"] = "Gnomeregan",
        ["Ульдаман"] = "Uldaman",
        ["Марадон"] = "Maraudon",
        ["Забытый Город"] = "The Temple of Atal'Hakkar",
        ["Черная Гора"] = "Blackrock Mountain",
        ["Черная Гора: Нижний Пик"] = "Blackrock Spire",
        ["Черная Гора: Верхний Пик"] = "Blackrock Spire",
        ["Стратхольм"] = "Stratholme",
        ["Некроситет"] = "Scholomance",
        ["Кузня Крови"] = "The Blood Furnace",
        ["Пещеры Времени"] = "Caverns of Time",
        ["Черные топи"] = "The Black Morass",
        ["Старые топи"] = "The Black Morass",
        ["Бастионы Адского Пламени"] = "Hellfire Ramparts",
        ["Цитадель Адского Пламени"] = "Hellfire Citadel",
        ["Аметистовая Крепость"] = "Magisters' Terrace",
        ["Платформа Наару"] = "The Botanica",
        ["Техника"] = "The Mechanar",
        ["Аркатрац"] = "The Arcatraz",
        ["Змеиное Святилище"] = "Serpentshrine Cavern",
        ["Крепость Бурь"] = "Tempest Keep",
        ["Черный Храм"] = "Black Temple",
        ["Гундрак"] = "Gundrak",
        ["Ан'кахет"] = "Ahn'kahet: The Old Kingdom",
        ["Азжол-Неруб"] = "Azjol-Nerub",
        ["Нексус"] = "The Nexus",
        ["Окулус"] = "The Oculus",
        ["Утгардская Крепость"] = "Utgarde Keep",
        ["Утгардские Вершины"] = "Utgarde Pinnacle",
        ["Чертоги Молний"] = "Halls of Lightning",
        ["Чертоги Отражений"] = "Halls of Reflection",
        ["Чертоги Камня"] = "Halls of Stone",
        ["Крепость Плети"] = "The Forge of Souls",
        ["Яма Сарона"] = "The Pit of Saron",
        ["Испытание Чемпиона"] = "Trial of the Champion",
        ["Испытание Крестоносца"] = "Trial of the Crusader",
        ["Ледяной Трон"] = "Icecrown Citadel",
        ["Очищение Стратхольма"] = "Culling of Stratholme",
    }

    if zoneTranslation[russianName] then
        return zoneTranslation[russianName]
    end

    for ruName, enName in pairs(zoneTranslation) do
        if string.find(russianName, ruName) or string.find(ruName, russianName) then
            self:Debug("Найдено частичное совпадение: %s -> %s", ruName, enName)
            return enName
        end
    end

    return nil
end
function DeathLoggerWorldMap:ExtractZoneName(locationStr)
    if not locationStr then return nil end
    self:Debug("ExtractZoneName из: %s", locationStr)

    local cleanStr = locationStr:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()

    if cleanStr == "" then return nil end

    if cleanStr:match("^%d+[.,]?%d*%s*[,;:]%s*%d+[.,]?%d*$") then
        self:Debug("Строка содержит только координаты")
        return nil
    end

    local zoneName = cleanStr

    local match = cleanStr:match("^(.-)[%s,;:]+%d")
    if match then
        zoneName = match:trim()
        self:Debug("Извлечено по паттерну с цифрами: %s", zoneName)
    else
        match = cleanStr:match("^([^,]+)")
        if match then
            zoneName = match:trim()
            self:Debug("Извлечено по запятой: %s", zoneName)
        end
    end

    return zoneName
end
function DeathLoggerWorldMap:ShouldShowMarker(entry)
    if not self.settings then
        self:Debug("ShouldShowMarker: настройки не загружены")
        return false
    end
    if not entry or not entry.name then
        self:Debug("ShouldShowMarker: entry или entry.name отсутствует")
        return false
    end

    if entry.causeID == 11 and not self.settings.showChallengeMarkers then
        self:Debug("Маркер завершения скрыт по настройкам")
        return false
    elseif entry.causeID ~= 11 and not self.settings.showDeathMarkers then
        self:Debug("Маркер смерти скрыт по настройкам")
        return false
    end

    if self.settings.filterByLevel then
        local level = entry.level or 0
        if level < self.settings.minLevel or level > self.settings.maxLevel then
            self:Debug("Уровень %d вне диапазона %d-%d", level, self.settings.minLevel, self.settings.maxLevel)
            return false
        end
    end

    if self.settings.filterByFaction ~= "ALL" then
        local faction = entry.side or "Нейтрал"
        if self.settings.filterByFaction == "ALLIANCE" then
            if faction ~= "Альянс" and faction ~= "Нейтрал" then
                self:Debug("Фракция %s не соответствует Альянсу", faction)
                return false
            end
        elseif self.settings.filterByFaction == "HORDE" then
            if faction ~= "Орда" and faction ~= "Нейтрал" then
                self:Debug("Фракция %s не соответствует Орде", faction)
                return false
            end
        end
    end

    if self.settings.filterByGuild then
        local inGuild = _G.Utils and _G.Utils.IsPlayerInGuild and _G.Utils.IsPlayerInGuild(entry.name)
        if not inGuild then
            self:Debug("Игрок %s не в гильдии", entry.name or "nil")
            return false
        end
    end

    if not self.settings.showPlayerDeaths and entry.name == UnitName("player") then
        self:Debug("Собственные смерти скрыты")
        return false
    end

    if not self.settings.showGuildDeaths and _G.Utils and _G.Utils.IsPlayerInGuild and _G.Utils.IsPlayerInGuild(entry.name) then
        self:Debug("Смерти гильдии скрыты")
        return false
    end

    self:Debug("Маркер прошел все фильтры")
    return true
end
function DeathLoggerWorldMap:GetEntryName(entry)
    if not entry then return nil end
    if entry.playerName then return entry.playerName end
    if entry.name then return entry.name end
    if entry.charName then return entry.charName end
    if entry.character then return entry.character end
    if entry.nick then return entry.nick end
    return nil
end
function DeathLoggerWorldMap:GetEntryFaction(entry)
    if not entry then return "Нейтрал" end
    if entry.faction then return entry.faction end
    if entry.side then return entry.side end
    return "Нейтрал"
end
function DeathLoggerWorldMap:CreateMarker(entry, index)
    local playerName = self:GetEntryName(entry)
    self:Debug("Создание маркера #%d для %s", index, playerName or "nil")
    if not entry or not playerName then
        self:Debug("Неверные данные для маркера")
        return nil
    end

    local locationInfo = self:ParseLocation(entry)
    if not locationInfo then
        self:Debug("Не удалось распознать локацию для %s", playerName)
        return nil
    end

    local faction = self:GetEntryFaction(entry)

    local markerEntry = {
        name = playerName,
        causeID = 0,
        level = tonumber(entry.level) or 0,
        side = faction,
        classID = self:GetClassID(entry.class),
        parseGuild = entry.parseGuild or "",
        locationStr = locationInfo.zone
    }

    if not self:ShouldShowMarker(markerEntry) then
        self:Debug("Маркер отфильтрован")
        return nil
    end

    local marker = CreateFrame("Button", "DeathLoggerMarker" .. index, self.parentFrame)
    marker:SetSize(self.settings.markerSize, self.settings.markerSize)
    marker:SetFrameStrata("HIGH")
    marker:SetAlpha(self.settings.markerOpacity)

    local texture = marker:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")

    if faction == "Альянс" then
        texture:SetVertexColor(0.1, 0.3, 1)
        self:Debug("Создан маркер Альянса (синий)")
    elseif faction == "Орда" then
        texture:SetVertexColor(1, 0.1, 0.1)
        self:Debug("Создан маркер Орды (красный)")
    else
        texture:SetVertexColor(0.7, 0.7, 0.7)
        self:Debug("Создан маркер нейтрала (серый)")
    end

    marker.entryData = {
        name = playerName,
        level = tonumber(entry.level) or 0,
        class = entry.class or "Неизвестно",
        side = faction,
        locationStr = locationInfo.zone,
        timestamp = entry.timestamp,
        parseGuild = entry.parseGuild or "",
        tooltip = entry.tooltip
    }
    marker.locationInfo = locationInfo

    if self.settings.showTooltips then
        marker:SetScript("OnEnter", function(self)
            DeathLoggerWorldMap.Marker_ShowTooltip(self)
        end)
        
        marker:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    marker:SetScript("OnClick", function(self, button)
        DeathLoggerWorldMap.Marker_OnClick(self, button)
    end)

    self:Debug("Маркер успешно создан для локации: %s", locationInfo.zone or "Неизвестно")
    return marker
end
function DeathLoggerWorldMap:GetClassID(className)
    if not className then return 0 end
    local classMap = {
        ["Воин"] = 1,
        ["Паладин"] = 2,
        ["Охотник"] = 3,
        ["Разбойник"] = 4,
        ["Жрец"] = 5,
        ["Рыцарь смерти"] = 6,
        ["Шаман"] = 7,
        ["Маг"] = 8,
        ["Чернокнижник"] = 9,
        ["Монах"] = 10,
        ["Друид"] = 11,
    }

    return classMap[className] or 0
end
-- ИСПРАВЛЕННАЯ ФУНКЦИЯ: Правильное позиционирование маркеров для 3.3.5
function DeathLoggerWorldMap:PositionMarker(marker)
    if not marker or not marker.locationInfo then
        self:Debug("PositionMarker: маркер или информация о локации отсутствует")
        return
    end
    self:Debug("Позиционирование маркера для %s", marker.entryData and marker.entryData.name or "nil")

    local continent = GetCurrentMapContinent()

    if continent and continent > 0 and marker.locationInfo.continent and marker.locationInfo.continent > 0 and marker.locationInfo.continent ~= continent then
        self:Debug("Маркер для континента %d, текущий %d - скрываем", marker.locationInfo.continent, continent)
        marker:Hide()
        return
    end

    local mapWidth = WorldMapFrame:GetWidth()
    local mapHeight = WorldMapFrame:GetHeight()

    if not mapWidth or not mapHeight or mapWidth <= 0 or mapHeight <= 0 then
        self:Debug("Некорректные размеры карты: %dx%d", mapWidth or 0, mapHeight or 0)
        marker:Hide()
        return
    end

    local x = marker.locationInfo.x or 0.5
    local y = marker.locationInfo.y or 0.5

    marker:ClearAllPoints()
    -- ИСПРАВЛЕНО: используем проценты от карты для 3.3.5
    marker:SetPoint("CENTER", self.parentFrame, "TOPLEFT", 
        x * mapWidth, -y * mapHeight)
    marker:Show()

    self:Debug("Маркер установлен на позицию: %.2f, %.2f", x, y)
end
-- ИСПРАВЛЕННАЯ ФУНКЦИЯ: Обновление маркеров с фильтрацией по зоне
function DeathLoggerWorldMap:UpdateMarkers()
    self:Debug("=== ОБНОВЛЕНИЕ МАРКЕРОВ ===")
    if not self.settings or not self.settings.enabled then 
        self:Debug("Модуль отключен, пропускаем обновление")
        return 
    end

    if not self.parentFrame then
        self:Debug("Родительский фрейм не создан")
        return
    end

    if not WorldMapFrame or not WorldMapFrame:IsVisible() then
        self:Debug("Карта мира не видима, пропускаем обновление")
        return
    end

    if not self.parentFrame:IsVisible() then
        self:Debug("parentFrame не видим! Показываем его")
        self.parentFrame:Show()
    end

    -- Очистка старых маркеров
    if self.markers then
        for _, marker in pairs(self.markers) do
            if marker then
                marker:Hide()
                marker:SetParent(nil)
            end
        end
    end
    self.markers = {}

    if not DeathLoggerDB or not DeathLoggerDB.entries then
        self:Debug("DeathLoggerDB или entries отсутствуют")
        return
    end

    -- Получаем текущую зону и континент
    local currentZone = self:GetCurrentMapZone()
    local currentContinent = GetCurrentMapContinent()
    
    -- Сохраняем текущую зону для отслеживания изменений
    currentZoneName = currentZone
    currentContinentID = currentContinent
    
    self:Debug("Текущая зона: %s, Континент: %d", currentZone or "Неизвестно", currentContinent or 0)

    if WMDebug then
        self:Debug("Первые 5 записей в БД:")
        for i = 1, math.min(5, #DeathLoggerDB.entries) do
            local entry = DeathLoggerDB.entries[i]
            if entry then
                self:Debug("  %d. %s - локация: %s", i, entry.name or "?", entry.locationStr or "нет")
            end
        end
    end

    local count = 0
    local zoneDeathsCount = 0
    
    for i, entry in ipairs(DeathLoggerDB.entries) do
        if count >= self.settings.maxMarkers then
            self:Debug("Достигнут лимит маркеров (%d)", self.settings.maxMarkers)
            break
        end
        
        local shouldCreateMarker = true
        
        -- ПРОВЕРКА: Смерть в текущей зоне?
        local locationInfo = self:ParseLocation(entry)
        if locationInfo and locationInfo.zone then
            local zoneMatch = self:CompareZones(currentZone, locationInfo.zone)
            
            -- Если зоны не совпадают и включена фильтрация по зоне, пропускаем эту запись
            if not zoneMatch and self.settings.filterByZone then
                self:Debug("Пропущена запись #%d - зона не совпадает (%s != %s)", i, locationInfo.zone, currentZone or "nil")
                shouldCreateMarker = false
            end
            
            if shouldCreateMarker then
                zoneDeathsCount = zoneDeathsCount + 1
            end
        else
            self:Debug("Пропущена запись #%d - не удалось определить локацию", i)
            shouldCreateMarker = false
        end
        
        -- Создаем маркер только если проверка пройдена
        if shouldCreateMarker then
            self:Debug("Создание маркера для записи #%d", i)
            local marker = self:CreateMarker(entry, i)
            if marker then
                table.insert(self.markers, marker)
                self:PositionMarker(marker)
                count = count + 1
                self:Debug("Маркер #%d создан и позиционирован", count)
            else
                self:Debug("Не удалось создать маркер для записи #%d", i)
            end
        end
    end

    if self.settings.clusterRadius > 0 and count > 0 then
        self:Debug("Применение кластеризации с радиусом %d", self.settings.clusterRadius)
        self:ClusterMarkers()
    end

    self:Debug("Обновление завершено. Создано %d маркеров (всего смертей в зоне: %d)", count, zoneDeathsCount)
end

function DeathLoggerWorldMap:ScheduleUpdate()
    self:Debug("Планирование обновления маркеров")
    if not self.settings or not self.settings.enabled then
        self:Debug("Модуль выключен, пропускаем обновление")
        return
    end

    if not self.parentFrame then
        self:Debug("parentFrame не создан, инициализируем")
        self:LazyInit()
        if not self.parentFrame then
            self:Debug("Не удалось инициализировать parentFrame")
            return
        end
    end

    if not WorldMapFrame or not WorldMapFrame:IsVisible() then
        self:Debug("Карта мира не видима, пропускаем обновление")
        return
    end

    self:CreateDelayedUpdate(0.1, function()
        if self.UpdateMarkers then
            self:UpdateMarkers()
        end
    end)
end
function DeathLoggerWorldMap:ClusterMarkers()
    if not self.markers then
        self:Debug("ClusterMarkers: нет маркеров")
        return
    end
    self:Debug("Кластеризация %d маркеров", #self.markers)

    local clusters = {}
    local radius = self.settings.clusterRadius

    for i, marker in ipairs(self.markers) do
        if marker and marker:IsShown() then
            local clustered = false
            
            for _, cluster in ipairs(clusters) do
                local dx = math.abs(marker:GetLeft() - cluster.x)
                local dy = math.abs(marker:GetTop() - cluster.y)
                
                if dx < radius and dy < radius then
                    table.insert(cluster.markers, marker)
                    marker:Hide()
                    clustered = true
                    self:Debug("Маркер %d добавлен в кластер", i)
                    break
                end
            end
            
            if not clustered then
                local x, y = marker:GetLeft(), marker:GetTop()
                table.insert(clusters, {
                    x = x,
                    y = y,
                    markers = {marker}
                })
                self:Debug("Создан новый кластер для маркера %d", i)
            end
        end
    end

    local clusterCount = 0
    for _, cluster in ipairs(clusters) do
        if #cluster.markers > 1 then
            local clusterMarker = CreateFrame("Button", nil, self.parentFrame)
            clusterMarker:SetSize(self.settings.markerSize + 4, self.settings.markerSize + 4)
            clusterMarker:SetPoint("CENTER", self.parentFrame, "TOPLEFT", cluster.x, -cluster.y)
            
            local texture = clusterMarker:CreateTexture(nil, "OVERLAY")
            texture:SetAllPoints()
            texture:SetTexture("Interface\\MINIMAP\\ObjectIcons")
            texture:SetTexCoord(0, 0.25, 0, 0.25)
            texture:SetVertexColor(1, 0.5, 0)
            
            clusterMarker:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Кластер смертей", 1, 0.5, 0)
                GameTooltip:AddLine("Количество: " .. #cluster.markers, 1, 1, 1)
                GameTooltip:Show()
            end)
            
            clusterMarker:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            
            table.insert(self.markers, clusterMarker)
            clusterCount = clusterCount + 1
            self:Debug("Создан кластерный маркер с %d маркерами", #cluster.markers)
        end
    end

    self:Debug("Создано %d кластерных маркеров", clusterCount)
end
function DeathLoggerWorldMap:Enable()
    self:Debug("Включение модуля карты")
    if not self.settings then 
        self:Debug("Настройки не загружены, инициализируем")
        self:LazyInit()
        if not self.settings then
            print("|cFFFF0000Death Logger|r: Не удалось загрузить настройки")
            return 
        end
    end

    if not self.parentFrame then
        self:Debug("Родительский фрейм не создан, инициализируем")
        self:LazyInit()
        if not self.parentFrame then
            print("|cFFFF0000Death Logger|r: Не удалось создать родительский фрейм")
            return
        end
    end

    if not WorldMapFrame then
        print("|cFFFF0000Death Logger|r: Карта мира не доступна")
        return
    end

    self.settings.enabled = true
    DeathLoggerDB.worldMapSettings.enabled = true

    if self.parentFrame then
        self.parentFrame:Show()
        self:Debug("parentFrame показан")
    end

    self:UpdateButtonAppearance()
    self:UpdateDropdownText()
    self:UpdateMarkers()

    self:Debug("Модуль успешно включен")
end
function DeathLoggerWorldMap:Disable()
    self:Debug("Выключение модуля карты")
    if not self.settings then 
        self:Debug("Настройки не загружены")
        return 
    end

    self.settings.enabled = false
    DeathLoggerDB.worldMapSettings.enabled = false

    if self.parentFrame then
        self.parentFrame:Hide()
        self:Debug("parentFrame скрыт")
    end

    self:UpdateButtonAppearance()
    self:UpdateDropdownText()

    if self.markers then
        for _, marker in pairs(self.markers) do
            if marker then
                marker:Hide()
                marker:SetParent(nil)
            end
        end
        self.markers = {}
        self:Debug("Маркеры очищены")
    end

    self:Debug("Модуль успешно выключен")
end
function DeathLoggerWorldMap:ToggleEnabled()
    self:Debug("Переключение состояния модуля")
    if not self.settings then
        self:Debug("Настройки не инициализированы, инициализируем")
        if not DeathLoggerDB then
            DeathLoggerDB = {
                entries = {},
                worldMapSettings = {},
                locationHistory = {}
            }
        end
        DeathLoggerDB.worldMapSettings = DeathLoggerDB.worldMapSettings or {}
        for k, v in pairs(DEFAULT_SETTINGS) do
            if DeathLoggerDB.worldMapSettings[k] == nil then
                DeathLoggerDB.worldMapSettings[k] = v
            end
        end
        self.settings = DeathLoggerDB.worldMapSettings
    end

    if self.settings.enabled then
        self:Disable()
        print("|cFF00FF00Death Logger|r: Маркеры на карте мира отключены")
    else
        self:Enable()
        print("|cFF00FF00Death Logger|r: Маркеры на карте мира включены")
    end
end
function DeathLoggerWorldMap:UpdateDropdownText()
    if not self.dropdown then
        return
    end
    if self.settings and self.settings.enabled then
        UIDropDownMenu_SetText(self.dropdown, "Смерти ВКЛ")
    else
        UIDropDownMenu_SetText(self.dropdown, "Смерти ВЫКЛ")
    end
end
-- ИСПРАВЛЕННАЯ ФУНКЦИЯ: Регистрация событий с обработкой смены зоны
function DeathLoggerWorldMap:RegisterEvents()
    self:Debug("Регистрация событий")
    local function IsWorldMapMinimized()
        if WorldMapFrameSizeDownButton and WorldMapFrameSizeDownButton:IsVisible() then
            return false
        elseif WorldMapFrameSizeUpButton and WorldMapFrameSizeUpButton:IsVisible() then
            return true
        end
        
        local width, height = WorldMapFrame:GetSize()
        if width and height and width < 400 and height < 300 then
            return true
        end
        
        return false
    end

    local function UpdateControlsVisibility()
        local isMinimized = IsWorldMapMinimized()
        
        self:Debug("Обновление видимости элементов. Карта свернута: %s", tostring(isMinimized))
        
        if self.toggleButton then
            if WorldMapFrame:IsVisible() then
                self.toggleButton:Show()
            else
                self.toggleButton:Hide()
            end
        end
        
        if self.dropdown then
            if isMinimized or not WorldMapFrame:IsVisible() then
                self.dropdown:Hide()
            else
                self.dropdown:Show()
                
                if self.settings and self.settings.enabled then
                    UIDropDownMenu_SetText(self.dropdown, "Смерти ВКЛ")
                else
                    UIDropDownMenu_SetText(self.dropdown, "Смерти ВЫКЛ")
                end
            end
        end
        
        if not isMinimized and WorldMapFrame:IsVisible() and self.settings and self.settings.enabled then
            self:ScheduleUpdate()
        end
    end

    WorldMapFrame:HookScript("OnShow", function()
        self:Debug("WorldMapFrame показан")
        UpdateControlsVisibility()
        
        if WMDebug then
            self:Debug("Дебаг включен, запускаем автоматический показ смертей")
            self:AutoShowZoneDeathsOnMapOpen()
        end
    end)

    WorldMapFrame:HookScript("OnHide", function()
        self:Debug("WorldMapFrame скрыт")
        if self.toggleButton then
            self.toggleButton:Hide()
        end
        if self.dropdown then
            self.dropdown:Hide()
        end
        self:CleanupTimers()
    end)

    if WorldMapFrameSizeDownButton then
        WorldMapFrameSizeDownButton:HookScript("OnClick", function()
            self:Debug("Кнопка минимизации нажата")
            self:CleanupTimers()
            self:CreateDelayedUpdate(0.2, UpdateControlsVisibility)
        end)
    end

    if WorldMapFrameSizeUpButton then
        WorldMapFrameSizeUpButton:HookScript("OnClick", function()
            self:Debug("Кнопка разворачивания нажата")
            self:CleanupTimers()
            self:CreateDelayedUpdate(0.2, UpdateControlsVisibility)
        end)
    end

    if self.parentFrame then
        self.parentFrame:RegisterEvent("WORLD_MAP_UPDATE")
        self.parentFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self.parentFrame:RegisterEvent("ZONE_CHANGED")  -- ДОБАВЛЕНО: для лучшей детекции
        self.parentFrame:RegisterEvent("ZONE_CHANGED_INDOORS")  -- ДОБАВЛЕНО
        self.parentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        
        self.parentFrame:SetScript("OnEvent", function(frame, event, ...)
            self:Debug("Событие: %s", event)
            
            -- При смене зоны - принудительное обновление маркеров
            if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
                self:Debug("Зона изменилась! Перерисовываем маркеры...")
                local newZone = self:GetCurrentMapZone()
                local newContinent = GetCurrentMapContinent()
                
                -- Проверяем, действительно ли зона изменилась
                if newZone ~= currentZoneName or newContinent ~= currentContinentID then
                    currentZoneName = newZone
                    currentContinentID = newContinent
                    self:Debug("Новая зона: %s (континент: %d)", newZone or "Неизвестно", newContinent or 0)
                    
                    if self.settings and self.settings.enabled then
                        self:CreateDelayedUpdate(0.5, function()
                            self:UpdateMarkers()
                        end)
                        print("|cFF00FF00Death Logger|r: Зона изменена на: " .. (newZone or "Неизвестно"))
                    end
                end
            end
            
            if event == "WORLD_MAP_UPDATE" and self.settings and self.settings.enabled then
                self:ScheduleUpdate()
                
                if WMDebug then
                    self:CreateDelayedUpdate(0.5, function()
                        self:AutoShowZoneDeathsOnMapOpen()
                    end)
                end
            end
            
            if event == "PLAYER_ENTERING_WORLD" then
                self:Debug("Игрок вошел в мир, обновляем зону")
                currentZoneName = self:GetCurrentMapZone()
                currentContinentID = GetCurrentMapContinent()
            end
        end)
    end

    self:Debug("События зарегистрированы")
end
function DeathLoggerWorldMap:CleanupTimers()
    self:Debug("Очистка таймеров")
    if self.timers then
        for i, timer in ipairs(self.timers) do
            if timer and timer:HasScript("OnUpdate") then
                timer:SetScript("OnUpdate", nil)
                timer:Hide()
                DLWMDebug("Таймер #%d очищен", i)
            end
        end
        self.timers = {}
    end
end
function DeathLoggerWorldMap:CreateDelayedUpdate(delay, callback)
    DLWMDebug("Создание отложенного обновления через %.1f сек", delay)
    self:CleanupTimers()
    local timerFrame = CreateFrame("Frame")
    local elapsed = 0

    timerFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            DLWMDebug("Отложенное обновление выполнено")
            if callback then
                callback()
            end
        end
    end)

    if not self.timers then
        self.timers = {}
    end
    table.insert(self.timers, timerFrame)
    DLWMDebug("Таймер создан, всего таймеров: %d", #self.timers)
end
-- Методы для маркеров
function DeathLoggerWorldMap.Marker_ShowTooltip(marker)
    if not marker or not marker.entryData then
        DLWMDebug("Marker_ShowTooltip: маркер или данные отсутствуют")
        GameTooltip:Hide()
        return
    end
    local entry = marker.entryData

    GameTooltip:SetOwner(marker, "ANCHOR_RIGHT")
    GameTooltip:SetText("✗ " .. (entry.name or "Неизвестно"), 1, 0, 0)
    GameTooltip:AddLine("Уровень: " .. (entry.level or "? "), 1, 1, 1)

    if entry.class then
        GameTooltip:AddLine("Класс: " .. entry.class, 1, 1, 1)
    end

    if entry.side then
        local factionColor = {1, 1, 1}
        if entry.side == "Альянс" then
            factionColor = {0.1, 0.3, 1}
        elseif entry.side == "Орда" then
            factionColor = {1, 0.1, 0.1}
        end
        GameTooltip:AddLine("Фракция: " .. entry.side, unpack(factionColor))
    end

    if entry.locationStr then
        GameTooltip:AddLine("Локация: " .. entry.locationStr, 1, 1, 1)
    end

    if entry.timestamp then
        local dateStr = date("%Y-%m-%d %H:%M", entry.timestamp)
        GameTooltip:AddLine("Дата: " .. dateStr, 0.8, 0.8, 0.8)
    end

    if entry.parseGuild and entry.parseGuild ~= "" then
        GameTooltip:AddLine("Гильдия: |cFFFFFF00" .. entry.parseGuild .. "|r", 1, 1, 1)
    end

    if entry.tooltip then
        GameTooltip:AddLine("   ")
        GameTooltip:AddLine(entry.tooltip, 0.8, 0.8, 0.8, 1)
    end

    GameTooltip:Show()
end
function DeathLoggerWorldMap.Marker_OnClick(marker, button)
    if not marker or not marker.entryData then
        DLWMDebug("Marker_OnClick: маркер или данные отсутствуют")
        return
    end
    local entry = marker.entryData

    if not entry.name then
        DLWMDebug("Marker_OnClick: entry.name отсутствует")
        return
    end

    DLWMDebug("Клик по маркеру: %s, кнопка: %s", entry.name or "nil", button)

    if button == "LeftButton" then
        local message = string.format("|cFFFF0000✗|r %s (%d ур.) погиб в %s",
            entry.name or "Неизвестно", entry.level or 0, entry.locationStr or "неизвестной локации")
        
        if entry.parseGuild and entry.parseGuild ~= "" then
            message = message .. " |cFFFFFF00<" .. entry.parseGuild .. ">|r"
        end
        
        print("|cFF00FF00Death Logger|r: " .. message)
        
    elseif button == "RightButton" then
        if ChatFrameEditBox:IsVisible() then
            ChatFrameEditBox:Insert(entry.name or "")
            DLWMDebug("Имя вставлено в чат: %s", entry.name or "nil")
        else
            local menu = {
                {
                    text = entry.name or "Неизвестно",
                    isTitle = true,
                    notCheckable = true
                },
                {
                    text = "Шепнуть",
                    func = function()
                        if entry.name then
                            ChatFrame_SendTell(entry.name)
                        end
                    end,
                    notCheckable = true
                },
                {
                    text = "Копировать имя",
                    func = function()
                        _G.DEATHLOGGER_COPY_BUFFER = entry.name or ""
                        print("|cFF00FF00Death Logger|r: Имя скопировано: " .. (entry.name or "Неизвестно"))
                    end,
                    notCheckable = true
                },
                {
                    text = "Узнать гильдию",
                    func = function()
                        if _G.SlashCmdList and _G.SlashCmdList["DEATHLOGGERINFO"] and entry.name then
                            _G.SlashCmdList["DEATHLOGGERINFO"](entry.name)
                        end
                    end,
                    notCheckable = true
                }
            }
            
            EasyMenu(menu, UIParent, "cursor", 0, 0, "MENU")
        end
    end
end
-- Глобальные функции для использования в основном файле
function DeathLoggerWorldMap_OnAddonLoaded()
    DLWMDebug("DeathLoggerWorldMap_OnAddonLoaded вызвана")
    if WorldMapFrame then
        _G.DeathLoggerWorldMap = DeathLoggerWorldMap:new()
        DLWMDebug("Модуль карты создан (ленивая инициализация)")
    else
        DLWMDebug("WorldMapFrame не доступен, модуль карты не создан")
    end
end
function DeathLoggerWorldMap_OnDeath(dataMap)
    DLWMDebug("DeathLoggerWorldMap_OnDeath вызвана")
    if not dataMap then
        DLWMDebug("dataMap is nil")
        return
    end

    DLWMDebug("Получены данные: имя=%s, локация=%s", dataMap.name or "N/A", dataMap.locationStr or "N/A")

    if _G.DeathLoggerWorldMap then
        if not initialized and DeathLoggerDB then
            if dataMap.locationStr and not _G.DeathLoggerWorldMap.locationData[dataMap.locationStr] then
                DLWMDebug("Кэширование локации: %s", dataMap.locationStr)
                
                local mapID = GetCurrentMapAreaID()
                local x, y = GetPlayerMapPosition("player")
                
                if x and y and x > 0 and y > 0 then
                    local continent = GetCurrentMapContinent()
                    local zone = GetZoneText()
                    
                    _G.DeathLoggerWorldMap.locationData[dataMap.locationStr] = {
                        x = x,
                        y = y,
                        zone = zone,
                        continent = continent
                    }
                     
                    DeathLoggerDB.locationHistory = DeathLoggerDB.locationHistory or {}
                    DeathLoggerDB.locationHistory[dataMap.locationStr] = _G.DeathLoggerWorldMap.locationData[dataMap.locationStr]
                end
            end
        end
        
        if initialized and _G.DeathLoggerWorldMap.settings and _G.DeathLoggerWorldMap.settings.enabled then
            DLWMDebug("Модуль карты включен, планируем обновление")
            _G.DeathLoggerWorldMap:ScheduleUpdate()
        end
    end
end
function DeathLoggerWorldMap_Toggle()
    DLWMDebug("DeathLoggerWorldMap_Toggle вызвана")
    if _G.DeathLoggerWorldMap then
        if not initialized then
            _G.DeathLoggerWorldMap:LazyInit()
        end
        _G.DeathLoggerWorldMap:ToggleEnabled()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не создан")
        DLWMDebug("Модуль карты не создан")
    end
end
-- Обработчик открытия карты для ленивой инициализации
local frame = CreateFrame("Frame")
frame:RegisterEvent("WORLD_MAP_UPDATE")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DeathLogger" then
        if WorldMapFrame then
            _G.DeathLoggerWorldMap = DeathLoggerWorldMap:new()
            DLWMDebug("Модуль карты создан при загрузке аддона")
        end
    elseif event == "PLAYER_LOGIN" then
        if _G.DeathLoggerWorldMap and not initialized then
            DLWMDebug("Игрок вошел в мир, модуль готов")
        end
    elseif event == "WORLD_MAP_UPDATE" then
        if WorldMapFrame:IsVisible() and _G.DeathLoggerWorldMap and not initialized then
            DLWMDebug("Карта открыта, выполняем ленивую инициализацию")
            _G.DeathLoggerWorldMap:LazyInit()
        end
    end
end)
-- Создаем глобальные команды для отладки
SLASH_DEATHLOGGERWMDEBUG1 = "/dlwmdebug"
SlashCmdList["DEATHLOGGERWMDEBUG"] = function(msg)
    if msg == "on" then
        DeathLoggerWorldMap:EnableDebug()
    elseif msg == "off" then
        DeathLoggerWorldMap:DisableDebug()
    else
        DeathLoggerWorldMap:ToggleDebug()
    end
end
SLASH_DEATHLOGGERWMINFO1 = "/dlwminfo"
SlashCmdList["DEATHLOGGERWMINFO"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:ShowDebugInfo()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMZONEDEATHS1 = "/dlwmzone"
SlashCmdList["DEATHLOGGERWMZONEDEATHS"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:ShowDeathsInCurrentZone()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMDIAG1 = "/dlwmdiag"
SlashCmdList["DEATHLOGGERWMDIAG"] = function()
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:DiagnoseDatabase()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMENTRY1 = "/dlwmentry"
SlashCmdList["DEATHLOGGERWMENTRY"] = function(msg)
    if _G.DeathLoggerWorldMap then
        local index = tonumber(msg) or 1
        _G.DeathLoggerWorldMap:DebugEntry(index)
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMTEST1 = "/dlwmtest"
SlashCmdList["DEATHLOGGERWMTEST"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:TestMarkers()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMQUICKTEST1 = "/dlwmquick"
SlashCmdList["DEATHLOGGERWMQUICKTEST"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:QuickTest()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMZONEDEBUG1 = "/dlwmzonedebug"
SlashCmdList["DEATHLOGGERWMZONEDEBUG"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:DebugZoneDetection()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMCLEAR1 = "/dlwmclear"
SlashCmdList["DEATHLOGGERWMCLEAR"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:ClearAllMarkers()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
SLASH_DEATHLOGGERWMENTRIES1 = "/dlwmentries"
SlashCmdList["DEATHLOGGERWMENTRIES"] = function(msg)
    if _G.DeathLoggerWorldMap then
        _G.DeathLoggerWorldMap:DebugEntries()
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
-- НОВАЯ КОМАНДА: Переключение фильтрации по зоне
SLASH_DEATHLOGGERWMZONEFILTER1 = "/dlwmzonefilter"
SlashCmdList["DEATHLOGGERWMZONEFILTER"] = function(msg)
    if _G.DeathLoggerWorldMap then
        local enabled = msg and (msg == "on" or msg == "1" or msg == "true")
        if _G.DeathLoggerWorldMap.settings then
            if enabled then
                _G.DeathLoggerWorldMap.settings.filterByZone = true
                DeathLoggerDB.worldMapSettings.filterByZone = true
                print("|cFF00FF00Death Logger|r: Фильтрация по зоне ВКЛЮЧЕНА (маркеры только для текущей зоны)")
            else
                _G.DeathLoggerWorldMap.settings.filterByZone = false
                DeathLoggerDB.worldMapSettings.filterByZone = false
                print("|cFF00FF00Death Logger|r: Фильтрация по зоне ВЫКЛЮЧЕНА (маркеры для всех зон)")
            end
            _G.DeathLoggerWorldMap:ForceUpdateOnZoneChange()
        else
            print("|cFFFF0000Death Logger|r: Настройки не загружены")
        end
    else
        print("|cFFFF0000Death Logger|r: Модуль карты мира не инициализирован")
    end
end
-- Экспортируем таблицу
_G[addonName .. "_WorldMap"] = DeathLoggerWorldMap