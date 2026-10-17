# Third-Party Notices

## CodexIsland

Portions of the interaction and animation design are adapted from
[ericjypark/codex-island](https://github.com/ericjypark/codex-island).

MIT License

Copyright (c) 2026 Eric Park

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Asta Sans

The bundled Asta Sans Regular, Medium, and SemiBold font files are distributed
under the SIL Open Font License 1.1. The complete license text is included at
`Contents/Resources/Fonts/AstaSans-OFL.txt` in the application bundle and at
`Resources/Fonts/AstaSans-OFL.txt` in this source tree.

## QuotaView

The floating activity-island composition and portions of the Ripple Glow
palette and renderer are adapted from
[Duoasa/QuotaView](https://github.com/Duoasa/QuotaView).

The multitask card hierarchy, fixed-canvas native path/content transitions,
presentation-layer retargeting, transparent-space pointer routing, scroll
anchors and row-visibility calculations also adapt `IslandConceptBoard.swift`
and `IslandTaskScrolling.swift` at commit
`f632288fb706b83e691000e365004f6ed9654d94`. The application bundle includes
the source pin, adaptation scope and MIT license in
`Contents/Resources/ThirdPartyNotices.txt` (source: `Resources/ThirdPartyNotices.txt`).

The complete State Smoke / Quantum Noise / Liquid Wave Metal renderer and
preview host, native glass and notch shapes, scrolling text, material gradient,
task-card composition and settings preview assets are reused/adapted from
`d16307f4666f75b94a40cdb3933777a028d8fa8a` (`v0.8.2-build.2`). The corresponding
upstream files are `CodexActivityStateSmoke.swift`, `IslandConceptBoard.swift`,
`CodexActivityIsland.swift`, `IslandScrollingText.swift`, `AppPreferences.swift`,
`SettingsView.swift` and the settings-preview image assets. The native settings rows, cards, icons, value menus and effect-option styles, plus
completion/confirmation glow, outline, palettes and compositor pulse are reused
from the same pinned source. The compact fitting-title layout and receipt cadence,
token formatter from `CodexActivityCopy.swift`, and field guards/content whitelist
from the QuotaViewCore rollout/public-content decoders are reused or adapted too. Source attribution
is retained in the adapted files and bundled notice.

Desktop observation additionally adapts `CodexDesktopIPCClient.swift` and
`CodexDesktopRequestProjection.swift` from the same pin, plus the session-kind
and subagent identity declarations from `CodexActivityTaskIdentity.swift` and
`CodexActivitySubagentIdentity.swift`. Approval/answer submission entry points
are removed; an egress allowlist permits only observation and explicit protocol
refusals. Incremental cursor and line-buffering logic from
`CodexLocalRolloutActivityClient.swift` is adapted to the existing transcript
decoder. Native IPC fixtures are adapted from `CodexDesktopIPCClientTests.swift`.

MIT License

Copyright (c) 2026 Duoasa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Usage dashboard adaptation: QuotaView f7795311bf06c2a54c9b9756da375c50d0f4930e, IslandConceptBoard.swift (IslandUsageBento and IslandActivityHeatmap). MIT, Copyright (c) 2026 Duoasa; covered by the QuotaView license above.

Usage parity update (f779531): IslandGlassSurface macOS 27 tint separation, IslandPageLayout, IslandChartScroller/IslandRecentChartScroll, chart hover anchors, EstimatedCostChartModel aggregate-token proxy, and IslandResetTicket artwork/hover/sweep adapted under the QuotaView MIT license above.

Island reset detail: QuotaView f779531 IslandResetPage.swift ticket anchor preference and complete reversible 3D flight compositor reused (MIT, Copyright (c) 2026 Duoasa); demo submission replaced by Codex Monitor’s explicit-confirmation real reset service.

Reset action controls reuse QuotaView f779531 IslandApprovalTypedContent.swift / IslandApprovalActionStyle native-glass surfaces, semantic red tint and hover/press feedback (MIT, Copyright (c) 2026 Duoasa).


Zstandard decoder v1.5.7
https://github.com/facebook/zstd/tree/f8745da6ff1ad1e7bab384bd1f9d742439278e99
Decoder-only single-file source; used under the BSD license below.

BSD License

For Zstandard software

Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

 * Neither the name Facebook, nor Meta, nor the names of its contributors may
   be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Unified glass appearance: QuotaView v0.8.3-build.1 (178a2b03e94cf16119777c14ebdd9d2fd6ed97dc), AppPreferences.swift / IslandConceptBoard.swift. Reused scoped light/dark/automatic resolution, public AppKit effectiveAppearance observation, foreground contrast and shared untinted clear material. Codex Monitor retains its settings controls and opaque reset cards. MIT, Copyright (c) 2026 Duoasa; covered by the QuotaView license above.


Open Claude UI
https://github.com/Caho1/open-claude-ui/tree/ddf3aea1711db62fd6d24343bbab500a5ae69f64
Monitor Center, settings and floating-surface tokens and SwiftUI motion adapted from cds-theme.css, SegmentedControl.tsx and ClaudeMotionPresets.ts; no React/Electron dependency or proprietary assets included.

MIT License

Copyright (c) 2026 Caho1

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
