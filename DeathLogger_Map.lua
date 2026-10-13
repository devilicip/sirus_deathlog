-------------------------------------------------------------------------------------------------
-- Copyright 2025-2026 Norzia (devilicip2@gmail.com) for sirus-wow
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
local Utils = _G[addonName.."_Utils"] or {}
local Data  = _G[addonName.."_Data"]  or {}
local Map = {}
_G.DeathLoggerMap = Map

local MAX_PINS = 180
local MAX_PER_POS = 3
local CLUSTER_RADIUS = 0.005
local pinPool = {}
local activePins = {}
local mapFrame
local overlay
local overlayLabel
local overlayCheck
local overlayHint
local zoneCache = {}
local zoneCacheBuilt = false
local hookedSizeToggle = false
local mobPosCache

local function EnsureDB()
    DeathLoggerDB = DeathLoggerDB or {}
    if DeathLoggerDB.showDeathMap == nil then
        DeathLoggerDB.showDeathMap = true
    end
end

local function MapIsShown()
    return WorldMapFrame and WorldMapFrame:IsShown()
end

local function RaiseAboveMapChrome(frame)
    if not frame or not WorldMapFrame then return end
    local strata = WorldMapFrame:GetFrameStrata() or "FULLSCREEN"
    frame:SetFrameStrata(strata)
    local level = WorldMapFrame:GetFrameLevel() or 1
    local chrome = {
        WorldMapTitleButton,
        WorldMapFrameCloseButton,
        WorldMapFrameSizeDownButton,
        WorldMapFrameSizeUpButton,
        WorldMapPositioningBar,
        WorldMapButton,
        WorldMapDetailFrame,
    }
    for i = 1, #chrome do
        local f = chrome[i]
        if f and f.GetFrameLevel then
            local fl = f:GetFrameLevel() or 0
            if fl > level then
                level = fl
            end
        end
    end
    frame:SetFrameLevel(level)
end

local function GetMapPinParent()
    if WorldMapButton then
        return WorldMapButton
    end
    return WorldMapDetailFrame
end

