--[[
    AutoPiano - auto.lua  (FILE NÀY ĐƯỢC SINH TỰ ĐỘNG từ auto.template.lua + engine.lua bằng build.py)
    Execute: loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/autopiano/main/auto.lua", true))()
]]

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local REPO_BASE = "https://raw.githubusercontent.com/Linh-1205/autopiano/main/"
local SHEET_HOST = "https://hellohellohell0.com/talentless-raw/SONGS/"
local CUSTOM_DIR = "AUTOPIANO_CUSTOM_SONGS"
local LEGACY_DIR = "TALENTLESS_CUSTOM_SONGS"

-- Thêm bài: url = tên file sheet (không đuôi) trên host SONGS
local SONG_LIST = {
    { url = "INTERSTELLAR", bpm = "104", cat = { "epic", "beautiful" } },
    -- { url = "TEN_FILE", bpm = "120", cat = { "pop" } },
}

----------------------------------------------------------------------
-- Dọn UI cũ nếu execute lại
----------------------------------------------------------------------
if _G.__AP_UI_DESTROY then pcall(_G.__AP_UI_DESTROY) end

----------------------------------------------------------------------
-- Notif (từ repo user, fallback print)
----------------------------------------------------------------------
local Notif
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet(REPO_BASE .. "notif_lib.lua", true))()
    end)
    if ok and type(res) == "table" and res.SendNotification then
        Notif = res
    else
        Notif = { SendNotification = function(_, t, m) print(t, m) end }
    end
    _G.AP_Notif = Notif
end

