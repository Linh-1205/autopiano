-- MIDI2LUA loader + GUI
-- Original-style playback
--
-- No timeline seek, no +/- time controls, no random Shift
--
-- Repeated notes such as:
-- d d p
-- p p
-- l l
-- are handled with per-key generations.

_G.STOPIT = false

local NotificationLibrary =
    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/hellohellohell012321/TALENTLESS/main/notif_lib.lua"
    ))()

local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ================================================================
-- SOUND
-- ================================================================

local function playSound(soundId, loudness)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. tostring(soundId)
    sound.Parent = LocalPlayer.Character or LocalPlayer
    sound.Volume = loudness or 1
    sound:Play()

    task.delay(3, function()
        if sound then
            sound:Destroy()
        end
    end)
end

-- ================================================================
-- LOAD MAIN AUTOPIANO FILE
-- ================================================================

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Linh-1205/autopiano/refs/heads/main/load.lua",
    true
))()

task.wait(0.3)

playSound("6493287948", 0.1)

NotificationLibrary:SendNotification(
    "Success",
    "MIDI2LUA loader loaded.",
    1
)

-- ================================================================
-- GLOBAL SETTINGS
-- ================================================================

local songPlaying = false
local pausing = false

local errormargin = tonumber(errormargin) or 0

bpm = tonumber(bpm) or 120

if bpm <= 0 then
    bpm = 120
end

-- Đồng bộ với Gui (Gui ghi vào _G, vòng lặp này chép vào biến của loader)
_G.BPM = bpm
_G.ERROR_MARGIN = errormargin
_G.PAUSED = false

task.spawn(function()
    while not _G.STOPIT do
        bpm = _G.BPM or bpm
        errormargin = _G.ERROR_MARGIN or errormargin
        pausing = _G.PAUSED == true
        task.wait(0.05)
    end
end)

-- ================================================================
-- KEY MAPPINGS
-- ================================================================

local keyMappings = {

    ["1"] = Enum.KeyCode.One,
    ["!"] = Enum.KeyCode.One,

    ["2"] = Enum.KeyCode.Two,
    ["@"] = Enum.KeyCode.Two,

    ["3"] = Enum.KeyCode.Three,
    ["#"] = Enum.KeyCode.Three,

    ["4"] = Enum.KeyCode.Four,
    ["$"] = Enum.KeyCode.Four,

    ["5"] = Enum.KeyCode.Five,
    ["%"] = Enum.KeyCode.Five,

    ["6"] = Enum.KeyCode.Six,
    ["^"] = Enum.KeyCode.Six,

    ["7"] = Enum.KeyCode.Seven,
    ["&"] = Enum.KeyCode.Seven,

    ["8"] = Enum.KeyCode.Eight,
    ["*"] = Enum.KeyCode.Eight,

    ["9"] = Enum.KeyCode.Nine,
    ["("] = Enum.KeyCode.Nine,

    ["0"] = Enum.KeyCode.Zero,
    [")"] = Enum.KeyCode.Zero,

    ["q"] = Enum.KeyCode.Q,
    ["Q"] = Enum.KeyCode.Q,

    ["w"] = Enum.KeyCode.W,
    ["W"] = Enum.KeyCode.W,

    ["e"] = Enum.KeyCode.E,
    ["E"] = Enum.KeyCode.E,

    ["r"] = Enum.KeyCode.R,
    ["R"] = Enum.KeyCode.R,

    ["t"] = Enum.KeyCode.T,
    ["T"] = Enum.KeyCode.T,

    ["y"] = Enum.KeyCode.Y,
    ["Y"] = Enum.KeyCode.Y,

    ["u"] = Enum.KeyCode.U,
    ["U"] = Enum.KeyCode.U,

    ["i"] = Enum.KeyCode.I,
    ["I"] = Enum.KeyCode.I,

    ["o"] = Enum.KeyCode.O,
    ["O"] = Enum.KeyCode.O,

    ["p"] = Enum.KeyCode.P,
    ["P"] = Enum.KeyCode.P,

    ["a"] = Enum.KeyCode.A,
    ["A"] = Enum.KeyCode.A,

    ["s"] = Enum.KeyCode.S,
    ["S"] = Enum.KeyCode.S,

    ["d"] = Enum.KeyCode.D,
    ["D"] = Enum.KeyCode.D,

    ["f"] = Enum.KeyCode.F,
    ["F"] = Enum.KeyCode.F,

    ["g"] = Enum.KeyCode.G,
    ["G"] = Enum.KeyCode.G,

    ["h"] = Enum.KeyCode.H,
    ["H"] = Enum.KeyCode.H,

    ["j"] = Enum.KeyCode.J,
    ["J"] = Enum.KeyCode.J,

    ["k"] = Enum.KeyCode.K,
    ["K"] = Enum.KeyCode.K,

    ["l"] = Enum.KeyCode.L,
    ["L"] = Enum.KeyCode.L,

    ["z"] = Enum.KeyCode.Z,
    ["Z"] = Enum.KeyCode.Z,

    ["x"] = Enum.KeyCode.X,
    ["X"] = Enum.KeyCode.X,

    ["c"] = Enum.KeyCode.C,
    ["C"] = Enum.KeyCode.C,

    ["v"] = Enum.KeyCode.V,
    ["V"] = Enum.KeyCode.V,

    ["b"] = Enum.KeyCode.B,
    ["B"] = Enum.KeyCode.B,

    ["n"] = Enum.KeyCode.N,
    ["N"] = Enum.KeyCode.N,

    ["m"] = Enum.KeyCode.M,
    ["M"] = Enum.KeyCode.M
}

