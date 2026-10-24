// --------------------------------------------------------------------------------------------------
// @file       CardLocationSearch.swift
// @brief      Apple Maps place search for Card location drafts
// @details    Searches MapKit, previews selectable results on a map, and returns a place name and
//             address only after explicit selection. Card persistence remains with the parent editor.
//
// --------------------------------------------------------------------------------------------------
import MapKit
import SwiftUI


///
/// Retains the display and coordinate values of one map-search result
///
/// @section    Purpose
///     Separates provider objects from observable presentation state and creates an unambiguous
///     place-and-address string compatible with the existing optional Card location field.
///
struct CardLocationSearchResult: Identifiable, Hashable, Sendable
{


    let id:        UUID
    let name:      String
    let address:   String
    let latitude:  Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D
    {

        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }


    var savedLocation: String
    {

        let title = CardLocation.normalized(name)
        let address = CardLocation.normalized(address)
        if let title, let address, title.caseInsensitiveCompare(address) != .orderedSame
        {

            return "\(title), \(address)"
        }

        if let value = title ?? address
        {

            return value
        }

        return String(format: "%.6f, %.6f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }



    ///
    /// @fcn        CardLocationSearchResult.init
    /// @brief      Initialize an independently testable map result
    /// @details    Retains explicit coordinates and visible place text under a stable result identity.
    /// @param[in]  id        Identity used for map markers and result-list selection
    /// @param[in]  name      Place name returned by the provider
    /// @param[in]  address   Address text used to distinguish similarly named places
    /// @param[in]  latitude  Coordinate latitude
    /// @param[in]  longitude Coordinate longitude
    /// @return     (CardLocationSearchResult) initialized place result
    ///
    init(id: UUID = UUID(), name: String, address: String, latitude: Double, longitude: Double)
    {

        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }



    ///
    /// @fcn        CardLocationSearchResult.init
    /// @brief      Extract a place's name, formatted address, and valid coordinate from MapKit
    /// @details    Uses current address APIs on iOS 26 and newer with a compatible iOS 17 fallback.
    ///             Invalid coordinates are excluded instead of rendering an unusable marker.
    /// @param[in]  item MapKit search result to represent
    /// @return     (CardLocationSearchResult?) retained result, or nil for invalid coordinates
    ///
    init?(item: MKMapItem)
    {

        let coordinate: CLLocationCoordinate2D
        let address: String
        if #available(iOS 26.0, *)
        {

            coordinate = item.location.coordinate
            address = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
            ?? item.address?.fullAddress ?? ""
        }

        else
        {

            coordinate = item.placemark.coordinate
            address = item.placemark.title ?? ""
        }

        guard CLLocationCoordinate2DIsValid(coordinate) else
        {

            return nil
        }

        self.init(name: item.name ?? address, address: address,
            latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

}



///
/// Coordinates cancellable place searches without persisting Card changes
///
/// @section    Purpose
///     Keeps loading, empty, and failure states explicit; stale responses cannot replace a newer
///     query or selection. An injected search function supports deterministic offline tests.
///
@MainActor
final class CardLocationSearchModel: ObservableObject
{


    typealias Searcher = @MainActor (String, MKCoordinateRegion?) async throws -> [CardLocationSearchResult]

    ///
    /// Identifies the current place-search presentation state
    ///
    /// @section    Purpose
    ///     Distinguishes an empty query, an active request, results, no matches, and service failure.
    ///
    enum Phase
    {

        case idle, searching, results, empty, failed
    }


    @Published var query: String
    {

        didSet
        {

            if query != oldValue
            {

                cancel()
            }

        }

    }

    @Published private(set) var results: [CardLocationSearchResult] = []
    @Published private(set) var phase: Phase = .idle
    @Published var selectedID: UUID?
    private let searcher: Searcher
    private var revision = UUID()

    var selectedResult: CardLocationSearchResult?
    {

        results.first
        {

            $0.id == selectedID
        }

    }



    ///
    /// @fcn        CardLocationSearchModel.init
    /// @brief      Initialize a search session from the current location draft
    /// @details    Does not search until the view starts its debounced request or the caller asks.
    /// @param[in]  query    Initial place or address text
    /// @param[in]  searcher Optional test provider; nil uses Apple's native local search
    /// @return     (CardLocationSearchModel) initialized search session
    ///
    init(query: String = "", searcher: Searcher? = nil)
    {

        self.query = query
        self.searcher = searcher ?? Self.findPlaces
    }



    ///
    /// @fcn        CardLocationSearchModel.cancel
    /// @brief      Invalidate pending results and clear the previous selection
    /// @details    Called immediately when query text changes or the search view departs, keeping
    ///             a previously selected place from being used for a different query.
    /// @return     (Void) resets the session without editing the Card or parent draft
    ///
    func cancel()
    {

        revision = UUID()
        results = []
        selectedID = nil
        phase = .idle
    }



    ///
    /// @fcn        CardLocationSearchModel.search
    /// @brief      Fetch matches for the latest query and accept only the current response
    /// @details    Empty queries reset the session. Cancellation and late responses leave newer
    ///             state intact; failures retain manual-entry access in the parent editor.
    /// @param[in]  region Optional visible map region used as a search hint
    /// @return     (Void) publishes current matches or an honest empty/failure state
    ///
    func search(in region: MKCoordinateRegion? = nil) async
    {

        cancel()
        guard let query = CardLocation.normalized(query) else
        {

            return
        }

        let requestRevision = revision
        phase = .searching
        do
        {

            let matches = try await searcher(query, region)
            guard revision == requestRevision else
            {

                return
            }

            guard !Task.isCancelled else
            {

                cancel()
                return
            }

            results = matches
            phase = matches.isEmpty ? .empty : .results
        }

        catch
        {

            guard revision == requestRevision else
            {

                return
            }

            guard !Task.isCancelled else
            {

                cancel()
                return
            }

            phase = .failed
        }

    }



    ///
    /// @fcn        CardLocationSearchModel.findPlaces
    /// @brief      Perform an Apple Maps search for an explicit place or address
    /// @details    Requests address and point-of-interest results without user-location access.
    ///             Cancels the MapKit request when its view task is superseded or dismissed.
    /// @param[in]  query  Normalized place search text
    /// @param[in]  region Optional visible-region hint, omitted for a world-scale map
    /// @return     ([CardLocationSearchResult]) valid selectable place results
    /// @throws     Propagates MapKit search failures and cancellation
    ///
    private static func findPlaces(_ query: String, region: MKCoordinateRegion?) async throws -> [CardLocationSearchResult]
    {

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let region, region.span.latitudeDelta < 120, region.span.longitudeDelta < 180
        {

            request.region = region
        }

        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler
        {

            try await search.start()
        }

        onCancel:
        {

            Task
            {

            @MainActor in
                search.cancel()
            }

        }

        return response.mapItems.compactMap(CardLocationSearchResult.init(item:))
    }

}



///
/// Lets a user find a place on Apple Maps before filling the location draft
///
/// @section    Purpose
///     Combines a native map, debounced place search, and explicit result selection. Use this
///     location fills the parent draft; neither searching nor leaving the view saves the Card.
///
struct CardLocationSearchView: View
{


    let onSelect: (String) -> Void
    @StateObject private var model: CardLocationSearchModel
    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var retryRevision = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    ///
    /// @fcn        CardLocationSearchView.init
    /// @brief      Start a map-search screen using the current location draft
    /// @details    A supplied model keeps tests independent of live search service responses.
    /// @param[in]  query    Initial location text to search
    /// @param[in]  model    Optional injected search session
    /// @param[in]  onSelect Callback invoked only by Use this location
    /// @return     (CardLocationSearchView) initialized place picker
    ///
    @MainActor
    init(query: String, model: CardLocationSearchModel? = nil, onSelect: @escaping (String) -> Void)
    {

        self.onSelect = onSelect
        self._model = StateObject(wrappedValue: model ?? CardLocationSearchModel(query: query))
    }



    ///
    /// @fcn        CardLocationSearchView.searchFeedback
    /// @brief      Show current result rows or the appropriate request status
    /// @details    Place rows select a marker without accepting it; empty and failed searches
    ///             remain retryable and never substitute the query for a chosen result.
    /// @return     (some View) result list or compact search-state feedback
    ///
    @ViewBuilder
    private var searchFeedback: some View
    {

        switch model.phase
        {

        case .results:
            List(model.results)
            {

            place in
                Button
                {

                    model.selectedID = place.id
                }

                label:
                {

                    HStack
                    {

                        VStack(alignment: .leading, spacing: 3)
                        {

                            Text(place.name)
                            .font(.body.weight(.medium))
                            Text(place.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        }

                        Spacer(minLength: 8)
                        if model.selectedID == place.id
                        {

                            Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        }

                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(place.savedLocation)
                .accessibilityAddTraits(model.selectedID == place.id ? .isSelected : [])
            }
            .listStyle(.plain)
            .accessibilityIdentifier("card.location.search.results")
        case .searching:
            ProgressView("Searching places…")
            .padding()
        case .empty:
            Text("No places found. Try a place name, city, or street address.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
        case .failed:
            VStack(spacing: 8)
            {

                Text("Search is unavailable. Try again or enter the address manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button("Try again")
                {

                    retryRevision += 1
                }

            }
            .padding()
        case .idle:
            Text("Search for a place or address, then select a result.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
        }

    }



    ///
    /// @fcn        CardLocationSearchView.body
    /// @brief      Present the searchable map with an explicit location-selection action
    /// @details    Queries are debounced and cancelled when superseded. Selected markers and rows
    ///             share one identity; leaving without Use this location preserves the parent draft.
    /// @return     (some View) native Apple Maps search and selection workspace
    ///
    var body: some View
    {

        GeometryReader
        {

        geometry in
            VStack(spacing: 0)
            {

                Map(position: $position, selection: $model.selectedID)
                {

                    ForEach(model.results)
                    {

                    place in
                        Marker(place.name, coordinate: place.coordinate)
                        .tag(place.id)
                    }

                }
                .mapControls
                {

                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .onEnd)
                {

                    visibleRegion = $0.region
                }
                .accessibilityIdentifier("card.location.search.map")
                searchFeedback
                .frame(maxHeight: model.phase == .results ? min(220, geometry.size.height * 0.4) : nil)
            }

        }
        .navigationTitle("Find on map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Place or address")
        .onSubmit(of: .search)
        {

            retryRevision += 1
        }
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
        .safeAreaInset(edge: .bottom)
        {

            VStack(alignment: .leading, spacing: 8)
            {

                if let selected = model.selectedResult
                {

                    Text(selected.savedLocation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                Button
                {

                    guard let selected = model.selectedResult else
                    {

                        return
                    }

                    onSelect(selected.savedLocation)
                    dismiss()
                }

                label:
                {

                    Text("Use this location")
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedResult == nil)
                .accessibilityIdentifier("card.location.search.use")
            }
            .padding()
            .background(.regularMaterial)
        }
        .task(id: [model.query, String(retryRevision)])
        {

            do
            {

                try await Task.sleep(for: .milliseconds(350))
            }

            catch
            {

                return
            }

            await model.search(in: visibleRegion)
        }
        .onChange(of: model.results)
        {

        _, _ in
            position = .automatic
        }
        .onChange(of: model.selectedID)
        {

        _, _ in
            guard let selected = model.selectedResult else
            {

                return
            }

            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25))
            {

                position = .region(MKCoordinateRegion(center: selected.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)))
            }

        }
        .onDisappear
        {

            model.cancel()
        }

    }

}

