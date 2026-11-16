# Phone sync shortcuts

`Fitness sync.plist` reads yesterday back N days (default 7) from Apple Health and POSTs one JSON array to `https://fitness.karunagath.in/api/ingest` with `Authorization: Bearer <key>`. `Fitness backfill.plist` asks "How many days?" (default 365) and runs Fitness sync with that number.

## Setup

1. On a Mac, sign both (unsigned plists; the `.shortcut` name is required, and if signing says "isn't in the correct format", run the `plutil` line first):
   ```sh
   cp "Fitness sync.plist" "Fitness sync.shortcut"
   cp "Fitness backfill.plist" "Fitness backfill.shortcut"
   plutil -convert binary1 "Fitness sync.shortcut" "Fitness backfill.shortcut"
   shortcuts sign -i "Fitness sync.shortcut" -o "Fitness sync signed.shortcut"
   shortcuts sign -i "Fitness backfill.shortcut" -o "Fitness backfill signed.shortcut"
   ```
   After signing, rename the signed files back to `Fitness sync.shortcut` / `Fitness backfill.shortcut` (the shortcut takes its library name from the file; `Fitness backfill` runs the shortcut named exactly `Fitness sync`).
2. AirDrop or open each signed file on the iPhone, tap Add, and paste the key from the app (More > Phone sync) when asked.
3. Allow Health access for every type on the first run.
4. Shortcuts > Automation > Time of Day 21:00 > Run Immediately > Run Shortcut `Fitness sync`.
5. Run `Fitness backfill` once.
6. To share: on the iPhone, Share `Fitness sync` as an iCloud link (the key is cleared on share; each person pastes their own).

Keep Health display units metric (kg, cm, g, mg, kcal): the shortcut sends values in the unit Health shows.

## Fields

Approach: Find Health Samples for the local day, Get Details, Calculate Statistics Sum (no summary action exists in the reference).

- `date`: YYYY-MM-DD of the day
- `steps`: Steps, count, sum
- `sleep`: Sleep, Duration summed, hours (seconds / 3600)
- `weight`: Weight, kg, first sample of the day
- `bodyfat`: Body Fat Percentage, first sample (percent or fraction)
- `waist`: Waist Circumference, cm, first sample
- `kcal`: Dietary Energy, kcal, sum
- `protein`: Protein, g, sum
- `carbs`: Carbohydrates, g, sum
- `fat`: Total Fat, g, sum
- `satfat`: Saturated Fat, g, sum
- `fibre`: Fiber, g, sum
- `sodium`: Sodium, mg, sum
- `active_kcal`: Active Calories, kcal, sum
- `rhr`: Resting Heart Rate, bpm, first sample of the day

A key is added only when the day has samples of that type.

## First run check

After the first sync, compare yesterday's steps, sleep and active energy in the app (Trends / Log the day) with the Health app. Known risks:

- Sleep may sum In Bed plus the sleep stages.
- Steps and active energy may double-count iPhone and Watch.
- The day list may not encode as a JSON array.

If numbers are off or nothing arrives, send a screenshot of the shortcut's result.
