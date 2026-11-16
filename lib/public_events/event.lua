-- Owns the rally, encounter clock, heroic transition and cleanup for each site.
-- A family supplies callbacks and site bindings. The host scope retains mutable state.
local lib = require("lib.mission_lib")
local runtime = require("lib.public_events.runtime")
local presentation = require("lib.public_events.presentation")
local rally_module = require("lib.public_events.rally")
local director_module = require("lib.public_events.director")
local devices = require("lib.public_events.devices")
local cleanup_module = require("lib.public_events.cleanup")

local event = {}

-- Ending timer purposes retain the step across reloads; purpose 1 is the runtime deadline.
local TIMER_BANNER, TIMER_CHEST, TIMER_GRACE, TIMER_PRELUDE = 2, 3, 4, 5
-- Reconstructed ending delays between the result line, banner and chest.
local END_BANNER_MS, END_CHEST_MS = 3000, 2000
-- Reconstructed retention of the chest and scenery after the ending.
local GRACE_MS = 60000
-- Incoming step 0 withdraws the rally flag; family steps follow from 1.
local STEP_LEAVE = 0
-- Chest ownership is recorded as this tier; inventory rewards need a separate contract.
local REWARD_TIER = "tier0:"
-- The completion row selects the exit state while retaining the active phase.
local BANNER_STATE = presentation.directive.exit
-- Family reports forwarded while the objective is live.
local REPORTS = {"on_squad", "on_squad_counted", "on_object_state", "on_objective", "on_trigger",
    "on_damage"}
-- Hook lists that a family may leave out.
local OPTIONAL_LISTS = {"incoming", "timers", "tracked", "scenery", "device_keys"}

---@class EventSettings
---@field KEY string Host-scope prefix of the family; also its lifecycle timer name.
---@field EVENT_SECONDS integer Normal event duration.
---@field TICK_SECONDS integer Freeroam service cadence.
---@field JOIN_LINE_TIMER string|nil Timer for the second cue when the site supplies join_lines.
---@field CUE_START integer Cue played once after local membership.
---@field CUE_SUCCESS integer
---@field CUE_FAILED integer
---@field CUE_HEROIC_SUCCESS integer
---@field CUE_HEROIC_FAILED integer
---@field MUSIC_ACTIVE integer Music section while the objective is live; also the clear default.
---@field MUSIC_HEROIC integer Music section after the heroic commit.

---@class EventDefinition
---@field directive_sensor string Type-68 sensor owning the event rows.
---@field navpoint string|nil Type-47 fallback marker of an objective row.
---@field incoming table|nil Row shown before the objective; the goal row by default.
---@field engagement string Type-70 event audience sensor.
---@field engagement_volume string Type-60 audience volume; engagement_volumes replaces it.
---@field engagement_volumes string[]|nil Type-60 volumes whose union is the event area.
---@field dialog string Type-53 dialogue sensor.
---@field join_lines table|nil Cues played on joining: first, second and delay_ms; replaces both
--- the site's alert and start cues.
---@field dialog_volume string|nil Type-60 volume filtering every cue; nil plays them to all.
---@field music string Music sensor.
---@field chest string Chest object slot.
---@field rally RallyDefinition|nil Rally point opened before the event.
---@field event_sensor string|nil Type-71 sensor of the Director policy.
---@field event_area string|nil Type-60 area of the Director policy.
---@field normal_event_state boolean|nil Send the normal sensor state at this site.

---@class EventRow
---@field directive table Row of the directive sensor to show.
---@field total_seconds integer Clock total shown while entering.
---@field progress table|nil Counter {current, maximum}.
---@field counts_members boolean|nil Republish the row when the member count changes.
---@field navpoint string|nil Marker slot of this row; the site's location by default.

---@class EventStep
---@field delay_ms integer Delay before this step runs.
---@field run fun(context, scope) Family action.

