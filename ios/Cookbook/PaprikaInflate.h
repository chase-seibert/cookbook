#include <stddef.h>
#include <stdint.h>

int cookbook_inflate(const uint8_t *input, size_t input_length,
                     uint8_t *output, size_t output_capacity,
                     size_t *output_length, int window_bits);

int cookbook_gzip(const uint8_t *input, size_t input_length,
                  uint8_t *output, size_t output_capacity,
                  size_t *output_length);
