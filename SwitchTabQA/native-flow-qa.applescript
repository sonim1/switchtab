on releaseModifiers()
    tell application "System Events"
        key up command
        key up shift
        key up control
        key up option
    end tell
end releaseModifiers

on overlaySnapshot()
    set resultText to ""
    tell application "System Events" to tell application process "SwitchTab"
        set resultText to "overlay-windows=" & (count windows) & linefeed
        if (count windows) is 0 then return resultText
        set nodes to entire contents of window 1
        repeat with node in nodes
            if role of node is "AXButton" then
                set nodeValue to ""
                set nodeLabel to ""
                set nodeHelp to ""
                try
                    set nodeValue to (value of attribute "AXValue" of node) as text
                end try
                try
                    set nodeLabel to (value of attribute "AXIdentifier" of node) as text
                end try
                try
                    set nodeHelp to (value of attribute "AXHelp" of node) as text
                end try
                if nodeValue is "Selected" or nodeValue is "Not selected" then
                    set resultText to resultText & "tile=" & nodeLabel & " value=" & nodeValue & " help=" & nodeHelp & linefeed
                end if
            end if
        end repeat
    end tell
    return resultText
end overlaySnapshot

on selectedTile()
    tell application "System Events" to tell application process "SwitchTab"
        set nodes to entire contents of window 1
        repeat with node in nodes
            try
                if role of node is "AXButton" and (value of attribute "AXValue" of node) as text is "Selected" then
                    return (value of attribute "AXIdentifier" of node) as text
                end if
            end try
        end repeat
    end tell
    error "Selected tile label missing"
end selectedTile

on mainOwnedTitle(targetPID)
    tell application "System Events" to tell (first application process whose unix id is targetPID)
        repeat with candidate in windows
            set candidateTitle to (get name of candidate) as text
            if candidateTitle starts with "SwitchTab Security QA " and (get value of attribute "AXMain" of candidate) is true then return candidateTitle
        end repeat
    end tell
    error "Owned main window missing"
end mainOwnedTitle

