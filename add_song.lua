--[[ AutoPiano - add_song.lua (optional)
     Dán script sheet + đặt tên + chọn mục -> lưu vào AUTOPIANO_CUSTOM_SONGS/{name}.txt
     - Mục: chọn NHIỀU mục có sẵn (bấm để bật/tắt), mặc định "custom"; có thể gõ thêm mục mới (cách nhau bằng dấu phẩy).
     - BPM: tự đọc từ dòng "--BPM:xxx" ở đầu sheet (web MIDI -> Lua tự ghi dòng này), không cần nhập tay.
     Mục lưu trong _categories.txt (dòng "name|cat1,cat2") và header --CAT: trong file. ]]

local DIR = "AUTOPIANO_CUSTOM_SONGS"
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local function notify(kind, msg)
    local n = _G.AP_Notif
    if n and n.SendNotification then n:SendNotification(kind, msg, 3) else print(kind, msg) end
end

if type(writefile) ~= "function" or type(makefolder) ~= "function" or type(isfolder) ~= "function" then
    notify("Error", "Executor has no file system support")
    return
end

if _G.__AP_ADDSONG_GUI then pcall(function() _G.__AP_ADDSONG_GUI:Destroy() end) end

-- Theme hồng + kính, giống giao diện chính (auto.lua)
local C = {
    bg = Color3.fromRGB(244, 198, 211), panel = Color3.fromRGB(255, 255, 255), item = Color3.fromRGB(255, 255, 255),
    text = Color3.fromRGB(67, 48, 58), muted = Color3.fromRGB(112, 90, 101),
    accent = Color3.fromRGB(201, 112, 141), accentText = Color3.fromRGB(255, 255, 255),
    pink100 = Color3.fromRGB(249, 221, 229), pink300 = Color3.fromRGB(236, 169, 189),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o) new("UICorner", { CornerRadius = UDim.new(0, 8) }, o) end
local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

-- viền kính: sáng ở góc trên-trái, mờ dần ở giữa, hồng nhạt ở góc dưới-phải
local function glowStroke(o, thickness)
    local st = new("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255), Thickness = thickness or 1, Transparency = 0.2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
    new("UIGradient", {
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), C.pink300),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.65), NumberSequenceKeypoint.new(1, 0.2),
        }),
        Rotation = 45,
    }, st)
end

-- mục có sẵn: từ auto.lua (đã gồm mục tạo bằng nút +), "custom" luôn đứng đầu
local categories = { "custom" }
if _G.AP_GetCategories then
    local ok, list = pcall(_G.AP_GetCategories)
    if ok and type(list) == "table" then categories = list end
end

local gui = Instance.new("ScreenGui")
gui.Name = "APAddSong"
gui.ResetOnSpawn = false
gui.DisplayOrder = 950
local ok = pcall(function() gui.Parent = CoreGui end)
if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
_G.__AP_ADDSONG_GUI = gui

local main = new("Frame", {
    Size = UDim2.new(0, 420, 0, 436), Position = UDim2.new(0.5, -210, 0.5, -218),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true, Draggable = true,
}, gui)
corner(main, 18)
new("UIGradient", { Color = ColorSequence.new(C.pink100, C.pink300), Rotation = 135 }, main)
glowStroke(main, 1.5)
-- ảnh nền (nếu auto.lua đã tải xong) + lớp sương để chữ rõ
if _G.AP_WALLPAPER then
    local wall = new("ImageLabel", {
        Name = "Wallpaper", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        Image = _G.AP_WALLPAPER, ScaleType = Enum.ScaleType.Crop,
    }, main)
    corner(wall, 18)
end
local veil = new("Frame", {
    Name = "Veil", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.4, BorderSizePixel = 0,
}, main)
corner(veil, 18)

new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 6), Size = UDim2.new(1, -96, 0, 30),
    Text = 'Add <font color="rgb(201,112,141)"><i>Song</i></font>', RichText = true,
    Font = Enum.Font.Garamond, TextSize = 28, TextColor3 = C.text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local closeBtn = new("TextButton", {
    Position = UDim2.new(1, -74, 0, 8), Size = UDim2.new(0, 62, 0, 24), BackgroundColor3 = C.panel,
    BorderSizePixel = 0, Text = "Close", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
}, main)
corner(closeBtn)
closeBtn.BackgroundTransparency = 0.5
closeBtn.AutoButtonColor = false
glowStroke(closeBtn, 1)
closeBtn.Activated:Connect(function() gui:Destroy() end)

