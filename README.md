require "import"
import "com.androlua.*"
import "java.util.Calendar"
import "android.icu.util.IslamicCalendar"
import "android.content.Intent"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "java.io.File"

-- بیرونی ڈیٹا فائل کو لوڈ کریں
require "data"

local APP_TITLE = "دائمی جنتری - خانپور\nدرگاہ عالیہ دین پور شریف"

-- متغیرات برائے سیٹنگز
selectedCity = "خانپور"
hijriOffset = 0 -- ہجری تاریخ کی رویت کے مطابق ایڈجسٹمنٹ (-5 to +5)

-- شہروں کی ترتیب وار لسٹ
local cityNamesList = {
    "خانپور", "رحیم یار خان", "صادق آباد", "کوٹ سمابہ", "کوٹ سبزل", "سکھر", "شکار پور", 
    "نواب شاہ", "حیدر آباد", "کراچی", "احمد پور شرقیہ", "اوچ شریف", "لیاقت پور", 
    "ڈیرہ نواب", "بہاولپور", "ملتان", "مظفر گڑھ", "ڈیرہ غازی خان", "میانوالی", 
    "سرگودھا", "کوہاٹ", "سیالکوٹ", "گوجرانوالہ"
}

--------------------------------------------------
-- اذان کے لیے متغیرات (Settings)
--------------------------------------------------
azaanSettings = {
    ["سحری"] = false, ["فجر"] = false, ["طلوع"] = false,
    ["اشراق"] = false, ["زوال"] = false, ["ظہر"] = false,
    ["عصر اول"] = false, ["عصر ثانی"] = false,
    ["غروب"] = false, ["افطار"] = false, ["عشاء"] = false
}

local prayerNamesOrder = {"سحری", "فجر", "طلوع", "اشراق", "زوال", "ظہر", "عصر اول", "عصر ثانی", "غروب", "افطار", "عشاء"}

-- ٹاک بیک اور ڈسپلے کے لیے انگلش + اردو لیبلز
local prayerNamesEngUrdu = {
    ["سحری"] = "Sehri (سحری)",
    ["فجر"] = "Fajr (فجر)",
    ["طلوع"] = "Sunrise (طلوع)",
    ["اشراق"] = "Ishraq (اشراق)",
    ["زوال"] = "Zawal (زوال)",
    ["ظہر"] = "Zuhr (ظہر)",
    ["عصر اول"] = "Asr 1 (عصر اول)",
    ["عصر ثانی"] = "Asr 2 (عصر ثانی)",
    ["غروب"] = "Sunset (غروب)",
    ["افطار"] = "Iftar (افطار)",
    ["عشاء"] = "Isha (عشاء)"
}

--------------------------------------------------
-- ایپ کی ڈائریکٹری معلوم کرنے کا مضبوط فنکشن
--------------------------------------------------
local function getAppDir()
    local dir = nil
    pcall(function()
        local info = debug.getinfo(1, "S")
        if info and info.source and info.source:match("^@") then
            dir = info.source:sub(2):match("(.*)/")
        end
    end)
    if not dir or dir == "" or dir == "nil" then
        pcall(function()
            if this and this.getLuaDir then dir = tostring(this.getLuaDir())
            elseif activity and activity.getLuaDir then dir = tostring(activity.getLuaDir())
            elseif service and service.getLuaDir then dir = tostring(service.getLuaDir()) end
        end)
    end
    if dir then return string.gsub(dir, "/$", "") else return "" end
end

--------------------------------------------------
-- سیٹنگز کو فائل میں محفوظ کرنے اور پڑھنے کا سسٹم
--------------------------------------------------
local function saveSettingsToFile(tempSettings)
    pcall(function()
        local luaDir = getAppDir()
        if luaDir == "" then return end
        local settingsPath = luaDir .. "/azaan_settings.txt"
        local f = io.open(settingsPath, "w")
        if f then
            f:write("selectedCity=" .. tostring(selectedCity) .. "\n")
            f:write("hijriOffset=" .. tostring(hijriOffset) .. "\n")
            for k, v in pairs(tempSettings) do
                f:write(k .. "=" .. tostring(v) .. "\n")
            end
            f:close()
        end
    end)
