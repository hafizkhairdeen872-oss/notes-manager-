--[[
Plugin Name: Notes Manager Pro V1.0
Author: Hafiz Khair Din
Version: 1.0
Description: Advanced Smart Paging for Urdu Books
--]]
require "import"
import "android.widget.*"
import "android.view.*"
import "java.io.*"
import "android.content.*"
import "android.speech.tts.*"
import "java.util.Locale"
import "android.text.InputType"
import "android.os.Bundle"
import "java.util.HashMap"

local basePath = "/sdcard/JieshuoNotes/"
local configPath = basePath .. "config.dat"
local posPath = basePath .. "positions.dat"

if not File(basePath).exists() then File(basePath).mkdirs() end

local currentPath = basePath
local charLimit = 1500
local tts_obj = nil
local saved_engine = nil
local saved_lang = "Default"
local saved_voice = "Default"
local saved_speed = "1.0"
local lastReadPos = 0
local tempResumePos = 0 
local globalPositions = {}

function load_positions()
  local f = io.open(posPath, "r")
  if f then
    for line in f:lines() do
      local name, pos = line:match("^(.*)|(%d+)$")
      if name then globalPositions[name] = tonumber(pos) end
    end
    f:close()
  end
end

function save_position(fileName, pos)
  globalPositions[fileName] = pos
  local f = io.open(posPath, "w")
  if f then
    for k, v in pairs(globalPositions) do
      f:write(k .. "|" .. v .. "\n")
    end
    f:close()
  end
end

load_positions()

local function tts_speak(text)
  if not tts_obj or not text or text == "" then return end
  local ut_id = "id" .. os.clock()
  pcall(function()
    local params = Bundle()
    params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, ut_id)
    tts_obj.speak(text, TextToSpeech.QUEUE_FLUSH, params, ut_id)
  end)
end

function load_config()
  local f = io.open(configPath, "r")
  if f then
    saved_engine = f:read("*l")
    saved_lang = f:read("*l")
    saved_voice = f:read("*l")
    saved_speed = f:read("*l") or "1.0"
    f:close()
  end
end
load_config()

local playNextPage = nil 

function init_tts(engine_name)
  if tts_obj then tts_obj.stop(); tts_obj.shutdown() end
  tts_obj = TextToSpeech(service, TextToSpeech.OnInitListener{
    onInit=function(status)
      if status == TextToSpeech.SUCCESS then
        apply_tts_settings()
        tts_obj.setOnUtteranceProgressListener(UtteranceProgressListener{
          onRangeStart=function(utteranceId, start, _end, frame)
            lastReadPos = start 
          end,
          onDone=function(utteranceId)
            if playNextPage then playNextPage() end
          end
        })
      end
    end
  }, engine_name)
end

function apply_tts_settings()
  if tts_obj then
    if saved_lang and saved_lang ~= "Default" then
      local lang_code = saved_lang:match("%((.-)%)") or saved_lang
      tts_obj.setLanguage(Locale(lang_code))
    end
    if saved_speed then
      tts_obj.setSpeechRate(tonumber(saved_speed))
    end
    if saved_voice and saved_voice ~= "Default" then
      local voices = tts_obj.getVoices()
      if voices then
        local it = voices.iterator()
        while it.hasNext() do
          local v = it.next()
          if tostring(v.getName()) == saved_voice then
            tts_obj.setVoice(v)
            break
          end
        end
      end
    end
  end
end

init_tts(saved_engine)

function open_reader(title, content)
  local pages = {}
  
