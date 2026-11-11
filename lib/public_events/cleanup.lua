-- Final cleanup request ownership survives gameplay release; state stays in the host scope.
local cleanup = {}
local Cleanup = {}
Cleanup.__index = Cleanup

-- Retained operation keys: count, terminal failure, request ordinal and consumed retry.
local COUNT, FAILED, REQUEST, RETRIED = ".n", ".f", ".q", ".r"
local UNCLEAN = ".unclean" -- Unconfirmed cleanup retained until the next attempt starts.
-- 24 held ticks exceed kIntentLifetimeMs (60 s); reattach resets it; staged outputs serialize.
local MAX_HELD_TICKS = 24

---@class CleanupOperation
---@field send fun(context, scope): table|nil Queues final-state setters and returns their requests.
---@field retry boolean Whether the operation is safe to repeat once after a terminal failure.
---@field blocking boolean|nil False when an unresolved operation must not delay site rotation.

--- Binds a fixed list of final-state operations; no callback context is retained.
---@param key string Cleanup prefix within the event's host scope.
---@param operations CleanupOperation[] Ordered operations; never animation or reward sequences.
---@return table cleanup Retained request ownership and bounded retry handling.
function cleanup.new(key, operations)
    return setmetatable({key = key, operations = operations}, Cleanup)
end

--- Clears one operation's request identities and retry state, preserving the site warning.
local function clear_operation(scope, key)
    for ordinal = 1, scope:variable(key .. COUNT) or 0 do
        scope:clear_variable(key .. REQUEST .. ordinal)
    end
    for _, suffix in ipairs({COUNT, FAILED, RETRIED}) do scope:clear_variable(key .. suffix) end
end

--- True while an operation still owns at least one unresolved request.
local function pending(scope, key)
    for ordinal = 1, scope:variable(key .. COUNT) or 0 do
        if scope:variable(key .. REQUEST .. ordinal) ~= nil then return true end
    end
    return false
end

--- Queues one operation and retains every resulting request until its terminal outcome.
---@param context table Borrowed callback context.
---@param scope table Host scope owning the request identities.
---@param index integer Index of the bound cleanup operation.
function Cleanup:send(context, scope, index)
    local key = self.key .. index
    local requests = self.operations[index].send(context, scope) or {}
    for ordinal = #requests + 1, scope:variable(key .. COUNT) or 0 do
        scope:clear_variable(key .. REQUEST .. ordinal)
    end
    scope:set_variable(key .. COUNT, #requests)
    scope:clear_variable(key .. FAILED)
    for ordinal, request in ipairs(requests) do
        scope:set_variable(key .. REQUEST .. ordinal, request.value)
    end
end

--- Starts final cleanup once per event attempt; duplicate cleanup calls issue nothing.
---@param context table Borrowed callback context.
---@param scope table Host scope retaining the attempt's cleanup state.
function Cleanup:start(context, scope)
    if scope:variable(self.key) == true then return end
    scope:set_variable(self.key, true)
    for index = 1, #self.operations do self:send(context, scope, index) end
end

--- Releases expired bookkeeping with a warning; only unresolved blocking operations delay reuse.
---@param scope table Host scope owning the cleanup state.
---@param held_ticks integer|nil Held service ticks since cleanup began waiting; zero for queries.
---@return boolean blocked Whether a new event must wait.
function Cleanup:blocked(scope, held_ticks)
    local blocked = false
    for index, operation in ipairs(self.operations) do
        local key = self.key .. index
        local outstanding = pending(scope, key)
        if (outstanding and (held_ticks or 0) >= MAX_HELD_TICKS)
            or (not outstanding and scope:variable(key .. FAILED) == true) then
            scope:set_variable(self.key .. UNCLEAN, true)
            clear_operation(scope, key)
        elseif outstanding and operation.blocking ~= false then
            blocked = true
        end
    end
    return blocked
end

--- Starts fresh bookkeeping; forced resets preserve an unclean warning instead of faulting.
---@param scope table Host scope owning the cleanup state.
function Cleanup:reset(scope)
    scope:clear_variable(self.key .. UNCLEAN)
    scope:clear_variable(self.key)
    for index = 1, #self.operations do
        local key = self.key .. index
        if pending(scope, key) or scope:variable(key .. FAILED) == true then
            scope:set_variable(self.key .. UNCLEAN, true)
        end
        clear_operation(scope, key)
    end
end

--- Handles only retained terminal results; staging confirms output queueing, not client receipt.
---@param context table Borrowed callback context used only for a permitted retry.
---@param scope table Host scope retaining requests across release and reload.
---@param report table Outcome whose request identity must match this cleanup.
---@return boolean|nil retried True when a new intent needs a fresh held-time allowance.
function Cleanup:on_effect(context, scope, report)
    local outcome = report.outcome
    if report.request_key == nil or (outcome ~= "transport_staged" and outcome ~= "refused"
        and outcome ~= "expired" and outcome ~= "canceled") then return end
    for index, operation in ipairs(self.operations) do
        local key = self.key .. index
        local count = scope:variable(key .. COUNT) or 0
        for ordinal = 1, count do
            local request_key = key .. REQUEST .. ordinal
            if scope:variable(request_key) == report.request_key.value then
                scope:clear_variable(request_key)
                if outcome ~= "transport_staged" then scope:set_variable(key .. FAILED, true) end
                if pending(scope, key) then return end
                if scope:variable(key .. FAILED) == true then
                    if operation.retry and scope:variable(key .. RETRIED) ~= true then
                        scope:set_variable(key .. RETRIED, true)
                        self:send(context, scope, index)
                        return true
                    else
                        scope:set_variable(self.key .. UNCLEAN, true)
                        clear_operation(scope, key)
                    end
                end
                return
            end
        end
    end
end

return cleanup
