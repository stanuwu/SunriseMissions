-- Fixed-schema mission records fit one bounded Host variable and preserve integer identity.
local record = {}

-- ASCII hex keeps persisted records valid in the existing text UI and JSON captures.
local function hex_digit(byte)
    if byte >= 48 and byte <= 57 then return byte - 48 end
    if byte >= 97 and byte <= 102 then return byte - 87 end
    error("invalid mission record encoding")
end

function record.schema(signature, fields)
    assert(type(signature) == "string" and #signature == 2)
    local indexes = {}
    for index, field in ipairs(fields) do
        assert(type(field.name) == "string" and not indexes[field.name])
        assert(field.kind == "boolean" or field.kind == "integer" or field.kind == "string")
        if field.kind == "string" then
            assert(math.type(field.limit) == "integer" and field.limit > 0 and field.limit <= 127)
        end
        indexes[field.name] = index
    end
    return {signature=signature, fields=fields, indexes=indexes}
end

function record.read(state, key, schema)
    local bytes = state:variable(key)
    if bytes == nil then return {} end
    assert(type(bytes) == "string" and #bytes <= 127
        and string.sub(bytes, 1, 2) == schema.signature, "mission record schema mismatch")
    assert((#bytes - 2) % 2 == 0, "truncated mission record encoding")
    local decoded = schema.signature
    for cursor = 3, #bytes, 2 do
        decoded = decoded .. string.char(hex_digit(string.byte(bytes, cursor)) * 16
            + hex_digit(string.byte(bytes, cursor + 1)))
    end
    bytes = decoded
    local values, cursor = {}, 3
    for _, field in ipairs(schema.fields) do
        local present
        present, cursor = string.unpack("B", bytes, cursor)
        assert(present == 0 or present == 1, "invalid mission record presence")
        if present == 1 then
            local value
            if field.kind == "boolean" then
                value, cursor = string.unpack("B", bytes, cursor)
                assert(value == 0 or value == 1, "invalid mission record boolean")
                value = value == 1
            elseif field.kind == "integer" then
                value, cursor = string.unpack("<i8", bytes, cursor)
            else
                value, cursor = string.unpack("s1", bytes, cursor)
                assert(#value <= field.limit, "mission record string exceeds schema")
            end
            values[field.name] = value
        end
    end
    assert(cursor == #bytes + 1, "mission record trailing bytes")
    return values
end

function record.write(context, key, schema, values)
    local bytes = schema.signature
    for _, field in ipairs(schema.fields) do
        local value = values[field.name]
        bytes = bytes .. string.pack("B", value == nil and 0 or 1)
        if value ~= nil then
            if field.kind == "boolean" then
                assert(type(value) == "boolean", "mission record expects boolean")
                bytes = bytes .. string.pack("B", value and 1 or 0)
            elseif field.kind == "integer" then
                assert(math.type(value) == "integer", "mission record expects exact integer")
                bytes = bytes .. string.pack("<i8", value)
            else
                assert(type(value) == "string" and #value <= field.limit,
                    "mission record string exceeds schema")
                bytes = bytes .. string.pack("s1", value)
            end
        end
    end
    local encoded = schema.signature
    for cursor = 3, #bytes do
        encoded = encoded .. string.format("%02x", string.byte(bytes, cursor))
    end
    assert(#encoded <= 127, "mission record exceeds Host capacity")
    context:set_variable(key, encoded)
end

function record.get(state, key, schema, name)
    assert(schema.indexes[name], "unknown mission record field")
    return record.read(state, key, schema)[name]
end

function record.set(context, state, key, schema, name, value)
    assert(schema.indexes[name], "unknown mission record field")
    local values = record.read(state, key, schema)
    values[name] = value
    record.write(context, key, schema, values)
end

return record
