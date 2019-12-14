#! /usr/bin/env bash
#TODO check if target exists, if not run search again, if fail, set a lock
set -ueo pipefail

d="$(dirname $0)"
FILENAME="$d/private.loc" #TODO change this to not be inside the repo or something

salt=7DC03B96584031776E91EB4D7A5D4472
target=81c82cd090df5eed4a287305c0ee8a8e27ee30650c4c7fab46c577f270852925

[ -f "$FILENAME" ] || "$d/find.py" / "$salt" "$target" > "$FILENAME"; #TODO just have the script have a -r mode?
cat "$FILENAME"
