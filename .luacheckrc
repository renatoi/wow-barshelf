std = "lua51"
max_line_length = false

exclude_files = {
	"Libs/",
	".luacheckrc",
}

ignore = {
	"11./SLASH_.*",
	"11./BINDING_.*",
	"122/StaticPopupDialogs",
	"212/self",
	"211",            -- Unused local variable
	"213",            -- Unused loop variable
	"31./_",          -- Unused/setting non-standard global _
	"42.",            -- Shadowing a local variable
	"43.",            -- Shadowing an upvalue
	"542",            -- Empty if branch
}

-- WoW API globals
read_globals = {
	-- Core WoW
	"bit",
	"C_EditMode",
	"C_Item",
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
	"Settings",
	"UIParent",
	"UISpecialFrames",
	"UnitName",
	"UnregisterStateDriver",
	"tinsert",
	"strtrim",
	"wipe",
	"pcall",
	"ActionButton_Update",
	"PickupItem",
	"PickupMacro",
	"PickupSpell",
}

-- Addon globals
globals = {
	"Barshelf",
	"BarshelfDB",
	"_",
}
