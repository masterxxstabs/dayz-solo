const string SOLO_SHOP_COMMANDS_PATH = "$profile:SoloShop/commands.txt";
const int SOLO_SHOP_MAX_COMMAND_LINES = 50;

modded class MissionServer
{
	override void OnInit()
	{
		super.OnInit();
		SoloShopServer.GetShop();
		GetGame().GetCallQueue(CALL_CATEGORY_SYSTEM).CallLater(SoloShopPollAdminCommands, 2000, true);
	}

	override void InvokeOnConnect(PlayerBase player, PlayerIdentity identity)
	{
		super.InvokeOnConnect(player, identity);
		SoloShopServer.GetShop().SendShopState(player);
	}

	protected void SoloShopPollAdminCommands()
	{
		if (!FileExist(SOLO_SHOP_COMMANDS_PATH))
			return;

		FileHandle file = OpenFile(SOLO_SHOP_COMMANDS_PATH, FileMode.READ);
		if (!file)
			return;

		array<string> commands = new array<string>;
		string line;
		int guard = 0;
		while (guard < SOLO_SHOP_MAX_COMMAND_LINES && FGets(file, line) > 0)
		{
			commands.Insert(line.Trim());
			guard++;
		}
		CloseFile(file);
		DeleteFile(SOLO_SHOP_COMMANDS_PATH);

		if (!SoloShopServer.GetShop().IsShopEnabled())
			return;

		foreach (string command : commands)
		{
			array<string> parts = new array<string>;
			command.Split(" ", parts);
			if (parts.Count() != 3)
				continue;
			string amountText = parts[2];
			if (parts[0] == "money")
				SoloShopServer.GetShop().AdminAdjustBalance(parts[1], amountText.ToInt(), false);
			else if (parts[0] == "setmoney")
				SoloShopServer.GetShop().AdminAdjustBalance(parts[1], amountText.ToInt(), true);
		}
	}
}
