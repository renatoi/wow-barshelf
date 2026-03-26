local _, Barshelf = ...

---------------------------------------------------------------------------
-- Minimap icon via LibDataBroker + LibDBIcon
---------------------------------------------------------------------------
function Barshelf:SetupMinimapIcon()
    local LDB  = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBI then return end

    local dataObj = LDB:NewDataObject("Barshelf", {
        type = "data source",
        text = "Barshelf",
        icon = "Interface\\Icons\\INV_Misc_Bag_07",
        OnClick = function(_, button)
            if button == "LeftButton" then
                Barshelf:ToggleConfig()
            end
        end,
        OnTooltipShow = function(tip)
            tip:AddLine("Barshelf", 1, 1, 1)
            tip:AddLine("Left-click to open settings", 0.7, 0.7, 0.7)
        end,
    })

    if dataObj then
        LDBI:Register("Barshelf", dataObj, self.db.minimap)
        if self.db.showMinimap == false then
            LDBI:Hide("Barshelf")
        end
    end
end

---------------------------------------------------------------------------
-- Debounced rebuild (prevents slider spam rebuilding everything)
---------------------------------------------------------------------------
local rebuildPending = false
local function DebouncedRebuild()
    if rebuildPending then return end
    rebuildPending = true
    C_Timer.After(0.15, function()
        rebuildPending = false
        if not InCombatLockdown() then
            Barshelf:RebuildAll()
        end
    end)
end

---------------------------------------------------------------------------
-- Expansion state (separate from saved variables)
---------------------------------------------------------------------------
local expandedState = {}
local layoutExpandedState = {}

---------------------------------------------------------------------------
-- Reusable dropdown menu frame
---------------------------------------------------------------------------
local dropdownFrame

local function ShowDropdown(anchorFrame, options, onChange)
    if dropdownFrame then dropdownFrame:Hide() end

    dropdownFrame = dropdownFrame or CreateFrame("Frame", "BarshelfDropdownMenu", UIParent, "BackdropTemplate")
    local mf = dropdownFrame
    mf:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    mf:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    mf:SetFrameStrata("TOOLTIP")
    mf:ClearAllPoints()
    mf:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    mf:SetSize(180, #options * 22 + 8)

    -- Remove old children
    for _, child in pairs({mf:GetChildren()}) do child:Hide() end

    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, mf)
        item:SetSize(174, 20)
        item:SetPoint("TOPLEFT", 3, -(3 + (i - 1) * 22))
        item:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        local txt = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 4, 0)
        txt:SetText(opt.text)
        item:SetScript("OnClick", function()
            onChange(opt.value, opt.text)
            mf:Hide()
        end)
        item:Show()
    end

    mf:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() and IsMouseButtonDown() then
            self:Hide()
        end
    end)
    mf:Show()
end

---------------------------------------------------------------------------
-- UI control factories (using templates that exist in 12.0.1)
---------------------------------------------------------------------------
local function CreateSection(parent, titleText, yOffset)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, yOffset)
    title:SetText(titleText)
    return title, yOffset - 22
end

local function CreateCheckbox(parent, x, y, labelText, checked, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    -- Modern WoW uses .Text (capital T) on UICheckButtonTemplate
    local textFS = cb.Text or cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textFS:ClearAllPoints()
    textFS:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    textFS:SetText(labelText)
    cb:SetChecked(checked)
    cb:SetScript("OnClick", function(frame)
        onChange(frame:GetChecked())
    end)
    return cb, y - 28
end

local function CreateSlider(parent, x, y, labelText, minVal, maxVal, step, value, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)
    container:SetPoint("TOPLEFT", x, y)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, 0)

    -- Build slider manually (OptionsSliderTemplate was removed in 10.0)
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", 0, -16)
    slider:SetSize(180, 16)
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        edgeSize = 8, tile = true, tileSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(value or minVal)
    slider:EnableMouseWheel(true)

    -- Min/max labels
    local low = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
    low:SetText(tostring(minVal))

    local high = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
    high:SetText(tostring(maxVal))

    local function refresh(v)
        lbl:SetText(labelText .. ": |cffffffff" .. tostring(v) .. "|r")
    end
    refresh(value or minVal)

    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        refresh(v)
        onChange(v)
    end)

    slider:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetValue()
        self:SetValue(cur + delta * step)
    end)

    return container, y - 48
