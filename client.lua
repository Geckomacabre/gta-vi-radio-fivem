--[[
    VI Radio - client
    FiveM port of the singleplayer "VI Radio" mod by sej0bec.

    The original is a ScriptHookVDotNet plugin that drew its HUD with native
    textures. FiveM cannot load SHVDN assemblies, so the HUD is rebuilt as NUI
    and the game side (stations, slow motion, timecycle, mute) lives here.
]]

local RES = GetCurrentResourceName()

-- state ----------------------------------------------------------------------
local stations      = {}     -- ordered list of { name, label, logo, genre }
local index         = 1      -- currently highlighted entry in `stations`
local wheelOpen     = false
local keyHeld       = false
local muted         = false
local mutedVehicle  = 0      -- vehicle the mute was applied to
local nowPlaying    = { title = nil, artist = nil }
local timeScaleNow  = 1.0
local navHeldSince  = 0
local navLastStep   = 0
local navDir        = 0
local stickLatched  = false  -- right stick must recentre between station changes
local openedByControl = false -- opened by the raw radio-wheel control (pad), not our keybind

-- helpers --------------------------------------------------------------------

local function currentVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 0 end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return 0 end
    if Config.DriverOnly and GetPedInVehicleSeat(veh, -1, false) ~= ped then return 0 end
    return veh
end

local function canUseRadio()
    if currentVehicle() ~= 0 then return true end
    return Config.AllowOnFoot and IsMobilePhoneRadioActive()
end

local function stationInfo(name)
    local cfg = Config.Stations[name]
    if cfg then
        return {
            name  = name,
            label = cfg.label,
            logo  = cfg.logo and ('logos/' .. cfg.logo) or nil,
            genre = cfg.genre,
        }
    end
    -- Unknown / add-on station: fall back to a readable version of the raw name.
    local pretty = name:gsub('^RADIO_%d+_', ''):gsub('^DLC_', ''):gsub('_', ' ')
    return { name = name, label = pretty, logo = nil, genre = nil }
end

