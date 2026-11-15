class SoloStatusPlayer
{
	string Uid;
	string Name;
	vector Position;
	float Heading;
	float Health;
	float Blood;
	bool InSafeZone;
}

class SoloStatusEvent
{
	string Kind;
	string Label;
	string Place;
	vector Position;
	float AgeMinutes;
}

class SoloStatus
{
	int Players;
	float UptimeSeconds;
	string WorldTime;
	ref array<ref SoloStatusPlayer> Survivors;
	ref array<ref SoloStatusEvent> Events;

	void SoloStatus()
	{
		Survivors = new array<ref SoloStatusPlayer>;
		Events = new array<ref SoloStatusEvent>;
	}
}
