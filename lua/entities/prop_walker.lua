AddCSLuaFile( )

DEFINE_BASECLASS( "base_anim" )

local InactiveTimerDelay = 120

--[[-------------------------------------------------------------------------
Removal the prop walker after 2 minutes of inactivity
---------------------------------------------------------------------------]]
function ENT:RestartRemovalTimer( )

	return timer.Start( "pwRemove_".. self:EntIndex( ) )

end

-- A global table to find all prop walkers without iterating all entities
propWalkers = propWalkers or {}

local function HandleRemoval( pw )

	timer.Remove( "pwRemove_".. pw:EntIndex( ) )

	table.remove( propWalkers, pw.PWIndex )

end


--[[-------------------------------------------------------------------------
Init the prop walker and cover the ground
---------------------------------------------------------------------------]]
function ENT:Initialize( )

	local ground = self:GetNW2Entity( "Ground" )
	if SERVER and !IsValid( ground ) then

		self:Remove( )

		return

	end

	-- Cover the new ground
	self:RebuildPhysics( ground:GetModel( ) )

	self:SetPos( ground:GetPos( ) )
	self:SetAngles( ground:GetAngles( ) )
	self:SetModel( ground:GetModel( ) )
	self:SetParent( ground )

	ground:SetNW2Entity( "PropWalker", self )
	-- Set our original ground entity to collide with everything but the player himself
	ground:SetCollisionGroup( COLLISION_GROUP_PASSABLE_DOOR )
	-- Add the new prop walker to the table of prop walkers for quicker filtering in collision traces and store its index for removal
	self.PWIndex = table.insert( propWalkers, self )
	-- And remove ourselves from the table upon removal
	self:CallOnRemove( "HandleRemoval", HandleRemoval )
	-- Make the prop walker invisible
	self:DrawShadow( false )
	self:SetNoDraw( true )
	-- Solidify the prop walker
	self:SetSolid( SOLID_VPHYSICS )
	self:SetCollisionGroup( COLLISION_GROUP_NONE )
	self:EnableCustomCollisions( true )
	
	if SERVER then
		-- Network our abs position as soon as possible for smooth player mounts
		self:NetworkAbsPosition( )

		-- Create a self removal timer in case of inactivity
		timer.Create( "pwRemove_".. self:EntIndex( ), InactiveTimerDelay, 1, function( )

			SafeRemoveEntity( self )

		end )
		-- We want to use touch hooks to determine ground collision groups
		-- self:SetTrigger( true )
	end
	
end


--[[-------------------------------------------------------------------------
Rebuild the physics of the prop walker to match our ground's model
---------------------------------------------------------------------------]]
function ENT:RebuildPhysics( model )

	if self.PhysModel == model then return end -- We've already built the physics we want

	self.PhysModel = model
	self.PhysCollides = CreatePhysCollidesFromModel( model )

	-- Perhaps some of these are redundant
	self:SetSolid( SOLID_VPHYSICS )
	local phys = self:GetPhysicsObject( )
	if IsValid( phys ) then

		phys:EnableMotion( false )

	end

	self:EnableCustomCollisions( true )

end



--[[-------------------------------------------------------------------------
 Handles collisions against traces, includes player movement
---------------------------------------------------------------------------]]
function ENT:TestCollision( startpos, delta, isbox, extents, mask )

	if !self.PhysCollides then return end
	-- Return nothing if our mask isn't involved with actual player collisions
	if bit.band( mask, CONTENTS_PLAYERCLIP ) == 0 then return end
	-- TraceBox expects the trace to begin at the center of the box, but TestCollision is very quite silly
	local max = extents
	local min = -extents
	max.z = max.z - min.z
	min.z = 0

	for k, v in ipairs( self.PhysCollides ) do

		local hit, norm, frac = v:TraceBox( self:GetPos( ), self:GetAngles( ), startpos, startpos + delta, min, max )

		if !hit then continue end

		return {

			HitPos = hit,

			Normal = norm,

			Fraction = frac,

		}

	end

end


--[[-------------------------------------------------------------------------
Network position and angle to the client to overcome engine inaccuracies
---------------------------------------------------------------------------]]
function ENT:NetworkAbsPosition( pos, ang )

	if CLIENT then return pos, ang end

	local ground = self:GetNW2Entity( "Ground" )
	if !IsValid( ground ) then return end

	local currPos = self:GetNW2Vector( "GroundPos" )
	local currAng = self:GetNW2Vector( "GroundAng" )

	local newPos = ground:GetPos( )
	local newAng = ground:GetAngles( )
	-- Only network if there was a change
	if !currPos or currPos != newPos then

		self:SetNW2Vector( "GroundPos", newPos )

	end

	if !currAng or currAng != newAng then

		self:SetNW2Angle( "GroundAng", newAng )

	end

end

--[[-------------------------------------------------------------------------
Walked on or not, we also wish to network the absolute position whenever it changes
---------------------------------------------------------------------------]]
function ENT:CalcAbsolutePosition( )

	self:NetworkAbsPosition( )

end


--[[-------------------------------------------------------------------------
Prevent Physgun pickups
---------------------------------------------------------------------------]]
hook.Add( "PhysgunPickup", "PreventPickups", function( ply, ent )

	if ent:GetClass( ) == "prop_walker" then return false end

end )
