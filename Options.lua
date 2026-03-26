local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")

local AceConfig       = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceGUI          = LibStub("AceGUI-3.0")
local AceDBOptions    = LibStub("AceDBOptions-3.0")

---------------------------------------------------------------------------
-- Minimap icon via LibDataBroker + LibDBIcon
---------------------------------------------------------------------------
function Barshelf:SetupMinimapIcon()
    local LDB  = LibStub("LibDataBroker-1.1", true)
    local LDBI = LibStub("LibDBIcon-1.0", true)
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
        LDBI:Register("Barshelf", dataObj, self.db.profile.minimap)
        if self.db.profile.showMinimap == false then
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
-- UI control factories
---------------------------------------------------------------------------
local function CreateCheckbox(parent, x, y, labelText, checked, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
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
-- Blizzard Settings panel registration
---------------------------------------------------------------------------
local parentCategory
local subcategories = {} -- name -> { category, panel, built }

local SUB_NAMES = {
    "General",
    "Appearance",
    "Shelves",
    "Docks",
    "Profiles",
}

local function createSubPanel()
    local p = CreateFrame("Frame")
    p:Hide()
    return p
end

---------------------------------------------------------------------------
-- buildAceConfigPanel: embed an AceConfig options table into a frame
---------------------------------------------------------------------------
local function buildAceConfigPanel(parentFrame, aceConfigName, title, description)
    local yOffset = -16
    if title then
        local hdr = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hdr:SetPoint("TOPLEFT", 16, -16)
        hdr:SetText(title)
        if description then
            local desc = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            desc:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -6)
            desc:SetPoint("RIGHT", parentFrame, "RIGHT", -16, 0)
            desc:SetJustifyH("LEFT")
            desc:SetSpacing(3)
            desc:SetText(description)
            local origOnShow = parentFrame:GetScript("OnShow")
            parentFrame:SetScript("OnShow", function(self)
                if origOnShow then origOnShow(self) end
                local descH = desc:GetStringHeight() or 14
                local hdrH = hdr:GetStringHeight() or 16
                local aceContainer = self._aceContainer
                if aceContainer then
                    aceContainer:ClearAllPoints()
                    aceContainer:SetPoint("TOPLEFT", 16, -(16 + hdrH + 6 + descH + 12))
                    aceContainer:SetPoint("BOTTOMRIGHT", -16, 10)
                end
            end)
            yOffset = -(16 + 16 + 6 + 14 + 12)
        else
            yOffset = -(16 + 16 + 12)
        end
    end

    local aceContainer = CreateFrame("Frame", nil, parentFrame)
    aceContainer:SetPoint("TOPLEFT", 16, yOffset)
    aceContainer:SetPoint("BOTTOMRIGHT", -16, 10)
    parentFrame._aceContainer = aceContainer

    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("Fill")
    container.frame:SetParent(parentFrame)
    container.frame:SetAllPoints(aceContainer)
    container.frame:Show()

    AceConfigDialog:Open(aceConfigName, container)
    return container
end