-- === Advanced Smart Page Break Logic ===
  local currentChunk = ""
  local hasSmartPaging = false

  for line in content:gmatch("[^\r\n]+") do
    local lower_line = string.lower(line)
    if lower_line:match("^%s*page number %d+%s*$") or 
       lower_line:match("^%s*page %d+%s*$") or 
       line:match("^%s*صفحہ %d+%s*$") then
       hasSmartPaging = true
       break
    end
  end

  if hasSmartPaging then
    for line in content:gmatch("[^\r\n]+") do
      local lower_line = string.lower(line)
      local isNewPage = lower_line:match("^%s*page number %d+%s*$") or 
                        lower_line:match("^%s*page %d+%s*$") or 
                        line:match("^%s*صفحہ %d+%s*$")
      
      if isNewPage then
        if currentChunk:gsub("%s", "") ~= "" then
          table.insert(pages, currentChunk)
        end
        currentChunk = line .. "\n"
      else
        currentChunk = currentChunk .. line .. "\n"
      end
    end
    if currentChunk:gsub("%s", "") ~= "" then table.insert(pages, currentChunk) end
  else
    for line in content:gmatch("[^\r\n]+") do
      if #currentChunk + #line > charLimit then
        table.insert(pages, currentChunk)
        currentChunk = line .. "\n"
      else
        currentChunk = currentChunk .. line .. "\n"
      end
    end
    if currentChunk ~= "" then table.insert(pages, currentChunk) end
  end
  
  if #pages == 0 then table.insert(pages, "No Content") end  local currentPage = 1
  tempResumePos = globalPositions[title] or 0
  lastReadPos = 0

  local layout = LinearLayout(service).setOrientation(1)
  local pageInfo = TextView(service).setText("Page " .. currentPage .. " of " .. #pages).setGravity(Gravity.CENTER).setPadding(0,10,0,20).setTextSize(20)
  layout.addView(pageInfo)

  local txtView = TextView(service).setText(pages[currentPage]).setPadding(30,30,30,30).setTextSize(18)
  local scroll = ScrollView(service); scroll.addView(txtView)
  layout.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1))

  local btnLayout = LinearLayout(service).setOrientation(1)
  local row1 = LinearLayout(service)
  local btnSearchPage = Button(service).setText("Search Page")
  local btnRewind = Button(service).setText("10s Backward")
  local btnForward = Button(service).setText("10s Forward")
  row1.addView(btnRewind, LinearLayout.LayoutParams(-1, -2, 1))
  row1.addView(btnSearchPage, LinearLayout.LayoutParams(-1, -2, 1.2))
  row1.addView(btnForward, LinearLayout.LayoutParams(-1, -2, 1))
  btnLayout.addView(row1)

  local row2 = LinearLayout(service)
  local btnPlay = Button(service).setText("Play")
  local btnPause = Button(service).setText("Pause")
  local btnStop = Button(service).setText("Stop")
  row2.addView(btnPlay, LinearLayout.LayoutParams(-1, -2, 1))
  row2.addView(btnPause, LinearLayout.LayoutParams(-1, -2, 1))
  row2.addView(btnStop, LinearLayout.LayoutParams(-1, -2, 1))
  btnLayout.addView(row2)

  local row3 = LinearLayout(service)
  local btnPrev = Button(service).setText("Previous Page")
  local btnNext = Button(service).setText("Next Page")
  row3.addView(btnPrev, LinearLayout.LayoutParams(-1, -2, 1))
  row3.addView(btnNext, LinearLayout.LayoutParams(-1, -2, 1))
  btnLayout.addView(row3)

  local btnBack = Button(service).setText("Back to Library")
  btnLayout.addView(btnBack)
  layout.addView(btnLayout)

  local readerDlg = LuaDialog(service).setTitle(title).setView(layout).show()

  playNextPage = function()
    if currentPage < #pages then
      service.handler.post(function()
        currentPage = currentPage + 1
        pageInfo.setText("Page " .. currentPage .. " of " .. #pages)
        txtView.setText(pages[currentPage])
        tempResumePos = 0
        lastReadPos = 0
        save_position(title, 0)
        tts_speak(pages[currentPage])
      end)
    end
  end

  local function update_page(index)
    if index >= 1 and index <= #pages then
      if tts_obj then tts_obj.stop() end
      currentPage = index
      pageInfo.setText("Page " .. currentPage .. " of " .. #pages)
      txtView.setText(pages[currentPage])
      tempResumePos = 0
      lastReadPos = 0
      save_position(title, 0)
      local textToRead = pages[currentPage]
      tts_speak(textToRead)
    end
  end

  btnSearchPage.onClick = function()
    local edit = EditText(service).setHint("Enter page number...").setInputType(InputType.TYPE_CLASS_NUMBER)
    LuaDialog(service).setTitle("Search Page").setView(edit).setPositiveButton("Go", function()
      local target = tonumber(edit.getText().toString())
      if target and target >= 1 and target <= #pages then
        update_page(target)
      else
        print("Invalid page number")
      end
    end).show()
  end

  btnPlay.onClick = function()
    local textToRead = pages[currentPage]:sub(tempResumePos + 1)
    tts_speak(textToRead)
  end

  btnPause.onClick = function()
    if tts_obj then 
      tts_obj.stop()
      tempResumePos = tempResumePos + lastReadPos
      lastReadPos = 0
      save_position(title, tempResumePos)
    end
  end

  btnStop.onClick = function()
    if tts_obj then tts_obj.stop() end
    tempResumePos = 0
    lastReadPos = 0
    save_position(title, 0)
  end

  btnForward.onClick = function()
    if tts_obj then tts_obj.stop() end
    tempResumePos = tempResumePos + lastReadPos + 200
    lastReadPos = 0
    if tempResumePos >= #pages[currentPage] then
      if currentPage < #pages then
        update_page(currentPage + 1)
      else
        print("End of Note")
      end
    else
      save_position(title, tempResumePos)
      tts_speak(pages[currentPage]:sub(tempResumePos + 1))
    end
  end

  btnRewind.onClick = function()
    if tts_obj then tts_obj.stop() end
    tempResumePos = (tempResumePos + lastReadPos) - 200
    lastReadPos = 0
    if tempResumePos < 0 then
      if currentPage > 1 then
        update_page(currentPage - 1)
      else
        tempResumePos = 0
        save_position(title, 0)
        tts_speak(pages[currentPage])
      end
    else
      save_position(title, tempResumePos)
      tts_speak(pages[currentPage]:sub(tempResumePos + 1))
    end
  end

  btnNext.onClick = function() if currentPage < #pages then update_page(currentPage + 1) end end
  btnPrev.onClick = function() if currentPage > 1 then update_page(currentPage - 1) end end
  btnBack.onClick = function() 
    if tts_obj then tts_obj.stop() end
    tempResumePos = tempResumePos + lastReadPos
    save_position(title, tempResumePos)
    readerDlg.dismiss()
    show_saved_notes(currentPath) 
  end
end

function main_menu()
  local items = {"New Note", "New Folder", "Library", "Settings", "About", "Exit"}
  local lv = ListView(service)
  lv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, items)
  local dlg = LuaDialog(service).setTitle("Notes Manager v1.0").setView(lv).show()
  lv.onItemClick = function(l, v, p, i)
    dlg.dismiss()
    if i == 0 then create_note_dialog() 
    elseif i == 1 then create_folder_dialog()
    elseif i == 2 then show_saved_notes(basePath) 
    elseif i == 3 then show_settings()
    elseif i == 4 then show_about_info()
    elseif i == 5 then service.stop()
    end
  end
end

function show_saved_notes(path, filter)
  currentPath = path
  local files = File(path).list()
  local items = {"[ Back to Main Menu ]", "[ Search Notes ]"}
  if tostring(path) ~= basePath then table.insert(items, ".. Back to Previous Folder") end
  if files then 
    for i=0, #files-1 do 
      local fname = files[i]
      if fname ~= "config.dat" and fname ~= "positions.dat" then
        if not filter or fname:lower():find(filter:lower()) then 
          table.insert(items, fname) 
        end 
      end
    end 
  end
  local lv = ListView(service); lv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, items)
  local dlg = LuaDialog(service).setTitle("Library").setView(lv).show()
  
  lv.onItemClick = function(l, v, p, i)
    local selected = items[i+1]
    if selected == "[ Back to Main Menu ]" then dlg.dismiss(); main_menu()
    elseif selected == "[ Search Notes ]" then
      dlg.dismiss()
      local se = EditText(service).setHint("Search...")
      LuaDialog(service).setTitle("Search").setView(se).setPositiveButton("Find", function() show_saved_notes(path, tostring(se.getText())) end).show()
    elseif selected == ".. Back to Previous Folder" then dlg.dismiss(); show_saved_notes(File(path).getParent() .. "/")
    elseif File(path .. selected).isDirectory() then dlg.dismiss(); show_saved_notes(path .. selected .. "/")
    else 
      dlg.dismiss()
      local f = io.open(currentPath .. selected, "r")
      local content = f and f:read("*a") or ""
      if f then f:close() end
      open_reader(selected, content)
    end
  end

  lv.onItemLongClick = function(l, v, p, i)
    local selected = items[i+1]
    if selected ~= "[ Back to Main Menu ]" and selected ~= "[ Search Notes ]" and selected ~= ".. Back to Previous Folder" then
      dlg.dismiss()
      show_note_options(selected)
      return true
    end
    return false
  end
