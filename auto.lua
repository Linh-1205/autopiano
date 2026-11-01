--[[
  AutoPiano - Entry point
  UI + orchestration + embedded engine
  Spec: independent, no Talentless library dependency
  Sheet data only from: https://hellohellohell0.com/talentless-raw/SONGS/{url}
]]

-- ========== Notification ==========
local NotificationLibrary = (function()
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/Linh-1205/autopiano/main/notif_lib.lua", true))()
    end)
    if ok and lib then return lib end
    return {
        SendNotification = function(_, title, text)
            print("[Notif]", title, text)
        end
    }
end)()

local function playSound(soundId, loudness)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://" .. tostring(soundId)
        sound.Parent = game.Players.LocalPlayer.Character or game.Players.LocalPlayer
        sound.Volume = loudness or 0.15
        sound:Play()
        game:GetService("Debris"):AddItem(sound, 3)
    end)
end

-- ========== Embed engine source ==========
-- Prefer local embed; fallback HttpGet if embed empty
_G.__AP_ENGINE_SRC = [=[
--[[
  AutoPiano Engine - self-contained note player
  No external libraries. Defines: keypress, rest, finishedSong, pressnote, etc.
]]

_G.STOPIT = false
_G.songisplaying = true
_G.SEEK_SECONDS = 0

local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

x = "hi" -- song scripts pass this as beats (short notes)
if type(bpm) ~= "number" or bpm <= 0 then
    bpm = 120
end
errormargin = errormargin or 0
pausing = false

local resumeEvent = Instance.new("BindableEvent")

-- minimal notif (self-drawn, no external lib required)
local function notify(title, text, dur)
    dur = dur or 2
    local ok = pcall(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "APNotif"
        sg.ResetOnSpawn = false
        sg.Parent = CoreGui
        local f = Instance.new("Frame")
        f.Size = UDim2.new(0, 280, 0, 56)
        f.Position = UDim2.new(1, -300, 1, -80)
        f.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
        f.Parent = sg
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.new(1, -16, 0, 20)
        t.Position = UDim2.new(0, 8, 0, 6)
        t.Font = Enum.Font.GothamBold
        t.TextSize = 14
        t.TextColor3 = Color3.fromRGB(255, 255, 255)
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Text = tostring(title)
        t.Parent = f
        local b = Instance.new("TextLabel")
        b.BackgroundTransparency = 1
        b.Size = UDim2.new(1, -16, 0, 22)
        b.Position = UDim2.new(0, 8, 0, 28)
        b.Font = Enum.Font.Gotham
        b.TextSize = 13
        b.TextColor3 = Color3.fromRGB(200, 200, 210)
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.Text = tostring(text)
        b.Parent = f
        task.delay(dur, function()
            pcall(function() sg:Destroy() end)
        end)
    end)
    if not ok then
        print("[AutoPiano]", title, text)
    end
end

local function clickSound()
    pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = "rbxassetid://6493287948"
        s.Volume = 0.08
        s.Parent = LP.Character or LP
        s:Play()
        game:GetService("Debris"):AddItem(s, 2)
    end)
end

-- key maps (Virtual Piano QWERTY)
local shiftKeys = {
    ["!"]=true,["@"]=true,["#"]=true,["$"]=true,["%"]=true,["^"]=true,
    ["&"]=true,["*"]=true,["("]=true,[")"]=true,
    ["Q"]=true,["W"]=true,["E"]=true,["R"]=true,["T"]=true,["Y"]=true,
    ["U"]=true,["I"]=true,["O"]=true,["P"]=true,
    ["A"]=true,["S"]=true,["D"]=true,["F"]=true,["G"]=true,["H"]=true,
    ["J"]=true,["K"]=true,["L"]=true,
    ["Z"]=true,["X"]=true,["C"]=true,["V"]=true,["B"]=true,["N"]=true,["M"]=true,
}

local keyMap = {
    ["1"]=Enum.KeyCode.One,["!"]=Enum.KeyCode.One,
    ["2"]=Enum.KeyCode.Two,["@"]=Enum.KeyCode.Two,
    ["3"]=Enum.KeyCode.Three,["#"]=Enum.KeyCode.Three,
    ["4"]=Enum.KeyCode.Four,["$"]=Enum.KeyCode.Four,
    ["5"]=Enum.KeyCode.Five,["%"]=Enum.KeyCode.Five,
    ["6"]=Enum.KeyCode.Six,["^"]=Enum.KeyCode.Six,
    ["7"]=Enum.KeyCode.Seven,["&"]=Enum.KeyCode.Seven,
    ["8"]=Enum.KeyCode.Eight,["*"]=Enum.KeyCode.Eight,
    ["9"]=Enum.KeyCode.Nine,["("]=Enum.KeyCode.Nine,
    ["0"]=Enum.KeyCode.Zero,[")"]=Enum.KeyCode.Zero,
    ["q"]=Enum.KeyCode.Q,["Q"]=Enum.KeyCode.Q,
    ["w"]=Enum.KeyCode.W,["W"]=Enum.KeyCode.W,
    ["e"]=Enum.KeyCode.E,["E"]=Enum.KeyCode.E,
    ["r"]=Enum.KeyCode.R,["R"]=Enum.KeyCode.R,
    ["t"]=Enum.KeyCode.T,["T"]=Enum.KeyCode.T,
    ["y"]=Enum.KeyCode.Y,["Y"]=Enum.KeyCode.Y,
    ["u"]=Enum.KeyCode.U,["U"]=Enum.KeyCode.U,
    ["i"]=Enum.KeyCode.I,["I"]=Enum.KeyCode.I,
    ["o"]=Enum.KeyCode.O,["O"]=Enum.KeyCode.O,
    ["p"]=Enum.KeyCode.P,["P"]=Enum.KeyCode.P,
    ["a"]=Enum.KeyCode.A,["A"]=Enum.KeyCode.A,
    ["s"]=Enum.KeyCode.S,["S"]=Enum.KeyCode.S,
    ["d"]=Enum.KeyCode.D,["D"]=Enum.KeyCode.D,
    ["f"]=Enum.KeyCode.F,["F"]=Enum.KeyCode.F,
    ["g"]=Enum.KeyCode.G,["G"]=Enum.KeyCode.G,
    ["h"]=Enum.KeyCode.H,["H"]=Enum.KeyCode.H,
    ["j"]=Enum.KeyCode.J,["J"]=Enum.KeyCode.J,
    ["k"]=Enum.KeyCode.K,["K"]=Enum.KeyCode.K,
    ["l"]=Enum.KeyCode.L,["L"]=Enum.KeyCode.L,
    ["z"]=Enum.KeyCode.Z,["Z"]=Enum.KeyCode.Z,
    ["x"]=Enum.KeyCode.X,["X"]=Enum.KeyCode.X,
    ["c"]=Enum.KeyCode.C,["C"]=Enum.KeyCode.C,
    ["v"]=Enum.KeyCode.V,["V"]=Enum.KeyCode.V,
    ["b"]=Enum.KeyCode.B,["B"]=Enum.KeyCode.B,
    ["n"]=Enum.KeyCode.N,["N"]=Enum.KeyCode.N,
    ["m"]=Enum.KeyCode.M,["M"]=Enum.KeyCode.M,
}

local noteMap = {
    ["C"]  = {[1]="1",[2]="8",[3]="t",[4]="s",[5]="l",[6]="m"},
    ["C#"] = {[1]="!",[2]="*",[3]="T",[4]="S",[5]="L"},
    ["D"]  = {[1]="2",[2]="9",[3]="y",[4]="d",[5]="z"},
    ["D#"] = {[1]="@",[2]="(",[3]="Y",[4]="D",[5]="Z"},
    ["E"]  = {[1]="3",[2]="0",[3]="u",[4]="f",[5]="x"},
    ["F"]  = {[1]="4",[2]="q",[3]="i",[4]="g",[5]="c"},
    ["F#"] = {[1]="$",[2]="Q",[3]="I",[4]="G",[5]="C"},
    ["G"]  = {[1]="5",[2]="w",[3]="o",[4]="h",[5]="v"},
    ["G#"] = {[1]="%",[2]="W",[3]="O",[4]="H",[5]="V"},
    ["A"]  = {[1]="6",[2]="e",[3]="p",[4]="j",[5]="b"},
    ["A#"] = {[1]="^",[2]="E",[3]="P",[4]="J",[5]="B"},
    ["B"]  = {[1]="7",[2]="r",[3]="a",[4]="k",[5]="n"},
}

local function holdTime(beats, useBpm)
    if type(beats) ~= "number" then
        return math.random(5, 12) / 100 -- short note
    end
    local t = (beats / (useBpm or bpm or 120)) * 60
    return math.max(0.04, t * 0.85)
end

local function pressOne(key, beats, useBpm)
    if _G.STOPIT then return end
    local code = keyMap[key]
    if not code then return end
    local needShift = shiftKeys[key] == true
    if needShift then
        VIM:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
    end
    VIM:SendKeyEvent(true, code, false, game)
    task.wait(holdTime(beats, useBpm))
    VIM:SendKeyEvent(false, code, false, game)
    if needShift then
        VIM:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
    end
end

local function pressKeys(keys, beats, useBpm)
    if _G.STOPIT or type(keys) ~= "string" then return end
    local ctrl = false
    if keys:sub(1, 5) == "Ctrl+" then
        ctrl = true
        keys = keys:sub(6)
    end
    for i = 1, #keys do
        local key = keys:sub(i, i)
        task.spawn(function()
            if _G.STOPIT then return end
            if ctrl then
                VIM:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
            end
            pressOne(key, beats, useBpm)
            if ctrl then
                VIM:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
            end
        end)
        if errormargin and errormargin > 0 and math.random() < 0.4 then
            task.wait(math.random() * errormargin / 3)
        end
    end
end

-- ===== Public API (used by song scripts) =====

function keypress(keys, beats, useBpm)
    if _G.STOPIT then return end
    if pausing then resumeEvent.Event:Wait() end
    task.spawn(function()
        if _G.STOPIT then return end
        pressKeys(keys, beats, useBpm or bpm)
    end)
end

function rest(beats, useBpm)
    if _G.STOPIT then return end
    if pausing then resumeEvent.Event:Wait() end
    local t = (tonumber(beats) or 0) / (useBpm or bpm or 120) * 60
    if _G.SEEK_SECONDS and _G.SEEK_SECONDS > 0 then
        if _G.SEEK_SECONDS >= t then
            _G.SEEK_SECONDS = _G.SEEK_SECONDS - t
            return
        end
        t = t - _G.SEEK_SECONDS
        _G.SEEK_SECONDS = 0
    end
    if t > 0 then
        task.wait(t)
    end
end

function finishedSong()
    if _G.STOPIT then return end
    clickSound()
    notify("Done", "Song finished.", 2)
    _G.STOPIT = true
    _G.songisplaying = false
    songisplaying = false
    if _G.APControls then
        pcall(function() _G.APControls:Destroy() end)
        _G.APControls = nil
    end
end

function pressnote(note, octave, beats, useBpm)
    local key = noteMap[note] and noteMap[note][octave]
    if key then
        keypress(key, beats, useBpm)
    end
end

function keysequence16(keys, beats, useBpm)
    for i = 1, #keys do
        if _G.STOPIT then return end
        keypress(keys:sub(i, i), beats, useBpm)
        rest(0.25, useBpm)
    end
end

function adjustVelocity(vel)
    -- optional: virtual piano velocity via Alt+key; skip if unwanted
end

function pedalDown()
    if _G.STOPIT then return end
    VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
end

function pedalUp()
    if _G.STOPIT then return end
    VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
end

function stopPlayingSongs()
    _G.STOPIT = true
    _G.songisplaying = false
    songisplaying = false
    clickSound()
    notify("Stop", "Stopped.", 1)
    if _G.APControls then
        pcall(function() _G.APControls:Destroy() end)
        _G.APControls = nil
    end
end

-- ===== Control UI =====
pcall(function()
    local old = CoreGui:FindFirstChild("APControls")
    if old then old:Destroy() end
end)

local guiParent = CoreGui
pcall(function()
    if not guiParent then
        guiParent = LP:WaitForChild("PlayerGui")
    end
end)

local sg = Instance.new("ScreenGui")
sg.Name = "APControls"
sg.ResetOnSpawn = false
sg.DisplayOrder = 120
sg.Parent = guiParent
_G.APControls = sg

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 110)
frame.Position = UDim2.new(0.5, -160, 0.75, 0)
frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
frame.BorderSizePixel = 0
frame.Parent = sg
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 120, 160)
stroke.Thickness = 1.2
stroke.Transparency = 0.35

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -16, 0, 22)
title.Position = UDim2.new(0, 10, 0, 6)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "AutoPiano  |  BPM " .. tostring(bpm)
title.Parent = frame

