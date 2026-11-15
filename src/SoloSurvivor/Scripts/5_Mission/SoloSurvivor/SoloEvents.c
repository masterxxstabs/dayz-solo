static const int SOLO_MINIMAP_MARKERS_RPC = 74631201;
static const string SOLO_MINIMAP_MARKER_FILE = "$profile:SoloMinimap/markers.json";
static const float SOLO_EVENT_PLAYER_NEAR = 150;
static const float SOLO_EVENT_CLEAR_RADIUS = 12;
static const int SOLO_EVENT_SPOT_ATTEMPTS = 20;

class SoloStaticMarker
{
	string Name;
	vector Position;
}

class SoloStaticMarkerFile
{
	ref array<ref SoloStaticMarker> Markers;

	void SoloStaticMarkerFile()
	{
		Markers = new array<ref SoloStaticMarker>;
	}
}

class SoloActiveEvent
{
	string Kind;
	string Label;
	string Place;
	vector Position;
	float SpawnedAt;
	ref array<Object> Objects;

	void SoloActiveEvent()
	{
		Objects = new array<Object>;
	}
}

class SoloEventManager
{
	protected SoloEventSettings m_Settings;
	protected SoloSurvivorSettings m_SoloSettings;
	protected ref array<ref SoloActiveEvent> m_Active;
	protected ref SoloStaticMarkerFile m_StaticMarkers;
	protected float m_NextEventAt;
	protected float m_NextGasAt;

	void SoloEventManager(SoloSurvivorSettings soloSettings)
	{
		m_SoloSettings = soloSettings;
		m_Settings = soloSettings.Events;
		m_Active = new array<ref SoloActiveEvent>;
		m_StaticMarkers = new SoloStaticMarkerFile();
		if (FileExist(SOLO_MINIMAP_MARKER_FILE))
		{
			string markersError;
			if (!JsonFileLoader<SoloStaticMarkerFile>.LoadFile(SOLO_MINIMAP_MARKER_FILE, m_StaticMarkers, markersError))
				Print("[SoloSurvivor] " + markersError);
		}
		m_NextEventAt = GetGame().GetTickTime() + m_Settings.FirstEventMinutes * 60;
		m_NextGasAt = GetGame().GetTickTime() + m_Settings.Gas.FirstStrikeMinutes * 60;
	}

	array<ref SoloActiveEvent> GetActiveEvents()
	{
		return m_Active;
	}

	void TickEvents()
	{
		float now = GetGame().GetTickTime();
		bool changed = false;
		for (int i = m_Active.Count() - 1; i >= 0; i--)
		{
			SoloActiveEvent ev = m_Active[i];
			if (ev.Kind == "gas")
			{
				// The cloud decays on its own; only the marker is retired here.
				if (now - ev.SpawnedAt < m_Settings.Gas.MarkerMinutes * 60)
					continue;
				m_Active.RemoveOrdered(i);
				changed = true;
				continue;
			}
			if (now - ev.SpawnedAt < m_Settings.DespawnMinutes * 60 || IsPlayerNear(ev.Position, SOLO_EVENT_PLAYER_NEAR))
				continue;
			CleanupEvent(ev);
			m_Active.RemoveOrdered(i);
			changed = true;
		}
		if (changed)
			SendMarkersToEveryone();

		if (m_Settings.Gas.Enabled && now >= m_NextGasAt)
		{
			m_NextGasAt = now + Math.RandomFloatInclusive(m_Settings.Gas.MinIntervalMinutes, m_Settings.Gas.MaxIntervalMinutes) * 60;
			if (AnyPlayersOnline())
				TriggerGasStrike();
		}

		if (!m_Settings.Enabled || now < m_NextEventAt)
			return;
		m_NextEventAt = now + Math.RandomFloatInclusive(m_Settings.MinIntervalMinutes, m_Settings.MaxIntervalMinutes) * 60;
		if (m_Active.Count() >= m_Settings.MaxActive || !AnyPlayersOnline())
			return;
		TriggerEvent("");
	}

