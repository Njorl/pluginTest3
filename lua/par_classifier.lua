
ParClassifier = {

    Keys = {
        Base = "Global/PARClassification",
    },

    ClassesMap = {
        Military = "Military",
        CarryingGun = "CarryingGun"
    },

    ClassesList = {
        "Military",
        "CarryingGun"
    },
    TrackMetaKeys = {
        LastClassificationTime = "par_classification_last_classification_time",
        CarryingGun = "par_classification_carrying_gun",
        DebugAverageGunClassificationConfidence = "par_classification_debug_average_gun_classification_confidence",
        LastInferenceBBox = "par_classification_last_inference_bbox",
        CarryingGunConfidence = "par_classification_carrying_gun_confidence",
        GunClassificationHistory = "par_gun_classification_history"
    }
}


ParClassifier.Keys.Enabled = ParClassifier.Keys.Base.."/enabled"
ParClassifier.Keys.Duration = ParClassifier.Keys.Base.."/duration_sec"
ParClassifier.Keys.GunClassIndex = ParClassifier.Keys.Base.."/gun_class_index"
ParClassifier.Keys.Frequency = ParClassifier.Keys.Base.."/frequency_per_sec"
ParClassifier.Keys.Model = ParClassifier.Keys.Base.."/Model"
ParClassifier.Keys.CarryingGunConfidenceThreshold = ParClassifier.Keys.Base.."/gun_conf_threshold"
ParClassifier.Keys.BBoxHorizontalPaddingFactor = ParClassifier.Keys.Base.."/bbox_horizontal_padding_factor"
ParClassifier.Keys.BBoxVerticalPaddingFactor = ParClassifier.Keys.Base.."/bbox_vertical_padding_factor"

ParClassifier.ClassesUISelection = {
    {Label = "Armed person", Field = ParClassifier.ClassesMap.CarryingGun}
}

--- Loads the model
---@param instance rt_instance
---@return boolean true if loaded
function ParClassifier.LoadModel(instance)
    local detectInst = api.factory.inference.get(instance, ParClassifier.Keys.Model)
    if detectInst == nil then
        local detectInst = api.factory.inference.create(instance, ParClassifier.Keys.Model)
        detectInst:loadModelFromConfig()
    end
    return true
end

--- Checks if the model has been loaded
---@param instance rt_instance
---@return boolean true if loaded
function ParClassifier.IsModelLoaded(instance)
    local detectInst = api.factory.inference.get(instance, ParClassifier.Keys.Model)
    return detectInst ~= nil
end

--- Deletes the face detector
---@param instance rt_instance
function ParClassifier.DeleteModel(instance)
    deleteInferenceBackend(instance, ParClassifier.Keys.Model)
end

--- Checks if face detection is enabled
---@param instance rt_instance
---@return boolean
function ParClassifier.IsEnabled(instance)
    return instance:getConfigValue(ParClassifier.Keys.Enabled) == true
end

