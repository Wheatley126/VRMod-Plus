local cvar_mass = CreateConVar("vrmod_pickup_maxmass","35",bit.bor(FCVAR_REPLICATED,FCVAR_CHEAT),"Highest mass that can be picked up, in kilograms",0)
local cvar_range = CreateConVar("vrmod_pickup_range","72",bit.bor(FCVAR_REPLICATED,FCVAR_CHEAT),"How far you can reach",0)

local function ClosestPointInOBB(ent,pos)
	local mins,maxs = ent:OBBMins(),ent:OBBMaxs()
	local lpos = ent:WorldToLocal(pos)
	lpos:SetUnpacked(math.Clamp(lpos[1],mins[1],maxs[1]), math.Clamp(lpos[2],mins[2],maxs[2]), math.Clamp(lpos[3],mins[3],maxs[3]))

	return ent:LocalToWorld(lpos)
end

local function CanGrab(e,phys,pl)
	if CLIENT && not phys:IsValid() then
		-- Most entities won't have a PhysObj on the client	
		if e:GetMoveType() ~= MOVETYPE_VPHYSICS then return false end

		local mass

		local info = util.GetModelInfo(e:GetModel())
		if info && info.KeyValues then
			info = util.KeyValuesToTable(info.KeyValues)
			if info.solid && info.solid.mass then
				mass = info.solid.mass
			end
		end

		return not mass or mass <= cvar_mass:GetFloat()
	end

	return phys:IsValid() && phys:IsMoveable() && not phys:HasGameFlag(FVPHYSICS_NO_PLAYER_PICKUP) && not phys:HasGameFlag(FVPHYSICS_MULTIOBJECT_ENTITY) && phys:GetMass() <= cvar_mass:GetFloat() && (e.CPPICanPickup == nil or e:CPPICanPickup(pl))
end

local cylRadius = 16
local function GetGrabbableObjects(pl,pos,ang)
	local range = cvar_range:GetFloat()
	local size = Vector(range,range,range)

	local tbl = {}
	for i,e in ipairs(ents.FindInBox(pos-size,pos+size)) do
		if !e:IsValid() or !CanGrab(e,e:GetPhysicsObject(),pl) then continue end

		local testpos = WorldToLocal(e:LocalToWorld(e:OBBCenter()),angle_zero,pos,ang)
		testpos = LocalToWorld(Vector(testpos[1]-e:BoundingRadius()),angle_zero,pos,ang)

		local point = ClosestPointInOBB(e,testpos)
		if pos:DistToSqr(point) > range*range then continue end

		local lpos = WorldToLocal(point,angle_zero,pos,ang)
		local deviate = Vector(lpos[2],lpos[3]):Length2DSqr()
		if lpos[1] < -0.01 or deviate > cylRadius*cylRadius then continue end

		local priority = lpos[1]/2
		priority = priority*priority+deviate
		table.insert(tbl,{ent = e, point = point, priority = priority})
	end

	if not table.IsEmpty(tbl) then
		table.sort(tbl,function(a,b)
			return a.priority < b.priority
		end)
	end

	return tbl
end

vrmod.pickupList = vrmod.pickupList or {}

local function NetWritePlayer(pl)
	local id = pl:IsPlayer() && pl:EntIndex() or 0
	net.WriteUInt(id-1,7)
end

local function NetReadPlayer()
	local id = net.ReadUInt(7)
	if !id then return end

	return Entity(id+1)
end

