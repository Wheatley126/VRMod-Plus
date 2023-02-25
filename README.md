# VR Mod+
This repository is a WIP fork of the [original VRMod by Catse](https://steamcommunity.com/sharedfiles/filedetails/?id=1678408548). It'll be updated later with documentation.  
When this is more finished and polished I'll upload it to the workshop.

Some of the names and functions might change before release so be prepared if you decide to make an addon using it.

### *If you wish to support the VRMod community, I can't take donations, but you should consider donating to [another dev who could use it](https://ko-fi.com/pescorrkastelina).*

---

## Current Changes (Probably forgot some):

* ### Settings
    * Added an option to disable haptic feedback.
    * Added an option and menu to change the floating hands model.
    * Changing playermodels will automatically recalculate bone info (no more spaghetti people).
    * Floating Hands, Use Worldmodels, and Laser Pointer can be toggled without needing to restart VR.

* ### Pickups
    * Objects can be picked up from a distance.
    * Picking up objects too quickly no longer causes them to be desynced on the client (this should also help after lag spikes).
    * Held objects should no longer go invisible if you outrun their physics object.
    * Held objects' shadows now follow the object's rendered position much better.

* ### UI
    * Panels now render once per frame rather than 0.1 seconds after clicking them.
    * Menus are drawn using the same material, rather than a separate one for each.
    * Fixed clipping and translucency issues when rendering panels.

* ### Mod Support
    * Weapons can specify a "Draw Mode" that functions regardless of the "Use Worldmodels" setting. Options are Viewmodel, Worldmodel, and Custom.
    * The model (+skin and bodygroups) for the floating hands can be chosen with the hook "VRMod_GetHandsModel".
    * Models can be added to the hands menu with vrmod.AddHandsOption().
    * Menus can specify a custom render function that gets called in place of the default.
    * Entities can be picked up and dropped manually with vrmod.DoPickup() and vrmod.DoDrop().

* ### QoL
    * Removed the voice permissions prompt upon starting VR. You will still be prompted when activating voice from the chat menu.


## To Do:

* ### Pickups
    * Fix Halos.
    * Add indicator that objects can be picked up.
    * Add hold finger poses.
    * Move UpdateShadowControl to a hook and remove the pickup controller.
    * Use serverside copy of hand pose to reduce networking.
    * Drop object if it's been too far from the hand for too long.

* ### UI
    * Add skins and bodygroups to the hands menu.

* ### Mod Support
    * Properly implement the ENTITY.VRInfo table.
    * Overhaul input hook.
    * Add more PrePickup and PostPickup hooks (and possibly PostDrop).
    * Replace various instances of hook.Call with hook.Run.

* ### Other
    * Make hand-agnostic control scheme.
    * Recompile hand models with same bone structure.
    * Update hands model after respawn.
    * Improve vehicle support.