-- ================================================================
-- SHIFT MAP
--
-- Lowercase:  d -> D key WITHOUT Shift
-- Uppercase:  D -> D key WITH Shift
-- There is NO random Shift.
-- ================================================================

local shiftRequired = {

    ["!"] = true,
    ["@"] = true,
    ["#"] = true,
    ["$"] = true,
    ["%"] = true,
    ["^"] = true,
    ["&"] = true,
    ["*"] = true,
    ["("] = true,
    [")"] = true,

    ["Q"] = true,
    ["W"] = true,
    ["E"] = true,
    ["R"] = true,
    ["T"] = true,
    ["Y"] = true,
    ["U"] = true,
    ["I"] = true,
    ["O"] = true,
    ["P"] = true,

    ["A"] = true,
    ["S"] = true,
    ["D"] = true,
    ["F"] = true,
    ["G"] = true,
    ["H"] = true,
    ["J"] = true,
    ["K"] = true,
    ["L"] = true,

    ["Z"] = true,
    ["X"] = true,
    ["C"] = true,
    ["V"] = true,
    ["B"] = true,
    ["N"] = true,
    ["M"] = true
}

-- ================================================================
-- KEY GENERATION
--
-- Prevents an old key-up from cancelling a newer key-down
-- of the same key (repeated notes).
-- ================================================================

local keyGeneration = {}

local function getKeyId(key)
    return tostring(key)
end

local function createKeyGeneration(key)
    local id = getKeyId(key)
    keyGeneration[id] = (keyGeneration[id] or 0) + 1
    return keyGeneration[id]
end

local function isCurrentGeneration(key, generation)
    return keyGeneration[getKeyId(key)] == generation
end

-- ================================================================
-- RELEASE EVERYTHING
-- ================================================================

local function releaseAllInputs()

    for _, keyCode in pairs(keyMappings) do
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)
    end

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftAlt, false, game)
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
end

-- ================================================================
-- NOTE HOLD TIME
-- ================================================================

local function getHoldTime(beats, isShort, bpmValue)

    if isShort then
        return math.random(4, 12) / 100
    end

    if type(beats) ~= "number" or beats <= 0 then
        return 0.04
    end

    local safeBpm =
        math.max(
            tonumber(bpmValue)
                or tonumber(bpm)
                or 120,
            1
        )

    local noteTime = (beats / safeBpm) * 60
    local maxRandom = noteTime / 2
    local randomOff = math.random() * maxRandom

    return math.max(0.01, noteTime - randomOff)
end

-- ================================================================
-- PRESS ONE KEY
-- ================================================================