local function mkBtn(text, x, w, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 36)
    b.Position = UDim2.new(0, x, 0, 40)
    b.BackgroundColor3 = Color3.fromRGB(48, 48, 56)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    b.MouseButton1Click:Connect(callback)
    return b
end

mkBtn("Pause", 10, 70, function()
    pausing = not pausing
    if not pausing then
        resumeEvent:Fire()
        notify("Resume", "Playing", 1)
    else
        notify("Pause", "Paused", 1)
    end
    clickSound()
end)

mkBtn("Stop", 90, 70, function()
    stopPlayingSongs()
end)

mkBtn("<< 5s", 170, 60, function()
    _G.SEEK_SECONDS = math.max(0, (_G.SEEK_SECONDS or 0) - 5)
    notify("Seek", "-5s", 1)
    clickSound()
end)

mkBtn(">> 5s", 240, 60, function()
    _G.SEEK_SECONDS = (_G.SEEK_SECONDS or 0) + 5
    notify("Seek", "+5s", 1)
    clickSound()
end)

-- drag
do
    local dragging, start, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            start = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - start
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

notify("Play", "Engine ready", 1)
print("[AutoPiano] Engine loaded. BPM=", bpm)

]=]

-- Try load local engine content if running from same host later; for now use remote fallback in play.