local function buildStations()
    local list = {}
    local seenOff = false
    for i = 0, GetNumUnlockedRadioStations() - 1 do
        local name = GetRadioStationName(i)
        if name and name ~= '' then
            if name == 'OFF' then
                seenOff = true
            elseif not name:find('^HIDDEN_') then
                local cfg = Config.Stations[name]
                if not (cfg and cfg.hidden) then
                    list[#list + 1] = stationInfo(name)
                end
            end
        end
    end
    if Config.IncludeOff or seenOff then
        list[#list + 1] = { name = 'OFF', label = Config.OffLabel, logo = nil, genre = nil }
    end
    stations = list

    -- keep the highlight on whatever is actually playing
    local playing = GetPlayerRadioStationName() or 'OFF'
    for i, s in ipairs(stations) do
        if s.name == playing then index = i break end
    end
    if index > #stations then index = 1 end
end

local function applyStation(entry)
    local veh = currentVehicle()
    if veh ~= 0 then
        SetVehRadioStation(veh, entry.name)
    end
    SetRadioToStationName(entry.name)
end

local function applyMute()
    local veh = currentVehicle()
    if veh ~= 0 then
        SetVehicleRadioEnabled(veh, not muted)
        mutedVehicle = muted and veh or 0
    end
    SetMobileRadioEnabledDuringGameplay(not muted)
end

-- NUI ------------------------------------------------------------------------

local function nuiPayload()
    local items = {}
    for i, s in ipairs(stations) do
        items[i] = { label = s.label, logo = s.logo, genre = s.genre, off = s.name == 'OFF' }
    end
    return items
end

local function pushState(withList)
    if not Config.Hud.enabled then return end
    SendNUIMessage({
        action  = 'state',
        open    = wheelOpen,
        hud     = withList and Config.Hud or nil,
        list    = withList and nuiPayload() or nil,
        index   = index - 1,
        muted   = muted,
        title   = nowPlaying.title,
        artist  = nowPlaying.artist,
    })
end

local function playSound(file)
    if not Config.RadioSounds or not file then return end
    SendNUIMessage({ action = 'sound', file = file, volume = Config.SoundVolume / 100 })
end

-- wheel ----------------------------------------------------------------------

local function step(dir)
    if #stations == 0 then return end
    index = index + dir
    if index < 1 then index = #stations elseif index > #stations then index = 1 end
    applyStation(stations[index])
    if muted then
        muted = false
        applyMute()
    end
    pushState(false)
end

local function openWheel()
    if wheelOpen or not canUseRadio() then return end
    buildStations()
    wheelOpen = true
    navDir, navHeldSince, navLastStep = 0, 0, 0
    playSound(Config.OpenSound)
    pushState(true)
end

local function closeWheel()
    if not wheelOpen then return end
    wheelOpen = false
    stickLatched = false
    openedByControl = false
    playSound(Config.CloseSound)
    pushState(false)

    if Config.Timecycle ~= '' then ClearTimecycleModifier() end
    if Config.HideRadar then DisplayRadar(true) end
end

local function toggleMute()
    if not canUseRadio() then return end
    muted = not muted
    applyMute()
    pushState(false)
    if not wheelOpen and Config.Hud.enabled then
        -- brief HUD flash so the player sees the mute state change
        SendNUIMessage({ action = 'flash', muted = muted })
    end
end

-- keybinds -------------------------------------------------------------------

RegisterCommand('+vi_radio', function() keyHeld = true end, false)
RegisterCommand('-vi_radio', function() keyHeld = false end, false)
RegisterKeyMapping('+vi_radio', 'VI Radio: hold to open the radio wheel', 'keyboard', Config.OpenKey)

RegisterCommand('vi_radio_mute', function() toggleMute() end, false)
RegisterKeyMapping('vi_radio_mute', 'VI Radio: mute / unmute the radio', 'keyboard', Config.MuteKey)

-- main loop ------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = 200

        -- Controllers do not go through RegisterKeyMapping. A pad binding there
        -- is only a *default*, so it never reaches anyone whose client already
        -- stored a binding for this command. Reading the game's own radio-wheel
        -- control instead always works, needs no binding, and follows whatever
        -- the player has that control set to (D-pad Left by default).
        local ctrlHeld = Config.Controller.enabled and IsDisabledControlPressed(0, 85)
        local wantOpen = keyHeld or ctrlHeld

        if wantOpen and not wheelOpen then
            -- keyHeld means our keyboard bind fired, so arrow keys are safe.
            openedByControl = not keyHeld
            openWheel()
        elseif wheelOpen and (not wantOpen or not canUseRadio()) then
            closeWheel()
        end

        if not wheelOpen and IsPedInAnyVehicle(PlayerPedId(), false) then
            wait = 0  -- poll every frame so the pad opens without lag
        end

        if wheelOpen then
            wait = 0

            -- effects
            if Config.Timecycle ~= '' then
                SetTimecycleModifier(Config.Timecycle)
                SetTimecycleModifierStrength(Config.TimecycleStrength + 0.0)
            end
            if Config.HiDof then SetUseHiDof() end
            if Config.HideRadar then DisplayRadar(false) end

            -- swallow the inputs we are replacing
            DisableControlAction(0, 85, true)   -- VEH_RADIO_WHEEL
            DisableControlAction(0, 81, true)   -- VEH_NEXT_RADIO
            DisableControlAction(0, 82, true)   -- VEH_PREV_RADIO
            DisableControlAction(0, 83, true)   -- VEH_NEXT_RADIO_TRACK
            DisableControlAction(0, 84, true)   -- VEH_PREV_RADIO_TRACK
            DisableControlAction(0, 27, true)   -- PHONE
            DisableControlAction(0, 172, true)  -- CELLPHONE_UP
            DisableControlAction(0, 173, true)  -- CELLPHONE_DOWN
            DisableControlAction(0, 174, true)  -- CELLPHONE_LEFT  (arrow left)
            DisableControlAction(0, 175, true)  -- CELLPHONE_RIGHT (arrow right)
            if Config.ScrollRadio then
                DisableControlAction(0, 14, true)  -- WEAPON_WHEEL_NEXT
                DisableControlAction(0, 15, true)  -- WEAPON_WHEEL_PREV
            end

            local pad = openedByControl
            local now = GetGameTimer()

            if pad and Config.Controller.lockCamera then
                DisableControlAction(0, 1, true)    -- LOOK_LR
                DisableControlAction(0, 2, true)    -- LOOK_UD
                DisableControlAction(0, 220, true)  -- SCRIPT_RIGHT_AXIS_X
                DisableControlAction(0, 221, true)  -- SCRIPT_RIGHT_AXIS_Y
            end

            if Config.MuteOnDownWhileOpen and IsDisabledControlJustPressed(0, 173) then
                toggleMute()
            end

            -- navigation
            local dir, held = 0, 0

            if pad then
                -- D-pad Left is the button holding the wheel open, so it cannot
                -- double as "previous": right stick, D-pad Right, D-pad Up.
                local axis = GetDisabledControlNormal(0, 220)
                if math.abs(axis) >= Config.Controller.deadzone then
                    held = axis > 0 and 1 or -1
                    if not stickLatched then
                        dir = held
                        stickLatched = true
                    end
                else
                    stickLatched = false
                    if IsDisabledControlJustPressed(0, 175) then dir = 1
                    elseif IsDisabledControlJustPressed(0, 172) then dir = -1 end
                    if IsDisabledControlPressed(0, 175) then held = 1
                    elseif IsDisabledControlPressed(0, 172) then held = -1 end
                end
            else
                stickLatched = false
                if IsDisabledControlJustPressed(0, 175) then dir = 1
                elseif IsDisabledControlJustPressed(0, 174) then dir = -1
                elseif Config.ScrollRadio and IsDisabledControlJustPressed(0, 14) then dir = 1
                elseif Config.ScrollRadio and IsDisabledControlJustPressed(0, 15) then dir = -1 end

                if IsDisabledControlPressed(0, 175) then held = 1
                elseif IsDisabledControlPressed(0, 174) then held = -1 end
            end

            if dir ~= 0 then
                step(dir)
                navDir, navHeldSince, navLastStep = dir, now, now
            elseif Config.ArrowAutoRepeat and held ~= 0 and held == navDir then
                if now - navHeldSince > Config.AutoRepeatDelay
                   and now - navLastStep > Config.AutoRepeatRate then
                    step(held)
                    navLastStep = now
                end
            elseif held == 0 then
                navDir = 0
            end
        end

        Wait(wait)
    end
end)

-- slow motion ----------------------------------------------------------------
-- Kept in its own thread so the easing is smooth and so it can be switched off
-- entirely (Config.TimeScale = 1.0) without touching the rest of the script.

CreateThread(function()
    if Config.TimeScale >= 1.0 then return end
    while true do
        local target = wheelOpen and Config.TimeScale or 1.0
        if math.abs(timeScaleNow - target) > 0.001 then
            local stepSize = (16 / math.max(Config.TimeScaleFade, 1))
            if timeScaleNow < target then
                timeScaleNow = math.min(target, timeScaleNow + stepSize)
            else
                timeScaleNow = math.max(target, timeScaleNow - stepSize)
            end
            SetTimeScale(timeScaleNow + 0.0)
            Wait(0)
        else
            if timeScaleNow ~= 1.0 and target == 1.0 then
                timeScaleNow = 1.0
                SetTimeScale(1.0)
            end
            Wait(wheelOpen and 0 or 200)
        end
    end
end)

-- vanilla radio HUD and controls ---------------------------------------------
-- The stock wheel shares its button with ours on both keyboard (Q) and pad
-- (D-pad Left), so it has to be suppressed every frame, not only while open.

CreateThread(function()
    if not Config.DisableRadioHUD and not Config.DisableVanillaRadioControls then return end
    while true do
        if Config.DisableRadioHUD then
            HideHudComponentThisFrame(20)  -- HUD_RADIO_STATIONS
        end
        if Config.DisableVanillaRadioControls then
            DisableControlAction(0, 85, true)  -- VEH_RADIO_WHEEL
            DisableControlAction(0, 81, true)  -- VEH_NEXT_RADIO
            DisableControlAction(0, 82, true)  -- VEH_PREV_RADIO
        end
        Wait(0)
    end
end)

-- housekeeping ---------------------------------------------------------------
-- Re-apply mute when the player changes vehicle, and keep the idle HUD in sync
-- with whatever else on the server might have changed the station.

CreateThread(function()
    local lastStation = nil
    while true do
        if muted then
            local veh = currentVehicle()
            if veh ~= mutedVehicle then applyMute() end
        end

        local playing = GetPlayerRadioStationName()
        if playing ~= lastStation then
            lastStation = playing
            if not wheelOpen and #stations > 0 then
                for i, s in ipairs(stations) do
                    if s.name == playing then index = i break end
                end
                pushState(false)
            end
        end

        Wait(500)
    end
end)

-- debug ----------------------------------------------------------------------
-- /viradio_debug prints why the wheel is or is not responding.

RegisterCommand('viradio_debug', function()
    local ok, kbm = pcall(function() return IsUsingKeyboardAndMouse(2) end)
    print(('[vi_radio] inVehicle=%s seatAllowed=%s stations=%d open=%s viaControl=%s keyHeld=%s ctrl85=%s keyboardAndMouse=%s muted=%s'):format(
        tostring(IsPedInAnyVehicle(PlayerPedId(), false)),
        tostring(currentVehicle() ~= 0),
        #stations,
        tostring(wheelOpen),
        tostring(openedByControl),
        tostring(keyHeld),
        tostring(IsDisabledControlPressed(0, 85)),
        ok and tostring(kbm) or 'n/a',
        tostring(muted)))
end, false)

-- exports --------------------------------------------------------------------
-- FiveM has no native that resolves the current track title, so the title and
-- artist lines are driven from outside. Any resource that knows what is playing
-- (custom streamed stations, xsound, a metadata feed) can push it in here.

local function setNowPlaying(title, artist)
    nowPlaying.title  = title
    nowPlaying.artist = artist
    pushState(false)
end

exports('SetNowPlaying', setNowPlaying)
RegisterNetEvent('vi_radio:setNowPlaying', setNowPlaying)

exports('IsOpen', function() return wheelOpen end)
exports('IsMuted', function() return muted end)
exports('SetMuted', function(state)
    if state == muted then return end
    muted = state and true or false
    applyMute()
    pushState(false)
end)
exports('GetStation', function() return GetPlayerRadioStationName() end)

-- cleanup --------------------------------------------------------------------

AddEventHandler('onResourceStop', function(name)
    if name ~= RES then return end
    SetTimeScale(1.0)
    ClearTimecycleModifier()
    DisplayRadar(true)
    if muted then
        muted = false
        applyMute()
    end
end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end
    buildStations()
    pushState(true)
end)
