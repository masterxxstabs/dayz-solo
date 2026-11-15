class SoloShopBalanceEntry
{
	string Uid;
	int Balance;
}

class SoloShopBalanceFile
{
	ref array<ref SoloShopBalanceEntry> Players;

	void SoloShopBalanceFile()
	{
		Players = new array<ref SoloShopBalanceEntry>;
	}
}

class SoloShopCategoryList
{
	ref array<string> Classes;
	ref array<int> BuyPrices;
	ref array<int> SellPrices;

	void SoloShopCategoryList()
	{
		Classes = new array<string>;
		BuyPrices = new array<int>;
		SellPrices = new array<int>;
	}
}

class SoloShopServer
{
	protected static ref SoloShopServer s_SoloShopInstance;
	protected ref SoloShopCatalog m_Catalog;
	protected ref SoloShopBalanceFile m_Balances;
	protected ref map<string, SoloShopEntry> m_SoloEntries;
	protected ref map<string, bool> m_SoloVehicleEntries;
	protected ref map<string, ref SoloShopCategoryList> m_SoloCategoryLists;

	static SoloShopServer GetShop()
	{
		if (!s_SoloShopInstance)
			s_SoloShopInstance = new SoloShopServer();
		return s_SoloShopInstance;
	}

	void SoloShopServer()
	{
		m_Catalog = new SoloShopCatalog();
		string catalogError;
		if (!FileExist(SOLO_SHOP_CATALOG_PATH))
			Print("[SoloShop] No catalog at " + SOLO_SHOP_CATALOG_PATH + " - the launcher writes it at start");
		else if (!JsonFileLoader<SoloShopCatalog>.LoadFile(SOLO_SHOP_CATALOG_PATH, m_Catalog, catalogError))
			Print("[SoloShop] " + catalogError);

		m_Balances = new SoloShopBalanceFile();
		string balancesError;
		if (FileExist(SOLO_SHOP_BALANCES_PATH) && !JsonFileLoader<SoloShopBalanceFile>.LoadFile(SOLO_SHOP_BALANCES_PATH, m_Balances, balancesError))
			Print("[SoloShop] " + balancesError);

		IndexShopCatalog();
	}

	protected void IndexShopCatalog()
	{
		m_SoloEntries = new map<string, SoloShopEntry>;
		m_SoloVehicleEntries = new map<string, bool>;
		m_SoloCategoryLists = new map<string, ref SoloShopCategoryList>;
		foreach (SoloShopCategory category : m_Catalog.Categories)
		{
			SoloShopCategoryList list = new SoloShopCategoryList();
			foreach (SoloShopEntry entry : category.Items)
			{
				if (!m_SoloEntries.Contains(entry.ClassName))
				{
					m_SoloEntries.Insert(entry.ClassName, entry);
					m_SoloVehicleEntries.Insert(entry.ClassName, entry.Vehicle || category.IsVehicles);
				}
				list.Classes.Insert(entry.ClassName);
				list.BuyPrices.Insert(entry.Buy);
				list.SellPrices.Insert(entry.Sell);
			}
			m_SoloCategoryLists.Insert(category.Name, list);
		}
		if (m_Catalog.Enabled)
			Print("[SoloShop] Catalog ready: " + m_SoloEntries.Count() + " items in " + m_Catalog.Categories.Count() + " categories");
		else
			Print("[SoloShop] The shop is turned off on this server");
	}

	bool IsShopEnabled()
	{
		return m_Catalog.Enabled;
	}

