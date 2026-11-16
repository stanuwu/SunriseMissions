-- Open world. One zone per authored state row, population that respawns, public event sites and
-- Lost Sectors. A zone owns its entities; only the held zone receives requests.
-- Deaths arrive on the type-1 squad Sense, so nothing here reads the client.
-- A site may carry a handler that owns its encounter. The rotation stays here: it starts the
-- handler, routes the held zone's reports to it, and takes the site back when a callback returns
-- true. Sites without a handler keep the all-squads-dead rule below.
local lib = require("lib.mission_lib")

local freeroam = {}

-- One service timer drives every cooldown. A destination has up to 64 zones and the host
-- retains 32 timers, so a timer per zone or per site would not fit.
local TICK_TIMER = "tick"
local TICK_KEY = "now"
local HELD_KEY = "held"
local ENTERED_KEY = "in"
-- Consecutive held service ticks waiting for this zone's active-site cleanup.
local CLEANUP_WAIT_KEY = "cleanup_wait"
-- Entry/schedule selection retained while the previous site finishes cleanup.
local NEXT_SITE_KEY = "next_site"

-- The service cadence bounds how late a respawn can be, so it stays well under the wait.
local DEFAULT_TICK_MS = 5000
-- A dead patrol squad returns after this wait.
local DEFAULT_RESPAWN_MS = 30000
local DEFAULT_EVENT_COOLDOWN_MS = 120000

-- The client copies this into the event banner. Anything but 0 is unverified.
local EVENT_STATE = 0
local EVENT_LEAVE_SECONDS = 30.0
-- Local test only: twice the client froze about 8 s after a delivered type-71 body whose area
-- names the sensor's own slot. The area contract is unknown, so the sensor is not sent.
local SEND_EVENT_SENSOR = false

local PHASE_RUNNING = 1
local PHASE_CLEARED = 2
-- A scheduled site waiting for its wall-clock wake; its handler decides the start.
local PHASE_WAITING = 3

local SECTOR_KEY = "sec"
local SECTOR_ACTIVE = 1
local SECTOR_CLEARED = 2
local SECTOR_CLEARED_KEY = "sk"
local ACTIVE_SITE_KEY = "as"
-- A manually started site keeps its turn until it ends or the host cancels it.
local MANUAL_KEY = "manual_event"
-- Per zone: the host answered the client's arrival in this zone (set once), and a public site
-- is waiting for that answer before it starts.
local ARRIVED_KEY = "arr"
local SITE_WAITING_KEY = "sw"
-- A handled site may name the patrol units that stand on its ground (site.patrol_hold, keyed by
-- slot id). They retire when the site starts and are owed a placement once it ends, as the
-- retail area clears for a public event. Nothing holds patrol a site does not name.
local PATROL_HELD_KEY = "ph"

-- One member per authored lane. Each lane carries its own actor class and behaviour, so a
-- lane may be thinned but never emptied: zeroing one spawns the wrong members without AI.
local LANE_CAP = 1

--- Pairs a squad with the type-1 slot its Sense reports on; the zone cap applies to its counts.
---@return Unit
function freeroam.unit(squad, slot, options)
    options = options or {}
    return {squad = lib.one(squad, "unit squad"), slot = lib.one(slot, "unit slot"),
        counts = options.counts, cap = LANE_CAP, objective = options.objective,
        task_group = options.group, member = options.member, spawn_rule = options.spawn_rule}
end

-- Ticks, never milliseconds: the script has no clock and the service timer is the only cadence.
local function ticks_for(milliseconds, tick_ms)
    local count = milliseconds // tick_ms
    if count < 1 then
        return 1
    end
    return count
end

local function now_tick(scope)
    return scope:variable(TICK_KEY) or 0
end

-- A due key names one respawnable inside its zone. Durable keys hold 63 bytes.
local function due_key(index)
    return "d" .. index
end

local function schedule(scope, index, delay_ticks)
    scope:set_variable(due_key(index), now_tick(scope) + delay_ticks)
end

local function due(scope, index)
    local at = scope:variable(due_key(index))
    return at ~= nil and at <= now_tick(scope)
end

local function clear_due(scope, index)
    scope:clear_variable(due_key(index))
