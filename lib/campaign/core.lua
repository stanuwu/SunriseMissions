-- Legs, steps and the main chain.
-- A step shows its goal when the previous step ends. It ends on its own trigger, monitor, kill,
-- ghost link, interaction or scene, and, unless a barrier holds the player, on any later step's
-- trigger or monitor. Other capabilities add their own ends through builder end kinds.
-- A step marked `checkpoint = true` is recorded once it starts; a restart keeps everything before
-- it and replays the step and what follows.
local lib = require("lib.mission_lib")
local flow = require("lib.flow")
local common = require("lib.campaign.common")
local list, speak = common.list, common.speak

local core = {name = "core"}

-- A goal without a navpoint keeps its text and shows no marker. Inside the waypoint volume the
-- marker hides. Sending the same goal again moves the marker without a popup.
local function show(content, context, step)
    context:slot(content.directive_sensor):set_directive{
        directive = step.directive,
        navpoint = step.navpoint ~= nil and context:slot(step.navpoint) or nil,
        waypoint = step.waypoint ~= nil and context:slot(step.waypoint) or nil,
    }
end

-- An armed trigger reports on every update while the player stays inside, so the first report
-- disarms it. The variable keeps a burst of reports to one disarm.
local function armed_key(id)
    return "armed/" .. id
end

local function arm_trigger(context, id)
    context:set_variable(armed_key(id), true)
    context:slot(id):fire_trigger()
end

-- A type-30 monitor reports its own entered edge and needs no disarm. One player is enough.
local function watch_monitor(context, id)
    context:slot(id):set_occupancy_condition{value = 1}
end

local function disarm_reported(context, state, event)
    local id = event.slot ~= nil and event.slot.id or nil
    if id ~= nil and state:variable(armed_key(id)) == true then
        context:clear_variable(armed_key(id))
        context:slot(id):disarm_trigger()
    end
end

-- The link and the interaction row register their objects, so they go before the goal. A row not
-- yet used shows a generic prompt, and without the row the client never reports a use.
local function begin(content, builder, step)
    return function(context, state)
        local ends = step.ends or {}
        if ends.ghost_link ~= nil then
            context:slot(ends.ghost_link):set_ghost_link{active = true}
        end
        if ends.interact ~= nil then
            context:slot(ends.interact):set_interactable_object{used = true}
        end
        if step.scene ~= nil then context:scene(step.scene):activate{} end
        if step.directive ~= nil then show(content, context, step) end
        speak(content, context, step)
        -- Arming again reports a player who is already inside the volume.
        if step.revisit then
            for _, trigger in ipairs(list(ends.trigger)) do arm_trigger(context, trigger) end
        end
        builder:run_actions(context, state, step)
        if step.on_start ~= nil then step.on_start(context) end
    end
end

local SLOT_PREFIX = "slot/"

