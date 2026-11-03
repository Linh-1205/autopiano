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
local HIDDEN_FILE = CUSTOM_DIR .. "/_hidden.txt" -- bài có sẵn đã xoá (ẩn)
local EXTRA_FILE = CUSTOM_DIR .. "/_extra_cats.txt" -- mục tạo bằng nút +
local ASSET_DIR = "AUTOPIANO_ASSETS" -- ảnh nền được tải 1 lần rồi lưu ở đây
-- Thử lần lượt: bản 1600x900 nhẹ (upload wallpaper.jpg cạnh auto.lua) -> ảnh gốc 4K
local WALLPAPER_URLS = {
    REPO_BASE .. "wallpaper.jpg",
    "https://raw.githubusercontent.com/Linh-1205/autopiano/9bce86fc18d8f8e6a8680981d82fb9a986d48733/Wallpaper_Alchemy_-_Cyrene_Honkai_Star_Rail_4K_Wallpaper.jpg",
}

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

-- Sustain pedal = Space (giữ / thả). Dừng bài thì releaseAll() tự nhả pedal.
local function sendPedal(down)
    if _G.STOPIT then return end
    sendKey(KC.Space, down)
end

-- Velocity: Virtual Piano đổi lực nốt bằng Alt + 1 phím trong map "58qrupdhl"
local VELOCITY_MAP = "58qrupdhl"
local function velocityKey(vel)
    vel = math.clamp(tonumber(vel) or 0.5, 0, 1)
    if vel < 0.27 then return "2" end -- rất nhẹ
    if vel >= 0.88 then return "c" end -- rất mạnh
    local index = math.floor((vel - 0.27) / 0.61 * (#VELOCITY_MAP - 2)) + 2
    return VELOCITY_MAP:sub(index, index)
end
local function sendVelocity(vel)
    if _G.STOPIT then return end
    local entry = keyMap[velocityKey(vel)]
    if not entry then return end
    local code = entry[1]
    sendKey(KC.LeftAlt, true)
    sendKey(code, true)
    sendKey(code, false)
    sendKey(KC.LeftAlt, false)
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
    sendKey(KC.LeftAlt, false)
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
-- Theme hồng + kính, giống giao diện chính (auto.lua)
local ACCENT = Color3.fromRGB(201, 112, 141) -- rose
local BG = Color3.fromRGB(255, 250, 251)
local BTN = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(67, 48, 58)
local INK_SOFT = Color3.fromRGB(112, 90, 101)
local PINK100 = Color3.fromRGB(249, 221, 229)
local PINK300 = Color3.fromRGB(236, 169, 189)

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

-- viền kính: sáng ở góc trên-trái, mờ dần ở giữa, hồng nhạt ở góc dưới-phải
local function glowStroke(o, thickness)
    local st = newObj("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255), Thickness = thickness or 1, Transparency = 0.2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
    newObj("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), PINK300),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.65), NumberSequenceKeypoint.new(1, 0.2),
        }),
        Rotation = 45,
    }, st)
end

