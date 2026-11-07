# Plenact platform languages and shared desktop architecture

**Date:** November 7, 2026  
**Context:** Justin Reina and Alex's Plenact development collaboration.  
**Decision:** Use C++ with Qt for the planned Windows, Mac, and Linux desktop applications.  
**Status:** Desktop technology direction selected; implementation details and supported configurations require prototypes and validation.

This reference records the reasoning behind our platform-language choices, the alternatives considered, and the costs we accept. It also records how Plenact can serve both as a supported product and as a framework for Justin's professional learning.

The comparisons below are engineering judgments for Plenact, not measured development-time estimates or universal rankings of programming languages. Framework support and licensing references were consulted for this discussion; release-specific requirements must be checked again when implementation and distribution begin.

## 1. The decision in one view

| Product | Starting language and interface | Decision status |
| --- | --- | --- |
| Plenact-iOS / iPadOS | Swift and SwiftUI, retaining existing UIKit integrations where needed | Continue the existing implementation |
| Plenact-Android | Kotlin and Jetpack Compose | Planned direction; validate with an Android prototype |
| Plenact-Windows | C++ and Qt | Selected desktop direction; supersedes the earlier provisional C# plan |
| Plenact-Mac | C++ and Qt | Selected desktop direction; supersedes the earlier provisional SwiftUI Mac plan |
| Plenact-Linux | C++ and Qt | Selected desktop direction; supersedes the earlier gtkmm proposal |
| Plenact-Web | HTML and CSS with TypeScript for browser behavior | Planned direction; JavaScript fundamentals remain essential |
| Shared backend / API | PHP, initially considering Bluehost | Provisional until hosting, deployment, persistence, and operational capabilities are verified |

For the desktop interface, Qt Quick/QML is the preferred initial prototype direction. The confirmed decision is C++/Qt across desktops; the detailed UI architecture, Qt modules, compiler baseline, and distribution configuration remain to be established.

QML is another language to learn. “C++ for all desktops” means C++ is the principal desktop application language, not that every interface declaration, build file, or platform integration will be written in C++.

These product names describe intended clients. This document does not create new repositories, build targets, services, or release commitments.

## 2. What we are optimizing for

Plenact has two complementary purposes:

1. Deliver a dependable application that can be developed, tested, released, updated, and supported across platforms.
2. Give Justin a substantial codebase through which to practice, learn, and demonstrate professional engineering skills.

The product needs a manageable maintenance burden. The learning effort needs understandable boundaries and opportunities for Justin to take ownership. Choosing more languages does not automatically produce a better portfolio, and choosing one language does not automatically produce a simpler product.

Our priority is a working, supportable product developed progressively, with learning built into that process. We should avoid making every platform a simultaneous language experiment.

**Justin's professionally fluent language is C.** C++ familiarity and embedded experience do not imply fluency in modern C++, Qt, desktop UI programming, or cross-platform deployment. An earlier discussion overstated that fluency; this decision uses C as the actual starting point.

## 3. Languages, toolkits, and architecture solve different problems

The language determines how we express application behavior. A UI toolkit supplies controls, rendering, events, and related application facilities. Architecture determines which responsibilities can be shared and which must remain platform-specific.

For example:

- C++ with Qt and C++ with WinUI are different application-development approaches despite sharing a language.
- A C# Windows application could share a C++ data core, but that introduces a language-interoperability boundary.
- Swift code can implement the same portable contract as C++ without sharing its source files.
- A shared Qt interface still needs adaptations and tests for each operating system.

The goal is not simply to minimize the language count. It is to choose boundaries that reduce repeated work without concealing important platform behavior.

## 4. Why retain Swift for iOS and iPadOS?

Plenact already has a working Swift application with established behavior and migration/export evidence. Retaining that investment lets us continue improving the product instead of restarting it in a different language.

SwiftUI remains the main interface direction, with existing UIKit integrations adapted as needed. Native Apple frameworks provide an appropriate environment for mobile lifecycle, interaction, accessibility, and operating-system integration. Apple's multiplatform tooling can also share suitable SwiftUI code across Apple platforms, which initially made a Swift Mac version attractive. [Apple multiplatform guidance](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target)

