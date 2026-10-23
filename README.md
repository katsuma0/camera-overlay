# Same Spot

A camera for timelapses that take months. You pick a spot and take one photo. That photo shows up as a faint ghost over the camera every time you come back, so you can line it up and shoot from the same place. After enough days, it turns the photos into a video.

There are four tabs. Projects, Camera, Library, Settings. That's the whole app.

## Running it

1. Open `SameSpot.xcodeproj` in Xcode 16 or newer.
2. Click the SameSpot target, go to Signing & Capabilities, and pick your team. If Xcode says the bundle identifier is taken, change `com.katsumaonishi.SameSpot` to something of your own.
3. Plug in an iPhone on iOS 17 or later and press Run.

The simulator has no camera, so the app draws a fake backyard instead. Every button still works. To start with three weeks of photos already taken, go to Product, Scheme, Edit Scheme, Run, Arguments, and tick `-demo`.

## How it works

A project is one spot. Making one asks for a name and when you want reminders, then opens the camera so you can take the original. The original is also day one of the video.

From then on the camera ghosts the original over the live view at 35% strength. The slider changes that. If a scene has changed so much that the original doesn't help anymore (snow, leaves gone), switch the guide to your last photo instead. Flash, a 3 or 10 second timer, and a grid sit along the top of the camera.

Reminders are a list of times and a set of days. Morning and night every day is two times and all seven days. Tapping a reminder opens the camera on that project.

The camera is locked to the back 1x lens, and every photo in a project is taken at the orientation of the original, even if the phone is held differently. A landscape project stays landscape. Photos are saved as 12 MP HEIC in the app's own folder, not your camera roll.

The library shows when each photo was taken, sorts newest or oldest first, and the full screen viewer swipes in the same order. A bar with one tick per photo along the bottom lets you drag through a whole project.

Settings has the camera defaults, light or dark mode, haptics, the shutter blink, notification status, how much space the photos take, and an About page.

Make Timelapse turns the photos into an MP4 at 6, 12, 24 or 30 photos per second. Standard is 1440 × 1080 H.264, which plays anywhere. High is 2880 × 2160 HEVC. You can share it or save it to Photos.

## Things it doesn't do yet

- No iCloud sync. Photos live on the phone, and in your iPhone backup.
- No importing old photos from the camera roll.
- iOS keeps at most 64 pending reminders per app. Picking individual days instead of every day uses one reminder per day per time, so a lot of projects with a lot of custom days can hit that.

## Layout

- `SameSpot/Camera` is the capture screen, the session, and the simulator stand-in.
- `SameSpot/Model` is the project data and the JSON file it's saved to.
- `SameSpot/Projects`, `SameSpot/Library`, `SameSpot/Video` and `SameSpot/Settings` are the other screens.
- `.github/workflows/build.yml` builds the app on a Mac runner for every pull request and takes screenshots of each tab in the simulator.
