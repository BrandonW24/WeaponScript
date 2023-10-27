do -- script WeaponScript 
	
	--[[
	Personal Notes
	- If the gun position wise glitches out on other clients, the issue is related to runtime errors on the script (even if it doesn't print it out to the console).
	- When it comes to syncing sounds, I tried syncing with the optional parameter to reduce redudancy however on newly spawned prefabs the optional parameter gets lost somehow? (NEW NOTE: It's because AudioClip is not a serialized for a paremeter)
	- For the audio sources, when a new prefab is spawned with a mixer group assigned, the audio seemingly actually gets lost? (checked client volume settings as well)
	]]--

	-- get reference to the script
	local WeaponScript = LUA.script;

	--|||||||||||||||||||||||||||||||||||||||||||||| PUBLIC VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| PUBLIC VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| PUBLIC VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||

	--gun fire
	local bool_semiFire = SerializedField("(Fire) Semi Fire", Bool);
	local number_fireRate = SerializedField("(Fire) Fire Rate", Number);
	local number_prefireDelay = SerializedField("(Fire) Prefire Delay", Number);
	local number_damageAmount = SerializedField("(Fire) Damage Points Amount", Number);
	local number_randomSpread = SerializedField("(Fire) Random Spread Amount", Number);
	local number_raycastForce = SerializedField("(Fire) Raycast Physics Force", Number);
	local number_raycastHitEffectHeightOffset = SerializedField("(Fire) Raycast Hit Effect Height Offset", Number);
	local bool_projectileBased = SerializedField("(Fire) Projectile Based", Bool);
	local number_projectileForce = SerializedField("(Fire) Projectile Force", Number);

	--gun reloading
	local number_clips = SerializedField("(Reloading) Clips", Number);
	local number_roundsInClip = SerializedField("(Reloading) Rounds In Clip", Number);
	local number_reloadTime = SerializedField("(Reloading) Reload Time", Number);
	local bool_infiniteAmmo = SerializedField("(Reloading) Infinite Ammo", Bool);

	--gun objects
	local gameObject_barrelOrigin = SerializedField("(Objects) Barrel Origin", GameObject);
	local gameObject_projectilePrefab = SerializedField("(Objects) Projectile", GameObject);
	local gameObject_raycastHitEffectPrefab = SerializedField("(Objects) Raycast Hit Effect", GameObject);
	local gameObject_playerHitPrefab = SerializedField("Player Hit Prefab", GameObject);
	local textMesh_gunInfoText = SerializedField("(Objects) Info Text Mesh", TextMesh);
	local playableDirector_firingAnimation = SerializedField("(Objects) Playable Director Animation", PlayableDirector);
	local gameObject_localPlayerObjects = SerializedField("(Objects) Local Player Objects", GameObject);
	local gameObject_nonLocalPlayerObjects = SerializedField("(Objects) Non Local Player Objects", GameObject);
	local textMesh_gunPlayerHealthText = SerializedField("(Objects) Info Health Text", TextMesh);
	local gameObject_prefireLazerPointer = SerializedField("(Objects) Prefire Lazer Pointer", GameObject);
	local gameObject_bulletTrailPrefab = SerializedField("(Objects) Bullet Trail", GameObject);

	--gun sounds
	local audioClip_prefireSound = SerializedField("(Sounds) Prefire Sound", AudioClip);
	local audioClip_fireSound = SerializedField("(Sounds) Fire Sound", AudioClip);
	local audioClip_reloadSound = SerializedField("(Sounds) Reload Sound", AudioClip);
	local audioClip_emptySound = SerializedField("(Sounds) Empty Sound", AudioClip);
	local audioClip_grabSound = SerializedField("(Sounds) Grab Sound", AudioClip);
	local audioClip_dropSound = SerializedField("(Sounds) Drop Sound", AudioClip);

	--|||||||||||||||||||||||||||||||||||||||||||||| SERVER VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| SERVER VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| SERVER VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--these variables are syncronized across clients
	--NOTE: kept names small since they can affect server sync performance (I would prefer to have readable names... but they are costly)

	local server_number_currentRoundsInClip = SyncVar(WeaponScript, "a");
	local server_number_currentClips = SyncVar(WeaponScript, "b");

	--|||||||||||||||||||||||||||||||||||||||||||||| PRIVATE VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| PRIVATE VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| PRIVATE VARIABLES ||||||||||||||||||||||||||||||||||||||||||||||

	--player property keys
	local string_PLAYERKEY_serverIsDead = "IsDead";
	local string_PLAYERKEY_currentlyInMatch = "CurrentlyInMatch";

	local number_currentRoundsInClip = 0;
	local number_currentClips = 0;
	local number_currentfireRate = 0;
	local number_nextFireTime = 0;
	local number_nextPrefireTime = 0;
	local number_nextReloadTime = 0;

	local bool_firedOnce = false;
	local bool_isGrabbed = false;
	local bool_isReloading = false;
	local bool_isHoldingTriggerDown = false;

	local audioSource_weaponSource = nil;
	local mlgrab_weaponGrab = nil;
	local mlplayer_currentGunOwner = nil;
	local number_currentGunOwnerActorID = nil;
	local newGamePlayer_currentGunOwner = nil;
	local number_playerHealth = nil;
	local hold_bool = true;
	local obj 				= WeaponScript.gameObject;

	--|||||||||||||||||||||||||||||||||||||||||||||| ACTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| ACTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| ACTIONS ||||||||||||||||||||||||||||||||||||||||||||||

	local function SetGunLocalObjects()
		if (gameObject_localPlayerObjects) and (gameObject_nonLocalPlayerObjects) then 
			if (mlplayer_currentGunOwner ~= nil) and (mlplayer_currentGunOwner.isLocal == true) then
				gameObject_localPlayerObjects.SetActive(true);
				gameObject_nonLocalPlayerObjects.SetActive(false);
			else
				gameObject_localPlayerObjects.SetActive(false);
				gameObject_nonLocalPlayerObjects.SetActive(true);
			end
		end
	end

	local function UpdateText()
		if(number_roundsInClip == nil) or (textMesh_gunInfoText == nil) then return end

		local roundsLeft = number_currentClips * number_roundsInClip;

		if(bool_isGrabbed == true) then
			textMesh_gunInfoText.text = tostring(number_currentRoundsInClip) .. "/" .. tostring(roundsLeft);

			--mlplayer_currentGunOwner.SetProperty("AmmoCounter", tostring(number_currentRoundsInClip) .. "/" .. tostring(roundsLeft));

			number_playerHealth = mlplayer_currentGunOwner.Health;
			textMesh_gunPlayerHealthText.text = "HP " .. tostring(number_playerHealth);
		else
			textMesh_gunInfoText.text = "";
			textMesh_gunPlayerHealthText.text = "";
		end
	end

	local function ReplenishWeapon()
		if (mlplayer_currentGunOwner ~= nil) and (mlplayer_currentGunOwner.isLocal == true) then
			number_currentClips = number_clips;

			if (bool_infiniteAmmo == true) then
				number_currentRoundsInClip = 99999;
			else
				number_currentRoundsInClip = number_roundsInClip;
			end

			server_number_currentRoundsInClip.SyncSet(number_currentRoundsInClip);
			server_number_currentClips.SyncSet(number_currentClips);
		end
	end

	--|||||||||||||||||||||||||||||||||||||||||||||| MAIN GUN FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| MAIN GUN FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| MAIN GUN FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||

	--NOTE: I want to reduce code redudancy, and because AudioClip is not a serialized object that can be passed through LuaEvent calls..
	--we can get around it by just passing in a single length string (5 + [length of string] bytes) which is serialized, and using that value to indicate which sound to play.
	--considered doing a value but since numbers in lua are considered doubles (64 bit/8 bytes or 9 bytes because of photon) a single length string would be smaller
	local function PlayGunSound(soundStringIdentifier)
		if(string.match(soundStringIdentifier, "F")) then --FIRING
			audioSource_weaponSource.PlayOneShot(audioClip_fireSound);
		elseif(string.match(soundStringIdentifier, "R")) then --RELOADING
			audioSource_weaponSource.PlayOneShot(audioClip_reloadSound);
		elseif(string.match(soundStringIdentifier, "E")) then --EMPTY
			audioSource_weaponSource.PlayOneShot(audioClip_emptySound);
		elseif(string.match(soundStringIdentifier, "P")) then --PREFIRE
			audioSource_weaponSource.PlayOneShot(audioClip_prefireSound);
		elseif(string.match(soundStringIdentifier, "G")) then --GRAB
			audioSource_weaponSource.PlayOneShot(audioClip_grabSound);
		elseif(string.match(soundStringIdentifier, "D")) then --DROP
			audioSource_weaponSource.PlayOneShot(audioClip_dropSound);
		end
	end

	local function StopSounds()
		audioSource_weaponSource.Stop();
	end

	local function SpawnHitEffect(position)
		Object.Instantiate(gameObject_raycastHitEffectPrefab, position, Quaternion(0, 0, 0, 0));
	end

	local function SpawnProjectile(position)

		local number_randomX = math.random(-number_randomSpread, number_randomSpread);
		local number_randomY = math.random(-number_randomSpread, number_randomSpread);
		local vector3_randomSpreadVector = Vector3(number_randomX, number_randomY, 1); --Vector3 type
		local vector3_transformedRandomSpreadVector =  gameObject_barrelOrigin.transform.TransformDirection(vector3_randomSpreadVector); --Vector3 type
		local vector3_finalBarrelVector = Vector3.Normalize(gameObject_barrelOrigin.transform.forward + vector3_transformedRandomSpreadVector); --Vector3 type

		Debug.log("is this gun projectile based? ".. tostring(bool_projectileBased));

		Debug.log("Projectile created");
		local gameObject_newProjectile = Object.Instantiate(gameObject_projectilePrefab, gameObject_barrelOrigin.transform.position, gameObject_barrelOrigin.transform.rotation); --GameObject type
		local rigidbody_newProjectileRigidbody = gameObject_newProjectile.GetComponent(Rigidbody); --Rigidbody type
		local vector3_projectileForceVector = vector3_finalBarrelVector * number_projectileForce; --Vector3 type
		rigidbody_newProjectileRigidbody.AddForce(vector3_projectileForceVector);
		Debug.log("Applying force to projectile created");

		rigidbody_newProjectileRigidbody.velocity = gameObject_barrelOrigin.transform.forward * number_projectileForce;

		--if hits own gun
		local newProjectileCollider = gameObject_newProjectile.GetComponent(Collider);
		local gun_collider = obj.GetComponent(Collider);
		Physics.IgnoreCollision(gun_collider, newProjectileCollider, true);


	end

	local function SpawnPlayerHitEffect(position)
		Object.Instantiate(gameObject_playerHitPrefab, position, Quaternion(0, 0, 0, 0));
	end

	local function SpawnTrailEffect(vector3_startPosition, vector3_endPosition)
		local vector3_averagedPosition = Vector3(0, 0, 0);
		vector3_averagedPosition.x = (vector3_startPosition.x + vector3_endPosition.x) / 2.0;
		vector3_averagedPosition.y = (vector3_startPosition.y + vector3_endPosition.y) / 2.0;
		vector3_averagedPosition.z = (vector3_startPosition.z + vector3_endPosition.z) / 2.0;

		local vector3_direction = Vector3(0, 0, 0);
		vector3_direction.x = (vector3_startPosition.x - vector3_endPosition.x);
		vector3_direction.y = (vector3_startPosition.y - vector3_endPosition.y);
		vector3_direction.z = (vector3_startPosition.z - vector3_endPosition.z);
		
		local quaternion_newRotation = Quaternion.LookRotation(vector3_direction, Vector3.up);

		local gameObject_bulletTrailInstance = Object.Instantiate(gameObject_bulletTrailPrefab, vector3_averagedPosition, quaternion_newRotation);

		local number_distance = Vector3.Distance(vector3_startPosition, vector3_endPosition);
		local vector3_newScale = Vector3(gameObject_bulletTrailInstance.transform.localScale.x, gameObject_bulletTrailInstance.transform.localScale.y, number_distance);
		gameObject_bulletTrailInstance.transform.localScale = vector3_newScale;
	end

	local function LocalForceRelease()
		mlgrab_weaponGrab.ForceRelease();
	end

	local function Reload()
		if (Time.time > number_nextReloadTime) then

			if (number_currentClips > 0) then
				--Invoke PlayGunSound() to play a reloading sound across all clients
				LuaEvents.InvokeLocalForAll(WeaponScript, "B", "R");

				number_currentRoundsInClip = number_roundsInClip;
				number_currentClips = number_currentClips - 1;

				server_number_currentRoundsInClip.SyncSet(number_currentRoundsInClip);
				server_number_currentClips.SyncSet(number_currentClips);
			else
				--Invoke PlayGunSound() to play an empty sound across all clients
				LuaEvents.InvokeLocalForAll(WeaponScript, "B", "E");
			end

			number_nextReloadTime = Time.time + number_reloadTime;
		end
	end

	local function FireEffects()
		if (playableDirector_firingAnimation) then
			playableDirector_firingAnimation.Stop();
			playableDirector_firingAnimation.Play();
		end
	end

	local function FireLogic()
		if (Time.time < number_nextReloadTime) then return end

		if (number_currentRoundsInClip <= 0) then
			Reload();
			return 
        end

		if (bool_semiFire == true and bool_firedOnce == true) then return end

		if (Time.time > number_nextFireTime) then
			number_nextFireTime = Time.time + number_currentfireRate;

			number_currentRoundsInClip = number_currentRoundsInClip - 1;
			server_number_currentRoundsInClip.SyncSet(number_currentRoundsInClip);

			--Invoke FireEffects() across all clients
			LuaEvents.InvokeLocalForAll(WeaponScript, "A");

			local number_randomX = math.random(-number_randomSpread, number_randomSpread);
			local number_randomY = math.random(-number_randomSpread, number_randomSpread);
			local vector3_randomSpreadVector = Vector3(number_randomX, number_randomY, 1); --Vector3 type
			local vector3_transformedRandomSpreadVector =  gameObject_barrelOrigin.transform.TransformDirection(vector3_randomSpreadVector); --Vector3 type
			local vector3_finalBarrelVector = Vector3.Normalize(gameObject_barrelOrigin.transform.forward + vector3_transformedRandomSpreadVector); --Vector3 type

			--Debug.log("is this gun projectile based? ".. tostring(bool_projectileBased));

			if (tostring(bool_projectileBased) == "true") then
				LuaEvents.InvokeLocalForAll(WeaponScript, "H");
				
			else
				local physicRay_ray = PhysicRay(gameObject_barrelOrigin.transform.position, vector3_finalBarrelVector); --PhysicRay type

				--IMPORTANT: MAKES sure that we don't hit any triggers
				physicRay_ray.queryTriggerInteraction = QueryTriggerInteraction.Ignore;

				local bool_hit, raycastHit_cast = Physics:Raycast(physicRay_ray);

				if (bool_hit) then
					local vector3_hitPosition = raycastHit_cast.point; --Vector3 type
					local vector3_hitNormal = raycastHit_cast.normal; --Vector3 type
					local gameObject_hitObject = raycastHit_cast.transform.gameObject; --GameObject type
					local mlplayer_hitPlayer = gameObject_hitObject.GetPlayer(); --MLPlayer type
					local rigidbody_hitBody = gameObject_hitObject.GetComponent(Rigidbody); --Rigidbody type
					local mountedTurret_hitTurret = gameObject_hitObject.GetComponent(MountedTurret); --MountedTurret type
					local weaponScript_hitWeapon = gameObject_hitObject.GetComponent(WeaponScript); --WeaponScript type

					if (rigidbody_hitBody) then
						local vector3_forceVector = vector3_finalBarrelVector * number_raycastForce; --Vector3 type
						rigidbody_hitBody.AddForceAtPosition(vector3_forceVector, vector3_hitPosition);
					end

					if (mlplayer_hitPlayer) then
						if(mlplayer_hitPlayer.PlayerRoot ~= nil) then
							local newGamePlayer_player = mlplayer_hitPlayer.PlayerRoot.GetComponent(NewGamePlayer);

							--additional nil checks
							if(newGamePlayer_player ~= nil) then
								if(newGamePlayer_player.script ~= nil) then
									newGamePlayer_player.script.TakeDamage(number_damageAmount, number_currentGunOwnerActorID);

									--Invoke SpawnPlayerHitEffect() across all clients
									LuaEvents.InvokeLocalForAll(WeaponScript, "G", vector3_hitPosition);
								end
							end
						end
					end

					if (mountedTurret_hitTurret) then
						mountedTurret_hitTurret.script.ApplyDamageToPlayer(number_damageAmount, number_currentGunOwnerActorID);
					end

					if (weaponScript_hitWeapon) then
						weaponScript_hitWeapon.script.ApplyDamageToPlayer(number_damageAmount, number_currentGunOwnerActorID);
					end

					if (gameObject_raycastHitEffectPrefab) then
						local vector3_newHitPosition = vector3_hitPosition + (vector3_hitNormal * number_raycastHitEffectHeightOffset); --Vector3 type

						--SELF NOTE: The parameter types that you pass through with these calls have to be serializable
						--https://sdk.massiveloop.com/getting_started/scripting/SerializableTypes.html
						--Invoke SpawnHitEffect() across all clients
						LuaEvents.InvokeLocalForAll(WeaponScript, "D", vector3_newHitPosition);
					end

					if (gameObject_bulletTrailPrefab) then
						--Invoke SpawnTrailEffect() across all clients
						LuaEvents.InvokeLocalForAll(WeaponScript, "F", gameObject_barrelOrigin.transform.position, vector3_hitPosition);
					end
				end
			end

			--Invoke PlayGunSound() across all clients
			LuaEvents.InvokeLocalForAll(WeaponScript, "B", "F");

			if (bool_semiFire == true) then 
				bool_firedOnce = true;
			end
		end
	end

	--|||||||||||||||||||||||||||||||||||||||||||||| MLGRAB CALLBACKS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| MLGRAB CALLBACKS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| MLGRAB CALLBACKS ||||||||||||||||||||||||||||||||||||||||||||||

	local function OnPrimaryTriggerDown()
		if(mlplayer_currentGunOwner.GetProperty(string_PLAYERKEY_currentlyInMatch) == true) and (mlplayer_currentGunOwner.GetProperty(string_PLAYERKEY_serverIsDead) == false) then
			bool_isHoldingTriggerDown = true;
			number_nextPrefireTime = Time.time + number_prefireDelay;

			if (number_prefireDelay > 0) then
				--Invoke PlayGunSound() to play a prefire sound across all clients
				LuaEvents.InvokeLocalForAll(WeaponScript, "B", "P");
			end

		else
			bool_isHoldingTriggerDown = false;
		end
	end

	local function OnPrimaryTriggerUp()
		bool_isHoldingTriggerDown = false;

		if (number_prefireDelay > 0) and (Time.time < number_nextPrefireTime) and (bool_isGrabbed == true) then
			--Invoke StopSounds() across all clients
			LuaEvents.InvokeLocalForAll(WeaponScript, "C");
		end

		number_nextPrefireTime = 0;

		if (bool_semiFire == true) then
			bool_firedOnce = false;
		end
	end

	local function OnPrimaryGrabBegin()
		bool_isGrabbed = true;

		--Invoke PlayGunSound() to play a grab sound across all clients
		LuaEvents.InvokeLocalForAll(WeaponScript, "B", "G");

		mlplayer_currentGunOwner = mlgrab_weaponGrab.CurrentUser; --MLPlayer type
		number_currentGunOwnerActorID = mlplayer_currentGunOwner.ActorID; --String type

		newGamePlayer_currentGunOwner = mlplayer_currentGunOwner.PlayerRoot.GetComponent(NewGamePlayer);
		newGamePlayer_currentGunOwner.script.SetHasWeapon(true);
	end

	local function OnPrimaryGrabEnd()
		bool_isGrabbed = false;

		--Invoke PlayGunSound() to play a drop sound across all clients
		LuaEvents.InvokeLocalForAll(WeaponScript, "B", "D");

		mlplayer_currentGunOwner = nil;
		number_currentGunOwnerActorID = nil;

		newGamePlayer_currentGunOwner.script.SetHasWeapon(false);
		newGamePlayer_currentGunOwner = nil;
	end

	local function OnSecondaryGrabBegin()
		--Invoke PlayGunSound() to play a grab sound across all clients
		LuaEvents.InvokeLocalForAll(WeaponScript, "B", "G");
	end

	local function OnSecondaryGrabEnd()
		--Invoke PlayGunSound() to play a drop sound across all clients
		LuaEvents.InvokeLocalForAll(WeaponScript, "B", "D");
	end

	--|||||||||||||||||||||||||||||||||||||||||||||| SERVER DATA CALLBACKS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| SERVER DATA CALLBACKS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| SERVER DATA CALLBACKS ||||||||||||||||||||||||||||||||||||||||||||||

	local function server_number_currentRoundsInClip_OnChange(value)
		number_currentRoundsInClip = value;
	end

	local function server_number_currentRoundsInClip_OnSet(value)
		number_currentRoundsInClip = value;
	end

	local function server_number_currentClips_OnChange(value)
		number_currentClips = value;
	end

	local function server_number_currentClips_OnSet(value)
		number_currentClips = value;
	end

	--|||||||||||||||||||||||||||||||||||||||||||||| PUBLIC FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| PUBLIC FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| PUBLIC FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||

	function WeaponScript.EquipPowerupAmmo()
		ReplenishWeapon();
    end

	function WeaponScript.ResetGun()
		number_currentfireRate = number_fireRate;

		ReplenishWeapon();
	end

	function WeaponScript.CanGetAmmoPowerup()
		if(number_currentRoundsInClip < number_roundsInClip) or (number_currentClips < number_clips) then
			return true;
		else
			return false;
		end
	end

	function WeaponScript.ForceRelease()
		--Invoke LocalForceRelease() across all clients
		LuaEvents.InvokeLocalForAll(WeaponScript, "E");
	end

	function WeaponScript.IsHeld()
		if(mlplayer_currentGunOwner == nil) then
			return false;
		else
			return true;
		end
	end

	function WeaponScript.ApplyDamageToPlayer(number_damageAmount, string_responsiblePlayerActorID)
		local newGamePlayerObject = mlplayer_currentGunOwner.PlayerRoot.GetComponent(NewGamePlayer);
		newGamePlayerObject.script.TakeDamage(number_damageAmount, string_responsiblePlayerActorID);
	end

	--|||||||||||||||||||||||||||||||||||||||||||||| UNITY FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| UNITY FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||
	--|||||||||||||||||||||||||||||||||||||||||||||| UNITY FUNCTIONS ||||||||||||||||||||||||||||||||||||||||||||||

	function WeaponScript.Start()
		audioSource_weaponSource = WeaponScript.gameObject.GetComponent(AudioSource);
		mlgrab_weaponGrab = WeaponScript.gameObject.GetComponent(MLGrab);

		--NOTE: kept names small since they can affect server sync performance (I would prefer to have readable names... but they are costly)
		LuaEvents.AddLocal(WeaponScript, "A", FireEffects);
		LuaEvents.AddLocal(WeaponScript, "B", PlayGunSound);
		LuaEvents.AddLocal(WeaponScript, "C", StopSounds);
		LuaEvents.AddLocal(WeaponScript, "D", SpawnHitEffect);
		LuaEvents.AddLocal(WeaponScript, "E", LocalForceRelease);
		LuaEvents.AddLocal(WeaponScript, "F", SpawnTrailEffect);
		LuaEvents.AddLocal(WeaponScript, "G", SpawnPlayerHitEffect);
		LuaEvents.AddLocal(WeaponScript, "H", SpawnProjectile);

		server_number_currentRoundsInClip.OnVariableChange.Add(server_number_currentRoundsInClip_OnChange);
		server_number_currentRoundsInClip.OnVariableSet.Add(server_number_currentRoundsInClip_OnSet);
		server_number_currentClips.OnVariableChange.Add(server_number_currentClips_OnChange);
		server_number_currentClips.OnVariableSet.Add(server_number_currentClips_OnSet);

		mlgrab_weaponGrab.OnPrimaryTriggerDown.Add(OnPrimaryTriggerDown);
		mlgrab_weaponGrab.OnPrimaryTriggerUp.Add(OnPrimaryTriggerUp);
		mlgrab_weaponGrab.OnPrimaryGrabBegin.Add(OnPrimaryGrabBegin);
		mlgrab_weaponGrab.OnPrimaryGrabEnd.Add(OnPrimaryGrabEnd);
		mlgrab_weaponGrab.OnSecondaryGrabBegin.Add(OnSecondaryGrabBegin);
		mlgrab_weaponGrab.OnSecondaryGrabEnd.Add(OnSecondaryGrabEnd);

		number_currentfireRate = number_fireRate;
		number_currentClips = number_clips;
		number_currentRoundsInClip = number_roundsInClip;

		UpdateText();
	end

	function WeaponScript.Update()
		if (mlplayer_currentGunOwner ~= nil) and (mlplayer_currentGunOwner.isLocal == true) then
			if (bool_isHoldingTriggerDown == true) then
				if (Time.time > number_nextPrefireTime) then
					FireLogic();
				else
					if(gameObject_prefireLazerPointer ~= nil) then
						gameObject_prefireLazerPointer.SetActive(true);
					end
				end
			else
				if(gameObject_prefireLazerPointer ~= nil) then
					gameObject_prefireLazerPointer.SetActive(false);
				end
			end
		end

		SetGunLocalObjects();
		UpdateText();
	end
end