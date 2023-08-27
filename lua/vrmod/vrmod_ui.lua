if CLIENT then
	g_VR = g_VR or {}
	g_VR.menuFocus = false
	g_VR.menuCursorX = 0
	g_VR.menuCursorY = 0

	-- The initial size of this material affects how RTs are scaled with it so we use a texture the size of the screen
	local mat_panel = CreateMaterial("vrmod_mat_ui","UnlitGeneric",{
		["$basetexture"] = "_rt_FullFrameFB",
		["$translucent"] = 1
	})
	
	g_VR.menus = {}
	local menus = g_VR.menus
	local menuOrder = {}
	local menusExist = false
	local prevFocusPanel = nil
	
	function VRUtilMenuRenderPanel(uid)
		if !menus[uid] or !menus[uid].panel or !menus[uid].panel:IsValid() then return end

		render.PushRenderTarget(menus[uid].rt)

		cam.Start2D()
			render.Clear(0,0,0,0,true,true)

			local oldclip = DisableClipping(false)
			render.SetWriteDepthToDestAlpha(false)

			menus[uid].panel:PaintManual()

			render.SetWriteDepthToDestAlpha(true)
			DisableClipping(oldclip)
		cam.End2D()

		render.PopRenderTarget()
	end

	function VRUtilMenuRenderStart(uid)
		render.PushRenderTarget(menus[uid].rt)
		cam.Start2D()
		render.Clear(0,0,0,0,true,true)
		render.SetWriteDepthToDestAlpha(false)
	end

	function VRUtilMenuRenderEnd()
		cam.End2D()
		render.PopRenderTarget()
		render.SetWriteDepthToDestAlpha(true)
	end

	function VRUtilIsMenuOpen(uid)
		return menus[uid] ~= nil
	end

	function VRUtilRenderMenuRTs()
		for uid,t in pairs(menus) do
			if t.renderFunc then
				if isfunction(t.renderFunc) then
					VRUtilMenuRenderStart(uid)
					t.renderFunc()
					VRUtilMenuRenderEnd()
				end

				continue
			end

			VRUtilMenuRenderPanel(uid)
		end
	end

	function VRUtilRenderMenuSystem()
		if menusExist == false then return end

		g_VR.menuFocus = false
		local menuFocusDist = 99999
		local menuFocusPanel = nil
		local menuFocusCursorWorldPos = nil
		
		local tms = render.GetToneMappingScaleLinear()
		render.SetToneMappingScaleLinear(Vector(1,1,1)*(g_VR.view.dopostprocess && 0.75 or 1))
		for k,v in ipairs(menuOrder) do
			k = v.uid
			if v.panel then
				if not IsValid(v.panel) or not v.panel:IsVisible() then
					VRUtilMenuClose(k)
					continue
				end
			end

			local pos, ang = v.pos, v.ang
			if v.attachment == 1 then
				pos, ang = LocalToWorld(pos, ang, g_VR.tracking.pose_lefthand.pos, g_VR.tracking.pose_lefthand.ang)
			elseif v.attachment == 2 then
				pos, ang = LocalToWorld(pos, ang, g_VR.tracking.pose_righthand.pos, g_VR.tracking.pose_righthand.ang)
			elseif v.attachment == 3 then
				pos, ang = LocalToWorld(pos, ang, g_VR.tracking.hmd.pos, g_VR.tracking.hmd.ang)
			elseif v.attachment == 4 then
				pos, ang = LocalToWorld(pos, ang, g_VR.origin, g_VR.originAngle)
			end

			cam.IgnoreZ(true)
			cam.Start3D2D( pos, ang, v.scale )
				surface.SetDrawColor(255,255,255)

				mat_panel:SetTexture("$basetexture",v.rt:GetName())
				surface.SetMaterial(mat_panel)
				surface.DrawTexturedRect(0,0,v.width,v.height)

				--debug outline
				--surface.SetDrawColor(255,0,0,255)
				--surface.DrawOutlinedRect(0,0,v.width,v.height)
			cam.End3D2D()
			cam.IgnoreZ(false)

			if v.cursorEnabled then
				local cursorX, cursorY = -1,-1
				local cursorWorldPos = Vector()
				local start = g_VR.tracking.pose_righthand.pos
				local dir = g_VR.tracking.pose_righthand.ang:Forward()
				local dist
				local normal = ang:Up()
				local A = normal:Dot(dir)

				if A < 0 then
					local B = normal:Dot(pos-start)
					if B <  0 then
						dist = B/A
						cursorWorldPos = start+dir*dist
						local tp, unused = WorldToLocal( cursorWorldPos, Angle(), pos, ang)
						cursorX = tp.x*(1/v.scale)
						cursorY = -tp.y*(1/v.scale)
					end
				end

				if cursorX >= 0 and cursorY >= 0 and cursorX <= v.width and cursorY <= v.height and dist <= menuFocusDist then
					g_VR.menuFocus = k
					g_VR.menuCursorX = cursorX
					g_VR.menuCursorY = cursorY
					menuFocusDist = dist
					menuFocusPanel = v.panel
					menuFocusCursorWorldPos = cursorWorldPos
				end
			end
		end
		render.SetToneMappingScaleLinear(tms)

		if menuFocusPanel ~= prevFocusPanel then
			if IsValid(prevFocusPanel) then
				prevFocusPanel:SetMouseInputEnabled(false)
			end
			if IsValid(menuFocusPanel) then
				menuFocusPanel:SetMouseInputEnabled(true)
			end
			gui.EnableScreenClicker(menuFocusPanel ~= nil)
			prevFocusPanel = menuFocusPanel
		end

		if g_VR.menuFocus then
			render.SetColorMaterialIgnoreZ()
			render.DrawBeam(g_VR.tracking.pose_righthand.pos, menuFocusCursorWorldPos, 0.1, 0, 1, Color(0,0,255))
			input.SetCursorPos(g_VR.menuCursorX,g_VR.menuCursorY)
		end
	end
	
	function VRUtilMenuOpen(uid, width, height, panel, attachment, pos, ang, scale, cursorEnabled, closeFunc, renderFunc)
		if menus[uid] then return end

		menus[uid] = {
			uid = uid,
			panel = panel,
			closeFunc = closeFunc,
			attachment = attachment,
			pos = pos,
			ang = ang,
			scale = scale,
			cursorEnabled = cursorEnabled,
			rt = GetRenderTarget("vrmod_rt_ui_"..uid, width, height),
			width = width,
			height = height,
			renderFunc = renderFunc
		}

		table.insert(menuOrder,menus[uid])
		
		if panel then
			panel:SetPaintedManually(true)
		end
		
		render.PushRenderTarget(menus[uid].rt)
		render.Clear(0,0,0,0,true,true)
		render.PopRenderTarget()
		
		menusExist = true
	end
	
	function VRUtilMenuClose(uid)
		for k,v in pairs(menus) do
			if k == uid or not uid then
				if IsValid(v.panel) then
					v.panel:SetPaintedManually(false)
				end

				if v.closeFunc then
					v.closeFunc()
				end

				for k2,v2 in ipairs(menuOrder) do
					if v2 == v then
						table.remove(menuOrder,k2)
						break
					end
				end
				menus[k] = nil
			end
		end

		if table.IsEmpty(menus) then
			g_VR.menuFocus = false
			menusExist = false
			gui.EnableScreenClicker(false)
		end
	end
	
	hook.Add("VRMod_Input","ui",function(action, pressed)
		if g_VR.menuFocus and action == "boolean_primaryfire" then
			if pressed then
				gui.InternalMousePressed(MOUSE_LEFT)
			else
				gui.InternalMouseReleased(MOUSE_LEFT)
			end
		end
	end)

end