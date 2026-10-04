-- MIDI2LUA timeline loader
-- Timeline playback + seek + pause + BPM + velocity + sustain
-- Key handling intentionally does NOT randomly apply Shift.
--
-- IMPORTANT:
-- "d" -> D key WITHOUT Shift
-- "D" -> D key WITH Shift
--
-- Repeated notes such as:
-- d d p
-- p p
-- l l
-- are handled with per-key generations so an old key-up
-- cannot cancel a newer retrigger.

_G.STOPIT = false

local NotificationLibrary =
    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/hellohellohell012321/TALENTLESS/main/notif_lib.lua"
    ))()

local UserInputService =
    game:GetService("UserInputService")

local VirtualInputManager =
    game:GetService("VirtualInputManager")

local Players =
    game:GetService("Players")

local LocalPlayer =
    Players.LocalPlayer

local function playSound(soundId, loudness)
    local sound = Instance.new("Sound")

    sound.SoundId =
        "rbxassetid://" .. tostring(soundId)

    sound.Parent =
        LocalPlayer.Character or LocalPlayer

    sound.Volume =
        loudness or 1

    sound:Play()

    task.delay(3, function()
        if sound then
            sound:Destroy()
        end
    end)
end

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Linh-1205/autopiano/refs/heads/main/load.lua",
    true
))()

task.wait(0.3)

playSound("6493287948", 0.1)

NotificationLibrary:SendNotification(
    "Success",
    "Timeline player loaded.",
    1
)

-- ================================================================
-- GLOBAL STATE
-- ================================================================

local songPlaying = false
local pausing = false
local timelineReady = false

local timeline = {}
local totalBeats = 0

local currentBeat = 0
local currentEventIndex = 1

local playbackToken = 0
local playbackThreadRunning = false

local draggingWindow = false
local dragInput = nil
local dragStart = nil
local startPosition = nil

local seeking = false
local resumeAfterSeek = false

local runtimeLastVelocity = nil

local errormargin =
    tonumber(errormargin) or 0

bpm =
    tonumber(bpm) or 120

if bpm <= 0 then
    bpm = 120
end

-- ================================================================
-- GUI
-- ================================================================

local lilgui =
    Instance.new("ScreenGui")

lilgui.Name =
    "MIDI2LUAPlayer"

lilgui.ZIndexBehavior =
    Enum.ZIndexBehavior.Sibling

lilgui.ResetOnSpawn =
    false

lilgui.Parent =
    game:GetService("CoreGui")

local fram =
    Instance.new("Frame")

fram.Name =
    "Player"

fram.Parent =
    lilgui

fram.Size =
    UDim2.new(0, 430, 0, 185)

fram.Position =
    UDim2.new(0.5, -215, 0.5, -92)

fram.BackgroundColor3 =
    Color3.fromRGB(30, 30, 30)

fram.BorderSizePixel =
    0

local corner =
    Instance.new("UICorner")

corner.CornerRadius =
    UDim.new(0, 8)

corner.Parent =
    fram

local stroke =
    Instance.new("UIStroke")

stroke.Color =
    Color3.fromRGB(70, 70, 70)

stroke.Thickness =
    1

stroke.Parent =
    fram

-- ================================================================
-- TITLE
-- ================================================================

local title =
    Instance.new("TextLabel")

title.Parent =
    fram

title.BackgroundTransparency =
    1

title.Position =
    UDim2.new(0, 14, 0, 8)

title.Size =
    UDim2.new(1, -28, 0, 25)

title.Text =
    "MIDI2LUA Player"

title.TextColor3 =
    Color3.fromRGB(235, 235, 235)

title.TextSize =
    16

title.Font =
    Enum.Font.GothamBold

title.TextXAlignment =
    Enum.TextXAlignment.Left

-- ================================================================
-- BPM
-- ================================================================

local bpmtext =
    Instance.new("TextLabel")

bpmtext.Parent =
    fram

bpmtext.BackgroundTransparency =
    1

bpmtext.Position =
    UDim2.new(1, -125, 0, 10)

