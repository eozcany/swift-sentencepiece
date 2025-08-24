#pragma once

// Expose the C API (Swift cannot import C++ headers directly).
// sentencepiece_c.h ships with the SentencePiece sources (src/sentencepiece_c.h).

#ifdef __cplusplus
extern "C" {
#endif

#include "sentencepiece_c.h"

#ifdef __cplusplus
}
#endif