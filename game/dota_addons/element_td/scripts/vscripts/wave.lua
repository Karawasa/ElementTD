Wave = createClass({
		constructor = function(self, playerID, waveNumber)
			self.playerID = playerID
			self.playerData = GetPlayerData(self.playerID)

			self.waveNumber = waveNumber
			self.creepsRemaining = CREEPS_PER_WAVE
			self.creeps = {}
			self.startTime = 0
			self.endTime = 0
			self.leaks = 0
			self.kills = 0
			self.callback = nil
		end
	},
{}, nil)

function Wave:GetWaveNumber()
	return self.waveNumber
end

function Wave:GetCreeps()
	return self.creeps
end

-- call the callback when the player beats this wave
function Wave:SetOnCompletedCallback(func)
	self.callback = func
end

function Wave:OnCreepKilled(index)
	if self.creeps[index] then
		self.creeps[index] = nil
		self.creepsRemaining = self.creepsRemaining - 1
		local creep = EntIndexToHScript(index)
		if IsValidEntity(creep) and creep:HasAbility("creep_ability_bulky") then
		    self.creepsRemaining = self.creepsRemaining - 1
		end
		self.kills = self.kills + 1

		-- Remove from scoreboard count
		local playerData = GetPlayerData(self.playerID)
		playerData.remaining = playerData.remaining - 1		
		UpdateScoreboard(self.playerID)

		if self.creepsRemaining <= 0 and self.callback then
			self.endTime = GameRules:GetGameTime()
			self.callback()
		end
	end
end

function Wave:RegisterCreep(index)
	if not self.creeps[index] then
		self.creeps[index] = index
	else
		Log:warn("Attemped to register creep " .. index .. " which is already register!")
	end
end

function Wave:SpawnWave()
	local playerData = GetPlayerData(self.playerID)
	local difficulty = playerData.difficulty
	local startPos = EntityStartLocations[playerData.sector + 1]
	local entitiesSpawned = 0
	local sector = playerData.sector + 1
	local ply = PlayerResource:GetPlayer(self.playerID)

	if ply then
		EmitSoundOnClient("ui.contract_complete", ply)
	end

	local time_between_spawns = 0.5
	self.startTime = GameRules:GetGameTime() + time_between_spawns
	self.leaks = 0
	self.kills = 0
	local creepBossSequence = 0
	local creepBossAbilities = CreepBoss:GetAbilityList()
	local numAbilities = #creepBossAbilities

	self.spawnTimer = Timers:CreateTimer(time_between_spawns, function()
		if playerData.health == 0 then
			return nil
		end
		local entity = SpawnEntity(WAVE_CREEPS[self.waveNumber], self.playerID, startPos, self.waveNumber)
		if entity then
			self:RegisterCreep(entity:entindex())
			entity:SetForwardVector(Vector(0, -1, 0))
			entity:CreatureLevelUp(self.waveNumber-entity:GetLevel())
			entity.waveObject = self
			entity.waveNumber = self.waveNumber
			entitiesSpawned = entitiesSpawned + 1

			-- Set health
			local health = WAVE_HEALTH[self.waveNumber] * difficulty:GetHealthMultiplier()
			entity:SetMaxHealth(health)
			entity:SetBaseMaxHealth(health)
			entity:SetHealth(entity:GetMaxHealth())

			-- Boss mode
			if self.waveNumber == WAVE_COUNT and not EXPRESS_MODE then
				local bossHealth = WAVE_HEALTH[self.waveNumber] * difficulty:GetHealthMultiplier() * (math.pow(1.3,playerData.bossWaves))
				entity:SetMaxHealth(bossHealth)
				entity:SetBaseMaxHealth(bossHealth)
				entity:SetHealth(entity:GetMaxHealth())
				entity.waveNumber = playerData.bossWaves

				-- Choose an ability in sequence
				if CHALLENGE_MODE then
					creepBossAbilities = CreepBoss:GetAbilityList()

					-- Do not let count entities spawned count go over CREEPS_PER_WAVE
					local rand1 = math.random(#creepBossAbilities)
					local rand2 = math.random(#creepBossAbilities - 1)
					if entitiesSpawned == CREEPS_PER_WAVE then
						-- Last creep in wave cannot be bulky
						if rand1 == 1 then
							rand1 = rand1 + 1
						end
						if rand2 == 1 then
							rand2 = rand2 + 1
						end
					end

					local ability1 = table.remove(creepBossAbilities, rand1)
					local ability2 = table.remove(creepBossAbilities, rand2)

					entity.scriptObject.abilities = {}
					entity.scriptObject.abilities[ability1] = AddAbility(entity, ability1) 
					entity.scriptObject.abilities[ability2] = AddAbility(entity, ability2) 
					entity.random_abilities = {[ability1] = true, [ability2] = true}
				else
					creepBossSequence = (creepBossSequence % numAbilities) + 1
					local abilityName = creepBossAbilities[creepBossSequence]
					entity.random_abilities = {[abilityName] = true}
					entity.scriptObject.abilities = {}
					entity.scriptObject.abilities[abilityName] = AddAbility(entity, abilityName)
				end
				
			end

			-- Set bounty
			local bounty = difficulty:GetBountyForWave(self.waveNumber)

			-- Bulky: double spawn time, double bounty, half creep count
			if entity:HasAbility("creep_ability_bulky") then
				time_between_spawns = 1
				entitiesSpawned = entitiesSpawned + 1
				bounty = bounty * 2
			else
				time_between_spawns = 0.5
			end

			entity:SetMaximumGoldBounty(bounty)
			entity:SetMinimumGoldBounty(bounty)

			entity.scriptObject:OnSpawned() -- called the OnSpawned event

			CreateMoveTimerForCreep(entity, sector)
			if entitiesSpawned == CREEPS_PER_WAVE then
				self.endSpawnTime = GameRules:GetGameTime()
				ClosePortalForSector(self.playerID, sector)

				-- Endless waves are started as soon as the wave finishes spawning
				if GameSettings:GetEndless() == "Endless" then
					playerData.nextWave = playerData.nextWave + 1

					-- Rush Boss Waves just follow the same classic spawn rules, skip
			        if playerData.nextWave > WAVE_COUNT and not EXPRESS_MODE then
					
			        	--[[playerData.bossWaves = playerData.bossWaves + 1
			            Log:info("Spawning Rush boss wave " .. playerData.bossWaves .. " for ["..self.playerID.."] ".. playerData.name)
			            ShowBossWaveMessage(self.playerID, playerData.bossWaves)
			            UpdateWaveInfo(self.playerID, WAVE_COUNT)
			            SpawnWaveForPlayer(self.playerID, WAVE_COUNT) -- spawn dat boss wave]]
			            
			            return nil
			        elseif playerData.nextWave > WAVE_COUNT and EXPRESS_MODE then
			        	return nil
			        end
					StartBreakTime(self.playerID, GetPlayerDifficulty(self.playerID):GetWaveBreakTime(playerData.nextWave))

					-- Update UI for dead players
					StartBreakTime_DeadPlayers(self.playerID, GetPlayerDifficulty(self.playerID):GetWaveBreakTime(playerData.nextWave), playerData.nextWave)
				else
					if self.waveNumber ~= WAVE_COUNT then
						-- Start clock timer on the UI
						CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(self.playerID), "etd_start_wave_clock", {threshold = FAST_THRESHOLD})
					end
				end
				return nil
			else
				return time_between_spawns
			end
		end
	end)
end
