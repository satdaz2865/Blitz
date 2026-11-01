# Blitz for the browser

This is a no-build web version of the VIC-20 Blitz port. It uses the original port's 8x8 character ROM glyphs, custom game sprites, and recorded engine, bomb-hit and crash sounds. All assets are embedded in local JavaScript, so the game works when opened directly from `file://`.

## Play

Hosted at **https://blitz-vic20.vercel.app** (Vercel, static site). The page is just the game canvas; it scales to fit the visible viewport on phones in both portrait and landscape.

Open `index.html` in a modern browser. No server, install, network connection or external assets are needed.

- **Space**, **Enter**, **Down Arrow**, or **F1**: start or drop a bomb
- **Escape**: return to the title screen
- **M**: toggle monochrome display
- **+ / -**: change flight speed
- On phones and small screens, tap the screen to drop a bomb

Bombs drill through a stack of up to five floors and damage the next floor. Clear the city skyline to reach the runway, earn a landing bonus and advance to the next frame. The best score is saved in browser local storage when available.

## Deploy

From this folder, after a one-time `npx vercel login`:

```sh
npx vercel deploy --prod --yes
```

The project name is `blitz-vic20`, which maps to the URL above. Any static host also works.

## Tests

From the repository root, run:

```sh
node --test HTML/game.test.mjs
```