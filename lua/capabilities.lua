---@diagnostic disable: lowercase-global

dofile(project_root .. "/enums.lua")
dofile(project_root .. "/trackmeta.lua")
dofile(project_root .. "/vehicle_classifier.lua")
dofile(project_root .. "/par_classifier.lua")


--- @param track Track
function getTrackDisplayClass(track)
    if IsTrackPerson(track) then

        if ParClassifier.KnowIfIsCarryingGun(track) then
            if ParClassifier.IsCarryingGun(track) then
                return "Armed Person"
            end
        end

        return "Person"
    elseif IsTrackVehicle(track)  then

        if VehicleClassifier.HasVehicleClass(track) then
            return firstToUpper(VehicleClassifier.GetVehicleClass(track))
        end

        return "Vehicle"
    elseif IsTrackAnimal(track)  then
        return "Animal"
    elseif IsTrackUnknown(track)  then
        return "Unknown"
    end
    return "Undefined"
end

--- @param track Track
function getTrackClass(track)
    if IsTrackPerson(track) then
        return "Person"
    elseif IsTrackVehicle(track)  then
        return "Vehicle"
    elseif IsTrackAnimal(track)  then
        return "Animal"
    elseif IsTrackUnknown(track)  then
        return "Unknown"
    end
    return "Undefined"
end


---Checks zones
---@param tracks Track
---@param zoneInst zonemanaged
---@return table
function checkZones(tracks, zoneInst)

    local tracksTargetInfo = {}

    for _, track in pairs(tracks) do

        local trackId = track.id

        local trackTargetInfo = {
            track = track,
            id = trackId,
            trackid=trackId,
            bbox = track.bbox,
            bbox3d = TrackMeta.getValue(trackId,TrackMetaKeys.BBox3d),
            prev_bbox = TrackMeta.getValue(trackId,TrackMetaKeys.ZonePreviousBBox),
            custom = {
                is_people = TrackMeta.getValue(trackId,TrackMetaKeys.IsPerson),
                is_vehicle = TrackMeta.getValue(trackId,TrackMetaKeys.IsVehicle),
                is_animal = TrackMeta.getValue(trackId,TrackMetaKeys.IsAnimal),
                is_unknown = TrackMeta.getValue(trackId,TrackMetaKeys.IsUnknown),
                moving =IsTrackMoving(track)
            },
            last_seen = track.last_seen,
        }
        -- getTrackValue returns {} if field is not found. We want it to be null
        -- if next(trackTargetInfo.prev_bbox) == nil then trackTargetInfo.prev_bbox = nil end

        table.insert(tracksTargetInfo,trackTargetInfo)
    end

    -- Check if any zones triggered and update current_hits internally
    -- Iterate over all zones, and check only the tracks relevant to each zone
    local zoneIds = zoneInst:getZoneIds()
    local zonesEvents = {}
    for _, zoneId in pairs(zoneIds) do

        local zoneTargets = table.filter(tracksTargetInfo,function (zoneTarget)
            return IsTrackRelevantForZone(zoneTarget.track,zoneInst,zoneId)
        end)

        local checkAnchorPoint = zoneInst:getZoneValue(zoneId,"check_anchor_point",ZoneDictType.Config)

        zoneTargets = table.remap(zoneTargets, function (trackTargetInfo)
            
            local bbox_point = GetAnchorPointFromObject(trackTargetInfo.bbox,trackTargetInfo.bbox3d, checkAnchorPoint)
            -- Ensure point is inside the frame
            bbox_point.x = math.max(0,math.min(bbox_point.x,0.99))
            bbox_point.y = math.max(0,math.min(bbox_point.y,0.99))

            return {id=trackTargetInfo.id,points={{bbox_point.x,bbox_point.y}}}
        end)

        zoneInst:processZones(zoneTargets, {zoneId})

        table.extend(zonesEvents,zoneInst:getZoneEvents())
    end

    --Update zone_prev_bbox
    for _, trackTargetInfo in pairs(tracksTargetInfo) do
        TrackMeta.setValue(trackTargetInfo.id,TrackMetaKeys.ZonePreviousBBox,CopyRect(trackTargetInfo.bbox))
    end

    return zonesEvents
end

