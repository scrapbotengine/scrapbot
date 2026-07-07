# Odin Packages and Ecosystem

## Contents

- Package collections
- Common package choices
- Vendor libraries and foreign code
- Examples and learning resources
- Reference links

## Package Collections

Odin package docs live at https://pkg.odin-lang.org/.

Collections:

- `base:` is required by Odin targets and implementations. It includes runtime-level support.
- `core:` is the standard library collection for normal application/library code.
- `vendor:` contains maintained bindings and ports for external libraries.

Import examples:

```odin
import "core:fmt"
import "core:mem"
import "core:os"
import "core:testing"
import glfw "vendor:glfw"
```

Package documentation is generated from source. For generated platform packages, the docs may be target-specific, so reading the local compiler source can be more reliable.

## Common Package Choices

Start here for common needs:

- Text and formatting: `core:fmt`, `core:strings`, `core:strconv`, `core:unicode/utf8`.
- Memory and allocation: `core:mem`, `core:mem/virtual`, `core:mem/tlsf`.
- OS and paths: `core:os`, `core:path/filepath`, `core:path/slashpath`.
- Files/streams: `core:io`, `core:bufio`.
- Logging: `core:log`.
- Time: `core:time`.
- Randomness: `core:math/rand`.
- Math: `core:math`, `core:math/linalg`, `core:math/linalg/glsl`, `core:math/linalg/hlsl`, `core:simd`.
- Containers: `core:container/*`, `core:slice`, `core:sort`.
- Serialization/parsing: `core:encoding/json`, `core:encoding/csv`, `core:encoding/ini`, `core:encoding/xml`, `core:encoding/hex`, `core:encoding/base64`.
- Networking and concurrency: `core:net`, `core:sync`, `core:sync/chan`, `core:thread`, `core:nbio`.
- Reflection/tooling: `core:reflect`, `core:odin/parser`, `core:odin/tokenizer`, `core:odin/ast`.
- Testing: `core:testing`.
- C interop: `core:c`, `core:dynlib`, `core:sys/*`.

## Vendor Libraries and Foreign Code

Use `vendor:` before hand-writing bindings for common graphics, windowing, audio, platform, and C libraries. The official vendor collection changes over time, so inspect https://pkg.odin-lang.org/vendor/ and local compiler sources.

Typical vendor workflow:

1. Import the vendor package.
2. Preserve upstream API naming when it makes porting clearer.
3. Keep setup/teardown explicit with `defer`.
4. Wrap raw C-ish calls behind project-level Odin procedures if the rest of the code wants a safer interface.

For missing libraries:

- Write a narrow binding for only the API surface needed.
- Use `foreign import` and `foreign` blocks.
- Use `core:c` types and `cstring` at the boundary.
- Add link attributes and target-specific build tags.
- Keep allocations and ownership at the wrapper edge.

## Examples and Learning Resources

Official and maintainer-adjacent resources:

- Official docs: https://odin-lang.org/docs/
- Overview: https://odin-lang.org/docs/overview/
- Install/getting started: https://odin-lang.org/docs/install/
- Demo file: https://odin-lang.org/docs/demo/
- Running tests: https://odin-lang.org/docs/testing/
- FAQ: https://odin-lang.org/docs/faq/
- Package docs: https://pkg.odin-lang.org/
- Compiler/source: https://github.com/odin-lang/Odin
- Official examples: https://github.com/odin-lang/examples
- Odin examples naming/style convention: https://github.com/odin-lang/examples/wiki/Naming-and-style-convention
- Odin Book by Karl Zylinski: https://www.odinbook.com/
- Odin news/declaration syntax: https://odin-lang.org/news/declaration-syntax/
- Community/forum: https://forum.odin-lang.org/

The official examples repository is useful because it covers idiomatic use of language features, `core`, and `vendor`. It also recommends reading the compiler's `core` folder as practical source-level documentation.

## Reference Links

Use these when the task needs authoritative detail:

- Documentation index: https://odin-lang.org/docs/
- Language overview: https://odin-lang.org/docs/overview/
- Language specification entry: https://odin-lang.org/docs/spec/
- Package index: https://pkg.odin-lang.org/
- Base library: https://pkg.odin-lang.org/base/
- Core library: https://pkg.odin-lang.org/core/
- Vendor library: https://pkg.odin-lang.org/vendor/
- Nightly builds: https://odin-lang.org/docs/nightly/
- Latest releases: https://github.com/odin-lang/Odin/releases
- Issues/discussions: https://github.com/odin-lang/Odin
