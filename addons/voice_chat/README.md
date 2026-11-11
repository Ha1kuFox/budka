# Voice Chat

Small friends-only voice chat layer for the existing Godot `MultiplayerAPI` peer.

- Opus encoding/decoding, RNNoise noise suppression, AGC and jitter buffering
  come from [TwoVoIP](https://github.com/goatchurchprime/two-voip-godot-4), which
  is vendored under `addons/twovoip/`.
- The host relays voice packets. There is no voice server and no server
  authority.
- Microphone is **off by default**. The player enables it from the in-game
  **Voice** panel.
- One global voice volume; per-player volume is intentionally not implemented.

## Install

The addon is already enabled in this project. For another project:

1. Copy `addons/twovoip/` and `addons/voice_chat/`.
2. Install the matching TwoVoIP native library for the target platform.
3. Enable **Voice Chat** in Project Settings → Plugins. This registers the
   `VoiceChat` autoload.
4. Make sure `audio/driver/enable_input` is enabled in Project Settings.
5. Add a `voice_ptt` input action if push-to-talk is wanted. This project uses
   `V`.

Platform note: this repository currently vendors the **Linux x86_64**
debug/release v7.0.0 libraries. Windows needs its own v7.0.0 build before voice
works in a Windows export.

## Use

- Open the pause menu and press **Voice**.
- Turn on **Microphone**.
- Choose **Voice activation** or **Push to talk**.
- Pick an input device if the default is wrong.
- Adjust **Volume** (the `Voice` audio bus).
- RNNoise is enabled by default.

Settings other than the current microphone on/off state are persisted in
`user://voice_chat.cfg`.

## Public API

```gdscript
VoiceChat.set_mic_enabled(true)
VoiceChat.set_mode(VoiceChat.Mode.VOX) # or VoiceChat.Mode.PTT
VoiceChat.set_output_volume(-3.0)
VoiceChat.set_noise_enabled(true)
VoiceChat.toggle_panel()
VoiceChat.is_panel_open()
VoiceChat.is_talking()
VoiceChat.get_debug_info()
```

The network screen (F3+N) has a **Voice** row with mode, mic state, packet
counters and speaker count.

## Network shape

- Client → host: `_receive_control` / `_receive_audio`.
- Host validates and relays with `_relay_control` / `_relay_audio`.
- Control: reliable, RPC channel 2.
- Audio: unreliable ordered, RPC channel 1.
- Snapshot traffic stays on channel 0.
- Client-authoritative session; host relay only. Friends-only scope.

Voice is intentionally not positional, has no teams, recording, echo
cancellation, or per-player mute. Headphones are recommended.
