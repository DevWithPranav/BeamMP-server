-- ServerTools: admin chat commands, persistent bans, welcome message and a
-- periodic "[stats]" log line (consumed by scripts/stats-reporter.sh).
--
-- Config via env (see docker-compose.yml):
--   BEAMMP_ADMINS          comma-separated BeamMP account names
--   BEAMMP_WELCOME         message sent to each player on join
--   BEAMMP_STATS_INTERVAL  seconds between stats lines (0 disables)

local BAN_FILE = "Resources/Server/ServerTools/bans.json"

local admins = {}
for name in (os.getenv("BEAMMP_ADMINS") or ""):gmatch("[^,%s]+") do
  admins[name:lower()] = true
end
local welcome = os.getenv("BEAMMP_WELCOME") or ""
local statsInterval = tonumber(os.getenv("BEAMMP_STATS_INTERVAL") or "60") or 60

local bans = {}

local function loadBans()
  local f = io.open(BAN_FILE, "r")
  if not f then return end
  local ok, data = pcall(Util.JsonDecode, f:read("*a"))
  f:close()
  if ok and type(data) == "table" then bans = data end
end

local function saveBans()
  local f = io.open(BAN_FILE, "w")
  if not f then
    print("[ServerTools] could not write " .. BAN_FILE)
    return
  end
  f:write(Util.JsonEncode(bans))
  f:close()
end

local function isAdmin(pid)
  if MP.IsPlayerGuest(pid) then return false end
  return admins[(MP.GetPlayerName(pid) or ""):lower()] == true
end

local function reply(pid, msg)
  MP.SendChatMessage(pid, msg)
end

local function findPlayer(query)
  query = (query or ""):lower()
  if query == "" then return nil end
  local match
  for pid, name in pairs(MP.GetPlayers() or {}) do
    local lname = name:lower()
    if lname == query then return pid, name end
    if lname:find(query, 1, true) then
      if match then return nil end -- ambiguous
      match = { pid, name }
    end
  end
  if match then return match[1], match[2] end
  return nil
end

local function countVehicles()
  local total = 0
  for pid in pairs(MP.GetPlayers() or {}) do
    for _ in pairs(MP.GetPlayerVehicles(pid) or {}) do total = total + 1 end
  end
  return total
end

local commands = {}

commands.help = function(pid)
  local msg = "Commands: /players"
  if isAdmin(pid) then msg = msg .. ", /kick <name> [reason], /ban <name> [reason], /unban <name>, /say <msg>" end
  reply(pid, msg)
end

commands.players = function(pid)
  local names = {}
  for _, name in pairs(MP.GetPlayers() or {}) do names[#names + 1] = name end
  table.sort(names)
  reply(pid, #names .. " online: " .. table.concat(names, ", "))
end

commands.kick = function(pid, target, reason, admin)
  if not admin then return reply(pid, "Admins only.") end
  local tpid, tname = findPlayer(target)
  if not tpid then return reply(pid, "No unique player matches '" .. (target or "") .. "'.") end
  MP.DropPlayer(tpid, reason ~= "" and reason or "Kicked by an admin")
  MP.SendChatMessage(-1, tname .. " was kicked.")
end

commands.ban = function(pid, target, reason, admin)
  if not admin then return reply(pid, "Admins only.") end
  local tpid, tname = findPlayer(target)
  if not tpid then return reply(pid, "No unique player matches '" .. (target or "") .. "'.") end
  bans[tname:lower()] = reason ~= "" and reason or "Banned by an admin"
  saveBans()
  MP.DropPlayer(tpid, bans[tname:lower()])
  MP.SendChatMessage(-1, tname .. " was banned.")
end

commands.unban = function(pid, target, _, admin)
  if not admin then return reply(pid, "Admins only.") end
  local key = (target or ""):lower()
  if bans[key] == nil then return reply(pid, "'" .. (target or "") .. "' is not banned.") end
  bans[key] = nil
  saveBans()
  reply(pid, target .. " unbanned.")
end

commands.say = function(pid, first, rest, admin)
  if not admin then return reply(pid, "Admins only.") end
  local text = (first or "") .. (rest ~= "" and (" " .. rest) or "")
  MP.SendChatMessage(-1, "[Server] " .. text)
end

function ST_onPlayerAuth(name, role, isGuest, identifiers)
  local reason = bans[(name or ""):lower()]
  if reason then return "Banned: " .. reason end
end

function ST_onPlayerJoin(pid)
  if welcome ~= "" then reply(pid, welcome) end
end

function ST_onChatMessage(pid, name, message)
  local cmd, target, rest = message:match("^/(%S+)%s*(%S*)%s*(.*)$")
  if not cmd then return end
  local handler = commands[cmd:lower()]
  if not handler then
    reply(pid, "Unknown command. Try /help.")
    return 1
  end
  local ok, err = pcall(handler, pid, target, rest, isAdmin(pid))
  if not ok then print("[ServerTools] /" .. cmd .. " failed: " .. tostring(err)) end
  return 1 -- keep commands out of public chat
end

function ST_stats()
  local players = 0
  for _ in pairs(MP.GetPlayers() or {}) do players = players + 1 end
  print(string.format("[stats] players=%d vehicles=%d", players, countVehicles()))
end

loadBans()
MP.RegisterEvent("onPlayerAuth", "ST_onPlayerAuth")
MP.RegisterEvent("onPlayerJoin", "ST_onPlayerJoin")
MP.RegisterEvent("onChatMessage", "ST_onChatMessage")
if statsInterval > 0 then
  MP.RegisterEvent("ST_stats", "ST_stats")
  MP.CreateEventTimer("ST_stats", statsInterval * 1000)
end
local adminCount = 0
for _ in pairs(admins) do adminCount = adminCount + 1 end
print("[ServerTools] loaded; " .. adminCount .. " admin(s) configured")