	bool TriggerEvent(string kind)
	{
		if (kind == "gas")
			return TriggerGasStrike();
		if (kind == "")
			kind = PickEventKind();
		SoloEventType eventType = GetEventType(kind);
		if (!eventType)
		{
			Print("[SoloSurvivor] No event type available to trigger");
			return false;
		}

		SoloEventLocation location;
		vector spot;
		if (!PickEventSpot(location, spot))
		{
			Print("[SoloSurvivor] No free spot found for a " + kind + " event on this map");
			return false;
		}

		SoloActiveEvent ev = new SoloActiveEvent();
		ev.Kind = kind;
		ev.Place = location.Name;
		ev.Position = spot;
		ev.SpawnedAt = GetGame().GetTickTime();
		if (kind == "heli")
		{
			ev.Label = "Heli crash";
			SpawnHeliCrash(eventType, ev);
		}
		else
		{
			ev.Label = "Airdrop";
			SpawnAirdrop(eventType, ev);
		}
		m_Active.Insert(ev);

		Print("[SoloSurvivor] " + ev.Label + " at " + ev.Place + " " + spot.ToString());
		AnnounceEvent(eventType.Announcement, ev);
		SendMarkersToEveryone();
		return true;
	}

	bool TriggerGasStrike()
	{
		vector spot;
		if (!PickGasSpot(spot))
		{
			Print("[SoloSurvivor] No open spot found for a gas strike");
			return false;
		}

		Entity cloud = GetCEApi().SpawnGroup("ContaminatedArea_Dynamic", spot);
		if (!cloud)
		{
			Print("[SoloSurvivor] The game couldn't create a gas cloud on this map");
			return false;
		}

		SoloActiveEvent ev = new SoloActiveEvent();
		ev.Kind = "gas";
		ev.Label = "Toxic gas";
		ev.Place = NearestPlaceName(spot);
		ev.Position = spot;
		ev.SpawnedAt = GetGame().GetTickTime();
		ev.Objects.Insert(cloud);
		m_Active.Insert(ev);

		Print("[SoloSurvivor] Gas strike near " + ev.Place + " " + spot.ToString());
		AnnounceEvent(m_Settings.Gas.Announcement, ev);
		SendMarkersToEveryone();
		return true;
	}

	protected bool PickGasSpot(out vector spot)
	{
		float worldSize = GetGame().GetWorld().GetWorldSize();
		float margin = 400;
		for (int attempt = 0; attempt < SOLO_EVENT_SPOT_ATTEMPTS * 2; attempt++)
		{
			float x = Math.RandomFloat(margin, worldSize - margin);
			float z = Math.RandomFloat(margin, worldSize - margin);
			if (GetGame().SurfaceIsSea(x, z) || GetGame().SurfaceIsPond(x, z))
				continue;
			vector pos = Vector(x, GetGame().SurfaceY(x, z), z);
			if (m_SoloSettings.FindSafeZone(pos) || IsPlayerNear(pos, m_Settings.Gas.MinDistanceFromPlayer))
				continue;
			spot = pos;
			return true;
		}
		return false;
	}

	protected string NearestPlaceName(vector pos)
	{
		string worldName;
		GetGame().GetWorldName(worldName);
		worldName.ToLower();

		string nearest = "";
		float bestDistance = -1;
		foreach (SoloEventLocation loc : m_Settings.Locations)
		{
			string locationMap = loc.MapName;
			locationMap.ToLower();
			if (locationMap != "" && locationMap != worldName)
				continue;
			float distance = vector.Distance(pos, loc.Position);
			if (bestDistance < 0 || distance < bestDistance)
			{
				bestDistance = distance;
				nearest = loc.Name;
			}
		}
		if (nearest == "")
			return "the wilderness";
		return nearest;
	}

	void ClearEvents()
	{
		foreach (SoloActiveEvent ev : m_Active)
			CleanupEvent(ev);
		m_Active.Clear();
		SendMarkersToEveryone();
	}

	void SendMarkersTo(PlayerBase player)
	{
		if (!player || !player.GetIdentity())
			return;

		array<string> names = new array<string>;
		array<vector> positions = new array<vector>;
		foreach (SoloStaticMarker marker : m_StaticMarkers.Markers)
		{
			names.Insert(marker.Name);
			positions.Insert(marker.Position);
		}
		foreach (SoloActiveEvent ev : m_Active)
		{
			names.Insert(ev.Label);
			positions.Insert(ev.Position);
		}

		Param2<ref array<string>, ref array<vector>> data = new Param2<ref array<string>, ref array<vector>>(names, positions);
		GetGame().RPCSingleParam(player, SOLO_MINIMAP_MARKERS_RPC, data, true, player.GetIdentity());
	}

