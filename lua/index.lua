---@diagnostic disable: lowercase-global
if project_root == nil then project_root = "" end

-- Common RT Utils
dofile(luaroot .. "/api/api.lua")
-- dofile(luaroot .. "/api/plugin/tripwire.lua")
-- dofile(luaroot .. "/api/plugin/zone.lua")
dofile(luaroot .. "/api/plugin/motion.lua")
-- Project Specific Utils
dofile(project_root .. "/utils.lua")
dofile(project_root .. "/capabilities.lua")
dofile(project_root .. "/enums.lua")
dofile(project_root .. "/faces.lua")
dofile(project_root .. "/vehicle_classifier.lua")
dofile(project_root .. "/par_classifier.lua")
-- dofile(project_root .. "/profiler.lua")

json = dofile(luaroot .. "/api/json.lua")

--- GLOBAL VARIABLES ---

lastFrameDetections = {}

-- Trackers, one per class
---@type trackermanaged
personTracker = nil

---@type trackermanaged
vehicleTracker = nil

---@type trackermanaged
animalTracker = nil

---@type trackermanaged
motionTracker = nil

---@type trackermanaged
objectLeftRemovedTracker = nil --Use for object left/removed

---@type zonemanaged
zoneInst = nil

---@type tripwiremanaged
tripwireInst = nil

---@type inferencemanaged
detectInst = nil

---@type writedatamanaged
writeInst = nil

---@type motionmanaged
motionInst = nil

---@type motionmanaged
motionObjectLeftRemovedInst = nil

---@type inferencemanaged
classifierInst = nil

---@type Track[]
allTracks = {}

---@type Event[]
tentativeEvents = {}

lastFrameTracks = {}

-- Executed once on the creation of an Instance
function onCreateInstance(instance)
    input = api.factory.input.create(instance, "Input")
    input:setSourceFromConfig()

    api.factory.motion.create(instance, "Motion")
    api.factory.motion.create(instance, "MotionObjectLeftRemoved")

    api.factory.tracker.create(instance, "PersonTracker")
    api.factory.tracker.create(instance, "VehicleTracker")
    api.factory.tracker.create(instance, "AnimalTracker")
    api.factory.tracker.create(instance, "MotionTracker")
    api.factory.tracker.create(instance, "ObjectLeftRemovedTracker")

    api.factory.zone.create(instance, "Zone")
    api.factory.tripwire.create(instance, "Tripwire")
    api.factory.writedata.create(instance, "WriteData")

    output = api.factory.output.create(instance, "Output")
    output:loadHandlersFromConfig()
end

-- Executed every time when an Instance starts
function onStartInstance(name, config)
    local instance = api.thread.getCurrentInstance()
    instance:createWorker("onInit", "onRun")
end

-- Executed every time when createWorker creates a thread
function onInit(inst)
    instance = inst
    solution = instance:getSolution()

    input = api.factory.input.get(instance, "Input")
    motionInst = api.factory.motion.get(instance, "Motion")
    motionObjectLeftRemovedInst = api.factory.motion.get(instance, "MotionObjectLeftRemoved")
    personTracker = api.factory.tracker.get(instance, "PersonTracker")
    vehicleTracker = api.factory.tracker.get(instance, "VehicleTracker")
    animalTracker = api.factory.tracker.get(instance, "AnimalTracker")
    motionTracker = api.factory.tracker.get(instance, "MotionTracker")
    objectLeftRemovedTracker = api.factory.tracker.get(instance, "ObjectLeftRemovedTracker")

    zoneInst = api.factory.zone.get(instance, "Zone")
    tripwireInst = api.factory.tripwire.get(instance, "Tripwire")
    writeInst = api.factory.writedata.get(instance, "WriteData")
    output = api.factory.output.get(instance, "Output") --We need to have this to be able to export data

    instanceName = instance:getName()

    Motion.onInit(motionInst)

    Motion.onInit(motionObjectLeftRemovedInst)

    zoneInst:registerKnownZones()

    tripwireInst:registerKnownTripwires()

    ReloadClassifierIfNeeded(instance,nil,instance:getConfigValue("Global/Classification/enabled"))
    Reload3DBboxIfNeeded(instance,nil,instance:getConfigValue("Global/Bbox3d/enabled"))

    if Faces.IsFaceDetectionEnabled(instance) then
        Faces.LoadDetector(instance)
    end
    if VehicleClassifier.IsEnabled(instance) then
        VehicleClassifier.LoadModel(instance)
    end
    if ParClassifier.IsEnabled(instance) then
        ParClassifier.LoadModel(instance)
    end

    return true
