// --------------------------------------------------------------------------------------------------
// @file       PhotoAttachments.swift
// @brief      Media attachment models, local file storage, and picker/gallery components
// @details    Imports image selections, stores photo and video bytes in the app container, and
//             presents attached photos, videos, and web links
//
// @notes      Cards persist attachment metadata and IDs; image data remains outside the board JSON
//
// @section    Opens
//      Function Headers
//      Variable Comments
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit


///
/// Identifies the supported content types for card attachments
///
/// @section    Purpose
///     Distinguish local photo/video media from remotely accessible links
///
enum KanbanAttachmentKind: String, Codable, Sendable {
    case photo
    case video
    case link
}


///
/// Categories for the offline illustration library
///
/// @section    Purpose
///     Organize artwork without imposing categories on people's cards
///
enum CoverCategory: String, CaseIterable, Identifiable {
    case home = "Home & Everyday"
    case nature = "Nature & Garden"
    case work = "Work & Learning"
    case food = "Food & Shopping"
    case travel = "Travel & Outdoors"
    case creativity = "Creativity & Connection"
    case health = "Health & Movement"
    case rest = "Rest & Reflection"

    ///
    /// @fcn        CoverCategory.id
    /// @brief      Identify a category filter
    /// @return     (String) stable category label
    ///
    var id: String { rawValue } /* Stable category identity */

    ///
    /// @fcn        CoverCategory.images
    /// @brief      Supply 50 ordered covers per category
    /// @details    Categories describe artwork only, not card ownership or semantics
    /// @return     ([ExampleCoverImage]) explicit curated category membership
    ///
    var images: [ExampleCoverImage] {
        switch self {
        case .home: [.readingCorner, .tidyHome, .laundryDay, .homeRepairs, .cozySofa, .cleanKitchen, .petCare, .deskLamp, .morningRoutine, .bedroomReset, .familyHome, .windowCleaning, .mailAndLetters, .bathroomCare, .homeBudget, .closetOrganizing, .shoeRack, .houseKeys, .vacuumCleaning, .movingDay, .homeSecurity, .recyclingDay, .lightbulbMoment, .householdTools, .homeLaundryBasket, .catCompanion, .dogWalk, .puppyPlay, .catNap, .fishTank, .breakfastTable, .linenSorting, .storageBoxes, .familyCalendar, .plantShelf, .weekendChores, .balconyBreak, .homeNetwork, .roomRefresh, .organizedEntryway, .blanketCorner, .trashDay, .dishwashing, .windowGarden, .homeDelivery, .kitchenSupplies, .sharedHousehold, .shoeCleaning, .batteryCheck, .seasonalDecor]
        case .nature: [.garden, .wateringPlants, .forestPath, .flowerBouquet, .sunrise, .herbPots, .rainyDay, .butterfly, .seedlingCare, .appleOrchard, .flowerBed, .gardenTools, .birdWatching, .sunflowerDay, .moonlitGarden, .autumnLeaves, .snowyMorning, .rainbowSky, .cloudWatching, .riverFlow, .greenhouse, .cactusCare, .springRain, .honeyBees, .starrySky, .woodlandHare, .rabbitGarden, .pondFish, .songbirdMorning, .butterflyMeadow, .ladybugLeaf, .dragonflyPond, .pineForest, .moonAndCloud, .sunAfterRain, .winterForest, .mushroomWalk, .orchardHarvest, .wildflowerTrail, .riverStones, .fernCorner, .roseGarden, .stormySky, .mistyHills, .gardenHarvest, .birdFeeder, .pottingDay, .gardenFence, .natureObservation, .fallWalk]
        case .work: [.workspace, .studyBooks, .writingNotes, .projectPlanning, .learning, .calendarPlan, .coding, .goalSteps, .teamMeeting, .researchSession, .inboxReview, .presentationDay, .mathPractice, .scienceLab, .languageStudy, .examPreparation, .careerGrowth, .remoteOffice, .projectMilestone, .documentReview, .focusSession, .ideaMap, .engineeringPlan, .schoolDay, .certificateGoal, .dailyPriorities, .weeklyReview, .writingDraft, .proofreading, .videoConference, .phoneInterview, .jobSearch, .portfolioBuilding, .businessPlan, .financialReview, .codingPractice, .softwareRelease, .productDesign, .teamRetrospective, .mentoring, .historyStudy, .geographyStudy, .biologyStudy, .physicsPractice, .chemistryNotes, .onlineCourse, .libraryVisit, .studyGroup, .presentationRehearsal, .learningMilestone]
        case .food: [.freshProduce, .cooking, .groceryBag, .coffeeBreak, .baking, .breakfast, .pantry, .market, .teaTime, .soupSeason, .fruitBowl, .pizzaNight, .saladPreparation, .mealPrep, .breadMaking, .birthdayCake, .waterBottle, .shoppingCart, .weeklyMenu, .recipeBook, .packedLunch, .farmersMarket, .foodStorage, .familyDinner, .kitchenTimer, .appleSnack, .vegetableChopping, .smoothieBreak, .coffeeBeans, .herbalTea, .hotChocolate, .cookieBaking, .pancakeMorning, .sandwichLunch, .pastaEvening, .riceBowl, .spiceShelf, .oliveOil, .freezerPrep, .leftoversPlan, .dinnerReservation, .shoppingList, .budgetGroceries, .checkoutTime, .localBakery, .freshFish, .vegetarianMeal, .fruitPicnic, .celebrationToast, .recipeTesting]
        case .travel: [.mountains, .camping, .coastalWalk, .cycling, .travelBag, .trainTrip, .sailboat, .picnic, .roadTrip, .cityBreak, .airportDeparture, .passportReady, .beachDay, .kayaking, .hikingBoots, .skiWeekend, .mapAndRoute, .compassPoint, .waterfallWalk, .campfireEvening, .stargazingTrip, .bikeRoute, .fishingTrip, .travelCamera, .weekendGetaway, .trainPlatform, .busJourney, .ferryCrossing, .motorcycleRide, .camperVan, .hotelCheckin, .beachSunrise, .seasidePicnic, .mountainCabin, .forestCamping, .lakeKayak, .sunsetSailing, .islandEscape, .nationalPark, .travelItinerary, .packingChecklist, .travelBudget, .roadsideStop, .scenicOverlook, .waterfrontStroll, .urbanExploration, .museumDay, .travelPostcard, .snowAdventure, .returningHome]
        case .creativity: [.painting, .music, .conversation, .sharedMeal, .photography, .crafting, .gift, .gameNight, .potterySession, .sewingProject, .knittingTime, .pianoPractice, .guitarSession, .creativeWriting, .filmNight, .letterToFriend, .communityTime, .volunteerDay, .partyPlanning, .familyMemories, .puzzleBreak, .stagePerformance, .colorPalette, .sketchbook, .friendshipCall, .watercolorPractice, .paperCollage, .origamiTime, .embroideryWork, .woodworking, .creativeBrainstorm, .poetryReading, .storyOutline, .songwriting, .choirPractice, .singingSession, .violinPractice, .drumRhythm, .recordingSession, .photoEditing, .portraitSession, .streetPhotography, .handmadeGift, .birthdayLetter, .boardGameEvening, .familyGame, .bookClub, .communityGarden, .charityProject, .celebrationMemories]
        case .health: [.morningStretch, .walkingBreak, .runningRoute, .yogaPractice, .strengthSession, .swimmingLaps, .heartHealth, .hydrationHabit, .balancedMeal, .sleepHabit, .meditationPractice, .breathingPause, .healthAppointment, .medicineReminder, .recoverySteps, .wheelchairJourney, .gentleMovement, .danceWorkout, .sportsPractice, .boxingSession, .balanceTraining, .outdoorFitness, .selfCare, .healthyBoundaries, .wellnessJournal, .sunriseWalk, .parkJog, .stairWorkout, .cyclingSession, .indoorCycling, .pilatesPractice, .mobilitySession, .restDay, .physicalTherapy, .medicalCheckup, .visionCare, .dentalCare, .bloodPressure, .vitaminRoutine, .mindfulEating, .proteinPrep, .healthySnack, .waterReminder, .sleepSchedule, .bodyScan, .stressRelease, .mentalHealth, .supportSession, .smallProgress, .energyCheck]
        case .rest: [.quietMorning, .cozyEvening, .slowWeekend, .readingPause, .reflectionJournal, .peacefulBreath, .unplugTime, .candlelight, .warmBath, .softMusic, .mindfulMoment, .gratitudeList, .sunsetRest, .cloudDreams, .moonlight, .teaAndThoughts, .restfulSpace, .rainyWindow, .peacefulLake, .forestRetreat, .personalPause, .freshStart, .smallVictories, .kindnessMoment, .intentionalDay, .afternoonPause, .weekendReading, .hammockTime, .cabinQuiet, .seasideCalm, .mountainStillness, .rainListening, .slowBreathing, .sunriseReflection, .moonJournal, .selfCompassion, .hopefulMorning, .calmFocus, .lettingGo, .quietConfidence, .joyfulMoment, .comfortCorner, .peacefulSleep, .screenFreeEvening, .journalingPrompt, .freshPerspective, .patientProgress, .softSunlight, .clearMind, .thankfulEvening]
        }
    }
}


///
/// Original bundled illustrations for examples and explicit user cover choices
///
/// @section    Purpose
///     Keep example drafts side-effect-free and independent of personal media files
///
enum ExampleCoverImage: String, Codable, CaseIterable, Sendable {
    case garden, mountains, workspace
    case readingCorner = "reading-corner", tidyHome = "tidy-home", laundryDay = "laundry-day", homeRepairs = "home-repairs"
    case wateringPlants = "watering-plants", forestPath = "forest-path", flowerBouquet = "flower-bouquet", sunrise
    case studyBooks = "study-books", writingNotes = "writing-notes", projectPlanning = "project-planning", learning
    case freshProduce = "fresh-produce", cooking, groceryBag = "grocery-bag", coffeeBreak = "coffee-break"
    case camping, coastalWalk = "coastal-walk", cycling, travelBag = "travel-bag"
    case painting, music, conversation, sharedMeal = "shared-meal"
    case cozySofa = "cozy-sofa", cleanKitchen = "clean-kitchen", petCare = "pet-care", deskLamp = "desk-lamp"
    case herbPots = "herb-pots", rainyDay = "rainy-day", butterfly
    case calendarPlan = "calendar-plan", coding, goalSteps = "goal-steps"
    case baking, breakfast, pantry, market
    case trainTrip = "train-trip", sailboat, picnic
    case photography, crafting, gift, gameNight = "game-night"

