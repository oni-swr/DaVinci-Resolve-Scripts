--[[
 * Resolve Script Name: Export markers as reaper CSV
 * About: Use with X-Raym REAPER import markers script from CSV
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
 * v1.0 (2021-01-06)
  + Initial Release
--]]


-- USER CONFIG AREA ---------------------------------------
time_offset = 0 -- 0, 3600 if timeline starts at 01:00:00
----------------------------------- END OF USER CONFIG AREA


function OutputToConsoleAndFile(output, file)
    -- Print to the console
    print(output)

    -- Write to the file
    file:write(output .. "\n")
end

function GetSecondsFromFrame( pos, fps )
    local seconds = pos/fps
    return seconds
end

-- Open the file for writing
-- Change the path to your desired location (Also at the end of the script)
local file = io.open("/Your/Path/reaper_markers.csv", "w")

-- Check if the file opened successfully
if not file then
    print("Error: Could not open the file for writing.")
    return
end

print("-------------------------")
file:write("-------------------------\n")

resolve = Resolve()
pm = resolve:GetProjectManager()
proj = pm:GetCurrentProject()
tl = proj:GetCurrentTimeline()
markers = tl:GetMarkers()

positions = {}
for k, marker in pairs( markers ) do
    table.insert(positions, k)
end

table.sort( positions )

fps = proj:GetSetting("timelineFrameRate")

local header = "Type\tName\tPos_Start\tPos_End"
OutputToConsoleAndFile(header, file)

for i, pos in ipairs(positions) do
    local marker = markers[pos]
    local position = GetSecondsFromFrame( pos, fps ) + time_offset
    local t = {
        "M" .. i,
        marker.name,
        position,
        position
    }
    
    local output = table.concat( t, "\t")
    OutputToConsoleAndFile(output, file)
end

-- Close the file
file:close()

print("Output written to /Your/Path/reaper_markers.csv")