-- Witches' Ritual mechanics on the shared event skeleton: sigil occupancy drops each wizard's
-- shield, both wizards dying opens the portal, and the portal brings the Sorcerer, or the Champion
-- when both crystals fall first. Reconstructed policy is marked in settings.lua.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.witches_ritual.settings")
local visual_module = require("lib.public_events.witches_ritual.visuals")

local module = {}

--- Builds the Witches' Ritual handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references.
---@return table handler Freeroam site handler.
function module.new(definition)
    local visuals = visual_module.new(definition)
    local wizards, crystals = definition.wizards, definition.crystals
    local units, critical = {}, {}
    for _, group in ipairs({wizards, definition.acolytes, definition.waves,
        definition.portal_waves, {definition.sorcerer, definition.champion}, definition.thralls}) do
        for _, unit in ipairs(group) do units[#units + 1] = unit end
    end
    for _, plate in ipairs(definition.knights) do
        for _, unit in ipairs(plate) do units[#units + 1] = unit end
    end
    for _, group in ipairs({wizards, {definition.sorcerer, definition.champion}}) do
        for _, unit in ipairs(group) do critical[#critical + 1] = unit end
    end

    return event.new(definition, c, function(ev)
        local hooks = {}

        local function unit_key(unit) return c.UNIT_KEY .. unit.name end
        local function live_key(unit) return c.LIVE_KEY .. unit.name end

        --- Places a unit and marks it live until its end report.
        local function place(context, scope, unit)
            squads.place(context, scope, unit, unit_key(unit))
            scope:set_variable(live_key(unit), true)
        end

        --- Clears an ended unit's flag and records its generation against late count reports.
        local function mark_ended(scope, unit, generation)
            scope:clear_variable(live_key(unit))
            if generation ~= nil then scope:set_variable(c.ENDED_KEY .. unit.name, generation) end
        end

        --- Retires every live squad this attempt placed.
        local function retire_squads(context, scope)
            for _, unit in ipairs(units) do
                squads.retire_if_placed(context, scope, unit, unit_key(unit))
                scope:clear_variable(live_key(unit))
            end
        end

        --- Sends the next wave group; a unit of the group that is still alive is skipped.
        local function send_group(context, scope)
            local count = scope:variable(c.WAVE_COUNT_KEY) or 0
            scope:set_variable(c.WAVE_COUNT_KEY, count + 1)
            for _, index in ipairs(c.WAVE_GROUPS[count % #c.WAVE_GROUPS + 1]) do
                local unit = definition.waves[index]
                if scope:variable(live_key(unit)) ~= true then place(context, scope, unit) end
            end
        end

        --- Sends the next portal group; a unit of the group that is still alive is skipped.
        local function send_portal_group(context, scope)
            local count = scope:variable(c.PORTAL_COUNT_KEY) or 0
            scope:set_variable(c.PORTAL_COUNT_KEY, count + 1)
            for _, index in ipairs(c.PORTAL_GROUPS[count % #c.PORTAL_GROUPS + 1]) do
                local unit = definition.portal_waves[index]
                if scope:variable(live_key(unit)) ~= true then place(context, scope, unit) end
            end
        end

        --- Returns the number of wizards killed in this attempt.
        local function killed(scope) return scope:variable(c.KILLED_KEY) or 0 end

        --- Sends the plate's next Knight while its wizard lives; each variant arrives once.
        local function send_knight(context, scope, index)
            if scope:variable(live_key(wizards[index])) ~= true then return end
            local ordinal = (scope:variable(c.KNIGHT_KEY .. index) or 0) + 1
            local unit = definition.knights[index][ordinal]
            if unit == nil then return end
            scope:set_variable(c.KNIGHT_KEY .. index, ordinal)
            place(context, scope, unit)
        end

        --- Returns the plate whose Knight this unit is, or nil.
        local function knight_plate(unit)
            for index, plate in ipairs(definition.knights) do
                for _, knight in ipairs(plate) do
                    if knight == unit then return index end
                end
            end
            return nil
        end

        --- True while a plate can be charged: its wizard lives, or the portal stands.
        local function plate_active(scope, index)
            local stage = scope:variable(c.STAGE_KEY)
            return stage == c.STAGE_PORTAL or (stage == c.STAGE_WIZARDS
                and scope:variable(live_key(wizards[index])) == true)
        end

        --- True once a held plate finished its charge.
        local function charged(scope, index)
            return scope:variable(c.CHARGED_KEY .. index) == true
        end

        --- Forgets a plate's charge and stops its timer.
        local function clear_charge(scope, index)
            scope:cancel_timer(c.CHARGE_TIMERS[index])
            scope:clear_variable(c.CHARGE_KEY .. index)
            scope:clear_variable(c.CHARGED_KEY .. index)
        end

        --- Keeps occupancy through wizard deaths and selects only the current phase's sigils.
        --- An active plate shows the vacant outline; a held one is sent the success value once
        --- and glides there, while the charge level drives the pillar runes.
        local function show_plate(context, scope, index)
            local stage = scope:variable(c.STAGE_KEY)
            local value = c.PLATE_OFF
            if plate_active(scope, index) then
                value = c.PLATE_VACANT
                if scope:variable(c.CIRCLE_KEY .. index) == true then
                    value = c.PLATE_OCCUPIED
                end
            end
            visuals.plate(context, scope, index, value)
            local lit, fraction = 0, c.PILLAR_OFF
            if stage == c.STAGE_PORTAL or stage == c.STAGE_BOSS then
                lit, fraction = c.RUNES_PER_ARTIFACT, c.PILLAR_FULL
            elseif value > c.PLATE_VACANT then
                local level = scope:variable(c.CHARGE_KEY .. index) or 0
                lit, fraction = level, math.min(level * c.PILLAR_STEP, c.PILLAR_FULL)
            end
            visuals.pillar(context, scope, index, lit, fraction)
            if scope:variable(c.CRYSTAL_KEY .. index) ~= true and (stage == c.STAGE_PORTAL
                or scope:variable(c.CRYSTAL_SHIELD_KEY .. index) ~= nil) then
                visuals.crystal_shield(context, scope, index, stage ~= c.STAGE_PORTAL
                    or not charged(scope, index))
            end
        end

        --- One charge step on a held plate; the last step disrupts the living wizard's shield.
        local function charge_step(context, scope, index)
            if scope:variable(c.CIRCLE_KEY .. index) ~= true or charged(scope, index)
                or not plate_active(scope, index) then
                return
            end
            local level = (scope:variable(c.CHARGE_KEY .. index) or 0) + 1
            scope:set_variable(c.CHARGE_KEY .. index, level)
            visuals.play_increment(context, index)
            if level < c.CHARGE_STEPS then
                show_plate(context, scope, index)
                scope:start_timer(c.CHARGE_TIMERS[index], c.CHARGE_STEP_MS)
                return
            end
            scope:set_variable(c.CHARGED_KEY .. index, true)
            if scope:variable(c.STAGE_KEY) == c.STAGE_WIZARDS then
                visuals.drop_shield(context, scope, index)
                visuals.play_shield_change(context, index, false)
            end
            show_plate(context, scope, index)
        end

        --- Refreshes both devices after a phase change without requiring another trigger report.
        local function show_plates(context, scope)
            for index = 1, #wizards do show_plate(context, scope, index) end
        end

        --- Brings in the Sorcerer for normal play.
        local function bring_sorcerer(context, scope)
            scope:set_variable(c.STAGE_KEY, c.STAGE_BOSS)
            show_plates(context, scope)
            place(context, scope, definition.sorcerer)
            ev:goal(context, scope, presentation.directive.enter)
        end

        --- Opens the portal and its crystals; the boss follows after the window.
        local function open_portal(context, scope)
            scope:set_variable(c.STAGE_KEY, c.STAGE_PORTAL)
            ev:say(context, c.CUE_PORTAL)
            visuals.open_portal(context)
            show_plates(context, scope)
            ev:goal(context, scope, presentation.directive.enter)
            scope:start_timer(c.BOSS_TIMER, c.BOSS_DELAY_MS)
            scope:start_timer(c.PORTAL_TIMER, c.PORTAL_FIRST_MS)
        end

        --- Counts a wizard's death once; the second opens the portal.
        local function wizard_down(context, scope, index)
            scope:set_variable(c.KILLED_KEY, killed(scope) + 1)
            if killed(scope) >= c.WIZARD_COUNT then
                open_portal(context, scope)
            else
                show_plate(context, scope, index)
                ev:goal(context, scope, presentation.directive.enter)
            end
        end

        --- Routes one ended unit to its role; supporting squads only clear their live flag.
        local function unit_ended(context, scope, unit, generation)
            mark_ended(scope, unit, generation)
            for index, wizard in ipairs(wizards) do
                if unit == wizard then wizard_down(context, scope, index) end
            end
            local plate = knight_plate(unit)
            if plate ~= nil then send_knight(context, scope, plate) end
            if unit == definition.sorcerer or unit == definition.champion then
                ev:finish(context, scope, true)
            end
        end

        --- Returns the live unit that this report names, or nil.
        local function live_unit(context, scope, report)
            for _, unit in ipairs(units) do
                if scope:variable(live_key(unit)) == true
                    and lib.is_slot(context, report, unit.slot) then
                    return unit
                end
            end
            return nil
        end

        --- True when every member of the unit has ended in a count-only report.
        local function counted_out(context, unit, report)
            local squad = context:squad(unit.squad)
            for index = 1, squad.member_count do
                if (report.slot_counts[index] or 0) < (squad.default_counts[index] or 0) then
                    return false
                end
            end
            return true
        end

        hooks.incoming = {{delay_ms = 0, run = function(context, scope)
            ev:show_incoming(context, scope, presentation.directive.enter)
        end}}
        hooks.start_delay_ms = c.START_AFTER_LEAVE_MS
        hooks.timers = {c.INTRO_TIMER, c.WAVE_TIMER, c.BOSS_TIMER, c.JOIN_LINE_TIMER,
            c.PORTAL_TIMER, table.unpack(c.CHARGE_TIMERS)}
        hooks.tracked, hooks.required = {}, {}
        for _, unit in ipairs(units) do
            squads.append_request_keys(hooks.tracked, unit_key(unit))
        end
        for _, unit in ipairs(critical) do
            squads.append_request_keys(hooks.required, unit_key(unit))
        end
        hooks.scenery = visuals.scenery()
        hooks.device_keys = {c.GATEWAY_KEY, table.unpack(c.PLATE_KEYS)}
        for index = 1, #wizards do
            hooks.device_keys[#hooks.device_keys + 1] = c.ARTIFACT_KEYS[index]
            hooks.device_keys[#hooks.device_keys + 1] = c.CRYSTAL_SHIELD_KEY .. index
            for rune = 1, c.RUNES_PER_ARTIFACT do
                hooks.device_keys[#hooks.device_keys + 1] = c.RUNE_KEY .. index .. "." .. rune
            end
        end

        --- The counter row counts wizards; the later rows name the portal and each boss.
        function hooks.goal(scope)
            local stage = scope:variable(c.STAGE_KEY)
            if ev:heroic(scope) then
                return {directive = definition.heroic_directive, total_seconds = c.EVENT_SECONDS}
            end
            if stage == c.STAGE_BOSS then
                return {directive = definition.boss_directive, total_seconds = c.EVENT_SECONDS}
            end
            if stage == c.STAGE_PORTAL then
                return {directive = definition.portal_directive, total_seconds = c.EVENT_SECONDS}
            end
            return {directive = definition.directive, total_seconds = c.EVENT_SECONDS,
                progress = {killed(scope), c.WIZARD_COUNT}}
        end

        --- Resets the attempt, shields both wizards and sends the opening crews.
        function hooks.on_start(context, scope)
            scope:set_variable(c.STAGE_KEY, c.STAGE_WIZARDS)
            scope:set_variable(c.KILLED_KEY, 0)
            scope:set_variable(c.WAVE_COUNT_KEY, 0)
            scope:set_variable(c.PORTAL_COUNT_KEY, 0)
            for _, unit in ipairs(units) do scope:clear_variable(c.ENDED_KEY .. unit.name) end
            for index = 1, #crystals do scope:clear_variable(c.CRYSTAL_KEY .. index) end
            for index = 1, #wizards do
                scope:clear_variable(c.CIRCLE_KEY .. index)
                scope:clear_variable(c.KNIGHT_KEY .. index)
                clear_charge(scope, index)
            end
            visuals.begin(context)
            for index, wizard in ipairs(wizards) do
                place(context, scope, wizard)
                place(context, scope, definition.acolytes[index])
                visuals.raise_shield(context, scope, index)
                show_plate(context, scope, index)
            end
            scope:start_timer(c.INTRO_TIMER, c.INTRO_MS)
            scope:start_timer(c.WAVE_TIMER, c.FIRST_WAVE_MS)
        end

        --- The Champion and the first thralls arrive through the portal; one boss per outcome,
        --- so a Sorcerer already standing is retired first.
        function hooks.on_heroic(context, scope)
            scope:cancel_timer(c.BOSS_TIMER)
            local sorcerer = definition.sorcerer
            if scope:variable(live_key(sorcerer)) == true then
                squads.retire(context, sorcerer.squad)
                scope:clear_variable(unit_key(sorcerer))
                mark_ended(scope, sorcerer, nil)
            end
            scope:set_variable(c.STAGE_KEY, c.STAGE_BOSS)
            show_plates(context, scope)
            place(context, scope, definition.champion)
            for _, unit in ipairs(definition.thralls) do place(context, scope, unit) end
        end

        --- Stops the encounter's squads and sigils before the shared result presentation.
        function hooks.on_stop(context, scope)
            retire_squads(context, scope)
            visuals.gateway(context, scope)
            scope:cancel_timer(c.PORTAL_TIMER)
            for index = 1, #wizards do
                clear_charge(scope, index)
                visuals.plate(context, scope, index, c.PLATE_OFF)
                visuals.pillar(context, scope, index, 0, c.PILLAR_OFF)
                if scope:variable(c.CRYSTAL_SHIELD_KEY .. index) ~= nil
                    and scope:variable(c.CRYSTAL_KEY .. index) ~= true then
                    visuals.crystal_shield(context, scope, index, true)
                end
            end
        end

        --- The boss exit scenes have no recovered trigger; cleanup removes the scenery instead.
        function hooks.on_finish() end

        --- Removes both shields and the scenery's controls; repeatable. Rows reset here so the next
        --- attempt's passive location row starts from the wizard counter.
        function hooks.on_cleanup(context, scope)
            scope:clear_variable(c.STAGE_KEY)
            scope:clear_variable(c.KILLED_KEY)
            return visuals.cleanup(context, scope)
        end

        --- A refused supporting placement never reports, so it must not stay live.
        function hooks.on_failure(_, scope, report)
            for _, unit in ipairs(units) do
                if squads.owns_request(scope, unit_key(unit), report.request_key) then
                    scope:clear_variable(live_key(unit))
                    return
                end
            end
        end

        --- Wizard and boss deaths advance the event; other squads only clear their flag.
        function hooks.on_squad(context, scope, _, report)
            local unit = live_unit(context, scope, report)
            if unit ~= nil then unit_ended(context, scope, unit, report.spawn_generation) end
            return false
        end

        --- A unit that never reported alive ends on its count-only report, once per generation.
        function hooks.on_squad_counted(context, scope, _, report)
            local unit = live_unit(context, scope, report)
            local generation = report.spawn_generation
            if unit == nil or generation == nil or report.initial_observation == true
                or generation == scope:variable(c.ENDED_KEY .. unit.name)
                or not counted_out(context, unit, report) then
                return false
            end
            unit_ended(context, scope, unit, generation)
            return false
        end

        --- Entering a sigil starts its charge; leaving forgets it and restores a living wizard's
        --- shield if the charge had completed. Occupancy outlives wizard death.
        function hooks.on_trigger(context, scope, _, report)
            if report.available == false or report.occupied == nil then return false end
            for index, circle in ipairs(definition.circles) do
                local wizard = wizards[index]
                local was = scope:variable(c.CIRCLE_KEY .. index) == true
                if lib.is_slot(context, report, circle) then
                    scope:set_variable(c.CIRCLE_KEY .. index, report.occupied)
                    if report.occupied and not was then
                        scope:set_variable(c.CHARGE_KEY .. index, 0)
                        scope:start_timer(c.CHARGE_TIMERS[index], c.CHARGE_STEP_MS)
                        if scope:variable(c.STAGE_KEY) == c.STAGE_WIZARDS
                            and scope:variable(c.KNIGHT_KEY .. index) == nil then
                            send_knight(context, scope, index)
                        end
                    elseif was and not report.occupied then
                        local completed = charged(scope, index)
                        clear_charge(scope, index)
                        if completed and scope:variable(live_key(wizard)) == true then
                            visuals.raise_shield(context, scope, index)
                            visuals.play_shield_change(context, index, true)
                        end
                    end
                    show_plate(context, scope, index)
                end
            end
            return false
        end

        --- Both crystals falling inside the portal window commits heroic.
        function hooks.on_object_state(context, scope, _, report)
            if scope:variable(c.STAGE_KEY) ~= c.STAGE_PORTAL or report.present ~= false
                or report.initial_observation == true then
                return false
            end
            local fallen = 0
            for index, crystal in ipairs(crystals) do
                if lib.is_slot(context, report, crystal) then
                    scope:set_variable(c.CRYSTAL_KEY .. index, true)
                end
                if scope:variable(c.CRYSTAL_KEY .. index) == true then fallen = fallen + 1 end
            end
            if fallen == #crystals and not ev:heroic(scope) and ev:remaining(scope) > 0 then
                ev:commit_heroic(context, scope, ev:remaining(scope))
            end
            return false
        end

        --- Handles the intro, wave, charge, portal and portal-window timers.
        function hooks.on_timer(context, scope, _, _, name)
            for index, timer in ipairs(c.CHARGE_TIMERS) do
                if name == timer then
                    charge_step(context, scope, index)
                    return false
                end
            end
            if name == c.INTRO_TIMER then
                visuals.finish_intro(context)
            elseif name == c.WAVE_TIMER then
                send_group(context, scope)
                scope:start_timer(c.WAVE_TIMER, c.WAVE_INTERVAL_MS)
            elseif name == c.PORTAL_TIMER then
                send_portal_group(context, scope)
                scope:start_timer(c.PORTAL_TIMER, c.PORTAL_INTERVAL_MS)
            elseif name == c.JOIN_LINE_TIMER then
                ev:say(context, definition.join_lines.second)
            elseif name == c.BOSS_TIMER and not ev:heroic(scope) then
                bring_sorcerer(context, scope)
            end
            return false
        end

        return hooks
    end)
end

return module