bpmtext.Size =
    UDim2.new(0, 110, 0, 22)

bpmtext.Text =
    "BPM: " .. tostring(bpm)

bpmtext.TextColor3 =
    Color3.fromRGB(190, 190, 190)

bpmtext.TextSize =
    13

bpmtext.Font =
    Enum.Font.Gotham

bpmtext.TextXAlignment =
    Enum.TextXAlignment.Right

-- ================================================================
-- TIME LABEL
-- ================================================================

local timeLabel =
    Instance.new("TextLabel")

timeLabel.Parent =
    fram

timeLabel.BackgroundTransparency =
    1

timeLabel.Position =
    UDim2.new(0, 14, 0, 38)

timeLabel.Size =
    UDim2.new(1, -28, 0, 20)

timeLabel.Text =
    "00:00 / 00:00"

timeLabel.TextColor3 =
    Color3.fromRGB(205, 205, 205)

timeLabel.TextSize =
    12

timeLabel.Font =
    Enum.Font.Gotham

timeLabel.TextXAlignment =
    Enum.TextXAlignment.Left

-- ================================================================
-- TIMELINE BAR
-- ================================================================

local timelineBar =
    Instance.new("Frame")

timelineBar.Parent =
    fram

timelineBar.Position =
    UDim2.new(0, 14, 0, 63)

timelineBar.Size =
    UDim2.new(1, -28, 0, 7)

timelineBar.BackgroundColor3 =
    Color3.fromRGB(65, 65, 65)

timelineBar.BorderSizePixel =
    0

local timelineCorner =
    Instance.new("UICorner")

timelineCorner.CornerRadius =
    UDim.new(1, 0)

timelineCorner.Parent =
    timelineBar

local timelineProgress =
    Instance.new("Frame")

timelineProgress.Parent =
    timelineBar

timelineProgress.Size =
    UDim2.new(0, 0, 1, 0)

timelineProgress.BackgroundColor3 =
    Color3.fromRGB(225, 225, 225)

timelineProgress.BorderSizePixel =
    0

local progressCorner =
    Instance.new("UICorner")

progressCorner.CornerRadius =
    UDim.new(1, 0)

progressCorner.Parent =
    timelineProgress

local timelineHandle =
    Instance.new("Frame")

timelineHandle.Parent =
    timelineBar

timelineHandle.AnchorPoint =
    Vector2.new(0.5, 0.5)

timelineHandle.Position =
    UDim2.new(0, 0, 0.5, 0)

timelineHandle.Size =
    UDim2.new(0, 13, 0, 13)

timelineHandle.BackgroundColor3 =
    Color3.fromRGB(245, 245, 245)

timelineHandle.BorderSizePixel =
    0

local handleCorner =
    Instance.new("UICorner")

handleCorner.CornerRadius =
    UDim.new(1, 0)

handleCorner.Parent =
    timelineHandle

-- ================================================================
-- BUTTON CREATOR
-- ================================================================

local function createButton(name, text, position, size)
    local button =
        Instance.new("TextButton")

    button.Name =
        name

    button.Parent =
        fram

    button.Position =
        position

    button.Size =
        size

    button.BackgroundColor3 =
        Color3.fromRGB(45, 45, 45)

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.TextColor3 =
        Color3.fromRGB(230, 230, 230)

    button.TextSize =
        12

    button.Font =
        Enum.Font.GothamMedium

    local buttonCorner =
        Instance.new("UICorner")

    buttonCorner.CornerRadius =
        UDim.new(0, 5)

    buttonCorner.Parent =
        button

    local buttonStroke =
        Instance.new("UIStroke")

    buttonStroke.Color =
        Color3.fromRGB(75, 75, 75)

    buttonStroke.Thickness =
        1

    buttonStroke.Parent =
        button

    return button
end

-- ================================================================
-- CONTROLS
-- ================================================================

local backButton =
    createButton(
        "Back",
        "-5s",
        UDim2.new(0, 14, 0, 82),
        UDim2.new(0, 65, 0, 30)
    )

