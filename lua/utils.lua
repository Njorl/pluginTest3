dofile(project_root .. "/geometry_utils.lua")
dofile(project_root .. "/lua_helpers.lua")
dofile(project_root .. "/enums.lua")
dofile(project_root .. "/3dbbox.lua")
dofile(project_root .. "/definitions.lua")
dofile(project_root .. "/trackmeta.lua")
dofile(project_root .. "/vehicle_classifier.lua")
dofile(project_root .. "/par_classifier.lua")


-- DebugTrackId = "VehicleTracker_1845" -- Set this to nil on production
DebugTrackId = nil -- Set this to nil on production


---Checks if a track is relevant to a given zone. This only checks for class compatibility
---@param track Track
---@param zoneInst zonemanaged
---@param zoneId string
---@param tripwireInst tripwiremanaged
---@param tripwireId string
---@return boolean
function ShouldConfirmEventForTrackOnZoneOrTripwire(track,zoneInst,zoneId,tripwireInst,tripwireId)

    local instance = api.thread.getCurrentInstance()

    if IsTrackLocked(track) ~= true then
        return false
    end

    local ignoreStationaryObjects = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"ignore_stationary_objects")

    if ignoreStationaryObjects == true and IsOrWasTrackMoving(track) ~= true then
        return false
    end

    local objectMinWidth = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"object_min_width")
    local objectMinHeight = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"object_min_height")
    local objectMaxWidth = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"object_max_width")
    local objectMaxHeight = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"object_max_height")

    local trackWidth = track.bbox.width
    local trackHeight = track.bbox.height

    --Check object size restrictions
    if objectMinWidth ~= nil then
        if trackWidth < objectMinWidth then
            return false
        end
    end

    if objectMinHeight ~= nil then
        if trackHeight < objectMinHeight then
            return false
        end
    end

    if objectMaxWidth ~= nil then
        if trackWidth > objectMaxWidth then
            return false
        end
    end

    if objectMaxHeight ~= nil then
        if trackHeight > objectMaxHeight then
            return false
        end
    end

    local detectPeople = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"detect_people")
    local detectVehicles = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"detect_vehicles")
    local detectAnimals = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"detect_animals")
    local detectUnknowns = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"detect_unknowns")


    if IsTrackPerson(track) and detectPeople == true then

        local restrictPersonAttributes = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"restrict_person_attributes")

        if restrictPersonAttributes == true then
            if ParClassifier.KnowIfIsCarryingGun(track) then
                local restrictPersonAttributeCarryingGun = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"restric_person_attribute_CarryingGun") 
                return ParClassifier.IsCarryingGun(track) == restrictPersonAttributeCarryingGun
            else
                return false
            end
        end

        return true
    elseif IsTrackVehicle(track) and detectVehicles == true then

        -- If Vehicle subclassification is enabled, wait for the vehicle classifier to classify the vehicle
        if VehicleClassifier.IsEnabled(instance) then
            if VehicleClassifier.HasVehicleClass(track) ~= true then
                return false
            end

            local restrictVehicleType = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"restrict_vehicle_type")

            -- Vehicle subclassification
            if restrictVehicleType == true then
                local vehicleClass = VehicleClassifier.GetVehicleClass(track)
                -- If not specified in the config that we don't want a certain vehicle class, then we consider it relevant

                local detectVehicleClass = GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,"detect_vehicle_"..vehicleClass)

                if detectVehicleClass == true then
                    return true
                else
                    return false
                end
            end
        end


        return true
    elseif IsTrackAnimal(track) == true and detectAnimals == true then
        return true
    elseif IsTrackUnknown(track) == true and detectUnknowns == true and IsTrackMoving(track) == true then
        return true
    end
        
    return false
end

function MatchBestIoU(box, candidates, iouThreshold)
    iouThreshold = iouThreshold or 0.5
    local iouMax, idxMax, boxArea = 0, -1, box.width * box.height
    for idx, candidate in pairs(candidates) do
        local x0 = math.max(box.x, candidate.x)
        local x1 = math.min(box.x + box.width, candidate.x + candidate.width)
        if x0 >= x1 then goto continue end

        local y0 = math.max(box.y, candidate.y)
        local y1 = math.min(box.y + box.height, candidate.y + candidate.height)
        if y0 >= y1 then goto continue end

        local unionArea = (x1-x0) * (y1-y0)
        local candidateArea = candidate.width * candidate.height
        local iou = unionArea / (candidateArea + boxArea - unionArea)

        if iou > iouMax and iou > iouThreshold then
            iouMax = iou
            idxMax = idx
        end

        ::continue::
    end

    if idxMax < 0 then return nil end
    return { iou = iouMax, idx = idxMax, box = {x = candidates[idxMax].x, y = candidates[idxMax].y, width = candidates[idxMax].width, height = candidates[idxMax].height } }
end

--- This function updates the track's confidence field
---@param trackerInst    trackermanaged
---@param tracks    Track[]
---@param sourceBoxes    Detection[]
function UpdateTracksConfidence(tracks,trackerInst,sourceBoxes)

    local matchedTracks = trackerInst:getMatchedTracks()
    local matchedTracksMap = {}

    for _, matchPair in ipairs(matchedTracks) do
        matchedTracksMap[matchPair[1]] = matchPair[2]
    end

    for _, track in pairs(tracks) do

        local sourceTrackId = track.sourceTrackerTrackId

        if matchedTracksMap[sourceTrackId] ~= nil then
            -- Update the track's confidence based on the latest detection
            local sourceBoxIdx = matchedTracksMap[sourceTrackId] + 1
            local sourceBox = sourceBoxes[sourceBoxIdx]
            if sourceBox.confidence ~= nil then
                TrackMeta.setValue(track.id,TrackMetaKeys.Confidence,sourceBox.confidence)
            else
                TrackMeta.setValue(track.id,TrackMetaKeys.Confidence,0.0)
            end
        else
            TrackMeta.setValue(track.id,TrackMetaKeys.Confidence,0.0)
        end

    end


end

--- Gets regions for the object detector based on the inference strategy configured
--- @param instance rt_instance RT instance
--- @param inputimg buffer Input image buffer
--- @param motionRegions table
--- @param isDetectionEnabled boolean
--- @param detectInst inferencemanaged
--- @param tracks Track[]
--- @return DetectorRegionsInfo
function GetDetectorRegionsInfoFromInferenceStrategy(instance,inputimg,isDetectionEnabled,motionRegions,detectInst,tracks)

    local inputImgSize = inputimg:getSize()

    if not isDetectionEnabled then

        local detectorRegionsInfo = {}
        detectorRegionsInfo.isUsingAtlasPacking = false
        detectorRegionsInfo.regions = {}

        return detectorRegionsInfo
    end

    local detectionInferenceStrategy = instance:getConfigValue("Global/Detection/inference_strategy")

    if detectionInferenceStrategy == InferenceStrategy.FullFrameInference then

        local detectorRegionsInfo = {}
        detectorRegionsInfo.isUsingAtlasPacking = false
        detectorRegionsInfo.regions = {{ source = inputimg, x = 0.0, y = 0.0, width = 1.0, height = 1.0 }}

        return detectorRegionsInfo
    elseif detectionInferenceStrategy == InferenceStrategy.MotionGuided then

        local regionPadding = instance:getConfigValue("Global/Detection/motion_guided_settings/region_padding")


        local useVehicleDetectionsForTexturePacking = ShouldConsiderVehicleDetectionsForTexturePacking(instance,zoneInst)

        --Both detections and motion regions are considered for the texture packing
        local detectionRegions = {}

        for _, track in pairs(tracks) do
            if IsTrackPerson(track) then
                local personBbox = track.bbox
                table.insert(detectionRegions,personBbox)
            elseif useVehicleDetectionsForTexturePacking and IsTrackVehicle(track) then
                table.insert(detectionRegions,track.bbox)
            end
        end

        for _, motionRegion in ipairs(motionRegions) do
            table.insert(detectionRegions,motionRegion)
        end

        -- Merge redundant boxes
        local absDetectionRegions = GeomUtils.RectsNormToAbs(detectionRegions, inputImgSize)
        absDetectionRegions = GeomUtils.MergeRedundantRects(absDetectionRegions,0.01)
        detectionRegions = GeomUtils.RectsAbsToNorm(absDetectionRegions, inputImgSize)


        if #detectionRegions > 0 then

            ---@type buffer
            local atlas = nil

            --Pad the boxes and adjust them to fit the image boundaries
            for _, detectionRegion in pairs(detectionRegions) do
                detectionRegion = PadBoxRel(detectionRegion,regionPadding)
                detectionRegion = TrimBoxToFitImageBoundaries(detectionRegion)
            end

            atlas, locations = detectInst:packJobs(detectionRegions, inputimg)

            local detectorRegionsInfo = {}
            detectorRegionsInfo.isUsingAtlasPacking = true
            detectorRegionsInfo.atlasPackingInfo = { sourceRegions = detectionRegions, atlasRegions = locations, atlas = atlas}
            detectorRegionsInfo.regions = {{ source = atlas, x = 0.0, y = 0.0, width = 1.0, height = 1.0 }}

            return detectorRegionsInfo
        else
            local detectorRegionsInfo = {}
            detectorRegionsInfo.isUsingAtlasPacking = false
            detectorRegionsInfo.regions = {}

            return detectorRegionsInfo
        end
    end


end