-- chế độ: Single (từng bài) / Multiple (dán gói nhiều bài)
local modeBtns = {}
local function modeButton(label, x, w)
    local b = new("TextButton", {
        Position = UDim2.new(0, x, 0, 10), Size = UDim2.new(0, w, 0, 22), BackgroundColor3 = C.panel,
        BorderSizePixel = 0, Text = label, Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = C.text,
        AutoButtonColor = false,
    }, main)
    corner(b)
    glowStroke(b, 1)
    modeBtns[label] = b
    return b
end
modeButton("Single", 138, 56)
modeButton("Multiple", 198, 66)

-- khung chứa toàn bộ giao diện chế độ Single (ẩn khi chuyển sang Multiple)
local singleFrame = new("Frame", { Name = "Single", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0) }, main)

local function box(y, h, placeholder, multi)
    local b = new("TextBox", {
        Position = UDim2.new(0, 14, 0, y), Size = UDim2.new(1, -28, 0, h),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "",
        PlaceholderText = placeholder, PlaceholderColor3 = C.muted,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text,
        ClearTextOnFocus = false, MultiLine = multi or false, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
        ClipsDescendants = true,
    }, singleFrame)
    corner(b)
    b.BackgroundTransparency = 0.45
    glowStroke(b, 1)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, b)
    return b
end

local nameBox = box(40, 30, "Song name")

-- chọn nhiều mục (bấm để bật/tắt, mặc định chỉ custom)
new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 76), Size = UDim2.new(1, -28, 0, 16),
    Text = "Categories (tap to toggle, default: custom)", Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left,
}, singleFrame)
local chipBar = new("ScrollingFrame", {
    Position = UDim2.new(0, 14, 0, 94), Size = UDim2.new(1, -28, 0, 28),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X,
}, singleFrame)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, chipBar)

local selected = { custom = true }
local chips = {}
local function paintChips()
    for name, chip in pairs(chips) do
        local on = selected[name] == true
        chip.BackgroundColor3 = on and C.accent or C.item
        chip.BackgroundTransparency = on and 0.08 or 0.5
        chip.TextColor3 = on and C.accentText or C.text
    end
end
for _, name in ipairs(categories) do
    local chip = new("TextButton", {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = C.item, BorderSizePixel = 0, Text = name,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
    }, chipBar)
    corner(chip)
    chip.AutoButtonColor = false
    glowStroke(chip, 1)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
    chips[name] = chip
    chip.Activated:Connect(function()
        selected[name] = not selected[name] or nil
        paintChips()
    end)
end
paintChips()

local newCatBox = box(128, 30, "Add new categories too (comma separated, optional)")
local scriptBox = box(166, 160, "Paste sheet script here (keypress / rest / finishedSong)", true)

-- BPM đọc từ dòng --BPM: ở đầu sheet
local bpmLabel = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 330), Size = UDim2.new(1, -28, 0, 18),
    Text = "BPM: paste a sheet to detect", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
}, singleFrame)

local function readBpm(script)
    for line in tostring(script):gmatch("[^\r\n]+") do
        local b = line:match("^%s*%-%-%s*BPM%s*:%s*(%d+)")
        if b then return tonumber(b) end
        if not line:match("^%s*%-%-") then break end -- header chỉ nằm ở các dòng comment đầu file
    end
    return nil
end

local function refreshBpmLabel()
    local script = scriptBox.Text
    if #script <= 10 then
        bpmLabel.Text = "BPM: paste a sheet to detect"
        bpmLabel.TextColor3 = C.muted
        return
    end
    local b = readBpm(script)
    if b then
        bpmLabel.Text = "BPM: " .. b .. " (read from sheet)"
        bpmLabel.TextColor3 = C.accent
    else
        bpmLabel.Text = "BPM: not found in sheet, default 120 (change it before Play)"
        bpmLabel.TextColor3 = C.muted
    end
end
scriptBox:GetPropertyChangedSignal("Text"):Connect(refreshBpmLabel)

local saveBtn = new("TextButton", {
    Position = UDim2.new(0, 14, 1, -48), Size = UDim2.new(1, -28, 0, 34),
    BackgroundColor3 = C.accent, BorderSizePixel = 0, Text = "Save",
    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.accentText,
}, singleFrame)
corner(saveBtn)
saveBtn.BackgroundTransparency = 0.08
saveBtn.AutoButtonColor = false
glowStroke(saveBtn, 1)