local pausebutton =
    createButton(
        "Pause",
        "Pause",
        UDim2.new(0, 87, 0, 82),
        UDim2.new(0, 75, 0, 30)
    )

local forwardButton =
    createButton(
        "Forward",
        "+5s",
        UDim2.new(0, 170, 0, 82),
        UDim2.new(0, 65, 0, 30)
    )

local stopbutton =
    createButton(
        "Stop",
        "Stop",
        UDim2.new(0, 243, 0, 82),
        UDim2.new(0, 65, 0, 30)
    )

local restartButton =
    createButton(
        "Restart",
        "|<",
        UDim2.new(0, 316, 0, 82),
        UDim2.new(0, 45, 0, 30)
    )

-- ================================================================
-- BPM CONTROLS
-- ================================================================

local downbpm =
    createButton(
        "BPMDown",
        "-",
        UDim2.new(0, 14, 0, 120),
        UDim2.new(0, 35, 0, 27)
    )

local upbpm =
    createButton(
        "BPMUp",
        "+",
        UDim2.new(0, 55, 0, 120),
        UDim2.new(0, 35, 0, 27)
    )

local errorbox =
    Instance.new("TextLabel")

errorbox.Parent =
    fram

errorbox.BackgroundTransparency =
    1

errorbox.Position =
    UDim2.new(0, 105, 0, 120)

errorbox.Size =
    UDim2.new(0, 120, 0, 27)

errorbox.Text =
    "Error: 0.000"

errorbox.TextColor3 =
    Color3.fromRGB(180, 180, 180)

errorbox.TextSize =
    11

errorbox.Font =
    Enum.Font.Gotham

errorbox.TextXAlignment =
    Enum.TextXAlignment.Left

local less =
    createButton(
        "ErrorDown",
        "-",
        UDim2.new(0, 225, 0, 120),
        UDim2.new(0, 30, 0, 27)
    )

local more =
    createButton(
        "ErrorUp",
        "+",
        UDim2.new(0, 261, 0, 120),
        UDim2.new(0, 30, 0, 27)
    )

local statusLabel =
    Instance.new("TextLabel")

statusLabel.Parent =
    fram

statusLabel.BackgroundTransparency =
    1

statusLabel.Position =
    UDim2.new(0, 300, 0, 120)

statusLabel.Size =
    UDim2.new(0, 115, 0, 27)

statusLabel.Text =
    "Loading..."

statusLabel.TextColor3 =
    Color3.fromRGB(150, 150, 150)

statusLabel.TextSize =
    11

statusLabel.Font =
    Enum.Font.Gotham

statusLabel.TextXAlignment =
    Enum.TextXAlignment.Right

-- ================================================================
-- DRAG WINDOW
-- ================================================================

fram.InputBegan:Connect(function(input)
    if
        input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
    then
        draggingWindow = true

        dragStart =
            input.Position

        startPosition =
            fram.Position

        input.Changed:Connect(function()
            if input.UserInputState ==
                Enum.UserInputState.End
            then
                draggingWindow = false
            end
        end)
    end
end)

fram.InputChanged:Connect(function(input)
    if
        input.UserInputType ==
            Enum.UserInputType.MouseMovement
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
    then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if
        input == dragInput
        and draggingWindow
        and not seeking
    then
        local delta =
            input.Position - dragStart

        fram.Position =
            UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
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
-- IMPORTANT:
-- Lowercase letters are NEVER shifted.
-- Uppercase letters ARE shifted.
-- Numbers 1-0 are NOT shifted.
-- Symbols ! @ # etc ARE shifted.
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
-- This fixes:
--
-- d d p
--
-- Old:
-- d down
-- d down
-- d up
-- d up
--
-- New:
-- d #1 gets generation 1
-- d #2 gets generation 2
-- generation 1 is no longer allowed to release d
-- ================================================================

local keyGeneration = {}

local function getKeyId(key)
    return tostring(key)
end

local function createKeyGeneration(key)
    local id =
        getKeyId(key)

    keyGeneration[id] =
        (keyGeneration[id] or 0) + 1

    return keyGeneration[id]
end

local function isCurrentGeneration(key, generation)
    return
        keyGeneration[getKeyId(key)] ==
        generation
end

-- ================================================================
-- RELEASE ALL INPUT
-- ================================================================

local function releaseAllInputs()
    for _, keyCode in pairs(keyMappings) do
        pcall(function()
            VirtualInputManager:SendKeyEvent(
                false,
                keyCode,
                false,
                game
            )
        end)
    end

    pcall(function()
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftShift,
            false,
            game
        )
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftControl,
            false,
            game
        )
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftAlt,
            false,
            game
        )
    end)

    pcall(function()
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.Space,
            false,
            game
        )
    end)
