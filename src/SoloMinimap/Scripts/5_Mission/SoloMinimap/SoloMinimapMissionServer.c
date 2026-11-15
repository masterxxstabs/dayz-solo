modded class MissionServer
{
	override void InvokeOnConnect(PlayerBase player, PlayerIdentity identity)
	{
		super.InvokeOnConnect(player, identity);
		if (!player || !identity || !FileExist(SOLO_MINIMAP_MARKERS_PATH))
			return;

		SoloMinimapMarkerFile file = new SoloMinimapMarkerFile();
		string loadError;
		if (!JsonFileLoader<SoloMinimapMarkerFile>.LoadFile(SOLO_MINIMAP_MARKERS_PATH, file, loadError))
		{
			Print("[SoloMinimap] " + loadError);
			return;
		}

		array<string> names = new array<string>;
		array<vector> positions = new array<vector>;
		foreach (SoloMinimapMarker marker : file.Markers)
		{
			names.Insert(marker.Name);
			positions.Insert(marker.Position);
		}

		Param3<bool, ref array<string>, ref array<vector>> data = new Param3<bool, ref array<string>, ref array<vector>>(file.Enabled, names, positions);
		GetGame().RPCSingleParam(player, SOLO_MINIMAP_RPC_MARKERS, data, true, identity);
	}
}
