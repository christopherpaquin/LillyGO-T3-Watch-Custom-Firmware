#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  # shellcheck source=scripts/lib/verify-backup.sh
  source "${SCRIPTS}/lib/verify-backup.sh"
}

@test "passes for an untouched backup" {
  image="$(make_backup)"
  run verify_backup_image "${image}" "${MAC}"
  [ "$status" -eq 0 ]
  run require_verified_backup "${MAC}"
  [ "$status" -eq 0 ]
  [ "$output" = "${image}" ]
}

@test "fails when there is no backup for this watch" {
  run require_verified_backup "${MAC}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no backup for watch"* ]]
}

@test "fails when the backup belongs to another watch" {
  image="$(make_backup)"
  run verify_backup_image "${image}" "aabbccddeeff"
  [ "$status" -eq 1 ]
  [[ "$output" == *"belongs to ${MAC}"* ]]
}

@test "fails for a truncated image" {
  image="$(make_backup)"
  chmod 600 "${image}"
  truncate -s 100 "${image}"
  run verify_backup_image "${image}" "${MAC}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected 4096"* ]]
}

@test "fails for an edited image" {
  image="$(make_backup)"
  printf 'X' | dd of="${image}" bs=1 seek=10 conv=notrunc status=none
  run verify_backup_image "${image}" "${MAC}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hash mismatch"* ]]
}

@test "fails for an edited hash file" {
  image="$(make_backup)"
  echo "0000  x.bin" > "${image%.bin}.sha256"
  run verify_backup_image "${image}" "${MAC}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"hash mismatch"* ]]
}

@test "fails when metadata is missing" {
  image="$(make_backup)"
  rm "${image%.bin}.meta"
  run verify_backup_image "${image}" "${MAC}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing metadata"* ]]
}

@test "require_verified_backup ignores a tampered newer backup" {
  good="$(make_backup)"
  sleep 1
  bad="$(make_backup)"
  printf 'X' | dd of="${bad}" bs=1 seek=10 conv=notrunc status=none
  run require_verified_backup "${MAC}"
  [ "$status" -eq 0 ]
  [ "$output" = "${good}" ]
}
