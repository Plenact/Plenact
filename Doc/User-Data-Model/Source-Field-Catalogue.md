# Current Swift source coverage

**Supported User Data Model versions:** 1.0; Version 0 is historical reference only.
**Status:** Final specification. Application/API integration is tracked separately.

SwiftSyntax audited 96 Codable declarations, 379 stored fields and 41 literal key/prefix segments. Computed/static members are excluded. The [machine mapping](Source-Coverage.json) includes source hashes and lifecycle classifications; the [Specification](Specification.md) defines wire semantics.

## WorkspaceListReference

Source: [Src/App/WorkspaceNavigation.swift](../../Src/App/WorkspaceNavigation.swift). Scope: **synchronized**. Target: `today-shortcuts#/properties/payload/properties/items/items`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `ownerID` | `collection_id` |
| `listID` | `list_id` |

## ItemAccent

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case teal, blue, purple, rose, orange, green, coral, graphite`

## KanbanListTint

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case neutral, blue, green, orange, red`

## BoardCardDetail

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case compact, detailed`

## CollectionBackgroundPreset

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case linen, sage, ocean, plum, sandstone, midnight, photo, tabletop, forestPath, sunlitWall, plain`

## CollectionBackground

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/collection_background`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `preset` | `preset` |
| `photoFileName` | `photo_asset_id` |

## BoardAppearance

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/board_appearance`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `bannerBackground` | `banner_background` |
| `listBackground` | `list_background` |
| `cardBackground` | `card_background` |
| `cardDetail` | `card_detail` |
| `collectionBackground` | `collection_background` |
| `cardTitleColor` | `card_title_color` |
| `cardTextColor` | `card_text_color` |
| `addItemTextColor` | `add_item_text_color` |
| `studioSurface` | `studio_surface` |
| `studioCardSurface` | `studio_card_surface` |
| `subtitleItalic` | `subtitle_italic` |

## ListPreviewTextColor

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case graphite, blue, teal, green, plum, rose, amber`

## SingleListViewMode

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case cards, noteList`

## ItemAppearance