---Checks tripwires. To avoid multiple crossings and other issues, we run this at a fixed (slower) rate than zones
---@param tracks Track[]
---@param tripwireInst tripwiremanaged
---@param currentTimeSec number
---@return table
function checkTripwires(tracks, tripwireInst, currentTimeSec)

    local pointsChecked = {}
    local tracksTargetInfo = {}

    for _, track in pairs(tracks) do

        local trackId = track.id

        local trackTargetInfo = {
            track = track,
            id = trackId,
            trackid=trackId,
            bbox = track.bbox,
            bbox3d = TrackMeta.getValue(trackId,TrackMetaKeys.BBox3d),
            prev_bbox = TrackMeta.getValue(trackId,TrackMetaKeys.TripwirePreviousBBox),
            custom = {
                is_people = TrackMeta.getValue(trackId,TrackMetaKeys.IsPerson),
                is_vehicle = TrackMeta.getValue(trackId,TrackMetaKeys.IsVehicle),
                is_animal = TrackMeta.getValue(trackId,TrackMetaKeys.IsAnimal),
                is_unknown = TrackMeta.getValue(trackId,TrackMetaKeys.IsUnknown),
                moving = IsTrackMoving(track)
            },
            last_seen = track.lastSeen,
        }
        
        if trackTargetInfo.prev_bbox == nil then
            trackTargetInfo.prev_bbox = trackTargetInfo.bbox
        end

        table.insert(tracksTargetInfo,trackTargetInfo)
    end

    -- Check if any tripwires triggered and update current_hits internally
    local tripwiresEvents = {}
    local tripwireIds = tripwireInst:getTripwireIds()

    for _, tripwireId in ipairs(tripwireIds) do
        
        local tripwireConfig = instance:getConfigValue("Tripwire/Tripwires/"..tripwireId)

        local tripwireTargets = table.filter(tracksTargetInfo,function (tripwireTarget)
            -- Only consider relevant tracks that have a previous bbox and have not been checked recently
            return IsTrackRelevantForTripwire(tripwireTarget.track,tripwireInst,tripwireId)
        end)
        
        tripwireTargets = table.remap(tripwireTargets, function (trackTargetInfo)

            local prev_bbox_point = GetAnchorPointFromObject(trackTargetInfo.prev_bbox, trackTargetInfo.bbox3d, tripwireConfig.check_anchor_point)
            local bbox_point = GetAnchorPointFromObject(trackTargetInfo.bbox, trackTargetInfo.bbox3d, tripwireConfig.check_anchor_point)
            trackTargetInfo.points = {{prev_bbox_point.x,prev_bbox_point.y},{bbox_point.x,bbox_point.y}}

            table.insert(pointsChecked, {x=prev_bbox_point.x,y=prev_bbox_point.y})
            table.insert(pointsChecked, {x=bbox_point.x,y=bbox_point.y})

            return {id=trackTargetInfo.id,current_bbox=trackTargetInfo.bbox,points={{prev_bbox_point.x,prev_bbox_point.y},{bbox_point.x,bbox_point.y}}}
        end)

        if #tripwireTargets > 0 then

            tripwireInst:processTripwires(tripwireTargets,{tripwireId})

            table.extend(tripwiresEvents,tripwireInst:getTripwireEvents())

            for _, trackTargetInfo in pairs(tripwireTargets) do
                TrackMeta.setValue(trackTargetInfo.id,TrackMetaKeys.TripwirePreviousBBox,CopyRect(trackTargetInfo.current_bbox))
            end
        end
        
    end

    return {tripwiresEvents, pointsChecked}
end