saveBtn.Activated:Connect(function()
    local name = trim((trim(nameBox.Text):gsub("[^%w%-_ ]", "")))
    local script = scriptBox.Text
    if name == "" then notify("Error", "Enter a song name") return end
    if #script <= 10 then notify("Error", "Paste the sheet script first") return end

    -- mục = các chip đang bật (theo thứ tự hiển thị) + mục gõ thêm
    local cats, seen = {}, {}
    for _, c in ipairs(categories) do
        if selected[c] and not seen[c] then seen[c] = true; cats[#cats + 1] = c end
    end
    for raw in trim(newCatBox.Text):gmatch("[^,]+") do
        local c = trim(raw):lower()
        if c ~= "" and not seen[c] then seen[c] = true; cats[#cats + 1] = c end
    end
    -- chỉ "custom" (hoặc không chọn gì) = mặc định, không cần ghi header
    if #cats == 1 and cats[1] == "custom" then cats = {} end

    local okSave, err = pcall(function()
        if not isfolder(DIR) then makefolder(DIR) end

        local body = script
        if #cats > 0 and not body:match("^%-%-CAT:") then
            body = "--CAT:" .. table.concat(cats, ",") .. "\n" .. body
        end
        writefile(DIR .. "/" .. name .. ".txt", body)

        -- _categories.txt : "name|cat1,cat2"
        local catPath = DIR .. "/_categories.txt"
        local lines = {}
        if type(isfile) == "function" and isfile(catPath) then
            for line in tostring(readfile(catPath)):gmatch("[^\r\n]+") do
                local n = line:match("^(.-)|")
                if n ~= name then lines[#lines + 1] = line end
            end
        end
        if #cats > 0 then lines[#lines + 1] = name .. "|" .. table.concat(cats, ",") end
        writefile(catPath, table.concat(lines, "\n"))
    end)

    if okSave then
        local b = readBpm(script)
        notify("Success", "Saved: " .. name .. " (" .. (#cats > 0 and table.concat(cats, ", ") or "custom")
            .. (b and (", " .. b .. " BPM") or "") .. ")")
        if _G.AP_RefreshSongs then pcall(_G.AP_RefreshSongs) end
        gui:Destroy()
    else
        warn("[AutoPiano] add_song: " .. tostring(err))
        notify("Error", "Could not save song")
    end
end)

----------------------------------------------------------------------
-- Chế độ Multiple: dán gói nhiều bài (từ web "Merged pack" hoặc nút Share)
--   Import all : thêm thẳng tất cả bài
--   Edit       : tách thành cửa sổ nhiều tab (mỗi bài 1 tab), sửa rồi tự bấm Add từng bài
----------------------------------------------------------------------
local PackLib
pcall(function()
    if type(_G.__AP_PACK_SRC) == "string" then PackLib = loadstring(_G.__AP_PACK_SRC)() end
end)

local multiFrame = new("Frame", { Name = "Multi", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = false }, main)
local editFrame = new("Frame", { Name = "Edit", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = false }, main)

local function field(parent, x, y, w, h, placeholder, multi)
    local b = new("TextBox", {
        Position = UDim2.new(0, x, 0, y), Size = UDim2.new(w == 0 and 1 or 0, w == 0 and -28 or w, 0, h),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "",
        PlaceholderText = placeholder, PlaceholderColor3 = C.muted,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text,
        ClearTextOnFocus = false, MultiLine = multi or false, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
        ClipsDescendants = true,
    }, parent)
    corner(b)
    b.BackgroundTransparency = 0.45
    glowStroke(b, 1)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, b)
    return b
end
local function actionButton(parent, text, x, w, primary)
    local b = new("TextButton", {
        Position = UDim2.new(x, x == 0 and 14 or 4, 1, -48), Size = UDim2.new(w, -18, 0, 34),
        BackgroundColor3 = primary and C.accent or C.panel, BorderSizePixel = 0, Text = text,
        Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = primary and C.accentText or C.text,
        AutoButtonColor = false,
    }, parent)
    corner(b)
    b.BackgroundTransparency = primary and 0.08 or 0.45
    glowStroke(b, 1)
    return b
end

-- ---- khung dán gói
local packBox = field(multiFrame, 14, 40, 0, 296, "Paste the merged pack here (from the web converter, or from Share)", true)
local packInfo = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 340), Size = UDim2.new(1, -28, 0, 18),
    Text = "Paste a pack to detect songs", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
}, multiFrame)
local importAllBtn = actionButton(multiFrame, "Import all", 0, 0.5, true)
local editBtn = actionButton(multiFrame, "Edit", 0.5, 0.5, false)

