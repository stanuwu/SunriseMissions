-- Rally-point opportunity shared by public events. The flag stands for one countdown that runs
-- from its appearance. The first rally binds the rally audience, shows the countdown row and
-- starts the tone; it never moves the clock. The audience volume is bound only then: bound at
-- the flag's appearance it made the client treat every player inside it as already rallied.
-- Mutable state stays in the host scope.
local lib = require("lib.mission_lib")
local site_names = require("lib.public_events.site_names")
local devices = require("lib.public_events.devices")
local presentation = require("lib.public_events.presentation")

local rally = {}

-- Every rally row shares this authored name hash and first element.
local DIRECTIVE_HASH, DIRECTIVE_ELEMENT = 0x76B10BE7, 0
local DIRECTIVE_BASE = "PUBLIC_EVENT_INCOMING"
local HASHED_DIRECTIVE = string.format("%s_%08X", DIRECTIVE_BASE, DIRECTIVE_HASH)
local MS_PER_SECOND = 1000
-- Reconstructed countdown shown from the moment the flag appears.
local COUNTDOWN_SECONDS = 60
-- The completed countdown lingers for one second before the flag leaves.
local LINGER_MS = 1000
-- The flag's authored sound owns repetition and pitch; the device position selects them.
-- Reconstructed: the position is the elapsed share of a 300 s countdown, moved in 5 s stages
-- counted back from the moment the flag leaves.
local AUTHORED_SECONDS, STAGE_SECONDS = 300, 5
-- Reconstructed policy: a shorter countdown plays the last three stages unchanged and spreads
-- the earlier part of the range over the time before them.
local FINAL_SECONDS = 15
-- Interval armed on the tone timer to read the host time back from its deadline.
local CLOCK_READ_MS = 1000
-- A stage timer fires this long after its boundary, so the reading lies inside the new stage.
local STAGE_MARGIN_MS = 50
-- Lowest position inside the tone's range.
local AUDIO_MIN_POSITION = 0.01
-- Past the tone's range the flag plays its authored ending: one long tone as it folds away.
local AUDIO_END_POSITION = 1
-- Reconstructed time the ending needs before the flag object is taken away.
local FOLD_MS = 1500
-- Flag incidents identify no player; retain a distinct non-player marker.
local INCIDENT_OWNER = "incident"

---@class RallyDefinition
---@field flag string Type-4 flag object slot.
---@field device string Type-23 flag device slot driving the tone.
---@field sensor string Type-68 directive sensor of the rally registry.
---@field engagement string Type-70 audience sensor, optionally shared with active play.
---@field volume string Type-60 volume owned by the audience sensor's registry.
---@field directive table|nil Countdown row found by rally.find_directive.
---@field incident_target integer|nil Reconstructed client incident naming a flag use.
---@field settled boolean|nil Post the countdown row settled, as the goal row is; default unsettled.
---@field audience_free boolean|nil Post the countdown row to no audience; default the rally
--- audience.
---@field admit_everyone boolean|nil Admit every present player to the rally audience at the first
--- rally, so the countdown shows at the flag when the flag stands outside the rally volume.

local Rally = {}
Rally.__index = Rally

--- Finds the countdown row of a rally sensor; generated key suffixes are not stable.
function rally.find_directive(mission, sensor)
    local key, suffix = DIRECTIVE_BASE, 1
    while true do
        local row = mission.Directive[key]
        if row == nil then return nil end
        if row.sensor == sensor and row.name_hash == DIRECTIVE_HASH
            and row.element == DIRECTIVE_ELEMENT then
            return row
        end
        -- The first duplicate has only the hash. Later duplicates append _2, _3 and so on.
        key = HASHED_DIRECTIVE
        if suffix > 1 then key = key .. "_" .. suffix end
        suffix = suffix + 1
    end
end

-- Reconstructed flag-use binding to client incident object definition 7043.
rally.FLAG_INCIDENT = 7043

