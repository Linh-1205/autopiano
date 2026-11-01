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

-- minimal notif
local function notify(title, text, dur)
    dur = dur or 2
    local ok, gui = pcall(function()
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
        return sg
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

-- key maps (virtual piano QWERTY)
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
