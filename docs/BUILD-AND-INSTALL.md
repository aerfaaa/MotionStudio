# Building and installing from Windows

You do not need a Mac, but the app can only be compiled on one. GitHub Actions gives you a Mac in the cloud
for free (for public repositories, as far as I know; check GitHub's current pricing page).

**Nothing here has been tested yet.** Treat the first run as an experiment, and expect to paste error
messages back to Claude to get them fixed.

## 0. What you need

- A free GitHub account.
- Git for Windows (download from git-scm.com).
- Your iPhone, a USB cable and a free Apple ID (only for installing, step 5).

## 1. Unzip the project

Open **Command Prompt** (press the Windows key, type `cmd`, press Enter). Type each line and press Enter:

```
cd %USERPROFILE%\Downloads
tar -xf MotionStudio.zip
cd MotionStudio
```

## 2. Create a NEW empty repository on GitHub

On github.com: **New repository**. Name it `motionstudio`. Choose **Public**.
Leave "Add a README", ".gitignore" and "license" all **unticked**. This is a fresh start; do not reuse any old repository.

## 3. Upload the project

Still in the Command Prompt window, inside the `MotionStudio` folder. Replace `YOUR-USERNAME` and your details:

```
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git init -b main
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR-USERNAME/motionstudio.git
git push -u origin main
```

A browser window may ask you to sign in to GitHub. If `git init -b main` is not recognised, use
`git init` and then `git branch -M main`.

## 4. Build it (manual, one button)

1. On GitHub open your repository, then the **Actions** tab. If asked, click the button to enable workflows.
2. Choose **Core tests**, then **Run workflow**. This is the fast check of the brain (MotionCore).
3. When it finishes, choose **iOS build**, then **Run workflow**. This takes several minutes.
4. A red cross means an error. Open the run, click the failed step and copy the red lines to Claude.
   Expect this on the first try: the code has never been compiled.
5. When it is green, scroll to **Artifacts** at the bottom of the run page:
   - `MotionStudio-unsigned-ipa` is the app file.
   - `simulator-screenshots` has pictures of the app on an iPhone and an iPad simulator (this job may fail on its own without stopping the rest).

## 5. Install on your iPhone (free route, with limits)

The downloaded app is **unsigned**. An iPhone will not run it until it is signed with an Apple ID.

Limits of the free route (from my understanding, not verified; check the tool's own instructions):
- The app stops opening after **7 days** and must be re-signed and reinstalled.
- Free Apple IDs can only keep a small number of sideloaded apps and new app IDs per week.
- Your iPhone needs **Developer Mode** turned on, and you must trust the developer profile.
- These tools ask for your Apple ID. A separate Apple ID just for this is a common precaution.
- No TestFlight and no App Store without a paid Apple Developer membership.

Steps with **Sideloadly** (a Windows tool; search for it and use only its official site):
1. Install iTunes and iCloud **from Apple's website** (not the Microsoft Store versions), as the Sideloadly instructions ask.
2. On GitHub, download the artifact (a `.zip`). In Command Prompt:
   ```
   cd %USERPROFILE%\Downloads
   tar -xf MotionStudio-unsigned-ipa.zip
   ```
   You now have `MotionStudio-unsigned.ipa`.
3. Connect your iPhone by cable and tap **Trust** on the phone.
4. Open Sideloadly, drag the `.ipa` in, enter your Apple ID, press **Start**.
5. On the iPhone: **Settings, General, VPN & Device Management**, trust your Apple ID.
6. If the iPhone asks for it: **Settings, Privacy & Security, Developer Mode**, turn on and restart.

**AltStore** is an alternative that can refresh the 7-day signing over Wi-Fi.

## 6. Where your projects are

In the **Files** app: **On My iPhone, Motion Studio, Projects**. Each project is a folder ending in `.motionproj`.

## 7. Changing the app name or bundle ID

Edit `project.yml` (`CFBundleDisplayName` and `PRODUCT_BUNDLE_IDENTIFIER`). The screenshot job in
`.github/workflows/ios-build.yml` also uses the bundle ID `com.example.motionstudio`, so change it there too.

## Not verified

GitHub Actions free minutes for macOS, the workflow files, XcodeGen's output, the Swift Actions version,
Sideloadly and AltStore behaviour, and every limit listed above. Re-check them when you reach each step.
