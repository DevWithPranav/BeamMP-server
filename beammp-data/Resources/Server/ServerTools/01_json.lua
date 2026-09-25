-- Minimal JSON encoder. Only needs to handle the plain Lua tables/strings/
-- numbers/booleans this plugin builds itself (Discord payloads, dashboard
-- state) -- no decoder, no metatables, no cycle detection needed for that.

local function st_json_escape_string(s)
  s = s:gsub('[%c\\"]', function(c)
    if c == '\\' then return '\\\\' end
    if c == '"' then return '\\"' end
    if c == '\n' then return '\\n' end
    if c == '\r' then return '\\r' end
    if c == '\t' then return '\\t' end
    return string.format('\\u%04x', string.byte(c))
  end)
  return s
end

function ST_JsonEncode(value)
  local t = type(value)

  if value == nil then
    return "null"
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "0"
    end
    return tostring(value)
  elseif t == "string" then
    return '"' .. st_json_escape_string(value) .. '"'
  elseif t == "table" then
    local n = 0
    local isArray = true
    for k in pairs(value) do
      n = n + 1
      if type(k) ~= "number" then
        isArray = false
      end
    end

    if n == 0 then
      return "{}"
    end

    if isArray then
      for i = 1, n do
        if value[i] == nil then
          isArray = false
          break
        end
      end
    end

    local parts = {}
    if isArray then
      for i = 1, n do
        parts[#parts + 1] = ST_JsonEncode(value[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end

    for k, v in pairs(value) do
      parts[#parts + 1] = ST_JsonEncode(tostring(k)) .. ":" .. ST_JsonEncode(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end

  return "null"
end