---@class EventHooks
---@field incoming EventStep[]|nil Steps after the flag leaves; none starts at once.
---@field start_delay_ms integer|nil Delay between the last step and the start.
---@field timers string[]|nil Family timers cancelled when the event stops.
---@field device_keys string[]|nil Cached position keys owned by the family's device controls.
---@field tracked string[]|nil Retained request keys cleared at each attempt start.
---@field required string[]|nil Keys whose terminal failure aborts; defaults to tracked.
---@field scenery string[]|nil Objects removed with the chest at cleanup.
---@field goal fun(scope): EventRow Current objective row.
---@field on_start fun(context, scope) Family objects, squads and timers at the start.
---@field on_heroic fun(context, scope)|nil Family reinforcements after the heroic commit.
---@field on_stop fun(context, scope, live) Retires family squads before an ending or abort.
---@field on_finish fun(context, scope, succeeded: boolean) Family scenery at the ending.
---@field prelude EventStep|nil Family step between the success line and the banner.
---@field on_cleanup fun(context, scope): table|nil Repeatable removals; returns queued requests.
---@field on_deadline fun(context, scope)|nil Outcome when the clock ends; failure by default.
---@field on_timer fun(context, scope, site, report, name)|nil Family timers while live.
---@field on_squad fun(context, scope, site, report)|nil
---@field on_squad_counted fun(context, scope, site, report)|nil Member counts with no alive fall.
---@field on_object_state fun(context, scope, site, report)|nil
---@field on_objective fun(context, scope, site, report)|nil
---@field on_trigger fun(context, scope, site, report)|nil
---@field on_damage fun(context, scope, site, report)|nil Damage report while the event is active.
---@field on_effect fun(context, scope, report)|nil Request result after device cache updates.
---@field on_incident fun(context, scope, site, report)|nil Accepted incidents while live.
---@field on_failure fun(context, scope, report)|nil Noncritical terminal request failures.
---@field on_interaction fun(context, scope, site, report)|nil Live uses beyond flag and chest.

local Event = {}
Event.__index = Event

--- Returns the lifecycle phase, or nil before the site starts.
function Event:phase(scope)
    return self.lifecycle:phase(scope)
end

--- True while the objective is live.
function Event:active(scope)
    return self:phase(scope) == runtime.phase.active
end

--- True once heroic has been committed in this attempt.
function Event:heroic(scope)
    return scope:variable(self.heroic_key) == true
end

--- Present audience members as last reported.
function Event:members(scope)
    return scope:variable(self.member_count_key) or 0
end

--- Nonnegative seconds left on the event clock.
function Event:remaining(scope)
    return self.lifecycle:remaining(scope)
end

--- Plays an event cue; the definition's dialogue volume, when set, filters the listeners.
function Event:say(context, cue)
    presentation.dialogue(context, self.definition.dialog, cue, self.definition.dialog_volume)
end

--- Selects one complete event music mask; nil clears it.
---@return userdata request Queued music control.
function Event:music(context, section)
    return presentation.music(context, self.definition.music, section, self.settings.MUSIC_ACTIVE)
end

--- Changes event membership without changing the phase.
---@return userdata|nil request Queued binding, or nil without a sensor.
function Event:audience(context, scope, enabled)
    local definition = self.definition
    return presentation.audience(context, definition.engagement,
        definition.engagement_volumes or definition.engagement_volume, enabled)
end

--- Returns the marker handle of a row's own slot or the site's location; nil without either.
function Event:marker(context, slot)
    slot = slot or self.definition.navpoint
    return slot ~= nil and context:slot(slot) or nil
end

--- Returns the row shown before the objective starts.
function Event:incoming_directive(scope)
    return self.definition.incoming or self.hooks.goal(scope).directive
end

--- Posts a row of the family's objective in the given state. Heroic rows play their entrance
--- and name the site's sensor, the treatment the Spire heroic banner ran with.
function Event:post(context, scope, row, state)
    local heroic = self:heroic(scope)
    presentation.goal(context, self.definition.directive_sensor, row.directive, state, {
        audience = context:slot(self.definition.engagement),
        progress = row.progress,
        navpoint = self:marker(context, row.navpoint),
        event = heroic and self.director:handle(context) or nil,
        entrance = heroic,
        clock = {remaining = self.lifecycle:remaining(scope), total = row.total_seconds},
    })