end

lastFrameIndex = 0

function onRun()

    local instance = api.thread.getCurrentInstance()

    -- Get next frame, if the instance is paused we must ignore the skip_frame functionality
    local inputFrames = input:readMetaFrames(instance:isPaused())

    if #inputFrames == 0 then
        -- No frames available yet due to FPS syncronization
		instance:sleep(1) -- avoid CPU burn
        return InstanceStepResult.INSTANCE_STEP_INVALID
    end

    local inputimg = inputFrames[1].image
    if inputimg == nil or not inputimg:is_valid() then
        instance:sleep(1) -- avoid CPU burn
        return InstanceStepResult.INSTANCE_STEP_INVALID
    end


    -- Check if we need to exit the instance
    local shouldExitWhenReachedEnd = (instance:getConfigValue("Global/exit_on_end") == true)
    if input:getCurrentFrame() < lastFrameIndex then

        if shouldExitWhenReachedEnd then
            return InstanceStepResult.INSTANCE_STEP_FAIL
        end

        local resetMotionOnRestart = instance:getConfigValue("Global/reset_motion_on_restart")
        if resetMotionOnRestart == nil then resetMotionOnRestart = true end

        -- If we play a new video (or restart the current one), we need to reset motion/tracker
        resetPluginsState(resetMotionOnRestart)
    end

    lastFrameIndex = input:getCurrentFrame()

    local isDetectionEnabled = instance:getConfigValue("Global/Detection/enabled") == true
    local isClassificationEnabled = instance:getConfigValue("Global/Classification/enabled") == true
    local is3dbboxEnabled = instance:getConfigValue("Global/Bbox3d/enabled") == true

    UpdateDetectorPreset(instance)
    UpdateDetectorSensitivityPreset(instance)
    UpdateMovementSensitivityPreset(instance)

    -- Check if either detector/classifier backend needs to be restarted
    detectInst = ReloadDetectorIfNeeded(instance,detectInst,isDetectionEnabled)
    classifierInst = ReloadClassifierIfNeeded(instance,classifierInst,isClassificationEnabled)
    bbox3dInst = Reload3DBboxIfNeeded(instance,bbox3dInst,is3dbboxEnabled)
    if Faces.IsFaceDetectionEnabled(instance) then
        Faces.LoadDetector(instance)
    end

    if VehicleClassifier.IsEnabled(instance) then
        VehicleClassifier.LoadModel(instance)
    end

    if ParClassifier.IsEnabled(instance) then
        ParClassifier.LoadModel(instance)
    end

    UpdateTriggersUISettings(zoneInst)

    local motionRegions = {}

    if IsMotionActive() and IsTrackingMotionRequired(instance,zoneInst,tripwireInst) then
        motionRegions = motionInst:detectMotion(inputimg)
    end

    return runSingleFrame(inputimg,motionRegions,isDetectionEnabled,isClassificationEnabled,is3dbboxEnabled)
end

