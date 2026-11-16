-- Resolves the generated names of one authored object, and its objective rows from their sensor.
-- A generated key is the authored name in upper case, with the object's tag appended only when
-- another object repeats that name. Placements of one prefab therefore differ in root prefab
-- and in which keys carry the tag; this module hides both, so one family binder serves every site.
-- The sandbox has no table iteration, so every lookup tries the possible keys in turn.
local lib = require("lib.mission_lib")

local site_names = {}

-- Highest index tried for a numbered slot family; placements skip numbers.
local NUMBERED_LIMIT = 15

---@class SiteObject
---@field prefab fun(stem: string): string Generated key of a slot under the root prefab.
---@field zone fun(stem: string): string Generated key of a slot beside the root prefab.
---@field find fun(stem: string): string|nil As prefab, or nil when the placement lacks the slot.
---@field find_zone fun(stem: string): string|nil As zone, or nil when the placement lacks it.
---@field numbered fun(stem: string): string[] Keys of the prefab slots stem0, stem1, ... present.

--- Binds the slots of one object.
---@param mission table Generated mission module.
---@param tag string Eight upper-case hex digits of the object's tag.
---@param root string|nil Root prefab stem in key form, such as "PF_VEXBLOCK01"; nil for none.
---@return SiteObject
function site_names.object(mission, tag, root)
    local Slot = mission.Slot
    local owned = "slot/" .. string.lower(tag) .. "/"
    local base = root ~= nil and root .. "_" or ""
    --- The tagged key, or the bare key when this object owns it.
    local function key_of(stem)
        local tagged = stem .. "_" .. tag
        if Slot[tagged] ~= nil then return tagged end
        local id = Slot[stem]
        if id ~= nil and string.sub(id, 1, #owned) == owned then return stem end
        return nil
    end
    local object = {}
    function object.prefab(stem)
        return lib.one(key_of(base .. stem), "slot " .. base .. stem .. " of object " .. tag)
    end
    function object.zone(stem)
        return lib.one(key_of(stem), "slot " .. stem .. " of object " .. tag)
    end
    function object.find(stem) return key_of(base .. stem) end
    function object.find_zone(stem) return key_of(stem) end
    function object.numbered(stem)
        local list = {}
        for number = 0, NUMBERED_LIMIT do
            local key = key_of(base .. stem .. number)
            if key ~= nil then list[#list + 1] = key end
        end
        return list
    end
    return object
end

--- Finds an objective row of a directive sensor. Generated row keys are the row's title, then the
--- title with its name hash, then numbered repeats, in an order no site can rely on.
---@param title string Title in key form, such as "SPIRE_INTEGRATION".
---@param name_hash integer Hash of the row's authored name; the same for every placement.
---@param sensor string Slot id of the type-68 sensor.
---@param element integer|nil Element of the row; zero when omitted.
---@return table row Generated mission.Directive row.
function site_names.directive(mission, title, name_hash, sensor, element)
    local hashed = title .. "_" .. string.format("%08X", name_hash)
    local key, repeats = title, 0
    while true do
        local row = mission.Directive[key]
        -- A title every sensor repeats may have no bare key; the hashed keys are dense.
        if row == nil and repeats > 0 then break end
        if row ~= nil and row.sensor == sensor and row.name_hash == name_hash
            and row.element == (element or 0) then
            return row
        end
        repeats = repeats + 1
        key = repeats == 1 and hashed or hashed .. "_" .. repeats
    end
    error("no directive " .. hashed .. " on sensor " .. sensor)
end

return site_names
