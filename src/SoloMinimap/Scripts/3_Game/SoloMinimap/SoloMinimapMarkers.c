const int SOLO_MINIMAP_RPC_MARKERS = 74631201;
const string SOLO_MINIMAP_MARKERS_PATH = "$profile:SoloMinimap/markers.json";

class SoloMinimapMarker
{
	string Name;
	vector Position;
}

class SoloMinimapMarkerFile
{
	bool Enabled;
	ref array<ref SoloMinimapMarker> Markers;

	void SoloMinimapMarkerFile()
	{
		Enabled = false;
		Markers = new array<ref SoloMinimapMarker>;
	}
}

class SoloMinimapMarkers
{
	static bool Enabled;
	static ref array<string> Names = new array<string>;
	static ref array<vector> Positions = new array<vector>;

	static void SetMarkers(array<string> names, array<vector> positions)
	{
		Names.Clear();
		Positions.Clear();
		int count = names.Count();
		if (positions.Count() < count)
			count = positions.Count();
		for (int i = 0; i < count; i++)
		{
			Names.Insert(names[i]);
			Positions.Insert(positions[i]);
		}
	}
}
