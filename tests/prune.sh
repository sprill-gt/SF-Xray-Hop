#!/usr/bin/env bash
set -euo pipefail
SFXH_CODE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export SFXH_TEST_MODE=1 SFXH_TEST_ROOT=$SFXH_CODE/.cache/prune-root
source "$SFXH_CODE/lib/common.sh"
source "$SFXH_CODE/lib/core.sh"
source "$SFXH_CODE/lib/transaction.sh"
sf_paths; sf_dirs
ids=()
for i in {0..10}; do
    hash=$(printf '%s' "$i" | sha256sum | cut -c1-16)
    ids[i]="v26.9.$i-$hash"
    mkdir -p "$SFXH_VAR/cores/${ids[i]}"
    jq -n --arg id "${ids[i]}" --arg at "$(printf '%02d' "$i")" --argjson verified "$([[ $i != 10 ]] && printf true || printf false)" \
       '{id:$id,verified:$verified,verifiedAt:$at}' > "$SFXH_VAR/cores/${ids[i]}/metadata.json"
    touch -d '2000-01-01' "$SFXH_VAR/cores/${ids[i]}"
done
for i in {1..20}; do
    name=$(printf 'g%02d' "$i"); path=$SFXH_ETC/generations/$name
    mkdir -p "$path"
    index=4; [[ $i != 1 ]] || index=2; [[ $i != 2 ]] || index=3; [[ $i != 20 ]] || index=1
    printf '%s\n' "${ids[index]}" > "$path/core-id"
    printf '{}\n' > "$path/state.json"; printf '{}\n' > "$path/config.json"
    (cd "$path" && sha256sum state.json config.json core-id > SHA256SUMS)
    cp -a "$path" "$SFXH_ETC/backups/$(printf 'b%02d' "$i")"
done
sf_activate g20
printf 'g01\n' > "$SFXH_ETC/last-good"
printf '{"old":"g02","new":"g03"}\n' > "$SFXH_ETC/transaction.json"
mkdir -p "$SFXH_VAR/cores/.stage-${ids[0]}-orphan" "$SFXH_VAR/cores/.quarantine/${ids[0]}-old"
mkdir -p "$SFXH_VAR/cores/.stage-${ids[0]}-recent"
touch -d '2000-01-01' "$SFXH_VAR/cores/.stage-${ids[0]}-orphan" "$SFXH_VAR/cores/.quarantine/${ids[0]}-old"
sf_prune_locked
for g in g01 g02 g03 g20; do test -d "$SFXH_ETC/generations/$g"; done
printf 'PASS active, last-good and pending transaction generations protected\n'
test "$(find "$SFXH_ETC/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 5
for i in {5..9}; do test -d "$SFXH_VAR/cores/${ids[i]}"; done
printf 'PASS five backups and five newest verified cores retained\n'
for i in {1..4}; do test -d "$SFXH_VAR/cores/${ids[i]}"; done
printf 'PASS every retained generation or backup protects its core\n'
test ! -e "$SFXH_VAR/cores/${ids[0]}"
test ! -e "$SFXH_VAR/cores/${ids[10]}"
printf 'PASS only old unreferenced cores removed\n'
test ! -e "$SFXH_VAR/cores/.stage-${ids[0]}-orphan"
test ! -e "$SFXH_VAR/cores/.quarantine/${ids[0]}-old"
test -d "$SFXH_VAR/cores/.stage-${ids[0]}-recent"
printf 'PASS abandoned publications expire while recent candidates stay\nTOTAL 5 retention checks\n'
