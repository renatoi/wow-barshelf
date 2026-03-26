local ADDON_NAME, Barshelf = ...
_G.Barshelf = Barshelf

Barshelf.version = "1.0.0"
Barshelf.docks = {}        -- dockID -> dock frame
Barshelf.shelves = {}      -- ordered list of active shelf objects
Barshelf.combatQueue = {}
Barshelf.inCombat = false

---------------------------------------------------------------------------
-- Bar-to-button mapping
---------------------------------------------------------------------------
Barshelf.BAR_INFO = {
    [1] = { prefix = "ActionButton",              count = 12, label = "Action Bar 1", frame = "MainMenuBar" },
    [2] = { prefix = "MultiBarBottomLeftButton",  count = 12, label = "Action Bar 2", frame = "MultiBarBottomLeft" },
    [3] = { prefix = "MultiBarRightButton",       count = 12, label = "Action Bar 3", frame = "MultiBarRight" },
    [4] = { prefix = "MultiBarLeftButton",        count = 12, label = "Action Bar 4", frame = "MultiBarLeft" },
    [5] = { prefix = "MultiBarBottomRightButton", count = 12, label = "Action Bar 5", frame = "MultiBarBottomRight" },
    [6] = { prefix = "MultiBar5Button",           count = 12, label = "Action Bar 6", frame = "MultiBar5" },
    [7] = { prefix = "MultiBar6Button",           count = 12, label = "Action Bar 7", frame = "MultiBar6" },
    [8] = { prefix = "MultiBar7Button",           count = 12, label = "Action Bar 8", frame = "MultiBar7" },
}

---------------------------------------------------------------------------
-- Saved variable defaults
---------------------------------------------------------------------------
local DEFAULTS = {
    closeOthers = true,
    showMinimap = true,
    animatePopups = true,
    animationDuration = 0.15,
    dockBgAlpha = 0.75,
    dockBorderAlpha = 0.8,
    dockShowBorder = true,
    dockPadding = 4,
    popupBgAlpha = 0.92,
    handleBgAlpha = 0.85,
    handleIconSize = 16,
    handleFontSize = 12,
    barRowOrder = "auto",  -- "auto" (detect from Blizzard), "topdown", "bottomup"
    barIconSize = nil,     -- nil = use Blizzard's native size per bar
    barIconPadding = nil,  -- nil = use Blizzard's native padding per bar
    docks = {
        { id = 1, name = "Main", point = nil, orientation = "HORIZONTAL" },
    },
    shelves = {},
    nextDockID = 2,
    nextShelfID = 1,
    minimap = { hide = false },
}

---------------------------------------------------------------------------
-- Utility
---------------------------------------------------------------------------
local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[k] = DeepCopy(v) end
    return copy
end

local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = DeepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" and not v[1] then
            MergeDefaults(target[k], v)
        end
    end
end

---------------------------------------------------------------------------
-- Combat queue
---------------------------------------------------------------------------
function Barshelf:QueueForCombat(fn)
    if self.inCombat or InCombatLockdown() then
        table.insert(self.combatQueue, fn)
    else
        fn()
    end
end

function Barshelf:ProcessCombatQueue()
    local queue = self.combatQueue
    self.combatQueue = {}
    for _, fn in ipairs(queue) do
        fn()
    end
end

---------------------------------------------------------------------------
-- Popup helpers
---------------------------------------------------------------------------
function Barshelf:CloseAllPopups()
    if self._closingPopups then return end
    self._closingPopups = true
    for _, shelf in ipairs(self.shelves) do
        if shelf.popup and shelf.popup:IsShown() then
            shelf.popup:Hide()
        end
    end
    if self.backdrop then self.backdrop:Hide() end
    if self.escHelper then self.escHelper:Hide() end
    self._closingPopups = false
end

function Barshelf:AnyPopupShown()
    for _, shelf in ipairs(self.shelves) do
        if shelf.popup and shelf.popup:IsShown() then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Secure frame refs (close-others wiring)
---------------------------------------------------------------------------
function Barshelf:UpdateAllSecureRefs()
    if InCombatLockdown() then
        self:QueueForCombat(function() self:UpdateAllSecureRefs() end)
        return
    end

    local allShelves = self.shelves
    for _, shelf in ipairs(allShelves) do
        if shelf.handle then
            local count = 0
            for _, other in ipairs(allShelves) do
                if other ~= shelf and other.popup then
                    count = count + 1
                    shelf.handle:SetFrameRef("otherpopup" .. count, other.popup)
                end
            end
            shelf.handle:SetAttribute("otherpopupcount", count)
            shelf.handle:SetAttribute("closeOthers", self.db.closeOthers)
        end
    end
end

