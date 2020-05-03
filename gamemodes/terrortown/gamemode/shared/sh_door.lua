--- LOCAL DOOR RELATED STUFF ---

local door_list = {
	doors = {}
}

local valid_doors = {
	special = {
		["func_door"] = true,
		["func_door_rotating"] = true
	},
	normal = {
		["prop_door_rotating"] = true
	}
}

-- Returns if a door is open
local function IsDoorOpen(ent)
	if CLIENT then return end

	local cls = ent:GetClass()

	if door.IsValidNormal(cls) then
		return ent:GetInternalVariable("m_eDoorState") ~= 0
	elseif door.IsValidSpecial(cls) then
		return ent:GetInternalVariable("m_toggle_state") == 0
	end

	return false
end

-- Returns if a player can interact with a door
local function PlayerCanUseDoor(ent)
	if CLIENT then return end

	local cls = ent:GetClass()

	if door.IsValidNormal(cls) then
		-- 32768: ignore player +use
		return not ent:HasSpawnFlags(32768)
	elseif door.IsValidSpecial(cls) then
		-- 256: use opens
		return ent:HasSpawnFlags(256)
	end

	return false
end

-- Returns if touching a door opens it
local function PlayerCanTouchDoor(ent)
	if CLIENT then return end

	local cls = ent:GetClass()

	if door.IsValidNormal(cls) then
		-- this door type has no touch mode
		return false
	elseif door.IsValidSpecial(cls) then
		-- 1024: touch opens
		return ent:HasSpawnFlags(1024)
	end

	return false
end

-- Returns if a door autocloses after some time
local function DoorAutoCloses(ent)
	if CLIENT then return end

	local cls = ent:GetClass()

	if door.IsValidNormal(cls) then
		-- 8192: door closes on use
		return not ent:HasSpawnFlags(8192)
	elseif door.IsValidSpecial(cls) then
		-- 1024: touch opens
		return not ent:HasSpawnFlags(32)
	end

	return false
end

--- DOORS MODULE STUFF ---

---
-- @module door
-- @author Mineotopia
-- @desc A bunch of functions that handle all doors found on a map

door = {}

