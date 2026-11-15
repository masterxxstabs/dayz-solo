modded class MissionGameplay
{
	protected const float SOLO_MINIMAP_MIN_SCALE = 0.02;
	protected const float SOLO_MINIMAP_MAX_SCALE = 0.5;
	protected const float SOLO_MINIMAP_REFRESH = 0.1;

	protected Widget m_SoloMinimapRoot;
	protected MapWidget m_SoloMinimap;
	protected bool m_SoloMinimapVisible = true;
	protected float m_SoloMinimapScale = 0.08;
	protected float m_SoloMinimapTimer;

	override void OnInit()
	{
		super.OnInit();
		m_SoloMinimapRoot = GetGame().GetWorkspace().CreateWidgets("SoloMinimap/gui/layouts/minimap.layout");
		if (m_SoloMinimapRoot)
		{
			m_SoloMinimap = MapWidget.Cast(m_SoloMinimapRoot.FindAnyWidget("Minimap"));
			m_SoloMinimapRoot.Show(false);
		}
		if (!m_SoloMinimap)
			Print("[SoloMinimap] Couldn't create the minimap widget");
	}

	override void OnMissionFinish()
	{
		if (m_SoloMinimapRoot)
			m_SoloMinimapRoot.Unlink();
		m_SoloMinimapRoot = null;
		m_SoloMinimap = null;
		super.OnMissionFinish();
	}

	override void OnUpdate(float timeslice)
	{
		super.OnUpdate(timeslice);
		SoloMinimapUpdate(timeslice);
	}

	protected void SoloMinimapUpdate(float timeslice)
	{
		if (!m_SoloMinimapRoot || !m_SoloMinimap)
			return;
		if (!SoloMinimapMarkers.Enabled)
		{
			m_SoloMinimapRoot.Show(false);
			return;
		}

		bool inMenu = GetGame().GetUIManager().GetMenu() != null;
		if (!inMenu)
			SoloMinimapHandleKeys();

		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		bool show = m_SoloMinimapVisible && player && player.IsAlive() && !inMenu;
		m_SoloMinimapRoot.Show(show);
		if (!show)
			return;

		m_SoloMinimapTimer += timeslice;
		if (m_SoloMinimapTimer < SOLO_MINIMAP_REFRESH)
			return;
		m_SoloMinimapTimer = 0;

		vector position = player.GetPosition();
		m_SoloMinimap.SetScale(m_SoloMinimapScale);
		m_SoloMinimap.SetMapPos(position);
		m_SoloMinimap.ClearUserMarks();
		for (int i = 0; i < SoloMinimapMarkers.Names.Count(); i++)
			m_SoloMinimap.AddUserMark(SoloMinimapMarkers.Positions[i], SoloMinimapMarkers.Names[i], ARGB(255, 255, 196, 40), "");
		m_SoloMinimap.AddUserMark(position, "You", ARGB(255, 90, 220, 255), "");
	}

	protected void SoloMinimapHandleKeys()
	{
		if (KeyState(KeyCode.KC_N))
		{
			ClearKey(KeyCode.KC_N);
			m_SoloMinimapVisible = !m_SoloMinimapVisible;
		}
		if (KeyState(KeyCode.KC_ADD))
		{
			ClearKey(KeyCode.KC_ADD);
			m_SoloMinimapScale = Math.Max(SOLO_MINIMAP_MIN_SCALE, m_SoloMinimapScale * 0.7);
		}
		if (KeyState(KeyCode.KC_SUBTRACT))
		{
			ClearKey(KeyCode.KC_SUBTRACT);
			m_SoloMinimapScale = Math.Min(SOLO_MINIMAP_MAX_SCALE, m_SoloMinimapScale / 0.7);
		}
	}
}
