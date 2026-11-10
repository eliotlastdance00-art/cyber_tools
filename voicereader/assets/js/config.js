// VoiceReader — configuration.
// After creating your Gumroad product, put its permalink and buy URL here.
// FREE_CHAR_LIMIT: characters a Free user may read per document.
// OFFLINE_SECRET: used by the offline license-key fallback (tools/make_license.py).
//   Change it to your own random string and regenerate keys with the tool.
window.VR_CONFIG = {
  GUMROAD_PERMALINK: 'voicereader-pro',
  GUMROAD_BUY_URL: 'https://voicereader.gumroad.com/l/voicereader-pro',
  OFFLINE_SECRET: 'change-me-voicereader-secret',
  FREE_CHAR_LIMIT: 1500,
  PRICE_DISPLAY: '$19',
  STRIKE_PRICE: '$39'
};