end

-- Every respawnable in a zone gets one index, so a due key is short and stable across visits.
local function number_zone(zone)
    local index = 0
    for _, unit in ipairs(zone.patrol) do
        index = index + 1
        unit.index = index
    end
    for _, site in ipairs(zone.events) do
        index = index + 1
        site.index = index
        site.phase_key = "p" .. index
        site.cleared_key = "k" .. index
        site.wake_key = "w" .. index
    end
end

local function place_one(context, unit, mode)
    lib.place_unit(context, unit, mode)
end

local function place_units(context, units, mode)
    for _, unit in ipairs(units) do
        place_one(context, unit, mode)
    end
end

-- A zero request retires every member. A squad still holding a live body ignores a new
-- placement, so a reset empties it and the next entry fills it.
local function retire_units(context, units)
    for _, unit in ipairs(units) do
        lib.retire_squad(context, unit.squad)
    end
end

-- True when a site holds this patrol unit while it runs.
local function patrol_held(scope, site, unit)
    return site ~= nil and site.patrol_hold ~= nil and site.patrol_hold[unit.slot] == true
        and scope:variable(PATROL_HELD_KEY) == true
end

local active_site
local start_active_site

-- The ordinal of the zone's site scheduled under a roster key, or nil.
local function scheduled_ordinal(zone, site_key)
    if site_key == nil then return nil end
    for ordinal, site in ipairs(zone.events) do
        if site.handler ~= nil and site.handler.site_key == site_key then return ordinal end
    end
    return nil
end

-- The ordinal of a scheduled site whose slot has arrived: the rally lead or the active window.
local function arriving_site(context, scope, zone)
    if context.host_unix_seconds == nil then return nil end
    for ordinal, site in ipairs(zone.events) do
        if site.handler ~= nil and site.handler.schedule ~= nil then
            local plan = site.handler.schedule(context)
            if plan ~= nil and plan.arrival ~= nil then
                return ordinal
            end
        end
    end
    return nil
end

-- Retires the patrol units the site names and forgets their pending returns.
local function hold_patrol(context, scope, zone, site)
    if site.patrol_hold == nil then
        return
    end
    for _, unit in ipairs(zone.patrol) do
        if site.patrol_hold[unit.slot] then
            lib.retire_squad(context, unit.squad)
            clear_due(scope, unit.index)
        end
    end
    scope:set_variable(PATROL_HELD_KEY, true)
end

-- Owes each held unit one placement after the usual respawn wait.
local function release_patrol(scope, zone, site, respawn_ticks)
    if site.patrol_hold == nil or not scope:variable(PATROL_HELD_KEY) then
        return
    end
    scope:clear_variable(PATROL_HELD_KEY)
    for _, unit in ipairs(zone.patrol) do
        if site.patrol_hold[unit.slot] then
            schedule(scope, unit.index, respawn_ticks)
        end
    end
end

local function set_objects(context, slots, active)
    if #slots > 0 then
        context:activate_objects{slots = slots, active = active}
    end
end

-- Sites and sectors both answer "did this squad's slot report?".
local function unit_reporting(context, event, units)
    for _, unit in ipairs(units) do
        if lib.is_slot(context, event, unit.slot) then
            return unit
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Public event sites
-- ---------------------------------------------------------------------------