local function glassControl(o)
    o.BackgroundTransparency = 0.5
    glowStroke(o, 1)
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
        BackgroundColor3 = PINK100,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    newObj("UICorner", { CornerRadius = UDim.new(0, 16) }, frame)
    newObj("UIGradient", { Color = ColorSequence.new(PINK100, PINK300), Rotation = 135 }, frame)
    glowStroke(frame, 1.5)
    -- ảnh nền (nếu auto.lua đã tải xong) + lớp sương để chữ rõ
    if _G.AP_WALLPAPER then
        local wall = newObj("ImageLabel", {
            Name = "Wallpaper", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            Image = _G.AP_WALLPAPER, ScaleType = Enum.ScaleType.Crop,
        }, frame)
        newObj("UICorner", { CornerRadius = UDim.new(0, 16) }, wall)
    end
    local veil = newObj("Frame", {
        Name = "Veil", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = BG,
        BackgroundTransparency = 0.35, BorderSizePixel = 0,
    }, frame)
    newObj("UICorner", { CornerRadius = UDim.new(0, 16) }, veil)

    newObj("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(0.5, 0, 0, 22),
        Text = 'Auto<font color="rgb(201,112,141)"><i>Piano</i></font>',
        RichText = true,
        Font = Enum.Font.Garamond,
        TextSize = 23,
        TextColor3 = INK,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, frame)
    S.timeLabel = newObj("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0.5, 0, 0, 8),
        Size = UDim2.new(0.5, -12, 0, 22),
        Text = "0:00 / " .. fmtTime(S.total),
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = INK_SOFT,
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
            TextColor3 = INK,
            AutoButtonColor = true,
        }, frame)
        newObj("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
        glassControl(b)
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
        TextColor3 = INK_SOFT,
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
            TextColor3 = INK,
        }, frame)
        newObj("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
        glassControl(b)
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
        TextColor3 = INK,
        ClearTextOnFocus = false,
    }, frame)
    newObj("UICorner", { CornerRadius = UDim.new(0, 10) }, bpmBox)
    glassControl(bpmBox)
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
        BackgroundColor3 = PINK300,
        BackgroundTransparency = 0.45,
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
    newObj("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2 }, knob)

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
                -- khôi phục velocity / pedal đúng như trạng thái tại vị trí mới
                local lastPedal, lastVel
                for i = 1, idx - 1 do
                    if ev[i].pedal ~= nil then lastPedal = ev[i].pedal end
                    if ev[i].vel ~= nil then lastVel = ev[i].vel end
                end
                if lastVel ~= nil then sendVelocity(lastVel) end
                if lastPedal then sendPedal(true) end
            end

            if not (pausing or S.typingPause) then S.pos = S.pos + dt * S.speed end

            while idx <= n and ev[idx].t <= S.pos do
                local e = ev[idx]
                if e.pedal ~= nil then
                    sendPedal(e.pedal)
                elseif e.vel ~= nil then
                    sendVelocity(e.vel)
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
    if _G.STOPIT then return end
    if S.phase == "record" then
        S.events[#S.events + 1] = { t = S.cursor, pedal = true }
    else
        sendPedal(true)
    end
end

function pedalUp()
    if _G.STOPIT then return end
    if S.phase == "record" then
        S.events[#S.events + 1] = { t = S.cursor, pedal = false }
    else
        sendPedal(false)
    end
end

-- vel: 0..1 (MIDI velocity / 127). Gọi trước cụm nốt cần đổi lực.
function adjustVelocity(vel)
    if _G.STOPIT then return end
    if S.phase == "record" then
        S.events[#S.events + 1] = { t = S.cursor, vel = tonumber(vel) or 0.5 }
    else
        sendVelocity(vel)
    end
end

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
local TweenService = game:GetService("TweenService")

-- Bảng màu giống index.html (ivory / blush / pink / rose / ink)
local C = {
    white = Color3.fromRGB(255, 255, 255),
    ivory = Color3.fromRGB(255, 250, 251),
    blush = Color3.fromRGB(253, 238, 242),
    pink100 = Color3.fromRGB(249, 221, 229),
    pink200 = Color3.fromRGB(244, 198, 211),
    pink300 = Color3.fromRGB(236, 169, 189),
    rose = Color3.fromRGB(201, 112, 141),
    roseDeep = Color3.fromRGB(168, 80, 110),
    ink = Color3.fromRGB(67, 48, 58),
    inkSoft = Color3.fromRGB(112, 90, 101), -- đậm hơn index một chút để đọc được trên kính
}
local FONT_SERIF = Enum.Font.Garamond
local FONT = Enum.Font.Gotham
local FONT_MED = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end

----------------------------------------------------------------------
-- Hiệu ứng kính (liquid glass)
--   * nền trắng hồng trong suốt để thấy ảnh nền phía sau
--   * viền sáng chéo: góc trên-trái sáng, mờ dần ở giữa, hồng nhạt ở góc dưới-phải
--   * UIGradient KHÔNG gắn lên TextButton/TextBox (sẽ nhuộm màu chữ), chỉ gắn lên viền và Frame
----------------------------------------------------------------------
local function glowStroke(o, thickness)
    local st = new("UIStroke", {
        Color = C.white, Thickness = thickness or 1, Transparency = 0.2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
    new("UIGradient", {
        Color = ColorSequence.new(C.white, C.pink300),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.45, 0.65),
            NumberSequenceKeypoint.new(1, 0.2),
        }),
        Rotation = 45,
    }, st)
    return st
end

-- Frame / ScrollingFrame dạng kính
local function glassFrame(o, alpha, radius)
    o.BackgroundColor3 = C.white
    o.BackgroundTransparency = alpha or 0.4
    o.BorderSizePixel = 0
    corner(o, radius or 14)
    new("UIGradient", { Color = ColorSequence.new(C.white, C.pink100), Rotation = 90 }, o)
    glowStroke(o, 1)
    return o
end

local function hoverFade(b, base, over)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = over }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.2), { BackgroundTransparency = base }):Play()
    end)
