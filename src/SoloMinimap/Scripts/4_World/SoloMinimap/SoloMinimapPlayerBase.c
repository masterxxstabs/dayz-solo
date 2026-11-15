modded class PlayerBase
{
	override void OnRPC(PlayerIdentity sender, int rpc_type, ParamsReadContext ctx)
	{
		super.OnRPC(sender, rpc_type, ctx);
		if (rpc_type != SOLO_MINIMAP_RPC_MARKERS || GetGame().IsDedicatedServer())
			return;

		Param3<bool, ref array<string>, ref array<vector>> data = new Param3<bool, ref array<string>, ref array<vector>>(false, new array<string>, new array<vector>);
		if (!ctx.Read(data) || !data.param2 || !data.param3)
			return;

		SoloMinimapMarkers.Enabled = data.param1;
		SoloMinimapMarkers.SetMarkers(data.param2, data.param3);
	}
}
