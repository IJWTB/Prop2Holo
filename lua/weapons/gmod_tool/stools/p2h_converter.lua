
-------------------------------------------
-- Prop to holo converter
-- by shadowscion

AddCSLuaFile( "p2h/convert.lua" )

-------------------------------------------
-- Shared
TOOL.Name     = "E2 Hologram Converter"
TOOL.Category = "Render"

if ( WireLib ) then
    TOOL.Tab                  = "Wire"
    TOOL.Wire_MultiCategories = { "Tools" }
end

TOOL.ClientConVar = {
    ["radius"] = 64,
    ["clipboard"] = 1,
    ["openeditor"] = 1,
    ["vclips"] = 1,
}


-------------------------------------------
-- Client
if ( CLIENT ) then
    local draw = draw
	
	include( "weapons/gmod_tool/stools/p2h/convert.lua" )
	
    language.Add( "Tool.p2h_converter.name", "E2 Hologram Converter" )
    language.Add( "Tool.p2h_converter.desc", "Converts props into holograms for use with expression2." )
    language.Add( "Tool.p2h_converter.0", "Click to select or deselect an entity. Hold USE to select entities within a radius. Hold SPRINT to restore the previous selection. Right click to finalize. Reload to clear selection." )

    function TOOL:LeftClick()  return true end
    function TOOL:RightClick() return true end

    local PANEL_TEXT_COLOR = Color( 0, 0, 0 )
	local COLOR_DARK_GRAY = Color( 50, 50, 50, 255 )
	local COLOR_MIDD_GRAY = Color( 125, 125, 125, 255 )
	local COLOR_LITE_GRAY = Color( 175, 175, 175, 255 )

    function TOOL.BuildCPanel( cpanel )
        -- Base panel
        function cpanel:Paint( w, h )
            draw.RoundedBox( 0, 0, 0, w, 20, COLOR_DARK_GRAY )
            draw.RoundedBox( 0, 1, 1, w - 2, 18, COLOR_LITE_GRAY )
        end

        -- Root category element
        local root = vgui.Create( "DCollapsibleCategory" )

        root:SetLabel( "Options" )
        root:SetExpanded( 1 )
        cpanel:AddItem( root )

        function root:Paint( w, h )
            draw.RoundedBox( 0, 0, 0, w, h, COLOR_DARK_GRAY )
            draw.RoundedBox( 0, 1, 1, w - 2, h - 2, COLOR_LITE_GRAY )
            draw.RoundedBox( 0, 1, 1, w - 2, 18, COLOR_MIDD_GRAY )
        end

        -- List container
        local container = vgui.Create( "DPanelList" )

        container:SetAutoSize( true )
        container:SetDrawBackground( false )
        container:SetSpacing( 5 )
        container:SetPadding( 5 )
        root:SetContents( container )

        ------------------------------------
        -- Clipboard toggle
        local xbox = vgui.Create( "DCheckBoxLabel" )

        xbox:SetText( "Copy to clipboard." )
        xbox:SetTextColor( PANEL_TEXT_COLOR )
        xbox:SetValue( 1 )
        xbox:SetConVar( "p2h_converter_clipboard" )
        container:AddItem( xbox )

        ------------------------------------
        -- Editor toggle
        local xbox = vgui.Create( "DCheckBoxLabel" )

        xbox:SetText( "Open in expression2 editor." )
        xbox:SetTextColor( PANEL_TEXT_COLOR )
        xbox:SetValue( 1 )
        xbox:SetConVar( "p2h_converter_openeditor" )
        container:AddItem( xbox )

        ------------------------------------
        -- VClip toggle
        local xbox = vgui.Create( "DCheckBoxLabel" )

        xbox:SetText( "Enable visclip support." )
        xbox:SetTextColor( PANEL_TEXT_COLOR )
        xbox:SetValue( 1 )
        xbox:SetConVar( "p2h_converter_vclips" )
        container:AddItem( xbox )

        ------------------------------------
        -- Set selection radius
        local ctrl = vgui.Create( "DNumSlider" )

        ctrl:SetText( "Selection radius." )
        ctrl.Label:SetTextColor( PANEL_TEXT_COLOR )
        ctrl:SetMin( 0 )
        ctrl:SetMax( 4096 )
        ctrl:SetDecimals( 0 )
        ctrl:SetConVar( "p2h_converter_radius" )
        container:AddItem( ctrl )
    end
	
