// --------------------------------------------------------------------------------------------------
// @file       CoverLibrary.swift
// @brief      Offline illustration catalog and cover selection
// @details    Provides bundled artwork discovery and previews alongside explicit attachment or
//             library cover choices.
//
// --------------------------------------------------------------------------------------------------
import AVKit
import Foundation
import ImageIO
import PencilKit
import PhotosUI
import SwiftUI
import UIKit


///
/// Categories for the offline illustration library
///
/// @section    Purpose
///     Organize artwork without imposing categories on people's cards
///
enum CoverCategory: String, CaseIterable, Identifiable
{


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
    var id: String
    {
        rawValue
    }  /* Stable category identity */


    ///
    /// @fcn        CoverCategory.images
    /// @brief      Supply 50 ordered covers per category
    /// @details    Categories describe artwork only, not card ownership or semantics
    /// @return     ([ExampleCoverImage]) explicit curated category membership
    ///
    var images: [ExampleCoverImage]
    {

        switch self
        {

        case .home:
            [
                .readingCorner, .tidyHome, .laundryDay, .homeRepairs, .cozySofa, .cleanKitchen, .petCare, .deskLamp,
                .morningRoutine, .bedroomReset, .familyHome, .windowCleaning, .mailAndLetters, .bathroomCare,
                .homeBudget, .closetOrganizing, .shoeRack, .houseKeys, .vacuumCleaning, .movingDay, .homeSecurity,
                .recyclingDay, .lightbulbMoment, .householdTools, .homeLaundryBasket, .catCompanion, .dogWalk,
                .puppyPlay, .catNap, .fishTank, .breakfastTable, .linenSorting, .storageBoxes, .familyCalendar,
                .plantShelf, .weekendChores, .balconyBreak, .homeNetwork, .roomRefresh, .organizedEntryway,
                .blanketCorner, .trashDay, .dishwashing, .windowGarden, .homeDelivery, .kitchenSupplies,
                .sharedHousehold, .shoeCleaning, .batteryCheck, .seasonalDecor
            ]
        case .nature:
            [
                .garden, .wateringPlants, .forestPath, .flowerBouquet, .sunrise, .herbPots, .rainyDay, .butterfly,
                .seedlingCare, .appleOrchard, .flowerBed, .gardenTools, .birdWatching, .sunflowerDay, .moonlitGarden,
                .autumnLeaves, .snowyMorning, .rainbowSky, .cloudWatching, .riverFlow, .greenhouse, .cactusCare,
                .springRain, .honeyBees, .starrySky, .woodlandHare, .rabbitGarden, .pondFish, .songbirdMorning,
                .butterflyMeadow, .ladybugLeaf, .dragonflyPond, .pineForest, .moonAndCloud, .sunAfterRain,
                .winterForest, .mushroomWalk, .orchardHarvest, .wildflowerTrail, .riverStones, .fernCorner, .roseGarden,
                .stormySky, .mistyHills, .gardenHarvest, .birdFeeder, .pottingDay, .gardenFence, .natureObservation,
                .fallWalk
            ]
        case .work:
            [
                .workspace, .studyBooks, .writingNotes, .projectPlanning, .learning, .calendarPlan, .coding, .goalSteps,
                .teamMeeting, .researchSession, .inboxReview, .presentationDay, .mathPractice, .scienceLab,
                .languageStudy, .examPreparation, .careerGrowth, .remoteOffice, .projectMilestone, .documentReview,
                .focusSession, .ideaMap, .engineeringPlan, .schoolDay, .certificateGoal, .dailyPriorities,
                .weeklyReview, .writingDraft, .proofreading, .videoConference, .phoneInterview, .jobSearch,
                .portfolioBuilding, .businessPlan, .financialReview, .codingPractice, .softwareRelease, .productDesign,
                .teamRetrospective, .mentoring, .historyStudy, .geographyStudy, .biologyStudy, .physicsPractice,
                .chemistryNotes, .onlineCourse, .libraryVisit, .studyGroup, .presentationRehearsal, .learningMilestone
            ]
        case .food:
            [
                .freshProduce, .cooking, .groceryBag, .coffeeBreak, .baking, .breakfast, .pantry, .market, .teaTime,
                .soupSeason, .fruitBowl, .pizzaNight, .saladPreparation, .mealPrep, .breadMaking, .birthdayCake,
                .waterBottle, .shoppingCart, .weeklyMenu, .recipeBook, .packedLunch, .farmersMarket, .foodStorage,
                .familyDinner, .kitchenTimer, .appleSnack, .vegetableChopping, .smoothieBreak, .coffeeBeans, .herbalTea,
                .hotChocolate, .cookieBaking, .pancakeMorning, .sandwichLunch, .pastaEvening, .riceBowl, .spiceShelf,
                .oliveOil, .freezerPrep, .leftoversPlan, .dinnerReservation, .shoppingList, .budgetGroceries,
                .checkoutTime, .localBakery, .freshFish, .vegetarianMeal, .fruitPicnic, .celebrationToast,
                .recipeTesting
            ]
        case .travel:
            [
                .mountains, .camping, .coastalWalk, .cycling, .travelBag, .trainTrip, .sailboat, .picnic, .roadTrip,
                .cityBreak, .airportDeparture, .passportReady, .beachDay, .kayaking, .hikingBoots, .skiWeekend,
                .mapAndRoute, .compassPoint, .waterfallWalk, .campfireEvening, .stargazingTrip, .bikeRoute,
                .fishingTrip, .travelCamera, .weekendGetaway, .trainPlatform, .busJourney, .ferryCrossing,
                .motorcycleRide, .camperVan, .hotelCheckin, .beachSunrise, .seasidePicnic, .mountainCabin,
                .forestCamping, .lakeKayak, .sunsetSailing, .islandEscape, .nationalPark, .travelItinerary,
                .packingChecklist, .travelBudget, .roadsideStop, .scenicOverlook, .waterfrontStroll, .urbanExploration,
                .museumDay, .travelPostcard, .snowAdventure, .returningHome
            ]
        case .creativity:
            [
                .painting, .music, .conversation, .sharedMeal, .photography, .crafting, .gift, .gameNight,
                .potterySession, .sewingProject, .knittingTime, .pianoPractice, .guitarSession, .creativeWriting,
                .filmNight, .letterToFriend, .communityTime, .volunteerDay, .partyPlanning, .familyMemories,
                .puzzleBreak, .stagePerformance, .colorPalette, .sketchbook, .friendshipCall, .watercolorPractice,
                .paperCollage, .origamiTime, .embroideryWork, .woodworking, .creativeBrainstorm, .poetryReading,
                .storyOutline, .songwriting, .choirPractice, .singingSession, .violinPractice, .drumRhythm,
                .recordingSession, .photoEditing, .portraitSession, .streetPhotography, .handmadeGift, .birthdayLetter,
                .boardGameEvening, .familyGame, .bookClub, .communityGarden, .charityProject, .celebrationMemories
            ]
        case .health:
            [
                .morningStretch, .walkingBreak, .runningRoute, .yogaPractice, .strengthSession, .swimmingLaps,
                .heartHealth, .hydrationHabit, .balancedMeal, .sleepHabit, .meditationPractice, .breathingPause,
                .healthAppointment, .medicineReminder, .recoverySteps, .wheelchairJourney, .gentleMovement,
                .danceWorkout, .sportsPractice, .boxingSession, .balanceTraining, .outdoorFitness, .selfCare,
                .healthyBoundaries, .wellnessJournal, .sunriseWalk, .parkJog, .stairWorkout, .cyclingSession,
                .indoorCycling, .pilatesPractice, .mobilitySession, .restDay, .physicalTherapy, .medicalCheckup,
                .visionCare, .dentalCare, .bloodPressure, .vitaminRoutine, .mindfulEating, .proteinPrep, .healthySnack,
                .waterReminder, .sleepSchedule, .bodyScan, .stressRelease, .mentalHealth, .supportSession,
                .smallProgress, .energyCheck
            ]
        case .rest:
            [
                .quietMorning, .cozyEvening, .slowWeekend, .readingPause, .reflectionJournal, .peacefulBreath,
                .unplugTime, .candlelight, .warmBath, .softMusic, .mindfulMoment, .gratitudeList, .sunsetRest,
                .cloudDreams, .moonlight, .teaAndThoughts, .restfulSpace, .rainyWindow, .peacefulLake, .forestRetreat,
                .personalPause, .freshStart, .smallVictories, .kindnessMoment, .intentionalDay, .afternoonPause,
                .weekendReading, .hammockTime, .cabinQuiet, .seasideCalm, .mountainStillness, .rainListening,
                .slowBreathing, .sunriseReflection, .moonJournal, .selfCompassion, .hopefulMorning, .calmFocus,
                .lettingGo, .quietConfidence, .joyfulMoment, .comfortCorner, .peacefulSleep, .screenFreeEvening,
                .journalingPrompt, .freshPerspective, .patientProgress, .softSunlight, .clearMind, .thankfulEvening
            ]
        }

    }

}