-- A slot id is slot/<object tag>/...; a marker needs its object registered on the client.
local function object_of(slot)
    if string.sub(slot, 1, #SLOT_PREFIX) ~= SLOT_PREFIX then return nil end
    return string.sub(slot, #SLOT_PREFIX + 1, #SLOT_PREFIX + 8)
end

-- A flow group holds at most 64 conditions; a repeated fact adds nothing.
local GROUP = 64

local function any_of(options)
    local seen, unique = {}, {}
    for _, option in ipairs(options) do
        local key = type(option) == "table" and option.fact or nil
        if key == nil or not seen[key] then
            if key ~= nil then seen[key] = true end
            unique[#unique + 1] = option
        end
    end
    while #unique > GROUP do
        local folded = {}
        for start = 1, #unique, GROUP do
            local part = {}
            for index = start, math.min(start + GROUP - 1, #unique) do
                part[#part + 1] = unique[index]
            end
            folded[#folded + 1] = {any = part}
        end
        unique = folded
    end
    if #unique == 0 then return nil end
    return {any = unique}
end

function core.check(content, builder)
    lib.one(content.key, "campaign key")
    lib.one(content.directive_sensor, "directive sensor")
    assert(#lib.one(content.legs, "campaign legs") > 0, "a campaign needs a leg")
    assert(#lib.one(content.steps, "campaign steps") > 0, "a campaign needs a step")
    local armed, watched = {}, {}
    for _, leg in ipairs(content.legs) do
        lib.one(leg.state, lib.one(leg.id, "leg id") .. " state")
        for _, trigger in ipairs(leg.arm or {}) do armed[trigger] = leg.id end
        for _, monitor in ipairs(leg.watch or {}) do watched[monitor] = leg.id end
    end
    for _, step in ipairs(content.steps) do
        lib.one(step.id, "step id")
        if step.lines ~= nil then lib.one(content.dialogue_sensor, "dialogue sensor") end
        for _, trigger in ipairs(list((step.ends or {}).trigger)) do
            assert(armed[trigger], step.id .. " ends on a trigger no leg arms")
        end
        for _, monitor in ipairs(list((step.ends or {}).monitor)) do
            assert(watched[monitor], step.id .. " ends on a monitor no leg watches")
        end
        assert(step.checkpoint == nil or type(step.checkpoint) == "boolean",
            step.id .. " checkpoint must be a boolean")
        local hurt = (step.ends or {}).health
        if hurt ~= nil then
            lib.one(hurt.slot, step.id .. " health slot")
            assert(type(hurt.at) == "number" and hurt.at >= 0 and hurt.at <= 1,
                step.id .. " health fraction must be between zero and one")
        end
    end
    local step_ids = {arrival = true}
    for _, step in ipairs(content.steps) do step_ids[step.id] = true end
    builder:provide("legs", {armed = armed, watched = watched, step_ids = step_ids})
end

function core.build(content, builder)
    local legs, steps = content.legs, content.steps
    local first = legs[1]
    local intro = builder:find("intro")
    local has_intro = intro ~= nil and intro.count > 0
    local facts, trigger_fact, graph = {}, {}, nil

    -- The client spawns on the arrival answer. Its region leg and its empty reports both arrive
    -- while it is still loading. A move after a cutscene may not hold the spawn again, so there
    -- the region report also counts.
    facts[#facts + 1] = {id = "arrival", observe = function(_, state, event)
        local region = first.state.region_index
        if event.entered == true and event.held_region_index == region then return true end
        return has_intro and intro.done(state) and event.region_index == region
    end}
    for _, leg in ipairs(legs) do
        local region = leg.state.region_index
        facts[#facts + 1] = {id = "leg." .. leg.id, observe = function(_, _, event)
            return event.region_index == region
                or (event.entered == true and event.held_region_index == region)
        end}
    end
    local function watch(trigger)
        if trigger_fact[trigger] == nil then
            local id = "t" .. (#facts + 1)
            trigger_fact[trigger] = id
            facts[#facts + 1] = {id = id, observe = function(context, _, event)
                return lib.is_slot(context, event, trigger)
            end}
        end
        return flow.fact(trigger_fact[trigger])
    end
    -- A revisited volume was crossed earlier, so its report counts only once the step is on.
    local function fresh(step, number)
        return flow.fact(step.id .. ".t" .. number)
    end
    for _, step in ipairs(steps) do
        local ends = step.ends or {}
        for number, trigger in ipairs(list(ends.trigger)) do
            if step.revisit then
                facts[#facts + 1] = {id = step.id .. ".t" .. number,
                    observe = function(context, state, event)
                        return graph:started(context, state, step.id)
                            and lib.is_slot(context, event, trigger)
                    end}
            else
                watch(trigger)
            end
        end
        for _, monitor in ipairs(list(ends.monitor)) do watch(monitor) end
        if ends.ghost_link ~= nil then
            local link, started = ends.ghost_link, step.id .. ".scan"
            facts[#facts + 1] = {id = started, observe = function(context, state, event)
                return graph:started(context, state, step.id) and lib.is_slot(context, event, link)
                    and event.active == true and (event.progress or 0) > 0
            end}
            facts[#facts + 1] = {id = step.id .. ".scanned",
                observe = function(context, state, event)
                    return graph:fact(context, state, started)
                        and lib.is_slot(context, event, link) and event.active == false
                end}
        end
        for number, object in ipairs(ends.destroyed or {}) do
            facts[#facts + 1] = {id = step.id .. ".gone" .. number,
                observe = function(context, state, event)
                    return graph:started(context, state, step.id)
                        and lib.is_slot(context, event, object) and event.present == false
                end}
        end
        if ends.interact ~= nil then
            local object = ends.interact
            facts[#facts + 1] = {id = step.id .. ".used", observe = function(context, state, event)
                return graph:started(context, state, step.id)
                    and lib.is_slot(context, event, object)
            end}
        end
        -- The type-2 Sense carries the combatant's health as a fraction, so a phase gate needs no
        -- client read. An unknown pool reports below zero and never ends a step.
        if ends.health ~= nil then
            local target, at = ends.health.slot, ends.health.at
            facts[#facts + 1] = {id = step.id .. ".hurt", observe = function(context, state, event)
                return graph:started(context, state, step.id)
                    and lib.is_slot(context, event, target)
                    and type(event.health) == "number" and event.health >= 0
                    and event.health <= at
            end}
        end
        -- A scene may have played before; only a report after its step counts.
        if ends.scene ~= nil then
            local scene = ends.scene
            facts[#facts + 1] = {id = step.id .. ".played",
                observe = function(context, state, event)
                return graph:started(context, state, step.id)
                    and lib.is_slot(context, event, scene)
            end}
        end
    end

    local encounters = builder:find("encounters")
    local function own_end(step)
        local ends, options = step.ends or {}, {}
        for number, trigger in ipairs(list(ends.trigger)) do
            options[#options + 1] = step.revisit and fresh(step, number) or watch(trigger)
        end
        for _, monitor in ipairs(list(ends.monitor)) do options[#options + 1] = watch(monitor) end
        if ends.region ~= nil then options[#options + 1] = flow.fact("leg." .. ends.region) end
        if ends.clear ~= nil then
            options[#options + 1] = assert(encounters, step.id .. " ends on a clear with no "
                .. "encounters").cleared(list(ends.clear))
        end
        if ends.ghost_link ~= nil then options[#options + 1] = flow.fact(step.id .. ".scanned") end
        if ends.interact ~= nil then options[#options + 1] = flow.fact(step.id .. ".used") end
        if ends.scene ~= nil then options[#options + 1] = flow.fact(step.id .. ".played") end
        if ends.health ~= nil then options[#options + 1] = flow.fact(step.id .. ".hurt") end
        if ends.destroyed ~= nil then
            local all = {}
            for number = 1, #ends.destroyed do
                all[number] = flow.fact(step.id .. ".gone" .. number)
            end
            options[#options + 1] = {all = all}
        end
        for _, name in ipairs(builder.end_kind_names) do
            if ends[name] ~= nil then
                for _, option in ipairs(builder.end_kinds[name](step, ends[name])) do
                    options[#options + 1] = option
                end
            end
        end
        return options
    end

    -- A restart before any checkpoint replays from the arrival, which never happens twice, so a
    -- mission that restarts keeps the arrival as its first checkpoint.
    local checkpoints = builder:find("checkpoints")
    local restarts = checkpoints ~= nil and checkpoints.restarts
    local chain = {{id = "arrival", await = flow.fact("arrival"), checkpoint = restarts}}
    local previous = "arrival"
    for index, step in ipairs(steps) do
        local options = own_end(step)
        if not step.barrier then
            for later = index + 1, #steps do
                local ends = steps[later].ends or {}
                for _, trigger in ipairs(steps[later].revisit and {} or list(ends.trigger)) do
                    options[#options + 1] = watch(trigger)
                end
                for _, monitor in ipairs(list(ends.monitor)) do
                    options[#options + 1] = watch(monitor)
                end
                if ends.region ~= nil then
                    options[#options + 1] = flow.fact("leg." .. ends.region)
                end
            end
        end
        -- A step with no end finishes at once; the next step starts with it.
        local await = any_of(options)
        -- A flow records a checkpoint when its step finishes, so a checkpoint step gets an empty
        -- step before it: reaching the step records it, and a restart replays it and what follows.
        if step.checkpoint == true then
            chain[#chain + 1] = {id = step.id .. ".cp", after = {previous}, checkpoint = true}
            previous = step.id .. ".cp"
        end
        chain[#chain + 1] = {id = step.id, after = {previous}, run = begin(content, builder, step),
            await = await}
        previous = step.id
    end
    -- The finished mission shows no goal and no map marker.
    chain[#chain + 1] = {id = "done", after = {previous}, run = function(context)
        if content.finish ~= nil then content.finish(context) end
        context:slot(content.directive_sensor):clear_directives()
        context:complete_mission{}
    end}

    -- The chain is linear, so a step has finished once the step after it has started.
    local following = {}
    for index, step in ipairs(steps) do
        following[step.id] = steps[index + 1] ~= nil and steps[index + 1].id or "done"
    end
    graph = flow.new{key = content.key, facts = facts, steps = chain}
    builder:graph(graph)

    -- An interactable spawns with its group's seed, so it stays out until its step sends its row.
    local omit = {}
    for _, id in ipairs(content.omit or {}) do omit[#omit + 1] = id end
    for _, step in ipairs(steps) do
        local object = step.ends ~= nil and step.ends.interact or nil
        if object ~= nil then omit[#omit + 1] = object end
    end
    if builder.initial.region_index == nil then
        builder.initial.region_index = first.state.region_index
    end
    builder.initial.spawn_set_hash = content.spawn_set
    builder.initial.omit = omit
    builder:provide("core", {
        graph = function() return graph end,
        omit = omit,
        finished = function(context, state, id)
            return graph:started(context, state, following[id])
        end,
    })

    -- A trigger reports only once the host arms it, and arming registers its object, so each
    -- leg arms its triggers when the player reaches it.
    local function arm(context, region)
        local objects = {}
        for _, leg in ipairs(legs) do
            if leg.state.region_index == region then
                for _, trigger in ipairs(leg.arm or {}) do
                    arm_trigger(context, trigger)
                    objects[object_of(trigger) or trigger] = true
                end
                for _, monitor in ipairs(leg.watch or {}) do
                    watch_monitor(context, monitor)
                    objects[object_of(monitor) or monitor] = true
                end
            end
        end
        return objects
    end
    local function active(context, state)
        for _, step in ipairs(steps) do
            if graph:started(context, state, step.id)
                and not graph:started(context, state, following[step.id]) then
                return step
            end
        end
        return nil
    end
    local function handle(context, state, event)
        builder:handle(context, state, event)
    end
    -- A goal sent before its marker's object registered shows no marker, so the goal still
    -- showing is sent again once the new region registers that object.
    local function enter(context, state, event, region)
        local before = active(context, state)
        local objects = arm(context, region)
        handle(context, state, event)
        if before == nil or before.directive == nil or active(context, state) ~= before then
            return
        end
        local marker = before.navpoint or before.waypoint
        if marker ~= nil and objects[object_of(marker)] then show(content, context, before) end
    end

    builder:on("on_event_region_changed", function(context, state, event)
        enter(context, state, event, event.region_index)
    end)
    -- Only the arrival answer feeds the graph. A pending leg report names a region the
    -- client has not loaded.
    builder:on("on_event_client_state_changed", function(context, state, event)
        if event.entered == true then enter(context, state, event, event.held_region_index) end
    end)
    builder:on("on_event_player_trigger", function(context, state, event)
        disarm_reported(context, state, event)
        handle(context, state, event)
    end)
    -- A watched monitor reports here, not through the player-trigger event.
    for _, handler in ipairs({"on_event_trigger_entered", "on_event_scene_finished",
        "on_event_damage_state", "on_event_squad_state", "on_event_device_state",
        "on_event_object_interacted", "on_event_ghost_link_state", "on_event_object_state"}) do
        builder:on(handler, handle)
    end
end

return core