-- ========== Song catalog (url = sheet name on host) ==========
-- url field is used directly: .../SONGS/{url}
local SONG_DATA = {
    { name = "INTERSTELLAR",           bpm = "104", url = "INTERSTELLAR",              cat = {"epic", "beautiful"} },
    { name = "RUSH E",                 bpm = "80",  url = "RUSH_E",                    cat = {"memes"} },
    { name = "GOLDEN HOUR",            bpm = "94",  url = "GOLDEN_HOUR",               cat = {"beautiful", "best"} },
    { name = "CUPID",                  bpm = "120", url = "CUPID",                     cat = {"pop/hiphop"} },
    { name = "RAT DANCE",              bpm = "120", url = "RAT_DANCE",                 cat = {"memes"} },
    { name = "RUNAWAY",                bpm = "85",  url = "RUNAWAY",                   cat = {"pop/hiphop"} },
    { name = "YOUR REALITY",           bpm = "105", url = "YOUR_REALITY",              cat = {"video games", "beautiful", "best"} },
    { name = "ANOTHER LOVE",           bpm = "123", url = "ANOTHER_LOVE",              cat = {"sad", "best", "epic", "beautiful"} },
    { name = "FINAL DUET",             bpm = "84",  url = "FINAL_DUET",                cat = {"video games"} },
    { name = "EXPERIENCE",             bpm = "92",  url = "EXPERIENCE",                cat = {"epic", "best", "beautiful", "peak"} },
    { name = "CAN YOU HEAR THE MUSIC", bpm = "80",  url = "CAN_YOU_HEAR_THE_FUCKING_MUSIC", cat = {"epic"} },
    { name = "HOWLS MOVING CASTLE",   bpm = "156", url = "HOWLS_MOVING_CASTLE",      cat = {"anime/jpop", "beautiful"} },
    { name = "YOUNG GIRL A",           bpm = "130", url = "YOUNG_GIRL_A",              cat = {"anime/jpop", "sad", "beautiful", "best"} },
    { name = "ARIA MATH",              bpm = "84",  url = "ARIA_MATH",                 cat = {"video games", "minecraft", "beautiful"} },
    { name = "ALL MY FELLAS",          bpm = "160", url = "ALL_MY_FELLAS",             cat = {"memes"} },
    { name = "THICK OF IT",            bpm = "146", url = "THICK_OF_IT",               cat = {"memes"} },
    { name = "ROMANTIC HOMICIDE",      bpm = "132", url = "ROMANTIC_HOMICIDE",         cat = {"sad"} },
    { name = "IF I AM WITH YOU",       bpm = "82",  url = "IF_I_AM_WITH_YOU",          cat = {"anime/jpop", "best", "beautiful", "peak"} },
    { name = "CRADLES",                bpm = "79",  url = "CRADLES",                   cat = {"electronic"} },
    { name = "IDOL",                   bpm = "166", url = "IDOL",                      cat = {"anime/jpop", "best"} },
    { name = "RIVER FLOWS IN YOU",     bpm = "137", url = "RIVER_FLOWS_IN_YOU",        cat = {"sad"} },
    { name = "NOCTURNE",               bpm = "62",  url = "NOCTURNE",                  cat = {"classical", "best"} },
    { name = "ISABELLA'S LULLABY",     bpm = "112", url = "ISABELLAS_LULLABY",         cat = {"video games"} },
    { name = "GIORNO",                 bpm = "135", url = "GIORNO",                    cat = {"anime/jpop", "memes"} },
    { name = "NEVER GONNA GIVE YOU UP",bpm = "113", url = "GIVE_UP",                   cat = {"memes", "pop/hiphop"} },
    { name = "UNRAVEL",                bpm = "135", url = "UNRAVEL",                   cat = {"anime/jpop", "beautiful"} },
    { name = "SWEATER WEATHER",        bpm = "124", url = "SWEATER_WEATHER",           cat = {"sad"} },
    { name = "VIVA LA VIDA",           bpm = "138", url = "VIVA_LA_VIDA",              cat = {"epic"} },
    { name = "HOPES AND DREAMS",       bpm = "170", url = "HOPES_DREAMS",              cat = {"video games", "undertale", "best", "epic", "peak"} },
    { name = "UNDERTALE",              bpm = "100", url = "UNDERTALE",                 cat = {"video games", "undertale", "best", "epic"} },
    { name = "MEGALOVANIA",            bpm = "120", url = "MEGALOVANIA",               cat = {"video games", "undertale", "memes"} },
    { name = "SPIDER DANCE",           bpm = "115", url = "SPIDER_DANCE",              cat = {"video games", "undertale"} },
    { name = "BAD APPLE!!",            bpm = "138", url = "BAD_APPLE",                 cat = {"anime/jpop", "popular"} },
    { name = "FADED",                  bpm = "90",  url = "FADED",                     cat = {"electronic"} },
    { name = "DESPACITO",              bpm = "89",  url = "DESPACITO",                 cat = {"pop/hiphop"} },
    { name = "BLINDING LIGHTS",        bpm = "171", url = "BLINDING_LIGHTS",           cat = {"pop/hiphop"} },
    { name = "AS IT WAS",              bpm = "174", url = "AS_IT_WAS",                 cat = {"pop/hiphop"} },
    { name = "DIE WITH A SMILE",       bpm = "152", url = "DIE_WITH",                  cat = {"pop/hiphop"} },
    { name = "BIRDS OF A FEATHER",     bpm = "105", url = "BIRDS_OF_A",                cat = {"pop/hiphop"} },
    { name = "SWEDEN",                 bpm = "44",  url = "SWEDEN",                    cat = {"video games", "minecraft"} },
    { name = "WET HANDS",              bpm = "74",  url = "WET_HANDS",                 cat = {"video games", "minecraft", "beautiful"} },
    { name = "DRY HANDS",              bpm = "90",  url = "DRY_HANDS",                 cat = {"video games", "minecraft", "beautiful"} },
    { name = "CANON IN D",             bpm = "60",  url = "CANON_D",                   cat = {"classical"} },
    { name = "CARELESS WHISPER",       bpm = "77",  url = "CARELESS",                  cat = {"pop/hiphop"} },
    { name = "ENTRY OF THE GLADIATORS",bpm = "140", url = "ENTRY_OF_THE",              cat = {"classical", "memes"} },
    { name = "AT THE SPEED OF LIGHT",  bpm = "162", url = "SPEED_OF",                  cat = {"video games", "electronic", "epic", "best", "peak"} },
    { name = "A SKY FULL OF STARS",    bpm = "125", url = "A_SKY_FULL",                cat = {"pop/hiphop"} },
    { name = "AFTER DARK",             bpm = "140", url = "AFTER_DARK",                cat = {"sad"} },
    { name = "DEATH BED",              bpm = "72",  url = "DEATH_BED",                 cat = {"sad"} },
    { name = "FALLEN DOWN",            bpm = "110", url = "FALLEN_DOWN",               cat = {"video games", "undertale"} },
    { name = "HIS THEME",              bpm = "90",  url = "HIS_THEME",                 cat = {"video games", "undertale"} },
}

