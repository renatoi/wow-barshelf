Barshelf = LibStub("AceAddon-3.0"):NewAddon("Barshelf", "AceConsole-3.0", "AceEvent-3.0")
local L = Barshelf_L

Barshelf.version = "1.2.1"
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
    clickOutsideToClose = true,
    centerPopupsOnDock = false,
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
    defaultPopupAnchor = "AUTO",
    defaultDisplayMode = "both",
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
-- SavedVariable migration
-- v1.0-v1.1 used SavedVariablesPerCharacter: BarshelfDB
-- v1.2+ uses SavedVariables: BarshelfGlobalDB (account-wide for AceDB profiles)
-- The .toc still declares BarshelfDB as PerCharacter so WoW loads the old file.
---------------------------------------------------------------------------
function Barshelf:MigrateOldDB()
  -- Nothing to migrate
  if not BarshelfDB or not next(BarshelfDB) then
    return
  end
  -- Already migrated on a previous login
  if BarshelfDB._migrated then
    return
  end

  local charKey = UnitName("player") .. " - " .. GetRealmName()

  -- Normalize: pre-AceDB flat table → AceDB format
  local src = BarshelfDB
  if not src.profiles then
    src = {
      profileKeys = { [charKey] = charKey },
      profiles = { [charKey] = src },
    }
  end

  -- Copy into account-wide DB
  if not BarshelfGlobalDB then
    BarshelfGlobalDB = {}
  end
  if not BarshelfGlobalDB.profiles then
    BarshelfGlobalDB.profiles = {}
  end
  if not BarshelfGlobalDB.profileKeys then
    BarshelfGlobalDB.profileKeys = {}
  end

  -- Find this character's profile data from the old DB
  local oldProfileName = src.profileKeys[charKey]
  local profileData = oldProfileName and src.profiles[oldProfileName]

  if profileData then
    -- Always store under the character's own name (not "Default")
    -- so each character gets an independent copy after migration
    if not BarshelfGlobalDB.profiles[charKey] or not next(BarshelfGlobalDB.profiles[charKey]) then
      BarshelfGlobalDB.profiles[charKey] = profileData
    end
    BarshelfGlobalDB.profileKeys[charKey] = charKey
  end

  -- Mark migrated (don't wipe — keeps data as fallback)
  BarshelfDB._migrated = true
  self:Print(L["Migrated shelves for %s."]:format(charKey))
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
    if shelf.popup and shelf.popup:IsShown() and not shelf.config.pinned then
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
  self._popupZCounter = 10
end

function Barshelf:AnyPopupShown()
  for _, shelf in ipairs(self.shelves) do
    if shelf.popup and shelf.popup:IsShown() and not shelf.config.pinned and shelf.config.type ~= "bags" then
      return true
    end
  end
  return false
end

function Barshelf:AnyDockPopupShown(dockID)
  for _, shelf in ipairs(self.shelves) do
    if
      (shelf.config.dockID or 1) == dockID
      and shelf.popup
      and shelf.popup:IsShown()
      and not shelf.config.pinned
      and shelf.config.type ~= "bags"
    then
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
        if other ~= shelf and other.popup and not other.config.pinned and other.config.type ~= "bags" then
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
  f:RegisterForClicks("LeftButtonUp")
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
  elseif config.type == "micro" then
    shelf = self:CreateMicroShelf(config, index)
  elseif config.type == "bags" then
    shelf = self:CreateBagShelf(config, index)
  elseif config.type == "status" then
    shelf = self:CreateStatusShelf(config, index)
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
  self:ShowPinnedPopups()
end

---------------------------------------------------------------------------
-- Show pinned popups at their saved positions
---------------------------------------------------------------------------
function Barshelf:ShowPinnedPopups()
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:ShowPinnedPopups()
    end)
    return
  end
  for _, shelf in ipairs(self.shelves) do
    if shelf.config.pinned and shelf.popup then
      shelf.popup:ClearAllPoints()
      local pt = shelf.config.pinnedPoint
      if pt then
        shelf.popup:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
      else
        self:UpdatePopupAnchor(shelf.popup)
      end
      shelf.popup:Show()
      self:SetupPopupPinning(shelf)
    end
  end
end

function Barshelf:TeardownAll()
  if InCombatLockdown() then
    self:QueueForCombat(function()
      self:TeardownAll()
    end)
    return
  end
  self._tearingDown = true
  for _, shelf in ipairs(self.shelves) do
    if shelf.type == "bar" then
      self:DeactivateBarShelf(shelf)
    elseif shelf.type == "custom" then
      self:DeactivateCustomShelf(shelf)
    elseif shelf.type == "micro" then
      self:DeactivateMicroShelf(shelf)
    elseif shelf.type == "bags" then
      self:DeactivateBagShelf(shelf)
    elseif shelf.type == "status" then
      self:DeactivateStatusShelf(shelf)
    end
    if shelf.handle then
      shelf.handle:Hide()
    end
    if shelf.popup then
      if shelf.popup._pinnedFadeTimer then
        shelf.popup._pinnedFadeTimer:Cancel()
        shelf.popup._pinnedFadeTimer = nil
      end
      shelf.popup:Hide()
    end
  end
  wipe(self.shelves)
  for id, dock in pairs(self.docks) do
    dock:Hide()
  end
  wipe(self.docks)
  self._tearingDown = false
