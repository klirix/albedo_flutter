#ifndef ALBEDO_H
#define ALBEDO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint8_t AlbedoResult;

// Opaque pointer types as void pointers
typedef void* AlbedoBucket;
typedef void* AlbedoListHandle;

// Open a database
AlbedoResult albedo_open(const char *path, AlbedoBucket *out);

// Close a database
AlbedoResult albedo_close(AlbedoBucket bucket);

// Insert a document
AlbedoResult albedo_insert(AlbedoBucket bucket, uint8_t *docBuffer);

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

// Get the library version
__attribute__((visibility("default"))) __attribute__((used)) uint32_t albedo_version(void);

#ifdef __cplusplus
}
#endif

#endif // ALBEDO_H