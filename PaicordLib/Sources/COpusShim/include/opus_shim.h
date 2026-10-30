// Non-variadic wrappers around opus_encoder_ctl/opus_decoder_ctl, which Swift
// cannot call directly.
#pragma once
#include <opus.h>

#ifdef __cplusplus
extern "C" {
#endif

int paicord_opus_set_bitrate(OpusEncoder *enc, opus_int32 bitrate);
int paicord_opus_set_inband_fec(OpusEncoder *enc, int enabled);
int paicord_opus_set_packet_loss_perc(OpusEncoder *enc, int percent);
int paicord_opus_set_signal_voice(OpusEncoder *enc);
int paicord_opus_encoder_reset(OpusEncoder *enc);
int paicord_opus_decoder_reset(OpusDecoder *dec);

#ifdef __cplusplus
}
#endif
