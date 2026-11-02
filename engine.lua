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
_G.SEEK_TO = nil -- tua tới vị trí tuyệt đối (giây), dùng cho thanh kéo
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
    baseBpm = 120, -- BPM của sheet lúc bắt đầu phát
    curBpm = 120,  -- BPM đang chỉnh
    speed = 1,     -- curBpm / baseBpm
    typingPause = false, -- đang gõ vào ô BPM thì tạm dừng
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

-- Đổi BPM ngay lúc đang phát: chỉ đổi tốc độ phát timeline (không cần chạy lại sheet)
local function setBpm(v)
    v = tonumber(v)
    if not v or v <= 0 then return false end
    v = math.clamp(v, 20, 400)
    S.curBpm = v
    S.speed = v / (S.baseBpm or v)
    if S.showBpm then pcall(S.showBpm) end
    return true
end
_G.AP_SET_BPM = setBpm

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
    keyMap[c:upper()] = { KC[c:upper()], true } -- chữ hoa = Shift + phím
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
        Size = UDim2.new(0, 260, 0, 154),
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
            Position = UDim2.new(0, 9 + (i - 1) * 62, 0, 80),
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

    ----------------------------------------------------------------
    -- BPM: [-] [ 120 ] [+] [Reset]  (gõ số rồi Enter, hoặc bấm -/+ = 5 BPM)
    ----------------------------------------------------------------
    newObj("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 118),
        Size = UDim2.new(0, 34, 0, 28),
        Text = "BPM",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(200, 200, 215),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    local function bpmButton(text, x, w, cb)
        local b = newObj("TextButton", {
            Position = UDim2.new(0, x, 0, 118),
            Size = UDim2.new(0, w, 0, 28),
            BackgroundColor3 = BTN,
            BorderSizePixel = 0,
            Text = text,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = Color3.fromRGB(235, 235, 245),
        }, frame)
        newObj("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
        table.insert(S.conns, b.Activated:Connect(cb))
    end
    local bpmBox = newObj("TextBox", {
        Position = UDim2.new(0, 82, 0, 118),
        Size = UDim2.new(0, 64, 0, 28),
        BackgroundColor3 = BTN,
        BorderSizePixel = 0,
        Text = tostring(math.floor((S.curBpm or 120) + 0.5)),
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Color3.fromRGB(235, 235, 245),
        ClearTextOnFocus = false,
    }, frame)
    newObj("UICorner", { CornerRadius = UDim.new(0, 8) }, bpmBox)
    S.showBpm = function() bpmBox.Text = tostring(math.floor(S.curBpm + 0.5)) end
    bpmButton("-", 48, 30, function() setBpm(S.curBpm - 5) end)
    bpmButton("+", 150, 30, function() setBpm(S.curBpm + 5) end)
    bpmButton("Reset", 184, 64, function() setBpm(S.baseBpm) end)
    -- đang gõ thì tạm dừng để phím ảo không chui vào ô nhập
    table.insert(S.conns, bpmBox.Focused:Connect(function() S.typingPause = true end))
    table.insert(S.conns, bpmBox.FocusLost:Connect(function()
        S.typingPause = false
        if not setBpm(bpmBox.Text) then S.showBpm() end
    end))

    -- kéo thả
    local dragging, dragStart, startPos = false, nil, nil
    local function isPointer(i)
        return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
    end
    table.insert(S.conns, frame.InputBegan:Connect(function(input)
        if isPointer(input) and not S.sliding then
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

    ----------------------------------------------------------------
    -- Thanh kéo tua: kéo tới đâu, thả ra thì nhảy tới đó
    ----------------------------------------------------------------
    local hit = newObj("TextButton", {
        Position = UDim2.new(0, 12, 0, 38),
        Size = UDim2.new(1, -24, 0, 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, frame)
    local track = newObj("Frame", {
        Position = UDim2.new(0, 0, 0.5, -3),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = BTN,
        BorderSizePixel = 0,
    }, hit)
    newObj("UICorner", { CornerRadius = UDim.new(0, 3) }, track)
    local fill = newObj("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = ACCENT,
        BorderSizePixel = 0,
    }, track)
    newObj("UICorner", { CornerRadius = UDim.new(0, 3) }, fill)
    local knob = newObj("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = UDim2.new(0, -7, 0.5, -7),
        BackgroundColor3 = ACCENT,
        BorderSizePixel = 0,
    }, track)
    newObj("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    S.setSlider = function(ratio)
        ratio = math.clamp(ratio, 0, 1)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        knob.Position = UDim2.new(ratio, -7, 0.5, -7)
    end

    local function ratioFromInput(input)
        local w = hit.AbsoluteSize.X
        if w <= 0 then return 0 end
        return math.clamp((input.Position.X - hit.AbsolutePosition.X) / w, 0, 1)
    end
    local function preview(ratio)
        S.slideRatio = ratio
        S.setSlider(ratio)
        if S.timeLabel then
            S.timeLabel.Text = fmtTime(ratio * S.total / S.speed) .. " / " .. fmtTime(S.total / S.speed)
        end
    end

    table.insert(S.conns, hit.InputBegan:Connect(function(input)
        if isPointer(input) then
            S.sliding = true
            dragging = false -- không kéo cả panel khi đang kéo thanh
            preview(ratioFromInput(input))
        end
    end))
    table.insert(S.conns, UserInputService.InputChanged:Connect(function(input)
        if S.sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            preview(ratioFromInput(input))
        end
    end))
    table.insert(S.conns, UserInputService.InputEnded:Connect(function(input)
        if S.sliding and isPointer(input) then
            S.sliding = false
            _G.SEEK_TO = (S.slideRatio or 0) * S.total
        end
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
    S.baseBpm = tonumber(bpm) or 120
    S.curBpm = S.baseBpm
    S.speed = 1
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
            local st = tonumber(_G.SEEK_TO)
            if sk ~= 0 or st then
                _G.SEEK_SECONDS = 0
                _G.SEEK_TO = nil
                S.pos = math.min(math.max(0, (st or S.pos) + sk * S.speed), S.total)
                idx = 1
                while idx <= n and ev[idx].t < S.pos do idx = idx + 1 end
                releaseAll()
            end

            if not (pausing or S.typingPause) then S.pos = S.pos + dt * S.speed end

            while idx <= n and ev[idx].t <= S.pos do
                local e = ev[idx]
                if e.pedal ~= nil then
                    sendKey(KC.Space, e.pedal)
                else
                    pressChord(e.keys, e.hold and math.max(e.hold / S.speed, 0.03) or nil)
                end
                idx = idx + 1
            end

            if S.timeLabel and not S.sliding and now - lastLabel > 0.1 then
                lastLabel = now
                pcall(function()
                    S.timeLabel.Text = fmtTime(math.min(S.pos, S.total) / S.speed) .. " / " .. fmtTime(S.total / S.speed)
                    if S.setSlider and S.total > 0 then S.setSlider(S.pos / S.total) end
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