end

--- Publishes the family's current objective row.
function Event:goal(context, scope, state)
    self:post(context, scope, self.hooks.goal(scope), state)
end

--- Shows the incoming row without a clock, audience or location marker.
function Event:show_incoming(context, scope, state, directive)
    context:slot(self.definition.directive_sensor):set_directive{
        directive = directive or self:incoming_directive(scope), state = state,
        active = false, settled = false,
    }
end

--- Plays the start cue once after local membership.
function Event:announce(context, scope)
    if not self:active(scope) or scope:variable(self.arrived_key) == true then return end
    scope:set_variable(self.arrived_key, true)
    local join = self.definition.join_lines
    if join == nil then
        self:say(context, self.settings.CUE_START)
        return
    end
    self:say(context, join.first)
    scope:start_timer(self.settings.JOIN_LINE_TIMER, join.delay_ms)
end

--- Starts the objective after the incoming steps; the clock begins here.
function Event:begin(context, scope)
    if self.rally ~= nil then
        self.rally:close(context, scope,
            self.definition.rally.engagement == self.definition.engagement)
    end
    scope:clear_variable(self.stage_key)
    self.lifecycle:enter(scope, runtime.phase.active)
    self.lifecycle:start_clock(scope)
    for _, key in ipairs({self.arrived_key, self.heroic_key, self.reward_key}) do
        scope:clear_variable(key)
    end
    self.hooks.on_start(context, scope)
    self:music(context, self.settings.MUSIC_ACTIVE)
    self:audience(context, scope, true)
    self:goal(context, scope, presentation.directive.enter)
    if scope:variable(self.member_key) == true then self:announce(context, scope) end
    if self.director:activate(context) ~= nil then
        scope:set_variable(self.director_key, true)
        scope:set_variable(self.director_normal_key, true)
    end
end

--- Runs the next incoming step; after the last family step the objective starts.
function Event:step(context, scope)
    local stage = scope:variable(self.stage_key) or STEP_LEAVE
    local steps = self.hooks.incoming
    if stage > #steps then
        self:begin(context, scope)
        return
    end
    if stage == STEP_LEAVE then
        if self.rally ~= nil then self.rally:leave(context, scope) end
    else
        steps[stage].run(context, scope)
    end
    local delay = stage < #steps and steps[stage + 1].delay_ms or self.hooks.start_delay_ms
    scope:set_variable(self.stage_key, stage + 1)
    scope:start_timer(self.incoming_timer, delay)
end

---@class EventArrival
---@field rally_seconds integer|nil Seconds to the scheduled start; the rally counts them down.
---@field rally_total integer|nil The countdown the rally row totals: the scheduled lead.
---@field active boolean|nil The map already shows the event active: begin at once.

--- Opens the rally countdown, or runs the first incoming step when the site has no flag. A
--- scheduled arrival shortens the countdown to the time left, or begins at once when the map is
--- active.
---@param arrival EventArrival|nil
function Event:start(context, scope, arrival)
    self.final_cleanup:reset(scope)
    scope:clear_variable(self.director_key)
    scope:clear_variable(self.director_normal_key)
    devices.reset(scope, self.hooks.device_keys)
    for _, key in ipairs(self.hooks.tracked) do scope:clear_variable(key) end
    scope:clear_variable(self.member_key)
    scope:clear_variable(self.member_count_key)
    scope:clear_variable(self.heroic_key)
    self.lifecycle:enter(scope, runtime.phase.incoming)
    if arrival ~= nil and arrival.active == true then
        self:start_active(context, scope)
        return
    end
    if self.rally == nil then
        scope:set_variable(self.stage_key, STEP_LEAVE + 1)
        self:step(context, scope)
        return
    end
    scope:set_variable(self.stage_key, STEP_LEAVE)
    if arrival ~= nil then
        self.rally:open(context, scope, arrival.rally_seconds, arrival.rally_total)
        return
    end
    self.rally:open(context, scope)
