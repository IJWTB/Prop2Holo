-------------------------------------------
-- Prop to holo converter
-- by shadowscion

-------------------------------------------
-- Shared
TOOL.Name     = "E2 Hologram Converter"
TOOL.Category = "Render"

if ( WireLib ) then
    TOOL.Tab                  = "Wire"
    TOOL.Wire_MultiCategories = { "Tools" }
end

TOOL.Information = {
	"left",
	"right",
	"reload",
	{
		name  = "shift_left",
		icon2  = "gui/e.png",
		icon = "gui/lmb.png",
	},
	{
		name  = "shift_right",
		icon2  = "gui/e.png",
		icon = "gui/rmb.png",
	}
}

TOOL.ClientConVar = {
    ["radius"]     = 64,
    ["clipboard"]  = 1,
    ["openeditor"] = 1,
    ["vclips"]     = 1,
}

local MODE = TOOL.Mode
local ENT_ID_BITS = 16


if ( SERVER ) then
	
	-------------------------------------------
	-- Server
	local math = math
	local pairs = pairs
	local IsValid = IsValid
	
	util.AddNetworkString( MODE )
	
	function TOOL:ShouldApplyVisclips() return tobool( self:GetClientNumber( "vclips" ) ) end
	
	TOOL.Selection     = {}
	TOOL.PrevSelection = {}

	local COLOR_NORM = Color( 0, 255, 0, 150 )
	local COLOR_CLIP = Color( 0, 0, 255, 150 )

	local MAX_ALPHA = 255
	
	-------------------------------------------
	-- Checks if an entity belongs to a player
	local function IsPropOwner( ply, ent )
		if ( CPPI ) then return ent:CPPICanTool( ply, "prop2holo" ) end
	
		local puid = ply:UniqueID()
		
		for uid, types in pairs( g_SBoxObjects ) do
			for _, ents in pairs( types ) do
				for _, e in pairs( ents ) do
					if ( e == ent and uid == puid ) then return true end
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

			ent:SetColor( (ent.ClipData and self:ShouldApplyVisclips() and COLOR_CLIP) or COLOR_NORM )
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
		
		local ply = self:GetOwner()
		local ent = tr.Entity

		if ( not IsValid( ply ) ) then return false end
		
		-- Filter out bad entities
		if ( IsValid( ent ) ) then
			if ( ent:IsPlayer() )                                       then return false end
			if ( not IsPropOwner( ply, ent ) )                          then return false end
			if ( not util.IsValidPhysicsObject( ent, tr.PhysicsBone ) ) then return false end
		end

		-- Shift + LMB -> Re-select the previous selection
		if ( ply:KeyDown( IN_USE ) or ply:KeyDown( IN_SPEED ) ) then
			for ent, _ in pairs( self.PrevSelection ) do
				if ( not IsValid( ent ) ) then continue end
				self:Select( ent )
			end
			return true
		end
		
		-- Make sure the entity is valid before trying to select it 
		if ( not IsValid( ent ) ) then return false end
		
		-- Deselect entity if already selected
		if ( self:IsSelected( ent ) ) then self:Deselect( ent ) return true end

		-- Otherwise add to selection
		self:Select( ent )

		return true

	end

	-------------------------------------------
	-- Right click ( finalize )
	function TOOL:RightClick( tr )

		
		local ply = self:GetOwner()
		local ent = tr.Entity
		
		-- Filter out bad entities
		if ( ent:IsPlayer() ) then return false end
		
		-- Shift + RMB -> Area select entities within a user's specified radius
		if ( ply:KeyDown( IN_USE ) or ply:KeyDown( IN_SPEED ) ) then
			local radius = math.Clamp( self:GetClientNumber( "radius" ), 64, 4096 )

			for _, ent in pairs( ents.FindInSphere( tr.HitPos, radius ) ) do
				if ( not IsValid( ent ) or not IsPropOwner( ply, ent ) ) then continue end
				self:Select( ent )
			end

			return true
		end
		
		-- Get the number of selected entities to send to the client
		local numSelected = table.Count( self.Selection )
		
		if ( IsValid( ent ) ) then
			-- If the entity is valid, make sure the player owns it before using it as the base
			if ( not IsPropOwner( ply, ent ) ) then
				return false
			end
		else
			-- Entity was invalid and the player didn't select anything, so return false
			if ( numSelected == 0 ) then
				return false
			end
			
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

		net.Start( MODE )
			-- Base entity
			net.WriteEntity( ent )

			-- Entity list
			if ( numSelected >= 1 ) then
				-- Send the number of entities to read, minus 1 to account for the base
				net.WriteUInt( numSelected - 1, ENT_ID_BITS )
				
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

