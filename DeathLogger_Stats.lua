-------------------------------------------------------------------------------------------------
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
local Stats = {}
Stats.__index = Stats
local Graph = LibStub("LibGraph-2.0")
local DEBUG_MODE = false -- отладка

local CreateFrame = CreateFrame
local pairs = pairs
local ipairs = ipairs
local string = string
local table = table
local math = math
local tonumber = tonumber
local print = print
local UIDropDownMenu_SetText = UIDropDownMenu_SetText
local UIDropDownMenu_Initialize = UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton = UIDropDownMenu_AddButton
local wipe = wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

if not next(Graph) then
    error("|cFFFF0000Не удалось загрузить LibGraph-2.lua!|r")
elseif DEBUG_MODE then
    print("LibGraph-2 успешно загружен")
end

local DLTooltipFrame = CreateFrame("Frame", "DLTooltipFrame", UIParent)
DLTooltipFrame:SetFrameStrata("TOOLTIP")
DLTooltipFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
DLTooltipFrame:SetBackdropColor(0, 0, 0, 0.8)
DLTooltipFrame.text = DLTooltipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
DLTooltipFrame.text:SetPoint("CENTER", 0, 0)
DLTooltipFrame:SetSize(200, 40)
DLTooltipFrame:Hide()

-- парсинг
function Stats:ParseFromTooltip(tooltip, pattern, default)
    if not tooltip then 
        if DEBUG_MODE then print("|cFFFF0000DEBUG: ParseFromTooltip - tooltip отсутствует|r") end
        return default 
    end
    
    local startPos, endPos = tooltip:find(pattern)
    if not startPos then 
        if DEBUG_MODE then print("|cFFFF0000DEBUG: ParseFromTooltip - паттерн не найден:|r " .. string.sub(tooltip, 1, 50) .. "...") end
        return default 
    end
    
    local valueStart = endPos + 1
    local valueEnd = tooltip:find("\n", valueStart) or #tooltip + 1
    local value = tooltip:sub(valueStart, valueEnd - 1)
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):trim()
    
    if DEBUG_MODE then print("|cFF00FF00DEBUG: Парсим:|r " .. value) end
    return value
end

function Stats:ParseClassFromTooltip(tooltip)
    return self:ParseFromTooltip(tooltip, "Класс: ", "Неизвестно")
end

function Stats:ParseZoneFromTooltip(tooltip)
    return self:ParseFromTooltip(tooltip, "Локация: ", "")
end

function Stats:ParseGuildFromTooltip(tooltip)
    return self:ParseFromTooltip(tooltip, "Гильдия: ", "")
end

function Stats:ParseCauseFromTooltip(tooltip)
    if tooltip:find("Пройден") then
        return "Пройден"
    end
    return self:ParseFromTooltip(tooltip, "Причина: ", "Неизвестно")
end

function Stats:ParseFactionCauseFromTooltip(tooltip)
    return self:ParseFromTooltip(tooltip, "От: ", "")
end

function Stats:ParseLevelFromEntry(entry)
    if not entry then return 0 end
    if entry.tooltip and entry.tooltip:find("Пройден") then return 80 end
    
    if entry.tooltip then
        local level = self:ParseFromTooltip(entry.tooltip, "Уровень: ", nil)
        return tonumber(level) or 0
    end
    
    return tonumber(entry.level) or 0
end

function Stats:CreateVerticalTab(parent, text, onClickHandler)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(30, 100)
    tab:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 30, -20)
    tab:SetFrameLevel(parent:GetFrameLevel() + 10)
    tab:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, 
        tileSize = 16, 
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    tab:SetBackdropColor(0, 0, 0, 0.8)
    tab:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local normalTex = tab:CreateTexture(nil, "BACKGROUND")
    normalTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    normalTex:SetAllPoints()
    normalTex:SetVertexColor(0.1, 0.1, 0.1, 0.7)
    tab:SetNormalTexture(normalTex)

    local highlightTex = tab:CreateTexture(nil, "HIGHLIGHT")
    highlightTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlightTex:SetAllPoints()
    highlightTex:SetVertexColor(0.3, 0.3, 0.3, 0.7)
    tab:SetHighlightTexture(highlightTex)

    local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tabText:SetText(text)
    tabText:SetTextColor(1, 0.8, 0)
    tabText:SetPoint("CENTER", 0, 0)
    tabText:SetJustifyH("CENTER")
    tabText:SetJustifyV("MIDDLE")
    
    tab:SetScript("OnClick", onClickHandler)
    
    return tab, tabText
end

-- function Stats:SwitchWindows(fromFrame, toFrame)
    -- fromFrame:Hide()
    -- if toFrame then
        -- toFrame:Show()
        -- if toFrame == DLStatsFrame then
            -- toFrame.instance:UpdateStats()
            -- if fromFrame == DLSearchFrame and fromFrame.statsTabText then
                -- fromFrame.statsTabText:SetText("Ста\nтис\nти\nка")
            -- end
        -- end
    -- end
-- end

-- Stats.rowTemplate = nil

function Stats:CreateStatRow(text, value, offset)
    local row = CreateFrame("Frame", nil, self.contentFrame)
    row:SetSize(300, 20)
    row:SetPoint("TOPLEFT", 20, offset)
    
    local textLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textLabel:SetPoint("LEFT")
    textLabel:SetText(string.format("|cffffcc00%s:|r %d", text, value))
    
    return offset - (textLabel:GetHeight() + 5)
end

function Stats:CreateClickableHeader(parent, text, section, x, y)
    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", x, y)
    header:SetSize(150, 20)
    
    local textLabel = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textLabel:SetPoint("LEFT")
    textLabel:SetText("|cffffffff"..text..":|r")
    textLabel:SetTextColor(1, 1, 0.8)
    
    header:SetScript("OnEnter", function()
        textLabel:SetTextColor(1, 1, 1)
    end)
    
    header:SetScript("OnLeave", function()
        textLabel:SetTextColor(1, 1, 0.8)
    end)
    
    header:SetScript("OnClick", function()
        self.currentChartType = section
        self:UpdateStats()
    end)
    
    return header
end

function Stats:CreateLegendItem(parent, x, y, text, color, value)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("CENTER", parent, "CENTER", x, y)
    frame:SetSize(150, 20)
    
    local colorIndicator = frame:CreateTexture(nil, "BACKGROUND")
    colorIndicator:SetSize(12, 12)
    colorIndicator:SetPoint("LEFT")
    colorIndicator:SetTexture("Interface\\Buttons\\WHITE8X8")
    colorIndicator:SetVertexColor(unpack(color))
    
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", colorIndicator, "RIGHT", 5, 0)
    label:SetText(string.format("%s: %d (%.1f%%)", text, value, (value / self.data.total) * 100))
