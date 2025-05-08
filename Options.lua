-------------------------------------------------------------------------------------------------
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
    dl_ver = 1.481
}

local isConfigOpen = false
_G.isConfigOpen = isConfigOpen

local function UpdateBannerElements()
    HCBL_Settings = HCBL_Settings or {}
    if not (HardcoreLossBanner and HardcoreLossBanner.Title) then
        return
    end

    if HCBL_Settings.hideOriginal then
        HardcoreLossBanner:Hide()
        return -- Прекращаем дальнейшие обновления, если баннер скрыт
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
	-- local icon  = _G.deathIcons[causeID] or defaults.currentDeathIcon

    if icon ~= "" and not HCBL_Settings.hideSkullCircle then
        HardcoreLossBanner.CustomDeathIcon:SetTexture(icon)
        HardcoreLossBanner.CustomDeathIcon:Show()
        HardcoreLossBanner.SkullCircle:SetAlpha(0)
        -- print("Иконка установлена:", icon)
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

    if HardcoreLossBanner then
        UpdateBannerPosition()
        SetupBannerMovement(HardcoreLossBanner)
        UpdateBannerElements()

        -- Основная проверка: если hideOriginal активен, баннер всегда скрыт
        if HCBL_Settings.hideOriginal then
            HardcoreLossBanner:Hide()
            HCBL_Settings.moveOriginal = false
            if positionCheckbox then 
                positionCheckbox:SetChecked(false)
            end
        else
            -- В противном случае, видимость зависит от moveOriginal и isConfigOpen
            HardcoreLossBanner:SetShown(isConfigOpen and HCBL_Settings.moveOriginal)
        end
    end
end