elseif ( CLIENT ) then
	
	-------------------------------------------
	-- Client
    local net = net
	local file = file
	local draw = draw
	local pairs = pairs
	local string = string
	local tobool = tobool
	local ipairs = ipairs
	local Entity = Entity
	local IsValid = IsValid
	local SetClipboardText = SetClipboardText
	
    language.Add( "Tool."..MODE..".name",        "E2 Hologram Converter" )
    language.Add( "Tool."..MODE..".desc",        "Converts props into holograms for use with Expression2." )
	language.Add( "tool."..MODE..".left",        "Select/Deselect an entity" )
	language.Add( "tool."..MODE..".right",       "Finalize selection" )
	language.Add( "tool."..MODE..".reload",      "Clear selection" )
	language.Add( "tool."..MODE..".shift_left",  "Restore previous selection" )
	language.Add( "tool."..MODE..".shift_right", "Area-select entities within a radius" )
	
    function TOOL:LeftClick()  return true end
    function TOOL:RightClick() return true end

    local PANEL_TEXT_COLOR = Color( 0, 0, 0 )
	local COLOR_DARK_GRAY  = Color( 50, 50, 50, 255 )
	local COLOR_MIDD_GRAY  = Color( 125, 125, 125, 255 )
	local COLOR_LITE_GRAY  = Color( 175, 175, 175, 255 )

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
        local cbox = vgui.Create( "DCheckBoxLabel" )

        cbox:SetText( "Copy to clipboard." )
        cbox:SetTextColor( PANEL_TEXT_COLOR )
        cbox:SetValue( 1 )
        cbox:SetConVar( MODE.."_clipboard" )
        container:AddItem( cbox )

        ------------------------------------
        -- Editor toggle
        local cbox = vgui.Create( "DCheckBoxLabel" )

        cbox:SetText( "Open in expression2 editor." )
        cbox:SetTextColor( PANEL_TEXT_COLOR )
        cbox:SetValue( 1 )
        cbox:SetConVar( MODE.."_openeditor" )
        container:AddItem( cbox )

        ------------------------------------
        -- VClip toggle
        local cbox = vgui.Create( "DCheckBoxLabel" )

        cbox:SetText( "Enable visclip support." )
        cbox:SetTextColor( PANEL_TEXT_COLOR )
        cbox:SetValue( 1 )
        cbox:SetConVar( MODE.."_vclips" )
        container:AddItem( cbox )

        ------------------------------------
        -- Set selection radius
        local ctrl = vgui.Create( "DNumSlider" )

        ctrl:SetText( "Selection radius." )
        ctrl.Label:SetTextColor( PANEL_TEXT_COLOR )
        ctrl:SetMin( 0 )
        ctrl:SetMax( 4096 )
        ctrl:SetDecimals( 0 )
        ctrl:SetConVar( MODE.."_radius" )
        container:AddItem( ctrl )
    end
	
	
	-- E2 script string literals
	local str_Holo = "    HN++,HT[HN,array] = array(%d,vec(%f,%f,%f),ang(%f,%f,%f),\"%s\",\"%s\",vec4(%d,%d,%d,%d))\n"

	local str_Header = [[
#[
    Important!!!!!!!!!

    Holograms are not magic, they are still entities and they still take server resources.
    You should consider them the same as you would any other prop.

    Ideally this tool is to be used for minor details, not entire contraptions.
]#

@name <NAME>
@inputs BaseProp:entity
@persist [ID SpawnStatus CoreStatus]:string [HT CT BG]:table [HN CN SpawnCounter ScaleFactor ToggleColMat ToggleShading] BaseParent:entity Rescale:vector

if ( dupefinished() | first() ) {

    #Settings
    ScaleFactor   = 1 #scales the contraption
    ToggleColMat  = 1 #disables materials and color
    ToggleShading = 0 #disables shading


    #Holo data
]]

    local str_Footer = [[


    #[
        HOLOGRAM LOADER - DO NOT EDIT BELOW THIS LINE

        IF YOU WISH TO EDIT HOLOGRAMS AFTER SPAWNING, PLACE CODE AFTER THE

        elseif ( CoreStatus == "InitPostSpawn" ) {

        CODEBLOCK AT THE BOTTOM
    ]#

    BaseParent = BaseProp ?: entity()
    Rescale = vec( ScaleFactor )

    function array:holo() {
        local Index = This[1, number]
        local Parent = Index != 1 ? holoEntity( 1 ) : BaseParent

        holoCreate( Index, Parent:toWorld( This[2, vector]*ScaleFactor ), Rescale, Parent:toWorld( This[3, angle] ), vec( 255 ), This[4, string] ?: "cube" )
        holoParent( Index, Parent )

        if ( ToggleColMat ) {
            holoMaterial( Index, This[5, string] )
            holoColor( Index, This[6, vector4] )
        }

        if ( ToggleShading ) { holoDisableShading( Index, 1 ) }
        if ( This[7, number] ) { holoSkin( Index, This[7, number] ) }
        if ( BG[Index, array] ) { foreach ( K, Group:vector2 = BG[Index, array] ) { holoBodygroup( Index, Group[1], Group[2] ) } }

        if ( CT[Index, table] ) {
            for ( I = 1, CT[Index, table]:count() ) {
                local Clip = CT[Index, table][I, array]
                holoClipEnabled( Index, Clip[1, number], 1 )
                holoClip( Index, Clip[1, number], Clip[2, vector]*ScaleFactor, Clip[3, vector], 0 )
                CN++
            }
        }
    }

    function loadContraption() {
        switch ( SpawnStatus ) {
            case "InitSpawn",
                if ( clk( "Start" ) ) {
                    SpawnStatus = "LoadHolograms"
                }
                soundPlay( "Blip", 0, "@^garrysmod/content_downloaded.wav", 0.212 )
            break

            case "LoadHolograms",
                while ( perf() & holoCanCreate() &  SpawnCounter < HN ) {
                    SpawnCounter++
                    HT[SpawnCounter, array]:holo()

                    if ( SpawnCounter >= HN ) {
                        SpawnStatus = "PrintStatus"
                        SpawnCounter = 0
                        break
                    }
                }
            break

            case "PrintStatus",
                printColor( vec( 125, 255, 125 ), "HoloCore: ", vec( 255, 255, 255 ), "Loaded " + HN + " holograms and " + CN + " clips." )

                CoreStatus = "InitPostSpawn"
                SpawnStatus = ""
            break
        }
    }

    runOnTick( 1 )
    timer( "Start", 500 )

    CoreStatus = "InitSpawn"
    SpawnStatus = "InitSpawn"

}

#----------------------
#-- Load the hologram and clip data arrays.
elseif ( CoreStatus == "InitSpawn" ) {
    loadContraption()
}


#----------------------
#-- This is like if ( first() ) { }, code here is run only once.
elseif ( CoreStatus == "InitPostSpawn" ) {
    CoreStatus = "RunThisCode"

    interval( 0 ) #start or stop clk

    runOnTick( 0 ) #start or stop tick
}


#----------------------
#-- This is where executing code goes
elseif ( CoreStatus == "RunThisCode" ) {
    if ( clk() ) {
        #interval( 15 )

    }

    if ( tickClk() ) {

    }
}
]]
	
	local cvarVisClips  = CreateClientConVar( MODE.."_vclips", "1", true, false )
	local cvarClipboard = GetConVar( MODE.."_clipboard" )
	local cvarEditor    = GetConVar( MODE.."_openeditor" )

	-------------------------------------------
	-- HOOK: Grab the cvars when they are fully initialized
	hook.Add( "InitPostEntity", "p2h_initialize_cvars", function()
		cvarClipboard = GetConVar( MODE.."_clipboard" )
		cvarEditor    = GetConVar( MODE.."_openeditor" )
	end )

	-------------------------------------------
	-- FUNC: Returns table of entity info
	-- ARGS: base entity, selection table
	local function SetupEntityInfo( base, ents )
		local ret = {}

		local doClips = cvarVisClips:GetBool()

		for k, ent in ipairs( ents ) do
			if ( not IsValid( ent ) ) then continue end
			if ( ent:IsPlayer() )     then continue end
			
			local entry = {
				lpos = base:WorldToLocal( ent:GetPos() ),
				lang = base:WorldToLocalAngles( ent:GetAngles() ),
				-- edit: default to an empty model if this entity doesn't have one
				model = (ent:GetModel() or ""):lower(),
				material = ent:GetMaterial():lower(),
				color = ent:GetColor(),
			}

			if ( k == 1 ) then entry.lang = ent:GetAngles() end
			
			-- bodygroup support
			-- edit: default to 0 if this entity doesn't support skins at all
			if ( (ent:GetSkin() or 0) > 0 ) then entry.skin = ent:GetSkin() end

			local bgroups = ent:GetBodyGroups() or {}
			if ( #bgroups > 1 ) then
				local groups = {}
				for j, bgroup in pairs( bgroups ) do
					if ( bgroup.num <= 1 ) then continue end
					if ( bgroup.num == 2 ) then
						if ( ent:GetBodygroup( bgroup.id ) == 1 ) then groups[#groups + 1] = { id = bgroup.id, state = 1 } end
					else
						for j = 2, bgroup.num do
							if ( ent:GetBodygroup( bgroup.id ) == j - 1 ) then groups[#groups + 1] = { id = bgroup.id, state = j - 1 } end
						end
					end
				end
				if ( #groups > 0 ) then entry.bodygroups = groups end
			end

			if ( not doClips or not ent.ClipData ) then ret[#ret + 1] = entry continue end

			-- visclip support ( requires wrex's workshop version )
			entry.clips = {}

			for _, clip in ipairs( ent.ClipData ) do
				entry.clips[#entry.clips + 1] = {
					ldir = clip[1]:Forward(),
					lpos = clip[1]:Forward()*clip[2],
				}
			end

			ret[#ret + 1] = entry
		end

		return ret
	end

	-------------------------------------------
	-- FUNC: Returns formatted e2 code
	-- ARGS: script name, entity info table
	local function FormatEntityInfo( name, info )
		local ret = str_Header:Replace( "<NAME>", name or "defaultname" )

		for i, entry in pairs( info ) do
			local line = str_Holo:format(
				i,
				entry.lpos.x, entry.lpos.y, entry.lpos.z,
				entry.lang.p, entry.lang.y, entry.lang.r,
				entry.model, entry.material,
				entry.color.r, entry.color.g, entry.color.b, entry.color.a
			)

			-- bodygroup support
			if ( entry.skin ) then line = line:Left( #line - 2 ) .. "," .. entry.skin .. ")" end

			if ( entry.bodygroups ) then
				line = line .. "\n    #Bodygroup data <" .. i .. ">\n    BG[" .. i .. ",array] = array("
				for bi, bgroup in ipairs( entry.bodygroups ) do
					line = line .. "\n        vec2(" .. bgroup.id .. "," .. bgroup.state .. ")" .. ( bi ~= #entry.bodygroups  and "," or "\n    )\n" )
				end
				if ( i ~= #info ) then line = line .. "\n    #Holo data\n" end
			end

			if ( not entry.clips ) then ret = ret .. line continue end

			-- visclip support ( requires wrex's workshop version )
			line = line .. "\n    #Clip data <" .. i .. ">\n    CT[" .. i .. ",table] = table("

			for ci, clip in ipairs( entry.clips ) do
				line = line .. string.format("\n        array(%d,vec(%f,%f,%f),vec(%f,%f,%f))" .. (ci ~= #entry.clips and "," or "\n    )\n"),
					ci,
					clip.lpos.x, clip.lpos.y, clip.lpos.z,
					clip.ldir.x, clip.ldir.y, clip.ldir.z
				)
			end

			if ( i ~= #info ) then line = line .. "\n    #Holo data\n" end
			ret = ret .. line
		end

		ret = ret .. str_Footer

		return ret
	end
	
	-------------------------------------------
	-- FUNC: Handles data recieved from server
	-- ARGS: script name, entity info table
	local function PostListGet( name, base, ents )
		local data = SetupEntityInfo( base, ents )
		local code = FormatEntityInfo( name, data )

		file.Write( "p2h_auto.txt", code )

		if ( cvarClipboard:GetBool() ) then
			SetClipboardText( code )
		end

		if ( not WireLib ) then return end
		if ( not cvarEditor:GetBool() ) then return end

		spawnmenu.ActivateTool( "wire_expression2" )

		openE2Editor()
		
		if ( wire_expression2_editor ) then
			wire_expression2_editor:NewTab()
			wire_expression2_editor:SetCode( code )
		end

	end
	
	-------------------------------------------
	-- FUNC: Recieves data from server
	local function GetListFromServer()
		local eid = net.ReadUInt( ENT_ID_BITS )
		local base = Entity( eid )

		if ( not IsValid( base ) ) then return end

		local ents = { base }
		local count = net.ReadUInt( ENT_ID_BITS )

		for i = 1, count do
			local ent = net.ReadEntity()

			if ( not IsValid( ent ) ) then continue end

			ents[#ents + 1] = ent
		end

		Derma_StringRequest(
			"Expression2 Script Name", "Please enter a name for your script!", "default_script_name",

			function ( text )
				PostListGet( text, base, ents )
			end,

			function () end
		)
	end
	net.Receive( MODE, GetListFromServer )
	
end