--- @param zoneInst zonemanaged Instance of Zone plugin
--- @param zoneEvents table Table with zone events
--- @param tracks Track[] List of tracks
--- @param imgbuffer buffer Image where debug text will be rendered to
--- @param currentTimeSec number Current time in seconds (gotten in the beggining of the loop)
--- @param outputEvents table Table with output events
function handleAreas(zoneInst, zoneEvents, tracks, imgbuffer, currentTimeSec, outputEvents)

    UpdateObjectInsideLastKnownInfo(tracks,zoneInst)

    for _, zoneEvent in ipairs(zoneEvents) do
        local trackId = zoneEvent[1]
        local zoneId = zoneEvent[2]
        local enter = zoneEvent[3]

        local triggerOnEnter = zoneInst:getZoneValue(zoneId,"trigger_on_enter",ZoneDictType.Config)
        local triggerOnExit = zoneInst:getZoneValue(zoneId,"trigger_on_exit",ZoneDictType.Config)
        local triggerOnCrowding = zoneInst:getZoneValue(zoneId,"trigger_crowding",ZoneDictType.Config)
        local triggerOnIntrusion = zoneInst:getZoneValue(zoneId,"trigger_on_intrusion",ZoneDictType.Config)
        local ignoreStationaryObjects = zoneInst:getZoneValue(zoneId,"ignore_stationary_objects",ZoneDictType.Config)
        local crowdingMinCount = zoneInst:getZoneValue(zoneId,"crowding_min_count",ZoneDictType.Config)

        local objectsInside = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside,ZoneDictType.State) or {}
        local ongoingIntrusions = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.OngoingIntrusions,ZoneDictType.State) or {}
        local ongoingLoiterings = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.OngoingLoiterings,ZoneDictType.State) or {}
        local currentEntries = zoneInst:getZoneValue(zoneId,"cur_entries",ZoneDictType.State) or {}
        local isCrowded = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.IsCrowded,ZoneDictType.State) or {}

        if enter == 0 then
            
            local track = GetTrackById(tracks,trackId)
            local trackBbox = track.bbox
            --Object entered zone            
            --Trigger on enter event
            if ShouldConsiderEventsGeneratedByTrack(track,tracks) == true and (triggerOnEnter or triggerOnIntrusion) then
                local label = "Entered area"
                local eventType = EventTypes.AreaEnter
                if triggerOnEnter and ignoreStationaryObjects then
                    label = getTrackDisplayClass(track).." movement in area"
                elseif triggerOnIntrusion then
                    if IsTrackUnknown(track) then
                        label = "Unknown movement detected"
                    else
                        label = getTrackDisplayClass(track).." Intrusion detected"
                    end

                    eventType = EventTypes.IntrusionStart
                end

                local extra = {
                    bbox = trackBbox,
                    track_id = trackId,
                    external_id = track.externalId,
                    class = getTrackClass(track),
                }
                
                if VehicleClassifier.HasVehicleClass(track) then
                    extra.vehicle_class = VehicleClassifier.GetVehicleClass(track)
                end
                if ParClassifier.KnowIfIsCarryingGun(track) then
                    extra.armed = ParClassifier.IsCarryingGun(track)
                end

                local event = addEvent(outputEvents,eventType,imgbuffer,extra,label,{track},zoneId,nil)

                if eventType == EventTypes.IntrusionStart then
                    local eventRelevantData = {id = event.id, frame_time = event.frame_time, extra = event.extra}
                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.OngoingIntrusions.."/"..trackId,eventRelevantData,ZoneDictType.State)
                end

            end
        
            --Check for crowding
            if triggerOnCrowding then

                local isCrowded = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.IsCrowded,ZoneDictType.State)
                
                if currentEntries >= crowdingMinCount and isCrowded ~= true then
                    
                    local extra = {
                    }
                    local trackIds = table.keys(objectsInside)
                    local tracks = table.filter(tracks,function (track)
                        return table.contains(trackIds,track.id)
                    end)
                    addEvent(outputEvents,EventTypes.AreaCrowding,imgbuffer,extra,"Crowding in area",tracks,zoneId,nil)

                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.IsCrowded,true,ZoneDictType.State)
                end
            end
        else

            --Object left zone
            -- If zone crowding is active and the number of objects dropped below the threshold, clear the flag so that we can trigger the event again once the threshold is reached
            if triggerOnCrowding and isCrowded and currentEntries < crowdingMinCount then
                isCrowded = false
                zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.IsCrowded,isCrowded,ZoneDictType.State)
            end

            --Trigger on exit event
            local isOngoingIntrusion = ongoingIntrusions[trackId] ~= nil
            local isOngoingLoitering = ongoingLoiterings[trackId] ~= nil

            if isOngoingIntrusion or isOngoingLoitering or triggerOnExit == true then

                local eventType = EventTypes.AreaExit
                local label = "Exited area"

                local externalTrackIdLeft = TrackMeta.getValue(trackId,TrackMetaKeys.ExternalId)

                local extra = {
                    track_id_left = trackId,
                    external_track_id_left = externalTrackIdLeft
                }
                local eventTracks = {}
                if DoesTrackExist(tracks,trackId) then
                    
                    local track = GetTrackById(tracks,trackId)
                    local trackBbox = track.bbox
                    extra.bbox = trackBbox
                    extra.class = getTrackClass(track)
                    extra.external_id = track.externalId
                    if VehicleClassifier.HasVehicleClass(track) then
                        extra.vehicle_class = VehicleClassifier.GetVehicleClass(track)
                    end
                    if ParClassifier.KnowIfIsCarryingGun(track) then
                        extra.armed = ParClassifier.IsCarryingGun(track)
                    end
                    eventTracks = {GetTrackById(tracks,trackId)}
                end

                local eventId = nil

                --- If we are exiting an ongoing intrusion, we need to trigger the event and remove it from the list of ongoing intrusions
                --- We also reuse the event id in that case
                if isOngoingIntrusion then
                    local intrusionStartEventData = ongoingIntrusions[trackId]
                    ongoingIntrusions[trackId] = nil
                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.OngoingIntrusions.."/"..trackId,nil,ZoneDictType.State)

                    eventId = intrusionStartEventData.id
                    eventType = EventTypes.IntrusionEnd
                    -- calculate duration of intrusion
                    local currentFrameTime = imgbuffer:getTimestamp()
                    extra.duration = currentFrameTime - intrusionStartEventData.frame_time
                    extra.start_frame_time = intrusionStartEventData.frame_time
                    extra.end_frame_time = currentFrameTime
                    label = "Intrusion ended"
                elseif isOngoingLoitering then
                    local loiteringStartEventData = ongoingLoiterings[trackId]
                    ongoingLoiterings[trackId] = nil
                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.OngoingLoiterings.."/"..trackId,nil,ZoneDictType.State)
                    eventId = loiteringStartEventData.id
                    eventType = EventTypes.LoiteringEnd
                    -- calculate duration of intrusion
                    local currentFrameTime = imgbuffer:getTimestamp()
                    extra.loitering_time = (currentFrameTime - loiteringStartEventData.frame_time) + loiteringStartEventData.extra.loitering_time
                    extra.start_frame_time = loiteringStartEventData.frame_time
                    extra.end_frame_time = currentFrameTime
                    label = "Loitering ended"
                end


                addEvent(outputEvents,eventType,imgbuffer,extra,label,eventTracks,zoneId,nil,eventId)
            end

        end
    end

