--[[ Melochi4Luna - pack_lib.lua
     Đóng gói / nhập kho bài hát để chia sẻ.

     Gói KHÔNG chứa code sheet thô. Mỗi dòng sheet được kiểm tra rồi nén thành 1 token:
         keypress("tuo", x, bpm)      -> ktuo
         keypress("u", 1.5, bpm)      -> hu,1.5
         rest(0.5, bpm)               -> r0.5
         pedalDown() / pedalUp()      -> d / u
         adjustVelocity(0.24)         -> v0.24
     Khi nhập, mỗi token được kiểm tra lại rồi dựng ra dòng sheet chuẩn. Dòng lạ => bỏ cả bài,
     nên gói bị sửa tay cũng không thể chèn thêm lệnh nào vào file bài hát.

     API: encodeSheet, buildPack, parsePack, install, run ]]

local M = {}

local VERSION = "ML1"
local DEFAULT_DIR = "AUTOPIANO_CUSTOM_SONGS"
-- phím hợp lệ: chữ, số và !@#$%^&*()  (không có dấu nháy, dấu ; , | nên không thể phá định dạng)
local CLOSE = "]" .. "==" .. "]" -- viết tách để file này không tự chứa chuỗi đóng
local KEY_OK = "^[%w!@#%$%%%^&%*%(%)]+$"

local function notify(kind, msg)
    local n = _G.AP_Notif
    if n and n.SendNotification then
        pcall(function() n:SendNotification(kind, msg, 3) end)
    else
        print("[AutoPiano] " .. tostring(kind) .. ": " .. tostring(msg))
    end
end

local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

-- số không âm, ngắn, hợp lệ (trả lại đúng chuỗi gốc)
local function num(s)
    if type(s) ~= "string" or #s > 12 or not s:match("^%d+%.?%d*$") then return nil end
    local n = tonumber(s)
    if not n or n > 100000 then return nil end
    return s
end

local function sanitizeName(name)
    return trim(tostring(name or ""):gsub("[^%w%-_ ]", "")):sub(1, 60)
end

