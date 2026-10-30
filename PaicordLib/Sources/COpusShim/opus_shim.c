#include "opus_shim.h"

int paicord_opus_set_bitrate(OpusEncoder *enc, opus_int32 bitrate) {
  return opus_encoder_ctl(enc, OPUS_SET_BITRATE(bitrate));
}

int paicord_opus_set_inband_fec(OpusEncoder *enc, int enabled) {
  return opus_encoder_ctl(enc, OPUS_SET_INBAND_FEC(enabled));
}

int paicord_opus_set_packet_loss_perc(OpusEncoder *enc, int percent) {
  return opus_encoder_ctl(enc, OPUS_SET_PACKET_LOSS_PERC(percent));
}

int paicord_opus_set_signal_voice(OpusEncoder *enc) {
  return opus_encoder_ctl(enc, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
}

int paicord_opus_encoder_reset(OpusEncoder *enc) {
  return opus_encoder_ctl(enc, OPUS_RESET_STATE);
}

int paicord_opus_decoder_reset(OpusDecoder *dec) {
  return opus_decoder_ctl(dec, OPUS_RESET_STATE);
}
