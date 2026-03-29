std = "lua51"
max_line_length = false

exclude_files = {
  "Libs/",
  "tests/",
  "TextureNames.lua",
  ".luacheckrc",
}

ignore = {
  "11./SLASH_.*",
  "11./BINDING_.*",
  "122/StaticPopupDialogs",
  "212/self",
  "211", -- Unused local variable
  "213", -- Unused loop variable
  "31./_", -- Unused/setting non-standard global _
  "42.", -- Shadowing a local variable
  "43.", -- Shadowing an upvalue
  "542", -- Empty if branch
}

-- WoW API globals
read_globals = {
  -- Core WoW
  "bit",
  "C_Container",
  "C_EditMode",
  "C_Item",
  "C_Reputation",
  "C_Spell",
  "C_Timer",
  "ChatFontNormal",
  "ClearCursor",
  "CreateFrame",
  "EditModeManagerFrame",
  "GameFontDisable",
  "GameFontDisableSmall",
  "GameFontHighlight",
  "GameFontHighlightSmall",
  "GameFontNormal",
  "GameFontNormalLarge",
  "GameFontNormalSmall",
  "GameTooltip",
  "GetActionCooldown",
  "GetActionCount",
  "GetActionTexture",
  "GetCursorInfo",
  "GetCursorPosition",
  "GetLocale",
  "GetMaxPlayerLevel",
  "GetMacroInfo",
  "GetRealmName",
  "GetScreenHeight",
  "GetTime",
  "HasAction",
  "InCombatLockdown",
  "IsMouseButtonDown",
  "IsShiftKeyDown",
  "IsUsableAction",
  "LibStub",
  "Mixin",
  "NumberFontNormal",
  "NumberFontNormalSmallGray",
  "RegisterStateDriver",
  "NO",
  "Settings",
  "StaticPopup_Show",
  "YES",
  "NUM_BAG_SLOTS",
  "NUM_TOTAL_BAG_FRAMES",
  "UIParent",
  "UISpecialFrames",
  "UnitLevel",
  "UnitName",
  "UnitXP",
  "UnitXPMax",
  "UnregisterStateDriver",
  "tinsert",
  "strtrim",
  "wipe",
  "pcall",
  "ActionButton_Update",
  "C_SpellBook",
  "C_Texture",
  "Enum",
  "FauxScrollFrame_GetOffset",
  "FauxScrollFrame_OnVerticalScroll",
  "FauxScrollFrame_Update",
  "GetLooseMacroIcons",
  "GetLooseMacroItemIcons",
  "GetMacroIcons",
  "GetMacroItemIcons",
  "GetNumSpellTabs",
  "PickupItem",
  "PickupMacro",
  "PickupSpell",
  "ToggleAllBags",
  "OpenAllBags",
  "CloseAllBags",
}

-- Addon globals
globals = {
  "Barshelf",
  "Barshelf_L",
  "Barshelf_TextureNames",
  "BarshelfDB",
  "StaticPopupDialogs",
  "BarshelfGlobalDB",
  "_",
}
