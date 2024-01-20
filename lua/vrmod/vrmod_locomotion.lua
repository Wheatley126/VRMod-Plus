-- TELEPORT CODE START
local cv_allowtp = CreateConVar("vrmod_allow_teleport", "1", FCVAR_REPLICATED)

local rayHeight = 32
local fallHeight = 236
local up = Vector(0,0,1)
local slopeZ = 0.707107

-- Returns the end position and normal
local function FindTeleportPos(ply,startPos,ang)
	-- Don't allow teleporting if we're falling
	if not ply:OnGround() then return false,startPos,vector_origin end

	local norm = ang:Forward()
	local speed = ply:GetWalkSpeed()+(ply:GetRunSpeed()-ply:GetWalkSpeed())/2

	local tr = util.TraceLine({
		start = startPos,
		endpos = startPos+norm*speed,
		filter = ply,
		collisiongroup = COLLISION_GROUP_PLAYER,
		mask = MASK_PLAYERSOLID
	})

	if not tr.Hit then
		return false,startPos+norm*speed,-norm
	end

	local realPos,hitnorm = tr.HitPos,tr.HitNormal
	local renderPos = Vector(realPos)

	local mins,maxs = ply:GetHullDuck()
	local tall = Vector(0,0,maxs[3]-mins[3])

	-- Check for floor
	tr = util.TraceHull({
		start = realPos,
		endpos = realPos+tall,
		filter = ply,
		mins = mins,
		maxs = maxs,
		collisiongroup = COLLISION_GROUP_PLAYER,
		mask = MASK_PLAYERSOLID
	})

	local raised = false
	if tr.FractionLeftSolid > 0 then
		realPos[3] = realPos[3]+tall[3]*tr.FractionLeftSolid--+0.05
		raised = true
	end

	--- Past here is checking if the area should be accessible

	-- TODO: Add fall damage check to height restriction
	if (raised && up[3] or hitnorm[3]) < slopeZ or realPos[3]-ply:GetPos()[3] > math.max(ply:GetStepSize(),ply:GetJumpPower()*0.34) or tr.Fraction-tr.FractionLeftSolid <= 0 then
		return false,renderPos,hitnorm
	end

	local fullmins,fullmaxs = ply:GetHull()
	local add = Vector(0,0,fullmaxs[3]-maxs[3])

	-- Make sure the area is accessible
	tr = util.TraceHull({
		start = ply:GetPos()+add,
		endpos = realPos+add,
		filter = ply,
		mins = mins,
		maxs = maxs,
		collisiongroup = COLLISION_GROUP_PLAYER,
		mask = MASK_PLAYERSOLID
	})
	if tr.Hit then
		return false,renderPos,hitnorm
	end

	return true,realPos,raised && up or hitnorm
end

if SERVER then
	util.AddNetworkString("vrmod_teleport")
	vrmod.NetReceiveLimited("vrmod_teleport",10,200,function(len, ply)
		local pos,ang = net.ReadVector(),net.ReadAngle()

		-- Previously this also required noclip permissions
		-- if (hook.Run("PlayerNoClip", ply, true) == true or ULib and ULib.ucl.query( ply, "ulx noclip" ) == true)
		if pos and ang and cv_allowtp:GetBool() and vrmod.IsPlayerInVR(ply) then
			local success,hitpos,hitang = FindTeleportPos(ply,pos,ang)
			if success then
				ply:SetPos(hitpos)
			else
				-- TODO: Play fail sound
			end
		end
	end)


	return
end

local function GetSegmentPos(i,forw,zDiff)
	local perc = (i-1)/16

	local bend = math.min(math.max(forw*0.05,zDiff*0.1),20) -- Arc elasticity
	return Vector(forw*perc,0,math.sin(perc*3.14)*bend)
end

local function UpdatePreviewBones(self,startpos,endpos,endang,success)
	self:SetupBones() -- Avoid "Bone is unwriteable" error

	local mtx = Matrix()
	mtx:SetTranslation(endpos)
	mtx:SetAngles(endang)
	if not success then
		mtx:SetScale(Vector(0.5,0.5,0.5))
	end

	self:SetBoneMatrix(0,mtx)

	local offset = endpos-startpos
	local realang = offset:Angle()
	local lOffset = WorldToLocal(endpos,angle_zero,startpos,realang)[1]

	-- Gap fix
	local gap = lOffset*0.003

	for bone = 1,16 do
		local pos = GetSegmentPos(bone,lOffset,offset[3])
		local ang = (GetSegmentPos(bone+1,lOffset,offset[3])-GetSegmentPos(bone-1,lOffset,offset[3])):Angle()
		ang[1] = ang[1]-90

		pos,ang = LocalToWorld(pos,ang,startpos,realang)

		mtx:Identity()
		mtx:SetTranslation(pos)
		mtx:SetAngles(ang)
		mtx:SetScale(Vector(1,1,lOffset/16+gap))

		self:SetBoneMatrix(bone,mtx)
	end
