local Barshelf = LibStub("AceAddon-3.0"):GetAddon("Barshelf")

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local L = Barshelf_L

---------------------------------------------------------------------------
-- Minimap icon via LibDataBroker + LibDBIcon
---------------------------------------------------------------------------
function Barshelf:SetupMinimapIcon()
  local LDB = LibStub("LibDataBroker-1.1", true)
  local LDBI = LibStub("LibDBIcon-1.0", true)
  if not LDB or not LDBI then
    return
  end

  local dataObj = LDB:NewDataObject("Barshelf", {
    type = "data source",
    text = "Barshelf",
    icon = "Interface\\AddOns\\Barshelf\\assets\\logo",
    OnClick = function(_, button)
      if button == "LeftButton" then
        Barshelf:ToggleConfig()
      end
    end,
    OnTooltipShow = function(tip)
      tip:AddLine("Barshelf", 1, 1, 1)
      tip:AddLine(L["Left-click to open settings"], 0.7, 0.7, 0.7)
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
  if rebuildPending then
    return
  end
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
  if dropdownFrame then
    dropdownFrame:Hide()
  end

  dropdownFrame = dropdownFrame or CreateFrame("Frame", "BarshelfDropdownMenu", UIParent, "BackdropTemplate")
  local mf = dropdownFrame
  mf:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  mf:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
  mf:SetFrameStrata("TOOLTIP")
  mf:ClearAllPoints()
  mf:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
  mf:SetSize(180, #options * 22 + 8)

  for _, child in pairs({ mf:GetChildren() }) do
    child:Hide()
  end

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
-- Icon picker popup (same approach as MacroToolkit: direct WoW API)
---------------------------------------------------------------------------
local iconPickerFrame
local allIconTextures -- populated once from WoW APIs
local iconNameMap -- texture → lowercase searchable name

-- Build the icon list and name map
local function BuildIconList()
  if allIconTextures then
    return
  end
  allIconTextures = {}
  iconNameMap = {}

  -- Spellbook icons first — we get both texture AND spell name
  pcall(function()
    local spellBank = Enum.SpellBookSpellBank.Player
    local numTabs = (GetNumSpellTabs or C_SpellBook.GetNumSpellBookSkillLines)()
    for i = 1, numTabs do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if info then
        local offset = (info.itemIndexOffset or 0) + 1
        local tabEnd = offset + (info.numSpellBookItems or 0)
        for j = offset, tabEnd - 1 do
          local tex = C_SpellBook.GetSpellBookItemTexture(j, spellBank)
          if tex and not iconNameMap[tex] then
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(j, spellBank)
            if spellInfo and spellInfo.name then
              iconNameMap[tex] = spellInfo.name:lower()
            end
            allIconTextures[#allIconTextures + 1] = tex
          end
        end
      end
    end
  end)

  -- Append all macro/item icons from WoW API
  local beforeCount = #allIconTextures
  GetLooseMacroIcons(allIconTextures)
  GetLooseMacroItemIcons(allIconTextures)
  GetMacroIcons(allIconTextures)
  GetMacroItemIcons(allIconTextures)

  -- For non-spellbook entries, use the texture value as name
  -- (string entries like "spell_holy_powerwordshield" become searchable)
  for i = beforeCount + 1, #allIconTextures do
    local tex = allIconTextures[i]
    if type(tex) == "string" and not iconNameMap[tex] then
      iconNameMap[tex] = tex:lower():gsub("[_]", " ")
    end
  end
end

-- Resolve a texture entry to something SetTexture can use
local function ResolveTexture(tex)
  if type(tex) == "number" then
    return tex
  elseif type(tex) == "string" then
    return "Interface\\Icons\\" .. tex
  end
  return nil
end

local function ShowIconPicker(anchorFrame, onSelect)
  -- Toggle: close if already open
  if iconPickerFrame and iconPickerFrame:IsShown() then
    iconPickerFrame:Hide()
    return
  end

  BuildIconList()

  local COLS = 12
  local ICON_SZ = 32
  local ICON_PAD = 2
  local VISIBLE_ROWS = 10
  local INSET = 6
  local SEARCH_H = 26
  local gridW = COLS * (ICON_SZ + ICON_PAD) - ICON_PAD
  local gridH = VISIBLE_ROWS * (ICON_SZ + ICON_PAD) - ICON_PAD
  local frameW = gridW + INSET * 2 + 24
  local frameH = gridH + INSET * 2 + SEARCH_H + 8

  if not iconPickerFrame then
    local f = CreateFrame("Frame", "BarshelfIconPicker", UIParent, "BackdropTemplate")
    f:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    -- Search box
    local searchBox = CreateFrame("EditBox", "BarshelfIconPickerSearch", f, "InputBoxTemplate")
    searchBox:SetSize(gridW, 18)
    searchBox:SetPoint("TOPLEFT", INSET + 4, -INSET)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    f.searchBox = searchBox

    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    searchHint:SetText(L["Search..."])
    f.searchHint = searchHint
    searchBox:SetScript("OnTextChanged", function(self)
      local text = self:GetText()
      searchHint:SetShown(text == "")
      if f._searchTimer then
        f._searchTimer:Cancel()
      end
      f._searchTimer = C_Timer.NewTimer(0.3, function()
        f._searchTimer = nil
        if f._refreshGrid then
          f:_refreshGrid()
        end
      end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)

    -- FauxScrollFrame for virtual scrolling
    local scroll = CreateFrame("ScrollFrame", "BarshelfIconPickerScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", INSET, -INSET - SEARCH_H - 4)
    scroll:SetPoint("BOTTOMRIGHT", -INSET - 22, INSET)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", INSET, -INSET - SEARCH_H - 4)
    content:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    f.content = content
    f.scroll = scroll
    f.iconButtons = {}

    iconPickerFrame = f
  end

  local f = iconPickerFrame
  f:SetSize(frameW, frameH)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
  f.searchBox:SetText("")
  f.searchHint:Show()

  local stride = ICON_SZ + ICON_PAD
  local visibleCount = COLS * VISIBLE_ROWS

  -- Create/position visible buttons (fixed grid, textures change on scroll)
  for i = 1, visibleCount do
    if not f.iconButtons[i] then
      local btn = CreateFrame("Button", nil, f.content)
      btn:SetSize(ICON_SZ, ICON_SZ)
      local t = btn:CreateTexture(nil, "ARTWORK")
      t:SetAllPoints()
      btn.icon = t
      btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
      f.iconButtons[i] = btn
    end
    local btn = f.iconButtons[i]
    local row = math.floor((i - 1) / COLS)
    local col = (i - 1) % COLS
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", f.content, "TOPLEFT", col * stride, -row * stride)
  end

  -- Build per-index name cache: spellbook names + TextureNames data + string filenames
  if not f._nameCache then
    local cache = {}
    local texNames = Barshelf_TextureNames or {}
    for i, tex in ipairs(allIconTextures) do
      -- Priority: spellbook name > TextureNames data > string filename
      local name = iconNameMap[tex]
      if not name and type(tex) == "number" and texNames[tex] then
        name = texNames[tex]:lower()
      end
      if not name and type(tex) == "string" then
        name = tex:lower():gsub("[_]", " ")
      end
      cache[i] = name
    end
    f._nameCache = cache
  end
  local nameCache = f._nameCache

  -- Filtered results (indices into allIconTextures)
  f._searchResults = f._searchResults or {}

  local function RebuildSearchResults()
    local results = f._searchResults
    wipe(results)
    local filter = f.searchBox:GetText():lower()
    if filter == "" then
      for i = 1, #allIconTextures do
        results[i] = i
      end
    else
      local filterNum = tonumber(filter)
      for i = 1, #allIconTextures do
        local tex = allIconTextures[i]
        -- Match by name (spell name or filename)
        local name = nameCache[i]
        if name and name:find(filter, 1, true) then
          results[#results + 1] = i
        -- Match by FileDataID (numeric search)
        elseif filterNum and type(tex) == "number" and tex == filterNum then
          results[#results + 1] = i
        -- Match numeric ID as substring (e.g., typing "1362" matches 136235)
        elseif type(tex) == "number" and tostring(tex):find(filter, 1, true) then
          results[#results + 1] = i
        end
      end
    end
  end

  local function UpdateIcons()
    local results = f._searchResults
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    local firstIndex = offset * COLS + 1

    for i = 1, visibleCount do
      local btn = f.iconButtons[i]
      local dataIndex = firstIndex + i - 1
      local resultEntry = results[dataIndex]
      if resultEntry then
        local rawTex = allIconTextures[resultEntry]
        local tex = ResolveTexture(rawTex)
        local name = nameCache[resultEntry]
        btn.icon:SetTexture(tex)
        btn:SetScript("OnClick", function()
          onSelect(tex)
          f:Hide()
        end)
        btn:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(name or tostring(rawTex), 1, 1, 1)
          GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
        btn:Show()
      else
        btn.icon:SetTexture(nil)
        btn:Hide()
      end
    end
  end

  f.scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, stride, UpdateIcons)
  end)

  function f:_refreshGrid()
    RebuildSearchResults()
    local totalRows = math.ceil(#self._searchResults / COLS)
    FauxScrollFrame_Update(self.scroll, totalRows, VISIBLE_ROWS, stride)
    UpdateIcons()
  end

  f:_refreshGrid()

  f:SetScript("OnUpdate", function(self)
    if not self:IsMouseOver() and not self.searchBox:HasFocus() and IsMouseButtonDown() then
      self:Hide()
    end
  end)

  f:Show()
  f.searchBox:SetFocus()
end

---------------------------------------------------------------------------
-- Faction picker popup (hierarchical with search)
---------------------------------------------------------------------------
local factionPickerFrame

local function ShowFactionPicker(anchorFrame, onSelect, excludeIDs)
  -- Toggle: close if already open
  if factionPickerFrame and factionPickerFrame:IsShown() then
    factionPickerFrame:Hide()
    return
  end

  -- Build faction list, expanding all headers to get the full tree
  local factionList = {} -- { factionID, name, isHeader, indent }
  local excludeSet = {}
  if excludeIDs then
    for _, id in ipairs(excludeIDs) do
      excludeSet[id] = true
    end
  end

  local ok = pcall(function()
    -- Expand all collapsed headers first to enumerate every faction
    local expanded = {}
    local pass = 0
    repeat
      pass = pass + 1
      local changed = false
      local n = C_Reputation.GetNumFactions()
      for i = n, 1, -1 do
        local d = C_Reputation.GetFactionDataByIndex(i)
        if d and d.isHeader and d.isCollapsed then
          C_Reputation.ExpandFactionHeader(i)
          expanded[#expanded + 1] = d.factionID
          changed = true
        end
      end
    until not changed or pass > 20

    local n = C_Reputation.GetNumFactions()
    local depth = 1
    for i = 1, n do
      local d = C_Reputation.GetFactionDataByIndex(i)
      if d and d.name then
        if d.isHeader then
          factionList[#factionList + 1] = {
            factionID = d.factionID,
            name = d.name,
            isHeader = true,
            indent = 0,
          }
          depth = 1
        else
          factionList[#factionList + 1] = {
            factionID = d.factionID,
            name = d.name,
            isHeader = false,
            indent = depth,
          }
        end
      end
    end

    -- Collapse back what we expanded (reverse order to preserve indices)
    for i = #expanded, 1, -1 do
      local n2 = C_Reputation.GetNumFactions()
      for j = 1, n2 do
        local d = C_Reputation.GetFactionDataByIndex(j)
        if d and d.factionID == expanded[i] and not d.isCollapsed then
          C_Reputation.CollapseFactionHeader(j)
          break
        end
      end
    end
  end)

  if not ok or #factionList == 0 then
    return
  end

  local PICKER_W = 300
  local PICKER_H = 400
  local ROW_H = 20
  local INSET = 6
  local SEARCH_H = 26

  if not factionPickerFrame then
    local f = CreateFrame("Frame", "BarshelfFactionPicker", UIParent, "BackdropTemplate")
    f:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    -- Search box
    local searchBox = CreateFrame("EditBox", "BarshelfFactionPickerSearch", f, "InputBoxTemplate")
    searchBox:SetSize(PICKER_W - INSET * 2 - 8, 18)
    searchBox:SetPoint("TOPLEFT", INSET + 4, -INSET)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("ChatFontNormal")
    f.searchBox = searchBox

    local searchHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
    searchHint:SetText(L["Search..."])
    f.searchHint = searchHint
    searchBox:SetScript("OnTextChanged", function(self)
      local text = self:GetText()
      searchHint:SetShown(text == "")
      if f._searchTimer then
        f._searchTimer:Cancel()
      end
      f._searchTimer = C_Timer.NewTimer(0.2, function()
        f._searchTimer = nil
        if f._rebuild then
          f:_rebuild()
        end
      end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)

    -- Scrollable content area
    local scroll = CreateFrame("ScrollFrame", "BarshelfFactionPickerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", INSET, -INSET - SEARCH_H - 4)
    scroll:SetPoint("BOTTOMRIGHT", -INSET - 22, INSET)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PICKER_W - INSET * 2 - 24, 1)
    scroll:SetScrollChild(content)
    f.scroll = scroll
    f.content = content

    factionPickerFrame = f
  end

  local f = factionPickerFrame
  f:SetSize(PICKER_W, PICKER_H)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
  f.searchBox:SetText("")
  f.searchHint:Show()

  -- Store data on the frame for rebuild
  f._factionList = factionList
  f._excludeSet = excludeSet
  f._onSelect = onSelect

  function f:_rebuild()
    local content = self.content
    -- Clear old rows
    for _, c in pairs({ content:GetChildren() }) do
      c:Hide()
      c:ClearAllPoints()
      c:SetParent(nil)
    end
    for _, r in pairs({ content:GetRegions() }) do
      r:Hide()
    end

    local filter = self.searchBox:GetText():lower()
    local list = self._factionList
    local exclude = self._excludeSet
    local selectFn = self._onSelect
    local y = 0
    local contentW = PICKER_W - INSET * 2 - 24

    -- When searching, show matching factions (and their parent header)
    local visibleEntries = {}
    if filter == "" then
      for _, entry in ipairs(list) do
        visibleEntries[#visibleEntries + 1] = entry
      end
    else
      -- Find factions matching the filter, include their preceding header
      local lastHeader = nil
      local lastHeaderAdded = false
      for _, entry in ipairs(list) do
        if entry.isHeader then
          lastHeader = entry
          lastHeaderAdded = false
        else
          if entry.name:lower():find(filter, 1, true) then
            if lastHeader and not lastHeaderAdded then
              visibleEntries[#visibleEntries + 1] = lastHeader
              lastHeaderAdded = true
            end
            visibleEntries[#visibleEntries + 1] = entry
          end
        end
      end
    end

    for _, entry in ipairs(visibleEntries) do
      local indentPx = entry.isHeader and 0 or 16

      if entry.isHeader then
        -- Header row: bold yellow, not clickable
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(contentW, ROW_H)
        row:SetPoint("TOPLEFT", 0, y)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", indentPx, 0)
        lbl:SetText("|cffffd100" .. entry.name .. "|r")
        row:Show()
      else
        -- Faction row: clickable, dimmed if excluded
        local isExcluded = exclude[entry.factionID]
        local row = CreateFrame("Button", nil, content)
        row:SetSize(contentW, ROW_H)
        row:SetPoint("TOPLEFT", 0, y)

        if not isExcluded then
          row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        end

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", indentPx, 0)
        lbl:SetText(entry.name)

        if isExcluded then
          lbl:SetTextColor(0.4, 0.4, 0.4)
        else
          row:SetScript("OnClick", function()
            selectFn(entry.factionID)
            f:Hide()
          end)
        end

        row:Show()
      end

      y = y - ROW_H
    end

    content:SetHeight(math.max(math.abs(y), 1))
  end

  f:_rebuild()

  f:SetScript("OnUpdate", function(self)
    if not self:IsMouseOver() and not self.searchBox:HasFocus() and IsMouseButtonDown() then
      self:Hide()
    end
  end)

  f:Show()
  f.searchBox:SetFocus()
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
    edgeSize = 8,
    tile = true,
    tileSize = 8,
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
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10,
    tile = true,
    tileSize = 8,
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
  eb:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

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
  "Shelves & Docks",
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
        if origOnShow then
          origOnShow(self)
        end
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
    name = L["General"],
    args = {
      closeOthers = {
        order = 1,
        type = "toggle",
        name = L["Close other popups when opening one"],
        desc = L["Automatically hide other open shelves when a new one is opened."],
        width = "full",
        get = function()
          return Barshelf.db.profile.closeOthers
        end,
        set = function(_, v)
          Barshelf.db.profile.closeOthers = v
          Barshelf:UpdateAllSecureRefs()
        end,
      },
      clickOutsideToClose = {
        order = 1.1,
        type = "toggle",
        name = L["Click outside to close popups"],
        desc = L["Close all open shelves when clicking outside them. When off, shelves stay open until their handle is clicked again (useful for dragging spells to action bars)."],
        width = "full",
        get = function()
          return Barshelf.db.profile.clickOutsideToClose
        end,
        set = function(_, v)
          Barshelf.db.profile.clickOutsideToClose = v
        end,
      },
      stackPopups = {
        order = 1.5,
        type = "toggle",
        name = L["Stack open popups"],
        desc = L["When multiple popups are open, stack them sequentially instead of overlapping. Only applies when 'Close other popups' is off."],
        width = "full",
        disabled = function()
          return Barshelf.db.profile.closeOthers
        end,
        get = function()
          return Barshelf.db.profile.stackPopups
        end,
        set = function(_, v)
          Barshelf.db.profile.stackPopups = v
          if not InCombatLockdown() then
            for _, dock in pairs(Barshelf.docks) do
              Barshelf:LayoutDockPopups(dock)
            end
          end
        end,
      },
      centerPopupsOnDock = {
        order = 1.6,
        type = "toggle",
        name = L["Center popups on dock"],
        desc = L["Center shelf popups horizontally on the dock instead of aligning them to their handle."],
        width = "full",
        get = function()
          return Barshelf.db.profile.centerPopupsOnDock
        end,
        set = function(_, v)
          Barshelf.db.profile.centerPopupsOnDock = v
          DebouncedRebuild()
        end,
      },
      animatePopups = {
        order = 2,
        type = "toggle",
        name = L["Animate popups (fade in)"],
        desc = L["Play a short fade-in animation when a shelf popup opens."],
        width = "full",
        get = function()
          return Barshelf.db.profile.animatePopups
        end,
        set = function(_, v)
          Barshelf.db.profile.animatePopups = v
        end,
      },
      dockIdleHeader = {
        order = 2.5,
        type = "header",
        name = L["Dock Idle Behavior"],
      },
      dockIdleAlpha = {
        order = 2.6,
        type = "range",
        name = L["Idle dock opacity"],
        desc = L["Dock opacity when no popup is open and mouse is not hovering. Set to 100% to disable fading."],
        min = 0,
        max = 1,
        step = 0.05,
        isPercent = true,
        get = function()
          return Barshelf.db.profile.dockIdleAlpha or 1.0
        end,
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
        name = L["Fade duration"],
        desc = L["How long the fade animation takes (seconds)."],
        min = 0,
        max = 1,
        step = 0.05,
        disabled = function()
          return (Barshelf.db.profile.dockIdleAlpha or 1.0) >= 1.0
        end,
        get = function()
          return Barshelf.db.profile.dockFadeDuration or 0.3
        end,
        set = function(_, v)
          Barshelf.db.profile.dockFadeDuration = v
        end,
      },
      showMinimap = {
        order = 3,
        type = "toggle",
        name = L["Show minimap icon"],
        desc = L["Display the Barshelf icon on the minimap."],
        width = "full",
        get = function()
          return Barshelf.db.profile.showMinimap ~= false
        end,
        set = function(_, v)
          Barshelf.db.profile.showMinimap = v
          Barshelf.db.profile.minimap.hide = not v
          local LDBI = LibStub("LibDBIcon-1.0", true)
          if LDBI then
            if v then
              LDBI:Show("Barshelf")
            else
              LDBI:Hide("Barshelf")
            end
          end
        end,
      },
      barRowOrder = {
        order = 4,
        type = "select",
        name = L["Bar Row Order"],
        desc = L["How rows are ordered within bar shelves."],
        values = {
          auto = L["Auto (Blizzard)"],
          topdown = L["Top to Bottom"],
          bottomup = L["Bottom to Top"],
        },
        sorting = { "auto", "topdown", "bottomup" },
        get = function()
          return Barshelf.db.profile.barRowOrder or "auto"
        end,
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
    name = L["Appearance"],
    args = {
      -- Dock section
      dockHeader = {
        order = 1,
        type = "header",
        name = L["Dock"],
      },
      dockBgAlpha = {
        order = 2,
        type = "range",
        name = L["Background Opacity"],
        desc = L["Opacity of the dock background."],
        min = 0,
        max = 1,
        step = 0.05,
        isPercent = true,
        get = function()
          return Barshelf.db.profile.dockBgAlpha or 0.75
        end,
        set = function(_, v)
          Barshelf.db.profile.dockBgAlpha = v
          DebouncedRebuild()
        end,
      },
      dockBorderAlpha = {
        order = 3,
        type = "range",
        name = L["Border Opacity"],
        desc = L["Opacity of the dock border."],
        min = 0,
        max = 1,
        step = 0.05,
        isPercent = true,
        get = function()
          return Barshelf.db.profile.dockBorderAlpha or 0.8
        end,
        set = function(_, v)
          Barshelf.db.profile.dockBorderAlpha = v
          DebouncedRebuild()
        end,
      },
      dockShowBorder = {
        order = 4,
        type = "toggle",
        name = L["Show Border"],
        desc = L["Draw a border around the dock frame."],
        get = function()
          return Barshelf.db.profile.dockShowBorder ~= false
        end,
        set = function(_, v)
          Barshelf.db.profile.dockShowBorder = v
          DebouncedRebuild()
        end,
      },
      dockPadding = {
        order = 5,
        type = "range",
        name = L["Padding"],
        desc = L["Space between dock edge and shelf handles."],
        min = 0,
        max = 12,
        step = 1,
        get = function()
          return Barshelf.db.profile.dockPadding or 4
        end,
        set = function(_, v)
          Barshelf.db.profile.dockPadding = v
          DebouncedRebuild()
        end,
      },

      -- Shelf Popup section
      popupHeader = {
        order = 10,
        type = "header",
        name = L["Shelf Popup"],
      },
      popupBgAlpha = {
        order = 11,
        type = "range",
        name = L["Background Opacity"],
        desc = L["Opacity of the shelf popup background."],
        min = 0,
        max = 1,
        step = 0.05,
        isPercent = true,
        get = function()
          return Barshelf.db.profile.popupBgAlpha or 0.92
        end,
        set = function(_, v)
          Barshelf.db.profile.popupBgAlpha = v
          DebouncedRebuild()
        end,
      },

      -- Handle section
      handleHeader = {
        order = 20,
        type = "header",
        name = L["Handle"],
      },
      handleBgAlpha = {
        order = 21,
        type = "range",
        name = L["Background Opacity"],
        desc = L["Opacity of the handle background."],
        min = 0,
        max = 1,
        step = 0.05,
        isPercent = true,
        get = function()
          return Barshelf.db.profile.handleBgAlpha or 0.85
        end,
        set = function(_, v)
          Barshelf.db.profile.handleBgAlpha = v
          DebouncedRebuild()
        end,
      },
      handleIconSize = {
        order = 22,
        type = "range",
        name = L["Icon Size"],
        desc = L["Size of the icon displayed on shelf handles."],
        min = 10,
        max = 32,
        step = 1,
        get = function()
          return Barshelf.db.profile.handleIconSize or 16
        end,
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
        name = L["Font Size"],
        desc = L["Size of the label text on shelf handles."],
        min = 8,
        max = 18,
        step = 1,
        get = function()
          return Barshelf.db.profile.handleFontSize or 12
        end,
        set = function(_, v)
          Barshelf.db.profile.handleFontSize = v
          for _, cfg in ipairs(Barshelf.db.profile.shelves) do
            cfg.labelFontSize = v
          end
          DebouncedRebuild()
        end,
      },

      -- Shelf Defaults section
      shelfDefaultsHeader = {
        order = 25,
        type = "header",
        name = L["Shelf Defaults"],
      },
      defaultPopupAnchor = {
        order = 26,
        type = "select",
        name = L["Open Direction"],
        desc = L["Default popup direction for new shelves."],
        values = {
          AUTO = L["Auto"],
          BOTTOM = L["Below"],
          TOP = L["Above"],
          LEFT = L["Left"],
          RIGHT = L["Right"],
        },
        sorting = { "AUTO", "BOTTOM", "TOP", "LEFT", "RIGHT" },
        get = function()
          return Barshelf.db.profile.defaultPopupAnchor or "AUTO"
        end,
        set = function(_, v)
          Barshelf.db.profile.defaultPopupAnchor = v
          DebouncedRebuild()
        end,
      },
      defaultDisplayMode = {
        order = 27,
        type = "select",
        name = L["Handle Style"],
        desc = L["Default handle display style for new shelves."],
        values = {
          both = L["Icon + Label"],
          label = L["Label only"],
          icon = L["Icon only"],
        },
        sorting = { "both", "label", "icon" },
        get = function()
          return Barshelf.db.profile.defaultDisplayMode or "both"
        end,
        set = function(_, v)
          Barshelf.db.profile.defaultDisplayMode = v
          DebouncedRebuild()
        end,
      },

      -- Bar Defaults section
      barHeader = {
        order = 30,
        type = "header",
        name = L["Bar Defaults"],
      },
      barIconSize = {
        order = 31,
        type = "range",
        name = L["Icon Size"],
        desc = L["Default icon size for bar shelves."],
        min = 20,
        max = 56,
        step = 2,
        get = function()
          return Barshelf.db.profile.barIconSize or 36
        end,
        set = function(_, v)
          Barshelf.db.profile.barIconSize = v
          for _, cfg in ipairs(Barshelf.db.profile.shelves) do
            if cfg.type == "bar" then
              cfg.buttonSize = v
            end
          end
          DebouncedRebuild()
        end,
      },
      barIconPadding = {
        order = 32,
        type = "range",
        name = L["Icon Padding"],
        desc = L["Default padding between icons in bar shelves."],
        min = 0,
        max = 12,
        step = 1,
        get = function()
          return Barshelf.db.profile.barIconPadding or 2
        end,
        set = function(_, v)
          Barshelf.db.profile.barIconPadding = v
          for _, cfg in ipairs(Barshelf.db.profile.shelves) do
            if cfg.type == "bar" then
              cfg.buttonPadding = v
            end
          end
          DebouncedRebuild()
        end,
      },
    },
  }
end

---------------------------------------------------------------------------
-- Shelves & Docks panel: tree-view list on left, detail on right
---------------------------------------------------------------------------
local selectedShelf = nil -- index into db.shelves
local selectedDock = nil -- dock ID (not index)

local function BuildShelvesAndDocksPanel(panel)
  local LIST_WIDTH = 220
  local DETAIL_LEFT = LIST_WIDTH + 12
  local TOPBAR_HEIGHT = 30

  -- Top: add buttons bar
  local topBar = CreateFrame("Frame", nil, panel)
  topBar:SetPoint("TOPLEFT", 4, -4)
  topBar:SetPoint("TOPRIGHT", -4, -4)
  topBar:SetHeight(TOPBAR_HEIGHT)

  local addDockBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
  addDockBtn:SetSize(100, 22)
  addDockBtn:SetPoint("TOPLEFT", 4, -2)
  addDockBtn:SetText(L["+ Add Dock"])

  local addShelfBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
  addShelfBtn:SetSize(100, 22)
  addShelfBtn:SetPoint("LEFT", addDockBtn, "RIGHT", 4, 0)
  addShelfBtn:SetText(L["+ Add Shelf"])

  -- Left: tree-view list (scrollable)
  local listBorder = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  listBorder:SetPoint("TOPLEFT", 4, -(8 + TOPBAR_HEIGHT))
  listBorder:SetPoint("BOTTOMLEFT", 4, 8)
  listBorder:SetWidth(LIST_WIDTH)
  listBorder:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
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
  detailScroll:SetPoint("TOPLEFT", DETAIL_LEFT, -(8 + TOPBAR_HEIGHT))
  detailScroll:SetPoint("BOTTOMRIGHT", -24, 8)
  local detailChild = CreateFrame("Frame", nil, detailScroll)
  detailChild:SetSize(320, 1)
  detailScroll:SetScrollChild(detailChild)

  ---------------------------------------------------------------------------
  -- Determine which dock is "selected" based on the currently selected shelf or dock
  local function GetSelectedDockID()
    if selectedDock then
      return selectedDock
    end
    if not selectedShelf then
      return 1
    end
    local db = Barshelf.db.profile
    local cfg = db.shelves[selectedShelf]
    if cfg then
      return cfg.dockID or 1
    end
    return 1
  end

  ---------------------------------------------------------------------------
  local function RefreshList()
    for _, c in pairs({ listChild:GetChildren() }) do
      c:Hide()
      c:ClearAllPoints()
      c:SetParent(nil)
    end
    for _, r in pairs({ listChild:GetRegions() }) do
      r:Hide()
    end

    local db = Barshelf.db.profile
    local y = 0
    local rowWidth = LIST_WIDTH - 28

    if #db.docks == 0 and #db.shelves == 0 then
      local hint = listChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      hint:SetPoint("TOPLEFT", 4, -4)
      hint:SetText(L["No shelves yet."])
      y = -20
    end

    for _, dockCfg in ipairs(db.docks) do
      -- Dock header row (clickable to select dock)
      local dockRow = CreateFrame("Button", nil, listChild)
      dockRow:SetSize(rowWidth, 22)
      dockRow:SetPoint("TOPLEFT", 0, y)

      local dockBg = dockRow:CreateTexture(nil, "BACKGROUND")
      dockBg:SetAllPoints()
      if selectedDock == dockCfg.id and not selectedShelf then
        dockBg:SetColorTexture(0.3, 0.4, 0.2, 0.6)
      else
        dockBg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
      end

      dockRow:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

      local dockLabel = dockRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      dockLabel:SetPoint("LEFT", 4, 0)
      dockLabel:SetText(dockCfg.name or ("Dock " .. dockCfg.id))

      dockRow:SetScript("OnClick", function()
        selectedDock = dockCfg.id
        selectedShelf = nil
        panel._refresh()
      end)

      -- Delete button (not for dock 1)
      if dockCfg.id ~= 1 then
        local del = CreateFrame("Button", nil, dockRow, "UIPanelButtonTemplate")
        del:SetSize(18, 18)
        del:SetPoint("RIGHT", -2, 0)
        del:SetNormalFontObject("GameFontNormalSmall")
        del:SetText("X")
        del:SetScript("OnClick", function()
          if selectedDock == dockCfg.id then
            selectedDock = nil
          end
          Barshelf:RemoveDock(dockCfg.id)
          panel._refresh()
        end)
      end

      y = y - 24

      -- Shelf rows indented under this dock
      for si, cfg in ipairs(db.shelves) do
        if (cfg.dockID or 1) == dockCfg.id then
          local row = CreateFrame("Button", nil, listChild)
          row:SetSize(rowWidth, 22)
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

          -- Type prefix badge
          local badge
          if cfg.type == "bar" then
            badge = "|cff88ccff[B" .. (cfg.barID or "?") .. "]|r "
          elseif cfg.type == "micro" then
            badge = "|cffcc88ff[M]|r "
          elseif cfg.type == "bags" then
            badge = "|cff88ffcc[Bag]|r "
          elseif cfg.type == "status" then
            badge = "|cffffcc88[S]|r "
          else
            badge = "|cffcccc88[C]|r "
          end

          local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          lbl:SetPoint("LEFT", 16, 0)
          lbl:SetPoint("RIGHT", -4, 0)
          lbl:SetJustifyH("LEFT")
          local displayName
          if cfg.type == "status" then
            displayName = "Status"
          elseif cfg.type == "bags" then
            displayName = "Bags"
          else
            displayName = cfg.label or "Unnamed"
          end
          lbl:SetText(badge .. displayName)
          if not cfg.enabled then
            lbl:SetAlpha(0.5)
          end

          row:SetScript("OnClick", function()
            selectedShelf = si
            selectedDock = nil
            panel._refresh()
          end)

          y = y - 23
        end
      end

      y = y - 4
    end

    listChild:SetHeight(math.abs(y) + 4)
  end

  ---------------------------------------------------------------------------
  local function RefreshDetail()
    for _, c in pairs({ detailChild:GetChildren() }) do
      c:Hide()
      c:ClearAllPoints()
      c:SetParent(nil)
    end
    for _, r in pairs({ detailChild:GetRegions() }) do
      r:Hide()
    end

    local db = Barshelf.db.profile

    -- Dock detail panel (when a dock is selected, not a shelf)
    if selectedDock and not selectedShelf then
      local dockCfg
      for _, dc in ipairs(db.docks) do
        if dc.id == selectedDock then
          dockCfg = dc
          break
        end
      end
      if not dockCfg then
        selectedDock = nil
        local hint = detailChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        hint:SetPoint("TOPLEFT", 8, -8)
        hint:SetText(L["Select a shelf on the left to configure it."])
        detailChild:SetHeight(30)
        return
      end

      local y = -4
      local indent = 4

      -- Title
      local titleText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      titleText:SetPoint("TOPLEFT", indent, y)
      titleText:SetText(dockCfg.name or ("Dock " .. dockCfg.id))
      y = y - 26

      -- Dock Name
      _, y = CreateEditBox(detailChild, indent, y, L["Dock Name"], dockCfg.name, 200, function(v)
        dockCfg.name = v
        Barshelf:RebuildAll()
        panel._refresh()
      end)

      -- Orientation
      local orientNames = { HORIZONTAL = L["Horizontal"], VERTICAL = L["Vertical"] }
      _, y = CreateDropdownButton(
        detailChild,
        indent,
        y,
        L["Orientation"],
        {
          { text = L["Horizontal"], value = "HORIZONTAL" },
          { text = L["Vertical"], value = "VERTICAL" },
        },
        orientNames[dockCfg.orientation] or L["Horizontal"],
        function(v)
          dockCfg.orientation = v
          Barshelf:RebuildAll()
          panel._refresh()
        end
      )

      -- Defaults (dock)
      y = y - 8
      local resetDockBtn = CreateFrame("Button", nil, detailChild, "UIPanelButtonTemplate")
      resetDockBtn:SetSize(80, 22)
      resetDockBtn:SetPoint("TOPLEFT", indent, y)
      resetDockBtn:SetText(L["Defaults"])
      resetDockBtn:SetScript("OnClick", function()
        StaticPopup_Show("BARSHELF_CONFIRM_RESET_DOCK_" .. dockCfg.id)
      end)
      resetDockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Reset all settings to defaults"], 1, 1, 1)
        GameTooltip:Show()
      end)
      resetDockBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      StaticPopupDialogs["BARSHELF_CONFIRM_RESET_DOCK_" .. dockCfg.id] = {
        text = L["Are you sure you want to reset this dock to defaults?"],
        button1 = YES,
        button2 = NO,
        OnAccept = function()
          dockCfg.orientation = "HORIZONTAL"
          dockCfg.point = nil
          Barshelf:RebuildAll()
          panel._refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
      }
      y = y - 28

      -- Delete button (not for dock 1)
      if dockCfg.id ~= 1 then
        local del = CreateFrame("Button", nil, detailChild, "UIPanelButtonTemplate")
        del:SetSize(100, 22)
        del:SetPoint("TOPLEFT", indent, y)
        del:SetText(L["Delete"])
        del:SetScript("OnClick", function()
          selectedDock = nil
          Barshelf:RemoveDock(dockCfg.id)
          panel._refresh()
        end)
        y = y - 28
      end

      detailChild:SetHeight(math.abs(y) + 20)
      return
    end

    local cfg = db.shelves[selectedShelf]
    if not cfg then
      local hint = detailChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
      hint:SetPoint("TOPLEFT", 8, -8)
      hint:SetText(L["Select a shelf on the left to configure it."])
      detailChild:SetHeight(30)
      return
    end

    local si = selectedShelf
    local y = -4
    local indent = 4

    -- Title row: type + label + enabled + move + delete
    -- Title
    local titleText = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", indent, y)
    titleText:SetText(cfg.label or "Unnamed")
    y = y - 22

    -- Controls row: enabled, move, delete, reset
    local ctrlRow = CreateFrame("Frame", nil, detailChild)
    ctrlRow:SetHeight(22)
    ctrlRow:SetPoint("TOPLEFT", indent, y)
    ctrlRow:SetPoint("RIGHT", detailChild, "RIGHT", -4, 0)

    local enable = CreateFrame("CheckButton", nil, ctrlRow, "UICheckButtonTemplate")
    enable:SetPoint("LEFT", 0, 0)
    enable:SetSize(22, 22)
    enable:SetChecked(cfg.enabled)
    local enText = enable.Text or enable.text
    if enText then
      enText:SetText(L["Enabled"])
    end
    enable:SetScript("OnClick", function(f)
      cfg.enabled = f:GetChecked()
      Barshelf:RebuildAll()
      RefreshList()
    end)

    local moveUp = CreateFrame("Button", nil, ctrlRow, "UIPanelScrollUpButtonTemplate")
    moveUp:SetSize(18, 16)
    moveUp:SetPoint("LEFT", enable, "RIGHT", 50, 0)
    if si > 1 then
      moveUp:SetScript("OnClick", function()
        db.shelves[si], db.shelves[si - 1] = db.shelves[si - 1], db.shelves[si]
        selectedShelf = si - 1
        Barshelf:RebuildAll()
        panel._refresh()
      end)
    else
      moveUp:Disable()
    end
    moveUp:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(L["Move up"], 1, 1, 1)
      GameTooltip:Show()
    end)
    moveUp:HookScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    local moveDown = CreateFrame("Button", nil, ctrlRow, "UIPanelScrollDownButtonTemplate")
    moveDown:SetSize(18, 16)
    moveDown:SetPoint("LEFT", moveUp, "RIGHT", 1, 0)
    if si < #db.shelves then
      moveDown:SetScript("OnClick", function()
        db.shelves[si], db.shelves[si + 1] = db.shelves[si + 1], db.shelves[si]
        selectedShelf = si + 1
        Barshelf:RebuildAll()
        panel._refresh()
      end)
    else
      moveDown:Disable()
    end
    moveDown:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(L["Move down"], 1, 1, 1)
      GameTooltip:Show()
    end)
    moveDown:HookScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    local del = CreateFrame("Button", nil, ctrlRow, "UIPanelButtonTemplate")
    del:SetSize(55, 20)
    del:SetPoint("LEFT", moveDown, "RIGHT", 6, 0)
    del:SetText(L["Delete"])
    del:SetScript("OnClick", function()
      selectedShelf = nil
      Barshelf:RemoveShelf(si)
      panel._refresh()
    end)

    local resetShelfBtn = CreateFrame("Button", nil, ctrlRow, "UIPanelButtonTemplate")
    resetShelfBtn:SetSize(65, 20)
    resetShelfBtn:SetPoint("LEFT", del, "RIGHT", 4, 0)
    resetShelfBtn:SetText(L["Defaults"])
    resetShelfBtn:SetScript("OnClick", function()
      StaticPopup_Show("BARSHELF_CONFIRM_RESET_SHELF")
    end)
    resetShelfBtn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(L["Reset all settings to defaults"], 1, 1, 1)
      GameTooltip:Show()
    end)
    resetShelfBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    StaticPopupDialogs["BARSHELF_CONFIRM_RESET_SHELF"] = {
      text = L["Are you sure you want to reset this shelf to defaults?"],
      button1 = YES,
      button2 = NO,
      OnAccept = function()
        cfg.buttonSize = (cfg.type == "bar") and 45 or 36
        cfg.buttonPadding = 2
        cfg.iconSize = Barshelf.db.profile.handleIconSize or 16
        cfg.labelFontSize = Barshelf.db.profile.handleFontSize or 12
        cfg.displayMode = "both"
        cfg.popupAnchor = "AUTO"
        DebouncedRebuild()
        RefreshDetail()
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
    }

    y = y - 28

    -- Label (with template keyword tooltip for status/bags types)
    local labelEB
    labelEB, y = CreateEditBox(detailChild, indent, y, L["Label"], cfg.label, 200, function(v)
      cfg.label = v
      DebouncedRebuild()
      RefreshList()
    end)

    if cfg.type == "status" or cfg.type == "bags" then
      labelEB:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Template Keywords"], 1, 1, 1)
        if cfg.type == "status" then
          GameTooltip:AddLine("$level - player level", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$xp - XP percentage", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$xpCur - current XP", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$xpMax - max XP", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$rep - rep percentage", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$repName - tracked faction name", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$repStanding - standing text", 0.7, 0.7, 0.7)
        elseif cfg.type == "bags" then
          GameTooltip:AddLine("$used - used bag slots", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$total - total bag slots", 0.7, 0.7, 0.7)
          GameTooltip:AddLine("$free - free bag slots", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
      end)
      labelEB:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end

    -- Icon picker (drag spell/item/macro to set, right-click to reset)
    do
      local iconFrame = CreateFrame("Button", nil, detailChild)
      iconFrame:SetSize(28, 28)
      iconFrame:SetPoint("TOPLEFT", indent, y)

      local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
      iconTex:SetAllPoints()

      -- Resolve current icon (same logic as UpdateHandleIcon)
      local currentIcon = cfg.customIcon
      if not currentIcon then
        currentIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
        if cfg.type == "bar" then
          local info = Barshelf.BAR_INFO[cfg.barID]
          if info then
            for bi = 1, cfg.numButtons or 12 do
              local btn = _G[info.prefix .. bi]
              if btn and btn.icon then
                local ic = btn.icon:GetTexture()
                if ic then
                  currentIcon = ic
                  break
                end
              end
            end
          end
        elseif cfg.type == "micro" then
          currentIcon = "Interface\\Icons\\INV_Misc_Book_09"
        elseif cfg.type == "bags" then
          currentIcon = "Interface\\Icons\\INV_Misc_Bag_08"
        elseif cfg.type == "status" then
          currentIcon = "Interface\\Icons\\Achievement_Level_80"
        end
      end
      iconTex:SetTexture(currentIcon)

      local iconLabel = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      iconLabel:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
      iconLabel:SetText(cfg.customIcon and L["Custom icon"] or L["Auto icon"])
      iconLabel:SetTextColor(0.7, 0.7, 0.7)

      iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Shelf Icon"], 1, 1, 1)
        GameTooltip:AddLine(L["Click to browse icons"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Drag a spell, item, or macro to set icon"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Right-click to reset to auto"], 0.5, 0.5, 0.5)
        GameTooltip:Show()
      end)
      iconFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      iconFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      iconFrame:SetScript("OnClick", function(self, mb)
        if mb == "RightButton" then
          cfg.customIcon = nil
          DebouncedRebuild()
          RefreshDetail()
          return
        end
        -- Left-click with cursor: apply dragged icon
        local cursorType, id, subType, spellID = GetCursorInfo()
        if cursorType then
          local tex
          if cursorType == "spell" then
            tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID or id)
          elseif cursorType == "item" then
            tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
          elseif cursorType == "macro" then
            local _, macroTex = GetMacroInfo(id)
            tex = macroTex
          end
          if tex then
            cfg.customIcon = tex
            ClearCursor()
            DebouncedRebuild()
            RefreshDetail()
          end
          return
        end
        -- Left-click without cursor: open icon picker
        ShowIconPicker(self, function(tex)
          cfg.customIcon = tex
          DebouncedRebuild()
          RefreshDetail()
        end)
      end)

      iconFrame:SetScript("OnReceiveDrag", function()
        local cursorType, id, subType, spellID = GetCursorInfo()
        if not cursorType then
          return
        end
        local tex
        if cursorType == "spell" then
          tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID or id)
        elseif cursorType == "item" then
          tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        elseif cursorType == "macro" then
          local _, macroTex = GetMacroInfo(id)
          tex = macroTex
        end
        if tex then
          cfg.customIcon = tex
          ClearCursor()
          DebouncedRebuild()
          RefreshDetail()
        end
      end)

      y = y - 34
    end

    -- Action Bar (bar type only)
    if cfg.type == "bar" then
      local barOpts = {}
      for id = 1, 8 do
        barOpts[#barOpts + 1] = { text = Barshelf.BAR_INFO[id].label, value = id }
      end
      _, y = CreateDropdownButton(
        detailChild,
        indent,
        y,
        L["Action Bar"],
        barOpts,
        Barshelf.BAR_INFO[cfg.barID] and Barshelf.BAR_INFO[cfg.barID].label or "?",
        function(v)
          for oi, oc in ipairs(db.shelves) do
            if oi ~= si and oc.type == "bar" and oc.barID == v and oc.enabled then
              Barshelf:Print(L["Bar %d is already on a shelf."]:format(v))
              return
            end
          end
          cfg.barID = v
          cfg.label = Barshelf.BAR_INFO[v].label
          Barshelf:RebuildAll()
          panel._refresh()
        end
      )
    end

    -- Open Direction and Handle Style: only when overriding appearance
    if cfg.overrideAppearance then
      local anchorNames =
        { AUTO = L["Auto"], BOTTOM = L["Below"], TOP = L["Above"], LEFT = L["Left"], RIGHT = L["Right"] }
      _, y = CreateDropdownButton(
        detailChild,
        indent,
        y,
        L["Open Direction"],
        {
          { text = L["Auto"], value = "AUTO" },
          { text = L["Below"], value = "BOTTOM" },
          { text = L["Above"], value = "TOP" },
          { text = L["Left"], value = "LEFT" },
          { text = L["Right"], value = "RIGHT" },
        },
        anchorNames[cfg.popupAnchor] or L["Auto"],
        function(v)
          cfg.popupAnchor = v
          DebouncedRebuild()
        end
      )

      local modeNames = { both = L["Icon + Label"], label = L["Label only"], icon = L["Icon only"] }
      _, y = CreateDropdownButton(
        detailChild,
        indent,
        y,
        L["Handle Style"],
        {
          { text = L["Icon + Label"], value = "both" },
          { text = L["Label only"], value = "label" },
          { text = L["Icon only"], value = "icon" },
        },
        modeNames[cfg.displayMode] or L["Icon + Label"],
        function(v)
          cfg.displayMode = v
          DebouncedRebuild()
        end
      )
    end

    -- Row Order (bar type only)
    if cfg.type == "bar" then
      local curVal = cfg.rowOrder
      local curLabel = curVal == "auto" and L["Auto (Blizzard)"]
        or curVal == "topdown" and L["Top to Bottom"]
        or curVal == "bottomup" and L["Bottom to Top"]
        or L["Use Global"]
      _, y = CreateDropdownButton(
        detailChild,
        indent,
        y,
        L["Row Order"],
        {
          { text = L["Use Global"], value = nil },
          { text = L["Auto (Blizzard)"], value = "auto" },
          { text = L["Top to Bottom"], value = "topdown" },
          { text = L["Bottom to Top"], value = "bottomup" },
        },
        curLabel,
        function(v)
          cfg.rowOrder = v
          DebouncedRebuild()
        end
      )
    end

    -- Dock (only if >1)
    if #db.docks > 1 then
      local dockOpts = {}
      for _, dc in ipairs(db.docks) do
        dockOpts[#dockOpts + 1] = { text = dc.name, value = dc.id }
      end
      local curDockName = "Main"
      for _, dc in ipairs(db.docks) do
        if dc.id == cfg.dockID then
          curDockName = dc.name
          break
        end
      end
      _, y = CreateDropdownButton(detailChild, indent, y, L["Dock"], dockOpts, curDockName, function(v)
        cfg.dockID = v
        DebouncedRebuild()
        RefreshList()
      end)
    end

    -- Status shelf: Show XP / Show Rep checkboxes
    if cfg.type == "status" then
      y = y - 6
      local statusHdr = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      statusHdr:SetPoint("TOPLEFT", indent, y)
      statusHdr:SetText("|cffffffff" .. L["Status Options"] .. "|r")
      y = y - 18

      _, y = CreateCheckbox(detailChild, indent, y, L["Show XP Bar"], cfg.showXP ~= false, function(v)
        cfg.showXP = v
        DebouncedRebuild()
      end)

      _, y = CreateCheckbox(detailChild, indent, y, L["Show Reputation Bar"], cfg.showRep ~= false, function(v)
        cfg.showRep = v
        DebouncedRebuild()
      end)

      -- Tracked factions
      y = y - 6
      local trackHdr = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      trackHdr:SetPoint("TOPLEFT", indent, y)
      trackHdr:SetText("|cffffffff" .. L["Tracked Factions"] .. "|r")
      y = y - 18

      cfg.trackedFactions = cfg.trackedFactions or {}

      -- List current tracked factions with remove buttons
      for i, factionID in ipairs(cfg.trackedFactions) do
        local fName = ""
        pcall(function()
          local fData = C_Reputation.GetFactionDataByID(factionID)
          if fData then
            fName = fData.name or ("Faction #" .. factionID)
          end
        end)
        if fName == "" then
          fName = "Faction #" .. factionID
        end

        local row = CreateFrame("Frame", nil, detailChild)
        row:SetSize(250, 20)
        row:SetPoint("TOPLEFT", indent, y)

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText(fName)

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(20, 18)
        removeBtn:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
        removeBtn:SetText("X")
        removeBtn:SetScript("OnClick", function()
          table.remove(cfg.trackedFactions, i)
          Barshelf:RebuildAll()
          Barshelf:RefreshConfig()
        end)

        y = y - 22
      end

      -- "Add Faction" button with hierarchical faction picker
      local addFactionBtn = CreateFrame("Button", nil, detailChild, "UIPanelButtonTemplate")
      addFactionBtn:SetSize(120, 20)
      addFactionBtn:SetPoint("TOPLEFT", indent, y)
      addFactionBtn:SetText(L["+ Add Faction"])
      addFactionBtn:SetScript("OnClick", function(self)
        ShowFactionPicker(self, function(factionID)
          cfg.trackedFactions = cfg.trackedFactions or {}
          cfg.trackedFactions[#cfg.trackedFactions + 1] = factionID
          Barshelf:RebuildAll()
          Barshelf:RefreshConfig()
        end, cfg.trackedFactions)
      end)
      y = y - 28
    end

    y = y - 6

    local isBar = cfg.type == "bar"
    local isMicro = cfg.type == "micro"
    local isBags = cfg.type == "bags"
    local isStatus = cfg.type == "status"
    -- Pinning section (not for bags — bags are handle-only, no popup to pin)
    if not isBags then
      local pinHdr = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      pinHdr:SetPoint("TOPLEFT", indent, y)
      pinHdr:SetText("|cffffffff" .. L["Pinning"] .. "|r")
      y = y - 18

      _, y = CreateCheckbox(detailChild, indent, y, L["Pin as bar (always visible)"], cfg.pinned or false, function(v)
        if InCombatLockdown() then
          Barshelf:Print(L["Cannot change pinning in combat."])
          return
        end
        cfg.pinned = v
        if not v then
          cfg.pinnedPoint = nil
        end
        Barshelf:RebuildAll()
        Barshelf:RefreshConfig()
      end)

      if cfg.pinned then
        _, y = CreateSlider(
          detailChild,
          indent,
          y,
          L["Bar idle opacity"],
          0,
          1,
          0.05,
          cfg.popupIdleAlpha or 1.0,
          function(v)
            cfg.popupIdleAlpha = v
            for _, shelf in ipairs(Barshelf.shelves) do
              if shelf.config == cfg and shelf.popup and shelf.popup.UpdatePinnedAlpha then
                shelf.popup:UpdatePinnedAlpha()
              end
            end
          end
        )

        local resetPosBtn = CreateFrame("Button", nil, detailChild, "UIPanelButtonTemplate")
        resetPosBtn:SetSize(140, 22)
        resetPosBtn:SetPoint("TOPLEFT", indent, y)
        resetPosBtn:SetText(L["Reset Bar Position"])
        resetPosBtn:SetScript("OnClick", function()
          cfg.pinnedPoint = nil
          DebouncedRebuild()
        end)
        y = y - 28
      end
    end -- not isBags

    y = y - 6

    local hideLayoutControls = isStatus or isBags

    -- Status/bags shelves have no button grid; skip layout section entirely
    if not hideLayoutControls then
      -- Layout & Sizing section header
      local layoutHdr = detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      layoutHdr:SetPoint("TOPLEFT", indent, y)
      layoutHdr:SetText("|cffffffff" .. L["Layout & Sizing"] .. "|r")
      y = y - 18

      -- Micro/bags shelves auto-detect button count; don't show # of Icons or Icon Size
      if not isMicro and not isBags then
        _, y = CreateSlider(
          detailChild,
          indent,
          y,
          L["# of Icons"],
          1,
          isBar and 12 or 24,
          1,
          cfg.numButtons or 12,
          function(v)
            cfg.numButtons = v
            DebouncedRebuild()
          end
        )
      end

      _, y = CreateSlider(
        detailChild,
        indent,
        y,
        L["# of Rows"],
        1,
        (isMicro or isBags) and 4 or (isBar and 12 or 24),
        1,
        cfg.numRows or 1,
        function(v)
          cfg.numRows = v
          DebouncedRebuild()
        end
      )

      if not isMicro and not isBags then
        _, y = CreateSlider(
          detailChild,
          indent,
          y,
          L["Icon Size"],
          20,
          56,
          2,
          cfg.buttonSize or (isBar and 45 or 36),
          function(v)
            cfg.buttonSize = v
            DebouncedRebuild()
          end
        )
      end

      _, y = CreateSlider(detailChild, indent, y, L["Icon Padding"], 0, 12, 1, cfg.buttonPadding or 2, function(v)
        cfg.buttonPadding = v
        DebouncedRebuild()
      end)
    end

    y = y - 6

    -- Override Appearance section (uses global Appearance settings unless overridden)
    if not isBags then
      -- Auto-detect: if user has per-shelf values that differ from globals, enable override
      if cfg.overrideAppearance == nil then
        local globalIcon = Barshelf.db.profile.handleIconSize or 16
        local globalFont = Barshelf.db.profile.handleFontSize or 12
        local globalMode = Barshelf.db.profile.defaultDisplayMode or "both"
        local globalAnchor = Barshelf.db.profile.defaultPopupAnchor or "AUTO"
        if
          (cfg.iconSize and cfg.iconSize ~= globalIcon)
          or (cfg.labelFontSize and cfg.labelFontSize ~= globalFont)
          or (cfg.displayMode and cfg.displayMode ~= globalMode)
          or (cfg.popupAnchor and cfg.popupAnchor ~= globalAnchor)
        then
          cfg.overrideAppearance = true
        end
      end

      y = y - 6
      _, y = CreateCheckbox(
        detailChild,
        indent,
        y,
        L["Override Appearance"],
        cfg.overrideAppearance or false,
        function(v)
          cfg.overrideAppearance = v
          if not v then
            -- Clear overrides so globals take effect
            cfg.iconSize = nil
            cfg.labelFontSize = nil
            cfg.displayMode = nil
            cfg.popupAnchor = nil
          else
            -- Initialize with current global values
            cfg.iconSize = cfg.iconSize or Barshelf.db.profile.handleIconSize or 16
            cfg.labelFontSize = cfg.labelFontSize or Barshelf.db.profile.handleFontSize or 12
            cfg.displayMode = cfg.displayMode or Barshelf.db.profile.defaultDisplayMode or "both"
            cfg.popupAnchor = cfg.popupAnchor or Barshelf.db.profile.defaultPopupAnchor or "AUTO"
          end
          DebouncedRebuild()
          RefreshDetail()
        end
      )

      if cfg.overrideAppearance then
        _, y = CreateSlider(detailChild, indent, y, L["Handle Icon Size"], 10, 32, 1, cfg.iconSize or 16, function(v)
          cfg.iconSize = v
          DebouncedRebuild()
        end)

        _, y = CreateSlider(
          detailChild,
          indent,
          y,
          L["Handle Font Size"],
          8,
          18,
          1,
          cfg.labelFontSize or 12,
          function(v)
            cfg.labelFontSize = v
            DebouncedRebuild()
          end
        )
      end

      y = y - 6
    end

    detailChild:SetHeight(math.abs(y) + 20)
  end

  ---------------------------------------------------------------------------
  local function Refresh()
    local db = Barshelf.db.profile
    -- Clamp selection
    if selectedShelf and (selectedShelf < 1 or selectedShelf > #db.shelves) then
      selectedShelf = nil
    end
    if selectedDock then
      local found = false
      for _, dc in ipairs(db.docks) do
        if dc.id == selectedDock then
          found = true
          break
        end
      end
      if not found then
        selectedDock = nil
      end
    end
    RefreshList()
    RefreshDetail()
  end

  addShelfBtn:SetScript("OnClick", function(self)
    local db = Barshelf.db.profile
    local dockID = GetSelectedDockID()

    -- Build dropdown options dynamically
    local options = {}

    -- Action Bars 1-8 (skip already-used bars)
    local usedBars = {}
    for _, cfg in ipairs(db.shelves) do
      if cfg.type == "bar" and cfg.enabled then
        usedBars[cfg.barID] = true
      end
    end
    for id = 1, 8 do
      if not usedBars[id] then
        options[#options + 1] = { text = Barshelf.BAR_INFO[id].label, value = "bar:" .. id }
      end
    end

    -- Custom
    options[#options + 1] = { text = "Custom", value = "custom" }

    -- Micro Menu (hidden if already exists)
    local hasMicro = false
    for _, cfg in ipairs(db.shelves) do
      if cfg.type == "micro" and cfg.enabled then
        hasMicro = true
        break
      end
    end
    if not hasMicro then
      options[#options + 1] = { text = "Micro Menu", value = "micro" }
    end

    -- Bags (hidden if already exists)
    local hasBags = false
    for _, cfg in ipairs(db.shelves) do
      if cfg.type == "bags" and cfg.enabled then
        hasBags = true
        break
      end
    end
    if not hasBags then
      options[#options + 1] = { text = "Bags", value = "bags" }
    end

    -- Status (hidden if already exists)
    local hasStatus = false
    for _, cfg in ipairs(db.shelves) do
      if cfg.type == "status" and cfg.enabled then
        hasStatus = true
        break
      end
    end
    if not hasStatus then
      options[#options + 1] = { text = "Status", value = "status" }
    end

    ShowDropdown(self, options, function(value)
      if value == "custom" then
        Barshelf:AddCustomShelf("Custom", dockID)
      elseif value == "micro" then
        Barshelf:AddMicroShelf(dockID)
      elseif value == "bags" then
        Barshelf:AddBagShelf(dockID)
      elseif value == "status" then
        Barshelf:AddStatusShelf(dockID)
      elseif value:find("^bar:") then
        local barID = tonumber(value:match("^bar:(%d+)$"))
        if barID then
          Barshelf:AddBarShelf(barID, dockID)
        end
      end
      selectedShelf = #db.shelves
      selectedDock = nil
      Refresh()
    end)
  end)

  addDockBtn:SetScript("OnClick", function()
    Barshelf:AddDock()
    Refresh()
  end)

  panel._refresh = Refresh
  panel:SetScript("OnShow", function()
    Refresh()
  end)
  Refresh()
end

---------------------------------------------------------------------------
-- Panel builders (dispatched lazily on first OnShow)
---------------------------------------------------------------------------
local function BuildGeneralPanel(panel)
  buildAceConfigPanel(panel, "Barshelf_General", L["General"], L["Global behavior settings for all shelves and docks."])
end

local function BuildAppearancePanel(panel)
  buildAceConfigPanel(
    panel,
    "Barshelf_Appearance",
    L["Appearance"],
    L["Visual settings for docks, shelf popups, handles, and bar defaults."]
  )
end

local function BuildProfilesPanel(panel)
  AceConfig:RegisterOptionsTable("Barshelf_Profiles", AceDBOptions:GetOptionsTable(Barshelf.db))
  buildAceConfigPanel(panel, "Barshelf_Profiles", L["Profiles"], L["Manage saved variable profiles."])
end

local PANEL_BUILDERS = {
  General = BuildGeneralPanel,
  Appearance = BuildAppearancePanel,
  ["Shelves & Docks"] = BuildShelvesAndDocksPanel,
  Profiles = BuildProfilesPanel,
}

---------------------------------------------------------------------------
-- Register all panels with Blizzard Settings
---------------------------------------------------------------------------
local function RegisterAllPanels()
  if parentCategory then
    return
  end

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
    desc:SetText(
      L["Access your hidden action bars through floating popup shelves."]
        .. "\n\n"
        .. L["Select a subcategory on the left to configure Barshelf."]
    )
  end)

  -- Create subcategories with lazy building
  for _, name in ipairs(SUB_NAMES) do
    local p = createSubPanel()
    local subcat = Settings.RegisterCanvasLayoutSubcategory(parentCategory, p, L[name])
    subcategories[name] = { category = subcat, panel = p, built = false }

    p:SetScript("OnShow", function(self)
      if subcategories[name].built then
        return
      end
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
  if not parentCategory then
    return
  end

  -- Pre-select a shelf if requested
  if shelfIndex then
    selectedShelf = shelfIndex
    subcategoryName = subcategoryName or "Shelves & Docks"
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
      self:Print(L["Settings will open after combat ends."])
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
  local sub = subcategories["Shelves & Docks"]
  if sub and sub.built and sub.panel and sub.panel:IsShown() and sub.panel._refresh then
    sub.panel._refresh()
  end
end

---------------------------------------------------------------------------
-- SetupOptions: called from Core.lua's OnInitialize
---------------------------------------------------------------------------
function Barshelf:SetupOptions()
  RegisterAllPanels()
end
