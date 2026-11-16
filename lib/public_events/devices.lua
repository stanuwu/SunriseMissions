-- Shared device-channel operations for public events; retained values stay in the host scope.
local devices = {}

-- Each cached position retains the request that last selected it.
local REQUEST_SUFFIX = ".r"

--- Queues a changed position; the cached value records intent, not client acknowledgement.
---@param context table Borrowed callback context.
---@param scope table Host scope retaining the value and request identity.
---@param device string Device slot identifier.
---@param key string Unique position key in this scope.
---@param value number Position control value.
---@param snap boolean|nil Whether to snap to the requested position.
function devices.set_position(context, scope, device, key, value, snap)
    if scope:variable(key) == value then return end
    local request = context:slot(device):set_channel{
        channel = context.sdk.device_channels.position,
        value = context.sdk.unit(value),
        snap = snap == true,
    }
    devices.retain(scope, key, value, request)
end

--- Retains an output intent and its request under the same failure-invalidation contract.
---@param scope table Host scope owning this intent.
---@param key string Key shared with the event's device_keys list.
---@param value boolean|number Desired value, not acknowledgement.
---@param request userdata Queued request identity.
function devices.retain(scope, key, value, request)
    scope:set_variable(key, value)
    scope:set_variable(key .. REQUEST_SUFFIX, request.value)
end

--- Forgets position intents and their requests before a new event attempt.
---@param scope table Host scope owning the cached values.
---@param keys string[] Position keys owned by this event.
function devices.reset(scope, keys)
    for _, key in ipairs(keys) do
        scope:clear_variable(key)
        scope:clear_variable(key .. REQUEST_SUFFIX)
    end
end

--- Invalidates a failed current intent so the next explicit position call can retry it.
---@param scope table Host scope owning the cached values.
---@param keys string[] Position keys owned by this event.
---@param report table Delivery outcome; older requests cannot invalidate newer intents.
function devices.on_effect(scope, keys, report)
    if report.request_key == nil then return end
    local outcome = report.outcome
    if outcome ~= "refused" and outcome ~= "expired" and outcome ~= "canceled" then return end
    for _, key in ipairs(keys) do
        local request_key = key .. REQUEST_SUFFIX
        if scope:variable(request_key) == report.request_key.value then
            scope:clear_variable(key)
            scope:clear_variable(request_key)
            return
        end
    end
end

return devices