end

function show_settings()
  local items = {"Engine: "..(saved_engine or "Default"), "Language: "..(saved_lang or "Default"), "Voice: "..(saved_voice or "Default"), "Speed: "..(saved_speed or "1.0"), "Back to Main"}
  local lv = ListView(service); lv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, items)
  local dlg = LuaDialog(service).setTitle("Settings").setView(lv).show()
  lv.onItemClick = function(l, v, p, i)
    dlg.dismiss()
    if i == 0 then
      local engines = tts_obj.getEngines()
      local names, labels = {}, {}
      for k=0, engines.size()-1 do table.insert(names, engines.get(k).name); table.insert(labels, engines.get(k).label) end
      table.insert(labels, "[ Back ]")
      local elv = ListView(service); elv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, labels)
      local edlg = LuaDialog(service).setTitle("Engines").setView(elv).show()
      elv.onItemClick = function(l2,v2,p2,i2) 
        edlg.dismiss()
        if labels[i2+1] ~= "[ Back ]" then saved_engine = names[i2+1]; save_and_reload() else show_settings() end
      end
    elseif i == 1 then
      local langs = {"Urdu (ur_PK)", "Urdu (ur_IN)", "English (en_US)", "Hindi (hi_IN)", "Arabic (ar_SA)", "Bengali (bn_BD)", "Chinese (zh_CN)", "Default", "[ Back ]"}
      local llv = ListView(service); llv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, langs)
      local ldlg = LuaDialog(service).setTitle("Select Language").setView(llv).show()
      llv.onItemClick = function(l3,v3,p3,i3) 
        ldlg.dismiss()
        if langs[i3+1] ~= "[ Back ]" then saved_lang = langs[i3+1]; save_and_reload() else show_settings() end
      end
    elseif i == 2 then
      local voices = tts_obj.getVoices()
      local v_names = {}
      if voices and voices.size() > 0 then
        local selected_lang_code = saved_lang:match("%((.-)%)") or ""
        local it = voices.iterator()
        while it.hasNext() do 
          local v = it.next()
          if selected_lang_code == "" or tostring(v.getLocale()):find(selected_lang_code) then table.insert(v_names, v.getName()) end
        end
      end
      table.insert(v_names, "[ Back ]")
      local vlv = ListView(service); vlv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, v_names)
      local vdlg = LuaDialog(service).setTitle("Select Voice").setView(vlv).show()
      vlv.onItemClick = function(l4,v4,p4,i4) 
        vdlg.dismiss()
        if v_names[i4+1] ~= "[ Back ]" then saved_voice = v_names[i4+1]; save_and_reload() else show_settings() end
      end
    elseif i == 3 then
      local speeds = {"0.5", "0.8", "1.0", "1.2", "1.5", "2.0", "[ Back ]"}
      local slv = ListView(service); slv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, speeds)
      local sdlg = LuaDialog(service).setTitle("Speech Speed").setView(slv).show()
      slv.onItemClick = function(l5,v5,p5,i5) 
        sdlg.dismiss()
        if speeds[i5+1] ~= "[ Back ]" then saved_speed = speeds[i5+1]; save_and_reload() else show_settings() end
      end
    elseif i == 4 then main_menu() end
  end
