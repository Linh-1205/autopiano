-- MIDI2LUA loader
-- Original-style playback
--
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

local songPlaying = false
local pausing = false

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
--
-- IMPORTANT:
--
-- Lowercase:
-- d -> D key WITHOUT Shift
--
-- Uppercase:
-- D -> D key WITH Shift
--
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
-- Prevents:
--
-- d #1:
--     key down
--
-- d #2:
--     key down
--
-- old d #1:
--     key up
--
-- from cancelling the newer d #2.
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

    -- Make sure an old hold does not
    -- remain active before retriggering.
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

    -- ============================================================
    -- CTRL
    -- ============================================================

    if ctrlRequired then

        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.LeftControl,
            false,
            game
        )

    end

    -- ============================================================
    -- SHIFT
    --
    -- ONLY uppercase/symbol mappings get Shift.
    --
    -- There is NO random Shift here.
    -- ============================================================

    if needsShift then

        VirtualInputManager:SendKeyEvent(
            true,
            Enum.KeyCode.LeftShift,
            false,
            game
        )

    end

    -- ============================================================
    -- KEY DOWN
    -- ============================================================

    VirtualInputManager:SendKeyEvent(
        true,
        keyCode,
        false,
        game
    )

    -- ============================================================
    -- RELEASE MODIFIERS
    --
    -- We do NOT keep Shift held.
    -- ============================================================

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

    -- ============================================================
    -- HOLD
    -- ============================================================

    local waitTime =
        getHoldTime(
            beats,
            isShort,
            bpm
        )

    task.wait(waitTime)

    -- ============================================================
    -- STOP SAFETY
    -- ============================================================

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

    -- ============================================================
    -- ONLY NEWEST GENERATION MAY RELEASE
    -- ============================================================

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

    -- ============================================================
    -- CTRL+
    -- ============================================================

    if
        keys:sub(1, 5)
        == "Ctrl+"
    then

        ctrlRequired =
            true

        keys =
            keys:sub(6)

    end

    -- ============================================================
    -- PRESS EACH KEY
    -- ============================================================

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

        -- Keep the original error-margin
        -- timing behavior.
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
        -- Original loader behavior:
        -- do not start while paused.
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

    -- Keep original error-margin behavior.
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
