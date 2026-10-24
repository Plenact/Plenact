# Card locations

Cards can retain an optional place name or address. In Card Details, **Add location**
opens a local draft. Save applies the normalized text; Cancel leaves the Card
unchanged. Existing locations have a pencil edit action and a Remove location
button in the editor.

Tap the saved location to open the place in the preferred maps provider. Plenact
passes the text as a place-search query and leaves all subsequent actions to Maps.
Opening a saved place does not request directions or device location access.

**Maps → Preferred maps app** appears in Account settings and Plan settings, using
their existing Save/Cancel drafts. Apple Maps is the default, including older
profiles. Google Maps uses its official universal place-search URL, which opens
its installed app or website according to the operating system's link handling.
The current preference is read whenever the location row is displayed.

Location text is optional Codable Card content and is preserved through copies,
moves, dates-only edits, and normal workspace persistence. Changes appear as
**Location** in Card edit history. Locked and read-only Cards retain their place
link while hiding edit controls; rejected saves retain the editor draft.

## Find on map

The location editor includes **Find on map**, which opens an Apple Maps search
inside Plenact. It starts with the draft's current text and searches after a brief
pause in typing. The visible map region supplies a search hint; no device-location
permission, external app launch, or API key is required.

Results appear as selectable map markers and rows with place names and addresses.
The user selects a result, then taps **Use this location** to fill the parent draft.
The Card is unchanged until the parent editor's Save action. Cancel or leaving the
map preserves the previous draft. The saved location includes the name and address
without duplicating identical text, and still opens in the user's preferred maps app.

Search uses native MapKit local search. New queries cancel earlier view tasks;
revision checks reject stale responses even if a provider finishes late. Changing
the query clears the previous selection. Empty and failed searches explain their
state, offer retry where useful, and leave manual address entry available.

Deterministic tests inject a provider to cover selection, failure, empty queries,
late responses, cancellation, and rendered results without depending on live search.

## Example destinations and existing Cards

The Jmr starter routine now assigns these requested destinations:

- **Gym:** Planet Fitness, 1971 S Koeller St, Oshkosh, WI 54902.
- **Work:** Mercury Marine Plant 33, 505 Marion Road, Oshkosh, WI 54901.

A one-time update runs after the workspace loads. It fills empty locations on
editable Cards titled exactly Gym or Work, ignoring case and outer whitespace.
It includes retained active calendar Lists, active personal collections, and saved
routines. Existing custom locations, Notes, dividers, locked Cards, and archived
contents remain unchanged. Location additions use ordinary Card edit history.

The update prepares and encodes every document before writing. Original Board,
calendar, personal-collection, and routine documents are retained under
`Plenact.ExampleCardLocations.Backup.v1`. A failed verified write restores those
original documents. `Plenact.ExampleCardLocations.Applied.v1` is marked only after
success, so subsequent location removals are not automatically filled again.
This does not establish a location rule for future manually created Cards.

Bundled routine revision 5 adds locations to saved Jmr examples when missing.
Routine application copies location text into fresh Cards and dated weeks.

Address references:

- [Planet Fitness Oshkosh](https://www.planetfitness.com/gyms/oshkosh-wi)
- [Mercury Marine routing guide: Plant 33](https://www.supplier.mercurymarine.com/content/dam/mercury-isupplier/documentation/International%20Routing%20Guide%202023.pdf)

## Provider references

- [Apple MapKit local search](https://developer.apple.com/documentation/mapkit/mklocalsearch)
- [Apple Maps URLs](https://developer.apple.com/documentation/mapkit/unified-map-urls)
- [Google Maps URLs: search and app/web behavior](https://developers.google.com/maps/documentation/urls/get-started)