end

-- ================================================================
-- NOTE HOLD TIME
-- ================================================================

local function getHoldTime(beats, isShort)
    if isShort then
        return math.random(4, 12) / 100
    end

    if
        type(beats) ~= "number"
        or beats <= 0
    then
        return 0.04
    end

    local safeBpm =
        math.max(
            tonumber(bpm) or 120,
            1
        )

    local noteTime =
        (beats / safeBpm) * 60

    local randomOff =
        math.random() *
        (noteTime / 2)

    return math.max(
        0.01,
        noteTime - randomOff
    )
end

-- ================================================================
-- PRESS ONE PHYSICAL KEY
-- ================================================================

local function pressSingleKey(
    key,
    beats,
    isShort,
    ctrlRequired
)
    if _G.STOPIT then
        return
    end

    local keyCode =
        keyMappings[key]

    if not keyCode then
        warn(
            "Unknown key mapping: " ..
            tostring(key)
        )
        return
    end

    local generation =
        createKeyGeneration(key)

    -- Always release the physical key first.
    -- This makes repeated same-key notes retrigger correctly.
    pcall(function()
        VirtualInputManager:SendKeyEvent(
            false,
            keyCode,
            false,
            game
        )
    end)

    local needsShift =
        shiftRequired[key] == true

    -- Ctrl is local to this exact keypress.
    if ctrlRequired then
        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.LeftControl,
            false,
            game
        )
    end

    -- Shift is local to this exact keypress.
    --
    -- Lowercase d DOES NOT enter here.
    -- Uppercase D DOES enter here.
    if needsShift then
        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.LeftShift,
            false,
            game
        )
    end

    VirtualInputManager:SendKeyEvent(
        true,
        keyCode,
        false,
        game
    )

    -- Immediately release modifiers.
    --
    -- We DO NOT keep Shift held.
    if needsShift then
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftShift,
            false,
            game
        )
    end

    if ctrlRequired then
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftControl,
            false,
            game
        )
    end

    local waitTime =
        getHoldTime(
            beats,
            isShort
        )

    task.wait(waitTime)

    if _G.STOPIT then
        pcall(function()
            VirtualInputManager:SendKeyEvent(
                false,
                keyCode,
                false,
                game
            )
        end)

        return
    end

    -- Only the newest press is allowed to release this key.
    if isCurrentGeneration(
        key,
        generation
    ) then
        VirtualInputManager:SendKeyEvent(
            false,
            keyCode,
            false,
            game
        )
    end
end

-- ================================================================
-- PRESS KEY / CHORD
-- ================================================================

local function pressKey(
    keys,
    beats,
    isShort
)
    if _G.STOPIT then
        return
    end

    keys =
        tostring(keys)

    local ctrlRequired =
        false

    if
        keys:sub(1, 5) ==
        "Ctrl+"
    then
        ctrlRequired = true
        keys = keys:sub(6)
    end

    for i = 1, #keys do
        local key =
            keys:sub(i, i)

        task.spawn(function()
            pressSingleKey(
                key,
                beats,
                isShort,
                ctrlRequired
            )
        end)

        if
            errormargin ~= 0
            and math.random() < 0.5
        then
            task.wait(
                math.random() *
                errormargin / 3
            )
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

    local velocityMap =
        "58qrupdhl"

    vel =
        math.clamp(
            tonumber(vel) or 0.5,
            0,
            1
        )

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

        index =
            math.clamp(
                index,
                1,
                #velocityMap
            )

        topress =
            velocityMap:sub(
                index,
                index
            )
    end

    local keyCode =
        keyMappings[topress]

    if not keyCode then
        return
    end

    VirtualInputManager:SendKeyEvent(
        true,
        Enum.KeyCode.LeftAlt,
        false,
        game
    )

    VirtualInputManager:SendKeyEvent(
        true,
        keyCode,
        false,
        game
    )

    VirtualInputManager:SendKeyEvent(
        false,
        keyCode,
        false,
        game
    )

    VirtualInputManager:SendKeyEvent(
        false,
        Enum.KeyCode.LeftAlt,
        false,
        game
    )
