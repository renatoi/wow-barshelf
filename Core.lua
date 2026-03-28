Barshelf = LibStub("AceAddon-3.0"):NewAddon("Barshelf", "AceConsole-3.0", "AceEvent-3.0")

Barshelf.version = "1.1.0"
Barshelf.docks = {} -- dockID -> dock frame
Barshelf.shelves = {} -- ordered list of active shelf objects
Barshelf.combatQueue = {}
Barshelf.inCombat = false

---------------------------------------------------------------------------
-- Bar-to-button mapping
---------------------------------------------------------------------------
Barshelf.BAR_INFO = {
  [1] = { prefix = "ActionButton", count = 12, label = "Action Bar 1", frame = "MainMenuBar" },
  [2] = { prefix = "MultiBarBottomLeftButton", count = 12, label = "Action Bar 2", frame = "MultiBarBottomLeft" },
  [3] = { prefix = "MultiBarRightButton", count = 12, label = "Action Bar 3", frame = "MultiBarRight" },
  [4] = { prefix = "MultiBarLeftButton", count = 12, label = "Action Bar 4", frame = "MultiBarLeft" },
  [5] = { prefix = "MultiBarBottomRightButton", count = 12, label = "Action Bar 5", frame = "MultiBarBottomRight" },
  [6] = { prefix = "MultiBar5Button", count = 12, label = "Action Bar 6", frame = "MultiBar5" },
  [7] = { prefix = "MultiBar6Button", count = 12, label = "Action Bar 7", frame = "MultiBar6" },
  [8] = { prefix = "MultiBar7Button", count = 12, label = "Action Bar 8", frame = "MultiBar7" },
}

---------------------------------------------------------------------------
-- Saved variable defaults (AceDB format)
---------------------------------------------------------------------------
local defaults = {
  profile = {
    closeOthers = true,
    showMinimap = true,
    animatePopups = true,
    animationDuration = 0.15,
    dockIdleAlpha = 1.0,
    dockFadeDuration = 0.3,
    stackPopups = true,
    dockBgAlpha = 0.75,
    dockBorderAlpha = 0.8,
    dockShowBorder = true,
    dockPadding = 4,
    popupBgAlpha = 0.92,
    handleBgAlpha = 0.85,
    handleIconSize = 16,
    handleFontSize = 12,
    barRowOrder = "auto",
    barIconSize = nil,
    barIconPadding = nil,
    docks = {
      { id = 1, name = "Main", point = nil, orientation = "HORIZONTAL" },
    },
    shelves = {},
    nextDockID = 2,
    nextShelfID = 1,
    minimap = { hide = false },
  },
}

---------------------------------------------------------------------------
-- SavedVariable migration (pre-AceDB -> AceDB)
---------------------------------------------------------------------------
function Barshelf:MigrateOldDB()
  if not BarshelfDB then
    return
  end
  if BarshelfDB.profiles then
    return
  end -- already AceDB
  local old = BarshelfDB
  local charKey = UnitName("player") .. " - " .. GetRealmName()
  BarshelfDB = {
    profileKeys = { [charKey] = charKey },
    profiles = { [charKey] = old },
  }
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
  if self._closingPopups then
    return
  end
  self._closingPopups = true
  for _, shelf in ipairs(self.shelves) do
    if shelf.popup and shelf.popup:IsShown() then
      shelf.popup:Hide()
    end
  end
  if self.backdrop then
    self.backdrop:Hide()
  end
  if self.escHelper then
    self.escHelper:Hide()
  end
  self._closingPopups = false
end

function Barshelf:AnyPopupShown()
  for _, shelf in ipairs(self.shelves) do
    if shelf.popup and shelf.popup:IsShown() then
      return true
    end
  end
  return false
end

function Barshelf:AnyDockPopupShown(dockID)
  for _, shelf in ipairs(self.shelves) do
    if (shelf.config.dockID or 1) == dockID and shelf.popup and shelf.popup:IsShown() then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Secure frame refs (close-others wiring)
---------------------------------------------------------------------------
function Barshelf:UpdateAllSecureRefs()
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:UpdateAllSecureRefs()
    end)
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
      shelf.handle:SetAttribute("closeOthers", self.db.profile.closeOthers)
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
    if GetTime() - (self.showTime or 0) < 0.15 then
      return
    end
    if not InCombatLockdown() then
      Barshelf:CloseAllPopups()
    end
  end)
  self.backdrop = f

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
  if not shelf then
    return
  end

  table.insert(self.shelves, shelf)
  local dock = self.docks[config.dockID or 1]
  if dock then
    dock:AddShelf(shelf)
  end
  return shelf
end

