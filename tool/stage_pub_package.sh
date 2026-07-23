#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: tool/stage_pub_package.sh packages/<package> [empty-output-dir]" >&2
  exit 64
fi

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
relative_source=$1
case "$relative_source" in
  packages/glint_*) ;;
  *)
    echo "package must be a packages/glint_* directory" >&2
    exit 64
    ;;
esac

source_dir="$repo_root/$relative_source"
if [ ! -f "$source_dir/pubspec.yaml" ] || [ ! -f "$source_dir/.pubignore" ]; then
  echo "package must contain pubspec.yaml and .pubignore" >&2
  exit 66
fi

if [ "$#" -eq 2 ]; then
  stage_dir=$2
  mkdir -p "$stage_dir"
  if [ -n "$(find "$stage_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "output directory must be empty: $stage_dir" >&2
    exit 73
  fi
else
  stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/glint-pub.XXXXXX")
fi

rsync -a --exclude-from="$source_dir/.pubignore" "$source_dir/" "$stage_dir/"
echo "$stage_dir"
