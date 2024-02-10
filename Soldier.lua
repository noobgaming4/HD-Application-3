---- Get services
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChatService = game:GetService("Chat")
local TweenService = game:GetService("TweenService")

----- Modules
local NPCs_Module = require(script.Parent.Parent.NPCs) --- a table of current npcs in the game
local GeneralFunctions = require(script.Parent.Parent.GeneralFunctions) -- general functions that include finding the closest target etc.
local CoversModule = require(script.Parent.Parent.Covers) --- a table of cover positions that are generated
local NPC_Class = require(script.Parent) --- the npc class that this class inherits from
local PathfindingScript = require(script.Parent.Parent.PathfindingScript) --- pathfinding module

local NPC_Storage = ServerStorage:WaitForChild("NPC_Storage") --- npc storage
local Events = ServerStorage:WaitForChild("Events") --- events
local Noob_Remotes = ReplicatedStorage:WaitForChild("Noob_Remotes") --- remotes


local Soldier_Dialouges = require(script.Dialouge) --- dialouge module


local LEADER_TARGET_SPOTTED_LINES = { --- the lines that the squad leader says when an enemy is spotted
	"TAKIM, DÜŞMAN!",
	"HEDEF GÖRÜLDÜ.",
	"DÜŞMAN BELIRLENDI."
}

local LEADER_ATTACK_LINES = { -- the lines that the squad leader says when ordering to attack
	"TAKIM, SALDIR.",
	"TAKIM, İLERİ.",
	"TAKIM, İLERLE."
}

local COPY_LINES = { --- lines squad members say when they recieve an order / event
	"Anlaşıldı.",
	"Anlaşıldı."
}

local FIND_COVER_RANGE = 35 --- the max range a cover can be found

local TargetSpottedEvent : BindableEvent = Events:WaitForChild("Soldier_Spot_Target") --- target spotted event
local AttackOrderEvent : BindableEvent = Events:WaitForChild("SoldierAttackOrder") -- attack order event

local DistruptableStates = { --- states that can be distrupted by events
	["Patrol"] = true,
	["DecideState"] = true,
	["LookForTalk"] = true,
	["Talking"] = true,
	["Listening"] = true
}

local WaypointFunctions = require(script.WaypointFunctions) --- waypoint functions such as rappeling

local States = {} --- state functions

function States.TestState(Unit) -- a state for testing stuff
	
end

