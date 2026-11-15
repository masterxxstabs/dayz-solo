class SoloTerrainLocation
{
	string Name;
	ref array<vector> Points;

	void SoloTerrainLocation()
	{
		Points = new array<vector>;
	}
}

class SoloTerrainFile
{
	string MapName;
	ref array<ref SoloTerrainLocation> Locations;
	ref array<ref SoloTerrainLocation> SafeZones;

	void SoloTerrainFile()
	{
		Locations = new array<ref SoloTerrainLocation>;
		SafeZones = new array<ref SoloTerrainLocation>;
	}
}
