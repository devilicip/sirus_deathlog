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
local Utils = _G[addonName.."_Utils"] or {}
if not _G.DeathLoggerDB then
    _G.DeathLoggerDB = {}
end
local HCBL_Settings = _G.DeathLoggerDB.HCBL_Settings or {}
_G.DeathLoggerDB.HCBL_Settings = HCBL_Settings
local iconSize = 44
local ICON_BASE_PATH = "Interface\\AddOns\\DeathLogger\\Icons\\" 
_G.deathIcons = {}
for i = 0, 11 do
    _G.deathIcons[i] = ICON_BASE_PATH .. i .. ".tga"
end
local widgetInstance = _G.widgetInstance

local defaults = {
    origOffsetX = 0,
    origOffsetY = 100,
    showOriginalForPositioning = false,
    moveOriginal = false,
    hideOriginal = false,
    currentDeathIcon = _G.deathIcons[11],
    hideSkullCircle = false,
    fontName = "FRIZQT__",
    fontSize = 15,
    fontColor = {r=1, g=1, b=1, a=1},
    fontOutline = "NONE",
    fontShadow = true,
    fontStyle = "NORMAL",
    scaleFactor = 1.0,
    dl_ver = 1.893,
    guildChatTextCompleted = "ГЦ",
    guildChatTextDeath = "F",
    useRandomPhrases = false,
    randomPhrasesCompleted = "",
    randomPhrasesDeath = ""
}

local isConfigOpen = false
_G.isConfigOpen = isConfigOpen


local function CreateCustomButton(parent, width, height, text)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 140, height or 25)
    
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    bg:SetTexCoord(0, 0.625, 0, 0.6875)
    bg:SetAllPoints()
    button.bg = bg
    
    local pushed = button:CreateTexture(nil, "BACKGROUND")
    pushed:SetTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    pushed:SetTexCoord(0, 0.625, 0, 0.6875)
    pushed:SetAllPoints()
    pushed:Hide()
    button.pushed = pushed
    
    local highlight = button:CreateTexture(nil, "BACKGROUND")
    highlight:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    highlight:SetTexCoord(0, 0.625, 0, 0.6875)
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    highlight:Hide()
    button.highlight = highlight
    
    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonText:SetPoint("CENTER", 0, 1)
    buttonText:SetText(text or "")
    button.text = buttonText
    
    button:SetScript("OnMouseDown", function(self)
        self.pushed:Show()
        self.text:SetPoint("CENTER", 1, -1)
    end)
    
    button:SetScript("OnMouseUp", function(self)
        self.pushed:Hide()
        self.text:SetPoint("CENTER", 0, 1)
    end)
    
    button:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        self.highlight:Hide()
    end)
    
    button:EnableMouse(true)
    
    button.SetText = function(self, newText)
        self.text:SetText(newText)
    end
    
    button.GetText = function(self)
        return self.text:GetText()
    end
    
    return button
end

local function CreateCustomEditBox(parent, width, height)
    local editbox = CreateFrame("EditBox", nil, parent)
    editbox:SetSize(width or 100, height or 20)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(GameFontHighlight)
    
    local bg = editbox:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bg:SetVertexColor(0, 0, 0, 0.5)
    bg:SetAllPoints()
    editbox.bg = bg
    
    editbox:SetTextInsets(5, 5, 0, 0)
    editbox:SetMaxLetters(50)
    editbox:SetTextColor(1, 1, 1, 1)
    
    editbox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    
    editbox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    editbox:SetScript("OnEditFocusGained", function(self)
        self.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
    end)
    
    editbox:SetScript("OnEditFocusLost", function(self)
        self.bg:SetVertexColor(0, 0, 0, 0.5)
    end)
    
    return editbox
end

-- Баннер
local function UpdateBannerElements()
    HCBL_Settings = HCBL_Settings or {}
    if not (HardcoreLossBanner and HardcoreLossBanner.Title) then
        return
    end
    
    if HCBL_Settings.hideOriginal then
        HardcoreLossBanner:Hide()
        return
    end
    
    HCBL_Settings.fontColor = HCBL_Settings.fontColor or defaults.fontColor
    HCBL_Settings.scaleFactor = HCBL_Settings.scaleFactor or defaults.scaleFactor
    HCBL_Settings.fontName = HCBL_Settings.fontName or defaults.fontName
    HCBL_Settings.fontOutline = HCBL_Settings.fontOutline or defaults.fontOutline
    
    if HardcoreLossBanner and HardcoreLossBanner.Title then
        HCBL_Settings.fontColor = HCBL_Settings.fontColor or {r=1, g=1, b=1, a=1}
        
        local fontPath = string.format("Fonts\\%s.ttf", HCBL_Settings.fontName or defaults.fontName)
        HardcoreLossBanner.Title:SetFont(fontPath, HCBL_Settings.fontSize or defaults.fontSize, HCBL_Settings.fontOutline or defaults.fontOutline)
        
        local scale = HCBL_Settings.scaleFactor or 1.0
        scale = math.min(math.max(scale, 0.5), 2.0)
        HardcoreLossBanner:SetScale(scale)
        
        HardcoreLossBanner.Title:SetTextColor(
            HCBL_Settings.fontColor.r,
            HCBL_Settings.fontColor.g,
            HCBL_Settings.fontColor.b,
            HCBL_Settings.fontColor.a
        )
        HardcoreLossBanner.Title:SetShadowColor(0, 0, 0, HCBL_Settings.fontShadow and 1 or 0)
        HardcoreLossBanner.Title:SetShadowOffset(1, -1)
    end
    
    if not HardcoreLossBanner.CustomDeathIcon then
        HardcoreLossBanner.CustomDeathIcon = HardcoreLossBanner:CreateTexture(nil, "OVERLAY", nil, 7)
        HardcoreLossBanner.CustomDeathIcon:SetSize(iconSize, iconSize)
        HardcoreLossBanner.CustomDeathIcon:SetPoint("CENTER", HardcoreLossBanner.SkullCircle, "CENTER", 0, 0)
        HardcoreLossBanner.CustomDeathIcon:SetBlendMode("BLEND")
        HardcoreLossBanner.CustomDeathIcon:SetTexCoord(0, 1, 0, 1)
        
        local maskTexture = HardcoreLossBanner:CreateTexture(nil, "BORDER")
        maskTexture:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        maskTexture:SetAllPoints(HardcoreLossBanner.CustomDeathIcon)
        maskTexture:SetSize(iconSize, iconSize)
    end
    
    if HCBL_Settings.currentDeathIcon then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(HCBL_Settings.currentDeathIcon)
    end
    
    local icon = HCBL_Settings.currentDeathIcon or defaults.currentDeathIcon
    
    if icon ~= "" and not HCBL_Settings.hideSkullCircle then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(icon)
        HardcoreLossBanner.CustomDeathIcon:Show()
        HardcoreLossBanner.SkullCircle:SetAlpha(0)
    else
        HardcoreLossBanner.CustomDeathIcon:Hide()
        HardcoreLossBanner.SkullCircle:SetAlpha(1)
    end
    
    local scale = math.min(math.max(HCBL_Settings.scaleFactor or 1.0, 0.5), 2.0)
    HardcoreLossBanner:SetScale(scale)