end

local function loadSettingsFromFile()
    pcall(function()
        local luaDir = getAppDir()
        if luaDir == "" then return end
        local settingsPath = luaDir .. "/azaan_settings.txt"
        local f = io.open(settingsPath, "r")
        if f then
            for line in f:lines() do
                local k, v = line:match("(.+)%=(.+)")
                if k and v then
                    if k == "selectedCity" then
                        selectedCity = v
                    elseif k == "hijriOffset" then
                        hijriOffset = tonumber(v) or 0
                    else
                        azaanSettings[k] = (v == "true")
                    end
                end
            end
            f:close()
        end
    end)
end

-- ایپ شروع ہوتے ہی پرانی محفوظ شدہ سیٹنگز لوڈ کریں
loadSettingsFromFile()

--------------------------------------------------
-- وقت ایڈجسٹ کرنے کا فنکشن
--------------------------------------------------
local function adjustTime(timeStr, offsetMinutes)
  if not timeStr or offsetMinutes == 0 then return timeStr end
  local h, m = timeStr:match("(%d+):(%d+)")
  h = tonumber(h)
  m = tonumber(m)
  m = m + offsetMinutes
  while m >= 60 do
    m = m - 60
    h = h + 1
    if h > 12 then h = 1 end
  end
  while m < 0 do
    m = m + 60
    h = h - 1
    if h < 1 then h = 12 end
  end
  return string.format("%d:%02d", h, m)
end

--------------------------------------------------
--------------------------------------------------
-- 24 گھنٹے والے منٹوں میں تبدیل کرنے کا فنکشن (وقت کا موازنہ کرنے کے لیے)
--------------------------------------------------
local function parseTimeToMinutes24(timeStr, isPMType)
    local h, m = timeStr:match("(%d+):(%d+)")
    h = tonumber(h)
    m = tonumber(m)
    if h == 12 then h = 0 end 
    if isPMType then h = h + 12 end
    return (h * 60) + m
end