---comment
---@param tracks Track[]
---@param requireLock boolean
---@return table
function ProcessTracksForSinkOutput(tracks, requireLock)

    local tracks_bbox = {}
    local captureExtraTrackInfo = instance:getConfigValue("Global/Debug/capture_extra_track_info") == true
    local enableDebugSinks = instance:getConfigValue("Global/Debug/enable_debug_sinks") == true

    if DebugTrackId ~= nil then
        tracks = table.filter(tracks, function(track)
            return track.id == DebugTrackId
        end)
        if #tracks > 0 then
            local instance = api.thread.getCurrentInstance()
            instance:setPause(true)
        end
    end



    for _, track in pairs(tracks) do

        local trackEvents = TrackMeta.getValue(track.id,TrackMetaKeys.Events)
        local bbox = CopyRect(track.bbox)

        if requireLock ~= true or (requireLock == true and IsTrackLocked(track)) then

            local trackLabel = track.classLabel

            if VehicleClassifier.HasVehicleClass(track) then
                bbox.vehicle_class = VehicleClassifier.GetVehicleClass(track)
                trackLabel = bbox.vehicle_class
            end

            if ParClassifier.KnowIfIsCarryingGun(track) then
                bbox.armed = ParClassifier.IsCarryingGun(track)
            end

            bbox.label = track.id

            if trackEvents ~= nil then
                bbox.events = trackEvents
            end

            bbox.track_id = track.id
            bbox.external_id = track.externalId

            bbox.class_label = getTrackClass(track)
            bbox.is_moving = IsTrackMoving(track)

            bbox.has_tentative_event = (TrackMeta.getValue(track.id,TrackMetaKeys.HasTentativeEvent) == true)
            bbox.track_age = TrackMeta.getValue(track.id,TrackMetaKeys.Age)

            if captureExtraTrackInfo then
                bbox.atlas_crop = track.atlas_crop
                bbox.atlas = track.atlas
                bbox.accum_movement = TrackMeta.getValue(track.id,TrackMetaKeys.AccumulatedMovement)
            end

            if enableDebugSinks then
                local movementStatus = TrackMeta.getValue(track.id,TrackMetaKeys.MovementStatus)
                bbox.label = bbox.label .. " ,m: " .. movementStatus
            end



            if TrackMeta.getValue(track.id,TrackMetaKeys.Confidence) ~= nil then
                bbox.confidence = TrackMeta.getValue(track.id,TrackMetaKeys.Confidence)
            end

            table.insert(tracks_bbox, bbox)
        end

    end
    return tracks_bbox
end

function GetMatchedTracksBboxesFromTracker(trackerInst)
    local tracks_bbox = {}
    local matchedTracksInfo = trackerInst:getMatchedTracks()
    for _, info in ipairs(matchedTracksInfo) do
        table.insert(tracks_bbox, trackerInst:getTrackValue(info[1], "bbox"))

    end
    return tracks_bbox
end

function GetMovingTracksBboxesFromTracker(trackerInst)
    local tracks_bbox = {}
    local trackIds = trackerInst:getTrackIds()
    for _, trackId in pairs(trackIds) do

        if IsTrackMoving(trackId) then
            table.insert(tracks_bbox, trackerInst:getTrackValue(trackId, "bbox"))
        end

    end
    return tracks_bbox
end


function getUnmatchedTracksBboxesFromTracker(trackerInst)
    local tracks_bbox = {}
    local unmatchedTracksInfo = trackerInst:getUnmatchedTracks()
    for _, trackId in ipairs(unmatchedTracksInfo) do
        table.insert(tracks_bbox,trackerInst:getTrackValue(trackId, "bbox"))
    end
    return tracks_bbox
end

function getBoundingBoxFromPath(path)

    local minX = math.huge
    local minY = math.huge
    local maxX = -math.huge
    local maxY = -math.huge

    for _, point in ipairs(path) do
        if point.x < minX then
            minX = point.x
        end
        if point.y < minY then
            minY = point.y
        end
        if point.x > maxX then
            maxX = point.x
        end
        if point.y > maxY then
            maxY = point.y
        end
    end

    return {xMin = minX, yMin = minY, xMax = maxX, yMax = maxY}
end

LastUpdateTrackMovementStatusTimeSec = 0