local function CreateOptionsPanel()
	local panel = CreateFrame("Frame")
	panel.name = addonName
    panel:SetSize(600, 500)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(addonName)

    local mainContainer = CreateFrame("Frame", nil, panel)
    mainContainer:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -30)
    mainContainer:SetPoint("BOTTOMRIGHT", panel, -16, 16)
	
	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()
	local maxWidth = screenWidth * 0.45
	local maxHeight = screenHeight * 0.70
	local minWidthLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minWidthLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
	minWidthLabel:SetText("Минимальная ширина (в % от экрана):")

	local minWidthSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
	minWidthSlider:SetPoint("TOPLEFT", minWidthLabel, "BOTTOMLEFT", 0, -10)
	minWidthSlider:SetWidth(200)
	minWidthSlider:SetMinMaxValues(10, 45)
	minWidthSlider:SetValueStep(1)
	minWidthSlider:SetValue((DeathLoggerDB.minWidth or 200) / screenWidth * 100)
	minWidthSlider.tooltipText = "Установите минимальную ширину окна в процентах от ширины экрана (макс. 45%)"
	minWidthSlider.Low:SetText("10%")
	minWidthSlider.High:SetText("45%")
	minWidthSlider.Text = minWidthSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minWidthSlider.Text:SetPoint("TOP", minWidthSlider, "BOTTOM", 0, -5)
	minWidthSlider.Text:SetText(math.floor((DeathLoggerDB.minWidth or 100) / screenWidth * 100) .. "%")
	minWidthSlider:SetScript("OnValueChanged", function(self, value)
		local screenWidth = GetScreenWidth()
		local percent = math.floor(value)
		self.Text:SetText(percent .. "%")
		DeathLoggerDB.minWidth = math.max(100, math.min(screenWidth * percent / 100, screenWidth * 0.45))
		DeathLoggerDB.width = DeathLoggerDB.minWidth
		if widgetInstance and widgetInstance.mainWnd then
			widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
			widgetInstance.mainWnd:SetMaxResize(maxWidth, maxHeight)
			local currentWidth, currentHeight = widgetInstance.mainWnd:GetSize()
			widgetInstance.mainWnd:SetWidth(math.min(DeathLoggerDB.minWidth, maxWidth))
		end
		widgetInstance.mainWnd:SetMinResize(DeathLoggerDB.minWidth, DeathLoggerDB.minHeight)
	end)

	local minHeightLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	minHeightLabel:SetPoint("LEFT", minWidthLabel, "RIGHT", 50, 0)
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
	guildOnlyCheckbox:SetPoint("TOPLEFT", minWidthSlider, "BOTTOMLEFT", 0, -30)
	guildOnlyCheckbox.text:SetText("Показывать только гильдейские смерти")
	guildOnlyCheckbox:SetChecked(DeathLoggerDB.guildOnly or false)
	guildOnlyCheckbox:SetScript("OnClick", function(self)
		DeathLoggerDB.guildOnly = self:GetChecked()
		if widgetInstance then
			widgetInstance:ApplyFilter(function(entry) return true end)
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

    local container = CreateFrame("Frame", nil, panel)
    container:SetPoint("TOPLEFT", guildOnlyCheckbox, "BOTTOMLEFT", 0, -20)
    container:SetPoint("BOTTOMRIGHT", panel, -16, 16)

    -- Чекбокс спрятать оригинальный баннер
    local hideCheckbox = CreateFrame("CheckButton", nil, container, "OptionsCheckButtonTemplate")
    hideCheckbox:SetPoint("TOPLEFT", 20, -20)
    hideCheckbox:SetSize(24, 24)
    hideCheckbox.text = hideCheckbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hideCheckbox.text:SetPoint("LEFT", hideCheckbox, "RIGHT", 5, 0)
    hideCheckbox.text:SetText("Убрать оригинальный баннер")
    hideCheckbox:SetChecked(HCBL_Settings.hideOriginal)
hideCheckbox:SetScript("OnClick", function(self)
    HCBL_Settings.hideOriginal = self:GetChecked()
    DeathLoggerDB.HCBL_Settings = HCBL_Settings
    -- Принудительно скрываем/показываем баннер
    if HCBL_Settings.hideOriginal then
        HardcoreLossBanner:Hide()
    else
        HardcoreLossBanner:Show()
    end
    SetupOriginalBanner()
end)

    -- Чекбокс позиционирования
    local positionCheckbox = CreateFrame("CheckButton", nil, container, "OptionsCheckButtonTemplate")
    positionCheckbox:SetPoint("TOPLEFT", hideCheckbox, "BOTTOMLEFT", 0, -30)
    positionCheckbox:SetSize(24, 24)
    positionCheckbox.text = positionCheckbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    positionCheckbox.text:SetPoint("LEFT", positionCheckbox, "RIGHT", 5, 0)
    positionCheckbox.text:SetText("Разрешить перемещение баннера")
    positionCheckbox:SetChecked(HCBL_Settings.moveOriginal)
positionCheckbox:SetScript("OnClick", function(self)
    if HCBL_Settings.hideOriginal then 
        self:SetChecked(false)
        return 
    end
    HCBL_Settings.moveOriginal = self:GetChecked()
    DeathLoggerDB.HCBL_Settings = HCBL_Settings
    SetupOriginalBanner()
end)

	-- Кнопка черепа
    local skullCheckbox = CreateFrame("CheckButton", nil, container, "OptionsCheckButtonTemplate")
    skullCheckbox:SetPoint("LEFT", hideCheckbox, "RIGHT", 250, 0)
    skullCheckbox:SetSize(24, 24)
    skullCheckbox.text = skullCheckbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    skullCheckbox.text:SetPoint("LEFT", skullCheckbox, "RIGHT", 5, 0)
    skullCheckbox.text:SetText("Стандартный череп")
    skullCheckbox:SetChecked(HCBL_Settings.hideSkullCircle)
    skullCheckbox:SetScript("OnClick", function(self)
        HCBL_Settings.hideSkullCircle = self:GetChecked()
	    DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateBannerElements()
    end)

    -- Кнопка сброса позиции
    local resetButton = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    resetButton:SetPoint("TOPLEFT", skullCheckbox, "BOTTOMLEFT", 0, -30)
    resetButton:SetSize(140, 25)
    resetButton:SetText("Сбросить позицию")
    resetButton:SetScript("OnClick", function()
        HCBL_Settings.origOffsetX = defaults.origOffsetX
        HCBL_Settings.origOffsetY = defaults.origOffsetY
	    DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateBannerPosition()
    end)

	-- Шрифт
    local fontDropdown = CreateFrame("Frame", "HCBLFontDropdown", container, "UIDropDownMenuTemplate")
	fontDropdown:SetParent(panel)
    fontDropdown:SetPoint("TOPLEFT", positionCheckbox, "BOTTOMLEFT", -10, -30)
    UIDropDownMenu_SetWidth(fontDropdown, 150)
	UIDropDownMenu_SetText(fontDropdown, "Шрифт: "..(HCBL_Settings.fontName or defaults.fontName))
	UIDropDownMenu_Initialize(fontDropdown, FontDropdown_Initialize)

    local function FontDropdown_Initialize()
        local fonts = {"FRIZQT__", "ARIALN", "MORPHEUS", "SKURRI", "FRIENDS", "NIM_____"}
        for _, font in ipairs(fonts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = font
            info.func = function()
                HCBL_Settings.fontName = font
			    DeathLoggerDB.HCBL_Settings = HCBL_Settings
                UIDropDownMenu_SetText(fontDropdown, "Шрифт: "..font)
                UpdateBannerElements()
            end
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(fontDropdown, FontDropdown_Initialize)

	-- Стиль контура
	local outlineDropdown = CreateFrame("Frame", "HCBLOutlineDropdown", container, "UIDropDownMenuTemplate")
	outlineDropdown:SetParent(panel)
	outlineDropdown:SetPoint("LEFT", fontDropdown, "RIGHT", 130, 0)
	UIDropDownMenu_SetWidth(outlineDropdown, 150)
	UIDropDownMenu_SetText(outlineDropdown, "Контур: "..(HCBL_Settings.fontOutline or defaults.fontOutline))

	local function OutlineDropdown_Initialize()
		local outlines = {"NONE", "OUTLINE", "THICKOUTLINE"}
		for _, outline in ipairs(outlines) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = outline
			info.func = function()
				HCBL_Settings.fontOutline = outline
				UIDropDownMenu_SetText(outlineDropdown, "Контур: "..outline)
				    DeathLoggerDB.HCBL_Settings = HCBL_Settings

				UpdateBannerElements()
			end
			UIDropDownMenu_AddButton(info)
		end
	end	
	UIDropDownMenu_Initialize(outlineDropdown, OutlineDropdown_Initialize)
	
    -- Выбор цвета
    local colorButton = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    colorButton:SetPoint("TOPLEFT", fontDropdown, "BOTTOMLEFT", 15, -30)
    colorButton:SetSize(120, 25)
    colorButton:SetText("Цвет текста")
    colorButton:SetScript("OnClick", function()
        ColorPickerFrame:SetColorRGB(HCBL_Settings.fontColor.r, HCBL_Settings.fontColor.g, HCBL_Settings.fontColor.b)
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = HCBL_Settings.fontColor.a
        ColorPickerFrame.func = function()
            HCBL_Settings.fontColor.r, HCBL_Settings.fontColor.g, HCBL_Settings.fontColor.b = ColorPickerFrame:GetColorRGB()
            HCBL_Settings.fontColor.a = OpacitySliderFrame:GetValue()
			    DeathLoggerDB.HCBL_Settings = HCBL_Settings

            UpdateBannerElements()
        end
        ColorPickerFrame:Show()
    end)

    -- Тень текста
    local shadowCheckbox = CreateFrame("CheckButton", nil, container, "OptionsCheckButtonTemplate")
    shadowCheckbox:SetPoint("LEFT", colorButton, "RIGHT", 35, 0)
    shadowCheckbox:SetSize(24, 24)
    shadowCheckbox.text = shadowCheckbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    shadowCheckbox.text:SetPoint("LEFT", shadowCheckbox, "RIGHT", 5, 0)
    shadowCheckbox.text:SetText("Тень текста")
    shadowCheckbox:SetChecked(HCBL_Settings.fontShadow)
    shadowCheckbox:SetScript("OnClick", function(self)
        HCBL_Settings.fontShadow = self:GetChecked()
	    DeathLoggerDB.HCBL_Settings = HCBL_Settings
        UpdateBannerElements()
    end)
	
	-- Масштаб
    local scaleSlider = CreateFrame("Slider", "HCBLScaleSlider", container, "OptionsSliderTemplate")
    scaleSlider:SetPoint("LEFT", shadowCheckbox, "RIGHT", 115, 0)
    scaleSlider:SetWidth(200)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.1)
    scaleSlider:SetValue(HCBL_Settings.scaleFactor or 1.0)
    scaleSlider.Text = scaleSlider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scaleSlider.Text:SetPoint("BOTTOM", scaleSlider, "TOP", 0, 2)
    scaleSlider.Text:SetText(string.format("Размер: %.1f", HCBL_Settings.scaleFactor or 1.0))
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        HCBL_Settings.scaleFactor = math.floor(value * 10) / 10
        DeathLoggerDB.HCBL_Settings = HCBL_Settings
        self.Text:SetText(string.format("Размер: %.1f", HCBL_Settings.scaleFactor))
        UpdateBannerElements()
    end)

	-- Баннер скрывается при закрытии панели
	panel:SetScript("OnShow", function()
		isConfigOpen = true
		HCBL_Settings = DeathLoggerDB.HCBL_Settings
		guildOnlyCheckbox:SetChecked(DeathLoggerDB.guildOnly)
		hideCheckbox:SetChecked(HCBL_Settings.hideOriginal)
		positionCheckbox:SetChecked(HCBL_Settings.moveOriginal)
		skullCheckbox:SetChecked(HCBL_Settings.hideSkullCircle)
		UIDropDownMenu_SetText(fontDropdown, "Шрифт: "..HCBL_Settings.fontName)
	    shadowCheckbox:SetChecked(HCBL_Settings.fontShadow)
		UIDropDownMenu_SetText(outlineDropdown, "Контур: "..HCBL_Settings.fontOutline)
		scaleSlider:SetValue(HCBL_Settings.scaleFactor)
    	SetupOriginalBanner()
	end)
    
panel:SetScript("OnHide", function()
    isConfigOpen = false
    HCBL_Settings.showOriginalForPositioning = false

    -- Принудительно скрываем баннер, если опция hideOriginal активна
    if HCBL_Settings.hideOriginal then
        HardcoreLossBanner:Hide()
    end

    SetupOriginalBanner()
    CloseDropDownMenus()

    if UIDROPDOWNMENU_OPEN_MENU then
        if UIDROPDOWNMENU_OPEN_MENU == HCBLFontDropdown or 
           UIDROPDOWNMENU_OPEN_MENU == HCBLOutlineDropdown then
            CloseDropDownMenus()
        end
    end
end)

	InterfaceOptions_AddCategory(panel)
end

_G.DeathLogger_Options = {
	defaults = defaults,
    UpdateBannerElements = UpdateBannerElements,
    UpdateBannerPosition = UpdateBannerPosition,
    SetupOriginalBanner = SetupOriginalBanner,
    CreateOptionsPanel = CreateOptionsPanel,
    HCBL_Settings = HCBL_Settings
}