///
/// Original bundled illustrations for examples and explicit user cover choices
///
/// @section    Purpose
///     Keep example drafts side-effect-free and independent of personal media files
///
enum ExampleCoverImage: String, Codable, CaseIterable, Sendable
{


    case garden, mountains, workspace
    case readingCorner = "reading-corner", tidyHome = "tidy-home", laundryDay = "laundry-day", homeRepairs =
            "home-repairs"
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
    var title: String
    {
        rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }  /* Readable artwork name */

    private static let tagCatalog: [String: [String]] =
    {

        guard
        let url = Bundle.main.url(
            forResource: "cover-tags", withExtension: "json", subdirectory: "CardCoverImages"),
        let data = try? Data(contentsOf: url),
        let tags = try? JSONDecoder().decode([String: [String]].self, from: data)
        else
        {
            return [:]
        }

        return tags
    }()
    var tags: [String]
    {
        Self.tagCatalog[rawValue] ?? rawValue.components(separatedBy: "-")
    }


    ///
    /// @fcn        ExampleCoverImage.search
    /// @brief      Filter cover choices by album and search text
    /// @details    Applies the optional album restriction and each cover's shared query matching rules without
    ///             changing the catalog.
    ///
    /// @param[in]  query  User-entered search text
    /// @param[in]  album  Optional cover-category restriction
    ///
    /// @return     ([Self]) covers satisfying the optional album restriction and search query
    ///
    static func search(_ query: String, in album: CoverCategory? = nil) -> [Self]
    {

        (album?.images ?? CoverCategory.allCases.flatMap(\.images)).filter
        {
            $0.matches(query)
        }

    }