function States.LookForTalk(Unit) --- a state where squad members look for other squad members to talk to. only when there is no enemy
	local SquadData = NPCs_Module.Squads[Unit.Squad] --- get the squad table

	for i,Member in ipairs( SquadData.M ) do -- loop through every member of the squad
		if Member == Unit.Model then --- if the member is this member, return
			return
		end
		local MemberUnit = NPCs_Module.NPCs[Member] --- get the member data table from its model
		if MemberUnit then
			if MemberUnit.State == "LookForTalk" then --- if that member is also looking to talk
				local ChosenDialouge = math.random(1,#Soldier_Dialouges) -- select a random dialouge
				MemberUnit.ObjectT = Unit.Model --- set the object target variable
				MemberUnit.State = "Listening" --- set the members state to listening, which basically does nothing 
				
				--- set variables
				Unit.ObjectT = Member --- object target variable
				Unit.Timer1 = ChosenDialouge -- timer1 is reused to get the dialouges index
				Unit.Timer0 = 1 --- timer0 is reused to set the current dialouge index
				
				Unit.State = "Talking"  -- set the state to talking
				
				Unit.Model.Humanoid:MoveTo(Member.PrimaryPart.Position) -- move to that members position
			end
		end
	end
end

function States.Listening(Unit) --- a state where the member listens to the talker
	if Unit.Target or not Unit.ObjectT then --- if the talker doesnt exist, change states
		Unit.State = "DecideState"
	end
end

function States.Talking(Unit) --- this state handles the talking for both members
	if not Unit.Target and Unit.ObjectT then --- check if the other member exists and that there is no target
		local Dialog = Soldier_Dialouges[Unit.Timer1] -- get the dialouge
		if Dialog then
			local Text = Dialog[Unit.Timer0] --- this is the dialouge that the first member speaks
			local Text2 = Dialog[Unit.Timer0 + 1] -- this is the dialouge that the second member speaks
			if Text then
				ChatService:Chat(Unit.Model.Head, Text)
				Unit.Timer0 = Unit.Timer0 + 2 --- add 2 since we spoke 2 times
			else
				Unit.State = "DecideState" 
			end
			task.wait(2)
			if Text2 then
				ChatService:Chat(Unit.ObjectT.Head, Text2)
			else
				NPCs_Module.NPCs[Unit.ObjectT].State = "DecideState"	
			end
			task.wait(2)
		else
			Unit.State = "DecideState"
		end
	else
		Unit.State = "DecideState"
	end
	---- if any of the ifs fail switch to decide state
	task.wait(2)--- wait 2 seconds for the next dialouge
end

function States.GetInCover(Unit) --- a state to get to cover
	if Unit.Target then -- if theres an enemy
		Unit.CoverAnim:Play() -- play the cover animation
		Unit.CanFire = false -- unit cannot fire 
		task.wait(3) -- wait 3 seconds in cover
		Unit.CanFire = true --- can fire now
		Unit.CoverAnim:Stop() -- stop the cover animation
		task.wait(3)
	else
		Unit.State = "DecideState"	 -- if no target, switch to decide state
	end
	
end

function States.Combat(Unit) -- this state only happens if there is no cover and an enemy
	Unit.Model.Humanoid:MoveTo(Unit.Model.PrimaryPart.Position + Vector3.new(math.random(-5,5) , 0 , math.random(-5,5))) --- move randomly
	
	if math.random(1,5) == 1 then --- jump randomly
		Unit.Model.Humanoid.Jump = true
	end
	
	if not Unit.Target then -- if no target then , switch states
		Unit.State = "DecideState"
	end
end

function States.TargetFound(Unit) -- this state happens when the enemy is spotted for the first time
	
	TargetSpottedEvent:Fire(Unit.Target) -- give the news to other squad members
	
	if Unit.Moving == false then -- if the unit is not moving
		if not Unit.Cover then
			local Cover = GeneralFunctions.GetClosestCover(Unit.Model.PrimaryPart.Position,FIND_COVER_RANGE) -- get the closest cover
			if Cover then
				
				if CoversModule.Covers[Cover[2]] then --- if the cover is unoccupied
					Unit.Cover = Cover[2] -- set cover
					CoversModule.Covers[Cover[2]][2] = true -- set the cover as occupied
					Unit:PathfindTo(Cover[1], "GetInCover" ) -- pathfind to the cover and switch the state to GetInCover when the pathfind is complete
				end
				
				
			end
		end
		
	end
	
	Unit.State = "Combat" --- set the state to combat, if there is cover the pathfind will override this state
	
end

local function TargetSpotted(Unit) -- a function that fires when the target is spotted
	if Unit.Squad then
		if NPCs_Module.Squads[Unit.Squad].L == Unit.Model then --- if the squad leader is this unit
			Unit.L_TargetSpotted:Play() --- fire the target spotted animation
			ChatService:Chat(Unit.Model.Head, LEADER_TARGET_SPOTTED_LINES[math.random(1,#LEADER_TARGET_SPOTTED_LINES)]) -- chat
		end
	end

	Unit.AlignOrientation.Enabled = true -- enable align orientation to look at the target
	Unit.State = "TargetFound" -- change state
end

local function SquadWellnessCheck(Unit) -- function to check if the squad is fine
	if Unit.Squad then
		for i,Member in ipairs( NPCs_Module.Squads[Unit.Squad].M ) do -- loop through every member
			local MemberUnit = NPCs_Module.NPCs[Member] -- get the member table from the model
			if MemberUnit then 
				if MemberUnit.Target or Member.Humanoid.Health == 0 then -- check if the member is dead or has a target
					Unit:PathfindTo(MemberUnit.Target.PrimaryPart.Position, "DecideState") --- if any of those is true, pathfind to that member and 
					-- decide the state when u get there
					break
				end
			end
		end
	end
end

function States.Patrol(Unit) --- a state that happens when there is no enemy
	if not Unit.Target then 
		Unit.Model.Humanoid:MoveTo(Unit.Model.PrimaryPart.Position + Vector3.new(math.random(-3,3),0,math.random(-3,3))) -- move randomly
		Unit.Timer0 = Unit.Timer0 + 2 --- add 2 seconds to the timer
		if Unit.Timer0 > 6 then --- if the timer is above 6, set the state to decidestate to update the npc
			Unit.Timer0 = 0
			Unit.State = "DecideState"
		end
		task.wait(2)
	else
		TargetSpotted(Unit)
	end
end

function States.DecideState(Unit) --- a state that decides which state to go to
	local Target = GeneralFunctions.FindClosestVisibleEnemy(Unit, Unit.FireRange) -- find an enemy
	if Target then 
		
		TargetSpotted(Unit)
	else
		local FoundSomethingToDo = false 
		
		if Unit.Squad then --- same as the SquadWellnessCheck
			local SquadData = NPCs_Module.Squads[Unit.Squad]
			
			for i,Member in ipairs( SquadData.M ) do
				local MemberUnit = NPCs_Module.NPCs[Member]
				if MemberUnit then
					if MemberUnit.Target or Member.Humanoid.Health == 0 then
						FoundSomethingToDo = true
						Unit:PathfindTo(MemberUnit.Target.PrimaryPart.Position)
						break
					end
				end
			end
			
			if SquadData.L == Unit.Model then --- if this member is the leader of the squad
				if SquadData.TP then --- if there is an position to attack
					if (Unit.Model.PrimaryPart.Position - SquadData.TP).Magnitude > 15 then -- if the distance of that position is over 15
						FoundSomethingToDo = true -- found something to do
						Unit.Model:PivotTo(CFrame.lookAt(Unit.Model.PrimaryPart.Position, Vector3.new(SquadData.TP.X, Unit.Model.PrimaryPart.Position.Y, SquadData.Z) ))
						--- look at that position
						Unit.L_AttackOrder:Play() --- play the attack animation order
						ChatService:Chat(Unit.Model.Head, LEADER_ATTACK_LINES[math.random(1,#LEADER_ATTACK_LINES)]) -- chat
						task.wait(Unit.L_AttackOrder.Length) -- wait for the animation to be over
						AttackOrderEvent:Fire(SquadData.TP) --- fire the attack order event
					end
				end
			end
		end
		
		if not FoundSomethingToDo then -- if there is nothing to do
			Unit.AlignOrientation.Enabled = false
			if math.random(1,5) == 1 then -- switch to look for someone to talk to with a %20 chance
				Unit.State = "LookForTalk"
			else	
				
				Unit.State = "Patrol" -- patrol
			end
			
		end
		
	end
end

function States.Moving(Unit) --- a state that happens when the unit is pathfinding. since the pathfinding function handles the movement there is nothing
	--- to do here
end

local Soldier = {}

local WaitF = task.wait

Soldier.__index = Soldier
setmetatable(Soldier,NPC_Class)

function Soldier:Cleanup() -- cleanup the unit 
	self.Run = false
end

function Soldier:PathfindTo(destination,SwitchTo,Distruptable) --- a function to make the unit pathfind to
	PathfindingScript.PathfindToHuman(self, destination, SwitchTo, Distruptable, WaypointFunctions) 
	---self is the unit table
	--- destination is the target position
	--- switch to is the state that will be switched to when the pathfinding is over
	--- distruptable is a bool that stops the pathfinding when a target is found if true
	-- waypoint functions are functions for pathfindinglinks
end

function Soldier:Update() -- update the soldier

	if self.State then
		States[self.State](self) --- fire the function that is the units current state
	end
	
end

function Soldier.New(NPC) --- function to generate a new unit
	local Unit = NPC_Class.New(NPC) --- inherit from the npc class
	setmetatable(Unit,Soldier)
	
	local Human = NPC:WaitForChild("Humanoid") -- humanoid
	local Animator = Human:WaitForChild("Animator")  -- animator
	local HumanoidRootPart = NPC:WaitForChild("HumanoidRootPart") -- rootpart
	
	local Animations : Folder = NPC:WaitForChild("Animations") -- a folder that contains the animations
	local ValuesFolder = NPC:WaitForChild("Values") -- a folder that contains values
	
	Unit.RefreshRate = ValuesFolder:WaitForChild("RefreshRate").Value --- how often the npc updates
	Unit.FindTargetRange = ValuesFolder:WaitForChild("Range").Value --- at what range the npc finds targets
	Unit.MoveFunction = ValuesFolder:WaitForChild("MoveFunction").Value -- the move function, there is currently only one
	
	local WeaponsFolder : Folder = NPC:WaitForChild("Weapons") --- weapons folder
	Unit.CurrentWeapon = WeaponsFolder:WaitForChild("MainWeapon") --- this weapon is randomly assigned by the spawner
	
	--- weapon stats
	Unit.Damage = Unit.CurrentWeapon:GetAttribute("Damage")
	Unit.Inaccuary = Unit.CurrentWeapon:GetAttribute("Inaccuary")
	Unit.ReloadTime = Unit.CurrentWeapon:GetAttribute("ReloadTime")
	Unit.MaxAmmo = Unit.CurrentWeapon:GetAttribute("Ammo")
	Unit.FireRange = Unit.CurrentWeapon:GetAttribute("Range")
	Unit.Firerate = Unit.CurrentWeapon:GetAttribute("Firerate")
	
	--- barrel is the part where the effects are contained
	NPC.Barrel.Value = NPC.Weapons.MainWeapon.Barrel
	NPC.Torso.WeaponWeld.Part1 = Unit.CurrentWeapon.WeaponHandle
	--- weaponweld is the motor6d to play animations properly
	
	--- load animations
	Unit.FireAnim = Animator:LoadAnimation( Animations:WaitForChild("Fire") ) --- animation that plays when the npc fires
	Unit.ReloadAnim = Animator:LoadAnimation( Animations:WaitForChild("Reload") ) --- animation plays when the npc reloads
	Unit.CoverAnim = Animator:LoadAnimation(Animations:WaitForChild("Cover")) --- animation that plays when the npc is in cover
	Unit.L_TargetSpotted = Animator:LoadAnimation(Animations:WaitForChild("L_TargetSpotted")) --- squad leaders play this when an target is spotted
	Unit.L_AttackOrder = Animator:LoadAnimation(Animations:WaitForChild("L_AttackOrder")) --- squad leaders play this when an order to attack is given
	Unit.RappelAnim = Animator:LoadAnimation(Animations:WaitForChild("Rappel")) ---- rappel animation for the rappel waypoint
	
	-- timer variables, reusable for bunch of stuff
	Unit.Timer0 = 0
	Unit.Timer1 = 0
	Unit.Timer2 = 0
	
	--- object target
	Unit.ObjectT = nil
	
	--- set this since i forgot to do it in the animator
	Unit.RappelAnim.Looped = true
	
	--- alignorientation
	Unit.AlignOrientation = NPC.HumanoidRootPart:WaitForChild("AlignOrientation")
	
	-- variables that change constantly
	Unit.State = "DecideState"
	Unit.Ammo = Unit.MaxAmmo
	Unit.Target = nil
	Unit.Cover = nil
	Unit.CanFire = true
	Unit.Moving = false
	
	Unit.Squad = NPC.Squad.Value or nil --- set the units squad
	
	if Unit.Squad then -- if there is a squad
		Unit.TargetSpottedConnection = TargetSpottedEvent.Event:Connect(function(Target) -- set up the target spotted connection
			if DistruptableStates[Unit.State] and Target then -- if there is a target and the units state is distruptable
				if not (NPCs_Module.Squads[Unit.Squad].L == NPC) then --- if not the member is the squad leader
					ChatService:Chat(Unit.Model.Head, COPY_LINES[math.random(1,#COPY_LINES)]) --- chat the understood lines
				end
				Unit:PathfindTo(Target.PrimaryPart.Position, "DecideState", true) --- pathfind to that target
			end	
		end)
		
		Unit.AttackOrderConnection = AttackOrderEvent.Event:Connect(function(TargetPosition) --- an event that plays when the squad leader gives the order to attack
			if DistruptableStates[Unit.State] and TargetPosition then -- if there is a target and the units state is distruptable
				if not (NPCs_Module.Squads[Unit.Squad].L == NPC) then--- if not the member is the squad leader
					ChatService:Chat(Unit.Model.Head, COPY_LINES[math.random(1,#COPY_LINES)])--- chat the understood lines
				end
				Unit:PathfindTo(TargetPosition, "DecideState", true)--- pathfind to that target position
			end
		end)
	end
	
	if not (Unit.Squad == "") then --- if there is a squad
		local Squad = NPCs_Module.Squads[Unit.Squad] --- check for the squad in the squads table
		if Squad then -- if the squad exists
			table.insert(NPCs_Module.Squads[Unit.Squad].M, NPC ) --- insert the model to the squads members table
		else
			NPCs_Module.Squads[Unit.Squad] = {L = NPC, M = {NPC}, TP = nil} --- make the squad if there is no squad
		end		
	end
	
	Unit.MainLoop = coroutine.create(function() --- main npc loop, handles movement and stuff
		while Human.Health > 0 and Unit.Run do -- while the npc is alive
			
			Unit:Update() -- update
			
			WaitF(Unit.RefreshRate) -- wait refresh rate
		end
		Unit.Run = false
		Debris:AddItem(NPC,10)
		
		if Unit.Cover then --- if the unit was in cover, set the covers occupied to false
			CoversModule.Covers[Unit.Cover][2] = false
		end
		
		if Unit.Squad then -- if the unit has a squad
			local Squad = NPCs_Module.Squads[Unit.Squad]
			if Squad then
				table.remove(Squad.M, table.find(Squad.M, NPC)) -- remove the unit from the squads member list
				
				if #Squad.M < 0 then-- if all of the squad is dead, destroy the squad
					NPCs_Module.Squads[Unit.Squad] = nil
				else 
					if Squad.L == NPC then -- if the unit was the squad leader, assign a new member as the squad leader
						Squad.L = Squad.M[1]
					end
				end
				
			end
		end
		
		-- disconnect events
		if Unit.TargetSpottedConnection then
			Unit.TargetSpottedConnection:Disconnect() 
		end
		
		if Unit.AttackOrderConnection then
			Unit.AttackOrderConnection:Disconnect()
		end
		
		Noob_Remotes.Effects.Ragdoll:FireAllClients(NPC) --- fire the ragdoll remote
	end)
	
	Unit.FireLoop = coroutine.create(function() -- this loop handles firing
		while Unit.Run  do -- while the unit is alive
			local Target = GeneralFunctions.FindClosestVisibleEnemy(Unit,Unit.FireRange) --- find a target
			if Unit.CanFire and Target then --- if can fire and target
				if Unit.Ammo > 0 then -- if has ammo
					Unit.Ammo = Unit.Ammo - 1
					Unit.Target = Target -- set the target variable
					Unit.AlignOrientation.CFrame = CFrame.lookAt(HumanoidRootPart.Position, Target.PrimaryPart.Position) -- look at target
					Unit.FireAnim:Play() -- play anim
					GeneralFunctions.FireBullet(Unit,Target) -- fire bullet
				else
					-- reload
					Unit.ReloadAnim:Play()
					NPC.Barrel.Value.Reload:Play()
					task.wait(Unit.ReloadAnim.Length)
					Unit.Ammo = Unit.MaxAmmo
				end
				
			else
				Unit.Target = nil
			end
			
			WaitF(Unit.Firerate)
		end
	end)
	
	
	--- resume cororoutines
	local Success,Error = coroutine.resume(Unit.FireLoop)
	print(Success,Error)
	
	local Success,Error = coroutine.resume(Unit.MainLoop)
	print(Success,Error)
	
	return Unit
end

return Soldier
