class SoloSafeZone
{
	string Name;
	vector Position;
	float Radius;
}

class SoloSurvivorSettings
{
	bool ShutdownServerWhenEmpty;
	int ShutdownDelaySeconds;
	bool UseFixedSpawn;
	vector FixedSpawnPosition;
	ref array<string> ExtraStartingItems;
	string WelcomeMessage;
	bool AlwaysDay;
	int DayStartHour;
	int DayEndHour;
	ref array<ref SoloSafeZone> SafeZones;
	ref SoloEventSettings Events;

	void SoloSurvivorSettings()
	{
		ShutdownServerWhenEmpty = false;
		ShutdownDelaySeconds = 10;
		UseFixedSpawn = false;
		FixedSpawnPosition = "6550 0 2465";
		ExtraStartingItems = new array<string>;
		WelcomeMessage = "This world is yours alone. Good luck, survivor.";
		AlwaysDay = false;
		DayStartHour = 7;
		DayEndHour = 19;
		SafeZones = new array<ref SoloSafeZone>;
		Events = new SoloEventSettings();
	}

	SoloSafeZone FindSafeZone(vector pos)
	{
		foreach (SoloSafeZone zone : SafeZones)
		{
			float dx = pos[0] - zone.Position[0];
			float dz = pos[2] - zone.Position[2];
			if (dx * dx + dz * dz <= zone.Radius * zone.Radius)
				return zone;
		}
		return null;
	}

	static SoloSurvivorSettings Load()
	{
		string dir = "$profile:SoloSurvivor";
		string path = dir + "/settings.json";
		SoloSurvivorSettings settings = new SoloSurvivorSettings();

		if (!FileExist(dir))
			MakeDirectory(dir);

		if (FileExist(path))
		{
			string loadError;
			if (!JsonFileLoader<SoloSurvivorSettings>.LoadFile(path, settings, loadError))
				Print("[SoloSurvivor] " + loadError);
		}
		else
		{
			string saveError;
			JsonFileLoader<SoloSurvivorSettings>.SaveFile(path, settings, saveError);
		}

		return settings;
	}
}
