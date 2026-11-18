# Orchard

Orchard is a personal iPhone app for tasting and remembering fruit and vegetables. Log a variety in a few taps and it is planted on a top-down farm. The rating changes the plant: loved fruit grows large and lush, middling fruit stays ordinary, and low scores wilt. There is no farmer or avatar. The farmhouse in the middle of the plot is the progression piece, and it upgrades as more distinct varieties are tasted.

The app is SwiftUI and SwiftData, iOS 17 or later, fully on device. There is no backend.

## Build

1. Open `Orchard.xcodeproj` in Xcode 15 or later.
2. The bundle id is `com.chrismartin.orchard`, version 1.0 (build 1). Signing is Automatic and the development team `HN9GXZ5384` is set on the project and on both targets.
3. Pick an iPhone simulator or your phone and run. The first launch loads `Orchard/Resources/catalogue.json` into SwiftData.

This project file was written by `tools/generate_xcodeproj.py` because XcodeGen is not available on Linux. `project.yml` describes the same targets. After adding or removing files, regenerate with:

```bash
python3 tools/generate_xcodeproj.py
```

Final compile and any TestFlight upload happen on a Mac. This repository was prepared on a machine that cannot compile iOS.

## Screens

The tab bar is Farm, Taste, Shop, and Collection. Shop is supermarket mode and is one tap from anywhere.

- **Farm.** Scrollable plot with an orchard, ground beds, trellis, a lab greenhouse, a tractor, and the farmhouse. Tasted varieties appear as plants. Tap one for its card.
- **Quick taste.** Searchable catalogue, or add a custom variety. Sweet, Tart, Crunch, and Juicy sliders, an overall score from 1 to 5 in half steps, notes, and an optional photo. Plant it saves the tasting and jumps back to the farm.
- **Supermarket mode.** Opens on a large search field. Typed matches show a colour, the score, and a one-line note. Untasted matches are listed as "Not tried yet". With an empty field, the screen is the personal ranking of what has already been tasted.
- **Collection.** Per-category log such as Apples 4 / 25. The denominator is the live catalogue for that category, including custom varieties, not a fixed target of 30. Tried varieties are in colour. The rest are faded chase tiles. The Hunt segment is the shopping list.

The latest tasting decides the plant and the supermarket score. Older tastings stay on the card.

## House upgrades

Thresholds live in `HouseRules.thresholds` in `Orchard/Logic/HouseProgress.swift`.

| Distinct varieties tasted | Building |
| --- | --- |
| 0 | Shed |
| 3 | Cottage |
| 8 | Farmhouse |
| 15 | Homestead |

A small sign under the house shows the current level and how many varieties are left until the next one. The tractor is decoration.

## Photos and stickers

The camera and photo library usage strings are in `Orchard/Info.plist`, along with `ITSAppUsesNonExemptEncryption` set to false. Vision reads text on the device. A variety name, alias, or 4-digit PLU (including an organic 9-prefix) suggests a match. If nothing matches, pick the variety by hand.

Supermarket mode is also a Home Screen quick action and an App Shortcut ("Open supermarket mode in Orchard").

## Debug launches

These arguments are read only in Debug builds:

```bash
xcrun simctl launch booted com.chrismartin.orchard -seedSampleTastings -openScreen farm
```

`-openScreen` accepts `farm`, `taste`, `shop` (or `supermarket`), and `collection`.

`-seedSampleTastings` inserts fictional tastings for varieties that have none, so the farm, supermarket list, and collection have something to screenshot. They are not a real tasting notebook. Delete them from a variety card if you want them gone. A variety you have already tasted is left alone.

The catalogue import runs on a background SwiftData actor after the first frame. On a fresh install the farm shows the shed, tractor and empty plots immediately, then the seeded plants appear.

## Catalogue

Edit `Orchard/Resources/catalogue.json` and relaunch. Existing rows are updated from the file. Tastings, hunt items, and custom varieties are kept. Rows you delete from the JSON are not removed from the database.

The apple list is the set this research could tie to commercial sale or production in Australia. It is not padded or trimmed to 30. The collection header uses that count.

Each variety can carry regions, season months, a where-to-find line, and a short fact. `factStatus` is `verified`, `unverified`, or `none`. Empty regions or months were left empty on purpose. Hex colours are painting values chosen to match a written description, not measured colours. `skinVerified: false` means the drawing is a placeholder.