end

local function CreateEditBox(parent, x, y, labelText, text, width, onChange)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(labelText)

    -- InputBoxTemplate removed in 10.0; build manually
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetPoint("TOPLEFT", x + 2, y - 16)
    eb:SetSize(width or 180, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")
    eb:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, tile = true, tileSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    eb:SetBackdropColor(0, 0, 0, 0.5)
    eb:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    eb:SetTextInsets(4, 4, 0, 0)
    eb:SetText(text or "")
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        onChange(self:GetText())
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    return eb, y - 44
end

local function CreateDropdownButton(parent, x, y, labelText, options, selected, onChange)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(labelText)

    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y - 16)
    btn:SetSize(180, 24)
    btn:SetText(selected or "Select...")

    btn:SetScript("OnClick", function(self)
        ShowDropdown(self, options, function(value, text)
            btn:SetText(text)
            onChange(value)
        end)
    end)

    return btn, y - 46
end

---------------------------------------------------------------------------
-- Main config frame
---------------------------------------------------------------------------
local CONFIG_WIDTH, CONFIG_HEIGHT = 640, 540

function Barshelf:CreateConfigFrame()
    if self.configFrame then return self.configFrame end

    local f = CreateFrame("Frame", "BarshelfConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(CONFIG_WIDTH, CONFIG_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Barshelf Settings")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -36)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(CONFIG_WIDTH - 50, 1) -- height set dynamically
    scrollFrame:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    -- ESC to close
    tinsert(UISpecialFrames, "BarshelfConfigFrame")

    self.configFrame = f
    self:PopulateConfig(f)
    return f
end

