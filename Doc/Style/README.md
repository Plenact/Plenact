# Swift Style References

This directory holds reference material for Plenact's Swift source style and documentation headers.

## Contents

- [`style.swift`](style.swift): the in-repository example for file, type, function, parameter, return, precondition, and postcondition commentary.
- `Style - Coding style templates - GitHub.webloc`: shortcut to an external style-template resource.

## For Developers

Follow nearby production source first, then use `style.swift` as a guide when adding new declarations. Plenact generally favors explicit, readable headers for types and nontrivial functions, especially where state mutation, persistence, or data compatibility is involved.

Use comments to explain purpose, contracts, and non-obvious behavior. Avoid comments that merely restate a Swift expression. Preserve existing indentation and formatting when making focused changes.

This directory is not part of the application target. Changes here do not alter runtime behavior unless equivalent changes are made in [`../../Src/`](../../Src/README.md).