----------------------------------------------------------------------
-- Engine embed
----------------------------------------------------------------------
_G.__AP_ENGINE_SRC = [=[
--[[
    AutoPiano engine (self-contained, no external HttpGet)

    Cách hoạt động:
      1. Sheet chạy 1 lần (khung "record"): keypress/rest chỉ GHI lại timeline, không chờ.
      2. finishedSong() (hoặc __AP_start) chuyển sang "play": engine phát timeline theo thời gian thực.
      => Pause / Stop / Seek tới-lui đều chính xác, kể cả tua lùi.

    Globals (sheet dùng): x, bpm, errormargin, pausing, _G.STOPIT, _G.songisplaying, _G.SEEK_SECONDS
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)

-- dừng engine cũ (nếu chạy lại) trước khi set globals
if _G.__AP_ENGINE_STOP then pcall(_G.__AP_ENGINE_STOP) end

_G.STOPIT = false
_G.songisplaying = true
_G.SEEK_SECONDS = 0
_G.AP_END = nil
x = "hi" -- short-note convention
bpm = bpm or 120
errormargin = errormargin or 0
pausing = false

local KC = Enum.KeyCode

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local S = {
    events = {},      -- { t=seconds, keys=string, hold=number|nil } | { t=, pedal=true/false }
    cursor = 0,       -- thời gian (giây) trong lúc record
    phase = "record", -- record -> play -> live
    started = false,
    stopped = false,
    finished = false,
    pos = 0,
    total = 0,
    held = {},        -- [KeyCode] = token
    token = 0,
    shiftCount = 0,
    conns = {},
    gui = nil,
}

local function notify(title, text, dur)
    local n = _G.AP_Notif
    if n and n.SendNotification then
        local ok = pcall(function() n:SendNotification(title, text, dur or 3) end)
        if ok then return end
    end
    print("[AutoPiano]", title, text)
end

local function getBpm(b)
    local v = tonumber(b) or tonumber(bpm) or 120
    if v <= 0 then v = 120 end
    return v
end

----------------------------------------------------------------------
-- Key map: Virtual Piano (QWERTY)
--   1234567890 qwertyuiop asdfghjkl zxcvbnm  = 36 phím trắng (C2..C7)
--   Shift + phím trắng = nốt thăng; chữ hoa / !@#$%^&*() = có Shift
----------------------------------------------------------------------
local WHITE = "1234567890qwertyuiopasdfghjklzxcvbnm"
local digitNames = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero" }
local shiftSyms = "!@#$%^&*()"
local keyMap = {}

for i = 1, 10 do
    keyMap[tostring(i % 10)] = { KC[digitNames[i]], false }
    keyMap[shiftSyms:sub(i, i)] = { KC[digitNames[i]], true }
end
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
    keyMap[c] = { KC[c:upper()], false }
    keyMap[c:upper()] = { KC[c:upper()], true }
end
keyMap[" "] = { KC.Space, false }

local function parseKeys(keys)
    keys = tostring(keys or "")
    local ctrl = false
    if keys:lower():sub(1, 5) == "ctrl+" then
        ctrl = true
        keys = keys:sub(6)
    end
    local list = {}
    for i = 1, #keys do
        local e = keyMap[keys:sub(i, i)]
        if e then list[#list + 1] = { kc = e[1], shift = e[2] } end
    end
    return list, ctrl
end

local function sendKey(kc, down)
    if not VIM then return end
    pcall(function() VIM:SendKeyEvent(down, kc, false, game) end)
end

local function shiftAcquire()
    S.shiftCount = S.shiftCount + 1
    if S.shiftCount == 1 then sendKey(KC.LeftShift, true) end
end
local function shiftRelease()
    if S.shiftCount <= 0 then return end
    S.shiftCount = S.shiftCount - 1
    if S.shiftCount == 0 then sendKey(KC.LeftShift, false) end
end

local function pressDown(kc)
    if S.held[kc] then sendKey(kc, false) end -- nhấn lại cùng phím: nhả trước
    S.token = S.token + 1
    local tk = S.token
    S.held[kc] = tk
    sendKey(kc, true)
    return tk
end
local function pressUp(kc, tk)
    if S.held[kc] == tk then
        S.held[kc] = nil
        sendKey(kc, false)
    end
end

local function releaseAll()
    for kc in pairs(S.held) do sendKey(kc, false) end
    S.held = {}
    S.shiftCount = 0
    sendKey(KC.LeftShift, false)
    sendKey(KC.LeftControl, false)
    sendKey(KC.Space, false)
end

-- Gõ 1..n phím cùng lúc (chord), async để không block
local function pressChord(keys, hold)
    local list, ctrl = parseKeys(keys)
    if #list == 0 then return end
    hold = hold or (math.random(50, 120) / 1000)
    task.spawn(function()
        local downs = {}
        if ctrl then sendKey(KC.LeftControl, true) end
        for _, e in ipairs(list) do
            if not e.shift then downs[#downs + 1] = { e.kc, pressDown(e.kc) } end
        end
        local needShift = false
        for _, e in ipairs(list) do
            if e.shift then
                needShift = true
                break
            end
        end
        local used = 0
        if needShift then
            shiftAcquire()
            for _, e in ipairs(list) do
                if e.shift then downs[#downs + 1] = { e.kc, pressDown(e.kc) } end
            end
            local t0 = os.clock()
            task.wait() -- giữ Shift đúng 1 frame, đủ để game đọc trạng thái lúc keydown
            used = os.clock() - t0
            shiftRelease()
        end
        if hold > used then task.wait(hold - used) end
        for _, d in ipairs(downs) do pressUp(d[1], d[2]) end
        if ctrl then sendKey(KC.LeftControl, false) end
    end)
end

----------------------------------------------------------------------
-- Control panel
----------------------------------------------------------------------
local ACCENT = Color3.fromRGB(255, 182, 208)
local BG = Color3.fromRGB(20, 20, 28)
local BTN = Color3.fromRGB(38, 38, 52)

local function destroyPanel()
    for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
    S.conns = {}
    if S.gui then
        pcall(function() S.gui:Destroy() end)
        S.gui = nil
    end
    S.timeLabel = nil
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function newObj(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function buildPanel()
    local gui = Instance.new("ScreenGui")
    gui.Name = "APControls"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end
    S.gui = gui

    local frame = newObj("Frame", {
        Name = "Panel",
        Size = UDim2.new(0, 260, 0, 96),
        Position = UDim2.new(0.5, -130, 0, 24),
        BackgroundColor3 = BG,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    newObj("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
    newObj("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.5 }, frame)

    newObj("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(0.5, 0, 0, 22),
        Text = "AutoPiano",
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = ACCENT,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    S.timeLabel = newObj("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0.5, 0, 0, 8),
        Size = UDim2.new(0.5, -12, 0, 22),
        Text = "0:00 / " .. fmtTime(S.total),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = Color3.fromRGB(200, 200, 215),
        TextXAlignment = Enum.TextXAlignment.Right,
    }, frame)

    local function button(text, i, cb)
        local b = newObj("TextButton", {
            Position = UDim2.new(0, 9 + (i - 1) * 62, 0, 52),
            Size = UDim2.new(0, 56, 0, 32),
            BackgroundColor3 = BTN,
            BorderSizePixel = 0,
            Text = text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = Color3.fromRGB(235, 235, 245),
            AutoButtonColor = true,
        }, frame)
        newObj("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
        table.insert(S.conns, b.Activated:Connect(cb))
        return b
    end

    local pauseBtn
    pauseBtn = button("Pause", 1, function()
        pausing = not pausing
        pauseBtn.Text = pausing and "Resume" or "Pause"
    end)
    button("Stop", 2, function() _G.stopPlayingSongs() end)
    button("<< 5s", 3, function() _G.SEEK_SECONDS = -5 end)
    button(">> 5s", 4, function() _G.SEEK_SECONDS = 5 end)

    -- kéo thả
    local dragging, dragStart, startPos = false, nil, nil
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    table.insert(S.conns, frame.InputBegan:Connect(function(input)
        if isPointer(input) then
            dragging, dragStart, startPos = true, input.Position, frame.Position
        end
    end))
    table.insert(S.conns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    table.insert(S.conns, UserInputService.InputEnded:Connect(function(input)
        if isPointer(input) then dragging = false end
    end))
end

----------------------------------------------------------------------
-- Kết thúc / dừng
----------------------------------------------------------------------
local function finish()
    if S.finished then return end
    S.finished = true
    S.stopped = true
    releaseAll()
    _G.STOPIT = true
    _G.songisplaying = false
    _G.AP_END = "finished"
    destroyPanel()
    notify("Success", "Song finished", 3)
    print("[AutoPiano] Song finished")
end

function stopPlayingSongs()
    if S.finished then return end
    S.finished = true
    S.stopped = true
    releaseAll()
    _G.STOPIT = true
    _G.songisplaying = false
    _G.AP_END = "stopped"
    destroyPanel()
    notify("Info", "Playback stopped", 2)
    print("[AutoPiano] Stopped")
end
_G.stopPlayingSongs = stopPlayingSongs

-- engine cũ bị thay thế: dừng im lặng
_G.__AP_ENGINE_STOP = function()
    S.finished = true
    S.stopped = true
    releaseAll()
    destroyPanel()
end

----------------------------------------------------------------------
-- Player (phát timeline)
----------------------------------------------------------------------
local function startPlayback()
    if S.started then return end
    S.started = true
    S.phase = "play"

    local ev = S.events
    local n = #ev
    local total = S.cursor
    for i = 1, n do
        local e = ev[i]
        local e_end = e.t + (e.hold or 0.1)
        if e_end > total then total = e_end end
    end
    S.total = total
    print(string.format("[AutoPiano] Engine ready: %d events, %.1fs", n, total))

    if n == 0 then
        finish()
        return
    end

    local okp, errp = pcall(buildPanel)
    if not okp then
        warn("[AutoPiano] Control panel failed: " .. tostring(errp))
    end

    task.spawn(function()
        local idx = 1
        local last = os.clock()
        local lastLabel = 0
        while not S.stopped do
            local now = os.clock()
            local dt = now - last
            last = now
            if dt > 0.5 then dt = 0.5 end

            local sk = tonumber(_G.SEEK_SECONDS) or 0
            if sk ~= 0 then
                _G.SEEK_SECONDS = 0
                S.pos = math.min(math.max(0, S.pos + sk), S.total)
                idx = 1
                while idx <= n and ev[idx].t < S.pos do idx = idx + 1 end
                releaseAll()
            end

            if not pausing then S.pos = S.pos + dt end

            while idx <= n and ev[idx].t <= S.pos do
                local e = ev[idx]
                if e.pedal ~= nil then
                    sendKey(KC.Space, e.pedal)
                else
                    pressChord(e.keys, e.hold)
                end
                idx = idx + 1
            end

            if S.timeLabel and now - lastLabel > 0.2 then
                lastLabel = now
                pcall(function()
                    S.timeLabel.Text = fmtTime(math.min(S.pos, S.total)) .. " / " .. fmtTime(S.total)
                end)
            end

            if idx > n and S.pos >= S.total then
                finish()
                break
            end
            task.wait()
        end
    end)
end
_G.__AP_start = startPlayback

----------------------------------------------------------------------
-- Public API (sheet gọi được)
----------------------------------------------------------------------
function keypress(keys, beats, b)
    local bp = getBpm(b)
    local hold
    if type(beats) == "number" then hold = math.max(beats / bp * 60, 0.05) end
    if S.phase == "record" then
        S.events[#S.events + 1] = { t = S.cursor, keys = tostring(keys), hold = hold }
    else
        pressChord(keys, hold)
    end
end

function rest(beats, b)
    local secs = (tonumber(beats) or 0) / getBpm(b) * 60
    if S.phase == "record" then
        S.cursor = S.cursor + secs
        return
    end
    -- live: chờ thật, tôn trọng pause + seek
    local remaining = secs
    local last = os.clock()
    while remaining > 0 and not S.stopped do
        local now = os.clock()
        local dt = now - last
        last = now
        local sk = tonumber(_G.SEEK_SECONDS) or 0
        if sk > 0 then
            remaining = remaining - sk
            _G.SEEK_SECONDS = 0
        elseif sk < 0 then
            _G.SEEK_SECONDS = 0
        end
        if not pausing then remaining = remaining - dt end
        if remaining > 0 then task.wait() end
    end
end

function finishedSong()
    if S.phase == "record" then
        startPlayback()
    else
        finish()
    end
end

function pedalDown()
    if S.phase == "record" then
        S.events[#S.events + 1] = { t = S.cursor, pedal = true }
    else
        sendKey(KC.Space, true)
    end
end

function pedalUp()
    if S.phase == "record" then
        S.events[#S.events + 1] = { t = S.cursor, pedal = false }
    else
        sendKey(KC.Space, false)
    end
end

function adjustVelocity(vel) end -- no-op

-- midi (C4 = 60) -> ký tự Virtual Piano; nil nếu ngoài C2..C7
local WHITE_DEGREE = { [0] = 0, [2] = 1, [4] = 2, [5] = 3, [7] = 4, [9] = 5, [11] = 6 }
local function midiToKey(m)
    if m < 36 or m > 96 then return nil end
    local oct = math.floor(m / 12) - 1
    local pc = m % 12
    local sharp = false
    if WHITE_DEGREE[pc] == nil then
        pc = pc - 1
        sharp = true
    end
    local idx = (oct - 2) * 7 + WHITE_DEGREE[pc] + 1
    local ch = WHITE:sub(idx, idx)
    if ch == "" then return nil end
    if sharp then
        local d = tonumber(ch)
        if d then
            ch = shiftSyms:sub((d == 0) and 10 or d, (d == 0) and 10 or d)
        else
            ch = ch:upper()
        end
    end
    return ch
end

function pressnote(note, octave, beats, b)
    local letter, acc = tostring(note):match("^%s*([A-Ga-g])([#bB]?)")
    if not letter then return end
    local semi = ({ C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 })[letter:upper()]
    if acc == "#" then
        semi = semi + 1
    elseif acc == "b" or acc == "B" then
        semi = semi - 1
    end
    local m = (tonumber(octave) or 4) * 12 + 12 + semi
    local ch = midiToKey(m)
    if ch then keypress(ch, beats, b) end
end

function keysequence16(keys, beats, b)
    keys = tostring(keys)
    for i = 1, #keys do
        keypress(keys:sub(i, i), beats, b)
        rest(0.25, b)
    end
end

function stopPlayingSongsGlobal() stopPlayingSongs() end
]=]

----------------------------------------------------------------------
-- Services / theme
----------------------------------------------------------------------
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local C = {
    bg = Color3.fromRGB(18, 18, 24),
    panel = Color3.fromRGB(28, 28, 38),
    item = Color3.fromRGB(36, 36, 50),
    text = Color3.fromRGB(235, 235, 245),
    muted = Color3.fromRGB(150, 150, 172),
    accent = Color3.fromRGB(255, 182, 208),
    accentText = Color3.fromRGB(40, 24, 32),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end

local function notify(kind, msg, dur) Notif:SendNotification(kind, msg, dur or 3) end

----------------------------------------------------------------------
-- Song model
----------------------------------------------------------------------
local songs = {}
local songisplaying = false
local shuffleOn = false
local selectedCat = "All"
local alive = true

local gui, listFrame, searchBox, catBar, nameLabel, bpmbox
local refreshList, buildCats, selectSong, disable

local function prettyName(url) return (tostring(url):gsub("_", " ")) end

local function addSong(s)
    s.name = s.name or prettyName(s.url)
    s.var = false
    s.bpm = s.bpm or "120"
    s.cat = s.cat or {}
    songs[#songs + 1] = s
    return s
end

local function loadBuiltinSongs()
    for _, d in ipairs(SONG_LIST) do
        addSong({ url = d.url, bpm = d.bpm, cat = d.cat })
    end
end

-- Custom songs từ folder executor
local function hasFS()
    return type(isfolder) == "function" and type(listfiles) == "function" and type(readfile) == "function"
end

local function readCategoriesFile(dir)
    local map = {}
    local path = dir .. "/_categories.txt"
    if type(isfile) == "function" and isfile(path) then
        local ok, content = pcall(readfile, path)
        if ok and content then
            for line in tostring(content):gmatch("[^\r\n]+") do
                local name, cats = line:match("^(.-)|(.*)$")
                if name then
                    local list = {}
                    for c in cats:gmatch("[^,]+") do list[#list + 1] = (c:gsub("^%s+", ""):gsub("%s+$", "")) end
                    map[name] = list
                end
            end
        end
    end
    return map
end

local function loadCustomSongs()
    if not hasFS() then return end
    for _, dir in ipairs({ CUSTOM_DIR, LEGACY_DIR }) do
        local okd, isdir = pcall(isfolder, dir)
        if okd and isdir then
            local catMap = readCategoriesFile(dir)
            local okl, files = pcall(listfiles, dir)
            if okl and type(files) == "table" then
                for _, path in ipairs(files) do
                    local name = tostring(path):match("([^/\\]+)%.txt$")
                    if name and name ~= "_categories" then
                        local ok, content = pcall(readfile, path)
                        if ok and type(content) == "string" then
                            local cats = catMap[name] or {}
                            local bpmHeader
                            for line in content:gmatch("[^\r\n]+") do
                                local cat = line:match("^%-%-CAT:(.+)$")
                                if cat then
                                    cats = {}
                                    for c in cat:gmatch("[^,]+") do
                                        cats[#cats + 1] = (c:gsub("^%s+", ""):gsub("%s+$", ""))
                                    end
                                end
                                local b = line:match("^%-%-BPM:%s*(%d+)")
                                if b then bpmHeader = b end
                                if not line:match("^%-%-") then break end
                            end
                            local tags = { "custom" }
                            for _, c in ipairs(cats) do tags[#tags + 1] = c end
                            addSong({ name = name, url = name, path = path, custom = true,
                                bpm = bpmHeader or "120", cat = tags })
                        end
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Play flow
----------------------------------------------------------------------
local function resetPlaying()
    songisplaying = false
end

local function playbuttonclicked()
    -- 1) đang phát?
    if songisplaying or (_G.songisplaying == true and _G.STOPIT ~= true) then
        notify("Error", "A song is already playing", 3)
        return
    end

    -- 2) BPM
    bpm = tonumber(bpmbox.Text)
    if not bpm or bpm <= 0 then
        notify("Error", "Invalid BPM", 3)
        return
    end
    _G.bpm = bpm

    -- 3) bài đã chọn
    local selected
    for _, s in ipairs(songs) do
        if s.var == true then selected = s break end
    end
    if not selected then
        notify("Error", "Select a song first", 3)
        return
    end

    -- 4) fetch sheet TRƯỚC (host SONGS; custom thì đọc file)
    local ok, songscript
    if selected.custom then
        ok, songscript = pcall(readfile, selected.path)
    else
        ok, songscript = pcall(function() return game:HttpGet(SHEET_HOST .. selected.url, true) end)
    end
    if not ok or type(songscript) ~= "string" or #songscript <= 10 then
        notify("Error", "Song data not found", 3)
        return
    end

    -- 5) cờ + engine
    songisplaying = true
    _G.songisplaying = true
    _G.STOPIT = false

    local engineOk = pcall(function() loadstring(_G.__AP_ENGINE_SRC)() end)
    if not engineOk then
        engineOk = pcall(function()
            loadstring(game:HttpGet(REPO_BASE .. "engine.lua", true))()
        end)
    end
    if not engineOk then
        notify("Error", "Engine failed to load", 4)
        resetPlaying()
        _G.songisplaying = false
        _G.STOPIT = true
        return
    end

    -- 6) chạy sheet (keypress/rest/finishedSong dùng global của engine)
    print("[AutoPiano] Playing: " .. selected.name .. " | sheet length: " .. #songscript .. " | BPM: " .. bpm)
    local fn = loadstring(songscript)
    local runOk, runErr
    if fn then
        runOk, runErr = pcall(fn)
    else
        runOk, runErr = false, "invalid sheet"
    end
    if not runOk then
        warn("[AutoPiano] Sheet error: " .. tostring(runErr))
        notify("Error", "Song data is invalid", 4)
        if _G.stopPlayingSongs then pcall(_G.stopPlayingSongs) end
        resetPlaying()
        return
    end
    -- sheet thiếu finishedSong() vẫn phát được
    if _G.__AP_start then pcall(_G.__AP_start) end
end

----------------------------------------------------------------------
-- Shuffle / loop
----------------------------------------------------------------------
local function playRandom()
    local pool = {}
    for _, s in ipairs(songs) do
        if s.button and s.button.Visible then pool[#pool + 1] = s end
    end
    if #pool == 0 then
        shuffleOn = false
        notify("Error", "No songs to shuffle", 3)
        return
    end
    selectSong(pool[math.random(1, #pool)])
    playbuttonclicked()
end

local function stopLoop()
    shuffleOn = false
    if _G.songisplaying == true and _G.STOPIT ~= true and _G.stopPlayingSongs then
        pcall(_G.stopPlayingSongs)
    end
end

task.spawn(function()
    while alive do
        task.wait(0.4)
        if songisplaying and (_G.songisplaying ~= true or _G.STOPIT == true) then
            resetPlaying()
            if shuffleOn and _G.AP_END == "finished" then
                task.wait(1)
                if shuffleOn and alive then playRandom() end
            end
        end
    end
end)

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local function paintButton(s)
    if not s.button then return end
    s.button.BackgroundColor3 = s.var and C.accent or C.item
    local nm = s.button:FindFirstChild("Name")
    if nm then nm.TextColor3 = s.var and C.accentText or C.text end
    local tg = s.button:FindFirstChild("Tags")
    if tg then tg.TextColor3 = s.var and C.accentText or C.muted end
end

disable = function()
    for _, s in ipairs(songs) do
        s.var = false
        paintButton(s)
    end
end

selectSong = function(s)
    disable()
    s.var = true
    paintButton(s)
    nameLabel.Text = s.name
    bpmbox.Text = tostring(s.bpm)
end

local function matches(s, query)
    if selectedCat ~= "All" then
        local found = false
        for _, c in ipairs(s.cat) do
            if c:lower() == selectedCat:lower() then found = true break end
        end
        if not found then return false end
    end
    if query == "" then return true end
    if s.name:lower():find(query, 1, true) then return true end
    for _, c in ipairs(s.cat) do
        if c:lower():find(query, 1, true) then return true end
    end
    return false
end

refreshList = function()
    local q = (searchBox and searchBox.Text or ""):lower()
    for _, s in ipairs(songs) do
        if s.button then s.button.Visible = matches(s, q) end
    end
end

local function makeSongButton(s)
    local b = new("TextButton", {
        Size = UDim2.new(1, -6, 0, 32),
        BackgroundColor3 = C.item,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = true,
    }, listFrame)
    corner(b, 6)
    new("TextLabel", {
        Name = "Name",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(0.6, -10, 1, 0),
        Text = s.name,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, b)
    new("TextLabel", {
        Name = "Tags",
        BackgroundTransparency = 1,
        Position = UDim2.new(0.6, 0, 0, 0),
        Size = UDim2.new(0.4, -10, 1, 0),
        Text = table.concat(s.cat, ", "),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = C.muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, b)
    s.button = b
    b.Activated:Connect(function() selectSong(s) end)
end

buildCats = function()
    for _, ch in ipairs(catBar:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    local set, list = {}, {}
    for _, s in ipairs(songs) do
        for _, c in ipairs(s.cat) do
            local k = c:lower()
            if not set[k] then set[k] = true; list[#list + 1] = k end
        end
    end
    table.sort(list)
    table.insert(list, 1, "All")
    for _, name in ipairs(list) do
        local active = (name:lower() == selectedCat:lower())
        local chip = new("TextButton", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = active and C.accent or C.item,
            BorderSizePixel = 0,
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextColor3 = active and C.accentText or C.text,
        }, catBar)
        corner(chip, 6)
        new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
        chip.Activated:Connect(function()
            selectedCat = name
            buildCats()
            refreshList()
        end)
    end
end

local function rebuildAll()
    for _, s in ipairs(songs) do
        if s.button then s.button:Destroy() end
    end
    songs = {}
    loadBuiltinSongs()
    loadCustomSongs()
    for _, s in ipairs(songs) do makeSongButton(s) end
    buildCats()
    refreshList()
end

local function buildUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "AutoPianoUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 900
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 480, 0, 420),
        Position = UDim2.new(0.5, -240, 0.5, -210),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    corner(main, 12)
    new("UIStroke", { Color = C.accent, Thickness = 1, Transparency = 0.55 }, main)

    -- title bar (kéo thả)
    local title = new("Frame", {
        Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1,
    }, main)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(0.6, 0, 1, 0),
        Text = "AutoPiano", Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = C.accent,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, title)
    local close = new("TextButton", {
        Position = UDim2.new(1, -74, 0, 6), Size = UDim2.new(0, 62, 0, 26),
        BackgroundColor3 = C.item, BorderSizePixel = 0, Text = "Close",
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
    }, title)
    corner(close, 6)

    local dragging, dragStart, startPos
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    title.InputBegan:Connect(function(i)
        if isPointer(i) then dragging, dragStart, startPos = true, i.Position, main.Position end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i) if isPointer(i) then dragging = false end end)

    -- search
    searchBox = new("TextBox", {
        Position = UDim2.new(0, 12, 0, 44), Size = UDim2.new(1, -24, 0, 30),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "",
        PlaceholderText = "Search by name or tag", PlaceholderColor3 = C.muted,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    corner(searchBox, 8)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, searchBox)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function() refreshList() end)

    -- category chips
    catBar = new("ScrollingFrame", {
        Position = UDim2.new(0, 12, 0, 80), Size = UDim2.new(1, -24, 0, 28),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
    }, main)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, catBar)

    -- song list
    listFrame = new("ScrollingFrame", {
        Position = UDim2.new(0, 12, 0, 114), Size = UDim2.new(1, -24, 0, 196),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, ScrollBarThickness = 4,
        ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, main)
    corner(listFrame, 8)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
    }, listFrame)

    -- bottom bar
    local bar = new("Frame", {
        Position = UDim2.new(0, 12, 0, 318), Size = UDim2.new(1, -24, 0, 90),
        BackgroundTransparency = 1,
    }, main)
    nameLabel = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -210, 0, 34),
        Text = "No song selected", Font = Enum.Font.GothamMedium, TextSize = 14,
        TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, bar)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -204, 0, 0), Size = UDim2.new(0, 34, 0, 34),
        Text = "BPM", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.muted,
    }, bar)
    bpmbox = new("TextBox", {
        Position = UDim2.new(1, -168, 0, 2), Size = UDim2.new(0, 64, 0, 30),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "120",
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text, ClearTextOnFocus = false,
    }, bar)
    corner(bpmbox, 8)
    local play = new("TextButton", {
        Position = UDim2.new(1, -96, 0, 2), Size = UDim2.new(0, 96, 0, 30),
        BackgroundColor3 = C.accent, BorderSizePixel = 0, Text = "Play",
        Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.accentText,
    }, bar)
    corner(play, 8)
    play.Activated:Connect(playbuttonclicked)

    local function small(text, i, cb)
        local b = new("TextButton", {
            Position = UDim2.new((i - 1) / 3, (i - 1) * 2, 0, 46), Size = UDim2.new(1 / 3, -6, 0, 30),
            BackgroundColor3 = C.item, BorderSizePixel = 0, Text = text,
            Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
        }, bar)
        corner(b, 8)
        b.Activated:Connect(cb)
    end
    small("Shuffle", 1, function()
        if shuffleOn then return end
        if songisplaying then notify("Error", "A song is already playing", 3) return end
        shuffleOn = true
        notify("Info", "Shuffle loop on", 2)
        playRandom()
    end)
    small("Stop Loop", 2, function()
        stopLoop()
        notify("Info", "Loop stopped", 2)
    end)
    small("Add Song", 3, function()
        local ok, err = pcall(function()
            loadstring(game:HttpGet(REPO_BASE .. "add_song.lua", true))()
        end)
        if not ok then
            warn("[AutoPiano] add_song failed: " .. tostring(err))
            notify("Error", "Could not load Add Song", 3)
        end
    end)

    close.Activated:Connect(function() _G.__AP_UI_DESTROY() end)
end

_G.__AP_UI_DESTROY = function()
    alive = false
    shuffleOn = false
    if gui then pcall(function() gui:Destroy() end) end
    gui = nil
end
_G.AP_RefreshSongs = function()
    if gui then rebuildAll() end
end

buildUI()
rebuildAll()
print("[AutoPiano] UI ready - select a song then press Play")
