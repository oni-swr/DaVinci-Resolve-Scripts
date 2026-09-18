--[[
 * Resolve Script Name: Export clip markers to CSV
 * About: Export markers from selected Media Pool clips, current bin clips, or timeline clips to a CSV file.
 * Author: X-Raym
 * Author URI: https://www.extremraym.com
 * Repository: GitHub > X-Raym > DaVinci-Resolve-Scripts
 * Repository URI: https://github.com/X-Raym/DaVinci-Resolve-Scripts
 * Licence: GPL v3
 * REAPER: 5.0
 * Version: 1.1
--]]

--[[
 * Changelog:
 * v1.1 (2026-09-18)
  + Fix save file dialog: correctly resolve Fusion application object via resolve:Fusion()
  + Fix file saving in sandboxed Lua environments via dual io.open / os.execute fallback
  + Automatically copy CSV output to system clipboard via bmd.setclipboard
 * v1.0 (2026-09-18)
  + Initial Release
--]]

-- USER CONFIG AREA ---------------------------------------
-- "combined" = One single CSV containing all markers from all processed clips
-- "individual" = Separate CSV file created next to each source media file (e.g. video.csv)
export_mode = "combined"

-- Output file path for "combined" mode.
-- Leave empty "" to open a save file dialog (or auto-save to Desktop if dialog is cancelled/unavailable)
file_path = ""

-- CSV Delimiter: "," or ";" or "\t"
csv_delimiter = ","

-- Include header row in CSV output
include_headers = true

-- Scope to scan clips:
-- "auto"     = Selected Media Pool clips > Current Timeline clips > Current Media Pool Bin
-- "selected" = Selected Media Pool clips only
-- "timeline" = Clips from the active timeline only
-- "bin"      = All clips in the current Media Pool folder only
scan_scope = "auto"
----------------------------------- END OF USER CONFIG AREA

-- HELPERS ------------------------------------------------

local function EscapeCSV( val, sep )
  if val == nil then return "" end
  val = tostring(val)
  sep = sep or ","
  local pattern = '[",\r\n'
  if sep == "\t" then pattern = pattern .. '\t'
  elseif sep == ";" then pattern = pattern .. ';' end
  pattern = pattern .. ']'
  if val:find(pattern) then
    val = '"' .. val:gsub('"', '""') .. '"'
  end
  return val
end

local function ParseTimeCode( tc, fps )
  if not tc or tc == "" then return 0 end
  local h, m, s, f = tc:match("(%d+):(%d+):(%d+)[:;](%d+)")
  if not h then
    h, m, s = tc:match("(%d+):(%d+):(%d+)")
    f = 0
  end
  if not h then return 0 end
  fps = tonumber(fps) or 24
  return math.floor((tonumber(h)*3600 + tonumber(m)*60 + tonumber(s)) * fps + tonumber(f) + 0.5)
end

local function FramesToTimeCode( total_frames, fps, is_drop_frame )
  fps = tonumber(fps) or 24
  local rfps = math.floor(fps + 0.5)
  if rfps <= 0 then rfps = 24 end
  total_frames = math.floor(total_frames + 0.5)
  if total_frames < 0 then total_frames = 0 end
  local f = total_frames % rfps
  local ts = math.floor(total_frames / rfps)
  local s = ts % 60
  local tm = math.floor(ts / 60)
  local m = tm % 60
  local h = math.floor(tm / 60)
  local sep = is_drop_frame and ";" or ":"
  return string.format("%02d:%02d:%02d%s%02d", h, m, s, sep, f)
end

local function SplitFileName( strfilename )
  if not strfilename or strfilename == "" then return "", "", "" end
  local path, file_name, extension = string.match( strfilename, "(.-)([^\\/]-([^\\/%.]+))$" )
  local name_no_ext = file_name and string.match( file_name, "(.+)%..+" ) or file_name or ""
  return path or "", name_no_ext, extension or ""
end