---Updates tracks movement status
---This goes through every track and keeps track of its recent path
---If both the top-left and bottom-right corners of the track's bounding box move more than a certain distance, the track is considered moving
---If the track is moving, the field .moving is set to true
---This function is called twice per second
---@param instance rt_instance
---@param trackerInst trackermanaged
---@param tracks Track[]
---@param currentTimeSec number
---@param inputSize number[]
function UpdateTracksMovementStatus(instance,tracks,trackerInst,currentTimeSec,inputSize)

    local vehicleMovementThreshold = instance:getConfigValue("Movement/vehicle_movement_threshold")
    local personMovementThreshold = instance:getConfigValue("Movement/person_movement_threshold")
    local animalMovementThreshold = instance:getConfigValue("Movement/animal_movement_threshold")
    local unknownMovementThreshold = instance:getConfigValue("Movement/unknown_movement_threshold")


    for _, track in pairs(tracks) do

        local trackId = track.id

        -- If track is already moving, we use the movement direction to know when it stops moving (and thereby becomes idle)
        if IsTrackMoving(track) then
            
            local movementDirection = track.movementDirection

            ---@type Vec2
            local accumMovement = TrackMeta.getValue(trackId,TrackMetaKeys.AccumulatedMovement)


            ---@type TrackMovementHistoryEntry[]
            local movementDirectionHistory = TrackMeta.getValue(trackId,TrackMetaKeys.MovementDirectionHistory)

            if movementDirectionHistory == nil then
                movementDirectionHistory = {}
            end

            table.insert(movementDirectionHistory,{direction = movementDirection, timestamp = currentTimeSec})
            accumMovement = {x=accumMovement.x + movementDirection.x, y=accumMovement.y + movementDirection.y}
            TrackMeta.setValue(trackId,TrackMetaKeys.MovementDirectionHistory,movementDirectionHistory)
            TrackMeta.setValue(trackId,TrackMetaKeys.AccumulatedMovement,accumMovement)

            -- print("#movementDirectionHistory "..#movementDirectionHistory)
            -- print("accumMovement "..inspect(accumMovement))

            if #movementDirectionHistory > 150 then

                -- If there is not enough movement and we have enough history, we can assume the track is idle
                if (math.abs(accumMovement.x) + math.abs(accumMovement.y)) < 0.1 then
                    TrackMeta.setValue(trackId,TrackMetaKeys.MovementStatus, TrackMovementStatus.Stopped)
                    TrackMeta.setValue(trackId,TrackMetaKeys.AccumulatedMovement,{x=0,y=0})
                else
                    -- Otherwise, let's ensure the history never grows more than the maximum size, by removing the first entry and update accumMovement
                    local firstEntry = movementDirectionHistory[1]
                    accumMovement = {x=accumMovement.x - firstEntry.direction.x, y=accumMovement.y - firstEntry.direction.y}
                    table.remove(movementDirectionHistory,1)
                    TrackMeta.setValue(trackId,TrackMetaKeys.MovementDirectionHistory,movementDirectionHistory)
                end
            end

            
        else

            local movementDirection = track.movementDirection
            local accumMovement = TrackMeta.getValue(trackId,TrackMetaKeys.AccumulatedMovement)
            accumMovement = accumMovement or {x=0,y=0}

            local bboxHistory = TrackMeta.getValue(trackId,TrackMetaKeys.BBoxHistory)
            bboxHistory = bboxHistory or {}
            table.insert(bboxHistory,track.bbox)
            TrackMeta.setValue(trackId,TrackMetaKeys.BBoxHistory,bboxHistory)

            --Update accumMovement
            if movementDirection ~= nil then
                accumMovement = {x=accumMovement.x + movementDirection.x, y=accumMovement.y + movementDirection.y}
                TrackMeta.setValue(trackId,TrackMetaKeys.AccumulatedMovement,accumMovement)
            end

            local relativeMovementTreshold = unknownMovementThreshold

            if IsTrackPerson(track) then
                relativeMovementTreshold = personMovementThreshold
            elseif IsTrackVehicle(track) then
                relativeMovementTreshold = vehicleMovementThreshold
            elseif IsTrackAnimal(track) then
                relativeMovementTreshold = animalMovementThreshold
            end

            if math.abs(accumMovement.x) + math.abs(accumMovement.y) > relativeMovementTreshold then
                TrackMeta.setValue(trackId,TrackMetaKeys.MovementStatus, TrackMovementStatus.Moving)

                -- Since we already know the track is moving, we can disable the CPU-intensive feature tracking feature for it
                trackerInst:saveTrackValue(track.sourceTrackerTrackId, "track_features", false)

                -- Clear out the accumulated movement variable to be used for determining when the track stops moving
                TrackMeta.setValue(trackId,TrackMetaKeys.AccumulatedMovement,{x=0,y=0})
            else 
                if TrackMeta.getValue(trackId,TrackMetaKeys.MovementStatus) == nil then
                    TrackMeta.setValue(trackId,TrackMetaKeys.MovementStatus, TrackMovementStatus.Undetermined)
                end
            end

        end
    end

end

AnchorPointWarnRaised = false;

---Gets an anchor point from an object either from the 2D or 3D bounding box
---@param bbox2d table
---@param bbox3d table
---@param boxAnchor string
function GetAnchorPointFromObject(bbox2d,bbox3d,boxAnchor)
    local x = bbox2d.x
    local y = bbox2d.y
    if boxAnchor == BoxAnchor.Center then
        x = x + bbox2d.width/2
        y = y + bbox2d.height/2
    elseif boxAnchor == BoxAnchor.TopRight then
        x = x + bbox2d.width
    elseif boxAnchor == BoxAnchor.BottomLeft then
        y = y + bbox2d.height
    elseif boxAnchor == BoxAnchor.BottomRight then
        x = x + bbox2d.width
        y = y + bbox2d.height
    elseif boxAnchor == BoxAnchor.TopCenter then
        x = x + bbox2d.width/2
    elseif boxAnchor == BoxAnchor.BottomCenter then
        x = x + bbox2d.width/2
        y = y + bbox2d.height
    elseif boxAnchor == BoxAnchor.BottomPlaneCenter then
        if BBox3d.hasBottomPlaneCenter(bbox3d) then
            local bpc = BBox3d.getBottomPlaneCenter(bbox3d)
            x = bpc[1]
            y = bpc[2]
        else
            if not AnchorPointWarnRaised then
                AnchorPointWarnRaised = true
                api.logging.LogWarning("No 3D Bounding Box available for object, falling back to 2D Bounding Box bottom center")
            end
            return GetAnchorPointFromObject(bbox2d,bbox3d,BoxAnchor.BottomCenter)
        end
    end

    return {x = x, y = y}
end

---writes Tracks to disk in MOT Format 1.1
---@param writeInst writedatamanaged
---@param frameNumber number
---@param tracks table
---@param filePath string
---@param imageSize number[]
function writeTracksToDiskInMOTFormat(writeInst,frameNumber,tracks, filePath,imageSize)

    for _, track in ipairs(tracks) do
        if track ~= nil then
            local line =
            tostring(frameNumber) .. "," ..
                    tostring(track.id) .. "," ..
                    tostring(track.bbox.x*imageSize[1]) .. "," ..
                    tostring(track.bbox.y*imageSize[2]) .. "," ..
                    tostring(track.bbox.width*imageSize[1]) .. "," ..
                    tostring(track.bbox.height*imageSize[2]) .. "," ..
                    "0,0,0,0"
            print("Appending " .. line .. " to "..filePath)
            writeInst:appendText(filePath, line, "\n")
        end
    end
end

---get detector key based on modality
---@param instance rt_instance
---@return string
function getDetectorKeyBasedOnModality(instance)
    local modality = instance:getConfigValue("Global/modality")
    local detectorKey = nil

    if modality == Modality.Thermal then
        detectorKey = PluginKeys.DetectorThermal
    elseif modality == Modality.RGB then
        detectorKey = PluginKeys.DetectorRGB
    else
        api.logging.LogError("Unknown modality: " .. inspect(modality)..", Please set Global/modality to either rgb or thermal")
        instance:setPause(true)
        return ""
    end

    return detectorKey
end

---Deletes inference backend
---@param instance rt_instance
---@param key string
function deleteInferenceBackend(instance,key)
    local inferenceInst = api.factory.inference.get(instance, key)
    if (inferenceInst ~= nil) then
        api.logging.LogVerbose("Deleting inference backend with key "..inspect(key))
        api.factory.inference.delete(instance, key)
    end
end

CurrentlyLoadedDetectorPluginKey = nil

---create detector backend
---@param instance rt_instance
---@return inferencemanaged
function createDetectorBasedOnModality(instance)
    local detectorKey = getDetectorKeyBasedOnModality(instance)
    local detectInst = api.factory.inference.get(instance, detectorKey)

    if detectInst == nil then
        detectInst = api.factory.inference.create(instance, detectorKey)
    end

    CurrentlyLoadedDetectorPluginKey = detectorKey

    detectInst:loadModelFromConfig()

    return detectInst
end

---Checks if track with id exists
---@param tracks Track[]
---@param trackId string
---@return boolean
function DoesTrackExist(tracks,trackId)
    for _, track in ipairs(tracks) do
        if track.id == trackId then
            return true
        end
    end

    return false
end

---Checks if motion should be deactivate based on the number of tracks
---@param instance rt_instance
---@param trackerInst trackermanaged
---@return boolean
function ShouldDeactivateMotion(instance,trackerInst)

    local maxNumTracks = instance:getConfigValue("Global/max_num_tracks_to_deactive_motion")
    local trackIds = trackerInst:getTrackIds()

    if #trackIds > maxNumTracks then
        return true
    else
        return false
    end
end

IsMotionActivate = true
MotionLastDeactivationTimestamp = nil

---Deactivates motion
---@param currentTimeSec number
function DeactivateMotion(currentTimeSec)
    api.logging.LogWarning("Deactivating motion due to too many tracks")
    IsMotionActivate = false
    MotionLastDeactivationTimestamp = currentTimeSec
end


function ActivateMotion()
    api.logging.LogInfo("Activating motion")
    IsMotionActivate = true
end

function IsMotionActive()
    return IsMotionActivate
end

---Checks if motion should be re-activated based on time elapsed since last deactivation
---@param instance rt_instance
---@param currentTimeSec number
function ShouldReactivateMotion(instance,currentTimeSec)
    local motionReactivationDelaySec = instance:getConfigValue("Global/motion_reactivation_delay_sec")
    if MotionLastDeactivationTimestamp ~= nil and (currentTimeSec - MotionLastDeactivationTimestamp) > motionReactivationDelaySec then
        return true
    else
        return false
    end
end

---Sets a new inference strategy temporarily. Can be reset back to default by calling ResetGlobalInferenceStrategy
---@param instance rt_instance
---@param inferenceStrategy string
function SetTemporaryGlobalInferenceStrategy(instance,inferenceStrategy)

    local originalInferenceStrategy = instance:getConfigValue("Global/Detection/inference_strategy")
    instance:setConfigValue("Global/Detection/original_inference_strategy",originalInferenceStrategy)
    instance:setConfigValue("Global/Detection/inference_strategy",inferenceStrategy)
end

---Resets the inference strategy for triggers to the original value
---@param instance rt_instance
function ResetGlobalInferenceStrategy(instance)

    instance:setConfigValue("Global/Detection/inference_strategy",instance:getConfigValue("Global/Detection/original_inference_strategy"))

end

---Checks if motion is required (any trigger with with detect unknowns, or classification is enabled)
---@param instance rt_instance
---@param zoneInst zonemanaged
---@param tripwireInst tripwiremanaged
function IsTrackingMotionRequired(instance,zoneInst,tripwireInst)

    local classificationSettings = instance:getConfigValue("Global/Classification")

    if classificationSettings.enabled == true then
        return true
    end

    local detectionSettings = instance:getConfigValue("Global/Detection")
    if detectionSettings.enabled == true then
        if detectionSettings.inference_strategy == InferenceStrategy.MotionGuided then
            return true
        end
    end

    -- Check if there is any zone that is expecting unknown objects
    local zoneIds = zoneInst:getZoneIds()
    for _,zoneId in pairs(zoneIds) do
        local zoneConfig = instance:getConfigValue("Zone/Zones/"..zoneId)
        if zoneConfig.detect_unknowns == true then
            return true
        end
    end

    local tripwireIds = tripwireInst:getTripwireIds()
    for _,tripwireId in pairs(tripwireIds) do
        local tripwireConfig = instance:getConfigValue("Tripwire/Tripwires/" .. tripwireId)
        if tripwireConfig.detect_unknowns == true then
            return true
        end
    end

    return false
end

---Reload detector if needed
---@param instance rt_instance
---@param detectInst inferencemanaged
---@param isDetectionEnabled boolean
function ReloadDetectorIfNeeded(instance,detectInst,isDetectionEnabled)
    if instance:getConfigValue("Global/reload_detector_required") == true and detectInst ~= nil then
        UpdateDetectorPreset(instance)
        api.logging.LogInfo("Reloading detector backend")
        detectInst = nil
        deleteInferenceBackend(instance,CurrentlyLoadedDetectorPluginKey)
        instance:setConfigValue("Global/reload_detector_required",nil)
    end

    if isDetectionEnabled and detectInst == nil then
        return createDetectorBasedOnModality(instance)
    end

    return detectInst
end


---Update settings for triggers to ensure they show up correctly in the UI
---@param zoneInst zonemanaged
function UpdateTriggersUISettings(zoneInst)

    local zoneIds = zoneInst:getZoneIds()
    for _,zoneId in pairs(zoneIds) do

        local triggerWhen = zoneInst:getZoneValue(zoneId,"trigger_when",ZoneDictType.Config)
        local labelFormat = zoneInst:getZoneValue(zoneId,"label_format",ZoneDictType.Config)

        -- Object left/removed zones should not show up the object counter
        if (triggerWhen == "object_left" or triggerWhen == "object_removed") and labelFormat ~= "None" then
            zoneInst:setZoneValue(zoneId,"label_format","None",ZoneDictType.State)
        end
    end
end

---Retrieves detector regions defined by the user
---@param instance rt_instance
---@param inputimg buffer
---@return table
function GetUserDefinedDetectorRegions(instance,inputimg)

    if IsDetectionEnabled(instance) == false then
        return {}
    end

    local userDefinedDetectorRegions = instance:getInputShapes("DetectorRegions")

    for _, region in ipairs(userDefinedDetectorRegions) do
        region.source = inputimg
    end

    return userDefinedDetectorRegions
end

---Update track classes based on the results of the object classifier
---@param instance rt_instance
---@param tracks Track[]
---@param classifierInst inferencemanaged
---@param inputimg buffer
---@param currentTimeSec number
---@param isClassificationEnabled boolean
function UpdateTrackClassesBasedOnClassification(instance,tracks,classifierInst,inputimg,currentTimeSec,isClassificationEnabled)

    local classificationBoxes = {}
    local classificationSettings = instance:getConfigValue("Global/Classification")

    if isClassificationEnabled ~= true then
        goto ret
    end

    local classificationJobs = {}

    for _, track in pairs(tracks) do


        local isTrackLocked = IsTrackLocked(track)

        if classificationSettings.require_locked_track == true and isTrackLocked == false then
            goto continue
        end

        local isTrackMoving = IsTrackMoving(track)

        if classificationSettings.require_moving_track == true and isTrackMoving == false then
            goto continue
        end

        local isTrackAlreadyClassified = TrackMeta.getValue(track.id,TrackMetaKeys.ClassificationLock) == true

        if isTrackAlreadyClassified and classificationSettings.periodic_reclassification ~= true then
            goto continue
        end

        local lastClassificationTime = TrackMeta.getValue(track.id,TrackMetaKeys.LastClassificationLockTimeSec)
        
        if lastClassificationTime ~= nil then
            local timeSinceLastClassification = currentTimeSec - lastClassificationTime
            if isTrackAlreadyClassified and classificationSettings.periodic_reclassification == true and timeSinceLastClassification < classificationSettings.periodic_reclassification_time_sec then
                goto continue
            end
        end


        local trackBbox = CopyRect(track.bbox)
        trackBbox.trackId = track.id

        table.insert(classificationJobs,trackBbox)

        ::continue::
    end

    if #classificationJobs > 0 then
        local classificationResults = classifierInst:runInference(classificationJobs,inputimg)

        for idx, classificationResult in ipairs(classificationResults) do
            local classificationLabel = classificationResult.label
            local trackId = classificationJobs[idx].trackId
            local minHitsForLock = classificationSettings.min_hits_for_lock


            local lastClassificationLabel = TrackMeta.getValue(trackId,TrackMetaKeys.LastClassificationLabel)
            if lastClassificationLabel ~= classificationLabel then
                TrackMeta.setValue(trackId,TrackMetaKeys.ClassificationHits,0)
            end
            TrackMeta.setValue(trackId,TrackMetaKeys.LastClassificationLabel,classificationLabel)
            local currentHits = TrackMeta.getValue(trackId,TrackMetaKeys.ClassificationHits)
            local newHits = currentHits + 1
            TrackMeta.setValue(trackId,TrackMetaKeys.ClassificationHits,newHits)

            if newHits >= minHitsForLock then

                if classificationLabel == ClassLabels.Background then
                    TrackMeta.setValue(trackId,TrackMetaKeys.OverrideClassificationLabel,ClassLabels.Unknown)
                else
                    TrackMeta.setValue(trackId,TrackMetaKeys.OverrideClassificationLabel,classificationLabel)
                end

                TrackMeta.setValue(trackId,TrackMetaKeys.ClassificationLock,true)
                TrackMeta.setValue(trackId,TrackMetaKeys.ClassificationHits,0)
                TrackMeta.setValue(trackId,TrackMetaKeys.LastClassificationLockTimeSec,currentTimeSec)

            end

        end
    end

    ::ret::

end


---create classifier backend
---@param instance rt_instance
---@return inferencemanaged
function createClassifierBasedOnModality(instance)
    local pluginKey = getClassifierKeyBasedOnModality(instance)
    local inferenceInst = api.factory.inference.get(instance, pluginKey)

    if inferenceInst == nil then
        inferenceInst = api.factory.inference.create(instance, pluginKey)
        inferenceInst:loadModelFromConfig()
    end

    return inferenceInst
end


---get detector key based on modality
---@param instance rt_instance
---@return string
function getClassifierKeyBasedOnModality(instance)
    local modality = instance:getConfigValue("Global/modality")
    local pluginKey = nil

    if modality == Modality.Thermal then
        pluginKey = PluginKeys.ClassifierThermal
    elseif modality == Modality.RGB then
        pluginKey = PluginKeys.ClassifierRGB
    else
        api.logging.LogError("Unknown modality: " .. inspect(modality)..", Please set Global/modality to either rgb or thermal")
        instance:setPause(true)
        return ""
    end

    return pluginKey
end


---Reload classifier if needed
---@param instance rt_instance
---@param classifierInst inferencemanaged
---@param isClassificationEnabled boolean
---@return inferencemanaged
function ReloadClassifierIfNeeded(instance,classifierInst,isClassificationEnabled)
    if instance:getConfigValue("Global/reload_classifier_required") == true then
        api.logging.LogInfo("Reloading classifier backend")
        classifierInst:loadModelFromConfig()
        instance:setConfigValue("Global/reload_classifier_required",nil)
    end

    if isClassificationEnabled and classifierInst == nil then
        return createClassifierBasedOnModality(instance)
    end

    return classifierInst
end


---Update 3d bounding boxes for tracks.
---@param instance rt_instance
---@param tracks Track[]
---@param boundingBox3dRegressorInst inferencemanaged
---@param inputimg buffer
---@param is3dbboxEnabled boolean
function UpdateTrack3dBoundingBoxes(instance,tracks,boundingBox3dRegressorInst,inputimg,is3dbboxEnabled)

    local boundingBox3dSettings = instance:getConfigValue("Global/Bbox3d")

    if is3dbboxEnabled ~= true then
        goto ret
    end

    local inferenceJobs = {}
    for _, track in pairs(tracks) do

        local is_people = IsTrackPerson(track)
        local is_animal = IsTrackAnimal(track)
        local is_vehicle = IsTrackVehicle(track)

        if (boundingBox3dSettings.run_on_people == true and is_people == true) or (boundingBox3dSettings.run_on_vehicles == true and is_vehicle == true) or (boundingBox3dSettings.run_on_animals == true and is_animal == true) then

            local trackBbox = CopyRect(track.bbox)
            trackBbox.trackId = track.id

            table.insert(inferenceJobs,trackBbox)
        end

    end

    if #inferenceJobs > 0 then

        BBox3d.ConvertToBBox3dData = BBox3d.Convert4PointsToBBox3dData
        local classificationResults = boundingBox3dRegressorInst:runInference(inferenceJobs,inputimg)

        for idx, box3d in ipairs(classificationResults) do
            local trackId = inferenceJobs[idx].trackId
            local bboxData = BBox3d.ConvertToBBox3dData(box3d.feat, box3d.job.width, box3d.job.height)
            local screenSpacePointsData = BBox3d.ConvertBBox3dDataToScreenSpace(bboxData, box3d.job, true)
            TrackMeta.setValue(trackId,TrackMetaKeys.BBox3d,screenSpacePointsData)
        end
    end
    ::ret::

end

---Get 3d bounding boxes from tracker
---@param tracks Track[]
function Get3DBoundingBoxesFromTracks(tracks)
    local tracks3DBoundingBoxes = {}

    for _, track in pairs(tracks) do
        local boundingBox3D = TrackMeta.getValue(track.id,TrackMetaKeys.BBox3d)
        if boundingBox3D ~= nil and next(boundingBox3D) ~= nil then
            table.insert(tracks3DBoundingBoxes, boundingBox3D)
        end
    end

    return tracks3DBoundingBoxes


end

---Calculates and returns stats of all zones
---@param zoneInst zonemanaged
---@param inputImage buffer
---@return ZoneStats
function GetZoneStats(zoneInst, inputImage)

    local numOccupiedZones = 0
    local numVacantZones = 0


    --iterate over all zones
    local zoneIds = zoneInst:getZoneIds()
    for _, zoneId in pairs(zoneIds) do
        local curEntries = zoneInst:getZoneValue(zoneId,"cur_entries",ZoneDictType.State)
        if curEntries ~= nil and curEntries > 0 then
            numOccupiedZones = numOccupiedZones + 1
        else
            numVacantZones = numVacantZones + 1
        end
    end


    local occupancyRate = 0.0
    if numOccupiedZones + numVacantZones > 0 then
        occupancyRate = numOccupiedZones/(numOccupiedZones+numVacantZones)
    end

    ---@type ZoneStats
    local zoneStats = {occupancyRate = occupancyRate, numOccupiedZones = numOccupiedZones, numVacantZones = numVacantZones}

    return {
        image = inputImage,
        data = zoneStats
    }
end


---Iterate through all tracks and update their locking status. Use IsTrackLocked to check if a given track is locked
---@param tracks Track[]
---@param trackerInst trackermanaged
---@param currentTimeSec number
function UpdateTracksLocking(tracks,trackerInst, currentTimeSec)

    local trackerLockingSettings = trackerInst:getConfig()["Locking"]

    local matchRatioThreshold = trackerLockingSettings.match_ratio_threshold
    local timeWindowDurationSec = trackerLockingSettings.time_window_duration_sec

    local mathedTracksInfo = trackerInst:getMatchedTracks()

    function hasTrackBeenMatched(trackId)
        for _, trackInfo in ipairs(mathedTracksInfo) do
            if trackInfo[1] == trackId then
                return true
            end
        end

        return false
    end


    for _, track in ipairs(tracks) do

        local trackId = track.id

        local trackBornTimeSec = TrackMeta.getValue(trackId,TrackMetaKeys.BornTimeSec)
        if trackBornTimeSec == nil then
            trackBornTimeSec = currentTimeSec
            TrackMeta.setValue(trackId,TrackMetaKeys.BornTimeSec,currentTimeSec)
        end

        local trackAgeSec = currentTimeSec - trackBornTimeSec
        TrackMeta.setValue(trackId,TrackMetaKeys.Age,trackAgeSec)

        -- Skip track if already lock
        if IsTrackLocked(track) then
            goto continue
        end

        local trackMatchHistory = TrackMeta.getValue(trackId,TrackMetaKeys.LockMatchHistory) or {}

        -- Discard old entries
        for idx, trackMatchHistoryEntry in ipairs(trackMatchHistory) do
            local entryTimestamp = trackMatchHistoryEntry.timestamp
            if currentTimeSec - entryTimestamp > timeWindowDurationSec then
                table.remove(trackMatchHistory,idx)
            end
        end

        local trackMatchedThisFrame = hasTrackBeenMatched(track.sourceTrackerTrackId)
        -- Add new entry
        local trackMatchHistoryEntry = {matched = trackMatchedThisFrame, timestamp = currentTimeSec}
        table.insert(trackMatchHistory,trackMatchHistoryEntry)

        --- Skip locking if track is too young or if it has not been matched this frame
        if trackAgeSec >= timeWindowDurationSec and trackMatchedThisFrame then


            -- Calculate match ratio
            local numMatched = 0
            local numTotal = 0
            for _, trackMatchHistoryEntry in ipairs(trackMatchHistory) do
                if trackMatchHistoryEntry.matched == true then
                    numMatched = numMatched + 1
                end
                numTotal = numTotal + 1
            end
            local matchRatio = numMatched/numTotal

            -- Update lock status
            local isLocked = matchRatio >= matchRatioThreshold
            TrackMeta.setValue(trackId,TrackMetaKeys.IsLocked,isLocked)
            trackerInst:saveTrackValue(track.sourceTrackerTrackId,"tracking_lock",isLocked)
        end

        TrackMeta.setValue(trackId,TrackMetaKeys.LockMatchHistory,trackMatchHistory)

        ::continue::
    end

end

---Returns lock status of a track
---@param track Track
---@return boolean
function IsTrackLocked(track)
    local isLocked = TrackMeta.getValue(track.id,TrackMetaKeys.IsLocked) == true
    return isLocked
end

---Returns true if track is of an unknown class (e.g. motion)
---@param track Track
---@return boolean
function IsTrackUnknown(track)
    return track.classLabel == ClassLabels.Unknown
end

---Returns true if its a person track
---@param track Track
---@return boolean
function IsTrackPerson(track)
    return track.classLabel == ClassLabels.Person
end

---Returns true if its a vehicle track
---@param track Track
---@return boolean
function IsTrackVehicle(track)
    return track.classLabel == ClassLabels.Vehicle
end

---Returns true if its a animal track
---@param track Track
---@return boolean
function IsTrackAnimal(track)
    return track.classLabel == ClassLabels.Animal
end


---Returns true if track is moving
---@param track Track
---@return boolean
function IsTrackMoving(track)
    local isMoving = TrackMeta.getValue(track.id,TrackMetaKeys.MovementStatus) == TrackMovementStatus.Moving
    return isMoving
end

---Returns true if track is moving
---@param track Track
---@return boolean
function IsOrWasTrackMoving(track)
    local movingStatus = TrackMeta.getValue(track.id,TrackMetaKeys.MovementStatus)
    return movingStatus == TrackMovementStatus.Moving or movingStatus == TrackMovementStatus.Stopped
end

---Returns true if track stopped moving (i.e. was already considered moving in the past but is no longer so)
---@param track Track
---@return boolean
function IsTrackStopped(track)
    local isStopped = TrackMeta.getValue(track.id,TrackMetaKeys.MovementStatus) == TrackMovementStatus.Stopped
    return isStopped
end

---Returns true if track is moving
---@param track Track
---@return boolean
function IsTrackMotion(track)
    return track.classLabel == ClassLabels.Unknown
end


---Returns true if track is moving
---@param track Track
---@return boolean
function IsTrackMatchedLastFrame(track)

    return track.lastSeen < 0.001
end

---Reload 3d bounding box inference backend if needed (i.e. not yet loaded)
---@param instance rt_instance
---@param inferenceInst inferencemanaged
---@param is3dbboxEnabled boolean
---@return inferencemanaged
function Reload3DBboxIfNeeded(instance,inferenceInst,is3dbboxEnabled)

    if is3dbboxEnabled then
        inferenceInst = api.factory.inference.get(instance, PluginKeys.Bbox3d)

        if inferenceInst == nil then
            inferenceInst = api.factory.inference.create(instance, PluginKeys.Bbox3d)
            inferenceInst:loadModelFromConfig()
        end
    end

    return inferenceInst
end

---
---@param instance rt_instance
---@return boolean
function IsDetectionEnabled(instance)
    return instance:getConfigValue("Global/Detection/enabled")
end


--- Filters detections that are not overlaping with moving objects
---@param detections table
---@param motionRegions Rect[]
---@return table
function FilterDetectionsNotOverlappingMotionRegions(detections,motionRegions)

    local filteredDetections = {}


    for _, detection in ipairs(detections) do
        for _, motionRegion in ipairs(motionRegions) do
            if BoxContainment(detection,motionRegion) > 0.8 then
                table.insert(filteredDetections,detection)
                break
            end
        end
    end

    return filteredDetections

end

---Retrusn the inference strategy for the detector
---@param instance rt_instance
function GetDetectorInferenceStrategy(instance)
    return instance:getConfigValue("Global/Detection/inference_strategy")
end

---Calculates and returns stats of all zones
---@param tracks Track[]
---@param inputImage buffer
---@return GlobalObjectStats
function GetGlobalObjectStats(tracks, inputImage)

    local globalObjectStats = {numPeople = 0, numVehicles = 0, numAnimals = 0, numUnknown = 0}

    for _, track in ipairs(tracks) do

        if IsTrackLocked(track) then
            if IsTrackPerson(track) then
                globalObjectStats.numPeople = globalObjectStats.numPeople + 1
            elseif IsTrackVehicle(track) then
                globalObjectStats.numVehicles = globalObjectStats.numVehicles + 1
            elseif IsTrackAnimal(track) then
                globalObjectStats.numAnimals = globalObjectStats.numAnimals + 1
            elseif IsTrackUnknown(track) then
                globalObjectStats.numUnknown = globalObjectStats.numUnknown + 1
            end
        end
    end

    return {
        image = inputImage,
        data = globalObjectStats
    }
end


---Convert Packed Detections to Image Space
---@param atlasPackingInfo AtlasPackingInfo
---@param atlasDetections Detection[]
---@return Detection[]
function UnpackAtlasDetections(atlasPackingInfo, atlasDetections)


    local atlasRegions = atlasPackingInfo.atlasRegions
    local sourceRegions = atlasPackingInfo.sourceRegions

    -- Determine which atlas block does each detection belong to

    local detections = {}
    for idx, detection in ipairs(atlasDetections) do
        local atlasBlockIndex = -1

        local detectionCenterX = detection.x + detection.width/2
        local detectionCenterY = detection.y + detection.height/2

        for atlasBlockIdx, atlasLocation in ipairs(atlasRegions) do
            -- check if the center of the detection is inside the atlas block

            if detectionCenterX >= atlasLocation.x and detectionCenterX <= atlasLocation.x + atlasLocation.width and
                    detectionCenterY >= atlasLocation.y and detectionCenterY <= atlasLocation.y + atlasLocation.height then
                atlasBlockIndex = atlasBlockIdx
                break
            end
        end

        if atlasBlockIndex == -1 then

            goto continue
        end

        --Convert detection to atlas location space

        local atlasRegion = atlasRegions[atlasBlockIndex]
        local sourceRegion = sourceRegions[atlasBlockIndex]

        local detectionBoxImageSpace = ConvertAtlasBoxToImageSpace(detection,atlasRegion,sourceRegion)

        local detectionImageSpace = detectionBoxImageSpace

        detectionImageSpace.confidence = detection.confidence
        detectionImageSpace.classid = detection.classid
        detectionImageSpace.label = detection.label

        table.insert(detections,detectionImageSpace)

        ::continue::
    end

    return detections
end

---Returns true if box is at the edge of the image
---@param box Rect
---@param boundaries Rect
---@return boolean
function IsBoxAtTheEdge(box, boundaries)

    local edgeDistanceThreshold = 0.01

    local rightEdgeDistance = math.abs(boundaries.x + boundaries.width - (box.x + box.width))
    local leftEdgeDistance = math.abs(box.x - boundaries.x)
    local topEdgeDistance = math.abs(box.y - boundaries.y)
    local bottomEdgeDistance = math.abs(boundaries.y + boundaries.height - (box.y + box.height))

    if rightEdgeDistance < edgeDistanceThreshold or leftEdgeDistance < edgeDistanceThreshold or
            topEdgeDistance < edgeDistanceThreshold or bottomEdgeDistance < edgeDistanceThreshold then
        return true
    end

    return false
end

---Returns the sides of the box that are at the edge of the boundaries
---@param box Rect
---@param boundaries Rect
---@return number[] sidesAtTheEdge - 1: right, 2: left, 3: top, 4: bottom
function GetBoxSidesAtTheEdge(box,boundaries)

    local sidesAtTheEdge = {}

    local edgeDistanceThreshold = 0.01

    local rightEdgeDistance = math.abs(boundaries.x + boundaries.width - (box.x + box.width))
    local leftEdgeDistance = math.abs(box.x - boundaries.x)
    local topEdgeDistance = math.abs(box.y - boundaries.y)
    local bottomEdgeDistance = math.abs(boundaries.y + boundaries.height - (box.y + box.height))

    if rightEdgeDistance < edgeDistanceThreshold then
        table.insert(sidesAtTheEdge,1)
    end

    if leftEdgeDistance < edgeDistanceThreshold then
        table.insert(sidesAtTheEdge,2)
    end

    if topEdgeDistance < edgeDistanceThreshold then
        table.insert(sidesAtTheEdge,3)
    end

    if bottomEdgeDistance < edgeDistanceThreshold then
        table.insert(sidesAtTheEdge,4)
    end

    return sidesAtTheEdge

end

--- Convert Atlas Box to Image Space
---@param atlasBox Rect|Detection
---@param atlasRegion Rect
---@param sourceRegion Rect
---@return Rect
function ConvertAtlasBoxToImageSpace(atlasBox, atlasRegion, sourceRegion)

    local atlasSubRegionXMin = (atlasBox.x - atlasRegion.x) / atlasRegion.width
    local atlasSubRegionYMin = (atlasBox.y - atlasRegion.y) / atlasRegion.height
    local atlasSubRegionXMax = (atlasBox.x + atlasBox.width - atlasRegion.x) / atlasRegion.width
    local atlasSubRegionYMax = (atlasBox.y + atlasBox.height - atlasRegion.y) / atlasRegion.height

    local imageSpaceXMin = atlasSubRegionXMin * sourceRegion.width + sourceRegion.x
    local imageSpaceYMin = atlasSubRegionYMin * sourceRegion.height + sourceRegion.y
    local imageSpaceXMax = atlasSubRegionXMax * sourceRegion.width + sourceRegion.x
    local imageSpaceYMax = atlasSubRegionYMax * sourceRegion.height + sourceRegion.y

    local imageSpaceBox = {
        x = imageSpaceXMin,
        y = imageSpaceYMin,
        width = imageSpaceXMax - imageSpaceXMin,
        height = imageSpaceYMax - imageSpaceYMin,
    }

    return imageSpaceBox
end

--- Filter detections that are at the edge of the sub detection regions but not at the edge of the source image
---@param detections Detection[]
---@param detectionRegions Rect[]
---@param isUsingAtlasPacking boolean
---@param atlasPackingInfo AtlasPackingInfo
---@param labelRestrict table
---@return Detection[]
function FilterEdgeDetections(detections,detectionRegions, isUsingAtlasPacking, atlasPackingInfo,labelRestrict)

    local filteredDetections = {}

    local FullScreenDetectionRegion = {
        x = 0,
        y = 0,
        width = 1,
        height = 1
    }


    for _, detection in ipairs(detections) do

        if labelRestrict ~= nil and not labelRestrict[detection.label] then
            table.insert(filteredDetections,detection)
            goto continue
        end

        local isDetectionAtTheEdge = false
        if isUsingAtlasPacking then
            local sourceRegions = atlasPackingInfo.sourceRegions

            -- An atlas packed detection is only accepted if the number of box sides at the edge of the packing source regions is the same as the number of box sides at the edge of the detection regions
            local boxSidesAtTheEdgeOfTheScreen = GetBoxSidesAtTheEdge(detection,FullScreenDetectionRegion)
            for _, sourceRegion in ipairs(sourceRegions) do
                if BoxContainment(detection,sourceRegion) > 0.8 then

                    local boxSidesAtTheEdgeOfPackingRegion = GetBoxSidesAtTheEdge(detection,sourceRegion)

                    if #boxSidesAtTheEdgeOfTheScreen ~= #boxSidesAtTheEdgeOfPackingRegion then
                        isDetectionAtTheEdge = true
                        break
                    end

                    break
                end
            end
        else
            for _, detectionRegion in ipairs(detectionRegions) do
                local isFullScreenDetectionRegion = detectionRegion.x == 0 and detectionRegion.y == 0 and
                        detectionRegion.width == 1 and detectionRegion.height == 1

                if IsBoxAtTheEdge(detection,detectionRegion) then
                    if not isFullScreenDetectionRegion then
                        isDetectionAtTheEdge = true
                        break
                    else
                        isDetectionAtTheEdge = false
                    end
                end
            end
        end

        if not isDetectionAtTheEdge then
            table.insert(filteredDetections,detection)
        end

        ::continue::
    end

    return filteredDetections

end

--- Filter detections by confidence, allowing each class to have a different confidence threshold
---@param inferencePlugin inferencemanaged
---@param detections Detection[]
---@return Detection[]
function FilterDetectionsByConfidence(inferencePlugin,detections)

    local filteredDetections = {}

    local inferencePluginConfig = inferencePlugin:getConfig()

    local personConfidenceThreshold = inferencePluginConfig["person_confidence_threshold"]
    local animalConfidenceThreshold = inferencePluginConfig["animal_confidence_threshold"]
    local vehicleConfidenceThreshold = inferencePluginConfig["vehicle_confidence_threshold"]

    for _, detection in ipairs(detections) do
        if detection.label == ClassLabels.Person and detection.confidence >= personConfidenceThreshold then
            table.insert(filteredDetections,detection)
        elseif detection.label == ClassLabels.Animal and detection.confidence >= animalConfidenceThreshold then
            table.insert(filteredDetections,detection)
        elseif detection.label == ClassLabels.Vehicle and detection.confidence >= vehicleConfidenceThreshold then
            table.insert(filteredDetections,detection)
        end
    end

    return filteredDetections

end

--- Checks if events generated by a given track should be considered. This is used to discard events of tracks with unknown class when there is a known class track inside the region.
---@param track Track
---@param tracks Track[]
---@return boolean
function ShouldConsiderEventsGeneratedByTrack(track, tracks)


    if IsTrackUnknown(track) then
        local sourceTrackBbox = track.bbox
        for _, track in ipairs(tracks) do
            if IsTrackAnimal(track) or IsTrackPerson(track) or IsTrackVehicle(track) then
                if BoxContainment(track.bbox,sourceTrackBbox) > 0.8 then
                    return false
                end
            end
        end
    end

    return true

end


---Copy Rect
---@param rect Rect
---@return Rect
function CopyRect(rect)
    return {
        x = rect.x,
        y = rect.y,
        width = rect.width,
        height = rect.height
    }
end


function sigmoid(input)
    local output = {}
    for i=1, #input do
        output[i] = 1 / (1 + math.exp(-input[i]))
    end
    return output
end

function get_current_date_RFC_3339()
    local date_table = os.date("!*t") -- Get UTC time
    local year = string.format("%04d", date_table.year)
    local month = string.format("%02d", date_table.month)
    local day = string.format("%02d", date_table.day)
    local hour = string.format("%02d", date_table.hour)
    local minute = string.format("%02d", date_table.min)
    local second = string.format("%02d", date_table.sec)
    return year .. "-" .. month .. "-" .. day .. "T" .. hour .. ":" .. minute .. ":" .. second .. "Z"
end

CurrentDetectorPreset = nil

---Update Movement Preset Settings
---@param instance rt_instance
function UpdateDetectorPreset(instance)

    local detectorKey = getDetectorKeyBasedOnModality(instance)
    local storedPreset = instance:getConfigValue(detectorKey.."/current_preset")

    if storedPreset ~= CurrentDetectorPreset then

        CurrentDetectorPreset = storedPreset

        api.logging.LogVerbose("["..detectorKey.."] Updating detector preset to "..storedPreset)

        local settingsToUse = instance:getConfigValue(detectorKey.."/preset_values/" .. storedPreset)

        api.logging.LogVerbose("["..detectorKey.."] "..inspect(settingsToUse))

        --Apply settings
        for key, value in pairs(settingsToUse) do
            api.logging.LogVerbose("["..detectorKey.."] instance:setConfigValue(\""..key.."\","..inspect(value)..")")
            instance:setConfigValue(key,value)
        end
    end
end

CurrentDetectorSensitivityPreset = nil
---Update Movement Preset Settings
---@param instance rt_instance
function UpdateDetectorSensitivityPreset(instance)

    local storedPreset = instance:getConfigValue("Detector/current_sensitivity_preset")

    if storedPreset ~= CurrentDetectorSensitivityPreset then

        CurrentDetectorSensitivityPreset = storedPreset

        api.logging.LogVerbose("[Detector] Updating detector sensitivity preset to "..storedPreset)

        local settingsToUse = instance:getConfigValue("Detector/sensitivity_preset_values/" .. storedPreset)

        api.logging.LogVerbose("[Detector] "..inspect(settingsToUse))

        --Apply settings
        for key, value in pairs(settingsToUse) do
            api.logging.LogVerbose("[Detector] instance:setConfigValue(\""..key.."\","..value..")")
            instance:setConfigValue(key,value)
        end
    end
end

CurrentMovementSensitivityPreset = nil
---Update Movement Preset Settings
---@param instance rt_instance
function UpdateMovementSensitivityPreset(instance)

    local storedPreset = instance:getConfigValue("Movement/current_sensitivity_preset")

    if storedPreset ~= CurrentMovementSensitivityPreset then

        CurrentMovementSensitivityPreset = storedPreset

        api.logging.LogVerbose("[Movement] Updating sensitivity preset to "..storedPreset)

        local settingsToUse = instance:getConfigValue("Movement/sensitivity_preset_values/" .. storedPreset)

        api.logging.LogVerbose("[Movement] "..inspect(settingsToUse))

        --Apply settings
        for key, value in pairs(settingsToUse) do
            api.logging.LogVerbose("[Movement] instance:setConfigValue(\""..key.."\","..value..")")
            instance:setConfigValue(key,value)
        end
    end
end


---Get Tracks From Plugin
---@param trackerInst trackermanaged
---@param classLabel string @The label of the tracks to get. Can be "unknown", "person", "animal", "vehicle"
---@return Track[]
function GetTracksFromTracker(trackerInst, classLabel)

    local pluginName = trackerInst:getName()
    local trackIds = trackerInst:getTrackIds()

    ---@type Track[]
    local tracks = {}

    for _, trackId in ipairs(trackIds) do
        local bbox = trackerInst:getTrackValue(trackId,"bbox")
        local confidence = trackerInst:getTrackValue(trackId,"confidence")
        local lastSeen = trackerInst:getTrackValue(trackId,"last_seen")
        local movementDirectionTuple = trackerInst:getTrackValue(trackId,"movement_direction")
        local movementDirectionVec = {x = movementDirectionTuple[1], y = movementDirectionTuple[2]}
        local externalId = trackerInst:getTrackValue(trackId,"external_id")
        local trackAge = trackerInst:getTrackValue(trackId,"track_age")
        local bestThumbnail = trackerInst:getTrackValue(trackId,"best_thumbnail")
        local id = pluginName .. "_" .. trackId

        TrackMeta.setValue(id,TrackMetaKeys.ExternalId,externalId)
        TrackMeta.setValue(id,TrackMetaKeys.SourceTracker,trackerInst)
        
        local overrideClassLabel = TrackMeta.getValue(id,TrackMetaKeys.OverrideClassificationLabel)

        -- mark this track as alive
        TrackMeta.setValue(id,TrackMetaKeys.IsAlive,true)

        if overrideClassLabel ~= nil then
            classLabel = overrideClassLabel
        end

        ---@type Track
        local track = {bbox = bbox, classLabel = classLabel, id = id, trackAge = trackAge, lastSeen = lastSeen, originalTrackId = trackId, sourceTrackerTrackId = trackId, movementDirection = movementDirectionVec, externalId = externalId, bestThumbnail = bestThumbnail}

        table.insert(tracks,track)
    end

    return tracks
end

--- Filter detections by label
---@param detections Detection[]
---@param label string
---@return Detection[]
function FilterDetectionsByLabel(detections, label)
    local filteredDetections = {}
    for _, detection in ipairs(detections) do
        if detection.label == label then
            table.insert(filteredDetections, detection)
        end
    end
    return filteredDetections
end

--- Get track by id from list
---@param tracks Track[]
---@param id string
---@return Track
function GetTrackById(tracks, id)
    for _, track in ipairs(tracks) do
        if track.id == id then
            return track
        end
    end
    return nil
end

--- Filter overlapping detections (i.e detections that are fully contained within another detection). This can be useful for texture packed inference
---@param detections Detection[]
---@param labelRestrict table
---@return Detection[]
function FilterOverlappingDetections(detections,labelRestrict)

    local filteredDetections = {}

    for _, detection in ipairs(detections) do

        if labelRestrict ~= nil and not labelRestrict[detection.label] then
            table.insert(filteredDetections,detection)
            goto continue
        end

        local isDetectionOverlapping = false
        for _, detection2 in ipairs(detections) do
            if detection ~= detection2 and detection.label == detection2.label then
                if BoxContainment(detection,detection2) > 0.8 then
                    isDetectionOverlapping = true
                    break
                end
            end
        end

        if not isDetectionOverlapping then
            table.insert(filteredDetections,detection)
        end

        ::continue::
    end

    return filteredDetections
end

function FetchAtlasBlockForTracks(atlasPackingInfo, tracks)

    local atlasRegions = atlasPackingInfo.atlasRegions
    local sourceRegions = atlasPackingInfo.sourceRegions

    -- Determine which atlas block does each detection belong to

    local detections = {}
    for idx, detection in ipairs(tracks) do
        local atlasBlockIndex = -1

        local detectionCenterX = detection.bbox.x + detection.bbox.width/2
        local detectionCenterY = detection.bbox.y + detection.bbox.height/2

        for atlasBlockIdx, atlasLocation in ipairs(sourceRegions) do
            -- check if the center of the detection is inside the atlas block

            if detectionCenterX >= atlasLocation.x and detectionCenterX <= atlasLocation.x + atlasLocation.width and
                    detectionCenterY >= atlasLocation.y and detectionCenterY <= atlasLocation.y + atlasLocation.height then
                atlasBlockIndex = atlasBlockIdx
                break
            end
        end

        if atlasBlockIndex == -1 then

            goto continue
        end

        --Convert detection to atlas location space

        if #sourceRegions ~= #atlasRegions then
            goto continue
        end

        local atlasRegion = atlasRegions[atlasBlockIndex]

        image = atlasPackingInfo.atlas:copy(atlasRegion.x, atlasRegion.y, atlasRegion.width, atlasRegion.height, true)

        tracks[idx].atlas_crop = image
        tracks[idx].atlas = atlasPackingInfo.atlas

        ::continue::
    end

    return tracks
end

--- Checks if any zone or tripwire requires vehicles
---@param instance rt_instance
---@param zoneInst zonemanaged
---@param tripwireInst tripwiremanaged
---@param isClassificationEnabled boolean
---@return ClassRequirements
function CheckClassesRequiredFromTripwiresAndZones(instance,zoneInst,tripwireInst,isClassificationEnabled)

    ---@class ClassRequirements
    local classRequirements = {vehicles = false, people = false, animals = false, unknowns = false}

    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in ipairs(zoneIds) do

        classRequirements.unknowns = classRequirements.unknowns or (zoneInst:getZoneValue(zoneId,"detect_unknowns",ZoneDictType.Config) == true)
        classRequirements.vehicles = classRequirements.vehicles or (zoneInst:getZoneValue(zoneId,"detect_vehicles",ZoneDictType.Config) == true)
        classRequirements.people = classRequirements.people or (zoneInst:getZoneValue(zoneId,"detect_people",ZoneDictType.Config) == true)
        classRequirements.animals = classRequirements.animals or (zoneInst:getZoneValue(zoneId,"detect_animals",ZoneDictType.Config) == true)
    end

    local tripwireIds = tripwireInst:getTripwireIds()

    for _, tripwireId in ipairs(tripwireIds) do
        classRequirements.unknowns = classRequirements.unknowns or (GetTripwireConfigValue(instance,tripwireId,"detect_unknowns") == true)
        classRequirements.vehicles = classRequirements.vehicles or (GetTripwireConfigValue(instance,tripwireId,"detect_vehicles") == true)
        classRequirements.people = classRequirements.people or (GetTripwireConfigValue(instance,tripwireId,"detect_people") == true)
        classRequirements.animals = classRequirements.animals or (GetTripwireConfigValue(instance,tripwireId,"detect_animals") == true)
    end

    if isClassificationEnabled then
        classRequirements.unknowns = true
    end

    return classRequirements
end

--- Filters a list of tentative events by returning the ones that should be published. In addition, this function also returns the tentative events that should be kept for future processing.
---@param tentativeEvents Event[]
---@param zoneInst zonemanaged
---@param tripwireInst tripwiremanaged
---@param currentTimeSec number
---@param allTracks Track[]
---@param lastFrameTracks Track[]
---@return Event[], Event[]
function ProcessTentativeEvents(tentativeEvents, zoneInst, tripwireInst, currentTimeSec,allTracks,lastFrameTracks)

    local confirmedEvents = {}
    local updatedTentativeEvents = {}

    for _, event in ipairs(tentativeEvents) do

        local eventType = event.type

        if (eventType == EventTypes.ObjectLeft or eventType == EventTypes.ObjectRemoved) then
            table.insert(confirmedEvents,event)
            goto continue
        end


        local zoneId = event.zone_id

        if zoneId ~= nil then
           
            local triggerOnEnter = zoneInst:getZoneValue(event.zone_id,"trigger_on_enter",ZoneDictType.Config)
            local triggerOnIntrusion = zoneInst:getZoneValue(event.zone_id,"trigger_on_intrusion",ZoneDictType.Config)

            -- If the event signals the end of an intrusion/enter/loitering AND the zone is configured to trigger on enter, we need to have a confirmed intrusion/enter/loitering start prior to this event
            if ((triggerOnEnter and eventType == EventTypes.AreaExit) or (triggerOnIntrusion and eventType == EventTypes.IntrusionEnd)) or eventType == EventTypes.LoiteringEnd then
                
                local zoneId = event.zone_id
                local trackIdLeft = event.extra.track_id_left
                local confirmationMapKey = nil

                if eventType == EventTypes.AreaExit then
                    confirmationMapKey = ZoneStateFieldPaths.ConfirmedEnters
                elseif eventType == EventTypes.IntrusionEnd then
                    confirmationMapKey = ZoneStateFieldPaths.ConfirmedIntrusions
                elseif eventType == EventTypes.LoiteringEnd then
                    confirmationMapKey = ZoneStateFieldPaths.ConfirmedLoiterings
                end

                local matchingStartEventData = zoneInst:getZoneValue(zoneId,confirmationMapKey.."/"..trackIdLeft,ZoneDictType.State)

                if matchingStartEventData == nil then

                    --- Ignore event
                    goto continue
                else
                    --- If we have an event that signals the end of an intrusion/enter/loitering, we need to remove the corresponding entry from the confirmation map
                    zoneInst:setZoneValue(zoneId,confirmationMapKey.."/"..trackIdLeft,nil,ZoneDictType.State)
                end
            end


            if event.extra.track_id_left ~= nil then
                local currentBbox = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInsideLastKnownInfo.."/"..event.extra.track_id_left.."/bbox",ZoneDictType.State)
                event.extra.bbox = currentBbox    

                local objectClass = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInsideLastKnownInfo.."/"..event.extra.track_id_left.."/class",ZoneDictType.State)
                event.extra.class = objectClass

                -- Set the field to nil to avoid memory leaking            
                zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInsideLastKnownInfo.."/"..event.extra.track_id_left,nil,ZoneDictType.State)
            end


        end

        
        -- If any of the event tracks no longer exist, remove this event (i.e. dont add it to the updated list of tentative events)
        local eventTracks = event.tracks

        for _, track in ipairs(eventTracks) do

            if DoesTrackExist(allTracks,track.id) ~= true then
                goto continue
            end
        end

        -- Add a tentative flag to the tracks and enable thumbnail creation
        for _, track in ipairs(eventTracks) do
            TrackMeta.setValue(track.id,TrackMetaKeys.HasTentativeEvent,true)

            -- Enable thumbnail generation
            ---@type trackermanaged
            local sourceTracker = TrackMeta.getValue(track.id,TrackMetaKeys.SourceTracker)

            sourceTracker:saveTrackValue(track.sourceTrackerTrackId,"enable_thumbnail",true)
        end

        local zoneId = event.zone_id
        local tripwireId = event.tripwire_id
        
        if zoneId == nil and tripwireId == nil then
            api.logging.LogError("GetConfirmedEvents: event has no zone or tripwire id")
            local instance = api.thread.getCurrentInstance()
            instance:stop()
            return {}, {}
        end

        local eventTracks = event.tracks
        local shouldConfirmEvent = true

        for _, track in ipairs(eventTracks) do
            shouldConfirmEvent = ShouldConfirmEventForTrackOnZoneOrTripwire(track,zoneInst,zoneId,tripwireInst,tripwireId) 

            if shouldConfirmEvent == false then
                break
            end
        end


        if shouldConfirmEvent == true then

            -- Since we have confirmed this event, we need to update the track' meta to include this new event
            for _, track in ipairs(eventTracks) do
                local trackEvents = TrackMeta.getValue(track.id,TrackMetaKeys.Events)
                trackEvents = trackEvents or {}
                table.insert(trackEvents,event)
                TrackMeta.setValue(track.id,TrackMetaKeys.Events,trackEvents)
            end

            -- If we are dealing with area enter or intrusion events, we need to keep track of which tracks have been confirmed in the zone
            if eventType == EventTypes.IntrusionStart or eventType == EventTypes.AreaEnter or eventType == EventTypes.LoiteringStart then
                local zoneId = event.zone_id

                local confirmationMapKey = nil

                if eventType == EventTypes.AreaEnter then
                    confirmationMapKey = ZoneStateFieldPaths.ConfirmedEnters
                elseif eventType == EventTypes.IntrusionStart then
                    confirmationMapKey = ZoneStateFieldPaths.ConfirmedIntrusions
                elseif eventType == EventTypes.LoiteringStart then
                    confirmationMapKey = ZoneStateFieldPaths.ConfirmedLoiterings
                end

                for _, track in ipairs(eventTracks) do
                    local trackConfirmationValue = zoneInst:getZoneValue(zoneId,confirmationMapKey.."/"..track.id,ZoneDictType.State)
                    if trackConfirmationValue ~= nil then
                        api.logging.LogError("Track entered area twice "..inspect(track.id))
                    end
                    local eventRelevantData = {id = event.id, frame_time = event.frame_time, extra = event.extra}
                    zoneInst:setZoneValue(zoneId,confirmationMapKey.."/"..track.id,eventRelevantData,ZoneDictType.State)
                end
            end

            --Convert event tracks to snake_case

            event.tracks = ConvertTracksToSnakeCase(event.tracks)

            table.insert(confirmedEvents,event)
        else
            table.insert(updatedTentativeEvents,event)
        end

        ::continue::
    end

    -- Process confirmed events
    for _, event in ipairs(confirmedEvents) do
        ProcessConfirmedEvent(event,zoneInst,tripwireInst,allTracks,lastFrameTracks)
    end

    return confirmedEvents,updatedTentativeEvents