    case morningRoutine = "morning-routine"
    case bedroomReset = "bedroom-reset"
    case familyHome = "family-home"
    case windowCleaning = "window-cleaning"
    case mailAndLetters = "mail-and-letters"
    case bathroomCare = "bathroom-care"
    case homeBudget = "home-budget"
    case closetOrganizing = "closet-organizing"
    case shoeRack = "shoe-rack"
    case houseKeys = "house-keys"
    case vacuumCleaning = "vacuum-cleaning"
    case movingDay = "moving-day"
    case homeSecurity = "home-security"
    case recyclingDay = "recycling-day"
    case lightbulbMoment = "lightbulb-moment"
    case householdTools = "household-tools"
    case homeLaundryBasket = "home-laundry-basket"
    case seedlingCare = "seedling-care"
    case appleOrchard = "apple-orchard"
    case flowerBed = "flower-bed"
    case gardenTools = "garden-tools"
    case birdWatching = "bird-watching"
    case sunflowerDay = "sunflower-day"
    case moonlitGarden = "moonlit-garden"
    case autumnLeaves = "autumn-leaves"
    case snowyMorning = "snowy-morning"
    case rainbowSky = "rainbow-sky"
    case cloudWatching = "cloud-watching"
    case riverFlow = "river-flow"
    case greenhouse = "greenhouse"
    case cactusCare = "cactus-care"
    case springRain = "spring-rain"
    case honeyBees = "honey-bees"
    case starrySky = "starry-sky"
    case teamMeeting = "team-meeting"
    case researchSession = "research-session"
    case inboxReview = "inbox-review"
    case presentationDay = "presentation-day"
    case mathPractice = "math-practice"
    case scienceLab = "science-lab"
    case languageStudy = "language-study"
    case examPreparation = "exam-preparation"
    case careerGrowth = "career-growth"
    case remoteOffice = "remote-office"
    case projectMilestone = "project-milestone"
    case documentReview = "document-review"
    case focusSession = "focus-session"
    case ideaMap = "idea-map"
    case engineeringPlan = "engineering-plan"
    case schoolDay = "school-day"
    case certificateGoal = "certificate-goal"
    case teaTime = "tea-time"
    case soupSeason = "soup-season"
    case fruitBowl = "fruit-bowl"
    case pizzaNight = "pizza-night"
    case saladPreparation = "salad-preparation"
    case mealPrep = "meal-prep"
    case breadMaking = "bread-making"
    case birthdayCake = "birthday-cake"
    case waterBottle = "water-bottle"
    case shoppingCart = "shopping-cart"
    case weeklyMenu = "weekly-menu"
    case recipeBook = "recipe-book"
    case packedLunch = "packed-lunch"
    case farmersMarket = "farmers-market"
    case foodStorage = "food-storage"
    case familyDinner = "family-dinner"
    case kitchenTimer = "kitchen-timer"
    case roadTrip = "road-trip"
    case cityBreak = "city-break"
    case airportDeparture = "airport-departure"
    case passportReady = "passport-ready"
    case beachDay = "beach-day"
    case kayaking = "kayaking"
    case hikingBoots = "hiking-boots"
    case skiWeekend = "ski-weekend"
    case mapAndRoute = "map-and-route"
    case compassPoint = "compass-point"
    case waterfallWalk = "waterfall-walk"
    case campfireEvening = "campfire-evening"
    case stargazingTrip = "stargazing-trip"
    case bikeRoute = "bike-route"
    case fishingTrip = "fishing-trip"
    case travelCamera = "travel-camera"
    case weekendGetaway = "weekend-getaway"
    case potterySession = "pottery-session"
    case sewingProject = "sewing-project"
    case knittingTime = "knitting-time"
    case pianoPractice = "piano-practice"
    case guitarSession = "guitar-session"
    case creativeWriting = "creative-writing"
    case filmNight = "film-night"
    case letterToFriend = "letter-to-friend"
    case communityTime = "community-time"
    case volunteerDay = "volunteer-day"
    case partyPlanning = "party-planning"
    case familyMemories = "family-memories"
    case puzzleBreak = "puzzle-break"
    case stagePerformance = "stage-performance"
    case colorPalette = "color-palette"
    case sketchbook = "sketchbook"
    case friendshipCall = "friendship-call"
    case morningStretch = "morning-stretch"
    case walkingBreak = "walking-break"
    case runningRoute = "running-route"
    case yogaPractice = "yoga-practice"
    case strengthSession = "strength-session"
    case swimmingLaps = "swimming-laps"
    case heartHealth = "heart-health"
    case hydrationHabit = "hydration-habit"
    case balancedMeal = "balanced-meal"
    case sleepHabit = "sleep-habit"
    case meditationPractice = "meditation-practice"
    case breathingPause = "breathing-pause"
    case healthAppointment = "health-appointment"
    case medicineReminder = "medicine-reminder"
    case recoverySteps = "recovery-steps"
    case wheelchairJourney = "wheelchair-journey"
    case gentleMovement = "gentle-movement"
    case danceWorkout = "dance-workout"
    case sportsPractice = "sports-practice"
    case boxingSession = "boxing-session"
    case balanceTraining = "balance-training"
    case outdoorFitness = "outdoor-fitness"
    case selfCare = "self-care"
    case healthyBoundaries = "healthy-boundaries"
    case wellnessJournal = "wellness-journal"
    case quietMorning = "quiet-morning"
    case cozyEvening = "cozy-evening"
    case slowWeekend = "slow-weekend"
    case readingPause = "reading-pause"
    case reflectionJournal = "reflection-journal"
    case peacefulBreath = "peaceful-breath"
    case unplugTime = "unplug-time"
    case candlelight = "candlelight"
    case warmBath = "warm-bath"
    case softMusic = "soft-music"
    case mindfulMoment = "mindful-moment"
    case gratitudeList = "gratitude-list"
    case sunsetRest = "sunset-rest"
    case cloudDreams = "cloud-dreams"
    case moonlight = "moonlight"
    case teaAndThoughts = "tea-and-thoughts"
    case restfulSpace = "restful-space"
    case rainyWindow = "rainy-window"
    case peacefulLake = "peaceful-lake"
    case forestRetreat = "forest-retreat"
    case personalPause = "personal-pause"
    case freshStart = "fresh-start"
    case smallVictories = "small-victories"
    case kindnessMoment = "kindness-moment"
    case intentionalDay = "intentional-day"

