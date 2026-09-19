-- Ordered beats inside a step or an encounter.
-- A holder's `sequence` lists items that run in order once the holder has begun: its step has
-- started, or its encounter has placed. Each item waits for at most one event, then for its delay,
-- then acts:
--   on = trigger or monitor slot       a report counts even before the item is reached, since an
--                                      armed volume reports once
--   finished = scene slot              the scene reports finished after the previous item acted
--   interacted = object slot           the object reports a use after the previous item acted
--   cleared = {encounter ids}          every squad of those encounters is gone
--   any wait another capability registers, such as `spoken`
--   after_ms = milliseconds            counted once the event holds
--   lines, scenes, move, objects, signal, stop, run(context, state)   the action, in that order
-- A step can end when its sequence has finished: `ends = {sequence = true}`.
-- Each sequence is its own flow graph, so a reattach resumes it and a checkpoint replays it.
local lib = require("lib.mission_lib")
local flow = require("lib.flow")
local common = require("lib.campaign.common")
local EventKind = require("sunrise.activity_sdk").EventKind

local sequence = {name = "sequence"}

-- Each item takes up to two flow steps and one fact, and a flow holds 64 of each.
local ITEM_LIMIT = 32
local WAITS = {"on", "finished", "interacted", "cleared"}
-- A slot also shows up in other events, such as an object's state when it appears, so a wait on
-- a report only counts the event kind that is that report.
local REPORTS = {finished = EventKind.SCENE_FINISHED, interacted = EventKind.OBJECT_INTERACTED}

local function sequenced(content)
    local result = {}
    for _, step in ipairs(content.steps or {}) do
        if step.sequence ~= nil then
            result[#result + 1] = {where = "step " .. tostring(step.id), holder = step, step = true}
        end
    end
    for _, encounter in ipairs(content.encounters or {}) do
        if encounter.sequence ~= nil then
            result[#result + 1] = {where = "encounter " .. tostring(encounter.id),
                holder = encounter}
        end
    end
    return result
end

function sequence.check(content, builder)
    local legs = builder:need("legs")
    for _, place in ipairs(sequenced(content)) do
        local items = place.holder.sequence
        assert(type(items) == "table" and #items > 0 and #items <= ITEM_LIMIT,
            place.where .. " sequence must be a list of at most " .. ITEM_LIMIT .. " items")
        for index = 1, #items do
            local where = place.where .. " sequence " .. index
            local item = lib.one(items[index], where)
            assert(item.sequence == nil, where .. " cannot hold a sequence")
            if item.on ~= nil then
                assert(legs.armed[item.on] or legs.watched[item.on],
                    where .. " waits on a volume no leg arms or watches")
            end
            if item.cleared ~= nil then
                lib.one(builder:find("encounters"), where .. " clear needs encounters")
            end
            assert(item.after_ms == nil
                or (math.type(item.after_ms) == "integer" and item.after_ms > 0),
                where .. " after_ms must be a positive integer")
            assert(item.run == nil or type(item.run) == "function",
                where .. " run must be a function")
            if item.lines ~= nil then lib.one(content.dialogue_sensor, "dialogue sensor") end
        end
    end
    for _, step in ipairs(content.steps or {}) do
        if step.ends ~= nil and step.ends.sequence ~= nil then
            assert(step.ends.sequence == true and step.sequence ~= nil,
                "step " .. tostring(step.id) .. " ends on a sequence it does not hold")
        end
    end
end

function sequence.declare(content, builder)
    -- Filled by build; a step's end reads its own sequence graph.
    local graph_of = {}
    builder:provide("sequence", {graph_of = graph_of})
    builder:end_kind("sequence", function(step)
        return {function(context, state)
            local graph = graph_of[step]
            return graph ~= nil and graph:finished(context, state)
        end}
    end)
end

function sequence.build(content, builder)
    local places = sequenced(content)
    if #places == 0 then return end
    local graph_of = builder:need("sequence").graph_of
    local core, encounters = builder:need("core"), builder:find("encounters")
    local timed = false
    for number, place in ipairs(places) do
        local holder = place.holder
        local key = content.key .. ".q" .. number
        local facts, steps, graph = {}, {}, nil
        -- A step that already finished does not begin its sequence again when a checkpoint
        -- replays the steps after it.
        local function begun(context, state)
            if place.step then
                return core.graph():started(context, state, holder.id)
                    and not core.finished(context, state, holder.id)
            end
            return encounters.placed(context, state, holder.id)
        end
        local previous = nil
        for index, item in ipairs(holder.sequence) do
            -- Extra wait kinds are registered in declare, after this capability's check.
            local waits, extra = 0, nil
            for _, wait in ipairs(WAITS) do
                if item[wait] ~= nil then waits = waits + 1 end
            end
            for _, name in ipairs(builder.wait_kind_names) do
                if item[name] ~= nil then waits, extra = waits + 1, name end
            end
            assert(waits <= 1,
                place.where .. " sequence " .. index .. " waits on more than one event")
            local before = previous
            -- The item before has acted, or this is the first item and its holder has begun.
            local function reached(context, state)
                if before == nil then return begun(context, state) end
                return graph:started(context, state, before)
            end
            local wait = reached
            if item.on ~= nil then
                local id = "on" .. index
                facts[#facts + 1] = {id = id, observe = function(context, _, event)
                    return lib.is_slot(context, event, item.on)
                end}
                wait = flow.all(reached, flow.fact(id))
            elseif item.finished ~= nil or item.interacted ~= nil then
                local id, target = "ev" .. index, item.finished or item.interacted
                local kind = item.finished ~= nil and REPORTS.finished or REPORTS.interacted
                facts[#facts + 1] = {id = id, observe = function(context, state, event)
                    return event.kind == kind and reached(context, state)
                        and lib.is_slot(context, event, target)
                end}
                wait = flow.all(reached, flow.fact(id))
            elseif item.cleared ~= nil then
                wait = flow.all(reached, encounters.cleared(common.list(item.cleared)))
            elseif extra ~= nil then
                wait = flow.all(reached, builder.wait_kinds[extra](item[extra]))
            end
            local after = before ~= nil and {before} or nil
            if item.after_ms ~= nil then
                timed = true
                local id, name = "t" .. index, key .. ".t" .. index
                facts[#facts + 1] = {id = id, observe = function(_, _, event)
                    return event.timer_name == name
                end}
                steps[#steps + 1] = {id = "w" .. index, after = after, when = wait,
                    run = function(context) context:start_timer(name, item.after_ms) end,
                    await = flow.fact(id)}
                after, wait = {"w" .. index}, nil
            end
            steps[#steps + 1] = {id = "a" .. index, after = after, when = wait,
                run = function(context, state)
                    common.speak(content, context, item)
                    builder:run_actions(context, state, item)
                    if item.run ~= nil then item.run(context, state) end
                end}
            previous = "a" .. index
        end
        graph = flow.new{key = key, facts = facts, steps = steps}
        builder:graph(graph)
        graph_of[holder] = graph
    end
    if timed then
        builder:on("on_event_timer_elapsed", function(context, state, event)
            builder:handle(context, state, event)
        end)
    end
    -- A sequence finishing inside one event can end its step, and a step starting can begin the
    -- next sequence, so every graph advances once more after all of them handled the event.
    builder:after_handle(function(context, state)
        builder:advance(context, state)
    end)
end

return sequence