end

---Checks if a track is relevant to a given zone. This only checks for class compatibility
---@param track Track
---@param zoneId string
---@param zoneInst zonemanaged
---@return boolean
function IsTrackRelevantForZone(track,zoneInst,zoneId)

    if IsTrackPerson(track) then
        return zoneInst:getZoneValue(zoneId,"detect_people",ZoneDictType.Config) == true
    elseif IsTrackVehicle(track)then
        return zoneInst:getZoneValue(zoneId,"detect_vehicles",ZoneDictType.Config) == true
    elseif IsTrackAnimal(track) then
        return zoneInst:getZoneValue(zoneId,"detect_animals",ZoneDictType.Config) == true
    elseif IsTrackUnknown(track) then
        return zoneInst:getZoneValue(zoneId,"detect_unknowns",ZoneDictType.Config) == true
    end

    return false
end

---Checks if a track is relevant to a given tripwire. This only checks for class compatibility
---@param track Track
---@param tripwireInst tripwiremanaged
---@param tripwireId string
---@return boolean
function IsTrackRelevantForTripwire(track,tripwireInst,tripwireId)

    if IsTrackPerson(track) then
        return tripwireInst:getTripwireValue(tripwireId,"detect_people",ZoneDictType.Config) == true
    elseif IsTrackVehicle(track)then
        return tripwireInst:getTripwireValue(tripwireId,"detect_vehicles",ZoneDictType.Config) == true
    elseif IsTrackAnimal(track) then
        return tripwireInst:getTripwireValue(tripwireId,"detect_animals",ZoneDictType.Config) == true
    elseif IsTrackUnknown(track) then
        return tripwireInst:getTripwireValue(tripwireId,"detect_unknowns",ZoneDictType.Config) == true
    end

    return false