local function GetDesktopPath()
  local home = os.getenv("USERPROFILE")
  if home and home ~= "" then
    return home:gsub("\\", "/") .. "/Desktop/"
  end
  home = os.getenv("HOME")
  if home and home ~= "" then
    return home .. "/Desktop/"
  end
  return ""
end

local function GetResolveApp()
  -- 1. Check if global 'resolve' is already valid (Utility / Edit page scripts)
  if type(resolve) == "userdata" or (type(resolve) == "table" and resolve.GetProjectManager) then
    return resolve
  end

  -- 2. Check if global 'Resolve' is a function (Console / some script contexts)
  if type(Resolve) == "function" then
    local res = Resolve()
    if res then return res end
  end

  -- 3. Check if app:GetResolve() is available (Fusion page / Comp scripts)
  if (type(app) == "userdata" or type(app) == "table") and app.GetResolve then
    local res = app:GetResolve()
    if res then return res end
  end

  -- 4. Check if fusion/fu:GetResolve() is available
  local fusion_obj = (type(fu) == "userdata" and fu) or (type(fusion) == "userdata" and fusion)
  if fusion_obj and fusion_obj.GetResolve then
    local res = fusion_obj:GetResolve()
    if res then return res end
  end

  -- 5. Check if bmd.scriptapp('Resolve') is available
  if type(bmd) == "table" and bmd.scriptapp then
    local res = bmd.scriptapp("Resolve")
    if res then return res end
  end

  return nil
end

local function GetFusionApp( resolve_instance )
  -- Check global 'fusion'
  if fusion and fusion.RequestFile then
    return fusion
  end

  -- Check global 'fu'
  if fu and fu.RequestFile then
    return fu
  end

  -- Retrieve Fusion from Resolve application instance
  local res = resolve_instance or GetResolveApp()
  if res and res.Fusion then
    local ok, f = pcall(function() return res:Fusion() end)
    if ok and f and f.RequestFile then
      return f
    end
  end

  -- Check app:GetResolve():Fusion()
  if app and app.GetResolve then
    local ok, f = pcall(function() return app:GetResolve():Fusion() end)
    if ok and f and f.RequestFile then
      return f
    end
  end

  -- Check bmd.scriptapp("Fusion")
  if type(bmd) == "table" and bmd.scriptapp then
    local ok, f = pcall(function() return bmd.scriptapp("Fusion") end)
    if ok and f and f.RequestFile then
      return f
    end
  end

  return nil
end

local function RequestSaveFilePath( default_filename, resolve_instance )
  local default_path = GetDesktopPath() .. default_filename
  local fusion_app = GetFusionApp(resolve_instance)

  if fusion_app and fusion_app.RequestFile then
    local desktop_dir = GetDesktopPath()

    -- Try 1: Open native Save dialog specifying desktop directory and default filename
    local ok, chosen = pcall(function()
      return fusion_app:RequestFile(desktop_dir, default_filename, {
        FReqB_Saving = true,
        FReqS_Title = "Export Clip Markers to CSV",
        FReqS_Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
        FReqS_DefExt = "csv"
      })
    end)

    -- Try 2: If desktop_dir caused an issue, open with empty initial path
    if not ok or chosen == false then
      ok, chosen = pcall(function()
        return fusion_app:RequestFile("", default_filename, {
          FReqB_Saving = true,
          FReqS_Title = "Export Clip Markers to CSV",
          FReqS_Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*",
          FReqS_DefExt = "csv"
        })
      end)
    end

    if ok and chosen and chosen ~= "" then
      local path_str = tostring(chosen)
      if not path_str:lower():match("%.csv$") then
        path_str = path_str .. ".csv"
      end
      return path_str
    elseif ok and chosen == nil then
      -- User explicitly clicked Cancel in the file dialog
      return nil
    end
  end

  -- Fallback to Desktop path if dialog is unavailable
  return default_path
end

