-- Exact decimal identities without Lua patterns, which the mission sandbox disables.
local identity = {}
local max_unsigned = "18446744073709551615"
local max_transaction_length = 39 -- Two signed 64-bit positive integers and one colon.

function identity.positive_decimal(value)
    if type(value)~="string" or #value==0 or #value>#max_unsigned then return false end
    for index=1,#value do
        local byte=string.byte(value,index)
        if byte<48 or byte>57 or (index==1 and byte==48) then return false end
    end
    return #value<#max_unsigned or value<=max_unsigned
end

-- Return text components so consumers can retain their own exact integer/epoch checks.
function identity.transaction_parts(value)
    if type(value)~="string" or #value>max_transaction_length then return end
    local separator
    for index=1,#value do
        if string.byte(value,index)==58 then
            if separator then return end
            separator=index
        end
    end
    if not separator then return end
    local first,last=string.sub(value,1,separator-1),string.sub(value,separator+1)
    if not identity.positive_decimal(first) or not identity.positive_decimal(last) then return end
    return first,last
end

return identity