-- ========== GUI ==========
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoPianoUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LP:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Name = "frame"
frame.Parent = ScreenGui
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
frame.BorderSizePixel = 0
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Size = UDim2.new(0, 520, 0, 360)
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 140, 170)
stroke.Thickness = 1.5
stroke.Transparency = 0.4

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = Color3.fromRGB(255, 120, 160)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 16)
titleFix.Position = UDim2.new(0, 0, 1, -16)
titleFix.BackgroundColor3 = Color3.fromRGB(255, 120, 160)
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 16, 0, 0)
title.Font = Enum.Font.GothamBold
title.Text = "AutoPiano"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 28, 0, 28)
closeButton.Position = UDim2.new(1, -36, 0, 8)
closeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 14
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Parent = titleBar
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)
closeButton.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

local infoButton = Instance.new("TextButton")
infoButton.Size = UDim2.new(0, 28, 0, 28)
infoButton.Position = UDim2.new(1, -70, 0, 8)
infoButton.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
infoButton.Text = "?"
infoButton.Font = Enum.Font.GothamBold
infoButton.TextSize = 14
infoButton.TextColor3 = Color3.fromRGB(255, 255, 255)
infoButton.Parent = titleBar
Instance.new("UICorner", infoButton).CornerRadius = UDim.new(0, 6)
infoButton.MouseButton1Click:Connect(function()
    NotificationLibrary:SendNotification("Info", "Select a song → set BPM → Play. Custom songs in AUTOPIANO_CUSTOM_SONGS.", 4)
end)

