# Shortcut Helper Copy Design

## Goal

Remove the redundant idle helper text below each shortcut setting title while preserving clear recording feedback and accessibility guidance.

## Behavior

- When a shortcut row is idle, show only its title. Do not show `Click the keycap to record`.
- While shortcut recording is active, show `Press shortcut now` below the title.
- Keep the keycap button's current shortcut value, recording state, click behavior, and layout unchanged.
- Keep the button's accessibility label, value, and hint unchanged so VoiceOver users retain explicit instructions.

## Verification

- Add a focused presentation test proving idle helper text is absent and recording helper text is present.
- Run the focused test, the complete Swift test suite, and an unsigned Xcode app build.