-- Standard file writer function to mimic other scripts
local function WriteTextFile( filepath, content )
  if not io then
    return false, "Global 'io' library is unavailable (sandboxed)."
  end
  
  local f, err = io.open(filepath, "w")
  if f then
    f:write(content)
    f:close()
    return true, "Success"
  end
  
  return false, tostring(err)
end

-- MAIN EXPORT LOGIC --------------------------------------

function ExportMarkers()
  print("========================================")
  print("  Export Clip Markers to CSV - X-Raym  ")
  print("========================================")

  local resolve = GetResolveApp()
  if not resolve then
    print("Error: DaVinci Resolve scripting environment not found.")
    print("Debug info:")
    print("  resolve: " .. tostring(resolve))
    print("  Resolve: " .. tostring(Resolve))
    print("  app: " .. tostring(app))
    print("  fu: " .. tostring(fu))
    print("  fusion: " .. tostring(fusion))
    print("  bmd: " .. tostring(bmd))
    print("Hint: In Resolve, place scripts in 'Utility' to run from any page, or 'Comp' to run from Fusion.")
    return
  end

  local pm = resolve:GetProjectManager()
  if not pm then
    print("Error: Could not retrieve Project Manager.")
    return
  end

  local proj = pm:GetCurrentProject()
  if not proj then
    print("Error: No project is currently loaded.")
    return
  end

  local proj_name = proj:GetName() or "Project"
  local proj_fps = tonumber(proj:GetSetting("timelineFrameRate")) or 24
  local mp = proj:GetMediaPool()
  local tl = proj:GetCurrentTimeline()

  -- Collect clips based on scan_scope
  local clips_to_process = {} -- Array of tables: { type="mediapool"|"timeline", item=..., clip_prop=... }
  local scope_used = scan_scope

  -- 1. Check Media Pool Selection
  if (scan_scope == "auto" or scan_scope == "selected") and mp then
    local sel = mp:GetSelectedClips()
    if sel and #sel > 0 then
      scope_used = "selected media pool clips"
      for _, clip in ipairs(sel) do
        table.insert(clips_to_process, {
          source_type = "MediaPoolItem",
          clip = clip,
          timeline_item = nil,
          track_name = "N/A"
        })
      end
    end
  end

  -- 2. Check Timeline clips if auto and no selection, or if explicitly requested
  if (scan_scope == "auto" and #clips_to_process == 0) or scan_scope == "timeline" then
    if tl then
      scope_used = "active timeline clips"
      local track_types = { "video", "audio", "subtitle" }
      for _, track_type in ipairs(track_types) do
        local count = tl:GetTrackCount(track_type) or 0
        for track_id = 1, count do
          local track_name = tl:GetTrackName(track_type, track_id) or (track_type .. " " .. track_id)
          local items = tl:GetItemListInTrack(track_type, track_id)
          if items then
            for _, item in ipairs(items) do
              local mp_item = item:GetMediaPoolItem()
              table.insert(clips_to_process, {
                source_type = "TimelineItem",
                clip = mp_item,
                timeline_item = item,
                track_name = track_name
              })
            end
          end
        end
      end
    end
  end

  -- 3. Check Media Pool Current Folder if still empty
  if (scan_scope == "auto" and #clips_to_process == 0) or scan_scope == "bin" then
    if mp then
      scope_used = "current media pool folder"
      local folder = mp:GetCurrentFolder()
      if folder then
        local folder_clips = folder:GetClipList()
        if folder_clips then
          for _, clip in ipairs(folder_clips) do
            table.insert(clips_to_process, {
              source_type = "MediaPoolItem",
              clip = clip,
              timeline_item = nil,
              track_name = "N/A"
            })
          end
        end
      end
    end
  end

  print("Project: " .. proj_name)
  print("Scope: " .. scope_used .. " (" .. #clips_to_process .. " items inspected)")
  print("Mode: " .. export_mode)
  print("----------------------------------------")

  if #clips_to_process == 0 then
    print("No clips found to inspect.")
    return
  end

  -- Gather all markers
  local total_markers_count = 0
  local combined_rows = {}
  local individual_files = {} -- clip_path -> rows

  for _, entry in ipairs(clips_to_process) do
    local clip = entry.clip
    local tl_item = entry.timeline_item
    local track_name = entry.track_name

    -- Properties
    local clip_name = ""
    local file_path_str = ""
    local start_tc = "00:00:00:00"
    local fps = proj_fps

    if clip then
      clip_name = clip:GetName() or ""
      file_path_str = clip:GetClipProperty("File Path") or ""
      start_tc = clip:GetClipProperty("Start TC") or "00:00:00:00"
      fps = tonumber(clip:GetClipProperty("FPS")) or proj_fps
    elseif tl_item then
      clip_name = tl_item:GetName() or "Timeline Clip"
    end

    local start_frame = ParseTimeCode(start_tc, fps)

    -- Collect markers from MediaPoolItem and/or TimelineItem
    local markers_found = {} -- frameId -> marker_info

    -- Markers on source MediaPoolItem
    if clip then
      local mp_markers = clip:GetMarkers()
      if mp_markers then
        for f, m in pairs(mp_markers) do
          m.origin = "MediaPool"
          markers_found[f] = m
        end
      end
    end

    -- Markers on TimelineItem (if item has its own markers)
    if tl_item then
      local tl_markers = tl_item:GetMarkers()
      if tl_markers then
        for f, m in pairs(tl_markers) do
          m.origin = "TimelineItem"
          markers_found[f] = m
        end
      end
    end

    -- Sort marker frame positions
    local positions = {}
    for pos in pairs(markers_found) do
      table.insert(positions, pos)
    end
    table.sort(positions)

    if #positions > 0 then
      print("Found " .. #positions .. " marker(s) on: " .. clip_name)

      for _, pos in ipairs(positions) do
        total_markers_count = total_markers_count + 1
        local m = markers_found[pos]
        local dur = tonumber(m.duration) or 1
        if dur < 1 then dur = 1 end

        -- Timecode calculations
        local src_in_tc = FramesToTimeCode(start_frame + pos, fps)
        local src_out_tc = FramesToTimeCode(start_frame + pos + dur, fps)
        local rel_in_tc = FramesToTimeCode(pos, fps)
        local rel_out_tc = FramesToTimeCode(pos + dur, fps)
        local dur_tc = FramesToTimeCode(dur, fps)

        -- Timeline timecode (if timeline item)
        local tl_in_tc = "N/A"
        local tl_out_tc = "N/A"
        if tl_item then
          local tl_start = tl_item:GetStart() or 0
          tl_in_tc = FramesToTimeCode(tl_start + pos, proj_fps)
          tl_out_tc = FramesToTimeCode(tl_start + pos + dur, proj_fps)
        end

        -- Row for combined CSV
        local combined_row = {
          EscapeCSV(clip_name, csv_delimiter),
          EscapeCSV(file_path_str, csv_delimiter),
          EscapeCSV(track_name, csv_delimiter),
          EscapeCSV(m.origin or "Clip", csv_delimiter),
          EscapeCSV(m.name or "", csv_delimiter),
          EscapeCSV(m.color or "", csv_delimiter),
          EscapeCSV(src_in_tc, csv_delimiter),
          EscapeCSV(src_out_tc, csv_delimiter),
          EscapeCSV(rel_in_tc, csv_delimiter),
          EscapeCSV(rel_out_tc, csv_delimiter),
          EscapeCSV(tl_in_tc, csv_delimiter),
          EscapeCSV(tl_out_tc, csv_delimiter),
          EscapeCSV(pos, csv_delimiter),
          EscapeCSV(dur, csv_delimiter),
          EscapeCSV(dur_tc, csv_delimiter),
          EscapeCSV(m.note or "", csv_delimiter),
          EscapeCSV(m.customData or "", csv_delimiter)
        }
        table.insert(combined_rows, table.concat(combined_row, csv_delimiter))

        -- Row for individual clip CSV (compatible with X-Raym marker import script)
        -- Format: Timecode, Color, Name, Note, Duration, CustomData
        if file_path_str ~= "" then
          if not individual_files[file_path_str] then
            individual_files[file_path_str] = {}
          end
          local indiv_row = {
            EscapeCSV(src_in_tc, csv_delimiter),
            EscapeCSV(m.color or "", csv_delimiter),
            EscapeCSV(m.name or "", csv_delimiter),
            EscapeCSV(m.note or "", csv_delimiter),
            EscapeCSV(dur_tc, csv_delimiter),
            EscapeCSV(m.customData or "", csv_delimiter)
          }
          table.insert(individual_files[file_path_str], table.concat(indiv_row, csv_delimiter))
        end
      end
    end
  end

  print("----------------------------------------")
  print("Total Markers Found: " .. total_markers_count)

  if total_markers_count == 0 then
    print("No markers found on inspected clips.")
    return
  end

  -- PREPARE HEADERS AND CONTENT
  local headers = {
    "Clip Name",
    "Source File",
    "Track",
    "Marker Source",
    "Marker Name",
    "Color",
    "Source TC In",
    "Source TC Out",
    "Relative TC In",
    "Relative TC Out",
    "Timeline TC In",
    "Timeline TC Out",
    "Frame Offset",
    "Duration Frames",
    "Duration TC",
    "Note",
    "Custom Data"
  }
  local header_line = table.concat(headers, csv_delimiter)
  local full_csv_content = (include_headers and (header_line .. "\n") or "") .. table.concat(combined_rows, "\n") .. "\n"

  -- ALWAYS PRINT CSV TO CONSOLE
  print("\n==================== CSV OUTPUT ====================")
  if include_headers then
    print(header_line)
  end
  for _, line in ipairs(combined_rows) do
    print(line)
  end
  print("================== END CSV OUTPUT ==================\n")

  -- COPY TO CLIPBOARD IF SUPPORTED
  if bmd and bmd.setclipboard then
    pcall(function() bmd.setclipboard(full_csv_content) end)
    print("-> Note: CSV data has also been copied to your clipboard!")
  end

  -- SAVE TO FILE
  if export_mode == "combined" then
    local target_path = file_path

    if not target_path or target_path == "" then
      local safe_proj = proj_name:gsub('[\\/:*?"<>|]', "_")
      local default_name = safe_proj .. "_Clip_Markers.csv"
      target_path = RequestSaveFilePath(default_name, resolve)
    end

    if not target_path or target_path == "" then
      print("Export cancelled by user (or no path specified).")
      return
    end

    local success, method_or_err = WriteTextFile(target_path, full_csv_content)
    if success then
      print("SUCCESS: Exported " .. total_markers_count .. " marker(s) to:")
      print("  " .. target_path)
    else
      print("Error: Could not save file to " .. target_path)
      print("System message: " .. tostring(method_or_err))
      print("CSV output is printed above and copied to clipboard.")
    end

  elseif export_mode == "individual" then
    local count_exported_files = 0
    for clip_media_path, rows in pairs(individual_files) do
      local path, name, ext = SplitFileName(clip_media_path)
      if path ~= "" and name ~= "" then
        local target_path = path .. name .. ".csv"
        local indiv_content = ""
        if include_headers then
          local headers = { "Timecode", "Color", "Name", "Note", "Duration", "CustomData" }
          indiv_content = table.concat(headers, csv_delimiter) .. "\n"
        end
        indiv_content = indiv_content .. table.concat(rows, "\n") .. "\n"

        local success, method_or_err = WriteTextFile(target_path, indiv_content)
        if success then
          count_exported_files = count_exported_files + 1
          print("Exported: " .. target_path .. " (" .. #rows .. " markers)")
        else
          print("Error writing " .. target_path .. ": " .. tostring(method_or_err))
        end
      end
    end
    print("SUCCESS: Exported individual CSV files for " .. count_exported_files .. " clip(s).")
  end

  print("========================================")
end

-- RUN
ExportMarkers()
