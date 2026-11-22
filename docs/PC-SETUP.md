# Setting up your PC (Milestone A)

This puts the AI on your PC and checks that it uses your graphics card. It takes about
30 minutes, mostly waiting for downloads. You only click things; no typing commands.

## Part 1: Get the code onto your PC (once)

We'll use **GitHub Desktop**, because it makes updates one click later.

1. On your PC, open a browser and go to **desktop.github.com**. Click **Download for Windows**,
   then open the file you downloaded. It installs itself.
2. GitHub Desktop opens. Click **Sign in to GitHub.com** and sign in with your GitHub account
   (the same one you use on your phone). Click **Finish**.
3. Click **File** (top left) → **Clone repository...**. Find **Dunky64/VSKF** in the list
   and click it.
4. Under **Local path**, change the folder to `C:\DrivewayButler` (click in the box and type that
   short path, or leave it as it is). Click **Clone**.
5. At the top, click the button that says **Current branch: main**, and choose
   **claude/driveway-butler-kerbscore-f5k563**. (This is where I put the new work.)
6. Click **Repository** (top menu) → **Show in Explorer**. A folder opens. You should see
   `setup.bat`, `diagnose.bat`, `update.bat`, and some folders.

> No GitHub Desktop? You can also download a ZIP: on GitHub, switch to the branch above,
> tap **Code** → **Download ZIP**, then right-click the ZIP → **Extract All**. Updates are
> easier with GitHub Desktop, though.

## Part 2: Phone alerts app (2 minutes, free)

This lets the PC send reports (and later, new quote alerts) straight to your phone.

1. On your phone, install **ntfy** (App Store or Google Play, it's free, by Philipp Heckel).
2. Leave it for now. Setup will show you a topic name to subscribe to.

## Part 3: Run setup

1. In the folder from Part 1, double-click **`setup.bat`**.
2. If a blue box says **"Windows protected your PC"**, click **More info** → **Run anyway**.
   (Windows shows this for any new script. It's expected.)
3. A black window opens and works through **8 steps**. Each says **[OK]** in green,
   **[WARN]** in yellow or **[FAIL]** in red. The model download (step 5) shows a progress bar
   and takes the longest.
4. Step 7 tests 5 driveway photos. You should see something like:
   ```
   [1/5] sample_01.jpg:   4.2 s  block_paving, dirt 6/10, size M, confidence 0.8
   ...
   GPU check:            PASS - running fully on the graphics card
   ```
   If it says **FAIL** or **PARTIAL**, setup automatically tries a backup method (Vulkan).
5. At the end it says **SETUP FINISHED**, and shows your **phone alert topic**, something like
   `dwb-k7f3q9x2mn`. Write it down.

**If your graphics driver is old**, setup will say so. Go to **amd.com/support**, download
**AMD Software: Adrenalin Edition**, install it, restart the PC, then run `setup.bat` again.

## Part 4: Send me the report

1. On your phone, open **ntfy** → tap **+** → type your topic (e.g. `dwb-k7f3q9x2mn`) →
   **Subscribe**.
2. On the PC, double-click **`diagnose.bat`**. It takes about a minute.
3. The report arrives on your phone in ntfy. Long-press it → **Copy**, and paste it to me
   here. (If nothing arrives, run `diagnose.bat` once more now that you're subscribed.)

The report is also saved at `pc\local\diagnose-report.txt` and copied to the PC's clipboard.
It contains no personal details: just Windows version, graphics card, timings and errors.

## Later: updating

When I tell you there's an update: open GitHub Desktop → click **Fetch origin** → **Pull origin**,
or just double-click **`update.bat`**, which does the same and restarts the worker.

## Things to know

- Setup is safe to run again. It skips anything already done.
- Nothing is opened up to the internet on your PC. It only makes outgoing connections.
- Setup log files are in `pc\local\logs` if I ask for them.
