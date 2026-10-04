-- MIDI2LUA loader
-- Original-style playback
--
-- GUI RESTORED
-- No timeline
-- No seek
-- No +/- time controls
-- No random Shift
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

local UserInputService =
    game:GetService("UserInputService")

local VirtualInputManager =
    game:GetService("VirtualInputManager")

local Players =
    game:GetService("Players")

local LocalPlayer =
    Players.LocalPlayer

local PlayerGui =
    LocalPlayer:WaitForChild("PlayerGui")

-- ================================================================
-- SOUND
-- ================================================================

local function playSound(soundId, loudness)

    local sound =
        Instance.new("Sound")

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

-- ================================================================
-- LOAD MAIN AUTOPIANO FILE
-- ================================================================

loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Linh-1205/autopiano/refs/heads/main/load.lua",
    true
))()

task.wait(0.3)

playSound(
    "6493287948",
    0.1
)

NotificationLibrary:SendNotification(
    "Success",
    "MIDI2LUA loader loaded.",
    1
)

-- ================================================================
-- GLOBAL SETTINGS
-- ================================================================

local songPlaying =
    false

local pausing =
    false

local errormargin =
    tonumber(errormargin) or 0

bpm =
    tonumber(bpm) or 120

if bpm <= 0 then
    bpm = 120
end

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

local function isCurrentGeneration(
    key,
    generation
)

    return
        keyGeneration[
            getKeyId(key)
        ] == generation

end

-- ================================================================
-- RELEASE EVERYTHING
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

local function getHoldTime(
    beats,
    isShort,
    bpmValue
)

    if isShort then

        return math.random(
            4,
            12
        ) / 100

    end

    if
        type(beats) ~= "number"
        or beats <= 0
    then

        return 0.04

    end

    local safeBpm =
        math.max(
            tonumber(bpmValue)
                or tonumber(bpm)
                or 120,
            1
        )

    local noteTime =
        (beats / safeBpm) * 60

    local maxRandom =
        noteTime / 2

    local randomOff =
        math.random() * maxRandom

    return math.max(
        0.01,
        noteTime - randomOff
    )

end

-- ================================================================
-- PRESS ONE KEY
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
            "Unknown key mapping: "
            .. tostring(key)
        )

        return
    end

    local generation =
        createKeyGeneration(key)

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

    -- CTRL

    if ctrlRequired then

        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.LeftControl,
            false,
            game
        )

    end

    -- SHIFT

    if needsShift then

        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.LeftShift,
            false,
            game
        )

    end

    -- KEY DOWN

    VirtualInputManager:SendKeyEvent(
        true,
        keyCode,
        false,
        game
    )

    -- RELEASE SHIFT

    if needsShift then

        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftShift,
            false,
            game
        )

    end

    -- RELEASE CTRL

    if ctrlRequired then

        VirtualInputManager:SendKeyEvent(
            false,
            Enum.KeyCode.LeftControl,
            false,
            game
        )

    end

    -- HOLD

    local waitTime =
        getHoldTime(
            beats,
            isShort,
            bpm
        )

    task.wait(waitTime)

    -- STOP SAFETY

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

    -- ONLY NEWEST GENERATION MAY RELEASE

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
        keys:sub(1, 5)
        == "Ctrl+"
    then

        ctrlRequired =
            true

        keys =
            keys:sub(6)

    end

    for i = 1, #keys do

        local key =
            keys:sub(
                i,
                i
            )

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
                math.random()
                * errormargin
                / 3
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
            tonumber(vel)
                or 0.5,
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
-- SUSTAIN PEDAL
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

function pressnote(
    note,
    octave,
    beats,
    bpmValue
)

    if _G.STOPIT then
        return
    end

    if pausing then
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

-- ================================================================
-- REST
-- ================================================================

function rest(
    beats,
    bpmValue
)

    if _G.STOPIT then
        return
    end

    if pausing then
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

    if errormargin == 0 then

        task.wait(
            waitTime
        )

    else

        local randomOffset =
            (
                math.random() * 1.6 - 1
            )
            * (
                errormargin / 2
            )

        task.wait(
            math.max(
                0,
                waitTime
                + randomOffset
            )
        )

    end

end

-- ================================================================
-- KEYPRESS
-- ================================================================

function keypress(
    keys,
    beats,
    bpmValue
)

    if _G.STOPIT then
        return
    end

    if pausing then
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

-- ================================================================
-- KEY SEQUENCE 16
-- ================================================================

