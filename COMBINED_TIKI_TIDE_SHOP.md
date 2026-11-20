# Combined Tiki Tide Shop UI

## Change
The three top-level tabs **XP & Boosts**, **Tip Jar**, and **Item Shop** are consolidated into one top-level **Shop** tab. Inside Shop, a compact three-way selector switches between **Items**, **XP & Boosts**, and **Tip Jar**. The selected section is retained while switching sections and the existing section renderers are reused.

## Preserved
- Existing item shop card rendering and purchase prompts.
- Existing XP progress, boost state, and 2x/4x Developer Product prompts.
- Existing donation products, perks, and Developer Product prompts.
- Purchase IDs, server receipt handling, and other backend behavior are untouched.

## File
`UI_Renderer (2).lua` in `ReplicatedStorage/UI_Renderer`.

## Testing
This is a source change only. It has not been tested in Roblox Studio or published. Test each Shop section on desktop and mobile, including purchase prompt flows and scroll behavior.
