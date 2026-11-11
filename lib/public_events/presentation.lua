-- Shared SDK presentation operations; event definitions choose content and audiences.
local presentation = {}

--- Directive states accepted by the SDK; navpoints and clocks belong to entering objectives.
presentation.directive = {enter = 0, complete = 1, exit = 2}

--- Plays one authored cue, optionally restricted to a supplied volume.
function presentation.dialogue(context, sensor, cue, volume)
    context:slot(sensor):play_dialogue_cue{
        cue = cue, filter = volume ~= nil and context:slot(volume) or nil,
    }
end

--- Replaces the complete music selection; nil clears it using the supplied default section.
---@return userdata request Queued music control.
function presentation.music(context, sensor, section, default_section)
    return context:slot(sensor):set_music_section{
        section = section or default_section, enabled = section ~= nil,
    }
end

--- Rebinds an audience with a new revision; an absent sensor leaves it unchanged. The volumes
--- argument is one slot or a list of same-owner slots; a player inside any of them is a member.
---@return userdata|nil request Queued binding, or nil when the sensor is absent.
---@param everyone boolean|nil Admit every present player as well as the occupants of the volumes.
function presentation.audience(context, scope, sensor, volumes, key, enabled, everyone)
    if sensor == nil then return end
    if type(volumes) ~= "table" then volumes = {volumes} end
    local handles = {}
    if enabled then
        for _, volume in ipairs(volumes) do handles[#handles + 1] = context:slot(volume) end
    end
    local revision = (scope:variable(key) or 0) + 1
    local request = context:slot(sensor):set_engagement{volumes = handles, revision = revision,
        everyone = (enabled and everyone == true) or nil}
    scope:set_variable(key, revision)
    return request
end

---@class GoalOptions
---@field audience table Engagement slot handle the row is shown to.
---@field progress table|nil Counter {current, maximum} of counter rows.
---@field navpoint table|nil Marker slot handle of rows that track a location.
---@field clock table|nil {remaining, total}; shown by entering rows only.
---@field event table|nil Public-event sensor handle whose state the HUD record copies.
---@field entrance boolean|nil Play the entry transition instead of settling.

--- Posts one objective row; entering rows settle with their clock and marker, later states play
--- active without either: the native encoder refuses a marker on a non-entering row.
--- On public sensors the client shows the marker timer only outside the row's audience.
---@param options GoalOptions
function presentation.goal(context, sensor, directive, state, options)
    local entering = state == presentation.directive.enter
    context:slot(sensor):set_directive{
        directive = directive,
        state = state,
        active = not entering,
        settled = entering and not options.entrance,
        audience = options.audience,
        progress = options.progress,
        navpoint = entering and options.navpoint or nil,
        event = options.event,
        clock = entering and options.clock or nil,
    }
end

return presentation