	void SendMarkersToEveryone()
	{
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		foreach (Man man : players)
			SendMarkersTo(PlayerBase.Cast(man));
	}

	protected string PickEventKind()
	{
		float heli = 0;
		float drop = 0;
		if (m_Settings.HeliCrash && m_Settings.HeliCrash.Enabled)
			heli = m_Settings.HeliCrash.Weight;
		if (m_Settings.Airdrop && m_Settings.Airdrop.Enabled)
			drop = m_Settings.Airdrop.Weight;
		if (heli + drop <= 0)
			return "";
		if (Math.RandomFloat(0, heli + drop) < heli)
			return "heli";
		return "airdrop";
	}

	protected SoloEventType GetEventType(string kind)
	{
		if (kind == "heli" && m_Settings.HeliCrash && m_Settings.HeliCrash.Enabled)
			return m_Settings.HeliCrash;
		if (kind == "airdrop" && m_Settings.Airdrop && m_Settings.Airdrop.Enabled)
			return m_Settings.Airdrop;
		return null;
	}

	protected bool PickEventSpot(out SoloEventLocation location, out vector spot)
	{
		string worldName;
		GetGame().GetWorldName(worldName);
		worldName.ToLower();

		array<SoloEventLocation> candidates = new array<SoloEventLocation>;
		foreach (SoloEventLocation loc : m_Settings.Locations)
		{
			string locationMap = loc.MapName;
			locationMap.ToLower();
			if (locationMap == "" || locationMap == worldName)
				candidates.Insert(loc);
		}
		if (candidates.Count() == 0)
			return false;

		for (int attempt = 0; attempt < SOLO_EVENT_SPOT_ATTEMPTS; attempt++)
		{
			SoloEventLocation pick = candidates.GetRandomElement();
			float angle = Math.RandomFloat(0, Math.PI2);
			float dist = Math.RandomFloat(0, pick.Radius);
			float x = pick.Position[0] + Math.Cos(angle) * dist;
			float z = pick.Position[2] + Math.Sin(angle) * dist;
			if (GetGame().SurfaceIsSea(x, z) || GetGame().SurfaceIsPond(x, z))
				continue;
			vector pos = Vector(x, GetGame().SurfaceY(x, z), z);
			if (m_SoloSettings.FindSafeZone(pos) || IsSpotBlocked(pos) || IsPlayerNear(pos, SOLO_EVENT_PLAYER_NEAR))
				continue;
			location = pick;
			spot = pos;
			return true;
		}
		return false;
	}

	protected bool IsSpotBlocked(vector pos)
	{
		array<Object> objects = new array<Object>;
		GetGame().GetObjectsAtPosition(pos, SOLO_EVENT_CLEAR_RADIUS, objects, null);
		foreach (Object obj : objects)
		{
			if (obj.IsBuilding() || obj.IsTree())
				return true;
		}
		return false;
	}

	protected bool AnyPlayersOnline()
	{
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		return players.Count() > 0;
	}

	protected bool IsPlayerNear(vector pos, float radius)
	{
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		foreach (Man man : players)
		{
			if (vector.Distance(man.GetPosition(), pos) < radius)
				return true;
		}
		return false;
	}

	protected vector PointAround(vector center, float minDist, float maxDist)
	{
		float angle = Math.RandomFloat(0, Math.PI2);
		float dist = Math.RandomFloat(minDist, maxDist);
		float x = center[0] + Math.Cos(angle) * dist;
		float z = center[2] + Math.Sin(angle) * dist;
		return Vector(x, GetGame().SurfaceY(x, z), z);
	}