end



---Handle Line Crossing and Tailgating
---@param tripwireInst tripwiremanaged
---@param imgbuffer buffer
---@param tripwireEvents any
---@param tracks Track[]
---@param currentTimeSec number
---@param outputEvents table Sequence where line crossing and tailgating events will be added to
function handleLineCrossingAndTailgating(tripwireInst, imgbuffer, tripwireEvents, tracks, currentTimeSec, outputEvents)
    local instance = api.thread.getCurrentInstance()
    local tripWireActivationCooldownSec = 3.0

    if tripwireEvents ~= nil then
        for _, triggerEvent in pairs(tripwireEvents) do

            local trackId = triggerEvent[1]
            local track = GetTrackById(tracks,trackId)

            local trackTripwiresCrossed = TrackMeta.getValue(trackId, TrackMetaKeys.TripwiresCrossed)
            if trackTripwiresCrossed == nil then trackTripwiresCrossed = {} end
            
            local trackBbox = track.bbox

            local tripWireId = triggerEvent[2]
            local tripwireConfig = instance:getConfigValue("Tripwire/Tripwires/" .. tripWireId)

            local crossingDirection = triggerEvent[3]

            local tripWire = tripwireInst:getTripwireById(tripWireId)

            if tripWire.custom == nil then tripWire.custom = {} end

            if trackBbox ~= nil then

                local shouldTrigger = true

                -- Check if the track has crossed this tripwire before
                if trackTripwiresCrossed[tripWireId] ~= nil then
                    local timeSinceLastCrossing = currentTimeSec - trackTripwiresCrossed[tripWireId]
                    if timeSinceLastCrossing < tripWireActivationCooldownSec then
                        shouldTrigger = false
                    end
                end

                if shouldTrigger then

                    -- Update tripwire crossed time
                    trackTripwiresCrossed[tripWireId] = currentTimeSec
                    TrackMeta.setValue(trackId, TrackMetaKeys.TripwiresCrossed, trackTripwiresCrossed)

                    -- Crossed event
                    
                    local extra = {
                        class = getTrackDisplayClass(track),
                        bbox = trackBbox,
                        track_id = trackId,
                        external_id = track.externalId,
                        tripwire = tripwireConfig,
                        crossing_direction = crossingDirection
                    }
                    if VehicleClassifier.HasVehicleClass(track) then
                        extra.vehicle_class = VehicleClassifier.GetVehicleClass(track)
                    end
                    addEvent(outputEvents,EventTypes.TripwireCrossing,imgbuffer,extra,"Tripwire crossed",{track},nil,tripWire)

                    -- Check tailgating
                    if tripwireConfig.trigger_tailgating then

                        local tailgatingMaxDuration = tripwireConfig.tailgating_maximum_crossing_elapsed or 1.0
                        if tripWire.custom.last_trigger ~= nil then
                            local td = currentTimeSec - tripWire.custom.last_trigger

                            -- Time delta needs to be positive. If the video restarts, that might not be the case
                            if td >= 0.0 and td <= tailgatingMaxDuration then
                                -- Tailgating detected
                                tripWire.custom.last_tailgating = tostring(currentTimeSec)
                                local extra = {
                                    class = getTrackDisplayClass(track),
                                    bbox = trackBbox,
                                    track_id = trackId,
                                    external_id = track.externalId,
                                    tripwire = tripwireConfig,
                                    time_interval = td
                                }
                                if VehicleClassifier.HasVehicleClass(track) then
                                    extra.vehicle_class = VehicleClassifier.GetVehicleClass(track)
                                end

                                -- Check if the last track to have crossed the tripwire is still alive. If not, ignore it

                                local lastTrackId = tripWire.custom.last_triggered_track_id

                                local eventTracks = {track}
                                extra.second_crossing_track_external_id = track.externalId     
                                if lastTrackId ~= nil and DoesTrackExist(tracks,lastTrackId) then
                                    local lastTrack = GetTrackById(tracks,lastTrackId)
                                    eventTracks = {track,lastTrack}
                                    extra.first_crossing_track_external_id = lastTrack.externalId
                                end

                                addEvent(outputEvents,EventTypes.TripwireTailgating,imgbuffer,extra,"Tailgating",eventTracks,nil,tripWire)
                            end
                        end

                        tripWire.custom.last_trigger = currentTimeSec
                        tripWire.custom.last_triggered_track_id = trackId

                    end

                end

            end

            tripwireInst:setTripwireValue(tripWireId, tripWire, 0);
        end
    end
    