--- Resolves an authored PF_PUBLIC_EVENT_RALLY_POINT prefab by its generated registry suffix.
---@param mission table Generated mission module.
---@param suffix string Generated suffix of the rally registry, such as "_80C03220".
---@param volume string|nil Exact generated volume key when this prefab uses another stem.
---@return RallyDefinition
function rally.bind(mission, suffix, volume)
    local function slot(stem)
        return lib.one(mission.Slot[stem .. suffix], "rally slot " .. stem)
    end
    local sensor = slot("M_DIRECTIVE_SENSOR")
    return {
        flag = slot("PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG"),
        device = slot("PF_PUBLIC_EVENT_RALLY_POINT_RALLY_FLAG_DEVICE"),
        sensor = sensor,
        engagement = slot("M_ENGAGEMENT_SENSOR"),
        volume = volume ~= nil and lib.one(mission.Slot[volume], "rally volume " .. volume)
            or slot("RALLY_POINT_SPAWN_OVERRIDE_VOLUME"),
        directive = rally.find_directive(mission, sensor),
        incident_target = rally.FLAG_INCIDENT,
    }
end

-- Root prefabs a rally object is authored under.
local RALLY_ROOTS = {"PF_PUBLIC_EVENT_RALLY_POINT", "EVENT_RALLY_POINT", "RALLY_POINT_PREFAB"}
-- Stem of the spawn-override volume unless the site names its own; most sites do.
local RALLY_VOLUME = "RALLY_POINT_SPAWN_OVERRIDE_VOLUME"

--- Binds the rally prefab of one object; its root prefab and its volume's stem differ by site.
---@param tag string Eight upper-case hex digits of the rally object's tag.
---@param volume_stem string|nil Stem of its spawn-override volume when the site names its own.
---@return RallyDefinition
function rally.bind_object(mission, tag, volume_stem)
    local Slot = mission.Slot
    local object = site_names.object(mission, tag)
    local flag, device
    for _, root in ipairs(RALLY_ROOTS) do
        flag = flag or object.find(root .. "_RALLY_FLAG")
        device = device or object.find(root .. "_RALLY_FLAG_DEVICE")
    end
    local volume = object.find(volume_stem or RALLY_VOLUME)
    local sensor = Slot[object.zone("M_DIRECTIVE_SENSOR")]
    return {
        flag = Slot[lib.one(flag, "rally flag of object " .. tag)],
        device = Slot[lib.one(device, "rally flag device of object " .. tag)],
        sensor = sensor,
        engagement = Slot[object.zone("M_ENGAGEMENT_SENSOR")],
        volume = Slot[lib.one(volume, "rally volume of object " .. tag)],
        directive = rally.find_directive(mission, sensor),
        incident_target = rally.FLAG_INCIDENT,
    }
end

--- The marker slot of a rally prefab, for an event whose own object authors none.
---@param tag string Eight upper-case hex digits of the rally object's tag.
---@return string slot Slot id of the rally's location point.
function rally.location_point(mission, tag)
    local object = site_names.object(mission, tag)
    local point
    for _, root in ipairs(RALLY_ROOTS) do
        point = point or object.find(root .. "_LOCATION_POINT")
    end
    return mission.Slot[lib.one(point, "location point of rally object " .. tag)]
end

--- Binds one rally point; key names derive from the owning event's prefix.
---@param definition RallyDefinition
---@param prefix string Host-scope prefix of the owning event.
function rally.new(definition, prefix)
    return setmetatable({
        definition = lib.one(definition, "rally definition"),
        used_key = prefix .. ".fu",
        total_key = prefix .. ".ft",
        audio_key = prefix .. ".fa",
        fold_key = prefix .. ".fd",
        leave_timer = prefix .. "rl",
        audio_timer = prefix .. "ra",
        stop_timer = prefix .. "rz",
    }, Rally)
end

--- Returns the first flag user, or nil while the flag is unused.
function Rally:used(scope)
    return scope:variable(self.used_key)
end

