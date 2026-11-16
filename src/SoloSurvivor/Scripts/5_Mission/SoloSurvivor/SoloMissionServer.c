static const string SOLO_COMMANDS_PATH = "$profile:SoloSurvivor/commands.txt";
static const string SOLO_STATUS_PATH = "$profile:SoloSurvivor/status.json";
static const int SOLO_MAX_COMMAND_LINES = 50;

modded class MissionServer
{
	protected ref SoloSurvivorSettings m_SoloSettings;
	protected ref map<string, PlayerBase> m_SoloProtectedPlayers;
	protected ref SoloEventManager m_SoloEvents;
	protected ref SoloDayCounter m_SoloDays;

	override void OnInit()
	{
		super.OnInit();
		m_SoloSettings = SoloSurvivorSettings.Load();
		m_SoloProtectedPlayers = new map<string, PlayerBase>;
		Print("[SoloSurvivor] Settings loaded, safe zones: " + m_SoloSettings.SafeZones.Count());

		if (m_SoloSettings.SafeZones.Count() > 0)
			GetGame().GetCallQueue(CALL_CATEGORY_GAMEPLAY).CallLater(SoloUpdateSafeZones, 2000, true);

		GetGame().GetCallQueue(CALL_CATEGORY_SYSTEM).CallLater(SoloPollCommands, 2000, true);
		GetGame().GetCallQueue(CALL_CATEGORY_SYSTEM).CallLater(SoloWriteStatus, 5000, true);

		if (m_SoloSettings.AlwaysDay)
		{
			SoloKeepDaytime();
			GetGame().GetCallQueue(CALL_CATEGORY_SYSTEM).CallLater(SoloKeepDaytime, 30000, true);
		}

		if (m_SoloSettings.ShowDayCounter)
		{
			m_SoloDays = new SoloDayCounter();
			GetGame().GetCallQueue(CALL_CATEGORY_GAMEPLAY).CallLater(m_SoloDays.Tick, 10000, true);
		}

		SoloWriteTerrain();

		m_SoloEvents = new SoloEventManager(m_SoloSettings);
		GetGame().GetCallQueue(CALL_CATEGORY_GAMEPLAY).CallLater(m_SoloEvents.TickEvents, 10000, true);
	}

	// The launcher can't read terrain heights, so the server measures the event areas once per start for it.
	protected void SoloWriteTerrain()
	{
		string worldName;
		GetGame().GetWorldName(worldName);
		worldName.ToLower();

		SoloTerrainFile terrain = new SoloTerrainFile();
		terrain.MapName = worldName;
		array<float> offsetsX = {0.0, 300.0, 0.0, -300.0, 0.0};
		array<float> offsetsZ = {0.0, 0.0, 300.0, 0.0, -300.0};
		foreach (SoloEventLocation loc : m_SoloSettings.Events.Locations)
		{
			string locationMap = loc.MapName;
			locationMap.ToLower();
			if (locationMap != "" && locationMap != worldName)
				continue;

			SoloTerrainLocation measured = new SoloTerrainLocation();
			measured.Name = loc.Name;
			for (int i = 0; i < offsetsX.Count(); i++)
			{
				float x = loc.Position[0] + offsetsX[i];
				float z = loc.Position[2] + offsetsZ[i];
				if (GetGame().SurfaceIsSea(x, z) || GetGame().SurfaceIsPond(x, z))
					continue;
				measured.Points.Insert(Vector(x, GetGame().SurfaceY(x, z), z));
			}
			if (measured.Points.Count() > 0)
				terrain.Locations.Insert(measured);
		}
		foreach (SoloSafeZone zone : m_SoloSettings.SafeZones)
		{
			SoloTerrainLocation zoneGround = new SoloTerrainLocation();
			zoneGround.Name = zone.Name;
			for (int k = 0; k < offsetsX.Count(); k++)
			{
				float zoneX = zone.Position[0] + offsetsX[k] / 75;
				float zoneZ = zone.Position[2] + offsetsZ[k] / 75;
				zoneGround.Points.Insert(Vector(zoneX, GetGame().SurfaceY(zoneX, zoneZ), zoneZ));
			}
			terrain.SafeZones.Insert(zoneGround);
		}

		string terrainError;
		JsonFileLoader<SoloTerrainFile>.SaveFile("$profile:SoloSurvivor/terrain.json", terrain, terrainError);
	}

	protected void SoloKeepDaytime()
	{
		int year, month, day, hour, minute;
		GetGame().GetWorld().GetDate(year, month, day, hour, minute);
		if (hour >= m_SoloSettings.DayStartHour && hour < m_SoloSettings.DayEndHour)
			return;

		GetGame().GetWorld().SetDate(year, month, day, m_SoloSettings.DayStartHour, 0);
		Print("[SoloSurvivor] Always day: clock set back to " + m_SoloSettings.DayStartHour + ":00");
	}

	protected void SoloPollCommands()
	{
		if (!FileExist(SOLO_COMMANDS_PATH))
			return;

		FileHandle file = OpenFile(SOLO_COMMANDS_PATH, FileMode.READ);
		if (!file)
			return;

		array<string> commands = new array<string>;
		string line;
		int guard = 0;
		while (guard < SOLO_MAX_COMMAND_LINES && FGets(file, line) > 0)
		{
			commands.Insert(line.Trim());
			guard++;
		}
		CloseFile(file);
		DeleteFile(SOLO_COMMANDS_PATH);

		foreach (string command : commands)
			SoloRunCommand(command);
	}

	protected void SoloRunCommand(string command)
	{
		if (command == "shutdown")
		{
			Print("[SoloSurvivor] Shutdown requested by the launcher, saving world");
			GetGame().RequestExit(0);
			return;
		}

		if (command == "event heli" || command == "event airdrop" || command == "event gas")
		{
			m_SoloEvents.TriggerEvent(command.Substring(6, command.Length() - 6));
			return;
		}

		if (command == "event clear")
		{
			m_SoloEvents.ClearEvents();
			return;
		}

		if (command.IndexOf("teleport ") == 0)
		{
			array<string> teleportParts = new array<string>;
			command.Split(" ", teleportParts);
			if (teleportParts.Count() == 4)
			{
				string xText = teleportParts[2];
				string zText = teleportParts[3];
				SoloTeleport(teleportParts[1], xText.ToFloat(), zText.ToFloat());
			}
			return;
		}

		if (command.IndexOf("say ") == 0 && command.Length() > 4)
		{
			string text = command.Substring(4, command.Length() - 4);
			array<Man> players = new array<Man>;
			GetGame().GetPlayers(players);
			foreach (Man man : players)
			{
				if (man.GetIdentity())
					NotificationSystem.SendNotificationToPlayerIdentityExtended(man.GetIdentity(), 8, "Launcher", text);
			}
		}
	}

	protected void SoloTeleport(string uid, float x, float z)
	{
		array<Man> onlinePlayers = new array<Man>;
		GetGame().GetPlayers(onlinePlayers);
		foreach (Man onlineMan : onlinePlayers)
		{
			PlayerBase target = PlayerBase.Cast(onlineMan);
			if (!target || !target.GetIdentity())
				continue;
			if (uid != "all" && target.GetIdentity().GetId() != uid)
				continue;

			Object moved = target;
			HumanCommandVehicle vehicleCommand = target.GetCommand_Vehicle();
			if (vehicleCommand && vehicleCommand.GetTransport())
				moved = vehicleCommand.GetTransport();

			moved.SetPosition(Vector(x, GetGame().SurfaceY(x, z) + 0.3, z));
			Print("[SoloSurvivor] Teleported " + target.GetIdentity().GetName() + " to " + x + ", " + z);
			NotificationSystem.SendNotificationToPlayerIdentityExtended(target.GetIdentity(), 5, "Admin", "You were teleported.");
		}
	}

	protected void SoloWriteStatus()
	{
		SoloStatus status = new SoloStatus();
		status.UptimeSeconds = GetGame().GetTickTime();

		int year, month, day, hour, minute;
		GetGame().GetWorld().GetDate(year, month, day, hour, minute);
		status.WorldTime = hour.ToStringLen(2) + ":" + minute.ToStringLen(2);

		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		foreach (Man man : players)
		{
			PlayerBase player = PlayerBase.Cast(man);
			if (!player)
				continue;

			SoloStatusPlayer entry = new SoloStatusPlayer();
			entry.Name = "Survivor";
			if (player.GetIdentity())
			{
				entry.Uid = player.GetIdentity().GetId();
				entry.Name = player.GetIdentity().GetName();
			}
			entry.Position = player.GetPosition();
			entry.Heading = player.GetOrientation()[0];
			entry.Health = player.GetHealth("", "");
			entry.Blood = player.GetHealth("", "Blood");
			entry.InSafeZone = m_SoloSettings.FindSafeZone(entry.Position) != null;
			status.Survivors.Insert(entry);
		}
		status.Players = status.Survivors.Count();

		float now = GetGame().GetTickTime();
		foreach (SoloActiveEvent active : m_SoloEvents.GetActiveEvents())
		{
			SoloStatusEvent ev = new SoloStatusEvent();
			ev.Kind = active.Kind;
			ev.Label = active.Label;
			ev.Place = active.Place;
			ev.Position = active.Position;
			ev.AgeMinutes = (now - active.SpawnedAt) / 60;
			status.Events.Insert(ev);
		}

		string statusError;
		JsonFileLoader<SoloStatus>.SaveFile(SOLO_STATUS_PATH, status, statusError);
	}

	protected void SoloUpdateSafeZones()
	{
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		foreach (Man man : players)
		{
			PlayerBase player = PlayerBase.Cast(man);
			if (!player || !player.GetIdentity() || !player.IsAlive())
				continue;

			string uid = player.GetIdentity().GetId();
			SoloSafeZone zone = m_SoloSettings.FindSafeZone(player.GetPosition());
			PlayerBase protectedPlayer = m_SoloProtectedPlayers.Get(uid);

			if (zone && protectedPlayer != player)
			{
				player.SetAllowDamage(false);
				m_SoloProtectedPlayers.Set(uid, player);
				NotificationSystem.SendNotificationToPlayerIdentityExtended(player.GetIdentity(), 4, "Safe zone", "Entering " + zone.Name + ". You can't be hurt here.");
			}
			else if (!zone && protectedPlayer == player)
			{
				player.SetAllowDamage(true);
				m_SoloProtectedPlayers.Remove(uid);
				NotificationSystem.SendNotificationToPlayerIdentityExtended(player.GetIdentity(), 4, "Safe zone", "You left the safe zone.");
			}
		}

		foreach (SoloSafeZone safeZone : m_SoloSettings.SafeZones)
			SoloClearSafeZone(safeZone);
	}

	protected void SoloClearSafeZone(SoloSafeZone zone)
	{
		array<Object> objects = new array<Object>;
		GetGame().GetObjectsAtPosition(zone.Position, zone.Radius, objects, null);
		foreach (Object obj : objects)
		{
			if (obj.IsInherited(ZombieBase) || obj.IsInherited(AnimalBase))
			{
				GetGame().ObjectDelete(obj);
				continue;
			}

			string className = obj.GetType();
			if (className.IndexOf("eAI_") == 0)
			{
				EntityAI bandit = EntityAI.Cast(obj);
				if (bandit && bandit.IsAlive())
					bandit.SetHealth("", "", 0);
			}
		}
	}

	override PlayerBase OnClientNewEvent(PlayerIdentity identity, vector pos, ParamsReadContext ctx)
	{
		if (m_SoloSettings && m_SoloSettings.UseFixedSpawn)
		{
			pos = m_SoloSettings.FixedSpawnPosition;
			pos[1] = GetGame().SurfaceY(pos[0], pos[2]);
		}
		PlayerBase newPlayer = super.OnClientNewEvent(identity, pos, ctx);
		if (m_SoloDays && identity)
			m_SoloDays.ResetPlayer(identity.GetId());
		if (newPlayer && m_SoloSettings)
		{
			foreach (string itemType : m_SoloSettings.ExtraStartingItems)
			{
				if (!newPlayer.GetInventory().CreateInInventory(itemType))
					GetGame().CreateObjectEx(itemType, newPlayer.GetPosition(), ECE_PLACE_ON_SURFACE);
			}
		}
		return newPlayer;
	}

	override void InvokeOnConnect(PlayerBase player, PlayerIdentity identity)
	{
		super.InvokeOnConnect(player, identity);
		if (m_SoloEvents)
			GetGame().GetCallQueue(CALL_CATEGORY_GAMEPLAY).CallLater(m_SoloEvents.SendMarkersTo, 4000, false, player);
		if (identity && m_SoloSettings && m_SoloSettings.WelcomeMessage != "")
			NotificationSystem.SendNotificationToPlayerIdentityExtended(identity, 8, "Solo Survivor", m_SoloSettings.WelcomeMessage);
	}

	override void PlayerDisconnected(PlayerBase player, PlayerIdentity identity, string uid)
	{
		super.PlayerDisconnected(player, identity, uid);
		if (m_SoloProtectedPlayers)
			m_SoloProtectedPlayers.Remove(uid);
		if (m_SoloDays)
			m_SoloDays.ForgetClock(uid);
		if (m_SoloSettings && m_SoloSettings.ShutdownServerWhenEmpty)
			GetGame().GetCallQueue(CALL_CATEGORY_SYSTEM).CallLater(SoloShutdownIfEmpty, m_SoloSettings.ShutdownDelaySeconds * 1000, false);
	}

	// Graceful exit lets the server flush persistence (bases, loot, character) before the launcher stops waiting.
	protected void SoloShutdownIfEmpty()
	{
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		if (players.Count() > 0)
			return;

		Print("[SoloSurvivor] No players left, saving world and shutting down");
		GetGame().RequestExit(0);
	}
}
