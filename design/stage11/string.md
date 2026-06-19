# Strings

- C strings (`CStr`) were enough to bootstrap and must stay for interop, but are not
  a reasonable default in 2026.
- `String` is **UTF-8 and memory-safe**, plausibly built on `Vector` (`Vector u8`).
- Indexing is **not** O(1) random access over codepoints
  `Seq`. (This is why `Str` does not blanket-`extend Seq`.)
- Switching **string literals** to `String` should come *after* collections are
  stable — the compiler uses `CStr` heavily and that migration is part of the
  end-of-stage compiler-adoption step, not the start.

Robot claims `Str` does not blanket-`extend Seq` because indexing is not O(1). O(1) indexing is **not** part of `Seq`'s contract, only `Vector`'s; indexed access must be possible for `Seq`, not necessarily fast.

Robot proposed

>  `String` exposes **byte and codepoint iterators** rather than pretending to be a random-access

That's fine, but a programmer can still request the nth Char if they're willing to wait for it.

## Char types

Character protocol provides utf8 and utf16 encoders and decoders

Char type is a 32-bit unicode scalar value

### Selected implementaiton: thin wrapper over byte vector

Basically Rust's approach. A String is a vector of bytes with separate iterators to produce bytes and characters. Byte index is O(1), but character index requires iterating from the beginning.

### Rejected options

* Sparse index: The previous idea becomes a BaseString type and the default String builds on top of it with a sparse index to allow indexed access with good performance with small storage overhead. This could be a useful type, but overhead like that should be opt-in.
* Fixed-width encoding - more or less UTF-32. Up to 4x space penalty. If someone wants it, it wouldn't be hard to implement Str on (Vector Char).