	void SendShopState(PlayerBase player)
	{
		if (!player || !player.GetIdentity())
			return;
		Param2<bool, bool> state = new Param2<bool, bool>(m_Catalog.Enabled, m_Catalog.Enabled && m_Catalog.Cash.Count() > 0);
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_STATE, state, true, player.GetIdentity());
	}

	void ProcessShopRequest(PlayerBase player, PlayerIdentity sender, int rpcType, ParamsReadContext ctx)
	{
		if (!player || !sender || !player.GetIdentity() || sender.GetId() != player.GetIdentity().GetId())
			return;
		if (!m_Catalog.Enabled)
			return;

		if (rpcType == SOLO_SHOP_RPC_REQUEST_CATEGORIES)
		{
			SendShopCategories(player);
			return;
		}

		if (!CanShopHere(player))
		{
			SendShopResult(player, false, "Go to the trader to shop.");
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_REQUEST_ITEMS)
		{
			Param1<string> itemsRequest = new Param1<string>("");
			if (ctx.Read(itemsRequest))
				SendShopItems(player, itemsRequest.param1);
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_REQUEST_SELLABLES)
		{
			SendShopSellables(player);
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_CASH_OUT)
		{
			Param1<int> cashRequest = new Param1<int>(0);
			if (ctx.Read(cashRequest))
				CashOut(player, cashRequest.param1);
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_PAY_IN)
		{
			PayIn(player);
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_BUY)
		{
			Param2<string, int> buyRequest = new Param2<string, int>("", 1);
			if (ctx.Read(buyRequest))
				BuyShopItem(player, buyRequest.param1, buyRequest.param2);
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_SELL)
		{
			Param1<string> sellRequest = new Param1<string>("");
			if (ctx.Read(sellRequest))
				SellShopItem(player, sellRequest.param1);
		}
	}

	protected SoloShopBalanceEntry GetBalanceEntry(PlayerBase player)
	{
		return GetBalanceEntryByUid(player.GetIdentity().GetId());
	}

	protected SoloShopBalanceEntry GetBalanceEntryByUid(string uid)
	{
		foreach (SoloShopBalanceEntry existing : m_Balances.Players)
		{
			if (existing.Uid == uid)
				return existing;
		}

		SoloShopBalanceEntry created = new SoloShopBalanceEntry();
		created.Uid = uid;
		created.Balance = m_Catalog.StartingBalance;
		m_Balances.Players.Insert(created);
		SaveShopBalances();
		return created;
	}

	void AdminAdjustBalance(string uid, int amount, bool setExact)
	{
		SoloShopBalanceEntry balance = GetBalanceEntryByUid(uid);
		if (setExact)
			balance.Balance = amount;
		else
			balance.Balance = balance.Balance + amount;
		if (balance.Balance < 0)
			balance.Balance = 0;
		SaveShopBalances();
		Print("[SoloShop] Admin set balance of " + uid + " to " + balance.Balance);

		array<Man> onlinePlayers = new array<Man>;
		GetGame().GetPlayers(onlinePlayers);
		foreach (Man onlineMan : onlinePlayers)
		{
			PlayerBase online = PlayerBase.Cast(onlineMan);
			if (online && online.GetIdentity() && online.GetIdentity().GetId() == uid)
				SendShopResult(online, true, "An admin changed your balance to " + SoloShopText.Money(balance.Balance) + ".");
		}
	}

	protected void SaveShopBalances()
	{
		if (!FileExist("$profile:SoloShop"))
			MakeDirectory("$profile:SoloShop");
		string saveError;
		if (!JsonFileLoader<SoloShopBalanceFile>.SaveFile(SOLO_SHOP_BALANCES_PATH, m_Balances, saveError))
			Print("[SoloShop] " + saveError);
	}

	protected bool CanShopHere(PlayerBase player)
	{
		if (!m_Catalog.RequireTraderZone || m_Catalog.Zones.Count() == 0)
			return true;

		vector pos = player.GetPosition();
		foreach (SoloShopZone zone : m_Catalog.Zones)
		{
			float dx = pos[0] - zone.Position[0];
			float dz = pos[2] - zone.Position[2];
			if (dx * dx + dz * dz <= zone.Radius * zone.Radius)
				return true;
		}
		return false;
	}

	protected SoloShopEntry FindShopEntry(string className, out bool isVehicle)
	{
		isVehicle = false;
		SoloShopEntry entry;
		if (!m_SoloEntries.Find(className, entry))
			return null;
		m_SoloVehicleEntries.Find(className, isVehicle);
		return entry;
	}

	protected void SendShopResult(PlayerBase player, bool ok, string message, string className = "")
	{
		Param4<bool, string, int, string> result = new Param4<bool, string, int, string>(ok, message, GetBalanceEntry(player).Balance, className);
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_RESULT, result, true, player.GetIdentity());
	}

	protected void SendShopCategories(PlayerBase player)
	{
		array<string> names = new array<string>;
		if (CanShopHere(player))
		{
			foreach (SoloShopCategory category : m_Catalog.Categories)
				names.Insert(category.Name);
		}
		Param3<ref array<string>, int, string> categories = new Param3<ref array<string>, int, string>(names, GetBalanceEntry(player).Balance, m_Catalog.VehicleCategory);
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_CATEGORIES, categories, true, player.GetIdentity());
		if (!CanShopHere(player))
			SendShopResult(player, false, "Go to the trader to shop.");
	}

	protected void SendShopItems(PlayerBase player, string categoryName)
	{
		SoloShopCategoryList list;
		if (!m_SoloCategoryLists.Find(categoryName, list))
			list = new SoloShopCategoryList();
		Param4<string, ref array<string>, ref array<int>, ref array<int>> items = new Param4<string, ref array<string>, ref array<int>, ref array<int>>(categoryName, list.Classes, list.BuyPrices, list.SellPrices);
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_ITEMS, items, true, player.GetIdentity());
	}

	protected bool IsSellable(PlayerBase player, EntityAI item)
	{
		if (!item || item == player)
			return false;

		InventoryLocation location = new InventoryLocation();
		item.GetInventory().GetCurrentInventoryLocation(location);
		if (location.GetType() == InventoryLocationType.ATTACHMENT && location.GetParent() == player)
			return false;

		if (item.GetInventory().AttachmentCount() > 0)
			return false;
		CargoBase cargo = item.GetInventory().GetCargo();
		if (cargo && cargo.GetItemCount() > 0)
			return false;
		return true;
	}

	protected void SendShopSellables(PlayerBase player)
	{
		array<string> classes = new array<string>;
		array<int> prices = new array<int>;
		array<int> counts = new array<int>;
		array<EntityAI> carried = new array<EntityAI>;
		player.GetInventory().EnumerateInventory(InventoryTraversalType.PREORDER, carried);
		foreach (EntityAI item : carried)
		{
			if (!IsSellable(player, item))
				continue;
			bool isVehicle;
			SoloShopEntry entry = FindShopEntry(item.GetType(), isVehicle);
			if (!entry || entry.Sell <= 0)
				continue;
			int index = classes.Find(item.GetType());
			if (index < 0)
			{
				classes.Insert(item.GetType());
				prices.Insert(entry.Sell);
				counts.Insert(1);
			}
			else
			{
				counts.Set(index, counts.Get(index) + 1);
			}
		}
		Param3<ref array<string>, ref array<int>, ref array<int>> sellables = new Param3<ref array<string>, ref array<int>, ref array<int>>(classes, prices, counts);
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_SELLABLES, sellables, true, player.GetIdentity());
	}

	protected void BuyShopItem(PlayerBase player, string className, int amount)
	{
		bool isVehicle;
		SoloShopEntry entry = FindShopEntry(className, isVehicle);
		if (!entry || entry.Buy <= 0)
		{
			SendShopResult(player, false, "That item isn't for sale.");
			return;
		}

		if (amount < 1)
			amount = 1;
		if (amount > SOLO_SHOP_MAX_AMOUNT)
			amount = SOLO_SHOP_MAX_AMOUNT;
		if (isVehicle)
			amount = 1;

		SoloShopBalanceEntry balance = GetBalanceEntry(player);
		int total = entry.Buy * amount;
		if (balance.Balance < total)
		{
			SendShopResult(player, false, "Not enough money - you need " + SoloShopText.Money(total) + ".");
			return;
		}

		if (isVehicle)
		{
			if (!SpawnShopVehicle(player, entry))
			{
				SendShopResult(player, false, "Couldn't deliver the vehicle here - try somewhere more open.");
				return;
			}
		}
		else if (entry.PerPiece)
		{
			SpawnShopPieces(player, className, amount);
		}
		else
		{
			for (int i = 0; i < amount; i++)
				SpawnShopItem(player, className);
		}

		balance.Balance = balance.Balance - total;
		SaveShopBalances();
		Print("[SoloShop] Sold " + amount + "x " + className + " to " + player.GetIdentity().GetName() + " for " + total);
		SendShopResult(player, true, "Bought " + amount + "x %NAME% for " + SoloShopText.Money(total) + ".", className);
	}

	protected void SpawnShopItem(PlayerBase player, string className)
	{
		EntityAI item = player.GetInventory().CreateInInventory(className);
		if (!item)
			item = EntityAI.Cast(GetGame().CreateObjectEx(className, player.GetPosition(), ECE_PLACE_ON_SURFACE));
		if (!item)
			return;

		Magazine magazine = Magazine.Cast(item);
		if (magazine)
		{
			magazine.ServerSetAmmoCount(magazine.GetAmmoMax());
			return;
		}
		ItemBase itemBase = ItemBase.Cast(item);
		if (itemBase && itemBase.HasQuantity())
			itemBase.SetQuantity(itemBase.GetQuantityMax());
	}

	protected EntityAI CreateForPlayer(PlayerBase player, string className)
	{
		EntityAI item = player.GetInventory().CreateInInventory(className);
		if (!item)
			item = EntityAI.Cast(GetGame().CreateObjectEx(className, player.GetPosition(), ECE_PLACE_ON_SURFACE));
		return item;
	}

	protected int SpawnStacks(PlayerBase player, string className, int count, int maxStacks)
	{
		int stacksUsed = 0;
		return SpawnStacksCounted(player, className, count, maxStacks, stacksUsed);
	}

	// Creates up to count pieces in at most maxStacks stacks; returns how many pieces were really made.
	protected int SpawnStacksCounted(PlayerBase player, string className, int count, int maxStacks, out int stacks)
	{
		int made = 0;
		stacks = 0;
		while (made < count && stacks < maxStacks)
		{
			EntityAI item = CreateForPlayer(player, className);
			if (!item)
				break;
			stacks++;
			ItemBase stackable = ItemBase.Cast(item);
			int pieces = 1;
			if (stackable && stackable.HasQuantity() && stackable.GetQuantityMax() > 1)
			{
				pieces = Math.Min(count - made, stackable.GetQuantityMax());
				stackable.SetQuantity(pieces);
			}
			made = made + pieces;
		}
		return made;
	}

	protected void SpawnShopPieces(PlayerBase player, string className, int amount)
	{
		SpawnStacks(player, className, amount, amount);
	}

	protected int PieceCount(EntityAI item)
	{
		ItemBase stackable = ItemBase.Cast(item);
		if (stackable && stackable.HasQuantity() && stackable.GetQuantityMax() > 1)
			return Math.Max(0, Math.Round(stackable.GetQuantity()));
		return 1;
	}

	protected void CashOut(PlayerBase player, int amount)
	{
		if (m_Catalog.Cash.Count() == 0)
		{
			SendShopResult(player, false, "This trader doesn't hand out cash.");
			return;
		}
		SoloShopBalanceEntry balance = GetBalanceEntry(player);
		if (amount <= 0)
		{
			SendShopResult(player, false, "Type how much cash you want.");
			return;
		}
		if (amount > SOLO_SHOP_MAX_CASH_OUT)
			amount = SOLO_SHOP_MAX_CASH_OUT;
		if (amount > balance.Balance)
		{
			SendShopResult(player, false, "You only have " + SoloShopText.Money(balance.Balance) + ".");
			return;
		}

		int remaining = amount;
		int stacksLeft = SOLO_SHOP_MAX_CASH_STACKS;
		int paid = 0;
		foreach (SoloShopCashItem bill : m_Catalog.Cash)
		{
			if (bill.Value <= 0 || remaining < bill.Value || stacksLeft <= 0)
				continue;
			int wanted = remaining / bill.Value;
			int stacksUsed = 0;
			int made = SpawnStacksCounted(player, bill.ClassName, wanted, stacksLeft, stacksUsed);
			paid = paid + made * bill.Value;
			remaining = remaining - made * bill.Value;
			stacksLeft = stacksLeft - stacksUsed;
		}

		if (paid <= 0)
		{
			SendShopResult(player, false, "Couldn't make that amount in cash.");
			return;
		}
		balance.Balance = balance.Balance - paid;
		SaveShopBalances();
		Print("[SoloShop] Cash out " + paid + " to " + player.GetIdentity().GetName());
		string message = "Took out " + SoloShopText.Money(paid) + " in cash.";
		if (paid < amount)
			message = message + " The rest stays in your account (no smaller bills).";
		SendShopResult(player, true, message);
		SendShopSellables(player);
	}

	protected void PayIn(PlayerBase player)
	{
		map<string, int> values = new map<string, int>;
		foreach (SoloShopCashItem bill : m_Catalog.Cash)
		{
			string key = bill.ClassName;
			key.ToLower();
			values.Set(key, bill.Value);
		}

		array<EntityAI> carried = new array<EntityAI>;
		player.GetInventory().EnumerateInventory(InventoryTraversalType.PREORDER, carried);
		array<EntityAI> bills = new array<EntityAI>;
		int total = 0;
		foreach (EntityAI item : carried)
		{
			if (!item || item == player)
				continue;
			string type = item.GetType();
			type.ToLower();
			int value;
			if (!values.Find(type, value))
				continue;
			total = total + value * PieceCount(item);
			bills.Insert(item);
		}

		if (bills.Count() == 0)
		{
			SendShopResult(player, false, "You aren't carrying any cash.");
			return;
		}
		foreach (EntityAI paidBill : bills)
			GetGame().ObjectDelete(paidBill);

		SoloShopBalanceEntry balance = GetBalanceEntry(player);
		balance.Balance = balance.Balance + total;
		SaveShopBalances();
		Print("[SoloShop] Pay in " + total + " from " + player.GetIdentity().GetName());
		SendShopResult(player, true, "Paid in " + SoloShopText.Money(total) + " in cash.");
		SendShopSellables(player);
	}

	protected bool SpawnShopVehicle(PlayerBase player, SoloShopEntry entry)
	{
		vector direction = player.GetDirection();
		direction[1] = 0;
		direction.Normalize();
		vector spot = player.GetPosition() + direction * 8;
		spot[1] = GetGame().SurfaceY(spot[0], spot[2]);

		Object created = GetGame().CreateObjectEx(entry.ClassName, spot, ECE_PLACE_ON_SURFACE | ECE_CREATEPHYSICS | ECE_SETUP | ECE_UPDATEPATHGRAPH);
		EntityAI vehicle = EntityAI.Cast(created);
		if (!vehicle)
			return false;
		vehicle.SetOrientation(player.GetOrientation());

		foreach (string part : entry.Parts)
			vehicle.GetInventory().CreateAttachment(part);

		Car car = Car.Cast(vehicle);
		if (car)
		{
			car.Fill(CarFluid.FUEL, car.GetFluidCapacity(CarFluid.FUEL));
			car.Fill(CarFluid.OIL, car.GetFluidCapacity(CarFluid.OIL));
			car.Fill(CarFluid.COOLANT, car.GetFluidCapacity(CarFluid.COOLANT));
			car.Fill(CarFluid.BRAKE, car.GetFluidCapacity(CarFluid.BRAKE));
		}
		return true;
	}

	protected void SellShopItem(PlayerBase player, string className)
	{
		bool isVehicle;
		SoloShopEntry entry = FindShopEntry(className, isVehicle);
		if (!entry || entry.Sell <= 0)
		{
			SendShopResult(player, false, "The trader doesn't buy that.");
			return;
		}

		array<EntityAI> carried = new array<EntityAI>;
		player.GetInventory().EnumerateInventory(InventoryTraversalType.PREORDER, carried);
		EntityAI found;
		foreach (EntityAI item : carried)
		{
			if (item && item.GetType() == className && IsSellable(player, item))
			{
				found = item;
				break;
			}
		}
		if (!found)
		{
			SendShopResult(player, false, "Empty it or take its attachments off first - or you no longer have it.");
			SendShopSellables(player);
			return;
		}

		int price = entry.Sell;
		Magazine magazine = Magazine.Cast(found);
		ItemBase itemBase = ItemBase.Cast(found);
		if (entry.PerPiece)
		{
			price = entry.Sell * PieceCount(found);
		}
		else if (magazine && magazine.GetAmmoMax() > 0)
		{
			price = entry.Sell * magazine.GetAmmoCount() / magazine.GetAmmoMax();
		}
		else if (itemBase && itemBase.HasQuantity() && itemBase.GetQuantityMax() > 0)
		{
			float percent = 100 * itemBase.GetQuantity() / itemBase.GetQuantityMax();
			string percentText = Math.Round(percent).ToString();
			price = entry.Sell * percentText.ToInt() / 100;
		}

		GetGame().ObjectDelete(found);
		SoloShopBalanceEntry balance = GetBalanceEntry(player);
		balance.Balance = balance.Balance + price;
		SaveShopBalances();
		SendShopResult(player, true, "Sold %NAME% for " + SoloShopText.Money(price) + ".", className);
		SendShopSellables(player);
	}
}

