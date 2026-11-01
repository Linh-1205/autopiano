--[[ AutoPiano notification library (self-contained)
     NotificationLibrary:SendNotification(title, text, duration?)
     Màu theo title: Success / Error / Info / Warning ]]

local NotificationLibrary = {}

local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local COLORS = {
    success = Color3.fromRGB(120, 220, 160),
    error = Color3.fromRGB(255, 105, 120),
    warning = Color3.fromRGB(255, 200, 95),
    info = Color3.fromRGB(255, 182, 208),
}

local container

local function getContainer()
    if container and container.Parent then return container end

    local gui = Instance.new("ScreenGui")
    gui.Name = "APNotifications"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1000
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end

    container = Instance.new("Frame")
    container.Name = "Stack"
    container.AnchorPoint = Vector2.new(1, 1)
    container.Position = UDim2.new(1, -16, 1, -16)
    container.Size = UDim2.new(0, 280, 0, 420)
    container.BackgroundTransparency = 1
    container.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.Padding = UDim.new(0, 8)
    layout.Parent = container

    return container
end

local counter = 0

function NotificationLibrary:SendNotification(title, text, duration)
    title = tostring(title or "Info")
    text = tostring(text or "")
    duration = tonumber(duration) or 3

    local color = COLORS.info
    local key = title:lower()
    for name, c in pairs(COLORS) do
        if key:find(name, 1, true) then color = c end
    end

    local ok, err = pcall(function()
        counter = counter + 1
        local parent = getContainer()

        local card = Instance.new("Frame")
        card.LayoutOrder = counter
        card.Size = UDim2.new(0, 260, 0, 62)
        card.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
        card.BackgroundTransparency = 1
        card.BorderSizePixel = 0
        card.Parent = parent

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local strip = Instance.new("Frame")
        strip.Size = UDim2.new(0, 4, 1, -16)
        strip.Position = UDim2.new(0, 8, 0, 8)
        strip.BackgroundColor3 = color
        strip.BackgroundTransparency = 1
        strip.BorderSizePixel = 0
        strip.Parent = card
        local sc = Instance.new("UICorner")
        sc.CornerRadius = UDim.new(0, 2)
        sc.Parent = strip

        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Position = UDim2.new(0, 22, 0, 8)
        t.Size = UDim2.new(1, -30, 0, 18)
        t.Font = Enum.Font.GothamBold
        t.TextSize = 14
        t.TextColor3 = color
        t.TextTransparency = 1
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Text = title
        t.Parent = card

        local m = Instance.new("TextLabel")
        m.BackgroundTransparency = 1
        m.Position = UDim2.new(0, 22, 0, 28)
        m.Size = UDim2.new(1, -30, 1, -34)
        m.Font = Enum.Font.Gotham
        m.TextSize = 13
        m.TextColor3 = Color3.fromRGB(215, 215, 228)
        m.TextTransparency = 1
        m.TextWrapped = true
        m.TextXAlignment = Enum.TextXAlignment.Left
        m.TextYAlignment = Enum.TextYAlignment.Top
        m.Text = text
        m.Parent = card

        local info = TweenInfo.new(0.25)
        local function fade(bg, tt)
            TweenService:Create(card, info, { BackgroundTransparency = bg }):Play()
            TweenService:Create(strip, info, { BackgroundTransparency = bg }):Play()
            TweenService:Create(t, info, { TextTransparency = tt }):Play()
            TweenService:Create(m, info, { TextTransparency = tt }):Play()
        end

        fade(0.05, 0)
        task.delay(duration, function()
            fade(1, 1)
            task.wait(0.3)
            card:Destroy()
        end)
    end)

    if not ok then print("[AutoPiano]", title, text) end
end

return NotificationLibrary
