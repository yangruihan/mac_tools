#!/bin/sh
# Preserve the original single-file role; --sources restores a disposable source-tree copy.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -eq 2 ] && [ "$1" = '--sources' ]; then
    TARGET=${2%/}
    [ -d "$TARGET" ] && [ -f "$TARGET/MacTools.swift" ] || { echo 'Expected a copied MacTools source directory' >&2; exit 2; }
    BACKUP="$TARGET.before-rollback.$$"
    [ ! -e "$BACKUP" ] || { echo 'Backup path already exists' >&2; exit 2; }
    mv "$TARGET" "$BACKUP"
    mkdir -p "$TARGET"
    cp "$HERE/BASELINE.swift" "$TARGET/MacTools.swift"
    printf 'Prior source copy preserved: %s\n' "$BACKUP"
elif [ "$#" -eq 2 ] && [ "$1" = '--menu-bar' ]; then
    TARGET=${2%/}
    [ -f "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift" ] && [ -f "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift" ] || {
        echo 'Expected a copied MacTools project' >&2; exit 2;
    }
    cp "$HERE/BASELINE_MENU_BAR.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
    cp "$HERE/BASELINE_MENU_BAR_TESTS.swift" "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--crowded-menu-bar' ]; then
    TARGET=${2%/}
    [ -f "$TARGET/Sources/MacTools/MacTools.swift" ] && [ -f "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift" ] && [ -f "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift" ] || {
        echo 'Expected a copied MacTools project' >&2; exit 2;
    }
    cp "$HERE/BASELINE_CROWDED_APP.swift" "$TARGET/Sources/MacTools/MacTools.swift"
    cp "$HERE/BASELINE_CROWDED_MENU_BAR.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
    cp "$HERE/BASELINE_CROWDED_TESTS.swift" "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--ux' ]; then
    TARGET=${2%/}
    for FILE in Sources/MacTools/UI/ContentView.swift Sources/MacTools/UI/SharedControls.swift Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift Tests/MacToolsTests/MenuBarOrganizerTests.swift; do
        [ -f "$TARGET/$FILE" ] || { echo "Expected copied file: $FILE" >&2; exit 2; }
    done
    cp "$HERE/BASELINE_UX_CONTENT.swift" "$TARGET/Sources/MacTools/UI/ContentView.swift"
    cp "$HERE/BASELINE_UX_SHARED.swift" "$TARGET/Sources/MacTools/UI/SharedControls.swift"
    cp "$HERE/BASELINE_UX_MENU_BAR.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
    cp "$HERE/BASELINE_UX_TESTS.swift" "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--style-drag' ]; then
    TARGET=${2%/}
    for FILE in Sources/MacTools/UI/ContentView.swift Sources/MacTools/UI/SharedControls.swift Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift Tests/MacToolsTests/MenuBarOrganizerTests.swift; do
        [ -f "$TARGET/$FILE" ] || { echo "Expected copied file: $FILE" >&2; exit 2; }
    done
    cp "$HERE/BASELINE_STYLE_CONTENT.swift" "$TARGET/Sources/MacTools/UI/ContentView.swift"
    cp "$HERE/BASELINE_STYLE_SHARED.swift" "$TARGET/Sources/MacTools/UI/SharedControls.swift"
    cp "$HERE/BASELINE_DRAG_MENU_BAR.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
    cp "$HERE/BASELINE_DRAG_TESTS.swift" "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--signing-ux' ]; then
    TARGET=${2%/}
    [ -f "$TARGET/scripts/build-app.sh" ] && [ -f "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift" ] || {
        echo 'Expected a copied MacTools project' >&2; exit 2;
    }
    cp "$HERE/BASELINE_SIGNING.sh" "$TARGET/scripts/build-app.sh"
    cp "$HERE/BASELINE_DRAG_DIAGNOSTIC.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--icon-style' ]; then
    TARGET=${2%/}
    [ -f "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift" ] || {
        echo 'Expected a copied MacTools project' >&2; exit 2;
    }
    cp "$HERE/BASELINE_ICON_STYLE.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--direct-gesture' ]; then
    TARGET=${2%/}
    [ -f "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift" ] && [ -f "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift" ] || {
        echo 'Expected a copied MacTools project' >&2; exit 2;
    }
    cp "$HERE/BASELINE_DIRECT_GESTURE.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
    cp "$HERE/BASELINE_DIRECT_GESTURE_TESTS.swift" "$TARGET/Tests/MacToolsTests/MenuBarOrganizerTests.swift"
elif [ "$#" -eq 2 ] && [ "$1" = '--native-icon-click' ]; then
    TARGET=${2%/}
    [ -f "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift" ] || {
        echo 'Expected a copied MacTools project' >&2; exit 2;
    }
    cp "$HERE/BASELINE_NATIVE_CLICK.swift" "$TARGET/Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOrganizerPlugin.swift"
else
    [ "$#" -eq 1 ] || { echo 'usage: ROLLBACK.sh TARGET_FILE_COPY | --sources DIR | --menu-bar PROJECT | --crowded-menu-bar PROJECT | --ux PROJECT | --style-drag PROJECT | --signing-ux PROJECT | --icon-style PROJECT | --direct-gesture PROJECT | --native-icon-click PROJECT' >&2; exit 2; }
    cp "$HERE/BASELINE.swift" "$1"
fi