modded class PlayerBase
{
	override void OnRPC(PlayerIdentity sender, int rpc_type, ParamsReadContext ctx)
	{
		super.OnRPC(sender, rpc_type, ctx);
		if (rpc_type < SOLO_SHOP_RPC_FIRST || rpc_type > SOLO_SHOP_RPC_LAST)
			return;

		if (GetGame().IsDedicatedServer())
		{
			SoloShopServer.GetShop().ProcessShopRequest(this, sender, rpc_type, ctx);
			return;
		}
		SoloShopReceive(rpc_type, ctx);
	}

	protected void SoloShopReceive(int rpcType, ParamsReadContext ctx)
	{
		if (rpcType == SOLO_SHOP_RPC_STATE)
		{
			Param2<bool, bool> stateData = new Param2<bool, bool>(false, false);
			if (ctx.Read(stateData))
			{
				SoloShopClientState.Enabled = stateData.param1;
				SoloShopClientState.CashEnabled = stateData.param2;
			}
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_CATEGORIES)
		{
			Param3<ref array<string>, int, string> categoriesData = new Param3<ref array<string>, int, string>(new array<string>, 0, "");
			if (!ctx.Read(categoriesData))
				return;
			SoloShopClientState.Categories.Copy(categoriesData.param1);
			SoloShopClientState.Balance = categoriesData.param2;
			SoloShopClientState.VehicleCategory = categoriesData.param3;
			SoloShopClientState.CategoriesVersion++;
			SoloShopClientState.StatusVersion++;
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_ITEMS)
		{
			Param4<string, ref array<string>, ref array<int>, ref array<int>> itemsData = new Param4<string, ref array<string>, ref array<int>, ref array<int>>("", new array<string>, new array<int>, new array<int>);
			if (!ctx.Read(itemsData))
				return;
			SoloShopClientState.ItemsCategory = itemsData.param1;
			SoloShopClientState.ItemClasses.Copy(itemsData.param2);
			SoloShopClientState.ItemBuy.Copy(itemsData.param3);
			SoloShopClientState.ItemSell.Copy(itemsData.param4);
			SoloShopClientState.ItemsVersion++;
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_SELLABLES)
		{
			Param3<ref array<string>, ref array<int>, ref array<int>> sellData = new Param3<ref array<string>, ref array<int>, ref array<int>>(new array<string>, new array<int>, new array<int>);
			if (!ctx.Read(sellData))
				return;
			SoloShopClientState.SellClasses.Copy(sellData.param1);
			SoloShopClientState.SellPrices.Copy(sellData.param2);
			SoloShopClientState.SellCounts.Copy(sellData.param3);
			SoloShopClientState.SellVersion++;
			return;
		}

		if (rpcType == SOLO_SHOP_RPC_RESULT)
		{
			Param4<bool, string, int, string> resultData = new Param4<bool, string, int, string>(false, "", 0, "");
			if (!ctx.Read(resultData))
				return;
			string message = resultData.param2;
			if (resultData.param4 != "")
				message.Replace("%NAME%", SoloShopText.DisplayName(resultData.param4));
			SoloShopClientState.MessageOk = resultData.param1;
			SoloShopClientState.Message = message;
			SoloShopClientState.Balance = resultData.param3;
			SoloShopClientState.StatusVersion++;
		}
	}
}