end

--- @param imgbuffer buffer Pointer to BufferLua object
--- @param zoneInst zonemanaged Instance of Zone plugin
--- @param currentTimeSec number Current time in seconds
--- @param tracks Track[] List of tracks
--- @param outputEvents table Table with output events
function handleAreaLoitering(imgbuffer, zoneInst, currentTimeSec, tracks, outputEvents)
    local instance = api.thread.getCurrentInstance()
    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in ipairs(zoneIds) do

        local triggerOnLoitering = zoneInst:getZoneValue(zoneId,"trigger_loitering",ZoneDictType.Config)
        
        if triggerOnLoitering then

            local loiteringMinDuration = zoneInst:getZoneValue(zoneId,"loitering_min_duration",ZoneDictType.Config)
            local loiteringNotifications = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.LoiteringNotifications,ZoneDictType.State) or {}

            local maxObjectStayDuration = 0.0

            if loiteringMinDuration == nil then
                loiteringMinDuration = 3.0
            end

            local objectsInside = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside,ZoneDictType.State) or {}

            for trackId, enterTime in pairs(objectsInside) do

                TrackMeta.setValue(trackId,TrackMetaKeys.LoiteringStatus,TrackLoiteringStatus.Checking)
                
                local trackAreaStayDuration = math.abs(currentTimeSec - tonumber(enterTime))
            
                if trackAreaStayDuration > maxObjectStayDuration then
                    maxObjectStayDuration = trackAreaStayDuration
                end

                if trackAreaStayDuration > loiteringMinDuration and loiteringNotifications[trackId] == nil then

                    TrackMeta.setValue(trackId,TrackMetaKeys.LoiteringStatus,TrackLoiteringStatus.Confirmed)

                    local track = GetTrackById(tracks, trackId)

                    local extra = {
                        track_id = trackId,
                        external_id = track.externalId,
                        bbox = track.bbox,
                        class = getTrackDisplayClass(track),
                        loitering_time = trackAreaStayDuration
                    }
                    if VehicleClassifier.HasVehicleClass(track) then
                        extra.vehicle_class = VehicleClassifier.GetVehicleClass(track)
                    end

                    local loiteringEvent = addEvent(outputEvents,EventTypes.LoiteringStart,imgbuffer,extra,"Loitering started",{track},zoneId,nil)
                    
                    local eventRelevantData = {id = loiteringEvent.id, frame_time = loiteringEvent.frame_time, extra = loiteringEvent.extra}

                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.LoiteringNotifications.."/"..trackId,tostring(currentTimeSec),ZoneDictType.State)
                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.OngoingLoiterings.."/"..trackId,eventRelevantData,ZoneDictType.State)

                end
            end

            -- Clean up dead tracks from loitering notifications
            for trackId, enterTime in pairs(loiteringNotifications) do
                if not DoesTrackExist(tracks, trackId) then
                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.LoiteringNotifications.."/"..trackId,nil,ZoneDictType.State)
                end
            end
        end
    end