-- Categories
local categoriesFrame = Instance.new("ScrollingFrame")
categoriesFrame.Name = "categoriesFrame"
categoriesFrame.Parent = frame
categoriesFrame.BackgroundTransparency = 1
categoriesFrame.Position = UDim2.new(0, 10, 0, 54)
categoriesFrame.Size = UDim2.new(0, 110, 0, 240)
categoriesFrame.ScrollBarThickness = 3
categoriesFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
categoriesFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

local categoriesLayout = Instance.new("UIListLayout")
categoriesLayout.Parent = categoriesFrame
categoriesLayout.SortOrder = Enum.SortOrder.LayoutOrder
categoriesLayout.Padding = UDim.new(0, 6)
categoriesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local categoriesPadding = Instance.new("UIPadding")
categoriesPadding.Parent = categoriesFrame
categoriesPadding.PaddingTop = UDim.new(0, 4)
categoriesPadding.PaddingBottom = UDim.new(0, 4)

-- Song list
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "scroll"
scroll.Parent = frame
scroll.BackgroundTransparency = 1
scroll.Position = UDim2.new(0, 128, 0, 54)
scroll.Size = UDim2.new(0, 220, 0, 240)
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = scroll
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)

local listPad = Instance.new("UIPadding")
listPad.Parent = scroll
listPad.PaddingTop = UDim.new(0, 8)
listPad.PaddingBottom = UDim.new(0, 8)

