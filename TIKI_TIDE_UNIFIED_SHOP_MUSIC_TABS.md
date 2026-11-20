# Tiki Tide Unified Shop and Music Navigation

## Changes
- Replaced the three top-level **XP & Boosts**, **Tip Jar**, and **Item Shop** tabs with one **Shop** tab.
- Shop has three internal sections: **Items**, **XP & Boosts**, and **Tip Jar**. The original renderers, purchase prompt calls, product IDs, ownership checks, and reward state are reused without changing purchase logic.
- Merged **Music** and **All Tracks** navigation. Music now has internal **Listen** and **Catalog • All Tracks** views.
- The Catalog view reuses the existing catalog renderer, search/filter/pagination and staff playlist/catalog operations.
- Home genre/All Tracks shortcuts, queue Browse, and playlist Add Tracks now open Music > Catalog. The favorites Library shortcut opens Music > Listen.
- The separate **Playlists** staff tab remains, as does **Audio ID**.

## Deployment
Replace the existing UI Renderer source with the updated `UI_Renderer (2).lua` in the appropriate client location. No server-side purchase or audio logic changes are required for these navigation/UI merges.

## Verification status
Static source review only. Not tested in Roblox Studio, with live client interactions, mobile layouts, or Marketplace prompts. Test each Shop section, the music Listen/Catalog switch, catalog search/genre/pagination, favorite and request actions, staff playlist access, and purchase prompts before merging/publishing.