--- Returns the audience handle for the countdown row, or nil for an audience-free site.
function Rally:row_audience(context)
    if self.definition.audience_free == true then return nil end
    return context:slot(self.definition.engagement)
end

--- Returns true while this rally owns the named timer.
function Rally:owns_timer(name)
    return name == self.leave_timer or name == self.audio_timer or name == self.stop_timer
end

--- Raises the flag and starts its countdown; the row, audience and tone wait for the first rally.
---@param seconds integer|nil Seconds until the start; the whole countdown when nil.
---@param total integer|nil The countdown the row totals; the retained default when nil.
function Rally:open(context, scope, seconds, total)
    local definition = self.definition
    total = total or COUNTDOWN_SECONDS
    local countdown = seconds or total
    scope:clear_variable(self.used_key)
    scope:clear_variable(self.fold_key)
    scope:set_variable(self.total_key, total)
    context:activate_objects{slots = {definition.flag}, active = true}
    context:slot(definition.flag):set_interactable_object{track_owner = true}
    scope:start_timer(self.leave_timer, countdown * MS_PER_SECOND + LINGER_MS)
    scope:start_timer(self.stop_timer, countdown * MS_PER_SECOND)
end

--- The countdown this flag opened with; the retained default for a flag opened without one.
function Rally:total(scope)
    return scope:variable(self.total_key) or COUNTDOWN_SECONDS
end

--- Milliseconds from current host time to a rally timer's deadline, or nil once it has gone.
--- Re-arms the tone timer: its new deadline is how the script reads the host time.
function Rally:until_ms(scope, timer)
    local deadline = tonumber(scope.state:timer(scope:key(timer)))
    if deadline == nil then return nil end
    scope:start_timer(self.audio_timer, CLOCK_READ_MS)
    local armed = tonumber(scope.state:timer(scope:key(self.audio_timer)))
    return deadline - (armed - CLOCK_READ_MS)
end

--- Tone position for the stages left until the flag leaves.
---@param stages integer Five-second stages left, the running one included.
---@param total_seconds number The whole wait from the flag's appearance until it leaves.
local function tone_position(stages, total_seconds)
    local seconds = stages * STAGE_SECONDS
    if seconds > FINAL_SECONDS and total_seconds > FINAL_SECONDS
        and total_seconds < AUTHORED_SECONDS then
        seconds = FINAL_SECONDS + (seconds - FINAL_SECONDS)
            * (AUTHORED_SECONDS - FINAL_SECONDS) / (total_seconds - FINAL_SECONDS)
    end
    return math.max(AUDIO_MIN_POSITION, 1 - seconds / AUTHORED_SECONDS)
end

--- Shows the countdown row and starts the tone at the time left. An audience-free site names no
--- audience on the row: the client shows an audience row only once its engagement sensor admits
--- the player, which waits for the walk from the flag into the rally volume.
function Rally:show(context, scope)
    local definition = self.definition
    local remaining = self:until_ms(scope, self.stop_timer)
    local total = self:total(scope)
    local seconds = 0
    if remaining ~= nil and remaining > 0 then
        seconds = math.floor(remaining / MS_PER_SECOND)
    end
    if seconds > total then seconds = total end
    if definition.directive ~= nil then
        context:slot(definition.sensor):set_directive{
            directive = definition.directive,
            state = presentation.directive.enter,
            active = false,
            settled = definition.settled == true,
            audience = self:row_audience(context),
            clock = {remaining = seconds, total = total},
        }
        -- The rally definition requires membership to keep its countdown visible.
        presentation.audience(context, definition.engagement, definition.volume, true,
            definition.admit_everyone == true)
    end
    self:update_audio(context, scope)
end

--- Stops the flag tone and its timers.
function Rally:stop_audio(context, scope)
    scope:cancel_timer(self.audio_timer)
    scope:cancel_timer(self.stop_timer)
    if self:used(scope) ~= nil then
        devices.set_position(context, scope, self.definition.device, self.audio_key, 0, true)
    end
end

