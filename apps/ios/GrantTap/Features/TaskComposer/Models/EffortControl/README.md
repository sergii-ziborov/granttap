# Effort control

Public entry: `ComposerEffortPicker`, used by `ComposerModelPill` in the chat,
Task controls and home/new-Task composers on iPhone, iPad and Mac.

`EffortScale` maps pointer, touch and accessibility positions to the selected
model's supported levels. Unknown inherited effort remains unknown. A reported
chat level or provider default can be displayed without creating an override.
Reset clears the override. Model changes retain the existing confirmation and
remove an effort that the new model cannot accept. Cursor reasoning variants
remain model choices; this control does not invent a standalone Cursor flag.

`EffortSlider` provides native pointer/touch, arrow key and accessibility control.
`EffortAnimatedTrack` owns its animation clock independently of the chat and
renders at most 24 frames per second while visible and active. Every selectable
level moves; Extra High uses blue particles, Maximum a purple pixel pattern,
and Ultra a brighter gradient and glow. Reduce Motion renders a static frame.

Local tests verify native level mapping, persistence, wire overrides and reduced
motion. `AnimatedEffortUITests` verifies dragging, model limits, reset and Done
on both clients. See [Task Composer](../../README.md) and the root engineering
contract.

The native slider opts its containing List out of delayed content touches. A
quick horizontal drag reaches the thumb on touch-down; the List retains normal
vertical scrolling. `AnimatedEffortUITests` exercises the initial drag, level
changes, model restrictions, reset, and reopening the picker.
