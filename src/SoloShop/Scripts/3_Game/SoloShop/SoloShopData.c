const int SOLO_SHOP_RPC_FIRST = 74631301;
const int SOLO_SHOP_RPC_REQUEST_CATEGORIES = 74631301;
const int SOLO_SHOP_RPC_CATEGORIES = 74631302;
const int SOLO_SHOP_RPC_REQUEST_ITEMS = 74631303;
const int SOLO_SHOP_RPC_ITEMS = 74631304;
const int SOLO_SHOP_RPC_REQUEST_SELLABLES = 74631305;
const int SOLO_SHOP_RPC_SELLABLES = 74631306;
const int SOLO_SHOP_RPC_BUY = 74631307;
const int SOLO_SHOP_RPC_SELL = 74631308;
const int SOLO_SHOP_RPC_RESULT = 74631309;
const int SOLO_SHOP_RPC_STATE = 74631310;
const int SOLO_SHOP_RPC_CASH_OUT = 74631311;
const int SOLO_SHOP_RPC_PAY_IN = 74631312;
const int SOLO_SHOP_RPC_LAST = 74631312;
const int SOLO_SHOP_MAX_CASH_OUT = 10000000;
const int SOLO_SHOP_MAX_CASH_STACKS = 40;

const string SOLO_SHOP_CATALOG_PATH = "$profile:SoloShop/catalog.json";
const string SOLO_SHOP_BALANCES_PATH = "$profile:SoloShop/balances.json";
const int SOLO_SHOP_MAX_AMOUNT = 20;

class SoloShopEntry
{
	string ClassName;
	int Buy;
	int Sell;
	bool Vehicle;
	bool PerPiece;
	ref array<string> Parts;

	void SoloShopEntry()
	{
		Parts = new array<string>;
	}
}

class SoloShopCategory
{
	string Name;
	bool IsVehicles;
	ref array<ref SoloShopEntry> Items;

	void SoloShopCategory()
	{
		Items = new array<ref SoloShopEntry>;
	}
}

class SoloShopCashItem
{
	string ClassName;
	int Value;
}

class SoloShopZone
{
	string Name;
	vector Position;
	float Radius;
}

class SoloShopCatalog
{
	bool Enabled;
	int StartingBalance;
	string VehicleCategory;
	bool RequireTraderZone;
	ref array<ref SoloShopZone> Zones;
	ref array<ref SoloShopCategory> Categories;
	ref array<ref SoloShopCashItem> Cash;

	void SoloShopCatalog()
	{
		Cash = new array<ref SoloShopCashItem>;
		Enabled = false;
		StartingBalance = 2000;
		VehicleCategory = "Vehicles";
		Zones = new array<ref SoloShopZone>;
		Categories = new array<ref SoloShopCategory>;
	}
}

class SoloShopClientState
{
	static bool Enabled;
	static bool CashEnabled;
	static string VehicleCategory = "Vehicles";
	static int CategoriesVersion;
	static int ItemsVersion;
	static int SellVersion;
	static int StatusVersion;
	static int Balance;
	static string Message;
	static bool MessageOk;
	static ref array<string> Categories = new array<string>;
	static string ItemsCategory;
	static ref array<string> ItemClasses = new array<string>;
	static ref array<int> ItemBuy = new array<int>;
	static ref array<int> ItemSell = new array<int>;
	static ref array<string> SellClasses = new array<string>;
	static ref array<int> SellPrices = new array<int>;
	static ref array<int> SellCounts = new array<int>;
}

class SoloShopText
{
	protected static ref map<string, string> s_SoloNames = new map<string, string>;

	static string DisplayName(string className)
	{
		string cached;
		if (s_SoloNames.Find(className, cached))
			return cached;
		string resolved = LookUpDisplayName(className);
		s_SoloNames.Insert(className, resolved);
		return resolved;
	}

	protected static string LookUpDisplayName(string className)
	{
		array<string> roots = {"CfgVehicles", "CfgWeapons", "CfgMagazines"};
		foreach (string root : roots)
		{
			string path = root + " " + className + " displayName";
			if (!GetGame().ConfigIsExisting(path))
				continue;
			string name;
			GetGame().ConfigGetText(path, name);
			if (name.IndexOf("$STR_") == 0)
				name = Widget.TranslateString("#" + name.Substring(1, name.Length() - 1));
			if (name != "")
				return name;
		}
		return className;
	}

	static string Money(int amount)
	{
		string digits = Math.AbsInt(amount).ToString();
		string grouped = "";
		int count = 0;
		for (int i = digits.Length() - 1; i >= 0; i--)
		{
			grouped = digits.Get(i) + grouped;
			count++;
			if (count % 3 == 0 && i > 0)
				grouped = "," + grouped;
		}
		if (amount < 0)
			grouped = "-" + grouped;
		return "$" + grouped;
	}
}