function keysequence16(
    keys,
    beats,
    bpmValue
)

    if _G.STOPIT then
        return
    end

    if pausing then
        return
    end

    task.spawn(function()

        for i = 1, #keys do

            if _G.STOPIT then
                return
            end

            local key =
                keys:sub(
                    i,
                    i
                )

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
-- FINISHED SONG
-- ================================================================

function finishedSong()

    if _G.STOPIT then
        return
    end

    songPlaying =
        false

    pausing =
        false

    releaseAllInputs()

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

-- ================================================================
-- STOP
-- ================================================================

function stopPlayingSongs()

    _G.STOPIT =
        true

    songPlaying =
        false

    pausing =
        false

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

LocalPlayer.CharacterRemoving:Connect(
    function()

        releaseAllInputs()

    end
)

-- ================================================================
-- GUI
-- ================================================================

-- XÓA GUI CŨ NẾU CÓ
pcall(function()

    local oldGui =
        PlayerGui:FindFirstChild(
            "MIDI2LUA_GUI"
        )

    if oldGui then
        oldGui:Destroy()
    end

end)

-- SCREEN GUI

local gui =
    Instance.new("ScreenGui")

gui.Name =
    "MIDI2LUA_GUI"

gui.ResetOnSpawn =
    false

gui.IgnoreGuiInset =
    true

gui.DisplayOrder =
    999999

gui.ZIndexBehavior =
    Enum.ZIndexBehavior.Sibling

gui.Parent =
    PlayerGui

-- ================================================================
-- MAIN FRAME
-- ================================================================

local MainFrame =
    Instance.new("Frame")

MainFrame.Name =
    "MainFrame"

MainFrame.Size =
    UDim2.new(
        0,
        327,
        0,
        119
    )

MainFrame.Position =
    UDim2.new(
        0.5,
        -163,
        0.5,
        -60
    )

MainFrame.BackgroundColor3 =
    Color3.fromRGB(
        30,
        30,
        30
    )

MainFrame.BorderSizePixel =
    0

MainFrame.Active =
    true

MainFrame.ZIndex =
    10

MainFrame.Parent =
    gui

local MainCorner =
    Instance.new("UICorner")

MainCorner.CornerRadius =
    UDim.new(
        0,
        8
    )

MainCorner.Parent =
    MainFrame

-- ================================================================
-- TITLE
-- ================================================================

local Title =
    Instance.new("TextLabel")

Title.Name =
    "Title"

Title.Size =
    UDim2.new(
        1,
        -20,
        0,
        18
    )

Title.Position =
    UDim2.new(
        0,
        10,
        0,
        2
    )

Title.BackgroundTransparency =
    1

Title.Text =
    "MIDI2LUA"

Title.TextColor3 =
    Color3.fromRGB(
        220,
        220,
        220
    )

Title.TextSize =
    13

Title.Font =
    Enum.Font.SourceSansBold

Title.TextXAlignment =
    Enum.TextXAlignment.Left

Title.ZIndex =
    11

Title.Parent =
    MainFrame

-- ================================================================
-- DRAG
-- ================================================================

local dragging =
    false

local dragStart
local startPos

Title.InputBegan:Connect(
    function(input)

        if
            input.UserInputType
            == Enum.UserInputType.MouseButton1
        then

            dragging =
                true

            dragStart =
                input.Position

            startPos =
                MainFrame.Position

            input.Changed:Connect(
                function()

                    if
                        input.UserInputState
                        == Enum.UserInputState.End
                    then

                        dragging =
                            false

                    end

                end
            )

        end

    end
)

UserInputService.InputChanged:Connect(
    function(input)

        if
            dragging
            and
            input.UserInputType
            == Enum.UserInputType.MouseMovement
        then

            local delta =
                input.Position
                - dragStart

            MainFrame.Position =
                UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,

                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )

        end

    end
)

-- ================================================================
-- BUTTON CREATOR
-- ================================================================

local function createButton(
    name,
    text,
    x,
    y,
    width
)

    local button =
        Instance.new("TextButton")

    button.Name =
        name

    button.Size =
        UDim2.new(
            0,
            width,
            0,
            28
        )

    button.Position =
        UDim2.new(
            0,
            x,
            0,
            y
        )

    button.BackgroundColor3 =
        Color3.fromRGB(
            55,
            55,
            55
        )

    button.BorderSizePixel =
        0

    button.Text =
        text

    button.TextColor3 =
        Color3.fromRGB(
            255,
            255,
            255
        )

    button.TextSize =
        14

    button.Font =
        Enum.Font.SourceSans

    button.AutoButtonColor =
        true

    button.ZIndex =
        11

    button.Parent =
        MainFrame

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(
            0,
            5
        )

    corner.Parent =
        button

    return button

end

-- ================================================================
-- PAUSE
-- ================================================================

local PauseButton =
    createButton(
        "PauseButton",
        "Pause",
        10,
        22,
        100
    )

PauseButton.MouseButton1Click:Connect(
    function()

        if _G.STOPIT then
            return
        end

        pausing =
            not pausing

        if pausing then

            PauseButton.Text =
                "Resume"

        else

            PauseButton.Text =
                "Pause"

        end

    end
)

-- ================================================================
-- STOP
-- ================================================================

local StopButton =
    createButton(
        "StopButton",
        "Stop",
        117,
        22,
        100
    )