--------------------------------------------------
-- اوقاتِ نماز دکھانے کا فنکشن
--------------------------------------------------
function showPrayerTimes(mIdx)
  local list = {}
  local data = khanpurData[mIdx]
  if not data or #data == 0 then 
    print("Data not available for this month.") 
    return 
  end

  local offset = cityOffsets[selectedCity] or 0
  
  local cal = Calendar.getInstance()
  local currentMonth = cal.get(Calendar.MONTH) + 1
  local currentDay = cal.get(Calendar.DAY_OF_MONTH)
  local currentYear = cal.get(Calendar.YEAR)

  -- دنوں کے نام (انگلش اور اردو)
  local daysOfWeek = {
      [Calendar.SUNDAY]    = "Sunday (اتوار)",
      [Calendar.MONDAY]    = "Monday (پیر)",
      [Calendar.TUESDAY]   = "Tuesday (منگل)",
      [Calendar.WEDNESDAY] = "Wednesday (بدھ)",
      [Calendar.THURSDAY]  = "Thursday (جمعرات)",
      [Calendar.FRIDAY]    = "Friday (جمعہ)",
      [Calendar.SATURDAY]  = "Saturday (ہفتہ)"
  }

  if mIdx == currentMonth and data[currentDay] then
    local t = data[currentDay]
    
    local gcal = Calendar.getInstance()
    if hijriOffset ~= 0 then gcal.add(Calendar.DAY_OF_MONTH, hijriOffset) end
    local h = IslamicCalendar()
    h.setTime(gcal.getTime())
    local hijriStr = h.get(IslamicCalendar.DAY_OF_MONTH) .. " " .. hijriMonths[h.get(IslamicCalendar.MONTH)+1] .. " " .. h.get(IslamicCalendar.YEAR) .. "ھ"
    
    local dayOfWeekStr = daysOfWeek[cal.get(Calendar.DAY_OF_WEEK)] or ""

    -- موجودہ وقت منٹوں میں
    local current_total_m = (cal.get(Calendar.HOUR_OF_DAY) * 60) + cal.get(Calendar.MINUTE)
    
    local eventsCheck = {
        {name="Sehri (سحری)", idx=1, isPM=false},
        {name="Fajr (فجر)", idx=2, isPM=false},
        {name="Sunrise (طلوع)", idx=3, isPM=false},
        {name="Ishraq (اشراق)", idx=4, isPM=false},
        {name="Zawal (زوال)", idx=5, isPM=true},
        {name="Zuhr (ظہر)", idx=6, isPM=true},
        {name="Asr 1 (عصر اول)", idx=7, isPM=true},
        {name="Asr 2 (عصر ثانی)", idx=8, isPM=true},
        {name="Sunset (غروب)", idx=9, isPM=true},
        {name="Iftar (افطار)", idx=10, isPM=true},
        {name="Isha (عشاء)", idx=11, isPM=true}
    }

    local nextEventName = ""
    local nextEventTime = ""

    -- چیک کریں کہ اگلی نماز کون سی ہے
    for _, ev in ipairs(eventsCheck) do
        local adjStr = adjustTime(t[ev.idx], offset)
        local evMins = parseTimeToMinutes24(adjStr, ev.isPM)
        if current_total_m < evMins then
            nextEventName = ev.name
            nextEventTime = adjStr
            break
        end
    end

    -- اگر عشاء کا وقت بھی گزر چکا ہو تو اگلا دن سحری کا دکھائے گا
    if nextEventName == "" then
        nextEventName = "Sehri (سحری) - Tomorrow"
        nextEventTime = "--:--"
    end

    local todayStr = ">>> آج کا دن (TODAY) <<<\n" ..
      "دن: " .. dayOfWeekStr .. "\n" ..
      "عیسوی تاریخ: " .. currentDay .. " " .. monthNames[mIdx] .. " " .. currentYear .. "\n" ..
      "ہجری تاریخ: " .. hijriStr .. "\n" ..
      "شہر: " .. selectedCity .. "\n" ..
      "-----------------------------------\n" ..
      "👉 آنے والا وقت (Next Event):\n" ..
      nextEventName .. " : " .. nextEventTime .. "\n" ..
      "==================================="
      
    table.insert(list, todayStr)
  end

  for d, t in ipairs(data) do
    table.insert(list, "Date (تاریخ): "..d.." "..monthNames[mIdx].." ("..selectedCity..")\n"..
      "Sehri (سحری): "..adjustTime(t[1], offset).." | Fajr (فجر): "..adjustTime(t[2], offset).." | Sunrise (طلوع): "..adjustTime(t[3], offset).."\n"..
      "Ishraq (اشراق): "..adjustTime(t[4], offset).." | Zawal (زوال): "..adjustTime(t[5], offset).." | Zuhr (ظہر): "..adjustTime(t[6], offset).."\n"..
      "Asr 1 (عصر اول): "..adjustTime(t[7], offset).." | Asr 2 (عصر ثانی): "..adjustTime(t[8], offset).."\n"..
      "Sunset (غروب): "..adjustTime(t[9], offset).." | Iftar (افطار): "..adjustTime(t[10], offset).." | Isha (عشاء): "..adjustTime(t[11], offset).."\n"..
      "-----------------------------------")
  end
  local dlg = LuaDialog(this).setTitle(monthNames[mIdx].." - Timings ("..selectedCity..")").setItems(list)
  dlg.setButton("Back", function() dlg.dismiss() end).show()