-- Search
local searchbar = Instance.new("TextBox")
searchbar.Name = "searchbar"
searchbar.Parent = scroll
searchbar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
searchbar.Size = UDim2.new(0, 200, 0, 28)
searchbar.Font = Enum.Font.Gotham
searchbar.PlaceholderText = "Search..."
searchbar.Text = ""
searchbar.TextColor3 = Color3.fromRGB(255, 255, 255)
searchbar.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
searchbar.TextSize = 14
searchbar.LayoutOrder = 0
Instance.new("UICorner", searchbar).CornerRadius = UDim.new(0, 6)

-- Right control bar
local bar = Instance.new("Frame")
bar.Name = "bar"
bar.Parent = frame
bar.BackgroundTransparency = 1
bar.Position = UDim2.new(1, -160, 0, 54)
bar.Size = UDim2.new(0, 148, 0, 240)

local barlist = Instance.new("UIListLayout")
barlist.Parent = bar
barlist.SortOrder = Enum.SortOrder.LayoutOrder
barlist.Padding = UDim.new(0, 10)
barlist.HorizontalAlignment = Enum.HorizontalAlignment.Center

local barpadding = Instance.new("UIPadding")
barpadding.Parent = bar
barpadding.PaddingTop = UDim.new(0, 8)

local songname = Instance.new("TextLabel")
songname.Name = "songname"
songname.Parent = bar
songname.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
songname.Size = UDim2.new(0, 130, 0, 40)
songname.Font = Enum.Font.GothamBold
songname.Text = "Select a song"
songname.TextColor3 = Color3.fromRGB(255, 255, 255)
songname.TextSize = 13
songname.TextWrapped = true
songname.LayoutOrder = 1
Instance.new("UICorner", songname).CornerRadius = UDim.new(0, 8)

local bpmbox = Instance.new("TextBox")
bpmbox.Name = "bpmbox"
bpmbox.Parent = bar
bpmbox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
bpmbox.Size = UDim2.new(0, 100, 0, 28)
bpmbox.Font = Enum.Font.Gotham
bpmbox.PlaceholderText = "BPM"
bpmbox.Text = ""
bpmbox.TextColor3 = Color3.fromRGB(255, 255, 255)
bpmbox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
bpmbox.TextSize = 14
bpmbox.LayoutOrder = 2
Instance.new("UICorner", bpmbox).CornerRadius = UDim.new(0, 6)

