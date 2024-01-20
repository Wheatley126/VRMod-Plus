if SERVER then return end

-- TODO: Make new action sets for standing and vehicles
hook.Add("VRMod_EnterVehicle","vrmod_switchactionset",function()
	VRMOD_SetActiveActionSets("/actions/base", "/actions/driving")
end)

hook.Add("VRMod_ExitVehicle","vrmod_switchactionset",function()
	VRMOD_SetActiveActionSets("/actions/base", "/actions/main")
end)


local defaults = {
	boolean_primaryfire = function(pressed)
		if not g_VR.menuFocus then
			LocalPlayer():ConCommand(pressed and "+attack" or "-attack")
		else
			-- UI Input
			if pressed then
				gui.InternalMousePressed(MOUSE_LEFT)
			else
				gui.InternalMouseReleased(MOUSE_LEFT)
			end
		end
	end,

	boolean_secondaryfire = function(pressed)
		if not g_VR.menuFocus then
			LocalPlayer():ConCommand(pressed and "+attack2" or "-attack2")
		else
			-- UI Input
			if pressed then
				gui.InternalMousePressed(MOUSE_RIGHT)
			else
				gui.InternalMouseReleased(MOUSE_RIGHT)
			end
		end
	end,

	boolean_left_pickup = function(pressed)
		if not g_VR.menuFocus then
			vrmod.Pickup(true, not pressed)
		end
	end,

	boolean_right_pickup = function(pressed)
		if not g_VR.menuFocus then
			vrmod.Pickup(false, not pressed)
		end
	end,

	boolean_use = function(pressed)
		if pressed then
			LocalPlayer():ConCommand("+use")

			local wep = LocalPlayer():GetActiveWeapon()
			if IsValid(wep) and wep:GetClass() == "weapon_physgun" then
				hook.Add("CreateMove", "vrutil_hook_cmphysguncontrol", function(cmd)
					if g_VR.input.vector2_walkdirection.y > 0.9 then
						cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD))
					elseif g_VR.input.vector2_walkdirection.y < -0.9 then
						cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_BACK))
					else
						cmd:SetMouseX(g_VR.input.vector2_walkdirection.x*50)
						cmd:SetMouseY(g_VR.input.vector2_walkdirection.y*-50)
					end
				end)
			end
		else
			LocalPlayer():ConCommand("-use")
			hook.Remove("CreateMove", "vrutil_hook_cmphysguncontrol")
		end
	end,

	boolean_changeweapon = function(pressed)
		if pressed then
			VRUtilWeaponMenuOpen()
		else
			VRUtilWeaponMenuClose()
		end
	end,

	boolean_flashlight = function(pressed)
		if pressed then
			LocalPlayer():ConCommand("impulse 100")
		end
	end,

	boolean_reload = function(pressed)
		LocalPlayer():ConCommand(pressed and "+reload" or "-reload")
	end,

	-- This should get renamed when we remake the action set
	boolean_chat = function(pressed)
		if pressed then
			vrmod.TeleportStart()
		else
			vrmod.TeleportEnd()
		end
	end,

	boolean_undo = function(pressed)
		if pressed then
			LocalPlayer():ConCommand("gmod_undo")
		end
	end,

	boolean_spawnmenu = function(pressed)
		if pressed then
			g_VR.MenuOpen()
		else
			g_VR.MenuClose()
		end
	end
}
-- aliases
defaults.boolean_turret = defaults.boolean_primaryfire
defaults.boolean_exit = defaults.boolean_use

local function RunCustomActions(action, pressed)
	for i,info in ipairs(g_VR.CustomActions) do
		if action == info[1] then
			local commands = string.Explode(";",info[pressed and 2 or 3],false)
			for j,txt in ipairs(commands) do
				local args = string.Explode(" ",txt,false)
				RunConsoleCommand(args[1],unpack(args,2))
			end
		end
	end
end

local function SwapInputs(a,b)
	local t = g_VR.input[a]
	g_VR.input[a] = g_VR.input[b]
	g_VR.input[b] = t

	t = g_VR.changedInputs[a]
	g_VR.changedInputs[a] = g_VR.changedInputs[b]
	g_VR.changedInputs[b] = t
end

function g_VR.ProcessInput()
	g_VR.input, g_VR.changedInputs = VRMOD_GetActions()

	-- Rebind some keys (in the future we'll change them in the action manifest)
	SwapInputs("boolean_reload","boolean_secondaryfire")
	SwapInputs("boolean_reload","boolean_chat")
	SwapInputs("boolean_spawnmenu","boolean_reload")

	if vrmod.GetVRWeaponHand() == VR_HAND_LEFT then
		-- Swap certain buttons when in the left hand
		SwapInputs("boolean_primaryfire","boolean_secondaryfire")
		SwapInputs("boolean_reload","boolean_spawnmenu")
	end

	local wep = LocalPlayer():GetActiveWeapon()
	local wepInput = wep:IsValid() && wep.HandleVRInput ~= nil
	for action,pressed in pairs(g_VR.changedInputs) do
		-- Weapons take priority
		if wepInput then
			if wep:HandleVRInput(action,pressed) then continue end
		end

		if hook.Run("VRMod_AllowDefaultAction", action) ~= false then
			if defaults[action] then defaults[action](pressed) end
			RunCustomActions(action,pressed)
		end

		hook.Run("VRMod_Input",action,pressed)
	end
end