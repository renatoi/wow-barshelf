#!/usr/bin/env lua
---------------------------------------------------------------------------
-- Migration backwards-compatibility tests
-- Run: lua tests/test_migration.lua
-- Verifies that saved variable migration preserves user data.
---------------------------------------------------------------------------

local passed, failed = 0, 0

local function assert_eq(a, b, msg)
  if a == b then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
    print("  expected: " .. tostring(b))
    print("  got:      " .. tostring(a))
  end
end

local function assert_true(v, msg)
  if v then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

-- Stubs for WoW API
function UnitName()
  return _G._testCharName or "TestChar"
end
function GetRealmName()
  return _G._testRealm or "TestRealm"
end
function InCombatLockdown()
  return false
end

-- Minimal AceAddon stub
local Barshelf = { shelves = {}, docks = {}, combatQueue = {} }
Barshelf.Print = function(self, msg)
  _G._lastPrint = msg
end

-- Load migration function directly
local function loadMigration()
  -- Re-define from Core.lua logic
  function Barshelf:MigrateOldDB()
    if not BarshelfDB or not next(BarshelfDB) then
      return
    end
    if BarshelfDB._migrated then
      return
    end
    local charKey = UnitName("player") .. " - " .. GetRealmName()
    local src = BarshelfDB
    if not src.profiles then
      src = {
        profileKeys = { [charKey] = charKey },
        profiles = { [charKey] = src },
      }
    end
    if not BarshelfGlobalDB then
      BarshelfGlobalDB = {}
    end
    if not BarshelfGlobalDB.profiles then
      BarshelfGlobalDB.profiles = {}
    end
    if not BarshelfGlobalDB.profileKeys then
      BarshelfGlobalDB.profileKeys = {}
    end
    local oldProfileName = src.profileKeys[charKey]
    local profileData = oldProfileName and src.profiles[oldProfileName]
    if profileData then
      if not BarshelfGlobalDB.profiles[charKey] or not next(BarshelfGlobalDB.profiles[charKey]) then
        BarshelfGlobalDB.profiles[charKey] = profileData
      end
      BarshelfGlobalDB.profileKeys[charKey] = charKey
    end
    BarshelfDB._migrated = true
    self:Print("Migrated shelves for " .. charKey .. ".")
  end
end

local function reset()
  BarshelfDB = nil
  BarshelfGlobalDB = nil
  _G._lastPrint = nil
end

---------------------------------------------------------------------------
-- Test 1: v1.1 AceDB format migrates correctly
---------------------------------------------------------------------------
print("Test 1: v1.1 AceDB format → BarshelfGlobalDB")
reset()
loadMigration()
_G._testCharName = "Iduna"
_G._testRealm = "Stormrage"

BarshelfDB = {
  profileKeys = { ["Iduna - Stormrage"] = "Default" },
  profiles = {
    ["Default"] = {
      shelves = {
        { type = "bar", barID = 2, label = "Action Bar 2", enabled = true },
        { type = "bar", barID = 3, label = "Action Bar 3", enabled = true },
        { type = "custom", label = "Custom", enabled = true },
      },
      dockIdleAlpha = 0,
      closeOthers = false,
    },
  },
}
BarshelfGlobalDB = nil

Barshelf:MigrateOldDB()

