local plymeta = assert(FindMetaTable("Player"), "FAILED TO FIND ENTITY TABLE")

SPEED = SPEED or {}

if SERVER then
	util.AddNetworkString("TTT2UpdateSpeedModifier")

	function SPEED:HandleSpeedCalculation(ply, moveData)
		if not ply:IsTerror() then return end

		local baseMultiplier = 1
		local isSlowed = false

		-- Slow down ironsighters
		local wep = ply:GetActiveWeapon()

		if IsValid(wep) and wep.GetIronsights and wep:GetIronsights() then
			baseMultiplier = 120 / 220
			isSlowed = true
		end

		local speedMultiplierModifier = {1}
		local returnMultiplier = hook.Run("TTTPlayerSpeedModifier", ply, isSlowed, moveData, speedMultiplierModifier) or 1

		ply:SetSpeedMultiplier(baseMultiplier * returnMultiplier * speedMultiplierModifier[1])
	end

	---
	-- A hook to modify the player speed, it is automatically networked.
	-- @param Player ply The player whose speed should be modified
	-- @param boolean isSlowed Is true if the player uses iron sights
	-- @param CMoveData moveData The move data
	-- @param table speedMultiplierModifier The speed modifier table. Modify the first table entry to change the player speed
	-- @return[deprecated] number The deprecated way of changing the player speed
	-- @hook
	-- @realm server
	function GM:TTTPlayerSpeedModifier(ply, isSlowed, moveData, speedMultiplierModifier)

	end

	---
	-- Sets the speed multiplier to an absolute value
	-- @param number value The new value
	-- @realm server
	function plymeta:SetSpeedMultiplier(value)
		if self:GetSpeedMultiplier() == value then return end

		self.speedModifier = math.max(0, value)

		net.Start("TTT2UpdateSpeedModifier")
		net.WriteFloat(self.speedModifier)
		net.Send(self)
	end
end

if CLIENT then
	---
	-- Initializes the speed system once the game is ready.
	-- It is called in @{GM:Initialize}.
	-- @realm client
	function SPEED:Initialize()
		STATUS:RegisterStatus("ttt_speed_status_good", {
			hud = {
				Material("vgui/ttt/perks/hud_speedrun.png")
			},
			type = "good",
			DrawInfo = function()
				return math.Round(LocalPlayer():GetSpeedMultiplier(), 1)
			end
		})

		STATUS:RegisterStatus("ttt_speed_status_bad", {
			hud = {
				Material("vgui/ttt/perks/hud_speedrun.png")
			},
			type = "bad",
			DrawInfo = function()
				return math.Round(LocalPlayer():GetSpeedMultiplier(), 1)
			end
		})
	end

	net.Receive("TTT2UpdateSpeedModifier", function()
		local client = LocalPlayer()

		local oldval = client:GetSpeedMultiplier()
		local newval = net.ReadFloat()

		client.speedModifier = newval

		newval = math.Round(newval, 1)

		if newval == 1.0 then
			STATUS:RemoveStatus("ttt_speed_status_good")
			STATUS:RemoveStatus("ttt_speed_status_bad")
		elseif newval > 1.0 and oldval <= 1.0 then
			STATUS:RemoveStatus("ttt_speed_status_bad")
			STATUS:AddStatus("ttt_speed_status_good")
		elseif newval < 1.0 and oldval >= 1.0 then
			STATUS:RemoveStatus("ttt_speed_status_good")
			STATUS:AddStatus("ttt_speed_status_bad")
		end
	end)
end

---
-- Returns the current player speed modifier
-- @return number The speed modifier
-- @realm shared
function plymeta:GetSpeedMultiplier()
	return self.speedModifier or 1.0
end
