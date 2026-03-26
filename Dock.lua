local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")

---------------------------------------------------------------------------
-- Dock mixin
---------------------------------------------------------------------------
local DockMixin = {}

function DockMixin:SavePosition()
    local point, _, relPoint, x, y = self:GetPoint()
    if point then
        self.config.point = { point, relPoint, x, y }
    end
end

function DockMixin:AddShelf(shelf)
    table.insert(self.orderedShelves, shelf)
    self:CreateHandle(shelf)
    self:LayoutHandles()
end

function DockMixin:RemoveShelf(shelf)
    for i, s in ipairs(self.orderedShelves) do
        if s == shelf then table.remove(self.orderedShelves, i); break end
    end
    if shelf.handle then
        shelf.handle:Hide()
        shelf.handle:SetParent(UIParent)
    end
    self:LayoutHandles()
end

---------------------------------------------------------------------------
-- Handle creation (SecureHandlerClickTemplate for combat-safe toggle)
---------------------------------------------------------------------------
local HANDLE_CLICK_SNIPPET = [[
    if button == "LeftButton" then
        local popup = self:GetFrameRef("popup")
        if not popup then return end
        local isShown = popup:IsShown()

        local closeOthers = self:GetAttribute("closeOthers")
        if closeOthers and not isShown then
            local count = self:GetAttribute("otherpopupcount") or 0
            for i = 1, count do
                local other = self:GetFrameRef("otherpopup" .. i)
                if other and other:IsShown() then
                    other:Hide()
                end
            end
        end

        if isShown then
            popup:Hide()
        else
            popup:Show()
        end
    end
]]

---------------------------------------------------------------------------
-- Handle creation
---------------------------------------------------------------------------
function DockMixin:CreateHandle(shelf)
    if InCombatLockdown() then
        Barshelf:QueueForCombat(function() self:CreateHandle(shelf) end)
        return
    end

    local dock = self -- capture for closures
    local handleName = "BarshelfHandle_" .. self.config.id .. "_" .. (shelf.index or 0)
    local handle = CreateFrame("Button", handleName, self, "SecureHandlerClickTemplate")
    handle:SetFrameStrata("DIALOG")
    handle:SetFrameLevel(self:GetFrameLevel() + 1)

    -- Background
    local bg = handle:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, Barshelf.db.profile.handleBgAlpha or 0.85)
    handle.bg = bg

    -- Highlight
    local hl = handle:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.3, 0.3, 0.3, 0.4)

    -- Icon
    local icon = handle:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    handle.icon = icon

    -- Label
    local label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handle.label = label

    -- Secure click handler (popup toggle)
    handle:SetFrameRef("popup", shelf.popup)
    handle:SetAttribute("_onclick", HANDLE_CLICK_SNIPPET)
    handle:RegisterForClicks("AnyUp")

    -- Right-click opens settings for this shelf
    handle:HookScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and not InCombatLockdown() then
            Barshelf:openOptions("Shelves", shelf.index)
        end
    end)

    shelf.handle = handle
    self:UpdateHandleDisplay(handle, shelf)
end

---------------------------------------------------------------------------
-- Handle display modes: "label", "icon", "both"
---------------------------------------------------------------------------
function DockMixin:UpdateHandleDisplay(handle, shelf)
    local config   = shelf.config
    local mode     = config.displayMode or "both"
    local iconSz   = config.iconSize or 16
    local fontSize = config.labelFontSize or 12
    local pad      = 4

    handle.icon:SetSize(iconSz, iconSz)

    local fontPath = handle.label:GetFont() or "Fonts\\FRIZQT__.TTF"
    handle.label:SetFont(fontPath, fontSize, "OUTLINE")
    handle.label:SetText(config.label or "Shelf")

    if mode == "icon" then
        handle.icon:Show()
        handle.icon:ClearAllPoints()
        handle.icon:SetPoint("CENTER")
        handle.label:Hide()
        handle:SetSize(iconSz + pad * 2, iconSz + pad * 2)
    elseif mode == "label" then
        handle.icon:Hide()
        handle.label:Show()
        handle.label:ClearAllPoints()
        handle.label:SetPoint("CENTER")
        handle:SetSize(handle.label:GetStringWidth() + pad * 2, fontSize + pad * 2 + 2)
    else -- "both"
        handle.icon:Show()
        handle.label:Show()
        handle.icon:ClearAllPoints()
        handle.icon:SetPoint("LEFT", pad, 0)
        handle.label:ClearAllPoints()
        handle.label:SetPoint("LEFT", handle.icon, "RIGHT", 3, 0)
        local w = iconSz + 3 + handle.label:GetStringWidth() + pad * 2
        local h = math.max(iconSz, fontSize + 2) + pad * 2
        handle:SetSize(w, h)
    end

    self:UpdateHandleIcon(handle, shelf)
end

function DockMixin:UpdateHandleIcon(handle, shelf)
    local texture = "Interface\\Icons\\INV_Misc_QuestionMark"

    if shelf.config.type == "bar" then
        local info = Barshelf.BAR_INFO[shelf.config.barID]
        if info then
            for i = 1, shelf.config.numButtons or 12 do
                local btn = _G[info.prefix .. i]
                if btn then
                    local ic = btn.icon and btn.icon:GetTexture()
                    if ic then texture = ic; break end
                end
            end
        end
    elseif shelf.config.type == "custom" and shelf.config.buttons then
        for i = 1, shelf.config.numButtons or 6 do
            local bc = shelf.config.buttons[i]
            if bc then
                local t
                if bc.type == "spell" and bc.id then
                    t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(bc.id)
                elseif bc.type == "item" and bc.id then
                    t = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(bc.id)
                end
                if t then texture = t; break end
            end
        end
    end

    handle.icon:SetTexture(texture)
