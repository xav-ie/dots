#!/usr/bin/osascript

tell application "System Events"
	tell process "ControlCenter"
		click menu bar item 4 of menu bar 1

		-- Poll for window with minimal delay (up to 1 second)
		set foundIt to false
		repeat 100 times
			delay 0.01
			if exists window 1 then
				tell window 1
					tell group 1
						set childGroups to groups
						if (count of childGroups) > 0 then
							-- Search through child groups
							repeat with grp in childGroups
								try
									-- Quick check: does this group have any sliders?
									set groupSliders to sliders of grp
									if (count of groupSliders) > 0 then
										-- Check if any slider is the volume slider
										repeat with sld in groupSliders
											if description of sld is "sound volume" then
												-- Found it, wait a moment for UI to settle, then click
                        -- This delay is magic. Not sure why higher or lower does not work.
												delay 0.05
												click grp
												set foundIt to true
												exit repeat
											end if
										end repeat
									end if
									if foundIt then exit repeat
								end try
							end repeat
							if foundIt then return
						end if
					end tell
				end tell
				-- Groups not ready yet, continue polling
			end if
		end repeat
	end tell
end tell