    case catCompanion = "cat-companion"
    case dogWalk = "dog-walk"
    case puppyPlay = "puppy-play"
    case catNap = "cat-nap"
    case fishTank = "fish-tank"
    case breakfastTable = "breakfast-table"
    case linenSorting = "linen-sorting"
    case storageBoxes = "storage-boxes"
    case familyCalendar = "family-calendar"
    case plantShelf = "plant-shelf"
    case weekendChores = "weekend-chores"
    case balconyBreak = "balcony-break"
    case homeNetwork = "home-network"
    case roomRefresh = "room-refresh"
    case organizedEntryway = "organized-entryway"
    case blanketCorner = "blanket-corner"
    case trashDay = "trash-day"
    case dishwashing = "dishwashing"
    case windowGarden = "window-garden"
    case homeDelivery = "home-delivery"
    case kitchenSupplies = "kitchen-supplies"
    case sharedHousehold = "shared-household"
    case shoeCleaning = "shoe-cleaning"
    case batteryCheck = "battery-check"
    case seasonalDecor = "seasonal-decor"
    case woodlandHare = "woodland-hare"
    case rabbitGarden = "rabbit-garden"
    case pondFish = "pond-fish"
    case songbirdMorning = "songbird-morning"
    case butterflyMeadow = "butterfly-meadow"
    case ladybugLeaf = "ladybug-leaf"
    case dragonflyPond = "dragonfly-pond"
    case pineForest = "pine-forest"
    case moonAndCloud = "moon-and-cloud"
    case sunAfterRain = "sun-after-rain"
    case winterForest = "winter-forest"
    case mushroomWalk = "mushroom-walk"
    case orchardHarvest = "orchard-harvest"
    case wildflowerTrail = "wildflower-trail"
    case riverStones = "river-stones"
    case fernCorner = "fern-corner"
    case roseGarden = "rose-garden"
    case stormySky = "stormy-sky"
    case mistyHills = "misty-hills"
    case gardenHarvest = "garden-harvest"
    case birdFeeder = "bird-feeder"
    case pottingDay = "potting-day"
    case gardenFence = "garden-fence"
    case natureObservation = "nature-observation"
    case fallWalk = "fall-walk"
    case dailyPriorities = "daily-priorities"
    case weeklyReview = "weekly-review"
    case writingDraft = "writing-draft"
    case proofreading = "proofreading"
    case videoConference = "video-conference"
    case phoneInterview = "phone-interview"
    case jobSearch = "job-search"
    case portfolioBuilding = "portfolio-building"
    case businessPlan = "business-plan"
    case financialReview = "financial-review"
    case codingPractice = "coding-practice"
    case softwareRelease = "software-release"
    case productDesign = "product-design"
    case teamRetrospective = "team-retrospective"
    case mentoring = "mentoring"
    case historyStudy = "history-study"
    case geographyStudy = "geography-study"
    case biologyStudy = "biology-study"
    case physicsPractice = "physics-practice"
    case chemistryNotes = "chemistry-notes"
    case onlineCourse = "online-course"
    case libraryVisit = "library-visit"
    case studyGroup = "study-group"
    case presentationRehearsal = "presentation-rehearsal"
    case learningMilestone = "learning-milestone"
    case appleSnack = "apple-snack"
    case vegetableChopping = "vegetable-chopping"
    case smoothieBreak = "smoothie-break"
    case coffeeBeans = "coffee-beans"
    case herbalTea = "herbal-tea"
    case hotChocolate = "hot-chocolate"
    case cookieBaking = "cookie-baking"
    case pancakeMorning = "pancake-morning"
    case sandwichLunch = "sandwich-lunch"
    case pastaEvening = "pasta-evening"
    case riceBowl = "rice-bowl"
    case spiceShelf = "spice-shelf"
    case oliveOil = "olive-oil"
    case freezerPrep = "freezer-prep"
    case leftoversPlan = "leftovers-plan"
    case dinnerReservation = "dinner-reservation"
    case shoppingList = "shopping-list"
    case budgetGroceries = "budget-groceries"
    case checkoutTime = "checkout-time"
    case localBakery = "local-bakery"
    case freshFish = "fresh-fish"
    case vegetarianMeal = "vegetarian-meal"
    case fruitPicnic = "fruit-picnic"
    case celebrationToast = "celebration-toast"
    case recipeTesting = "recipe-testing"
    case trainPlatform = "train-platform"
    case busJourney = "bus-journey"
    case ferryCrossing = "ferry-crossing"
    case motorcycleRide = "motorcycle-ride"
    case camperVan = "camper-van"
    case hotelCheckin = "hotel-checkin"
    case beachSunrise = "beach-sunrise"
    case seasidePicnic = "seaside-picnic"
    case mountainCabin = "mountain-cabin"
    case forestCamping = "forest-camping"
    case lakeKayak = "lake-kayak"
    case sunsetSailing = "sunset-sailing"
    case islandEscape = "island-escape"
    case nationalPark = "national-park"
    case travelItinerary = "travel-itinerary"
    case packingChecklist = "packing-checklist"
    case travelBudget = "travel-budget"
    case roadsideStop = "roadside-stop"
    case scenicOverlook = "scenic-overlook"
    case waterfrontStroll = "waterfront-stroll"
    case urbanExploration = "urban-exploration"
    case museumDay = "museum-day"
    case travelPostcard = "travel-postcard"
    case snowAdventure = "snow-adventure"
    case returningHome = "returning-home"
    case watercolorPractice = "watercolor-practice"
    case paperCollage = "paper-collage"
    case origamiTime = "origami-time"
    case embroideryWork = "embroidery-work"
    case woodworking = "woodworking"
    case creativeBrainstorm = "creative-brainstorm"
    case poetryReading = "poetry-reading"
    case storyOutline = "story-outline"
    case songwriting = "songwriting"
    case choirPractice = "choir-practice"
    case singingSession = "singing-session"
    case violinPractice = "violin-practice"
    case drumRhythm = "drum-rhythm"
    case recordingSession = "recording-session"
    case photoEditing = "photo-editing"
    case portraitSession = "portrait-session"
    case streetPhotography = "street-photography"
    case handmadeGift = "handmade-gift"
    case birthdayLetter = "birthday-letter"
    case boardGameEvening = "board-game-evening"
    case familyGame = "family-game"
    case bookClub = "book-club"
    case communityGarden = "community-garden"
    case charityProject = "charity-project"
    case celebrationMemories = "celebration-memories"
    case sunriseWalk = "sunrise-walk"
    case parkJog = "park-jog"
    case stairWorkout = "stair-workout"
    case cyclingSession = "cycling-session"
    case indoorCycling = "indoor-cycling"
    case pilatesPractice = "pilates-practice"
    case mobilitySession = "mobility-session"
    case restDay = "rest-day"
    case physicalTherapy = "physical-therapy"
    case medicalCheckup = "medical-checkup"
    case visionCare = "vision-care"
    case dentalCare = "dental-care"
    case bloodPressure = "blood-pressure"
    case vitaminRoutine = "vitamin-routine"
    case mindfulEating = "mindful-eating"
    case proteinPrep = "protein-prep"
    case healthySnack = "healthy-snack"
    case waterReminder = "water-reminder"
    case sleepSchedule = "sleep-schedule"
    case bodyScan = "body-scan"
    case stressRelease = "stress-release"
    case mentalHealth = "mental-health"
    case supportSession = "support-session"
    case smallProgress = "small-progress"
    case energyCheck = "energy-check"
    case afternoonPause = "afternoon-pause"
    case weekendReading = "weekend-reading"
    case hammockTime = "hammock-time"
    case cabinQuiet = "cabin-quiet"
    case seasideCalm = "seaside-calm"
    case mountainStillness = "mountain-stillness"
    case rainListening = "rain-listening"
    case slowBreathing = "slow-breathing"
    case sunriseReflection = "sunrise-reflection"
    case moonJournal = "moon-journal"
    case selfCompassion = "self-compassion"
    case hopefulMorning = "hopeful-morning"
    case calmFocus = "calm-focus"
    case lettingGo = "letting-go"
    case quietConfidence = "quiet-confidence"
    case joyfulMoment = "joyful-moment"
    case comfortCorner = "comfort-corner"
    case peacefulSleep = "peaceful-sleep"
    case screenFreeEvening = "screen-free-evening"
    case journalingPrompt = "journaling-prompt"
    case freshPerspective = "fresh-perspective"
    case patientProgress = "patient-progress"
    case softSunlight = "soft-sunlight"
    case clearMind = "clear-mind"
    case thankfulEvening = "thankful-evening"

    ///
    /// @fcn        ExampleCoverImage.title
    /// @brief      Provide a readable artwork label without embedded image text
    /// @return     (String) human-readable name
    ///
    var title: String { rawValue.replacingOccurrences(of: "-", with: " ").capitalized } /* Readable artwork name */
    private static let tagCatalog: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "cover-tags", withExtension: "json", subdirectory: "CardCoverImages"),
              let data = try? Data(contentsOf: url), let tags = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return tags
    }()
    var tags: [String] { Self.tagCatalog[rawValue] ?? rawValue.components(separatedBy: "-") }
    static func search(_ query: String, in album: CoverCategory? = nil) -> [Self] {
        (album?.images ?? CoverCategory.allCases.flatMap(\.images)).filter { $0.matches(query) }
    }
    func matches(_ query: String) -> Bool {
        let normalized = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let terms = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let searchable = ([title] + tags).joined(separator: " ").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = searchable.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }


    ///
    /// @fcn        ExampleCoverImage.url
    /// @brief      Resolve the immutable bundled illustration
    /// @details    Only known resource names can be resolved; no remote downloads occur
    /// @return     (URL?) bundled PNG location
    ///
    var url: URL? { /* Bundled artwork resource URL */
        Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "CardCoverImages")
    }
}


///
/// Offline visual library with category filters and explicit cover selection
///
/// @section    Purpose
///     Browse all 400 offline illustrations without downloading or analyzing card content
///
struct CardCoverLibrary: View {
    let selectedImage: ExampleCoverImage? /* Current library cover, if any */
    let onSelect: (ExampleCoverImage) -> Bool /* Owner validates and publishes an explicit choice */
    @State private var query = ""
    @State private var category: CoverCategory? /* nil shows All Covers */
    @Environment(\.dynamicTypeSize) private var textSize /* Use a single column for accessibility text */
    @Environment(\.dismiss) private var dismiss /* Cancel or close a successful selection */

