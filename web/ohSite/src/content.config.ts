import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

// One app card on the landing page. The file name is the card's link target
// id (trellis.yaml is #trellis), so keep file names as they are.
//
// Every link is copied word for word from the old hand-kept landing page.
// The schema is strict: a field it does not know fails the build.
const desktopBuilds = z
  .object({
    win: z.url(),
    mac: z.url(),
    linux: z.url(),
  })
  .strict();

const hex = z.string().regex(/^#[0-9A-Fa-f]{6}$/);

const apps = defineCollection({
  loader: glob({ pattern: '*.yaml', base: './src/content/apps' }),
  schema: z
    .object({
      name: z.string().min(1),
      // The small label above the name, for example "Baby tracker".
      kind: z.string().min(1),
      // Card order on the page, from 1.
      order: z.number().int().positive(),
      // The app's two colours; c1 tints the card's top edge.
      c1: hex,
      c2: hex,
      // The picture: the app's own icon, as raw SVG markup.
      icon: z.string().startsWith('<svg'),
      // One plain line, shown first. No em dash.
      line: z
        .string()
        .min(1)
        .refine((s) => !s.includes('—'), 'a card line has no em dash'),
      // The longer description, shown under "More".
      desc: z.string().min(1),
      // The installable web build, and the label on its button.
      pwa: z.url(),
      pwaLabel: z.string().min(1).optional(),
      // The Android APK. The owner: "sideloading is FOSS freedom."
      apk: z.url().optional(),
      // A desktop app's builds by OS, and the page that lists them all.
      desktopBuilds: desktopBuilds.optional(),
      desktopAll: z.url().optional(),
    })
    .strict()
    .refine((a) => !a.desktopBuilds === !a.desktopAll, {
      error: 'desktopBuilds and desktopAll come together',
    }),
});

const privacy = defineCollection({
  loader: glob({ pattern: '*.md', base: './src/content/privacy' }),
  schema: z.object({
    app: z.string(),
    lastUpdated: z.string(),
  }),
});

export const collections = { apps, privacy };