end

--- Starts an event the map already shows as active: no rally, the incoming steps run at once
--- without their delays, and the objective begins with its full duration (reconstruction policy).
function Event:start_active(context, scope)
    for _, step in ipairs(self.hooks.incoming) do step.run(context, scope) end
    self:begin(context, scope)
end

--- True while the flag stands and a use can still be recorded.
function Event:rally_open(scope)
    return self.rally ~= nil and self:phase(scope) == runtime.phase.incoming
        and scope:variable(self.stage_key) == STEP_LEAVE
end

--- Commits heroic with reinforcements, music, the event sensor and the heroic row.
---@param seconds integer|nil New duration in seconds; omit to keep the running deadline.
function Event:commit_heroic(context, scope, seconds)
    scope:set_variable(self.heroic_key, true)
    if self.hooks.on_heroic ~= nil then self.hooks.on_heroic(context, scope) end
    self:music(context, self.settings.MUSIC_HEROIC)
    if seconds ~= nil then self.lifecycle:restart_clock(scope, seconds) end
    if self.director:heroic(context) ~= nil then scope:set_variable(self.director_key, true) end
    self:goal(context, scope, presentation.directive.enter)
end

--- Cancels timers and stops combat before an ending or abort; live says the objective ran.
function Event:stop(context, scope, live)
    scope:cancel_timer(self.incoming_timer)
    for _, name in ipairs(self.hooks.timers) do scope:cancel_timer(name) end
    self.lifecycle:cancel(scope)
    self.hooks.on_stop(context, scope, live)
    self:music(context, nil)
end

--- Begins the ending: result line, then banner and chest on success or the grace period.
function Event:finish(context, scope, succeeded)
    local settings, heroic = self.settings, self:heroic(scope)
    self.lifecycle:enter(scope, runtime.phase.ending)
    self:stop(context, scope, true)
    self.hooks.on_finish(context, scope, succeeded)
    if succeeded then
        self:say(context, heroic and settings.CUE_HEROIC_SUCCESS or settings.CUE_SUCCESS)
        local prelude = self.hooks.prelude
        if prelude ~= nil then
            self.lifecycle:wait(scope, TIMER_PRELUDE, prelude.delay_ms)
        else
            self.lifecycle:wait(scope, TIMER_BANNER, END_BANNER_MS)
        end
        return
    end
    self:say(context, heroic and settings.CUE_HEROIC_FAILED or settings.CUE_FAILED)
    self:goal(context, scope, presentation.directive.exit)
    self.lifecycle:wait(scope, TIMER_GRACE, GRACE_MS)
end

--- Makes the chest interactable; inventory rewards require a separate contract.
function Event:open_chest(context)
    local chest = self.definition.chest
    context:activate_objects{slots = {chest}, active = true}
    context:slot(chest):set_interactable_object{track_owner = true}
end

--- Queues final removals once; request ownership outlives the gameplay phase.
function Event:cleanup(context, scope)
    self.final_cleanup:start(context, scope)
end

--- Stops an attempt and releases gameplay; pending final cleanup delays site reuse.
function Event:abort(context, scope)
    local live = self:active(scope)
    local flag_standing = self:rally_open(scope)
    self.lifecycle:enter(scope, runtime.phase.aborted)
    self:stop(context, scope, live)
    if flag_standing then self.rally:leave(context, scope) end
    if self.rally ~= nil then self.rally:close(context, scope) end
    self:cleanup(context, scope)
    self.lifecycle:release(scope)
    return true
end

--- Advances prelude, banner and chest, then releases the site after the grace period.
function Event:on_ending_timer(context, scope, purpose)
    if purpose == TIMER_PRELUDE then
        self.hooks.prelude.run(context, scope)
        self.lifecycle:wait(scope, TIMER_BANNER, END_BANNER_MS)
    elseif purpose == TIMER_BANNER then
        self:goal(context, scope, BANNER_STATE)
        self.lifecycle:wait(scope, TIMER_CHEST, END_CHEST_MS)
    elseif purpose == TIMER_CHEST then
        self:open_chest(context)
        self.lifecycle:wait(scope, TIMER_GRACE, GRACE_MS)
    elseif purpose == TIMER_GRACE then
        self:cleanup(context, scope)
        self.lifecycle:release(scope)
        return true
    end
    return false
