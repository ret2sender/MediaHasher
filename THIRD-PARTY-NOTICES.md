# Third-Party Notices

MediaHasher is distributed as a whole under the **GNU General Public License
v3.0 or later** (see `LICENSE`). The **MediaHash core library** (`MediaHash/`)
is additionally available on its own under the **MIT License** (see
`MediaHash/LICENSE`).

This file lists the third-party components bundled with or linked by the
project, grouped by which component depends on them. Every listed license is
compatible with GPLv3. The core-library section is kept self-contained so it
can move with `MediaHash/` if that library is ever published separately.

---

## Application (`ui/`)

### Linked libraries

| Component | License | Project |
|-----------|---------|---------|
| Qt 6 (Core, Gui, Quick, QuickControls2) | LGPL v3 / GPL v3 | https://www.qt.io |
| yaml-cpp | MIT | https://github.com/jbeder/yaml-cpp |

Qt is used under the LGPLv3 option and linked dynamically; distributing the
application under GPLv3 satisfies those terms.

### Bundled fonts

The full license text for each font ships alongside the font files in
`ui/Sources/fonts/`.

- **Inter** - `ui/Sources/fonts/Inter-*.ttf`
  Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter)
  SIL Open Font License, Version 1.1 - see `ui/Sources/fonts/Inter_OFL.txt`.

- **JetBrains Mono** - `ui/Sources/fonts/JetBrainsMono-*.ttf`
  Copyright 2020 The JetBrains Mono Project Authors
  (https://github.com/JetBrains/JetBrainsMono)
  SIL Open Font License, Version 1.1 - see
  `ui/Sources/fonts/JetBrainsMono_OFL.txt`.

### Bundled icons

- **Google Material Symbols** - `ui/Sources/icons/google_material/*.svg`
  Copyright Google LLC.
  Apache License, Version 2.0 - https://www.apache.org/licenses/LICENSE-2.0

- **IntelliJ Platform icons (redrawn / modified)** -
  `ui/Sources/icons/jetbrains_intellij/*.svg`
  Derived from JetBrains IntelliJ Platform icons.
  Copyright 2000-2023 JetBrains s.r.o. and contributors.
  Apache License, Version 2.0 - https://www.apache.org/licenses/LICENSE-2.0
  Modifications: redrawn as vector paths, rescaled to a uniform 24x24 canvas,
  recolored to the application palette, and converted from stroked outlines to
  filled paths.

### Logo artwork

The MediaHasher logo - both the "MH" glyph mark and the "MediaHasher"
wordmark - is a vector outline set in **Akronim**
(Copyright (c) 2012 Grzegorz Klimczewski, Fonty.PL, www.fonty.pl;
https://fonts.google.com/specimen/Akronim), licensed under the SIL Open Font
License, Version 1.1. The OFL permits creating logos and artwork with a
licensed font and does not extend its terms to the rendered outlines, so the
logo artwork itself is covered by the project license and carries no
third-party obligation. This entry is provenance documentation, not a license
requirement. The font itself is not bundled with MediaHasher.

### Original assets

The window-control glyphs in `ui/Sources/icons/windows/` are original artwork
(generic close/minimize shapes) and are covered by the project license.

---

## Core library (`MediaHash/`)

These dependencies belong to the MIT-licensed core. If `MediaHash/` is ever
extracted into its own repository, copy this section into that repository's
own notices file.

| Component | License | Project |
|-----------|---------|---------|
| OpenSSL 3 | Apache License 2.0 | https://www.openssl.org |
| BLAKE3 | CC0-1.0 or Apache 2.0 | https://github.com/BLAKE3-team/BLAKE3 |
| xxHash | BSD 2-Clause | https://github.com/Cyan4973/xxHash |

---

## License texts

- Apache-2.0 - https://www.apache.org/licenses/LICENSE-2.0
- BSD 2-Clause - https://opensource.org/license/bsd-2-clause
- CC0-1.0 - https://creativecommons.org/publicdomain/zero/1.0/legalcode
- OFL-1.1 - https://openfontlicense.org
- GPL-3.0 - see `LICENSE`
- MIT - see `MediaHash/LICENSE`