end
      "Sehri (سحری): "..adjustTime(t[1], offset).." | Fajr (فجر): "..adjustTime(t[2], offset).." | Sunrise (طلوع): "..adjustTime(t[3], offset).."\n"..
      "Ishraq (اشراق): "..adjustTime(t[4], offset).." | Zawal (زوال): "..adjustTime(t[5], offset).." | Zuhr (ظہر): "..adjustTime(t[6], offset).."\n"..
      "Asr 1 (عصر اول): "..adjustTime(t[7], offset).." | Asr 2 (عصر ثانی): "..adjustTime(t[8], offset).."\n"..
      "Sunset (غروب): "..adjustTime(t[9], offset).." | Iftar (افطار): "..adjustTime(t[10], offset).." | Isha (عشاء): "..adjustTime(t[11], offset).."\n"..
      "==================================="
      
    table.insert(list, todayStr)
  end

  for d, t in ipairs(data) do
    table.insert(list, "Date (تاریخ): "..d.." "..monthNames[mIdx].." ("..selectedCity..")\n"..
      "Sehri (سحری): "..adjustTime(t[1], offset).." | Fajr (فجر): "..adjustTime(t[2], offset).." | Sunrise (طلوع): "..adjustTime(t[3], offset).."\n"..
      "Ishraq (اشراق): "..adjustTime(t[4], offset).." | Zawal (زوال): "..adjustTime(t[5], offset).." | Zuhr (ظہر): "..adjustTime(t[6], offset).."\n"..
      "Asr 1 (عصر اول): "..adjustTime(t[7], offset).." | Asr 2 (عصر ثانی): "..adjustTime(t[8], offset).."\n"..
      "Sunset (غروب): "..adjustTime(t[9], offset).." | Iftar (افطار): "..adjustTime(t[10], offset).." | Isha (عشاء): "..adjustTime(t[11], offset).."\n"..
      "-----------------------------------")
  end
  local dlg = LuaDialog(this).setTitle(monthNames[mIdx].." - Timings ("..selectedCity..")").setItems(list)
  dlg.setButton("Back", function() dlg.dismiss() end).show()
end

--------------------------------------------------
-- اسلامی کلینڈر دکھانے کا فنکشن
--------------------------------------------------
function showCalendarMonth(mIdx)
  local gcal = Calendar.getInstance()
  local year = gcal.get(Calendar.YEAR)
  local md = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
  if (year%4==0 and year%100~=0) or (year%400==0) then md[2] = 29 end
  local list = {}

  for d = 1, md[mIdx] do
    gcal.set(year, mIdx-1, d)
    if hijriOffset ~= 0 then
      gcal.add(Calendar.DAY_OF_MONTH, hijriOffset)
    end

    local h = IslamicCalendar()
    h.setTime(gcal.getTime())
    
    if hijriOffset ~= 0 then
      gcal.add(Calendar.DAY_OF_MONTH, -hijriOffset)
    end

    table.insert(list, 
      d.." "..monthNames[mIdx].." "..year..
      "  |  "..h.get(IslamicCalendar.DAY_OF_MONTH)..
      " "..hijriMonths[h.get(IslamicCalendar.MONTH)+1]..
      " "..h.get(IslamicCalendar.YEAR).."ھ"
    )
  end
  local dlg = LuaDialog(this).setTitle("Hijri Calendar - "..monthNames[mIdx])
  dlg.setItems(list)
  dlg.setButton("Back", function() dlg.dismiss() end).show()
end

--------------------------------------------------
-- مسائلِ نماز دکھانے کا فنکشن
--------------------------------------------------
function showMasailMenu()
  local sections = {
    "1. Conditions of Prayer (نماز کی شرائط)",
    "2. Pillars of Prayer (نماز کے ارکان)",
    "3. Obligations of Prayer (نماز کے واجبات)",
    "4. Disliked Acts (نماز کے مکروہات)",
    "5. Forbidden Times (مکروہ اوقات)"
  }
  local d = LuaDialog(this).setTitle("Prayer Rules (Fiqh Hanafi)")
  d.setItems(sections)
  d.onItemClick = function(l, v, p, i)
    local target = nil
    if i == 1 then target = namazMasail.sharaait
    elseif i == 2 then target = namazMasail.faraaiz
    elseif i == 3 then target = namazMasail.wajibbaat
    elseif i == 4 then target = namazMasail.makroohat
    elseif i == 5 then target = namazMasail.awqaatMakrooha end

    if target then
      local text = table.concat(target.items, "\n\n")
      LuaDialog(this)
        .setTitle(target.title)
        .setMessage(text)
        .setButton("Back", function(dlg) dlg.dismiss() end)
        .show()
    end
  end
  d.setButton("Back", function() d.dismiss() end).show()
end