-- A handler may carry a schedule: asked with the context it answers with a wait in seconds or
-- with the arrival the start takes. A slot picked for another site of the zone goes to that site.
-- Without a host clock the site starts as an unscheduled one.
local function start_site(context, scope, zone, site, arrival)
    if arrival == nil and site.handler ~= nil and site.handler.schedule ~= nil then
        local now = context.host_unix_seconds
        local plan = now ~= nil and site.handler.schedule(context) or nil
        if plan ~= nil and plan.wait_seconds ~= nil then
            local picked = scheduled_ordinal(zone, plan.selected_site)
            if picked ~= nil and zone.events[picked] ~= site then
                scope:clear_variable(site.phase_key)
                scope:clear_variable(site.wake_key)
                clear_due(scope, site.index)
                start_active_site(context, scope, zone, picked)
                return
            end
            scope:set_variable(site.phase_key, PHASE_WAITING)
            scope:set_variable(site.wake_key, now + plan.wait_seconds)
            clear_due(scope, site.index)
            return
        end
        arrival = plan ~= nil and plan.arrival or nil
    end
    scope:clear_variable(site.wake_key)
    scope:set_variable(site.phase_key, PHASE_RUNNING)
    scope:set_variable(site.cleared_key, 0)
    clear_due(scope, site.index)
    if site.handler ~= nil then
        hold_patrol(context, scope, zone, site)
        site.handler.start(context, scope, site, arrival)
        return
    end
    set_objects(context, site.chest, false)
    context:slot(site.objective):reset_objectives()
    place_units(context, site.squads, context.sdk.squad_modes.replace)
    if not SEND_EVENT_SENSOR then
        return
    end
    -- The sensor's own slot bounds the watched area.
    context:slot(site.sensor):set_public_event_state{
        state = EVENT_STATE,
        area = context:slot(site.sensor),
        leave_seconds = EVENT_LEAVE_SECONDS,
    }
end

