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
            stackPopups = {
                order = 1.5,
                type = "toggle",
                name = "Stack open popups",
                desc = "When multiple popups are open, stack them sequentially instead of overlapping. Only applies when 'Close other popups' is off.",
                width = "full",
                disabled = function() return Barshelf.db.profile.closeOthers end,
                get = function() return Barshelf.db.profile.stackPopups end,
                set = function(_, v)
                    Barshelf.db.profile.stackPopups = v
                    if not InCombatLockdown() then
                        for _, dock in pairs(Barshelf.docks) do
                            Barshelf:LayoutDockPopups(dock)
                        end
                    end
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
            dockIdleHeader = {
                order = 2.5,
                type = "header",
                name = "Dock Idle Behavior",
            },
            dockIdleAlpha = {
                order = 2.6,
                type = "range",
                name = "Idle dock opacity",
                desc = "Dock opacity when no popup is open and mouse is not hovering. Set to 1 to disable fading.",
                min = 0, max = 1, step = 0.05,
                isPercent = true,
                get = function() return Barshelf.db.profile.dockIdleAlpha or 1.0 end,
                set = function(_, v)
                    Barshelf.db.profile.dockIdleAlpha = v
                    for _, dock in pairs(Barshelf.docks) do
                        dock:UpdateMouseoverAlpha()
                    end
                end,
            },
            dockFadeDuration = {
                order = 2.7,
                type = "range",
                name = "Fade duration",
                desc = "How long the fade animation takes (seconds).",
                min = 0, max = 1, step = 0.05,
                disabled = function() return (Barshelf.db.profile.dockIdleAlpha or 1.0) >= 1.0 end,
                get = function() return Barshelf.db.profile.dockFadeDuration or 0.3 end,
                set = function(_, v)
                    Barshelf.db.profile.dockFadeDuration = v
                end,
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
-- Shelves panel: list on left, detail on right
---------------------------------------------------------------------------
local selectedShelf = nil -- index into db.shelves

local function BuildShelvesPanel(panel)
    local LIST_WIDTH = 170
    local DETAIL_LEFT = LIST_WIDTH + 12

    -- Left: shelf list (scrollable)
    local listBorder = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    listBorder:SetPoint("TOPLEFT", 4, -8)
    listBorder:SetPoint("BOTTOMLEFT", 4, 36)
    listBorder:SetWidth(LIST_WIDTH)
    listBorder:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listBorder:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
    listBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local listScroll = CreateFrame("ScrollFrame", nil, listBorder, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 4, -4)
    listScroll:SetPoint("BOTTOMRIGHT", -22, 4)
    local listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(LIST_WIDTH - 28, 1)
    listScroll:SetScrollChild(listChild)

    -- Right: detail area (scrollable)
    local detailScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", DETAIL_LEFT, -8)
    detailScroll:SetPoint("BOTTOMRIGHT", -24, 36)
    local detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(400, 1)
    detailScroll:SetScrollChild(detailChild)

    -- Bottom: add buttons
    local addBarBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBarBtn:SetSize(130, 22)
    addBarBtn:SetPoint("BOTTOMLEFT", 8, 8)
    addBarBtn:SetText("+ Add Bar Shelf")

    local addCustBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addCustBtn:SetSize(140, 22)
    addCustBtn:SetPoint("LEFT", addBarBtn, "RIGHT", 8, 0)
    addCustBtn:SetText("+ Add Custom Shelf")

    ---------------------------------------------------------------------------
    local function RefreshList()
        for _, c in pairs({listChild:GetChildren()}) do c:Hide(); c:ClearAllPoints(); c:SetParent(nil) end
        for _, r in pairs({listChild:GetRegions()}) do r:Hide() end

        local db = Barshelf.db.profile
        local y = 0

        if #db.shelves == 0 then
            local hint = listChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            hint:SetPoint("TOPLEFT", 4, -4)
            hint:SetText("No shelves yet.")
            y = -20
        end

        for si, cfg in ipairs(db.shelves) do
            local row = CreateFrame("Button", nil, listChild)
            row:SetSize(LIST_WIDTH - 28, 22)
            row:SetPoint("TOPLEFT", 0, y)

            -- Selected highlight
            local sel = row:CreateTexture(nil, "BACKGROUND")
            sel:SetAllPoints()
            if si == selectedShelf then
                sel:SetColorTexture(0.2, 0.4, 0.6, 0.6)
            else
                sel:SetColorTexture(0, 0, 0, 0)
            end

            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            -- Label
            local badge = (cfg.type == "bar")
                and "|cff88ccff[B" .. (cfg.barID or "?") .. "]|r "
                or "|cffcccc88[C]|r "
            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", 4, 0)
            lbl:SetPoint("RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetText(badge .. (cfg.label or "Unnamed"))
            if not cfg.enabled then lbl:SetAlpha(0.5) end

            row:SetScript("OnClick", function()
                selectedShelf = si
                panel._refresh()
            end)

            y = y - 23
        end

        listChild:SetHeight(math.abs(y) + 4)
    end

    ---------------------------------------------------------------------------
    local function RefreshDetail()
        for _, c in pairs({detailChild:GetChildren()}) do c:Hide(); c:ClearAllPoints(); c:SetParent(nil) end
        for _, r in pairs({detailChild:GetRegions()}) do r:Hide() end

        local db = Barshelf.db.profile
        local cfg = db.shelves[selectedShelf]
        if not cfg then
            local hint = detailChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            hint:SetPoint("TOPLEFT", 8, -8)
            hint:SetText("Select a shelf on the left to configure it.")
            detailChild:SetHeight(30)
            return
        end

        local si = selectedShelf
        local y = -4
        local indent = 4

        -- Title row: type + label + enabled + move + delete
        local titleRow = CreateFrame("Frame", nil, detailChild)
        titleRow:SetSize(390, 24)
        titleRow:SetPoint("TOPLEFT", indent, y)

        local titleText = titleRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleText:SetPoint("LEFT")
        titleText:SetText(cfg.label or "Unnamed")

        -- Enabled
        local enable = CreateFrame("CheckButton", nil, titleRow, "UICheckButtonTemplate")
        enable:SetPoint("RIGHT", titleRow, "RIGHT", 0, 0)
        enable:SetSize(22, 22)
        enable:SetChecked(cfg.enabled)
        local enText = enable.Text or enable.text
        if enText then enText:SetText("Enabled") end
        enable:SetScript("OnClick", function(f)
            cfg.enabled = f:GetChecked()
            Barshelf:RebuildAll()
            RefreshList()
        end)

        -- Delete
        local del = CreateFrame("Button", nil, titleRow, "UIPanelButtonTemplate")
        del:SetSize(60, 20)
        del:SetPoint("RIGHT", enable, "LEFT", -6, 0)
        del:SetText("Delete")
        del:SetScript("OnClick", function()
            selectedShelf = nil
            Barshelf:RemoveShelf(si)
            panel._refresh()
        end)

        -- Move up / down
        local moveDown = CreateFrame("Button", nil, titleRow, "UIPanelButtonTemplate")
        moveDown:SetSize(22, 20)
        moveDown:SetPoint("RIGHT", del, "LEFT", -4, 0)
        moveDown:SetNormalFontObject("GameFontNormalSmall")
        moveDown:SetText("v")
        if si < #db.shelves then
            moveDown:SetScript("OnClick", function()
                db.shelves[si], db.shelves[si + 1] = db.shelves[si + 1], db.shelves[si]
                selectedShelf = si + 1
                Barshelf:RebuildAll()
                panel._refresh()
            end)
        else moveDown:Disable() end

        local moveUp = CreateFrame("Button", nil, titleRow, "UIPanelButtonTemplate")
        moveUp:SetSize(22, 20)
        moveUp:SetPoint("RIGHT", moveDown, "LEFT", -1, 0)
        moveUp:SetNormalFontObject("GameFontNormalSmall")
        moveUp:SetText("^")
        if si > 1 then
            moveUp:SetScript("OnClick", function()
                db.shelves[si], db.shelves[si - 1] = db.shelves[si - 1], db.shelves[si]
                selectedShelf = si - 1
                Barshelf:RebuildAll()
                panel._refresh()
            end)
        else moveUp:Disable() end

        y = y - 30

        -- Label
        _, y = CreateEditBox(detailChild, indent, y, "Label", cfg.label, 200, function(v)
            cfg.label = v
            DebouncedRebuild()
            RefreshList()
        end)

        -- Action Bar (bar type only)
        if cfg.type == "bar" then
            local barOpts = {}
            for id = 1, 8 do
                barOpts[#barOpts + 1] = { text = Barshelf.BAR_INFO[id].label, value = id }
            end
            _, y = CreateDropdownButton(detailChild, indent, y, "Action Bar",
                barOpts,
                Barshelf.BAR_INFO[cfg.barID] and Barshelf.BAR_INFO[cfg.barID].label or "?",
                function(v)
                    for oi, oc in ipairs(db.shelves) do
                        if oi ~= si and oc.type == "bar" and oc.barID == v and oc.enabled then
                            Barshelf:Print("Bar " .. v .. " is already used.")
                            return
                        end
                    end
                    cfg.barID = v
                    cfg.label = Barshelf.BAR_INFO[v].label
                    Barshelf:RebuildAll()
                    panel._refresh()
                end)
        end

        -- Open Direction
        local anchorNames = { AUTO = "Auto", BOTTOM = "Below", TOP = "Above", LEFT = "Left", RIGHT = "Right" }
        _, y = CreateDropdownButton(detailChild, indent, y, "Open Direction",
            {
                { text = "Auto",  value = "AUTO" },
                { text = "Below", value = "BOTTOM" },
                { text = "Above", value = "TOP" },
                { text = "Left",  value = "LEFT" },
                { text = "Right", value = "RIGHT" },
            },
            anchorNames[cfg.popupAnchor] or "Auto",
            function(v) cfg.popupAnchor = v; DebouncedRebuild() end)

        -- Button Style
        local modeNames = { both = "Icon + Label", label = "Label only", icon = "Icon only" }
        _, y = CreateDropdownButton(detailChild, indent, y, "Handle Style",
            {
                { text = "Icon + Label", value = "both" },
                { text = "Label only",   value = "label" },
                { text = "Icon only",    value = "icon" },
            },
            modeNames[cfg.displayMode] or "Icon + Label",
            function(v) cfg.displayMode = v; DebouncedRebuild() end)

        -- Row Order (bar type only)
        if cfg.type == "bar" then
            local curVal = cfg.rowOrder
            local curLabel = curVal == "auto" and "Auto (Blizzard)"
                or curVal == "topdown" and "Top to Bottom"
                or curVal == "bottomup" and "Bottom to Top"
                or "Use Global"
            _, y = CreateDropdownButton(detailChild, indent, y, "Row Order",
                {
                    { text = "Use Global", value = nil },
                    { text = "Auto (Blizzard)", value = "auto" },
                    { text = "Top to Bottom",   value = "topdown" },
                    { text = "Bottom to Top",   value = "bottomup" },
                },
                curLabel,
                function(v) cfg.rowOrder = v; DebouncedRebuild() end)
        end

        -- Dock (only if >1)
        if #db.docks > 1 then
            local dockOpts = {}
            for _, dc in ipairs(db.docks) do
                dockOpts[#dockOpts + 1] = { text = dc.name, value = dc.id }
            end
            local curDockName = "Main"
            for _, dc in ipairs(db.docks) do
                if dc.id == cfg.dockID then curDockName = dc.name; break end
            end
            _, y = CreateDropdownButton(detailChild, indent, y, "Dock",
                dockOpts, curDockName,
                function(v) cfg.dockID = v; DebouncedRebuild() end)
        end

        y = y - 6

        -- Layout & Sizing section header
        local layoutHdr = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        layoutHdr:SetPoint("TOPLEFT", indent, y)
        layoutHdr:SetText("|cffffffffLayout & Sizing|r")
        y = y - 18

        local isBar = cfg.type == "bar"

        _, y = CreateSlider(detailChild, indent, y, "# of Icons",
            1, isBar and 12 or 24, 1, cfg.numButtons or 12,
            function(v) cfg.numButtons = v; DebouncedRebuild() end)

        _, y = CreateSlider(detailChild, indent, y, "# of Rows",
            1, isBar and 12 or 24, 1, cfg.numRows or 1,
            function(v) cfg.numRows = v; DebouncedRebuild() end)

        _, y = CreateSlider(detailChild, indent, y, "Icon Size",
            20, 56, 2, cfg.buttonSize or 36,
            function(v) cfg.buttonSize = v; DebouncedRebuild() end)

        _, y = CreateSlider(detailChild, indent, y, "Icon Padding",
            0, 12, 1, cfg.buttonPadding or 2,
            function(v) cfg.buttonPadding = v; DebouncedRebuild() end)

        y = y - 6

        local handleHdr = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        handleHdr:SetPoint("TOPLEFT", indent, y)
        handleHdr:SetText("|cffffffffHandle (per-shelf)|r")
        y = y - 18

        _, y = CreateSlider(detailChild, indent, y, "Handle Icon Size",
            10, 32, 1, cfg.iconSize or 16,
            function(v) cfg.iconSize = v; DebouncedRebuild() end)

        _, y = CreateSlider(detailChild, indent, y, "Handle Font Size",
            8, 18, 1, cfg.labelFontSize or 12,
            function(v) cfg.labelFontSize = v; DebouncedRebuild() end)

        detailChild:SetHeight(math.abs(y) + 20)
    end

    ---------------------------------------------------------------------------
    local function Refresh()
        local db = Barshelf.db.profile
        -- Clamp selection
        if selectedShelf and (selectedShelf < 1 or selectedShelf > #db.shelves) then
            selectedShelf = nil
        end
        RefreshList()
        RefreshDetail()
    end

    addBarBtn:SetScript("OnClick", function()
        local db = Barshelf.db.profile
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
        selectedShelf = #db.shelves
        Refresh()
    end)

    addCustBtn:SetScript("OnClick", function()
        Barshelf:AddCustomShelf("Custom")
        selectedShelf = #Barshelf.db.profile.shelves
        Refresh()
    end)

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

function Barshelf:openOptions(subcategoryName, shelfIndex)
    if not parentCategory then return end

    -- Pre-select a shelf if requested
    if shelfIndex then
        selectedShelf = shelfIndex
        subcategoryName = subcategoryName or "Shelves"
    end

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
