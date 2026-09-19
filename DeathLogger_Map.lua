-------------------------------------------------------------------------------------------------
-- Copyright 2025 Norzia (devilicip2@gmail.com) for sirus-wow
-- Death pins on the World of Warcraft world map (3.3.5 / Sirus)
-------------------------------------------------------------------------------------------------

local addonName = "DeathLogger"
local Utils = _G[addonName.."_Utils"] or {}
local Map = {}
_G.DeathLoggerMap = Map

local MAX_PINS = 180
local pinPool = {}
local activePins = {}
local mapFrame
local toggleButton
local zoneCache = {}
local zoneCacheBuilt = false

local function EnsureDB()
    DeathLoggerDB = DeathLoggerDB or {}
    if DeathLoggerDB.showDeathMap == nil then
        DeathLoggerDB.showDeathMap = true
    end
end

local function Hash01(str, salt)
    local h = salt or 5381
    str = str or ""
    for i = 1, #str do
        h = (h * 33 + str:byte(i)) % 2147483647
    end
    return (h % 10000) / 10000
end

local function NormalizeZone(name)
    if not name or type(name) ~= "string" then return "" end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    name = name:gsub("%s*%(?[%d%.]+%s*[,/]%s*[%d%.]+%)?%s*$", "")
    name = name:match("^%s*(.-)%s*$") or name
    return strlower(name)
end

local function ParseLocationFromTooltip(tooltip)
    if not tooltip or type(tooltip) ~= "string" then return nil end
    local loc = tooltip:match("Локация:%s*([^\n]+)")
    if loc then
        loc = loc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return loc:match("^%s*(.-)%s*$")
    end
    return nil
end

local function BuildZoneCache()
    wipe(zoneCache)
    for continent = 1, 4 do
        local zones = { GetMapZones(continent) }
        for index, zoneName in ipairs(zones) do
            zoneCache[NormalizeZone(zoneName)] = {
                continent = continent,
                zone = index,
                name = zoneName
            }
        end
    end
    zoneCacheBuilt = true
end

local function GetCurrentMapZoneName()
    local continent = GetCurrentMapContinent()
    local zone = GetCurrentMapZone()
    if continent and continent > 0 and zone and zone > 0 then
        local zones = { GetMapZones(continent) }
        return zones[zone]
    end
    return nil
end

local function CapturePlayerMapPos()
    local x, y = GetPlayerMapPosition("player")
    if x and y and (x > 0 or y > 0) then
        return x, y
    end
    return nil, nil
end

function Map.CapturePlayerMapPos()
    return CapturePlayerMapPos()
end

local function AcquirePin(parent)
    local pin = table.remove(pinPool)
    if not pin then
        pin = CreateFrame("Frame", nil, parent)
        pin:SetSize(16, 16)
        pin.texture = pin:CreateTexture(nil, "OVERLAY")
        pin.texture:SetAllPoints()
        pin.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-TargetingFrame-Skull")
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self)
            if not self.tooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        pin:SetParent(parent)
    end
    pin:Show()
    return pin
end

local function ReleasePins()
    for i = #activePins, 1, -1 do
        local pin = table.remove(activePins, i)
        pin:Hide()
        pin.tooltip = nil
        table.insert(pinPool, pin)
    end
end

local function ShouldShowEntry(entry)
    if not entry then return false end
    local faction = entry.faction
    local filterId = DeathLoggerDB.currentFilterId or 1
    if filterId == 2 then
        if not (faction == "Альянс" or faction == "Нейтрал") then
            return false
        end
    elseif filterId == 3 then
        if not (faction == "Орда" or faction == "Нейтрал") then
            return false
        end
    end
    if DeathLoggerDB.guildOnly then
        return Utils.IsGuildDeath(entry.playerName, entry.parseGuild, entry.tooltip, entry.data, entry.isGuild)
    end
    return true
end

local function CollectDeathsForZone(zoneName)
    local deaths = {}
    if not DeathLoggerDB.entries then return deaths end
    local want = NormalizeZone(zoneName)
    if want == "" then return deaths end

    for _, entry in ipairs(DeathLoggerDB.entries) do
        if ShouldShowEntry(entry) then
            local loc = entry.locationStr or ParseLocationFromTooltip(entry.tooltip)
            if loc and NormalizeZone(loc) == want then
                table.insert(deaths, entry)
            end
        end
    end
    return deaths
end

local function PinColor(entry)
    if Utils.IsGuildDeath(entry.playerName, entry.parseGuild, entry.tooltip, entry.data, entry.isGuild) then
        return 0.2, 1, 0.2
    end
    if entry.faction == "Альянс" then
        return 0.2, 0.45, 1
    elseif entry.faction == "Орда" then
        return 1, 0.15, 0.15
    end
    return 1, 1, 1
end

