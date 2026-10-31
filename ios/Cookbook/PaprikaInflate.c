#include "PaprikaInflate.h"
#include <zlib.h>

int cookbook_inflate(const uint8_t *input, size_t input_length,
                     uint8_t *output, size_t output_capacity,
                     size_t *output_length, int window_bits) {
    z_stream stream = {0};
    if (inflateInit2(&stream, window_bits) != Z_OK) return 0;
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = output;
    stream.avail_out = (uInt)output_capacity;
    int result = inflate(&stream, Z_FINISH);
    if (result == Z_STREAM_END) *output_length = (size_t)stream.total_out;
    inflateEnd(&stream);
    return result == Z_STREAM_END;
}

int cookbook_gzip(const uint8_t *input, size_t input_length,
                  uint8_t *output, size_t output_capacity,
                  size_t *output_length) {
    z_stream stream = {0};
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                     15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) return 0;
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_length;
    stream.next_out = output;
    stream.avail_out = (uInt)output_capacity;
    int result = deflate(&stream, Z_FINISH);
    if (result == Z_STREAM_END) *output_length = (size_t)stream.total_out;
    deflateEnd(&stream);
    return result == Z_STREAM_END;
}