local function parsedPack()
    if not PackLib then notify("Error", "Pack library unavailable (reload auto.lua)") return nil end
    local list, err = PackLib.parsePack(packBox.Text)
    if not list then notify("Error", "Invalid pack: " .. tostring(err)) return nil end
    return list
end

packBox:GetPropertyChangedSignal("Text"):Connect(function()
    if #packBox.Text < 10 or not PackLib then
        packInfo.Text, packInfo.TextColor3 = "Paste a pack to detect songs", C.muted
        return
    end
    local list, err = PackLib.parsePack(packBox.Text)
    if list then
        packInfo.Text, packInfo.TextColor3 = #list .. " song(s) detected", C.accent
    else
        packInfo.Text, packInfo.TextColor3 = "Not a valid pack: " .. tostring(err), C.muted
    end
end)

importAllBtn.Activated:Connect(function()
    local list = parsedPack()
    if not list then return end
    local added, err = PackLib.install(list, DIR)
    if not added then notify("Error", tostring(err)) return end
    notify("Success", "Added " .. added .. " of " .. #list .. " song(s)")
    if _G.AP_RefreshSongs then pcall(_G.AP_RefreshSongs) end
    gui:Destroy()
end)

-- ---- cửa sổ sửa nhiều bài (mỗi tab 1 bài)
local tabBar = new("ScrollingFrame", {
    Position = UDim2.new(0, 14, 0, 40), Size = UDim2.new(1, -28, 0, 28),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X,
}, editFrame)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)
local eName = field(editFrame, 14, 74, 0, 30, "Name of this song")
local eChipBar = new("ScrollingFrame", {
    Position = UDim2.new(0, 14, 0, 110), Size = UDim2.new(1, -28, 0, 28),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X,
}, editFrame)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, eChipBar)
local eCats = field(editFrame, 14, 142, 0, 30, "Add new categories too (comma separated, optional)")
local eSheet = field(editFrame, 14, 176, 0, 156, "Sheet script", true)
local eInfo = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 336), Size = UDim2.new(1, -28, 0, 18),
    Text = "", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left,
}, editFrame)
local eAdd = actionButton(editFrame, "Add this song", 0, 0.6, true)
local eBack = actionButton(editFrame, "Back", 0.6, 0.4, false)

local edits, active, tabButtons = {}, 0, {}

-- chip mục (mỗi bài có tập chọn riêng e.sel); không chọn gì = custom (mặc định)
local eChips = {}
local function paintEditChips()
    local e = edits[active]
    for name, chip in pairs(eChips) do
        local on = e ~= nil and e.sel[name] == true
        chip.BackgroundColor3 = on and C.accent or C.item
        chip.BackgroundTransparency = on and 0.08 or 0.5
        chip.TextColor3 = on and C.accentText or C.text
    end
end
for _, name in ipairs(categories) do
    local chip = new("TextButton", {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = C.item, BorderSizePixel = 0, Text = name,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text, AutoButtonColor = false,
    }, eChipBar)
    corner(chip)
    glowStroke(chip, 1)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
    eChips[name] = chip
    chip.Activated:Connect(function()
        local e = edits[active]
        if e and not e.added then
            e.sel[name] = not e.sel[name] or nil
            paintEditChips()
        end
    end)
end

local function paintTabs()
    for i, b in ipairs(tabButtons) do
        local e = edits[i]
        local on = (i == active)
        b.BackgroundColor3 = on and C.accent or C.item
        b.BackgroundTransparency = on and 0.08 or 0.5
        b.TextColor3 = on and C.accentText or C.text
        local label = trim(e.name) ~= "" and trim(e.name) or "(no name)"
        if #label > 14 then label = label:sub(1, 12) .. ".." end
        b.Text = (e.added and "+ " or "") .. label
    end
end

local function stash()
    local e = edits[active]
    if e and not e.added then
        e.name, e.cats, e.text = eName.Text, eCats.Text, eSheet.Text
    end
end

local function showTab(i)
    stash()
    active = i
    local e = edits[i]
    eName.Text, eCats.Text, eSheet.Text = e.name, e.cats, e.text
    local b = readBpm(e.text)
    eInfo.Text = e.added and "Already added" or (b and ("BPM: " .. b .. " (read from sheet)") or "BPM: not found, default 120")
    eInfo.TextColor3 = e.added and C.accent or C.muted
    eAdd.Text = e.added and "Added" or "Add this song"
    paintTabs()
    paintEditChips()
end