end

local function UpdateBannerPosition()
    if HardcoreLossBanner then
        HardcoreLossBanner:ClearAllPoints()
        HardcoreLossBanner:SetPoint(
            "CENTER", 
            UIParent, 
            "CENTER", 
            HCBL_Settings.origOffsetX, 
            HCBL_Settings.origOffsetY
        )
        UpdateBannerElements()
    end
end

local function SetupBannerMovement(banner)
    banner:SetMovable(true)
    banner:EnableMouse(true)
    banner:SetScript("OnMouseDown", function(self, button)
        if isConfigOpen and button == "LeftButton" and HCBL_Settings.moveOriginal then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    
    banner:SetScript("OnMouseUp", function(self, button)
         if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            
            local centerX, centerY = self:GetCenter()
            local screenWidth = UIParent:GetWidth()
            local screenHeight = UIParent:GetHeight()
            
            HCBL_Settings.origOffsetX = (centerX - screenWidth / 2)
            HCBL_Settings.origOffsetY = (centerY - screenHeight / 2)
            
            DeathLoggerDB.HCBL_Settings.origOffsetX = HCBL_Settings.origOffsetX
            DeathLoggerDB.HCBL_Settings.origOffsetY = HCBL_Settings.origOffsetY
            
            UpdateBannerPosition()
        end
    end)
end

local function SetupOriginalBanner()
    if not DeathLoggerDB.HCBL_Settings then
        DeathLoggerDB.HCBL_Settings = {}
    end
    HCBL_Settings = DeathLoggerDB.HCBL_Settings
    
    if HardcoreLossBanner and not HardcoreLossBanner.originalShow then
        HardcoreLossBanner.originalShow = HardcoreLossBanner.Show
        HardcoreLossBanner.Show = function(self, ...)
            if HCBL_Settings.hideOriginal then
                return
            end
            self:originalShow(...)
        end
    end
    
    if HardcoreLossBanner then
        UpdateBannerPosition()
        SetupBannerMovement(HardcoreLossBanner)
        UpdateBannerElements()
        
        if HCBL_Settings.hideOriginal then
            HardcoreLossBanner:Hide()
            HCBL_Settings.moveOriginal = false
        else
            HardcoreLossBanner:SetShown(isConfigOpen and HCBL_Settings.moveOriginal)
        end
    end
end

-- Вкладки
local function CreateTabSystem(panel)
    local tabs = {}
    local currentTab = nil
    
    local contentBackground = CreateFrame("Frame", nil, panel)
    contentBackground:SetPoint("TOPLEFT", 16, -50)
    contentBackground:SetPoint("BOTTOMRIGHT", panel, -16, 50)
    contentBackground:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    contentBackground:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    contentBackground:SetBackdropBorderColor(0.4, 0.4, 0.4)
    
    local contentFrame = CreateFrame("Frame", nil, contentBackground)
    contentFrame:SetPoint("TOPLEFT", 10, -10)
    contentFrame:SetPoint("BOTTOMRIGHT", -10, 10)
    
    function tabs.CreateTab(name, title)
        local tabIndex = #tabs + 1
        local tab = CreateFrame("Button", "DeathLoggerTab"..tabIndex, panel, "CharacterFrameTabButtonTemplate")
        tab:SetID(tabIndex)
        tab:SetText(title)
        
        if tabIndex == 1 then
            tab:SetPoint("BOTTOMLEFT", contentBackground, "BOTTOMLEFT", 10, -28)
        else
            tab:SetPoint("LEFT", _G["DeathLoggerTab"..(tabIndex-1)], "RIGHT", -16, 0)
        end
        
        tab:SetScript("OnClick", function(self)
            tabs.SwitchTab(tabIndex)
        end)
        
        tabs[tabIndex] = {
            frame = tab,
            name = name,
            content = CreateFrame("Frame", nil, contentFrame),
            elements = {},
            updateFunction = nil
        }
        
        tabs[tabIndex].content:SetAllPoints(contentFrame)
        tabs[tabIndex].content:Hide()
        
        return tabs[tabIndex]
    end
    
    function tabs.SwitchTab(tabIndex)
        for i, tabData in ipairs(tabs) do
            tabData.content:Hide()
            PanelTemplates_DeselectTab(tabData.frame)
        end
        
        currentTab = tabs[tabIndex]
        currentTab.content:Show()
        PanelTemplates_SelectTab(currentTab.frame)
        
        if currentTab.updateFunction then
            currentTab.updateFunction()
        end
    end
    
    function tabs.Initialize()
        if #tabs > 0 then
            tabs.SwitchTab(1)
        end
    end
    
    return tabs, contentFrame
end

-- настройки - первая
local function CreateGeneralTab(tab)
    local content = tab.content
    
    local sizeHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeHeader:SetPoint("TOPLEFT", 10, -10)
    sizeHeader:SetText("Размеры окна")
    
    local screenWidth = GetScreenWidth()
    local screenHeight = GetScreenHeight()
    local maxWidth = screenWidth * 0.45
    local maxHeight = screenHeight * 0.70
    
    local function GetCurrentWindowSizePercent()
        local currentWidth, currentHeight
        
        if _G.widgetInstance and _G.widgetInstance.mainWnd then
            currentWidth, currentHeight = _G.widgetInstance.mainWnd:GetSize()
        else
            currentWidth = DeathLoggerDB.width or DeathLoggerDB.minWidth or 200
            currentHeight = DeathLoggerDB.height or DeathLoggerDB.minHeight or 100
        end
        
        local widthPercent = math.floor((currentWidth / screenWidth) * 100)
        local heightPercent = math.floor((currentHeight / screenHeight) * 100)
        
        widthPercent = math.min(math.max(widthPercent, 10), 45)
        heightPercent = math.min(math.max(heightPercent, 10), 70)
        
        return widthPercent, heightPercent
    end
    
    local minWidthLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minWidthLabel:SetPoint("TOPLEFT", sizeHeader, "BOTTOMLEFT", 0, -20)
    minWidthLabel:SetText("Минимальная ширина (в % от экрана):")
    
    local minWidthSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    minWidthSlider:SetPoint("TOPLEFT", minWidthLabel, "BOTTOMLEFT", 0, -10)
    minWidthSlider:SetWidth(200)
    minWidthSlider:SetMinMaxValues(10, 45)
    minWidthSlider:SetValueStep(1)
    minWidthSlider.tooltipText = "Установите минимальную ширину окна в процентах от ширины экрана (макс. 45%)"
    minWidthSlider.Low:SetText("10%")
    minWidthSlider.High:SetText("45%")
    minWidthSlider.Text = minWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minWidthSlider.Text:SetPoint("TOP", minWidthSlider, "BOTTOM", 0, -5)
    
    local isUpdatingSlider = false
    
    minWidthSlider:SetScript("OnValueChanged", function(self, value)
        if isUpdatingSlider then return end
        
        local percent = math.floor(value)
        self.Text:SetText(percent .. "%")
        
        if self.userModified then
            DeathLoggerDB.minWidth = math.max(100, math.min(screenWidth * percent / 100, screenWidth * 0.45))
            DeathLoggerDB.width = DeathLoggerDB.minWidth
            
            if _G.widgetInstance and _G.widgetInstance.mainWnd then
                _G.widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
                _G.widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
                _G.widgetInstance.mainWnd:SetWidth(math.min(DeathLoggerDB.minWidth, maxWidth))
            end
        end
    end)
    
    minWidthSlider:SetScript("OnMouseDown", function(self)
        self.userModified = true
    end)
    
    local minHeightLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minHeightLabel:SetPoint("LEFT", minWidthLabel, "RIGHT", 50, 0)
    minHeightLabel:SetText("Минимальная высота окна (%):")
    
    local minHeightSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    minHeightSlider:SetPoint("TOPLEFT", minHeightLabel, "BOTTOMLEFT", 0, -10)
    minHeightSlider:SetWidth(200)
    minHeightSlider:SetMinMaxValues(10, 70)
    minHeightSlider:SetValueStep(1)
    minHeightSlider.tooltipText = "Установите минимальную высоту окна в процентах от высоты экрана (макс. 70%)"
    minHeightSlider.Low:SetText("10%")
    minHeightSlider.High:SetText("70%")
    minHeightSlider.Text = minHeightSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minHeightSlider.Text:SetPoint("TOP", minHeightSlider, "BOTTOM", 0, -5)
    
    minHeightSlider:SetScript("OnValueChanged", function(self, value)
        if isUpdatingSlider then return end
        
        local percent = math.floor(value)
        self.Text:SetText(percent .. "%")
        
        if self.userModified then
            DeathLoggerDB.minHeight = screenHeight * percent / 100
            DeathLoggerDB.height = DeathLoggerDB.minHeight
            
            if _G.widgetInstance and _G.widgetInstance.mainWnd then
                _G.widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
                _G.widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
                _G.widgetInstance.mainWnd:SetHeight(math.min(DeathLoggerDB.minHeight, maxHeight))
            end
        end
    end)
    
    minHeightSlider:SetScript("OnMouseDown", function(self)
        self.userModified = true
    end)
    
    local filterHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterHeader:SetPoint("TOPLEFT", minWidthSlider, "BOTTOMLEFT", 0, -30)
    filterHeader:SetText("Фильтры отображения")
    
    local guildOnlyCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    guildOnlyCheckbox:SetPoint("TOPLEFT", filterHeader, "BOTTOMLEFT", 0, -20)
    guildOnlyCheckbox:SetSize(24, 24)
    local guildOnlyText = guildOnlyCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildOnlyText:SetPoint("LEFT", guildOnlyCheckbox, "RIGHT", 5, 0)
    guildOnlyText:SetText("Показывать только гильдейские смерти")
    guildOnlyCheckbox:SetScript("OnClick", function(self)
        DeathLoggerDB.guildOnly = self:GetChecked()
        if _G.widgetInstance then
            _G.widgetInstance:ApplyFilter(function(entry) return true end)
        end
    end)
    
    guildOnlyCheckbox.tooltipText = "Если включено, фильтр применяется только к текущему составу гильдии.\n\n|cFF00FF00Примечание:|r Если игрок удалил игрового персонажа фильтр не будет применяться."
    guildOnlyCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    guildOnlyCheckbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    local announceCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    announceCheckbox:SetPoint("TOPLEFT", guildOnlyCheckbox, "BOTTOMLEFT", 0, -30)
    announceCheckbox:SetSize(24, 24)
    local announceText = announceCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    announceText:SetPoint("LEFT", announceCheckbox, "RIGHT", 5, 0)
    announceText:SetText("Сообщать в гильдию о своей смерти")
    announceCheckbox:SetScript("OnClick", function(self)
        DeathLoggerDB.announceDeathToGuild = self:GetChecked()
    end)
    
    announceCheckbox.tooltipText = "При включении, при вашей смерти будет отправлено сообщение в гильдейский чат"
    announceCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    announceCheckbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    local function UpdateGeneralTab()
        if DeathLoggerDB.minWidth == nil then
            DeathLoggerDB.minWidth = 200
            DeathLoggerDB.width = 200
        end
        if DeathLoggerDB.minHeight == nil then
            DeathLoggerDB.minHeight = 100
            DeathLoggerDB.height = 100
        end
        if DeathLoggerDB.guildOnly == nil then
            DeathLoggerDB.guildOnly = false
        end
        if DeathLoggerDB.announceDeathToGuild == nil then
            DeathLoggerDB.announceDeathToGuild = true
        end
        
        local currentWidthPercent, currentHeightPercent = GetCurrentWindowSizePercent()
        
        isUpdatingSlider = true
        
        minWidthSlider:SetValue(currentWidthPercent)
        minWidthSlider.Text:SetText(currentWidthPercent .. "%")
        
        minHeightSlider:SetValue(currentHeightPercent)
        minHeightSlider.Text:SetText(currentHeightPercent .. "%")
        
        minWidthSlider.userModified = false
        minHeightSlider.userModified = false
        
        isUpdatingSlider = false
        
        guildOnlyCheckbox:SetChecked(DeathLoggerDB.guildOnly)
        announceCheckbox:SetChecked(DeathLoggerDB.announceDeathToGuild)
    end
    
    tab.elements = {
        minWidthSlider = minWidthSlider,
        minHeightSlider = minHeightSlider,
        guildOnlyCheckbox = guildOnlyCheckbox,
        announceCheckbox = announceCheckbox
    }
    
    tab.updateFunction = UpdateGeneralTab
    
    UpdateGeneralTab()
end

-- Вкладка вторая
local function CreateBannerTab(tab)
    local content = tab.content
    
    local bannerHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bannerHeader:SetPoint("TOPLEFT", 10, -10)
    bannerHeader:SetText("Настройки баннера смерти")
    
    local hideCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    hideCheckbox:SetPoint("TOPLEFT", bannerHeader, "BOTTOMLEFT", 0, -20)
    hideCheckbox:SetSize(24, 24)
    local hideText = hideCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideText:SetPoint("LEFT", hideCheckbox, "RIGHT", 5, 0)
    hideText:SetText("Скрыть оригинальный баннер")
    
    local moveCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    moveCheckbox:SetPoint("TOPLEFT", hideCheckbox, "BOTTOMLEFT", 0, -30)
    moveCheckbox:SetSize(24, 24)
    local moveText = moveCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moveText:SetPoint("LEFT", moveCheckbox, "RIGHT", 5, 0)
    moveText:SetText("Разрешить перемещение баннера")
    
    local skullCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    skullCheckbox:SetPoint("TOPLEFT", moveCheckbox, "BOTTOMLEFT", 0, -30)
    skullCheckbox:SetSize(24, 24)
    local skullText = skullCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skullText:SetPoint("LEFT", skullCheckbox, "RIGHT", 5, 0)
    skullText:SetText("Использовать стандартный череп")
    
    local function UpdateMoveCheckboxState()
        if HCBL_Settings.hideOriginal then
            moveCheckbox:SetEnabled(false)
            moveCheckbox:SetAlpha(0.5)
            moveCheckbox:SetChecked(false)
            HCBL_Settings.moveOriginal = false
        else
            moveCheckbox:SetEnabled(true)
            moveCheckbox:SetAlpha(1)
        end
    end
    
    hideCheckbox:SetScript("OnClick", function(self)
        HCBL_Settings.hideOriginal = self:GetChecked()
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateMoveCheckboxState()
        SetupOriginalBanner()
    end)
    
    moveCheckbox:SetScript("OnClick", function(self)
        if not HCBL_Settings.hideOriginal then
            HCBL_Settings.moveOriginal = self:GetChecked()
            DeathLoggerDB.HCBL_Settings = HCBL_Settings
            SetupOriginalBanner()
        end
    end)
    
    skullCheckbox:SetScript("OnClick", function(self)
        HCBL_Settings.hideSkullCircle = self:GetChecked()
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateBannerElements()
    end)
    
    local resetButton = CreateCustomButton(content, 140, 25, "Сбросить позицию")
    resetButton:SetPoint("TOPLEFT", skullCheckbox, "BOTTOMLEFT", 0, -40)
    resetButton:SetScript("OnClick", function()
        HCBL_Settings.origOffsetX = defaults.origOffsetX
        HCBL_Settings.origOffsetY = defaults.origOffsetY
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateBannerPosition()
    end)
    
    local textHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textHeader:SetPoint("TOPLEFT", 300, -10)
    textHeader:SetText("Настройки текста")
    
    local fontLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontLabel:SetPoint("TOPLEFT", textHeader, "BOTTOMLEFT", 0, -20)
    fontLabel:SetText("Шрифт:")
    
    local fontDropdown = CreateFrame("Frame", "HCBLFontDropdown", content, "UIDropDownMenuTemplate")
    fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -20, -10)
    UIDropDownMenu_SetWidth(fontDropdown, 150)
    
    local outlineLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    outlineLabel:SetPoint("TOPLEFT", fontDropdown, "BOTTOMLEFT", 20, -20)
    outlineLabel:SetText("Контур:")
    
    local outlineDropdown = CreateFrame("Frame", "HCBLOutlineDropdown", content, "UIDropDownMenuTemplate")
    outlineDropdown:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", -20, -10)
    UIDropDownMenu_SetWidth(outlineDropdown, 150)
    
    local colorButton = CreateCustomButton(content, 120, 25, "Цвет текста")
    colorButton:SetPoint("TOPLEFT", outlineDropdown, "BOTTOMLEFT", 20, -20)
    
    local shadowCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    shadowCheckbox:SetPoint("TOPLEFT", colorButton, "BOTTOMLEFT", 0, -20)
    shadowCheckbox:SetSize(24, 24)
    local shadowText = shadowCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shadowText:SetPoint("LEFT", shadowCheckbox, "RIGHT", 5, 0)
    shadowText:SetText("Тень текста")
    
    local scaleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLabel:SetPoint("TOPLEFT", shadowCheckbox, "BOTTOMLEFT", 0, -20)
    scaleLabel:SetText("Масштаб баннера:")
    
    local scaleSlider = CreateFrame("Slider", nil, content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -10)
    scaleSlider:SetWidth(200)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider.Text = scaleSlider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scaleSlider.Text:SetPoint("TOP", scaleSlider, "BOTTOM", 0, 2)
    
    local function FontDropdown_Initialize()
        local fonts = {"FRIZQT__", "ARIALN", "MORPHEUS", "SKURRI", "FRIENDS", "NIM_____"}
        local currentFont = HCBL_Settings.fontName or defaults.fontName
        
        for _, font in ipairs(fonts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = font
            info.checked = (font == currentFont)
            info.func = function()
                HCBL_Settings.fontName = font
                DeathLoggerDB.HCBL_Settings = HCBL_Settings
                UIDropDownMenu_SetText(fontDropdown, font)
                UpdateBannerElements()
            end
            UIDropDownMenu_AddButton(info)
        end
    end
    
    local function OutlineDropdown_Initialize()
        local outlines = {"NONE", "OUTLINE", "THICKOUTLINE"}
        local currentOutline = HCBL_Settings.fontOutline or defaults.fontOutline
        
        for _, outline in ipairs(outlines) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = outline
            info.checked = (outline == currentOutline)
            info.func = function()
                HCBL_Settings.fontOutline = outline
                DeathLoggerDB.HCBL_Settings = HCBL_Settings
                UIDropDownMenu_SetText(outlineDropdown, outline)
                UpdateBannerElements()
            end
            UIDropDownMenu_AddButton(info)
        end
    end
    
    UIDropDownMenu_Initialize(fontDropdown, FontDropdown_Initialize)
    UIDropDownMenu_Initialize(outlineDropdown, OutlineDropdown_Initialize)
    
    colorButton:SetScript("OnClick", function()
        ColorPickerFrame:SetColorRGB(
            HCBL_Settings.fontColor.r or defaults.fontColor.r,
            HCBL_Settings.fontColor.g or defaults.fontColor.g, 
            HCBL_Settings.fontColor.b or defaults.fontColor.b
        )
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = HCBL_Settings.fontColor.a or defaults.fontColor.a
        ColorPickerFrame.func = function()
            HCBL_Settings.fontColor.r, HCBL_Settings.fontColor.g, HCBL_Settings.fontColor.b = ColorPickerFrame:GetColorRGB()
            HCBL_Settings.fontColor.a = OpacitySliderFrame:GetValue()
            DeathLoggerDB.HCBL_Settings = HCBL_Settings
            UpdateBannerElements()
        end
        ColorPickerFrame:Show()
    end)
    
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        HCBL_Settings.scaleFactor = math.floor(value * 10) / 10
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        self.Text:SetText(string.format("Размер: %.1f", HCBL_Settings.scaleFactor))
        UpdateBannerElements()
    end)
    
    shadowCheckbox:SetScript("OnClick", function(self)
        HCBL_Settings.fontShadow = self:GetChecked()
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateBannerElements()
    end)
    
    local function UpdateBannerTab()
        hideCheckbox:SetChecked(HCBL_Settings.hideOriginal or false)
        moveCheckbox:SetChecked(HCBL_Settings.moveOriginal or false)
        skullCheckbox:SetChecked(HCBL_Settings.hideSkullCircle or false)
        shadowCheckbox:SetChecked(HCBL_Settings.fontShadow ~= nil and HCBL_Settings.fontShadow or defaults.fontShadow)
        
        UIDropDownMenu_SetText(fontDropdown, HCBL_Settings.fontName or defaults.fontName)
        UIDropDownMenu_SetText(outlineDropdown, HCBL_Settings.fontOutline or defaults.fontOutline)
        
        local scaleValue = HCBL_Settings.scaleFactor or defaults.scaleFactor
        scaleSlider:SetValue(scaleValue)
        scaleSlider.Text:SetText(string.format("Размер: %.1f", scaleValue))
        
        UpdateMoveCheckboxState()
        
        UIDropDownMenu_Initialize(fontDropdown, FontDropdown_Initialize)
        UIDropDownMenu_Initialize(outlineDropdown, OutlineDropdown_Initialize)
    end
    
    tab.elements = {
        hideCheckbox = hideCheckbox,
        moveCheckbox = moveCheckbox,
        skullCheckbox = skullCheckbox,
        fontDropdown = fontDropdown,
        outlineDropdown = outlineDropdown,
        shadowCheckbox = shadowCheckbox,
        scaleSlider = scaleSlider
    }
    
    tab.updateFunction = UpdateBannerTab
    
    UpdateBannerTab()
