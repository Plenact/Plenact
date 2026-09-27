# Documentation Source References

This directory currently contains `Style`, a macOS Finder alias to an external or local coding-style resource. It is documentation support material, not Swift source compiled into Plenact.

## For Developers

The maintained in-repository Swift style reference is [`../Style/style.swift`](../Style/style.swift). Prefer that file when reviewing documentation headers and local formatting because Finder aliases may not resolve on another developer's machine.

Do not place application implementation here. Runtime Swift belongs under [`../../Src/`](../../Src/README.md), while product and architecture documents belong under [`../`](../README.md).

## Portability

Aliases can contain machine-specific targets. A new developer or customer browsing the repository should not need the alias to understand, build, or use the project.