eSheet:GetPropertyChangedSignal("Text"):Connect(function()
    local b = readBpm(eSheet.Text)
    if edits[active] and not edits[active].added then
        eInfo.Text = b and ("BPM: " .. b .. " (read from sheet)") or "BPM: not found, default 120"
    end
end)
eName:GetPropertyChangedSignal("Text"):Connect(function()
    local e = edits[active]
    if e and not e.added then e.name = eName.Text; paintTabs() end
end)

local function setMode(mode)
    singleFrame.Visible = (mode == "Single")
    multiFrame.Visible = (mode == "Multiple")
    editFrame.Visible = (mode == "Edit")
    for label, b in pairs(modeBtns) do
        local on = (label == mode) or (mode == "Edit" and label == "Multiple")
        b.BackgroundColor3 = on and C.accent or C.panel
        b.BackgroundTransparency = on and 0.08 or 0.5
        b.TextColor3 = on and C.accentText or C.text
    end
end
modeBtns["Single"].Activated:Connect(function() setMode("Single") end)
modeBtns["Multiple"].Activated:Connect(function()
    setMode(#edits > 0 and editFrame.Visible and "Edit" or "Multiple")
end)
setMode("Single")

editBtn.Activated:Connect(function()
    local list = parsedPack()
    if not list then return end
    for _, b in ipairs(tabButtons) do b:Destroy() end
    tabButtons, edits, active = {}, {}, 0
    for i, s in ipairs(list) do
        local sel, extra = {}, {}
        for _, c in ipairs(s.cats or {}) do
            if eChips[c] then sel[c] = true else extra[#extra + 1] = c end
        end
        edits[i] = {
            name = s.name, sel = sel, cats = table.concat(extra, ", "), added = false,
            text = "--BPM:" .. tostring(s.bpm) .. "\n" .. table.concat(s.sheet, "\n"),
        }
        local b = new("TextButton", {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.item,
            BorderSizePixel = 0, Text = s.name, Font = Enum.Font.GothamMedium, TextSize = 12,
            TextColor3 = C.text, AutoButtonColor = false, LayoutOrder = i,
        }, tabBar)
        corner(b)
        glowStroke(b, 1)
        new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, b)
        tabButtons[i] = b
        b.Activated:Connect(function() showTab(i) end)
    end
    setMode("Edit")
    showTab(1)
end)

eBack.Activated:Connect(function()
    stash()
    setMode("Multiple")
end)

-- thêm thủ công đúng bài đang mở (nội dung theo những gì người dùng đã sửa)
eAdd.Activated:Connect(function()
    local e = edits[active]
    if not e or e.added then return end
    stash()
    local name = trim((trim(e.name):gsub("[^%w%-_ ]", "")))
    local script = e.text
    if name == "" then notify("Error", "Enter a song name") return end
    if #script <= 10 then notify("Error", "The sheet is empty") return end

    local cats, seen = {}, {}
    for _, c in ipairs(categories) do
        if e.sel[c] and not seen[c] then seen[c] = true; cats[#cats + 1] = c end
    end
    for raw in trim(e.cats):gmatch("[^,]+") do
        local c = trim((raw:gsub("[^%w%-_ ]", ""))):lower()
        if c ~= "" and not seen[c] then seen[c] = true; cats[#cats + 1] = c end
    end
    if #cats == 1 and cats[1] == "custom" then cats = {} end

    local okSave, err = pcall(function()
        if not isfolder(DIR) then makefolder(DIR) end
        local body = script
        if #cats > 0 and not body:match("^%-%-CAT:") then
            body = "--CAT:" .. table.concat(cats, ",") .. "\n" .. body
        end
        writefile(DIR .. "/" .. name .. ".txt", body)
        local catPath = DIR .. "/_categories.txt"
        local lines = {}
        if type(isfile) == "function" and isfile(catPath) then
            for line in tostring(readfile(catPath)):gmatch("[^\r\n]+") do
                if line:match("^(.-)|") ~= name then lines[#lines + 1] = line end
            end
        end
        if #cats > 0 then lines[#lines + 1] = name .. "|" .. table.concat(cats, ",") end
        writefile(catPath, table.concat(lines, "\n"))
    end)
    if okSave then
        e.added = true
        notify("Success", "Saved: " .. name)
        if _G.AP_RefreshSongs then pcall(_G.AP_RefreshSongs) end
        showTab(active)
    else
        warn("[AutoPiano] add_song: " .. tostring(err))
        notify("Error", "Could not save song")
    end
end)
