local function Init()
	if CLIENT then
		hook.Remove("VRMod_Pickup","avr_pose")
	else
		local function GrabAndPose(ent, lefthand, ply)
			if !IsValid(ent) or !ent.ArcticVR then return end

			if hook.Run("VRMod_Pickup", ply, ent) == false then return end

			vrmod.DoPickup(ply,ent,lefthand)
		end

		net.Receivers["avr_pose"] = nil

		net.Receive("avr_magout", function(len, ply)
			local grab = net.ReadBool()
			local pos = net.ReadVector()
			local ang = net.ReadAngle()
			local wpn = ply:GetActiveWeapon()
			local hpos, hang, lefthand

			if grab then
				hpos = net.ReadVector()
				hang = net.ReadAngle()
				lefthand = net.ReadBool()
			end

			if !wpn.ArcticVR then return end

			if !wpn.Magazine then return end

			local loaded = wpn.LoadedRounds or 0

			local mag = ArcticVR.CreateMag(wpn.Magazine, loaded)

			mag:SetAngles(ang)
			mag:SetPos(pos)

			wpn.Magazine = nil
			wpn.LoadedRounds = 0

			if grab then
				GrabAndPose(mag, lefthand, ply)
			end
		end)

		net.Receive("avr_spawnmag", function(len, ply)
			local pos = net.ReadVector()
			local ang = net.ReadAngle()

			local wpn = ply:GetActiveWeapon()

			if !wpn.ArcticVR then return end

			for k, v in pairs(g_VR[ply:SteamID()].heldItems) do
				if v.left then return end
			end

			local magid = wpn.DefaultMagazine

			if wpn:GetAttOverride("MagExtender") then
				if wpn.ExtendedMagazine then
					magid = wpn.ExtendedMagazine
				end
			end

			if wpn:GetAttOverride("MagReducer") then
				if wpn.ReducedMagazine then
					magid = wpn.ReducedMagazine
				end

				if wpn:GetAttOverride("MagExtender") then
					magid = wpn.DefaultMagazine
				end
			end

			local magtbl = ArcticVR.MagazineTable[magid]

			local cap = magtbl.Capacity
			local ammotype = wpn.Primary.Ammo
			local reserve = ply:GetAmmoCount(ammotype)
			local toload = math.Clamp(reserve, 0, cap)

			local mag = ArcticVR.CreateMag(magid, toload)

			if !mag then return end

			ply:SetAmmo(reserve - toload, ammotype)

			mag:SetAngles(ang)
			mag:SetPos(pos)

			GrabAndPose(mag, true, ply)
		end)
	end
end

timer.Simple(0,function()
	if ArcticVR then
		Init()
	end
end)