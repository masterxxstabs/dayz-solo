class SoloEventLocation
{
	string Name;
	string MapName;
	vector Position;
	float Radius;
}

class SoloEventType
{
	bool Enabled;
	float Weight;
	ref array<string> Objects;
	ref array<string> Loot;
	int LootCount;
	ref array<string> Zombies;
	int ZombieCount;
	string Announcement;

	void SoloEventType()
	{
		Enabled = true;
		Weight = 1;
		Objects = new array<string>;
		Loot = new array<string>;
		Zombies = new array<string>;
	}
}

class SoloGasSettings
{
	bool Enabled;
	float FirstStrikeMinutes;
	float MinIntervalMinutes;
	float MaxIntervalMinutes;
	float MarkerMinutes;
	float MinDistanceFromPlayer;
	string Announcement;

	void SoloGasSettings()
	{
		Enabled = false;
		FirstStrikeMinutes = 20;
		MinIntervalMinutes = 90;
		MaxIntervalMinutes = 150;
		MarkerMinutes = 45;
		MinDistanceFromPlayer = 400;
		Announcement = "Toxic gas incoming";
	}
}

class SoloEventSettings
{
	bool Enabled;
	float FirstEventMinutes;
	float MinIntervalMinutes;
	float MaxIntervalMinutes;
	int MaxActive;
	float DespawnMinutes;
	ref SoloEventType HeliCrash;
	ref SoloEventType Airdrop;
	ref SoloGasSettings Gas;
	ref array<ref SoloEventLocation> Locations;

	void SoloEventSettings()
	{
		Enabled = false;
		FirstEventMinutes = 10;
		MinIntervalMinutes = 30;
		MaxIntervalMinutes = 60;
		MaxActive = 2;
		DespawnMinutes = 45;
		HeliCrash = new SoloEventType();
		Airdrop = new SoloEventType();
		Gas = new SoloGasSettings();
		Locations = new array<ref SoloEventLocation>;
	}
}
