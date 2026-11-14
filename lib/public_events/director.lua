-- Native public-event sensor state for objective/HUD presentation.
-- Director map nodes read the authored schedule independently of these writes.
local director = {}

-- Heroic and closing values sent to the type-71 sensor.
local STATE_HEROIC, STATE_CLOSED = 1, 0
-- Leave delay sent with the heroic sensor state, in seconds.
local LEAVE_SECONDS = 600
-- Site-opt-in normal sensor state, sent at start and withdrawn only by its owning cleanup.
local NORMAL_STATE, NORMAL_LEAVE_SECONDS = 0, 30

local Director = {}
Director.__index = Director

---@class DirectorDefinition
---@field event_sensor string|nil Type-71 public-event sensor of the site.
---@field event_area string|nil Type-60 volume the sensor watches the player against.
---@field normal_event_state boolean|nil Opt into the native normal sensor state.

--- Binds a site's sensor and area; either may be nil while the policy is unsent.
---@param definition DirectorDefinition
function director.new(definition)
    return setmetatable({sensor = definition.event_sensor, area = definition.event_area,
        normal_opt_in = definition.normal_event_state == true}, Director)
end

--- True when the site has both a sensor and an area.
function Director:bound()
    return self.sensor ~= nil and self.area ~= nil
end

--- Returns the sensor handle for rows that name it, or nil without one.
function Director:handle(context)
    if self.sensor == nil then return nil end
    return context:slot(self.sensor)
end

--- Sends one sensor state.
---@param context table Borrowed callback context.
---@param state integer Existing sensor-state policy value.
---@param leave_seconds integer Leave delay in seconds.
---@return userdata request Queued request, not a client acknowledgement.
function Director:send(context, state, leave_seconds)
    return context:slot(self.sensor):set_public_event_state{
        state = state, area = context:slot(self.area), leave_seconds = leave_seconds,
    }
end

--- Publishes the active event when the objective starts; an opt-in uses the normal preset.
---@param context table Borrowed callback context.
---@return userdata|nil request Queued request, or nil when normal sends are disabled or unbound.
function Director:activate(context)
    if self.normal_opt_in and self:bound() then
        return self:send(context, NORMAL_STATE, NORMAL_LEAVE_SECONDS)
    end
end

--- Publishes the heroic state before the heroic objective row.
---@param context table Borrowed callback context.
---@return userdata|nil request Queued request, or nil when the site has no sensor or area.
function Director:heroic(context)
    if self:bound() then
        return self:send(context, STATE_HEROIC, LEAVE_SECONDS)
    end
end

--- Only an attempt that sent a normal-state request owns its closing request.
---@param context table Borrowed callback context.
---@param normal_requested boolean Whether this attempt owns a normal sensor request.
---@return userdata|nil request Closing request, or nil without a normal request and bound sensor.
function Director:close(context, normal_requested)
    if normal_requested and self:bound() then
        return self:send(context, STATE_CLOSED, 0)
    end
end

return director