local function pressSingleKey(key, beats, isShort, ctrlRequired)

    if _G.STOPIT then
        return
    end

    local keyCode = keyMappings[key]

    if not keyCode then
        warn("Unknown key mapping: " .. tostring(key))
        return
    end

    local generation = createKeyGeneration(key)

    -- Make sure an old hold does not remain active before retriggering.
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)

    local needsShift = shiftRequired[key] == true

    -- CTRL
    if ctrlRequired then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
    end

    -- SHIFT (only uppercase/symbol mappings, never random)
    if needsShift then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
    end

    -- KEY DOWN
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)

    -- RELEASE MODIFIERS (we do NOT keep Shift held)
    if needsShift then
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end

    if ctrlRequired then
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
    end

    -- HOLD
    local waitTime = getHoldTime(beats, isShort, bpm)

    task.wait(waitTime)

    -- STOP SAFETY
    if _G.STOPIT then
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
        end)
        return
    end

    -- ONLY NEWEST GENERATION MAY RELEASE
    if isCurrentGeneration(key, generation) then
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end
end

-- ================================================================
-- PRESS KEY / CHORD
-- ================================================================

local function pressKey(keys, beats, isShort)

    if _G.STOPIT then
        return
    end

    keys = tostring(keys)

    local ctrlRequired = false

    -- CTRL+
    if keys:sub(1, 5) == "Ctrl+" then
        ctrlRequired = true
        keys = keys:sub(6)
    end

    -- PRESS EACH KEY
    for i = 1, #keys do

        local key = keys:sub(i, i)

        task.spawn(function()
            pressSingleKey(key, beats, isShort, ctrlRequired)
        end)

        -- Keep the original error-margin timing behavior.
        if errormargin ~= 0 and math.random() < 0.5 then
            task.wait(math.random() * errormargin / 3)
        end
    end
end

-- ================================================================
-- VELOCITY
-- ================================================================

function adjustVelocity(vel)

    if _G.STOPIT then
        return
    end

    local velocityMap = "58qrupdhl"

    vel = math.clamp(tonumber(vel) or 0.5, 0, 1)

    local topress

    if vel < 0.27 then
        topress = "2"
    elseif vel >= 0.88 then
        topress = "c"
    else
        local index =
            math.floor(
                (vel - 0.27)
                / 0.61
                * (#velocityMap - 2)
            ) + 2

        index = math.clamp(index, 1, #velocityMap)

        topress = velocityMap:sub(index, index)
    end

    local keyCode = keyMappings[topress]

    if not keyCode then
        return
    end

    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftAlt, false, game)
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftAlt, false, game)
end

-- ================================================================
-- SUSTAIN PEDAL
-- ================================================================

function pedalDown()
    if _G.STOPIT then
        return
    end

    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
end

function pedalUp()
    if _G.STOPIT then
        return
    end

    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end

-- ================================================================
-- NOTE MAPPINGS
-- ================================================================

local noteMappings = {

    ["C"] = {
        [1] = "1",
        [2] = "8",
        [3] = "t",
        [4] = "s",
        [5] = "l",
        [6] = "m"
    },

    ["C#"] = {
        [1] = "!",
        [2] = "*",
        [3] = "T",
        [4] = "S",
        [5] = "L"
    },

    ["D"] = {
        [1] = "2",
        [2] = "9",
        [3] = "y",
        [4] = "d",
        [5] = "z"
    },

    ["D#"] = {
        [1] = "@",
        [2] = "(",
        [3] = "Y",
        [4] = "D",
        [5] = "Z"
    },

    ["E"] = {
        [1] = "3",
        [2] = "0",
        [3] = "u",
        [4] = "f",
        [5] = "x"
    },

    ["F"] = {
        [1] = "4",
        [2] = "q",
        [3] = "i",
        [4] = "g",
        [5] = "c"
    },

    ["F#"] = {
        [1] = "$",
        [2] = "Q",
        [3] = "I",
        [4] = "G",
        [5] = "C"
    },

    ["G"] = {
        [1] = "5",
        [2] = "w",
        [3] = "o",
        [4] = "h",
        [5] = "v"
    },

    ["G#"] = {
        [1] = "%",
        [2] = "W",
        [3] = "O",
        [4] = "H",
        [5] = "V"
    },

    ["A"] = {
        [1] = "6",
        [2] = "e",
        [3] = "p",
        [4] = "j",
        [5] = "b"
    },

    ["A#"] = {
        [1] = "^",
        [2] = "E",
        [3] = "P",
        [4] = "J",
        [5] = "B"
    },

    ["B"] = {
        [1] = "7",
        [2] = "r",
        [3] = "a",
        [4] = "k",
        [5] = "n"
    }
}

-- ================================================================
-- PRESS NOTE
-- ================================================================

