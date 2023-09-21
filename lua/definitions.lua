---@diagnostic disable: duplicate-doc-field

---@meta

---@class ZoneStats
---@field occupancyRate number
---@field numOccupiedZones integer
---@field numVacantZones integer

---@class GlobalObjectStats
---@field numVehicles integer
---@field numPeople integer
---@field numAnimals integer
---@field numUnknown integer


---@class AtlasPackingInfo
---@field sourceRegions Rect[]
---@field atlasRegions Rect[]
---@field atlas buffer

---@class DetectorRegionsInfo
---@field isUsingAtlasPacking boolean
---@field atlasPackingInfo AtlasPackingInfo
---@field regions Rect[]


---@class ThumbnailInfo
---@field image buffer
---@field confidence number
---@field position Rect
---@field timestamp number

---@class Track
---@field bbox Rect
---@field classLabel string
---@field lastSeen number
---@field id string
---@field sourceTrackerTrackId number
---@field movementDirection Vec2
---@field externalId string
---@field bestThumbnail ThumbnailInfo

---@class Vec2
---@field x number
---@field y number


---@class Event
---@field id string
---@field type string
---@field subtype string
---@field image buffer
---@field date string
---@field frame_time number
---@field frame_id number
---@field instance_id string
---@field system_date string
---@field extra table
---@field tracks Track[]
---@field zone_id string
---@field tripwire_id string
---@field best_thumbnail ThumbnailInfo


---@class ClassRequirements
---@field unknowns boolean
---@field people boolean
---@field vehicle boolean
---@field animals boolean

---@class TrackMovementHistoryEntry
---@field direction Vec2
---@field timestamp number