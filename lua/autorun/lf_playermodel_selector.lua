-- Enhanced PlayerModel Selector
-- Upgraded code by LibertyForce https://steamcommunity.com/id/libertyforce
-- Based on: https://github.com/garrynewman/garrysmod/blob/1a2c317eeeef691e923453018236cf9f66ee74b4/garrysmod/gamemodes/sandbox/gamemode/editor_player.lua


local flag = { FCVAR_REPLICATED }
if SERVER then flag = { FCVAR_ARCHIVE, FCVAR_REPLICATED } end
local convars = { }
convars["sv_playermodel_selector_force"]		= 1
convars["sv_playermodel_selector_gamemodes"]	= 1
convars["sv_playermodel_selector_instantly"]	= 1
convars["sv_playermodel_selector_flexes"]		= 0
convars["sv_playermodel_selector_limit"]		= 1
convars["sv_playermodel_selector_debug"]		= 0
for cvar, def in pairs( convars ) do
	CreateConVar( cvar,	def, flag )
end
flag = nil


if SERVER then


AddCSLuaFile()

--util.AddNetworkString("lf_playermodel_client_sync")
util.AddNetworkString("lf_playermodel_cvar_change")
util.AddNetworkString("lf_playermodel_blacklist")
util.AddNetworkString("lf_playermodel_voxlist")
util.AddNetworkString("lf_playermodel_update")

local SetMDL = FindMetaTable("Entity").SetModel

local addon_legs = false

local debugmode = GetConVar( "sv_playermodel_selector_debug" ):GetBool() or false
cvars.AddChangeCallback( "sv_playermodel_selector_debug", function() debugmode = GetConVar( "sv_playermodel_selector_debug" ):GetBool() end )


--local function client_sync( ply )
--	net.Start("lf_playermodel_client_sync")
--	net.WriteBool( addon_vox )
--	net.Send( ply )
--end
--hook.Add( "PlayerInitialSpawn", "lf_playermodel_client_sync_hook", client_sync )
--net.Receive("lf_playermodel_client_sync", function( len, ply ) client_sync( ply ) end )

net.Receive("lf_playermodel_cvar_change", function( len, ply )
	if !ply:IsAdmin() then return end

	local cvar = net.ReadString()
	if !convars[cvar] then ply:Kick("Illegal convar change") return end

	RunConsoleCommand( cvar, net.ReadString() )
end )


if !file.Exists( "lf_playermodel_selector", "DATA" ) then file.CreateDir( "lf_playermodel_selector" ) end
if file.Exists( "playermodel_selector_blacklist.txt", "DATA" ) then -- Migrate from old version
	if !file.Exists( "lf_playermodel_selector/sv_blacklist.txt", "DATA" ) then
		local content = file.Read( "playermodel_selector_blacklist.txt", "DATA" )
		file.Write( "lf_playermodel_selector/sv_blacklist.txt", content )
	end
	file.Delete( "playermodel_selector_blacklist.txt" )
end

local Blacklist = { }
if file.Exists( "lf_playermodel_selector/sv_blacklist.txt", "DATA" ) then
	local loaded = util.JSONToTable( file.Read( "lf_playermodel_selector/sv_blacklist.txt", "DATA" ) )
	if istable( loaded ) then
		for k, v in pairs( loaded ) do
			Blacklist[tostring(k)] = v
		end
		loaded = nil
	end
end

net.Receive("lf_playermodel_blacklist", function( len, ply )
	if ( !ply:IsAdmin() ) then return end

	local mode = net.ReadInt( 3 )
	if mode == 1 then
		local gamemode = net.ReadString()
		if gamemode != "sandbox" then
			Blacklist[gamemode] = true
			file.Write( "lf_playermodel_selector/sv_blacklist.txt", util.TableToJSON( Blacklist, true ) )
		end
	elseif mode == 2 then
		local tbl = net.ReadTable()
		if istable( tbl ) then
			for k, v in pairs( tbl ) do
				local name = tostring( v )
				Blacklist[name] = nil
			end
			file.Write( "lf_playermodel_selector/sv_blacklist.txt", util.TableToJSON( Blacklist, true ) )
		end
	end

	net.Start("lf_playermodel_blacklist")
	net.WriteTable( Blacklist )
	net.Send( ply )
end )

local VOXlist = { }

function lf_playermodel_selector_get_voxlist() -- global
	return VOXlist
end

local function InitVOX()
	if file.Exists( "lf_playermodel_selector/sv_voxlist.txt", "DATA" ) then
		local loaded = util.JSONToTable( file.Read( "lf_playermodel_selector/sv_voxlist.txt", "DATA" ) )
		if istable( loaded ) then
			for k, v in pairs( loaded ) do
				VOXlist[tostring(k)] = tostring(v)
			end
			loaded = nil
		end
	end
end

net.Receive("lf_playermodel_voxlist", function( len, ply )
	if ( !ply:IsAdmin() ) then return end
	if !TFAVOX_Models then return end

	local function tfa_reload()
		TFAVOX_Packs_Initialize()
		TFAVOX_PrecachePacks()
		for k, v in player.Iterator() do
			print("Resetting the VOX of " .. v:Nick() )
			if IsValid(v) then TFAVOX_Init(v,true,true) end
		end
	end

	local mode = net.ReadInt( 3 )
	if mode == 1 then
		local k = net.ReadString()
		local v = net.ReadString()
		VOXlist[k] = v
		file.Write( "lf_playermodel_selector/sv_voxlist.txt", util.TableToJSON( VOXlist, true ) )
		tfa_reload()
	elseif mode == 2 then
		local tbl = net.ReadTable()
		if istable( tbl ) then
			for k, v in pairs( tbl ) do
				local name = tostring( v )
				VOXlist[name] = nil
				if istable( TFAVOX_Models ) then TFAVOX_Models[name] = nil end
			end
			file.Write( "lf_playermodel_selector/sv_voxlist.txt", util.TableToJSON( VOXlist, true ) )
			tfa_reload()
		end
	end

	net.Start("lf_playermodel_voxlist")
	net.WriteTable( VOXlist )
	net.Send( ply )
end )


local plymeta = FindMetaTable( "Player" )
local CurrentPlySetModel

local function Allowed( ply )
	if GAMEMODE_NAME == "sandbox" or ( !Blacklist[GAMEMODE_NAME] and ( ply:IsAdmin() or GetConVar( "sv_playermodel_selector_gamemodes"):GetBool() ) ) then
		return true	else return false
	end
end


local function UpdatePlayerModel( ply )
	if Allowed( ply ) then

		ply.lf_playermodel_spawned = true

		if debugmode then print( "LF_PMS: Updating playermodel for: "..tostring( ply:GetName() ) ) end

		local mdlname = ply:GetInfo( "cl_playermodel" )
		local mdlpath = player_manager.TranslatePlayerModel( mdlname )

		if not onWhiteList(mdlpath) then
			return
		end

		SetMDL( ply, mdlpath )
		if debugmode then print( "LF_PMS: Set model to: "..tostring( mdlname ).." - "..tostring( mdlpath ) ) end

		local skin = ply:GetInfoNum( "cl_playerskin", 0 )
		ply:SetSkin( skin )
		if debugmode then print( "LF_PMS: Set model skin to no.: "..tostring( skin ) ) end

		local groups = ply:GetInfo( "cl_playerbodygroups" )
		if ( groups == nil ) then groups = "" end
		local groups = string.Explode( " ", groups )
		for k = 0, ply:GetNumBodyGroups() - 1 do
			local v = tonumber( groups[ k + 1 ] ) or 0
			ply:SetBodygroup( k, v )
			if debugmode then print( "LF_PMS: Set bodygroup no. "..tostring( k ).." to: "..tostring( v ) ) end
		end

		if GetConVar( "sv_playermodel_selector_flexes" ):GetBool() and tobool( ply:GetInfoNum( "cl_playermodel_selector_unlockflexes", 0 ) ) then
			local flexes = ply:GetInfo( "cl_playerflexes" )
			if ( flexes == nil ) or ( flexes == "0" ) then return end
			local flexes = string.Explode( " ", flexes )
			for k = 0, ply:GetFlexNum() - 1 do
				ply:SetFlexWeight( k, tonumber( flexes[ k + 1 ] ) or 0 )
			end
		end

		local pcol = ply:GetInfo( "cl_playercolor" )
		local wcol = ply:GetInfo( "cl_weaponcolor" )
		ply:SetPlayerColor( Vector( pcol ) )
		ply:SetWeaponColor( Vector( wcol ) )

		timer.Simple( 0.1, function() if ply.SetupHands and isfunction( ply.SetupHands ) then ply:SetupHands() end end )
		timer.Simple( 0.2, function()
			if ply:GetInfo( "cl_playerhands" ) != "" then mdlname = ply:GetInfo( "cl_playerhands" ) end
			local mdlhands = player_manager.TranslatePlayerHands( mdlname )

			local hands_ent = ply:GetHands()
			if hands_ent and mdlhands and istable( mdlhands ) then
				if hands_ent:GetModel() != mdlhands.model then
					if debugmode then print( "LF_PMS: SetupHands failed. Gamemode doesn't implement this function correctly. Trying workaround..." ) end
					if ( IsValid( hands_ent ) ) then
						hands_ent:SetModel( mdlhands.model )
						hands_ent:SetSkin( mdlhands.skin )
						hands_ent:SetBodyGroups( mdlhands.body )

						local skin = ply:GetInfoNum( "cl_playerhandsskin", 0 )
						hands_ent:SetSkin( skin )
						if debugmode then print( "LF_PMS: Set hands model skin to no.: "..tostring( skin ) ) end

						local groups = ply:GetInfo( "cl_playerhandsbodygroups" )
						if ( groups == nil ) then groups = "" end
						local groups = string.Explode( " ", groups )
						for k = 0, hands_ent:GetNumBodyGroups() - 1 do
							local v = tonumber( groups[ k + 1 ] ) or 0
							hands_ent:SetBodygroup( k, v )
							if debugmode then print( "LF_PMS: Set hands bodygroup no. "..tostring( k ).." to: "..tostring( v ) ) end
						end

						if debugmode then
							timer.Simple( 0.2, function()
								if hands_ent:GetModel() != mdlhands.model then
									print( "LF_PMS: Workaround failed. Unable to setup viewmodel hands. Please check for incompatible addons." )
								else
									print( "LF_PMS: Workaround successful. Hands set to: "..mdlhands.model )
								end
							end )
						end
					end
				else
					if debugmode then print( "LF_PMS: SetupHands successful. Hands set to: "..tostring( mdlhands.model ) ) end
				end
			else
				if debugmode then print( "LF_PMS: ERROR - SetupHands failed. player_manager.TranslatePlayerHands didn't return valid data. Please check for incompatible addons." ) end
			end
		end )

		if addon_legs then
			hook.Run( "SetModel", ply, mdlpath )
		end

	end
end

net.Receive("lf_playermodel_update", function( len, ply )
	if ply:IsValid() and ply:IsPlayer() and ( ply:IsAdmin() or GetConVar( "sv_playermodel_selector_instantly"):GetBool() ) then
		if game.SinglePlayer() or ply:IsAdmin() then
			UpdatePlayerModel( ply )
		else
			local limit = math.Clamp( GetConVar( "sv_playermodel_selector_limit"):GetInt(), 0, 900 )
			local ct = CurTime()
			local diff1 = ct - ( ply.lf_playermodel_lastcall or limit*(-1) )
			local diff2 = ct - ( ply.lf_playermodel_lastsuccess or limit*(-1) )
			if diff1 < 0.1 then
				ply:Kick( "Too many requests. Please check your script for infinite loops" )
				if debugmode then print ( "LF_PMS: Kicked "..tostring( ply:GetName() )..". Multiple calls for playermodel change in less than: "..tostring( diff1 ).." seconds" ) end
			elseif diff2 >= limit then
				ply.lf_playermodel_lastcall = ct
				ply.lf_playermodel_lastsuccess = ct
				UpdatePlayerModel( ply )
			else
				ply.lf_playermodel_lastcall = ct
				ply:ChatPrint( "Enhanced PlayerModel Selector: Too many requests. Please wait another "..tostring( limit - math.floor( diff2 ) ).." seconds before trying again." )
				if debugmode then print ( "LF_PMS: Prevented "..tostring( ply:GetName() ).." from changing playermodel. Last try: "..tostring( math.floor( diff1 ) ).." seconds ago." ) end
			end
		end
	end
end )

