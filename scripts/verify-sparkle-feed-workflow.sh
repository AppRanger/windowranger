#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
test_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/windowranger-sparkle-feed-test.XXXXXX")"
release_root="$test_root/releases"
feed_directory="$test_root/feed"
fake_sparkle_bin="$test_root/sparkle-bin"
failing_sparkle_bin="$test_root/failing-sparkle-bin"

cleanup() {
    [[ "$test_root" == "${TMPDIR:-/tmp}/windowranger-sparkle-feed-test."* ]] || return
    /bin/rm -R -- "$test_root"
}
trap cleanup EXIT INT TERM

/bin/mkdir -p "$release_root" "$feed_directory" "$fake_sparkle_bin" "$failing_sparkle_bin"

# This deterministic stand-in models the part of generate_appcast that previously caused the
# regression: on every run, all retained enclosure URLs are rewritten from the supplied prefix.
/usr/bin/tee "$fake_sparkle_bin/generate_appcast" >/dev/null <<'FAKE_GENERATOR'
#!/bin/zsh
set -euo pipefail
prefix=""
output=""
source_directory="${argv[-1]}"
while (( $# > 1 )); do
    case "$1" in
        --download-url-prefix) prefix="$2"; shift ;;
        -o) output="$2"; shift ;;
        --account|--link|--versions|--maximum-versions|--channel) shift ;;
        --embed-release-notes) ;;
    esac
    shift
done
[[ -n "$prefix" && -n "$output" ]]
{
    print '<?xml version="1.0" encoding="utf-8"?>'
    print '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>'
    for archive in "$source_directory"/WindowRanger-*.zip(N); do
        name="${archive:t}"
        version="${name#WindowRanger-}"
        version="${version%.zip}"
        build="${version##*.}"
        print "<item><sparkle:version>ignored</sparkle:version><enclosure url=\"$prefix$name\" sparkle:version=\"$build\"/><sparkle:channel>beta</sparkle:channel></item>"
    done
    print '</channel></rss>'
} > "$output"
FAKE_GENERATOR
/bin/chmod +x "$fake_sparkle_bin/generate_appcast"

/usr/bin/tee "$failing_sparkle_bin/generate_appcast" >/dev/null <<'FAILING_GENERATOR'
#!/bin/zsh
exit 42
FAILING_GENERATOR
/bin/chmod +x "$failing_sparkle_bin/generate_appcast"

make_release_fixture() {
    local version="$1"
    local build_number="$2"
    local release_directory="$release_root/$version"
    local archive_name="WindowRanger-$version.zip"

    /bin/mkdir -p "$release_directory"
    print -r -- "fixture archive $version" > "$release_directory/$archive_name"
    {
        print "version=$version"
        print "build_number=$build_number"
    } > "$release_directory/WindowRanger-$version.release.txt"
    (cd "$release_directory" && /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256")
    print -r -- "Release notes for $version" > "$release_directory/notes.txt"
}

run_feed_update() {
    local version="$1"
    local sparkle_bin="$2"
    WINDOWRANGER_RELEASE_ROOT="$release_root" \
        WINDOWRANGER_TEST_RELEASE_INPUTS=1 \
        "$repository_root/scripts/generate-update-appcast.sh" \
        --version "$version" \
        --feed-directory "$feed_directory" \
        --sparkle-bin "$sparkle_bin" \
        --release-notes "$release_root/$version/notes.txt" >/dev/null
}

make_release_fixture 1.0.0-beta.8 8
make_release_fixture 1.0.0-beta.9 9
print '8\t1.0.0-beta.8\tallocated\tTwo-release workflow fixture' > "$release_root/release-builds.tsv"
run_feed_update 1.0.0-beta.8 "$fake_sparkle_bin"
{
    print '8\t1.0.0-beta.8\tpublished\tTwo-release workflow fixture'
    print '9\t1.0.0-beta.9\tallocated\tTwo-release workflow fixture'
} > "$release_root/release-builds.tsv"
run_feed_update 1.0.0-beta.9 "$fake_sparkle_bin"

appcast="$feed_directory/appcast.xml"
[[ "$(/usr/bin/grep -c 'https://windowranger.com/updates/WindowRanger-1.0.0-beta.[89].zip' "$appcast")" == 2 ]] || {
    print -u2 "Two-release fixture did not retain both stable-prefix enclosure URLs"
    exit 1
}
for version in 1.0.0-beta.8 1.0.0-beta.9; do
    [[ -f "$feed_directory/WindowRanger-$version.zip" ]] || {
        print -u2 "Two-release fixture lost archive $version"
        exit 1
    }
done

before_failure="$test_root/feed-before-failure.sha256"
after_failure="$test_root/feed-after-failure.sha256"
(cd "$feed_directory" && /usr/bin/find . -type f -print0 | /usr/bin/sort -z | /usr/bin/xargs -0 /usr/bin/shasum -a 256) > "$before_failure"
make_release_fixture 1.0.0-beta.10 10
{
    print '8\t1.0.0-beta.8\tpublished\tTwo-release workflow fixture'
    print '9\t1.0.0-beta.9\tpublished\tTwo-release workflow fixture'
    print '10\t1.0.0-beta.10\tallocated\tAtomic failure fixture'
} > "$release_root/release-builds.tsv"
if run_feed_update 1.0.0-beta.8 "$fake_sparkle_bin" 2>/dev/null; then
    print -u2 "A stale release branch bypassed the authoritative build allocation"
    exit 1
fi
if run_feed_update 1.0.0-beta.10 "$failing_sparkle_bin" 2>/dev/null; then
    print -u2 "Failing appcast generator unexpectedly succeeded"
    exit 1
fi
(cd "$feed_directory" && /usr/bin/find . -type f -print0 | /usr/bin/sort -z | /usr/bin/xargs -0 /usr/bin/shasum -a 256) > "$after_failure"
/usr/bin/cmp -s "$before_failure" "$after_failure" || {
    print -u2 "A failed appcast generation mutated the original feed"
    exit 1
}

print "Sparkle two-release, publication-order, and atomic-failure feed workflow verified."
