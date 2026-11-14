# Tech debt cleanup

LLM prototyping has resulted in a prototype-quality compiler. That's getting upgraded to pre-release the old-fashioned way in this stage.

## Add abstractions

These were spelled out several times in the codebase

* node/index-of
* keyword/keyword
* keyword/keyword-name

## Remove legacy warnings

The robot added warnings for legacy spellings. Without legacy codebases, they're just cruft.

* legacy-marker-tail
* legacy-marker-name
* legacy-marker-ref
* reject-legacy-marker
* rd-at-legacy-marker