end


--- Get tripwire config value
---@param instance rt_instance
---@param tripwireId string
---@param configKey string
---@return any
function GetTripwireConfigValue(instance,tripwireId,configKey)
    return instance:getConfigValue("Tripwire/Tripwires/" .. tripwireId .. "/" .. configKey)
end


--- Get zone config value
---@param instance rt_instance
---@param zoneId string
---@return any
function GetZoneConfig(instance,zoneId)
    return instance:getConfigValue("Zone/Zones/" .. zoneId)
end

--- Get tripwire config
---@param instance rt_instance
---@param tripwireId string
---@return any
function GetTripwireConfig(instance,tripwireId)
    return instance:getConfigValue("Tripwire/Tripwires/" .. tripwireId)
end

--- Get frame metadata
---@param instance rt_instance
---@param inputimg buffer
function GetFrameMetadata(instance,inputimg)
    return {
        date = os.date("%c"),
        frame_time = inputimg:getTimestamp(),
        frame_id = inputimg:getFrameId(),
        instance_id = instance:getName(),
        system_date = get_current_date_RFC_3339()
    }
end

function IsTrackAlive(track)
    return TrackMeta.getValue(track.id,TrackMetaKeys.IsAlive) == true
end


--- Determines if vehicle detections should be considered for texture packing
--- Returns true if there is any zone configured to trigger on vehicle loitering or if set to true in the config
---@param instance rt_instance
---@param zoneInst zonemanaged
---@return boolean
function ShouldConsiderVehicleDetectionsForTexturePacking(instance, zoneInst)

    if AnyVehicleLoiteringZone(zoneInst) then
        return true
    end

    return instance:getConfigValue("Global/Detection/texture_packing/consider_vehicles") == true