    ///
    /// @fcn        ExampleCoverImage.matches
    /// @brief      Match a built-in cover against descriptive search text
    /// @details    Uses the cover's searchable metadata and normalized query, allowing an empty query to retain the
    ///             cover.
    ///
    /// @param[in]  query  User-entered search text
    ///
    /// @return     (Bool) true when the cover's searchable metadata matches the normalized query
    ///
    func matches(_ query: String) -> Bool
    {

        let normalized = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let terms = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter
        {
            !$0.isEmpty
        }

        let searchable = ([title] + tags).joined(separator: " ").folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = searchable.components(separatedBy: CharacterSet.alphanumerics.inverted).filter
        {
            !$0.isEmpty
        }

        return terms.allSatisfy
        {
            term in
            words.contains
            {
                $0.hasPrefix(term)
            }

        }

    }


    ///
    /// @fcn        ExampleCoverImage.url
    /// @brief      Resolve the immutable bundled illustration
    /// @details    Only known resource names can be resolved; no remote downloads occur
    /// @return     (URL?) bundled PNG location
    ///
    var url: URL?
    {  /* Bundled artwork resource URL */

        Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "CardCoverImages")
    }

}


///
/// Offline visual library with category filters and explicit cover selection
///
/// @section    Purpose
///     Browse all 400 offline illustrations without downloading or analyzing card content
///
struct CardCoverLibrary: View
{


    let selectedImage: ExampleCoverImage?           /* Current library cover, if any                    */
    let onSelect:      (ExampleCoverImage) -> Bool  /* Owner validates and publishes an explicit choice */
    @State private var query = ""
    @State private var category: CoverCategory?           /* nil shows All Covers                       */
    @Environment(\.dynamicTypeSize) private var textSize  /* Use a single column for accessibility text */
    @Environment(\.dismiss) private var dismiss           /* Cancel or close a successful selection     */