--------------------------------------------------
-- انفو ونڈو
--------------------------------------------------
function showInfo()
  local infoText = [[
Source of Data:
مدرسه عربیہ صدیقیه راشدیہ دائمی جنتری درگاه عالیه دین پور شریف

Original Creator:
حافظ کریم الدین

App Developer:
اسے حافظ خیر دن نے بنایا ہے
]]
  LuaDialog(this)
    .setTitle("Info")
    .setMessage(infoText)
    .setButton("Back", function(d) d.dismiss() end)
    .show()
end

--------------------------------------------------
-- اذان الارم سیٹنگز مینیو
--------------------------------------------------
function showAzaanSettings(tempSettings)
  if tempSettings == nil then
    tempSettings = {}
    for k, v in pairs(azaanSettings) do
      tempSettings[k] = v
    end
  end

  local list = {}
  for i, name in ipairs(prayerNamesOrder) do
    local displayName = prayerNamesEngUrdu[name] or name
    local mark = tempSettings[name] and " [ Selected ✓ ]" or " [ Unselected ]"
    table.insert(list, displayName .. mark)
  end
  
  local d = LuaDialog(this).setTitle("Select Times for Azaan/Alarm")
  d.setItems(list)
  d.onItemClick = function(l, v, p, i)
    local name = prayerNamesOrder[i]
    tempSettings[name] = not tempSettings[name]
    d.dismiss()
    showAzaanSettings(tempSettings) 
  end
  
  d.setButton("Save", function()
    for k, v in pairs(tempSettings) do
      azaanSettings[k] = v
    end
    saveSettingsToFile(azaanSettings) -- سیٹنگز کو فائل میں پکا محفوظ کر لیا
    print("Settings Saved! Alarm timer started.")
    d.dismiss()
    showSettingsMenu()
  end)
  
  d.setButton2("Cancel", function()
    d.dismiss()
    showSettingsMenu()
  end)

  d.show()
end

--------------------------------------------------
-- سیٹنگز مینیو 
--------------------------------------------------
function showSettingsMenu()
  local options = {
    "Select City (Current: " .. selectedCity .. ")",
    "Adjust Hijri Date (Current: " .. (hijriOffset > 0 and "+" or "") .. hijriOffset .. ")",
    "Azaan Alarms (اذان الارم)"
  }
  local d = LuaDialog(this).setTitle("Settings")
  d.setItems(options)
  d.onItemClick = function(l, v, p, i)
    d.dismiss()
    if i == 1 then
      local displayCities = {}
      for idx, city in ipairs(cityNamesList) do
        if city == selectedCity then table.insert(displayCities, city .. " [✓]")
        else table.insert(displayCities, city) end
      end
      local cd = LuaDialog(this).setTitle("Select Your City").setItems(displayCities)
      cd.onItemClick = function(l2, v2, p2, i2)
        selectedCity = cityNamesList[i2]
        saveSettingsToFile(azaanSettings) -- نیا شہر بھی فائل میں محفوظ ہو گیا
        cd.dismiss()
        showSettingsMenu()
      end
      cd.setButton("Back", function() cd.dismiss() showSettingsMenu() end).show()

    elseif i == 2 then
      local offsetOptions = {}
      local offsetValues = {}
      for val = -5, 5 do
        local label = tostring(val)
        if val > 0 then label = "+" .. label end
        if val == hijriOffset then label = label .. " [✓]" end
        table.insert(offsetOptions, label)
        table.insert(offsetValues, val)
      end
      local hd = LuaDialog(this).setTitle("Adjust Hijri Offset (Days)").setItems(offsetOptions)
      hd.onItemClick = function(l3, v3, p3, i3)
        hijriOffset = offsetValues[i3]
        saveSettingsToFile(azaanSettings) -- نئی ہجری تاریخ بھی فائل میں محفوظ ہو گئی
        hd.dismiss()
        showSettingsMenu()
      end
      hd.setButton("Back", function() hd.dismiss() showSettingsMenu() end).show()
      
    elseif i == 3 then
      showAzaanSettings(nil)
    end
  end
  d.setButton("Back", function() d.dismiss() end).show()
end

