#!/usr/bin/env bash
set -uo pipefail

action="${1:-}"
base='http://192.168.178.4:8111/api/v3'
ids_file='ids.txt'
checkpoint_file='.shoko_resume'

if [[ "${2:-}" == '--fresh' ]]; then
    rm -f -- "$checkpoint_file"
fi

if [[ ! "$action" =~ ^(Preview|Relocate)$ ]]; then
    echo 'Aufruf: shoko_relocate.sh Preview|Relocate [--fresh]'
    exit 2
fi

for required_command in curl jq; do
    if ! command -v "$required_command" >/dev/null; then
        echo "Fehlendes Programm: $required_command"
        exit 1
    fi
done

if [[ ! -s "$ids_file" ]]; then
    echo "$ids_file fehlt oder ist leer."
    exit 1
fi

if [[ -z "${SHOKO_APIKEY+x}" || -z "$SHOKO_APIKEY" ]]; then
    read -rsp 'Shoko Admin-API-Key: ' SHOKO_APIKEY
    echo
    export SHOKO_APIKEY
fi

preset_response="$(mktemp)"

if ! curl \
        --fail-with-body \
        --silent \
        --show-error \
        --header "apikey: $SHOKO_APIKEY" \
        --output "$preset_response" \
        "$base/Relocation/Preset"; then
    echo 'Relocation-Presets konnten nicht geladen werden:'
    cat "$preset_response"
    rm -f -- "$preset_response"
    exit 1
fi

preset_id="$(
    jq --raw-output '
        .[]
        | select(
            .Name == "Baines-LUARenamer"
            and .IsUsable == true
        )
        | .ID
    ' "$preset_response" |
        head -n 1
)"

rm -f -- "$preset_response"

if [[ -z "$preset_id" ]]; then
    echo 'Baines-LUARenamer wurde nicht gefunden oder ist nicht verwendbar.'
    exit 1
fi

echo 'Preset: Baines-LUARenamer'
echo "Preset-ID: $preset_id"

preview_query='move=true&rename=true&allowRelocationInsideDestination=true'

__shoko_post() {
    local url="$1"
    local out="$2"
    local body="$3"
    local code=''
    local attempt
    for attempt in 1 2 3; do
        code="$(
            curl --silent --show-error \
                --request POST \
                --header "apikey: $SHOKO_APIKEY" \
                --header 'accept: text/plain' \
                --header 'Content-Type: application/json-patch+json' \
                --data-binary "$body" \
                --output "$out" \
                --write-out '%{http_code}' \
                "$url"
        )"
        if [[ -n "$code" && ! "$code" =~ ^(415|429|500|503)$ ]]; then
            echo "$code"
            return 0
        fi
        sleep 2
    done
    echo "$code"
}

probe_body="$(
    head -n 1 "$ids_file" |
        jq --raw-input --slurp --compact-output '
            split("\n")
            | map(
                gsub("\r"; "")
                | select(length > 0)
                | tonumber
            )
        '
)"

probe_response="$(mktemp)"
probe_code="$(__shoko_post \
    "$base/Relocation/Preset/$preset_id/Preview?$preview_query" \
    "$probe_response" "$probe_body")"
rm -f -- "$probe_response"

if [[ "$probe_code" != 200 ]]; then
    echo "Preview-Probe fehlgeschlagen (HTTP $probe_code)."
    exit 1
fi

query="$preview_query"

if [[ "$action" == Relocate ]]; then
    query="$query&deleteEmptyDirectories=true"

    read -r -p 'Echten globalen Lauf starten? Tippe JA: ' confirmation
    if [[ "$confirmation" != JA ]]; then
        echo 'Abgebrochen.'
        exit 1
    fi
fi

resume_from="$(
    [[ -s "$checkpoint_file" ]] && cat "$checkpoint_file" || true
)"
if [[ -n "$resume_from" ]]; then
    echo "Resume ab ID $resume_from (überspringe bereit verarbeitete IDs)"
fi

bodies="$(
    jq --raw-input \
        --slurp \
        --compact-output \
        --argjson batch_size 500 \
        --arg resume_from "$resume_from" '
        split("\n")
        | map(
            gsub("\r"; "")
            | select(length > 0)
            | tonumber
        )
        | map(select(. > ($resume_from | tonumber? // 0)))
        | . as $ids
        | range(0; length; $batch_size) as $start
        | $ids[$start:$start + $batch_size]
    ' "$ids_file"
)"

if [[ -z "$bodies" ]]; then
    echo "Alle IDs bereits verarbeitet oder $ids_file konnte nicht verarbeitet werden."
    exit 1
fi

batch_number=0
total_batches="$(grep -c . <<< "$bodies")"
total_succeeded=0
total_failed=0

while IFS= read -r body; do
    [[ -n "$body" ]] || continue
    batch_number=$((batch_number + 1))
    response_file="$(mktemp)"

    echo "Batch $batch_number/$total_batches: $action"

    code="$(__shoko_post \
        "$base/Relocation/Preset/$preset_id/$action?$query" \
        "$response_file" "$body")"

    if [[ "$code" != 200 ]]; then
        echo "HTTP-Fehler ($code) in Batch $batch_number:"
        cat "$response_file"
        rm -f -- "$response_file"
        exit 1
    fi

    if ! jq --exit-status 'type == "array"' \
                        "$response_file" >/dev/null; then
        echo "Unerwartete Antwort in Batch $batch_number:"
        cat "$response_file"
        rm -f -- "$response_file"
        exit 1
    fi

    jq --raw-output 'last' <<< "$body" > "$checkpoint_file"

    succeeded="$(
        jq '
            [
                .[]
                | select(
                    (.IsSuccess // .isSuccess // false) == true
                )
            ]
            | length
        ' "$response_file"
    )"

    failed="$(
        jq '
            [
                .[]
                | select(
                    (.IsSuccess // .isSuccess // false) != true
                )
            ]
            | length
        ' "$response_file"
    )"

    total_succeeded=$((total_succeeded + succeeded))
    total_failed=$((total_failed + failed))

    echo "Batch $batch_number/$total_batches: $succeeded erfolgreich, $failed fehlgeschlagen"

    if [[ "$failed" -gt 0 ]]; then
        jq --raw-output '
            .[]
            | select(
                (.IsSuccess // .isSuccess // false) != true
            )
            | "ID \(.FileID // .fileID): \(
                .ErrorMessage
                // .errorMessage
                // "unbekannter Fehler"
            )"
        ' "$response_file"
    fi

    rm -f -- "$response_file"
done <<< "$bodies"

echo
echo 'Lauf abgeschlossen:'
echo "Erfolgreich: $total_succeeded"
echo "Fehlgeschlagen: $total_failed"
