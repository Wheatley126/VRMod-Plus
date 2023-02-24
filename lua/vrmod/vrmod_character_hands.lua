if SERVER then return end

local convars = vrmod.GetConvars()

local dontUpdate = false
local function RefreshModel()
	if !dontUpdate then g_VR.UpdateHandsModel() end
end

vrmod.AddCallbackedConvar("vrmod_floatinghands_mdl",nil,"Citizen Hands",nil,nil,nil,nil,nil,RefreshModel)
vrmod.AddCallbackedConvar("vrmod_floatinghands_skin",nil,"0",nil,nil,0,nil,nil,RefreshModel)
vrmod.AddCallbackedConvar("vrmod_floatinghands_bg",nil,"",nil,nil,nil,nil,nil,RefreshModel)

g_VR.handsModels = g_VR.handsModels or {}

function vrmod.AddHandsOption(name,mdl)
	g_VR.handsModels[name] = mdl
end

vrmod.AddHandsOption("Citizen Hands","models/vrmod/hands/vr_hands.mdl")
vrmod.AddHandsOption("Rebel Gloves","models/vrmod/hands/vr_gloves.mdl")
vrmod.AddHandsOption("HEV Gloves","models/vrmod/hands/vr_hands_hev.mdl")

function vrmod.GetHands()
	return g_VR.hands or NULL
end

function vrmod.SetHandsModel(mdl)
	local hands = vrmod.GetHands()
	if hands:IsValid() then
		hands:ChangeModel(mdl)
	end
end

function g_VR.OpenHandsMenu()
	g_VR.CloseHandsMenu()

	local pnl = vgui.Create("DFrame")
	pnl:SetSize(640,320)
	pnl:Center()
	pnl:SetDraggable(false)
	pnl:SetTitle("Change Hands")

	local selected = string.Trim(convars.vrmod_floatinghands_mdl:GetString())

	local sec_mdl = pnl:Add("DScrollPanel")
	sec_mdl:SetSize(450,320)
	sec_mdl:DockMargin(5,5,5,5)

	function sec_mdl:Paint(w,h)
		surface.SetDrawColor(180,180,180)
		surface.DrawRect(0,0,w,h)
	end

	for name,mdl in SortedPairs(g_VR.handsModels) do
		local btn = sec_mdl:Add("DButton")
		btn:SetSize(32,32)
		btn:SetText(name)
		btn:SetFont("DermaLarge")
		btn:DockMargin(5,5,5,5)
		btn:Dock(TOP)

		function btn:Paint(w,h)
			surface.SetDrawColor(255,255,255)
			surface.DrawRect(0,0,w,h)

			if selected == self:GetValue() then
				surface.SetDrawColor(100,100,255)
				surface.DrawOutlinedRect(0,0,w,h,3)
			end
		end

		function btn:DoClick()
			dontUpdate = true
			convars.vrmod_floatinghands_skin:SetInt(0)
			convars.vrmod_floatinghands_bg:SetString("")
			dontUpdate = false

			convars.vrmod_floatinghands_mdl:SetString(self:GetValue())

			selected = self:GetValue()
		end
	end


	local sec_opt = pnl:Add("DScrollPanel")
	sec_opt:SetSize(165,320)
	sec_opt:DockMargin(5,5,5,5)

	function sec_opt:Paint(w,h)
		surface.SetDrawColor(220,220,220)
		surface.DrawRect(0,0,w,h)
	end


	sec_mdl:Dock(LEFT)
	sec_opt:Dock(RIGHT)

	g_VR.handsMenu = pnl
	pnl:MakePopup()
end

function g_VR.CloseHandsMenu()
	if IsValid(g_VR.handsMenu) then
		g_VR.handsMenu:Remove()
	end
end

function g_VR.UpdateHandsModel(noChange)
	local hands = vrmod.GetHands()
	if !noChange && !hands:IsValid() then return end

	local mdl,skn,bg = hook.Run("VRMod_GetHandsModel")

	if !mdl && !skn && !bg then
		local name = string.Trim(convars.vrmod_floatinghands_mdl:GetString())
		if g_VR.handsModels[name] then
			mdl = g_VR.handsModels[name]

			skn = convars.vrmod_floatinghands_skin:GetInt()

			bg = {}
			local bgStr = string.Trim(convars.vrmod_floatinghands_bg:GetString())
			for i,val in ipairs(string.Split(bgStr," ")) do
				bg[i-1] = tonumber(val)
			end
		end
	end

	if !mdl then mdl = "models/vrmod/hands/vr_hands.mdl" end
	if noChange then return mdl end

	if hands:GetModel() != mdl then
		hands:ChangeModel(mdl)
	end

	if !skn or skn < 0 or skn > hands:SkinCount()-1 then
		skn = 0
	else
		skn = math.floor(skn)
	end

	if !bg then bg = {} end

	if hands:GetSkin() != skn then
		hands:SetSkin(skn)
	end

	for group = 0,hands:GetNumBodyGroups()-1 do
		local val = bg[group]
		if !val or val < 0 or val > hands:GetBodygroupCount(group) then
			val = 0
		else
			val = math.floor(val)
		end

		if hands:GetBodygroup(group) != val then
			hands:SetBodygroup(group,val)
		end
	end