--------------------------------------------------
-- واٹس ایپ فیڈ بیک فنکشن
--------------------------------------------------
function openWhatsAppFeedback()
  local url = "https://wa.me/923087279148"
  local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  
  if service then
    service.startActivity(intent)
  elseif this then
    this.startActivity(intent)
  end
end


--------------------------------------------------
--------------------------------------------------
--------------------------------------------------
-- اذان پلے کرنے اور نوٹیفکیشن دینے کا سسٹم (ہینگ ہونے والے مسئلے کا مکمل حل)
--------------------------------------------------
function playAzaanAudio(prayerName)
    local luaDir = getAppDir()
    local audioPath = luaDir .. "/azaan.mp3" 
    local file = File(audioPath)
    
    if file.exists() then
        -- 1. الارم بجتے ہی سکرین کو زبردستی آن (Wake Up) کرنے کا نیا کوڈ
        pcall(function()
            local Context = luajava.bindClass("android.content.Context")
            local context = service or this
            if context then
                local pm = context.getSystemService(Context.POWER_SERVICE)
                -- 268435466 = SCREEN_BRIGHT_WAKE_LOCK اور ACQUIRE_CAUSES_WAKEUP 
                local wakeLock = pm.newWakeLock(268435466, "Jieshuo:AzaanWakeLock")
                wakeLock.acquire(15000) -- 15 سیکنڈ کے لیے سکرین کی لائٹ آن رکھے گا
            end
        end)

        -- 2. ٹوسٹ نوٹیفکیشن دینے کا عمل
        pcall(function()
            local Handler = luajava.bindClass("android.os.Handler")
            local Looper = luajava.bindClass("android.os.Looper")
            local Runnable = luajava.bindClass("java.lang.Runnable")
            Handler(Looper.getMainLooper()).post(Runnable{
                run = function()
                    local msg = "اذان / الارم: نماز کا وقت شروع ہو گیا ہے!"
                    if prayerName then
                        msg = "اذان / الارم: " .. prayerName .. " کا وقت شروع ہو گیا ہے!"
                    end
                    print(msg)
                end
            })
        end)
        
        -- 3. آڈیو پلے کرنے کا نیا اور محفوظ ترین طریقہ (جو موبائل ہرگز ہینگ نہیں کرے گا)
        pcall(function()
            local MediaPlayer = luajava.bindClass("android.media.MediaPlayer")
            local player = MediaPlayer()
            player.setDataSource(audioPath)
            player.prepare()
            player.start()
            
            -- پچھلے کوڈ کی تھریڈ ڈیلیٹ کر دی گئی ہے، اب آڈیو خود بخود ختم ہو کر کلئیر ہو جائے گی
            player.setOnCompletionListener(MediaPlayer.OnCompletionListener{
                onCompletion = function(mp)
                    pcall(function() mp.release() end)
                end
            })
        end)
    else
        print("Audio not found at:\n" .. audioPath)
    end
end

-- وقت کو 24 گھنٹے والے منٹوں میں تبدیل کرنے کا فنکشن
local function parseTimeToMinutes24(timeStr, isPMType)
    local h, m = timeStr:match("(%d+):(%d+)")
    h = tonumber(h)
    m = tonumber(m)
    if h == 12 then h = 0 end 
    if isPMType then h = h + 12 end
    return (h * 60) + m
end