The desktop C++ decision does not authorize rewriting iOS or replacing its persistence implementation. A shared C++ component could be evaluated later, but must demonstrate a benefit that exceeds its integration and migration cost.

## 5. Why Kotlin and Jetpack Compose for Android?

The planned Android direction is Kotlin with Jetpack Compose. Android's documentation follows a Compose-first approach, making it a relevant native starting point. [Android Compose guidance](https://developer.android.com/develop/ui/compose/first)

For Plenact, the expected benefit is direct access to Android UI, lifecycle, accessibility, permissions, background execution, and system services. Compose's declarative UI approach also offers conceptual parallels with SwiftUI, although the frameworks and their behavior are not interchangeable.

Android supports C/C++ through the NDK. A shared native core is possible, with Kotlin/Java communication typically using JNI. That bridge adds ownership, error-handling, threading, and build concerns. We have not established that it would reduce Plenact's Android development effort. [Android NDK concepts](https://developer.android.com/ndk/guides/concepts), [Android JNI guidance](https://github.com/android/ndk/wiki/JNI)

For now, Android remains a native Kotlin client of the shared contract. Qt's mobile support is an available capability, not a commitment to move our mobile applications onto Qt.

## 6. Why the desktop decision changed during the discussion

We initially considered a platform-specific approach:

- Swift/SwiftUI for Mac, benefiting from the iOS investment.
- C#/.NET with WinUI for Windows, benefiting from Microsoft's application ecosystem.
- C++ with gtkmm for Linux, providing a C++ path without Qt.

Those remain technically credible alternatives. Microsoft supports WinUI development in C# and C++, and gtkmm provides a C++ interface to GTK. [Windows app development](https://developer.microsoft.com/en-us/windows/apps/build-a-windows-app), [gtkmm reference](https://gnome.pages.gitlab.gnome.org/gtkmm/)

However, that arrangement creates three desktop interface implementations and several application-development environments. Once we considered the long-term cost of feature parity and support, the value of sharing substantial desktop code became more important.

Justin's initial hesitation about Qt came from seeing it adopted indiscriminately in a previous workplace. That was not a technical finding that Qt was unsuitable for Plenact. We revisited the framework on its merits and selected it for a specific responsibility: the shared desktop application.

## 7. Qt's value proposition for Plenact

