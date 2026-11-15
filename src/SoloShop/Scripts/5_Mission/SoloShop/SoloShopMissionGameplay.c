modded class MissionGameplay
{
	protected ref SoloShopMenu m_SoloShopMenu;

	override void OnUpdate(float timeslice)
	{
		super.OnUpdate(timeslice);
		if (!SoloShopClientState.Enabled || !KeyState(KeyCode.KC_B))
			return;
		ClearKey(KeyCode.KC_B);

		if (GetGame().GetUIManager().GetMenu())
			return;
		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (!player || !player.IsAlive())
			return;

		if (!m_SoloShopMenu)
		{
			m_SoloShopMenu = new SoloShopMenu();
			m_SoloShopMenu.Init();
		}
		GetGame().GetUIManager().ShowScriptedMenu(m_SoloShopMenu, null);
	}
}