end


--- Returns true if there is any zone configured to trigger on vehicle loitering
---@param zoneInst zonemanaged
---@return boolean
function AnyVehicleLoiteringZone(zoneInst)

    --Check if there is any zone configured to trigger on vehicle loitering
    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in ipairs(zoneIds) do

        local triggerLoitering =  zoneInst:getZoneValue(zoneId,"trigger_loitering",ZoneDictType.Config)
        local detectVehicles =  zoneInst:getZoneValue(zoneId,"detect_vehicles",ZoneDictType.Config)

        if triggerLoitering == true and detectVehicles == true then
            return true
        end
    end

    return false
end

--- Decision function to determine if vehicles on the edge of the image should be filtered
---@param zoneInst zonemanaged
---@return boolean
function ShouldFilterVehicleEdgeDetections(zoneInst)
    if AnyVehicleLoiteringZone(zoneInst) then
        return false
    end

    return true
end

--- Converts tracks fields to snake case
---@param tracks Track[]
---@return table
function ConvertTracksToSnakeCase(tracks)

    local processedTracks = {}

    for _, track in ipairs(tracks) do
        local processedTrack = {
            bbox = track.bbox,
            class_label = track.classLabel,
            last_seen = track.lastSeen,
            id = track.id,
            source_tracker_track_id = track.sourceTrackerTrackId,
            movement_direction = track.movementDirection,
            external_id = track.externalId,
            best_thumbnail = track.bestThumbnail
        }

        table.insert(processedTracks,processedTrack)
    end


    return processedTracks