on run argv
    if (count argv) is not 2 then error "Expected owned fixture PID and scenario"
    set targetPID to (item 1 of argv) as integer
    set scenario to item 2 of argv
    if scenario is not in {"window-nav-cancel", "window-return", "app-nav-cancel", "mode-handoff", "minimized-return", "close-owned-window", "quit-owned-app", "app-click-owned-view"} then error "Unknown scenario"
    tell application "System Events"
        set targetProcess to first application process whose unix id is targetPID
        if name of targetProcess is not "SwitchTabSecurityQA" then error "Target is not the owned disposable fixture"
        set targetAppIdentifier to bundle identifier of targetProcess
        if targetAppIdentifier is not "com.royjen.switchtab.security-qa-fixture" then error "Target bundle is not the owned disposable fixture"
    end tell
    my releaseModifiers()
    tell application "System Events"
        set frontmost of targetProcess to true
        delay 0.2
    end tell
    set beforeTitle to my mainOwnedTitle(targetPID)
    set resultText to "scenario=" & scenario & " before=" & beforeTitle & linefeed
    try
        tell application "System Events" to key down command
        if scenario is in {"app-nav-cancel", "mode-handoff", "quit-owned-app", "app-click-owned-view"} then
            tell application "System Events" to key code 48
        else
            tell application "System Events" to key code 50
        end if
        delay 0.4
        set resultText to resultText & "INITIAL" & linefeed & my overlaySnapshot()
        set initialSelection to my selectedTile()

        if scenario is "window-nav-cancel" or scenario is "app-nav-cancel" then
            tell application "System Events" to key code 124
            delay 0.2
            set resultText to resultText & "ADVANCED" & linefeed & my overlaySnapshot()
            tell application "System Events" to key code 53
            my releaseModifiers()
            delay 0.2
            tell application "System Events" to key down command
            if scenario is "window-nav-cancel" then
                tell application "System Events" to key code 50
            else
                tell application "System Events" to key code 48
            end if
            delay 0.3
            set resultText to resultText & "REOPENED" & linefeed & my overlaySnapshot()
            if my selectedTile() is not initialSelection then error "Cancellation changed the next MRU target"
            tell application "System Events" to key code 53
        else if scenario is "window-return" then
            tell application "System Events" to key code 124
            delay 0.2
            set resultText to resultText & "CONFIRM_TARGET=" & my selectedTile() & linefeed & my overlaySnapshot()
            tell application "System Events" to key code 36
        else if scenario is "mode-handoff" or scenario is "quit-owned-app" then
            tell application "System Events"
                key down shift
                key code 48
                key up shift
            end tell
            delay 0.2
            set targetLabel to my selectedTile()
            if targetLabel is not targetAppIdentifier and targetLabel is not "pid:" & targetPID then error "Selected app is not the owned fixture"
            set resultText to resultText & "OWNED_APP" & linefeed & my overlaySnapshot()
            if scenario is "mode-handoff" then
                tell application "System Events" to key code 50
                delay 0.3
                set resultText to resultText & "APP_TO_WINDOWS" & linefeed & my overlaySnapshot()
                tell application "System Events" to key code 48
                delay 0.3
                set resultText to resultText & "WINDOWS_TO_APP" & linefeed & my overlaySnapshot()
                tell application "System Events" to key code 53
            else
                tell application "System Events" to key code 12
                delay 0.7
                set resultText to resultText & "AFTER_QUIT" & linefeed & my overlaySnapshot()
                tell application "System Events" to key code 53
            end if
        else if scenario is "minimized-return" then
            set foundMinimized to false
            repeat 4 times
                tell application "System Events" to tell application process "SwitchTab"
                    set nodes to entire contents of window 1
                    repeat with node in nodes
                        try
                            if role of node is "AXButton" and (value of attribute "AXValue" of node) as text is "Selected" and (value of attribute "AXHelp" of node) as text contains "minimized window" then set foundMinimized to true
                        end try
                    end repeat
                end tell
                if foundMinimized then exit repeat
                tell application "System Events" to key code 124
                delay 0.2
            end repeat
            if not foundMinimized then error "No selected minimized owned window"
            set resultText to resultText & "MINIMIZED_TARGET=" & my selectedTile() & linefeed & my overlaySnapshot()
            tell application "System Events" to key code 36
        else if scenario is "app-click-owned-view" then
            tell application "System Events" to tell application process "SwitchTab"
                set nodes to entire contents of window 1
                set didConfirm to false
                repeat with node in nodes
                    try
                        if role of node is "AXButton" and (value of attribute "AXIdentifier" of node) as text is "com.royjen.switchtab.view-audit" then
                            perform action "AXPress" of node
                            set didConfirm to true
                            exit repeat
                        end if
                    end try
                end repeat
            end tell
            if not didConfirm then error "Owned view fixture app tile missing"
            delay 0.4
            tell application "System Events"
                set activeIdentifier to bundle identifier of (first application process whose frontmost is true)
            end tell
            set resultText to resultText & "active-app=" & activeIdentifier & linefeed
            if activeIdentifier is not "com.royjen.switchtab.view-audit" then error "App click did not activate its exact target"
        else if scenario is "close-owned-window" then
            set closeTarget to my selectedTile()
            if closeTarget does not start with (targetPID as text) & "-" then error "Close target is not an owned fixture window"
            set resultText to resultText & "CLOSE_TARGET=" & closeTarget & linefeed
            tell application "System Events" to key code 13
            delay 0.7
            set resultText to resultText & "AFTER_CLOSE" & linefeed & my overlaySnapshot()
            tell application "System Events" to key code 53
        end if
        my releaseModifiers()
        delay 0.3
        tell application "System Events"
            if scenario is "quit-owned-app" then
                set resultText to resultText & "fixture-running=" & (exists (first application process whose unix id is targetPID)) & linefeed
            else
                set afterTitle to my mainOwnedTitle(targetPID)
                set resultText to resultText & "after=" & afterTitle & " frontmost=" & frontmost of targetProcess & linefeed
                if scenario is in {"window-nav-cancel", "app-nav-cancel", "mode-handoff"} and afterTitle is not beforeTitle then error "Cancelled selection changed fixture focus"
            end if
        end tell
        set resultText to resultText & "DISMISSED" & linefeed & my overlaySnapshot()
        return resultText
    on error errorText number errorNumber
        tell application "System Events" to key code 53
        my releaseModifiers()
        error resultText & linefeed & errorText number errorNumber
    end try
end run