StopButton.MouseButton1Click:Connect(
    function()

        stopPlayingSongs()

        PauseButton.Text =
            "Stopped"

    end
)

-- ================================================================
-- BPM LABEL
-- ================================================================

local BPMLabel =
    Instance.new("TextLabel")

BPMLabel.Name =
    "BPMLabel"

BPMLabel.Size =
    UDim2.new(
        0,
        82,
        0,
        25
    )

BPMLabel.Position =
    UDim2.new(
        0,
        10,
        0,
        54
    )

BPMLabel.BackgroundTransparency =
    1

BPMLabel.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

BPMLabel.TextSize =
    14

BPMLabel.Font =
    Enum.Font.SourceSans

BPMLabel.TextXAlignment =
    Enum.TextXAlignment.Left

BPMLabel.ZIndex =
    11

BPMLabel.Parent =
    MainFrame

-- ================================================================
-- BPM BUTTONS
-- ================================================================

local BPMUp =
    createButton(
        "BPMUp",
        "^",
        91,
        52,
        25
    )

local BPMDown =
    createButton(
        "BPMDown",
        "v",
        119,
        52,
        25
    )

-- ================================================================
-- ERROR LABEL
-- ================================================================

local ErrorLabel =
    Instance.new("TextLabel")

ErrorLabel.Name =
    "ErrorLabel"

ErrorLabel.Size =
    UDim2.new(
        0,
        100,
        0,
        25
    )

ErrorLabel.Position =
    UDim2.new(
        0,
        150,
        0,
        54
    )

ErrorLabel.BackgroundTransparency =
    1

ErrorLabel.TextColor3 =
    Color3.fromRGB(
        255,
        255,
        255
    )

ErrorLabel.TextSize =
    14

ErrorLabel.Font =
    Enum.Font.SourceSans

ErrorLabel.TextXAlignment =
    Enum.TextXAlignment.Left

ErrorLabel.ZIndex =
    11

ErrorLabel.Parent =
    MainFrame

-- ================================================================
-- ERROR BUTTONS
-- ================================================================

local ErrorUp =
    createButton(
        "ErrorUp",
        "↑",
        258,
        52,
        25
    )

local ErrorDown =
    createButton(
        "ErrorDown",
        "↓",
        286,
        52,
        25
    )

-- ================================================================
-- CREDIT
-- ================================================================

local Credit =
    Instance.new("TextLabel")

Credit.Name =
    "Credit"

Credit.Size =
    UDim2.new(
        1,
        -20,
        0,
        18
    )

Credit.Position =
    UDim2.new(
        0,
        10,
        0,
        88
    )

Credit.BackgroundTransparency =
    1

Credit.Text =
    "MIDI2LUA • Original-style playback"

Credit.TextColor3 =
    Color3.fromRGB(
        140,
        140,
        140
    )

Credit.TextSize =
    11

Credit.Font =
    Enum.Font.SourceSans

Credit.TextXAlignment =
    Enum.TextXAlignment.Left

Credit.ZIndex =
    11

Credit.Parent =
    MainFrame

-- ================================================================
-- UPDATE GUI TEXT
-- ================================================================

local function updateBPMLabel()

    BPMLabel.Text =
        "BPM: "
        .. tostring(
            math.floor(
                tonumber(bpm)
                or 120
            )
        )

end

local function updateErrorLabel()

    ErrorLabel.Text =
        "Error: "
        .. string.format(
            "%.2f",
            tonumber(errormargin)
            or 0
        )

end

updateBPMLabel()
updateErrorLabel()

-- ================================================================
-- BPM UP
-- ================================================================

BPMUp.MouseButton1Click:Connect(
    function()

        bpm =
            math.min(
                999,
                (tonumber(bpm) or 120)
                + 1
            )

        updateBPMLabel()

    end
)

-- ================================================================
-- BPM DOWN
-- ================================================================

BPMDown.MouseButton1Click:Connect(
    function()

        bpm =
            math.max(
                1,
                (tonumber(bpm) or 120)
                - 1
            )

        updateBPMLabel()

    end
)

-- ================================================================
-- ERROR UP
-- ================================================================

ErrorUp.MouseButton1Click:Connect(
    function()

        errormargin =
            math.min(
                1,
                (tonumber(errormargin) or 0)
                + 0.01
            )

        updateErrorLabel()

    end
)

-- ================================================================
-- ERROR DOWN
-- ================================================================

ErrorDown.MouseButton1Click:Connect(
    function()

        errormargin =
            math.max(
                0,
                (tonumber(errormargin) or 0)
                - 0.01
            )

        updateErrorLabel()

    end
)

-- ================================================================
-- FINAL STATE
-- ================================================================

songPlaying =
    true

pausing =
    false

print(
    "MIDI2LUA loader ready."
)

print(
    "Random Shift: DISABLED"
)

print(
    "Repeated-key protection: ENABLED"
)

print(
    "GUI: ENABLED"
)
