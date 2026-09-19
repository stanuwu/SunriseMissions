-- Declarative world changes any step, encounter or sequence item can carry:
--   move     = {to = "<device transition>", slots = {type-23 slots}, snap = true}
--   objects  = {slots = {type-4 slots}, active = false}
--   signal   = {scene = mission.scenes.<NAME>, keys = {event keys}}  keys for an active scene
--   stop     = {mission.scenes.<NAME>, ...}                           ends each scene's generation
--   retire   = {Squad.<NAME>, ...}                                    removes the squads' members
--   interact = {slots = {type-4 slots}, active = false, used = false} offers or withdraws a use
--   music    = section, or {section = section, enabled = false}      selects a music section
--   perform  = {cells = {type-2 slots}, sequence = "<SEQUENCE SYMBOL>"}
--              creates each cell's actor playing that sequence of its own action table
-- They run in that order, after the holder's own scenes. Music plays through the mission's
-- `music_sensor`. A performed actor has no objective: an `assign` once it has landed gives it one.
local lib = require("lib.mission_lib")
local common = require("lib.campaign.common")

local actions = {name = "actions"}

local function slots(value, where)
    assert(type(value) == "table" and #value > 0, where .. " needs a nonempty slot list")
    for index = 1, #value do lib.one(value[index], where .. " slot " .. index) end
end

local function scene(value, where)
    assert(type(value) == "table" and type(value.id) == "string",
        where .. " must name a mission.scenes entry")
end

-- A music sensor holds 128 sections.
local MUSIC_SECTIONS = 128

-- `music = 8` is short for `music = {section = 8}`.
local function music_of(value)
    if type(value) == "table" then return value end
    return {section = value}
end

function actions.check(content)
    for _, place in ipairs(common.holders(content)) do
        local holder, where = place.holder, place.where
        if holder.move ~= nil then
            assert(type(holder.move.to) == "string", where .. " move needs a transition name")
            slots(holder.move.slots, where .. " move")
            assert(holder.move.snap == nil or type(holder.move.snap) == "boolean",
                where .. " move snap must be a boolean")
        end
        if holder.objects ~= nil then
            slots(holder.objects.slots, where .. " objects")
            assert(holder.objects.active == nil or type(holder.objects.active) == "boolean",
                where .. " objects active must be a boolean")
        end
        if holder.signal ~= nil then
            scene(holder.signal.scene, where .. " signal")
            local keys = holder.signal.keys
            assert(type(keys) == "table" and #keys > 0, where .. " signal needs keys")
            for number = 1, #keys do
                assert(math.type(keys[number]) == "integer" and keys[number] > 0,
                    where .. " signal key " .. number .. " must be a positive integer")
            end
        end
        if holder.stop ~= nil then
            assert(type(holder.stop) == "table" and #holder.stop > 0, where .. " stop needs scenes")
            for number = 1, #holder.stop do scene(holder.stop[number], where .. " stop") end
        end
        if holder.retire ~= nil then slots(holder.retire, where .. " retire") end
        if holder.interact ~= nil then
            slots(holder.interact.slots, where .. " interact")
            assert(holder.interact.active == nil or type(holder.interact.active) == "boolean",
                where .. " interact active must be a boolean")
            assert(holder.interact.used == nil or type(holder.interact.used) == "boolean",
                where .. " interact used must be a boolean")
        end
        if holder.perform ~= nil then
            slots(holder.perform.cells, where .. " perform")
            assert(type(holder.perform.sequence) == "string",
                where .. " perform needs a sequence symbol")
        end
        if holder.music ~= nil then
            lib.one(content.music_sensor, "music sensor")
            local music = music_of(holder.music)
            assert(math.type(music.section) == "integer" and music.section >= 0
                and music.section < MUSIC_SECTIONS,
                where .. " music section must be an integer below " .. MUSIC_SECTIONS)
            assert(music.enabled == nil or type(music.enabled) == "boolean",
                where .. " music enabled must be a boolean")
        end
    end
end

function actions.declare(content, builder)
    builder:action("move", function(context, _, _, move)
        local transition = context.sdk.device_transitions[move.to]
        for _, slot in ipairs(move.slots) do
            context:slot(slot):transition{transition = transition, snap = move.snap}
        end
    end)
    builder:action("objects", function(context, _, _, objects)
        context:activate_objects{slots = objects.slots, active = objects.active}
    end)
    builder:action("signal", function(context, _, _, signal)
        local target = context:scene(signal.scene.id)
        for _, key in ipairs(signal.keys) do target:send_event{key = key} end
    end)
    builder:action("stop", function(context, _, _, list)
        for _, target in ipairs(list) do context:scene(target.id):stop{} end
    end)
    -- A squad has no retire call: placing it again with every count at zero removes its members.
    builder:action("retire", function(context, _, _, list)
        for _, id in ipairs(list) do
            local squad = context:squad(id)
            local counts = squad:counts()
            for lane = 1, counts.count do counts:set(lane, 0) end
            squad:place{counts = counts, mode = context.sdk.squad_modes.replace}
        end
    end)
    -- The use row is sent as used by default, since a row not used yet shows a generic prompt.
    -- `used = false` sends it fresh instead, for an object whose use is not a one-off.
    builder:action("interact", function(context, _, _, interact)
        local active = interact.active ~= false
        local used = active and interact.used ~= false
        for _, slot in ipairs(interact.slots) do
            context:slot(slot):set_interactable_object{active = active, used = used}
        end
    end)
    -- The sequence is looked up by its symbol in the actor's own table, so no key is written down.
    builder:action("perform", function(context, _, _, perform)
        for _, cell in ipairs(perform.cells) do
            local actor = context:slot(cell)
            local sequence = lib.one(actor:sequences()[perform.sequence],
                "actor sequence " .. perform.sequence)
            actor:run_atoms{spawn = true, atoms = {{kind = "sequence", value = sequence.key}}}
        end
    end)
    builder:action("music", function(context, _, _, value)
        local music = music_of(value)
        context:slot(content.music_sensor):set_music_section{
            section = music.section, enabled = music.enabled}
    end)
end

return actions
