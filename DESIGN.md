# SwitchTab website design

## 1. Atmosphere & Identity

Preserve the existing dark macOS product presentation. The layered switcher demo
is the homepage signature; guides prioritize legible text and authentic UI examples.
Audience: Mac users comparing shortcuts, then deciding whether to install.

## 2. Color

Reuse `docs/landing.css` tokens: `--canvas` (#07080c), `--text` (#f5f6fa),
`--text-soft` (#bec2cf), `--text-faint` (#7d8291), `--blue` (#6da8ff),
`--line`, `--line-soft`, `--surface` and `--surface-soft`. No new palette.

## 3. Typography

Use the existing system sans stack and system monospace for commands. Guide tokens:
`--guide-body: 1rem`, `--guide-small: .875rem`, `--guide-title: clamp(2rem, 5vw, 3.5rem)`,
`--guide-heading: clamp(1.5rem, 3vw, 2rem)`. Body line height 1.75, title 1.1.

## 4. Spacing & Layout

Reuse `.shell` (1180px cap, 24px side gutters, 16px at 640px and below).
Guide measure: `--guide-width: 760px`; space tokens 8, 16, 24, 32, 48 and 64px.
Guides use one reading column at all sizes, fluid images and wrapping commands.

## 5. Components

Reuse `.brand`, `.site-header`, `.header-nav`, `.button`, `kbd`, `.site-footer`.
Existing homepage serves as their state harness. Guide article sections use semantic
headings, a shortcut table, a linked contents list, figures and an installation section.
Inline guide links are underlined; controls retain visible focus and hover feedback.
Homepage guide link is a short paragraph after Quick Answers, visible on mobile.

## 6. Motion & Interaction

Reuse existing link/button feedback and reduced-motion settings. No new animation.
Contents links jump to headings; install links lead to the existing download flow.

## 7. Depth & Surface

Reuse existing dark background and blue atmosphere. Reading sections use simple
rules; commands use `--surface-soft`; UI images use `--radius-md`. No new decorative cards.

## 8. Accessibility Constraints & Accepted Debt

Target AA text contrast, visible keyboard focus, logical heading order, descriptive
image alt text and semantic table headers. At 320px, content must fit without clipping.
Existing homepage styling is preserved; this task does not claim a full-site AA audit.