---
-- Setting up all doors found on a map, this is done on every map reset (on prepare round)
-- @internal
-- @realm shared
function door.SetUp()
	local all_ents = ents.GetAll()
	local doors = {}

	-- search for new doors
	for i = 1, #all_ents do
		local ent = all_ents[i]

		if not ent:IsDoor() then continue end

		doors[#doors + 1] = ent

		-- set up synced states if on server
		if CLIENT then continue end

		ent:SetNWBool("ttt2_door_locked", ent:GetInternalVariable("m_bLocked") or false)
		ent:SetNWBool("ttt2_door_forceclosed", ent:GetInternalVariable("forceclosed") or false)
		ent:SetNWBool("ttt2_door_open", IsDoorOpen(ent) or false)

		ent:SetNWBool("ttt2_door_player_use", PlayerCanUseDoor(ent))
		ent:SetNWBool("ttt2_door_player_touch", PlayerCanTouchDoor(ent))
		ent:SetNWBool("ttt2_door_auto_close", DoorAutoCloses(ent))

		outputs.RegisterMapEntityOutput(ent, "OnOpen", "TTT2DoorOpens")
		outputs.RegisterMapEntityOutput(ent, "OnClose", "TTT2DoorCloses")
		outputs.RegisterMapEntityOutput(ent, "OnFullyOpen", "TTT2DoorFullyOpen")
		outputs.RegisterMapEntityOutput(ent, "OnFullyClosed", "TTT2DoorFullyClosed")
	end

	door_list.doors = doors
end

---
-- Returns all valid door entity class names
-- @return table A table of door class names
-- @realm shared
function door.GetValid()
	return valid_doors
end

---
-- Returns if a passed door class is a valid normal door (prop_door_rotating)
-- @return boolean True if it is a valid normal door
-- @realm shared
function door.IsValidNormal(cls)
	return valid_doors.normal[cls] or false
end

---
-- Returns if a passed door class is a valid special door (func_door, func_door_rotating)
-- @return boolean True if it is a valid special door
-- @realm shared
function door.IsValidSpecial(cls)
	return valid_doors.special[cls] or false
end

---
-- Returns all valid door entities found on a map
-- @return table A table of door entities
-- @realm shared
function door.GetAll()
	return door_list.doors
end

if SERVER then
	---
	-- Called when a map I/O event occurs.
	-- @param Entity ent Entity that receives the input
	-- @param string input The input name. Is not guaranteed to be a valid input on the entity.
	-- @param Entity activator Activator of the input
	-- @param Entity caller Caller of the input
	-- @param any data Data provided with the input
	-- @return boolean Return true to prevent this input from being processed.
	-- @ref https://wiki.facepunch.com/gmod/GM:AcceptInput
	-- @hook
	-- @realm server
	function GM:AcceptInput(ent, name, activator, caller, data)
		if not IsValid(ent) or not ent:IsDoor() then return end

		name = string.lower(name)

		-- if there is a SID64 in the data string, it should be extracted
		local sid

		if data and data ~= "" then
			local dataTable = string.Explode("||", data)
			local dataTableCleared = {}

			for i = 1, #dataTable do
				local dataLine = dataTable[i]

				if string.sub(dataLine, 1, 4) == "sid=" then
					sid = string.sub(dataLine, 5)
				else
					dataTableCleared[#dataTableCleared + 1] = dataLine
				end
			end

			data = string.Implode("||", dataTableCleared)
		end

		local ply = player.GetBySteamID64(sid)

		if IsValid(ply) then
			activator = IsValid(activator) and activator or ply
			caller = IsValid(caller) and caller or ply
		end

		print(ent)
		print(name)
		print(activator)
		print(caller)
		print(data)
		print("------")

		-- handle the entity input types
		if name == "lock" then
			local shouldCancel = hook.Run("TTT2OnDoorLock", ent, activator, caller)

			if shouldCancel then
				return true
			end

			-- we expect the door to be locked now, but we check the real state after a short
			-- amount of time to be sure
			ent:SetNWBool("ttt2_door_locked", true)

			-- check if the assumed state was correct
			timer.Create("ttt2_recheck_door_lock_" .. ent:EntIndex(), 1, 1, function()
				if not IsValid(ent) then return end

				ent:SetNWBool("ttt2_door_locked", ent:GetInternalVariable("m_bLocked") or false)
			end)
		elseif name == "unlock" then
			local shouldCancel = hook.Run("TTT2OnDoorUnlock", ent, activator, caller)

			if shouldCancel then
				return true
			end

			-- we expect the door to be unlocked now, but we check the real state after a short
			-- amount of time to be sure
			ent:SetNWBool("ttt2_door_locked", false)

			-- check if the assumed state was correct
			timer.Create("ttt2_recheck_door_unlock_" .. ent:EntIndex(), 1, 1, function()
				if not IsValid(ent) then return end

				ent:SetNWBool("ttt2_door_locked", ent:GetInternalVariable("m_bLocked") or false)
			end)
		elseif name == "use" and ent:IsDoorOpen() then
			local shouldCancel = hook.Run("TTT2OnDoorClose", ent, activator, caller)

			if shouldCancel then
				return true
			end

		elseif name == "use" and not ent:IsDoorOpen() then
			local shouldCancel = hook.Run("TTT2OnDoorOpen", ent, activator, caller)

			if shouldCancel then
				return true
			end
		end
	end

	---
	-- This hook is called after the door started opening.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity, it seems to be the door entity for most doors
	-- @hook
	-- @realm server
	function GM:TTT2DoorOpens(doorEntity, activator)
		if not doorEntity:IsDoor() then return end

		doorEntity:SetNWBool("ttt2_door_open", true)
	end

	---
	-- This hook is called after the door finished opening and is fully opened.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity, it seems to be the door entity for most doors
	-- @hook
	-- @realm server
	function GM:TTT2DoorFullyOpen(doorEntity, activator)
		if not doorEntity:IsDoor() then return end

		doorEntity:SetNWBool("ttt2_door_open", true)
	end

	---
	-- This hook is called after the door started closing.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity, it seems to be the door entity for most doors
	-- @hook
	-- @realm server
	function GM:TTT2DoorCloses(doorEntity, activator)
		if not doorEntity:IsDoor() then return end

		doorEntity:SetNWBool("ttt2_door_open", false)
	end

	---
	-- This hook is called after the door finished closing and is fully closed.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity, it seems to be the door entity for most doors
	-- @hook
	-- @realm server
	function GM:TTT2DoorFullyClosed(doorEntity, activator)
		if not doorEntity:IsDoor() then return end

		doorEntity:SetNWBool("ttt2_door_open", false)
	end

	---
	-- This hook is called when the door is about to be locked. You can cancel the event.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity
	-- @param Entity caller The caller entity
	-- @return boolean Return true to cance the door lock
	-- @hook
	-- @realm server
	function GM:TTT2OnDoorLock(doorEntity, activator, caller)

	end

	---
	-- This hook is called when the door is about to be unlocked. You can cancel the event.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity
	-- @param Entity caller The caller entity
	-- @return boolean Return true to cance the door unlock
	-- @hook
	-- @realm server
	function GM:TTT2OnDoorUnlock(doorEntity, activator, caller)

	end

	---
	-- This hook is called when the door is about to be opened. You can cancel the event.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity
	-- @param Entity caller The caller entity
	-- @return boolean Return true to cance the door opening
	-- @hook
	-- @realm server
	function GM:TTT2OnDoorOpen(doorEntity, activator, caller)

	end

	---
	-- This hook is called when the door is about to be closed. You can cancel the event.
	-- @param Entity doorEntity The door entity
	-- @param Entity activator The activator entity
	-- @param Entity caller The caller entity
	-- @return boolean Return true to cance the door closing
	-- @hook
	-- @realm server
	function GM:TTT2OnDoorClose(doorEntity, activator, caller)

	end
end


--- ENTITY EXTENSION STUFF ---

---
-- @module Entity
-- @author Mineotopia
-- @ref https://wiki.facepunch.com/gmod/Entity
-- @desc shared extensions to entity table

local entmeta = assert(FindMetaTable("Entity"), "FAILED TO FIND ENTITY TABLE")

---
-- Returns whether this entity is a door or not
-- @return boolean Returns true if it is a valid door
-- @realm shared
function entmeta:IsDoor()
	local cls = self:GetClass()
	local valid = door.GetValid()

	if IsValid(self) and (valid.normal[cls] or valid.special[cls]) then
		return true
	end

	return false
end

---
-- Returns the lock state of a door
-- @return boolean The door state; true: locked, false: unlocked, nil: no valid door
-- @realm shared
function entmeta:IsDoorLocked()
	if not self:IsDoor() then return end

	return self:GetNWBool("ttt2_door_locked", false)
end

---
-- Returns if a door is forceclosed, if it forceclosed it will close no matter what
-- @return boolean The door state; true: forceclosed, false: not forceclosed, nil: no valid door
-- @realm shared
function entmeta:IsDoorForceclosed()
	if not self:IsDoor() then return end

	return self:GetNWBool("ttt2_door_forceclosed", false)
end

---
-- Returns if this door can be opened with the use key, traitor room doors or doors
-- opened with a button press can't be opened with the use key for example
-- @return boolean If the door can be opened with the use key
-- @realm shared
function entmeta:UseOpensDoor()
	if not self:IsDoor() then return end

	return self:GetNWBool("ttt2_door_player_use", false)
end

---
-- Returns if this door can be opened by close proximity of a player
-- @return boolean If the door can be opened with proximity
-- @realm shared
function entmeta:TouchOpensDoor()
	if not self:IsDoor() then return end

	return self:GetNWBool("ttt2_door_player_touch", false)
end

---
-- Returns if this door can be opened by a player
-- @return boolean If the door can be opened
-- @realm shared
function entmeta:PlayerCanOpenDoor()
	if not self:IsDoor() then return end

	return self:UseOpensDoor() or self:TouchOpensDoor()
end

---
-- Returns if this door closes automatically after a certain time
-- @return boolean If the door closes automatically
-- @realm shared
function entmeta:DoorAutoCloses()
	if not self:IsDoor() then return end

	return self:GetNWBool("ttt2_door_auto_close", false)
end

---
-- Returns if a door is open
-- @return boolean The door state; true: open, false: close, nil: no valid door
-- @realm shared
function entmeta:IsDoorOpen()
	if not self:IsDoor() then return end

	return self:GetNWBool("ttt2_door_open", false)
end

if SERVER then
	local function GetDataString(ply, data)
		local dataTable = {}

		if IsValid(ply) then
			dataTable[#dataTable + 1] = "sid=" .. ply:SteamID64()
		end

		if data and data ~= "" then
			dataTable[#dataTable + 1] = data
		end

		return string.Implode("||", dataTable)
	end

	---
	-- Locks a door.
	-- @param [opt]Player ply The player that will be passed through as the activator
	-- @param [opt]string data Optional data that can be passed through
	-- @param [default=0]number delay The delay until the event is fired
	-- @realm server
	function entmeta:LockDoor(ply, data, delay)
		if not self:IsDoor() then return end

		self:Fire("Lock", GetDataString(ply, data), delay or 0)
	end

	---
	-- Unlocks a door.
	-- Locks a door.
	-- @param [opt]Player ply The player that will be passed through as the activator
	-- @param [opt]string data Optional data that can be passed through
	-- @param [default=0]number delay The delay until the event is fired
	-- @realm server
	function entmeta:UnlockDoor(ply, data, delay)
		if not self:IsDoor() then return end

		self:Fire("Unlock", GetDataString(ply, data), delay or 0)
	end

	---
	-- Opens the door.
	-- Locks a door.
	-- @param [opt]Player ply The player that will be passed through as the activator
	-- @param [opt]string data Optional data that can be passed through
	-- @param [default=0]number delay The delay until the event is fired
	-- @realm server
	function entmeta:OpenDoor(ply, data, delay)
		if not self:IsDoor() then return end

		self:Fire("Open", GetDataString(ply, data), delay or 0)
	end

	---
	-- Closes a door.
	-- Locks a door.
	-- @param [opt]Player ply The player that will be passed through as the activator
	-- @param [opt]string data Optional data that can be passed through
	-- @param [default=0]number delay The delay until the event is fired
	-- @realm server
	function entmeta:CloseDoor(ply, data, delay)
		if not self:IsDoor() then return end

		self:Fire("Close", GetDataString(ply, data), delay or 0)
	end

	---
	-- Toggles a door between open and closed.
	-- Locks a door.
	-- @param [opt]Player ply The player that will be passed through as the activator
	-- @param [opt]string data Optional data that can be passed through
	-- @param [default=0]number delay The delay until the event is fired
	-- @realm server
	function entmeta:ToggleDoor(ply, data, delay)
		if not self:IsDoor() then return end

		self:Fire("Toggle", GetDataString(ply, data), delay or 0)
	end

	---
	-- Returns if a door is currently transitioning between beeing opened and closed
	-- @return boolean The door state; true: open, false: close, nil: no valid door
	-- @realm server
	function entmeta:DoorIsTransitioning()
		if not self:IsDoor() then return end

		local cls = self:GetClass()

		if door.IsValidNormal(cls) then
			-- some doors have an auto-close feature
			if self:DoorAutoCloses() and self:GetInternalVariable("m_eDoorState") == 2 then
				return true
			end

			return self:GetInternalVariable("m_eDoorState") == 1 or self:GetInternalVariable("m_eDoorState") == 3
		elseif door.IsValidSpecial(cls) then
			-- some doors have an auto-close feature
			if self:DoorAutoCloses() and self:GetInternalVariable("m_toggle_state") == 0 then
				return true
			end

			return self:GetInternalVariable("m_toggle_state") == 2 or self:GetInternalVariable("m_toggle_state") == 3
		end
	end
end