-- یہ فنکشن ہر ایک منٹ بعد چیک کرے گا
_G.doAzaanCheck = function()
    pcall(function()
        loadSettingsFromFile() 
        
        local cal = Calendar.getInstance()
        local current_h24 = cal.get(Calendar.HOUR_OF_DAY)
        local current_m = cal.get(Calendar.MINUTE)
        local current_total_m = (current_h24 * 60) + current_m
        
        local mIdx = cal.get(Calendar.MONTH) + 1
        local dIdx = cal.get(Calendar.DAY_OF_MONTH)
        
        if khanpurData and khanpurData[mIdx] and khanpurData[mIdx][dIdx] then
            local todayData = khanpurData[mIdx][dIdx]
            local offset = cityOffsets[selectedCity] or 0
            
            local times = {
                ["سحری"] = adjustTime(todayData[1], offset),
                ["فجر"] = adjustTime(todayData[2], offset),
                ["طلوع"] = adjustTime(todayData[3], offset),
                ["اشراق"] = adjustTime(todayData[4], offset),
                ["زوال"] = adjustTime(todayData[5], offset),
                ["ظہر"] = adjustTime(todayData[6], offset),
                ["عصر اول"] = adjustTime(todayData[7], offset),
                ["عصر ثانی"] = adjustTime(todayData[8], offset),
                ["غروب"] = adjustTime(todayData[9], offset),
                ["افطار"] = adjustTime(todayData[10], offset),
                ["عشاء"] = adjustTime(todayData[11], offset)
            }

            local pmTypes = {
                ["زوال"]=true, ["ظہر"]=true, ["عصر اول"]=true, 
                ["عصر ثانی"]=true, ["غروب"]=true, ["افطار"]=true, ["عشاء"]=true
            }

            for name, pTime in pairs(times) do
                if azaanSettings[name] then
                    local isPMType = pmTypes[name] or false
                    local prayer_total_m = parseTimeToMinutes24(pTime, isPMType)
                    
                    -- اب یہ ٹھیک اسی وقت چلے گا جب نماز کا ٹائم ہوگا
                    if current_total_m == prayer_total_m then
                        local dateStr = cal.get(Calendar.DAY_OF_MONTH) .. "-" .. cal.get(Calendar.MONTH)
                        local uniqueKey = name .. "_" .. dateStr
                        
                        if _G.lastPlayedTime ~= uniqueKey then
                            _G.lastPlayedTime = uniqueKey
                            playAzaanAudio(name) 
                        end
                    end
                end
            end
        end
    end)
end

-- ٹائمر شروع کرنے کا کوڈ
if not _G.azaanTimerStarted then
    _G.azaanTimerStarted = true
    print("اذان کا آٹو ٹائمر آن ہو گیا ہے۔")
    
    local Handler = luajava.bindClass("android.os.Handler")
    local Looper = luajava.bindClass("android.os.Looper")
    local Runnable = luajava.bindClass("java.lang.Runnable")
    
    _G.azaanHandler = Handler(Looper.getMainLooper())
    _G.azaanRunnable = Runnable{
        run = function()
            if _G.doAzaanCheck then _G.doAzaanCheck() end
            _G.azaanHandler.postDelayed(_G.azaanRunnable, 60000)
        end
    }
    
    if _G.doAzaanCheck then _G.doAzaanCheck() end
    _G.azaanHandler.postDelayed(_G.azaanRunnable, 60000)
end-- مین مینیو (Main Menu)
--------------------------------------------------
function MainMenu()
  local d = LuaDialog(this).setTitle(APP_TITLE)
  d.setItems({
    "Prayer Times",
    "Islamic Calendar",
    "Prayer Rules (Masail)",
    "Settings",
    "Info",
    "Feedback",
    "Exit"
  })
  
  d.onItemClick = function(l, v, p, i)
    if i == 1 then
      local m = LuaDialog(this).setTitle("Select Month").setItems(monthNames)
      m.onItemClick = function(l2, v2, p2, i2) showPrayerTimes(i2) end
      m.setButton("Back", function() m.dismiss() end).show()

    elseif i == 2 then
      local m = LuaDialog(this).setTitle("Select Month").setItems(monthNames)
      m.onItemClick = function(l2, v2, p2, i2) showCalendarMonth(i2) end
      m.setButton("Back", function() m.dismiss() end).show()

    elseif i == 3 then
      showMasailMenu()

    elseif i == 4 then
      showSettingsMenu()

    elseif i == 5 then
      showInfo()
      
    elseif i == 6 then
      local fd = LuaDialog(this).setTitle("Feedback")
      fd.setItems({"Contact WhatsApp"})
      fd.onItemClick = function(fl, fv, fp, fi)
        if fi == 1 then
          fd.dismiss() 
          d.dismiss()  
          openWhatsAppFeedback() 
        end
      end
      fd.setButton("Back", function() fd.dismiss() end)
      fd.show()

    elseif i == 7 then
      d.dismiss()
    end
  end
  d.show()
end

MainMenu()