---------------------------------------------------------------------------
-- AceConfig: General
---------------------------------------------------------------------------
local function GetGeneralOptions()
    return {
        type = "group",
        name = "General",
        args = {
            closeOthers = {
                order = 1,
                type = "toggle",
                name = "Close other popups when opening one",
                desc = "Automatically hide other open shelves when a new one is opened.",
                width = "full",
                get = function() return Barshelf.db.profile.closeOthers end,
                set = function(_, v)
                    Barshelf.db.profile.closeOthers = v
                    Barshelf:UpdateAllSecureRefs()
                end,
            },
            animatePopups = {
                order = 2,
                type = "toggle",
                name = "Animate popups (fade in)",
                desc = "Play a short fade-in animation when a shelf popup opens.",
                width = "full",
                get = function() return Barshelf.db.profile.animatePopups end,
                set = function(_, v) Barshelf.db.profile.animatePopups = v end,
            },
            showMinimap = {
                order = 3,
                type = "toggle",
                name = "Show minimap icon",
                desc = "Display the Barshelf icon on the minimap.",
                width = "full",
                get = function() return Barshelf.db.profile.showMinimap ~= false end,
                set = function(_, v)
                    Barshelf.db.profile.showMinimap = v
                    Barshelf.db.profile.minimap.hide = not v
                    local LDBI = LibStub("LibDBIcon-1.0", true)
                    if LDBI then
                        if v then LDBI:Show("Barshelf") else LDBI:Hide("Barshelf") end
                    end
                end,
            },
            barRowOrder = {
                order = 4,
                type = "select",
                name = "Bar Row Order",
                desc = "How rows are ordered within bar shelves.",
                values = {
                    auto     = "Auto (Blizzard)",
                    topdown  = "Top to Bottom",
                    bottomup = "Bottom to Top",
                },
                sorting = { "auto", "topdown", "bottomup" },
                get = function() return Barshelf.db.profile.barRowOrder or "auto" end,
                set = function(_, v)
                    Barshelf.db.profile.barRowOrder = v
                    DebouncedRebuild()
                end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- AceConfig: Appearance
---------------------------------------------------------------------------
local function GetAppearanceOptions()
    return {
        type = "group",
        name = "Appearance",
        args = {
            -- Dock section
            dockHeader = {
                order = 1,
                type = "header",
                name = "Dock",
            },
            dockBgAlpha = {
                order = 2,
                type = "range",
                name = "Background Opacity",
                desc = "Opacity of the dock background.",
                min = 0, max = 1, step = 0.05,
                isPercent = true,
                get = function() return Barshelf.db.profile.dockBgAlpha or 0.75 end,
                set = function(_, v)
                    Barshelf.db.profile.dockBgAlpha = v
                    DebouncedRebuild()
                end,
            },
            dockBorderAlpha = {
                order = 3,
                type = "range",
                name = "Border Opacity",
                desc = "Opacity of the dock border.",
                min = 0, max = 1, step = 0.05,
                isPercent = true,
                get = function() return Barshelf.db.profile.dockBorderAlpha or 0.8 end,
                set = function(_, v)
                    Barshelf.db.profile.dockBorderAlpha = v
                    DebouncedRebuild()
                end,
            },
            dockShowBorder = {
                order = 4,
                type = "toggle",
                name = "Show Border",
                desc = "Draw a border around the dock frame.",
                get = function() return Barshelf.db.profile.dockShowBorder ~= false end,
                set = function(_, v)
                    Barshelf.db.profile.dockShowBorder = v
                    DebouncedRebuild()
                end,
            },
            dockPadding = {
                order = 5,
                type = "range",
                name = "Padding",
                desc = "Space between dock edge and shelf handles.",
                min = 0, max = 12, step = 1,
                get = function() return Barshelf.db.profile.dockPadding or 4 end,
                set = function(_, v)
                    Barshelf.db.profile.dockPadding = v
                    DebouncedRebuild()
                end,
            },

            -- Shelf Popup section
            popupHeader = {
                order = 10,
                type = "header",
                name = "Shelf Popup",
            },
            popupBgAlpha = {
                order = 11,
                type = "range",
                name = "Background Opacity",
                desc = "Opacity of the shelf popup background.",
                min = 0, max = 1, step = 0.05,
                isPercent = true,
                get = function() return Barshelf.db.profile.popupBgAlpha or 0.92 end,
                set = function(_, v)
                    Barshelf.db.profile.popupBgAlpha = v
                    DebouncedRebuild()
                end,
            },

            -- Handle section
            handleHeader = {
                order = 20,
                type = "header",
                name = "Handle",
            },
            handleBgAlpha = {
                order = 21,
                type = "range",
                name = "Background Opacity",
                desc = "Opacity of the handle background.",
                min = 0, max = 1, step = 0.05,
                isPercent = true,
                get = function() return Barshelf.db.profile.handleBgAlpha or 0.85 end,
                set = function(_, v)
                    Barshelf.db.profile.handleBgAlpha = v
                    DebouncedRebuild()
                end,
            },
            handleIconSize = {
                order = 22,
                type = "range",
                name = "Icon Size",
                desc = "Size of the icon displayed on shelf handles.",
                min = 10, max = 32, step = 1,
                get = function() return Barshelf.db.profile.handleIconSize or 16 end,
                set = function(_, v)
                    Barshelf.db.profile.handleIconSize = v
                    for _, cfg in ipairs(Barshelf.db.profile.shelves) do
                        cfg.iconSize = v
                    end
                    DebouncedRebuild()
                end,
            },
            handleFontSize = {
                order = 23,
                type = "range",
                name = "Font Size",
                desc = "Size of the label text on shelf handles.",
                min = 8, max = 18, step = 1,
                get = function() return Barshelf.db.profile.handleFontSize or 12 end,
                set = function(_, v)
                    Barshelf.db.profile.handleFontSize = v
                    for _, cfg in ipairs(Barshelf.db.profile.shelves) do
                        cfg.labelFontSize = v
                    end
                    DebouncedRebuild()
                end,
            },

            -- Bar Defaults section
            barHeader = {
                order = 30,
                type = "header",
                name = "Bar Defaults",
            },
            barIconSize = {
                order = 31,
                type = "range",
                name = "Icon Size",
                desc = "Default icon size for bar shelves.",
                min = 20, max = 56, step = 2,
                get = function() return Barshelf.db.profile.barIconSize or 36 end,
                set = function(_, v)
                    Barshelf.db.profile.barIconSize = v
                    for _, cfg in ipairs(Barshelf.db.profile.shelves) do
                        if cfg.type == "bar" then cfg.buttonSize = v end
                    end
                    DebouncedRebuild()
                end,
            },
            barIconPadding = {
                order = 32,
                type = "range",
                name = "Icon Padding",
                desc = "Default padding between icons in bar shelves.",
                min = 0, max = 12, step = 1,
                get = function() return Barshelf.db.profile.barIconPadding or 2 end,
                set = function(_, v)
                    Barshelf.db.profile.barIconPadding = v
                    for _, cfg in ipairs(Barshelf.db.profile.shelves) do
                        if cfg.type == "bar" then cfg.buttonPadding = v end
                    end
                    DebouncedRebuild()
                end,
            },
        },
    }
end

---------------------------------------------------------------------------
-- Shelves panel (custom frame, not AceConfig)
---------------------------------------------------------------------------
local function BuildShelvesPanel(panel)
    local PANEL_WIDTH = 580

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH, 1)
    scrollFrame:SetScrollChild(scrollChild)
    panel._scrollChild = scrollChild
    panel._scrollFrame = scrollFrame

    local function Refresh()
        local parent = panel._scrollChild
        if not parent then return end

        for _, child in pairs({parent:GetChildren()}) do
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
        for _, region in pairs({parent:GetRegions()}) do
            region:Hide()
        end

        local db = Barshelf.db.profile
        local y = -4

        if #db.shelves == 0 then
            local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            hint:SetPoint("TOPLEFT", 16, y)
            hint:SetText("No shelves yet. Add one below.")
            y = y - 20
        end

        for si, shelfCfg in ipairs(db.shelves) do
            local ROW_LEFT = 8

            -- Header row
            local hdr = CreateFrame("Frame", nil, parent)
            hdr:SetSize(PANEL_WIDTH - 20, 26)
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
            expandText:SetText(expandedState[si] and "v" or ">")

            -- Type badge
            local typeLabel = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            typeLabel:SetPoint("LEFT", expand, "RIGHT", 4, 0)
            if shelfCfg.type == "bar" then
                typeLabel:SetText("|cff88ccff[Bar " .. (shelfCfg.barID or "?") .. "]|r")
            else
                typeLabel:SetText("|cffcccc88[Custom]|r")
            end

            -- Label
            local label = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", typeLabel, "RIGHT", 6, 0)
            label:SetText(shelfCfg.label or "Unnamed")

            -- Enable toggle
            local enable = CreateFrame("CheckButton", nil, hdr, "UICheckButtonTemplate")
            enable:SetPoint("RIGHT", hdr, "RIGHT", -26, 0)
            enable:SetSize(22, 22)
            enable:SetChecked(shelfCfg.enabled)
            enable:SetScript("OnClick", function(frame)
                shelfCfg.enabled = frame:GetChecked()
                Barshelf:RebuildAll()
            end)

            -- Delete
            local del = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
            del:SetSize(22, 20)
            del:SetPoint("RIGHT", enable, "LEFT", -2, 0)
            del:SetText("X")
            del:SetScript("OnClick", function()
                expandedState[si] = nil
                layoutExpandedState[si] = nil
                Barshelf:RemoveShelf(si)
                Refresh()
            end)

            -- Move down
            local moveDown = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
            moveDown:SetSize(22, 20)
            moveDown:SetPoint("RIGHT", del, "LEFT", -2, 0)
            moveDown:SetNormalFontObject("GameFontNormalSmall")
            moveDown:SetText("v")
            if si < #db.shelves then
                moveDown:SetScript("OnClick", function()
                    local shelves = db.shelves
                    shelves[si], shelves[si + 1] = shelves[si + 1], shelves[si]
                    expandedState[si], expandedState[si + 1] = expandedState[si + 1], expandedState[si]
                    layoutExpandedState[si], layoutExpandedState[si + 1] = layoutExpandedState[si + 1], layoutExpandedState[si]
                    Barshelf:RebuildAll()
                    Refresh()
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
            if si > 1 then
                moveUp:SetScript("OnClick", function()
                    local shelves = db.shelves
                    shelves[si], shelves[si - 1] = shelves[si - 1], shelves[si]
                    expandedState[si], expandedState[si - 1] = expandedState[si - 1], expandedState[si]
                    layoutExpandedState[si], layoutExpandedState[si - 1] = layoutExpandedState[si - 1], layoutExpandedState[si]
                    Barshelf:RebuildAll()
                    Refresh()
                end)
            else
                moveUp:Disable()
            end

            y = y - 28

            expand:SetScript("OnClick", function()
                expandedState[si] = not expandedState[si]
                Refresh()
            end)

            -- Expanded settings
            if expandedState[si] then
                local indent = ROW_LEFT + 20

                -- Label edit
                _, y = CreateEditBox(parent, indent, y, "Label", shelfCfg.label, 180, function(v)
                    shelfCfg.label = v
                    DebouncedRebuild()
                end)

                -- Action Bar (bar shelves only)
                if shelfCfg.type == "bar" then
                    local barOpts = {}
                    for id = 1, 8 do
                        local info = Barshelf.BAR_INFO[id]
                        barOpts[#barOpts + 1] = { text = info.label, value = id }
                    end
                    _, y = CreateDropdownButton(parent, indent, y, "Action Bar",
                        barOpts,
                        Barshelf.BAR_INFO[shelfCfg.barID] and Barshelf.BAR_INFO[shelfCfg.barID].label or "?",
                        function(v)
                            for oi, oc in ipairs(db.shelves) do
                                if oi ~= si and oc.type == "bar" and oc.barID == v and oc.enabled then
                                    Barshelf:Print("Bar " .. v .. " is already used.")
                                    return
                                end
                            end
                            shelfCfg.barID = v
                            shelfCfg.label = Barshelf.BAR_INFO[v].label
                            Barshelf:RebuildAll()
                            Refresh()
                        end)
                end

                -- Open Direction
                local anchorOpts = {
                    { text = "Auto",  value = "AUTO" },
                    { text = "Below", value = "BOTTOM" },
                    { text = "Above", value = "TOP" },
                    { text = "Left",  value = "LEFT" },
                    { text = "Right", value = "RIGHT" },
                }
                local anchorNames = { AUTO = "Auto", BOTTOM = "Below", TOP = "Above", LEFT = "Left", RIGHT = "Right" }
                _, y = CreateDropdownButton(parent, indent, y, "Open Direction",
                    anchorOpts, anchorNames[shelfCfg.popupAnchor] or "Auto",
                    function(v) shelfCfg.popupAnchor = v; DebouncedRebuild() end)

                -- Row Order (bar shelves only, per-shelf override)
                if shelfCfg.type == "bar" then
                    local shelfRowOpts = {
                        { text = "Use Global", value = nil },
                        { text = "Auto (Blizzard)", value = "auto" },
                        { text = "Top to Bottom",   value = "topdown" },
                        { text = "Bottom to Top",   value = "bottomup" },
                    }
                    local curVal = shelfCfg.rowOrder
                    local curLabel = curVal == "auto" and "Auto (Blizzard)"
                        or curVal == "topdown" and "Top to Bottom"
                        or curVal == "bottomup" and "Bottom to Top"
                        or "Use Global"
                    _, y = CreateDropdownButton(parent, indent, y, "Row Order",
                        shelfRowOpts, curLabel,
                        function(v) shelfCfg.rowOrder = v; DebouncedRebuild() end)
                end

                -- Button Style
                local modeOpts = {
                    { text = "Icon + Label", value = "both" },
                    { text = "Label only",   value = "label" },
                    { text = "Icon only",    value = "icon" },
                }
                local modeNames = { both = "Icon + Label", label = "Label only", icon = "Icon only" }
                _, y = CreateDropdownButton(parent, indent, y, "Button Style",
                    modeOpts, modeNames[shelfCfg.displayMode] or "Icon + Label",
                    function(v) shelfCfg.displayMode = v; DebouncedRebuild() end)

                -- Dock assignment (only when multiple docks exist)
                if #db.docks > 1 then
                    local dockOpts = {}
                    for _, dc in ipairs(db.docks) do
                        dockOpts[#dockOpts + 1] = { text = dc.name, value = dc.id }
                    end
                    local curDockName = "Main"
                    for _, dc in ipairs(db.docks) do
                        if dc.id == shelfCfg.dockID then curDockName = dc.name; break end
                    end
                    _, y = CreateDropdownButton(parent, indent, y, "Dock",
                        dockOpts, curDockName,
                        function(v) shelfCfg.dockID = v; DebouncedRebuild() end)
                end

                -- Layout & Sizing sub-toggle
                y = y - 4
                local layoutToggle = CreateFrame("Button", nil, parent)
                layoutToggle:SetSize(200, 18)
                layoutToggle:SetPoint("TOPLEFT", indent, y)
                local layoutText = layoutToggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                layoutText:SetPoint("LEFT")
                layoutText:SetText((layoutExpandedState[si] and "v" or ">") .. " Layout & Sizing")
                layoutToggle:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                layoutToggle:SetScript("OnClick", function()
                    layoutExpandedState[si] = not layoutExpandedState[si]
                    Refresh()
                end)
                y = y - 22

                if layoutExpandedState[si] then
                    local layoutIndent = indent + 16
                    local isBar = shelfCfg.type == "bar"

                    _, y = CreateSlider(parent, layoutIndent, y, "# of Icons",
                        1, isBar and 12 or 24, 1, shelfCfg.numButtons or 12,
                        function(v) shelfCfg.numButtons = v; DebouncedRebuild() end)

                    _, y = CreateSlider(parent, layoutIndent, y, "# of Rows",
                        1, isBar and 12 or 24, 1, shelfCfg.numRows or 1,
                        function(v) shelfCfg.numRows = v; DebouncedRebuild() end)

                    _, y = CreateSlider(parent, layoutIndent, y, "Icon Padding",
                        0, 12, 1, shelfCfg.buttonPadding or 2,
                        function(v) shelfCfg.buttonPadding = v; DebouncedRebuild() end)

                    _, y = CreateSlider(parent, layoutIndent, y, "Icon Size",
                        20, 56, 2, shelfCfg.buttonSize or 36,
                        function(v) shelfCfg.buttonSize = v; DebouncedRebuild() end)

                    _, y = CreateSlider(parent, layoutIndent, y, "Handle Icon Size",
                        10, 32, 1, shelfCfg.iconSize or 16,
                        function(v) shelfCfg.iconSize = v; DebouncedRebuild() end)

                    _, y = CreateSlider(parent, layoutIndent, y, "Handle Font Size",
                        8, 18, 1, shelfCfg.labelFontSize or 12,
                        function(v) shelfCfg.labelFontSize = v; DebouncedRebuild() end)
                end

                y = y - 4
            end
        end

        y = y - 6

        -- Add shelf buttons
        local addBarBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        addBarBtn:SetSize(130, 22)
        addBarBtn:SetPoint("TOPLEFT", 12, y)
        addBarBtn:SetText("+ Add Bar Shelf")
        addBarBtn:SetScript("OnClick", function()
            local used = {}
            for _, cfg in ipairs(db.shelves) do
                if cfg.type == "bar" and cfg.enabled then used[cfg.barID] = true end
            end
            local barID
            for id = 1, 8 do
                if not used[id] then barID = id; break end
            end
            if not barID then
                Barshelf:Print("All bars (1-8) are already assigned.")
                return
            end
            Barshelf:AddBarShelf(barID)
            Refresh()
        end)

        local addCustBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        addCustBtn:SetSize(140, 22)
        addCustBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 8, 0)
        addCustBtn:SetText("+ Add Custom Shelf")
        addCustBtn:SetScript("OnClick", function()
            Barshelf:AddCustomShelf("Custom")
            Refresh()
        end)

        y = y - 30

        parent:SetHeight(math.abs(y) + 20)
    end

    panel._refresh = Refresh
    panel:SetScript("OnShow", function() Refresh() end)
    Refresh()
end

---------------------------------------------------------------------------
-- Docks panel (custom frame, not AceConfig)
---------------------------------------------------------------------------
local function BuildDocksPanel(panel)
    local PANEL_WIDTH = 580

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH, 1)
    scrollFrame:SetScrollChild(scrollChild)
    panel._scrollChild = scrollChild

    local function Refresh()
        local parent = panel._scrollChild
        if not parent then return end

        for _, child in pairs({parent:GetChildren()}) do
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
        for _, region in pairs({parent:GetRegions()}) do
            region:Hide()
        end

        local db = Barshelf.db.profile
        local y = -4

        local dockHint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        dockHint:SetPoint("TOPLEFT", 12, y)
        dockHint:SetText("Drag the dotted grip on each dock to reposition it.")
        y = y - 20

        for _, dockCfg in ipairs(db.docks) do
            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(PANEL_WIDTH - 40, 24)
            row:SetPoint("TOPLEFT", 12, y)

            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", 0, 0)
            lbl:SetText(dockCfg.name or ("Dock " .. dockCfg.id))

            local orient = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            orient:SetSize(80, 20)
            orient:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
            orient:SetText(dockCfg.orientation == "VERTICAL" and "Vertical" or "Horizontal")
            orient:SetScript("OnClick", function()
                dockCfg.orientation = dockCfg.orientation == "VERTICAL" and "HORIZONTAL" or "VERTICAL"
                orient:SetText(dockCfg.orientation == "VERTICAL" and "Vertical" or "Horizontal")
                Barshelf:RebuildAll()
            end)

            if dockCfg.id ~= 1 then
                local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                del:SetSize(22, 20)
                del:SetPoint("LEFT", orient, "RIGHT", 4, 0)
                del:SetText("X")
                del:SetScript("OnClick", function()
                    Barshelf:RemoveDock(dockCfg.id)
                    Refresh()
                end)
            end

            y = y - 26
        end

        local addDock = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        addDock:SetSize(100, 22)
        addDock:SetPoint("TOPLEFT", 12, y)
        addDock:SetText("+ Add Dock")
        addDock:SetScript("OnClick", function()
            Barshelf:AddDock()
            Refresh()
        end)
        y = y - 30

        parent:SetHeight(math.abs(y) + 20)
    end

    panel._refresh = Refresh
    panel:SetScript("OnShow", function() Refresh() end)
    Refresh()
end

---------------------------------------------------------------------------
-- Panel builders (dispatched lazily on first OnShow)
---------------------------------------------------------------------------
local function BuildGeneralPanel(panel)
    buildAceConfigPanel(panel, "Barshelf_General", "General",
        "Global behavior settings for all shelves and docks.")
end

local function BuildAppearancePanel(panel)
    buildAceConfigPanel(panel, "Barshelf_Appearance", "Appearance",
        "Visual settings for docks, shelf popups, handles, and bar defaults.")
end

local function BuildProfilesPanel(panel)
    AceConfig:RegisterOptionsTable("Barshelf_Profiles", AceDBOptions:GetOptionsTable(Barshelf.db))
    buildAceConfigPanel(panel, "Barshelf_Profiles", "Profiles",
        "Manage saved variable profiles.")
end

local PANEL_BUILDERS = {
    General    = BuildGeneralPanel,
    Appearance = BuildAppearancePanel,
    Shelves    = BuildShelvesPanel,
    Docks      = BuildDocksPanel,
    Profiles   = BuildProfilesPanel,
}

---------------------------------------------------------------------------
-- Register all panels with Blizzard Settings
---------------------------------------------------------------------------
local function RegisterAllPanels()
    if parentCategory then return end

    -- Register AceConfig option tables (General, Appearance)
    AceConfig:RegisterOptionsTable("Barshelf_General", GetGeneralOptions)
    AceConfig:RegisterOptionsTable("Barshelf_Appearance", GetAppearanceOptions)

    -- Main (parent) panel -- landing page
    local mainPanel = createSubPanel()
    parentCategory = Settings.RegisterCanvasLayoutCategory(mainPanel, "Barshelf")
    Settings.RegisterAddOnCategory(parentCategory)

    mainPanel:SetScript("OnShow", function(self)
        self:SetScript("OnShow", nil)
        local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Barshelf")

        local ver = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ver:SetPoint("LEFT", title, "RIGHT", 8, 0)
        ver:SetText("|cff888888v" .. (Barshelf.version or "?") .. "|r")

        local desc = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetWidth(500)
        desc:SetJustifyH("LEFT")
        desc:SetText("Access your hidden action bars through floating popup shelves.\n\n" ..
            "Select a subcategory on the left to configure Barshelf.")
    end)

    -- Create subcategories with lazy building
    for _, name in ipairs(SUB_NAMES) do
        local p = createSubPanel()
        local subcat = Settings.RegisterCanvasLayoutSubcategory(parentCategory, p, name)
        subcategories[name] = { category = subcat, panel = p, built = false }

        p:SetScript("OnShow", function(self)
            if subcategories[name].built then return end
            subcategories[name].built = true
            local builder = PANEL_BUILDERS[name]
            if builder then
                builder(self)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- openOptions: navigate to a subcategory (combat-safe)
---------------------------------------------------------------------------
local pendingOpen = false

function Barshelf:openOptions(subcategoryName)
    if not parentCategory then return end

    local targetID
    if subcategoryName and subcategories[subcategoryName] then
        targetID = subcategories[subcategoryName].category.ID
    elseif subcategories["General"] then
        targetID = subcategories["General"].category.ID
    else
        targetID = parentCategory.ID
    end

    if InCombatLockdown() then
        if not pendingOpen then
            pendingOpen = true
            self:Print("Settings will open after combat ends.")
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                pendingOpen = false
                if targetID then
                    Settings.OpenToCategory(targetID)
                end
            end)
        end
        return
    end

    Settings.OpenToCategory(targetID)
end

---------------------------------------------------------------------------
-- ToggleConfig: replaces the old standalone config frame toggle
---------------------------------------------------------------------------
function Barshelf:ToggleConfig()
    self:openOptions()
end

---------------------------------------------------------------------------
-- RefreshConfig: refresh visible custom panels (Shelves, Docks)
---------------------------------------------------------------------------
function Barshelf:RefreshConfig()
    for _, name in ipairs({"Shelves", "Docks"}) do
        local sub = subcategories[name]
        if sub and sub.built and sub.panel and sub.panel:IsShown() and sub.panel._refresh then
            sub.panel._refresh()
        end
    end
end

---------------------------------------------------------------------------
-- SetupOptions: called from Core.lua's OnInitialize
---------------------------------------------------------------------------
function Barshelf:SetupOptions()
    RegisterAllPanels()
end