---------------------------------------------------------------------------
-- Rebuild everything from saved config
---------------------------------------------------------------------------
function Barshelf:RebuildAll()
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:RebuildAll()
    end)
    return
  end
  self:TeardownAll()

  for _, dockCfg in ipairs(self.db.profile.docks) do
    self:CreateDock(dockCfg)
  end
  for i, shelfCfg in ipairs(self.db.profile.shelves) do
    if shelfCfg.enabled then
      self:CreateShelf(shelfCfg, i)
    end
  end
  self:UpdateAllSecureRefs()
end

function Barshelf:TeardownAll()
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:TeardownAll()
    end)
    return
  end
  for _, shelf in ipairs(self.shelves) do
    if shelf.type == "bar" then
      self:DeactivateBarShelf(shelf)
    elseif shelf.type == "custom" then
      self:DeactivateCustomShelf(shelf)
    end
    if shelf.handle then
      shelf.handle:Hide()
    end
    if shelf.popup then
      shelf.popup:Hide()
    end
  end
  wipe(self.shelves)
  for id, dock in pairs(self.docks) do
    dock:Hide()
  end
  wipe(self.docks)
end

---------------------------------------------------------------------------
-- Add / remove helpers for config
---------------------------------------------------------------------------
function Barshelf:AddBarShelf(barID, dockID)
  for _, cfg in ipairs(self.db.profile.shelves) do
    if cfg.type == "bar" and cfg.barID == barID and cfg.enabled then
      self:Print("Bar " .. barID .. " is already on a shelf.")
      return nil
    end
  end
  local info = self.BAR_INFO[barID]

  local visibleCount, rowCount, btnSize, btnPadding = 12, 1, 36, 2
  if info then
    visibleCount = 0
    for i = 1, info.count do
      local btn = _G[info.prefix .. i]
      if btn and btn:IsShown() then
        visibleCount = visibleCount + 1
      end
    end
    if visibleCount == 0 then
      visibleCount = info.count
    end

    local ys = {}
    for i = 1, visibleCount do
      local btn = _G[info.prefix .. i]
      if btn then
        local _, by = btn:GetCenter()
        if by then
          local found = false
          for _, ey in ipairs(ys) do
            if math.abs(by - ey) < 3 then
              found = true
              break
            end
          end
          if not found then
            ys[#ys + 1] = by
          end
        end
      end
    end
    rowCount = math.max(#ys, 1)

    local firstBtn = _G[info.prefix .. "1"]
    if firstBtn then
      local w = firstBtn:GetWidth()
      if w and w > 10 then
        btnSize = math.floor(w + 0.5)
      end
    end
    local btn1, btn2 = _G[info.prefix .. "1"], _G[info.prefix .. "2"]
    if btn1 and btn2 then
      local x1 = btn1:GetLeft()
      local x2 = btn2:GetLeft()
      if x1 and x2 then
        local gap = math.abs(x2 - x1) - btnSize
        if gap >= 0 and gap < 20 then
          btnPadding = math.floor(gap + 0.5)
        end
      end
    end
  end

  local cols = math.ceil(visibleCount / rowCount)

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
    iconSize = self.db.profile.handleIconSize or 16,
    labelFontSize = self.db.profile.handleFontSize or 12,
    numButtons = visibleCount,
    numRows = rowCount,
    buttonSize = self.db.profile.barIconSize or btnSize,
    buttonPadding = self.db.profile.barIconPadding or btnPadding,
    popupAnchor = "AUTO",
    bottomUp = bottomUp,
  }
  table.insert(self.db.profile.shelves, cfg)
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
    iconSize = self.db.profile.handleIconSize or 16,
    labelFontSize = self.db.profile.handleFontSize or 12,
    numButtons = 6,
    numRows = 1,
    buttonSize = 36,
    buttonPadding = 2,
    popupAnchor = "AUTO",
    buttons = {},
  }
  table.insert(self.db.profile.shelves, cfg)
  self:RebuildAll()
  return cfg
end

function Barshelf:RemoveShelf(index)
  if not self.db.profile.shelves[index] then
    return
  end
  table.remove(self.db.profile.shelves, index)
  self:RebuildAll()
end

function Barshelf:AddDock(name)
  local id = self.db.profile.nextDockID
  self.db.profile.nextDockID = id + 1
  local cfg = { id = id, name = name or ("Dock " .. id), point = nil, orientation = "HORIZONTAL" }
  table.insert(self.db.profile.docks, cfg)
  self:RebuildAll()
  return cfg
end