end

function g_VR.RecreateHands()
	local old = vrmod.GetHands()
	if old:IsValid() then old:Remove() end

	local hands = ClientsideModel(g_VR.UpdateHandsModel(true))
	hands:SetNoDraw(true)

	function hands:UpdateBoneInfo()
		self.LeftHandBone = self:LookupBone("ValveBiped.Bip01_L_Hand")
		self.RightHandBone = self:LookupBone("ValveBiped.Bip01_R_Hand")

		local fingerboneids = {}
		local tmp = {"0","01","02","1","11","12","2","21","22","3","31","32","4","41","42"}
		for i = 1,30 do
			fingerboneids[#fingerboneids+1] = self:LookupBone( "ValveBiped.Bip01_"..((i<16) and "L" or "R").."_Finger"..tmp[i-(i<16 and 0 or 15)] ) or -1
		end
		self.FingerIDs = fingerboneids

		self.BoneCount = self:GetBoneCount()
		local boneinfo = {}
		for i = 0, self.BoneCount-1 do
			local parent = self:GetBoneParent(i)
			local mtx = self:GetBoneMatrix(i) or Matrix()
			local mtxParent = self:GetBoneMatrix(parent) or mtx
			local relativePos, relativeAng = WorldToLocal( mtx:GetTranslation(), mtx:GetAngles(), mtxParent:GetTranslation(), mtxParent:GetAngles() )
			boneinfo[i] = {
				name = self:GetBoneName(i),
				parent = parent,
				relativePos = relativePos,
				relativeAng = relativeAng,
				offsetAng = angle_zero,
				pos = vector_origin,
				ang = angle_zero,
				targetMatrix = mtx
			}
		end

		self.BoneInfo = boneinfo
	end

	function hands:ChangeModel(mdl)
		self.BoneInfo = nil
		self:SetModel(mdl)
		self:SetupBones()

		self:UpdateBoneInfo()
	end

	hands:SetupBones()
	hands:UpdateBoneInfo()

	hands:AddCallback("BuildBonePositions",function(self)
		if !self.BoneInfo then return end

		if self.LastFrame ~= FrameNumber() then
			self.LastFrame = FrameNumber()

			local steamid = LocalPlayer():SteamID()
			local netFrame = g_VR.net[steamid] && g_VR.net[steamid].lerpedFrame
			if netFrame then
				self.BoneInfo[self.LeftHandBone].overridePos, self.BoneInfo[self.LeftHandBone].overrideAng = netFrame.lefthandPos, netFrame.lefthandAng
				self.BoneInfo[self.RightHandBone].overridePos, self.BoneInfo[self.RightHandBone].overrideAng = netFrame.righthandPos, netFrame.righthandAng + Angle(0,0,180)

				for k,v in pairs(self.FingerIDs) do
					if !self.BoneInfo[v] then continue end
					self.BoneInfo[v].offsetAng = LerpAngle(netFrame["finger"..math.floor((k-1)/3+1)], g_VR.openHandAngles[k], g_VR.closedHandAngles[k])
				end
			end

			for i = 0,self.BoneCount-1 do
				local info = self.BoneInfo[i]
				local parentInfo = self.BoneInfo[info.parent] or info
				local wpos, wang = LocalToWorld(info.relativePos, info.relativeAng + info.offsetAng, parentInfo.pos, parentInfo.ang)
				wpos = info.overridePos or wpos
				wang = info.overrideAng or wang
				local mat = Matrix()
				mat:Translate(wpos)
				mat:Rotate(wang)
				info.targetMatrix = mat
				info.pos = wpos
				info.ang = wang
			end
		end

		for i = 0,self.BoneCount-1 do
			if self:GetBoneMatrix(i) then
				self:SetBoneMatrix(i, self.BoneInfo[i].targetMatrix)
			end
		end
	end)

	g_VR.hands = hands

	g_VR.UpdateHandsModel()
end

if !IsValid(g_VR.hands) then
	g_VR.RecreateHands()
end