local function HookResize(frame)
    if not frame or frame.deathLoggerResizeHooked then return end
    frame.deathLoggerResizeHooked = true
    frame:HookScript("OnSizeChanged", function()
        if MapIsShown() then
            Map.Refresh()
        end
    end)
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
        local tip = WorldMapTooltip or GameTooltip
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(self.tooltip, 1, 1, 1, 1, true)
        tip:Show()
    end)
    pin:SetScript("OnLeave", function()
        local tip = WorldMapTooltip or GameTooltip
        tip:Hide()
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

local function GetKillerName(entry)
    if not entry then return nil end
    
    local k = entry.enemyName or entry.killerName or entry.killer
    if k and k ~= "" then return k end
    
    local src = entry.tooltip or entry.data
    if type(src) == "string" then
        local m = src:match("От:%s*([^\n]-)%s+%d+%-го уровня")
        if m then
            m = m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            return m:match("^%s*(.-)%s*$")
        end
    end
    return nil
end

local function BuildMobPosCache()
    if mobPosCache then return mobPosCache end
    mobPosCache = {}
    
    local csv = Data.csvData
    if not csv then return mobPosCache end
    
    local normName = Data.NormalizeName or function(s) return (s or ""):lower() end
    local normZone = Data.NormalizeZone or NormalizeZone
    
    local first = true
    for line in csv:gmatch("[^\r\n]+") do
        if first then
            first = false
        else
            local f = {}
            for v in (line..";"):gmatch("([^;]*);") do
                f[#f + 1] = v
            end
            if #f >= 9 then
                local mobName, zoneName, kind = f[1], f[5], f[6]
                local x, y = tonumber(f[8]), tonumber(f[9])
                if mobName and mobName ~= "" and zoneName and x and y then
                    local nk = normName(mobName)
                    if nk ~= "" then
                        local list = mobPosCache[nk]
                        if not list then list = {}; mobPosCache[nk] = list end
                        list[#list + 1] = {
                            zone = normZone(zoneName),
                            x = x / 100,
                            y = y / 100,
                            kind = kind,
                        }
                    end
                end
            end
        end
    end
    return mobPosCache
end

local function GetMobPositionsInZone(killerName, zoneKey, cache)
    if not killerName or not zoneKey or not cache then return nil end
    local nk = (Data.NormalizeName and Data.NormalizeName(killerName)) or strlower(killerName)
    local list = cache[nk]
    if not list then return nil end
    local result
    for _, pos in ipairs(list) do
        if pos.zone == zoneKey then
            result = result or {}
            result[#result + 1] = pos
        end
    end
    return result
end

local function GetNoKillerPositionsInZone(zoneKey)
    local tbl = Data.noKillerPositions
    if not tbl or not zoneKey then return nil end
    local list = tbl[zoneKey]
    if not list or #list == 0 then return nil end
    local result = {}
    for i = 1, #list do
        local p = list[i]
        result[#result + 1] = { x = p.x, y = p.y }
    end
    return result
end

local function UpdateOverlayVisual(countText)
    if not overlay then return end
    EnsureDB()
    local on = DeathLoggerDB.showDeathMap and true or false
    if overlayCheck then
        if on then
            overlayCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            overlayCheck:SetAlpha(1)
        else
            overlayCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
            overlayCheck:SetAlpha(0.9)
        end
    end
    if overlayLabel then
        overlayLabel:SetText(countText or "Смерти")
        if on then
            overlayLabel:SetTextColor(1, 0.82, 0)
        else
            overlayLabel:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    if overlayHint then
        overlayHint:SetText(on and "вкл" or "выкл")
        overlayHint:SetTextColor(on and 0.4 or 0.55, on and 0.9 or 0.55, on and 0.4 or 0.55)
    end
end

local function PlaceOverlay()
    if not overlay or not WorldMapFrame then return end
    overlay:SetParent(WorldMapFrame)
    overlay:ClearAllPoints()
    local anchor
    if WorldMapFrameSizeDownButton and WorldMapFrameSizeDownButton:IsShown() then
        anchor = WorldMapFrameSizeDownButton
    elseif WorldMapFrameSizeUpButton and WorldMapFrameSizeUpButton:IsShown() then
        anchor = WorldMapFrameSizeUpButton
    elseif WorldMapFrameCloseButton then
        anchor = WorldMapFrameCloseButton
    end
    if anchor then
        overlay:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    else
        overlay:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -40, -4)
    end
    RaiseAboveMapChrome(overlay)
    overlay:EnableMouse(true)
    overlay:Show()
    overlay:Raise()
end

local function MapFrameOf()
    return WorldMapFrame
end

local function IsMapMinimized()
    if WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.size and WORLDMAP_WINDOWED_SIZE
        and WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE then
        return true
    end
    if WorldMapFrameSizeUpButton and WorldMapFrameSizeUpButton:IsShown() then
        return true
    end
    return false
end

local function EnsureMapMouse()
    local frame = MapFrameOf()
    if not frame then return end
    if IsMapMinimized() and frame:IsShown() then
        if not frame:IsMouseEnabled() then
            frame:EnableMouse(true)
        end
        if not frame:IsMovable() then
            frame:SetMovable(true)
        end
        frame:SetClampedToScreen(true)
    end
end

local function SaveMapPosition()
    local frame = MapFrameOf()
    if not frame or not IsMapMinimized() then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    EnsureDB()
    DeathLoggerDB.mapLeft = left
    DeathLoggerDB.mapTop = top
end

local function RestoreMapPosition()
    local frame = MapFrameOf()
    if not frame or not frame:GetParent() then return end
    EnsureDB()
    if not DeathLoggerDB.mapLeft or not DeathLoggerDB.mapTop then return end
    
    local ratio = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
        DeathLoggerDB.mapLeft * ratio, DeathLoggerDB.mapTop * ratio)
end

local function BeginMapDrag()
    local frame = MapFrameOf()
    if not frame then return end
    
    if not IsMapMinimized()
        and not (WORLDMAP_SETTINGS and WORLDMAP_SETTINGS.advanced and not WORLDMAP_SETTINGS.locked) then
        return
    end
    
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:StartMoving()
    PlaceOverlay()
end

local function EndMapDrag()
    local frame = MapFrameOf()
    if not frame then return end
    frame:StopMovingOrSizing()
    SaveMapPosition()
    PlaceOverlay()
    Map.Refresh()
end

local function SetupMapDrag()
    local frame = MapFrameOf()
    if not frame then return end
    
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    
    if not frame.deathLoggerDragHooked then
        frame.deathLoggerDragHooked = true
        frame:HookScript("OnDragStart", BeginMapDrag)
        frame:HookScript("OnDragStop", EndMapDrag)
    end
    
    local title = WorldMapTitleButton
    if title then
        title:EnableMouse(true)
        title:RegisterForDrag("LeftButton")
        if not title.deathLoggerDragHooked then
            title.deathLoggerDragHooked = true
            title:HookScript("OnDragStart", BeginMapDrag)
            title:HookScript("OnDragStop", EndMapDrag)
        end
    end
    
    EnsureMapMouse()
end

local function SyncMapChrome()
    SetupMapDrag()
    RaiseAboveMapChrome(overlay)
    PlaceOverlay()
    Map.Refresh()
end

local function CreateOverlay()
    if overlay or not WorldMapFrame then return end
    
    overlay = CreateFrame("Frame", "DeathLoggerWorldMapToggle", WorldMapFrame)
    overlay:SetSize(168, 24)
    overlay:EnableMouse(true)
    overlay:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overlay:SetBackdropColor(0, 0, 0, 0.78)
    overlay:SetBackdropBorderColor(0.85, 0.7, 0.2, 0.95)
    
    local box = overlay:CreateTexture(nil, "ARTWORK")
    box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetSize(18, 18)
    box:SetPoint("LEFT", 4, 0)
    
    overlayCheck = overlay:CreateTexture(nil, "OVERLAY")
    overlayCheck:SetSize(16, 16)
    overlayCheck:SetPoint("CENTER", box, "CENTER", 0, 0)
    
    local skull = overlay:CreateTexture(nil, "ARTWORK")
    skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    skull:SetSize(14, 14)
    skull:SetPoint("LEFT", box, "RIGHT", 1, 0)
    
    overlayLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlayLabel:SetPoint("LEFT", skull, "RIGHT", 4, 0)
    overlayLabel:SetPoint("RIGHT", overlay, "RIGHT", -28, 0)
    overlayLabel:SetJustifyH("LEFT")
    overlayLabel:SetText("Смерти")
    
    overlayHint = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    overlayHint:SetPoint("RIGHT", -6, 0)
    overlayHint:SetText("вкл")
    
    overlay:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        EnsureDB()
        DeathLoggerDB.showDeathMap = not DeathLoggerDB.showDeathMap
        UpdateOverlayVisual()
        Map.Refresh()
    end)
    overlay:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("DeathLogger — смерти на карте", 1, 0.82, 0)
        GameTooltip:AddLine("Клик — показать или скрыть метки.", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine("Зелёные — гильдия, синие — Альянс, красные — Орда.", 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
        self:SetBackdropBorderColor(1, 0.9, 0.4, 1)
    end)
    overlay:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetBackdropBorderColor(0.85, 0.7, 0.2, 0.95)
    end)
    
    PlaceOverlay()
    UpdateOverlayVisual()
end

function Map.Refresh()
    EnsureDB()
    ReleasePins()
    CreateOverlay()
    PlaceOverlay()
    
    if not DeathLoggerDB.showDeathMap then
        UpdateOverlayVisual("Смерти")
        return
    end
    
    if not MapIsShown() then
        UpdateOverlayVisual("Смерти")
        return
    end
    
    local parent = GetMapPinParent()
    if not parent then
        UpdateOverlayVisual("Смерти")
        return
    end
    
    HookResize(parent)
    HookResize(WorldMapDetailFrame)
    HookResize(WorldMapButton)
    HookResize(WorldMapFrame)
    
    if not zoneCacheBuilt then
        BuildZoneCache()
    end
    
    local zoneName = GetCurrentMapZoneName()
    if not zoneName then
        local continent = GetCurrentMapContinent()
        local n = (continent and continent > 0) and CountDeathsOnContinent(continent) or 0
        if n > 0 then
            UpdateOverlayVisual(string.format("%d на конт.", n))
        else
            UpdateOverlayVisual("нет меток")
        end
        return
    end
    
    local deaths = CollectDeathsForZone(zoneName)
    local width, height = parent:GetWidth(), parent:GetHeight()
    if not width or width == 0 then
        UpdateOverlayVisual("Смерти")
        return
    end
    
    local zoneKey = (Data.NormalizeZone and Data.NormalizeZone(zoneName)) or NormalizeZone(zoneName)
    local cache   = BuildMobPosCache()
    
    local groups = {}
    local groupOrder = {}
    
    for _, entry in ipairs(deaths) do
        local killer = GetKillerName(entry)
        local key
        if killer then
            key = "k:" .. ((Data.NormalizeName and Data.NormalizeName(killer)) or strlower(killer))
        else
            key = "nk"
        end
        local grp = groups[key]
        if not grp then
            grp = { killer = killer, entries = {} }
            groups[key] = grp
            groupOrder[#groupOrder + 1] = key
        end
        grp.entries[#grp.entries + 1] = entry
    end
    
    local placement = {}
    
    for _, key in ipairs(groupOrder) do
        if #placement >= MAX_PINS then break end
        local grp = groups[key]
        local killer = grp.killer
        local M = #grp.entries
        
        local positions
        if killer then
            positions = GetMobPositionsInZone(killer, zoneKey, cache)
        else
            positions = GetNoKillerPositionsInZone(zoneKey)
        end
        
        if not positions or #positions == 0 then
            for _, entry in ipairs(grp.entries) do
                if #placement >= MAX_PINS then break end
                local loc = entry.locationStr or ParseLocationFromTooltip(entry.tooltip)
                local _, parsedX, parsedY = Utils.ParseLocation(loc or "")
                local px = entry.mapX or parsedX
                local py = entry.mapY or parsedY
                if not px or not py then
                    px = 0.18 + Hash01(entry.playerName, 7)  * 0.64
                    py = 0.18 + Hash01(entry.playerName, 13) * 0.64
                end
                placement[#placement + 1] = {
                    x = px, y = py, entry = entry, killer = killer,
                }
            end
        else
            local N = #positions
            local perPosition = {}
            local remaining = M
            for p = 1, N do
                local take = math.min(MAX_PER_POS, remaining)
                perPosition[p] = take
                remaining = remaining - take
            end
            if remaining > 0 then
                perPosition[N] = perPosition[N] + remaining
            end
            
            local deathIdx = 0
            for p = 1, N do
                if #placement >= MAX_PINS then break end
                local cnt = perPosition[p]
                if cnt > 0 then
                    local pos = positions[p]
                    for k = 1, cnt do
                        if #placement >= MAX_PINS then break end
                        deathIdx = deathIdx + 1
                        local entry = grp.entries[deathIdx]
                        local ox, oy = 0, 0
                        if cnt > 1 then
                            local angle = (k - 1) * (math.pi * 2 / cnt)
                            ox = math.cos(angle) * CLUSTER_RADIUS
                            oy = math.sin(angle) * CLUSTER_RADIUS
                        end
                        placement[#placement + 1] = {
                            x = pos.x + ox,
                            y = pos.y + oy,
                            entry = entry,
                            killer = killer,
                        }
                    end
                end
            end
        end
    end
    
    for i = 1, #placement do
        local rec = placement[i]
        local pin = AcquirePin(parent)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", parent, "TOPLEFT", rec.x * width, -rec.y * height)
        pin:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
        
        local r, gcol, b = PinColor(rec.entry)
        pin.texture:SetVertexColor(r, gcol, b)
        
        if rec.killer then
            pin.tooltip = string.format("Убийца: %s\n%s",
                rec.killer, FormatPinTooltip(rec.entry))
        else
            pin.tooltip = FormatPinTooltip(rec.entry)
        end
        
        table.insert(activePins, pin)
    end
    
    UpdateOverlayVisual(string.format("%d в зоне", #placement))
end

function Map.Init()
    EnsureDB()
    if mapFrame then return end
    mapFrame = CreateFrame("Frame")
    mapFrame:RegisterEvent("WORLD_MAP_UPDATE")
    mapFrame:SetScript("OnEvent", function()
        if MapIsShown() then
            PlaceOverlay()
            Map.Refresh()
        end
    end)
    
    local function OnMapShow()
        CreateOverlay()
        PlaceOverlay()
        Map.Refresh()
    end
    
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            OnMapShow()
            EnsureMapMouse()
            RestoreMapPosition()
            SetupMapDrag()
        end)
        WorldMapFrame:HookScript("OnHide", function()
            ReleasePins()
        end)
        CreateOverlay()
        
        HookResize(WorldMapFrame)
        HookResize(WorldMapPositioningGuide)
        HookResize(WorldMapDetailFrame)
        HookResize(WorldMapButton)
        
        if MapIsShown() then
            OnMapShow()
        end
    end
    
    if not hookedSizeToggle and type(hooksecurefunc) == "function" then
        hookedSizeToggle = true
        if WorldMapFrame_ToggleWindowSize then
            hooksecurefunc("WorldMapFrame_ToggleWindowSize", function()
                SyncMapChrome()
            end)
        end
        
        if WorldMap_ToggleSizeDown then
            hooksecurefunc("WorldMap_ToggleSizeDown", function()
                EnsureMapMouse()
                RestoreMapPosition()
                SyncMapChrome()
            end)
        end
        if WorldMap_ToggleSizeUp then
            hooksecurefunc("WorldMap_ToggleSizeUp", function()
                SyncMapChrome()
            end)
        end
        if WorldMapFrame_SetMiniMode then
            hooksecurefunc("WorldMapFrame_SetMiniMode", function()
                EnsureMapMouse()
            end)
        end
    end
    
    SetupMapDrag()
end

function Map.Open()
    EnsureDB()
    DeathLoggerDB.showDeathMap = true
    if WorldMapFrame then
        if not WorldMapFrame:IsShown() then
            if ToggleFrame then
                ToggleFrame(WorldMapFrame)
            else
                WorldMapFrame:Show()
            end
        end
    end
    CreateOverlay()
    PlaceOverlay()
    UpdateOverlayVisual()
    Map.Refresh()
end