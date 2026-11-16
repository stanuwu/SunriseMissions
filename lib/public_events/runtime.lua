-- Public-event lifecycle under lib.freeroam; mutable state stays in the host scope.
local runtime = {}

--- Retained phase values allow an existing event attempt to survive a script reload.
runtime.phase = {active = 1, ending = 2, aborted = 3, incoming = 4}
-- Purpose 1 is reserved for the active deadline; encounters own later ending steps.
local DEADLINE = 1
local MS_PER_SECOND = 1000
local CALLBACKS = {
    "start", "abort", "on_squad", "on_squad_counted", "on_effect", "on_objective",
    "on_object_state", "on_trigger", "on_damage", "on_engagement", "on_incident",
    "on_interaction", "on_cleanup_effect", "cleanup_pending", "status",
}

---@class PublicEventLifecycle
---@field timer string
---@field clock_timer string
---@field phase_key string
---@field start_key string
---@field purpose_key string
---@field tick_key string
---@field tick_seconds integer
---@field duration_seconds integer
local Lifecycle = {}
Lifecycle.__index = Lifecycle

--- Returns the retained phase, or nil before this site starts.
function Lifecycle:phase(scope)
    return scope:variable(self.phase_key)
end

--- Writes a lifecycle phase without changing encounter-specific state.
function Lifecycle:enter(scope, phase)
    scope:set_variable(self.phase_key, phase)
end

--- Arms the active deadline and anchors the separate coarse wave schedule.
function Lifecycle:start_clock(scope)
    scope:set_variable(self.start_key, scope:variable(self.tick_key) or 0)
    self:wait(scope, DEADLINE, self.duration_seconds * MS_PER_SECOND)
end

--- Returns elapsed seconds at the freeroam service's resolution.
function Lifecycle:elapsed(scope)
    return ((scope:variable(self.tick_key) or 0) - (scope:variable(self.start_key) or 0))
        * self.tick_seconds
end

--- Reads whole seconds until the active host deadline; ending timers are not countdowns.
---@param scope table Host scope; a temporary timer is armed and canceled to sample host time.
---@return integer seconds Zero outside active play or after deadline expiry/cancellation.
function Lifecycle:remaining(scope)
    if self:phase(scope) ~= runtime.phase.active then return 0 end
    local deadline = tonumber(scope.state:timer(scope:key(self.timer)))
    if deadline == nil then return 0 end
    -- A zero-delay timer exposes this callback's host time without changing the active deadline.
    scope:start_timer(self.clock_timer, 0)
    local now = tonumber(scope.state:timer(scope:key(self.clock_timer)))
    scope:cancel_timer(self.clock_timer)
    return math.max(0, math.floor((deadline - now) / MS_PER_SECOND))
end

--- Replaces the deadline while retaining the objective clock's total duration.
function Lifecycle:restart_clock(scope, seconds)
    local elapsed_ticks = (self.duration_seconds - seconds) // self.tick_seconds
    scope:set_variable(self.start_key, (scope:variable(self.tick_key) or 0) - elapsed_ticks)
    scope:start_timer(self.timer, seconds * MS_PER_SECOND)
end

--- Schedules one encounter step on the event's retained timer.
function Lifecycle:wait(scope, purpose, milliseconds)
    scope:set_variable(self.purpose_key, purpose)
    scope:start_timer(self.timer, milliseconds)
end

--- Cancels the main deadline or ending timer; encounter timers remain separately owned.
function Lifecycle:cancel(scope)
    scope:cancel_timer(self.timer)
end

--- Releases gameplay bookkeeping; final cleanup outcomes have separate retained ownership.
function Lifecycle:release(scope)
    scope:clear_variable(self.purpose_key)
end

---@class PublicEventOptions
---@field name string|nil Event name in the launcher.
---@field key string State and timer prefix within the freeroam zone scope.
---@field duration_seconds integer Normal event duration.
---@field tick_seconds integer Existing freeroam service cadence.

--- Creates a handler; callbacks return true only when freeroam may release the site.
---@param options PublicEventOptions
---@param create fun(lifecycle: PublicEventLifecycle): table Builds the encounter callbacks.
---@return table handler Retains definitions, never callback contexts or mutable gameplay state.
function runtime.new(options, create)
    assert(type(options.key) == "string" and #options.key > 0, "event needs a state key")
    assert(options.duration_seconds > 0 and options.tick_seconds > 0, "invalid event clock")
    local lifecycle = setmetatable({
        timer = options.key,
        clock_timer = options.key .. ".clock",
        phase_key = options.key .. ".p",
        start_key = options.key .. ".st",
        purpose_key = options.key .. ".t",
        tick_key = "now",
        tick_seconds = options.tick_seconds,
        duration_seconds = options.duration_seconds,
    }, Lifecycle)
    local encounter = create(lifecycle)
    assert(type(encounter.start) == "function", "event needs a start callback")
    assert(type(encounter.on_deadline) == "function", "event needs a deadline callback")
    assert(type(encounter.on_ending_timer) == "function", "event needs an ending callback")
    local handler = {name = options.name}
    for _, name in ipairs(CALLBACKS) do handler[name] = encounter[name] end

    --- Routes the main timer by phase; other timers retain the encounter's own checks.
    function handler.on_timer(context, scope, site, event, name)
        if name ~= lifecycle.timer then
            if encounter.on_timer ~= nil then
                return encounter.on_timer(context, scope, site, event, name)
            end
            return false
        end
        local phase = lifecycle:phase(scope)
        local purpose = scope:variable(lifecycle.purpose_key)
        if phase == runtime.phase.active and purpose == DEADLINE then
            return encounter.on_deadline(context, scope)
        end
        if phase == runtime.phase.ending then
            return encounter.on_ending_timer(context, scope, purpose)
        end
        return false
    end
    return handler
end

--- Attaches a handler to an authored site; prioritization is an explicit scheduling choice.
---@param first boolean Move this site to the front of its zone's rotation when true.
---@param patrol string[]|nil Patrol slot ids the zone retires while this site runs.
---@return table zones The supplied zone list with the selected site bound.
function runtime.attach(zones, region, sensor, handler, first, patrol)
    for _, zone in ipairs(zones) do
        if zone.region == region then
            for index, site in ipairs(zone.events or {}) do
                if site.sensor == sensor then
                    site.handler = handler
                    if patrol ~= nil then
                        site.patrol_hold = {}
                        for _, slot in ipairs(patrol) do site.patrol_hold[slot] = true end
                    end
                    if first then
                        table.remove(zone.events, index)
                        table.insert(zone.events, 1, site)
                    end
                    return zones
                end
            end
        end
    end
    error("no event site with that sensor in region " .. region)
end

return runtime