end

-- Вкладка третья
local function CreateSyncTab(tab)
    local content = tab.content
    
    local syncHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncHeader:SetPoint("TOPLEFT", 10, -10)
    syncHeader:SetText("Синхронизация данных")
    
    local syncCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    syncCheckbox:SetPoint("TOPLEFT", syncHeader, "BOTTOMLEFT", 0, -20)
    syncCheckbox:SetSize(24, 24)
    local syncText = syncCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncText:SetPoint("LEFT", syncCheckbox, "RIGHT", 5, 0)
    syncText:SetText("Включить синхронизацию")
    
    local autoSyncCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    autoSyncCheckbox:SetPoint("TOPLEFT", syncCheckbox, "BOTTOMLEFT", 0, -30)
    autoSyncCheckbox:SetSize(24, 24)
    local autoSyncText = autoSyncCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoSyncText:SetPoint("LEFT", autoSyncCheckbox, "RIGHT", 5, 0)
    autoSyncText:SetText("Автоматическая синхронизация при входе")
    
    local notifyCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    notifyCheckbox:SetPoint("TOPLEFT", autoSyncCheckbox, "BOTTOMLEFT", 0, -30)
    notifyCheckbox:SetSize(24, 24)
    local notifyText = notifyCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notifyText:SetPoint("LEFT", notifyCheckbox, "RIGHT", 5, 0)
    notifyText:SetText("Уведомления о синхронизации")
    
    local syncButton = CreateCustomButton(content, 180, 25, "Запросить историю сейчас")
    syncButton:SetPoint("TOPLEFT", notifyCheckbox, "BOTTOMLEFT", 0, -20)
    syncButton:SetScript("OnClick", function()
        if DeathLoggerSync and DeathLoggerSync.RequestFullSync then
            DeathLoggerSync:RequestFullSync()
        end
    end)
    
    local chatHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chatHeader:SetPoint("LEFT", syncHeader, "RIGHT", 180, 0)
    chatHeader:SetText("Текст в гильдейском чате")
    
    local deathLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    deathLabel:SetPoint("TOPLEFT", chatHeader, "BOTTOMLEFT", 0, -20)
    deathLabel:SetText("Фраза для умерших:")
    
    local deathEdit = CreateCustomEditBox(content, 100, 20)
    deathEdit:SetPoint("TOPLEFT", deathLabel, "BOTTOMLEFT", 0, -10)
    deathEdit:SetScript("OnTextChanged", function(self)
        DeathLoggerDB.guildChatTextDeath = self:GetText() or defaults.guildChatTextDeath
    end)
    deathEdit:SetScript("OnEscapePressed", function(self) 
        self:ClearFocus() 
    end)
    deathEdit:SetScript("OnEnterPressed", function(self) 
        self:ClearFocus() 
    end)
    
    local completedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    completedLabel:SetPoint("TOPLEFT", deathEdit, "BOTTOMLEFT", 0, -20)
    completedLabel:SetText("Фраза для завершивших:")
    
    local completedEdit = CreateCustomEditBox(content, 100, 20)
    completedEdit:SetPoint("TOPLEFT", completedLabel, "BOTTOMLEFT", 0, -10)
    completedEdit:SetScript("OnTextChanged", function(self)
        DeathLoggerDB.guildChatTextCompleted = self:GetText() or defaults.guildChatTextCompleted
    end)
    completedEdit:SetScript("OnEscapePressed", function(self) 
        self:ClearFocus() 
    end)
    completedEdit:SetScript("OnEnterPressed", function(self) 
        self:ClearFocus() 
    end)
    
    local randomPhrasesCheckbox = CreateFrame("CheckButton", nil, content, "OptionsCheckButtonTemplate")
    randomPhrasesCheckbox:SetPoint("TOPLEFT", completedEdit, "BOTTOMLEFT", 0, -20)
    randomPhrasesCheckbox:SetSize(24, 24)
    local randomPhrasesText = randomPhrasesCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    randomPhrasesText:SetPoint("LEFT", randomPhrasesCheckbox, "RIGHT", 5, 0)
    randomPhrasesText:SetText("Использовать случайные фразы")
    
    randomPhrasesCheckbox.tooltipText = "Если включено, будут показываться случйаные фразы. Перечислить фразы через ENTER"
    randomPhrasesCheckbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    randomPhrasesCheckbox:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    local randomDeathLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    randomDeathLabel:SetPoint("TOPLEFT", randomPhrasesCheckbox, "BOTTOMLEFT", 0, -20)
    randomDeathLabel:SetText("Случайная для умерших:")
    
    local randomDeathEdit = CreateFrame("EditBox", nil, content)
    randomDeathEdit:SetPoint("TOPLEFT", randomDeathLabel, "BOTTOMLEFT", 0, -10)
    randomDeathEdit:SetSize(200, 60)
    randomDeathEdit:SetMultiLine(true)
    randomDeathEdit:SetAutoFocus(false)
    randomDeathEdit:SetFontObject(GameFontHighlight)
    randomDeathEdit:SetTextInsets(5, 5, 5, 5)
    randomDeathEdit:SetMaxLetters(500)
    
    local bgDeath = randomDeathEdit:CreateTexture(nil, "BACKGROUND")
    bgDeath:SetAllPoints(randomDeathEdit)
    bgDeath:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bgDeath:SetVertexColor(0, 0, 0, 0.5)
    
    randomDeathEdit:SetScript("OnTextChanged", function(self)
        DeathLoggerDB.randomPhrasesDeath = self:GetText() or ""
    end)
    randomDeathEdit:SetScript("OnEscapePressed", function(self) 
        self:ClearFocus() 
    end)
    
    local randomCompletedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    randomCompletedLabel:SetPoint("TOPLEFT", randomDeathEdit, "BOTTOMLEFT", 0, -20)
    randomCompletedLabel:SetText("Случайная для завершивших:")
    
    local randomCompletedEdit = CreateFrame("EditBox", nil, content)
    randomCompletedEdit:SetPoint("TOPLEFT", randomCompletedLabel, "BOTTOMLEFT", 0, -10)
    randomCompletedEdit:SetSize(200, 60)
    randomCompletedEdit:SetMultiLine(true)
    randomCompletedEdit:SetAutoFocus(false)
    randomCompletedEdit:SetFontObject(GameFontHighlight)
    randomCompletedEdit:SetTextInsets(5, 5, 5, 5)
    randomCompletedEdit:SetMaxLetters(500)
    
    local bgCompleted = randomCompletedEdit:CreateTexture(nil, "BACKGROUND")
    bgCompleted:SetAllPoints(randomCompletedEdit)
    bgCompleted:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bgCompleted:SetVertexColor(0, 0, 0, 0.5)
    
    randomCompletedEdit:SetScript("OnTextChanged", function(self)
        DeathLoggerDB.randomPhrasesCompleted = self:GetText() or ""
    end)
    randomCompletedEdit:SetScript("OnEscapePressed", function(self) 
        self:ClearFocus() 
    end)
    
    local function UpdateSyncDependentControls()
        local syncEnabled = DeathLoggerDB.syncEnabled or false
        
        if not syncEnabled then
            autoSyncCheckbox:SetEnabled(false)
            autoSyncCheckbox:SetAlpha(0.5)
            notifyCheckbox:SetEnabled(false)
            notifyCheckbox:SetAlpha(0.5)
            syncButton:SetEnabled(false)
            syncButton:SetAlpha(0.5)
        else
            autoSyncCheckbox:SetEnabled(true)
            autoSyncCheckbox:SetAlpha(1)
            notifyCheckbox:SetEnabled(true)
            notifyCheckbox:SetAlpha(1)
            syncButton:SetEnabled(true)
            syncButton:SetAlpha(1)
        end
    end
    
    local function UpdateRandomPhrasesControls()
        local useRandomPhrases = DeathLoggerDB.useRandomPhrases or false
        
        if useRandomPhrases then
            completedEdit:SetEnabled(false)
            completedEdit:SetAlpha(0.5)
            deathEdit:SetEnabled(false)
            deathEdit:SetAlpha(0.5)
            randomCompletedEdit:SetEnabled(true)
            randomCompletedEdit:SetAlpha(1)
            randomDeathEdit:SetEnabled(true)
            randomDeathEdit:SetAlpha(1)
        else
            completedEdit:SetEnabled(true)
            completedEdit:SetAlpha(1)
            deathEdit:SetEnabled(true)
            deathEdit:SetAlpha(1)
            randomCompletedEdit:SetEnabled(false)
            randomCompletedEdit:SetAlpha(0.5)
            randomDeathEdit:SetEnabled(false)
            randomDeathEdit:SetAlpha(0.5)
        end
    end
    
    syncCheckbox:SetScript("OnClick", function(self)
        DeathLoggerDB.syncEnabled = self:GetChecked() or false
        UpdateSyncDependentControls()
        print("Синхронизация: " .. (DeathLoggerDB.syncEnabled and "|cff00ff00ВКЛ|r" or "|cffff0000ВЫКЛ|r"))
    end)
    
    autoSyncCheckbox:SetScript("OnClick", function(self)
        if DeathLoggerDB.syncEnabled then
            DeathLoggerDB.autoSync = self:GetChecked() or false
            print("Автосинхронизация: " .. (DeathLoggerDB.autoSync and "|cff00ff00ВКЛ|r" or "|cffff0000ВЫКЛ|r"))
        else
            autoSyncCheckbox:SetChecked(DeathLoggerDB.autoSync or false)
        end
    end)
    
    notifyCheckbox:SetScript("OnClick", function(self)
        if DeathLoggerDB.syncEnabled then
            DeathLoggerDB.syncNotifications = self:GetChecked() or false
            print("Уведомления: " .. (DeathLoggerDB.syncNotifications and "|cff00ff00ВКЛ|r" or "|cffff0000ВЫКЛ|r"))
        else
            notifyCheckbox:SetChecked(DeathLoggerDB.syncNotifications ~= false)
        end
    end)
    
    randomPhrasesCheckbox:SetScript("OnClick", function(self)
        DeathLoggerDB.useRandomPhrases = self:GetChecked() or false
        UpdateRandomPhrasesControls()
        print("Случайные фразы: " .. (DeathLoggerDB.useRandomPhrases and "|cff00ff00ВКЛ|r" or "|cffff0000ВЫКЛ|r"))
    end)
    
    local function UpdateSyncTab()
        syncCheckbox:SetChecked(DeathLoggerDB.syncEnabled or false)
        autoSyncCheckbox:SetChecked(DeathLoggerDB.autoSync or false)
        notifyCheckbox:SetChecked(DeathLoggerDB.syncNotifications ~= false)
        randomPhrasesCheckbox:SetChecked(DeathLoggerDB.useRandomPhrases or false)
        
        completedEdit:SetText(DeathLoggerDB.guildChatTextCompleted or defaults.guildChatTextCompleted)
        deathEdit:SetText(DeathLoggerDB.guildChatTextDeath or defaults.guildChatTextDeath)
        randomCompletedEdit:SetText(DeathLoggerDB.randomPhrasesCompleted or "")
        randomDeathEdit:SetText(DeathLoggerDB.randomPhrasesDeath or "")
        
        UpdateSyncDependentControls()
        UpdateRandomPhrasesControls()
    end
    
    tab.elements = {
        syncCheckbox = syncCheckbox,
        autoSyncCheckbox = autoSyncCheckbox,
        notifyCheckbox = notifyCheckbox,
        syncButton = syncButton,
        randomPhrasesCheckbox = randomPhrasesCheckbox,
        completedEdit = completedEdit,
        deathEdit = deathEdit,
        randomCompletedEdit = randomCompletedEdit,
        randomDeathEdit = randomDeathEdit
    }
    
    tab.updateFunction = UpdateSyncTab
    
    UpdateSyncTab()
