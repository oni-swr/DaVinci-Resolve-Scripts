--[[
 * Resolve Script Name: Export markers as reaper CSV
 * About: Use with X-Raym REAPER import markers script from CSV
 * Author: X-Raym
 * Author URI: https://www.extremraym.com
 * Repository: GitHub > X-Raym > DaVinci-Resolve-Scripts
 * Repository URI: https://github.com/X-Raym/DaVinci-Resolve-Scripts
 * Licence: GPL v3
 * REAPER: 5.0
 * Version: 1.0.1
--]]

--[[
 * Changelog:
 * v1.0.1 (2025-10-13)
  * Export to file
 * v1.0 (2021-01-06)
  + Initial Release
--]]


-- USER CONFIG AREA ---------------------------------------
time_offset = 0 -- 0, 3600 if timeline starts at 01:00:00

file_path = "" -- absolute file path for export
----------------------------------- END OF USER CONFIG AREA

function GetSecondsFromFrame( pos, fps )
    return pos/fps
end

function Export( str )
  print( str )
  if file then
    file:write( str .. "\n" )
  end
end

-- INIT
resolve = Resolve()
pm = resolve:GetProjectManager()
proj = pm:GetCurrentProject()
tl = proj:GetCurrentTimeline()
fps = proj:GetSetting("timelineFrameRate")
markers = tl:GetMarkers()

positions = {}
for k, marker in pairs( markers ) do
    table.insert(positions, k)
end

table.sort( positions )

-- Start export
file = io.open( file_path, "w")

Export( "Type\tName\tPos_Start\tPos_End" ) -- header
Export( "-------------------------" )

-- body
for i, pos in ipairs(positions) do
    local marker = markers[pos]
    local position = GetSecondsFromFrame( pos, fps ) + time_offset
    local t = {
        "M" .. i,
        marker.name,
        position,
        position
    }

    Export( table.concat( t, "\t") ) -- line
end

file:close()

Export( (file and "\nExported File:\n"  .. path) or "No file exported.\n:Edit file paht in the script header if needed." )
