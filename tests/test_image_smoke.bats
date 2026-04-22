#!/usr/bin/env bats
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    IMAGE_TAG="claude-pal:test-$RANDOM"
}

teardown() {
    [ -n "${IMAGE_TAG:-}" ] && docker rmi -f "$IMAGE_TAG" 2>/dev/null || true
}

@test "image builds from scratch" {
    run "$REPO_ROOT/scripts/build-image.sh" "$IMAGE_TAG"
    assert_success
}

@test "image contains workspace-boot.sh and run-pipeline.sh" {
    run docker run --rm --entrypoint sh "$IMAGE_TAG" -c 'test -x /opt/pal/workspace-boot.sh && test -x /opt/pal/run-pipeline.sh'
    [ "$status" -eq 0 ]
}

@test "image default CMD is workspace-boot.sh" {
    run docker inspect --format '{{json .Config.Cmd}}' "$IMAGE_TAG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"workspace-boot.sh"* ]]
}