Qt supports Windows, macOS, and Linux. Qt Quick provides a declarative interface approach that can work with C++ application logic. Exact supported operating systems, architectures, compilers, and modules depend on the selected release. [Qt supported platforms](https://doc.qt.io/qt-6/supported-platforms.html), [Qt Quick introduction](https://www.qt.io/product/qt6/qml-book/ch06-controls-introduction)

The expected value is a shared desktop product containing much of the same:

- Board layout and navigation.
- Card, Note, checklist, and attachment editing.
- Studio and artwork interfaces.
- Local data handling and synchronization behavior.
- Validation and automated test infrastructure.
- Feature fixes and accessibility improvements.

The greatest prospective reward is maintenance capacity. An improvement to a shared editor can benefit all three desktop versions together, rather than requiring independent UI implementations.

This is an opportunity for reuse, not a promise that all code will be shared or every change will work everywhere without adaptation. It must be demonstrated by real Plenact screens and workflows.

### Other desktop frameworks considered

Qt is not the only way to share a desktop application:

- **C# with Avalonia:** offers a shared Windows, Mac, and Linux application approach. This could also reduce repeated implementation. Choosing Qt instead reflects our selected C++ learning direction and the framework we intend to prototype; shared-code benefits are not exclusive to C++ or Qt. [Avalonia platform support](https://docs.avaloniaui.net/docs/supported-platforms)
- **C++ with wxWidgets:** offers a common desktop API using native platform controls. It remains a credible alternative if our Qt prototype reveals a better fit for that approach. We have not measured either framework against Plenact's rich editing and artwork needs. [wxWidgets overview](https://wxwidgets.org/about/)
- **C++ with gtkmm, or C with GTK:** would provide a Linux application route, including a possible bridge from Justin's existing C fluency. We chose the shared Qt desktop direction instead of introducing a separate Linux interface implementation. [GTK language bindings](https://www.gtk.org/docs/language-bindings/)
- **C++ with separate native interfaces:** could keep substantial C++ domain logic while using different platform UI frameworks. That can increase platform alignment, but still requires multiple interfaces and potentially language bridges.

The selected architecture should therefore be compared with other complete architectures, not with an assumption that every alternative necessarily requires three unrelated codebases.

## 8. Why include Mac in the shared Qt application?

The Mac application is expected to have a desktop-first interface, substantially different from the iPhone application. Likely desktop concerns include multiple windows, larger Board arrangements, sidebars, menus, keyboard navigation, drag-and-drop, and editing layouts designed for a mouse and keyboard.

If we chose SwiftUI for Mac, we could reuse suitable iOS models, validation, persistence, and some view components. We would still need to implement and maintain much of the desktop interaction model.

With that interface difference, the more valuable UI-sharing relationship may be **Mac–Windows–Linux**, rather than **Mac–iPhone**. A shared desktop application lets us develop desktop behavior together.

There is a real cost: some business logic already implemented in Swift must also be implemented in C++. Native Apple integration may require more adaptation than a Swift/AppKit implementation. We accept those prospective costs in exchange for reducing the number of independent desktop applications.

Qt styles can help presentation, but visual resemblance does not prove native interaction quality. Mac menus, shortcuts, accessibility, window behavior, file handling, and system integration still need deliberate design and testing. [Qt Quick Controls styling](https://doc.qt.io/qt-6/qtquickcontrols-styles.html)

The Mac client should feel appropriate on Mac while sharing the desktop product's core behavior. It should not simply enlarge the phone interface or impose Windows conventions on every platform.

## 9. C++/Qt everywhere on desktop versus C# on Windows

This comparison assumes C++/Qt on Mac/Linux and asks whether Windows should share that application or use a separate C#/.NET/WinUI implementation.

| Concern | C++/Qt across desktops | Separate C# Windows application |
| --- | --- | --- |
| Initial development | Build a shared foundation and adapt each platform | Potentially productive Windows development, plus a distinct application implementation |
| Feature maintenance | Share substantial interface and behavior changes | Coordinate Windows changes with the Qt application |
| Behavioral consistency | Common implementation reduces divergence opportunities | Additional compatibility testing between desktop implementations |
| Windows integration | Requires appropriate Qt/platform adaptation | More direct alignment with Microsoft's native UI framework |
| Memory safety | C++ ownership and lifetime errors remain significant risks | Managed memory reduces that class of risk; native resources still need care |
| Learning | Modern C++, Qt, QML, and desktop tooling | Those skills plus C#, .NET, and WinUI |
| Framework dependency | More desktop functionality depends on Qt | Windows gains an independent framework path |
| Release/support | Shared code can simplify fixes; each OS still needs its own release work | Another build, dependency, testing, and debugging path to maintain |
| Portfolio | Greater depth in cross-platform C++ engineering | Greater breadth through a separate .NET application |

C# was never rejected as an inferior language. Its managed memory and application libraries can make Windows development productive. Microsoft's WinUI is a native Windows framework available to both C# and C++. [C# memory management](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/basic-concepts), [WinUI](https://learn.microsoft.com/en-us/windows/apps/winui)

The decision is that a second desktop implementation currently lacks a demonstrated product benefit sufficient to justify its ongoing cost.

### When C# could become the better Windows choice

We would reconsider if a prototype exposes a Windows requirement Qt cannot satisfy adequately, a Windows-focused team brings substantial .NET expertise, or the Windows product deliberately needs an experience whose independent development is justified.

That would be an evidence-based architectural revision. It should not require defending the original choice after circumstances change.

### The hybrid alternative

A C# Windows interface could call a shared C++ core. That preserves some reuse but adds a boundary for data conversion, lifetime, threading, callbacks, errors, and deployment. .NET supports native interoperability, but its engineering cost remains ours. [Microsoft native interoperability guidance](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)

Likewise, Swift/C++ interoperability exists, with documented constraints. It is an option to evaluate later, not proof that moving current iOS logic into C++ would be inexpensive. [Swift/C++ interoperability](https://www.swift.org/documentation/cxx-interop/)

## 10. Risk and reward of concentrating desktop development in C++/Qt

| Area | Expected reward | Risk or cost | How we intend to manage it |
| --- | --- | --- | --- |
| Shared features | Less repeated implementation | A common defect can affect every desktop | Shared behavioral tests plus per-platform acceptance |
| Modern C++ | Deep, transferable engineering experience | Ownership, lifetime, and concurrency mistakes | Explicit ownership, RAII, small modules, appropriate analysis and sanitizer checks |
| Qt/QML | Integrated desktop development and reusable UI | Framework learning and upgrade dependency | Prototype difficult workflows; pin and deliberately upgrade dependencies |
| Cross-platform interface | Consistent Plenact behavior | Platform expectations can be missed | Platform adapters and real keyboard/accessibility testing |
| Shared data logic | Fewer desktop copies of synchronization rules | A poorly bounded core becomes tightly coupled to UI | Clear responsibilities and contract-level tests |
| Delivery | More common work can be released together | Packaging and operating-system behavior still differ | Separate build/install/update checks on supported configurations |
| Small-team operation | Fewer independent applications to support | Several platforms still require substantial support capacity | Release clients progressively and limit the initial support matrix |

The memory-management risk is real even for an experienced C developer. C++ adds tools for managing resources, but also introduces language and library complexity. Qt has its own object-lifetime and thread-affinity rules; combining Qt ownership with standard-library ownership requires an explicit design.

Garbage collection in C# reduces managed-memory work, but does not remove resource, concurrency, persistence, or synchronization correctness problems. Neither language choice supplies a reliable offline data model automatically.

Performance alone is not the deciding factor. We have not measured a Plenact workload demonstrating that C# would be too slow or that C++ will solve interface performance problems. Responsiveness will depend on architecture, data access, rendering, background work, and measurement.

## 11. Financial and operational cost analysis

No credible dollar total, delivery date, or percentage saving has been established. We should measure a prototype and account for recurring costs before making such claims.

Costs to compare include:

- **Implementation:** shared feature work versus separate platform implementations.
- **Learning:** C++, Qt/QML, build systems, UI architecture, and debugging.
- **Dependencies and licensing:** selected Qt modules, third-party libraries, update policies, and any commercial arrangements.
- **Build infrastructure:** operating systems, supported architectures, test machines, and continuous integration.
- **Distribution:** packaging, signing, notarization where applicable, installation, and updates.
- **Verification:** accessibility, input methods, different displays, file handling, offline behavior, and recovery.
- **Support:** reproducing platform issues, safe diagnostics, compatibility fixes, documentation, and dependency updates.

Shared source code does not remove these expenses. It can reduce repeated feature implementation while allowing us to spend more attention on the platform-specific work that remains.

Qt offers commercial and open-source licensing options, and component terms vary. We must evaluate the actual modules and distribution approach before selecting a licensing path. This document does not determine that a particular distribution complies with a license or quote a commercial price. [Qt licensing](https://doc.qt.io/qt-6/licensing.html)

Using Qt should remain a scoped choice. We should not introduce unrelated modules or move server/mobile work into Qt simply because it is available.

## 12. The intended architectural boundaries

```text
Swift iOS/iPadOS client       Kotlin Android client       C++/Qt desktop client
        |                            |                   Windows / Mac / Linux
        +----------------------------+----------------------------+
                                     |
                    Shared portable contract and API
                                     |
                   Planned shared backend and storage

Browser client: HTML / CSS / TypeScript uses that same API.
```

This is a proposed responsibility map, not a statement that synchronization or these clients already exist.

Within the desktop application, we intend to distinguish:

1. Domain behavior: records, identity, validation, and planning rules.
2. Persistence and synchronization: durable local changes, transactions, conflict handling, and verified media.
3. Presentation: Qt models, view state, QML, and user interaction.
4. Platform integration: credentials, notifications, file dialogs, menus, lifecycle, and packaging.

We should keep domain logic independent of interface objects where that improves understanding, testing, or demonstrated reuse. We should not create a large abstraction framework before we have working features that need it.

The shared contract is the primary cross-language boundary. Shared source code is a separate optimization to justify through evidence.

## 13. What must remain consistent across every client

Regardless of language, Plenact needs the same meanings for:

- Stable account, workspace, owner, and record identities.
- References qualified by their actual ownership context.
- Dates, time zones, relative schedules, and timestamp precision.
- Authored order versus unordered selections.
- Saved writing and historical snapshots.
- Deletion intent, retained references, compatibility, and recovery.
- Original media verification and transfer.
- Durable offline changes and conflict behavior.

Our migration work demonstrates why these are product requirements rather than language details. An arbitrary Set iteration order must not become an authored ordering change. A historical review must not be replayed as a command. A display name or email must not establish cloud ownership.

Cross-client contract tests should reuse equivalent synthetic scenarios and expected portable outcomes. Passing a UI test in one language does not establish compatibility with another client.

Published User Data Model 1.0 remains immutable. Working Model 1.1 remains unpublished until explicitly authorized and ready. New clients must implement a deliberately supported contract rather than silently reinterpret existing records.

## 14. Web and backend choices

For the browser, HTML defines structure, CSS defines presentation, and TypeScript provides type-checked application behavior that ultimately runs as JavaScript. Learning JavaScript remains part of learning TypeScript. [TypeScript fundamentals](https://www.typescriptlang.org/docs/handbook/typescript-from-scratch)

PHP is the provisional shared backend/API direction, with Bluehost the planned host. That requires verification of the actual hosting plan's capabilities and operating constraints. Authentication, persistence, media storage, request handling, deployment, backups, and diagnostics need a concrete design and tests.

The backend serves all authorized clients. It should not become a separate website-only system with unrelated ownership or synchronization rules.

Choosing C++ for desktop does not require a C++ server. Shared protocol behavior matters more than using one language on both sides of the network.

## 15. The prototype that should validate the desktop direction

Before building full desktop parity, create a small, representative implementation containing:

- A Board with a realistic collection of Cards and Notes.
- A Card editor with text, checklist, and image attachment behavior.
- Local save/reopen and controlled malformed-input handling.
- Import/export of a supported synthetic portable scenario.
- Keyboard navigation, resizing, and accessibility checks.
- A build and basic installation path for each initial desktop target.

Evaluate Qt Quick/QML against those actual workflows. Rich text, input methods, focus behavior, artwork, and large Boards deserve early attention because a trivial button-and-label sample will not expose their difficulty.

Record development friction, platform adaptations, responsiveness, testability, dependency footprint, and deployment work. Do not infer success solely from the same window appearing on three operating systems.

The prototype should establish supported toolchain versions, the intended C++ standard, necessary Qt modules, platform targets, and the initial packaging approach. We have not selected those details in this conversation.

## 16. Releasing and supporting the product

A shared implementation is useful only if we can release and maintain it responsibly. Each supported platform still needs verification of installation, updates, permissions, file locations, keyboard behavior, display scaling, accessibility, offline use, and recovery.

We should begin with a manageable set of operating-system versions and architectures. Supporting every Linux distribution or every historical desktop configuration is not an initial commitment.

Shared tests can cover domain rules and portable data. Platform tests must cover actual system behavior. Dependency changes need a deliberate compatibility process, and support diagnostics must avoid exposing private records or media.

Publishing source code for portfolio purposes does not authorize publishing personal workspaces, archives, screenshots, or test records derived from private content. Automated regression fixtures remain synthetic and isolated.

## 17. Learning and portfolio development

The selected stack provides depth without requiring a separate shipping client solely to demonstrate each language:

- C remains Justin's existing professional foundation.
- Swift develops Apple mobile application skills through the current product.
- Modern C++ and Qt/QML develop shared desktop engineering skills.
- Kotlin develops native Android skills when that client begins.
- TypeScript, HTML, CSS, and PHP develop browser and server-side skills as those components begin.

C# remains a worthwhile optional future learning project. It is no longer a prerequisite for delivering the planned Windows application.

Learning should be deliberate: trace a feature, explain its data flow, implement a bounded change, debug a failure, write or interpret an appropriate test, and review the result. AI assistance can support each step, but generated code becomes maintainable only when its behavior and boundaries can be understood.

We should gradually increase Justin's ownership of meaningful features. Producing more code is not by itself evidence of increased engineering understanding.

## 18. Fit with our four-step delivery plan

1. **iOS migration and export:** preserve and reconcile existing user data through the portable model, including verified recovery.
2. **Cloud staging:** implement and test the shared API on the planned host with synthetic data.
3. **iOS synchronization:** prove durable offline changes, conflicts, and verified media transfer with the existing client.
4. **Additional clients:** bring Web, Windows, Mac, Linux, and Android onto the tested contract progressively.

The original fourth step emphasized Web and Windows. This language discussion expands the planned client set; it does not establish simultaneous delivery dates or move us past the earlier prerequisites.

At this decision checkpoint, Step 1 remains in progress. v22 is the latest owner-accepted portable checkpoint; Week-template replacement has automated evidence with manual acceptance still pending. Cloud synchronization remains disabled. The new desktop direction does not require repeating completed acceptance tests or restarting the migration.

## 19. Evidence that would justify revisiting the decision

Reconsider the detailed approach if a representative prototype reveals unacceptable accessibility, editing, integration, maintenance, licensing, or deployment costs. Also reconsider if the team's expertise or product priorities change materially.

Possible adjustments include retaining the shared C++ domain core while changing one interface, revising the Qt UI approach, or adding a specialized platform implementation for a demonstrated requirement. Those changes have costs and should be evaluated explicitly.

Our decision is firm enough to guide the next prototype, while remaining open to evidence. The objective is a dependable Plenact product and an understandable engineering foundation, not permanent allegiance to a framework.

## 20. Reference links

These are technical references, not measurements of Plenact's future development cost. Versioned support and licensing details must be reviewed for the releases we actually adopt.

- [Apple: configuring a multiplatform app](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target)
- [Android: Compose-first development](https://developer.android.com/develop/ui/compose/first)
- [Android: NDK concepts](https://developer.android.com/ndk/guides/concepts)
- [Android NDK: JNI](https://github.com/android/ndk/wiki/JNI)
- [Qt: supported platforms](https://doc.qt.io/qt-6/supported-platforms.html)
- [Qt: introduction to Qt Quick Controls](https://www.qt.io/product/qt6/qml-book/ch06-controls-introduction)
- [Qt: styling Qt Quick Controls](https://doc.qt.io/qt-6/qtquickcontrols-styles.html)
- [Qt: licensing](https://doc.qt.io/qt-6/licensing.html)
- [Microsoft: Windows application development](https://developer.microsoft.com/en-us/windows/apps/build-a-windows-app)
- [Microsoft: WinUI](https://learn.microsoft.com/en-us/windows/apps/winui)
- [Microsoft: C# basic concepts and memory management](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/basic-concepts)
- [Microsoft: native interoperability best practices](https://learn.microsoft.com/en-us/dotnet/standard/native-interop/best-practices)
- [Swift: mixing Swift and C++](https://www.swift.org/documentation/cxx-interop/)
- [GTK: language bindings](https://www.gtk.org/docs/language-bindings/)
- [gtkmm: C++ interface to GTK](https://gnome.pages.gitlab.gnome.org/gtkmm/)
- [Avalonia: supported platforms](https://docs.avaloniaui.net/docs/supported-platforms)
- [wxWidgets: overview](https://wxwidgets.org/about/)
- [TypeScript: fundamentals](https://www.typescriptlang.org/docs/handbook/typescript-from-scratch)
