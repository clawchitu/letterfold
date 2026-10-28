# Audio sources

Letterfold ships **no recorded audio**. Every sound is synthesised at run time:

| sound | where | how |
|---|---|---|
| effects (slap, seal, rub, gate, …) and sound mode | `App/Sources/Sound.swift` | synthesised buffers |
| background music (all chapters) | `Packages/FoldCore/Sources/FoldCore/Music/` | real-time synthesis on `AVAudioSourceNode`s: modal 古琴 / 箫 / wood plucks, drone, water / air bed, `AVAudioUnitReverb` |
| fold swish (the music's accent on a close) | `MusicDSP.swift` `renderSwish` | synthesised band-limited noise (port of `paper_swish_synth` in the approved sample's `gen.py`) |

## The CC0 paper recording that was considered (not used)

The ch1 sample's variant b used a slice of Freesound #398896 "Paper - folding 01.wav" by Anthousai
(https://freesound.org/people/Anthousai/sounds/398896/). Its page was checked on 2026-10-27 and states
**CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/). However the original WAV can only be downloaded
with a Freesound login (the download URL redirects to `/home/login/`); only the lossy HQ MP3 preview is public.
Per the rule for build 24 ("use the recording only if the original WAV can be obtained and CC0 confirmed"), the
swish is **synthesised** instead and no Freesound audio is in the app. If the original is fetched later, record
the file name, SHA-256, download date and the licence as shown on the page here before adding it.
