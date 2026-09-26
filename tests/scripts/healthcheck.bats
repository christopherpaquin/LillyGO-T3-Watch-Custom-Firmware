#!/usr/bin/env bats

load test_helper

setup() {
  setup_env
  export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
}

@test "passes when the watch answers and a verified backup exists" {
  make_backup > /dev/null
  run "${REPO_ROOT}/healthcheck.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chip answers, MAC ${MAC}"* ]]
  [[ "$output" == *"verified backup"* ]]
}

@test "fails when there is no backup" {
  run "${REPO_ROOT}/healthcheck.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no verified backup"* ]]
}

@test "fails when the chip doesn't answer" {
  export STUB_FAIL_READMAC=1
  run "${REPO_ROOT}/healthcheck.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chip not answering"* ]]
}

@test "fails when the USB device is absent" {
  export STUB_NO_USB=1
  run "${REPO_ROOT}/healthcheck.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Espressif USB device"* ]]
}
