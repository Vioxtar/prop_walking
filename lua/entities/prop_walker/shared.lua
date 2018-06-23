AddCSLuaFile()

DEFINE_BASECLASS("base_anim")

--[[-------------------------------------------------------------------------
Removal the prop walker after 10 minutes of inactivity
---------------------------------------------------------------------------]]
function ENT:RemovalTimer()
	if CLIENT then return end
	timer.Adjust("pwRemove"..self:EntIndex(), 600, 1, function()
		if IsValid(self) then self:Remove() end
	end)
end

-- A global table to find all prop walkers without iterating all entities
propWalkers = {}

local function HandleRemoval(pw)
	propWalkers[pw] = nil
end


--[[-------------------------------------------------------------------------
Init the prop walker and cover the ground
---------------------------------------------------------------------------]]
function ENT:Initialize()

	local ground = self:GetNW2Entity("Ground")
	if !IsValid(ground) then
		if SERVER then self:Remove() end
		return
	end

	-- Cover the new ground
	self:RebuildPhysics(ground:GetModel())
	self:SetPos(ground:GetPos())
	self:SetAngles(ground:GetAngles())
	self:SetModel(ground:GetModel())
	self:SetParent(ground)
	ground:SetNW2Entity("PropWalker", self)
	ground:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) -- This is a temporary solution

	-- Add the new prop walker to the table of prop walkers for quicker filtering in collision traces
	propWalkers[self] = self
	-- And remove ourselves from the table upon removal
	self:CallOnRemove("HandleRemoval", HandleRemoval)

	-- Make the prop walker invisible
	self:DrawShadow(false)
	self:SetNoDraw(true)

	-- Solidify the prop walker
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:EnableCustomCollisions(true)

	
	if SERVER then
		-- Network our abs position as soon as possible for smooth player mounts
		self:NetworkAbsPosition()

		-- Start a self removal timer in case of inactivity
		self:RemovalTimer()
	end
	
end


--[[-------------------------------------------------------------------------
Rebuild the physics of the prop walker to match our ground's model
---------------------------------------------------------------------------]]
function ENT:RebuildPhysics(model)

	if self.PhysModel == model then return end -- We've already built the physics we want

	self.PhysModel = model
	self.PhysCollides = CreatePhysCollidesFromModel(model)

	-- Perhaps some of these are redundant
	self:SetSolid(SOLID_VPHYSICS)
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		self:GetPhysicsObject():EnableMotion(false)
	end

	self:EnableCustomCollisions(true)
end


--[[-------------------------------------------------------------------------
 Handles collisions against traces, includes player movement
---------------------------------------------------------------------------]]
function ENT:TestCollision(startpos, delta, isbox, extents)
	if !self.PhysCollides then return end

	-- TraceBox expects the trace to begin at the center of the box, but TestCollision is very quite silly
	local max = extents
	local min = -extents
	max.z = max.z - min.z
	min.z = 0

	for k, v in ipairs(self.PhysCollides) do
		local hit, norm, frac = v:TraceBox(self:GetPos(), self:GetAngles(), startpos, startpos + delta, min, max)
		
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
function ENT:NetworkAbsPosition()
	if CLIENT then return end

	local ground = self:GetNW2Entity("Ground")
	if !IsValid(ground) then return end

	local currPos = self:GetNW2Vector("GroundPos")
	local currAng = self:GetNW2Vector("GroundAng")

	local newPos = ground:GetPos()
	local newAng = ground:GetAngles()

	-- Only network if there was a change
	if !currPos or currPos != newPos then
		self:SetNW2Vector("GroundPos", newPos)
	end
	if !currAng or currAng != newAng then
		self:SetNW2Angle("GroundAng", newAng)
	end
end


--[[-------------------------------------------------------------------------
Prevent Physgun pickups
---------------------------------------------------------------------------]]
hook.Add("PhysgunPickup", "PreventPickups", function(ply, ent)
	if ent:GetClass() == "prop_walker" then return false end
end)