end

---------------------------------------------------------------------------
-- Arrange handles inside dock
---------------------------------------------------------------------------
function DockMixin:LayoutHandles()
    local isH      = (self.config.orientation or "HORIZONTAL") == "HORIZONTAL"
    local spacing  = 1
    local dockPad  = Barshelf.db.profile.dockPadding or 4
    local gripSize = 12

    local visible = {}
    for _, shelf in ipairs(self.orderedShelves) do
        if shelf.handle then
            shelf.handle:Show()
            visible[#visible + 1] = shelf.handle
        end
    end

    if #visible == 0 then
        self:Hide()
        if self.grip then self.grip:Hide() end
        return
    end

    -- Measure handles
    local totalMain, maxCross = 0, 0
    for i, h in ipairs(visible) do
        local w, ht = h:GetSize()
        if isH then
            totalMain = totalMain + w + (i > 1 and spacing or 0)
            if ht > maxCross then maxCross = ht end
        else
            totalMain = totalMain + ht + (i > 1 and spacing or 0)
            if w > maxCross then maxCross = w end
        end
    end

    -- Size dock (grip + padding + handles)
    if isH then
        self:SetSize(gripSize + totalMain + dockPad * 2, maxCross + dockPad * 2)
    else
        self:SetSize(maxCross + dockPad * 2, gripSize + totalMain + dockPad * 2)
    end

    -- Position grip
    if self.grip then
        self.grip:ClearAllPoints()
        if isH then
            self.grip:SetPoint("LEFT", self, "LEFT", 2, 0)
            self.grip:SetSize(gripSize - 2, maxCross)
        else
            self.grip:SetPoint("TOP", self, "TOP", 0, -2)
            self.grip:SetSize(maxCross, gripSize - 2)
        end
        self.grip:Show()
    end

    -- Position handles (after grip)
    local offset = dockPad + gripSize
    for i, h in ipairs(visible) do
        h:ClearAllPoints()
        if isH then
            h:SetPoint("LEFT", self, "LEFT", offset, 0)
            offset = offset + h:GetWidth() + spacing
        else
            h:SetPoint("TOP", self, "TOP", 0, -offset)
            offset = offset + h:GetHeight() + spacing
        end
    end

    self:Show()
end

---------------------------------------------------------------------------
-- Dock creation
---------------------------------------------------------------------------
function Barshelf:CreateDock(config)
    local id = config.id
    local dock = CreateFrame("Frame", "BarshelfDock_" .. id, UIParent, "BackdropTemplate")
    Mixin(dock, DockMixin)
    dock.config = config
    dock.orderedShelves = {}

    local showBorder = Barshelf.db.profile.dockShowBorder ~= false
    dock:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = showBorder and "Interface/Tooltips/UI-Tooltip-Border" or nil,
        tile = true, tileSize = 16, edgeSize = showBorder and 10 or 0,
        insets = showBorder and { left = 2, right = 2, top = 2, bottom = 2 } or { left = 0, right = 0, top = 0, bottom = 0 },
    })
    dock:SetBackdropColor(0.08, 0.08, 0.08, Barshelf.db.profile.dockBgAlpha or 0.75)
    if showBorder then
        dock:SetBackdropBorderColor(0.35, 0.35, 0.35, Barshelf.db.profile.dockBorderAlpha or 0.8)
    end

    dock:SetMovable(true)
    dock:EnableMouse(true)
    dock:RegisterForDrag("LeftButton")
    dock:SetClampedToScreen(true)

    -- Manual drag: track mouse offset to avoid StartMoving() snap issues
    local function BeginDockDrag()
        if InCombatLockdown() or dock._isDragging then return end
        local scale = dock:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        dock._dragOffsetX = cx / scale - (dock:GetLeft() or 0)
        dock._dragOffsetY = cy / scale - (dock:GetTop() or 0)
        dock._isDragging = true
        dock:SetScript("OnUpdate", function(self)
            if not self._isDragging then return end
            local s = self:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                mx / s - self._dragOffsetX,
                my / s - self._dragOffsetY)
        end)
    end
    local function EndDockDrag()
        if not dock._isDragging then return end
        dock._isDragging = false
        dock:SetScript("OnUpdate", nil)
        dock:SavePosition()
    end

    dock:SetScript("OnDragStart", function() BeginDockDrag() end)
    dock:SetScript("OnDragStop", function() EndDockDrag() end)

    -- Drag grip indicator (clearly draggable area)
    local grip = CreateFrame("Frame", nil, dock)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() BeginDockDrag() end)
    grip:SetScript("OnDragStop", function() EndDockDrag() end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Grip dot pattern (2 cols x 3 rows)
    for row = 0, 2 do
        for col = 0, 1 do
            local dot = grip:CreateTexture(nil, "ARTWORK")
            dot:SetSize(2, 2)
            dot:SetColorTexture(0.5, 0.5, 0.5, 0.7)
            dot:SetPoint("CENTER", grip, "CENTER", (col - 0.5) * 4, (1 - row) * 4)
        end
    end
    dock.grip = grip

    dock:SetFrameStrata("DIALOG")
    dock:SetFrameLevel(2)
    dock:SetSize(10, 10)

    if config.point then
        dock:SetPoint(config.point[1], UIParent, config.point[2], config.point[3], config.point[4])
    else
        dock:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    self.docks[id] = dock
    return dock
end