file.CreateDir("player_storage")

local savePath = "player_storage/blacklist.txt"
local modelWhitelist = {}

local function whitelistSave(text)
	file.Write(savePath, text)
end

local function whitelistLoad()
	if ( !file.Exists(savePath, "DATA") ) then
		file.Write(savePath, "")
	end

	local lines = string.Explode("\n", file.Read(savePath, "DATA")) or ""
	if ( lines == "" ) then return end

	for _, line in ipairs(lines) do
        local model = string.Trim(line)
        if model != "" then
            if file.Exists(model, "GAME") and !onWhitelist(model) then
                modelWhitelist[model] = true
            end
        end
    end
end

local function onWhiteList(model)
	return modelWhitelist[model] or false
end

local function setDefaultModel(ply)
	for model, _ in pairs(modelWhitelist) do
		ply:SetModel(firstModel)
		break
	end
end

whitelistLoad()

hook.Add( "PlayerSpawn", "lf_playermodel_force_hook1", function( ply )
	if GetConVar( "sv_playermodel_selector_force" ):GetBool() and tobool( ply:GetInfoNum( "cl_playermodel_selector_force", 0 ) ) then
		--UpdatePlayerModel( ply )
		ply.lf_playermodel_spawned = nil
	end

	local plyM = ply:GetModel()
	if !onWhiteList(plyM) then
		//if firstModel then -- What even is this
			setDefaultModel(ply)
		//end
	end
end )

hook.Add( "PlayerSetHandsModel", "lf_fe_hands_select2", function( ply, ent )
	if ply:GetInfo( "cl_playerhands" ) and ply:GetInfo( "cl_playerhands" ) != "" then
		local info = player_manager.TranslatePlayerHands( ply:GetInfo( "cl_playerhands" ) )

		if ( info ) then
			timer.Simple( 0, function()
				if IsValid(ent) then
					ent:SetModel( info.model )
					ent:SetSkin( info.skin )
					ent:SetBodyGroups( info.body )

					local skin = ply:GetInfoNum( "cl_playerhandsskin", 0 )
					ent:SetSkin( skin )

					local groups = ply:GetInfo( "cl_playerhandsbodygroups" )
					if ( groups == nil ) then groups = "" end
					local groups = string.Explode( " ", groups )
					for k = 0, ent:GetNumBodyGroups() - 1 do
						local v = tonumber( groups[ k + 1 ] ) or 0
						ent:SetBodygroup( k, v )
					end

				end
			end)
		end
	end
end )

local function ForceSetModel( ply, mdl )
	if GetConVar( "sv_playermodel_selector_force" ):GetBool() and Allowed( ply ) and tobool( ply:GetInfoNum( "cl_playermodel_selector_force", 0 ) ) then
		if !ply.lf_playermodel_spawned then
			if debugmode then print( "LF_PMS: Detected initial call for SetModel on: "..tostring( ply:GetName() ) ) end
			UpdatePlayerModel( ply )
		else
			if debugmode then print( "LF_PMS: Enforcer prevented "..tostring( ply:GetName() ).."'s model from being changed to: "..tostring( mdl ) ) end
		end
	elseif mdl then
		CurrentPlySetModel( ply, mdl )
		if addon_legs then hook.Run( "SetModel" , ply, mdl ) end
	end
end

local function ToggleForce()
	if plymeta.SetModel and plymeta.SetModel ~= ForceSetModel then
		CurrentPlySetModel = plymeta.SetModel
	else
		CurrentPlySetModel = SetMDL
	end

	if GetConVar( "sv_playermodel_selector_force" ):GetBool() then
		plymeta.SetModel = ForceSetModel
	else
		plymeta.SetModel = CurrentPlySetModel
	end
end
cvars.AddChangeCallback( "sv_playermodel_selector_force", ToggleForce )

hook.Add( "Initialize", "lf_playermodel_force_hook2", function( ply )
	if file.Exists( "autorun/sh_legs.lua", "LUA" ) then addon_legs = true end
	--if file.Exists( "autorun/tfa_vox_loader.lua", "LUA" ) then addon_vox = true end
	if TFAVOX_Models then InitVOX() end

	local try = 0

	ToggleForce()

	timer.Create( "lf_playermodel_force_timer", 5, 0, function()
		if plymeta.SetModel == ForceSetModel or not GetConVar( "sv_playermodel_selector_force" ):GetBool() then
			timer.Remove( "lf_playermodel_force_timer" )
		else
			ToggleForce()
			try = try + 1
			print( "LF_PMS: Addon conflict detected. Unable to initialize enforcer to protect playermodel. [Attempt: " .. tostring( try ) .. "/10]" )
			if try >= 10 then
				timer.Remove( "lf_playermodel_force_timer" )
			end
		end
	end )
end )


end

-----------------------------------------------------------------------------------------------------------------------------------------------------

if CLIENT then



local Version = "3.3, Fesiug's Edit"
local Menu = { }
local Frame
local default_animations = { "idle_all_01", "menu_walk", "menu_combine", "pose_standing_02", "pose_standing_03", "idle_fist", "menu_gman", "idle_all_scared", "menu_zombie_01", "idle_magic", "walk_ar2" }
local currentanim = 0
local Favorites = { }
--local addon_vox = false

if !file.Exists( "lf_playermodel_selector", "DATA" ) then file.CreateDir( "lf_playermodel_selector" ) end
if file.Exists( "playermodel_selector_favorites.txt", "DATA" ) then -- Migrate from old version
	if !file.Exists( "lf_playermodel_selector/cl_favorites.txt", "DATA" ) then
		local content = file.Read( "playermodel_selector_favorites.txt", "DATA" )
		file.Write( "lf_playermodel_selector/cl_favorites.txt", content )
	end
	file.Delete( "playermodel_selector_favorites.txt" )
end

if file.Exists( "lf_playermodel_selector/cl_favorites.txt", "DATA" ) then
	local loaded = util.JSONToTable( file.Read( "lf_playermodel_selector/cl_favorites.txt", "DATA" ) )
	if istable( loaded ) then
		for k, v in pairs( loaded ) do
			Favorites[tostring(k)] = v
		end
		loaded = nil
	end
end

local function RRRotateAroundPoint(pos, ang, point, offset_ang)
    local mat = Matrix()
    mat:SetTranslation(pos)
    mat:SetAngles(ang)
    mat:Translate(point)

    local rot_mat = Matrix()
    rot_mat:SetAngles(offset_ang)
    rot_mat:Invert()

    mat:Mul(rot_mat)

    mat:Translate(-point)

    return mat:GetTranslation(), mat:GetAngles()
end


CreateClientConVar( "cl_playermodel_selector_force", "1", true, true )
CreateClientConVar( "cl_playermodel_selector_unlockflexes", "0", false, true )
CreateClientConVar( "cl_playermodel_selector_bgcolor_custom", "1", true, true )
CreateClientConVar( "cl_playermodel_selector_bgcolor_trans", "1", true, true )
CreateClientConVar( "cl_playermodel_selector_ignorehands", "1", true, true )

--net.Start("lf_playermodel_client_sync")
--net.SendToServer()
--net.Receive("lf_playermodel_client_sync", function()
--	addon_vox = net.ReadBool()
--end )

