local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")
local L = Barshelf_L

---------------------------------------------------------------------------
-- Status shelf: custom XP + reputation display in a popup.
-- Unlike bar/micro/bag shelves, this does NOT reparent Blizzard frames.
---------------------------------------------------------------------------

local STATUS_POPUP_WIDTH = 280
local STATUS_BAR_HEIGHT = 22
local STATUS_POPUP_INSET = 8
local STATUS_BAR_SPACING = 6

---------------------------------------------------------------------------
-- Reputation standing names (fallback when API doesn't provide them)
---------------------------------------------------------------------------
local STANDING_NAMES = {
  [1] = "Hated",
  [2] = "Hostile",
  [3] = "Unfriendly",
  [4] = "Neutral",
  [5] = "Friendly",
  [6] = "Honored",
  [7] = "Revered",
  [8] = "Exalted",
}

---------------------------------------------------------------------------
-- Create a styled StatusBar
---------------------------------------------------------------------------
local function CreateStatusBar(parent, r, g, b)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:GetStatusBarTexture():SetHorizTile(false)
  bar:SetStatusBarColor(r, g, b)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.1, 0.1, 0.1, 0.7)

  local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  border:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

  local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("CENTER")
  text:SetJustifyH("CENTER")
  bar.text = text

  return bar
end

---------------------------------------------------------------------------
-- Format number with commas (e.g. 12345 -> "12,345")
---------------------------------------------------------------------------
local function FormatNumber(n)
  local formatted = tostring(n)
  while true do
    local k
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then
      break
    end
  end
  return formatted
end

---------------------------------------------------------------------------
-- Template keyword system for status handle labels
---------------------------------------------------------------------------
function Barshelf:FormatStatusLabel(template)
  local level, xp, xpMax = 0, 0, 1
  pcall(function()
    level = UnitLevel("player") or 0
    xp = UnitXP("player") or 0
    xpMax = UnitXPMax("player") or 1
  end)

  local xpPct = xpMax > 0 and ((xp / xpMax) * 100) or 0

  local repName, repPct, repStanding = "", 0, ""
  pcall(function()
    local factionData = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if factionData and factionData.name then
      repName = factionData.name
      local current = factionData.currentReactionThreshold or 0
      local nextThresh = factionData.nextReactionThreshold or 0
      local standing = factionData.currentStanding or 0
      repStanding = factionData.reaction and STANDING_NAMES[factionData.reaction] or ""

      if nextThresh > current and nextThresh > 0 then
        repPct = ((standing - current) / (nextThresh - current)) * 100
      else
        repPct = 100
      end
    end
  end)

  local result = template
  result = result:gsub("%$xpCur", FormatNumber(xp))
  result = result:gsub("%$xpMax", FormatNumber(xpMax))
  result = result:gsub("%$xp", string.format("%.1f", xpPct))
  result = result:gsub("%$level", tostring(level))
  result = result:gsub("%$repName", repName)
  result = result:gsub("%$repStanding", repStanding)
  result = result:gsub("%$rep", string.format("%.1f", repPct))
  return result
end

function Barshelf:CreateStatusShelf(config, index)
  local shelf = {
    config = config,
    index = index,
    type = "status",
    buttons = {},
  }

  -- Apply defaults
  if config.showXP == nil then
    config.showXP = true
  end
  if config.showRep == nil then
    config.showRep = true
  end
  if not config.label or config.label == "Status" then
    config.label = "Lv$level $xp%"
  end

  shelf.popup = self:CreatePopup(shelf)
  self:BuildStatusContent(shelf)
  self:ActivateStatusShelf(shelf)
  return shelf
end

---------------------------------------------------------------------------
-- Build the custom popup content (XP bar + Rep bar)
---------------------------------------------------------------------------
function Barshelf:BuildStatusContent(shelf)
  local popup = shelf.popup
  local config = shelf.config

  -- XP bar
  local xpBar = CreateStatusBar(popup, 0.58, 0.0, 0.82)
  xpBar:SetSize(STATUS_POPUP_WIDTH - STATUS_POPUP_INSET * 2, STATUS_BAR_HEIGHT)
  xpBar:SetPoint("TOPLEFT", popup, "TOPLEFT", STATUS_POPUP_INSET, -STATUS_POPUP_INSET)
  shelf.xpBar = xpBar

  -- Watched rep bar
  local repBar = CreateStatusBar(popup, 0.0, 0.6, 0.1)
  repBar:SetSize(STATUS_POPUP_WIDTH - STATUS_POPUP_INSET * 2, STATUS_BAR_HEIGHT)
  shelf.repBar = repBar

  -- Extra tracked faction bars
  shelf.trackedBars = {}
  self:RebuildTrackedFactionBars(shelf)

  self:LayoutStatusPopup(shelf)
end

