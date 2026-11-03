extends RefCounted
## What this build is, written into the runner by .github/scripts/stamp_version.sh.
##
## The committed values describe a build nobody stamped: a run from the editor,
## a test, a local export. CI rewrites the five lines below in its own checkout
## before exporting and never commits the result, exactly as it does for
## export_presets.cfg -- a committed file cannot know the run it will be built
## in.
##
## Why a script of constants rather than a ConfigFile or a JSON file: scripts
## are packed into every export without an include_filter, a typo is a parse
## error that `check_scripts.sh` catches rather than a silent default at
## runtime, and reading it costs nothing. And why no `class_name`: this file is
## data, not an API. Readers `preload()` it, which also lets the stamp test
## load a stamped copy from elsewhere without it colliding with a registered
## global class of the same name.
##
## Android has its own copy of CODE and NAME in the manifest, but the engine
## offers no way to read the running package's version code back, so the app's
## idea of "which build am I" has to travel in the pack. stamp_version.sh
## writes both from the same arguments so they cannot disagree.
##
## CHANNEL is what turns the update check on: only "dev" builds call home, and
## only android.yml stamps "dev" (see DevUpdate.should_check). FEED is the
## version.json of the repository the build came from, so a fork's builds
## follow the fork.

const CODE := 1
const NAME := "0.1.0"
const SHA := ""
const CHANNEL := ""
const FEED := ""
