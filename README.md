# Barometer

SwiftUI iPhone barometer prototype for iPhone 14 Pro.

The app reads local pressure with `CMAltimeter`, gets the current location with `CoreLocation`, fetches nearby airport METAR data from NOAA Aviation Weather Center, and estimates altitude from local station pressure and airport sea-level pressure.

## Build

Codemagic workflow:

```text
ios-unsigned
```

The workflow produces:

```text
build/Barometer-unsigned.ipa
```

This IPA is unsigned and is intended for local signing/installing with Sideloadly.

## Install With Sideloadly

1. Download `Barometer-unsigned.ipa` from Codemagic artifacts.
2. Open Sideloadly and connect the iPhone.
3. Drag the IPA into Sideloadly.
4. Sign with a free Apple ID.
5. Trust the developer profile on the iPhone if prompted.

Free Apple ID installs usually need refreshing after 7 days.
