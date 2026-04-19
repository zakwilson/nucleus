# Conventions

## Design documents

When a feature in a design document gets implemented, add a **Status:** note but preserve the original design discussion and commentary. The design reasoning is a valuable record of how decisions were made and remains useful context for future work even after implementation.

## C interop invariant

All Nucleus types must be representable in C. This is a core design requirement — Nucleus is a drop-in replacement for C, and any function or data structure defined in Nucleus must be consumable from C. If you encounter or are asked to create a type that cannot be represented as a C struct/function/enum (e.g. closures with hidden captured environments, tagged unions requiring runtime support), flag it as a design violation before proceeding.