end

-- Nút / ô nhập: "soft" = kính trắng chữ tối, "rose" = hồng đậm chữ trắng (nút chính)
local function control(o, kind, radius)
    corner(o, radius or 10)
    o.BorderSizePixel = 0
    if kind == "rose" then
        o.BackgroundColor3 = C.rose
        o.BackgroundTransparency = 0.08
        o.TextColor3 = C.white
    else
        o.BackgroundColor3 = C.white
        o.BackgroundTransparency = 0.5
        o.TextColor3 = C.ink
    end
    glowStroke(o, 1)
    if o:IsA("TextButton") then
        o.AutoButtonColor = false
        hoverFade(o, o.BackgroundTransparency, math.max(o.BackgroundTransparency - 0.22, 0))
    end
    return o
end

-- Ảnh nền: tải 1 lần, lưu file, nạp bằng getcustomasset (cần executor hỗ trợ; không có thì dùng nền gradient hồng)
local function loadWallpaper(apply)
    if type(writefile) ~= "function" or type(getcustomasset) ~= "function" then return end
    task.spawn(function()
        local path = ASSET_DIR .. "/wallpaper.jpg"
        local have = type(isfile) == "function" and isfile(path)
        if not have then
            pcall(function()
                if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(ASSET_DIR) then
                    makefolder(ASSET_DIR)
                end
            end)
            local data
            for _, url in ipairs(WALLPAPER_URLS) do
                local ok, res = pcall(function() return game:HttpGet(url, true) end)
                -- JPEG bắt đầu bằng FF D8 FF; trang lỗi 404 của GitHub là chữ nên bị loại
                if ok and type(res) == "string" and #res > 2000 and res:sub(1, 3) == "\255\216\255" then
                    data = res
                    break
                end
            end
            if not data then
                warn("[AutoPiano] Wallpaper not found, using the plain pink background")
                return
            end
            if not pcall(writefile, path, data) then return end
        end
        local ok, id = pcall(getcustomasset, path)
        if ok and id then
            _G.AP_WALLPAPER = id
            apply(id)
        end
    end)
end

local function notify(kind, msg, dur) Notif:SendNotification(kind, msg, dur or 3) end

----------------------------------------------------------------------
-- Song model
----------------------------------------------------------------------
local songs = {}
local songisplaying = false
local shuffleOn = false
local selectedCat = "All"
local alive = true
local hidden = {} -- [url] = true: bài trong SONG_LIST bị xoá/ẩn

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
        if not hidden[d.url] then
            addSong({ url = d.url, bpm = d.bpm, cat = d.cat })
        end
    end
end

-- Custom songs từ folder executor
local function hasFS()
    return type(isfolder) == "function" and type(listfiles) == "function" and type(readfile) == "function"
end

local function loadHidden()
    if type(isfile) == "function" and type(readfile) == "function" and isfile(HIDDEN_FILE) then
        local ok, content = pcall(readfile, HIDDEN_FILE)
        if ok and content then
            for line in tostring(content):gmatch("[^\r\n]+") do hidden[line] = true end
        end
    end
end