elseif ( SERVER ) then

	local math = math
	local pairs = pairs
	local IsValid = IsValid
	
	-------------------------------------------
	-- Server
	util.AddNetworkString( "p2h_converter" )

	TOOL.Selection     = {}
	TOOL.PrevSelection = {}

	local COLOR_NORM = Color( 0, 255, 0, 150 )
	local COLOR_CLIP = Color( 0, 0, 255, 150 )

	local MAX_ALPHA = 255
	
	-------------------------------------------
	-- Checks if an entity belongs to a player
	local function IsPropOwner( ply, ent )
		if ( CPPI ) then return ent:CPPICanTool( ply, "prop2holo" ) end

		for k, v in pairs( g_SBoxObjects ) do
			for b, j in pairs( v ) do
				for _, e in pairs( j ) do
					if ( e == ent and k == ply:UniqueID() ) then return true end
				end
			end
		end

		return false
	end

	-------------------------------------------
	-- Checks if an entity is already selected
	function TOOL:IsSelected( ent )
		return self.Selection[ent]
	end

	-------------------------------------------
	--  Adds an entity to selection
	function TOOL:Select( ent )
		if ( not self:IsSelected( ent ) ) then
			local oldColor = ent:GetColor()

			ent:SetColor( ( ent.ClipData and tobool( self:GetClientNumber( "vclips" ) ) ) and COLOR_CLIP or COLOR_NORM )
			ent:SetRenderMode( RENDERMODE_TRANSALPHA )

			ent:CallOnRemove( "e2holo_convertor_onrmv", function( e )
				self:Deselect( e )
				self.Selection[e] = nil
			end )

			self.Selection[ent] = oldColor
		end
	end

	-------------------------------------------
	-- Removes an entity from selection
	function TOOL:Deselect( ent )
		if ( self:IsSelected( ent ) ) then
			local oldColor = self.Selection[ent]

			ent:SetColor( oldColor )
			ent:SetRenderMode( oldColor.a ~= MAX_ALPHA and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL )

			self.Selection[ent] = nil
		end
	end

	-------------------------------------------
	-- Removes all entities from selection
	function TOOL:Reload()
		self.PrevSelection = {}
		for ent, _ in pairs( self.Selection ) do
			self.PrevSelection[ent] = self.Selection[ent]
			self:Deselect( ent )
		end
		return true
	end

	-------------------------------------------
	-- Left click ( selection )
	function TOOL:LeftClick( tr )

		-- Filter out bad entities
		local ply = self:GetOwner()
		local ent = tr.Entity

		if ( not IsValid( ply ) ) then return false end
		if ( ent:IsWorld() and ( not ply:KeyDown( IN_USE ) and not ply:KeyDown( IN_SPEED ) ) ) then return false end

		if ( IsValid( ent ) ) then
			if ( ent:IsPlayer() ) then return false end
			if ( not IsPropOwner( ply, ent ) ) then return false end
			if ( not util.IsValidPhysicsObject( ent, tr.PhysicsBone ) ) then return false end
		end

		-- Select previous
		if ( ply:KeyDown( IN_SPEED ) ) then
			for ent, _ in pairs( self.PrevSelection ) do
				self:Select( ent )
			end
			return true
		end

		-- Area select
		if ( ply:KeyDown( IN_USE ) ) then
			local radius = math.Clamp( self:GetClientNumber( "radius" ), 64, 4096 )

			for _, ent in pairs( ents.FindInSphere( tr.HitPos, radius ) ) do
				if ( not IsValid( ent ) or not IsPropOwner( ply, ent ) ) then continue end
				self:Select( ent )
			end

			return true
		end

		-- Deselect entity if already selected
		if ( self:IsSelected( ent ) ) then self:Deselect( ent ) return true end

		-- Otherwise add to selection
		self:Select( ent )

		return true

	end

	-------------------------------------------
	-- Right click ( finalize )
	function TOOL:RightClick( tr )

		-- Filter out bad entities
		local ply = self:GetOwner()
		local ent = tr.Entity

		if ( ent:IsPlayer() ) then return false end
		
		-- Get the number of selected entities to send to the client
		local numSelected = table.Count( self.Selection )
		
		if ( not IsValid( ent ) ) then
			if ( numSelected == 0 ) then return false end
			
			-- Grab an entity from the selection list as use it as the base
			for otherEnt, _ in pairs( self.Selection ) do
				ent = otherEnt
				break
			end
		end
		
		-- Remove base entity from selection
		self.PrevSelection = {}
		self.PrevSelection[ent] = self.Selection[ent]
		self:Deselect( ent )

		net.Start( "p2h_converter" )
			-- Base entity
			net.WriteEntity( ent )

			-- Entity list
			if ( numSelected >= 1 ) then
				-- Send the number of entities to read, minus 1 to account for the base
				net.WriteUInt( numSelected - 1, 16 )
				
				-- Write out every entity to the client
				for ent, _ in pairs( self.Selection ) do
					net.WriteEntity( ent )
					self.PrevSelection[ent] = self.Selection[ent]
					self:Deselect( ent )
				end
			end
		net.Send( ply )

		-- Clear selection
		self.Selection = {}

		-- No serverside tool sounds
		return true

	end
	
end