end

local mat = Material("vrmod/tpbeam")
local clr_success = Vector(100,255,100)/255
local clr_fail = Vector(255,100,100)/255

local function DoDraw()
	local startpos,startang = g_VR.tracking.pose_righthand.pos,g_VR.tracking.pose_righthand.ang

	local success,hitpos,hitnorm = FindTeleportPos(LocalPlayer(),startpos,startang)
	local endang = hitnorm:Angle()

	if hook.Run("VRMod_DrawTeleport",startpos,hitpos,endang,success) then return end

	if not IsValid(tpEnt) then
		tpEnt = ClientsideModel("models/vrmod/tpbeam.mdl")
		tpEnt:SetNoDraw(true)
		--tpEnt:SetRenderMode(RENDERMODE_TRANSCOLOR)
	end

	endang[1] = endang[1]+90
	endang[3] = endang[3]+90
	UpdatePreviewBones(tpEnt,startpos,hitpos,endang,success)

	if success then mat:SetVector("$color2",clr_success) else mat:SetVector("$color2",clr_fail) end
	mat:SetFloat("$alpha",0.588) -- 150/255

	render.ModelMaterialOverride(mat)
	tpEnt:DrawModel()
	render.ModelMaterialOverride()
end

local teleporting = false
local tpEnt
function vrmod.TeleportStart()
	if teleporting then return end

	hook.Add("PreDrawTranslucentRenderables","VRMod_DrawTeleport",DoDraw)

	teleporting = true
end

function vrmod.TeleportEnd()
	if not teleporting then return end
	local startpos,startang = g_VR.tracking.pose_righthand.pos,g_VR.tracking.pose_righthand.ang
	local success,hitpos,hitnorm = FindTeleportPos(LocalPlayer(),startpos,startang)

	if success then
		net.Start("vrmod_teleport")
			net.WriteVector(startpos)
			net.WriteAngle(startang)
		net.SendToServer()
	else
		-- TODO: Play fail sound
	end

	hook.Remove("PreDrawTranslucentRenderables","VRMod_DrawTeleport")
	if IsValid(tpEnt) then
		tpEnt:Remove()
		tpEnt = nil
	end

	teleporting = false
end


-- TELEPORT CODE END


