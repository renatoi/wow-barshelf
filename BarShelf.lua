local _, Barshelf = ...

---------------------------------------------------------------------------
-- Bar shelves reparent Blizzard's own action buttons at their native size.
-- No resizing, no chrome stripping — Blizzard's code handles cooldowns,
-- usability, range coloring, and proc highlights natively (including in
-- combat where addon code can't read "secret values").
---------------------------------------------------------------------------
function Barshelf:CreateBarShelf(config, index)
    local shelf = {
        config = config,
        index  = index,
        type   = "bar",
        buttons = {},
        originalParents = {},
        originalPoints  = {},
        originalScales  = {},
    }

    shelf.popup = self:CreatePopup(shelf)
    self:ActivateBarShelf(shelf)
    return shelf
end

---------------------------------------------------------------------------
-- Activate: reparent Blizzard buttons into our popup at native size
---------------------------------------------------------------------------
function Barshelf:ActivateBarShelf(shelf)
    if InCombatLockdown() then
        self:QueueForCombat(function() self:ActivateBarShelf(shelf) end)
        return
    end

    local info = self.BAR_INFO[shelf.config.barID]
    if not info then return end

    wipe(shelf.buttons)

    -- Count how many buttons Blizzard is actually showing (respects Edit Mode
    -- "# of Icons" setting). Only reparent visible buttons.
    local blizzardCount = 0
    for i = 1, info.count do
        local button = _G[info.prefix .. i]
        if button and button:IsShown() then
            blizzardCount = blizzardCount + 1
        end
    end
    local num = math.min(shelf.config.numButtons or info.count, blizzardCount)

    for i = 1, num do
        local button = _G[info.prefix .. i]
        if button then
            shelf.originalParents[i] = button:GetParent()
            shelf.originalScales[i] = button:GetScale()
            local n = button:GetNumPoints()
            if n > 0 then
                shelf.originalPoints[i] = { button:GetPoint(1) }
            end

            -- Prevent Blizzard's bar management from hiding reparented buttons
            RegisterStateDriver(button, "visibility", "show")
            button._barshelfManaged = true

            shelf.buttons[i] = button
        end
    end

    self:LayoutBarPopup(shelf)

    -- Force Blizzard's update on each button to clear stale icons
    local function RefreshAllButtons()
        for _, button in pairs(shelf.buttons) do
            pcall(function()
                if button.UpdateAction then
                    button:UpdateAction()
                elseif button.Update then
                    button:Update()
                elseif ActionButton_Update then
                    ActionButton_Update(button)
                end
            end)
        end
    end

    RefreshAllButtons()

    -- Also refresh every time the popup opens (icons may go stale
    -- while the popup is hidden due to Blizzard's event handlers)
    shelf.popup:HookScript("OnShow", function()
        C_Timer.After(0, function()
            if not InCombatLockdown() then
                RefreshAllButtons()
            end
        end)
    end)

    -- Watchdog: Blizzard's update code may hide icons/hotkeys on mouseover.
    -- Texture/FontString ops are safe in combat (not secure objects).
    local popup = shelf.popup
    local buttons = shelf.buttons
    -- Watchdog: only fix button FRAME visibility and parenting.
    -- Do NOT touch icon/hotkey/textures — Blizzard manages those correctly
    -- (hiding icons on empty slots, showing them on filled ones).
    popup:SetScript("OnUpdate", function()
        if InCombatLockdown() then return end
        for _, btn in pairs(buttons) do
            if btn and btn._barshelfManaged then
                if btn:GetParent() ~= popup then btn:SetParent(popup) end
                if not btn:IsShown() then btn:Show() end
            end
        end
    end)

    -- Hide the original Blizzard bar frame
    if info.frame then
        local barFrame = _G[info.frame]
        if barFrame then
            shelf.hiddenBarFrame = barFrame
            shelf.barFrameWasShown = barFrame:IsShown()
            barFrame:Hide()
            RegisterStateDriver(barFrame, "visibility", "hide")
        end
    end
end

---------------------------------------------------------------------------
-- Layout bar buttons in a grid. Uses SetScale to resize Blizzard buttons
-- uniformly (icon, border, cooldown all scale together).
---------------------------------------------------------------------------
local BAR_POPUP_INSET = 4

function Barshelf:LayoutBarPopup(shelf)
    if InCombatLockdown() then
        self:QueueForCombat(function() self:LayoutBarPopup(shelf) end)
        return
    end

    local config  = shelf.config
    local popup   = shelf.popup
    local buttons = shelf.buttons
    local numRows = config.numRows        or 1
    local cols    = math.ceil((config.numButtons or 12) / math.max(numRows, 1))
    local num     = config.numButtons    or 12
    local bpad    = config.buttonPadding or 2

    -- Read the first button's native size
    local nativeSize = 36
    for i = 1, num do
        if buttons[i] then
            nativeSize = math.max(buttons[i]:GetWidth(), buttons[i]:GetHeight())
            break
        end
    end

    -- Scale the POPUP frame itself (like Bartender4 does).
    -- Buttons are positioned at native coordinates inside it.
    -- This avoids SetScale/SetPoint offset confusion on individual buttons.
    local targetSize = config.buttonSize or nativeSize
    local popupScale = targetSize / nativeSize

    local stride = nativeSize + bpad
    local rows   = math.ceil(math.max(num, 1) / cols)

    popup:SetScale(popupScale)
    popup:SetSize(
        cols * stride - bpad + BAR_POPUP_INSET * 2,
        rows * stride - bpad + BAR_POPUP_INSET * 2
    )

    -- Resolve row order: per-shelf override > global setting > auto-detected
    local rowOrder = config.rowOrder or Barshelf.db.barRowOrder or "auto"
    local bottomUp
    if rowOrder == "bottomup" then
        bottomUp = true
    elseif rowOrder == "topdown" then
        bottomUp = false
    else -- "auto": use what was detected from Blizzard's layout
        bottomUp = config.bottomUp or false
    end

    for i = 1, #buttons do
        local button = buttons[i]
        if not button then
        elseif i <= num then
            local row = math.floor((i - 1) / cols)
            if bottomUp then row = rows - 1 - row end
            local col = (i - 1) % cols
            local x =  BAR_POPUP_INSET + col * stride
            local y = -BAR_POPUP_INSET - row * stride

            button:SetParent(popup)
            button:SetScale(1)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", popup, "TOPLEFT", x, y)
            button:Show()
        else
            button:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Deactivate: return buttons to their original parent
---------------------------------------------------------------------------
function Barshelf:DeactivateBarShelf(shelf)
    if InCombatLockdown() then
        self:QueueForCombat(function() self:DeactivateBarShelf(shelf) end)
        return
    end

    -- Restore the original Blizzard bar frame
    if shelf.hiddenBarFrame then
        UnregisterStateDriver(shelf.hiddenBarFrame, "visibility")
        if shelf.barFrameWasShown then
            shelf.hiddenBarFrame:Show()
        end
        shelf.hiddenBarFrame = nil
        shelf.barFrameWasShown = nil
    end

    -- Remove watchdog and reset popup scale
    shelf.popup:SetScript("OnUpdate", nil)
    shelf.popup:SetScale(1)

    for i = 1, #shelf.buttons do
        local button = shelf.buttons[i]
        if button then
            button._barshelfManaged = nil
            UnregisterStateDriver(button, "visibility")
            button:SetScale(shelf.originalScales[i] or 1)
            local origParent = shelf.originalParents[i]
            if origParent then
                button:SetParent(origParent)
            end
            local origPt = shelf.originalPoints[i]
            if origPt then
                button:ClearAllPoints()
                button:SetPoint(unpack(origPt))
            end
        end
    end

    wipe(shelf.buttons)
    wipe(shelf.originalParents)
    wipe(shelf.originalPoints)
    wipe(shelf.originalScales)
end