assert_true(BarshelfGlobalDB ~= nil, "BarshelfGlobalDB created")
assert_eq(BarshelfGlobalDB.profileKeys["Iduna - Stormrage"], "Iduna - Stormrage", "profileKey set to charKey")
local profile = BarshelfGlobalDB.profiles["Iduna - Stormrage"]
assert_true(profile ~= nil, "profile exists under charKey")
assert_eq(#profile.shelves, 3, "3 shelves migrated")
assert_eq(profile.shelves[1].label, "Action Bar 2", "first shelf label")
assert_eq(profile.dockIdleAlpha, 0, "appearance setting preserved")
assert_eq(profile.closeOthers, false, "behavior setting preserved")
assert_true(BarshelfDB._migrated, "marked as migrated")

---------------------------------------------------------------------------
-- Test 2: Second character migrates independently
---------------------------------------------------------------------------
print("Test 2: Second character migrates independently")
_G._testCharName = "Ocaratossiu"
_G._testRealm = "Illidan"

-- Simulate Ocaratossiu's per-character data
BarshelfDB = {
  profileKeys = { ["Ocaratossiu - Illidan"] = "Default" },
  profiles = {
    ["Default"] = {
      shelves = {
        { type = "bar", barID = 1, label = "Action Bar 1", enabled = true },
      },
    },
  },
}
-- BarshelfGlobalDB still has Iduna's data from Test 1

Barshelf:MigrateOldDB()

assert_eq(BarshelfGlobalDB.profileKeys["Ocaratossiu - Illidan"], "Ocaratossiu - Illidan", "Ocaratossiu profileKey")
assert_eq(#BarshelfGlobalDB.profiles["Ocaratossiu - Illidan"].shelves, 1, "Ocaratossiu has 1 shelf")
assert_eq(BarshelfGlobalDB.profiles["Ocaratossiu - Illidan"].shelves[1].label, "Action Bar 1", "Ocaratossiu shelf label")
-- Iduna's data unchanged
assert_eq(#BarshelfGlobalDB.profiles["Iduna - Stormrage"].shelves, 3, "Iduna still has 3 shelves")

---------------------------------------------------------------------------
-- Test 3: Already migrated skips
---------------------------------------------------------------------------
print("Test 3: Already migrated skips")
_G._testCharName = "Iduna"
_G._testRealm = "Stormrage"
_G._lastPrint = nil

BarshelfDB = { _migrated = true, profiles = { Default = { shelves = {} } }, profileKeys = {} }

Barshelf:MigrateOldDB()

assert_eq(_G._lastPrint, nil, "no migration message printed")

---------------------------------------------------------------------------
-- Test 4: Empty BarshelfDB skips
---------------------------------------------------------------------------
print("Test 4: Empty BarshelfDB skips")
reset()
loadMigration()
_G._lastPrint = nil

BarshelfDB = {}
BarshelfGlobalDB = nil

Barshelf:MigrateOldDB()

assert_eq(BarshelfGlobalDB, nil, "BarshelfGlobalDB not created")
assert_eq(_G._lastPrint, nil, "no migration message")

---------------------------------------------------------------------------
-- Test 5: nil BarshelfDB skips (new user)
---------------------------------------------------------------------------
print("Test 5: nil BarshelfDB skips (new user)")
reset()
loadMigration()
_G._lastPrint = nil

BarshelfDB = nil
BarshelfGlobalDB = nil

Barshelf:MigrateOldDB()

assert_eq(BarshelfGlobalDB, nil, "BarshelfGlobalDB not created for new user")

---------------------------------------------------------------------------
-- Test 6: pre-AceDB flat format migrates
---------------------------------------------------------------------------
print("Test 6: pre-AceDB flat format migrates")
reset()
loadMigration()
_G._testCharName = "OldUser"
_G._testRealm = "OldRealm"

BarshelfDB = {
  shelves = {
    { type = "bar", barID = 1, label = "Bar 1", enabled = true },
  },
  docks = { { id = 1, name = "Main" } },
}
BarshelfGlobalDB = nil

Barshelf:MigrateOldDB()

assert_true(BarshelfGlobalDB ~= nil, "BarshelfGlobalDB created for flat format")
local flatProfile = BarshelfGlobalDB.profiles["OldUser - OldRealm"]
assert_true(flatProfile ~= nil, "flat profile migrated under charKey")
assert_true(flatProfile.shelves ~= nil, "shelves present")
assert_eq(#flatProfile.shelves, 1, "1 shelf migrated from flat format")

---------------------------------------------------------------------------
-- Test 7: Won't overwrite existing non-empty profile
---------------------------------------------------------------------------
print("Test 7: Won't overwrite existing non-empty profile")
reset()
loadMigration()
_G._testCharName = "Existing"
_G._testRealm = "Realm"

BarshelfGlobalDB = {
  profileKeys = { ["Existing - Realm"] = "Existing - Realm" },
  profiles = {
    ["Existing - Realm"] = {
      shelves = { { type = "bar", barID = 5, label = "Existing Bar", enabled = true } },
    },
  },
}
BarshelfDB = {
  profileKeys = { ["Existing - Realm"] = "Default" },
  profiles = {
    ["Default"] = {
      shelves = { { type = "bar", barID = 1, label = "Old Bar", enabled = true } },
    },
  },
}

Barshelf:MigrateOldDB()

assert_eq(BarshelfGlobalDB.profiles["Existing - Realm"].shelves[1].label, "Existing Bar", "existing profile NOT overwritten")

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
else
  print("All tests passed!")
end