local convars, convarValues = vrmod.AddCallbackedConvar("vrmod_controlleroriented", "controllerOriented", "0", nil, nil, nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_smoothturn", "smoothTurn", "0", nil, nil, nil, nil, tobool)
vrmod.AddCallbackedConvar("vrmod_smoothturnrate", "smoothTurnRate", "180", nil, nil, nil, nil, tonumber)
vrmod.AddCallbackedConvar("vrmod_crouchthreshold", "crouchThreshold", "40", nil, nil, nil, nil, tonumber)

local zeroVec, zeroAng = Vector(), Angle()
local upVec = Vector(0,0,1)

local function start()
	local ply = LocalPlayer()
	local followVec = zeroVec
	local originVehicleLocalPos, originVehicleLocalAng = zeroVec, zeroAng
	
	vrmod.AddInGameMenuItem("#vrmod.quicksettings.vehiclereset", 3, 1, function()
		originVehicleLocalPos = nil
	end)
	
	hook.Add("PreRender","vrmod_locomotion",function()
		if not g_VR.threePoints then return end
		if ply:InVehicle() then
			local v = ply:GetVehicle()
			local attachment = v:GetAttachment(v:LookupAttachment("vehicle_driver_eyes"))
			if not originVehicleLocalPos then
				local originHmdRelV, originHmdRelA = WorldToLocal(g_VR.origin, g_VR.originAngle, g_VR.tracking.hmd.pos, Angle(0,g_VR.tracking.hmd.ang.yaw,0)) --where the origin is relative to the hmd				
				g_VR.origin, g_VR.originAngle = LocalToWorld(originHmdRelV + Vector(7,0,2), originHmdRelA, attachment.Pos, attachment.Ang) --where the origin would be if the attachment was the hmd
				originVehicleLocalPos, originVehicleLocalAng = WorldToLocal( g_VR.origin, g_VR.originAngle, attachment.Pos, attachment.Ang ) --new origin relative to the attachment
			end
			g_VR.origin, g_VR.originAngle = LocalToWorld( originVehicleLocalPos, originVehicleLocalAng, attachment.Pos, attachment.Ang )
			return
		end
		if originVehicleLocalPos then
			originVehicleLocalPos = nil
			g_VR.originAngle = Angle(0, g_VR.originAngle.yaw, 0)
		end
		local plyPos = ply:GetPos()
		local turnAmount = convarValues.smoothTurn and -g_VR.input.vector2_smoothturn.x * convarValues.smoothTurnRate * RealFrameTime() or g_VR.changedInputs.boolean_turnright and -30 or g_VR.changedInputs.boolean_turnleft and 30 or 0
		if turnAmount ~= 0 then
			g_VR.origin = LocalToWorld( g_VR.origin-plyPos, zeroAng, plyPos, Angle(0,turnAmount,0) )
			g_VR.originAngle.yaw = g_VR.originAngle.yaw + turnAmount
		end
		--make the player follow the hmd
		local plyTargetPos = g_VR.tracking.hmd.pos + upVec:Cross(g_VR.tracking.hmd.ang:Right())*-10
		followVec = (ply:GetMoveType() == MOVETYPE_NOCLIP) and zeroVec or Vector( (plyTargetPos.x - plyPos.x) * 8 , (plyPos.y - plyTargetPos.y) * -8,0)
		--teleport view if further than 64 units from target
		if followVec:LengthSqr() > 262144 then 
			local prevOrigin = g_VR.origin
			g_VR.origin = g_VR.origin + (plyPos-plyTargetPos)
			g_VR.origin.z = plyPos.z
			followVec = zeroVec
			return
		end
		local groundEnt = ply:GetGroundEntity()
		local groundVel = IsValid(groundEnt) and groundEnt:GetVelocity() or zeroVec
		originVelocity = ply:GetVelocity() - followVec + groundVel
		originVelocity.z = 0
		if originVelocity:Length() < 15 then
			originVelocity = zeroVec
		end
		g_VR.origin = g_VR.origin + originVelocity*FrameTime()
		g_VR.origin.z = plyPos.z
	end)
	
	hook.Add("CreateMove","vrmod_locomotion",function(cmd)
		if !g_VR.threePoints then return end

		--vehicle behaviour
		if ply:InVehicle() then
			cmd:SetForwardMove((g_VR.input.vector1_forward-g_VR.input.vector1_reverse)*400)
			cmd:SetSideMove(g_VR.input.vector2_steer.x*400)
			local _,relativeAng = WorldToLocal(Vector(0,0,0),g_VR.tracking.hmd.ang,Vector(0,0,0),ply:GetVehicle():GetAngles())
			cmd:SetViewAngles(relativeAng) --turret aiming
			cmd:SetButtons( bit.bor(cmd:GetButtons(), g_VR.input.boolean_turbo and IN_SPEED or 0, g_VR.input.boolean_handbrake and IN_JUMP or 0) )
			return
		end

		local moveType = ply:GetMoveType()
		cmd:SetButtons( bit.bor(cmd:GetButtons(), g_VR.input.boolean_jump and IN_JUMP + IN_DUCK or 0,  g_VR.input.boolean_sprint and IN_SPEED or 0, moveType == MOVETYPE_LADDER and IN_FORWARD or 0, (g_VR.tracking.hmd.pos.z < ( g_VR.origin.z + convarValues.crouchThreshold )) and IN_DUCK or 0 ) )

		--set view angles to viewmodel muzzle angles for engine weapon support, note: movement is relative to view angles
		local viewAngles = g_VR.currentvmi and g_VR.currentvmi.wrongMuzzleAng and g_VR.tracking.pose_righthand.ang or g_VR.viewModelMuzzle and g_VR.viewModelMuzzle.Ang or g_VR.tracking.hmd.ang
		viewAngles = viewAngles:Forward():Angle()
		cmd:SetViewAngles(viewAngles)

		--noclip behaviour
		if moveType == MOVETYPE_NOCLIP then
			cmd:SetForwardMove( math.abs(g_VR.input.vector2_walkdirection.y) > 0.5 and g_VR.input.vector2_walkdirection.y or 0 )
			cmd:SetSideMove( math.abs(g_VR.input.vector2_walkdirection.x) > 0.5 and g_VR.input.vector2_walkdirection.x or 0 )
			originVelocity = ply:GetVelocity()
			return
		end
		--
		local joystickVec = LocalToWorld(Vector(g_VR.input.vector2_walkdirection.y * math.abs(g_VR.input.vector2_walkdirection.y), (-g_VR.input.vector2_walkdirection.x) * math.abs(g_VR.input.vector2_walkdirection.x), 0)*ply:GetMaxSpeed()*0.9, Angle(0,0,0), Vector(0,0,0), Angle(0, convarValues.controllerOriented and g_VR.tracking.pose_lefthand.ang.yaw or g_VR.tracking.hmd.ang.yaw, 0))
		--
		local walkDirViewAngRelative = WorldToLocal(followVec + joystickVec, zeroAng, zeroVec, Angle(0,viewAngles.yaw,0))
		cmd:SetForwardMove( walkDirViewAngRelative.x )
		cmd:SetSideMove( -walkDirViewAngRelative.y )
	end)
	
	--
	concommand.Add("vrmod_debuglocomotion", function( ply, cmd, args )
		hook[args[1] == "1" and "Add" or "Remove"]("PostDrawTranslucentRenderables","vrmod_playspaceviz",function(depth, sky)
			if depth or sky then return end
			render.SetColorMaterial()
			render.DrawWireframeBox( LocalPlayer():GetPos(), zeroAng, Vector(1,1,0)*-16, Vector(1,1,4.5)*16, Color( 255, 0, 0 ))
			render.DrawWireframeBox( g_VR.origin, g_VR.originAngle, Vector(-200,-200,0.1), Vector(200,200,200), Color( 255, 255, 255 ), true )
			for i = 1,4 do
				render.DrawWireframeBox( g_VR.origin, g_VR.originAngle, Vector(-200,-300 + i*100,0.1), Vector(200,-250 + i*100,0.1), Color( 255, 255, 255 ), true )
				render.DrawWireframeBox( g_VR.origin, g_VR.originAngle, Vector(-300 + i*100,-200,0.1), Vector(-250 + i*100,200,0.1), Color( 255, 255, 255 ), true )
			end
		end)
	end)
	--]]
	
