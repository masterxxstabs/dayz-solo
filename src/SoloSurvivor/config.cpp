class CfgPatches
{
	class SoloSurvivor
	{
		units[] = {};
		weapons[] = {};
		requiredVersion = 0.1;
		requiredAddons[] = {"DZ_Data", "DZ_Scripts"};
	};
};

class CfgMods
{
	class DayZSolo
	{
		dir = "DayZSolo";
		name = "DayZ Solo";
		author = "DayZ Solo";
		version = "1.0.0";
		type = "mod";
		hideName = 0;
		hidePicture = 1;
		dependencies[] = {"Game", "World", "Mission"};

		class defs
		{
			class gameScriptModule
			{
				value = "";
				files[] = {"SoloSurvivor/Scripts/3_Game", "SoloShop/Scripts/3_Game", "SoloMinimap/Scripts/3_Game"};
			};
			class worldScriptModule
			{
				value = "";
				files[] = {"SoloSurvivor/Scripts/4_World", "SoloShop/Scripts/4_World", "SoloMinimap/Scripts/4_World"};
			};
			class missionScriptModule
			{
				value = "";
				files[] = {"SoloSurvivor/Scripts/5_Mission", "SoloShop/Scripts/5_Mission", "SoloMinimap/Scripts/5_Mission"};
			};
		};
	};
};
