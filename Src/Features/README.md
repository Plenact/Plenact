# Features

This directory contains cohesive features that support the Board and card-detail experience without introducing separate application layers.

## Available Features

- [`Attachments/`](Attachments/README.md): local photo/video storage, web-link validation, pickers, previews, and attachment UI.
- [`Labels/`](Labels/README.md): reusable categorized labels and card-label assignment.

## For Developers

Feature code is compiled into the single `Plenact` application target. Features currently integrate directly with `KanbanCard`, `CardDetailView`, and Board persistence.

When adding a feature:

- Keep its data ownership and persistence boundary explicit.
- Preserve Codable compatibility for fields stored on cards.
- Avoid external services, permissions, analytics, or dependencies without explicit product approval.
- Add a feature README describing user behavior, model ownership, persistence, privacy consequences, and known limitations.
- Keep private content local unless a separately designed sharing model exists.

## For Customers and Product Reviewers

The folders here describe implemented supporting capabilities, not separate products or synchronized services. Read each feature README for current limitations and data behavior.