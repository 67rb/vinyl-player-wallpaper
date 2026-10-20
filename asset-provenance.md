# Wallpaper assets — 2026-10-11

## Real media

- `Resources/assets/fire-live.mp4`: actual fire filmed by ROMAN ODINTSOV, [Burning Logs in the Fireplace](https://www.pexels.com/video/burning-logs-in-the-fireplace-7592907/). Local copy encoded as H.264 at 24 fps and 1024 pixels wide, without audio. It loops locally and is cropped to the fireplace opening when painted on the canvas.
- `Resources/assets/fire-poster.jpg`: the same clip's published poster.
- `Resources/assets/rain-window.jpg`: photograph by Andaru Firmansyah, [Coffee on Table by Rainy Window in Bandung Cafe](https://www.pexels.com/photo/coffee-on-table-by-rainy-window-in-bandung-cafe-37279767/). The CSS window shows its upper wet-glass and greenery region, excluding the cup and branding.
- The above media is supplied under the [Pexels license](https://www.pexels.com/license/). Bundled media works without network requests.

## Generated assets

The room interiors and tonearms are generated assets, not claims of photographed rooms. The built-in imagegen tool was used to revise the room interiors toward a subdued photographic treatment, preserve overlay landmarks, and replace the former bulky tonearm. Both tonearm images retain alpha transparency.

- `Resources/assets/tonearm-overhead.png`: simple silver S-shaped arm seen directly from above; small black circular pivot, short counterweight, perforated headshell, small black cartridge. Neutral satin chrome, soft upper-left light, no gimbal posts or clutter, isolated on a transparent square canvas.
- `Resources/assets/tonearm-angled.png`: same design seen from a low angle, with consistent top-and-side perspective and foreshortening. Separate geometry for the angled room views.
- `Resources/assets/fireside.png`: original composition preserved; reduce orange HDR lighting and gloss, simplify decorations, use irregular worn wood and matte leather. The fireplace is dark with no baked-in flames, so filmed flames provide the motion.
- `Resources/assets/rain-light.png`, `rain-heavy.png`, `rain-storm.png`: shared revised interior with matching overlay landmarks. Reduce procedural wood detail and amber lighting; remove decorative clutter, retain one practical lamp. The photographed window is a separate layer; rain density and scene-specific lighting distinguish the three weather states.

Prompt briefs above describe the final tool requests. The complete prompts and original generated-file locations are recorded in the conversation's imagegen calls.

Native ambient audio: `ambient-rain.wav`, `ambient-storm.wav`, `ambient-fire.wav`, and `ambient-thunder.wav` are locally synthesized mono noise beds with different low-pass filters. They are not field recordings.
