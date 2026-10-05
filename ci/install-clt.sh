#!/usr/bin/env bash
set -euo pipefail
approved='https://github.com/aichi-chishan/snap-hutao-data/releases/download/clt-26.0.0.821/clt-part-00'
if [[ "${DEVECO_CLT_URL:-}" != "$approved" ]]; then
  echo 'DEVECO_CLT_URL must match the reviewed CLT 26.0.0.821 part-00 URL exactly; other releases require reviewed pins.' >&2
  exit 1
fi
destination="${1:?Pass a new isolated tool directory}"
[[ ! -e "$destination" ]] || { echo 'Tool directory must not exist' >&2; exit 1; }
mkdir -p "$destination/downloads"
destination="$(cd "$destination" && pwd)"
base='https://github.com/aichi-chishan/snap-hutao-data/releases/download/clt-26.0.0.821'
for part in clt-part-00 clt-part-01; do
  curl --fail --location --max-redirs 3 --connect-timeout 30 --max-time 900 --retry 0 \
    --output "$destination/downloads/$part" "$base/$part"
done
python3 "$(dirname "$0")/verify-clt.py" "$destination"
clt="$destination/clt/command-line-tools"
[[ -x "$clt/bin/hvigorw" && -x "$clt/bin/codelinter" && -x "$clt/tool/node/bin/node" ]]
mkdir -p "$destination/hvigor-home" "$destination/npm-cache" "$destination/ohpm-cache" "$destination/tmp"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf '%s\n' "DEVECO_CLI_CLT_PATH=$clt" "DEVECO_SDK_HOME=$clt/sdk" \
    "DEVECO_NODE_HOME=$clt/tool/node" "NODE_HOME=$clt/tool/node" \
    "HVIGOR_USER_HOME=$destination/hvigor-home" "NPM_CONFIG_CACHE=$destination/npm-cache" \
    "npm_config_cache=$destination/npm-cache" "OHPM_CACHE=$destination/ohpm-cache" "TMPDIR=$destination/tmp" >> "$GITHUB_ENV"
  printf '%s\n' "$clt/bin" "$clt/tool/node/bin" >> "$GITHUB_PATH"
fi
printf 'Verified CLT: %s\n' "$clt"
