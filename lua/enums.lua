
EventTypes = {
    TripwireCrossing = "tripwire_crossing",
    TripwireTailgating = "tripwire_tailgating",
    AreaEnter = "area_enter",
    AreaExit = "area_exit",
    AreaCrowding = "area_crowding",
    AreaMovement = "area_movement",
    ObjectLeft = "object_left",
    ObjectRemoved = "object_removed",
    IntrusionStart = "intrusion_start",
    IntrusionEnd = "intrusion_end",
    LoiteringStart = "loitering_start",
    LoiteringEnd = "loitering_end",
}

Modality = {
    RGB = "rgb",
    Thermal = "thermal"
}

PluginKeys = {
    DetectorRGB = "Detector",
    DetectorThermal = "DetectorThermal",
    ClassifierRGB = "ClassifierRGB",
    ClassifierThermal = "ClassifierThermal",
    Bbox3d = "Bbox3d",
    VehicleClassifier = "VehicleClassifier",
}

TriggerGroups = {
    AreaAdvanced = "advanced_areas",
    TripwireAdvanced = "advanced_tripwires",
    TripwireCrossing = "tripwire_crossing",
    TripwireCounting = "tripwire_counting",
    TripwireTailgating = "tripwire_tailgating",
    AreaCrowding = "crowding_areas",
    AreaLoitering = "loitering_areas",
    AreaOccupancy = "occupancy_areas",
    AreaIntrusion = "intrusion_areas",
    AreaMovement = "movement_areas",
    ObjectLeft = "object_left",
    ObjectRemoved = "object_removed",
}

BoxAnchor = {
    TopLeft = "top_left",
    TopRight = "top_right",
    BottomLeft = "bottom_left",
    BottomRight = "bottom_right",
    Center = "center",
    TopCenter = "top_center",
    BottomCenter = "bottom_center",
    BottomPlaneCenter= "bottom_plane_center"
}

BoxAnchorOptions = {
    {top_left = "Top Left"},
    {top_right = "Top Right"},
    {bottom_left = "Bottom Left"},
    {bottom_right = "Bottom Right"},
    {center = "Center"},
    {top_center = "Top Center"},
    {bottom_center = "Bottom Center"}
}

BoxAnchorIncluding3DBBoxesOptions = {
    {top_left = "Top Left"},
    {top_right = "Top Right"},
    {bottom_left = "Bottom Left"},
    {bottom_right = "Bottom Right"},
    {center = "Center"},
    {top_center = "Top Center"},
    {bottom_center = "Bottom Center"},
    {bottom_plane_center = "Center of bottom plane"}
}

InferenceStrategy = {
    FullFrameInference = "full_frame",
    MotionGuided = "motion_guided",
    UseTriggerShape = "trigger_shape"
}

InferenceStrategyOptions = {
    {full_frame = "Full Region Inference"},
    {motion_guided = "Motion Guided"}
}

MotionGuidedMaxObjectSize = {
    Tiny = "tiny",
    Small = "small",
    Medium = "medium",
    Large = "large",
    XLarge = "xlarge",
    XXLarge = "xxlarge"
}

MotionGuidedMaxObjectSizeOptions = {
    {tiny = "Tiny"},
    {small = "Small"},
    {medium = "Medium"},
    {large = "Large"},
    {xlarge = "XLarge"},
    {xxlarge = "XXLarge"},
}

DetectorVariantOptions = {
    {medium_aerial = "Medium (aerial perspective)"},
    {medium_ground = "Medium (ground perspective)"},
    {medium_mixed = "Medium (aerial & ground perspective)"},
    {small_aerial = "Small (aerial perspective)"},
    {small_ground = "Small (ground perspective)"},
    {small_mixed = "Small (aerial & ground perspective)"},
    {nano = "Tiny"},
}

DetectorVariantUris = {
    medium_aerial = "auto://pva_det/rgb_aerial/medium_512x512/220325b",
    medium_mixed = "auto://pva_det/rgb/medium_512x512/230124",
    medium_ground = "auto://pva_det/rgb_ground/medium_512x512/220330",
    small_aerial = "auto://pva_det/rgb/small_320x320_aerial/221128",
    small_ground = "auto://pva_det/rgb/small_320x320_ground/221129",
    small_mixed = "auto://pva_det/rgb/small_320x320/220822",
    nano = "auto://pva_det/rgb_gs/nano_160x160/220527b",
}

ClassLabels = {
    Unknown = "Unknown",
    Background = "Background",
    Person = "Person",
    Vehicle = "Vehicle",
    Bicycle = "Bicycle",
    Animal = "Animal"
}

DetectorPresetOptions = {
    {FullRegionInference = "Full Region Inference"},
    {MosaicInference = "Mosaic Inference"}
}

DetectorPreset = {
    FullRegionInference = "FullRegionInference",
    MosaicInference = "MosaicInference"
}

ZoneDictType = {
    Config = 1,
    State = 0
}

ZoneStateFieldPaths = {
    CustomFieldsConfiguredFlag = "custom_fields_configured",
    ObjectsEntered = "custom/objects_entered",
    ObjectsInside = "custom/objects_inside",
    OngoingIntrusions = "custom/ongoing_intrusions",
    ConfirmedIntrusions = "custom/confirmed_intrusions",
    OngoingLoiterings = "custom/ongoing_loiterings",
    ConfirmedLoiterings = "custom/confirmed_loiterings",
    LoiteringNotifications = "custom/loitering_notifications",
    IsCrowded = "custom/is_crowded",
    ConfirmedEnters = "custom/confirmed_enters",
    ObjectsInsideLastKnownInfo = "custom/objects_inside_last_known_info",
}


TripwireStateFieldPaths = {
    ConfirmedCrossingCount = "custom/confirmed_crossing_count",
}

TrackMetaKeys = {
    SourceTracker = "source_tracker",
    ExternalId = "external_id",
    AccumulatedMovement = "accum_movement",
    HasTentativeEvent = "has_tentative_event",
    IsPerson = "is_person",
    IsVehicle = "is_vehicle",
    IsAnimal = "is_animal",
    IsUnknown = "is_unknown",
    BBox3d = "bbox3d",
    ZonePreviousBBox = "zone_previous_bbox",
    TripwirePreviousBBox = "tripwire_previous_bbox",
    TripwiresCrossed = "tripwires_crossed",
    Events = "events",
    Age = "age",
    Confidence = "confidence",
    IsAlive = "is_alive",
    IsLocked = "is_locked",
    OverrideClassificationLabel = "override_classification_label",
    ClassificationLock = "classification_lock",
    LastClassificationLockTimeSec = "last_classification_lock_time_sec",
    LastClassificationLabel = "last_classification_label",
    ClassificationHits = "classification_hits",
    BornTimeSec = "born_time_sec",
    LockMatchHistory = "lock_match_history",
    BBoxHistory = "bbox_history",
    MovementDirectionHistory = "movement_direction_history",
    MovementStatus = "moving_status",
    LoiteringStatus = "loitering_status",
}

TrackMovementStatus = {
    Undetermined = "undetermined",
    Moving = "moving",
    Stopped = "stopped"
}

TrackLoiteringStatus = {
    Ignored = "ignored",
    Checking = "checking",
    Confirmed = "confirmed"
}