end

function Stats:SetupPieChartTooltip(pieChart, sectors)
    local tooltipFrame = CreateFrame("Frame", nil, pieChart:GetParent())
    tooltipFrame:SetAllPoints(pieChart)
    tooltipFrame:SetFrameLevel(pieChart:GetFrameLevel() + 10)
    tooltipFrame.sectors = sectors

    tooltipFrame:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsVisible() then 
            DLTooltipFrame:Hide()
            return 
        end
        
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        x = x / scale
        y = y / scale
        
        local left = self:GetLeft()
        local top = self:GetTop()
        local width = self:GetWidth()
        local height = self:GetHeight()
        
        local centerX = left + width/2
        local centerY = top - height/2
        
        local dx = x - centerX
        local dy = centerY - y
        local distance = math.sqrt(dx*dx + dy*dy)
        local radius = width/2
        
        if distance > radius then
            DLTooltipFrame:Hide()
            return
        end
        
        local angle = math.deg(math.atan2(dx, -dy))
        if angle < 0 then
            angle = angle + 360
        end
        
        for i, sector in ipairs(self.sectors) do
            local startAngle = sector.startAngle
            local endAngle = sector.endAngle
            
            if endAngle < startAngle then
                if angle >= startAngle or angle < endAngle then
                    DLTooltipFrame.text:SetText(
                        string.format("%s\nКоличество: %d (%.1f%%)", 
                        sector.name, sector.value, sector.percent)
                    )
                    DLTooltipFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y + 20)
                    DLTooltipFrame:Show()
                    return
                end
            else
                if angle >= startAngle and angle < endAngle then
                    DLTooltipFrame.text:SetText(
                        string.format("%s\nКоличество: %d (%.1f%%)", 
                        sector.name, sector.value, sector.percent)
                    )
                    DLTooltipFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y + 20)
                    DLTooltipFrame:Show()
                    return
                end
            end
        end
        DLTooltipFrame:Hide()
    end)
    
    tooltipFrame:SetScript("OnLeave", function()
        DLTooltipFrame:Hide()
    end)
end

function Stats:GetChartData()
    local data = {}
    local colors = {}
    local total = 0
    
    if self.currentChartType == "Фракции" then
        colors = {
            Alliance = {0, 0, 1, 1},     -- синий
            Horde = {1, 0, 0, 1},        -- красный
            Neutral = {0.5, 0.5, 0.5, 1} -- серый
        }
        
        for faction, count in pairs(self.data.factions) do
            if count > 0 then
                local name = faction == "Alliance" and "Альянс" or 
                             faction == "Horde" and "Орда" or 
                             "Нейтралы"
                table.insert(data, {
                    name = name,
                    value = count,
                    color = colors[faction]
                })
                total = total + count
            end
        end
        
    elseif self.currentChartType == "Классы" then
        colors = {
            ["ВОИН"] = {0.78, 0.61, 0.43, 1},         -- коричневый
            ["ПАЛАДИН"] = {0.96, 0.55, 0.73, 1},      -- розовый
            ["ОХОТНИК"] = {0.67, 0.83, 0.45, 1},      -- зеленый
            ["РАЗБОЙНИК"] = {1, 0.96, 0.41, 1},       -- желтый
            ["ЖРЕЦ"] = {1, 1, 1, 1},                  -- белый
            ["ШАМАН"] = {0, 0.44, 0.87, 1},           -- синий
            ["МАГ"] = {0.41, 0.8, 0.94, 1},           -- голубой
            ["ЧЕРНОКНИЖНИК"] = {0.58, 0.51, 0.79, 1}, -- фиолетовый
            ["ДРУИД"] = {1, 0.49, 0.04, 1},           -- оранжевый
        }
        
        for class, count in pairs(self.data.classes) do
            local color = colors[class:upper()] or {0.5, 0.5, 0.5, 1}
            table.insert(data, {
                name = class,
                value = count,
                color = color
            })
            total = total + count
        end
        
    elseif self.currentChartType == "Уровни" then
        local levelColors = {
            ["10-19"] = {1, 1, 1, 1},                -- белый
            ["20-29"] = {1, 1, 0, 1},                -- желтый
            ["30-39"] = {0.56, 0.93, 0.56, 1},       -- светло-зеленый
            ["40-49"] = {0.68, 0.85, 0.9, 1},        -- светло-голубой
            ["50-59"] = {1, 0, 0, 1},                -- красный
            ["60-69"] = {0, 0, 1, 1},                -- синий
            ["70-79"] = {0.58, 0.44, 0.86, 1},       -- фиолетовый
            ["Испытание пройдено"] = {1, 0.84, 0, 1} -- золотой
        }
        for _, range in ipairs(self.data.levelRanges) do
            if range.count > 0 then
                local color = levelColors[range.name] or {0.5, 0.5, 0.5, 1}
                table.insert(data, {
                    name = range.name,
                    value = range.count,
                    color = color
                })
                total = total + range.count
            end
        end
        
    elseif self.currentChartType == "Причины" then
        for cause, count in pairs(self.data.causes) do
            local color = {math.random(), math.random(), math.random(), 1}
            table.insert(data, {
                name = cause,
                value = count,
                color = color
            })
            total = total + count
        end
    end
    table.sort(data, function(a, b) return a.value > b.value end)
    return data, colors, total
end

function Stats:DrawCurrentChart(middleColumnX, columnWidth)
    local colHeader = self.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    colHeader:SetPoint("TOP", middleColumnX -100 , -20)
    colHeader:SetText("|cffffffff"..self.currentChartType.."|r")
    
    local chartContainer = CreateFrame("Frame", nil, self.contentFrame)
    chartContainer:SetSize(columnWidth, 250)
    chartContainer:SetPoint("TOP", middleColumnX -100 , -20)
    
    local pieSize = math.min(180, columnWidth - 20)
    local pieChart = Graph:CreateGraphPieChart("DLPieChart", chartContainer, "CENTER", "CENTER", 0, 0, pieSize, pieSize)
    
    local data, _, total = self:GetChartData()
    
    if not data or total == 0 then
        local noData = chartContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noData:SetText("|cff888888(нет данных)|r")
        noData:SetPoint("CENTER")
        return
    end

    local sectors = {}
    local startAngle = 0
    for _, entry in ipairs(data) do
        local percent = (entry.value / total) * 100
        pieChart:AddPie(percent, entry.color)
        local endAngle = startAngle + percent * 3.6
        table.insert(sectors, {
            startAngle = startAngle,
            endAngle = endAngle,
            name = entry.name,
            value = entry.value,
            percent = percent
        })
        startAngle = endAngle
    end
    pieChart:CompletePie()
    
    -- легенда
    local legendContainer = CreateFrame("Frame", nil, chartContainer)
    legendContainer:SetPoint("TOP", pieChart, "BOTTOM", 0, 80)
    legendContainer:SetSize(columnWidth, 200)
    
    local legendY = 0
    for i, entry in ipairs(data) do
        if i > 9 then break end
        self:CreateLegendItem(legendContainer, 0, legendY, entry.name, entry.color, entry.value)
        legendY = legendY - 20
    end
    
    local centerText = chartContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    centerText:SetPoint("CENTER", pieChart, "CENTER", 0, 0)
    centerText:SetText(string.format("Всего: %d", total))
    
    self:SetupPieChartTooltip(pieChart, sectors)