    ///
    /// @fcn        CardCoverLibrary.body
    /// @brief      Offer category browsing, named previews, and a non-destructive Cancel path
    /// @details    No selection or attachment is created until a person taps an illustration
    /// @return     (some View) adaptive offline library
    ///
    private var albumPicker: some View {
                    Picker("Cover album", selection: $category) {
                        Text("All Covers").tag(Optional<CoverCategory>.none)
                        ForEach(CoverCategory.allCases) { category in
                            Text(category.rawValue).tag(Optional(category))
                        }
                    }

                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 160, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("coverLibrary.album")
    }
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search covers", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Search selected cover album")
                .accessibilityIdentifier("coverLibrary.search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear cover search")
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .frame(minWidth: 130)
    }

    private var filteredImages: [ExampleCoverImage] {
        ExampleCoverImage.search(query, in: category)
    }

    var body: some View { /* Offline cover library interface */
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { albumPicker; searchField }
                        VStack(alignment: .leading, spacing: 8) { albumPicker; searchField }
                    }
                    Text("\(filteredImages.count) covers").font(.caption).foregroundStyle(.secondary)
                    if filteredImages.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    Text("Choose an illustration to use as this card's cover. Your existing photos stay attached.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns:                                        textSize.isAccessibilitySize
                              ? [GridItem(.flexible())]
                              : [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                        ForEach(filteredImages, id: \.self) { image in
                            Button {
                                if onSelect(image) {

                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CardCoverPreview(attachment: KanbanAttachment(
                                        mediaKind: .photo, exampleImage: image
                                    ), height:                   96)
                                    Label(image.title, systemImage: selectedImage == image ? "checkmark.circle.fill" : "photo")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                .padding(8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }

                            .buttonStyle(.plain)
                            .accessibilityLabel(image.title + (selectedImage == image ? ", current cover" : ""))
                            .accessibilityHint("Use this illustration as the card cover.")
                        }
                    }
                }

                .padding()
            }

            .navigationTitle("Cover Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}


///
/// Decorative, bounded preview shared by card rows and cover controls
///
/// @section    Purpose
///     Load photos away from the main actor without creating or modifying files
///
struct CardCoverPreview: View {
    let attachment: KanbanAttachment /* Explicitly selected photo */
    var height: CGFloat = 128 /* Fixed preview height, independent of source image dimensions */
    var unavailableTitle = "Cover unavailable"
    @State private var image: UIImage? /* Downsampled image for this presentation */
    @State private var unavailable = false /* Explicit missing/invalid-image feedback */

    ///
    /// @fcn        CardCoverPreview.body
    /// @brief      Render the selected cover without hiding the card's text identity
    /// @details    Task identity/cancellation prevents a previous image from replacing a changed cover
    /// @return     (some View) decorative cropped image or visible unavailable notice
    ///
    var body: some View { /* Loaded cover preview or fallback */
        GeometryReader { geometry in
            Group {
                if let image { /* Successfully decoded cover thumbnail */

                    Image(uiImage: image).resizable().scaledToFill()
                } else if unavailable {

                    Label(unavailableTitle, systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {

                    Color.secondary.opacity(0.08)
                }
            }

            .frame(width: geometry.size.width, height: height)
            .clipped()
        }

        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(!unavailable)
        .task(id: attachment) {
            image = nil
            unavailable = false

            let result = await Task.detached(priority: .utility) { /* Background thumbnail decode result */
                Result { try CardAttachmentStore.coverThumbnail(for: attachment) }
            }.value
            guard !Task.isCancelled else {

                return
            }

            switch result {

                case .success(let thumbnail): image = thumbnail /* Decoded cover thumbnail */
                case .failure: unavailable = true
            }
        }
    }
}


///
/// Visual chooser for photos already attached to a card
///
/// @section    Purpose
///     Make cover replacement recognizable without relying on numbered photo menus
///
struct CardCoverPicker: View {
    let photos: [KanbanAttachment] /* Current attached photo choices */
    let selectedID: UUID? /* Current cover, if explicitly enabled */
    let onSelect: (UUID) -> Void /* Owner validates and saves selection */
    @Environment(\.dismiss) private var dismiss /* Cancel or return after choosing */

    ///
    /// @fcn        CardCoverPicker.body
    /// @brief      Show recognizable photo choices and a clear Cancel path
    /// @details    Cancel does not mutate a card; choosing a row reuses its existing attachment
    /// @return     (some View) navigable cover-photo chooser
    ///
    var body: some View { /* Attached-photo cover choices */
        NavigationStack {
            List {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        onSelect(photo.id)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CardCoverPreview(attachment: photo)
                            Label("Photo \(index + 1)", systemImage: selectedID == photo.id ? "checkmark.circle.fill" : "photo")
                        }
                    }

                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1)\(selectedID == photo.id ? ", current cover" : "")")
                    .accessibilityHint("Use this attached photo as the card cover.")
                }
            }

            .navigationTitle("Choose Card Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}


///
/// Identifies one photo, video, or web link attached to a card
///
/// @section    Purpose
///     Persist stable attachment identity and lightweight file or URL metadata without embedding
///     image bytes in the board
///
struct KanbanAttachment: Identifiable, Hashable, Codable, Sendable {

    let id:        UUID                     /* Stable attachment identity     */
    let fileName:  String?                  /* Device-local media filename    */
    let url:       URL?                     /* Remote web-link destination    */
    let mediaKind: KanbanAttachmentKind?    /* Explicit media type when known */
    let addedAt:   Date                     /* Attachment creation time       */
    let exampleImage: ExampleCoverImage?    /* Immutable original example illustration, never user media */
    var caption: String?                   /* Optional photo text; absent in legacy attachment records */

    ///
    /// @fcn        KanbanAttachment.kind
    /// @brief      Resolve the attachment's content kind
    /// @details    Uses explicit metadata when available and infers legacy photo or link records
    ///             from whether a URL is present
    ///
    /// @return     (KanbanAttachmentKind) resolved photo, video, or link kind
    ///
    /// @pre        The attachment contains its persisted metadata
    /// @post       No attachment fields are modified
    ///
    var kind: KanbanAttachmentKind { /* Resolved kind for legacy and current records */
        mediaKind ?? (url == nil ? .photo : .link)
    }


    ///
    /// @fcn        KanbanAttachment.init(id:fileName:url:mediaKind:addedAt:)
    /// @brief      Create attachment metadata for local media or a remote link
    /// @details    Stores the supplied stable identity, location metadata, and creation date
    ///
    /// @param[in]  id        Stable attachment identity
    /// @param[in]  fileName  Local media filename, when stored on this device
    /// @param[in]  url       Remote web URL, when the attachment is a link
    /// @param[in]  mediaKind Explicit photo, video, or link content type
    /// @param[in]  addedAt   Attachment creation time
    /// @param[in]  exampleImage  Optional bundled illustration for synthetic examples
    ///
    /// @return     (KanbanAttachment) configured attachment metadata
    ///
    /// @pre        Supplied metadata describes the attachment location and content, when known
    /// @post       Stored fields match the provided values
    ///
    init(id: UUID = UUID(), fileName: String? = nil, url: URL? = nil, mediaKind: KanbanAttachmentKind? = nil, addedAt: Date = .now, exampleImage: ExampleCoverImage? = nil, caption: String? = nil) {

        self.id        = id
        self.fileName  = fileName
        self.url       = url
        self.mediaKind = mediaKind
        self.addedAt   = addedAt
        self.exampleImage = exampleImage
        self.caption   = caption
    }
}


///
/// Stores imported card media in the app's private Documents directory and validates web links
///
/// @section    Purpose
///     Keep image data out of UserDefaults while allowing board JSON to retain lightweight photo
///     and link records
///
/// @note       Files no longer referenced by any card can be removed with
///             removeUnreferencedFiles(keeping:)
///
enum CardAttachmentStore {


    ///
    /// @fcn        CardAttachmentStore.coverThumbnail(for:)
    /// @brief      Decode a bounded, orientation-correct cover image
    /// @details    Downsamples before decoding so Board rows do not load full-size camera images
    ///
    /// @param[in]  attachment  Local or bundled photo metadata
    ///
    /// @return     (UIImage) thumbnail with at most 960 pixels on its longest edge
    ///
    /// @throws     Read/decode errors for missing or invalid media
    ///
    static func coverThumbnail(for attachment: KanbanAttachment) throws -> UIImage {

        guard let url = imageURL(for: attachment), /* Resolved attachment image URL */
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), /* ImageIO source for the attachment */
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 960,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) /* Orientation-correct bounded thumbnail */ else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return UIImage(cgImage: image)
    }


    ///
    /// @fcn        CardAttachmentStore.fileNames(in:)
    /// @brief      Collect retained local media references from complete Board snapshots
    /// @details    Includes both active and archived cards regardless of the list's archive state
    ///
    /// @param[in]  lists  Complete retained lists
    ///
    /// @return     (Set<String>) referenced media filenames
    ///
    static func fileNames(in lists: [KanbanList]) -> Set<String> {

        Set(lists.flatMap(\.allCards).flatMap { $0.attachments ?? [] }.compactMap(\.fileName))
    }


    ///
    /// @fcn        CardAttachmentStore.removeDeletedFiles(_:keeping:)
    /// @brief      Remove only media belonging to successfully saved deletions
    /// @details    Never scans unrelated files; skips names still referenced by any retained
    ///             snapshot
    ///
    /// @param[in]  candidates  Previously referenced filenames affected by the saved mutation
    /// @param[in]  retained    All filenames still retained by the app
    ///
    /// @return     (Void) remove only media belonging to successfully saved deletions
    ///
    /// @throws     File removal errors; absent files are already removed
    ///
    static func removeDeletedFiles(_ candidates: Set<String>, keeping retained: Set<String>) throws {

        for name in candidates.subtracting(retained) {

            guard name == (name as NSString).lastPathComponent,
                  !name.isEmpty, name != ".", name != ".." else {
                throw CocoaError(.fileWriteInvalidFileName)
            }

            let attachment = KanbanAttachment(fileName: name) /* Metadata for the stored media file */

            guard let url = fileURL(for: attachment) else { /* Local destination for the attachment */

                throw CocoaError(.fileNoSuchFile)
            }

            if FileManager.default.fileExists(atPath: url.path) {

                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static let directoryName = "CardAttachments" /* Local media folder name */


    ///
    /// @fcn        CardAttachmentStore.saveMedia(_:kind:fileExtension:)
    /// @brief      Save selected photo or video data to the app's private attachment directory
    /// @details    Writes the media atomically under a unique filename and returns metadata
    ///             referencing that file
    ///
    /// @param[in]  mediaData      Encoded photo or video data transferred from system photo picker
    /// @param[in]  kind           Media kind represented by the saved data
    /// @param[in]  fileExtension  Preferred file extension supplied by the Photos library
    ///
    /// @return     (KanbanAttachment) metadata for the newly stored media file
    ///
    /// @throws     File-system error if the Documents directory cannot be obtained, created, or
    ///             written
    ///
    /// @pre        mediaData contains transferable photo or video bytes
    /// @post       A new media file exists in the app's Documents/CardAttachments directory
    ///
    static func saveMedia(_ mediaData: Data, kind: KanbanAttachmentKind, fileExtension: String) throws -> KanbanAttachment {

        let attachmentID        = UUID() /* Stable identity for the new media file */
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) /* Clean extension input */
        let safeExtension       = normalizedExtension.isEmpty ? (kind == .video ? "mov" : "jpg") : normalizedExtension /* Valid file extension */
        let fileName            = "\(attachmentID.uuidString).\(safeExtension)" /* Unique stored filename */
        let directoryURL        = try attachmentsDirectory() /* App-local media directory */
        let fileURL             = directoryURL.appendingPathComponent(fileName, isDirectory: false) /* Destination file URL */

        try mediaData.write(to: fileURL, options: .atomic)

        return KanbanAttachment(id: attachmentID, fileName: fileName, mediaKind: kind)
    }

    
    ///
    /// @fcn        CardAttachmentStore.fileURL(for:)
    /// @brief      Resolve an attachment record to its local media URL
    /// @details    Combines the app's Documents directory, attachment subdirectory, and stored
    ///             filename
    ///
    /// @param[in]  attachment  Metadata identifying the stored media file
    ///
    /// @return     (URL?) local media URL, or nil when its filename or Documents directory is
    ///             unavailable
    ///
    /// @pre        attachment.fileName is the filename returned when the media was saved
    /// @post       No file data or attachment metadata is modified
    ///
    static func fileURL(for attachment: KanbanAttachment) -> URL? {

        if let exampleImage = attachment.exampleImage { /* Explicit bundled cover selection */

            return exampleImage.url
        }

        guard let fileName = attachment.fileName, /* Stored local filename */
              
              let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { /* App Documents directory */
            
            return nil
        }

        return documentsURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }


    ///
    /// @fcn        CardAttachmentStore.imageURL(for:)
    /// @brief      Resolve a local URL only when an attachment represents a photo
    /// @details    Delegates filename resolution to the attachment store after checking the kind
    ///
    /// @param[in]  attachment  Attachment metadata to inspect
    ///
    /// @return     (URL?) local photo URL, or nil for other media or an unresolved filename
    ///
    /// @pre        attachment contains its persisted media metadata
    /// @post       No file data or attachment metadata is modified
    ///
    static func imageURL(for attachment: KanbanAttachment) -> URL? {
        
        guard attachment.kind == .photo else {

            return nil
        }
        
        return fileURL(for: attachment)
    }


    ///
    /// @fcn        CardAttachmentStore.webURL(from:)
    /// @brief      Validate and parse a web address entered as text
    /// @details    Trims surrounding whitespace and accepts only HTTP or HTTPS URLs with a host
    ///
    /// @param[in]  text  Candidate URL text
    ///
    /// @return     (URL?) HTTP or HTTPS URL with a host, or nil when invalid
    ///
    /// @pre        text contains a candidate URL
    /// @post       The input text is unchanged
    ///
    static func webURL(from text: String) -> URL? {
        
          let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines) /* Normalized pasted or typed URL */

          guard let components = URLComponents(string: trimmedText), /* Parsed URL components */
              
              let scheme = components.scheme?.lowercased(), /* Normalized URL scheme */
              ["http", "https"].contains(scheme),
              
              let host = components.host, /* Required URL host */
              !host.isEmpty else {
            
            return nil
        }

        return components.url
    }

    
    ///
    /// @fcn        CardAttachmentStore.removeUnreferencedFiles(keeping:)
    /// @brief      Remove stored image files no longer referenced by any card
    /// @details    Scans the attachment directory and deletes filenames absent from the supplied
    ///             reference set
    ///
    /// @param[in]  fileNames  Filenames still referenced by the current board cards
    ///
    /// @return     (Void) removes unreferenced files when the attachment directory can be read
    ///
    /// @pre        fileNames represents the current persisted card attachment references
    /// @post       Referenced files remain; unreferenced files are removed when possible
    ///
    static func removeUnreferencedFiles(keeping fileNames: Set<String>) {

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { /* App Documents directory */

            return
        }

        let directoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true) /* Attachment folder URL */

        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { /* Files available for cleanup */

            return
        }

        for fileURL in files where !fileNames.contains(fileURL.lastPathComponent) {

            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    

    ///
    /// @fcn        CardAttachmentStore.attachmentsDirectory()
    /// @brief      Return the app's photo attachment directory
    /// @details    Resolves Documents/CardAttachments and creates the directory if it does not
    ///             already exist
    ///
    /// @return     (URL) directory used to store imported card images
    ///
    /// @throws     CocoaError when the Documents directory is unavailable or directory creation
    ///             fails
    ///
    /// @pre        The app has access to its user Documents directory
    /// @post       The returned directory exists and is ready to receive files
    ///
    private static func attachmentsDirectory() throws -> URL {

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { /* App Documents directory */

            throw CocoaError(.fileNoSuchFile)
        }

        let directoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true) /* Attachment folder URL */

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL
    }
}


///
/// Identifies the attachment sources available from card detail
///
/// @section    Purpose
///     Provide stable source identities and display metadata for the attachment picker
///
enum CardAttachmentSource: String, CaseIterable, Identifiable {

    case trello
    case confluence
    case jira
    case file
    case documentScanner
    case qrCode
    case camera
    case photoOrVideo
    case link
    case clipboard

    ///
    /// @fcn        CardAttachmentSource.id
    /// @brief      Expose the source token as its stable identity
    /// @details    Reuses the enum raw value for picker rows
    ///
    /// @return     (String) attachment-source identifier
    ///
    var id: String { rawValue } /* Stable picker identity */

    ///
    /// @fcn        CardAttachmentSource.title
    /// @brief      Return the display title for an attachment source
    /// @details    Maps each source case to its picker-row label
    ///
    /// @return     (String) display text defined for the source
    ///
    var title: String { /* User-facing attachment-source label */
        switch self {

            case .trello:         "Trello"
            case .confluence:     "Confluence"
            case .jira:           "Jira"
            case .file:           "File"
            case .documentScanner:"Document scanner"
            case .qrCode:         "QR code"
            case .camera:         "Camera"
            case .photoOrVideo:   "Photo or video"
            case .link:           "Link"
            case .clipboard:      "Clipboard"
        }
    }

    ///
    /// @fcn        CardAttachmentSource.symbolName
    /// @brief      Return the SF Symbol name for an attachment source
    /// @details    Maps each source case to the icon shown in the picker
    ///
    /// @return     (String) SF Symbol identifier for the source
    ///
    var symbolName: String { /* SF Symbol for the picker row */
        switch self {

            case .trello:         "square.split.2x2"
            case .confluence:     "water.waves"
            case .jira:           "checkmark.circle"
            case .file:           "paperclip"
            case .documentScanner:"doc.viewfinder"
            case .qrCode:         "qrcode.viewfinder"
            case .camera:         "camera"
            case .photoOrVideo:   "photo.on.rectangle"
            case .link:           "link"
            case .clipboard:      "doc.on.clipboard"
        }
    }
}


///
/// Presents supported attachment sources and dispatches the selected action
///
/// @section    Purpose
///     Connect photo selection, link entry, clipboard import, and unavailable source notices
///
struct CardAttachmentSourceSheet: View {

    @Binding var photoSelection: [PhotosPickerItem] /* Current Photos-picker selection */
    
    let onAddLink: ()          -> Void /* Callback opening manual link entry */
    let onPasteClipboard: ()   -> Void /* Callback importing clipboard images or a link */
    let onComingSoon: (String) -> Void /* Callback reporting unsupported source */

    @Environment(\.dismiss) private var dismiss /* Sheet dismissal action */

    
    ///
    /// @fcn        CardAttachmentSourceSheet.select(_:)
    /// @brief      Dispatch the action associated with one attachment source
    /// @details    Invokes link or clipboard callbacks, leaves photo selection to PhotosPicker, and
    ///             reports unsupported source choices
    ///
    /// @param[in]  source  Selected attachment source
    ///
    /// @return     (Void) invokes the matching callback or system picker
    ///
    /// @pre        source is one of the available attachment sources
    /// @post       The corresponding callback is invoked where applicable
    ///
    private func select(_ source: CardAttachmentSource) {

        switch source {

            case .link:
                onAddLink()
            case .clipboard:
                onPasteClipboard()
                dismiss()
            case .photoOrVideo:
                break
            default:
                onComingSoon(source.title)
        }
    }


    ///
    /// @fcn        CardAttachmentSourceSheet.body
    /// @brief      Build the attachment-source picker
    /// @details    Presents PhotosPicker for media and dispatches the other source actions
    ///
    /// @return     (some View) attachment-source sheet
    ///
    /// @pre        The selection binding and action callbacks are configured
    /// @post       Selecting a source dispatches its supported action
    ///
    var body: some View { /* Attachment-source picker */
        
        NavigationStack {
            
            List {

                ForEach(CardAttachmentSource.allCases) { source in

                    if source == .photoOrVideo {

                        PhotosPicker(selection: $photoSelection, maxSelectionCount: 12, matching: .any(of: [.images, .videos])) {
                            Label(source.title, systemImage: source.symbolName)
                                .foregroundStyle(.primary)
                        }

                    } else {

                        Button {
                            select(source)
                        } label: {
                            Label(source.title, systemImage: source.symbolName)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            .navigationTitle("Add attachment from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }

        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


///
/// Collects and validates a web address to attach to a card
///
/// @section    Purpose
///     Accept a valid URL and return it to the owning card-detail view
///
struct CardLinkAttachmentSheet: View {

    let onSave: (URL) -> Void /* Callback receiving the validated URL */

    @Environment(\.dismiss) private var dismiss /* Sheet dismissal action */
    @State private var urlDraft = "" /* User-entered URL text */

    ///
    /// @fcn        CardLinkAttachmentSheet.validatedURL
    /// @brief      Return the parsed URL when the current draft is valid
    /// @details    Delegates URL validation to CardAttachmentStore
    ///
    /// @return     (URL?) valid HTTP or HTTPS URL, or nil for invalid draft text
    ///
    private var validatedURL: URL? { /* Parsed URL when the draft is valid */
        CardAttachmentStore.webURL(from: urlDraft)
    }


    ///
    /// @fcn        CardLinkAttachmentSheet.body
    /// @brief      Build the manual web-link form
    /// @details    Collects URL text and enables submission only when validation succeeds
    ///
    /// @return     (some View) link-entry sheet with Cancel and Add actions
    ///
    /// @pre        The save callback and dismissal environment are available
    /// @post       A valid submitted URL is passed to the save callback
    ///
    var body: some View {               /* Manual web-link form */

        NavigationStack {

            Form {

                Section("Link") {

                    TextField("https://example.com", text: $urlDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveLink)
                }
            }

            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveLink()
                    }

                    .disabled(validatedURL == nil)
                }
            }
        }

        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }


    ///
    /// @fcn        CardLinkAttachmentSheet.saveLink()
    /// @brief      Submit the entered URL when it passes web-link validation
    /// @details    Calls the owner callback and dismisses the sheet for a valid draft
    ///
    /// @return     (Void) invokes the save callback and dismisses the sheet
    ///
    /// @pre        The draft has a validated URL
    /// @post       The callback receives that URL and the sheet is dismissed
    ///
    private func saveLink() {

        guard let validatedURL else { /* Validated attachment URL */

            return
        } /* Require a valid web address */

        onSave(validatedURL)

        dismiss()
    }
}


extension KanbanListTint {
    var color: Color {
        switch self {
        case .neutral: Color(.systemGray6)
        case .blue: Color.blue.opacity(0.12)
        case .green: Color.green.opacity(0.12)
        case .orange: Color.orange.opacity(0.12)
        case .red: Color.red.opacity(0.12)
        }
    }
}

extension ItemAccent {
    var color: Color {
        switch self {
            case .teal: .teal
            case .blue: .blue
            case .purple: .purple
            case .rose: .pink
            case .orange: .orange
            case .green: .green
        }
    }

    var darkHeaderColor: Color {
        switch self {
            case .teal: Color(red: 0.08, green: 0.28, blue: 0.28)
            case .blue: Color(red: 0.08, green: 0.20, blue: 0.36)
            case .purple: Color(red: 0.24, green: 0.12, blue: 0.32)
            case .rose: Color(red: 0.34, green: 0.12, blue: 0.22)
            case .orange: Color(red: 0.34, green: 0.20, blue: 0.08)
            case .green: Color(red: 0.12, green: 0.28, blue: 0.14)
        }
    }

    func bannerColor(increasedContrast: Bool) -> Color {
        Color(uiColor: UIColor { traits in
            let tint = UIColor(self.color).resolvedColor(with: traits)
            let base = UIColor.systemBackground.resolvedColor(with: traits)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            var baseRed: CGFloat = 0
            var baseGreen: CGFloat = 0
            var baseBlue: CGFloat = 0
            tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &alpha)
            let amount: CGFloat = increasedContrast ? 0.10 : 0.16
            return UIColor(
                red: baseRed * (1 - amount) + red * amount,
                green: baseGreen * (1 - amount) + green * amount,
                blue: baseBlue * (1 - amount) + blue * amount,
                alpha: 1
            )
        })
    }
}

struct ItemAppearanceMark: View {
    let appearance: ItemAppearance?

    var body: some View {
        if let icon = appearance?.icon {
            Image(systemName: icon.rawValue)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

private struct ItemBannerBackground: ViewModifier {
    let appearance: ItemAppearance?
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if let background = appearance?.background {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background.bannerColor(increasedContrast: contrast == .increased))
        } else {
            content
        }
    }
}

extension View {
    func itemBannerBackground(_ appearance: ItemAppearance?) -> some View {
        modifier(ItemBannerBackground(appearance: appearance))
    }
}

/// Shows the complete selected image at its natural aspect ratio, using the existing thumbnail loader.
struct ItemPicturePreview: View {
    let attachment: KanbanAttachment?
    var title: String? = nil

    private var accessibleDescription: String {
        let text = [title, attachment?.caption]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return text.isEmpty ? "Picture" : text
    }
    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
            } else {
                Label(attachment == nil ? "Choose picture" : (unavailable ? "Picture unavailable" : "Loading picture…"), systemImage: "photo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Color.secondary.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibleDescription)
        .accessibilityValue(attachment == nil ? "Choose picture" : (unavailable ? "Picture unavailable" : ""))
        .accessibilityAddTraits(.isImage)
        .task(id: attachment) {
            image = nil
            unavailable = false
            guard let attachment else { return }
            let result = await Task.detached(priority: .utility) {
                Result { try CardAttachmentStore.coverThumbnail(for: attachment) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let thumbnail): image = thumbnail
            case .failure: unavailable = true
            }
        }
    }
}

/// Shared row menu; changes only the canonical record's display metadata.
struct ItemDisplayFormatMenu: View {
    let card: KanbanCard
    let onUpdate: (KanbanCard) -> Void

    var body: some View {
        Menu {
            ForEach(ItemDisplayFormat.allCases) { format in
                Button {
                    var updated = card
                    updated.displayFormat = format
                    onUpdate(updated)
                } label: {
                    Label(format.title, systemImage: card.displayFormat == format ? "checkmark" : format.symbol)
                }
            }
        } label: {
            Label("Display as", systemImage: "rectangle.on.rectangle")
        }
    }
}

/// Shared optional preview profile control; Unchanged is stored as no override.
struct CardDisplayProfilePicker: View {
    @Binding var selection: BoardCardDetail?
    var body: some View {
        Picker("Card display", selection: $selection) {
            Text("Unchanged").tag(Optional<BoardCardDetail>.none)
            Text("Detailed").tag(Optional(BoardCardDetail.detailed))
            Text("Compact").tag(Optional(BoardCardDetail.compact))
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("appearance.cardDisplay")
    }
}

extension ListPreviewTextColor {
    var color: Color {
        let light: (CGFloat, CGFloat, CGFloat)
        let dark: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .graphite: light = (0.22, 0.25, 0.29); dark = (0.78, 0.81, 0.85)
        case .blue: light = (0.16, 0.32, 0.56); dark = (0.59, 0.75, 0.98)
        case .teal: light = (0.12, 0.40, 0.42); dark = (0.52, 0.83, 0.83)
        case .green: light = (0.19, 0.39, 0.23); dark = (0.60, 0.84, 0.62)
        case .plum: light = (0.40, 0.26, 0.48); dark = (0.81, 0.67, 0.92)
        case .rose: light = (0.55, 0.25, 0.34); dark = (0.95, 0.65, 0.73)
        case .amber: light = (0.47, 0.34, 0.13); dark = (0.92, 0.78, 0.49)
        }
        return Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

struct ItemAppearanceSheet: View {
    let title: String
    let onSave: (ItemAppearance?) -> Bool
    let onOpenCover: (() -> Void)?
    let onOpenLayout: (() -> Void)?
    let showsListBackground: Bool
    let onSaveDisplay: ((ItemAppearance?, ItemDisplayFormat) -> Bool)?
    @State private var draftDisplay: ItemDisplayFormat?
    @State private var draft: ItemAppearance
    @Environment(\.dismiss) private var dismiss

    init(title: String, appearance: ItemAppearance?, onOpenCover: (() -> Void)? = nil, onOpenLayout: (() -> Void)? = nil, showsListBackground: Bool = false, displayFormat: ItemDisplayFormat? = nil, onSaveDisplay: ((ItemAppearance?, ItemDisplayFormat) -> Bool)? = nil, onSave: @escaping (ItemAppearance?) -> Bool) {
        self.title = title
        self.showsListBackground = showsListBackground
        self.onSave = onSave
        self.onOpenCover = onOpenCover
        self.onOpenLayout = onOpenLayout
        self.onSaveDisplay = onSaveDisplay
        _draftDisplay = State(initialValue: displayFormat)
        _draft = State(initialValue: appearance ?? ItemAppearance())
    }

    var body: some View {
        NavigationStack {
            Form {
                if draftDisplay != nil {
                    Section("Display as") {
                        Picker("Format", selection: Binding(
                            get: { draftDisplay ?? .card }, set: { draftDisplay = $0 }
                        )) {
                            ForEach(ItemDisplayFormat.allCases) { format in
                                Label(format.title, systemImage: format.symbol).tag(format)
                            }
                        }
                        .accessibilityIdentifier("appearance.displayFormat")
                        Text("Changes how this item is displayed. Its writing, actions, dates, and photos are retained.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if draftDisplay == .picture {
                            Text("Picture uses the selected Card Cover. Save this format, then choose a picture in Card Cover if needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if draftDisplay == .card {
                    Section("Subtitle") {
                        Toggle("Hide subtitle when empty", isOn: Binding(
                            get: { draft.hideEmptySubtitle == true },
                            set: { draft.hideEmptySubtitle = $0 ? true : nil }
                        ))
                        .accessibilityIdentifier("appearance.hideEmptySubtitle")
                        Text("Filled subtitles stay visible. Use Add subtitle from the card menu to write one when the empty field is hidden.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let onOpenLayout {
                        Section("Card Layout") {
                            Button("Layout", systemImage: "rectangle.3.group", action: onOpenLayout)
                                .accessibilityIdentifier("appearance.layout")
                        }
                    }
                }
                if showsListBackground || (draftDisplay != nil && draftDisplay != .divider) {
                    Section("Card display") {
                        CardDisplayProfilePicker(selection: $draft.cardDetail)
                        Text(showsListBackground
                             ? "Unchanged follows the Board or existing layout. Individual items can override this List."
                             : "Unchanged follows the List, then Board. This changes the list preview; opening the item still shows its full contents.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if showsListBackground || draftDisplay != .divider {
                    PreviewTextColorsSection(titleColor: $draft.cardTitleColor, textColor: $draft.cardTextColor,
                        explanation: showsListBackground
                            ? "Unchanged follows the Board. Individual Cards and Notes can override this List. Colors affect previews only."
                            : "Unchanged follows the List, then Board. Colors affect previews only; opened editors, dates, labels, and status indicators keep their own styling.")
                }
                Section("Preview") {
                    HStack {
                        ItemAppearanceMark(appearance: draft)
                        Text(title).font(.headline)
                    }
                }
                Section("Leading icon") {
                    Picker("Icon", selection: $draft.icon) {
                        Text("None").tag(Optional<PersonalCollectionIcon>.none)
                        ForEach(PersonalCollectionIcon.allCases, id: \.self) { icon in
                            Label(icon.title, systemImage: icon.rawValue).tag(Optional(icon))
                        }
                    }
                    .accessibilityIdentifier("appearance.icon")
                }
                if showsListBackground {
                    Section("List background") {
                        Picker("Background color", selection: $draft.listBackground) {
                            Text("Use Board default").tag(Optional<KanbanListTint>.none)
                            ForEach(KanbanListTint.allCases) { tint in
                                Text(tint.title).tag(Optional(tint))
                            }
                        }
                        .accessibilityIdentifier("appearance.listBackground")
                        Text("A subtle color behind the items in this Board’s list. Use Board default inherits the Board’s choice; Default keeps a neutral background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Banner background") {
                    Picker("Background color", selection: $draft.background) {
                        Text(showsListBackground ? "Use Board default" : "None").tag(Optional<ItemAccent>.none)
                        ForEach(ItemAccent.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }
                    }
                    .accessibilityIdentifier("appearance.background")
                    Text("A soft color across the full header and upper bar, independent of the icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let onOpenCover {
                    Section("Card Cover") {
                        Button("Card Cover", systemImage: "photo", action: onOpenCover)
                            .accessibilityIdentifier("appearance.cover")
                        Text("Choose or remove a cover. Cover changes apply immediately and are separate from saving or canceling the icon and background draft.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Reset appearance") { draft = ItemAppearance() }
                        .accessibilityIdentifier("appearance.reset")
                    Text("Icon and background are optional and independent. Titles, covers, photos, and other content stay unchanged. Save applies your choices; Cancel discards them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let appearance = draft.isEmpty ? nil : draft
                        let saved: Bool
                        if let draftDisplay, let onSaveDisplay {
                            saved = onSaveDisplay(appearance, draftDisplay)
                        } else {
                            saved = onSave(appearance)
                        }
                        if saved { dismiss() }
                    }
                    .accessibilityIdentifier("appearance.save")
                }
            }
        }
        .databaseActivityOverlay()
    }
}

struct CardPhotoGallery: View {
    let photos: [KanbanAttachment]
    @Binding var photoSelection: [PhotosPickerItem]
    let onOpen: (KanbanAttachment) -> Void
    let onCaption: (UUID, String) -> Bool
    let onReorder: ([UUID]) -> Bool
    let onRemove: (KanbanAttachment) -> Void
    let onSetCover: (UUID) -> Void

    @ScaledMetric(relativeTo: .body) private var photoWidth = 220
    @ScaledMetric(relativeTo: .body) private var photoHeight = 180
    @State private var captionPhoto: KanbanAttachment?
    @State private var removalPhoto: KanbanAttachment?
    @State private var showsArrangement = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Gallery").font(.headline)
                    Spacer()
                    galleryControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gallery").font(.headline)
                    galleryControls
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        photoTile(photo, index: index)
                    }
                }
            }
            .accessibilityIdentifier("photoGallery.row")
        }
        .accessibilityIdentifier("photoGallery")
        .sheet(item: $captionPhoto) { photo in
            CardPhotoCaptionSheet(photo: photo) { onCaption(photo.id, $0) }
                .databaseActivityOverlay()
        }
        .sheet(isPresented: $showsArrangement) {
            CardPhotoArrangementSheet(photos: photos, onReorder: onReorder)
                .databaseActivityOverlay()
        }
        .confirmationDialog("Remove this photo?", isPresented: Binding(
            get: { removalPhoto != nil },
            set: { if !$0 { removalPhoto = nil } }
        ), titleVisibility: .visible) {
            if let photo = removalPhoto {
                Button("Remove photo", role: .destructive) {
                    onRemove(photo)
                    removalPhoto = nil
                }
            }
            Button("Cancel", role: .cancel) { removalPhoto = nil }
        } message: {
            Text("Removes the photo and its caption from this item. Photos retained elsewhere are kept.")
        }
    }

    private var galleryControls: some View {
        HStack(spacing: 12) {
            Button("Arrange", systemImage: "arrow.left.arrow.right") {
                showsArrangement = true
            }
            .disabled(photos.count < 2)
            .accessibilityLabel("Arrange gallery photos")
            .accessibilityIdentifier("photoGallery.arrange")
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 12, matching: .images) {
                Label("Add photos", systemImage: "photo.badge.plus")
            }
            .accessibilityIdentifier("photoGallery.add")
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    private func photoTile(_ photo: KanbanAttachment, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { onOpen(photo) } label: {
                CardCoverPreview(attachment: photo, height: photoHeight, unavailableTitle: "Photo unavailable")
                    .overlay(alignment: .bottomLeading) {
                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(3)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.95)],
                                                   startPoint: .top, endPoint: .bottom)
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo \(index + 1)")
            .accessibilityValue(photo.caption ?? "No caption")
            .accessibilityHint("Opens the full photo. Touch and hold to drag it to another gallery position.")
            .accessibilityIdentifier("photoGallery.photo.\(photo.id)")
            .draggable("plenact.gallery.\(photo.id.uuidString)")
            .dropDestination(for: String.self) { items, _ in
                guard items.count == 1,
                      let token = items.first,
                      token.hasPrefix("plenact.gallery."),
                      let id = UUID(uuidString: String(token.dropFirst("plenact.gallery.".count))),
                      let source = photos.firstIndex(where: { $0.id == id }),
                      id != photo.id else { return false }
                var ids = photos.map(\.id)
                ids.remove(at: source)
                ids.insert(id, at: index)
                return onReorder(ids)
            }
            HStack {
                Text("Photo \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(photo.caption == nil ? "Add caption" : "Edit caption", systemImage: "text.bubble") {
                        captionPhoto = photo
                    }
                    Button("Move earlier", systemImage: "arrow.left") { movePhoto(index, by: -1) }
                        .disabled(index == 0)
                    Button("Move later", systemImage: "arrow.right") { movePhoto(index, by: 1) }
                        .disabled(index == photos.count - 1)
                    Button("Set as Cover", systemImage: "photo") { onSetCover(photo.id) }
                    Button("Remove photo", systemImage: "trash", role: .destructive) { removalPhoto = photo }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for photo \(index + 1)")
                .accessibilityIdentifier("photoGallery.options.\(photo.id)")
            }
        }
        .frame(width: photoWidth)
    }

    private func movePhoto(_ index: Int, by offset: Int) {
        var ids = photos.map(\.id)
        ids.swapAt(index, index + offset)
        _ = onReorder(ids)
    }
}

struct CardPhotoCaptionSheet: View {
    let photo: KanbanAttachment
    let onSave: (String) -> Bool
    @State private var caption: String
    @Environment(\.dismiss) private var dismiss

    init(photo: KanbanAttachment, onSave: @escaping (String) -> Bool) {
        self.photo = photo
        self.onSave = onSave
        _caption = State(initialValue: photo.caption ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardCoverPreview(attachment: photo, height: 180, unavailableTitle: "Photo unavailable")
                }
                Section("Caption") {
                    TextField("Optional caption", text: $caption, axis: .vertical)
                        .accessibilityIdentifier("photoGallery.captionField")
                    Text("Shown over the bottom of the photo. Clear the text to remove its caption.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Photo caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if onSave(caption) { dismiss() } }
                        .accessibilityIdentifier("photoGallery.saveCaption")
                }
            }
        }
    }
}

struct CardPhotoArrangementSheet: View {
    let photos: [KanbanAttachment]
    let onReorder: ([UUID]) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        HStack(spacing: 12) {
                            CardCoverPreview(attachment: photo, height: 64, unavailableTitle: "Photo unavailable")
                                .frame(width: 80)
                            Text(photo.caption ?? "Photo \(index + 1)")
                        }
                    }
                    .onMove { source, destination in
                        var ids = photos.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        _ = onReorder(ids)
                    }
                } footer: {
                    Text("Drag the handles to arrange photos. The cover stays separate. Changes are saved as you move photos.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

///
/// Displays a square thumbnail for an attached card item
///
/// @section    Purpose
///     Provide a compact preview for photos, videos, and web links in card details
///
struct CardAttachmentThumbnail: View {

    let attachment: KanbanAttachment /* Attachment represented by the thumbnail */

    ///
    /// @fcn        CardAttachmentThumbnail.body
    /// @brief      Build a square preview for an attached card item
    /// @details    Shows a link or video symbol, a cropped local photo, or a photo placeholder when
    ///             the local image cannot be loaded
    ///
    /// @return     (some View) square attachment thumbnail or missing-photo fallback
    ///
    /// @pre        attachment contains metadata for a local image file
    /// @post       Rendering does not modify the attachment or stored image data
    ///
    var body: some View { /* Local image, remote link, or media fallback */

        GeometryReader { geometry in
        Group {

            if let url = attachment.url { /* Remote link URL */
                
                VStack(spacing: 6) {
                    
                    Image(systemName: "link")
                        .font(.title2)
                    
                    Text(url.host ?? url.absoluteString)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                
            } else if attachment.kind == .video {
                
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                
            } else if let imageURL = CardAttachmentStore.imageURL(for: attachment), /* Local photo file URL */
                      
               let image = UIImage(contentsOfFile: imageURL.path) { /* Decoded local image */
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                
            } else {

                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .clipped()
        }

        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}


///
/// Displays an attached photo or video at a larger size
///
/// @section    Purpose
///     Allow users to inspect local media after opening its card-detail thumbnail
///
struct CardAttachmentPreview: View {

    let attachment: KanbanAttachment        /* The media attachment to preview */

    @Environment(\.dismiss) private var dismiss /* Preview dismissal action */

    ///
    /// @fcn        CardAttachmentPreview.body
    /// @brief      Build a large preview for an attached photo
    /// @details    Plays a local video or displays a local photo scaled to fit, with a fallback
    ///             view when the referenced file is unavailable
    ///
    /// @return     (some View) navigable image preview with a Done action
    ///
    /// @pre        attachment identifies a photo previously imported for a card
    /// @post       The preview is shown without modifying the image or its metadata
    ///
    var body: some View { /* Video or image preview with unavailable fallback */

        NavigationStack {
            Group {

                if attachment.kind == .video,
                   
                   let videoURL = CardAttachmentStore.fileURL(for: attachment) { /* Local video file URL */
                    VideoPlayer(player: AVPlayer(url: videoURL))
                    
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let imageURL = CardAttachmentStore.imageURL(for: attachment),
                               let image = UIImage(contentsOfFile: imageURL.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                ContentUnavailableView("Photo unavailable", systemImage: "photo")
                            }
                            if let caption = attachment.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }

            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .topBarTrailing) {
                    
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }

        .presentationDetents([.large])
    }
}


// Board colors are a draft until Save; applying to all clears only List color overrides.
/// Collection photos live separately from card attachments so attachment cleanup cannot remove them.
enum CollectionBackgroundPhotoStore {
    private static let cache = NSCache<NSString, UIImage>()
    static func directory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = root.appendingPathComponent("PlenactCollectionBackgrounds", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func preparedPhoto(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return jpeg
    }
    static func save(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".jpg"
        try data.write(to: directory().appendingPathComponent(name), options: .atomic)
        return name
    }
    static func image(named name: String?) -> UIImage? {
        guard let name, name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".jpg") else { return nil }
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let directory = try? directory(), let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString, cost: Int(image.size.width * image.size.height * 4))
        cache.totalCostLimit = 32 * 1024 * 1024
        return image
    }
    static func remove(_ name: String) {
        guard name == URL(fileURLWithPath: name).lastPathComponent, let directory = try? directory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        cache.removeObject(forKey: name as NSString)
    }
}

/// Stationary procedural surfaces keep the interface readable without extra bundled images.
struct CollectionBackgroundSurface: View {
    var background: CollectionBackground? = nil
    var draftPhoto: Data? = nil
    private var colors: [Color] {
        switch background?.preset {
        case .linen: [Color(red: 0.47, green: 0.39, blue: 0.31), Color(red: 0.64, green: 0.54, blue: 0.43)]
        case .sage: [Color(red: 0.19, green: 0.33, blue: 0.27), Color(red: 0.39, green: 0.52, blue: 0.38)]
        case .ocean: [Color(red: 0.08, green: 0.26, blue: 0.36), Color(red: 0.21, green: 0.49, blue: 0.53)]
        case .plum: [Color(red: 0.26, green: 0.18, blue: 0.31), Color(red: 0.49, green: 0.34, blue: 0.43)]
        case .sandstone: [Color(red: 0.43, green: 0.28, blue: 0.22), Color(red: 0.65, green: 0.47, blue: 0.34)]
        case .midnight: [Color(red: 0.10, green: 0.13, blue: 0.23), Color(red: 0.22, green: 0.27, blue: 0.38)]
        default: [Color(red: 0.10, green: 0.18, blue: 0.25), Color(red: 0.22, green: 0.34, blue: 0.38)]
        }
    }
    private var photo: UIImage? {
        guard background?.preset == .photo else { return nil }
        if let draftPhoto { return UIImage(data: draftPhoto) }
        return CollectionBackgroundPhotoStore.image(named: background?.photoFileName)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    Color.black.opacity(0.30)
                    LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .center)
                } else if let preset = background?.preset, preset != .photo {
                    Canvas { context, size in
                        var grain = Path()
                        for row in stride(from: 0, through: Int(size.height), by: 7) {
                            for column in stride(from: 0, through: Int(size.width), by: 7) {
                                let shift = (row * 17 + column * 13) % 5
                                grain.addEllipse(in: CGRect(x: CGFloat(column + shift), y: CGFloat(row), width: 0.8, height: 0.8))
                            }
                        }
                        context.fill(grain, with: .color(.white.opacity(0.12)))
                        if preset == .linen || preset == .sandstone {
                            var weave = Path()
                            for x in stride(from: 0, through: Int(size.width), by: 4) {
                                weave.move(to: CGPoint(x: x, y: 0)); weave.addLine(to: CGPoint(x: CGFloat(x), y: size.height))
                            }
                            context.stroke(weave, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct BoardAppearanceSheet: View {
    @State private var photoSelection: PhotosPickerItem?
    @State private var draftPhoto: Data?
    @State private var isImportingPhoto = false
    @State private var backgroundError: String?
    let allowsCollectionBackground: Bool
    @State private var draft: BoardAppearance
    @State private var applyToAll = false
    @State private var draftPresentation: BoardPresentation
    let onSavePresentation: ((BoardPresentation) -> Void)?
    let onSave: (BoardAppearance, Bool) -> Bool
    @Environment(\.dismiss) private var dismiss

    init(appearance: BoardAppearance, presentation: BoardPresentation = .standard,
         onSavePresentation: ((BoardPresentation) -> Void)? = nil,
         allowsCollectionBackground: Bool = false,
         onSave: @escaping (BoardAppearance, Bool) -> Bool) {
        self.allowsCollectionBackground = allowsCollectionBackground
        _draft = State(initialValue: appearance)
        _draftPresentation = State(initialValue: presentation)
        self.onSavePresentation = onSavePresentation
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if allowsCollectionBackground { collectionBackgroundSection }
                if onSavePresentation != nil {
                    Section("Display") {
                        Picker("Board presentation", selection: $draftPresentation) {
                            ForEach(BoardPresentation.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                    }
                }
                Section("Card display") {
                    CardDisplayProfilePicker(selection: $draft.cardDetail)
                    Text("Unchanged keeps the existing layout. Compact emphasizes titles and small indicators; Detailed includes supporting content. Lists and individual items can override this choice.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                PreviewTextColorsSection(titleColor: $draft.cardTitleColor, textColor: $draft.cardTextColor,
                    explanation: "Unchanged keeps the app defaults. Lists and individual Cards and Notes can override each color independently. Colors affect previews only.")
                Section("List banner color") {
                    Picker("Banner background", selection: $draft.bannerBackground) {
                        Text("Default").tag(Optional<ItemAccent>.none)
                        ForEach(ItemAccent.allCases, id: \.self) { color in
                            Text(color.rawValue.capitalized).tag(Optional(color))
                        }
                    }
                }
                Section("List background color") {
                    Picker("List background", selection: $draft.listBackground) {
                        Text("Default").tag(Optional<KanbanListTint>.none)
                        ForEach(KanbanListTint.allCases.filter { $0 != .neutral }) { tint in
                            Text(tint.title).tag(Optional(tint))
                        }
                    }
                }
                Section("Card background color") {
                    Picker("Card background", selection: $draft.cardBackground) {
                        Text("Default").tag(Optional<KanbanListTint>.none)
                        ForEach(KanbanListTint.allCases.filter { $0 != .neutral }) { tint in
                            Text(tint.title).tag(Optional(tint))
                        }
                    }
                    Text("A soft tint for Card and Note rows on this Board. Pictures, Dividers, and individual item banner colors are retained.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Apply to all Lists", isOn: $applyToAll)
                    Text(applyToAll
                         ? "Save replaces color overrides in active and archived Lists. Icons and content are retained."
                         : "New Lists and Lists using Board defaults inherit these colors. Individually chosen List colors are retained.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Board Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAppearance()
                    }
                    .disabled(isImportingPhoto)
                }
            }
        }
        .task(id: photoSelection) {
            guard let photoSelection else { return }
            isImportingPhoto = true
            defer { isImportingPhoto = false }
            do {
                guard let data = try await photoSelection.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let prepared = try await Task.detached(priority: .userInitiated) { try CollectionBackgroundPhotoStore.preparedPhoto(data) }.value
                try Task.checkCancellation()
                draftPhoto = prepared
                draft.collectionBackground = CollectionBackground(preset: .photo)
            } catch is CancellationError { }
            catch { backgroundError = "This photo could not be opened. Please choose another image." }
        }
        .alert("Background", isPresented: Binding(get: { backgroundError != nil }, set: { if !$0 { backgroundError = nil } })) {
            Button("OK", role: .cancel) { backgroundError = nil }
        } message: { Text(backgroundError ?? "") }
        .databaseActivityOverlay()
    }

    private var collectionBackgroundSection: some View {
        Section("Background") {
            CollectionBackgroundSurface(background: draft.collectionBackground, draftPhoto: draftPhoto)
                .frame(height: 136)
                .overlay(alignment: .bottomLeading) {
                    Text(draft.collectionBackground?.preset.title ?? "Plenact default")
                        .font(.headline).foregroundStyle(.white).padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Picker("Background", selection: Binding(
                get: { draft.collectionBackground?.preset },
                set: { preset in
                    guard preset != draft.collectionBackground?.preset else { return }
                    if preset != .photo { draftPhoto = nil }
                    draft.collectionBackground = preset.map { CollectionBackground(preset: $0) }
                }
            )) {
                Text("Default").tag(Optional<CollectionBackgroundPreset>.none)
                ForEach(CollectionBackgroundPreset.allCases.filter { $0 != .photo }) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
                if draft.collectionBackground?.preset == .photo {
                    Text("Your photo").tag(Optional(CollectionBackgroundPreset.photo))
                }
            }
            .accessibilityIdentifier("appearance.collectionBackground")
            .disabled(isImportingPhoto)
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label("Choose photo", systemImage: "photo")
            }
            .disabled(isImportingPhoto)
            if isImportingPhoto { ProgressView("Preparing photo…") }
            Text("A personal background for this Board or List. Photos stay on this device. Week and Day views keep their Plenact background.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func saveAppearance() {
        guard !isImportingPhoto else { return }
        var updated = draft
        var importedName: String?
        do {
            if allowsCollectionBackground, updated.collectionBackground?.preset == .photo, let draftPhoto {
                let name = try CollectionBackgroundPhotoStore.save(draftPhoto)
                importedName = name
                updated.collectionBackground?.photoFileName = name
            }
            if onSave(updated, applyToAll) {
                onSavePresentation?(draftPresentation)
                dismiss()
            } else if let importedName { CollectionBackgroundPhotoStore.remove(importedName) }
        } catch {
            if let importedName { CollectionBackgroundPhotoStore.remove(importedName) }
            backgroundError = "The background could not be saved. Your current appearance has been kept."
        }
    }

}

/// Optional preview colors share one control at Board, List, Card, and Note scope.
struct PreviewTextColorsSection: View {
    @Binding var titleColor: ListPreviewTextColor?
    @Binding var textColor: ListPreviewTextColor?
    let explanation: String

    private func picker(_ title: String, selection: Binding<ListPreviewTextColor?>) -> some View {
        Picker(title, selection: selection) {
            Text("Unchanged").tag(Optional<ListPreviewTextColor>.none)
            ForEach(ListPreviewTextColor.allCases) { color in
                Text(color.title).tag(Optional(color))
            }
        }
    }
    var body: some View {
        Section("Preview text colors") {
            picker("Title color", selection: $titleColor)
            picker("Supporting text color", selection: $textColor)
            VStack(alignment: .leading, spacing: 6) {
                Text("Card or note title").font(.headline).foregroundStyle(titleColor?.color ?? .primary)
                Text("Subtitle or note preview").font(.subheadline).foregroundStyle(textColor?.color ?? .secondary)
            }.padding(.vertical, 8)
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
