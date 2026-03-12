local NotificationLibrary =
    loadstring(game:HttpGet("https://hellohellohell0.com/talentless-raw/notif_lib.lua"))()

local function playSound(soundId, loudness)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://" .. soundId
    sound.Parent = game.Players.LocalPlayer.Character or game.Players.LocalPlayer
    sound.Volume = loudness or 1
    sound:Play()
end

local addgui = Instance.new("ScreenGui")
local newsongframe = Instance.new("Frame")
local insertscript = Instance.new("TextBox")
local newsonglabel = Instance.new("TextLabel")
local cancelButton = Instance.new("TextButton")
local insertsongName = Instance.new("TextBox")
local submitSong = Instance.new("TextButton")
local UIListLayout = Instance.new("UIListLayout")
local uic = Instance.new("UICorner")

addgui.Name = "addgui"
addgui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
addgui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

newsongframe.Name = "newsongframe"
newsongframe.Parent = addgui
newsongframe.AnchorPoint = Vector2.new(0.5, 0.5)
newsongframe.BackgroundColor3 = Color3.fromRGB(255, 228, 235)
newsongframe.BorderColor3 = Color3.fromRGB(255, 182, 193)
newsongframe.BorderSizePixel = 0
newsongframe.Position = UDim2.new(0.5, 0, 0.5, 0)
newsongframe.Size = UDim2.new(0, 254, 0, 326)

uic.CornerRadius = UDim.new(0, 4)
uic.Parent = newsongframe

newsonglabel.Name = "newsonglabel"
newsonglabel.Parent = newsongframe
newsonglabel.BackgroundColor3 = Color3.fromRGB(255, 228, 235)
newsonglabel.BorderColor3 = Color3.fromRGB(255, 182, 193)
newsonglabel.BorderSizePixel = 4
newsonglabel.LayoutOrder = 1
newsonglabel.Position = UDim2.new(0.0708699971, 0, 0.0552100018, 0)
newsonglabel.Size = UDim2.new(0, 218, 0, 50)
newsonglabel.Font = Enum.Font.SourceSansBold
newsonglabel.Text = "Add Custom Song"
newsonglabel.TextColor3 = Color3.fromRGB(255, 255, 255)
newsonglabel.TextScaled = true
newsonglabel.TextWrapped = true

cancelButton.Name = "cancelButton"
cancelButton.Parent = newsongframe
cancelButton.AnchorPoint = Vector2.new(1, 0)
cancelButton.BackgroundColor3 = Color3.fromRGB(255, 182, 193)
cancelButton.BorderColor3 = Color3.fromRGB(255, 182, 193)
cancelButton.BorderSizePixel = 0
cancelButton.Position = UDim2.new(1, -5, 0, 5)
cancelButton.Size = UDim2.new(0, 30, 0, 30)
cancelButton.Font = Enum.Font.SourceSansBold
cancelButton.Text = "X"
cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
cancelButton.TextSize = 20
cancelButton.ZIndex = 5

insertscript.Name = "insertscript"
insertscript.Parent = newsongframe
insertscript.BackgroundColor3 = Color3.fromRGB(255, 228, 235)
insertscript.BorderColor3 = Color3.fromRGB(255, 182, 193)
insertscript.BorderSizePixel = 4
insertscript.LayoutOrder = 2
insertscript.Position = UDim2.new(0.0708699971, 0, 0.257669985, 0)
insertscript.Size = UDim2.new(0, 218, 0, 123)
insertscript.Font = Enum.Font.SourceSans
insertscript.PlaceholderText = "Paste your song script here..."
insertscript.Text = ""
insertscript.TextColor3 = Color3.fromRGB(255, 255, 255)
insertscript.TextSize = 14.000
insertscript.TextWrapped = true
insertscript.MultiLine = true
insertscript.ClearTextOnFocus = false

insertsongName.Name = "insertsongName"
insertsongName.Parent = newsongframe
insertsongName.BackgroundColor3 = Color3.fromRGB(255, 228, 235)
insertsongName.BorderColor3 = Color3.fromRGB(255, 182, 193)
insertsongName.BorderSizePixel = 4
insertsongName.LayoutOrder = 3
insertsongName.Position = UDim2.new(0.0708699971, 0, 0.69325, 0)
insertsongName.Size = UDim2.new(0, 218, 0, 32)
insertsongName.Font = Enum.Font.SourceSans
insertsongName.PlaceholderText = "Song name..."
insertsongName.Text = ""
insertsongName.TextColor3 = Color3.fromRGB(255, 255, 255)
insertsongName.TextSize = 20
insertsongName.TextWrapped = true

submitSong.Name = "submitSong"
submitSong.Parent = newsongframe
submitSong.BackgroundColor3 = Color3.fromRGB(255, 182, 193)
submitSong.BorderColor3 = Color3.fromRGB(255, 182, 193)
submitSong.BorderSizePixel = 0
submitSong.LayoutOrder = 4
submitSong.Position = UDim2.new(0.0708699971, 0, 0.834360003, 0)
submitSong.Size = UDim2.new(0, 218, 0, 41)
submitSong.Font = Enum.Font.SourceSansBold
submitSong.Text = "Add Song"
submitSong.TextColor3 = Color3.fromRGB(255, 255, 255)
submitSong.TextSize = 30.000

UIListLayout.Parent = newsongframe
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
UIListLayout.Padding = UDim.new(0, 15)

-- drag script

local UserInputService = game:GetService("UserInputService")
local gui = newsongframe
local dragging, dragInput, dragStart, startPos

local function update(input)
    local delta = input.Position - dragStart
    gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

gui.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = gui.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

gui.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        update(input)
    end
end)

cancelButton.MouseButton1Click:Connect(function()
    newsongframe.Visible = false
end)

submitSong.MouseButton1Click:Connect(function()
    local scriptInput = insertscript.Text
    local songName = insertsongName.Text

    if songName == "" or scriptInput == "" then
        playSound("6493287948", 0.1)
        NotificationLibrary:SendNotification("Error", "Please fill in both fields.", 3)
        return
    end

    local folderExists = false
    for _, file in ipairs(listfiles("")) do
        if string.match(tostring(file), "AUTOPIANO_CUSTOM_SONGS") then
            folderExists = true
        end
    end

    if not folderExists then
        makefolder("AUTOPIANO_CUSTOM_SONGS")
    end

    local songexists = false
    for _, file in ipairs(listfiles("./AUTOPIANO_CUSTOM_SONGS")) do
        if string.find(tostring(file), songName .. ".txt") then
            playSound("6493287948", 0.1)
            NotificationLibrary:SendNotification("Error", "A song with that name already exists.", 3)
            songexists = true
            break
        end
    end

    if not songexists then
        writefile("AUTOPIANO_CUSTOM_SONGS/" .. songName .. ".txt", scriptInput)
        playSound("6493287948", 0.1)
        NotificationLibrary:SendNotification("Success", "Added song: " .. songName, 5)
        insertscript.Text = ""
        insertsongName.Text = ""
    end

    wait(0.5)
    updateSongs()
end)