function pressnote(note, octave, beats, bpmValue)

    if _G.STOPIT then
        return
    end

    -- Pause: đứng chờ cho tới khi resume (hoặc stop)
    while pausing and not _G.STOPIT do
        task.wait(0.05)
    end

    if _G.STOPIT then
        return
    end

    local key =
        noteMappings[note]
        and
        noteMappings[note][octave]

    if key then
        task.spawn(function()
            pressKey(key, beats, false)
        end)
    else
        warn(
            "Invalid note or octave: "
            .. tostring(note)
            .. " "
            .. tostring(octave)
        )
    end
end

-- ================================================================
-- REST
-- ================================================================

function rest(beats, bpmValue)

    if _G.STOPIT then
        return
    end

    while pausing and not _G.STOPIT do
        task.wait(0.05)
    end

    if _G.STOPIT then
        return
    end

    local safeBpm =
        math.max(
            tonumber(bpmValue)
                or tonumber(bpm)
                or 120,
            1
        )

    local waitTime =
        (tonumber(beats) or 0)
        / safeBpm
        * 60

    -- Keep original error-margin behavior.
    if errormargin == 0 then
        task.wait(waitTime)
    else
        local randomOffset =
            (math.random() * 1.6 - 1)
            * (errormargin / 2)

        task.wait(math.max(0, waitTime + randomOffset))
    end
end

-- ================================================================
-- KEYPRESS
-- ================================================================

function keypress(keys, beats, bpmValue)

    if _G.STOPIT then
        return
    end

    while pausing and not _G.STOPIT do
        task.wait(0.05)
    end

    if _G.STOPIT then
        return
    end

    task.spawn(function()
        pressKey(keys, beats, type(beats) ~= "number")
    end)
end

-- ================================================================
-- KEY SEQUENCE 16
-- ================================================================

function keysequence16(keys, beats, bpmValue)

    if _G.STOPIT then
        return
    end

    while pausing and not _G.STOPIT do
        task.wait(0.05)
    end

    if _G.STOPIT then
        return
    end

    task.spawn(function()

        for i = 1, #keys do

            if _G.STOPIT then
                return
            end

            local key = keys:sub(i, i)

            keypress(key, beats, bpmValue)

            rest(0.25, bpmValue)
        end
    end)
end

-- ================================================================
-- FINISHED SONG
-- ================================================================

function finishedSong()

    if _G.STOPIT then
        return
    end

    songPlaying = false
    pausing = false

    releaseAllInputs()

    playSound("6493287948", 0.1)

    NotificationLibrary:SendNotification(
        "Success",
        "Your song has finished.",
        3
    )
end

-- ================================================================
-- STOP
-- ================================================================

function stopPlayingSongs()

    _G.STOPIT = true

    songPlaying = false
    pausing = false

    releaseAllInputs()

    NotificationLibrary:SendNotification(
        "Success",
        "Stopping...",
        1
    )
end

-- ================================================================
-- CHARACTER SAFETY
-- ================================================================

LocalPlayer.CharacterRemoving:Connect(function()
    releaseAllInputs()
end)

-- ================================================================
-- GUI
-- ================================================================

local function getGuiParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end

    local ok2, core = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and core then
        local t = Instance.new("Folder")
        local good = pcall(function() t.Parent = core end)
        t:Destroy()
        if good then return core end
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
local oldGui = guiParent:FindFirstChild("PlayerGui_Main")
if oldGui then oldGui:Destroy() end

local BG = Color3.fromRGB(32, 32, 32)
local PINK1 = Color3.fromRGB(255, 108, 154)
local PINK2 = Color3.fromRGB(255, 109, 155)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local BTN = Color3.fromRGB(55, 55, 55)

local gui = Instance.new("ScreenGui")
gui.Name = "PlayerGui_Main"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(327, 119)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 5)
    c.Parent = o
end

local function makeButton(text, x, y, w, h)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, h)
    b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = BTN
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = WHITE
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.AutoButtonColor = true
    b.Parent = main
    corner(b)
    return b
end

