This directory holds Plenact's product, UX, architecture, demonstration, and coding-style material. Documents should distinguish current app behavior from proposed work

## Start Here

- [`Production-Preparation-Handoff.md`](Production-Preparation-Handoff.md) - verified product, architecture, data-safety, and release-preparation handoff for the next production agent

- [`Life-Planning-Model.md`](Life-Planning-Model.md) - product-model reference for Lists, Cards, checklist actions, planning views, and the proposed weekly review

- [`Board-Presentation.md`](Board-Presentation.md) - implemented Standard/Overview presets, portrait/landscape layout, local preferences, and remaining device acceptance checks

- [`Today-View-Architecture.md`](Today-View-Architecture.md) - current app boundaries and incremental architecture direction

- [`Today-View-UI.md`](Today-View-UI.md) - Today screen behavior and interaction proposal

- [`Board-and-Scheduled-Views.md`](Board-and-Scheduled-Views.md) - implemented Board behavior and the proposed Scheduled view

- [`Checklist-Actions-Architecture.md`](Checklist-Actions-Architecture.md) - stable checklist-item migration and proposed linked/detail action types

- [`Local-Profile-Architecture.md`](Local-Profile-Architecture.md) - local identity, personalization, persistence, and future session boundary

- [`Users/`](Users/README.md) - proposed shared Plenact user directory, registration, and card assignment design

- [`Database/`](Database/README.md) - Bluehost setup gates, Plenact data contract, and initial demo import plan

- [`../Server/`](../Server/README.md) - Plenact-owned API and SQL migration work, separate from the reference project

- [`GitHub-Organization-Profile/`](GitHub-Organization-Profile/README.md) - maintained source for the public Plenact organization landing page

- [`Demo/`](Demo/README.md) - product walkthrough recordings

- [`Style/`](Style/README.md) - Swift documentation and formatting references

- [`Src/`](Src/README.md) - legacy documentation-source pointer material, not app implementation

## Audience

Developers should use these documents to understand product boundaries before changing navigation, persistence, or stored models. Customers and prospective customers can use them to understand the intended workflow, while paying attention to each document's status statement

## Documentation Rules

- Label implemented, proposed, and exploratory behavior explicitly
- Do not describe calendar sync, accounts, cloud/team sync, a database, or web/desktop clients as available
- Do not make medical, treatment, clinical-validation, privacy-compliance, or regulatory claims
- Keep examples respectful and avoid personal health details
- Update documentation when a proposal becomes implemented or its behavior changes

The `.webloc` files are local shortcuts to project resources. They are conveniences, not source dependencies