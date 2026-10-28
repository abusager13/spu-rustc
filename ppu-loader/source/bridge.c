/*
 * Copyright (C) 2026 The spu-rustc contributors
 *
 * This file is part of spu-rustc.
 *
 * spu-rustc is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 */

#include <stdint.h>
#include <sys/spu.h>

enum {
    LOADER_OK = 0,
    LOADER_INITIALIZE_FAILED = 1,
    LOADER_IMAGE_OPEN_FAILED = 2,
    LOADER_GROUP_CREATE_FAILED = 3,
    LOADER_THREAD_CREATE_FAILED = 4,
    LOADER_GROUP_START_FAILED = 5,
    LOADER_GROUP_JOIN_FAILED = 6,
    LOADER_EXIT_STATUS_FAILED = 7,
    LOADER_GROUP_DESTROY_FAILED = 8,
    LOADER_IMAGE_CLOSE_FAILED = 9,
};

int32_t spu_loader_run(const char *path, int32_t *exit_status)
{
    sysSpuImage image;
    sys_spu_group_t group = 0;
    sys_spu_thread_t thread = 0;
    sysSpuThreadGroupAttribute group_attributes;
    sysSpuThreadAttribute thread_attributes;
    sysSpuThreadArgument arguments;
    uint32_t cause = 0;
    uint32_t group_status = 0;
    int32_t thread_status = 0;
    int32_t result = LOADER_OK;
    int image_open = 0;
    int group_created = 0;

    if (sysSpuInitialize(6, 0) != 0) {
        return LOADER_INITIALIZE_FAILED;
    }

    if (sysSpuImageOpen(&image, path) != 0) {
        return LOADER_IMAGE_OPEN_FAILED;
    }
    image_open = 1;

    sysSpuThreadGroupAttributeInitialize(group_attributes);
    sysSpuThreadGroupAttributeName(group_attributes, "rust-spu");
    group_attributes.option.ct = 0;
    if (sysSpuThreadGroupCreate(&group, 1, 100, &group_attributes) != 0) {
        result = LOADER_GROUP_CREATE_FAILED;
        goto cleanup;
    }
    group_created = 1;

    sysSpuThreadAttributeInitialize(thread_attributes);
    sysSpuThreadAttributeName(thread_attributes, "rust-spu-thread");
    sysSpuThreadArgumentInitialize(arguments);
    if (sysSpuThreadInitialize(&thread, group, 0, &image,
                               &thread_attributes, &arguments) != 0) {
        result = LOADER_THREAD_CREATE_FAILED;
        goto cleanup;
    }

    if (sysSpuThreadGroupStart(group) != 0) {
        result = LOADER_GROUP_START_FAILED;
        goto cleanup;
    }

    if (sysSpuThreadGroupJoin(group, &cause, &group_status) != 0) {
        result = LOADER_GROUP_JOIN_FAILED;
        goto cleanup;
    }

    if (sysSpuThreadGetExitStatus(thread, &thread_status) != 0) {
        result = LOADER_EXIT_STATUS_FAILED;
        goto cleanup;
    }

    *exit_status = thread_status;

cleanup:
    if (group_created && sysSpuThreadGroupDestroy(group) != 0 &&
        result == LOADER_OK) {
        result = LOADER_GROUP_DESTROY_FAILED;
    }
    if (image_open && sysSpuImageClose(&image) != 0 && result == LOADER_OK) {
        result = LOADER_IMAGE_CLOSE_FAILED;
    }
    return result;
}