end

---------------------------------------------------------------------------
-- Add / remove helpers for config
---------------------------------------------------------------------------
function Barshelf:AddBarShelf(barID, dockID)
  for _, cfg in ipairs(self.db.profile.shelves) do
    if cfg.type == "bar" and cfg.barID == barID and cfg.enabled then
      self:Print(L["Bar %d is already on a shelf."]:format(barID))
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

function Barshelf:AddMicroShelf(dockID)
  for _, cfg in ipairs(self.db.profile.shelves) do
    if cfg.type == "micro" and cfg.enabled then
      self:Print(L["Micro menu shelf already exists."])
      return nil
    end
  end
  local cfg = {
    type = "micro",
    dockID = dockID or 1,
    enabled = true,
    label = "Micro Menu",
    displayMode = "both",
    iconSize = self.db.profile.handleIconSize or 16,
    labelFontSize = self.db.profile.handleFontSize or 12,
    numRows = 1,
    buttonPadding = 0,
    popupAnchor = "AUTO",
  }
  table.insert(self.db.profile.shelves, cfg)
  self:RebuildAll()
  return cfg
end

function Barshelf:AddBagShelf(dockID)
  for _, cfg in ipairs(self.db.profile.shelves) do
    if cfg.type == "bags" and cfg.enabled then
      self:Print(L["Bags shelf already exists."])
      return nil
    end
  end
  local cfg = {
    type = "bags",
    dockID = dockID or 1,
    enabled = true,
    label = "$used/$total",
    displayMode = "both",
    iconSize = self.db.profile.handleIconSize or 16,
    labelFontSize = self.db.profile.handleFontSize or 12,
    numRows = 1,
    buttonPadding = 0,
    popupAnchor = "AUTO",
  }
  table.insert(self.db.profile.shelves, cfg)
  self:RebuildAll()
  return cfg
end

function Barshelf:AddStatusShelf(dockID)
  for _, cfg in ipairs(self.db.profile.shelves) do
    if cfg.type == "status" and cfg.enabled then
      self:Print(L["Status shelf already exists."])
      return nil
    end
  end
  local cfg = {
    type = "status",
    dockID = dockID or 1,
    enabled = true,
    label = "Lv$level $xp%",
    displayMode = "both",
    iconSize = self.db.profile.handleIconSize or 16,
    labelFontSize = self.db.profile.handleFontSize or 12,
    showXP = true,
    showRep = true,
    popupAnchor = "AUTO",
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
    self:Print(L["Cannot remove the default dock."])
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
  self.db = LibStub("AceDB-3.0"):New("BarshelfGlobalDB", defaults, true)

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

  self:Print(L["Loaded. Type /bs to open settings."])
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
  self:ShowPinnedPopups()
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
  -- Defer: Edit Mode opens via a protected panel manager call chain;
  -- UnregisterStateDriver/SetAttribute would be blocked if called inline.
  C_Timer.After(0, function()
    if InCombatLockdown() then
      return
    end
    for _, shelf in ipairs(self.shelves) do
      if shelf.type == "bar" and shelf.hiddenBarFrame then
        shelf.hiddenBarFrame._barshelfHidden = nil
        UnregisterStateDriver(shelf.hiddenBarFrame, "visibility")
        shelf.hiddenBarFrame:Show()
      end
      if shelf.type == "micro" and shelf.hiddenMicroContainer then
        UnregisterStateDriver(shelf.hiddenMicroContainer, "visibility")
        shelf.hiddenMicroContainer:Show()
      end
      if shelf.type == "bags" and shelf.hiddenBagContainer then
        UnregisterStateDriver(shelf.hiddenBagContainer, "visibility")
        shelf.hiddenBagContainer:Show()
      end
      if shelf.type == "status" and shelf.hiddenStatusContainer then
        pcall(function()
          shelf.hiddenStatusContainer:Show()
        end)
      end
      -- Hide pinned popups (their buttons are returned to Blizzard)
      if shelf.config.pinned and shelf.popup then
        shelf.popup:Hide()
      end
    end
  end)
end

function Barshelf:OnEditModeExit()
  -- Defer for same reason as OnEditModeEnter.
  -- RebuildAll re-activates all shelves which re-hides bar frames
  -- and sets _barshelfHidden, so no manual loop is needed here.
  C_Timer.After(0, function()
    if InCombatLockdown() then
      return
    end
    self:RebuildAll()
  end)
end

---------------------------------------------------------------------------
-- Slash command handler
---------------------------------------------------------------------------
function Barshelf:ChatCommand(msg)
  msg = strtrim(msg):lower()
  if msg == "reset" then
    self:ResetAllDockPositions()
    self:Print(L["Dock positions reset."])
  elseif msg == "rebuild" then
    self:RebuildAll()
    self:Print(L["Rebuilt."])
  else
    self:ToggleConfig()
  end
end

---------------------------------------------------------------------------
-- Config toggle
---------------------------------------------------------------------------
function Barshelf:ToggleConfig()
  if InCombatLockdown() then
    self:Print(L["Cannot open settings in combat."])
    return
  end
  if self.openOptions then
    self:openOptions()
  end
end
