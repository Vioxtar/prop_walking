--[[-------------------------------------------------------------------------
 - We enable prop walking by having the player walk on a prop walker (called pw) entity instead of actual props.

 - Each prop (called ground) has its own prop walker. It's created whenever a player makes contact with a new ground,
and is removed after 10 minutes of being inactive (unstepped on by players) for optimization purposes.

- The per ground approach is preferred (rather than a per-player approach) to allow smooth transitions between grounds.

 - A prop walker is parented to its ground, and always shares its ground's physcollides, position and angles.

TODO:
	Crucial:
		For prop walker: Disable shoot traces, enable movement traces
		For ground: Enable shoot traces, disable movement traces

		Improve player-on-ground illusion on calcview, player draws, etc.
		Prevent physics damage with objects travelling the same velocity
	
	Optimization:
		Check if we really need to network prop walker position as well (for proper predictions) on pw:NetworkAbsPosition()

	Optional:
		Simulate player weight on original ground
		Tweak player velocity on leave to match ground's
		Resolve more player stuck cases
---------------------------------------------------------------------------]]

--[[-------------------------------------------------------------------------
Only cover certain grounds (current valid physics props)
---------------------------------------------------------------------------]]
local function ShouldCoverGround(ground)
	-- Check the ground
	if not IsValid(ground) then return false end
	if ground:GetClass() != "prop_physics" then return false end
	return true
end

--[[-------------------------------------------------------------------------
Only serve players that are actually on a ground
---------------------------------------------------------------------------]]
local function ShouldServePlayer(ply)
	-- Check the player
	if ply.m_bWasNoclipping then return false end
	if ply:InVehicle() then return false end
	if not ply:Alive() then return false end
	return true
end


--[[-------------------------------------------------------------------------
Create & handle prop walkers, tweak player positions
---------------------------------------------------------------------------]]
local maxSlope = 0.707107 -- We can't walk on slopes bigger than this
local turnOnDist = 50 -- Ground coverage turns on when this many units above the ground
hook.Add("PlayerTick", "PropWalk", function(ply, mv)

	-- Check if we have a ground we should cover
	local mins, maxs = ply:GetCollisionBounds()
	local plyHeight = maxs.z - mins.z
	local filter = {} -- A filter that includes all prop walkers and the player
	table.Add(filter, propWalkers)
	filter[#filter + 1] = ply
	local tr0 = util.TraceHull{
		start = mv:GetOrigin() + Vector(0, 0, plyHeight),
		endpos = mv:GetOrigin() - Vector(0, 0, turnOnDist),
		filter = filter,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID
	}

	local ground = tr0.Entity
	local goodSlope = tr0.HitNormal.z >= maxSlope or tr0.HitNormal.z == 0
	if tr0.Hit and ShouldCoverGround(ground) and ShouldServePlayer(ply) and goodSlope then -- We're above a ground
		local pw = ground:GetNW2Entity("PropWalker")
		
		if not IsValid(pw) then
			-- The ground is uncovered, create a new prop walker
			if SERVER then
				pw = ents.Create("prop_walker")

				-- Network the ground as soon as possible for correct initialization on client
				pw:SetNW2Entity("Ground", ground)
				ground:SetNW2Entity("PropWalker", pw)

				pw:Spawn()
			end
			
			return -- Wait for the next iteration
		end

		-- We have a valid prop walker, continue

		-- Fix prop walker position & angle networking, and bail on client
		if CLIENT then
			local netAng = pw:GetNW2Angle("GroundAng")
			local netPos = pw:GetNW2Vector("GroundPos")

			if netAng then pw:SetAngles(netAng) end
			if netPos then pw:SetPos(netPos) end

			return -- Only server stuff from here on out
		end

		if SERVER then

			-- Reset the removal timer
			pw:RemovalTimer()
			pw:NetworkAbsPosition()

			local nextOrigin = mv:GetOrigin()

			-- Set our local prop walker position
			local lastPW = ply.lastPW
			local lastPWPos = ply.lastPWPos
			if lastPWPos and pw == lastPW then
				nextOrigin = pw:LocalToWorld(lastPWPos)
			end

			-- Find out if we're stuck
			local tr1 = util.TraceHull{
				start = nextOrigin + Vector(0, 0, plyHeight),
				endpos = nextOrigin,
				filter = {ply, ground},
				mins = mins,
				maxs = maxs,
				mask = MASK_PLAYERSOLID
			}
			if tr1.Hit then -- We're stuck, resolve
				if tr1.Entity == pw and tr1.HitPos.z - mv:GetOrigin().z < 50 then
					nextOrigin = tr1.HitPos
				end
			end

			-- Set our next position only if we won't be stuck in it
			local tr2 = util.TraceHull{
				start = nextOrigin,
				endpos = nextOrigin,
				filter = ply,
				mins = mins,
				maxs = maxs,
				mask = MASK_PLAYERSOLID
			}
			if not tr2.Hit then -- We won't be stuck, set the player's new origin
				mv:SetOrigin(nextOrigin)
			end

			-- Store the last active prop walker for the FinishMove hook
			ply.lastPW = pw
		end

	else

		-- No valid prop walker to be worked with, forget & bail
		
		if SERVER then

			ply.lastPW = nil

		end

	end
end)


--[[-------------------------------------------------------------------------
Obtain relative ground position to be used in later movement hook (for moving grounds)
---------------------------------------------------------------------------]]
hook.Add("FinishMove", "GetRelativeGroundPosition", function(ply, mv)
	
	if CLIENT then return end

	local pw = ply.lastPW
	if IsValid(pw) then
		ply.lastPWPos = pw:WorldToLocal(mv:GetOrigin())
	else
		ply.lastPWPos = nil
	end

end)
