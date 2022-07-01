### pros
- 1 go module instead of 2 that are merged, therefore no munging of `go.mod`, `go.sum`, `vendor/modules.txt` needed
- precomputed vendor binaries, which speed up successive tests and builds
- parallel testing and builds

### considerations
- assumes vendoring. might need a mild refactor to work with both vendored and unvendored projects