if CLIENT then
	-- TODO: Determine the velocity serverside
	-- Edit: This mostly just gets used for dropping items so might not be necessary
	function vrmod.Pickup( bLeftHand, bDrop )
		net.Start("vrmod_pickup")
			net.WriteBool(bLeftHand)
			net.WriteBool(bDrop or false)

			local pose = bLeftHand and g_VR.tracking.pose_lefthand or g_VR.tracking.pose_righthand

			if bDrop then
				net.WriteVector(pose.vel)
				net.WriteVector(pose.angvel)
				g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = nil
			end
		net.SendToServer()
	end

	local function GetHeldPos(self)
		local info = self.VRPickup
		if not info then return end
		local netinfo = g_VR.net[info.steamid]
		if not netinfo then return end

		local wpos, wang
		if info.left then
			wpos, wang = LocalToWorld(info.localPos, info.localAng, netinfo.lerpedFrame.lefthandPos, netinfo.lerpedFrame.lefthandAng)
		else
			wpos, wang = LocalToWorld(info.localPos, info.localAng, netinfo.lerpedFrame.righthandPos, netinfo.lerpedFrame.righthandAng)
		end

		return wpos,wang
	end

	local function HeldRender(self,flags)
		if self.VRDrawingOld then
			self:DrawModel(flags)
			return
		end
		local oldpos,oldang = self:GetRenderOrigin(),self:GetRenderAngles()

		local wpos,wang = GetHeldPos(self)
		if wpos then
			self:SetRenderOrigin(wpos)
			self:SetRenderAngles(wang)
			self:SetupBones()
		end

		if self.VRPickup && self.VRPickup.oldRender then
			self.VRDrawingOld = true
			self.VRPickup.oldRender(self,flags)
			self.VRDrawingOld = nil
		else
			self:DrawModel(flags)
		end

		if wpos then
			self:SetRenderOrigin(oldpos)
			self:SetRenderAngles(oldang)
			self:InvalidateBoneCache()
		end
	end

	local function HeldCalcPos(self,pos,ang)
		local wpos,wang = GetHeldPos(self)
		if wpos then
			return wpos,wang
		end
	end

	local function AddCreationCheck()
		hook.Add("NotifyShouldTransmit","VRMod_RecreatePickup",function(ent,transmit)
			if not transmit then return end

			local id = ent:EntIndex()
			if vrmod.pickupList[id] && ent:GetCreationTime() == vrmod.pickupList[ent:EntIndex()].createtime then
				local info = vrmod.pickupList[id]
				-- Remove from list in-case it's invalid now
				vrmod.pickupList[id] = nil

				vrmod.OnPickup(id,info.ply,info.left,info.localPos,info.localAng,ent:GetCreationTime())
			end
		end)
	end

	local function RemoveCreationCheck()
		hook.Remove("NotifyShouldTransmit","VRMod_RecreatePickup")
	end

	function vrmod.OnPickup(entid,pl,bLeft,localPos,localAng,createtime)
		local steamid = IsValid(pl) && pl:SteamID()
		if g_VR.net[steamid] == nil then return end

		local ent = Entity(entid)

		local oldRender = ent.VRPickup && ent.VRPickup.oldRender or ent.RenderOverride
		local oldCalcPos = ent.VRPickup && ent.VRPickup.oldCalcPos or ent.CalcAbsolutePosition

		local info = {
			left = bLeft,
			localPos = localPos,
			localAng = localAng,
			steamid = steamid,
			ply = pl,
			oldRender = oldRender,
			oldCalcPos = oldCalcPos,
			createtime = createtime
		}

		if table.IsEmpty(vrmod.pickupList) then
			AddCreationCheck()
		end

		vrmod.pickupList[entid] = info

		if ent:IsValid() && ent:GetCreationTime() == createtime then
			ent.VRPickup = info
			ent.RenderOverride = HeldRender
			ent.CalcAbsolutePosition = HeldCalcPos

			info.ent = ent

			if pl == LocalPlayer() then
				g_VR[info.left && "heldEntityLeft" or "heldEntityRight"] = ent
			end

			hook.Run("VRMod_Pickup", pl, ent)
		end
	end

	function vrmod.OnDrop(entid,ply)
		vrmod.pickupList[entid] = nil

		local ent = Entity(entid)
		if ent:IsValid() then
			local t = ent.VRPickup

			if t then
				if ent.RenderOverride == HeldRender then
					ent.RenderOverride = t.oldRender
				end
				if ent.CalcAbsolutePosition == HeldCalcPos then
					ent.CalcAbsolutePosition = t.oldCalcPos
				end

				ent.VRPickup = nil
			end

			if table.IsEmpty(vrmod.pickupList) then
				RemoveCreationCheck()
			end
		end

		hook.Run("VRMod_Drop", ply, ent)
	end
	
	net.Receive("vrmod_pickup",function(len)
		local ply = NetReadPlayer()
		local entid = net.ReadUInt(13)+1
		local bDrop = net.ReadBool()

		if !bDrop then
			local left = net.ReadBool()
			local localPos = net.ReadVector()
			local localAng = net.ReadAngle()
			local createtime = net.ReadFloat()

			vrmod.OnPickup(entid,ply,left,localPos,localAng,createtime)
		else
			vrmod.OnDrop(entid,ply)
		end
	end)

	local hovered = {}
	function g_VR.DrawPickupHalos()
		local pl = LocalPlayer()

		-- Update hovered props once per frame
		if vrmod.InEye(true) then
			for i = 1,2 do
				if not vrmod.IsHandEmpty(pl,i == 1) then
					if hovered[i] then hovered[i] = nil end
					continue
				end

				local pos,ang
				if i == 1 then
					pos,ang = vrmod.GetLeftHandPose()
				else
					pos,ang = vrmod.GetRightHandPose()
				end

				local pickupPoint = LocalToWorld(Vector(3, i == 1 && -1.5 or 1.5),angle_zero,pos,ang)

				local found = false
				for _,t in ipairs(GetGrabbableObjects(pl,pickupPoint,ang)) do
					if hook.Run("VRMod_Pickup", pl, t.ent) == false then continue end

					local tr = util.TraceLine({
						start = pickupPoint,
						endpos = t.point,
						filter = {pl,t.ent}
					})
					if tr.Hit then continue end

					if i == 1 or hovered[1] ~= t.ent && not t.ent.VRPickupRenderOverride then
						found = true
						hovered[i] = t.ent
					end
					break
				end

				if not found && hovered[i] then hovered[i] = nil end
			end
		end

		if not table.IsEmpty(hovered) then
			local clr = pl:GetWeaponColor()
			clr = Color(clr[1]*255,clr[2]*255,clr[3]*255)

			if hovered[1] then halo.Add({hovered[1]},clr,1,1,0) end
			if hovered[2] then halo.Add({hovered[2]},clr,1,1,0) end
		end
	end

	hook.Add("VRMod_Start","VRMod_InitHalos",function(pl)
		if pl == LocalPlayer() then
			hook.Add("PreDrawHalos","VRMod_PickupHalos",g_VR.DrawPickupHalos)
		end
	end)

	hook.Add("VRMod_Exit","VRMod_RemoveHalos",function(pl)
		if pl == LocalPlayer() then
			hook.Remove("PreDrawHalos","VRMod_PickupHalos")
		end
	end)

