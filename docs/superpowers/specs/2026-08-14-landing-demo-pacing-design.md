# Landing Demo Window Stack Design

## Goal

Make application and window switching immediately understandable by preserving one spatially stable macOS desktop throughout the demo.

## Design

- Replace the Everyday, Developer, and Creative scenes with one spatially stable flow. Remove all persona labels.
- Capture Finder, Notes, both Preview windows, and both SwitchTab overlays as independent real macOS window images with transparency. Do not capture the user's desktop, wallpaper, icons, or unrelated applications.
- Treat every capture as public marketing material. Finder must show only a dedicated `SwitchTab Demo` folder with staged filenames, with its sidebar and path bar hidden. SwitchTab overlays must contain only a curated set of generic system applications; they must not reveal the user's installed or running applications.
- Keep the primary Preview window on the neutral `switch-faster` product artwork. Replace the secondary `shortcut-map` artwork with a neutral, shortcut-free product image so content inside a window cannot be mistaken for the live keyboard HUD or SwitchTab overlay.
- Layer those real window images on a neutral desktop surface. Keep Finder visible at the back-left, begin with Notes in front, and keep two Preview windows partially visible behind it. Their persistent edges provide spatial continuity.
- Show the real SwitchTab application overlay selecting Preview, then the real two-window Preview switcher, then reveal a duplicate of the selected Preview layer above Notes so the other windows remain visible behind it.
- Use six 1.5-second beats, producing a 9-second loop: base stack, app selection, app selection hold, window selection, window selection hold, selected window in front.
- Preserve hard cuts between overlay states; do not use full-frame fades.
- Use the same hard-cut boundaries for the keyboard HUD and window states.
- Show no HUD from 0–1.5 seconds, `⌘ Tab` from 1.5–4.5 seconds, Command–backtick from 4.5–7.5 seconds, and `release ⌘` from 7.5–9 seconds.
- At the first frame of each keyboard phase, animate only the changed key for 0.2 seconds: `Tab` and the backtick key compress slightly and flash blue, while the final Command key uses the inverse motion to communicate release.

## Scope

Change the window-layer captures, scene markup, timing, keyboard micro-interaction, and matching landing contract. Keep the surrounding landing layout, copy, reduced-motion poster behavior, and mobile crop unchanged.

## Verification

- The landing contract requires exactly one scene, six unique real window assets, no persona labels, and a 9-second loop.
- Browser sampling confirms the app panel, window panel, and selected Preview layer switch at 1.5, 4.5, and 7.5 seconds.
- Boundary sampling confirms the HUD changes at exactly 1.5, 4.5, and 7.5 seconds.
- Visual inspection confirms Finder, Notes, and both Preview windows retain stable positions while their front-to-back order changes.
- Responsive sampling confirms every real window and switcher asset keeps its intrinsic aspect ratio at desktop, tablet, and mobile widths.
- The real two-window SwitchTab overlay is visible before the selected Preview window comes to the front.
- Visual inspection confirms that no asset contains a personal account name, home-folder name, sidebar item, tag, project filename, browser content, or uncurated application list.
- Visual inspection confirms that the secondary background window contains no shortcut-map artwork that competes with the live keyboard HUD.
- Key press/release effects begin on the exact same boundary as their corresponding screen changes.
- Reduced motion continues to show the static poster.
