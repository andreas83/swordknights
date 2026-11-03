# Build, test and release pipeline

Everything here runs on **Godot 4.5.1-stable**, pinned by exact version in
every workflow. The engine binary and the export templates are downloaded from
the official GitHub release and verified against that release's own
`SHA512-SUMS.txt` before use.

- [Run every check locally](#run-every-check-locally)
- [Writing tests](#writing-tests)
- [The workflows](#the-workflows)
- [What the repository owner must enable](#what-the-repository-owner-must-enable)
- [Secrets](#secrets)
- [The COOP/COEP decision](#the-coopcoep-decision)
- [Decisions worth knowing about](#decisions-worth-knowing-about)
- [Bumping the pinned versions](#bumping-the-pinned-versions)

---

## Run every check locally

One command runs exactly what CI runs, in CI's order:

```bash
.github/scripts/check_all.sh
```

It needs `godot` on `PATH` (or `GODOT_BIN` pointing at it) and the Python
tooling:

```bash
pip install -r .github/requirements-ci.txt
```

It does not stop at the first failure — one run tells you everything that is
broken.

### The individual stages

Each stage is also a command of its own, and they are the same commands CI
invokes. Run them from the repository root.

| What | Command |
| ---- | ------- |
| Import (builds `.godot/`, registers global classes) | `godot --headless --path . --import` |
| Lint | `gdlint .` |
| Format check (advisory; see [below](#gdformat-is-advisory-everywhere)) | `gdformat --check scripts tools tests` |
| Format our code, in place | `gdformat scripts tools tests` |
| GDScript parse check | `.github/scripts/check_scripts.sh` |
| Boot smoke test | `.github/scripts/smoke_boot.sh` |
| Test suite | `.github/scripts/run_tests.sh` |
| Test suite, raw runner | `godot --headless --path . -s addons/gut/gut_cmdln.gd` |
| Web export | `godot --headless --path . --export-release "Web" build/web/index.html` |

> `gdlint` resolves `.gdlintrc` from the **current working directory**
> upwards, so it only picks up this project's configuration when run from the
> repository root.
>
> `gdformat` takes explicit paths because, unlike `gdlint`, it has no
> `excluded_directories` setting — a bare `gdformat .` would also rewrite
> vendored GUT under `addons/` and the prototypes under `legacy/`.

Run the import at least once before the test suite: GUT's test scripts
`extends GutTest`, and that class name only resolves once the global class
registry in `.godot/` exists.

---

## Writing tests

The harness is **GUT (Godot Unit Test) 9.6.1**, vendored at
`addons/gut/`.

### Conventions — write new tests this way

| | |
| --- | --- |
| Where tests live | `tests/`, in subdirectories by kind — `tests/unit/` today |
| File name | **`test_*.gd`** — the `test_` prefix is how GUT finds them |
| Base class | `extends GutTest` |
| Test function name | `func test_*() -> void:` |
| Run them | `.github/scripts/run_tests.sh` |

Subdirectories of `tests/` are searched recursively, so you can add
`tests/gameplay/`, `tests/levels/` and so on without touching any
configuration.

### The other kind: standalone `*_test.gd` scripts

`tests/` also holds a test written before this harness existed —
`tests/tuning_grammar_test.gd`. It `extends SceneTree`, asserts for itself and
`quit()`s with a status, and is run directly:

```bash
godot --headless --path . --script res://tests/tuning_grammar_test.gd
```

GUT cannot collect those: they do not extend `GutTest` and they do not match
its `test_*` prefix. So `run_tests.sh` runs them as an explicit **second
phase** after the GUT suite, discovering them by the mirrored naming
convention:

| Suffix `*_test.gd` | standalone `SceneTree` script, run directly |
| ------------------ | ------------------------------------------- |
| **Prefix `test_*.gd`** | **GUT test, collected into the suite** |

This is a bridge, not a second supported harness. Without it a standalone test
would be silently skipped, which is the worst outcome available: the coverage
is gone *and* the build is green. Both phases fail the build, so nothing is
silent either way.

**New tests should be GUT.** Porting `tuning_grammar_test.gd` is a small job —
`extends GutTest`, rename to `tests/unit/test_tuning_grammar.gd`, and swap its
`_equal`/`_true` helpers for `assert_eq`/`assert_true`, which already report
far better failure messages. Once `tests/` holds no `*_test.gd` files, phase
two becomes a no-op and the block in `run_tests.sh` can go.

Selection is configured once, in `.gutconfig.json` at the repository root, so
the script, the raw runner and the editor panel all agree on what the suite is.
Prefer adding a file over editing that config.

### A worked example

```gdscript
extends GutTest
## One sentence on what this file is responsible for.


func test_the_thing_does_what_it_says() -> void:
	assert_eq(2 + 2, 4, "a message that explains the intent, not the maths")
```

Useful GUT facilities: `add_child_autofree()` to put a node in the live tree and
have it freed at the end of the test, `await wait_physics_frames(n)` to let
`_physics_process` run (note: **not** `wait_frames`, which is deprecated), and
`assert_is`, `assert_has`, `assert_gt` and friends. Full reference:
<https://gut.readthedocs.io>.

### Two things that will fail your test for you

- **Engine errors and `push_error` fail the test.** `.gutconfig.json` sets
  `failure_error_types` to `["engine", "gut", "push_error"]`, which is GUT's
  default. A test that triggers an engine error fails even if every assert
  passes. `push_warning` is allowed through.
- **Zero tests is a failure.** `run_tests.sh` reads GUT's JUnit report and
  fails if it reports no tests. This is deliberate: GUT's CLI entry point
  `quit(0)`s if the project's class cache has not been built, so a job checking
  only the exit code would go green having run nothing.

### Keep a test file under twenty tests

`.gdlintrc` sets `max-public-methods: 20`, and every `test_*` function counts
as public. Twenty tests in one file is the point at which it is covering more
than one thing — split it rather than raising the limit.

### The existing smoke tests

Two files, twelve tests, which exist to prove the harness works end to end:

- `tests/unit/test_project_settings.gd` — asserts that the settings
  `tools/configure_project.gd` claims to write are actually in effect
  (viewport, stretch mode, physics tick, renderer, texture filter, and that
  every input action is mapped and has events bound). These guard the project's
  rule that configuration lives in code and not in editor state: change a
  setting through the editor UI without updating the script and these fail.
- `tests/unit/test_boot_scene.gd` — loads `scenes/boot.tscn`, instantiates it
  into the live tree, runs `_ready()`, and checks the constant naming the scene
  it hands off to.

---

## The workflows

### `android.yml` — a debug APK on every push to `main`

For trying the game on a phone. Exports the Android preset as a **debug**
build on every push to `main` (documentation-only pushes aside) and on demand
from the Actions tab, signs it with the standard Android debug identity
generated inside the run, verifies the signature with `apksigner`, and uploads
it as the run's artifact `swordknights-debug-apk`, kept fourteen days. It needs
no secrets. To install: open the run, download the artifact, unzip, open the
`.apk` on the phone and allow installing from that app. A debug build cannot be
installed over a release build of the same package, or the reverse.

Three things every export job needed, found when this one was first run — the
web deploy had been failing on every push since the pipeline was written:

- **Template directory name.** Godot looks for its export templates under
  `export_templates/4.5.1.stable` — a dot before the suffix — and writes the
  same into `version.txt`. `setup-godot` installed them under the dashed
  release name, `4.5.1-stable`, and compared the two spellings.
- **ETC2/ASTC.** Godot's Android exporter refuses to export unless
  `rendering/textures/vram_compression/import_etc2_astc` is on, and headless
  it says so with an empty list of reasons. It is set in
  `tools/configure_project.gd`; the pixel art is imported lossless, so it
  changes nothing on screen.
- **SDK and JDK paths.** These live in Godot's editor settings, not the
  project, and on a fresh runner Godot guesses `~/Android/Sdk`. Both Android
  workflows write `ANDROID_HOME` and `JAVA_HOME` into the editor settings after
  the import step.

### `ci.yml` — on push to `main` and on every pull request

Two jobs, run in parallel.

**`lint`** — Python 3.12, `gdtoolkit` pinned in
`.github/requirements-ci.txt`.

1. `gdlint .` — blocking.
2. `gdformat --check tests` — blocking.
3. `gdformat --check scripts tools` — advisory, see
   [below](#gdformat-is-advisory-everywhere).

**`check`** — Godot 4.5.1, no export templates (they are a 1.3 GB download and
nothing in this job exports).

1. `godot --headless --path . --import` — builds the import cache, the UID cache
   and the global class registry.
2. `.github/scripts/check_scripts.sh` — parse-checks every `.gd` file we own.
3. `.github/scripts/smoke_boot.sh 60` — boots the project headlessly and fails
   on any engine or script error.
4. `.github/scripts/run_tests.sh` — the GUT suite, with the JUnit report
   uploaded as an artifact (`gut-test-results`) whether it passes or fails.

Why three separate validation steps rather than one:

> **`--import` does not fail on a GDScript parse error.** Verified on 4.5.1: a
> file containing deliberate garbage imported "successfully" with exit code 0.
> The only parse check the engine offers is `--check-only`, whose help text is
> explicit that it is "use with `--script`" — one file per invocation — so
> `check_scripts.sh` drives it in a loop and aggregates the failures.
>
> And a file can parse perfectly and still fail the moment the scene tree
> touches it. `smoke_boot.sh` catches that class of problem, and because Godot
> prints runtime errors but still exits 0, it reads the output rather than
> trusting the exit code.

### `pages.yml` — on push to `main`, and on demand

Exports the Web build and deploys it to GitHub Pages. This is how the game gets
playtested from a link.

It also **verifies the export before publishing**: `index.html`, `index.js`,
`index.wasm` and `index.pck` must all exist and be non-empty, and the build
must contain no `*.worker.js`. That last check is the guard on the
[COOP/COEP decision](#the-coopcoep-decision) — a worker file means the threaded
template was used, which cannot work on Pages, and failing the build is better
than publishing a game that will not boot.

It drops a `.nojekyll` file so Pages does not run the output through Jekyll
(which strips paths beginning with an underscore).

`concurrency` is set to one deployment at a time and deliberately **not**
`cancel-in-progress`: cancelling a Pages deployment midway can leave the site
half-published.

### `release.yml` — on tag `v*`

Four jobs. `.github/scripts/stamp_version.sh` writes the tag into
`export_presets.cfg` inside the runner first, so the committed file can keep a
placeholder version. `v1.2.3` becomes `version/name "1.2.3"` and
`version/code 10203`, which keeps the Android version code rising with the tag.
A tag that is not `vMAJOR.MINOR.PATCH` fails the job rather than being stamped
as nonsense.

| Job | Runner | Produces |
| --- | ------ | -------- |
| `web` | `ubuntu-latest` | `swordknights-<tag>-web.zip` |
| `android` | `ubuntu-latest` | `swordknights-<tag>.apk`, signed, and verified with `apksigner verify` |
| `ios` | `macos-latest` | `.ipa` if signing secrets are set, otherwise a zipped Xcode project |
| `publish` | `ubuntu-latest` | the GitHub Release, with everything above attached |

The `ios` job is `continue-on-error: true` — best effort by design. Without an
Apple Developer team id, a signing identity and a provisioning profile there is
no signed `.ipa` to be had, and the release should still go out with Web and
Android.

`publish` uses the preinstalled `gh` CLI rather than a third-party release
action, and uploads with `--clobber`, so re-running the workflow on the same tag
is idempotent.

The Android job uses the Android SDK that is **already on the GitHub-hosted
ubuntu image** and fails with a clear message if it is absent, so there is no
third-party setup action in this pipeline. Every action used is first-party
`actions/*` or the local composite action, each pinned to a major version tag.

### `.github/actions/setup-godot` — the shared installer

A local composite action used by all three workflows. It caches the editor
(`godot-editor-<os>-<version>`) and, when asked, the export templates
(`godot-templates-<version>`), verifies both against the release's
`SHA512-SUMS.txt`, puts `godot` on `PATH`, exports `GODOT_BIN`, and then
**asserts that the version it installed is the version that was requested** —
so a stale cache entry restored under the right key cannot silently build the
wrong engine. With `templates: 'true'` it additionally checks the templates'
`version.txt` against the editor version.

### `.github/dependabot.yml`

Watches `github-actions` only, weekly, with routine `actions/*` minor and patch
bumps grouped into a single PR. Nothing else in the repository has a manifest
Dependabot understands — Godot is pinned by version string in the workflows,
GUT is vendored, and `gdtoolkit` is pinned in `.github/requirements-ci.txt`.
Those three move by hand; see
[Bumping the pinned versions](#bumping-the-pinned-versions).

---

## What the repository owner must enable

Three things, all in the repository's own settings. Until the first two are
done, `pages.yml` will fail.

1. **Pages source must be GitHub Actions.**
   *Settings → Pages → Build and deployment → Source: **GitHub Actions***.
   Not "Deploy from a branch" — this pipeline publishes an artifact, there is
   no `gh-pages` branch.

2. **Workflow permissions.**
   *Settings → Actions → General → Workflow permissions*. The workflows each
   request what they need in their own `permissions:` block, so the repository
   default can and should stay at **Read repository contents and packages
   permissions**. What must be allowed is that workflows *can* request more:
   if your organisation restricts `GITHUB_TOKEN` permissions, `pages.yml` needs
   `pages: write` and `id-token: write`, and `release.yml` needs
   `contents: write`.

3. **A `github-pages` environment** is created automatically on the first Pages
   deployment. If your organisation requires environment approvals, that
   environment will need a reviewer or the deployment will sit pending.

Nothing else. No self-hosted runners, no org-level secrets, and no third-party
app installations.

---

## Secrets

Set under *Settings → Secrets and variables → Actions → Repository secrets*.
None of these are needed for `ci.yml` or `pages.yml` — only `release.yml` reads
them.

### Android — required for a release

| Secret | What it is |
| ------ | ---------- |
| `ANDROID_KEYSTORE_BASE64` | The release keystore, base64-encoded |
| `ANDROID_KEYSTORE_ALIAS` | The key alias inside that keystore |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore/key password |

Generate a keystore once and keep it somewhere safe — if you lose it you cannot
ship an update to an existing Play Store listing.

```bash
keytool -genkeypair -v \
  -keystore swordknights-release.keystore \
  -alias swordknights \
  -keyalg RSA -keysize 4096 -validity 10000

# What goes into ANDROID_KEYSTORE_BASE64:
base64 -w0 swordknights-release.keystore
```

The workflow decodes it into `$RUNNER_TEMP/signing/` — outside the workspace,
so it cannot be swept into an export or an artifact — `chmod 600`s it, and
deletes it in an `if: always()` step.

**No Android credential is ever written into `export_presets.cfg`.** Godot 4.5
reads the keystore straight out of the environment, which the workflow sets from
these secrets:

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH
GODOT_ANDROID_KEYSTORE_RELEASE_USER
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
```

### iOS — optional; without them the job still produces an Xcode project

| Secret | What it is |
| ------ | ---------- |
| `IOS_TEAM_ID` | Apple Developer team id, 10 characters |
| `IOS_CODE_SIGN_IDENTITY` | e.g. `Apple Distribution: Your Name (TEAMID)` |
| `IOS_PROVISIONING_PROFILE_UUID` | UUID of the provisioning profile |

Unlike Android, Godot has **no environment-variable path** for these — they
have to be in the preset. So the committed preset keeps them empty and
`.github/scripts/ios_signing_overlay.sh` writes them in the runner at build
time, never echoing the values back into the log. All three must be set; with
any of them missing the script leaves `application/export_project_only=true`
and the export emits an Xcode project instead of a signed `.ipa`.

A genuinely store-ready `.ipa` also needs the provisioning profile and the
signing certificate installed into a keychain on the macOS runner. That is not
wired up here — it is the remaining work on the iOS path.

---

## The COOP/COEP decision

**The Web preset is built single-threaded, and that is why it works on GitHub
Pages.**

Godot's threaded web export uses `SharedArrayBuffer`, and browsers only hand
that out to a cross-origin-isolated document — one served with:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

GitHub Pages serves static files and cannot set response headers. There are
only two ways out, and this project takes the first:

1. **Don't use threads.** `variant/thread_support=false` in
   `export_presets.cfg` makes Godot link its `web_nothreads_release` template,
   which never touches `SharedArrayBuffer` and needs no headers at all.
2. Ship the service-worker COEP shim (Godot's
   `progressive_web_app/ensure_cross_origin_isolation_headers`), which
   synthesises the headers from a service worker.

Option 1 was chosen. Verified locally: the exported `index.wasm` is
byte-identical to `web_nothreads_release.zip`'s `godot.wasm`, and no
`*.worker.js` is emitted. `pages.yml` re-checks the absence of that worker file
on every deploy.

### What it costs

- **No threaded WebAssembly.** Resource loading, asset decompression and audio
  mixing all run on the main thread. For a 320×180 pixel-art 2D platformer on
  the `gl_compatibility` backend this is not a meaningful loss; for a 3D game
  with heavy streaming it would be.
- **`WorkerThreadPool` is a no-op.** Any gameplay code that offloads work to a
  thread will silently run synchronously on web. Worth knowing before writing
  threaded code.
- Slightly larger `.wasm` (~38 MB uncompressed, ~9 MB over the wire gzipped)
  than the threaded build.

### Why not the service-worker shim

It would have let threads work on Pages, but it costs more than it gives here:
it requires `progressive_web_app/enabled=true`, which installs a service
worker that aggressively caches the build — exactly the wrong behaviour for a
playtest link, where every push should be the build you get. It also only
takes effect from the *second* page load, and it fails on any browser where the
service worker does not register.

### If you ever do need threads

Set `variant/thread_support=true`, set
`progressive_web_app/enabled=true` and
`progressive_web_app/ensure_cross_origin_isolation_headers=true`, and expect
the stale-cache behaviour — or host the build somewhere you control headers
(Cloudflare Pages, Netlify, S3 + CloudFront) and drop the shim. The guard in
`pages.yml` will fail the deploy until you do one of the two, which is the
point of it.

---

## Decisions worth knowing about

### Two gdlint rules are disabled, and why

`gdlint` is a hard gate everywhere. `.gdlintrc` is gdlint's own default rule
set with the directories that are not ours excluded (`legacy/`, `addons/`,
`.godot/`, `build/`) and exactly two rules turned off, both because they
misfire on idiomatic GDScript rather than because they found something
inconvenient:

- **`class-definitions-order`** — gdlint wants plain `var` before
  `@onready var`, and `const` before both. This codebase consistently does the
  opposite and puts the node references at the top of the class
  (`scripts/core/game.gd`, `scripts/player/player_input.gd`,
  `scripts/render/parallax_sky.gd`). That is the common Godot idiom and it puts
  the scene wiring where you look for it. The rule encodes one ordering
  opinion; the codebase has a different, consistent one.
- **`max-returns`** — counts every returning arm of a `match` as a separate
  return. `AsciiLevel.atlas_for()` (8 arms, tile kind → atlas coordinates) and
  `PlayerArt._posture()` (14 arms, state → pose) are dispatch tables, which is
  the clearest form GDScript offers. On this codebase the rule is almost
  entirely false positives.

Nothing else is switched off. In particular `unused-argument` stays on — see
[the open finding](#one-open-lint-finding) below.

### `gdformat` is advisory everywhere

It is run on every CI run and reported, but it fails nothing. The repository
has never been through it: `gdformat --check scripts tools tests` currently
wants to rewrite 19 of 28 files. Some of that is harmless line-joining, but
some loses information — in `tools/configure_project.gd` it strips the blank
lines that group the settings dictionary into four commented sections and
double-parenthesises a `print()`.

Making it a gate would mean reformatting most of the gameplay code, which is
under active development by two other workstreams. Adopting a formatter is a
project decision that wants its own commit, not something a build-pipeline
change should force through.

**To adopt it properly**, once the gameplay work has settled:

1. `gdformat scripts tools tests`, review the diff, commit it on its own.
2. In `ci.yml`, drop `continue-on-error: true` from the `gdformat` step.

### `.import` and `.uid` files **are** committed

This is the convention `main` settled on — every `scripts/**/*.gd.uid`,
`icon.svg.import` and `assets/tiles.png.import` is tracked — and it matches
Godot's own recommendation: committing them makes a fresh clone's first import
deterministic and keeps resource UIDs stable across machines.

This pipeline adds no such files of its own beyond those shipped inside
`addons/gut/`. The `.uid` files for anything added under `tests/` are
generated on the next import; commit them along with the test.

### One open lint finding

`gdlint` reports exactly one real problem against `main` as merged:

```
scripts/player/player.gd:355: Error: unused function argument 'delta' (unused-argument)
```

`_update_ladder(delta: float)` does not use `delta`. It is one of a family of
`_update_*(delta)` state handlers dispatched uniformly, so the signature is
right to keep — the fix is to mark the argument intentionally unused, which is
a one-character change gdlint's `function-argument-name` rule already allows:

```gdscript
func _update_ladder(_delta: float) -> void:
```

This was deliberately **not** fixed here: `scripts/` belongs to the gameplay
workstreams and a build-pipeline change has no business editing a 448-line file
someone else has open. The rule was left enabled rather than silenced, so CI
will stay red on this one line until it is fixed — which is the pipeline doing
its job, not a defect in it.

### The GUT editor panel is not enabled

The command-line runner does not need the editor plugin, so nothing enables it
and `project.godot` is untouched. If you want the GUT panel inside the editor,
add this one setting to `tools/configure_project.gd`'s `_apply_settings()` and
re-run it:

```gdscript
"editor_plugins/enabled": PackedStringArray(["res://addons/gut/plugin.cfg"]),
```

### Everything excluded from shipped builds

All three presets carry
`exclude_filter="tests/*, addons/gut/*, .gutconfig.json"`, so the test suite and
the test framework are not packed into the game. `legacy/` needs no exclusion —
it carries a `.gdignore`, so the engine never sees it at all.

---

## Bumping the pinned versions

| Thing | Pinned in | How |
| ----- | --------- | --- |
| Godot | `GODOT_VERSION` in each of the three workflows | Change all three. The composite action verifies the binary reports the version asked for, so a mismatch fails loudly rather than silently. Also update `config/features` in `project.godot` on a minor bump. |
| Export templates | — | Follows `GODOT_VERSION` automatically; the action checks `version.txt` matches the editor. |
| `gdtoolkit` | `.github/requirements-ci.txt` | Bump, run `gdlint .`, fix what the new rules find in the same PR. |
| GUT | vendored at `addons/gut/` | Replace the directory from the upstream release. Currently **9.6.1**, from tag `v9.6.1` (commit `c80954f47bed74a0a2c471d472c0389f98e0a8f6`) of <https://github.com/bitwes/gut>. Copy its `addons/gut/` over ours, keep `LICENSE.md` (MIT), re-import and run the suite. |
| GitHub Actions | `uses:` lines | Dependabot opens the PRs. |