---------------------------------------------------------------------------
-- Create/rebuild bars for extra tracked factions
---------------------------------------------------------------------------
function Barshelf:RebuildTrackedFactionBars(shelf)
  -- Hide existing extra bars
  if shelf.trackedBars then
    for _, bar in ipairs(shelf.trackedBars) do
      bar:Hide()
    end
  end
  shelf.trackedBars = {}

  local factions = shelf.config.trackedFactions
  if not factions then
    return
  end

  for i, factionID in ipairs(factions) do
    -- Alternate colors for distinction
    local r, g, b
    if i % 3 == 1 then
      r, g, b = 0.0, 0.5, 0.7
    elseif i % 3 == 2 then
      r, g, b = 0.7, 0.5, 0.0
    else
      r, g, b = 0.5, 0.0, 0.7
    end
    local bar = CreateStatusBar(shelf.popup, r, g, b)
    bar:SetSize(STATUS_POPUP_WIDTH - STATUS_POPUP_INSET * 2, STATUS_BAR_HEIGHT)
    bar._factionID = factionID
    shelf.trackedBars[i] = bar
  end
end

---------------------------------------------------------------------------
-- Layout the status popup based on visibility settings
---------------------------------------------------------------------------
function Barshelf:LayoutStatusPopup(shelf)
  local config = shelf.config
  local popup = shelf.popup
  local xpBar = shelf.xpBar
  local repBar = shelf.repBar

  local showXP = config.showXP ~= false
  local showRep = config.showRep ~= false

  local level, maxLevel = 0, 0
  pcall(function()
    level = UnitLevel("player") or 0
    maxLevel = GetMaxPlayerLevel() or 0
  end)
  local atMaxLevel = maxLevel > 0 and level >= maxLevel

  -- Hide XP if at max level or user disabled it
  local xpVisible = showXP and not atMaxLevel
  xpBar:SetShown(xpVisible)

  repBar:SetShown(showRep)

  -- Position bars and size popup
  local height = STATUS_POPUP_INSET * 2
  local yOffset = -STATUS_POPUP_INSET

  if xpVisible then
    xpBar:ClearAllPoints()
    xpBar:SetPoint("TOPLEFT", popup, "TOPLEFT", STATUS_POPUP_INSET, yOffset)
    yOffset = yOffset - STATUS_BAR_HEIGHT - STATUS_BAR_SPACING
    height = height + STATUS_BAR_HEIGHT
  end

  if showRep then
    repBar:ClearAllPoints()
    repBar:SetPoint("TOPLEFT", popup, "TOPLEFT", STATUS_POPUP_INSET, yOffset)
    yOffset = yOffset - STATUS_BAR_HEIGHT - STATUS_BAR_SPACING
    height = height + STATUS_BAR_HEIGHT
    if xpVisible then
      height = height + STATUS_BAR_SPACING
    end
  end

  -- Extra tracked faction bars
  if shelf.trackedBars then
    for _, bar in ipairs(shelf.trackedBars) do
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT", popup, "TOPLEFT", STATUS_POPUP_INSET, yOffset)
      yOffset = yOffset - STATUS_BAR_HEIGHT - STATUS_BAR_SPACING
      height = height + STATUS_BAR_HEIGHT + STATUS_BAR_SPACING
      bar:Show()
    end
  end

  -- Minimum height if nothing shown
  if not xpVisible and not showRep and (not shelf.trackedBars or #shelf.trackedBars == 0) then
    height = STATUS_POPUP_INSET * 2 + STATUS_BAR_HEIGHT
  end

  popup:SetSize(STATUS_POPUP_WIDTH, height)
end

---------------------------------------------------------------------------
-- Activate: register events, start updates
---------------------------------------------------------------------------
function Barshelf:ActivateStatusShelf(shelf)
  -- Hide the original Blizzard status bars
  self:HideStatusBarContainer(shelf)

  -- Event frame for data updates
  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("PLAYER_XP_UPDATE")
  eventFrame:RegisterEvent("UPDATE_FACTION")
  eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
  eventFrame:RegisterEvent("UPDATE_EXPANSION_LEVEL")
  eventFrame:SetScript("OnEvent", function()
    self:UpdateStatusData(shelf)
  end)
  shelf._statusEventFrame = eventFrame

  -- Initial update (deferred to let handle be created)
  C_Timer.After(0.1, function()
    self:UpdateStatusData(shelf)
  end)
end

---------------------------------------------------------------------------
-- Hide the original Blizzard status bar container
---------------------------------------------------------------------------
function Barshelf:HideStatusBarContainer(shelf)
  local containerNames = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer" }
  for _, name in ipairs(containerNames) do
    local frame = _G[name]
    if frame and frame.Hide then
      shelf.hiddenStatusContainer = frame
      pcall(function()
        frame:Hide()
      end)
      return
    end
  end
end

---------------------------------------------------------------------------
-- Update XP and reputation data
---------------------------------------------------------------------------
function Barshelf:UpdateStatusData(shelf)
  local config = shelf.config

  -- XP data
  local xp, xpMax, level, maxLevel = 0, 1, 0, 0
  pcall(function()
    xp = UnitXP("player") or 0
    xpMax = UnitXPMax("player") or 1
    level = UnitLevel("player") or 0
    maxLevel = GetMaxPlayerLevel() or 0
  end)

  local atMaxLevel = maxLevel > 0 and level >= maxLevel

  if shelf.xpBar then
    if atMaxLevel then
      shelf.xpBar:SetMinMaxValues(0, 1)
      shelf.xpBar:SetValue(1)
      shelf.xpBar.text:SetText(L["Max Level"])
    else
      if xpMax > 0 then
        shelf.xpBar:SetMinMaxValues(0, xpMax)
        shelf.xpBar:SetValue(xp)
        local pct = (xp / xpMax) * 100
        shelf.xpBar.text:SetText(
          string.format(L["Level %d - %.1f%% (%s / %s)"], level, pct, FormatNumber(xp), FormatNumber(xpMax))
        )
      end
    end
  end

  -- Reputation data
  local repName, repPct, repText
  pcall(function()
    local factionData = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if factionData and factionData.name then
      repName = factionData.name
      local current = (factionData.currentReactionThreshold or 0)
      local nextThresh = (factionData.nextReactionThreshold or 0)
      local standing = factionData.currentStanding or 0

      local barMin = current
      local barMax = nextThresh
      local barVal = standing

      if barMax > barMin and barMax > 0 then
        local progress = barVal - barMin
        local range = barMax - barMin
        repPct = (progress / range) * 100

        local standingName = factionData.reaction and STANDING_NAMES[factionData.reaction] or ""
        repText = string.format("|cff88ff88*|r %s - %s %.0f%%", repName, standingName, repPct)

        if shelf.repBar then
          shelf.repBar:SetMinMaxValues(barMin, barMax)
          shelf.repBar:SetValue(barVal)
          shelf.repBar.text:SetText(repText)
        end
      else
        -- At max standing or no range
        if shelf.repBar then
          shelf.repBar:SetMinMaxValues(0, 1)
          shelf.repBar:SetValue(1)
          shelf.repBar.text:SetText(
            "|cff88ff88*|r " .. repName .. " - " .. (STANDING_NAMES[factionData.reaction] or "")
          )
        end
        repPct = 100
      end
    else
      if shelf.repBar then
        shelf.repBar:SetMinMaxValues(0, 1)
        shelf.repBar:SetValue(0)
        shelf.repBar.text:SetText(L["No tracked reputation"])
      end
    end
  end)

  -- Update extra tracked faction bars
  if shelf.trackedBars then
    for _, bar in ipairs(shelf.trackedBars) do
      pcall(function()
        local fData = C_Reputation.GetFactionDataByID(bar._factionID)
        if fData and fData.name then
          local cur = fData.currentReactionThreshold or 0
          local nxt = fData.nextReactionThreshold or 0
          local val = fData.currentStanding or 0
          local standingName = fData.reaction and STANDING_NAMES[fData.reaction] or ""

          if nxt > cur then
            bar:SetMinMaxValues(cur, nxt)
            bar:SetValue(val)
            local pct = ((val - cur) / (nxt - cur)) * 100
            bar.text:SetText(string.format("%s - %s %.0f%%", fData.name, standingName, pct))
          else
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(1)
            bar.text:SetText(fData.name .. " - " .. standingName)
          end
        else
          bar:SetMinMaxValues(0, 1)
          bar:SetValue(0)
          bar.text:SetText(L["No tracked reputation"])
        end
      end)
    end
  end

  -- Re-layout in case max level changed
  self:LayoutStatusPopup(shelf)

  -- Update handle label using template
  if shelf.handle then
    local template = config.label or "Lv$level $xp%"
    local text = self:FormatStatusLabel(template)
    shelf.handle.label:SetText(text)

    local dock = self.docks[config.dockID or 1]
    if dock then
      dock:LayoutHandles()
    end
  end
end

---------------------------------------------------------------------------
-- Deactivate: clean up events and restore hidden frames
---------------------------------------------------------------------------
function Barshelf:DeactivateStatusShelf(shelf)
  -- Clean up event frame
  if shelf._statusEventFrame then
    shelf._statusEventFrame:UnregisterAllEvents()
    shelf._statusEventFrame:SetScript("OnEvent", nil)
    shelf._statusEventFrame = nil
  end

  -- Restore the original container
  if shelf.hiddenStatusContainer then
    pcall(function()
      shelf.hiddenStatusContainer:Show()
    end)
    shelf.hiddenStatusContainer = nil
  end

  -- Hide our custom bars
  if shelf.xpBar then
    shelf.xpBar:Hide()
  end
  if shelf.repBar then
    shelf.repBar:Hide()
  end
  if shelf.trackedBars then
    for _, bar in ipairs(shelf.trackedBars) do
      bar:Hide()
    end
  end
end