PLU codes are the 4-digit numbers printed in trade PLU tables (a JA Technology Solutions quick reference and plu.pro). They were not re-queried one by one on ifpsglobal.com.

### Sources

The notes in the JSON point at the page used for that row. The main ones are:

- [APAL varieties](https://apal.org.au/consumer/varieties/)
- [APAL exporter directory](https://apal.org.au/wp-content/uploads/2020/06/APAL-Exporter-Directory-230418-v1.pdf)
- [NSW DPI Cripps Pink](https://www.dpi.nsw.gov.au/agriculture/horticulture/pomes/apples/varieties/cripps-pink) and [Cripps Red](https://www.dpi.nsw.gov.au/agriculture/horticulture/pomes/apples/varieties/cripps-red)
- [DPIRD apple breeding program](https://www.dpird.wa.gov.au/research/research-areas/horticulture-research/apple-breeding-program/) and the [1993 WA journal article](https://library.dpird.wa.gov.au/cgi/viewcontent.cgi?article=1434&context=journal_agriculture4) on Pink Lady and Sundowner
- [Fruit West Bravo good practice guide](https://www.fruitwest.com.au/index_htm_files/Fruit%20West%20-%20Bravo%20Apple%20Good%20Practice%20Guide%202020.pdf)
- [Woolworths apple guide](https://www.woolworths.com.au/shop/explore/fruit-veg/guides/apples)
- [Cosmic Crisp Australia](https://www.cosmiccrisp.com.au/growers-orchards/) and [ABC, June 2024](https://www.abc.net.au/news/2024-06-01/australian-apples-new-varieties-brands-consumer-demand/103913830)
- [SnapDragon Australia](https://snapdragonapple.com.au/)
- [Hort Innovation on Kalei](https://www.horticulture.com.au/information-hub/our-projects/historical-reports/ap08041)
- [Australian Dictionary of Biography, Charles Packham](https://adb.anu.edu.au/biography/packham-charles-henry-13142)
- [HIN pear harvest maturity](https://www.hin.com.au/__data/assets/pdf_file/0007/17899/Harvest-maturity.pdf)

### Left out or flagged

- **Rubens (Civni), Braeburn, Lady Williams, and SweeTango** are not in the seed list. This pass did not confirm that they are currently sold or grown commercially in Australia. Lady Williams is the historical parent of Pink Lady and Sundowner. Braeburn is a parent of Jazz and Envy. Add any of them to the JSON once there is a source.
- **Snap Fresh** was not found as a variety name. **SnapDragon** (NY 1) is the Australian supermarket apple that matched that description.
- **Cosmic Crisp** in Australia is grown in the Yarra Valley, Batlow, and Manjimup. The early mock-up card that said Tasmania and Queensland was not used.
- **Royal Gala** includes Gala as an alias so one tasting covers both names. The 1993 WA journal describes Royal Gala as a more highly coloured mutation of Gala.
- **Yello** is marked unverified because two trade articles disagree on whether the Golden Delicious × Senshu cross was made in 1983 or 1993.
- **Greenstar** is listed from the APAL exporter directory, not from a current supermarket ranging guide.
- **Kissabel** is included because an Adelaide Hills orchard grows it. National supermarket distribution was not confirmed.
- **Dutch, purple, and yellow carrots, and cherry tomato**, are shop types, not single cultivars. Their facts are empty.
- **Cotton Candy** is a novelty grape bred in California. Australian growing regions were not confirmed, so the regions list is empty. The greenhouse bed is where the app plants it, not a claim about how it is farmed.
- Several skin colours are explicitly unverified in `skinNote`. Do not treat those hex values as botanical descriptions.

## Art

Fruit, trees, beds, trellises, the greenhouse, the tractor, and each farmhouse stage are drawn in SwiftUI from the variety colour data. To replace a drawing later, add an image set to `Assets.xcassets`:

- `variety-<id>` replaces the fruit glyph (`variety-pink-lady`)
- `plant-<id>` replaces the whole plant on the farm

Until those assets exist, the procedural drawing is used.

## Tests

`OrchardTests` covers the rating-to-plant rules, the house thresholds, supermarket search, sticker and PLU matching, plot coordinates, and internal checks on `catalogue.json`. On a Mac:

```bash
xcodebuild test -scheme Orchard -destination 'platform=iOS Simulator,name=iPhone 16'
```