end

function save_and_reload()
  local f = io.open(configPath, "w")
  f:write((saved_engine or "Default") .. "\n" .. (saved_lang or "Default") .. "\n" .. (saved_voice or "Default") .. "\n" .. (saved_speed or "1.0"))
  f:close()
  init_tts(saved_engine)
  show_settings()
end

function show_note_options(fileName)
  local options = {"Read", "Copy", "Edit", "Share", "Delete", "Rename", "Back"}
  local lv = ListView(service); lv.adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, options)
  local dlg = LuaDialog(service).setTitle(fileName).setView(lv).show()
  lv.onItemClick = function(l, v, p, i)
    dlg.dismiss()
    local isDir = File(currentPath .. fileName).isDirectory()
    local content = ""
    if not isDir then
      local f = io.open(currentPath .. fileName, "r")
      if f then content = f:read("*a"); f:close() end
    else
      content = fileName
    end
    
    if i == 0 then 
      if isDir then show_saved_notes(currentPath .. fileName .. "/") else open_reader(fileName, content) end
    elseif i == 1 then 
      import "android.content.Context"
      import "android.content.ClipData"
      local textToCopy = content
      if #textToCopy > 100000 then
        textToCopy = string.sub(textToCopy, 1, 100000)
        print("کتاب بڑی ہے، صرف ابتدائی حصہ کاپی ہوا۔ مکمل شیئر کریں۔")
      else
        print("Copied")
      end
      pcall(function()
        local clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE)
        local clip = ClipData.newPlainText("Copied Note", textToCopy)
        clipboard.setPrimaryClip(clip)
      end)
    elseif i == 2 then 
      if isDir then rename_dialog(fileName) else create_note_dialog(fileName:gsub("%.txt$", ""), content) end
    elseif i == 3 then
      local intent = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, content)
      service.startActivity(Intent.createChooser(intent, "Share"))
    elseif i == 4 then 
      LuaDialog(service).setTitle("Warning")
      .setMessage("Are you sure you want to delete this? This action cannot be undone.")
      .setPositiveButton("Yes, Delete", function()
        if isDir then
          local function deleteDir(f)
            if f.isDirectory() then
              local files = f.listFiles()
              if files then for k=0, #files-1 do deleteDir(files[k]) end end
            end
            f.delete()
          end
          deleteDir(File(currentPath .. fileName))
        else
          File(currentPath .. fileName).delete()
        end
        print("Deleted successfully")
        show_saved_notes(currentPath)
      end)
      .setNegativeButton("Cancel", function() show_saved_notes(currentPath) end).show()
    elseif i == 5 then rename_dialog(fileName)
    elseif i == 6 then show_saved_notes(currentPath) end
  end
