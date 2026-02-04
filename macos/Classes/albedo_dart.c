// Relative import to be able to reuse the C sources.
// See the comment in ../albedo_dart.podspec for more information.
#include "albedo_dart.h"

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
    albedo_version();
    void *dummy = 0;
    albedo_close(dummy);
    albedo_insert(dummy, ((uint8_t *)0));
    albedo_delete(dummy, ((uint8_t *)0), 0);
    albedo_list(dummy, ((uint8_t *)0), (AlbedoListHandle *)0);
    albedo_data((AlbedoListHandle)0, (uint8_t **)0);
    albedo_next((AlbedoListHandle)0);
    albedo_close_iterator((AlbedoListHandle)0);

    albedo_ensure_index(dummy, "", 0);
    albedo_drop_index(dummy, "");
    albedo_flush(dummy);

    albedo_transform(dummy, ((uint8_t *)0), (AlbedoTransformIterator *)0);
    albedo_transform_data((AlbedoTransformIterator)0, (uint8_t **)0);
    albedo_transform_apply((AlbedoTransformIterator)0, ((uint8_t *)0));
    albedo_transform_close((AlbedoTransformIterator)0);

    albedo_set_replication_callback(dummy, dummy_callback, dummy);
    albedo_apply_batch(dummy, ((const uint8_t *)0), 0, 0);

    albedo_vacuum(dummy);
    albedo_bitsize();
    albedo_version();
    albedo_open("", (AlbedoBucket *)0);

    uint8_t *ptr = albedo_malloc(1);
    albedo_free(ptr, 1);
}