local function FormatPinTooltip(entry)
    local name = entry.playerName or "?"
    local loc = entry.locationStr or ParseLocationFromTooltip(entry.tooltip) or ""
    local extra = ""
    if entry.tooltip then
        extra = entry.tooltip
    elseif entry.data then
        extra = entry.data
    end
    if extra ~= "" then
        return extra
    end
    return string.format("%s\n%s", name, loc)
end

local countLabel

local function EnsureCountLabel(parent)
    if countLabel then return countLabel end
    countLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
    return countLabel
end

local function CountDeathsOnContinent(continent)
    if not zoneCacheBuilt then BuildZoneCache() end
    local n = 0
    if not DeathLoggerDB.entries then return 0 end
    for _, entry in ipairs(DeathLoggerDB.entries) do
        if ShouldShowEntry(entry) then
            local loc = entry.locationStr or ParseLocationFromTooltip(entry.tooltip)
            local info = loc and zoneCache[NormalizeZone(loc)]
            if info and info.continent == continent then
                n = n + 1
            end
        end
    end
    return n
end

function Map.Refresh()
    EnsureDB()
    ReleasePins()

    if not DeathLoggerDB.showDeathMap then
        if toggleButton then
            toggleButton:SetChecked(false)
        end
        if countLabel then countLabel:Hide() end
        return
    end
    if toggleButton then
        toggleButton:SetChecked(true)
    end

    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end

    local parent = WorldMapDetailFrame or WorldMapButton
    if not parent then return end

    if not zoneCacheBuilt then
        BuildZoneCache()
    end

    local zoneName = GetCurrentMapZoneName()
    local label = EnsureCountLabel(parent)
    if not zoneName then
        local continent = GetCurrentMapContinent()
        local n = (continent and continent > 0) and CountDeathsOnContinent(continent) or 0
        label:Show()
        label:SetText(n > 0 and string.format("DeathLogger: %d смертей на континенте — откройте зону", n) or "DeathLogger: нет смертей на этой карте")
        return
    end

    local deaths = CollectDeathsForZone(zoneName)
    local width, height = parent:GetWidth(), parent:GetHeight()
    if not width or width == 0 then return end

    label:Show()
    label:SetText(string.format("DeathLogger: %d смертей в зоне", #deaths))

    local count = math.min(#deaths, MAX_PINS)
    for i = 1, count do
        local entry = deaths[i]
        local loc = entry.locationStr or ParseLocationFromTooltip(entry.tooltip)
        local _, parsedX, parsedY = Utils.ParseLocation(loc or "")
        local x = entry.mapX or parsedX
        local y = entry.mapY or parsedY
        if not x or not y then
            x = 0.18 + Hash01(entry.playerName, 7) * 0.64
            y = 0.18 + Hash01(entry.playerName, 13) * 0.64
        end

        local pin = AcquirePin(parent)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", parent, "TOPLEFT", x * width, -y * height)
        pin:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
        local r, g, b = PinColor(entry)
        pin.texture:SetVertexColor(r, g, b)
        pin.tooltip = FormatPinTooltip(entry)
        table.insert(activePins, pin)
    end
end

local function CreateToggle()
    if toggleButton or not WorldMapFrame then return end
    toggleButton = CreateFrame("CheckButton", "DeathLoggerWorldMapToggle", WorldMapFrame, "OptionsCheckButtonTemplate")
    toggleButton:SetSize(24, 24)
    toggleButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 200, -32)
    local label = toggleButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", toggleButton, "RIGHT", 0, 1)
    label:SetText("DeathLogger")
    toggleButton:SetScript("OnClick", function(self)
        DeathLoggerDB.showDeathMap = self:GetChecked() and true or false
        Map.Refresh()
    end)
    toggleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Точки смертей на карте мира", 1, 1, 1)
        GameTooltip:AddLine("Зелёные — гильдия, синие — Альянс, красные — Орда.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    toggleButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function Map.Init()
    EnsureDB()
    if mapFrame then return end
    mapFrame = CreateFrame("Frame")
    mapFrame:RegisterEvent("WORLD_MAP_UPDATE")
    mapFrame:SetScript("OnEvent", function()
        if WorldMapFrame and WorldMapFrame:IsShown() then
            Map.Refresh()
        end
    end)

    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            CreateToggle()
            Map.Refresh()
        end)
        WorldMapFrame:HookScript("OnHide", function()
            ReleasePins()
        end)
        CreateToggle()
    end
end

function Map.Open()
    EnsureDB()
    DeathLoggerDB.showDeathMap = true
    if ToggleFrame then
        if not WorldMapFrame:IsShown() then
            ToggleFrame(WorldMapFrame)
        else
            WorldMapFrame:Show()
        end
    elseif WorldMapFrame then
        WorldMapFrame:Show()
    end
    Map.Refresh()
end