---Run biz logic for a single frame
---@param inputimg buffer
---@param motionRegions table
---@param isDetectionEnabled boolean
---@param isClassificationEnabled boolean
---@param is3dbboxEnabled boolean
---@return integer
function runSingleFrame(inputimg,motionRegions,isDetectionEnabled,isClassificationEnabled,is3dbboxEnabled)

    ---@type rt_instance
    local instance = api.thread.getCurrentInstance()

    local currentTimeSec = inputimg:getTimestamp()

    --- DETECTION
    local detectionRegionInfo = GetDetectorRegionsInfoFromInferenceStrategy(instance,inputimg,isDetectionEnabled,motionRegions,detectInst,allTracks)
    local detectionRegions = detectionRegionInfo.regions
    local atlas = nil
    local packedDetections = {}
    local lastFrameDetections = {}
    local unfilteredDetections = {}

    ---@type ClassRequirements
    local classRequirements = CheckClassesRequiredFromTripwiresAndZones(instance,zoneInst,tripwireInst,isClassificationEnabled)

    if isDetectionEnabled then

        local userDefinedDetectorRegions = GetUserDefinedDetectorRegions(instance,inputimg)

        if #userDefinedDetectorRegions > 0 then detectionRegions = userDefinedDetectorRegions end

        if #detectionRegions > 0 then lastFrameDetections = detectInst:runInference(detectionRegions) else lastFrameDetections = {} end

        if detectionRegionInfo.isUsingAtlasPacking then
            packedDetections = lastFrameDetections
            atlas = detectionRegionInfo.atlasPackingInfo.atlas
            lastFrameDetections = UnpackAtlasDetections(detectionRegionInfo.atlasPackingInfo,packedDetections)
        end

        lastFrameDetections = FilterDetectionsByConfidence(detectInst,lastFrameDetections)

        unfilteredDetections = lastFrameDetections
        lastFrameDetections = FilterEdgeDetections(lastFrameDetections,detectionRegions,detectionRegionInfo.isUsingAtlasPacking,detectionRegionInfo.atlasPackingInfo,{Vehicle = ShouldFilterVehicleEdgeDetections(zoneInst)})

        -- if detectionRegionInfo.isUsingAtlasPacking then
        --     lastFrameDetections = FilterOverlappingDetections(lastFrameDetections,{Person = true})
        -- end

        -- if GetDetectorInferenceStrategy(instance) == InferenceStrategy.MotionGuided then
        --     lastFrameDetections = FilterDetectionsNotOverlappingMotionRegions(lastFrameDetections,motionRegions)
        -- end


        if #lastFrameDetections > 1 then
            lastFrameDetections = api.utils.NMS(lastFrameDetections, 0.5, 0.01)
        end
    end


    -- TRACKER

    local personDetections = FilterDetectionsByLabel(lastFrameDetections,ClassLabels.Person)
    local vehicleDetections = FilterDetectionsByLabel(lastFrameDetections,ClassLabels.Vehicle)
    local animalDetections = FilterDetectionsByLabel(lastFrameDetections,ClassLabels.Animal)

    local motionTrackerSourceBoxes = motionRegions
    if classRequirements.unknowns == false then motionTrackerSourceBoxes = {} end

    motionTracker:trackAndUpdateObjects(inputimg, motionTrackerSourceBoxes, instance:getDeltaTime())

    local vehicleTrackerSourceBoxes = vehicleDetections
    if classRequirements.vehicles == false then vehicleTrackerSourceBoxes = {} end

    vehicleTracker:trackAndUpdateObjects(inputimg, vehicleTrackerSourceBoxes, instance:getDeltaTime())

    local peopleTrackerSourceBoxes = personDetections
    if classRequirements.people == false then peopleTrackerSourceBoxes = {} end
    personTracker:trackAndUpdateObjects(inputimg, peopleTrackerSourceBoxes, instance:getDeltaTime())

    local animalTrackerSourceBoxes = animalDetections
    if classRequirements.animals == false then animalTrackerSourceBoxes = {} end
    animalTracker:trackAndUpdateObjects(inputimg, animalTrackerSourceBoxes, instance:getDeltaTime())

    personTracks = GetTracksFromTracker(personTracker,ClassLabels.Person)
    vehicleTracks = GetTracksFromTracker(vehicleTracker,ClassLabels.Vehicle)
    animalTracks = GetTracksFromTracker(animalTracker,ClassLabels.Animal)
    motionTracks = GetTracksFromTracker(motionTracker,ClassLabels.Unknown)

    allTracks = tableConcat(personTracks,vehicleTracks)
    allTracks = tableConcat(allTracks,animalTracks)
    allTracks = tableConcat(allTracks,motionTracks)

    local newTracks, removedTracks = CalcTrackDiff(lastFrameTracks, allTracks)

    if detectionRegionInfo.isUsingAtlasPacking then
        local saveTrackAtlases = instance:getConfigValue("Global/Debug/capture_extra_track_info") == true
        if saveTrackAtlases then
            allTracks = FetchAtlasBlockForTracks(detectionRegionInfo.atlasPackingInfo, allTracks)
        end
    end

    UpdateTracksLocking(personTracks,personTracker,currentTimeSec)
    UpdateTracksLocking(vehicleTracks,vehicleTracker,currentTimeSec)
    UpdateTracksLocking(animalTracks,animalTracker,currentTimeSec)
    UpdateTracksLocking(motionTracks,motionTracker,currentTimeSec)

    UpdateTracksConfidence(personTracks,personTracker,personDetections)
    UpdateTracksConfidence(vehicleTracks,vehicleTracker,vehicleDetections)
    UpdateTracksConfidence(animalTracks,animalTracker,animalDetections)
    UpdateTracksConfidence(motionTracks,motionTracker,motionRegions)

    UpdateTracksMovementStatus(instance,personTracks,personTracker,currentTimeSec,inputimg:getSize())
    UpdateTracksMovementStatus(instance,vehicleTracks,vehicleTracker,currentTimeSec,inputimg:getSize())
    UpdateTracksMovementStatus(instance,animalTracks,animalTracker,currentTimeSec,inputimg:getSize())
    UpdateTracksMovementStatus(instance,motionTracks,motionTracker,currentTimeSec,inputimg:getSize())

    UpdateTrackClassesBasedOnClassification(instance,allTracks,classifierInst,inputimg,currentTimeSec,isClassificationEnabled)
    UpdateTrack3dBoundingBoxes(instance,allTracks,bbox3dInst,inputimg,is3dbboxEnabled)

    if Faces.IsFaceDetectionEnabled(instance) and Faces.IsModelLoaded(instance) then
        detectionResult = Faces.Detect(instance,personTracks,inputimg)
        faces = detectionResult[1]
        faceDetectionArea = detectionResult[2]
    end

    if VehicleClassifier.IsEnabled(instance) and VehicleClassifier.IsModelLoaded(instance) then
        VehicleClassifier.Classify(instance,vehicleTracks,inputimg,currentTimeSec)
    end


    if ParClassifier.IsEnabled(instance) and ParClassifier.IsModelLoaded(instance) then
        ParClassifier.Classify(instance,personTracks,inputimg,currentTimeSec)
    end

    -- BUSINESS LOGIC
    local zoneEvents = checkZones(allTracks,zoneInst)
    local tripwireEventInfo = checkTripwires(allTracks,tripwireInst,currentTimeSec)
    local tripwireEvents = tripwireEventInfo[1]
    local pointsChecked = tripwireEventInfo[2]
    zoneEvents = updateObjectsInsideZonesAndSmoothEvents(zoneEvents, zoneInst, allTracks, currentTimeSec)

    -- OBJECT LEFT/REMOVED
    if numberOfObjectLeftRemovedAreas(zoneInst) > 0 then
        usingMotionObjectLeftRemoved = true
        local motionAreas = motionObjectLeftRemovedInst:detectMotion(inputimg)
        objectLeftRemovedTracker:trackAndUpdateObjects(inputimg, motionAreas, instance:getDeltaTime())
        handleObjectLeft(objectLeftRemovedTracker, zoneInst, inputimg, currentTimeSec,tentativeEvents)
        handleObjectRemoved(objectLeftRemovedTracker, zoneInst, inputimg, currentTimeSec, tentativeEvents)
    end

    handleAreas(zoneInst, zoneEvents, allTracks, inputimg, currentTimeSec, tentativeEvents)
    handleLineCrossingAndTailgating(tripwireInst, inputimg, tripwireEvents, allTracks, currentTimeSec, tentativeEvents)
    handleAreaLoitering(inputimg, zoneInst, currentTimeSec, allTracks, tentativeEvents)

    -- EVENT FILTERING AND POST-PROCESSING --
    local confirmedEvents, updatedTentativeEvents = ProcessTentativeEvents(tentativeEvents, zoneInst, tripwireInst, currentTimeSec, allTracks, lastFrameTracks)
    tentativeEvents = updatedTentativeEvents

    local outputEvents = FilterEventsToBePublished(confirmedEvents, zoneInst, tripwireInst)

    if #outputEvents > 0 then
        api.logging.LogVerbose("Publishing events: " .. inspect(outputEvents))
    end

    UpdateTripwiresTotalHitsToMatchConfirmedCrossings(tripwireInst)

    -- SINKS --

    -- Required sinks
    instance:writeOutputSink("source", OutputType.Image, inputimg, "Input Image")
    instance:writeOutputSink("frame_meta", "", GetFrameMetadata(instance,inputimg), "Frame metadata")
    instance:writeOutputSink("zones", OutputType.Poly, zoneInst:getZones(2), "Areas")
    instance:writeOutputSink("tripwires", OutputType.Line, tripwireInst:getTripwires(2), "Tripwires")
    instance:writeOutputSink("tracks", OutputType.BBox, ProcessTracksForSinkOutput(allTracks,false), "Tracks")
    instance:writeOutputSink("bounding_boxes_3d", OutputType.BBox3D, Get3DBoundingBoxesFromTracks(allTracks), "3D Bounding Boxes")
    instance:writeOutputSink("zone_stats", "", GetZoneStats(zoneInst, inputimg), "Zone Stats")
    instance:writeOutputSink("global_object_stats", "",  GetGlobalObjectStats(allTracks, inputimg), "Global Object Stats")
    instance:writeOutputSink("detections", OutputType.BBox, lastFrameDetections, "Detections") -- not optional. it's exposed in the export options
    instance:writeOutputSink("events", OutputType.Event, outputEvents, "Events")


    -- Optional sinks (only in debug mode)
    if instance:getConfigValue("Global/Debug/enable_debug_sinks") then

        if atlas == nil then

            if #detectionRegions > 0 then
                atlas = inputimg:copy(detectionRegions[1].x,detectionRegions[1].y,detectionRegions[1].width,detectionRegions[1].height,true)
            else
                atlas = inputimg
            end
        end

        instance:writeOutputSink("texture_pack_atlas", OutputType.Image, atlas, "Packed texture")
        instance:writeOutputSink("packed_detections", OutputType.BBox, packedDetections, "Packed Detections")
        instance:writeOutputSink("unfiltered_detections", OutputType.BBox, unfilteredDetections, "Unfiltered Detections")

        -- end
        instance:writeOutputSink("matched_tracks", OutputType.BBox, GetMatchedTracksBboxesFromTracker(vehicleTracker), "Matched Tracks")
        instance:writeOutputSink("locked_tracks", OutputType.BBox, ProcessTracksForSinkOutput(allTracks,true), "Locked Tracks")
        instance:writeOutputSink("motion_boxes", OutputType.BBox, motionRegions, "Motion regions")
        instance:writeOutputSink("trigger_points_checked", OutputType.Point, pointsChecked, "Object Trigger points")

        if detectionRegionInfo.isUsingAtlasPacking then
            instance:writeOutputSink("detection_regions", OutputType.BBox, detectionRegionInfo.atlasPackingInfo.sourceRegions, "Detection regions")
        else
            instance:writeOutputSink("detection_regions", OutputType.BBox, detectionRegions, "Detection regions")
        end

        instance:writeOutputSink("gun_classification", OutputType.BBox, ParClassifier.GetUIBoxes(allTracks), "Gun classification")

    end

    -- draw the detections on an output buffer
    local outputImage = inputimg
    local outputPreset = instance:getConfigValue("Output/render_preset")
    if (outputPreset ~= nil and outputPreset ~= "NONE" and outputPreset ~= "") then
        outputImage = inputimg:copy()
    end

    if Faces.IsFaceDetectionEnabled(instance) and Faces.IsBlurringEnabled(instance) then
        Faces.Blur(faces,outputImage)
        instance:writeOutputSink("faces", OutputType.BBox, faces, "Faces")
        instance:writeOutputSink("face_detection_area", OutputType.BBox, {faceDetectionArea}, "Face Detection Area")
    end

    local outputDetections = {
        image = outputImage, -- used when exporting also the output buffer
        data = {detections = lastFrameDetections}
    }
    instance:writeOutputSink("output-detections", "output-detections", outputDetections, "Output buffer with detections metadata")

    local outputTracks = {
        image = inputimg, -- we can't export the ouptut buffer because we need to use the original image for creating the crops
        data = {tracks = ProcessTracksForSinkOutput(allTracks,true)}
    }
    instance:writeOutputSink("output-tracks", "output-tracks", outputTracks, "Output buffer with tracks metadata")

    instance:writeOutputSink("output-image", OutputType.Image, outputImage, "Output image")

    if #outputEvents > 0 then

        if instance:getConfigValue("Global/convert_event_boxes_to_abs_coords") == true then
            for _, event in ipairs(outputEvents) do
                if event.extra.bbox ~= nil then
                    event.extra.bbox = GeomUtils.RectNormToAbs(event.extra.bbox, inputimg:getSize())
                end
            end
        end

        local eventsExport = {
            image = inputimg,
            data = {events = outputEvents}
        }
        
        instance:writeOutputSink("eventsExport", "eventsExport", eventsExport, "Events Export")
    end
    
    instance:flushOutputSink()

    lastFrameTracks = allTracks

    personTracker:clearDeadTracks()
    vehicleTracker:clearDeadTracks()
    animalTracker:clearDeadTracks()
    motionTracker:clearDeadTracks()

    TrackMeta.deleteMissingTracks(allTracks)

    DeleteStoppedTracks(vehicleTracks,vehicleTracker)
    DeleteStoppedTracks(personTracks,personTracker)
    DeleteStoppedTracks(animalTracks,animalTracker)
    
    CleanObjectInsideLastKnownInfoForRemovedTracks(removedTracks,zoneInst)
    
    return InstanceStepResult.INSTANCE_STEP_OK
end

function resetPluginsState(resetMotion)
    
    if resetMotion then
        print("Resetting motion")
        if motionInst:getDetections() ~= nil then
            motionInst:reset()
        end
    end
    
    if motionObjectLeftRemovedInst:getDetections() ~= nil then
        motionObjectLeftRemovedInst:reset()
    end
    
    personTracker:deleteTracks()
    vehicleTracker:deleteTracks()
    animalTracker:deleteTracks()
    motionTracker:deleteTracks()

    objectLeftRemovedTracker:deleteTracks()
end