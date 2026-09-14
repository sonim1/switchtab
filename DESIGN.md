# SwitchTab website design

## 1. Atmosphere & Identity

Preserve the existing dark macOS product presentation. The layered switcher demo
is the homepage signature; guides prioritize legible text and authentic UI examples.
Audience: Mac users comparing shortcuts, then deciding whether to install.

## 2. Color

Reuse `docs/landing.css` tokens: `--canvas` (#07080c), `--text` (#f5f6fa),
`--text-soft` (#bec2cf), `--text-faint` (#a2a8b8), `--blue` (#6da8ff),
`--line`, `--line-soft`, `--surface` and `--surface-soft`. No new palette.

## 3. Typography

Use the existing system sans stack and system monospace for commands. Guide tokens:
`--guide-body: 1rem`, `--guide-small: .875rem`, `--guide-title: clamp(2rem, 5vw, 3.5rem)`,
`--guide-heading: clamp(1.5rem, 3vw, 2rem)`. Body line height 1.75, title 1.1.

Homepage readable type tokens: `--type-body: 1rem`, `--type-lede: 1.125rem`,
`--type-control: .9375rem`, `--type-secondary: .875rem`,
`--type-meta: .8125rem`, `--type-eyebrow: .75rem`. Keep existing headings.
Body/feature/installation paragraphs use body; hero uses lede (body on mobile).
Controls use control; navigation, commands, secondary links and labels use secondary;
captions, trust badges, footer and playback use meta. Eyebrows use eyebrow.
Decorative miniature macOS chrome remains 9px, not user instructions.

## 4. Spacing & Layout

Reuse `.shell` (1180px cap, 24px side gutters, 16px at 640px and below).
Guide measure: `--guide-width: 760px`; space tokens 8, 16, 24, 32, 48 and 64px.
Guides use one reading column at all sizes, fluid images and wrapping commands.

## 5. Components

Reuse `.brand`, `.site-header`, `.header-nav`, `.button`, `kbd`, `.site-footer`.
Existing homepage serves as their state harness. Guide article sections use semantic
headings, a shortcut table, a linked contents list, figures and an installation section.
Inline guide links are underlined; controls retain visible focus and hover feedback.

Installation commands wrap instead of clipping: min-width 0, white-space normal,
overflow-wrap anywhere, with 12px vertical padding and a non-shrinking cask link.
Agent installation uses native details/summary below the existing install panel,
with closed/open/focus states, a labelled read-only textarea and a plain-text link.
Use existing line/surface/radius tokens, 16px internal gaps and 24px padding.
Textarea uses body-size monospace, 1.65 line height, full width, wrapping, a 16rem
minimum height, and vertical resizing. It is manually selectable/copyable without
JavaScript or clipboard permission. The prompt and README match the public text file.
Homepage guide link is a short paragraph after Quick Answers, visible on mobile.

The demo OS chrome follows macOS menu-bar anatomy: Apple silhouette, bold active
app name, app menus on the left; battery, Wi-Fi, Spotlight, Control Center and
date/time on the right. These are decorative SVGs inside the existing aria-hidden
scene, not interactive OS controls. Use system sans, 9px menu text, 12px icons
(18px battery), a 26px bar, 12px desktop / 8px mobile gaps, and 12px side insets.
Menu material uses white text over translucent slate (`rgba(133,155,187,.24)`)
with the existing 20px backdrop blur and a fine light lower edge. Keep File/Edit/View
when the demo container is narrow (560px or less); secondary menus/date/Spotlight
may collapse. Never replace the
Apple silhouette with a font-only private-use character.

Reference: [Apple's menu-bar anatomy](https://support.apple.com/guide/mac-help/mchlp1446/mac).
Apple silhouette path: [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/icons/apple.svg),
used only within the illustrative macOS desktop, not as SwitchTab branding.

Playback belongs outside the OS frame, beside the caption in a second grid row
with a 12px row gap and 16px column gap. Preserve its 44px touch target, keyboard
focus, checked state and reduced-motion behavior. Window assets and the nine-second
story are preserved. The homepage demo is the state harness for this primitive.

## 6. Motion & Interaction

The demo uses `--demo-cycle: 9s` and `--demo-ease: cubic-bezier(.22, 1, .36, 1)`.
Switcher panels fade over 180ms with `--demo-panel-scale: .97` to 1; the selected
Preview window fades/scales from .985 to 1 over 270ms. Instructions appear before
the key press, then the panel responds. Key presses travel `--demo-key-travel: 2px`
and scale to `--demo-key-scale: .94` over 90ms, hold 180ms and release over 180ms.
Their blue highlight is an opacity-animated pseudo-element, using the existing
accent (#69a8ff border, rgba(67,139,255,.38) fill, .18 outer ring). Held Command
keys stay visibly depressed; release feedback returns to rest before the next loop.
Only opacity and transform animate; no new runtime library or animated layout.

Timeline percentages: app instructions 12–14 in / 44–46 out; Tab press 14–19;
app panel 16–18 in / 49–51 out; window instructions 46–48 in / 73–75 out;
backtick press 48–53; window panel 50–52 in / 76–78 out; release instructions
73–75 in / 94–96 out; Command releases 76–78. Selected window and menu label
transition 76–79 in / 95–98 out, with a 1.44s settled result hold, so the loop
boundary matches the initial poster.
Pause freezes the full timeline including key highlights; reduced motion removes
all demo animation and keeps the existing static Notes poster and text alternative.

Mechanism reference: [beui action-swap source](https://beui.dev/r/action-swap/raw):
paired opacity/scale entry-exit and reduced-motion bypass, adapted to the existing
CSS timeline without its React/Motion dependency, blur or decorative bounce.
Reuse existing link/button feedback outside the demo.
Contents links jump to headings; install links lead to the existing download flow.

## 7. Depth & Surface

Reuse existing dark background and blue atmosphere. Reading sections use simple
rules; commands use `--surface-soft`; UI images use `--radius-md`. No new decorative cards.

## 8. Accessibility Constraints & Accepted Debt

Target AA text contrast, visible keyboard focus, logical heading order, descriptive
image alt text and semantic table headers. At 320px, content must fit without clipping.
Existing homepage styling is preserved; this task does not claim a full-site AA audit.

Personas: phone readers, keyboard-only and motion-sensitive visitors, and local
coding-agent users. Installation copy distinguishes terminal-capable local agents
from chat-only tools. Verify macOS14+/Apple silicon, official release signature,
and leave existing installs and permissions under user control. No installer,
security bypass or permission grant runs on page load.