end

--- Fill event zone info
---@param zoneInst zonemanaged
---@param event Event
function FillEventZoneInfo(zoneInst,event)

    local zoneId = event.zone_id

    local zone = zoneInst:getZoneById(zoneId)
    
    event.extra.current_entries = zone.cur_entries
    event.extra.total_hits = zone.total_hits

    -- If zone is configured to trigger on loitering, add loitering_min_duration to event.extra
    local triggerLoitering =  zoneInst:getZoneValue(zoneId,"trigger_loitering",ZoneDictType.Config)
    if triggerLoitering == true then
        event.extra.loitering_min_duration = zoneInst:getZoneValue(zoneId,"loitering_min_duration",ZoneDictType.Config)
    end
end

--- Process confirmed event
---@param event Event
---@param zoneInst zonemanaged
---@param tripwireInst tripwiremanaged
---@param allTracks Track[]
---@param lastFrameTracks Track[]
function ProcessConfirmedEvent(event,zoneInst,tripwireInst,allTracks,lastFrameTracks)

    if event.zone_id ~= nil then
        FillEventZoneInfo(zoneInst,event)
    end

    if event.type == EventTypes.TripwireCrossing then
        ProcessTripwireCrossingConfirmedEvent(event,tripwireInst)
    end

    UpdateEventSubtype(event,lastFrameTracks)

    AddBestThumbnailToEvent(event,allTracks)