	protected Object SpawnObject(SoloActiveEvent ev, string className, vector pos, int flags)
	{
		Object obj = GetGame().CreateObjectEx(className, pos, flags);
		if (!obj)
		{
			Print("[SoloSurvivor] Couldn't spawn " + className + " - check the class name in SoloSurvivor.json");
			return null;
		}
		EntityAI entity = EntityAI.Cast(obj);
		if (entity)
			entity.SetLifetime(m_Settings.DespawnMinutes * 60 + 600);
		ev.Objects.Insert(obj);
		return obj;
	}

	protected void SpawnZombies(SoloEventType eventType, SoloActiveEvent ev, float minDist, float maxDist)
	{
		if (eventType.Zombies.Count() == 0)
			return;
		for (int i = 0; i < eventType.ZombieCount; i++)
			SpawnObject(ev, eventType.Zombies.GetRandomElement(), PointAround(ev.Position, minDist, maxDist), ECE_PLACE_ON_SURFACE | ECE_INITAI | ECE_EQUIP_ATTACHMENTS);
	}

	protected void SpawnHeliCrash(SoloEventType eventType, SoloActiveEvent ev)
	{
		if (eventType.Objects.Count() > 0)
		{
			Object wreck = SpawnObject(ev, eventType.Objects.GetRandomElement(), ev.Position, ECE_PLACE_ON_SURFACE);
			if (wreck)
				wreck.SetOrientation(Vector(Math.RandomFloat(0, 360), 0, 0));
		}
		if (eventType.Loot.Count() > 0)
		{
			for (int i = 0; i < eventType.LootCount; i++)
				SpawnObject(ev, eventType.Loot.GetRandomElement(), PointAround(ev.Position, 5, 9), ECE_PLACE_ON_SURFACE);
		}
		SpawnZombies(eventType, ev, 12, 30);
	}

	protected void SpawnAirdrop(SoloEventType eventType, SoloActiveEvent ev)
	{
		EntityAI crate;
		if (eventType.Objects.Count() > 0)
			crate = EntityAI.Cast(SpawnObject(ev, eventType.Objects.GetRandomElement(), ev.Position, ECE_PLACE_ON_SURFACE));

		for (int i = 0; i < eventType.LootCount && eventType.Loot.Count() > 0; i++)
		{
			string item = eventType.Loot.GetRandomElement();
			if (!crate || !crate.GetInventory().CreateInInventory(item))
				GetGame().CreateObjectEx(item, PointAround(ev.Position, 1.5, 3), ECE_PLACE_ON_SURFACE);
		}

		Object smoke = SpawnObject(ev, "M18SmokeGrenade_Red", PointAround(ev.Position, 2, 3), ECE_PLACE_ON_SURFACE);
		if (smoke)
			GetGame().GameScript.CallFunction(smoke, "Unpin", null, 0);

		SpawnZombies(eventType, ev, 15, 35);
	}

	protected void CleanupEvent(SoloActiveEvent ev)
	{
		foreach (Object obj : ev.Objects)
		{
			if (!obj)
				continue;
			EntityAI entity = EntityAI.Cast(obj);
			if (entity && entity.GetHierarchyRootPlayer())
				continue;
			GetGame().ObjectDelete(obj);
		}
		ev.Objects.Clear();
	}

	protected void AnnounceEvent(string announcement, SoloActiveEvent ev)
	{
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		foreach (Man man : players)
		{
			if (!man.GetIdentity())
				continue;
			string text = announcement;
			if (text == "")
				text = ev.Label;
			text = text + " - " + DescribeDirection(man.GetPosition(), ev.Position) + ", near " + ev.Place + ".";
			NotificationSystem.SendNotificationToPlayerIdentityExtended(man.GetIdentity(), 12, ev.Label, text);
		}
	}

	protected string DescribeDirection(vector from, vector to)
	{
		float dx = to[0] - from[0];
		float dz = to[2] - from[2];
		float km = Math.Round(Math.Sqrt(dx * dx + dz * dz) / 100) / 10;
		float angle = Math.Atan2(dx, dz) * Math.RAD2DEG;
		if (angle < 0)
			angle += 360;
		array<string> directions = {"north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"};
		int index = 0;
		if (angle < 337.5)
		{
			float sector = angle + 22.5;
			while (sector >= 45 && index < 7)
			{
				sector -= 45;
				index++;
			}
		}
		return "about " + km.ToString() + " km " + directions[index] + " of you";
	}
}
