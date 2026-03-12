// Relative import to be able to reuse the C sources.
// See the comment in ../albedo_dart.podspec for more information.
#include "../../src/albedo_dart.h"

static uint8_t dummy_callback(void *context, const uint8_t *data, uint32_t data_size, uint32_t page_count) {
    (void)context;
    (void)data;
    (void)data_size;
    (void)page_count;
    return 0;
}

void dummy_function(void) {
    // This function is intentionally left empty.
    // It serves as a placeholder to ensure that the C file is not empty.
    char path[] = "";
    albedo_bucket *bucket = 0;
    albedo_list_handle *list_handle = 0;
    albedo_transform_iterator *transform_iterator = 0;
    uint8_t *doc = 0;
    uint8_t *cursor = 0;

    albedo_version();
    albedo_close(bucket);
    albedo_insert(bucket, (uint8_t *)0);
    albedo_delete(bucket, (uint8_t *)0, 0);
    albedo_list(bucket, (uint8_t *)0, &list_handle);
    albedo_list_indexes(bucket, &doc);
    albedo_list_cursor_export(list_handle, &cursor);
    albedo_data(list_handle, &doc);
    albedo_next(list_handle);
    albedo_close_iterator(list_handle);

    albedo_ensure_index(bucket, "", 0);
    albedo_drop_index(bucket, "");
    albedo_flush(bucket);

    albedo_transform(bucket, (uint8_t *)0, &transform_iterator);
    albedo_transform_data(transform_iterator, &doc);
    albedo_transform_apply(transform_iterator, (uint8_t *)0);
    albedo_transform_close(transform_iterator);

    albedo_set_replication_callback(bucket, dummy_callback, bucket);
    albedo_apply_batch(bucket, (const uint8_t *)0, 0, 0);

    albedo_vacuum(bucket);
    albedo_bitsize();
    albedo_version();
    albedo_open(path, &bucket);

    uint8_t *ptr = albedo_malloc(1);
    albedo_free(ptr, 1);
}
