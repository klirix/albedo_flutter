#ifndef ALBEDO_H
#define ALBEDO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t AlbedoResult;

enum {
    ALBEDO_OK = 0,
    ALBEDO_ERROR = 1,
    ALBEDO_HAS_DATA = 2,
    ALBEDO_EOS = 3,
    ALBEDO_OUT_OF_MEMORY = 4,
    ALBEDO_FILE_NOT_FOUND = 5,
    ALBEDO_NOT_FOUND = 6,
    ALBEDO_INVALID_FORMAT = 7
};

// Opaque pointer types as void pointers
typedef void* AlbedoBucket;
typedef void* AlbedoListHandle;
typedef void* AlbedoTransformIterator;

typedef uint8_t (*AlbedoPageChangeCallback)(
    void* context,
    const uint8_t* data,
    uint32_t data_size,
    uint32_t page_count
);

// Open a database
AlbedoResult albedo_open(const char *path, AlbedoBucket *out);

// Close a database
AlbedoResult albedo_close(AlbedoBucket bucket);

// Insert a document
AlbedoResult albedo_insert(AlbedoBucket bucket, uint8_t *docBuffer);

// Ensure index exists
AlbedoResult albedo_ensure_index(AlbedoBucket bucket, const char *path, uint8_t options_byte);

// Drop an index
AlbedoResult albedo_drop_index(AlbedoBucket bucket, const char *path);

// Delete documents matching a query
AlbedoResult albedo_delete(AlbedoBucket bucket, uint8_t *queryBuffer, uint16_t queryLen);

// List documents matching a query
AlbedoResult albedo_list(AlbedoBucket bucket, uint8_t *queryBuffer, AlbedoListHandle *outIterator);

// Get the current document from the iterator
AlbedoResult albedo_data(AlbedoListHandle handle, uint8_t **outDoc);

// Advance the iterator
AlbedoResult albedo_next(AlbedoListHandle handle);

// Close the iterator and free resources
AlbedoResult albedo_close_iterator(AlbedoListHandle iterator);

// Vacuum the database
AlbedoResult albedo_vacuum(AlbedoBucket bucket);

// Flush pending writes to disk
AlbedoResult albedo_flush(AlbedoBucket bucket);

// Create a transform iterator
AlbedoResult albedo_transform(AlbedoBucket bucket, uint8_t *queryBuffer, AlbedoTransformIterator *iteratorOut);

// Get the current document from the transform iterator
AlbedoResult albedo_transform_data(AlbedoTransformIterator iterator, uint8_t **outDoc);

// Apply a transformation to the current document (nullable buffer to delete)
AlbedoResult albedo_transform_apply(AlbedoTransformIterator iterator, uint8_t *transformBuffer);

// Close the transform iterator
AlbedoResult albedo_transform_close(AlbedoTransformIterator iterator);

// Set a callback for page replication
AlbedoResult albedo_set_replication_callback(
    AlbedoBucket bucket,
    AlbedoPageChangeCallback callback,
    void* context
);

// Apply a replicated page batch
AlbedoResult albedo_apply_batch(
    AlbedoBucket bucket,
    const uint8_t* data,
    uint32_t data_size,
    uint32_t page_count
);

// Get the platform bit size
uint32_t albedo_bitsize(void);

// Get the library version
__attribute__((visibility("default"))) __attribute__((used)) uint32_t albedo_version(void);

// Allocate and free memory using the library allocator
uint8_t* albedo_malloc(size_t size);
void albedo_free(uint8_t* ptr, size_t size);

#ifdef __cplusplus
}
#endif

#endif // ALBEDO_H