end

--- Updates zones with custom information on which objects are inside and when did they enter
--- In addition, it also smooths the events by applying require enough time to pass before considering the object as "inside"
--- @param zoneEvents table Zone Events
--- @param zoneInst zonemanaged Instance of Zone plugin
--- @param tracks Track[]
--- @param currentTimeSec number Current time in seconds
function updateObjectsInsideZonesAndSmoothEvents(zoneEvents, zoneInst, tracks, currentTimeSec)

    local smoothedZoneEvents = {}


    -- Go through all enter/exit zone events and update zone.custom.objects_inside accordingly 
    for _, zoneEvent in ipairs(zoneEvents) do
        local trackid = zoneEvent[1]
        local zoneId = zoneEvent[2]
        local enter = zoneEvent[3]

        local objectsEntered = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsEntered,ZoneDictType.State) or {}
        local objectsInside = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside,ZoneDictType.State) or {}

        -- Check if relevant track entered zone
        if enter == 0 then
            objectsEntered[trackid] = currentTimeSec
            zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsEntered,objectsEntered,ZoneDictType.State)
        else
            if objectsInside[trackid] ~= nil then
                table.insert(smoothedZoneEvents,{trackid,zoneId,1})
                objectsInside[trackid] = nil
            else
                objectsInside[trackid] = nil
            end
            zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside,objectsInside,ZoneDictType.State)
        end
    end

    
    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in ipairs(zoneIds) do

        -- check if enough time has elapsed for them to be considered to be inside it
        local objectsEntered = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsEntered,ZoneDictType.State) or {}
        local objectsInside = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside,ZoneDictType.State) or {}
        local enterActivationDelay = zoneInst:getZoneValue(zoneId,"enter_activation_delay",ZoneDictType.Config)

        for trackId, enterTime in pairs(objectsEntered) do

            local timeSinceEnter = currentTimeSec - enterTime

            local enterActivationDelay = enterActivationDelay

            if enterActivationDelay == nil then
                enterActivationDelay = 0.2
            end
            
            if timeSinceEnter >= enterActivationDelay then

                objectsEntered[trackId] = nil
                zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsEntered,objectsEntered,ZoneDictType.State)

                -- Check if the track still exists (but might killed after entering, but before being considered inside)

                if DoesTrackExist(tracks,trackId) then
                    table.insert(smoothedZoneEvents,{trackId,zoneId,0})
                    zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside.."/"..trackId,currentTimeSec,ZoneDictType.State)
                end

            end
        end
        
        -- check if the track still exists.
        -- If not, update zone.custom.objects_inside accordingly
        for trackId, _ in pairs(objectsInside) do
            if DoesTrackExist(tracks,trackId) == false then

                -- Track no longer exists, remove entry from objects_inside
                zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside.."/"..trackId,nil,ZoneDictType.State)

                -- Add track exited to zoneEvents
                table.insert(smoothedZoneEvents, {trackId, zoneId, 1})
            end
        end
    end


    return smoothedZoneEvents
end