end

--- Builds the freeroam callbacks; family reports are forwarded while the objective is live.
function Event:handler()
    local handler = {}

    --- Returns the host stage and, during rally, the flag's stop time in host milliseconds.
    function handler.status(scope)
        if self:rally_open(scope) then
            return "Rally", tonumber(scope.state:timer(scope:key(self.rally.stop_timer)))
        end
        local phase = self.lifecycle:phase(scope)
        if phase == runtime.phase.active then return "Active" end
        if phase == runtime.phase.ending then return "Finishing" end
        if phase == runtime.phase.incoming then return "Incoming" end
    end

    --- Waits for cleanup within the held-zone bound, retaining unsuccessful cleanup as a warning.
    function handler.cleanup_pending(scope, held_ticks)
        return self.final_cleanup:blocked(scope, held_ticks)
    end

    --- Routes retained final-cleanup outcomes independently of gameplay phase or held region.
    function handler.on_cleanup_effect(context, scope, _, report)
        return self.final_cleanup:on_effect(context, scope, report)
    end

    function handler.start(context, scope, _, arrival)
        self:start(context, scope, arrival)
    end

    --- Routes flag incidents during rally and family incidents while the objective is live.
    function handler.on_incident(context, scope, site, report)
        if self:rally_open(scope) then
            self.rally:on_incident(context, scope, report)
        elseif self:active(scope) and self.hooks.on_incident ~= nil then
            return self.hooks.on_incident(context, scope, site, report)
        end
        return false
    end

    --- Records flag use or chest ownership without granting inventory rewards; other uses
    --- reach the family hook while the objective is live.
    function handler.on_interaction(context, scope, site, report)
        if self:rally_open(scope) then
            self.rally:on_interaction(context, scope, report)
        elseif self:phase(scope) == runtime.phase.ending
            and lib.is_slot(context, report, self.definition.chest)
            and scope:variable(self.reward_key) == nil then
            scope:set_variable(self.reward_key,
                REWARD_TIER .. tostring(report.owner_key or "unknown"))
        elseif self.hooks.on_interaction ~= nil and self:active(scope) then
            return self.hooks.on_interaction(context, scope, site, report)
        end
        return false
    end

    --- Invalidates device failures; required request failures abort only while live.
    function handler.on_effect(context, scope, _, report)
        devices.on_effect(scope, self.hooks.device_keys, report)
        if self.hooks.on_effect ~= nil then self.hooks.on_effect(context, scope, report) end
        local outcome = report.outcome
        if report.request_key == nil or (outcome ~= "refused" and outcome ~= "expired"
            and outcome ~= "canceled") then return false end
        local phase = self:phase(scope)
        if phase ~= runtime.phase.incoming and phase ~= runtime.phase.active then return false end
        for _, key in ipairs(self.hooks.required or self.hooks.tracked) do
            if scope:variable(key) == report.request_key.value then
                return self:abort(context, scope)
            end
        end
        if self.hooks.on_failure ~= nil then self.hooks.on_failure(context, scope, report) end
        return false
    end

    --- Republishes local join/leave changes without restarting the deadline or start cue.
    function handler.on_engagement(context, scope, _, report)
        if not lib.is_slot(context, report, self.definition.engagement) then return false end
        local members = report.member_count or 0
        local changed = scope:variable(self.member_count_key) ~= members
        local local_changed = (scope:variable(self.member_key) == true)
            ~= (report.local_member == true)
        scope:set_variable(self.member_key, report.local_member == true)
        scope:set_variable(self.member_count_key, members)
        if not self:active(scope) then return false end
        if report.local_member == true then self:announce(context, scope) end
        local row = self.hooks.goal(scope)
        if local_changed or (changed and row.counts_members == true) then
            self:post(context, scope, row, presentation.directive.enter)
        end
        return false
    end

    for _, name in ipairs(REPORTS) do
        handler[name] = function(context, scope, site, report)
            local hook = self.hooks[name]
            if hook == nil or not self:active(scope) then return false end
            return hook(context, scope, site, report)
        end
    end

    --- Services rally and incoming timers; family timers are forwarded while live.
    function handler.on_timer(context, scope, site, report, name)
        if self.rally ~= nil and self.rally:owns_timer(name) then
            if self.rally:on_timer(context, scope, name)
                and self:phase(scope) == runtime.phase.incoming then
                self:step(context, scope)
            end
            return false
        end
        if name == self.incoming_timer then
            if self:phase(scope) == runtime.phase.incoming then self:step(context, scope) end
            return false
        end
        local hook = self.hooks.on_timer
        if hook == nil or not self:active(scope) then return false end
        return hook(context, scope, site, report, name)
    end

    --- Converts the expired deadline into the family's outcome; failure unless a hook decides.
    function handler.on_deadline(context, scope)
        if self.hooks.on_deadline ~= nil then return self.hooks.on_deadline(context, scope) end
        self:finish(context, scope, false)
        return false
    end

    --- Aborts an incoming or running attempt when freeroam takes the site back early.
    function handler.abort(context, scope)
        return self:abort(context, scope)
    end

    function handler.on_ending_timer(context, scope, purpose)
        return self:on_ending_timer(context, scope, purpose)
    end

    return handler
