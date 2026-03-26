std = "lua51"
max_line_length = false

exclude_files = {
	"Libs/",
	".luacheckrc",
}

ignore = {
	"11./SLASH_.*",
	"11./BINDING_.*",
	"212/self",
	"42.",
	"43.",
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
	"HasAction",
	"InCombatLockdown",
	"IsMouseButtonDown",
	"IsUsableAction",
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
}

-- Addon globals
globals = {
	"Barshelf",
	"BarshelfDB",
}