hook.Add( "PostGamemodeLoaded", "lf_playermodel_sboxcvars", function()
	CreateConVar( "cl_playercolor", "0.24 0.34 0.41", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The value is a Vector - so between 0-1 - not between 0-255" )
	CreateConVar( "cl_weaponcolor", "0.30 1.80 2.10", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The value is a Vector - so between 0-1 - not between 0-255" )
	CreateConVar( "cl_playerskin", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The skin to use, if the model has any" )
	CreateConVar( "cl_playerbodygroups", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The bodygroups to use, if the model has any" )
	CreateConVar( "cl_playerflexes", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The flexes to use, if the model has any" )
	CreateConVar( "cl_playerhands", "", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The hands to use, if the model has any" )
	CreateConVar( "cl_playerhandsbodygroups", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The bodygroups on the hands to use, if the model has any" )
	CreateConVar( "cl_playerhandsskin", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The skin on the hands to use, if the model has any" )
end )


local function KeyboardOn( pnl )
	if ( IsValid( Frame ) and IsValid( pnl ) and pnl:HasParent( Frame ) ) then
		Frame:SetKeyboardInputEnabled( true )
	end
end
hook.Add( "OnTextEntryGetFocus", "lf_playermodel_keyboard_on", KeyboardOn )
local function KeyboardOff( pnl )
	if ( IsValid( Frame ) and IsValid( pnl ) and pnl:HasParent( Frame ) ) then
		Frame:SetKeyboardInputEnabled( false )
	end
end
hook.Add( "OnTextEntryLoseFocus", "lf_playermodel_keyboard_off", KeyboardOff )


local function LoadPlayerModel()
	if LocalPlayer():IsAdmin() or GetConVar( "sv_playermodel_selector_instantly" ):GetBool() then
		net.Start("lf_playermodel_update")
		net.SendToServer()
	end
end
concommand.Add( "playermodel_apply", LoadPlayerModel )

local function LoadFavorite( ply, cmd, args )
	local name = tostring( args[1] )
	if istable( Favorites[name] ) then
		RunConsoleCommand( "cl_playermodel", Favorites[name].model )
		RunConsoleCommand( "cl_playerbodygroups", Favorites[name].bodygroups )
		RunConsoleCommand( "cl_playerskin", Favorites[name].skin )
		timer.Simple( 0.1, LoadPlayerModel )
	else
		print( "Favorite not found. Remember: The name is case-sensitive and should be put in quotation marks." )
	end
end
concommand.Add( "playermodel_loadfav", LoadFavorite )


-- Horrible. I hate Garry's Mod
local HandIconGenerator = GetRenderTarget("HandIconGenerator", 512, 512)
local myMat2 = CreateMaterial( "HandIconGenerator_RTMat", "UnlitGeneric", {
	["$basetexture"] = HandIconGenerator:GetName(), -- Make the material use our render target texture
	["$translucent"] = 1,
	["$vertexcolor"] = 1,
	["$vertexalpha"] = 1,
} )
local matshiny = Material("models/shiny")
local hasbgs = Material("eps/hasbgs4.png", "mips smooth") -- or hasbgs3   idk which better

function Menu.UpdateFromConvars()
	-- wah wah dont error ples
end

function Menu.Setup()
	populateWhiteList()
	Frame = vgui.Create( "DFrame" )
	local fw, fh = math.min( ScrW() - 16, 960 ), math.min( ScrH() - 16, 700 )
	Frame:SetSize( fw, fh )
	Frame:SetTitle( "Enhanced PlayerModel Selector "..Version )
	Frame:SetVisible( true )
	Frame:SetDraggable( true )
	Frame:SetScreenLock( false )
	Frame:ShowCloseButton( true )
	Frame:Center()
	Frame:MakePopup()
	Frame:SetKeyboardInputEnabled( false )
	local r, g, b = 97, 100, 102
	if GetConVar( "cl_playermodel_selector_bgcolor_custom" ):GetBool() then
		local bgcolor = string.Explode( " ", GetConVar( "cl_playercolor" ):GetString() )
		bgcolor[1] = tonumber( bgcolor[1] )
		bgcolor[2] = tonumber( bgcolor[2] )
		bgcolor[3] = tonumber( bgcolor[3] )
		if isnumber( bgcolor[1] ) and isnumber( bgcolor[2] ) and isnumber( bgcolor[3] ) then
			r, g, b = math.Round( bgcolor[1] * 255 ), math.Round( bgcolor[2] * 255 ), math.Round( bgcolor[3] * 255 )
		else
			timer.Simple( 0.1, function() RunConsoleCommand( "cl_playercolor", "0.24 0.34 0.41" ) end )
		end
	end
	local a = GetConVar( "cl_playermodel_selector_bgcolor_trans" ):GetBool() == true and 127 or 255
	Frame.Paint = function( self, w, h )
		draw.RoundedBox( 10, 0, 0, w, h, Color( r, g, b, a ) ) return true
	end

	Frame.lblTitle:SetTextColor( Color( 0, 0, 0, 255 ) )
	Frame.lblTitle.Paint = function ( self, w, h )
		draw.SimpleTextOutlined( Frame.lblTitle:GetText(), "DermaDefaultBold", 1, 2, Color( 255, 255, 255, 255), 0, 0, 1, Color( 0, 0, 0, 255) ) return true
	end

	Frame.btnMinim:SetEnabled( true )
	Frame.btnMinim.DoClick = function()
		Frame:SetVisible( false )
	end
	--Frame.btnMaxim.Paint = function( panel, w, h ) derma.SkinHook( "Paint", "WindowMinimizeButton", panel, w, h ) end
	local maxi_allowed = false
	local maxi_mode = 0
	if ScrW() > fw and ScrH() > fh then maxi_allowed = true end
	Frame.btnMaxim:SetEnabled( maxi_allowed )
	Frame.btnMaxim.DoClick = function()
		if maxi_allowed and maxi_mode == 0 then
			Frame:SetSize( ScrW(), ScrH() )
			Frame:Center()
			Frame:SetDraggable( false )
			Menu.ApplyButton:SetPos( ScrW() - 560, 30 )
			Menu.ResetButton:SetPos( 5, ScrH() - 25 )
			Menu.AdvButton:SetPos( ScrW() - 200, 3 )
			maxi_mode = 1
		elseif maxi_allowed and maxi_mode == 1 then
			Menu.ApplyButton:SetVisible( false )
			Menu.ResetButton:SetVisible( false )
			Menu.AdvButton:SetVisible( false )
			Menu.Right:SetVisible( false )
			Frame:InvalidateLayout( false )
			maxi_mode = 2
		else
			Frame:SetSize( fw, fh )
			Frame:Center()
			Frame:SetDraggable( true )
			Menu.ApplyButton:SetPos( fw - 560, 30 )
			Menu.ApplyButton:SetVisible( true )
			Menu.ResetButton:SetPos( 5, fh - 25 )
			Menu.ResetButton:SetVisible( true )
			Menu.AdvButton:SetPos( fw - 200, 3 )
			Menu.AdvButton:SetVisible( true )
			Menu.Right:SetVisible( true )
			maxi_mode = 0
		end
	end

	local mdl = Frame:Add( "DModelPanel" )
	mdl:Dock( FILL )
	--mdl:SetSize( 520, 0 )
	mdl:SetFOV( 36 )
	mdl:SetCamPos( Vector( 0, 0, 0 ) )
	mdl:SetDirectionalLight( BOX_RIGHT, Color( 255, 160, 80, 255 ) )
	mdl:SetDirectionalLight( BOX_LEFT, Color( 80, 160, 255, 255 ) )
	mdl:SetAmbientLight( Vector( -64, -64, -64 ) )
	mdl:SetAnimated( true )
	mdl:SetLookAt( Vector( -100, 0, -22 ) )
	function mdl.DefaultPos()
		if ( Menu.IsHandsTabActive() ) then return end

		mdl.Angles = Angle( 0, 0, 0 )
		mdl.Pos = Vector( -100, 0, -61 )
		mdl.AngleOffset = Angle( 0, 0, 0 )
	end
	mdl.DefaultPos()

	function mdl:PreDrawModel( mdlEnt )
		if ( IsValid( self.EntityHands ) and Menu.IsHandsTabActive() ) then
			if ( not self.EntityHands:IsEffectActive( EF_BONEMERGE ) ) then
				self.EntityHands:AddEffects( EF_BONEMERGE )
				self.EntityHands:AddEffects( EF_BONEMERGE_FASTCULL )
			end

			self.EntityHands:DrawModel()

			return false
		end
	end

	Menu.AdvButton = Frame:Add( "DButton" )
	Menu.AdvButton:SetSize( 100, 18 )
	Menu.AdvButton:SetPos( fw - 200, 3 )
	Menu.AdvButton:SetText( "Visit Addon Page" )
	Menu.AdvButton.DoClick = function()
		gui.OpenURL( "https://steamcommunity.com/sharedfiles/filedetails/?id=2257795841" )
		SetClipboardText( "https://steamcommunity.com/sharedfiles/filedetails/?id=2257795841" )
	end

	Menu.ApplyButton = Frame:Add( "DButton" )
	Menu.ApplyButton:SetSize( 120, 30 )
	Menu.ApplyButton:SetPos( fw - 560, 30 )
	Menu.ApplyButton:SetText( "Apply playermodel" )
	Menu.ApplyButton:SetEnabled( LocalPlayer():IsAdmin() or GetConVar( "sv_playermodel_selector_instantly" ):GetBool() )
	Menu.ApplyButton.DoClick = LoadPlayerModel

	Menu.ResetButton = Frame:Add( "DButton" )
	Menu.ResetButton:SetSize( 40, 20 )
	Menu.ResetButton:SetPos( 5, fh - 25 )
	Menu.ResetButton:SetText( "Reset" )
	Menu.ResetButton.DoClick = mdl.DefaultPos

	Menu.ResetButton = Frame:Add( "DButton" )
	Menu.ResetButton:SetSize( 60, 20 )
	Menu.ResetButton:SetPos( 55, fh - 25 )
	Menu.ResetButton:SetText( "Next anim" )
	Menu.ResetButton.DoClick = function()
		currentanim = (currentanim + 1) % (#default_animations)
		Menu.PlayPreviewAnimation( mdl, LocalPlayer():GetInfo( "cl_playermodel" ) )
	end

	Menu.Right = Frame:Add( "DPropertySheet" )
	Menu.Right:Dock( RIGHT )
	Menu.Right:SetSize( 430, 0 )

	Menu.Right.OnActiveTabChanged = function( self, oldTab, newTab )
		timer.Simple( 0.1, function() Menu.UpdateFromConvars() end )
	end

		local modeltab = Menu.Right:Add( "DPropertySheet" )
		Menu.Right:AddSheet( "Model", modeltab, "icon16/user.png" )

			local t = modeltab:Add( "DLabel" )
			t:SetPos( 129, 1 )
			--t:SetSize( 100, 20 )
			t:SetText( "Search:" )

			Menu.ModelFilter = modeltab:Add( "DTextEntry" )
			Menu.ModelFilter:SetPos( 168, 1 )
			Menu.ModelFilter:SetSize( 246, 20 )
			Menu.ModelFilter:SetUpdateOnType( true )
			Menu.ModelFilter.OnValueChange = function() Menu.ModelPopulate() end

			local ModelScroll = modeltab:Add( "DScrollPanel" )
			modeltab:AddSheet( "Icons", ModelScroll, "icon16/application_view_tile.png" )
			ModelScroll:DockMargin( 2, 0, 2, 2 )
			ModelScroll:Dock( FILL )

			local ModelIconLayout = ModelScroll:Add( "DIconLayout" )
			ModelIconLayout:SetSpaceX( 2 )
			ModelIconLayout:SetSpaceY( 2 )
			ModelIconLayout:Dock( FILL )

			local modelicons = { }


			local ModelList = modeltab:Add( "DListView" )
			modeltab:AddSheet( "Table", ModelList, "icon16/application_view_list.png" )
			ModelList:DockMargin( 5, 0, 5, 5 )
			ModelList:Dock( FILL )
			ModelList:SetMultiSelect( false )
			ModelList:AddColumn( "Model" )
			ModelList:AddColumn( "Path" )
			ModelList.OnRowSelected = function()
				local sel = ModelList:GetSelected()
				if !sel[1] then return end
				local name = tostring( sel[1]:GetValue(1) )
				RunConsoleCommand( "cl_playermodel", name )
				RunConsoleCommand( "cl_playerbodygroups", "0" )
				RunConsoleCommand( "cl_playerskin", "0" )
				RunConsoleCommand( "cl_playerflexes", "0" )
				-- RunConsoleCommand( "cl_playerhands", "" )
				RunConsoleCommand( "cl_playerhandsbodygroups", "0" )
				RunConsoleCommand( "cl_playerhandsskin", "0" )
				timer.Simple( 0.3, function() Menu.UpdateFromConvars() end )
			end

			local AllModels = player_manager.AllValidModels()

			function Menu.ModelPopulate()

				ModelIconLayout:Clear()
				ModelList:Clear()

				local ModelFilter = Menu.ModelFilter:GetValue() or nil

				local function IsInFilter( name )
					if not ModelFilter or ModelFilter == "" then
						return true
					else
						local tbl = string.Split( ModelFilter, " " )
						for _, substr in pairs( tbl ) do
							if not string.match( name:lower(), string.PatternSafe( substr:lower() ) ) then
								return false
							end
						end
						return true
					end
				end

				for name, model in SortedPairs( AllModels ) do
					if ( !modelWhitelist[model] ) then continue end

					if IsInFilter( name ) then
						if GetConVar( "cl_playermodel_selector_ignorehands" ):GetBool() and player_manager.TranslatePlayerHands(name).model == model then continue end -- No

						local icon = ModelIconLayout:Add( "SpawnIcon" )
						icon:SetSize( 64, 64 )
						--icon:InvalidateLayout( true )
						icon:SetModel( model )
						icon:SetTooltip( name )
						table.insert( modelicons, icon )
						icon.DoClick = function()
							RunConsoleCommand( "cl_playermodel", name )
							RunConsoleCommand( "cl_playerbodygroups", "0" )
							RunConsoleCommand( "cl_playerskin", "0" )
							RunConsoleCommand( "cl_playerflexes", "0" )
							-- RunConsoleCommand( "cl_playerhands", "" )
							RunConsoleCommand( "cl_playerhandsbodygroups", "0" )
							RunConsoleCommand( "cl_playerhandsskin", "0" )
							timer.Simple( 0.3, function() Menu.UpdateFromConvars() end )
						end

						ModelList:AddLine( name, model )

					end

				end

			end

			Menu.ModelPopulate()

-------------------------------------------------------------
		local handtab = Menu.Right:Add( "DPropertySheet" )
		local htb = Menu.Right:AddSheet( "Hands", handtab, "icon16/attach.png" )

		htb.Tab.IsHandsTab = true

		local t = handtab:Add( "DLabel" )
			t:SetPos( 129, 1 )
			--t:SetSize( 100, 20 )
			t:SetText( "Search:" )

			Menu.HandsFilter = handtab:Add( "DTextEntry" )
			Menu.HandsFilter:SetPos( 168, 1 )
			Menu.HandsFilter:SetSize( 246, 20 )
			Menu.HandsFilter:SetUpdateOnType( true )
			Menu.HandsFilter.OnValueChange = function() Menu.HandsPopulate() end

			local ModelScroll = handtab:Add( "DScrollPanel" )
			handtab:AddSheet( "Icons", ModelScroll, "icon16/application_view_tile.png" )
			ModelScroll:DockMargin( 2, 0, 2, 2 )
			ModelScroll:Dock( FILL )

			local ModelIconLayout = ModelScroll:Add( "DIconLayout" )
			ModelIconLayout:SetSpaceX( 2 )
			ModelIconLayout:SetSpaceY( 2 )
			ModelIconLayout:Dock( FILL )

			local modelicons_forhands = { }


			local ModelList = handtab:Add( "DListView" )
			handtab:AddSheet( "Table", ModelList, "icon16/application_view_list.png" )
			ModelList:DockMargin( 5, 0, 5, 5 )
			ModelList:Dock( FILL )
			ModelList:SetMultiSelect( false )
			ModelList:AddColumn( "Model" )
			ModelList:AddColumn( "Path" )
			ModelList.OnRowSelected = function()
				local sel = ModelList:GetSelected()
				if !sel[1] then return end
				local name = tostring( sel[1]:GetValue(1) )
				RunConsoleCommand( "cl_playerhands", name )
				RunConsoleCommand( "cl_playerhandsbodygroups", "0" )
				RunConsoleCommand( "cl_playerhandsskin", "0" )
				timer.Simple( 0.1, function() Menu.UpdateFromConvars() end )
			end

			local AllModels = player_manager.AllValidModels()
			--AllModels["AbsolutelyNone"] = ""
			--PrintTable(AllModels)

			function Menu.HandsPopulate()
				ModelIconLayout:Clear()
				ModelList:Clear()

				local ModelFilter = Menu.HandsFilter:GetValue() or nil

				local function IsInFilter( name )
					if not ModelFilter or ModelFilter == "" then
						return true
					else
						local tbl = string.Split( ModelFilter, " " )
						for _, substr in pairs( tbl ) do
							if not string.match( name:lower(), string.PatternSafe( substr:lower() ) ) then
								return false
							end
						end
						return true
					end
				end

				local icon = ModelIconLayout:Add( "SpawnIcon" )
				icon:SetSize( 64, 64 )
				icon:SetSpawnIcon( "icon64/playermodel.png" )
				--icon:SetModel( model )
				icon:SetTooltip( "Use playermodel" )
				icon.DoClick = function()
					RunConsoleCommand( "cl_playerhands", "" )
					RunConsoleCommand( "cl_playerhandsbodygroups", "0" )
					RunConsoleCommand( "cl_playerhandsskin", "0" )
					timer.Simple( 0.1, function() Menu.UpdateFromConvars() end )
				end

				ModelList:AddLine( name, model )

				local exister = {}

				for name, model in SortedPairs( AllModels ) do
					if IsInFilter( name ) then
						local result = player_manager.TranslatePlayerHands( name )
						if exister[result.model:lower()] then
							continue
						else
							exister[result.model:lower()] = true
						end
						local icon = ModelIconLayout:Add( "SpawnIcon" )
						icon:SetSize( 64, 64 )
						--icon:InvalidateLayout( true )
						icon:SetModel( "models/kleiner_animations.mdl" )
						icon:SetTooltip( name .. "\n" .. result.model )
						icon.ResultList = result

						function icon:Paint( w, h )
							return true
						end
						table.insert( modelicons_forhands, icon )

						function icon:MakeHandIcon()
							if !self.ResultList then print("EPS Hands: Result list missing.") return end

							local CL_FISTS		= ClientsideModel("models/weapons/c_arms.mdl")
							local CL_REALHANDS	= ClientsideModel( self.ResultList.model, RENDERGROUP_BOTH )

							CL_FISTS:SetNoDraw( true )
							CL_FISTS:SetPos( vector_origin )
							CL_FISTS:SetAngles( angle_zero )
							CL_REALHANDS:SetNoDraw( true )

							CL_FISTS:ResetSequence( CL_FISTS:LookupSequence( "fists_idle_01" ) )

							CL_REALHANDS:AddEffects( EF_BONEMERGE )
							CL_REALHANDS:SetBodyGroups(result.body)
							CL_REALHANDS:SetSkin(isnumber(result.skin) and result.skin or 0)

							CL_REALHANDS:SetParent( CL_FISTS )

							local cam_pos = Vector( 0, 0, 0 )
							local cam_ang = Angle( 6, -16.9, 0 )
							local cam_fov = 17

							render.PushRenderTarget( HandIconGenerator )
								render.OverrideDepthEnable( true, true )
								render.SetWriteDepthToDestAlpha( false )
								render.SuppressEngineLighting( true )

								local CL_SHIRT = {
									{
										type = MATERIAL_LIGHT_POINT,
										color = Vector( 1, 1, 1 )*1,
										pos = Vector( 0, -48, 32 ),
									},
									{
										type = MATERIAL_LIGHT_POINT,
										color = Vector( -1, -1, -1 )*1,
										pos = Vector( 0, 32, -64 ),
									},
								}

								render.SetLocalModelLights(CL_SHIRT)
								-- render.Clear(0, 0, 0, 0, true, true)
								render.Clear(0, 0, 0, 0)
								render.ClearDepth( true )
								render.OverrideAlphaWriteEnable( true, true )


									-- rendering twice to get good alpha
								render.SetBlend(1)
								render.SetColorModulation(1, 1, 1)
								render.MaterialOverride(matshiny)
								render.OverrideColorWriteEnable(true, false)

								cam.Start3D( cam_pos, cam_ang, cam_fov, 0, 0, 64, 64, 0.1, 1000 )
									CL_FISTS:SetupBones()
									CL_REALHANDS:SetupBones()
									CL_REALHANDS:DrawModel( STUDIO_TWOPASS )
								cam.End3D()

								render.OverrideColorWriteEnable(false, false)
								render.MaterialOverride()


								render.SetWriteDepthToDestAlpha( true )
								render.OverrideBlend( true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD )

								cam.Start3D( cam_pos, cam_ang, cam_fov, 0, 0, 64, 64, 0.1, 1000 )
									CL_FISTS:SetupBones()
									CL_REALHANDS:SetupBones()
									CL_REALHANDS:DrawModel( STUDIO_TWOPASS )
								cam.End3D()

								render.MaterialOverride()
								render.SetWriteDepthToDestAlpha( false )

								render.OverrideBlend( false )
								render.SuppressEngineLighting(false)

								if CL_REALHANDS:GetNumBodyGroups() > 1 then
									cam.Start2D()
										surface.SetDrawColor( 255, 255, 255, 255 )
										surface.SetMaterial(hasbgs)
										surface.DrawTexturedRect(0, 0, 64, 64)
									cam.End2D()
								end

								print( "Generating " .. result.model:StripExtension() )
								local data = render.Capture( {
									format = "png",
									x = 0,
									y = 0,
									w = 64,
									h = 64
								} )

								if !file.Exists("eps_hands", "DATA") then
									file.CreateDir("eps_hands")
								end

								local EXPLOSION = string.Explode( "/", result.model:StripExtension(), false )
								EXPLOSION[#EXPLOSION] = nil
								EXPLOSION = table.concat( EXPLOSION, "/" )
								file.CreateDir( "eps_hands/" .. EXPLOSION )
								local fullpath = "eps_hands/" .. result.model:StripExtension() .. ".png"
								file.Write( fullpath, data )

								render.OverrideAlphaWriteEnable( false )
								render.SuppressEngineLighting( false )
								render.OverrideDepthEnable( false )
							render.PopRenderTarget()
							--icon:SetModel("models/kleiner_animations.mdl")
							icon:SetIcon( "data/eps_hands/" .. result.model:StripExtension() .. ".png" )
							--icon:SetTooltip( name .. "\n" .. result.model )

							--local tab = {}
							--tab.ent		= CL_REALHANDS
							--tab.cam_pos = Vector( 0, 0, 0 )
							--tab.cam_ang = Angle( 4, -18, 0 )
							--tab.cam_fov = 20

							--self:RebuildSpawnIconEx( tab )

							CL_FISTS:Remove()
							CL_REALHANDS:Remove()
						end

						-- Make a pretty ass icon
						if !file.Exists( "eps_hands/" .. result.model:StripExtension() .. ".png", "DATA" ) then
							print("IT DOESN'T EXIST", "eps_hands/" .. result.model:StripExtension() .. ".png")
							if IsValid(icon) then

								icon:MakeHandIcon()
							end
						else
							--icon:SetModel("models/kleiner_animations.mdl")
							icon:SetIcon( "data/eps_hands/" .. result.model:StripExtension() .. ".png" )
							--icon:SetTooltip( name .. "\n" .. result.model )
						end

						icon.DoClick = function()
							RunConsoleCommand( "cl_playerhands", name )
							RunConsoleCommand( "cl_playerhandsbodygroups", "0" )
							RunConsoleCommand( "cl_playerhandsskin", "0" )
							timer.Simple( 0.1, function() Menu.UpdateFromConvars() end )
						end

						icon.DoRightClick = function()
							if IsValid(icon) then
								icon:MakeHandIcon()
							end
						end

						ModelList:AddLine( name, model )
					end
				end

				--local thelabel = ModelIconLayout:Add( "DLabel" )
				--thelabel:SetText("")
				--function thelabel:Paint( w, h )
				--	local old = DisableClipping( true )
				--	local ox, oy = self:GetParent():LocalToScreen()

				--	local nx, ny = self:ScreenToLocal( ox, oy )
				--	ny = 0 + 64
				--	draw.SimpleText("Icons may not generate because of jank with spawnicon generation,", "DermaDefault", nx, ny + 0, color_black)
				--	draw.SimpleText("particularly when others are generating.", "DermaDefault", nx, ny + 12, color_black)
				--	draw.SimpleText("Press RIGHT-CLICK on an icon to regenerate it manually.", "DermaDefault", nx, ny + 24, color_black)
				--	DisableClipping( old )
				--end
			end

			Menu.HandsPopulate()
--------------------------------------------------------

		local favorites = Menu.Right:Add( "DPanel" )
		Menu.Right:AddSheet( "Favorites", favorites, "icon16/star.png" )
		favorites:DockPadding( 8, 8, 8, 8 )

		local FavList = favorites:Add( "DListView" )
		FavList:Dock( FILL )
		FavList:SetMultiSelect( true )
		FavList:AddColumn( "Favorites" )
		FavList:AddColumn( "Model" )
		FavList:AddColumn( "Skin" ):SetFixedWidth( 25 )
		FavList:AddColumn( "Bodygroups" )
		FavList.DoDoubleClick = function( id, sel )
			local name = tostring( FavList:GetLine( sel ):GetValue( 1 ) )
			if istable( Favorites[name] ) then
				RunConsoleCommand( "cl_playermodel", Favorites[name].model )
				RunConsoleCommand( "cl_playerbodygroups", Favorites[name].bodygroups )
				RunConsoleCommand( "cl_playerskin", Favorites[name].skin )
				timer.Simple( 0.1, function()
					Menu.UpdateFromConvars()
				end )
			end
		end

		function Menu.FavPopulate()
			FavList:Clear()
			for k, v in pairs( Favorites ) do
				FavList:AddLine( k, v.model, v.skin, v.bodygroups )
			end
			FavList:SortByColumn( 1 )
		end
		Menu.FavPopulate()

		local b = favorites:Add( "DButton" )
		b:Dock( TOP )
		b:SetHeight( 25 )
		b:DockMargin( 0, 0, 200, 10 )
		b:SetText( "Load selected Favorite" )
		b.DoClick = function()
			local sel = FavList:GetSelected()
			if !sel[1] then return end
			local name = tostring( sel[1]:GetValue(1) )
			if istable( Favorites[name] ) then
				RunConsoleCommand( "cl_playermodel", Favorites[name].model )
				RunConsoleCommand( "cl_playerbodygroups", Favorites[name].bodygroups )
				RunConsoleCommand( "cl_playerskin", Favorites[name].skin )
				timer.Simple( 0.3, function()
					Menu.UpdateFromConvars()
				end )
			end
		end

		local t = favorites:Add( "DLabel" )
		t:Dock( BOTTOM )
		t:SetAutoStretchVertical( true )
		t:SetText( "Here you can save your favorite playermodel combinations. To do this:\n1. Select a model and setup the skin and bodygroups as you wish.\n2. Enter a unique name into the textfield and click \"Add new favorite\".\n3. Load your favorite by selecting it in the list below and clicking \"Load selected\".\nYou can also apply existing favorites by console command:\nplayermodel_loadfav \"the favorite's name\"" )
		t:SetDark( true )
		t:SetWrap( true )

		local control = favorites:Add( "DPanel" )
		control:Dock( BOTTOM )
		control:DockMargin( 0, 10, 0, 0 )
		control:SetSize( 0, 60 )
		control:SetPaintBackground( false )

		function Menu.FavAdd( name )
			Favorites[name] = { }
			Favorites[name].model = LocalPlayer():GetInfo( "cl_playermodel" )
			Favorites[name].skin = LocalPlayer():GetInfoNum( "cl_playerskin", 0 )
			Favorites[name].bodygroups = LocalPlayer():GetInfo( "cl_playerbodygroups" )
			file.Write( "lf_playermodel_selector/cl_favorites.txt", util.TableToJSON( Favorites, true ) )
			Menu.FavPopulate()
		end

		local FavEntry = control:Add( "DTextEntry" )
		FavEntry:SetPos( 0, 0 )
		FavEntry:SetSize( 395, 20 )

		local b = control:Add( "DButton" )
		b:SetPos( 0, 30 )
		b:SetSize( 125, 20 )
		b:SetText( "Add new favorite" )
		b.DoClick = function()
			local name = FavEntry:GetValue()
			if name == "" then return end
			Menu.FavAdd( name )
		end

		local b = control:Add( "DButton" )
		b:SetPos( 135, 30 )
		b:SetSize( 125, 20 )
		b:SetText( "Replace selected" )
		b.DoClick = function()
			local sel = FavList:GetSelected()
			if sel[2] then return end
			if !sel[1] then return end
			local name = tostring( sel[1]:GetValue(1) )
			Menu.FavAdd( name )
		end

		local b = control:Add( "DButton" )
		b:SetPos( 270, 30 )
		b:SetSize( 125, 20 )
		b:SetText( "Delete all selected" )
		b.DoClick = function()
			local sel = FavList:GetSelected()
			for k, v in pairs( sel ) do
				local name = tostring( v:GetValue(1) )
				Favorites[name] = nil
			end
			file.Write( "lf_playermodel_selector/cl_favorites.txt", util.TableToJSON( Favorites, true ) )
			Menu.FavPopulate()
		end


		local bdcontrols = Menu.Right:Add( "DPanel" )
		local bgtab = Menu.Right:AddSheet( "Bodygroups", bdcontrols, "icon16/group.png" )
		bdcontrols:DockPadding( 8, 8, 8, 8 )

		local bdcontrolspanel = bdcontrols:Add( "DPanelList" )
		bdcontrolspanel:EnableVerticalScrollbar( true )
		bdcontrolspanel:Dock( FILL )

		-- Hands
		local h__bdcontrols = Menu.Right:Add( "DPanel" )
		local h__bgtab = Menu.Right:AddSheet( "Handgroups", h__bdcontrols, "icon16/group_link.png" )
		h__bdcontrols:DockPadding( 8, 8, 8, 8 )

		h__bgtab.Tab.IsHandsTab = true

		local h__bdcontrolspanel = h__bdcontrols:Add( "DPanelList" )
		h__bdcontrolspanel:EnableVerticalScrollbar( true )
		h__bdcontrolspanel:Dock( FILL )


		local flexcontrols = Menu.Right:Add( "DPanel" )
		local flextab = Menu.Right:AddSheet( "Flexes", flexcontrols, "icon16/emoticon_wink.png" )
		flexcontrols:DockPadding( 8, 8, 8, 8 )

		local flexcontrolspanel = flexcontrols:Add( "DPanelList" )
		flexcontrolspanel:EnableVerticalScrollbar( true )
		flexcontrolspanel:Dock( FILL )


		local controls = Menu.Right:Add( "DPanel" )
		Menu.Right:AddSheet( "Colors", controls, "icon16/color_wheel.png" )
		controls:DockPadding( 8, 8, 8, 8 )

		local lbl = controls:Add( "DLabel" )
		lbl:SetText( "Player color" )
		lbl:SetTextColor( Color( 0, 0, 0, 255 ) )
		lbl:Dock( TOP )

		local plycol = controls:Add( "DColorMixer" )
		plycol:SetAlphaBar( false )
		plycol:SetPalette( false )
		plycol:Dock( TOP )
		plycol:SetSize( 200, ( fh - 160) / 2 )

		local lbl = controls:Add( "DLabel" )
		lbl:SetText( "Physgun color" )
		lbl:SetTextColor( Color( 0, 0, 0, 255 ) )
		lbl:DockMargin( 0, 8, 0, 0 )
		lbl:Dock( TOP )

		local wepcol = controls:Add( "DColorMixer" )
		wepcol:SetAlphaBar( false )
		wepcol:SetPalette( false )
		wepcol:Dock( TOP )
		wepcol:SetSize( 200, ( fh - 160) / 2 )
		wepcol:SetVector( Vector( GetConVar( "cl_weaponcolor" ):GetString() ) )

		local b = controls:Add( "DButton" )
		b:DockMargin( 0, 8, 0, 0 )
		b:Dock( TOP )
		b:SetSize( 150, 20 )
		b:SetText( "Reset to default values" )
		b.DoClick = function()
			plycol:SetVector( Vector( 0.24, 0.34, 0.41 ) )
			wepcol:SetVector( Vector( 0.30, 1.80, 2.10 ) )
			RunConsoleCommand( "cl_playercolor", "0.24 0.34 0.41" )
			RunConsoleCommand( "cl_weaponcolor", "0.30 1.80 2.10" )
		end


		local moretab = Menu.Right:Add( "DPropertySheet" )
		Menu.Right:AddSheet( "Settings", moretab, "icon16/key.png" )


			local panel = moretab:Add( "DPanel" )
			moretab:AddSheet( "Client", panel, "icon16/status_online.png" )
			panel:DockPadding( 10, 10, 10, 10 )

			local panel = panel:Add( "DScrollPanel" )
			panel:Dock( FILL )

			local c = panel:Add( "DCheckBoxLabel" )
			c.cvar = "cl_playermodel_selector_force"
			c:Dock( TOP )
			c:DockMargin( 0, 0, 0, 5 )
			c:SetValue( GetConVar(c.cvar):GetBool() )
			c:SetText( "Enforce your playermodel" )
			c:SetDark( true )
			c.OnChange = function( p, v )
				RunConsoleCommand( c.cvar, v == true and "1" or "0" )
			end

			local t = panel:Add( "DLabel" )
			t:Dock( TOP )
			t:DockMargin( 0, 0, 0, 20 )
			t:SetAutoStretchVertical( true )
			t:SetText( "If enabled, your selected playermodel will be protected. No other function will be able to change your playermodel anymore." )
			t:SetDark( true )
			t:SetWrap( true )

			local c = panel:Add( "DCheckBoxLabel" )
			c.cvar = "cl_playermodel_selector_bgcolor_custom"
			c:Dock( TOP )
			c:DockMargin( 0, 0, 0, 5 )
			c:SetValue( GetConVar(c.cvar):GetBool() )
			c:SetText( "Use Player color as background" )
			c:SetDark( true )
			c:SizeToContents()
			c.OnChange = function( p, v )
				RunConsoleCommand( c.cvar, v == true and "1" or "0" )
			end

			local t = panel:Add( "DLabel" )
			t:Dock( TOP )
			t:DockMargin( 0, 0, 0, 20 )
			t:SetAutoStretchVertical( true )
			t:SetText( "If enabled, your selected player color will be used as the menu background. If disabled, the background will be grey." )
			t:SetDark( true )
			t:SetWrap( true )

			local c = panel:Add( "DCheckBoxLabel" )
			c.cvar = "cl_playermodel_selector_bgcolor_trans"
			c:Dock( TOP )
			c:DockMargin( 0, 0, 0, 5 )
			c:SetValue( GetConVar(c.cvar):GetBool() )
			c:SetText( "Transparent background" )
			c:SetDark( true )
			c:SizeToContents()
			c.OnChange = function( p, v )
				RunConsoleCommand( c.cvar, v == true and "1" or "0" )
			end

			local t = panel:Add( "DLabel" )
			t:Dock( TOP )
			t:DockMargin( 0, 0, 0, 20 )
			t:SetAutoStretchVertical( true )
			t:SetText( "If enabled, the menu backgroup will be transparent. If disabled, the background will be opaque." )
			t:SetDark( true )
			t:SetWrap( true )

			local c = panel:Add( "DCheckBoxLabel" )
			c.cvar = "cl_playermodel_selector_ignorehands"
			c:Dock( TOP )
			c:DockMargin( 0, 0, 0, 5 )
			c:SetValue( GetConVar(c.cvar):GetBool() )
			c:SetText( "Ignore c_hands only \"playermodels\" in main list" )
			c:SetDark( true )
			c:SizeToContents()
			c.OnChange = function( p, v )
				RunConsoleCommand( c.cvar, v == true and "1" or "0" )
				Menu.ModelPopulate()
			end

			local t = panel:Add( "DLabel" )
			t:Dock( TOP )
			t:DockMargin( 0, 0, 0, 20 )
			t:SetAutoStretchVertical( true )
			t:SetText( "If enabled, \"playermodels\" that are nothing but floating pair of hands will be not shown in list of available playermodels. Disable to see all registered playermodels." )
			t:SetDark( true )
			t:SetWrap( true )

			local c = panel:Add( "DCheckBoxLabel" )
			c.cvar = "cl_playermodel_selector_unlockflexes"
			c:Dock( TOP )
			c:DockMargin( 0, 0, 0, 5 )
			c:SetValue( GetConVar(c.cvar):GetBool() )
			c:SetText( "Show flexes tab" )
			c:SetDark( true )
			c:SizeToContents()
			c.OnChange = function( p, v )
				RunConsoleCommand( c.cvar, v == true and "1" or "0" )
				timer.Simple( 0, function() Menu.RebuildBodygroupTab() end )
			end

			local t = panel:Add( "DLabel" )
			t:Dock( TOP )
			t:DockMargin( 0, 0, 0, 20 )
			t:SetAutoStretchVertical( true )
			t:SetText( "This allows you to manipulate flexes on your playermodel. However, flex manipulation is not really made for playermodels and will cause issues. This includes the following:\n- Eye blinking no longer working.\n- Faces might be distorted unless the flexes are corrected manually.\n- Might break the faces of incompatible playermodels completely.\n- Even if you put all flexes to default value, the engine still considers them as manipulated. Models with problems won't be fixed.\nYou must switch your model once, for the tab to appear!" )
			t:SetDark( true )
			t:SetWrap( true )

			local b = panel:Add( "DButton" )
			b:Dock( TOP )
			b:DockMargin( 0, 0, 270, 5 )
			b:SetHeight( 15 )
			b:SetText( "Rebuild spawn icons" )
			b.DoClick = function()
				for _, icon in pairs( modelicons ) do
					icon:RebuildSpawnIcon()
				end

				-- local thecount = 0
				for _, icon in pairs( modelicons_forhands ) do
					if IsValid(icon) then
						icon:MakeHandIcon()
					end
				end
			end

			local t = panel:Add( "DLabel" )
			t:Dock( TOP )
			t:DockMargin( 0, 0, 0, 20 )
			t:SetAutoStretchVertical( true )
			t:SetText( "Forces all playermodel icons to be re-rendered. Useful if the icons are outdated after custom models changed their appearance. This may take a while, depending on the number of models and your PC's speed.\nThis also regenerates the hand's icons." )
			t:SetDark( true )
			t:SetWrap( true )


			if LocalPlayer():IsAdmin() then

				local panel = moretab:Add( "DPanel" )
				moretab:AddSheet( "Server", panel, "icon16/world.png" )
				panel:DockPadding( 10, 10, 10, 10 )

				local panel = panel:Add( "DScrollPanel" )
				panel:Dock( FILL )

				local function ChangeCVar( p, v )
					net.Start("lf_playermodel_cvar_change")
					net.WriteString( p.cvar )
					net.WriteString( v == true and "1" or "0" )
					net.SendToServer()
				end

				local c = panel:Add( "DCheckBoxLabel" )
				c.cvar = "sv_playermodel_selector_force"
				c:Dock( TOP )
				c:DockMargin( 0, 0, 0, 5 )
				c:SetValue( GetConVar(c.cvar):GetBool() )
				c:SetText( "Enable playermodel enforcement" )
				c:SetDark( true )
				c.OnChange = ChangeCVar

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "If enabled, selected playermodels will be enforced and protected. No gamemodes, maps or addons can overwrite them anymore. Players can toggle this function individually, using the checkbox on top of the menu.\nIf disabled, only the manual button works outside of Sandbox." )
				t:SetDark( true )
				t:SetWrap( true )

				local c = panel:Add( "DCheckBoxLabel" )
				c.cvar = "sv_playermodel_selector_instantly"
				c:Dock( TOP )
				c:DockMargin( 0, 0, 0, 5 )
				c:SetValue( GetConVar(c.cvar):GetBool() )
				c:SetText( "Allow instant changes" )
				c:SetDark( true )
				c.OnChange = ChangeCVar

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "If enabled, players can apply their changes instantly instead of having to respawn." )
				t:SetDark( true )
				t:SetWrap( true )

				local c = panel:Add( "DCheckBoxLabel" )
				c.cvar = "sv_playermodel_selector_flexes"
				c:Dock( TOP )
				c:DockMargin( 0, 0, 0, 5 )
				c:SetValue( GetConVar(c.cvar):GetBool() )
				c:SetText( "Allow players to change flexes" )
				c:SetDark( true )
				c.OnChange = ChangeCVar

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "If enabled, players can change the flexes for their playermodels. This will break player blinking and may cause other issues. Enable at own risk. Players can only reset their flexes by disconnecting." )
				t:SetDark( true )
				t:SetWrap( true )

				local c = panel:Add( "DCheckBoxLabel" )
				c.cvar = "sv_playermodel_selector_gamemodes"
				c:Dock( TOP )
				c:DockMargin( 0, 0, 0, 5 )
				c:SetValue( GetConVar(c.cvar):GetBool() )
				c:SetText( "Enable in all gamemodes" )
				c:SetDark( true )
				c.OnChange = ChangeCVar

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "If enabled, the PlayerModel Selector will be available for all players in every gamemode. If disabled, only Admins can use it outside of Sandbox." )
				t:SetDark( true )
				t:SetWrap( true )

				local s = panel:Add( "DNumSlider" )
				s.cvar = "sv_playermodel_selector_limit"
				s:Dock( TOP )
				s:DockMargin( 0, 0, 0, 5 )
				s:SetText( "Request limit" )
				s:SetDark( true )
				s:SetDecimals( 0 )
				s:SetMax( 900 )
				s:SetValue( GetConVar( "sv_playermodel_selector_limit" ):GetInt() )
				s.OnValueChanged = function( val )
					net.Start("lf_playermodel_cvar_change")
					net.WriteString( s.cvar )
					net.WriteString( tostring( math.floor( val:GetValue(1) ) ) )
					net.SendToServer()
				end

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "Timelimit in seconds that players have to wait, before they can use the instant change function again. Set to 0 to disable." )
				t:SetDark( true )
				t:SetWrap( true )

				local TextEntry = panel:Add("DTextEntry")
				local tempText = file.Read(savePath, "DATA") or ""

				local function GetLineCount(text)
					if text == "" then return 0 end
					return #string.Explode("\n", text)
				end

				if tempText ~= "" then
					TextEntry:SetValue(tempText)
					local text = TextEntry:GetValue()
					TextEntry:SetHeight( 20*GetLineCount(tempText) )
					--print(GetLineCount(tempText))
				else
					TextEntry:SetHeight( 20 )
				end
				TextEntry:Dock( TOP )
				TextEntry:DockMargin( 0, 0, 0, 10 )
				TextEntry:SetMultiline(true)

				TextEntry.OnChange = function(self)
					local text = self:GetValue()
					TextEntry:SetHeight( 20*GetLineCount(text) )
					whitelistSave(text)
				end

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "List of whitelisted models." )
				t:SetDark( true )
				t:SetWrap( true )

				local panel = moretab:Add( "DPanel" )
				moretab:AddSheet( "GM Blacklist", panel, "icon16/delete.png" )
				panel:DockPadding( 10, 10, 10, 10 )

				local Blacklist = panel:Add( "DListView" )
				Blacklist:Dock( LEFT )
				Blacklist:DockMargin( 0, 0, 20, 0 )
				Blacklist:SetWidth( 150 )
				Blacklist:SetMultiSelect( true )
				Blacklist:AddColumn( "Blacklisted gamemodes" )

				net.Receive("lf_playermodel_blacklist", function()
					local tbl = net.ReadTable()
					Blacklist:Clear()
					for k, v in pairs( tbl ) do
						Blacklist:AddLine( k )
					end
					Blacklist:SortByColumn( 1 )
				end )

				function Menu.BlacklistPopulate()
					net.Start( "lf_playermodel_blacklist" )
					net.WriteInt( 0, 3 )
					net.SendToServer()
				end
				Menu.BlacklistPopulate()

				local t = panel:Add( "DLabel" )
				t:Dock( TOP )
				t:DockMargin( 0, 0, 0, 20 )
				t:SetAutoStretchVertical( true )
				t:SetText( "Here you can blacklist incompatible gamemodes.\n\nPlayers (including Admins) can't change their playermodels in those gamemodes, regardless of other settings." )
				t:SetDark( true )
				t:SetWrap( true )

				local b = panel:Add( "DButton" )
				b:Dock( TOP )
				b:DockMargin( 0, 0, 0, 20 )
				b:SetHeight( 25 )
				b:SetText( "Add current gamemode to Blacklist" )
				b.DoClick = function()
					if GAMEMODE_NAME == "sandbox" then return end
					net.Start( "lf_playermodel_blacklist" )
					net.WriteInt( 1, 3 )
					net.WriteString( GAMEMODE_NAME )
					net.SendToServer()
				end

				local TextEntry = panel:Add( "DTextEntry" )
				TextEntry:Dock( TOP )
				TextEntry:DockMargin( 0, 0, 0, 10 )
				TextEntry:SetHeight( 20 )

				local b = panel:Add( "DButton" )
				b:Dock( TOP )
				b:DockMargin( 0, 0, 0, 20 )
				b:SetHeight( 20 )
				b:SetText( "Manually add gamemode" )
				b.DoClick = function()
					local name = TextEntry:GetValue()
					if name == "" or name == "sandbox" then return end
					net.Start( "lf_playermodel_blacklist" )
					net.WriteInt( 1, 3 )
					net.WriteString( name )
					net.SendToServer()
				end

				local b = panel:Add( "DButton" )
				b:Dock( TOP )
				b:DockMargin( 0, 0, 0, 0 )
				b:SetHeight( 25 )
				b:SetText( "Remove selected gamemodes" )
				b.DoClick = function()
					local tbl = { }
					local sel = Blacklist:GetSelected()
					for k, v in pairs( sel ) do
						local name = tostring( v:GetValue(1) )
						table.insert( tbl, name )
					end
					net.Start( "lf_playermodel_blacklist" )
					net.WriteInt( 2, 3 )
					net.WriteTable( tbl )
					net.SendToServer()
				end


				if TFAVOX_Models then

					local panel = moretab:Add( "DPanel" )
					moretab:AddSheet( "VOX", panel, "icon16/sound.png" )
					panel:DockPadding( 10, 10, 10, 10 )

					local VOXlist = panel:Add( "DListView" )
					VOXlist:Dock( TOP )
					VOXlist:DockMargin( 0, 0, 0, 10 )
					VOXlist:SetHeight( ( fh - 126 - 44 ) / 2 ) -- 260
					VOXlist:SetMultiSelect( true )
					VOXlist:AddColumn( "PlayerModel" )
					VOXlist:AddColumn( "assigned VOX pack" )

					net.Receive("lf_playermodel_voxlist", function()
						local tbl = net.ReadTable()
						VOXlist:Clear()
						for k, v in pairs( tbl ) do
							VOXlist:AddLine( string.StripExtension( string.gsub( k, "models/", "", 1 ) ), string.StripExtension( string.gsub( v, "models/", "", 1 ) ) )
						end
						VOXlist:SortByColumn( 1 )
					end )

					function Menu.VOXlistPopulate()
						net.Start( "lf_playermodel_voxlist" )
						net.WriteInt( 0, 3 )
						net.SendToServer()
					end
					Menu.VOXlistPopulate()

					local control = panel:Add( "DPanel" )
					control:Dock( TOP )
					control:DockMargin( 0, 0, 0, 0 )
					--control:SetSize( 0, 60 )
					control:SetPaintBackground( false )

					local VOXinstalled = panel:Add( "DListView" )
					VOXinstalled:Dock( TOP )
					VOXinstalled:DockMargin( 0, 10, 0, 0 )
					VOXinstalled:SetHeight( ( fh - 126 - 44 ) / 2 )
					VOXinstalled:SetMultiSelect( false )
					VOXinstalled:AddColumn( "Available VOX packs" )

					if istable( TFAVOX_Models ) then
						for k, v in pairs( TFAVOX_Models ) do
							VOXinstalled:AddLine( string.StripExtension( string.gsub( k, "models/", "", 1 ) ) )
						end
						VOXinstalled:SortByColumn( 1 )
					end

					local b = control:Add( "DButton" )
					b:Dock( LEFT )
					--b:DockPadding( 100, 0, 100, 0 )
					b:SetWidth( 200 )
					b:SetText( "Assign VOX pack to current PlayerModel" )
					b.DoClick = function()
						local sel = VOXinstalled:GetSelected()
						if !sel[1] then return end
						local v = "models/"..tostring( sel[1]:GetValue(1)..".mdl" )
						local k = string.lower( player_manager.TranslatePlayerModel( LocalPlayer():GetInfo( "cl_playermodel" ) ) )
						net.Start( "lf_playermodel_voxlist" )
						net.WriteInt( 1, 3 )
						net.WriteString( k )
						net.WriteString( v )
						net.SendToServer()
					end

					local b = control:Add( "DButton" )
					b:Dock( RIGHT )
					--b:DockPadding( 100, 0, 100, 0 )
					b:SetWidth( 170 )
					b:SetText( "Remove selected assignment" )
					b.DoClick = function()
						local tbl = { }
						local sel = VOXlist:GetSelected()
						for k, v in pairs( sel ) do
							local name = "models/"..tostring( v:GetValue(1)..".mdl" )
							table.insert( tbl, name )
						end
						net.Start( "lf_playermodel_voxlist" )
						net.WriteInt( 2, 3 )
						net.WriteTable( tbl )
						net.SendToServer()
					end

				end

			end


			local panel = moretab:Add( "DPanel" )
			moretab:AddSheet( "Info", panel, "icon16/information.png" )
			panel:DockPadding( 0, 0, 0, 0 )

			local t = panel:Add( "DHTML" )
			t:Dock( FILL )
			--t:DockMargin( 0, 0, 0, 15 )
			--t:SetHeight( 260 )
			t:SetAllowLua( true )
			t:AddFunction( "url", "open", function( str ) gui.OpenURL( str ) end )
			t:AddFunction( "url", "copy", function( str ) SetClipboardText( str ) end )

			local intro = [[]]

			t:SetHTML( [[
				<html>
					<head>
						<style type="text/css">
							body {
								background-color: #1b2838;
								font-family: Arial, Helvetica, Verdana, sans-serif;
								font-size: 14px;
								color: #acb2b8;
							}
							h1, h2, h3 {
								font-size: 15px;
								color: #5aa9d6;
								font-weight: bold;
								margin: 0;
								padding: 0px 0px 4px 0px;
							}
							h3, h4, h5, h6 {
								margin: 0;
								padding: 2px 0px 6px 0px;
							}
							h1 {
								font-size: 20px;
							}
							a {
								text-decoration: none;
								color: #ffffff;
							}
							a:hover {
								color:#66C0F4;
							}
							table {
								border: 1px solid #4d4d4d;
								border-spacing: 0px;
								padding: 4px;
							}
							table th {
								border: 1px solid #4d4d4d;
								padding: 4px;
								margin: 0px;
							}
							table td {
								border: 1px solid #4d4d4d;
								padding: 4px;
								margin: 0px;
							}
						</style>
					</head>
					<body>
						<h1><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=504945881' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=504945881' )">Enhanced PlayerModel Selector</a></h1>
						<h3>originally created by <a href="javascript:url.open( 'https://steamcommunity.com/id/libertyforce' )" oncontextmenu="url.copy( 'https://steamcommunity.com/id/libertyforce' )">LibertyForce</a></h3>
						<hr>
						<h1><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=2257795841' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=2257795841' )">Enhanced PlayerModel Selector Fesiug's Edit</a></h1>
						<h3>a fork by <a href="javascript:url.open( 'https://steamcommunity.com/id/Fesiug/' )" oncontextmenu="url.copy( 'https://steamcommunity.com/id/Fesiug/' )">Fesiug</a></h3>
						<h4><i>and with contributions from</i></h4>
						<h3><a href="javascript:url.open( 'https://steamcommunity.com/id/yurannnzzz' )" oncontextmenu="url.copy( 'https://steamcommunity.com/id/yurannnzzz' )">YuRaNnNzZZ</a></h3>
						<li>for the hands preview</li>
						<h3><a href="javascript:url.open( 'https://steamcommunity.com/id/dar-su' )" oncontextmenu="url.copy( 'https://steamcommunity.com/id/dar-su' )">Darsu</a></h3>
						<li>for the hands preview animation</li>
						<hr>
						<h2>Compatible Addons</h1>
						<p>Enhanced Playermodel Selector provides additional functionality with those addons installed:
						<ul>
							<li><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=112806637' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=112806637' )">Gmod Legs 3</a></li>
							<li><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=742906087' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=742906087' )">TFA-VOX || Player Callouts Redefined</a></li>
						</ul></p>
						<h2>More addons</h2>
						<p><ul>
							<li><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=624173012' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=624173012' )">Simple Addon Manager</a><br>
							<small>Tired of the slow and annoying addon manager included in Gmod? Here comes and easy to use and efficient alternative that allows you to handle even large addon collections.<br>
							+ Toggle multiple addons at once<br>+ Add tags to your addons<br>+ Cleanup your addons by uninstalling them at once</small><br>&nbsp;</li>
							<li><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=492765756' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=492765756' )">Weapon: Setup, Transfer And Restore</a><br>
							<small>This addon provides an easy way to restore all your weapons and ammo after you die, without having to spawn them again.</small><br>&nbsp;</li>
							<li><a href="javascript:url.open( 'https://steamcommunity.com/sharedfiles/filedetails/?id=351603470' )" oncontextmenu="url.copy( 'https://steamcommunity.com/sharedfiles/filedetails/?id=351603470' )">Anti-FriendlyFire (NPC)</a><br>
							<small>If you where ever annoyed by your allies killing each other in friendly fire, which made large NPC battle pretty much useless, then you have just found the solution! This mod allows you to turn off Friendly Fire towards and between NPCs.</small></li>
						</ul></p>
						<h2 style="font-size: 10px">Left click: Open in Steam Overlay.<br>Right click: Copy URL to clipboard for use in browser.</h2>
					</body>
				</html>
			]] )




	-- Helper functions

	function Menu.MakeNiceName( str )
		local newname = {}
		if string.find(str, ".smd") then str = string.sub(str, 0, -5) end

		for _, s in pairs( string.Explode( "_", str ) ) do
			if ( string.len( s ) == 1 ) then table.insert( newname, string.upper( s ) ) continue end
			table.insert( newname, string.upper( string.Left( s, 1 ) ) .. string.Right( s, string.len( s ) - 1 ) ) -- Ugly way to capitalize first letters.
		end

		return string.Implode( " ", newname )
	end

	function Menu.PlayHandsPreviewAnimation( panel, playermodel )
		local iSeq = panel.EntityHandsAnim:LookupSequence( "idle" )

		if ( iSeq > 0 ) then panel.EntityHandsAnim:ResetSequence( iSeq ) end
	end

	function Menu.PlayPreviewAnimation( panel, playermodel )

		if ( !panel or !IsValid( panel.Entity ) ) then return end

		-- local anims = list.Get( "PlayerOptionsAnimations" )

		local anim = default_animations[ currentanim+1 ]
		-- if ( anims[ playermodel ] ) then
		-- 	anims = anims[ playermodel ]
		-- 	anim = anims[ math.random( 1, #anims ) ]
		-- end

		local iSeq = panel.Entity:LookupSequence( anim )
		if ( iSeq > 0 ) then panel.Entity:ResetSequence( iSeq ) end

	end

	-- Updating

	function Menu.UpdateBodyGroups( pnl, val )
		local handsTabActive = Menu.IsHandsTabActive()

		if ( pnl.type == "bgroup" ) then

			if ( not handsTabActive ) then mdl.Entity:SetBodygroup( pnl.typenum, math.Round( val ) ) end

			local str = string.Explode( " ", GetConVar( "cl_playerbodygroups" ):GetString() )
			if ( #str < pnl.typenum + 1 ) then for i = 1, pnl.typenum + 1 do str[ i ] = str[ i ] or 0 end end
			str[ pnl.typenum + 1 ] = math.Round( val )
			RunConsoleCommand( "cl_playerbodygroups", table.concat( str, " " ) )

		elseif ( pnl.type == "flex" ) then

			if ( not handsTabActive ) then mdl.Entity:SetFlexWeight( pnl.typenum, math.Round( val, 2 ) ) end

			local str = string.Explode( " ", GetConVar( "cl_playerflexes" ):GetString() )
			if ( #str < pnl.typenum + 1 ) then for i = 1, pnl.typenum + 1 do str[ i ] = str[ i ] or 0 end end
			str[ pnl.typenum + 1 ] = math.Round( val, 2 )
			RunConsoleCommand( "cl_playerflexes", table.concat( str, " " ) )

		elseif ( pnl.type == "skin" ) then

			if ( not handsTabActive ) then mdl.Entity:SetSkin( math.Round( val ) ) end
			RunConsoleCommand( "cl_playerskin", math.Round( val ) )

		elseif ( pnl.type == "h__bgroup" ) then

			if true or ( handsTabActive ) then mdl.EntityHands:SetBodygroup( pnl.typenum, math.Round( val ) ) end

			local str = string.Explode( " ", GetConVar( "cl_playerhandsbodygroups" ):GetString() )
			if ( #str < pnl.typenum + 1 ) then for i = 1, pnl.typenum + 1 do str[ i ] = str[ i ] or 0 end end
			str[ pnl.typenum + 1 ] = math.Round( val )
			RunConsoleCommand( "cl_playerhandsbodygroups", table.concat( str, " " ) )

		elseif ( pnl.type == "h__skin" ) then

			if true or ( handsTabActive ) then mdl.EntityHands:SetSkin( math.Round( val ) ) end
			RunConsoleCommand( "cl_playerhandsskin", math.Round( val ) )

		end
	end

	function Menu.RebuildBodygroupTab()
		bdcontrolspanel:Clear()
		h__bdcontrolspanel:Clear()
		flexcontrolspanel:Clear()

		bgtab.Tab:SetVisible( false )
		h__bgtab.Tab:SetVisible( false )
		flextab.Tab:SetVisible( false )

		local nskins = mdl.Entity:SkinCount() - 1
		if ( nskins > 0 ) then
			local skins = vgui.Create( "DNumSlider" )
			skins:Dock( TOP )
			skins:SetText( "Skin" )
			skins:SetDark( true )
			skins:SetTall( 50 )
			skins:SetDecimals( 0 )
			skins:SetMax( nskins )
			skins:SetValue( GetConVar( "cl_playerskin" ):GetInt() )
			skins.type = "skin"
			skins.OnValueChanged = Menu.UpdateBodyGroups

			bdcontrolspanel:AddItem( skins )

			mdl.Entity:SetSkin( GetConVar( "cl_playerskin" ):GetInt() )

			bgtab.Tab:SetVisible( true )
		end

		local groups = string.Explode( " ", GetConVar( "cl_playerbodygroups" ):GetString() )
		for k = 0, mdl.Entity:GetNumBodyGroups() - 1 do
			if ( mdl.Entity:GetBodygroupCount( k ) <= 1 ) then continue end

			local bgroup = vgui.Create( "DNumSlider" )
			bgroup:Dock( TOP )
			bgroup:SetText( Menu.MakeNiceName( mdl.Entity:GetBodygroupName( k ) ) )
			bgroup:SetDark( true )
			bgroup:SetTall( 50 )
			bgroup:SetDecimals( 0 )
			bgroup.type = "bgroup"
			bgroup.typenum = k
			bgroup:SetMax( mdl.Entity:GetBodygroupCount( k ) - 1 )
			bgroup:SetValue( groups[ k + 1 ] or 0 )
			-- bgroup.OnValueChanged = Menu.UpdateBodyGroups

			bdcontrolspanel:AddItem( bgroup )

			local tgroup
			local submdls = mdl.Entity:GetBodyGroups()[k+1].submodels
			if istable(submdls) then
				local mdl = submdls[tonumber(groups[ k + 1 ] or 0)] or "idk"
				tgroup = vgui.Create( "DLabel" )
				tgroup:Dock( TOP )
				tgroup:DockMargin(10, -15, 0, 0)
				tgroup:SetText( Menu.MakeNiceName( mdl ))

				bdcontrolspanel:AddItem( tgroup )
			end

			bgroup.OnValueChanged = function(something1, val)
				local submdls = mdl.Entity:GetBodyGroups()[k+1].submodels
				if istable(submdls) then
					tgroup:SetText(Menu.MakeNiceName(submdls[math.Round(val)]) or "idk")
				end

				Menu.UpdateBodyGroups(something1, val)
			end

			mdl.Entity:SetBodygroup( k, groups[ k + 1 ] or 0 )

			bgtab.Tab:SetVisible( true )
		end

		-- Hands
		if GetConVar( "cl_playerhands" ):GetString() and GetConVar( "cl_playerhands" ):GetString() != "" and ( IsValid( mdl.EntityHands ) ) then
			local nskins = mdl.EntityHands:SkinCount() - 1
			if ( nskins > 0 ) then
				local skins = vgui.Create( "DNumSlider" )
				skins:Dock( TOP )
				skins:SetText( "Skin" )
				skins:SetDark( true )
				skins:SetTall( 50 )
				skins:SetDecimals( 0 )
				skins:SetMax( nskins )
				skins:SetValue( GetConVar( "cl_playerhandsskin" ):GetInt() )
				skins.type = "h__skin"
				skins.OnValueChanged = Menu.UpdateBodyGroups

				h__bdcontrolspanel:AddItem( skins )

				mdl.EntityHands:SetSkin( GetConVar( "cl_playerhandsskin" ):GetInt() )

				h__bgtab.Tab:SetVisible( true )
			end

			local groups = string.Explode( " ", GetConVar( "cl_playerhandsbodygroups" ):GetString() )
			for k = 0, mdl.EntityHands:GetNumBodyGroups() - 1 do
				if ( mdl.EntityHands:GetBodygroupCount( k ) <= 1 ) then continue end

				local bgroup = vgui.Create( "DNumSlider" )
				bgroup:Dock( TOP )
				bgroup:SetText( Menu.MakeNiceName( mdl.EntityHands:GetBodygroupName( k ) ) )
				bgroup:SetDark( true )
				bgroup:SetTall( 50 )
				bgroup:SetDecimals( 0 )
				bgroup.type = "h__bgroup"
				bgroup.typenum = k
				bgroup:SetMax( mdl.EntityHands:GetBodygroupCount( k ) - 1 )
				bgroup:SetValue( groups[ k + 1 ] or 0 )
				bgroup.OnValueChanged = Menu.UpdateBodyGroups

				h__bdcontrolspanel:AddItem( bgroup )

				local tgroup
				local submdls = mdl.EntityHands:GetBodyGroups()[k+1].submodels
				if istable(submdls) then
					local mdl = submdls[tonumber(groups[ k + 1 ] or 0)] or "idk"
					tgroup = vgui.Create( "DLabel" )
					tgroup:Dock( TOP )
					tgroup:DockMargin(10, -15, 0, 0)
					tgroup:SetText( Menu.MakeNiceName( mdl ))

					h__bdcontrolspanel:AddItem( tgroup )
				end

				bgroup.OnValueChanged = function(something1, val)
					local submdls = mdl.EntityHands:GetBodyGroups()[k+1].submodels
					if istable(submdls) then
						tgroup:SetText(Menu.MakeNiceName(submdls[math.Round(val)]) or "idk")
					end

					Menu.UpdateBodyGroups(something1, val)
				end

				mdl.EntityHands:SetBodygroup( k, groups[ k + 1 ] or 0 )

				h__bgtab.Tab:SetVisible( true )
			end
		end
		-- Hands end

		if GetConVar( "sv_playermodel_selector_flexes" ):GetBool() and GetConVar( "cl_playermodel_selector_unlockflexes" ):GetBool() then
			local t = vgui.Create( "DLabel" )
			t:Dock( TOP )
			t:SetTall( 70 )
			t:SetText( "Notes:\n-The model preview for flexes doesn't work correctly. However, they will be visible on your playermodel when you apply them.\n- The default values provided might not be correct and cause distorted faces.\n- There is no way to reset (or fix) flex manipulation besides disconnecting." )
			t:SetDark( true )
			t:SetWrap( true )
			flexcontrolspanel:AddItem( t )

			local flexes = string.Explode( " ", GetConVar( "cl_playerflexes" ):GetString() )
			for k = 0, mdl.Entity:GetFlexNum() - 1 do
				if ( mdl.Entity:GetFlexNum( k ) <= 1 ) then continue end

				local flex = vgui.Create( "DNumSlider" )
				local vmin, vmax = mdl.Entity:GetFlexBounds( k )
				local default = 0
				if vmin == -1 and vmax == 1 then default = 0.5 end
				flex:Dock( TOP )
				flex:SetText( Menu.MakeNiceName( mdl.Entity:GetFlexName( k ) ) )
				flex:SetDark( true )
				flex:SetTall( 30 )
				flex:SetDecimals( 2 )
				flex.type = "flex"
				flex.typenum = k
				flex:SetMin( vmin )
				flex:SetMax( vmax )
				flex:SetValue( flexes[ k + 1 ] or default )
				flex.OnValueChanged = Menu.UpdateBodyGroups

				flexcontrolspanel:AddItem( flex )

				mdl.Entity:SetFlexWeight( k, flexes[ k + 1 ] or default )

				flextab.Tab:SetVisible( true )
			end
		end

		Menu.Right.tabScroller:InvalidateLayout( true )
		Menu.Right:InvalidateLayout( true )
	end

	local handsAnimModel = Model( "models/weapons/chand_checker.mdl" )

	function Menu.UpdateFromConvars()
		if ( IsValid( mdl.EntityHands ) ) then
			mdl.EntityHands:Remove()
		end
		if ( IsValid( mdl.EntityHandsAnim ) ) then
			mdl.EntityHandsAnim:Remove()
		end
		mdl.EntityHandsAnim = ClientsideModel( handsAnimModel, RENDERGROUP_OTHER )
		mdl.EntityHandsAnim:SetNoDraw( true )
		mdl.EntityHandsAnim:SetPos( Vector( 0, 0, 0 ) )

		if true or ( Menu.IsHandsTabActive() ) then
			mdl:SetModel( handsAnimModel )
			local model = LocalPlayer():GetInfo( "cl_playerhands" )

			if ( model == "" ) then
				model = LocalPlayer():GetInfo( "cl_playermodel" )
			end

			local mdlhands = player_manager.TranslatePlayerHands( model )

			util.PrecacheModel( mdlhands.model )

			mdl.EntityHands = ClientsideModel( mdlhands.model, RENDERGROUP_OTHER )
			mdl.EntityHands:SetParent( mdl.EntityHandsAnim )
			mdl.EntityHands:SetNoDraw( true )

			local dumbassproof = mdlhands.skin
			if !isnumber( dumbassproof ) then
				dumbassproof = 0
			end

			mdl.EntityHands:SetSkin( dumbassproof )
			mdl.EntityHands:SetBodyGroups( mdlhands.body )
			mdl.EntityHands.GetPlayerColor = function() return Vector( GetConVar( "cl_playercolor" ):GetString() ) end

			Menu.PlayHandsPreviewAnimation( mdl, model )
			--Menu.RebuildBodygroupTab()
			--return
		end

		if true then
			local model = LocalPlayer():GetInfo( "cl_playermodel" )
			local modelname = player_manager.TranslatePlayerModel( model )
			util.PrecacheModel( modelname )
			mdl:SetModel( modelname )
			mdl.Entity.GetPlayerColor = function() return Vector( GetConVar( "cl_playercolor" ):GetString() ) end
			mdl.Entity:SetPos( Vector( -100, 0, -61 ) )

			plycol:SetVector( Vector( GetConVar( "cl_playercolor" ):GetString() ) )
			wepcol:SetVector( Vector( GetConVar( "cl_weaponcolor" ):GetString() ) )

			Menu.PlayPreviewAnimation( mdl, model )
			Menu.RebuildBodygroupTab()
		end

	end

	function Menu.UpdateFromControls()

		RunConsoleCommand( "cl_playercolor", tostring( plycol:GetVector() ) )
		RunConsoleCommand( "cl_weaponcolor", tostring( wepcol:GetVector() ) )

	end

	plycol.ValueChanged = Menu.UpdateFromControls
	wepcol.ValueChanged = Menu.UpdateFromControls

	Menu.UpdateFromConvars()

	-- Hold to rotate

	function mdl:DragMousePress( button )
		self.PressX, self.PressY = gui.MousePos()
		self.Pressed = button
	end

	function mdl:OnMouseWheeled( delta )
		self.WheelD = delta * -5
		self.Wheeled = true
	end

	function mdl:DragMouseRelease() self.Pressed = false end

	function mdl:RunAnimation() -- override to restart hands animation
		if ( Menu.IsHandsTabActive() and self.Entity:GetCycle() > 0.99 ) then
			self.Entity:SetCycle( 0 )
		end

		self.Entity:FrameAdvance( ( RealTime() - self.LastPaint ) * self.m_fAnimSpeed )
	end

	local handsang = Angle( 0, 180, 0 )
	local handspos = Vector( -2, 0, -2 )

	function mdl:LayoutEntity( Entity )
		if ( self.bAnimated ) then self:RunAnimation() end

		if ( Menu.IsHandsTabActive() ) then
			self.WasHandsTab = true

			self:SetFOV( 45 )

			self.Angles = handsang
			self.Pos = handspos

			self.EntityHandsAnim:SetAngles( self.Angles )
			self.EntityHandsAnim:SetPos( self.Pos )

			self.EntityHandsAnim:SetCycle( math.Remap((CurTime()/8) % 1, 0, 1, 0.01, 0.99) )

			return
		elseif ( self.WasHandsTab ) then -- reset position on tab switch
			self.WasHandsTab = false

			self:SetFOV( 36 )

			self.Pos = Vector( -100, 0, -61 )
			self.Angles = Angle( 0, 0, 0 )
			self.AngleOffset = Angle( 0, 0, 0 )
		end

		if ( self.Pressed == MOUSE_LEFT ) then
			local mx, my = gui.MousePos()
			self.Angles = self.Angles - Angle( 0, ( self.PressX or mx ) - mx, 0 )

			self.PressX, self.PressY = gui.MousePos()
		end

		if ( self.Pressed == MOUSE_RIGHT ) then
			local mx, my = gui.MousePos()
			self.AngleOffset = Angle( ( self.PressY*(0.15) or my*(0.15) ) - my*(0.15), 0, ( self.PressX*(-0.15) or mx*(-0.15) ) - mx*(-0.15) )
			self.Pos, self.Angles = RRRotateAroundPoint(self.Pos, self.Angles, Vector(0, 0, self.Pos.z * -0.5), self.AngleOffset)

			self.PressX, self.PressY = gui.MousePos()
		end

		if ( self.Pressed == MOUSE_MIDDLE ) then
			local mx, my = gui.MousePos()
			self.Pos = self.Pos - Vector( 0, ( self.PressX*(0.15) or mx*(0.15) ) - mx*(0.15), ( self.PressY*(-0.15) or my*(-0.15) ) - my*(-0.15) )

			self.PressX, self.PressY = gui.MousePos()
		end

		if ( self.Wheeled ) then
			self.Wheeled = false
			self.Pos = self.Pos - Vector( self.WheelD, 0, 0 )
		end

		Entity:SetAngles( self.Angles )
		Entity:SetPos( self.Pos )
	end

end

function Menu.IsHandsTabActive()
	if not IsValid(Menu.Right) then return false end

	return Menu.Right:GetActiveTab().IsHandsTab
end

function Menu.Toggle()
	if LocalPlayer():IsAdmin() or GAMEMODE_NAME == "sandbox" or GetConVar( "sv_playermodel_selector_gamemodes" ):GetBool()
	then
		if IsValid( Frame ) then
			Frame:ToggleVisible()
		else
			Menu.Setup()
		end
	else
		if IsValid( Frame ) then Frame:Close() end
	end
end

concommand.Add( "playermodel_selector", Menu.Toggle )

hook.Add( "PostGamemodeLoaded", "lf_playermodel_desktop_hook", function()
		if GAMEMODE_NAME == "sandbox" then
			list.GetForEdit( "DesktopWindows" ).PlayerEditor.init = function( icon, window )
				window:Remove()
				RunConsoleCommand( "playermodel_selector" )
			end
		else
			list.Set( "DesktopWindows", "PlayerEditor", {
				title		= "Player Model",
				icon		= "icon64/playermodel.png",
				init		= function( icon, window )
					window:Remove()
					RunConsoleCommand( "playermodel_selector" )
				end
			} )
		end
end )



list.Set( "PlayerOptionsAnimations", "gman", { "menu_gman" } )

list.Set( "PlayerOptionsAnimations", "hostage01", { "idle_all_scared" } )
list.Set( "PlayerOptionsAnimations", "hostage02", { "idle_all_scared" } )
list.Set( "PlayerOptionsAnimations", "hostage03", { "idle_all_scared" } )
list.Set( "PlayerOptionsAnimations", "hostage04", { "idle_all_scared" } )

list.Set( "PlayerOptionsAnimations", "zombine", { "menu_zombie_01" } )
list.Set( "PlayerOptionsAnimations", "corpse", { "menu_zombie_01" } )
list.Set( "PlayerOptionsAnimations", "zombiefast", { "menu_zombie_01" } )
list.Set( "PlayerOptionsAnimations", "zombie", { "menu_zombie_01" } )
list.Set( "PlayerOptionsAnimations", "skeleton", { "menu_zombie_01" } )

list.Set( "PlayerOptionsAnimations", "combine", { "menu_combine" } )
list.Set( "PlayerOptionsAnimations", "combineprison", { "menu_combine" } )
list.Set( "PlayerOptionsAnimations", "combineelite", { "menu_combine" } )
list.Set( "PlayerOptionsAnimations", "police", { "menu_combine" } )
list.Set( "PlayerOptionsAnimations", "policefem", { "menu_combine" } )

list.Set( "PlayerOptionsAnimations", "css_arctic", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_gasmask", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_guerilla", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_leet", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_phoenix", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_riot", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_swat", { "pose_standing_02", "idle_fist" } )
list.Set( "PlayerOptionsAnimations", "css_urban", { "pose_standing_02", "idle_fist" } )

local bonus = { "idle_all_01", "menu_walk", "pose_standing_02", "pose_standing_03", "idle_fist", "pose_standing_01", "pose_standing_04", "swim_idle_all", "idle_all_scared", "idle_magic" }
local fav = { -- ^_^ --
	"TFA-May-RS", "TFA-May-ORAS", "May", "Dawn", "Rosa", "Hilda", "Leaf", "Mami",
	"Misaka Mikoto (Summer)", "Misaka Mikoto (Winter)", "Misaka Imoito (Summer)", "Misaka Imoito (Winter)", "Shirai Kuroko (Summer)", "Shirai Kuroko (Winter)", "Uiharu Kazari", "Saten Ruiko",
	"Tda Hatsune Miku (v2)", "YYB Kagamine Rin (v3)", "Appearance Miku (Default)", "Appearance Miku (Stroll)", "Appearance Miku (Cupid)", "Appearance Miku (Colorful Drop)", "Kizuna AI"
}
for k, v in pairs( fav ) do
	list.Set( "PlayerOptionsAnimations", v, bonus )
end


end