--- @param trackerInst trackermanaged Tracker plugin instance
--- @param zoneInst zonemanaged Zone plugin instance
--- @param imgbuffer buffer Output image buffer
--- @param currentTimeSec number Current time in seconds
--- @param outputEvents table Output events
function handleObjectRemoved(trackerInst, zoneInst, imgbuffer, currentTimeSec, outputEvents)
    local instance = api.thread.getCurrentInstance()
    local trackIds = trackerInst:getTrackIds()

    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in pairs(zoneIds) do
        local zoneConfig = instance:getConfigValue("Zone/Zones/"..zoneId)
        local zoneVertices = ConvertVerticesToPairs(zoneConfig.vertices)
        if zoneConfig.trigger_when ~= "object_removed" then
            goto continue
        end

        local triggerDuration = zoneConfig.removed_duration

        for _, trackId in pairs(trackIds) do

            if trackerInst:getTrackValue(trackId,"tracking_lock") ~= true then
                goto continue
            end

            local trackBbox = trackerInst:getTrackValue(trackId,"bbox")
            local current_box = trackBbox
            local isInsideZone = false

            local shapeBox = GetShapeBoundingBox(zoneVertices)

            if BoxContainment(current_box,shapeBox) > 0.5 then
                isInsideZone = true
            end

            local trackCustomData = trackerInst:getTrackValue(trackId,"custom")

            if isInsideZone or trackCustomData.object_last_box_time ~= nil then

                if trackCustomData.object_last_box == nil then
                    trackCustomData.object_last_box = trackBbox
                    trackCustomData.object_last_box_time = currentTimeSec
                end

                local iou_compared_to_last_box = GeomUtils.Iou(trackCustomData.object_last_box,current_box)


                if iou_compared_to_last_box < 0.8 then
                    -- Reset loitering 
                    trackCustomData.object_last_box = trackBbox
                    trackCustomData.object_last_box_time = currentTimeSec
                end

                if trackCustomData.object_removed_track_notifications == nil then
                    trackCustomData.object_removed_track_notifications = {}
                end

                local loitering_duration = currentTimeSec - tonumber(trackCustomData.object_last_box_time)
                
                if loitering_duration > triggerDuration and trackCustomData.object_removed_track_notifications[tostring(trackId)] == nil then
                    -- POST EVENT
                    local extra = {
                        bbox = trackBbox,
                        track_id = trackId,
                        zone = zoneConfig
                    }
                    local track = {bbox=trackBbox}
                    
                    addEvent(outputEvents,EventTypes.ObjectRemoved,imgbuffer,extra,"Object removed",{track},nil,nil)

                    trackCustomData.object_removed_track_notifications[tostring(trackId)] = currentTimeSec
                end

                trackCustomData.object_last_box_time = tostring(trackCustomData.object_last_box_time)

                trackerInst:saveTrackValue(trackId,"custom",trackCustomData)
            end
            ::continue::
        end
        ::continue::
    end
end


--- @param trackerInst trackermanaged Tracker plugin instance
--- @param zoneInst zonemanaged Zone plugin instance
--- @param imgbuffer buffer Output image buffer
--- @param currentTimeSec number Current time in seconds
--- @param outputEvents table Output events
function handleObjectLeft(trackerInst, zoneInst, imgbuffer, currentTimeSec, outputEvents)
    local instance = api.thread.getCurrentInstance()
    local trackIds = trackerInst:getTrackIds()

    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in pairs(zoneIds) do
        local zoneConfig = instance:getConfigValue("Zone/Zones/"..zoneId)
        local zoneVertices = ConvertVerticesToPairs(zoneConfig.vertices)
        
        if zoneConfig.trigger_when ~= "object_left" then
            goto continue
        end

        local triggerDuration = zoneConfig.left_duration

        for _, trackId in pairs(trackIds) do

            if trackerInst:getTrackValue(trackId,"tracking_lock") ~= true then
                goto continue
            end

            local trackBbox = trackerInst:getTrackValue(trackId,"bbox")
            local current_box = trackBbox
            local isInsideZone = false

            if GeomUtils.Iou(GetShapeBoundingBox(zoneVertices), current_box) > 0.0 then
                isInsideZone = true
            end

            if isInsideZone then

                local trackCustomData = trackerInst:getTrackValue(trackId,"custom")

                if trackCustomData.object_last_box == nil then
                    trackCustomData.object_last_box = trackBbox
                    trackCustomData.object_last_box_time = currentTimeSec
                end


                local iou_compared_to_last_box = GeomUtils.Iou(trackCustomData.object_last_box,current_box)


                if iou_compared_to_last_box < 0.8 then
                    -- Reset timing 
                    trackCustomData.object_last_box = trackBbox
                    trackCustomData.object_last_box_time = currentTimeSec
                end

                local loitering_duration = currentTimeSec - tonumber(trackCustomData.object_last_box_time)

                if trackCustomData.object_left_track_notifications == nil then
                    trackCustomData.object_left_track_notifications = {}
                end

                if loitering_duration > triggerDuration and trackCustomData.object_left_track_notifications[tostring(trackId)] == nil then

                    --print("trackId "..inspect(trackId))
                    --print("trackCustomData.object_left_track_notifications "..inspect(trackCustomData.object_left_track_notifications))

                    -- POST EVENT
                    local extra = {
                        bbox = trackBbox,
                        track_id = trackId,
                        zone = zoneConfig
                    }
                    local track = {bbox=trackBbox}
                    addEvent(outputEvents,EventTypes.ObjectLeft,imgbuffer,extra,"Object left",{track},nil,nil)
                    trackCustomData.object_left_track_notifications[tostring(trackId)] = currentTimeSec
                end            

                trackCustomData.object_last_box_time = tostring(trackCustomData.object_last_box_time)

                trackerInst:saveTrackValue(trackId,"custom",trackCustomData)
            end
            ::continue::
        end
        ::continue::
    end