end

function Stats:InitializeData()
    self.data = {
        total = 0,
        factions = {Alliance = 0, Horde = 0, Neutral = 0},
        classes = {},
        levelRanges = {
            {min = 10, max = 19, count = 0, name = "10-19"},
            {min = 20, max = 29, count = 0, name = "20-29"},
            {min = 30, max = 39, count = 0, name = "30-39"},
            {min = 40, max = 49, count = 0, name = "40-49"},
            {min = 50, max = 59, count = 0, name = "50-59"},
            {min = 60, max = 69, count = 0, name = "60-69"},
            {min = 70, max = 79, count = 0, name = "70-79"},
            {min = 80, max = 80, count = 0, name = "Испытание пройдено"}
        },
        causes = {}
    }
end

function Stats:ClearContent()
    local children = { self.contentFrame:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        children[i]:SetParent(nil)
    end
    local regions = { self.contentFrame:GetRegions() }
    for i = 1, #regions do
        if regions[i] ~= self.contentFrame.Background then
            regions[i]:Hide()
        end
    end
end

function Stats:CollectStatistics()
    if not _G.DeathLoggerDB or not _G.DeathLoggerDB.entries then
        if DEBUG_MODE then print("|cFFFF0000Ошибка: Глобальная база данных недоступна|r") end
        return
    end
    
    self.data.total = 0
    for k in pairs(self.data.factions) do self.data.factions[k] = 0 end
    wipe(self.data.classes)
    wipe(self.data.causes)
    for _, range in ipairs(self.data.levelRanges) do
        range.count = 0
    end

    for _, entry in ipairs(_G.DeathLoggerDB.entries) do
        if entry and entry.faction and entry.tooltip then
            self.data.total = self.data.total + 1

            local faction = entry.faction
            if faction == "Орда" then
                self.data.factions.Horde = self.data.factions.Horde + 1
            elseif faction == "Альянс" then
                self.data.factions.Alliance = self.data.factions.Alliance + 1
            else
                self.data.factions.Neutral = self.data.factions.Neutral + 1
            end

            local class = self:ParseClassFromTooltip(entry.tooltip)
            if class ~= "Unknown" then
                self.data.classes[class] = (self.data.classes[class] or 0) + 1
            end

            local level = self:ParseLevelFromEntry(entry)
            for _, range in ipairs(self.data.levelRanges) do
                if level >= range.min and level <= range.max then
                    range.count = range.count + 1
                    break
                end
            end

            if level < 80 then
                local cause = self:ParseCauseFromTooltip(entry.tooltip)
                if cause ~= "Неизвестно" then
                    self.data.causes[cause] = (self.data.causes[cause] or 0) + 1
                end
            end
        end
    end
end

function Stats:DisplayStatistics()
    self:ClearContent()
    if self.data.total == 0 then
        local noData = self.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noData:SetText("|cff888888Нет данных для отображения|r")
        noData:SetPoint("CENTER")
        return
    end

    local leftOffset = -15
    local rightOffset = -20
    local contentWidth = self.contentFrame:GetWidth()
    local columnWidth = (contentWidth - 60) / 3
    local leftColumnX = 20
    local middleColumnX = leftColumnX + columnWidth + 20
    local rightColumnX = middleColumnX + columnWidth + 10
    
    self.statsTitle:SetText("Статистика смертей")

    leftOffset = self:CreateStatRow("Всего записей", self.data.total, leftOffset)
    leftOffset = leftOffset - 10

    self:CreateClickableHeader(self.contentFrame, "Фракции", "Фракции", leftColumnX, leftOffset)
    leftOffset = leftOffset - 25
    
    leftOffset = self:CreateStatRow("Альянс", self.data.factions.Alliance or 0, leftOffset)
    leftOffset = self:CreateStatRow("Орда", self.data.factions.Horde or 0, leftOffset)
    leftOffset = self:CreateStatRow("Нейтралы", self.data.factions.Neutral or 0, leftOffset)
    leftOffset = leftOffset - 20

    self:CreateClickableHeader(self.contentFrame, "Классы", "Классы", leftColumnX, leftOffset)
    leftOffset = leftOffset - 25

    if not next(self.data.classes) then
        local noData = self.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noData:SetText("|cff888888(данные отсутствуют)|r")
        noData:SetPoint("TOPLEFT", leftColumnX + 5, leftOffset)
        leftOffset = leftOffset - 25
    else
        local sorted = {}
        for class, count in pairs(self.data.classes) do table.insert(sorted, {class = class, count = count}) end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for i, entry in ipairs(sorted) do
            if i > 9 then break end
            leftOffset = self:CreateStatRow(entry.class, entry.count, leftOffset)
        end
    end

    self:CreateClickableHeader(self.contentFrame, "Уровни", "Уровни", middleColumnX, rightOffset)
    rightOffset = rightOffset - 25

    for _, range in ipairs(self.data.levelRanges) do
        if range.count > 0 then
            local displayText = range.name or string.format("%d-%d", range.min, range.max)
            local row = CreateFrame("Frame", nil, self.contentFrame)
            row:SetSize(columnWidth, 20)
            row:SetPoint("TOPLEFT", middleColumnX, rightOffset)
            
            local textLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            textLabel:SetPoint("LEFT")
            textLabel:SetText(string.format("|cffffcc00%s:|r %d", displayText, range.count))
            
            rightOffset = rightOffset - (textLabel:GetHeight() + 5)
        end
    end

    if next(self.data.causes) then
        rightOffset = rightOffset - 15
        self:CreateClickableHeader(self.contentFrame, "Причины", "Причины", middleColumnX, rightOffset)
        rightOffset = rightOffset - 25

        local sortedCauses = {}
        for cause, count in pairs(self.data.causes) do table.insert(sortedCauses, {cause = cause, count = count}) end
        table.sort(sortedCauses, function(a, b) return a.count > b.count end)

        for i, entry in ipairs(sortedCauses) do
            if i > 7 then break end
            local row = CreateFrame("Frame", nil, self.contentFrame)
            row:SetSize(columnWidth, 20)
            row:SetPoint("TOPLEFT", middleColumnX, rightOffset)
            
            local textLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            textLabel:SetPoint("LEFT")
            textLabel:SetText(string.format("|cffffcc00%s:|r %d", entry.cause, entry.count))
            
            rightOffset = rightOffset - (textLabel:GetHeight() + 5)
        end
    end

    self:DrawCurrentChart(middleColumnX, columnWidth)
end

function Stats:UpdateStats()
    self:ClearContent()
    self:InitializeData()
    self:CollectStatistics()
    self:DisplayStatistics()
    if DEBUG_MODE then print(string.format("|cFF00FF00DEBUG: Для статистики загружено записей: %d|r", self.data.total)) end
end

-- Stats.parsedEntriesCache = nil

function Stats:CreateSearchWindow(parent, width, height, padding, position)
    local frame = CreateFrame("Frame", "DLSearchFrame", parent)
    frame:SetSize(width, height)
    
    if position then
        local point, relativeToName, relativePoint, xOfs, yOfs = unpack(position)
        local anchorFrame = _G[relativeToName] or UIParent
        frame:SetPoint(point, anchorFrame, relativePoint, xOfs, yOfs)
    else
        frame:SetPoint("CENTER")
    end
    
    frame:SetFrameStrata("DIALOG")
    
    local statsTab, statsTabText = self:CreateVerticalTab(
        frame,
        "Ста\nтис\nти\nка",
        function()
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    local relativeToName = relativeTo and relativeTo:GetName() or "UIParent"
    _G.DeathLoggerDB.searchWindowPosition = {point, relativeToName, relativePoint, xOfs, yOfs}
    
    frame:Hide()
    
		if DLStatsFrame then
			DLStatsFrame:ClearAllPoints()
			if _G.DeathLoggerDB.statsWindowPosition then
				DLStatsFrame:SetPoint(unpack(_G.DeathLoggerDB.statsWindowPosition))
			else
				DLStatsFrame:SetPoint("CENTER")
			end
			DLStatsFrame:Show()
		end
	end)

    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", padding.left, -padding.top)
    contentFrame:SetPoint("BOTTOMRIGHT", -padding.right, padding.bottom)

    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAtlas("UI-EJ-Legion", true)
    frame.Background:SetAllPoints()
    frame.Background:SetAlpha(0.75)

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetBackdropBorderColor(0.8, 0.8, 0.8)
    frame.statsTabText = statsTabText
    frame:SetScript("OnShow", function()
        if DEBUG_MODE then print("|cFF00FF00DEBUG: Окно поиска открыто.|r") end
                frame.statsTabText:SetText("Ста\nтис\nти\nка")

        self.parsedEntriesCache = nil
        
        if not self.searchResults then
            self.searchResults = _G.DeathLoggerDB.entries
        end
        self:UpdateSearchResults(frame)
    end)
    
    frame:Hide()
    
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
	closeButton:SetScript("OnClick", function()
		local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(1)
		local relativeToName = relativeTo and relativeTo:GetName() or "UIParent"
		_G.DeathLoggerDB.searchWindowPosition = {point, relativeToName, relativePoint, xOfs, yOfs}
		frame.statsTabText:SetText("Ста\nтис\nти\nка")
		frame:Hide()
        if DLStatsFrame then
            DLStatsFrame:ClearAllPoints()
            if _G.DeathLoggerDB.statsWindowPosition then
                DLStatsFrame:SetPoint(unpack(_G.DeathLoggerDB.statsWindowPosition))
            else
                DLStatsFrame:SetPoint("CENTER")
            end
            DLStatsFrame:Show()
            if DLStatsFrame.instance and DLStatsFrame.instance.searchTabText then
                DLStatsFrame.instance.searchTabText:SetText("П\nо\nи\nс\nк")
            end
        end
    end)

    local uniqueClasses = {}
    local uniqueCauses = {}
    
    for _, entry in ipairs(_G.DeathLoggerDB.entries) do
        if entry and entry.tooltip then
            local class = self:ParseClassFromTooltip(entry.tooltip) or "Неизвестно"
            uniqueClasses[class] = true
            
            local cause = self:ParseCauseFromTooltip(entry.tooltip) or "Неизвестно"
            uniqueCauses[cause] = true
        end
    end
    
    if not next(uniqueClasses) then uniqueClasses["Неизвестно"] = true end
    if not next(uniqueCauses) then uniqueCauses["Неизвестно"] = true end
    
	local filterContainer = CreateFrame("Frame", nil, frame)
	filterContainer:SetPoint("TOP", 0, 0)
	filterContainer:SetSize(contentFrame:GetWidth() - 40, 60)
	
	local inputs = {}
	local currentX = 0
	local columnWidth = 100
	local spacing = 5
	
	local function CreateStyledInput(parent, width, height)
		local container = CreateFrame("Frame", nil, parent)
		container:SetSize(width, height)
		
		local bg = container:CreateTexture(nil, "BACKGROUND")
		bg:SetTexture("Interface\\Common\\Common-Input-Border")
		bg:SetTexCoord(0.0625, 0.9375, 0, 0.625)
		bg:SetVertexColor(0.5, 0.5, 0.5, 1)
		bg:SetAllPoints(container)
		
		local eb = CreateFrame("EditBox", nil, container)
		eb:SetPoint("TOPLEFT", 5, -3)
		eb:SetPoint("BOTTOMRIGHT", -5, 3)
		eb:SetAutoFocus(false)
		eb:SetFontObject("GameFontNormal")
		eb:SetTextInsets(5, 5, 0, 0)
		eb:SetJustifyH("LEFT")
		eb:SetBackdrop(nil)
		
		return eb, container
	end
	
	local function CreateFilterWithLabel(parent, name, elementType, values, default, width)
		width = width or columnWidth
		local container = CreateFrame("Frame", nil, parent)
		container:SetSize(width, 45)
		container:SetPoint("LEFT", currentX, 0)
		currentX = currentX + width + spacing
		
		local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP", 0, 0)
		label:SetText(name)
		label:SetTextColor(1, 1, 0.8)
		
		local element
		if elementType == "dropdown" then
			element = CreateFrame("Frame", name.."Dropdown", container, "UIDropDownMenuTemplate")
			element:SetPoint("TOP", label, "BOTTOM", 0, -5)
			element:SetSize(width - 10, 32)
			
			local function OnValueSelected(self, arg1, arg2, checked)
				UIDropDownMenu_SetText(element, arg1)
				element.selectedValue = arg1
			end
			
			UIDropDownMenu_Initialize(element, function(self, level, menuList)
				local info = UIDropDownMenu_CreateInfo()
				info.func = OnValueSelected
				
				info.text, info.arg1, info.checked = "Все", "Все", (element.selectedValue == "Все")
				UIDropDownMenu_AddButton(info)
				
				for value in pairs(values) do
					info.text, info.arg1, info.checked = value, value, (element.selectedValue == value)
					UIDropDownMenu_AddButton(info)
				end
			end)
			
			UIDropDownMenu_SetWidth(element, width - 15)
			UIDropDownMenu_SetText(element, default)
			element.selectedValue = default
		else
			element, inputContainer = CreateStyledInput(container, width - 10, 22)
			inputContainer:SetPoint("TOP", label, "BOTTOM", 0, -5)
			element:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		end
		
		return element
	end

	inputs.playerName = CreateFilterWithLabel(filterContainer, "Имя игрока", "editbox", nil, nil, 120)
	inputs.class = CreateFilterWithLabel(filterContainer, "Класс", "dropdown", uniqueClasses, "Все", 120)
	inputs.faction = CreateFilterWithLabel(filterContainer, "Фракция", "dropdown", {["Альянс"] = true, ["Орда"] = true, ["Нейтрал"] = true}, "Все", 90)
	inputs.zone = CreateFilterWithLabel(filterContainer, "Зона", "editbox", nil, nil, 170)
	inputs.cause = CreateFilterWithLabel(filterContainer, "Причина", "dropdown", uniqueCauses, "Все", 135)
	
	local levelContainer = CreateFrame("Frame", nil, filterContainer)
	levelContainer:SetSize(90, 45)
	levelContainer:SetPoint("LEFT", currentX, 0)
	currentX = currentX + 90 + spacing
	
	inputs.guild = CreateFilterWithLabel(filterContainer, "Гильдия", "editbox", nil, nil, 160)
	
	local levelLabel = levelContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	levelLabel:SetPoint("TOP", 0, 0)
	levelLabel:SetText("Уровень")
	levelLabel:SetTextColor(1, 1, 0.8)
	
	local levelInputs = CreateFrame("Frame", nil, levelContainer)
	levelInputs:SetPoint("TOP", levelLabel, "BOTTOM", 0, -5)
	levelInputs:SetSize(80, 20)
	
	inputs.minLevel, minContainer = CreateStyledInput(levelInputs, 38, 22)
	inputs.minLevel:SetAutoFocus(false)
	inputs.minLevel:SetNumeric(true)
	inputs.minLevel:SetMaxLetters(2)
	minContainer:SetPoint("LEFT", levelInputs, "LEFT", 0, 0)
	inputs.minLevel:SetScript("OnTabPressed", function(self)
		inputs.maxLevel:SetFocus()
	end)
	inputs.minLevel:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		statsInstance:PerformSearch(inputs)
	end)
	inputs.minLevel:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	inputs.minLevel:SetScript("OnTextChanged", function(self, userInput)
		if userInput and #self:GetText() == 2 then
			inputs.maxLevel:SetFocus()
		end
	end)
	inputs.minLevel:SetTextInsets(2, 2, 0, 0)
	
	local dash = levelInputs:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	dash:SetPoint("LEFT", minContainer, "RIGHT", 2, 0)
	dash:SetText("-")
	
	inputs.maxLevel, maxContainer = CreateStyledInput(levelInputs, 38, 22)
	inputs.maxLevel:SetAutoFocus(false)
	inputs.maxLevel:SetNumeric(true)
	inputs.maxLevel:SetMaxLetters(2)
	maxContainer:SetPoint("LEFT", dash, "RIGHT", 2, 0)
	inputs.maxLevel:SetScript("OnTabPressed", function(self)
		inputs.playerName:SetFocus()
	end)
	inputs.maxLevel:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		statsInstance:PerformSearch(inputs)
	end)
	inputs.maxLevel:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	
	inputs.maxLevel:SetTextInsets(2, 2, 0, 0)
	
	local statsInstance = self
	
	local function SetupEnterHandler(input)
		if input then
			input:SetScript("OnEnterPressed", function(self)
				self:ClearFocus()
				statsInstance:PerformSearch(inputs)
			end)
		end
	end
	
	SetupEnterHandler(inputs.playerName)
	SetupEnterHandler(inputs.minLevel)
	SetupEnterHandler(inputs.maxLevel)
	SetupEnterHandler(inputs.zone)
	SetupEnterHandler(inputs.guild)
	
    local buttonY = padding.bottom + 10
    local searchButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    searchButton:SetPoint("BOTTOMLEFT", padding.left + 10, buttonY)
    searchButton:SetSize(100, 25)
    searchButton:SetText("Поиск")
    searchButton:SetScript("OnClick", function()
        self:PerformSearch(inputs)
    end)
    
    local resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetButton:SetPoint("BOTTOMRIGHT", -padding.right - 10, buttonY)
    resetButton:SetSize(100, 25)
    resetButton:SetText("Сбросить")
    resetButton:SetScript("OnClick", function()
        inputs.playerName:SetText("")
        inputs.minLevel:SetText("")
        inputs.maxLevel:SetText("")
        inputs.zone:SetText("")
        inputs.guild:SetText("")
        
        UIDropDownMenu_SetText(inputs.faction, "Все")
        inputs.faction.selectedValue = "Все"
        
        UIDropDownMenu_SetText(inputs.class, "Все")
        inputs.class.selectedValue = "Все"
        
        UIDropDownMenu_SetText(inputs.cause, "Все")
        inputs.cause.selectedValue = "Все"
        
        self.searchResults = _G.DeathLoggerDB.entries
        self:UpdateSearchResults(frame)
    end)
    
    local resultFrame = CreateFrame("Frame", nil, frame)
    resultFrame:SetPoint("TOPLEFT", filterContainer, "BOTTOMLEFT", 0, -10)
    resultFrame:SetPoint("BOTTOMRIGHT", -10, buttonY + 35)
    
    local headerFrame = CreateFrame("Frame", nil, resultFrame)
    headerFrame:SetPoint("TOPLEFT", resultFrame, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", resultFrame, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(20)
    frame.headerFrame = headerFrame
    
    local scrollFrame = CreateFrame("ScrollFrame", "DLSearchScrollFrame", resultFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", resultFrame, "BOTTOMRIGHT", -27, 0)
    
    local scrollBar = scrollFrame.ScrollBar or _G["DLSearchScrollFrameScrollBar"]
    if scrollBar then
        scrollBar:SetWidth(24)
        local upButton = scrollBar.ScrollUpButton or _G[scrollBar:GetName().."ScrollUpButton"]
        local downButton = scrollBar.ScrollDownButton or _G[scrollBar:GetName().."ScrollDownButton"]
        
        if upButton then upButton:SetSize(24, 24) end
        if downButton then downButton:SetSize(24, 24) end
        
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetSize(24, 30)
            thumb:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
            thumb:SetTexCoord(0.25, 0.75, 0.25, 0.75)
        end
    end
    
    local scrollChild = CreateFrame("Frame", "DLSearchScrollChild", scrollFrame)
    scrollChild:SetSize(100, 100)
    scrollFrame:SetScrollChild(scrollChild)
    
    local resultLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    resultLabel:SetPoint("TOPLEFT", 0, 0)
    -- resultLabel:SetText("Введите критерии поиска")
    
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.resultLabel = resultLabel
    
    return frame
end

function Stats:PerformSearch(inputs)
    if DEBUG_MODE then print("|cFF00FF00DEBUG: PerformSearch запущен.|r") end
    
    if not _G.DeathLoggerDB or not _G.DeathLoggerDB.entries then
        if DEBUG_MODE then print("|cFFFF0000ERROR: DeathLoggerDB не загружен!|r") end
        self.searchResults = {}
        self:UpdateSearchResults(DLSearchFrame)
        return
    end
    
    local function trim(str)
        return str:gsub("^%s*(.-)%s*$", "%1")
    end
    
    local criteria = {}
    
    local playerNameText = inputs.playerName:GetText()
    if playerNameText and playerNameText:trim() ~= "" then
        criteria.playerName = trim(playerNameText)
    end
    
    if inputs.faction.selectedValue and inputs.faction.selectedValue ~= "Все" then
        criteria.faction = inputs.faction.selectedValue
    end
    
    local minLevelText = inputs.minLevel:GetText()
    if minLevelText and minLevelText ~= "" then
        criteria.minLevel = tonumber(minLevelText)
    end
    
    local maxLevelText = inputs.maxLevel:GetText()
    if maxLevelText and maxLevelText ~= "" then
        criteria.maxLevel = tonumber(maxLevelText)
    end
    
    local zoneText = inputs.zone:GetText()
    if zoneText and zoneText:trim() ~= "" then
        criteria.zone = trim(zoneText)
    end
	
    local guildText = inputs.guild:GetText()
    if guildText and guildText:trim() ~= "" then
        criteria.guild = trim(guildText)
    end

    if inputs.class.selectedValue and inputs.class.selectedValue ~= "Все" then
        criteria.class = inputs.class.selectedValue
    end
    
    if inputs.cause.selectedValue and inputs.cause.selectedValue ~= "Все" then
        criteria.cause = inputs.cause.selectedValue
    end
    
    self.searchResults = {}
    for _, entry in ipairs(_G.DeathLoggerDB.entries) do
        if entry and entry.tooltip then
            local parsed = {
                class = self:ParseClassFromTooltip(entry.tooltip),
                cause = self:ParseCauseFromTooltip(entry.tooltip),
                level = self:ParseLevelFromEntry(entry),
                zone = self:ParseZoneFromTooltip(entry.tooltip),
                source = self:ParseFactionCauseFromTooltip(entry.tooltip),
                guild = self:ParseGuildFromTooltip(entry.tooltip)
            }
            
            local match = true
            
            if criteria.playerName then
                if not entry.playerName:lower():find(criteria.playerName:lower(), 1, true) then
                    match = false
                end
            end
            
            if criteria.faction then
                if entry.faction:lower() ~= criteria.faction:lower() then
                    match = false
                end
            end
            
            if criteria.minLevel and parsed.level < criteria.minLevel then
                match = false
            end
            
            if criteria.maxLevel and parsed.level > criteria.maxLevel then
                match = false
            end
            
            if criteria.zone then
                if not parsed.zone:lower():find(criteria.zone:lower(), 1, true) then
                    match = false
                end
            end
			
            if criteria.guild then
				if not parsed.guild:lower():find(criteria.guild:lower(), 1, true) then
					match = false
				end
			end

            if criteria.class then
                if parsed.class:lower() ~= criteria.class:lower() then
                    match = false
                end
            end
            
            if criteria.cause then
                if parsed.cause:lower() ~= criteria.cause:lower() then
                    match = false
                end
            end
            
            if match then
                entry.parsed = parsed
                table.insert(self.searchResults, entry)
            end
        end
    end
    
    if DEBUG_MODE then print("Найдено записей: " .. #self.searchResults) end
    self:UpdateSearchResults(DLSearchFrame)
end

-- function Stats:CreateRowPool(parent, width, headers)
    -- local rowPool = {}
    -- local rowHeight = 20
    -- local verticalSpacing = 3
    
    -- for i = 1, 10 do
        -- local row = CreateFrame("Frame", nil, parent)
        -- row:SetSize(width, rowHeight)
        -- row:Hide()

        -- row.bg = row:CreateTexture(nil, "BACKGROUND")
        -- row.bg:SetAllPoints()
        -- row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        
        -- row.fields = {}
        -- local currentX = 3
        -- for j, header in ipairs(headers) do
            -- local colWidth = width * header.width
            -- local field = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            -- field:SetPoint("LEFT", currentX, 0)
            -- field:SetWidth(colWidth)
            -- field:SetJustifyH("CENTER")
            -- table.insert(row.fields, field)
            -- currentX = currentX + colWidth
        -- end
        
        -- table.insert(rowPool, row)
    -- end
    
    -- return rowPool
-- end

function Stats:UpdateSearchResults(frame)
    if not frame or not frame.scrollFrame or not frame.scrollChild then
        if DEBUG_MODE then print("|cFFFF0000ERROR: Неверная структура окна поиска|r") end
        return
    end
    
    local scrollFrame = frame.scrollFrame
    local scrollChild = frame.scrollChild
    local resultLabel = frame.resultLabel
    local headerFrame = frame.headerFrame
    
    if headerFrame then
        local headerChildren = { headerFrame:GetChildren() }
        for i = 1, #headerChildren do
            headerChildren[i]:Hide()
            headerChildren[i]:SetParent(nil)
        end
    end
    
    if frame.rowPool then
        for _, row in ipairs(frame.rowPool) do
            row:Hide()
        end
    end
    
    resultLabel:Hide()

    if not self.searchResults or #self.searchResults == 0 then
        if headerFrame then headerFrame:Hide() end
        resultLabel:SetText(not self.searchResults and "Введите критерии поиска" or "|cFFFF0000Ничего не найдено|r")
        resultLabel:Show()
        resultLabel:SetPoint("TOP", 0, -10)
        scrollChild:SetHeight(50)
        scrollFrame:SetVerticalScroll(0)
        return
    end
    
    headerFrame:Show()
    local scrollWidth = scrollFrame:GetWidth()
    local headers = {
        {id = "name", text = "Имя", width = 0.10},
        {id = "level", text = "Ур.", width = 0.03},
        {id = "class", text = "Класс", width = 0.09},
        {id = "faction", text = "Фракция", width = 0.09},
        {id = "zone", text = "Зона", width = 0.21},
        {id = "cause", text = "Причина", width = 0.10},
        {id = "source", text = "От", width = 0.20},
        {id = "guild", text = "Гильдия", width = 0.13}
    }
    
    local currentX = 0
    for i, header in ipairs(headers) do
        local colWidth = scrollWidth * header.width
        
        local headerButton = CreateFrame("Button", nil, headerFrame)
        headerButton:SetPoint("LEFT", currentX, 0)
        headerButton:SetSize(colWidth, 20)
        headerButton.columnId = header.id
        headerButton:EnableMouse(true)
        headerButton:RegisterForClicks("LeftButtonUp")
        headerButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        
        local headerText = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("CENTER", 0, 0)
        headerText:SetWidth(colWidth - 10)
        headerText:SetText("|cFFFFD100"..header.text.."|r")
        headerText:SetJustifyH("CENTER")
        
        local sortIndicator = headerButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sortIndicator:SetPoint("RIGHT", -5, 0)
        sortIndicator:Hide()
        headerButton.sortIndicator = sortIndicator
        
        headerButton:SetScript("OnClick", function(self)
            local searchFrame = self:GetParent():GetParent()
            if searchFrame and searchFrame.sortFunc then
                searchFrame:sortFunc(self.columnId)
            end
        end)
        
        currentX = currentX + colWidth
    end
    
    frame.headers = headers
    frame.currentSortColumn = nil
    frame.sortAscending = true
    
    function frame:sortFunc(columnId)
        if not self.searchResults then return end
        
        if self.currentSortColumn == columnId then
            self.sortAscending = not self.sortAscending
        else
            self.currentSortColumn = columnId
            self.sortAscending = true
        end
        
        for _, headerButton in ipairs({self.headerFrame:GetChildren()}) do
            if headerButton.columnId then
                headerButton.sortIndicator:Hide()
                if headerButton.columnId == columnId then
                    headerButton.sortIndicator:SetText(self.sortAscending and "▲" or "▼")
                    headerButton.sortIndicator:Show()
                end
            end
        end
        
        table.sort(self.searchResults, function(a, b)
            local valueA, valueB
            
            if columnId == "name" then
                valueA = a.playerName or ""
                valueB = b.playerName or ""
            elseif columnId == "level" then
                valueA = Stats:ParseLevelFromEntry(a) or 0
                valueB = Stats:ParseLevelFromEntry(b) or 0
            elseif columnId == "class" then
                valueA = Stats:ParseClassFromTooltip(a.tooltip) or ""
                valueB = Stats:ParseClassFromTooltip(b.tooltip) or ""
            elseif columnId == "faction" then
                valueA = a.faction or ""
                valueB = b.faction or ""
            elseif columnId == "zone" then
                valueA = Stats:ParseZoneFromTooltip(a.tooltip) or ""
                valueB = Stats:ParseZoneFromTooltip(b.tooltip) or ""
            elseif columnId == "cause" then
                valueA = Stats:ParseCauseFromTooltip(a.tooltip) or ""
                valueB = Stats:ParseCauseFromTooltip(b.tooltip) or ""
            elseif columnId == "source" then
                valueA = Stats:ParseFactionCauseFromTooltip(a.tooltip) or ""
                valueB = Stats:ParseFactionCauseFromTooltip(b.tooltip) or ""
            elseif columnId == "guild" then
                valueA = Stats:ParseGuildFromTooltip(a.tooltip) or ""
                valueB = Stats:ParseGuildFromTooltip(b.tooltip) or ""
            else
                return false
            end
            
            if type(valueA) == "string" then
                valueA = valueA:lower()
                valueB = valueB:lower()
            end
            
            if self.sortAscending then
                return valueA < valueB
            else
                return valueA > valueB
            end
        end)
        
        Stats:UpdateSearchResults(self)
    end
    
    -- resultLabel:SetText(string.format("Найдено записей: %d", #self.searchResults))
    -- resultLabel:SetPoint("TOP", 0, -10)
    
    local rowHeight = 20
    local verticalSpacing = 3
    local visibleRows = math.floor(scrollFrame:GetHeight() / (rowHeight + verticalSpacing)) + 2
    
    if not frame.rowPool then
        frame.rowPool = {}
        for i = 1, visibleRows do
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(scrollWidth, rowHeight)
            row:Hide()
            
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            
            row.fields = {}
            local currentX = 3
            for j, header in ipairs(headers) do
                local colWidth = scrollWidth * header.width
                
                local field = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                field:SetPoint("LEFT", currentX, 0)
                field:SetWidth(colWidth - 5)
                field:SetJustifyH("CENTER")
                table.insert(row.fields, field)
                
                currentX = currentX + colWidth
            end
            
            table.insert(frame.rowPool, row)
        end
    end
    
    local totalHeight = #self.searchResults * (rowHeight + verticalSpacing)
    scrollChild:SetHeight(totalHeight)
    scrollFrame:UpdateScrollChildRect()
    
	local function UpdateVisibleRows()
		if not frame:IsVisible() then return end
		
		local scrollOffset = scrollFrame:GetVerticalScroll()
		local firstVisible = math.floor(scrollOffset / (rowHeight + verticalSpacing)) + 1
		local lastVisible = math.min(firstVisible + visibleRows - 1, #self.searchResults)
		
		for _, row in ipairs(frame.rowPool) do
			row:Hide()
		end
		
		for i = firstVisible, lastVisible do
			local poolIndex = i - firstVisible + 1
			local row = frame.rowPool[poolIndex]
			local entry = self.searchResults[i]
			
			if row and entry then
				if not entry.parsed then
					entry.parsed = {
						class = self:ParseClassFromTooltip(entry.tooltip) or "Неизвестно",
						cause = self:ParseCauseFromTooltip(entry.tooltip) or "Неизвестно",
						level = self:ParseLevelFromEntry(entry) or 0,
						zone = self:ParseZoneFromTooltip(entry.tooltip) or "",
						source = self:ParseFactionCauseFromTooltip(entry.tooltip) or "",
						guild = self:ParseGuildFromTooltip(entry.tooltip) or ""
					}
				end
				
                local parsed = entry.parsed
                
                row.fields[1]:SetText(entry.playerName)
                row.fields[2]:SetText(parsed.level)
                row.fields[3]:SetText(parsed.class)
                row.fields[4]:SetText(entry.faction)
                row.fields[5]:SetText(parsed.zone)
                row.fields[6]:SetText(parsed.cause)
                row.fields[7]:SetText(parsed.source)
                row.fields[8]:SetText(parsed.guild)
                
                local yOffset = - (i-1) * (rowHeight + verticalSpacing)
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
                row:Show()
    
                if parsed.level == 80 then
                    row.bg:SetVertexColor(0, 0.5, 0, 0.7)
                else
                    row.bg:SetVertexColor(i % 2 == 0 and 0.1 or 0.15, 0.1, 0.1, 0.7)
                end
            end
        end
    end

    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetScript("OnValueChanged", function(self, value)
            scrollFrame:SetVerticalScroll(value)
            UpdateVisibleRows()
        end)
    end
    
    scrollFrame:SetVerticalScroll(0)
    UpdateVisibleRows()
end

function Stats.new(parent, mainWindowRef)
    if not parent or parent:GetObjectType() ~= "Frame" then
        error("Неправильный родительский фрейм для статистики")
    end
    
    if not _G.DeathLoggerDB then
        error("_G.DeathLoggerDB не инициализирован!")
    end
    
    if _G["DLStatsFrame"] then
        _G["DLStatsFrame"]:Show()
        return _G["DLStatsFrame"].instance
    end
    
    local instance = setmetatable({}, Stats)
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()
    instance.frameWidth = screenWidth * 0.8
    instance.frameHeight = screenHeight * 0.65
    instance.mainWindowRef = mainWindowRef

    instance.contentPadding = {left = 10, right = 10, top = 40, bottom = 10}

    instance.statsFrame = CreateFrame("Frame", "DLStatsFrame", parent)
	    instance.statsFrame:SetFrameStrata("DIALOG")

    instance.statsFrame:SetSize(instance.frameWidth, instance.frameHeight)

    if _G.DeathLoggerDB.statsWindowPosition then
        instance.statsFrame:SetPoint(unpack(_G.DeathLoggerDB.statsWindowPosition))
    else
        instance.statsFrame:SetPoint("CENTER")
    end
    
    instance.statsFrame:SetMovable(true)
    instance.statsFrame:SetClampedToScreen(true)

    instance.statsFrame.Background = instance.statsFrame:CreateTexture(nil, "BACKGROUND")
    instance.statsFrame.Background:SetAtlas("UI-EJ-BattleforAzeroth", true)
    instance.statsFrame.Background:SetAllPoints()
    instance.statsFrame.Background:SetAlpha(0.75)
    instance.statsFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    instance.statsFrame:SetBackdropColor(0, 0, 0, 0.8)

    instance.statsTitle = instance.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    instance.statsTitle:SetPoint("TOP", 0, -10)
    instance.statsTitle:SetText("Статистика смертей")
    
    instance.closeButton = CreateFrame("Button", nil, instance.statsFrame, "UIPanelCloseButton")
    instance.closeButton:SetSize(32, 32)
    instance.closeButton:SetPoint("TOPRIGHT", -5, -5)
    instance.closeButton:SetScript("OnClick", function()
        parent:Hide()
        _G.DLDialogFrame_v2:Show()
        _G.isFullWindow = false
    end)

    local searchTab, searchTabText = instance:CreateVerticalTab(
        instance.statsFrame,
        "П\nо\nи\nс\nк",
        function()
            local point, relativeTo, relativePoint, xOfs, yOfs = instance.statsFrame:GetPoint(1)
            local relativeToName = relativeTo and relativeTo:GetName() or "UIParent"
            _G.DeathLoggerDB.statsWindowPosition = {point, relativeToName, relativePoint, xOfs, yOfs}
            
            instance.statsFrame:Hide()
            instance.searchTabText:SetText("Ста\nтис\nти\nка")
            
		local currentPosition = {point, relativeToName, relativePoint, xOfs, yOfs}
		
		if DLSearchFrame then
			DLSearchFrame:ClearAllPoints()
			DLSearchFrame:SetPoint(unpack(currentPosition))
			DLSearchFrame:Show()
		else
			DLSearchFrame = Stats:CreateSearchWindow(
				parent, 
				instance.frameWidth, 
				instance.frameHeight, 
				instance.contentPadding,
				currentPosition
			)
			DLSearchFrame:Show()
		end
	end

    )
    instance.searchTabText = searchTabText
    
    instance.dragRegion = CreateFrame("Frame", nil, instance.statsFrame)
    instance.dragRegion:SetPoint("TOPLEFT", instance.statsFrame, "TOPLEFT", 0, 0)
    instance.dragRegion:SetPoint("TOPRIGHT", instance.statsFrame, "TOPRIGHT", 0, 0)
    instance.dragRegion:SetHeight(30)
    instance.dragRegion:EnableMouse(true)
    instance.dragRegion:RegisterForDrag("LeftButton")
    instance.dragRegion:SetScript("OnDragStart", function(self)
        instance.statsFrame:StartMoving()
    end)
    instance.dragRegion:SetScript("OnDragStop", function(self)
        instance.statsFrame:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = instance.statsFrame:GetPoint(1)
        local relativeToName = relativeTo and relativeTo:GetName() or "UIParent"
        _G.DeathLoggerDB.statsWindowPosition = {point, relativeToName, relativePoint, xOfs, yOfs}
    end)
    instance.dragRegion:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Перетащите для перемещения окна", 1, 1, 1)
        GameTooltip:Show()
    end)
    instance.dragRegion:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        ResetCursor()
    end)
    
    instance.contentFrame = CreateFrame("Frame", nil, instance.statsFrame)
    instance.contentFrame:SetPoint("TOPLEFT", instance.contentPadding.left, -instance.contentPadding.top)
    instance.contentFrame:SetPoint("BOTTOMRIGHT", -instance.contentPadding.right, instance.contentPadding.bottom)
    
    instance:InitializeData()
    instance.statsFrame.instance = instance
    instance.currentChartType = "Фракции"
    
	instance.statsFrame:SetScript("OnShow", function()
		if DEBUG_MODE then print("|cFF00FF00DEBUG: Окно статистики открыто.|r") end
		instance:UpdateStats()
		instance.searchTabText:SetText("П\nо\nи\nс\nк")
	end)
    instance.statsFrame:SetScript("OnHide", function()
        instance:ClearContent()
        instance:InitializeData()
    end)
    
    return instance
end

_G.DeathLogger_Stats = Stats