end

function create_note_dialog(n, c)
  local layout = LinearLayout(service).setOrientation(1)
  local eN = EditText(service).setHint("Title").setText(n or "")
  local eC = EditText(service).setHint("Content").setText(c or "")
  layout.addView(eN); layout.addView(eC)
  LuaDialog(service).setTitle("Editor").setView(layout).setPositiveButton("Save", function()
    local f = io.open(currentPath .. tostring(eN.getText()) .. ".txt", "w")
    f:write(tostring(eC.getText())):close()
    show_saved_notes(currentPath)
  end).setNegativeButton("Back", function() show_saved_notes(currentPath) end).show()
end

function rename_dialog(old)
  local isDir = File(currentPath .. old).isDirectory()
  local defaultText = isDir and old or old:gsub("%.txt$", "")
  local edit = EditText(service).setText(defaultText)
  LuaDialog(service).setTitle("Rename").setView(edit).setPositiveButton("OK", function()
    local newName = tostring(edit.getText())
    if not isDir and not newName:find("%.txt$") then newName = newName .. ".txt" end
    File(currentPath .. old).renameTo(File(currentPath .. newName))
    show_saved_notes(currentPath)
  end).setNegativeButton("Back", nil).show()
end

function create_folder_dialog()
  local e = EditText(service).setHint("Folder Name")
  LuaDialog(service).setTitle("New Folder").setView(e).setPositiveButton("Create", function()
    File(currentPath .. tostring(e.getText())).mkdirs(); show_saved_notes(currentPath)
  end).setNegativeButton("Back", function() show_saved_notes(currentPath) end).show()
end

function show_about_info()
  local info = "Notes Manager Pro\n" ..
               "Developer: Hafiz Khair Din\n" ..
               "Version: 1.0\n\n" ..
               "Advanced Smart Page Break for Urdu Books"
  LuaDialog(service).setTitle("About").setMessage(info).setPositiveButton("OK", function() main_menu() end).show()
end

main_menu()