end

-- Инит панели
function CreateOptionsPanel()
    if _G.DeathLoggerOptionsPanel then
        return _G.DeathLoggerOptionsPanel
    end
    
    local panel = CreateFrame("Frame", "DeathLoggerOptionsPanel", UIParent)
    panel.name = "DeathLogger"
    panel:Hide()
    
    local titleFrame = CreateFrame("Frame", nil, panel)
    titleFrame:SetSize(300, 30)
    titleFrame:SetPoint("TOPLEFT", 16, -16)
    
    local skullIcon = titleFrame:CreateTexture(nil, "OVERLAY")
    skullIcon:SetSize(24, 24)
    skullIcon:SetPoint("LEFT", titleFrame, "LEFT", 0, 0)
    skullIcon:SetTexture(_G.deathIcons[7])
    
    local title = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", skullIcon, "RIGHT", 8, 0)
    title:SetText("DeathLogger - Настройки")
    
    local tabs, contentFrame = CreateTabSystem(panel)
    
    local generalTab = tabs.CreateTab("general", "Основные")
    local bannerTab = tabs.CreateTab("banner", "Баннер")
    local syncTab = tabs.CreateTab("sync", "Синхронизация")
    
    CreateGeneralTab(generalTab)
    CreateBannerTab(bannerTab)
    CreateSyncTab(syncTab)
    
    tabs.Initialize()
    
    panel:SetScript("OnShow", function()
        isConfigOpen = true
        _G.isConfigOpen = true
        HCBL_Settings.moveOriginal = true
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        SetupOriginalBanner()
    end)
    
    panel:SetScript("OnHide", function()
        isConfigOpen = false
        _G.isConfigOpen = false
        HCBL_Settings.moveOriginal = false
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        SetupOriginalBanner()
    end)
    
    InterfaceOptions_AddCategory(panel)
    
    return panel
