-- Ether Resupply mechanics: the Prime Ether Servitor is the one
-- critical role and its death ends the event. A site that authors the intro gets the Ketch, the
-- skeleton-crew Skiff and its Vandals, the communion, the beam and the covers around the Prime.
-- The Transport Servitors, their shield, the heroic commit and the supporting waves are not
-- here yet.
local lib = require("lib.mission_lib")
local event = require("lib.public_events.event")
local presentation = require("lib.public_events.presentation")
local squads = require("lib.public_events.squads")
local c = require("lib.public_events.ether_resupply.settings")

local module = {}

---@class EtherIntro
---@field ketch string The Ketch flyover object.
---@field sequence string Authored intro sequence.
---@field active string Authored active behavior sequence.
---@field communion table The Prime's intro scene.
---@field beam string The sky beam object.
---@field cover string[] Cover objects around the site.
---@field skiff Unit The skeleton-crew Skiff; its authored command sequences carry no destination,
--- so the runtime refuses them as actor paths and the ship is placed and retired, not flown.
---@field crew Unit[] The Vandals the Skiff drops.

--- Builds the Ether Resupply handler; its retained keys require the site's freeroam scope.
---@param definition table Authored site references; `intro` (EtherIntro) is optional.
---@return table handler Freeroam site handler.
function module.new(definition)
    local prime = definition.prime
    local intro = definition.intro

    return event.new(definition, c, function(ev)
        local hooks = {}

        -- The cues of this registry's dialogue sensor are unmapped; no line is played.
        function ev:say() end

        hooks.tracked = {}
        squads.append_request_keys(hooks.tracked, c.PRIME_KEY)
        -- Only the Prime's placement is required. Its objective assignment is not: the host's
        -- second public link repeats every request and has its slot requests refused, and a
        -- refused assignment leaves the Prime standing.
        hooks.required = {c.PRIME_KEY}
        hooks.incoming = {}
        hooks.scenery = {}
        if intro ~= nil then
            squads.append_request_keys(hooks.tracked, c.SKIFF_KEY)
            for index = 1, #intro.crew do
                squads.append_request_keys(hooks.tracked, c.CREW_KEY .. index)
            end
            hooks.timers = {c.INTRO_TIMER}
            hooks.scenery = {intro.ketch, intro.beam}
            for _, slot in ipairs(intro.cover) do hooks.scenery[#hooks.scenery + 1] = slot end
            -- After the flag leaves: the Ketch with the event row, then the Skiff;
            -- the Prime follows at the start.
            hooks.incoming = {
                {delay_ms = c.KETCH_AFTER_LEAVE_MS, run = function(context, scope)
                    context:activate_objects{slots = {intro.ketch}, active = true}
                    ev:show_incoming(context, scope, presentation.directive.enter)
                end},
                {delay_ms = c.SKIFF_AFTER_KETCH_MS, run = function(context, scope)
                    squads.place(context, scope, intro.skiff, c.SKIFF_KEY)
                end},
            }
            hooks.start_delay_ms = c.START_AFTER_SKIFF_MS
        end

        --- The single objective row. Its marker stays on the site's point: a row's navpoint must be
        --- a type-47 slot, so the Prime's objective cannot carry the diamond.
        function hooks.goal()
            return {directive = definition.directive, total_seconds = c.EVENT_SECONDS}
        end

        --- Drops the crew beside the Prime.
        local function drop_crew(context, scope)
            for index, unit in ipairs(intro.crew) do
                squads.place(context, scope, unit, c.CREW_KEY .. index)
            end
        end

        --- Ends the intro: the communion and the beam stop, the Skiff leaves, the active
        --- behavior runs.
        local function finish_intro(context, scope)
            context:scene(intro.communion):stop{}
            context:activate_objects{slots = {intro.beam}, active = false}
            squads.retire_if_placed(context, scope, intro.skiff, c.SKIFF_KEY)
            context:slot(intro.active):play_sequence{}
        end

        --- Places the Prime; with the intro, under its communion and beam, with the covers up.
        function hooks.on_start(context, scope)
            squads.place(context, scope, prime, c.PRIME_KEY)
            if intro == nil then return end
            context:activate_objects{slots = {intro.beam}, active = true}
            context:activate_objects{slots = intro.cover, active = true}
            context:scene(intro.communion):activate{}
            context:slot(intro.sequence):play_sequence{}
            scope:set_variable(c.INTRO_STAGE_KEY, c.INTRO_CREW)
            scope:start_timer(c.INTRO_TIMER, c.CREW_AFTER_START_MS)
        end

        --- The intro's two beats: the crew drops, then the intro ends.
        function hooks.on_timer(context, scope, _, _, name)
            if name ~= c.INTRO_TIMER then return false end
            local stage = scope:variable(c.INTRO_STAGE_KEY)
            if stage == c.INTRO_CREW then
                drop_crew(context, scope)
                scope:set_variable(c.INTRO_STAGE_KEY, c.INTRO_DONE)
                scope:start_timer(c.INTRO_TIMER, c.INTRO_MS - c.CREW_AFTER_START_MS)
            elseif stage == c.INTRO_DONE then
                scope:clear_variable(c.INTRO_STAGE_KEY)
                finish_intro(context, scope)
            end
            return false
        end

        --- Retires whatever still stands: the Prime, the Skiff and the crew; the scene stops.
        function hooks.on_stop(context, scope)
            squads.retire_if_placed(context, scope, prime, c.PRIME_KEY)
            if intro == nil then return end
            squads.retire_if_placed(context, scope, intro.skiff, c.SKIFF_KEY)
            for index, unit in ipairs(intro.crew) do
                squads.retire_if_placed(context, scope, unit, c.CREW_KEY .. index)
            end
            if scope:variable(c.INTRO_STAGE_KEY) ~= nil then
                scope:clear_variable(c.INTRO_STAGE_KEY)
                context:scene(intro.communion):stop{}
            end
        end

        --- No site-specific ending beat; the event's banner and chest follow.
        function hooks.on_finish() end

        --- The shared event removes the scenery with the chest; nothing else is queued.
        function hooks.on_cleanup() end

        --- The Prime's death report ends the event once; a repeated report finds no live Prime.
        function hooks.on_squad(context, scope, _, report)
            if scope:variable(c.PRIME_KEY) == nil
                or not lib.is_slot(context, report, prime.slot) then
                return false
            end
            scope:clear_variable(c.PRIME_KEY)
            ev:finish(context, scope, true)
            return false
        end

        --- Uses the same completion path when the native generation ends before an alive fall.
        function hooks.on_squad_counted(context, scope, site, report)
            if lib.is_slot(context, report, prime.slot)
                and squads.counted_out(context, prime, report) then
                return hooks.on_squad(context, scope, site, report)
            end
            return false
        end

        return hooks
    end)
end

return module
