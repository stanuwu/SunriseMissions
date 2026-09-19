-- Waits on the dialogue lines a mission plays through its dialogue sensor:
--   spoken = cue    holds once that cue has finished in this attempt
-- It works as a sequence wait and as a step end: `ends = {spoken = cue}`. A finish latches, so a
-- wait reached after its line ended still holds, and a cue finished in an earlier attempt does not
-- count after a restart. The runtime reports a finish only for a cue the script played: a line a
-- scene plays on its own reports nothing. A Sunrise build without dialogue_finished events refuses
-- `spoken` when the script loads, rather than leave the wait unmet for good.
local common = require("lib.campaign.common")
local EventKind = require("sunrise.activity_sdk").EventKind

local dialogue = {name = "dialogue"}

local function spoken_cue(value, where)
    assert(math.type(value) == "integer" and value >= 0, where .. " spoken must be a cue index")
end

-- Every sequence item and step end that waits on a cue, for checking and to know whether any does.
local function waits(content)
    local result = {}
    local function scan(where, holder)
        for index, item in ipairs(holder.sequence or {}) do
            if item.spoken ~= nil then
                result[#result + 1] = {where = where .. " sequence " .. index, cue = item.spoken}
            end
        end
    end
    for _, step in ipairs(content.steps or {}) do
        local where = "step " .. tostring(step.id)
        scan(where, step)
        if step.ends ~= nil and step.ends.spoken ~= nil then
            result[#result + 1] = {where = where .. " end", cue = step.ends.spoken}
        end
    end
    for _, encounter in ipairs(content.encounters or {}) do
        scan("encounter " .. tostring(encounter.id), encounter)
    end
    return result
end

function dialogue.check(content)
    -- `spoken` waits inside a sequence or ends a step; anywhere else it would be ignored.
    for _, place in ipairs(common.holders(content)) do
        assert(place.item or place.holder.spoken == nil,
            place.where .. " spoken belongs in a sequence item or in ends")
    end
    local list = waits(content)
    for _, wait in ipairs(list) do spoken_cue(wait.cue, wait.where) end
    if #list > 0 then
        assert(content.dialogue_sensor ~= nil, "spoken needs the mission's dialogue sensor")
        assert(EventKind.DIALOGUE_FINISHED ~= nil,
            "spoken needs a Sunrise build that reports dialogue_finished events")
    end
end

-- Each cue that finished keeps the attempt it finished in.
local function said_key(content, cue)
    return content.key .. ".said." .. cue
end

function dialogue.declare(content, builder)
    local function spoken(cue)
        local key = said_key(content, cue)
        return function(context, state)
            return state:variable(key) == context.attempt_generation
        end
    end
    builder:wait_kind("spoken", spoken)
    builder:end_kind("spoken", function(_, cue) return {spoken(cue)} end)
end

function dialogue.build(content, builder)
    if #waits(content) == 0 then return end
    builder:on("on_event_dialogue_finished", function(context, state, event)
        local sensor = context:slot(content.dialogue_sensor)
        if event.cue == nil or event.dialogue_registry_key ~= sensor.registry_key
            or event.dialogue_slot_type ~= sensor.slot_type
            or event.dialogue_slot_index ~= sensor.slot_index then
            return
        end
        context:set_variable(said_key(content, event.cue), context.attempt_generation)
        builder:handle(context, state, event)
    end)
end

return dialogue