    ///
    /// @fcn        CardCoverLibrary.body
    /// @brief      Offer category browsing, named previews, and a non-destructive Cancel path
    /// @details    No selection or attachment is created until a person taps an illustration
    /// @return     (some View) adaptive offline library
    ///
    private var albumPicker: some View
    {

        Picker("Cover album", selection: $category)
        {

            Text("All Covers").tag(Optional<CoverCategory>.none)
            ForEach(CoverCategory.allCases)
            {
                category in
                Text(category.rawValue).tag(Optional(category))
            }

        }

        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 160, minHeight: 44, alignment: .leading)
        .accessibilityIdentifier("coverLibrary.album")
    }

    private var searchField: some View
    {

        HStack(spacing: 6)
        {

            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search covers", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityLabel("Search selected cover album")
            .accessibilityIdentifier("coverLibrary.search")
            if !query.isEmpty
            {

                Button
                {

                    query = ""
                }
                label:
                {

                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear cover search")
            }

        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .frame(minWidth: 130)
    }


    private var filteredImages: [ExampleCoverImage]
    {

        ExampleCoverImage.search(query, in: category)
    }


    var body: some View
    {  /* Offline cover library interface */

        NavigationStack
        {

            ScrollView
            {

                VStack(alignment: .leading, spacing: 16)
                {

                    ViewThatFits(in: .horizontal)
                    {

                        HStack(spacing: 12)
                        {

                            albumPicker;
                            searchField
                        }

                        VStack(alignment: .leading, spacing: 8)
                        {

                            albumPicker;
                            searchField
                        }

                    }

                    Text("\(filteredImages.count) covers").font(.caption).foregroundStyle(.secondary)
                    if filteredImages.isEmpty
                    {

                        ContentUnavailableView.search(text: query)
                    }

                    Text("Choose an illustration to use as this card's cover. Your existing photos stay attached.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: textSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.adaptive(minimum: 150))], spacing: 16
                    )
                    {

                        ForEach(filteredImages, id: \.self)
                        {
                            image in
                            Button
                            {

                                if onSelect(image)
                                {


                                    dismiss()
                                }

                            }
                            label:
                            {

                                VStack(alignment: .leading, spacing: 8)
                                {

                                    CardCoverPreview(
                                        attachment: KanbanAttachment(
                                            mediaKind: .photo, exampleImage: image
                                        ), height: 96)
                                    Label(
                                        image.title,
                                        systemImage: selectedImage == image ? "checkmark.circle.fill" : "photo"
                                    )
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
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

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
struct CardCoverPreview: View
{


    let attachment: KanbanAttachment  /* Explicitly selected photo                                    */
    var height:     CGFloat = 128     /* Fixed preview height, independent of source image dimensions */
    var unavailableTitle = "Cover unavailable"
    @State private var image: UIImage?      /* Downsampled image for this presentation */
    @State private var unavailable = false  /* Explicit missing/invalid-image feedback */

    ///
    /// @fcn        CardCoverPreview.body
    /// @brief      Render the selected cover without hiding the card's text identity
    /// @details    Task identity/cancellation prevents a previous image from replacing a changed cover
    /// @return     (some View) decorative cropped image or visible unavailable notice
    ///
    var body: some View
    {  /* Loaded cover preview or fallback */

        GeometryReader
        {
            geometry in
            Group
            {

                if let image
                {  /* Successfully decoded cover thumbnail */


                    Image(uiImage: image).resizable().scaledToFill()
                }
                else if unavailable
                {


                    Label(unavailableTitle, systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                else
                {


                    Color.secondary.opacity(0.08)
                }

            }

            .frame(width: geometry.size.width, height: height)
            .clipped()
        }

        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(!unavailable)
        .task(id: attachment)
        {

            image = nil
            unavailable = false

            let result = await Task.detached(priority: .utility)
            {  /* Background thumbnail decode result */

                Result
                {
                    try CardAttachmentStore.coverThumbnail(for: attachment)
                }

            } .value
            guard !Task.isCancelled else
            {


                return
            }


            switch result
            {


            case .success(let thumbnail):
                image = thumbnail /* Decoded cover thumbnail */
            case .failure:
                unavailable = true
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
struct CardCoverPicker: View
{


    let photos:     [KanbanAttachment]           /* Current attached photo choices       */
    let selectedID: UUID?                        /* Current cover, if explicitly enabled */
    let onSelect:   (UUID) -> Void               /* Owner validates and saves selection  */
    @Environment(\.dismiss) private var dismiss  /* Cancel or return after choosing      */

    ///
    /// @fcn        CardCoverPicker.body
    /// @brief      Show recognizable photo choices and a clear Cancel path
    /// @details    Cancel does not mutate a card; choosing a row reuses its existing attachment
    /// @return     (some View) navigable cover-photo chooser
    ///
    var body: some View
    {  /* Attached-photo cover choices */

        NavigationStack
        {

            List
            {

                ForEach(Array(photos.enumerated()), id: \.element.id)
                {
                    index, photo in
                    Button
                    {

                        onSelect(photo.id)
                        dismiss()
                    }
                    label:
                    {

                        VStack(alignment: .leading, spacing: 8)
                        {

                            CardCoverPreview(attachment: photo)
                            Label(
                                                                                    "Photo \(index + 1)",
                                                                                    systemImage: selectedID == photo.id ? "checkmark.circle.fill" : "photo")
                        }

                    }

                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1)\(selectedID == photo.id ? ", current cover" : "")")
                    .accessibilityHint("Use this attached photo as the card cover.")
                }

            }

            .navigationTitle("Choose Card Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {

                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel")
                    {
                        dismiss()
                    }

                }

            }

        }

    }

}