Source: [Src/Features/Appearance/AppearanceModels.swift](../../Src/Features/Appearance/AppearanceModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/item_appearance`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `accent` | `accent` |
| `icon` | `icon` |
| `background` | `background` |
| `listBackground` | `list_background` |
| `cardBackground` | `card_background` |
| `cardTitleColor` | `card_title_color` |
| `cardTextColor` | `card_text_color` |
| `addItemTextColor` | `add_item_text_color` |
| `sectionCollapsed` | `section_collapsed` |
| `hideEmptySubtitle` | `hide_empty_subtitle` |
| `studioSurface` | `studio_surface` |
| `studioCardSurface` | `studio_card_surface` |
| `subtitleItalic` | `subtitle_italic` |
| `cardDetail` | `card_detail` |
| `listViewMode` | `list_view_mode` |
| `iconColor` | `icon_color` |
| `showsIconInHeader` | `shows_icon_in_header` |
| `listBackgroundOpacity` | `list_background_opacity` |

## StudioMaterial

Source: [Src/Features/Appearance/StudioModels.swift](../../Src/Features/Appearance/StudioModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case plain, color, gradient, paper, linen, dots, grid, canvas, photo, unsplash`

## StudioRemotePhoto

Source: [Src/Features/Appearance/StudioModels.swift](../../Src/Features/Appearance/StudioModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/remote_photo`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `imageURL` | `image_url` |
| `photographer` | `photographer` |
| `profileURL` | `profile_url` |
| `downloadURL` | `download_url` |

## StudioSurface

Source: [Src/Features/Appearance/StudioModels.swift](../../Src/Features/Appearance/StudioModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/surface`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `material` | `material` |
| `color` | `color` |
| `secondaryColor` | `secondary_color` |
| `strength` | `strength` |
| `readability` | `readability` |
| `verticalPosition` | `vertical_position` |
| `zoom` | `zoom` |
| `showsInPreviews` | `shows_in_previews` |
| `photoFileName` | `photo_asset_id` |
| `remotePhoto` | `remote_photo` |

## StudioArtwork

Source: [Src/Features/Appearance/StudioModels.swift](../../Src/Features/Appearance/StudioModels.swift). Scope: **synchronized**. Target: `studio-artwork#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `name` | `name` |
| `surface` | `surface` |
| `header` | `header` |
| `italicSubtitle` | `italic_subtitle` |
| `titleColor` | `title_color` |
| `textColor` | `text_color` |

## StudioDestination

Source: [Src/Features/Appearance/StudioModels.swift](../../Src/Features/Appearance/StudioModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case today = "Today", week = "Week", plans = "Plans", activity = "Activity"`
- `case calendar = "Calendar", search = "Search", settings = "Settings"`

## StudioSettings

Source: [Src/Features/Appearance/StudioModels.swift](../../Src/Features/Appearance/StudioModels.swift). Scope: **synchronized**. Target: `studio-settings#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `views` | `views` |
| `defaultCardSurface` | `default_card_surface` |
| `defaultNoteSurface` | `default_note_surface` |
| `variesNewSurfaces` | `varies_new_surfaces` |
| `variesNewHeaders` | `varies_new_headers` |
| `palette` | `palette` |

## KanbanAttachmentKind

Source: [Src/Features/Attachments/AttachmentStore.swift](../../Src/Features/Attachments/AttachmentStore.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case photo`
- `case video`
- `case audio`
- `case link`

## KanbanAttachment

Source: [Src/Features/Attachments/AttachmentStore.swift](../../Src/Features/Attachments/AttachmentStore.swift). Scope: **synchronized**. Target: `content-types#/$defs/attachment`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `fileName` | `asset_id` |
| `url` | `url` |
| `mediaKind` | `kind` |
| `addedAt` | `source_added_at_utc` |
| `exampleImage` | `example_image` |
| `drawingFileName` | `drawing_asset_id` |
| `caption` | `caption` |

## ExampleCoverImage

Source: [Src/Features/Attachments/CoverLibrary.swift](../../Src/Features/Attachments/CoverLibrary.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case garden, mountains, workspace`
- `case readingCorner = "reading-corner", tidyHome = "tidy-home", laundryDay = "laundry-day", homeRepairs =
            "home-repairs"`
- `case wateringPlants = "watering-plants", forestPath = "forest-path", flowerBouquet = "flower-bouquet", sunrise`
- `case studyBooks = "study-books", writingNotes = "writing-notes", projectPlanning = "project-planning", learning`
- `case freshProduce = "fresh-produce", cooking, groceryBag = "grocery-bag", coffeeBreak = "coffee-break"`
- `case camping, coastalWalk = "coastal-walk", cycling, travelBag = "travel-bag"`
- `case painting, music, conversation, sharedMeal = "shared-meal"`
- `case cozySofa = "cozy-sofa", cleanKitchen = "clean-kitchen", petCare = "pet-care", deskLamp = "desk-lamp"`
- `case herbPots = "herb-pots", rainyDay = "rainy-day", butterfly`
- `case calendarPlan = "calendar-plan", coding, goalSteps = "goal-steps"`
- `case baking, breakfast, pantry, market`
- `case trainTrip = "train-trip", sailboat, picnic`
- `case photography, crafting, gift, gameNight = "game-night"`
- `case morningRoutine = "morning-routine"`
- `case bedroomReset = "bedroom-reset"`
- `case familyHome = "family-home"`
- `case windowCleaning = "window-cleaning"`
- `case mailAndLetters = "mail-and-letters"`
- `case bathroomCare = "bathroom-care"`
- `case homeBudget = "home-budget"`
- `case closetOrganizing = "closet-organizing"`
- `case shoeRack = "shoe-rack"`
- `case houseKeys = "house-keys"`
- `case vacuumCleaning = "vacuum-cleaning"`
- `case movingDay = "moving-day"`
- `case homeSecurity = "home-security"`
- `case recyclingDay = "recycling-day"`
- `case lightbulbMoment = "lightbulb-moment"`
- `case householdTools = "household-tools"`
- `case homeLaundryBasket = "home-laundry-basket"`
- `case seedlingCare = "seedling-care"`
- `case appleOrchard = "apple-orchard"`
- `case flowerBed = "flower-bed"`
- `case gardenTools = "garden-tools"`
- `case birdWatching = "bird-watching"`
- `case sunflowerDay = "sunflower-day"`
- `case moonlitGarden = "moonlit-garden"`
- `case autumnLeaves = "autumn-leaves"`
- `case snowyMorning = "snowy-morning"`
- `case rainbowSky = "rainbow-sky"`
- `case cloudWatching = "cloud-watching"`
- `case riverFlow = "river-flow"`
- `case greenhouse = "greenhouse"`
- `case cactusCare = "cactus-care"`
- `case springRain = "spring-rain"`
- `case honeyBees = "honey-bees"`
- `case starrySky = "starry-sky"`
- `case teamMeeting = "team-meeting"`
- `case researchSession = "research-session"`
- `case inboxReview = "inbox-review"`
- `case presentationDay = "presentation-day"`
- `case mathPractice = "math-practice"`
- `case scienceLab = "science-lab"`
- `case languageStudy = "language-study"`
- `case examPreparation = "exam-preparation"`
- `case careerGrowth = "career-growth"`
- `case remoteOffice = "remote-office"`
- `case projectMilestone = "project-milestone"`
- `case documentReview = "document-review"`
- `case focusSession = "focus-session"`
- `case ideaMap = "idea-map"`
- `case engineeringPlan = "engineering-plan"`
- `case schoolDay = "school-day"`
- `case certificateGoal = "certificate-goal"`
- `case teaTime = "tea-time"`
- `case soupSeason = "soup-season"`
- `case fruitBowl = "fruit-bowl"`
- `case pizzaNight = "pizza-night"`
- `case saladPreparation = "salad-preparation"`
- `case mealPrep = "meal-prep"`
- `case breadMaking = "bread-making"`
- `case birthdayCake = "birthday-cake"`
- `case waterBottle = "water-bottle"`
- `case shoppingCart = "shopping-cart"`
- `case weeklyMenu = "weekly-menu"`
- `case recipeBook = "recipe-book"`
- `case packedLunch = "packed-lunch"`
- `case farmersMarket = "farmers-market"`
- `case foodStorage = "food-storage"`
- `case familyDinner = "family-dinner"`
- `case kitchenTimer = "kitchen-timer"`
- `case roadTrip = "road-trip"`
- `case cityBreak = "city-break"`
- `case airportDeparture = "airport-departure"`
- `case passportReady = "passport-ready"`
- `case beachDay = "beach-day"`
- `case kayaking = "kayaking"`
- `case hikingBoots = "hiking-boots"`
- `case skiWeekend = "ski-weekend"`
- `case mapAndRoute = "map-and-route"`
- `case compassPoint = "compass-point"`
- `case waterfallWalk = "waterfall-walk"`
- `case campfireEvening = "campfire-evening"`
- `case stargazingTrip = "stargazing-trip"`
- `case bikeRoute = "bike-route"`
- `case fishingTrip = "fishing-trip"`
- `case travelCamera = "travel-camera"`
- `case weekendGetaway = "weekend-getaway"`
- `case potterySession = "pottery-session"`
- `case sewingProject = "sewing-project"`
- `case knittingTime = "knitting-time"`
- `case pianoPractice = "piano-practice"`
- `case guitarSession = "guitar-session"`
- `case creativeWriting = "creative-writing"`
- `case filmNight = "film-night"`
- `case letterToFriend = "letter-to-friend"`
- `case communityTime = "community-time"`
- `case volunteerDay = "volunteer-day"`
- `case partyPlanning = "party-planning"`
- `case familyMemories = "family-memories"`
- `case puzzleBreak = "puzzle-break"`
- `case stagePerformance = "stage-performance"`
- `case colorPalette = "color-palette"`
- `case sketchbook = "sketchbook"`
- `case friendshipCall = "friendship-call"`
- `case morningStretch = "morning-stretch"`
- `case walkingBreak = "walking-break"`
- `case runningRoute = "running-route"`
- `case yogaPractice = "yoga-practice"`
- `case strengthSession = "strength-session"`
- `case swimmingLaps = "swimming-laps"`
- `case heartHealth = "heart-health"`
- `case hydrationHabit = "hydration-habit"`
- `case balancedMeal = "balanced-meal"`
- `case sleepHabit = "sleep-habit"`
- `case meditationPractice = "meditation-practice"`
- `case breathingPause = "breathing-pause"`
- `case healthAppointment = "health-appointment"`
- `case medicineReminder = "medicine-reminder"`
- `case recoverySteps = "recovery-steps"`
- `case wheelchairJourney = "wheelchair-journey"`
- `case gentleMovement = "gentle-movement"`
- `case danceWorkout = "dance-workout"`
- `case sportsPractice = "sports-practice"`
- `case boxingSession = "boxing-session"`
- `case balanceTraining = "balance-training"`
- `case outdoorFitness = "outdoor-fitness"`
- `case selfCare = "self-care"`
- `case healthyBoundaries = "healthy-boundaries"`
- `case wellnessJournal = "wellness-journal"`
- `case quietMorning = "quiet-morning"`
- `case cozyEvening = "cozy-evening"`
- `case slowWeekend = "slow-weekend"`
- `case readingPause = "reading-pause"`
- `case reflectionJournal = "reflection-journal"`
- `case peacefulBreath = "peaceful-breath"`
- `case unplugTime = "unplug-time"`
- `case candlelight = "candlelight"`
- `case warmBath = "warm-bath"`
- `case softMusic = "soft-music"`
- `case mindfulMoment = "mindful-moment"`
- `case gratitudeList = "gratitude-list"`
- `case sunsetRest = "sunset-rest"`
- `case cloudDreams = "cloud-dreams"`
- `case moonlight = "moonlight"`
- `case teaAndThoughts = "tea-and-thoughts"`
- `case restfulSpace = "restful-space"`
- `case rainyWindow = "rainy-window"`
- `case peacefulLake = "peaceful-lake"`
- `case forestRetreat = "forest-retreat"`
- `case personalPause = "personal-pause"`
- `case freshStart = "fresh-start"`
- `case smallVictories = "small-victories"`
- `case kindnessMoment = "kindness-moment"`
- `case intentionalDay = "intentional-day"`
- `case catCompanion = "cat-companion"`
- `case dogWalk = "dog-walk"`
- `case puppyPlay = "puppy-play"`
- `case catNap = "cat-nap"`
- `case fishTank = "fish-tank"`
- `case breakfastTable = "breakfast-table"`
- `case linenSorting = "linen-sorting"`
- `case storageBoxes = "storage-boxes"`
- `case familyCalendar = "family-calendar"`
- `case plantShelf = "plant-shelf"`
- `case weekendChores = "weekend-chores"`
- `case balconyBreak = "balcony-break"`
- `case homeNetwork = "home-network"`
- `case roomRefresh = "room-refresh"`
- `case organizedEntryway = "organized-entryway"`
- `case blanketCorner = "blanket-corner"`
- `case trashDay = "trash-day"`
- `case dishwashing = "dishwashing"`
- `case windowGarden = "window-garden"`
- `case homeDelivery = "home-delivery"`
- `case kitchenSupplies = "kitchen-supplies"`
- `case sharedHousehold = "shared-household"`
- `case shoeCleaning = "shoe-cleaning"`
- `case batteryCheck = "battery-check"`
- `case seasonalDecor = "seasonal-decor"`
- `case woodlandHare = "woodland-hare"`
- `case rabbitGarden = "rabbit-garden"`
- `case pondFish = "pond-fish"`
- `case songbirdMorning = "songbird-morning"`
- `case butterflyMeadow = "butterfly-meadow"`
- `case ladybugLeaf = "ladybug-leaf"`
- `case dragonflyPond = "dragonfly-pond"`
- `case pineForest = "pine-forest"`
- `case moonAndCloud = "moon-and-cloud"`
- `case sunAfterRain = "sun-after-rain"`
- `case winterForest = "winter-forest"`
- `case mushroomWalk = "mushroom-walk"`
- `case orchardHarvest = "orchard-harvest"`
- `case wildflowerTrail = "wildflower-trail"`
- `case riverStones = "river-stones"`
- `case fernCorner = "fern-corner"`
- `case roseGarden = "rose-garden"`
- `case stormySky = "stormy-sky"`
- `case mistyHills = "misty-hills"`
- `case gardenHarvest = "garden-harvest"`
- `case birdFeeder = "bird-feeder"`
- `case pottingDay = "potting-day"`
- `case gardenFence = "garden-fence"`
- `case natureObservation = "nature-observation"`
- `case fallWalk = "fall-walk"`
- `case dailyPriorities = "daily-priorities"`
- `case weeklyReview = "weekly-review"`
- `case writingDraft = "writing-draft"`
- `case proofreading = "proofreading"`
- `case videoConference = "video-conference"`
- `case phoneInterview = "phone-interview"`
- `case jobSearch = "job-search"`
- `case portfolioBuilding = "portfolio-building"`
- `case businessPlan = "business-plan"`
- `case financialReview = "financial-review"`
- `case codingPractice = "coding-practice"`
- `case softwareRelease = "software-release"`
- `case productDesign = "product-design"`
- `case teamRetrospective = "team-retrospective"`
- `case mentoring = "mentoring"`
- `case historyStudy = "history-study"`
- `case geographyStudy = "geography-study"`
- `case biologyStudy = "biology-study"`
- `case physicsPractice = "physics-practice"`
- `case chemistryNotes = "chemistry-notes"`
- `case onlineCourse = "online-course"`
- `case libraryVisit = "library-visit"`
- `case studyGroup = "study-group"`
- `case presentationRehearsal = "presentation-rehearsal"`
- `case learningMilestone = "learning-milestone"`
- `case appleSnack = "apple-snack"`
- `case vegetableChopping = "vegetable-chopping"`
- `case smoothieBreak = "smoothie-break"`
- `case coffeeBeans = "coffee-beans"`
- `case herbalTea = "herbal-tea"`
- `case hotChocolate = "hot-chocolate"`
- `case cookieBaking = "cookie-baking"`
- `case pancakeMorning = "pancake-morning"`
- `case sandwichLunch = "sandwich-lunch"`
- `case pastaEvening = "pasta-evening"`
- `case riceBowl = "rice-bowl"`
- `case spiceShelf = "spice-shelf"`
- `case oliveOil = "olive-oil"`
- `case freezerPrep = "freezer-prep"`
- `case leftoversPlan = "leftovers-plan"`
- `case dinnerReservation = "dinner-reservation"`
- `case shoppingList = "shopping-list"`
- `case budgetGroceries = "budget-groceries"`
- `case checkoutTime = "checkout-time"`
- `case localBakery = "local-bakery"`
- `case freshFish = "fresh-fish"`
- `case vegetarianMeal = "vegetarian-meal"`
- `case fruitPicnic = "fruit-picnic"`
- `case celebrationToast = "celebration-toast"`
- `case recipeTesting = "recipe-testing"`
- `case trainPlatform = "train-platform"`
- `case busJourney = "bus-journey"`
- `case ferryCrossing = "ferry-crossing"`
- `case motorcycleRide = "motorcycle-ride"`
- `case camperVan = "camper-van"`
- `case hotelCheckin = "hotel-checkin"`
- `case beachSunrise = "beach-sunrise"`
- `case seasidePicnic = "seaside-picnic"`
- `case mountainCabin = "mountain-cabin"`
- `case forestCamping = "forest-camping"`
- `case lakeKayak = "lake-kayak"`
- `case sunsetSailing = "sunset-sailing"`
- `case islandEscape = "island-escape"`
- `case nationalPark = "national-park"`
- `case travelItinerary = "travel-itinerary"`
- `case packingChecklist = "packing-checklist"`
- `case travelBudget = "travel-budget"`
- `case roadsideStop = "roadside-stop"`
- `case scenicOverlook = "scenic-overlook"`
- `case waterfrontStroll = "waterfront-stroll"`
- `case urbanExploration = "urban-exploration"`
- `case museumDay = "museum-day"`
- `case travelPostcard = "travel-postcard"`
- `case snowAdventure = "snow-adventure"`
- `case returningHome = "returning-home"`
- `case watercolorPractice = "watercolor-practice"`
- `case paperCollage = "paper-collage"`
- `case origamiTime = "origami-time"`
- `case embroideryWork = "embroidery-work"`
- `case woodworking = "woodworking"`
- `case creativeBrainstorm = "creative-brainstorm"`
- `case poetryReading = "poetry-reading"`
- `case storyOutline = "story-outline"`
- `case songwriting = "songwriting"`
- `case choirPractice = "choir-practice"`
- `case singingSession = "singing-session"`
- `case violinPractice = "violin-practice"`
- `case drumRhythm = "drum-rhythm"`
- `case recordingSession = "recording-session"`
- `case photoEditing = "photo-editing"`
- `case portraitSession = "portrait-session"`
- `case streetPhotography = "street-photography"`
- `case handmadeGift = "handmade-gift"`
- `case birthdayLetter = "birthday-letter"`
- `case boardGameEvening = "board-game-evening"`
- `case familyGame = "family-game"`
- `case bookClub = "book-club"`
- `case communityGarden = "community-garden"`
- `case charityProject = "charity-project"`
- `case celebrationMemories = "celebration-memories"`
- `case sunriseWalk = "sunrise-walk"`
- `case parkJog = "park-jog"`
- `case stairWorkout = "stair-workout"`
- `case cyclingSession = "cycling-session"`
- `case indoorCycling = "indoor-cycling"`
- `case pilatesPractice = "pilates-practice"`
- `case mobilitySession = "mobility-session"`
- `case restDay = "rest-day"`
- `case physicalTherapy = "physical-therapy"`
- `case medicalCheckup = "medical-checkup"`
- `case visionCare = "vision-care"`
- `case dentalCare = "dental-care"`
- `case bloodPressure = "blood-pressure"`
- `case vitaminRoutine = "vitamin-routine"`
- `case mindfulEating = "mindful-eating"`
- `case proteinPrep = "protein-prep"`
- `case healthySnack = "healthy-snack"`
- `case waterReminder = "water-reminder"`
- `case sleepSchedule = "sleep-schedule"`
- `case bodyScan = "body-scan"`
- `case stressRelease = "stress-release"`
- `case mentalHealth = "mental-health"`
- `case supportSession = "support-session"`
- `case smallProgress = "small-progress"`
- `case energyCheck = "energy-check"`
- `case afternoonPause = "afternoon-pause"`
- `case weekendReading = "weekend-reading"`
- `case hammockTime = "hammock-time"`
- `case cabinQuiet = "cabin-quiet"`
- `case seasideCalm = "seaside-calm"`
- `case mountainStillness = "mountain-stillness"`
- `case rainListening = "rain-listening"`
- `case slowBreathing = "slow-breathing"`
- `case sunriseReflection = "sunrise-reflection"`
- `case moonJournal = "moon-journal"`
- `case selfCompassion = "self-compassion"`
- `case hopefulMorning = "hopeful-morning"`
- `case calmFocus = "calm-focus"`
- `case lettingGo = "letting-go"`
- `case quietConfidence = "quiet-confidence"`
- `case joyfulMoment = "joyful-moment"`
- `case comfortCorner = "comfort-corner"`
- `case peacefulSleep = "peaceful-sleep"`
- `case screenFreeEvening = "screen-free-evening"`
- `case journalingPrompt = "journaling-prompt"`
- `case freshPerspective = "fresh-perspective"`
- `case patientProgress = "patient-progress"`
- `case softSunlight = "soft-sunlight"`
- `case clearMind = "clear-mind"`
- `case thankfulEvening = "thankful-evening"`

## BoardViewportState

Source: [Src/Features/Boards/BoardViewport.swift](../../Src/Features/Boards/BoardViewport.swift). Scope: **device_local**. Target: `device-only state; retained by private source capture`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `scale` | `device-only state; retained by private source capture` |
| `panoramic` | `device-only state; retained by private source capture` |
| `gallery` | `device-only state; retained by private source capture` |
| `presentation` | `device-only state; retained by private source capture` |
| `visibleListID` | `device-only state; retained by private source capture` |
| `offsets` | `device-only state; retained by private source capture` |

## DatedPlanningWeek

Source: [Src/Features/Calendar/CalendarModels.swift](../../Src/Features/Calendar/CalendarModels.swift). Scope: **synchronized**. Target: `calendar-week#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `startKey` | `start_date` |
| `collection` | `collection_id` |
| `dayListIDs` | `day_lists` |
| `explicitlySaved` | `explicitly_saved` |

## PlanningCalendarDocument

Source: [Src/Features/Calendar/CalendarModels.swift](../../Src/Features/Calendar/CalendarModels.swift). Scope: **synchronized**. Target: `calendar-index#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `version` | `source_store_version` |
| `currentWeekKey` | `current_week_start_date` |
| `firstWeekday` | `first_weekday` |
| `weeks` | `week_ids` |
| `checklistLinkWeeks` | `checklist_link_weeks` |

## ListCreationDraft

Source: [Src/Features/Capture/InlineListCapture.swift](../../Src/Features/Capture/InlineListCapture.swift). Scope: **device_local**. Target: `device-only state; retained by private source capture`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `title` | `device-only state; retained by private source capture` |
| `subtitle` | `device-only state; retained by private source capture` |
| `description` | `device-only state; retained by private source capture` |

## PreferredMapsApp

Source: [Src/Features/Cards/CardLocation.swift](../../Src/Features/Cards/CardLocation.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case apple, google`

## FullMonthExampleStore.Manifest

Source: [Src/Features/Examples/FullMonthExamples.swift](../../Src/Features/Examples/FullMonthExamples.swift). Scope: **recovery_local**. Target: `local recovery only; no synchronized representation`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `version` | `local recovery only; no synchronized representation` |
| `createdAt` | `local recovery only; no synchronized representation` |
| `hashes` | `local recovery only; no synchronized representation` |

## LibraryImportanceItem

Source: [Src/Features/Importance/ImportanceStore.swift](../../Src/Features/Importance/ImportanceStore.swift). Scope: **synchronized**. Target: `content-selection#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `collectionID` | `capture-only: owner context for mapped card_id` |
| `cardID` | `card_id` |
| `level` | `importance` |

## KanbanLabelColor

Source: [Src/Features/Labels/LabelModels.swift](../../Src/Features/Labels/LabelModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case mint`
- `case yellow`
- `case orange`
- `case coral`
- `case pink`
- `case purple`
- `case blue`
- `case green`
- `case red`
- `case gray`

## KanbanLabelCategory

Source: [Src/Features/Labels/LabelModels.swift](../../Src/Features/Labels/LabelModels.swift). Scope: **synchronized**. Target: `label-category#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `name` | `name` |

## KanbanLabel

Source: [Src/Features/Labels/LabelModels.swift](../../Src/Features/Labels/LabelModels.swift). Scope: **synchronized**. Target: `label#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `name` | `name` |
| `categoryID` | `category_id` |
| `color` | `color` |

## LabelLibrary

Source: [Src/Features/Labels/LabelModels.swift](../../Src/Features/Labels/LabelModels.swift). Scope: **synchronized**. Target: `label + label-category records`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `categories` | `label-category records` |
| `labels` | `label records` |

## DailyCheckIn

Source: [Src/Features/Planning/DailyCheckIn.swift](../../Src/Features/Planning/DailyCheckIn.swift). Scope: **synchronized**. Target: `planning-types#/$defs/check_in`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `focus` | `focus` |
| `changed` | `changed` |
| `savedAt` | `saved_at_utc` |

## CheckInMood

Source: [Src/Features/Planning/DailyCheckIn.swift](../../Src/Features/Planning/DailyCheckIn.swift). Scope: **synchronized**. Target: `planning-types#/$defs/mood`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `emoji` | `emoji` |
| `label` | `label` |

## DailyCheckInEntry

Source: [Src/Features/Planning/DailyCheckIn.swift](../../Src/Features/Planning/DailyCheckIn.swift). Scope: **synchronized**. Target: `planning-types#/$defs/check_in_entry`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `savedAt` | `saved_at_utc` |
| `changed` | `changed` |
| `focus` | `focus` |
| `intention` | `intention` |
| `constraints` | `constraints` |
| `concerns` | `concerns` |
| `priorities` | `priorities` |
| `completedTasks` | `completed_tasks` |
| `totalTasks` | `total_tasks` |
| `notes` | `notes` |
| `unavailable` | `unavailable` |
| `legacy` | `legacy` |
| `mood` | `mood` |

## ObjectiveStatus

Source: [Src/Features/Planning/PeriodicReview.swift](../../Src/Features/Planning/PeriodicReview.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case active = "Active", achieved = "Achieved", paused = "Paused", released = "Let go"`

## ReviewObjective

Source: [Src/Features/Planning/PeriodicReview.swift](../../Src/Features/Planning/PeriodicReview.swift). Scope: **synchronized**. Target: `planning-types#/$defs/objective`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `title` | `title` |
| `status` | `status` |
| `progress` | `progress` |
| `nextStep` | `next_step` |

## PeriodicReviewRecord

Source: [Src/Features/Planning/PeriodicReview.swift](../../Src/Features/Planning/PeriodicReview.swift). Scope: **synchronized**. Target: `periodic-review#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `title` | `title` |
| `startKey` | `start_date` |
| `endKey` | `end_date` |
| `timeZoneID` | `time_zone` |
| `step` | `step` |
| `highlights` | `highlights` |
| `learned` | `learned` |
| `direction` | `direction` |
| `risks` | `risks` |
| `startingObjectives` | `starting_objectives` |
| `objectives` | `objectives` |
| `priorities` | `priorities` |
| `updatedAt` | `updated_at_utc` |
| `completedAt` | `completed_at_utc` |

## PeriodicReviewStore.Document

Source: [Src/Features/Planning/PeriodicReview.swift](../../Src/Features/Planning/PeriodicReview.swift). Scope: **legacy_storage_wrapper**. Target: `contained records synchronize; wrapper version retained in migration provenance`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `version` | `contained records synchronize; wrapper version retained in migration provenance` |
| `records` | `contained records synchronize; wrapper version retained in migration provenance` |

## PlanningExampleFocus

Source: [Src/Features/Planning/PlanningTemplates.swift](../../Src/Features/Planning/PlanningTemplates.swift). Scope: **synchronized**. Target: `planning-types#/$defs/example_focus`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `important` | `important` |
| `bookmarked` | `bookmarked` |
| `allDay` | `all_day` |

## PlanningRoutineTemplate

Source: [Src/Features/Planning/PlanningTemplates.swift](../../Src/Features/Planning/PlanningTemplates.swift). Scope: **synchronized**. Target: `planning-template#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `name` | `name` |
| `kind` | `kind` |
| `anchorKey` | `anchor_date` |
| `timeZoneID` | `time_zone` |
| `firstWeekday` | `first_weekday` |
| `collection` | `collection_id` |
| `weekdays` | `weekdays` |
| `exampleFocus` | `example_focus` |

## PlanningRoutineTemplate.Kind

Source: [Src/Features/Planning/PlanningTemplates.swift](../../Src/Features/Planning/PlanningTemplates.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case day = "Day", week = "Week"`

## PlanningRoutineLibrary

Source: [Src/Features/Planning/PlanningTemplates.swift](../../Src/Features/Planning/PlanningTemplates.swift). Scope: **synchronized**. Target: `template-library#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `version` | `source_store_version` |
| `templates` | `template_ids` |
| `defaultWeekID` | `default_week_id` |
| `bundledRoutineRevision` | `bundled_routine_revision` |

## ReviewRhythmKind

Source: [Src/Features/Planning/ReviewRhythm.swift](../../Src/Features/Planning/ReviewRhythm.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case daily, weekly`

## ReviewRhythmPreferences

Source: [Src/Features/Planning/ReviewRhythm.swift](../../Src/Features/Planning/ReviewRhythm.swift). Scope: **synchronized**. Target: `review-rhythm#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `dailyInvitations` | `daily_invitations` |
| `weeklyInvitations` | `weekly_invitations` |
| `dailyMinutes` | `daily_minutes` |
| `weeklyMinutes` | `weekly_minutes` |
| `weeklyWeekday` | `weekly_weekday` |
| `dailyNotifications` | `daily_notifications` |
| `weeklyNotifications` | `weekly_notifications` |

## DailyPlanPriority

Source: [Src/Features/Planning/TodayPlan.swift](../../Src/Features/Planning/TodayPlan.swift). Scope: **synchronized**. Target: `planning-types#/$defs/priority`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `ownerID` | `source_collection_id` |
| `cardID` | `card_id` |
| `title` | `title` |
| `location` | `source_location` |
| `sourceCreatedAt` | `source_created_at_utc` |

## DailyPlan

Source: [Src/Features/Planning/TodayPlan.swift](../../Src/Features/Planning/TodayPlan.swift). Scope: **synchronized**. Target: `daily-plan#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `date` |
| `timeZoneID` | `time_zone` |
| `intention` | `intention` |
| `constraints` | `constraints` |
| `concerns` | `concerns` |
| `priorities` | `priorities` |
| `updatedAt` | `updated_at_utc` |
| `checkIn` | `check_in` |
| `checkIns` | `check_ins` |
| `eveningReview` | `evening_review` |
| `visionStep` | `vision_step` |
| `visionCompletedAt` | `vision_completed_at_utc` |

## DailyPlanStore.Document

Source: [Src/Features/Planning/TodayPlan.swift](../../Src/Features/Planning/TodayPlan.swift). Scope: **legacy_storage_wrapper**. Target: `contained records synchronize; wrapper version retained in migration provenance`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `version` | `contained records synchronize; wrapper version retained in migration provenance` |
| `plans` | `contained records synchronize; wrapper version retained in migration provenance` |

## DailyReviewAction

Source: [Src/Features/Planning/TodayReview.swift](../../Src/Features/Planning/TodayReview.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case keep, keepTomorrow, table, complete, archive, queue, tomorrow, date(String)`

## DailyReviewDecision

Source: [Src/Features/Planning/TodayReview.swift](../../Src/Features/Planning/TodayReview.swift). Scope: **synchronized**. Target: `planning-types#/$defs/review_decision`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `source` | `source` |
| `result` | `result` |
| `action` | `action` |
| `recordedAt` | `recorded_at_utc` |

## DailyEveningReview

Source: [Src/Features/Planning/TodayReview.swift](../../Src/Features/Planning/TodayReview.swift). Scope: **synchronized**. Target: `planning-types#/$defs/evening_review`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `step` | `step` |
| `completedAt` | `completed_at_utc` |
| `helped` | `helped` |
| `difficult` | `difficult` |
| `tomorrow` | `tomorrow` |
| `decisions` | `decisions` |
| `achievements` | `achievements` |

## WeeklyReviewRecord

Source: [Src/Features/Planning/TodayReview.swift](../../Src/Features/Planning/TodayReview.swift). Scope: **synchronized**. Target: `weekly-review#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `source_review_key` |
| `startKey` | `start_date` |
| `timeZoneID` | `time_zone` |
| `firstWeekday` | `first_weekday` |
| `step` | `step` |
| `highlights` | `highlights` |
| `learned` | `learned` |
| `direction` | `direction` |
| `constraints` | `constraints` |
| `risks` | `risks` |
| `priorities` | `priorities` |
| `decisions` | `decisions` |
| `updatedAt` | `updated_at_utc` |
| `completedAt` | `completed_at_utc` |

## WeeklyReviewStore.Document

Source: [Src/Features/Planning/TodayReview.swift](../../Src/Features/Planning/TodayReview.swift). Scope: **legacy_storage_wrapper**. Target: `contained records synchronize; wrapper version retained in migration provenance`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `version` | `contained records synchronize; wrapper version retained in migration provenance` |
| `records` | `contained records synchronize; wrapper version retained in migration provenance` |

## ProfileColor

Source: [Src/Features/Profile/ProfileModels.swift](../../Src/Features/Profile/ProfileModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/color`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `red` | `red` |
| `green` | `green` |
| `blue` | `blue` |
| `legacyToken` | `legacy_token` |

## ProfileAvatarIcon

Source: [Src/Features/Profile/ProfileModels.swift](../../Src/Features/Profile/ProfileModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case initials`
- `case person`
- `case personCircle`
- `case smilingFace`
- `case leaf`
- `case sun`
- `case moon`
- `case sparkles`
- `case bolt`
- `case heart`
- `case star`
- `case cloud`

## TodayFocusOrder

Source: [Src/Features/Profile/ProfileModels.swift](../../Src/Features/Profile/ProfileModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case dayList, chronological`

## ImportanceStarStyle

Source: [Src/Features/Profile/ProfileModels.swift](../../Src/Features/Profile/ProfileModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case tucked, fanned`

## LocalProfilePreferences

Source: [Src/Features/Profile/ProfileModels.swift](../../Src/Features/Profile/ProfileModels.swift). Scope: **synchronized**. Target: `user-preferences#/properties/payload/properties/preferences`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `defaultListID` | `default_list_id` |
| `usesReducedContent` | `uses_reduced_content` |
| `scrollsOverflowingTitles` | `scrolls_overflowing_titles` |
| `importanceStarStyle` | `importance_star_style` |
| `enablesLowerCornerBack` | `enables_lower_corner_back` |
| `usesLargeControls` | `uses_large_controls` |
| `randomizesNewCardHeaders` | `randomizes_new_card_headers` |
| `randomizesNewCardBackgrounds` | `randomizes_new_card_backgrounds` |
| `showsDueDatesOnNewCards` | `shows_due_dates_on_new_cards` |
| `preferredMapsApp` | `preferred_maps_app` |
| `keepsDayListsInTimeOrder` | `keeps_day_lists_in_time_order` |
| `todayFocusOrder` | `today_focus_order` |
| `todayFocusGroupsBySection` | `today_focus_groups_by_section` |
| `todayFocusIncludesUpNext` | `today_focus_includes_up_next` |
| `todayFocusIncludesImportant` | `today_focus_includes_important` |
| `todayFocusIncludesBookmarked` | `today_focus_includes_bookmarked` |
| `todayFocusHidesCompleted` | `today_focus_hides_completed` |
| `todayFocusItemCount` | `today_focus_item_count` |
| `showsNavigationLabels` | `shows_navigation_labels` |

## LocalProfile

Source: [Src/Features/Profile/ProfileModels.swift](../../Src/Features/Profile/ProfileModels.swift). Scope: **synchronized**. Target: `user-profile#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `source_profile_id` |
| `createdAt` | `source_created_at_utc` |
| `displayName` | `display_name` |
| `email` | `email` |
| `context` | `context` |
| `avatarColor` | `avatar_color` |
| `avatarIcon` | `avatar_icon` |
| `avatarForegroundColor` | `avatar_foreground_color` |
| `avatarPhotoFileName` | `avatar_asset_id` |
| `preferences` | `user-preferences#/properties/payload/properties/preferences` |

## PlenactRemoteUser

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `userID` | `Version-0.md` |
| `username` | `Version-0.md` |
| `displayName` | `Version-0.md` |
| `accountRole` | `Version-0.md` |

## PlenactRemoteSession

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **credentials_or_version_0_auth**. Target: `excluded from user-data exports`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `accessToken` | `excluded from user-data exports` |
| `expiresAtUTC` | `excluded from user-data exports` |
| `user` | `excluded from user-data exports` |

## PlenactUserDirectoryResponse

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `users` | `Version-0.md` |

## PlenactCreatedUserResponse

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `user` | `Version-0.md` |

## PlenactLoginRequest

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **credentials_or_version_0_auth**. Target: `excluded from user-data exports`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `action` | `excluded from user-data exports` |
| `username` | `excluded from user-data exports` |
| `password` | `excluded from user-data exports` |

## PlenactLogoutRequest

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `action` | `Version-0.md` |

## PlenactCreateMemberRequest

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **credentials_or_version_0_auth**. Target: `excluded from user-data exports`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `username` | `excluded from user-data exports` |
| `displayName` | `excluded from user-data exports` |
| `password` | `excluded from user-data exports` |

## PlenactBoardWriteRequest

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `expectedRevision` | `Version-0.md` |
| `document` | `Version-0.md` |
| `seedKind` | `Version-0.md` |

## PlenactAssignmentRequest

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `expectedRevision` | `Version-0.md` |
| `cardID` | `Version-0.md` |
| `action` | `Version-0.md` |
| `userID` | `Version-0.md` |

## PlenactAPIErrorResponse

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `error` | `Version-0.md` |
| `currentRevision` | `Version-0.md` |

## PlenactAPIClient.EmptyResponse

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.


## PlenactBoardWriteResponse

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `revision` | `Version-0.md` |
| `document` | `Version-0.md` |

## PlenactAssignmentResponse

Source: [Src/Features/Sync/PlenactAPIClient.swift](../../Src/Features/Sync/PlenactAPIClient.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `revision` | `Version-0.md` |
| `changed` | `Version-0.md` |

## PlenactBoardDocument

Source: [Src/Features/Sync/PlenactBoardDocument.swift](../../Src/Features/Sync/PlenactBoardDocument.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `schemaVersion` | `Version-0.md` |
| `boardKey` | `Version-0.md` |
| `lists` | `Version-0.md` |
| `labelLibrary` | `Version-0.md` |

## PlenactBoardSnapshotResponse

Source: [Src/Features/Sync/PlenactBoardDocument.swift](../../Src/Features/Sync/PlenactBoardDocument.swift). Scope: **version_0_transport**. Target: `Version-0.md`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `revision` | `Version-0.md` |
| `document` | `Version-0.md` |
| `storedAtUTC` | `Version-0.md` |
| `storedByUserID` | `Version-0.md` |
| `storageOrigin` | `Version-0.md` |

## KanbanChecklistActionDetail

Source: [Src/Models/ChecklistModels.swift](../../Src/Models/ChecklistModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/action_detail`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `description` | `description` |
| `checklists` | `checklists` |
| `comments` | `comments` |

## KanbanChecklistActionContent

Source: [Src/Models/ChecklistModels.swift](../../Src/Models/ChecklistModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case webLink(URL)`
- `case standard`
- `case linkedCard(cardID: Int)`
- `case actionDetail(KanbanChecklistActionDetail)`

## KanbanChecklistActionContent.Kind

Source: [Src/Models/ChecklistModels.swift](../../Src/Models/ChecklistModels.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case webLink`
- `case standard`
- `case linkedCard`
- `case actionDetail`

## KanbanChecklistItem

Source: [Src/Models/ChecklistModels.swift](../../Src/Models/ChecklistModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/checklist_item`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `title` | `title` |
| `isCompleted` | `completed` |
| `content` | `content` |
| `retainedDetail` | `retained_detail` |
| `retainedCardID` | `retained_card_id` |
| `retainedURL` | `retained_url` |
| `linkedCollectionID` | `linked_collection_id` |

## KanbanChecklist

Source: [Src/Models/ChecklistModels.swift](../../Src/Models/ChecklistModels.swift). Scope: **synchronized**. Target: `content-types#/$defs/checklist`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `title` | `title` |
| `items` | `items` |

## CardAssigneeKind

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case registeredUser`
- `case manual`

## CardAssignee

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `content-types#/$defs/assignee`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `kind` | `kind` |
| `userID` | `user_id` |
| `displayName` | `display_name` |

## ItemPresentation

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case card`
- `case note`

## ItemDisplayFormat

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case card, note, divider, picture, title, text`

## CardDateKind

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case date, time, dateAndTime`

## ItemEmojiReaction

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `content-types#/$defs/reaction`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `emoji` | `emoji` |
| `authorID` | `source_author_id` |
| `createdAt` | `source_created_at_utc` |

## KanbanComment

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `content-types#/$defs/comment`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `author` | `author` |
| `body` | `body` |
| `createdAt` | `source_created_at_utc` |

## CardSection

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case quickActions, media, description, details, checklists, activity`

## CardSectionLayout

Source: [Src/Models/ItemMetadata.swift](../../Src/Models/ItemMetadata.swift). Scope: **synchronized**. Target: `content-types#/$defs/section_layout`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `order` | `order` |
| `hidden` | `hidden` |

## KanbanCard

Source: [Src/Models/KanbanCard.swift](../../Src/Models/KanbanCard.swift). Scope: **synchronized**. Target: `card#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `editHistory` | `edit_history` |
| `word` | `title` |
| `listTitle` | `derived: list title; original retained in source capture` |
| `isDivider` | `is_divider` |
| `isTitleChecked` | `completed` |
| `editingLocked` | `editing_locked` |
| `members` | `members` |
| `labelIDs` | `label_ids` |
| `startDate` | `start` |
| `location` | `location` |
| `dueDate` | `due` |
| `createdAt` | `source_created_at_utc` |
| `descriptionOverride` | `description_override` |
| `startDateKind` | `start_kind` |
| `dueDateKind` | `due_kind` |
| `showsDueDateInList` | `shows_due_date_in_list` |
| `sectionLayout` | `section_layout` |
| `subtitleOverride` | `subtitle_override` |
| `checklists` | `checklists` |
| `showsReactionsInPreviews` | `shows_reactions_in_previews` |
| `reactions` | `reactions` |
| `comments` | `comments` |
| `attachments` | `attachments` |
| `coverAttachmentID` | `cover_attachment_id` |
| `appearance` | `appearance` |
| `dismissedActivityIDs` | `dismissed_activity_ids` |
| `listDisplayFormat` | `display_format` |
| `itemPresentation` | `presentation` |

## KanbanList

Source: [Src/Models/KanbanList.swift](../../Src/Models/KanbanList.swift). Scope: **synchronized**. Target: `list#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `title` | `title` |
| `subtitleOverride` | `subtitle_override` |
| `cards` | `card_ids` |
| `archivedCards` | `archived_card_ids` |
| `isArchived` | `archived` |
| `appearance` | `appearance` |
| `defaultItemPresentation` | `default_item_presentation` |

## CardEditChange

Source: [Src/Models/KanbanList.swift](../../Src/Models/KanbanList.swift). Scope: **synchronized**. Target: `content-types#/$defs/history_change`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `field` | `field` |
| `previousValue` | `previous_value` |
| `newValue` | `new_value` |

## CardEditRecord

Source: [Src/Models/KanbanList.swift](../../Src/Models/KanbanList.swift). Scope: **synchronized**. Target: `content-types#/$defs/history`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `id` |
| `timestamp` | `source_timestamp_utc` |
| `changes` | `changes` |

## PersonalCollectionKind

Source: [Src/Models/PersonalCollection.swift](../../Src/Models/PersonalCollection.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case list = "List"`
- `case board = "Board"`

## PersonalCollectionIcon

Source: [Src/Models/PersonalCollection.swift](../../Src/Models/PersonalCollection.swift). Scope: **synchronized**. Target: `Value-Types.md#source-enum-tokens`.


Source enum declarations (wire tokens are defined by schemas):

- `case notes = "note.text"`
- `case tasks = "checklist"`
- `case shopping = "cart"`
- `case reminders = "bell"`
- `case project = "square.stack.3d.up"`
- `case home = "house"`
- `case heart = "heart"`
- `case upcoming = "calendar"`

## PersonalCollection

Source: [Src/Models/PersonalCollection.swift](../../Src/Models/PersonalCollection.swift). Scope: **synchronized**. Target: `collection#/properties/payload`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `id` | `@id` |
| `title` | `title` |
| `kind` | `kind` |
| `icon` | `icon` |
| `color` | `color` |
| `lists` | `list_ids` |
| `savedCardIDs` | `content-selection.bookmarked` |
| `isArchived` | `archived` |
| `boardAppearance` | `board_appearance` |
| `collectionDescription` | `description` |

## ExampleLoadUndoSnapshot

Source: [Src/Persistence/ExampleUndoStore.swift](../../Src/Persistence/ExampleUndoStore.swift). Scope: **recovery_local**. Target: `local recovery only; no synchronized representation`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `lists` | `local recovery only; no synchronized representation` |
| `todayListID` | `local recovery only; no synchronized representation` |
| `week` | `local recovery only; no synchronized representation` |
| `savedCardIDs` | `local recovery only; no synchronized representation` |
| `importantCardIDs` | `local recovery only; no synchronized representation` |
| `importanceLevels` | `local recovery only; no synchronized representation` |

## LibraryRecentItem

Source: [Src/Persistence/RecentHistory.swift](../../Src/Persistence/RecentHistory.swift). Scope: **device_local**. Target: `device-only state; retained by private source capture`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `collectionID` | `device-only state; retained by private source capture` |
| `cardID` | `device-only state; retained by private source capture` |

## PlanRichText.Run

Source: [Src/SharedUI/RichTextEditor.swift](../../Src/SharedUI/RichTextEditor.swift). Scope: **synchronized**. Target: `rich-text-runs#/items`.

| Stored source field | Target / retained meaning |
| --- | --- |
| `text` | `text` |
| `bold` | `bold` |
| `italic` | `italic` |
| `color` | `color` |
| `fontName` | `fontName` |
| `fontSize` | `fontSize` |

## Storage keys and prefixes

| Literal key/prefix segment | Lifecycle |
| --- | --- |
| `Plenact.` | operational_identifier_not_storage |
| `Plenact.ActivityRecentSquareCards` | synchronized |
| `Plenact.ActivityRecents.v1` | device_local |
| `Plenact.ActivityShowsCovers` | synchronized |
| `Plenact.Board.persistence` | operational_identifier_not_storage |
| `Plenact.Board.v1` | synchronized |
| `Plenact.BoardPresentation.v1` | synchronized |
| `Plenact.BoardViewport.v1.` | device_local |
| `Plenact.CalendarWeeks.v1` | synchronized |
| `Plenact.CardCovers.enabled` | synchronized |
| `Plenact.DailyPlans.v1` | synchronized |
| `Plenact.DailyReviewTransaction.v1` | recovery_local |
| `Plenact.ExampleCardLocations.Applied.v1` | recovery_local |
| `Plenact.ExampleCardLocations.Backup.v1` | recovery_local |
| `Plenact.ExampleLoadUndo.v1` | recovery_local |
| `Plenact.LabelLibrary.v1` | synchronized |
| `Plenact.LastViewedList.v1` | device_local |
| `Plenact.LibraryImportant.v1` | synchronized |
| `Plenact.LibraryRecents.v1` | device_local |
| `Plenact.LibraryScrollsCollectionPreviews` | synchronized |
| `Plenact.LibraryShowsCollectionPreviews` | synchronized |
| `Plenact.LocalProfile.v1` | synchronized |
| `Plenact.LocalReactionAuthor.v1` | device_local |
| `Plenact.PeriodicReviews.v1` | synchronized |
| `Plenact.PersonalCollections.v1` | synchronized |
| `Plenact.PlanPreferences.v1` | synchronized |
| `Plenact.PlanningTemplates.v1` | synchronized |
| `Plenact.RecentSearches.v1` | device_local |
| `Plenact.ReviewRhythm.` | operational_identifier_not_storage |
| `Plenact.ReviewRhythm.v1` | synchronized |
| `Plenact.ReviewRhythmDismissals.v1` | device_local |
| `Plenact.SavedCardIDs.v1` | synchronized |
| `Plenact.StopAudioPreview` | operational_identifier_not_storage |
| `Plenact.Studio.Artwork.v1` | synchronized |
| `Plenact.Studio.Settings.v1` | synchronized |
| `Plenact.TodayListShortcuts.v1` | synchronized |
| `Plenact.WeekAppearance.v1` | synchronized |
| `Plenact.WeeklyReviews.v1` | synchronized |
| `Plenact.Welcome.lastDeparture.v1` | device_local |
| `Plenact.remote-session` | operational_identifier_not_storage |
| `plenact.creationDraft.` | device_local |