-- One event runs at a time. Starting every site in a zone at once places hundreds of squads
-- in one frame, which retail never does.
start_active_site = function(context, scope, zone, ordinal)
    if #zone.events == 0 then
        return
    end
    local previous = active_site(scope, zone)
    if previous ~= nil and previous.handler ~= nil
        and previous.handler.cleanup_pending ~= nil
        and previous.handler.cleanup_pending(scope, 0) then
        scope:set_variable(NEXT_SITE_KEY, ordinal)
        return
    end
    scope:clear_variable(NEXT_SITE_KEY)
    local index = ((ordinal - 1) % #zone.events) + 1
    scope:set_variable(ACTIVE_SITE_KEY, index)
    start_site(context, scope, zone, zone.events[index])
end

active_site = function(scope, zone)
    local index = scope:variable(ACTIVE_SITE_KEY)
    if index == nil or zone.events[index] == nil then
        return nil
    end
    return zone.events[index]
end

-- The next site starts after the cooldown; the finished site keeps nothing.
local function finish_site(scope, zone, site, cooldown_ticks, respawn_ticks)
    scope:clear_variable(MANUAL_KEY)
    scope:set_variable(site.phase_key, PHASE_CLEARED)
    schedule(scope, site.index, cooldown_ticks)
    release_patrol(scope, zone, site, respawn_ticks)
end

-- A site ends when every squad it placed is gone. Not every event is a boss kill.
local function site_squad_cleared(context, scope, zone, site, cooldown_ticks, respawn_ticks)
    if scope:variable(site.phase_key) ~= PHASE_RUNNING then
        return
    end
    local cleared = (scope:variable(site.cleared_key) or 0) + 1
    scope:set_variable(site.cleared_key, cleared)
    if cleared < #site.squads then
        return
    end
    set_objects(context, site.chest, true)
    finish_site(scope, zone, site, cooldown_ticks, respawn_ticks)
end

-- ---------------------------------------------------------------------------
-- Lost Sectors
-- ---------------------------------------------------------------------------

local function start_sector(context, scope, sector)
    scope:set_variable(SECTOR_KEY, SECTOR_ACTIVE)
    scope:set_variable(SECTOR_CLEARED_KEY, 0)
    set_objects(context, sector.chest, false)
    -- A blocker object is retired, not moved. A door is a type-23 channel.
    set_objects(context, sector.blockers, false)
    for _, door in ipairs(sector.doors) do
        context:slot(door.slot):set_channel{
            channel = door.channel,
            value = door.value,
            snap = true,
        }
    end
    -- TODO: shield effects need a type-26 server endpoint.
    place_units(context, sector.squads, context.sdk.squad_modes.replace)
    -- A crystal stays inert until its guardian dies. The monitor answers its destruction.
    for index, crystal in ipairs(sector.crystals) do
        scope:clear_variable("crystal" .. index)
        context:activate_objects{slots = {crystal.object}, active = false}
        context:slot(crystal.monitor):watch_damage{target = context:slot(crystal.object)}
    end
end

local function open_crystal(context, event, sector)
    for _, crystal in ipairs(sector.crystals) do
        if crystal.guard ~= nil and lib.is_slot(context, event, crystal.guard) then
            context:activate_objects{slots = {crystal.object}, active = true}
            return true
        end
    end
    return false
end

local function expose_boss_crystal(context, sector)
    for _, crystal in ipairs(sector.crystals) do
        if crystal.boss then
            context:activate_objects{slots = {crystal.object}, active = true}
        end
    end
end

local function crystal_destroyed(context, scope, event, sector)
    for index, crystal in ipairs(sector.crystals) do
        if lib.is_slot(context, event, crystal.monitor) then
            if scope:variable("crystal" .. index) then return end
            scope:set_variable("crystal" .. index, true)
            if crystal.boss then
                return
            end
            local done = 0
            for other, target in ipairs(sector.crystals) do
                if not target.boss and scope:variable("crystal" .. other) then done = done + 1 end
            end
            if done >= sector.guarded_crystals then
                expose_boss_crystal(context, sector)
            end
            return
        end
    end
end

local function clear_sector(context, scope, sector)
    if scope:variable(SECTOR_KEY) ~= SECTOR_ACTIVE then
        return
    end
    scope:set_variable(SECTOR_KEY, SECTOR_CLEARED)
    -- The chest opens and grants nothing: no script call reaches an account.
    set_objects(context, sector.chest, true)
end

-- Retail unlocks the chest on the boss. Without an authored boss name, a full clear stands in.
local function sector_squad_cleared(context, scope, sector)
    local cleared = (scope:variable(SECTOR_CLEARED_KEY) or 0) + 1
    scope:set_variable(SECTOR_CLEARED_KEY, cleared)
    if cleared >= #sector.squads then
        clear_sector(context, scope, sector)
    end
end

-- ---------------------------------------------------------------------------
-- Zones
-- ---------------------------------------------------------------------------

-- A Lost Sector is private content in a bubble this link already hosts, so its population
-- needs no state selection. Selecting one makes the placements wait for the client's slice-set
-- switch, which does not run until the public bubble unloads.
local function enter_zone(context, scope, zone)
    if zone.sector ~= nil then
        start_sector(context, scope, zone.sector)
        return
    end
    -- zone.omit names objects the state's seed leaves out, such as an event no script runs.
    context:select_state(zone.state, zone.omit)
    place_units(context, zone.ambient, context.sdk.squad_modes.reinforce)
    place_units(context, zone.patrol, context.sdk.squad_modes.reinforce)
    -- The host may allocate a second public link for a region the client only reported in
    -- passing. That link also sees the region held, but its first report carries the pending
    -- move and it never gets a plain "current is the held region" report; the real link does.
    -- So a public site starts on that report, not on the region change (see arrive).
    if context.activity_role == "public" and not scope:variable(ARRIVED_KEY) then
        scope:set_variable(SITE_WAITING_KEY, true)
        return
    end
    start_active_site(context, scope, zone, 1)
end

-- A public link's arrival in a zone: the report that names the held region as current with
-- no pending move (the host answers the client's arrival on the mission link only). Starts the
-- site that waited for it.
local function arrive(context, state, zone)
    local scope = lib.scope(context, state, zone.tag)
    scope:set_variable(ARRIVED_KEY, true)
    if zone.event_location and scope:variable("event_region") ~= zone.region then
        scope:set_variable("event_region", zone.region)
    end
    if scope:variable(SITE_WAITING_KEY) then
        scope:clear_variable(SITE_WAITING_KEY)
        start_active_site(context, scope, zone, 1)
    end
end

-- A patrol squad that died before the visit ended is owed a placement on return.
local function resume_zone(context, scope, zone)
    local site = active_site(scope, zone)
    for _, unit in ipairs(zone.patrol) do
        if scope:variable(due_key(unit.index)) ~= nil and not patrol_held(scope, site, unit) then
            place_one(context, unit, context.sdk.squad_modes.reinforce)
            clear_due(scope, unit.index)
        end
    end
end

-- Publishes committed progress for the overlay. Repeated ticks keep the same durable values.
local function report_event(scope, key, value)
    if scope:variable(key) ~= value then scope:set_variable(key, value) end
end

local function event_status(scope, site)
    if not site or scope:variable(site.phase_key) ~= PHASE_RUNNING then return "Waiting" end
    if site.handler and site.handler.status then return site.handler.status(scope) end
    return "Active"
end

local function report_site(scope, site)
    local status, rally_end = event_status(scope, site)
    status = status or "Waiting"
    local current = status ~= "Waiting" and scope:variable(ACTIVE_SITE_KEY) or 0
    report_event(scope, "event_current", current)
    report_event(scope, "event_status", status)
    report_event(scope, "event_rally_end", rally_end or 0)
    return status
end

-- Returns true while the launcher owns this service tick. The existing abort and cleanup run
-- before the new arrival, so replacing a rally cannot leave its flag or squads in the next one.
local function service_launcher(context, scope, zone, site, cleanup_pending, cooldown, respawn)
    if not zone.event_location or context.activity_role ~= "public"
        or scope:variable("event_region") ~= zone.region then return false end
    local phase = report_site(scope, site)
    local manual = scope:variable(MANUAL_KEY) == true
    local request = context.public_event_request
    if not request or request.region ~= zone.region
        or request.serial == scope:variable("event_request_seen") then return manual end
    if request.site == 0 and not manual then
        scope:set_variable("event_request_seen", request.serial)
        return false
    end
    local wanted = zone.events[request.site]
    if request.site ~= 0 and (not wanted or not wanted.handler or not wanted.handler.name) then
        scope:set_variable("event_request_seen", request.serial)
        return manual
    end
    if cleanup_pending or phase == "Finishing" then return true end
    if site and scope:variable(site.phase_key) == PHASE_RUNNING then
        if site.handler then
            site.handler.abort(context, scope, site)
        else
            retire_units(context, site.squads)
            set_objects(context, site.chest, false)
        end
        finish_site(scope, zone, site, cooldown, respawn)
        report_site(scope, nil)
        return true
    end
    scope:clear_variable(NEXT_SITE_KEY)
    scope:set_variable("event_request_seen", request.serial)
    if request.site == 0 then return false end
    local seconds = request.rally_seconds
    local arrival = seconds == 0 and {active = true} or {rally_seconds = seconds, rally_total = seconds}
    scope:set_variable(MANUAL_KEY, true)
    scope:set_variable(ACTIVE_SITE_KEY, request.site)
    start_site(context, scope, zone, wanted, arrival)
    report_site(scope, wanted)
    return true
end

local function service_zone(context, scope, zone, cooldown, respawn)
    local running = active_site(scope, zone)
    for _, unit in ipairs(zone.patrol) do
        if due(scope, unit.index) and not patrol_held(scope, running, unit) then
            clear_due(scope, unit.index)
            place_one(context, unit, context.sdk.squad_modes.reinforce)
        end
    end
    -- Re-read the schedule on each tick so arrivals keep the remaining time in the slot.
    local site = active_site(scope, zone)
    -- Retained cleanup owns the site until it settles or exhausts its held-tick allowance.
    local cleanup_pending = false
    if site ~= nil and site.handler ~= nil and site.handler.cleanup_pending ~= nil then
        local held_ticks = (scope:variable(CLEANUP_WAIT_KEY) or 0) + 1
        cleanup_pending = site.handler.cleanup_pending(scope, held_ticks)
        if cleanup_pending then
            scope:set_variable(CLEANUP_WAIT_KEY, held_ticks)
        else
            scope:clear_variable(CLEANUP_WAIT_KEY)
        end
    end
    if service_launcher(context, scope, zone, site, cleanup_pending, cooldown, respawn)
        or cleanup_pending then return end
    local next_site = scope:variable(NEXT_SITE_KEY)
    if next_site ~= nil then
        start_active_site(context, scope, zone, next_site)
        return
    end
    if site ~= nil and scope:variable(site.phase_key) == PHASE_WAITING then
        if context.host_unix_seconds ~= nil then
            start_site(context, scope, zone, site)
        end
        return
    end
    -- A scheduled slot that is here, within the lead or active, takes the zone from a cooling site
    -- or an unscheduled one at once. A running scheduled site finishes first.
    if site == nil or site.handler == nil or site.handler.schedule == nil
        or scope:variable(site.phase_key) ~= PHASE_RUNNING then
        local ordinal = arriving_site(context, scope, zone)
        if ordinal ~= nil then
            if site ~= nil then
                scope:set_variable(site.phase_key, PHASE_CLEARED)
                clear_due(scope, site.index)
            end
            start_active_site(context, scope, zone, ordinal)
            return
        end
    end
    if site ~= nil and due(scope, site.index) then
        clear_due(scope, site.index)
        start_active_site(context, scope, zone, (scope:variable(ACTIVE_SITE_KEY) or 1) + 1)
    end
end

--- Builds the open-world handler table for one destination.
function freeroam.new(definition)
    local zones = lib.one(definition.zones, "zones")
    local tick_ms = definition.tick_ms or DEFAULT_TICK_MS
    local respawn_ticks = ticks_for(definition.respawn_ms or DEFAULT_RESPAWN_MS, tick_ms)
    local cooldown_ticks =
        ticks_for(definition.event_cooldown_ms or DEFAULT_EVENT_COOLDOWN_MS, tick_ms)

    local by_region, launcher_sites = {}, {}
    for _, zone in ipairs(zones) do
        local encounter = definition.sectors ~= nil and definition.sectors[zone.region] or nil
        if encounter ~= nil then
            zone.sector = zone.sector or {}
            zone.sector.squads = encounter.squads
            zone.sector.boss = encounter.boss
            zone.sector.chest = encounter.chest
        end
        zone.patrol = zone.patrol or {}
        zone.ambient = zone.ambient or {}
        zone.events = zone.events or {}
        zone.tag = "z" .. zone.region
        if zone.sector ~= nil then
            zone.sector.squads = zone.sector.squads or {}
            zone.sector.chest = zone.sector.chest or {}
            zone.sector.doors = zone.sector.doors or {}
            zone.sector.blockers = zone.sector.blockers or {}
            zone.sector.crystals = zone.sector.crystals or {}
            local guarded = 0
            for _, crystal in ipairs(zone.sector.crystals) do
                if not crystal.boss then
                    guarded = guarded + 1
                end
            end
            zone.sector.guarded_crystals = guarded
        end
        number_zone(zone)
        local label = definition.event_locations and definition.event_locations[zone.region]
        for ordinal, site in ipairs(zone.events) do
            if site.handler and site.handler.name then
                zone.event_location = label or ("Region " .. zone.region)
                launcher_sites[#launcher_sites + 1] = {region = zone.region, site = ordinal,
                    location = zone.event_location, name = site.handler.name}
            end
        end
        assert(by_region[zone.region] == nil, "two zones share a region")
        by_region[zone.region] = zone
    end

    -- One link, one job. The mission link hosts the private content: Lost Sectors and patrol.
    -- A public bubble link hosts its own bubble's combat and events. Neither may touch the
    -- other's zones, or both place the same population.
    local function owns(context, zone)
        if context.activity_role == "public" then
            return zone.sector == nil
        end
        return zone.sector ~= nil
    end

    local function held_zone(state)
        local region = state:variable(HELD_KEY)
        if region == nil then
            return nil
        end
        return by_region[region]
    end

    -- Leaving a sector's bubble empties it. Retiring and placing in one dispatch loses the
    -- placement, so the run that leaves clears the bodies and the next entry fills them.
    local function reset_departed(context, state, region)
        for _, zone in ipairs(zones) do
            local scope = lib.scope(context, state, zone.tag)
            if zone.sector ~= nil and zone.region ~= region and scope:variable(ENTERED_KEY) then
                retire_units(context, zone.sector.squads)
                scope:clear_variable(ENTERED_KEY)
                scope:clear_variable(SECTOR_KEY)
                scope:clear_variable(SECTOR_CLEARED_KEY)
            end
        end
    end

    -- A handled site keeps its timers and reports only while its zone is held, so leaving the
    -- zone mid-event would strand it. The handler aborts and the site takes its cooldown.
    local function abort_departed(context, state, region)
        for _, zone in ipairs(zones) do
            if zone.region ~= region and owns(context, zone) then
                local scope = lib.scope(context, state, zone.tag)
                local site = active_site(scope, zone)
                if site ~= nil and site.handler ~= nil and site.handler.abort ~= nil
                    and scope:variable(site.phase_key) == PHASE_RUNNING then
                    site.handler.abort(context, scope, site)
                    finish_site(scope, zone, site, cooldown_ticks, respawn_ticks)
                end
            end
        end
    end

    local function build_zone(context, state, zone)
        local scope = lib.scope(context, state, zone.tag)
        if scope:variable(ENTERED_KEY) then
            resume_zone(context, scope, zone)
            return
        end
        scope:set_variable(ENTERED_KEY, true)
        enter_zone(context, scope, zone)
    end

    -- Hands one report to the running site's handler. A true return ends the site.
    local function route(context, state, event, name, detail)
        local zone = held_zone(state)
        if zone == nil or not owns(context, zone) then
            return false
        end
        local scope = lib.scope(context, state, zone.tag)
        local site = active_site(scope, zone)
        if site == nil or site.handler == nil or site.handler[name] == nil
            or scope:variable(site.phase_key) ~= PHASE_RUNNING then
            return false
        end
        if site.handler[name](context, scope, site, event, detail) == true then
            finish_site(scope, zone, site, cooldown_ticks, respawn_ticks)
        end
        return true
    end

    local program = {
        -- Reattach restarts pending-intent lifetimes, so restart their held-time allowance too.
        on_load = function(context, state)
            for _, zone in ipairs(zones) do
                lib.scope(context, state, zone.tag):clear_variable(CLEANUP_WAIT_KEY)
            end
        end,
        -- A sector starts when the client names it, not after its slice-set switch. It selects no
        -- state, so it cannot stall behind the switch or disturb a spawn. It needs a held region:
        -- building during the first load black-screens the client.
        on_event_client_state_changed = function(context, state, event)
            if context.activity_role == "public" and event.region_index == nil
                and event.current_region_index ~= nil
                and event.current_region_index == event.held_region_index then
                local held = by_region[event.held_region_index]
                if held ~= nil and owns(context, held) then
                    arrive(context, state, held)
                end
            end
            if event.held_region_index == nil or event.region_index == nil then
                return
            end
            local zone = by_region[event.region_index]
            if zone == nil or zone.sector == nil or not owns(context, zone) then
                return
            end
            build_zone(context, state, zone)
            context:start_timer(TICK_TIMER, tick_ms)
        end,

        -- Every other zone builds on the region change, because it selects a state and that
        -- must not happen for a region the client is not in.
        on_event_region_changed = function(context, state, event)
            local departed = held_zone(state)
            if departed ~= nil and departed.region ~= event.region_index then
                local scope = lib.scope(context, state, departed.tag)
                scope:clear_variable(CLEANUP_WAIT_KEY)
                if departed.event_location then
                    scope:clear_variable("event_region")
                    scope:clear_variable("event_current")
                    scope:clear_variable("event_status")
                    scope:clear_variable("event_rally_end")
                    local request = context.public_event_request
                    if request and request.region == departed.region then
                        scope:set_variable("event_request_seen", request.serial)
                    end
                end
            end
            local zone = by_region[event.region_index]
            context:set_variable(HELD_KEY, event.region_index)
            reset_departed(context, state, event.region_index)
            abort_departed(context, state, event.region_index)
            if zone == nil or not owns(context, zone) then
                return
            end
            build_zone(context, state, zone)
            context:start_timer(TICK_TIMER, tick_ms)
        end,

        on_event_squad_state = function(context, state, event)
            local zone = held_zone(state)
            if zone == nil or not owns(context, zone) then
                return
            end
            -- A squad can end with no alive count reported; only its member counts show it.
            if event.alive_count == 0 and event.previous_alive_count == 0 then
                route(context, state, event, "on_squad_counted")
                return
            end
            if event.alive_count ~= 0 or type(event.previous_alive_count) ~= "number"
                or event.previous_alive_count <= 0 then
                return
            end
            local scope = lib.scope(context, state, zone.tag)
            local unit = unit_reporting(context, event, zone.patrol)
            if unit ~= nil then
                schedule(scope, unit.index, respawn_ticks)
                return
            end
            local site = active_site(scope, zone)
            if site ~= nil and site.handler ~= nil then
                route(context, state, event, "on_squad")
                return
            end
            if site ~= nil and unit_reporting(context, event, site.squads) ~= nil then
                site_squad_cleared(context, scope, zone, site, cooldown_ticks, respawn_ticks)
                return
            end
            local sector = zone.sector
            if sector == nil then
                return
            end
            if sector.boss ~= nil then
                if lib.is_slot(context, event, sector.boss) then
                    clear_sector(context, scope, sector)
                    return
                end
            elseif unit_reporting(context, event, sector.squads) ~= nil then
                sector_squad_cleared(context, scope, sector)
                return
            end
            open_crystal(context, event, sector)
        end,

        -- The type-20 monitor echoes the crystal's health, so destruction needs no client read.
        on_event_damage_state = function(context, state, event)
            local zone = held_zone(state)
            if zone == nil or not owns(context, zone) then
                return
            end
            if zone.sector == nil then
                route(context, state, event, "on_damage")
                return
            end
            if type(event.health) ~= "number" or event.health ~= 0 then
                return
            end
            crystal_destroyed(context, lib.scope(context, state, zone.tag), event, zone.sector)
        end,

        on_event_timer_elapsed = function(context, state, event)
            local zone = held_zone(state)
            if zone == nil or not owns(context, zone) then
                return
            end
            if event.timer_name ~= TICK_TIMER then
                -- A handler's timers carry the zone tag; the name without it reaches the handler.
                local name = lib.timer_name(zone.tag, event.timer_name)
                if name ~= nil then
                    route(context, state, event, "on_timer", name)
                end
                return
            end
            local scope = lib.scope(context, state, zone.tag)
            scope:set_variable(TICK_KEY, now_tick(scope) + 1)
            service_zone(context, scope, zone, cooldown_ticks, respawn_ticks)
            context:start_timer(TICK_TIMER, tick_ms)
        end,

        on_event_objective_progress = function(context, state, event)
            route(context, state, event, "on_objective")
        end,

        on_event_object_interacted = function(context, state, event)
            route(context, state, event, "on_interaction")
        end,

        -- Some uses reach the server only as a client incident naming the object's definition.
        on_event_incident_received = function(context, state, event)
            route(context, state, event, "on_incident")
        end,

        on_event_object_state = function(context, state, event)
            route(context, state, event, "on_object_state")
        end,

        on_event_integration = function(context, state, event)
            route(context, state, event, "on_integration")
        end,

        on_event_trigger_state = function(context, state, event)
            route(context, state, event, "on_trigger")
        end,

        on_event_engagement_state = function(context, state, event)
            route(context, state, event, "on_engagement")
        end,

        on_event_effect_result = function(context, state, event)
            -- Final cleanup belongs to its original site, even after gameplay or travel ends.
            for _, zone in ipairs(zones) do
                if owns(context, zone) then
                    local scope = lib.scope(context, state, zone.tag)
                    for _, site in ipairs(zone.events) do
                        if site.handler ~= nil and site.handler.on_cleanup_effect ~= nil then
                            local retried = site.handler.on_cleanup_effect(
                                context, scope, site, event)
                            if retried == true and site == active_site(scope, zone) then
                                scope:clear_variable(CLEANUP_WAIT_KEY)
                            end
                        end
                    end
                end
            end
            route(context, state, event, "on_effect")
        end,
    }
    for _, name in ipairs({"on_event_client_state_changed", "on_event_region_changed",
        "on_event_squad_state", "on_event_damage_state", "on_event_timer_elapsed",
        "on_event_objective_progress", "on_event_object_interacted", "on_event_object_state",
        "on_event_effect_result", "on_event_integration", "on_event_trigger_state",
        "on_event_engagement_state", "on_event_incident_received"}) do
        local handler = program[name]
        program[name] = function(context, state, event)
            if event.attempt_generation ~= context.attempt_generation then return end
            handler(context, state, event)
        end
    end
    program.public_events = launcher_sites
    return program
end

return freeroam