end

-- ================================================================
-- PEDAL
-- ================================================================

function pedalDown()
    if _G.STOPIT then
        return
    end

    VirtualInputManager:SendKeyEvent(
        true,
        Enum.KeyCode.Space,
        false,
        game
    )
end

function pedalUp()
    if _G.STOPIT then
        return
    end

    VirtualInputManager:SendKeyEvent(
        false,
        Enum.KeyCode.Space,
        false,
        game
    )
end

-- ================================================================
-- TIME FORMAT
-- ================================================================

local function formatTime(seconds)
    seconds =
        math.max(
            0,
            tonumber(seconds) or 0
        )

    local minutes =
        math.floor(
            seconds / 60
        )

    local secs =
        math.floor(
            seconds % 60
        )

    return string.format(
        "%02d:%02d",
        minutes,
        secs
    )
end

local function beatsToSeconds(beats)
    local safeBpm =
        math.max(
            tonumber(bpm) or 120,
            1
        )

    return
        (beats / safeBpm) * 60
end

-- ================================================================
-- TIMELINE UI
-- ================================================================

local function updateTimelineUI()
    if not timelineReady then
        return
    end

    local safeTotal =
        math.max(
            totalBeats,
            0.001
        )

    local ratio =
        math.clamp(
            currentBeat / safeTotal,
            0,
            1
        )

    timelineProgress.Size =
        UDim2.new(
            ratio,
            0,
            1,
            0
        )

    timelineHandle.Position =
        UDim2.new(
            ratio,
            0,
            0.5,
            0
        )

    timeLabel.Text =
        formatTime(
            beatsToSeconds(currentBeat)
        )
        .. " / " ..
        formatTime(
            beatsToSeconds(totalBeats)
        )

    bpmtext.Text =
        "BPM: " ..
        tostring(
            math.floor(
                tonumber(bpm) or 120
            )
        )

    errorbox.Text =
        string.format(
            "Error: %.3f",
            errormargin
        )
end

-- ================================================================
-- FIND EVENT INDEX
-- ================================================================

local function findEventIndex(beat)
    local low = 1
    local high = #timeline

    while low <= high do
        local mid =
            math.floor(
                (low + high) / 2
            )

        local event =
            timeline[mid]

        if event.t < beat then
            low = mid + 1
        else
            high = mid - 1
        end
    end

    return math.max(
        1,
        low
    )
end

-- ================================================================
-- RESTORE STATE WHEN SEEKING
-- ================================================================

local function restoreStateAtBeat(beat)
    local pedalState =
        false

    runtimeLastVelocity =
        nil

    for i = 1, #timeline do
        local event =
            timeline[i]

        if event.t >= beat then
            break
        end

        if event.p ~= nil then
            pedalState =
                event.p == 1
        elseif event.v ~= nil then
            runtimeLastVelocity =
                event.v
        end
    end

    if pedalState then
        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.Space,
            false,
            game
        )
    else
        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.Space,
            false,
            game
        )
    end
end

-- ================================================================
-- PROCESS EVENT
-- ================================================================

local function processEvent(event)
    if _G.STOPIT then
        return
    end

    if event.p ~= nil then
        if event.p == 1 then
            pedalDown()
        else
            pedalUp()
        end

        return
    end

    if event.v ~= nil then
        if
            runtimeLastVelocity == nil
            or
            math.abs(
                runtimeLastVelocity -
                event.v
            ) > 0.0001
        then
            adjustVelocity(
                event.v
            )

            runtimeLastVelocity =
                event.v
        end
    end

    if event.k ~= nil then
        pressKey(
            event.k,
            event.d,
            event.s == true
        )
    end