---------------------------------------------------------------------------
-- Backdrop (click-outside-to-close, out of combat only)
---------------------------------------------------------------------------
function Barshelf:CreateBackdrop()
    local f = CreateFrame("Button", "BarshelfBackdrop", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(0)
    f:EnableMouse(true)
    f:RegisterForClicks("AnyUp")
    f:Hide()
    f:SetScript("OnShow", function(self)
        self.showTime = GetTime()
    end)
    f:SetScript("OnClick", function(self)
        -- Ignore clicks that arrive in the same frame as the backdrop showing,
        -- prevents the click that opened the popup from immediately closing it
        if GetTime() - (self.showTime or 0) < 0.15 then return end
        if not InCombatLockdown() then
            Barshelf:CloseAllPopups()
        end
    end)
    self.backdrop = f

    -- ESC-to-close helper: shown while any popup is open,
    -- WoW's ESC handler hides it which triggers CloseAllPopups
    local esc = CreateFrame("Frame", "BarshelfEscHelper", UIParent)
    esc:Hide()
    esc:SetScript("OnHide", function()
        if not Barshelf._closingPopups and not InCombatLockdown() then
            Barshelf:CloseAllPopups()
        end
    end)
    tinsert(UISpecialFrames, "BarshelfEscHelper")
    self.escHelper = esc
end

---------------------------------------------------------------------------
-- Shelf creation dispatcher
---------------------------------------------------------------------------
function Barshelf:CreateShelf(config, index)
    local shelf
    if config.type == "bar" then
        shelf = self:CreateBarShelf(config, index)
    elseif config.type == "custom" then
        shelf = self:CreateCustomShelf(config, index)
    end
    if not shelf then return end

    table.insert(self.shelves, shelf)
    local dock = self.docks[config.dockID or 1]
    if dock then dock:AddShelf(shelf) end
    return shelf
end

---------------------------------------------------------------------------
-- Rebuild everything from saved config
---------------------------------------------------------------------------
function Barshelf:RebuildAll()
    if InCombatLockdown() then
        self:QueueForCombat(function() self:RebuildAll() end)
        return
    end
    self:TeardownAll()

    for _, dockCfg in ipairs(self.db.docks) do
        self:CreateDock(dockCfg)
    end
    for i, shelfCfg in ipairs(self.db.shelves) do
        if shelfCfg.enabled then
            self:CreateShelf(shelfCfg, i)
        end
    end
    self:UpdateAllSecureRefs()
end

function Barshelf:TeardownAll()
    if InCombatLockdown() then
        self:QueueForCombat(function() self:TeardownAll() end)
        return
    end
    -- Deactivate shelves
    for _, shelf in ipairs(self.shelves) do
        if shelf.type == "bar" then
            self:DeactivateBarShelf(shelf)
        elseif shelf.type == "custom" then
            self:DeactivateCustomShelf(shelf)
        end
        if shelf.handle then shelf.handle:Hide() end
        if shelf.popup then shelf.popup:Hide() end
    end
    wipe(self.shelves)
    -- Hide docks
    for id, dock in pairs(self.docks) do
        dock:Hide()
    end
    wipe(self.docks)
end

---------------------------------------------------------------------------
-- Add / remove helpers for config
---------------------------------------------------------------------------
function Barshelf:AddBarShelf(barID, dockID)
    -- Prevent duplicate bar assignment
    for _, cfg in ipairs(self.db.shelves) do
        if cfg.type == "bar" and cfg.barID == barID and cfg.enabled then
            print("|cff00ccffBarshelf:|r Bar " .. barID .. " is already on a shelf.")
            return nil
        end
    end
    local info = self.BAR_INFO[barID]

    -- Auto-detect Blizzard's Edit Mode configuration from button state
    local visibleCount, rowCount, btnSize, btnPadding = 12, 1, 36, 2
    if info then
        -- Count visible buttons (respects "# of Icons")
        visibleCount = 0
        for i = 1, info.count do
            local btn = _G[info.prefix .. i]
            if btn and btn:IsShown() then visibleCount = visibleCount + 1 end
        end
        if visibleCount == 0 then visibleCount = info.count end

        -- Detect rows from distinct Y positions (respects "# of Rows")
        local ys = {}
        for i = 1, visibleCount do
            local btn = _G[info.prefix .. i]
            if btn then
                local _, by = btn:GetCenter()
                if by then
                    local found = false
                    for _, ey in ipairs(ys) do
                        if math.abs(by - ey) < 3 then found = true; break end
                    end
                    if not found then ys[#ys + 1] = by end
                end
            end
        end
        rowCount = math.max(#ys, 1)

        -- Read icon size and padding from first button (respects "Icon Size" / "Icon Padding")
        local firstBtn = _G[info.prefix .. "1"]
        if firstBtn then
            local w = firstBtn:GetWidth()
            if w and w > 0 then btnSize = math.floor(w + 0.5) end
        end
        -- Detect padding from gap between first two buttons
        local btn1, btn2 = _G[info.prefix .. "1"], _G[info.prefix .. "2"]
        if btn1 and btn2 then
            local x1 = btn1:GetLeft()
            local x2 = btn2:GetLeft()
            if x1 and x2 then
                local gap = math.abs(x2 - x1) - btnSize
                if gap >= 0 and gap < 20 then btnPadding = math.floor(gap + 0.5) end
            end
        end
    end

    local cols = math.ceil(visibleCount / rowCount)

    -- Detect if Blizzard lays out rows bottom-up (common for bottom-anchored bars)
    local bottomUp = false
    if rowCount > 1 and cols > 0 and info then
        local btn1 = _G[info.prefix .. "1"]
        local btnNextRow = _G[info.prefix .. (cols + 1)]
        if btn1 and btnNextRow then
            local _, y1 = btn1:GetCenter()
            local _, y2 = btnNextRow:GetCenter()
            if y1 and y2 and y1 < y2 then
                bottomUp = true
            end
        end
    end

    local cfg = {
        type = "bar",
        barID = barID,
        dockID = dockID or 1,
        enabled = true,
        label = info and info.label or ("Bar " .. barID),
        displayMode = "both",
        iconSize = self.db.handleIconSize or 16,
        labelFontSize = self.db.handleFontSize or 12,
        numButtons = visibleCount,
        numRows = rowCount,
        buttonSize = self.db.barIconSize or btnSize,
        buttonPadding = self.db.barIconPadding or btnPadding,
        popupAnchor = "AUTO",
        bottomUp = bottomUp,
    }
    table.insert(self.db.shelves, cfg)
    self:RebuildAll()
    return cfg
end

function Barshelf:AddCustomShelf(label, dockID)
    local cfg = {
        type = "custom",
        dockID = dockID or 1,
        enabled = true,
        label = label or "Custom",
        displayMode = "both",
        iconSize = self.db.handleIconSize or 16,
        labelFontSize = self.db.handleFontSize or 12,
        numButtons = 6,
        numRows = 1,
        buttonSize = 36,
        buttonPadding = 2,
        popupAnchor = "AUTO",
        buttons = {},
    }
    table.insert(self.db.shelves, cfg)
    self:RebuildAll()
    return cfg
end

function Barshelf:RemoveShelf(index)
    if not self.db.shelves[index] then return end
    table.remove(self.db.shelves, index)
    self:RebuildAll()
end

function Barshelf:AddDock(name)
    local id = self.db.nextDockID
    self.db.nextDockID = id + 1
    local cfg = { id = id, name = name or ("Dock " .. id), point = nil, orientation = "HORIZONTAL" }
    table.insert(self.db.docks, cfg)
    self:RebuildAll()
    return cfg
end

function Barshelf:RemoveDock(dockID)
    if dockID == 1 then
        print("|cff00ccffBarshelf:|r Cannot remove the default dock.")
        return
    end
    -- Move shelves from removed dock to dock 1
    for _, cfg in ipairs(self.db.shelves) do
        if cfg.dockID == dockID then cfg.dockID = 1 end
    end
    for i, d in ipairs(self.db.docks) do
        if d.id == dockID then table.remove(self.db.docks, i); break end
    end
    self:RebuildAll()
end

function Barshelf:ResetAllDockPositions()
    for _, dockCfg in ipairs(self.db.docks) do
        dockCfg.point = nil
    end
    self:RebuildAll()
end

---------------------------------------------------------------------------
-- Init & Events
---------------------------------------------------------------------------
function Barshelf:Init()
    if not BarshelfDB then
        BarshelfDB = DeepCopy(DEFAULTS)
    end
    self.db = BarshelfDB
    MergeDefaults(self.db, DEFAULTS)
end

function Barshelf:Setup()
    self:CreateBackdrop()

    for _, dockCfg in ipairs(self.db.docks) do
        self:CreateDock(dockCfg)
    end
    for i, shelfCfg in ipairs(self.db.shelves) do
        if shelfCfg.enabled then
            self:CreateShelf(shelfCfg, i)
        end
    end

    self:UpdateAllSecureRefs()
    self:SetupMinimapIcon()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        Barshelf:Init()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        Barshelf:Setup()
        eventFrame:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_REGEN_DISABLED" then
        Barshelf.inCombat = true
        -- Close config panel if open
        if Barshelf.configFrame and Barshelf.configFrame:IsShown() then
            Barshelf.configFrame:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        Barshelf.inCombat = false
        Barshelf:ProcessCombatQueue()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_BARSHELF1 = "/barshelf"
SLASH_BARSHELF2 = "/bs"
SlashCmdList["BARSHELF"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "reset" then
        Barshelf:ResetAllDockPositions()
        print("|cff00ccffBarshelf:|r Dock positions reset.")
    elseif msg == "rebuild" then
        Barshelf:RebuildAll()
        print("|cff00ccffBarshelf:|r Rebuilt.")
    else
        Barshelf:ToggleConfig()
    end
end