local playsong = Instance.new("TextButton")
playsong.Name = "playsong"
playsong.Parent = bar
playsong.BackgroundColor3 = Color3.fromRGB(255, 120, 160)
playsong.Size = UDim2.new(0, 130, 0, 36)
playsong.Font = Enum.Font.GothamBold
playsong.Text = "Play"
playsong.TextColor3 = Color3.fromRGB(255, 255, 255)
playsong.TextSize = 18
playsong.LayoutOrder = 3
Instance.new("UICorner", playsong).CornerRadius = UDim.new(0, 8)

local addSongBtn = Instance.new("TextButton")
addSongBtn.Name = "addSongBtn"
addSongBtn.Parent = bar
addSongBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 68)
addSongBtn.Size = UDim2.new(0, 130, 0, 30)
addSongBtn.Font = Enum.Font.Gotham
addSongBtn.Text = "Add Song"
addSongBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
addSongBtn.TextSize = 13
addSongBtn.LayoutOrder = 4
Instance.new("UICorner", addSongBtn).CornerRadius = UDim.new(0, 6)

local playRandomBtn = Instance.new("TextButton")
playRandomBtn.Name = "playRandomBtn"
playRandomBtn.Parent = bar
playRandomBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 68)
playRandomBtn.Size = UDim2.new(0, 130, 0, 28)
playRandomBtn.Font = Enum.Font.Gotham
playRandomBtn.Text = "Random"
playRandomBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
playRandomBtn.TextSize = 13
playRandomBtn.LayoutOrder = 5
Instance.new("UICorner", playRandomBtn).CornerRadius = UDim.new(0, 6)

-- Drag main frame
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- ========== Songs state ==========
local songs = {} -- { button, bpm, var, url, cat, name }
local songisplaying = false
local activeCategory = "all"

local function disable()
    for _, s in ipairs(songs) do
        s.var = false
        if s.button then
            s.button.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        end
    end
end

local function newSongButton(displayName)
    local button = Instance.new("TextButton")
    button.Name = displayName
    button.Parent = scroll
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    button.Size = UDim2.new(0, 200, 0, 32)
    button.Font = Enum.Font.Gotham
    button.Text = displayName
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 13
    button.TextTruncate = Enum.TextTruncate.AtEnd
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    return button
end

-- Build song buttons from SONG_DATA
for _, data in ipairs(SONG_DATA) do
    local btn = newSongButton(data.name)
    local entry = {
        button = btn,
        bpm = data.bpm,
        var = false,
        url = data.url,
        cat = data.cat or {},
        name = data.name,
    }
    table.insert(songs, entry)
    btn.MouseButton1Click:Connect(function()
        disable()
        entry.var = true
        btn.BackgroundColor3 = Color3.fromRGB(255, 120, 160)
        songname.Text = data.name
        bpmbox.Text = data.bpm
        playSound(6493287948, 0.08)
    end)
end

-- Categories chips
local ALL_CATS = {"all", "epic", "beautiful", "best", "peak", "sad", "memes", "anime/jpop", "video games", "minecraft", "undertale", "pop/hiphop", "electronic", "classical", "custom"}
local catButtons = {}

local function setCategory(cat)
    activeCategory = cat
    for name, b in pairs(catButtons) do
        b.BackgroundColor3 = (name == cat) and Color3.fromRGB(255, 120, 160) or Color3.fromRGB(45, 45, 55)
    end
    -- filter
    local q = searchbar.Text:lower()
    for _, s in ipairs(songs) do
        local matchCat = (cat == "all")
        if not matchCat then
            for _, c in ipairs(s.cat) do
                if c == cat then matchCat = true break end
            end
        end
        local matchSearch = (q == "") or s.name:lower():find(q, 1, true) or (s.url and s.url:lower():find(q, 1, true))
        s.button.Visible = matchCat and matchSearch
    end
end

for _, cat in ipairs(ALL_CATS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 98, 0, 26)
    b.BackgroundColor3 = (cat == "all") and Color3.fromRGB(255, 120, 160) or Color3.fromRGB(45, 45, 55)
    b.Text = cat
    b.Font = Enum.Font.Gotham
    b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Parent = categoriesFrame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    catButtons[cat] = b
    b.MouseButton1Click:Connect(function()
        setCategory(cat)
    end)
end

searchbar:GetPropertyChangedSignal("Text"):Connect(function()
    setCategory(activeCategory)
end)

-- ========== Play flow (exact order per spec) ==========
local function loadEngine()
    if type(_G.__AP_ENGINE_SRC) == "string" and #_G.__AP_ENGINE_SRC > 200 and not _G.__AP_ENGINE_SRC:find("placeholder") then
        loadstring(_G.__AP_ENGINE_SRC)()
    else
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Linh-1205/autopiano/main/engine.lua", true))()
    end