end

-- ================================================================
-- STOP PLAYBACK
-- ================================================================

local function invalidatePlayback()
    playbackToken =
        playbackToken + 1

    releaseAllInputs()
end

-- ================================================================
-- START PLAYBACK LOOP
-- ================================================================

local function startPlaybackLoop()
    if playbackThreadRunning then
        return
    end

    playbackThreadRunning =
        true

    local token =
        playbackToken

    task.spawn(function()
        local lastClock =
            os.clock()

        while
            token == playbackToken
            and not _G.STOPIT
            and songPlaying
        do
            if pausing then
                lastClock =
                    os.clock()

                task.wait(0.03)

            else
                local now =
                    os.clock()

                local delta =
                    now - lastClock

                lastClock =
                    now

                if delta < 0 then
                    delta = 0
                end

                currentBeat =
                    currentBeat +
                    (
                        delta *
                        math.max(
                            tonumber(bpm) or 120,
                            1
                        ) / 60
                    )

                while
                    currentEventIndex <=
                    #timeline
                    and
                    timeline[
                        currentEventIndex
                    ].t <=
                    currentBeat + 0.0005
                do
                    if token ~= playbackToken then
                        break
                    end

                    local event =
                        timeline[
                            currentEventIndex
                        ]

                    processEvent(event)

                    currentEventIndex =
                        currentEventIndex + 1
                end

                updateTimelineUI()

                if
                    currentBeat >=
                    totalBeats
                then
                    currentBeat =
                        totalBeats

                    updateTimelineUI()

                    songPlaying =
                        false

                    break
                end

                task.wait(0.01)
            end
        end

        playbackThreadRunning =
            false

        if
            token == playbackToken
            and
            not _G.STOPIT
            and
            not songPlaying
            and
            currentBeat >= totalBeats
        then
            releaseAllInputs()

            statusLabel.Text =
                "Finished"

            playSound(
                "6493287948",
                0.1
            )

            NotificationLibrary:SendNotification(
                "Success",
                "Your song has finished.",
                3
            )
        end
    end)
end

-- ================================================================
-- SEEK
-- ================================================================

local function seekToBeat(
    targetBeat,
    shouldResume
)
    if not timelineReady then
        return
    end

    targetBeat =
        math.clamp(
            tonumber(targetBeat) or 0,
            0,
            totalBeats
        )

    invalidatePlayback()

    currentBeat =
        targetBeat

    currentEventIndex =
        findEventIndex(
            targetBeat
        )

    restoreStateAtBeat(
        targetBeat
    )

    updateTimelineUI()

    if shouldResume
        and targetBeat < totalBeats
    then
        pausing = false
        songPlaying = true
        pausebutton.Text = "Pause"
        statusLabel.Text = "Playing"

        playbackToken =
            playbackToken + 1

        startPlaybackLoop()
    else
        pausing = true
        songPlaying = true
        pausebutton.Text = "Play"
        statusLabel.Text = "Paused"
    end
end

-- ================================================================
-- TIMELINE BAR POSITION
-- ================================================================

local function beatFromInput(input)
    local absoluteX =
        input.Position.X

    local left =
        timelineBar.AbsolutePosition.X

    local width =
        timelineBar.AbsoluteSize.X

    if width <= 0 then
        return 0
    end

    local ratio =
        math.clamp(
            (absoluteX - left) / width,
            0,
            1
        )

    return
        ratio * totalBeats
end

-- ================================================================
-- TIMELINE DRAG
-- ================================================================

