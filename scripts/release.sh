#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

die() {
    echo "$@" >&2
    exit 1
}

if [ -z "${GITHUB_USER:-}" ]; then
  die "GITHUB_USER is not set."
fi

if [ -z "${GITHUB_REPO:-}" ]; then
  die "GITHUB_REPO is not set."
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  die "GITHUB_TOKEN is not set."
fi

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  die "USAGE: $0 VERSION"
fi

./scripts/cross_build.sh "$VERSION"

CHANGELOG=$(go run scripts/extract_changelog.go "$VERSION")

echo "Releasing $VERSION"
echo ""
echo "CHANGELOG:"
echo "$CHANGELOG"
echo ""

UPLOADS_URL=$( \
  echo '{}' | \
    jq -Mr \
      --arg version "$VERSION" \
      --arg changelog "$CHANGELOG" \
      '. + {
        tag_name: $version,
        name: $version,
        body: $changelog,
      }' | \
    curl --user "$GITHUB_USER:$GITHUB_TOKEN" -X POST --data @- \
      "https://api.github.com/repos/$GITHUB_REPO/releases" | \
    jq -e -r '.upload_url' | \

    # The UPLOADS_URL has a strange {?name,label} as a suffix that we need to remove.
    # E.g., https://uploads.github.com/repos/yarpc/yab/releases/11488347/assets{?name,label}
    cut -d '{' -f1)

# Upon creating a release, we get back the URL to which assets should be
# uploaded under .uploads_url.
#
# See https://developer.github.com/v3/repos/releases/#create-a-release for
# more information.

for FILE in build/yab-"$VERSION"-*.zip; do
  echo "Uploading $FILE"

  # See https://developer.github.com/v3/repos/releases/#upload-a-release-asset
  UPLOAD_URL="${UPLOADS_URL}?name=$(basename "$FILE")"
  curl --user "$GITHUB_USER:$GITHUB_TOKEN" -X POST \
    --data-binary @"$FILE" -H 'Content-Type: application/zip' \
    "$UPLOAD_URL"
done
