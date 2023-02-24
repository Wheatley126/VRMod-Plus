scripted_ents.Register({Type = "anim", Base = "vrmod_pickup"}, "vrmod_pickup")

local cvar_mass = CreateConVar("vrmod_pickup_maxmass","35",bit.bor(FCVAR_REPLICATED,FCVAR_CHEAT),"Highest mass that can be picked up, in kilograms",0)
local cvar_range = CreateConVar("vrmod_pickup_range","72",bit.bor(FCVAR_REPLICATED,FCVAR_CHEAT),"How far you can reach",0)

local function ClosestPointInOBB(ent,pos)
	local mins,maxs = ent:OBBMins(),ent:OBBMaxs()
	local lpos = ent:WorldToLocal(pos)
	lpos:SetUnpacked(math.Clamp(lpos[1],mins[1],maxs[1]), math.Clamp(lpos[2],mins[2],maxs[2]), math.Clamp(lpos[3],mins[3],maxs[3]))

	return ent:LocalToWorld(lpos)
end

local function CanGrab(e,phys,pl)
	if CLIENT && !phys:IsValid() then
		// Most entities won't have a PhysObj on the client	
		if e:GetMoveType() != MOVETYPE_VPHYSICS	then return false end

		local mass

		local info = util.GetModelInfo(e:GetModel())
		if info && info.KeyValues then
			info = util.KeyValuesToTable(info.KeyValues)
			if info.solid && info.solid.mass then
				mass = info.solid.mass
			end
		end

		return !mass or mass <= cvar_mass:GetFloat()
	end

	return phys:IsValid() && phys:IsMoveable() && phys:GetMass() <= cvar_mass:GetFloat() && !phys:HasGameFlag(FVPHYSICS_MULTIOBJECT_ENTITY) && (e.CPPICanPickup == nil or e:CPPICanPickup(pl))
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

	if !table.IsEmpty(tbl) then
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
	// TODO: Replace this with a simpler message that doesn't network pos/ang/vels
	// (The server's should be able to use it's own copy)
	function vrmod.Pickup( bLeftHand, bDrop )
		net.Start("vrmod_pickup")
			net.WriteBool(bLeftHand)
			net.WriteBool(bDrop or false)

			local pose = bLeftHand and g_VR.tracking.pose_lefthand or g_VR.tracking.pose_righthand
			net.WriteVector(pose.pos)
			net.WriteAngle(pose.ang)

			if bDrop then
				net.WriteVector(pose.vel)
				net.WriteVector(pose.angvel)
				g_VR[bLeftHand and "heldEntityLeft" or "heldEntityRight"] = nil
			end
		net.SendToServer()
	end

	local function GetHeldPos(self)
		local info = self.VRPickup
		if !info then return end
		local netinfo = g_VR.net[info.steamid]
		if !netinfo then return end

		local wpos, wang
		if info.left then
			wpos, wang = LocalToWorld(info.localPos, info.localAng, netinfo.lerpedFrame.lefthandPos, netinfo.lerpedFrame.lefthandAng)
		else
			wpos, wang = LocalToWorld(info.localPos, info.localAng, netinfo.lerpedFrame.righthandPos, netinfo.lerpedFrame.righthandAng)
		end

		return wpos,wang
	end

	local function HeldRenderOverride(self)
		local wpos,wang = GetHeldPos(self)
		if !wpos then return end

		local oldpos,oldang = self:GetRenderOrigin(),self:GetRenderAngles()
		self:SetRenderOrigin(wpos)
		self:SetRenderAngles(wang)
		self:SetupBones()

		self:DrawModel()

		self:SetRenderOrigin(oldpos)
		self:SetRenderAngles(oldang)
		self:InvalidateBoneCache()
	end

	local function HeldCalcPosition(self,pos,ang)
		local wpos,wang = GetHeldPos(self)
		if wpos then
			return wpos,wang
		else
			return pos,ang
		end
	end

	local function AddCreationCheck()
		hook.Add("NotifyShouldTransmit","VRMod_RecreatePickup",function(ent,transmit)
			if !transmit then return end

			local id = ent:EntIndex()
			if vrmod.pickupList[id] && ent:GetCreationTime() == vrmod.pickupList[ent:EntIndex()].createtime then
				local info = vrmod.pickupList[id]
				// Remove from list in-case it's invalid now
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
			ent.RenderOverride = HeldRenderOverride
			ent.CalcAbsolutePosition = HeldCalcPosition

			if pl == LocalPlayer() then
				g_VR[info.left && "heldEntityLeft" or "heldEntityRight"] = ent
			end

			hook.Run("VRMod_Pickup", pl, ent)
		end
	end

	function vrmod.OnDrop(entid,ply)
		--print("client received drop")
		vrmod.pickupList[entid] = nil

		local ent = Entity(entid)
		if ent:IsValid() then
			if ent.VRPickup then
				if ent.RenderOverride == HeldRenderOverride then
					ent.RenderOverride = ent.VRPickup.oldRender
				end
				if ent.CalcAbsolutePosition == HeldCalcPosition then
					ent.CalcAbsolutePosition = ent.VRPickup.oldCalcPos
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

	// TODO: Halos are broken in VR even with the current fix
	/*local hovered = {}
	function g_VR.DrawPickupHalos()
		local pl = LocalPlayer()

		// Update hovered props once per frame
		if vrmod.InEye(true) then
			for i = 1,2 do
				if !vrmod.IsHandEmpty(pl,i == 1) then
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

					if i == 1 or hovered[1] != t.ent && !t.ent.VRPickupRenderOverride then
						found = true
						hovered[i] = t.ent
					end
					break
				end

				if !found && hovered[i] then hovered[i] = nil end
			end
		end

		if !table.IsEmpty(hovered) then
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
	end)*/

elseif SERVER then

	util.AddNetworkString("vrmod_pickup")
	
	local pickupController

	local function CreatePickupController()
		--print("created controller")
		pickupController = ents.Create("vrmod_pickup")

		pickupController.ShadowParams = { 
			secondstoarrive = 0.0001, --1/cv_tickrate:GetInt()
			maxangular = 5000,
			maxangulardamp = 5000,
			maxspeed = 1000000,
			maxspeeddamp = 10000,
			dampfactor = 0.5,
			teleportdistance = 0,
			deltatime = 0,
		}

		function pickupController:PhysicsSimulate( phys, deltatime )
			phys:Wake()
			local t = phys:GetEntity().vrmod_pickup_info
			local frame = g_VR[t.steamid] and g_VR[t.steamid].latestFrame
			if !frame then return end
			local handPos, handAng = LocalToWorld( t.left and frame.lefthandPos or frame.righthandPos, t.left and frame.lefthandAng or frame.righthandAng, t.ply:GetPos(), Angle()) --frame is relative to ply pos when on foot
			self.ShadowParams.pos, self.ShadowParams.angle = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
			--this doesn't have to be inside PhysicsSimulate, we could potentially get rid of the motion controller entirely (as a micro optimization) and do this from the tick hook, but it seems to work better from here
			phys:ComputeShadowControl(self.ShadowParams)
		end
		pickupController:StartMotionController()

		hook.Add("Tick","vrmod_pickup",function()
			--drop items that have become immovable or invalid
			for i,t in ipairs(vrmod.pickupList) do
				if !IsValid(t.phys) or !t.phys:IsMoveable() or !g_VR[t.steamid] or !t.ply:Alive() or t.ply:InVehicle() then
					--print("dropping invalid")
					vrmod.DoDrop(t.steamid, t.left)
				end
			end
		end)
	end

	local function RemovePickupController()
		pickupController:StopMotionController()
		pickupController:Remove()
		pickupController = nil

		hook.Remove("Tick","vrmod_pickup")
		--print("removed controller")
	end
	
	function vrmod.DoDrop(pl, bLeftHand, handPos, handAng, handVel, handAngVel)
		if !IsValid(pl) then return end
		local steamid = pl:SteamID()

		for i,t in ipairs(vrmod.pickupList) do
			if t.steamid ~= steamid or t.left ~= bLeftHand then continue end

			local phys = t.phys
			if IsValid(phys) then
				t.ent:SetCollisionGroup(t.collisionGroup)
				pickupController:RemoveFromMotionController(phys)
				if handPos then
					local wPos, wAng = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
					phys:SetPos(wPos)
					phys:SetAngles(wAng)
					phys:SetVelocity( t.ply:GetVelocity() + handVel )
					phys:AddAngleVelocity( - phys:GetAngleVelocity() + phys:WorldToLocalVector(handAngVel))
					phys:Wake()
				end
			end

			net.Start("vrmod_pickup")
				NetWritePlayer(t.ply)
				net.WriteUInt(t.ent:EntIndex()-1,13)
				net.WriteBool(true) --drop
			net.Broadcast()

			if g_VR[t.steamid] then
				g_VR[t.steamid].heldItems[bLeftHand and 1 or 2] = nil
			end

			table.remove(vrmod.pickupList,i)

			if table.IsEmpty(vrmod.pickupList) then
				RemovePickupController()
			end

			hook.Call("VRMod_Drop", nil, t.ply, t.ent)
			return
		end
	end

	function vrmod.DoPickup(pl,ent,bLeft,localPos,localAng,phys)
		if !pl:IsValid() or !ent:IsValid() then return end

		phys = phys or ent:GetPhysicsObject()
		if !phys:IsValid() then return end
		local steamid = pl:SteamID()

		if pickupController == nil then
			CreatePickupController()
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

		if !colGroup then --new pickup
			pl:PickupObject(ent) --this is done to trigger map logic
			timer.Simple(0,function() pl:DropObject() end)

			pickupController:AddToMotionController(phys)
			ent:PhysWake()
		end

		if ent.ArcticVRMagazine && ent.Pose then
			localPos, localAng = ent.Pose.pos*1,ent.Pose.ang*1
			localPos[2] = -localPos[2]

			if !bLeft then
				localPos,localAng = WorldToLocal(localPos,localAng,vector_origin,Angle(180,180))
			end
		end

		if !localPos or !localAng then
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
	end
	
	function vrmod.AttemptPickup(ply, bLeftHand, handPos, handAng)
		if !vrmod.IsHandEmpty(ply,bLeftHand) then return end

		local steamid = ply:SteamID()
		local pickupPoint = LocalToWorld(Vector(3, bLeftHand and -1.5 or 1.5,0), Angle(), handPos, handAng)

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

		hook.Run("VRMod_PostPickup",grabbed)
	end
	
	vrmod.NetReceiveLimited("vrmod_pickup",10,400,function(len, ply)
		local bLeftHand = net.ReadBool()
		local bDrop = net.ReadBool()

		if !bDrop then
			vrmod.AttemptPickup(ply, bLeftHand, net.ReadVector(), net.ReadAngle())
		else
			vrmod.DoDrop(ply, bLeftHand, net.ReadVector(), net.ReadAngle(), net.ReadVector(), net.ReadVector())
		end
	end)
	
	--block the gmod default pickup for vr players
	hook.Add("AllowPlayerPickup","vrmod",function(ply)
		if g_VR[ply:SteamID()] ~= nil then
			return false
		end
	end)

end