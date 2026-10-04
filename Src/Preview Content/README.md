This directory is reserved for assets and sample support used by SwiftUI previews during development.

## Contents

- `Preview Assets.xcassets/`: an Xcode-managed preview asset catalog. It currently contains catalog metadata and no production assets.

## For Developers

Keep preview content deterministic, non-sensitive, and clearly fictional. Runtime app icons, colors, and production resources belong in `../Assets.xcassets/`, while deterministic model samples belong near their owning models when that matches the current source structure.

Do not depend on preview assets for normal application execution. Preview-only resources may be absent from release builds or from another developer's local preview environment.

Avoid personal, clinical, or customer data in screenshots and sample records. Preview examples should demonstrate layout and accessibility states without implying implemented synchronization, sharing, or treatment functionality.
