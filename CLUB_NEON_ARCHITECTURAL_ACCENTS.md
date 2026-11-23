# Club Neon Architectural Accent Lighting

## Dual-system ownership
- Server: `ClubNeonArchitecturalAccentRig` discovers and tags configured existing BaseParts. It does not create, resize, move, or delete map geometry.
- Client: `ArchitecturalAccentFX` animates tagged part colors locally using `ClubAudioSync`.
- The client updates at 12 Hz and uses 16-beat phrase timing. It does not add lights or change light brightness/range.

## Configure existing map parts
In Roblox Studio, select the existing BaseParts that should receive accents and add a string attribute:
- `ClubNeonAccentZone` = `Pillar`, `Balcony`, `Railing`, `DJBooth`, or `Structure`.

Optional attributes:
- `ClubNeonAccentEnabled` (Boolean, default true)
- `ClubNeonAccentBaseColor` (Color3, blends the animation toward a chosen base color)

The server adds the `ClubNeonArchitecturalAccent` CollectionService tag to eligible parts. Unconfigured parts are untouched. No geometry is generated, so existing map architecture and animations are preserved.

## Visual behavior
Zones receive offset palette waves rather than all changing together. DJ booth accents receive a restrained phrase transition; pillars receive a subtle beat lift. No full-white strobe behavior is introduced.

## Validation
Check that the server log reports the expected counts for each zone. If all counts are zero, no map parts have been configured. Test in an unpublished Studio copy before any live deployment.