---------------------------------------------------------------------------
-- Populate the config panel
---------------------------------------------------------------------------
function Barshelf:PopulateConfig(f)
    local parent = f.scrollChild
    if not parent then return end

    -- Hide all old children to avoid leaks
    for _, child in pairs({parent:GetChildren()}) do
        child:Hide()
        child:ClearAllPoints()
        child:SetParent(nil)
    end
    -- Also hide old font strings / textures (prevents text overlap on refresh)
    for _, region in pairs({parent:GetRegions()}) do
        region:Hide()
    end

    local y = 0

    -----------------------------------------------------------------
    -- Global settings
    -----------------------------------------------------------------
    local _, ny = CreateSection(parent, "Global", y)
    y = ny

    _, y = CreateCheckbox(parent, 16, y, "Close other popups when opening one",
        self.db.closeOthers,
        function(v) self.db.closeOthers = v; self:UpdateAllSecureRefs() end)

    _, y = CreateCheckbox(parent, 16, y, "Animate popups (fade in)",
        self.db.animatePopups,
        function(v) self.db.animatePopups = v end)

    _, y = CreateCheckbox(parent, 16, y, "Show minimap icon",
        self.db.showMinimap ~= false,
        function(v)
            self.db.showMinimap = v
            self.db.minimap.hide = not v
            local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
            if LDBI then
                if v then LDBI:Show("Barshelf") else LDBI:Hide("Barshelf") end
            end
        end)

    y = y - 12

    -----------------------------------------------------------------
    -- Dock & Handle appearance
    -----------------------------------------------------------------
    local _, ny2 = CreateSection(parent, "Appearance", y)
    y = ny2

    _, y = CreateSlider(parent, 16, y, "Dock Background Opacity",
        0, 100, 5, (self.db.dockBgAlpha or 0.75) * 100,
        function(v)
            self.db.dockBgAlpha = v / 100
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Dock Border Opacity",
        0, 100, 5, (self.db.dockBorderAlpha or 0.8) * 100,
        function(v)
            self.db.dockBorderAlpha = v / 100
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Shelf Background Opacity",
        0, 100, 5, (self.db.popupBgAlpha or 0.92) * 100,
        function(v)
            self.db.popupBgAlpha = v / 100
            DebouncedRebuild()
        end)

    _, y = CreateCheckbox(parent, 16, y, "Show dock border",
        self.db.dockShowBorder ~= false,
        function(v) self.db.dockShowBorder = v; DebouncedRebuild() end)

    _, y = CreateSlider(parent, 16, y, "Handle Background Opacity",
        0, 100, 5, (self.db.handleBgAlpha or 0.85) * 100,
        function(v)
            self.db.handleBgAlpha = v / 100
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Dock Padding",
        0, 12, 1, self.db.dockPadding or 4,
        function(v)
            self.db.dockPadding = v
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Handle Icon Size",
        10, 32, 1, self.db.handleIconSize or 16,
        function(v)
            self.db.handleIconSize = v
            for _, cfg in ipairs(self.db.shelves) do cfg.iconSize = v end
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Handle Font Size",
        8, 18, 1, self.db.handleFontSize or 12,
        function(v)
            self.db.handleFontSize = v
            for _, cfg in ipairs(self.db.shelves) do cfg.labelFontSize = v end
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Bar Icon Size",
        20, 56, 2, self.db.barIconSize or 36,
        function(v)
            self.db.barIconSize = v
            for _, cfg in ipairs(self.db.shelves) do
                if cfg.type == "bar" then cfg.buttonSize = v end
            end
            DebouncedRebuild()
        end)

    _, y = CreateSlider(parent, 16, y, "Bar Icon Padding",
        0, 12, 1, self.db.barIconPadding or 2,
        function(v)
            self.db.barIconPadding = v
            for _, cfg in ipairs(self.db.shelves) do
                if cfg.type == "bar" then cfg.buttonPadding = v end
            end
            DebouncedRebuild()
        end)

    local rowOrderOpts = {
        { text = "Auto (Blizzard)", value = "auto" },
        { text = "Top to Bottom",   value = "topdown" },
        { text = "Bottom to Top",   value = "bottomup" },
    }
    local rowOrderNames = { auto = "Auto (Blizzard)", topdown = "Top to Bottom", bottomup = "Bottom to Top" }
    _, y = CreateDropdownButton(parent, 16, y, "Bar Row Order",
        rowOrderOpts, rowOrderNames[self.db.barRowOrder] or "Auto (Blizzard)",
        function(v)
            self.db.barRowOrder = v
            DebouncedRebuild()
        end)

    y = y - 8

    -----------------------------------------------------------------
    -- Shelves (most commonly used section, shown before Docks)
    -----------------------------------------------------------------
    _, ny = CreateSection(parent, "Shelves", y)
    y = ny

    if #self.db.shelves == 0 then
        local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        hint:SetPoint("TOPLEFT", 20, y)
        hint:SetText("No shelves yet. Add one below.")
        y = y - 20
    end

    for si, shelfCfg in ipairs(self.db.shelves) do
        y = self:CreateShelfConfigRow(parent, si, shelfCfg, y)
    end

    y = y - 6

    -- Add buttons
    local addBarBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBarBtn:SetSize(130, 22)
    addBarBtn:SetPoint("TOPLEFT", 20, y)
    addBarBtn:SetText("+ Add Bar Shelf")
    addBarBtn:SetScript("OnClick", function()
        local used = {}
        for _, cfg in ipairs(self.db.shelves) do
            if cfg.type == "bar" and cfg.enabled then used[cfg.barID] = true end
        end
        local barID
        for id = 1, 8 do
            if not used[id] then barID = id; break end
        end
        if not barID then
            print("|cff00ccffBarshelf:|r All bars (1-8) are already assigned.")
            return
        end
        self:AddBarShelf(barID)
        self:RefreshConfig()
    end)

    local addCustBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addCustBtn:SetSize(140, 22)
    addCustBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 8, 0)
    addCustBtn:SetText("+ Add Custom Shelf")
    addCustBtn:SetScript("OnClick", function()
        self:AddCustomShelf("Custom")
        self:RefreshConfig()
    end)

    y = y - 30

    -----------------------------------------------------------------
    -- Docks
    -----------------------------------------------------------------
    _, ny = CreateSection(parent, "Docks", y)
    y = ny

    local dockHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dockHint:SetPoint("TOPLEFT", 20, y)
    dockHint:SetText("Drag the dotted grip on each dock to reposition it.")
    y = y - 16

    for _, dockCfg in ipairs(self.db.docks) do
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(CONFIG_WIDTH - 60, 24)
        row:SetPoint("TOPLEFT", 20, y)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(dockCfg.name or ("Dock " .. dockCfg.id))

        local orient = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        orient:SetSize(60, 20)
        orient:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
        orient:SetText(dockCfg.orientation == "VERTICAL" and "Vertical" or "Horizontal")
        orient:SetScript("OnClick", function()
            dockCfg.orientation = dockCfg.orientation == "VERTICAL" and "HORIZONTAL" or "VERTICAL"
            orient:SetText(dockCfg.orientation == "VERTICAL" and "Vertical" or "Horizontal")
            self:RebuildAll()
        end)

        if dockCfg.id ~= 1 then
            local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            del:SetSize(22, 20)
            del:SetPoint("LEFT", orient, "RIGHT", 4, 0)
            del:SetText("X")
            del:SetScript("OnClick", function()
                self:RemoveDock(dockCfg.id)
                self:RefreshConfig()
            end)
        end

        y = y - 26
    end

    local addDock = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addDock:SetSize(100, 22)
    addDock:SetPoint("TOPLEFT", 20, y)
    addDock:SetText("+ Add Dock")
    addDock:SetScript("OnClick", function()
        self:AddDock()
        self:RefreshConfig()
    end)
    y = y - 30

    -- Set scroll child height to actual content height
    parent:SetHeight(math.abs(y) + 20)