local function makeLabel(text, x, y, w, h, bg, tc, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(w, h)
    l.Position = UDim2.fromOffset(x, y)
    l.BackgroundColor3 = bg
    l.BackgroundTransparency = bg and 0 or 1
    l.BorderSizePixel = 0
    l.Text = text
    l.TextColor3 = tc
    l.Font = Enum.Font.GothamBold
    l.TextSize = size or 13
    l.Parent = main
    corner(l)
    return l
end

-- Hàng 1: Pause / Stop / BPM
local pauseBtn = makeButton("II", 8, 8, 28, 28)
local stopBtn = makeButton("■", 40, 8, 28, 28)

local bpmUp = makeButton("^", 164, 8, 28, 28)
local bpmLabel = makeLabel("BPM: " .. _G.BPM, 196, 8, 92, 28, PINK1, BLACK, 13)
local bpmDown = makeButton("v", 292, 8, 28, 28)

-- Hàng 2: thanh tiến trình
local timeLeft = makeLabel("0:00", 8, 44, 32, 20, BG, WHITE, 11)
timeLeft.BackgroundTransparency = 1
local timeRight = makeLabel("0:00", 287, 44, 32, 20, BG, WHITE, 11)
timeRight.BackgroundTransparency = 1

local barBack = Instance.new("Frame")
barBack.Size = UDim2.fromOffset(240, 4)
barBack.Position = UDim2.fromOffset(44, 52)
barBack.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
barBack.BorderSizePixel = 0
barBack.Parent = main
corner(barBack, 2)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = PINK1
barFill.BorderSizePixel = 0
barFill.Parent = barBack
corner(barFill, 2)

local knob = Instance.new("Frame")
knob.Size = UDim2.fromOffset(10, 10)
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.fromScale(0, 0.5)
knob.BackgroundColor3 = WHITE
knob.BorderSizePixel = 0
knob.Parent = barBack
corner(knob, 5)

-- Hàng 3: Error margin + credit
local emUp = makeButton("↑", 8, 76, 26, 26)
local emLabel = makeLabel(string.format("error margin: %.2f", _G.ERROR_MARGIN), 38, 76, 128, 26, PINK2, BLACK, 12)
local emDown = makeButton("↓", 170, 76, 26, 26)
local credit = makeLabel("created by gau1234ct5", 202, 76, 117, 26, WHITE, BLACK, 10)

-- Chức năng
pauseBtn.MouseButton1Click:Connect(function()
    _G.PAUSED = not _G.PAUSED
    pauseBtn.Text = _G.PAUSED and "▶" or "II"
end)

-- Stop: dừng bài, nhả hết phím, tắt Gui
stopBtn.MouseButton1Click:Connect(function()
    stopPlayingSongs()
    gui:Destroy()
end)

local function refreshBPM()
    bpmLabel.Text = "BPM: " .. _G.BPM
end
bpmUp.MouseButton1Click:Connect(function()
    _G.BPM = _G.BPM + 10
    refreshBPM()
end)
bpmDown.MouseButton1Click:Connect(function()
    _G.BPM = math.max(10, _G.BPM - 10)
    refreshBPM()
end)

local function refreshEM()
    emLabel.Text = string.format("error margin: %.2f", _G.ERROR_MARGIN)
end
emUp.MouseButton1Click:Connect(function()
    _G.ERROR_MARGIN = math.floor((_G.ERROR_MARGIN + 0.005) * 1000 + 0.5) / 1000
    refreshEM()
end)
emDown.MouseButton1Click:Connect(function()
    _G.ERROR_MARGIN = math.max(0, math.floor((_G.ERROR_MARGIN - 0.005) * 1000 + 0.5) / 1000)
    refreshEM()
end)

-- API cập nhật tiến trình: _G.SetProgress(giây_hiện_tại, tổng_giây)
local function fmt(t)
    t = math.max(0, math.floor(t))
    return string.format("%d:%02d", t // 60, t % 60)
end
_G.SetProgress = function(cur, total)
    if not gui.Parent then return end
    local a = total > 0 and math.clamp(cur / total, 0, 1) or 0
    barFill.Size = UDim2.fromScale(a, 1)
    knob.Position = UDim2.fromScale(a, 0.5)
    timeLeft.Text = fmt(cur)
    timeRight.Text = fmt(total)
end

-- Kéo Gui bằng chuột
local dragging, dragStart, startPos
main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

-- ================================================================
-- FINAL STATE
-- ================================================================

songPlaying = true
pausing = false

print("MIDI2LUA loader ready.")
print("Random Shift: DISABLED")
print("Repeated-key protection: ENABLED")