end

---Adds an event to the outputEvents table and returns the event
---@param outputEvents Event[]
---@param eventType string
---@param inputimage buffer
---@param extra table
---@param label string
---@param tracks Track[]
---@param zoneId string|nil
---@param tripwire table|nil
---@param id string|nil
---@return Event
function addEvent(outputEvents,eventType,inputimage,extra,label,tracks,zoneId,tripwire,id)
    -- TODO: expose the padding as a config option
    local padding = 0.02
    local image = nil

    if #tracks > 0 then
        local imageBbox = GetTracksBoundingBox(tracks)
        image = inputimage:copy(imageBbox.x-padding,imageBbox.y-padding,imageBbox.width+padding*2,imageBbox.height+padding*2,true)
    elseif zoneId ~= nil then

        local zoneVertices = zoneInst:getZoneValue(zoneId,"vertices",ZoneDictType.Config)
        local zone_bbox = GetShapeBoundingBox(ConvertVerticesToPairs(zoneVertices))
        image = inputimage:copy(zone_bbox.x-padding,zone_bbox.y-padding,zone_bbox.width+padding*2,zone_bbox.height+padding*2,true)
    end

    local instance = api.thread.getCurrentInstance()

    local zoneName = nil
    local tripwireName = nil

    if zoneId ~= nil then
        zoneName = zoneInst:getZoneValue(zoneId,"name",ZoneDictType.Config)
    end

    if tripwire ~= nil then
        tripwireName = tripwireInst:getTripwireValue(tripwire.id,"name",ZoneDictType.Config)
    end

    local eventData = {
        id = id or api.system.generateGuid(),
        type = eventType,
        label = label,
        image = image,
        date = os.date("%c"),
        frame_time = inputimage:getTimestamp(),
        frame_id = inputimage:getFrameId(),
        instance_id = instance:getName(),
        system_date = get_current_date_RFC_3339(),
        extra = extra,
        tracks = tracks,
        zone_id = zoneId,
        tripwire_id = tripwire ~= nil and tripwire.id or nil,
        zone_name = zoneName,
        tripwire_name = tripwireName
    }

    table.insert(outputEvents,eventData)

    return eventData
end


---Returns the number of object left/removed zones in an instance
---@param zoneInst any
function numberOfObjectLeftRemovedAreas(zoneInst)
    local zoneIds = zoneInst:getZoneIds()
    local numberOfAreas = 0
    for _, zoneId in ipairs(zoneIds) do
        
        local triggerWhen = zoneInst:getZoneValue(zoneId,"trigger_when",ZoneDictType.Config)

        if triggerWhen == "object_left" or triggerWhen == "object_removed" then
            numberOfAreas = numberOfAreas + 1
        end
    end
    return numberOfAreas
end

function anyTriggerRequiresDetector(instance,zoneInst,tripwireInst)
    if #tripwireInst:getTripwireIds() > 0 then
        return true
    end

    local numZones = #zoneInst:getZoneIds()
    if numZones > 0 and numberOfObjectLeftRemovedAreas(zoneInst) < numZones then
        return true
    end

    return false
end


---
---@param event Event
---@param currentTracks Track[]
function AddBestThumbnailToEvent(event,currentTracks)

    local eventTracks = event.tracks

    if #eventTracks == 1 then
        local eventTrack = eventTracks[1]
        local currentTrack = GetTrackById(currentTracks,eventTrack.id)
        if currentTrack ~= nil and currentTrack.bestThumbnail ~= nil then
            event.best_thumbnail = currentTrack.bestThumbnail
            event.image = event.best_thumbnail.image
        end
    end

end

--- Update Event subtype
---@param event Event
---@param lastFrameTracks Track[]
function UpdateEventSubtype(event,lastFrameTracks)
    event.subtype = ""

    if #event.tracks == 1 then
        local track = event.tracks[1]

        if ParClassifier.KnowIfIsCarryingGun(track) and ParClassifier.IsCarryingGun(track) then
            event.subtype = "person_armed"
        end
    end

    if event.extra.track_id_left ~= nil then
        local track = GetTrackById(lastFrameTracks,event.extra.track_id_left)
        if track~= nil and ParClassifier.KnowIfIsCarryingGun(track) and ParClassifier.IsCarryingGun(track) then
            event.subtype = "person_armed"
        end
    end
end