end

---------------------------------------------------------------------------
-- Per-shelf config row (expandable)
---------------------------------------------------------------------------
function Barshelf:CreateShelfConfigRow(parent, index, config, y)
    local ROW_LEFT = 20

    -- Header row
    local hdr = CreateFrame("Frame", nil, parent)
    hdr:SetSize(CONFIG_WIDTH - 60, 26)
    hdr:SetPoint("TOPLEFT", ROW_LEFT, y)

    local bg = hdr:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)

    -- Expand toggle
    local expand = CreateFrame("Button", nil, hdr)
    expand:SetSize(20, 20)
    expand:SetPoint("LEFT", 2, 0)
    local expandText = expand:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    expandText:SetPoint("CENTER")
    expandText:SetText(expandedState[index] and "v" or ">")

    -- Type badge
    local typeLabel = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    typeLabel:SetPoint("LEFT", expand, "RIGHT", 4, 0)
    if config.type == "bar" then
        typeLabel:SetText("|cff88ccff[Bar " .. (config.barID or "?") .. "]|r")
    else
        typeLabel:SetText("|cffcccc88[Custom]|r")
    end

    -- Label
    local label = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", typeLabel, "RIGHT", 6, 0)
    label:SetText(config.label or "Unnamed")

    -- Enable toggle
    local enable = CreateFrame("CheckButton", nil, hdr, "UICheckButtonTemplate")
    enable:SetPoint("RIGHT", hdr, "RIGHT", -26, 0)
    enable:SetSize(22, 22)
    enable:SetChecked(config.enabled)
    enable:SetScript("OnClick", function(frame)
        config.enabled = frame:GetChecked()
        Barshelf:RebuildAll()
    end)

    -- Delete
    local del = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    del:SetSize(22, 20)
    del:SetPoint("RIGHT", enable, "LEFT", -2, 0)
    del:SetText("X")
    del:SetScript("OnClick", function()
        expandedState[index] = nil
        layoutExpandedState[index] = nil
        Barshelf:RemoveShelf(index)
        Barshelf:RefreshConfig()
    end)

    -- Move down
    local moveDown = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    moveDown:SetSize(22, 20)
    moveDown:SetPoint("RIGHT", del, "LEFT", -2, 0)
    moveDown:SetNormalFontObject("GameFontNormalSmall")
    moveDown:SetText("v")
    if index < #Barshelf.db.shelves then
        moveDown:SetScript("OnClick", function()
            local shelves = Barshelf.db.shelves
            shelves[index], shelves[index + 1] = shelves[index + 1], shelves[index]
            Barshelf:RebuildAll()
            Barshelf:RefreshConfig()
        end)
    else
        moveDown:Disable()
    end

    -- Move up
    local moveUp = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    moveUp:SetSize(22, 20)
    moveUp:SetPoint("RIGHT", moveDown, "LEFT", -1, 0)
    moveUp:SetNormalFontObject("GameFontNormalSmall")
    moveUp:SetText("^")
    if index > 1 then
        moveUp:SetScript("OnClick", function()
            local shelves = Barshelf.db.shelves
            shelves[index], shelves[index - 1] = shelves[index - 1], shelves[index]
            Barshelf:RebuildAll()
            Barshelf:RefreshConfig()
        end)
    else
        moveUp:Disable()
    end

    y = y - 28

    -- Expand/collapse
    expand:SetScript("OnClick", function()
        expandedState[index] = not expandedState[index]
        Barshelf:RefreshConfig()
    end)

    -- Expanded settings
    if expandedState[index] then
        local indent = ROW_LEFT + 20

        -- Label
        _, y = CreateEditBox(parent, indent, y, "Label", config.label, 180, function(v)
            config.label = v
            DebouncedRebuild()
        end)

        -- Action Bar (bar shelves only)
        if config.type == "bar" then
            local barOpts = {}
            for id = 1, 8 do
                local info = Barshelf.BAR_INFO[id]
                barOpts[#barOpts + 1] = { text = info.label, value = id }
            end
            _, y = CreateDropdownButton(parent, indent, y, "Action Bar",
                barOpts, Barshelf.BAR_INFO[config.barID] and Barshelf.BAR_INFO[config.barID].label or "?",
                function(v)
                    for si, sc in ipairs(Barshelf.db.shelves) do
                        if si ~= index and sc.type == "bar" and sc.barID == v and sc.enabled then
                            print("|cff00ccffBarshelf:|r Bar " .. v .. " is already used.")
                            return
                        end
                    end
                    config.barID = v
                    config.label = Barshelf.BAR_INFO[v].label
                    Barshelf:RebuildAll()
                    Barshelf:RefreshConfig()
                end)
        end

        -- Open Direction (renamed from "Popup Anchor")
        local anchorOpts = {
            { text = "Auto",  value = "AUTO" },
            { text = "Below", value = "BOTTOM" },
            { text = "Above", value = "TOP" },
            { text = "Left",  value = "LEFT" },
            { text = "Right", value = "RIGHT" },
        }
        local anchorNames = { AUTO = "Auto", BOTTOM = "Below", TOP = "Above", LEFT = "Left", RIGHT = "Right" }
        _, y = CreateDropdownButton(parent, indent, y, "Open Direction",
            anchorOpts, anchorNames[config.popupAnchor] or "Auto",
            function(v) config.popupAnchor = v; DebouncedRebuild() end)

        -- Row Order (bar shelves only, overrides global)
        if config.type == "bar" then
            local shelfRowOpts = {
                { text = "Use Global", value = nil },
                { text = "Auto (Blizzard)", value = "auto" },
                { text = "Top to Bottom",   value = "topdown" },
                { text = "Bottom to Top",   value = "bottomup" },
            }
            local curVal = config.rowOrder
            local curLabel = curVal == "auto" and "Auto (Blizzard)"
                or curVal == "topdown" and "Top to Bottom"
                or curVal == "bottomup" and "Bottom to Top"
                or "Use Global"
            _, y = CreateDropdownButton(parent, indent, y, "Row Order",
                shelfRowOpts, curLabel,
                function(v) config.rowOrder = v; DebouncedRebuild() end)
        end

        -- Button Style (renamed from "Handle Display")
        local modeOpts = {
            { text = "Icon + Label", value = "both" },
            { text = "Label only",   value = "label" },
            { text = "Icon only",    value = "icon" },
        }
        local modeNames = { both = "Icon + Label", label = "Label only", icon = "Icon only" }
        _, y = CreateDropdownButton(parent, indent, y, "Button Style",
            modeOpts, modeNames[config.displayMode] or "Icon + Label",
            function(v) config.displayMode = v; DebouncedRebuild() end)

        -- Dock assignment (only shown when multiple docks exist)
        if #self.db.docks > 1 then
            local dockOpts = {}
            for _, dc in ipairs(self.db.docks) do
                dockOpts[#dockOpts + 1] = { text = dc.name, value = dc.id }
            end
            local curDockName = "Main"
            for _, dc in ipairs(self.db.docks) do
                if dc.id == config.dockID then curDockName = dc.name; break end
            end
            _, y = CreateDropdownButton(parent, indent, y, "Dock",
                dockOpts, curDockName,
                function(v) config.dockID = v; DebouncedRebuild() end)
        end

        -- Layout & Sizing sub-toggle
        y = y - 4
        local layoutToggle = CreateFrame("Button", nil, parent)
        layoutToggle:SetSize(200, 18)
        layoutToggle:SetPoint("TOPLEFT", indent, y)
        local layoutText = layoutToggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        layoutText:SetPoint("LEFT")
        layoutText:SetText((layoutExpandedState[index] and "v" or ">") .. " Layout & Sizing")
        layoutToggle:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        layoutToggle:SetScript("OnClick", function()
            layoutExpandedState[index] = not layoutExpandedState[index]
            Barshelf:RefreshConfig()
        end)
        y = y - 22

        if layoutExpandedState[index] then
            local layoutIndent = indent + 16
            local isBar = config.type == "bar"

            _, y = CreateSlider(parent, layoutIndent, y, "# of Icons",
                1, isBar and 12 or 24, 1, config.numButtons or 12,
                function(v) config.numButtons = v; DebouncedRebuild() end)

            _, y = CreateSlider(parent, layoutIndent, y, "# of Rows",
                1, isBar and 12 or 24, 1, config.numRows or 1,
                function(v) config.numRows = v; DebouncedRebuild() end)

            _, y = CreateSlider(parent, layoutIndent, y, "Icon Padding",
                0, 12, 1, config.buttonPadding or 2,
                function(v) config.buttonPadding = v; DebouncedRebuild() end)

            _, y = CreateSlider(parent, layoutIndent, y, "Icon Size",
                20, 56, 2, config.buttonSize or 36,
                function(v) config.buttonSize = v; DebouncedRebuild() end)

            _, y = CreateSlider(parent, layoutIndent, y, "Handle Icon Size",
                10, 32, 1, config.iconSize or 16,
                function(v) config.iconSize = v; DebouncedRebuild() end)

            _, y = CreateSlider(parent, layoutIndent, y, "Handle Font Size",
                8, 18, 1, config.labelFontSize or 12,
                function(v) config.labelFontSize = v; DebouncedRebuild() end)
        end

        y = y - 4
    end

    return y
end

---------------------------------------------------------------------------
-- Refresh config (rebuild the panel content)
---------------------------------------------------------------------------
function Barshelf:RefreshConfig()
    if self.configFrame and self.configFrame:IsShown() then
        self:PopulateConfig(self.configFrame)
    end
end

---------------------------------------------------------------------------
-- Toggle config visibility
---------------------------------------------------------------------------
function Barshelf:ToggleConfig()
    if InCombatLockdown() then
        print("|cff00ccffBarshelf:|r Cannot open settings in combat.")
        return
    end
    local f = self:CreateConfigFrame()
    if f:IsShown() then
        f:Hide()
    else
        self:PopulateConfig(f)
        f:Show()
    end
end