--- Sets the tone's stage for the time left until the flag leaves and arms the next stage. The
--- tone runs through the lingering second after zero.
function Rally:update_audio(context, scope)
    local remaining = self:until_ms(scope, self.leave_timer)
    if remaining == nil or remaining <= 0 then
        scope:cancel_timer(self.audio_timer)
        return
    end
    local stage_ms = STAGE_SECONDS * MS_PER_SECOND
    local stages = math.ceil(remaining / stage_ms)
    local total_seconds = self:total(scope) + LINGER_MS / MS_PER_SECOND
    devices.set_position(context, scope, self.definition.device, self.audio_key,
        tone_position(stages, total_seconds), true)
    if stages > 1 then
        scope:start_timer(self.audio_timer, remaining - (stages - 1) * stage_ms + STAGE_MARGIN_MS)
    else
        scope:cancel_timer(self.audio_timer)
    end
end

--- Completes a shown countdown row.
local function complete_row(self, context, scope)
    local definition = self.definition
    if definition.directive ~= nil and self:used(scope) ~= nil then
        context:slot(definition.sensor):set_directive{
            directive = definition.directive, state = presentation.directive.complete,
            active = false, settled = false, audience = self:row_audience(context)}
    end
end

--- Silences the tone and takes the flag object away.
local function remove(self, context, scope)
    self:stop_audio(context, scope)
    scope:clear_variable(self.fold_key)
    context:activate_objects{slots = {self.definition.flag}, active = false}
end

--- Records the first flag user and shows the running countdown; later uses change nothing.
function Rally:use(context, scope, owner)
    if self:used(scope) ~= nil then return false end
    scope:set_variable(self.used_key, owner)
    self:show(context, scope)
    return true
end

--- Accepts the reconstructed flag-use incident; returns true on the first use.
function Rally:on_incident(context, scope, event)
    local target = self.definition.incident_target
    if target == nil or event.incident_target ~= target then return false end
    return self:use(context, scope, INCIDENT_OWNER)
end

--- Accepts a flag interaction; returns true on the first use.
function Rally:on_interaction(context, scope, event)
    if not lib.is_slot(context, event, self.definition.flag) then return false end
    return self:use(context, scope, tostring(event.owner_key or "unknown"))
end

--- Services the tone timer; returns true when the flag is due to leave. The stop timer only
--- marks zero for the row and the launcher.
function Rally:on_timer(context, scope, name)
    if name == self.audio_timer then
        if scope:variable(self.fold_key) == true then
            remove(self, context, scope)
        else
            self:update_audio(context, scope)
        end
    end
    return name == self.leave_timer
end

--- Ends the countdown and completes a shown row. A used flag plays its authored ending and is
--- taken away after it; an unused flag was silent and goes at once.
function Rally:leave(context, scope)
    if self:used(scope) == nil then
        remove(self, context, scope)
        return
    end
    scope:cancel_timer(self.stop_timer)
    devices.set_position(context, scope, self.definition.device, self.audio_key,
        AUDIO_END_POSITION, true)
    scope:set_variable(self.fold_key, true)
    scope:start_timer(self.audio_timer, FOLD_MS)
    complete_row(self, context, scope)
end

--- Takes a standing flag away at once, without its ending, and completes a shown row.
function Rally:withdraw(context, scope)
    remove(self, context, scope)
    complete_row(self, context, scope)
end

--- Clears the countdown row, retaining membership only when active play uses this audience.
---@param keep_audience boolean|nil Leave the audience bound for the active event.
function Rally:close(context, scope, keep_audience)
    scope:cancel_timer(self.leave_timer)
    scope:clear_variable(self.total_key)
    if scope:variable(self.fold_key) == true then
        remove(self, context, scope)
    else
        self:stop_audio(context, scope)
    end
    local definition = self.definition
    context:slot(definition.sensor):clear_directives()
    if not keep_audience and definition.directive ~= nil and self:used(scope) ~= nil then
        presentation.audience(context, definition.engagement, definition.volume, false)
    end
end

return rally
