# Swift Style References

This directory holds reference material for Plenact's Swift source style and documentation headers.

## Contents

- [`style.swift`](style.swift): the in-repository example for file, type, function, parameter, return, precondition, and postcondition commentary.
- `Style - Coding style templates - GitHub.webloc`: shortcut to an external style-template resource.

## For Developers

Use `style.swift` as the header reference and follow nearby production source for indentation and layout. The workspace-wide documentation convention covers active app sources, tests, and retained legacy Swift files; the template itself remains a reference, not application code.

- **Files:** describe responsibility, important data boundaries, and relevant limitations. Preserve known authorship/creation metadata; do not invent authors, historical dates, legal notices, or unresolved work.
- **Types and extensions:** provide a summary and an `@section Purpose` block describing their role.
- **Functions and initializers:** use `@fcn`, `@brief`, and `@details`. Document actual parameters, results, thrown errors, and meaningful preconditions/postconditions where applicable. Do not imply that a fallback or a test establishes guarantees it does not provide.
- **Computed properties:** use function-style headers to explain the result and any setter effects.
- **Stored properties:** provide concise purpose descriptions, including wrapped state and binding ownership. Local variables need comments only when their role is not clear.
- **Legacy sources:** identify noncompiled status in file headers. Documentation updates do not activate them or change Xcode target membership.

Use comments to explain purpose, contracts, and non-obvious behavior. Avoid comments that merely restate a Swift expression. Preserve existing indentation and formatting when making focused changes.

This directory is not part of the application target. Changes here do not alter runtime behavior unless equivalent changes are made in [`../../Src/`](../../Src/README.md).