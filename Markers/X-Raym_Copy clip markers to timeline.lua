--[[
 * Resolve Script Name: Copy clip markers to timeline
 * About: Copy markers from timeline clips (or their source media pool clips) onto the timeline ruler.
 * Author: X-Raym
 * Author URI: https://www.extremraym.com
 * Repository: GitHub > X-Raym > DaVinci-Resolve-Scripts
 * Repository URI: https://github.com/X-Raym/DaVinci-Resolve-Scripts
 * Licence: GPL v3
 * REAPER: 5.0
 * Version: 1.0
--]]

--[[
 * Changelog:
 * v1.0 (2026-09-18)
  + Initial Release
--]]

-- USER CONFIG AREA ---------------------------------------
-- Tracks to scan: { "video", "audio" }
track_types = { "video", "audio" }

-- Overwrite existing markers on timeline if color/pos match
overwrite_existing = true

-- Include markers from source Media Pool item (accounting for clip in/out cuts on timeline)
include_media_pool_markers = true

-- Include markers placed directly on Timeline clips
include_timeline_clip_markers = true
----------------------------------- END OF USER CONFIG AREA

function CopyClipMarkersToTimeline()
  print("========================================")
  print("  Copy Clip Markers to Timeline - X-Raym")
  print("========================================")

  local resolve = Resolve and Resolve()
  if not resolve then
    print("Error: DaVinci Resolve scripting environment not found.")
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

  local tl = proj:GetCurrentTimeline()
  if not tl then
    print("Error: No active timeline found.")
    return
  end

  local copied_count = 0
  local timeline_markers = tl:GetMarkers() or {}

  for _, track_type in ipairs(track_types) do
    local track_count = tl:GetTrackCount(track_type) or 0
    for track_id = 1, track_count do
      local track_name = tl:GetTrackName(track_type, track_id) or (track_type .. " " .. track_id)
      local items = tl:GetItemListInTrack(track_type, track_id)
      if items then
        for _, item in ipairs(items) do
          local item_start = item:GetStart() or 0
          local item_duration = item:GetDuration() or 0
          local left_offset = item:GetLeftOffset() or 0

          -- 1. Markers placed directly on the timeline item
          if include_timeline_clip_markers then
            local tl_item_markers = item:GetMarkers()
            if tl_item_markers then
              for pos, marker in pairs(tl_item_markers) do
                local tl_pos = math.floor(item_start + pos)
                local dur = tonumber(marker.duration) or 1
                local success = tl:AddMarker(tl_pos, marker.color, marker.name or "", marker.note or "", dur, marker.customData or "")
                if success then
                  copied_count = copied_count + 1
                  print("Copied timeline clip marker '" .. tostring(marker.name) .. "' to timeline frame " .. tl_pos)
                end
              end
            end
          end

          -- 2. Markers from the underlying MediaPoolItem
          if include_media_pool_markers then
            local mp_item = item:GetMediaPoolItem()
            if mp_item then
              local mp_markers = mp_item:GetMarkers()
              if mp_markers then
                for pos, marker in pairs(mp_markers) do
                  -- Check if source marker falls within the visible trimmed portion of the clip on timeline
                  if pos >= left_offset and pos < (left_offset + item_duration) then
                    local offset_in_item = pos - left_offset
                    local tl_pos = math.floor(item_start + offset_in_item)
                    local dur = tonumber(marker.duration) or 1
                    local success = tl:AddMarker(tl_pos, marker.color, marker.name or "", marker.note or "", dur, marker.customData or "")
                    if success then
                      copied_count = copied_count + 1
                      print("Copied media pool marker '" .. tostring(marker.name) .. "' to timeline frame " .. tl_pos)
                    end
                  end
                end
              end
            end
          end

        end
      end
    end
  end

  print("----------------------------------------")
  print("Copied " .. copied_count .. " marker(s) to timeline ruler.")
  print("========================================")
end

CopyClipMarkersToTimeline()
