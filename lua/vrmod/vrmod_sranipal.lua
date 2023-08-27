if CLIENT then

	local lip_error, eye_error = nil, nil
	local _, convarValues = vrmod.AddCallbackedConvar("vrmod_use_sranipal", nil, "0", nil, nil, nil, nil, tobool)
	local origMouthMove = nil
	local flexSetups = {}
	
	
	net.Receive( "vrmod_flexsetup", function( len, ply )
		local ply = net.ReadEntity()
		if not IsValid(ply) then return end
		ply.vrmod_flexsetup = {
			scale = net.ReadUInt(4),
			eye = net.ReadBool(),
			lip = net.ReadBool(),
			flexes = {},
			weights = {},
			smoothWeights = {},
		}
		for i = 1,net.ReadUInt(8) do
			ply.vrmod_flexsetup.flexes[#ply.vrmod_flexsetup.flexes+1] = net.ReadUInt(8)
		end
		if ply.vrmod_flexsetup.lip then
			if origMouthMove == nil then
				origMouthMove = GAMEMODE.MouthMoveAnimation
				GAMEMODE.MouthMoveAnimation = function(...)
					local args = {...}
					if not args[2].vrmod_flexsetup or args[2].vrmod_flexsetup.lip == false then
						origMouthMove(unpack(args))
					end
				end
			end
		end
		for i = 0, ply:GetFlexNum()-1 do
			ply:SetFlexWeight(i,0)
		end
		flexSetups[ply:SteamID()] = ply.vrmod_flexsetup
		hook.Add("UpdateAnimation","vrmod_sranipal",function(ply)
			local setup = ply.vrmod_flexsetup
			if setup then
				for k,v in ipairs(setup.flexes) do
					setup.smoothWeights[k] = Lerp(0.4, setup.smoothWeights[k] or 0, (setup.weights[k] or 0) * setup.scale)
					ply:SetFlexWeight(v, setup.smoothWeights[k] )
				end
			end
		end)
	end)
	
	net.Receive( "vrmod_flexdata", function( len, ply )
		local ply = net.ReadEntity()
		if not ply.vrmod_flexsetup then return end
		if ply.vrmod_flexsetup.eye then
			ply:SetEyeTarget(net.ReadVector())
		end
		for i = 1, #ply.vrmod_flexsetup.flexes do
			ply.vrmod_flexsetup.weights[i] = net.ReadUInt(16) / 65535
		end
	end)
	
	hook.Add("VRMod_Menu","vrmod_n_sranipal",function(frame)
		if VRMOD_SRanipalInit == nil then return end
		frame.SettingsForm:CheckBox("Enable SRanipal", "vrmod_use_sranipal")
		frame.SettingsForm:ControlHelp("For Vive Pro Eye / Vive Facial Tracker")
	end)
			
	hook.Add("VRMod_Start","sranipal",function(ply)
		if ply ~= LocalPlayer() then 
			net.Start("vrmod_requestflexsetup")
			net.WriteEntity(ply)
			net.SendToServer()
			return
		end
		vrmod.RemoveInGameMenuItem( "Flexbinder" )
		if not convarValues.vrmod_use_sranipal or VRMOD_SRanipalInit == nil then return end
		--
		local err1, err2 = VRMOD_SRanipalInit()
		eye_error, lip_error = (err1 or eye_error), (err2 or lip_error)
		local dataTables = {VRMOD_SRanipalGetLipData(), VRMOD_SRanipalGetEyeData()}
		--
		local filename = "vrmod/flexbinder/"..string.match(string.sub(ply:GetModel(),1,-5),"[^/]*$")..".txt"
		local connections = util.JSONToTable(file.Read(filename) or "[]")
		local flexScale = 1
		if isnumber(connections[#connections]) then
			flexScale = connections[#connections]
			connections[#connections] = nil
		end
		--
		local connectedFlexes = {}
		local function flexSetup()
			connectedFlexes = {}
			local addedFlexes = {}
			for k,v in ipairs(connections) do
				if addedFlexes[v.flex] then continue end
				addedFlexes[v.flex] = true
				connectedFlexes[#connectedFlexes+1] = v.flex
			end
			net.Start("vrmod_flexsetup")
			net.WriteUInt(flexScale,4)
			net.WriteBool(eye_error==0)
			net.WriteBool(lip_error==0)
			net.WriteUInt(#connectedFlexes,8)
			for k,v in ipairs(connectedFlexes) do
				net.WriteUInt(v,8)
			end
			net.SendToServer()
		end
		flexSetup()
		--
		if eye_error == 0 or lip_error == 0 then
			local weights = {}
			hook.Add("Tick","vrmod_flextest",function()
				local setup = ply.vrmod_flexsetup
				if not g_VR.active or not setup then return end
				net.Start("vrmod_flexdata", true)
				if eye_error == 0 then
					VRMOD_SRanipalGetEyeData()
					local leftEyePos, rightEyePos = g_VR.eyePosLeft, g_VR.eyePosRight
					local leftEyeDir, rightEyeDir = dataTables[2].gaze_direction, dataTables[3].gaze_direction
					local leftEyeDir = LocalToWorld(Vector(leftEyeDir.z, leftEyeDir.x, leftEyeDir.y),Angle(),Vector(),g_VR.view.angles)
					local rightEyeDir = LocalToWorld(Vector(rightEyeDir.z, rightEyeDir.x, rightEyeDir.y),Angle(),Vector(),g_VR.view.angles)
					local n = rightEyeDir:Cross(leftEyeDir:Cross(rightEyeDir))
					local c = leftEyePos + math.abs( (rightEyePos-leftEyePos):Dot(n) / leftEyeDir:Dot(n) ) * leftEyeDir
					if c.x == 1/0 or c.x ~= c.x then
						c = (dataTables[2].eye_openness > dataTables[3].eye_openness) and leftEyePos+leftEyeDir*100 or rightEyePos+rightEyeDir*100
					end
					ply:SetEyeTarget(c)
					net.WriteVector(c)
				end
				if lip_error == 0 then
					VRMOD_SRanipalGetLipData()
				end
				for i = 1,#connectedFlexes do
					weights[connectedFlexes[i]] = 0
				end
				for k,v in ipairs(connections) do
					weights[v.flex] = weights[v.flex] + dataTables[v.tab][v.key] * v.mul + v.add
				end
				for k,v in ipairs(connectedFlexes) do
					--ply:SetFlexWeight(v, weights[v])
					setup.weights[k] = weights[v]
					net.WriteUInt(weights[v]*65535, 16)
				end
				net.SendToServer()
			end)
		end
		--
		vrmod.AddInGameMenuItem("#vrmod.quicksettings.flex", 0, 1, function()
			
			local ang = Angle(0,g_VR.tracking.hmd.ang.yaw-90,45)
			local pos, ang = WorldToLocal( g_VR.tracking.hmd.pos + Vector(0,0,-20) + Angle(0,g_VR.tracking.hmd.ang.yaw,0):Forward()*30 + ang:Forward()*1366*-0.02 + ang:Right()*768*-0.02, ang, g_VR.origin, g_VR.originAngle)
			
			local blacklist = {
				["gaze_origin_mm"] = true,
				["gaze_direction"] = true,
				["head_rightleft"] = true,
				["head_updown"] = true,
				["head_tilt"] = true,
				["eyes_updown"] = true,
				["eyes_rightleft"] = true,
				["body_rightleft"] = true,
				["chest_rightleft"] = true,
				["head_forwardback"] = true,
				["gesture_updown"] = true,
				["gesture_rightleft"] = true,
				["timestamp"] = true,
			}
			local inputs, outputs = {}, {}
			for i = 1,#dataTables do
				for k,v in pairs(dataTables[i]) do
					inputs[#inputs+1] = not blacklist[k] and {(i==2 and "left_" or i==3 and "right_" or "")..k,k,i,{}} or nil --displayname, key, datatableindex, connections
				end
			end
			for i = 0,ply:GetFlexNum()-1 do
				outputs[#outputs+1] = not blacklist[ply:GetFlexName(i)] and {ply:GetFlexName(i), i, nil, {}} or nil --flexname, flexid, nil, connections
			end
			for k,v in ipairs(connections) do
				local inputIndex, outputIndex = 0,0
				for k2,v2 in ipairs(inputs) do
					inputIndex = (v2[2] == v.key and v2[3] == v.tab) and k2 or inputIndex
				end
				for k2,v2 in ipairs(outputs) do
					outputIndex = (v2[2] == v.flex) and k2 or outputIndex
				end
				inputs[inputIndex][4][#inputs[inputIndex][4]+1] = outputIndex
				outputs[outputIndex][4][#outputs[outputIndex][4]+1] = inputIndex
			end
			local draggedItem = 0
			local dragStartX, dragStartY = 0, 0
			local leftScrollAmount, rightScrollAmount = 0, 0
			local mul, add, test = 0, 0, 0
			local selectedInput, selectedOutput, selectedConnection = 0, 0, 0
			local hoveredInput, hoveredOutput = 0, 0
			local fileChanges = false
			--
			dataTables[#dataTables+1] = {0}
			local testConnections = {{key=1,tab=#dataTables,mul=0,add=0,flex=0}}
			local origConnections = connections
			--
			local function DrawFlexBinder()
				local cursorX, cursorY = g_VR.menuCursorX, g_VR.menuCursorY
				--handle click press
				if g_VR.menuFocus == "flexbinder" and g_VR.changedInputs.boolean_primaryfire == true then
					--scrollbars
					dragStartX, dragStartY = cursorX, cursorY
					if (cursorX > 5 and cursorX < 25) or (cursorX > 1341 and cursorX < 1361)  then
						draggedItem = cursorX >= 25 and 2 or 1
						dragStartY = dragStartY - (draggedItem==1 and leftScrollAmount or rightScrollAmount)
					end
					--sliders
					if cursorX > 460 and cursorX < 460+450 and cursorY > 289 and cursorY < 289+18*3 then
						draggedItem = 3+math.floor((cursorY-289)/18)
						if draggedItem == 5 then --test
							connections = testConnections
							testConnections[1].flex = outputs[selectedOutput][2]
							flexSetup()
						end
					end
					--select input/output
					local prevInput, prevOutput = selectedInput,selectedOutput
					if cursorX > 30 and cursorX < 330 and cursorY > 40 and cursorY < 763 then
						selectedInput = math.floor((cursorY-40+leftScrollAmount)/18)+1
					end
					if cursorX > 1036 and cursorX < 1336 and cursorY > 40 and cursorY < 763 then
						selectedOutput = math.floor((cursorY-40+rightScrollAmount)/18)+1
					end
					if (prevInput ~= selectedInput or prevOutput ~= selectedOutput) and selectedInput > 0 and selectedOutput > 0 then
						selectedConnection, add, mul = 0, 0, 0
						for k,v in ipairs(connections) do
							if v.key == inputs[selectedInput][2] and v.tab == inputs[selectedInput][3] and v.flex == outputs[selectedOutput][2] then
								selectedConnection = k
								add = v.add
								mul = v.mul
								break
							end
						end
					end
					--scale
					if ((cursorX > 1000 and cursorX < 1030) or (cursorX > 1121 and cursorX < 1151)) and cursorY > 5 and cursorY < 35 then
						flexScale = math.Clamp(flexScale + (cursorX < 1030 and -1 or 1),1,9)
						fileChanges = true
						flexSetup()
					end
					--clear
					if cursorX > 1156 and cursorX < 1256 and cursorY > 5 and cursorY < 35 then
						connections = {}
						for k,v in ipairs(inputs) do v[4] = {} end
						for k,v in ipairs(outputs) do v[4] = {} end
						selectedConnection = 0
						fileChanges = true
					end
					--save
					if cursorX > 1261 and cursorX < 1361 and cursorY > 5 and cursorY < 35 then
						file.CreateDir("vrmod/flexbinder")
						connections[#connections+1] = flexScale
						file.Write(filename,util.TableToJSON(connections,true))
						connections[#connections] = nil
						fileChanges = false
					end
					--connect/disconnect
					if cursorX > 770 and cursorX < 770+190 and cursorY > 347 and cursorY < 347+25 and selectedInput > 0 and selectedOutput > 0 then --todo remove input/output checks
						if selectedConnection == 0 then
							inputs[selectedInput][4][#inputs[selectedInput][4]+1] = selectedOutput
							outputs[selectedOutput][4][#outputs[selectedOutput][4]+1] = selectedInput
							connections[#connections+1] = {key = inputs[selectedInput][2], tab = inputs[selectedInput][3], mul = mul, add = add, flex = outputs[selectedOutput][2]}
							selectedConnection = #connections
						else
							for k,v in ipairs(inputs[selectedInput][4]) do
								if v == selectedOutput then
									table.remove(inputs[selectedInput][4], k)
									table.remove(connections,selectedConnection)
									selectedConnection, add, mul = 0, 0, 0
									break
								end
							end
							for k,v in ipairs(outputs[selectedOutput][4]) do
								if v == selectedInput then
									table.remove(outputs[selectedOutput][4], k)
									break
								end
							end
						end
						fileChanges = true
						flexSetup()
					end
				end
				--handle click release
				if g_VR.changedInputs.boolean_primaryfire == false then
					if draggedItem == 5 then
						test = 0
						connections = origConnections
						flexSetup()
					end
					if selectedConnection > 0 and (draggedItem == 3 or draggedItem == 4) then
						connections[selectedConnection].mul = mul
						connections[selectedConnection].add = add
						fileChanges = true
					end
					draggedItem = 0
				end
				--dragging
				if draggedItem > 0 then
					leftScrollAmount = draggedItem ~= 1 and leftScrollAmount or cursorY-dragStartY
					rightScrollAmount = draggedItem ~= 2 and rightScrollAmount or cursorY-dragStartY
					local sliderStep = 450/(2/0.05)
					mul = draggedItem ~= 3 and mul or math.Clamp(math.floor((cursorX-460+sliderStep/2)/sliderStep)*sliderStep/225-1,-1,1)
					add = draggedItem ~= 4 and add or math.Clamp(math.floor((cursorX-460+sliderStep/2)/sliderStep)*sliderStep/225-1,-1,1)
					if draggedItem == 5 then
						test = math.Clamp((cursorX-460-2)/450,0,1)
						testConnections[1].add = test
					end
				end
				--hovering
				hoveredInput = 0
				if not g_VR.input.boolean_primaryfire and cursorX > 30 and cursorX < 330 and cursorY > 40 and cursorY < 763 then
					hoveredInput = math.floor((cursorY-40+leftScrollAmount)/18)+1
					hoveredInput = (hoveredInput==selectedInput) and 0 or hoveredInput
				end
				hoveredOutput = 0
				if not g_VR.input.boolean_primaryfire and cursorX > 1036 and cursorX < 1336 and cursorY > 40 and cursorY < 763 then
					hoveredOutput = math.floor((cursorY-40+rightScrollAmount)/18)+1
					hoveredOutput = (hoveredOutput==selectedOutput) and 0 or hoveredOutput
				end
				--start rendering
				surface.SetFont( "ChatFont" )
				surface.SetTextColor( 255, 255, 255 )
				--background
				surface.SetDrawColor( 0, 0, 0, 230 )
				surface.DrawRect( 0, 0, 1366, 768 )
				--left scroll panel
				local contentHeight = #inputs*18
				local panelHeight = 768-45
				local maxScrollAmount = contentHeight-panelHeight
				leftScrollAmount = math.Clamp(leftScrollAmount,0,maxScrollAmount)
				surface.SetDrawColor( 128, 128, 128, 255 )
				surface.DrawRect( 5, 40, 20, panelHeight )
				surface.SetDrawColor( 64, 64, 64, 255 )
				surface.DrawRect( 6, 41 + leftScrollAmount, 18, panelHeight-maxScrollAmount-2 )
				local text_x, text_y = 30, 40-leftScrollAmount
				if hoveredInput > 0 then
					surface.SetDrawColor( 255, 255, 255, 255 )
					surface.DrawOutlinedRect(30,text_y+18*(hoveredInput-1),300,19)
				end
				if selectedInput > 0 then
					surface.SetDrawColor( 0, 255, 0, 255 )
					surface.DrawOutlinedRect(30,text_y+18*(selectedInput-1),300,19)
				end
				for k,v in ipairs(inputs) do
					surface.SetTextPos( text_x, text_y ) 
					surface.DrawText( v[1] )
					surface.SetTextPos( text_x + 250, text_y ) 
					surface.DrawText( tostring(math.Round(dataTables[v[3]][v[2]],3)) )
					text_y = text_y + 18
				end
				--right scroll panel
				local contentHeight = #outputs*18
				local maxScrollAmount = contentHeight-panelHeight
				rightScrollAmount = math.Clamp(rightScrollAmount,0,maxScrollAmount)
				surface.SetDrawColor( 128, 128, 128, 255 )
				surface.DrawRect( 1341, 40, 20, panelHeight )
				surface.SetDrawColor( 64, 64, 64, 255 )
				surface.DrawRect( 1342, 41 + rightScrollAmount, 18, panelHeight-maxScrollAmount-2 )
				local text_x, text_y = 1040, 40-rightScrollAmount
				if hoveredOutput > 0 then
					surface.SetDrawColor( 255, 255, 255, 255 )
					surface.DrawOutlinedRect(1036,text_y+18*(hoveredOutput-1),300,19)
				end
				if selectedOutput > 0 then
					surface.SetDrawColor( 0, 255, 0, 255 )
					surface.DrawOutlinedRect(1036,text_y+18*(selectedOutput-1),300,19)
				end
				for i = 1,#outputs do
					surface.SetTextPos( text_x, text_y ) 
					surface.DrawText( outputs[i][1] )
					surface.SetTextPos( text_x + 250, text_y ) 
					surface.DrawText( tostring(math.Round(ply:GetFlexWeight(outputs[i][2]),3)) )
					text_y = text_y + 18
				end
				--connecting lines
				local input = hoveredInput > 0 and hoveredInput or selectedInput
				if input > 0 then
					for k,v in ipairs(inputs[input][4]) do
						local tmp = (v == selectedOutput and input == selectedInput ) and 0 or 255
						surface.SetDrawColor(tmp,255,tmp,255)
						surface.DrawLine(330,49-leftScrollAmount+(input-1)*18,1036,49-rightScrollAmount+18*(v-1))
					end
				end
				local output = hoveredOutput > 0 and hoveredOutput or selectedOutput
				if output > 0 then
					for k,v in ipairs(outputs[output][4]) do
						local tmp = (v == selectedInput and output == selectedOutput ) and 0 or 255
						surface.SetDrawColor(tmp,255,tmp,255)
						surface.DrawLine(330,49-leftScrollAmount+(v-1)*18,1036,49-rightScrollAmount+18*(output-1))
					end
				end
				--edit node
				if selectedInput > 0 and selectedOutput > 0 then
					surface.SetDrawColor(200,200,200,255)
					surface.DrawOutlinedRect(383,284,600,100)
					surface.SetDrawColor( 0, 0, 0, 200 )
					surface.DrawRect(383,284,600,100)
					surface.SetDrawColor( 200, 200, 200, 255 )
					--if selectedConnection > 0 then
						surface.SetTextPos( 388, 289 ) 
						surface.DrawText( "Multiply" )
						surface.SetTextPos( 920, 289 ) 
						surface.DrawText( tostring(math.Round(mul,2)) )
						surface.DrawRect(460,295,450,4)
						surface.DrawRect(460+((mul+1)/2)*450,290,4,14)
						surface.SetTextPos( 388, 289+18 ) 
						surface.DrawText( "Add" )
						surface.SetTextPos( 920, 289+18 ) 
						surface.DrawText( tostring(math.Round(add,2)) )
						surface.DrawRect(460,295+18,450,4)
						surface.DrawRect(460+((add+1)/2)*450,290+18,4,14)
					--end
					surface.SetTextPos( 388, 289+18*2 ) 
					surface.DrawText( "Test" )
					surface.SetTextPos( 920, 289+18*2 ) 
					surface.DrawText( tostring(math.Round(test,2)) )
					surface.DrawRect(460,295+18*2,450,4)
					surface.DrawRect(460+test/1*450,290+18*2,4,14)
					
					surface.SetTextPos( 780, 350 ) 
					surface.DrawText( "Connect / Disconnect" )
					surface.DrawOutlinedRect(770,347,190,25)
				end
				--top bar
				render.OverrideBlend(true,BLEND_ZERO,BLEND_ZERO,BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
				surface.SetDrawColor( 0, 0, 0, 230 )
				surface.DrawRect(0,0,1366,40)
				surface.DrawRect(0,768-5,1366,5)
				render.OverrideBlend(false)
				surface.SetDrawColor( 255, 255, 255, 255 )
				surface.DrawOutlinedRect( 1000, 5, 30, 30 )
				surface.SetTextPos( 1010, 10 ) 
				surface.DrawText( "-      Scale: "..flexScale )
				surface.DrawOutlinedRect( 1121, 5, 30, 30 )
				surface.SetTextPos( 1130, 10 ) 
				surface.DrawText( "+" )
				surface.SetTextPos( 5, 10 ) 
				surface.DrawText( "lip_error: "..tostring(lip_error)..", eye_error: "..tostring(eye_error) )
				surface.SetTextPos( 500, 10 ) 
				surface.DrawText( "File: "..filename..(fileChanges and "*" or "") )
				surface.DrawOutlinedRect( 1156, 5, 100, 30 )
				surface.SetTextPos( 1185, 10 ) 
				surface.DrawText( "Clear" )
				surface.DrawOutlinedRect( 1261, 5, 100, 30 )
				surface.SetTextPos( 1290, 10 ) 
				surface.DrawText( "Save" )
			end

			VRUtilMenuOpen("flexbinder", 1366, 768, nil, 4, pos, ang, 0.04, true, nil, DrawFlexBinder)
			
			hook.Add("VRMod_OpenQuickMenu","flexbinder",function()
				hook.Remove("VRMod_OpenQuickMenu","flexbinder")
				VRUtilMenuClose("flexbinder")
				return false
			end)
		end)
	
	end)

	hook.Add("VRMod_Exit","sranipal",function(ply,steamid)
		ply.vrmod_flexsetup = nil
		flexSetups[steamid] = nil
		local found = false
		for k,v in pairs(flexSetups) do
			found = found or v.lip
		end
		if not found then
			GAMEMODE.MouthMoveAnimation = origMouthMove or GAMEMODE.MouthMoveAnimation
			origMouthMove = nil
		end
		if table.Count(flexSetups) == 0 then
			hook.Remove("UpdateAnimation","vrmod_sranipal")
		end
		if ply == LocalPlayer() then
			hook.Remove("Tick","vrmod_flextest")
		end
	end)

elseif SERVER then

	util.AddNetworkString("vrmod_requestflexsetup")
	util.AddNetworkString("vrmod_flexsetup")
	util.AddNetworkString("vrmod_flexdata")
	
	local function sendFlexSetup(ply, recipient)
		if ply.vrmod_flexsetup == nil then return end
		net.Start("vrmod_flexsetup")
		net.WriteEntity(ply)
		net.WriteUInt( ply.vrmod_flexsetup.scale, 4)
		net.WriteBool( ply.vrmod_flexsetup.eye)
		net.WriteBool( ply.vrmod_flexsetup.lip)
		net.WriteUInt(#ply.vrmod_flexsetup.flexes, 8)
		for k,v in ipairs(ply.vrmod_flexsetup.flexes) do
			net.WriteUInt(v,8)
		end
		if recipient then
			net.Send(recipient)
		else
			net.Broadcast()
		end
	end
	
	vrmod.NetReceiveLimited( "vrmod_requestflexsetup",10,32, function( len, ply )
		sendFlexSetup(net.ReadEntity(), ply)
	end)
	
	vrmod.NetReceiveLimited( "vrmod_flexsetup",10,1024, function( len, ply )
		ply.vrmod_flexsetup = {
			scale = net.ReadUInt(4),
			eye = net.ReadBool(),
			lip = net.ReadBool(),
			flexes = {}
		}
		for i = 1,net.ReadUInt(8) do
			ply.vrmod_flexsetup.flexes[#ply.vrmod_flexsetup.flexes+1] = net.ReadUInt(8)
		end
		for i = 0,ply:GetFlexNum()-1 do
			--if we don't do this and set flex weights on client they will look bugged / different in each eye
			--this also blocks blinking, and allows setting weights above 1 on client
			--and also allows client to set weights at any time without them getting pulled back to zero
			ply:SetFlexWeight(i,0)
		end
		sendFlexSetup(ply, nil)
	end)
	
	vrmod.NetReceiveLimited( "vrmod_flexdata",1/engine.TickInterval()+5,1024, function( len, ply )
		if not ply.vrmod_flexsetup then return end
		net.Start("vrmod_flexdata")
		net.WriteEntity(ply)
		if ply.vrmod_flexsetup.eye then
			net.WriteVector(net.ReadVector())
		end
		for k,v in ipairs(ply.vrmod_flexsetup.flexes) do
			net.WriteUInt( net.ReadUInt(16), 16 )
		end
		net.SendOmit(ply)
	end)

end