--- Detects faces on image
---@param instance rt_instance
---@param personTracks Track[]
---@param image buffer
---@param currentTimeSec number
function ParClassifier.Classify(instance,personTracks,image,currentTimeSec)

    local timeBetweenClassifications = 1.0 / instance:getConfigValue(ParClassifier.Keys.Frequency)

    
    local personBboxes = table.remap(personTracks, function(track)
        return track.bbox
    end)

    local bboxHorizontalPaddingFactor = instance:getConfigValue(ParClassifier.Keys.BBoxHorizontalPaddingFactor) or 100
    local bboxVerticalPaddingFactor = instance:getConfigValue(ParClassifier.Keys.BBoxVerticalPaddingFactor) or 100


    local imgSize = image:getSize()
    local paddedPersonBboxes = table.remap(personBboxes, function(bbox)
        return PadBoxRelFactor(bbox, imgSize, bboxHorizontalPaddingFactor/100.0, bboxVerticalPaddingFactor/100.0)
    end)
    personBboxes = paddedPersonBboxes

    if #personBboxes > 0 then
        local classificationDuration = instance:getConfigValue(ParClassifier.Keys.Duration)

        local classifierInst = api.factory.inference.get(instance, ParClassifier.Keys.Model)
        local batchInferenceResults = classifierInst:runInference(personBboxes, image)

        for sourceIdx, inferenceResult in ipairs(batchInferenceResults) do

            local classificationConfidences = sigmoid(inferenceResult.feat)
            local gunClassIdx = instance:getConfigValue(ParClassifier.Keys.GunClassIndex)
            local gunConfidence = classificationConfidences[gunClassIdx]
            local originalBbox = personBboxes[sourceIdx]

            -- If we know the person is already carrying a gun, don't classify again
            if ParClassifier.IsCarryingGun(personTracks[sourceIdx]) then
                goto continue
            end
            
            local sourceTrackId = personTracks[sourceIdx].id
            
            local lastClassificationTime = TrackMeta.getValue(sourceTrackId, ParClassifier.TrackMetaKeys.LastClassificationTime)

            if lastClassificationTime == nil or (currentTimeSec - lastClassificationTime) >= timeBetweenClassifications then
                TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.LastClassificationTime, currentTimeSec)
            else
                goto continue
            end

            local gunClassificationHistory = TrackMeta.getValue(sourceTrackId, ParClassifier.TrackMetaKeys.GunClassificationHistory)

            -- print("gun confidence "..inspect(gunConfidence))

            if gunClassificationHistory == nil then
                gunClassificationHistory = {{confidence=gunConfidence, time=currentTimeSec}}
            else
                table.insert(gunClassificationHistory, {confidence=gunConfidence, time=currentTimeSec})
            end

            -- Remove old classifications

            -- print("#recentGunClassificationHistory "..inspect(#gunClassificationHistory))
            -- print("#gunClassificationHistory "..inspect(#gunClassificationHistory))

            local recentGunClassificationHistory = table.filter(gunClassificationHistory, function(classification)
                return (currentTimeSec - classification.time) <= classificationDuration
            end)

            TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.GunClassificationHistory, recentGunClassificationHistory)

            TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.CarryingGunConfidence, gunConfidence)
            TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.LastInferenceBBox, originalBbox)

            local timeElapsedBetweenClassifications = gunClassificationHistory[#gunClassificationHistory].time - gunClassificationHistory[1].time

            -- print("timeElapsedBetweenClassifications "..inspect(timeElapsedBetweenClassifications).." classificationDuration "..inspect(classificationDuration))

            if timeElapsedBetweenClassifications >= classificationDuration then


                local gunClassificationConfidences = table.remap(recentGunClassificationHistory, function(classification)
                    return classification.confidence
                end)
                
                -- Average the confidences
                local averageGunClassificationConfidence = table.reduce(gunClassificationConfidences, function(acc, confidence)
                    return acc + confidence
                end, 0) / #gunClassificationConfidences

                -- print("averageGunClassificationConfidence "..inspect(averageGunClassificationConfidence))

                local gunClassificationConfidenceThreshold = instance:getConfigValue(ParClassifier.Keys.CarryingGunConfidenceThreshold)

                TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.DebugAverageGunClassificationConfidence, gunClassificationConfidenceThreshold)

                if averageGunClassificationConfidence >= gunClassificationConfidenceThreshold then
                    TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.CarryingGun, true)
                else
                    TrackMeta.setValue(sourceTrackId, ParClassifier.TrackMetaKeys.CarryingGun, false)
                end
            end
            

            ::continue::
        end
    end
end


--- Returns true if the track is carrying a gun
---@param track Track
---@return boolean
function ParClassifier.IsCarryingGun(track)
    return TrackMeta.getValue(track.id, ParClassifier.TrackMetaKeys.CarryingGun)
end

--- Returns true if we know if the track is carrying a gun
---@param track Track
---@return boolean
function ParClassifier.KnowIfIsCarryingGun(track)
    return TrackMeta.getValue(track.id, ParClassifier.TrackMetaKeys.CarryingGun) ~=  nil
end

--- Returns true if we know if the track is carrying a gun
---@param track Track
---@return boolean
function ParClassifier.GetDebugGunAverageClassificationConfidence(track)
    return TrackMeta.getValue(track.id, ParClassifier.TrackMetaKeys.DebugAverageGunClassificationConfidence)
end


--- Returns boxes to be displayed on UI
---@param tracks Track[]
---@return table
function ParClassifier.GetUIBoxes(tracks)
    
    local relevantTracks = table.filter(tracks, function(track)
        return ParClassifier.KnowIfIsCarryingGun(track)
    end)

    local relevantBoxes = table.remap(relevantTracks, function(track)
        local box = TrackMeta.getValue(track.id, ParClassifier.TrackMetaKeys.LastInferenceBBox)
        box.label = "Gun"
        box.confidence = TrackMeta.getValue(track.id, ParClassifier.TrackMetaKeys.CarryingGunConfidence)
        return box
    end)

    return relevantBoxes
end