end

local function playbuttonclicked()
    if songisplaying or _G.songisplaying then
        playSound(6493287948, 0.1)
        NotificationLibrary:SendNotification("Error", "A song is already playing.", 1)
        return
    end

    local bpmVal = tonumber(bpmbox.Text)
    if not bpmVal or bpmVal <= 0 then
        playSound(6493287948, 0.1)
        NotificationLibrary:SendNotification("Error", "Invalid BPM.", 2)
        return
    end
    bpm = bpmVal

    local selected = nil
    for _, song in ipairs(songs) do
        if song.var == true then
            selected = song
            break
        end
    end
    if not selected then
        playSound(6493287948, 0.1)
        NotificationLibrary:SendNotification("Error", "Select a song first.", 2)
        return
    end

    -- Resolve song script: custom local OR remote sheet
    local songscript
    if selected.custom and selected.script then
        songscript = selected.script
    else
        local ok, res = pcall(function()
            return game:HttpGet("https://hellohellohell0.com/talentless-raw/SONGS/" .. tostring(selected.url), true)
        end)
        if ok and type(res) == "string" and #res > 10 then
            songscript = res
        end
    end
    if not songscript then
        playSound(6493287948, 0.1)
        NotificationLibrary:SendNotification("Error", "Song data not found: " .. tostring(selected.url or selected.name), 3)
        return
    end

    songisplaying = true
    _G.songisplaying = true
    _G.STOPIT = false

    local okE, errE = pcall(loadEngine)
    if not okE then
        songisplaying = false
        _G.songisplaying = false
        NotificationLibrary:SendNotification("Error", "Engine failed to load.", 3)
        warn("[AutoPiano] engine:", errE)
        return
    end

    print("[AutoPiano] Playing:", selected.name, "len=", #songscript, "BPM=", bpm)
    local okS, errS = pcall(function()
        loadstring(songscript)()
    end)
    if not okS then
        songisplaying = false
        _G.songisplaying = false
        _G.STOPIT = true
        NotificationLibrary:SendNotification("Error", "Song script error.", 3)
        warn("[AutoPiano] song:", errS)
    end
end

playsong.MouseButton1Click:Connect(playbuttonclicked)

playRandomBtn.MouseButton1Click:Connect(function()
    if #songs == 0 then return end
    local r = songs[math.random(1, #songs)]
    disable()
    r.var = true
    r.button.BackgroundColor3 = Color3.fromRGB(255, 120, 160)
    songname.Text = r.name
    bpmbox.Text = r.bpm
    playbuttonclicked()
end)

addSongBtn.MouseButton1Click:Connect(function()
    pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Linh-1205/autopiano/main/add_song.lua", true))()
    end)
end)

-- ========== Custom songs ==========
function updateSongs()
    if not (isfolder and listfiles and readfile) then return end
    local folders = {"AUTOPIANO_CUSTOM_SONGS", "TALENTLESS_CUSTOM_SONGS"}
    for _, folder in ipairs(folders) do
        if isfolder(folder) then
            for _, filepath in ipairs(listfiles(folder)) do
                local path = tostring(filepath)
                if path:match("%.txt$") and not path:match("_categories") then
                    local fname = path:match("([^/\\]+)%.txt$") or "Custom"
                    local already = false
                    for _, s in ipairs(songs) do
                        if s.name == fname and s.custom then already = true break end
                    end
                    if not already then
                        local content = readfile(path)
                        local cat = {"custom"}
                        local catLine = content:match("^%-%-CAT:(%S+)")
                        if catLine then cat = {catLine} end
                        local btn = newSongButton(fname)
                        local entry = {
                            button = btn,
                            bpm = "120",
                            var = false,
                            url = nil,
                            cat = cat,
                            name = fname,
                            custom = true,
                            script = content,
                        }
                        table.insert(songs, entry)
                        btn.MouseButton1Click:Connect(function()
                            disable()
                            entry.var = true
                            btn.BackgroundColor3 = Color3.fromRGB(255, 120, 160)
                            songname.Text = fname
                            bpmbox.Text = entry.bpm
                        end)
                    end
                end
            end
        end
    end
end

task.defer(updateSongs)

print("[AutoPiano] UI ready - select a song then press Play")
NotificationLibrary:SendNotification("Success", "AutoPiano ready", 2)