timelineBar.InputBegan:Connect(function(input)
    if
        input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
    then
        if not timelineReady then
            return
        end

        seeking = true

        resumeAfterSeek =
            songPlaying
            and not pausing

        local target =
            beatFromInput(input)

        seekToBeat(
            target,
            false
        )
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if
        not seeking
        or
        not timelineReady
    then
        return
    end

    if
        input.UserInputType ==
            Enum.UserInputType.MouseMovement
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
    then
        local target =
            beatFromInput(input)

        seekToBeat(
            target,
            false
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if
        not seeking
    then
        return
    end

    if
        input.UserInputType ==
            Enum.UserInputType.MouseButton1
        or
        input.UserInputType ==
            Enum.UserInputType.Touch
    then
        seeking = false

        if
            resumeAfterSeek
            and currentBeat < totalBeats
        then
            pausing = false
            songPlaying = true
            pausebutton.Text = "Pause"
            statusLabel.Text = "Playing"

            playbackToken =
                playbackToken + 1

            startPlaybackLoop()
        end
    end
end)

-- ================================================================
-- PAUSE / RESUME
-- ================================================================

local function pauseSong()
    if not timelineReady then
        return
    end

    if pausing then
        if currentBeat >= totalBeats then
            seekToBeat(
                0,
                true
            )

            return
        end

        pausing = false
        songPlaying = true

        pausebutton.Text =
            "Pause"

        statusLabel.Text =
            "Playing"

        playbackToken =
            playbackToken + 1

        startPlaybackLoop()

        playSound(
            "6493287948",
            0.1
        )

    else
        pausing = true

        songPlaying = true

        pausebutton.Text =
            "Play"

        statusLabel.Text =
            "Paused"

        releaseAllInputs()

        playSound(
            "6493287948",
            0.1
        )
    end
end

pausebutton.MouseButton1Click:Connect(
    pauseSong
)

-- ================================================================
-- STOP
-- ================================================================

local function stopPlayingSongs()
    _G.STOPIT = true

    songPlaying = false
    pausing = true

    invalidatePlayback()

    statusLabel.Text =
        "Stopped"

    playSound(
        "6493287948",
        0.1
    )

    NotificationLibrary:SendNotification(
        "Success",
        "Stopping...",
        1
    )

    task.wait(0.1)

    if lilgui then
        lilgui:Destroy()
        lilgui = nil
    end
end

stopbutton.MouseButton1Click:Connect(
    stopPlayingSongs
)

-- ================================================================
-- RESTART
-- ================================================================

restartButton.MouseButton1Click:Connect(function()
    if not timelineReady then
        return
    end

    seekToBeat(
        0,
        true
    )
end)

-- ================================================================
-- BACK 5 SECONDS
-- ================================================================

backButton.MouseButton1Click:Connect(function()
    if not timelineReady then
        return
    end

    local target =
        currentBeat -
        (
            5 *
            math.max(
                tonumber(bpm) or 120,
                1
            ) / 60
        )

    local resume =
        songPlaying
        and not pausing

    seekToBeat(
        target,
        resume
    )
end)

-- ================================================================
-- FORWARD 5 SECONDS
-- ================================================================

forwardButton.MouseButton1Click:Connect(function()
    if not timelineReady then
        return
    end

    local target =
        currentBeat +
        (
            5 *
            math.max(
                tonumber(bpm) or 120,
                1
            ) / 60
        )

    local resume =
        songPlaying
        and not pausing

    seekToBeat(
        target,
        resume
    )
end)

-- ================================================================
-- BPM
-- ================================================================

local function updateBPM()
    bpm =
        math.max(
            tonumber(bpm) or 120,
            1
        )

    bpmtext.Text =
        "BPM: " ..
        tostring(
            math.floor(bpm)
        )
end

upbpm.MouseButton1Click:Connect(function()
    bpm =
        bpm + 10

    updateBPM()
end)

downbpm.MouseButton1Click:Connect(function()
    bpm =
        math.max(
            1,
            bpm - 10
        )

    updateBPM()
end)

-- ================================================================
-- ERROR MARGIN
-- ================================================================

local function round(num, decimalPlaces)
    local mult =
        10 ^ decimalPlaces

    return
        math.floor(
            num * mult + 0.5
        ) / mult
end

local function updateErrorMargin()
    errorbox.Text =
        string.format(
            "Error: %.3f",
            errormargin
        )
end

more.MouseButton1Click:Connect(function()
    errormargin =
        round(
            errormargin + 0.005,
            3
        )

    updateErrorMargin()
end)

less.MouseButton1Click:Connect(function()
    if errormargin <= 0 then
        return
    end

    errormargin =
        round(
            errormargin - 0.005,
            3
        )

    updateErrorMargin()
end)

-- ================================================================
-- COMPATIBILITY FUNCTIONS
--
-- These remain so older generated scripts can still call:
-- pressnote()
-- rest()
-- keypress()
-- keysequence16()
--
-- New MIDI2LUA files use playTimeline().
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

function pressnote(
    note,
    octave,
    beats,
    bpmValue
)
    if _G.STOPIT then
        return
    end

    local key =
        noteMappings[note]
        and
        noteMappings[note][octave]

    if key then
        task.spawn(function()
            pressKey(
                key,
                beats,
                false
            )
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

function rest(
    beats,
    bpmValue
)
    if _G.STOPIT then
        return
    end

    local safeBpm =
        math.max(
            tonumber(bpmValue) or bpm,
            1
        )

    local waitTime =
        (beats / safeBpm) * 60

    if errormargin == 0 then
        task.wait(waitTime)
    else
        local randomOffset =
            (
                math.random() * 1.6 - 1
            )
            * (errormargin / 2)

        task.wait(
            math.max(
                0,
                waitTime + randomOffset
            )
        )
    end
end

function keypress(
    keys,
    beats,
    bpmValue
)
    if _G.STOPIT then
        return
    end

    task.spawn(function()
        pressKey(
            keys,
            beats,
            type(beats) ~= "number"
        )
    end)
end

function keysequence16(
    keys,
    beats,
    bpmValue
)
    if _G.STOPIT then
        return
    end

    task.spawn(function()
        for i = 1, #keys do
            if _G.STOPIT then
                return
            end

            local key =
                keys:sub(i, i)

            keypress(
                key,
                beats,
                bpmValue
            )

            rest(
                0.25,
                bpmValue
            )
        end
    end)
end

-- ================================================================
-- MAIN TIMELINE FUNCTION
-- ================================================================

function playTimeline(
    events,
    durationInBeats
)
    if _G.STOPIT then
        return
    end

    timeline = events or {}

    totalBeats =
        math.max(
            tonumber(durationInBeats) or 0,
            0
        )

    table.sort(
        timeline,
        function(a, b)
            if a.t == b.t then
                return false
            end

            return a.t < b.t
        end
    )

    currentBeat = 0

    currentEventIndex = 1

    runtimeLastVelocity =
        nil

    timelineReady = true

    songPlaying = true

    pausing = false

    statusLabel.Text =
        "Playing"

    pausebutton.Text =
        "Pause"

    updateBPM()

    updateErrorMargin()

    updateTimelineUI()

    playbackToken =
        playbackToken + 1

    startPlaybackLoop()
end

-- ================================================================
-- FINISH FUNCTION
--
-- Kept for compatibility with generated scripts.
--
-- The timeline player itself does not immediately destroy the GUI
-- when it reaches the end, because that would make seeking after
-- completion impossible.
-- ================================================================

function finishedSong()
    if _G.STOPIT then
        return
    end

    if
        timelineReady
        and
        currentBeat < totalBeats
    then
        return
    end

    songPlaying = false

    pausing = true

    releaseAllInputs()

    statusLabel.Text =
        "Finished"

    pausebutton.Text =
        "Play"
end

-- ================================================================
-- INITIAL STATE
-- ================================================================

updateBPM()
updateErrorMargin()

timeLabel.Text =
    "00:00 / 00:00"

statusLabel.Text =
    "Waiting for timeline"

timelineProgress.Size =
    UDim2.new(
        0,
        0,
        1,
        0
    )

timelineHandle.Position =
    UDim2.new(
        0,
        0,
        0.5,
        0
    )

-- ================================================================
-- SAFETY
-- ================================================================

game:GetService("Players")
    .LocalPlayer
    .CharacterRemoving
    :Connect(function()
        releaseAllInputs()
    end)
