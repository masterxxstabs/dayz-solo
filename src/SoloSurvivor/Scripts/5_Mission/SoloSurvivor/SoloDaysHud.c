modded class MissionGameplay
{
	protected Widget m_SoloDaysRoot;
	protected TextWidget m_SoloDaysText;
	protected int m_SoloDaysShown = -1;

	override void OnInit()
	{
		super.OnInit();
		m_SoloDaysRoot = GetGame().GetWorkspace().CreateWidgets("SoloSurvivor/gui/layouts/days.layout");
		if (m_SoloDaysRoot)
		{
			m_SoloDaysText = TextWidget.Cast(m_SoloDaysRoot.FindAnyWidget("DayText"));
			m_SoloDaysRoot.Show(false);
		}
		if (!m_SoloDaysText)
			Print("[SoloSurvivor] Couldn't create the day counter");
	}

	override void OnMissionFinish()
	{
		if (m_SoloDaysRoot)
			m_SoloDaysRoot.Unlink();
		m_SoloDaysRoot = null;
		m_SoloDaysText = null;
		SoloDays.Show = false;
		super.OnMissionFinish();
	}

	override void OnUpdate(float timeslice)
	{
		super.OnUpdate(timeslice);
		SoloDaysUpdate();
	}

	protected void SoloDaysUpdate()
	{
		if (!m_SoloDaysRoot || !m_SoloDaysText)
			return;

		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		bool show = SoloDays.Show && player && player.IsAlive() && !GetGame().GetUIManager().GetMenu();
		m_SoloDaysRoot.Show(show);
		if (show && m_SoloDaysShown != SoloDays.Day)
		{
			m_SoloDaysText.SetText("Day " + SoloDays.Day.ToString());
			m_SoloDaysShown = SoloDays.Day;
		}
	}
}
