#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
project_file="$repository_root/WindowRanger.xcodeproj"
bundle_identifier="dev.appranger.WindowRanger"
mode="${1:-interactive}"

case "$mode" in
    interactive|--scheme-action|--check) ;;
    -h|--help)
        print "Usage: ${0:t} [--check | --scheme-action]"
        print ""
        print "Gracefully quits any running WindowRanger before a Debug session."
        print "Without an option, it also opens the Xcode project."
        exit 0
        ;;
    *)
        print -u2 "Unknown option: $mode"
        exit 2
        ;;
esac

running_instances() {
    /usr/bin/osascript -l JavaScript - "$bundle_identifier" "$1" <<'JXA'
ObjC.import("AppKit")

function run(arguments) {
    const bundleIdentifier = arguments[0]
    const shouldTerminate = arguments[1] === "terminate"
    const applications = $.NSWorkspace.sharedWorkspace.runningApplications
    const matches = []

    for (let index = 0; index < applications.count; index += 1) {
        const application = applications.objectAtIndex(index)
        const identifier = application.bundleIdentifier
        if (identifier.isNil() || ObjC.unwrap(identifier) !== bundleIdentifier) {
            continue
        }

        const bundleURL = application.bundleURL
        const path = bundleURL.isNil() ? "unknown path" : ObjC.unwrap(bundleURL.path)
        matches.push(`${application.processIdentifier}|${path}`)

        if (shouldTerminate && !application.terminate) {
            throw new Error(`WindowRanger refused the quit request (PID ${application.processIdentifier})`)
        }
    }

    return matches.join("\n")
}
JXA
}

current_instances="$(running_instances inspect)"

if [[ "$mode" == "--check" ]]; then
    if [[ -z "$current_instances" ]]; then
        print "WindowRanger is not running."
    else
        print "Running WindowRanger instance(s):"
        print -r -- "$current_instances" | /usr/bin/awk -F '|' '{ print "  PID " $1 ": " $2 }'
    fi
    exit 0
fi

if [[ -n "$current_instances" ]]; then
    print "Gracefully quitting the active WindowRanger before development..."
    running_instances terminate >/dev/null

    for attempt in {1..100}; do
        [[ -z "$(running_instances inspect)" ]] && break
        /bin/sleep 0.1
    done

    remaining_instances="$(running_instances inspect)"
    if [[ -n "$remaining_instances" ]]; then
        print -u2 "WindowRanger did not quit within 10 seconds."
        print -u2 "Quit it from its menu, then run this command again."
        exit 1
    fi
fi

if [[ "$mode" == "interactive" ]]; then
    [[ -d "$project_file" ]] || {
        print -u2 "Missing generated Xcode project: $project_file"
        exit 1
    }
    /usr/bin/open "$project_file"
    print "Development session prepared. Run the WindowRanger scheme in Xcode."
fi
