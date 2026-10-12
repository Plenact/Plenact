# Offline Cover Library

The app bundles 400 PNG covers at 960 × 480 pixels: 48 existing illustrations and 352 additional vector-based illustrations. Eight albums contain 50 covers each. Searchable titles and tags are defined in `Src/CardCoverImages/cover-tags.json`; searches require all query terms to match within the selected album.

The expanded artwork uses native system symbols and a custom garden-tool drawing, rendered into themed compositions. To regenerate the expanded files from the repository root on macOS:

```sh
swift Design/CoverLibrary/GenerateCovers.swift Design/CoverLibrary/expanded-covers.json Src/CardCoverImages
```

Existing enum identifiers and PNG files are retained so saved covers remain compatible. New entries must be added to the enum, their album, metadata, and assets together. Regression checks validate the complete bundled set, unique image data, canvas sizes, album filtering, and the 150 MB artwork budget.

Each cover carries 10–20 contextual keywords, including title and album terms. Search matches word prefixes rather than arbitrary interior substrings, so “cat” can match “cats” without matching “education.” Conceptual tags such as animal, wildlife, mood, and wellbeing connect related subjects.