end

--- Creates a family handler on the shared lifecycle; build(event) returns the family hooks.
---@param definition EventDefinition
---@param settings EventSettings
---@param build fun(event: table): EventHooks
---@return table handler Retains definitions and hooks, never mutable gameplay state.
function event.new(definition, settings, build)
    local key = settings.KEY
    return runtime.new({name = settings.NAME, key = key, duration_seconds = settings.EVENT_SECONDS,
        tick_seconds = settings.TICK_SECONDS}, function(lifecycle)
        local self = setmetatable({
            definition = definition,
            settings = settings,
            lifecycle = lifecycle,
            rally = definition.rally ~= nil and rally_module.new(definition.rally, key) or nil,
            director = director_module.new(definition),
            stage_key = key .. ".is",
            member_key = key .. ".m",
            member_count_key = key .. ".mc",
            arrived_key = key .. ".av",
            heroic_key = key .. ".h",
            reward_key = key .. ".rw",
            -- Records queued sensor ownership, not confirmed client state.
            director_key = key .. ".ds",
            director_normal_key = key .. ".dn",
            incoming_timer = key .. "s",
        }, Event)
        local hooks = build(self)
        for _, name in ipairs(OPTIONAL_LISTS) do hooks[name] = hooks[name] or {} end
        if self.rally ~= nil then
            hooks.device_keys[#hooks.device_keys + 1] = self.rally.audio_key
        end
        hooks.on_cleanup = hooks.on_cleanup or function() return {} end
        hooks.start_delay_ms = hooks.start_delay_ms or 0
        self.hooks = hooks
        local slots = {definition.chest}
        for _, slot in ipairs(hooks.scenery) do slots[#slots + 1] = slot end
        self.final_cleanup = cleanup_module.new(key .. ".cl", {
            {retry = true, send = function(context)
                return context:activate_objects{slots = slots, active = false}
            end},
            {retry = true, send = hooks.on_cleanup},
            {retry = true, send = function(context)
                return {context:slot(definition.directive_sensor):clear_directives()}
            end},
            {retry = true, send = function(context) return {self:music(context, nil)} end},
            {retry = true, send = function(context, scope)
                return {self:audience(context, scope, false)}
            end},
            -- Record a rejected close once. Retrying it could close a later attempt.
            {retry = false, blocking = false, send = function(context, scope)
                return {self.director:close(context, scope:variable(self.director_key) == true
                    and scope:variable(self.director_normal_key) == true)}
            end},
        })
        return self:handler()
    end)
end

return event