end

local function stop()
	hook.Remove("CreateMove","vrmod_locomotion")
	hook.Remove("PreRender","vrmod_locomotion")
	--
	hook.Remove("VRMod_PreRender","teleport")
	if IsValid(tpBeamEnt) then tpBeamEnt:Remove() end
	vrmod.RemoveInGameMenuItem("#vrmod.quicksettings.vehiclereset")
end

local function options( panel )
	local tmp = vgui.Create("DCheckBoxLabel")
	panel:Add(tmp)
	tmp:Dock( TOP )
	tmp:DockMargin( 5, 0, 0, 5 )
	tmp:SetDark(true)
	tmp:SetText("#vrmod.settings.loco.controlleroriented")
	tmp:SetChecked(convarValues.controllerOriented)
	function tmp:OnChange(val)
		convars.vrmod_controlleroriented:SetBool(val)
	end
			
	local tmp = vgui.Create("DCheckBoxLabel")
	panel:Add(tmp)
	tmp:Dock( TOP )
	tmp:DockMargin( 5, 0, 0, 0 )
	tmp:SetDark(true)
	tmp:SetText("#vrmod.settings.loco.smoothturn")
	tmp:SetChecked(convarValues.smoothTurn)
	function tmp:OnChange(val)
		convars.vrmod_smoothturn:SetBool(val)
	end
			
	local tmp = vgui.Create("DNumSlider")
	panel:Add(tmp)
	tmp:Dock( TOP )
	tmp:DockMargin( 5, 0, 0, 5 )
	tmp:SetMin(1)
	tmp:SetMax(360)
	tmp:SetDecimals(0)
	tmp:SetValue(convarValues.smoothTurnRate)
	tmp:SetDark(true)
	tmp:SetText("#vrmod.settings.loco.smoothturnrate")
	function tmp:OnValueChanged(val)
		convars.vrmod_smoothturnrate:SetInt(val)
	end

end

timer.Simple(0,function()
	vrmod.AddLocomotionOption("default", start, stop, options)
	vrmod.AddInGameMenuItem("#vrmod.quicksettings.noclip", 2, 1, function()
		LocalPlayer():ConCommand("noclip")
	end)
end)