function Barshelf:RemoveDock(dockID)
  if dockID == 1 then
    self:Print("Cannot remove the default dock.")
    return
  end
  for _, cfg in ipairs(self.db.profile.shelves) do
    if cfg.dockID == dockID then
      cfg.dockID = 1
    end
  end
  for i, d in ipairs(self.db.profile.docks) do
    if d.id == dockID then
      table.remove(self.db.profile.docks, i)
      break
    end
  end
  self:RebuildAll()
end

function Barshelf:ResetAllDockPositions()
  for _, dockCfg in ipairs(self.db.profile.docks) do
    dockCfg.point = nil
  end
  self:RebuildAll()
end

---------------------------------------------------------------------------
-- AceAddon lifecycle
---------------------------------------------------------------------------
function Barshelf:OnInitialize()
  self:MigrateOldDB()
  self.db = LibStub("AceDB-3.0"):New("BarshelfDB", defaults, true)

  -- Ensure critical tables exist (profile copy/reset may not create them)
  local p = self.db.profile
  if not p.docks or #p.docks == 0 then
    p.docks = { { id = 1, name = "Main", point = nil, orientation = "HORIZONTAL" } }
  end
  if not p.shelves then
    p.shelves = {}
  end
  if not p.minimap then
    p.minimap = { hide = false }
  end

  local function onProfileChanged()
    local pr = self.db.profile
    if not pr.docks or #pr.docks == 0 then
      pr.docks = { { id = 1, name = "Main", point = nil, orientation = "HORIZONTAL" } }
    end
    if not pr.shelves then
      pr.shelves = {}
    end
    if not pr.minimap then
      pr.minimap = { hide = false }
    end
    self:RebuildAll()
  end
  self.db.RegisterCallback(self, "OnProfileChanged", onProfileChanged)
  self.db.RegisterCallback(self, "OnProfileCopied", onProfileChanged)
  self.db.RegisterCallback(self, "OnProfileReset", onProfileChanged)

  self:RegisterChatCommand("barshelf", "ChatCommand")
  self:RegisterChatCommand("bs", "ChatCommand")

  if self.SetupOptions then
    self:SetupOptions()
  end

  self:Print("Loaded. Type /bs to open settings.")
end

function Barshelf:OnEnable()
  self:CreateBackdrop()

  for _, dockCfg in ipairs(self.db.profile.docks) do
    self:CreateDock(dockCfg)
  end
  for i, shelfCfg in ipairs(self.db.profile.shelves) do
    if shelfCfg.enabled then
      self:CreateShelf(shelfCfg, i)
    end
  end

  self:UpdateAllSecureRefs()
  self:SetupMinimapIcon()

  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")

  -- Show original bars in Edit Mode so users can configure Blizzard's settings
  if EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnShow", function()
      Barshelf:OnEditModeEnter()
    end)
    EditModeManagerFrame:HookScript("OnHide", function()
      Barshelf:OnEditModeExit()
    end)
  end
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
function Barshelf:PLAYER_REGEN_DISABLED()
  self.inCombat = true
end

function Barshelf:PLAYER_REGEN_ENABLED()
  self.inCombat = false
  self:ProcessCombatQueue()
end

function Barshelf:OnEditModeEnter()
  -- Temporarily restore original Blizzard bars so Edit Mode can configure them
  for _, shelf in ipairs(self.shelves) do
    if shelf.type == "bar" and shelf.hiddenBarFrame then
      UnregisterStateDriver(shelf.hiddenBarFrame, "visibility")
      shelf.hiddenBarFrame:Show()
    end
  end
end

function Barshelf:OnEditModeExit()
  -- Re-hide Blizzard bars that our shelves replace
  for _, shelf in ipairs(self.shelves) do
    if shelf.type == "bar" and shelf.hiddenBarFrame then
      shelf.hiddenBarFrame:Hide()
      RegisterStateDriver(shelf.hiddenBarFrame, "visibility", "hide")
    end
  end
  -- Rebuild to pick up any Edit Mode changes (icon count, size, etc.)
  self:RebuildAll()
end

---------------------------------------------------------------------------
-- Slash command handler
---------------------------------------------------------------------------
function Barshelf:ChatCommand(msg)
  msg = strtrim(msg):lower()
  if msg == "reset" then
    self:ResetAllDockPositions()
    self:Print("Dock positions reset.")
  elseif msg == "rebuild" then
    self:RebuildAll()
    self:Print("Rebuilt.")
  else
    self:ToggleConfig()
  end
end

---------------------------------------------------------------------------
-- Config toggle
---------------------------------------------------------------------------
function Barshelf:ToggleConfig()
  if InCombatLockdown() then
    self:Print("Cannot open settings in combat.")
    return
  end
  if self.openOptions then
    self:openOptions()
  end
end
