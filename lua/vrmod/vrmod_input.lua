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
		end
	end,

	boolean_secondaryfire = function(pressed)
		if not g_VR.menuFocus then
			LocalPlayer():ConCommand(pressed and "+attack2" or "-attack2")
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
end)

function g_VR.ProcessInput()
	g_VR.input, g_VR.changedInputs = VRMOD_GetActions()

	for action,pressed in pairs(g_VR.changedInputs) do
		if hook.Run("VRMod_AllowDefaultAction", action) ~= false then
			if defaults[action] then defaults[action](pressed) end
			RunCustomActions(action,pressed)
		end

		hook.Run("VRMod_Input",k,v)
	end
end