modded class PlayerBase
{
	override void OnRPC(PlayerIdentity sender, int rpc_type, ParamsReadContext ctx)
	{
		super.OnRPC(sender, rpc_type, ctx);
		if (rpc_type != SOLO_DAYS_RPC || GetGame().IsDedicatedServer())
			return;

		Param1<int> data = new Param1<int>(0);
		if (!ctx.Read(data))
			return;

		SoloDays.Day = data.param1;
		SoloDays.Show = true;
	}
}