end

-- Инит настроек
local function InitializeOptions()
    if not DeathLoggerDB then
        DeathLoggerDB = {}
    end
    
    if not DeathLoggerDB.HCBL_Settings then
        DeathLoggerDB.HCBL_Settings = {}
    end
    
    if DeathLoggerDB.syncEnabled == nil then
        DeathLoggerDB.syncEnabled = true
    end
    if DeathLoggerDB.autoSync == nil then
        DeathLoggerDB.autoSync = true
    end
    if DeathLoggerDB.syncNotifications == nil then
        DeathLoggerDB.syncNotifications = true
    end
    if DeathLoggerDB.useRandomPhrases == nil then
        DeathLoggerDB.useRandomPhrases = false
    end
    if DeathLoggerDB.randomPhrasesCompleted == nil then
        DeathLoggerDB.randomPhrasesCompleted = ""
    end
    if DeathLoggerDB.randomPhrasesDeath == nil then
        DeathLoggerDB.randomPhrasesDeath = ""
    end
    
    HCBL_Settings = DeathLoggerDB.HCBL_Settings
    
    for k, v in pairs(defaults) do
        if HCBL_Settings[k] == nil then
            HCBL_Settings[k] = v
        end
    end
    
    CreateOptionsPanel()
    
    SetupOriginalBanner()
end

InitializeOptions()

_G.DeathLogger_Options = {
    defaults = defaults,
    UpdateBannerElements = UpdateBannerElements,
    UpdateBannerPosition = UpdateBannerPosition,
    SetupOriginalBanner = SetupOriginalBanner,
    CreateOptionsPanel = CreateOptionsPanel,
    HCBL_Settings = HCBL_Settings
}