local function saveHidden()
    if type(writefile) ~= "function" then return end -- không có FS: chỉ ẩn trong phiên này
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(CUSTOM_DIR) then
            makefolder(CUSTOM_DIR)
        end
        local lines = {}
        for url in pairs(hidden) do lines[#lines + 1] = url end
        table.sort(lines)
        writefile(HIDDEN_FILE, table.concat(lines, "\n"))
    end)
end

local extraCats = {} -- [name] = true: mục tạo bằng nút +

local function loadExtraCats()
    if type(isfile) == "function" and type(readfile) == "function" and isfile(EXTRA_FILE) then
        local ok, content = pcall(readfile, EXTRA_FILE)
        if ok and content then
            for line in tostring(content):gmatch("[^\r\n]+") do extraCats[line:lower()] = true end
        end
    end
end

local function saveExtraCats()
    if type(writefile) ~= "function" then return end -- không có FS: chỉ giữ trong phiên này
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(CUSTOM_DIR) then
            makefolder(CUSTOM_DIR)
        end
        local lines = {}
        for name in pairs(extraCats) do lines[#lines + 1] = name end
        table.sort(lines)
        writefile(EXTRA_FILE, table.concat(lines, "\n"))
    end)
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
                    if name and name:sub(1, 1) ~= "_" then
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
                            local tags = (#cats > 0) and cats or { "custom" }
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
    if s.var then
        s.button.BackgroundColor3 = C.rose
        s.button.BackgroundTransparency = 0.1
    else
        s.button.BackgroundColor3 = C.white
        s.button.BackgroundTransparency = 0.55
    end
    local nm = s.button:FindFirstChild("Name")
    if nm then nm.TextColor3 = s.var and C.white or C.ink end
    local tg = s.button:FindFirstChild("Tags")
    if tg then tg.TextColor3 = s.var and C.pink100 or C.inkSoft end
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

local function paintCheck(s)
    if not s.check then return end
    if s.checked then
        s.check.BackgroundColor3 = C.rose
        s.check.BackgroundTransparency = 0.05
        s.check.Text = "x"
    else
        s.check.BackgroundColor3 = C.white
        s.check.BackgroundTransparency = 0.35
        s.check.Text = ""
    end
end

local function makeSongButton(s)
    local b = new("TextButton", {
        Size = UDim2.new(1, -6, 0, 34),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, listFrame)
    corner(b, 10)
    new("UIStroke", { Color = C.white, Thickness = 1, Transparency = 0.65 }, b)
    local box = new("TextButton", {
        Name = "Check",
        Position = UDim2.new(0, 9, 0.5, -9),
        Size = UDim2.new(0, 18, 0, 18),
        BackgroundColor3 = C.white,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Text = "",
        Font = FONT_BOLD,
        TextSize = 12,
        TextColor3 = C.white,
        AutoButtonColor = false,
    }, b)
    corner(box, 5)
    new("UIStroke", { Color = C.pink300, Thickness = 1, Transparency = 0.2 }, box)
    s.check = box
    s.checked = false
    box.Activated:Connect(function()
        s.checked = not s.checked
        paintCheck(s)
    end)
    new("TextLabel", {
        Name = "Name",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 38, 0, 0),
        Size = UDim2.new(0.6, -38, 1, 0),
        Text = s.name,
        Font = FONT_SERIF,
        TextSize = 19,
        TextColor3 = C.ink,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, b)
    new("TextLabel", {
        Name = "Tags",
        BackgroundTransparency = 1,
        Position = UDim2.new(0.6, 0, 0, 0),
        Size = UDim2.new(0.4, -12, 1, 0),
        Text = table.concat(s.cat, ", "),
        Font = FONT,
        TextSize = 11,
        TextColor3 = C.inkSoft,
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
    for k in pairs(extraCats) do
        if not set[k] then set[k] = true; list[#list + 1] = k end
    end
    table.sort(list)
    table.insert(list, 1, "All")
    local stillThere = false
    for _, name in ipairs(list) do
        if name:lower() == selectedCat:lower() then stillThere = true end
    end
    if not stillThere then selectedCat = "All" end
    for _, name in ipairs(list) do
        local active = (name:lower() == selectedCat:lower())
        local chip = new("TextButton", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = name,
            Font = FONT_MED,
            TextSize = 12,
        }, catBar)
        control(chip, active and "rose" or "soft", 10)
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

local function deleteSongs(targets)
    local removed, failed, hiddenChanged = 0, 0, false
    for _, s in ipairs(targets) do
        if s.custom then
            if type(delfile) ~= "function" then
                failed = failed + 1
            else
                local ok, err = pcall(delfile, s.path)
                if not ok then
                    warn("[AutoPiano] delete failed: " .. tostring(err))
                    failed = failed + 1
                else
                    removed = removed + 1
                    -- gỡ khỏi _categories.txt cùng thư mục
                    local dir = tostring(s.path):match("^(.*)[/\\][^/\\]+$")
                    if dir and type(isfile) == "function" then
                        local cp = dir .. "/_categories.txt"
                        if isfile(cp) then
                            pcall(function()
                                local lines = {}
                                for line in tostring(readfile(cp)):gmatch("[^\r\n]+") do
                                    local n = line:match("^(.-)|")
                                    if n ~= s.name then lines[#lines + 1] = line end
                                end
                                writefile(cp, table.concat(lines, "\n"))
                            end)
                        end
                    end
                end
            end
        else
            hidden[s.url] = true -- bài có sẵn: ẩn khỏi danh sách (lưu lại để lần sau vẫn ẩn)
            hiddenChanged = true
            removed = removed + 1
        end
    end
    if hiddenChanged then saveHidden() end
    nameLabel.Text = "No song selected"
    rebuildAll()
    if removed > 0 then notify("Success", "Deleted " .. removed .. " song(s)", 3) end
    if failed > 0 then notify("Error", failed .. " song(s) could not be deleted (no delfile)", 4) end
end

local function buildUI()
    gui = Instance.new("ScreenGui")
    gui.Name = "AutoPianoUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 900
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

    -- Cửa sổ: nền gradient hồng (dự phòng) -> ảnh nền -> lớp sương trắng -> các tấm kính
    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.new(0, 500, 0, 454),
        Position = UDim2.new(0.5, -250, 0.5, -227),
        BackgroundColor3 = C.pink200,
        BorderSizePixel = 0,
        Active = true,
    }, gui)
    corner(main, 18)
    new("UIGradient", { Color = ColorSequence.new(C.pink100, C.pink300), Rotation = 135 }, main)
    glowStroke(main, 1.5)

    local wall = new("ImageLabel", {
        Name = "Wallpaper", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Image = "", ImageTransparency = 1, ScaleType = Enum.ScaleType.Crop,
    }, main)
    corner(wall, 18)

    -- lớp sương nhẹ để chữ không bị chìm vào ảnh
    local veil = new("Frame", {
        Name = "Veil", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.white,
        BackgroundTransparency = 0.5, BorderSizePixel = 0,
    }, main)
    corner(veil, 18)
    new("UIGradient", { Color = ColorSequence.new(C.white, C.pink100), Rotation = 120 }, veil)

    -- vệt sáng phía trên như mặt kính phản chiếu
    local sheen = new("Frame", {
        Name = "Sheen", Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = C.white,
        BackgroundTransparency = 0, BorderSizePixel = 0,
    }, main)
    corner(sheen, 18)
    new("UIGradient", {
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
        Rotation = 90,
    }, sheen)

    -- thanh tiêu đề (kéo thả)
    local title = new("Frame", { Name = "Title", Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 42) }, main)
    glassFrame(title, 0.38, 14)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(0.6, 0, 1, 0),
        Text = 'Auto<font color="rgb(201,112,141)"><i>Piano</i></font>', RichText = true,
        Font = FONT_SERIF, TextSize = 30, TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left,
    }, title)
    local close = new("TextButton", {
        Position = UDim2.new(1, -78, 0.5, -14), Size = UDim2.new(0, 66, 0, 28), Text = "Close",
        Font = FONT_MED, TextSize = 12,
    }, title)
    control(close, "soft", 10)

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
        Position = UDim2.new(0, 12, 0, 62), Size = UDim2.new(1, -132, 0, 32), Text = "",
        PlaceholderText = "Search by name or tag", PlaceholderColor3 = C.inkSoft,
        Font = FONT, TextSize = 13, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    control(searchBox, "soft", 10)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, searchBox)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function() refreshList() end)

    -- tick / bỏ tick tất cả bài đang hiện
    local selAll = new("TextButton", {
        Position = UDim2.new(1, -112, 0, 62), Size = UDim2.new(0, 100, 0, 32), Text = "Select All",
        Font = FONT_MED, TextSize = 12,
    }, main)
    control(selAll, "soft", 10)
    selAll.Activated:Connect(function()
        local any, allChecked = false, true
        for _, s in ipairs(songs) do
            if s.button and s.button.Visible then
                any = true
                if not s.checked then allChecked = false end
            end
        end
        if not any then return end
        for _, s in ipairs(songs) do
            if s.button and s.button.Visible then
                s.checked = not allChecked
                paintCheck(s)
            end
        end
    end)

    -- category chips
    catBar = new("ScrollingFrame", {
        Position = UDim2.new(0, 12, 0, 100), Size = UDim2.new(1, -56, 0, 28),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
    }, main)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, catBar)

    -- nút + : tạo mục mới (gõ tên rồi Enter, hoặc bấm + lần nữa)
    local plus = new("TextButton", {
        Position = UDim2.new(1, -40, 0, 100), Size = UDim2.new(0, 28, 0, 28), Text = "+",
        Font = FONT_BOLD, TextSize = 18,
    }, main)
    control(plus, "rose", 10)
    local catInput = new("TextBox", {
        Position = UDim2.new(0, 12, 0, 100), Size = UDim2.new(1, -56, 0, 28), Text = "", Visible = false,
        PlaceholderText = "New category name, then Enter", PlaceholderColor3 = C.inkSoft,
        Font = FONT, TextSize = 13, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    }, main)
    control(catInput, "soft", 10)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, catInput)

    local function closeCatInput(commit)
        local name = (catInput.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        catInput.Visible = false
        catBar.Visible = true
        catInput.Text = ""
        if commit and name ~= "" and name ~= "all" then
            if not extraCats[name] then
                extraCats[name] = true
                saveExtraCats()
                notify("Success", "Category added: " .. name, 3)
            end
            buildCats()
            refreshList()
        end
    end
    plus.Activated:Connect(function()
        if catInput.Visible then
            closeCatInput(true)
        else
            catBar.Visible = false
            catInput.Visible = true
            pcall(function() catInput:CaptureFocus() end)
        end
    end)
    catInput.FocusLost:Connect(function(enterPressed)
        if enterPressed and catInput.Visible then closeCatInput(true) end
    end)

    -- song list
    listFrame = new("ScrollingFrame", {
        Position = UDim2.new(0, 12, 0, 136), Size = UDim2.new(1, -24, 0, 188),
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.rose, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, main)
    glassFrame(listFrame, 0.36, 14)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
    }, listFrame)

    -- bottom bar
    local bar = new("Frame", { Position = UDim2.new(0, 12, 0, 332), Size = UDim2.new(1, -24, 0, 110) }, main)
    glassFrame(bar, 0.36, 14)
    nameLabel = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -262, 0, 36),
        Text = "No song selected", Font = FONT_SERIF, TextSize = 23,
        TextColor3 = C.ink, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, bar)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -230, 0, 8), Size = UDim2.new(0, 34, 0, 36),
        Text = "BPM", Font = FONT_MED, TextSize = 11, TextColor3 = C.inkSoft,
    }, bar)
    bpmbox = new("TextBox", {
        Position = UDim2.new(1, -192, 0, 11), Size = UDim2.new(0, 66, 0, 30), Text = "120",
        Font = FONT_MED, TextSize = 13, ClearTextOnFocus = false,
    }, bar)
    control(bpmbox, "soft", 10)
    local play = new("TextButton", {
        Position = UDim2.new(1, -118, 0, 11), Size = UDim2.new(0, 104, 0, 30), Text = "Play",
        Font = FONT_BOLD, TextSize = 14,
    }, bar)
    control(play, "rose", 10)
    play.Activated:Connect(playbuttonclicked)

    local function small(text, i, cb)
        local b = new("TextButton", {
            Position = UDim2.new(0, 14 + (i - 1) * 113, 0, 62), Size = UDim2.new(0, 109, 0, 34), Text = text,
            Font = FONT_MED, TextSize = 12,
        }, bar)
        control(b, "soft", 10)
        b.Activated:Connect(cb)
        return b
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

    -- Delete: xoá các bài đã tick (không tick thì xoá bài đang chọn). Bấm 2 lần để xác nhận.
    local deleteBtn, armedSig
    deleteBtn = small("Delete", 4, function()
        local targets = {}
        for _, s in ipairs(songs) do
            if s.checked then targets[#targets + 1] = s end
        end
        if #targets == 0 then
            for _, s in ipairs(songs) do
                if s.var == true then targets[1] = s break end
            end
        end
        if #targets == 0 then
            notify("Error", "Tick songs or select one first", 3)
            return
        end
        local names = {}
        for _, s in ipairs(targets) do names[#names + 1] = s.name end
        local sig = #targets .. ":" .. table.concat(names, "|")
        if armedSig ~= sig then
            armedSig = sig
            deleteBtn.Text = (#targets > 1) and ("Confirm (" .. #targets .. ")?") or "Confirm?"
            task.delay(3, function()
                if armedSig == sig then
                    armedSig = nil
                    deleteBtn.Text = "Delete"
                end
            end)
            return
        end
        armedSig = nil
        deleteBtn.Text = "Delete"
        deleteSongs(targets)
    end)

    -- Close: thu nhỏ thành 1 nút nhỏ (kéo được), bấm vào để mở lại
    local mini = new("TextButton", {
        Name = "Mini", Position = main.Position, Size = UDim2.new(0, 112, 0, 36), Visible = false,
        Text = 'Auto<i>Piano</i>', RichText = true, Font = FONT_SERIF, TextSize = 22,
    }, gui)
    control(mini, "rose", 14)
    local miniDown, miniStart, miniPos, miniMoved = false, nil, nil, false
    mini.InputBegan:Connect(function(i)
        if isPointer(i) then miniDown, miniStart, miniPos, miniMoved = true, i.Position, mini.Position, false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if miniDown and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - miniStart
            if math.abs(d.X) + math.abs(d.Y) > 6 then miniMoved = true end
            mini.Position = UDim2.new(miniPos.X.Scale, miniPos.X.Offset + d.X,
                miniPos.Y.Scale, miniPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i) if isPointer(i) then miniDown = false end end)
    mini.Activated:Connect(function()
        if miniMoved then miniMoved = false return end -- vừa kéo thả, không mở
        main.Position = mini.Position
        mini.Visible = false
        main.Visible = true
    end)
    close.Activated:Connect(function()
        mini.Position = main.Position
        main.Visible = false
        mini.Visible = true
    end)

    -- ảnh nền: hiện dần khi tải xong
    local function applyWallpaper(id)
        if not (gui and wall.Parent) then return end
        wall.Image = id
        TweenService:Create(wall, TweenInfo.new(0.6), { ImageTransparency = 0 }):Play()
    end
    if _G.AP_WALLPAPER then applyWallpaper(_G.AP_WALLPAPER) else loadWallpaper(applyWallpaper) end
end

_G.__AP_UI_DESTROY = function()
    alive = false
    shuffleOn = false
    if gui then pcall(function() gui:Destroy() end) end
    gui = nil
end
_G.AP_GetCategories = function()
    local set, list = { custom = true }, {}
    for _, s in ipairs(songs) do
        for _, c in ipairs(s.cat) do
            local k = c:lower()
            if not set[k] then set[k] = true; list[#list + 1] = k end
        end
    end
    for k in pairs(extraCats) do
        if not set[k] then set[k] = true; list[#list + 1] = k end
    end
    table.sort(list)
    table.insert(list, 1, "custom")
    return list
end
_G.AP_RefreshSongs = function()
    if gui then rebuildAll() end
end

loadHidden()
loadExtraCats()
buildUI()
rebuildAll()
print("[AutoPiano] UI ready - select a song then press Play")