end


---@param zoneInst zonemanaged
---@param zoneId string
---@param tripwireInst tripwiremanaged
---@param tripwireId string
---@return boolean
function GetTriggerStateValue(zoneInst,zoneId,tripwireInst,tripwireId,key)

    if zoneId ~= nil then
        return zoneInst:getZoneValue(zoneId,key,ZoneDictType.State)
    else
        return tripwireInst:getTripwireValue(tripwireId,key,ZoneDictType.State)
    end
end

---@param zoneInst zonemanaged
---@param zoneId string
---@param tripwireInst tripwiremanaged
---@param tripwireId string
---@param key string
---@return boolean
function GetTriggerConfigValue(zoneInst,zoneId,tripwireInst,tripwireId,key)

    if zoneId ~= nil then
        return zoneInst:getZoneValue(zoneId,key,ZoneDictType.Config)
    else
        return tripwireInst:getTripwireValue(tripwireId,key,ZoneDictType.Config)
    end
end

--- Process tripwire crossing confirmed event
---@param event Event
---@param tripwireInst tripwiremanaged
function ProcessTripwireCrossingConfirmedEvent(event,tripwireInst)

    local confirmedCrossingCount = tripwireInst:getTripwireValue(event.tripwire_id,TripwireStateFieldPaths.ConfirmedCrossingCount,ZoneDictType.State)

    if confirmedCrossingCount == nil then
        confirmedCrossingCount = 0
    end

    confirmedCrossingCount = confirmedCrossingCount + 1

    tripwireInst:setTripwireValue(event.tripwire_id,TripwireStateFieldPaths.ConfirmedCrossingCount,confirmedCrossingCount,ZoneDictType.State)

    event.extra.count = confirmedCrossingCount

end

--- Update tripwires total hits to match confirmed crossings
---@param tripwireInst tripwiremanaged
function UpdateTripwiresTotalHitsToMatchConfirmedCrossings(tripwireInst)

    local tripwireIds = tripwireInst:getTripwireIds()

    for _, tripwireId in ipairs(tripwireIds) do

        local confirmedCrossingCount = tripwireInst:getTripwireValue(tripwireId,TripwireStateFieldPaths.ConfirmedCrossingCount,ZoneDictType.State)

        if confirmedCrossingCount == nil then
            confirmedCrossingCount = 0
        end

        tripwireInst:setTripwireValue(tripwireId,"total_hits",confirmedCrossingCount,ZoneDictType.State)
    end

end


--- Filter events to be published
---@param events Event[]
---@param zoneInst zonemanaged
---@param tripwireInst tripwiremanaged
---@return Event[]
function FilterEventsToBePublished(events,zoneInst,tripwireInst)

    local filteredEvents = {}

    for _, event in ipairs(events) do
        if event.type == EventTypes.TripwireCrossing then
            local tripwireId = event.tripwire_id
            local triggerOnCrossing = tripwireInst:getTripwireValue(tripwireId,"trigger_crossing",ZoneDictType.Config)
            if triggerOnCrossing then
                table.insert(filteredEvents,event)
            end
        else
            table.insert(filteredEvents,event)
        end
    end

    return filteredEvents
end

--- Update event start data entries
---@param tracks Track[]
---@param zoneInst zonemanaged
function UpdateObjectInsideLastKnownInfo(tracks,zoneInst)

    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in ipairs(zoneIds) do

        local objectsInside = zoneInst:getZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInside,ZoneDictType.State) or {}

        for trackId, _ in pairs(objectsInside) do
            local track = GetTrackById(tracks,trackId)
            if track ~= nil then
                zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInsideLastKnownInfo.."/"..trackId.."/bbox",track.bbox,ZoneDictType.State)
                zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInsideLastKnownInfo.."/"..trackId.."/class",getTrackClass(track),ZoneDictType.State)
            end
        end
        
    end
end

--- Clean Object Inside Last known info to prevent memory leaking
---@param removedTracks Track[]
---@param zoneInst zonemanaged
function CleanObjectInsideLastKnownInfoForRemovedTracks(removedTracks,zoneInst)

    local zoneIds = zoneInst:getZoneIds()

    for _, zoneId in ipairs(zoneIds) do

        for _, track in ipairs(removedTracks) do
            -- api.logging.LogWarning("Cleaning object inside last known info for track "..track.id)
            zoneInst:setZoneValue(zoneId,ZoneStateFieldPaths.ObjectsInsideLastKnownInfo.."/"..track.id,nil,ZoneDictType.State)
        end
        
    end
end

--- Calculates the difference between the current and last tracks, and returns the tracks that have been added and removed
---@param lastFrameTracks Track[]
---@param currentTracks Track[]
---@return Track[], Track[]
function CalcTrackDiff(lastFrameTracks, currentTracks)
    
    local addedTracks = {}
    local removedTracks = {}

    local lastFrameTrackIds = {}
    local currentTrackIds = {}

    for _, track in ipairs(lastFrameTracks) do
        lastFrameTrackIds[track.id] = true
    end

    for _, track in ipairs(currentTracks) do
        currentTrackIds[track.id] = true
    end

    for _, track in ipairs(currentTracks) do
        if lastFrameTrackIds[track.id] == nil then
            table.insert(addedTracks, track)
        end
    end

    for _, track in ipairs(lastFrameTracks) do
        if currentTrackIds[track.id] == nil then
            table.insert(removedTracks, track)
        end
    end

    return addedTracks, removedTracks

end


--- Deletes tracks that are no longer moving
---@param tracks Track[]
---@param trackerInst trackermanaged
function DeleteStoppedTracks(tracks,trackerInst)
    for _, track in ipairs(tracks) do

        -- Let's make sure we don't delete tracks that are being checked for loitering events.
        local isBeingCheckedForLoitering = TrackMeta.getValue(track.id,TrackMetaKeys.LoiteringStatus) == TrackLoiteringStatus.Checking

        if IsTrackStopped(track) and isBeingCheckedForLoitering == false then
            api.logging.LogVerbose("Track is considered to be idle, deleting it "..track.id)
            trackerInst:deleteTrackById(track.sourceTrackerTrackId)
        end
    end
end