elseif SERVER then

	util.AddNetworkString("vrmod_pickup")
	
	local function CreatePhysHook()
		local function Simulate(ent, delta)
			local t = ent.vrmod_pickup_info

			if t.phys:IsAsleep() then t.phys:Wake() end

			local frame = g_VR[t.steamid] and g_VR[t.steamid].latestFrame
			if not frame then return end

			local handPos, handAng = (t.left && frame.lefthandPos or frame.righthandPos)+t.ply:GetPos(), (t.left && frame.lefthandAng or frame.righthandAng)
			local pos, ang = LocalToWorld(t.localPos, t.localAng, handPos, handAng)

			local params = {
				secondstoarrive = engine.TickInterval(),
				pos = pos,
				angle = ang,

				maxangular = 5000,
				maxangulardamp = 5000,

				maxspeed = 1000000,
				maxspeeddamp = 10000,

				dampfactor = 0.5,
				teleportdistance = 0,
				deltatime = delta
			}

			t.phys:ComputeShadowControl(params)
		end

		hook.Add("Tick","vrmod_pickup",function()
			if table.IsEmpty(vrmod.pickupList) then return end
			local delta = FrameTime()

			-- Reverse order to avoid issues when removing elements
			for i = #vrmod.pickupList,1,-1 do
				local t = vrmod.pickupList[i]

				if not t.ent:IsValid() or not t.phys:IsValid() or not t.phys:IsMoveable() or not g_VR[t.steamid] or not t.ply:Alive() or t.ply:InVehicle() then
					vrmod.DoDrop(t.steamid, t.left) --drop items that have become immovable or invalid
				else
					Simulate(t.ent,delta)
				end
			end
		end)
	end

	local function RemovePhysHook()
		hook.Remove("Tick","vrmod_pickup")
	end
	
	function vrmod.DoDrop(pl, bLeftHand, handVel, handAngVel)
		if not IsValid(pl) then return end
		local steamid = pl:SteamID()

		local handPos,handAng
		if bLeftHand then
			handPos,handAng = vrmod.GetLeftHandPose(pl)
		else
			handPos,handAng = vrmod.GetRightHandPose(pl)
		end

		for i,t in ipairs(vrmod.pickupList) do
			if t.steamid ~= steamid or t.left ~= bLeftHand then continue end

			-- In the future we could add a PreDrop hook here, but it probably won't be needed

			if IsValid(t.phys) then
				if IsValid(t.ent) then
					t.ent:SetCollisionGroup(t.collisionGroup)
				end

				if handPos then
					local wPos, wAng = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
					t.phys:SetPos(wPos)
					t.phys:SetAngles(wAng)
					t.phys:SetVelocity(t.ply:GetVelocity() + handVel)
					t.phys:SetAngleVelocity(t.phys:WorldToLocalVector(handAngVel))

					t.phys:Wake()
				end
			end

			net.Start("vrmod_pickup")
				NetWritePlayer(t.ply)
				net.WriteUInt(t.ent:EntIndex()-1,13)
				net.WriteBool(true) --drop
			net.Broadcast()

			if g_VR[t.steamid] then
				g_VR[t.steamid].heldItems[bLeftHand && 1 or 2] = nil
			end

			table.remove(vrmod.pickupList,i)

			if table.IsEmpty(vrmod.pickupList) then
				RemovePhysHook()
			end

			hook.Run("VRMod_Drop", t.ply, t.ent)
			break
		end
	end

	function vrmod.DoPickup(pl,ent,bLeft,localPos,localAng,phys)
		if not pl:IsValid() or not ent:IsValid() then return end

		phys = phys or ent:GetPhysicsObject()
		if not phys:IsValid() then return end
		local steamid = pl:SteamID()

		hook.Run("VRMod_PrePickup",ent,ply)

		if table.IsEmpty(vrmod.pickupList) then
			CreatePhysHook()
		end

		-- Drop item if we're already holding one
		local held = g_VR[steamid].heldItems[bLeft && 1 or 2]
		if held && held.ent ~= ent then
			vrmod.DoDrop(pl,bLeft)
		end

		--if the item is already being held we should overwrite the existing pickup instead of adding a new one
		local colGroup
		for i,t in ipairs(vrmod.pickupList) do
			if ent == t.ent then
				colGroup = t.collisionGroup
				g_VR[t.steamid].heldItems[t.left && 1 or 2] = nil
				table.remove(vrmod.pickupList,i)
				break
			end
		end

		if not colGroup then --new pickup
			pl:PickupObject(ent) --this is done to trigger map logic
			ent:PhysWake()

			timer.Simple(0,function()
				if IsValid(pl) && IsValid(ent) then pl:DropObject() end
			end)
		end

		if ent.ArcticVRMagazine && ent.Pose then -- ArcVR mags get set manually (if they implement their own grabpose we should remove this)
			localPos, localAng = ent.Pose.pos*1,ent.Pose.ang*1
			localPos[2] = -localPos[2]

			if !bLeft then
				localPos,localAng = WorldToLocal(localPos,localAng,vector_origin,Angle(180,180))
			end
		end

		if not localPos or not localAng then
			local pos,ang
			if bLeft then
				pos,ang = vrmod.GetLeftHandPose(pl)
			else
				pos,ang = vrmod.GetRightHandPose(pl)
			end

			localPos, localAng = WorldToLocal(ent:GetPos(),ent:GetAngles(),pos,ang)
		end
		
		local info = {
			ent = ent,
			phys = phys,
			left = bLeft,
			localPos = localPos,
			localAng = localAng,
			collisionGroup = colGroup or ent:GetCollisionGroup(),
			steamid = steamid,
			ply = pl
		}

		table.insert(vrmod.pickupList,info)

		if !g_VR[steamid].heldItems then g_VR[steamid].heldItems = {} end
		g_VR[steamid].heldItems[bLeft && 1 or 2] = info

		ent.vrmod_pickup_info = info
		ent:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) --don't collide with the player

		net.Start("vrmod_pickup")
			NetWritePlayer(pl)
			net.WriteUInt(ent:EntIndex()-1,13)
			net.WriteBool(false)
			net.WriteBool(bLeft)
			net.WriteVector(localPos)
			net.WriteAngle(localAng)
			net.WriteFloat(ent:GetCreationTime())
		net.Broadcast()

		hook.Run("VRMod_PostPickup",ent,ply)
	end
	
	function vrmod.AttemptPickup(ply, bLeftHand)
		if not vrmod.IsHandEmpty(ply,bLeftHand) then return end

		-- TEMP: Avoid multiple pickups on the same tick
		if ply.lastVRPickup == engine.TickCount() then
			return
		else
			ply.lastVRPickup = engine.TickCount()
		end

		local handPos,handAng
		if bLeftHand then
			handPos,handAng = vrmod.GetLeftHandPose(ply)
		else
			handPos,handAng = vrmod.GetRightHandPose(ply)
		end
		local pickupPoint = vrmod.GetPalm(ply,bLeftHand,handPos,handAng)

		local grabbed
		local lpos,lang
		for _,t in ipairs(GetGrabbableObjects(ply,pickupPoint,handAng)) do
			if hook.Run("VRMod_Pickup", ply, t.ent) == false then continue end

			local tr = util.TraceLine({
				start = pickupPoint,
				endpos = t.point,
				filter = {ply,t.ent}
			})
			if tr.Hit then continue end

			grabbed = t.ent
			lpos,lang = WorldToLocal(t.ent:GetPos()+(pickupPoint-t.point),t.ent:GetAngles(),handPos,handAng)
			break
		end

		if grabbed then
			vrmod.DoPickup(ply,grabbed,bLeftHand,lpos,lang)
		end
	end
	
	vrmod.NetReceiveLimited("vrmod_pickup",10,400,function(len, ply)
		local bLeftHand = net.ReadBool()
		local bDrop = net.ReadBool()

		if not bDrop then
			vrmod.AttemptPickup(ply, bLeftHand)
		else
			vrmod.DoDrop(ply, bLeftHand, net.ReadVector(), net.ReadVector())
		end
	end)
	
	--block the gmod default pickup for vr players
	hook.Add("AllowPlayerPickup","vrmod",function(ply)
		if g_VR[ply:SteamID()] ~= nil then
			return false
		end
	end)

end