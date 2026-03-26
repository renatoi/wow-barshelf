.PHONY: lint format format-check

lint:
	luacheck Core.lua Options.lua Dock.lua Popup.lua BarShelf.lua CustomShelf.lua

format:
	stylua Core.lua Options.lua Dock.lua Popup.lua BarShelf.lua CustomShelf.lua

format-check:
	stylua --check Core.lua Options.lua Dock.lua Popup.lua BarShelf.lua CustomShelf.lua
