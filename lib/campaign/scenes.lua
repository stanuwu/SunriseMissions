-- Authored scenes a step plays when it starts, an encounter when it places, or a sequence item
-- when it acts.
-- A step, an encounter or a sequence item lists them in `scenes`; each entry is
--   {scene = mission.scenes.<NAME>, bind = {cell slots}, keys = {event keys}, spawn = true}
-- A scene claims a combatant participant through its bound cell: the bind arms the cell for the
-- scene's own squad member spawn, so no pose goes first, and a pose would only add a duplicate.
-- The event keys join the activation's generation, so they go out once that activation reaches
-- transport. Without `keys`, the scene's authored event keys are sent in authored order.
local lib = require("lib.mission_lib")
local common = require("lib.campaign.common")

local scenes = {name = "scenes"}

local function keys_of(entry, where)
    if entry.keys ~= nil then return entry.keys end
    return assert(entry.scene.event_keys, where .. " has no authored event keys; list them in keys")
end

function scenes.check(content)
    for _, place in ipairs(common.holders(content)) do
        local list = place.holder.scenes
        if list ~= nil then
            assert(type(list) == "table" and #list > 0, place.where .. " scenes must be a list")
            for index = 1, #list do
                local where = place.where .. " scene " .. index
                local entry = lib.one(list[index], where)
                local scene = lib.one(entry.scene, where)
                assert(type(scene) == "table" and type(scene.id) == "string",
                    where .. " must name a mission.scenes entry")
                local bind = entry.bind or {}
                for number = 1, #bind do lib.one(bind[number], where .. " bind " .. number) end
                local keys = keys_of(entry, where)
                for number = 1, #keys do
                    assert(math.type(keys[number]) == "integer" and keys[number] > 0,
                        where .. " key " .. number .. " must be a positive integer")
                end
                assert(entry.spawn == nil or type(entry.spawn) == "boolean",
                    where .. " spawn must be a boolean")
            end
        end
    end
end

-- Each listed scene owns one variable holding its pending activation request. Plays are kept
-- per holder and position, so one entry table listed by two holders is still two plays.
local function collect(content)
    local plays, plays_of = {}, {}
    for _, place in ipairs(common.holders(content)) do
        local list = place.holder.scenes
        if list ~= nil then
            local own = {}
            for index, entry in ipairs(list) do
                local play = {entry = entry, keys = keys_of(entry, place.where),
                    key = content.key .. ".scene." .. (#plays + 1)}
                plays[#plays + 1] = play
                own[index] = play
            end
            plays_of[place.holder] = own
        end
    end
    return plays, plays_of
end

-- The action registers in declare, so a holder's scenes play before its other actions.
function scenes.declare(content, builder)
    local plays, plays_of = collect(content)
    if #plays == 0 then return end
    builder:action("scenes", function(context, _, holder, list)
        for index, entry in ipairs(list) do
            local play = plays_of[holder][index]
            for _, cell in ipairs(entry.bind or {}) do
                context:slot(cell):bind_combatant_to_squad{}
            end
            local request = context:scene(entry.scene.id):activate{spawn = entry.spawn}
            if #play.keys > 0 then context:set_variable(play.key, request.value) end
        end
    end)
end

function scenes.build(content, builder)
    local plays = collect(content)
    if #plays == 0 then return end
    -- A refused or expired activation sends nothing; the scene has no generation to join.
    builder:on("on_event_effect_result", function(context, state, event)
        if event.effect ~= "scene.activate" or event.request_key == nil then return end
        local value = event.request_key.value
        for _, play in ipairs(plays) do
            if state:variable(play.key) == value then
                context:clear_variable(play.key)
                if event.outcome == "transport_staged" then
                    local scene = context:scene(play.entry.scene.id)
                    for _, key in ipairs(play.keys) do scene:send_event{key = key} end
                end
            end
        end
    end)
end

return scenes