local function sanitizeCats(str)
    local list, seen = {}, {}
    for raw in tostring(str or ""):gmatch("[^,]+") do
        local c = trim(raw:gsub("[^%w%-_ ]", "")):lower():sub(1, 30)
        if c ~= "" and not seen[c] and #list < 8 then
            seen[c] = true
            list[#list + 1] = c
        end
    end
    return list
end

----------------------------------------------------------------------
-- Sheet -> body (kiểm tra từng dòng)
-- trả về: body, bpmHeader, catHeader   hoặc   nil, lý do
----------------------------------------------------------------------
function M.encodeSheet(text)
    local bpm, cats, ops = nil, nil, {}
    for raw in tostring(text):gmatch("[^\r\n]+") do
        local line = trim(raw)
        if line == "" then
            -- bỏ qua
        elseif line:sub(1, 2) == "--" then
            local b = line:match("^%-%-%s*BPM%s*:%s*(%d+)")
            if b then bpm = b end
            local c = line:match("^%-%-%s*CAT%s*:%s*(.+)$")
            if c then cats = c end
        else
            local keys = line:match('^keypress%("([^"]*)",%s*x,%s*bpm%)$')
            local k2, beats = line:match('^keypress%("([^"]*)",%s*([%d%.]+),%s*bpm%)$')
            local r = line:match("^rest%(([%d%.]+),%s*bpm%)$")
            local v = line:match("^adjustVelocity%(([%d%.]+)%)$")
            if keys then
                if not keys:match(KEY_OK) then return nil, "bad keys" end
                ops[#ops + 1] = "k" .. keys
            elseif k2 then
                if not k2:match(KEY_OK) or not num(beats) then return nil, "bad keypress" end
                ops[#ops + 1] = "h" .. k2 .. "," .. beats
            elseif r then
                if not num(r) then return nil, "bad rest" end
                ops[#ops + 1] = "r" .. r
            elseif v then
                if not num(v) then return nil, "bad velocity" end
                ops[#ops + 1] = "v" .. v
            elseif line == "pedalDown()" then
                ops[#ops + 1] = "d"
            elseif line == "pedalUp()" then
                ops[#ops + 1] = "u"
            elseif line == "finishedSong()" then
                -- tự thêm lại khi giải nén
            else
                return nil, "unsupported line: " .. line:sub(1, 40)
            end
        end
    end
    if #ops == 0 then return nil, "empty sheet" end
    return table.concat(ops, ";"), bpm, cats
end

-- body -> danh sách dòng sheet chuẩn (kiểm tra lại từng token)
local function decodeBody(body)
    local lines = {}
    for op in tostring(body):gmatch("[^;]+") do
        local t, arg = op:sub(1, 1), op:sub(2)
        if t == "k" then
            if not arg:match(KEY_OK) then return nil, "bad data" end
            lines[#lines + 1] = 'keypress("' .. arg .. '", x, bpm)'
        elseif t == "h" then
            local keys, beats = arg:match("^([^,]+),([%d%.]+)$")
            if not keys or not keys:match(KEY_OK) or not num(beats) then return nil, "bad data" end
            lines[#lines + 1] = 'keypress("' .. keys .. '", ' .. beats .. ", bpm)"
        elseif t == "r" then
            if not num(arg) then return nil, "bad data" end
            lines[#lines + 1] = "rest(" .. arg .. ", bpm)"
        elseif t == "v" then
            if not num(arg) then return nil, "bad data" end
            lines[#lines + 1] = "adjustVelocity(" .. arg .. ")"
        elseif t == "d" and arg == "" then
            lines[#lines + 1] = "pedalDown()"
        elseif t == "u" and arg == "" then
            lines[#lines + 1] = "pedalUp()"
        else
            return nil, "bad data"
        end
    end
    if #lines == 0 then return nil, "empty song" end
    lines[#lines + 1] = "finishedSong()"
    return lines
end

----------------------------------------------------------------------
-- Tạo gói
--   songs = { { name=, bpm=, cats=(bảng hoặc chuỗi), text=nội dung file bài }, ... }
--   trả về: script, số bài, danh sách bài bị bỏ { {name=, why=}, ... }
----------------------------------------------------------------------
function M.buildPack(songs)
    local src = _G.__AP_PACK_SRC
    if type(src) ~= "string" or src:find(CLOSE, 1, true) then
        return nil, 0, {}, "pack library source missing"
    end
    local out, skipped, count = { VERSION }, {}, 0
    for _, s in ipairs(songs) do
        local name = sanitizeName(s.name)
        local body, hb, hc = M.encodeSheet(s.text)
        if name ~= "" and body then
            local bpm = hb or tostring(s.bpm or ""):match("^%d+") or "120"
            local cats = sanitizeCats(type(s.cats) == "table" and table.concat(s.cats, ",") or (s.cats or hc or ""))
            if #cats == 1 and cats[1] == "custom" then cats = {} end -- mặc định, không cần ghi
            out[#out + 1] = "S|" .. name .. "|" .. bpm .. "|" .. table.concat(cats, ",")
            out[#out + 1] = body
            count = count + 1
        else
            skipped[#skipped + 1] = { name = tostring(s.name), why = name == "" and "bad name" or tostring(hb) }
        end
    end
    local script = "--[[ Melochi4Luna song pack (" .. count .. " song" .. (count == 1 and "" or "s") .. ")\n"
        .. "     Safest: paste this whole text into Import inside Melochi4Luna. It only reads the data, nothing is executed.\n"
        .. "     Or run it directly (loadstring / executor): it only writes song files into " .. DEFAULT_DIR .. ". ]]\n"
        .. "local PACK = [==[\n" .. table.concat(out, "\n") .. "\n" .. CLOSE .. "\n"
        .. "local LIB = [==[\n" .. src .. "\n" .. CLOSE .. "\n"
        .. "local lib = loadstring(LIB)()\n"
        .. "lib.run(PACK)\n"
    return script, count, skipped
end

----------------------------------------------------------------------
-- Đọc gói (text có thể là cả script hoặc chỉ phần dữ liệu). KHÔNG chạy gì cả.
-- trả về: { {name=, bpm=, cats={...}, sheet={dòng...}}, ... }   hoặc   nil, lý do
----------------------------------------------------------------------
function M.parsePack(text)
    text = tostring(text or "")
    local data = text:match("local PACK = %[==%[\r?\n(.-)\r?\n%]==%]") or text
    data = data:gsub("^%s+", "")
    if data:sub(1, #VERSION) ~= VERSION then return nil, "not a song pack" end
    local lines = {}
    for line in data:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    local songs, i = {}, 2
    while i <= #lines do
        local name, bpm, cats = lines[i]:match("^S|([^|]*)|(%d*)|(.*)$")
        local body = lines[i + 1]
        if not name or not body then return nil, "damaged pack (line " .. i .. ")" end
        i = i + 2
        local clean = sanitizeName(name)
        local sheet, err = decodeBody(body)
        if not sheet then return nil, err end
        if clean ~= "" then
            songs[#songs + 1] = { name = clean, bpm = (bpm ~= "" and bpm) or "120", cats = sanitizeCats(cats), sheet = sheet }
        end
    end
    if #songs == 0 then return nil, "pack has no songs" end
    return songs
end

----------------------------------------------------------------------
-- Ghi bài vào thư mục custom. Trùng tên thì thêm hậu tố (2), (3)... không ghi đè bài cũ.
-- trả về: số bài đã thêm   hoặc   nil, lý do
----------------------------------------------------------------------
function M.install(songs, dir)
    dir = dir or DEFAULT_DIR
    if type(writefile) ~= "function" or type(makefolder) ~= "function" or type(isfolder) ~= "function"
        or type(isfile) ~= "function" then
        return nil, "Executor has no file system support"
    end
    local ok, err = pcall(function()
        if not isfolder(dir) then makefolder(dir) end
    end)
    if not ok then return nil, tostring(err) end

    local catPath = dir .. "/_categories.txt"
    local catLines = {}
    if isfile(catPath) then
        for line in tostring(readfile(catPath)):gmatch("[^\r\n]+") do catLines[#catLines + 1] = line end
    end

    local added = 0
    for _, s in ipairs(songs) do
        local final, n = s.name, 1
        while isfile(dir .. "/" .. final .. ".txt") do
            n = n + 1
            final = s.name .. " (" .. n .. ")"
        end
        local head = {}
        local cats = s.cats or {}
        local custom = (#cats == 0) or (#cats == 1 and cats[1] == "custom")
        if not custom then head[#head + 1] = "--CAT:" .. table.concat(cats, ",") end
        head[#head + 1] = "--BPM:" .. tostring(s.bpm or "120")
        local okw = pcall(writefile, dir .. "/" .. final .. ".txt", table.concat(head, "\n") .. "\n" .. table.concat(s.sheet, "\n"))
        if okw then
            added = added + 1
            if not custom then catLines[#catLines + 1] = final .. "|" .. table.concat(cats, ",") end
        end
    end
    pcall(writefile, catPath, table.concat(catLines, "\n"))
    return added
end

-- Dùng khi chạy gói trực tiếp: đọc, kiểm tra rồi nhập
function M.run(text)
    local songs, err = M.parsePack(text)
    if not songs then
        notify("Error", "Invalid song pack: " .. tostring(err))
        return
    end
    local added, ierr = M.install(songs)
    if not added then
        notify("Error", tostring(ierr))
        return
    end
    notify("Success", "Imported " .. added .. " song(s)")
    if _G.AP_RefreshSongs then pcall(_G.AP_RefreshSongs) end
end

return M
