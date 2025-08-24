#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* spm_processor_t;

spm_processor_t spm_processor_new(void);
void spm_processor_free(spm_processor_t p);

int spm_processor_load(spm_processor_t p, const char* model_path);

/* Encode UTF-8 text -> ids. Allocates ids; caller frees with spm_ids_free. */
int spm_encode(spm_processor_t p, const char* text, int32_t** ids, size_t* size);
void spm_ids_free(int32_t* ids);

/* Decode ids -> UTF-8 string. Allocates string; caller frees with spm_string_free. */
int spm_decode(spm_processor_t p, const int32_t* ids, size_t size, char** out);
void spm_string_free(char* s);

/* Metadata */
int spm_eos_id(spm_processor_t p);
int spm_bos_id(spm_processor_t p);
int spm_vocab_size(spm_processor_t p);

#ifdef __cplusplus
}
#endif